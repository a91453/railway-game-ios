#!/usr/bin/env python3
"""What the overseas maps' ground tools share (FUKUOKA-GROUND): the people
(`population.json`), the steep slopes and the files of the ground
(`water.json`, `heights.dat`, `terrain.pmtiles`), and the land of a map
whose coast the extract cuts open, in the formats of Taiwan's, Hong Kong's
(`tools/hk-map/`) and Rovaniemi's (`tools/rovaniemi-map/`).

A city's tool keeps what is its own (where its heights come from, its
checks, its sources record) and calls these, so that a new map does not
copy another's tool. Rovaniemi's tools call them too and make the same
files as before, byte for byte.
"""
import hashlib
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
import build_slope_grid  # noqa: E402
import build_terrain  # noqa: E402


def write_json(folder, name, value):
    import json
    with open(os.path.join(folder, name), 'w', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')


def population(source, expected_sha256, extent):
    """WorldPop's 1 km grid (constrained, R2025A v1, CC BY 4.0), the series
    of Taiwan's and Hong Kong's, cut to the cells whose middle lies in
    `extent`, in the format of `taiwan_population.json`: WorldPop's own
    grid (30 arc-seconds), its north-west corner the cut's, each run a
    row, its first column and the people of each cell from there on,
    rounded to whole people. Returns the fields of `population.json` but
    its `source`, `from` and `licence`, the file's digest and the cut."""
    import tifffile
    raw = open(source, 'rb').read()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != expected_sha256:
        sys.exit(f'{source}: sha256 {digest}, expected {expected_sha256}')
    page = tifffile.TiffFile(source).pages[0]
    scale = page.tags[33550].value
    tie = page.tags[33922].value
    nodata = float(page.tags[42113].value)
    cells = page.asarray().astype('float64')
    people = np.where((cells == nodata) | ~np.isfinite(cells), 0, np.rint(cells)).astype('int64')
    north, west, step = tie[4], tie[3], scale[0]
    # The rows and columns whose middle is in the extent.
    top = math.ceil((north - extent['north']) / step - 0.5)
    bottom = math.floor((north - extent['south']) / step - 0.5)
    left = math.ceil((extent['west'] - west) / step - 0.5)
    right = math.floor((extent['east'] - west) / step - 0.5)
    cut = people[top:bottom + 1, left:right + 1]
    runs = []
    for row in range(cut.shape[0]):
        col = 0
        while col < cut.shape[1]:
            if cut[row, col] <= 0:
                col += 1
                continue
            start = col
            while col < cut.shape[1] and cut[row, col] > 0:
                col += 1
            runs.append({'r': row, 'c': start, 'p': [int(v) for v in cut[row, start:col]]})
    fields = {'north': north - top * step, 'west': west + left * step, 'cellDegrees': step, 'runs': runs}
    return fields, digest, cut


def steep(level, dry, latitudes, step):
    """`build_slope_grid.py`'s rule (decision 115) on `level` (metres, a
    rows × columns array): the slope of the 3 × 3 median over two cells
    north–south or east–west above SLOPE, kept where five of the nine
    cells round it are steep, on `dry` cells alone."""
    rows, columns = level.shape
    smooth = build_slope_grid.median3(level.astype(np.float32))
    dy = 2 * step * build_slope_grid.METRES_PER_DEGREE_LATITUDE
    dx = (2 * step * build_slope_grid.METRES_PER_DEGREE_LONGITUDE * np.cos(np.radians(latitudes)))[:, None]
    north_south = np.zeros_like(smooth)
    east_west = np.zeros_like(smooth)
    north_south[1:-1, :] = np.abs(smooth[:-2, :] - smooth[2:, :]) / dy
    east_west[:, 1:-1] = np.abs(smooth[:, 2:] - smooth[:, :-2]) / dx
    raw = (np.maximum(north_south, east_west) > build_slope_grid.SLOPE) & dry
    padded = np.pad(raw, 1).astype(np.uint8)
    votes = sum(padded[1 + dr:1 + dr + rows, 1 + dc:1 + dc + columns] for dr in (-1, 0, 1) for dc in (-1, 0, 1))
    return (votes >= 5) & dry


def write_ground(folder, extract, stamp, box, heights, water, steep_cells, slope_source, terrain_name,
                 terrain_attribution):
    """`water.json`, `heights.dat` and `terrain.pmtiles` from the grids;
    `box` is the grid's (north, west, step, rows, columns). Returns the
    length of `heights.dat`."""
    north, west, step, rows, columns = box
    data = {
        'source': f'OpenStreetMap contributors, from the extract {os.path.basename(extract)}',
        'licence': 'ODbL 1.0',
        'osmData': [stamp, stamp],
        'north': north,
        'west': west,
        'cellDegrees': step,
        'rows': rows,
        'columns': columns,
        'water': build_slope_grid.encode(water),
        'steep': build_slope_grid.encode(steep_cells),
        'slopeSource': slope_source,
    }
    write_json(folder, 'water.json', data)
    encoded = build_slope_grid.encode_heights(heights, data)
    with open(os.path.join(folder, 'heights.dat'), 'wb') as f:
        f.write(encoded)
    build_terrain.main(os.path.join(folder, 'heights.dat'), os.path.join(folder, 'terrain.pmtiles'),
                       name=terrain_name, attribution=terrain_attribution)
    return len(encoded)


def land_box(box):
    """A `coastline` for `build_basemap.main` of a map with no coast
    (Rovaniemi's): one ring of land, `box` (west, south, east, north),
    anticlockwise as OpenStreetMap draws an island's coast; nothing cut
    open; no edit of its own."""
    def coastline(path):
        west, south, east, north = box
        ring = [(south, west), (south, east), (north, east), (north, west), (south, west)]
        return [ring], 0, None
    return coastline


def _coast_ways(path):
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
    return ways, newest


def _chains(ways):
    """The ways joined end to start: closed rings and open lines, each a
    list of (lat, lon)."""
    starts = {}
    for index, way in enumerate(ways):
        starts.setdefault(way[0][0], []).append(index)
    ends = {way[-1][0] for way in ways}
    used, rings, lines = [False] * len(ways), [], []
    for index in sorted(range(len(ways)), key=lambda i: ways[i][0][0] in ends):
        if used[index]:
            continue
        used[index] = True
        chain = list(ways[index])
        while chain[0][0] != chain[-1][0]:
            following = [n for n in starts.get(chain[-1][0], []) if not used[n]]
            if not following:
                break
            used[following[0]] = True
            chain += ways[following[0]][1:]
        points = [(lat, lon) for _, lat, lon in chain]
        (rings if chain[0][0] == chain[-1][0] else lines).append(points)
    return rings, lines


def _inside(point, box):
    west, south, east, north = box
    return south <= point[0] <= north and west <= point[1] <= east


def _crossing(a, b, box):
    """Where the segment from `a` (inside `box`) to `b` (outside) leaves it."""
    west, south, east, north = box
    best = 1.0
    for value, index in ((south, 0), (north, 0), (west, 1), (east, 1)):
        delta = b[index] - a[index]
        if delta:
            t = (value - a[index]) / delta
            if 0 <= t < best:
                other = a[1 - index] + t * (b[1 - index] - a[1 - index])
                low, high = (west, east) if index == 0 else (south, north)
                if low - 1e-12 <= other <= high + 1e-12:
                    best = t
    return (a[0] + best * (b[0] - a[0]), a[1] + best * (b[1] - a[1]))


def _clip(line, box):
    """The pieces of an open line inside `box`, each from where it comes in
    to where it goes out, those ends on the box's edge."""
    pieces, piece = [], None
    for a, b in zip(line, line[1:]):
        if _inside(a, box) and piece is None:
            piece = [a]
        if piece is not None:
            if _inside(b, box):
                piece.append(b)
            else:
                piece.append(_crossing(a, b, box))
                pieces.append(piece)
                piece = None
        elif _inside(b, box):
            piece = [_crossing(b, a, box), b]
    if piece is not None:
        pieces.append(piece)
    return pieces


def _around(point, box):
    """How far round the box's edge `point` is, anticlockwise from its
    south-west corner (east along the south, north up the east, west
    along the north, south down the west), in degrees."""
    west, south, east, north = box
    width, height = east - west, north - south
    lat, lon = point
    if abs(lat - south) < 1e-9:
        return lon - west
    if abs(lon - east) < 1e-9:
        return width + lat - south
    if abs(lat - north) < 1e-9:
        return width + height + east - lon
    return 2 * width + height + north - lat


def coast_in_box(box):
    """A `coastline` for `build_basemap.main` and the water grid of a map
    whose coast the extract cuts open (Fukuoka's: Kyushu's shore runs out
    of the extract on every side): the closed rings as they are, and each
    open line cut to `box` (west, south, east, north) and closed along the
    box's edge, anticlockwise from where it goes out to where the next one
    comes in, so the land stays on the left as OpenStreetMap draws it (the
    rule of osmcoastline's, written here). Returns the rings of (lat, lon),
    how many lines could not be closed (none) and the newest edit."""
    west, south, east, north = box
    corners = [(south, east), (north, east), (north, west), (south, west)]
    width, height = east - west, north - south
    corner_at = [width, width + height, 2 * width + height, 2 * (width + height)]

    def coastline(path):
        ways, newest = _coast_ways(path)
        rings, lines = _chains(ways)
        pieces = [piece for line in lines for piece in _clip(line, box) if len(piece) >= 2]
        perimeter = 2 * (width + height)
        used = [False] * len(pieces)
        for first in range(len(pieces)):
            if used[first]:
                continue
            ring, current = [], first
            while not used[current]:
                used[current] = True
                ring += pieces[current]
                out = _around(pieces[current][-1], box)
                # The next piece coming in, anticlockwise from here.
                ahead = min(range(len(pieces)), key=lambda n: (_around(pieces[n][0], box) - out) % perimeter)
                into = _around(pieces[ahead][0], box)
                distance = (into - out) % perimeter
                for corner, at in sorted(zip(corners, corner_at), key=lambda c: (c[1] - out) % perimeter):
                    if 0 < (at - out) % perimeter < distance:
                        ring.append(corner)
                current = ahead
            ring.append(ring[0])
            rings.append(ring)
        if pieces:
            print(f'coastline: {len(lines)} open lines, {len(pieces)} pieces in the box closed along its edge', flush=True)
        return rings, 0, newest
    return coastline
