#!/usr/bin/env python3
"""Whether each TRA and High Speed Rail station's platforms are islands or
side platforms, from OpenStreetMap (ODbL 1.0); decision 741.

Reads a whole extract of Taiwan (osmtoday.com's `asia/taiwan.pbf`, as every
data tool of the game does; pyosmium, BSD 2-Clause). At each station of
`track_stations.geojson` whose system is `tra_sched` or `thsr_sched`, it
counts the tracks side by side through the station (as
`tools/hsr-platforms/build_hsr_platforms.py` does) and takes each platform
near it: an island when its own system's track runs within `BESIDE` metres
of its middle on both sides, else a side platform. The station is `island`
(every platform an island), `side` (none), `mixed`, or `unknown` (OSM draws
no platform there).

    python3 -I build_platform_types.py taiwan.pbf track_stations.geojson out.json
"""

import json
import math
import sys

import osmium

LAT_M = 110_850.0
REACH = 300.0
STEP = 10.0
HALF_WIDTH = 60.0
PLATFORM_REACH = 400.0
# A platform's middle to its own track: at most this far (a 12 m island's
# middle stands some 7.5 m from each of its tracks' middles).
BESIDE = 9.0
SYSTEMS = {"tra_sched": "1067", "thsr_sched": "1435"}


def lon_m(lat):
    return 111_320.0 * math.cos(math.radians(lat))


def is_high_speed(tags):
    text = tags.get("operator", "") + tags.get("name", "") + tags.get("network", "")
    return tags.get("highspeed") == "yes" or "高速鐵路" in text or "高鐵" in text


class Features(osmium.SimpleHandler):
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
        if tags.get("railway") == "rail" and tags.get("gauge", "") in ("1067", "1435", ""):
            self.ways[w.id] = {"tags": dict(tags), "nodes": points}
        if tags.get("railway") == "platform" or (tags.get("public_transport") == "platform" and tags.get("train") == "yes"):
            lat = sum(p[1] for p in points) / len(points)
            lon = sum(p[2] for p in points) / len(points)
            self.platforms.append({"id": w.id, "tags": dict(tags), "centre": (lat, lon)})


def component(ways, seeds):
    by_node = {}
    for i, w in ways.items():
        for n, _, _ in w["nodes"]:
            by_node.setdefault(n, []).append(i)
    reached, frontier = set(), list(seeds)
    while frontier:
        i = frontier.pop()
        if i in reached:
            continue
        reached.add(i)
        for n, _, _ in ways[i]["nodes"]:
            frontier.extend(j for j in by_node.get(n, []) if j not in reached)
    return reached


def main(pbf, stations_path, out_path):
    handler = Features()
    handler.apply_file(pbf, locations=True)
    ways = handler.ways
    # Each system's track: the High Speed Rail's as its tool joins it; the
    # TRA's every 1067 mm rail way (the metros' and HSR's are 1435 mm).
    hsr = component(ways, [i for i, w in ways.items() if is_high_speed(w["tags"])])
    tracks_of = {
        "thsr_sched": hsr,
        "tra_sched": {i for i, w in ways.items() if w["tags"].get("gauge") == "1067" and i not in hsr},
    }
    seen, stations = set(), []
    for f in json.load(open(stations_path, encoding="utf-8"))["features"]:
        p = f["properties"]
        key = (p.get("sys"), p["name"])
        if p.get("sys") in SYSTEMS and key not in seen:
            seen.add(key)
            stations.append((p["sys"], p["name"], p.get("lineId"), f["geometry"]["coordinates"][1], f["geometry"]["coordinates"][0]))

    out = []
    for system, name, line, lat0, lon0 in stations:
        kx = lon_m(lat0)
        own = tracks_of[system]

        def plain(lat, lon):
            return (lon - lon0) * kx, (lat - lat0) * LAT_M

        near_ways = []
        for i in own:
            nodes = ways[i]["nodes"]
            if any(abs(plain(a, b)[0]) < PLATFORM_REACH + 200 and abs(plain(a, b)[1]) < PLATFORM_REACH + 200 for _, a, b in nodes):
                near_ways.append(i)
        best = None
        for i in near_ways:
            if "service" in ways[i]["tags"]:
                continue
            nodes = ways[i]["nodes"]
            for (_, a, b), (_, c, d) in zip(nodes, nodes[1:]):
                p, q = plain(a, b), plain(c, d)
                dx, dy = q[0] - p[0], q[1] - p[1]
                length2 = dx * dx + dy * dy
                if length2 == 0:
                    continue
                t = max(0.0, min(1.0, -(p[0] * dx + p[1] * dy) / length2))
                distance = math.hypot(p[0] + t * dx, p[1] + t * dy)
                if best is None or distance < best[0]:
                    best = (distance, dx / math.sqrt(length2), dy / math.sqrt(length2), p[0] + t * dx, p[1] + t * dy)
        if best is None or best[0] > 150:
            out.append({"system": system, "station": name, "line": line, "type": "unknown", "reason": "no track near the station's point"})
            continue
        _, ux, uy, fx, fy = best
        nx, ny = -uy, ux

        def local(lat, lon):
            x, y = plain(lat, lon)
            x, y = x - fx, y - fy
            return x * ux + y * uy, x * nx + y * ny

        segments = []
        for i in near_ways:
            nodes = ways[i]["nodes"]
            for (_, a, b), (_, c, d) in zip(nodes, nodes[1:]):
                s0, s1 = local(a, b)
                t0, t1 = local(c, d)
                segments.append((s0, s1, t0, t1, i))

        def crossing(at, width):
            sides = {}
            for s0, s1, t0, t1, i in segments:
                if min(s0, t0) <= at < max(s0, t0) and s0 != t0:
                    side = s1 + (at - s0) / (t0 - s0) * (t1 - s1)
                    if abs(side) <= width:
                        sides[i] = side
            return sorted(sides.values())

        profile = [len(crossing(-REACH + k * STEP, HALF_WIDTH)) for k in range(int(2 * REACH / STEP) + 1)]
        tracks = max(set(profile), key=lambda c: (profile.count(c), c))

        platforms = []
        for platform in handler.platforms:
            along, side = local(*platform["centre"])
            if math.hypot(along, side) > PLATFORM_REACH:
                continue
            here = crossing(along, HALF_WIDTH + 20)
            left = [side - s for s in here if 0.5 < side - s <= BESIDE]
            right = [s - side for s in here if 0.5 < s - side <= BESIDE]
            if not left and not right:
                continue
            if any(abs(other["side"] - side) < 3 for other in platforms):
                continue
            platforms.append({
                "way": platform["id"], "name": platform["tags"].get("name"), "side": round(side, 1),
                "kind": "island" if left and right else "side",
            })
        platforms.sort(key=lambda p: p["side"])
        kinds = {p["kind"] for p in platforms}
        kind = "unknown" if not kinds else kinds.pop() if len(kinds) == 1 else "mixed"
        out.append({
            "system": system, "station": name, "line": line, "type": kind, "tracks": tracks,
            "islands": sum(p["kind"] == "island" for p in platforms), "sides": sum(p["kind"] == "side" for p in platforms),
            "platforms": platforms,
        })
        print(system, name, kind, "tracks", tracks, [(p["kind"], p["side"]) for p in platforms])

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "source": "© OpenStreetMap contributors, ODbL 1.0 (osmtoday.com asia/taiwan.pbf)",
            "stations": out,
        }, f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
