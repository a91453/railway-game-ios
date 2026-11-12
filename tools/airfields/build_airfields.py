#!/usr/bin/env python3
"""The airfields the 3D map draws (decision 699).

Reads a whole OpenStreetMap extract of Taiwan (osmtoday.com's
`asia/taiwan.pbf`, ODbL 1.0) and writes
`RailwayGameApp/Resources/BaseMap/taiwan_airfields.json`, which
`GamePresentation`'s `RealAirfields` reads:

    python3 -I tools/airfields/build_airfields.py taiwan.pbf \
        RailwayGameApp/Resources/BaseMap/taiwan_airfields.json

Kept, for every aerodrome with an IATA code (the ones with scheduled
flights): its runways (centre line, width, the numbers painted at its
ends), its taxiways (centre lines, simplified to about 1 m), its aprons
(outlines, simplified to about 2 m), its parking positions (where the nose
stops and which way it points; an airport with fewer than six mapped gets
a row of them on the apron by its terminal, `row_of_stands`), its jet
bridges and its control towers.
Points are whole 1e-6 degrees (about 0.1 m), a line's first point whole and
the rest the change from the one before.

Needs pyosmium (`pip install osmium`, BSD 2-Clause; decision 93), only
here, never in the app; the geometry is the standard library's.
"""

import json
import math
import sys

# Widths when OpenStreetMap gives none, metres.
RUNWAY_WIDTH = 45
TAXIWAY_WIDTH = 23
TAXILANE_WIDTH = 15
# A control tower's height when it has none, metres.
TOWER_HEIGHT = 40
# Simplified to this many degrees.
LINE_TOLERANCE = 1e-5
RING_TOLERANCE = 2e-5
# The smallest apron kept, m².
SMALLEST_APRON = 1_500
# An airport with fewer mapped parking positions than this gets a row of
# them on the apron by its terminal, this far apart, metres, at most
# `MOST_MADE`.
FEWEST_STANDS = 6
STAND_PITCH = 46
MOST_MADE = 8
# How far from an aerodrome's outline its things may lie, degrees (a
# runway's end or a taxiway may cross the fence OpenStreetMap drew).
SLACK = 0.002


def metres(a, b):
    """The distance between two (lat, lon) points, m."""
    kx = 111_320 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[1] - b[1]) * kx, (a[0] - b[0]) * 110_574)


def area(ring):
    lat0 = sum(p[0] for p in ring) / len(ring)
    kx = 111_320 * math.cos(math.radians(lat0))
    total = 0.0
    for (a, b), (c, d) in zip(ring, ring[1:] + ring[:1]):
        total += (b * kx) * (c * 110_574) - (d * kx) * (a * 110_574)
    return abs(total) / 2


def inside(point, ring):
    y, x = point
    result = False
    for (ay, ax), (by, bx) in zip(ring, ring[1:] + ring[:1]):
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            result = not result
    return result


def simplified(points, tolerance):
    """An open line by Douglas–Peucker (degrees)."""
    if len(points) < 3:
        return points

    def off(point, a, b):
        (y, x), (ay, ax), (by, bx) = point, a, b
        dx, dy = bx - ax, by - ay
        length2 = dx * dx + dy * dy
        t = 0 if length2 == 0 else max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / length2))
        return math.hypot(x - ax - t * dx, y - ay - t * dy)

    far, at = -1, 0
    for k in range(1, len(points) - 1):
        distance = off(points[k], points[0], points[-1])
        if distance > far:
            far, at = distance, k
    if far <= tolerance:
        return [points[0], points[-1]]
    return simplified(points[:at + 1], tolerance)[:-1] + simplified(points[at:], tolerance)


def simplified_ring(ring, tolerance):
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 4:
        return ring
    split = max(range(len(ring)), key=lambda k: math.hypot(ring[k][0] - ring[0][0], ring[k][1] - ring[0][1]))
    return simplified(ring[:split + 1], tolerance)[:-1] + simplified(ring[split:] + ring[:1], tolerance)[:-1]


