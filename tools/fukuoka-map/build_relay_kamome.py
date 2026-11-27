#!/usr/bin/env python3
"""The Relay Kamome (特急リレーかもめ), JR Kyushu's limited express from
Hakata to Takeo-Onsen on the conventional lines, as the game's real-railway
files (decision 1028, RELAY-KAMOME-LINE): the map's first JR line on the
1,067 mm gauge, a system of its own (`jrkyushu`), read and laid out as the
Kyushu Shinkansen's are (`build_kyushu_shinkansen.py`, decision 975).

    python3 -I tools/fukuoka-map/build_relay_kamome.py \\
        N02-25_Station.geojson kyushu.pbf tools/fukuoka-map/relay-kamome

and merged into the map pack beside the subway's and the Shinkansen's:

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge \\
        tools/fukuoka-map/relay-kamome RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

When only the service changes, the day's trips are laid out again without
N02 or OpenStreetMap (the Nishi-Kyushu Shinkansen's, which they meet at
Takeo-Onsen, read from the pack):

    python3 -I tools/fukuoka-map/build_relay_kamome.py times \\
        tools/fukuoka-map/relay-kamome RailwayGameApp/Resources/MapPacks/fukuoka

Where each part comes from:

- **Stations and their Japanese names**: N02 (2025 edition, CC BY 4.0),
  九州旅客鉄道's stations the Relay Kamome calls at (`STATIONS`): Hakata
  and Tosu of 鹿児島線, Shin-Tosu, Saga and Kōhoku of 長崎線, Takeo-Onsen of
  佐世保線, each the middle of N02's platform line. The stations only the
  local trains call at are left out (they are another ticket). The codes
  `RK01`–`RK06` are this project's.
- **Track, tunnels and viaducts**: OpenStreetMap (osmtoday.com's Kyushu
  extract, read whole): the `railway=rail` main-line ways of the three
  lines' infrastructure relations (`RELATIONS`: 鹿児島本線, JR長崎本線,
  JR佐世保線), joined and walked as the subway's are.
- **Chinese and English names**: this project's (N02's names in
  traditional characters, 温 → 溫; JR Kyushu's romaji without macrons).
- **The colour**: OpenStreetMap's for the Nagasaki Main Line
  (`route_master` 11823798, `#FAAF18`), the line the Relay Kamome runs on
  most of the way.
- **Times**: JR Kyushu publishes no open timetable. The day is laid out
  from the Nishi-Kyushu Shinkansen's estimated day already in the pack
  (`build_nishi_kyushu_shinkansen.py`, decision 998), as the real Relay
  Kamome is timed to its Kamome: each Kamome that leaves Takeo-Onsen for
  Nagasaki has a Relay Kamome come in across the platform `TRANSFER`
  seconds before it, and each Kamome that comes in from Nagasaki one leave
  `TRANSFER` seconds after it, every train calling at all six stations
  (as most real ones do; some pass Shin-Tosu). The seconds between
  stations come from the distance and the line's 130 km/h.
  `jrkyushu_times.json` says it is an estimate.
- **Gauge**: 1,067 mm, 20 kV 60 Hz overhead wire, written on the line as a
  record; the game lays the line at the gauge `TrackGauge.ofRealLine`
  names (decision 970).
"""
import collections
import json
import math
import os
import sys

import osmium

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_fukuoka_rail as fk  # noqa: E402
import build_kyushu_shinkansen as ks  # noqa: E402

