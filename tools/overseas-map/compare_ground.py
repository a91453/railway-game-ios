#!/usr/bin/env python3
"""How good an overseas map pack's ground is, or two builds of it side by
side (OVERSEAS-DEM, decision 943's measure on a map pack):

    python3 -I tools/overseas-map/compare_ground.py RailwayGameApp/Resources/MapPacks/rovaniemi
    python3 -I tools/overseas-map/compare_ground.py /tmp/before/rovaniemi RailwayGameApp/Resources/MapPacks/rovaniemi

Each folder holds `heights.dat`, `water.json`, `population.json`,
`track_lines.geojson` and `rail_structures.json` (the track and the people
are read from the last folder for every build, so the first may hold the
two ground files alone).

  steep cells    over the map, and among the cells where people live
                 (`population.json`'s 30″ cells of 100 people or more: a
                 town is not built on a 30 % slope, so a steep cell there
                 is mostly the data's doing)
  rail grades    along the lines' track off bridges and out of tunnels, a
                 place every 25 m: how many 100 m stretches the ground
                 climbs or falls more than 40 ‰, read from the file and on
                 the game's 64 m corners (`compare_dems.py`'s count)
  roughness      the mean difference between a dry cell and the median of
                 the nine round it, in metres: a surface model's trees and
                 roofs show here

Needs numpy only.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
import build_slope_grid  # noqa: E402
import compare_dems  # noqa: E402

PEOPLE = 100
NEAR_STRUCTURE = 40.0


def structure_points(folder):
    """A point every 10 m or so along each bridge and tunnel, (lat, lon)."""
    path = os.path.join(folder, 'rail_structures.json')
    if not os.path.exists(path):
        return np.zeros((0, 2))
    points = []
    for structure in json.load(open(path, encoding='utf-8'))['structures']:
        line = structure['points']
        for (x0, y0), (x1, y1) in zip(line, line[1:]):
            length = math.hypot((x1 - x0) * 111_320 * math.cos(math.radians(y0)), (y1 - y0) * 110_574)
            for k in range(int(length // 10) + 2):
                t = min(1.0, k * 10 / max(length, 1e-9))
                points.append((y0 + t * (y1 - y0), x0 + t * (x1 - x0)))
    return np.array(points).reshape(-1, 2)


def people_cells(folder, build):
    """The build's cells inside a `population.json` cell of PEOPLE or more."""
    population = json.load(open(os.path.join(folder, 'population.json'), encoding='utf-8'))
    step = population['cellDegrees']
    rows, columns = build.grid.shape
    mask = np.zeros((rows, columns), dtype=bool)
    for run in population['runs']:
        for offset, people in enumerate(run['p']):
            if people < PEOPLE:
                continue
            north = population['north'] - run['r'] * step
            west = population['west'] + (run['c'] + offset) * step
            top = max(0, round((build.north - north) / build.cell))
            left = max(0, round((west - build.west) / build.cell))
            size = round(step / build.cell)
            mask[top:top + size, left:left + size] = True
    return mask


def main(folders):
    last = folders[-1]
    builds = [compare_dems.Build(os.path.join(f, 'heights.dat'), os.path.join(f, 'water.json')) for f in folders]
    first = builds[0]
    compare_dems.LATITUDE = first.north - first.grid.shape[0] * first.cell / 2
    names = ['before', 'after'] if len(builds) == 2 else ['pack']
    town = people_cells(last, first)
    structures = structure_points(last)
    lines = json.load(open(os.path.join(last, 'track_lines.geojson'), encoding='utf-8'))['features']

    print('| | ' + ' | '.join(names) + ' |')
    print('| --- | ' + ' | '.join('---:' for _ in names) + ' |')

    def row(label, values):
        print(f'| {label} | ' + ' | '.join(values) + ' |')

    dry = [~b.water for b in builds]
    row('乾格', [str(int(d.sum())) for d in dry])
    row('陡坡格（佔乾格）', [f'{int(b.steep.sum())}（{100 * b.steep.sum() / max(d.sum(), 1):.2f}%）'
                      for b, d in zip(builds, dry)])
    row(f'有人住的格（30″ 格 ≥ {PEOPLE} 人）裡的陡坡格',
        [f'{int((b.steep & town).sum())}／{int((town & d).sum())}（{100 * (b.steep & town).sum() / max((town & d).sum(), 1):.2f}%）'
         for b, d in zip(builds, dry)])
    rough = []
    for b, d in zip(builds, dry):
        smooth = build_slope_grid.median3(b.grid.astype(np.float32))
        rough.append(f'{float(np.abs(b.metres - smooth)[d].mean()):.2f}')
    row('粗糙度（乾格與 3 × 3 中位數的平均差，m）', rough)
    row('高度範圍（m）', [f'{int(b.grid.min())} – {int(b.grid.max())}' for b in builds])

    span = int(compare_dems.WINDOW / compare_dems.STEP)
    total = {(n, c): [0, 0.0] for n in range(len(builds)) for c in (None, 64.0)}
    km = 0.0
    for feature in lines:
        geometry = feature['geometry']
        parts = geometry['coordinates'] if geometry['type'] == 'MultiLineString' else [geometry['coordinates']]
        for part in parts:
            points = np.array(part, dtype=np.float64)
            at = compare_dems.samples(points[:, 1], points[:, 0])
            if at is None:
                continue
            keep = np.ones(len(at[0]), dtype=bool)
            if len(structures):
                east = 111_320 * math.cos(math.radians(compare_dems.LATITUDE))
                for index in range(len(at[0])):
                    dy = (structures[:, 0] - at[0][index]) * 110_574
                    dx = (structures[:, 1] - at[1][index]) * east
                    keep[index] = (dx * dx + dy * dy).min() > NEAR_STRUCTURE ** 2
            both = keep[span:] & keep[:-span]
            km += int(both.sum()) * compare_dems.STEP / 1000
            for n, build in enumerate(builds):
                for corner in (None, 64.0):
                    ground = build.ground(at[0], at[1], corner)
                    rise = np.abs(ground[span:] - ground[:-span])
                    step = np.abs(np.diff(ground))[keep[1:] & keep[:-1]]
                    total[(n, corner)][0] += int(((rise > compare_dems.GRADE * compare_dems.WINDOW) & both).sum())
                    total[(n, corner)][1] += float(step.sum())
    row(f'地面段沿線超過 40‰ 的 100 m 段（{km:.1f} km），直接讀',
        [f'{total[(n, None)][0]}（每公里起伏 {total[(n, None)][1] / max(km, 0.001):.1f} m）' for n in range(len(builds))])
    row('同上，64 m 角點（遊戲）',
        [f'{total[(n, 64.0)][0]}（每公里起伏 {total[(n, 64.0)][1] / max(km, 0.001):.1f} m）' for n in range(len(builds))])
    if len(builds) == 2:
        a, b = builds
        land = dry[0] & dry[1]
        difference = (b.grid.astype(np.int32) - a.grid.astype(np.int32))[land]
        print(f'\nbefore → after：不再是陡坡 {int((a.steep & ~b.steep).sum())} 格，新成為陡坡 {int((~a.steep & b.steep).sum())} 格；'
              f'乾格高度差 平均 {difference.mean():.2f} m、中位數 {np.median(difference):.0f} m、'
              f'p5 {np.percentile(difference, 5):.0f} m、p95 {np.percentile(difference, 95):.0f} m')


if __name__ == '__main__':
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    main(sys.argv[1:])
