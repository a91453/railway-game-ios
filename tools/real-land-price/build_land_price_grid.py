#!/usr/bin/env python3
"""How dear Taiwan's land is, place by place, from the real-price
registry (實價登錄), as the app's `Resources/RealWorld/taiwan_land_price.dat`
(decision 1025).

    T=tools/real-land-price/build_land_price_grid.py
    U=tools/overture-footprint-tiles/usage_permits.py
    # about 3 minutes: the door-number points of Taiwan's counties
    python3 -I $U addresses 2026-11-18.0 addresses.parquet
    # about 5 minutes: every sale of the seasons 110S1 to 115S3
    python3 -I $T registry registry_prices.tsv.gz 110S1 115S3
    # about 2 minutes
    python3 -I $T build registry_prices.tsv.gz addresses.parquet \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json townships.geojson \\
        RailwayGameApp/Resources/RealWorld/taiwan_land_price.dat land_price.json

`townships.geojson` is the Ministry of the Interior's township
boundaries as `a91453/railway-reference-private` keeps them,
`Railway/geo-scene-reference-clean/source/public/statistics/township-reference.geojson`
(368 townships, `area_name` 臺東縣成功鎮).

What a sale says about its land (the land residual method, 土地殘餘法, of
Taiwan's appraisal rules): a sale of land with a building (房地) pays
for both, so the building's cost new (`COST_NEW` a m² by its kind) less
straight-line wear over its life (`LIFE` years, never below `FLOOR` of
it) is taken off the price, with the parking's own price, and what is
left is the land's: over the land's area moved, its price a m². A tower
flat and a terraced house of the same street then come out near the
same land price, although the flat's price a m² of floor is far lower.
A sale of land alone (土地) is its own price a m². Sales the registry
marks as not at arm's length (between kin, the government's, auctions,
reserved public land, and the like: `UNUSUAL`) are left out, and a sale
whose building leaves less than `LEAST_LAND` of its price to the land.

Each sale's price is over the national median of the same zone (`zone`:
the registry's 都市土地使用分區 or, outside urban plans, its 使用編定) in
the same year: a ratio, so a place's prices rising with the years and a
shop zone dearer than a farm zone both drop out. What is left is how
good the place is (its location). The game multiplies its own value of a
cell's use by it, so a cell the player zones keeps its place's ratio.

The grid is four of the water file's cells a side (7.5″, some 230 m).
A cell's ratio is the geometric mean of the ratios of the sales that a
door-number point puts in it, when there are `ENOUGH`; else of the
smallest square of cells round it (`WINDOWS` a side, out to some 7 km)
that holds as many; else its township's, of every sale the registry
names in it, door number found or not (Yilan, Nantou, Chiayi City and
Lienchiang have no door-number points); else UNKNOWN. Each ratio is in
thousandths, to the power `SPREAD`, `LOWEST` to `HIGHEST`; UNKNOWN (-1)
outside every township.
The file is the heights file's form (`build_slope_grid.py`) under the
magic `TWLP` (GamePresentation's `LandPriceGrid`).

Sources: Ministry of the Interior, Department of Land Administration,
real-price registry (不動產買賣實價登錄批次資料, data.gov.tw 18703); the
counties' door-number points through OpenAddresses and Overture Maps;
the Ministry of the Interior's township boundaries (Open Government Data
License, version 1.0, all three).
"""

import collections
import csv
import gzip
import io
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))

import usage_permits as U  # noqa: E402

UNKNOWN = -1
# The grid's cell, in the water file's cells a side.
COARSE = 4
# Sales a cell's ratio needs.
ENOUGH = 6
# The squares round a cell tried in turn, in cells a side.
WINDOWS = (1, 3, 7, 15, 31)
# A ratio's bounds, in thousandths.
LOWEST, HIGHEST = 100, 10_000
# The game's factor is the ratio to this power: the square root keeps the
# order of places and halves their spread (in logs), so Xinyi's 5.6 times
# the country is 2.4 times and a mountain village's 0.1 is 0.32. Land
# values, rents and land bought all scale with the factor, and the raw
# spread left a country town's company buildings letting for next to
# nothing while Taipei's paid for themselves in months.
SPREAD = 0.5
# One sale's ratio is held to these before it is averaged (a sale ten
# times the median of its zone is a tower's flat whose land share the
# registry rounded, or a shop's goodwill).
SALE_LOWEST, SALE_HIGHEST = 0.05, 20.0
# What a m² of building costs new, NT$, by the registry's kind (建物型態),
# and its life in years: the order of Taiwan's construction price
# tables of 2020–2025; only their proportions to the land matter.
COST_NEW = {
    '住宅大樓': 55_000, '辦公商業大樓': 55_000, '華廈': 45_000, '套房': 45_000,
    '公寓': 38_000, '透天厝': 38_000, '店面': 40_000,
    '工廠': 22_000, '廠辦': 30_000, '倉庫': 18_000, '農舍': 30_000,
}
OTHER_COST = 38_000
LIFE = {'工廠': 35, '倉庫': 35, '廠辦': 40}
OTHER_LIFE = 50
# The least of its cost new a building is held to be worth however old.
FLOOR = 0.2
# The least of a sale's price its land must keep, or it is left out.
LEAST_LAND = 0.1
# Notes (備註) of sales not at arm's length.
UNUSUAL = ('親友', '特殊關係', '協議價購', '標讓售', '標售', '拍賣', '地上權', '畸零地',
           '公共設施保留地', '僅車位', '急買急賣', '瑕疵', '債權債務', '容積代金', '徵收')
