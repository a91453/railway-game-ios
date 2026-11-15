#!/usr/bin/env python3
"""The railways of the Rovaniemi map as the game's real-railway files
(decision 789), in the formats and under the file names of Hong Kong's
pack (`tools/hk-map/build_hk_mtr.py`, decision 697).

    python3 -I tools/rovaniemi-map/build_rovaniemi_rail.py rovaniemi.pbf \\
        tools/rovaniemi-map/digitraffic_trains.json \\
        RailwayGameApp/Resources/MapPacks/rovaniemi

Two lines out of Rovaniemi, every station of each on the map:

- `KJA`, the Kemijärvi line: Rovaniemi, Misi, Kemijärvi (the branch north
  east, electrified in 2014; the trains a player can buy are its real
  ones: the night train's end from Helsinki and back, and the few day
  trains the timetable has).
- `MUL`, the main line south as far as Muurola, the last passenger
  station on the map; past it the line runs on to Oulu and Helsinki, off
  the map. Its trains are the intercity, Pendolino and night trains, cut
  to the map: from Muurola (where they come in) to Rovaniemi and back.

The tracks are OpenStreetMap's (the whole Finland extract cut to the map
with `osmium extract`, read with pyosmium, never Overpass): the route
relation `Laurila–Kemijärvi` (`RELATION`), its member ways joined into a
graph by their shared nodes, the cheapest path found between each two
stations that follow each other. A station is OpenStreetMap's
`railway=station` node of its Digitraffic short code (`railway:ref`),
checked to lie within 300 m of Digitraffic's own point, and put on the
nearest node of the line's track.

The times are Fintraffic's (Digitraffic, CC BY 4.0, `fetch_digitraffic.py`
saved them in `digitraffic_trains.json`): every passenger train of each
day of the fetched week, at its scheduled times, in Finnish time
(UTC+2 in the winter: `UTC_OFFSET`). A trip is laid on the local day of
its first time on the map (a night train from Helsinki, listed on the day
it left, reaches Rovaniemi the next morning). A train that passes Misi
without stopping passes it (`kinds` "2", decision 605's passing trips);
one that runs through Muurola without stopping calls there, the end of
the line on the map. Seconds between stations and the dwell at Misi are
the medians of the trains that stop at both.

Writes `vr.json`, `vr_times.json`, `track_lines.geojson`,
`track_stations.geojson`, `station_names.json`, `rail_structures.json`
and `pack.json` into the folder, and `rovaniemi_sources.json` (what it
read, with checksums) beside this tool.
"""
import collections
import datetime
import hashlib
import heapq
import json
import math
import os
import statistics
import sys

import osmium

SYSTEM = "vr"
# Digitraffic short code: (Chinese name, English name).
STATIONS = {
    "ROI": ("羅瓦涅米", "Rovaniemi"),
    "MUL": ("穆羅拉", "Muurola"),
    "MIS": ("米西", "Misi"),
    "KJÄ": ("凱米耶爾維", "Kemijärvi"),
}
# (game line id, stations in order, Chinese name, English name, colour).
# The colours are this project's (OpenStreetMap's relation has none):
# VR's green for the branch, a darker one for the main line.
LINES = [
    ("KJA", ["ROI", "MIS", "KJÄ"], "凱米耶爾維線", "Kemijärvi Line", "#3FA535"),
    ("MUL", ["ROI", "MUL"], "羅瓦涅米—穆羅拉", "Rovaniemi–Muurola", "#1E6B3A"),
]
RELATION = 375226
# Finland's winter time, the timetable's weeks being in December.
UTC_OFFSET = 2 * 3600
DAY = 86400
WEEKDAYS = ["週日", "週一", "週二", "週三", "週四", "週五", "週六"]
# Decision 789: how far the Rovaniemi map reaches, in degrees: Muurola in
# the south west to Kemijärvi in the east, the city, the airport and the
# Santa Claus village between (docs/research/WINTER_EVENT_2026-11-15.md
# §3.1), some 107 km by 55 km.
EXTENT = {"north": 66.80, "south": 66.30, "west": 25.20, "east": 27.60}


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


