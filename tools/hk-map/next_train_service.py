#!/usr/bin/env python3
"""Each MTR line's seconds between stations, headways and first train, from
samples of the next-train feed (`sample_next_train.py`), as `service.json`
for `build_hk_mtr.py` (decision 697).

    python3 -I tools/hk-map/next_train_service.py hong_kong.pbf \\
        mtr_lines_and_stations.csv <samples folder> tools/hk-map/service.json

The feed lists, for a station and a direction, the next four trains: where
each is bound and when it is there, to the second, from the timetable.

Between two stations that follow each other, a train's time is the later
station's less the earlier's. The feed does not say which train is which
and gives whole minutes, so a sample counts only where one difference takes
every train of the earlier station to a train of the later one
(`run_between`); of several that do (trains evenly spaced fit one headway
later as well), the one that pairs the most trains, then the shortest no
train could beat (130 km/h over the stretch). Only trains bound for a place
both stations list are paired: a terminus does not list its arrivals. The
line's figure is the median over every such sample, the two directions
together. It is from one station's time to the next's, so it holds the
stop. A stretch no sample settles, or whose median is no train's speed
(under 20 km/h or over 130), gets its length at the line's median speed
(every line's, when the line has none), and `runSamples` says 0 for it.

A line's headway is the median gap between two trains bound for its end
that follow each other at a station, over the samples taken in the peak
(07:30 to 09:30 and 17:30 to 19:30, Hong Kong time) and outside it. A
branch's trains are those bound for its end (Lok Ma Chau, LOHAS Park), and
the main line's those bound for its own (Lo Wu, Po Lam): really the
branches' trains run through over the main line.

The first train is the earliest the samples hold at either end. The last
train is not sampled: 00:30, as `lastTrainSec` says with `lastTrainEstimated`.
"""
import collections
import datetime
import glob
import importlib.util
import json
import os
import statistics
import sys

PEAKS = [[7 * 3600 + 1800, 9 * 3600 + 1800], [17 * 3600 + 1800, 19 * 3600 + 1800]]
LAST_TRAIN = 24 * 3600 + 1800


