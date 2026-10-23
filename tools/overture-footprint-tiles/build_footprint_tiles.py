#!/usr/bin/env python3
"""Overture Maps' buildings of Taiwan as compact footprint tiles the app can
read (decision 386, step 1 of real footprints everywhere): one tile per
z16 Web Mercator square (553–568 m across Taiwan, the size of the 3D map's
512 m chunks, decision 358), gzipped, in PMTiles v3 archives, one for the
whole island and one per county.

    pip install duckdb
    python3 tools/overture-footprint-tiles/build_footprint_tiles.py \\
        extract 2026-09-23.1 COUNTIES overture_footprints.parquet
    python3 tools/overture-footprint-tiles/build_footprint_tiles.py \\
        heights overture_footprints.parquet POPULATION heights.json
    python3 tools/overture-footprint-tiles/build_footprint_tiles.py \\
        storeys overture_footprints.parquet POPULATION heights.json \\
        GHSL_DIR TAICHUNG TAIPEI.shp storeys.parquet
    python3 tools/overture-footprint-tiles/build_footprint_tiles.py \\
        build overture_footprints.parquet OUT [TOLERANCE] [storeys.parquet]
    python3 tools/overture-footprint-tiles/build_footprint_tiles.py \\
        window OUT/taiwan.pmtiles LAT LON SIDE heights.json POPULATION window.json

COUNTIES is the reference repository's county outlines
(`Railway/geo-scene-reference-clean/source/public/statistics/
county-reference-2025.geojson`, 內政部; used only to keep Kinmen's and
Matsu's buildings apart from Xiamen's and Fuzhou's and to group the tiles
by county, never bundled). POPULATION is the app's
`Resources/RealWorld/taiwan_population.json` (WorldPop, CC BY 4.0).

`extract` reads the release's buildings as
`real-world-population/build_overture_building_grid.py` does, over three
boxes (Taiwan and Penghu, Kinmen, Matsu), with each building's use
(`subtype`), and keeps those whose centroid lies in a county or within
2 km of one, each with its county. Underground buildings are left out.

`storeys` gives every building its storeys (decision 386's point 6,
decision 389): the first of these that has a value, else the density
guess. Each is written with where it came from (`STOREYS_FROM`), so a
source added or dropped later is only a matter of running this again.

    NLSC's national 3D buildings   (not used until the owner has asked)
    a city's building map          Taichung's of 2025, 2024 and 2022
                                   (data.gov.tw 158889, 152106, 162900)
    OpenStreetMap's tags           Overture's `num_floors`, else `height`
    Taipei's building permit map   (data.gov.tw 151936)
    the density guess              `proposed_storeys`, GHSL picking p25,
                                   the median or p75 (`picked_storeys`)

TAICHUNG is Taichung's maps' shapefiles, newest first, joined by `:`
(the 2025 and 2024 maps come as 7z and RAR archives: `bsdtar -xf`, see
the README). They and TAIPEI.shp are matched as
`measure_height_sources.py` matches them (overlap of at least half the
footprint). GHSL_DIR holds
GHS-BUILT-H ANBH R2023A's tiles R6_C30 and R7_C30, read by `tiff.py`.

`build` writes OUT/taiwan.pmtiles, OUT/counties/<code>.pmtiles and
OUT/report.json (sizes before and after compression, bytes a building,
what simplification did to the shapes). TOLERANCE is Douglas-Peucker's, in
metres (default 0.5). With `storeys`' file, every building's storeys and
where they came from; without, the tags' (0 when unknown). The same input
gives byte-identical files: rows, buildings and rings in a fixed order,
gzip at level 9 without a time stamp.

A tile (before gzip), every number an unsigned LEB128 varint, signed ones
zigzagged:

    version (2), buildings
    each building:
        attributes: storeys << 8 | from << 5 | use << 1 | source
            storeys: 1–255; 0 when unknown
            from: STOREYS_FROM's index, where the storeys came from
            use: USES' index (0 unknown)
            source: 0 OpenStreetMap, 1 Shi et al.'s East Asian buildings
        rings (the outline first, then its holes)
        each ring: points (at least 3, not closed), then each point's
            zigzag x and y step from the last point written in the tile
            (the first from 0, 0)

x and y are the tile's own units, 4096 a side (as a vector tile's extent;
0.137–0.140 m on the ground in Taiwan), east and south of its north-west
corner; a building belongs to the tile its centroid is in, so a large one
reaches past the edges. Outlines run counter-clockwise seen from above,
holes clockwise. A multipolygon is one building a polygon.

Overture's buildings are ODbL 1.0 as a whole; each keeps its source's
licence: OpenStreetMap ODbL 1.0, Shi et al. (doi:10.5281/zenodo.8174931)
CC BY 4.0. DuckDB is MIT. The PMTiles writer is `basemap/build_basemap.py`'s.
"""
import gzip
import hashlib
import json
import math
import multiprocessing
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))

