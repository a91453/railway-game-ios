#!/usr/bin/env python3
"""Rovaniemi's buildings, as footprint tiles in its map pack
(`MapPacks/rovaniemi/buildings.pmtiles`, decision 799).

    python3 -I tools/rovaniemi-map/build_rovaniemi_buildings.py \\
        rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi

The tiles are Taiwan's (`tools/overture-footprint-tiles/`, `footprints/2`:
one gzipped z16 tile of outlines, storeys and uses, in a PMTiles archive),
written by that tool's own encoder as Hong Kong's are
(`tools/hk-map/build_hk_buildings.py`, whose reader of the extract and
table of uses this one runs), so the 3D map's one reader
(`Map3DFootprints.swift`) reads all three.

Everything is OpenStreetMap's (osmtoday.com's `europe/finland.pbf`, cut to
the map as the README says and read with pyosmium): Finland's National
Land Survey has no key-free download (decision 789), and Lapland has no
measured heights like Hong Kong's Lands Department's.

Left out: a building under SMALLEST m² that is not tagged as somewhere
people live or work (the sheds, wood stores and carports beside every
house, a third of the extract, which the 3D map would strew round each
house as boxes).

Storeys, in this order:

1. OpenStreetMap's `building:levels`, or its `height` at the game's 3.2 m
   a storey (origin `tags`); levels that would make a storey under half a
   metre of the tagged height are a slip and are not used, as in Hong
   Kong's tool.
2. A guess from the tagged buildings (origin `guess`), as Taiwan's
   `heights` step makes it: grouped by what they are (the tool's groups,
   and houses apart from flats), the people living round them (the pack's
   `population.json`, WorldPop) and their footprint, between the group's
   lower and upper quartiles, picked by a hash of where it stands. One in
   fifty of Rovaniemi's buildings is tagged, so a band with fewer than
   KNOWN tagged buildings takes every group's of the same footprint among
   as many people (so a village hall is not guessed from the town's
   flats), then its group's of that footprint anywhere, then every
   group's, then one storey. (The tool's own fallback, two to four
   storeys, is Taiwan's towns; here it would have stood four storeys on
   a lakeside cabin.)

A building's use is its `building` tag's (Hong Kong's table, with
Finland's `sauna`, `outbuilding`, `boathouse` and `allotment_house`).

Also writes `tools/rovaniemi-map/rovaniemi_buildings.json` (what was read
and made) and the pack's `pack.json`.
"""

import gzip
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
sys.path.insert(0, os.path.join(HERE, '..', 'hk-map'))
sys.path.insert(0, HERE)
import build_footprint_tiles as tiles  # noqa: E402
import build_hk_buildings as hk  # noqa: E402
import build_rovaniemi_rail  # noqa: E402
from build_basemap import tile_id, write_pmtiles  # noqa: E402

# Metres a tile's outlines are simplified to, Taiwan's.
TOLERANCE = 0.5
# m²: Hong Kong's for its sheds and shelters (`KEPT_FROM`).
SMALLEST = 30.0
# The tagged buildings a band needs for its quartiles to be used.
KNOWN = 30
USE_OF = dict(hk.USE_OF, sauna='outbuilding', outbuilding='outbuilding', boathouse='outbuilding',
              allotment_house='residential')
# The uses a small building is kept for.
LIVED_IN = {'residential', 'commercial', 'education', 'medical', 'religious', 'civic', 'transportation', 'entertainment'}


def tagged_storeys(levels, height):
    if levels and height and levels * 2 > height:
        levels = None
    return tiles.storeys_of(round(levels) if levels and levels >= 1 else None, height)


def guessed(tables, key, x, y):
    """A building of unknown storeys: between the quartiles of the first of
    its band, its density and footprint, its group and footprint, and its
    footprint alone that has KNOWN tagged buildings, picked by the tool's
    hash of where it is; one storey when none has."""
    for table, at in zip(tables, ladder(key)):
        entry = table.get(at)
        if entry and entry['known'] >= KNOWN:
            low, high = entry['p25'], max(entry['p25'], entry['p75'])
            h = (x * 73856093 ^ y * 19349663) & 0xFFFFFFFF
            h = (h ^ (h >> 13)) * 0x5BD1E995 & 0xFFFFFFFF
            return low + (h ^ (h >> 15)) % (high - low + 1)
    return 1


def ladder(key):
    group, density, size = key
    return key, ('any', density, size), (group, size), size


