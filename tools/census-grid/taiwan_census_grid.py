"""Taiwan's people and jobs on the real-world map's population grid
(decision 1002, TAIWAN-CENSUS-GRID), in the form decision 1000 gave map
packs (`PopulationGrid`, with `jobs`), from the government's own figures
instead of WorldPop's 1 km estimate.

    python3 -I tools/census-grid/taiwan_census_grid.py fetch <folder>
    python3 -I tools/census-grid/taiwan_census_grid.py build <folder> <places-7.5.json> <out> [--compare old.json]

`fetch` downloads what the cloud can reach into `<folder>`: the statistical
areas' boundaries (最小統計區圖, data.gov.tw 25128), the 2020 census's
resident population by township (109 年人口及住宅普查 常住人口, 18447–18521),
the household register by village at the end of 2020 (村里戶數、單一年齡人口
10912, data.gov.tw 77132) and the 2021 census of industry and services'
persons engaged by township (110 年工業及服務業普查, 15706–15729). The
statistical areas' population (統計區人口統計_最小統計區, data.gov.tw 18681)
is served only by segisws.moi.gov.tw, which refuses connections from
outside Taiwan: its 22 files are kept in `a91453/railway-reference-private`
`Railway/segis-snapshot-2026-11/population/` (`<county>.xml.gz`), copied into
`<folder>/segis/` by hand.

`build` writes the grid (`RailwayGameApp/Resources/RealWorld/taiwan_population.json`):

- The grid is 7.5″ square cells, a quarter of WorldPop's 30″ cell on the
  same corner, so each is exactly one zone cell of `taiwan_places.json`
  (decision 93) and 4 × 4 cells of the water grid (1.875″, decision 105).
- `runs`, where people live: each statistical area's registered people
  (戶籍人口, some 300 to 500 people an area in towns) spread over the
  water-grid cells whose middles lie in it, by how much of each such cell
  buildings cover (`taiwan_coverage.dat`, decision 147; evenly over its dry
  cells where no building is known), then summed on the 7.5″ cells. Cells
  whose zone is a park or industrial land (decision 93) take no one unless
  the area has nothing else: the game lays out no homes there. The
  register counts people where they are registered, not where they live
  (Kinmen registers twice its residents), so each township's people are
  scaled to the 2020 census's residents there (常住人口 ÷ the register at the
  end of 2020), and rounded so each township keeps its total.
- `jobs`, where people work: each township's persons engaged in the 2021
  census (年底從業員工人數, the census of industry and services: no public
  administration, defence or farming) placed by what OpenStreetMap maps on
  the 7.5″ cells (`<places-7.5.json>`, `build_place_grid.py` counted on this
  grid): shops and restaurants (`shop`) 25 each, offices 500 (`office`),
  schools 300 (`civic`), sights 50 (`leisure`), `LandImport.jobsPerPlace`,
  and the industrial land of `taiwan_places.json`'s zones 29 a 64 m cell
  (`office`; `LandImport.industrialJobsPerCell`), all scaled so the
  township's jobs are the census's; a park's places count for nothing.
  A township with jobs and nothing mapped puts them where its people live.

Licence: 政府資料開放授權條款第 1 版 (Open Government Data License, version
1.0, compatible with CC BY 4.0): commercial use allowed, with the source
named. Credit: 內政部統計處「統計區人口統計」「最小統計區圖」、行政院主計總處
「109 年人口及住宅普查」「110 年工業及服務業普查」、內政部戶政司「村里戶數、
單一年齡人口」. OpenStreetMap's places stay ODbL 1.0.
"""

import glob
import gzip
import hashlib
import io
import json
import math
import os
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
import zipfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORLD = os.path.join(ROOT, 'RailwayGameApp', 'Resources', 'RealWorld')
RECORD = os.path.join(HERE, 'taiwan_sources.json')

