#!/usr/bin/env python3
"""Hong Kong's ground for its map pack (decision 726): the heights
(`heights.dat`), the water and steep slopes the rules read (`water.json`)
and the hill shading of the 2D map (`terrain.pmtiles`), in the formats of
Taiwan's `taiwan_heights.dat`, `taiwan_water.json` and
`taiwan_terrain.pmtiles`.

    pip install osmium tifffile imagecodecs numpy
    curl -L -o hk_dtm.zip https://static.csdi.gov.hk/csdi-webpage/download/common/e9a836d098a3a9ccf55a7f61f69a93e71923c722fb94ddf7b36be83a67b99140
    unzip hk_dtm.zip          # "Digital Terrain Model.tif" (498 MB) and its .tfw
    curl -L -o hong_kong.pbf https://osmtoday.com/asia/china/hong_kong.pbf
    python3 -I tools/hk-map/build_hk_ground_grids.py "Digital Terrain Model.tif" hong_kong.pbf \\
        RailwayGameApp/Resources/MapPacks/hongkong

The grid is Taiwan's: 1.875″ cells (16 × 16 to each of WorldPop's 30″
cells, the pack's `population.json`), from that grid's corner, over the
pack's extent.

Water (`build_water_grid.py`'s rule): a cell is water when its middle is
outside the land of OpenStreetMap's coastline or inside a body of water.
The coastline is closed as the base map closes it
(`build_hk_basemap.coastline`): the mainland's open shore is joined round
the north, so Shenzhen is land, not sea.

Heights: the Lands Department's Digital Terrain Model (5 m, HK1980 Grid,
EPSG:2326; whole metres, the sea 0). Each cell takes the mean of the
model's samples within it: its middle is taken from WGS 84 to HK80 by the
Lands Department's own shift (latitude + 5.5″, longitude − 8.8″, good to a
metre or two), then to the grid by the Transverse Mercator of the
International 1924 ellipsoid with the grid's origin, both written here with
the standard library and numpy. The water then goes as Taiwan's
(`build_slope_grid.py`, decision 132): water within SHORE cells of dry land
keeps its surface, no lower than 0; the rest of the sea is 0. Land the
model does not cover (Shenzhen, the far islands) is 0. The model is the
ground where it is bare but the top of the trees where trees cover it (the
Lands Department says so), and dates from the 2015 aerial survey.

Steep slopes: `build_slope_grid.py`'s rule (decision 115) on these
heights.

The check: Tai Mo Shan's top must be within CHECK_METRES of 957 m, and
how much of the model's land (above 1 m) OpenStreetMap calls land is
printed (98 % on 2026-11-13; 89 % with the shift's signs the other
way round, 93 % without it): below 97 % the tool stops.
"""
import hashlib
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
import build_hk_basemap  # noqa: E402
import build_hk_mtr  # noqa: E402
import build_slope_grid  # noqa: E402
import build_terrain  # noqa: E402
import build_water_grid  # noqa: E402

CUTS = 16
SHORE = build_slope_grid.SHORE
# The zip as downloaded (2026-11-13), and the GeoTIFF in it.
ZIP_SHA256 = '6dbcdfb50bbc4bc520828eec574e5235c887b02cfeaff3dd24d85e87621bd1af'
DTM_SHA256 = '35cd4e90cce9d75da51c0af679da172fe936ebef8f30070d8e7733964e3c6794'
DTM_URL = ('https://static.csdi.gov.hk/csdi-webpage/download/common/'
           'e9a836d098a3a9ccf55a7f61f69a93e71923c722fb94ddf7b36be83a67b99140')
DTM_PAGE = 'https://portal.csdi.gov.hk/geoportal/?datasetId=landsd_rcd_1638158088368_93806'
# The model's samples: the middle of its north-west one, and the spacing.
DTM_EAST, DTM_NORTH, DTM_STEP = 800_000.0, 848_000.0, 5.0

# HK1980 Grid (EPSG:2326): Transverse Mercator on International 1924.
A = 6_378_388.0
F = 1 / 297.0
LAT0 = math.radians(22 + 18 / 60 + 43.68 / 3600)
LON0 = math.radians(114 + 10 / 60 + 42.80 / 3600)
FALSE_EAST, FALSE_NORTH = 836_694.05, 819_069.80
# WGS 84 to HK80, in arc-seconds (Lands Department, Explanatory Notes on
# Geodetic Datums in Hong Kong).
SHIFT_LAT, SHIFT_LON = 5.5, -8.8

# Known tops: Tai Mo Shan, 957 m, its highest sample at E 830,877.5, N
# 830,122.5 of the model.
TAI_MO_SHAN = (22.41056, 114.12444, 957)
CHECK_METRES = 40


def meridian(phi):
    e2 = F * (2 - F)
    e4, e6 = e2 * e2, e2 * e2 * e2
    return A * ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi
                - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * np.sin(2 * phi)
                + (15 * e4 / 256 + 45 * e6 / 1024) * np.sin(4 * phi)
                - (35 * e6 / 3072) * np.sin(6 * phi))


