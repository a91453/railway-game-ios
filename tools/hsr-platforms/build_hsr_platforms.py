#!/usr/bin/env python3
"""The Taiwan High Speed Rail's stations' tracks and platforms, from
OpenStreetMap (ODbL 1.0).

Reads a whole extract of Taiwan (osmtoday.com's `asia/taiwan.pbf`, as every
data tool of the game does; pyosmium, BSD 2-Clause) and, at each of the High
Speed Rail's twelve stations, counts how many of its tracks lie side by side
through the station and how many platforms stand beside them. Writes one
JSON file (`hsr_platforms.json`); the README says how it was made and what
it found.

    python3 -I build_hsr_platforms.py taiwan.pbf track_stations.geojson out.json

`track_stations.geojson` is the app's (`RailwayGameApp/Resources/
RealRailways/`): where the twelve stations are.
"""

import json
import math
import sys

import osmium

# Metres per degree near Taiwan.
LAT_M = 110_850.0
# How far along the line either side of the station the cross-sections are
# tried, how far apart, and how wide each is (metres).
REACH = 300.0
STEP = 10.0
HALF_WIDTH = 60.0
# How far from the station's point a platform may be, and how far its
# middle from the nearest of the High Speed Rail's tracks (metres).
PLATFORM_REACH = 400.0
PLATFORM_GAP = 10.0


def lon_m(lat):
    return 111_320.0 * math.cos(math.radians(lat))


def is_high_speed(tags):
    text = tags.get("operator", "") + tags.get("name", "") + tags.get("network", "")
    return tags.get("highspeed") == "yes" or "高速鐵路" in text or "高鐵" in text


class Features(osmium.SimpleHandler):
    """Every standard-gauge rail way with its nodes, and every platform."""

    def __init__(self):
        super().__init__()
        self.ways = {}
        self.platforms = []

    def way(self, w):
        tags = w.tags
        try:
            points = [(n.ref, n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if tags.get("railway") == "rail" and tags.get("gauge", "1435") == "1435":
            self.ways[w.id] = {"tags": dict(tags), "nodes": points}
        if tags.get("railway") == "platform" or (tags.get("public_transport") == "platform" and tags.get("train") == "yes"):
            lat = sum(p[1] for p in points) / len(points)
            lon = sum(p[2] for p in points) / len(points)
            self.platforms.append({"id": w.id, "tags": dict(tags), "centre": (lat, lon), "nodes": [(a, b) for _, a, b in points]})


def main(pbf, stations_path, out_path):
    handler = Features()
    handler.apply_file(pbf, locations=True)
    ways = handler.ways

    # The High Speed Rail's track: its line, and every rail way joined to it
    # by shared nodes (as the reference's topology.js joins track), so the
    # stations' untagged loops count and the other railways' (the metro's
    # standard gauge beside it in Taipei) do not.
    line = {i for i, w in ways.items() if is_high_speed(w["tags"])}
    by_node = {}
    for i, w in ways.items():
        for n, _, _ in w["nodes"]:
            by_node.setdefault(n, []).append(i)
    reached, frontier = set(), list(line)
    while frontier:
        i = frontier.pop()
        if i in reached:
            continue
        reached.add(i)
        for n, _, _ in ways[i]["nodes"]:
            frontier.extend(j for j in by_node.get(n, []) if j not in reached)
    main_line = [i for i in line if "service" not in ways[i]["tags"]]

    stations = [
        (f["properties"]["name"], f["geometry"]["coordinates"][1], f["geometry"]["coordinates"][0])
        for f in json.load(open(stations_path, encoding="utf-8"))["features"]
        if f["properties"].get("sys") == "thsr_sched"
    ]

    out = []
    for name, lat0, lon0 in stations:
        kx = lon_m(lat0)

        def xy(lat, lon):
            return (lon - lon0) * kx, (lat - lat0) * LAT_M

        # The line's way at the station: the main-line segment nearest it.
        best = None
        for i in main_line:
            nodes = ways[i]["nodes"]
            for (_, a, b), (_, c, d) in zip(nodes, nodes[1:]):
                p, q = xy(a, b), xy(c, d)
                dx, dy = q[0] - p[0], q[1] - p[1]
                length2 = dx * dx + dy * dy
                if length2 == 0:
                    continue
                t = max(0.0, min(1.0, -(p[0] * dx + p[1] * dy) / length2))
                distance = math.hypot(p[0] + t * dx, p[1] + t * dy)
                if best is None or distance < best[0]:
                    best = (distance, dx / math.sqrt(length2), dy / math.sqrt(length2), p[0] + t * dx, p[1] + t * dy)
        _, ux, uy, fx, fy = best
        nx, ny = -uy, ux

        # Measured from the foot of the station's point on the line.
        def xy(lat, lon, plain=xy):
            x, y = plain(lat, lon)
            return x - fx, y - fy

        segments = []
        for i in reached:
            nodes = ways[i]["nodes"]
            for (_, a, b), (_, c, d) in zip(nodes, nodes[1:]):
                p, q = xy(a, b), xy(c, d)
                segments.append((p[0] * ux + p[1] * uy, p[0] * nx + p[1] * ny, q[0] * ux + q[1] * uy, q[0] * nx + q[1] * ny, i))

        # Tracks side by side: the most the line across the station crosses,
        # tried every `STEP` along it.
        profile = []
        at = -REACH
        while at <= REACH:
            crossing = set()
            for s0, s1, t0, t1, i in segments:
                if min(s0, t0) <= at < max(s0, t0) and s0 != t0:
                    side = s1 + (at - s0) / (t0 - s0) * (t1 - s1)
                    if abs(side) <= HALF_WIDTH:
                        crossing.add(i)
            profile.append(len(crossing))
            at += STEP

        # Platforms: those near the station beside the High Speed Rail's
        # track (a track of it within `PLATFORM_GAP` of the platform's
        # middle; the other railways' platforms beside it, Taipei's and
        # Xinzuoying's, are not), each once (OSM often has a platform both
        # as an area and as a line).
        def gap(x, y):
            least = math.inf
            for s0, s1, t0, t1, _ in segments:
                along, side = x * ux + y * uy, x * nx + y * ny
                if min(s0, t0) <= along <= max(s0, t0) and s0 != t0:
                    least = min(least, abs(side - (s1 + (along - s0) / (t0 - s0) * (t1 - s1))))
            return least

        near = []
        for platform in handler.platforms:
            x, y = xy(*platform["centre"])
            along, side = x * ux + y * uy, x * nx + y * ny
            if math.hypot(x, y) > PLATFORM_REACH or gap(x, y) > PLATFORM_GAP:
                continue
            if any(abs(other["side"] - side) < 3 for other in near):
                continue
            tags = platform["tags"]
            near.append({"way": platform["id"], "name": tags.get("name"), "side": round(side, 1)})
        near.sort(key=lambda p: p["side"])
        # The tracks through the station: the count the cross-sections
        # find most often (a ladder's diagonals add one here and there).
        tracks = max(set(profile), key=lambda c: (profile.count(c), c))
        out.append({
            "station": name,
            "tracks": tracks,
            "platforms": near,
        })
        print(name, "tracks", tracks, "platforms", len(near), [(p["name"], p["side"]) for p in near])

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "source": "© OpenStreetMap contributors, ODbL 1.0 (osmtoday.com asia/taiwan.pbf)",
            "stations": out,
        }, f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
