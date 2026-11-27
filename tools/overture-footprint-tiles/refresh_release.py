#!/usr/bin/env python3
"""A newer Overture release on the bundled Taiwan buildings, house by
house (decision 1026): what the release added goes in, what it took away
comes out, and everything else stays byte for byte, so the storeys of
the usage permits and the registry (decision 1011) and Taichung's own
outlines (decision 1015) stay as they are. A full rebuild would have to
fetch every one of those sources again; a month of Overture changes a
few thousand houses.

    R=tools/overture-footprint-tiles/refresh_release.py
    T=tools/overture-footprint-tiles/build_footprint_tiles.py
    C=../railway-reference-private/Railway/geo-scene-reference-clean/source/public/statistics/county-reference-2025.geojson
    P=RailwayGameApp/Resources/RealWorld/taiwan_population.json
    A=RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles
    python3 -I $R latest                    # the newest release on Overture's S3
    python3 -I $R current $A                # the release the bundled file is on
    python3 -I $T extract 2026-11-18.0 $C new.parquet          # about a minute
    python3 -I $R patch $A new.parquet $C $P 2026-11-18.0 out.pmtiles refresh.json   # about 5 minutes
    cp out.pmtiles $A                       # only when patch exits 0

How (`patch`): each tile of the release is encoded as `build` encodes it
(same simplifying, same rounding), so a house the release did not change
has exactly the rings it has in the bundled file. In each tile:

- a bundled house with a house of the release of the same rings stays,
  its storeys and where they came from as they are; only where they were
  a guess or OpenStreetMap's tags and the release now tags it are the
  tags taken, and the release's use where it has one;
- a bundled house the release has not is gone (pulled down, or redrawn
  by OpenStreetMap), unless it stands in a county whose own outlines
  were laid (`OFFICIAL`, Taichung: those are not in Overture at all);
- a house of the release the bundled file has not comes in, unless the
  houses staying cover a tenth of it or it covers half of one of them
  (decision 1001's rule, as `official_outlines.py` lays Taichung's map:
  so the Overture houses Taichung's map replaced do not come back). Its
  storeys are the release's tags, else the density guess
  (`proposed_storeys`, as `storeys` guesses where GHSL has nothing).

Station landmarks, landmarks and the game's own stations take the houses
under them away when the map is drawn, by where they stand
(`underLandmark`, `replacedPlots`, `underRailway`), never by an id, so
they take the new houses away as they took the old.

Before the file is written the change is checked (`LIMITS`); one that
breaks a limit (a release whose shapes all moved, a county half gone) is
written to the report with what broke and the command exits 3 without
writing the file. The report lists, county by county, the houses kept,
gone and new.

Needs `pip install duckdb` (decision 93) with its spatial extension. The
same inputs give the same bytes.
"""

import collections
import contextlib
import gzip
import hashlib
import io
import json
import math
import multiprocessing
import os
import re
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))

import build_footprint_tiles as T  # noqa: E402
import usage_permits as U  # noqa: E402
from official_outlines import COVERED, SWALLOWS, lonlat, wkt  # noqa: E402

BUCKET = 'https://overturemaps-us-west-2.s3.us-west-2.amazonaws.com/'
# Counties whose own outlines were laid (decision 1015): their houses that
# Overture has not are the city's, and stay.
OFFICIAL = ['66000']
# Degrees round such a county still counted in it (its houses on the line).
OFFICIAL_MARGIN = 0.001
GUESS = T.STOREYS_FROM.index('guess')
TAGS = T.STOREYS_FROM.index('tags')
# What one release may change; over any, nothing is written (exit 3).
LIMITS = {
    # Of the bundled houses outside OFFICIAL, the share whose rings the
    # release still has: under this the release's shapes moved (a new
    # simplifying, a new source), not its houses.
    'keptShareAtLeast': 0.95,
    # A county's houses gone, and new, against what it had (a village
    # OpenStreetMap redrew counts in both), and gone less new.
    'countyGoneAtMost': 0.1,
    'countyNewAtMost': 0.1,
    'countyLostAtMost': 0.03,
    # The whole island's net change.
    'netAtLeast': -0.01,
    'netAtMost': 0.03,
    # A tile of this many houses or more may not lose (gone less new) more
    # than this share of its houses and of the ground they cover.
    'tileHouses': 100,
    'tileLostAtMost': 0.3,
}


def latest():
    """The newest release in the bucket (`release/<date>.<n>/`)."""
    text = urllib.request.urlopen(BUCKET + '?list-type=2&prefix=release/&delimiter=/').read().decode()
    releases = re.findall(r'<Prefix>release/(\d{4}-\d{2}-\d{2}\.\d+)/</Prefix>', text)
    if not releases:
        sys.exit('no release in the bucket')
    return max(releases, key=lambda r: tuple(int(p) for p in re.split(r'[-.]', r)))


