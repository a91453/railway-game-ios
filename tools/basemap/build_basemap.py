#!/usr/bin/env python3
"""Taiwan's base map for real-world games, as vector tiles the app bundles
(`Resources/BaseMap/taiwan.pmtiles`, ARCHITECTURE decision 151).

    python3 tools/basemap/build_basemap.py taiwan.pbf \\
        RailwayGameApp/Resources/BaseMap/taiwan.pmtiles

The extract is the one every other data tool reads (osmtoday.com's
`asia/taiwan.pbf`, read with pyosmium, BSD 2-Clause, `pip install osmium`;
decision 93), so the base map shows the same OpenStreetMap as the game's
water, zones and places. It takes some ten minutes on four cores.

The tiles follow a part of the OpenMapTiles schema (its layer names, classes
and fields; https://openmaptiles.org/schema/, CC-BY 4.0, credited with the
map), so the game's one style (`OpenStreetMapBase.style`) draws them and
OpenFreeMap's tiles outside Taiwan alike:

- `water` (class ocean, lake, river, dock): the sea is a polygon round
  Taiwan with the coastline's rings as holes (the rings of
  `build_water_grid.coastline`); fish ponds are farms (decision 96), not
  water.
- `waterway` (class river, canal, stream; name): no drains or ditches.
- `landcover` (class wood, grass, wetland, sand): no farmland, which the
  game's zones draw.
- `park` (class national_park, nature_reserve, park).
- `transportation` (class motorway … service; ramp, brunnel) and
  `transportation_name` (name, ref, class): no railways (the game draws
  the real ones), paths, tracks or parking aisles.
- `place` (class city … hamlet, island; name) and `boundary` (admin_level
  4 and 7, maritime).

Not in them: buildings (the game draws its own city, decision 126), points
of interest and land use (the game's zones), so neither are military or
other sensitive sites (the `Ci/` reference's `osmSensitiveFacilityLabelFilter`
hides their labels; the style still filters OpenFreeMap's).

Tiles are cut as geojson-vt (ISC licence, Copyright (c) 2015, Mapbox;
https://github.com/mapbox/geojson-vt) does: each feature's points ranked
once for simplification (its `simplify.js`), then each tile clipped into
its four children with a buffer (its `clip.js`), ported to Python here.
The tiles are Mapbox Vector Tiles 2.1 (extent 4096), gzipped, in a PMTiles
v3 archive (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md),
both encoded here with the standard library.

It also says which 256-character glyph ranges the names need that MapLibre
does not draw on the device itself (its `allowsFixedWidthGlyphGeneration`,
CJK and kana); `fetch_glyphs.py` bundles every range anyway.
"""
import gzip
import hashlib
import json
import math
import multiprocessing
import os
import struct
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'real-world-population'))
from build_water_grid import coastline  # noqa: E402

EXTENT = 4096
BUFFER = 64
MAX_ZOOM = 14
# Tiles from this zoom down are cut in worker processes, one tile each.
SPLIT_ZOOM = 7
# The sea polygon reaches this far past Taiwan's land (degrees), snapped
# out to whole tiles of SPLIT_ZOOM, so a map near the coast always has sea;
# below SPLIT_ZOOM it fills whole tiles of zoom 5.
SEA_MARGIN = 2.0
# Simplification tolerance in tile units (of EXTENT), as geojson-vt's.
TOLERANCE = 4.0
TOLERANCE_MAX_ZOOM = 2.0

NAME_KEYS = ('name', 'name:en', 'name:zh', 'name:zh-Hant')

ROADS = {
    'motorway': ('motorway', 5), 'trunk': ('trunk', 6), 'primary': ('primary', 8),
    'secondary': ('secondary', 9), 'tertiary': ('tertiary', 11),
    'unclassified': ('minor', 13), 'residential': ('minor', 13), 'living_street': ('minor', 13),
    'road': ('minor', 13), 'busway': ('minor', 13), 'service': ('service', 14),
}
# A link road from zoom 9 at the earliest.
LINK_ZOOM = 9
NO_SERVICE = {'parking_aisle', 'driveway', 'drive-through'}
ROAD_NAME_ZOOM = {'motorway': 10, 'trunk': 11, 'primary': 12, 'secondary': 13, 'tertiary': 13, 'minor': 14, 'service': 14}
WATERWAYS = {'river': 8, 'canal': 12, 'stream': 13}
PLACES = {
    'city': 4, 'county': 7, 'town': 8, 'suburb': 11, 'quarter': 12, 'village': 12,
    'neighbourhood': 13, 'hamlet': 14, 'island': 8, 'islet': 12,
}
BOUNDARIES = {4: 5, 7: 10}


# --- projection ------------------------------------------------------------

def project(lon, lat):
    """Web Mercator, the world a unit square, y down."""
    s = math.sin(math.radians(max(-85.05, min(85.05, lat))))
    return (lon / 360 + 0.5, 0.5 - 0.25 * math.log((1 + s) / (1 - s)) / math.pi)


def unproject(x, y):
    return (360 * (x - 0.5), math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y)))))


