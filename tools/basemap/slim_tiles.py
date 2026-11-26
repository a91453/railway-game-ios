#!/usr/bin/env python3
"""Decision 1005: smaller map files, the same map. Rewrites PMTiles
archives in place, keeping their header's bounds, centre and zooms:

    python3 -I tools/basemap/slim_tiles.py basemap FILE...
    python3 -I tools/basemap/slim_tiles.py buildings FILE...
    python3 -I tools/basemap/slim_tiles.py terrain FILE...

`basemap` (a base map `build_basemap.py` wrote, Taiwan's or a map pack's):

- zoom 14, the most detailed, which the 3D map, the road cells and the
  buses read: every point on whole units of 2048 a side, not 4096 (0.5 m
  to 1 m in Taiwan and Kyushu; the roads are simplified to 2 units of
  4096 there anyway). A line or ring that rounds to nothing goes.
- zoom 13: no `minor` roads (`transportation` class `minor`, the streets
  `build_basemap.ROADS` gives zoom 13); the 2D map draws them from
  zoom 14's tiles, a zoom closer.

`buildings` (footprint tiles, `footprints/2`): every tile as `footprints/3`
(`build_footprint_tiles.coarsened`, 2048 units a side, about 0.25 m),
the format the tools write since this decision.

`terrain` (hill shading `build_terrain.py` wrote): without the zooms past
`build_terrain.LAST_ZOOM` (zoom 10, two thirds of the file), the tiles
it keeps as they are; what `build_terrain.py` writes since this decision,
without making it again from the heights.

All three are idempotent: a file already slimmed is written again
unchanged.
"""
import gzip
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'overture-footprint-tiles'))
import build_basemap as base  # noqa: E402

# The most detailed zoom's units a side.
FINE_EXTENT = 2048
# The zoom whose minor roads go.
NO_MINOR_ZOOM = 13


# --- PMTiles ---------------------------------------------------------------

def read_archive(path):
    """(tiles {id: stored bytes}, metadata, header fields) of a PMTiles v3
    archive `base.write_pmtiles` wrote."""
    import build_footprint_tiles as tiles
    data = open(path, 'rb').read()
    assert data[:7] == b'PMTiles' and data[7] == 3, path
    fields = struct.unpack_from('<BQQQQQQQQQQQBBBBBBiiiiBii', data, 7)
    meta_offset, meta_length = fields[3], fields[4]
    metadata = json.loads(gzip.decompress(data[meta_offset:meta_offset + meta_length]))
    header = {
        'tile_compression': fields[14], 'tile_type': fields[15], 'zooms': (fields[16], fields[17]),
        'bounds': tuple(v / 1e7 for v in fields[18:22]), 'center': (fields[23] / 1e7, fields[24] / 1e7, fields[22]),
    }
    return tiles.read_directory(data), metadata, header


def write_archive(path, entries, metadata, header):
    base.write_pmtiles(path, sorted(entries.items()), metadata, header['bounds'], header['center'],
                       tile_type=header['tile_type'], tile_compression=header['tile_compression'],
                       zooms=header['zooms'])


def zxy(tid):
    """The zoom, column and row of a PMTiles tile id."""
    z = 0
    while ((1 << (2 * (z + 1))) - 1) // 3 <= tid:
        z += 1
    d = tid - ((1 << (2 * z)) - 1) // 3
    x = y = 0
    s = 1
    while s < (1 << z):
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


# --- vector tiles ----------------------------------------------------------

def _varint(data, at):
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return value, at


def _fields(data):
    """(field number, wire type, value or bytes) of a protobuf message."""
    at = 0
    while at < len(data):
        key, at = _varint(data, at)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, at = _varint(data, at)
        elif wire == 2:
            length, at = _varint(data, at)
            value, at = bytes(data[at:at + length]), at + length
        elif wire == 5:
            value, at = bytes(data[at:at + 4]), at + 4
        elif wire == 1:
            value, at = bytes(data[at:at + 8]), at + 8
        else:
            raise ValueError(f'wire type {wire}')
        yield number, wire, value


def _packed(data):
    out, at = [], 0
    while at < len(data):
        value, at = _varint(data, at)
        out.append(value)
    return out


