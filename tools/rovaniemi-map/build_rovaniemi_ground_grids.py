#!/usr/bin/env python3
"""The Rovaniemi map's ground for its map pack (decision 789): the heights
(`heights.dat`), the water and steep slopes the rules read (`water.json`)
and the hill shading of the 2D map (`terrain.pmtiles`), in the formats of
Taiwan's and Hong Kong's (`tools/hk-map/build_hk_ground_grids.py`,
decision 726).

    pip install osmium tifffile imagecodecs numpy
    python3 -I tools/rovaniemi-map/fetch_nls_dem.py /tmp/rv/nls
    python3 -I tools/rovaniemi-map/build_rovaniemi_ground_grids.py /tmp/rv/nls rovaniemi.pbf \\
        RailwayGameApp/Resources/MapPacks/rovaniemi

The second argument may be the pack's own `water.json` instead of the
extract: the water then stays as it is, cell for cell, and the heights and
steep slopes alone are made again (how the model was changed in decision
971, without moving a lake's shore under a game already played).

The grid is Taiwan's: 1.875″ cells (16 × 16 to each of WorldPop's 30″
cells, the pack's `population.json`), from that grid's corner, over the
pack's extent.

Water (`build_water_grid.py`'s rule): a cell is water when its middle is
inside a body of water of OpenStreetMap's (the Kemijoki and Ounasjoki, the
lakes). Lapland has no coast: all the rest is land.

Heights (decision 971): the National Land Survey of Finland's 10 m
elevation model (`fetch_nls_dem.py`; ETRS-TM35FIN, N2000), the bare ground
from the laser survey. Until then the pack had the Copernicus DEM GLO-30,
a surface model: the tops of the spruce and pine that cover Lapland, so
every clearing, road and railway cutting through the forest was a trench
10 to 20 m deep with steep sides. Each cell takes the mean of the samples
whose middles lie within it (some 58 m by 23 m here, a dozen samples), as
Hong Kong's and Fukuoka's do, water too: the model flattens rivers and
lakes to their surface, which is what Taiwan's rule (`build_slope_grid.py`,
decision 132) keeps for water near the shore; with no sea there is no 0.

Steep slopes: `build_slope_grid.py`'s rule (decision 115) on these heights.

The check: Ounasvaara's top, east of the town, must be within
CHECK_METRES of 204 m, and the Kemijoki at Rovaniemi between 70 and 100 m;
every cell has a height.
"""
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'hk-map'))
sys.path.insert(0, os.path.join(HERE, '..', 'overseas-map'))
import build_hk_ground_grids  # noqa: E402
import overseas_ground  # noqa: E402
import build_rovaniemi_rail  # noqa: E402
import build_water_grid  # noqa: E402

import fetch_nls_dem  # noqa: E402

DEM_STEP = 10.0
NLS = 'National Land Survey of Finland, Elevation model 10 m, 08/2023'
NLS_LICENCE = "the National Land Survey of Finland's open data licence, CC BY 4.0"
# Known: Ounasvaara, 204 m (its top at 66.4989 N, 25.8028 E); the river
# at Rovaniemi, upstream of the Jätkänkynttilä bridge.
OUNASVAARA = (66.4989, 25.8028, 204)
KEMIJOKI = (66.4990, 25.7390)
CHECK_METRES = 15


def mosaic(folder):
    """The sheets over the map as one array (NaN where a sheet has no
    height), the easting of its west edge and the northing of its north
    edge, and each sheet's digest."""
    import tifffile  # Only for the model.
    wanted = fetch_nls_dem.sheets()
    west = min(w for w, _ in wanted.values())
    north = max(n for _, n in wanted.values())
    east = max(w for w, _ in wanted.values()) + fetch_nls_dem.SHEET_EAST
    south = min(n for _, n in wanted.values()) - fetch_nls_dem.SHEET_NORTH
    dem = np.full((int((north - south) / DEM_STEP), int((east - west) / DEM_STEP)), np.nan, dtype=np.float32)
    digests = {}
    for name, (sheet_west, sheet_north) in sorted(wanted.items()):
        path = os.path.join(folder, name + '.tif')
        digests[name + '.tif'] = hashlib.sha256(open(path, 'rb').read()).hexdigest()
        page = tifffile.TiffFile(path).pages[0]
        tie, scale = page.tags['ModelTiepointTag'].value, page.tags['ModelPixelScaleTag'].value
        if (tie[3], tie[4]) != (sheet_west, sheet_north) or scale[0] != DEM_STEP or scale[1] != DEM_STEP:
            sys.exit(f'{name}: not the 10 m sheet from {sheet_west} E, {sheet_north} N')
        part = page.asarray().astype(np.float32)
        part[part < -1000] = np.nan
        row, column = int((north - sheet_north) / DEM_STEP), int((sheet_west - west) / DEM_STEP)
        dem[row:row + part.shape[0], column:column + part.shape[1]] = part
    return dem, west, north, digests


