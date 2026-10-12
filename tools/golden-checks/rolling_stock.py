#!/usr/bin/env python3
"""Independent check of GoldenScenarios/rolling-stock-economics.json:
rolling-stock economics (ARCHITECTURE decision 180).

Written from the rules in the decision, not from the Swift code. Money is in
cents. With the switch on:

- a new train costs the first-car price of its type (a train without a type is
  type A: $150,000);
- a car added costs the type's car price (maglev $150,000, L $25,000);
- a change of type costs 30 % of the new type's price for the cars the train
  has (first car + (cars - 1) car prices), rounded down;
- a train sold brings 70 % of what is left of its cost on the books, the train
  record and the cars record each rounded down; nothing has depreciated on day 0.

It replays the scenario's purchases and sales, prints the balance and, with
--check, compares it with the fixture's final balance.

Python 3 standard library only: python3 -I tools/golden-checks/rolling_stock.py --check
"""
import json
import pathlib
import sys

DOLLAR = 100
PRICES = {None: (150_000, 40_000), "MAGLEV": (600_000, 150_000), "L": (90_000, 25_000)}


def price(kind, cars):
    first, each = PRICES[kind]
    return (first + each * (cars - 1)) * DOLLAR


def main():
    path = pathlib.Path(__file__).resolve().parents[2] / "GoldenScenarios" / "rolling-stock-economics.json"
    scenario = json.loads(path.read_text())
    balance = scenario["initialState"]["balance"]
    edge_cost = 1_000          # one 1,024-unit edge at 1,000 a 1,024 units
    # Blue: bought, refitted to maglev as one car, set to 4 cars.
    blue_train = price(None, 1)
    balance -= blue_train
    refit = price("MAGLEV", 1) * 30 // 100
    balance -= refit
    blue_train += refit
    blue_cars = PRICES["MAGLEV"][1] * DOLLAR * 3
    balance -= blue_cars
    # Green: bought; the track; refit to L at one car, then a second car.
    balance -= price(None, 1)
    balance -= edge_cost
    balance -= price("L", 1) * 30 // 100
    balance -= PRICES["L"][1] * DOLLAR
    # Blue sold at 70 %, the train record and the cars record each.
    balance += blue_train * 70 // 100 + blue_cars * 70 // 100
    print("balance", balance)
    if "--check" in sys.argv:
        expected = scenario["expectedFinalState"]["balance"]
        if balance != expected:
            sys.exit(f"fixture has {expected}, the rules give {balance}")
        print("matches the fixture")


if __name__ == "__main__":
    main()
