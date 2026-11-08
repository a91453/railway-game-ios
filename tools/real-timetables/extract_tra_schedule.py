#!/usr/bin/env python3
"""Pack Taiwan Railway's every train of one week, for the real lines of the
real-world map (ARCHITECTURE decision 532), from the `Railway/` site's TRA
timetable.

    python3 -I tools/real-timetables/extract_tra_schedule.py \\
        <reference>/Railway/taiwan-rail-reference-clean/source/data/tra_schedule_dense.json \\
        RailwayGameApp/Resources/RealRailways/tra.json \\
        RailwayGameApp/Resources/RealRailways/tra-schedule.json

The input is a `tra_schedule_dense.json` in the reference site's shape:
first the newer snapshot's `data/tra_schedule_dense.json` (14 days from
2026-10-16), now `rebuild_tra_schedule.py`'s from TRA's own files fetched
on 2026-11-08 (decision 650); TRA's open data, ods.railway.gov.tw, under
the Open Government Data License, version 1. Every train has its number,
kind (`typeName`), model (`carName`), its stops' arrival and departure
seconds of the service day (past 86,400 after midnight), the stations it
passes timed between its calls along the line, and which dates it runs.

The game runs a week, so the output keeps one real day of each weekday,
the first that is not a public holiday (`PUBLIC_HOLIDAYS`), and the first
public holiday on a weekday (in 2026-11-08's, Friday 12-25, fetched beside
the fortnight), and only the trains of those eight days. Each train
keeps only what the game draws and lists:

    {"n": number, "t": kind index, "k": model index, "d": day bits,
     "s": [station, arrival, dwell, station, gap, dwell, ...]}

`d` has bit w for weekday w of `days` (Sunday first) and bit 7 for the
holiday. `s` is three numbers a stop: its station's index into `stations`
(negative, `-(index + 1)`, for one it passes without stopping), then the
first stop's arrival second and every later one's seconds since the stop
before it left, then how long it stands. The stations are named as the
game's `tra.json` names them (the timetable's 左營 and 新城 are its
左營(舊城) and 新城 (太魯閣)); a stop at a station `tra.json` does not have
(臺北-環島, a tour train's) is left out.
"""
import json
import sys

# The site's `TW_DAYTYPE`, the game's `RealTimetables.publicHolidays`:
# Taiwan's public holidays of 2026 and 2027.
PUBLIC_HOLIDAYS = {
    "2026-01-01", "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19",
    "2026-02-20", "2026-02-27", "2026-02-28", "2026-04-03", "2026-04-04", "2026-04-05",
    "2026-04-06", "2026-05-01", "2026-06-19", "2026-09-25", "2026-09-28", "2026-10-09",
    "2026-10-10", "2026-10-25", "2026-10-26", "2026-12-25",
    "2027-01-01", "2027-02-04", "2027-02-05", "2027-02-06", "2027-02-07", "2027-02-08",
    "2027-02-09", "2027-02-10", "2027-02-28", "2027-03-01", "2027-04-04", "2027-04-05",
    "2027-04-06", "2027-04-30", "2027-05-01", "2027-06-09", "2027-09-15", "2027-09-28",
    "2027-10-10", "2027-10-11", "2027-10-25", "2027-12-24", "2027-12-25", "2027-12-31",
}

# The timetable's names that `tra.json` spells otherwise.
RENAMED = {"左營": "左營(舊城)", "新城": "新城 (太魯閣)"}


def pick_days(dates, holidays):
    """The first date of each weekday (Sunday first) that is not a holiday,
    and the first holiday on a weekday (Monday to Friday)."""
    import datetime

    days = [None] * 7
    holiday = None
    for date in sorted(dates):
        weekday = (datetime.date.fromisoformat(date).weekday() + 1) % 7  # Sunday 0
        if date in holidays:
            if holiday is None and 1 <= weekday <= 5:
                holiday = date
        elif days[weekday] is None:
            days[weekday] = date
    if None in days or holiday is None:
        sys.exit(f"the dates do not give a whole week and a weekday holiday: {days}, {holiday}")
    return days, holiday


