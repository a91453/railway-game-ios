#!/usr/bin/env python3
"""Every running track of Taiwan's real railways, one OpenStreetMap way
each, with the height the owner's site shows it at (decision 402): for the
3D map of a real-world game to lay the real lines as single, double or more
tracks, as they are, at the heights of their viaducts and tunnels.

    R=<railway-reference-private>/Railway/taiwan-rail-reference-clean/source/rail-3d/physical
    python3 -I tools/real-railways/extract_tracks.py \\
        "$R/network.json" "$R/metro-network.json" "$R/level-profiles.json" \\
        RailwayGameApp/Resources/RealRailways/rail_tracks.json \\
        "$R/dispatch.json" RailwayGameApp/Resources/RealRailways/rail_dispatch.json

The inputs are those of `extract_structures.py` (decision 279): the site's
OpenStreetMap railway and metro ways (Overpass, ODbL 1.0) and
`level-profiles.json`, where the site settled each way's structure (bridge,
tunnel or surface; OpenStreetMap's tags filled in from the National Land
Surveying and Mapping Center's railway geometry, data.gov.tw 73220-73222,
Open Government Data License 1.0) and the height it draws it at.

What it keeps: every way of `SYSTEMS` and `METRO_SYSTEMS` with no `service`
tag (no siding, yard, spur or crossover), its kind, and its points with the
height of each over the ground: the profile's `flatOffsets` (the site's
flat map: the height over the ground at that point, every crossing's lower
line 7 m under the upper and shared nodes at one height, its viaducts eased
over 200 m and kept to each system's steepest grade). The site's absolute
heights (`values`, `terrainValues`) stand on its own terrain; the game has
its own ground, so it lays the height over it. Where the profile's samples
fall between a way's points they are kept as points of their own, unless
the height there is within `TOLERANCE` of the straight line between the
points either side kept.

The file is small: each way's points are whole numbers, a millionth of a
degree (about 0.1 m) and a tenth of a metre, the first point as it is and
each next the change from the one before.

Decision 600: with the site's `dispatch.json` (its estimated track
assignment of every Taiwan Railway, High Speed Rail and forest railway
train, `motion.js`/`plan-binding.js`), it also keeps the sidings,
crossovers and yard tracks those trains' paths run on (marked `"v":1`, so a
train with no assignment of its own keeps off them), and writes each
assignment (`rail_dispatch.json`): every path from one station to the next
as the stretches of the tracks it runs along (a track's way, and from
which of its points to which), and every train's stations and the path it
takes between each two.
"""

import bisect
import hashlib
import json
import math
import re
import sys

SYSTEMS = ("tra_sched", "thsr_sched", "afr_sched")
METRO_SYSTEMS = ("mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt")
KINDS = {"surface": "s", "bridge": "b", "tunnel": "t"}
# Metres: a profile sample this close to a way's point is that point, and
# one whose height is within this of the straight line is left out.
NEAR = 0.5
TOLERANCE = 0.15
EARTH_M = 6371000


def distance(a, b):
    """The site's `distanceM` (`integration/train-path.js`), metres."""
    r = math.pi / 180
    dy = (b[1] - a[1]) * r
    dx = (b[0] - a[0]) * r
    s = math.sin(dy / 2) ** 2 + math.cos(a[1] * r) * math.cos(b[1] * r) * math.sin(dx / 2) ** 2
    return 2 * EARTH_M * math.asin(min(1, math.sqrt(s)))


def sample(distances, values, s):
    """The site's `sample` (`route-runtime.js`): linear between samples."""
    hi = max(1, min(len(distances) - 1, bisect.bisect_right(distances, s)))
    lo = hi - 1
    span = distances[hi] - distances[lo] or 1
    f = max(0.0, min(1.0, (s - distances[lo]) / span))
    return values[lo] * (1 - f) + values[hi] * f


def read_network(path, name, profiles):
    with open(path, "rb") as f:
        data = f.read()
    expected = profiles["inputSha256"][name]
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        sys.exit(f"{name} is {actual}, the profiles were made from {expected}")
    return actual, json.loads(data)


