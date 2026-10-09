#!/usr/bin/env python3
"""Mark Taiwan's steep slopes on the water file's grid, and add them to the
app's `Resources/RealWorld/taiwan_water.json` as its `steep` (ARCHITECTURE
decision 112).

    python3 tools/real-world-population/build_slope_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        copernicus-dem/ \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json

The water file (`build_water_grid.py`) gives the grid: 1.875″ cells, some
58 × 53 m; its other contents are kept as they are. The folder holds the
Copernicus DEM's 1° tiles over Taiwan (GLO-30, 1″; where a tile is only
released at 3″, GLO-90, as Matsu's N26 E119): Cloud Optimized GeoTIFFs named
as the DEM names them, `Copernicus_DSM_COG_10_N23_00_E120_00_DEM.tif`
(`_30_` for 3″), from the public buckets `copernicus-dem-30m` and
`copernicus-dem-90m`.

Each grid cell takes the height of the DEM's sample at its middle; a 3 × 3
median (some 170 m) takes off the buildings and trees a surface model holds
(a tower in Taipei is a step of 100 m or more in one cell, a mountainside is
not), and the slope is the steeper of the two central differences, east
and north, over two cells. A dry cell is steep when its slope is more than
SLOPE (30 %, the Building Technical Regulations' line above which a
hillside may not be built on), and then only where at least 5 of the 9
cells round it (itself included) are, so a lone cell on a terrace or by a
cutting is not, and a lone flat cell on a mountainside is. Water is never
steep.

The file gains `"steep": [[row, column, count, gap, count, …], …]`, as
`"water"`, and `"slopeSource"`. Reading the tiles needs tifffile and
imagecodecs (`pip install tifffile imagecodecs numpy`), as the population
grid's script; about a minute.
"""
import glob
import json
import math
import os
import sys

import numpy as np

SLOPE = 0.30
METRES_PER_DEGREE_LATITUDE = 110_574.0
METRES_PER_DEGREE_LONGITUDE = 111_320.0


def water_mask(data):
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
    return mask


def tiles(folder):
    """Each tile's south-west corner (whole degrees), samples a degree and
    heights, north row first; 1″ tiles before 3″ ones of the same place."""
    found = {}
    for path in sorted(glob.glob(os.path.join(folder, '*.tif'))):
        name = os.path.basename(path)
        parts = name.split('_')
        try:
            arcseconds = int(parts[3])
            south = int(parts[4][1:]) * (1 if parts[4][0] == 'N' else -1)
            west = int(parts[6][1:]) * (1 if parts[6][0] == 'E' else -1)
        except (IndexError, ValueError):
            continue
        if (south, west) in found and found[(south, west)][0] <= arcseconds:
            continue
        found[(south, west)] = (arcseconds, path)
    import tifffile  # Only for the DEM's tiles.
    for (south, west), (arcseconds, path) in sorted(found.items()):
        heights = tifffile.imread(path).astype(np.float32)
        yield south, west, heights


def heights_on_grid(data, folder):
    """The height at each grid cell's middle (NaN where no tile reaches),
    and how many tiles were read."""
    rows, columns = data['rows'], data['columns']
    north, west, step = data['north'], data['west'], data['cellDegrees']
    grid = np.full((rows, columns), np.nan, dtype=np.float32)
    latitudes = north - (np.arange(rows) + 0.5) * step
    longitudes = west + (np.arange(columns) + 0.5) * step
    count = 0
    for tile_south, tile_west, heights in tiles(folder):
        count += 1
        size_y, size_x = heights.shape
        in_rows = np.flatnonzero((latitudes >= tile_south) & (latitudes < tile_south + 1))
        in_columns = np.flatnonzero((longitudes >= tile_west) & (longitudes < tile_west + 1))
        if not len(in_rows) or not len(in_columns):
            continue
        # A tile's first row is its north edge; samples are pixel centres
        # spaced 1/size of a degree.
        y = np.clip(((tile_south + 1 - latitudes[in_rows]) * size_y).astype(np.int64), 0, size_y - 1)
        x = np.clip(((longitudes[in_columns] - tile_west) * size_x).astype(np.int64), 0, size_x - 1)
        grid[np.ix_(in_rows, in_columns)] = heights[np.ix_(y, x)]
    return grid, count


def median3(grid):
    """A 3 × 3 median, row band by row band (edges keep their own)."""
    out = grid.copy()
    rows = grid.shape[0]
    band = 512
    for start in range(1, rows - 1, band):
        end = min(rows - 1, start + band)
        window = np.lib.stride_tricks.sliding_window_view(grid[start - 1:end + 1], (3, 3))
        out[start:end, 1:-1] = np.nanmedian(window.reshape(window.shape[0], window.shape[1], 9), axis=2)
    return out


def encode(mask):
    encoded = []
    for row in range(mask.shape[0]):
        line = mask[row]
        if not line.any():
            continue
        edges = np.flatnonzero(np.diff(np.concatenate(([False], line, [False])).astype(np.int8)))
        starts, ends = edges[0::2], edges[1::2]
        numbers = [row, int(starts[0]), int(ends[0] - starts[0])]
        for previous_end, start, end in zip(ends[:-1], starts[1:], ends[1:]):
            numbers += [int(start - previous_end), int(end - start)]
        encoded.append(numbers)
    return encoded


def main(water_path, folder, out):
    data = json.load(open(water_path))
    rows, step = data['rows'], data['cellDegrees']
    water = water_mask(data)
    grid, count = heights_on_grid(data, folder)
    grid[water] = 0
    smooth = median3(np.nan_to_num(grid, nan=0.0))
    latitudes = data['north'] - (np.arange(rows) + 0.5) * step
    dy = 2 * step * METRES_PER_DEGREE_LATITUDE
    dx = (2 * step * METRES_PER_DEGREE_LONGITUDE * np.cos(np.radians(latitudes)))[:, None]
    north_south = np.zeros_like(smooth)
    east_west = np.zeros_like(smooth)
    north_south[1:-1, :] = np.abs(smooth[:-2, :] - smooth[2:, :]) / dy
    east_west[:, 1:-1] = np.abs(smooth[:, 2:] - smooth[:, :-2]) / dx
    slope = np.maximum(north_south, east_west)
    raw = (slope > SLOPE) & ~water & ~np.isnan(grid)
    # A 3 × 3 majority.
    padded = np.pad(raw, 1).astype(np.uint8)
    votes = sum(padded[1 + dr:1 + dr + rows, 1 + dc:1 + dc + raw.shape[1]] for dr in (-1, 0, 1) for dc in (-1, 0, 1))
    steep = (votes >= 5) & ~water & ~np.isnan(grid)
    data['steep'] = encode(steep)
    data['slopeSource'] = (
        'Copernicus DEM GLO-30 (GLO-90 where only that is released), (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH '
        '2014-2018 provided under COPERNICUS by the European Union and ESA'
    )
    text = json.dumps(data, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)
    cell_km2 = (step * METRES_PER_DEGREE_LATITUDE / 1000) * (step * METRES_PER_DEGREE_LONGITUDE / 1000 * np.cos(np.radians(latitudes)))
    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)
    runs = sum((len(numbers) - 1) // 2 for numbers in data['steep'])
    print(f'{out}: {count} tiles; land {km2(~water)} km², steep {km2(steep)} km² ({runs} runs); {len(text)} bytes')
    return data, steep, grid


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
