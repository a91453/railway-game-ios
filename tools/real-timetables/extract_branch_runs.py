#!/usr/bin/env python3
"""Extract the real trains of the TRA branch lines a player can buy
(ARCHITECTURE decision 315) from the reference's TRA timetable.

    python3 -I tools/real-timetables/extract_branch_runs.py \\
        <reference>/Railway/taiwan-rail-reference-clean/source/data/tra_schedule_dense.json \\
        RailwayGameApp/Resources/RealRailways/tra.json \\
        RailwayGameApp/Resources/RealRailways/tra_branch_runs.json

The input is the reference website's `data/tra_schedule_dense.json`: every
TRA train of 14 days (TRA's open data, ods.railway.gov.tw, under the Open
Government Data License, version 1), each with its stops' arrival and
departure seconds of the service day, the stations it passes with the
time it passes them, and which days it runs. The stations of each line
come from the app's own `tra.json` (the same website's), so the names
match the stations the map draws.

A line is bought from its junction to its end (`LINES`): the trains that
call at one of its stations past the junction are kept, from their first
call on it to their last. Trains that come from the main line or go on to
it are cut at the junction. A station a train passes without stopping is
kept as a call at the time it passes (arrival = departure), because a run
of the game calls at every station between its ends (decision 133).

A train's days are the weekdays it runs on in the timetable's first week
(no holiday), as the game counts them (0 Sunday).

The cut trains do not end each day where they began. The trains a line
needs, and where they stand at midnight (`overnight`), are what most
weekdays need at each station, sending each run the train that has stood
longest at its first stop at least three minutes before it leaves; on a
weekday that needs a train elsewhere (the Shalun Line's Saturday has no
early trains from Zhongzhou and three from Shalun), a positioning run
brings one from the station whose train is free soonest, a turnaround
before the run leaves. When no such run can, they are the most each
weekday needs at each station. After a
day's last arrival, positioning runs take the trains back to where the
next day needs them; each is timed as the real train that runs that
stretch fastest. The tool checks that every weekday starts and ends with
the same trains at the same stations, and leaves a line out (and says so)
when it cannot.

Each station's `tracks` is the most trainsets standing at it at once, a
train that passes without stopping counted for the second it passes: the
tracks with a platform the game lays there, so the trains meet where the
real ones do (one more than the main track is a passing loop).

The Liujia and Shalun Lines are double track: their real trains pass each
other between stations, and the game lays them two tracks (decision 315,
後來); their `tracks` count both.
"""
import collections
import datetime
import json
import sys

# The lines a player can buy: the app's `tra.json` id, the station the line
# starts at (its junction with the main line) and its game id. Neiwan is
# bought from Zhuzhong: Hsinchu to Zhuzhong carries the Liujia trains too,
# and the reference's DR1000 rule (`isDr1000`) counts Neiwan south of it.
LINES = [
    ("PINGXI", "三貂嶺", "pingxi"),
    ("JIJI", "二水", "jiji"),
    ("NEIWAN", "竹中", "neiwan"),
    ("SHENAO", "瑞芳", "shenao"),
    ("LIUJIA", "竹中", "liujia"),
    ("SHALUN", "中洲", "shalun"),
]
TURNAROUND = 180
DAY = 86400


def weekday(date):
    """The game's weekday of `date`: 0 Sunday to 6 Saturday."""
    return (datetime.date.fromisoformat(date).weekday() + 1) % 7


def weekdays(data):
    """Each train's weekdays, as they ran in the timetable's first week."""
    first = {}
    for date in sorted(data["dates"]):
        first.setdefault(weekday(date), date)
    days = collections.defaultdict(set)
    for day, date in first.items():
        for index in data["dates"][date]:
            days[index].add(day)
    return days


def runs(data, days, stops):
    inner = set(stops[1:])
    out = []
    for index, train in enumerate(data["trains"]):
        if index not in days or not any(s.get("stop") and s["name"] in inner for s in train["stops"]):
            continue
        on_line = [s for s in train["stops"] if s["name"] in stops]
        while on_line and not on_line[0].get("stop"):
            on_line.pop(0)
        while on_line and not on_line[-1].get("stop"):
            on_line.pop()
        positions = [stops.index(s["name"]) for s in on_line]
        step = 1 if positions[-1] > positions[0] else -1
        if len(positions) < 2 or positions != list(range(positions[0], positions[-1] + step, step)):
            return None, f"train {train['train']} does not pass every station between its ends on the line: {[s['name'] for s in on_line]}"
        out.append({
            "train": train["train"],
            "type": train["typeName"],
            "calls": [[s["name"], s["arrSec"], s["depSec"]] for s in on_line],
            "days": sorted(days[index]),
        })
    return out, None