COUNTIES = {
    'a': '臺北市', 'b': '臺中市', 'c': '基隆市', 'd': '臺南市', 'e': '高雄市', 'f': '新北市',
    'g': '宜蘭縣', 'h': '桃園市', 'i': '嘉義市', 'j': '新竹縣', 'k': '苗栗縣', 'm': '南投縣',
    'n': '彰化縣', 'o': '新竹市', 'p': '雲林縣', 'q': '嘉義縣', 't': '屏東縣', 'u': '花蓮縣',
    'v': '臺東縣', 'w': '金門縣', 'x': '澎湖縣', 'z': '連江縣',
}
FIELDS = ('鄉鎮市區', '交易標的', '土地位置建物門牌', '土地移轉總面積平方公尺', '都市土地使用分區',
          '非都市土地使用分區', '非都市土地使用編定', '交易年月日', '總價元', '建物型態',
          '建築完成年月', '建物移轉總面積平方公尺', '車位移轉總面積平方公尺', '車位總價元', '備註')


# --- registry -----------------------------------------------------------------

def registry(out, first='110S1', last='115S3'):
    """Every sale and pre-sale (a and b files) of the seasons `first` to
    `last`, as `<letter>\\t<kind>\\t` and `FIELDS` tab-separated lines."""
    import tempfile
    import urllib.request
    import zipfile
    csv.field_size_limit(1 << 30)
    year, quarter = int(first[:-2]), int(first[-1])
    rows = 0
    with gzip.open(out, 'wt', encoding='utf-8') as file:
        while (year, quarter) <= (int(last[:-2]), int(last[-1])):
            season = f'{year}S{quarter}'
            with tempfile.TemporaryFile() as zipped:
                try:
                    with urllib.request.urlopen(U.REGISTRY_URL.format(season), timeout=600) as response:
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
                    if not all(f in head for f in FIELDS):
                        print(season, base, 'lacks a field', file=sys.stderr)
                        continue
                    at = [head.index(f) for f in FIELDS]
                    for row in lines:
                        if len(row) <= max(at):
                            continue
                        values = [re.sub(r'\s', ' ', row[i]) for i in at]
                        file.write('\t'.join([base[0].lower(), base[-5]] + values) + '\n')
                        rows += 1
            print(season, rows, file=sys.stderr, flush=True)
            year, quarter = (year, quarter + 1) if quarter < 4 else (year + 1, 1)


# --- one sale -----------------------------------------------------------------

def number(text):
    try:
        return float(U.plain(text).replace(',', '') or 0)
    except ValueError:
        return 0.0


def zone(urban, rural, use):
    """The sale's zone: res, com, ind, farm, or None (roads, other)."""
    urban = U.plain(urban)
    if urban:
        if '商' in urban:
            return 'com'
        if '工' in urban:
            return 'ind'
        if '住' in urban:
            return 'res'
        if '農' in urban:
            return 'farm'
        return None
    use = U.plain(use)
    if '丁種建築' in use or '工業區' in U.plain(rural):
        return 'ind'
    if '建築用地' in use:
        return 'res'
    if any(w in use for w in ('農牧', '養殖', '林業')):
        return 'farm'
    return None


def roc_year(text):
    """1150902 → 2026; 0 for a date that is not one."""
    text = U.plain(text)
    return int(text[:-4]) + 1911 if len(text) >= 6 and text[:-4].isdigit() else 0


def kind_of(text):
    text = U.plain(text)
    return next((k for k in COST_NEW if text.startswith(k)), None)


