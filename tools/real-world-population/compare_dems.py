#!/usr/bin/env python3
"""Compare two builds of the game's Taiwan ground (ARCHITECTURE decision
943): the heights file and the water file's steep cells before and after a
change of source, as the app reads them:

    git show origin/main:RailwayGameApp/Resources/RealWorld/taiwan_heights.dat > /tmp/before.dat
    git show origin/main:RailwayGameApp/Resources/RealWorld/taiwan_water.json > /tmp/before.json
    python3 -I tools/real-world-population/compare_dems.py \\
        /tmp/before.dat /tmp/before.json \\
        RailwayGameApp/Resources/RealWorld/taiwan_heights.dat \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        RailwayGameApp/Resources/RealRailways/rail_tracks.json

Three things are counted for each build:

  steep cells    in a box round each place and over the whole grid
  heights        at known points, between cells' middles (bilinear, as
                 GamePresentation's `HeightGrid` reads the file)
  rail grades    along the real railways' surface track (`rail_tracks.json`'s
                 ways of kind `s`, on the ground, not on a bridge or in a
                 tunnel), a place every 25 m: how many 100 m stretches the
                 ground climbs or falls more than 40 ‰ (4 m), the grade the
                 game lays track within, and the ground's rise and fall a
                 kilometre. A real surface line is nowhere that steep (the
                 Alishan line's 62.5 ‰ aside), so each such stretch is the
                 data's doing.

The rail grades are counted three ways: reading the file directly; on the
game's ground, which is GameCore's 64 m block corners (`HeightGrid.ground(of:
frame:)` reads the file once at each corner, and track and the 3D ground
take the corners, not the file), the corners bilinear between; and on
32 m corners, for a finer ground the game does not have. The corner lattice
is a plane in metres round 23.7° N, not a game's own frame, so the counts
are the same for every anchor within a few.

Prints Markdown tables. Needs numpy only; a few minutes, most of it decoding the two heights
files.
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'basemap'))
from build_terrain import read_heights  # noqa: E402

METRES_PER_DEGREE_LATITUDE = 110_574.0
METRES_PER_DEGREE_LONGITUDE = 111_320.0
LATITUDE = 23.7

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
# Name, latitude, longitude and half the box's side in degrees: the
# surface track of a few valley lines, counted alone.
LINES = [
    ('平溪線', 25.0300, 121.7650, 0.07),
    ('內灣線', 24.7350, 121.1300, 0.07),
    ('集集線', 23.8400, 120.7300, 0.12),
]
WINDOW = 100.0
STEP = 25.0
GRADE = 0.040
CORNERS = (None, 64.0, 32.0)


def runs(rows, columns, encoded):
    """The cells of a `[[row, column, count, gap, count, …], …]` list."""
    mask = np.zeros((rows, columns), dtype=bool)
    for numbers in encoded:
        row, column = numbers[0], numbers[1]
        mask[row, column:column + numbers[2]] = True
        column += numbers[2]
        for gap, count in zip(numbers[3::2], numbers[4::2]):
            column += gap
            mask[row, column:column + count] = True
            column += count
    return mask


class Build:
    def __init__(self, heights_path, water_path):
        self.north, self.west, self.cell, self.grid = read_heights(heights_path)
        self.metres = self.grid.astype(np.float64)
        water = json.load(open(water_path))
        assert (water['rows'], water['columns']) == self.grid.shape, 'the two files are not on one grid'
        self.water = runs(water['rows'], water['columns'], water['water'])
        self.steep = runs(water['rows'], water['columns'], water.get('steep', []))

    def read(self, latitudes, longitudes):
        """The heights between cells' middles, as `HeightGrid` reads them."""
        rows, columns = self.grid.shape
        y = np.clip((self.north - latitudes) / self.cell - 0.5, 0, rows - 1.001)
        x = np.clip((longitudes - self.west) / self.cell - 0.5, 0, columns - 1.001)
        row, column = y.astype(np.int64), x.astype(np.int64)
        v, u = y - row, x - column
        g = self.metres
        return (g[row, column] * (1 - u) * (1 - v) + g[row, column + 1] * u * (1 - v)
                + g[row + 1, column] * (1 - u) * v + g[row + 1, column + 1] * u * v)

    def ground(self, latitudes, longitudes, corner):
        """The ground the game would draw: the file at `corner`-metre
        corners, bilinear between; the file itself when `corner` is None."""
        if corner is None:
            return self.read(latitudes, longitudes)
        east = METRES_PER_DEGREE_LONGITUDE * math.cos(math.radians(LATITUDE))
        x, y = longitudes * east / corner, latitudes * METRES_PER_DEGREE_LATITUDE / corner
        x0, y0 = np.floor(x), np.floor(y)
        u, v = x - x0, y - y0

        def at(cx, cy):
            return self.read(cy * corner / METRES_PER_DEGREE_LATITUDE, cx * corner / east)
        return (at(x0, y0) * (1 - u) * (1 - v) + at(x0 + 1, y0) * u * (1 - v)
                + at(x0, y0 + 1) * (1 - u) * v + at(x0 + 1, y0 + 1) * u * v)

    def box(self, latitude, longitude, half):
        rows, columns = self.grid.shape
        top = max(0, int((self.north - latitude - half) / self.cell))
        bottom = min(rows, int((self.north - latitude + half) / self.cell))
        left = max(0, int((longitude - half - self.west) / self.cell))
        right = min(columns, int((longitude + half - self.west) / self.cell))
        return slice(top, bottom), slice(left, right)


