#!/usr/bin/env python3
"""Turns the real coach routes into the small network the game's rule reads
(decision 706, second step).

Input: RailwayGameApp/Resources/RealCoaches/real_coaches.json (committed;
tools/real-coaches/build_real_coaches.py writes it from TDX).
Output: RailwayGameApp/Resources/RealCoaches/coach_network.json.

A hub is a group of stops: the stops are taken busiest first (coach calls on
a Wednesday), and each joins the nearest hub within HUB_METRES or starts a
new one. A link is a pair of hubs at least LINK_METRES apart that some route
calls at in that order, boarding allowed at the first and alighting at the
second, with its Wednesday coaches, minutes (weighted by coaches) and fare
(the route's fare by the share of its length, NT$ FARE_PER_KM a kilometre
where the route has none). Standard library only; the same input writes the
same bytes.
"""

import argparse
import collections
import hashlib
import json
import math
import os
import sys

SCHEMA = 1
SCALE = 100_000
HUB_METRES = 800.0
LINK_METRES = 10_000.0
# A hub with fewer coaches a Wednesday, a link with fewer, and the links of
# a hub past its busiest MAX_LINKS are left out.
MIN_HUB_COACHES = 8
MIN_LINK_COACHES = 4
MAX_LINKS = 16
WEDNESDAY = 1 << 2
# The median full fare of the routes that have one, NT$ a kilometre
# (tools/real-coaches/README.md).
FARE_PER_KM = 2.02
EARTH = 6_378_137.0


