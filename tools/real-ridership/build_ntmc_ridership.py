"""New Taipei Metro's ridership by station (ARCHITECTURE decision 298).

Reads New Taipei Metro's monthly statistics ("全系統運量統計", the company
website's 統計資料 page, one spreadsheet a month): for each of its lines,
every station's entries and exits on each day of the month. The company
publishes them with no open-data licence, so only each station's average
(a fact) is taken, credited to the company, as the High Speed Rail's are.

The tool takes twelve consecutive months (`--first`, YYYY-MM), checks that
each station row's days add up to its 總計 column and that a sheet has a
column for every day of its month, and writes, for each line that has all
twelve months, each station's average a day: (entries + exits) / 2 over
the months' days. 人工統計資料 (single-journey and other paper tickets, about
2% of a line) has no station and is left out.

    python3 -I tools/real-ridership/build_ntmc_ridership.py \
        --first 2025-10 --downloaded 2026-10-20 \
        --app RailwayGameApp/Resources/RealRailways \
        --output RailwayGameApp/Resources/RealRailways

writes `ntdlrt_ridership.json` (Danhai Light Rail, codes V), `ntalrt_
ridership.json` (Ankeng Light Rail, K) and `ntmc_circular_ridership.json`
(the Circular Line, Y), keyed by the names of the app's ntdlrt.json,
ntalrt.json and trtc.json; the Sanying Line (LB) once it has twelve
months, into `sanying_ridership.json`. It prints every station it cannot
match and every station of the app with no data.

Only the months published as .ods are read (2025-09 on; earlier months are
PDF or .xlsx). `--files FOLDER` reads FOLDER/YYYY-MM.ods instead of
downloading (the tests use it). Standard library and curl only. See
README.md.
"""

import argparse
import base64
import calendar
import hashlib
import html
import io
import json
import os
import re
import subprocess
import sys
import zipfile
from collections import defaultdict

PAGE = "https://www.ntmetro.com.tw/basic/?node=10145"
DOWNLOAD = "https://www.ntmetro.com.tw/basic/?mode=download&func=basic&code=basic10145&join=10145&path="
PUBLISHER = "新北大眾捷運股份有限公司"
TERMS = (
    "no open-data licence (the company website's 政府網站資料開放宣告); only each station's "
    "average a day, a fact, is taken, credited to the company"
)
# Each line's station-code prefix: the output file, the app's file and its
# lines with the stations of this one.
LINES = {
    "V": ("ntdlrt_ridership.json", "ntdlrt.json", None, "淡海輕軌"),
    "K": ("ntalrt_ridership.json", "ntalrt.json", None, "安坑輕軌"),
    "Y": ("ntmc_circular_ridership.json", "trtc.json", "環狀線", "環狀線"),
    "LB": ("sanying_ridership.json", "sanying.json", None, "三鶯線"),
}


def fetch(url):
    """`url`'s body, through curl: it reads the system's and a proxy's
    certificate settings as they are, which Python's strict default does
    not always accept."""
    result = subprocess.run(["curl", "-sSfL", "--retry", "3", "-m", "120", url], stdout=subprocess.PIPE)
    if result.returncode != 0:
        sys.exit(f"curl failed ({result.returncode}) for {url}")
    return result.stdout


def listed_months():
    """{"YYYY-MM": download URL} of the page's .ods files."""
    page = fetch(PAGE).decode("utf-8", "replace")
    months = {}
    for path in re.findall(r'path=([^"&]+)"', page):
        # The site's own escapes for base64's + / = (filename_stamp.ext).
        encoded = path.replace("(2B", "+").replace("(2F", "/").replace("(3D", "=")
        name, _, extension = encoded.rpartition(".")
        try:
            title = base64.b64decode(name + "=" * (-len(name) % 4)).decode("utf-8")
        except ValueError:
            continue
        match = re.match(r"(\d+)年(\d+)月全系統運量統計", title)
        if match and extension == "ods":
            months[f"{int(match.group(1)) + 1911}-{int(match.group(2)):02d}"] = DOWNLOAD + path
    return months


def rows(sheet):
    """A sheet's rows as lists of cell values, repeated cells expanded."""
    for row in re.findall(r"<table:table-row[^>]*>.*?</table:table-row>", sheet, flags=re.S):
        cells = []
        for cell in re.finditer(r"<table:table-cell([^>]*?)(?:/>|>(.*?)</table:table-cell>)", row, flags=re.S):
            attributes, body = cell.group(1), cell.group(2) or ""
            repeated = re.search(r'number-columns-repeated="(\d+)"', attributes)
            value = re.search(r'office:value="([^"]*)"', attributes)
            text = value.group(1) if value else html.unescape(re.sub(r"<[^>]+>", "", body)).strip()
            # A long run of empty cells is the sheet's unused width.
            cells += [text] * min(int(repeated.group(1)) if repeated else 1, 64)
        while cells and cells[-1] == "":
            cells.pop()
        yield cells