def surface_ways(path):
    """Each surface way of the real railways: its system's name and its
    points' latitudes and longitudes in degrees."""
    tracks = json.load(open(path))
    for way in tracks['ways']:
        if way['kind'] != 's':
            continue
        numbers = np.array(way['points'], dtype=np.int64).reshape(-1, 3)
        yield tracks['systems'][way['system']], np.cumsum(numbers[:, 1]) / 1e6, np.cumsum(numbers[:, 0]) / 1e6


def samples(latitudes, longitudes):
    """Places every STEP metres along a way, or None for a way shorter
    than WINDOW."""
    x = (longitudes - longitudes[0]) * METRES_PER_DEGREE_LONGITUDE * np.cos(np.radians(latitudes[0]))
    y = (latitudes - latitudes[0]) * METRES_PER_DEGREE_LATITUDE
    along = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(x), np.diff(y)))))
    if along[-1] < WINDOW:
        return None
    at = np.arange(0.0, along[-1], STEP)
    return np.interp(at, along, latitudes), np.interp(at, along, longitudes)


def main(before_heights, before_water, after_heights, after_water, tracks_path):
    builds = {'before': Build(before_heights, before_water), 'after': Build(after_heights, after_water)}
    names = list(builds)
    first = builds['before']
    dry = ~first.water

    print('| 地點 | 乾格 | ' + ' | '.join(f'{n} 陡坡格' for n in names) + ' |')
    print('| --- | ---: | ' + ' | '.join('---:' for _ in names) + ' |')
    for name, latitude, longitude, half in PLACES + [('全部', 0, 0, None)]:
        where = (slice(None), slice(None)) if half is None else first.box(latitude, longitude, half)
        cells = int(dry[where].sum())
        counts = [int(builds[n].steep[where].sum()) for n in names]
        print(f'| {name} | {cells} | ' + ' | '.join(f'{c}（{100 * c / max(cells, 1):.1f}%）' for c in counts) + ' |')
    a, b = builds['before'].steep, builds['after'].steep
    print(f'\nbefore → after：不再是陡坡 {int((a & ~b).sum())} 格，新成為陡坡 {int((~a & b).sum())} 格\n')

    print('| 地點 | 實際 (m) | ' + ' | '.join(f'{n} (m)' for n in names) + ' |')
    print('| --- | ---: | ' + ' | '.join('---:' for _ in names) + ' |')
    for name, latitude, longitude, real in POINTS:
        values = [builds[n].read(np.array([latitude]), np.array([longitude]))[0] for n in names]
        print(f'| {name} | {real} | ' + ' | '.join(f'{v:.1f}' for v in values) + ' |')
    land = ~first.water & ~builds['after'].water
    difference = (builds['after'].grid.astype(np.int32) - first.grid.astype(np.int32))[land]
    print(f'\nafter − before over dry cells: mean {difference.mean():.2f} m, median {np.median(difference):.0f} m, '
          f'p5 {np.percentile(difference, 5):.0f} m, p95 {np.percentile(difference, 95):.0f} m\n')

    span = int(WINDOW / STEP)
    groups = {}
    for system, latitudes, longitudes in surface_ways(tracks_path):
        at = samples(latitudes, longitudes)
        if at is None:
            continue
        keys = [system] + [line for line, la, lo, half in LINES
                           if abs(at[0].mean() - la) < half and abs(at[1].mean() - lo) < half and system == 'tra_sched']
        for key in keys:
            entry = groups.setdefault(key, {'km': 0.0})
            entry['km'] += (len(at[0]) - span) * STEP / 1000
            for n in names:
                for corner in CORNERS:
                    ground = builds[n].ground(at[0], at[1], corner)
                    rise = np.abs(ground[span:] - ground[:-span])
                    count, swing = entry.setdefault((n, corner), [0, 0.0])
                    entry[(n, corner)] = [count + int((rise > GRADE * WINDOW).sum()),
                                          swing + float(np.abs(np.diff(ground)).sum())]
    labels = {None: '直接讀', 64.0: '64 m 角點（遊戲）', 32.0: '32 m 角點'}
    print('超過 40‰ 的 100 m 段數（括號：每公里起伏 m）\n')
    print('| 系統（地面段） | 公里 | ' + ' | '.join(f'{n} {labels[c]}' for n in names for c in CORNERS) + ' |')
    print('| --- | ---: | ' + ' | '.join('---:' for _ in names for _ in CORNERS) + ' |')
    for key, entry in groups.items():
        km = max(entry['km'], 0.001)
        cells = [f'{entry[(n, c)][0]}（{entry[(n, c)][1] / km:.1f}）' for n in names for c in CORNERS]
        print(f'| {key} | {entry["km"]:.1f} | ' + ' | '.join(cells) + ' |')


if __name__ == '__main__':
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
