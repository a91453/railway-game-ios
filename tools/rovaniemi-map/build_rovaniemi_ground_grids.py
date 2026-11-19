#!/usr/bin/env python3
"""The Rovaniemi map's ground for its map pack (decision 789): the heights
(`heights.dat`), the water and steep slopes the rules read (`water.json`)
and the hill shading of the 2D map (`terrain.pmtiles`), in the formats of
Taiwan's and Hong Kong's (`tools/hk-map/build_hk_ground_grids.py`,
decision 726).

    pip install osmium tifffile imagecodecs numpy
    for e in 025 026 027; do curl -L -o /tmp/rv/dem/N66_E$e.tif \\
      https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N66_00_E${e}_00_DEM/Copernicus_DSM_COG_10_N66_00_E${e}_00_DEM.tif; done
    python3 -I tools/rovaniemi-map/build_rovaniemi_ground_grids.py /tmp/rv/dem rovaniemi.pbf \\
        RailwayGameApp/Resources/MapPacks/rovaniemi

The grid is Taiwan's: 1.875″ cells (16 × 16 to each of WorldPop's 30″
cells, the pack's `population.json`), from that grid's corner, over the
pack's extent.

Water (`build_water_grid.py`'s rule): a cell is water when its middle is
inside a body of water of OpenStreetMap's (the Kemijoki and Ounasjoki, the
lakes). Lapland has no coast: all the rest is land.

Heights: the Copernicus DEM GLO-30 (the three 1° tiles N66 E025 to E027;
WGS 84, 1″ of latitude by 2″ of longitude this far north, the samples'
middles on whole seconds, metres above EGM2008). It is a surface model,
the tops of the trees and buildings where they stand. Each cell takes the
model bilinearly at its middle, water too: the model flattens rivers and
lakes to their surface, which is what Taiwan's rule (`build_slope_grid.py`,
decision 132) keeps for water near the shore; with no sea there is no 0.

Steep slopes: `build_slope_grid.py`'s rule (decision 115) on these heights.

The check: Ounasvaara's top, east of the town, must be within
CHECK_METRES of 204 m, and the Kemijoki at Rovaniemi between 70 and 100 m.
"""
import glob
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

# The tiles as downloaded (2026-11-15).
TILES = {
    'N66_E025.tif': '2d208c587d80da14e2380eef852667857c8ad653bb3660a470324d7e642f60a0',
    'N66_E026.tif': 'af03e41ac7bb2d4205f5ac7258fde1e550fd36f61897a7b94f51fe86b9ae31ef',
    'N66_E027.tif': 'a77afebdb7e68f7e37e6a71b98425291201a3a979b1320bc9f9db0cb15401ae1',
}
TILE_URL = ('https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N66_00_E{e}_00_DEM/'
            'Copernicus_DSM_COG_10_N66_00_E{e}_00_DEM.tif')
# The mosaic: its north-west sample's middle, and the spacing.
DEM_NORTH, DEM_WEST, DEM_LAT_STEP, DEM_LON_STEP = 67.0, 25.0, 1 / 3600, 2 / 3600
# Known: Ounasvaara, 204 m (its top at 66.4989 N, 25.8028 E); the river
# at Rovaniemi, upstream of the Jätkänkynttilä bridge.
OUNASVAARA = (66.4989, 25.8028, 204)
KEMIJOKI = (66.4990, 25.7390)
CHECK_METRES = 30


def mosaic(folder):
    import tifffile  # Only for the model.
    parts = []
    for name, digest in sorted(TILES.items()):
        path = os.path.join(folder, name)
        got = hashlib.sha256(open(path, 'rb').read()).hexdigest()
        if got != digest:
            sys.exit(f'{path}: sha256 {got}, expected {digest} (a newer model: check it, then change TILES)')
        page = tifffile.TiffFile(path).pages[0]
        tie, scale = page.tags[33922].value, page.tags[33550].value
        if abs(scale[0] - DEM_LON_STEP) > 1e-12 or abs(scale[1] - DEM_LAT_STEP) > 1e-12 or tie[4] != DEM_NORTH:
            sys.exit(f'{name}: not 2″ × 1″ samples from 67°N')
        parts.append(page.asarray().astype(np.float64))
    return np.concatenate(parts, axis=1)


def sample(dem, latitude, longitude):
    """The model bilinearly at each point (numpy arrays of degrees)."""
    r = (DEM_NORTH - latitude) / DEM_LAT_STEP
    c = (longitude - DEM_WEST) / DEM_LON_STEP
    r0 = np.clip(np.floor(r).astype(np.int64), 0, dem.shape[0] - 2)
    c0 = np.clip(np.floor(c).astype(np.int64), 0, dem.shape[1] - 2)
    fr, fc = np.clip(r - r0, 0, 1), np.clip(c - c0, 0, 1)
    top = dem[r0, c0] * (1 - fc) + dem[r0, c0 + 1] * fc
    bottom = dem[r0 + 1, c0] * (1 - fc) + dem[r0 + 1, c0 + 1] * fc
    return top * (1 - fr) + bottom * fr


def main(dem_folder, extract, folder):
    dem = mosaic(dem_folder)
    population = json.load(open(os.path.join(folder, 'population.json'), encoding='utf-8'))
    north, west, step, rows, columns = build_hk_ground_grids.grid_box(population, build_rovaniemi_rail.EXTENT)
    latitudes = north - (np.arange(rows) + 0.5) * step
    longitudes = west + (np.arange(columns) + 0.5) * step

    # Water: the bodies of water; no coast.
    areas, bodies, stamp = build_water_grid.water_areas(extract)
    water = build_water_grid.fill(areas, north, west, step, rows, columns)

    # Heights.
    lat, lon = np.meshgrid(latitudes, longitudes, indexing='ij')
    level = sample(dem, lat, lon)
    del lat, lon
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
        'Copernicus DEM GLO-30, © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 '
        'provided under COPERNICUS by the European Union and ESA',
        'Rovaniemi terrain', 'Copernicus DEM GLO-30 © DLR e.V., © Airbus Defence and Space GmbH')
    build_rovaniemi_rail.write_manifest(folder)

    record = os.path.join(HERE, 'rovaniemi_sources.json')
    with open(record, encoding='utf-8') as f:
        sources = json.load(f)
    for name, digest in sorted(TILES.items()):
        sources['inputs'][name] = {'sha256': digest, 'from': TILE_URL.format(e=name[5:8]), 'downloaded': '2026-11-15',
                                   'licence': 'Copernicus DEM licence (GLO-30 public): free of charge, with the credit'}
    sources['inputs'][os.path.basename(extract) + ' (water.json)'] = {'osmData': stamp, 'bodies': bodies}
    build_rovaniemi_rail.write(HERE, 'rovaniemi_sources.json', sources)

    cell_km2 = (step * 110.574) * (step * 111.320 * np.cos(np.radians(latitudes)))

    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)

    print(f'{rows} × {columns} cells of {step * 3600:.3f}″ from {north:.6f}°N {west:.6f}°E; {bodies} bodies of water, '
          f'OSM data to {stamp}; land {km2(dry)} km², water {km2(water)} km², steep {km2(steep)} km²; '
          f'heights {int(heights.min())} to {int(heights.max())} m; heights.dat {size} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
