#!/usr/bin/env python3
"""Real bus routes for the app (decision 400, 10i-3).

Reads the routes, stop order, stops, shapes and service frequency of
Taiwan's city and county buses and writes one small file per city or
county, plus an index, for GamePresentation's ``RealBuses``:

- the owner's reference, ``Railway/geo-scene-reference-clean/source/
  public/bus/<preset>_bus_routes.json`` (20 cities and counties: shapes,
  stops as progress along the shape, buses an hour; made from TDX by its
  ``scripts/preprocess/preprocess-bus-routes.py``), and
- TDX's own answers, for the places the reference lacks (Taipei City,
  Pingtung County): ``<City>_Shape.json``, ``<City>_StopOfRoute.json`` and
  ``<City>_Schedule.json`` in a folder, each the answer of
  ``/api/basic/v2/Bus/<Shape|StopOfRoute|Schedule>/City/<City>`` that
  ``.github/workflows/tdx-check.yml`` keeps (README.md has the paths).

Standard library only. The output depends only on the input files: the
same inputs write the same bytes.
"""

import argparse
import hashlib
import json
import math
import os
import re
import sys

SCHEMA = 1

# The reference's presets (preprocess-bus-routes.py's CITY_PRESETS) by
# TDX's city name, which the app uses as each place's id.
REFERENCE_PRESETS = {
    "newtaipei": ("NewTaipei", "新北市"),
    "taoyuan": ("Taoyuan", "桃園市"),
    "taichung": ("Taichung", "臺中市"),
    "tainan": ("Tainan", "臺南市"),
    "kaohsiung": ("Kaohsiung", "高雄市"),
    "keelung": ("Keelung", "基隆市"),
    "hsinchu": ("Hsinchu", "新竹市"),
    "chiayi": ("Chiayi", "嘉義市"),
    "hsinchucounty": ("HsinchuCounty", "新竹縣"),
    "miaolicounty": ("MiaoliCounty", "苗栗縣"),
    "changhuacounty": ("ChanghuaCounty", "彰化縣"),
    "nantoucounty": ("NantouCounty", "南投縣"),
    "yunlincounty": ("YunlinCounty", "雲林縣"),
    "chiayicounty": ("ChiayiCounty", "嘉義縣"),
    "yilancounty": ("YilanCounty", "宜蘭縣"),
    "hualiencounty": ("HualienCounty", "花蓮縣"),
    "taitungcounty": ("TaitungCounty", "臺東縣"),
    "penghucounty": ("PenghuCounty", "澎湖縣"),
    "kinmencounty": ("KinmenCounty", "金門縣"),
    "lienchiangcounty": ("LienchiangCounty", "連江縣"),
}

TDX_CITIES = {
    "Taipei": "臺北市",
    "PingtungCounty": "屏東縣",
}

# The cities (the six special municipalities and the three provincial
# cities): a route with no schedule runs every 30 minutes there, every 60
# in a county. The reference's own stand-in for no schedule is 0.5 buses an
# hour everywhere (calc_frequency); the game marks every such headway as
# estimated.
CITIES = {"Taipei", "NewTaipei", "Taoyuan", "Taichung", "Tainan", "Kaohsiung", "Keelung", "Hsinchu", "Chiayi"}
ESTIMATED_CITY_HEADWAY = 30
ESTIMATED_COUNTY_HEADWAY = 60
# The reference's frequency when a route had no schedule rows.
REFERENCE_NO_SCHEDULE = 0.5
# GameCore's BusService.longestHeadway.
LONGEST_HEADWAY = 720

# Coordinates are kept as integers of 1e-5 degree (about 1 m), the
# reference's own rounding (5 decimals).
SCALE = 100_000
# Shapes are simplified (Douglas-Peucker) to within this many metres.
SIMPLIFY_METRES = 4.0
# A route is left out, and listed, when a stop is farther than this from its
# shape, or two points of the shape are farther apart than MAX_GAP_METRES.
MAX_STOP_OFFSET_METRES = 150.0
MAX_GAP_METRES = 5_000.0

# RealRailways.Coordinate.distance(to:)'s radius, so the app measures a shape as
# the tool did.
EARTH_RADIUS = 6_378_137.0


def metres_between(a, b):
    """Great-circle metres between two (lon, lat) points."""
    lon1, lat1, lon2, lat2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(min(1.0, math.sqrt(h)))


def local_xy(origin_lat):
    """A flat projection near `origin_lat`: (lon, lat) to metres."""
    kx = math.radians(1) * EARTH_RADIUS * math.cos(math.radians(origin_lat))
    ky = math.radians(1) * EARTH_RADIUS
    return lambda p: (p[0] * kx, p[1] * ky)


