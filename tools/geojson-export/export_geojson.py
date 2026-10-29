#!/usr/bin/env python3
"""Writes the game's position data as GeoJSON (WGS84) for geolibre.app.

Layers: stations, lines, depots, roads, cells. Standard library only; run
with `python3 -I` (README.md).
"""
import argparse
import gzip
import json
import math
import os
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
RAILWAYS = os.path.join(ROOT, 'RailwayGameApp', 'Resources', 'RealRailways')
BASEMAP = os.path.join(ROOT, 'RailwayGameApp', 'Resources', 'BaseMap', 'taiwan.pmtiles')
HSR_DEPOTS = os.path.join(ROOT, 'tools', 'hsr-depots', 'hsr_depots.json')

OSM = '© OpenStreetMap contributors, ODbL 1.0'
TDX = '交通部 TDX（政府資料開放授權條款－第1版）'

# Same constants as RealWorldFrame (RealWorldDemo.swift) and Land.cellLength.
WORLD_POINTS = 268_435_456.0
EARTH_RADIUS = 6_378_137.0
CELL_METRES = 64.0
SAMPLE_METRES = 8.0  # RealRoadCells.sampleMetres
ZOOM = 14  # BaseMapTiles.zoom
WORLD_METRES = 16_384.0  # a new game's world, a side


def collection(name, license_text, features):
    return {'type': 'FeatureCollection', 'name': name, 'license': license_text, 'features': features}


def write(path, data):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    print(f'{path}: {len(data["features"])} features, {os.path.getsize(path) / 1024:.0f} KiB')


def feature(geometry, **props):
    return {'type': 'Feature', 'properties': props, 'geometry': geometry}


# --- stations and lines (bundled, already WGS84) ---------------------------

def in_box(lon, lat, box):
    return box is None or (box[0] <= lon <= box[2] and box[1] <= lat <= box[3])


def stations(box):
    data = json.load(open(os.path.join(RAILWAYS, 'track_stations.geojson'), encoding='utf-8'))
    out = []
    for f in data['features']:
        lon, lat = f['geometry']['coordinates'][:2]
        if not in_box(lon, lat, box):
            continue
        p = f['properties']
        out.append(feature(f['geometry'], name=p.get('name'), system=p.get('sys'), line=p.get('lineId'), color=p.get('color')))
    return collection('stations', f'{OSM}; {TDX}', out)


def lines(box):
    data = json.load(open(os.path.join(RAILWAYS, 'track_lines.geojson'), encoding='utf-8'))
    out = []
    for f in data['features']:
        coords = f['geometry']['coordinates']
        if box and not any(in_box(c[0], c[1], box) for c in coords):
            continue
        p = f['properties']
        out.append(feature(f['geometry'], name=p.get('name'), system=p.get('sys'), id=p.get('id'), color=p.get('color')))
    return collection('lines', f'{OSM}; {TDX}', out)


# --- depots ----------------------------------------------------------------

# Hand-copied from Sources/GamePresentation (RealLineDepot.swift,
# HighSpeedDemo.realDepots, TRADemo.depots): the code is the source.
SANXIA = {'junction': (24.937315, 121.388084), 'yard': ((24.936919, 121.385823), (24.934964, 121.383852)), 'sidings': 4}
HSR_GAME_DEPOTS = [('南港機廠', 25.054203, 121.615057), ('烏日機廠', 24.093566, 120.624164), ('左營機廠', 22.696992, 120.318536)]
TRA_GAME_DEPOTS = [
    ('北端留置線', 24.867724, 121.829668, 0),
    ('宜蘭側線', 24.754210, 121.758450, 2500),
    ('蘇澳新側線', 24.610150, 121.827340, -3400),
]
SIDING_SPACING = 5.0  # metres between OSM yard tracks, for the rough footprint only


