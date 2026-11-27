#!/usr/bin/env python3
"""The Kyushu Shinkansen from Hakata to Kumamoto as the game's real-railway
files (KYUSHU-SHINKANSEN-DATA, for the map's growth south to Kumamoto,
decision 969), in the formats of the Fukuoka City Subway's
(`build_fukuoka_rail.py`, decision 854), whose reading of N02 and
OpenStreetMap it uses.

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py \\
        N02-25_Station.geojson kyushu.pbf tools/fukuoka-map/kyushu-shinkansen

The files are made in `tools/fukuoka-map/kyushu-shinkansen/` and, since
SHINKANSEN-SALE (decision 975), merged from there into the map pack, where
the game reads them as the map's second system:

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge \
        tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

(`merge` needs neither N02 nor OpenStreetMap; `build_fukuoka_rail.py`
writes the pack's railway files with the subway alone, so `merge` is run
again after it.) When only the service changes (`SERVICE`, `FAR_TURN`),
the day's trips are laid out again in each folder without N02 or
OpenStreetMap, before `merge` and `extract_fukuoka_runs.py`:

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py times \
        tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka

Where each part comes from:

- **Stations and their Japanese names**: N02 (2025 edition, CC BY 4.0), the
  seven stations of 九州旅客鉄道's 九州新幹線 from Hakata to Kumamoto, each
  the middle of N02's platform line, in the line's order (`STATIONS`). The
  line has no station numbering: the codes `KS01`–`KS07` are this project's.
- **Track, tunnels and viaducts**: OpenStreetMap (osmtoday.com's Kyushu
  extract, read whole with pyosmium): the `railway=rail`, `highspeed=yes`
  main-line ways whose name has 九州新幹線 (Hakata's platforms and the first
  8 km are shared with the Sanyo Shinkansen's depot line, 博多南線, and named
  for both), joined and walked as the subway's are.
- **The depot**: JR Kyushu's Kumamoto General Rolling Stock Depot (熊本総合
  車両所) at Tomiai, south of Kumamoto: where its lead leaves the main line,
  the lead, and the storage tracks, from OpenStreetMap (`depot.json`). It
  lies 8.45 km past Kumamoto, the end of the stretch on sale, so the game
  lays a depot of its own just past the station
  (`RealLineDepotSite.kumamoto`, decision 975) and `depot.json` is a record.
- **Chinese and English names, the line's colour**: this project's. The
  seven names are the same in traditional characters; the English names are
  JR Kyushu's romaji without macrons, checked against OpenStreetMap's
  `name:en`.
- **Times**: JR Kyushu publishes no open timetable (no GTFS; its timetable
  pages may not be reused). Each day's trips are laid out from headways and
  first and last trains this project estimated (`SERVICE`), every train
  calling at every station (the Tsubame pattern), the seconds between
  stations from the distance and the line's top speed (`run_seconds`);
  `kyushushinkansen_times.json` says it is an estimate. Mizuho and Sakura,
  which pass stations, and the trains running through to Kagoshima-Chuo and
  Shin-Osaka are left out (KYUSHU-SHINKANSEN-EXPRESS, later).
- **Gauge and loading gauge**: 1,435 mm and the Shinkansen's, with 25 kV
  60 Hz overhead wire, written on the line as a record; the game lays the
  line at the gauge `TrackGauge.ofRealLine` names (decision 970).
"""
import collections
import json
import math
import os
import sys

import osmium

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_fukuoka_rail as fk  # noqa: E402

