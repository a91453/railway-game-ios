#!/usr/bin/env python3
"""Real intercity coach routes for the app (decision 706, first step).

Reads TDX's highway bus answers (the Highway Bureau's routes, ``InterCity``)
and writes the intercity ones into one file for GamePresentation's
``RealCoaches``: each route direction's stops in order, its shape, every
departure of the week, the minutes to each stop and the full fare.

The five answers, each kept by ``.github/workflows/tdx-check.yml`` and
renamed (README.md has the paths), sit in one folder:

    InterCity_Route.json         /api/basic/v2/Bus/Route/InterCity
    InterCity_StopOfRoute.json   /api/basic/v2/Bus/StopOfRoute/InterCity
    InterCity_Shape.json         /api/basic/v2/Bus/Shape/InterCity
    InterCity_Schedule.json      /api/basic/v2/Bus/Schedule/InterCity
    InterCity_RouteFare.json     /api/basic/v2/Bus/RouteFare/InterCity

Standard library only. The output depends only on the input files: the
same inputs write the same bytes. The geometry (rounding, simplifying,
putting stops on the shape) is ``tools/real-buses/build_real_buses.py``'s,
so a coach's shape and stops read as a city bus's do.
"""

import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "real-buses"))
import build_real_buses as buses  # noqa: E402

SCHEMA = 1

# TDX's BusRouteType: 13 is a freeway coach (國道客運), 12 an ordinary
# highway bus (一般公路客運).
FREEWAY = 13
HIGHWAY = 12
KINDS = {FREEWAY: "freeway", HIGHWAY: "highway"}

# Which routes are intercity: every freeway coach, and a highway bus whose
# stops lie in two or more cities or counties and which gets at least this
# far, in a straight line, from its first stop. The rest (a county's own
# rural buses, which the Highway Bureau also licenses) are left out.
HIGHWAY_REACH_METRES = 30_000.0

# A coach terminal may stand farther from the drawn line than a city bus
# stop does (Kaohsiung's Jianguo terminal is 400 m from its routes'), and a
# freeway's line may have two points farther apart.
MAX_STOP_OFFSET_METRES = 500.0
MAX_GAP_METRES = 10_000.0

# The speed a route is given when no trip times two of its stops, or the
# timetable's own minutes make it slower or faster than a coach runs
# (11 km/h and 127 km/h are in the data).
ESTIMATED_KMH = {"freeway": 70.0, "highway": 35.0}
SLOWEST_KMH = 15.0
FASTEST_KMH = 110.0

DAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
EVERY_DAY = (1 << len(DAYS)) - 1


def zh(value):
    return buses.zh(value).strip()


def minutes_of(text):
    """`hh:mm` as minutes after midnight, or None."""
    if not isinstance(text, str) or not re.fullmatch(r"\d{1,2}:\d{2}", text):
        return None
    hours, minutes = text.split(":")
    return int(hours) * 60 + int(minutes)


def day_mask(service_day):
    """Bit 0 is Monday, bit 6 Sunday; a row with no days runs every day."""
    if not service_day:
        return EVERY_DAY
    mask = 0
    for bit, day in enumerate(DAYS):
        if service_day.get(day):
            mask |= 1 << bit
    return mask


def reach_metres(points):
    """How far the stops get from the first one, in a straight line."""
    return max(buses.metres_between(points[0], p) for p in points)


