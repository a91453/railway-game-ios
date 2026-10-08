#!/usr/bin/env python3
"""Independent check of the Phase 6c-1 city building fixtures (ARCHITECTURE
decision 74): GoldenScenarios/city-buildings.json and
GoldenScenarios/city-buildings-growth.json.

Written from the rules in the decision, not from the Swift code: the
capacity table from its floor areas, the building each cell gets, the
numbering, the first town of a seed (FNV-1a draws, with decision 90's
farms, factories, schools, sights and parks) and the spread of a growing
station. It prints what each fixture observes and the final
building counts, and with --check compares them with the fixture files.

Python 3 standard library only: python3 -I tools/golden-checks/city_buildings.py --check
"""
import json
import pathlib
import sys

FLOOR_AREA, PER_RESIDENT, PER_JOB = 1536, 48, 32
FLOORS = {1: 2, 2: 6, 3: 18, 4: 40}
# Decision 90 adds factories (no homes), schools and public offices and
# sights (as offices), farms (as shops) and parks (no floor, no one).
HOME_EIGHTHS = {"residential": 7, "commercial": 2, "office": 1, "industrial": 0, "civic": 1, "leisure": 1, "agricultural": 2}
CELL = 4096


def table(use, density):
    if use == "park":
        return 0, 0
    floor = FLOOR_AREA * FLOORS[density]
    homes = HOME_EIGHTHS[use]
    assert floor * homes % (8 * PER_RESIDENT) == 0 and floor * (8 - homes) % (8 * PER_JOB) == 0
    return floor * homes // 8 // PER_RESIDENT, floor * (8 - homes) // 8 // PER_JOB


def fit(use, residents, jobs):
    """(kind, density, residentCapacity, jobCapacity) of a cell's building."""
    main_is_homes = use == "residential"
    for density in (1, 2, 3, 4):
        r, j = table(use, density)
        if (r if main_is_homes else j) >= (residents if main_is_homes else jobs):
            if main_is_homes:
                return "city", density, r, max(j, jobs)
            return "city", density, max(r, residents), j
    r, j = table(use, 4)
    return "existingStock", 4, max(r, residents), max(j, jobs)


def number(cells):
    """Buildings for cells {(row, column): (use, residents, jobs)}, numbered
    from 1 by row and then column."""
    return {pos: (index + 1,) + fit(*cells[pos]) for index, pos in enumerate(sorted(cells))}


def counts(buildings):
    summary = {"buildings": len(buildings), "d1": 0, "d2": 0, "d3": 0, "d4": 0, "existingStock": 0}
    for _, kind, density, _, _ in buildings.values():
        summary["existingStock" if kind == "existingStock" else "d%d" % density] += 1
    return summary


# The first town of a seed (decision 72, point 4).

def fnv(seed, key):
    value = 2166136261
    for byte in ("%d|%s" % (seed, key)).encode():
        value ^= byte
        value = (value * 16777619) % 2**32
    return value


def roll(seed, key, low, high):
    return low + fnv(seed, key) % (high - low + 1)


