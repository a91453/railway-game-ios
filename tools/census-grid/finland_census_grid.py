"""Finland's people and jobs on a map pack's population grid (decision 1007,
FINLAND-CENSUS-GRID), in the form of decision 1000's `population.json`:
Statistics Finland's open population grid (Väestöruutuaineisto 1 km × 1 km
2025: residents at the end of 2024) and the workplaces of its open postal
code statistics (Paavo 2025), each spread over the pack's own buildings.

    python3 -I tools/census-grid/finland_census_grid.py fetch <pack> <folder>
    python3 -I tools/census-grid/finland_census_grid.py build <folder> <pack> [--compare old.json]

`fetch` asks Statistics Finland's open WFS (`geo.stat.fi`) for the 1 km
cells and the postal code areas the pack's extent touches (some 0.6 MB for
Rovaniemi) into `<folder>`; `build` writes the pack's `population.json`:

- the grid is Japan's (`japan_census_grid.py`): 7.5″ square cells (1/480°,
  some 231 m north to south and 93 m east to west at 66.5° N) on the lattice
  of WorldPop's 30″ grid, the cells whose middle lies in the extent kept,
  each run a row (`PopulationGrid`).
- `runs` are the 1 km grid's residents (`vaesto`, every inhabited cell, the
  smallest too). The 1 km cells are on ETRS-TM35FIN; a 7.5″ cell belongs to
  the 1 km cell its middle lies in. A 1 km cell's residents go to its 7.5″
  cells by the floor area (footprint × storeys) of the buildings people live
  in there (the pack's `buildings.pmtiles`: residential, and untagged
  `building=yes`, which is most houses in Lapland), else of any building,
  else evenly; rounded by the largest remainder, so each 1 km cell keeps
  its count.
- `jobs` are Paavo's workplaces (`tp_tyopy`, by industry, TOL 2008) in the
  four kinds `LandImport` lays out: `shop` G (trade) and I (hotels and
  restaurants); `civic` O (public administration), P (education) and Q
  (health and social work); `leisure` R (arts and recreation) and S (other
  services); `office` the rest of the total (farming, forestry, factories,
  building, transport, information, finance, property, professional
  services, unknown). A postal area's jobs of a kind go to its 7.5″ cells
  (a cell belongs to the area its middle lies in): WORK_SHARE of them by
  the floor area of the buildings of that kind (WORK_USES; else of any
  building but houses and sheds), the rest by the floor area of every
  building (home care, and the shops and workshops in buildings OSM leaves
  untagged); with no building at all, evenly. An area reaching past the map
  keeps the part of its jobs that its residents inside the map are of its
  residents (or of its land, when nobody lives there).

Statistics Finland's 250 m grid and its 1 km grid of workplaces (the Grid
Database, Ruututietokanta) are sold, not open, and may not be passed on:
this tool reads only the open data.

Licence: CC BY 4.0 (Statistics Finland's open data). Credit: "Source:
Statistics Finland, Population grid data 1 km × 1 km 2025 and Paavo – Open
data by postal code area 2025".
"""

