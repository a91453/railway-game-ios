#!/usr/bin/env python3
"""Independent check of GoldenScenarios/tourism.json: tourists (ARCHITECTURE
decision 174) on a two-station world.

Written from the rules in the decision, not from the Swift code:

- an attraction of `s` hundredths of a star draws potential tourists a day by
  line between 100 -> 300, 200 -> 800, 300 -> 2,000, 400 -> 4,500, 500 -> 9,000
  (integer division inside a segment);
- a shop adds 25 hundredths a level, five stars at most;
- the day's factor (thousandths) is 600 on a weekday, 1,600 on a Saturday,
  1,300 on a Sunday and 2,000 on a holiday; day 0 is a Monday and, with
  Taiwan's holidays on, New Year's Day; a town has no season (1,000); clear
  weather is 1,000;
- a fifth are captured: tourists = potential * day * season * weather * 200
  / 10^12, rounded half up;
- they set out from Home, the only source (an outside connection: the world
  is smaller than the margin), by the scenic arrival curve times the day's
  shape, apportioned by largest remainder; they come back from Foot by the
  scenic departure curve;
- a station must lie within 51,200 units (800 m) of the attraction.

It prints what the fixture observes and with --check compares it with the
fixture file. Python 3 standard library only:
python3 -I tools/golden-checks/tourism.py --check
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "GoldenScenarios" / "tourism.json"
SOURCE = (ROOT / "Sources/GameCore/Passenger/StationDemand.swift").read_text()

POTENTIAL = [300, 800, 2000, 4500, 9000]
REACH = 51_200


def array(name):
    body = re.search(r"static let %s: \[Int64\] = \[(.*?)\]" % name, SOURCE, re.S).group(1)
    return [int(x) for x in re.findall(r"\d+", body)]


DAY, ARRIVALS, DEPARTURES = array("dayShape"), array("scenicArrivals"), array("scenicDepartures")


def potential(stars):
    stars = max(100, min(500, stars))
    low = stars // 100 - 1
    if low >= 4:
        return POTENTIAL[4]
    return POTENTIAL[low] + (POTENTIAL[low + 1] - POTENTIAL[low]) * (stars - 100 * (low + 1)) // 100


def tourists(stars, day):
    scale = 10**12
    return (potential(stars) * day * 1000 * 1000 * 200 + scale // 2) // scale


def apportion(total, weights):
    whole = sum(weights)
    shares = [total * w // whole for w in weights]
    remainders = [total * w % whole for w in weights]
    for i in sorted(range(len(weights)), key=lambda i: (-remainders[i], i))[: total - sum(shares)]:
        shares[i] += 1
    return shares


def out_hours(total):
    return apportion(total, [DAY[h] * ARRIVALS[h] for h in range(24)])


def back_hours(total):
    return apportion(total, [DAY[h] * DEPARTURES[h] for h in range(24)])


def run():
    """Replays the fixture's commands on the rules and gives each
    observation's expected answer, by step index."""
    scenario = json.loads(FIXTURE.read_text())
    sight = None            # (x, stars_base, level)
    on = False
    holiday = False
    level = 0
    answers = {}
    foot_x = 5632
    for index, step in enumerate(scenario["steps"]):
        if "command" in step:
            c = step["command"]
            if c["type"] == "setTourism":
                on = bool(c["attractions"])
                if on:
                    a = c["attractions"][0]
                    sight = (a["x"], a["stars"])
                    level = 0
            elif c["type"] == "investInSouvenirShop" and step["expect"]["result"] == "ok":
                level += 1
            elif c["type"] == "setDisruptions":
                holiday = c["level"] is not None
        else:
            o = step["observe"]
            if o["type"] != "demand":
                continue
            total = 0
            if on and abs(sight[0] - foot_x) <= REACH:
                total = tourists(sight[1] + 25 * level, 2000 if holiday else 600)
            if (o["from"], o["to"]) == (1, 2):
                hours = out_hours(total) if total else [0] * 24
            elif (o["from"], o["to"]) == (2, 1):
                hours = back_hours(total) if total else [0] * 24
            else:
                continue
            answers[index] = (total, hours)
    return scenario, answers


def main():
    scenario, answers = run()
    bad = 0
    for index, (total, hours) in sorted(answers.items()):
        expect = scenario["steps"][index]["expect"]
        ok = expect["daily"] == total and expect["hourly"] == hours
        print(f"steps[{index}] daily {total} {'ok' if ok else 'DIFFERS: fixture says ' + str(expect['daily'])}")
        bad += not ok
    if "--check" in sys.argv and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
