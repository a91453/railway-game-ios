#!/usr/bin/env python3
"""How many visitors the game's sights had in a year, by the official count
(decision 724).

Reads the Tourism Administration's (交通部觀光署) open data "歷年國內主要
觀光遊憩據點遊客人數月別統計" (data.gov.tw dataset 8116, Open Government
Data License, version 1.0): one CSV, one row per official spot and year,
twelve months and the year's total. The CSV has no coordinates, so which
official spot is which sight of the game is the hand-checked table
`official_names.json` beside this file (an entry with more than one official
spot adds them; one with none was looked at and left out on purpose).

Writes `RailwayGameApp/Resources/RealWorld/taiwan_sight_visitors.json`:
for each matched sight, the year's visitors and the twelve months.

Fails, rather than skipping, when the CSV's year has a month missing, when a
name in the table is not in the CSV for that year and county (or is there
twice), when a row's months do not add up to its total, or when a sight's
id is not one of the game's (`taiwan_attractions.json`).

Only the Python standard library. The CSV (some 600 KB) is not committed:

    curl -s https://data.gov.tw/api/v2/rest/dataset/8116 \
      | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["result"]["distribution"][0]["resourceDownloadUrl"])'
    # download that address (its file name is Chinese; quote it) as visitors.csv
    python3 -I tools/tourism-spots/build_official_visitors.py visitors.csv 2026-11-13

The second argument is the day the CSV was downloaded, written into the
output with the CSV's SHA-256.
"""
import csv
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NAMES = os.path.join(HERE, "official_names.json")
ATTRACTIONS = os.path.join(HERE, "taiwan_attractions.json")
OUTPUT = os.path.join(ROOT, "RailwayGameApp", "Resources", "RealWorld", "taiwan_sight_visitors.json")

DATASET = "https://data.gov.tw/dataset/8116"
LICENCE = "https://data.gov.tw/license"
MONTHS = ["%d月" % m for m in range(1, 13)]


def first_line(text):
    """The CSV writes some names and counties with their English on a second
    line ("臺北市立動物園\\nTaipei Zoo"); the Chinese is the first."""
    return text.split("\n")[0].strip()


def count(text, where):
    """A month's count; `None` for a blank cell (a spot closed that month)."""
    text = text.strip().replace(",", "")
    if text == "":
        return None
    if not text.isdigit():
        sys.exit("%s: not a count: %r" % (where, text))
    return int(text)


def read_rows(path, year):
    rows = {}
    with open(path, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row["年別"].strip() != str(year):
                continue
            key = (first_line(row["細分"]), first_line(row["縣市"]))
            where = "%s %s" % key
            months = [count(row[m], "%s %s" % (where, m)) for m in MONTHS]
            total = count(row["合計"], "%s 合計" % where)
            if total is None:
                sys.exit("%s has no total" % where)
            if sum(m or 0 for m in months) != total:
                sys.exit("%s: the months add up to %d, the total is %d" % (where, sum(m or 0 for m in months), total))
            if key in rows:
                sys.exit("%s is in the CSV twice for %d" % (where, year))
            rows[key] = months
    if not rows:
        sys.exit("The CSV has no rows for %d" % year)
    # A year still being counted has its later months blank or zero
    # everywhere; a closed spot is zero all year, which is fine.
    for m in range(12):
        if all(not months[m] for months in rows.values()):
            sys.exit("%d has no counts for month %d yet" % (year, m + 1))
    return rows


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, downloaded = sys.argv[1], sys.argv[2]
    with open(path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    with open(NAMES, encoding="utf-8") as f:
        table = json.load(f)
    with open(ATTRACTIONS, encoding="utf-8") as f:
        game = {a["id"]: a["name"] for a in json.load(f)["attractions"]}
    year = table["year"]
    rows = read_rows(path, year)

    sights, seen = [], set()
    for entry in table["sights"]:
        sid = entry["id"]
        if sid not in game:
            sys.exit("%s is not one of the game's sights" % sid)
        if game[sid] != entry["sight"]:
            sys.exit("%s is %s in the game, not %s" % (sid, game[sid], entry["sight"]))
        if sid in seen:
            sys.exit("%s is in the table twice" % sid)
        seen.add(sid)
        if not entry["official"]:
            if not entry.get("why"):
                sys.exit("%s has no official spot and no reason why" % sid)
            continue
        months = [0] * 12
        for spot in entry["official"]:
            key = (spot["name"], spot["county"])
            if key not in rows:
                sys.exit("%s: %s %s is not in the CSV for %d" % (sid, key[0], key[1], year))
            if None in rows[key]:
                sys.exit("%s: %s has a month with no count in %d" % (sid, key[0], year))
            months = [a + b for a, b in zip(months, rows[key])]
        if sum(months) == 0:
            sys.exit("%s: its official spot had no visitors in %d (closed?); leave it out" % (sid, year))
        sights.append({"id": sid, "visitors": sum(months), "months": months})

    out = {
        "source": "交通部觀光署「歷年國內主要觀光遊憩據點遊客人數月別統計」",
        "dataset": DATASET,
        "licence": "政府資料開放授權條款第 1 版 (Open Government Data License, version 1.0)",
        "licenceURL": LICENCE,
        "csvSHA256": sha,
        "downloaded": downloaded,
        "year": year,
        "sights": sights,
    }
    # One sight a line, so a change shows as that sight's line in a diff.
    head = json.dumps({k: v for k, v in out.items() if k != "sights"}, ensure_ascii=False, indent=1)[:-2]
    lines = ",\n  ".join(json.dumps(s, ensure_ascii=False) for s in sights)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write('%s,\n "sights": [\n  %s\n ]\n}\n' % (head, lines))
    matched = sum(1 for e in table["sights"] if e["official"])
    summed = sum(1 for e in table["sights"] if len(e["official"]) > 1)
    print("%d sights matched (%d adding several spots), %d looked at and left out; %s"
          % (matched, summed, len(table["sights"]) - matched, os.path.relpath(OUTPUT, ROOT)))


if __name__ == "__main__":
    main()
