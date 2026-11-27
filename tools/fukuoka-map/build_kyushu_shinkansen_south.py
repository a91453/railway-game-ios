#!/usr/bin/env python3
"""The Kyushu Shinkansen south of Kumamoto, Kumamoto to Shin-Minamata
(decision 1030, KYUSHU-SHINKANSEN-MINAMATA), as the game's real-railway
files: a third line, `KS2`, of the Kyushu Shinkansen's system
(`build_kyushu_shinkansen.py`, decision 975), read and laid out as the
Hakata to Kumamoto line `KS` and the Nishi-Kyushu Shinkansen `NK`
(`build_nishi_kyushu_shinkansen.py`, decision 998) are.

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen_south.py \\
        N02-25_Station.geojson kyushu.pbf tools/fukuoka-map/kyushu-shinkansen-south

and merged into the map pack beside them (its own line in the system's
files; `KS` and `NK` kept as they are):

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge \\
        tools/fukuoka-map/kyushu-shinkansen-south RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

When only the service changes (`SERVICE`, `FAR_TURN`), the day's trips
are laid out again without N02 or OpenStreetMap:

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen_south.py times \\
        tools/fukuoka-map/kyushu-shinkansen-south

Where each part comes from:

- **Stations and their Japanese names**: N02 (2025 edition, CC BY 4.0),
  九州旅客鉄道's 九州新幹線 from Kumamoto to Shin-Minamata, the last
  station before the map's south edge (32.09N; Izumi, the next, is at
  32.08N). Codes go on from the Kyushu Shinkansen's: Kumamoto is `KS07`,
  Shin-Yatsushiro `KS08`, Shin-Minamata `KS09` (this project's; the line
  has no station numbering).
- **Track, tunnels and viaducts**: OpenStreetMap (osmtoday.com's Kyushu
  extract, read whole): the `railway=rail`, `highspeed=yes` main-line ways
  named 九州新幹線, from Kumamoto south.
- **The depot**: JR Kyushu's Kumamoto General Rolling Stock Depot (熊本総合
  車両所) at Tomiai, whose lead leaves this line 8.45 km south of Kumamoto
  (`depot.json`, the same record `build_kyushu_shinkansen.py` writes).
- **Chinese and English names**: this project's. 新水俣's 俣 is written
  俁 in traditional Chinese (水俁); 新八代 is the same. The English names
  are JR Kyushu's romaji.
- **Times**: JR Kyushu publishes no open timetable (no GTFS; its timetable
  pages may not be reused). The counts are its station timetables' of
  Friday 2026-11-27, as the owner's research of that day gathered them:
  21 trains a day call at Shin-Yatsushiro and Shin-Minamata toward
  Kagoshima-Chuo (14 Sakura, 7 Tsubame) and 23 toward Hakata, none to two
  an hour in the day; the Mizuho pass both. Since 2026-09-18 the stretch
  runs to a timetable JR Kyushu calls temporary (当面の間), slower near
  Shin-Yatsushiro, after it was closed from 2026-07-28. This line runs
  them as a service of its own from Kumamoto, hourly in the day and
  half-hourly in the peaks (21 each way), every train calling at both
  stations, the seconds between stations from the distance and the
  line's 260 km/h (`build_kyushu_shinkansen.run_seconds`). The trains
  running through from Hakata and on to Kagoshima-Chuo, and the Sakura
  that pass one of the two, are left out. `kyushushinkansen_times.json`
  says it is an estimate.
- **Gauge and loading gauge**: 1,435 mm and the Shinkansen's, with 25 kV
  60 Hz overhead wire, as the Kyushu Shinkansen's.
"""
import json
import os
import sys

import osmium

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_fukuoka_rail as fk  # noqa: E402
import build_kyushu_shinkansen as ks  # noqa: E402

SYSTEM = ks.SYSTEM
LINE_ID = "KS2"
N02_LINE = ks.N02_LINE
RELATION = ks.RELATION
COLOUR = ks.COLOUR
STATIONS = [
    ("熊本", "熊本", "Kumamoto"), ("新八代", "新八代", "Shin-Yatsushiro"), ("新水俣", "新水俁", "Shin-Minamata"),
]
# The codes, going on from the Kyushu Shinkansen's KS01 (Hakata) to KS07
# (Kumamoto).
CODES = ["KS07", "KS08", "KS09"]
# The line's own length: Kumamoto 98.2 km from Hakata, Shin-Minamata 172.8
# (実キロ, Japanese Wikipedia's 九州新幹線 station list, checked
# 2026-11-27); the fare distances are 118.4 and 194.1.
REAL_KM, KM_TOLERANCE = 74.6, 0.02
TRACK = dict(ks.TRACK)
# The service: hourly in the day, half-hourly in the peaks, from Kumamoto
# (where the depot is, `depotEnd`) from 6:00 until the last from
# Shin-Minamata at 23:00: 21 trains each way, as many as call at both
# stations toward Kagoshima-Chuo on a weekday (23 toward Hakata).
# Shin-Minamata's turnaround: eighteen minutes, so the trains turn
# round at the two ends alike (18 minutes at Kumamoto in the peaks, three
# sets for the half-hourly service). With ten, a train stood 26 minutes
# at Kumamoto and the next came in three minutes after it left: under
# the realistic rules the one standing was in the way of the next one's
# route and went the 8 km to the depot and back, 12 minutes late, at
# every half past (decision 1030).
SERVICE = {"peakHeadwaySec": 1800, "offpeakHeadwaySec": 3600, "depotEnd": "熊本"}
KUMAMOTO_FIRST, MINAMATA_LAST = 6 * 3600, 23 * 3600
PEAKS = ks.PEAKS
DWELL = ks.DWELL
FAR_TURN = 1080


