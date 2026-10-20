"""Kaohsiung Metro's ridership by station (ARCHITECTURE decision 298).

Reads Kaohsiung's open data "高雄都會區大眾捷運系統各站旅運量入站" and
"…出站" (data.gov.tw datasets 159641 and 159640, one row a year, a column a
station) and writes, for one year, each station's average riders a day:
(entries + exits) / 2 over the year's days, rounded. The cloud container
cannot reach data.kcg.gov.tw, so the owner downloads the two CSV files and
hands them over; the tool records their SHA-256 and the day they were
downloaded.

Columns are named by code and name ("R3 小港站", "O5 R10 美麗島站"). Five
stations have been renamed since the data's names; RENAMED gives the names
the app's krtc.json uses. The tool prints every station it cannot match,
and every station of the app's red and orange lines with no data.

    python3 -I tools/real-ridership/build_krtc_ridership.py ENTRIES.csv EXITS.csv \
        --year 2025 --downloaded 2026-10-20 \
        --stations RailwayGameApp/Resources/RealRailways/krtc.json \
        --output RailwayGameApp/Resources/RealRailways/krtc_ridership.json

Standard library only. See README.md.
"""

import argparse
import calendar
import csv
import hashlib
import json
import re
import sys

DATASETS = ["https://data.gov.tw/dataset/159641", "https://data.gov.tw/dataset/159640"]
LICENCE = "Open Government Data License, version 1.0 (https://data.gov.tw/license)"
# The data's station names that Kaohsiung Metro has since renamed, by the
# name the app's krtc.json (TDX) gives the same station.
RENAMED = {
    "楠梓加工區": "楠梓科技園區",
    "南岡山": "岡山高醫",
    "西子灣": "哈瑪星",
    "市議會": "前金",
    "技擊館": "苓雅運動園區",
}


def read(path, year):
    """The year's row of one file: {station name: riders in the year}."""
    raw = open(path, "rb").read()
    rows = list(csv.reader(raw.decode("utf-8-sig").splitlines()))
    header = rows[0]
    if header[:3] != ["Seq", "年份", "總計"]:
        sys.exit(f"{path}: unexpected header {header[:3]}")
    matching = [row for row in rows[1:] if row and row[1] == f"{year}年"]
    if len(matching) != 1:
        sys.exit(f"{path}: no single row for {year}")
    row = matching[0]
    stations = {}
    for column, value in zip(header, row):
        # "R3 小港站", "O5 R10 美麗島站", "RK1岡山車站": the codes, then the name.
        match = re.fullmatch(r"((?:[A-Z]+\d+(?:[A-Z](?!\d))?\s*)+)(.+?)", column.strip())
        if not match or column.endswith(("小計", "團體票", "其他")):
            continue
        name = match.group(2).strip().removesuffix("站")
        stations[RENAMED.get(name, name)] = int(value.replace(",", ""))
    total = int(row[2].replace(",", ""))
    return stations, total, hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("entries", help="the entries file (dataset 159641)")
    parser.add_argument("exits", help="the exits file (dataset 159640)")
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--downloaded", required=True, help="the day the owner downloaded the files, YYYY-MM-DD")
    parser.add_argument("--stations", required=True, help="the app's krtc.json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    entries, entry_total, entry_hash = read(args.entries, args.year)
    exits, exit_total, exit_hash = read(args.exits, args.year)
    lines = json.load(open(args.stations, encoding="utf-8"))["lines"]
    metro = {station["name"] for line in lines if line["name"] in ("紅線", "橘線") for station in line["stations"]}

    # The data writes every name with 站; the app only some (高雄車站, 鳳山西站).
    def app_name(name):
        return name + "站" if name not in metro and name + "站" in metro else name
    entries = {app_name(name): count for name, count in entries.items()}
    exits = {app_name(name): count for name, count in exits.items()}
    if set(entries) != set(exits):
        sys.exit(f"the files' stations differ: {sorted(set(entries) ^ set(exits))}")
    if entry_total != exit_total:
        print(f"note: the year's entries ({entry_total:,}) and exits ({exit_total:,}) differ")
    days = 366 if calendar.isleap(args.year) else 365
    riders = {name: round((entries[name] + exits[name]) / 2 / days) for name in sorted(entries)}
    output = {
        "source": {
            "title": "高雄都會區大眾捷運系統各站旅運量入站、出站",
            "publisher": "高雄市政府",
            "datasets": DATASETS,
            "fileSha256": {"entries": entry_hash, "exits": exit_hash},
            "downloaded": args.downloaded,
            "downloadedBy": "the owner (data.kcg.gov.tw is out of the cloud container's reach)",
            "licence": LICENCE,
            "renamed": RENAMED,
        },
        "period": {"from": f"{args.year}0101", "to": f"{args.year}1231"},
        "measure": "average riders a day: (entries + exits) / 2 over the year's days",
        "riders": riders,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")
    print(f"{len(riders)} stations, {args.year}")
    print("names the app does not have: " + (", ".join(sorted(set(riders) - metro)) or "none"))
    print("red and orange line stations of the app with no data: " + (", ".join(sorted(metro - set(riders))) or "none"))
    top = sorted(riders.items(), key=lambda item: -item[1])[:5]
    print("busiest: " + ", ".join(f"{name} {count:,}" for name, count in top))


if __name__ == "__main__":
    main()
