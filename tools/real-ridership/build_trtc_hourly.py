"""Taipei Metro's riders by hour of the day, a whole year (the tide's ruler).

Reads the same open data as build_trtc_ridership.py, "臺北捷運各站分時進出量
統計" (data.gov.tw dataset 128506): one CSV a month of every day's hourly
trips from each station to each other. The months of one year are streamed,
never saved. The output is a small file whose numbers the report test
TideReportTests (GameCoreTests) prints beside the game's own; the test
copies them rather than reading the file, and the app does not bundle it.

- Each service day runs from 06:00 to 06:00: a row before 06:00 belongs to
  the day before (the last trains after midnight, New Year's Eve all night).
- Working days and days off are told apart by the riders, not a calendar: a
  day with more riders than halfway between the year's median Monday-to-
  Friday and median Saturday-and-Sunday is a working day. Holidays on a
  weekday and make-up working Saturdays fall where they belong; the file
  names every day the weekday rule would have put elsewhere.
- For each station, a working day's average entries (trips from it) and
  exits (trips to it), all day, 07-09 and 17-19.
- Residential stations are the ten (with at least 1,000 entries and 1,000
  exits a working day) whose morning entries are the most times their morning exits; office
  stations the ten whose evening entries are the most times their morning
  entries (research RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md §2.2).

    python3 -I tools/real-ridership/build_trtc_hourly.py \
        --year 2025 --downloaded 2026-10-21 \
        --output tools/real-ridership/trtc_hourly_2025.json

Standard library and curl only. See README.md.
"""

import argparse
import csv
import datetime
import hashlib
import io
import json
import os
import re
import statistics
import sys
from collections import defaultdict

# The sibling tool's reader; -I leaves the script's folder off the path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_trtc_ridership import DATASET, INDEX, LICENCE, _Hashing, open_url

MORNING = range(7, 9)
EVENING = range(17, 19)
BUSY = 1_000
CHOSEN = 10


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--year", type=int, required=True, help="a whole year the data covers")
    parser.add_argument("--downloaded", required=True, help="the day the data was read, YYYY-MM-DD")
    parser.add_argument("--output", required=True)
    parser.add_argument("--cache", help="a folder to keep each month's sums in, so a second run reads only new months")
    parser.add_argument("--index", default=INDEX, help="the month index (a URL curl reads; tests give a file:// one)")
    args = parser.parse_args()

    with open_url(args.index) as response:
        index = list(csv.DictReader(io.StringIO(response.read().decode("utf-8-sig"))))
    by_month = {(int(row["西元年"]), int(row["月"])): row["URL"] for row in index}
    if [month for month in range(1, 13) if (args.year, month) not in by_month]:
        sys.exit(f"the index does not have all twelve months of {args.year}")
    # January's file starts with the last trains of the year before's 31
    # December; next January's holds this year's New Year's Eve after midnight.
    wanted = [(args.year, month) for month in range(1, 13)]
    if (args.year + 1, 1) in by_month:
        wanted.append((args.year + 1, 1))

    # service day -> 24 hours of entries; service day -> station -> [entries, exits, am in, am out, pm in, pm out]
    hours = defaultdict(lambda: [0] * 24)
    stations = defaultdict(lambda: defaultdict(lambda: [0] * 6))
    digests = {}
    for year, month in wanted:
        sums = month_sums(year, month, by_month[(year, month)], args.cache)
        for day, counts in sums["hours"].items():
            if day.startswith(f"{args.year}-"):
                hours[day] = [a + b for a, b in zip(hours[day], counts)]
        for day, per_station in sums["stations"].items():
            if day.startswith(f"{args.year}-"):
                for name, counts in per_station.items():
                    stations[day][name] = [a + b for a, b in zip(stations[day][name], counts)]
        digests[f"{year}-{month:02}"] = sums["sha256"]
        print(f"{year}-{month:02}: {sums['rows']:,} rows", flush=True)
    days = sorted(hours)
    if len(days) < 365:
        sys.exit(f"{args.year} has data for {len(days)} days only: not a whole year")

    total = {day: sum(hours[day]) for day in days}
    weekday = {day: datetime.date.fromisoformat(day).weekday() < 5 for day in days}
    line = (statistics.median(total[d] for d in days if weekday[d]) + statistics.median(total[d] for d in days if not weekday[d])) / 2
    working = {day: total[day] > line for day in days}
    kinds = {"working": [d for d in days if working[d]], "off": [d for d in days if not working[d]]}

    def shares(group):
        sums = [sum(hours[d][h] for d in group) for h in range(24)]
        return [round(count / sum(sums), 4) for count in sums]

    # Where two lines' gates are counted apart the data names them by line
    # ("BL板橋" and "Y板橋"), and one name ends with 站 ("大橋頭站"): as
    # build_trtc_ridership.py, each adds to the one station. 台北車站 is
    # the station's own name and keeps its 站.
    station_days = defaultdict(lambda: [0] * 6)
    for day in kinds["working"]:
        for name, counts in stations[day].items():
            name = re.sub(r"^(BL|BR|G|O|R|Y)(?=\D)", "", name)
            if not name.endswith("車站"):
                name = name.removesuffix("站")
            station_days[name] = [a + b for a, b in zip(station_days[name], counts)]
    average = {name: [round(count / len(kinds["working"])) for count in counts] for name, counts in station_days.items()}
    # The Circular line's own stations have entries but no exits in 128506
    # (New Taipei Metro counts them; build_ntmc_ridership.py): a station
    # needs both.
    busy = {name: counts for name, counts in average.items() if counts[0] >= BUSY and counts[1] >= BUSY}
    residential = sorted(busy, key=lambda name: -busy[name][2] / max(busy[name][3], 1))[:CHOSEN]
    office = sorted(busy, key=lambda name: -busy[name][4] / max(busy[name][2], 1))[:CHOSEN]

    def spread(values):
        values = sorted(values)
        return {"min": round(values[0], 3), "median": round(statistics.median(values), 3), "max": round(values[-1], 3)}

    output = {
        "source": {
            "title": "臺北捷運各站分時進出量統計",
            "publisher": "臺北大眾捷運股份有限公司",
            "dataset": DATASET,
            "index": INDEX,
            "monthSha256": digests,
            "downloaded": args.downloaded,
            "licence": LICENCE,
        },
        "period": {"from": days[0], "to": days[-1]},
        "measure": "service days of 06:00 to 06:00; hour h is the trips entering in h:00-h+1:00; a working day has more riders than halfway between the median weekday's and the median weekend day's",
        "days": {
            "working": len(kinds["working"]),
            "off": len(kinds["off"]),
            "weekdaysOff": [d for d in days if weekday[d] and not working[d]],
            "weekendsWorking": [d for d in days if not weekday[d] and working[d]],
        },
        "ridersADay": {kind: round(sum(total[d] for d in group) / len(group)) for kind, group in kinds.items()},
        "hourShare": {kind: shares(group) for kind, group in kinds.items()},
        "stations": {
            "columns": ["entries", "exits", "entries 07-09", "exits 07-09", "entries 17-19", "exits 17-19"],
            "workingDay": dict(sorted(average.items())),
        },
        "residential": {
            "stations": residential,
            "morningEntryShare": spread(busy[n][2] / busy[n][0] for n in residential),
            "morningEntriesToExits": spread(busy[n][2] / max(busy[n][3], 1) for n in residential),
        },
        "office": {
            "stations": office,
            "eveningToMorningEntries": spread(busy[n][4] / max(busy[n][2], 1) for n in office),
        },
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1)
        file.write("\n")

    print(f"{len(days)} service days, {days[0]} to {days[-1]}: {len(kinds['working'])} working, {len(kinds['off'])} off")
    print("weekdays off: " + (", ".join(output["days"]["weekdaysOff"]) or "none"))
    print("weekend days working: " + (", ".join(output["days"]["weekendsWorking"]) or "none"))
    print("riders a day: " + ", ".join(f"{kind} {count:,}" for kind, count in output["ridersADay"].items()))
    print("residential: " + ", ".join(residential) + f"; morning entries {output['residential']['morningEntryShare']}, to exits {output['residential']['morningEntriesToExits']}")
    print("office: " + ", ".join(office) + f"; evening to morning entries {output['office']['eveningToMorningEntries']}")


