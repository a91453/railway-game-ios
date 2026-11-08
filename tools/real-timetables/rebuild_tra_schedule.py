#!/usr/bin/env python3
"""Rebuild the reference site's `tra_schedule_dense.json` from TRA's daily
timetables (ARCHITECTURE decision 650), for `extract_tra_schedule.py`.

    python3 -I tools/real-timetables/rebuild_tra_schedule.py \\
        <reference>/Railway/taiwan-rail-reference-clean/source \\
        <dir> 2026-11-08 <out>/tra_schedule_dense.json [--skip 2026-11-09 ...]

The reference site makes the file in two steps, `scripts/fetch_tra_schedule.py`
(TRA's open data, ods.railway.gov.tw: a list page of daily JSON files, and
the station list) and `scripts/densify_schedule.py` (the stations each train
passes, timed along the line). ods.railway.gov.tw does not answer the cloud
sessions (the connection is reset), so this tool runs both scripts as they
are, from the reference checkout, with their downloads answered from files
fetched elsewhere. `<dir>` holds one of:

- ODS's own files, as `.github/workflows/tra-ods-fetch.yml` saves them from
  a GitHub runner (the artifact `tra-ods`): `stations.json` and
  `YYYYMMDD.json`, one a day (preferred: times to the second);
- or TDX's, when ODS cannot be had: `station.json` (TDX
  `/api/basic/v3/Rail/TRA/Station`) and `day-YYYY-MM-DD.json` (TDX
  `/api/basic/v3/Rail/TRA/DailyTrainTimetable/TrainDate/YYYY-MM-DD`), each
  fetched with `.github/workflows/tdx-check.yml`. TDX's TRA timetables are
  TRA's own (AuthorityCode TRA) with ODS's fields under other names
  (`TrainTypeID` is `CarClass`, `StationID` `Station`, `StopSequence`
  `Order`), but to the minute, not the second. A day on which TDX marks a
  train suspended (`SuspendedFlag` 1, or 2 for part of its run) is left out
  whole.

`--skip` leaves out the days given: a disrupted day is not the timetable
(2026-11-09 had 106 of its 908 trains suspended, the Jiji line all day, as
TDX marks it; ODS's file of that day does not say so), and the game's week
takes the next day of that weekday instead.

The scripts take the days from the start date (the third argument, so a
rerun gives the same file) that the list page holds: the list this tool
answers with holds every day file given, so a weekday holiday after the
fortnight (for the game's holiday bit) can come along. Nothing is written
into the reference checkout: the scripts run in a temporary directory
holding copies of the `data/` files they read.
"""
import datetime
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile


def ods_day(tdx):
    """A TDX daily timetable in ODS's shape, and how many of its trains TDX
    marks suspended."""
    trains, suspended = [], 0
    for timetable in tdx["TrainTimetables"]:
        info = timetable["TrainInfo"]
        if info.get("SuspendedFlag"):
            suspended += 1
        times = []
        for stop in timetable["StopTimes"]:
            times.append({
                "Station": stop["StationID"],
                "Order": str(stop["StopSequence"]),
                "ARRTime": stop["ArrivalTime"] + ":00",
                "DEPTime": stop["DepartureTime"] + ":00",
            })
        trains.append({
            "Train": info["TrainNo"],
            "CarClass": info["TrainTypeID"],
            "Note": info.get("Note", ""),
            "TimeInfos": times,
        })
    update = tdx.get("SrcUpdateTime") or tdx.get("UpdateTime", "")
    return {"TrainInfos": trains, "UpdateTime": update}, suspended


def ods_stations(tdx):
    return [{
        "stationCode": s["StationID"],
        "stationName": s["StationName"]["Zh_tw"],
        "gps": f'{s["StationPosition"]["PositionLat"]} {s["StationPosition"]["PositionLon"]}',
    } for s in tdx["Stations"]]