def rectangle(lat, lon, bearing_deg, length, width):
    """A rotated rectangle round (lat, lon): `length` metres along the
    compass bearing, `width` across."""
    b = math.radians(bearing_deg)
    ue, un = math.sin(b), math.cos(b)
    ring = []
    for a, c in ((1, 1), (1, -1), (-1, -1), (-1, 1), (1, 1)):
        east = a * ue * length / 2 + c * un * width / 2
        north = a * un * length / 2 - c * ue * width / 2
        ring.append([lon + east / (111320 * math.cos(math.radians(lat))), lat + north / 110574])
    return {'type': 'Polygon', 'coordinates': [ring]}


def depots(box):
    out = []

    def pt(lat, lon):
        return {'type': 'Point', 'coordinates': [lon, lat]}

    osm = json.load(open(HSR_DEPOTS, encoding='utf-8'))
    for d in osm['depots']:
        lat, lon = d['centre']
        if not in_box(lon, lat, box):
            continue
        name = d.get('area', {}) and d['area'].get('name') or f"{d['station']}站旁"
        width = max(d['tracks'], 1) * SIDING_SPACING
        out.append(feature(rectangle(lat, lon, d['axis'], d['trackLength'], width), name=name, kind='hsr_depot_footprint',
                           tracks=d['tracks'], note='約略範圍：停車長度 × 股數 × 5 m，沿主軸', source='tools/hsr-depots/hsr_depots.json'))
        out.append(feature(pt(lat, lon), name=name, kind='hsr_depot_centre', tracks=d['tracks'], source='tools/hsr-depots/hsr_depots.json'))
        for tlat, tlon, node in d['turnouts']:
            out.append(feature(pt(tlat, tlon), name=f'{name} 轉轍器', kind='hsr_depot_turnout', node=node, source='tools/hsr-depots/hsr_depots.json'))
    if in_box(121.386, 24.936, box):
        j, (ys, ye) = SANXIA['junction'], SANXIA['yard']
        out.append(feature(pt(*j), name='三峽機廠 入出庫線岔出點', kind='sanxia_junction', source='RealLineDepotSite.sanxia'))
        out.append(feature({'type': 'LineString', 'coordinates': [[j[1], j[0]], [ys[1], ys[0]], [ye[1], ye[0]]]},
                           name='三峽機廠 停車線（近端到遠端）', kind='sanxia_yard', sidings=SANXIA['sidings'], source='RealLineDepotSite.sanxia'))
    for name, lat, lon in HSR_GAME_DEPOTS:
        if in_box(lon, lat, box):
            out.append(feature(pt(lat, lon), name=name, kind='hsr_demo_depot', source='HighSpeedDemo.realDepots'))
    for name, lat, lon, shift in TRA_GAME_DEPOTS:
        if in_box(lon, lat, box):
            out.append(feature(pt(lat, lon), name=name, kind='tra_demo_depot', shift_south_metres=shift, source='TRADemo.depots'))
    return collection('depots', f'{OSM}; 遊戲內數字照 Sources/GamePresentation', out)


# --- PMTiles and vector tiles ----------------------------------------------

def read_varint(b, i):
    n = shift = 0
    while True:
        c = b[i]
        i += 1
        n |= (c & 0x7F) << shift
        if c < 0x80:
            return n, i
        shift += 7


def tile_id(z, x, y):
    acc = ((1 << (2 * z)) - 1) // 3
    d, s = 0, (1 << z) >> 1
    while s > 0:
        rx = 1 if x & s else 0
        ry = 1 if y & s else 0
        d += s * s * ((3 * rx) ^ ry)
        if ry == 0:
            if rx == 1:
                x, y = s - 1 - x, s - 1 - y
            x, y = y, x
        s >>= 1
    return acc + d


