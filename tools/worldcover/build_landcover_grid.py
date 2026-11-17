#!/usr/bin/env python3
"""What covers Taiwan's ground outside its towns, from ESA WorldCover 10 m
2021 v200, on the water file's grid, as the app's
`Resources/RealWorld/taiwan_landcover.dat` (ARCHITECTURE decision 811).

    pip install tifffile numpy
    for t in N21E117 N21E120 N24E117 N24E120 N24E123; do
      curl -LO https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_${t}_Map.tif
    done
    python3 tools/worldcover/build_landcover_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        worldcover/ \\
        RailwayGameApp/Resources/RealWorld/taiwan_landcover.dat

WorldCover is © ESA WorldCover project 2021 / Contains modified
Copernicus Sentinel data (2021) processed by ESA WorldCover consortium,
under CC BY 4.0 (doi:10.5281/zenodo.7254221). Its map is 3° tiles of 1/12000°
(0.3″, some 10 m) samples, each one of eleven classes; the folder holds the
five tiles over Taiwan, Penghu, Kinmen and Matsu, named as the project names
them.

The water file (`tools/real-world-population/build_water_grid.py`) gives
the grid: 1.875″ cells, some 58 × 53 m, each holding some 39 of
WorldCover's samples (those whose middle lies in it). A cell's value is the
class most of its samples are, folded into the game's eight:

    0  unknown (no WorldCover tile reaches it, or water in the water file)
    1  forest     (10 tree cover)
    2  shrubland  (20)
    3  grassland  (30; 100 moss and lichen)
    4  cropland   (40)
    5  built-up   (50)
    6  bare       (60 bare and sparse; 70 snow and ice)
    7  water      (80 permanent water bodies) on land the water file has dry
    8  wetland    (90 herbaceous wetland; 95 mangroves)

then the most common of the 3 × 3 cells round it (itself included, ties to
the lower value), which takes off the lone cells of a field in a forest or
a tree in a field (a 58 m cell is less than the game's 64 m square of
ground) and keeps the file at some 1.8 MB, not 3.0. How many of a cell's
samples are trees is not kept: 96 % of the forest's cells are at least half
trees.

The water file's water is 0 here, so the game's own sea, rivers and lakes
(OpenStreetMap's) stay as they are; WorldCover's water on dry ground (a
fish pond, a reservoir OSM does not hold) is 7. Like the coverage file
(decision 147) it is the heights file's form (`build_slope_grid.py`) under
its own magic, `TWLC`: row by row as varint differences with runs of equal
values, each row read alone (GamePresentation's `LandCoverGrid`).
"""
import glob
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))

from build_slope_grid import encode_heights, water_mask  # noqa: E402

# WorldCover's sample size: 1/12000°.
SAMPLES_PER_DEGREE = 12000
TILE_DEGREES = 3

# The four tiles over Taiwan, Penghu, Kinmen and Matsu by their SHA-256, as
# the owner's web edition recorded them (railway-reference-private
# `Railway/rail-reference/regions/taiwan/source/rail-3d/landcover/
# worldcover-2021/manifest.json`, written by its `scripts/
# build_worldcover.py`): the same source, so the two maps agree. Another
# file (a later WorldCover release) stops the tool rather than change the
# map unnoticed.
SHA256 = {
    'N21E117': '072533cfdf31cfddf3f4d033fe4b48df36448a5b36dd20f80abd80e2841244fb',
    'N21E120': 'b23a186262569b69c05b7638e6fa0645a7376ebbb2644a8eac8c58fa8a767bd2',
    'N24E117': '99cbc3abd8b76a1bcb81e1e614323506807076dad6799b0727644cbf6a4024c1',
    'N24E120': '730c11c72158595d6fcc9b0fe4a61ff2fb786e17f08a3412542ce7e4de17a3c9',
}

# WorldCover's classes → the game's (the module's docstring).
FOLD = {10: 1, 20: 2, 30: 3, 100: 3, 40: 4, 50: 5, 60: 6, 70: 6, 80: 7, 90: 8, 95: 8}
COVERS = 9


