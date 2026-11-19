#!/usr/bin/env python3
"""The Fukuoka map's ground for its map pack (FUKUOKA-GROUND): the people
(`population.json`), the base map (`basemap.pmtiles`), and the heights,
water and steep slopes (`heights.dat`, `water.json`, `terrain.pmtiles`),
in the formats of Taiwan's, Hong Kong's and Rovaniemi's, with the tools
they share (`tools/overseas-map/overseas_ground.py`).

    python3 -I tools/fukuoka-map/build_fukuoka_ground.py population /tmp/fk/pop/jpn.tif RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/build_fukuoka_ground.py basemap /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka
    python3 -I tools/fukuoka-map/build_fukuoka_ground.py grids /tmp/fk/gsi /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka

People: WorldPop's 1 km grid of Japan (2025, constrained, R2025A v1,
CC BY 4.0), cut to the extent (`build_fukuoka_rail.EXTENT`).

Base map: Taiwan's tiles (`tools/basemap/build_basemap.py`) from the
Kyushu extract cut to the map. Kyushu's shore runs out of the extract on
every side, so the open coastline is cut to the extract's box and closed
along its edge (`overseas_ground.coast_in_box`); Nokonoshima and the other
islands are closed rings of their own.

Grids: Taiwan's 1.875″ cells from the population grid's corner, over the
extent. Water: a cell is water when its middle is outside the land of that
coastline or inside a body of water. Heights: the Geospatial Information
Authority of Japan's elevation tiles (`fetch_gsi_dem.py`): the 5 m models
(the laser survey's where it has the tile, else the photogrammetric ones),
and the 10 m model where a 5 m pixel has no value. They are the bare
ground, not the tops of buildings and trees: Fukuoka's centre is a city of
tall buildings, and a surface model (Copernicus, which Rovaniemi's
forests and low town can take) would put its railways on their roofs.
Each cell takes the mean of the pixels whose middles lie within it. The
water then goes as Hong Kong's (`build_slope_grid.py`, decision 132):
water within SHORE cells of dry land keeps its surface, no lower than 0;
the rest of the sea is 0. Steep slopes: decision 115's rule.

The checks: Atagoyama (愛宕山, 68 m on GSI's map) within CHECK_METRES of its
height; of the model's pixels above 1 m, at least 97 % land by
OpenStreetMap's coastline.
"""
import glob
import hashlib
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'overseas-map'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'hk-map'))
import build_fukuoka_rail  # noqa: E402
import overseas_ground  # noqa: E402

POPULATION_SHA256 = '0e6e4155c86d5e87f61a837ad3bd90f993dd19b7a34c475f7a05cb36d6338e3d'
POPULATION_URL = ('https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/JPN/v1/1km_ua/constrained/'
                  'jpn_pop_2025_CN_1km_R2025A_UA_v1.tif')
# The extract's box (west, south, east, north), as cut with osmium.
BOX = (130.25, 33.49, 130.52, 33.75)
SEA_MARGIN = 0.05
GSI_CREDIT = '国土地理院の標高タイルを加工して作成'
GSI_TERMS = '国土地理院コンテンツ利用規約 (https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html), compatible with CC BY 4.0'
ATAGOYAMA = (33.5856, 130.3347, 68)
CHECK_METRES = 25
RECORD = os.path.join(HERE, 'fukuoka_sources.json')


def record(name, entry):
    with open(RECORD, encoding='utf-8') as f:
        sources = json.load(f)
    sources['inputs'][name] = entry
    overseas_ground.write_json(HERE, 'fukuoka_sources.json', sources)


def population(source, folder):
    fields, digest, cut = overseas_ground.population(source, POPULATION_SHA256, build_fukuoka_rail.EXTENT)
    overseas_ground.write_json(folder, 'population.json', {
        'source': 'WorldPop, Japan 2025, constrained, 30 arc-second (about 1 km), R2025A v1, cut to the Fukuoka map',
        'from': POPULATION_URL,
        'licence': 'CC BY 4.0',
        **fields,
    })
    build_fukuoka_rail.write_manifest(folder)
    record('jpn_pop_2025_CN_1km_R2025A_UA_v1.tif', {'sha256': digest, 'from': POPULATION_URL,
                                                     'licence': 'CC BY 4.0, WorldPop'})
    print(f'population.json: {len(fields["runs"])} runs, {int(cut.sum())} people, {cut.shape[0]} x {cut.shape[1]} cells')


