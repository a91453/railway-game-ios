#!/usr/bin/env python3
"""Hong Kong's buildings, as footprint tiles in its map pack
(`MapPacks/hongkong/buildings.pmtiles`, decisions 712 and 729).

    python3 -I tools/hk-map/build_hk_buildings.py \\
        Building_Outline_Public_<version>_Building_converted.geojson \\
        hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong

The tiles are Taiwan's (`tools/overture-footprint-tiles/`, `footprints/2`:
one gzipped z16 tile of outlines, storeys and uses, in a PMTiles archive),
written by that tool's own encoder, so the 3D map's one reader
(`Map3DFootprints.swift`) reads both.

Decision 729: the outlines and heights are the Lands Department's
(`Building` of its Building and Occupation Permit data, the GeoJSON in
WGS84 on the CSDI Portal): every Tower and Podium, and the Temporary and
Open-sided structures of 30 m² and more. OpenStreetMap
(osmtoday.com's `asia/china/hong_kong.pbf`, read with pyosmium) gives only
what each building is used for, which the Lands Department's data does not
say.

Storeys, in this order:

1. The Lands Department's heights (origin `landsd`): `TopHeight` less the
   base, at the game's 3.2 m a storey. The base is the building's own
   `BaseHeight`, or the Podium's under it where that is lower: a tower's
   `BaseHeight` is the podium's roof (the International Commerce Centre's
   is 29.4 m above Principal Datum), and the 3D map raises every outline
   from the ground. `Storeys` is only compared with, never used (it is
   given for a sixth of them).
2. A Temporary or Open-sided structure with no heights: one storey
   (origin `guess`).
3. A Tower or Podium with no heights: OpenStreetMap's storeys where an
   OpenStreetMap building is matched (origin `tags`), else a guess as
   Taiwan's `heights` step makes it but from the measured buildings
   (origin `guess`): grouped by what they are (GROUPS), the people living
   round them (the pack's `population.json`, WorldPop) and their footprint,
   between the group's lower and upper quartiles, picked by a hash of
   where it stands.

A building's use is that of the OpenStreetMap building it is matched to:
the largest one whose middle is inside it with a use, else the one its
middle is inside. Unmatched, it has none (the 3D map draws it by storeys).

LANDMARKS lists the Lands Department buildings (`BuildingCSUID`) that a
landmark model draws instead (`docs/research/HK_3D_VISUALISATION_MAP_2026-11-13.md`);
they are left out. It is empty until the landmarks are made.

Also writes `tools/hk-map/hk_buildings.json` (what was read and made) and
the pack's `pack.json`.
"""

import gzip
import hashlib
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))
sys.path.insert(0, HERE)
import build_footprint_tiles as tiles  # noqa: E402
import build_hk_mtr  # noqa: E402
from build_basemap import tile_id, write_pmtiles  # noqa: E402

# Metres a tile's outlines are simplified to, Taiwan's.
TOLERANCE = 0.5
LEFT_OUT = {'no', 'roof', 'bridge', 'ruins', 'construction', 'collapsed', 'proposed'}
# Decision 729: the Lands Department's kinds of building block. Temporary
# and Open-sided structures (sheds, covered walkways, bus shelters) are
# kept only from this size (m²), so the 3D map is not strewn with huts.
KEPT_ALWAYS = {'Tower', 'Podium'}
KEPT_FROM = {'Temporary Structure': 30.0, 'Open-sided Structure': 30.0}
# The Lands Department buildings a landmark model draws (BuildingCSUID);
# none yet.
LANDMARKS = []
# Where storeys come from: the tool's list, and the Lands Department's
# heights after it (`Map3DFootprints.StoreysFrom.landsd`).
STOREYS_FROM = tiles.STOREYS_FROM + ['landsd']
# Degrees a cell of the grid the OpenStreetMap buildings are found by.
CELL = 0.002

