#!/usr/bin/env python3
"""The railways of the Fukuoka map as the game's real-railway files
(decision 854), in the formats and under the file names of Hong Kong's
pack (`tools/hk-map/build_hk_mtr.py`, decision 697) and Rovaniemi's
(`tools/rovaniemi-map/build_rovaniemi_rail.py`, decision 789).

    python3 -I tools/fukuoka-map/build_fukuoka_rail.py \\
        N02-25_Station.geojson fukuoka.pbf \\
        RailwayGameApp/Resources/MapPacks/fukuoka

Japan's first map is one small area, not the whole country: the Fukuoka
City Subway's three lines, from Meinohama to Fukuoka Airport (the Kuko
Line, K), from Nakasu-Kawabata to Kaizuka (the Hakozaki Line, H) and from
Hashimoto to Hakata (the Nanakuma Line, N). The airport's station is on
the Kuko Line, two stops from Hakata, as Hong Kong's is on the Airport
Express (the flights that open the map, decision 712, come later).

Where each part comes from:

- **Stations**: the Ministry of Land, Infrastructure, Transport and
  Tourism's National Land Numerical Information, railway data N02
  (2025 edition, CC BY 4.0): each station of the operator 福岡市 on the
  three lines (`N02_003`), its point the middle of N02's platform line.
  The order of each line is the operator's own station numbering
  (`STATIONS`), checked against N02: every one of N02's stations of the
  line is in it and every one of it is in N02.
- **Track, tunnels and viaducts**: OpenStreetMap (the Kyushu extract cut
  to the map with `osmium extract`, read with pyosmium, never Overpass):
  every `railway=subway` way of the main lines (no yard, siding, spur or
  crossover), joined into a graph by their shared nodes, the cheapest
  path between each two stations that follow each other. A station is put
  on the nearest node of the track, which must lie within `SNAP` metres of
  N02's point. A way tagged `tunnel` is a tunnel, `bridge` a viaduct.
- **English names**: this project's (`STATIONS`, the operator's romaji
  without macrons), checked against OpenStreetMap's `name:en` of the
  station or stop within `NAME_REACH` metres that has N02's name; the
  tool prints where they differ (the GSI's multilingual names are
  experimental and not used, JAPAN_RAIL_DATA_2026-10-21 §4.F).
- **Chinese names**, line names and the colours' choice: this project's.
  The colours are OpenStreetMap's route relations' (`colour`).
- **Times**: there is no published open timetable of the Fukuoka City
  Subway (searched 2026-11-18). Each day's trips are laid out from
  headways, first and last trains this project estimated from the City of
  Fukuoka's timetable-change notices (2024-2026: peak headways), the
  seconds between stations from the distance (`run_seconds`), as Hong
  Kong's are from headways (`build_hk_mtr.trips`); `fksubway_times.json`
  says it is an estimate. The Hakozaki Line's trains that run on to
  Meinohama and the Kuko Line's that run on to JR's Chikuhi Line are left
  out: each line runs its own stretch (FUKUOKA-THROUGH, later).

Writes `fksubway.json`, `fksubway_times.json`, `track_lines.geojson`,
`track_stations.geojson`, `station_names.json`, `rail_structures.json`
and `pack.json` into the folder, and `fukuoka_sources.json` (what it read,
with checksums) beside this tool.
"""
import collections
import hashlib
import heapq
import json
import math
import os
import sys

import osmium