def decode_layer(data):
    """{'name', 'extent', 'features': [(id or None, tags [(key, value
    bytes)], kind, geometry [int])]} of a vector tile layer."""
    keys, values, raw = [], [], []
    layer = {'name': '', 'extent': 4096, 'features': []}
    for number, _, value in _fields(data):
        if number == 1:
            layer['name'] = value.decode()
        elif number == 2:
            raw.append(value)
        elif number == 3:
            keys.append(value.decode())
        elif number == 4:
            values.append(value)
        elif number == 5:
            layer['extent'] = value
    for blob in raw:
        fid, tags, kind, geometry = None, [], 0, []
        for number, _, value in _fields(blob):
            if number == 1:
                fid = value
            elif number == 2:
                tags = _packed(value)
            elif number == 3:
                kind = value
            elif number == 4:
                geometry = _packed(value)
        layer['features'].append((fid, [(keys[tags[i]], values[tags[i + 1]]) for i in range(0, len(tags), 2)],
                                  kind, geometry))
    return layer


def encode_layer(layer):
    """A layer's bytes, in `build_basemap.encode_layer`'s field order, its
    keys and values in the order the features first use them."""
    keys, values, key_index, value_index = [], [], {}, {}
    body = bytearray()
    for fid, tags, kind, geometry in layer['features']:
        numbers = []
        for key, value in tags:
            if key not in key_index:
                key_index[key] = len(keys)
                keys.append(key)
            if value not in value_index:
                value_index[value] = len(values)
                values.append(value)
            numbers += (key_index[key], value_index[value])
        feature = b''
        if fid is not None:
            feature += base.varint(1 << 3) + base.varint(fid)
        feature += base.packed(2, numbers) + base.varint(3 << 3) + base.varint(kind) + base.packed(4, geometry)
        body += base.field_bytes(2, feature)
    out = base.varint(15 << 3) + base.varint(2) + base.field_bytes(1, layer['name'].encode()) + bytes(body)
    for key in keys:
        out += base.field_bytes(3, key.encode())
    for value in values:
        out += base.field_bytes(4, value)
    return out + base.varint(5 << 3) + base.varint(layer['extent'])


def decode_tile(data):
    return [decode_layer(value) for number, _, value in _fields(data) if number == 3]


def encode_tile(layers):
    return b''.join(base.field_bytes(3, encode_layer(layer)) for layer in layers)


def _signed(v):
    return (v >> 1) ^ -(v & 1)


def parts(geometry):
    """A feature's geometry as parts of absolute points, each (points,
    closed)."""
    out, at, x, y = [], 0, 0, 0
    while at < len(geometry):
        command, count = geometry[at] & 7, geometry[at] >> 3
        at += 1
        if command == 7:
            out[-1] = (out[-1][0], True)
            continue
        for _ in range(count):
            x += _signed(geometry[at])
            y += _signed(geometry[at + 1])
            at += 2
            if command == 1:
                out.append(([(x, y)], False))
            else:
                out[-1][0].append((x, y))
    return out


def geometry_of(pieces):
    out, cx, cy = [], 0, 0
    for points, closed in pieces:
        cx, cy = base.path(out, points, cx, cy, closed)
    return out


