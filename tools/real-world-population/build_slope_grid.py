#!/usr/bin/env python3
"""Mark Taiwan's steep slopes on the water file's grid, and add them to the
app's `Resources/RealWorld/taiwan_water.json` as its `steep` (ARCHITECTURE
decision 115); with a fourth argument, also write the ground's height on
the same grid, the app's `Resources/RealWorld/taiwan_heights.dat`
(decision 124).

    python3 tools/real-world-population/build_slope_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        copernicus-dem/ \\
        RailwayGameApp/Resources/RealWorld/taiwan_water.json \\
        RailwayGameApp/Resources/RealWorld/taiwan_heights.dat

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

The heights are the same median heights, rounded to whole metres, but
taken with the water in (ARCHITECTURE decision 132): water within SHORE
cells of dry land (rivers, lakes, the shore) is at its surface, no lower
than 0; the open sea, the mainland across it (water in the OpenStreetMap
extract of Taiwan) and anywhere no tile reaches are 0 (the sea). The file is little-endian:
the magic `TWHG`, version 1 (u16) and 0 (u16); the grid's north, west and
cell size in degrees (f64 each) and its rows and columns (u32 each); then
rows + 1 offsets (u32) from the start of the rows' bytes, row by row, the
last the end. A row is its heights from the west, each the one before it
(0 before the first) plus a difference, as varints (7 bits a byte, the low
first, the high bit set on every byte but the last): a difference d other
than 0 is (d << 1) ^ (d >> 31), never 0; a 0 is followed by how many
differences of 0 there are in a row. About 12 MB, and each row reads alone
(GamePresentation's `HeightGrid`).
"""
import glob
import json
import math
import os
import struct
import sys

import numpy as np

SLOPE = 0.30
# How far from dry land water keeps the DEM's height in the heights file,
# in cells (some 450 m): rivers and lakes, not the open sea.
SHORE = 8
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


MOI_URL = 'https://download.mapterhorn.com/sources/aatw.tar'
MOI_MD5 = '1785de52c6ccf6469cc67c8547762c4b'
MOI_BYTES = 150_374_400
MOI_NO_DATA = -32767.0
# TWD97 / TM2 zone 121 (EPSG:3826), the DTM's own grid: GRS80, central
# meridian 121° E, scale 0.9999, false easting 250,000 m.
TM2_A = 6_378_137.0
TM2_INVERSE_FLATTENING = 298.257222101
TM2_MERIDIAN = 121.0
TM2_SCALE = 0.9999
TM2_EASTING = 250_000.0


def moi_dtm(path):
    """The Ministry of the Interior's 20 m DTM (decision 943): its heights
    (NaN where it has none: the sea, and everywhere off its sheet), the
    easting of its west edge and the northing of its north edge, in TWD97
    TM2 metres, and its cell size. `path` is the DTM's GeoTIFF (`tw.tif`);
    where there is none yet, Mapterhorn's copy of the source archive is
    downloaded beside it, checked against its size and MD5, and unpacked."""
    if not os.path.exists(path):
        import hashlib
        import tarfile
        import urllib.request
        folder = os.path.dirname(os.path.abspath(path))
        os.makedirs(folder, exist_ok=True)
        archive = os.path.join(folder, 'aatw.tar')
        if not os.path.exists(archive):
            print(f'downloading {MOI_URL} ({MOI_BYTES} bytes)…', file=sys.stderr)
            urllib.request.urlretrieve(MOI_URL, archive + '.part')
            os.replace(archive + '.part', archive)
        digest = hashlib.md5()
        with open(archive, 'rb') as file:
            for chunk in iter(lambda: file.read(1 << 20), b''):
                digest.update(chunk)
        if os.path.getsize(archive) != MOI_BYTES or digest.hexdigest() != MOI_MD5:
            sys.exit(f'{archive}: not the archive this tool knows (size or MD5 differs)')
        with tarfile.open(archive) as tar:
            member = tar.getmember('files/tw.tif')
            with tar.extractfile(member) as source, open(path, 'wb') as target:
                for chunk in iter(lambda: source.read(1 << 20), b''):
                    target.write(chunk)
    import tifffile  # Only for the DEM's tiles.
    with tifffile.TiffFile(path) as file:
        page = file.pages[0]
        scale = page.tags['ModelPixelScaleTag'].value
        tie = page.tags['ModelTiepointTag'].value
        parameters = page.tags['GeoDoubleParamsTag'].value
        # The sheet is the grid `tm2` works in, or the heights would land
        # somewhere else without a word.
        assert tuple(parameters[1:4]) == (TM2_MERIDIAN, TM2_SCALE, TM2_EASTING), f'{path}: not TWD97 TM2 zone 121'
        assert scale[0] == scale[1] and tie[:3] == (0.0, 0.0, 0.0), f'{path}: not a north-up grid'
        heights = page.asarray().astype(np.float32)
    heights[heights == MOI_NO_DATA] = np.nan
    return heights, tie[3], tie[4], scale[0]


