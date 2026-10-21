#!/usr/bin/env python3
"""How far the app's OpenStreetMap railway lines are from the government's
(HANDOFF §5, PLAYER_FEEDBACK 78.1 #8): the measurement that decides whether
the lines need the official geometry where OSM is off, or only a small
offset of the base map.

    python3 -I tools/real-railways/measure_osm_offset.py \\
        RailwayGameApp/Resources/RealRailways/track_lines.geojson \\
        <RAIL_*.shp> <MRT_*.shp> [report.json]

The lines are the app's bundled `track_lines.geojson` (drawn along
OpenStreetMap, decision 151). The reference is the National Land Surveying
and Mapping Center's "臺灣鐵路" (data.gov.tw 73220) and "捷運" (73222)
shapefiles, TWD97[2020] TM2 zone 121, Open Government Data License 1.0.
Its "高速鐵路" (73221) is served from tgos.tw, which refuses connections
from outside Taiwan, so the High Speed Rail is measured only when its
shapefile is given as a fourth path ending in `.shp` (HSRAIL_*.shp).

Each line is sampled every 20 m; each sample's distance is to the nearest
official segment of the same railway (the TRA's, the Alishan Forest
Railway's or the line's metro system). Samples with no official segment
within 100 m are counted apart as missing from the official data (a line the
official file does not have, or a stretch it has elsewhere) and left out of
the distribution. The official lines are drawn on the centre of the
formation, OSM's on one track, so about 2 m on double track is the two
data sets agreeing.

The shapefile reader and the TM2 inverse are ported from the owner's
reference, `Railway/taiwan-rail-reference-clean/source/scripts/
build_rail_structures_official.mjs` (its `readShp`, `readDbf`, `toWgs`).
"""

import json
import math
import os
import struct
import sys
from collections import defaultdict

STEP = 20.0
MISSING = 100.0
CELL = 0.002  # degrees, about 200 m
R_LAT = 110574.0
R_LON = 101751.0  # at about 23.7° N, as the reference's index

# Which official railway each of the app's systems is measured against.
RAIL = {"tra_sched": "tra", "afr_sched": "afr", "thsr_sched": "hsr"}
METRO = {
    "mrt": {"臺北捷運", "新北捷運"},  # the Circular line is New Taipei's
    "ntdlrt": {"新北捷運"},
    "ntalrt": {"新北捷運"},
    "sanying": {"新北捷運"},
    "tymc": {"臺灣桃園國際機場捷運"},
    "krtc": {"高雄捷運"},
    "tmrt": {"臺中捷運"},
}


def read_dbf(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[4:8])[0]
    header, record = struct.unpack("<HH", b[8:12])
    fields, o = [], 32
    while b[o] != 0x0D:
        fields.append((b[o:o + 11].split(b"\0")[0].decode(), b[o + 16]))
        o += 32
    rows, p = [], header
    for _ in range(n):
        q, row = p + 1, {}
        for name, length in fields:
            row[name] = b[q:q + length].decode("utf8", "replace").strip()
            q += length
        rows.append(row)
        p += record
    return rows


def read_shp(path):
    b = open(path, "rb").read()
    out, p = [], 100
    while p < len(b):
        words = struct.unpack(">I", b[p + 4:p + 8])[0]
        body = b[p + 8:p + 8 + words * 2]
        p += 8 + words * 2
        if struct.unpack("<I", body[0:4])[0] != 3:  # 3 = PolyLine
            out.append([])
            continue
        parts, points = struct.unpack("<II", body[36:44])
        starts = list(struct.unpack("<%dI" % parts, body[44:44 + parts * 4])) + [points]
        base = 44 + parts * 4
        xy = struct.unpack("<%dd" % (points * 2), body[base:base + points * 16])
        pts = [(xy[2 * i], xy[2 * i + 1]) for i in range(points)]
        out.append([pts[starts[i]:starts[i + 1]] for i in range(parts)])
    return out


# TWD97[2020] TM2 zone 121 (EPSG:3826) back to WGS84: central meridian 121°,
# scale 0.9999, false easting 250 km, GRS80.
A, F = 6378137.0, 1 / 298.257222101
E2 = 2 * F - F * F
EP2 = E2 / (1 - E2)
K0, FE, LON0 = 0.9999, 250000.0, math.radians(121)
E1 = (1 - math.sqrt(1 - E2)) / (1 + math.sqrt(1 - E2))


