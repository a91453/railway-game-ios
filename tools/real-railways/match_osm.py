#!/usr/bin/env python3
"""Redraw the app's real railways on OpenStreetMap's tracks (ARCHITECTURE
decision 151): every line of `RailwayGameApp/Resources/RealRailways/
track_lines.geojson` follows the tracks of the extract the base map, the
water and the zones are made from, so the railway lies where the base map's
bridges, tunnels and cuttings are; its stations
(`track_stations.geojson`) sit on the redrawn lines.

    python3 tools/real-railways/match_osm.py taiwan.pbf \\
        <railway-reference-private>/Railway/site_archive_clean/data/track_lines.geojson \\
        <railway-reference-private>/Railway/site_archive_clean/data/track_stations.geojson \\
        tools/real-railways/osm_exceptions.json \\
        RailwayGameApp/Resources/RealRailways/track_lines.geojson \\
        RailwayGameApp/Resources/RealRailways/track_stations.geojson

The inputs are the owner's `Railway/` site's original files (checked by
sha256 against the exceptions file's `base`); the lines' and stations'
fields (system, line, name, colours, drawing order) stay the site's, from
TDX; only their shapes and points change. Read with pyosmium (`pip install
osmium`, decision 93), well under a minute.

How a line is matched (the `Railway/` reference's `rail-3d/physical/
topology.js`: tracks join where they share a node, never by nearness):

- The tracks: OSM ways of `railway=rail|subway|light_rail|monorail|tram|
  narrow_gauge` (not sidings, yards, spurs or crossovers, nor a line OSM
  names collapsed or abandoned), each given its
  system by the reference's `railwaySystem` (operator, network, name,
  gauge); a metro or light rail way with no system may serve any metro.
- Anchors every ANCHOR_SPACING metres along the line (and at its ends) are
  put on the nearest track node within SNAP metres; between two anchors the
  line is the cheapest path on the system's tracks, each edge costing its
  length times 1 + (its distance from the old line / SPREAD)², so the path
  keeps to the old line's side of a double track and never wanders into
  another line.
- A stretch whose path strays more than STRAY metres from the old line, or
  is much longer or shorter than it, or has no track near it, keeps its old
  shape and is reported: OpenStreetMap is the rule, but not where it has no
  such track. The exceptions file names the stretches kept as they are on
  purpose (the Alishan line at Duolin, where OSM still has the collapsed old
  line and TDX the line in use).
- The result is simplified (Douglas–Peucker, SIMPLIFY metres) and written
  with six decimals (some 0.1 m).

A station moves onto the nearest point of its system's new lines when that
is within STATION_REACH metres (a station on several lines to one point),
else stays where it is and is reported.
"""
import hashlib
import heapq
import json
import math
import os
import sys

ANCHOR_SPACING = 2_000.0
SNAP = 80.0
STEP = 20.0
RETRY = 200.0
SPREAD = 15.0
STRAY = 100.0
SIMPLIFY = 1.0
STATION_REACH = 60.0
CORRIDOR = 250.0
RAILWAYS = {'rail', 'subway', 'light_rail', 'monorail', 'tram', 'narrow_gauge'}
NOT_LINES = {'siding', 'yard', 'spur', 'crossover'}
# A track OSM still has but trains no longer run on.
GONE = ('已崩塌', '已廢', '廢線')
METROS = {'mrt', 'tymc', 'ntdlrt', 'ntalrt', 'sanying', 'krtc', 'tmrt'}


def railway_system(tags):
    """The `Railway/` reference's `railwaySystem` (`rail-3d/physical/
    topology.js`): which of the site's systems a track is."""
    text = ' '.join(tags.get(k) for k in ('operator', 'network', 'name') if tags.get(k))
    railway = tags.get('railway')
    if '阿里山' in text and railway == 'narrow_gauge':
        return 'afr_sched'
    for system, words in (
        ('sanying', ('三鶯',)), ('ntalrt', ('安坑',)), ('ntdlrt', ('淡海',)),
        ('tymc', ('桃園捷運', '桃園機場捷運')), ('tmrt', ('臺中捷運', '台中捷運')),
        ('krtc', ('高雄捷運', '高雄環狀輕軌')), ('mrt', ('臺北大眾捷運', '台北捷運', '捷運環狀線', '文湖線')),
        ('thsr_sched', ('高速鐵路', '台灣高鐵', 'THSR')),
    ):
        if any(w in text for w in words):
            return system
    if railway == 'rail' and (tags.get('gauge') == '1067' or any(w in text for w in ('臺灣鐵路', '臺鐵', 'Taiwan Railway'))):
        return 'tra_sched'
    return None


