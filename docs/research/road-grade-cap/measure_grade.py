"""Decision 834 (ROAD-GRADE-CAP): the motorways' grade before and after.

Reads the app's own files as decision 737's measure.py does (its reader,
the 64 m corners in whole metres, decision 737's levelling), lays the
motorways (the tiles' `motorway`, link roads too, bridges as free spans,
no tunnels) joined end to end, works out each one's profile as
`Map3DRoadGrade` does (U/L envelopes at 5 % within 420 m, the slack
growing without end from 300 m to 420 m, held at the ground at a road's
ends, then held to 8 % along each piece) and prints the grade on the
ground (every 8 m, as measure.py) before and after, and how deep the
cuttings and how high the fills.

    pip install mapbox-vector-tile numpy
    cd docs/research/road-grade-cap && python3 measure_grade.py
"""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../road-flatten'))
import measure as M
import opt2
import mapbox_vector_tile as mvt

GRADE, STEEPEST, WINDOW, TAPER, STEP, JOIN = 0.05, 0.08, 420.0, 300.0, 8.0, 1.5

def levelled(radius=3, sigma=2.0, clamp=3.0):
    """Decision 737's corners (opt3.py's `make`, its chosen values)."""
    memo = {}
    def corner(i, j):
        if (i, j) in memo: return memo[(i, j)]
        s = w = 0
        for di in range(-radius, radius + 1):
            for dj in range(-radius, radius + 1):
                ww = math.exp(-(di * di + dj * dj) / (2 * sigma * sigma)); s += ww * opt2.rc(i + di, j + dj); w += ww
        v = opt2.rc(i, j); memo[(i, j)] = v + max(-clamp, min(clamp, s / w - v)); return memo[(i, j)]
    return corner

def slack(d):
    d = np.asarray(d, dtype=float)
    past = np.maximum(0, d - TAPER)
    with np.errstate(divide='ignore'):
        extra = np.where(d < WINDOW, GRADE * past * past / np.maximum(WINDOW - d, 1e-9), np.inf)
    return GRADE * d + extra

def motorways(lat0, lon0, lat1, lon1):
    z = 14; n = 2 ** z
    def tx(lon): return int((lon + 180) / 360 * n)
    def ty(lat): return int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
    out = []
    for x in range(tx(lon0) - 1, tx(lon1) + 2):
        for y in range(ty(lat1) - 1, ty(lat0) + 2):
            b = M.find(M.tile_id(z, x, y))
            if not b: continue
            t = mvt.decode(b)
            if 'transportation' not in t: continue
            L = t['transportation']; ext = L['extent']
            for f in L['features']:
                p = f['properties']
                if p.get('class') != 'motorway' or p.get('brunnel') == 'tunnel': continue
                g = f['geometry']
                lines = [g['coordinates']] if g['type'] == 'LineString' else (g['coordinates'] if g['type'] == 'MultiLineString' else [])
                for ln in lines:
                    out.append((p.get('brunnel') == 'bridge', bool(p.get('ramp')), [M.lonlat(z, x, y, a, b2, ext) for a, b2 in ln]))
    return out

