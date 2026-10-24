#!/usr/bin/env python3
"""Every running track of Taiwan's real railways, one OpenStreetMap way
each, with the height the owner's site shows it at (decision 402): for the
3D map of a real-world game to lay the real lines as single, double or more
tracks, as they are, at the heights of their viaducts and tunnels.

    R=<railway-reference-private>/Railway/taiwan-rail-reference-clean/source/rail-3d/physical
    python3 -I tools/real-railways/extract_tracks.py \\
        "$R/network.json" "$R/metro-network.json" "$R/level-profiles.json" \\
        RailwayGameApp/Resources/RealRailways/rail_tracks.json

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
"""

import bisect
import hashlib
import json
import math
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


def points_of(way, entry):
    """The way's points as (longitude, latitude, height over the ground),
    with the profile's samples between them that bend its height."""
    coordinates = way["coordinates"]
    along = [0.0]
    for a, b in zip(coordinates, coordinates[1:]):
        along.append(along[-1] + distance(a, b))
    if entry is None:
        return [(lon, lat, 0.0) for lon, lat in coordinates]
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
    return [(lon, lat, h) for _, lon, lat, h, _ in kept]


def main(network_path, metro_path, profiles_path, out_path):
    with open(profiles_path, "rb") as f:
        profiles_bytes = f.read()
    profiles = json.loads(profiles_bytes)
    network_sha, network = read_network(network_path, "network.json", profiles)
    metro_sha, metro = read_network(metro_path, "metro-network.json", profiles)
    entries = profiles["entries"]
    systems = SYSTEMS + METRO_SYSTEMS

    ways = []
    for way in network["ways"] + metro["ways"]:
        if way["system"] not in systems or "service" in way["tags"] or len(way["coordinates"]) < 2:
            continue
        entry = entries.get(way["id"])
        kind = KINDS[(entry or {}).get("kind", "surface")]
        packed, previous = [], (0, 0, 0)
        for lon, lat, height in points_of(way, entry):
            point = (round(lon * 1e6), round(lat * 1e6), round(height * 10))
            packed.extend(p - q for p, q in zip(point, previous))
            previous = point
        ways.append({"way": way["id"], "system": systems.index(way["system"]), "kind": kind, "points": packed})
    ways.sort(key=lambda w: (w["system"], len(w["way"]), w["way"]))

    out = {
        "_readme": "Every running track (no siding, yard, spur or crossover) of the TRA, the High Speed Rail, the Alishan Forest Railway and the metros and light rails, one way of the site's network each, "
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


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