SYSTEM = "kyushushinkansen"
LINE_ID = "KS"
N02_LINE = "九州新幹線"
OPERATOR = "九州旅客鉄道"
# OpenStreetMap's route relation of the line (it has no `colour`).
RELATION = 1565609
# This project's choice: JR Kyushu's red, darker than the Kuko Line's
# orange-red beside it at Hakata.
COLOUR = "#C8102E"
# Hakata to Kumamoto in the line's order: (N02's name, the game's Chinese
# name, the English name).
STATIONS = [
    ("博多", "博多", "Hakata"), ("新鳥栖", "新鳥栖", "Shin-Tosu"), ("久留米", "久留米", "Kurume"),
    ("筑後船小屋", "筑後船小屋", "Chikugo-Funagoya"), ("新大牟田", "新大牟田", "Shin-Omuta"),
    ("新玉名", "新玉名", "Shin-Tamana"), ("熊本", "熊本", "Kumamoto"),
]
# The map after it grows to Kumamoto (decision 969, JAPAN-MAP-GROW's
# handoff): the north and west edges are Fukuoka's.
EXTENT = {"north": 34.03, "south": 32.09, "west": 129.34, "east": 131.33}
# The line's own distance from Hakata to Kumamoto, in km (the construction
# length; the fare distance, 118.4 km, is the old main line's), and how far
# the measured one may differ.
REAL_KM, KM_TOLERANCE = 98.2, 0.02
# What TRACK-GAUGE and TRACK-ELECTRIFICATION will read (nothing does yet).
TRACK = {"gaugeMm": 1435, "loadingGauge": "shinkansen", "electrification": "AC 25 kV 60 Hz overhead",
         "maxSpeedKmh": 260}

# The estimated service (seconds of the day). Off-peak: JR Kyushu's
# timetable since March 2023 has a Sakura or Tsubame leave Hakata for
# Kumamoto at 1 and 36 minutes past each hour of a weekday afternoon (as
# reported, https://www.tetsudo.com/news/629/), so a train every half hour;
# the Mizuho that runs about hourly besides passes every station between
# and is left out with the other fast trains. The peaks' quarter of an hour
# and the first and last trains are this project's estimate. All trains
# here stop everywhere. The depot is at the Kumamoto end, so the day is
# laid out from Kumamoto (decision 898, `build_fukuoka_rail.trips`): no
# train stands at Hakata overnight, 100 km from the depot.
SERVICE = {"peakHeadwaySec": 900, "offpeakHeadwaySec": 1800, "depotEnd": "熊本"}
KUMAMOTO_FIRST, HAKATA_LAST = 6 * 3600, 23 * 3600 + 10 * 60
PEAKS = [[7 * 3600, 9 * 3600 + 30 * 60], [17 * 3600, 19 * 3600 + 30 * 60]]
DWELL = 60
# A Shinkansen's turnaround at Hakata: eight minutes (decision 975). With
# twelve, the train standing there was still waiting for its run when the
# next one, a quarter of an hour behind, set off from Shin-Tosu for the same
# platform under the realistic rules, and the game sent it to the depot as
# a train in the way (decision 297): its run left with the next train, five
# minutes late, all through both peaks (18 runs a day).
FAR_TURN = 480
# `run_seconds`: the line's top speed (260 km/h), how fast a train gains
# and loses it (m/s², an 800 series' in service), and the slack a timetable
# keeps.
TOP_SPEED, RATE, SLACK = 260 / 3.6, 0.45, 1.10

# The depot (OpenStreetMap's `landuse=railway` way 732086837, 熊本総合車両所):
# its tracks lie in this box, and a storage track is a `service=yard` way
# at least this long (a six-car 800 series is 155 m, an eight-car N700 205 m).
DEPOT_AREA = 732086837
DEPOT_BOX = {"north": 32.720, "south": 32.698, "west": 130.665, "east": 130.680}
STORAGE_MIN = 250


def run_seconds(km):
    """Seconds between two stations `km` apart, without the dwell: up to
    the top speed and down again at `RATE` (never reaching it on a short
    stretch), with the timetable's slack. An estimate: Hakata to Kumamoto
    comes to about 48 minutes with the stops, as a Tsubame takes."""
    d = km * 1000
    reach = TOP_SPEED ** 2 / RATE
    seconds = d / TOP_SPEED + TOP_SPEED / RATE if d >= reach else 2 * math.sqrt(d / RATE)
    return int(round(seconds * SLACK))


