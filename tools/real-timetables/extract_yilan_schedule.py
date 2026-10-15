#!/usr/bin/env python3
"""Extract a weekday of the Yilan Line's real trains, Toucheng to Su'aoxin,
for the TRA demo (ARCHITECTURE decision 240) from the `Railway/` site's TRA
timetable.

    python3 -I tools/real-timetables/extract_yilan_schedule.py \\
        <reference>/Railway/site_archive_clean/data/tra_schedule_dense.json \\
        RailwayGameApp/Resources/RealRailways/tra-yilan-schedule.json

The input is the site's `data/tra_schedule_dense.json`: every TRA train of
14 days (TRA's open data, ods.railway.gov.tw, under the Open Government
Data License, version 1), each with its stops' arrival and departure
seconds of the service day, the stations it passes timed between its calls
along the line, and which dates it runs.

The output is one day, in the format of the app's `thsr-schedule.json`
(``RealDailySchedule``): every train of 2026-10-05, a Monday with no
holiday, that calls at two of the demo's stations or more, with its stops
between Toucheng and Su'aoxin. Xinma is left out: no train calls there
that day.

The demo's railway ends at Toucheng and Su'aoxin, where the real trains
come from and go on to Taipei and Hualien. A train that runs on beyond
either end, and passes it, is given a call there at its passing time: so
the expresses run the whole way, as they do, and not only between the
stations they call at.
"""
import json
import sys

DATE = "2026-10-05"
ENDS = {"頭城", "蘇澳新"}
STATIONS = ["頭城", "頂埔", "礁溪", "四城", "宜蘭", "二結", "中里", "羅東", "冬山", "蘇澳新"]


def extract(data):
    trains = []
    for index in data["dates"][DATE]:
        train = data["trains"][index]
        stops = train["stops"]
        inside = [i for i, s in enumerate(stops) if s["name"] in STATIONS]
        if not inside:
            continue
        kept = [dict(stops[i], stop=bool(stops[i].get("stop"))) for i in inside]
        # The ends: a train that comes from beyond the first station it
        # reaches, or goes on beyond the last, calls there.
        if kept[0]["name"] in ENDS and inside[0] > 0:
            kept[0]["stop"] = True
        if kept[-1]["name"] in ENDS and inside[-1] < len(stops) - 1:
            kept[-1]["stop"] = True
        calls = [s for s in kept if s["stop"]]
        if len(calls) < 2:
            continue
        # Only the stretch from its first call to its last.
        kept = kept[kept.index(calls[0]):kept.index(calls[-1]) + 1]
        for order, stop in enumerate(kept, start=1):
            stop["order"] = order
        trains.append({
            "train": train["train"],
            "typeName": train["typeName"],
            "carName": train["carName"],
            "color": train["color"],
            "stops": [{k: s[k] for k in ("name", "lat", "lon", "order", "arrSec", "depSec", "stop")} for s in kept],
        })
    trains.sort(key=lambda t: (t["stops"][0]["depSec"], t["train"]))
    return trains


def main():
    source, target = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as f:
        data = json.load(f)
    trains = extract(data)
    out = {
        "system": "臺鐵宜蘭線時刻表",
        "date": DATE.replace("-", ""),
        "source_notes": (
            "臺鐵開放資料（ods.railway.gov.tw，政府資料開放授權條款第 1 版），經參考庫 Railway/ 網站的 "
            f"data/tra_schedule_dense.json；{DATE}（星期一）頭城到蘇澳新之間停靠兩站以上的列車。"
            "通過站的時刻照網站的沿線內插。示範的鐵路止於頭城與蘇澳新，"
            "開往更遠處而通過這兩站的列車，在該站照通過時刻算一次停靠。"
            "由 tools/real-timetables/extract_yilan_schedule.py 產生。"
        ),
        "types": data["types"],
        "trains": trains,
    }
    with open(target, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{len(trains)} trains")


if __name__ == "__main__":
    main()
