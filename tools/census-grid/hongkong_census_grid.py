"""Hong Kong's people and jobs on its map pack's population grid
(JAPAN-CENSUS-GRID's next step, decision 1008): the 2021 Population Census's
residents of the 2,342 Small Subunit Groups and the Quarterly Survey of
Employment and Vacancies' persons engaged of 2021 in each Tertiary Planning
Unit, both published by the Census and Statistics Department, laid on the
Planning Department's land use (2025, 10 m) so that each lives and works
where the homes and workplaces stand.

    pip install numpy pillow osmium   # osmium only for tools/hk-map's imports
    python3 -I tools/census-grid/hongkong_census_grid.py fetch <folder>
    python3 -I tools/census-grid/hongkong_census_grid.py build <folder> <pack> [--compare old.json]

`fetch` downloads into `<folder>` (some 120 MB, most of it the two
boundary files): the Small Subunit Groups' boundaries and populations, the
2021 Tertiary Planning Units' boundaries, table 215-16009 and the land use
tiles (`tools/hk-map/build_hk_landcover.py fetch`). `build` writes the
pack's `population.json`:

- the grid is 7.5″ square cells (1/480°, some 230 × 215 m in Hong Kong),
  the cells whose middle lies in the pack's extent, as Japan's
  (`japan_census_grid.cut`): the form of `taiwan_population.json` with
  `jobs` (decision 1000).
- Each cell is sampled at 10 × 10 points (0.75″, some 23 m apart). A point
  belongs to the Small Subunit Group and the Tertiary Planning Unit whose
  outline it lies in and has the land use of the 10 m pixel it falls in
  (`build_hk_ground_grids.hk80_grid`, as `landcover.dat`).
- A group's residents go to its points on housing (private, public and
  rural settlements); a group with none, to its built-up points; with none
  of those, to its land, then to all its points; a group too small to hold
  a point, to the cell of its outline's middle. Each cell gets the share of
  its points, rounded so the group's total stays whole (largest remainder,
  the earlier cell first on a tie).
- A Tertiary Planning Unit's jobs, in `LandImport`'s four kinds, go the
  same way to the points of their own land (`KIND_LAND`), then of any
  workplace, then built-up, land, then all.
- The industries (Hong Kong Standard Industrial Classification 2.0):
  `shop` G (import/export, wholesale and retail) and I (accommodation and
  food), as Japan's wholesale and retail and its hotels and restaurants;
  `civic` P (education) and Q (health and social work); `leisure` R (arts,
  entertainment and recreation) and S (other services: hairdressers,
  laundries, repairs ...); `office` B, C, D, E, H, J, K, L, M and N.
  Figures under 10 (shown `[-§35]`) are 0. The survey leaves out the civil
  service, construction sites, farming and fishing, and domestic helpers,
  so the jobs are some 2.6 million of the census's 3.6 million working.

Licences: DATA.GOV.HK Terms and Conditions of Use (the census statistics,
table 215-16009, the land use) and the CSDI Portal Terms and Conditions of
Use (the boundaries): free for commercial and non-commercial use, the
source identified and attributed to the Government, the Census and
Statistics Department, the Planning Department and DATA.GOV.HK.
"""

import hashlib
import json
import os
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'hk-map'))
import japan_census_grid as grid  # noqa: E402

RECORD = os.path.join(HERE, 'hongkong_sources.json')
UNITS = grid.UNITS
SUB = 10  # points per cell along each side

FILES = {
    'ssug.geojson': 'https://portal.csdi.gov.hk/csdi-webpage/file-api?dataset_id=censtatd_rcd_1635933365202_19171'
                    '&format=geojson&layer_name=SSUG_21C',
    'tpusu.geojson': 'https://portal.csdi.gov.hk/csdi-webpage/file-api?dataset_id=pland_rcd_1634022783366_65050'
                     '&format=geojson&layer_name=TPUSU_2021',
    '215-16009.json': 'https://www.censtatd.gov.hk/api/get.php?id=215-16009&lang=en&full_series=1',
}
PAGES = {
    'residents': 'https://data.gov.hk/en-data/dataset/hk-censtatd-census_geo-2021-population-census-by-ssg',
    'jobs': 'https://data.gov.hk/en-data/dataset/hk-censtatd-tablechart-215-16009',
    'units': 'https://data.gov.hk/en-data/dataset/hk-pland-pland1-boundaries-of-tpu-sb-vc',
    'land use': 'https://data.gov.hk/en-data/dataset/hk-pland-pland1-land-utilization-in-hong-kong-raster-grid',
}
YEAR = '2021'
SOURCE = ('Census and Statistics Department, Hong Kong SAR: the 2021 Population Census (residents of the Small Subunit '
          'Groups) and the Quarterly Survey of Employment and Vacancies, 2021 (persons engaged by Tertiary Planning Unit, '
          'table 215-16009); Planning Department: the Tertiary Planning Units of 2021 and the 2025 Raster Grids on Land '
          'Utilization, on which each is spread over its homes and workplaces; 7.5 arc-second cells cut to the map')