SYSTEM = "fksubway"
OPERATOR = "福岡市"
# (game line id = the operator's line letter, N02's line name, Chinese
# name, English name, OpenStreetMap's route relation (one direction) whose
# colour the line takes, its colour as that relation had it.)
LINES = [
    ("K", "1号線(空港線)", "空港線", "Kuko Line", 1871204, "#FF4500"),
    ("H", "2号線(箱崎線)", "箱崎線", "Hakozaki Line", 1871205, "#0077CC"),
    ("N", "3号線(七隈線)", "七隈線", "Nanakuma Line", 1871203, "#008000"),
]
# Each line's stations in the operator's numbering (K01 Meinohama ...):
# (N02's name, the game's Chinese name, the English name OpenStreetMap
# should give). The Chinese names are N02's in traditional characters
# (姪浜 → 姪濱, 恵 → 惠, 県庁 → 縣廳, 薬 → 藥, 辺 → 邊, 桜 → 櫻, 呉 → 吳),
# and 福岡空港 is 福岡機場, as Taiwan's airports' stations are named.
STATIONS = {
    "K": [
        ("姪浜", "姪濱", "Meinohama"), ("室見", "室見", "Muromi"), ("藤崎", "藤崎", "Fujisaki"),
        ("西新", "西新", "Nishijin"), ("唐人町", "唐人町", "Tojinmachi"), ("大濠公園", "大濠公園", "Ohorikoen"),
        ("赤坂", "赤坂", "Akasaka"), ("天神", "天神", "Tenjin"), ("中洲川端", "中洲川端", "Nakasu-Kawabata"),
        ("祇園", "祇園", "Gion"), ("博多", "博多", "Hakata"), ("東比恵", "東比惠", "Higashi-Hie"),
        ("福岡空港", "福岡機場", "Fukuoka Airport"),
    ],
    "H": [
        ("中洲川端", "中洲川端", "Nakasu-Kawabata"), ("呉服町", "吳服町", "Gofukumachi"),
        ("千代県庁口", "千代縣廳口", "Chiyo-Kenchoguchi"), ("馬出九大病院前", "馬出九大病院前", "Maidashi-Kyudaibyoinmae"),
        ("箱崎宮前", "箱崎宮前", "Hakozakimiyamae"), ("箱崎九大前", "箱崎九大前", "Hakozaki-Kyudaimae"),
        ("貝塚", "貝塚", "Kaizuka"),
    ],
    "N": [
        ("橋本", "橋本", "Hashimoto"), ("次郎丸", "次郎丸", "Jiromaru"), ("賀茂", "賀茂", "Kamo"),
        ("野芥", "野芥", "Noke"), ("梅林", "梅林", "Umebayashi"), ("福大前", "福大前", "Fukudaimae"),
        ("七隈", "七隈", "Nanakuma"), ("金山", "金山", "Kanayama"), ("茶山", "茶山", "Chayama"),
        ("別府", "別府", "Befu"), ("六本松", "六本松", "Ropponmatsu"), ("桜坂", "櫻坂", "Sakurazaka"),
        ("薬院大通", "藥院大通", "Yakuin-Odori"), ("薬院", "藥院", "Yakuin"), ("渡辺通", "渡邊通", "Watanabe-dori"),
        ("天神南", "天神南", "Tenjin-Minami"), ("櫛田神社前", "櫛田神社前", "Kushida-jinja-mae"), ("博多", "博多", "Hakata"),
    ],
}
# Estimated service of each line (seconds of the day; a last train past
# midnight is over 86400, as Hong Kong's). Peaks: weekday mornings and
# evenings. Peak headways from the City of Fukuoka's notices: the Kuko
# Line's 3 min 20 s between Nakasu-Kawabata and the airport (March 2026),
# the Nanakuma Line's average 3 min 15 s (August 2023; its shortest is
# 3 min since March 2024, but at 3 min the trains the change to off-peak
# leaves over need six tracks at each end, and the game lays five where a
# line has no depot: the real line's is at Hashimoto, FUKUOKA-DEPOT later);
# the Hakozaki Line's and every off-peak headway are this project's
# estimate.
SERVICE = {
    "K": {"peakHeadwaySec": 200, "offpeakHeadwaySec": 300},
    "H": {"peakHeadwaySec": 300, "offpeakHeadwaySec": 480},
    "N": {"peakHeadwaySec": 195, "offpeakHeadwaySec": 300},
}
FIRST_TRAIN, LAST_TRAIN = 5 * 3600 + 30 * 60, 24 * 3600 + 15 * 60
PEAKS = [[7 * 3600, 9 * 3600 + 30 * 60], [17 * 3600, 19 * 3600 + 30 * 60]]
DWELL = 30
# How far N02's station may lie from the track, and OpenStreetMap's named
# point from N02's, in metres.
SNAP, NAME_REACH = 150, 400
# How much farther than the nearest node a station's node may be, in
# metres, to keep the line on one track.
CHOICE = 40
# Decision 854: how far the Fukuoka map reaches, in degrees: Meinohama and
# Hashimoto in the west to the airport in the east, Hakata Bay and Kaizuka
# in the north, with room to the north for Nishitetsu's Kaizuka Line
# (NISHITETSU-KAIZUKA, later); some 17.6 km by 22.2 km.
EXTENT = {"north": 33.72, "south": 33.52, "west": 130.29, "east": 130.48}
SKIPPED_SERVICE = {"yard", "siding", "spur", "crossover"}


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