class Parts(osmium.SimpleHandler):
    """The line's main-line ways (as `build_fukuoka_rail.Parts`), and the
    depot's: every standard-gauge way in its box."""

    def __init__(self):
        super().__init__()
        self.ways, self.named, self.colours = {}, [], {}
        self.depot, self.depot_area = {}, None
        self.newest = ""

    def way(self, w):
        tags = dict(w.tags)
        if w.id == DEPOT_AREA:
            self.depot_area = {"name": tags.get("name"), "points": [(n.lon, n.lat) for n in w.nodes]}
        if tags.get("railway") != "rail":
            return
        nodes = [(n.ref, n.lon, n.lat) for n in w.nodes]
        stamp = w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
        box = DEPOT_BOX
        if (tags.get("gauge") == "1435" or tags.get("highspeed") == "yes") and any(
                box["south"] <= y <= box["north"] and box["west"] <= x <= box["east"] for _, x, y in nodes):
            self.depot[w.id] = {"tags": tags, "nodes": nodes}
            self.newest = max(self.newest, stamp)
        if tags.get("highspeed") != "yes" or N02_LINE not in tags.get("name", ""):
            return
        if tags.get("service") in fk.SKIPPED_SERVICE:
            return
        self.ways[w.id] = {"tags": tags, "nodes": nodes}
        self.newest = max(self.newest, stamp)

    def node(self, n):
        tags = dict(n.tags)
        if "name" in tags and (tags.get("railway") in ("station", "stop") or tags.get("public_transport") in ("station", "stop_position")):
            self.named.append({"name": tags["name"], "en": tags.get("name:en"), "at": (n.location.lon, n.location.lat)})

    def relation(self, r):
        if r.id == RELATION:
            self.colours[r.id] = dict(r.tags).get("colour")


def kind_of(tags):
    return "tunnel" if tags.get("tunnel") not in (None, "no") else "bridge" if tags.get("bridge") not in (None, "no") else None


def length(points):
    return sum(fk.metres(a, b) for a, b in zip(points, points[1:]))


def middle(points):
    return [round(sum(p[0] for p in points) / len(points), 6), round(sum(p[1] for p in points) / len(points), 6)]


def depot_of(parts, line, at):
    """Where the depot's lead leaves the main line south of Kumamoto, the
    lead to the storage tracks, and the storage tracks' two ends."""
    if parts.depot_area is None or parts.depot_area["name"] != "熊本総合車両所":
        sys.exit(f"OpenStreetMap's way {DEPOT_AREA} is no longer the depot: {parts.depot_area}")
    # The storage tracks: the yard's ways of the commonest length.
    yard = {ref: way for ref, way in parts.depot.items() if way["tags"].get("service") == "yard"}
    long = {ref: [(x, y) for _, x, y in way["nodes"]] for ref, way in yard.items()
            if length([(x, y) for _, x, y in way["nodes"]]) >= STORAGE_MIN}
    common = collections.Counter(round(length(p) / 10) for p in long.values()).most_common(1)[0][0]
    storage = {ref: p for ref, p in long.items() if round(length(p) / 10) == common}
    if len(storage) < 6:
        sys.exit(f"the depot has only {len(storage)} storage tracks of one length")
    north = [max(p[0], p[-1], key=lambda q: q[1]) for p in storage.values()]
    south = [min(p[0], p[-1], key=lambda q: q[1]) for p in storage.values()]
    # The lead: from the main line's last point at Kumamoto, along the main
    # line and then the yard's ways, to the storage tracks' nearer end.
    ways = dict(parts.ways)
    ways.update(parts.depot)
    graph, where, way_of = fk.track(type("P", (), {"ways": ways})())
    start = min(at, key=lambda n: fk.metres(at[n], tuple(line["shape"][-1])))
    ends = {ref: way["nodes"][0][0] if way["nodes"][0][2] > way["nodes"][-1][2] else way["nodes"][-1][0]
            for ref, way in parts.depot.items() if ref in storage}
    reached = fk.distances(graph, start, set(ends.values()))
    if not reached:
        sys.exit("no track from Kumamoto to the depot's storage tracks")
    target = min(reached, key=reached.get)
    path = fk.cheapest(graph, start, target)
    leaves = next(i for i, (p, q) in enumerate(zip(path, path[1:])) if way_of[(p, q)] not in parts.ways)
    main, lead = [where[n] for n in path[:leaves + 1]], [where[n] for n in path[leaves:]]
    structures = []
    for p, q in zip(path, path[1:]):
        way = way_of[(p, q)]
        kind = kind_of(ways[way]["tags"])
        if kind is None:
            continue
        if structures and structures[-1]["way"] == way:
            structures[-1]["points"].append([round(where[q][0], 6), round(where[q][1], 6)])
        else:
            structures.append({"way": way, "system": SYSTEM, "kind": kind,
                               "points": [[round(c, 6) for c in where[p]], [round(c, 6) for c in where[q]]]})
    junction = where[path[leaves]]
    for point in [junction] + north + south:
        if not (EXTENT["south"] <= point[1] <= EXTENT["north"] and EXTENT["west"] <= point[0] <= EXTENT["east"]):
            sys.exit(f"the depot's {point} is off the map")
    return {
        "_readme": "JR Kyushu's Kumamoto General Rolling Stock Depot at Tomiai, from OpenStreetMap: where its lead "
                   "leaves the main line (junction, kmFromKumamoto along mainLine), the lead from there to the storage "
                   "tracks (lead), and the storage tracks (storage: how many OpenStreetMap draws, their length, the "
                   "middles of their near (north) and far (south) ends), for RealLineDepotSite. Points are [lon, lat]. "
                   "A record: the game lays its own depot just past Kumamoto (RealLineDepotSite.kumamoto, decision 975). Made by tools/fukuoka-map/build_kyushu_shinkansen.py.",
        "system": SYSTEM, "line": LINE_ID, "end": "熊本",
        "ja": "熊本総合車両所", "name": "熊本綜合車輛所", "english": "Kumamoto General Rolling Stock Depot",
        "osmArea": DEPOT_AREA, "centre": middle(parts.depot_area["points"]),
        "junction": [round(junction[0], 6), round(junction[1], 6)],
        "kmFromKumamoto": round(length(main) / 1000, 3),
        "mainLine": [[round(x, 6), round(y, 6)] for x, y in fk.simplified(main)],
        "lead": [[round(x, 6), round(y, 6)] for x, y in fk.simplified(lead)],
        "leadKm": round(length(lead) / 1000, 3),
        "storage": {"tracks": len(storage), "metres": round(sum(length(p) for p in storage.values()) / len(storage)),
                    "near": middle(north), "far": middle(south), "ways": sorted(storage)},
        "structures": structures,
        **TRACK,
    }