LICENCE = ('DATA.GOV.HK Terms and Conditions of Use; CSDI Portal Terms and Conditions of Use (commercial use allowed, '
           'the source identified)')
CREDIT = ('2021 Population Census and Quarterly Survey of Employment and Vacancies, Census and Statistics Department; '
          'Tertiary Planning Units and Land Utilization, Planning Department; Government of the Hong Kong SAR, via '
          'DATA.GOV.HK and the CSDI Portal. Processed for the game.')

INDUSTRIES = {
    'office': ('B', 'C', 'D', 'E', 'H', 'J', 'K', 'L', 'M', 'N'),
    'shop': ('G', 'I'),
    'civic': ('P', 'Q'),
    'leisure': ('R', 'S'),
}
KINDS = ('office', 'shop', 'civic', 'leisure')

# Land use codes (`build_hk_landcover`'s docstring; 1 is all housing).
HOUSING = (1, 3)
WORKPLACE = (11, 21, 22, 23, 31, 43, 44, 52, 54)
KIND_LAND = {
    'office': (11, 21, 22, 23, 43, 44, 52, 54),  # commercial, industrial, storage, airport, port, utilities, others
    'shop': (11, 1, 3, 43),                       # commercial, the shops under the flats, the airport's
    'civic': (31,),                               # government, institutions and community
    'leisure': (11, 32),                          # commercial, open space and recreation
}

# Places the grid must get right: (name, latitude, longitude, what).
CHECKS = [
    ('Central', 22.2820, 114.1580, 'more jobs than residents'),
    ('Kwun Tong', 22.3115, 114.2245, 'more jobs than residents'),
    ('Tin Shui Wai', 22.4600, 114.0020, 'more residents than jobs'),
    ('Tseung Kwan O', 22.3075, 114.2600, 'more residents than jobs'),
]


