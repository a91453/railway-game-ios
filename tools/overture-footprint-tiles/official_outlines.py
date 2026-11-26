#!/usr/bin/env python3
"""A city's own building outlines in place of Overture's on the bundled
Taiwan buildings (decision 1015): official first, Overture only where the
city's map has nothing.

Of Taiwan's counties only Taichung opens its building map (臺中市建物圖,
data.gov.tw 158889, 政府資料開放授權條款第 1 版): every building of its
1:1000 aerial maps, one outline a house (a row of terrace houses is a row
of outlines), with its storeys above ground (`B1D`), the year it was last
surveyed (`B1E`, 103–114) and its kind (`B1B`) and structure (`B1C`).
Overture's outlines of Taiwan are 70 % machine-drawn (Shi et al.), which
merge a street of houses into one block and miss many; the rest are
OpenStreetMap's.

The city's outlines are laid first, then each building of the archive is
kept only where they leave room, by decision 1001's rule: it goes when
the city's buildings cover a tenth of it, or it covers half of one of
them (an outline drawn round a row the city has house by house is the
same houses). Kept, a building stays byte for byte (its storeys from the
usage permits and the registry, decision 1011, too).

Houses wall to wall of the same storeys and structure are then made one
building (`merged_neighbours`): the far view could not draw a million
houses within decision 709's budget, and a row's steps in height stay.

A city building's storeys are its map's (`cityMap`, as decision 389 took
them); 0 on the map, those of the archive's building it overlaps most,
else unknown (the app's guess). Its use is that building's when it has
one: the map has no use, only the kind of house, so a building of iron
frame (`B1C` 3, 鐵皮屋) is otherwise industry and the rest houses, as the
app draws a building of no use. Under SMALLEST m² and of iron frame
(sheds, carports) it is left out, as decision 799 leaves out small
outbuildings.

    O=tools/overture-footprint-tiles/official_outlines.py
    # data.gov.tw 158889's CSV names a Google Drive file (78 MB, 7z)
    curl -L -o t114.7z 'https://drive.usercontent.google.com/download?id=1i8TxgAoLGCFdSe5Ug5550oKvjzzGPcr4&export=download&confirm=t'
    LC_ALL=C.UTF-8 bsdtar -xf t114.7z -C t114
    # about 17 minutes; after usage_permits.py apply
    python3 -I $O apply RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles out.pmtiles \\
        official_outlines.json taichung=t114/01-SHP/114期末_B0001_1216n.shp
    cp out.pmtiles RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles

Needs `pip install duckdb` (decision 93) with its spatial extension. The
same inputs give the same bytes.
"""

import collections
import gzip
import hashlib
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))

import build_footprint_tiles as T  # noqa: E402
import usage_permits as U  # noqa: E402

# Decision 1001: a building already laid covering this share of a newcomer,
# or a newcomer covering this share of one laid, is the same building.
COVERED = 0.1
SWALLOWS = 0.5
# Iron-frame sheds under this many m² are left out (decision 799's 30 m²).
SMALLEST = 30.0
# `B1C` of iron frame: a shed when small, else most often a works or a
# warehouse of sheet metal (鐵皮屋), drawn as industry when nothing says.
IRON_FRAME = '3'
LICENCE = ('Outlines: Taichung City Government, building map of 2025 (臺中市建物圖 114 年版, data.gov.tw 158889, '
           'Open Government Data License, version 1.0)')
CITY = 'cityMap'


def lonlat(tx, ty, x, y):
    """A point of tile (tx, ty) in working units as (lon, lat)."""
    wx = tx + x / T.EXTENT
    wy = ty + y / T.EXTENT
    n = 1 << T.ZOOM
    return wx / n * 360 - 180, math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * wy / n))))


def wkt(rings, tx, ty):
    parts = []
    for ring in rings:
        points = [lonlat(tx, ty, x, y) for x, y in ring]
        points.append(points[0])
        parts.append('(' + ','.join(f'{a:.8f} {b:.8f}' for a, b in points) + ')')
    return 'POLYGON(' + ','.join(parts) + ')'


