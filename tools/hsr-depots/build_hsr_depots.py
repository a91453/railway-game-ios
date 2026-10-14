#!/usr/bin/env python3
"""The Taiwan High Speed Rail's real depots, from OpenStreetMap (ODbL 1.0).

Reads a whole extract of Taiwan (osmtoday.com's `asia/taiwan.pbf`, as every
data tool of the game does; pyosmium, BSD 2-Clause) and finds where the
High Speed Rail keeps its sets: the clusters of yard, siding and spur tracks
joined to its line, each with the main-line turnouts it leaves by, how many
stabling tracks lie side by side, and how long they are. Writes one JSON
file (`hsr_depots.json`); the README says how it was made and what it found.

    python3 -I build_hsr_depots.py taiwan.pbf track_stations.geojson out.json

`track_stations.geojson` is the app's (`RailwayGameApp/Resources/
RealRailways/`): the High Speed Rail's twelve stations, by which a depot is
named for the station it stands by.
"""

import json
import math
import sys

import osmium

# Yards closer than this are one depot (metres).
NEAR = 300.0

# Metres per degree near Taiwan (the clusters are a few kilometres across).
LAT_M = 110_850.0


def lon_m(lat):
    return 111_320.0 * math.cos(math.radians(lat))


def is_high_speed(tags):
    text = tags.get("operator", "") + tags.get("name", "") + tags.get("network", "")
    return tags.get("highspeed") == "yes" or "高速鐵路" in text or "高鐵" in text


