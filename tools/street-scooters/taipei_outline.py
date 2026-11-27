#!/usr/bin/env python3
"""Decision 1037: Taipei City's (臺北市) outline for the scooters' share.

Reads the app's township outlines (`RailwayGameApp/Resources/RealWorld/
taiwan_place_names.json`, OpenStreetMap, ODbL 1.0; decision 159), joins the
twelve districts whose county is 臺北市 by dropping the edges two districts
share, and simplifies what is left (Douglas-Peucker, 150 m) into the
latitudes and longitudes `Map3DStreetScooters.taipeiOutline` holds:

    python3 -I tools/street-scooters/taipei_outline.py
"""

import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOLERANCE_M = 150.0


def rings():
    data = json.load(open(os.path.join(ROOT, "RailwayGameApp/Resources/RealWorld/taiwan_place_names.json")))
    for township in data["townships"]:
        if township.get("county") != "臺北市":
            continue
        for deltas in township["rings"]:
            lat = lon = 0
            ring = []
            for i in range(0, len(deltas), 2):
                lat += deltas[i]
                lon += deltas[i + 1]
                ring.append((lat, lon))
            if ring[0] == ring[-1]:
                ring.pop()
            yield ring


def outer():
    edges = {}
    for ring in rings():
        for a, b in zip(ring, ring[1:] + ring[:1]):
            key = (min(a, b), max(a, b))
            edges[key] = edges.get(key, 0) + 1
    single = [key for key, n in edges.items() if n == 1]
    nexts = {}
    for a, b in single:
        nexts.setdefault(a, []).append(b)
        nexts.setdefault(b, []).append(a)
    loops = []
    seen = set()
    for start in nexts:
        if start in seen:
            continue
        loop = [start]
        seen.add(start)
        previous, at = None, start
        while True:
            options = [p for p in nexts[at] if p != previous and p not in seen]
            if not options:
                break
            previous, at = at, options[0]
            seen.add(at)
            loop.append(at)
        if len(loop) > 3:
            loops.append(loop)
    return max(loops, key=len)


def simplify(points, tolerance):
    lat0 = sum(p[0] for p in points) / len(points) / 1e5
    kx = 111_320 * math.cos(math.radians(lat0)) / 1e5
    ky = 110_574 / 1e5

    def dist(p, a, b):
        px, py = p[1] * kx, p[0] * ky
        ax, ay = a[1] * kx, a[0] * ky
        bx, by = b[1] * kx, b[0] * ky
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        t = 0 if length == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
        return math.hypot(px - ax - t * dx, py - ay - t * dy)

    def run(segment):
        if len(segment) < 3:
            return segment
        far, index = 0, 0
        for i in range(1, len(segment) - 1):
            d = dist(segment[i], segment[0], segment[-1])
            if d > far:
                far, index = d, i
        if far <= tolerance:
            return [segment[0], segment[-1]]
        return run(segment[:index + 1])[:-1] + run(segment[index:])

    half = len(points) // 2
    return run(points[:half + 1])[:-1] + run(points[half:] + points[:1])[:-1]


def main():
    loop = outer()
    points = simplify(loop, TOLERANCE_M)
    print(f"// {len(loop)} points joined, {len(points)} kept", file=sys.stderr)
    rows = [f"({p[0] / 1e5:.5f}, {p[1] / 1e5:.5f})" for p in points]
    for i in range(0, len(rows), 6):
        print("        " + ", ".join(rows[i:i + 6]) + ",")


if __name__ == "__main__":
    main()
