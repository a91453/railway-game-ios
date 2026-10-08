#!/usr/bin/env python3
"""Measure OpenStreetMap's industrial land, parks and farmland in Taiwan on
a finer cut of WorldPop's grid, and add them to the app's
`Resources/RealWorld/taiwan_places.json` as its `zones` (decision 93).

    python3 tools/real-world-population/build_zone_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_places.json \\
        osm-zone-tiles/ \\
        RailwayGameApp/Resources/RealWorld/taiwan_places.json

The places file gives the grid (its corner and cell size); its other
contents are kept as they are, so this runs after `build_place_grid.py`.
Like that script, it asks an Overpass API server (OVERPASS_URL, by default
the maps.mail.ru mirror; several, separated by commas, are taken in turn
when one does not answer) for every 0.25° tile with places in the file, one
tile and one kind of land at a time with pauses, keeps each whole answer
in the tiles folder (a run that stops part way picks up where it left
off) and asks again for one the server cut short.

The zones are areas, not points: industrial land, parks and farmland (TAGS:
`landuse=industrial`, `leisure=park`, `landuse=farmland` and their kin) as
ways and multipolygon relations, as MapBuilder's
`fetchAndHandleParks` takes the parks' area around a station. Each WorldPop
cell is cut into CUTS × CUTS zone cells (7.5″, some 230 × 210 m in
Taiwan), and each zone cell into SAMPLES × SAMPLES points; a zone cell's
number is how many of its points lie inside that kind of land (even-odd, so
a relation's inner rings are holes), from 0 to SAMPLES². A point inside
several areas of one kind counts once. Standard library only.

A whole extract of Taiwan (an OpenStreetMap `.pbf` file, for example
osmtoday.com's `asia/taiwan.pbf`) can stand for the tiles folder, when the
Overpass servers are too busy: it is read in a few minutes, with
pyosmium (BSD 2-Clause; `pip install osmium`), the only time the script
needs more than the standard library:

    python3 tools/real-world-population/build_zone_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_places.json \\
        taiwan.pbf \\
        RailwayGameApp/Resources/RealWorld/taiwan_places.json
"""
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

OVERPASS_URLS = os.environ.get('OVERPASS_URL', 'https://maps.mail.ru/osm/tools/overpass/api/interpreter').split(',')
TILE = 0.25
SPLITS = 2
CUTS = 4
SAMPLES = 4
# The tags of each kind of land (decision 96): OpenStreetMap's land that
# works, plays or farms like it. Woods, nature reserves, water, cemeteries
# and military land are none of them (decision 96 says why), and neither are
# `landuse=harbour` (often the harbour's water) or the shops' and schools'
# own areas (their places are counted as points, `build_place_grid.py`).
TAGS = {
    'industrial': {'landuse': ('industrial', 'quarry')},
    'park': {'leisure': ('park', 'golf_course'), 'landuse': ('recreation_ground',)},
    'farmland': {'landuse': ('farmland', 'orchard', 'vineyard', 'aquaculture', 'farmyard', 'greenhouse_horticulture', 'plant_nursery')},
}
SETS = [
    (name, ''.join(f'wr["{key}"~"^({"|".join(values)})$"]({{b}});' for key, values in keys.items()))
    for name, keys in TAGS.items()
]


def query(sets, box):
    # `out count` first says how many areas the answer must hold.
    return '[out:json][timeout:180];(' + sets.format(b=box) + ');out count;out geom qt;'


def incomplete(answer):
    """Why an answer is not a whole one, or None. Overpass still answers
    200 when it runs out of time or memory part way, with a `remark` and
    only some of the elements: such an answer would leave land out. Its
    `out count` must be followed by exactly that many areas."""
    remark = answer.get('remark', '')
    if 'error' in remark.lower():
        return remark
    elements = answer.get('elements', [])
    if not elements or elements[0].get('type') != 'count':
        return 'no count'
    expected = int(elements[0].get('tags', {}).get('total', -1))
    if expected != len(elements) - 1:
        return f'{len(elements) - 1} areas for a count of {expected}'
    return None