# OpenStreetMap's `building` to the tiles' use (the tool's `USES`,
# Overture's subtypes). A church is civic, not religious: the 3D map draws
# the religious as Taiwan's temples.
USE = {
    'residential': ['house', 'apartments', 'residential', 'dormitory', 'terrace', 'detached', 'semidetached_house', 'bungalow',
                    'static_caravan', 'houseboat', 'cabin'],
    'commercial': ['commercial', 'retail', 'office', 'hotel', 'supermarket', 'kiosk'],
    'industrial': ['industrial', 'warehouse', 'storage_tank', 'manufacture', 'silo', 'hangar', 'digester'],
    'outbuilding': ['shed', 'garage', 'garages', 'hut', 'carport', 'container'],
    'education': ['school', 'university', 'college', 'kindergarten'],
    'medical': ['hospital', 'clinic'],
    'religious': ['temple', 'shrine', 'monastery'],
    'civic': ['civic', 'public', 'government', 'fire_station', 'toilets', 'church', 'chapel', 'cathedral', 'mosque', 'synagogue',
              'police', 'library', 'museum'],
    'transportation': ['train_station', 'transportation', 'parking', 'ferry_terminal'],
    'entertainment': ['grandstand', 'stadium', 'sports_hall', 'sports_centre', 'pavilion'],
    'service': ['service', 'transformer_tower', 'substation'],
    'agricultural': ['stable', 'farm', 'farm_auxiliary', 'barn', 'greenhouse', 'cowshed', 'sty'],
}
USE_OF = {value: use for use, values in USE.items() for value in values}

# What a building is, for guessing its storeys: Taiwan's three groups, and
# houses apart from flats (a New Territories village house is three
# storeys by law, a block of flats thirty).
HOUSES = {'house', 'detached', 'semidetached_house', 'bungalow', 'terrace', 'cabin', 'static_caravan'}


def group_of(kind, use):
    if kind in HOUSES:
        return 'houses'
    return tiles.group_of(use)


def number(text):
    """The leading number of a tag's value (`12`, `12.5`, `45 m`), or None."""
    if not text:
        return None
    digits = ''
    for character in text.strip():
        if character.isdigit() or (character == '.' and '.' not in digits):
            digits += character
        else:
            break
    try:
        return float(digits)
    except ValueError:
        return None


def wkb(rings):
    """A WKB polygon of `rings` of (lon, lat)."""
    out = bytearray(struct.pack('<BII', 1, 3, len(rings)))
    for ring in rings:
        out += struct.pack('<I', len(ring))
        for lon, lat in ring:
            out += struct.pack('<dd', lon, lat)
    return bytes(out)


def metres_area(ring):
    """The area of a ring of (lon, lat), m²."""
    lat0 = sum(lat for _, lat in ring) / len(ring)
    kx = math.radians(1) * tiles.EARTH * math.cos(math.radians(lat0))
    ky = math.radians(1) * tiles.EARTH
    total = 0.0
    for i in range(len(ring)):
        x1, y1 = ring[i - 1]
        x2, y2 = ring[i]
        total += (x1 * kx) * (y2 * ky) - (x2 * kx) * (y1 * ky)
    return abs(total) / 2


def read(path, extent):
    """The extract's buildings in `extent`: (id, kind, levels, height,
    rings of (lon, lat), middle (lon, lat)) by id, and the newest edit."""
    import osmium  # pyosmium.
    found, newest = [], [None]

    class Handler(osmium.SimpleHandler):
        def area(self, area):
            kind = area.tags.get('building')
            if kind is None or kind in LEFT_OUT or area.tags.get('location') == 'underground':
                return
            levels = number(area.tags.get('building:levels'))
            height = number(area.tags.get('height'))
            name = ('w' if area.from_way() else 'r') + str(area.orig_id())
            if area.tags.get('office') or area.tags.get('shop'):
                kind = kind if kind in USE_OF else 'commercial'
            for part, outer in enumerate(area.outer_rings()):
                rings = [[(node.lon, node.lat) for node in outer]]
                rings += [[(node.lon, node.lat) for node in inner] for inner in area.inner_rings(outer)]
                rings = [ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else ring for ring in rings]
                if len(rings[0]) < 3:
                    continue
                middle = (sum(lon for lon, _ in rings[0]) / len(rings[0]), sum(lat for _, lat in rings[0]) / len(rings[0]))
                if not (extent['west'] <= middle[0] <= extent['east'] and extent['south'] <= middle[1] <= extent['north']):
                    continue
                found.append((f'{name}/{part}', kind, levels, height, rings, middle))
            stamp = area.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ') if hasattr(area, 'timestamp') else None
            if stamp:
                newest[0] = max(newest[0] or stamp, stamp)

    Handler().apply_file(path)
    found.sort(key=lambda building: building[0])
    return found, newest[0]