def basemap(extract, folder):
    import build_basemap
    build_basemap.SEA_MARGIN = SEA_MARGIN
    build_basemap.main(extract, os.path.join(folder, 'basemap.pmtiles'), name='Fukuoka base map',
                       center=(130.40, 33.60, 11), coastline=overseas_ground.coast_in_box(BOX))
    build_fukuoka_rail.write_manifest(folder)
    record(os.path.basename(extract) + ' (basemap, water.json)', {
        'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
        'from': 'https://osmtoday.com/asia/japan/kyushu.pbf, cut with osmium extract -b '
                + ','.join(f'{v:g}' for v in BOX) + ' -s smart',
        'licence': 'ODbL 1.0, © OpenStreetMap contributors'})


def gsi_heights(path):
    """A tile's 256 × 256 heights in metres, NaN where it has none."""
    import imagecodecs
    rgb = imagecodecs.png_decode(open(path, 'rb').read()).astype(np.int64)
    x = (rgb[..., 0] << 16) + (rgb[..., 1] << 8) + rgb[..., 2]
    metres = np.where(x < 1 << 23, x, x - (1 << 24)) * 0.01
    return np.where(x == 1 << 23, np.nan, metres)


def mosaic(tiles_folder):
    """The zoom-15 pixels over the tiles: the 5 m models', the 10 m
    model's (each of its zoom-14 pixels four of these) where those have
    none; with the first tile's x and y and a digest of all the tiles."""
    five = {}
    for path in sorted(glob.glob(os.path.join(tiles_folder, 'dem5*_png_15_*.png'))):
        _, _, _, x, y = os.path.basename(path)[:-4].rsplit('_', 4)
        five[(int(x), int(y))] = path
    ten = {}
    for path in sorted(glob.glob(os.path.join(tiles_folder, 'dem_png_14_*.png'))):
        _, _, _, x, y = os.path.basename(path)[:-4].rsplit('_', 4)
        ten[(int(x), int(y))] = path
    xs = [x for x, _ in five] + [2 * x for x, _ in ten] + [2 * x + 1 for x, _ in ten]
    ys = [y for _, y in five] + [2 * y for _, y in ten] + [2 * y + 1 for _, y in ten]
    x0, y0 = min(xs), min(ys)
    pixels = np.full(((max(ys) - y0 + 1) * 256, (max(xs) - x0 + 1) * 256), np.nan)
    for (x, y), path in ten.items():
        big = np.repeat(np.repeat(gsi_heights(path), 2, axis=0), 2, axis=1)
        r, c = (2 * y - y0) * 256, (2 * x - x0) * 256
        rows = slice(max(r, 0), r + 512)
        columns = slice(max(c, 0), c + 512)
        part = big[max(0, -r):, max(0, -c):]
        target = pixels[rows, columns]
        target[...] = part[:target.shape[0], :target.shape[1]]
    for (x, y), path in five.items():
        heights = gsi_heights(path)
        target = pixels[(y - y0) * 256:(y - y0 + 1) * 256, (x - x0) * 256:(x - x0 + 1) * 256]
        target[...] = np.where(np.isnan(heights), target, heights)
    digest = hashlib.sha256()
    for path in sorted(list(five.values()) + list(ten.values())):
        digest.update(os.path.basename(path).encode())
        digest.update(hashlib.sha256(open(path, 'rb').read()).digest())
    return pixels, x0, y0, digest.hexdigest(), len(five), len(ten)


def pixel_x(longitude, x0):
    return ((longitude + 180) / 360 * (1 << 15) - x0) * 256


def pixel_y(latitude, y0):
    return ((1 - np.arcsinh(np.tan(np.radians(latitude))) / math.pi) / 2 * (1 << 15) - y0) * 256


def mean_heights(pixels, x0, y0, north, west, step, rows, columns):
    """Each cell's mean of the pixels whose middles lie within it (NaN
    where none has a value), by summed-area tables as Hong Kong's."""
    valid = ~np.isnan(pixels)
    sums = np.zeros((pixels.shape[0] + 1, pixels.shape[1] + 1))
    sums[1:, 1:] = np.where(valid, pixels, 0).cumsum(0).cumsum(1)
    counts = np.zeros_like(sums)
    counts[1:, 1:] = valid.cumsum(0).cumsum(1)
    edges_lat = north - np.arange(rows + 1) * step
    edges_lon = west + np.arange(columns + 1) * step
    # Pixel middles at k + 0.5: those within [a, b) are ceil(a - 0.5) .. ceil(b - 0.5) - 1.
    cx = np.clip(np.ceil(pixel_x(edges_lon, x0) - 0.5), 0, pixels.shape[1]).astype(np.int64)
    ry = np.clip(np.ceil(pixel_y(edges_lat, y0) - 0.5), 0, pixels.shape[0]).astype(np.int64)
    r0, r1 = ry[:-1, None], ry[1:, None]
    c0, c1 = cx[None, :-1], cx[None, 1:]

    def box(table):
        return table[r1, c1] - table[r0, c1] - table[r1, c0] + table[r0, c0]

    total, count = box(sums), box(counts)
    return np.where(count > 0, total / np.maximum(count, 1), np.nan)


