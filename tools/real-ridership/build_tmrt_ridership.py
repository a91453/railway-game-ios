"""Taichung Metro's ridership by station (ARCHITECTURE decision 298).

Reads Taichung Metro's open data "臺中捷運股份有限公司捷運各站旅運量"
(data.gov.tw dataset 175718, files on newdatacenter.taichung.gov.tw): one
JSON file a month, a row a station and a measure ("欄位名稱" the station,
"數值" the month's riders). The platform lacks some months, and until
2026-02 the files have exits only, no entries; so the tool takes the months
of the year the platform lists and writes, for each station, its average a
day over those months' days: (entries + exits) / 2 where every month has
both, otherwise exits alone (the whole line's entries and exits are equal,
so a station's exits are its riders a day near enough). A year with fewer
than twelve months is refused unless `--partial` says to take it; the file
then names the months it is the average of.

The data writes every name with 站 (高鐵臺中站, 北屯總站); the app's
tmrt.json only some. The tool prints every station it cannot match and
every station of the app with no data, so a new or renamed station is seen,
not dropped.

    python3 -I tools/real-ridership/build_tmrt_ridership.py \
        --year 2025 --partial --downloaded 2026-10-20 \
        --stations RailwayGameApp/Resources/RealRailways/tmrt.json \
        --output RailwayGameApp/Resources/RealRailways/tmrt_ridership.json

`--files FOLDER` reads FOLDER/YYYY-MM.json instead of downloading (the
tests use it). Standard library and curl only. See README.md.
"""

import argparse
import calendar
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

DATASET = "https://data.gov.tw/dataset/175718"
API = "https://data.gov.tw/api/v2/rest/dataset/175718"
LICENCE = "Open Government Data License, version 1.0 (https://data.gov.tw/license)"
# The two measures of a station's own gates; 團體票 and 其他 are rows of the
# whole line, with no station.
ENTRIES = "捷運各站旅運量-入站人數(人次)(單位:人次)"
EXITS = "捷運各站旅運量-出站人數(人次)(單位:人次)"


def fetch(url):
    """`url`'s body, through curl: it reads the system's and a proxy's
    certificate settings as they are, which Python's strict default does
    not always accept."""
    result = subprocess.run(["curl", "-sSfL", "--retry", "3", url], stdout=subprocess.PIPE)
    if result.returncode != 0:
        sys.exit(f"curl failed ({result.returncode}) for {url}")
    return result.stdout


def listed_months(year):
    """{month: download URL} of the year's files the platform lists."""
    distribution = json.loads(fetch(API))["result"]["distribution"]
    months = {}
    for resource in distribution:
        match = re.match(r"(\d{4})-(\d{2})_", resource["resourceDescription"])
        if match and int(match.group(1)) == year:
            months[int(match.group(2))] = resource["resourceDownloadUrl"]
    return months


def key(name):
    """A name as both the data and the app may write it."""
    return name.replace("臺", "台").removesuffix("站")


def read(raw, year, month):
    """One month's file: ({station: entries}, {station: exits})."""
    entries, exits = {}, {}
    for row in json.loads(raw.decode("utf-8-sig")):
        if row["資料時間日期"][:7] != f"{year}-{month:02d}":
            sys.exit(f"{year}-{month:02d}: a row of {row['資料時間日期']}")
        name = row["欄位名稱"].strip()
        if row["項目"] not in (ENTRIES, EXITS) or not name:
            continue
        target = entries if row["項目"] == ENTRIES else exits
        if name in target:
            sys.exit(f"{year}-{month:02d}: {name} twice")
        target[name] = int(row["數值"].replace(",", ""))
    if not exits:
        sys.exit(f"{year}-{month:02d}: no exits")
    if entries and set(entries) != set(exits):
        sys.exit(f"{year}-{month:02d}: entries and exits name different stations")
    return entries, exits


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--partial", action="store_true", help="take a year the platform has only some months of")
    parser.add_argument("--downloaded", required=True, help="the day the data was read, YYYY-MM-DD")
    parser.add_argument("--stations", required=True, help="the app's tmrt.json")
    parser.add_argument("--output", required=True)
    parser.add_argument("--files", help="a folder of YYYY-MM.json files to read instead of downloading")
    args = parser.parse_args()

    if args.files:
        months = {}
        for name in os.listdir(args.files):
            match = re.fullmatch(r"(\d{4})-(\d{2})\.json", name)
            if match and int(match.group(1)) == args.year:
                months[int(match.group(2))] = os.path.join(args.files, name)
    else:
        months = listed_months(args.year)
    if not months:
        sys.exit(f"no month of {args.year}")
    if len(months) < 12 and not args.partial:
        sys.exit(f"{args.year} has months {sorted(months)} only; --partial takes them")

    by_month = {}
    digests = {}
    for month in sorted(months):
        raw = open(months[month], "rb").read() if args.files else fetch(months[month])
        by_month[month] = read(raw, args.year, month)
        digests[f"{args.year}-{month:02d}"] = hashlib.sha256(raw).hexdigest()

    with_entries = all(entries for entries, _ in by_month.values())
    days = sum(calendar.monthrange(args.year, month)[1] for month in by_month)
    totals = defaultdict(int)
    for entries, exits in by_month.values():
        for name, count in exits.items():
            totals[name] += count + entries[name] if with_entries else count
    stations = {name for _, exits in by_month.values() for name in exits}
    if any(set(exits) != stations for _, exits in by_month.values()):
        print("note: the months name different stations; each is averaged over all the months' days")

    lines = json.load(open(args.stations, encoding="utf-8"))["lines"]
    app = {key(station["name"]): station["name"] for line in lines for station in line["stations"]}
    divisor = 2 * days if with_entries else days
    riders = {app.get(key(name), name): round(count / divisor) for name, count in sorted(totals.items())}
    month_list = [f"{args.year}-{month:02d}" for month in sorted(by_month)]
    output = {
        "source": {
            "title": "臺中捷運股份有限公司捷運各站旅運量",
            "publisher": "臺中捷運股份有限公司",
            "dataset": DATASET,
            "fileSha256": digests,
            "downloaded": args.downloaded,
            "licence": LICENCE,
        },
        "period": {"from": f"{month_list[0]}-01", "to": f"{month_list[-1]}-{calendar.monthrange(args.year, max(by_month))[1]:02d}"},
        "months": month_list,
        "measure": (
            "average riders a day: (entries + exits) / 2 over the listed months' days"
            if with_entries else
            "average riders a day: exits over the listed months' days (these months have no entries)"
        ),
        "riders": riders,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")
    print(f"{len(riders)} stations, months {', '.join(month_list)} ({days} days), {'entries and exits' if with_entries else 'exits only'}")
    print("names the app does not have: " + (", ".join(sorted(set(riders) - set(app.values()))) or "none"))
    print("stations of the app with no data: " + (", ".join(sorted(set(app.values()) - set(riders))) or "none"))
    top = sorted(riders.items(), key=lambda item: -item[1])[:5]
    print("busiest: " + ", ".join(f"{name} {count:,}" for name, count in top))


if __name__ == "__main__":
    main()
