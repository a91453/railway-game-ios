#!/usr/bin/env python3
"""The overseas maps' buildings, as footprint tiles in their map packs
(`buildings.pmtiles`): Rovaniemi's rule (decision 799) for any map whose
buildings are OpenStreetMap's alone, shared so a new map does not copy
`tools/rovaniemi-map/build_rovaniemi_buildings.py` (whose docstring says
what the rule is) but calls `make` with its own table of uses.

The tiles are Taiwan's (`tools/overture-footprint-tiles/`, `footprints/2`),
written by that tool's encoder as Hong Kong's are
(`tools/hk-map/build_hk_buildings.py`, whose reader of the extract and
table of uses this runs).
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
import build_footprint_tiles as tiles  # noqa: E402
import build_hk_buildings as hk  # noqa: E402
from build_basemap import tile_id, write_pmtiles  # noqa: E402

# Metres a tile's outlines are simplified to, Taiwan's.
TOLERANCE = 0.5
# m²: Hong Kong's for its sheds and shelters (`KEPT_FROM`).
SMALLEST = 30.0
# The tagged buildings a band needs for its quartiles to be used.
KNOWN = 30
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


def overture_layers(path, extent):
    """Overture's machine-drawn buildings of `path` (`overture_extra.py`)
    whose middle is in `extent`, one layer a dataset in
    `overture_extra.DATASETS`' order: (dataset, [(name, use, storeys,
    rings, middle)])."""
    import overture_extra
    found = {dataset: [] for dataset in overture_extra.DATASETS}
    for name, dataset, wkb in overture_extra.read(path):
        if dataset not in found:
            continue
        for part, rings in enumerate(tiles.polygons(wkb)):
            if len(rings[0]) < 3:
                continue
            middle = (sum(lon for lon, _ in rings[0]) / len(rings[0]), sum(lat for _, lat in rings[0]) / len(rings[0]))
            if extent['west'] <= middle[0] <= extent['east'] and extent['south'] <= middle[1] <= extent['north']:
                found[dataset].append((f'ov:{name}/{part}', None, None, rings, middle))
    return list(found.items())


def plateau_layer(rows, extent):
    """PLATEAU's buildings (`tools/fukuoka-map/plateau_buildings.read`)
    whose middle is in `extent`, as a layer, with their measured storeys."""
    out = []
    for name, use, height, storeys, rings in rows:
        middle = (sum(lon for lon, _ in rings[0]) / len(rings[0]), sum(lat for _, lat in rings[0]) / len(rings[0]))
        if extent['west'] <= middle[0] <= extent['east'] and extent['south'] <= middle[1] <= extent['north']:
            out.append((name, use, measured_storeys(height, storeys) or None, rings, middle))
    return 'PLATEAU', out


def added_where_none(layers, osm_kept):
    """The buildings of `layers` (decision 1001: PLATEAU's, then
    Overture's machine outlines), each laid where no building of
    `osm_kept` nor of a layer before it is: (name, layer, use, storeys,
    rings, middle, size) by name, and the report of what was read, laid
    and left out.

    A building is left out when the buildings laid already cover a tenth
    of it, or it covers half of one of them: an outline drawn round a row
    of houses OpenStreetMap has one by one is the same buildings."""
    from shapely import STRtree, Polygon
    laid = [Polygon(rings[0], rings[1:]).buffer(0) for _, _, _, _, _, rings, _ in osm_kept]
    report = {'read': {}, 'laid': {}, 'overlapping': {}, 'small': {}}
    added = []
    for layer, buildings in layers:
        report['read'][layer] = len(buildings)
        tree = STRtree(laid)
        mine, overlapping, small = [], 0, 0
        for name, use, storeys, rings, middle in buildings:
            size = hk.metres_area(rings[0]) - sum(hk.metres_area(hole) for hole in rings[1:] if len(hole) >= 3)
            if size < SMALLEST and use not in LIVED_IN:
                small += 1
                continue
            shape = Polygon(rings[0], rings[1:]).buffer(0)
            if shape.is_empty or shape.area <= 0:
                small += 1
                continue
            covered, swallows = 0.0, False
            for index in tree.query(shape, predicate='intersects'):
                other = laid[index]
                common = shape.intersection(other).area
                covered += common
                if other.area > 0 and common >= 0.5 * other.area:
                    swallows = True
                    break
            if swallows or covered >= 0.1 * shape.area:
                overlapping += 1
                continue
            mine.append(shape)
            added.append((name, layer, use, storeys, rings, middle, size))
        laid += mine
        del tree
        report['laid'][layer], report['overlapping'][layer], report['small'][layer] = len(mine), overlapping, small
    added.sort(key=lambda building: building[0])
    return added, report


def measured_storeys(height, storeys):
    """A PLATEAU building's storeys (decision 1001): its storeys above
    ground where they fit its measured height (2–7 m a storey), else from
    the height as a tagged height is, else the storeys alone."""
    if storeys is not None and not 0 < storeys < 200:
        storeys = None
    if storeys and height and 2.0 <= height / storeys <= 7.0:
        return storeys
    if height and height > 0:
        return tiles.storeys_of(None, height)
    return storeys or 0


def measured_by_building(kept, measured, extent):
    """The storeys PLATEAU measured for the buildings of `kept` (decision
    1001), by name, from `measured`'s (longitude, latitude, storeys) of
    each of its buildings' middle: each goes to the smallest outline of
    `kept` its middle is in, and an outline with several takes the tallest
    (a machine outline round a block of PLATEAU's buildings); and the
    report of what was matched. Outlines are found through a grid of
    0.002°, so three million of them fit in memory."""
    cell = 0.002
    grid = {}
    boxes = []
    for index, building in enumerate(kept):
        rings = building[5]
        xs, ys = [lon for lon, _ in rings[0]], [lat for _, lat in rings[0]]
        box = (min(xs), min(ys), max(xs), max(ys))
        boxes.append(box)
        for gx in range(int(box[0] / cell), int(box[2] / cell) + 1):
            for gy in range(int(box[1] / cell), int(box[3] / cell) + 1):
                grid.setdefault((gx, gy), []).append(index)
    found, unmatched, unmeasured, inside = {}, 0, 0, 0
    for x, y, count in measured:
        if not (extent['west'] <= x <= extent['east'] and extent['south'] <= y <= extent['north']):
            continue
        inside += 1
        if not count:
            unmeasured += 1
            continue
        best = None
        for index in grid.get((int(x / cell), int(y / cell)), ()):
            x0, y0, x1, y1 = boxes[index]
            if x0 <= x <= x1 and y0 <= y <= y1 and hk.inside((x, y), kept[index][5][0]):
                size = (x1 - x0) * (y1 - y0)
                if best is None or size < best[0]:
                    best = (size, index)
        if best is None:
            unmatched += 1
            continue
        name = kept[best[1]][0]
        found[name] = max(found.get(name, 0), min(255, count))
    return found, {'read': len(measured), 'inTheMap': inside, 'noHeight': unmeasured,
                   'inNoOutline': unmatched, 'outlinesMeasured': len(found)}


def make(extract, folder, extent, *, title, use_of, report_path, extract_from, decision, write_manifest,
         overture=None, overture_release=None, plateau=None, plateau_from=None):
    """The pack's `buildings.pmtiles` from `extract` over `extent`, with
    Overture's machine-drawn outlines OpenStreetMap does not have when
    `overture` names `overture_extra.py`'s extract (decision 1001); writes
    the report of what was read and made to `report_path` and the pack's
    manifest with `write_manifest(folder)`.

    `plateau` (PLATEAU's buildings, `tools/fukuoka-map/plateau_buildings.read`,
    decision 1001) adds the official outlines OpenStreetMap does not have,
    before Overture's machine ones, and its measured heights give the
    storeys (`cityMap`) of the buildings OpenStreetMap does not tag; they
    join the tagged ones in the quartiles the rest are guessed from."""
    density = tiles.density_lookup(os.path.join(folder, 'population.json'))
    osm, newest = hk.read(extract, extent)

    kept, left = [], {'small': 0}
    for name, kind, levels, height, rings, middle in osm:
        use = use_of.get(kind)
        size = hk.metres_area(rings[0]) - sum(hk.metres_area(hole) for hole in rings[1:] if len(hole) >= 3)
        if size < SMALLEST and use not in LIVED_IN:
            left['small'] += 1
            continue
        key = (hk.group_of(kind, use), tiles.band(density(*middle), tiles.DENSITY_BANDS), tiles.band(size, tiles.AREA_BANDS))
        kept.append((name, kind, use, key, tagged_storeys(levels, height), rings, middle))

    layers = []
    if plateau:
        layers.append(plateau_layer(plateau, extent))
    if overture:
        layers += overture_layers(overture, extent)
    added_report = None
    if layers:
        added, added_report = added_where_none(layers, kept)
        if overture:
            added_report['overture'] = overture_release
        if plateau:
            added_report['plateau'] = plateau_from
        kept = [building + (None,) for building in kept]
        for name, layer, use, storeys, rings, middle, size in added:
            key = (hk.group_of(None, use), tiles.band(density(*middle), tiles.DENSITY_BANDS), tiles.band(size, tiles.AREA_BANDS))
            kept.append((name, layer, use, key, None, rings, middle, storeys))
    else:
        kept = [building + (None,) for building in kept]
    measured_report = None
    if plateau:
        points = [
            (sum(lon for lon, _ in rings[0]) / len(rings[0]), sum(lat for _, lat in rings[0]) / len(rings[0]),
             measured_storeys(height, storeys)) for _, _, height, storeys, rings in plateau]
        unmeasured = [building for building in kept if not building[4] and not building[7]]
        storeys_measured, measured_report = measured_by_building(unmeasured, points, extent)
        kept = [building[:7] + (storeys_measured.get(building[0]),) if not building[4] and not building[7] else building
                for building in kept]

    known = [{}, {}, {}, {}]
    for _, _, _, key, tagged, _, _, metred in kept:
        tagged = tagged or metred
        if tagged:
            for table, at in zip(known, ladder(key)):
                table.setdefault(at, []).append(tagged)
    tables = [{at: hk.quartiles(values) for at, values in table.items()} for table in known]

    storeys, rows, origins = {}, {}, {}
    for name, kind, use, key, tagged, rings, middle, metred in kept:
        wx, wy = tiles.tile_of(*middle)
        if tagged:
            count, origin = tagged, 'tags'
        elif metred:
            count, origin = metred, 'cityMap'
        else:
            count, origin = guessed(tables, key, int(wx * tiles.EXTENT), int(wy * tiles.EXTENT)), 'guess'
        storeys[name] = (max(1, min(255, count)), tiles.STOREYS_FROM.index(origin))
        origins[origin] = origins.get(origin, 0) + 1
        source = kind if name.startswith(('ov:', 'pl:')) else tiles.OSM
        rows.setdefault((int(wx), int(wy)), []).append((name, None, None, use, source, None, middle[0], middle[1],
                                                        hk.wkb(rings)))

    entries, total, raw_bytes = [], 0, 0
    for key in sorted(rows):
        raw, stats = tiles.encode_tile(key, rows[key], TOLERANCE, storeys)
        if not stats[0]:
            continue
        total += stats[0]
        raw_bytes += len(raw)
        entries.append((tile_id(tiles.ZOOM, key[0], key[1]), gzip.compress(raw, 9, mtime=0)))
    metadata = {'name': title, 'format': f'footprints/{tiles.VERSION}', 'zoom': tiles.ZOOM,
                'extent': tiles.EXTENT, 'tolerance': TOLERANCE, 'uses': tiles.USES, 'storeysFrom': tiles.STOREYS_FROM,
                'attribution': 'Outlines, uses and tagged storeys: © OpenStreetMap contributors (ODbL 1.0). Storeys where '
                               'not tagged: this project, from the tagged buildings and WorldPop (CC BY 4.0)',
                'newestEdit': newest}
    if overture or plateau:
        credit = ['Outlines, uses and tagged storeys: © OpenStreetMap contributors (ODbL 1.0)']
        if plateau:
            credit.append('Outlines, uses and measured heights OpenStreetMap does not have: 「3D都市モデル（Project PLATEAU）」'
                          '（国土交通省）を加工して作成 (MLIT\'s terms of use, compatible with CC BY 4.0)')
        if overture:
            credit.append(f'Outlines neither has: Overture Maps Foundation, buildings, release {overture_release} (ODbL 1.0), '
                          'from Microsoft ML Building Footprints (ODbL 1.0) and Qian Shi et al., East Asian buildings, '
                          'doi:10.5281/zenodo.8174931 (CC BY 4.0)')
        credit.append('Storeys neither tagged nor measured: this project, from the tagged and measured buildings and '
                      'WorldPop (CC BY 4.0)')
        metadata['attribution'] = '. '.join(credit)
    out = os.path.join(folder, 'buildings.pmtiles')
    write_pmtiles(out, entries, metadata, (extent['west'], extent['south'], extent['east'], extent['north']),
                  ((extent['west'] + extent['east']) / 2, (extent['south'] + extent['north']) / 2, tiles.ZOOM),
                  tile_type=0, tile_compression=2, zooms=(tiles.ZOOM, tiles.ZOOM))

    counts = sorted(count for count, _ in storeys.values())
    uses = {}
    for name, _, use, _, _, _, _, _ in kept:
        if not name.startswith(('ov:', 'pl:')) or use:
            uses[use or 'none'] = uses.get(use or 'none', 0) + 1
    whole = open(out, 'rb').read()
    report = {
        'decision': decision,
        'extract': {'file': os.path.basename(extract), 'sha256': hashlib.sha256(open(extract, 'rb').read()).hexdigest(),
                    'from': extract_from,
                    'licence': 'ODbL 1.0, © OpenStreetMap contributors', 'newestBuildingEdit': newest,
                    'buildingsRead': len(osm)},
        **({'added': added_report} if added_report else {}),
        **({'plateauHeightsOnOpenStreetMap': measured_report} if measured_report else {}),
        'buildings': total, 'leftOut': left, 'tiles': len(entries),
        'storeysFrom': dict(sorted(origins.items())),
        'uses': dict(sorted(uses.items())),
        'storeys': {'median': counts[len(counts) // 2], 'tallest': counts[-1],
                    'of1': sum(c == 1 for c in counts), 'of2': sum(c == 2 for c in counts),
                    'of3to5': sum(3 <= c <= 5 for c in counts), 'of6andMore': sum(c >= 6 for c in counts)},
        'rawBytes': raw_bytes, 'archiveBytes': len(whole), 'sha256': hashlib.sha256(whole).hexdigest(),
    }
    with open(report_path, 'w') as file:
        json.dump(report, file, indent=1, ensure_ascii=False)
        file.write('\n')
    print(json.dumps(report, indent=1, ensure_ascii=False))
    write_manifest(folder)
    return report