def to_wgs(e, n):
    mu = n / K0 / (A * (1 - E2 / 4 - 3 * E2 ** 2 / 64 - 5 * E2 ** 3 / 256))
    p = (mu + (3 * E1 / 2 - 27 * E1 ** 3 / 32) * math.sin(2 * mu)
         + (21 * E1 ** 2 / 16 - 55 * E1 ** 4 / 32) * math.sin(4 * mu)
         + (151 * E1 ** 3 / 96) * math.sin(6 * mu) + (1097 * E1 ** 4 / 512) * math.sin(8 * mu))
    c, t, s = EP2 * math.cos(p) ** 2, math.tan(p) ** 2, math.sin(p)
    n1 = A / math.sqrt(1 - E2 * s * s)
    r1 = A * (1 - E2) / (1 - E2 * s * s) ** 1.5
    d = (e - FE) / (n1 * K0)
    lat = p - (n1 * math.tan(p) / r1) * (d ** 2 / 2 - (5 + 3 * t + 10 * c - 4 * c * c - 9 * EP2) * d ** 4 / 24
                                         + (61 + 90 * t + 298 * c + 45 * t * t - 252 * EP2 - 3 * c * c) * d ** 6 / 720)
    lon = LON0 + (d - (1 + 2 * t + c) * d ** 3 / 6 + (5 - 2 * c + 28 * t - 3 * c * c + 8 * EP2 + 24 * t * t) * d ** 5 / 120) / math.cos(p)
    return math.degrees(lon), math.degrees(lat)


def load(shp):
    base = shp[:-4]
    if "TM2_zone_121" not in open(base + ".prj").read():
        sys.exit(f"{shp}: not TM2 zone 121")
    rows, geoms = read_dbf(base + ".dbf"), read_shp(shp)
    if len(rows) != len(geoms):
        sys.exit(f"{shp}: {len(rows)} records but {len(geoms)} shapes")
    return [(row, [[to_wgs(x, y) for x, y in part] for part in parts]) for row, parts in zip(rows, geoms)]


class Index:
    def __init__(self):
        self.grid, self.segs = defaultdict(list), []

    def add(self, a, b):
        i = len(self.segs)
        self.segs.append((a, b))
        for x in range(math.floor(min(a[0], b[0]) / CELL), math.floor(max(a[0], b[0]) / CELL) + 1):
            for y in range(math.floor(min(a[1], b[1]) / CELL), math.floor(max(a[1], b[1]) / CELL) + 1):
                self.grid[(x, y)].append(i)

    def nearest(self, pt):
        """The distance to the nearest segment within MISSING and the
        vector to it (east, north), in metres."""
        x0, y0, best, vector = math.floor(pt[0] / CELL), math.floor(pt[1] / CELL), MISSING, None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for i in self.grid.get((x0 + dx, y0 + dy), ()):
                    (ax, ay), (bx, by) = self.segs[i]
                    px, py = (pt[0] - ax) * R_LON, (pt[1] - ay) * R_LAT
                    vx, vy = (bx - ax) * R_LON, (by - ay) * R_LAT
                    l2 = vx * vx + vy * vy
                    t = max(0.0, min(1.0, (px * vx + py * vy) / l2)) if l2 else 0.0
                    d = math.hypot(px - t * vx, py - t * vy)
                    if d < best:
                        best, vector = d, (t * vx - px, t * vy - py)
        return best, vector