def set_up():
    """`build_fukuoka_rail`'s line building and day's trips, told this line."""
    fk.SYSTEM, fk.OPERATOR, fk.EXTENT = SYSTEM, OPERATOR, EXTENT
    fk.LINES = [(LINE_ID, N02_LINE, "九州新幹線", "Kyushu Shinkansen", RELATION, COLOUR)]
    fk.STATIONS = {LINE_ID: STATIONS}
    fk.SERVICE = {LINE_ID: SERVICE}
    fk.PEAKS, fk.DWELL, fk.FAR_TURN, fk.run_seconds = PEAKS, DWELL, FAR_TURN, run_seconds


def set_day(line):
    """The first and last trains from Hakata, the far end, so that
    Kumamoto's first leaves at `KUMAMOTO_FIRST`."""
    stations = line["stations"]
    lag = sum(run_seconds(b["d"] - a["d"]) + DWELL for a, b in zip(stations, stations[1:])) + FAR_TURN
    fk.FIRST_TRAIN, fk.LAST_TRAIN = KUMAMOTO_FIRST + lag, HAKATA_LAST
    return lag - FAR_TURN


NOTE = ("Stations and their Japanese names: " + fk.MLIT_CREDIT + ". Tracks, tunnels and viaducts: © OpenStreetMap "
        "contributors, ODbL 1.0. Chinese and English names, the colour and times: this project's; JR Kyushu publishes "
        "no open timetable, so each day's trips are laid out from estimated headways, every train calling at every "
        "station, not the operator's timetable.")


def write_times(out, line):
    trips = fk.trips(line)
    fk.write(out, f"{SYSTEM}_times.json", {
        "system": SYSTEM.upper(), "estimated": True,
        "source_notes": "No open timetable (JR Kyushu publishes no GTFS and its timetable pages may not be reused): "
                        "each day's trips are laid out from headways, first and last trains this project estimated "
                        "(off-peak: the half-hourly Sakura and Tsubame of JR Kyushu's timetable since March 2023, as "
                        "reported at https://www.tetsudo.com/news/629/), every train calling at every station, and times between stations worked out from the distance and the line's 260 km/h; "
                        "not the operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日", "sets": {"每日": trips}}},
    })
    return trips


