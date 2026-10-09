#!/usr/bin/env python3
"""Map Taiwan's water, the sea off its coast, its rivers and its lakes, on a
fine cut of WorldPop's grid, for the app's
`Resources/RealWorld/taiwan_water.json` (ARCHITECTURE decision 105).

    python3 tools/real-world-population/build_water_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_population.json \\
        taiwan.pbf \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        [taiwan_land.json]

The population file gives the grid: its corner and cell size (30″); each of
its cells is cut into CUTS × CUTS water cells (1.875″, some 58 × 53 m in
Taiwan, about one of the game's 64 m cells). A water cell is water when its
middle is:

- the sea: not inside any closed ring of OpenStreetMap's coastline
  (`natural=coastline`, ways joined end to end, even-odd). A ring the
  extract cut open (the edge of the extract crosses China's Dadeng island
  north of Kinmen) is not Taiwan's and is left out;
- or a body of water (WATER_TAGS: `natural=water`, `waterway=riverbank`,
  `waterway=dock`, `landuse=reservoir`), its inner rings islands, but not a
  fish pond (`landuse=aquaculture`, `water=fishpond`): decision 96 farms
  those.

The grid covers Taiwan's land with MARGIN degrees round it (some 11 km, more
than half a 16 km map); a point outside it has no water. Inside it, land
that is not Taiwan's (the coast of China facing Kinmen and Matsu) is sea, as
the extract has only Taiwan.

The extract (an OpenStreetMap `.pbf` file, osmtoday.com's
`asia/taiwan.pbf`) is read with pyosmium (BSD 2-Clause; `pip install
osmium`), and the cells are filled with numpy, in about a minute.

Given the Ministry of the Interior's coastline (`taiwan_land.json`, the
reference's `Railway/site_archive_clean/data/`, its counties' boundaries
dissolved and simplified to about 150 m), it also says how many water cells
it puts on land and land cells in the sea, the check decision 105 made.

The file: `{"source", "licence", "osmData", "north", "west", "cellDegrees",
"rows", "columns", "water": [[row, column, count, gap, count, …], …]}`, a
row with water once, in order, its runs of water as the first's column and
length, then for each next one the gap of land before it and its length.
"""
import json
import math
import os
import sys

import numpy as np

CUTS = 16
MARGIN = 0.1
WATER_TAGS = {
    'natural': ('water',),
    'waterway': ('riverbank', 'dock'),
    'landuse': ('reservoir',),
}
# Fish ponds farm (decision 96): never water.
FARMED = {'landuse': ('aquaculture',), 'water': ('fishpond', '魚塭')}


def crossings(rings, north, west, step, rows):
    """For each ring edge, the rows of `step` degrees from `north` whose
    middle latitude it crosses, and its longitude there, as numpy arrays
    (row, longitude, group); `rings` is a list of (group, points)."""
    out_rows, out_lons, out_groups = [], [], []
    for group, ring in rings:
        points = np.asarray(ring, dtype=np.float64)
        if len(points) < 4:
            continue
        a, b = points[:-1], points[1:]
        lat_a, lon_a, lat_b, lon_b = a[:, 0], a[:, 1], b[:, 0], b[:, 1]
        keep = lat_a != lat_b
        lat_a, lon_a, lat_b, lon_b = lat_a[keep], lon_a[keep], lat_b[keep], lon_b[keep]
        low, high = np.minimum(lat_a, lat_b), np.maximum(lat_a, lat_b)
        # The rows whose middle latitude lies in [low, high).
        first = np.ceil((north - high) / step - 0.5).astype(np.int64)
        last = np.ceil((north - low) / step - 0.5).astype(np.int64) - 1
        first = np.maximum(first, 0)
        last = np.minimum(last, rows - 1)
        counts = np.maximum(last - first + 1, 0)
        if counts.sum() == 0:
            continue
        edge = np.repeat(np.arange(len(counts)), counts)
        row = first[edge] + (np.arange(counts.sum()) - np.repeat(np.cumsum(counts) - counts, counts))
        latitude = north - (row + 0.5) * step
        inside = (low[edge] <= latitude) & (latitude < high[edge])
        edge, row, latitude = edge[inside], row[inside], latitude[inside]
        longitude = lon_a[edge] + (latitude - lat_a[edge]) * (lon_b[edge] - lon_a[edge]) / (lat_b[edge] - lat_a[edge])
        out_rows.append(row)
        out_lons.append(longitude)
        out_groups.append(np.full(len(row), group, dtype=np.int64))
    if not out_rows:
        return np.zeros(0, np.int64), np.zeros(0), np.zeros(0, np.int64)
    return np.concatenate(out_rows), np.concatenate(out_lons), np.concatenate(out_groups)


def fill(rings, north, west, step, rows, columns):
    """The cells (a rows × columns bool array) whose middles lie inside a
    group of `rings` (even-odd within each group; the groups together)."""
    row, longitude, group = crossings(rings, north, west, step, rows)
    order = np.lexsort((longitude, group, row))
    row, longitude, group = row[order], longitude[order], group[order]
    # Each group crosses each row an even number of times: pair them.
    assert len(row) % 2 == 0 and np.all(row[0::2] == row[1::2]) and np.all(group[0::2] == group[1::2])
    start, end, span_row = longitude[0::2], longitude[1::2], row[0::2]
    first = np.maximum(np.ceil((start - west) / step - 0.5).astype(np.int64), 0)
    last = np.minimum(np.ceil((end - west) / step - 0.5).astype(np.int64) - 1, columns - 1)
    keep = first <= last
    first, last, span_row = first[keep], last[keep], span_row[keep]
    depth = np.zeros((rows, columns + 1), dtype=np.int32)
    np.add.at(depth, (span_row, first), 1)
    np.add.at(depth, (span_row, last + 1), -1)
    return np.cumsum(depth, axis=1, dtype=np.int32)[:, :columns] > 0