def stop_minutes(stop_metres, sequences, trips, kind):
    """Minutes from the first stop to each stop, and whether they are
    estimated.

    The timetable times only some stops. The trip that times the most
    stops (the earliest of them) gives those stops' minutes; the stops
    between take theirs by distance, and stops before the first or after
    the last timed one go at the trip's own average speed. A route no trip
    times over any distance, or whose timed speed is outside SLOWEST_KMH to
    FASTEST_KMH, runs at ESTIMATED_KMH."""
    index_of = {sequence: i for i, sequence in enumerate(sequences)}
    best = None
    for trip in trips:
        anchors = []
        last = None
        for sequence, minute in trip["times"]:
            if sequence not in index_of:
                continue
            if last is not None and minute < last:
                minute += 24 * 60 * ((last - minute) // (24 * 60) + 1)
            last = minute
            anchors.append((stop_metres[index_of[sequence]], minute))
        if len(anchors) < 2:
            continue
        distance = anchors[-1][0] - anchors[0][0]
        duration = anchors[-1][1] - anchors[0][1]
        if distance <= 0 or duration <= 0:
            continue
        rank = (-len(anchors), trip["departure"], anchors)
        if best is None or rank < best[0]:
            best = (rank, anchors, duration / distance)
    if best is not None and stop_metres[-1] > 0:
        kmh = 0.06 / best[2]
        if not SLOWEST_KMH <= kmh <= FASTEST_KMH:
            best = None
    if best is None:
        per_metre = 60 / (ESTIMATED_KMH[kind] * 1000)
        return [round(m * per_metre) for m in stop_metres], True
    _, anchors, per_metre = best
    start = anchors[0][1] - anchors[0][0] * per_metre
    minutes = []
    for metres in stop_metres:
        if metres <= anchors[0][0]:
            value = anchors[0][1] - (anchors[0][0] - metres) * per_metre
        elif metres >= anchors[-1][0]:
            value = anchors[-1][1] + (metres - anchors[-1][0]) * per_metre
        else:
            value = anchors[-1][1]
            for (m0, t0), (m1, t1) in zip(anchors, anchors[1:]):
                if m0 <= metres <= m1:
                    value = t0 if m1 == m0 else t0 + (t1 - t0) * (metres - m0) / (m1 - m0)
                    break
        minutes.append(value - start)
    rounded = []
    for value in minutes:
        rounded.append(max(rounded[-1] if rounded else 0, round(value)))
    return rounded, False


def departures(schedules):
    """Every departure of the week of one route direction: [(minute after
    midnight at the first timed stop, day mask)], sorted, and how many of
    them come from a headway row rather than a timetabled trip.

    A headway row (every 15 to 20 minutes from 06:20 to 21:00 on weekdays)
    becomes a trip at its start and one every average headway after it, up
    to its end. A timetabled trip inside a headway row's hours and days is
    the same service written twice and is dropped."""
    timed = []
    windows = []
    trips = []
    for entry in schedules:
        for row in entry.get("Frequencys") or []:
            start, end = minutes_of(row.get("StartTime")), minutes_of(row.get("EndTime"))
            low = float(row.get("MinHeadwayMins") or 0)
            high = float(row.get("MaxHeadwayMins") or 0)
            headway = (low + high) / 2 if low > 0 and high > 0 else (low or high)
            mask = day_mask(row.get("ServiceDay"))
            if start is None or end is None or end < start or headway <= 0 or mask == 0:
                continue
            windows.append((start, end, headway, mask))
        for timetable in entry.get("Timetables") or []:
            times = []
            for stop in timetable.get("StopTimes") or []:
                minute = minutes_of(stop.get("DepartureTime")) if stop.get("DepartureTime") else minutes_of(stop.get("ArrivalTime"))
                if minute is not None:
                    times.append((int(stop["StopSequence"]), minute))
            mask = day_mask(timetable.get("ServiceDay"))
            if not times or mask == 0:
                continue
            times.sort(key=lambda t: t[0])
            trip = {"departure": times[0][1] % (24 * 60), "times": times, "mask": mask}
            trips.append(trip)
            timed.append(trip)
    result = {}
    for trip in timed:
        mask = trip["mask"]
        for start, end, _, window_mask in windows:
            if start <= trip["departure"] <= end:
                mask &= ~window_mask
        if mask:
            result[trip["departure"]] = result.get(trip["departure"], 0) | mask
    from_headways = 0
    for start, end, headway, mask in sorted(windows):
        count = int((end - start) // headway) + 1
        for i in range(count):
            minute = round(start + i * headway) % (24 * 60)
            added = mask & ~result.get(minute, 0)
            if added:
                result[minute] = result.get(minute, 0) | mask
                from_headways += 1
    return sorted(result.items()), from_headways, trips


def full_fares(fare_rows):
    """The adult single fare over each route direction's longest stage, by
    (SubRouteUID, Direction): the lowest full ticket (FareClass 1) of the
    stage that spans the most stops, across the operators that run it."""
    best = {}
    for row in fare_rows:
        for stage in row.get("StageFares") or []:
            key = ("THB" + row["SubRouteID"], int(stage["Direction"]))
            span = int(stage["DestinationStage"]["Sequence"]) - int(stage["OriginStage"]["Sequence"])
            prices = [int(f["Price"]) for f in stage.get("Fares") or [] if f.get("FareClass") == 1 and int(f.get("Price") or 0) > 0]
            if span <= 0 or not prices:
                continue
            candidate = (-span, min(prices))
            if key not in best or candidate < best[key]:
                best[key] = candidate
    return {key: price for key, (_, price) in best.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tdx", required=True, help="the folder with the five InterCity_*.json answers")
    parser.add_argument("--tdx-fetched", required=True, help="the day the answers were fetched, yyyy-mm-dd")
    parser.add_argument("--output", required=True, help="RailwayGameApp/Resources/RealCoaches")
    args = parser.parse_args()

    def read(kind):
        with open(os.path.join(args.tdx, f"InterCity_{kind}.json"), encoding="utf-8") as file:
            return json.load(file)

    kinds = ("Route", "StopOfRoute", "Shape", "Schedule", "RouteFare")
    route_rows = {row["RouteUID"]: row for row in read("Route")}
    stop_rows = read("StopOfRoute")
    shape_rows = read("Shape")
    schedule_rows = read("Schedule")
    fares = full_fares(read("RouteFare"))

    shapes = {}
    problems = []
    for row in sorted(shape_rows, key=lambda r: (r["SubRouteUID"], int(r["Direction"]))):
        key = (row["SubRouteUID"], int(row["Direction"]))
        if key in shapes:
            problems.append(f"{key[0]}_{key[1]}: a second shape, left out")
            continue
        shapes[key] = row
    schedules = {}
    for row in schedule_rows:
        schedules.setdefault((row["SubRouteUID"], int(row["Direction"])), []).append(row)
    headsigns = {}
    for row in route_rows.values():
        for sub in row.get("SubRoutes") or []:
            headsigns[(sub["SubRouteUID"], int(sub["Direction"]))] = (sub.get("Headsign") or "", sub.get("HeadsignEn") or "")

    buses.MAX_STOP_OFFSET_METRES = MAX_STOP_OFFSET_METRES
    buses.MAX_GAP_METRES = MAX_GAP_METRES
    routes = []
    counts = {"freeway": 0, "highway": 0}
    not_intercity = 0
    seen = set()
    for entry in sorted(stop_rows, key=lambda e: (e["SubRouteUID"], int(e["Direction"]))):
        uid = entry["RouteUID"]
        direction = int(entry["Direction"])
        key = (entry["SubRouteUID"], direction)
        name = f"{key[0]}_{key[1]}"
        if key in seen:
            problems.append(f"{name}: a second stop list, left out")
            continue
        seen.add(key)
        route = route_rows.get(uid)
        if route is None or route.get("BusRouteType") not in KINDS:
            problems.append(f"{name}: no route of a known kind")
            continue
        kind = KINDS[route["BusRouteType"]]
        rows = []
        for stop in entry.get("Stops") or []:
            position = stop.get("StopPosition") or {}
            if position.get("PositionLon") is None or position.get("PositionLat") is None:
                continue
            rows.append((int(stop["StopSequence"]), zh(stop.get("StopName")),
                         (float(position["PositionLon"]), float(position["PositionLat"])),
                         stop.get("LocationCityCode") or "", int(stop.get("StopBoarding") or 0)))
        rows.sort(key=lambda r: r[0])
        if len(rows) < 2:
            problems.append(f"{name}: fewer than two stops")
            continue
        if kind == "highway":
            cities = {r[3] for r in rows if r[3]}
            if len(cities) < 2 or reach_metres([r[2] for r in rows]) < HIGHWAY_REACH_METRES:
                not_intercity += 1
                continue
        shape = shapes.get(key)
        if shape is None:
            problems.append(f"{name}: no shape")
            continue
        times, from_headways, trips = departures(schedules.get(key, []))
        if not times:
            problems.append(f"{name}: no departures in the schedule")
            continue
        route_problems = []
        built = buses.build_route(name, uid, zh(route.get("RouteName")), zh(entry.get("SubRouteName")), direction,
                                  buses.wkt_points(shape.get("Geometry") or ""), [(r[1], r[2]) for r in rows],
                                  1, False, route_problems)
        if built is None:
            problems += route_problems
            continue
        minutes, estimated = stop_minutes(built["stopMetres"], [r[0] for r in rows], trips, kind)
        if minutes[-1] <= 0:
            problems.append(f"{name}: no running time")
            continue
        del built["headway"], built["headwayEstimated"]
        built["kind"] = kind
        built["operators"] = sorted({zh(o.get("OperatorName")) for o in entry.get("Operators") or [] if zh(o.get("OperatorName"))})
        headsign = headsigns.get(key, ("", ""))
        built["headsign"] = headsign[0]
        built["headsignEn"] = headsign[1]
        built["stopCities"] = [r[3] for r in rows]
        # 0 both, 1 boarding only, -1 alighting only (TDX's StopBoarding).
        if any(r[4] for r in rows):
            built["stopBoarding"] = [r[4] for r in rows]
        built["stopMinutes"] = minutes
        if estimated:
            built["minutesEstimated"] = True
        built["tripMinutes"] = [minute for minute, _ in times]
        built["tripDays"] = [mask for _, mask in times]
        if from_headways:
            built["tripsFromHeadways"] = from_headways
        if key in fares:
            built["fare"] = fares[key]
        routes.append(built)
        counts[kind] += 1

    os.makedirs(args.output, exist_ok=True)
    size = buses.write_json(os.path.join(args.output, "real_coaches.json"), {
        "schema": SCHEMA,
        "scale": buses.SCALE,
        "origin": {"source": "tdx", "fetched": args.tdx_fetched},
        "inputs": [{"file": f"/api/basic/v2/Bus/{kind}/InterCity",
                    "sha256": buses.sha256(os.path.join(args.tdx, f"InterCity_{kind}.json"))} for kind in kinds],
        "bounds": buses.bounds(routes),
        "routes": routes,
    })
    weekday = sum(1 for r in routes for mask in r["tripDays"] if mask & 0b0000100)
    print(f"{len(routes)} route directions ({counts['freeway']} freeway, {counts['highway']} highway) of "
          f"{len({r['route'] for r in routes})} routes; {not_intercity} highway directions are not intercity")
    print(f"{sum(len(r['stopNames']) for r in routes)} stops, {sum(len(r['shape']) // 2 for r in routes)} shape points, "
          f"{weekday} departures on a Wednesday, {sum(r.get('tripsFromHeadways', 0) for r in routes)} from headway rows, "
          f"{sum(1 for r in routes if r.get('minutesEstimated'))} with estimated minutes, "
          f"{sum(1 for r in routes if 'fare' not in r)} with no fare")
    print(f"{size / 1e6:.2f} MB")
    for problem in problems:
        print("left out:", problem)


if __name__ == "__main__":
    sys.exit(main())