def run(name, box, inner):
    M.LAT0 = box[0]; opt2.raw.clear()
    ground = opt2.gg_factory(levelled())
    k = math.cos(math.radians(M.LAT0))
    def metres(la, lo): return ((lo - 121) * 111320 * k, (la - M.LAT0) * 110574)
    pieces = []
    for bridge, ramp, pts in motorways(*box):
        P = np.array([metres(la, lo) for la, lo in pts])
        d = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
        if d[-1] < 0.01: continue
        at = np.arange(0, d[-1], STEP)
        if d[-1] - at[-1] > 1e-6: at = np.r_[at, d[-1]]
        S = np.c_[np.interp(at, d, P[:, 0]), np.interp(at, d, P[:, 1])]
        G = np.array([ground(M.LAT0 + z / 110574, 121 + x / (111320 * k)) for x, z in S])
        pieces.append(dict(bridge=bridge, P=P, S=S, G=G))
    # Pieces meet where one's end lies on another.
    def on(p, piece):
        A = piece['P'][:-1]; B = piece['P'][1:]; AB = B - A
        t = np.clip(((p - A) * AB).sum(1) / np.maximum((AB * AB).sum(1), 1e-12), 0, 1)
        return np.min(np.hypot(*(A + AB * t[:, None] - p).T)) <= JOIN
    nb = [set() for _ in pieces]; terms = []
    for i, a in enumerate(pieces):
        for end, s in [(a['P'][0], 0), (a['P'][-1], -1)]:
            met = False
            for j, b in enumerate(pieces):
                if j != i and on(end, b): nb[i].add(j); nb[j].add(i); met = True
            if not met: terms.append((i, end, a['G'][s]))
    # Components (the whole road; the app looks only within the window).
    comp = [-1] * len(pieces); c = 0
    for i in range(len(pieces)):
        if comp[i] >= 0: continue
        stack = [i]; comp[i] = c
        while stack:
            u = stack.pop()
            for v in nb[u]:
                if comp[v] < 0: comp[v] = c; stack.append(v)
        c += 1
    before, after, cut, fill = [], [], [], []
    for i, a in enumerate(pieces):
        mates = [j for j in range(len(pieces)) if comp[j] == comp[i]]
        QS = np.concatenate([pieces[j]['S'] for j in mates if not pieces[j]['bridge']] or [np.zeros((0, 2))])
        QG = np.concatenate([pieces[j]['G'] for j in mates if not pieces[j]['bridge']] or [np.zeros(0)])
        T = [(e, g) for (j, e, g) in terms if comp[j] == comp[i]]
        prof = []
        for p in a['S']:
            d = np.hypot(*(QS - p).T); w = d <= WINDOW
            if not w.any(): prof.append(np.nan); continue
            h = ((QG[w] + slack(d[w])).min() + (QG[w] - slack(d[w])).max()) / 2
            lo, hi = -np.inf, np.inf
            for e, g in T:
                dd = math.hypot(*(e - p))
                if dd <= WINDOW: lo = max(lo, g - slack(dd)); hi = min(hi, g + slack(dd))
            h = min(max(h, lo), hi) if lo <= hi else (lo + hi) / 2
            prof.append(h)
        prof = np.array(prof)
        # Held to STEEPEST along the piece itself, both ways.
        for order in (range(1, len(prof)), range(len(prof) - 2, -1, -1)):
            for j in order:
                o = j - 1 if order.step == 1 else j + 1
                if np.isnan(prof[j]) or np.isnan(prof[o]): continue
                most = STEEPEST * math.hypot(*(a['S'][j] - a['S'][o]))
                prof[j] = min(max(prof[j], prof[o] - most), prof[o] + most)
        if a['bridge']: continue
        # Only the samples inside the measured box, as measure.py's region.
        la = M.LAT0 + a['S'][:, 1] / 110574; lo_ = 121 + a['S'][:, 0] / (111320 * k)
        keep = (la >= inner[0]) & (la <= inner[2]) & (lo_ >= inner[1]) & (lo_ <= inner[3])
        steps = np.hypot(*np.diff(a['S'], axis=0).T); both = keep[1:] & keep[:-1] & (steps > 1)
        before += list((np.abs(np.diff(a['G'])) / steps)[both])
        ok = both & ~np.isnan(prof[1:]) & ~np.isnan(prof[:-1])
        after += list((np.abs(np.diff(prof)) / steps)[ok])
        off = prof - a['G']
        cut += list(-off[keep & (off < 0)]); fill += list(off[keep & (off > 0)])
    q = lambda xs, p: np.percentile(xs, p) if len(xs) else float('nan')
    km = len(before) * STEP / 1000
    print(f"== {name}: motorway {km:.1f} km on the ground")
    if not before: return
    print(f"   grade p50 {q(before,50)*100:.1f}% p95 {q(before,95)*100:.1f}% max {max(before)*100:.1f}%  ->  "
          f"p50 {q(after,50)*100:.1f}% p95 {q(after,95)*100:.1f}% max {max(after)*100:.1f}%  (over 5%: {np.mean(np.array(after)>0.0505)*100:.1f}% of steps)")
    print(f"   cutting depth p95 {q(cut,95):.1f} max {max(cut or [0]):.1f} m;  fill height p95 {q(fill,95):.1f} max {max(fill or [0]):.1f} m;"
          f"  moved over 0.5 m: {np.mean(np.abs(np.r_[cut, fill]) > 0.5) * len(cut + fill) * STEP / 1000:.1f} km")

if __name__ == "__main__":
    for name, inner in [('林口坡地', (25.050, 121.340, 25.080, 121.380)), ('木柵、深坑（國3）', (24.980, 121.560, 25.010, 121.620)),
                        ('三重、五股平地（國1）', (25.060, 121.440, 25.090, 121.490))]:
        pad = 0.006  # the roads round it, as a scene reads past its region
        run(name, (inner[0] - pad, inner[1] - pad, inner[2] + pad, inner[3] + pad), inner)
