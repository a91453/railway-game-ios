"""Which data tells a station's tide best (the tide's step 1.5).

Taipei Metro's stations in 2025 are the answer: each working day's morning
(07-09) share of a station's entries, morning share of its exits, and
morning entries ÷ evening (17-19) entries, from `trtc_hourly_2025.json`
(build_trtc_hourly.py). Each way of guessing them is fitted on the other
stations and asked about the one left out (leave-one-out), so no way is
judged on a station it learnt from:

- none: every station the others' average (the floor every way must beat);
- A: the kind the game gives a station from the OpenStreetMap places within
  800 m (StationDemandKind.realWorld: offices, shops, sights or schools if
  one has 1.5 times what the station's residents would at the country's
  rate, homes otherwise), each kind the average of its stations;
- B: the same places and residents, mixed rather than the most: each kind's
  share of the people and places within 800 m (a place weighed as the
  residents who would have it at the country's rate), each kind a curve
  and a station the curves in its shares;
- C: the station's township's weekday daytime ÷ night-time people, from
  the Ministry of the Interior's telecom signal counts (data.gov.tw 162907
  and 162908, November 2020): a line in its logarithm;
- D: B and C together;
- B′ and D′: B and D with the places in one number rather than mixed: the
  logarithm of the places (each weighed as above) ÷ the residents, a
  station's own daytime ÷ night-time as OpenStreetMap tells it. A line in
  it does not run past the stations it learnt from as B's mix can.

The places and people are the app's own files (`taiwan_places.json`,
OpenStreetMap, ODbL 1.0; `taiwan_population.json`, WorldPop, CC BY 4.0),
counted as the app does (GridCounts.count(within:), a sample every 50 m);
the stations' coordinates are `trtc.json`'s and their townships the
outlines in `taiwan_place_names.json` (OpenStreetMap). The two telecom
files are read with curl and their SHA-256 kept in the output.

    python3 -I tools/real-ridership/compare_tide_sources.py \\
        --downloaded 2026-10-21 \\
        --output tools/real-ridership/tide_sources_2025.json

Standard library and curl only. See README.md.
"""

import argparse
import csv
import hashlib
import io
import json
import math
import os
import statistics
import sys

# The sibling tool's reader; -I leaves the script's folder off the path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_trtc_ridership import LICENCE, open_url

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RESOURCES = os.path.join(ROOT, "RailwayGameApp", "Resources")

# 162907 has two files of daytime people a few per cent apart; the second
# is the one research RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md §2.3
# read (its 蘆洲 0.69).
DAY_DATASET = "https://data.gov.tw/dataset/162907"
NIGHT_DATASET = "https://data.gov.tw/dataset/162908"
DAY_URL = "https://opdadm.moi.gov.tw/api/v1/no-auth/resource/api/dataset/F12D8CDB-7758-40FB-8C27-D19987BA5ECB/resource/8912D1ED-D811-419F-8BB6-BAB47260146E/download"
NIGHT_URL = "https://opdadm.moi.gov.tw/api/v1/no-auth/resource/api/dataset/556056F7-2418-493E-B2F8-B94E9F376728/resource/3A0FB7B7-B4DC-4637-9C14-3777E21C3497/download"

