"""Taoyuan Airport MRT's ridership by station (ARCHITECTURE decision 298).

Reads Taoyuan Metro's monthly "各站旅運量統計" (the company website's 統計資料
page, one PDF a month): each station's entries and exits in the month, and
the line's total. The same company's open data (data.gov.tw dataset 164957)
lives on opendata.tycg.gov.tw, which the cloud container cannot reach
("Request Rejected"); the website's PDFs it can. They are published with no
open-data licence named, so only each station's average (a fact) is taken,
credited to the company, as the High Speed Rail's are.

The tool takes the twelve months of `--year`, checks that each month's
stations add up to its 總計 row, and writes each station's average a day:
(entries + exits) / 2 over the year's days. 團體票 and 其他 (group tickets,
bicycle and paper tickets, under 0.1%) have no station and are left out.
It prints every station it cannot match and every station of the app with
no data.

    python3 -I tools/real-ridership/build_tymc_ridership.py --year 2025 --downloaded 2026-10-20 \
        --stations RailwayGameApp/Resources/RealRailways/tymc.json \
        --output RailwayGameApp/Resources/RealRailways/tymc_ridership.json

The PDFs' text is read with poppler's `pdftotext -layout` (installed in the
cloud container; the tool runs it, it is not part of the project).
`--files FOLDER` reads FOLDER/YYYY-MM.txt, text already extracted, instead
of downloading (the tests use it). Standard library, curl and pdftotext.
See README.md.
"""

import argparse
import calendar
import hashlib
import json
import os
import re
import subprocess
import sys

PAGE = "https://www.tymetro.com.tw/tymetro-new/tw/_pages/about/statistics.html"
FILES = "https://www.tymetro.com.tw/tymetro-new/upload/file/"
PUBLISHER = "桃園大眾捷運股份有限公司"
TERMS = (
    "no open-data licence named on the company website; only each station's average a day, a fact, "
    "is taken, credited to the company (the same company's open data, data.gov.tw 164957, is out of "
    "the cloud container's reach)"
)


def run(command, data=None):
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE)
    if result.returncode != 0:
        sys.exit(f"{command[0]} failed ({result.returncode}) for {command[-2] if data else command[-1]}")
    return result.stdout


def fetch(url):
    """`url`'s body, through curl: it reads the system's and a proxy's
    certificate settings as they are, which Python's strict default does
    not always accept."""
    return run(["curl", "-sSfL", "--retry", "3", "-m", "120", url])


def listed_months(year):
    """{month: PDF URL} of the year's "各站旅運量統計" on the statistics pages."""
    months = {}
    first = fetch(PAGE).decode("utf-8", "replace")
    pages = int((re.search(r'data-total="(\d+)"', first) or [0, 1])[1])
    for page in range(1, pages + 1):
        body = first if page == 1 else fetch(f"{PAGE}?page={page}").decode("utf-8", "replace")
        for path, title in re.findall(r"href='[./]*upload/file/([^']+\.pdf)' download title=\"([^\"]+)\"", body):
            match = re.match(r"(\d+)年(\d+)月各站旅運量統計", title)
            if match and int(match.group(1)) + 1911 == year:
                months.setdefault(int(match.group(2)), FILES + path)
    return months


def number(text):
    return int(text.replace(",", ""))


def read(text, year, month):
    """One month's text: {station as written: entries + exits}."""
    match = re.search(r"營運月份：\s*(\d+)年(\d+)月", text)
    if not match or (int(match.group(1)) + 1911, int(match.group(2))) != (year, month):
        sys.exit(f"{year}-{month:02d}: the file is of {match.group(0) if match else 'no month'}")
    stations = {}
    entries = exits = 0
    total = None
    for line in text.splitlines():
        row = re.fullmatch(r"\s*(A\d+[a-z]?)\s*(\S+?)\s+([\d,]+)\s+([\d,]+)\s*", line)
        if row:
            name = row.group(2)
            if name in stations:
                sys.exit(f"{year}-{month:02d}: {name} twice")
            stations[name] = number(row.group(3)) + number(row.group(4))
            entries += number(row.group(3))
            exits += number(row.group(4))
            continue
        row = re.fullmatch(r"\s*總計\s+([\d,]+)\s+([\d,]+)\s*", line)
        if row:
            total = (number(row.group(1)), number(row.group(2)))
    if total != (entries, exits):
        sys.exit(f"{year}-{month:02d}: the stations add up to {(entries, exits)}, the total row is {total}")
    return stations


def key(name):
    """A name as both the data and the app may write it."""
    return name.replace("臺", "台").removesuffix("站")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--downloaded", required=True, help="the day the data was read, YYYY-MM-DD")
    parser.add_argument("--stations", required=True, help="the app's tymc.json")
    parser.add_argument("--output", required=True)
    parser.add_argument("--files", help="a folder of YYYY-MM.txt (pdftotext -layout) files to read instead of downloading")
    args = parser.parse_args()

    if args.files:
        sources = {month: os.path.join(args.files, f"{args.year}-{month:02d}.txt") for month in range(1, 13)}
        sources = {month: path for month, path in sources.items() if os.path.exists(path)}
    else:
        sources = listed_months(args.year)
    if sorted(sources) != list(range(1, 13)):
        sys.exit(f"{args.year} has months {sorted(sources)}, not all twelve")

    digests = {}
    totals = {}
    for month in range(1, 13):
        if args.files:
            raw = open(sources[month], "rb").read()
            text = raw.decode("utf-8")
        else:
            raw = fetch(sources[month])
            text = run(["pdftotext", "-layout", "-", "-"], data=raw).decode("utf-8")
        digests[f"{args.year}-{month:02d}"] = hashlib.sha256(raw).hexdigest()
        stations = read(text, args.year, month)
        if totals and set(stations) != set(totals):
            print(f"note: {args.year}-{month:02d} names different stations: {sorted(set(stations) ^ set(totals))}")
        for name, count in stations.items():
            totals[name] = totals.get(name, 0) + count

    lines = json.load(open(args.stations, encoding="utf-8"))["lines"]
    app = {key(station["name"]): station["name"] for line in lines for station in line["stations"]}
    days = 366 if calendar.isleap(args.year) else 365
    riders = {app.get(key(name), name): round(count / 2 / days) for name, count in sorted(totals.items())}
    output = {
        "source": {
            "title": "桃園大眾捷運股份有限公司 各站旅運量統計",
            "publisher": PUBLISHER,
            "page": PAGE,
            "fileSha256": digests,
            "downloaded": args.downloaded,
            "terms": TERMS,
        },
        "period": {"from": f"{args.year}-01-01", "to": f"{args.year}-12-31"},
        "measure": "average riders a day: (entries + exits) / 2 over the days of the year",
        "riders": riders,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")
    print(f"{len(riders)} stations, {args.year}")
    print("names the app does not have: " + (", ".join(sorted(set(riders) - set(app.values()))) or "none"))
    print("stations of the app with no data: " + (", ".join(sorted(set(app.values()) - set(riders))) or "none"))
    top = sorted(riders.items(), key=lambda item: -item[1])[:5]
    print("busiest: " + ", ".join(f"{name} {count:,}" for name, count in top))


if __name__ == "__main__":
    main()