def main(n02_path, extract, out):
    os.makedirs(out, exist_ok=True)
    set_up()
    n02 = fk.n02_stations(n02_path)
    wanted = {s[0] for s in STATIONS}
    # N02's line runs on to Kagoshima-Chuo; the map ends south of Kumamoto.
    n02[LINE_ID] = {name: point for name, point in n02[LINE_ID].items() if name in wanted}
    parts = Parts()
    parts.apply_file(extract, locations=True, filters=[osmium.filter.KeyFilter("railway", "landuse")])
    graph, at, way_of = fk.track(parts)
    line = fk.line_of(fk.LINES[0], n02, parts, graph, at, way_of)
    km = line["stations"][-1]["d"]
    if abs(km - REAL_KM) > REAL_KM * KM_TOLERANCE:
        sys.exit(f"Hakata to Kumamoto measures {km:.2f} km, the line's own length is {REAL_KM} km")
    end_to_end = set_day(line)
    depot = depot_of(parts, line, at)

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_kyushu_shinkansen.py"}
    stations = line["stations"]
    fk.write(out, f"{SYSTEM}.json", {
        "system": SYSTEM.upper(), "source_notes": NOTE,
        "lines": [{
            "id": line["id"], "name": line["chinese"], "color": line["colour"],
            "peakHeadwaySec": SERVICE["peakHeadwaySec"], "offpeakHeadwaySec": SERVICE["offpeakHeadwaySec"],
            "headway_estimated": True,
            **TRACK,
            "stations": [{"name": s["name"], "lat": s["lat"], "lon": s["lon"], "d": s["d"]} for s in stations],
            "shape": [[y, x] for x, y in line["shape"]],
            "segs": [{"run": run_seconds(b["d"] - a["d"])} for a, b in zip(stations, stations[1:])],
            "dwellSec": [DWELL] * len(stations),
        }],
    })
    trips = write_times(out, line)
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
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"], "ja": N02_LINE}}},
    })
    fk.write(out, "rail_structures.json", {
        "_readme": "Where the line of track_lines.geojson is on viaducts and bridges (bridge) or in tunnels (tunnel), "
                   "one OpenStreetMap way each; the rest is on the ground (embankments and cuttings). Made by "
                   "tools/fukuoka-map/build_kyushu_shinkansen.py.",
        "source": {"openStreetMap": osm},
        "structures": line["structures"],
    })
    fk.write(out, "depot.json", depot)

    by_kind = collections.Counter()
    for s in line["structures"]:
        by_kind[s["kind"]] += length(s["points"]) / 1000
    here = os.path.dirname(os.path.abspath(__file__))
    fk.write(here, "kyushu_shinkansen_sources.json", {
        "task": "KYUSHU-SHINKANSEN-DATA", "staged": os.path.relpath(out, os.path.join(here, "..", "..")),
        "inputs": {
            os.path.basename(n02_path): {
                "sha256": fk.sha256(n02_path), "from": "https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip "
                "(UTF-8/N02-25_Station.geojson)", "licence": "CC BY 4.0, " + fk.MLIT_CREDIT},
            os.path.basename(extract): {
                "sha256": fk.sha256(extract), "from": "https://osmtoday.com/asia/japan/kyushu.pbf (whole, not cut)",
                "newestTrackEdit": parts.newest, "licence": "ODbL 1.0, © OpenStreetMap contributors"},
        },
        "line": {"id": line["id"], "osmRelation": RELATION, "stations": len(stations), "km": km, "realKm": REAL_KM,
                 "tunnelKm": round(by_kind["tunnel"], 2), "viaductKm": round(by_kind["bridge"], 2),
                 "groundKm": round(km - by_kind["tunnel"] - by_kind["bridge"], 2),
                 "endToEndSec": end_to_end, "trips": len(trips)},
        "depot": {"kmFromKumamoto": depot["kmFromKumamoto"], "leadKm": depot["leadKm"],
                  "storageTracks": depot["storage"]["tracks"], "storageMetres": depot["storage"]["metres"]},
        "files": {name: os.path.getsize(os.path.join(out, name)) for name in sorted(os.listdir(out)) if name.endswith("json")},
    })
    print(f"{line['id']} {len(stations)} stations {km:.2f} km (the line's own {REAL_KM}) {len(line['shape'])} points; "
          f"tunnels {by_kind['tunnel']:.1f} km, viaducts {by_kind['bridge']:.1f} km; "
          f"{end_to_end // 60} min {end_to_end % 60} s end to end, {len(trips)} trips a day")
    for a, b in zip(stations, stations[1:]):
        print(f"  {a['ja']} → {b['ja']}: {b['d'] - a['d']:6.2f} km, {run_seconds(b['d'] - a['d'])} s")
    print(f"depot: lead leaves the main line {depot['kmFromKumamoto']} km past Kumamoto at {depot['junction']}, "
          f"{depot['leadKm']} km to {depot['storage']['tracks']} storage tracks of {depot['storage']['metres']} m")