ZOOM = 16
EXTENT = 4096
LEVEL_HEIGHT = 3.2
# West, south, east, north: Taiwan and Penghu (the survey's), Kinmen, Matsu.
BOXES = [(119.3, 21.8, 122.1, 25.4), (118.1, 24.35, 118.55, 24.56), (119.85, 25.9, 120.55, 26.4)]
# Kept when the centroid is this far (degrees, about 2 km) from a county.
NEAR = 0.02
OSM = 'OpenStreetMap'
# Overture's building subtypes; a building's `use` is the index + 1.
USES = ['agricultural', 'civic', 'commercial', 'education', 'entertainment', 'industrial', 'medical',
        'military', 'outbuilding', 'religious', 'residential', 'service', 'transportation']
# Where a building's storeys came from (3 bits); `nlsc` is kept for the
# national 3D buildings, used once the owner has asked for them.
STOREYS_FROM = ['guess', 'tags', 'cityMap', 'permits', 'nlsc']
VERSION = 2
# Rings smaller than these (m²) after simplifying are dropped.
SMALLEST_OUTLINE = 2.0
SMALLEST_HOLE = 1.0
# Metres a degree of latitude, and a z16 tile unit at the equator.
EARTH = 6_378_137.0
UNIT = 2 * math.pi * EARTH / (1 << ZOOM) / EXTENT


# --- extract ---------------------------------------------------------------

def extract(release, counties, out):
    import duckdb
    from build_overture_building_grid import release_files, sql_list
    connection = duckdb.connect()
    connection.sql('INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial;')
    connection.sql('SET threads = 32')
    urls = release_files(release)
    boxes = {}
    for name, group, column, low, high in connection.sql(f"""
        SELECT file_name, row_group_id, path_in_schema, stats_min_value, stats_max_value
        FROM parquet_metadata({sql_list(urls)})
        WHERE path_in_schema IN ('bbox, xmin', 'bbox, xmax', 'bbox, ymin', 'bbox, ymax')
    """).fetchall():
        boxes.setdefault((name, group), {})[column.split(', ')[1]] = (float(low), float(high))
    files = sorted({name for (name, _), box in boxes.items()
                    if any(box['xmax'][1] >= w and box['xmin'][0] <= e and box['ymax'][1] >= s and box['ymin'][0] <= n
                           for w, s, e, n in BOXES)})
    print(f'{len(urls)} files, {len(files)} reach Taiwan', file=sys.stderr)
    within = ' OR '.join(f'(bbox.xmax >= {w} AND bbox.xmin <= {e} AND bbox.ymax >= {s} AND bbox.ymin <= {n})'
                         for w, s, e, n in BOXES)
    connection.sql(f"CREATE TABLE counties AS SELECT area_code AS code, area_name AS name, ST_GeomFromWKB(ST_AsWKB(geom)) AS geom FROM ST_Read('{counties}')")
    connection.sql(f"""
        CREATE TABLE raw AS
        SELECT id, num_floors, height, subtype, sources[1].dataset AS dataset,
               ST_GeomFromWKB(ST_AsWKB(geometry)) AS geometry
        FROM read_parquet({sql_list(files)})
        WHERE ({within}) AND NOT coalesce(is_underground, false)
    """)
    connection.sql('CREATE TABLE placed AS SELECT *, ST_Centroid(geometry) AS centroid FROM raw')
    # Each building's county: the one it is in, else the nearest within NEAR.
    connection.sql(f"""
        COPY (
            WITH inside AS (
                SELECT p.id, min(c.code) AS code FROM placed p JOIN counties c ON ST_Contains(c.geom, p.centroid) GROUP BY p.id
            ), outside AS (
                SELECT p.id, arg_min(c.code, ST_Distance(c.geom, p.centroid)) AS code
                FROM placed p JOIN counties c ON ST_DWithin(c.geom, p.centroid, {NEAR})
                WHERE p.id NOT IN (SELECT id FROM inside) GROUP BY p.id
            ), counted AS (SELECT * FROM inside UNION ALL SELECT * FROM outside)
            SELECT p.id, p.num_floors, p.height, p.subtype, p.dataset, k.code AS county, c.name AS county_name,
                   ST_X(p.centroid) AS lon, ST_Y(p.centroid) AS lat, ST_AsWKB(p.geometry) AS footprint
            FROM placed p JOIN counted k USING (id) JOIN counties c ON c.code = k.code
            ORDER BY p.id
        ) TO '{out}' (FORMAT parquet, COMPRESSION zstd)
    """)
    total = connection.sql('SELECT count(*) FROM raw').fetchall()[0][0]
    kept = connection.sql(f"SELECT count(*) FROM read_parquet('{out}')").fetchall()[0][0]
    print(f'{total} buildings in the boxes, {kept} in or near a county', file=sys.stderr)