def fetch(sets, south, west, size, path, depth=0):
    """The answers for one kind of land in a box: kept from an earlier run,
    or asked for now. A box the servers keep failing on (a busy server
    gives up on a slow question with 504) is asked for again as its four
    quarters, smaller questions, down to a sixteenth of a tile; the
    smallest is asked until it is answered or the waits run out."""
    box = f'{south:.4f},{west:.4f},{south + size:.4f},{west + size:.4f}'
    if os.path.exists(path):
        try:
            kept = json.load(open(path))
            if incomplete(kept) is None:
                return [kept]
        except ValueError:
            pass
    stem = path[:-len('.json')]
    # An earlier run already asked for the quarters.
    split = depth < SPLITS and os.path.exists(f'{stem}_0.json')
    data = urllib.parse.urlencode({'data': query(sets, box)}).encode()
    waits = () if split else (10, 20, 40, 60, 90, 120, 180, 180, 300, 300, 300, 600) if depth == SPLITS else (10, 20, 40)
    if waits:
        time.sleep(1)  # A pause between questions to a shared server.
    for n, wait in enumerate(waits):
        url = OVERPASS_URLS[n % len(OVERPASS_URLS)]
        try:
            request = urllib.request.Request(url, data=data, headers={'User-Agent': 'railway-game-ios-zones/1.0'})
            body = urllib.request.urlopen(request, timeout=300).read()
            answer = json.loads(body)
            problem = incomplete(answer)
            if problem is not None:
                raise ValueError(f'incomplete answer: {problem}')
            open(path, 'wb').write(body)
            return [answer]
        except Exception as error:  # A busy server answers 504 or HTML.
            print(f'{box}: {url}: {error}; again in {wait} s', flush=True)
            time.sleep(wait)
    if depth == SPLITS:
        sys.exit(f'{box}: no answer from {", ".join(OVERPASS_URLS)}')
    print(f'{box}: asking for its quarters', flush=True)
    half = size / 2
    return [answer for n, (row, column) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1)))
            for answer in fetch(sets, south + row * half, west + column * half, half, f'{stem}_{n}.json', depth + 1)]


def rings(element):
    """An area's closed rings as lists of (lat, lon): a closed way's own, or
    a relation's member ways joined end to end (outer and inner alike; a
    ring that does not close is left out)."""
    def points(geometry):
        return [(point['lat'], point['lon']) for point in geometry if point]
    if element['type'] == 'way':
        ring = points(element.get('geometry', []))
        return [ring] if len(ring) >= 4 and ring[0] == ring[-1] else []
    pieces = [points(member['geometry']) for member in element.get('members', [])
              if member.get('type') == 'way' and member.get('geometry')]
    pieces = [piece for piece in pieces if len(piece) >= 2]
    closed = []
    while pieces:
        ring = pieces.pop()
        while ring[0] != ring[-1]:
            for n, piece in enumerate(pieces):
                if piece[0] == ring[-1]:
                    ring = ring + piece[1:]
                elif piece[-1] == ring[-1]:
                    ring = ring + piece[-2::-1]
                else:
                    continue
                del pieces[n]
                break
            else:
                break
        if len(ring) >= 4 and ring[0] == ring[-1]:
            closed.append(ring)
    return closed


def fill(area, north, west, step, inside):
    """Add the sample points (row, column) of `step` degrees from the grid's
    corner that lie inside `area`'s rings (even-odd) to `inside`."""
    crossings = {}
    for ring in area:
        for (a_lat, a_lon), (b_lat, b_lon) in zip(ring, ring[1:]):
            if a_lat == b_lat:
                continue
            # The sample rows whose latitude lies in [low, high) of the edge.
            low, high = min(a_lat, b_lat), max(a_lat, b_lat)
            first = math.ceil((north - high) / step - 0.5)
            last = math.ceil((north - low) / step - 0.5) - 1
            for row in range(max(first, 0), last + 1):
                latitude = north - (row + 0.5) * step
                if not (low <= latitude < high):
                    continue
                longitude = a_lon + (latitude - a_lat) * (b_lon - a_lon) / (b_lat - a_lat)
                crossings.setdefault(row, []).append(longitude)
    for row, xs in crossings.items():
        xs.sort()
        for start, end in zip(xs[0::2], xs[1::2]):
            first = max(math.ceil((start - west) / step - 0.5), 0)
            last = math.ceil((end - west) / step - 0.5) - 1
            for column in range(first, last + 1):
                inside.add((row, column))