def encode(points):
    out, last = [], None
    for lat, lon in points:
        point = (round(lat * 1e6), round(lon * 1e6))
        if point == last:
            continue
        out += list(point) if last is None else [point[0] - last[0], point[1] - last[1]]
        last = point
    return out


def number(text, default):
    try:
        return float(str(text).replace('m', '').strip())
    except (TypeError, ValueError):
        return default


def bearing(a, b):
    """Degrees clockwise from north, from a to b."""
    kx = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.degrees(math.atan2((b[1] - a[1]) * kx, b[0] - a[0])) % 360


def is_tower(tags):
    return tags.get('aeroway') in ('control_tower', 'tower') or tags.get('building') == 'control_tower' \
        or tags.get('man_made') == 'control_tower' or tags.get('tower:type') == 'airport_control' or tags.get('service') == 'aircraft_control'


def joined(pieces):
    """Runway pieces (ref, width, points) of one name that meet end to end
    made one line each."""
    pieces = [list(piece) for piece in pieces]
    merged = True
    while merged:
        merged = False
        for i, a in enumerate(pieces):
            for j, b in enumerate(pieces):
                if i == j or a[0] != b[0]:
                    continue
                for first, second in ((a[2], b[2]), (a[2], b[2][::-1]), (a[2][::-1], b[2]), (a[2][::-1], b[2][::-1])):
                    if metres(first[-1], second[0]) < 8:
                        a[2] = first + second[1:]
                        a[1] = max(a[1], b[1])
                        del pieces[j]
                        merged = True
                        break
                if merged:
                    break
            if merged:
                break
    return pieces


def row_of_stands(apron, runways, most):
    """Stands along the side of `apron` (a ring) away from the nearest of
    `runways` (lines), nose in: one every `STAND_PITCH` metres, at most
    `most`. For an airport whose parking positions OpenStreetMap has not."""
    lat0 = sum(p[0] for p in apron) / len(apron)
    kx, ky = 111_320 * math.cos(math.radians(lat0)), 110_574

    def flat(p):
        return ((p[1] - apron[0][1]) * kx, (p[0] - apron[0][0]) * ky)

    def back(q):
        return (apron[0][0] + q[1] / ky, apron[0][1] + q[0] / kx)

    ring = [flat(p) for p in apron]
    middle = (sum(q[0] for q in ring) / len(ring), sum(q[1] for q in ring) / len(ring))
    # Away from the runway: from its nearest point to the apron's middle.
    best = None
    for line in runways:
        (ax, ay), (bx, by) = flat(line[0]), flat(line[-1])
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((middle[0] - ax) * dx + (middle[1] - ay) * dy) / (dx * dx + dy * dy)))
        off = (middle[0] - ax - t * dx, middle[1] - ay - t * dy)
        if best is None or math.hypot(*off) < math.hypot(*best[0]):
            best = (off, (dx, dy))
    if best is None:
        return []
    length = math.hypot(*best[0]) or 1
    away = (best[0][0] / length, best[0][1] / length)
    along = (-away[1], away[0])
    far = max(q[0] * away[0] + q[1] * away[1] for q in ring)
    low = min(q[0] * along[0] + q[1] * along[1] for q in ring)
    high = max(q[0] * along[0] + q[1] * along[1] for q in ring)
    stands, at = [], low + STAND_PITCH / 2
    heading = math.degrees(math.atan2(away[0], away[1])) % 360
    while at < high and len(stands) < most:
        # The nose 14 m inside the far side, where the apron is there.
        for depth in range(14, 120, 6):
            q = (along[0] * at + away[0] * (far - depth), along[1] * at + away[1] * (far - depth))
            tail = (q[0] - away[0] * 40, q[1] - away[1] * 40)
            if inside((q[1], q[0]), [(r[1], r[0]) for r in ring]) and inside((tail[1], tail[0]), [(r[1], r[0]) for r in ring]):
                stands.append((back(q), heading))
                break
        at += STAND_PITCH
    return stands