class PMTiles:
    def __init__(self, path):
        self.f = open(path, 'rb')
        h = self.f.read(127)
        if h[:7] != b'PMTiles' or h[7] != 3:
            raise SystemExit(f'{path} is not a PMTiles v3 archive')
        (self.root_off, self.root_len, _, _, self.leaf_off, _, self.data_off, _) = struct.unpack('<8Q', h[8:72])
        self.internal_gzip = h[97] == 2
        self.tile_gzip = h[98] == 2

    def _read(self, off, length, gz):
        self.f.seek(off)
        b = self.f.read(length)
        return gzip.decompress(b) if gz else b

    @staticmethod
    def _entries(b):
        n, i = read_varint(b, 0)
        ids, last = [], 0
        for _ in range(n):
            d, i = read_varint(b, i)
            last += d
            ids.append(last)
        runs, lens, offs = [], [], []
        for _ in range(n):
            v, i = read_varint(b, i)
            runs.append(v)
        for _ in range(n):
            v, i = read_varint(b, i)
            lens.append(v)
        prev = 0
        for k in range(n):
            v, i = read_varint(b, i)
            offs.append(prev if v == 0 and k > 0 else v - 1)
            prev = offs[-1] + lens[k]
        return list(zip(ids, runs, lens, offs))

    def tile(self, z, x, y):
        want = tile_id(z, x, y)
        off, length = self.root_off, self.root_len
        for _ in range(4):
            entries = self._entries(self._read(off, length, self.internal_gzip))
            lo, hi, hit = 0, len(entries) - 1, None
            while lo <= hi:
                mid = (lo + hi) // 2
                if entries[mid][0] <= want:
                    hit, lo = entries[mid], mid + 1
                else:
                    hi = mid - 1
            if hit is None:
                return None
            _, run, length, o = hit
            if run == 0:
                off, length = self.leaf_off + o, length
                continue
            if want - hit[0] >= run:
                return None
            return self._read(self.data_off + o, length, self.tile_gzip)
        return None


def decode_layer(buf, name):
    """The line features of layer `name` of a vector tile: (properties,
    parts), a part a list of (x, y) tile points; the layer's extent."""
    i, result, extent = 0, [], 4096
    while i < len(buf):
        key, i = read_varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 2:
            ln, i = read_varint(buf, i)
            body = buf[i:i + ln]
            i += ln
            if field == 3:
                layer = parse_layer(body)
                if layer[0] == name:
                    return layer[1], layer[2]
        elif wire == 0:
            _, i = read_varint(buf, i)
        elif wire == 1:
            i += 8
        elif wire == 5:
            i += 4
    return result, extent


def parse_layer(b):
    i, name, keys, values, feats, extent = 0, '', [], [], [], 4096
    while i < len(b):
        key, i = read_varint(b, i)
        field, wire = key >> 3, key & 7
        if wire == 2:
            ln, i = read_varint(b, i)
            body = b[i:i + ln]
            i += ln
            if field == 1:
                name = body.decode()
            elif field == 2:
                feats.append(body)
            elif field == 3:
                keys.append(body.decode())
            elif field == 4:
                values.append(parse_value(body))
        elif wire == 0:
            v, i = read_varint(b, i)
            if field == 5:
                extent = v
        elif wire == 1:
            i += 8
        elif wire == 5:
            i += 4
    return name, [parse_feature(f, keys, values) for f in feats], extent


def parse_value(b):
    key, i = read_varint(b, 0)
    field, wire = key >> 3, key & 7
    if wire == 2:
        ln, i = read_varint(b, i)
        return b[i:i + ln].decode()
    if wire == 0:
        v, i = read_varint(b, i)
        if field == 6:
            v = (v >> 1) ^ -(v & 1)
        if field == 7:
            v = bool(v)
        return v
    if wire == 1:
        return struct.unpack('<d', b[i:i + 8])[0]
    return struct.unpack('<f', b[i:i + 4])[0]


