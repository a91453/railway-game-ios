#!/usr/bin/env python3
"""Land the 3D map builds no town on (decision 385).

Reads a whole OpenStreetMap extract of Taiwan (osmtoday.com's
`asia/taiwan.pbf`, ODbL 1.0) and writes
`RailwayGameApp/Resources/BaseMap/taiwan_no_build.json`, which
`GamePresentation`'s `RealNoBuildLand` reads:

    python3 -I tools/no-build-land/build_no_build.py taiwan.pbf \
        RailwayGameApp/Resources/BaseMap/taiwan_no_build.json

Kept: the outer rings of airports, military land, cemeteries, golf
courses, railway land and ports (`KINDS`), of at least `SMALLEST` m²,
simplified to about 3 m; and the buildings standing in the
airports (terminals, hangars), with their height and what they are
(`use_of`). Points are 1e-5 degrees
(about a metre), each ring's first point whole and the rest the change
from the one before.

Needs pyosmium (`pip install osmium`, BSD 2-Clause; decision 93),
only here, never in the app; the geometry is the standard library's.
"""

import json
import math
import sys

# Each kind: the tags that make an area one (key: values, None for any).
KINDS = [
    ('airport', {'aeroway': {'aerodrome'}}),
    ('military', {'landuse': {'military'}, 'military': None}),
    ('cemetery', {'landuse': {'cemetery'}, 'amenity': {'grave_yard'}}),
    ('golf', {'leisure': {'golf_course'}}),
    ('railway', {'landuse': {'railway'}}),
    ('port', {'landuse': {'port'}, 'industrial': {'port'}, 'man_made': {'pier'}}),
]
# The smallest area kept, m².
SMALLEST = 2_500
# Simplified to this many degrees (about 3 m).
TOLERANCE = 3e-5
# The heights of an airport's buildings with neither `height` nor
# `building:levels`, metres.
HEIGHTS = {'hangar': 14, 'terminal': 16, 'transportation': 16, 'control_tower': 30}
DEFAULT_HEIGHT = 7
SMALLEST_BUILDING = 150


def kind_of(tags):
    for number, (_, tag_set) in enumerate(KINDS):
        for key, values in tag_set.items():
            value = tags.get(key)
            if value is not None and value != 'no' and (values is None or value in values):
                return number
    return None


def metres2(ring):
    """A ring's area, m², on a local flat projection."""
    lat0 = sum(p[0] for p in ring) / len(ring)
    kx = 111_320 * math.cos(math.radians(lat0))
    ky = 110_574
    total = 0.0
    for (a, b), (c, d) in zip(ring, ring[1:] + ring[:1]):
        total += (b * kx) * (c * ky) - (d * kx) * (a * ky)
    return abs(total) / 2


def simplified(ring, tolerance):
    """A closed ring by Douglas–Peucker (degrees), split at its first
    point and the point farthest from it; the closing point dropped."""
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 4:
        return ring

    def off(point, a, b):
        (y, x), (ay, ax), (by, bx) = point, a, b
        dx, dy = bx - ax, by - ay
        length2 = dx * dx + dy * dy
        t = 0 if length2 == 0 else max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / length2))
        return math.hypot(x - ax - t * dx, y - ay - t * dy)

    def line(points):
        if len(points) < 3:
            return points
        far, at = -1, 0
        for k in range(1, len(points) - 1):
            distance = off(points[k], points[0], points[-1])
            if distance > far:
                far, at = distance, k
        if far <= tolerance:
            return [points[0], points[-1]]
        return line(points[:at + 1])[:-1] + line(points[at:])

    split = max(range(len(ring)), key=lambda k: math.hypot(ring[k][0] - ring[0][0], ring[k][1] - ring[0][1]))
    return line(ring[:split + 1])[:-1] + line(ring[split:] + ring[:1])[:-1]


def inside(point, ring):
    """Whether a point lies in a ring, by the even-odd rule."""
    y, x = point
    result = False
    for (ay, ax), (by, bx) in zip(ring, ring[1:] + ring[:1]):
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            result = not result
    return result


def encode(ring):
    """A ring as whole 1e-5 degrees, the first point whole, the rest as
    changes; the closing point dropped."""
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    out, last = [], None
    for lat, lon in ring:
        point = (round(lat * 1e5), round(lon * 1e5))
        if point == last:
            continue
        if last is None:
            out += list(point)
        else:
            out += [point[0] - last[0], point[1] - last[1]]
        last = point
    return out if len(out) >= 6 else None


def height_of(tags):
    try:
        return float(tags['height'].replace('m', '').strip())
    except (KeyError, ValueError):
        pass
    try:
        return 1 + 3.5 * float(tags['building:levels'])
    except (KeyError, ValueError):
        pass
    return HEIGHTS.get(tags.get('building') or '', HEIGHTS.get(tags.get('aeroway') or '', DEFAULT_HEIGHT))


def use_of(tags):
    """0 for most buildings, 1 for a hangar, 2 for a terminal."""
    if 'hangar' in (tags.get('building'), tags.get('aeroway')):
        return 1
    if {'terminal', 'transportation'} & {tags.get('building'), tags.get('aeroway')}:
        return 2
    return 0


def main(source, out):
    import osmium  # pyosmium
    keys = sorted({key for _, tag_set in KINDS for key in tag_set} | {'building'})
    areas, airports, buildings = [], [], []
    counts = [0] * len(KINDS)
    newest = None
    processor = osmium.FileProcessor(source).with_areas(osmium.filter.KeyFilter(*keys))
    for area in processor.with_filter(osmium.filter.EntityFilter(osmium.osm.AREA)):
        tags = {tag.k: tag.v for tag in area.tags}
        kind = kind_of(tags)
        for outer in area.outer_rings():
            ring = [(node.lat, node.lon) for node in outer]
            if len(ring) < 4:
                continue
            if kind is not None:
                size = metres2(ring)
                if size < SMALLEST:
                    continue
                encoded = encode(simplified(ring, TOLERANCE))
                if not encoded:
                    continue
                areas.append([kind] + encoded)
                counts[kind] += 1
                if KINDS[kind][0] == 'airport':
                    airports.append((min(p[0] for p in ring), max(p[0] for p in ring),
                                     min(p[1] for p in ring), max(p[1] for p in ring), ring[:-1] if ring[0] == ring[-1] else ring))
                stamp = area.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
                newest = max(newest or stamp, stamp)
            elif 'building' in tags and metres2(ring) >= SMALLEST_BUILDING:
                buildings.append((ring, tags))
    kept = []
    for ring, tags in buildings:
        middle = (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))
        if not any(south <= middle[0] <= north and west <= middle[1] <= east and inside(middle, outline)
                   for south, north, west, east, outline in airports):
            continue
        encoded = encode(simplified(ring, TOLERANCE / 2))
        if encoded:
            kept.append([max(3, min(80, round(height_of(tags)))), use_of(tags)] + encoded)
    areas.sort()
    kept.sort()
    document = {
        'source': 'OpenStreetMap contributors (ODbL 1.0), osmtoday.com asia/taiwan.pbf',
        'newest': newest,
        'kinds': [name for name, _ in KINDS],
        'counts': dict(zip([name for name, _ in KINDS], counts)),
        'areas': areas,
        'buildings': kept,
    }
    with open(out, 'w', encoding='utf-8') as file:
        json.dump(document, file, separators=(',', ':'), ensure_ascii=False)
        file.write('\n')
    print(document['counts'], 'airport buildings', len(kept), 'newest', newest)


if __name__ == '__main__':
    main(*sys.argv[1:3])
