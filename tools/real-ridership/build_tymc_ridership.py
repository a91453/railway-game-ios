"""Taoyuan Airport MRT's ridership by station (ARCHITECTURE decision 298).

Reads Taoyuan Metro's open data "桃園大眾捷運各場站運量每月統計表"
(data.gov.tw dataset 164957, files on opendata.tycg.gov.tw): one CSV a
month with the columns 年度, 月份, 捷運站別, 平均日運量, a row a station. The
cloud container cannot reach opendata.tycg.gov.tw ("Request Rejected"), so
the owner downloads the year's twelve files in Taiwan and hands them over;
the tool records each file's SHA-256 and the day it was downloaded.

The column is already an average a day. The dataset does not say of what,
so `--measure` must say: `mean` when it is (entries + exits) / 2 or
entries (the line's entries and exits are equal, so the two are the same
number near enough), `sum` when it is entries + exits (the tool halves it).
The tool prints the stations' total of each month to compare with the
whole line's average a day (dataset 164956) and A1's to compare with what
the news reports; README.md says how. A station's year is its months'
averages weighted by the months' days.

    python3 -I tools/real-ridership/build_tymc_ridership.py FILE... \
        --year 2025 --measure mean --downloaded 2026-10-21 \
        --stations RailwayGameApp/Resources/RealRailways/tymc.json \
        --output RailwayGameApp/Resources/RealRailways/tymc_ridership.json

Twelve files, one for each month of the year. It prints every station it
cannot match and every station of the app with no data. Standard library
only. See README.md.
"""

import argparse
import calendar
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict

DATASET = "https://data.gov.tw/dataset/164957"
LICENCE = "Open Government Data License, version 1.0 (https://data.gov.tw/license)"
COLUMNS = ["年度", "月份", "捷運站別", "平均日運量"]


def text(raw):
    """The platform says Big5; a file saved again may be UTF-8."""
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return raw.decode("cp950")


def number(value):
    return float(value.replace(",", "").strip())


def read(path, year):
    """One file: (month, {station as written: average a day}, SHA-256)."""
    raw = open(path, "rb").read()
    table = list(csv.reader(text(raw).splitlines()))
    header = [cell.strip() for cell in table[0]]
    if any(column not in header for column in COLUMNS):
        sys.exit(f"{path}: columns {header}, not {COLUMNS}")
    at = {column: header.index(column) for column in COLUMNS}
    months = set()
    stations = {}
    for row in table[1:]:
        if not any(cell.strip() for cell in row):
            continue
        # 年度 as the Gregorian year or the Republic's (114 is 2025).
        row_year = int(number(row[at["年度"]]))
        if row_year + (1911 if row_year < 1911 else 0) != year:
            sys.exit(f"{path}: a row of {row[at['年度']]}, not {year}")
        months.add(int(number(row[at["月份"]])))
        name = row[at["捷運站別"]].strip()
        if name in stations:
            sys.exit(f"{path}: {name} twice")
        stations[name] = number(row[at["平均日運量"]])
    if len(months) != 1:
        sys.exit(f"{path}: months {sorted(months)}, not one")
    return months.pop(), stations, hashlib.sha256(raw).hexdigest()


def key(name):
    """A name as both the data and the app may write it: no code in front
    ("A1台北車站", "A1 台北車站"), 臺 as 台, no 站 at the end."""
    name = re.sub(r"^A\d+[a-z]?\s*", "", name.strip())
    return name.replace("臺", "台").removesuffix("站")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("files", nargs="+", help="the year's twelve CSV files")
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--measure", choices=["mean", "sum"], required=True, help="what 平均日運量 is: (entries + exits) / 2 or entries (mean), or entries + exits (sum)")
    parser.add_argument("--downloaded", required=True, help="the day the owner downloaded the files, YYYY-MM-DD")
    parser.add_argument("--stations", required=True, help="the app's tymc.json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    by_month = {}
    digests = {}
    for path in args.files:
        month, stations, digest = read(path, args.year)
        if month in by_month:
            sys.exit(f"{path}: a second file of month {month}")
        by_month[month] = stations
        digests[f"{args.year}-{month:02d}"] = digest
    if sorted(by_month) != list(range(1, 13)):
        sys.exit(f"months {sorted(by_month)}, not all twelve of {args.year}")

    lines = json.load(open(args.stations, encoding="utf-8"))["lines"]
    app = {key(station["name"]): station["name"] for line in lines for station in line["stations"]}
    halve = 2 if args.measure == "sum" else 1
    weighted = defaultdict(float)
    days_of = defaultdict(int)
    for month, stations in sorted(by_month.items()):
        days = calendar.monthrange(args.year, month)[1]
        a1 = next((count for name, count in stations.items() if key(name) == key("台北車站")), None)
        print(f"{args.year}-{month:02d}: stations' total {sum(stations.values()):,.0f} a day; A1 {a1:,.0f}" if a1 is not None else f"{args.year}-{month:02d}: stations' total {sum(stations.values()):,.0f} a day; no A1")
        for name, count in stations.items():
            station = app.get(key(name), name)
            weighted[station] += count * days
            days_of[station] += days
    riders = {name: round(weighted[name] / days_of[name] / halve) for name in sorted(weighted)}
    short = sorted(name for name, days in days_of.items() if days < (366 if calendar.isleap(args.year) else 365))
    output = {
        "source": {
            "title": "桃園大眾捷運各場站運量每月統計表",
            "publisher": "桃園大眾捷運股份有限公司",
            "dataset": DATASET,
            "fileSha256": digests,
            "downloaded": args.downloaded,
            "downloadedBy": "the owner (opendata.tycg.gov.tw is out of the cloud container's reach)",
            "licence": LICENCE,
        },
        "period": {"from": f"{args.year}-01-01", "to": f"{args.year}-12-31"},
        "measure": (
            "average riders a day: the months' 平均日運量 ((entries + exits) / 2 or entries) weighted by their days"
            if args.measure == "mean" else
            "average riders a day: the months' 平均日運量 (entries + exits) weighted by their days, halved"
        ),
        "riders": riders,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")
    print(f"{len(riders)} stations, {args.year}")
    print("names the app does not have: " + (", ".join(sorted(set(riders) - set(app.values()))) or "none"))
    print("stations of the app with no data: " + (", ".join(sorted(set(app.values()) - set(riders))) or "none"))
    print("stations missing from some months (averaged over the months they have): " + (", ".join(short) or "none"))
    top = sorted(riders.items(), key=lambda item: -item[1])[:5]
    print("busiest: " + ", ".join(f"{name} {count:,}" for name, count in top))


if __name__ == "__main__":
    main()