def simplify(points, tolerance):
    """Douglas-Peucker on (lon, lat) points, in metres; keeps both ends."""
    if len(points) < 3:
        return list(points)
    xy = local_xy(points[0][1])
    flat = [xy(p) for p in points]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        ax, ay = flat[first]
        bx, by = flat[last]
        dx, dy = bx - ax, by - ay
        length_sq = dx * dx + dy * dy
        worst, worst_index = -1.0, -1
        for i in range(first + 1, last):
            px, py = flat[i]
            if length_sq == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
                d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if d > worst:
                worst, worst_index = d, i
        if worst > tolerance:
            keep[worst_index] = True
            stack.append((first, worst_index))
            stack.append((worst_index, last))
    return [p for p, k in zip(points, keep) if k]


def project(point, shape, cumulative, xy):
    """The metres along `shape` of the point on it nearest `point`, and how
    far `point` is from it (the reference's project_stop_to_line, in
    metres)."""
    px, py = xy(point)
    best = (float("inf"), 0.0)
    for i in range(len(shape) - 1):
        ax, ay = xy(shape[i])
        bx, by = xy(shape[i + 1])
        dx, dy = bx - ax, by - ay
        length_sq = dx * dx + dy * dy
        t = 0.0 if length_sq == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
        d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
        if d < best[0]:
            best = (d, cumulative[i] + t * (cumulative[i + 1] - cumulative[i]))
    return best[1], best[0]


def cumulative_metres(shape):
    total = [0.0]
    for a, b in zip(shape, shape[1:]):
        total.append(total[-1] + metres_between(a, b))
    return total