# --- geometry --------------------------------------------------------------

def tile_of(lon, lat):
    """The z16 tile (x, y) and the point in world tile units (x, y down)."""
    s = math.sin(math.radians(lat))
    wx = (lon / 360 + 0.5) * (1 << ZOOM)
    wy = (0.5 - 0.25 * math.log((1 + s) / (1 - s)) / math.pi) * (1 << ZOOM)
    return wx, wy


def polygons(wkb):
    """The rings of each polygon of a WKB Polygon or MultiPolygon, as
    (lon, lat) lists, the closing point dropped."""
    out = []

    def polygon(at, order):
        (count,) = struct.unpack_from(order + 'I', wkb, at)
        at += 4
        rings = []
        for _ in range(count):
            (n,) = struct.unpack_from(order + 'I', wkb, at)
            at += 4
            points = list(struct.iter_unpack(order + 'dd', wkb[at:at + 16 * n]))
            at += 16 * n
            if len(points) > 1 and points[0] == points[-1]:
                points.pop()
            rings.append(points)
        return rings, at

    order = '<' if wkb[0] == 1 else '>'
    (kind,) = struct.unpack_from(order + 'I', wkb, 1)
    if kind == 3:
        out.append(polygon(5, order)[0])
    elif kind == 6:
        (count,) = struct.unpack_from(order + 'I', wkb, 5)
        at = 9
        for _ in range(count):
            order = '<' if wkb[at] == 1 else '>'
            rings, at = polygon(at + 5, order)
            out.append(rings)
    return out


def segment_sq(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    if dx or dy:
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        ax, ay = ax + dx * t, ay + dy * t
    return (px - ax) ** 2 + (py - ay) ** 2


def douglas_peucker(points, sq_tolerance):
    """The closed ring `points` simplified: split at the point farthest from
    the first, each half kept to within the tolerance."""
    n = len(points)
    if n <= 3 or sq_tolerance <= 0:
        return points
    x0, y0 = points[0]
    far = max(range(n), key=lambda i: ((points[i][0] - x0) ** 2 + (points[i][1] - y0) ** 2, -i))
    keep = [False] * n
    keep[0] = keep[far] = True
    ring = points + [points[0]]
    stack = [(0, far), (far, n)]
    while stack:
        first, last = stack.pop()
        best, index = sq_tolerance, -1
        ax, ay = ring[first]
        bx, by = ring[last]
        for i in range(first + 1, last):
            d = segment_sq(ring[i][0], ring[i][1], ax, ay, bx, by)
            if d > best:
                best, index = d, i
        if index >= 0:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [p for p, k in zip(points, keep) if k]


def area(ring):
    """Twice the signed area, positive counter-clockwise with y up."""
    total = 0
    for i in range(len(ring)):
        x1, y1 = ring[i - 1]
        x2, y2 = ring[i]
        total += x1 * y2 - x2 * y1
    return -total  # y runs down in tile units


def snap(ring):
    """`ring` on whole tile units, repeated points and straight-through ones
    (no area between neighbours) dropped."""
    out = []
    for x, y in ring:
        p = (int(math.floor(x + 0.5)), int(math.floor(y + 0.5)))
        if not out or out[-1] != p:
            out.append(p)
    while len(out) > 1 and out[0] == out[-1]:
        out.pop()
    changed = True
    while changed and len(out) >= 3:
        changed = False
        for i in range(len(out)):
            a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) == 0:
                del out[i]
                changed = True
                break
    return out


# --- tiles -----------------------------------------------------------------

def varint(v, out):
    while v > 0x7F:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)


def zigzag(v):
    return (v << 1) ^ (v >> 63)


def storeys_of(floors, height):
    if floors is not None and 0 < floors < 256:
        return int(floors)
    if height is not None and height > 0:
        return max(1, min(255, int(math.floor(height / LEVEL_HEIGHT + 0.5))))
    return 0


