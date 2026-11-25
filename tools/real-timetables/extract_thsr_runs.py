#!/usr/bin/env python3
"""THSR-SALE (decision 993): the runs of the Taiwan High Speed Rail on sale,
Nangang to Zuoying, from the app's `thsr-schedule.json` (one real day of
TDX's daily timetable, 2026-09-29, 169 trains), added to the app's
`metro_runs.json` as the line `thsr_sched:THSR`.

    python3 -I tools/real-timetables/extract_thsr_runs.py \\
        RailwayGameApp/Resources/RealRailways

It is `extract_metro_runs.py`'s checks and layout (where the trains stand
overnight, the positioning runs, each station's tracks) on the High Speed
Rail's day, as `tools/fukuoka-map/extract_fukuoka_runs.py` runs them on
the Kyushu Shinkansen's:

- Every train of the day runs every day of the week (the file has one
  day). A train calls where the timetable has it stop, with its real
  arrival and departure, and passes the stations between at the time
  between its neighbours' (`passes`, decision 605), as the Taoyuan
  Airport MRT's expresses do.
- The line is bought with a depot past each end (`RealLineDepotSite`
  `nangang` and `zuoying`): its trains stand there overnight and while
  the line does not need them, so the ends are laid with no more than
  `END_TRACKS` and the game sends the rest into the depots.
- A train has five minutes at either end to make a delay good, as the
  Kyushu Shinkansen's at Kumamoto.

Every other line of `metro_runs.json` is kept as it is; the High Speed
Rail's entry is replaced or appended.
"""
import collections
import importlib.util
import json
import os
import sys

LINE = "THSR"
SYSTEM = "thsr_sched"
GAME_ID = f"{SYSTEM}:{LINE}"
# North to south, as `track_stations.geojson` names them.
STATIONS = ["南港", "台北", "板橋", "桃園", "新竹", "苗栗", "台中", "彰化", "雲林", "嘉義", "台南", "左營"]
ENDS_WITH_DEPOTS = ("南港", "左營")
# Where the trainsets stand overnight, in the depots past the ends. The
# day is uneven (81 trains reach Nangang from Zuoying, 67 leave for it;
# 17 more turn round at Taichung, where the real ones stand at the Wuri
# depot), so a positioning run takes each train the next morning needs
# elsewhere there after the last train leaves where it stands. Ten at
# Nangang and thirty at Zuoying is the fewest sets (forty; thirty-nine
# needs one more positioning run a day) whose day runs with the fewest
# positioning runs (33): `python3 -I tools/real-timetables/extract_thsr_runs.py --sets`
# prints the others.
OVERNIGHT = {"南港": 10, "左營": 30}


