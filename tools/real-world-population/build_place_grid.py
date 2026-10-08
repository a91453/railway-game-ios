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

A whole extract of Taiwan (an OpenStreetMap `.pbf` file, for example
osmtoday.com's `asia/taiwan.pbf`, the one `build_zone_grid.py` reads) can
stand for the tiles folder: it is read in a few minutes with pyosmium (BSD
2-Clause; `pip install osmium`), the only time the script needs more than
the standard library. The places are the same: the same tags, the centre
of a way or relation its bounding box's (as Overpass's `center`), counted
where the centre's tile has people.
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


def from_overpass(north, west, size, tiles, tiles_dir):
    """The places of each kind per cell from Overpass, tile by tile, and
    the servers' data times."""
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
    return counts, [min(stamps), max(stamps)]


# The tags of each kind, as SETS asks Overpass for them.
SHOP_AMENITIES = {'restaurant', 'cafe', 'fast_food', 'food_court', 'marketplace', 'bar', 'pub'}
SCHOOLS = {'school', 'university', 'college'}
SIGHTS = {'attraction', 'museum', 'zoo', 'theme_park', 'viewpoint', 'aquarium', 'gallery'}


def kinds_of(tags):
    """The kinds of place an element with `tags` is, as SETS sees it."""
    amenity = tags.get('amenity')
    kinds = []
    if 'shop' in tags or amenity in SHOP_AMENITIES:
        kinds.append('shops')
    if 'office' in tags:
        kinds.append('offices')
    if amenity in SCHOOLS:
        kinds.append('schools')
    if tags.get('tourism') in SIGHTS:
        kinds.append('attractions')
    return kinds


def from_extract(north, west, size, tiles, path):
    """The places of each kind per cell from a whole `.pbf` extract: nodes
    where they are, ways and relations at the centre of their bounding box
    (a relation's of its member nodes and ways), each counted once; and the
    newest edit among them (an extract's header need not say when it was
    made)."""
    import osmium  # pyosmium: only for an extract.
    counts = {name: {} for name, _ in SETS}
    newest = None
    relations = []  # (kinds, member nodes, member ways)
    wanted_nodes, wanted_ways = set(), set()

    def count(kinds, latitude, longitude):
        if (math.floor(latitude / TILE), math.floor(longitude / TILE)) not in tiles:
            return  # As Overpass is asked only for tiles with people.
        cell = (math.floor((north - latitude) / size), math.floor((longitude - west) / size))
        if cell[0] < 0 or cell[1] < 0:
            return  # North or west of the population grid.
        for kind in kinds:
            counts[kind][cell] = counts[kind].get(cell, 0) + 1

    def stamp(element):
        nonlocal newest
        text = element.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
        newest = max(newest or text, text)

    processor = osmium.FileProcessor(path).with_locations().with_filter(osmium.filter.KeyFilter('shop', 'amenity', 'office', 'tourism'))
    for element in processor:
        kinds = kinds_of(element.tags)
        if not kinds:
            continue
        stamp(element)
        if element.is_node():
            count(kinds, element.location.lat, element.location.lon)
        elif element.is_way():
            points = [(node.location.lat, node.location.lon) for node in element.nodes if node.location.valid()]
            if points:
                latitudes, longitudes = zip(*points)
                count(kinds, (min(latitudes) + max(latitudes)) / 2, (min(longitudes) + max(longitudes)) / 2)
        elif element.is_relation():
            nodes = [member.ref for member in element.members if member.type == 'n']
            ways = [member.ref for member in element.members if member.type == 'w']
            relations.append((kinds, nodes, ways))
            wanted_nodes.update(nodes)
            wanted_ways.update(ways)
    # The relations' members, in a second reading.
    places = {}
    if relations:
        for element in osmium.FileProcessor(path, osmium.osm.NODE | osmium.osm.WAY).with_locations():
            if element.is_node() and element.id in wanted_nodes:
                places[('n', element.id)] = [(element.location.lat, element.location.lon)]
            elif element.is_way() and element.id in wanted_ways:
                places[('w', element.id)] = [(node.location.lat, node.location.lon) for node in element.nodes if node.location.valid()]
    for kinds, nodes, ways in relations:
        points = [point for ref in nodes for point in places.get(('n', ref), [])]
        points += [point for ref in ways for point in places.get(('w', ref), [])]
        if points:
            latitudes, longitudes = zip(*points)
            count(kinds, (min(latitudes) + max(latitudes)) / 2, (min(longitudes) + max(longitudes)) / 2)
    return counts, [newest, newest]


def main(population_path, source, out):
    grid = json.load(open(population_path))
    north, west, size = grid['north'], grid['west'], grid['cellDegrees']
    tiles = set()
    for run in grid['runs']:
        for offset in range(len(run['p'])):
            latitude = north - (run['r'] + 0.5) * size
            longitude = west + (run['c'] + offset + 0.5) * size
            tiles.add((math.floor(latitude / TILE), math.floor(longitude / TILE)))
    if source.endswith('.pbf'):
        counts, stamps = from_extract(north, west, size, tiles, source)
    else:
        counts, stamps = from_overpass(north, west, size, tiles, source)
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
        'source': 'OpenStreetMap contributors, ' + (f'from the extract {os.path.basename(source)}' if source.endswith('.pbf') else 'through the Overpass API'),
        'licence': 'ODbL 1.0',
        'osmData': stamps,
        'north': north,
        'west': west,
        'cellDegrees': size,
        'layers': layers,
    }
    text = json.dumps(places, ensure_ascii=False, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)
    totals = {name: sum(cells.values()) for name, cells in counts.items()}
    print(f'{out}: {totals}, OSM data {stamps[0]} to {stamps[1]}, {len(text)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