COUNTIES = ['臺北市', '新北市', '基隆市', '桃園市', '新竹市', '新竹縣', '苗栗縣', '臺中市', '彰化縣', '南投縣', '雲林縣',
            '嘉義市', '嘉義縣', '臺南市', '高雄市', '屏東縣', '宜蘭縣', '花蓮縣', '臺東縣', '澎湖縣', '金門縣', '連江縣']

# data.gov.tw datasets, by county: the 2020 census's residents and the 2021
# census of industry and services, both by township.
RESIDENT_DATASETS = {
    '新北市': 18447, '臺北市': 18450, '臺中市': 18454, '臺南市': 18503, '高雄市': 18504, '宜蘭縣': 18505, '桃園市': 18506,
    '新竹縣': 18507, '苗栗縣': 18508, '彰化縣': 18509, '南投縣': 18510, '雲林縣': 18511, '嘉義縣': 18512, '屏東縣': 18513,
    '臺東縣': 18514, '花蓮縣': 18515, '澎湖縣': 18516, '基隆市': 18517, '新竹市': 18518, '嘉義市': 18519, '金門縣': 18520,
    '連江縣': 18521,
}
JOB_DATASETS = {
    '新北市': 15706, '臺北市': 15707, '基隆市': 15708, '新竹市': 15709, '宜蘭縣': 15710, '桃園市': 15711, '新竹縣': 15712,
    '臺中市': 15713, '苗栗縣': 15714, '彰化縣': 15715, '南投縣': 15716, '雲林縣': 15717, '臺南市': 15718, '高雄市': 15719,
    '嘉義市': 15720, '嘉義縣': 15721, '屏東縣': 15722, '澎湖縣': 15723, '臺東縣': 15724, '花蓮縣': 15726, '金門縣': 15727,
    '連江縣': 15729,
}
BOUNDARIES = 25128          # 最小統計區圖
REGISTER = (77132, '10912')  # 村里戶數、單一年齡人口（新增區域代碼）, 109 年 12 月
AREA_POPULATION = 18681      # 統計區人口統計_最小統計區 (segisws.moi.gov.tw only)

# Townships renamed since the boundaries (2015) were drawn: 員林 and 頭份
# became cities in 2015.
RENAMED = {('彰化縣', '員林鎮'): '員林市', ('苗栗縣', '頭份鎮'): '頭份市'}

DATASET = 'https://data.gov.tw/api/v2/rest/dataset/{}'

SOURCE = ('Ministry of the Interior (statistical areas: registered people, boundaries; household register by village) '
          'and DGBAS (2020 Census of Population and Housing: residents by township; 2021 Industry and Service Census: '
          'persons engaged by township), spread over 7.5 arc-second cells by building cover and OpenStreetMap places')
LICENCE = '政府資料開放授權條款第1版 (Open Government Data License, version 1.0, compatible with CC BY 4.0)'
CREDIT = ('內政部統計處「統計區人口統計」「最小統計區圖」、內政部戶政司「村里戶數、單一年齡人口」、'
          '行政院主計總處「109年人口及住宅普查」「110年工業及服務業普查」')

# LandImport's jobs of each kind of place and of a 64 m cell of industrial
# land (decisions 72, 93, 96): the weights that place a township's jobs.
JOBS_PER_PLACE = {'shops': ('shop', 25), 'offices': ('office', 500), 'schools': ('civic', 300), 'attractions': ('leisure', 50)}
INDUSTRIAL_PER_CELL = 29
CELL_METRES = 64.0

# TWD97 / TM2 (EPSG:3826 on 121° E, EPSG:3825 on 119° E for Penghu, Kinmen
# and Matsu).
TM2_A = 6_378_137.0
TM2_INVERSE_FLATTENING = 298.257222101
TM2_SCALE = 0.9999
TM2_EASTING = 250_000.0


# ---------------------------------------------------------------- download

def curl(url, path):
    """Downloads with curl (data.gov.tw refuses Python's own client)."""
    subprocess.run(['curl', '-sSfL', '--retry', '3', '-m', '600', '-o', path, url], check=True)


