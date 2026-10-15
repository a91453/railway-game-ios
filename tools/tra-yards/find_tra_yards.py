#!/usr/bin/env python3
"""The Taiwan Railway's yards along the Yilan Line, Toucheng to Su'ao, from
OpenStreetMap (ODbL 1.0), for the TRA demo's sidings (ARCHITECTURE
decision 240).

Reads a whole extract of Taiwan (osmtoday.com's `asia/taiwan.pbf`, as every
data tool of the game does; pyosmium, BSD 2-Clause) and prints each cluster
of `service=yard|siding|spur` rail ways inside the line's box: the tracks'
total length, the middle of their nodes, how many ways, and their names.
Ways are one cluster where they share a node.

    python3 -I tools/tra-yards/find_tra_yards.py taiwan.pbf
"""

import collections
import math
import sys

import osmium

SOUTH, NORTH, WEST, EAST = 24.58, 24.90, 121.70, 121.90


class Tracks(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = {}

    def way(self, w):
        if w.tags.get("railway") != "rail" or w.tags.get("service") not in ("yard", "siding", "spur"):
            return
        try:
            nodes = [(n.ref, n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if any(SOUTH < lat < NORTH and WEST < lon < EAST for _, lat, lon in nodes):
            self.ways[w.id] = {"tags": dict(w.tags), "nodes": nodes}


def length(nodes):
    total = 0.0
    for (_, a, b), (_, c, d) in zip(nodes, nodes[1:]):
        total += math.hypot((c - a) * 110_850, (d - b) * 111_320 * math.cos(math.radians(a)))
    return total


def main():
    tracks = Tracks()
    tracks.apply_file(sys.argv[1], locations=True)
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            x = parent[x]
        return x

    by_node = collections.defaultdict(list)
    for wid, way in tracks.ways.items():
        for node, _, _ in way["nodes"]:
            by_node[node].append(wid)
    for ways in by_node.values():
        for other in ways[1:]:
            parent[find(other)] = find(ways[0])
    clusters = collections.defaultdict(list)
    for wid in tracks.ways:
        clusters[find(wid)].append(tracks.ways[wid])
    rows = []
    for ways in clusters.values():
        points = [(lat, lon) for way in ways for _, lat, lon in way["nodes"]]
        middle = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        names = sorted({way["tags"].get("name", "") for way in ways} - {""})
        rows.append((sum(length(way["nodes"]) for way in ways), middle, len(ways), names))
    for total, middle, count, names in sorted(rows, reverse=True):
        if total >= 100:
            print(f"{total:7.0f} m  {middle[0]:.5f}, {middle[1]:.5f}  {count} ways  {', '.join(names)}")


if __name__ == "__main__":
    main()