def quartiles(values):
    values = sorted(values)

    def q(p):
        return values[min(len(values) - 1, int(p * len(values)))]
    return {'known': len(values), 'p25': q(0.25), 'median': q(0.5), 'p75': q(0.75)}


def inside(point, ring):
    """Whether (lon, lat) `point` is inside `ring` (even-odd)."""
    x, y = point
    hit = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def within(point, rings):
    return inside(point, rings[0]) and not any(inside(point, hole) for hole in rings[1:])


def middle_of(ring):
    return (sum(lon for lon, _ in ring) / len(ring), sum(lat for _, lat in ring) / len(ring))


def cell_of(point):
    return (int(math.floor(point[0] / CELL)), int(math.floor(point[1] / CELL)))


def cells_over(ring):
    west, east = min(p[0] for p in ring), max(p[0] for p in ring)
    south, north = min(p[1] for p in ring), max(p[1] for p in ring)
    (x0, y0), (x1, y1) = cell_of((west, south)), cell_of((east, north))
    return [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]


def read_landsd(path, extent):
    """The Lands Department's buildings in `extent`: dicts of id, block,
    base, top, storeys (the field, for comparing), name, rings, middle,
    area, sorted by id; and what was left out, by why."""
    with open(path, encoding='utf-8') as file:
        data = json.load(file)
    found, left = [], {}
    for feature in data['features']:
        properties, geometry = feature['properties'], feature['geometry']
        block = properties.get('BuildingBlockType')
        if properties.get('Status') != 'Active':
            left['inactive'] = left.get('inactive', 0) + 1
            continue
        polygons = geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]
        for part, polygon in enumerate(polygons):
            rings = [[(lon, lat) for lon, lat, *_ in ring] for ring in polygon]
            rings = [ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else ring for ring in rings]
            if len(rings[0]) < 3:
                left['degenerate'] = left.get('degenerate', 0) + 1
                continue
            size = metres_area(rings[0]) - sum(metres_area(hole) for hole in rings[1:] if len(hole) >= 3)
            if block not in KEPT_ALWAYS and size < KEPT_FROM.get(block, float('inf')):
                key = 'small ' + str(block)
                left[key] = left.get(key, 0) + 1
                continue
            middle = middle_of(rings[0])
            if not (extent['west'] <= middle[0] <= extent['east'] and extent['south'] <= middle[1] <= extent['north']):
                left['outside'] = left.get('outside', 0) + 1
                continue
            uid = properties.get('BuildingCSUID') or str(properties['OBJECTID'])
            if uid in LANDMARKS:
                left['landmark'] = left.get('landmark', 0) + 1
                continue
            found.append({'id': f"{uid}/{part}", 'block': block, 'base': properties.get('BaseHeight'),
                          'top': properties.get('TopHeight'), 'storeys': properties.get('Storeys'),
                          'name': properties.get('BuildingNameEN'), 'nameTC': properties.get('BuildingNameTC'),
                          'rings': rings, 'middle': middle, 'area': size})
    found.sort(key=lambda building: building['id'])
    return found, dict(sorted(left.items()))


def lowest_bases(buildings):
    """Each building's base: its own, or a Podium's it stands on where
    that is lower (a tower's `BaseHeight` is the podium's roof)."""
    podiums = {}
    for index, building in enumerate(buildings):
        if building['block'] == 'Podium' and building['base'] is not None:
            for cell in cells_over(building['rings'][0]):
                podiums.setdefault(cell, []).append(index)
    bases = []
    for building in buildings:
        base = building['base']
        if base is not None and building['block'] != 'Podium':
            for index in podiums.get(cell_of(building['middle']), []):
                podium = buildings[index]
                if podium['base'] < base and within(building['middle'], podium['rings']):
                    base = podium['base']
        bases.append(base)
    return bases