def points_of(way, entry, flags=False):
    """The way's points as (longitude, latitude, height over the ground),
    with the profile's samples between them that bend its height; with
    `flags`, each also with whether it is one of the way's own points."""
    coordinates = way["coordinates"]
    along = [0.0]
    for a, b in zip(coordinates, coordinates[1:]):
        along.append(along[-1] + distance(a, b))
    if entry is None:
        return [(lon, lat, 0.0, True) if flags else (lon, lat, 0.0) for lon, lat in coordinates]
    distances = entry["distances"]
    heights = entry.get("flatOffsets") or entry["offsets"]
    # Every point of the way, and every sample between two of them.
    candidates = [(s, i, True) for i, s in enumerate(along)]
    for s in distances:
        i = bisect.bisect_right(along, s) - 1
        if 0 <= i < len(along) - 1 and s - along[i] > NEAR and along[i + 1] - s > NEAR:
            candidates.append((s, i, False))
    candidates.sort()
    full = []
    for s, i, vertex in candidates:
        if vertex:
            lon, lat = coordinates[i]
        else:
            f = (s - along[i]) / (along[i + 1] - along[i])
            (a, b) = coordinates[i], coordinates[i + 1]
            lon, lat = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
        full.append((s, lon, lat, sample(distances, heights, s), vertex))
    # The samples off the straight line between those kept either side.
    kept = [full[0]]
    for index in range(1, len(full) - 1):
        point = full[index]
        if point[4]:
            kept.append(point)
            continue
        last, after = kept[-1], full[index + 1]
        span = after[0] - last[0] or 1
        line = last[3] + (after[3] - last[3]) * (point[0] - last[0]) / span
        if abs(point[3] - line) > TOLERANCE:
            kept.append(point)
    kept.append(full[-1])
    return [(lon, lat, h, vertex) if flags else (lon, lat, h) for _, lon, lat, h, vertex in kept]


def station_key(name):
    """The site's `stationKey` (`timing.js`) without its system."""
    name = re.sub(r"\s*[（(].*?[）)]", "", str(name).replace("臺", "台"))
    if name.endswith("-環島"):
        name = name[: -len("-環島")]
    return name.strip()


def vertex_indices(way, entry):
    """Where each of the way's points is among `points_of`'s, which keep
    every point of the way and some between."""
    return [index for index, point in enumerate(points_of(way, entry, flags=True)) if point[3]]