def finer_feature(kind, geometry, extent):
    """A feature's geometry on FINE_EXTENT units (from `extent`), or None
    when nothing of it is left."""
    step = extent // FINE_EXTENT

    def q(v):
        return (v + step // 2) // step

    if kind == 1:
        out = []
        for points, _ in parts(geometry):
            for x, y in points:
                p = (min(max(q(x), 0), FINE_EXTENT - 1), min(max(q(y), 0), FINE_EXTENT - 1))
                out.append(([p], False))
        if not out:
            return None
        # MoveTo with all the points, as a multipoint is written.
        flat = [base.command(1, len(out))]
        cx = cy = 0
        for (p,), _ in out:
            flat += (base.zigzag(p[0] - cx), base.zigzag(p[1] - cy))
            cx, cy = p
        return flat
    kept = []
    if kind == 2:
        for points, _ in parts(geometry):
            line = []
            for x, y in points:
                p = (q(x), q(y))
                if not line or line[-1] != p:
                    line.append(p)
            if len(line) >= 2:
                kept.append((line, False))
        return geometry_of(kept) if kept else None
    # Polygons: an outer ring (positive area, y down) and its holes; a ring
    # that rounds to no area or turns over goes, an outer one with its holes.
    outer = False
    for points, _ in parts(geometry):
        signed = base.shoelace(points)
        is_outer = signed > 0
        ring = []
        for x, y in points:
            p = (q(x), q(y))
            if not ring or ring[-1] != p:
                ring.append(p)
        while len(ring) > 1 and ring[0] == ring[-1]:
            ring.pop()
        now = base.shoelace(ring) if len(ring) >= 3 else 0
        if now == 0 or (now > 0) != is_outer:
            if is_outer:
                outer = False
            continue
        if is_outer:
            outer = True
        elif not outer:
            continue
        kept.append((ring, True))
    return geometry_of(kept) if kept else None


def slim_vector(data, z):
    """A base map tile's bytes (unzipped) of zoom `z`, slimmed, or None
    when it is left with nothing."""
    layers = decode_tile(data)
    out = []
    for layer in layers:
        features = layer['features']
        if z == NO_MINOR_ZOOM and layer['name'] == 'transportation':
            minor = base.field_bytes(1, b'minor')
            features = [f for f in features if ('class', minor) not in f[1]]
        if z == base.MAX_ZOOM and layer['extent'] != FINE_EXTENT:
            finer = []
            for fid, tags, kind, geometry in features:
                geometry = finer_feature(kind, geometry, layer['extent'])
                if geometry is not None:
                    finer.append((fid, tags, kind, geometry))
            features = finer
            layer = dict(layer, extent=FINE_EXTENT)
        if features:
            out.append(dict(layer, features=features))
    return encode_tile(out) if out else None


def basemap(path):
    entries, metadata, header = read_archive(path)
    before = os.path.getsize(path)
    out, done = {}, {}
    for tid, stored in entries.items():
        z = zxy(tid)[0]
        if z not in (NO_MINOR_ZOOM, base.MAX_ZOOM):
            out[tid] = stored
            continue
        # The same tile (the open sea) is slimmed once.
        if (z, stored) not in done:
            slim = slim_vector(gzip.decompress(stored), z)
            done[z, stored] = None if slim is None else gzip.compress(slim, 9, mtime=0)
        if done[z, stored] is not None:
            out[tid] = done[z, stored]
    metadata['slimmed'] = 'decision 1005: zoom 14 on 2048 units a side, zoom 13 without minor roads'
    write_archive(path, out, metadata, header)
    print(f'{path}: {before:,} → {os.path.getsize(path):,} bytes', flush=True)


def buildings(path):
    import build_footprint_tiles as tiles
    entries, metadata, header = read_archive(path)
    before = os.path.getsize(path)
    out = {}
    for tid, stored in entries.items():
        _, _, y = zxy(tid)
        raw = tiles.coarsened(gzip.decompress(stored), y)
        if raw[1:2] != b'\x00':  # tiles.written(...) of no building: version, 0
            out[tid] = gzip.compress(raw, 9, mtime=0)
    metadata['format'] = f'footprints/{tiles.VERSION}'
    metadata['extent'] = tiles.WRITTEN_EXTENT
    write_archive(path, out, metadata, header)
    print(f'{path}: {before:,} → {os.path.getsize(path):,} bytes', flush=True)


def terrain(path):
    import build_terrain
    entries, metadata, header = read_archive(path)
    before = os.path.getsize(path)
    last = build_terrain.LAST_ZOOM
    out = {tid: stored for tid, stored in entries.items() if zxy(tid)[0] <= last}
    header['zooms'] = (header['zooms'][0], min(header['zooms'][1], last))
    write_archive(path, out, metadata, header)
    print(f'{path}: {before:,} → {os.path.getsize(path):,} bytes', flush=True)


if __name__ == '__main__':
    steps = {'basemap': basemap, 'buildings': buildings, 'terrain': terrain}
    if len(sys.argv) < 3 or sys.argv[1] not in steps:
        sys.exit(__doc__)
    for file in sys.argv[2:]:
        steps[sys.argv[1]](file)