def from_overpass(places, tiles_dir, inside):
    """Fill `inside` from Overpass, tile by tile; the servers' data times."""
    north, west, size = places['north'], places['west'], places['cellDegrees']
    tiles = set()
    for runs in places['layers'].values():
        for run in runs:
            for offset in range(len(run['p'])):
                latitude = north - (run['r'] + 0.5) * size
                longitude = west + (run['c'] + offset + 0.5) * size
                tiles.add((math.floor(latitude / TILE), math.floor(longitude / TILE)))
    os.makedirs(tiles_dir, exist_ok=True)
    step = size / (CUTS * SAMPLES)
    seen = {name: set() for name, _ in SETS}
    stamps = set()
    for n, (row, column) in enumerate(sorted(tiles)):
        for name, sets in SETS:
            for answer in fetch(sets, row * TILE, column * TILE, TILE, os.path.join(tiles_dir, f'tile_{row}_{column}_{name}.json')):
                stamps.add(answer['osm3s']['timestamp_osm_base'])
                for element in answer['elements'][1:]:
                    key = (element['type'], element['id'])
                    if key in seen[name]:
                        continue
                    seen[name].add(key)
                    fill(rings(element), north, west, step, inside[name])
        print(f'{n + 1}/{len(tiles)} {row * TILE:.2f},{column * TILE:.2f}', flush=True)
    return {name: len(ids) for name, ids in seen.items()}, [min(stamps), max(stamps)]


def from_extract(places, path, inside):
    """Fill `inside` from a whole `.pbf` extract, its areas put together by
    libosmium (closed ways and multipolygon relations, inner rings as
    holes); the newest edit among them (an extract's header need not say
    when it was made)."""
    import osmium  # pyosmium: only for an extract.
    north, west, size = places['north'], places['west'], places['cellDegrees']
    step = size / (CUTS * SAMPLES)
    counts = {name: 0 for name in TAGS}
    newest = None
    keys = sorted({key for kinds in TAGS.values() for key in kinds})
    processor = osmium.FileProcessor(path).with_areas(osmium.filter.KeyFilter(*keys))
    for area in processor.with_filter(osmium.filter.EntityFilter(osmium.osm.AREA)):
        for name, kinds in TAGS.items():
            if not any(area.tags.get(key) in values for key, values in kinds.items()):
                continue
            area_rings = []
            for outer in area.outer_rings():
                area_rings.append([(node.lat, node.lon) for node in outer])
                for inner in area.inner_rings(outer):
                    area_rings.append([(node.lat, node.lon) for node in inner])
            fill(area_rings, north, west, step, inside[name])
            counts[name] += 1
            stamp = area.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
            newest = max(newest or stamp, stamp)
    return counts, [newest, newest]


def main(places_path, source, out):
    places = json.load(open(places_path))
    size = places['cellDegrees']
    inside = {name: set() for name, _ in SETS}
    if source.endswith('.pbf'):
        counts, stamps = from_extract(places, source, inside)
    else:
        counts, stamps = from_overpass(places, source, inside)
    layers = {}
    for name, points in inside.items():
        cells = {}
        for row, column in points:
            cell = (row // SAMPLES, column // SAMPLES)
            cells[cell] = cells.get(cell, 0) + 1
        runs = []
        for (row, column) in sorted(cells):
            if runs and runs[-1]['r'] == row and runs[-1]['c'] + len(runs[-1]['p']) == column:
                runs[-1]['p'].append(cells[(row, column)])
            else:
                if runs and runs[-1]['r'] == row and runs[-1]['c'] + len(runs[-1]['p']) + 1 == column:
                    runs[-1]['p'].extend([0, cells[(row, column)]])  # One gap costs less than a new run.
                    continue
                runs.append({'r': row, 'c': column, 'p': [cells[(row, column)]]})
        layers[name] = runs
    places['zones'] = {
        'source': 'OpenStreetMap contributors, ' + (f'from the extract {os.path.basename(source)}' if source.endswith('.pbf') else 'through the Overpass API'),
        'licence': 'ODbL 1.0',
        'osmData': stamps,
        'cuts': CUTS,
        'samples': SAMPLES * SAMPLES,
        'layers': layers,
    }
    text = json.dumps(places, ensure_ascii=False, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)
    cell_km2 = (size / CUTS * 110.574) * (size / CUTS * 111.320 * math.cos(math.radians(23.7)))
    areas = {name: round(len(points) / SAMPLES ** 2 * cell_km2, 1) for name, points in inside.items()}
    print(f'{out}: km² {areas}, areas {counts}, OSM data {stamps[0]} to {stamps[1]}, {len(text)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
