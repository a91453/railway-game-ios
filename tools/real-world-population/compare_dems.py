#!/usr/bin/env python3
"""Measure what the Ministry of the Interior's 20 m DTM would change against
the Copernicus surface model the game's ground was made from (ARCHITECTURE
decision 943), before anything is replaced:

    python3 tools/real-world-population/compare_dems.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        copernicus-dem/ moi-dtm/tw.tif \\
        RailwayGameApp/Resources/RealRailways/rail_tracks.json

On the water file's grid (1.875″), each variant's steep cells and whole-metre
heights are worked out exactly as `build_slope_grid.py` writes them:

  copernicus       what the game has: the surface model, 3 × 3 median
  moi              the DTM as it is where it reaches (the main island and
                   the islets on its sheet), Copernicus elsewhere
  moi+median       the same, with the 3 × 3 median over the DTM too

and three things are counted: steep cells in a box round each place and
over all the land; the heights at known points; and, along the real
railways' surface track (`rail_tracks.json`'s ways of kind `s`, which stand
on the ground, not on a bridge or in a tunnel), how many 100 m stretches the
ground climbs or falls more than 40 ‰ (4 m), the grade the game lays track
within. A real surface line is nowhere that steep (the Alishan line's
62.5 ‰ aside), so each such stretch is the data's doing: a building, a
tree line, a river bank or a cell that mixes two levels.

Prints Markdown tables. Needs numpy, tifffile and imagecodecs.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_slope_grid as slopes  # noqa: E402

# Name, latitude, longitude, half the box's side in degrees.
PLACES = [
    ('台北市中心', 25.0478, 121.5170, 0.04),
    ('台中市中心', 24.1447, 120.6736, 0.04),
    ('高雄市中心', 22.6273, 120.3014, 0.04),
    ('九份', 25.1092, 121.8443, 0.02),
    ('陽明山', 25.1700, 121.5450, 0.04),
    ('十分', 25.0410, 121.7755, 0.02),
    ('平溪線（三貂嶺–菁桐）', 25.0400, 121.7800, 0.05),
    ('內灣線（竹東–內灣）', 24.7200, 121.1400, 0.05),
    ('集集線（二水–車埕）', 23.8300, 120.7400, 0.10),
    ('阿里山山腳（竹崎–樟腦寮）', 23.5300, 120.5900, 0.05),
    ('玉山', 23.4700, 120.9573, 0.04),
]
# Name, latitude, longitude, the height on the ground in metres.
POINTS = [
    ('台北車站', 25.0478, 121.5170, 7),
    ('台北 101', 25.0336, 121.5650, 10),
    ('板橋車站', 25.0143, 121.4635, 8),
    ('台中車站', 24.1369, 120.6850, 77),
    ('高雄車站', 22.6394, 120.3020, 9),
    ('阿里山車站', 23.5103, 120.8040, 2216),
    ('合歡山武嶺', 24.1372, 121.2756, 3275),
    ('玉山主峰', 23.4700, 120.9573, 3952),
]
WINDOW = 100.0
STEP = 25.0
GRADE = 0.040


def variant(data, water, grid, keep):
    """The steep cells and whole-metre heights `build_slope_grid.py` would
    write from `grid`, keeping the cells of `keep` out of the median."""
    steep, _ = slopes.steep_cells(data, water, grid, keep)
    return steep, slopes.ground_heights(data, water, grid, keep)


def bilinear(heights, data, latitudes, longitudes):
    """The heights between cell middles, as the app's `HeightGrid` reads
    them."""
    y = np.clip((data['north'] - latitudes) / data['cellDegrees'] - 0.5, 0, heights.shape[0] - 1.001)
    x = np.clip((longitudes - data['west']) / data['cellDegrees'] - 0.5, 0, heights.shape[1] - 1.001)
    row, column = y.astype(np.int64), x.astype(np.int64)
    v, u = y - row, x - column
    def h(rows, columns):
        return heights[rows, columns].astype(np.float64)
    return (h(row, column) * (1 - u) * (1 - v) + h(row, column + 1) * u * (1 - v)
            + h(row + 1, column) * (1 - u) * v + h(row + 1, column + 1) * u * v)


def surface_ways(path):
    """Each surface way of the real railways: its system's name and its
    points' longitudes and latitudes in degrees."""
    tracks = json.load(open(path))
    for way in tracks['ways']:
        if way['kind'] != 's':
            continue
        numbers = np.array(way['points'], dtype=np.int64).reshape(-1, 3)
        yield tracks['systems'][way['system']], np.cumsum(numbers[:, 0]) / 1e6, np.cumsum(numbers[:, 1]) / 1e6