def day_of(found, day):
    return sorted((r for r in found if day in r["days"]), key=lambda r: (r["calls"][0][2], r["train"]))


def needs(found, day):
    """The trains `day`'s runs need at each station at its start."""
    idle = collections.defaultdict(list)
    needed = collections.Counter()
    for run in day_of(found, day):
        origin, leaves = run["calls"][0][0], run["calls"][0][2]
        ready = [t for t in idle[origin] if t <= leaves]
        if ready:
            idle[origin].remove(min(ready))
        else:
            needed[origin] += 1
        idle[run["calls"][-1][0]].append(run["calls"][-1][1] + TURNAROUND)
    return needed


def play(found, day, start, stuck_idle=None):
    """Runs `day` from `start`: where its trains end, and when each is free
    there; or the run no train is there for (and, in `stuck_idle`, where
    the trains were free then)."""
    idle = collections.defaultdict(list)
    for station, count in start.items():
        idle[station] += [-DAY] * count
    for run in day_of(found, day):
        origin, leaves = run["calls"][0][0], run["calls"][0][2]
        ready = [t for t in idle[origin] if t <= leaves]
        if not ready:
            if stuck_idle is not None:
                stuck_idle.update(idle)
            return None, run
        idle[origin].remove(min(ready))
        idle[run["calls"][-1][0]].append(run["calls"][-1][1] + TURNAROUND)
    return idle, None


def rescue(found, day, start):
    """Positioning runs on `day` that bring a train from another station to
    each run no train stands ready for, each timed as the fastest real train
    to come in a turnaround before the run leaves, sent by the station whose
    train is free soonest; or the run none can reach."""
    added = []
    for _ in range(len(day_of(found, day))):
        idle = collections.defaultdict(list)
        _, stuck = play(found + added, day, start, idle)
        if stuck is None:
            return added, None
        origin, leaves = stuck["calls"][0][0], stuck["calls"][0][2]
        best = None
        for donor, times in sorted(idle.items()):
            if donor == origin or not times:
                continue
            probe = stretch(found, donor, origin, 0)
            if probe is None:
                continue
            took = probe[-1][1] - probe[0][2]
            sets_off = leaves - TURNAROUND - took
            free = min(times)
            if free <= sets_off and (best is None or free < best[0]):
                best = (free, donor, sets_off)
        if best is None:
            return None, stuck
        moved = stretch(found, best[1], origin, best[2])
        added.append({"train": "回送", "type": "回送", "calls": moved, "days": [day], "positioning": True})
    return None, stuck


def tracks(found, day, start):
    """The most trainsets standing at each station at once on `day`, run
    from `start`: each train from when it comes in (midnight for one there
    overnight) to when it leaves (midnight for one there at the day's end);
    one coming in counted before one leaving at the same second."""
    events = collections.defaultdict(list)
    idle = collections.defaultdict(list)
    for station, count in start.items():
        idle[station] += [0] * count
        events[station] += [(0, 0)] * count
    for run in day_of(found, day):
        origin, leaves = run["calls"][0][0], run["calls"][0][2]
        ready = [t for t in idle[origin] if t <= leaves]
        idle[origin].remove(min(ready))
        events[origin].append((leaves, 1))
        for name, arrival, departure in run["calls"][1:-1]:
            events[name] += [(arrival, 0), (departure, 1)]
        end, arrives = run["calls"][-1][0], run["calls"][-1][1]
        events[end].append((arrives, 0))
        idle[end].append(arrives + TURNAROUND)
    most = {}
    for station, changes in events.items():
        standing = peak = 0
        for _, leaving in sorted(changes):
            standing += -1 if leaving else 1
            peak = max(peak, standing)
        most[station] = peak
    return most


def stretch(found, origin, destination, leaves):
    """A positioning run from `origin` to `destination` leaving at `leaves`,
    timed as the fastest real train over that stretch."""
    best = None
    for run in found:
        names = [c[0] for c in run["calls"]]
        if origin in names and destination in names and names.index(origin) < names.index(destination):
            calls = run["calls"][names.index(origin):names.index(destination) + 1]
            took = calls[-1][1] - calls[0][2]
            if best is None or took < best[0]:
                best = (took, calls)
    if best is None:
        return None
    calls = best[1]
    shift = leaves - calls[0][2]
    moved = [[c[0], c[1] + shift, c[2] + shift] for c in calls]
    moved[0][1] = moved[0][2]
    moved[-1][2] = moved[-1][1]
    return moved


