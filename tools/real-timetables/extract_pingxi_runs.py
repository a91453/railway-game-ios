#!/usr/bin/env python3
"""Extract the Pingxi Line's real trains for the real-world demo
(ARCHITECTURE decision 133) from the `Railway/` site's TRA timetable.

    python3 -I tools/real-timetables/extract_pingxi_runs.py \\
        <reference>/Railway/site_archive_clean/data/tra_schedule_dense.json \\
        RailwayGameApp/Resources/RealRailways/tra_pingxi_runs.json

The input is the site's `data/tra_schedule_dense.json`: every TRA train of
14 days (TRA's open data, ods.railway.gov.tw, under the Open Government
Data License, version 1), each with its stops' arrival and departure
seconds of the service day, and which days it runs.

The demo runs one line, Badouzi to Jingtong through Ruifang and
Sandiaoling (the demo's 平溪線). Every train that calls at a Pingxi Line
station is kept, from its first call on that line to its last: the
Badouzi trains whole; the Badu trains from Ruifang (Badu to Ruifang is the
Yilan Line's, which the demo runs at a headway). A train's days are the
weekdays it runs on in the timetable's first week (2026-10-02 to
2026-10-08, no holiday), as the game counts them (0 Sunday).

The real trains do not end each day where they began: trainsets come and
go by the main line, which the demo does not run. One positioning run is
added each day, Shifen to Ruifang at 04:15, timed as train 4735 runs that
stretch, so the day's last train (4744, which ends at Shifen) is at
Ruifang for the first (4704, 05:07). The trains a day needs, and where
they stand at midnight, are worked out by sending each run the first train
standing at its first stop at least three minutes before it leaves.
"""
import collections
import datetime
import json
import sys

STOPS = ["八斗子", "海科館", "瑞芳", "猴硐", "三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐"]
PINGXI = {"大華", "十分", "望古", "嶺腳", "平溪", "菁桐"}
TURNAROUND = 180
POSITIONING_DEPARTURE = 4 * 3600 + 15 * 60


def weekday(date):
    """The game's weekday of `date`: 0 Sunday to 6 Saturday."""
    return (datetime.date.fromisoformat(date).weekday() + 1) % 7


def runs(data):
    # Each weekday as it ran in the timetable's first week: later dates
    # can be holidays with another timetable (2026-10-09, a Friday, ran the
    # weekend's trains, the day off for National Day).
    first = {}
    for date in sorted(data["dates"]):
        first.setdefault(weekday(date), date)
    days = collections.defaultdict(set)
    for day, date in first.items():
        for index in data["dates"][date]:
            days[index].add(day)
    out = []
    for index, train in enumerate(data["trains"]):
        calls = [s for s in train["stops"] if s.get("stop")]
        if index not in days or not any(s["name"] in PINGXI for s in calls):
            continue
        on_line = [s for s in calls if s["name"] in STOPS]
        positions = [STOPS.index(s["name"]) for s in on_line]
        step = 1 if positions[-1] > positions[0] else -1
        if positions != list(range(positions[0], positions[-1] + step, step)):
            sys.exit(f"train {train['train']} does not call at every station between its ends on the line: {[s['name'] for s in on_line]}")
        out.append({
            "train": train["train"],
            "type": train["typeName"],
            "calls": [[s["name"], s["arrSec"], s["depSec"]] for s in on_line],
            "days": sorted(days[index]),
        })
    return out


def positioning(found):
    """Shifen to Ruifang at 04:15, every day, timed as 4735 runs it."""
    model = next(r for r in found if r["train"] == "4735")
    calls = model["calls"]
    start = [c[0] for c in calls].index("十分")
    end = [c[0] for c in calls].index("瑞芳")
    shift = POSITIONING_DEPARTURE - calls[start][2]
    stretch = [[c[0], c[1] + shift, c[2] + shift] for c in calls[start:end + 1]]
    stretch[0][1] = stretch[0][2]
    stretch[-1][2] = stretch[-1][1]
    return {"train": "回送", "type": "回送", "calls": stretch, "days": list(range(7)), "positioning": True}


def overnight(found, day):
    """Where each train stands at midnight before `day`'s runs, and how many."""
    todays = sorted((r for r in found if day in r["days"]), key=lambda r: r["calls"][0][2])
    idle = collections.defaultdict(list)
    needed = collections.Counter()
    for run in todays:
        origin, leaves = run["calls"][0][0], run["calls"][0][2]
        ready = [t for t in idle[origin] if t <= leaves]
        if ready:
            idle[origin].remove(min(ready))
        else:
            needed[origin] += 1
        idle[run["calls"][-1][0]].append(run["calls"][-1][1] + TURNAROUND)
    ends = collections.Counter({station: len(times) for station, times in idle.items() if times})
    return dict(needed), dict(ends)


def main(source, out):
    data = json.load(open(source, encoding="utf-8"))
    found = runs(data)
    found.append(positioning(found))
    found.sort(key=lambda r: (r["calls"][0][2], r["train"]))
    starts = {}
    for day in range(7):
        needed, ends = overnight(found, day)
        if needed != ends:
            sys.exit(f"weekday {day}: the day starts with {needed} and ends with {ends}")
        starts[day] = needed
    if len({json.dumps(s, sort_keys=True) for s in starts.values()}) != 1:
        sys.exit(f"the days start differently: {starts}")
    result = {
        "source": "TRA open data (ods.railway.gov.tw), via the Railway/ site's data/tra_schedule_dense.json, "
                  f"{data['dateRange'][0]} to {data['dateRange'][1]}",
        "licence": "Open Government Data License, version 1",
        "stops": STOPS,
        "overnight": starts[0],
        "runs": found,
    }
    # One run a line.
    lines = [json.dumps(run, ensure_ascii=False, separators=(",", ":")) for run in found]
    head = json.dumps({k: v for k, v in result.items() if k != "runs"}, ensure_ascii=False, separators=(",", ":"))
    text = head[:-1] + ',"runs":[\n' + ",\n".join(lines) + "\n]}\n"
    json.loads(text)
    open(out, "w", encoding="utf-8").write(text)
    real = sum(1 for r in found if not r.get("positioning"))
    print(f"{out}: {real} real trains and {len(found) - real} positioning run; {sum(starts[0].values())} trainsets, "
          f"overnight {starts[0]}; {len(text.encode())} bytes")


if __name__ == "__main__":
    main(*sys.argv[1:])