def land_price(fields, presale):
    """NT$ a m² of a sale's land, or None for a sale that says nothing
    about it (`land_price.__doc__` in the module's docstring)."""
    (_, target, _, land_area, _, _, _, date, total, kind, built, floor, parking_area, parking_price, note) = fields
    target = U.plain(target)
    if any(w in note for w in UNUSUAL):
        return None
    land, price = number(land_area), number(total) - number(parking_price)
    if land <= 1 or price <= 0:
        return None
    if target == '土地':
        return price / land
    if not target.startswith('房地'):
        return None
    k = kind_of(kind)
    area = number(floor) - (number(parking_area) if number(parking_price) > 0 else 0)
    if area <= 0:
        return None
    age = 0.0 if presale else max(0.0, roc_year(date) - roc_year(built)) if roc_year(built) else 25.0
    life = LIFE.get(k, OTHER_LIFE)
    building = area * COST_NEW.get(k, OTHER_COST) * max(FLOOR, 1 - age / life)
    left = price - building
    if left < LEAST_LAND * price:
        return None
    return left / land


# The years of the seasons read (110 to 115).
FIRST_YEAR, LAST_YEAR = 2021, 2026


def sales(path):
    """(letter, township, address, zone, year, NT$ a m²) of every sale the
    registry says something about its land of."""
    with gzip.open(path, 'rt', encoding='utf-8') as file:
        for line in file:
            parts = line.rstrip('\n').split('\t')
            if len(parts) != 2 + len(FIELDS):
                continue
            letter, kind, fields = parts[0], parts[1], parts[2:]
            z = zone(fields[4], fields[5], fields[6])
            year = roc_year(fields[7])
            # A sale reported late, or a date typed wrong (1922, 2028),
            # would be judged against a handful of others.
            if z is None or not FIRST_YEAR <= year <= LAST_YEAR:
                continue
            price = land_price(fields, presale=kind == 'b')
            if price is None:
                continue
            yield letter, U.plain(fields[0]), fields[2], z, year, price