# --- features --------------------------------------------------------------
# A feature: [layer, kind, minzoom, maxzoom, props, geometry, bbox]. kind is
# 1 point, 2 line, 3 polygon. A line's geometry is a list of flat lists
# [x, y, importance, …]; a polygon's is a list of rings, each a flat list
# and its area (world units², outer rings first, holes after their outer);
# a point's is [x, y]. bbox is (minX, minY, maxX, maxY).

def rank(coords, first, last, sq_tolerance):
    """geojson-vt's `simplify`: give each point between `first` and `last`
    (indices of x, step 3) the squared distance at which simplification
    would drop it."""
    stack = [(first, last)]
    while stack:
        first, last = stack.pop()
        max_sq, index = sq_tolerance, 0
        ax, ay, bx, by = coords[first], coords[first + 1], coords[last], coords[last + 1]
        mid = (last - first) // 3
        mid = first + (mid - mid % 2) * 3 if mid > 1 else first
        min_pos_to_mid = last - first
        for i in range(first + 3, last, 3):
            d = segment_sq(coords[i], coords[i + 1], ax, ay, bx, by)
            if d > max_sq:
                index, max_sq = i, d
            elif d == max_sq:
                pos = abs(i - mid)
                if pos < min_pos_to_mid:
                    index, min_pos_to_mid = i, pos
        if max_sq > sq_tolerance:
            coords[index + 2] = max_sq
            if index - first > 3:
                stack.append((first, index))
            if last - index > 3:
                stack.append((index, last))


def segment_sq(px, py, x, y, bx, by):
    dx, dy = bx - x, by - y
    if dx != 0 or dy != 0:
        t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy)
        if t > 1:
            x, y = bx, by
        elif t > 0:
            x += dx * t
            y += dy * t
    dx, dy = px - x, py - y
    return dx * dx + dy * dy


BASE_SQ = (TOLERANCE_MAX_ZOOM / ((1 << MAX_ZOOM) * EXTENT)) ** 2


def flat(points):
    """A flat [x, y, importance, …] list of (lon, lat) points, ranked."""
    out = []
    for lon, lat in points:
        x, y = project(lon, lat)
        out += (x, y, 0.0)
    if len(out) >= 6:
        out[2] = out[-1] = 1.0
        rank(out, 0, len(out) - 3, BASE_SQ)
    return out


def ring_area(coords):
    area = 0.0
    for i in range(0, len(coords) - 3, 3):
        area += coords[i] * coords[i + 4] - coords[i + 3] * coords[i + 1]
    return area / 2


def bbox_of(parts):
    xs = [c for part in parts for c in part[0::3]]
    ys = [c for part in parts for c in part[1::3]]
    return (min(xs), min(ys), max(xs), max(ys))


def line_feature(layer, minzoom, props, points, maxzoom=MAX_ZOOM):
    coords = flat(points)
    if len(coords) < 6:
        return None
    return [layer, 2, minzoom, maxzoom, props, [coords], bbox_of([coords])]


def polygon_feature(layer, minzoom, props, rings, maxzoom=MAX_ZOOM):
    """`rings`: lists of (lon, lat), the outer one first."""
    out = []
    for points in rings:
        coords = flat(points)
        if len(coords) >= 12:
            out.append([coords, abs(ring_area(coords))])
    if not out:
        return None
    return [layer, 3, minzoom, maxzoom, props, out, bbox_of([ring for ring, _ in out])]


def point_feature(layer, minzoom, props, lon, lat):
    x, y = project(lon, lat)
    return [layer, 1, minzoom, MAX_ZOOM, props, [x, y], (x, y, x, y)]


def names(tags):
    out = {}
    for key in NAME_KEYS:
        value = tags.get(key)
        if value:
            out[key] = value
    if 'name:zh-Hant' not in out and tags.get('name:zh-TW'):
        out['name:zh-Hant'] = tags.get('name:zh-TW')
    if 'name:en' in out:
        out['name_en'] = out['name:en']
    return out


def area_zoom(area_km2, steps):
    """The first zoom of `steps` [(km², zoom), …] (largest first) the area
    reaches, else the last zoom."""
    for limit, zoom in steps:
        if area_km2 >= limit:
            return zoom
    return steps[-1][1]


def km2(rings):
    """The area of an outer ring of (lon, lat) less its holes, in km²."""
    def one(points):
        if len(points) < 3:
            return 0.0
        lat0 = math.radians(sum(p[1] for p in points) / len(points))
        kx, ky = 111.320 * math.cos(lat0), 110.574
        a = 0.0
        for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]):
            a += (x1 * kx) * (y2 * ky) - (x2 * kx) * (y1 * ky)
        return abs(a) / 2
    return max(0.0, one(rings[0]) - sum(one(r) for r in rings[1:]))


# --- reading ---------------------------------------------------------------

def water_class(tags):
    if tags.get('landuse') == 'aquaculture' or tags.get('water') in ('fishpond', '魚塭'):
        return None
    if tags.get('waterway') == 'dock':
        return 'dock'
    if tags.get('waterway') == 'riverbank' or tags.get('water') in ('river', 'canal', 'stream', 'oxbow'):
        return 'river'
    if tags.get('natural') == 'water' or tags.get('landuse') == 'reservoir':
        return 'lake'
    return None


