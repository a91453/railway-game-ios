"""Japan's people and jobs on a map pack's population grid (decision 1000,
JAPAN-CENSUS-GRID): the 2020 Population Census (国勢調査) and the 2021
Economic Census for Business Activity (経済センサス‐活動調査), both counted
on the 500 m regional mesh (4次メッシュ, JGD2011) and published by e-Stat.

    python3 -I tools/census-grid/japan_census_grid.py fetch <extent-or-pack> <zips>
    python3 -I tools/census-grid/japan_census_grid.py build <zips> <pack> [--compare old.json]

`fetch` downloads the two tables of every first-order mesh (80 km) the
pack's extent touches into `<zips>` (some 7 MB for Fukuoka, Saga, Kumamoto
and Nagasaki); `build` writes the pack's `population.json`:

- the grid is 7.5″ square cells (1/480°, some 230 × 195 m in Kyushu) on the
  lattice of WorldPop's 30″ grid, its north-west corner the cut's, each run
  a row, its first column and the count of each cell from there on: the
  form of `taiwan_population.json` (`PopulationGrid`). A 500 m mesh cell is
  15″ × 22.5″, exactly 2 × 3 of these cells; its count is shared evenly
  among the six, the first `n mod 6` in row-major order (north-west first)
  one more. The cells whose middle lies in the extent are kept, as for
  WorldPop (`overseas_ground.population`).
- `runs` are the census's residents (人口（総数）, T001141001); a cell whose
  details are hidden (秘匿, HTKSYORI 2) still publishes its total.
- `jobs` are the economic census's persons engaged (従業者数, public
  offices included, T001162022–042) in the four kinds `LandImport` lays out:
  `shop` I (wholesale and retail) and M (hotels, restaurants); `civic` O
  (education), P (health and welfare) and S (government); `leisure` N
  (living-related services and amusement); `office` the rest of the total
  (agriculture, mining, building, factories, utilities, information,
  transport, finance, property, professional services, other services).

Licence: 政府統計の総合窓口（e-Stat）利用規約, which follows the Government
of Japan Standard Terms of Use 2.0 and is compatible with CC BY 4.0:
commercial use allowed, with the source named and changes said.
"""

import hashlib
import json
import math
import os
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
RECORD = os.path.join(HERE, 'japan_sources.json')

# The 7.5″ cell, in degrees, and the units the mesh is counted in.
UNITS = 480
CELL = 1 / UNITS

RESIDENTS = 'T001141'   # 令和2年国勢調査 人口及び世帯（JGD2011）（500mメッシュ）
WORKPLACES = 'T001162'  # 令和3年経済センサス‐活動調査 産業（大分類）別事業所数及び従業者数（JGD2011）（500mメッシュ）
TABLES = {
    RESIDENTS: '令和2年国勢調査 人口及び世帯（JGD2011）（500mメッシュ）',
    WORKPLACES: '令和3年経済センサス‐活動調査 産業（大分類）別事業所数及び従業者数（JGD2011）（500mメッシュ）',
}
URL = 'https://www.e-stat.go.jp/gis/statmap-search/data?statsId={table}&code={code}&downloadType=2'
SOURCE = ('Statistics Bureau of Japan (総務省統計局), via e-Stat: the 2020 Population Census (residents) and the '
          '2021 Economic Census for Business Activity (persons engaged), 500 m regional mesh (JGD2011), '
          'each mesh cell shared evenly over 2 x 3 cells of 7.5 arc-seconds, cut to the map')
LICENCE = '政府統計の総合窓口（e-Stat）利用規約 (Government of Japan Standard Terms of Use 2.0, compatible with CC BY 4.0)'
CREDIT = '「令和2年国勢調査」「令和3年経済センサス‐活動調査」（総務省統計局）（政府統計の総合窓口（e-Stat））を加工して作成'

# The persons-engaged columns of T001162 (its definition sheet).
JOBS_TOTAL = 22
JOB_COLUMNS = {'shop': (32, 36), 'civic': (38, 39, 42), 'leisure': (37,)}


def extent_of(path):
    """An extent from a pack folder's `pack.json` or a JSON file of one."""
    if os.path.isdir(path):
        path = os.path.join(path, 'pack.json')
    with open(path, encoding='utf-8') as f:
        value = json.load(f)
    return value.get('extent', value)


