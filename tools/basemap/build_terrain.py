#!/usr/bin/env python3
"""Taiwan's relief for the base map (ARCHITECTURE decision 151): the game's
own ground heights as terrain tiles MapLibre shades the hills with
(`Resources/BaseMap/taiwan_terrain.pmtiles`, the style's `hillshade`).

    python3 tools/basemap/build_terrain.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_heights.dat \\
        RailwayGameApp/Resources/BaseMap/taiwan_terrain.pmtiles

The heights are the game's (`taiwan_heights.dat`, decision 124, from the
Copernicus DEM by `tools/real-world-population/build_slope_grid.py`), so the
map's shading falls where the game's ground rises: where a line runs on an
embankment, in a cutting or in a tunnel. The tiles are as the `Railway/`
reference's terrain (`rail-3d/integration/map3d.js`: a `raster-dem` source,
Terrarium-encoded, 512 pixels, under a `hillshade` layer lit from 315°):
each pixel's height in metres is red × 256 + green + blue / 256 − 32768,
as PNG (written here with the standard library and numpy). Zooms 0 to
MAX_ZOOM, whose 512-pixel tiles (some 70 m a pixel in Taiwan at zoom 10)
are about as fine as the heights' 1.875″ cells (some 58 m); MapLibre draws them
larger past it. A pixel takes the heights bilinearly at its middle, the
mean of SAMPLES × SAMPLES such points below MAX_ZOOM so the hills do not
flicker; only tiles with land in them are written.
"""
import os
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_basemap import tile_id, unproject, write_pmtiles  # noqa: E402

SIZE = 512
MAX_ZOOM = 10
SAMPLES = 4


def read_heights(path):
    """The heights grid (decision 124's format): its corner, cell size and
    the heights, an int16 array of rows × columns."""
    data = open(path, 'rb').read()
    assert data[:4] == b'TWHG' and struct.unpack_from('<HH', data, 4) == (1, 0), 'not a heights file'
    north, west, cell = struct.unpack_from('<ddd', data, 8)
    rows, columns = struct.unpack_from('<II', data, 32)
    offsets = struct.unpack_from(f'<{rows + 1}I', data, 40)
    start = 40 + 4 * (rows + 1)
    grid = np.zeros((rows, columns), np.int16)
    for row in range(rows):
        body = data[start + offsets[row]:start + offsets[row + 1]]
        out, height, i, n = [], 0, 0, len(body)

        def varint():
            nonlocal i
            value = shift = 0
            while True:
                byte = body[i]
                i += 1
                value |= (byte & 0x7F) << shift
                if byte < 0x80:
                    return value
                shift += 7
        while i < n:
            value = varint()
            if value == 0:
                out.extend([height] * varint())
            else:
                height += (value >> 1) ^ -(value & 1)
                out.append(height)
        assert len(out) == columns, f'row {row} has {len(out)} heights'
        grid[row] = out
    return north, west, cell, grid


def sample(grid, north, west, cell, lat, lon):
    """The heights at (lat, lon) arrays, bilinear between cells' middles;
    0 (the sea) off the grid."""
    rows, columns = grid.shape
    r = (north - lat) / cell - 0.5
    c = (lon - west) / cell - 0.5
    r0, c0 = np.floor(r).astype(np.int64), np.floor(c).astype(np.int64)
    fr, fc = r - r0, c - c0
    out = np.zeros(lat.shape, np.float64)
    for dr, dc, w in ((0, 0, (1 - fr) * (1 - fc)), (0, 1, (1 - fr) * fc), (1, 0, fr * (1 - fc)), (1, 1, fr * fc)):
        rr, cc = r0 + dr, c0 + dc
        inside = (rr >= 0) & (rr < rows) & (cc >= 0) & (cc < columns)
        values = np.zeros(lat.shape, np.float64)
        values[inside] = grid[rr[inside], cc[inside]]
        out += w * values
    return out


