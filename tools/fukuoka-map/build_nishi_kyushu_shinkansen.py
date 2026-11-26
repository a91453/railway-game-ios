#!/usr/bin/env python3
"""The West Kyushu Shinkansen (西九州新幹線) from Takeo-Onsen to Nagasaki
as the game's real-railway files (decision 998, NISHI-KYUSHU-SALE), a
second line of the Kyushu Shinkansen's system (`build_kyushu_shinkansen.py`,
decision 975), JR Kyushu's too, read and laid out the same way.

    python3 -I tools/fukuoka-map/build_nishi_kyushu_shinkansen.py \\
        N02-25_Station.geojson kyushu.pbf tools/fukuoka-map/nishi-kyushu-shinkansen

and merged into the map pack beside the Kyushu Shinkansen (its own line,
`NK`, in the system's files; the Kyushu Shinkansen's line `KS` kept as it
is):

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge \\
        tools/fukuoka-map/nishi-kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

When only the service changes (`SERVICE`, `FAR_TURN`), the day's trips
are laid out again without N02 or OpenStreetMap:

    python3 -I tools/fukuoka-map/build_nishi_kyushu_shinkansen.py times \\
        tools/fukuoka-map/nishi-kyushu-shinkansen

Where each part comes from:

- **Stations and their Japanese names**: N02 (2025 edition, CC BY 4.0), the
  five stations of 九州旅客鉄道's 西九州新幹線, each the middle of N02's
  platform line. The line has no station numbering: `NK01`–`NK05` are this
  project's.
- **Track, tunnels and viaducts**: OpenStreetMap (osmtoday.com's Kyushu
  extract, read whole): the `railway=rail`, `highspeed=yes` main-line ways
  named 西九州新幹線 (route relation 7356208).
- **The depot**: JR Kyushu's Ōmura depot (大村車両基地, `landuse=railway`
  way 784642936), beside the line between Ureshino-Onsen and Shin-Ōmura:
  where its lead leaves the main line and its yard (`depot.json`), kept for
  later: the game does not lay it yet, its three sets spending the night at
  Nagasaki (decision 998).
- **Chinese and English names, the line's colour**: this project's.
- **Times**: JR Kyushu publishes no open timetable (no GTFS; its timetable
  pages may not be reused). The day is laid out from headways this project
  set to come near the published counts (22 Kamome each way a day, the
  first from Nagasaki at 6:17, the last from Takeo-Onsen at 23:17, an hourly
  train in the middle of the day and about every half hour in the evening:
  Japanese Wikipedia's かもめ (列車) and the timetable of 2026-03-14 as
  reported at https://jr-shinkansen.net/articles/kamome-timetable/), every
  train calling at every station (13 of the real 22 do; the others pass
  Ureshino-Onsen or Shin-Ōmura), the seconds between stations from the
  distance and the line's 260 km/h. `kyushushinkansen_times.json` says it
  is an estimate.
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
LINE_ID = "NK"
N02_LINE = "西九州新幹線"
RELATION = 7356208
# This project's choice: a deeper red than the Kyushu Shinkansen's, the
# Kamome's own red stripe.
COLOUR = "#A6192E"
STATIONS = [
    ("武雄温泉", "武雄溫泉", "Takeo-Onsen"), ("嬉野温泉", "嬉野溫泉", "Ureshino-Onsen"),
    ("新大村", "新大村", "Shin-Omura"), ("諫早", "諫早", "Isahaya"), ("長崎", "長崎", "Nagasaki"),
]
# The line's own length (実キロ; the fare distance is 69.6 km).
REAL_KM, KM_TOLERANCE = 66.0, 0.02
TRACK = dict(ks.TRACK)
# The service: an hourly train in the middle of the day, every half hour
# in the morning and evening peaks, the day laid out from Nagasaki
# (decision 898's way: no train stands overnight at Takeo-Onsen, where the
# shinkansen has two tracks and the Relay Kamome waits across the
# platform). Takeo-Onsen's turnaround is the real one, a quarter of an
# hour: the first Kamome arrives at 6:48 and leaves again at 7:03, after
# the Relay Kamome from Hakata.
SERVICE = {"peakHeadwaySec": 1800, "offpeakHeadwaySec": 3600, "depotEnd": "長崎"}
NAGASAKI_FIRST, TAKEO_LAST = 6 * 3600 + 17 * 60, 23 * 3600 + 17 * 60
PEAKS = [[7 * 3600, 8 * 3600 + 30 * 60], [17 * 3600, 20 * 3600]]
DWELL = ks.DWELL
FAR_TURN = 900

# The depot (OpenStreetMap's way 784642936): its yard's tracks lie in this
# box, the lead leaving the main line at its south end.
DEPOT_AREA = 784642936
DEPOT_BOX = {"north": 32.9590, "south": 32.9400, "west": 129.9430, "east": 129.9535}


def set_up():
    fk.SYSTEM, fk.OPERATOR, fk.EXTENT = SYSTEM, ks.OPERATOR, ks.EXTENT
    fk.LINES = [(LINE_ID, N02_LINE, "西九州新幹線", "Nishi-Kyushu Shinkansen", RELATION, COLOUR)]
    fk.STATIONS = {LINE_ID: STATIONS}
    fk.SERVICE = {LINE_ID: SERVICE}
    fk.PEAKS, fk.DWELL, fk.FAR_TURN, fk.run_seconds = PEAKS, DWELL, FAR_TURN, ks.run_seconds
    ks.N02_LINE, ks.DEPOT_AREA, ks.DEPOT_BOX = N02_LINE, DEPOT_AREA, DEPOT_BOX


def set_day(line):
    """The first train from Takeo-Onsen (the far end) so that Nagasaki's
    first leaves at `NAGASAKI_FIRST`, and the last from Takeo-Onsen."""
    stations = line["stations"]
    lag = sum(ks.run_seconds(b["d"] - a["d"]) + DWELL for a, b in zip(stations, stations[1:])) + FAR_TURN
    fk.FIRST_TRAIN, fk.LAST_TRAIN = NAGASAKI_FIRST + lag, TAKEO_LAST
    return lag - FAR_TURN


NOTE = ("Stations and their Japanese names: " + fk.MLIT_CREDIT + ". Tracks, tunnels and viaducts: © OpenStreetMap "
        "contributors, ODbL 1.0. Chinese and English names, the colour and times: this project's; JR Kyushu publishes "
        "no open timetable, so each day's trips are laid out from headways set near the published counts, every "
        "train calling at every station, not the operator's timetable.")


def times_of(line):
    trips = fk.trips(line)
    return trips, {
        "system": SYSTEM.upper(), "estimated": True,
        "source_notes": "No open timetable (JR Kyushu publishes no GTFS and its timetable pages may not be reused): "
                        "each day's trips are laid out from headways this project set near the published counts "
                        "(22 Kamome each way, the first from Nagasaki at 6:17, the last from Takeo-Onsen at 23:17, "
                        "as reported at https://jr-shinkansen.net/articles/kamome-timetable/), every train calling "
                        "at every station, and times between stations worked out from the distance and the line's "
                        "260 km/h; not the operator's timetable.",
        "lines": {line["id"]: {"days": ["每日"] * 7, "holiday": "每日", "sets": {"每日": trips}}},
    }


def depot_of(parts, line, at, graph, where, way_of):
    """The Ōmura depot: where its lead leaves the main line, the lead to
    its yard, and the yard's two ends (the middles of its storage
    tracks' near and far ends)."""
    if parts.depot_area is None or "大村車両基地" not in (parts.depot_area["name"] or ""):
        sys.exit(f"OpenStreetMap's way {DEPOT_AREA} is no longer the depot: {parts.depot_area}")
    yard = {ref: [(x, y) for _, x, y in way["nodes"]] for ref, way in parts.depot.items()
            if way["tags"].get("service") == "yard"}
    # The storage tracks: the yard's ways at least a six-car set long.
    storage = {ref: p for ref, p in yard.items() if ks.length(p) >= 160}
    if len(storage) < 2:
        sys.exit(f"the depot has only {len(storage)} tracks a train long")
    north = [max(p[0], p[-1], key=lambda q: q[1]) for p in storage.values()]
    south = [min(p[0], p[-1], key=lambda q: q[1]) for p in storage.values()]
    # The lead: the main-line node the yard's ways reach, nearest Shin-Ōmura.
    on_line = {n for n in at}
    joins = [n for ref, way in parts.depot.items() for n, _, _ in way["nodes"] if n in on_line and ref not in parts.ways]
    if not joins:
        sys.exit("no yard way joins the main line")
    junction = min(joins, key=lambda n: at[n][1])
    return {
        "_readme": "JR Kyushu's Ōmura depot (大村車両基地), from OpenStreetMap: where its lead leaves the main line "
                   "(junction), and its storage tracks (storage: how many OpenStreetMap draws a six-car set long, "
                   "their length, the middles of their south and north ends), for RealLineDepotSite.omura. Points are "
                   "[lon, lat]. Made by tools/fukuoka-map/build_nishi_kyushu_shinkansen.py.",
        "system": SYSTEM, "line": LINE_ID,
        "ja": "大村車両基地", "name": "大村車輛基地", "english": "Omura Depot",
        "osmArea": DEPOT_AREA, "centre": ks.middle(parts.depot_area["points"]),
        "junction": [round(at[junction][0], 6), round(at[junction][1], 6)],
        "storage": {"tracks": len(storage), "metres": round(sum(ks.length(p) for p in storage.values()) / len(storage)),
                    "south": ks.middle(south), "north": ks.middle(north), "ways": sorted(storage)},
        **TRACK,
    }