def tm2(latitudes, longitudes):
    """TWD97 TM2 eastings and northings of places in degrees (Krüger's
    series to the fourth order of the third flattening: under a millimetre
    across Taiwan)."""
    f = 1 / TM2_INVERSE_FLATTENING
    n = f / (2 - f)
    radius = TM2_A / (1 + n) * (1 + n ** 2 / 4 + n ** 4 / 64)
    alpha = (
        n / 2 - 2 * n ** 2 / 3 + 5 * n ** 3 / 16 + 41 * n ** 4 / 180,
        13 * n ** 2 / 48 - 3 * n ** 3 / 5 + 557 * n ** 4 / 1440,
        61 * n ** 3 / 240 - 103 * n ** 4 / 140,
        49561 * n ** 4 / 161280,
    )
    e = math.sqrt(f * (2 - f))
    phi = np.radians(latitudes)
    lam = np.radians(longitudes - TM2_MERIDIAN)
    sine = np.sin(phi)
    t = np.sinh(np.arctanh(sine) - e * np.arctanh(e * sine))
    xi = np.arctan2(t, np.cos(lam))
    eta = np.arctanh(np.sin(lam) / np.sqrt(1 + t * t))
    northing = xi.copy()
    easting = eta.copy()
    for j, a in enumerate(alpha, start=1):
        northing = northing + a * np.sin(2 * j * xi) * np.cosh(2 * j * eta)
        easting = easting + a * np.cos(2 * j * xi) * np.sinh(2 * j * eta)
    return TM2_EASTING + TM2_SCALE * radius * easting, TM2_SCALE * radius * northing


def moi_on_grid(data, path):
    """The DTM's height at each grid cell (NaN where it has none): the mean
    of the 3 × 3 of its 20 m cells round the grid cell's middle, some 60 m
    a side, which is the grid cell's own ground (58 × 53 m); of those of
    the nine it has, at the shore and the sheet's edge."""
    heights, west_edge, north_edge, size = moi_dtm(path)
    padded = np.pad(heights, 1, constant_values=np.nan)
    total = np.zeros_like(heights)
    count = np.zeros(heights.shape, dtype=np.uint8)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            part = padded[1 + dy:1 + dy + heights.shape[0], 1 + dx:1 + dx + heights.shape[1]]
            known = np.isfinite(part)
            total += np.where(known, part, 0)
            count += known
    mean = np.where(count > 0, total / np.maximum(count, 1), np.nan).astype(np.float32)
    rows, columns = data['rows'], data['columns']
    north, west, step = data['north'], data['west'], data['cellDegrees']
    longitudes = west + (np.arange(columns) + 0.5) * step
    grid = np.full((rows, columns), np.nan, dtype=np.float32)
    band = 256
    for start in range(0, rows, band):
        latitudes = north - (np.arange(start, min(rows, start + band)) + 0.5) * step
        easting, northing = tm2(latitudes[:, None], longitudes[None, :])
        x = np.floor((easting - west_edge) / size).astype(np.int64)
        y = np.floor((north_edge - northing) / size).astype(np.int64)
        inside = (x >= 0) & (x < mean.shape[1]) & (y >= 0) & (y < mean.shape[0])
        values = np.full(x.shape, np.nan, dtype=np.float32)
        values[inside] = mean[y[inside], x[inside]]
        grid[start:start + len(latitudes)] = values
    return grid