def dataset(number, folder):
    path = os.path.join(folder, 'datasets', f'{number}.json')
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        curl(DATASET.format(number), path)
    with open(path, encoding='utf-8') as f:
        return json.load(f)['result']


def fetch(folder):
    os.makedirs(folder, exist_ok=True)
    jobs = []
    for county, number in RESIDENT_DATASETS.items():
        urls = [d['resourceDownloadUrl'] for d in dataset(number, folder)['distribution'] if 'a109' in d['resourceDownloadUrl'].lower()]
        jobs.append((urls[0], os.path.join(folder, 'residents', county + '.xml')))
    for county, number in JOB_DATASETS.items():
        urls = [d['resourceDownloadUrl'] for d in dataset(number, folder)['distribution'] if 'a110' in d['resourceDownloadUrl'].lower()]
        jobs.append((urls[0], os.path.join(folder, 'jobs', county + '.xml')))
    for d in dataset(BOUNDARIES, folder)['distribution']:
        if d['resourceFormat'] == 'SHP':
            county = d['resourceDescription'].replace('最小統計區圖', '')
            jobs.append((d['resourceDownloadUrl'], os.path.join(folder, 'boundaries', county + '.zip')))
    number, month = REGISTER
    url = [d['resourceDownloadUrl'] for d in dataset(number, folder)['distribution'] if d['resourceDescription'].startswith(month)][0]
    jobs.append((url, os.path.join(folder, f'register-{month}.csv')))
    for url, path in jobs:
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            curl(url, path)
            print('fetched', os.path.relpath(path, folder))
    missing = [c for c in COUNTIES if not os.path.exists(os.path.join(folder, 'segis', c + '.xml.gz'))]
    if missing:
        print(f'{len(missing)} counties lack the statistical areas\' population (segis/<county>.xml.gz): '
              'copy them from a91453/railway-reference-private Railway/segis-snapshot-2026-11/population/.')


# ------------------------------------------------------------------ reading

def text(node):
    return (node.text or '').replace('　', '').strip()


def number(value):
    value = (value or '').replace(',', '').strip()
    return int(float(value)) if value not in ('', '-', '…') else 0


def township_table(path, column):
    """`{township: count}` of a DGBAS county table: the rows after the
    county's total whose `column` (a prefix of the tag) holds a number."""
    rows = {}
    root = ElementTree.parse(path).getroot()
    for record in root:
        fields = list(record)
        name = text(fields[0])
        values = [f.text for f in fields if f.tag.startswith(column)]
        if not values or values[0] is None or not name or name.isascii():
            continue
        rows[name] = number(values[0])
    return rows


def county_of(name):
    return name.replace('台', '臺')


def residents(folder):
    """The 2020 census's residents, `{(county, township): people}`."""
    out = {}
    for county in COUNTIES:
        table = township_table(os.path.join(folder, 'residents', county + '.xml'), '常住人口數_總計')
        for name, people in table.items():
            if name != county:
                out[(county, name)] = people
    return out


def persons_engaged(folder):
    """The 2021 census's persons engaged, `{(county, township): jobs}`."""
    out = {}
    for county in COUNTIES:
        table = township_table(os.path.join(folder, 'jobs', county + '.xml'), '年底從業員工人數')
        for name, jobs in table.items():
            if name not in ('總計', county):
                out[(county, name)] = jobs
    return out


