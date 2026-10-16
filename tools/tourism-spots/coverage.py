#!/usr/bin/env python3
"""How many sights a 16 km real-world map has (ARCHITECTURE decision 250).

Lays 16.384 km squares (a new game's map) over Taiwan at every 2 km, adds
up the people in each from the app's population grid (WorldPop, CC BY 4.0)
and counts the catalog's sights inside. Prints, for the squares with at
least so many people, how many have 0, 1, 2 to 5 and more than 5 sights.

    python3 -I tools/tourism-spots/coverage.py \
        tools/tourism-spots/taiwan_attractions.json \
        RailwayGameApp/Resources/RealWorld/taiwan_population.json
"""
import json
import math
import sys

SIDE_KM = 16.384
STEP_KM = 2.0


def main():
    spots = json.load(open(sys.argv[1], encoding="utf-8"))["attractions"]
    grid = json.load(open(sys.argv[2], encoding="utf-8"))
    north, west, cell = grid["north"], grid["west"], grid["cellDegrees"]
    people = []
    for run in grid["runs"]:
        for offset, count in enumerate(run["p"]):
            people.append((north - (run["r"] + 0.5) * cell, west + (run["c"] + offset + 0.5) * cell, count))
    # Kilometres east and north of a point in the south west, flat (the
    # island is small enough).
    lat0, lon0 = 21.8, 119.9

    def xy(lat, lon):
        return ((lon - lon0) * 111.320 * math.cos(math.radians(23.7)), (lat - lat0) * 110.574)

    def bucket(items):
        table = {}
        for lat, lon, value in items:
            x, y = xy(lat, lon)
            table.setdefault((int(x // STEP_KM), int(y // STEP_KM)), []).append((x, y, value))
        return table

    population = bucket(people)
    sights = bucket([(s["lat"], s["lon"], 1) for s in spots])
    steps = int(SIDE_KM // STEP_KM)
    results = []
    for i in range(0, int(400 / STEP_KM)):
        for j in range(0, int(420 / STEP_KM)):
            x0, y0 = i * STEP_KM, j * STEP_KM

            def total(table):
                count = 0
                for di in range(-1, steps + 2):
                    for dj in range(-1, steps + 2):
                        for x, y, value in table.get((i + di, j + dj), ()):
                            if x0 <= x < x0 + SIDE_KM and y0 <= y < y0 + SIDE_KM:
                                count += value
                return count

            residents = total(population)
            if residents >= 20_000:
                results.append((residents, total(sights)))
    for floor in (20_000, 100_000, 500_000):
        counts = [n for residents, n in results if residents >= floor]
        none = sum(1 for n in counts if n == 0)
        one = sum(1 for n in counts if n == 1)
        some = sum(1 for n in counts if 2 <= n <= 5)
        many = sum(1 for n in counts if n > 5)
        print(f"{floor:>7} people or more: {len(counts)} maps; 0: {none}, 1: {one}, 2-5: {some}, over 5: {many}; "
              f"median {sorted(counts)[len(counts) // 2]}")


if __name__ == "__main__":
    main()