def month_sums(year, month, url, cache):
    """One month's file summed by service day: each hour's entries, and each
    station's entries and exits all day, 07-09 and 17-19; its row count and
    SHA-256. Kept in `cache` when given."""
    path = os.path.join(cache, f"hourly-{year}-{month:02}.json") if cache else None
    if path and os.path.exists(path):
        return json.load(open(path, encoding="utf-8"))
    hours = defaultdict(lambda: [0] * 24)
    stations = defaultdict(lambda: defaultdict(lambda: [0] * 6))
    digest = hashlib.sha256()
    rows = 0
    with open_url(url) as response:
        text = io.TextIOWrapper(io.BufferedReader(_Hashing(response, digest), 1 << 20), encoding="utf-8-sig", newline="")
        reader = csv.reader(text)
        header = next(reader)
        if header != ["日期", "時段", "進站", "出站", "人次"]:
            sys.exit(f"{year}-{month:02}: unexpected header {header}")
        before = {}
        for date, hour, origin, destination, trips in reader:
            hour, count = int(hour), int(trips)
            if not 0 <= hour < 24:
                sys.exit(f"{year}-{month:02}: hour {hour} on {date}")
            if hour < 6:
                if date not in before:
                    before[date] = (datetime.date.fromisoformat(date) - datetime.timedelta(days=1)).isoformat()
                day = before[date]
            else:
                day = date
            hours[day][hour] += count
            out, into = stations[day][origin], stations[day][destination]
            out[0] += count
            into[1] += count
            if hour in MORNING:
                out[2] += count
                into[3] += count
            elif hour in EVENING:
                out[4] += count
                into[5] += count
            rows += 1
    sums = {"hours": hours, "stations": stations, "rows": rows, "sha256": digest.hexdigest()}
    if path:
        os.makedirs(cache, exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            json.dump(sums, file, ensure_ascii=False)
    return sums


if __name__ == "__main__":
    main()