def register(folder):
    """The household register at the end of 2020, `{(county, township): people}`."""
    import csv
    out = {}
    with open(os.path.join(folder, f'register-{REGISTER[1]}.csv'), encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            area = row['區域別']
            if not row['人口數'].strip().isdigit():
                continue
            county = county_of(area[:3])
            out[(county, area[3:])] = out.get((county, area[3:]), 0) + int(row['人口數'])
    return out


def area_population(folder):
    """The statistical areas' registered people, `{CODEBASE: people}`, and
    the time each county's file gives."""
    out, times = {}, {}
    for county in COUNTIES:
        with gzip.open(os.path.join(folder, 'segis', county + '.xml.gz')) as f:
            root = ElementTree.parse(f).getroot()
        for record in root.iter():
            fields = {child.tag.split('}')[-1]: child.text for child in record}
            if 'CODEBASE' in fields and 'P_CNT' in fields:
                out[fields['CODEBASE'].strip()] = number(fields['P_CNT'])
                times[county] = (fields.get('INFO_TIME') or '').strip()
    return out, times


def read_dbf(data, encoding='big5'):
    count, header, length = struct.unpack('<IHH', data[4:12])
    fields, at = [], 32
    while data[at] != 0x0D:
        name = data[at:at + 11].split(b'\0')[0].decode('ascii')
        fields.append((name, data[at + 16]))
        at += 32
    records = []
    for i in range(count):
        offset = header + i * length + 1
        record = {}
        for name, size in fields:
            record[name] = data[offset:offset + size].decode(encoding, 'replace').strip()
            offset += size
        records.append(record)
    return records


def read_shp(data):
    """Each polygon's rings, as arrays of (x, y) in the file's metres."""
    shapes, at = [], 100
    while at < len(data):
        _, length = struct.unpack('>II', data[at:at + 8])
        body = data[at + 8:at + 8 + 2 * length]
        at += 8 + 2 * length
        kind = struct.unpack('<i', body[:4])[0]
        if kind == 0:
            shapes.append([])
            continue
        parts, points = struct.unpack('<ii', body[36:44])
        starts = list(struct.unpack(f'<{parts}i', body[44:44 + 4 * parts])) + [points]
        xy = np.frombuffer(body, dtype='<f8', count=2 * points, offset=44 + 4 * parts).reshape(points, 2)
        shapes.append([xy[starts[i]:starts[i + 1]] for i in range(parts)])
    return shapes


def boundaries(folder):
    """Every statistical area: its code, township, and rings in degrees."""
    areas = []
    for path in sorted(glob.glob(os.path.join(folder, 'boundaries', '*.zip'))):
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            stem = [n for n in names if n.lower().endswith('.shp')][0][:-4]
            encoding = z.read(stem + '.cpg').decode('ascii').strip() if stem + '.cpg' in names else 'big5'
            records = read_dbf(z.read(stem + '.dbf'), 'utf-8' if 'utf' in encoding.lower() else 'big5')
            shapes = read_shp(z.read(stem + '.shp'))
            projection = z.read(stem + '.prj').decode('ascii', 'replace') if stem + '.prj' in names else ''
        # 121° E for Taiwan; 119° E for Penghu, Kinmen and Matsu (the
        # dataset's note; Penghu's file has no .prj).
        found = re.search(r'central_meridian",\s*([0-9.]+)', projection)
        meridian = float(found.group(1)) if found else (119 if os.path.basename(path)[:3] in ('澎湖縣', '金門縣', '連江縣') else 121)
        for record, rings in zip(records, shapes):
            geographic = []
            for ring in rings:
                latitudes, longitudes = tm2_inverse(ring[:, 0], ring[:, 1], meridian)
                geographic.append(np.column_stack((latitudes, longitudes)))
            middle = tm2_inverse(np.array([float(record['X'] or 0)]), np.array([float(record['Y'] or 0)]), meridian)
            county = county_of(record['COUNTY'])
            township = RENAMED.get((county, record['TOWN']), record['TOWN'])
            areas.append({
                'code': record['CODEBASE'], 'county': county, 'township': township,
                'rings': geographic, 'middle': (float(middle[0][0]), float(middle[1][0])),
            })
    return areas


# ---------------------------------------------------------------- geometry

def tm2_inverse(eastings, northings, meridian):
    """Degrees of TWD97 TM2 eastings and northings (Krüger's series to the
    fourth order; the inverse of `build_slope_grid.tm2`)."""
    f = 1 / TM2_INVERSE_FLATTENING
    n = f / (2 - f)
    radius = TM2_A / (1 + n) * (1 + n ** 2 / 4 + n ** 4 / 64)
    beta = (
        n / 2 - 2 * n ** 2 / 3 + 37 * n ** 3 / 96 - n ** 4 / 360,
        n ** 2 / 48 + n ** 3 / 15 - 437 * n ** 4 / 1440,
        17 * n ** 3 / 480 - 37 * n ** 4 / 840,
        4397 * n ** 4 / 161280,
    )
    e = math.sqrt(f * (2 - f))
    xi = np.asarray(northings, dtype=float) / (TM2_SCALE * radius)
    eta = (np.asarray(eastings, dtype=float) - TM2_EASTING) / (TM2_SCALE * radius)
    xi0, eta0 = xi.copy(), eta.copy()
    for j, b in enumerate(beta, start=1):
        xi0 = xi0 - b * np.sin(2 * j * xi) * np.cosh(2 * j * eta)
        eta0 = eta0 - b * np.cos(2 * j * xi) * np.sinh(2 * j * eta)
    chi = np.arcsin(np.sin(xi0) / np.cosh(eta0))
    longitude = meridian + np.degrees(np.arctan2(np.sinh(eta0), np.cos(xi0)))
    phi = chi.copy()
    for _ in range(8):
        s = e * np.sin(phi)
        phi = 2 * np.arctan(np.tan(math.pi / 4 + chi / 2) * ((1 + s) / (1 - s)) ** (e / 2)) - math.pi / 2
    return np.degrees(phi), longitude


def raster_cells(rings, north, west, size, rows, columns):
    """The (row, column) of every cell of the grid whose middle lies in the
    polygon (even-odd over its rings), as two arrays."""
    points = np.concatenate(rings)
    top = int(math.floor((north - points[:, 0].max()) / size))
    bottom = int(math.floor((north - points[:, 0].min()) / size))
    top, bottom = max(top, 0), min(bottom, rows - 1)
    if top > bottom:
        return np.zeros(0, int), np.zeros(0, int)
    a = np.concatenate([r[:-1] for r in rings if len(r) > 1])
    b = np.concatenate([r[1:] for r in rings if len(r) > 1])
    out_rows, out_columns = [], []
    latitudes = north - (np.arange(top, bottom + 1) + 0.5) * size
    lat1, lon1, lat2, lon2 = a[:, 0], a[:, 1], b[:, 0], b[:, 1]
    for k, latitude in enumerate(latitudes):
        spans = (lat1 <= latitude) != (lat2 <= latitude)
        if not spans.any():
            continue
        t = (latitude - lat1[spans]) / (lat2[spans] - lat1[spans])
        crossings = np.sort(lon1[spans] + t * (lon2[spans] - lon1[spans]))
        for x0, x1 in zip(crossings[0::2], crossings[1::2]):
            first = max(int(math.ceil((x0 - west) / size - 0.5)), 0)
            last = min(int(math.floor((x1 - west) / size - 0.5)), columns - 1)
            if first <= last:
                out_columns.append(np.arange(first, last + 1))
                out_rows.append(np.full(last - first + 1, top + k))
    if not out_rows:
        return np.zeros(0, int), np.zeros(0, int)
    return np.concatenate(out_rows), np.concatenate(out_columns)


# ------------------------------------------------------------- app's grids

def water_grid():
    with open(os.path.join(WORLD, 'taiwan_water.json'), encoding='utf-8') as f:
        data = json.load(f)
    rows, columns = data['rows'], data['columns']
    mask = np.zeros((rows, columns), dtype=bool)
    for numbers in data['water']:
        row, column = numbers[0], numbers[1]
        mask[row, column:column + numbers[2]] = True
        column += numbers[2]
        for gap, count in zip(numbers[3::2], numbers[4::2]):
            column += gap
            mask[row, column:column + count] = True
            column += count
    return data, mask


def read_varint_grid(path, magic):
    """A grid in the heights file's form (`build_slope_grid.encode_heights`)."""
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == magic, path
    _, _, north, west, size, rows, columns = struct.unpack('<HHdddII', data[4:40])
    offsets = np.frombuffer(data, dtype='<u4', count=rows + 1, offset=40)
    body = np.frombuffer(data, dtype=np.uint8, offset=40 + 4 * (rows + 1))
    # Every varint at once: a number ends at each byte without the high bit.
    ends = np.flatnonzero(body < 0x80)
    starts = np.concatenate(([0], ends[:-1] + 1))
    values = np.zeros(len(ends), dtype=np.int64)
    widest = int((ends - starts).max()) + 1
    for k in range(widest):
        at = starts + k
        live = at <= ends
        values[live] |= (body[at[live]].astype(np.int64) & 0x7F) << (7 * k)
    number_of_byte_end = np.searchsorted(ends, offsets[:-1].astype(np.int64))
    grid = np.zeros((rows, columns), dtype=np.int16)
    for row in range(rows):
        numbers = values[number_of_byte_end[row]:np.searchsorted(ends, int(offsets[row + 1]) - 1) + 1] if offsets[row + 1] > offsets[row] else values[:0]
        cells, i, previous, column = grid[row], 0, 0, 0
        while i < len(numbers) and column < columns:
            v = int(numbers[i])
            if v == 0:
                run = int(numbers[i + 1])
                cells[column:column + run] = previous
                column += run
                i += 2
            else:
                previous += (v >> 1) ^ -(v & 1)
                cells[column] = previous
                column += 1
                i += 1
    return {'north': north, 'west': west, 'cellDegrees': size, 'rows': rows, 'columns': columns}, grid


# ------------------------------------------------------------------- build

def round_keeping(values, total):
    """Whole numbers of `values` summing to `total` (the largest remainder,
    ties to the first)."""
    if total <= 0 or values.sum() <= 0:
        return np.zeros(len(values), dtype=np.int64)
    scaled = values * (total / values.sum())
    whole = np.floor(scaled).astype(np.int64)
    short = int(total - whole.sum())
    if short > 0:
        order = np.argsort(-(scaled - whole), kind='stable')
        whole[order[:short]] += 1
    return whole


def runs_of(counts, shape):
    """`counts` ({flat index: n}) as runs along rows."""
    rows, columns = shape
    out = []
    keys = sorted(k for k, v in counts.items() if v > 0)
    i = 0
    while i < len(keys):
        row, column = divmod(keys[i], columns)
        values = [int(counts[keys[i]])]
        j = i + 1
        while j < len(keys) and keys[j] == keys[j - 1] + 1 and keys[j] // columns == row:
            values.append(int(counts[keys[j]]))
            j += 1
        out.append({'r': row, 'c': column, 'p': values})
        i = j
    return out


def build(folder, places_path, out, compare=None):
    with open(os.path.join(WORLD, 'taiwan_places.json'), encoding='utf-8') as f:
        places30 = json.load(f)
    north, west = places30['north'], places30['west']
    cuts = places30['zones']['cuts']
    size = places30['cellDegrees'] / cuts
    water, wet = water_grid()
    cover_box, cover = read_varint_grid(os.path.join(WORLD, 'taiwan_coverage.dat'), b'TWCV')
    assert abs(cover_box['north'] - water['north']) < 1e-9 and abs(cover_box['west'] - water['west']) < 1e-9
    fine = water['cellDegrees']
    per = round(size / fine)
    row_shift = round((water['north'] - north) / fine)
    column_shift = round((west - water['west']) / fine)
    assert row_shift % per == 0 and column_shift % per == 0, (row_shift, column_shift)
    rows = (water['rows'] - row_shift) // per + 1
    columns = (water['columns'] - column_shift) // per + 1

    def coarse(r, c):
        """The 7.5″ cell of water-grid cells."""
        return (r - row_shift) // per, (c - column_shift) // per

    # The zone of each 7.5″ cell, as `PlaceGrid.zoneOfCell` finds it: the
    # kind most of its points are, if at least half, ties to industrial land,
    # then parks, then farmland (decision 93).
    samples = places30['zones']['samples']
    points = {}
    for zone in ('industrial', 'park', 'farmland'):
        for run in places30['zones']['layers'][zone]:
            for offset, n in enumerate(run['p']):
                k = run['r'] * columns + run['c'] + offset
                if n > points.get(k, (None, 0))[1]:
                    points[k] = (zone, n)
    zone_of = {k: zone for k, (zone, n) in points.items() if 2 * n >= samples}
    # The game lays out no one on a park or a factory (decision 93): people
    # live, and jobs other than the factories' are, on the cells round them.
    unlived = np.zeros(rows * columns, dtype=bool)
    for k, zone in zone_of.items():
        if zone in ('park', 'industrial') and k < rows * columns:
            unlived[k] = True
    parks = {k for k, zone in zone_of.items() if zone == 'park'}

    # ---- residents
    people_of_area, times = area_population(folder)
    areas = boundaries(folder)
    census = residents(folder)
    registered = register(folder)
    scale = {key: census[key] / registered[key] for key in census if registered.get(key)}
    township_float = {}
    unmatched = 0
    for area in areas:
        people = people_of_area.get(area['code'], 0)
        if not area['code'] in people_of_area:
            unmatched += 1
        if people <= 0 or not area['rings']:
            continue
        r, c = raster_cells(area['rings'], water['north'], water['west'], fine, water['rows'], water['columns'])
        if len(r) == 0:
            lat, lon = area['middle']
            r = np.array([int((water['north'] - lat) // fine)])
            c = np.array([int((lon - water['west']) // fine)])
        dry = ~wet[r, c]
        if dry.any():
            r, c = r[dry], c[dry]
        rr, cc = coarse(r, c)
        lived = ~unlived[np.clip(rr * columns + cc, 0, rows * columns - 1)]
        if lived.any():
            r, c = r[lived], c[lived]
        weights = np.clip(cover[r, c].astype(float), 0, None)
        if weights.sum() <= 0:
            weights = np.ones(len(r))
        share = people * weights / weights.sum()
        rr, cc = coarse(r, c)
        key = (area['county'], area['township'])
        cells = township_float.setdefault(key, {})
        for k, v in zip((rr * columns + cc).tolist(), share.tolist()):
            cells[k] = cells.get(k, 0.0) + v
    people = {}
    report = {'unmatchedAreas': unmatched, 'areas': len(areas), 'areasWithPeople': len(people_of_area), 'townships': {}}
    for key, cells in township_float.items():
        factor = scale.get(key)
        if factor is None:
            print('no census scale for', key, file=sys.stderr)
            factor = 1.0
        registered_now = sum(cells.values())
        keys = list(cells)
        whole = round_keeping(np.array([cells[k] for k in keys]), int(round(registered_now * factor)))
        for k, v in zip(keys, whole.tolist()):
            people[k] = people.get(k, 0) + v
        report['townships']['/'.join(key)] = {'registered': round(registered_now), 'scale': round(factor, 4)}

    # ---- jobs
    if places_path == '-':
        fine_places = {'cellDegrees': size, 'north': north, 'layers': {layer: [] for layer in JOBS_PER_PLACE}}
    else:
        with open(places_path, encoding='utf-8') as f:
            fine_places = json.load(f)
    assert abs(fine_places['cellDegrees'] - size) < 1e-12 and abs(fine_places['north'] - north) < 1e-9
    weights = {kind: {} for kind in ('office', 'shop', 'civic', 'leisure')}
    for layer, (kind, each) in JOBS_PER_PLACE.items():
        for run in fine_places['layers'][layer]:
            for offset, n in enumerate(run['p']):
                k = run['r'] * columns + run['c'] + offset
                weights[kind][k] = weights[kind].get(k, 0) + n * each
    # No one works in a park (decision 93 gives parks no one): its places'
    # jobs are its township's other cells'.
    for kind in weights:
        weights[kind] = {k: w for k, w in weights[kind].items() if k not in parks}
    # Industrial land: its share of a zone cell's points, times the 64 m
    # cells the zone cell holds, times the jobs of each.
    for run in places30['zones']['layers']['industrial']:
        for offset, n in enumerate(run['p']):
            r, c = run['r'], run['c'] + offset
            latitude = north - (r + 0.5) * size
            area = (size * 110_574.0) * (size * 111_320.0 * math.cos(math.radians(latitude)))
            k = r * columns + c
            weights['office'][k] = weights['office'].get(k, 0) + n / samples * area / CELL_METRES ** 2 * INDUSTRIAL_PER_CELL
    # The township of each 7.5″ cell: where most of its people live, else
    # the statistical area its middle lies in.
    township_of = {}
    for key, cells in township_float.items():
        for k, v in cells.items():
            if v > township_of.get(k, (None, -1))[1]:
                township_of[k] = (key, v)
    middles = {}
    for area in areas:
        r, c = raster_cells(area['rings'], north, west, size, rows, columns)
        for k in (r * columns + c).tolist():
            middles.setdefault(k, (area['county'], area['township']))
    def township(k):
        return township_of[k][0] if k in township_of else middles.get(k)
    engaged = persons_engaged(folder)
    by_township = {}
    for kind, cells in weights.items():
        for k, w in cells.items():
            key = township(k)
            if key is not None:
                by_township.setdefault(key, []).append((kind, k, w))
    jobs = {kind: {} for kind in weights}
    lost = 0
    for key, total in engaged.items():
        entries = by_township.get(key)
        if not entries:
            entries = [('office', k, v) for k, v in township_float.get(key, {}).items()]
        if not entries:
            lost += total
            continue
        whole = round_keeping(np.array([w for _, _, w in entries], dtype=float), total)
        for (kind, k, _), n in zip(entries, whole.tolist()):
            if n:
                jobs[kind][k] = jobs[kind].get(k, 0) + n
    report['jobsWithoutPlace'] = lost
    report['townshipsWithoutJobs'] = sorted('/'.join(k) for k in by_township if k not in engaged)

    grid = {
        'source': SOURCE,
        'licence': LICENCE,
        'credit': CREDIT,
        'statisticalAreasTime': sorted(set(times.values())),
        'north': north,
        'west': west,
        'cellDegrees': size,
        'runs': runs_of(people, (rows, columns)),
        'jobs': {kind: runs_of(cells, (rows, columns)) for kind, cells in jobs.items()},
    }
    text_out = json.dumps(grid, ensure_ascii=False, separators=(',', ':'))
    with open(out, 'w', encoding='utf-8') as f:
        f.write(text_out)
    totals = {'people': sum(people.values()), **{kind: sum(c.values()) for kind, c in jobs.items()}}
    print(json.dumps({'totals': totals, 'bytes': len(text_out.encode()), 'unmatchedAreas': unmatched,
                      'jobsWithoutPlace': lost}, ensure_ascii=False))
    record = {'decision': 1002, 'totals': totals, 'bytes': len(text_out.encode()), 'report': report,
              'files': {}}
    for path in sorted(glob.glob(os.path.join(folder, '**', '*'), recursive=True)):
        if os.path.isfile(path) and '/datasets/' not in path:
            with open(path, 'rb') as f:
                record['files'][os.path.relpath(path, folder)] = hashlib.sha256(f.read()).hexdigest()
    with open(RECORD, 'w', encoding='utf-8') as f:
        json.dump(record, f, ensure_ascii=False, indent=1)
        f.write('\n')
    if compare:
        with open(compare, encoding='utf-8') as f:
            old = json.load(f)
        print('before', sum(sum(r['p']) for r in old['runs']), 'after', totals['people'])


def main(argv):
    if len(argv) >= 2 and argv[0] == 'fetch':
        fetch(argv[1])
    elif len(argv) >= 4 and argv[0] == 'build':
        compare = argv[argv.index('--compare') + 1] if '--compare' in argv else None
        build(argv[1], argv[2], argv[3], compare)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
