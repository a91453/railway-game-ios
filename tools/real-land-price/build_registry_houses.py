#!/usr/bin/env python3
"""The houses the real-price registry (實價登錄) knows of where the bundled
buildings have none, as the app's
`Resources/RealWorld/taiwan_registry_houses.dat` (decision 1031).

    T=tools/real-land-price/build_land_price_grid.py
    U=tools/overture-footprint-tiles/usage_permits.py
    H=tools/real-land-price/build_registry_houses.py
    # the door-number points and the registry's kinds (see $T's docstring)
    python3 -I $U addresses 2026-11-18.0 addresses.parquet
    python3 -I $T registry registry_prices.tsv.gz 110S1 115S3
    # the registry's storeys (總樓層數), every season from 101S1
    python3 -I $U registry registry.tsv.gz 101S1 115S3
    # about 10 minutes
    python3 -I $H build registry_prices.tsv.gz registry.tsv.gz addresses.parquet \\
        RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles \\
        RailwayGameApp/Resources/RealWorld/taiwan_registry_houses.dat registry_houses.json

Run it again after the bundled buildings change (decision 1026's monthly
Overture refresh): a door number a new building now stands at drops out.
The game keeps its houses off the real buildings anyway, so a file a
month old does no harm, only a little less good.

Each sale of a house (房地 or 建物) names its door number, its kind
(建物型態) and how many storeys the building has (總樓層數). Its door
number is found in the counties' door-number points (`usage_permits`'s
tables, the same as the storeys of decision 1011), and when no bundled
building stands within `NEAR` metres of it (`NEAR_TALL` for a block of
flats or a tower, whose door is often on the street in front of a
forecourt), the building the sale was in is missing from the map: the
point goes in the file with its storeys (the count most of its sales
name; else its kind's `TYPICAL`) and its kind.

The file: `TWRH`, a version (UInt32, 1), a count (UInt32), then each point
by latitude then longitude: longitude and latitude in millionths of a
degree (Int32 each), storeys (UInt8) and kind (UInt8: `KINDS`'s index);
little-endian throughout. GamePresentation's `RegistryHouses` reads it.

Sources: Ministry of the Interior, Department of Land Administration,
real-price registry (不動產買賣實價登錄批次資料, data.gov.tw 18703); the
counties' door-number points through OpenAddresses and Overture Maps
(Open Government Data License, version 1.0); the bundled buildings
(Overture Maps, ODbL, and the cities' building maps).
"""

import collections
import gzip
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
import usage_permits as U  # noqa: E402

T = U.T
# The kinds of house, the file's codes, and the registry's 建物型態 each
# takes; a sale of any other kind (a factory, an office, a parking space,
# 其他) names no house the game draws.
KINDS = ('terrace', 'walkUp', 'midRise', 'tower')
OF_TYPE = {
    '透天厝': 0, '店面(店鋪)': 0, '農舍': 0,
    '公寓(5樓含以下無電梯)': 1, '套房(1房1廳1衛)': 1,
    '華廈(10層含以下有電梯)': 2,
    '住宅大樓(11層含以上有電梯)': 3, '辦公商業大樓': 3,
}
# Storeys a kind has when its sales name none, and the most it may have.
TYPICAL = (3, 4, 8, 15)
RANGE = ((1, 6), (2, 6), (4, 12), (8, 60))
# Metres from the nearest bundled building beyond which a door number's
# building is missing.
NEAR = 10.0
NEAR_TALL = 25.0
FIELDS = 15


def kinds(path):
    """(letter, address) → Counter of kinds over its sales of a house."""
    found = collections.defaultdict(collections.Counter)
    with gzip.open(path, 'rt', encoding='utf-8') as file:
        for line in file:
            parts = line.rstrip('\n').split('\t')
            if len(parts) != 2 + FIELDS:
                continue
            letter, fields = parts[0], parts[2:]
            what, address, kind = fields[1], fields[2], OF_TYPE.get(fields[9])
            if kind is None or ('房地' not in what and '建物' not in what):
                continue
            if '號' not in address or not U.single_address(address):
                continue
            found[(letter, address)][kind] += 1
    return found


def storeys(path):
    """(letter, address) → Counter of storeys over its sales."""
    found = collections.defaultdict(collections.Counter)
    with gzip.open(path, 'rt', encoding='utf-8') as file:
        for line in file:
            letter, text = line.rstrip('\n').split('\t', 1)
            text, count = text.rsplit('\t', 1)
            found[(letter, text)][int(count)] += 1
    return found


