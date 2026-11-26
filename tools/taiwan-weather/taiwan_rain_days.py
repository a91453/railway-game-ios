#!/usr/bin/env python3
"""Taiwan's rain days of 1 mm or more and thunder days, per weather station
(decision 1013, after decisions 1003 and 1004).

Decision 1003 gave Hong Kong, Kyushu and Finland each month's chance of a
thunderstorm (days with thunder over the month's days) and of rain (days with
1 mm or more over the month's days, less the storm's). Taiwan kept the
project's own table, shared out by the stations' days of 0.1 mm or more,
because the Central Weather Administration (CWA) publishes no days of 1 mm
in its normals and no thunder days at all. This tool makes Taiwan's the same
as the others':

- rain: the CWA open data platform's daily rainfall of the last nine years
  (dataset C-B0025-002, a ZIP; it needs the platform's free key, read from
  the environment variable CWA_API_KEY and never printed), counted per
  station and month: days of 1.0 mm or more over the days with a reading;
- thunder: the CWA's platform has no thunder record of more than a few
  months, so the days with thunder are NOAA's Global Summary of the Day
  (public domain), whose FRSHTT flag is set from the same CWA stations'
  synoptic reports; Taiwan's stations are in it in full up to 1998 only,
  so it takes the years 1981-1998 with a nearly full record (330 days or
  more). Tamsui has no record there and takes Taipei's.

It also reads the CWA's 1991-2020 normals (C-B0027-001) to print each
station's days of 0.1 mm or more beside the counts, as a check.

    CWA_API_KEY=... python3 -I tools/taiwan-weather/taiwan_rain_days.py \
        --out tools/taiwan-weather/taiwan_rain_days.json

The GitHub workflow `.github/workflows/taiwan-weather.yml` runs it with the
repository secret CWA_API_KEY. Nothing in the game reads the key: the JSON
it writes is copied by hand into `Disruptions.weatherStations`.
"""

import argparse
import csv
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

CWA_FILE = "https://opendata.cwa.gov.tw/fileapi/v1/opendataapi/{id}"
CWA_REST = "https://opendata.cwa.gov.tw/api/v1/rest/datastore/{id}"
GSOD = "https://www.ncei.noaa.gov/data/global-summary-of-the-day/access/{year}/{usaf}99999.csv"

