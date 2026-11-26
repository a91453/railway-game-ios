#!/usr/bin/env python3
"""Rovaniemi's buildings, as footprint tiles in its map pack
(`MapPacks/rovaniemi/buildings.pmtiles`, decisions 799 and 1009).

    python3 -I tools/rovaniemi-map/mml_buildings.py fetch /tmp/rv/mml
    python3 -I tools/rovaniemi-map/build_rovaniemi_buildings.py \\
        /tmp/rv/mml rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi

The tiles are Taiwan's (`tools/overture-footprint-tiles/`, `footprints/2`:
one gzipped z16 tile of outlines, storeys and uses, in a PMTiles archive),
written by that tool's own encoder as Hong Kong's are
(`tools/hk-map/build_hk_buildings.py`), so the 3D map's one reader
(`Map3DFootprints.swift`) reads all of them.

Decision 1009: official first, as Hong Kong's are the Lands Department's.
The outlines are the National Land Survey of Finland's (MML,
`mml_buildings.py`: the Topographic Database's `Rakennus`, CC BY 4.0), and
OpenStreetMap (osmtoday.com's `europe/finland.pbf` or openstreetmap.fr's
`europe/finland/lapland`, cut to the map as the README says, read with
pyosmium) gives what each is used for where it says more than MML's five
classes, and the buildings MML has not drawn yet. Laid in this order, each
only where none before it stands (`overlapping`: one that the outlines
laid already cover a tenth of, or that covers half of one of them, is the
same building):

1. MML's Topographic Database: every building, its use class and its
   storeys class (one or two, three or more).
2. MML's Buildings 3D (the 2022 laser scan of Rovaniemi) where the
   Topographic Database has no outline: its ground.
3. OpenStreetMap's.

Left out: a building under SMALLEST m² that is not somewhere people live
or work (the saunas, wood stores and carports beside every house, MML's
`muu rakennus`, which the 3D map would strew round each house as boxes).

A building's use is that of the OpenStreetMap building matched to it
(Hong Kong's `matched_osm`: the largest one with a use whose middle is
inside it, else the one its middle is inside) when its `building` tag has
a use (Hong Kong's table, with Finland's `sauna`, `outbuilding`,
`boathouse` and `allotment_house`), else MML's class (`MTK_USE`).

Storeys, in this order:

1. MML's measured height (origin `mml`): Buildings 3D's eaves, the
   foot of its roof over the ground (`mml_buildings.read_lod2`), at the
   game's 3.2 m a storey (the ridge, its `measuredHeight`, or the roof's
   middle would stand a one-storey gabled house two storeys tall), kept
   within the Topographic Database's storeys class. A Topographic
   Database outline takes the tallest of the 3D buildings whose ground's
   middle is inside it.
2. OpenStreetMap's `building:levels`, or its `height` (origin `tags`),
   as decision 799 reads them, within the class too.
3. A guess (origin `guess`), as decision 799 makes it but from the
   measured and tagged buildings: grouped by what they are, the people
   round them (the pack's `population.json`) and their footprint, between
   the group's lower and upper quartiles, picked by a hash of where it
   stands, then kept within its storeys class (three where MML says three
   or more, two at most where it says one or two).

Also writes `tools/rovaniemi-map/rovaniemi_buildings.json` (what was read
and made) and the pack's `pack.json`.
"""

import gzip
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'overseas-map'))
sys.path.insert(0, os.path.join(HERE, '..', 'hk-map'))
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
sys.path.insert(0, HERE)
import build_footprint_tiles as tiles  # noqa: E402
import build_hk_buildings as hk  # noqa: E402
import build_rovaniemi_rail  # noqa: E402
import mml_buildings as mml  # noqa: E402
import overseas_buildings  # noqa: E402
from build_basemap import tile_id, write_pmtiles  # noqa: E402

USE_OF = dict(hk.USE_OF, sauna='outbuilding', outbuilding='outbuilding', boathouse='outbuilding',
              allotment_house='residential')
# `Map3DFootprints.StoreysFrom.mml`: after Hong Kong's `landsd`.
STOREYS_FROM = hk.STOREYS_FROM + ['mml']
SMALLEST = overseas_buildings.SMALLEST
LIVED_IN = overseas_buildings.LIVED_IN
# The tiles' dataset bit: not OpenStreetMap's.
MML = 'MML'


def within_class(count, floors):
    """`count` storeys kept within MML's class: 1 (one or two), 2 (three
    or more), 0 (none given)."""
    if floors == 1:
        return min(count, 2)
    if floors == 2:
        return max(count, 3)
    return count