def grids(tiles_folder, extract, folder):
    import build_hk_ground_grids
    import build_slope_grid
    import build_water_grid

    pixels, x0, y0, digest, five, ten = mosaic(tiles_folder)
    population_data = json.load(open(os.path.join(folder, 'population.json'), encoding='utf-8'))
    north, west, step, rows, columns = build_hk_ground_grids.grid_box(population_data, build_fukuoka_rail.EXTENT)
    latitudes = north - (np.arange(rows) + 0.5) * step

    # Water.
    rings, _, coast_stamp = overseas_ground.coast_in_box(BOX)(extract)
    land = build_water_grid.fill([(0, ring) for ring in rings], north, west, step, rows, columns)
    areas, bodies, water_stamp = build_water_grid.water_areas(extract)
    inland = build_water_grid.fill(areas, north, west, step, rows, columns)
    water = ~land | inland
    stamp = max(s for s in (coast_stamp, water_stamp) if s)

    # Heights.
    mean = mean_heights(pixels, x0, y0, north, west, step, rows, columns)
    covered = ~np.isnan(mean)
    level = np.rint(np.nan_to_num(mean, nan=0.0))
    dry = ~water
    near = water & build_slope_grid.near(dry, build_slope_grid.SHORE)
    heights = np.where(dry, np.where(covered, level, 0), np.where(near & covered, np.maximum(level, 0), 0))
    heights = np.clip(heights, -32768, 32767).astype(np.int16)
    steep = overseas_ground.steep(np.where(water, 0, np.nan_to_num(mean, nan=0.0)), dry & covered, latitudes, step)

    # The checks.
    a_lat, a_lon, a_height = ATAGOYAMA
    a_row, a_column = int((north - a_lat) / step), int((a_lon - west) / step)
    top = int(heights[max(0, a_row - 3):a_row + 4, max(0, a_column - 3):a_column + 4].max())
    if abs(top - a_height) > CHECK_METRES:
        sys.exit(f'Atagoyama: {top} m round its top, not {a_height} m')
    model_land = covered & (mean > 1)
    agree = float((model_land & land).sum()) / max(1, int(model_land.sum()))
    print(f'Atagoyama {top} m; of the model\'s land above 1 m, {100 * agree:.2f} % is land by OpenStreetMap', flush=True)
    if agree < 0.97:
        sys.exit('the model and the coastline disagree')

    size = overseas_ground.write_ground(
        folder, extract, stamp, (north, west, step, rows, columns), heights, water, steep,
        'GSI elevation tiles (DEM5A/5B/5C, DEM10B), ' + GSI_CREDIT,
        'Fukuoka terrain', 'GSI elevation tiles, ' + GSI_CREDIT)
    build_fukuoka_rail.write_manifest(folder)
    record('GSI elevation tiles', {'sha256 of the tiles (names and digests, sorted)': digest,
                                   'tiles': {'5 m (zoom 15)': five, '10 m (zoom 14)': ten},
                                   'from': 'https://cyberjapandata.gsi.go.jp/xyz/{dem5a_png,dem5b_png,dem5c_png,dem_png}/',
                                   'downloaded': '2026-11-19', 'licence': GSI_TERMS + '; ' + GSI_CREDIT})

    cell_km2 = (step * 110.574) * (step * 111.320 * np.cos(np.radians(latitudes)))

    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)

    print(f'{rows} × {columns} cells of {step * 3600:.3f}″ from {north:.6f}°N {west:.6f}°E; {bodies} bodies of water, '
          f'OSM data to {stamp}; land {km2(dry)} km², of it with no height {km2(dry & ~covered)} km², water '
          f'{km2(water)} km², steep {km2(steep)} km²; heights {int(heights.min())} to {int(heights.max())} m; '
          f'heights.dat {size} bytes')


if __name__ == '__main__':
    steps = {'population': (population, 2), 'basemap': (basemap, 2), 'grids': (grids, 3)}
    if len(sys.argv) < 2 or sys.argv[1] not in steps or len(sys.argv) != 2 + steps[sys.argv[1]][1]:
        sys.exit(__doc__)
    steps[sys.argv[1]][0](*sys.argv[2:])