def current(archive):
    """The Overture release the archive is on: its metadata's `overture`,
    which this tool writes; before it, 2026-09-23.1 (decision 386)."""
    _, metadata, _, _ = U.read_archive(archive)
    return metadata.get('overture', '2026-09-23.1')


def key_of(rings):
    return tuple(tuple((int(x), int(y)) for x, y in ring) for ring in rings)


def centroid(rings, tx, ty, scale):
    """(lon, lat) of the mean of a house's outline points."""
    outline = rings[0]
    x = sum(p[0] for p in outline) / len(outline) * scale
    y = sum(p[1] for p in outline) / len(outline) * scale
    return lonlat(tx, ty, x, y)


TABLE = {}
DENSITY = None


def compare(job):
    """One tile: the bundled houses kept (index → attributes), gone
    (index, lon, lat), and the release's new ones (sort key, attributes,
    rings), and the tile's county."""
    key, rows, blob = job
    tx, ty = key
    new = T.encoded_buildings(key, rows, T.TOLERANCE)[0] if rows else []
    info = {r[0]: r for r in rows}
    pool = collections.defaultdict(list)
    for building in new:
        pool[key_of(building[6])].append(building)
    kept, gone = {}, []
    if blob is not None:
        bundled, scale = U.buildings_of(gzip.decompress(blob))
        for index, (_, _, attributes, rings) in enumerate(bundled):
            same = pool.get(key_of(rings))
            if same:
                theirs = same.pop()[5]
                storeys, origin = attributes >> 8, attributes >> 5 & 7
                if origin in (GUESS, TAGS) and theirs >> 8 and theirs >> 5 & 7 == TAGS:
                    storeys, origin = theirs >> 8, TAGS
                use = theirs >> 1 & 15 or attributes >> 1 & 15
                kept[index] = storeys << 8 | (origin if storeys else 0) << 5 | use << 1 | attributes & 1
            else:
                lon, lat = centroid(rings, tx, ty, scale)
                gone.append((index, lon, lat))
    metre = T.metre_of(ty) / T.COARSE  # written units a metre
    added = []
    for same in pool.values():
        for building in same:
            sort_key, attributes, rings = building[:5], building[5], building[6]
            if not attributes >> 8:
                _id, _, _, subtype, _, _, lon, lat, _ = info[sort_key[4]]
                size = abs(T.area(rings[0])) / 2 / metre ** 2
                storeys = T.proposed_storeys(TABLE, T.group_of(subtype), DENSITY(lon, lat), size,
                                             int(lon * 1e5), int(lat * 1e5))
                attributes = storeys << 8 | GUESS << 5 | (attributes & 0x1F)
            added.append((sort_key, attributes, rings))
    added.sort(key=lambda b: b[0])
    county = T._mode([r[5] for r in rows]) if rows else None
    return key, kept, gone, added, county