def extract(data, game_stations, holidays):
    days, holiday = pick_days(data["dates"], holidays)
    bits = {}
    for bit, date in enumerate(days + [holiday]):
        for index in data["dates"][date]:
            bits[index] = bits.get(index, 0) | (1 << bit)
    kinds, models, stations = [], [], []

    def index_of(table, value):
        if value not in table:
            table.append(value)
        return table.index(value)

    trains, dropped = [], {}
    for index in sorted(bits, key=lambda i: (data["trains"][i]["stops"][0]["depSec"], data["trains"][i]["train"])):
        train = data["trains"][index]
        stops = []
        for stop in train["stops"]:
            name = RENAMED.get(stop["name"], stop["name"])
            if name not in game_stations:
                dropped[name] = dropped.get(name, 0) + 1
                continue
            stops.append((name, stop["arrSec"], stop["depSec"], bool(stop.get("stop"))))
        if len(stops) < 2:
            continue
        flat = []
        left = None
        for name, arrival, departure, stopping in stops:
            station = index_of(stations, name)
            flat += [station if stopping else -(station + 1), arrival if left is None else arrival - left, departure - arrival]
            left = departure
        if any(v < 0 for v in flat[1::3]) or any(v < 0 for v in flat[2::3]):
            sys.exit(f"train {train['train']}: its times run backwards")
        trains.append({
            "n": train["train"],
            "t": index_of(kinds, train["typeName"]),
            "k": index_of(models, train["carName"]),
            "d": bits[index],
            "s": flat,
        })
    return days, holiday, kinds, models, stations, trains, dropped


def main():
    source, game_tra, target = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(source, encoding="utf-8") as f:
        data = json.load(f)
    with open(game_tra, encoding="utf-8") as f:
        game = json.load(f)
    game_stations = {s["name"] for line in game["lines"] for s in line["stations"]}
    holidays = PUBLIC_HOLIDAYS
    days, holiday, kinds, models, stations, trains, dropped = extract(data, game_stations, holidays)
    first, last = data["dateRange"]
    notes = data.get("source_notes", "")
    if notes.startswith("經 TDX"):
        # tools/real-timetables/rebuild_tra_schedule.py from TDX (decision 650).
        origin = (
            "臺鐵時刻表（資料權責臺鐵，經交通部 TDX 的 Rail/TRA/DailyTrainTimetable 逐日檔，"
            "政府資料開放授權條款第 1 版），由 tools/real-timetables/rebuild_tra_schedule.py "
            "照參考庫 Railway/taiwan-rail-reference-clean 的 fetch_tra_schedule.py、densify_schedule.py "
            f"排成 tra_schedule_dense.json（{first} 到 {last}，有停駛的日子不收）"
        )
    elif "rebuild_tra_schedule.py" in notes.split(" | ")[0]:
        # The same from ODS's own files (decision 650).
        origin = (
            "臺鐵開放資料（ods.railway.gov.tw，政府資料開放授權條款第 1 版，"
            f"{data.get('date', first)} 由 .github/workflows/tra-ods-fetch.yml 抓下），"
            "由 tools/real-timetables/rebuild_tra_schedule.py 照參考庫 Railway/taiwan-rail-reference-clean 的 "
            f"fetch_tra_schedule.py、densify_schedule.py 排成 tra_schedule_dense.json（{first} 到 {last}，有停駛的日子不收）"
        )
    else:
        origin = (
            "臺鐵開放資料（ods.railway.gov.tw，政府資料開放授權條款第 1 版），經參考庫 "
            "Railway/taiwan-rail-reference-clean 的 data/tra_schedule_dense.json"
            f"（{first} 到 {last}）"
        )
    out = {
        "system": "tra",
        "source_notes": (
            origin + "；每個星期幾取一個不是假日的日子、再取一個平日的假日，"
            "只收這八天開的列車。通過站的時刻照網站的沿線內插。"
            "由 tools/real-timetables/extract_tra_schedule.py 產生。"
        ),
        "days": days,
        "holiday": holiday,
        "kinds": kinds,
        "models": models,
        "stations": stations,
        "trains": trains,
    }
    with open(target, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    stops = sum(len(t["s"]) // 3 for t in trains)
    print(f"{len(trains)} trains, {stops} stops, {len(stations)} stations; days {days}, holiday {holiday}")
    if dropped:
        print(f"left out (not in tra.json): {dropped}")


if __name__ == "__main__":
    main()
