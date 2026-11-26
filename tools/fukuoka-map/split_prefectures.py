#!/usr/bin/env python3
"""Cut Japan's map pack along the prefectures' borders (decision 991).

    osmium tags-filter -o /tmp/fk/osm/admin4.pbf /tmp/fk/osm/kyushu.pbf r/admin_level=4
    python3 -I tools/fukuoka-map/split_prefectures.py /tmp/fk/osm/admin4.pbf \\
        RailwayGameApp/Resources/MapPacks

The owner (2026-11-26): 「依日本道縣分界拆分」 — Fukuoka's pack holds the
whole of Fukuoka Prefecture, Kumamoto's the whole of Kumamoto Prefecture,
and Saga, between them, a pack of its own; decision 997 added Nagasaki
Prefecture, west of Saga, a fourth. The map stays one map: the game
reads the three as one pack (`MapPack` lists a part's files in the city's
`pack.json` by folder and name), and each is an asset pack of its own, so
a change to Kumamoto's tiles uploads Kumamoto's pack alone.

What is cut is the two heavy files, `basemap.pmtiles` and
`buildings.pmtiles` (nine tenths of the pack): every tile of every zoom
goes to the one part whose prefecture holds the tile's middle, so no two
parts have the same tile and a reader takes the first that has it. A tile
whose middle no prefecture of the four holds (the sea, and the corners of
Oita, Yamaguchi, Kagoshima and Miyazaki the map's box reaches) goes to the
nearest prefecture. Everything else (the railways, heights,
water, people, airfields, land no one builds on, hill shading) stays whole
in Fukuoka's folder: it is small, and the game reads each as one grid.

The borders are OpenStreetMap's (`boundary=administrative`,
`admin_level=4`, 福岡県, 佐賀県, 熊本県, 長崎県) from the Kyushu extract's
relations of that level, whole (`osmium extract` cuts a box's relations
other than multipolygons, so the ground's extract has none), simplified to
some 100 m, which only says which part a tile is kept in. The same
extract gives the same parts, byte for byte.

Reads `MapPacks/fukuoka/basemap.pmtiles` and `buildings.pmtiles` as the
ground tools wrote them (the whole map), writes Fukuoka's share in their
place and the others' to `MapPacks/fukuoka-saga/`,
`MapPacks/fukuoka-kumamoto/` and `MapPacks/fukuoka-nagasaki/`, and lists the parts' files in `pack.json`.
Run it once after `build_fukuoka_ground.py basemap` and `buildings`; run
on parts already cut it stops (the whole map's file is no longer there).
"""
import gzip
import hashlib
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'basemap'))
import build_basemap  # noqa: E402

# The parts, in the order the game reads them: the city's own folder first.
PARTS = (
    ('fukuoka', '福岡県'),
    ('fukuoka-saga', '佐賀県'),
    ('fukuoka-kumamoto', '熊本県'),
    # Decision 997: Nagasaki Prefecture, the map's west edge moved to take
    # it in.
    ('fukuoka-nagasaki', '長崎県'),
)
FILES = ('basemap.pmtiles', 'buildings.pmtiles')
# The cells the parts are looked up in, in degrees, and how far the
# borders are simplified.
CELL = 0.005
SIMPLIFY = 0.001


# --- PMTiles v3 -------------------------------------------------------------

def varints(data):
    value, shift = 0, 0
    for byte in data:
        value |= (byte & 0x7F) << shift
        if byte & 0x80:
            shift += 7
        else:
            yield value
            value, shift = 0, 0


def entries_of(blob):
    numbers = list(varints(gzip.decompress(blob)))
    count = numbers[0]
    ids, runs, lengths, offsets = (numbers[1 + count * k:1 + count * (k + 1)] for k in range(4))
    out, last_id = [], 0
    for i in range(count):
        last_id += ids[i]
        offset = out[-1][1] + out[-1][2] if offsets[i] == 0 else offsets[i] - 1
        out.append((last_id, offset, lengths[i], runs[i]))
    return out


