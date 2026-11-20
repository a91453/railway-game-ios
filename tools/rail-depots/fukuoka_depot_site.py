#!/usr/bin/env python3
"""Decision 897: where the Fukuoka City Subway's Hashimoto depot (橋本車両基地)
is, from OpenStreetMap, for `RealLineDepotSite.hashimoto`
(Sources/GamePresentation/RealLineDepot.swift).

    pip install osmium        # BSD 2-Clause, decision 93
    curl -L -o kyushu.pbf https://osmtoday.com/asia/japan/kyushu.pbf
    python3 -I tools/rail-depots/fukuoka_depot_site.py kyushu.pbf

It prints the depot's land (way 965734835), the leads between the line and
the yard (the `railway=subway` ways with no `service` south of Hashimoto
that are not the line's own), where they leave the line, and the yard
tracks (`service=yard`) by length. Some two minutes. The data is
OpenStreetMap contributors', ODbL 1.0.
"""
import math
import sys

import osmium

# Round Hashimoto station and the depot south-east of it.
BOX = (130.317, 33.545, 130.328, 33.557)
DEPOT = 965734835
# The Nanakuma Line's own two tracks into Hashimoto.
LINE = {23322477, 826154327}
# A Nanakuma Line train: four cars of 16.5 m.
TRAIN = 66


def length(points):
    k = 111_320.0
    return sum(math.hypot((a[0] - b[0]) * k, (a[1] - b[1]) * k * math.cos(math.radians(a[0]))) for a, b in zip(points, points[1:]))


class Reader(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.depot, self.line, self.leads, self.yard = None, [], [], []

    def way(self, w):
        tags = w.tags
        if w.id != DEPOT and tags.get("railway") != "subway":
            return
        try:
            points = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if not any(BOX[1] <= lat <= BOX[3] and BOX[0] <= lon <= BOX[2] for lat, lon in points):
            return
        refs = [n.ref for n in w.nodes]
        if w.id == DEPOT:
            self.depot = (dict(tags), points)
        elif w.id in LINE:
            self.line.append((w.id, points, refs))
        elif tags.get("service") == "yard":
            self.yard.append((w.id, points))
        elif "service" not in tags:
            self.leads.append((w.id, points, refs))


def main(path):
    reader = Reader()
    reader.apply_file(path, locations=True)
    if reader.depot:
        tags, points = reader.depot
        lats, lons = [p[0] for p in points], [p[1] for p in points]
        print(f"depot way {DEPOT}: {tags.get('name', '')} {tags.get('landuse', tags.get('railway', ''))}, "
              f"{min(lats):.6f}..{max(lats):.6f}, {min(lons):.6f}..{max(lons):.6f}")
    on_line = {ref: point for _, points, refs in reader.line for ref, point in zip(refs, points)}
    for way, points, refs in sorted(reader.leads):
        shared = [f"node {r} ({on_line[r][0]:.6f}, {on_line[r][1]:.6f})" for r in refs if r in on_line]
        print(f"lead way {way}: {length(points):.0f} m, ({points[0][0]:.6f}, {points[0][1]:.6f}) to ({points[-1][0]:.6f}, {points[-1][1]:.6f})"
              + (f"; on the line at {', '.join(shared)}" if shared else ""))
    yard = sorted(reader.yard, key=lambda t: -length(t[1]))
    long = [t for t in yard if length(t[1]) >= 2 * TRAIN]
    one = [t for t in yard if TRAIN <= length(t[1]) < 2 * TRAIN]
    print(f"yard tracks: {len(yard)}, {len(long)} of {2 * TRAIN} m or more, {len(one)} of {TRAIN} to {2 * TRAIN} m")
    for way, points in yard:
        if length(points) >= TRAIN:
            north, south = max(points, key=lambda p: p[0]), min(points, key=lambda p: p[0])
            print(f"  way {way}: {length(points):.0f} m, north end ({north[0]:.6f}, {north[1]:.6f}), south end ({south[0]:.6f}, {south[1]:.6f})")


if __name__ == "__main__":
    main(*sys.argv[1:])