def landcover_class(tags):
    natural, landuse = tags.get('natural'), tags.get('landuse')
    if natural == 'wood' or landuse == 'forest':
        return 'wood'
    if natural in ('grassland', 'scrub', 'heath') or landuse in ('grass', 'meadow'):
        return 'grass'
    if natural == 'wetland':
        return 'wetland'
    if natural in ('sand', 'beach', 'dune'):
        return 'sand'
    return None


def park_class(tags):
    if tags.get('boundary') == 'national_park':
        return 'national_park'
    if tags.get('leisure') == 'nature_reserve':
        return 'nature_reserve'
    if tags.get('leisure') == 'park':
        return 'park'
    return None


def read(path):
    import osmium  # pyosmium.
    features, newest = [], [None]
    boundary_ways = {}

    def stamp(obj):
        s = obj.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
        newest[0] = max(newest[0] or s, s)

    # Boundaries: each member way's lowest admin_level, and whether it is at
    # sea.
    for relation in osmium.FileProcessor(path, osmium.osm.RELATION):
        tags = relation.tags
        if tags.get('boundary') != 'administrative':
            continue
        try:
            level = int(tags.get('admin_level', ''))
        except ValueError:
            continue
        if level not in BOUNDARIES:
            continue
        for member in relation.members:
            if member.type == 'w':
                boundary_ways[member.ref] = min(level, boundary_ways.get(member.ref, 99))

    area_keys = osmium.filter.KeyFilter('natural', 'landuse', 'leisure', 'waterway', 'boundary', 'place', 'water')
    processor = osmium.FileProcessor(path).with_locations().with_areas(area_keys).with_filter(osmium.filter.EmptyTagFilter())
    for obj in processor:
        tags = obj.tags
        if obj.is_node():
            place = tags.get('place')
            if place in PLACES and tags.get('name'):
                features.append(point_feature('place', PLACES[place], {'class': place, **names(tags)}, obj.location.lon, obj.location.lat))
                stamp(obj)
            continue
        if obj.is_way():
            highway, waterway = tags.get('highway'), tags.get('waterway')
            points = [(n.lon, n.lat) for n in obj.nodes if n.location.valid()]
            if len(points) < 2:
                continue
            if highway:
                road = highway[:-5] if highway.endswith('_link') else highway
                if road in ROADS and not (road == 'service' and tags.get('service') in NO_SERVICE) \
                        and tags.get('area') != 'yes':
                    cls, zoom = ROADS[road]
                    props = {'class': cls}
                    if highway.endswith('_link'):
                        props['ramp'] = 1
                        zoom = max(zoom, LINK_ZOOM)
                    if tags.get('bridge') not in (None, 'no'):
                        props['brunnel'] = 'bridge'
                    elif tags.get('tunnel') not in (None, 'no') or tags.get('covered') == 'yes':
                        props['brunnel'] = 'tunnel'
                    f = line_feature('transportation', zoom, props, points)
                    if f:
                        f.append(('road', obj.nodes[0].ref, obj.nodes[-1].ref))
                        features.append(f)
                    label = names(tags)
                    if tags.get('ref'):
                        label['ref'] = tags.get('ref')
                    if label.get('name') or label.get('ref'):
                        f = line_feature('transportation_name', ROAD_NAME_ZOOM[cls], {'class': cls, **label}, points)
                        if f:
                            f.append(('road', obj.nodes[0].ref, obj.nodes[-1].ref))
                            features.append(f)
                    stamp(obj)
            if waterway in WATERWAYS:
                props = {'class': waterway, **names(tags)}
                if tags.get('tunnel') not in (None, 'no'):
                    props['brunnel'] = 'tunnel'
                f = line_feature('waterway', WATERWAYS[waterway], props, points)
                if f:
                    f.append(('water', obj.nodes[0].ref, obj.nodes[-1].ref))
                    features.append(f)
                stamp(obj)
            level = boundary_ways.get(obj.id)
            if level:
                maritime = 1 if tags.get('maritime') == 'yes' or tags.get('natural') == 'coastline' else 0
                f = line_feature('boundary', BOUNDARIES[level], {'admin_level': level, 'maritime': maritime}, points)
                if f:
                    f.append(('boundary', obj.nodes[0].ref, obj.nodes[-1].ref))
                    features.append(f)
                stamp(obj)
            continue
        if obj.is_area():
            water, cover, park = water_class(tags), landcover_class(tags), park_class(tags)
            island = tags.get('place') in ('island', 'islet') and tags.get('name')
            if not (water or cover or park or island):
                continue
            for outer in obj.outer_rings():
                rings = [[(n.lon, n.lat) for n in outer]]
                rings += [[(n.lon, n.lat) for n in inner] for inner in obj.inner_rings(outer)]
                area = km2(rings)
                if water:
                    zoom = area_zoom(area, [(10, 6), (1, 8), (0.1, 10), (0.01, 12), (0, 13)])
                    f = polygon_feature('water', zoom, {'class': water}, rings)
                elif cover:
                    zoom = area_zoom(area, [(10, 7), (1, 9), (0.1, 11), (0, 12)])
                    f = polygon_feature('landcover', zoom, {'class': cover, 'subclass': tags.get('natural') or tags.get('landuse')}, rings)
                elif park:
                    zoom = 6 if park == 'national_park' else area_zoom(area, [(10, 7), (1, 10), (0.05, 12), (0, 13)])
                    f = polygon_feature('park', zoom, {'class': park, **names(tags)}, rings)
                else:
                    f = None
                if f:
                    features.append(f)
                if island:
                    lon, lat = label_point(rings[0])
                    cls = tags.get('place')
                    zoom = area_zoom(area, [(50, 7), (5, 9), (0.5, 11), (0, PLACES[cls])])
                    features.append(point_feature('place', zoom, {'class': cls, **names(tags)}, lon, lat))
            stamp(obj)
    return features, newest[0]


