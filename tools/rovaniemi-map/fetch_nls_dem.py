#!/usr/bin/env python3
"""The National Land Survey of Finland's 10 m elevation model over the
Rovaniemi map (OVERSEAS-DEM), for `build_rovaniemi_ground_grids.py`.

    python3 -I tools/rovaniemi-map/fetch_nls_dem.py /tmp/rv/nls

Maanmittauslaitos, Korkeusmalli 10 m (the bare ground, from the laser
survey; ETRS-TM35FIN, heights in N2000, float32 metres, 24 km × 12 km
sheets of 2,400 × 1,200 samples). The Survey's own file service asks for an
API key, so the sheets come from Kapsi's mirror of it
(https://kartat.kapsi.fi/, the sheets of 08/2023); CSC's Paituli mirror
(https://www.nic.funet.fi/index/geodata/mml/dem10m/2019/) has the 2019
ones under the same names. Each sheet is saved under its name; one at a
time.

Licence: the National Land Survey's open data licence, Creative Commons
Attribution 4.0, with the credit "National Land Survey of Finland,
Elevation model 10 m, 08/2023".

The sheet division (TM35): a letter is a row of 96 km from 6,570,000 m
north (K, L, M, N, P … X, no O) and a digit a column of 192 km from
-76,000 m east (2 …); each further digit quarters the sheet (1 south-west,
2 north-west, 3 south-east, 4 north-east), down to 24 km × 12 km.
"""
import math
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
import build_rovaniemi_rail  # noqa: E402

URL = 'https://kartat.kapsi.fi/files/korkeusmalli/hila_10m/etrs-tm35fin-n2000/{a}/{b}/{name}.tif'
ROWS = 'KLMNPQRSTUVWX'
ROW_SOUTH, COLUMN_WEST, FIRST_COLUMN = 6_570_000, -76_000, 2
SHEET_EAST, SHEET_NORTH = 24_000, 12_000
# Past the extent, in degrees: the grid reaches to whole population cells
# beyond it.
MARGIN = 0.02
TM35_MERIDIAN, TM35_SCALE, TM35_EASTING = 27.0, 0.9996, 500_000.0


def tm35(latitudes, longitudes):
    """ETRS-TM35FIN eastings and northings of places in degrees (numpy
    arrays): `build_slope_grid.tm2`'s series on the same ellipsoid
    (GRS 80), with this projection's meridian, scale and false easting."""
    import build_slope_grid
    easting, northing = build_slope_grid.tm2(latitudes, longitudes, TM35_MERIDIAN)
    ratio = TM35_SCALE / build_slope_grid.TM2_SCALE
    return TM35_EASTING + (easting - build_slope_grid.TM2_EASTING) * ratio, northing * ratio


def sheet(east, north):
    """The name of the 24 km × 12 km sheet that holds a point, and its
    west and north edges."""
    row, column = int((north - ROW_SOUTH) // 96_000), int((east - COLUMN_WEST) // 192_000)
    name = ROWS[row] + str(column + FIRST_COLUMN)
    west, south = COLUMN_WEST + column * 192_000, ROW_SOUTH + row * 96_000
    width, height = 192_000, 96_000
    for _ in range(3):
        width, height = width // 2, height // 2
        right, upper = east >= west + width, north >= south + height
        name += str(1 + (2 if right else 0) + (1 if upper else 0))
        west, south = west + (width if right else 0), south + (height if upper else 0)
    return name, west, south + height


def sheets(extent=None):
    """The sheets that hold the extent and its margin: {name: (west, north)}."""
    import numpy as np
    e = extent or build_rovaniemi_rail.EXTENT
    latitudes = np.linspace(e['south'] - MARGIN, e['north'] + MARGIN, 60)
    longitudes = np.linspace(e['west'] - MARGIN, e['east'] + MARGIN, 240)
    lat, lon = np.meshgrid(latitudes, longitudes, indexing='ij')
    east, north = tm35(lat, lon)
    found = {}
    # The sheets' own lattice: 24 km from COLUMN_WEST, 12 km from ROW_SOUTH.
    xs = np.unique(((east - COLUMN_WEST) // SHEET_EAST).astype(int))
    ys = np.unique(((north - ROW_SOUTH) // SHEET_NORTH).astype(int))
    for x in range(xs.min(), xs.max() + 1):
        for y in range(ys.min(), ys.max() + 1):
            name, west, top = sheet(COLUMN_WEST + x * SHEET_EAST + 1, ROW_SOUTH + y * SHEET_NORTH + 1)
            found[name] = (west, top)
    return found


def main(folder):
    os.makedirs(folder, exist_ok=True)
    wanted = sheets()
    for index, name in enumerate(sorted(wanted), start=1):
        path = os.path.join(folder, name + '.tif')
        if os.path.exists(path):
            continue
        url = URL.format(a=name[:2], b=name[:3], name=name)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(url, timeout=120) as response:
                    data = response.read()
                with open(path, 'wb') as f:
                    f.write(data)
                break
            except (urllib.error.URLError, OSError):
                time.sleep(2 ** attempt)
        else:
            sys.exit(f'{name}: no answer after 4 tries')
        print(f'{index}/{len(wanted)} {name} {math.ceil(len(data) / 1e6)} MB', flush=True)
        time.sleep(0.5)
    print(f'{len(wanted)} sheets in {folder}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