def patch(archive, extract, counties, population, release, out, report_path):
    global TABLE, DENSITY
    import duckdb
    from build_basemap import tile_id, write_pmtiles
    entries, metadata, bounds, center = U.read_archive(archive)
    with tempfile.TemporaryDirectory() as scratch:
        heights = os.path.join(scratch, 'heights.json')
        with contextlib.redirect_stdout(io.StringIO()):
            T.heights(extract, population, heights)
        TABLE = {(e['group'], T.DENSITY_BANDS.index(e['density']), T.AREA_BANDS.index(e['area'])): e
                 for e in json.load(open(heights))['table']}
    DENSITY = T.density_lookup(population)
    tiles = T.tiles_of(extract)
    keys = sorted(set(tiles) | {U.hilbert_xy(tid) for tid in entries})
    ids = {k: tile_id(T.ZOOM, k[0], k[1]) for k in keys}
    jobs = [(k, tiles.get(k, []), entries.get(ids[k])) for k in keys]
    with multiprocessing.get_context('fork').Pool() as workers:
        results = workers.map(compare, jobs, chunksize=64)

    connection = duckdb.connect()
    connection.sql('INSTALL spatial; LOAD spatial;')
    connection.sql(f"CREATE TABLE c AS SELECT area_code AS code, ST_GeomFromWKB(ST_AsWKB(geom)) AS geom FROM ST_Read('{counties}')")

    # Gone: unless in a county whose own outlines were laid.
    official = ','.join(f"'{code}'" for code in OFFICIAL) or "''"
    connection.sql(f"""
        CREATE TABLE f AS SELECT ST_Simplify(ST_Buffer(geom, {OFFICIAL_MARGIN}), {OFFICIAL_MARGIN / 2}) AS geom
        FROM c WHERE code IN ({official})
    """)
    with tempfile.TemporaryDirectory() as scratch:
        path = os.path.join(scratch, 'gone.tsv')
        with open(path, 'w') as file:
            for k, _, gone_here, _, _ in results:
                for index, lon, lat in gone_here:
                    file.write(f'{ids[k]}\t{index}\t{lon!r}\t{lat!r}\n')
        connection.sql(f"""
            CREATE TABLE g AS SELECT tid, idx, ST_Point(lon, lat) AS p
            FROM read_csv('{path}', delim = '\t', header = false,
                          columns = {{'tid': 'BIGINT', 'idx': 'INTEGER', 'lon': 'DOUBLE', 'lat': 'DOUBLE'}})
        """)
    protected = {(t, i) for t, i in connection.sql(
        'SELECT DISTINCT g.tid, g.idx FROM g JOIN f ON ST_Contains(f.geom, g.p)').fetchall()}
    gone = {(ids[k], index) for k, _, g_, _, _ in results for index, _, _ in g_} - protected
    connection.sql('CREATE TABLE s AS SELECT code, ST_Simplify(geom, 0.0002) AS geom FROM c')
    gone_county = {}
    for t, i, code in connection.sql(
            'SELECT g.tid, g.idx, min(s.code) FROM g JOIN s ON ST_Contains(s.geom, g.p) GROUP BY g.tid, g.idx').fetchall():
        if (t, i) in gone:
            gone_county[t, i] = code

    # New: unless the houses staying already stand there (decision 1001).
    near = set()
    for k, _, _, added, _ in results:
        if added:
            near.update((k[0] + dx, k[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    with tempfile.TemporaryDirectory() as scratch:
        laid = os.path.join(scratch, 'laid.tsv')
        with open(laid, 'w') as file:
            for k in sorted(near):
                blob = entries.get(ids.get(k) or tile_id(T.ZOOM, k[0], k[1]))
                if blob is None:
                    continue
                tid = tile_id(T.ZOOM, k[0], k[1])
                bundled, scale = U.buildings_of(gzip.decompress(blob))
                for index, (_, _, _, rings) in enumerate(bundled):
                    if (tid, index) not in gone:
                        working = [[(x * scale, y * scale) for x, y in ring] for ring in rings]
                        file.write(f'{tid}\t{index}\t{wkt(working, *k)}\n')
        newcomers = os.path.join(scratch, 'new.tsv')
        with open(newcomers, 'w') as file:
            for k, _, _, added, _ in results:
                for n, (_, _, rings) in enumerate(added):
                    working = [[(x * T.COARSE, y * T.COARSE) for x, y in ring] for ring in rings]
                    file.write(f'{ids[k]}\t{n}\t{wkt(working, *k)}\n')
        for name, path in (('o', laid), ('t', newcomers)):
            connection.sql(f"""
                CREATE TABLE {name} AS
                SELECT tid, idx, ST_MakeValid(ST_GeomFromText(shape)) AS geom
                FROM read_csv('{path}', delim = '\t', header = false, quote = '',
                              columns = {{'tid': 'BIGINT', 'idx': 'INTEGER', 'shape': 'VARCHAR'}})
            """)
    connection.sql('ALTER TABLE t ADD COLUMN area DOUBLE')
    connection.sql('UPDATE t SET area = ST_Area(geom)')
    connection.sql(f"""
        CREATE TABLE pairs AS
        SELECT t.tid, t.idx, ST_Area(ST_Intersection(t.geom, o.geom)) AS shared, t.area AS t_area, ST_Area(o.geom) AS o_area
        FROM t JOIN o ON ST_Intersects(t.geom, o.geom)
    """)
    connection.sql('DELETE FROM pairs WHERE shared <= 0')
    standing = {(t, i) for t, i in connection.sql(f"""
        SELECT tid, idx FROM pairs GROUP BY tid, idx
        HAVING sum(shared) >= {COVERED} * any_value(t_area) OR max(shared / o_area) >= {SWALLOWS}
    """).fetchall()}

    # The new tiles, and what changed county by county.
    counts = collections.defaultdict(collections.Counter)
    tiles_broken = []
    changed = 0
    for k, kept, gone_here, added, county in results:
        tid = ids[k]
        blob = entries.get(tid)
        bundled, scale = U.buildings_of(gzip.decompress(blob)) if blob is not None else ([], 1)
        county = county or 'none'
        counts[county]['before'] += len(bundled)
        out_buildings = []
        edited = False
        for index, (_, _, attributes, rings) in enumerate(bundled):
            if (tid, index) in gone:
                counts[gone_county.get((tid, index), county)]['gone'] += 1
                edited = True
                continue
            if index in kept:
                counts[county]['kept'] += 1
                edited |= kept[index] != attributes
                attributes = kept[index]
            else:
                counts[county]['keptOfficial'] += 1
            working = [[(x * scale, y * scale) for x, y in ring] for ring in rings]
            out_buildings.append(T.sort_key(working[0], f'~{index:08d}') + (attributes, rings))
        for n, (sort_key, attributes, rings) in enumerate(added):
            if (tid, n) in standing:
                counts[county]['newStanding'] += 1
                continue
            counts[county]['new'] += 1
            counts[county]['newGuessed'] += attributes >> 5 & 7 == GUESS
            out_buildings.append(sort_key + (attributes, rings))
            edited = True
        # Net, in houses and in ground covered: a street OpenStreetMap
        # redrew loses its old outlines and gains new ones, sometimes fewer
        # and larger (a works drawn as one hall, not as the sheds Shi et
        # al. saw).
        lost = len(bundled) - len(out_buildings)
        if len(bundled) >= LIMITS['tileHouses'] and lost > LIMITS['tileLostAtMost'] * len(bundled):
            before_area = sum(abs(T.area(b[3][0])) for b in bundled)  # written units, both
            after_area = sum(abs(T.area(b[6][0])) for b in out_buildings)
            if after_area < (1 - LIMITS['tileLostAtMost']) * before_area:
                tiles_broken.append({'tile': list(k), 'houses': len(bundled), 'lost': lost,
                                     'groundKept': round(after_area / before_area, 3)})
        if not edited:
            continue
        changed += 1
        if not out_buildings:
            entries.pop(tid, None)
            continue
        out_buildings.sort(key=lambda b: b[:5])
        entries[tid] = gzip.compress(T.written(b[5:] for b in out_buildings), 9, mtime=0)

    total = collections.Counter()
    for c in counts.values():
        total.update(c)
    outside = sum(c['kept'] + c['gone'] for code, c in counts.items() if code not in OFFICIAL)
    kept_outside = sum(c['kept'] for code, c in counts.items() if code not in OFFICIAL)
    broken = []
    share = kept_outside / outside if outside else 1
    if share < LIMITS['keptShareAtLeast']:
        broken.append(f'only {share:.1%} of the houses outside {OFFICIAL} kept their shape')
    for code, c in sorted(counts.items()):
        if c['before'] and c['gone'] > LIMITS['countyGoneAtMost'] * c['before']:
            broken.append(f'county {code}: {c["gone"]} of {c["before"]} gone')
        if c['before'] and c['new'] > LIMITS['countyNewAtMost'] * c['before']:
            broken.append(f'county {code}: {c["new"]} new against {c["before"]}')
        if c['before'] and c['gone'] - c['new'] > LIMITS['countyLostAtMost'] * c['before']:
            broken.append(f'county {code}: {c["gone"] - c["new"]} fewer of {c["before"]}')
    net = (total['new'] - total['gone']) / total['before']
    if not LIMITS['netAtLeast'] <= net <= LIMITS['netAtMost']:
        broken.append(f'net change {net:+.2%}')
    if tiles_broken:
        broken.append(f'{len(tiles_broken)} tiles lost over {LIMITS["tileLostAtMost"]:.0%} of their houses')

    report = {
        'decision': 1026,
        'from': metadata.get('overture', '2026-09-23.1'),
        'to': release,
        'limits': LIMITS,
        'broken': broken,
        'keptShapeOutsideOfficial': round(share, 5),
        'netChange': round(net, 5),
        'houses': dict(total),
        'tilesChanged': changed,
        'tilesBroken': tiles_broken[:50],
        'counties': {code: dict(c) for code, c in sorted(counts.items())},
    }
    if not broken:
        metadata['overture'] = release
        ordered = sorted(entries.items())
        write_pmtiles(out, ordered, metadata, tuple(bounds), center,
                      tile_type=0, tile_compression=2, zooms=(T.ZOOM, T.ZOOM))
        whole = open(out, 'rb').read()
        report.update({'tiles': len(ordered), 'archiveBytes': len(whole), 'sha256': hashlib.sha256(whole).hexdigest()})
    with open(report_path, 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps({k: v for k, v in report.items() if k not in ('counties', 'limits')}, ensure_ascii=False, indent=1))
    if broken:
        sys.exit(3)


if __name__ == '__main__':
    command, arguments = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ('', [])
    if command == 'latest' and not arguments:
        print(latest())
    elif command == 'current' and len(arguments) == 1:
        print(current(*arguments))
    elif command == 'patch' and len(arguments) == 7:
        patch(*arguments)
    else:
        sys.exit(__doc__)