def label_point(points):
    """The area-weighted middle of a ring, or its first point when that
    falls outside it."""
    a = cx = cy = 0.0
    for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]):
        cross = x1 * y2 - x2 * y1
        a += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    if a == 0:
        return points[0]
    x, y = cx / (3 * a), cy / (3 * a)
    inside = False
    for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return (x, y) if inside else points[0]


def merge_lines(features):
    """Join lines of one layer and the same fields end to end where exactly
    two meet, so a road is a few long lines rather than many short ones."""
    groups, out = {}, []
    for f in features:
        if f[1] == 2 and len(f) > 7:
            key = (f[0], f[2], json.dumps(f[4], sort_keys=True, ensure_ascii=False))
            groups.setdefault(key, []).append(f)
        else:
            out.append(f[:7])
    for group in groups.values():
        ends = {}
        for i, f in enumerate(group):
            ends.setdefault(f[7][1], []).append(i)
            ends.setdefault(f[7][2], []).append(i)
        used = [False] * len(group)
        for i, f in enumerate(group):
            if used[i]:
                continue
            used[i] = True
            coords = list(f[5][0])
            first, last = f[7][1], f[7][2]
            for forward in (True, False):
                while True:
                    node = last if forward else first
                    nxt = [j for j in ends.get(node, []) if not used[j]]
                    if len(ends.get(node, [])) != 2 or len(nxt) != 1:
                        break
                    j = nxt[0]
                    used[j] = True
                    other = list(group[j][5][0])
                    a, b = group[j][7][1], group[j][7][2]
                    if forward:
                        if a != node:
                            other, a, b = reverse(other), b, a
                        coords = coords + other[3:]
                        last = b
                    else:
                        if b != node:
                            other, a, b = reverse(other), b, a
                        coords = other[:-3] + coords
                        first = a
            # The joints keep their rank (each was an end, ranked 1).
            out.append([f[0], 2, f[2], f[3], f[4], [coords], bbox_of([coords])])
    return out


def reverse(coords):
    out = []
    for i in range(len(coords) - 3, -1, -3):
        out += coords[i:i + 3]
    return out


def sea(land_rings):
    """The sea round Taiwan: one polygon for zooms SPLIT_ZOOM and up (a box
    SEA_MARGIN past the land, snapped to whole SPLIT_ZOOM tiles) and one
    for lower zooms (whole zoom-5 tiles), each with the land as holes."""
    lons = [lon for ring in land_rings for _, lon in ring]
    lats = [lat for ring in land_rings for lat, _ in ring]
    west, east = min(lons) - SEA_MARGIN, max(lons) + SEA_MARGIN
    south, north = min(lats) - SEA_MARGIN, max(lats) + SEA_MARGIN
    # OpenStreetMap draws the coastline with the land on its left: an
    # island's ring runs anticlockwise (a hole in the sea), and a clockwise
    # one is sea inside the land (a lagoon), a sea of its own.
    holes, lagoons = [], []
    for ring in land_rings:
        points = [(lon, lat) for lat, lon in ring]
        signed = sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(points, points[1:]))
        (holes if signed > 0 else lagoons).append(points)

    def box(zoom):
        n = 1 << zoom
        x0, y0 = project(west, north)
        x1, y1 = project(east, south)
        x0, y0 = math.floor(x0 * n) / n, math.floor(y0 * n) / n
        x1, y1 = math.ceil(x1 * n) / n, math.ceil(y1 * n) / n
        (w, nl), (e, s) = unproject(x0, y0), unproject(x1, y1)
        return [(w, nl), (e, nl), (e, s), (w, s), (w, nl)]
    out = []
    for zoom, minzoom, maxzoom in ((SPLIT_ZOOM, SPLIT_ZOOM, MAX_ZOOM), (5, 0, SPLIT_ZOOM - 1)):
        f = polygon_feature('water', minzoom, {'class': 'ocean'}, [box(zoom)] + holes, maxzoom=maxzoom)
        out.append(f)
    for points in lagoons:
        f = polygon_feature('water', area_zoom(km2([points]), [(10, 6), (1, 8), (0.1, 10), (0, 12)]), {'class': 'ocean'}, [points])
        if f:
            out.append(f)
    print(f'sea: {len(holes)} islands, {len(lagoons)} lagoons', flush=True)
    return out, (west, south, east, north)