def set_up():
    fk.SYSTEM, fk.OPERATOR, fk.EXTENT = SYSTEM, ks.OPERATOR, ks.EXTENT
    fk.LINES = [(LINE_ID, N02_LINE, "九州新幹線（新水俁）", "Kyushu Shinkansen (Shin-Minamata)", RELATION, COLOUR)]
    fk.STATIONS = {LINE_ID: STATIONS}
    fk.SERVICE = {LINE_ID: SERVICE}
    fk.PEAKS, fk.DWELL, fk.FAR_TURN, fk.run_seconds = PEAKS, DWELL, FAR_TURN, ks.run_seconds


def set_day(line):
    """The first train from Shin-Minamata (the far end) so that
    Kumamoto's first leaves at `KUMAMOTO_FIRST`, and the last from
    Shin-Minamata."""
    stations = line["stations"]
    lag = sum(ks.run_seconds(b["d"] - a["d"]) + DWELL for a, b in zip(stations, stations[1:])) + FAR_TURN
    fk.FIRST_TRAIN, fk.LAST_TRAIN = KUMAMOTO_FIRST + lag, MINAMATA_LAST
    return lag - FAR_TURN


NOTE = ("Stations and their Japanese names: " + fk.MLIT_CREDIT + ". Tracks, tunnels and viaducts: © OpenStreetMap "
        "contributors, ODbL 1.0. Chinese and English names, the colour and times: this project's; JR Kyushu publishes "
        "no open timetable, so each day's trips are laid out from estimated headways, every train calling at every "
        "station, not the operator's timetable.")


def times_of(line):
    trips = fk.trips(line)
    return trips, {
        "system": SYSTEM.upper(), "estimated": True,
        "source_notes": "No open timetable (JR Kyushu publishes no GTFS and its timetable pages may not be reused): "
                        "each day's trips are laid out from headways this project estimated to come near the "
                        "counts of JR Kyushu's station timetables of 2026-11-27 (21 Sakura and Tsubame a day call at "
                        "Shin-Yatsushiro and Shin-Minamata toward Kagoshima-Chuo, 23 toward Hakata; the Mizuho pass "
                        "both), every train calling at every station, "
                        "and times between stations worked out from the distance and the line's 260 km/h; not the "
                        "operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日", "sets": {"每日": trips}}},
    }


def start_where_hakata_kumamoto_ends(line):
    """Kumamoto where Hakata to Kumamoto has it (`kyushu-shinkansen/`,
    `build_kyushu_shinkansen.py`): `fk.line_of` puts each end on the node
    that makes the line shortest, so Hakata to Kumamoto's Kumamoto is the
    north end of N02's 210 m platform line and this line's was its south
    end, and the two lines' platforms were laid one after the other along
    the track, 25 m apart, instead of side by side (decision 1030). The
    way between the two points is the one OpenStreetMap way, 705285309,
    on the viaduct, that both lines' first structure is."""
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "kyushu-shinkansen", f"{SYSTEM}.json"), encoding="utf-8") as f:
        north = json.load(f)["lines"][0]
    kumamoto = next(s for s in north["stations"] if s["name"] == "熊本")
    point = (kumamoto["lon"], kumamoto["lat"])
    first = line["stations"][0]
    assert first["name"] == "熊本"
    gap = fk.metres(point, line["shape"][0]) / 1000
    if gap < 0.001:
        return
    line["shape"].insert(0, list(point))
    first["lon"], first["lat"] = point
    for station in line["stations"][1:]:
        station["d"] = round(station["d"] + gap, 4)
    structure = line["structures"][0]
    assert structure["way"] == 705285309 and structure["points"][0] == line["shape"][1], structure
    structure["points"].insert(0, list(point))