def measured_on(buildings, scanned):
    """For each of `buildings` (dicts of rings and middle), the storeys of
    the tallest of `scanned` (Buildings 3D) whose ground's middle is inside
    it, or None; and the indices of `scanned` inside none."""
    grid = {}
    for index, building in enumerate(buildings):
        for cell in hk.cells_over(building['rings'][0]):
            grid.setdefault(cell, []).append(index)
    found, alone = [None] * len(buildings), []
    for index, scan in enumerate(scanned):
        homes = [at for at in grid.get(hk.cell_of(scan['middle']), []) if hk.within(scan['middle'], buildings[at]['rings'])]
        if not homes:
            alone.append(index)
            continue
        count = tiles.storeys_of(None, scan['eaves']) if scan['eaves'] > 0 else 0
        for at in homes:
            if count and (found[at] is None or count > found[at]):
                found[at] = count
    return found, alone


def where_none(laid, candidates):
    """The candidates (dicts of rings) that stand where none of `laid`
    (shapely shapes) does: those the laid cover less than a tenth of and
    that cover less than half of any of them; and how many overlapped."""
    from shapely import STRtree, Polygon
    tree = STRtree(laid)
    kept, overlapping = [], 0
    for candidate in candidates:
        shape = Polygon(candidate['rings'][0], candidate['rings'][1:]).buffer(0)
        if shape.is_empty or shape.area <= 0:
            overlapping += 1
            continue
        covered, swallows = 0.0, False
        for index in tree.query(shape, predicate='intersects'):
            common = shape.intersection(laid[index]).area
            covered += common
            if laid[index].area > 0 and common >= 0.5 * laid[index].area:
                swallows = True
                break
        if swallows or covered >= 0.1 * shape.area:
            overlapping += 1
            continue
        kept.append(candidate)
    return kept, overlapping


def shapes(buildings):
    from shapely import Polygon
    return [Polygon(b['rings'][0], b['rings'][1:]).buffer(0) for b in buildings]


