#!/usr/bin/env python3
"""Independent check of GoldenScenarios/door-crowding.json: door crowding
(ARCHITECTURE decision 169) on boarding.json's world.

Written from the rules in the decision, not from the Swift code:

- the crowd at a train's doors, in thousandths, when they have opened is the
  larger of the riders over what the train is rated for and the passengers
  waiting over what a station holds (4,000), at most 1,100;
- an exchange takes `ceil(count * m / (rate * 1000))` seconds, `m` being
  1,000 + 1,500 * x^4 / 1,000^3 for the crowd `x`, each power rounded down to
  a thousandth (square = x * x // 1000, fourth = square * square // 1000,
  m = 1000 + 1500 * fourth // 1000), and `rate` the passengers the doors pass
  a second: 2 through each of 4 doors for each of the train's cars;
- the doors have opened 8 s after the train's arrival, which is when the
  exchange begins; they start closing at the latest of its end, the least
  dwell at a terminal (42 s) after the arrival less the 9 s they take to
  close, and the scheduled departure less those 9 s; a train waiting at a stop
  is late by how long ago its scheduled departure was (and 0 before it).

It prints what the fixture observes, and with --check compares it with the
fixture file. What it takes from the fixture is only what the fixture itself
observes before the train comes: the queue at Alpha (4,000 at 480:00) and
the arrival (28,800 s).

Python 3 standard library only: python3 -I tools/golden-checks/door_crowding.py --check
"""
import json
import pathlib
import sys

DOOR_OPENING, DOOR_CLOSING, TERMINAL_DWELL = 8, 9, 42
PER_DOOR, DOORS, CARS = 2, 4, 1
RATED_PER_CAR = 320          # the standard car (no type): 320 rated, 352 taken
STATION_CAPACITY = 4_000
LIMIT = 1_100
SCHEDULED_DEPARTURE = 28_800 + 42   # boarding.json: Alpha T to T+42 s


def crowd(riders, rated, waiting):
    return min(max(riders * 1000 // rated, waiting * 1000 // STATION_CAPACITY), LIMIT)


def multiplier(x):
    x = min(max(0, x), LIMIT)
    square = x * x // 1000
    fourth = square * square // 1000
    return 1000 + 1500 * fourth // 1000


def exchange_seconds(count, rate, x):
    scaled = count * multiplier(x)
    per = rate * 1000
    return -(-scaled // per)


def late(now):
    return max(0, now - SCHEDULED_DEPARTURE)


def main():
    path = pathlib.Path(__file__).resolve().parents[2] / "GoldenScenarios" / "door-crowding.json"
    scenario = json.loads(path.read_text(encoding="utf-8"))
    steps = scenario["steps"]
    observations = [s for s in steps if "observe" in s]

    # Alpha's queue the minute before the train comes: the ledger observed
    # after the first advance of 10 minutes (480:00, the train's arrival).
    first_ledger = next(s for s in observations if s["observe"]["type"] == "passengerLedger")
    waiting = first_ledger["expect"]["ledger"]["waiting"]
    arrival = 28_800

    rate = PER_DOOR * DOORS * CARS
    boarded = 352            # a car takes 1.1 * 320, as boarding.json observes (225 + 127)
    x = crowd(0, RATED_PER_CAR * CARS, waiting)
    seconds = exchange_seconds(boarded, rate, x)
    opened = arrival + DOOR_OPENING
    exchange_end = opened + seconds
    closing = max(exchange_end, arrival + TERMINAL_DWELL - DOOR_CLOSING, SCHEDULED_DEPARTURE - DOOR_CLOSING)

    # The two moments the fixture looks at: 481:00 and 482:00.
    first, second = 28_860, 28_920
    computed = {
        "crowd": x,
        "multiplier": multiplier(x),
        "seconds": seconds,
        "exchangeEnd": exchange_end,
        "closing": closing,
        "serviceTimes@28860": {"arrival": arrival, "exchangeEnd": exchange_end}
        if first < closing else {"arrival": arrival, "exchangeEnd": exchange_end, "closing": closing},
        "serviceTimes@28920": {"arrival": arrival, "exchangeEnd": exchange_end, "closing": closing}
        if second >= closing else {"arrival": arrival, "exchangeEnd": exchange_end},
        "lateness@28860": late(first),
        "lateness@28920": late(second),
    }
    print(json.dumps(computed, indent=2))

    if "--check" in sys.argv:
        times = [s["expect"]["times"] for s in observations if s["observe"]["type"] == "serviceTimes"]
        lateness = [s["expect"]["lateness"] for s in observations if s["observe"]["type"] == "lateness"]
        ok = (times == [computed["serviceTimes@28860"], computed["serviceTimes@28920"]]
              and lateness == [computed["lateness@28860"], computed["lateness@28920"]])
        print("OK" if ok else "MISMATCH")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