SYSTEM = "jrkyushu"
LINE_ID = "RK"
OPERATOR = "九州旅客鉄道"
# OpenStreetMap's infrastructure relations (`route=railway`) of the lines
# the Relay Kamome runs on.
RELATIONS = {359426: "鹿児島本線", 1871198: "JR長崎本線", 1871195: "JR佐世保線"}
# The ways left out: as the subway's (`build_fukuoka_rail.SKIPPED_SERVICE`)
# but for the crossovers. On a double main line the Sasebo Line leaves
# one track at Kōhoku and the line comes in on the other: without the
# crossover between them, the way from one to the other ran out past the
# station and back twice (1.4 km too long).
SKIPPED_SERVICE = fk.SKIPPED_SERVICE - {"crossover"}
# The names OpenStreetMap gives the lines' ways, some of which their
# relations leave out (two ways of JR長崎線 between Tosu and Shin-Tosu).
NAMES = {"JR鹿児島本線", "鹿児島本線", "JR長崎本線", "JR長崎線", "長崎本線", "JR佐世保線", "佐世保線"}
# Takeo-Onsen: the Relay Kamome stands on track 10 (way 458032623, which
# OpenStreetMap tags a siding), across the island of platform 10;11 from
# the Kamome's track 11 (way 1258185406), 12 m apart, as the real ones
# meet across the platform (the owner's study of 2026-11-26). The Sasebo
# Line's main track through the station, 11 m further north-west (ways
# 933929935, 458032625 and 1367644704), is left out so the line comes in
# on track 10.
TAKEO_TRACK = 458032623
TAKEO_MAIN = {933929935, 458032625, 1367644704}
# N02's Takeo-Onsen of the Sasebo Line is the whole conventional station's
# middle, some 90 m north-east of that island's: the line's station is
# put at the middle of the island (way 846511481, platform 10;11), so its
# platform stands beside the Kamome's, not end to end with it.
TAKEO_ISLAND, TAKEO = 846511481, "武雄温泉"
# Hakata: the station's conventional platforms are on its second floor,
# over the concourse, the Shinkansen's on the third (ekitan.com's station
# guide, checked 2026-11-27); OpenStreetMap's tracks there carry no
# bridge tag, the bridges beginning 187 m south of the station's middle.
# So the line is on a viaduct from `HAKATA_VIADUCT` metres north of it to
# that many south, over the platforms (some 410 m) and on to the first
# of those bridges.
HAKATA_VIADUCT = (230, 215)
# The Nagasaki Main Line's colour (OpenStreetMap's route_master 11823798).
COLOUR_RELATION, COLOUR = 11823798, "#FAAF18"
# Hakata to Takeo-Onsen in the line's order: (N02's line, N02's name, the
# game's Chinese name, the English name).
STATIONS = [
    ("鹿児島線", "博多", "博多", "Hakata"), ("鹿児島線", "鳥栖", "鳥栖", "Tosu"),
    ("長崎線", "新鳥栖", "新鳥栖", "Shin-Tosu"), ("長崎線", "佐賀", "佐賀", "Saga"),
    ("長崎線", "江北", "江北", "Kohoku"), ("佐世保線", "武雄温泉", "武雄溫泉", "Takeo-Onsen"),
]
EXTENT = ks.EXTENT
# The fare distance (営業キロ): Hakata to Tosu 28.6 km on the Kagoshima
# Main Line, Tosu to Kōhoku 39.6 km on the Nagasaki Main Line, Kōhoku to
# Takeo-Onsen 13.7 km on the Sasebo Line.
REAL_KM, KM_TOLERANCE = 81.9, 0.02
TRACK = {"gaugeMm": 1067, "loadingGauge": "conventional", "electrification": "AC 20 kV 60 Hz overhead",
         "maxSpeedKmh": 130}
# A Relay Kamome's dwell at each station, and how long before a Kamome
# leaves Takeo-Onsen it comes in, and after one comes in it leaves: the
# timetable's three minutes across the platform (20 of the 22 each way;
# the owner's study of 2026-11-26, railway-assets-private-2
# docs/research/NISHI-KYUSHU-KAMOME-2026-11-26.md; decision 912 gives a
# passenger a minute to cross it).
DWELL = 60
TRANSFER = 180
# `run_seconds`: the line's top speed (130 km/h, the 885 series' on the
# Nagasaki Main Line), how fast a train gains and loses it (m/s², about an
# 885's 2.2 km/h/s), and the slack a timetable keeps on lines that wind
# and share their tracks with local and freight trains.
TOP_SPEED, RATE, SLACK = 130 / 3.6, 0.6, 1.25


