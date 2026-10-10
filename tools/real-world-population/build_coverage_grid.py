#!/usr/bin/env python3
"""How much of each cell of the water file's grid Taiwan's buildings cover,
from Overture Maps' buildings, as the app's
`Resources/RealWorld/taiwan_coverage.dat` (ARCHITECTURE decision 147).

    pip install duckdb osmium numpy
    python3 tools/real-world-population/build_overture_building_grid.py \\
        extract 2026-09-23.1 overture_taiwan.parquet
    python3 tools/real-world-population/build_coverage_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        overture_taiwan.parquet \\
        RailwayGameApp/Resources/RealWorld/taiwan_coverage.dat

The water file (`build_water_grid.py`) gives the grid: 1.875″ cells, some
58 × 53 m. The extract is the survey's (`build_overture_building_grid.py`):
mainland Taiwan with Penghu, where the survey found Overture's footprints
nearly whole. A cell whose middle lies outside those bounds (Kinmen, Matsu)
is UNKNOWN: there Overture misses most of the towns (Jincheng's middle has
some 2 % of its ground built), and the game reckons its buildings as before.

Each building's footprint is cut by the cells its box reaches (DuckDB's
spatial extension), so a building across several cells counts in each for
the part on it; a cell's coverage is its buildings' ground over its own, in
whole percent, at most 100 (Overture's footprints may overlap a little),
measured in square degrees, as a cell's latitude scales both alike. Water
is 0. Overture's buildings in Taiwan are OpenStreetMap's (ODbL 1.0) and,
where OpenStreetMap has none, the East Asian buildings of Shi et al.
(doi:10.5281/zenodo.8174931, CC BY 4.0) traced from imagery; the theme is
ODbL 1.0 (`docs/research/OSM_BUILDING_SURVEY.md`, "Overture Maps").

The file is the heights file's form (`build_slope_grid.py`) under the magic
`TWCV`: the percentages (UNKNOWN, -1, where the extract does not reach)
row by row as varint differences with runs of equal values, each row read
alone (GamePresentation's `CoverageGrid`).
"""
import json
import sys

import duckdb
import numpy as np

from build_overture_building_grid import BOUNDS
from build_slope_grid import encode_heights, water_mask

# A cell the buildings' extract does not reach.
UNKNOWN = -1


def coverage(data, extract):
    """The grid's coverage in whole percent, by row and column."""
    rows, columns = data['rows'], data['columns']
    north, west, step = data['north'], data['west'], data['cellDegrees']
    connection = duckdb.connect()
    connection.sql('INSTALL spatial; LOAD spatial;')
    found = connection.sql(f"""
        WITH shapes AS (
            SELECT ST_GeomFromWKB(footprint) AS shape FROM read_parquet('{extract}')
        ), spans AS (
            SELECT shape,
                   floor(({north} - ST_YMax(shape)) / {step})::BIGINT AS r0, floor(({north} - ST_YMin(shape)) / {step})::BIGINT AS r1,
                   floor((ST_XMin(shape) - {west}) / {step})::BIGINT AS c0, floor((ST_XMax(shape) - {west}) / {step})::BIGINT AS c1
            FROM shapes
        ), by_row AS (
            SELECT shape, r0, r1, c0, c1, unnest(range(r0, r1 + 1)) AS r FROM spans
        ), by_cell AS (
            SELECT shape, r0, r1, c0, c1, r, unnest(range(c0, c1 + 1)) AS c FROM by_row
        )
        SELECT r, c, sum(CASE WHEN r0 = r1 AND c0 = c1 THEN ST_Area(shape)
                              ELSE ST_Area(ST_Intersection(shape, ST_MakeEnvelope(
                                  {west} + c * {step}, {north} - (r + 1) * {step}, {west} + (c + 1) * {step}, {north} - r * {step})))
                         END) AS area
        FROM by_cell
        WHERE r BETWEEN 0 AND {rows - 1} AND c BETWEEN 0 AND {columns - 1}
        GROUP BY r, c
    """).fetchnumpy()
    grid = np.zeros((rows, columns), dtype=np.int64)
    percent = np.minimum(100, np.rint(100 * found['area'] / (step * step))).astype(np.int64)
    grid[found['r'], found['c']] = percent
    grid[water_mask(data)] = 0
    west_, south, east, north_ = BOUNDS
    latitudes = north - (np.arange(rows) + 0.5) * step
    longitudes = west + (np.arange(columns) + 0.5) * step
    outside = ~((latitudes >= south) & (latitudes <= north_))[:, None] | ~((longitudes >= west_) & (longitudes <= east))[None, :]
    grid[outside] = UNKNOWN
    return grid


def main(water_path, extract, out):
    data = json.load(open(water_path))
    grid = coverage(data, extract)
    open(out, 'wb').write(encode_heights(grid, data, magic=b'TWCV'))
    covered = grid > 0
    print(f'{(grid == UNKNOWN).sum()} cells unknown', file=sys.stderr)
    print(f'{covered.sum()} cells with buildings, mean {grid[covered].mean():.1f}% of them, '
          f'{(grid >= 50).sum()} at half or more', file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
