#!/usr/bin/env python3
"""The National Land Survey of Finland's (Maanmittauslaitos, MML) buildings
round Rovaniemi (decision 1009), downloaded and read for
`build_rovaniemi_buildings.py`.

    python3 -I tools/rovaniemi-map/mml_buildings.py fetch /tmp/rv/mml

Two of MML's open datasets (both CC BY 4.0, MML's open data licence), from
Kapsi's public mirror (MML's own download service wants an API key, as the
elevation model's README says):

- The Topographic Database (Maastotietokanta), `Rakennus`: every
  building's outline as MML draws it from aerial photographs, with what it
  is used for (`kayttotarkoitus`) and its storeys as a class
  (`kerrosluku`: 1 for one or two, 2 for three or more). One GML a half
  sheet (`<sheet>L_mtk.zip`, `<sheet>R_mtk.zip`, 12 × 12 km) under
  `MTK_URL`; the sheets are the elevation model's (`fetch_nls_dem.sheets`).
- Buildings 3D (Rakennukset 3D), LoD2 CityGML from the 2022 laser scan of
  Rovaniemi: each building's ground and roof, and its measured height.
  One GML a 6 × 6 km square (`<sheet><A–H>.zip`) under `LOD2_URL`; only the
  Rovaniemi block of 2022 reaches the map, the town and its suburbs.

Both are in ETRS-TM35FIN (EPSG:3067), turned to longitude and latitude by
`lonlat` (the inverse of `fetch_nls_dem.tm35`, Krüger's series).
"""

import math
import os
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fetch_nls_dem  # noqa: E402

MTK_URL = 'https://kartat.kapsi.fi/files/maastotietokanta/kaikki/etrs89/gml/{a}/{b}/{name}_mtk.zip'
LOD2_URL = 'https://kartat.kapsi.fi/files/3D-rakennukset/kaikki/2022/etrs89/citygml/Rovaniemi/LOD2/'
LICENCE = ('National Land Survey of Finland open data licence (CC BY 4.0), '
           'https://www.maanmittauslaitos.fi/en/opendata-licence-cc40')

# MTK's `kayttotarkoitus` to the tiles' use (the tool's `USES`) and the
# OpenStreetMap kind it stands for when guessing storeys (`hk.group_of`).
# A church is civic, as Hong Kong's table has it: the 3D map draws the
# religious as Taiwan's temples.
MTK_USE = {
    1: ('residential', 'house'),         # asuinrakennus
    2: ('commercial', 'commercial'),     # liike- tai julkinen rakennus
    3: ('residential', 'cabin'),         # lomarakennus
    4: ('industrial', 'industrial'),     # teollinen rakennus
    5: ('civic', 'chapel'),              # kirkollinen rakennus
    6: ('outbuilding', 'shed'),          # muu rakennus: saunas, stores, barns
    8: ('civic', 'church'),              # kirkko
}

# GRS 80 and TM35FIN, as `fetch_nls_dem.tm35`.
A, F = 6_378_137.0, 1 / 298.257222101


def lonlat(easting, northing):
    """Longitude and latitude (degrees) of an ETRS-TM35FIN point."""
    n = F / (2 - F)
    big_a = A / (1 + n) * (1 + n * n / 4 + n ** 4 / 64)
    beta = [n / 2 - 2 * n * n / 3 + 37 * n ** 3 / 96, n * n / 48 + n ** 3 / 15, 17 * n ** 3 / 480]
    xi = northing / (fetch_nls_dem.TM35_SCALE * big_a)
    eta = (easting - fetch_nls_dem.TM35_EASTING) / (fetch_nls_dem.TM35_SCALE * big_a)
    xi1, eta1 = xi, eta
    for j, b in enumerate(beta, start=1):
        xi1 -= b * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        eta1 -= b * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
    chi = math.asin(math.sin(xi1) / math.cosh(eta1))
    e = math.sqrt(F * (2 - F))
    phi = chi
    for _ in range(6):
        phi = math.asin(math.tanh(math.atanh(math.sin(chi)) + e * math.atanh(e * math.sin(phi))))
    lam = math.atan2(math.sinh(eta1), math.cos(xi1))
    return fetch_nls_dem.TM35_MERIDIAN + math.degrees(lam), math.degrees(phi)


def get(url, path):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=300) as response:
                data = response.read()
            with open(path, 'wb') as file:
                file.write(data)
            return len(data)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return 0
            time.sleep(2 ** attempt)
        except (urllib.error.URLError, OSError):
            time.sleep(2 ** attempt)
    sys.exit(f'{url}: no answer after 4 tries')


def fetch(folder):
    """The half sheets of MTK over the map and the 3D squares of the
    Rovaniemi block in them (about 300 MB and 20 MB)."""
    os.makedirs(os.path.join(folder, 'mtk'), exist_ok=True)
    os.makedirs(os.path.join(folder, 'lod2'), exist_ok=True)
    sheets = sorted(fetch_nls_dem.sheets())
    for sheet in sheets:
        for half in 'LR':
            name = sheet + half
            path = os.path.join(folder, 'mtk', name + '_mtk.zip')
            if not os.path.exists(path):
                size = get(MTK_URL.format(a=name[:2], b=name[:3], name=name), path)
                print(f'{name} {math.ceil(size / 1e6)} MB', flush=True)
    with urllib.request.urlopen(LOD2_URL, timeout=120) as response:
        listing = response.read().decode()
    for name in sorted(set(re.findall(r'href="(T\d{4}[A-H])\.zip"', listing))):
        if name[:5] not in sheets:
            continue
        path = os.path.join(folder, 'lod2', name + '.zip')
        if not os.path.exists(path):
            size = get(LOD2_URL + name + '.zip', path)
            print(f'3D {name} {math.ceil(size / 1e3)} kB', flush=True)


