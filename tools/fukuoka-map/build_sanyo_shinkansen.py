#!/usr/bin/env python3
"""The Sanyo Shinkansen (山陽新幹線) from Hakata to Kokura, JR West's, as
the game's real-railway files (decision 1029, SANYO-SHINKANSEN-KOKURA): a
system of its own (`sanyoshinkansen`), so it is sold apart from JR Kyushu's
Kyushu Shinkansen it shares Hakata with, read and laid out as that one's
are (`build_kyushu_shinkansen.py`, decision 975).

    python3 -I tools/fukuoka-map/build_sanyo_shinkansen.py \\
        N02-25_Station.geojson kyushu.pbf tools/fukuoka-map/sanyo-shinkansen

and merged into the map pack beside the others:

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge \\
        tools/fukuoka-map/sanyo-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

When only the service changes (`SERVICE`), the day's trips are laid out
again without N02 or OpenStreetMap:

    python3 -I tools/fukuoka-map/build_sanyo_shinkansen.py times tools/fukuoka-map/sanyo-shinkansen

Where each part comes from:

- **Stations and their Japanese names**: N02 (2025 edition, CC BY 4.0),
  西日本旅客鉄道's 山陽新幹線, its last two stations, Hakata and Kokura, each
  the middle of N02's platform line. The codes `SY01`, `SY02` are this
  project's (the line has no station numbering).
- **Track, tunnels and viaducts**: OpenStreetMap (osmtoday.com's Kyushu
  extract, read whole): the `railway=rail`, `highspeed=yes` main-line ways
  whose name has 山陽新幹線 (Hakata's platform tracks are named for the
  three lines that use them, 山陽新幹線・博多南線・九州新幹線), joined and
  walked as the subway's are.
- **The depot**: none is laid. JR West's Hakata General Rolling Stock
  Depot (博多総合車両所) lies at the end of the Hakata-Minami Line, 8.5 km
  south of Hakata along the Kyushu Shinkansen's own tracks, which the game
  sells as another company's line; north of Kokura the line goes into the
  Shin-Kanmon Tunnel. So the line's trains stand overnight at its two ends
  (decision 816), as the Relay Kamome's (decision 1028).
- **Chinese and English names, the line's colour**: this project's. Both
  names are the same in traditional characters; the colour is JR West's
  blue (OpenStreetMap's relation has none).
- **Times**: JR West publishes no open timetable (no GTFS; its timetable
  pages may not be reused). Each day's trips are laid out from headways and
  first and last trains this project estimated (`SERVICE`), between the
  line's two stations only: the real trains run on to Shin-Osaka and Tokyo
  and through onto the Kyushu Shinkansen (KYUSHU-SHINKANSEN-EXPRESS,
  later). The seconds between the stations come from the distance and the
  line's 300 km/h; `sanyoshinkansen_times.json` says it is an estimate.
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
import build_kyushu_shinkansen as ks  # noqa: E402

SYSTEM = "sanyoshinkansen"
LINE_ID = "SY"
N02_LINE = "山陽新幹線"
OPERATOR = "西日本旅客鉄道"
# OpenStreetMap's route relation of the line (it has no `colour`).
RELATION = 1837932
# This project's choice: JR West's blue, apart from the Kyushu
# Shinkansen's reds beside it at Hakata.
COLOUR = "#0072BC"
# Hakata to Kokura: (N02's name, the game's Chinese name, the English name).
STATIONS = [("博多", "博多", "Hakata"), ("小倉", "小倉", "Kokura")]
EXTENT = ks.EXTENT
# The line's own length from Hakata to Kokura (実キロ; the fare distance,
# 67.2 km, is the old main line's; both as tabi-mag.jp's table of the
# Shinkansen's stations gives them, https://tabi-mag.jp/shinkansen-st/),
# and how far the measured one may differ.
REAL_KM, KM_TOLERANCE = 55.9, 0.03
TRACK = {"gaugeMm": 1435, "loadingGauge": "shinkansen", "electrification": "AC 25 kV 60 Hz overhead",
         "maxSpeedKmh": 300}
# The estimated service (seconds of the day): a train every quarter of
# an hour all day, near the four to six Nozomi, Hikari and Kodama that
# leave Hakata for Kokura in an hour (the Mizuho and Sakura coming off the
# Kyushu Shinkansen are left out with it); the first from Kokura at 6:00
# and the last from Hakata at 23:00, this project's estimate. No depot:
# both ends start their day at once (`build_fukuoka_rail.trips`). Every
# ten minutes in the peaks, four sets turned round in four minutes at each
# end, and the day of the line bought alone had two minutes of deadlock
# and four runs not sent; every twelve, eight minutes, and under the
# realistic rules, the trains slower through the curves than the
# timetable, five runs of the morning peak up to 13 minutes late and its
# longest gap 28 minutes against 12; every fifteen, thirteen.
SERVICE = {"peakHeadwaySec": 900, "offpeakHeadwaySec": 900}
FIRST_TRAIN, LAST_TRAIN = 6 * 3600, 23 * 3600
PEAKS = [[7 * 3600, 9 * 3600 + 30 * 60], [17 * 3600, 19 * 3600 + 30 * 60]]
DWELL = 60
# `run_seconds`: the line's top speed (300 km/h, the N700's on the Sanyo
# Shinkansen), how fast a train gains and loses it (m/s², as the Kyushu
# Shinkansen's), and the timetable's slack.
TOP_SPEED, RATE, SLACK = 300 / 3.6, 0.45, 1.10


def run_seconds(km):
    """Seconds between two stations `km` apart, without the dwell, as
    `build_kyushu_shinkansen.run_seconds` works them out. An estimate:
    Hakata to Kokura comes to about 16 minutes, as a Nozomi takes (15 to
    17; a Kodama 17 to 19)."""
    d = km * 1000
    reach = TOP_SPEED ** 2 / RATE
    seconds = d / TOP_SPEED + TOP_SPEED / RATE if d >= reach else 2 * math.sqrt(d / RATE)
    return int(round(seconds * SLACK))


class Parts(osmium.SimpleHandler):
    """The line's main-line ways (as `build_fukuoka_rail.Parts`)."""

    def __init__(self):
        super().__init__()
        self.ways, self.named, self.colours = {}, [], {}
        self.newest = ""

    def way(self, w):
        tags = dict(w.tags)
        if tags.get("railway") != "rail" or tags.get("highspeed") != "yes" or N02_LINE not in tags.get("name", ""):
            return
        if tags.get("service") in fk.SKIPPED_SERVICE:
            return
        self.ways[w.id] = {"tags": tags, "nodes": [(n.ref, n.lon, n.lat) for n in w.nodes]}
        self.newest = max(self.newest, w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"))

    def node(self, n):
        tags = dict(n.tags)
        if "name" in tags and (tags.get("railway") in ("station", "stop") or tags.get("public_transport") in ("station", "stop_position")):
            self.named.append({"name": tags["name"], "en": tags.get("name:en"), "at": (n.location.lon, n.location.lat)})

    def relation(self, r):
        if r.id == RELATION:
            self.colours[r.id] = dict(r.tags).get("colour")


def set_up():
    """`build_fukuoka_rail`'s line building and day's trips, told this line."""
    fk.SYSTEM, fk.OPERATOR, fk.EXTENT = SYSTEM, OPERATOR, EXTENT
    fk.LINES = [(LINE_ID, N02_LINE, "山陽新幹線", "Sanyo Shinkansen", RELATION, COLOUR)]
    fk.STATIONS = {LINE_ID: STATIONS}
    fk.SERVICE = {LINE_ID: SERVICE}
    fk.PEAKS, fk.DWELL, fk.run_seconds = PEAKS, DWELL, run_seconds
    fk.FIRST_TRAIN, fk.LAST_TRAIN = FIRST_TRAIN, LAST_TRAIN


NOTE = ("Stations and their Japanese names: " + fk.MLIT_CREDIT + ". Tracks, tunnels and viaducts: © OpenStreetMap "
        "contributors, ODbL 1.0. Chinese and English names, the colour and times: this project's; JR West publishes "
        "no open timetable, so each day's trips are laid out from estimated headways between Hakata and Kokura, not "
        "the operator's timetable.")


def write_times(out, line):
    trips = fk.trips(line)
    fk.write(out, f"{SYSTEM}_times.json", {
        "system": SYSTEM.upper(), "estimated": True,
        "source_notes": "No open timetable (JR West publishes no GTFS and its timetable pages may not be reused): "
                        "each day's trips are laid out from headways, first and last trains this project estimated "
                        "(about as many trains an hour as leave Hakata for Kokura), between Hakata and Kokura only, "
                        "and the time between them worked out from the distance and the line's 300 km/h; not the "
                        "operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日", "sets": {"每日": trips}}},
    })
    return trips


