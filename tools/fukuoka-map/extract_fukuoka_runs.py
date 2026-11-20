#!/usr/bin/env python3
"""The runs of the Fukuoka City Subway lines, from `fksubway.json` and
`fksubway_times.json`, as the pack's `metro_runs.json` (decision 854).

    python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

It is `tools/real-timetables/extract_metro_runs.py` run on the Fukuoka
files: the same checks and layout (where the trains stand overnight, the
positioning runs, each station's tracks), so a line is in the file only if
the game can lay and run it as it does a Taiwan metro. A line that does not
pass is left out and the tool prints why. As Hong Kong's (`extract_hk_runs.py`).
"""
import importlib.util
import json
import os
import sys

SYSTEM = "fksubway"


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
    # Decision 712 (Hong Kong's, kept): a train standing overnight at a station between the
    # ends leaves before the morning's first train the same way reaches it.
    tool.OUT_BEFORE_FIRST = True
    # Decision 898: the Nanakuma Line is bought with a depot past
    # Hashimoto, its end (`RealLineDepotSite.hashimoto`), counts its trains
    # by the game's dwell, and has three minutes at Hashimoto to make a
    # delay good (`extract_branch_runs.RECOVERY`): 23 trains, not 20.
    tool.DEPOT_ENDS = dict(tool.DEPOT_ENDS, **{f"{SYSTEM}:N": ("橋本",)})
    tool.COUNT_GAME_DWELL = True
    tool.RECOVERY = {"橋本": 180}
    out = os.path.join(folder, "metro_runs.json")
    tool.main(folder, out)
    with open(out, encoding="utf-8") as f:
        text = f.read()
    head, rest = text.split(',"lines":[', 1)
    head = json.dumps({
        "source": "Trips laid out from headways this project estimated and times between stations worked out from "
                  "the distance, via fksubway_times.json; not the operator's timetable",
        "licence": "this project's estimate; stations: National Land Numerical Information N02 (MLIT), CC BY 4.0",
    }, ensure_ascii=False, separators=(",", ":"))[:-1]
    text = head + ',"lines":[' + rest
    json.loads(text)
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    sys.path.insert(0, here)
    import build_fukuoka_rail
    build_fukuoka_rail.write_manifest(folder)


if __name__ == "__main__":
    main(*sys.argv[1:])
