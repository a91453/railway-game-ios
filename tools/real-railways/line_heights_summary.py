#!/usr/bin/env python3
"""HEIGHT-STUDY: reads the HEIGHT_* lines LineHeightReportTests prints and the
OSM ways line_heights_osm.py pickled, and prints, per line, how the game's
track compares with the real line's (structures, heights, OSM tags): the
shares, the stretches that differ, and each station.

    python3 -I line_heights_summary.py report.log osm_heights.pkl

See docs/research/LINE_HEIGHTS_2026-11-05.md."""
import math, pickle, re, sys
from collections import defaultdict

log, pkl = sys.argv[1], sys.argv[2]
ways, osm_stations, platforms = pickle.load(open(pkl, 'rb'))

GAME = {'tunnel': 'U', 'viaduct': 'R', 'bridge': 'R', 'surface': 'G', 'embankment': 'G', 'cutting': 'G'}
REAL = {'t': 'U', 'b': 'R', 's': 'G'}
NAME = {'U': '地下', 'R': '高架／橋', 'G': '地面'}
# Which OSM railway kinds each system's running track is.
OSM_KINDS = {'tra_sched': {'rail', 'narrow_gauge'}, 'mrt': {'subway', 'rail', 'monorail'}, 'tymc': {'subway', 'rail'},
             'ntdlrt': {'light_rail', 'rail'}, 'ntalrt': {'light_rail', 'rail'}, 'sanying': {'subway', 'rail', 'light_rail', 'monorail'}}


def metres(a, b):
    lat = math.radians((a[1] + b[1]) / 2)
    return math.hypot((a[0] - b[0]) * 111320 * math.cos(lat), (a[1] - b[1]) * 110540)


def to_xy(p, origin):
    lat = math.radians(origin[1])
    return ((p[0] - origin[0]) * 111320 * math.cos(lat), (p[1] - origin[1]) * 110540)


def osm_class(tags):
    if tags.get('tunnel') in ('yes', 'building_passage', 'culvert') or tags.get('location') == 'underground':
        return 'U'
    if tags.get('bridge') in ('yes', 'viaduct', 'aqueduct', 'boardwalk', 'cantilever', 'movable', 'covered'):
        return 'R'
    return 'G'


lines, samples, stations = {}, defaultdict(list), defaultdict(list)
for raw in open(log, encoding='utf-8'):
    raw = raw.strip()
    if raw.startswith('HEIGHT_LINE '):
        parts = raw.split()
        lines[parts[1]] = dict(p.split('=', 1) for p in parts[2:])
    elif raw.startswith('HEIGHT_SAMPLE '):
        parts = raw.split()
        f = dict(p.split('=', 1) for p in parts[2:])
        lat, lon = map(float, f['ll'].split(','))
        g = f['game'].split(':')
        r = f['real'].split(':') if f['real'] != 'none' else None
        samples[parts[1]].append(dict(d=int(f['d']), ll=(lon, lat), game=GAME[g[0]], gkind=g[0], gover=float(g[1]),
                                      real=REAL[r[0]] if r else None, rheight=float(r[1]) if r else None,
                                      structure=f['structure'], ground=float(f['ground'])))
    elif raw.startswith('HEIGHT_STATION '):
        m = re.match(r'HEIGHT_STATION (\S+) (.+?) at=(\d+) ll=(\S+) platforms=(\S*) real=(\S+) structure=(\S+)', raw)
        if m:
            lat, lon = map(float, m.group(4).split(','))
            stations[m.group(1)].append(dict(name=m.group(2), at=int(m.group(3)), ll=(lon, lat), platforms=m.group(5),
                                             real=m.group(6), structure=m.group(7)))


def osm_near(network, ll, reach=30):
    """The nearest OSM running way of the line's system within reach: (class, layer, way id, distance)."""
    system = lines[network]['system']
    kinds = OSM_KINDS.get(system, {'rail'})
    best = None
    for wid, tags, pts in candidates[network]:
        if tags.get('railway') not in kinds:
            continue
        for a, b in zip(pts, pts[1:]):
            ax, ay = to_xy(a, ll); bx, by = to_xy(b, ll)
            dx, dy = bx - ax, by - ay
            l2 = dx * dx + dy * dy
            t = 0 if l2 == 0 else max(0, min(1, -(ax * dx + ay * dy) / l2))
            d = math.hypot(ax + t * dx, ay + t * dy)
            if d < reach and (best is None or d < best[3]):
                best = (osm_class(tags), tags.get('layer', ''), wid, d)
    return best


