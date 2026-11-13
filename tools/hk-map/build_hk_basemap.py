#!/usr/bin/env python3
"""Hong Kong's base map, as vector tiles in its map pack
(`MapPacks/hongkong/basemap.pmtiles`, decision 712).

    python3 -I tools/hk-map/build_hk_basemap.py hong_kong.pbf \\
        RailwayGameApp/Resources/MapPacks/hongkong/basemap.pmtiles

The tiles are Taiwan's (`tools/basemap/build_basemap.py`: the same layers,
classes and zooms, so the game's one style and its 3D map read both), made
from osmtoday.com's `asia/china/hong_kong.pbf` with pyosmium.

What differs is the coastline. Taiwan's is islands, every ring closed. Hong
Kong's mainland is part of China's, whose coast the extract cuts open: the
New Territories and Kowloon are one open line from Deep Bay round to Mirs
Bay, and a piece of Shekou's shore is another. Left out, as Taiwan's tool
leaves a cut ring out, they would be sea. So the open lines are joined, each
end to the nearest start (the missing shore between them, straight), and
the last end is taken back to the first start round the north, NORTH past
the northernmost point: the mainland is land. A line whose ends are within
GAP of each other is closed on itself.

The sea reaches SEA_MARGIN past the land, less than Taiwan's 2 degrees: the
map is 62 km wide.
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'basemap'))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'real-world-population'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_basemap  # noqa: E402
import build_hk_mtr  # noqa: E402

SEA_MARGIN = 0.25
NORTH = 0.05
# Metres.
GAP = 500.0


def metres(a, b):
    """Between two (lat, lon)."""
    dy = (a[0] - b[0]) * 111_320.0
    dx = (a[1] - b[1]) * 111_320.0 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot(dx, dy)


def coastline(path):
    """The coastline as closed rings of (lat, lon), how many open lines
    could not be closed (none), and the newest edit: the closed rings as
    they are, the open lines closed as the file's head says."""
    import osmium  # pyosmium.
    ways, newest = [], None

    class Handler(osmium.SimpleHandler):
        def way(self, way):
            nonlocal newest
            if way.tags.get('natural') == 'coastline':
                ways.append([(node.ref, node.lat, node.lon) for node in way.nodes])
                stamp = way.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
                newest = max(newest or stamp, stamp)

    Handler().apply_file(path, locations=True)
    starts = {}
    for index, way in enumerate(ways):
        starts.setdefault(way[0][0], []).append(index)
    ends = {way[-1][0] for way in ways}
    used, rings, lines = [False] * len(ways), [], []
    # A line is followed from its first way: one no other way leads to.
    for index in sorted(range(len(ways)), key=lambda i: ways[i][0][0] in ends):
        if used[index]:
            continue
        used[index] = True
        ring = list(ways[index])
        while ring[0][0] != ring[-1][0]:
            following = [n for n in starts.get(ring[-1][0], []) if not used[n]]
            if not following:
                break
            used[following[0]] = True
            ring += ways[following[0]][1:]
        points = [(lat, lon) for _, lat, lon in ring]
        if ring[0][0] == ring[-1][0]:
            rings.append(points)
        elif metres(points[0], points[-1]) <= GAP:
            rings.append(points + [points[0]])
        else:
            lines.append(points)
    if lines:
        # From the westernmost start, each end to the nearest start left.
        lines.sort(key=lambda line: line[0][1])
        joined, rest = list(lines[0]), lines[1:]
        while rest:
            nearest = min(rest, key=lambda line: metres(joined[-1], line[0]))
            rest.remove(nearest)
            joined += nearest
        north = max(lat for ring in rings + [joined] for lat, _ in ring) + NORTH
        joined += [(north, joined[-1][1]), (north, joined[0][1]), joined[0]]
        rings.append(joined)
        print(f'coastline: {len(lines)} open lines joined and closed round the north at {north:.4f}', flush=True)
    return rings, 0, newest


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build_basemap.SEA_MARGIN = SEA_MARGIN
    build_basemap.main(sys.argv[1], sys.argv[2], name='Hong Kong base map', center=(114.14, 22.35, 10), coastline=coastline)
    # The pack's list of its files and their sizes.
    build_hk_mtr.write_manifest(os.path.dirname(os.path.abspath(sys.argv[2])))