def line_runs(data, days, stops):
    found, problem = runs(data, days, stops)
    if problem:
        return None, problem
    # Where the trains stand at midnight: what most weekdays need, if a
    # positioning run on the others brings a train where it is short (the
    # Shalun Line's Saturday starts at Shalun, its other days at
    # Zhongzhou); or else the most each weekday needs at each station.
    patterns = collections.Counter(tuple(sorted(needs(found, day).items())) for day in range(7))
    start = collections.Counter(dict(max(patterns, key=lambda p: (patterns[p], -sum(c for _, c in p), p))))
    rescued = []
    for day in range(7):
        added, _ = rescue(found, day, start)
        if added is None:
            rescued = None
            break
        rescued += added
    if rescued is None:
        start, rescued = collections.Counter(), []
        for day in range(7):
            for station, count in needs(found, day).items():
                start[station] = max(start[station], count)
    found += rescued
    for day in range(7):
        idle, stuck = play(found, day, start)
        if stuck:
            return None, f"weekday {day}: no train for {stuck['train']}"
        surplus = []
        for station, times in idle.items():
            spare = len(times) - start[station]
            if spare > 0:
                surplus += [(free, station) for free in sorted(times)[-spare:]]
        deficit = []
        for station, count in start.items():
            deficit += [station] * max(0, count - len(idle[station]))
        surplus.sort()
        for (free, origin), destination in zip(surplus, deficit):
            last = max([r["calls"][-1][1] for r in day_of(found, day)] + [free])
            moved = stretch(found, origin, destination, max(free, last + TURNAROUND))
            if moved is None:
                return None, f"weekday {day}: no real train runs {origin} to {destination} to time a positioning run"
            if moved[-1][1] >= 2 * DAY:
                return None, f"weekday {day}: the positioning run {origin} to {destination} ends after the second midnight"
            found.append({"train": "回送", "type": "回送", "calls": moved, "days": [day], "positioning": True})
    merged = {}
    for run in found:
        if run.get("positioning"):
            key = json.dumps(run["calls"])
            if key in merged:
                merged[key]["days"] = sorted(set(merged[key]["days"]) | set(run["days"]))
                continue
            merged[key] = run
    found = [r for r in found if not r.get("positioning")] + list(merged.values())
    for day in range(7):
        idle, stuck = play(found, day, start)
        if stuck:
            return None, f"weekday {day}: no train for {stuck['train']} after positioning"
        ends = collections.Counter({s: len(t) for s, t in idle.items() if t})
        if ends != start:
            return None, f"weekday {day}: starts with {dict(start)} and ends with {dict(ends)}"
    found.sort(key=lambda r: (r["calls"][0][2], r["train"]))
    most = collections.Counter()
    for day in range(7):
        for station, count in tracks(found, day, start).items():
            most[station] = max(most[station], count)
    needed = {s: max(1, most[s]) for s in stops}
    return {"stops": stops, "overnight": dict(sorted(start.items())), "tracks": needed, "runs": found}, None


def main(source, network, out):
    data = json.load(open(source, encoding="utf-8"))
    lines = {line["id"]: [s["name"] for s in line["stations"]] for line in json.load(open(network, encoding="utf-8"))["lines"]}
    days = weekdays(data)
    result = {
        "source": "TRA open data (ods.railway.gov.tw), via the reference website's data/tra_schedule_dense.json, "
                  f"{data['dateRange'][0]} to {data['dateRange'][1]}",
        "licence": "Open Government Data License, version 1",
        "lines": [],
    }
    for network_id, junction, game_id in LINES:
        stops = lines[network_id][lines[network_id].index(junction):]
        line, problem = line_runs(data, days, stops)
        if problem:
            print(f"{game_id}: left out: {problem}")
            continue
        real = sum(1 for r in line["runs"] if not r.get("positioning"))
        print(f"{game_id}: {stops[0]}–{stops[-1]}, {real} real trains, {len(line['runs']) - real} positioning runs, "
              f"{sum(line['overnight'].values())} trainsets, overnight {line['overnight']}, "
              f"tracks {{{', '.join(f'{k} {v}' for k, v in line['tracks'].items() if v > 1)}}}")
        result["lines"].append({"id": game_id, "network": network_id, **line})
    # One run a line.
    parts = []
    for line in result["lines"]:
        head = json.dumps({k: v for k, v in line.items() if k != "runs"}, ensure_ascii=False, separators=(",", ":"))
        body = ",\n".join(json.dumps(run, ensure_ascii=False, separators=(",", ":")) for run in line["runs"])
        parts.append(head[:-1] + ',"runs":[\n' + body + "\n]}")
    head = json.dumps({k: v for k, v in result.items() if k != "lines"}, ensure_ascii=False, separators=(",", ":"))
    text = head[:-1] + ',"lines":[\n' + ",\n".join(parts) + "\n]}\n"
    json.loads(text)
    open(out, "w", encoding="utf-8").write(text)
    print(f"{out}: {len(text.encode())} bytes")


if __name__ == "__main__":
    main(*sys.argv[1:])
