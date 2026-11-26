#!/usr/bin/env python3
"""Storeys from New Taipei's and Taipei's usage permits (使用執照) on the
bundled Taiwan buildings (decision 1011).

A usage permit is the city's own record of a finished building: its
storeys above ground, height, floor area and every door number. The
permits have addresses and no coordinates, so each address is found in
the cities' door-number points (門牌坐標, as Overture Maps' addresses
theme carries them from OpenAddresses), and a building whose outline
holds one of the permit's points (or is the nearest within NEAR metres)
takes the permit's storeys. The permits come before OpenStreetMap's
tags and the guess, after Taipei's permit map (decision 389's order was
a city's building map, the tags, the permit map, the guess): matched
this way they agree with the permit map on 97 % of the buildings both
reach, and with the tags on 57 %. Everything else in the archive stays
byte for byte.

    U=tools/overture-footprint-tiles/usage_permits.py
    # about 2 minutes: the door-number points of Taipei and New Taipei
    python3 -I $U addresses 2026-11-18.0 addresses.parquet
    # the permits (data.gov.tw 123639 and 128203; links in the README)
    curl -o ntpc.csv https://data.ntpc.gov.tw/api/datasets/c1487d7b-fff1-43d3-a2ce-4716eab4d286/csv/file
    curl -o taipei.xml https://data.taipei/api/dataset/c876ff02-af2e-4eb8-bd33-d444f5052733/resource/0f3f9675-8356-4f1a-9908-1ce8892012fa/download
    # about 3 minutes
    python3 -I $U apply RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles \\
        addresses.parquet ntpc.csv taipei.xml out.pmtiles usage_permits.json
    cp out.pmtiles RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles

Needs `pip install duckdb` for `addresses` only (decision 93).
"""

import collections
import csv
import gzip
import hashlib
import json
import math
import os
import re
import struct
import sys
import unicodedata
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))

import build_footprint_tiles as T  # noqa: E402

BUCKET = 'https://overturemaps-us-west-2.s3.us-west-2.amazonaws.com/'
# OpenAddresses' sources inside Overture's addresses: the two cities'
# door-number points (Open Government Data License, version 1.0).
DATASETS = {'tw/nwt/regionwide': '新北市', 'tw/tpe/regionwide': '台北市'}
# A footprint over this many times the permit's ground area (plus a
# terrace house's worth) is a row or a block the outlines merged, so the
# permit's storeys are not all of it.
AREA_SLACK = 2.5
AREA_EXTRA = 60.0
# The lowest storey a permit may give, in metres.
LOWEST_STOREY = 2.2
# Metres from an outline a door-number point may stand and still be its.
NEAR = 10.0
LICENCE = ('Storeys: New Taipei City Government, building usage permits (data.gov.tw 123639); Taipei City '
           'Construction Management Office, usage permit summaries (data.gov.tw 128203); door-number points of '
           'both cities through OpenAddresses and Overture Maps (Open Government Data License, version 1.0)')

CHINESE = '〇一二三四五六七八九'


# --- addresses ----------------------------------------------------------------

def addresses(release, out):
    """The two cities' door-number points from Overture's addresses theme."""
    import duckdb
    import urllib.request
    prefix = f'release/{release}/theme=addresses/type=address/'
    keys = re.findall(r'<Key>(.*?\.parquet)</Key>',
                      urllib.request.urlopen(BUCKET + '?list-type=2&prefix=' + prefix).read().decode())
    urls = [BUCKET + k for k in keys]
    connection = duckdb.connect()
    connection.sql('INSTALL httpfs; LOAD httpfs; SET threads = 32')
    listed = '[' + ','.join(f"'{u}'" for u in urls) + ']'
    boxes = {}
    for name, group, column, low, high in connection.sql(f"""
        SELECT file_name, row_group_id, path_in_schema, stats_min_value, stats_max_value
        FROM parquet_metadata({listed}) WHERE path_in_schema IN ('bbox, xmin', 'bbox, ymin')
    """).fetchall():
        boxes.setdefault((name, group), {})[column] = (float(low), float(high))
    files = sorted({name for (name, _), box in boxes.items()
                    if box['bbox, xmin'][1] >= 121.2 and box['bbox, xmin'][0] <= 122.1
                    and box['bbox, ymin'][1] >= 24.6 and box['bbox, ymin'][0] <= 25.4})
    files = '[' + ','.join(f"'{u}'" for u in files) + ']'
    datasets = ','.join(f"'{d}'" for d in DATASETS)
    connection.sql(f"""
        COPY (SELECT sources[1].dataset AS dataset, address_levels[2].value AS district, street, number, unit,
                     bbox.xmin AS lon, bbox.ymin AS lat
              FROM read_parquet({files}) WHERE country = 'TW' AND sources[1].dataset IN ({datasets})
              ORDER BY id) TO '{out}' (FORMAT parquet, COMPRESSION zstd)
    """)


