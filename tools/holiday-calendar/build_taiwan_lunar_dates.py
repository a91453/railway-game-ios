#!/usr/bin/env python3
"""The Gregorian dates of Taiwan's lunar holidays, for the holiday calendar
(ARCHITECTURE decision 209).

Reads the Hong Kong Observatory's Gregorian-lunar conversion tables (one
UTF-8 text file a year, `T<year>c.txt`, the lunar calendar reckoned at
UTC+8 as Taiwan's is) and prints, for each year, the Gregorian month and
day (as MMDD) of the Lunar New Year (正月初一), Qingming (the solar term),
the Dragon Boat Festival (五月初五) and the Mid-Autumn Festival (八月十五),
as the Swift rows of `TaiwanHolidayRules.lunarDates`.

    for y in $(seq 2024 2100); do
      curl -sSO "https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T${y}c.txt"
    done
    python3 -I tools/holiday-calendar/build_taiwan_lunar_dates.py <folder> 2025 2100

The table of the year before the first is needed too: a year's file
starts in the eleventh lunar month, whose name is printed only on its first
day.
"""
import os
import re
import sys

LINE = re.compile(r"^(\d{4})年(\d{1,2})月(\d{1,2})日\s+(\S+)\s+星期\S\s*(\S*)\s*$")
MONTHS = {"正": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "十一": 11, "十二": 12}
DIGITS = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def lunar_day(text):
    """初一..初十, 十一..十九, 二十, 廿一..廿九 (or 二十一..), 三十."""
    if text.startswith("初"):
        return 10 if text[1:] == "十" else DIGITS[text[1:]]
    if text == "二十":
        return 20
    if text == "三十":
        return 30
    if text.startswith("廿"):
        return 20 + DIGITS[text[1:]]
    if text.startswith("二十"):
        return 20 + DIGITS[text[2:]]
    if text.startswith("十"):
        return 10 + DIGITS[text[1:]]
    raise ValueError(text)


def main():
    folder, first, last = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    found = {}
    month = None  # (number, leap)
    day = None
    for year in range(first - 1, last + 1):
        with open(os.path.join(folder, f"T{year}c.txt"), encoding="utf-8-sig") as handle:
            for raw in handle:
                match = LINE.match(raw.strip())
                if not match:
                    continue
                gy, gm, gd, lunar, term = int(match[1]), int(match[2]), int(match[3]), match[4], match[5]
                if lunar.endswith("月"):
                    leap = lunar.startswith("閏")
                    month = (MONTHS[lunar[1:-1] if leap else lunar[:-1]], leap)
                    day = 1
                elif month is not None:
                    day = lunar_day(lunar)
                mmdd = gm * 100 + gd
                row = found.setdefault(gy, {})
                if term == "清明":
                    row.setdefault("qingming", []).append(mmdd)
                if month is None or month[1]:
                    continue
                for key, (lm, ld) in {"springFestival": (1, 1), "dragonBoat": (5, 5), "midAutumn": (8, 15)}.items():
                    if (month[0], day) == (lm, ld):
                        row.setdefault(key, []).append(mmdd)
    print(f"        // {first} to {last}: Lunar New Year, Qingming, Dragon Boat, Mid-Autumn (MMDD).")
    for year in range(first, last + 1):
        row = found[year]
        values = []
        for key in ("springFestival", "qingming", "dragonBoat", "midAutumn"):
            dates = row.get(key, [])
            if len(dates) != 1:
                raise SystemExit(f"{year} {key}: {dates}")
            values.append(dates[0])
        print(f"        [{', '.join(str(v) for v in values)}], // {year}")


if __name__ == "__main__":
    main()
