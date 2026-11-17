#!/usr/bin/env python3
"""What covers Hong Kong's ground, from the Planning Department's Raster
Grids on Land Utilization (10 m, 2025), on the pack's water grid, as the
pack's `landcover.dat` (ARCHITECTURE decision 835): the form and the eight
covers of Taiwan's `taiwan_landcover.dat` (decision 811,
`tools/worldcover/build_landcover_grid.py`), so the 3D map tints Hong
Kong's countryside and plants its woods as it does Taiwan's.

    pip install numpy pillow
    python3 -I tools/hk-map/build_hk_landcover.py fetch /tmp/hk/landuse
    python3 -I tools/hk-map/build_hk_landcover.py build /tmp/hk/landuse \\
        RailwayGameApp/Resources/MapPacks/hongkong

The data: "2025 Raster Grids on Land Utilization", Planning Department,
Government of the Hong Kong SAR, via DATA.GOV.HK and the CSDI Portal
(dataset `pland_rcd_1754559265139_25057`; DATA.GOV.HK terms: free to use,
reproduce and distribute with the source acknowledged, not to be resold).
Its GeoTIFF's download link (`.../csdi-webpage/download/common/<hash>`)
answers 403 from the cloud, as the other CSDI downloads did (README step
7), so `fetch` reads the same raster through the portal's own map
service: `MapServer/export` at its native 10 m on the HK1980 Grid
(EPSG:2326), in four 3,200 × 2,400 tiles from E 800,000 N 800,000. The
service draws the land use codes as a grey stretch; `fetch` asks the
service's `identify` for the code of one pixel of every grey it drew and
writes that table (`calibration.json`) beside the tiles. The stretch
draws codes 0, 1 and 2 (the sea, private and public housing) the same
black; `build` tells the sea from the housing by where the black lies
(below).

The codes, read from the 2025 raster (no dictionary is published with
it): each code's area and places matched against the Planning
Department's land use classes, in their order (Plover Cove Reservoir 91,
Victoria Park 32, Chek Lap Kok's runways 43, Tai Mo Shan's radar station
31, Tai O 61 ...):

     1 private residential  2 public residential  3 rural settlement
    11 commercial          21 industrial          22 industrial estates
    23 warehouse, open storage                    31 government, institutions
    32 open space, recreation                     41 roads, transport
    42 railways  43 airport  44 port  51 cemeteries  52 utilities
    53 vacant land, construction                  54 others
    61 agricultural land   62 fish ponds, gei wais
    71 woodland  72 shrubland  73 grassland  74 mangrove, swamp
    81 badland  83 rocky shore  91 reservoirs  92 streams, nullahs
     0 the sea (and the land outside Hong Kong)

folded into the game's eight (``FOLD``): woodland the forest; shrubland,
grassland; farms; every built use the built-up land (the city's lots and
OpenStreetMap's parks and land cover draw that ground), but vacant land
and construction sites bare, as badland and rocky shore are; reservoirs
and streams water (OpenStreetMap's water lies on them); mangroves, swamps,
fish ponds and gei wais wetland (Mai Po and the ponds along the border).

The black: the sea is the black that reaches the tiles' edge through
black; the rest (housing, enclosed by roads and other uses) is built-up.
A housing estate whose black touches the sea's is taken for sea, which
the map draws the same: neither built-up nor unknown land is tinted.

Each cell of the water grid (`water.json`, 1.875″, some 54 × 58 m) takes
the cover most of its 6 × 6 points are (each point's middle taken from
WGS 84 to the HK1980 Grid as `build_hk_ground_grids.hk80_grid` takes it,
then the pixel it falls in); the sea's points do not vote, so a shore
cell is what its land is. Then the most common of the 3 × 3 cells round
it, as Taiwan's (`build_landcover_grid.majority`), and the water grid's
water is 0. Written in the heights file's form under `TWLC`, the form's
name (GamePresentation's `LandCoverGrid`).
"""
import hashlib
import json
import os
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, os.path.join(HERE, '..', 'worldcover'))
from build_hk_ground_grids import hk80_grid  # noqa: E402
import build_hk_mtr  # noqa: E402
from build_slope_grid import encode_heights, water_mask  # noqa: E402
from build_landcover_grid import majority, COVERS  # noqa: E402

DATASET = 'pland_rcd_1754559265139_25057'
PAGE = f'https://portal.csdi.gov.hk/geoportal/?datasetId={DATASET}'
SERVICE = f'https://portal.csdi.gov.hk/server/rest/services/common/{DATASET}/MapServer'
# The raster: 10 m pixels from its north-west corner.
WEST, SOUTH, EAST, NORTH, PIXEL = 800_000, 800_000, 864_000, 848_000, 10
TILE_W, TILE_H = 3_200, 2_400

