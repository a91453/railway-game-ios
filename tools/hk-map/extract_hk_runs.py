#!/usr/bin/env python3
"""The runs of the MTR lines a player can buy, from `hkmtr.json` and
`hkmtr_times.json`, as the pack's `metro_runs.json` (decision 697).

    python3 -I tools/hk-map/extract_hk_runs.py RailwayGameApp/Resources/MapPacks/hongkong

It is `tools/real-timetables/extract_metro_runs.py` run on the Hong Kong
files: the same checks and layout (where the trains stand overnight, the
positioning runs, each station's tracks), so a line is in the file only if
the game can lay and run it as it does a Taiwan metro. A line that does not
pass is left out and the tool prints why; none has a depot of its own yet.
"""
import importlib.util
import json
import os
import sys

SYSTEM = "hkmtr"


def main(folder):
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "real-timetables", "extract_metro_runs.py")
    spec = importlib.util.spec_from_file_location("extract_metro_runs", path)
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    with open(os.path.join(folder, f"{SYSTEM}.json"), encoding="utf-8") as f:
        network = json.load(f)
    tool.LINES = [(SYSTEM, line["id"], None, None) for line in network["lines"]]
    tool.METROS = {SYSTEM}
    out = os.path.join(folder, "metro_runs.json")
    tool.main(folder, out)
    with open(out, encoding="utf-8") as f:
        text = f.read()
    head, rest = text.split(',"lines":[', 1)
    head = json.dumps({
        "source": "Trips laid out from headways and times between stations sampled from MTR Corporation Limited's "
                  "Real-time MTR train information, DATA.GOV.HK, via hkmtr_times.json; not the operator's timetable",
        "licence": "DATA.GOV.HK Terms and Conditions of Use",
    }, ensure_ascii=False, separators=(",", ":"))[:-1]
    text = head + ',"lines":[' + rest
    json.loads(text)
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    sys.path.insert(0, here)
    import build_hk_mtr
    build_hk_mtr.write_manifest(folder)


if __name__ == "__main__":
    main(*sys.argv[1:])
