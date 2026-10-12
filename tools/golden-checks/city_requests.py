#!/usr/bin/env python3
"""Independent check of GoldenScenarios/city-requests.json: the city's
requests (ARCHITECTURE decision 183) on a three-station world.

Written from the rules in the decision, not from the Swift code:

- draws are FNV-1a, 32 bits, over the UTF-8 of "seed|key"; a roll in
  lo...hi is lo + hash % (hi - lo + 1);
- on the first of month m the six kinds (newStation, stationRiders,
  networkRiders, materials, population, tourism, in that order) are sorted
  by (hash("requests.m.order.<kind>"), their order), and of each the first
  whose conditions hold becomes an offer, up to three, numbered on;
- a station's riders: the stations a line with a train calls at with at
  least 500 planned trips a day, by ID, less those a request in hand of the
  kind already asks about, one picked by roll("requests.m.stationRiders");
  the target is ceil(trips x 1.4), the reward $40 a trip more, at least
  $200,000;
- a station's residents: the same with at least 1,000 residents within
  800 m; the target is ceil(residents x 1.2), the reward $100 a resident
  more, at least $1,000,000;
- the city trusts the company with 1 star at first and 1 + trust // 2
  requests in hand; one met at a midnight is owed, earns a star and is paid
  as the next month begins (the midnight that starts day 30), when the next
  month's offers are drawn.

The world: Home (1, 1,500 trips), Work (2, 800) and Far (3, 300) on line
Main with a train; one cell of 1,200 residents, within 800 m of every
station (the world is 192 m across). It prints what the fixture observes
and with --check compares it with the fixture file. Python 3 standard
library only: python3 -I tools/golden-checks/city_requests.py --check
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "GoldenScenarios" / "city-requests.json"
SEED = 7
KINDS = ["newStation", "stationRiders", "networkRiders", "materials", "population", "tourism"]
DAYS = {"newStation": 90, "stationRiders": 60, "networkRiders": 90, "materials": 45, "population": 120, "tourism": 90}
CAP = 1_000_000_000


def fnv(key):
    value = 2166136261
    for byte in f"{SEED}|{key}".encode():
        value ^= byte
        value = (value * 16777619) & 0xFFFFFFFF
    return value


def roll(key, lo, hi):
    return lo + fnv(key) % (hi - lo + 1)


def ceil(value, num, den):
    return (value * num + den - 1) // den


def reward(dollars, floor):
    return min(max(dollars, floor) * 100, CAP)


class World:
    def __init__(self):
        self.trips = {1: 1500, 2: 800, 3: 300}
        self.residents = 1200
        self.next_id = 1
        self.trust = 1
        self.offers = []
        self.active = []
        self.results = []
        self.owed = 0
        self.paid = 0

    def offer(self, kind, month, day):
        taken = {r["station"] for r in self.active if r["kind"] == kind}
        if kind == "stationRiders":
            free = [s for s in sorted(self.trips) if self.trips[s] >= 500 and s not in taken]
            if not free:
                return None
            station = free[roll(f"requests.{month}.{kind}", 0, len(free) - 1)]
            base = self.trips[station]
            target = ceil(base, 14, 10)
            pay = reward(40 * (target - base), 200_000)
        elif kind == "population":
            free = [s for s in sorted(self.trips) if self.residents >= 1000 and s not in taken]
            if not free:
                return None
            station = free[roll(f"requests.{month}.{kind}", 0, len(free) - 1)]
            base = self.residents
            target = ceil(base, 12, 10)
            pay = reward(100 * (target - base), 1_000_000)
        else:
            # No settlement of 3,000 without a station, no day carried, no
            # freight, no sights.
            return None
        return {"id": 0, "kind": kind, "station": station, "baseline": base, "target": target, "reward": pay,
                "days": DAYS[kind], "offeredDay": day, "progress": 0}

    def draw(self, month, day):
        order = sorted(range(len(KINDS)), key=lambda i: (fnv(f"requests.{month}.order.{KINDS[i]}"), i))
        self.offers = []
        for i in order:
            if len(self.offers) == 3:
                break
            offer = self.offer(KINDS[i], month, day)
            if offer:
                offer["id"] = self.next_id
                self.next_id += 1
                self.offers.append(offer)

    def capacity(self):
        return 1 + self.trust // 2

    def accept(self, ident, day):
        offer = next((o for o in self.offers if o["id"] == ident), None)
        if offer is None:
            return {"result": "unknownCityRequest", "request": ident}
        if len(self.active) >= self.capacity():
            return {"result": "cityRequestLimitReached", "limit": self.capacity()}
        self.offers.remove(offer)
        offer["acceptedDay"] = day
        offer["progress"] = self.measure(offer)
        self.active.append(offer)
        self.active.sort(key=lambda r: r["id"])
        return {"result": "ok"}

    def measure(self, request):
        if request["kind"] == "stationRiders":
            return self.trips[request["station"]]
        return self.residents

    def midnight(self, day):
        kept = []
        for request in self.active:
            request["progress"] = self.measure(request)
            if request["progress"] >= request["target"]:
                self.owed += request["reward"]
                self.results.append({"id": request["id"], "kind": request["kind"], "succeeded": True, "day": day})
                self.trust = min(5, self.trust + 1)
            elif day >= request["acceptedDay"] + request["days"] - 1:
                self.results.append({"id": request["id"], "kind": request["kind"], "succeeded": False, "day": day})
                self.trust = max(0, self.trust - 1)
            else:
                kept.append(request)
        self.active = kept
        if (day + 1) % 30 == 0:
            self.paid += self.owed
            self.owed = 0
            self.draw((day + 1) // 30, day + 1)

    def summary(self):
        return {"found": True, "cityRequests": {
            "trust": self.trust, "owed": self.owed, "paid": self.paid, "bestDayTrips": 0,
            "offers": [dict(o) for o in self.offers], "active": [dict(r) for r in self.active],
            "results": [dict(r) for r in self.results]}}


def run():
    """The fixture's story: what it observes, and the commands it needs."""
    world = World()
    world.draw(0, 0)
    observed = [world.summary()]
    first, second = world.offers[0], world.offers[1]
    outcomes = [world.accept(first["id"], 0), world.accept(second["id"], 0), world.accept(9, 0)]
    # Meet the first: raise its station's trips, or the land's residents.
    if first["kind"] == "stationRiders":
        world.trips[first["station"]] = first["target"]
        meet = {"type": "setStationDemand", "station": first["station"], "demand": {"kind": "residential", "dailyTrips": first["target"]}}
    else:
        world.residents = first["target"]
        meet = {"type": "setLand", "cells": [{"row": 0, "column": 0, "use": "residential", "residents": first["target"], "jobs": 0}]}
    world.midnight(0)
    observed.append(world.summary())
    outcomes.append(world.accept(second["id"], 1))
    for day in range(1, 30):
        world.midnight(day)
    observed.append(world.summary())
    return observed, outcomes, meet


def main():
    observed, outcomes, meet = run()
    print(json.dumps({"observed": observed, "outcomes": outcomes, "meet": meet}, indent=1))
    if "--check" in sys.argv:
        fixture = json.loads(FIXTURE.read_text())
        seen = [step["expect"] for step in fixture["steps"] if step.get("observe", {}).get("type") == "cityRequests"]
        accepts = [step["expect"] for step in fixture["steps"] if step.get("command", {}).get("type") == "acceptRequest"]
        # Before the requests are turned on there are none, and taking one
        # on is refused.
        assert seen == [{"found": False}] + observed, "the fixture's cityRequests observations differ"
        assert accepts == [{"result": "cityRequestsNotEnabled"}] + outcomes, "the fixture's acceptRequest outcomes differ"
        print("city-requests.json agrees.")


if __name__ == "__main__":
    main()