def encode_tile(key, rows, tolerance, storeys=None):
    """One tile's bytes before gzip, and what simplifying did:
    [buildings, rings dropped, points before, points after, area before (m²),
    sum |area change| (m²), buildings whose area moved over 5 %, largest
    relative change]."""
    tx, ty = key
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (ty + 0.5) / (1 << ZOOM)))))
    metre = 1 / (UNIT * math.cos(math.radians(lat)))  # tile units a metre
    sq_tolerance = (tolerance * metre) ** 2
    stats = [0, 0, 0, 0, 0.0, 0.0, 0, 0.0]
    buildings = []
    for _id, floors, height, subtype, dataset, _county, _lon, _lat, wkb in rows:
        count, origin = storeys[_id] if storeys and _id in storeys else (storeys_of(floors, height), 1)
        attributes = (count << 8 | (origin if count else 0) << 5 | (USES.index(subtype) + 1 if subtype in USES else 0) << 1
                      | (0 if dataset == OSM else 1))
        for polygon in polygons(wkb):
            rings = []
            before = after = 0.0
            for index, ring in enumerate(polygon):
                local = []
                for lon, la in ring:
                    wx, wy = tile_of(lon, la)
                    local.append(((wx - tx) * EXTENT, (wy - ty) * EXTENT))
                stats[2] += len(local)
                original = abs(area(local)) / 2 / metre ** 2 if len(local) >= 3 else 0
                simple = snap(douglas_peucker(local, sq_tolerance))
                twice = area(simple) if len(simple) >= 3 else 0
                size = abs(twice) / 2 / metre ** 2
                if size < (SMALLEST_OUTLINE if index == 0 else SMALLEST_HOLE):
                    stats[1] += 1
                    if index == 0:
                        rings = []
                        break
                    continue
                # Outline counter-clockwise, holes clockwise, seen from above.
                if (twice > 0) != (index == 0):
                    simple = [simple[0]] + simple[:0:-1]
                rings.append(simple)
                sign = 1 if index == 0 else -1
                before += sign * original
                after += sign * size
            if not rings:
                continue
            stats[0] += 1
            stats[3] += sum(len(r) for r in rings)
            stats[4] += before
            stats[5] += abs(after - before)
            change = abs(after - before) / before if before > 0 else 0
            stats[6] += change > 0.05
            stats[7] = max(stats[7], change)
            cx = sum(x for x, _ in rings[0]) / len(rings[0])
            cy = sum(y for _, y in rings[0]) / len(rings[0])
            buildings.append(((int(cy) >> 8, int(cx) >> 8, int(cy), int(cx), _id), attributes, rings))
    # Rows of 256 units, alternating direction, so steps stay short.
    buildings.sort(key=lambda b: (b[0][0], b[0][1] if b[0][0] % 2 == 0 else -b[0][1], b[0][2:]))
    out = bytearray()
    varint(VERSION, out)
    varint(len(buildings), out)
    cursor = (0, 0)
    for _, attributes, rings in buildings:
        varint(attributes, out)
        varint(len(rings), out)
        for ring in rings:
            varint(len(ring), out)
            for x, y in ring:
                varint(zigzag(x - cursor[0]), out)
                varint(zigzag(y - cursor[1]), out)
                cursor = (x, y)
    return bytes(out), stats


def decode_tile(data):
    """The buildings of a tile's bytes (unzipped): (storeys, use, source,
    rings of (x, y) tile units, where the storeys came from)."""
    at = 0

    def read():
        nonlocal at
        value = shift = 0
        while True:
            byte = data[at]
            at += 1
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                return value

    def signed():
        v = read()
        return (v >> 1) ^ -(v & 1)

    assert read() == VERSION
    cursor = [0, 0]
    out = []
    for _ in range(read()):
        attributes = read()
        rings = []
        for _ in range(read()):
            ring = []
            for _ in range(read()):
                cursor[0] += signed()
                cursor[1] += signed()
                ring.append(tuple(cursor))
            rings.append(ring)
        out.append((attributes >> 8, attributes >> 1 & 15, attributes & 1, rings, attributes >> 5 & 7))
    assert at == len(data)
    return out


STOREYS = {}


def _load_storeys(path):
    global STOREYS
    import duckdb
    STOREYS = {id_: (count, origin) for id_, count, origin in
               duckdb.connect().sql(f"SELECT id, storeys, origin FROM read_parquet('{path}')").fetchall()}


def work(job):
    key, rows, tolerance = job
    raw, stats = encode_tile(key, rows, tolerance, STOREYS)
    return key, raw, gzip.compress(raw, 9, mtime=0), stats, _mode([r[5] for r in rows])


def _mode(values):
    counts = {}
    for v in values:
        counts[v] = counts.get(v, 0) + 1
    return min(counts, key=lambda v: (-counts[v], v))