def first_meshes(extent):
    """The first-order mesh codes (40′ × 1°) the extent touches."""
    rows = range(math.floor(extent['south'] * 1.5), math.floor(extent['north'] * 1.5) + 1)
    columns = range(math.floor(extent['west']) - 100, math.floor(extent['east']) - 100 + 1)
    return [f'{row:02d}{column:02d}' for row in rows for column in columns]


def mesh_cell(code):
    """A 500 m mesh code's south-west corner in 7.5″ units: (latitude units,
    longitude units). The cell is 2 units tall and 3 wide."""
    code = str(code)
    if len(code) != 9:
        raise ValueError(f'{code}: not a 500 m mesh code')
    a, b = int(code[0:2]), int(code[2:4])
    e, f = int(code[4]), int(code[5])
    g, h = int(code[6]), int(code[7])
    quarter = int(code[8])
    if not (0 <= e <= 7 and 0 <= f <= 7 and 1 <= quarter <= 4):
        raise ValueError(f'{code}: not a 500 m mesh code')
    latitude = a * 320 + e * 40 + g * 4 + (2 if quarter in (3, 4) else 0)
    longitude = (b + 100) * 480 + f * 60 + h * 6 + (3 if quarter in (2, 4) else 0)
    return latitude, longitude


def read_table(path):
    """The rows of an e-Stat mesh table: its mesh code and its fields."""
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist() if n.lower().endswith('.txt')]
        if len(names) != 1:
            raise ValueError(f'{path}: {names}')
        text = archive.read(names[0]).decode('cp932')
    lines = text.splitlines()
    header = lines[0].split(',')
    rows = []
    for line in lines[2:]:
        if not line.strip():
            continue
        fields = line.split(',')
        rows.append((fields[0], fields))
    return header, rows


def number(text):
    """A count, with the census's hidden (`*`) and none (`-`, empty) as 0."""
    text = text.strip()
    if text in ('', '*', '-', 'X', 'x'):
        return 0
    return int(text)


def mesh_counts(folder, codes):
    """{(lat, lon): residents} and {(lat, lon): {kind: jobs}} per 500 m cell,
    and the files read with their digests."""
    residents, jobs, files = {}, {}, {}
    for code in codes:
        for table in (RESIDENTS, WORKPLACES):
            path = os.path.join(folder, f'{table}_{code}.zip')
            if not os.path.exists(path):
                sys.exit(f'{path}: missing (run fetch)')
            files[os.path.basename(path)] = hashlib.sha256(open(path, 'rb').read()).hexdigest()
            header, rows = read_table(path)
            if table == RESIDENTS:
                column = header.index(f'{RESIDENTS}001')
                for key, fields in rows:
                    people = number(fields[column])
                    if people:
                        cell = mesh_cell(key)
                        residents[cell] = residents.get(cell, 0) + people
            else:
                index = {name: i for i, name in enumerate(header)}

                def field(fields, n):
                    return number(fields[index[f'{WORKPLACES}{n:03d}']])
                for key, fields in rows:
                    total = field(fields, JOBS_TOTAL)
                    if not total:
                        continue
                    kinds = {kind: sum(field(fields, n) for n in columns) for kind, columns in JOB_COLUMNS.items()}
                    kinds['office'] = total - sum(kinds.values())
                    if kinds['office'] < 0:
                        sys.exit(f'{key}: its kinds add up to more than its total {total}')
                    cell = mesh_cell(key)
                    into = jobs.setdefault(cell, {})
                    for kind, count in kinds.items():
                        into[kind] = into.get(kind, 0) + count
    return residents, jobs, files


def spread(counts):
    """{(lat unit, lon unit): count} on the 7.5″ lattice: each 500 m cell's
    count shared evenly over its 2 × 3 cells, north-west first."""
    cells = {}
    for (south, west), count in counts.items():
        base, extra = divmod(count, 6)
        order = [(south + 1, west), (south + 1, west + 1), (south + 1, west + 2),
                 (south, west), (south, west + 1), (south, west + 2)]
        for i, cell in enumerate(order):
            share = base + (1 if i < extra else 0)
            if share:
                cells[cell] = cells.get(cell, 0) + share
    return cells


