#!/usr/bin/env python3
"""Hong Kong's buildings, as footprint tiles in its map pack
(`MapPacks/hongkong/buildings.pmtiles`, decision 712).

    python3 -I tools/hk-map/build_hk_buildings.py hong_kong.pbf \\
        RailwayGameApp/Resources/MapPacks/hongkong

The tiles are Taiwan's (`tools/overture-footprint-tiles/`, `footprints/2`:
one gzipped z16 tile of outlines, storeys and uses, in a PMTiles archive),
written by that tool's own encoder, so the 3D map's one reader
(`Map3DFootprints.swift`) reads both. Taiwan's come from Overture; Hong
Kong's are read straight from OpenStreetMap, osmtoday.com's
`asia/china/hong_kong.pbf` with pyosmium, every `building` whose middle is
in the pack's extent.

Storeys, in this order:

1. `building:levels` (origin `tags`).
2. `height` in metres, at the game's 3.2 m a storey (origin `tags`).
3. A guess (origin `guess`), as Taiwan's `heights` step makes it but from
   Hong Kong's own tagged buildings: the buildings that have storeys are
   grouped by what they are (GROUPS), the people living round them (the
   pack's `population.json`, WorldPop) and their footprint; a building
   without storeys takes one between its group's lower quartile and its
   median, picked by a hash of where it stands, so it never changes (the
   tagged half leans to the towers, so the upper half is not drawn from).
   Half of Hong Kong's buildings are tagged, and its blocks of flats are
   20 to 40 storeys, so the guesses are tall where the city is.

Left out: roofs and canopies (`building=roof`), bridges, ruins, building
sites, and anything underground. `building:part` is not read: an outline
carries its tallest part's storeys.

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


def main(extract, folder):
    extent = build_hk_mtr.EXTENT
    density = tiles.density_lookup(os.path.join(folder, 'population.json'))
    buildings, newest = read(extract, extent)

    # Each building's use, group, bands and tagged storeys.
    facts, known = {}, {}
    for name, kind, levels, height, rings, middle in buildings:
        use = USE_OF.get(kind)
        size = metres_area(rings[0])
        key = (group_of(kind, use), tiles.band(density(*middle), tiles.DENSITY_BANDS), tiles.band(size, tiles.AREA_BANDS))
        # Storeys under 2 m each are a slip of the hand (123 levels on an
        # 18 m building): the height is believed.
        if levels and height and levels * 2 > height:
            levels = None
        tagged = tiles.storeys_of(round(levels) if levels and levels >= 1 else None, height)
        facts[name] = (use, key, size, tagged)
        if tagged:
            known.setdefault(key, []).append(tagged)
    # The tagged buildings are the ones somebody looked up at: the towers
    # more than the sheds. So a guess is drawn from the lower half, the
    # lower quartile to the median, not Taiwan's quartile to quartile.
    table = {key: quartiles(values) for key, values in known.items()}
    for entry in table.values():
        entry['p75'] = entry['median']

    storeys, rows = {}, {}
    for name, kind, levels, height, rings, middle in buildings:
        use, key, size, tagged = facts[name]
        wx, wy = tiles.tile_of(*middle)
        if tagged:
            storeys[name] = (tagged, tiles.STOREYS_FROM.index('tags'))
        else:
            guess = tiles.proposed_storeys(table, key[0], tiles.DENSITY_BANDS[key[1]], size,
                                           int(wx * tiles.EXTENT), int(wy * tiles.EXTENT))
            storeys[name] = (max(1, min(255, guess)), tiles.STOREYS_FROM.index('guess'))
        rows.setdefault((int(wx), int(wy)), []).append((name, None, None, use, tiles.OSM, None, middle[0], middle[1], wkb(rings)))

    entries, total, raw_bytes = [], 0, 0
    for key in sorted(rows):
        raw, stats = tiles.encode_tile(key, rows[key], TOLERANCE, storeys)
        if not stats[0]:
            continue
        total += stats[0]
        raw_bytes += len(raw)
        entries.append((tile_id(tiles.ZOOM, key[0], key[1]), gzip.compress(raw, 9, mtime=0)))
    metadata = {'name': 'Hong Kong building footprints', 'format': f'footprints/{tiles.VERSION}', 'zoom': tiles.ZOOM,
                'extent': tiles.EXTENT, 'tolerance': TOLERANCE, 'uses': tiles.USES, 'storeysFrom': tiles.STOREYS_FROM,
                'attribution': '© OpenStreetMap contributors (ODbL 1.0). Storeys where untagged: this project, '
                               'from the tagged buildings and WorldPop (CC BY 4.0)',
                'newestEdit': newest}
    out = os.path.join(folder, 'buildings.pmtiles')
    write_pmtiles(out, entries, metadata, (extent['west'], extent['south'], extent['east'], extent['north']),
                  ((extent['west'] + extent['east']) / 2, (extent['south'] + extent['north']) / 2, tiles.ZOOM),
                  tile_type=0, tile_compression=2, zooms=(tiles.ZOOM, tiles.ZOOM))

    def share(values, least):
        return round(sum(v >= least for v in values) / max(1, len(values)), 4)
    counts = [count for count, _ in storeys.values()]
    homes = [storeys[name][0] for name, kind, *_ in buildings if facts[name][1][0] == 'homes']
    whole = open(out, 'rb').read()
    report = {
        'extract': {'file': os.path.basename(extract), 'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
                    'from': 'https://osmtoday.com/asia/china/hong_kong.pbf', 'licence': 'ODbL 1.0, © OpenStreetMap contributors',
                    'newestBuildingEdit': newest},
        'buildings': total, 'read': len(buildings), 'tiles': len(entries),
        'storeysFrom': {'tags': sum(origin == 1 for _, origin in storeys.values()),
                        'guess': sum(origin == 0 for _, origin in storeys.values())},
        'storeys': {'median': sorted(counts)[len(counts) // 2], 'tallest': max(counts),
                    'share10': share(counts, 10), 'share20': share(counts, 20), 'share40': share(counts, 40)},
        'flats': {'buildings': len(homes), 'median': sorted(homes)[len(homes) // 2], 'share10': share(homes, 10),
                  'share20': share(homes, 20)},
        'rawBytes': raw_bytes, 'archiveBytes': len(whole), 'sha256': hashlib.sha256(whole).hexdigest(),
    }
    with open(os.path.join(HERE, 'hk_buildings.json'), 'w') as file:
        json.dump(report, file, indent=1)
        file.write('\n')
    print(json.dumps(report, indent=1))
    build_hk_mtr.write_manifest(folder)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