import gzip
import hashlib
import json
import math
import os
import sys
import urllib.parse
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
sys.path.insert(0, os.path.join(HERE, '..', 'fukuoka-map'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
import japan_census_grid as japan  # noqa: E402

RECORD = os.path.join(HERE, 'finland_sources.json')
UNITS, CELL = japan.UNITS, japan.CELL

WFS = 'https://geo.stat.fi/geoserver/wfs'
GRID = 'vaestoruutu:vaki2025_1km'
POSTAL = 'postialue:pno_tilasto_2025'
TABLES = {
    GRID: 'Väestöruutuaineisto 1 km x 1 km 2025 (population on 31 December 2024)',
    POSTAL: 'Paavo-tilastoaineisto ja -postinumeroalueet 2025 (workplaces by industry, TOL 2008)',
}
FILES = {GRID: 'vaki2025_1km.json', POSTAL: 'pno_tilasto_2025.json'}
SOURCE = ('Statistics Finland (Tilastokeskus): Population grid data 1 km x 1 km 2025 (residents) and Paavo 2025 '
          '(workplaces by postal code area), each spread over the map\'s buildings on cells of 7.5 arc-seconds, '
          'cut to the map')
FROM = 'https://stat.fi/en/services/statistical-data-services/geographic-data'
LICENCE = 'CC BY 4.0'
CREDIT = ('Source: Statistics Finland, Population grid data 1 km × 1 km 2025 and Paavo – Open data by postal code '
          'area 2025')
# Past the extent, in degrees, so the 1 km cells at its edge are whole
# (0.03° of longitude is 1.3 km here).
MARGIN = 0.03

# Paavo's workplaces by industry (TOL 2008 sections).
JOB_FIELDS = {'shop': ('tp_g_kaup', 'tp_i_majo'),
              'civic': ('tp_o_julk', 'tp_p_koul', 'tp_q_terv'),
              'leisure': ('tp_r_taid', 'tp_s_muup')}
# The buildings people live in, and those each kind of job is in
# (`build_footprint_tiles.USES`; 'none' is an untagged `building=yes`).
HOME_USES = {'residential', 'none'}
WORK_USES = {'shop': {'commercial'},
             'leisure': {'commercial', 'entertainment', 'religious'},
             'civic': {'civic', 'education', 'medical', 'military'},
             'office': {'commercial', 'industrial', 'service', 'transportation', 'agricultural', 'civic'}}
NOT_WORK = {'residential', 'none', 'outbuilding'}
# The part of a postal area's jobs of a kind in the buildings of that kind;
# the rest go by every building's floor area.
WORK_SHARE = 0.8


def extent_of(pack):
    return japan.extent_of(pack)


# ETRS-TM35FIN, as `tools/rovaniemi-map/fetch_nls_dem.py` has it (that
# module reads the OSM extract's tools, so it is not imported here).
TM35_MERIDIAN, TM35_SCALE, TM35_EASTING = 27.0, 0.9996, 500_000.0


def tm35(latitudes, longitudes):
    """ETRS-TM35FIN eastings and northings of places in degrees."""
    import build_slope_grid
    easting, northing = build_slope_grid.tm2(np.asarray(latitudes, float), np.asarray(longitudes, float),
                                             TM35_MERIDIAN)
    ratio = TM35_SCALE / build_slope_grid.TM2_SCALE
    return TM35_EASTING + (easting - build_slope_grid.TM2_EASTING) * ratio, northing * ratio


# --- fetch ---------------------------------------------------------------

def fetch(pack, folder):
    extent = extent_of(pack)
    os.makedirs(folder, exist_ok=True)
    box = (extent['south'] - MARGIN, extent['west'] - MARGIN, extent['north'] + MARGIN, extent['east'] + MARGIN)
    for layer, name in FILES.items():
        query = {'service': 'WFS', 'version': '2.0.0', 'request': 'GetFeature', 'typeNames': layer,
                 'outputFormat': 'application/json', 'count': '100000',
                 'bbox': ','.join(f'{v:.4f}' for v in box) + ',urn:ogc:def:crs:EPSG::4326'}
        url = f'{WFS}?{urllib.parse.urlencode(query)}'
        with urllib.request.urlopen(url, timeout=300) as response:
            data = response.read()
        features = json.loads(data)['features']
        with open(os.path.join(folder, name), 'wb') as f:
            f.write(data)
        print(f'{layer}: {len(features)} features, {len(data):,} bytes')


# --- the lattice ------------------------------------------------------------

def lattice(extent, margin):
    """The 7.5″ cells over the extent and a margin: (south unit of the top
    row, west unit of the first column, rows, columns), and their middles'
    latitudes, longitudes and TM35 eastings and northings (rows × columns)."""
    top = math.floor((extent['north'] + margin) * UNITS - 0.5)
    bottom = math.ceil((extent['south'] - margin) * UNITS - 0.5)
    left = math.ceil((extent['west'] - margin) * UNITS - 0.5)
    right = math.floor((extent['east'] + margin) * UNITS - 0.5)
    rows, columns = top - bottom + 1, right - left + 1
    latitudes = (top - np.arange(rows) + 0.5) / UNITS
    longitudes = (left + np.arange(columns) + 0.5) / UNITS
    lat, lon = np.meshgrid(latitudes, longitudes, indexing='ij')
    east, north = tm35(lat, lon)
    return (top, left, rows, columns), east, north


# --- buildings --------------------------------------------------------------

def buildings(pack_folder, box):
    """Floor area (m²) by use on the lattice: {use: rows × columns array},
    from the pack's `buildings.pmtiles`, each building in the cell of its
    outline's middle."""
    import build_footprint_tiles as tiles
    import split_prefectures
    path = os.path.join(pack_folder, 'buildings.pmtiles')
    (compression, _type, _min, _max), _meta, archive = split_prefectures.read_pmtiles(path)
    top, left, rows, columns = box
    floors = {}
    for tile_id, blob in archive.items():
        z, tx, ty = split_prefectures.zxy(tile_id)
        if z != tiles.ZOOM:
            continue
        data = gzip.decompress(blob) if compression == 2 else blob
        for storeys, use, _source, rings, _origin in tiles.decode_tile(data):
            outline = rings[0]
            twice = 0
            for (x0, y0), (x1, y1) in zip(outline, outline[1:] + outline[:1]):
                twice += x0 * y1 - x1 * y0
            for hole in rings[1:]:
                for (x0, y0), (x1, y1) in zip(hole, hole[1:] + hole[:1]):
                    twice += x0 * y1 - x1 * y0
            cx = tx + sum(x for x, _ in outline) / len(outline) / tiles.EXTENT
            cy = ty + sum(y for _, y in outline) / len(outline) / tiles.EXTENT
            n = 1 << tiles.ZOOM
            lon = cx / n * 360 - 180
            lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * cy / n))))
            metre = 1 / (tiles.UNIT * math.cos(math.radians(lat)))
            area = abs(twice) / 2 / metre ** 2 * max(1, storeys)
            row = top - math.floor(lat * UNITS)
            column = math.floor(lon * UNITS) - left
            if 0 <= row < rows and 0 <= column < columns:
                name = tiles.USES[use - 1] if use else 'none'
                grid = floors.setdefault(name, np.zeros((rows, columns)))
                grid[row, column] += area
    digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()
    return floors, digest