RADIUS = 800.0  # StationDemand.catchmentRadius
KINDS = ["offices", "shops", "attractions", "schools"]
# StationDemandKind.realWorld's rule.
THRESHOLD = 1.5
MINIMUMS = {"offices": 5, "shops": 30, "attractions": 1, "schools": 3}
GAME_KIND = {"offices": "office", "shops": "shopping", "attractions": "scenic", "schools": "civic"}
BUSY = 1_000
MEASURES = [
    ("morningEntries", "07-09 share of entries"),
    ("morningExits", "07-09 share of exits"),
    ("morningToEvening", "07-09 entries ÷ 17-19 entries"),
]
METHODS = ["none", "A", "B", "B′", "C", "D", "D′"]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--downloaded", required=True, help="the day the telecom files were read, YYYY-MM-DD")
    parser.add_argument("--output", required=True)
    parser.add_argument("--hourly", default=os.path.join(HERE, "trtc_hourly_2025.json"))
    parser.add_argument("--lines", default=os.path.join(RESOURCES, "RealRailways", "trtc.json"))
    parser.add_argument("--population", default=os.path.join(RESOURCES, "RealWorld", "taiwan_population.json"))
    parser.add_argument("--places", default=os.path.join(RESOURCES, "RealWorld", "taiwan_places.json"))
    parser.add_argument("--townships", default=os.path.join(RESOURCES, "RealWorld", "taiwan_place_names.json"))
    parser.add_argument("--day", default=DAY_URL, help="162907's daytime file (a URL curl reads; tests give a file:// one)")
    parser.add_argument("--night", default=NIGHT_URL, help="162908's night-time file")
    args = parser.parse_args()

    hourly = json.load(open(args.hourly, encoding="utf-8"))
    working = hourly["stations"]["workingDay"]
    where = {}
    for line in json.load(open(args.lines, encoding="utf-8"))["lines"]:
        for station in line["stations"]:
            where.setdefault(station["name"], (station["lat"], station["lon"]))
    # The Circular line's own stations have entries but no exits in 128506
    # (build_trtc_hourly.py): a station needs both.
    names = sorted(name for name, counts in working.items() if counts[0] >= BUSY and counts[1] >= BUSY)
    unplaced = [name for name in names if name not in where]
    if unplaced:
        sys.exit(f"no coordinates in {args.lines} for {', '.join(unplaced)}")

    population = Grid(json.load(open(args.population, encoding="utf-8")), "runs")
    places_file = json.load(open(args.places, encoding="utf-8"))
    places = {kind: Grid(places_file, kind) for kind in KINDS}
    townships = Townships(json.load(open(args.townships, encoding="utf-8")))
    day, day_sha = read_csv(args.day)
    night, night_sha = read_csv(args.night)
    ratios = township_ratios(day, night)

    stations = []
    for name in names:
        latitude, longitude = where[name]
        entries, exits, am_in, am_out, pm_in, _ = working[name]
        residents = population.count(latitude, longitude)
        nearby = {kind: places[kind].count(latitude, longitude) for kind in KINDS}
        town = townships.containing(latitude, longitude)
        if town is None:
            town = townships.nearest(latitude, longitude)
            print(f"{name}: on no township's outline; the nearest is {town}")
        if town not in ratios:
            sys.exit(f"{name}: no township with telecom counts at {latitude}, {longitude} ({town})")
        stations.append({
            "name": name,
            "township": ratios[town]["name"],
            "answer": {
                "morningEntries": am_in / entries,
                "morningExits": am_out / exits,
                "morningToEvening": am_in / max(pm_in, 1),
            },
            "residents": round(residents),
            "places": {kind: round(nearby[kind], 1) for kind in KINDS},
            "kind": game_kind(residents, nearby, population.total, {kind: places[kind].total for kind in KINDS}),
            "shares": shares(residents, nearby, population.total, {kind: places[kind].total for kind in KINDS}),
            "dayToNight": ratios[town]["day"],
        })

    features = {
        "none": lambda s: [1.0],
        "A": lambda s: [1.0 if s["kind"] == kind else 0.0 for kind in ["residential"] + [GAME_KIND[k] for k in KINDS]],
        "B": lambda s: [s["shares"][kind] for kind in ["homes"] + KINDS],
        "C": lambda s: [1.0, math.log(s["dayToNight"])],
        "D": lambda s: [s["shares"][kind] for kind in ["homes"] + KINDS] + [math.log(s["dayToNight"])],
        "B′": lambda s: [1.0, places_to_homes(s)],
        "D′": lambda s: [1.0, math.log(s["dayToNight"]), places_to_homes(s)],
    }
    results = {}
    for key, _ in MEASURES:
        # The ratio is guessed and judged in its logarithm: 2× too many and
        # 2× too few are as wrong.
        logged = key == "morningToEvening"
        answers = [math.log(s["answer"][key]) if logged else s["answer"][key] for s in stations]
        results[key] = {}
        for method in METHODS:
            rows = [features[method](s) for s in stations]
            guesses = leave_one_out(rows, answers)
            for station, guess in zip(stations, guesses):
                station.setdefault("guess", {}).setdefault(key, {})[method] = math.exp(guess) if logged else guess
            errors = [abs(g - a) for g, a in zip(guesses, answers)]
            worst = sorted(range(len(stations)), key=lambda i: -errors[i])[:5]
            results[key][method] = {
                "medianError": statistics.median(errors),
                "meanError": statistics.fmean(errors),
                "worst": [stations[i]["name"] for i in worst],
            }

    output = {
        "measure": "leave-one-out: each way fitted by least squares on the other stations; errors are absolute, in shares for the two shares and in the natural logarithm for the ratio",
        "answer": {"file": os.path.basename(args.hourly), "source": hourly["source"]["title"], "dataset": hourly["source"]["dataset"], "period": hourly["period"]},
        "telecom": {
            "publisher": "內政部統計處",
            "day": {"title": "全國各鄉鎮市區電信信令人口統計資料日間活動人口", "dataset": DAY_DATASET, "url": args.day, "sha256": day_sha},
            "night": {"title": "全國各鄉鎮市區電信信令人口統計資料夜間停留人口", "dataset": NIGHT_DATASET, "url": args.night, "sha256": night_sha},
            "period": "2020-11",
            "downloaded": args.downloaded,
            "licence": LICENCE,
        },
        "places": {"file": "taiwan_places.json", "source": places_file["source"], "licence": places_file["licence"], "radius": RADIUS},
        "results": results,
        "stations": [],
    }
    # A station a line: the file stays small enough to read.
    text = json.dumps(round_floats(output), ensure_ascii=False, indent=1)
    rows = ",\n  ".join(json.dumps(round_floats(station), ensure_ascii=False) for station in stations)
    with open(args.output, "w", encoding="utf-8") as file:
        file.write(text.replace('"stations": []', '"stations": [\n  ' + rows + "\n ]") + "\n")
    report(stations, results)


