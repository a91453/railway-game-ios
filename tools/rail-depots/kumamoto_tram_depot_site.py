#!/usr/bin/env python3
"""Decision 1041: where the Kumamoto City Tram's two depots are, from
OpenStreetMap, for `RealLineDepotSite.oe` and `RealLineDepotSite.kamiKumamoto`
(Sources/GamePresentation/RealLineDepot.swift).

    pip install osmium        # BSD 2-Clause, decision 93
    curl -L -o kyushu.pbf https://osmtoday.com/asia/japan/kyushu.pbf
    python3 -I tools/rail-depots/kumamoto_tram_depot_site.py kyushu.pbf

For each depot it prints the `railway=tram` ways round it: the running
lines' (no `service`) and the depot's own (`service=yard`, `siding` or
`spur`) with their length and ends, and where a depot way meets a running
way (the node they share). Some two minutes. The data is OpenStreetMap
contributors', ODbL 1.0.
"""
import math
import sys

import osmium

# (name, south, west, north, east): round each depot and the line past it.
BOXES = (
    ("Ōe (大江車庫), beside Kōtsūkyoku-mae", 32.7955, 130.7180, 32.7995, 130.7225),
    ("Kami-Kumamoto (上熊本車庫), past Kami-Kumamoto", 32.8145, 130.6970, 32.8190, 130.7010),
)


def length(points):
    k = 111_320.0
    return sum(math.hypot((a[0] - b[0]) * k, (a[1] - b[1]) * k * math.cos(math.radians(a[0]))) for a, b in zip(points, points[1:]))


class Reader(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = []

    def way(self, w):
        if w.tags.get("railway") != "tram":
            return
        try:
            points = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        self.ways.append((w.id, dict(w.tags), points, [n.ref for n in w.nodes]))


def main(path):
    reader = Reader()
    reader.apply_file(path, locations=True)
    for name, south, west, north, east in BOXES:
        print(f"== {name}")
        near = [w for w in reader.ways if any(south <= lat <= north and west <= lon <= east for lat, lon in w[2])]
        running = {ref: point for _, tags, points, refs in near if "service" not in tags for ref, point in zip(refs, points)}
        for way, tags, points, refs in sorted(near, key=lambda w: (w[1].get("service", ""), w[0])):
            shared = [f"node {r} ({running[r][0]:.6f}, {running[r][1]:.6f})" for r in refs if r in running] if "service" in tags else []
            print(f"way {way} {tags.get('service', 'line')} {tags.get('name', '')}: {length(points):.0f} m, "
                  f"({points[0][0]:.6f}, {points[0][1]:.6f}) to ({points[-1][0]:.6f}, {points[-1][1]:.6f})"
                  + (f"; meets the line at {', '.join(shared)}" if shared else ""))


if __name__ == "__main__":
    main(*sys.argv[1:])