def write_dispatch(dispatch_path, dispatch_out, network, entries, kept_ids):
    """Decision 600: `rail_dispatch.json`, the site's track assignment."""
    with open(dispatch_path, "rb") as f:
        dispatch_bytes = f.read()
    dispatch = json.loads(dispatch_bytes)
    if dispatch["source"]["at"] != network["source"]["at"]:
        sys.exit("dispatch.json was made from another network.json")
    ways = network["ways"]
    vertices = {}
    paths, path_index = [], {}

    def path(pid):
        if pid in path_index:
            return path_index[pid]
        record = network["paths"][str(pid)]
        runs = []
        for wi, start, count in record["walk"]:
            way = ways[wi]
            if way["id"] not in kept_ids:
                sys.exit(f"path {pid} runs on way {way['id']}, which is not kept")
            if wi not in vertices:
                vertices[wi] = vertex_indices(way, entries.get(way["id"]))
            # The site's `unfold` (`route-runtime.js`): `count` edges from
            # point `start` on, or back from `start + 1`.
            first, end = (start, start + count) if count > 0 else (start + 1, start + count + 1)
            runs.extend([way["id"], vertices[wi][first], vertices[wi][end]])
        path_index[pid] = len(paths)
        paths.append(runs)
        return path_index[pid]

    systems = list(SYSTEMS)
    stations, station_index = [], {}
    plans, seen = [], set()
    for key in sorted(dispatch["plans"], key=lambda k: (k.split(":")[0], k)):
        plan = dispatch["plans"][key]
        system, number, first, last = key.split(":")
        signature = json.loads(plan["stopSignature"])
        if len(plan["pathIds"]) != len(signature) - 1:
            sys.exit(f"{key}: its paths are not one between each two stations")
        names = []
        for code, _, _ in signature:
            name = station_key(code.split(":", 1)[1])
            if name not in station_index:
                station_index[name] = len(stations)
                stations.append(name)
            names.append(station_index[name])
        pids = [path(pid) for pid in plan["pathIds"]]
        calls = [1 if i == 0 or i == len(signature) - 1 or s[2] > s[1] else 0 for i, s in enumerate(signature)]
        made = {"s": systems.index(system), "n": number, "k": [int(first), int(last)], "t": names, "q": calls, "p": pids}
        if plan.get("templateEligible") is False:
            made["x"] = 1
        same = json.dumps([made["s"], number, names, pids, calls])
        if same in seen:
            continue
        seen.add(same)
        plans.append(made)
    out = {
        "_readme": "Decision 600: the owner's site's estimated track assignment (rail-3d/physical/dispatch.json) of every Taiwan Railway, High Speed Rail and forest railway train. "
        "paths: each path from a station to the next, as [way, from point, to point] of rail_tracks.json's ways, in the order it runs; "
        "plans: each train's system (s), number (n), first departure and last arrival seconds (k), stations (t, of stations), whether it calls at each (q), "
        "the path between each two (p, of paths), and x when no other train may borrow its paths. An estimate, not the railway's own. "
        "Made by tools/real-railways/extract_tracks.py; do not edit.",
        "source": {
            "openStreetMap": {"attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "at": network["source"]["at"]},
            "assignmentBasis": dispatch["assignmentBasis"],
            "dispatchSha256": hashlib.sha256(dispatch_bytes).hexdigest(),
        },
        "systems": systems,
        "stations": stations,
        "paths": paths,
        "plans": plans,
    }
    with open(dispatch_out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{len(plans)} plans, {len(paths)} paths, {len(stations)} stations")


def used_ways(dispatch_path, network):
    """The ways the site's dispatched trains' paths run on."""
    with open(dispatch_path, "rb") as f:
        dispatch = json.load(f)
    used = set()
    for plan in dispatch["plans"].values():
        for pid in plan["pathIds"]:
            for wi, _, _ in network["paths"][str(pid)]["walk"]:
                used.add(network["ways"][wi]["id"])
    return used


def main(network_path, metro_path, profiles_path, out_path, dispatch_path=None, dispatch_out=None):
    with open(profiles_path, "rb") as f:
        profiles_bytes = f.read()
    profiles = json.loads(profiles_bytes)
    network_sha, network = read_network(network_path, "network.json", profiles)
    metro_sha, metro = read_network(metro_path, "metro-network.json", profiles)
    entries = profiles["entries"]
    systems = SYSTEMS + METRO_SYSTEMS

    dispatched = used_ways(dispatch_path, network) if dispatch_path else set()
    ways = []
    for way in network["ways"] + metro["ways"]:
        if way["system"] not in systems or len(way["coordinates"]) < 2:
            continue
        service = "service" in way["tags"]
        if service and way["id"] not in dispatched:
            continue
        entry = entries.get(way["id"])
        kind = KINDS[(entry or {}).get("kind", "surface")]
        packed, previous = [], (0, 0, 0)
        for lon, lat, height in points_of(way, entry):
            point = (round(lon * 1e6), round(lat * 1e6), round(height * 10))
            packed.extend(p - q for p, q in zip(point, previous))
            previous = point
        made = {"way": way["id"], "system": systems.index(way["system"]), "kind": kind, "points": packed}
        if service:
            made["v"] = 1
        ways.append(made)
    ways.sort(key=lambda w: (w["system"], len(w["way"]), w["way"]))

    out = {
        "_readme": "Every running track (no siding, yard, spur or crossover, but those a dispatched train runs on, marked v) of the TRA, the High Speed Rail, the Alishan Forest Railway and the metros and light rails, one way of the site's network each, "
        "with its kind (s surface, b bridge or viaduct, t tunnel) and its points as [longitude, latitude, height over the ground] in millionths of a degree and tenths of a metre, "
        "the first point as it is and each next the change from the one before. Made by tools/real-railways/extract_tracks.py (decision 402); do not edit.",
        "source": {
            "openStreetMap": {
                "attribution": "© OpenStreetMap contributors",
                "license": "ODbL-1.0",
                "at": network["source"]["at"],
                "metroAt": metro["source"]["at"],
            },
            "official": {
                "attribution": "內政部國土測繪中心「臺灣鐵路」「高速鐵路」「捷運」",
                "url": "https://data.gov.tw/dataset/73220 https://data.gov.tw/dataset/73221 https://data.gov.tw/dataset/73222",
                "license": "Open Government Data License 1.0",
            },
            "heights": profiles["flatBasis"],
            "networkSha256": network_sha,
            "metroNetworkSha256": metro_sha,
            "profilesSha256": hashlib.sha256(profiles_bytes).hexdigest(),
        },
        "systems": list(systems),
        "ways": ways,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    points = sum(len(w["points"]) // 3 for w in ways)
    counts = {system: sum(1 for w in ways if w["system"] == i) for i, system in enumerate(systems)}
    print(f"{len(ways)} ways, {points} points: {counts}")
    if dispatch_path:
        write_dispatch(dispatch_path, dispatch_out, network, entries, {w["way"] for w in ways})


if __name__ == "__main__":
    if len(sys.argv) not in (5, 7):
        sys.exit(__doc__)
    main(*sys.argv[1:])