def n02_stations(path):
    """N02's stations of the operator's three lines: {line id: {name: (lon, lat)}},
    each the middle of its platform line."""
    with open(path, encoding="utf-8") as f:
        features = json.load(f)["features"]
    by_name = {spec[1]: spec[0] for spec in LINES}
    found = collections.defaultdict(dict)
    for feature in features:
        p = feature["properties"]
        if p["N02_004"] != OPERATOR or p["N02_003"] not in by_name:
            continue
        coords = feature["geometry"]["coordinates"]
        along, total = [0.0], 0.0
        for a, b in zip(coords, coords[1:]):
            total += metres(a, b)
            along.append(total)
        half = total / 2
        for i in range(len(coords) - 1):
            if along[i + 1] >= half:
                t = (half - along[i]) / ((along[i + 1] - along[i]) or 1)
                mid = (coords[i][0] + t * (coords[i + 1][0] - coords[i][0]), coords[i][1] + t * (coords[i + 1][1] - coords[i][1]))
                break
        else:
            mid = tuple(coords[0])
        found[by_name[p["N02_003"]]][p["N02_005"]] = mid
    return found


class Parts(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways, self.named, self.colours = {}, [], {}
        self.newest = ""

    def way(self, w):
        tags = dict(w.tags)
        if tags.get("railway") != "subway" or tags.get("service") in SKIPPED_SERVICE:
            return
        self.ways[w.id] = {"tags": tags, "nodes": [(n.ref, n.lon, n.lat) for n in w.nodes]}
        self.newest = max(self.newest, w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"))

    def node(self, n):
        tags = dict(n.tags)
        if "name" in tags and (tags.get("railway") in ("station", "stop") or tags.get("public_transport") in ("station", "stop_position")):
            self.named.append({"name": tags["name"], "en": tags.get("name:en"), "at": (n.location.lon, n.location.lat)})

    def relation(self, r):
        if any(r.id == spec[4] for spec in LINES):
            self.colours[r.id] = dict(r.tags).get("colour")


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


def distances(graph, a, targets):
    """The track length from `a` to each of `targets` it reaches."""
    best, heap, found = {a: 0.0}, [(0.0, a)], {}
    while heap and len(found) < len(targets):
        d, u = heapq.heappop(heap)
        if d > best[u]:
            continue
        if u in targets:
            found[u] = d
        for v, w in graph[u]:
            if d + w < best.get(v, math.inf):
                best[v] = d + w
                heapq.heappush(heap, (d + w, v))
    return found


def english_of(name, point, parts):
    """OpenStreetMap's English name of the station called `name` near `point`."""
    near = [p for p in parts.named if p["name"] == name and p["en"] and metres(p["at"], point) <= NAME_REACH]
    names = collections.Counter(p["en"] for p in near)
    return names.most_common(1)[0][0] if names else None


def ascii_fold(text):
    """Macrons and the like off (Kūkō → Kuko), for comparing names."""
    table = str.maketrans("āēīōūĀĒĪŌŪ", "aeiouAEIOU")
    return text.translate(table).lower().replace(" ", "").replace("-", "")


def line_of(spec, n02, parts, graph, at, way_of):
    line_id, n02_name, chinese, english, relation, colour = spec
    listed = STATIONS[line_id]
    names = [s[0] for s in listed]
    if set(names) != set(n02[line_id]):
        sys.exit(f"{line_id}: N02 has {sorted(n02[line_id])}, the operator's numbering {sorted(names)}")
    found = parts.colours.get(relation)
    if found is not None and found.upper() != colour.upper():
        sys.exit(f"{line_id}: OpenStreetMap's relation {relation} is now {found}, not {colour}")
    # A double line is two tracks, joined where the yards and the ends
    # join them: each station is put on the node near it (within SNAP of
    # N02's point, and at most CHOICE farther than the nearest) that makes
    # the whole line shortest, so the line keeps to one track and never
    # runs out to an end and back.
    points = [n02[line_id][name] for name in names]
    choices = []
    for name, point in zip(names, points):
        near = sorted((metres(at[n], point), n) for n in at)
        if near[0][0] > SNAP:
            sys.exit(f"{line_id} {name}: the track passes {near[0][0]:.0f} m from N02's station")
        choices.append([n for d, n in near if d <= min(SNAP, near[0][0] + CHOICE)])
    best = {n: (0.0, [n]) for n in choices[0]}
    for options in choices[1:]:
        reached = {}
        for n, (length, path) in best.items():
            far = distances(graph, n, set(options))
            for m, d in far.items():
                if m not in reached or length + d < reached[m][0]:
                    reached[m] = (length + d, path + [m])
        if not reached:
            sys.exit(f"{line_id}: no track between two of {names}")
        best = reached
    best = (None, min(best.values())[1])
    stops, english_names = best[1], []
    for name, _, expected in listed:
        point = n02[line_id][name]
        osm = english_of(name, point, parts)
        if osm is not None and ascii_fold(osm) != ascii_fold(expected):
            print(f"note: {line_id} {name}: OpenStreetMap says {osm!r}, kept {expected!r}")
        english_names.append(expected)
    shape, structures, vertices = [at[stops[0]]], [], [0]
    for a, b in zip(stops, stops[1:]):
        path = cheapest(graph, a, b)
        if path is None:
            sys.exit(f"{line_id}: no track between two of {names}")
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
    for name, vertex in zip(names, vertices):
        x, y = shape[vertex]
        if not (EXTENT["south"] <= y <= EXTENT["north"] and EXTENT["west"] <= x <= EXTENT["east"]):
            sys.exit(f"{line_id} {name} is off the map")
    return {
        "id": line_id, "chinese": chinese, "english": english, "colour": colour,
        "stations": [{"code": f"{line_id}{n + 1:02d}", "ja": s[0], "name": s[1], "english": en,
                      "lon": round(shape[v][0], 6), "lat": round(shape[v][1], 6), "d": round(along[v] / 1000, 4)}
                     for n, (s, en, v) in enumerate(zip(listed, english_names, vertices))],
        "shape": [[round(x, 6), round(y, 6)] for x, y in shape],
        "structures": kept,
    }


def run_seconds(km):
    """Seconds between two stations `km` apart, door to door less the dwell:
    20 s of starting and stopping and the rest at 54 km/h (15 m/s), an
    estimate (no published running times)."""
    return int(round(20 + km * 1000 / 15))


def trips(line):
    """The day's trips both ways from the headways (`build_hk_mtr.trips`):
    each a list of station index and the second of the day it leaves (the
    last, arrives)."""
    service = SERVICE[line["id"]]
    stations = line["stations"]
    runs = [run_seconds(b["d"] - a["d"]) + DWELL for a, b in zip(stations, stations[1:])]
    count = len(stations)
    out = []
    for order in (list(range(count)), list(range(count - 1, -1, -1))):
        leave = FIRST_TRAIN
        while leave <= LAST_TRAIN:
            t, trip = leave, []
            for n, index in enumerate(order):
                if n:
                    t += runs[min(index, order[n - 1])]
                trip += [index, t]
            out.append(trip)
            peak = any(a <= leave < b for a, b in PEAKS)
            leave += service["peakHeadwaySec"] if peak else service["offpeakHeadwaySec"]
    return out


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def write(folder, name, value):
    with open(os.path.join(folder, name), "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


OSM, MLIT, OURS = "OpenStreetMap", "National Land Numerical Information (railway data N02, 2025), MLIT", "this project"
SOURCES = {
    "track_lines.geojson": {"geometry": OSM, "id, name, color": OURS},
    "track_stations.geojson": {"geometry (N02's station, on OpenStreetMap's track)": MLIT, "code (the operator's numbering)": OURS,
                               "name (Chinese)": OURS, "color": OURS},
    "station_names.json": {"ja (N02's station name)": MLIT, "en (checked against OpenStreetMap's name:en)": OURS, "routes": OURS},
    "rail_structures.json": {"structures": OSM},
    "fksubway.json": {"stations": MLIT, "shape": OSM, "segs.run, dwellSec (estimated from distance)": OURS},
    "fksubway_times.json": {"sets (laid out from estimated headways)": OURS},
    "metro_runs.json": {"runs (fksubway_times.json's trips)": OURS, "overnight, tracks, positioning runs": OURS},
}
MLIT_CREDIT = ("「国土数値情報（鉄道データ）」（国土交通省）"
               "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html を加工して作成, CC BY 4.0")


def write_manifest(folder):
    """`pack.json`: what the pack is and, for each file in it, its size and
    where its parts come from."""
    files = {name: {"bytes": os.path.getsize(os.path.join(folder, name)), "sources": SOURCES[name]}
             for name in sorted(SOURCES) if os.path.exists(os.path.join(folder, name))}
    write(folder, "pack.json", {
        "id": "fukuoka", "system": SYSTEM, "decision": 854,
        "english": "Fukuoka", "chinese": "福岡",
        "_readme": "Fukuoka's map pack: the Fukuoka City Subway's three lines, with estimated headways, in the formats "
                   "and under the file names of Taiwan's real railways, read from this folder alone. Made by "
                   "tools/fukuoka-map (README.md there). Railways only so far: no base map, ground or people.",
        "bytes": sum(f["bytes"] for f in files.values()),
        "extent": EXTENT,
        "licences": {OSM: "© OpenStreetMap contributors, ODbL 1.0", MLIT: MLIT_CREDIT},
        "files": files,
    })


def main(n02_path, extract, out):
    os.makedirs(out, exist_ok=True)
    n02 = n02_stations(n02_path)
    parts = Parts()
    parts.apply_file(extract, locations=True)
    graph, at, way_of = track(parts)
    lines = [line_of(spec, n02, parts, graph, at, way_of) for spec in LINES]

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_fukuoka_rail.py"}
    note = ("Stations and their Japanese names: " + MLIT_CREDIT + ". Tracks, tunnels, viaducts and line colours: © "
            "OpenStreetMap contributors, ODbL 1.0. Chinese and English names and times: this project's; no published "
            "timetable, so each day's trips are laid out from estimated headways, not the operator's timetable.")
    write(out, "fksubway.json", {
        "system": "FKSUBWAY", "source_notes": note,
        "lines": [{
            "id": line["id"], "name": line["chinese"], "color": line["colour"],
            "peakHeadwaySec": SERVICE[line["id"]]["peakHeadwaySec"],
            "offpeakHeadwaySec": SERVICE[line["id"]]["offpeakHeadwaySec"],
            "headway_estimated": True,
            "stations": [{"name": s["name"], "lat": s["lat"], "lon": s["lon"], "d": s["d"]} for s in line["stations"]],
            "shape": [[y, x] for x, y in line["shape"]],
            "segs": [{"run": run_seconds(b["d"] - a["d"])} for a, b in zip(line["stations"], line["stations"][1:])],
            "dwellSec": [DWELL] * len(line["stations"]),
        } for line in lines],
    })
    write(out, "fksubway_times.json", {
        "system": "FKSUBWAY", "estimated": True,
        "source_notes": "No published timetable: each day's trips are laid out from headways, first and last trains this "
                        "project estimated (peak headways from the City of Fukuoka's timetable-change notices) and times "
                        "between stations worked out from the distance; not the operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日", "sets": {"每日": trips(line)}} for line in lines},
    })
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
    names = {}
    for line in lines:
        for s in line["stations"]:
            entry = {"en": s["english"], "ja": s["ja"]}
            if names.setdefault(s["name"], entry) != entry:
                sys.exit(f"{s['name']} has two names: {names[s['name']]} and {entry}")
    write(out, "station_names.json", {
        "source": note,
        "systems": {SYSTEM: dict(sorted(names.items()))},
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"]} for line in lines}},
    })
    write(out, "rail_structures.json", {
        "_readme": "Where the lines of track_lines.geojson are on viaducts (bridge) or in tunnels (tunnel), one "
                   "OpenStreetMap way each. Made by tools/fukuoka-map/build_fukuoka_rail.py.",
        "source": {"openStreetMap": osm},
        "structures": [s for line in lines for s in line["structures"]],
    })
    here = os.path.dirname(os.path.abspath(__file__))
    write(here, "fukuoka_sources.json", {
        "decision": 854,
        "inputs": {
            os.path.basename(n02_path): {
                "sha256": sha256(n02_path), "from": "https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip "
                "(UTF-8/N02-25_Station.geojson)", "licence": "CC BY 4.0, " + MLIT_CREDIT},
            os.path.basename(extract): {
                "sha256": sha256(extract), "from": "https://osmtoday.com/asia/japan/kyushu.pbf, cut with "
                "osmium extract -b 130.25,33.49,130.52,33.75 -s smart", "licence": "ODbL 1.0, © OpenStreetMap contributors"},
        },
        "lines": [{"id": line["id"], "osmRelation": spec[4], "stations": len(line["stations"]),
                   "km": line["stations"][-1]["d"], "trips": len(trips(line))} for line, spec in zip(lines, LINES)],
    })
    write_manifest(out)
    for line in lines:
        tunnels = sum(1 for s in line["structures"] if s["kind"] == "tunnel")
        print(f"{line['id']} {len(line['stations']):2} stations {line['stations'][-1]['d']:6.2f} km "
              f"{len(line['shape']):4} points {tunnels:2} tunnels {len(line['structures']) - tunnels:2} viaducts; "
              f"{len(trips(line))} trips a day")


if __name__ == "__main__":
    main(*sys.argv[1:])