def tile_heights(grid, north, west, cell, z, x, y):
    """The tile's SIZE × SIZE heights in metres."""
    k = 1 if z == MAX_ZOOM else SAMPLES
    n = SIZE * (1 << z) * k
    i = (np.arange(SIZE * k) + 0.5)
    px = (x * SIZE * k + i) / n
    py = (y * SIZE * k + i) / n
    lon = 360 * (px - 0.5)
    lat = np.degrees(np.arctan(np.sinh(np.pi * (1 - 2 * py))))
    heights = sample(grid, north, west, cell, lat[:, None] * np.ones((1, SIZE * k)), np.ones((SIZE * k, 1)) * lon[None, :])
    return heights.reshape(SIZE, k, SIZE, k).mean(axis=(1, 3))


def terrarium_png(heights):
    """The heights as a Terrarium PNG (RGB, 8 bits, each row filtered Up)."""
    value = np.clip(np.round(heights) + 32768, 0, 65535).astype(np.uint32)
    rgb = np.zeros((SIZE, SIZE, 3), np.uint8)
    rgb[..., 0] = value >> 8
    rgb[..., 1] = value & 0xFF
    raw = rgb.reshape(SIZE, SIZE * 3)
    up = np.vstack([raw[:1], (raw[1:].astype(np.int16) - raw[:-1].astype(np.int16)) % 256]).astype(np.uint8)
    rows = np.hstack([np.full((SIZE, 1), 2, np.uint8), up])
    rows[0, 0] = 0
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF)
    header = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows.tobytes(), 9)) + chunk(b'IEND', b'')


def main(heights_path, out):
    north, west, cell, grid = read_heights(heights_path)
    rows, columns = grid.shape
    land = grid > 0
    south, east = north - rows * cell, west + columns * cell
    print(f'{rows} × {columns} heights, {int(land.sum())} cells above 0 m, {grid.min()}–{grid.max()} m', flush=True)
    # The rows and columns with any height above 0, for which tiles to cut.
    land_rows, land_columns = np.flatnonzero(land.any(axis=1)), np.flatnonzero(land.any(axis=0))
    top, bottom = north - land_rows[0] * cell, north - (land_rows[-1] + 1) * cell
    left, right = west + land_columns[0] * cell, west + (land_columns[-1] + 1) * cell

    tiles = []
    for z in range(MAX_ZOOM + 1):
        n = 1 << z
        def tx(lon):
            return int((lon / 360 + 0.5) * n)
        def ty(lat):
            s = np.sin(np.radians(lat))
            return int((0.5 - np.log((1 + s) / (1 - s)) / (4 * np.pi)) * n)
        count = 0
        for x in range(tx(left), tx(right) + 1):
            # Columns of the grid this tile column covers.
            (w, _), (e, _) = unproject(x / n, 0), unproject((x + 1) / n, 0)
            c0, c1 = max(0, int((w - west) / cell)), min(columns, int((e - west) / cell) + 1)
            if c0 >= c1 or not land[:, c0:c1].any():
                continue
            for y in range(ty(top), ty(bottom) + 1):
                (_, nl), (_, sl) = unproject(0, y / n), unproject(0, (y + 1) / n)
                r0, r1 = max(0, int((north - nl) / cell)), min(rows, int((north - sl) / cell) + 1)
                if r0 >= r1 or not land[r0:r1, c0:c1].any():
                    continue
                tiles.append((tile_id(z, x, y), terrarium_png(tile_heights(grid, north, west, cell, z, x, y))))
                count += 1
        print(f'zoom {z}: {count} tiles', flush=True)
    metadata = {
        'name': 'Taiwan terrain',
        'format': 'png',
        'encoding': 'terrarium',
        'tileSize': SIZE,
        'attribution': 'Copernicus DEM © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018',
        'description': f'The game\'s ground heights ({os.path.basename(heights_path)}, decision 124), Terrarium-encoded',
    }
    entries, contents = write_pmtiles(out, tiles, metadata, (west, south, east, north), ((west + east) / 2, (north + south) / 2, 7),
                                      tile_type=2, tile_compression=1, zooms=(0, MAX_ZOOM))
    print(f'{out}: {len(tiles)} tiles, {entries} directory entries, {os.path.getsize(out)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