def tiles_of(extract_path):
    """The extract's rows by z16 tile, tiles in order."""
    import duckdb
    connection = duckdb.connect()
    rows = connection.sql(f"""
        SELECT id, num_floors, height, subtype, dataset, county, lon, lat, footprint
        FROM read_parquet('{extract_path}') ORDER BY id
    """).fetchall()
    tiles = {}
    for row in rows:
        wx, wy = tile_of(row[6], row[7])
        tiles.setdefault((int(wx), int(wy)), []).append(row)
    return tiles


def build(extract_path, out, tolerance='0.5', storeys_path=None):
    from build_basemap import tile_id, write_pmtiles
    tolerance = float(tolerance)
    if storeys_path:
        _load_storeys(storeys_path)
    tiles = tiles_of(extract_path)
    jobs = [(key, tiles[key], tolerance) for key in sorted(tiles)]
    # Forked: the workers share STOREYS as it is.
    with multiprocessing.get_context('fork').Pool() as pool:
        results = pool.map(work, jobs, chunksize=64)
    os.makedirs(os.path.join(out, 'counties'), exist_ok=True)
    by_county, everything = {}, []
    totals = [0, 0, 0, 0, 0.0, 0.0, 0, 0.0]
    raw_bytes = 0
    sources = [0, 0]
    with_storeys = 0
    origins = [0] * len(STOREYS_FROM)
    for key, raw, packed, stats, county in results:
        tid = tile_id(ZOOM, key[0], key[1])
        everything.append((tid, packed))
        by_county.setdefault(county, []).append((tid, packed, len(raw), key, stats[0]))
        raw_bytes += len(raw)
        for i in range(7):
            totals[i] += stats[i]
        totals[7] = max(totals[7], stats[7])
        for storeys, _, source, _, origin in decode_tile(raw):
            sources[source] += 1
            with_storeys += storeys > 0
            origins[origin] += storeys > 0
    names = county_names(extract_path)

    def archive(path, entries):
        keys = [e[3] for e in entries]
        west = min(k[0] for k in keys) / (1 << ZOOM) * 360 - 180
        east = (max(k[0] for k in keys) + 1) / (1 << ZOOM) * 360 - 180
        north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * min(k[1] for k in keys) / (1 << ZOOM)))))
        south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (max(k[1] for k in keys) + 1) / (1 << ZOOM)))))
        metadata = {'name': 'Taiwan building footprints', 'format': f'footprints/{VERSION}', 'zoom': ZOOM, 'extent': EXTENT,
                    'tolerance': tolerance, 'uses': USES, 'storeysFrom': STOREYS_FROM,
                    'attribution': 'Overture Maps Foundation (ODbL 1.0): OpenStreetMap contributors (ODbL 1.0), '
                                   'Shi et al., East Asian buildings, doi:10.5281/zenodo.8174931 (CC BY 4.0)'
                                   + ('. Storeys: Taichung City Government, building maps of 2022, 2024 and 2025; '
                                      'Taipei City Construction Management Office, building permit map '
                                      '(Open Government Data License, version 1.0); European Commission JRC, GHS-BUILT-H '
                                      'R2023A, doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE (CC BY 4.0); '
                                      'WorldPop (CC BY 4.0)' if STOREYS else '')}
        write_pmtiles(path, [(t, b) for t, b, *_ in entries], metadata, (west, south, east, north),
                      ((west + east) / 2, (south + north) / 2, ZOOM), tile_type=0, tile_compression=2, zooms=(ZOOM, ZOOM))
        return os.path.getsize(path)

    archive(os.path.join(out, 'taiwan.pmtiles'),
            [(tile_id(ZOOM, k[0], k[1]), p, len(r), k, s[0]) for k, r, p, s, _ in results])
    counties = []
    for code in sorted(by_county):
        entries = by_county[code]
        size = archive(os.path.join(out, 'counties', f'{code}.pmtiles'), entries)
        counties.append({'code': code, 'name': names.get(code, code), 'tiles': len(entries),
                         'buildings': sum(e[4] for e in entries), 'raw': sum(e[2] for e in entries),
                         'gzipped': sum(len(e[1]) for e in entries), 'archive': size,
                         'zipped': len(zlib.compress(open(os.path.join(out, 'counties', f'{code}.pmtiles'), 'rb').read(), 9))})
    whole_bytes = open(os.path.join(out, 'taiwan.pmtiles'), 'rb').read()
    report = {
        'extract': os.path.basename(extract_path),
        'tolerance': tolerance,
        'tiles': len(results),
        'buildings': totals[0],
        'fromOpenStreetMap': sources[0], 'fromShi': sources[1],
        'withStoreys': with_storeys,
        'storeysFrom': dict(zip(STOREYS_FROM, origins)),
        'ringsDropped': totals[1],
        'pointsBefore': totals[2], 'pointsAfter': totals[3],
        'footprintKm2': round(totals[4] / 1e6, 2),
        'areaChangedShare': round(totals[5] / totals[4], 5),
        'buildingsMovedOver5Percent': totals[6],
        'largestRelativeChange': round(totals[7], 3),
        'rawBytes': raw_bytes,
        'gzippedTileBytes': sum(len(p) for _, p in everything),
        'archiveBytes': len(whole_bytes),
        'archiveZippedBytes': len(zlib.compress(whole_bytes, 9)),
        'bytesPerBuilding': round(len(whole_bytes) / totals[0], 2),
        'sha256': hashlib.sha256(whole_bytes).hexdigest(),
        'counties': counties,
    }
    with open(os.path.join(out, 'report.json'), 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps({k: v for k, v in report.items() if k != 'counties'}, ensure_ascii=False, indent=1))