def ratios(found):
    """Each sale's price over the median of its zone and year, held to
    `SALE_LOWEST`…`SALE_HIGHEST`, as its log."""
    groups = collections.defaultdict(list)
    for sale in found:
        groups[(sale[3], sale[4])].append(sale[5])
    medians = {key: sorted(v)[len(v) // 2] for key, v in groups.items()}
    low, high = math.log(SALE_LOWEST), math.log(SALE_HIGHEST)
    return [min(high, max(low, math.log(s[5] / medians[(s[3], s[4])]))) for s in found], medians


# --- the grid -----------------------------------------------------------------

def township_raster(path, north, west, step, rows, columns):
    """Each grid cell's township index (by its middle), -1 outside all,
    and the townships' names."""
    import numpy as np
    from PIL import Image, ImageDraw
    features = json.load(open(path, encoding='utf-8'))['features']
    names = [U.plain(f['properties']['area_name']) for f in features]
    image = Image.new('I', (columns, rows), -1)
    draw = ImageDraw.Draw(image)
    for index, feature in enumerate(features):
        geometry = feature['geometry']
        polygons = geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]
        for polygon in polygons:
            for ring_index, ring in enumerate(polygon):
                xy = [((lon - west) / step - 0.5, (north - lat) / step - 0.5) for lon, lat in ring]
                if len(xy) >= 3:
                    draw.polygon(xy, fill=index if ring_index == 0 else -1)
    return np.array(image, dtype=np.int32), names


def box_sum(grid, side):
    """Each cell's sum over the `side` × `side` square round it."""
    import numpy as np
    r = side // 2
    padded = np.pad(grid, r)
    total = padded.cumsum(0).cumsum(1)
    total = np.pad(total, ((1, 0), (1, 0)))
    rows, columns = grid.shape
    return (total[side:side + rows, side:side + columns] - total[:rows, side:side + columns]
            - total[side:side + rows, :columns] + total[:rows, :columns])


def build(registry_path, addresses, water_path, townships, out, report_path):
    import numpy as np
    from build_slope_grid import encode_heights
    water = json.load(open(water_path))
    step = water['cellDegrees'] * COARSE
    north, west = water['north'], water['west']
    rows, columns = -(-water['rows'] // COARSE), -(-water['columns'] // COARSE)
    found = list(sales(registry_path))
    logs, medians = ratios(found)
    tables = U.point_tables(addresses, sorted(set(U.REGISTRY_COUNTIES.values())))
    count = np.zeros((rows, columns), dtype=np.float64)
    total = np.zeros((rows, columns), dtype=np.float64)
    town_sum, town_count = collections.Counter(), collections.Counter()
    cache = {}
    located = 0
    for (letter, township, address, _, _, _), log in zip(found, logs):
        county = COUNTIES.get(letter)
        if county:
            # Hsinchu City and Chiayi City name no district: the city.
            name = U.plain(county if U.plain(township) in ('', U.plain(county)) else county + township)
            town_sum[name] += log
            town_count[name] += 1
        dataset = U.REGISTRY_COUNTIES.get(letter)
        if dataset not in tables or '號' not in address or not U.single_address(address):
            continue
        key = (letter, address)
        if key not in cache:
            exact, whole, roads = tables[dataset]
            k = U.address_key(U.COUNTY.sub('', U.plain(address)), roads)
            cache[key] = (exact.get(k) or whole.get(k[:3])) if k is not None else None
        point = cache[key]
        if point is None:
            continue
        r, c = int((north - point[1]) / step), int((point[0] - west) / step)
        if 0 <= r < rows and 0 <= c < columns:
            count[r, c] += 1
            total[r, c] += log
            located += 1
    ratio = np.full((rows, columns), np.nan)
    source = np.zeros((rows, columns), dtype=np.int8)
    for level, side in enumerate(WINDOWS, start=1):
        n = box_sum(count, side)
        s = box_sum(total, side)
        take = np.isnan(ratio) & (n >= ENOUGH)
        ratio[take] = s[take] / n[take]
        source[take] = level
    town, names = township_raster(townships, north, west, step, rows, columns)
    town_log = np.full(len(names) + 1, np.nan)
    for index, name in enumerate(names):
        # A district the registry does not name takes its city's.
        for key in (name, name[:3]):
            if town_count[key] >= ENOUGH:
                town_log[index] = town_sum[key] / town_count[key]
                break
    fill = np.isnan(ratio) & (town >= 0)
    ratio[fill] = town_log[town[fill]]
    source[fill & ~np.isnan(ratio)] = len(WINDOWS) + 1
    inside = town >= 0
    values = np.where(inside & ~np.isnan(ratio),
                      np.clip(np.rint(np.exp(SPREAD * np.nan_to_num(ratio)) * 1000), LOWEST, HIGHEST), UNKNOWN).astype(np.int16)
    open(out, 'wb').write(encode_heights(values, {'north': north, 'west': west, 'cellDegrees': step}, magic=b'TWLP'))
    known = values[values != UNKNOWN]
    report = {
        'sales': len(found), 'located': located,
        'medians': {f'{z}/{y}': round(m) for (z, y), m in sorted(medians.items())},
        'grid': {'north': north, 'west': west, 'cellDegrees': step, 'rows': rows, 'columns': columns},
        'cells': int(inside.sum()), 'known': int(known.size),
        'bySource': {name: int(((source == level) & inside).sum())
                     for level, name in enumerate(['none'] + [f'{s}x{s}' for s in WINDOWS] + ['township'])},
        'percentiles': {str(p): int(np.percentile(known, p)) for p in (1, 10, 25, 50, 75, 90, 99)} if known.size else {},
        'townshipsWithoutSales': sorted(n for i, n in enumerate(names) if np.isnan(town_log[i])),
    }
    json.dump(report, open(report_path, 'w'), ensure_ascii=False, indent=1)
    print(json.dumps({k: report[k] for k in ('sales', 'located', 'cells', 'known', 'bySource', 'percentiles')},
                     ensure_ascii=False))


def ratio_at(path, lon, lat):
    """The file's ratio at a point, for a look (`at <file> <lon> <lat>`)."""
    import struct
    data = open(path, 'rb').read()
    north, west, step = struct.unpack_from('<ddd', data, 8)
    rows, columns = struct.unpack_from('<II', data, 32)
    r, c = int((north - float(lat)) / step), int((float(lon) - west) / step)
    offsets = struct.unpack_from(f'<{rows + 1}I', data, 40)
    body = data[40 + 4 * (rows + 1):][offsets[r]:offsets[r + 1]]
    numbers, value, shift = [], 0, 0
    for byte in body:
        value |= (byte & 0x7f) << shift
        shift += 7
        if not byte & 0x80:
            numbers.append(value)
            value, shift = 0, 0
    cells, at, last = [], 0, 0
    while at < len(numbers):
        if numbers[at] == 0:
            cells += [last] * numbers[at + 1]
            at += 2
        else:
            z = numbers[at]
            last += (z >> 1) ^ -(z & 1)
            cells.append(last)
            at += 1
    print(cells[c])


if __name__ == '__main__':
    commands = {'registry': registry, 'build': build, 'at': ratio_at}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
