"""Taiwan Railway's ridership by station (ARCHITECTURE decision 298).

Reads Taiwan Railway's open data "每日各站點進出站人數" (data.gov.tw dataset
8792, the archive of one CSV a year) and writes, for one whole year, each
station's average a day: (entries + exits) / 2 over the days the station has
data, rounded to a whole rider. Stations are keyed by Taiwan Railway's station
code, the `id` of the app's `tra_station_info.json`; the tool prints every
code the app does not know and every station of the app with no data, so a
new or renamed station is seen, not dropped.

    python3 -I tools/real-ridership/build_tra_ridership.py ARCHIVE.zip \
        --year 2025 --downloaded 2026-10-20 \
        --stations RailwayGameApp/Resources/RealRailways/tra_station_info.json \
        --output RailwayGameApp/Resources/RealRailways/tra_ridership.json

Standard library only. See README.md for where the archive comes from.
"""

import argparse
import hashlib
import json
import sys
import zipfile
from collections import defaultdict

DATASET = "https://data.gov.tw/dataset/8792"
LICENCE = "Open Government Data License, version 1.0 (https://data.gov.tw/license)"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("archive", help="the dataset's zip of yearly CSV files")
    parser.add_argument("--year", type=int, required=True, help="a whole year the archive covers")
    parser.add_argument("--downloaded", required=True, help="the day the archive was downloaded, YYYY-MM-DD")
    parser.add_argument("--stations", required=True, help="the app's tra_station_info.json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    raw = open(args.archive, "rb").read()
    archive = zipfile.ZipFile(args.archive)
    # The yearly files end with the year, or with its last day for a file
    # that starts part way through one (20190423-20191231).
    names = [name for name in archive.namelist() if name.endswith(f"{args.year}.csv") or name.endswith(f"{args.year}1231.csv")]
    if len(names) != 1:
        sys.exit(f"the archive has no single file for {args.year}: {archive.namelist()}")
    lines = archive.read(names[0]).decode("utf-8-sig").splitlines()
    if lines[0].split(",") != ["TRN_OP_DATE", "STA_CODE", "GATE_IN_COMING_CNT", "GATE_OUT_GOING_CNT"]:
        sys.exit(f"unexpected header: {lines[0]}")

    days = defaultdict(set)
    riders = defaultdict(int)
    for line in lines[1:]:
        date, code, entries, exits = line.split(",")
        if not date.startswith(str(args.year)):
            sys.exit(f"a row of another year: {line}")
        days[code].add(date)
        riders[code] += int(entries) + int(exits)
    every_day = set().union(*days.values())
    if len(every_day) < 365:
        sys.exit(f"{args.year} has data for {len(every_day)} days only: not a whole year")

    stations = json.load(open(args.stations, encoding="utf-8"))
    names_by_code = {station["id"]: name for name, station in stations.items()}
    unknown = sorted(code for code in riders if code not in names_by_code)
    missing = sorted(name for code, name in names_by_code.items() if code not in riders)

    average = {code: round(riders[code] / 2 / len(days[code])) for code in sorted(riders)}
    output = {
        "source": {
            "title": "臺鐵每日各站點進出站人數",
            "publisher": "國營臺灣鐵路股份有限公司",
            "dataset": DATASET,
            "file": names[0],
            "archiveSha256": hashlib.sha256(raw).hexdigest(),
            "downloaded": args.downloaded,
            "licence": LICENCE,
        },
        "period": {"from": min(every_day), "to": max(every_day)},
        "measure": "average riders a day: (entries + exits) / 2 over the days the station has data",
        "riders": average,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")

    print(f"{len(average)} stations, {min(every_day)} to {max(every_day)}")
    print("codes the app does not know: " + (", ".join(unknown) or "none"))
    print("stations of the app with no data: " + (", ".join(missing) or "none"))
    short = sorted((names_by_code.get(code, code), len(dates)) for code, dates in days.items() if len(dates) < len(every_day))
    print("stations with data on fewer days: " + (", ".join(f"{name} ({count})" for name, count in short) or "none"))
    top = sorted(average.items(), key=lambda item: -item[1])[:5]
    print("busiest: " + ", ".join(f"{names_by_code.get(code, code)} {count:,}" for code, count in top))


if __name__ == "__main__":
    main()