# The 19 stations of decision 1004, in its order: the CWA name, and the
# NOAA (ISD) station whose position the game uses and whose GSOD record
# gives the thunder days (None: none there, take `THUNDER_FROM`'s).
STATIONS = [
    ("淡水", "466900"), ("臺北", "466920"), ("基隆", "466940"),
    ("花蓮", "466990"), ("蘇澳", "467060"), ("宜蘭", "467080"),
    ("澎湖", "467350"), ("臺南", "467410"), ("高雄", "467440"),
    ("嘉義", "467480"), ("臺中", "467490"), ("阿里山", "467530"),
    ("大武", "467540"), ("新竹", "467560"), ("恆春", "467590"),
    ("成功", "467610"), ("日月潭", "467650"), ("臺東", "467660"),
    ("梧棲", "467770"),
]
THUNDER_FROM = {"淡水": "臺北"}
NO_GSOD = {"淡水"}
THUNDER_YEARS = range(1981, 1999)
FULL_YEAR = 330
# A month's days in the game's 30-day months are not used: the chance is a
# share of the real month, February 28.25 days (decision 1003).
MONTH_DAYS = [31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


def get(url, headers=None, tries=4):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers=headers or {"User-Agent": "railway-game-tools"})
            with urllib.request.urlopen(req, timeout=180) as resp:
                return resp.read()
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return None
            if err.code in (401, 403) or attempt == tries - 1:
                body = err.read()[:200].decode("utf-8", "replace")
                raise RuntimeError(f"HTTP {err.code}: {body!r}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as err:
            if attempt == tries - 1:
                raise RuntimeError(f"network: {type(err).__name__}") from None
        time.sleep(5 * (attempt + 1))
    return None


def cwa(dataset, key, params, rest=False):
    """A CWA dataset, with the key in the query (as the platform asks); the
    URL is never printed."""
    query = urllib.parse.urlencode({"Authorization": key, **params})
    base = (CWA_REST if rest else CWA_FILE).format(id=dataset)
    # The key goes in the query only: the file API redirects to a storage
    # bucket that refuses any Authorization header.
    data = get(f"{base}?{query}")
    if data is None:
        raise RuntimeError(f"{dataset}: not found")
    return data


def describe(name, blob):
    print(f"  {name}: {len(blob)} bytes, starts {blob[:300].decode('utf-8', 'replace')!r}")


def reading(value):
    """A day's rainfall in mm, 0 for a trace, None for no reading."""
    if value is None:
        return None
    text = str(value).strip()
    if text in ("", "X", "x", "-", "/", "...", "None", "null"):
        return None
    if text.upper() == "T":
        return 0.0
    try:
        number = float(text)
    except ValueError:
        return None
    return number if number >= 0 else None


def daily_from_json(doc):
    """{station name: {(year, month, day): mm}} from the CWA's JSON (the
    shape of C-B0025-001)."""
    out = {}
    root = doc.get("cwaopendata", doc)
    resources = root.get("resources", root)
    resource = resources.get("resource", resources)
    if isinstance(resource, list):
        resource = resource[0]
    locations = resource["data"]["surfaceObs"]["location"]
    for loc in locations:
        name = loc["station"]["StationName"]
        times = loc.get("stationObsTimes", {}).get("stationObsTime", [])
        if isinstance(times, dict):
            times = [times]
        days = out.setdefault(name, {})
        for t in times:
            y, m, d = (int(x) for x in t["Date"][:10].split("-"))
            mm = reading(t.get("weatherElements", {}).get("Precipitation"))
            if mm is not None:
                days[(y, m, d)] = mm
    return out


def daily_from_csv(text):
    """The same from the CSV the metadata describes: a row per station,
    year and day of the month, a column per month."""
    out = {}
    rows = list(csv.reader(io.StringIO(text)))
    header = None
    for i, row in enumerate(rows):
        cells = [c.strip().lstrip("﻿") for c in row]
        if "1月" in cells and any("年" in c for c in cells):
            header = cells
            start = i + 1
            break
    if header is None:
        return out
    col = {name: header.index(name) for name in header}
    name_col = next(i for i, c in enumerate(header) if "中文名稱" in c and "備註" not in c)
    year_col = next(i for i, c in enumerate(header) if "年" in c and "月" not in c)
    day_col = next(i for i, c in enumerate(header) if c in ("日期", "日"))
    for row in rows[start:]:
        if len(row) <= max(col[f"{m}月"] for m in range(1, 13)):
            continue
        try:
            name = row[name_col].strip()
            year = int(row[year_col])
            day = int(row[day_col])
        except ValueError:
            continue
        days = out.setdefault(name, {})
        for m in range(1, 13):
            mm = reading(row[col[f"{m}月"]])
            if mm is not None:
                days[(year, m, day)] = mm
    return out


def cwa_daily(key):
    blob = cwa("C-B0025-002", key, {"downloadType": "WEB", "format": "ZIP"})
    print("C-B0025-002 (daily rainfall, last nine years):")
    if not zipfile.is_zipfile(io.BytesIO(blob)):
        describe("not a ZIP", blob)
        raise RuntimeError("C-B0025-002 is not a ZIP")
    daily = {}
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        names = zf.namelist()
        print(f"  {len(names)} files: {names[:12]}{' ...' if len(names) > 12 else ''}")
        described = False
        for name in names:
            if name.endswith("/"):
                continue
            raw = zf.read(name)
            for codec in ("utf-8-sig", "big5", "cp950"):
                try:
                    text = raw.decode(codec)
                    break
                except UnicodeDecodeError:
                    continue
            else:
                continue
            got = {}
            if text.lstrip().startswith(("{", "[")):
                try:
                    got = daily_from_json(json.loads(text))
                except (KeyError, TypeError, ValueError, IndexError):
                    got = {}
            elif name.lower().endswith(".csv") or "," in text[:2000]:
                got = daily_from_csv(text)
            if not got and not described:
                describe(name, raw)
                described = True
            for station, days in got.items():
                daily.setdefault(station, {}).update(days)
    if not daily:
        raise RuntimeError("C-B0025-002: no daily rainfall read")
    return daily


def cwa_normals(key):
    """{station name: [days of 0.1 mm or more, by month]} of 1991-2020."""
    blob = cwa("C-B0027-001", key, {"format": "JSON", "weatherElement": "Precipitation"}, rest=True)
    doc = json.loads(blob)
    root = doc.get("records", doc.get("cwaopendata", doc))
    try:
        locations = root["data"]["surfaceObs"]["location"]
    except (KeyError, TypeError):
        resources = root.get("resources", {})
        locations = resources.get("resource", {}).get("data", {}).get("surfaceObs", {}).get("location", [])
    out = {}
    for loc in locations:
        name = loc["station"]["StationName"]
        months = loc["stationObsStatistics"]["Precipitation"]["monthly"]
        out[name] = [None] * 12
        for m in months:
            value = m.get("GE01Days")
            if value not in (None, "", "X"):
                out[name][int(m["Month"]) - 1] = float(value)
    return out


def thunder_days(usaf):
    """Days with thunder by month (scaled to the month's days), the years
    used."""
    thunder = [0] * 12
    seen = [0] * 12
    years = []
    for year in THUNDER_YEARS:
        blob = get(GSOD.format(year=year, usaf=usaf))
        if not blob:
            continue
        rows = list(csv.DictReader(io.StringIO(blob.decode("utf-8", "replace"))))
        if len(rows) < FULL_YEAR:
            continue
        years.append(year)
        for row in rows:
            month = int(row["DATE"][5:7]) - 1
            seen[month] += 1
            if row["FRSHTT"].strip().zfill(6)[4] == "1":
                thunder[month] += 1
    return [thunder[m] / seen[m] * MONTH_DAYS[m] if seen[m] else 0.0 for m in range(12)], years


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    key = os.environ.get("CWA_API_KEY", "").strip()
    if not key:
        sys.exit("CWA_API_KEY is not set")

    # Whether this machine reaches the platform at all: a wrong key is
    # 401 there, a refused machine something else.
    try:
        get(CWA_REST.format(id="C-B0027-001") + "?Authorization=CWA-00000000-0000-0000-0000-000000000000", tries=1)
    except RuntimeError as err:
        print(f"probe with a made-up key: {err}")
    daily = cwa_daily(key)
    print(f"  stations read: {len(daily)}")
    try:
        normals = cwa_normals(key)
    except (RuntimeError, KeyError, TypeError, ValueError) as err:
        print(f"C-B0027-001 not read ({err}); the check column is left empty")
        normals = {}

    thunder = {}
    for name, usaf in STATIONS:
        if name in NO_GSOD:
            continue
        thunder[name] = thunder_days(usaf)
    for name, source in THUNDER_FROM.items():
        thunder[name] = thunder[source]

    stations = []
    for name, usaf in STATIONS:
        days = daily.get(name)
        if not days:
            sys.exit(f"{name}: not in C-B0025-002 (stations: {sorted(daily)})")
        wet = [0] * 12
        seen = [0] * 12
        light = [0] * 12
        years = sorted({y for (y, _, _) in days})
        for (y, m, d), mm in days.items():
            seen[m - 1] += 1
            if mm >= 1.0:
                wet[m - 1] += 1
            if mm >= 0.1:
                light[m - 1] += 1
        rain1 = [wet[m] / seen[m] * MONTH_DAYS[m] if seen[m] else 0.0 for m in range(12)]
        rain01 = [light[m] / seen[m] * MONTH_DAYS[m] if seen[m] else 0.0 for m in range(12)]
        storm_days, storm_years = thunder[name]
        chances = []
        for m in range(12):
            storm = round(storm_days[m] / MONTH_DAYS[m] * 1000)
            rain = max(0, round(rain1[m] / MONTH_DAYS[m] * 1000) - storm)
            chances.append([rain, storm])
        stations.append({
            "name": name,
            "noaa": usaf,
            "rain_years": [years[0], years[-1]],
            "rain_days_1mm": [round(x, 1) for x in rain1],
            "rain_days_0_1mm": [round(x, 1) for x in rain01],
            "normal_days_0_1mm_1991_2020": normals.get(name),
            "thunder_from": THUNDER_FROM.get(name, name),
            "thunder_years": [storm_years[0], storm_years[-1], len(storm_years)] if storm_years else None,
            "thunder_days": [round(x, 1) for x in storm_days],
            "chances": chances,
        })

    result = {
        "decision": 1013,
        "rain": "CWA open data C-B0025-002, days of 1.0 mm or more over days with a reading",
        "thunder": "NOAA GSOD FRSHTT thunder flag, 1981-1998 years with 330 days or more",
        "stations": stations,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
        f.write("\n")

    print("\n| 站 | 年 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 年計 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for s in stations:
        for label, row in (("≥1 mm", s["rain_days_1mm"]), ("≥0.1", s["rain_days_0_1mm"]),
                           ("平年≥0.1", s["normal_days_0_1mm_1991_2020"]), ("雷", s["thunder_days"])):
            if row is None:
                continue
            cells = " | ".join("" if x is None else f"{x:.1f}" for x in row)
            total = sum(x for x in row if x is not None)
            print(f"| {s['name']} | {label} | {cells} | {total:.1f} |")
    print("\nSwift (Disruptions.weatherStations, months):")
    for s in stations:
        print(f"  {s['name']}: " + ", ".join(f"({r}, {t})" for r, t in s["chances"]))
    print("\nJSON:")
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