def build_tool():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_hk_mtr.py")
    spec = importlib.util.spec_from_file_location("build_hk_mtr", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seconds(stamp):
    return datetime.datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S")


def run_between(at_a, at_b, least):
    """The seconds from the earlier station to the later, or `None` where
    the two lists do not settle it: a difference, `least` seconds or more,
    that takes every train of the earlier station the later's list reaches
    to a train of the later station (within 15 s), at least two of them;
    of several, the one that pairs the most trains, then the shortest."""
    scored = []
    for took in sorted({(y - x).total_seconds() for x in at_a for y in at_b}):
        if not max(20, least) <= took <= 1800:
            continue
        reach = [x for x in at_a if (at_b[-1] - x).total_seconds() + 15 >= took and (at_b[0] - x).total_seconds() - 15 <= took]
        hit = sum(1 for x in reach if any(abs((y - x).total_seconds() - took) <= 15 for y in at_b))
        if len(reach) >= 2 and hit == len(reach):
            scored.append((hit, took))
    if not scored:
        return None
    most = max(hit for hit, _ in scored)
    return min(took for hit, took in scored if hit == most)


def main(extract, stations_csv, folder, out):
    tool = build_tool()
    import csv
    with open(stations_csv, encoding="utf-8-sig") as f:
        rows = [r for r in csv.DictReader(f) if r["Line Code"]]
    relations = tool.Relations()
    relations.apply_file(extract)
    parts = tool.Parts(relations.ways, relations.nodes)
    parts.apply_file(extract, locations=True)
    lines = [tool.line_of(spec, rows, relations.found, parts) for spec in tool.LINES]

    files = sorted(glob.glob(os.path.join(folder, "2*.json")))
    samples = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            samples.append(json.load(f))

    def trains(sample, code, station, key, bound):
        answer = sample.get(f"{code}-{station}", {})
        data = answer.get("data", {}).get(f"{code}-{station}", {})
        # A station the feed has no answer for says "-" for the time.
        if not data or answer.get("status") != 1 or len(data.get("curr_time", "")) < 19:
            return None, []
        now = seconds(data["curr_time"])
        return now, [(seconds(t["time"]), t["dest"]) for t in data.get(key, [])
                     if t.get("valid") == "Y" and (bound is None or t["dest"] == bound)]

    result = {}
    every_speed = []
    for line in lines:
        code, stations = line["code"], line["stations"]
        ends = {"UP": stations[-1]["code"], "DOWN": stations[0]["code"]}
        runs = [[] for _ in stations[1:]]
        gaps = {"peak": [], "offpeak": []}
        first = []
        for sample in samples:
            for key, bound in ends.items():
                order = list(range(len(stations))) if key == "UP" else list(range(len(stations) - 1, -1, -1))
                for a, b in zip(order, order[1:]):
                    # Any train's, wherever bound: a short working takes as long.
                    _, at_a = trains(sample, code, stations[a]["code"], key, None)
                    _, at_b = trains(sample, code, stations[b]["code"], key, None)
                    both = {d for _, d in at_a} & {d for _, d in at_b}
                    least = abs(stations[a]["d"] - stations[b]["d"]) * 3600 / 130
                    took = run_between([t for t, d in at_a if d in both], [t for t, d in at_b if d in both], least)
                    if took is not None:
                        runs[min(a, b)].append(took)
                for index in order[:-1]:
                    now, at = trains(sample, code, stations[index]["code"], key, bound)
                    if now is None:
                        continue
                    at = [t for t, _ in at]
                    for x, y in zip(at, at[1:]):
                        of_day = x.hour * 3600 + x.minute * 60 + x.second
                        gap = (y - x).total_seconds()
                        if 60 <= gap <= 1800:
                            gaps["peak" if any(p <= of_day < q for p, q in PEAKS) else "offpeak"].append(gap)
                    if index == order[0] and at:
                        first.append(at[0].hour * 3600 + at[0].minute * 60 + at[0].second)
        if not gaps["offpeak"]:
            if "--provisional" not in sys.argv:
                sys.exit(f"{line['id']}: the samples give no headway")
            gaps["offpeak"] = [600]
        # A stretch no sample settles, or settles at no train's speed: its
        # length at the line's median speed.
        length = lambda i: abs(stations[i + 1]["d"] - stations[i]["d"]) * 1000
        for i, r in enumerate(runs):
            if r and not 20 / 3.6 <= length(i) / statistics.median(r) <= 130 / 3.6:
                runs[i] = []
        speeds = [length(i) / statistics.median(r) for i, r in enumerate(runs) if r]
        every_speed.extend(speeds)
        guessed = [i for i, r in enumerate(runs) if not r]
        for i in guessed:
            runs[i] = [length(i) / statistics.median(speeds or every_speed)]
        # Before 03:00 is the night before's last trains, not the first.
        morning = [t for t in first if t >= 4 * 3600]
        offpeak = round(statistics.median(gaps["offpeak"]))
        result[line["id"]] = {
            "runSec": [round(statistics.median(r)) for r in runs],
            "runSamples": [0 if i in guessed else len(r) for i, r in enumerate(runs)],
            "peakHeadwaySec": round(statistics.median(gaps["peak"])) if gaps["peak"] else offpeak,
            "offpeakHeadwaySec": offpeak,
            "headwaySamples": {k: len(v) for k, v in gaps.items()},
            "firstTrainSec": min(morning) if morning else 6 * 3600,
            "lastTrainSec": LAST_TRAIN, "lastTrainEstimated": True,
            "peaks": PEAKS,
        }
        r = result[line["id"]]
        print(f"{line['id']:8} end to end {sum(r['runSec']) / 60:5.1f} min  peak {r['peakHeadwaySec']:4} s "
              f"off-peak {r['offpeakHeadwaySec']:4} s  first {r['firstTrainSec'] // 3600:02}:{r['firstTrainSec'] % 3600 // 60:02} "
              f"samples {min(r['runSamples'])}–{max(r['runSamples'])} a stretch, headways {r['headwaySamples']}")
    name = lambda p: os.path.basename(p)[:-5]
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"sampled": f"{len(files)} sweeps, {name(files[0])} to {name(files[-1])}",
                   "feed": "https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php",
                   "lines": result}, f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main(*[a for a in sys.argv[1:] if a != "--provisional"])