def coastline(path):
    """Taiwan's coastline as closed rings of (lat, lon), and the newest edit."""
    import osmium  # pyosmium.
    ways, newest = [], None

    class Handler(osmium.SimpleHandler):
        def way(self, way):
            nonlocal newest
            if way.tags.get('natural') == 'coastline':
                ways.append([(node.ref, node.lat, node.lon) for node in way.nodes])
                stamp = way.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
                newest = max(newest or stamp, stamp)

    Handler().apply_file(path, locations=True)
    starts = {}
    for index, way in enumerate(ways):
        starts.setdefault(way[0][0], []).append(index)
    used, rings, cut = [False] * len(ways), [], 0
    for index in range(len(ways)):
        if used[index]:
            continue
        used[index] = True
        ring = list(ways[index])
        while ring[0][0] != ring[-1][0]:
            following = [n for n in starts.get(ring[-1][0], []) if not used[n]]
            if not following:
                break
            used[following[0]] = True
            ring += ways[following[0]][1:]
        if ring[0][0] == ring[-1][0]:
            rings.append([(lat, lon) for _, lat, lon in ring])
        else:
            cut += 1
    return rings, cut, newest


def water_areas(path):
    """The rings of every body of water (outer and inner alike, one group
    an area), how many, and the newest edit among them."""
    import osmium  # pyosmium.
    areas, count, newest = [], 0, None
    keys = sorted(set(WATER_TAGS) | set(FARMED))
    processor = osmium.FileProcessor(path).with_areas(osmium.filter.KeyFilter(*keys))
    for area in processor.with_filter(osmium.filter.EntityFilter(osmium.osm.AREA)):
        tags = area.tags
        if not any(tags.get(key) in values for key, values in WATER_TAGS.items()):
            continue
        if any(tags.get(key) in values for key, values in FARMED.items()):
            continue
        count += 1
        for outer in area.outer_rings():
            areas.append((count, [(node.lat, node.lon) for node in outer]))
            for inner in area.inner_rings(outer):
                areas.append((count, [(node.lat, node.lon) for node in inner]))
        stamp = area.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
        newest = max(newest or stamp, stamp)
    return areas, count, newest


def main(population_path, extract, out, moi=None):
    population = json.load(open(population_path))
    size = population['cellDegrees']
    step = size / CUTS
    rings, cut, coast_stamp = coastline(extract)
    lats = [lat for ring in rings for lat, _ in ring]
    lons = [lon for ring in rings for _, lon in ring]
    # Whole population cells from the population grid's corner, MARGIN round
    # the land.
    top = math.floor((population['north'] - (max(lats) + MARGIN)) / size)
    left = math.floor((min(lons) - MARGIN - population['west']) / size)
    bottom = math.ceil((population['north'] - (min(lats) - MARGIN)) / size)
    right = math.ceil((max(lons) + MARGIN - population['west']) / size)
    north = population['north'] - top * size
    west = population['west'] + left * size
    rows, columns = (bottom - top) * CUTS, (right - left) * CUTS

    land = fill([(0, ring) for ring in rings], north, west, step, rows, columns)
    areas, count, water_stamp = water_areas(extract)
    inland = fill(areas, north, west, step, rows, columns)
    water = ~land | inland

    encoded = []
    for row in range(rows):
        line = water[row]
        if not line.any():
            continue
        edges = np.flatnonzero(np.diff(np.concatenate(([False], line, [False])).astype(np.int8)))
        starts, ends = edges[0::2], edges[1::2]
        numbers = [row, int(starts[0]), int(ends[0] - starts[0])]
        for previous_end, start, end in zip(ends[:-1], starts[1:], ends[1:]):
            numbers += [int(start - previous_end), int(end - start)]
        encoded.append(numbers)
    stamps = sorted(stamp for stamp in (coast_stamp, water_stamp) if stamp)
    data = {
        'source': f'OpenStreetMap contributors, from the extract {os.path.basename(extract)}',
        'licence': 'ODbL 1.0',
        'osmData': [stamps[-1], stamps[-1]],
        'north': north,
        'west': west,
        'cellDegrees': step,
        'rows': rows,
        'columns': columns,
        'water': encoded,
    }
    text = json.dumps(data, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)

    latitude = north - (np.arange(rows) + 0.5) * step
    cell_km2 = (step * 110.574) * (step * 111.320 * np.cos(np.radians(latitude)))
    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)
    runs = sum((len(numbers) - 1) // 2 for numbers in encoded)
    print(f'{out}: {rows} × {columns} cells of {step * 3600:.3f}″ from {north:.6f}°N {west:.6f}°E; '
          f'{len(rings)} coastline rings ({cut} cut open, left out), {count} bodies of water; '
          f'land {km2(land)} km², inland water {km2(inland & land)} km² on it, water {km2(water)} km²; '
          f'{runs} runs, OSM data to {stamps[-1]}, {len(text)} bytes')
    if moi:
        feature = json.load(open(moi))
        moi_rings = [(n, [(lat, lon) for lon, lat in ring]) for n, polygon in enumerate(feature['geometry']['coordinates']) for ring in polygon]
        moi_land = fill(moi_rings, north, west, step, rows, columns)
        print(f'MOI: land {km2(moi_land)} km²; MOI land that OSM calls sea {km2(moi_land & ~land)} km², '
              f'OSM land that MOI calls sea {km2(land & ~moi_land)} km²; '
              f'cells agreeing {100 * float((moi_land == land).mean()):.2f} %')


if __name__ == '__main__':
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    main(*sys.argv[1:])
