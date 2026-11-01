#!/usr/bin/env python3
"""Turn the light rails' and metros' real timetables the app bundles into
the runs of the lines a player can buy (decision 400, 10j-2 and 10j-3), as
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
trips cut there as a branch line's are at its junction. The Green Mountain
Line is not (decision 493): after the Blue Coast Line it is bought whole,
with its own runs.

The metros (`METROS`) are read the same way, their trains named 捷運.
A metro's evening brings trains in faster than it sends them out, so a
train no later run of the day needs leaves for where it stands overnight
as soon as it is in and turned round (`balanced`'s `prompt="spare"`),
not after the day's last train out. Only the Xinbeitou and Xiaobitan
Branch Lines and the Sanying Line pass: every other metro line's ends
stand more trains at once than the game lays tracks (the tool prints
each one's count). The Sanying Line's trains standing overnight at
stations between come in from beyond them after the day's last train
there (`extract_branch_runs.facing`); before, they stood across the
night's last runs and the line stood still from the second day.

Danhai's Green Mountain Line is bought with its real depot past Kanding
(decision 489, `DEPOT_ENDS`): its trains stand there overnight and while
the line does not need them, so its ends are not held to the tracks the
game lays for the trains standing overnight. Its `tracks` count only the
trains the line needs at a station within the look ahead the game's depot
uses (`depot_tracks`), and an end may have up to `DEPOT_END_TRACKS`, its
loops three deep either side. The Wenhu Line is bought with its two, at
Muzha and Neihu (decision 535, PR W); its ends would hold 16 trains each
within the look ahead, so they are laid with `DEPOT_END_TRACKS` and the
game sends the rest into the depots. Not listed: the Kaohsiung Circular Light
Rail. Its trains run round the loop and come back to Lizihnei; a line's
runs of the game run end to end (decision 535).

The Ankeng LRT (decision 535, continued) stands two of its trains
overnight at stations between, Shuangcheng having too few tracks. Each
comes in from beyond its station, facing the end its first run of the
morning leaves for (`extract_branch_runs.beyond`): one from Shuangcheng
runs out to Shisizhang first. Come straight from Shuangcheng, it stood on
the second track, where the game lays no way over to the first, and the
morning's trains toward Shisizhang stood behind it from 06:12.
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
# Decision 489: the lines bought with a real depot past an end station
# (`RealLineDepotSite` in Sources/GamePresentation/RealLineDepot.swift),
# by their game id: that end station.
# Decision 535 (PR W): the Wenhu Line runs on into a depot past each end,
# the Muzha depot past Taipei Zoo and the Neihu depot past Taipei Nangang
# Exhibition Center.
DEPOT_ENDS = {"ntdlrt:V": ("崁頂",), "trtc:BR": ("動物園", "南港展覽館")}
# The tracks such a line's end station may have: its own and loops three
# deep either side.
DEPOT_END_TRACKS = 7
# How long a train waits at a station for its next run before the game
# sends it to the depot instead (`GameWorld.runDepotLookahead`).
LOOKAHEAD = 2 * 3600

# (system, line id in `<system>.json`, the station it is bought from when
# the line named by `after` is already the company's, `after`).
LINES = [
    ("ntdlrt", "V", None, None),
    ("ntdlrt", "VB", None, None),
    # Not the Green Mountain Line from Binhai Shalun after the Blue Coast
    # Line: it would stand eleven trains at once there. The game buys it
    # whole instead, laid beside the Blue Coast Line to Binhai Shalun
    # (decision 493), with the runs listed for it alone.
    ("ntdlrt", "VB", "濱海沙崙", "V"),
    ("ntalrt", "K", None, None),
    # Decision 400, 10j-3: the metros. Each is tried; those whose ends
    # stand more trains at once than the game lays tracks are left out
    # and say so.
    ("trtc", "R", None, None),
    ("trtc", "R_XBT", None, None),
    ("trtc", "G", None, None),
    ("trtc", "G_XBT", None, None),
    ("trtc", "O_XINZHUANG", None, None),
    ("trtc", "O_LUZHOU", None, None),
    ("trtc", "BL", None, None),
    ("trtc", "Y", None, None),
    # Decision 535 (PR W): the Wenhu Line, with its two depots.
    ("trtc", "BR", None, None),
    ("tymc", "A", None, None),
    ("krtc", "KR", None, None),
    ("krtc", "KO", None, None),
    ("tmrt", "TG", None, None),
    # Decision 400 (10j-3): the Sanying Line, its trains standing overnight
    # at stations between brought in after the last train there.
    ("sanying", "LB", None, None),
]
# The metros' systems: their trains a day has no more runs for leave for
# where they stand overnight as soon as they are in (`balanced`'s
# `prompt="spare"`), not after the last train out, as their evening
# brings trains in faster than it sends them out.
METROS = {"trtc", "tymc", "krtc", "tmrt", "sanying"}


def branch_tool():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extract_branch_runs.py")
    spec = importlib.util.spec_from_file_location("extract_branch_runs", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def trains(timetable, names, kind="輕軌"):
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
        out.append({"train": str(number + 1), "typeName": kind, "stops": stops})
        days[number] = running
    return out, days


def parked(tool, found, days, stops, line, prompt=True):
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
    line, problem = tool.line_runs({"trains": found}, days, stops, start=start, prompt=prompt)
    if problem:
        return None, problem
    worst = {s: n for s, n in line["tracks"].items() if n > (END_TRACKS if s in ends else 3)}
    if worst:
        return None, f"stations need more tracks than the game lays: {worst}"
    return line, None


def depot_tracks(tool, found, start, stops, depots):
    """Decision 489: the most trainsets standing at each station at once
    on any weekday of a line bought with a depot beside its end station
    in `depots`, played from `start` as `tool.tracks` does but with the
    trains standing at those ends overnight in their depots, and each train counted at
    a station only from `LOOKAHEAD` before its next run there (till then
    the game keeps it in the depot); one with no further run there that
    day goes to the depot at once. The positioning runs taking the other
    end's trains back there for the night are kept, as the game keeps
    them."""
    most = collections.Counter()
    for day in range(7):
        idle = collections.defaultdict(list)
        for station, count in start.items():
            if station not in depots:
                idle[station] += [0] * count
        spans = collections.defaultdict(list)
        for run in tool.day_of(found, day):
            origin, leaves = run["calls"][0][0], run["calls"][0][2]
            ready = [t for t in idle[origin] if t + tool.TURNAROUND <= leaves or t == 0]
            if ready:
                came = min(ready)
                idle[origin].remove(came)
            else:
                came = leaves  # out of the depot, as it leaves
            spans[origin].append((max(came, leaves - LOOKAHEAD), leaves))
            for name, arrival, departure in run["calls"][1:-1]:
                spans[name].append((arrival, departure))
            idle[run["calls"][-1][0]].append(run["calls"][-1][1])
        for station, times in spans.items():
            standing = peak = 0
            for _, leaving in sorted([(a, 0) for a, _ in times] + [(b, 1) for _, b in times]):
                standing += -1 if leaving else 1
                peak = max(peak, standing)
            most[station] = max(most[station], peak)
    return {s: max(1, most[s]) for s in stops}


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
        metro = system in METROS
        found, days = trains(timetable, names, "捷運" if metro else "輕軌")
        stops = names[names.index(after_station):] if after_station else names
        game_id = f"{system}:{line_id}"
        label = game_id + (f" after {system}:{after}" if after else "")
        line, problem = tool.line_runs({"trains": found}, days, stops)
        depots = DEPOT_ENDS.get(game_id)
        if depots and not problem:
            line["tracks"] = depot_tracks(tool, line["runs"], line["overnight"], stops, depots)
            ends = (stops[0], stops[-1])
            # Decision 535 (PR W): an end with a depot beyond it is laid
            # with no more than `DEPOT_END_TRACKS`; the game sends the
            # trains it cannot hold into the depot (decisions 221 and 297).
            for end in ends:
                if end in depots:
                    line["tracks"][end] = min(line["tracks"][end], DEPOT_END_TRACKS)
            worst = {s: n for s, n in line["tracks"].items() if n > (DEPOT_END_TRACKS if s in ends else 3)}
            if worst:
                problem = f"stations need more tracks than the game lays, with the depot: {worst}"
        elif not problem:
            line, problem = parked(tool, found, days, stops, line, "spare" if metro else True)
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