def main(extract, folder):
    extent = build_rovaniemi_rail.EXTENT
    density = tiles.density_lookup(os.path.join(folder, 'population.json'))
    osm, newest = hk.read(extract, extent)

    kept, left = [], {'small': 0}
    for name, kind, levels, height, rings, middle in osm:
        use = USE_OF.get(kind)
        size = hk.metres_area(rings[0]) - sum(hk.metres_area(hole) for hole in rings[1:] if len(hole) >= 3)
        if size < SMALLEST and use not in LIVED_IN:
            left['small'] += 1
            continue
        key = (hk.group_of(kind, use), tiles.band(density(*middle), tiles.DENSITY_BANDS), tiles.band(size, tiles.AREA_BANDS))
        kept.append((name, kind, use, key, tagged_storeys(levels, height), rings, middle))

    known = [{}, {}, {}, {}]
    for _, _, _, key, tagged, _, _ in kept:
        if tagged:
            for table, at in zip(known, ladder(key)):
                table.setdefault(at, []).append(tagged)
    tables = [{at: hk.quartiles(values) for at, values in table.items()} for table in known]

    storeys, rows, origins = {}, {}, {}
    for name, kind, use, key, tagged, rings, middle in kept:
        wx, wy = tiles.tile_of(*middle)
        if tagged:
            count, origin = tagged, 'tags'
        else:
            count, origin = guessed(tables, key, int(wx * tiles.EXTENT), int(wy * tiles.EXTENT)), 'guess'
        storeys[name] = (max(1, min(255, count)), tiles.STOREYS_FROM.index(origin))
        origins[origin] = origins.get(origin, 0) + 1
        rows.setdefault((int(wx), int(wy)), []).append((name, None, None, use, tiles.OSM, None, middle[0], middle[1],
                                                        hk.wkb(rings)))

    entries, total, raw_bytes = [], 0, 0
    for key in sorted(rows):
        raw, stats = tiles.encode_tile(key, rows[key], TOLERANCE, storeys)
        if not stats[0]:
            continue
        total += stats[0]
        raw_bytes += len(raw)
        entries.append((tile_id(tiles.ZOOM, key[0], key[1]), gzip.compress(raw, 9, mtime=0)))
    metadata = {'name': 'Rovaniemi building footprints', 'format': f'footprints/{tiles.VERSION}', 'zoom': tiles.ZOOM,
                'extent': tiles.EXTENT, 'tolerance': TOLERANCE, 'uses': tiles.USES, 'storeysFrom': tiles.STOREYS_FROM,
                'attribution': 'Outlines, uses and tagged storeys: © OpenStreetMap contributors (ODbL 1.0). Storeys where '
                               'not tagged: this project, from the tagged buildings and WorldPop (CC BY 4.0)',
                'newestEdit': newest}
    out = os.path.join(folder, 'buildings.pmtiles')
    write_pmtiles(out, entries, metadata, (extent['west'], extent['south'], extent['east'], extent['north']),
                  ((extent['west'] + extent['east']) / 2, (extent['south'] + extent['north']) / 2, tiles.ZOOM),
                  tile_type=0, tile_compression=2, zooms=(tiles.ZOOM, tiles.ZOOM))

    counts = sorted(count for count, _ in storeys.values())
    uses = {}
    for _, _, use, _, _, _, _ in kept:
        uses[use or 'none'] = uses.get(use or 'none', 0) + 1
    whole = open(out, 'rb').read()
    report = {
        'decision': 799,
        'extract': {'file': os.path.basename(extract), 'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
                    'from': 'https://osmtoday.com/europe/finland.pbf, cut with osmium extract -b 25.15,66.27,27.65,66.83 -s smart',
                    'licence': 'ODbL 1.0, © OpenStreetMap contributors', 'newestBuildingEdit': newest,
                    'buildingsRead': len(osm)},
        'buildings': total, 'leftOut': left, 'tiles': len(entries),
        'storeysFrom': dict(sorted(origins.items())),
        'uses': dict(sorted(uses.items())),
        'storeys': {'median': counts[len(counts) // 2], 'tallest': counts[-1],
                    'of1': sum(c == 1 for c in counts), 'of2': sum(c == 2 for c in counts),
                    'of3to5': sum(3 <= c <= 5 for c in counts), 'of6andMore': sum(c >= 6 for c in counts)},
        'rawBytes': raw_bytes, 'archiveBytes': len(whole), 'sha256': hashlib.sha256(whole).hexdigest(),
    }
    with open(os.path.join(HERE, 'rovaniemi_buildings.json'), 'w') as file:
        json.dump(report, file, indent=1, ensure_ascii=False)
        file.write('\n')
    print(json.dumps(report, indent=1, ensure_ascii=False))
    build_rovaniemi_rail.write_manifest(folder)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
