#!/usr/bin/env python3
"""Turn the light rails' real timetables the app bundles into the runs of
the lines a player can buy (decision 400, 10j-2), as
`extract_branch_runs.py` does for the TRA branch lines.

    python3 -I tools/real-timetables/extract_metro_runs.py \\
        RailwayGameApp/Resources/RealRailways \\
        RailwayGameApp/Resources/RealRailways/metro_runs.json

The input is the app's own `<system>.json` (each line's stations in order)
and `<system>_times.json` (each line's timetable sets, from the Ministry of
Transportation and Communications' TDX, fetched by the reference website on
2026-07-16): one second of the day for each station a trip calls at, to the
minute, the time it leaves; the last call's is when it arrives. The game's
run arrives 25 s before it leaves (`DWELL`), the dwell the site lists for
the Kaohsiung light rail's stations, the only light rail it lists one for.

A trip's days are the weekdays whose set (`days`, Sunday first) holds it;
the sets for public holidays and for particular dates (Danhai's fireworks
days) are not used, as the branch lines use their timetable's first week.
The same trip in two sets is one run of both sets' days. A trip that skips
a station of the line between its ends (four of Danhai's holiday trips)
passes it at the time between its neighbours', as a branch line's train
passes a station it does not stop at.

From there each line is checked and laid out as a branch line is
(`extract_branch_runs.line_runs`): where the trains stand at midnight
(`overnight`), positioning runs where a day ends with them elsewhere, and
each station's `tracks`. A line that does not pass is left out, and says
why.

`LINES` lists the lines. A line that shares its first stations with
another (Danhai's Blue Coast Line runs Hongshulin to Binhai Shalun on the
Green Mountain Line's track) is listed twice more, from the station where
they part (`after`): what it lays when the other is already bought, its
trips cut there as a branch line's are at its junction.

Danhai's Green Mountain Line does not pass: its ends stand more trains
overnight than the game lays tracks (Kanding's depot stables nine), and
so neither does the Blue Coast Line after it. Not listed: the Ankeng LRT
(see `LINES`) and the Kaohsiung Circular Light Rail. Its trains run one way round
the loop and come back to Lizihnei; a line of the game runs end to end and
turns back.
"""
import collections
import importlib.util
import json
import os
import sys

DWELL = 25
# The tracks the game lays at an end station of a light rail bought: the
# line's own and two loops either side, one beyond the other
# (`RealLineLayout.lightRail`).
END_TRACKS = 5

# (system, line id in `<system>.json`, the station it is bought from when
# the line named by `after` is already the company's, `after`).
LINES = [
    ("ntdlrt", "V", None, None),
    ("ntdlrt", "VB", None, None),
    ("ntdlrt", "V", "濱海沙崙", "VB"),
    ("ntdlrt", "VB", "濱海沙崙", "V"),
    # Not yet the Ankeng LRT (ntalrt:K): its trips pass here, but the
    # game's second track on its tight curves is laid only 8 m off the
    # first, and its trains then stand from six in the morning on
    # (docs/HANDOFF.md).
]


def branch_tool():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extract_branch_runs.py")
    spec = importlib.util.spec_from_file_location("extract_branch_runs", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def trains(timetable, names):
    """The trips of every weekday's set as the branch tool reads TRA's
    trains: each call's arrival and departure, and the weekdays it runs."""
    by_calls = collections.OrderedDict()
    for set_name in dict.fromkeys(timetable["days"]):
        days = {day for day, name in enumerate(timetable["days"]) if name == set_name}
        for trip in timetable["sets"][set_name]:
            calls = [(trip[i], trip[i + 1]) for i in range(0, len(trip), 2)]
            step = 1 if calls[-1][0] > calls[0][0] else -1
            filled = []
            for (a, at), (b, bt) in zip(calls, calls[1:]):
                filled.append((a, at))
                gap = list(range(a + step, b, step))
                for k, index in enumerate(gap, 1):
                    filled.append((index, at + (bt - at) * k // (len(gap) + 1)))
            filled.append(calls[-1])
            key = tuple(filled)
            if key in by_calls:
                by_calls[key] |= days
            else:
                by_calls[key] = set(days)
    out, days = [], {}
    for number, (calls, running) in enumerate(by_calls.items()):
        stops = []
        for position, (index, second) in enumerate(calls):
            last = position == len(calls) - 1
            first = position == 0
            arrives = second if last or first else second - DWELL
            stops.append({"name": names[index], "arrSec": arrives, "depSec": second, "stop": True})
        out.append({"train": str(number + 1), "typeName": "輕軌", "stops": stops})
        days[number] = running
    return out, days


def parked(tool, found, days, stops, line):
    """`line` with the trains an end station has no track for overnight
    standing instead at the stations next to it, one at each, a
    positioning run bringing each to the end for its first run and taking
    it back after the day's last (Danhai's Kanding stables nine of the
    Green Mountain Line's thirteen at its depot); or why no such layout
    fits."""
    ends = (stops[0], stops[-1])
    start = collections.Counter(line["overnight"])
    if all(start[end] <= END_TRACKS for end in ends):
        if all(line["tracks"][end] <= END_TRACKS for end in ends):
            return line, None
        return None, f"an end station needs {max(line['tracks'][e] for e in ends)} tracks"
    for end in ends:
        inner = stops[1:-1] if end == stops[0] else stops[-2:0:-1]
        while start[end] > END_TRACKS - 1:
            free = next((s for s in inner if start[s] == 0), None)
            if free is None:
                return None, f"{end}: {start[end]} trains overnight and no station beside it free"
            start[end] -= 1
            start[free] += 1
    line, problem = tool.line_runs({"trains": found}, days, stops, start=start)
    if problem:
        return None, problem
    worst = {s: n for s, n in line["tracks"].items() if n > (END_TRACKS if s in ends else 3)}
    if worst:
        return None, f"stations need more tracks than the game lays: {worst}"
    return line, None


def main(folder, out):
    tool = branch_tool()
    result = {
        "source": "The light rails' station timetables, Ministry of Transportation and Communications TDX "
                  "(fetched 2026-07-16), via the app's <system>_times.json",
        "licence": "Open Government Data License, version 1",
        "lines": [],
    }
    for system, line_id, after_station, after in LINES:
        network = json.load(open(os.path.join(folder, f"{system}.json"), encoding="utf-8"))
        names = [s["name"] for s in next(l for l in network["lines"] if l["id"] == line_id)["stations"]]
        timetable = json.load(open(os.path.join(folder, f"{system}_times.json"), encoding="utf-8"))["lines"][line_id]
        found, days = trains(timetable, names)
        stops = names[names.index(after_station):] if after_station else names
        game_id = f"{system}:{line_id}"
        label = game_id + (f" after {system}:{after}" if after else "")
        line, problem = tool.line_runs({"trains": found}, days, stops)
        if not problem:
            line, problem = parked(tool, found, days, stops, line)
        if problem:
            print(f"{label}: left out: {problem}")
            continue
        real = sum(1 for r in line["runs"] if not r.get("positioning"))
        print(f"{label}: {stops[0]}–{stops[-1]}, {real} real trips, {len(line['runs']) - real} positioning runs, "
              f"{sum(line['overnight'].values())} trainsets, overnight {line['overnight']}, "
              f"tracks {{{', '.join(f'{k} {v}' for k, v in line['tracks'].items() if v > 1)}}}")
        entry = {"id": game_id, "network": line_id}
        if after:
            entry["after"] = f"{system}:{after}"
        result["lines"].append({**entry, **line})
    # One run a line, as the branch lines' file.
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