def parse_feature(b, keys, values):
    i, tags, kind, geom = 0, [], 0, b''
    while i < len(b):
        key, i = read_varint(b, i)
        field, wire = key >> 3, key & 7
        if wire == 2:
            ln, i = read_varint(b, i)
            body = b[i:i + ln]
            i += ln
            if field == 2:
                j = 0
                while j < len(body):
                    v, j = read_varint(body, j)
                    tags.append(v)
            elif field == 4:
                geom = body
        elif wire == 0:
            v, i = read_varint(b, i)
            if field == 3:
                kind = v
        elif wire == 1:
            i += 8
        elif wire == 5:
            i += 4
    props = {keys[tags[k]]: values[tags[k + 1]] for k in range(0, len(tags) - 1, 2)}
    parts, part, x, y, j = [], [], 0, 0, 0
    while j < len(geom):
        cmd, j = read_varint(geom, j)
        op, count = cmd & 7, cmd >> 3
        for _ in range(count if op != 7 else 0):
            dx, j = read_varint(geom, j)
            dy, j = read_varint(geom, j)
            x += (dx >> 1) ^ -(dx & 1)
            y += (dy >> 1) ^ -(dy & 1)
            if op == 1:
                if part:
                    parts.append(part)
                part = []
            part.append((x, y))
    if part:
        parts.append(part)
    return props, kind, parts


# --- Web Mercator ----------------------------------------------------------

def merc_x(lon):
    return (lon + 180) / 360 * WORLD_POINTS


def merc_y(lat):
    s = math.sin(math.radians(lat))
    return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * WORLD_POINTS


def from_merc(x, y):
    return (math.asin(math.tanh((0.5 - y / WORLD_POINTS) * 2 * math.pi)) * 180 / math.pi, x / WORLD_POINTS * 360 - 180)


def tiles_for(box):
    n = 1 << ZOOM
    x0, x1 = int(merc_x(box[0]) / WORLD_POINTS * n), int(merc_x(box[2]) / WORLD_POINTS * n)
    y0, y1 = int(merc_y(box[3]) / WORLD_POINTS * n), int(merc_y(box[1]) / WORLD_POINTS * n)
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def road_features(box, pm):
    """Every line of the base map's `transportation` layer in box, in
    degrees, with its class and brunnel."""
    out = []
    n = 1 << ZOOM
    for tx, ty in tiles_for(box):
        data = pm.tile(ZOOM, tx, ty)
        if data is None:
            continue
        feats, extent = decode_layer(data, 'transportation')
        for props, kind, parts in feats:
            if kind != 2:
                continue
            for part in parts:
                coords = []
                for px, py in part:
                    lat, lon = from_merc((tx + px / extent) / n * WORLD_POINTS, (ty + py / extent) / n * WORLD_POINTS)
                    coords.append([round(lon, 7), round(lat, 7)])
                if len(coords) >= 2 and any(in_box(c[0], c[1], box) for c in coords):
                    out.append((props, coords))
    return out


# The classes the game keeps (Map3DBaseMap.roadKind) and which are freeways.
GAME_CLASSES = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service'}
HIGHWAYS = {'motorway', 'trunk'}


def roads(box, pm):
    out = []
    for props, coords in road_features(box, pm):
        cls = props.get('class')
        out.append(feature({'type': 'LineString', 'coordinates': coords}, **{
            'class': cls, 'brunnel': props.get('brunnel'), 'name': props.get('name'),
            'in_game': cls in GAME_CLASSES, 'highway': cls in HIGHWAYS,
            'game_road_cell': cls in GAME_CLASSES and (cls in HIGHWAYS or props.get('brunnel') != 'tunnel')}))
    return collection('roads', f'{OSM}; 遊戲的底圖（OpenMapTiles 欄位）', out)