def report(stations, results):
    kinds = {}
    for station in stations:
        kinds[station["kind"]] = kinds.get(station["kind"], 0) + 1
    print(f"{len(stations)} stations; the game's kinds: " + ", ".join(f"{kind} {count}" for kind, count in sorted(kinds.items())))
    for key, title in MEASURES:
        logged = key == "morningToEvening"
        print(f"\n{title}: median error" + (" (×)" if logged else " (points)") + ", worst stations")
        for method in METHODS:
            result = results[key][method]
            error = f"{math.exp(result['medianError']):.2f}×" if logged else f"{100 * result['medianError']:.1f}"
            print(f"  {method:4} {error:>6}  {', '.join(result['worst'])}")


def places_to_homes(station):
    """B′'s number: the logarithm of the places ÷ the residents, each kept
    off zero by a thousandth of the whole."""
    homes = station["shares"]["homes"]
    return math.log(max(1 - homes, 0.001) / max(homes, 0.001))


def leave_one_out(rows, answers):
    """Each answer guessed by least squares on all the others."""
    guesses = []
    for i in range(len(rows)):
        others = [j for j in range(len(rows)) if j != i]
        weights = least_squares([rows[j] for j in others], [answers[j] for j in others])
        guesses.append(sum(w * x for w, x in zip(weights, rows[i])))
    return guesses


def least_squares(rows, answers):
    """The weights of the columns that best give the answers: the normal
    equations, a tiny ridge keeping a column no station has (a kind none of
    the others is) from making them singular."""
    width = len(rows[0])
    matrix = [[sum(row[a] * row[b] for row in rows) + (1e-9 if a == b else 0) for b in range(width)] for a in range(width)]
    vector = [sum(row[a] * y for row, y in zip(rows, answers)) for a in range(width)]
    return solve(matrix, vector)


def solve(matrix, vector):
    n = len(vector)
    m = [row[:] + [v] for row, v in zip(matrix, vector)]
    for column in range(n):
        pivot = max(range(column, n), key=lambda r: abs(m[r][column]))
        m[column], m[pivot] = m[pivot], m[column]
        for r in range(n):
            if r != column and m[column][column] != 0:
                factor = m[r][column] / m[column][column]
                m[r] = [a - factor * b for a, b in zip(m[r], m[column])]
    return [m[r][n] / m[r][r] if m[r][r] != 0 else 0.0 for r in range(n)]


def game_kind(residents, nearby, population, totals):
    """StationDemandKind.realWorld: ties to offices, shops, sights, schools."""
    best = ("residential", 0.0)
    for kind in KINDS:
        expected = max(residents * totals[kind] / population, MINIMUMS[kind])
        ratio = nearby[kind] / expected
        if ratio > best[1]:
            best = (GAME_KIND[kind], ratio)
    return best[0] if best[1] >= THRESHOLD else "residential"


def shares(residents, nearby, population, totals):
    """Each kind's share of the station's people and places, a place weighed
    as the residents who would have it at the country's rate."""
    weights = {"homes": residents}
    for kind in KINDS:
        weights[kind] = nearby[kind] * population / totals[kind]
    total = sum(weights.values()) or 1
    return {kind: weight / total for kind, weight in weights.items()}


def read_csv(url):
    digest = hashlib.sha256()
    with open_url(url) as response:
        data = response.read()
    digest.update(data)
    return list(csv.reader(io.StringIO(data.decode("utf-8-sig")))), digest.hexdigest()