def sha256(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def fetch(folder):
    os.makedirs(folder, exist_ok=True)
    for name, url in FILES.items():
        path = os.path.join(folder, name)
        if os.path.exists(path):
            continue
        with urllib.request.urlopen(url, timeout=600) as response:
            data = response.read()
        if not data.lstrip().startswith(b'{'):
            sys.exit(f'{url}: not JSON (the portal refused it?)')
        open(path, 'wb').write(data)
        print(f'{name}: {len(data):,} bytes')
    import build_hk_landcover
    build_hk_landcover.fetch(os.path.join(folder, 'landuse'))


def jobs_by_unit(path):
    """{TPU code: {kind: persons engaged}} of YEAR."""
    rows = json.load(open(path, encoding='utf-8'))['dataSet']
    kind_of = {letter: kind for kind, letters in INDUSTRIES.items() for letter in letters}
    units = {}
    for row in rows:
        if row['period'] != YEAR or row['sv'] != 'PE' or row['TPUDesc'] == 'Total':
            continue
        letter = row['IND'][len('ind_'):]
        if letter not in kind_of:
            continue  # the sums of sections (B_D_E, M_N, P_S ...)
        figure = row['figure'] if isinstance(row['figure'], (int, float)) else 0
        into = units.setdefault(str(row['TPU']), {k: 0 for k in KINDS})
        into[kind_of[letter]] += int(figure)
    return units


def rings(geometry):
    """A (Multi)Polygon's polygons, each a list of rings of (lon, lat)."""
    if geometry['type'] == 'Polygon':
        return [geometry['coordinates']]
    if geometry['type'] == 'MultiPolygon':
        return geometry['coordinates']
    raise ValueError(geometry['type'])


def ring_area(ring):
    xs, ys = np.array([p[0] for p in ring]), np.array([p[1] for p in ring])
    return abs(float(np.dot(xs, np.roll(ys, 1)) - np.dot(ys, np.roll(xs, 1)))) / 2


def label(features, box):
    """The point raster (SUB × SUB a cell) of the feature each point lies
    in, 1-based (0 none), the larger drawn first so a hole's own feature
    is drawn over it; and each feature's middle."""
    from PIL import Image, ImageDraw
    top, left, rows, columns = box
    north, west = (top + 1) / UNITS, left / UNITS
    scale = UNITS * SUB
    image = Image.new('I', (columns * SUB, rows * SUB), 0)
    draw = ImageDraw.Draw(image)

    def xy(ring):
        return [((lon - west) * scale - 0.5, (north - lat) * scale - 0.5) for lon, lat, *_ in ring]
    order = sorted(range(len(features)), key=lambda i: -sum(ring_area(p[0]) for p in rings(features[i]['geometry'])))
    middles = {}
    for i in order:
        polygons = rings(features[i]['geometry'])
        biggest = max(polygons, key=lambda p: ring_area(p[0]))[0]
        middles[i + 1] = (float(np.mean([p[1] for p in biggest])), float(np.mean([p[0] for p in biggest])))
        for polygon in polygons:
            draw.polygon(xy(polygon[0]), fill=i + 1)
            for hole in polygon[1:]:
                draw.polygon(xy(hole), fill=0)
    return np.array(image, dtype=np.int32), middles


def land_points(landuse, box):
    """The land use code of every point (0 the sea and outside Hong Kong)."""
    import build_hk_landcover as lc
    from build_hk_ground_grids import hk80_grid
    codes, _, _ = lc.land_codes(landuse)
    top, left, rows, columns = box
    north, west = (top + 1) / UNITS, left / UNITS
    out = np.zeros((rows * SUB, columns * SUB), dtype=np.uint8)
    lon = west + (np.arange(columns * SUB) + 0.5) / (UNITS * SUB)
    for r in range(rows * SUB):
        lat = np.full_like(lon, north - (r + 0.5) / (UNITS * SUB))
        e, n = hk80_grid(lat, lon)
        pr = np.floor((lc.NORTH - n) / lc.PIXEL).astype(np.int64)
        pc = np.floor((e - lc.WEST) / lc.PIXEL).astype(np.int64)
        inside = (pr >= 0) & (pr < codes.shape[0]) & (pc >= 0) & (pc < codes.shape[1])
        out[r, inside] = codes[pr[inside], pc[inside]]
    return out


def allocate(zones, counts, levels, middles, box):
    """{cell: count}: each zone's count over its points, by the first of
    `levels` (boolean point rasters) the zone has a point of. Returns the
    cells and the count no point or middle of the map could take."""
    top, left, rows, columns = box
    flat_zone = zones.ravel()
    cell_of = ((np.arange(rows * SUB)[:, None] // SUB) * columns + (np.arange(columns * SUB)[None, :] // SUB)).ravel()
    n_zones = int(flat_zone.max()) + 1
    choice = np.full(n_zones, -1)
    for k in range(len(levels) - 1, -1, -1):
        has = np.bincount(flat_zone[levels[k].ravel()], minlength=n_zones) > 0
        choice[has] = k
    weight = np.zeros(flat_zone.shape, dtype=bool)
    for k, level in enumerate(levels):
        weight |= level.ravel() & (choice[flat_zone] == k)
    weight &= flat_zone > 0
    key = flat_zone[weight].astype(np.int64) * (rows * columns) + cell_of[weight]
    unique, points = np.unique(key, return_counts=True)
    zone_of, cell_at = unique // (rows * columns), unique % (rows * columns)
    cells, lost = {}, 0
    starts = np.searchsorted(zone_of, np.arange(n_zones + 1))
    for z, n in counts.items():
        if n <= 0:
            continue
        a, b = starts[z], starts[z + 1]
        if a == b:
            lat, lon = middles[z]
            r, c = int(np.floor(((top + 1) / UNITS - lat) * UNITS)), int(np.floor((lon - left / UNITS) * UNITS))
            if 0 <= r < rows and 0 <= c < columns:
                cells[(top - r, left + c)] = cells.get((top - r, left + c), 0) + n
            else:
                lost += n
            continue
        w = points[a:b].astype(np.float64)
        exact = n * w / w.sum()
        whole = np.floor(exact).astype(np.int64)
        rest = n - int(whole.sum())
        if rest:
            order = np.lexsort((np.arange(len(exact)), -(exact - whole)))
            whole[order[:rest]] += 1
        for cell, share in zip(cell_at[a:b].tolist(), whole.tolist()):
            if share:
                key2 = (top - cell // columns, left + cell % columns)
                cells[key2] = cells.get(key2, 0) + share
    return cells, lost


def near(cells, box, latitude, longitude, metres=800):
    top, left, rows, columns = box
    total = 0
    for (unit, column), n in cells.items():
        lat, lon = (unit + 0.5) / UNITS, (column + 0.5) / UNITS
        dy = (lat - latitude) * 110_574
        dx = (lon - longitude) * 111_320 * np.cos(np.radians(latitude))
        if dx * dx + dy * dy <= metres * metres:
            total += n
    return total


def build(folder, pack, compare=None):
    extent = grid.extent_of(pack)
    box = grid.cut(extent)
    top, left, rows, columns = box
    files = {name: sha256(os.path.join(folder, name)) for name in FILES}

    groups = json.load(open(os.path.join(folder, 'ssug.geojson'), encoding='utf-8'))['features']
    units_features = json.load(open(os.path.join(folder, 'tpusu.geojson'), encoding='utf-8'))['features']
    jobs = jobs_by_unit(os.path.join(folder, '215-16009.json'))

    land = land_points(os.path.join(folder, 'landuse'), box)
    is_land = land > 0
    built = np.isin(land, [c for c, cover in __import__('build_hk_landcover').FOLD.items() if cover == 5])
    everywhere = np.ones_like(is_land)

    group_zones, group_middles = label(groups, box)
    residents = {i + 1: int(f['properties']['t_pop']) for i, f in enumerate(groups)}
    people, people_lost = allocate(group_zones, residents, [np.isin(land, HOUSING), built, is_land, everywhere],
                                   group_middles, box)

    # The units' subunits drawn as one unit each.
    codes = sorted({str(f['properties']['TPU']) for f in units_features})
    index = {code: i + 1 for i, code in enumerate(codes)}
    unit_features = []
    for f in units_features:
        unit_features.append({'geometry': f['geometry'], 'unit': index[str(f['properties']['TPU'])]})
    sub_zones, sub_middles = label(unit_features, box)
    mapping = np.zeros(len(unit_features) + 1, dtype=np.int32)
    for i, f in enumerate(unit_features):
        mapping[i + 1] = f['unit']
    unit_zones = mapping[sub_zones]
    unit_middles = {}
    for i, f in enumerate(unit_features):
        unit_middles.setdefault(f['unit'], sub_middles[i + 1])
    missing = sorted(set(jobs) - set(index))
    if missing:
        sys.exit(f'table 215-16009 has units with no outline: {missing}')
    workplace = np.isin(land, WORKPLACE)
    by_kind, jobs_lost = {}, 0
    for kind in KINDS:
        counts = {index[code]: k[kind] for code, k in jobs.items()}
        cells, lost = allocate(unit_zones, counts, [np.isin(land, KIND_LAND[kind]), workplace, built, everywhere],
                               unit_middles, box)
        by_kind[kind] = cells
        jobs_lost += lost

    people_runs = grid.runs(people, box)
    job_runs = {kind: grid.runs(cells, box) for kind, cells in by_kind.items()}
    value = {
        'source': SOURCE,
        'from': PAGES['residents'],
        'licence': LICENCE,
        'credit': CREDIT,
        'north': (top + 1) / UNITS,
        'west': left / UNITS,
        'cellDegrees': grid.CELL,
        'runs': people_runs,
        'jobs': job_runs,
    }

    failed = []
    for name, lat, lon, want in CHECKS:
        home = near(people, box, lat, lon)
        work = sum(near(cells, box, lat, lon) for cells in by_kind.values())
        print(f'  {name}: {home:,} residents, {work:,} jobs within 800 m')
        if (want == 'more jobs than residents') != (work > home):
            failed.append(f'{name}: {home} residents, {work} jobs, want {want}')
    if failed:
        sys.exit('; '.join(failed))

    out = os.path.join(pack, 'population.json') if os.path.isdir(pack) else pack
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    calibration = json.load(open(os.path.join(folder, 'landuse', 'calibration.json')))
    record = {
        'pages': PAGES, 'files': {name: {'from': FILES[name], 'sha256': digest} for name, digest in files.items()},
        'land use tiles': calibration['tiles'], 'year of jobs': YEAR,
        'licence': LICENCE, 'credit': CREDIT, 'extent': extent, 'industries': INDUSTRIES,
        'residents in the census': sum(residents.values()), 'residents': grid.total(people_runs),
        'residents off the map': people_lost,
        'jobs in the table': {kind: sum(k[kind] for k in jobs.values()) for kind in KINDS},
        'jobs': {kind: grid.total(r) for kind, r in job_runs.items()}, 'jobs off the map': jobs_lost,
        'cells': [rows, columns],
    }
    with open(RECORD, 'w', encoding='utf-8') as f:
        json.dump(record, f, ensure_ascii=False, indent=1)
        f.write('\n')
    jobs_total = sum(grid.total(r) for r in job_runs.values())
    print(f'{out}: {rows} x {columns} cells of 7.5", {grid.total(people_runs):,} residents '
          f'({people_lost:,} off the map), {jobs_total:,} jobs '
          f'({", ".join(f"{k} {grid.total(r):,}" for k, r in job_runs.items())}; {jobs_lost:,} off the map), '
          f'{os.path.getsize(out):,} bytes')
    if compare:
        with open(compare, encoding='utf-8') as f:
            old = json.load(f)
        print(f'{compare}: {grid.total(old["runs"]):,} residents on {old["cellDegrees"] * 3600:.1f}" cells')


def main(argv):
    if len(argv) >= 2 and argv[0] == 'fetch':
        fetch(argv[1])
    elif len(argv) >= 3 and argv[0] == 'build':
        compare = argv[argv.index('--compare') + 1] if '--compare' in argv else None
        build(argv[1], argv[2], compare)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