class Relation(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = None
        self.tags = None

    def relation(self, r):
        if r.id == RELATION:
            self.tags = dict(r.tags)
            self.ways = [m.ref for m in r.members if m.type == "w"]


class Parts(osmium.SimpleHandler):
    def __init__(self, ways):
        super().__init__()
        self.want = set(ways)
        self.ways, self.stations = {}, {}
        self.newest = ""

    def way(self, w):
        if w.id in self.want:
            self.ways[w.id] = {"tags": dict(w.tags), "nodes": [(n.ref, n.lon, n.lat) for n in w.nodes]}
            self.newest = max(self.newest, w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"))

    def node(self, n):
        tags = dict(n.tags)
        if tags.get("railway") == "station":
            code = tags.get("railway:ref", "").upper()
            if code in STATIONS:
                self.stations[code] = {"id": n.id, "name": tags.get("name"), "at": (n.location.lon, n.location.lat)}


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


def track(parts):
    graph, at, way_of = collections.defaultdict(list), {}, {}
    for ref, way in parts.ways.items():
        nodes = way["nodes"]
        for a, b in zip(nodes, nodes[1:]):
            at[a[0]], at[b[0]] = (a[1], a[2]), (b[1], b[2])
            d = metres(at[a[0]], at[b[0]])
            graph[a[0]].append((b[0], d))
            graph[b[0]].append((a[0], d))
            way_of[(a[0], b[0])] = way_of[(b[0], a[0])] = ref
    return graph, at, way_of


def line_of(spec, parts, graph, at, way_of, digitraffic):
    line_id, codes, chinese, english, colour = spec
    stops = []
    for code in codes:
        station = parts.stations.get(code)
        if station is None:
            sys.exit(f"{line_id}: OpenStreetMap has no railway=station with railway:ref {code}")
        dt = digitraffic["stations"][code]
        off = metres(station["at"], (dt["lon"], dt["lat"]))
        if off > 300:
            sys.exit(f"{code}: OpenStreetMap's station is {off:.0f} m from Digitraffic's")
        node = min(at, key=lambda n: metres(at[n], station["at"]))
        if metres(at[node], station["at"]) > 100:
            sys.exit(f"{code}: the track passes {metres(at[node], station['at']):.0f} m from the station")
        stops.append(node)
    shape, structures, vertices = [at[stops[0]]], [], [0]
    for a, b in zip(stops, stops[1:]):
        path = cheapest(graph, a, b)
        if path is None:
            sys.exit(f"{line_id}: no track between two of {codes}")
        shape += simplified([at[n] for n in path])[1:]
        vertices.append(len(shape) - 1)
        run = []
        for p, q in zip(path, path[1:]):
            way = way_of[(p, q)]
            if run and run[0] == way:
                run[1].append(at[q])
            else:
                run = [way, [at[p], at[q]]]
                structures.append(run)
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
    for code, vertex in zip(codes, vertices):
        if not all(EXTENT["south"] <= y <= EXTENT["north"] and EXTENT["west"] <= x <= EXTENT["east"] for x, y in [shape[vertex]]):
            sys.exit(f"{code} is off the map")
    return {
        "id": line_id, "codes": codes, "chinese": chinese, "english": english, "colour": colour,
        "stations": [{"code": code, "name": STATIONS[code][0], "english": STATIONS[code][1],
                      "lon": round(shape[v][0], 6), "lat": round(shape[v][1], 6), "d": round(along[v] / 1000, 4)}
                     for code, v in zip(codes, vertices)],
        "shape": [[round(x, 6), round(y, 6)] for x, y in shape],
        "structures": kept,
    }


def local(time):
    """A Digitraffic UTC time as (local date, second of that day)."""
    moment = datetime.datetime.strptime(time, "%Y-%m-%dT%H:%M:%S.%fZ") + datetime.timedelta(seconds=UTC_OFFSET)
    return moment.date(), moment.hour * 3600 + moment.minute * 60 + moment.second


def trips_of(line, digitraffic, week):
    """Each local day's trips on `line`: the train, its calls (station
    index, second: the time it leaves, the last the time it arrives),
    and whether it passes a station between (`kinds` "2"); with the
    seconds each train that stops at two neighbours takes between them
    and stands at each station between."""
    codes = line["codes"]
    days = collections.defaultdict(list)
    runs, dwells = collections.defaultdict(list), collections.defaultdict(list)
    seen = set()
    for listed in sorted(digitraffic["days"]):
        for train in digitraffic["days"][listed]:
            rows = [r for r in train["rows"] if r["station"] in codes]
            here = {c for c in (r["station"] for r in rows)}
            if len(here) < 2:
                continue
            first = rows[0]["station"]
            order = codes if codes.index(first) == 0 else codes[::-1]
            if order[0] not in here or order[-1] not in here:
                # A train that starts or ends between the line's ends
                # (none in the fetched weeks).
                sys.exit(f"{line['id']}: {train['type']} {train['number']} does not run the whole line: {sorted(here)}")
            date, _ = local(rows[0]["time"])
            key = (train["type"], train["number"], date)
            if key in seen:
                continue
            seen.add(key)
            calls, passes, start = [], False, None
            for n, code in enumerate(order):
                at = {r["type"]: r for r in rows if r["station"] == code}
                last = n == len(order) - 1
                row = at.get("ARRIVAL") if last else at.get("DEPARTURE")
                if row is None:
                    sys.exit(f"{line['id']}: {train['type']} {train['number']} has no time at {code}")
                if 0 < n < len(order) - 1 and not row["stops"]:
                    passes = True
                    continue
                day, second = local(row["time"])
                if start is None:
                    start = day
                second += (day - start).days * DAY
                calls.append((codes.index(code), second))
            for (a, ta), (b, tb) in zip(calls, calls[1:]):
                if tb <= ta:
                    sys.exit(f"{line['id']}: {train['type']} {train['number']} goes back in time")
            # The seconds between neighbours that both stop, from the
            # departure at one to the arrival at the next.
            for p, q in zip(order, order[1:]):
                dep = next((r for r in rows if r["station"] == p and r["type"] == "DEPARTURE"), None)
                arr = next((r for r in rows if r["station"] == q and r["type"] == "ARRIVAL"), None)
                if dep and arr and dep["stops"] and arr["stops"]:
                    da, sa = local(dep["time"])
                    db, sb = local(arr["time"])
                    runs[min(codes.index(p), codes.index(q))].append(sb - sa + (db - da).days * DAY)
            for code in order[1:-1]:
                arr = next((r for r in rows if r["station"] == code and r["type"] == "ARRIVAL"), None)
                dep = next((r for r in rows if r["station"] == code and r["type"] == "DEPARTURE"), None)
                if arr and dep and arr["stops"]:
                    dwells[codes.index(code)].append(local(dep["time"])[1] - local(arr["time"])[1])
            if start in week:
                days[start].append({"train": f"{train['type']} {train['number']}", "calls": calls, "passes": passes})
    for day in days:
        days[day].sort(key=lambda t: t["calls"][0][1])
    return days, runs, dwells


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def write(folder, name, value):
    with open(os.path.join(folder, name), "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


OSM, FINTRAFFIC, OURS, WORLDPOP = "OpenStreetMap", "Fintraffic / Digitraffic", "this project", "WorldPop"
COPERNICUS = "Copernicus DEM GLO-30"
SOURCES = {
    "population.json": {"runs (people per 30 arc-second cell, rounded)": WORLDPOP},
    "basemap.pmtiles": {"roads, water, land cover, parks, boundaries, place names (build_rovaniemi_basemap.py)": OSM,
                        "land as far as the extract reaches (no coast)": OURS},
    "airfields.json": {"runways, taxiways, aprons, stands, control tower (tools/airfields/build_airfields.py)": OSM},
    "no_build.json": {"the airport, military land, cemeteries, golf courses, railway land and the airport's buildings "
                      "(tools/no-build-land/build_no_build.py)": OSM},
    # build_rovaniemi_ground_grids.py.
    "heights.dat": {"heights (the model at each 1.875 arc-second cell's middle)": COPERNICUS},
    "water.json": {"water (rivers and lakes)": OSM, "steep (slopes over 30 %)": COPERNICUS},
    "terrain.pmtiles": {"heights (heights.dat, Terrarium-encoded)": COPERNICUS},
    "track_lines.geojson": {"geometry": OSM, "id, name, color": OURS},
    "track_stations.geojson": {"geometry": OSM, "code (Digitraffic's station short code)": FINTRAFFIC,
                               "name (Chinese)": OURS, "color": OURS},
    "station_names.json": {"en (Digitraffic's station name)": FINTRAFFIC, "routes": OURS},
    "rail_structures.json": {"structures": OSM},
    "vr.json": {"stations, shape": OSM, "segs.run, dwellSec (medians of the scheduled times)": FINTRAFFIC},
    "vr_times.json": {"sets (the scheduled times of each train of the week)": FINTRAFFIC},
    "metro_runs.json": {"runs (vr_times.json's trips)": FINTRAFFIC, "overnight, tracks, positioning runs": OURS},
}


def write_manifest(folder):
    """`pack.json`: what the pack is and, for each file in it, its size and
    where its parts come from."""
    files = {name: {"bytes": os.path.getsize(os.path.join(folder, name)), "sources": SOURCES[name]}
             for name in sorted(SOURCES) if os.path.exists(os.path.join(folder, name))}
    licences = {
        OSM: "© OpenStreetMap contributors, ODbL 1.0",
        FINTRAFFIC: "Source: Fintraffic / digitraffic.fi, licence CC 4.0 BY",
    }
    if "population.json" in files:
        licences[WORLDPOP] = "WorldPop (www.worldpop.org), CC BY 4.0"
    if "heights.dat" in files:
        licences[COPERNICUS] = ("© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under "
                                "COPERNICUS by the European Union and ESA; all rights reserved")
    write(folder, "pack.json", {
        "id": "rovaniemi", "system": SYSTEM, "decision": 789,
        "english": "Rovaniemi", "chinese": "羅瓦涅米",
        "_readme": "Rovaniemi's map pack: the railways from Rovaniemi to Kemijärvi and Muurola, with Fintraffic's "
                   "real timetables, in the formats and under the file names of Taiwan's real railways, read from "
                   "this folder alone. Made by tools/rovaniemi-map (README.md there).",
        "bytes": sum(f["bytes"] for f in files.values()),
        "extent": EXTENT,
        "licences": licences,
        "files": files,
    })


def main(extract, trains_json, out, first="2026-12-14"):
    with open(trains_json, encoding="utf-8") as f:
        digitraffic = json.load(f)
    start = datetime.date.fromisoformat(first)
    week = [start + datetime.timedelta(days=n) for n in range(7)]
    relation = Relation()
    relation.apply_file(extract)
    if relation.ways is None:
        sys.exit(f"the extract has no relation {RELATION}")
    parts = Parts(relation.ways)
    parts.apply_file(extract, locations=True)
    graph, at, way_of = track(parts)
    lines = [line_of(spec, parts, graph, at, way_of, digitraffic) for spec in LINES]

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "relation": RELATION, "newestTrackEdit": parts.newest, "method": "tools/rovaniemi-map/build_rovaniemi_rail.py"}
    note = ("Timetables, station codes and English station names: Source: Fintraffic / digitraffic.fi, licence CC 4.0 BY "
            f"(scheduled trains of {week[0]} to {week[-1]}, fetched {digitraffic['fetched'][:10]}). "
            "Tracks and stations: © OpenStreetMap contributors, ODbL 1.0.")
    timetables, network, report = {}, [], []
    for line in lines:
        days, runs, dwells = trips_of(line, digitraffic, week)
        # One set for each different day, named by the days that run it
        # (Sunday first, as `days` is).
        ordered = sorted(week, key=lambda d: d.isoweekday() % 7)
        found = []
        for day in ordered:
            trips = days.get(day, [])
            encoded = [[v for call in t["calls"] for v in call] for t in trips]
            kinds = "".join("2" if t["passes"] else "1" for t in trips)
            same = next((f for f in found if f["sets"] == encoded), None)
            if same is None:
                same = {"sets": encoded, "kinds": kinds, "trains": [t["train"] for t in trips], "days": []}
                found.append(same)
            same["days"].append(WEEKDAYS[day.isoweekday() % 7])
        sets = {"、".join(f["days"]): (f["sets"], f["kinds"], f["trains"]) for f in found}
        names = [next(n for n, f in zip(sets, found) if WEEKDAYS[day.isoweekday() % 7] in f["days"]) for day in ordered]
        count = len(line["codes"])
        segs = []
        for i in range(count - 1):
            if not runs[i]:
                sys.exit(f"{line['id']}: no train stops at both {line['codes'][i]} and {line['codes'][i + 1]}")
            segs.append({"run": int(statistics.median(runs[i]))})
        dwell = [int(statistics.median(dwells[i])) if dwells.get(i) else 60 for i in range(count)]
        timetables[line["id"]] = {
            "days": names, "holiday": names[0],
            "sets": {n: s[0] for n, s in sets.items()},
            "kinds": {n: s[1] for n, s in sets.items()},
            "trains": {n: s[2] for n, s in sets.items()},
        }
        network.append({
            "id": line["id"], "name": line["chinese"], "color": line["colour"],
            "stations": [{"name": s["name"], "lat": s["lat"], "lon": s["lon"], "d": s["d"]} for s in line["stations"]],
            "shape": [[y, x] for x, y in line["shape"]],
            "segs": segs, "dwellSec": dwell,
        })
        report.append((line, {n: len(s[0]) for n, s in sets.items()}, names))

    write(out, "vr.json", {"system": "VR", "source_notes": note, "lines": network})
    write(out, "vr_times.json", {"system": "VR", "source_notes": note, "lines": timetables})
    write(out, "track_lines.geojson", {
        "type": "FeatureCollection", "source": note, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "id": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": line["chinese"], "color": line["colour"], "sortKey": n, "kind": "track"},
                      "geometry": {"type": "LineString", "coordinates": line["shape"]}}
                     for n, line in enumerate(lines)],
    })
    write(out, "track_stations.geojson", {
        "type": "FeatureCollection", "source": note, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "lineId": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": s["name"], "code": s["code"], "color": line["colour"]},
                      "geometry": {"type": "Point", "coordinates": [s["lon"], s["lat"]]}}
                     for line in lines for s in line["stations"]],
    })
    for line in lines:
        for s in line["stations"]:
            if digitraffic["stations"][s["code"]]["name"] != s["english"]:
                sys.exit(f"Digitraffic calls {s['code']} {digitraffic['stations'][s['code']]['name']}, not {s['english']}")
    write(out, "station_names.json", {
        "source": note,
        "systems": {SYSTEM: {name: {"en": en} for name, en in sorted(STATIONS.values())}},
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"]} for line in lines}},
    })
    write(out, "rail_structures.json", {
        "_readme": "Where the lines of track_lines.geojson are on bridges (bridge) or in tunnels (tunnel), one "
                   "OpenStreetMap way each. Made by tools/rovaniemi-map/build_rovaniemi_rail.py.",
        "source": {"openStreetMap": osm},
        "structures": [s for line in lines for s in line["structures"]],
    })
    here = os.path.dirname(os.path.abspath(__file__))
    record = os.path.join(here, "rovaniemi_sources.json")
    sources = json.load(open(record, encoding="utf-8")) if os.path.exists(record) else {"decision": 789, "inputs": {}}
    sources["inputs"][os.path.basename(extract)] = {
        "sha256": sha256(extract), "from": "https://osmtoday.com/europe/finland.pbf, cut with "
        "osmium extract -b 25.15,66.27,27.65,66.83 -s smart", "licence": "ODbL 1.0, © OpenStreetMap contributors"}
    sources["inputs"]["digitraffic_trains.json"] = {
        "sha256": sha256(trains_json), "from": "tools/rovaniemi-map/fetch_digitraffic.py", "fetched": digitraffic["fetched"],
        "week": [str(week[0]), str(week[-1])], "licence": "CC BY 4.0, Fintraffic / digitraffic.fi"}
    sources["lines"] = [{"id": line["id"], "osmRelation": RELATION, "stations": len(line["stations"]),
                         "km": line["stations"][-1]["d"], "trips": counts, "days": names}
                        for line, counts, names in report]
    write(here, "rovaniemi_sources.json", sources)
    write_manifest(out)
    for line, counts, names in report:
        print(f"{line['id']:4} {len(line['stations'])} stations {line['stations'][-1]['d']:6.2f} km "
              f"{len(line['shape']):4} points {len(line['structures']):2} structures; trips {counts}; days {names}")


if __name__ == "__main__":
    main(*sys.argv[1:])