def read_pmtiles(path):
    """(header fields, metadata, {tile id: bytes}) of a PMTiles v3 file."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:7] != b'PMTiles' or data[7] != 3:
        sys.exit(f'{path}: not a PMTiles v3 file')
    (root_offset, root_length, meta_offset, meta_length, leaf_offset, leaf_length, data_offset, _data_length,
     _addressed, _entries, _contents, _clustered, _internal, tile_compression, tile_type, min_zoom, max_zoom,
     *_rest) = struct.unpack('<QQQQQQQQQQQBBBBBBiiiiBii', data[8:127])
    metadata = json.loads(gzip.decompress(data[meta_offset:meta_offset + meta_length]))
    tiles = {}

    def walk(entries):
        for tile_id, offset, length, run in entries:
            if run == 0:
                start = leaf_offset + offset
                walk(entries_of(data[start:start + length]))
            else:
                blob = data[data_offset + offset:data_offset + offset + length]
                for k in range(run):
                    tiles[tile_id + k] = blob

    walk(entries_of(data[root_offset:root_offset + root_length]))
    return (tile_compression, tile_type, min_zoom, max_zoom), metadata, tiles


def zxy(tile_id):
    """The zoom, column and row of a PMTiles tile id (the inverse of
    `build_basemap.tile_id`)."""
    z, acc = 0, 0
    while tile_id >= acc + (1 << (2 * z)):
        acc += 1 << (2 * z)
        z += 1
    d, x, y, s = tile_id - acc, 0, 0, 1
    n = 1 << z
    while s < n:
        rx = 1 & (d // 2)
        ry = 1 & (d ^ rx)
        if ry == 0:
            if rx == 1:
                x, y = s - 1 - x, s - 1 - y
            x, y = y, x
        x += s * rx
        y += s * ry
        d //= 4
        s *= 2
    return z, x, y


def corner(z, x, y):
    """The (longitude, latitude) of a tile's north-west corner."""
    n = 1 << z
    return x / n * 360 - 180, math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))


# --- the borders -------------------------------------------------------------

def borders(extract):
    import osmium
    import shapely.wkb
    names = {name for _, name in PARTS}
    found = {}
    factory = osmium.geom.WKBFactory()

    class Areas(osmium.SimpleHandler):
        def area(self, a):
            tags = a.tags
            if tags.get('boundary') == 'administrative' and tags.get('admin_level') == '4' and tags.get('name') in names:
                found[tags['name']] = shapely.wkb.loads(factory.create_multipolygon(a), hex=True)

    Areas().apply_file(extract, locations=True)
    missing = names - set(found)
    if missing:
        sys.exit(f'{extract}: no border of {", ".join(sorted(missing))}')
    return [found[name].simplify(SIMPLIFY) for _, name in PARTS]


class Lookup:
    """Which part holds a place: the prefecture whose border holds it, else
    the nearest one, worked out once for each cell of the extent."""

    def __init__(self, shapes, extent):
        from shapely.geometry import Point
        from shapely.prepared import prep
        self.extent = extent
        self.rows = math.ceil((extent['north'] - extent['south']) / CELL)
        self.columns = math.ceil((extent['east'] - extent['west']) / CELL)
        prepared = [prep(shape) for shape in shapes]
        self.cells = bytearray(self.rows * self.columns)
        for row in range(self.rows):
            latitude = extent['north'] - (row + 0.5) * CELL
            for column in range(self.columns):
                point = Point(extent['west'] + (column + 0.5) * CELL, latitude)
                part = next((k for k, shape in enumerate(prepared) if shape.contains(point)), None)
                if part is None:
                    distances = [shape.distance(point) for shape in shapes]
                    part = distances.index(min(distances))
                self.cells[row * self.columns + column] = part

    def part(self, longitude, latitude):
        e = self.extent
        row = min(max(int((e['north'] - latitude) / CELL), 0), self.rows - 1)
        column = min(max(int((longitude - e['west']) / CELL), 0), self.columns - 1)
        return self.cells[row * self.columns + column]