def floor_of(floors, uses, shape):
    out = np.zeros(shape)
    for use in uses:
        if use in floors:
            out += floors[use]
    return out


# --- spreading --------------------------------------------------------------

def shares(count, weights):
    """`count` over `weights` (a 1-D array, all ≥ 0, some > 0) in whole
    numbers by the largest remainder, ties to the first."""
    exact = count * weights / weights.sum()
    whole = np.floor(exact).astype(np.int64)
    left = count - int(whole.sum())
    if left:
        order = np.lexsort((np.arange(len(exact)), -(exact - whole)))
        whole[order[:left]] += 1
    return whole


def spread_over(count, cells, tiers):
    """`count` over the cells (flat indices), by the first weight in `tiers`
    that is not all zero there, else evenly."""
    for weights in tiers:
        w = weights[cells]
        if w.sum() > 0:
            return shares(count, w)
    return shares(count, np.ones(len(cells)))


def mixed(cells, tiers):
    """A postal area's tiers for one kind of job: WORK_SHARE of the jobs by
    the buildings of that kind, the rest by every building (the home
    carers, the shops and workshops in untagged buildings), where the area
    has both."""
    specific, work, every = (t[cells] for t in tiers)
    first = specific if specific.sum() > 0 else work
    if first.sum() > 0 and every.sum() > 0:
        blend = WORK_SHARE * first / first.sum() + (1 - WORK_SHARE) * every / every.sum()
        out = np.zeros(len(tiers[0]))
        out[cells] = blend
        return (out,)
    return tiers


def residents(grid_features, east, north, floors):
    """Residents on the lattice (rows × columns ints)."""
    shape = east.shape
    home = floor_of(floors, HOME_USES, shape).ravel()
    every = floor_of(floors, floors.keys(), shape).ravel()
    key = (np.floor(east / 1000).astype(np.int64) * 100_000 + np.floor(north / 1000).astype(np.int64)).ravel()
    order = np.argsort(key, kind='stable')
    sorted_keys = key[order]
    out = np.zeros(key.size, np.int64)
    placed = missed = 0
    for feature in grid_features:
        p = feature['properties']
        people = int(p['vaesto'])
        if people <= 0:
            continue
        k = int(p['xkoord']) // 1000 * 100_000 + int(p['ykoord']) // 1000
        lo, hi = np.searchsorted(sorted_keys, [k, k + 1])
        cells = np.sort(order[lo:hi])
        if not len(cells):
            missed += people
            continue
        out[cells] += spread_over(people, cells, (home, every))
        placed += people
    return out.reshape(shape), placed, missed


def postal_areas(postal_features, east, north):
    """Each lattice cell's postal area (index into the features, -1 none)."""
    import shapely
    from shapely.geometry import shape as geometry
    area = np.full(east.shape, -1, np.int64)
    for i, feature in enumerate(postal_features):
        polygon = geometry(feature['geometry'])
        x0, y0, x1, y1 = polygon.bounds
        near = (east >= x0) & (east <= x1) & (north >= y0) & (north <= y1) & (area < 0)
        if not near.any():
            continue
        inside = shapely.contains_xy(polygon, east[near], north[near])
        rows, columns = np.nonzero(near)
        area[rows[inside], columns[inside]] = i
    return area