# Land use code → the game's cover (the module's docstring; 0 unknown,
# 1 forest, 2 shrubland, 3 grassland, 4 cropland, 5 built-up, 6 bare,
# 7 water, 8 wetland).
FOLD = {1: 5, 2: 5, 3: 5, 11: 5, 21: 5, 22: 5, 23: 5, 31: 5, 32: 5, 41: 5, 42: 5, 43: 5, 44: 5,
        51: 5, 52: 5, 53: 6, 54: 5, 61: 4, 62: 8, 71: 1, 72: 2, 73: 3, 74: 8,
        81: 6, 82: 6, 83: 6, 91: 7, 92: 7}
# The code the stretch draws black: the sea, or housing (1, 2).
BLACK = 0
POINTS = 6

# Places the file must know (latitude, longitude, cover).
CHECKS = [
    (22.400, 114.300, 1, 'Sai Kung country park'),
    (22.465, 114.255, 0, 'Plover Cove Reservoir'),  # OpenStreetMap's water
    (22.2516, 113.9200, 3, 'Lantau Peak'),
    (22.252, 113.862, 4, 'Tai O'),
    (22.3193, 114.1694, 5, 'Mong Kok'),
    (22.310, 113.915, 5, 'Chek Lap Kok'),
]


def tiles():
    for x in range(WEST, EAST, TILE_W * PIXEL):
        for y in range(SOUTH, NORTH, TILE_H * PIXEL):
            yield x, y