def hk80_grid(latitude, longitude):
    """WGS 84 degrees (numpy arrays) to HK1980 Grid easting and northing."""
    phi = np.radians(latitude + SHIFT_LAT / 3600)
    lam = np.radians(longitude + SHIFT_LON / 3600)
    e2 = F * (2 - F)
    ep2 = e2 / (1 - e2)
    n = A / np.sqrt(1 - e2 * np.sin(phi) ** 2)
    t = np.tan(phi) ** 2
    c = ep2 * np.cos(phi) ** 2
    a = (lam - LON0) * np.cos(phi)
    x = n * (a + (1 - t + c) * a ** 3 / 6 + (5 - 18 * t + t * t + 72 * c - 58 * ep2) * a ** 5 / 120)
    y = meridian(phi) - meridian(LAT0) + n * np.tan(phi) * (
        a * a / 2 + (5 - t + 9 * c + 4 * c * c) * a ** 4 / 24 + (61 - 58 * t + t * t + 600 * c - 330 * ep2) * a ** 6 / 720)
    return FALSE_EAST + x, FALSE_NORTH + y


def grid_box(population, extent):
    """The grid's corner, cell size, rows and columns: whole population
    cells from its corner, over the extent."""
    size = population['cellDegrees']
    top = math.floor((population['north'] - extent['north']) / size + 1e-9)
    left = math.floor((extent['west'] - population['west']) / size + 1e-9)
    bottom = math.ceil((population['north'] - extent['south']) / size - 1e-9)
    right = math.ceil((extent['east'] - population['west']) / size - 1e-9)
    north = population['north'] - top * size
    west = population['west'] + left * size
    return north, west, size / CUTS, (bottom - top) * CUTS, (right - left) * CUTS


def mean_heights(dtm, north, west, step, rows, columns):
    """Each cell's mean of the model's samples within it (NaN where the
    model has none)."""
    latitudes = north - (np.arange(rows) + 0.5) * step
    longitudes = west + (np.arange(columns) + 0.5) * step
    lat, lon = np.meshgrid(latitudes, longitudes, indexing='ij')
    east, northing = hk80_grid(lat, lon)
    half_east = step * 111_320.0 * np.cos(np.radians(lat)) / 2
    half_north = step * 110_574.0 / 2
    valid = dtm != -9999
    values = np.where(valid, dtm, 0).astype(np.int64)
    # Summed-area tables, a row and a column of zeros first.
    sums = np.zeros((dtm.shape[0] + 1, dtm.shape[1] + 1), np.int64)
    sums[1:, 1:] = values.cumsum(0).cumsum(1)
    del values
    counts = np.zeros_like(sums)
    counts[1:, 1:] = valid.astype(np.int64).cumsum(0).cumsum(1)
    # The samples whose middles lie within the cell: columns c0 .. c1 - 1,
    # rows r0 .. r1 - 1.
    c0 = np.clip(np.ceil((east - half_east - DTM_EAST) / DTM_STEP), 0, dtm.shape[1]).astype(np.int64)
    c1 = np.clip(np.floor((east + half_east - DTM_EAST) / DTM_STEP) + 1, 0, dtm.shape[1]).astype(np.int64)
    r0 = np.clip(np.ceil((DTM_NORTH - (northing + half_north)) / DTM_STEP), 0, dtm.shape[0]).astype(np.int64)
    r1 = np.clip(np.floor((DTM_NORTH - (northing - half_north)) / DTM_STEP) + 1, 0, dtm.shape[0]).astype(np.int64)
    c1, r1 = np.maximum(c1, c0), np.maximum(r1, r0)

    def box(table):
        return table[r1, c1] - table[r0, c1] - table[r1, c0] + table[r0, c0]

    total, count = box(sums), box(counts)
    return np.where(count > 0, total / np.maximum(count, 1), np.nan)


