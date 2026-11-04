#!/usr/bin/env python3
"""Landmarks, roads and crossings a new station on a real-world map can be
named after, as the app's `Resources/RealWorld/taiwan_station_landmarks.json`
(decision 569).

    python3 -I tools/station-landmarks/build_station_landmarks.py taiwan.pbf \\
        RailwayGameApp/Resources/RealWorld/taiwan_place_names.json \\
        RailwayGameApp/Resources/RealWorld/taiwan_station_landmarks.json

The extract is the one every other data tool reads (osmtoday.com's
`asia/taiwan.pbf`, read with pyosmium, BSD 2-Clause, `pip install osmium`;
decision 93); about two minutes. The place names file (decision 159) gives
the townships' outlines, which keep Fujian's roads and schools out.

- `landmarks`: universities and colleges, senior high schools (by name:
  高中, 高級中學, 高工, 高商… but not 國中, 國小), hospitals, parks of at least
  PARK_AREA m², night markets and shopping districts (夜市, 商圈), malls and
  department stores. A campus, hospital or shop drawn only as a point, or
  smaller than its kind's least area, is left out: a station is named after
  what people know. Each row: latitude, longitude, kind, area in hundreds
  of m² (0 for a point), Chinese name, English name or nothing. The name is
  the short one a station would take (國立臺灣大學 → 臺灣大學,
  臺北市立建國高級中學 → 建國高中). Of two places with one name within
  MERGE_METRES, the larger stays.
- `roads`: the names of the named trunk, primary, secondary and tertiary
  roads (路, 街, 大道; not 高速, 快速, 公路, 道路), without their section (南京東路三段 →
  南京東路), with the English name likewise ("Section 3, Nanjing East
  Road" → "Nanjing East Road"), longest first.
- `ways`: each road's lines (its ways joined where they meet), simplified to about TOLERANCE degrees: the road
  index, then the points as differences from the one before.
- `crossings`: where two of those roads meet (a node both use): latitude,
  longitude, the two roads' indices, the longer one first. One crossing of
  the same two roads per MERGE_METRES.

The game turns a crossing into a name the way Taiwan's metro and light rail
do (南京東路 × 復興北路 → 南京復興; `StationLandmarks.crossingName`), so the
rule is in Swift with its tests, not here.

Coordinates are in 1e-5 degrees (about a metre). The data is
OpenStreetMap's (ODbL 1.0), credited in the game's data sources
(`DataSourceCredits`).
"""
import json
import math
import re
import sys

import osmium

SCALE = 100000
TOLERANCE = 0.0004
MERGE_METRES = 600
PARK_AREA = 30000
LEAST_AREA = {
    'university': 20000,
    'school': 5000,
    'hospital': 4000,
    'park': PARK_AREA,
    'market': 0,
    'mall': 3000,
}
KINDS = ['university', 'school', 'hospital', 'park', 'market', 'mall']
ROAD_CLASSES = ('trunk', 'primary', 'secondary', 'tertiary')
ROAD = re.compile(r'^(.+?(?:路|街|大道))(?:[一二三四五六七八九十]+段)?$')
SECTION_EN = re.compile(r'(,?\s*(Sec\.|Section)\s*\d+,?\s*|\s*\d+(st|nd|rd|th)?\s*(Sec\.|Section)\s*)', re.I)
HIGH_SCHOOL = re.compile(r'高中|高級|中學|高工|高商|高農|高職|高家|工商|女中')
NOT_HIGH_SCHOOL = re.compile(r'國民中學|國中|國小|國民小學|附設|補習|幼兒')
UNIVERSITY = re.compile(r'大學|學院|科大|專科')
NOT_CAMPUS = re.compile(r'系|館|中心|宿舍|社區大學|補習|聖經|神學|廣場|研究所|分部')
SHOP_BRANDS = re.compile(r'全聯|小北|五金|生活百貨|皮件|鐘錶')


def short_name(name, kind):
    """The name a station would take."""
    name = re.sub(r'[\s(（,，、].*$', '', name) or name
    name = re.sub(r'^(國立|私立|天主教|基督教)', '', name)
    name = re.sub(r'^[一-鿿]{2}[市縣](市立|縣立|私立|立)', '', name)
    name = re.sub(r'^(市立|縣立|私立)', '', name)
    name = re.sub(r'^(天主教|基督教)', '', name)
    if kind == 'school':
        for long, short in (('女子高級中學', '女中'), ('高級中學', '高中'), ('實驗高級中學', '實中'),
                            ('高級工業職業學校', '高工'), ('高級商業職業學校', '高商'),
                            ('高級農業職業學校', '高農'), ('高級工商職業學校', '高工商'),
                            ('高級家事商業職業學校', '高家商'), ('高級海事水產職業學校', '海事')):
            name = name.replace(long, short)
    return name


