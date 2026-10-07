#!/usr/bin/env python3
"""Count OpenStreetMap's shops, offices, schools and sights in Taiwan on
WorldPop's grid, for the app's `Resources/RealWorld/taiwan_places.json`.

    python3 tools/real-world-population/build_place_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_population.json \\
        osm-tiles/ \\
        RailwayGameApp/Resources/RealWorld/taiwan_places.json

It asks an Overpass API server (OVERPASS_URL, by default the maps.mail.ru
mirror) for every 0.25° tile with people in the population grid, one tile
at a time with pauses, and keeps each answer in the tiles folder: a run
that stops part way picks up where it left off, and a folder of earlier
answers is used as it is. An answer the server cut short (a `remark`
error, or fewer places than its counts) is asked for again, never kept. A place is its node, or the centre of its way or
relation; one that several tiles return counts once, and one north or west
of the population grid not at all. Standard library only.
"""
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

OVERPASS_URL = os.environ.get('OVERPASS_URL', 'https://maps.mail.ru/osm/tools/overpass/api/interpreter')
TILE = 0.25
SETS = [
    ('shops', 'nwr["shop"]({b});nwr["amenity"~"^(restaurant|cafe|fast_food|food_court|marketplace|bar|pub)$"]({b});'),
    ('offices', 'nwr["office"]({b});'),
    ('schools', 'nwr["amenity"~"^(school|university|college)$"]({b});'),
    ('attractions', 'nwr["tourism"~"^(attraction|museum|zoo|theme_park|viewpoint|aquarium|gallery)$"]({b});'),
]


def query(box):
    parts = []
    for name, sets in SETS:
        # `out count` first marks where each set starts in the answer.
        parts.append('(' + sets.format(b=box) + ')->.' + name + ';.' + name + ' out count;.' + name + ' out ids center qt;')
    return '[out:json][timeout:180];' + ''.join(parts)


def incomplete(answer):
    """Why an answer is not a whole one, or None. Overpass still answers
    200 when it runs out of time or memory part way, with a `remark` and
    only some of the elements: such an answer would undercount the tile.
    Each set's `out count` must be followed by exactly that many places."""
    remark = answer.get('remark', '')
    if 'error' in remark.lower():
        return remark
    elements = answer.get('elements', [])
    starts = [i for i, element in enumerate(elements) if element.get('type') == 'count']
    if len(starts) != len(SETS):
        return f'{len(starts)} counts for {len(SETS)} sets'
    for n, start in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(elements)
        expected = int(elements[start].get('tags', {}).get('total', -1))
        if expected != end - start - 1:
            return f'{SETS[n][0]}: {end - start - 1} places for a count of {expected}'
    return None


def fetch(box, path):
    """The tile's whole answer: kept from an earlier run, or asked for now."""
    if os.path.exists(path):
        try:
            kept = json.load(open(path))
            if incomplete(kept) is None:
                return kept
        except ValueError:
            pass
    time.sleep(1)  # A pause between questions to a shared server.
    url = OVERPASS_URL + '?' + urllib.parse.urlencode({'data': query(box)})
    for wait in (10, 20, 40, 60, 90, 120, 180):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'railway-game-ios-places/1.0'})
            body = urllib.request.urlopen(request, timeout=240).read()
            answer = json.loads(body)
            problem = incomplete(answer)
            if problem is not None:
                raise ValueError(f'incomplete answer: {problem}')
            open(path, 'wb').write(body)
            return answer
        except Exception as error:  # A busy server answers 504 or HTML.
            print(f'{box}: {error}; again in {wait} s', flush=True)
            time.sleep(wait)
    sys.exit(f'{box}: no answer from {OVERPASS_URL}')


def main(population_path, tiles_dir, out):
    grid = json.load(open(population_path))
    north, west, size = grid['north'], grid['west'], grid['cellDegrees']
    tiles = set()
    for run in grid['runs']:
        for offset in range(len(run['p'])):
            latitude = north - (run['r'] + 0.5) * size
            longitude = west + (run['c'] + offset + 0.5) * size
            tiles.add((math.floor(latitude / TILE), math.floor(longitude / TILE)))
    os.makedirs(tiles_dir, exist_ok=True)
    seen = {name: set() for name, _ in SETS}
    counts = {name: {} for name, _ in SETS}
    stamps = set()
    for row, column in sorted(tiles):
        box = f'{row * TILE:.2f},{column * TILE:.2f},{(row + 1) * TILE:.2f},{(column + 1) * TILE:.2f}'
        answer = fetch(box, os.path.join(tiles_dir, f'tile_{row}_{column}.json'))
        stamps.add(answer['osm3s']['timestamp_osm_base'])
        names = iter(name for name, _ in SETS)
        current = None
        for element in answer['elements']:
            if element['type'] == 'count':
                current = next(names)
                continue
            key = (element['type'], element['id'])
            if key in seen[current]:
                continue
            seen[current].add(key)
            point = element.get('center', element)
            if 'lat' not in point:
                continue
            cell = (math.floor((north - point['lat']) / size), math.floor((point['lon'] - west) / size))
            if cell[0] < 0 or cell[1] < 0:
                continue  # North or west of the population grid.
            counts[current][cell] = counts[current].get(cell, 0) + 1
    layers = {}
    for name, cells in counts.items():
        runs = []
        for (row, column) in sorted(cells):
            if runs and runs[-1]['r'] == row and runs[-1]['c'] + len(runs[-1]['p']) == column:
                runs[-1]['p'].append(cells[(row, column)])
            else:
                runs.append({'r': row, 'c': column, 'p': [cells[(row, column)]]})
        layers[name] = runs
    places = {
        'source': 'OpenStreetMap contributors, through the Overpass API',
        'licence': 'ODbL 1.0',
        'osmData': [min(stamps), max(stamps)],
        'north': north,
        'west': west,
        'cellDegrees': size,
        'layers': layers,
    }
    text = json.dumps(places, ensure_ascii=False, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)
    totals = {name: sum(cells.values()) for name, cells in counts.items()}
    print(f'{out}: {totals}, OSM data {min(stamps)} to {max(stamps)}, {len(text)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
