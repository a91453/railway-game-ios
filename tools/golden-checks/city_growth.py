#!/usr/bin/env python3
"""Independent check of the Phase 6c-2 fixture (ARCHITECTURE decision 75):
GoldenScenarios/city-buildings-raise.json, under decision 129's station front
and nine-tenths fullness.

Written from the rules in the decision, not from the Swift code. The
fixture's land is set by hand; three stations share it. Its second midnight
grows the land: each station's service share and stations reached that
night are what the fixture observes (`townGrowth`, the GameCore values the
railway and passengers give), and everything after them is worked out here:
the rates, the shares of the land by nearness, the buildings full as the
night began (their main count at least nine tenths of their table's,
decisions 77 and 129), the raises (two a station, by row and column, a cell
once a night), growth up to each building's capacity (the station front,
the cells within 256 m, growing three times as fast: its people counted
three times in the share of the growth and twice more in the growth itself,
decision 129), and the new cells with D1 homes. It compares every land and building observation after that night.

It checks GoldenScenarios/materials-growth.json too: the same fixture with
building materials on (decisions 156 and 157). Each station holds the 60 t
it got by road at the first midnight; raising a building takes its new
storeys' floor (1,536 m2 a storey) at 200 m2 a ton, rounded up, from the
station's materials, in the order the raises are chosen, and the first it
cannot pay for stops its raising; a new cell takes 16 t. A station that
could not pay for a raise, or holds less than a new cell's 16 t after its
raises, grows at a quarter of its rate (at least 1); it builds its new cell
only if it holds 16 t. Each station then gets 60 t more at that midnight.

Python 3 standard library only: python3 -I tools/golden-checks/city_growth.py
"""
import json
import pathlib
import sys

CELL, R2 = 4096, 51200 ** 2
FRONT2, FRONT_GROWTH, FULLNESS = 16384 ** 2, 3, 900  # decision 129
TABLE = {
    "residential": [(56, 12), (168, 36), (504, 108), (1120, 240)],
    "commercial": [(16, 72), (48, 216), (144, 648), (320, 1440)],
    "office": [(8, 84), (24, 252), (72, 756), (160, 1680)],
}
STATIONS = [(1536, 512), (3584, 512), (5632, 512)]  # Alpha, Beta, Gamma
FLOORS, STOREY, PER_TON, LOCAL = [2, 6, 18, 40], 1536, 200, 60  # decisions 74, 156, 157


def tons(floors):
    return (floors * STOREY + PER_TON - 1) // PER_TON
COLUMNS, ROWS = 32768 // CELL, 8192 // CELL


def fit(use, residents, jobs):
    main = 0 if use == "residential" else 1
    count = (residents, jobs)[main]
    for density in range(1, 5):
        if TABLE[use][density - 1][main] >= count:
            return "city", density
    return "existingStock", 4


def capacity(plot):
    r, j = TABLE[plot["use"]][plot["density"] - 1]
    if plot["kind"] == "existingStock":
        return max(r, plot["residents"]), max(j, plot["jobs"])
    if plot["use"] == "residential":
        return r, max(j, plot["jobs"])
    return max(r, plot["residents"]), j


def d2(pos, station):
    x, y = pos[1] * CELL + CELL // 2, pos[0] * CELL + CELL // 2
    return (x - station[0]) ** 2 + (y - station[1]) ** 2


