#!/usr/bin/env python3
"""Independent check of GoldenScenarios/high-speed.json: a high-speed line
(ARCHITECTURE decision 168): the high-speed fare of a trip and the intercity
trips between two high-speed stations.

Written from the rules in the decision, not from the Swift code:

- the fare is `max(20, round(km * .45))` dollars (`Math.round` takes .5 up),
  the straight-line distance between the stations' points, in cents;
- two stations with `a` and `b` people in their hinterlands have, one way,
  `K * a * b` trips a day (K = 2,400 for a million and a million), the
  products in millions and rounded down a step at a time, kept by a share of
  their distance (none up to 10 km, all from 80 km, in a straight line
  between), rounded half up; the route of the line takes less than half an
  hour, so the minutes take nothing off;
- the hours come from the day's shape and the stations' peaks (built here
  from their formulas, normalised so a day's mean is 1), shared by the
  largest remainder, ties to the earlier hour.

It prints what the fixture observes, and with --check compares it with the
fixture file.

Python 3 standard library only: python3 -I tools/golden-checks/high_speed.py --check
"""
import json
import math
import pathlib
import sys

UNITS_PER_METRE = 64
K = 2400
NEAR, FULL = 10_000, 80_000  # metres
DAY_SHAPE = [100, 100, 100, 100, 100, 100, 720, 1500, 1800, 1500, 800, 820,
             840, 860, 880, 900, 1500, 1500, 1800, 1500, 1000, 1020, 1040, 100]
# Along one road, in world units: A, N and B (numbered 1, 3 and 2).
X = {1: 100_000, 3: 420_000, 2: 4_004_000}
HINTERLAND = {1: 2_000_000, 3: 500_000, 2: 1_000_000}
KIND = {1: "residential", 3: "shopping", 2: "office"}


def normalised(curve):
    mean = sum(curve) / 24
    return [round(1000 * value / mean) for value in curve]


def gauss(hour, mu, sigma):
    return math.exp(-0.5 * ((hour - mu) / sigma) ** 2)


def peak(mu):
    return normalised([1 + 0.6 * gauss(h, mu, 1.15) for h in range(24)])


MORNING, EVENING = peak(8), peak(18)
SHOP_OUT = normalised([1 + 0.42 * gauss(h, 14, 2.4) + 0.5 * gauss(h, 19, 1.8) for h in range(24)])
SHOP_IN = normalised([1 + 0.42 * gauss(h, 13, 2.4) + 0.5 * gauss(h, 18, 1.8) for h in range(24)])
DEPARTURES = {"residential": MORNING, "office": EVENING, "shopping": SHOP_OUT}
ARRIVALS = {"residential": EVENING, "office": MORNING, "shopping": SHOP_IN}


def isqrt(n):
    return math.isqrt(n)


def distance_units(a, b):
    return abs(X[a] - X[b])


def fare_cents(units):
    # km * 45 / 100 dollars, units / 64,000 km, rounded half up.
    dollars = (units * 45 + 3_200_000) // 6_400_000
    return max(20, dollars) * 100


def share(units):
    metres = units // UNITS_PER_METRE  # not used: the ramp is in units
    near, full = NEAR * UNITS_PER_METRE, FULL * UNITS_PER_METRE
    if units <= near:
        return 0
    if units >= full:
        return 1000
    return 1000 * (units - near) // (full - near)


def daily(origin, destination):
    units = distance_units(origin, destination)
    pair = HINTERLAND[origin] * HINTERLAND[destination] // 1_000_000 * K // 1_000_000
    return (pair * share(units) + 500) // 1000


def apportion(total, weights):
    whole = sum(weights)
    shares = [total * w // whole for w in weights]
    remainders = [total * w % whole for w in weights]
    left = total - sum(shares)
    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    for i in order[:left]:
        shares[i] += 1
    return shares


def hourly(total, origin, destination):
    out, arr = DEPARTURES[KIND[origin]], ARRIVALS[KIND[destination]]
    return apportion(total, [DAY_SHAPE[h] * out[h] * arr[h] for h in range(24)])


def observed():
    """What the fixture's observations should answer, by (type, from, to)."""
    answers = {}
    for origin, destination in [(1, 2), (2, 1), (3, 2), (2, 3), (1, 3)]:
        trips = daily(origin, destination)
        answers[("demand", origin, destination)] = {"daily": trips, "hourly": hourly(trips, origin, destination)}
    for origin, destination, high_speed in [(1, 2, False), (1, 2, True), (1, 3, True), (3, 2, True)]:
        units = distance_units(origin, destination)
        answers[("tripFare", origin, destination, high_speed)] = {"found": True, "fare": fare_cents(units) if high_speed else 500}
    return answers


def fixture_answers(path):
    scenario = json.loads(path.read_text())
    answers = {}
    for step in scenario["steps"]:
        if "observe" not in step:
            continue
        obs, expect = step["observe"], step["expect"]
        if obs["type"] == "demand":
            answers[("demand", obs["from"], obs["to"])] = expect
        elif obs["type"] == "tripFare":
            answers[("tripFare", obs["from"], obs["to"], obs.get("highSpeed", False))] = expect
    return answers


def main():
    expected = observed()
    for key, value in expected.items():
        print(key, json.dumps(value))
    if "--check" not in sys.argv:
        return 0
    path = pathlib.Path(__file__).resolve().parents[2] / "GoldenScenarios" / "high-speed.json"
    actual = fixture_answers(path)
    bad = 0
    for key, value in expected.items():
        if actual.get(key) != value:
            print("MISMATCH", key, "fixture:", json.dumps(actual.get(key)), "rules:", json.dumps(value))
            bad += 1
    extra = set(actual) - set(expected)
    for key in sorted(extra, key=str):
        print("NOT CHECKED", key)
    print("OK" if bad == 0 else f"{bad} differences")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