# --- clipping (geojson-vt's clip.js) ----------------------------------------

def clip(features, k1, k2, axis):
    """The features' parts between k1 and k2 along `axis` (0 x, 1 y)."""
    out = []
    lo, hi = axis, axis + 2
    for f in features:
        bbox = f[6]
        if bbox[lo] >= k1 and bbox[hi] < k2:
            out.append(f)
            continue
        if bbox[hi] < k1 or bbox[lo] >= k2:
            continue
        kind = f[1]
        if kind == 1:
            continue
        if kind == 2:
            parts = []
            for line in f[5]:
                clip_line(line, parts, k1, k2, axis, False)
            parts = [p for p in parts if len(p) >= 6]
            if parts:
                out.append([f[0], 2, f[2], f[3], f[4], parts, clipped_bbox(bbox, parts, axis)])
        else:
            rings, outer_kept = [], False
            for i, (ring, area) in enumerate(f[5]):
                new = []
                clip_line(ring, new, k1, k2, axis, True)
                is_outer = area_is_outer(f, i)
                if is_outer:
                    outer_kept = bool(new) and len(new[0]) >= 12
                if new and len(new[0]) >= 12 and outer_kept:
                    rings.append([new[0], area])
            if rings:
                out.append([f[0], 3, f[2], f[3], f[4], rings, clipped_bbox(bbox, [r for r, _ in rings], axis)])
    return out


def area_is_outer(feature, index):
    # A polygon feature has one outer ring, its first (the sea's holes are
    # its other rings).
    return index == 0


def clipped_bbox(bbox, parts, axis):
    values = [c for part in parts for c in part[axis::3]]
    if axis == 0:
        return (min(values), bbox[1], max(values), bbox[3])
    return (bbox[0], min(values), bbox[2], max(values))


def clip_line(coords, parts, k1, k2, axis, closed):
    """geojson-vt's clipLine: append to `parts` the pieces of `coords`
    within [k1, k2] (one ring, closed, when `closed`)."""
    piece = []
    for i in range(0, len(coords) - 3, 3):
        ax, ay, az = coords[i], coords[i + 1], coords[i + 2]
        bx, by = coords[i + 3], coords[i + 4]
        a = ax if axis == 0 else ay
        b = bx if axis == 0 else by
        exited = False
        if a < k1:
            if b > k1:
                intersect(piece, ax, ay, bx, by, k1, axis)
        elif a > k2:
            if b < k2:
                intersect(piece, ax, ay, bx, by, k2, axis)
        else:
            piece += (ax, ay, az)
        if b < k1 and a >= k1:
            intersect(piece, ax, ay, bx, by, k1, axis)
            exited = True
        if b > k2 and a <= k2:
            intersect(piece, ax, ay, bx, by, k2, axis)
            exited = True
        if not closed and exited:
            parts.append(piece)
            piece = []
    last = len(coords) - 3
    ax, ay, az = coords[last], coords[last + 1], coords[last + 2]
    a = ax if axis == 0 else ay
    if k1 <= a <= k2:
        piece += (ax, ay, az)
    if closed and len(piece) >= 6 and (piece[0] != piece[-3] or piece[1] != piece[-2]):
        piece += (piece[0], piece[1], piece[2])
    if piece:
        parts.append(piece)


def intersect(piece, ax, ay, bx, by, k, axis):
    if axis == 0:
        t = (k - ax) / (bx - ax)
        piece += (k, ay + (by - ay) * t, 1.0)
    else:
        t = (k - ay) / (by - ay)
        piece += (ax + (bx - ax) * t, k, 1.0)


# --- tiles -----------------------------------------------------------------

LAYER_ORDER = ('water', 'landcover', 'park', 'waterway', 'boundary', 'transportation', 'transportation_name', 'place')


def tile_bytes(z, x, y, features):
    """The tile's Mapbox Vector Tile, gzipped, or None when it is empty."""
    n = 1 << z
    sq_tol = (TOLERANCE_MAX_ZOOM if z == MAX_ZOOM else TOLERANCE) / (n * EXTENT)
    sq_tol *= sq_tol
    layers = {}
    for f in features:
        if not (f[2] <= z <= f[3]):
            continue
        # Road names keep their road's points: gzip then stores them almost
        # for nothing.
        geometry = encode_geometry(f, z, x, y, n, sq_tol)
        if geometry is None:
            continue
        layers.setdefault(f[0], []).append((f[1], f[4], geometry))
    if not layers:
        return None
    body = b''.join(field_bytes(3, encode_layer(name, layers[name])) for name in LAYER_ORDER if name in layers)
    return gzip.compress(body, 9, mtime=0)