def tiles(folder):
    """Each tile's south-west corner (whole degrees) and path."""
    for path in sorted(glob.glob(os.path.join(folder, 'ESA_WorldCover_10m_2021_v200_*_Map.tif'))):
        name = os.path.basename(path).split('_')[5]
        south = int(name[1:3]) * (1 if name[0] == 'N' else -1)
        west = int(name[4:7]) * (1 if name[3] == 'E' else -1)
        yield south, west, path


def landcover(data, folder):
    """The grid's covers (the module's docstring), before the majority, and
    how many tiles were read."""
    import tifffile  # Only for WorldCover's tiles.
    rows, columns = data['rows'], data['columns']
    north, west, step = data['north'], data['west'], data['cellDegrees']
    counts = np.zeros((COVERS, rows, columns), dtype=np.uint16)
    lookup = np.zeros(256, dtype=np.int64)
    for code, cover in FOLD.items():
        lookup[code] = cover
    read = 0
    for tile_south, tile_west, path in tiles(folder):
        tile_north = tile_south + TILE_DEGREES
        if tile_south >= north or tile_north <= north - rows * step or tile_west >= west + columns * step or tile_west + TILE_DEGREES <= west:
            continue
        classes = tifffile.imread(path)
        read += 1
        size = classes.shape[0]
        # Each sample's middle → the grid's row (from the tile's north
        # edge) and column.
        lat = tile_north - (np.arange(size) + 0.5) / SAMPLES_PER_DEGREE
        lon = tile_west + (np.arange(size) + 0.5) / SAMPLES_PER_DEGREE
        grid_row = np.floor((north - lat) / step).astype(np.int64)
        grid_column = np.floor((lon - west) / step).astype(np.int64)
        ys = np.flatnonzero((grid_row >= 0) & (grid_row < rows))
        xs = np.flatnonzero((grid_column >= 0) & (grid_column < columns))
        if not len(ys) or not len(xs):
            continue
        x0, x1 = xs[0], xs[-1] + 1
        cols = grid_column[x0:x1]
        for r in np.unique(grid_row[ys]):
            band = classes[np.flatnonzero(grid_row == r), x0:x1]
            folded = lookup[band]
            where = np.broadcast_to(cols, band.shape)
            for cover in range(1, COVERS):
                hit = folded == cover
                if hit.any():
                    np.add.at(counts[cover, r], where[hit], 1)
    cover = np.argmax(counts, axis=0)
    cover[counts.sum(axis=0) == 0] = 0
    cover[water_mask(data)] = 0
    return cover, read


def majority(cover):
    """The most common value of the 3 × 3 cells round each (ties to the
    lower), 0 where the cell itself is 0."""
    rows, columns = cover.shape
    padded = np.pad(cover, 1)
    votes = np.zeros((COVERS,) + cover.shape, dtype=np.uint8)
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            near = padded[1 + dr:1 + dr + rows, 1 + dc:1 + dc + columns]
            for k in range(COVERS):
                votes[k] += near == k
    out = np.argmax(votes, axis=0)
    out[cover == 0] = 0
    return out


def check_sources(folder):
    """Each tile the grid needs is there and is the file the web edition
    read (``SHA256``)."""
    for name, expected in SHA256.items():
        path = os.path.join(folder, f'ESA_WorldCover_10m_2021_v200_{name}_Map.tif')
        if not os.path.exists(path):
            sys.exit(f'{path}: missing (the module\'s docstring has the download)')
        digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()
        if digest != expected:
            sys.exit(f'{path}: SHA-256 {digest}, not the {expected} the web edition read')


def main(water_path, folder, out):
    check_sources(folder)
    data = json.load(open(water_path))
    raw, read = landcover(data, folder)
    cover = majority(raw)
    encoded = encode_heights(cover.astype(np.int16), data, magic=b'TWLC')
    open(out, 'wb').write(encoded)
    names = ['unknown', 'forest', 'shrubland', 'grassland', 'cropland', 'built-up', 'bare', 'water', 'wetland']
    total = int((cover > 0).sum())
    shares = ', '.join(f'{names[k]} {100 * int((cover == k).sum()) / max(total, 1):.1f} %' for k in range(1, COVERS))
    print(f'{out}: {read} tiles; {total} cells of land with a cover ({shares}); {len(encoded)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