def samples(coords):
    out = [coords[0]]
    for p, q in zip(coords, coords[1:]):
        d = math.hypot((q[0] - p[0]) * R_LON, (q[1] - p[1]) * R_LAT)
        for k in range(1, int(d // STEP) + 1):
            t = k * STEP / d
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def quantile(xs, q):
    return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else None


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    lines_path, rail_shp, mrt_shp = sys.argv[1:4]
    rest = sys.argv[4:]
    hsr_shp = next((a for a in rest if a.endswith(".shp")), None)
    report_path = next((a for a in rest if a.endswith(".json")), None)

    indexes = defaultdict(Index)
    for row, parts in load(rail_shp):
        key = "afr" if row["RAILNAME"].startswith("阿里山") else "tra"
        for part in parts:
            for a, b in zip(part, part[1:]):
                indexes[key].add(a, b)
    for row, parts in load(mrt_shp):
        for part in parts:
            for a, b in zip(part, part[1:]):
                indexes["metro:" + row["MRTSYS"]].add(a, b)
    if hsr_shp:
        for _, parts in load(hsr_shp):
            for part in parts:
                for a, b in zip(part, part[1:]):
                    indexes["hsr"].add(a, b)

    features = json.load(open(lines_path))["features"]
    result, every = [], []
    for f in features:
        props, geom = f["properties"], f["geometry"]
        sysid = props["sys"]
        if sysid in RAIL:
            keys = [RAIL[sysid]]
        else:
            keys = ["metro:" + s for s in METRO.get(sysid, ())]
        keys = [k for k in keys if k in indexes]
        if not keys:
            result.append({"sys": sysid, "line": props["name"], "measured": False})
            continue
        runs = geom["coordinates"] if geom["type"] == "MultiLineString" else [geom["coordinates"]]
        distances, missing, east, north = [], 0, 0.0, 0.0
        far, stretch, stretches = 10.0, [], []
        for run in runs:
            for pt in samples(run):
                d, vector = min((indexes[k].nearest(pt) for k in keys), key=lambda found: found[0])
                if vector is None:
                    missing += 1
                    d = None
                else:
                    distances.append(d)
                    east += vector[0]
                    north += vector[1]
                if d is not None and d > far:
                    stretch.append((pt, d))
                    continue
                if len(stretch) * STEP >= 200:
                    stretches.append(stretch)
                stretch = []
            if len(stretch) * STEP >= 200:
                stretches.append(stretch)
            stretch = []
        every += distances
        distances.sort()
        n = len(distances)
        result.append({
            "sys": sysid, "line": props["name"], "measured": True,
            "km": round((n + missing) * STEP / 1000, 1),
            "missingKm": round(missing * STEP / 1000, 1),
            "median": round(quantile(distances, 0.5), 1) if n else None,
            "p90": round(quantile(distances, 0.9), 1) if n else None,
            "p99": round(quantile(distances, 0.99), 1) if n else None,
            "max": round(distances[-1], 1) if n else None,
            "within3": round(sum(d <= 3 for d in distances) / n, 3) if n else None,
            "over10": round(sum(d > 10 for d in distances) / n, 3) if n else None,
            # The mean vector from the app's line to the official one: a
            # shift of the whole line shows here, scatter averages out.
            "meanShift": [round(east / n, 1), round(north / n, 1)] if n else None,
            "stretchesOver10": [
                {"from": [round(s[0][0][0], 5), round(s[0][0][1], 5)], "to": [round(s[-1][0][0], 5), round(s[-1][0][1], 5)],
                 "km": round(len(s) * STEP / 1000, 2), "worst": round(max(d for _, d in s), 1)}
                for s in stretches],
        })
    every.sort()
    total = {
        "km": round(len(every) * STEP / 1000, 1),
        "median": round(quantile(every, 0.5), 1), "p90": round(quantile(every, 0.9), 1),
        "p99": round(quantile(every, 0.99), 1),
        "within3": round(sum(d <= 3 for d in every) / len(every), 3),
        "over10": round(sum(d > 10 for d in every) / len(every), 3),
    }
    for r in result:
        if not r["measured"]:
            print(f"{r['sys']:10} {r['line']}: not measured (no official file)")
            continue
        print(f"{r['sys']:10} {r['line']}: {r['km']} km (missing {r['missingKm']}), median {r['median']} m, "
              f"p90 {r['p90']}, p99 {r['p99']}, max {r['max']}, shift E/N {r['meanShift']}, ≤3 m {r['within3']}, >10 m {r['over10']}, "
              f"stretches >10 m over 200 m: {len(r['stretchesOver10'])}")
    print("all", total)
    if report_path:
        with open(report_path, "w") as out:
            json.dump({"total": total, "lines": result}, out, ensure_ascii=False, indent=1)
            out.write("\n")


if __name__ == "__main__":
    main()