def metro_tool():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("extract_metro_runs", os.path.join(here, "extract_metro_runs.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def trains(schedule):
    """Each train of the day as the branch tool reads one: its calls with
    their real times, the stations it skips between them passed at the
    time between its neighbours."""
    out = []
    for train in schedule["trains"]:
        stops = train["stops"]
        names = [s["name"] for s in stops]
        positions = [STATIONS.index(n) for n in names]
        step = 1 if positions[-1] > positions[0] else -1
        filled = []
        for (a, sa), (b, sb) in zip(zip(positions, stops), zip(positions[1:], stops[1:])):
            filled.append({"name": STATIONS[a], "arrSec": sa["arrSec"], "depSec": sa["depSec"], "stop": True})
            gap = list(range(a + step, b, step))
            for k, index in enumerate(gap, 1):
                second = sa["depSec"] + (sb["arrSec"] - sa["depSec"]) * k // (len(gap) + 1)
                filled.append({"name": STATIONS[index], "arrSec": second, "depSec": second, "stop": False})
        last = stops[-1]
        filled.append({"name": STATIONS[positions[-1]], "arrSec": last["arrSec"], "depSec": last["depSec"], "stop": True})
        out.append({"train": train["train"], "typeName": "高鐵", "stops": filled})
    return out


def sets(folder):
    """The layouts that run, by sets and then positioning runs."""
    tool = metro_tool()
    branch = tool.branch_tool()
    branch.RECOVERY = {end: 300 for end in ENDS_WITH_DEPOTS}
    schedule = json.load(open(os.path.join(folder, "thsr-schedule.json"), encoding="utf-8"))
    for total in range(36, 46):
        for north in range(4, total - 20):
            found = trains(schedule)
            days = {index: set(range(7)) for index in range(len(found))}
            line, _ = branch.line_runs({"trains": found}, days, STATIONS, start={"南港": north, "左營": total - north})
            if line:
                moved = sum(1 for r in line["runs"] if r.get("positioning"))
                print(f"{total} sets: Nangang {north}, Zuoying {total - north}, {moved} positioning runs a day")


def main(folder):
    tool = metro_tool()
    branch = tool.branch_tool()
    schedule = json.load(open(os.path.join(folder, "thsr-schedule.json"), encoding="utf-8"))
    found = trains(schedule)
    days = {index: set(range(7)) for index in range(len(found))}
    passed = {t["train"]: [s["name"] for s in t["stops"] if not s["stop"]] for t in found}

    branch.RECOVERY = {end: 300 for end in ENDS_WITH_DEPOTS}
    line, problem = branch.line_runs({"trains": found}, days, STATIONS, start=OVERNIGHT)
    if problem:
        sys.exit(f"{GAME_ID}: left out: {problem}")
    line["tracks"] = tool.depot_tracks(branch, line["runs"], line["overnight"], STATIONS, ENDS_WITH_DEPOTS)
    for end in ENDS_WITH_DEPOTS:
        line["tracks"][end] = min(line["tracks"][end], tool.END_TRACKS)
    worst = {s: n for s, n in line["tracks"].items() if n > (tool.END_TRACKS if s in ENDS_WITH_DEPOTS else tool.BETWEEN_TRACKS)}
    if worst:
        sys.exit(f"{GAME_ID}: stations need more tracks than the game lays, with the depots: {worst}")
    for run in line["runs"]:
        names = [c[0] for c in run["calls"] if c[0] in passed.get(run["train"], ())] if not run.get("positioning") else []
        if names:
            run["passes"] = names
    real = sum(1 for r in line["runs"] if not r.get("positioning"))
    print(f"{GAME_ID}: {STATIONS[0]}–{STATIONS[-1]}, {real} real trips, {len(line['runs']) - real} positioning runs, "
          f"{sum(line['overnight'].values())} trainsets, overnight {dict(line['overnight'])}, tracks {line['tracks']}")

    entry = {"id": GAME_ID, "network": LINE, **line}
    head = json.dumps({k: v for k, v in entry.items() if k != "runs"}, ensure_ascii=False, separators=(",", ":"))
    body = ",\n".join(json.dumps(run, ensure_ascii=False, separators=(",", ":")) for run in entry["runs"])
    text = head[:-1] + ',"runs":[\n' + body + "\n]}"

    path = os.path.join(folder, "metro_runs.json")
    with open(path, encoding="utf-8") as f:
        existing = f.read()
    head, rest = existing.split(',"lines":[\n', 1)
    parts = rest.rstrip().removesuffix("]}").rstrip().split("\n]},\n")
    parts = [p if p.endswith("\n]}") else p + "\n]}" for p in parts]
    parts = [p for p in parts if json.loads(p)["id"] != GAME_ID] + [text]
    out = head + ',"lines":[\n' + ",\n".join(parts) + "\n]}\n"
    data = json.loads(out)
    assert [l["id"] for l in data["lines"]][-1] == GAME_ID
    with open(path, "w", encoding="utf-8") as f:
        f.write(out)
    print(f"{path}: {len(out.encode())} bytes, {len(data['lines'])} lines")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--sets"]:
        sets(*sys.argv[2:])
    else:
        main(*sys.argv[1:])