def samples(longitudes, latitudes):
    """Places every STEP metres along a way."""
    x = (longitudes - longitudes[0]) * slopes.METRES_PER_DEGREE_LONGITUDE * np.cos(np.radians(latitudes[0]))
    y = (latitudes - latitudes[0]) * slopes.METRES_PER_DEGREE_LATITUDE
    along = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(x), np.diff(y)))))
    if along[-1] < WINDOW:
        return None
    at = np.arange(0.0, along[-1], STEP)
    return np.interp(at, along, latitudes), np.interp(at, along, longitudes)


def main(water_path, copernicus, moi_path, tracks_path):
    data = json.load(open(water_path))
    water = slopes.water_mask(data)
    rows, columns, step = data['rows'], data['columns'], data['cellDegrees']
    surface, _ = slopes.heights_on_grid(data, copernicus)
    mixed, has = slopes.with_moi(data, water, surface, slopes.moi_on_grid(data, moi_path))
    variants = {
        'copernicus': variant(data, water, surface, None),
        'moi': variant(data, water, mixed, has),
        'moi+median': variant(data, water, mixed, None),
    }
    names = list(variants)
    dry = ~water & np.isfinite(surface)

    def box(latitude, longitude, half):
        top = max(0, int((data['north'] - latitude - half) / step))
        bottom = min(rows, int((data['north'] - latitude + half) / step))
        left = max(0, int((longitude - half - data['west']) / step))
        right = min(columns, int((longitude + half - data['west']) / step))
        return slice(top, bottom), slice(left, right)

    print(f'dry cells {int(dry.sum())}, of them with the DTM {int((dry & has).sum())} '
          f'({100 * (dry & has).sum() / dry.sum():.2f} %)\n')
    print('| 地點 | 乾格 | ' + ' | '.join(f'{n} 陡坡格' for n in names) + ' |')
    print('| --- | ---: | ' + ' | '.join('---:' for _ in names) + ' |')
    for name, latitude, longitude, half in PLACES + [('全部', 0, 0, None)]:
        where = (slice(None), slice(None)) if half is None else box(latitude, longitude, half)
        cells = int(dry[where].sum())
        counts = [int(variants[n][0][where].sum()) for n in names]
        print(f'| {name} | {cells} | ' + ' | '.join(f'{c}（{100 * c / max(cells, 1):.1f}%）' for c in counts) + ' |')
    first, second = variants['copernicus'][0], variants['moi'][0]
    print(f'\ncopernicus → moi：不再是陡坡 {int((first & ~second).sum())} 格，新成為陡坡 {int((~first & second).sum())} 格\n')

    print('| 地點 | 實際 (m) | ' + ' | '.join(f'{n} (m)' for n in names) + ' |')
    print('| --- | ---: | ' + ' | '.join('---:' for _ in names) + ' |')
    for name, latitude, longitude, real in POINTS:
        values = [bilinear(variants[n][1], data, np.array([latitude]), np.array([longitude]))[0] for n in names]
        print(f'| {name} | {real} | ' + ' | '.join(f'{v:.1f}' for v in values) + ' |')

    difference = (variants['moi'][1].astype(np.int32) - variants['copernicus'][1].astype(np.int32))[dry & has]
    print(f'\nmoi − copernicus over the DTM\'s dry cells: mean {difference.mean():.2f} m, median {np.median(difference):.0f} m, '
          f'p5 {np.percentile(difference, 5):.0f} m, p95 {np.percentile(difference, 95):.0f} m\n')

    totals = {}
    span = int(WINDOW / STEP)
    for system, longitudes, latitudes in surface_ways(tracks_path):
        at = samples(longitudes, latitudes)
        if at is None:
            continue
        entry = totals.setdefault(system, {'km': 0.0, **{n: [0, 0.0] for n in names}})
        entry['km'] += (len(at[0]) - span) * STEP / 1000
        for n in names:
            ground = bilinear(variants[n][1], data, at[0], at[1])
            rise = np.abs(ground[span:] - ground[:-span])
            entry[n][0] += int((rise > GRADE * WINDOW).sum())
            entry[n][1] += float(np.abs(np.diff(ground)).sum())
    print('| 系統（地面段） | 公里 | ' + ' | '.join(f'{n} 超過 40‰ 的 100 m 段' for n in names) + ' | '
          + ' | '.join(f'{n} 每公里起伏 (m)' for n in names) + ' |')
    print('| --- | ---: | ' + ' | '.join('---:' for _ in names * 2) + ' |')
    for system, entry in totals.items():
        print(f'| {system} | {entry["km"]:.1f} | ' + ' | '.join(str(entry[n][0]) for n in names) + ' | '
              + ' | '.join(f'{entry[n][1] / max(entry["km"], 0.001):.1f}' for n in names) + ' |')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