def with_moi(data, water, surface, moi):
    """The heights the game's ground is made from (decision 943): the DTM
    where it reaches, and the surface model `surface` elsewhere, and which
    cells are the DTM's.

    Land the DTM leaves out but that joins land it holds (a sheet missing
    in the mountains of Miaoli, made land at a harbour) takes the surface
    model's 3 × 3 median less what the surface model stands above the DTM
    round it (trees and buildings, some 6 m): that difference spreads into
    the gap a cell at a time, each cell the mean of its neighbours that
    have one, so the ground has no step where the two meet. Islands the
    DTM has nothing of (Penghu, Kinmen, Matsu, Green Island, Xiaoliuqiu)
    join none of its land and keep the surface model as it is."""
    has = np.isfinite(moi)
    median = median3(np.nan_to_num(surface, nan=0.0))
    difference = np.where(has, moi - median, 0).astype(np.float32)
    known = has.copy()
    # Where the difference may spread: land and the water by it, not the
    # open sea, so it crosses to no island.
    dry = ~water & np.isfinite(surface)
    open_to = (dry | (water & near(dry, SHORE))) & np.isfinite(surface) & ~has
    rows, columns = known.shape
    while True:
        padded_known = np.pad(known, 1)
        padded = np.pad(difference, 1)
        total = np.zeros_like(difference)
        count = np.zeros(known.shape, dtype=np.uint8)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                part = padded_known[1 + dy:1 + dy + rows, 1 + dx:1 + dx + columns]
                total += np.where(part, padded[1 + dy:1 + dy + rows, 1 + dx:1 + dx + columns], 0)
                count += part
        reached = open_to & ~known & (count > 0)
        if not reached.any():
            break
        difference[reached] = total[reached] / count[reached]
        known |= reached
    return np.where(has, moi, np.where(known, median + difference, surface)).astype(np.float32), has


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


def near(mask, cells):
    """Where `mask` is, or is within `cells` cells of it (a square round
    each), a cell at a time."""
    out = mask.copy()
    for _ in range(cells):
        grown = out.copy()
        grown[1:, :] |= out[:-1, :]
        grown[:-1, :] |= out[1:, :]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        grown[1:, 1:] |= out[:-1, :-1]
        grown[1:, :-1] |= out[:-1, 1:]
        grown[:-1, 1:] |= out[1:, :-1]
        grown[:-1, :-1] |= out[1:, 1:]
        out = grown
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


def varint(value, out):
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)


def encode_heights(heights, data, magic=b'TWHG'):
    """The heights file's bytes (see the module's docstring); another grid
    of whole numbers in the same form under another `magic`."""
    rows, columns = heights.shape
    body = bytearray()
    offsets = [0]
    for row in heights:
        differences = np.diff(row.astype(np.int64), prepend=0)
        # Where each run of equal (zero or not) differences starts.
        zero = differences == 0
        starts = np.flatnonzero(np.concatenate(([True], zero[1:] != zero[:-1])))
        ends = np.append(starts[1:], len(differences))
        for start, end in zip(starts.tolist(), ends.tolist()):
            if zero[start]:
                body.append(0)
                varint(end - start, body)
            else:
                for d in differences[start:end].tolist():
                    varint((d << 1) ^ (d >> 31), body)
        offsets.append(len(body))
    header = magic + struct.pack('<HHdddII', 1, 0, data['north'], data['west'], data['cellDegrees'], rows, columns)
    return header + struct.pack(f'<{len(offsets)}I', *offsets) + bytes(body)


def smoothed(grid, keep):
    """The 3 × 3 median of `grid` (no height counts as 0), but the cells of
    `keep` as they are: a terrain model's cells hold no building or tree
    for the median to take off (decision 943)."""
    filled = np.nan_to_num(grid, nan=0.0)
    smooth = median3(filled)
    if keep is not None:
        smooth[keep] = filled[keep]
    return smooth


