#!/usr/bin/env python3
"""Hong Kong's MTR heavy-rail lines as the game's real-railway files
(decision 697).

    python3 -I tools/hk-map/build_hk_mtr.py hong_kong.pbf \\
        mtr_lines_and_stations.csv tools/hk-map/service.json \\
        RailwayGameApp/Resources/RealRailways

The station order and the Chinese and English names are MTR Corporation's
own (`mtr_lines_and_stations.csv`, DATA.GOV.HK); the tracks, the stopping
points and the bridges and tunnels are OpenStreetMap's (the whole extract,
read with pyosmium, never Overpass). The method is the reference website's
for Singapore (`world-rail-reference-clean/source/tools/build_singapore.mjs`:
the operator fixes the network, OSM's route relations give the geometry and
the ordered stops), and its `headway2sched.mjs` for the day's trips.

For each line one direction's route relation is read: its member ways
joined into a graph by their shared nodes, the cheapest path found between
each two stopping points that follow each other, and the paths joined into
the line's shape. A line's stops must be the CSV's stations in the CSV's
order, by name, or the tool stops.

`service.json` (made by `next_train_service.py` from samples of MTR's
next-train feed) holds each line's seconds between stations, its headways
and its first train; the day's trips are laid out from them and the file
says so (`estimated`).

Writes `hkmtr.json`, `hkmtr_times.json`, `track_lines.geojson`,
`track_stations.geojson`, `station_names.json`,
`rail_structures.json` into the folder, and `hk_sources.json` (what
it read, with checksums) beside this tool.
"""
import collections
import csv
import hashlib
import heapq
import json
import math
import os
import sys

import osmium

SYSTEM = "hkmtr"
# (game line id, CSV line code, CSV direction, Chinese name, English name,
# the stations kept: None for all, or the first kept station's English name
# for a branch, which is laid from where it leaves the main line as Taipei
# Metro's Xinbeitou Branch Line is).
LINES = [
    ("AEL", "AEL", "UT", "機場快綫", "Airport Express", None),
    ("TCL", "TCL", "UT", "東涌綫", "Tung Chung Line", None),
    ("TML", "TML", "UT", "屯馬綫", "Tuen Ma Line", None),
    ("EAL", "EAL", "UT", "東鐵綫", "East Rail Line", None),
    ("EAL_LMC", "EAL", "LMC-UT", "東鐵綫（落馬洲）", "East Rail Line (Lok Ma Chau)", "Sheung Shui"),
    ("TWL", "TWL", "UT", "荃灣綫", "Tsuen Wan Line", None),
    ("ISL", "ISL", "UT", "港島綫", "Island Line", None),
    ("KTL", "KTL", "UT", "觀塘綫", "Kwun Tong Line", None),
    ("TKL", "TKL", "UT", "將軍澳綫", "Tseung Kwan O Line", None),
    ("TKL_LHP", "TKL", "TKS-UT", "將軍澳綫（康城）", "Tseung Kwan O Line (LOHAS Park)", "Tseung Kwan O"),
    ("SIL", "SIL", "UT", "南港島綫", "South Island Line", None),
    ("DRL", "DRL", "UT", "迪士尼綫", "Disneyland Resort Line", None),
]
# MTR's line colours, as OpenStreetMap's relations carry them (`colour`);
# the tool checks the extract still agrees.
COLOURS = {
    "AEL": "#00888A", "TCL": "#F7943E", "TML": "#923011", "EAL": "#53B7E8", "TWL": "#ED1D24",
    "ISL": "#007DC5", "KTL": "#00AB4E", "TKL": "#7D499D", "SIL": "#B6BD00", "DRL": "#F173AC",
}
DWELL = 30


def metres(a, b):
    """Between two (lon, lat) points."""
    radius = 6371008.8
    dlon, dlat = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[1])) * math.cos(math.radians(b[1])) * math.sin(dlon / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(h))


def simplified(points, tolerance=1.0):
    """Douglas-Peucker, `tolerance` in metres."""
    if len(points) < 3:
        return points
    lat0 = math.radians(points[0][1])
    kx, ky = 111320.0 * math.cos(lat0), 111320.0
    flat = [(p[0] * kx, p[1] * ky) for p in points]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = flat[a]
        bx, by = flat[b]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy) or 1e-9
        worst, at = 0.0, None
        for i in range(a + 1, b):
            d = abs((flat[i][0] - ax) * dy - (flat[i][1] - ay) * dx) / length
            if d > worst:
                worst, at = d, i
        if at is not None and worst > tolerance:
            keep[at] = True
            stack += [(a, at), (at, b)]
    return [p for p, k in zip(points, keep) if k]