def cells(box, pm, anchor, radius):
    """The 64 m cells RealRoadCells marks as having a road, for a world of
    WORLD_METRES a side centred on `anchor`, within `radius` metres of it."""
    lat0, lon0 = anchor
    ppm = WORLD_POINTS / (2 * math.pi * EARTH_RADIUS * math.cos(math.radians(lat0)))
    ax, ay = merc_x(lon0), merc_y(lat0)
    half = WORLD_METRES / 2
    n = 1 << ZOOM
    found = {'road': set(), 'highway': set()}
    for tx, ty in tiles_for(box):
        data = pm.tile(ZOOM, tx, ty)
        if data is None:
            continue
        feats, extent = decode_layer(data, 'transportation')
        for props, kind, parts in feats:
            cls = props.get('class')
            if kind != 2 or cls not in GAME_CLASSES:
                continue
            highway = cls in HIGHWAYS
            if not highway and props.get('brunnel') == 'tunnel':
                continue
            for part in parts:
                pts = [(((tx + px / extent) / n * WORLD_POINTS - ax) / ppm + half, ((ty + py / extent) / n * WORLD_POINTS - ay) / ppm + half) for px, py in part]
                for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
                    steps = max(1, math.ceil(math.hypot(x1 - x0, z1 - z0) / SAMPLE_METRES))
                    for s in range(steps + 1):
                        t = s / steps
                        x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
                        if x < 0 or z < 0 or x >= WORLD_METRES or z >= WORLD_METRES:
                            continue
                        if math.hypot(x - half, z - half) > radius:
                            continue
                        found['highway' if highway else 'road'].add((int(z // CELL_METRES), int(x // CELL_METRES)))
    out = []
    for key in ('road', 'highway'):
        for row, col in sorted(found[key]):
            ring = []
            for dc, dr in ((0, 0), (1, 0), (1, 1), (0, 1), (0, 0)):
                x, z = (col + dc) * CELL_METRES, (row + dr) * CELL_METRES
                lat, lon = from_merc((x - half) * ppm + ax, (z - half) * ppm + ay)
                ring.append([round(lon, 7), round(lat, 7)])
            out.append(feature({'type': 'Polygon', 'coordinates': [ring]}, kind=key, row=row, column=col))
    return collection('road_cells', f'{OSM}; 遊戲的道路格子（64 m），RealRoadCells 同一算法', out)


# --- command line ----------------------------------------------------------

def parse_box(text):
    if not text:
        return None
    w, s, e, n = (float(v) for v in text.split(','))
    return (w, s, e, n)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('layer', choices=['stations', 'lines', 'depots', 'roads', 'cells', 'all'])
    ap.add_argument('--out', default=os.path.join(ROOT, 'tools', 'geojson-export', 'out'), help='output folder (default tools/geojson-export/out, not committed)')
    ap.add_argument('--bbox', help='west,south,east,north in degrees; roads and cells need it (cells: derived from --anchor and --radius when left out)')
    ap.add_argument('--anchor', help='lat,lon of the middle of a game world (cells); the new-game map is 16,384 m a side')
    ap.add_argument('--radius', type=float, default=WORLD_METRES / 2, help='cells within this many metres of the anchor')
    ap.add_argument('--basemap', default=BASEMAP)
    ap.add_argument('--suffix', default='', help='added to the file names, e.g. _hsinchu')
    a = ap.parse_args()
    box = parse_box(a.bbox)
    layers = ['stations', 'lines', 'depots'] if a.layer == 'all' else [a.layer] if a.layer in ('stations', 'lines', 'depots') else []
    for layer in layers:
        data = {'stations': stations, 'lines': lines, 'depots': depots}[layer](box)
        write(os.path.join(a.out, f'{layer}{a.suffix}.geojson'), data)
    if a.layer in ('roads', 'cells'):
        if a.layer == 'cells':
            if not a.anchor:
                sys.exit('cells needs --anchor lat,lon')
            lat, lon = (float(v) for v in a.anchor.split(','))
            # Box from the radius, so a bbox is optional.
            dlat = a.radius / 110574
            dlon = a.radius / (111320 * math.cos(math.radians(lat)))
            box = box or (lon - dlon, lat - dlat, lon + dlon, lat + dlat)
            data = cells(box, PMTiles(a.basemap), (lat, lon), a.radius)
        else:
            if not box:
                sys.exit('roads needs --bbox west,south,east,north')
            data = roads(box, PMTiles(a.basemap))
        write(os.path.join(a.out, f'{data["name"]}{a.suffix}.geojson'), data)


if __name__ == '__main__':
    main()