def plain(text):
    """Full-width digits and letters to plain ones, 臺 as 台, no spaces."""
    return unicodedata.normalize('NFKC', text or '').replace('臺', '台').replace(' ', '').replace('　', '')


def road(text):
    """A road with its section, lane and alley, sections in Chinese
    numerals as the door-number points write them (二段, not 2段)."""
    return re.sub(r'(\d+)段', lambda m: CHINESE[int(m.group(1))] + '段' if len(m.group(1)) == 1
                  else m.group(0), text)


def address_key(text, roads):
    """(district, road, number, sub-number) of a permit's address, or None.
    臺北市松山區南京東路五段251巷22弄28號 2樓 → (松山區, 南京東路五段251巷22弄, 28, 0).
    Addresses before 2010 name New Taipei's districts as towns (新店市,
    林口鄉) or bare (蘆洲); a village (里, 村) and a neighbourhood (鄰) before
    the road are dropped by taking the longest end of the text before the
    number that is one of the district's roads (`roads`: district → roads
    of the door-number points)."""
    text = re.sub(r'^(?:新北市|台北市|台北縣)+', '', plain(text))
    district = next((d for d in sorted(roads, key=len, reverse=True) if text.startswith(d[:-1])), None)
    if district is None:
        return None
    text = text[len(district) - 1:]
    text = text[1:] if text[:1] in '區市鎮鄉' else text
    m = re.match(r'(?P<road>.+?)(?P<number>\d+)(?:[之-](?P<sub1>\d+))?號(?:之(?P<sub2>\d+))?', text)
    if not m:
        return None
    raw = road(re.sub(r'\d+鄰', '', m.group('road')))
    known = roads[district]
    street = next((raw[i:] for i in range(len(raw)) if raw[i:] in known), raw)
    sub = int(m.group('sub1') or m.group('sub2') or 0)
    return district, street, int(m.group('number')), sub


def point_table(path):
    """(district, road, number, sub-number) → (lon, lat) of the door-number
    points, (district, road, number) → the first point of the number, and
    district → its roads."""
    import duckdb
    exact, whole, roads = {}, {}, collections.defaultdict(set)
    for district, street, number, unit, lon, lat in duckdb.connect().sql(
            f"SELECT district, street, number, unit, lon, lat FROM read_parquet('{path}')").fetchall():
        n = re.match(r'(\d+)', plain(number))
        if not n or not district:
            continue
        s = re.search(r'之(\d+)', plain(unit))
        key = (plain(district), road(plain(street)), int(n.group(1)))
        roads[key[0]].add(key[1])
        exact.setdefault(key + (int(s.group(1)) if s else 0,), (lon, lat))
        whole.setdefault(key, (lon, lat))
    return exact, whole, roads


# --- permits ------------------------------------------------------------------

def number(text):
    m = re.search(r'\d+(?:\.\d+)?', plain(text))
    return float(m.group(0)) if m else 0.0


def ntpc_permits(path):
    """New Taipei's usage permits: (permit, storeys, height m, ground m²,
    addresses)."""
    out = []
    with open(path, encoding='utf-8-sig', newline='') as file:
        for row in csv.DictReader(file):
            ground = sum(float(v) for v in re.findall(r'(\d+(?:\.\d+)?)㎡', plain(row['building_area'])))
            out.append((row['license_number'], int(number(row['number_of_stories'])),
                        number(row['building_height']), ground,
                        [a for a in re.split(r'[、,;；]', row['house_address']) if a.strip()]))
    return out


def taipei_permits(path):
    """Taipei's usage permits of new buildings (新建), as `ntpc_permits`."""
    out = []
    for _, el in ET.iterparse(path):
        if el.tag != 'Data':
            continue
        if el.findtext('建造類別') == '新建':
            out.append((el.findtext('執照號碼'), int(number(el.findtext('建物資訊/地上層數'))),
                        number(el.findtext('建物高度')),
                        number(el.findtext('建物面積/建築面積')),
                        [a.text for a in el.findall('建築地點/地址') if a.text]))
        el.clear()
    return out


# --- apply --------------------------------------------------------------------