def main(source, out):
    import osmium  # pyosmium
    fields, lines, stands, towers, aprons, terminals = [], [], [], [], [], []
    newest = None
    # Only what is kept goes through Python: every building of Taiwan
    # would take half an hour.
    wanted = osmium.filter.TagFilter(*[('aeroway', value) for value in (
        'aerodrome', 'apron', 'terminal', 'control_tower', 'runway', 'taxiway', 'taxilane', 'parking_position', 'jet_bridge', 'stopway')],
        ('aeroway', 'tower'), ('building', 'terminal'), ('building', 'transportation'), ('building', 'control_tower'),
        ('man_made', 'control_tower'), ('tower:type', 'airport_control'), ('service', 'aircraft_control'))
    processor = osmium.FileProcessor(source).with_locations().with_areas(wanted)
    for thing in processor.with_filter(wanted):
        tags = {tag.k: tag.v for tag in thing.tags}
        aeroway = tags.get('aeroway')
        if thing.is_area():
            rings = [[(node.lat, node.lon) for node in outer] for outer in thing.outer_rings()]
            rings = [ring for ring in rings if len(ring) >= 4]
            if not rings:
                continue
            if aeroway == 'aerodrome' and tags.get('iata'):
                fields.append({'tags': tags, 'rings': [ring[:-1] if ring[0] == ring[-1] else ring for ring in rings]})
                stamp = thing.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
                newest = max(newest or stamp, stamp)
            elif aeroway == 'apron':
                aprons += rings
            elif aeroway == 'terminal' or tags.get('building') in ('terminal', 'transportation'):
                terminals += rings
            if is_tower(tags):
                ring = rings[0]
                towers.append(((sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring)), tags))
        elif thing.is_way():
            if aeroway in ('runway', 'taxiway', 'taxilane', 'parking_position', 'jet_bridge', 'stopway') and not thing.is_closed():
                points = [(node.lat, node.lon) for node in thing.nodes if node.location.valid()]
                if len(points) >= 2:
                    lines.append((aeroway, tags, points))
        elif thing.is_node():
            if aeroway == 'parking_position':
                stands.append(((thing.lat, thing.lon), None, tags))
            elif is_tower(tags):
                towers.append(((thing.lat, thing.lon), tags))

    def field_of(point):
        for index, field in enumerate(fields):
            for ring in field['rings']:
                if min(p[0] for p in ring) - SLACK <= point[0] <= max(p[0] for p in ring) + SLACK \
                        and min(p[1] for p in ring) - SLACK <= point[1] <= max(p[1] for p in ring) + SLACK:
                    if inside(point, ring) or min(metres(point, p) for p in ring) < 150:
                        return index
        return None

    made = [{'runways': [], 'taxiways': [], 'aprons': [], 'stands': [], 'bridges': [], 'towers': [], 'terminals': [], 'rings': []}
            for _ in fields]
    for ring in terminals:
        middle = (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))
        index = field_of(middle)
        if index is not None:
            made[index]['terminals'].append(ring)
    for kind, tags, points in lines:
        middle = points[len(points) // 2] if len(points) > 2 else ((points[0][0] + points[1][0]) / 2, (points[0][1] + points[1][1]) / 2)
        index = field_of(middle)
        if index is None:
            continue
        if kind == 'runway':
            if tags.get('surface') in ('grass', 'dirt', 'unpaved') or tags.get('runway') == 'displaced_threshold':
                continue
            made[index]['runways'].append((tags.get('ref', ''), round(number(tags.get('width'), RUNWAY_WIDTH)), points))
        elif kind in ('taxiway', 'taxilane', 'stopway'):
            width = number(tags.get('width'), TAXILANE_WIDTH if kind == 'taxilane' else TAXIWAY_WIDTH)
            made[index]['taxiways'].append({'width': round(min(width, 60)), 'line': encode(simplified(points, LINE_TOLERANCE))})
        elif kind == 'jet_bridge':
            made[index]['bridges'].append(encode([points[0], points[-1]]))
        elif kind == 'parking_position':
            # The nose stops at the line's end and points along it.
            stands.append((points[-1], bearing(points[-2], points[-1]), tags))
    for ring in aprons:
        middle = (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))
        index = field_of(middle)
        if index is not None and area(ring) >= SMALLEST_APRON:
            made[index]['aprons'].append(encode(simplified_ring(ring, RING_TOLERANCE)))
            made[index]['rings'].append(ring[:-1] if ring[0] == ring[-1] else ring)
    for point, heading, tags in stands:
        index = field_of(point)
        if index is None:
            continue
        if heading is None:
            # A stand marked as a point faces the nearest terminal within
            # 160 m; with none near, it is left for the app to turn.
            near = min(((metres(point, p), p) for ring in made[index]['terminals'] for p in ring), default=None)
            heading = bearing(point, near[1]) if near and near[0] < 160 else -1
        made[index]['stands'].append([round(point[0] * 1e6), round(point[1] * 1e6), round(heading)])
    for parts in made:
        if len(parts['stands']) >= FEWEST_STANDS or not parts['rings'] or not parts['runways']:
            continue
        # The apron nearest a terminal, or the largest.
        def rank(ring):
            near = min((metres(p, q) for terminal in parts['terminals'] for p in ring[::3] for q in terminal[::3]), default=None)
            return (0, near) if near is not None else (1, -area(ring))
        apron = min(parts['rings'], key=rank)
        for point, heading in row_of_stands(apron, [points for _, _, points in parts['runways']], MOST_MADE - len(parts['stands'])):
            if all(metres(point, (other[0] / 1e6, other[1] / 1e6)) > STAND_PITCH * 0.8 for other in parts['stands']):
                parts['stands'].append([round(point[0] * 1e6), round(point[1] * 1e6), round(heading)])
    for point, tags in towers:
        index = field_of(point)
        if index is not None:
            height = number(tags.get('height'), TOWER_HEIGHT)
            entry = [round(point[0] * 1e6), round(point[1] * 1e6), round(max(15, min(120, height)))]
            if all(metres(point, (other[0] / 1e6, other[1] / 1e6)) > 60 for other in made[index]['towers']):
                made[index]['towers'].append(entry)

    airports = []
    for field, parts in zip(fields, made):
        if not parts['runways']:
            continue
        del parts['terminals'], parts['rings']
        # A runway is drawn from its lower number to its higher, its first
        # name at its first point.
        runways = []
        for ref, width, points in joined(parts['runways']):
            points = [points[0], points[-1]]
            names = ref.split('/')
            if len(names) == 2 and round(bearing(points[0], points[1]) / 10) % 36 != int(''.join(c for c in names[0] if c.isdigit()) or 0) % 36:
                # The line runs from its second name to its first: turn the names.
                heading = round(bearing(points[0], points[1]) / 10) % 36
                second = int(''.join(c for c in names[1] if c.isdigit()) or 0) % 36
                if min(abs(heading - second), 36 - abs(heading - second)) <= 2:
                    ref = names[1] + '/' + names[0]
            runways.append({'ref': ref, 'width': width, 'line': encode(points)})
        parts['runways'] = runways
        for key in ('runways', 'taxiways'):
            parts[key].sort(key=lambda item: (item['line'], item['width']))
        for key in ('aprons', 'stands', 'bridges', 'towers'):
            parts[key].sort()
        ring = max(field['rings'], key=len)
        airports.append({'iata': field['tags']['iata'], 'icao': field['tags'].get('icao', ''),
                         'at': [round(sum(p[0] for p in ring) / len(ring) * 1e6), round(sum(p[1] for p in ring) / len(ring) * 1e6)], **parts})
    airports.sort(key=lambda item: item['iata'])
    document = {
        'source': 'OpenStreetMap contributors (ODbL 1.0), osmtoday.com asia/taiwan.pbf',
        'newest': newest,
        'airports': airports,
    }
    with open(out, 'w', encoding='utf-8') as file:
        json.dump(document, file, separators=(',', ':'), ensure_ascii=False)
        file.write('\n')
    for item in airports:
        print(item['iata'], item['icao'], 'runways', [(r['ref'], r['width']) for r in item['runways']], 'taxiways', len(item['taxiways']),
              'aprons', len(item['aprons']), 'stands', len(item['stands']), 'bridges', len(item['bridges']), 'towers', item['towers'])


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
