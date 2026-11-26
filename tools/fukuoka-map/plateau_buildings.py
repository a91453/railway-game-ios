#!/usr/bin/env python3
"""PLATEAU's buildings in Japan's map (decision 1001), for
`build_fukuoka_ground.py buildings`.

    python3 -I tools/fukuoka-map/plateau_buildings.py fetch /tmp/fk/plateau

PLATEAU, MLIT's 3D city models (国土交通省 Project PLATEAU), has the
buildings of 24 towns and cities of the map's four prefectures
(Kitakyushu, Fukuoka, Kumamoto, Kurume, Omuta, Iizuka, Munakata, Koga,
Tosu, Sasebo, ...): each one's outline (`bldg:lod0FootPrint`, else
`lod0RoofEdge`, else the bottom of its `lod1Solid`), its height measured
from airborne laser points (`bldg:measuredHeight`), its storeys above
ground and its use (`bldg:usage`). The owner (2026-11-26): official data
first, Overture's machine outlines only where there is none
(「然後都不行最後的替代方案就是overture」).

`fetch` asks PLATEAU's catalogue which towns have buildings
(https://api.plateau.reearth.io/datacatalog/plateau-datasets) and, for
each, the newest year's CityGML building files
(https://api.plateau.reearth.io/datacatalog/citygml/<town>), reads them
(about 3,000 files, a few GB, 16 at a time) and keeps one line a building
in `<town>.tsv`: gml:id, measured height (m), storeys above ground, use
code, and the outline as `lon lat,lon lat,...` rings (`|` before a hole,
`;` before another polygon). `buildings.tsv` is all of them, the town's
code first; `towns.json` says which town, year and how many. Running it
again reads only the towns missing.

Licence: PLATEAU's data are under MLIT's terms of use, compatible with
CC BY 4.0 (https://www.mlit.go.jp/plateau/site-policy/); credit
「3D都市モデル（Project PLATEAU）」（国土交通省）を加工して作成.
"""
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

CATALOGUE = 'https://api.plateau.reearth.io/datacatalog/plateau-datasets'
CITYGML = 'https://api.plateau.reearth.io/datacatalog/citygml/'
# 福岡県, 佐賀県, 長崎県, 熊本県.
PREFECTURES = ('40', '41', '42', '43')
# PLATEAU's Building_usage codes, as Overture's uses (`USES` of
# tools/overture-footprint-tiles/build_footprint_tiles.py).
USES = {'401': 'commercial', '402': 'commercial', '403': 'commercial', '404': 'commercial',
        '411': 'residential', '412': 'residential', '413': 'residential', '414': 'residential', '415': 'residential',
        '421': 'civic', '422': 'education', '431': 'industrial', '441': 'industrial', '451': 'agricultural',
        '452': 'service', '453': 'military'}

BUILDING = re.compile(r'<bldg:(Building|BuildingPart) gml:id="([^"]+)"')
POLYGON = re.compile(r'<gml:Polygon[^>]*>(.*?)</gml:Polygon>', re.S)
RING = re.compile(r'<gml:(exterior|interior)>.*?<gml:posList[^>]*>(.*?)</gml:posList>', re.S)


def get(url, attempts=5):
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=300) as response:
                return response.read()
        except OSError:
            if attempt == attempts - 1:
                raise


def towns(catalogue):
    return sorted({d['city_code'] for d in catalogue['datasets']
                   if d['type_en'] == 'bldg' and d['pref_code'] in PREFECTURES})


def value(block, tag):
    match = re.search(rf'<bldg:{tag}[^>]*>([^<]*)</bldg:{tag}>', block)
    return match.group(1).strip() if match else ''


def polygons(text):
    """[[ring, holes...]] of the gml:Polygons in `text`, (lon, lat, z)."""
    out = []
    for polygon in POLYGON.findall(text):
        rings = []
        for kind, positions in RING.findall(polygon):
            numbers = [float(v) for v in positions.split()]
            rings.append([(numbers[i + 1], numbers[i], numbers[i + 2]) for i in range(0, len(numbers) - 2, 3)])
        if rings:
            out.append(rings)
    return out


def outline(block):
    """The building's outline: its footprint, roof edge, or the lowest
    flat face of its solid."""
    for tag in ('lod0FootPrint', 'lod0RoofEdge'):
        start = block.find(f'<bldg:{tag}>')
        if start >= 0:
            found = polygons(block[start:block.index(f'</bldg:{tag}>', start)])
            if found:
                return found
    start = block.find('<bldg:lod1Solid>')
    if start >= 0:
        faces = [p for p in polygons(block[start:block.index('</bldg:lod1Solid>', start)])
                 if len(p[0]) >= 4 and max(z for _, _, z in p[0]) - min(z for _, _, z in p[0]) < 0.01]
        if faces:
            low = min(face[0][0][2] for face in faces)
            return [face for face in faces if abs(face[0][0][2] - low) < 0.01][:1]
    return []