def hilbert_xy(tid):
    """(x, y) of a z16 tile id (`build_basemap.tile_id`'s inverse)."""
    first = sum(4 ** z for z in range(T.ZOOM))
    d = tid - first
    x = y = 0
    s = 1
    n = 1 << T.ZOOM
    while s < n:
        rx = 1 & (d // 2)
        ry = 1 & (d ^ rx)
        if ry == 0:
            if rx == 1:
                x, y = s - 1 - x, s - 1 - y
            x, y = y, x
        x += s * rx
        y += s * ry
        d //= 4
        s *= 2
    return x, y


def global_units(lon, lat):
    """A point in working units of the whole z16 grid (`EXTENT` a tile)."""
    tx, ty = T.tile_of(lon, lat)
    return tx * T.EXTENT, ty * T.EXTENT


def read_archive(path):
    data = open(path, 'rb').read()
    (_, _, meta_offset, meta_length) = struct.unpack_from('<4Q', data, 8)
    metadata = json.loads(gzip.decompress(data[meta_offset:meta_offset + meta_length]))
    bounds = [v / 1e7 for v in struct.unpack_from('<4i', data, 102)]
    center = struct.unpack_from('<B2i', data, 118)
    return T.read_directory(data), metadata, bounds, (center[1] / 1e7, center[2] / 1e7, center[0])


def buildings_of(raw):
    """A tile's buildings (unzipped, version 2 or 3) as (attribute offset,
    attribute length, attributes, rings in the tile's own units), and the
    tile's scale to working units."""
    at = 0

    def read():
        nonlocal at
        value = shift = 0
        while True:
            byte = raw[at]
            at += 1
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                return value

    def signed():
        v = read()
        return (v >> 1) ^ -(v & 1)

    version = read()
    scale = 1 if version == 2 else T.EXTENT // T.WRITTEN_EXTENT if hasattr(T, 'WRITTEN_EXTENT') else 2
    cursor = [0, 0]
    out = []
    for _ in range(read()):
        start = at
        attributes = read()
        length = at - start
        rings = []
        for _ in range(read()):
            ring = []
            for _ in range(read()):
                cursor[0] += signed()
                cursor[1] += signed()
                ring.append((cursor[0], cursor[1]))
            rings.append(ring)
        out.append((start, length, attributes, rings))
    assert at == len(raw)
    return out, scale


def with_attributes(raw, changes):
    """`raw` with the attribute varints at the offsets of `changes`
    ({offset: (old length, new attributes)}) rewritten."""
    out = bytearray()
    last = 0
    for offset in sorted(changes):
        length, attributes = changes[offset]
        out += raw[last:offset]
        T.varint(attributes, out)
        last = offset + length
    out += raw[last:]
    return bytes(out)


def metre_of(ty):
    """Working units a metre in row `ty` of the z16 tiles."""
    lat = math.atan(math.sinh(math.pi * (1 - 2 * (ty + 0.5) / (1 << T.ZOOM))))
    return 1 / (T.UNIT * math.cos(lat))


def inside(x, y, ring):
    hit = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def believable(storeys, height):
    """Whether a permit's storeys can be its height's: New Taipei's
    permits before 2010 often hold the households or the floor area in
    the storeys (72 storeys 8.8 m high), so a permit with no height, or
    with storeys under LOWEST_STOREY m each (a metre or two of roof
    besides), is left out."""
    return height > 0 and storeys * LOWEST_STOREY <= height + 4


def apply(archive, address_path, ntpc_path, taipei_path, out, report_path):
    exact, whole, roads = point_table(address_path)
    permits = [('ntpc',) + p for p in ntpc_permits(ntpc_path)] + [('taipei',) + p for p in taipei_permits(taipei_path)]
    found = collections.Counter()
    # Working-unit points of the permits, by tile: (x, y, permit).
    points = []
    by_tile = collections.defaultdict(list)
    for index, (city, _, storeys, height, ground, addresses) in enumerate(permits):
        if storeys <= 0:
            found[city + 'NoStoreys'] += 1
            continue
        if not believable(storeys, height):
            found[city + 'StoreysAgainstHeight'] += 1
            continue
        mine = set()
        for text in addresses:
            key = address_key(text, roads)
            if key is None:
                continue
            point = exact.get(key) or whole.get(key[:3])
            if point:
                mine.add(point)
        found[city + ('Found' if mine else 'NotFound')] += 1
        for lon, lat in sorted(mine):
            gx, gy = global_units(lon, lat)
            by_tile[(int(gx) // T.EXTENT, int(gy) // T.EXTENT)].append(len(points))
            points.append((gx, gy, index))
    print(json.dumps(found), file=sys.stderr)

    entries, metadata, bounds, center = read_archive(archive)
    replaced = {T.STOREYS_FROM.index('guess'), T.STOREYS_FROM.index('tags')}
    permits_from = T.STOREYS_FROM.index('permits')
    # Each point's building: the outline holding it, else the nearest
    # within NEAR metres (door-number points often stand at the door, just
    # outside the outline). (distance, tile id, offset) per point.
    best = {}
    tiles, meta = {}, {}
    near = {(tx + dx, ty + dy) for tx, ty in by_tile for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    for tx, ty in sorted(near):
        tid = T.tile_id_of(tx, ty)
        if tid not in entries:
            continue
        candidates = [j for dx in (-1, 0, 1) for dy in (-1, 0, 1) for j in by_tile.get((tx + dx, ty + dy), ())]
        if not candidates:
            continue
        raw = gzip.decompress(entries[tid])
        buildings, scale = buildings_of(raw)
        tiles[tid] = raw
        metre = metre_of(ty)
        reach = NEAR * metre
        for offset, length, attributes, rings in buildings:
            outline = [(tx * T.EXTENT + x * scale, ty * T.EXTENT + y * scale) for x, y in rings[0]]
            xs = [p[0] for p in outline]
            ys = [p[1] for p in outline]
            west, east, north, south = min(xs) - reach, max(xs) + reach, min(ys) - reach, max(ys) + reach
            for j in candidates:
                gx, gy, _ = points[j]
                if not (west <= gx <= east and north <= gy <= south):
                    continue
                if inside(gx, gy, outline):
                    distance = 0.0
                else:
                    distance = math.sqrt(min(T.segment_sq(gx, gy, *outline[k - 1], *outline[k])
                                             for k in range(len(outline)))) / metre
                    if distance > NEAR:
                        continue
                choice = (distance, tid, offset)
                if j not in best or choice < best[j]:
                    best[j] = choice
                    meta[(tid, offset)] = (length, attributes, abs(T.area(outline)) / 2 / metre ** 2)
    held = collections.defaultdict(set)
    for j, (distance, tid, offset) in best.items():
        held[(tid, offset)].add(points[j][2])

    origins_hit = collections.Counter()
    changes = collections.defaultdict(dict)
    too_large = not_fitting = 0
    storeys_before, storeys_after = collections.Counter(), collections.Counter()
    hit_permits = set()
    agreement = collections.defaultdict(collections.Counter)
    changed_from = collections.Counter()
    for (tid, offset), holding in sorted(held.items()):
        length, attributes, size = meta[(tid, offset)]
        origin = attributes >> 5 & 7
        origins_hit[T.STOREYS_FROM[origin]] += 1
        storeys = 0
        for i in sorted(holding):
            _, _, value, _, ground, _ = permits[i]
            if ground > 0 and size > AREA_SLACK * ground + AREA_EXTRA:
                too_large += origin in replaced
                continue
            if not T.permit_fits(value, size):
                # A tower's permit on a footprint that also holds its podium
                # (Taipei 101 and its mall are one outline): the podium's
                # permit is not all of it either, so none is taken.
                not_fitting += origin in replaced
                storeys = -1
                break
            storeys = max(storeys, min(255, value))
        if storeys > 0 and origin in replaced:
            hit_permits.update(holding)
        if storeys > 0:
            # How the permits agree with what the building already had.
            had = attributes >> 8
            agreement[T.STOREYS_FROM[origin]][
                'same' if had == storeys else 'withinOne' if abs(had - storeys) == 1 else 'apart'] += 1

        if storeys > 0 and origin in replaced:
            changed_from[T.STOREYS_FROM[origin]] += 1
            storeys_before[attributes >> 8] += 1
            storeys_after[storeys] += 1
            changes[tid][offset] = (length, storeys << 8 | permits_from << 5 | (attributes & 31))
    changed = {}
    for tid, edits in changes.items():
        entries[tid] = gzip.compress(with_attributes(tiles[tid], edits), 9, mtime=0)
        changed[tid] = len(edits)

    from build_basemap import write_pmtiles
    metadata['attribution'] = metadata.get('attribution', '') + '. ' + LICENCE
    write_pmtiles(out, list(entries.items()), metadata, tuple(bounds), center,
                  tile_type=0, tile_compression=2, zooms=(T.ZOOM, T.ZOOM))
    whole_bytes = open(out, 'rb').read()
    report = {
        'decision': 1011,
        'permits': {k: v for k, v in sorted(found.items())},
        'buildingsWithAPoint': dict(sorted(origins_hit.items())),
        'pointsInside': sum(1 for d, _, _ in best.values() if d == 0),
        'pointsNear': sum(1 for d, _, _ in best.values() if d > 0),
        'pointsWithNoBuilding': len(points) - len(best),
        'agreementWithKnown': {k: dict(sorted(v.items())) for k, v in sorted(agreement.items())},
        'buildingsChanged': sum(changed.values()),
        'changedFrom': dict(sorted(changed_from.items())),
        'permitsUsed': len(hit_permits),
        'leftOutFootprintTooLarge': too_large,
        'leftOutTowerOnPodium': not_fitting,
        'storeysBefore': dict(sorted(storeys_before.items())),
        'storeysAfter': dict(sorted(storeys_after.items())),
        'archiveBytes': len(whole_bytes),
        'sha256': hashlib.sha256(whole_bytes).hexdigest(),
    }
    with open(report_path, 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    commands = {'addresses': addresses, 'apply': apply}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