def largest_remainder(total, weights):
    s = sum(weights)
    if s == 0:
        return [0] * len(weights)
    shares = [total * w // s for w in weights]
    order = sorted(range(len(weights)), key=lambda i: (-(total * weights[i] % s), i))
    for i in order[:total - sum(shares)]:
        shares[i] += 1
    return shares


def night(fixture):
    """The land before and after the second midnight, cell by cell, and the
    materials each station holds after it (or None without them)."""
    steps = fixture["steps"]
    materials = any(s.get("command", {}).get("type") == "enableBuildingMaterials" for s in steps)
    stock = {i: LOCAL for i in range(1, 4)} if materials else None
    used, shorts = 0, []
    land_cells = next(s["command"]["cells"] for s in steps if s.get("command", {}).get("type") == "setLand")
    land = {}
    for index, c in enumerate(sorted(land_cells, key=lambda c: (c["row"], c["column"]))):
        kind, density = fit(c["use"], c["residents"], c["jobs"])
        land[(c["row"], c["column"])] = dict(use=c["use"], residents=c["residents"], jobs=c["jobs"], id=index + 1, kind=kind, density=density)
    before = {k: dict(v) for k, v in land.items()}

    # The service measured at the second midnight (the observations after
    # the second advance).
    advances, measures = 0, {}
    for s in steps:
        if s.get("command", {}).get("type") == "advance":
            advances += 1
        elif s.get("observe", {}).get("type") == "townGrowth" and advances == 2:
            measures[s["observe"]["station"]] = s["expect"]["townGrowth"]
    rates, raises = {}, {}
    for station, m in measures.items():
        q, k = m["lastService"], m["lastReached"]
        rates[station] = q * 10 // 1000 + k if q > 0 else -2
        raises[station] = q >= 800 and k >= 1
    print("measures", measures, "rates", rates, "raises", raises)

    # Shares of the land as the night began.
    shares = {i: [0, 0] for i in range(1, 4)}
    for pos in sorted(land):
        near = [(i + 1, 1000 - d2(pos, s) * 1000 // R2) for i, s in enumerate(STATIONS) if d2(pos, s) < R2]
        for (i, _), r, j in zip(near, largest_remainder(land[pos]["residents"], [w for _, w in near]), largest_remainder(land[pos]["jobs"], [w for _, w in near])):
            shares[i][0] += r
            shares[i][1] += j
    print("shares", shares)
    full = set()
    for pos, plot in land.items():
        if plot["kind"] == "city" and plot["density"] < 4:
            # The main count (residents of homes, jobs of the rest) against
            # the table's, nine tenths or more.
            main = 0 if plot["use"] == "residential" else 1
            table = TABLE[plot["use"]][plot["density"] - 1][main]
            if (plot["residents"], plot["jobs"])[main] * 1000 >= table * FULLNESS:
                full.add(pos)
    print("full", sorted(full))
    raised = []
    for station in sorted(rates):
        rate = rates[station]
        if rate <= 0:
            continue
        reach = [p for p in sorted(land) if d2(p, STATIONS[station - 1]) < R2]
        short = False
        if raises[station]:
            for pos in [p for p in reach if p in full and p not in raised][:2]:
                if materials:
                    cost = tons(FLOORS[land[pos]["density"]] - FLOORS[land[pos]["density"] - 1])
                    if stock[station] < cost:
                        short = True
                        break
                    stock[station] -= cost
                    used += cost
                land[pos]["density"] += 1
                raised.append(pos)
        if materials and stock[station] < tons(FLOORS[0]):
            short = True
        if short:
            shorts.append(station)
            rate = max(1, rate // 4)
        grow = lambda amount: max(1, (amount * rate + 500) // 1000) if amount > 0 else 0
        # The station front as this station's turn comes (after the lower
        # stations grew and spread).
        front = [p for p in reach if d2(p, STATIONS[station - 1]) < FRONT2]
        for key, index in (("residents", 0), ("jobs", 1)):
            amount = shares[station][index] + (FRONT_GROWTH - 1) * sum(land[p][key] for p in front)
            weights = [land[p][key] * (FRONT_GROWTH if p in front else 1) for p in reach]
            added = largest_remainder(grow(amount), weights)
            for p, a in zip(reach, added):
                limit = capacity(land[p])[index]
                if land[p][key] < limit:
                    land[p][key] = min(limit, land[p][key] + a)
        best = None
        for row in range(ROWS):
            for column in range(COLUMNS):
                pos = (row, column)
                beside = any(q in land for q in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)])
                dist = d2(pos, STATIONS[station - 1])
                if pos not in land and dist < R2 and beside and (best is None or (dist, row, column) < best):
                    best = (dist, row, column)
        if best and materials:
            if stock[station] < tons(FLOORS[0]):
                best = None
            else:
                stock[station] -= tons(FLOORS[0])
                used += tons(FLOORS[0])
        if best:
            land[best[1:]] = dict(use="residential", residents=4, jobs=0, id=max(p["id"] for p in land.values()) + 1, kind="city", density=1)
    print("raised", raised, "materials left", stock, "used", used)
    for pos in sorted(land):
        print(pos, land[pos], "capacity", capacity(land[pos]))
    after = None
    if materials:
        # The second midnight's 60 t each, after the growth.
        after = dict(materials=[{"station": i, "tons": stock[i] + LOCAL} for i in sorted(stock)],
                     used=used, supplied=2 * 3 * LOCAL, short=shorts)
    return before, land, after


def answer(source, observe):
    pos = (observe["row"], observe["column"])
    plot = source.get(pos)
    if plot is None:
        return {"found": False}
    if observe["type"] == "landCell":
        return {"found": True, "landCell": {"row": pos[0], "column": pos[1], "use": plot["use"], "residents": plot["residents"], "jobs": plot["jobs"]}}
    r, j = capacity(plot)
    return {"found": True, "building": {"id": plot["id"], "kind": plot["kind"], "use": plot["use"], "density": plot["density"], "residents": r, "jobs": j}}


def check(fixture):
    steps = fixture["steps"]
    before, land, after = night(fixture)

    failures, advances = 0, 0
    for s in steps:
        if s.get("command", {}).get("type") == "advance":
            advances += 1
            continue
        observe = s.get("observe")
        if not observe or observe["type"] not in ("landCell", "building"):
            continue
        expected = answer(land if advances == 2 else before, observe)
        if expected != s["expect"]:
            failures += 1
            print("MISMATCH", observe, "fixture", s["expect"], "computed", expected)
    final = fixture["expectedFinalState"]
    counts = {"buildings": len(land), "d1": 0, "d2": 0, "d3": 0, "d4": 0, "existingStock": 0}
    for p in land.values():
        counts["existingStock" if p["kind"] == "existingStock" else "d%d" % p["density"]] += 1
    for name, got, want in [("cityBuildings", final.get("cityBuildings"), counts),
                            ("land", final.get("land"), {"cells": len(land), "residents": sum(p["residents"] for p in land.values()), "jobs": sum(p["jobs"] for p in land.values())})]:
        if got != want:
            failures += 1
            print("MISMATCH final", name, "fixture", got, "computed", want)
    if after is not None:
        freight = final.get("freight", {})
        got = dict(materials=freight.get("materials"), used=freight.get("materialsUsed"), supplied=freight.get("materialsSupplied"),
                   short=freight.get("lastShort", []))
        if got != after:
            failures += 1
            print("MISMATCH final materials", "fixture", got, "computed", after)
    return failures


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    failures = 0
    for name in ("city-buildings-raise.json", "materials-growth.json"):
        print("==", name)
        failures += check(json.loads((root / "GoldenScenarios" / name).read_text()))
    print("checked: every land and building observation and the final counts match" if failures == 0 else "%d mismatches" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
