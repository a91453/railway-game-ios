#!/usr/bin/env python3
"""Yard shapes of the real depots the game lays (docs/research/YARD_TYPES_2026-11-07.md).

    python3 -I tools/rail-depots/yard_types.py taiwan.pbf [name ...]

Reads osmtoday.com's asia/taiwan.pbf (ODbL) with pyosmium and, for each depot
window below, takes the rail ways with a `service` tag (yard, siding, spur,
crossover) or inside the window's stabling-way list, then prints: how many
parallel stabling tracks, their length and spacing, the switches (nodes where
three yard ways meet) and the ladder (throat) length at each end, and how many
tracks end in a buffer (dead end) at each end. Single throat = only one end has
switches; double throat = both.
"""
import math
import sys
import statistics as st

import osmium

# name: (lat, lon, radius m, label)
DEPOTS = {
    "muzha": (25.00077, 121.58640, 450, "木柵機廠"),
    "neihu": (25.05990, 121.61990, 450, "內湖機廠"),
    "danhai": (25.20284, 121.43350, 350, "淡海機廠"),
    "ankeng": (24.94400, 121.48700, 300, "安坑機廠"),
    "sanxia": (24.93590, 121.38480, 350, "三峽機廠"),
    "luzhu": (25.08240, 121.27040, 450, "蘆竹機廠"),
    "qingpu": (25.02530, 121.22110, 450, "青埔機廠"),
    "klrt": (22.60960, 120.32550, 450, "高雄輕軌機廠"),
    "liujia": (24.79860, 121.04279, 700, "高鐵六家"),
    "nangang": (25.05420, 121.61506, 1500, "高鐵南港盡頭線"),
}
R = lambda a, b: list(range(a, b + 1))
STABLING = {
    "muzha": R(1342641748, 1342641759) + R(1342641760, 1342641763),
    "neihu": R(1316259201, 1316259216) + R(1054511212, 1054511219),
    "danhai": [690355135, 690355138, 690355139, 690355140, 690355141, 690355144,
               690355145, 690355204, 690377821, 690377824, 690377825],
    "ankeng": R(1140796066, 1140796072) + R(1140796074, 1140796078),
    "sanxia": [1136774767, 1136774768],
    "qingpu": R(499824857, 499824866) + R(499831993, 499832001),
    "klrt": R(501281474, 501281484) + R(1153379542, 1153379546),
}
YARD = {"yard", "siding", "spur", "crossover"}
RAIL = {"rail", "light_rail", "subway"}


def metres(lat0, lon0, lat, lon):
    return ((lon - lon0) * 111320 * math.cos(math.radians(lat0)), (lat - lat0) * 110574)