def steep_cells(data, water, surface, keep=None):
    """The steep cells of the heights `surface` (NaN where there are none),
    and the heights with the water at 0 they were found on."""
    rows, step = data['rows'], data['cellDegrees']
    # The heights file keeps the DEM's own heights over water (the water's
    # surface, ARCHITECTURE decision 132); the steep slopes are found with
    # water at 0, as they always have been.
    grid = surface.copy()
    grid[water] = 0
    smooth = smoothed(grid, keep)
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
    return (votes >= 5) & ~water & ~np.isnan(grid), grid


def ground_heights(data, water, surface, keep=None):
    """The heights file's whole metres from the heights `surface`."""
    dry = ~water & ~np.isnan(surface)
    level = np.clip(np.rint(smoothed(surface, keep)), -32768, 32767)
    # Water near land (rivers, lakes, the shore) is at its surface, no
    # lower than the sea; the open sea, the mainland across it (which
    # the OpenStreetMap extract of Taiwan leaves as water) and anywhere
    # no tile reaches are the sea, 0.
    inland = water & near(dry, SHORE)
    return np.where(dry, level, np.where(inland & ~np.isnan(surface), np.maximum(level, 0), 0)).astype(np.int16)


COPERNICUS_SOURCE = (
    'Copernicus DEM GLO-30 (GLO-90 where only that is released), (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH '
    '2014-2018 provided under COPERNICUS by the European Union and ESA'
)
MOI_SOURCE = (
    'Ministry of the Interior, 2024 edition of the 20-metre grid digital terrain model of Taiwan (data.gov.tw 169807), '
    'Open Government Data License, version 1.0, where it reaches; elsewhere '
)


def main(water_path, folder, out, heights_out=None, moi_path=None):
    data = json.load(open(water_path))
    rows, step = data['rows'], data['cellDegrees']
    water = water_mask(data)
    surface, count = heights_on_grid(data, folder)
    has = None
    if moi_path:
        # Decision 943: the terrain model where it reaches, the surface
        # model elsewhere; the 3 × 3 median stays over both (without it
        # the DTM's finer hillsides are steep cells 13 % more of the land).
        surface, has = with_moi(data, water, surface, moi_on_grid(data, moi_path))
    steep, grid = steep_cells(data, water, surface)
    data['steep'] = encode(steep)
    data['slopeSource'] = (MOI_SOURCE if moi_path else '') + COPERNICUS_SOURCE
    text = json.dumps(data, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)
    latitudes = data['north'] - (np.arange(rows) + 0.5) * step
    cell_km2 = (step * METRES_PER_DEGREE_LATITUDE / 1000) * (step * METRES_PER_DEGREE_LONGITUDE / 1000 * np.cos(np.radians(latitudes)))
    def km2(mask):
        return round(float((mask.sum(axis=1) * cell_km2).sum()), 1)
    runs = sum((len(numbers) - 1) // 2 for numbers in data['steep'])
    print(f'{out}: {count} tiles; land {km2(~water)} km², steep {km2(steep)} km² ({runs} runs); {len(text)} bytes')
    if has is not None:
        dry = ~water & ~np.isnan(grid)
        print(f'{out}: {int((dry & has).sum())} of {int(dry.sum())} dry cells from the DTM')
    if heights_out:
        dry = ~water & ~np.isnan(grid)
        heights = ground_heights(data, water, surface)
        inland = water & near(dry, SHORE)
        encoded = encode_heights(heights, data)
        open(heights_out, 'wb').write(encoded)
        above = int((inland & (heights > 0)).sum())
        print(f'{heights_out}: {int(dry.sum())} dry cells, {above} water cells above the sea, {int(heights.min())} to {int(heights.max())} m; '
              f'{len(encoded)} bytes')
    return data, steep, grid


if __name__ == '__main__':
    if len(sys.argv) not in (4, 5, 6):
        sys.exit(__doc__)
    main(*sys.argv[1:])