def township_ratios(day, night):
    """Taipei's and New Taipei's townships by their bare names (板橋, not
    板橋區; the outlines name them so): weekday daytime ÷ night-time."""
    head, rows = day[0], day[2:]
    town, county, people = head.index("TOWN"), head.index("COUNTY"), head.index("DAY_WORK")
    asleep = {(row[1], row[3]): int(row[4]) for row in night[1:]}
    ratios = {}
    for row in rows:
        if row[county] not in ("臺北市", "新北市"):
            continue
        bare = row[town][:-1] if row[town][-1] in "區市鎮鄉" else row[town]
        ratios[bare] = {"name": row[county] + row[town], "day": int(row[people]) / asleep[(row[county], row[town])]}
    return ratios


class Grid:
    """A layer of WorldPop's grid as the app reads it (GridCounts)."""

    LATITUDE = 110_574.0

    def __init__(self, file, layer):
        self.north, self.west, self.size = float(file["north"]), float(file["west"]), float(file["cellDegrees"])
        runs = file[layer] if layer == "runs" else file["layers"][layer]
        self.counts = {}
        for run in runs:
            for offset, count in enumerate(run["p"]):
                key = (run["r"], run["c"] + offset)
                self.counts[key] = self.counts.get(key, 0) + count
        self.total = sum(self.counts.values())

    def count(self, latitude, longitude, radius=RADIUS, step=50.0):
        """GridCounts.count(within:ofLatitude:longitude:)."""
        steps = math.ceil(radius / step)
        density, samples = 0.0, 0
        for east in range(-steps, steps):
            for south in range(-steps, steps):
                x, y = (east + 0.5) * step, (south + 0.5) * step
                if x * x + y * y > radius * radius:
                    continue
                samples += 1
                lat = latitude - y / self.LATITUDE
                lon = longitude + x / (111_320.0 * math.cos(latitude * math.pi / 180))
                cell = (math.floor((self.north - lat) / self.size), math.floor((lon - self.west) / self.size))
                count = self.counts.get(cell, 0)
                if count > 0:
                    middle = self.north - (cell[0] + 0.5) * self.size
                    area = self.size * self.LATITUDE * self.size * 111_320.0 * math.cos(middle * math.pi / 180)
                    density += count / area
        return density / samples * math.pi * radius * radius if samples else 0.0


class Townships:
    """The townships' outlines of taiwan_place_names.json (PlaceNames)."""

    def __init__(self, file):
        scale = float(file["scale"])
        self.townships = []
        for township in file["townships"]:
            rings = []
            for deltas in township["rings"]:
                latitude = longitude = 0
                ring = []
                for i in range(0, len(deltas), 2):
                    latitude += deltas[i]
                    longitude += deltas[i + 1]
                    ring.append((latitude / scale, longitude / scale))
                rings.append(ring)
            self.townships.append((township["name"], rings))

    def containing(self, latitude, longitude):
        for name, rings in self.townships:
            inside = False
            for ring in rings:
                j = len(ring) - 1
                for i in range(len(ring)):
                    (a_lat, a_lon), (b_lat, b_lon) = ring[i], ring[j]
                    if (a_lat > latitude) != (b_lat > latitude):
                        if longitude < (b_lon - a_lon) * (latitude - a_lat) / (b_lat - a_lat) + a_lon:
                            inside = not inside
                    j = i
            if inside:
                return name
        return None

    def nearest(self, latitude, longitude):
        """The township whose outline passes nearest: for a station on a
        border the simplified outlines leave out of both (中山)."""
        def gap(a, b):
            # Degrees are near enough square at a few hundred metres.
            ax, ay, bx, by = a[1] - longitude, a[0] - latitude, b[1] - longitude, b[0] - latitude
            dx, dy = bx - ax, by - ay
            t = max(0.0, min(1.0, -(ax * dx + ay * dy) / ((dx * dx + dy * dy) or 1)))
            return math.hypot(ax + t * dx, ay + t * dy)
        return min(((min(gap(ring[i - 1], ring[i]) for ring in rings for i in range(len(ring))), name)
                    for name, rings in self.townships))[1]


def round_floats(value):
    if isinstance(value, float):
        return round(value, 3)
    if isinstance(value, dict):
        return {key: round_floats(item) for key, item in value.items()}
    if isinstance(value, list):
        return [round_floats(item) for item in value]
    return value


if __name__ == "__main__":
    main()
