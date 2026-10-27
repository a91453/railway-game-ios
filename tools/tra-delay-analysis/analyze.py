"""Taiwan Railway delay statistics from the TDX LiveTrainDelay history.

Reads the gzipped JSON Lines of `Railway/tdx-snapshot-2026-10/data/` in the
private reference repository and the TRA timetable of
`Railway/taiwan-rail-reference-clean/source/data/` (train number -> train type
and stop order), and writes small CSV tables to the output directory. Raw rows
never leave the reference repository.

    python3 -I tools/tra-delay-analysis/analyze.py \
        --data <ref>/Railway/tdx-snapshot-2026-10/data \
        --timetable <ref>/Railway/taiwan-rail-reference-clean/source/data \
        --out tools/tra-delay-analysis/results

Standard library only. A run over the 341 days takes a few minutes.
"""

import argparse
import collections
import csv
import datetime
import glob
import gzip
import json
import os

TAIWAN = datetime.timezone(datetime.timedelta(hours=8))
# Two reports of one train number more than this apart belong to two runs.
# The longest run (a round-the-island train plus a large delay) stays well
# under it, and the same number runs again at the earliest about 12 h later.
TRIP_GAP_SECONDS = 8 * 3600
# TRA counts a train on time when it reaches its terminal within 5 minutes of
# the timetable (DelayTime is in whole minutes, so <= 5).
ON_TIME_MINUTES = 5
DELAY_BUCKETS = [0, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 45, 60, 90, 120, 180]

# National holidays and the long weekends around them in the period covered
# (DGPA calendars for 2025 and 2026). Name -> inclusive Taiwan dates.
HOLIDAYS = {
    "行憲紀念日 2025-12-25": ("2025-12-25", "2025-12-25"),
    "元旦 2026": ("2026-01-01", "2026-01-01"),
    "春節 2026": ("2026-02-14", "2026-02-22"),
    "228 2026": ("2026-02-27", "2026-03-01"),
    "兒童節清明 2026": ("2026-04-03", "2026-04-06"),
    "勞動節 2026": ("2026-05-01", "2026-05-03"),
    "端午 2026": ("2026-06-19", "2026-06-21"),
    "中秋教師節 2026": ("2026-09-25", "2026-09-28"),
    "國慶 2026": ("2026-10-09", "2026-10-11"),
    "光復節 2026": ("2026-10-24", "2026-10-26"),
}


def parse_time(text):
    return int(datetime.datetime.fromisoformat(text).timestamp())


def taiwan(ts):
    return datetime.datetime.fromtimestamp(ts, TAIWAN)


def load_timetable(folder):
    with open(os.path.join(folder, "tra_schedule.json"), encoding="utf-8") as f:
        schedule = json.load(f)
    with open(os.path.join(folder, "tra_station_info.json"), encoding="utf-8") as f:
        stations = json.load(f)
    name_to_id = {name: info["id"] for name, info in stations.items()}
    # A train number can have several stop lists over the 14 days; keep the
    # one used on the most days.
    uses = collections.Counter()
    for indices in schedule["dates"].values():
        uses.update(indices)
    best = {}
    for index, train in enumerate(schedule["trains"]):
        number = train["train"]
        if number not in best or uses[index] > uses[best[number]]:
            best[number] = index
    table = {}
    for number, index in best.items():
        train = schedule["trains"][index]
        # Stops with no station code (the "臺北-環島" end marker) are left out.
        order = [sid for sid in (name_to_id.get(stop["name"]) for stop in train["stops"]) if sid]
        table[number] = {
            "type": train["typeName"],
            "car": train["carName"],
            "order": {sid: i for i, sid in enumerate(order)},
            "count": len(order),
            "first": order[0],
            "last": order[-1],
            "departure": train["stops"][0]["depSec"],
        }
    return table


def read_rows(path):
    with gzip.open(path, "rt", encoding="utf-8-sig") as f:
        for line in f:
            if line.strip():
                row = json.loads(line)
                yield (row["TrainNo"], parse_time(row["SrcUpdateTime"]),
                       row["StationID"], int(row["DelayTime"]))


def trips(files):
    """Yields (train number, [(time, station, delay), ...]) per run, in time order."""
    pending = {}
    for path in files:
        by_train = collections.defaultdict(list)
        for number, ts, station, delay in read_rows(path):
            by_train[number].append((ts, station, delay))
        end = max(ts for rows in by_train.values() for ts, _, _ in rows)
        for number, rows in pending.items():
            by_train[number].extend(rows)
        pending = {}
        for number, rows in by_train.items():
            # Stable sort keeps the file order of reports with the same time.
            rows.sort(key=lambda r: r[0])
            run = [rows[0]]
            for row in rows[1:]:
                if row[0] - run[-1][0] > TRIP_GAP_SECONDS:
                    yield number, run
                    run = []
                run.append(row)
            if end - run[-1][0] <= TRIP_GAP_SECONDS:
                pending[number] = run
            else:
                yield number, run
    for number, run in pending.items():
        yield number, run


