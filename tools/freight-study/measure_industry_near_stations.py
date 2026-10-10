#!/usr/bin/env python3
"""Where the real-world map has industrial land beside a railway station.

Research for docs/research/FREIGHT_STUDY.md (no game rule reads this). Reads
the committed files only, no network:

- RailwayGameApp/Resources/RealWorld/taiwan_places.json, `zones.layers.industrial`
  (decision 93/96: OpenStreetMap landuse=industrial and quarries, 7.5-second
  zone cells, `p` = how many of 16 sample points of a cell lie in industrial land);
- RailwayGameApp/Resources/RealRailways/tra.json (TRA station points).

For each radius it counts the industrial area (km2) within that radius of any
TRA station, how many stations have a given amount, and lists the top stations.
Usage: python3 -I tools/freight-study/measure_industry_near_stations.py [repo-root]
"""
import json
import math
import sys
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
places = json.loads((root / "RailwayGameApp/Resources/RealWorld/taiwan_places.json").read_text())
tra = json.loads((root / "RailwayGameApp/Resources/RealRailways/tra.json").read_text())

north, west, cell = places["north"], places["west"], places["cellDegrees"]
zones = places["zones"]
cuts, samples = zones["cuts"], zones["samples"]
step = cell / cuts

# Industrial zone cells: (lat, lon, area in km2 that is industrial).
cells = []
for run in zones["layers"]["industrial"]:
    for offset, points in enumerate(run["p"]):
        if points <= 0:
            continue
        lat = north - (run["r"] + 0.5) * step
        lon = west + (run["c"] + offset + 0.5) * step
        h = step * 111_320.0
        w = step * 111_320.0 * math.cos(math.radians(lat))
        cells.append((lat, lon, h * w / 1e6 * points / samples))
total = sum(c[2] for c in cells)

stations = {}
for line in tra["lines"]:
    for s in line["stations"]:
        stations.setdefault(s["name"], (s["lat"], s["lon"]))

def metres(a_lat, a_lon, b_lat, b_lon):
    dy = (a_lat - b_lat) * 111_320.0
    dx = (a_lon - b_lon) * 111_320.0 * math.cos(math.radians((a_lat + b_lat) / 2))
    return math.hypot(dx, dy)

print(f"industrial land in the file: {total:.1f} km2 in {len(cells)} zone cells; TRA stations: {len(stations)}")
for radius in (500, 1000, 2000):
    per = {}
    covered = set()
    for name, (la, lo) in stations.items():
        area = 0.0
        for i, (cl, co, a) in enumerate(cells):
            if abs(cl - la) > 0.03 or abs(co - lo) > 0.03:
                continue
            if metres(la, lo, cl, co) <= radius:
                area += a
                covered.add(i)
        per[name] = area
    union = sum(cells[i][2] for i in covered)
    enough = sum(1 for v in per.values() if v >= 0.25)
    print(f"\nwithin {radius} m of a TRA station: {union:.1f} km2 ({100 * union / total:.1f}% of all industrial land); "
          f"{enough} stations have at least 0.25 km2")
    if radius == 1000:
        for name, v in sorted(per.items(), key=lambda kv: -kv[1])[:25]:
            print(f"  {name}\t{v:.2f} km2")