def main(dtm_path, extract, folder):
    import tifffile  # Only for the model.

    digest = hashlib.sha256(open(dtm_path, 'rb').read()).hexdigest()
    if digest != DTM_SHA256:
        sys.exit(f'{dtm_path}: sha256 {digest}, expected {DTM_SHA256} (a newer model: check it, then change DTM_SHA256)')
    dtm = tifffile.imread(dtm_path)
    assert dtm.shape == (9601, 12751), f'the model is {dtm.shape}, not 9,601 × 12,751 samples of 5 m'
    population = json.load(open(os.path.join(folder, 'population.json'), encoding='utf-8'))
    north, west, step, rows, columns = grid_box(population, build_hk_mtr.EXTENT)

    # Water.
    rings, _, coast_stamp = build_hk_basemap.coastline(extract)
    land = build_water_grid.fill([(0, ring) for ring in rings], north, west, step, rows, columns)
    areas, bodies, water_stamp = build_water_grid.water_areas(extract)
    inland = build_water_grid.fill(areas, north, west, step, rows, columns)
    water = ~land | inland
    stamp = max(s for s in (coast_stamp, water_stamp) if s)

    # Heights.
    mean = mean_heights(dtm, north, west, step, rows, columns)
    covered = ~np.isnan(mean)
    level = np.rint(np.nan_to_num(mean, nan=0.0))
    dry = ~water
    near = water & build_slope_grid.near(dry, SHORE)
    heights = np.where(dry, np.where(covered, level, 0), np.where(near & covered, np.maximum(level, 0), 0))
    heights = np.clip(heights, -32768, 32767).astype(np.int16)

    # Steep slopes, as Taiwan's (decision 115), with the water at 0.
    flat = np.where(water, 0, np.nan_to_num(mean, nan=0.0)).astype(np.float32)
    smooth = build_slope_grid.median3(flat)
    latitudes = north - (np.arange(rows) + 0.5) * step
    dy = 2 * step * build_slope_grid.METRES_PER_DEGREE_LATITUDE
    dx = (2 * step * build_slope_grid.METRES_PER_DEGREE_LONGITUDE * np.cos(np.radians(latitudes)))[:, None]
    north_south = np.zeros_like(smooth)
    east_west = np.zeros_like(smooth)
    north_south[1:-1, :] = np.abs(smooth[:-2, :] - smooth[2:, :]) / dy
    east_west[:, 1:-1] = np.abs(smooth[:, 2:] - smooth[:, :-2]) / dx
    raw_steep = (np.maximum(north_south, east_west) > build_slope_grid.SLOPE) & ~water & covered
    padded = np.pad(raw_steep, 1).astype(np.uint8)
    votes = sum(padded[1 + dr:1 + dr + rows, 1 + dc:1 + dc + columns] for dr in (-1, 0, 1) for dc in (-1, 0, 1))
    steep = (votes >= 5) & ~water & covered

    # The checks.
    t_lat, t_lon, t_height = TAI_MO_SHAN
    t_row, t_column = int((north - t_lat) / step), int((t_lon - west) / step)
    top = int(heights[max(0, t_row - 2):t_row + 3, max(0, t_column - 2):t_column + 3].max())
    if abs(top - t_height) > CHECK_METRES:
        sys.exit(f'Tai Mo Shan: {top} m round its top, not {t_height} m: the datum or the projection is wrong')
    model_land = covered & (mean > 1)
    agree = float((model_land & land).sum()) / max(1, int(model_land.sum()))
    print(f'Tai Mo Shan {top} m; of the model\'s land above 1 m, {100 * agree:.2f} % is land by OpenStreetMap', flush=True)
    if agree < 0.97:
        sys.exit('the model and the coastline disagree: the datum shift is wrong')

    data = {
        'source': f'OpenStreetMap contributors, from the extract {os.path.basename(extract)}',
        'licence': 'ODbL 1.0',
        'osmData': [stamp, stamp],
        'north': north,
        'west': west,
        'cellDegrees': step,
        'rows': rows,
        'columns': columns,
        'water': build_slope_grid.encode(water),
        'steep': build_slope_grid.encode(steep),
        'slopeSource': 'Digital Terrain Model, Lands Department, Government of the Hong Kong SAR, via the CSDI Portal',
    }
    build_hk_mtr.write(folder, 'water.json', data)
    encoded = build_slope_grid.encode_heights(heights, data)
    with open(os.path.join(folder, 'heights.dat'), 'wb') as f:
        f.write(encoded)
    build_terrain.main(os.path.join(folder, 'heights.dat'), os.path.join(folder, 'terrain.pmtiles'),
                       name='Hong Kong terrain',
                       attribution='Digital Terrain Model © Lands Department, Government of the HKSAR')
    build_hk_mtr.write_manifest(folder)

    record = os.path.join(HERE, 'hk_sources.json')
    with open(record, encoding='utf-8') as f:
        sources = json.load(f)
    sources['inputs']['Digital Terrain Model.tif'] = {
        'sha256': DTM_SHA256, 'zip': ZIP_SHA256, 'from': DTM_URL, 'page': DTM_PAGE, 'downloaded': '2026-11-13',
        'licence': 'CSDI Portal Terms and Conditions of Use; Lands Department, Government of the HKSAR',
    }
    sources['inputs']['hong_kong.pbf (water.json)'] = {
        'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
        'from': 'https://osmtoday.com/asia/china/hong_kong.pbf', 'osmData': stamp,
        'licence': 'ODbL 1.0, © OpenStreetMap contributors',
    }
    with open(record, 'w', encoding='utf-8') as f:
        json.dump(sources, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')

    cell_km2 = (step * 110.574) * (step * 111.320 * np.cos(np.radians(latitudes)))

    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)

    print(f'{rows} × {columns} cells of {step * 3600:.3f}″ from {north:.6f}°N {west:.6f}°E; {bodies} bodies of water, '
          f'OSM data to {stamp}; land {km2(dry)} km², of it covered by the model {km2(dry & covered)} km², '
          f'steep {km2(steep)} km²; heights {int(heights.min())} to {int(heights.max())} m; '
          f'heights.dat {len(encoded)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