class Collect(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = []  # (id, tags, [(lat, lon, node)])

    def way(self, w):
        t = w.tags
        if t.get("railway") not in RAIL:
            return
        try:
            pts = [(n.lat, n.lon, n.ref) for n in w.nodes]
        except Exception:
            return
        if len(pts) < 2:
            return
        self.ways.append((w.id, {k: t.get(k) for k in ("railway", "service", "usage", "name")}, pts))


def analyse(name, ways):
    lat0, lon0, rad, label = DEPOTS[name]
    sel = []
    for wid, tags, pts in ways:
        xy = [metres(lat0, lon0, a, b) for a, b, _ in pts]
        if not any(math.hypot(x, y) <= rad for x, y in xy):
            continue
        if tags["service"] in YARD or (name in ("liujia", "nangang") and tags["service"] in YARD):
            sel.append((wid, tags, xy, [n for _, _, n in pts]))
    if not sel:
        print(f"## {name}: no yard ways"); return
    # main axis: PCA over way-length-weighted directions
    sxx = sxy = syy = 0.0
    for _, _, xy, _ in sel:
        for (x0, y0), (x1, y1) in zip(xy, xy[1:]):
            dx, dy = x1 - x0, y1 - y0
            l = math.hypot(dx, dy)
            if l == 0: continue
            sxx += dx * dx / l; sxy += dx * dy / l; syy += dy * dy / l
    ang = 0.5 * math.atan2(2 * sxy, sxx - syy)
    ux, uy = math.cos(ang), math.sin(ang)
    def along(p): return p[0] * ux + p[1] * uy
    def across(p): return -p[0] * uy + p[1] * ux
    length = lambda xy: sum(math.hypot(b[0]-a[0], b[1]-a[1]) for a, b in zip(xy, xy[1:]))
    # parallel stabling tracks: >= 50 m long and within 12 deg of the axis, not crossover
    stab = []
    for wid, tags, xy, nodes in sel:
        if tags["service"] == "crossover": continue
        L = length(xy)
        dx, dy = xy[-1][0]-xy[0][0], xy[-1][1]-xy[0][1]
        chord = math.hypot(dx, dy)
        if L < 50 or chord < 0.9 * L: continue
        a = abs(math.degrees(math.atan2(-dx*uy + dy*ux, dx*ux + dy*uy)))
        a = min(a, 180 - a)
        if a > 12: continue
        mid = xy[len(xy)//2]
        stab.append((wid, L, across(mid), along(xy[0]), along(xy[-1]), nodes))
    stab.sort(key=lambda s: s[2])
    print(f"## {name} {DEPOTS[name][3]}  window {rad} m; yard ways {len(sel)}; axis {math.degrees(ang)%180:.0f} deg")
    if not stab:
        print("   no parallel stabling tracks"); return
    # collapse tracks that overlap in line (same across within 2 m) — report distinct lines
    lines = []
    for s in stab:
        if lines and abs(s[2] - lines[-1][-1][2]) < 2.0: lines[-1].append(s)
        else: lines.append([s])
    offs = [st.mean(t[2] for t in l) for l in lines]
    gaps = [b - a for a, b in zip(offs, offs[1:]) if b - a < 15]
    Ls = [max(t[1] for t in l) for l in lines]
    print(f"   stabling lines {len(lines)} (ways {len(stab)}); across width {offs[-1]-offs[0]:.0f} m")
    print(f"   length m: min {min(Ls):.0f} median {st.median(Ls):.0f} max {max(Ls):.0f}")
    if gaps:
        print(f"   spacing m: min {min(gaps):.1f} median {st.median(gaps):.1f} max {max(gaps):.1f}")
    # switches: nodes shared by >= 3 way-ends among yard ways (incl. crossovers)
    cnt = {}
    pos = {}
    for wid, tags, xy, nodes in sel:
        for n, p in zip(nodes, xy):
            cnt.setdefault(n, set()).add(wid); pos[n] = p
    sw = [n for n, s in cnt.items() if len(s) >= 3]
    # dead ends of stabling tracks per end
    amin = min(min(s[3], s[4]) for s in stab); amax = max(max(s[3], s[4]) for s in stab)
    mid = (amin + amax) / 2
    for end, sign in (("low", -1), ("high", 1)):
        ends = [(s[0], s[5][0] if (s[3] < s[4]) == (sign < 0) else s[5][-1]) for s in stab]
        joined = sum(1 for _, n in ends if len(cnt.get(n, ())) >= 2)
        near = [along(pos[n]) for n in sw if (along(pos[n]) < mid) == (sign < 0)]
        near = [a for a in near if abs(a - (amin if sign < 0 else amax)) < 400]
        ladder = (max(near) - min(near)) if len(near) > 1 else 0
        print(f"   {end} end: tracks {len(ends)}, joined {joined}, buffer {len(ends)-joined}; "
              f"switch nodes within 400 m {len(near)}, ladder length {ladder:.0f} m")
    allsw = sorted(along(pos[n]) for n in sw)
    if len(allsw) > 1:
        d = [b - a for a, b in zip(allsw, allsw[1:]) if b - a > 0.5]
        print(f"   switches {len(sw)}; spacing of successive switches along axis: median {st.median(d):.0f} m, min {min(d):.0f} m")


def main():
    if len(sys.argv) < 2: raise SystemExit(__doc__)
    names = sys.argv[2:] or list(DEPOTS)
    h = Collect(); h.apply_file(sys.argv[1], locations=True)
    for n in names: analyse(n, h.ways)


def graph(name, ways):
    """Stabling ways named in STABLING: count, length, spacing, and the switch
    nodes (three yard ways meeting) reachable from their ends through ways
    with a service tag or none that are not the main line, within 500 m."""
    ids = set(STABLING[name])
    byid = {w[0]: w for w in ways}
    stab = [byid[i] for i in STABLING[name] if i in byid]
    if not stab:
        print(f"## {name}: stabling ways not found"); return
    lat0, lon0 = stab[0][2][0][0], stab[0][2][0][1]
    P = lambda pts: [metres(lat0, lon0, a, b) for a, b, _ in pts]
    # axis: mean direction of stabling chords
    sx = sy = 0.0
    for _, _, pts in stab:
        xy = P(pts); dx, dy = xy[-1][0]-xy[0][0], xy[-1][1]-xy[0][1]
        if dx*sx + dy*sy < 0: dx, dy = -dx, -dy
        sx += dx; sy += dy
    n = math.hypot(sx, sy); ux, uy = sx/n, sy/n
    al = lambda p: p[0]*ux + p[1]*uy
    ac = lambda p: -p[0]*uy + p[1]*ux
    length = lambda xy: sum(math.hypot(b[0]-a[0], b[1]-a[1]) for a, b in zip(xy, xy[1:]))
    Ls, offs, a_lo, a_hi = [], [], [], []
    for _, _, pts in stab:
        xy = P(pts); Ls.append(length(xy)); offs.append(ac(xy[len(xy)//2]))
        a = sorted([al(xy[0]), al(xy[-1])]); a_lo.append(a[0]); a_hi.append(a[1])
    ordr = sorted(offs)
    gaps = [b-a for a, b in zip(ordr, ordr[1:]) if 1.5 < b-a < 15]
    cx = [sum(al(p) for p in map(lambda q: q, [])) ]
    lo, hi = st.median(a_lo), st.median(a_hi)
    # reachable yard graph
    nodeways = {}
    for w in ways:
        for _, _, nid in w[2]: nodeways.setdefault(nid, []).append(w[0])
    pos = {}
    for w in ways:
        for (a, b, nid), q in zip(w[2], P(w[2])): pos[nid] = q
    seen = set(ids); queue = list(ids); comp_nodes = {}
    def yardish(w):
        t = w[1]
        return t["service"] in YARD or (t["service"] is None and t["usage"] not in ("main", "branch"))
    centre = (st.mean(offs), (lo+hi)/2)
    while queue:
        wid = queue.pop()
        for _, _, nid in byid[wid][2]:
            q = pos[nid]
            if math.hypot(ac(q)-centre[0], al(q)-centre[1]) > 500: continue
            comp_nodes.setdefault(nid, set()).add(wid)
            for o in nodeways[nid]:
                if o not in seen and yardish(byid[o]):
                    seen.add(o); queue.append(o)
    for nid in list(comp_nodes):
        comp_nodes[nid] = set(nodeways[nid]) & seen
    sw = [nid for nid, s in comp_nodes.items() if len(s) >= 3]
    exits = [nid for nid in comp_nodes if any(not yardish(byid[o]) for o in nodeways[nid])]
    print(f"## {name}: {len(stab)} stabling ways of {len(ids)} named; length median {st.median(Ls):.0f} m (min {min(Ls):.0f}, max {max(Ls):.0f}); "
          f"across {ordr[-1]-ordr[0]:.0f} m; spacing median {st.median(gaps) if gaps else 0:.1f} m (min {min(gaps) if gaps else 0:.1f})")
    for end, ref in (("low", lo), ("high", hi)):
        s_ = [al(pos[n]) for n in sw if abs(al(pos[n]) - ref) < 350 and ((al(pos[n]) < (lo+hi)/2) == (end == "low"))]
        e_ = [al(pos[n]) for n in exits if abs(al(pos[n]) - ref) < 500 and ((al(pos[n]) < (lo+hi)/2) == (end == "low"))]
        ladder = (max(s_) - min(s_)) if len(s_) > 1 else 0
        reach = (max(abs(x-ref) for x in s_)) if s_ else 0
        print(f"   {end} end at {ref:+.0f} m: switch nodes {len(s_)}, ladder length {ladder:.0f} m (farthest {reach:.0f} m from the stabling ends), connections to the line {len(e_)}")
    ss = sorted(al(pos[n]) for n in sw)
    d = [b-a for a, b in zip(ss, ss[1:]) if b-a > 1.0]
    if d: print(f"   switch nodes {len(sw)}; successive spacing along axis: median {st.median(d):.0f} m, min {min(d):.0f} m")


def main():
    if len(sys.argv) < 2: raise SystemExit(__doc__)
    names = sys.argv[2:] or list(DEPOTS)
    h = Collect(); h.apply_file(sys.argv[1], locations=True)
    for n in names:
        if n in STABLING: graph(n, h.ways)
        else: analyse(n, h.ways)


main()