def cut(extent):
    """The lattice rows and columns whose middle lies in the extent: the
    northmost row's unit, the westmost column's unit, rows and columns."""
    top = math.floor(extent['north'] * UNITS - 0.5)
    bottom = math.ceil(extent['south'] * UNITS - 0.5)
    left = math.ceil(extent['west'] * UNITS - 0.5)
    right = math.floor(extent['east'] * UNITS - 0.5)
    return top, left, top - bottom + 1, right - left + 1


def runs(cells, box):
    top, left, rows, columns = box
    out = []
    for row in range(rows):
        unit = top - row
        line = [cells.get((unit, left + c), 0) for c in range(columns)]
        c = 0
        while c < columns:
            if line[c] <= 0:
                c += 1
                continue
            start = c
            while c < columns and line[c] > 0:
                c += 1
            out.append({'r': row, 'c': start, 'p': line[start:c]})
    return out


def total(rs):
    return sum(sum(r['p']) for r in rs)


def build(folder, pack, compare=None):
    extent = extent_of(pack)
    codes = first_meshes(extent)
    residents, jobs, files = mesh_counts(folder, codes)
    box = cut(extent)
    top, left, rows, columns = box
    people = runs(spread(residents), box)
    by_kind = {}
    for kind in ('office', 'shop', 'civic', 'leisure'):
        by_kind[kind] = runs(spread({cell: k[kind] for cell, k in jobs.items() if k.get(kind)}), box)
    value = {
        'source': SOURCE,
        'from': 'https://www.e-stat.go.jp/gis/statmap-search?page=1&type=1',
        'licence': LICENCE,
        'credit': CREDIT,
        'north': (top + 1) / UNITS,
        'west': left / UNITS,
        'cellDegrees': CELL,
        'runs': people,
        'jobs': by_kind,
    }
    out = os.path.join(pack, 'population.json') if os.path.isdir(pack) else pack
    # Read the file to compare with first: it may be the one written here.
    old = None
    if compare:
        with open(compare, encoding='utf-8') as f:
            old = json.load(f)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    record = {'tables': TABLES, 'url': URL, 'licence': LICENCE, 'credit': CREDIT, 'extent': extent,
              'files': dict(sorted(files.items())),
              'residents': total(people), 'jobs': {k: total(v) for k, v in by_kind.items()},
              'cells': [rows, columns]}
    with open(RECORD, 'w', encoding='utf-8') as f:
        json.dump(record, f, ensure_ascii=False, indent=1)
        f.write('\n')
    jobs_total = sum(total(v) for v in by_kind.values())
    print(f'{out}: {rows} x {columns} cells of 7.5", {total(people):,} residents, {jobs_total:,} jobs '
          f'({", ".join(f"{k} {total(v):,}" for k, v in by_kind.items())}), {os.path.getsize(out):,} bytes')
    if old:
        print(f'{compare}: {total(old["runs"]):,} residents on {old["cellDegrees"] * 3600:.1f}" cells')


def fetch(pack, folder):
    os.makedirs(folder, exist_ok=True)
    for code in first_meshes(extent_of(pack)):
        for table in (RESIDENTS, WORKPLACES):
            path = os.path.join(folder, f'{table}_{code}.zip')
            if os.path.exists(path):
                continue
            try:
                with urllib.request.urlopen(URL.format(table=table, code=code), timeout=120) as response:
                    data = response.read()
            except urllib.error.HTTPError as error:
                # A first-order mesh all sea has no table.
                print(f'{table} {code}: {error.code}, skipped')
                open(path, 'wb').write(_empty_table(table))
                continue
            open(path, 'wb').write(data)
            print(f'{table} {code}: {len(data):,} bytes')


def _empty_table(table):
    """A table with its header and no rows, for a mesh e-Stat has none of."""
    import io
    buffer = io.BytesIO()
    columns = {RESIDENTS: [f'{RESIDENTS}001'], WORKPLACES: [f'{WORKPLACES}{n:03d}' for n in range(1, 47)]}[table]
    with zipfile.ZipFile(buffer, 'w') as archive:
        archive.writestr(f'tbl{table}.txt', (','.join(['KEY_CODE', *columns]) + '\n\n').encode('cp932'))
    return buffer.getvalue()


def main(argv):
    if len(argv) >= 3 and argv[0] == 'fetch':
        fetch(argv[1], argv[2])
    elif len(argv) >= 3 and argv[0] == 'build':
        compare = argv[argv.index('--compare') + 1] if '--compare' in argv else None
        build(argv[1], argv[2], compare)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