def point_at_progress(coords, progress):
    """The point at `progress` (0–1) of the reference's degree-space length
    (its cumDist and stopProgress), as interpolateOnLineString does."""
    lengths = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(coords, coords[1:])]
    target = progress * sum(lengths)
    run = 0.0
    for i, length in enumerate(lengths):
        if run + length >= target and length > 0:
            t = (target - run) / length
            a, b = coords[i], coords[i + 1]
            return (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
        run += length
    return tuple(coords[-1])


def headway_from_frequency(frequency, city):
    """Whole minutes between buses, and whether it is estimated."""
    if frequency is None or frequency <= 0 or frequency == REFERENCE_NO_SCHEDULE:
        return (ESTIMATED_CITY_HEADWAY if city in CITIES else ESTIMATED_COUNTY_HEADWAY), True
    return max(1, min(LONGEST_HEADWAY, round(60 / frequency))), False


def encode(points):
    """Points as one flat list of 1e-5 degree integers: the first point,
    then each point's difference from the one before."""
    flat = []
    last = (0, 0)
    for lon, lat in points:
        q = (round(lon * SCALE), round(lat * SCALE))
        flat += [q[0] - last[0], q[1] - last[1]]
        last = q
    return flat


def dequantised(points):
    return [(round(lon * SCALE) / SCALE, round(lat * SCALE) / SCALE) for lon, lat in points]


def build_route(key, uid, name, sub_name, direction, shape, stops, headway, estimated, problems):
    """One route's entry, or None (with the reason in `problems`).

    `stops` is [(name, (lon, lat))] in stop order."""
    shape = dequantised(shape)
    # Points one after another at the same place say nothing.
    shape = [p for i, p in enumerate(shape) if i == 0 or p != shape[i - 1]]
    if len(shape) < 2:
        problems.append(f"{key}: shape has fewer than 2 points")
        return None
    if not stops:
        problems.append(f"{key}: no stops")
        return None
    simple = simplify(shape, SIMPLIFY_METRES)
    cumulative = cumulative_metres(simple)
    gap = max(b - a for a, b in zip(cumulative, cumulative[1:]))
    if gap > MAX_GAP_METRES:
        problems.append(f"{key}: shape jumps {gap:.0f} m")
        return None
    xy = local_xy(simple[0][1])
    stop_points = dequantised([p for _, p in stops])
    metres = []
    running = 0.0
    for (stop_name, _), point in zip(stops, stop_points):
        along, offset = project(point, simple, cumulative, xy)
        if offset > MAX_STOP_OFFSET_METRES:
            problems.append(f"{key}: stop {stop_name} is {offset:.0f} m from the shape")
            return None
        # Each stop no earlier than the one before (the reference's clamp).
        running = max(running, along)
        metres.append(round(running))
    return {
        "key": key,
        "route": uid,
        "name": name,
        "subRoute": sub_name,
        "direction": direction,
        "headway": headway,
        "headwayEstimated": estimated,
        "metres": round(cumulative[-1]),
        "shape": encode(simple),
        "stopNames": [n for n, _ in stops],
        # Each stop is the point of the shape this many metres along it.
        "stopMetres": metres,
    }


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for block in iter(lambda: file.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


# ── The reference ─────────────────────────────────────────────────────────

def reference_routes(path, city, problems):
    with open(path, encoding="utf-8") as file:
        data = json.load(file)
    routes = []
    for key in sorted(data):
        entry = data[key]
        coords = entry["coords"]
        stops = [(n, point_at_progress(coords, p)) for n, p in zip(entry["stopNames"], entry["stopProgress"])]
        headway, estimated = headway_from_frequency(entry.get("frequency"), city)
        route = build_route(key, entry["routeUid"], entry["routeName"], entry.get("subRouteName", ""),
                            int(entry["direction"]), coords, stops, headway, estimated, problems)
        if route:
            routes.append(route)
    return routes


# ── TDX ───────────────────────────────────────────────────────────────────

def zh(value):
    if isinstance(value, dict):
        return value.get("Zh_tw", "") or ""
    return value or ""


def wkt_points(text):
    """A LINESTRING's or MULTILINESTRING's points, the parts one after
    another."""
    points = []
    for part in re.findall(r"\(([^()]+)\)", text):
        for pair in part.split(","):
            lon, lat = pair.split()[:2]
            points.append((float(lon), float(lat)))
    return points


def parse_hm(text):
    try:
        hours, minutes = text.split(":")
        return int(hours) + int(minutes) / 60
    except (AttributeError, ValueError):
        return None


def runs_on_weekdays(service_day):
    """Whether a schedule row runs on a weekday; a row with no service days
    counts."""
    if not service_day:
        return True
    return any(service_day.get(day) for day in ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday"))


def tdx_frequencies(schedule):
    """Buses an hour by (RouteUID, Direction), as the reference's
    calc_frequency works them out, from weekday rows only: the average of
    each frequency row's (min + max) / 2 headway, or else the number of
    timetabled weekday trips over the hours between the first and the last
    (14 when unknown). A route that runs on Mondays and Tuesdays has each
    trip once a day: trips are counted on the first weekday they run."""
    headways = {}
    trips = {}
    spans = {}
    for entry in schedule:
        key = (entry["RouteUID"], int(entry["Direction"]))
        for row in entry.get("Frequencys") or []:
            if not runs_on_weekdays(row.get("ServiceDay")):
                continue
            low = float(row.get("MinHeadwayMins") or 0)
            high = float(row.get("MaxHeadwayMins") or 0)
            average = (low + high) / 2 if low > 0 and high > 0 else (low or high)
            if average > 0:
                headways.setdefault(key, []).append(average)
        days = {}
        for timetable in entry.get("Timetables") or []:
            service = timetable.get("ServiceDay") or {}
            if not runs_on_weekdays(service):
                continue
            first_day = next((d for d in ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday") if service.get(d)), "Monday")
            times = [parse_hm(s.get("DepartureTime") or s.get("ArrivalTime")) for s in timetable.get("StopTimes") or []]
            times = [t for t in times if t is not None]
            if not times:
                continue
            days.setdefault(first_day, []).append(min(times))
        if days:
            # The busiest weekday.
            day = max(sorted(days), key=lambda d: len(days[d]))
            trips[key] = trips.get(key, 0) + len(days[day])
            span = max(days[day]) - min(days[day])
            spans[key] = max(spans.get(key, 0.0), span)
    frequencies = {}
    for key in set(headways) | set(trips):
        if key in headways:
            frequencies[key] = 60 / (sum(headways[key]) / len(headways[key]))
        else:
            hours = spans.get(key) or 14.0
            frequencies[key] = trips[key] / hours
    return frequencies


def tdx_routes(folder, city, problems):
    def read(kind):
        with open(os.path.join(folder, f"{city}_{kind}.json"), encoding="utf-8") as file:
            return json.load(file)

    shapes = read("Shape")
    stop_routes = read("StopOfRoute")
    frequencies = tdx_frequencies(read("Schedule"))

    # The reference's three ways of finding a shape's stops: the same
    # sub-route; a named sub-route's route as a whole; a shape with no
    # sub-route name, every sub-route's stops merged (by stop, lowest
    # sequence first).
    by_key = {}
    by_route = {}
    for entry in stop_routes:
        direction = int(entry["Direction"])
        rows = []
        for stop in entry.get("Stops") or []:
            position = stop.get("StopPosition") or {}
            if position.get("PositionLon") is None or position.get("PositionLat") is None:
                continue
            rows.append((int(stop["StopSequence"]), stop["StopUID"], zh(stop.get("StopName")),
                         (float(position["PositionLon"]), float(position["PositionLat"]))))
        rows.sort()
        by_key.setdefault((entry["RouteUID"], zh(entry.get("SubRouteName")), direction), rows)
        by_route.setdefault((entry["RouteUID"], direction), []).extend(rows)
    merged = {}
    for key, rows in by_route.items():
        lowest = {}
        for row in rows:
            if row[1] not in lowest or row[0] < lowest[row[1]][0]:
                lowest[row[1]] = row
        merged[key] = sorted(lowest.values())

    routes = []
    seen = set()
    for entry in sorted(shapes, key=lambda e: (e["RouteUID"], zh(e.get("SubRouteName")), int(e["Direction"]))):
        uid = entry["RouteUID"]
        sub_name = zh(entry.get("SubRouteName"))
        direction = int(entry["Direction"])
        key = f"{uid}_{sub_name}_{direction}" if sub_name else f"{uid}_{direction}"
        if key in seen:
            problems.append(f"{key}: a second shape, left out")
            continue
        seen.add(key)
        rows = by_key.get((uid, sub_name, direction))
        if rows is None and sub_name:
            rows = by_key.get((uid, "", direction))
        if rows is None and not sub_name:
            rows = merged.get((uid, direction))
        stops = [(r[2], r[3]) for r in rows or []]
        headway, estimated = headway_from_frequency(frequencies.get((uid, direction)), city)
        route = build_route(key, uid, zh(entry.get("RouteName")), sub_name, direction,
                            wkt_points(entry.get("Geometry") or ""), stops, headway, estimated, problems)
        if route:
            routes.append(route)
    return routes


# ── Output ────────────────────────────────────────────────────────────────

def bounds(routes):
    lons, lats = [], []
    for route in routes:
        lon = lat = 0
        flat = route["shape"]
        for i in range(0, len(flat), 2):
            lon += flat[i]
            lat += flat[i + 1]
            lons.append(lon)
            lats.append(lat)
    return [min(lons), min(lats), max(lons), max(lats)]


def write_json(path, value):
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    with open(path, "w", encoding="utf-8") as file:
        file.write(text)
    return len(text.encode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reference", required=True, help="geo-scene-reference-clean/source/public/bus")
    parser.add_argument("--reference-commit", required=True, help="the reference repository's commit read")
    parser.add_argument("--tdx", required=True, help="a folder with <City>_Shape.json, _StopOfRoute.json, _Schedule.json")
    parser.add_argument("--tdx-fetched", required=True, help="the day the TDX answers were fetched, yyyy-mm-dd")
    parser.add_argument("--output", required=True, help="RailwayGameApp/Resources/RealBuses")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)
    index = []
    total = 0
    all_problems = []
    places = [(preset, city, name, "reference") for preset, (city, name) in REFERENCE_PRESETS.items()]
    places += [(None, city, name, "tdx") for city, name in TDX_CITIES.items()]
    for preset, city, name, source in sorted(places, key=lambda p: p[1]):
        problems = []
        if source == "reference":
            path = os.path.join(args.reference, f"{preset}_bus_routes.json")
            routes = reference_routes(path, city, problems)
            inputs = [{"file": f"Railway/geo-scene-reference-clean/source/public/bus/{preset}_bus_routes.json",
                       "sha256": sha256(path)}]
            origin = {"source": "reference", "commit": args.reference_commit}
        else:
            routes = tdx_routes(args.tdx, city, problems)
            inputs = [{"file": f"/api/basic/v2/Bus/{kind}/City/{city}", "sha256": sha256(os.path.join(args.tdx, f"{city}_{kind}.json"))}
                      for kind in ("Shape", "StopOfRoute", "Schedule")]
            origin = {"source": "tdx", "fetched": args.tdx_fetched}
        file_name = f"real_buses_{city}.json"
        size = write_json(os.path.join(args.output, file_name), {
            "schema": SCHEMA,
            "city": city,
            "name": name,
            "origin": origin,
            "inputs": inputs,
            "routes": routes,
        })
        total += size
        estimated = sum(1 for r in routes if r["headwayEstimated"])
        index.append({
            "city": city,
            "name": name,
            "file": file_name,
            "source": source,
            "routes": len(routes),
            "estimatedHeadways": estimated,
            "bounds": bounds(routes),
        })
        print(f"{city:17s} {source:9s} {len(routes):5d} routes, {estimated:4d} estimated headways, "
              f"{len(problems):3d} left out, {size / 1e6:6.2f} MB")
        all_problems += [f"{city} {p}" for p in problems]
    total += write_json(os.path.join(args.output, "real_buses_index.json"), {
        "schema": SCHEMA,
        "scale": SCALE,
        "places": index,
    })
    print(f"total {total / 1e6:.2f} MB")
    for problem in all_problems:
        print("left out:", problem)


if __name__ == "__main__":
    sys.exit(main())