def main(n02_path, extract, out):
    os.makedirs(out, exist_ok=True)
    set_up()
    n02 = fk.n02_stations(n02_path)
    wanted = {s[0] for s in STATIONS}
    # N02's line runs on to Shin-Osaka; the map ends at the Kanmon Straits.
    n02[LINE_ID] = {name: point for name, point in n02[LINE_ID].items() if name in wanted}
    parts = Parts()
    parts.apply_file(extract, locations=True, filters=[osmium.filter.KeyFilter("railway", "type")])
    graph, at, way_of = fk.track(parts)
    line = fk.line_of(fk.LINES[0], n02, parts, graph, at, way_of)
    km = line["stations"][-1]["d"]
    if abs(km - REAL_KM) > REAL_KM * KM_TOLERANCE:
        sys.exit(f"Hakata to Kokura measures {km:.2f} km, the line's own length is {REAL_KM} km")

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_sanyo_shinkansen.py"}
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
                   "tools/fukuoka-map/build_sanyo_shinkansen.py.",
        "source": {"openStreetMap": osm},
        "structures": [dict(s, line=LINE_ID) for s in line["structures"]],
    })

    by_kind = collections.Counter()
    for s in line["structures"]:
        by_kind[s["kind"]] += ks.length(s["points"]) / 1000
    end_to_end = run_seconds(km)
    here = os.path.dirname(os.path.abspath(__file__))
    fk.write(here, "sanyo_shinkansen_sources.json", {
        "task": "SANYO-SHINKANSEN-KOKURA", "decision": 1029, "staged": os.path.relpath(out, os.path.join(here, "..", "..")),
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
        "files": {name: os.path.getsize(os.path.join(out, name)) for name in sorted(os.listdir(out)) if name.endswith("json")},
    })
    print(f"{line['id']} {len(stations)} stations {km:.2f} km (the line's own {REAL_KM}) {len(line['shape'])} points; "
          f"tunnels {by_kind['tunnel']:.1f} km, viaducts {by_kind['bridge']:.1f} km; "
          f"{end_to_end // 60} min {end_to_end % 60} s end to end, {len(trips)} trips a day")


def times(*folders):
    """The day's trips laid out again in each folder's
    `sanyoshinkansen_times.json` from the line its `sanyoshinkansen.json`
    holds, when only the service changes: neither N02 nor OpenStreetMap is
    read."""
    set_up()
    for folder in folders:
        with open(os.path.join(folder, f"{SYSTEM}.json"), encoding="utf-8") as f:
            stored = json.load(f)["lines"][0]
        line = {"id": LINE_ID, "stations": stored["stations"]}
        print(f"{folder}: {len(write_times(folder, line))} trips")


if __name__ == "__main__":
    if sys.argv[1:2] == ["times"]:
        times(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