def fits(system, railway):
    """Whether a track of no known system may serve `system`: platform
    tracks often leave out the operator and gauge (the reference's
    `makeTopology`), so any track of the system's kind may, and the cost of
    straying keeps the path on its own line."""
    if system in ('tra_sched', 'thsr_sched'):
        return railway == 'rail'
    if system == 'afr_sched':
        return railway == 'narrow_gauge'
    return railway != 'narrow_gauge'


def read_tracks(path):
    """The extract's tracks: {node: (lon, lat)}, [(system or None, railway,
    [node, …], way id, (west, south, east, north))], and the newest edit."""
    import osmium  # pyosmium.
    ways, newest = [], None
    processor = osmium.FileProcessor(path, osmium.osm.NODE | osmium.osm.WAY).with_locations()
    for way in processor.with_filter(osmium.filter.EntityFilter(osmium.osm.WAY)).with_filter(osmium.filter.KeyFilter('railway')):
        tags = way.tags
        railway = tags.get('railway')
        if railway not in RAILWAYS or tags.get('service') in NOT_LINES:
            continue
        if any(word in (tags.get('name') or '') for word in GONE):
            continue
        nodes = [(n.ref, n.lon, n.lat) for n in way.nodes if n.location.valid()]
        if len(nodes) < 2:
            continue
        ways.append((railway_system(dict(tags)), railway, nodes, way.id))
        stamp = way.timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
        newest = max(newest or stamp, stamp)
    coordinates = {}
    for _, _, nodes, _ in ways:
        for ref, lon, lat in nodes:
            coordinates[ref] = (lon, lat)
    out = []
    for s, r, nodes, w in ways:
        lons, lats = [n[1] for n in nodes], [n[2] for n in nodes]
        out.append((s, r, [n[0] for n in nodes], w, (min(lons), min(lats), max(lons), max(lats))))
    return coordinates, out, newest


class Local:
    """Metres east and north of a point, for distances over a line's span."""
    def __init__(self, lat):
        self.kx, self.ky = 111_320 * math.cos(math.radians(lat)), 110_574

    def __call__(self, lon, lat):
        return lon * self.kx, lat * self.ky


