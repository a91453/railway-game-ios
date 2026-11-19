#!/usr/bin/env python3
"""The Geospatial Information Authority of Japan's elevation tiles over the
Fukuoka map (FUKUOKA-GROUND), for `build_fukuoka_ground.py grids`.

    python3 -I tools/fukuoka-map/fetch_gsi_dem.py /tmp/fk/gsi

GSI's 標高タイル (PNG, https://maps.gsi.go.jp/development/demtile.html):
each 256 × 256 tile of zoom 15 from the 5 m models, the laser survey's
first (dem5a), then the photogrammetric ones (dem5b, dem5c), and the 10 m
model (dem_png, DEM10B, zoom 14) where none of them has the tile. Each tile is
saved as `<layer>_<z>_<x>_<y>.png`; a tile GSI does not have (404, the sea)
as nothing. Asks one tile at a time, as GSI asks of automated clients.

Licence: 国土地理院コンテンツ利用規約 (compatible with CC BY 4.0), with the
credit 「国土地理院の標高タイルを加工して作成」.
"""
import math
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_fukuoka_rail  # noqa: E402

URL = 'https://cyberjapandata.gsi.go.jp/xyz/{layer}/{z}/{x}/{y}.png'
FIVE = ('dem5a_png', 'dem5b_png', 'dem5c_png')
TEN = 'dem_png'
# A margin past the extent, in degrees: the grid reaches to whole
# population cells beyond it.
MARGIN = 0.01


def tile(lat, lon, z):
    n = 1 << z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return int(x), int(y)


def tiles(z):
    e = build_fukuoka_rail.EXTENT
    x0, y0 = tile(e['north'] + MARGIN, e['west'] - MARGIN, z)
    x1, y1 = tile(e['south'] - MARGIN, e['east'] + MARGIN, z)
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def get(folder, layer, z, x, y):
    path = os.path.join(folder, f'{layer}_{z}_{x}_{y}.png')
    if os.path.exists(path):
        return True
    for attempt in range(4):
        try:
            with urllib.request.urlopen(URL.format(layer=layer, z=z, x=x, y=y), timeout=30) as response:
                data = response.read()
            with open(path, 'wb') as f:
                f.write(data)
            return True
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return False
            time.sleep(2 ** attempt)
        except OSError:
            time.sleep(2 ** attempt)
    sys.exit(f'{layer} {z}/{x}/{y}: no answer after 4 tries')


def main(folder):
    os.makedirs(folder, exist_ok=True)
    counts = {}
    for x, y in tiles(15):
        layer = next((layer for layer in FIVE if get(folder, layer, 15, x, y)), None)
        counts[layer] = counts.get(layer, 0) + 1
    for x, y in tiles(14):
        if get(folder, TEN, 14, x, y):
            counts[TEN] = counts.get(TEN, 0) + 1
    print({str(k): v for k, v in counts.items()})


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