def read_days(source, skip):
    """The day files of `source` as ODS bytes by YYYYMMDD, the station list
    as ODS bytes, and which source it was."""
    days = {}
    ods = sorted(p for p in source.glob("*.json") if re.fullmatch(r"\d{8}\.json", p.name))
    if ods:
        for path in ods:
            key = path.stem
            date = f"{key[:4]}-{key[4:6]}-{key[6:]}"
            if date in skip:
                print(f"{date}: left out (--skip)", file=sys.stderr)
                continue
            body = path.read_bytes()
            print(f"{date}: {len(json.loads(body)['TrainInfos'])} trains", file=sys.stderr)
            days[key] = body
        return days, (source / "stations.json").read_bytes(), "ods"
    for path in sorted(source.glob("day-*.json")):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        date = data["TrainDate"]
        if path.name != f"day-{date}.json":
            sys.exit(f"{path.name} holds {date}")
        day, suspended = ods_day(data)
        if date in skip or suspended:
            print(f"{date}: left out, {suspended} of its {len(day['TrainInfos'])} trains suspended", file=sys.stderr)
            continue
        days[date.replace("-", "")] = json.dumps(day, ensure_ascii=False).encode("utf-8")
        print(f"{date}: {len(day['TrainInfos'])} trains", file=sys.stderr)
    with open(source / "station.json", encoding="utf-8") as f:
        stations = json.dumps(ods_stations(json.load(f)), ensure_ascii=False).encode("utf-8")
    return days, stations, "tdx"


def main():
    args = sys.argv[1:]
    skip = set()
    while "--skip" in args:
        at = args.index("--skip")
        skip.add(datetime.date.fromisoformat(args[at + 1]).isoformat())
        del args[at:at + 2]
    if len(args) != 4:
        sys.exit(__doc__)
    reference, source, start, target = (pathlib.Path(args[0]).resolve(), pathlib.Path(args[1]).resolve(),
                                        datetime.date.fromisoformat(args[2]), pathlib.Path(args[3]).resolve())
    days, stations, kind = read_days(source, skip)
    if not days:
        sys.exit(f"no day files in {source}")

    work = pathlib.Path(tempfile.mkdtemp())
    try:
        (work / "data").mkdir()
        for name in ["tra.json", "tra_station_of_line.json", "tra_station_info.json"]:
            shutil.copy(reference / "data" / name, work / "data" / name)
        sys.path.insert(0, str(reference / "scripts"))
        os.chdir(work)
        import fetch_tra_schedule as fetch

        listing = "".join(f'<a href="exceptionDataResource/{date}">{date}.json</a>' for date in days)

        def http_get(url, attempts=4):
            if url == fetch.LIST_URL:
                return listing.encode("utf-8")
            if url == fetch.STATIONS_URL:
                return stations
            key = url.rsplit("/", 1)[-1]
            if key in days:
                return days[key]
            raise RuntimeError(f"not answered: {url}")

        class Date(datetime.date):
            @classmethod
            def today(cls):
                return cls(start.year, start.month, start.day)

        class Clock:
            date = Date
            timedelta = datetime.timedelta

        fetch.http_get = http_get
        fetch.datetime = Clock
        last = max(datetime.date(int(d[:4]), int(d[4:6]), int(d[6:])) for d in days)
        fetch.DAYS_AHEAD = (last - start).days + 1
        fetch.main()

        import densify_schedule
        densify_schedule.main()
        with open(work / "data" / "tra_schedule_dense.json", encoding="utf-8") as f:
            dense = json.load(f)
        left_out = f"（不收 {'、'.join(sorted(skip))}，那天有停駛）" if skip else ""
        if kind == "ods":
            note = (
                "臺鐵開放資料 ods.railway.gov.tw 的逐日檔與車站基本資料（政府資料開放授權條款第 1 版），"
                "由 .github/workflows/tra-ods-fetch.yml 在 GitHub 執行器上抓下（雲端連不到），"
                f"再由 tools/real-timetables/rebuild_tra_schedule.py 照參考庫的 fetch_tra_schedule.py 與 "
                f"densify_schedule.py 產生{left_out}。 | ")
        else:
            note = (
                "經 TDX（交通部運輸資料流通服務，/api/basic/v3/Rail/TRA/DailyTrainTimetable/TrainDate 逐日與 "
                "/api/basic/v3/Rail/TRA/Station，資料權責臺鐵，政府資料開放授權條款第 1 版）由 "
                "tools/real-timetables/rebuild_tra_schedule.py 換成 ODS 的格式，照參考庫的 fetch_tra_schedule.py 與 "
                f"densify_schedule.py 產生（ods.railway.gov.tw 雲端連不到；有停駛的日子不收）{left_out}。"
                "以下是兩支原工具寫的說明，其中的 ODS 網址是工具原本的來源，這一份實際讀的是上面的 TDX 檔。 | ")
        dense["source_notes"] = note + dense["source_notes"]
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "w", encoding="utf-8") as f:
            json.dump(dense, f, ensure_ascii=False)
    finally:
        os.chdir("/")
        shutil.rmtree(work, ignore_errors=True)
    print(f"wrote {target}", file=sys.stderr)


if __name__ == "__main__":
    main()
