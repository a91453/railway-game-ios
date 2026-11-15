#!/usr/bin/env python3
"""The runs of the Rovaniemi lines a player can buy, from `vr.json` and
`vr_times.json`, as the pack's `metro_runs.json` (decision 789).

    python3 -I tools/rovaniemi-map/extract_rovaniemi_runs.py RailwayGameApp/Resources/MapPacks/rovaniemi

It is `tools/real-timetables/extract_metro_runs.py` run on the Rovaniemi
files, as `tools/hk-map/extract_hk_runs.py` runs it on Hong Kong's: the
same checks and layout (where the trains stand overnight, the positioning
runs, each station's tracks). The Kemijärvi line's trains that run through
Misi without stopping pass it (decision 605's `PASSING_LINES`). A line
that does not pass is left out and the tool prints why.
"""
import importlib.util
import json
import os
import sys

SYSTEM = "vr"


def main(folder):
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "real-timetables", "extract_metro_runs.py")
    spec = importlib.util.spec_from_file_location("extract_metro_runs", path)
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    with open(os.path.join(folder, f"{SYSTEM}.json"), encoding="utf-8") as f:
        network = json.load(f)
    tool.LINES = [(SYSTEM, line["id"], None, None) for line in network["lines"]]
    tool.METROS = set()
    tool.PASSING_LINES = {f"{SYSTEM}:KJA"}
    tool.OUT_BEFORE_FIRST = True
    out = os.path.join(folder, "metro_runs.json")
    tool.main(folder, out)
    with open(out, encoding="utf-8") as f:
        text = f.read()
    head, rest = text.split(',"lines":[', 1)
    head = json.dumps({
        "source": "Scheduled trains of Fintraffic / digitraffic.fi, via vr_times.json",
        "licence": "CC BY 4.0",
    }, ensure_ascii=False, separators=(",", ":"))[:-1]
    text = head + ',"lines":[' + rest
    runs = json.loads(text)
    # The runs' trains by their real names ("PYO 265"), not the tool's
    # count: each real run is the timetable's trip that leaves its first
    # station at its first second and ends at its last station.
    with open(os.path.join(folder, f"{SYSTEM}_times.json"), encoding="utf-8") as f:
        timetable = json.load(f)["lines"]
    stations = {line["id"]: [s["name"] for s in line["stations"]] for line in network["lines"]}
    for line in runs["lines"]:
        named = {}
        sets = timetable[line["network"]]
        names = stations[line["network"]]
        for set_name, trips in sets["sets"].items():
            for trip, train in zip(trips, sets["trains"][set_name]):
                key = (names[trip[0]], trip[1], names[trip[-2]])
                # The same trip under another number on other days (S 21
                # on Sundays is S 35 on weekdays) is one run of both.
                if train not in named.setdefault(key, []):
                    named[key].append(train)
        for run in line["runs"]:
            if run.get("positioning"):
                continue
            key = (run["calls"][0][0], run["calls"][0][2], run["calls"][-1][0])
            if key not in named:
                sys.exit(f"{line['id']}: no train of the timetable is the run {run['calls']}")
            run["train"] = "／".join(named[key])
            run["type"] = named[key][0].split(" ")[0]
    text = '{"source":%s,"licence":%s,"lines":[\n' % (json.dumps(runs["source"]), json.dumps(runs["licence"]))
    text += ",\n".join(
        '{%s,"runs":[\n%s]}' % (json.dumps({k: v for k, v in line.items() if k != "runs"}, ensure_ascii=False,
                                             separators=(",", ":"))[1:-1],
                                 ",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in line["runs"]))
        for line in runs["lines"]) + "]}\n"
    json.loads(text)
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    sys.path.insert(0, here)
    import build_rovaniemi_rail
    build_rovaniemi_rail.write_manifest(folder)


if __name__ == "__main__":
    main(*sys.argv[1:])