class Polyline:
    """A line in local metres, with a grid of its segments for distances."""
    CELL = 100.0

    def __init__(self, points):
        self.points = points
        self.cells = {}
        self.along = [0.0]
        for i, (a, b) in enumerate(zip(points, points[1:])):
            self.along.append(self.along[-1] + math.dist(a, b))
            for cell in self._cells(a, b):
                self.cells.setdefault(cell, []).append(i)

    def _cells(self, a, b):
        x0, x1 = sorted((a[0], b[0]))
        y0, y1 = sorted((a[1], b[1]))
        for cx in range(int(x0 // self.CELL), int(x1 // self.CELL) + 1):
            for cy in range(int(y0 // self.CELL), int(y1 // self.CELL) + 1):
                yield cx, cy

    def nearest(self, p, reach):
        """(distance, distance along the line) of the line's nearest point
        to p within reach, else (inf, None)."""
        best = (math.inf, None)
        r = int(reach // self.CELL) + 1
        cx, cy = int(p[0] // self.CELL), int(p[1] // self.CELL)
        seen = set()
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                for i in self.cells.get((cx + dx, cy + dy), ()):
                    if i in seen:
                        continue
                    seen.add(i)
                    a, b = self.points[i], self.points[i + 1]
                    d, t = point_segment(p, a, b)
                    if d < best[0]:
                        best = (d, self.along[i] + t * math.dist(a, b))
        return best if best[0] <= reach else (math.inf, None)

    def at(self, s):
        """The point at distance s along the line."""
        s = max(0.0, min(s, self.along[-1]))
        lo, hi = 0, len(self.along) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.along[mid] <= s:
                lo = mid
            else:
                hi = mid
        a, b = self.points[lo], self.points[hi]
        span = self.along[hi] - self.along[lo]
        t = 0 if span == 0 else (s - self.along[lo]) / span
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    def between(self, s0, s1):
        """The line's points from s0 to s1 along it, ends included."""
        inner = [p for p, s in zip(self.points, self.along) if s0 < s < s1]
        return [self.at(s0)] + inner + [self.at(s1)]


def point_segment(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy), t


def simplify(points, tolerance):
    """Douglas–Peucker, in local metres."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        best, index = tolerance, None
        for k in range(i + 1, j):
            d, _ = point_segment(points[k], points[i], points[j])
            if d > best:
                best, index = d, k
        if index is not None:
            keep[index] = True
            stack += [(i, index), (index, j)]
    return [p for p, k in zip(points, keep) if k]


def match(line, system, coordinates, ways, local, exceptions):
    """The line's new shape in local metres, and what was kept and why."""
    old = Polyline(line)
    # The system's tracks within CORRIDOR of the old line, as a graph.
    graph, position, distance = {}, {}, {}
    xs, ys = [p[0] for p in line], [p[1] for p in line]
    box = (min(xs) - CORRIDOR, min(ys) - CORRIDOR, max(xs) + CORRIDOR, max(ys) + CORRIDOR)
    for way_system, railway, nodes, _, bounds in ways:
        if way_system != system and not (way_system is None and fits(system, railway)):
            continue
        (x0, y0), (x1, y1) = local(bounds[0], bounds[1]), local(bounds[2], bounds[3])
        if x1 < box[0] or x0 > box[2] or y1 < box[1] or y0 > box[3]:
            continue
        for a, b in zip(nodes, nodes[1:]):
            for n in (a, b):
                if n not in position:
                    position[n] = local(*coordinates[n])
                    distance[n] = old.nearest(position[n], CORRIDOR)[0]
            if distance[a] == math.inf and distance[b] == math.inf:
                continue
            # A long straight edge (OSM leaves 100 m and more between the
            # nodes of a tunnel) is cut into pieces of STEP, so an anchor
            # always finds a point of it near.
            pa, pb = position[a], position[b]
            pieces = max(1, math.ceil(math.dist(pa, pb) / STEP))
            chain = [a]
            for k in range(1, pieces):
                extra = ('cut', a, b, k)
                if extra not in position:
                    t = k / pieces
                    position[extra] = (pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t)
                chain.append(extra)
            chain.append(b)
            for u, v in zip(chain, chain[1:]):
                length = math.dist(position[u], position[v])
                mid = old.nearest(((position[u][0] + position[v][0]) / 2, (position[u][1] + position[v][1]) / 2), CORRIDOR)[0]
                if mid == math.inf:
                    mid = CORRIDOR * 2
                cost = length * (1 + (mid / SPREAD) ** 2)
                graph.setdefault(u, []).append((v, cost))
                graph.setdefault(v, []).append((u, cost))
    total = old.along[-1]
    # Anchors: the ends, every ANCHOR_SPACING, and the ends of every
    # exception stretch.
    marks = {0.0, total}
    marks.update(i * ANCHOR_SPACING for i in range(1, int(total // ANCHOR_SPACING) + 1) if i * ANCHOR_SPACING < total - ANCHOR_SPACING / 4)
    kept = []
    for s0, s1, why in exceptions:
        marks.update((s0, s1))
        kept.append((s0, s1, why))
    marks = sorted(marks)
    # Snap each anchor to the nearest track node near it.
    grid = {}
    for n in graph:
        grid.setdefault((int(position[n][0] // SNAP), int(position[n][1] // SNAP)), []).append(n)

    def near(p):
        """The track nodes within SNAP of p, each with the cost of reaching
        it from p."""
        cx, cy = int(p[0] // SNAP), int(p[1] // SNAP)
        out = {}
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for n in grid.get((cx + dx, cy + dy), ()):
                    d = math.dist(p, position[n])
                    if d <= SNAP:
                        out[n] = d * (1 + (d / SPREAD) ** 2)
        return out
    out, report = [], []
    # Each stretch starts where the last ended, so a line keeps to one
    # track of a double track (crossovers are not lines). A stretch with no
    # track near an end is tried again in pieces of RETRY, so only the
    # piece with no track (a line drawn past OSM's last track, into a
    # depot) keeps its old shape.
    end = None
    stretches = list(zip(marks, marks[1:]))[::-1]
    while stretches:
        s0, s1 = stretches.pop()
        if s1 - s0 < 1e-6:
            continue
        short = s1 - s0 < 2 * SNAP
        reason = next((why for a, b, why in kept if a <= s0 and s1 <= b), None)
        path = None
        sources = {end: 0.0} if end is not None else near(old.at(s0))
        targets = near(old.at(s1))
        end = None
        if reason is None and sources and targets:
            path = shortest(graph, sources, targets)
            if path is not None:
                points = [position[n] for n in path]
                length = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
                stray = max(old.nearest(p, STRAY * 3)[0] for p in points)
                if stray > STRAY or not (short or 0.7 * (s1 - s0) <= length <= 1.3 * (s1 - s0) + 2 * SNAP):
                    report.append((s0, s1, f'the tracks stray {stray:.0f} m, {length:.0f} m for {s1 - s0:.0f} m'))
                    path = None
                else:
                    end = path[-1]
        elif reason is None:
            if s1 - s0 > RETRY * 1.5:
                pieces = math.ceil((s1 - s0) / RETRY)
                cuts = [s0 + (s1 - s0) * k / pieces for k in range(pieces + 1)]
                stretches += list(zip(cuts, cuts[1:]))[::-1]
                end = None if not sources or len(sources) > 1 else next(iter(sources))
                continue
            report.append((s0, s1, 'no track near it'))
        if path is not None:
            piece = [position[n] for n in path]
        else:
            if reason:
                report.append((s0, s1, f'kept: {reason}'))
            piece = old.between(s0, s1)
            # Join the kept piece to the matched pieces on either side.
            if out:
                piece[0] = out[-1]
        if out and math.dist(out[-1], piece[0]) < 0.01:
            piece = piece[1:]
        out += piece
    shape = simplify(out, SIMPLIFY)
    if len(shape) < 2 or sum(math.dist(a, b) for a, b in zip(shape, shape[1:])) < 1:
        return line, report + [(0.0, total, 'too short to match, kept')]
    return shape, report


def shortest(graph, sources, targets):
    """Dijkstra from any of `sources` to any of `targets` ({node: the cost
    of starting or ending there}); the nodes of the cheapest path, or None."""
    best, previous = dict(sources), {}
    queue = [(c, n) for n, c in sources.items()]
    heapq.heapify(queue)
    found, found_cost = None, math.inf
    while queue:
        cost, node = heapq.heappop(queue)
        if cost >= found_cost:
            break
        if cost > best.get(node, math.inf):
            continue
        if node in targets and cost + targets[node] < found_cost:
            found, found_cost = node, cost + targets[node]
        for other, step in graph.get(node, ()):
            c = cost + step
            if c < best.get(other, math.inf):
                best[other] = c
                previous[other] = node
                heapq.heappush(queue, (c, other))
    if found is None:
        return None
    path = [found]
    while path[-1] not in sources or path[-1] in previous:
        if path[-1] not in previous:
            break
        path.append(previous[path[-1]])
    return path[::-1]


def main(extract, lines_path, stations_path, exceptions_path, lines_out, stations_out):
    exceptions = json.load(open(exceptions_path, encoding='utf-8'))
    for path, key in ((lines_path, 'lines'), (stations_path, 'stations')):
        digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()
        if digest != exceptions['base'][key]['sha256']:
            sys.exit(f'{path}: sha256 {digest}, expected the site\'s {exceptions["base"][key]["path"]} at {exceptions["base"]["reference"]}')
    coordinates, ways, newest = read_tracks(extract)
    print(f'{len(ways)} tracks in the extract, OSM data to {newest}', flush=True)
    lines = json.load(open(lines_path, encoding='utf-8'))
    stations = json.load(open(stations_path, encoding='utf-8'))
    by_key = {}
    moved, worst = [], []
    line_ends = []
    for feature in lines['features']:
        p = feature['properties']
        coords = feature['geometry']['coordinates']
        line_ends.append((tuple(coords[0]), tuple(coords[-1])))
        lat0 = sum(c[1] for c in coords) / len(coords)
        local = Local(lat0)
        points = [local(lon, lat) for lon, lat in coords]
        old = Polyline(points)
        keep = []
        for e in exceptions['keep']:
            if e['lineKey'] != p['lineKey']:
                continue
            ends = [old.nearest(local(*e[k]), 200)[1] for k in ('from', 'to')]
            assert None not in ends, f'{e["id"]}: its ends are not on {p["lineKey"]}'
            keep.append((min(ends), max(ends), e['id']))
        shape, report = match(points, p['sys'], coordinates, ways, local, keep)
        new = Polyline(shape)
        drift = sorted(new.nearest(q, 1_000)[0] for q in points[::max(1, len(points) // 400)])
        worst.append((drift[-1], p['lineKey'], p['name']))
        for s0, s1, why in report:
            print(f'  {p["lineKey"]} {p["name"]}: {s0 / 1000:.1f}–{s1 / 1000:.1f} km {why}')
        feature['geometry']['coordinates'] = [[round(x / local.kx, 6), round(y / local.ky, 6)] for x, y in shape]
        by_key.setdefault(p['lineKey'], []).append((new, local))
        print(f'{p["lineKey"]} {p["name"]}: {len(coords)} → {len(shape)} points, the old line within '
              f'{drift[len(drift) // 2]:.0f} m (median), {drift[-1]:.0f} m (most) of the new', flush=True)
    # Lines that met end to end still do: each joint of the old lines is
    # where the first of them now ends.
    joints = {}
    for feature, old_ends in zip(lines['features'], line_ends):
        coords = feature['geometry']['coordinates']
        for index, key in ((0, old_ends[0]), (-1, old_ends[1])):
            if key in joints:
                coords[index] = list(joints[key])
            else:
                joints[key] = tuple(coords[index])
    # A station, one point for every line it is on (a station of several
    # lines has a record on each), moves to the nearest point of its
    # system's new lines within STATION_REACH, else stays.
    groups = {}
    for feature in stations['features']:
        p = feature['properties']
        groups.setdefault((p['sys'], p['name'], tuple(feature['geometry']['coordinates'])), []).append(feature)
    for (system, name, (lon, lat)), members in groups.items():
        best = (math.inf, None)
        for key, shapes in by_key.items():
            if not key.startswith(system + '|'):
                continue
            for new, local in shapes:
                d, s = new.nearest(local(lon, lat), STATION_REACH)
                if d < best[0]:
                    at = new.at(s)
                    best = (d, [round(at[0] / local.kx, 6), round(at[1] / local.ky, 6)])
        if best[1] is None:
            print(f'  station {system} {name}: not within {STATION_REACH:.0f} m of a line, stays')
            continue
        moved.append(best[0])
        for feature in members:
            feature['geometry']['coordinates'] = list(best[1])
    lines['osm'] = {
        'credit': '© OpenStreetMap contributors', 'license': 'ODbL-1.0',
        'extract': os.path.basename(extract), 'osmData': newest,
        'method': 'tools/real-railways/match_osm.py: each line on the extract\'s tracks; the exceptions file\'s stretches kept',
        'kept': [e['id'] for e in exceptions['keep']],
    }
    stations['osm'] = {'credit': '© OpenStreetMap contributors', 'license': 'ODbL-1.0', 'osmData': newest,
                       'method': 'each station on the nearest point of its line, match_osm.py'}
    for path, data in ((lines_out, lines), (stations_out, stations)):
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
            f.write('\n')
    moved.sort()
    worst.sort(reverse=True)
    print(f'stations: {len(moved)} points on their lines, moved {moved[len(moved) // 2]:.0f} m (median), {moved[-1]:.0f} m (most)')
    print('lines that moved most: ' + ', '.join(f'{k} {n} {d:.0f} m' for d, k, n in worst[:8]))


if __name__ == '__main__':
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    main(*sys.argv[1:])