def english(tags):
    en = tags.get('name:en')
    return en.strip() if en else None


def chinese(tags):
    return tags.get('name:zh-Hant') or tags.get('name:zh-TW') or tags.get('name')


def landmark_kind(tags):
    name = chinese(tags) or ''
    amenity, shop, leisure = tags.get('amenity'), tags.get('shop'), tags.get('leisure')
    if amenity in ('university', 'college'):
        if UNIVERSITY.search(name) and not NOT_CAMPUS.search(name):
            return 'university'
    if amenity == 'school' and HIGH_SCHOOL.search(name) and not NOT_HIGH_SCHOOL.search(name):
        return 'school'
    if amenity == 'hospital' and '醫院' in name:
        return 'hospital'
    if leisure == 'park' and name.endswith('公園'):
        return 'park'
    if '夜市' in name and amenity == 'marketplace':
        return 'market'
    if name.endswith('商圈') and not any(k in tags for k in ('highway', 'public_transport', 'railway', 'amenity')):
        return 'market'
    if '夜市' in name and not any(k in tags for k in ('highway', 'public_transport', 'railway', 'amenity', 'shop')):
        return 'market'
    if shop in ('mall', 'department_store') and not SHOP_BRANDS.search(name):
        return 'mall'
    return None


def metres(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((a[0] - b[0]) * 110540, (a[1] - b[1]) * 111320 * math.cos(lat))


def simplify(points, tolerance):
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (ay, ax), (by, bx) = points[first], points[last]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, index = 0.0, None
        for i in range(first + 1, last):
            py, px = points[i]
            d = math.hypot(px - ax, py - ay) if length == 0 else abs(dy * (px - ax) - dx * (py - ay)) / length
            if d > worst:
                worst, index = d, i
        if index is not None and worst > tolerance:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [p for p, k in zip(points, keep) if k]


def chains(ways):
    """The ways of each name joined end to end where they meet, so a road
    is a few long lines rather than many short ones."""
    by_name = {}
    for base, _, _, refs, points in ways:
        by_name.setdefault(base, []).append(list(zip(refs, points)))
    for base, pieces in by_name.items():
        ends = {}
        for i, piece in enumerate(pieces):
            ends.setdefault(piece[0][0], []).append(i)
            ends.setdefault(piece[-1][0], []).append(i)
        used = [False] * len(pieces)

        def take(node):
            for i in ends.get(node, []):
                if not used[i]:
                    used[i] = True
                    piece = pieces[i]
                    return piece if piece[0][0] == node else piece[::-1]
            return None

        for i, piece in enumerate(pieces):
            if used[i]:
                continue
            used[i] = True
            line = list(piece)
            while (more := take(line[-1][0])) is not None:
                line += more[1:]
            while (more := take(line[0][0])) is not None:
                line = more[::-1][:-1] + line
            yield base, [p for _, p in line]


class Taiwan:
    """The townships' outlines of the place names file."""

    def __init__(self, path):
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        scale = data['scale']
        self.rings = []
        for township in data['townships']:
            for deltas in township['rings']:
                lat = lon = 0
                ring = []
                for i in range(0, len(deltas), 2):
                    lat += deltas[i]
                    lon += deltas[i + 1]
                    ring.append((lat / scale, lon / scale))
                lats = [p[0] for p in ring]
                lons = [p[1] for p in ring]
                self.rings.append((min(lats), max(lats), min(lons), max(lons), ring))
        self.cache = {}

    def contains(self, lat, lon):
        key = (round(lat, 2), round(lon, 2))
        inside_any = False
        for south, north, west, east, ring in self.rings:
            if not (south <= lat <= north and west <= lon <= east):
                continue
            inside = False
            j = len(ring) - 1
            for i in range(len(ring)):
                a, b = ring[i], ring[j]
                if (a[0] > lat) != (b[0] > lat) and lon < (b[1] - a[1]) * (lat - a[0]) / (b[0] - a[0]) + a[1]:
                    inside = not inside
                j = i
            if inside:
                inside_any = True
                break
        return inside_any


class Reader(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.landmarks = []
        self.road_ways = []          # (name, en, class rank, [node ids], [(lat, lon)])
        self.node_roads = {}         # node id → set of road names

    def landmark(self, tags, lat, lon, area):
        kind = landmark_kind(tags)
        if not kind or area < LEAST_AREA[kind]:
            return
        if area == 0 and kind not in ('market',):
            return
        zh = short_name(chinese(tags), kind)
        if len(zh) < 2:
            return
        self.landmarks.append((lat, lon, kind, area, zh, english(tags)))

    def node(self, n):
        if 'name' in n.tags:
            self.landmark(n.tags, n.location.lat, n.location.lon, 0)

    def area(self, a):
        if 'name' not in a.tags or landmark_kind(a.tags) is None:
            return
        try:
            total, lat_sum, lon_sum, count = 0.0, 0.0, 0.0, 0
            for outer in a.outer_rings():
                points = [(n.lat, n.lon) for n in outer]
                lat0 = math.radians(points[0][0])
                s = 0.0
                for (y1, x1), (y2, x2) in zip(points, points[1:]):
                    s += (x1 * y2 - x2 * y1)
                total += abs(s) / 2 * 110540 * 111320 * math.cos(lat0)
                for y, x in points:
                    lat_sum += y
                    lon_sum += x
                    count += 1
        except osmium.InvalidLocationError:
            return
        if count:
            self.landmark(a.tags, lat_sum / count, lon_sum / count, int(total))

    def way(self, w):
        tags = w.tags
        cls = tags.get('highway')
        if cls not in ROAD_CLASSES:
            return
        name = chinese(tags)
        if not name or any(word in name for word in ('高速', '快速', '公路', '道路')):
            return
        match = ROAD.match(name)
        if not match:
            return
        base = match.group(1)
        en = english(tags)
        if en:
            en = SECTION_EN.sub(' ', en).strip(' ,')
        try:
            points = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        self.road_ways.append((base, en, ROAD_CLASSES.index(cls), [n.ref for n in w.nodes], points))


def main(pbf, place_names, out):
    taiwan = Taiwan(place_names)
    reader = Reader()
    reader.apply_file(pbf, locations=True)

    # Landmarks: in Taiwan, one per name per MERGE_METRES (the larger).
    landmarks = sorted((l for l in reader.landmarks if taiwan.contains(l[0], l[1])), key=lambda l: -l[3])
    kept = []
    for l in landmarks:
        if any(k[4] == l[4] and metres(k, l) < MERGE_METRES for k in kept):
            continue
        kept.append(l)
    kept.sort(key=lambda l: (l[0], l[1]))

    # Roads in Taiwan, by name.
    ways = [w for w in reader.road_ways if taiwan.contains(*w[4][len(w[4]) // 2])]
    length, english_of, best_class = {}, {}, {}
    for base, en, cls, _, points in ways:
        length[base] = length.get(base, 0) + sum(metres(a, b) for a, b in zip(points, points[1:]))
        if en and base not in english_of:
            english_of[base] = en
        best_class[base] = min(best_class.get(base, 9), cls)
    names = sorted(length, key=lambda n: (-length[n], n))
    index = {n: i for i, n in enumerate(names)}

    node_roads, node_where = {}, {}
    for base, _, _, refs, points in ways:
        for ref, point in zip(refs, points):
            node_roads.setdefault(ref, set()).add(index[base])
            node_where[ref] = point
    crossings = []
    by_pair = {}
    for ref, roads in node_roads.items():
        if len(roads) < 2:
            continue
        roads = sorted(roads)
        for i in range(len(roads)):
            for j in range(i + 1, len(roads)):
                pair = (roads[i], roads[j])
                point = node_where[ref]
                if any(metres(point, other) < MERGE_METRES for other in by_pair.get(pair, [])):
                    continue
                by_pair.setdefault(pair, []).append(point)
                crossings.append([round(point[0] * SCALE), round(point[1] * SCALE), pair[0], pair[1]])
    crossings.sort()

    way_rows = []
    for base, points in chains(ways):
        line = simplify(points, TOLERANCE)
        row = [index[base]]
        lat = lon = 0
        for y, x in line:
            fy, fx = round(y * SCALE), round(x * SCALE)
            row += [fy - lat, fx - lon]
            lat, lon = fy, fx
        way_rows.append(row)
    way_rows.sort(key=lambda r: (r[1], r[2]))

    data = {
        'source': 'OpenStreetMap contributors, from the extract taiwan.pbf',
        'licence': 'ODbL 1.0',
        'scale': SCALE,
        'kinds': KINDS,
        'landmarks': [[round(l[0] * SCALE), round(l[1] * SCALE), KINDS.index(l[2]), l[3] // 100, l[4]] + ([l[5]] if l[5] else [])
                      for l in kept],
        'roads': [[n] + ([english_of[n]] if n in english_of else []) for n in names],
        'ways': way_rows,
        'crossings': crossings,
    }
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    counts = {k: sum(1 for l in kept if l[2] == k) for k in KINDS}
    print(f'landmarks {len(kept)} {counts}; roads {len(names)}; ways {len(way_rows)}; crossings {len(crossings)}', file=sys.stderr)


if __name__ == '__main__':
    main(*sys.argv[1:4])