def county_names(extract_path):
    import duckdb
    return dict(duckdb.connect().sql(f"SELECT DISTINCT county, county_name FROM read_parquet('{extract_path}')").fetchall())


# --- heights ---------------------------------------------------------------

DENSITY_BANDS = [0, 500, 2_000, 5_000, 10_000, 20_000, 40_000]   # people a km²
AREA_BANDS = [0, 50, 100, 200, 400, 1_000, 3_000]                # footprint m²


def band(value, cuts):
    index = 0
    for i, cut in enumerate(cuts):
        if value >= cut:
            index = i
    return index


def density_lookup(population_path):
    population = json.load(open(population_path))
    size, north, west = population['cellDegrees'], population['north'], population['west']
    people = {}
    for run in population['runs']:
        for offset, count in enumerate(run['p']):
            people[(run['r'], run['c'] + offset)] = count

    def density(lon, lat):
        km2 = (math.radians(size) * 6_371.0088) ** 2 * math.cos(math.radians(lat))
        return people.get((int((north - lat) // size), int((lon - west) // size)), 0) / km2
    return density


def heights(extract_path, population_path, out):
    """Storeys of the buildings that have them, by the density of people
    round them, their footprint and their use: the quartiles each band's
    unknown buildings would be drawn from (decision 386, step 2's proposal)."""
    import duckdb
    density = density_lookup(population_path)
    connection = duckdb.connect()
    connection.sql('INSTALL spatial; LOAD spatial;')
    rows = connection.sql(f"""
        SELECT num_floors, height, subtype, lon, lat,
               ST_Area(ST_GeomFromWKB(footprint)) * {(math.radians(1) * EARTH) ** 2} * cos(radians(lat))
        FROM read_parquet('{extract_path}')
    """).fetchall()
    known, everyone = {}, {}
    for floors, height, subtype, lon, lat, size in rows:
        group = group_of(subtype)
        key = (group, band(density(lon, lat), DENSITY_BANDS), band(size, AREA_BANDS))
        everyone[key] = everyone.get(key, 0) + 1
        storeys = storeys_of(floors, height)
        if storeys:
            known.setdefault(key, []).append(storeys)
    table = []
    for key in sorted(everyone):
        values = sorted(known.get(key, []))

        def q(p):
            return values[min(len(values) - 1, int(p * len(values)))] if values else None
        table.append({'group': key[0], 'density': DENSITY_BANDS[key[1]], 'area': AREA_BANDS[key[2]],
                      'buildings': everyone[key], 'known': len(values),
                      'p25': q(0.25), 'median': q(0.5), 'p75': q(0.75)})
    with open(out, 'w') as file:
        json.dump({'densityBands': DENSITY_BANDS, 'areaBands': AREA_BANDS, 'table': table}, file, indent=1)
    print(json.dumps(table, indent=0)[:4000])


def proposed_storeys(table, group, density, size, x, y):
    """Step 2's proposal: a building of unknown storeys gets one from its
    band's p25–p75, picked by a hash of where it is, so it never changes."""
    entry = table.get((group, band(density, DENSITY_BANDS), band(size, AREA_BANDS)))
    if not entry or entry['known'] < 30:
        low, high = (1, 2) if group == 'industrial' else (2, 4)
    else:
        low, high = entry['p25'], max(entry['p25'], entry['p75'])
    h = (x * 73856093 ^ y * 19349663) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 0x5BD1E995 & 0xFFFFFFFF
    return low + (h ^ (h >> 15)) % (high - low + 1)


def group_of(subtype):
    return 'industrial' if subtype in ('industrial', 'agricultural', 'outbuilding') else \
        'other' if subtype not in (None, 'residential', 'commercial') else 'homes'


def picked_storeys(table, group, density, size, metres, x, y):
    """Decision 389: the density guess, GHSL's height of the 100 m cell
    (`metres`, 0 or None where it has none) picking the band's p75 when a
    storey or more above its median, p25 when a storey or more below, the
    median else; where GHSL has nothing, `proposed_storeys`' hash of `x`
    and `y`. A band with too few known buildings picks from its default
    range alike."""
    entry = table.get((group, band(density, DENSITY_BANDS), band(size, AREA_BANDS)))
    if not entry or entry['known'] < 30:
        low, high = (1, 2) if group == 'industrial' else (2, 4)
        middle = (low + high) // 2
    else:
        low, middle, high = entry['p25'], entry['median'], max(entry['p25'], entry['p75'])
    if not metres:
        return proposed_storeys(table, group, density, size, x, y)
    guess = metres / LEVEL_HEIGHT
    return high if guess >= middle + 1 else low if guess <= middle - 1 else middle


def permit_fits(storeys, size):
    """Whether a permit's storeys can be this footprint's (decision 389):
    a permit's polygon is the whole site, so its tower's count also lands
    on the podium, the station hall or a shed beside it. Not over Taipei
    101's 101, not over eight times as tall as the footprint is across,
    and no tower of 20 or more on a footprint over 5,000 m²."""
    return storeys <= 101 and storeys * LEVEL_HEIGHT <= 8 * math.sqrt(size) and not (storeys >= 20 and size > 5000)


def storeys(extract_path, population_path, heights_path, ghsl_dir, taichung, taipei, out):
    """Every building's storeys and where they came from (decision 386's
    point 6), for `build`."""
    import duckdb
    import measure_height_sources as M
    connection = M.connect(extract_path)
    M.load_twd97(connection, 'taipei', taipei,
                 "coalesce(nullif(bud_floor::INT, 0), try_cast(regexp_extract(budatt_no, '(\\d+)F$', 1) AS INT))")
    # Taichung's maps newest first: a building takes the first that covers it.
    city = {}
    for index, path in enumerate(taichung.split(os.pathsep)):
        M.load_twd97(connection, f'taichung{index}', path, 'B1D')
        for k, v in M.matched(connection, f'taichung{index}').items():
            city.setdefault(k, max(1, min(255, round(v))))
        connection.sql(f'DROP TABLE taichung{index}')
    permits = {k: max(1, min(255, round(v))) for k, v in M.matched(connection, 'taipei').items()}
    ghsl = M.ghsl_lookup(ghsl_dir)
    density = density_lookup(population_path)
    table = {(e['group'], DENSITY_BANDS.index(e['density']), AREA_BANDS.index(e['area'])): e
             for e in json.load(open(heights_path))['table']}
    square = (math.radians(1) * EARTH) ** 2
    rows = connection.sql(f"""
        SELECT id, num_floors, height, subtype, lon, lat, ST_Area(geom) * {square} * cos(radians(lat)) FROM o ORDER BY id
    """).fetchall()
    out_rows, counts = [], [0] * len(STOREYS_FROM)
    for id_, floors, height, subtype, lon, lat, size in rows:
        tagged = storeys_of(floors, height)
        if id_ in city:
            value, origin = city[id_], STOREYS_FROM.index('cityMap')
        elif tagged:
            value, origin = tagged, STOREYS_FROM.index('tags')
        elif id_ in permits and permit_fits(permits[id_], size):
            value, origin = permits[id_], STOREYS_FROM.index('permits')
        else:
            value = picked_storeys(table, group_of(subtype), density(lon, lat), size, ghsl(lon, lat),
                                   int(lon * 1e5), int(lat * 1e5))
            origin = STOREYS_FROM.index('guess')
        counts[origin] += 1
        out_rows.append((id_, value, origin))
    # Through a CSV beside `out`: DuckDB's row-by-row insert takes hours.
    import csv
    scratch = out + '.csv'
    with open(scratch, 'w', newline='') as file:
        csv.writer(file).writerows(out_rows)
    duckdb.connect().sql(f"""
        COPY (SELECT * FROM read_csv('{scratch}', header = false, columns = {{'id': 'VARCHAR', 'storeys': 'INTEGER', 'origin': 'INTEGER'}})
              ORDER BY id) TO '{out}' (FORMAT parquet, COMPRESSION zstd)
    """)
    os.remove(scratch)
    print(json.dumps(dict(zip(STOREYS_FROM, counts))), file=sys.stderr)


# --- a window for the 3D map's measurement ----------------------------------

def window(archive_path, lat, lon, side, heights_path, population_path, out):
    """The buildings whose first point lies in the square of `side` metres
    round (`lat`, `lon`), read back from the archive, as latitudes and
    longitudes, each with its storeys (proposed where unknown) and use."""
    sys.path.insert(0, os.path.join(HERE, '..', 'basemap'))
    lat, lon, side = float(lat), float(lon), float(side)
    data = open(archive_path, 'rb').read()
    entries = read_directory(data)
    table = {(e['group'], DENSITY_BANDS.index(e['density']), AREA_BANDS.index(e['area'])): e
             for e in json.load(open(heights_path))['table']}
    density = density_lookup(population_path)
    half_lat = side / 2 / 111_320
    half_lon = side / 2 / (111_320 * math.cos(math.radians(lat)))
    x0, y0 = tile_of(lon - half_lon, lat + half_lat)
    x1, y1 = tile_of(lon + half_lon, lat - half_lat)
    buildings = []
    for tx in range(int(x0) - 1, int(x1) + 2):
        for ty in range(int(y0) - 1, int(y1) + 2):
            blob = entries.get(tile_id_of(tx, ty))
            if blob is None:
                continue
            for storeys, use, source, rings, _ in decode_tile(gzip.decompress(blob)):
                def geo(p):
                    wx, wy = tx + p[0] / EXTENT, ty + p[1] / EXTENT
                    return (math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * wy / (1 << ZOOM))))),
                            wx / (1 << ZOOM) * 360 - 180)
                points = [geo(p) for p in rings[0]]
                la, lo = points[0]
                if abs(la - lat) > half_lat or abs(lo - lon) > half_lon:
                    continue
                cos = math.cos(math.radians(la))
                size = abs(sum((points[i - 1][1] * points[i][0] - points[i][1] * points[i - 1][0])
                               for i in range(len(points)))) / 2 * 111_320 ** 2 * cos
                subtype = USES[use - 1] if use else None
                group = group_of(subtype)
                known = storeys > 0
                if not known:
                    storeys = proposed_storeys(table, group, density(lo, la), size, *rings[0][0])
                buildings.append({'storeys': storeys, 'known': known, 'use': subtype or '', 'shi': source,
                                  'rings': [[[round(a, 7), round(b, 7)] for a, b in map(geo, r)] for r in rings]})
    with open(out, 'w') as file:
        json.dump({'latitude': lat, 'longitude': lon, 'side': side, 'buildings': buildings}, file)
    print(f'{len(buildings)} buildings, {sum(b["known"] for b in buildings)} with storeys', file=sys.stderr)