def per_station_last(run):
    """Station -> last reported delay, in the order the stations were first reached."""
    order, last = [], {}
    for _, station, delay in run:
        if station not in last:
            order.append(station)
        last[station] = delay
    return order, last


def peak_band(start):
    if start.weekday() >= 5:
        return "週末"
    minutes = start.hour * 60 + start.minute
    if 6 * 60 + 30 <= minutes < 9 * 60 or 16 * 60 + 30 <= minutes < 19 * 60 + 30:
        return "平日尖峰"
    return "平日離峰"


def holiday_of(day):
    text = day.isoformat()
    for name, (first, last) in HOLIDAYS.items():
        if first <= text <= last:
            return name
    return ""


class Group:
    __slots__ = ("trips", "on_time", "delays")

    def __init__(self):
        self.trips = 0
        self.on_time = 0
        self.delays = collections.Counter()

    def add(self, delay):
        self.trips += 1
        self.on_time += delay <= ON_TIME_MINUTES
        self.delays[delay] += 1

    def percentile(self, p):
        target = p * (self.trips - 1)
        seen = 0
        for value in sorted(self.delays):
            seen += self.delays[value]
            if seen - 1 >= target:
                return value
        return 0

    def mean(self):
        return sum(v * n for v, n in self.delays.items()) / self.trips if self.trips else 0

    def row(self, key):
        return [key, self.trips, f"{100 * self.on_time / self.trips:.2f}" if self.trips else "",
                f"{self.mean():.2f}", self.percentile(0.5), self.percentile(0.9),
                self.percentile(0.99), max(self.delays) if self.delays else 0]


HEADER = ["group", "trips", "on_time_pct", "mean_min", "p50", "p90", "p99", "max"]