def main(n02_path, extract, out):
    os.makedirs(out, exist_ok=True)
    set_up()
    n02 = fk.n02_stations(n02_path)
    parts = ks.Parts()
    parts.apply_file(extract, locations=True, filters=[osmium.filter.KeyFilter("railway", "landuse")])
    # `ks.Parts` keeps every way whose name holds 西九州新幹線; the Kyushu
    # Shinkansen's are named 九州新幹線 and left out here.
    parts.ways = {ref: way for ref, way in parts.ways.items() if N02_LINE in way["tags"].get("name", "")}
    graph, at, way_of = fk.track(parts)
    line = fk.line_of(fk.LINES[0], n02, parts, graph, at, way_of)
    km = line["stations"][-1]["d"]
    if abs(km - REAL_KM) > REAL_KM * KM_TOLERANCE:
        sys.exit(f"Takeo-Onsen to Nagasaki measures {km:.2f} km, the line's own length is {REAL_KM} km")
    end_to_end = set_day(line)
    depot = depot_of(parts, line, at, graph, at, way_of)

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_nishi_kyushu_shinkansen.py"}
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
                   "tools/fukuoka-map/build_nishi_kyushu_shinkansen.py.",
        "source": {"openStreetMap": osm},
        "structures": [dict(s, line=LINE_ID) for s in line["structures"]],
    })
    fk.write(out, "depot.json", depot)

    by_kind = {"tunnel": 0.0, "bridge": 0.0}
    for s in line["structures"]:
        by_kind[s["kind"]] += ks.length(s["points"]) / 1000
    here = os.path.dirname(os.path.abspath(__file__))
    fk.write(here, "nishi_kyushu_shinkansen_sources.json", {
        "task": "NISHI-KYUSHU-SALE", "decision": 998, "staged": os.path.relpath(out, os.path.join(here, "..", "..")),
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
        "depot": {"junction": depot["junction"], "storageTracks": depot["storage"]["tracks"],
                  "storageMetres": depot["storage"]["metres"]},
        "files": {name: os.path.getsize(os.path.join(out, name)) for name in sorted(os.listdir(out)) if name.endswith("json")},
    })
    print(f"{line['id']} {len(stations)} stations {km:.2f} km (the line's own {REAL_KM}) {len(line['shape'])} points; "
          f"tunnels {by_kind['tunnel']:.1f} km, viaducts {by_kind['bridge']:.1f} km; "
          f"{end_to_end // 60} min {end_to_end % 60} s end to end, {len(trips)} trips a day")
    for a, b in zip(stations, stations[1:]):
        print(f"  {a['ja']} → {b['ja']}: {b['d'] - a['d']:6.2f} km, {ks.run_seconds(b['d'] - a['d'])} s")
    print(f"depot: lead leaves the main line at {depot['junction']}, {depot['storage']['tracks']} storage tracks "
          f"of {depot['storage']['metres']} m")


def times(*folders):
    """The day's trips laid out again in each folder's
    `kyushushinkansen_times.json` (its line `NK` alone) from the line its
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
