#!/usr/bin/env python3
"""The runs of the Fukuoka City Subway lines, from `fksubway.json` and
`fksubway_times.json`, and (decision 975) of the Kyushu Shinkansen, from
`kyushushinkansen.json` and `kyushushinkansen_times.json`, as the pack's
`metro_runs.json` (decision 854).

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
# SHINKANSEN-SALE (decision 975): the Kyushu Shinkansen, a system of its own in the same pack.
SHINKANSEN = "kyushushinkansen"


def main(folder):
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "real-timetables", "extract_metro_runs.py")
    spec = importlib.util.spec_from_file_location("extract_metro_runs", path)
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    tool.LINES = []
    for system in (SYSTEM, SHINKANSEN):
        # The Shinkansen's file is there once `build_kyushu_shinkansen.py
        # merge` has run.
        if not os.path.exists(os.path.join(folder, f"{system}.json")):
            continue
        with open(os.path.join(folder, f"{system}.json"), encoding="utf-8") as f:
            network = json.load(f)
        tool.LINES += [(system, line["id"], None, None) for line in network["lines"]]
    tool.METROS = {SYSTEM, SHINKANSEN}
    # Decision 712 (Hong Kong's, kept): a train standing overnight at a station between the
    # ends leaves before the morning's first train the same way reaches it.
    tool.OUT_BEFORE_FIRST = True
    # Decision 898: the Nanakuma Line is bought with a depot past
    # Hashimoto, its end (`RealLineDepotSite.hashimoto`), counts its trains
    # by the game's dwell, and has three minutes at Hashimoto to make a
    # delay good (`extract_branch_runs.RECOVERY`): 23 trains, not 20.
    # Decision 975: the Kyushu Shinkansen is bought with a depot past
    # Kumamoto (`RealLineDepotSite.kumamoto`), where its day starts and
    # ends, with five minutes there to make a delay good.
    tool.DEPOT_ENDS = dict(tool.DEPOT_ENDS, **{f"{SYSTEM}:N": ("橋本",), f"{SHINKANSEN}:KS": ("熊本",)})
    tool.COUNT_GAME_DWELL = True
    tool.RECOVERY = {"橋本": 180, "熊本": 300}
    # Decision 975: Hakata, where each train turns round in eight minutes
    # (`build_kyushu_shinkansen.FAR_TURN`), with two of the real station's
    # tracks: the timetable stands one train there at a time, but without
    # traffic control the next one sets off from Shin-Tosu for its
    # platform before the one standing there has gone, and with one track
    # waited at Shin-Tosu (24 runs a day late).
    tool.TRACKS_AT_LEAST = {f"{SHINKANSEN}:KS": {"博多": 2}}
    out = os.path.join(folder, "metro_runs.json")
    tool.main(folder, out)
    with open(out, encoding="utf-8") as f:
        text = f.read()
    head, rest = text.split(',"lines":[', 1)
    head = json.dumps({
        "source": "Trips laid out from headways this project estimated and times between stations worked out from "
                  "the distance, via fksubway_times.json and kyushushinkansen_times.json; not the operator's timetable",
        "licence": "this project's estimate; stations: National Land Numerical Information N02 (MLIT), CC BY 4.0",
    }, ensure_ascii=False, separators=(",", ":"))[:-1]
    text = head + ',"lines":[' + rest
    json.loads(text)
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    sys.path.insert(0, here)
    import build_fukuoka_rail
    build_fukuoka_rail.refresh_manifest(folder)


if __name__ == "__main__":
    main(*sys.argv[1:])
