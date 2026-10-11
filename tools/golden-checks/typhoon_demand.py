#!/usr/bin/env python3
"""Independent check of GoldenScenarios/typhoon-demand.json: the trips of a
typhoon day (ARCHITECTURE decision 162, and its later fix: a typhoon cuts
the trips to and from the stations it blows over and sends none elsewhere).

Written from the rules in the decision, not from the Swift code: the
FNV-1a draws over "seed|key", the day's weather from each month's chances,
the year's typhoons, an origin's trips shared among its destinations by
their daily trips (largest remainder, ties to the lower ID), each pair then
keeping the smaller of its two ends' typhoon multipliers, and the hours
from the day's shape and the stations' peaks (built here from their
formulas, normalised so a day's mean is 1). It prints what the fixture
observes, and with --check compares it with the fixture file.

Python 3 standard library only: python3 -I tools/golden-checks/typhoon_demand.py --check
"""
import json
import math
import pathlib
import sys

WIDTH, HEIGHT = 12288, 3072
DAY = 194
SEED = 7
STATIONS = {  # id: (name, x, y, kind, daily trips), on one line in this order
    1: ("Home", 1536, 1536, "residential", 1000),
    2: ("Office", 5632, 1536, "office", 1000),
    3: ("Port", 9728, 1536, "office", 1000),
    4: ("Town", 11776, 1536, "residential", 1000),
}
PAIRS = [(1, 2), (1, 3), (4, 1), (4, 3)]
# Each month's chances of rain and of a thunderstorm, in thousandths.
MONTHLY_RAIN = [(250, 0), (300, 0), (300, 20), (300, 50), (450, 80), (450, 120),
                (200, 250), (200, 250), (200, 150), (200, 30), (200, 0), (200, 0)]
TYPHOON_COUNTRIES = {"TW", "CN", "HK", "JP", "KR", "VN"}
DAY_SHAPE = [100, 100, 100, 100, 100, 100, 720, 1500, 1800, 1500, 800, 820,
             840, 860, 880, 900, 1500, 1500, 1800, 1500, 1000, 1020, 1040, 100]


def peak(hour):
    """`1 + 0.6·g(h; hour, 1.15)`, in thousandths of the day's mean."""
    curve = [1 + 0.6 * math.exp(-0.5 * ((h - hour) / 1.15) ** 2) for h in range(24)]
    mean = sum(curve) / 24
    return [round(1000 * value / mean) for value in curve]


MORNING, EVENING = peak(8), peak(18)
DEPARTURES = {"residential": MORNING, "office": EVENING}
ARRIVALS = {"residential": EVENING, "office": MORNING}


def fnv1a(seed, key):
    value = 2166136261
    for byte in f"{seed}|{key}".encode():
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def roll(seed, key, low, high):
    return low + fnv1a(seed, key) % (high - low + 1)


def halved(drop, level):
    return drop if level == "standard" else drop // 2


def weather_drop(seed, day, level):
    if seed is None or day < 30:
        return 0
    rain, storm = MONTHLY_RAIN[day % 360 // 30]
    draw = roll(seed, f"weather.{day}", 0, 999)
    drop = 200 if draw < storm else 100 if draw < storm + rain else 0
    return halved(drop, level)


def typhoons(seed, year, country, level):
    if seed is None or country not in TYPHOON_COUNTRIES:
        return []
    found = []
    for slot in range(3):
        key = f"typhoon.{year}.{slot}"
        if roll(seed, f"{key}.comes", 0, 999) >= (500 if level == "standard" else 250):
            continue
        start = year * 360 + roll(seed, f"{key}.start", 180, 299)
        if start < 30:
            continue
        found.append({
            "announced": start - roll(seed, f"{key}.notice", 1, 3),
            "start": start,
            "end": start + roll(seed, f"{key}.days", 1, 2),
            "x": roll(seed, f"{key}.x", 0, WIDTH),
            "y": roll(seed, f"{key}.y", 0, HEIGHT),
            "radius": max(WIDTH, HEIGHT) * roll(seed, f"{key}.radius", 300, 600) // 1000,
            "drop": halved(800, level),
        })
    return sorted(found, key=lambda typhoon: typhoon["start"])


def apportion(total, weights):
    whole = sum(weights)
    shares = [total * weight // whole for weight in weights]
    order = sorted(range(len(weights)), key=lambda i: (-(total * weights[i] % whole), i))
    for i in order[:total - sum(shares)]:
        shares[i] += 1
    return shares


def left_of(station, blowing):
    _, x, y, _, _ = STATIONS[station]
    drops = [t["drop"] for t in blowing if (x - t["x"]) ** 2 + (y - t["y"]) ** 2 <= t["radius"] ** 2]
    return 1000 - max(drops, default=0)


def demand(origin, destination, country, level, seed):
    """The pair's daily trips and their hours on DAY (no holiday in July)."""
    blowing = [t for t in typhoons(seed, DAY // 360, country, level) if t["start"] <= DAY < t["end"]]
    network = 1000 - weather_drop(seed, DAY, level)
    trips = (STATIONS[origin][4] * 1000 * network + 500_000) // 1_000_000
    others = [s for s in sorted(STATIONS) if s != origin]
    shares = dict(zip(others, apportion(trips, [STATIONS[s][4] for s in others])))
    left = min(left_of(origin, blowing), left_of(destination, blowing))
    daily = (shares[destination] * left + 500) // 1000
    departures, arrivals = DEPARTURES[STATIONS[origin][3]], ARRIVALS[STATIONS[destination][3]]
    hourly = apportion(daily, [DAY_SHAPE[h] * departures[h] * arrivals[h] for h in range(24)]) if daily else [0] * 24
    return {"daily": daily, "hourly": hourly}


def observations():
    """What the fixture observes, in its order."""
    out = []
    for country, level, seed in [("TW", "standard", None), ("TW", "standard", SEED), ("GB", "standard", SEED), ("TW", "light", SEED)]:
        if seed is not None:
            draw = roll(seed, f"weather.{DAY}", 0, 999)
            rain, storm = MONTHLY_RAIN[DAY % 360 // 30]
            out.append({"weather": "thunderstorm" if draw < storm else "rain" if draw < storm + rain else "clear"})
            out.append({"typhoons": [t for t in typhoons(seed, DAY // 360, country, level) if t["announced"] <= DAY < t["end"]]})
        out += [demand(o, d, country, level, seed) for o, d in PAIRS]
    return out


def main():
    found = observations()
    for value in found:
        print(json.dumps(value))
    if "--check" in sys.argv:
        path = pathlib.Path(__file__).resolve().parents[2] / "GoldenScenarios" / "typhoon-demand.json"
        fixture = json.loads(path.read_text())
        expected = [step["expect"] for step in fixture["steps"] if "observe" in step]
        if expected != found:
            sys.exit("typhoon-demand.json differs from the rules")
        print("typhoon-demand.json agrees with the rules")


if __name__ == "__main__":
    main()
