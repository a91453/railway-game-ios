#!/usr/bin/env python3
"""Taiwan's place names for naming new stations on real-world maps, as the
app's `Resources/RealWorld/taiwan_place_names.json` (ARCHITECTURE decision
159).

    python3 tools/place-names/build_place_names.py taiwan.pbf \\
        RailwayGameApp/Resources/RealWorld/taiwan_place_names.json

The extract is the one every other data tool reads (osmtoday.com's
`asia/taiwan.pbf`, read with pyosmium, BSD 2-Clause, `pip install osmium`;
decision 93). It takes some two minutes.

MapBuilder (the owner's reference, `MapBuilder/reference_snapshot/_next/
static/chunks/611-2cd22d6d6f5c40f4.js`, `el`) names a rail station after
the most local administrative area around it (`is_in`, `admin_level` up to
8, `name:en` first), asking Overpass each time. The game cannot ask a
server while the player builds, so the names are read here once:

- `places`: OpenStreetMap's settlements, the nodes tagged `place` with
  one of SETTLEMENTS and a name: Taiwan's hamlets and villages (聚落) and
  city neighbourhoods. A name with a Latin part after a space
  ("豐南 Cilamitay") keeps the Chinese part, and the Latin part is its
  English name when it has no `name:en`.
- `wards`: the villages and wards (村、里; `admin_level` 9), each at the
  middle of its outline's bounding box: they are many and small, so a point
  is near enough.
- `townships`: the townships and districts (鄉、鎮、市、區; `admin_level` 7
  and 8, MapBuilder's most local level), as their outlines simplified to
  about TOLERANCE degrees (Douglas-Peucker), so the game can say which one
  a station is in.

Wards and townships are named as stations are: without the suffix (中和區
→ 中和, "Zhonghe District" → "Zhonghe"), unless one character would be
left (北區, 東區 keep theirs).

Only Taiwan's: the extract reaches into Fujian, whose areas are named in
simplified characters (区、乡、镇、街道) and left out by SUFFIXES.

Coordinates are in 1e-5 degrees (about a metre), the rings' points as
differences from the one before. The data is OpenStreetMap's (ODbL 1.0),
credited in the game's data sources (`DataSourceCredits`).
"""
import json
import math
import os
import sys

import osmium

SETTLEMENTS = ('hamlet', 'village', 'locality', 'neighbourhood', 'isolated_dwelling', 'quarter')
# The suffixes of Taiwan's townships (7, 8) and wards (9), in traditional
# characters only.
SUFFIXES = {7: ('區', '鄉', '鎮', '市'), 8: ('區', '鄉', '鎮', '市'), 9: ('村', '里')}
EN_SUFFIXES = (' District', ' Township', ' City', ' Town', ' Village', ' Vilage')
TOLERANCE = 0.0003
SCALE = 100000


def chinese_and_latin(name):
    """'豐南 Cilamitay' → ('豐南', 'Cilamitay'); '九份' → ('九份', None)."""
    head, _, tail = name.partition(' ')
    if tail and any('一' <= ch <= '鿿' for ch in head) and tail.isascii():
        return head, tail.strip()
    return name, None


def names(tags):
    zh = tags.get('name:zh-Hant') or tags.get('name:zh-TW') or tags.get('name')
    zh, latin = chinese_and_latin(zh)
    en = tags.get('name:en') or latin
    return zh, en


def station_names(zh, en):
    """An area's names without its suffix: ('中和區', 'Zhonghe District')
    → ('中和', 'Zhonghe'); ('北區', 'North District') as they are."""
    if len(zh) < 3:
        return zh, en
    if en:
        for suffix in EN_SUFFIXES:
            if en.endswith(suffix):
                en = en[:-len(suffix)]
                break
    return zh[:-1], en


def fixed(value):
    return int(round(value * SCALE))