def members(path):
    """The text of each file in a zip."""
    with zipfile.ZipFile(path) as archive:
        for info in sorted(archive.infolist(), key=lambda info: info.filename):
            if info.filename.lower().endswith(('.xml', '.gml')):
                yield archive.read(info).decode('utf-8')


def ring_of(text):
    """A posList of x y z triples as (lon, lat), not closed, and its z."""
    numbers = [float(value) for value in text.split()]
    points = [(numbers[i], numbers[i + 1]) for i in range(0, len(numbers) - 2, 3)]
    if len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    return [lonlat(x, y) for x, y in points], numbers[2::3]


def inside_extent(middle, extent):
    return extent['west'] <= middle[0] <= extent['east'] and extent['south'] <= middle[1] <= extent['north']


def middle_of(ring):
    return (sum(lon for lon, _ in ring) / len(ring), sum(lat for _, lat in ring) / len(ring))


def tag(block, name):
    found = re.search(rf'<{name}>([^<]*)</{name}>', block)
    return found.group(1) if found else None


def read_mtk(folder, extent):
    """MTK's buildings whose middle is in `extent`, by id: dicts of id
    (`mml:<gid>`), use (MTK's code), floors (its class, 0 unknown),
    rings of (lon, lat) and middle; each building once, though the half
    sheets overlap nowhere, and the report of what was read."""
    found, files = {}, []
    for name in sorted(os.listdir(os.path.join(folder, 'mtk'))):
        if not name.endswith('_mtk.zip'):
            continue
        files.append(name)
        for text in members(os.path.join(folder, 'mtk', name)):
            for match in re.finditer(r'<Rakennus gid="(\d+)".*?</Rakennus>', text, re.S):
                block = match.group(0)
                area = re.search(r'<Alue>(.*?)</Alue>', block, re.S)
                if not area:
                    continue
                outer = re.search(r'<gml:exterior>.*?<gml:posList[^>]*>([^<]*)</gml:posList>', area.group(1), re.S)
                if not outer:
                    continue
                rings = [ring_of(outer.group(1))[0]]
                for hole in re.finditer(r'<gml:interior>.*?<gml:posList[^>]*>([^<]*)</gml:posList>', area.group(1), re.S):
                    rings.append(ring_of(hole.group(1))[0])
                rings = [ring for ring in rings if len(ring) >= 3]
                if not rings or len(rings[0]) < 3:
                    continue
                middle = middle_of(rings[0])
                if not inside_extent(middle, extent):
                    continue
                gid = 'mml:' + match.group(1)
                found[gid] = {'id': gid, 'use': int(tag(block, 'kayttotarkoitus') or 0),
                              'floors': int(tag(block, 'kerrosluku') or 0), 'rings': rings, 'middle': middle,
                              'since': tag(block, 'alkupvm')}
    return [found[gid] for gid in sorted(found)], {'files': len(files), 'buildingsInTheMap': len(found)}


def read_lod2(folder, extent):
    """The 3D buildings whose ground's middle is in `extent`: dicts of id,
    ground (a ring of (lon, lat)), middle, measured (`measuredHeight`, the
    ground to the ridge, m) and eaves (the ground to the foot of the roof,
    m: the lowest corner of each of its faces, weighted by the face's size
    seen from above, so a porch roof does not bring a house's down), and
    the report of what was read."""
    out, files, read = [], 0, 0
    for name in sorted(os.listdir(os.path.join(folder, 'lod2'))):
        if not name.endswith('.zip'):
            continue
        files += 1
        for text in members(os.path.join(folder, 'lod2', name)):
            for match in re.finditer(r'<bldg:Building gml:id="([^"]+)">(.*?)</bldg:Building>', text, re.S):
                read += 1
                block = match.group(2)
                measured = re.search(r'<bldg:measuredHeight[^>]*>([^<]*)<', block)
                ground = re.search(r'<bldg:GroundSurface.*?</bldg:GroundSurface>', block, re.S)
                roof = re.search(r'<bldg:RoofSurface.*?</bldg:RoofSurface>', block, re.S)
                if not ground or not roof:
                    continue
                lists = re.findall(r'<gml:posList[^>]*>([^<]*)</gml:posList>', ground.group(0))
                rings = [ring_of(text) for text in lists]
                rings = [(ring, zs) for ring, zs in rings if len(ring) >= 3]
                if not rings:
                    continue
                biggest, ground_z = max(rings, key=lambda pair: abs(area_of(pair[0])))
                base = min(ground_z)
                eaves = []
                for text in re.findall(r'<gml:posList[^>]*>([^<]*)</gml:posList>', roof.group(0)):
                    ring, zs = ring_of(text)
                    if len(ring) >= 3 and zs:
                        eaves.append((abs(area_of(ring)), min(zs)))
                if not eaves or not sum(size for size, _ in eaves):
                    continue
                middle = middle_of(biggest)
                if not inside_extent(middle, extent):
                    continue
                out.append({'id': match.group(1), 'ground': biggest, 'middle': middle,
                            'measured': float(measured.group(1)) if measured else None,
                            'eaves': sum(size * z for size, z in eaves) / sum(size for size, _ in eaves) - base})
    out.sort(key=lambda building: building['id'])
    return out, {'files': files, 'buildingsRead': read, 'buildingsInTheMap': len(out)}


def area_of(ring):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1])) / 2


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] != 'fetch':
        sys.exit(__doc__)
    fetch(sys.argv[2])