def metres(a, b):
    lon1, lat1, lon2, lat2 = (math.radians(v / SCALE) for v in (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * EARTH * math.asin(min(1.0, math.sqrt(h)))


def stop_points(route):
    """The stops' points, each `stopMetres` along the shape, in 1e-5 degrees."""
    flat = route["shape"]
    points, lon, lat = [], 0, 0
    for index in range(0, len(flat), 2):
        lon += flat[index]
        lat += flat[index + 1]
        points.append((lon, lat))
    run = [0.0]
    for a, b in zip(points, points[1:]):
        run.append(run[-1] + metres(a, b))
    out, segment = [], 0
    for target in route["stopMetres"]:
        while segment < len(points) - 2 and run[segment + 1] < target:
            segment += 1
        length = run[segment + 1] - run[segment]
        t = 0.0 if length == 0 else max(0.0, min(1.0, (target - run[segment]) / length))
        a, b = points[segment], points[segment + 1]
        out.append((round(a[0] + t * (b[0] - a[0])), round(a[1] + t * (b[1] - a[1]))))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", required=True, help="RailwayGameApp/Resources/RealCoaches")
    args = parser.parse_args()
    source = os.path.join(args.resources, "real_coaches.json")
    with open(source, "rb") as file:
        raw = file.read()
    routes = json.loads(raw)["routes"]

    wednesday = {r["key"]: [m for m, days in zip(r["tripMinutes"], r["tripDays"]) if days & WEDNESDAY] for r in routes}
    points = {r["key"]: stop_points(r) for r in routes}
    calls = collections.Counter()
    names = {}
    for route in routes:
        coaches = len(wednesday[route["key"]])
        for point, name in zip(points[route["key"]], route["stopNames"]):
            calls[point] += coaches
            names.setdefault(point, collections.Counter())[name] += coaches

    # Hubs: busiest stop first, ties by position.
    hubs, hub_of, grid = [], {}, collections.defaultdict(list)
    for point in sorted(calls, key=lambda p: (-calls[p], p)):
        cell = (point[0] // 1000, point[1] // 1000)
        best = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for hub in grid[(cell[0] + dx, cell[1] + dy)]:
                    distance = metres(point, hubs[hub])
                    if distance <= HUB_METRES and (best is None or (distance, hub) < best):
                        best = (distance, hub)
        if best is None:
            hubs.append(point)
            grid[cell].append(len(hubs) - 1)
            hub_of[point] = len(hubs) - 1
        else:
            hub_of[point] = best[1]

    coaches_at = collections.Counter()
    # Hundredths of a coach load: each coach's riders board evenly among the
    # hubs it lets them board at, and alight evenly among those it lets
    # them alight at.
    boarding, alighting = collections.Counter(), collections.Counter()
    hours = collections.defaultdict(lambda: [0] * 24)
    links = {}
    for route in routes:
        trips = wednesday[route["key"]]
        if not trips:
            continue
        stops = points[route["key"]]
        flags = route.get("stopBoarding") or [0] * len(stops)
        at = [hub_of[p] for p in stops]
        board, alight, first_minute = [], [], {}
        for index, hub in enumerate(at):
            first_minute.setdefault(hub, route["stopMinutes"][index])
            if flags[index] >= 0 and hub not in board:
                board.append(hub)
            if flags[index] <= 0 and hub not in alight:
                alight.append(hub)
        for hub in board:
            boarding[hub] += len(trips) * 100 // len(board)
        for hub in alight:
            alighting[hub] += len(trips) * 100 // len(alight)
        for hub, minute in first_minute.items():
            coaches_at[hub] += len(trips)
            for trip in trips:
                hours[hub][(trip + minute) // 60 % 24] += 1
        length = max(1, route["stopMetres"][-1] - route["stopMetres"][0])
        seen = set()
        for i in range(len(stops)):
            if flags[i] < 0:
                continue
            for j in range(i + 1, len(stops)):
                pair = (at[i], at[j])
                if flags[j] > 0 or at[i] == at[j] or pair in seen:
                    continue
                if metres(hubs[at[i]], hubs[at[j]]) < LINK_METRES:
                    continue
                seen.add(pair)
                run = route["stopMetres"][j] - route["stopMetres"][i]
                fare = route["fare"] * run / length if "fare" in route else FARE_PER_KM * run / 1000
                link = links.setdefault(pair, [0, 0, 0.0])
                link[0] += len(trips)
                link[1] += len(trips) * (route["stopMinutes"][j] - route["stopMinutes"][i])
                link[2] += len(trips) * fare

    kept = [hub for hub in range(len(hubs)) if coaches_at[hub] >= MIN_HUB_COACHES]
    number = {hub: index for index, hub in enumerate(kept)}
    out, link_count = [], 0
    for hub in kept:
        mine = sorted(((-v[0], number[b], v) for (a, b), v in links.items()
                       if a == hub and b in number and v[0] >= MIN_LINK_COACHES))[:MAX_LINKS]
        flat = []
        for _, to, (coaches, minutes, fare) in sorted(mine, key=lambda entry: entry[1]):
            flat += [to, coaches, max(1, round(minutes / coaches)), max(1, round(fare / coaches))]
        link_count += len(mine)
        entry = {
            "name": sorted(names[hubs[hub]].items(), key=lambda item: (-item[1], item[0]))[0][0],
            "x": hubs[hub][0], "y": hubs[hub][1],
            "coaches": coaches_at[hub], "boarding": boarding[hub], "alighting": alighting[hub],
            "hours": hours[hub],
        }
        if flat:
            entry["links"] = flat
        out.append(entry)

    path = os.path.join(args.resources, "coach_network.json")
    text = json.dumps({
        "schema": SCHEMA, "scale": SCALE,
        "input": {"file": "real_coaches.json", "sha256": hashlib.sha256(raw).hexdigest()},
        "hubs": out,
    }, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as file:
        file.write(text)
    print(f"{len(hubs)} groups of stops, {len(out)} hubs with {MIN_HUB_COACHES} coaches or more, {link_count} links; "
          f"{sum(coaches_at[h] for h in kept)} of {sum(coaches_at.values())} coach calls, "
          f"{sum(boarding[h] for h in kept) // 100} of {sum(boarding.values()) // 100} coach loads boarding; "
          f"{len(text.encode()) / 1e6:.2f} MB")


if __name__ == "__main__":
    sys.exit(main())