def jobs(postal_features, area, people, floors, latitudes_of_rows, kept):
    """{kind: rows × columns ints} of jobs, and what each area kept."""
    shape = area.shape
    tiers = {kind: (floor_of(floors, uses, shape).ravel(),
                    floor_of(floors, set(floors) - NOT_WORK, shape).ravel(),
                    floor_of(floors, floors.keys(), shape).ravel())
             for kind, uses in WORK_USES.items()}
    cell_m2 = (CELL * 110_574.0) * (CELL * 111_320.0 * np.cos(np.radians(latitudes_of_rows)))
    flat_area = np.where(kept, area, -1).ravel()
    cell_area = np.repeat(cell_m2[:, None], shape[1], axis=1).ravel()
    flat_people = people.ravel()
    out = {kind: np.zeros(flat_area.size, np.int64) for kind in WORK_USES}
    record = {}
    for i, feature in enumerate(postal_features):
        p = feature['properties']
        cells = np.nonzero(flat_area == i)[0]
        total = int(p['tp_tyopy'] or 0)
        if total <= 0 or not len(cells):
            continue
        kinds = {kind: sum(int(p[f] or 0) for f in fields) for kind, fields in JOB_FIELDS.items()}
        kinds['office'] = total - sum(kinds.values())
        if kinds['office'] < 0:
            sys.exit(f'{p["postinumeroalue"]}: its kinds add up to more than its total {total}')
        land = float(cell_area[cells].sum()) / float(p['pinta_ala'])
        living = int(p['he_vakiy'] or 0)
        if land >= 0.98:
            part = 1.0
        elif living > 0:
            part = min(1.0, int(flat_people[cells].sum()) / living)
        else:
            part = min(1.0, land)
        for kind, count in kinds.items():
            n = round(count * part)
            if n:
                out[kind][cells] += spread_over(n, cells, mixed(cells, tiers[kind]))
        record[p['postinumeroalue']] = {'name': p['nimi'], 'workplaces': total, 'kept': round(part, 3)}
    return {kind: v.reshape(shape) for kind, v in out.items()}, record


# --- build ------------------------------------------------------------------

def build(folder, pack, compare=None):
    extent = extent_of(pack)
    pack_folder = pack if os.path.isdir(pack) else os.path.dirname(pack)
    features, files = {}, {}
    for layer, name in FILES.items():
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            sys.exit(f'{path}: missing (run fetch)')
        raw = open(path, 'rb').read()
        files[name] = hashlib.sha256(raw).hexdigest()
        features[layer] = json.loads(raw)['features']
    box, east, north = lattice(extent, MARGIN)
    top, left, rows, columns = box
    floors, buildings_digest = buildings(pack_folder, box)
    people, placed, missed = residents(features[GRID], east, north, floors)
    # The WFS gives every 1 km cell the margin's box touches; those only
    # grazing it hold no 7.5" cell and lie well past the map.
    cut_top, cut_left, cut_rows, cut_columns = japan.cut(extent)
    r0, c0 = top - cut_top, cut_left - left
    kept = np.zeros((rows, columns), bool)
    kept[r0:r0 + cut_rows, c0:c0 + cut_columns] = True
    area = postal_areas(features[POSTAL], east, north)
    latitudes = (top - np.arange(rows) + 0.5) / UNITS
    by_kind, areas = jobs(features[POSTAL], area, np.where(kept, people, 0), floors, latitudes, kept)

    def cells_of(grid):
        part = grid[r0:r0 + cut_rows, c0:c0 + cut_columns]
        return {(cut_top - r, cut_left + c): int(part[r, c]) for r, c in zip(*np.nonzero(part))}

    cut_box = (cut_top, cut_left, cut_rows, cut_columns)
    runs = japan.runs(cells_of(people), cut_box)
    job_runs = {kind: japan.runs(cells_of(by_kind[kind]), cut_box) for kind in ('office', 'shop', 'civic', 'leisure')}
    value = {
        'source': SOURCE, 'from': FROM, 'licence': LICENCE, 'credit': CREDIT,
        'north': (cut_top + 1) / UNITS, 'west': cut_left / UNITS, 'cellDegrees': CELL,
        'runs': runs, 'jobs': job_runs,
    }
    out = os.path.join(pack, 'population.json') if os.path.isdir(pack) else pack
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    record = {'decision': 1007, 'tables': TABLES, 'wfs': WFS, 'licence': LICENCE, 'credit': CREDIT,
              'extent': extent, 'files': dict(sorted(files.items())),
              'buildings.pmtiles': buildings_digest,
              'residents': japan.total(runs), 'jobs': {k: japan.total(v) for k, v in job_runs.items()},
              'cells': [cut_rows, cut_columns], 'postalAreas': dict(sorted(areas.items()))}
    with open(RECORD, 'w', encoding='utf-8') as f:
        json.dump(record, f, ensure_ascii=False, indent=1)
        f.write('\n')
    jobs_total = sum(japan.total(v) for v in job_runs.values())
    print(f'{out}: {cut_rows} x {cut_columns} cells of 7.5", {japan.total(runs):,} residents, {jobs_total:,} jobs '
          f'({", ".join(f"{k} {japan.total(v):,}" for k, v in job_runs.items())}), {os.path.getsize(out):,} bytes')
    if compare:
        with open(compare, encoding='utf-8') as f:
            old = json.load(f)
        print(f'{compare}: {japan.total(old["runs"]):,} residents on {old["cellDegrees"] * 3600:.1f}" cells')


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
