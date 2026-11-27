#!/usr/bin/env python3
"""The Kumamoto City Tram (熊本市電), Lines A and B, as the game's
real-railway files (decision 1041, KUMAMOTO-TRAM): street trams on
1,435 mm track, a system of their own (`kumamotocity`) on Japan's map,
read and laid out as the Relay Kamome's are (`build_relay_kamome.py`),
with the operator's own timetable.

    python3 -I tools/fukuoka-map/build_kumamoto_tram.py \\
        <unzipped GTFS folder> kyushu.pbf tools/fukuoka-map/kumamoto-tram

and merged into the map pack beside the other systems':

    python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge \\
        tools/fukuoka-map/kumamoto-tram RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

When only the timetable changes (a new GTFS), the day's trips are laid out
again without OpenStreetMap:

    python3 -I tools/fukuoka-map/build_kumamoto_tram.py times \\
        <unzipped GTFS folder> tools/fukuoka-map/kumamoto-tram

Where each part comes from:

- **Stops, their Japanese and English names, the lines' colours and every
  trip of the day**: the operator's GTFS (熊本市交通局, `kumamotoshiden`,
  from the GTFS repository https://gtfs-data.jp, CC BY 2.1 JP): each stop
  the middle of its two platforms (`<n>_1`, `<n>_2`), Line A 健軍町 to
  田崎橋 (26 stops), Line B 健軍町 to 上熊本 (28), the two sharing
  健軍町 to 辛島町, their trips the weekday's, Saturday's and Sunday's
  (Sundays' for public holidays, as the operator's calendar runs them).
- **Track**: OpenStreetMap (osmtoday.com's Kyushu extract, read whole):
  the `railway=tram` ways of Kumamoto (`BOX`), joined and walked as the
  subway's are, the stops snapped to them.
- **Chinese names**: this project's (the Japanese in traditional
  characters, 駅前 → 站前).
- **Gauge**: 1,435 mm, 600 V DC overhead wire, 40 km/h at most (the
  軌道運転規則's limit, article 53, which the operator's trams run to),
  written on the lines as a record.
"""
import collections
import csv
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_fukuoka_rail as fk  # noqa: E402
import build_kyushu_shinkansen as ks  # noqa: E402

SYSTEM = "kumamotocity"
OPERATOR = "熊本市交通局"
# Kumamoto's tram ways: the city, not Kagoshima's or Nagasaki's trams.
BOX = {"north": 32.83, "south": 32.77, "west": 130.67, "east": 130.78}
# GTFS route id, line id, Chinese name, English name, the route's colour
# (GTFS `route_color`), its GTFS stops by number in the line's order.
LINES = [
    ("1", "A", "熊本市電A系統", "Kumamoto City Tram Line A", "#E50014", list(range(1, 27))),
    ("2", "B", "熊本市電B系統", "Kumamoto City Tram Line B", "#005BAC", list(range(1, 20)) + list(range(27, 36))),
]
# The Japanese names this project writes in traditional characters.
CHINESE = {
    "神水交差点": "神水交差點", "市立体育館前": "市立體育館前", "国府": "國府", "新水前寺駅前": "新水前寺站前",
    "九品寺交差点": "九品寺交差點", "慶徳校前": "慶德校前", "呉服町": "吳服町", "熊本駅前": "熊本站前",
    "県立体育館前": "縣立體育館前",
}
# GTFS's English names, written with a space before the bracket.
ENGLISH = {
    "Shiritsutaiikukan-mae(City Gymnasium)": "Shiritsutaiikukan-mae (City Gymnasium)",
    "Kenritsutaiikukan-mae(Prefectural Gymnasium)": "Kenritsutaiikukan-mae (Prefectural Gymnasium)",
}
JAPANESE_LINES = {"A": "A系統", "B": "B系統"}
EXTENT = ks.EXTENT
TRACK = {"gaugeMm": 1435, "loadingGauge": "tram", "electrification": "DC 600 V overhead", "maxSpeedKmh": 40}
# The GTFS service of each day, Sunday first (`days`), and of public holidays.
DAYS = ["日祝", "平日", "平日", "平日", "平日", "平日", "土曜"]
HOLIDAY = "日祝"
# A tram's dwell at a stop (the GTFS gives each stop one minute, its
# arrival and departure the same): the time a stop's run is written
# without, as `segs.run` is.
DWELL = 20
PEAK = (7 * 3600, 9 * 3600)
DAY = (10 * 3600, 16 * 3600)
# Decision 1041: Line A's trips that turn at 熊本駅前 (GTFS stop 24), one
# stop short of 田崎橋 (26), run on there empty first, or start there,
# at the times of the trips running through (the median of each leg, the
# way it goes). On two tracks between two stops' ends, a tram turning at
# 熊本駅前 that found its next trip gone to another stood on the platform
# toward 田崎橋, and the trams behind it waited from 08:49 on under the
# realistic rules; 田崎橋, the line's end, keeps its trams between trips
# on a track of its own (`RealLineLayout.streetTram`'s loop).
RUN_ON = {"A": (24, 26)}