def run_seconds(km):
    """Seconds between two stations `km` apart, without the dwell, as
    `build_kyushu_shinkansen.run_seconds` works them out. An estimate:
    Hakata to Takeo-Onsen comes to about 65 minutes with the stops, as the
    real ones take (58 to 70)."""
    d = km * 1000
    reach = TOP_SPEED ** 2 / RATE
    seconds = d / TOP_SPEED + TOP_SPEED / RATE if d >= reach else 2 * math.sqrt(d / RATE)
    return int(round(seconds * SLACK))


class Members(osmium.SimpleHandler):
    """The ways of `RELATIONS`, and the colour of `COLOUR_RELATION`."""

    def __init__(self):
        super().__init__()
        self.ways, self.colour = {}, None

    def relation(self, r):
        if r.id in RELATIONS:
            for m in r.members:
                if m.type == "w":
                    self.ways.setdefault(m.ref, set()).add(r.id)
        if r.id == COLOUR_RELATION:
            self.colour = dict(r.tags).get("colour")


class Parts(osmium.SimpleHandler):
    """The main-line ways of the relations, and the 1,067 mm ways named as
    the lines (as `build_fukuoka_rail.Parts`)."""

    def __init__(self, members):
        super().__init__()
        self.members = members
        self.ways, self.named, self.colours = {}, [], {}
        self.island = None
        self.newest = ""

    def way(self, w):
        tags = dict(w.tags)
        if w.id == TAKEO_ISLAND:
            self.island = [(n.lon, n.lat) for n in w.nodes]
        if w.id in TAKEO_MAIN or w.id not in self.members and not (tags.get("name") in NAMES and tags.get("gauge") == "1067"):
            return
        if tags.get("railway") != "rail" or tags.get("service") in SKIPPED_SERVICE and w.id != TAKEO_TRACK:
            return
        self.ways[w.id] = {"tags": tags, "nodes": [(n.ref, n.lon, n.lat) for n in w.nodes]}
        self.newest = max(self.newest, w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"))

    def node(self, n):
        tags = dict(n.tags)
        if "name" in tags and (tags.get("railway") in ("station", "stop") or tags.get("public_transport") in ("station", "stop_position")):
            self.named.append({"name": tags["name"], "en": tags.get("name:en"), "at": (n.location.lon, n.location.lat)})


def n02_stations(path):
    """N02's points of `STATIONS`: {LINE_ID: {name: (lon, lat)}}."""
    wanted = {(s[0], s[1]) for s in STATIONS}
    with open(path, encoding="utf-8") as f:
        features = json.load(f)["features"]
    found = {}
    for feature in features:
        p = feature["properties"]
        if p["N02_004"] != OPERATOR or (p["N02_003"], p["N02_005"]) not in wanted:
            continue
        coords = feature["geometry"]["coordinates"]
        found[p["N02_005"]] = middle_of(coords)
    missing = {s[1] for s in STATIONS} - set(found)
    if missing:
        sys.exit(f"N02 has no {sorted(missing)}")
    return {LINE_ID: found}


def middle_of(coords):
    along, total = [0.0], 0.0
    for a, b in zip(coords, coords[1:]):
        total += fk.metres(a, b)
        along.append(total)
    half = total / 2
    for i in range(len(coords) - 1):
        if along[i + 1] >= half:
            t = (half - along[i]) / ((along[i + 1] - along[i]) or 1)
            return (coords[i][0] + t * (coords[i + 1][0] - coords[i][0]), coords[i][1] + t * (coords[i + 1][1] - coords[i][1]))
    return tuple(coords[0])


# OpenStreetMap leaves a few pieces of track unjoined a few metres from
# the track they meet (the Nagasaki Main Line's up track and the Kagoshima
# Main Line's at Tosu pass 3.1 m apart with no node in common): two pieces
# of track that come this near are joined where they come nearest.
JOIN = 5.0


def joined(graph, at, way_of):
    """`graph` with each two pieces of it that share no node joined at
    their two nearest nodes, if they are within `JOIN` metres."""
    piece, count = {}, 0
    for n in at:
        if n in piece:
            continue
        count += 1
        piece[n], stack = count, [n]
        while stack:
            u = stack.pop()
            for v, _ in graph[u]:
                if v not in piece:
                    piece[v] = count
                    stack.append(v)
    cell = 1e-4
    buckets = collections.defaultdict(list)
    for n, (x, y) in at.items():
        buckets[(int(x / cell), int(y / cell))].append(n)
    nearest = {}
    for n, (x, y) in at.items():
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for m in buckets[(int(x / cell) + i, int(y / cell) + j)]:
                    pair = tuple(sorted((piece[n], piece[m])))
                    if pair[0] == pair[1]:
                        continue
                    d = fk.metres((x, y), at[m])
                    if d <= JOIN and (pair not in nearest or d < nearest[pair][0]):
                        nearest[pair] = (d, n, m)
    for d, n, m in nearest.values():
        graph[n].append((m, d))
        graph[m].append((n, d))
        way_of[(n, m)] = way_of[(m, n)] = way_of[(n, graph[n][0][0])]
    return sorted((round(d, 1), n, m) for d, n, m in nearest.values())


def hakata_viaduct(shape):
    """The viaduct under Hakata's platforms (`HAKATA_VIADUCT`): from as far
    north of the line's first point as its first piece leads away from it,
    to as far south along it."""
    north, south = HAKATA_VIADUCT
    (x0, y0), (x1, y1) = shape[0], shape[1]
    first = fk.metres(shape[0], shape[1])
    start = (x0 - (x1 - x0) * north / first, y0 - (y1 - y0) * north / first)
    points, left = [start, shape[0]], south
    for a, b in zip(shape, shape[1:]):
        d = fk.metres(a, b)
        if d >= left:
            points.append((a[0] + (b[0] - a[0]) * left / d, a[1] + (b[1] - a[1]) * left / d))
            break
        points.append(b)
        left -= d
    return {"way": None, "system": SYSTEM, "kind": "bridge", "points": [[round(x, 6), round(y, 6)] for x, y in points],
            "note": "Hakata's platforms, on the station's second floor; not tagged in OpenStreetMap"}


def set_up():
    fk.SYSTEM, fk.OPERATOR, fk.EXTENT = SYSTEM, OPERATOR, EXTENT
    fk.LINES = [(LINE_ID, None, "海鷗接力號", "Relay Kamome", COLOUR_RELATION, COLOUR)]
    fk.STATIONS = {LINE_ID: [s[1:] for s in STATIONS]}
    fk.DWELL, fk.run_seconds = DWELL, run_seconds


def kamome_at_takeo(pack):
    """The Nishi-Kyushu Shinkansen's estimated day in `pack`
    (`kyushushinkansen_times.json`, line `NK`): the seconds each of its
    trains leaves Takeo-Onsen (station 0) and comes in there."""
    with open(os.path.join(pack, "kyushushinkansen_times.json"), encoding="utf-8") as f:
        trips = json.load(f)["lines"]["NK"]["sets"]["每日"]
    leaves, comes = [], []
    for trip in trips:
        if trip[0] == 0:
            leaves.append(trip[1])
        if trip[-2] == 0:
            comes.append(trip[-1])
    return sorted(leaves), sorted(comes)


def trips_of(line, pack):
    """The day's trips both ways, timed to the Kamome at Takeo-Onsen (the
    last station): each a list of station index and the second of the day
    it leaves (the last, arrives)."""
    stations = line["stations"]
    runs = [run_seconds(b["d"] - a["d"]) + DWELL for a, b in zip(stations, stations[1:])]
    end = len(stations) - 1
    leaves, comes = kamome_at_takeo(pack)
    out = []
    for leave in leaves:
        # Down: from Hakata, in at Takeo-Onsen TRANSFER before the Kamome
        # leaves (the times as `build_fukuoka_rail.trips` writes them: each
        # station's the run and a dwell after the one before).
        t = leave - TRANSFER - sum(runs)
        trip = [0, t]
        for n in range(1, end + 1):
            t += runs[n - 1]
            trip += [n, t]
        out.append(trip)
    for come in comes:
        t = come + TRANSFER
        trip = [end, t]
        for n in range(end - 1, -1, -1):
            t += runs[n]
            trip += [n, t]
        out.append(trip)
    return sorted(out, key=lambda trip: trip[1])


NOTE = ("Stations and their Japanese names: " + fk.MLIT_CREDIT + ". Tracks, tunnels and viaducts: © OpenStreetMap "
        "contributors, ODbL 1.0. Chinese and English names and times: this project's; the colour: OpenStreetMap's for "
        "the Nagasaki Main Line. JR Kyushu publishes no open timetable, so each day's trips are timed to the estimated "
        "Kamome at Takeo-Onsen, every train calling at every station, not the operator's timetable.")


def times_of(line, pack):
    trips = trips_of(line, pack)
    return trips, {
        "system": SYSTEM.upper(), "estimated": True,
        "source_notes": "No open timetable (JR Kyushu publishes no GTFS and its timetable pages may not be reused): "
                        "each day's trips are timed to the estimated Nishi-Kyushu Shinkansen Kamome at Takeo-Onsen "
                        f"(in {TRANSFER // 60} minutes before each Kamome leaves, out {TRANSFER // 60} minutes after "
                        "each comes in, across the platform, as the real Relay Kamome is), every train calling at "
                        "every station, and times between stations worked out from the distance and the line's "
                        "130 km/h; not the operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日", "sets": {"每日": trips}}},
    }