class Relations(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.found = []
        self.ways = set()
        self.nodes = set()

    def relation(self, r):
        tags = dict(r.tags)
        if tags.get("type") == "route" and tags.get("route") == "subway" and tags.get("ref") in COLOURS \
                and "MTR" in tags.get("operator", ""):
            members = [(m.type, m.ref, m.role) for m in r.members]
            self.found.append({"id": r.id, "tags": tags, "members": members})
            self.ways |= {ref for kind, ref, _ in members if kind == "w"}
            self.nodes |= {ref for kind, ref, _ in members if kind == "n"}


class Parts(osmium.SimpleHandler):
    def __init__(self, ways, nodes):
        super().__init__()
        self.want_ways, self.want_nodes = ways, nodes
        self.ways, self.nodes = {}, {}
        self.newest = ""

    def way(self, w):
        if w.id in self.want_ways:
            self.ways[w.id] = {"tags": dict(w.tags), "nodes": [(n.ref, n.lon, n.lat) for n in w.nodes]}
            self.newest = max(self.newest, w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"))

    def node(self, n):
        if n.id in self.want_nodes:
            self.nodes[n.id] = {"tags": dict(n.tags), "at": (n.location.lon, n.location.lat)}


def cheapest(graph, a, b):
    best, back, heap = {a: 0.0}, {}, [(0.0, a)]
    while heap:
        d, u = heapq.heappop(heap)
        if u == b:
            break
        if d > best[u]:
            continue
        for v, w in graph[u]:
            if d + w < best.get(v, math.inf):
                best[v] = d + w
                back[v] = u
                heapq.heappush(heap, (d + w, v))
    if b not in best:
        return None
    path = [b]
    while path[-1] != a:
        path.append(back[path[-1]])
    return path[::-1]


def english(node):
    tags = node["tags"]
    name = tags.get("name:en") or tags.get("name", "")
    # A stopping point named in both languages ("荃灣 Tsuen Wan").
    return name.split(" ", 1)[1] if name[:1] > "⹿" and " " in name else name


# Where MTR writes a station's name with another form of a character than
# OpenStreetMap does, the game shows MTR's (the name on the station).
MTR_SPELLING = {"荔景": "茘景", "荔枝角": "茘枝角"}


def chinese_name(node):
    tags = node["tags"]
    name = (tags.get("name:zh") or tags.get("name", "")).split(" ", 1)[0]
    return MTR_SPELLING.get(name, name)


def line_of(spec, rows, relations, parts):
    line_id, code, direction, chinese, english_name, first_kept = spec
    wanted = [r for r in rows if r["Line Code"] == code and r["Direction"] == direction]
    if first_kept:
        wanted = wanted[[r["English Name"] for r in wanted].index(first_kept):]
    names = [r["English Name"] for r in wanted]
    # The relation that stops at exactly these stations, else the shortest
    # that stops at them in a row (a branch's trains start further back).
    chosen = None
    for relation in sorted(relations, key=lambda r: (len(r["members"]), r["id"])):
        if relation["tags"]["ref"] != code:
            continue
        stops = [ref for kind, ref, role in relation["members"] if kind == "n" and role.startswith("stop") and ref in parts.nodes]
        called = [english(parts.nodes[s]) for s in stops]
        for start in range(len(called) - len(names) + 1):
            if called[start:start + len(names)] == names:
                chosen = (relation, stops[start:start + len(names)])
                break
        if chosen:
            break
    if chosen is None:
        sys.exit(f"{line_id}: no OpenStreetMap route relation stops at the CSV's stations in its order: {names}")
    relation, stops = chosen
    # The names the game shows are OpenStreetMap's; MTR's list only checks
    # them, so the pack stands without it.
    for stop, row in zip(stops, wanted):
        if chinese_name(parts.nodes[stop]) != row["Chinese Name"]:
            sys.exit(f"{line_id}: OpenStreetMap calls {row['Chinese Name']} ({row['English Name']}) "
                     f"{chinese_name(parts.nodes[stop])}")
    if relation["tags"].get("colour", "").upper() != COLOURS[code]:
        sys.exit(f"{line_id}: OpenStreetMap's colour is now {relation['tags'].get('colour')}, not {COLOURS[code]}")
    graph, at, way_of = collections.defaultdict(list), {}, {}
    for kind, ref, role in relation["members"]:
        if kind != "w" or role.startswith("platform") or ref not in parts.ways:
            continue
        nodes = parts.ways[ref]["nodes"]
        for a, b in zip(nodes, nodes[1:]):
            at[a[0]], at[b[0]] = (a[1], a[2]), (b[1], b[2])
            d = metres(at[a[0]], at[b[0]])
            graph[a[0]].append((b[0], d))
            graph[b[0]].append((a[0], d))
            way_of[(a[0], b[0])] = way_of[(b[0], a[0])] = ref
    shape, stations, structures = [], [], []
    for i, stop in enumerate(stops):
        if i:
            path = cheapest(graph, stops[i - 1], stop)
            if path is None:
                sys.exit(f"{line_id}: no track from {wanted[i - 1]['English Name']} to {wanted[i]['English Name']}")
            piece = simplified([at[n] for n in path])
            shape += piece[1:]
            # The bridges and tunnels along the way, one stretch a way.
            run = []
            for a, b in zip(path, path[1:]):
                way = way_of[(a, b)]
                if run and run[0] == way:
                    run[1].append(at[b])
                else:
                    run = [way, [at[a], at[b]]]
                    structures.append(run)
        else:
            shape.append(at[stop])
        stations.append({"row": wanted[i], "stop": stop, "at": at[stop], "vertex": len(shape) - 1})
    along = [0.0]
    for a, b in zip(shape, shape[1:]):
        along.append(along[-1] + metres(a, b))
    kept = []
    for way, points in structures:
        tags = parts.ways[way]["tags"]
        kind = "tunnel" if tags.get("tunnel") not in (None, "no") else "bridge" if tags.get("bridge") not in (None, "no") else None
        if kind:
            kept.append({"way": way, "system": SYSTEM, "kind": kind,
                         "points": [[round(x, 6), round(y, 6)] for x, y in simplified(points)]})
    return {
        "id": line_id, "code": code, "chinese": chinese, "english": english_name, "colour": COLOURS[code],
        "relation": relation["id"],
        "stations": [{"name": chinese_name(parts.nodes[s["stop"]]), "english": english(parts.nodes[s["stop"]]),
                      "code": s["row"]["Station Code"],
                      "lon": round(s["at"][0], 6), "lat": round(s["at"][1], 6), "d": round(along[s["vertex"]] / 1000, 4)}
                     for s in stations],
        "shape": [[round(x, 6), round(y, 6)] for x, y in shape],
        "structures": kept,
    }


def trips(line, service):
    """The day's trips both ways from the headways (the reference's
    `headway2sched.mjs`): each a list of station index and the second of
    the day it leaves (the last, arrives)."""
    runs = service["runSec"]
    count = len(line["stations"])
    if len(runs) != count - 1:
        sys.exit(f"{line['id']}: service.json has {len(runs)} runs for {count} stations")
    first, last = service["firstTrainSec"], service["lastTrainSec"]
    peaks = service["peaks"]
    out = []
    for order in (list(range(count)), list(range(count - 1, -1, -1))):
        leave = first
        while leave <= last:
            t, trip = leave, []
            for n, index in enumerate(order):
                if n:
                    t += runs[min(index, order[n - 1])]
                trip += [index, t]
            out.append(trip)
            peak = any(a <= leave < b for a, b in peaks)
            leave += service["peakHeadwaySec"] if peak else service["offpeakHeadwaySec"]
    return out


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def write(folder, name, value):
    with open(os.path.join(folder, name), "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


# Where each part of each file of the pack comes from (`pack.json`), so the
# parts that are MTR's can be told from OpenStreetMap's and taken out
# without making the rest again.
OSM, MTR, OURS, WORLDPOP = "OpenStreetMap", "MTR open data", "this project", "WorldPop"
# Decision 726: the ground's heights.
LANDSD = "Lands Department DTM"
# Decision 729: the Lands Department's buildings (outlines and heights).
LANDSD_BUILDINGS = "Lands Department Building"
# Decision 712: how far Hong Kong's map reaches, in degrees: the box of
# WorldPop's grid of Hong Kong (`build_hk_ground.py`), which holds all its
# land and every line here, some 62 km by 45 km. The game lays the city's
# world over this box (`MapPack.extent`), not over a 16 km square.
EXTENT = {"north": 22.5584, "south": 22.1500, "west": 113.8333, "east": 114.4417}
SOURCES = {
    "buildings.pmtiles": {"outlines and heights (build_hk_buildings.py)": LANDSD_BUILDINGS,
                          "uses, storeys of the few unmeasured towers where tagged": OSM,
                          "storeys where not measured (from the measured ones and the people round them)": OURS},
    "basemap.pmtiles": {"roads, water, land cover, parks, boundaries, place names (build_hk_basemap.py)": OSM,
                        "the mainland's shore closed past the extract": OURS},
    "population.json": {"runs (people per 30 arc-second cell, rounded)": WORLDPOP},
    # Decision 726 (build_hk_ground_grids.py).
    "heights.dat": {"heights (the mean of the model's 5 m samples in each 1.875 arc-second cell)": LANDSD,
                    "where the sea and the shore are": OSM, "water's surface and the sea at 0": OURS},
    "water.json": {"water (coastline, bodies of water)": OSM, "the mainland's shore closed past the extract": OURS,
                   "steep (slopes over 30 %)": LANDSD},
    "terrain.pmtiles": {"heights (heights.dat, Terrarium-encoded)": LANDSD},
    "track_lines.geojson": {"geometry": OSM, "color": OSM, "id (MTR's line code)": MTR, "name": OURS},
    "track_stations.geojson": {"geometry": OSM, "name (checked against MTR's list)": OSM, "name of 茘景 and 茘枝角 (MTR's form of 荔)": MTR, "color": OSM,
                               "code (MTR's station code)": MTR},
    "station_names.json": {"en (checked against MTR's list)": OSM, "routes": OURS},
    "rail_structures.json": {"structures": OSM},
    "hkmtr.json": {"stations (order checked against MTR's list)": OSM, "shape": OSM, "color": OSM,
                   "segs.run, peakHeadwaySec, offpeakHeadwaySec (sampled from MTR's next-train feed)": MTR,
                   "dwellSec": OURS},
    "hkmtr_times.json": {"sets (laid out from headways and running times sampled from MTR's next-train feed)": MTR},
    "metro_runs.json": {"runs (hkmtr_times.json's trips)": MTR, "overnight, tracks, positioning runs": OURS},
}


def write_manifest(folder):
    """`pack.json`: what the pack is and, for each file in it, its size and
    where its parts come from."""
    files = {name: {"bytes": os.path.getsize(os.path.join(folder, name)), "sources": SOURCES[name]}
             for name in sorted(SOURCES) if os.path.exists(os.path.join(folder, name))}
    licences = {
        OSM: "© OpenStreetMap contributors, ODbL 1.0",
        MTR: "MTR Corporation Limited, DATA.GOV.HK Terms and Conditions of Use",
    }
    if "population.json" in files:
        licences[WORLDPOP] = "WorldPop (www.worldpop.org), CC BY 4.0"
    if "heights.dat" in files:
        licences[LANDSD] = ("Digital Terrain Model, Lands Department, Government of the Hong Kong SAR, via the CSDI Portal; "
                            "CSDI Portal Terms and Conditions of Use")
    if "buildings.pmtiles" in files:
        licences[LANDSD_BUILDINGS] = ("Building, Lands Department, Government of the Hong Kong SAR, via the CSDI Portal; "
                                      "CSDI Portal Terms and Conditions of Use")
    write(folder, "pack.json", {
        "id": "hongkong", "system": SYSTEM, "decision": 697,
        "english": "Hong Kong", "chinese": "香港",
        "_readme": "Hong Kong's map pack: MTR's ten heavy-rail lines in the formats and under the file names of "
                   "Taiwan's real railways, read from this folder alone. Made by tools/hk-map (README.md there).",
        "bytes": sum(f["bytes"] for f in files.values()),
        "extent": EXTENT,
        "licences": licences,
        "files": files,
    })


def main(extract, stations_csv, service_json, out):
    with open(stations_csv, encoding="utf-8-sig") as f:
        rows = [r for r in csv.DictReader(f) if r["Line Code"]]
    with open(service_json, encoding="utf-8") as f:
        service = json.load(f)
    relations = Relations()
    relations.apply_file(extract)
    parts = Parts(relations.ways, relations.nodes)
    parts.apply_file(extract, locations=True)
    lines = [line_of(spec, rows, relations.found, parts) for spec in LINES]

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/hk-map/build_hk_mtr.py"}
    mtr = ("Station names and order: OpenStreetMap, checked against MTR Corporation Limited, MTR routes, fares and barrier-free facilities "
           "(mtr_lines_and_stations.csv), DATA.GOV.HK. Times between stations, headways and first trains: "
           "sampled from MTR Corporation Limited's Real-time MTR train information, DATA.GOV.HK ("
           + service["sampled"] + "). Tracks and stopping points: © OpenStreetMap contributors, ODbL 1.0.")

    write(out, "hkmtr.json", {
        "system": "HKMTR", "source_notes": mtr,
        "lines": [{
            "id": line["id"], "name": line["chinese"], "color": line["colour"],
            "peakHeadwaySec": service["lines"][line["id"]]["peakHeadwaySec"],
            "offpeakHeadwaySec": service["lines"][line["id"]]["offpeakHeadwaySec"],
            "headway_estimated": True,
            "stations": [{"name": s["name"], "lat": s["lat"], "lon": s["lon"], "d": s["d"]} for s in line["stations"]],
            "shape": [[y, x] for x, y in line["shape"]],
            "segs": [{"run": max(run - DWELL, 20)} for run in service["lines"][line["id"]]["runSec"]],
            "dwellSec": [DWELL] * len(line["stations"]),
        } for line in lines],
    })
    write(out, "hkmtr_times.json", {
        "system": "HKMTR", "estimated": True,
        "source_notes": "No published timetable: each day's trips are laid out from the headways and the times "
                        "between stations sampled from MTR Corporation Limited's Real-time MTR train information, "
                        "DATA.GOV.HK (" + service["sampled"] + "); not the operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日",
                               "sets": {"每日": trips(line, service["lines"][line["id"]])}} for line in lines},
    })
    write(out, "track_lines.geojson", {
        "type": "FeatureCollection", "source": mtr, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "id": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": line["chinese"], "color": line["colour"], "sortKey": n, "kind": "track"},
                      "geometry": {"type": "LineString", "coordinates": line["shape"]}}
                     for n, line in enumerate(lines)],
    })
    write(out, "track_stations.geojson", {
        "type": "FeatureCollection", "source": mtr, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "lineId": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": s["name"], "code": s["code"], "color": line["colour"]},
                      "geometry": {"type": "Point", "coordinates": [s["lon"], s["lat"]]}}
                     for line in lines for s in line["stations"]],
    })
    names = {}
    for line in lines:
        for s in line["stations"]:
            if names.setdefault(s["name"], s["english"]) != s["english"]:
                sys.exit(f"{s['name']} has two English names")
    write(out, "station_names.json", {
        "source": mtr,
        "systems": {SYSTEM: {name: {"en": en} for name, en in sorted(names.items())}},
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"]} for line in lines}},
    })
    write(out, "rail_structures.json", {
        "_readme": "Where the MTR lines of track_lines.geojson are on bridges and viaducts (bridge) or in "
                   "tunnels (tunnel), one OpenStreetMap way of the traced direction each. Made by "
                   "tools/hk-map/build_hk_mtr.py.",
        "source": {"openStreetMap": osm},
        "structures": [s for line in lines for s in line["structures"]],
    })
    write(os.path.dirname(os.path.abspath(__file__)), "hk_sources.json", {
        "decision": 697,
        "inputs": {
            os.path.basename(extract): {"sha256": sha256(extract), "from": "https://osmtoday.com/asia/china/hong_kong.pbf",
                                        "licence": "ODbL 1.0, © OpenStreetMap contributors"},
            os.path.basename(stations_csv): {"sha256": sha256(stations_csv),
                                             "from": "https://opendata.mtr.com.hk/data/mtr_lines_and_stations.csv",
                                             "licence": "DATA.GOV.HK Terms and Conditions of Use; MTR Corporation Limited"},
            "service.json": {"sha256": sha256(service_json), "from": "tools/hk-map/next_train_service.py",
                             "sampled": service["sampled"],
                             "licence": "DATA.GOV.HK Terms and Conditions of Use; MTR Corporation Limited"},
        },
        "lines": [{"id": line["id"], "osmRelation": line["relation"], "stations": len(line["stations"]),
                   "km": line["stations"][-1]["d"]} for line in lines],
    })
    write_manifest(out)
    for line in lines:
        print(f"{line['id']:8} {len(line['stations']):2} stations {line['stations'][-1]['d']:6.2f} km "
              f"{len(line['shape']):4} points {len(line['structures']):3} structures  relation {line['relation']}")


if __name__ == "__main__":
    main(*sys.argv[1:])
