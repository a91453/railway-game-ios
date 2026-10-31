#!/usr/bin/env python3
"""Extract the trains the DR3100 diesel express runs, for the real lines of
the 3D map (ARCHITECTURE decision 511), from the `Railway/` site's TRA
timetable.

    python3 -I tools/real-timetables/extract_dr3100_schedule.py \\
        <reference>/Railway/taiwan-rail-reference-clean/source/data/tra_schedule_dense.json \\
        RailwayGameApp/Resources/RealRailways/tra-dr3100-schedule.json

The input is the newer snapshot's `data/tra_schedule_dense.json`: every TRA
train of 14 days from 2026-10-16 (TRA's open data, ods.railway.gov.tw,
under the Open Government Data License, version 1), each with its model
(`carName`), its stops' arrival and departure seconds of the service day,
the stations it passes timed between its calls along the line, and which
dates it runs.

The output is the trains whose model is `自強(D31)` (the site's
`data/tra_special_trains.json` names that model the DR3100 diesel express)
on the first day, in the format of the app's `thsr-schedule.json`
(``RealDailySchedule``), every station it passes kept with its time. The
program stops when those trains do not run every one of the 14 days: the
game runs them every day.
"""
import json
import sys

MODEL = "自強(D31)"


def extract(data):
    dates = sorted(data["dates"])
    first = dates[0]
    picked = [i for i in data["dates"][first] if data["trains"][i]["carName"] == MODEL]
    for date in dates:
        theirs = sorted(i for i in data["dates"][date] if data["trains"][i]["carName"] == MODEL)
        if theirs != sorted(picked):
            sys.exit(f"{date}: {[data['trains'][i]['train'] for i in theirs]} run, not those of {first}")
    trains = []
    for index in picked:
        train = data["trains"][index]
        trains.append({
            "train": train["train"],
            "typeName": train["typeName"],
            "carName": train["carName"],
            "color": train["color"],
            "stops": [
                {"name": s["name"], "lat": s["lat"], "lon": s["lon"], "order": order,
                 "arrSec": s["arrSec"], "depSec": s["depSec"], "stop": bool(s.get("stop"))}
                for order, s in enumerate(train["stops"], start=1)
            ],
        })
    trains.sort(key=lambda t: (t["stops"][0]["depSec"], t["train"]))
    return first, dates[-1], trains


def main():
    source, target = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as f:
        data = json.load(f)
    first, last, trains = extract(data)
    out = {
        "system": "臺鐵 DR3100 柴聯自強號",
        "date": first.replace("-", ""),
        "source_notes": (
            "臺鐵開放資料（ods.railway.gov.tw，政府資料開放授權條款第 1 版），經參考庫 "
            "Railway/taiwan-rail-reference-clean 的 data/tra_schedule_dense.json；"
            f"車種「{MODEL}」（data/tra_special_trains.json 的 DR3100 柴聯自強號）的列車，"
            f"{first} 到 {last} 每天都開。通過站的時刻照網站的沿線內插。"
            "由 tools/real-timetables/extract_dr3100_schedule.py 產生。"
        ),
        "types": data["types"],
        "trains": trains,
    }
    with open(target, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{len(trains)} trains: {', '.join(t['train'] for t in trains)}")


if __name__ == "__main__":
    main()
