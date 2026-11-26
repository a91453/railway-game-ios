#!/usr/bin/env python3
"""Storeys from the usage permits (使用執照) of New Taipei, Taipei, Tainan
and Hsinchu City, and elsewhere from the real-price registry (實價登錄),
on the bundled Taiwan buildings (decision 1011).

A usage permit is the city's own record of a finished building: its
storeys above ground, height, floor area and every door number. The
permits have addresses and no coordinates, so each address is found in
the cities' door-number points (門牌坐標, as Overture Maps' addresses
theme carries them from OpenAddresses), and a building whose outline
holds one of the permit's points (or is the nearest within NEAR metres)
takes the permit's storeys. Tainan's permits name parcels, not door
numbers: each parcel is found in Tainan's parcel centres, and only the
outline holding the centre takes it. Where no permit reaches, the
real-price registry's sales and pre-sales of every county name a door
number and the building's storeys (總樓層數): a building whose door
numbers' sales mostly name one count takes it. The permits come before OpenStreetMap's
tags and the guess, after Taipei's permit map (decision 389's order was
a city's building map, the tags, the permit map, the guess): matched
this way they agree with the permit map on 97 % of the buildings both
reach, and with the tags on 57 %. Everything else in the archive stays
byte for byte.

    U=tools/overture-footprint-tiles/usage_permits.py
    # about 3 minutes: the door-number points of Taiwan's counties
    python3 -I $U addresses 2026-11-18.0 addresses.parquet
    # about 5 minutes: the registry's door numbers and storeys, every
    # season from 101S1 (data.gov.tw 18703)
    python3 -I $U registry registry.tsv.gz
    # the permits (data.gov.tw 123639 and 128203; links in the README)
    curl -o ntpc.csv https://data.ntpc.gov.tw/api/datasets/c1487d7b-fff1-43d3-a2ce-4716eab4d286/csv/file
    curl -o taipei.xml https://data.taipei/api/dataset/c876ff02-af2e-4eb8-bd33-d444f5052733/resource/0f3f9675-8356-4f1a-9908-1ce8892012fa/download
    # Hsinchu City's permits (data.gov.tw 163823): its site refuses this
    # cloud, so the copy in a91453/railway-reference-private,
    # Railway/building-storeys-snapshot-2026-11/新竹市/
    # Tainan's permits (data.gov.tw 121026) and parcel centres (176361):
    # every CSV of each into a folder of its own (tainan_permits/,
    # tainan_parcels/), the links in data.gov.tw's dataset pages
    # about a minute
    python3 -I $U apply RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles out.pmtiles \\
        usage_permits.json addresses=addresses.parquet ntpc=ntpc.csv taipei=taipei.xml \\
        hsinchu=hsinchu.csv tainan=tainan_permits:tainan_parcels registry=registry.tsv.gz
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
# A footprint over this many times the permit's ground area (plus a
# terrace house's worth) is a row or a block the outlines merged, so the
# permit's storeys are not all of it.
AREA_SLACK = 2.5
AREA_EXTRA = 60.0
# A storey in the game (Map3DFootprints.storeyHeight), in metres.
STOREY_METRES = 3.2
# The lowest storey a permit may give, in metres.
LOWEST_STOREY = 2.2
# Metres from an outline a door-number point may stand and still be its.
NEAR = 10.0
# A parcel's centre lies inside its house; one outside every outline is a
# yard or a field, and the nearest building may be the neighbour's.
NEAR_PARCEL = 0.0
LICENCE = ('Storeys: New Taipei City Government, building usage permits (data.gov.tw 123639); Taipei City '
           'Construction Management Office, usage permit summaries (data.gov.tw 128203); Tainan City Government, '
           'usage permits (121026) and parcel centres (176361); Hsinchu City Government, usage permits (163823); '
           'Ministry of the Interior, Department of Land Administration, real-price registry (18703); '
           'the counties\' door-number points through OpenAddresses and Overture Maps '
           '(Open Government Data License, version 1.0)')

CHINESE = '〇一二三四五六七八九'
# Cities whose permits name parcels, not door numbers.
PARCEL_CITIES = {'tainan'}
# Cities whose permits give no height.
NO_HEIGHT = {'hsinchu'}


# --- addresses ----------------------------------------------------------------

def addresses(release, out):
    """Taiwan's door-number points from Overture's addresses theme: every
    county's OpenAddresses source (tw/<county>/regionwide)."""
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
                    if box['bbox, xmin'][1] >= 118.1 and box['bbox, xmin'][0] <= 122.1
                    and box['bbox, ymin'][1] >= 21.8 and box['bbox, ymin'][0] <= 26.4})
    files = '[' + ','.join(f"'{u}'" for u in files) + ']'
    connection.sql(f"""
        COPY (SELECT sources[1].dataset AS dataset, address_levels[2].value AS district, street, number, unit,
                     bbox.xmin AS lon, bbox.ymin AS lat
              FROM read_parquet({files}) WHERE country = 'TW' AND sources[1].dataset LIKE 'tw/%'
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


def point_tables(path, datasets):
    """dataset → ((district, road, number, sub-number) → (lon, lat) of the
    door-number points, (district, road, number) → the first point of the
    number, district → its roads)."""
    import duckdb
    tables = {}
    listed = ','.join(f"'{d}'" for d in datasets)
    for dataset, district, street, number, unit, lon, lat in duckdb.connect().sql(
            f"SELECT dataset, district, street, number, unit, lon, lat FROM read_parquet('{path}') "
            f"WHERE dataset IN ({listed})").fetchall():
        n = re.match(r'(\d+)', plain(number))
        if not n or not district:
            continue
        exact, whole, roads = tables.setdefault(dataset, ({}, {}, collections.defaultdict(set)))
        s = re.search(r'之(\d+)', plain(unit))
        key = (plain(district), road(plain(street)), int(n.group(1)))
        roads[key[0]].add(key[1])
        exact.setdefault(key + (int(s.group(1)) if s else 0,), (lon, lat))
        whole.setdefault(key, (lon, lat))
    return tables


def point_table(path, datasets=('tw/nwt/regionwide', 'tw/tpe/regionwide')):
    """The door-number points of `datasets` as one table (`point_tables`)."""
    exact, whole, roads = {}, {}, collections.defaultdict(set)
    tables = point_tables(path, datasets)
    for dataset in datasets:
        e, w, r = tables.get(dataset, ({}, {}, {}))
        for k, v in e.items():
            exact.setdefault(k, v)
        for k, v in w.items():
            whole.setdefault(k, v)
        for k, v in r.items():
            roads[k] |= v
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


def hsinchu_permits(path):
    """Hsinchu City's usage permits (data.gov.tw 163823): one door number
    each and no height; the ground area is the floor area over the
    storeys."""
    out = []
    with open(path, encoding='utf-8-sig', newline='') as file:
        for row in csv.DictReader(file):
            storeys = int(number(row['地上層數']))
            floor = number(row['總樓地板面積'])
            out.append((row['執照字號'], storeys, 0.0, floor / storeys if storeys > 0 else 0.0,
                        [row['門牌地址']] if row['門牌地址'].strip() else []))
    return out


def citywide_key(text, roads):
    """(road, number, sub-number) of an address that names no district
    (新竹市復興里18鄰鐵道路二段9號4樓之1 → (鐵道路二段, 9, 0)): the
    longest end of the text before the number that is one of the city's
    roads."""
    text = re.sub(r'^(?:新竹市)', '', plain(text))
    text = re.sub(r'^[^\d]*?[東北]區|^香山區', '', text)
    m = re.match(r'(?P<road>.+?)(?P<number>\d+)(?:[之-](?P<sub1>\d+))?號(?:之(?P<sub2>\d+))?', text)
    if not m:
        return None
    raw = road(re.sub(r'\d+鄰', '', m.group('road')))
    street = next((raw[i:] for i in range(len(raw)) if raw[i:] in roads), None)
    if street is None:
        return None
    return street, int(m.group('number')), int(m.group('sub1') or m.group('sub2') or 0)


# --- real-price registry --------------------------------------------------------

# The registry's file letters (lvr_landcsv.zip) → the county's door-number
# points in OpenAddresses (Yilan, Nantou, Chiayi City and Lienchiang have
# none there). L, R and S are Taichung, Tainan and Kaohsiung counties of
# before 2010.
REGISTRY_COUNTIES = {
    'a': 'tw/tpe/regionwide', 'b': 'tw/txg/regionwide', 'c': 'tw/kee/regionwide', 'd': 'tw/tnn/regionwide',
    'e': 'tw/khh/regionwide', 'f': 'tw/nwt/regionwide', 'h': 'tw/tao/regionwide', 'j': 'tw/hsq/regionwide',
    'k': 'tw/mia/regionwide-zh', 'l': 'tw/txg/regionwide', 'n': 'tw/cha/regionwide', 'o': 'tw/hsz/regionwide',
    'p': 'tw/yun/regionwide', 'q': 'tw/cyq/regionwide', 'r': 'tw/tnn/regionwide', 's': 'tw/khh/regionwide',
    't': 'tw/pif/regionwide', 'u': 'tw/hua/regionwide', 'v': 'tw/ttt/regionwide', 'w': 'tw/kin/regionwide',
    'x': 'tw/pen/regionwide',
}
REGISTRY_URL = 'https://plvr.land.moi.gov.tw/DownloadSeason?season={}&type=zip&fileName=lvr_landcsv.zip'
COUNTY = re.compile(r'^(?:台北|新北|桃園|台中|台南|高雄|基隆|新竹|嘉義|苗栗|彰化|南投|雲林|屏東|宜蘭|花蓮|台東|澎湖|金門|連江)[縣市]')


def chinese_storeys(text):
    """十五層 → 15, 二十四層 → 24, 八層 → 8, 15 → 15; 0 when it is not a
    count (見其他登記事項, 地下層)."""
    text = plain(text).removesuffix('層')
    if text.isdigit():
        return int(text)
    if not text or any(c not in CHINESE + '十' for c in text):
        return 0
    tens, _, ones = text.rpartition('十')
    if '十' not in text:
        return CHINESE.index(text) if len(text) == 1 else 0
    return (CHINESE.index(tens) if tens else 1) * 10 + (CHINESE.index(ones) if ones else 0)


def registry(out, first='101S1', last='115S4'):
    """Every season's door number and storeys (總樓層數) of the real-price
    registry's sales and pre-sales (實價登錄, data.gov.tw 18703; the
    Ministry of the Interior's Department of Land Administration), as
    `<letter>\\t<address>\\t<storeys>` lines: no price, no date, no floor
    area. A season the site has not published yet is skipped."""
    import io
    import tempfile
    import urllib.request
    import zipfile
    csv.field_size_limit(1 << 30)
    year, quarter = int(first[:-2]), int(first[-1])
    rows = 0
    with gzip.open(out, 'wt', encoding='utf-8') as file:
        while f'{year}S{quarter}' <= last:
            season = f'{year}S{quarter}'
            with tempfile.TemporaryFile() as zipped:
                try:
                    with urllib.request.urlopen(REGISTRY_URL.format(season), timeout=600) as response:
                        while chunk := response.read(1 << 20):
                            zipped.write(chunk)
                    archive = zipfile.ZipFile(zipped)
                except (OSError, zipfile.BadZipFile) as error:
                    print(season, 'skipped:', error, file=sys.stderr)
                    archive = None
                for name in archive.namelist() if archive else ():
                    base = name.split('/')[-1]
                    if not base.endswith(('_lvr_land_a.csv', '_lvr_land_b.csv')):
                        continue
                    lines = csv.reader(io.StringIO(archive.read(name).decode('utf-8-sig', 'replace')))
                    head = next(lines, [])
                    next(lines, None)
                    if '總樓層數' not in head or '土地位置建物門牌' not in head:
                        continue
                    at, total = head.index('土地位置建物門牌'), head.index('總樓層數')
                    for row in lines:
                        if len(row) <= max(at, total):
                            continue
                        storeys = chinese_storeys(row[total])
                        if storeys > 0 and '號' in row[at]:
                            address = re.sub(r'\s', ' ', row[at])
                            file.write(f'{base[0].lower()}\t{address}\t{storeys}\n')
                            rows += 1
            print(season, rows, file=sys.stderr, flush=True)
            year, quarter = (year, quarter + 1) if quarter < 4 else (year + 1, 1)


def single_address(text):
    """The registry's address when it names one door number: not a range
    (18號2樓~18號6樓, 1~17單號) or a list (；, 等戶)."""
    return not re.search(r'[~～;；、]|等戶|單號|雙號', text)


def registry_points(path, addresses):
    """(lon, lat) → Counter of storeys over the registry's sales at that
    door number; with the county letters no door-number points were found
    for."""
    tables = point_tables(addresses, sorted(set(REGISTRY_COUNTIES.values())))
    seen = collections.defaultdict(collections.Counter)
    with gzip.open(path, 'rt', encoding='utf-8') as file:
        for line in file:
            letter, text = line.rstrip('\n').split('\t', 1)
            text, storeys = text.rsplit('\t', 1)
            if single_address(text):
                seen[(letter, text)][int(storeys)] += 1
    points = collections.defaultdict(collections.Counter)
    found = collections.Counter()
    for (letter, text), counts in sorted(seen.items()):
        dataset = REGISTRY_COUNTIES.get(letter)
        point = None
        if dataset in tables:
            exact, whole, roads = tables[dataset]
            key = address_key(COUNTY.sub('', plain(text)), roads)
            if key is not None:
                point = exact.get(key) or whole.get(key[:3])
        found['registry' + ('Found' if point else 'NotFound')] += 1
        if point:
            points[point].update(counts)
    return points, found


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


def tainan_permits(path):
    """Tainan's usage permits (data.gov.tw 121026, a folder of its yearly
    CSVs): as `ntpc_permits`, with (district, section, parcel) keys in
    place of door numbers, since Tainan's permits name only the parcels
    (仁德區太子段75-10，75-11，共計2筆地號)."""
    out = []
    for name in sorted(os.listdir(path)):
        if not name.endswith('.csv'):
            continue
        with open(os.path.join(path, name), encoding='utf-8-sig', newline='') as file:
            for row in csv.DictReader(file):
                ground = number(row.get('建築面積_其他')) + number(row.get('建築面積_騎樓'))
                out.append((row['執照號碼'], int(number(row['地上層數'])), number(row['建築物高度']), ground,
                            parcel_keys(row['建築地點'])))
    return out


def parcel_number(text):
    """0049-0002 → 49-2, 1080-0000 → 1080, 75-10 → 75-10."""
    main, _, sub = text.partition('-')
    main, sub = int(main), int(sub or 0)
    return f'{main}-{sub}' if sub else str(main)


def parcel_keys(text):
    """(district, section, parcel) of every parcel a Tainan permit names.
    A district and a section carry over to the parcels after them."""
    text = re.sub(r'^(?:台南市|台南縣)', '', plain(text))
    text = re.sub(r'(?:，|,)?共計\d+筆地號.*$|地號$', '', text)
    keys = []
    district = section = None
    for part in re.split(r'[，,、;；]', text):
        m = re.match(r'(?:(?P<district>[^\d]{1,4}?區))?(?:(?P<section>[^\d]+?段(?:[^\d]+?小段)?))?'
                     r'(?P<number>\d+(?:-\d+)?)(?:地號)?$', part.strip())
        if not m:
            continue
        district = m.group('district') or district
        section = m.group('section') or section
        if district and section:
            keys.append((district, section, parcel_number(m.group('number'))))
    return keys


def parcel_table(path):
    """(district, section, parcel) → (lon, lat) of Tainan's parcels
    (data.gov.tw 176361, a folder of CSVs), and (district, section) →
    the sections of that name with a 小段 (a permit may name the 段 only)."""
    exact, sections = {}, collections.defaultdict(set)
    for name in sorted(os.listdir(path)):
        if not name.endswith('.csv'):
            continue
        with open(os.path.join(path, name), encoding='utf-8-sig', newline='') as file:
            for row in csv.DictReader(file):
                try:
                    lon, lat = float(row['經度']), float(row['緯度'])
                    key = (plain(row['區名']), plain(row['地段名']), parcel_number(plain(row['地號'])))
                except (ValueError, KeyError):
                    continue
                exact[key] = (lon, lat)
                head = re.match(r'(.+?段)', key[1])
                if head and head.group(1) != key[1]:
                    sections[(key[0], head.group(1))].add(key[1])
    return exact, sections


def drawn_storeys(storeys, height):
    """The storeys the game draws for a permit: a hall, a factory or a
    temple of one or two tall storeys (a 16.9 m sports hall of one) is
    drawn as high as it stands, at the game's 3.2 m a storey, less 2 m
    of roof."""
    if storeys <= 3 and height >= 6 * storeys:
        return max(storeys, round((height - 2) / STOREY_METRES))
    return storeys


def apply(archive, out, report_path, *sources):
    """Sources are `addresses=<parquet>`, `ntpc=<csv>`, `taipei=<xml>`,
    `hsinchu=<csv>`, `tainan=<permit folder>:<parcel folder>` and
    `registry=<registry's tsv.gz>`; any may be left out."""
    given = dict(s.split('=', 1) for s in sources)
    permits = []
    # Each permit's points: (lon, lat) of its door numbers or parcels.
    located = []
    if 'ntpc' in given or 'taipei' in given:
        exact, whole, roads = point_table(given['addresses'])
        listed = ([('ntpc',) + p for p in ntpc_permits(given['ntpc'])] if 'ntpc' in given else []) + \
                 ([('taipei',) + p for p in taipei_permits(given['taipei'])] if 'taipei' in given else [])
        for permit in listed:
            mine = set()
            for text in permit[5]:
                key = address_key(text, roads)
                if key is not None:
                    point = exact.get(key) or whole.get(key[:3])
                    if point:
                        mine.add(point)
            permits.append(permit)
            located.append(mine)
    if 'hsinchu' in given:
        exact, whole, roads = point_table(given['addresses'], ('tw/hsz/regionwide',))
        exact = {k[1:]: v for k, v in sorted(exact.items())}
        whole = {k[1:]: v for k, v in sorted(whole.items())}
        roads = set().union(*roads.values())
        for permit in hsinchu_permits(given['hsinchu']):
            mine = set()
            for text in permit[4]:
                key = citywide_key(text, roads)
                if key is not None:
                    point = exact.get(key) or whole.get(key[:2])
                    if point:
                        mine.add(point)
            permits.append(('hsinchu',) + permit)
            located.append(mine)
    if 'tainan' in given:
        permit_dir, parcel_dir = given['tainan'].split(':')
        exact, sections = parcel_table(parcel_dir)
        for permit in tainan_permits(permit_dir):
            mine = set()
            for district, section, parcel in permit[4]:
                point = exact.get((district, section, parcel))
                if point is None:
                    # A permit naming the 段 of a section split into 小段.
                    hits = [exact[(district, s, parcel)] for s in sorted(sections.get((district, section), ()))
                            if (district, s, parcel) in exact]
                    point = hits[0] if len(hits) == 1 else None
                if point:
                    mine.add(point)
            permits.append(('tainan',) + permit)
            located.append(mine)
    registry_found = collections.Counter()
    if 'registry' in given:
        # One entry a door number, its sales' storeys in place of the
        # addresses.
        sold, registry_found = registry_points(given['registry'], given['addresses'])
        for point, counts in sorted(sold.items()):
            permits.append(('registry', 'lvr', max(counts), 0.0, 0.0, counts))
            located.append({point})
    found = collections.Counter()
    # Working-unit points of the permits, by tile: (x, y, permit).
    points = []
    by_tile = collections.defaultdict(list)
    for index, ((city, _, storeys, height, ground, _), mine) in enumerate(zip(permits, located)):
        if storeys <= 0:
            found[city + 'NoStoreys'] += 1
            continue
        if city not in NO_HEIGHT and city != 'registry' and not believable(storeys, height):
            found[city + 'StoreysAgainstHeight'] += 1
            continue
        if city != 'registry':
            found[city + ('Found' if mine else 'NotFound')] += 1
        for lon, lat in sorted(mine):
            gx, gy = global_units(lon, lat)
            by_tile[(int(gx) // T.EXTENT, int(gy) // T.EXTENT)].append(len(points))
            points.append((gx, gy, index, NEAR_PARCEL if city in PARCEL_CITIES else NEAR))
    found.update(registry_found)
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
                gx, gy, _, limit = points[j]
                if not (west <= gx <= east and north <= gy <= south):
                    continue
                if inside(gx, gy, outline):
                    distance = 0.0
                else:
                    distance = math.sqrt(min(T.segment_sq(gx, gy, *outline[k - 1], *outline[k])
                                             for k in range(len(outline)))) / metre
                    if distance > limit:
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
    too_large = not_fitting = rows = 0
    storeys_before, storeys_after = collections.Counter(), collections.Counter()
    hit_permits = set()
    agreement = collections.defaultdict(collections.Counter)
    changed_from = collections.Counter()
    changed_by = collections.Counter()
    registry_agreement = collections.defaultdict(collections.Counter)
    registry_mixed = 0
    for (tid, offset), holding in sorted(held.items()):
        length, attributes, size = meta[(tid, offset)]
        origin = attributes >> 5 & 7
        origins_hit[T.STOREYS_FROM[origin]] += 1
        storeys = 0
        row = []
        # The registry's sales at the building's door numbers: storeys →
        # how many.
        votes = collections.Counter()
        for i in sorted(holding):
            city, _, value, height, ground, extra = permits[i]
            if city == 'registry':
                votes.update(extra)
                continue
            value = drawn_storeys(value, height)
            if ground > 0 and size > AREA_SLACK * ground + AREA_EXTRA:
                row.append((value, ground))
                continue
            if not T.permit_fits(value, size):
                # A tower's permit on a footprint that also holds its podium
                # (Taipei 101 and its mall are one outline): the podium's
                # permit is not all of it either, so none is taken.
                not_fitting += origin in replaced
                storeys = -1
                break
            storeys = max(storeys, min(255, value))
        if storeys == 0 and row:
            # A row of terrace houses the outlines merged into one, each
            # house its own permit: when the permits together cover the
            # outline, the storeys most of their ground has.
            if size <= AREA_SLACK * sum(g for _, g in row) + AREA_EXTRA:
                by_storeys = collections.Counter()
                for value, ground in row:
                    by_storeys[min(255, value)] += ground
                value = max(by_storeys, key=lambda v: (by_storeys[v], v))
                if T.permit_fits(value, size):
                    storeys = value
                    rows += origin in replaced
                else:
                    not_fitting += origin in replaced
            else:
                too_large += origin in replaced
        source = 'permits'
        if votes:
            # Most of the sales name one count of storeys, or none is
            # taken: a building that holds a tower's door and its
            # neighbours' houses (the outlines merged them) has no one count.
            value = max(votes, key=lambda v: (votes[v], v))
            if 2 * votes[value] < sum(votes.values()):
                registry_mixed += storeys == 0 and origin in replaced
            elif T.permit_fits(value, size):
                had = attributes >> 8 if origin not in replaced or storeys == 0 else storeys
                if origin not in replaced or storeys > 0:
                    known = T.STOREYS_FROM[origin] if origin not in replaced else 'permits'
                    registry_agreement[known][
                        'same' if had == value else 'withinOne' if abs(had - value) == 1 else 'apart'] += 1
                if storeys == 0:
                    storeys, source = min(255, value), 'registry'
        if storeys > 0 and origin in replaced:
            hit_permits.update(i for i in holding if permits[i][0] != 'registry')
            changed_by[source] += 1
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
        'changedBy': dict(sorted(changed_by.items())),
        'registryAgreementWithKnown': {k: dict(sorted(v.items())) for k, v in sorted(registry_agreement.items())},
        'registryLeftOutMixed': registry_mixed,
        'rowsOfHouses': rows,
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
    commands = {'addresses': addresses, 'registry': registry, 'apply': apply}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