def write(out, name, header, rows):
    with open(os.path.join(out, name), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True)
    parser.add_argument("--timetable", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    table = load_timetable(args.timetable)
    files = sorted(glob.glob(os.path.join(args.data, "TRA_LiveTrainDelay_*.json*.gz")))
    # Only about 150 stations report trains (smaller ones never do), so a
    # timetable stop is compared only when its station reports at all; the
    # newest file stands for the set.
    reporting = {station for _, _, station, _ in read_rows(files[-1])}
    for info in table.values():
        info["reporting"] = [sid for sid in info["order"] if sid in reporting]

    groups = collections.defaultdict(lambda: collections.defaultdict(Group))
    events = Group()
    rows_seen = 0
    numbers = set()
    days = collections.defaultdict(lambda: [Group(), Group(), 0])  # final, max, rows
    worst_trips = []
    # Accumulation along the route: tenth of the stop list -> delay counts.
    along = collections.defaultdict(lambda: collections.defaultdict(Group))
    ends_at_terminal = 0
    matched_trips = 0
    month_match = collections.defaultdict(lambda: [0, 0])
    first_report = None
    last_report = None
    station_ids = set()
    station_late = collections.defaultdict(Group)
    hourly = collections.defaultdict(Group)

    for number, run in trips(files):
        rows_seen += len(run)
        numbers.add(number)
        first_report = run[0][0] if first_report is None else min(first_report, run[0][0])
        last_report = run[-1][0] if last_report is None else max(last_report, run[-1][0])
        for _, station, delay in run:
            events.add(delay)
            station_ids.add(station)
        start = taiwan(run[0][0])
        day = start.date()
        order, last = per_station_last(run)
        peak = max(d for _, _, d in run)
        info = table.get(number)
        # Trains report at the stations they pass as well as at their stops,
        # so a run matches the 2026-10 timetable when it reported at least
        # 80 % of that train's stops at reporting stations.
        matched = (bool(info) and len(info["reporting"]) >= 2
                   and sum(s in last for s in info["reporting"]) >= 0.8 * len(info["reporting"]))
        if matched:
            # The train's delay is the last one reported at the last
            # timetable stop it reached: the terminal when it reported there.
            stop = max((s for s in order if s in info["order"]), key=info["order"].get)
            final = last[stop]
        else:
            final = last[order[-1]]
        month = start.strftime("%Y-%m")
        month_match[month][0] += 1
        month_match[month][1] += matched
        kind = info["type"] if matched else "未對上時刻表"
        days[day][0].add(final)
        days[day][1].add(peak)
        days[day][2] += len(run)
        for name, key in (
            ("all", "全部"),
            ("type", kind),
            ("car", info["car"] if matched else "未對上時刻表"),
            ("band", peak_band(start)),
            ("weekday", "一二三四五六日"[start.weekday()]),
            ("month", month),
            ("holiday", holiday_of(day) or "非連假"),
            ("start_hour", f"{start.hour:02d}"),
        ):
            groups[name][key].add(final)
        groups["max_all"]["全部"].add(peak)
        groups["max_type"][kind].add(peak)
        worst_trips.append((peak, final, number, start.isoformat(), kind))
        if matched:
            matched_trips += 1
            # Terminals are not reported (a train reports when it leaves or
            # passes a station), so the last report is usually the stop
            # before the terminal.
            ends_at_terminal += stop in info["reporting"][-2:]
            count = max(info["count"] - 1, 1)
            for station in order:
                if station in info["order"]:  # stops only, not stations passed
                    tenth = min(int(10 * info["order"][station] / count), 9)
                    along[kind][tenth].add(last[station])
                    along["全部"][tenth].add(last[station])
        for station in order:
            station_late[station].add(last[station])
        for ts, _, delay in run:
            hourly[taiwan(ts).hour].add(delay)

    write(args.out, "overview.csv", ["key", "value"], [
        ["files", len(files)],
        ["rows", rows_seen],
        ["events_late_share_pct", f"{100 * (events.trips - events.delays[0]) / events.trips:.2f}"],
        ["event_max_delay", max(events.delays)],
        ["distinct_train_numbers", len(numbers)],
        ["distinct_station_ids", len(station_ids)],
        ["first_report_taiwan", taiwan(first_report).isoformat()],
        ["last_report_taiwan", taiwan(last_report).isoformat()],
        ["taiwan_days", len(days)],
        ["trips", groups["all"]["全部"].trips],
        ["trips_matched_to_2026_10_timetable", matched_trips],
        ["matched_trips_last_report_within_last_two_reporting_stops", ends_at_terminal],
        ["timetable_train_numbers", len(table)],
    ])
    for name in ("all", "type", "car", "band", "weekday", "month", "holiday", "start_hour"):
        keys = sorted(groups[name])
        write(args.out, f"final_by_{name}.csv", HEADER, [groups[name][k].row(k) for k in keys])
    write(args.out, "max_by_type.csv", HEADER,
          [groups["max_type"][k].row(k) for k in sorted(groups["max_type"])]
          + [groups["max_all"]["全部"].row("全部")])
    final = groups["all"]["全部"]
    total = final.trips
    rows = []
    for i, low in enumerate(DELAY_BUCKETS):
        high = DELAY_BUCKETS[i + 1] - 1 if i + 1 < len(DELAY_BUCKETS) else None
        n = sum(c for v, c in final.delays.items() if v >= low and (high is None or v <= high))
        rows.append([f"{low}" if high == low else f"{low}-{high if high is not None else ''}",
                     n, f"{100 * n / total:.3f}"])
    write(args.out, "final_histogram.csv", ["minutes", "trips", "pct"], rows)
    write(args.out, "event_by_hour.csv", HEADER, [hourly[h].row(f"{h:02d}") for h in sorted(hourly)])
    write(args.out, "along_route.csv", ["type", "tenth_of_route"] + HEADER[1:],
          [[kind] + along[kind][t].row(t) for kind in sorted(along) for t in sorted(along[kind])])
    write(args.out, "month_timetable_match.csv", ["month", "trips", "matched", "pct"],
          [[m, a, b, f"{100 * b / a:.1f}"] for m, (a, b) in sorted(month_match.items())])
    day_rows = []
    for day in sorted(days):
        fin, peak, nrows = days[day]
        day_rows.append([day.isoformat(), "一二三四五六日"[day.weekday()], holiday_of(day), nrows,
                         fin.trips, f"{100 * fin.on_time / fin.trips:.2f}", f"{fin.mean():.2f}",
                         fin.percentile(0.9), max(fin.delays), max(peak.delays)])
    write(args.out, "by_day.csv", ["day", "weekday", "holiday", "rows", "trips", "on_time_pct",
                                    "mean_final_min", "p90_final", "max_final", "max_any"], day_rows)
    worst_trips.sort(reverse=True)
    write(args.out, "worst_trips.csv", ["max_min", "final_min", "train", "start_taiwan", "type"],
          [list(t) for t in worst_trips[:40]])
    station_rows = [[s] + station_late[s].row(s)[1:] for s in station_late if station_late[s].trips >= 1000]
    station_rows.sort(key=lambda r: float(r[2]))
    write(args.out, "station_departure_on_time.csv", ["station_id"] + HEADER[1:], station_rows)


if __name__ == "__main__":
    main()