def matched_osm(buildings, osm):
    """For each Lands Department building, the OpenStreetMap building
    matched to it (an index into `osm`) or None: the largest one with a
    use whose middle is inside it, else the one its middle is inside."""
    grid = {}
    for index, (_, kind, levels, height, rings, middle) in enumerate(osm):
        grid.setdefault(cell_of(middle), []).append(index)
    sizes = [metres_area(rings[0]) for _, _, _, _, rings, _ in osm]
    # The OpenStreetMap outlines by the cells they reach, for the second test.
    over = {}
    for index, (_, _, _, _, rings, _) in enumerate(osm):
        for cell in cells_over(rings[0]):
            over.setdefault(cell, []).append(index)
    out = []
    for building in buildings:
        inner = [index for cell in cells_over(building['rings'][0]) for index in grid.get(cell, [])
                 if within(osm[index][5], building['rings'])]
        with_use = [index for index in inner if USE_OF.get(osm[index][1])]
        pick = max(with_use, key=lambda index: sizes[index]) if with_use else None
        if pick is None:
            around = [index for index in over.get(cell_of(building['middle']), []) if within(building['middle'], osm[index][4])]
            pick = (min(around, key=lambda index: sizes[index]) if around else
                    max(inner, key=lambda index: sizes[index]) if inner else None)
        out.append(pick)
    return out


