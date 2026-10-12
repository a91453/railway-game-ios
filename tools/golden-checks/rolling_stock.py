#!/usr/bin/env python3
"""Independent check of GoldenScenarios/rolling-stock-economics.json:
rolling-stock economics (ARCHITECTURE decision 180).

Written from the rules in the decision, not from the Swift code. Money is in
cents. With the switch on:

- a new train costs the first-car price of its type (a train without a type is
  type A: $150,000);
- a car added costs the type's car price (maglev $150,000, L $25,000);
- a change of type costs the new type's price for the cars the train has, less what
  selling the old train would bring (70 % of what is left on its books, the train
  record and the cars record each rounded down), at least nothing; it is booked as
  selling the old train and buying the new one at its price, so a downgrade pays
  nothing and pays nothing back;
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
    # Blue: bought; changed to maglev at one car (new price less 70 % of the
    # $150,000 train); set to 4 cars (3 maglev cars).
    blue_train_book = price(None, 1)
    balance -= blue_train_book
    fee = max(0, price("MAGLEV", 1) - blue_train_book * 70 // 100)
    balance -= fee
    blue_train_book = price("MAGLEV", 1)      # the new train is booked at its price
    blue_cars_book = PRICES["MAGLEV"][1] * DOLLAR * 3
    balance -= blue_cars_book
    # Green: bought; the track; changed to L at one car (worth more than the
    # L train costs: nothing paid, nothing paid back), then a second car.
    green = price(None, 1)
    balance -= green
    balance -= edge_cost
    balance -= max(0, price("L", 1) - green * 70 // 100)
    balance -= PRICES["L"][1] * DOLLAR
    # Blue sold at 70 %, the train record and the cars record each.
    balance += blue_train_book * 70 // 100 + blue_cars_book * 70 // 100
    print("balance", balance)
    if "--check" in sys.argv:
        expected = scenario["expectedFinalState"]["balance"]
        if balance != expected:
            sys.exit(f"fixture has {expected}, the rules give {balance}")
        print("matches the fixture")


if __name__ == "__main__":
    main()