def read(raw, month):
    """One month's spreadsheet: {"entries"|"exits": {code: (name, count)}}."""
    year, number = map(int, month.split("-"))
    days = calendar.monthrange(year, number)[1]
    content = zipfile.ZipFile(io.BytesIO(raw)).read("content.xml").decode("utf-8")
    sheets = dict(re.findall(r'<table:table table:name="([^"]*)"[^>]*>(.*?)</table:table>', content, flags=re.S))
    found = {}
    for kind, word in (("entries", "進站"), ("exits", "出站")):
        names = [name for name in sheets if word in name and "每日" in name]
        if len(names) != 1:
            sys.exit(f"{month}: no single {word} sheet among {list(sheets)}")
        stations = {}
        header = None
        for cells in rows(sheets[names[0]]):
            if cells and cells[0] == "日期":
                header = cells
                if len(header) != days + 2 or header[-1] != "總計":
                    sys.exit(f"{month} {word}: {len(header) - 2} day columns, not {days} and 總計")
                continue
            if not cells or not re.fullmatch(r"[A-Z]+\d+", cells[0]):
                continue
            if header is None:
                sys.exit(f"{month} {word}: a station before the dates")
            code, name = cells[0], cells[1].strip()
            counts = [int(float(value or 0)) for value in cells[2:days + 3]]
            if sum(counts[:days]) != counts[days]:
                sys.exit(f"{month} {word} {code}: the days add up to {sum(counts[:days])}, not {counts[days]}")
            if code in stations:
                sys.exit(f"{month} {word}: {code} twice")
            stations[code] = (name, counts[days])
        found[kind] = stations
    if set(found["entries"]) != set(found["exits"]):
        sys.exit(f"{month}: entries and exits name different stations")
    return found


def key(name):
    """A name as both the data and the app may write it."""
    return name.replace("臺", "台").removesuffix("站")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--first", required=True, help="the first of twelve months, YYYY-MM")
    parser.add_argument("--downloaded", required=True, help="the day the data was read, YYYY-MM-DD")
    parser.add_argument("--app", required=True, help="the app's RealRailways folder (ntdlrt.json, ntalrt.json, trtc.json, sanying.json)")
    parser.add_argument("--output", required=True, help="the folder to write into")
    parser.add_argument("--files", help="a folder of YYYY-MM.ods files to read instead of downloading")
    args = parser.parse_args()

    year, number = map(int, args.first.split("-"))
    wanted = [f"{year + (number - 1 + offset) // 12}-{(number - 1 + offset) % 12 + 1:02d}" for offset in range(12)]
    if args.files:
        sources = {month: os.path.join(args.files, f"{month}.ods") for month in wanted if os.path.exists(os.path.join(args.files, f"{month}.ods"))}
    else:
        sources = listed_months()
    missing = [month for month in wanted if month not in sources]
    if missing:
        sys.exit(f"no .ods for {', '.join(missing)}")

    digests = {}
    sums = defaultdict(lambda: defaultdict(int))  # code → month → entries + exits
    names = {}
    for month in wanted:
        raw = open(sources[month], "rb").read() if args.files else fetch(sources[month])
        digests[month] = hashlib.sha256(raw).hexdigest()
        found = read(raw, month)
        for code, (name, count) in found["entries"].items():
            sums[code][month] += count + found["exits"][code][1]
            names[code] = name
    first_day = f"{wanted[0]}-01"
    last_year, last_month = map(int, wanted[-1].split("-"))
    last_day = f"{wanted[-1]}-{calendar.monthrange(last_year, last_month)[1]:02d}"
    days = sum(calendar.monthrange(*map(int, month.split("-")))[1] for month in wanted)

    for prefix, (output_name, app_name, app_line, title) in LINES.items():
        codes = sorted(code for code in sums if re.fullmatch(prefix + r"\d+", code))
        if not codes:
            print(f"{title}: no stations")
            continue
        partial = [code for code in codes if len(sums[code]) < 12]
        if partial:
            print(f"{title}: skipped, {len(partial)} stations lack months (first month of {codes[0]}: {min(sums[codes[0]])})")
            continue
        lines = json.load(open(os.path.join(args.app, app_name), encoding="utf-8"))["lines"]
        app = {key(station["name"]): station["name"] for line in lines if app_line in (None, line["name"]) for station in line["stations"]}
        riders = {}
        for code in codes:
            name = app.get(key(names[code]), names[code])
            riders[name] = round(sum(sums[code].values()) / 2 / days)
        output = {
            "source": {
                "title": f"新北大眾捷運股份有限公司 營運統計數據：每日全線各站運量統計表（{title}）",
                "publisher": PUBLISHER,
                "page": PAGE,
                "fileSha256": digests,
                "downloaded": args.downloaded,
                "terms": TERMS,
            },
            "period": {"from": first_day, "to": last_day},
            "measure": "average riders a day: (entries + exits) / 2 over the twelve months' days",
            "riders": riders,
        }
        with open(os.path.join(args.output, output_name), "w", encoding="utf-8") as file:
            json.dump(output, file, ensure_ascii=False, indent=1, sort_keys=True)
            file.write("\n")
        print(f"{title}: {len(riders)} stations, {wanted[0]} to {wanted[-1]} ({days} days) → {output_name}")
        print("  names the app does not have: " + (", ".join(sorted(set(riders) - set(app.values()))) or "none"))
        print("  stations of the app with no data: " + (", ".join(sorted(set(app.values()) - set(riders))) or "none"))
        top = sorted(riders.items(), key=lambda item: -item[1])[:5]
        print("  busiest: " + ", ".join(f"{name} {count:,}" for name, count in top))


if __name__ == "__main__":
    main()