def buildings(gml):
    """(gml:id, height, storeys, use, polygons) of a CityGML file: each
    bldg:Building, or each of its BuildingParts when it has no outline of
    its own (the part's height and storeys, else the building's)."""
    text = gml.decode('utf-8')
    marks = [(m.start(), m.group(1), m.group(2)) for m in BUILDING.finditer(text)]
    out = []
    for at, kind, name in marks:
        if kind != 'Building':
            continue
        end = text.find('</bldg:Building>', at)
        end = len(text) if end < 0 else end
        whole = text[at:end]
        parts = [(m.start(), m.group(2)) for m in BUILDING.finditer(whole) if m.group(1) == 'BuildingPart']
        own = whole[:parts[0][0]] if parts else whole
        height, storeys, use = value(own, 'measuredHeight'), value(own, 'storeysAboveGround'), value(own, 'usage')
        found = outline(own)
        if found:
            out.append((name, height, storeys, use, found))
            continue
        for number, (start, part) in enumerate(parts):
            stop = parts[number + 1][0] if number + 1 < len(parts) else len(whole)
            block = whole[start:stop]
            found = outline(block)
            if found:
                out.append((part, value(block, 'measuredHeight') or height, value(block, 'storeysAboveGround') or storeys,
                            value(block, 'usage') or use, found))
    return out


def ring_text(polygons_):
    return ';'.join('|'.join(','.join(f'{lon:.7f} {lat:.7f}' for lon, lat, _ in ring) for ring in polygon)
                    for polygon in polygons_)


def fetch(out):
    os.makedirs(out, exist_ok=True)
    catalogue_path = os.path.join(out, 'catalogue.json')
    if not os.path.exists(catalogue_path):
        with open(catalogue_path, 'wb') as f:
            f.write(get(CATALOGUE))
    with open(catalogue_path, encoding='utf-8') as f:
        codes = towns(json.load(f))
    report = []
    for code in codes:
        path = os.path.join(out, code + '.tsv')
        info_path = os.path.join(out, code + '.json')
        if not os.path.exists(path):
            cities = json.loads(get(CITYGML + code))['cities']
            city = max((c for c in cities if c['files'].get('bldg')), key=lambda c: c['year'])
            urls = sorted(f['url'] for f in city['files']['bldg'])
            with ThreadPoolExecutor(16) as pool:
                rows = [row for found in pool.map(lambda u: buildings(get(u)), urls) for row in found]
            rows.sort(key=lambda row: row[0])
            with open(path + '.part', 'w', encoding='utf-8') as f:
                for name, height, storeys, use, found in rows:
                    f.write('\t'.join((name, height, storeys, use, ring_text(found))) + '\n')
            os.replace(path + '.part', path)
            with open(info_path, 'w', encoding='utf-8') as f:
                json.dump({'code': code, 'city': city['cityName'], 'year': city['year'], 'files': len(urls),
                           'url': city['url']}, f, ensure_ascii=False)
        with open(info_path, encoding='utf-8') as f:
            info = json.load(f)
        with open(path, encoding='utf-8') as f:
            info['buildings'] = sum(1 for _ in f)
        report.append(info)
        print(f"{code} {info['city']} {info['year']}: {info['files']} files, {info['buildings']} buildings", file=sys.stderr)
    with open(os.path.join(out, 'buildings.tsv'), 'w', encoding='utf-8') as whole:
        for info in report:
            with open(os.path.join(out, info['code'] + '.tsv'), encoding='utf-8') as f:
                for line in f:
                    whole.write(info['code'] + '\t' + line)
    with open(os.path.join(out, 'towns.json'), 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)


def read(folder):
    """(name, use, height or None, storeys or None, [rings]) of `fetch`'s
    buildings, each polygon one, in its order."""
    out = []
    with open(os.path.join(folder, 'buildings.tsv'), encoding='utf-8') as f:
        for line in f:
            code, name, height, storeys, use, rings = line.rstrip('\n').split('\t')
            for part, polygon in enumerate(rings.split(';') if rings else []):
                found = [[tuple(float(v) for v in point.split()) for point in ring.split(',')] for ring in polygon.split('|')]
                found = [ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else ring for ring in found]
                if len(found[0]) < 3:
                    continue
                out.append((f'pl:{code}/{name}/{part}', USES.get(use), float(height) if height else None,
                            int(storeys) if storeys.isdigit() else None, found))
    return out


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] != 'fetch':
        sys.exit(__doc__)
    fetch(sys.argv[2])