def first_town(seed, width, height):
    columns, rows = -(-width // CELL), -(-height // CELL)
    mx, my = width // 2, height // 2
    middle_row, middle_column = my // CELL, mx // CELL
    radius, peak, belt = 12, 260, 3
    cells = {}
    for dr in range(-radius - belt, radius + belt + 1):
        for dc in range(-radius - belt, radius + belt + 1):
            d2 = dr * dr + dc * dc
            row, column = middle_row + dr, middle_column + dc
            if not (0 <= row < rows and 0 <= column < columns):
                continue
            if d2 >= radius * radius:
                # Decision 90: farms, one in six, in the belt of three cells.
                if d2 < (radius + belt) ** 2 and roll(seed, "town.0.farm.%d.%d" % (dr, dc), 0, 5) == 0:
                    cells[(row, column)] = ("agricultural", 3, 8)
                continue
            share = (radius * radius - d2) * 1000 // (radius * radius)
            residents, jobs, use = peak * share // 1000, 0, "residential"
            if 9 * d2 < radius * radius:
                use = "office" if roll(seed, "town.0.cell.%d.%d" % (dr, dc), 0, 1) == 0 else "commercial"
                jobs = 3 * residents
                residents //= 4
            else:
                # Decision 90: in the inner ring (4 d^2 < r^2) a school, a
                # sight or a park, one in twenty each; in the outer ring a
                # factory, two in twenty.
                district = roll(seed, "town.0.district.%d.%d" % (dr, dc), 0, 19)
                inner = 4 * d2 < radius * radius
                if inner and district == 0:
                    use, residents, jobs = "civic", residents // 4, residents
                elif inner and district == 1:
                    use, residents, jobs = "leisure", 0, residents
                elif inner and district == 2:
                    use, residents, jobs = "park", 0, 0
                elif not inner and district in (0, 1):
                    use, residents, jobs = "industrial", 0, 2 * residents
            if residents + jobs > 0 or use == "park":
                cells[(row, column)] = (use, residents, jobs)
    return cells


def observation(buildings, row, column):
    if (row, column) not in buildings:
        return {"found": False}
    building_id, kind, density, r, j = buildings[(row, column)]
    return {"id": building_id, "kind": kind, "density": density, "residents": r, "jobs": j}


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    results = {}

    # city-buildings.json: the cells set by setLand.
    set_land = {
        (1, 2): ("residential", 56, 12), (1, 3): ("residential", 57, 0), (1, 4): ("residential", 230, 30),
        (1, 5): ("residential", 505, 0), (1, 6): ("residential", 100, 500), (1, 7): ("residential", 1121, 300),
        (2, 2): ("commercial", 16, 72), (2, 3): ("commercial", 0, 73), (2, 4): ("commercial", 65, 780),
        (2, 5): ("commercial", 10, 1441),
        (3, 2): ("office", 160, 84), (3, 3): ("office", 78, 285), (3, 4): ("office", 0, 1681),
        (3, 5): ("office", 65, 780), (3, 6): ("residential", 0, 5),
    }
    buildings = number(set_land)
    for pos, cell in sorted(set_land.items()):
        results["setLand %s" % (pos,)] = dict(observation(buildings, *pos), use=cell[0])
    results["setLand counts"] = counts(buildings)

    town = first_town(1, 131072, 98304)
    town_buildings = number(town)
    # The town of land-towns.json (437 cells, 50,189 residents and 33,276
    # jobs before decision 90).
    assert len(town) == 469 and sum(c[1] for c in town.values()) == 44457 and sum(c[2] for c in town.values()) == 42564
    for pos in [(12, 16), (12, 19), (12, 20), (12, 27), (0, 16)]:
        results["town %s" % (pos,)] = dict(observation(town_buildings, *pos), use=town.get(pos, (None,))[0])
    results["town counts"] = counts(town_buildings)

    # city-buildings-growth.json: (0, 0) homes and (0, 1) offices in a world
    # of 2 x 2 cells, three stations sharing both by nearness (decision 73),
    # each growing at 12 thousandths (all its trips arrived, 2 stations
    # reached), by ascending station: its share's growth shared over the
    # cells by their counts, then the empty cell beside people nearest it
    # (d^2, row, column), a home of 4 with a D1 building numbered next.
    R2 = 51200 ** 2
    stations = [(1536, 512), (3584, 512), (5632, 512)]
    land = {(0, 0): ["residential", 240, 0], (0, 1): ["office", 0, 240]}
    grown = number({k: tuple(v) for k, v in land.items()})

    def middle(pos):
        return pos[1] * CELL + CELL // 2, pos[0] * CELL + CELL // 2

    def d2(pos, station):
        (x, y), (sx, sy) = middle(pos), station
        return (x - sx) ** 2 + (y - sy) ** 2

    def largest_remainder(total, weights):
        total_weight = sum(weights)
        if total_weight == 0:
            return [0] * len(weights)
        shares = [total * w // total_weight for w in weights]
        order = sorted(range(len(weights)), key=lambda i: (-(total * weights[i] % total_weight), i))
        for i in order[:total - sum(shares)]:
            shares[i] += 1
        return shares

    shares = [[0, 0] for _ in stations]
    for pos in sorted(land):
        near = [(i, 1000 - d2(pos, s) * 1000 // R2) for i, s in enumerate(stations) if d2(pos, s) < R2]
        for (i, _), r, j in zip(near, largest_remainder(land[pos][1], [w for _, w in near]), largest_remainder(land[pos][2], [w for _, w in near])):
            shares[i][0] += r
            shares[i][1] += j
    results["growth shares"] = shares
    rate = 10 + 2
    spread = []
    for station, (share_r, share_j) in zip(stations, shares):
        grow = lambda amount: max(1, (amount * rate + 500) // 1000) if amount > 0 else 0
        cells = sorted(p for p in land if d2(p, station) < R2)
        for index, key in [(1, 0), (2, 1)]:
            added = largest_remainder(grow([share_r, share_j][key]), [land[p][index] for p in cells])
            for p, a in zip(cells, added):
                limit = 400 if index == 1 else 1200
                if land[p][index] < limit:
                    land[p][index] = min(limit, land[p][index] + a)
        best = None
        for row in range(2):
            for column in range(2):
                pos = (row, column)
                beside = any(q in land for q in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)])
                if pos not in land and d2(pos, station) < R2 and beside and (best is None or (d2(pos, station), row, column) < best):
                    best = (d2(pos, station), row, column)
        if best:
            land[best[1:]] = ["residential", 4, 0]
            grown[best[1:]] = (len(grown) + 1,) + fit("residential", 4, 0)
        spread.append(best and best[1:])
    results["growth spread"] = spread
    for pos in [(0, 0), (0, 1), (1, 0), (1, 1)]:
        results["growth land %s" % (pos,)] = land[pos]
        results["growth %s" % (pos,)] = observation(grown, *pos)
    results["growth land totals"] = [len(land), sum(v[1] for v in land.values()), sum(v[2] for v in land.values())]
    results["growth counts"] = counts(grown)
    growth_land, growth_buildings = land, grown

    for key, value in results.items():
        print(key, json.dumps(value))

    if "--check" in sys.argv:
        failures = 0

        def compare(what, expected, actual):
            nonlocal failures
            if expected != actual:
                failures += 1
                print("MISMATCH", what, "fixture", expected, "computed", actual)

        def building_answer(buildings, cells, row, column):
            if (row, column) not in buildings:
                return {"found": False}
            number_, kind, density, r, j = buildings[(row, column)]
            return {"found": True, "building": {"id": number_, "kind": kind, "use": cells[(row, column)][0], "density": density, "residents": r, "jobs": j}}

        # city-buildings.json: buildings observed before foundTowns are the
        # setLand ones (none before the land, none while off), after it the town's.
        fixture = json.loads((root / "GoldenScenarios" / "city-buildings.json").read_text())
        phase, on, has_land = "start", False, False
        for step in fixture["steps"]:
            command = step.get("command")
            if command:
                if command["type"] == "setCityBuildings":
                    on = command["enabled"]
                elif command["type"] == "setLand" and step["expect"]["result"] == "ok":
                    has_land = True
                elif command["type"] == "foundTowns":
                    phase = "town"
                continue
            observe = step["observe"]
            row, column = observe["row"], observe["column"]
            if phase == "town":
                expected = building_answer(town_buildings, town, row, column)
            elif on and has_land:
                expected = building_answer(buildings, set_land, row, column)
            else:
                expected = {"found": False}
            compare("city-buildings %s" % observe, step["expect"], expected)
        compare("city-buildings final buildings", fixture["expectedFinalState"]["cityBuildings"], counts(town_buildings))
        compare("city-buildings final land", fixture["expectedFinalState"]["land"],
                {"cells": len(town), "residents": sum(c[1] for c in town.values()), "jobs": sum(c[2] for c in town.values())})

        # city-buildings-growth.json: the observations after the second midnight.
        fixture = json.loads((root / "GoldenScenarios" / "city-buildings-growth.json").read_text())
        advances = 0
        initial = {(0, 0): ("residential", 240, 0), (0, 1): ("office", 0, 240)}
        for step in fixture["steps"]:
            command = step.get("command")
            if command:
                advances += command["type"] == "advance"
                continue
            observe = step["observe"]
            row, column = observe["row"], observe["column"]
            if observe["type"] == "landCell":
                cell = growth_land.get((row, column)) if advances == 2 else (initial.get((row, column)) if advances == 1 else None)
                expected = {"found": False} if cell is None else {"found": True, "landCell": {"row": row, "column": column, "use": cell[0], "residents": cell[1], "jobs": cell[2]}}
            else:
                cells = {k: tuple(v) for k, v in growth_land.items()}
                source = growth_buildings if advances == 2 else number(initial)
                expected = building_answer(source, cells, row, column)
            compare("growth %s after %d advances" % (observe, advances), step["expect"], expected)
        compare("growth final buildings", fixture["expectedFinalState"]["cityBuildings"], counts(growth_buildings))
        total = results["growth land totals"]
        compare("growth final land", fixture["expectedFinalState"]["land"], {"cells": total[0], "residents": total[1], "jobs": total[2]})
        print("checked: every building observation and final count matches" if failures == 0 else "%d mismatches" % failures)
        return 1 if failures else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