def simplify(points, tolerance):
    """Douglas-Peucker on (lon, lat); keeps the first and last point."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (ax, ay), (bx, by) = points[first], points[last]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, index = 0.0, None
        for i in range(first + 1, last):
            px, py = points[i]
            if length == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * (px - ax) - dx * (py - ay)) / length
            if d > worst:
                worst, index = d, i
        if index is not None and worst > tolerance:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [p for p, k in zip(points, keep) if k]


def encode_ring(points):
    """A closed ring as [lat0, lon0, dlat1, dlon1, …] in 1e-5 degrees,
    without the repeated last point."""
    if points[0] == points[-1]:
        points = points[:-1]
    out, last = [], (0, 0)
    for lon, lat in points:
        lat5, lon5 = fixed(lat), fixed(lon)
        if (lat5, lon5) == last and out:
            continue
        out += [lat5 - last[0], lon5 - last[1]]
        last = (lat5, lon5)
    return out


def read(path):
    places, wards, townships = [], [], []
    newest = ['']

    def stamp(obj):
        t = obj.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
        if t > newest[0]:
            newest[0] = t

    processor = osmium.FileProcessor(path).with_locations() \
        .with_areas(osmium.filter.TagFilter(('boundary', 'administrative'))) \
        .with_filter(osmium.filter.EmptyTagFilter())
    for obj in processor:
        tags = obj.tags
        if obj.is_node():
            if tags.get('place') in SETTLEMENTS and tags.get('name'):
                zh, en = names(tags)
                places.append([fixed(obj.location.lat), fixed(obj.location.lon), zh, en])
                stamp(obj)
            continue
        if not obj.is_area() or tags.get('boundary') != 'administrative' or not tags.get('name'):
            continue
        try:
            level = int(tags.get('admin_level', ''))
        except ValueError:
            continue
        zh, en = names(tags)
        if level not in SUFFIXES or not zh.endswith(SUFFIXES[level]):
            continue
        outers = [[(n.lon, n.lat) for n in outer] for outer in obj.outer_rings()]
        if not outers:
            continue
        stamp(obj)
        full = zh
        zh, en = station_names(zh, en)
        if level == 9:
            lons = [p[0] for ring in outers for p in ring]
            lats = [p[1] for ring in outers for p in ring]
            wards.append([fixed((min(lats) + max(lats)) / 2), fixed((min(lons) + max(lons)) / 2), zh, en, full])
            continue
        rings = []
        for outer in obj.outer_rings():
            rings.append([(n.lon, n.lat) for n in outer])
            rings += [[(n.lon, n.lat) for n in inner] for inner in obj.inner_rings(outer)]
        encoded = [encode_ring(simplify(ring, TOLERANCE)) for ring in rings]
        encoded = [ring for ring in encoded if len(ring) >= 6]
        if encoded:
            townships.append({'name': zh, 'en': en, 'level': level, 'rings': encoded})
    # A settlement named as a village or ward is (科園里) is only its label:
    # the ward is there already.
    ward_names = {w[4] for w in wards}
    places = [p for p in places if p[2] not in ward_names]
    wards = [w[:4] for w in wards]
    # One entry for the same name at the same point (a node mapped twice).
    places = sorted({(p[0], p[1], p[2]): p for p in places}.values())
    wards = sorted({(w[0], w[1], w[2]): w for w in wards}.values())
    townships.sort(key=lambda t: (t['name'], t['rings'][0][:2]))
    return places, wards, townships, newest[0]


def main():
    extract, out = sys.argv[1], sys.argv[2]
    places, wards, townships, newest = read(extract)
    data = {
        'source': f'OpenStreetMap contributors, from the extract {os.path.basename(extract)}',
        'licence': 'ODbL 1.0',
        'osmData': newest,
        'scale': SCALE,
        'places': places,
        'wards': wards,
        'townships': townships,
    }
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    print(f'{len(places)} places, {len(wards)} wards, {len(townships)} townships, '
          f'{os.path.getsize(out) / 1e6:.2f} MB, data to {newest}')


if __name__ == '__main__':
    main()