def rows(folder, name):
    with open(os.path.join(folder, name), encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def seconds(text):
    h, m, s = (int(x) for x in text.split(":"))
    return h * 3600 + m * 60 + s


def gtfs_stops(folder):
    """{stop number: (Japanese name, English name, (lon, lat))}, each stop
    the middle of its platforms."""
    english = {r["field_value"]: r["translation"] for r in rows(folder, "translations.txt")
               if r["table_name"] == "stops" and r["language"] == "en"}
    points = collections.defaultdict(list)
    names = {}
    for r in rows(folder, "stops.txt"):
        number = int(r["stop_id"].split("_")[0])
        points[number].append((float(r["stop_lon"]), float(r["stop_lat"])))
        names[number] = r["stop_name"]
    out = {}
    for number, at in points.items():
        name = names[number]
        en = english[name]
        out[number] = (name, ENGLISH.get(en, en), (sum(x for x, _ in at) / len(at), sum(y for _, y in at) / len(at)))
    return out


def check_routes(folder):
    """The GTFS routes are the two lines, with their colours."""
    routes = {r["route_id"]: r for r in rows(folder, "routes.txt")}
    for route, line_id, _, _, colour, _ in LINES:
        r = routes.get(route)
        if r is None or r["route_long_name"] != JAPANESE_LINES[line_id] or "#" + r["route_color"].upper() != colour:
            sys.exit(f"GTFS route {route} is now {r}, not {JAPANESE_LINES[line_id]} {colour}")


def trips_of(folder):
    """{line id: {service: [trip]}}: each trip a list of the line's
    station index and the second of the day it leaves (the last,
    arrives), the trip's stops one after another along the line."""
    check_routes(folder)
    index = {spec[1]: {number: n for n, number in enumerate(spec[5])} for spec in LINES}
    line_of = {spec[0]: spec[1] for spec in LINES}
    trips = {r["trip_id"]: (line_of[r["route_id"]], r["service_id"]) for r in rows(folder, "trips.txt")}
    calls = collections.defaultdict(list)
    for r in rows(folder, "stop_times.txt"):
        calls[r["trip_id"]].append((int(r["stop_sequence"]), int(r["stop_id"].split("_")[0]), seconds(r["arrival_time"]),
                                    seconds(r["departure_time"])))
    out = {spec[1]: collections.defaultdict(list) for spec in LINES}
    for trip_id, stops in calls.items():
        line_id, service = trips[trip_id]
        stops.sort()
        trip, last = [], None
        for n, (_, number, arrive, leave) in enumerate(stops):
            i = index[line_id].get(number)
            if i is None:
                sys.exit(f"{trip_id}: stop {number} is not on Line {line_id}")
            if last is not None and abs(i - last) != 1:
                sys.exit(f"{trip_id}: from the line's stop {last} to {i}, not the next")
            trip += [i, arrive if n == len(stops) - 1 else leave]
            last = i
        out[line_id][service].append(trip)
    for line_id, sets in out.items():
        for service in sets:
            sets[service].sort(key=lambda trip: (trip[1], trip[0]))
        if set(sets) != set(DAYS):
            sys.exit(f"Line {line_id}: services {sorted(sets)}, not {sorted(set(DAYS))}")
    for line_id, (turn, end) in RUN_ON.items():
        run_on(out[line_id], index[line_id][turn], index[line_id][end])
    return out


def run_on(sets, turn, end):
    """The trips of `sets` that end or start at stop `turn` run on to, or
    start at, `end`, the line's end beyond it (see `RUN_ON`)."""
    step = 1 if end > turn else -1
    legs = collections.defaultdict(list)
    for trips in sets.values():
        for trip in trips:
            for a in range(0, len(trip) - 2, 2):
                legs[(trip[a], trip[a + 2])].append(trip[a + 3] - trip[a + 1])
    leg = {key: int(statistics.median(times)) for key, times in legs.items()}
    beyond = list(range(turn + step, end + step, step))
    for trips in sets.values():
        for trip in trips:
            if trip[-2] == turn and len(trip) > 2 and trip[-4] == turn - step:
                at, last = trip[-1], turn
                for stop in beyond:
                    at += leg[(last, stop)]
                    trip += [stop, at]
                    last = stop
            elif trip[0] == turn and len(trip) > 2 and trip[2] == turn - step:
                at, last = trip[1], turn
                for stop in beyond:
                    at -= leg[(stop, last)]
                    trip[:0] = [stop, at]
                    last = stop
        trips.sort(key=lambda trip: (trip[1], trip[0]))


def runs_between(trips, count):
    """Each leg's time between stops in the weekday's trips (the median,
    less the dwell)."""
    legs = collections.defaultdict(list)
    for trip in trips:
        for a, b in zip(range(0, len(trip) - 2, 2), range(2, len(trip), 2)):
            leg = min(trip[a], trip[b])
            legs[leg].append(abs(trip[b + 1] - trip[a + 1]))
    return [max(30, int(statistics.median(legs[n])) - DWELL) for n in range(count - 1)]


def headway(trips, window, station):
    """The seconds between trams leaving `station` in `window`, one way."""
    leaves = sorted(trip[n + 1] for trip in trips for n in range(0, len(trip) - 2, 2)
                    if trip[n] == station and trip[n + 2] == station + 1 and window[0] <= trip[n + 1] < window[1])
    return int(round((window[1] - window[0]) / len(leaves))) if leaves else None


class Parts(fk.osmium.SimpleHandler):
    """Kumamoto's tram ways (as `build_fukuoka_rail.Parts`)."""

    def __init__(self):
        super().__init__()
        self.ways, self.named, self.colours = {}, [], {}
        self.newest = ""

    def way(self, w):
        tags = dict(w.tags)
        if tags.get("railway") != "tram" or tags.get("service") in fk.SKIPPED_SERVICE:
            return
        nodes = [(n.ref, n.lon, n.lat) for n in w.nodes]
        if not all(BOX["south"] <= y <= BOX["north"] and BOX["west"] <= x <= BOX["east"] for _, x, y in nodes):
            return
        self.ways[w.id] = {"tags": tags, "nodes": nodes}
        self.newest = max(self.newest, w.timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"))

    def node(self, n):
        tags = dict(n.tags)
        if "name" in tags and tags.get("railway") == "tram_stop":
            self.named.append({"name": tags["name"], "en": tags.get("name:en"), "at": (n.location.lon, n.location.lat)})


def set_up(stops):
    fk.SYSTEM, fk.OPERATOR, fk.EXTENT = SYSTEM, OPERATOR, EXTENT
    fk.LINES = [(line_id, None, chinese, english, None, colour) for _, line_id, chinese, english, colour, _ in LINES]
    fk.STATIONS = {line_id: [(stops[n][0], CHINESE.get(stops[n][0], stops[n][0]), stops[n][1]) for n in numbers]
                   for _, line_id, _, _, _, numbers in LINES}
    fk.DWELL = DWELL


NOTE = ("Stops, their Japanese and English names, the lines' colours and times: 熊本市交通局's GTFS (CC BY 2.1 JP). "
        "Track: © OpenStreetMap contributors, ODbL 1.0. Chinese names: this project's.")


def times_value(trips):
    return {
        "system": SYSTEM.upper(), "estimated": False,
        "source_notes": "The operator's timetable: 熊本市交通局's GTFS (kumamotoshiden, gtfs-data.jp, CC BY 2.1 JP), "
                        "weekdays, Saturdays and Sundays; public holidays run Sundays' trips.",
        "lines": {line_id: {"days": DAYS, "holiday": HOLIDAY, "sets": {k: v for k, v in sorted(sets.items())}}
                  for line_id, sets in trips.items()},
    }


def main(gtfs, extract, out):
    os.makedirs(out, exist_ok=True)
    stops = gtfs_stops(gtfs)
    set_up(stops)
    trips = trips_of(gtfs)
    n02 = {line_id: {stops[n][0]: stops[n][2] for n in numbers} for _, line_id, _, _, _, numbers in LINES}
    parts = Parts()
    parts.apply_file(extract, locations=True, filters=[fk.osmium.filter.KeyFilter("railway")])
    graph, at, way_of = fk.track(parts)
    import build_relay_kamome as rk
    joins = rk.joined(graph, at, way_of)
    lines = [fk.line_of(spec, n02, parts, graph, at, way_of) for spec in fk.LINES]

    osm = {"credit": "© OpenStreetMap contributors", "license": "ODbL-1.0", "extract": os.path.basename(extract),
           "newestTrackEdit": parts.newest, "method": "tools/fukuoka-map/build_kumamoto_tram.py"}
    written = []
    for line in lines:
        stations = line["stations"]
        weekday = trips[line["id"]]["平日"]
        runs = runs_between(weekday, len(stations))
        written.append({
            "id": line["id"], "name": line["chinese"], "color": line["colour"],
            "peakHeadwaySec": headway(weekday, PEAK, 0), "offpeakHeadwaySec": headway(weekday, DAY, 0),
            "headway_estimated": False, **TRACK,
            "stations": [{"name": s["name"], "lat": s["lat"], "lon": s["lon"], "d": s["d"]} for s in stations],
            "shape": [[y, x] for x, y in line["shape"]],
            "segs": [{"run": run} for run in runs],
            "dwellSec": [DWELL] * len(stations),
        })
    fk.write(out, f"{SYSTEM}.json", {"system": SYSTEM.upper(), "source_notes": NOTE, "lines": written})
    fk.write(out, f"{SYSTEM}_times.json", times_value(trips))
    fk.write(out, "track_lines.geojson", {
        "type": "FeatureCollection", "source": NOTE, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "id": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": line["chinese"], "color": line["colour"], "sortKey": n, "kind": "track"},
                      "geometry": {"type": "LineString", "coordinates": line["shape"]}} for n, line in enumerate(lines)],
    })
    fk.write(out, "track_stations.geojson", {
        "type": "FeatureCollection", "source": NOTE, "osm": osm,
        "features": [{"type": "Feature",
                      "properties": {"sys": SYSTEM, "lineId": line["id"], "lineKey": f"{SYSTEM}|{line['id']}",
                                     "name": s["name"], "code": s["code"], "color": line["colour"]},
                      "geometry": {"type": "Point", "coordinates": [s["lon"], s["lat"]]}}
                     for line in lines for s in line["stations"]],
    })
    names = {}
    for line in lines:
        for s in line["stations"]:
            names[s["name"]] = {"en": s["english"], "ja": s["ja"]}
    fk.write(out, "station_names.json", {
        "source": NOTE,
        "systems": {SYSTEM: dict(sorted(names.items()))},
        "routes": {SYSTEM: {line["chinese"]: {"en": line["english"], "ja": JAPANESE_LINES[line["id"]]} for line in lines}},
    })
    fk.write(out, "rail_structures.json", {
        "_readme": "Where the lines of track_lines.geojson are on bridges (bridge) or in tunnels (tunnel), one "
                   "OpenStreetMap way each; the rest is in the street. Made by tools/fukuoka-map/build_kumamoto_tram.py.",
        "source": {"openStreetMap": osm},
        "structures": [dict(s, line=line["id"]) for line in lines for s in line["structures"]],
    })

    here = os.path.dirname(os.path.abspath(__file__))
    summary = {}
    for line, row in zip(lines, written):
        sets = trips[line["id"]]
        summary[line["id"]] = {"stations": len(line["stations"]), "km": line["stations"][-1]["d"],
                               "trips": {k: len(v) for k, v in sorted(sets.items())},
                               "peakHeadwaySec": row["peakHeadwaySec"], "offpeakHeadwaySec": row["offpeakHeadwaySec"]}
        print(f"{line['id']} {len(line['stations'])} stops {line['stations'][-1]['d']:.2f} km {len(line['shape'])} points; "
              f"trips {summary[line['id']]['trips']}; headways {row['peakHeadwaySec']} / {row['offpeakHeadwaySec']} s; "
              f"{len(line['structures'])} structures")
    print(f"{len(joins)} ends joined")
    fk.write(here, "kumamoto_tram_sources.json", {
        "task": "KUMAMOTO-TRAM", "decision": 1041, "staged": os.path.relpath(out, os.path.join(here, "..", "..")),
        "inputs": {
            "gtfs": {
                "files": {name: fk.sha256(os.path.join(gtfs, name)) for name in sorted(os.listdir(gtfs)) if name.endswith(".txt")},
                "from": "https://api.gtfs-data.jp/v2/organizations/kumamoto-shiden/feeds/kumamotoshiden/files/feed.zip?rid=current",
                "licence": "CC BY 2.1 JP, 熊本市交通局"},
            os.path.basename(extract): {
                "sha256": fk.sha256(extract), "from": "https://osmtoday.com/asia/japan/kyushu.pbf (whole, not cut)",
                "newestTrackEdit": parts.newest, "licence": "ODbL 1.0, © OpenStreetMap contributors"},
        },
        "lines": summary,
        "files": {name: os.path.getsize(os.path.join(out, name)) for name in sorted(os.listdir(out)) if name.endswith("json")},
    })


def times(gtfs, folder):
    """The day's trips laid out again in `folder`'s `kumamotocity_times.json`
    from the GTFS in `gtfs`."""
    set_up(gtfs_stops(gtfs))
    trips = trips_of(gtfs)
    fk.write(folder, f"{SYSTEM}_times.json", times_value(trips))
    print(f"{folder}: " + ", ".join(f"{k} {sum(len(v) for v in s.values())}" for k, s in trips.items()))


if __name__ == "__main__":
    if sys.argv[1:2] == ["times"]:
        times(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