def encode_geometry(f, z, tx, ty, n, sq_tol):
    kind = f[1]
    if kind == 1:
        px, py = f[5]
        ix, iy = round((px * n - tx) * EXTENT), round((py * n - ty) * EXTENT)
        if not (0 <= ix < EXTENT and 0 <= iy < EXTENT):
            return None
        return [command(1, 1), zigzag(ix), zigzag(iy)]
    out, cx, cy = [], 0, 0
    if kind == 2:
        for line in f[5]:
            points = tile_points(line, n, tx, ty, sq_tol)
            if len(points) < 2:
                continue
            if length(points) < math.sqrt(sq_tol) * n * EXTENT:
                continue
            cx, cy = path(out, points, cx, cy, False)
        return out or None
    outer_ok = False
    for i, (ring, area) in enumerate(f[5]):
        if area < sq_tol and i == 0:
            return None
        if area < sq_tol:
            continue
        points = tile_points(ring, n, tx, ty, sq_tol)
        if len(points) < 4:
            if i == 0:
                return None
            continue
        points = points[:-1] if points[0] == points[-1] else points
        if len(points) < 3:
            if i == 0:
                return None
            continue
        signed = shoelace(points)
        if signed == 0:
            if i == 0:
                return None
            continue
        # Outer rings clockwise on screen (positive here, y down), holes
        # the other way (MVT 2.1 §4.3.4.4).
        if (i == 0) != (signed > 0):
            points.reverse()
        if i == 0:
            outer_ok = True
        cx, cy = path(out, points, cx, cy, True)
    return out if outer_ok else None


def tile_points(coords, n, tx, ty, sq_tol):
    out = []
    last = len(coords) - 3
    for i in range(0, len(coords), 3):
        if coords[i + 2] > sq_tol or i == 0 or i == last:
            p = (round((coords[i] * n - tx) * EXTENT), round((coords[i + 1] * n - ty) * EXTENT))
            if not out or out[-1] != p:
                out.append(p)
    return out


def length(points):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))


def shoelace(points):
    s = 0
    for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]):
        s += x1 * y2 - x2 * y1
    return s


def path(out, points, cx, cy, closed):
    x, y = points[0]
    out += (command(1, 1), zigzag(x - cx), zigzag(y - cy))
    cx, cy = x, y
    out.append(command(2, len(points) - 1))
    for x, y in points[1:]:
        out += (zigzag(x - cx), zigzag(y - cy))
        cx, cy = x, y
    if closed:
        out.append(command(7, 1))
    return cx, cy


def command(cid, count):
    return (cid & 7) | (count << 3)


def zigzag(v):
    return (v << 1) ^ (v >> 31)


def varint(v):
    out = bytearray()
    while v > 0x7F:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)


def field_bytes(number, payload):
    return varint(number << 3 | 2) + varint(len(payload)) + payload


def packed(number, values):
    return field_bytes(number, b''.join(varint(v) for v in values))


def encode_layer(name, features):
    keys, values, key_index, value_index = [], [], {}, {}
    body = bytearray()
    for kind, props, geometry in features:
        tags = []
        for key in sorted(props):
            value = props[key]
            if key not in key_index:
                key_index[key] = len(keys)
                keys.append(key)
            vkey = (type(value).__name__, value)
            if vkey not in value_index:
                value_index[vkey] = len(values)
                values.append(value)
            tags += (key_index[key], value_index[vkey])
        feature = packed(2, tags) + varint(3 << 3) + varint(kind) + packed(4, geometry)
        body += field_bytes(2, feature)
    out = varint(15 << 3) + varint(2) + field_bytes(1, name.encode())
    out += bytes(body)
    for key in keys:
        out += field_bytes(3, key.encode())
    for value in values:
        if isinstance(value, str):
            v = field_bytes(1, value.encode())
        else:
            v = varint(4 << 3) + varint(int(value))  # int_value; fields here are small and non-negative.
        out += field_bytes(4, v)
    out += varint(5 << 3) + varint(EXTENT)
    return out


def split(z, x, y, features):
    """The four children of tile z/x/y, each with its features clipped to
    it and its buffer."""
    n2 = 1 << (z + 1)
    k = BUFFER / EXTENT / n2
    # A feature drawn no deeper goes no further.
    features = [f for f in features if f[3] > z]
    left, right = (2 * x) / n2, (2 * x + 2) / n2
    mid_x = (2 * x + 1) / n2
    top, bottom = (2 * y) / n2, (2 * y + 2) / n2
    mid_y = (2 * y + 1) / n2
    out = []
    for cx, (x0, x1) in ((2 * x, (left - k, mid_x + k)), (2 * x + 1, (mid_x - k, right + k))):
        column = clip(features, x0, x1, 0)
        if not column:
            continue
        for cy, (y0, y1) in ((2 * y, (top - k, mid_y + k)), (2 * y + 1, (mid_y - k, bottom + k))):
            cell = clip(column, y0, y1, 1)
            if cell:
                out.append((z + 1, cx, cy, cell))
    return out


def full_sea(features, z, x, y):
    """Whether the tile is all sea and nothing else."""
    if len(features) != 1:
        return False
    f = features[0]
    if f[0] != 'water' or f[1] != 3 or len(f[5]) != 1 or f[2] > z:
        return False
    n = 1 << z
    b = f[6]
    return b[0] <= x / n and b[1] <= y / n and b[2] >= (x + 1) / n and b[3] >= (y + 1) / n