def fetch(folder):
    from PIL import Image  # Only for the service's PNGs.
    os.makedirs(folder, exist_ok=True)
    greys = {}
    for x, y in tiles():
        path = os.path.join(folder, f'tile_{x}_{y}.png')
        if not os.path.exists(path):
            url = (f'{SERVICE}/export?bbox={x},{y},{x + TILE_W * PIXEL},{y + TILE_H * PIXEL}&bboxSR=2326&imageSR=2326'
                   f'&size={TILE_W},{TILE_H}&format=png32&transparent=false&f=image')
            urllib.request.urlretrieve(url, path)
        grey = np.array(Image.open(path).convert('L'))
        for g in np.unique(grey).tolist():
            if g not in greys:
                r, c = np.argwhere(grey == g)[0]
                greys[g] = (x + PIXEL * int(c) + PIXEL // 2, y + TILE_H * PIXEL - PIXEL * int(r) - PIXEL // 2)
    codes = {}
    for g, (e, n) in sorted(greys.items()):
        url = (f'{SERVICE}/identify?geometry={e},{n}&geometryType=esriGeometryPoint&sr=2326&layers=all&tolerance=0'
               f'&mapExtent={e - 500},{n - 500},{e + 500},{n + 500}&imageDisplay=100,100,96&returnGeometry=false&f=json')
        found = json.load(urllib.request.urlopen(url, timeout=60))['results']
        codes[g] = int(found[0]['attributes']['Stretch.Pixel Value']) if found else BLACK
    record = {'dataset': DATASET, 'page': PAGE, 'service': SERVICE, 'greyToCode': {str(k): v for k, v in codes.items()},
              'tiles': {os.path.basename(p): hashlib.sha256(open(p, 'rb').read()).hexdigest()
                        for p in sorted(os.path.join(folder, f'tile_{x}_{y}.png') for x, y in tiles())}}
    with open(os.path.join(folder, 'calibration.json'), 'w') as f:
        json.dump(record, f, indent=1)
    print(f'{folder}: {len(record["tiles"])} tiles, {len(codes)} greys: {codes}')


def spread(mask, seed):
    """The cells of `mask` joined to `seed` through `mask` (4-neighbours),
    by whole runs along rows and columns in turn."""
    filled = seed & mask
    while True:
        before = int(filled.sum())
        for flip in (False, True):
            m = mask.T if flip else mask
            f = filled.T if flip else filled
            flat_m = np.ascontiguousarray(m).ravel()
            starts = flat_m.copy()
            starts[1:] &= ~flat_m[:-1]
            starts[::m.shape[1]] = flat_m[::m.shape[1]]
            run = np.cumsum(starts) * flat_m
            seeded = np.zeros(int(run.max()) + 1, dtype=bool)
            seeded[run[np.ascontiguousarray(f).ravel() & flat_m]] = True
            seeded[0] = False
            out = seeded[run].reshape(m.shape)
            filled = out.T if flip else out
        if int(filled.sum()) == before:
            return filled


def raster(folder):
    """The whole raster's covers (``FOLD``), the sea 0."""
    from PIL import Image
    record = json.load(open(os.path.join(folder, 'calibration.json')))
    for name, digest in record['tiles'].items():
        if hashlib.sha256(open(os.path.join(folder, name), 'rb').read()).hexdigest() != digest:
            sys.exit(f'{name}: not the tile calibration.json read')
    lookup = np.zeros(256, dtype=np.uint8)
    black = np.zeros(256, dtype=bool)
    for grey, code in record['greyToCode'].items():
        if code == BLACK:
            black[int(grey)] = True
        elif code not in FOLD:
            sys.exit(f'land use code {code}: not in FOLD (a new class: fold it)')
        else:
            lookup[int(grey)] = FOLD[code]
    rows, columns = (NORTH - SOUTH) // PIXEL, (EAST - WEST) // PIXEL
    cover = np.zeros((rows, columns), dtype=np.uint8)
    dark = np.zeros((rows, columns), dtype=bool)
    for x, y in tiles():
        grey = np.array(Image.open(os.path.join(folder, f'tile_{x}_{y}.png')).convert('L'))
        r0, c0 = (NORTH - y) // PIXEL - TILE_H, (x - WEST) // PIXEL
        cover[r0:r0 + TILE_H, c0:c0 + TILE_W] = lookup[grey]
        dark[r0:r0 + TILE_H, c0:c0 + TILE_W] = black[grey]
    edge = np.zeros_like(dark)
    edge[0, :] = edge[-1, :] = True
    edge[:, 0] = edge[:, -1] = True
    sea = spread(dark, edge)
    cover[dark & ~sea] = 5
    return cover, int((dark & ~sea).sum()), int(sea.sum())


def build(folder, pack):
    cover10, housing, sea = raster(folder)
    data = json.load(open(os.path.join(pack, 'water.json')))
    rows, columns, step = data['rows'], data['columns'], data['cellDegrees']
    north, west = data['north'], data['west']
    counts = np.zeros((COVERS, rows, columns), dtype=np.uint16)
    offsets = (np.arange(POINTS) + 0.5) / POINTS
    column_index = np.arange(columns)
    for r in range(rows):
        lat = north - (r + offsets[:, None]) * step                # POINTS × 1
        lon = west + (column_index[None, :] + offsets[:, None]) * step  # POINTS × columns
        la = np.repeat(lat, POINTS * columns).reshape(POINTS, POINTS, columns)
        lo = np.broadcast_to(lon[None, :, :], (POINTS, POINTS, columns))
        e, n = hk80_grid(la, lo)
        pr = np.floor((NORTH - n) / PIXEL).astype(np.int64)
        pc = np.floor((e - WEST) / PIXEL).astype(np.int64)
        inside = (pr >= 0) & (pr < cover10.shape[0]) & (pc >= 0) & (pc < cover10.shape[1])
        values = np.zeros(pr.shape, dtype=np.uint8)
        values[inside] = cover10[pr[inside], pc[inside]]
        cells = np.broadcast_to(column_index, values.shape)
        for k in range(1, COVERS):
            hit = values == k
            if hit.any():
                np.add.at(counts[k, r], cells[hit], 1)
    raw = np.argmax(counts, axis=0)
    raw[counts.sum(axis=0) == 0] = 0
    raw[water_mask(data)] = 0
    cover = majority(raw)

    names = ['unknown', 'forest', 'shrubland', 'grassland', 'cropland', 'built-up', 'bare', 'water', 'wetland']
    failed = []
    for lat, lon, want, place in CHECKS:
        got = int(cover[int((north - lat) / step), int((lon - west) / step)])
        if got != want:
            failed.append(f'{place}: {names[got]}, not {names[want]}')
    if failed:
        sys.exit('; '.join(failed))

    encoded = encode_heights(cover.astype(np.int16), data, magic=b'TWLC')
    with open(os.path.join(pack, 'landcover.dat'), 'wb') as f:
        f.write(encoded)
    build_hk_mtr.write_manifest(pack)

    record = os.path.join(HERE, 'hk_sources.json')
    with open(record, encoding='utf-8') as f:
        sources = json.load(f)
    calibration = json.load(open(os.path.join(folder, 'calibration.json')))
    sources['inputs']['2025 Raster Grids on Land Utilization (landcover.dat)'] = {
        'dataset': DATASET, 'page': PAGE, 'read through': SERVICE + '/export and /identify, 10 m, EPSG:2326',
        'tiles': calibration['tiles'], 'greyToCode': calibration['greyToCode'], 'read': '2026-11-17',
        'licence': 'DATA.GOV.HK Terms and Conditions of Use; Planning Department, Government of the HKSAR',
    }
    with open(record, 'w', encoding='utf-8') as f:
        json.dump(sources, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')

    total = int((cover > 0).sum())
    shares = ', '.join(f'{names[k]} {100 * int((cover == k).sum()) / max(total, 1):.1f} %' for k in range(1, COVERS))
    print(f'{pack}/landcover.dat: 10 m black: {housing} px housing, {sea} px sea; '
          f'{total} cells of land with a cover ({shares}); {len(encoded)} bytes')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'fetch':
        fetch(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == 'build':
        build(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
