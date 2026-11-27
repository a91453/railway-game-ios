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
# Decision 1028: JR Kyushu's conventional line, the Relay Kamome.
CONVENTIONAL = "jrkyushu"
# Decision 1029: JR West's Sanyo Shinkansen, Hakata to Kokura.
SANYO = "sanyoshinkansen"
# Decision 1041: the Kumamoto City Tram's Lines A and B, run to the
# operator's timetable.
TRAM = "kumamotocity"


def main(folder):
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "real-timetables", "extract_metro_runs.py")
    spec = importlib.util.spec_from_file_location("extract_metro_runs", path)
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    tool.LINES = []
    for system in (SYSTEM, SHINKANSEN, CONVENTIONAL, SANYO, TRAM):
        # The Shinkansen's file is there once `build_kyushu_shinkansen.py
        # merge` has run.
        if not os.path.exists(os.path.join(folder, f"{system}.json")):
            continue
        with open(os.path.join(folder, f"{system}.json"), encoding="utf-8") as f:
            network = json.load(f)
        tool.LINES += [(system, line["id"], None, None) for line in network["lines"]]
        # Decision 1041: Line B shares Kengunmachi to Karashimacho with
        # Line A, so once A is the company's it is laid from Karashimacho,
        # where they part, its trips cut there (as Danhai's Blue Coast
        # Line is after the Green Mountain Line, decision 400).
        if system == TRAM:
            tool.LINES.append((TRAM, "B", "辛島町", "A"))
    tool.METROS = {SYSTEM, SHINKANSEN, CONVENTIONAL, SANYO}
    # Decision 712 (Hong Kong's, kept): a train standing overnight at a station between the
    # ends leaves before the morning's first train the same way reaches it.
    tool.OUT_BEFORE_FIRST = True
    # Decision 1041: Kumamoto's trams stand overnight in their two real
    # depots, Line A's at Ōe beside Kōtsūkyoku-mae (`RealLineDepotSite.oe`)
    # and Line B's past Kami-Kumamoto (`RealLineDepotSite.kamiKumamoto`):
    # each train comes from there before its first run and goes back after
    # its last (the operator's timetable leaves those runs out).
    tool.STABLED_AT = {f"{TRAM}:A": "交通局前", f"{TRAM}:B": "上熊本"}
    # Decision 898: the Nanakuma Line is bought with a depot past
    # Hashimoto, its end (`RealLineDepotSite.hashimoto`), counts its trains
    # by the game's dwell, and has three minutes at Hashimoto to make a
    # delay good (`extract_branch_runs.RECOVERY`): 23 trains, not 20.
    # Decision 975: the Kyushu Shinkansen is bought with a depot past
    # Kumamoto (`RealLineDepotSite.kumamoto`), where its day starts and
    # ends, with five minutes there to make a delay good.
    # Decision 1030: Kumamoto to Shin-Minamata too, bought with the real
    # depot at Tomiai 8 km south of Kumamoto (`RealLineDepotSite.tomiai`).
    tool.DEPOT_ENDS = dict(tool.DEPOT_ENDS, **{f"{SYSTEM}:N": ("橋本",), f"{SHINKANSEN}:KS": ("熊本",),
                                                f"{SHINKANSEN}:KS2": ("熊本",)})
    tool.COUNT_GAME_DWELL = True
    tool.RECOVERY = {"橋本": 180, "熊本": 300}
    # Decision 975: Hakata, where each train turns round in eight minutes
    # (`build_kyushu_shinkansen.FAR_TURN`), with two of the real station's
    # tracks: the timetable stands one train there at a time, but without
    # traffic control the next one sets off from Shin-Tosu for its
    # platform before the one standing there has gone, and with one track
    # waited at Shin-Tosu (24 runs a day late).
    # Decision 1030: Shin-Minamata, where the trains from Kumamoto turn
    # round in eighteen minutes (`build_kyushu_shinkansen_south.FAR_TURN`),
    # with the real station's three tracks (2面3線, 11-13: JR Kyushu's
    # station plan via the Duet research of 2026-11-27), so a late train
    # in does not hold the next one at Shin-Yatsushiro.
    tool.TRACKS_AT_LEAST = {f"{SHINKANSEN}:KS": {"博多": 2}, f"{SHINKANSEN}:KS2": {"新水俁": 3}}
    out = os.path.join(folder, "metro_runs.json")
    tool.main(folder, out)
    with open(out, encoding="utf-8") as f:
        text = f.read()
    head, rest = text.split(',"lines":[', 1)
    head = json.dumps({
        "source": "Trips laid out from headways this project estimated and times between stations worked out from "
                  "the distance, via fksubway_times.json, kyushushinkansen_times.json, jrkyushu_times.json and sanyoshinkansen_times.json; not the operator's timetable",
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
