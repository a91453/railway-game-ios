#!/usr/bin/env python3
"""The trains of the Rovaniemi map's stations from Fintraffic's open rail
data (Digitraffic, CC BY 4.0), as `digitraffic_trains.json` beside this
tool (decision 789).

    python3 -I tools/rovaniemi-map/fetch_digitraffic.py 2026-12-14 2026-12-20

Asks `https://rata.digitraffic.fi/api/v1/trains/<date>` for each day from
the first date to the last, and `metadata/stations` once, and keeps only
the passenger trains (long-distance and commuter; not cargo, locomotives or
shunting) that call at or pass a station of `build_rovaniemi_rail.STATIONS`,
with their rows at those stations: scheduled time (UTC), arrival or
departure, whether the train stops there and whether the stop is
commercial. Digitraffic asks every client for a `Digitraffic-User` header;
this tool sends a generic one, no personal data.
"""
import datetime
import gzip
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_rovaniemi_rail  # noqa: E402

API = "https://rata.digitraffic.fi/api/v1"
HEADERS = {"Digitraffic-User": "railway-game-ios-tools", "Accept-Encoding": "gzip"}


def get(path):
    request = urllib.request.Request(f"{API}/{path}", headers=HEADERS)
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
    return json.loads(body)


def main(first, last):
    codes = set(build_rovaniemi_rail.STATIONS)
    stations = {s["stationShortCode"]: s for s in get("metadata/stations") if s["stationShortCode"] in codes}
    missing = codes - set(stations)
    if missing:
        sys.exit(f"Digitraffic lists no station {sorted(missing)}")
    days = {}
    day, end = datetime.date.fromisoformat(first), datetime.date.fromisoformat(last)
    while day <= end:
        kept = []
        for train in get(f"trains/{day.isoformat()}"):
            if train["trainCategory"] not in ("Long-distance", "Commuter") or train.get("cancelled"):
                continue
            rows = [{"station": r["stationShortCode"], "type": r["type"], "time": r["scheduledTime"],
                     "stops": r["trainStopping"], "commercial": bool(r.get("commercialStop"))}
                    for r in train["timeTableRows"] if r["stationShortCode"] in codes]
            if rows:
                kept.append({"type": train["trainType"], "number": train["trainNumber"],
                             "from": train["timeTableRows"][0]["stationShortCode"],
                             "to": train["timeTableRows"][-1]["stationShortCode"], "rows": rows})
        days[day.isoformat()] = sorted(kept, key=lambda t: t["number"])
        print(f"{day}: {len(kept)} passenger trains")
        day += datetime.timedelta(days=1)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "digitraffic_trains.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({
            "source": "Fintraffic / digitraffic.fi, rata.digitraffic.fi/api/v1/trains/<date> and metadata/stations",
            "licence": "CC BY 4.0",
            "fetched": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "stations": {code: {"name": s["stationName"], "lat": s["latitude"], "lon": s["longitude"],
                                "passenger": s["passengerTraffic"]} for code, s in sorted(stations.items())},
            "days": days,
        }, f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