# SHINKANSEN-SALE (decision 975): the staged files moved into the map pack.
# The system's own files (their sources are in `build_fukuoka_rail.SOURCES`).
PACK_FILES = (f"{SYSTEM}.json", f"{SYSTEM}_times.json")


# Decision 998: the lines of the system, in the order the pack lists them
# (the Kyushu Shinkansen's, then the Nishi-Kyushu Shinkansen's, staged by
# build_nishi_kyushu_shinkansen.py); and how each line's notes are told
# apart in a file both share.
LINE_ORDER = ("KS", "NK", "RK")
LINE_NOTES = {"KS": " Kyushu Shinkansen: ", "NK": " Nishi-Kyushu Shinkansen: ", "RK": " Relay Kamome: "}
# Decision 1028: the systems `merge` takes a staged line of, by the file
# the staging folder holds: this one's, and the Relay Kamome's JR Kyushu
# conventional line (`build_relay_kamome.py`).
MERGED_SYSTEMS = (SYSTEM, "jrkyushu")


def merge(staged, pack):
    """The staged line into the map pack `pack`, beside the subway's
    (decision 975): its line, trips, stations, names and structures added
    to the pack's `kyushushinkansen.json`, `_times.json`,
    `track_lines.geojson`, `track_stations.geojson`, `station_names.json`
    and `rail_structures.json`, and the files' sizes in `pack.json` written
    again. Run again, it replaces what it added before; the subway's part
    of each file, and decision 998's: the other line's of the system, are
    kept as they were. `depot.json` stays staged (the game's depot is a
    `RealLineDepotSite`). `extract_fukuoka_runs.py` then lays out
    `metro_runs.json` for every system.

    Decision 1028: the staged folder may hold another system's line
    (`MERGED_SYSTEMS`: the Relay Kamome's `jrkyushu.json`), merged the
    same way into that system's files, the other systems' parts of the
    shared files kept as they were."""
    system = next(s for s in MERGED_SYSTEMS if os.path.exists(os.path.join(staged, f"{s}.json")))
    def read(folder, name):
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            return json.load(f)

    def order(line_id):
        return LINE_ORDER.index(line_id) if line_id in LINE_ORDER else len(LINE_ORDER)

    def notes(theirs, ours, line_ids, own=None):
        """`theirs`, a note the lines share, with the notes of `line_ids`
        replaced by `ours`, each line's after its own marker; in the
        system's own files (`own`, the line an unmarked note is of), a
        note of one line alone is that line's, unmarked."""
        head, parts = theirs, {}
        markers = sorted(((theirs.find(mark), line_id) for line_id, mark in LINE_NOTES.items() if mark in theirs))
        if markers:
            head = theirs[:markers[0][0]]
            for (at, line_id), (after, _) in zip(markers, markers[1:] + [(len(theirs), None)]):
                parts[line_id] = theirs[at + len(LINE_NOTES[line_id]):after]
        elif own and theirs:
            head, parts = "", {own: theirs}
        for line_id in line_ids:
            parts[line_id] = ours
        if own and not head and len(parts) == 1:
            return next(iter(parts.values()))
        return head + "".join(LINE_NOTES[k] + parts[k] for k in sorted(parts, key=order))

    system_file, times_file = f"{system}.json", f"{system}_times.json"
    ours = read(staged, system_file)
    added_ids = [line["id"] for line in ours["lines"]]
    own = LINE_ID if system == SYSTEM else added_ids[0]
    if os.path.exists(os.path.join(pack, system_file)):
        theirs, their_times = read(pack, system_file), read(pack, times_file)
    else:
        theirs = dict(ours, lines=[], source_notes="")
        their_times = dict(read(staged, times_file), lines={}, source_notes="")
    theirs["lines"] = sorted([line for line in theirs["lines"] if line["id"] not in added_ids] + ours["lines"],
                             key=lambda line: order(line["id"]))
    theirs["source_notes"] = notes(theirs["source_notes"], ours["source_notes"], added_ids, own=own)
    fk.write(pack, system_file, theirs)
    our_times = read(staged, times_file)
    lines = {k: v for k, v in their_times["lines"].items() if k not in added_ids}
    lines.update(our_times["lines"])
    their_times["lines"] = {k: lines[k] for k in sorted(lines, key=order)}
    their_times["source_notes"] = notes(their_times["source_notes"], our_times["source_notes"], added_ids, own=own)
    fk.write(pack, times_file, their_times)

    def ours_too(properties):
        return properties["sys"] == system and properties.get("id", properties.get("lineId")) in added_ids

    for name in ("track_lines.geojson", "track_stations.geojson"):
        ours, theirs = read(staged, name), read(pack, name)
        kept = [f for f in theirs["features"] if not ours_too(f["properties"])]
        added = ours["features"]
        if name == "track_lines.geojson":
            kept = [f for f in kept if f["properties"]["sys"] != system] + sorted(
                (f for f in kept if f["properties"]["sys"] == system), key=lambda f: order(f["properties"]["id"]))
            added = [dict(f, properties=dict(f["properties"], sortKey=len(kept) + n)) for n, f in enumerate(added)]
        theirs["source"] = notes(theirs["source"], ours["source"], added_ids)
        theirs["features"] = kept + added
        fk.write(pack, name, theirs)
    ours, theirs = read(staged, "station_names.json"), read(pack, "station_names.json")
    theirs["source"] = notes(theirs["source"], ours["source"], added_ids)
    for key in ("systems", "routes"):
        theirs[key][system] = {**theirs[key].get(system, {}), **ours[key][system]}
    fk.write(pack, "station_names.json", theirs)
    ours, theirs = read(staged, "rail_structures.json"), read(pack, "rail_structures.json")
    theirs["structures"] = [s for s in theirs["structures"]
                            if s["system"] != system or s.get("line", "KS") not in added_ids] + ours["structures"]
    theirs["source"][system] = ours["source"]["openStreetMap"]
    fk.write(pack, "rail_structures.json", theirs)
    fk.refresh_manifest(pack)
    print(f"{pack}: {len(read(pack, 'track_lines.geojson')['features'])} lines, "
          f"{len(read(pack, 'track_stations.geojson')['features'])} stations, "
          f"{len(theirs['structures'])} structures")


def times(*folders):
    """SHINKANSEN-SALE (decision 975): the day's trips laid out again in
    each folder's `kyushushinkansen_times.json`, from the line its
    `kyushushinkansen.json` holds (the stations and their distances), when
    only the service changes (`SERVICE`, `FAR_TURN`): neither N02 nor
    OpenStreetMap is read."""
    set_up()
    for folder in folders:
        with open(os.path.join(folder, f"{SYSTEM}.json"), encoding="utf-8") as f:
            stored = json.load(f)["lines"][0]
        line = {"id": LINE_ID, "stations": stored["stations"]}
        set_day(line)
        print(f"{folder}: {len(write_times(folder, line))} trips")


if __name__ == "__main__":
    if sys.argv[1:2] == ["merge"]:
        merge(*sys.argv[2:])
    elif sys.argv[1:2] == ["times"]:
        times(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