def mean_heights(dem, dem_west, dem_north, north, west, step, rows, columns):
    """Each cell's mean of the model's samples whose middles lie within it
    (NaN where the model has none), `build_hk_ground_grids.mean_heights`'s
    way: summed-area tables, a row and a column of zeros first."""
    latitudes = north - (np.arange(rows) + 0.5) * step
    longitudes = west + (np.arange(columns) + 0.5) * step
    valid = np.isfinite(dem)
    sums = np.zeros((dem.shape[0] + 1, dem.shape[1] + 1), np.float64)
    sums[1:, 1:] = np.where(valid, dem, 0).astype(np.float64).cumsum(0).cumsum(1)
    counts = np.zeros((dem.shape[0] + 1, dem.shape[1] + 1), np.int64)
    counts[1:, 1:] = valid.astype(np.int64).cumsum(0).cumsum(1)
    del valid
    out = np.empty((rows, columns), np.float64)
    half_north = step * 110_574.0 / 2
    for start in range(0, rows, 256):
        lat, lon = np.meshgrid(latitudes[start:start + 256], longitudes, indexing='ij')
        east, northing = fetch_nls_dem.tm35(lat, lon)
        half_east = step * 111_320.0 * np.cos(np.radians(lat)) / 2
        # The sample in column c has its middle at dem_west + (c + 0.5) × 10 m.
        c0 = np.clip(np.ceil((east - half_east - dem_west) / DEM_STEP - 0.5), 0, dem.shape[1]).astype(np.int64)
        c1 = np.clip(np.floor((east + half_east - dem_west) / DEM_STEP - 0.5) + 1, 0, dem.shape[1]).astype(np.int64)
        r0 = np.clip(np.ceil((dem_north - (northing + half_north)) / DEM_STEP - 0.5), 0, dem.shape[0]).astype(np.int64)
        r1 = np.clip(np.floor((dem_north - (northing - half_north)) / DEM_STEP - 0.5) + 1, 0, dem.shape[0]).astype(np.int64)
        c1, r1 = np.maximum(c1, c0), np.maximum(r1, r0)
        total = sums[r1, c1] - sums[r0, c1] - sums[r1, c0] + sums[r0, c0]
        count = counts[r1, c1] - counts[r0, c1] - counts[r1, c0] + counts[r0, c0]
        out[start:start + 256] = np.where(count > 0, total / np.maximum(count, 1), np.nan)
    return out


def main(dem_folder, extract, folder):
    dem, dem_west, dem_north, digests = mosaic(dem_folder)
    population = json.load(open(os.path.join(folder, 'population.json'), encoding='utf-8'))
    north, west, step, rows, columns = build_hk_ground_grids.grid_box(population, build_rovaniemi_rail.EXTENT)
    latitudes = north - (np.arange(rows) + 0.5) * step

    # Water: the bodies of water; no coast. Or the pack's own, as it is.
    if extract.endswith('.json'):
        import compare_dems
        kept = json.load(open(extract, encoding='utf-8'))
        if (kept['north'], kept['west'], kept['cellDegrees'], kept['rows'], kept['columns']) != (north, west, step, rows, columns):
            sys.exit(f'{extract}: not on this grid')
        water = compare_dems.runs(rows, columns, kept['water'])
        stamp, bodies = kept['osmData'][0], None
        extract = kept['source'].rsplit(' ', 1)[-1]
    else:
        areas, bodies, stamp = build_water_grid.water_areas(extract)
        water = build_water_grid.fill(areas, north, west, step, rows, columns)

    # Heights.
    level = mean_heights(dem, dem_west, dem_north, north, west, step, rows, columns)
    del dem
    if np.isnan(level).any():
        sys.exit(f'{int(np.isnan(level).sum())} cells have no height')
    dry = ~water
    heights = np.clip(np.rint(level), -32768, 32767).astype(np.int16)

    # Steep slopes, as Taiwan's (decision 115).
    steep = overseas_ground.steep(level, dry, latitudes, step)

    # The checks.
    def cell(point):
        return int((north - point[0]) / step), int((point[1] - west) / step)
    o_row, o_column = cell(OUNASVAARA)
    top = int(heights[max(0, o_row - 8):o_row + 9, max(0, o_column - 8):o_column + 9].max())
    if abs(top - OUNASVAARA[2]) > CHECK_METRES:
        sys.exit(f'Ounasvaara: {top} m round its top, not {OUNASVAARA[2]} m')
    k_row, k_column = cell(KEMIJOKI)
    river = int(heights[k_row, k_column])
    if not water[k_row, k_column] or not 70 <= river <= 100:
        sys.exit(f'the Kemijoki at Rovaniemi: water {bool(water[k_row, k_column])}, {river} m')
    print(f'Ounasvaara {top} m; the Kemijoki at Rovaniemi {river} m', flush=True)

    size = overseas_ground.write_ground(
        folder, extract, stamp, (north, west, step, rows, columns), heights, water, steep,
        NLS + ', CC BY 4.0', 'Rovaniemi terrain', '© ' + NLS)
    build_rovaniemi_rail.write_manifest(folder)

    record = os.path.join(HERE, 'rovaniemi_sources.json')
    with open(record, encoding='utf-8') as f:
        sources = json.load(f)
    for name in [n for n in sources['inputs'] if n.startswith('N66_E')]:
        del sources['inputs'][name]
    sources['inputs']['NLS elevation model 10 m'] = {
        'sheets': digests, 'from': fetch_nls_dem.URL.replace('{a}/{b}/{name}.tif', ''), 'downloaded': '2026-11-25',
        'licence': NLS_LICENCE + '; credit: ' + NLS}
    if bodies is not None:
        sources['inputs'][os.path.basename(extract) + ' (water.json)'] = {'osmData': stamp, 'bodies': bodies}
    build_rovaniemi_rail.write(HERE, 'rovaniemi_sources.json', sources)

    cell_km2 = (step * 110.574) * (step * 111.320 * np.cos(np.radians(latitudes)))

    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)

    print(f'{rows} × {columns} cells of {step * 3600:.3f}″ from {north:.6f}°N {west:.6f}°E; '
          f'OSM data to {stamp}; land {km2(dry)} km², water {km2(water)} km², steep {km2(steep)} km²; '
          f'heights {int(heights.min())} to {int(heights.max())} m; heights.dat {size} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
