"""Taiwan High Speed Rail's ridership by station (ARCHITECTURE decision 298).

Reads the "各站進出旅客人數" tables of Taiwan High Speed Rail's page
"客運運輸情形" (its operating statistics, a table of entries and one of exits
for each year, a row for each month and a column for each station, and the
month's total) and writes, for one whole year, each station's average riders
a day: (entries + exits) / 2 over the year's days, rounded. Each month's row
must add up to the page's own total, and the year must have all twelve
months, so a change to the page fails here instead of giving wrong numbers.

    python3 -I tools/real-ridership/build_thsr_ridership.py \
        --year 2025 --downloaded 2026-10-20 \
        --output RailwayGameApp/Resources/RealRailways/thsr_ridership.json

Standard library and curl only. See README.md.
"""

import argparse
import calendar
import hashlib
import html
import json
import re
import subprocess
import sys

PAGE = "https://www.thsrc.com.tw/corp/9571df11-8524-4935-8a46-0d5a72e6bc7c"
STATIONS = ["南港", "台北", "板橋", "桃園", "新竹", "苗栗", "台中", "彰化", "雲林", "嘉義", "台南", "左營"]


def table(page, tab, year):
    """The month rows of `year`'s table in the tab `tab` (tab-01 entries,
    tab-02 exits): {month: [12 station counts]}."""
    start = page.find(f'id="{tab}"')
    if start < 0:
        sys.exit(f"the page has no {tab}")
    following = page.find('id="tab-0', start + 10)
    section = page[start:following if following > 0 else len(page)]
    # Every month's row is marked with its year; the tab holds every year's.
    text = html.unescape(re.sub(r"<[^>]+>", " ", section))
    rows = {}
    for month, numbers in re.findall(rf"\b{year}-(\d\d)\s+((?:[\d,]+\s+){{12}}[\d,]+)", text):
        counts = [int(value.replace(",", "")) for value in numbers.split()]
        if int(month) in rows:
            sys.exit(f"{tab} has {year}-{month} twice")
        if sum(counts[:12]) != counts[12]:
            sys.exit(f"{tab} {year}-{month}: the stations add up to {sum(counts[:12])}, the page's total is {counts[12]}")
        rows[int(month)] = counts[:12]
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--year", type=int, required=True, help="a whole year the page covers")
    parser.add_argument("--downloaded", required=True, help="the day the page was read, YYYY-MM-DD")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    raw = subprocess.run(["curl", "-sSfL", "--retry", "3", PAGE], check=True, capture_output=True).stdout
    page = raw.decode("utf-8", "replace")
    header = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", page)))
    if " ".join(STATIONS) not in header:
        sys.exit("the page's columns are no longer the twelve stations in order")
    entries, exits = table(page, "tab-01", args.year), table(page, "tab-02", args.year)
    if sorted(entries) != list(range(1, 13)) or sorted(exits) != list(range(1, 13)):
        sys.exit(f"{args.year} lacks months: entries {sorted(entries)}, exits {sorted(exits)}")

    days = 366 if calendar.isleap(args.year) else 365
    riders = {}
    for index, station in enumerate(STATIONS):
        total = sum(entries[month][index] + exits[month][index] for month in range(1, 13))
        riders[station] = round(total / 2 / days)
    output = {
        "source": {
            "title": "客運運輸情形：各站進出旅客人數",
            "publisher": "台灣高速鐵路股份有限公司",
            "page": PAGE,
            "pageSha256": hashlib.sha256(raw).hexdigest(),
            "downloaded": args.downloaded,
            "licence": "The company's published operating statistics; no open-data licence. Only each station's yearly totals are taken, credited to Taiwan High Speed Rail.",
        },
        "period": {"from": f"{args.year}0101", "to": f"{args.year}1231"},
        "measure": "average riders a day: (entries + exits) / 2 over the year's days",
        "riders": riders,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")
    yearly = {station: sum(entries[month][index] for month in range(1, 13)) for index, station in enumerate(STATIONS)}
    print(f"{args.year}: entries for the year " + ", ".join(f"{station} {count:,}" for station, count in yearly.items()))
    print("a day: " + ", ".join(f"{station} {count:,}" for station, count in riders.items()))


if __name__ == "__main__":
    main()
