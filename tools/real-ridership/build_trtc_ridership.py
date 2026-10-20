"""Taipei Metro's ridership by station (ARCHITECTURE decision 298).

Reads Taipei Metro's open data "臺北捷運各站分時進出量統計" (data.gov.tw
dataset 128506, published on data.taipei): an index of one CSV a month, each
every day's hourly trips from each station to each other, some 300 MB. The
months of one whole year are streamed, never saved, and each station's
entries (trips from it) and exits (trips to it) summed; the output is each
station's average a day, (entries + exits) / 2 over the days of the year,
keyed by the station's name as the data writes it. The tool prints every
name the app's `trtc.json` does not have and every station of it with no
data, so a new or renamed station is seen, not dropped.

    python3 -I tools/real-ridership/build_trtc_ridership.py \
        --year 2025 --downloaded 2026-10-20 \
        --stations RailwayGameApp/Resources/RealRailways/trtc.json \
        --output RailwayGameApp/Resources/RealRailways/trtc_ridership.json

Standard library and curl only. See README.md.
"""

import argparse
import csv
import hashlib
import io
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

DATASET = "https://data.gov.tw/dataset/128506"
INDEX = "https://data.taipei/api/dataset/63f31c7e-7fc3-418b-bd82-b95158755b4d/resource/eb481f58-1238-4cff-8caa-fa7bb20cb4f4/download"
LICENCE = "Open Government Data License, version 1.0 (https://data.gov.tw/license)"


class open_url:
    """`url`'s body, streamed through curl: it reads the system's and a
    proxy's certificate settings as they are, which Python's strict default
    does not always accept."""

    def __init__(self, url):
        self.url = url

    def __enter__(self):
        self.process = subprocess.Popen(["curl", "-sSfL", "--retry", "3", self.url], stdout=subprocess.PIPE)
        return self.process.stdout

    def __exit__(self, kind, *_):
        self.process.stdout.close()
        # A reader that stopped early makes curl fail too: its own error is
        # the one to show.
        if self.process.wait() != 0 and kind is None:
            sys.exit(f"curl failed ({self.process.returncode}) for {self.url}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--year", type=int, required=True, help="a whole year the data covers")
    parser.add_argument("--downloaded", required=True, help="the day the data was read, YYYY-MM-DD")
    parser.add_argument("--stations", required=True, help="the app's trtc.json")
    parser.add_argument("--output", required=True)
    parser.add_argument("--cache", help="a folder to keep each month's sums in, so a second run reads only new months")
    args = parser.parse_args()

    with open_url(INDEX) as response:
        index = list(csv.DictReader(io.StringIO(response.read().decode("utf-8-sig"))))
    months = sorted((int(row["月"]), row["URL"]) for row in index if int(row["西元年"]) == args.year)
    if [month for month, _ in months] != list(range(1, 13)):
        sys.exit(f"the index has months {[month for month, _ in months]} of {args.year}, not all twelve")

    entries, exits = defaultdict(int), defaultdict(int)
    days = set()
    digests = {}
    for month, url in months:
        sums = month_sums(args.year, month, url, args.cache)
        for name, count in sums["entries"].items():
            entries[name] += count
        for name, count in sums["exits"].items():
            exits[name] += count
        days.update(sums["days"])
        digests[f"{args.year}-{month:02}"] = sums["sha256"]
        print(f"{args.year}-{month:02}: {sums['rows']:,} rows", flush=True)
    if len(days) < 365:
        sys.exit(f"{args.year} has data for {len(days)} days only: not a whole year")

    lines = json.load(open(args.stations, encoding="utf-8"))["lines"]
    known = {station["name"] for line in lines for station in line["stations"]}

    # Where two lines' gates are counted apart the data names them by line
    # ("BL板橋" and "Y板橋", "G大坪林" beside "大坪林"), and one name ends
    # with 站 ("大橋頭站"): each adds to the station the app knows.
    def app_name(name):
        if name in known:
            return name
        bare = re.sub(r"^(BL|BR|G|O|R|Y)(?=\D)", "", name).removesuffix("站")
        return bare if bare in known else name
    riders = defaultdict(int)
    for name in set(entries) | set(exits):
        riders[app_name(name)] += entries[name] + exits[name]
    names = sorted(riders)
    average = {name: round(riders[name] / 2 / len(days)) for name in names}
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
        "period": {"from": min(days), "to": max(days)},
        "measure": "average riders a day: (entries + exits) / 2 over the days of the year",
        "riders": average,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
        file.write("\n")

    print(f"{len(average)} stations, {min(days)} to {max(days)}")
    print("names the app does not have: " + (", ".join(sorted(set(names) - known)) or "none"))
    print("stations of the app with no data: " + (", ".join(sorted(known - set(names))) or "none"))
    top = sorted(average.items(), key=lambda item: -item[1])[:5]
    print("busiest: " + ", ".join(f"{name} {count:,}" for name, count in top))


def month_sums(year, month, url, cache):
    """Each station's entries and exits in one month's file, the days it
    covers, its row count and SHA-256; kept in `cache` when given.

    The metro runs all night on New Year's Eve: December's file goes on
    into the small hours of 1 January (before 06:00), trips of the 31st's
    service day, counted with it and adding no day.
    """
    path = os.path.join(cache, f"{year}-{month:02}.json") if cache else None
    if path and os.path.exists(path):
        return json.load(open(path, encoding="utf-8"))
    following = f"{year + 1}-01-01" if month == 12 else f"{year}-{month + 1:02}-01"
    entries, exits = defaultdict(int), defaultdict(int)
    days = set()
    digest = hashlib.sha256()
    rows = 0
    with open_url(url) as response:
        # Line by line, so a month of some 300 MB is never held whole.
        text = io.TextIOWrapper(io.BufferedReader(_Hashing(response, digest), 1 << 20), encoding="utf-8-sig", newline="")
        reader = csv.reader(text)
        header = next(reader)
        if header != ["日期", "時段", "進站", "出站", "人次"]:
            sys.exit(f"{year}-{month:02}: unexpected header {header}")
        for date, hour, origin, destination, trips in reader:
            if date.startswith(f"{year}-{month:02}-"):
                days.add(date)
            elif not (date == following and int(hour) < 6):
                sys.exit(f"{year}-{month:02}: a row of another day: {date} {hour}:00")
            count = int(trips)
            entries[origin] += count
            exits[destination] += count
            rows += 1
    sums = {"entries": entries, "exits": exits, "days": sorted(days), "rows": rows, "sha256": digest.hexdigest()}
    if path:
        os.makedirs(cache, exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            json.dump(sums, file, ensure_ascii=False)
    return sums


class _Hashing(io.RawIOBase):
    """A response read through, its bytes added to a digest."""

    def __init__(self, response, digest):
        self.response, self.digest = response, digest

    def readable(self):
        return True

    def readinto(self, buffer):
        data = self.response.read(len(buffer))
        self.digest.update(data)
        buffer[:len(data)] = data
        return len(data)


if __name__ == "__main__":
    main()