def located(sold, tall, addresses):
    """(lon, lat) → (Counter of kinds, Counter of storeys)."""
    tables = U.point_tables(addresses, sorted(set(U.REGISTRY_COUNTIES.values())))
    points = {}
    for (letter, address), counts in sorted(sold.items()):
        dataset = U.REGISTRY_COUNTIES.get(letter)
        if dataset not in tables:
            continue
        exact, whole, roads = tables[dataset]
        key = U.address_key(U.COUNTY.sub('', U.plain(address)), roads)
        point = (exact.get(key) or whole.get(key[:3])) if key is not None else None
        if point is None:
            continue
        kind_counts, storey_counts = points.setdefault(point, (collections.Counter(), collections.Counter()))
        kind_counts.update(counts)
        storey_counts.update(tall.get((letter, address), {}))
    return points


def nearest(points, archive):
    """Each point's distance to the nearest bundled building, metres, up to
    `NEAR_TALL` (beyond it, infinity)."""
    entries, *_ = U.read_archive(archive)
    by_tile = collections.defaultdict(list)
    for j, (lon, lat) in enumerate(points):
        gx, gy = U.global_units(lon, lat)
        by_tile[(int(gx) // T.EXTENT, int(gy) // T.EXTENT)].append((j, gx, gy))
    best = [math.inf] * len(points)
    for tx, ty in sorted(by_tile):
        metre = U.metre_of(ty)
        reach = NEAR_TALL * metre
        candidates = by_tile[(tx, ty)]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                tid = T.tile_id_of(tx + dx, ty + dy)
                if tid not in entries:
                    continue
                buildings, scale = U.buildings_of(gzip.decompress(entries[tid]))
                for _, _, _, rings in buildings:
                    outline = [((tx + dx) * T.EXTENT + x * scale, (ty + dy) * T.EXTENT + y * scale) for x, y in rings[0]]
                    xs = [p[0] for p in outline]
                    ys = [p[1] for p in outline]
                    west, east, north, south = min(xs) - reach, max(xs) + reach, min(ys) - reach, max(ys) + reach
                    for j, gx, gy in candidates:
                        if best[j] == 0 or not (west <= gx <= east and north <= gy <= south):
                            continue
                        if U.inside(gx, gy, outline):
                            best[j] = 0.0
                            continue
                        d = math.sqrt(min(T.segment_sq(gx, gy, *outline[k - 1], *outline[k])
                                          for k in range(len(outline)))) / metre
                        best[j] = min(best[j], d)
    return best


def house(kind_counts, storey_counts):
    """(storeys, kind) of a door number's sales."""
    kind = max(kind_counts, key=lambda k: (kind_counts[k], k))
    low, high = RANGE[kind]
    fitting = collections.Counter({s: n for s, n in storey_counts.items() if low <= s <= high})
    count = max(fitting, key=lambda s: (fitting[s], s)) if fitting else TYPICAL[kind]
    return count, kind


def build(prices, registry, addresses, archive, out, report_path):
    points = located(kinds(prices), storeys(registry), addresses)
    order = sorted(points, key=lambda p: (p[1], p[0]))
    distance = nearest(order, archive)
    kept = []
    for point, d in zip(order, distance):
        count, kind = house(*points[point])
        if d > (NEAR_TALL if kind >= 2 else NEAR):
            kept.append((point, count, kind))
    body = bytearray(b'TWRH')
    body += struct.pack('<II', 1, len(kept))
    for (lon, lat), count, kind in kept:
        body += struct.pack('<iiBB', round(lon * 1e6), round(lat * 1e6), count, kind)
    open(out, 'wb').write(body)
    by_kind = collections.Counter(KINDS[k] for _, _, k in kept)
    report = {
        'doorNumbers': len(points), 'missing': len(kept), 'byKind': dict(sorted(by_kind.items())),
        'storeys': {KINDS[k]: dict(sorted(collections.Counter(c for _, c, kk in kept if kk == k).items())) for k in range(len(KINDS))},
        'bytes': len(body),
    }
    json.dump(report, open(report_path, 'w'), ensure_ascii=False, indent=1)
    print(json.dumps({k: report[k] for k in ('doorNumbers', 'missing', 'byKind', 'bytes')}, ensure_ascii=False))


if __name__ == '__main__':
    command, *arguments = sys.argv[1:]
    if command == 'build':
        build(*arguments)
    else:
        sys.exit(__doc__)