def main(landsd_path, extract, folder):
    extent = build_hk_mtr.EXTENT
    density = tiles.density_lookup(os.path.join(folder, 'population.json'))
    buildings, left = read_landsd(landsd_path, extent)
    osm, newest = read(extract, extent)
    matches = matched_osm(buildings, osm)
    bases = lowest_bases(buildings)

    # Each building's use, group, bands and measured storeys.
    facts, known = [], {}
    for building, match, base in zip(buildings, matches, bases):
        kind = osm[match][1] if match is not None else None
        use = USE_OF.get(kind)
        key = (group_of(kind, use), tiles.band(density(*building['middle']), tiles.DENSITY_BANDS),
               tiles.band(building['area'], tiles.AREA_BANDS))
        measured = None
        if building['top'] is not None and base is not None and building['top'] > base:
            measured = tiles.storeys_of(None, building['top'] - base)
        facts.append((use, key, measured))
        if measured and building['block'] in KEPT_ALWAYS:
            known.setdefault(key, []).append(measured)
    table = {key: quartiles(values) for key, values in known.items()}

    storeys, rows, origins = {}, {}, {}
    for building, match, (use, key, measured) in zip(buildings, matches, facts):
        name, middle = building['id'], building['middle']
        wx, wy = tiles.tile_of(*middle)
        if measured:
            count, origin = measured, 'landsd'
        elif building['block'] not in KEPT_ALWAYS:
            count, origin = 1, 'guess'
        else:
            levels, height = (osm[match][2], osm[match][3]) if match is not None else (None, None)
            if levels and height and levels * 2 > height:
                levels = None
            tagged = tiles.storeys_of(round(levels) if levels and levels >= 1 else None, height)
            if tagged:
                count, origin = tagged, 'tags'
            else:
                count = tiles.proposed_storeys(table, key[0], tiles.DENSITY_BANDS[key[1]], building['area'],
                                               int(wx * tiles.EXTENT), int(wy * tiles.EXTENT))
                origin = 'guess'
        storeys[name] = (max(1, min(255, count)), STOREYS_FROM.index(origin))
        origins[origin] = origins.get(origin, 0) + 1
        # Not OpenStreetMap's (the tiles' dataset bit): the outline is the
        # Lands Department's.
        rows.setdefault((int(wx), int(wy)), []).append((name, None, None, use, 'LandsD', None, middle[0], middle[1],
                                                        wkb(building['rings'])))

    entries, total, raw_bytes = [], 0, 0
    for key in sorted(rows):
        raw, stats = tiles.encode_tile(key, rows[key], TOLERANCE, storeys)
        if not stats[0]:
            continue
        total += stats[0]
        raw_bytes += len(raw)
        entries.append((tile_id(tiles.ZOOM, key[0], key[1]), gzip.compress(raw, 9, mtime=0)))
    metadata = {'name': 'Hong Kong building footprints', 'format': f'footprints/{tiles.VERSION}', 'zoom': tiles.ZOOM,
                'extent': tiles.EXTENT, 'tolerance': TOLERANCE, 'uses': tiles.USES, 'storeysFrom': STOREYS_FROM,
                'attribution': 'Outlines and heights: Building, Lands Department, Government of the Hong Kong SAR, via the '
                               'CSDI Portal. Uses: © OpenStreetMap contributors (ODbL 1.0). Storeys where not measured: '
                               'this project, from the measured buildings and WorldPop (CC BY 4.0)',
                'newestEdit': newest}
    out = os.path.join(folder, 'buildings.pmtiles')
    write_pmtiles(out, entries, metadata, (extent['west'], extent['south'], extent['east'], extent['north']),
                  ((extent['west'] + extent['east']) / 2, (extent['south'] + extent['north']) / 2, tiles.ZOOM),
                  tile_type=0, tile_compression=2, zooms=(tiles.ZOOM, tiles.ZOOM))

    def share(values, least):
        return round(sum(v >= least for v in values) / max(1, len(values)), 4)
    counts = [count for count, _ in storeys.values()]
    lasting = [building for building in buildings if building['block'] in KEPT_ALWAYS]
    heights = sorted(((building['top'] - base, building) for building, base in zip(buildings, bases)
                      if building['top'] is not None and base is not None), key=lambda pair: -pair[0])
    tallest = heights[0][1] if heights else None
    # `Storeys` beside the measured storeys, where both are given.
    pairs = [(building['storeys'], fact[2]) for building, fact in zip(buildings, facts) if building['storeys'] and fact[2]]
    off = sorted(abs(given - measured) / given for given, measured in pairs)
    whole = open(out, 'rb').read()
    report = {
        'landsd': {'file': os.path.basename(landsd_path), 'sha256': hashlib.sha256(open(landsd_path, 'rb').read()).hexdigest(),
                   'dataset': 'landsd_rcd_1637211194312_35158',
                   'licence': 'CSDI Portal Terms and Conditions of Use; Lands Department, Government of the Hong Kong SAR',
                   'leftOut': left},
        'extract': {'file': os.path.basename(extract), 'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
                    'from': 'https://osmtoday.com/asia/china/hong_kong.pbf', 'licence': 'ODbL 1.0, © OpenStreetMap contributors',
                    'newestBuildingEdit': newest, 'buildingsRead': len(osm)},
        'buildings': total, 'read': len(buildings),
        'blocks': {block: sum(b['block'] == block for b in buildings) for block in sorted({b['block'] for b in buildings})},
        'tiles': len(entries),
        'storeysFrom': dict(sorted(origins.items())),
        'measuredShareOfTowersAndPodiums': round(sum(fact[2] is not None for b, fact in zip(buildings, facts)
                                                    if b['block'] in KEPT_ALWAYS) / max(1, len(lasting)), 4),
        'onPodium': sum(base is not None and building['base'] is not None and base < building['base']
                        for building, base in zip(buildings, bases)),
        'withUse': sum(fact[0] is not None for fact in facts),
        'over100m': sum(h >= 100 for h, _ in heights), 'over150m': sum(h >= 150 for h, _ in heights),
        'over200m': sum(h >= 200 for h, _ in heights),
        'tallest': {'metres': round(heights[0][0], 1), 'name': tallest['name'], 'nameTC': tallest['nameTC'],
                    'id': tallest['id'], 'top': tallest['top'], 'base': tallest['base']} if tallest else None,
        'storeysFieldCompared': {'buildings': len(pairs), 'medianRelativeDifference': off[len(off) // 2] if off else None,
                                 'within20Percent': round(sum(o <= 0.2 for o in off) / max(1, len(off)), 4)},
        'storeys': {'median': sorted(counts)[len(counts) // 2], 'tallest': max(counts),
                    'share10': share(counts, 10), 'share20': share(counts, 20), 'share40': share(counts, 40)},
        'landmarks': LANDMARKS,
        'rawBytes': raw_bytes, 'archiveBytes': len(whole), 'sha256': hashlib.sha256(whole).hexdigest(),
    }
    with open(os.path.join(HERE, 'hk_buildings.json'), 'w') as file:
        json.dump(report, file, indent=1, ensure_ascii=False)
        file.write('\n')
    print(json.dumps(report, indent=1, ensure_ascii=False))
    build_hk_mtr.write_manifest(folder)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