def official(connection, path):
    """The map's buildings as table `t` (id, storeys, kind, frame, lon,
    lat, size m², geom in lon/lat, wkb)."""
    connection.sql(f"""
        CREATE TABLE t AS
        WITH r AS (
            SELECT ID AS id, B1D AS storeys, B1B AS kind, B1C AS frame,
                   ST_MakeValid(ST_Force2D(geom)) AS metric,
                   ST_Transform(ST_MakeValid(ST_Force2D(geom)), 'EPSG:3826', 'EPSG:4326', true) AS geom
            FROM ST_Read('{path}')
        )
        SELECT id, coalesce(storeys, 0) AS storeys, kind, frame, ST_X(ST_Centroid(geom)) AS lon,
               ST_Y(ST_Centroid(geom)) AS lat, ST_Area(metric) AS size, geom, ST_AsWKB(geom) AS wkb
        FROM r WHERE NOT ST_IsEmpty(geom) AND ST_Area(metric) > 0
        ORDER BY id
    """)


def merged_neighbours(connection):
    """Table `t` with each run of buildings wall to wall of the same
    storeys and the same structure (iron frame or not) made one building
    (decision 1015's later part): a row of five-storey houses becomes
    one five-storey block, its steps in height kept. Two buildings are
    wall to wall when they share two corners or more, as a 1:1000 map
    draws a party wall. Returns how many buildings were merged and into
    how many."""
    rows = connection.sql(f"SELECT id, storeys, frame = '{IRON_FRAME}', ST_AsText(geom) FROM t ORDER BY id").fetchall()
    owners = collections.defaultdict(list)
    for index, (_, _, _, text) in enumerate(rows):
        body = text[text.index('('):].replace('(', ' ').replace(')', ' ')
        corners = set()
        for point in body.split(','):
            xy = point.split()
            if len(xy) >= 2:
                corners.add((round(float(xy[0]), 7), round(float(xy[1]), 7)))
        for corner in corners:
            owners[corner].append(index)
    shared = collections.Counter()
    for who in owners.values():
        if len(who) > 1:
            for a in who:
                for b in who:
                    if a < b and rows[a][1:3] == rows[b][1:3]:
                        shared[a, b] += 1
    parent = list(range(len(rows)))

    def root(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for (a, b), count in sorted(shared.items()):
        if count >= 2:
            ra, rb = root(a), root(b)
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
    groups = [rows[root(index)][0] for index in range(len(rows))]
    connection.sql('CREATE TABLE g (id BIGINT, grp BIGINT)')
    connection.executemany('INSERT INTO g VALUES (?, ?)', list(zip((r[0] for r in rows), groups)))
    connection.sql("""
        CREATE TABLE m AS
        WITH u AS (
            SELECT g.grp AS id, any_value(t.storeys) AS storeys, mode(t.kind) AS kind, any_value(t.frame) AS frame,
                   sum(t.size) AS size, count(*) AS n,
                   CASE WHEN count(*) = 1 THEN any_value(t.geom) ELSE ST_MakeValid(ST_Union_Agg(t.geom)) END AS geom
            FROM t JOIN g USING (id) GROUP BY g.grp
        )
        SELECT id, storeys, kind, frame, ST_X(ST_Centroid(geom)) AS lon, ST_Y(ST_Centroid(geom)) AS lat,
               size, geom, ST_AsWKB(geom) AS wkb, n
        FROM u ORDER BY id
    """)
    merged, into = connection.sql('SELECT coalesce(sum(n), 0), count(*) FROM m WHERE n > 1').fetchall()[0]
    connection.sql('DROP TABLE t')
    connection.sql('DROP TABLE g')
    connection.sql('ALTER TABLE m DROP COLUMN n')
    connection.sql('ALTER TABLE m RENAME TO t')
    return int(merged), int(into)


def apply(archive, out, report_path, *sources):
    import duckdb
    given = dict(s.split('=', 1) for s in sources)
    connection = duckdb.connect()
    connection.sql('INSTALL spatial; LOAD spatial;')
    connection.sql('SET threads = 8')
    official(connection, given['taichung'])
    read = connection.sql('SELECT count(*) FROM t').fetchall()[0][0]
    small = connection.sql(f"SELECT count(*) FROM t WHERE size < {SMALLEST} AND frame = '{IRON_FRAME}'").fetchall()[0][0]
    connection.sql(f"DELETE FROM t WHERE size < {SMALLEST} AND frame = '{IRON_FRAME}'")
    merged, merged_into = merged_neighbours(connection)
    west, south, east, north = connection.sql(
        'SELECT min(ST_XMin(geom)), min(ST_YMin(geom)), max(ST_XMax(geom)), max(ST_YMax(geom)) FROM t').fetchall()[0]

    entries, metadata, bounds, center = U.read_archive(archive)
    tiles = {}
    (x0, y0), (x1, y1) = T.tile_of(west, north), T.tile_of(east, south)
    reach = range(int(x0) - 1, int(x1) + 2), range(int(y0) - 1, int(y1) + 2)
    for tid in sorted(entries):
        tx, ty = U.hilbert_xy(tid)
        if tx in reach[0] and ty in reach[1]:
            tiles[tid] = gzip.decompress(entries[tid])

    # The archive's buildings near the map, as polygons in lon/lat.
    rows = []
    decoded = {}
    for tid in sorted(tiles):
        tx, ty = U.hilbert_xy(tid)
        buildings, scale = U.buildings_of(tiles[tid])
        decoded[tid] = (buildings, scale)
        for index, (_, _, attributes, rings) in enumerate(buildings):
            working = [[(x * scale, y * scale) for x, y in ring] for ring in rings]
            rows.append((tid, index, attributes, wkt(working, tx, ty)))
    scratch = out + '.archive.tsv'
    with open(scratch, 'w') as file:
        for row in rows:
            file.write('\t'.join(str(v) for v in row) + '\n')
    connection.sql(f"""
        CREATE TABLE o AS
        SELECT tid, idx, attributes, ST_MakeValid(ST_GeomFromText(shape)) AS geom
        FROM read_csv('{scratch}', delim = '\t', header = false, quote = '',
                      columns = {{'tid': 'BIGINT', 'idx': 'INTEGER', 'attributes': 'BIGINT', 'shape': 'VARCHAR'}})
    """)
    os.remove(scratch)
    connection.sql('ALTER TABLE o ADD COLUMN area DOUBLE')
    connection.sql('UPDATE o SET area = ST_Area(geom)')
    connection.sql('''
        CREATE TABLE pairs AS
        SELECT o.tid, o.idx, t.id, ST_Area(ST_Intersection(o.geom, t.geom)) AS shared,
               o.area AS o_area, ST_Area(t.geom) AS t_area
        FROM o JOIN t ON ST_Intersects(o.geom, t.geom)
    ''')
    connection.sql('DELETE FROM pairs WHERE shared <= 0')
    gone = {(tid, idx) for tid, idx in connection.sql(f'''
        SELECT tid, idx FROM pairs GROUP BY tid, idx
        HAVING sum(shared) >= {COVERED} * any_value(o_area) OR max(shared / t_area) >= {SWALLOWS}
    ''').fetchall()}
    # Each city building's archive building of most overlap (among those
    # it replaces or not), for its use and, when the map has none, storeys.
    nearest = {id_: (tid, idx) for id_, tid, idx in connection.sql('''
        SELECT id, arg_max(tid, shared), arg_max(idx, shared) FROM pairs GROUP BY id
    ''').fetchall()}

    city = connection.sql('SELECT id, storeys, kind, frame, lon, lat, size, wkb FROM t ORDER BY id').fetchall()
    by_tile = collections.defaultdict(list)
    storeys_table = {}
    counts = collections.Counter()
    for id_, storeys, kind, frame, lon, lat, size, wkb in city:
        wx, wy = T.tile_of(lon, lat)
        key = (int(wx), int(wy))
        match = nearest.get(id_)
        use = 0
        origin_attributes = None
        if match:
            buildings, _ = decoded[match[0]]
            origin_attributes = buildings[match[1]][2]
            use = origin_attributes >> 1 & 15
        if storeys > 0:
            value, origin = min(255, storeys), T.STOREYS_FROM.index(CITY)
            counts['storeysFromMap'] += 1
        elif origin_attributes is not None and origin_attributes >> 8 > 0:
            value, origin = origin_attributes >> 8, origin_attributes >> 5 & 7
            counts['storeysFromOverlapped'] += 1
        else:
            value, origin = 0, 0
            counts['storeysUnknown'] += 1
        if use:
            counts['useFromOverlapped'] += 1
        elif frame == IRON_FRAME:
            use = T.USES.index('industrial') + 1
            counts['useIronFrame'] += 1
        else:
            counts['useUnknown'] += 1
        subtype = T.USES[use - 1] if use else None
        name = f'taichung:{id_:08d}'
        storeys_table[name] = (value, origin)
        by_tile[key].append((name, None, None, subtype, 'Taichung', None, lon, lat, wkb))

    # Every tile the map's buildings land in or the replaced ones were in.
    touched = {U.hilbert_xy(tid): tid for tid, _ in gone}
    from build_basemap import tile_id
    for key in by_tile:
        touched.setdefault(key, tile_id(T.ZOOM, key[0], key[1]))
    stats_total = [0, 0, 0, 0, 0.0, 0.0, 0, 0.0]
    kept_count = 0
    for key in sorted(touched):
        tid = touched[key]
        buildings = []
        if tid in decoded:
            old, scale = decoded[tid]
            for index, (_, _, attributes, rings) in enumerate(old):
                if (tid, index) in gone:
                    continue
                kept_count += 1
                working = [[(x * scale, y * scale) for x, y in ring] for ring in rings]
                buildings.append(T.sort_key(working[0], f'~{index:08d}') + (attributes, rings))
        elif tid in entries:
            raise SystemExit(f'tile {tid} was not decoded')
        new, stats = T.encoded_buildings(key, by_tile.get(key, []), T.TOLERANCE, storeys_table)
        for i in range(8):
            stats_total[i] = max(stats_total[i], stats[i]) if i == 7 else stats_total[i] + stats[i]
        buildings += new
        if not buildings:
            entries.pop(tid, None)
            continue
        buildings.sort(key=lambda b: b[:5])
        entries[tid] = gzip.compress(T.written(b[5:] for b in buildings), 9, mtime=0)

    from build_basemap import write_pmtiles
    metadata['attribution'] = metadata.get('attribution', '') + '. ' + LICENCE
    ordered = sorted(entries.items())
    write_pmtiles(out, ordered, metadata, tuple(bounds), center,
                  tile_type=0, tile_compression=2, zooms=(T.ZOOM, T.ZOOM))
    whole = open(out, 'rb').read()
    in_reach = len(rows)
    report = {
        'decision': 1015,
        'taichung': {
            'read': read,
            'leftOutSmallIronFrame': small,
            'laid': stats_total[0],
            'mergedWallToWall': merged,
            'mergedInto': merged_into,
            'droppedWhenSimplified': stats_total[1],
        },
        'archiveBuildingsNearTheMap': in_reach,
        'archiveBuildingsReplaced': len(gone),
        'archiveBuildingsKeptInTouchedTiles': kept_count,
        'replacedByOrigin': dict(sorted(collections.Counter(
            T.STOREYS_FROM[decoded[t][0][i][2] >> 5 & 7] for t, i in gone).items())),
        'replacedBySource': dict(sorted(collections.Counter(
            ('OpenStreetMap', 'Shi et al.')[decoded[t][0][i][2] & 1] for t, i in gone).items())),
        'cityBuildings': dict(sorted(counts.items())),
        'tilesTouched': len(touched),
        'tiles': len(ordered),
        'archiveBytes': len(whole),
        'sha256': hashlib.sha256(whole).hexdigest(),
    }
    with open(report_path, 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    commands = {'apply': apply}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
