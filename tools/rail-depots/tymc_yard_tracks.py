#!/usr/bin/env python3
"""How many stabling tracks the Taoyuan Airport MRT's two depots have
(decision 829), read from a whole OpenStreetMap extract of Taiwan
(osmtoday.com's asia/taiwan.pbf, ODbL) with pyosmium.

    python3 -I tymc_yard_tracks.py taiwan.pbf

Taoyuan Metro publishes no stabling capacity of the Luzhu and Qingpu
depots, so the game counts the stabling tracks OpenStreetMap maps: of
the `service=yard` ways of each depot's stabling banks (the ranges of
way ids below, mapped together), those long enough for a train (110 m:
a five-car express is some 102 m). `RealLineDepotSite.luzhu` and
`.qingpu` in `Sources/GamePresentation/RealLineDepot.swift` lay fewer
(16 and 12): decision 829 has what the real counts did to the morning's
first runs.

- Luzhu (蘆竹機廠): ways 1576463688 to 1576463746, the banks north-west
  of the workshop: 17 of some 119 m and 6 of some 152 m, 23. The
  shorter ones among them (some 94 m) are not counted, nor is the one of
  some 254 m (way 1576463719), the lead they leave.
- Qingpu (青埔機廠): ways 499824857 to 499824866 and 499831993 to
  499832001, the banks beside the line (`RealLineDepotSite.qingpu`'s
  yard): 15 of 228 m or longer; the four short ones are pieces of
  turnouts.
"""
import math
import sys

import osmium

DEPOTS = {
    "Luzhu": [(1576463688, 1576463746)],
    "Qingpu": [(499824857, 499824866), (499831993, 499832001)],
}
LONG_ENOUGH = 110


def metres(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((a[0] - b[0]) * 111_320, (a[1] - b[1]) * 111_320 * k)


class Reader(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.tracks = {name: [] for name in DEPOTS}

    def way(self, w):
        for name, ranges in DEPOTS.items():
            if any(low <= w.id <= high for low, high in ranges):
                tags = dict(w.tags)
                if tags.get("railway") in ("rail", "subway", "light_rail") and tags.get("service") == "yard":
                    points = [(n.lat, n.lon) for n in w.nodes]
                    self.tracks[name].append((w.id, sum(metres(points[i], points[i + 1]) for i in range(len(points) - 1))))


def main(path):
    reader = Reader()
    reader.apply_file(path, locations=True)
    for name, tracks in reader.tracks.items():
        long = sorted(length for _, length in tracks if length >= LONG_ENOUGH)
        short = sorted(length for _, length in tracks if length < LONG_ENOUGH)
        print(f"{name} depot: {len(tracks)} yard tracks in the stabling banks; {len(long)} of {LONG_ENOUGH} m or longer"
              f" ({long[0]:.0f} to {long[-1]:.0f} m)" + (f"; {len(short)} shorter ({short[0]:.0f} to {short[-1]:.0f} m)" if short else ""))
        groups = {}
        for length in long:
            groups[round(length / 10) * 10] = groups.get(round(length / 10) * 10, 0) + 1
        print("  by length, to the nearest 10 m: " + ", ".join(f"{count} of {metres_} m" for metres_, count in sorted(groups.items())))


if __name__ == "__main__":
    main(sys.argv[1])