# --- the cut -----------------------------------------------------------------

def cut(path, lookup, folders):
    """Writes the tiles of `path` to the part each belongs to (`folders`,
    one file each, the first in place of `path`); [(bytes, tiles)]."""
    (compression, tile_type, min_zoom, max_zoom), metadata, tiles = read_pmtiles(path)
    shares = [[] for _ in folders]
    for tile_id, blob in tiles.items():
        z, x, y = zxy(tile_id)
        west, north = corner(z, x, y)
        east, south = corner(z, x + 1, y + 1)
        shares[lookup.part((west + east) / 2, (north + south) / 2)].append((tile_id, blob))
    name = os.path.basename(path)
    written = []
    for folder, share in zip(folders, shares):
        os.makedirs(folder, exist_ok=True)
        boxes = [corner(*zxy(t)) + corner(zxy(t)[0], zxy(t)[1] + 1, zxy(t)[2] + 1) for t, _ in share if zxy(t)[0] == max_zoom]
        west = min(b[0] for b in boxes)
        north = max(b[1] for b in boxes)
        east = max(b[2] for b in boxes)
        south = min(b[3] for b in boxes)
        center = ((west + east) / 2, (south + north) / 2, max(min_zoom, min(max_zoom, 10)))
        meta = dict(metadata)
        meta['bounds'] = [round(v, 6) for v in (west, south, east, north)]
        out = os.path.join(folder, name)
        build_basemap.write_pmtiles(out, list(share), meta, (west, south, east, north), center,
                                    tile_type=tile_type, tile_compression=compression, zooms=(min_zoom, max_zoom))
        written.append((os.path.getsize(out), len(share)))
    return written


def sha256(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def main(extract, packs):
    import build_fukuoka_rail
    own = os.path.join(packs, PARTS[0][0])
    manifest_path = os.path.join(own, 'pack.json')
    with open(manifest_path, encoding='utf-8') as f:
        manifest = json.load(f)
    if any('/' in name for name in manifest['files']):
        sys.exit(f'{manifest_path}: the parts are cut already; make the whole map again first')
    lookup = Lookup(borders(extract), build_fukuoka_rail.EXTENT)
    folders = [os.path.join(packs, folder) for folder, _ in PARTS]
    report = {}
    for name in FILES:
        written = cut(os.path.join(own, name), lookup, folders)
        entry = manifest['files'][name]
        for (folder, prefecture), (size, count) in zip(PARTS, written):
            key = name if folder == PARTS[0][0] else f'{folder}/{name}'
            part = dict(entry)
            part['bytes'] = size
            part['sources'] = dict(entry['sources'])
            part['sources'][f'the tiles whose middle {prefecture} holds, or is nearest '
                            '(tools/fukuoka-map/split_prefectures.py)'] = 'OpenStreetMap'
            manifest['files'][key] = part
            report[key] = {'bytes': size, 'tiles': count, 'sha256': sha256(os.path.join(packs, folder, name))}
            print(f'{key}: {count} tiles, {size / 1e6:.1f} MB')
    # The other files as the ground tools left them, and where the map
    # lies (decision 991: laid anew, the games before it on `older`).
    for name, entry in manifest['files'].items():
        if '/' not in name and name not in FILES:
            entry['bytes'] = os.path.getsize(os.path.join(own, name))
    manifest['extent'] = build_fukuoka_rail.EXTENT
    manifest.pop('earlier', None)
    manifest['starts'] = build_fukuoka_rail.STARTS
    manifest['older'] = build_fukuoka_rail.OLDER
    manifest['files'] = dict(sorted(manifest['files'].items()))
    manifest['bytes'] = sum(entry['bytes'] for entry in manifest['files'].values())
    manifest['parts'] = {folder: prefecture for folder, prefecture in PARTS[1:]}
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, separators=(',', ':'))
    return report


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main(sys.argv[1], sys.argv[2])