def main(mml_folder, extract, folder):
    extent = build_rovaniemi_rail.EXTENT
    density = tiles.density_lookup(os.path.join(folder, 'population.json'))
    topo, topo_report = mml.read_mtk(mml_folder, extent)
    scanned, scan_report = mml.read_lod2(mml_folder, extent)
    osm, newest = hk.read(extract, extent)

    # 1. The Topographic Database's buildings, with their 3D heights.
    for building in topo:
        building['origin'] = 'mtk'
    measured, alone = measured_on(topo, scanned)
    for building, count in zip(topo, measured):
        building['measured'] = count
    # 2. Buildings 3D where the Topographic Database has no outline.
    scans = [{'id': 'mml3d:' + scanned[index]['id'], 'rings': [scanned[index]['ground']],
              'middle': scanned[index]['middle'], 'use': 0, 'floors': 0, 'origin': 'lod2',
              'measured': tiles.storeys_of(None, scanned[index]['eaves']) if scanned[index]['eaves'] > 0 else None}
             for index in alone]
    scans, scans_overlapping = where_none(shapes(topo), scans)
    official = topo + scans
    # 3. OpenStreetMap's where MML has none.
    osm_buildings = [{'id': name, 'kind': kind, 'levels': levels, 'height': height, 'rings': rings, 'middle': middle,
                      'use': 0, 'floors': 0, 'origin': 'osm', 'measured': None}
                     for name, kind, levels, height, rings, middle in osm]
    added, osm_overlapping = where_none(shapes(official), osm_buildings)

    # Each building's use, group, bands and storeys before the guess.
    matches = hk.matched_osm(official, osm)
    facts, left = [], {'small': {'mtk': 0, 'lod2': 0, 'osm': 0}}
    with_osm_use = 0
    for building, match in zip(official + added, matches + [None] * len(added)):
        if building['origin'] == 'osm':
            kind, levels, height = building['kind'], building['levels'], building['height']
        elif match is not None:
            kind, levels, height = osm[match][1], osm[match][2], osm[match][3]
        else:
            kind, levels, height = None, None, None
        use = USE_OF.get(kind)
        if use and building['origin'] != 'osm':
            with_osm_use += 1
        if not use and building['use'] in mml.MTK_USE:
            use, kind = mml.MTK_USE[building['use']]
            if kind == 'house' and building['floors'] == 2:
                kind = 'apartments'
        size = hk.metres_area(building['rings'][0]) - sum(hk.metres_area(hole) for hole in building['rings'][1:]
                                                          if len(hole) >= 3)
        if size < SMALLEST and use not in LIVED_IN:
            left['small'][building['origin']] += 1
            continue
        key = (hk.group_of(kind, use), tiles.band(density(*building['middle']), tiles.DENSITY_BANDS),
               tiles.band(size, tiles.AREA_BANDS))
        tagged = overseas_buildings.tagged_storeys(levels, height)
        facts.append((building, use, key, building['measured'], tagged))

    known = [{}, {}, {}, {}]
    for building, _, key, metred, tagged in facts:
        count = within_class(metred or tagged, building['floors']) if (metred or tagged) else 0
        if count:
            for table, at in zip(known, overseas_buildings.ladder(key)):
                table.setdefault(at, []).append(count)
    tables = [{at: hk.quartiles(values) for at, values in table.items()} for table in known]

    storeys, rows, origins, outlines = {}, {}, {}, {}
    against = {'agrees': 0, 'raised': 0, 'lowered': 0}
    for building, use, key, metred, tagged in facts:
        name, middle = building['id'], building['middle']
        wx, wy = tiles.tile_of(*middle)
        if metred:
            count, origin = metred, 'mml'
        elif tagged:
            count, origin = tagged, 'tags'
        else:
            count = overseas_buildings.guessed(tables, key, int(wx * tiles.EXTENT), int(wy * tiles.EXTENT))
            origin = 'guess'
        kept = within_class(count, building['floors'])
        if building['floors'] and origin != 'guess':
            against['agrees' if kept == count else 'raised' if kept > count else 'lowered'] += 1
        storeys[name] = (max(1, min(255, kept)), STOREYS_FROM.index(origin))
        origins[origin] = origins.get(origin, 0) + 1
        outlines[building['origin']] = outlines.get(building['origin'], 0) + 1
        source = tiles.OSM if building['origin'] == 'osm' else MML
        rows.setdefault((int(wx), int(wy)), []).append((name, None, None, use, source, None, middle[0], middle[1],
                                                        hk.wkb(building['rings'])))

    entries, total, raw_bytes = [], 0, 0
    for key in sorted(rows):
        raw, stats = tiles.encode_tile(key, rows[key], overseas_buildings.TOLERANCE, storeys)
        if not stats[0]:
            continue
        total += stats[0]
        raw_bytes += len(raw)
        entries.append((tile_id(tiles.ZOOM, key[0], key[1]), gzip.compress(raw, 9, mtime=0)))
    metadata = {'name': 'Rovaniemi building footprints', 'format': f'footprints/{tiles.VERSION}', 'zoom': tiles.ZOOM,
                'extent': tiles.EXTENT, 'tolerance': overseas_buildings.TOLERANCE, 'uses': tiles.USES,
                'storeysFrom': STOREYS_FROM,
                'attribution': 'Outlines, use classes, storeys classes and measured heights: contains data from the '
                               'National Land Survey of Finland Topographic Database and Buildings 3D (2022), '
                               'CC BY 4.0. Uses and the outlines MML has not drawn: © OpenStreetMap contributors '
                               '(ODbL 1.0). Storeys neither measured nor tagged: this project, from the measured and '
                               'tagged buildings and population.json',
                'newestEdit': newest}
    out = os.path.join(folder, 'buildings.pmtiles')
    write_pmtiles(out, entries, metadata, (extent['west'], extent['south'], extent['east'], extent['north']),
                  ((extent['west'] + extent['east']) / 2, (extent['south'] + extent['north']) / 2, tiles.ZOOM),
                  tile_type=0, tile_compression=2, zooms=(tiles.ZOOM, tiles.ZOOM))

    counts = sorted(count for count, _ in storeys.values())
    uses = {}
    for _, use, _, _, _ in facts:
        uses[use or 'none'] = uses.get(use or 'none', 0) + 1
    whole = open(out, 'rb').read()
    report = {
        'decision': 1009,
        'mml': {'topographicDatabase': {**topo_report, 'from': mml.MTK_URL.rsplit('/', 4)[0] + '/'},
                'buildings3D': {**scan_report, 'from': mml.LOD2_URL, 'insideNoOutline': len(alone),
                                'laidWhereNone': len(scans), 'overlapping': scans_overlapping},
                'licence': mml.LICENCE},
        'extract': {'file': os.path.basename(extract), 'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
                    'from': 'https://download.openstreetmap.fr/extracts/europe/finland/lapland-latest.osm.pbf, cut with '
                            'osmium extract -b 25.15,66.27,27.65,66.83 -s smart',
                    'licence': 'ODbL 1.0, © OpenStreetMap contributors', 'newestBuildingEdit': newest,
                    'buildingsRead': len(osm), 'laidWhereNone': len(added), 'overlapping': osm_overlapping,
                    'usesGivenToMml': with_osm_use},
        'buildings': total, 'outlines': dict(sorted(outlines.items())), 'leftOut': left, 'tiles': len(entries),
        'storeysFrom': dict(sorted(origins.items())),
        'measuredAgainstClass': against,
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
    return report


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
