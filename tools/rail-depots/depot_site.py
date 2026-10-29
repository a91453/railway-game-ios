#!/usr/bin/env python3
"""Where a real depot's leads leave its line and where its yard runs
(decision 479), read from a whole OpenStreetMap extract of Taiwan
(osmtoday.com's asia/taiwan.pbf, ODbL) with pyosmium.

    python3 -I depot_site.py taiwan.pbf

prints, for the Sanxia depot (三峽機廠) of the New Taipei Metro's Sanying
Line, the numbers `RealLineDepotSite.sanxia` in
`Sources/GamePresentation/RealLineDepot.swift` holds: the middle of the
crossover its leads leave the line by, the middle of its sidings' near
ends and of their far ends, and the real platforms' length (the game's
are not set from it: see the decision).
"""
import math
import sys

import osmium

DEPOT = 619043484           # landuse=railway, 三峽機廠
CROSSOVER = 1156270818      # service=crossover, the leads' junction
SIDINGS = [1136774767, 1136774768]
PLATFORM_FIRST = 1569306500  # the line's platforms, mapped together


class Ways(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = {}
        self.platforms = []

    def way(self, w):
        if w.id in (DEPOT, CROSSOVER, *SIDINGS):
            self.ways[w.id] = [(n.lat, n.lon) for n in w.nodes]
        elif w.id >= PLATFORM_FIRST and w.tags.get("railway") == "platform" and w.tags.get("area") == "yes":
            points = [(n.lat, n.lon) for n in w.nodes]
            if 24.9 < points[0][0] < 24.98 and 121.32 < points[0][1] < 121.43:
                self.platforms.append(points)


def metres(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((b[0] - a[0]) * 111_320, (b[1] - a[1]) * 111_320 * k)


def middle(points):
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def main():
    ways = Ways()
    ways.apply_file(sys.argv[1], locations=True)
    crossover = ways.ways[CROSSOVER]
    sidings = [ways.ways[i] for i in SIDINGS]
    print("junction", middle([crossover[0], crossover[-1]]))
    print("yard start", middle([s[-1] for s in sidings]))
    print("yard end", middle([s[0] for s in sidings]))
    sides = sorted(round(max(metres(p[i], p[i + 1]) for i in range(len(p) - 1)), 1) for p in ways.platforms)
    print("platforms", len(sides), "longest sides", sides[0], "to", sides[-1], "m")


if __name__ == "__main__":
    main()
