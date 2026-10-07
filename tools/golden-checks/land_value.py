#!/usr/bin/env python3
"""Independent check of the Phase 6c-3 fixture (ARCHITECTURE decision 76):
GoldenScenarios/land-value.json.

Written from the rule in the decision, not from the Swift code:

    base  = floor(B x D / 1000)
    value = clamp(base + 15 x S + 1000 x A, 500, 50000)   cents a m2

B is the use's base (1000 empty, 2000 homes, 3000 shops, 3500 offices), D
the building's density factor (1000, 1250, 1600, 2000 for D1-D4; 1000
without a building); S and A come from the station whose catchment reaches
the cell (d2 < 51200^2) with the highest floor(w x lastService / 1000),
w = 1000 - floor(d2 x 1000 / 51200^2), ties to the lower station, among
those with lastService > 0, and only while the land sets a managed
company's ridership.

The buildings and the stations' measures are what the fixture observes
(`building` and `townGrowth`, worked out by decisions 74 and 75 and checked
by city_buildings.py and city_growth.py); before any building is observed
the buildings are those setLand puts up. Every `landValue` observation is
worked out here and compared.

Python 3 standard library only: python3 -I tools/golden-checks/land_value.py
"""
import json
import pathlib
import sys

CELL, R2 = 4096, 51200 ** 2
BASE = {"residential": 2000, "commercial": 3000, "office": 3500}
FACTOR = {1: 1000, 2: 1250, 3: 1600, 4: 2000}
TABLE = {
    "residential": [(56, 12), (168, 36), (504, 108), (1120, 240)],
    "commercial": [(16, 72), (48, 216), (144, 648), (320, 1440)],
    "office": [(8, 84), (24, 252), (72, 756), (160, 1680)],
}


def fit(use, residents, jobs):
    main = 0 if use == "residential" else 1
    for density in range(1, 5):
        if TABLE[use][density - 1][main] >= (residents, jobs)[main]:
            return density
    return 4


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    fixture = json.loads((root / "GoldenScenarios" / "land-value.json").read_text())
    width, height = fixture["initialState"]["worldWidth"], fixture["initialState"]["worldHeight"]
    rows, columns = -(-height // CELL), -(-width // CELL)
    buildings, stations, measures, managed, land_demand = {}, [], {}, False, False
    failures = 0
    for step in fixture["steps"]:
        command, observe = step.get("command"), step.get("observe")
        if command:
            kind = command["type"]
            if kind == "setEconomyMode":
                managed = command["mode"] == "management"
            elif kind == "setLandDemand":
                land_demand = command["enabled"]
            elif kind == "setLand":
                for c in command["cells"]:
                    buildings[(c["row"], c["column"])] = (c["use"], fit(c["use"], c["residents"], c["jobs"]))
            elif kind == "buildStationAt":
                stations.append((command["point"]["x"], command["point"]["y"]))
            continue
        if observe["type"] == "townGrowth":
            measures[observe["station"]] = step["expect"]["townGrowth"]
            continue
        if observe["type"] == "building":
            if step["expect"]["found"]:
                b = step["expect"]["building"]
                buildings[(observe["row"], observe["column"])] = (b["use"], b["density"])
            continue
        if observe["type"] != "landValue":
            continue
        row, column = observe["row"], observe["column"]
        if not (0 <= row < rows and 0 <= column < columns):
            expected = {"found": False}
        else:
            use, density = buildings.get((row, column), (None, None))
            base = (BASE[use] if use else 1000) * (FACTOR[density] if density else 1000) // 1000
            best = None
            if managed and land_demand:
                x, y = column * CELL + CELL // 2, row * CELL + CELL // 2
                for index, (sx, sy) in enumerate(stations):
                    m = measures.get(index + 1)
                    if not m or m["lastService"] <= 0:
                        continue
                    d2 = (x - sx) ** 2 + (y - sy) ** 2
                    if d2 >= R2:
                        continue
                    score = (1000 - d2 * 1000 // R2) * m["lastService"] // 1000
                    if best is None or score > best[1]:
                        best = (index + 1, score, m["lastReached"])
            service = 15 * (best[1] if best else 0)
            access = 1000 * (best[2] if best else 0)
            expected = {"found": True, "landValue": {
                "value": min(50000, max(500, base + service + access)), "base": base,
                "servicePremium": service, "accessPremium": access, "station": best[0] if best else None}}
        if expected != step["expect"]:
            failures += 1
            print("MISMATCH", observe, "fixture", step["expect"], "computed", expected)
        else:
            print(observe["row"], observe["column"], expected)
    print("checked: every landValue observation matches" if failures == 0 else "%d mismatches" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