def main(n02_path, extract, out):
    os.makedirs(out, exist_ok=True)
    set_up()
    n02 = fk.n02_stations(n02_path)
    wanted = {s[0] for s in STATIONS}
    # N02's line runs from Hakata to Kagoshima-Chuo.
    n02[LINE_ID] = {name: point for name, point in n02[LINE_ID].items() if name in wanted}
    parts = ks.Parts()
    parts.apply_file(extract, locations=True, filters=[osmium.filter.KeyFilter("railway", "landuse")])
    # `ks.Parts` keeps every way whose name holds 九州新幹線, the
    # Nishi-Kyushu Shinkansen's (西九州新幹線) too: those are left out.
    parts.ways = {ref: way for ref, way in parts.ways.items() if "西九州新幹線" not in way["tags"].get("name", "")}
    graph, at, way_of = fk.track(parts)
    line = fk.line_of(fk.LINES[0], n02, parts, graph, at, way_of)
    start_where_hakata_kumamoto_ends(line)
    for station, code in zip(line["stations"], CODES):
        station["code"] = code
    km = line["stations"][-1]["d"]
    if abs(km - REAL_KM) > REAL_KM * KM_TOLERANCE:
        sys.exit(f"Kumamoto to Shin-Minamata measures {km:.2f} km, the line's own length is {REAL_KM} km")
    end_to_end = set_day(line)
    # The depot: from Kumamoto, this line's first station, along it to the
    # depot's storage tracks (`ks.depot_of` walks from a line's last
    # point; Kumamoto is the Hakata to Kumamoto line's).
    depot = ks.depot_of(parts, {"shape": line["shape"][:1]}, at)
    depot["line"] = LINE_ID
    depot["_readme"] = depot["_readme"].replace(
        "A record: the game lays its own depot just past Kumamoto (RealLineDepotSite.kumamoto, decision 975).",
        "Laid with Kumamoto to Shin-Minamata (RealLineDepotSite.tomiai, decision 1030).").replace(
        "build_kyushu_shinkansen.py", "build_kyushu_shinkansen_south.py")

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_kyushu_shinkansen_south.py"}
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
            "segs": [{"run": ks.run_seconds(b["d"] - a["d"])} for a, b in zip(stations, stations[1:])],
            "dwellSec": [DWELL] * len(stations),
        }],
    })
    trips, times = times_of(line)
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
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"], "ja": N02_LINE}}},
    })
    fk.write(out, "rail_structures.json", {
        "_readme": "Where the line of track_lines.geojson is on viaducts and bridges (bridge) or in tunnels (tunnel), "
                   "one OpenStreetMap way each; the rest is on the ground (embankments and cuttings). Made by "
                   "tools/fukuoka-map/build_kyushu_shinkansen_south.py.",
        "source": {"openStreetMap": osm},
        "structures": [dict(s, line=LINE_ID) for s in line["structures"]],
    })
    fk.write(out, "depot.json", depot)

    by_kind = {"tunnel": 0.0, "bridge": 0.0}
    for s in line["structures"]:
        by_kind[s["kind"]] += ks.length(s["points"]) / 1000
    here = os.path.dirname(os.path.abspath(__file__))
    fk.write(here, "kyushu_shinkansen_south_sources.json", {
        "task": "KYUSHU-SHINKANSEN-MINAMATA", "decision": 1030,
        "staged": os.path.relpath(out, os.path.join(here, "..", "..")),
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
        "depot": {"junction": depot["junction"], "kmFromKumamoto": depot["kmFromKumamoto"], "leadKm": depot["leadKm"],
                  "storageTracks": depot["storage"]["tracks"], "storageMetres": depot["storage"]["metres"]},
        "files": {name: os.path.getsize(os.path.join(out, name)) for name in sorted(os.listdir(out)) if name.endswith("json")},
    })
    print(f"{line['id']} {len(stations)} stations {km:.2f} km (the line's own {REAL_KM}) {len(line['shape'])} points; "
          f"tunnels {by_kind['tunnel']:.1f} km, viaducts {by_kind['bridge']:.1f} km; "
          f"{end_to_end // 60} min {end_to_end % 60} s end to end, {len(trips)} trips a day")
    for a, b in zip(stations, stations[1:]):
        print(f"  {a['ja']} → {b['ja']}: {b['d'] - a['d']:6.2f} km, {ks.run_seconds(b['d'] - a['d'])} s")
    print(f"depot: lead leaves the line {depot['kmFromKumamoto']} km past Kumamoto at {depot['junction']}, "
          f"{depot['leadKm']} km to {depot['storage']['tracks']} storage tracks of {depot['storage']['metres']} m")


def times(*folders):
    """The day's trips laid out again in each folder's
    `kyushushinkansen_times.json` (its line `KS2` alone) from the line its
    `kyushushinkansen.json` holds, when only the service changes."""
    set_up()
    for folder in folders:
        with open(os.path.join(folder, f"{SYSTEM}.json"), encoding="utf-8") as f:
            stored = next(line for line in json.load(f)["lines"] if line["id"] == LINE_ID)
        line = {"id": LINE_ID, "stations": stored["stations"]}
        set_day(line)
        trips, value = times_of(line)
        path = os.path.join(folder, f"{SYSTEM}_times.json")
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
        if set(old["lines"]) != {LINE_ID}:
            old["lines"][LINE_ID] = value["lines"][LINE_ID]
            value = old
        fk.write(folder, f"{SYSTEM}_times.json", value)
        print(f"{folder}: {len(trips)} trips")


if __name__ == "__main__":
    if sys.argv[1:2] == ["times"]:
        times(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
