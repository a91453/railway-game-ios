#!/usr/bin/env python3
"""Sample MTR's next-train feed (Real-time MTR train information,
DATA.GOV.HK) for every station of every line in `mtr_lines_and_stations.csv`.

    python3 -I tools/hk-map/sample_next_train.py mtr_lines_and_stations.csv <folder> <sweeps> <seconds between>

One JSON file a sweep in `<folder>`, named by its UTC time: each "LINE-STA"
to the feed's answer. A sweep is 120 requests, 0.15 s apart. The samples are
not committed; `next_train_service.py` turns them into `service.json`.
"""
import csv
import json
import os
import sys
import time
import urllib.request

FEED = "https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line={}&sta={}"


def main(stations_csv, folder, sweeps, interval):
    pairs = []
    with open(stations_csv, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            pair = (row["Line Code"], row["Station Code"])
            if row["Line Code"] and pair not in pairs:
                pairs.append(pair)
    for _ in range(int(sweeps)):
        start, answers = time.time(), {}
        for line, station in pairs:
            try:
                with urllib.request.urlopen(FEED.format(line, station), timeout=20) as f:
                    answers[f"{line}-{station}"] = json.load(f)
            except Exception as error:  # a sweep keeps what it could read
                answers[f"{line}-{station}"] = {"error": str(error)}
            time.sleep(0.15)
        name = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(start))
        with open(os.path.join(folder, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(answers, f, ensure_ascii=False)
        print(name, len(answers), round(time.time() - start), flush=True)
        time.sleep(max(0, int(interval) - (time.time() - start)))


if __name__ == "__main__":
    main(*sys.argv[1:])