def cut(z, x, y, features, out, stop_zoom):
    """Every tile from z/x/y down to stop_zoom (or MAX_ZOOM), depth first,
    into `out` as (z, x, y, bytes); at stop_zoom the tiles' features are
    kept instead, as (z, x, y, features)."""
    stack = [(z, x, y, features)]
    while stack:
        z, x, y, features = stack.pop()
        if stop_zoom is not None and z == stop_zoom:
            out.append((z, x, y, features))
            continue
        if full_sea(features, z, x, y) and features[0][3] == MAX_ZOOM:
            data = tile_bytes(z, x, y, features)
            for zz in range(z, MAX_ZOOM + 1):
                s = 1 << (zz - z)
                for xx in range(x * s, x * s + s):
                    for yy in range(y * s, y * s + s):
                        out.append((zz, xx, yy, data))
            continue
        data = tile_bytes(z, x, y, features)
        if data:
            out.append((z, x, y, data))
        if z < MAX_ZOOM:
            stack.extend(split(z, x, y, features))


JOBS = []


def work(index):
    z, x, y, features = JOBS[index]
    out = []
    cut(z, x, y, features, out, None)
    return out


# --- PMTiles ---------------------------------------------------------------

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


def directory(entries):
    out = varint(len(entries))
    last = 0
    for tid, _, _, _ in entries:
        out += varint(tid - last)
        last = tid
    for _, _, _, run in entries:
        out += varint(run)
    for _, _, length, _ in entries:
        out += varint(length)
    for i, (_, offset, _, _) in enumerate(entries):
        if i > 0 and offset == entries[i - 1][1] + entries[i - 1][2]:
            out += varint(0)
        else:
            out += varint(offset + 1)
    return gzip.compress(out, 9, mtime=0)


def write_pmtiles(path, tiles, metadata, bounds, center, tile_type=1, tile_compression=2, zooms=(0, MAX_ZOOM)):
    """Write `tiles` [(tile id, bytes), …] as a PMTiles v3 archive: its tiles
    `tile_type` (1 vector, 2 PNG) compressed as `tile_compression` (1 none,
    2 gzip), of zooms `zooms` (first, last); `bounds` (west, south, east,
    north) and `center` (lon, lat, zoom) in degrees."""
    tiles.sort(key=lambda t: t[0])
    data, offsets, entries = bytearray(), {}, []
    for tid, blob in tiles:
        digest = hashlib.sha256(blob).digest()
        if digest not in offsets:
            offsets[digest] = (len(data), len(blob))
            data += blob
        offset, size = offsets[digest]
        if entries and entries[-1][0] + entries[-1][3] == tid and entries[-1][1] == offset:
            e = entries[-1]
            entries[-1] = (e[0], e[1], e[2], e[3] + 1)
        else:
            entries.append((tid, offset, size, 1))
    root, leaves = directory(entries), b''
    leaf_size = 4096
    while len(root) > 16384 - 127:
        leaves, root_entries = bytearray(), []
        for i in range(0, len(entries), leaf_size):
            chunk = directory(entries[i:i + leaf_size])
            root_entries.append((entries[i][0], len(leaves), len(chunk), 0))
            leaves += chunk
        root = directory(root_entries)
        leaf_size *= 2
    meta = gzip.compress(json.dumps(metadata, ensure_ascii=False, separators=(',', ':')).encode(), 9, mtime=0)
    root_offset = 127
    meta_offset = root_offset + len(root)
    leaf_offset = meta_offset + len(meta)
    data_offset = leaf_offset + len(leaves)
    header = b'PMTiles' + struct.pack(
        '<BQQQQQQQQQQQBBBBBBiiiiBii', 3,
        root_offset, len(root), meta_offset, len(meta), leaf_offset, len(leaves), data_offset, len(data),
        len(tiles), len(entries), len(offsets),
        1, 2, tile_compression, tile_type, zooms[0], zooms[-1],
        round(bounds[0] * 1e7), round(bounds[1] * 1e7), round(bounds[2] * 1e7), round(bounds[3] * 1e7),
        center[2], round(center[0] * 1e7), round(center[1] * 1e7))
    assert len(header) == 127
    with open(path, 'wb') as out:
        out.write(header + root + meta + bytes(leaves) + bytes(data))
    return len(entries), len(offsets)


# --- glyphs ----------------------------------------------------------------

def drawn_on_device(c):
    """MapLibre Native's `allowsFixedWidthGlyphGeneration` (6.31.0): the
    characters it draws with the device's own font, never asking the
    style's glyphs for them."""
    ranges = (
        (0x02EA, 0x02EB), (0x1100, 0x11FF), (0x2E80, 0x2EFF), (0x2F00, 0x2FDF), (0x3000, 0x303F),
        (0x3040, 0x309F), (0x30A0, 0x30FF), (0x3105, 0x312F), (0x3131, 0x318E), (0x31A0, 0x31BF),
        (0x31C0, 0x31EF), (0x31F0, 0x31FF), (0x3200, 0x32FF), (0x3300, 0x33FF), (0x3400, 0x4DBF),
        (0x4E00, 0x9FFF), (0xA000, 0xA48C), (0xA490, 0xA4C6), (0xA960, 0xA97C), (0xAC00, 0xD7AF),
        (0xD7B0, 0xD7C6), (0xD7CB, 0xD7FB), (0xF900, 0xFA6D), (0xFA70, 0xFAD9), (0xFE10, 0xFE1F),
        (0xFE30, 0xFE4F), (0xFF00, 0xFFEF),
    )
    return any(a <= c <= b for a, b in ranges)