candidates = {}
for network, rows in samples.items():
    lons = [s['ll'][0] for s in rows]; lats = [s['ll'][1] for s in rows]
    box = (min(lons) - 0.005, max(lons) + 0.005, min(lats) - 0.005, max(lats) + 0.005)
    candidates[network] = [w for w in ways if any(box[0] < x < box[1] and box[2] < y < box[3] for x, y in w[2])]

for network in lines:
    rows = samples[network]
    st = sorted(stations[network], key=lambda s: s['at'])
    for s in rows:
        o = osm_near(network, s['ll'])
        s['osm'], s['layer'] = (o[0], o[1]) if o else (None, '')
    print(f'\n## {network} {lines[network]}')
    # Shares: real class (rail_tracks) against the game's.
    table = defaultdict(int)
    for s in rows:
        table[(s['real'], s['game'])] += 1
    print('real\\game  ' + '  '.join(f'{NAME[g]:>6}' for g in 'URG'))
    for r in ['U', 'R', 'G', None]:
        print(f'{NAME.get(r, "沒對到"):>8}  ' + '  '.join(f'{table[(r, g)]:>6}' for g in 'URG'))
    agree = sum(1 for s in rows if s['osm'] and s['real'] and s['osm'] == s['real'])
    both = sum(1 for s in rows if s['osm'] and s['real'])
    print(f'OSM 與 rail_tracks 同類 {agree}/{both}')

    def between(d):
        before = [x for x in st if x['at'] <= d]
        after = [x for x in st if x['at'] > d]
        return (before[-1]['name'] if before else '起點') + '—' + (after[0]['name'] if after else '終點')

    # Runs where the game's class differs from the real one.
    run = []
    def flush():
        if len(run) >= 2:
            a, b = run[0], run[-1]
            length = b['d'] - a['d'] + 64
            gover = sum(x['gover'] for x in run) / len(run)
            rh = [x['rheight'] for x in run if x['rheight'] is not None]
            layers = sorted({x['layer'] for x in run if x['layer']})
            print(f"  DIFF {a['d']/1000:.2f}–{(b['d']+64)/1000:.2f} km {length} m {between(a['d'])}"
                  f" game {NAME[a['game']]}({a['gkind']}) {gover:+.1f} m real {NAME[a['real']]} {sum(rh)/len(rh):+.1f} m"
                  f" structure {a['structure']} osm {a['osm']} layer {','.join(layers)} ground {a['ground']:.0f}")
        run.clear()
    for s in rows:
        if s['real'] and s['game'] != s['real'] and (not run or (run[-1]['game'], run[-1]['real']) == (s['game'], s['real'])):
            run.append(s)
        else:
            flush()
            if s['real'] and s['game'] != s['real']:
                run.append(s)
    flush()
    # Height gaps where both are the same class but differ by more than 8 m.
    run = []
    def flush_height():
        if len(run) >= 3:
            a, b = run[0], run[-1]
            print(f"  HEIGHT {a['d']/1000:.2f}–{(b['d']+64)/1000:.2f} km {between(a['d'])} {NAME[a['game']]}"
                  f" game {sum(x['gover'] for x in run)/len(run):+.1f} m real {sum(x['rheight'] for x in run)/len(run):+.1f} m")
        run.clear()
    for s in rows:
        if s['real'] and s['game'] == s['real'] and abs(s['gover'] - s['rheight']) > 8:
            run.append(s)
        else:
            flush_height()
    flush_height()
    for x in st:
        near = [o for o in osm_stations if metres((o[2], o[3]), x['ll']) < 600]
        named = [o for o in near if x['name'] in (o[1].get('name') or '')]
        tags = ''
        if named or near:
            o = min(named or near, key=lambda o: (o[1].get('railway') != 'station', metres((o[2], o[3]), x['ll'])))
            t = o[1]
            tags = ' '.join(f'{k}={t[k]}' for k in ('name', 'layer', 'level', 'location', 'station', 'subway') if k in t)
        print(f"  STATION {x['name']} at {x['at']/1000:.2f} km game {x['platforms']} real {x['real']} structure {x['structure']} osm[{tags}]")