class Tracks(osmium.SimpleHandler):
    """Every rail way with its nodes; the depots' named areas."""

    def __init__(self):
        super().__init__()
        self.ways = {}
        self.areas = []

    def way(self, w):
        tags = w.tags
        try:
            points = [(n.ref, n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if tags.get("railway") == "rail" and tags.get("gauge", "1435") == "1435":
            self.ways[w.id] = {"tags": dict(tags), "nodes": points}
        name = tags.get("name", "")
        if tags.get("landuse") == "railway" and "高鐵" in name and len(points) > 3 and points[0][0] == points[-1][0]:
            self.areas.append({"id": w.id, "name": name, "ring": [(lat, lon) for _, lat, lon in points]})


def inside(ring, lat, lon):
    hit = False
    for (a_lat, a_lon), (b_lat, b_lon) in zip(ring, ring[1:]):
        if (a_lat > lat) != (b_lat > lat):
            cross = a_lon + (lat - a_lat) / (b_lat - a_lat) * (b_lon - a_lon)
            if lon < cross:
                hit = not hit
    return hit


def length_m(points):
    total = 0.0
    for (_, a, b), (_, c, d) in zip(points, points[1:]):
        total += math.hypot((c - a) * LAT_M, (d - b) * lon_m(a))
    return total


def main(pbf, stations_path, out_path):
    handler = Tracks()
    handler.apply_file(pbf, locations=True)
    ways = handler.ways

    main_line = {i for i, w in ways.items() if is_high_speed(w["tags"]) and "service" not in w["tags"]}
    main_nodes = {n for i in main_line for n, _, _ in ways[i]["nodes"]}
    service = {i for i, w in ways.items() if w["tags"].get("service") in ("yard", "siding", "spur", "crossover") and i not in main_line}

    # The service tracks reachable from the High Speed Rail's line by shared
    # nodes (as the reference's topology.js joins track: by nodes, never by
    # nearness), so untagged yard tracks of its depots count and the other
    # railways' do not.
    by_node = {}
    for i in service:
        for n, _, _ in ways[i]["nodes"]:
            by_node.setdefault(n, []).append(i)
    reached, frontier = set(), [i for i in service if any(n in main_nodes for n, _, _ in ways[i]["nodes"])]
    while frontier:
        i = frontier.pop()
        if i in reached:
            continue
        reached.add(i)
        for n, _, _ in ways[i]["nodes"]:
            if n in main_nodes:
                continue
            frontier.extend(j for j in by_node.get(n, []) if j not in reached)

    # Clusters: the reached tracks joined to one another by a node off the
    # main line. A station's loops are crossovers and sidings beside its
    # platforms; a depot is the cluster with yard tracks.
    parent = {i: i for i in reached}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for n, ids in by_node.items():
        if n in main_nodes:
            continue
        ids = [i for i in ids if i in reached]
        for j in ids[1:]:
            parent[find(j)] = find(ids[0])
    clusters = {}
    for i in reached:
        clusters.setdefault(find(i), []).append(i)

    # Yards that only meet on the main line (Nangang's two stabling tracks,
    # one off each through track) but lie within `NEAR` of one another are
    # one depot.
    def middle(members):
        points = [(lat, lon) for i in members for _, lat, lon in ways[i]["nodes"]]
        return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)

    merged = []
    for members in sorted(clusters.values(), key=min):
        lat, lon = middle(members)
        for other in merged:
            o_lat, o_lon = middle(other)
            if math.hypot((lat - o_lat) * LAT_M, (lon - o_lon) * lon_m(lat)) < NEAR:
                other.extend(members)
                break
        else:
            merged.append(list(members))

    stations = [
        (f["properties"]["name"], f["geometry"]["coordinates"][1], f["geometry"]["coordinates"][0])
        for f in json.load(open(stations_path, encoding="utf-8"))["features"]
        if f["properties"].get("sys") == "thsr_sched"
    ]

    depots = []
    for members in merged:
        yard = [i for i in members if ways[i]["tags"].get("service") in ("yard", "spur")]
        yard_length = sum(length_m(ways[i]["nodes"]) for i in yard)
        if yard_length < 1_000:
            continue
        points = [(lat, lon) for i in yard for _, lat, lon in ways[i]["nodes"]]
        lat0 = sum(p[0] for p in points) / len(points)
        lon0 = sum(p[1] for p in points) / len(points)
        kx = lon_m(lat0)
        xy = [((lon - lon0) * kx, (lat - lat0) * LAT_M) for lat, lon in points]
        # The yard's long axis: its points' principal direction.
        sxx = sum(x * x for x, _ in xy)
        syy = sum(y * y for _, y in xy)
        sxy = sum(x * y for x, y in xy)
        angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
        ux, uy = math.cos(angle), math.sin(angle)
        along = [x * ux + y * uy for x, y in xy]
        lo, hi = min(along), max(along)

        # Stabling tracks side by side: the most yard tracks a line across
        # the yard crosses, tried every 10 m along it.
        def segments():
            for i in yard:
                nodes = ways[i]["nodes"]
                for (_, a, b), (_, c, d) in zip(nodes, nodes[1:]):
                    p = ((b - lon0) * kx, (a - lat0) * LAT_M)
                    q = ((d - lon0) * kx, (c - lat0) * LAT_M)
                    yield p[0] * ux + p[1] * uy, q[0] * ux + q[1] * uy, i

        segs = list(segments())
        tracks, best_at = 0, lo
        at = lo
        while at <= hi:
            crossing = len({i for s, t, i in segs if min(s, t) <= at < max(s, t)})
            if crossing > tracks:
                tracks, best_at = crossing, at
            at += 10.0
        # The stretch where at least half that many lie side by side: how
        # long a set's track there is.
        stretch = [a for a in [lo + 10.0 * k for k in range(int((hi - lo) / 10.0) + 1)]
                   if len({i for s, t, i in segs if min(s, t) <= a < max(s, t)}) * 2 >= tracks]
        usable = (max(stretch) - min(stretch)) if stretch else 0.0

        turnouts = sorted({(n, lat, lon) for i in members for n, lat, lon in ways[i]["nodes"] if n in main_nodes})
        station = min(stations, key=lambda s: math.hypot((s[1] - lat0) * LAT_M, (s[2] - lon0) * kx))
        distance = math.hypot((station[1] - lat0) * LAT_M, (station[2] - lon0) * kx)
        area = next((a for a in handler.areas if inside(a["ring"], lat0, lon0)), None)
        depots.append({
            "station": station[0],
            "stationDistance": round(distance),
            "area": {"name": area["name"], "way": area["id"]} if area else None,
            "centre": [round(lat0, 6), round(lon0, 6)],
            "axis": round(math.degrees(math.atan2(ux, uy)) % 180, 1),
            "tracks": tracks,
            "trackLength": round(usable),
            "yardLength": round(yard_length),
            "turnouts": [[round(lat, 6), round(lon, 6), n] for n, lat, lon in turnouts],
            "ways": sorted(members),
        })
    depots.sort(key=lambda d: -d["centre"][0])
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump({
            "source": "© OpenStreetMap contributors, ODbL 1.0 (osmtoday.com asia/taiwan.pbf)",
            "depots": depots,
        }, out, ensure_ascii=False, indent=1)
        out.write("\n")
    for d in depots:
        print(d["station"], d["stationDistance"], (d["area"] or {}).get("name"), d["centre"], "tracks", d["tracks"],
              "length", d["trackLength"], "yard", d["yardLength"], "turnouts", len(d["turnouts"]))


if __name__ == "__main__":
    main(*sys.argv[1:4])