def glyph_ranges(features):
    needed = {}
    for f in features:
        for key in NAME_KEYS + ('name_en', 'ref'):
            for ch in f[4].get(key, '') if isinstance(f[4].get(key), str) else '':
                c = ord(ch)
                if c > 0xFFFF or drawn_on_device(c):
                    continue
                start = c // 256 * 256
                needed[start] = needed.get(start, 0) + 1
    return needed


# --- main ------------------------------------------------------------------

def main(extract, out):
    started = time.time()
    features, newest = read(extract)
    print(f'read {len(features)} features in {time.time() - started:.0f} s', flush=True)
    rings, cut_rings, coast_stamp = coastline(extract)
    seas, bounds = sea(rings)
    features = merge_lines(features) + seas
    print(f'{len(features)} features after joining lines; {len(rings)} coastline rings ({cut_rings} cut open, left out); '
          f'{time.time() - started:.0f} s', flush=True)
    glyphs = glyph_ranges(features)

    tiles = []
    pending = []
    cut(0, 0, 0, features, pending, SPLIT_ZOOM)
    for z, x, y, item in pending:
        if isinstance(item, list):
            JOBS.append((z, x, y, item))
        else:
            tiles.append((tile_id(z, x, y), item))
    print(f'{len(tiles)} tiles cut whole, {len(JOBS)} tiles of zoom {SPLIT_ZOOM} to cut; '
          f'{time.time() - started:.0f} s', flush=True)
    features = None
    with multiprocessing.get_context('fork').Pool(os.cpu_count()) as pool:
        order = sorted(range(len(JOBS)), key=lambda i: -sum(len(p) for f in JOBS[i][3] for p in (f[5] if f[1] != 1 else [[0]])))
        for done, result in enumerate(pool.imap_unordered(work, order), 1):
            tiles += [(tile_id(z, x, y), data) for z, x, y, data in result if data]
            print(f'  {done}/{len(JOBS)} tiles of zoom {SPLIT_ZOOM}; {len(tiles)} tiles; {time.time() - started:.0f} s', flush=True)

    stamps = sorted(s for s in (newest, coast_stamp) if s)
    lon_lat = (bounds[0], bounds[1], bounds[2], bounds[3])
    metadata = {
        'name': 'Taiwan base map',
        'format': 'pbf',
        'attribution': '© OpenMapTiles © OpenStreetMap contributors',
        'description': f'OpenStreetMap contributors (ODbL 1.0), from the extract {os.path.basename(extract)}, data to {stamps[-1]}; '
                       'layers after the OpenMapTiles schema (CC-BY 4.0)',
        'osmData': stamps[-1],
        'vector_layers': [
            {'id': 'water', 'fields': {'class': 'String'}, 'minzoom': 0, 'maxzoom': MAX_ZOOM},
            {'id': 'landcover', 'fields': {'class': 'String', 'subclass': 'String'}, 'minzoom': 7, 'maxzoom': MAX_ZOOM},
            {'id': 'park', 'fields': {'class': 'String', 'name': 'String'}, 'minzoom': 6, 'maxzoom': MAX_ZOOM},
            {'id': 'waterway', 'fields': {'class': 'String', 'name': 'String', 'brunnel': 'String'}, 'minzoom': 8, 'maxzoom': MAX_ZOOM},
            {'id': 'boundary', 'fields': {'admin_level': 'Number', 'maritime': 'Number'}, 'minzoom': 5, 'maxzoom': MAX_ZOOM},
            {'id': 'transportation', 'fields': {'class': 'String', 'ramp': 'Number', 'brunnel': 'String'}, 'minzoom': 5, 'maxzoom': MAX_ZOOM},
            {'id': 'transportation_name', 'fields': {'class': 'String', 'name': 'String', 'ref': 'String'}, 'minzoom': 10, 'maxzoom': MAX_ZOOM},
            {'id': 'place', 'fields': {'class': 'String', 'name': 'String'}, 'minzoom': 4, 'maxzoom': MAX_ZOOM},
        ],
    }
    entries, contents = write_pmtiles(out, [(tid, data) for tid, data in tiles], metadata, lon_lat, (121.0, 23.7, 7))
    print(f'{out}: {len(tiles)} tiles, {entries} directory entries, {contents} distinct tiles, '
          f'{os.path.getsize(out)} bytes; OSM data to {stamps[-1]}; {time.time() - started:.0f} s')
    print('glyph ranges the names need from the style (not drawn on the device): '
          + ', '.join(f'{s}-{s + 255} ({n})' for s, n in sorted(glyphs.items())))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