def main(n02_path, extract, out, pack):
    os.makedirs(out, exist_ok=True)
    set_up()
    n02 = n02_stations(n02_path)
    members = Members()
    members.apply_file(extract, filters=[osmium.filter.KeyFilter("type")])
    if members.colour is None or members.colour.upper() != COLOUR:
        sys.exit(f"OpenStreetMap's relation {COLOUR_RELATION} is now {members.colour}, not {COLOUR}")
    parts = Parts(members.ways)
    parts.apply_file(extract, locations=True, filters=[osmium.filter.KeyFilter("railway")])
    if parts.island is None:
        sys.exit(f"OpenStreetMap has no way {TAKEO_ISLAND}, Takeo-Onsen's platform 10;11")
    ring = parts.island[:-1] if parts.island[0] == parts.island[-1] else parts.island
    n02[LINE_ID][TAKEO] = (sum(x for x, _ in ring) / len(ring), sum(y for _, y in ring) / len(ring))
    graph, at, way_of = fk.track(parts)
    joins = joined(graph, at, way_of)
    line = fk.line_of(fk.LINES[0], n02, parts, graph, at, way_of)
    line["structures"].insert(0, hakata_viaduct(line["shape"]))
    km = line["stations"][-1]["d"]
    if abs(km - REAL_KM) > REAL_KM * KM_TOLERANCE:
        sys.exit(f"Hakata to Takeo-Onsen measures {km:.2f} km, the fare distance is {REAL_KM} km")

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_relay_kamome.py"}
    stations = line["stations"]
    fk.write(out, f"{SYSTEM}.json", {
        "system": SYSTEM.upper(), "source_notes": NOTE,
        "lines": [{
            "id": line["id"], "name": line["chinese"], "color": line["colour"],
            "peakHeadwaySec": 1800, "offpeakHeadwaySec": 3600, "headway_estimated": True,
            **TRACK,
            "stations": [{"name": s["name"], "lat": s["lat"], "lon": s["lon"], "d": s["d"]} for s in stations],
            "shape": [[y, x] for x, y in line["shape"]],
            "segs": [{"run": run_seconds(b["d"] - a["d"])} for a, b in zip(stations, stations[1:])],
            "dwellSec": [DWELL] * len(stations),
        }],
    })
    trips, times = times_of(line, pack)
    fk.write(out, f"{SYSTEM}_times.json", times)
    fk.write(out, "track_lines.geojson", {
        "type": "FeatureCollection", "source": NOTE, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "id": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": line["chinese"], "color": line["colour"], "sortKey": 0, "kind": "track"},
                      "geometry": {"type": "LineString", "coordinates": line["shape"]}}],
    })
    fk.write(out, "track_stations.geojson", {
        "type": "FeatureCollection", "source": NOTE, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "lineId": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": s["name"], "code": s["code"], "color": line["colour"]},
                      "geometry": {"type": "Point", "coordinates": [s["lon"], s["lat"]]}} for s in stations],
    })
    fk.write(out, "station_names.json", {
        "source": NOTE,
        "systems": {SYSTEM: {s["name"]: {"en": s["english"], "ja": s["ja"]} for s in sorted(stations, key=lambda s: s["name"])}},
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"], "ja": "リレーかもめ"}}},
    })
    fk.write(out, "rail_structures.json", {
        "_readme": "Where the line of track_lines.geojson is on viaducts and bridges (bridge) or in tunnels (tunnel), "
                   "one OpenStreetMap way each; the rest is on the ground (embankments and cuttings). Made by "
                   "tools/fukuoka-map/build_relay_kamome.py.",
        "source": {"openStreetMap": osm},
        "structures": [dict(s, line=LINE_ID) for s in line["structures"]],
    })

    by_kind = collections.Counter()
    for s in line["structures"]:
        by_kind[s["kind"]] += ks.length(s["points"]) / 1000
    end_to_end = sum(run_seconds(b["d"] - a["d"]) + DWELL for a, b in zip(stations, stations[1:])) - DWELL
    here = os.path.dirname(os.path.abspath(__file__))
    fk.write(here, "relay_kamome_sources.json", {
        "task": "RELAY-KAMOME-LINE", "decision": 1028, "staged": os.path.relpath(out, os.path.join(here, "..", "..")),
        "inputs": {
            os.path.basename(n02_path): {
                "sha256": fk.sha256(n02_path), "from": "https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip "
                "(UTF-8/N02-25_Station.geojson)", "licence": "CC BY 4.0, " + fk.MLIT_CREDIT},
            os.path.basename(extract): {
                "sha256": fk.sha256(extract), "from": "https://osmtoday.com/asia/japan/kyushu.pbf (whole, not cut)",
                "newestTrackEdit": parts.newest, "licence": "ODbL 1.0, © OpenStreetMap contributors"},
        },
        "line": {"id": line["id"], "osmRelations": sorted(RELATIONS), "stations": len(stations), "km": km, "realKm": REAL_KM,
                 "tunnelKm": round(by_kind["tunnel"], 2), "viaductKm": round(by_kind["bridge"], 2),
                 "groundKm": round(km - by_kind["tunnel"] - by_kind["bridge"], 2),
                 "endToEndSec": end_to_end, "trips": len(trips)},
        "files": {name: os.path.getsize(os.path.join(out, name)) for name in sorted(os.listdir(out)) if name.endswith("json")},
    })
    print(f"{line['id']} {len(stations)} stations {km:.2f} km (fare {REAL_KM}) {len(line['shape'])} points; "
          f"tunnels {by_kind['tunnel']:.1f} km, viaducts {by_kind['bridge']:.1f} km; "
          f"{end_to_end // 60} min {end_to_end % 60} s end to end, {len(trips)} trips a day; {len(joins)} ends joined")
    for a, b in zip(stations, stations[1:]):
        print(f"  {a['ja']} → {b['ja']}: {b['d'] - a['d']:6.2f} km, {run_seconds(b['d'] - a['d'])} s")


def times(folder, pack):
    """The day's trips laid out again in `folder`'s `jrkyushu_times.json`
    from the line its `jrkyushu.json` holds and the Kamome in `pack`."""
    set_up()
    with open(os.path.join(folder, f"{SYSTEM}.json"), encoding="utf-8") as f:
        stored = next(line for line in json.load(f)["lines"] if line["id"] == LINE_ID)
    line = {"id": LINE_ID, "stations": stored["stations"]}
    trips, value = times_of(line, pack)
    fk.write(folder, f"{SYSTEM}_times.json", value)
    print(f"{folder}: {len(trips)} trips")


if __name__ == "__main__":
    if sys.argv[1:2] == ["times"]:
        times(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