def tile_id_of(x, y):
    from build_basemap import tile_id
    return tile_id(ZOOM, x, y)


def read_directory(data):
    """Tile id → gzipped bytes of an archive `write_pmtiles` wrote."""
    (root_offset, root_length, _, _, leaf_offset, _, data_offset) = struct.unpack_from('<7Q', data, 8)

    def entries(offset, length):
        raw = gzip.decompress(data[offset:offset + length])
        at = 0

        def read():
            nonlocal at
            value = shift = 0
            while True:
                byte = raw[at]
                at += 1
                value |= (byte & 0x7F) << shift
                shift += 7
                if byte < 0x80:
                    return value
        n = read()
        ids, last = [], 0
        for _ in range(n):
            last += read()
            ids.append(last)
        runs = [read() for _ in range(n)]
        lengths = [read() for _ in range(n)]
        offsets = []
        for i in range(n):
            o = read()
            offsets.append(offsets[i - 1] + lengths[i - 1] if o == 0 else o - 1)
        return list(zip(ids, runs, lengths, offsets))

    out = {}
    for tid, run, length, offset in entries(root_offset, root_length):
        if run == 0:
            for t, r, n, o in entries(leaf_offset + offset, length):
                for k in range(r):
                    out[t + k] = data[data_offset + o:data_offset + o + n]
        else:
            for k in range(run):
                out[tid + k] = data[data_offset + offset:data_offset + offset + length]
    return out


if __name__ == '__main__':
    command, arguments = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ('', [])
    if command == 'extract' and len(arguments) == 3:
        extract(*arguments)
    elif command == 'build' and len(arguments) in (2, 3, 4):
        build(*arguments)
    elif command == 'storeys' and len(arguments) == 7:
        storeys(*arguments)
    elif command == 'heights' and len(arguments) == 3:
        heights(*arguments)
    elif command == 'window' and len(arguments) == 7:
        window(*arguments)
    else:
        sys.exit(__doc__)
