#!/usr/bin/env python3
"""Original, deterministic airport studies; metres, x forward/y left/z up.

Decision 698 rebuilt the look of decision 594's studies (model-look): lofted
fuselages with a nose and an upswept tail, aerofoil wings and tails, nacelles
with propellers or intakes, round wheels, asphalt runways, terminals standing
on their own ground, and lamps that light the pavement at night.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve()
FERRY = HERE.parents[1] / 'ferry-studies' / 'produce.py'
spec = importlib.util.spec_from_file_location('native_mesh', FERRY)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
P = mod.P
# Muted, flat colours beside the game's own palette. Pavement is grey, never
# the navy of `dark` (the first pass's runway read as water).
P.update(deck=0xC6C8CA, warm=0xE3B349, asphalt=0x4B4E56, taxi=0x5C6069,
         joint=0xA9ACB1, grass=0xBDD1AB, belly=0xC9CED6, cockpit=0x22304A,
         tyre=0x2A2C33, metal=0x9BA2AB, wall=0xDDE0E4, base=0xB4B9C2,
         roof=0x7F90A8, navy=0x2F4470, orange=0xE28A3A, lamp=0xFFF1C4,
         lampgreen=0x62D29A, lampred=0xF0604E, lampblue=0x6FA8F5,
         window=0x3B4D6B, hub=0xD8DCE2, pane=0x7C9BBB)

# length, wingspan, height: the makers' published figures (SOURCE.md in the
# private pack). Everything else is read off photographs.
SPECS = {
    'commuter19': (16.56, 16.97, 4.86, 0.80, 5.75, 'high', 'prop'),
    'regional70': (27.17, 27.05, 7.65, 1.435, 10.9, 'high-t', 'prop'),
    'narrowjet': (44.51, 35.80, 11.76, 1.975, 15.3, 'low', 'jet'),
    'widejet': (66.80, 64.75, 17.05, 2.98, 24.0, 'low', 'jet'),
}
PALETTES = [('white', 'blue'), ('white', 'green'), ('white', 'red'), ('white', 'navy')]
DEFAULT_PAINT = {'commuter19': 2, 'regional70': 0, 'narrowjet': 1, 'widejet': 3}
PARTS = ('runway', 'runway-end', 'taxiway', 'apron', 'papi', 'windsock', 'fence',
         'tug', 'baggage', 'stairs', 'fuel')
NAMES = {'commuter19':'十九座雙螺旋槳', 'regional70':'七十座雙渦輪螺旋槳',
         'narrowjet':'窄體噴射客機', 'widejet':'廣體噴射客機',
         'city':'城市航廈', 'island':'離島航廈', 'city-scene':'城市機位組景',
         'island-scene':'離島機位組景', 'runway':'跑道中段', 'runway-end':'跑道頭',
         'taxiway':'滑行道', 'apron':'停機坪', 'papi':'進場燈', 'windsock':'風向袋',
         'fence':'圍界', 'tug':'推車', 'baggage':'行李拖車', 'stairs':'登機梯車',
         'fuel':'加油車'}

# The shape of each type. Stations run from the nose (s = metres behind it):
# (s, half-width fraction, top, bottom), top and bottom in half-heights from
# the fuselage centre line. `e` is the section's superellipse exponent: 2 is
# round, larger is the boxy cabin of the short-field type.
SHAPES = {
 'commuter19': dict(hw=.80, hh=.95, zc=1.57, e=3.6,
    hull=[(0,.07,-.38,-.56),(.5,.34,-.12,-.80),(1.4,.62,.18,-.95),(2.35,.86,.50,-1),
          (3.25,1,1,-1),(9.6,1,1,-1),(12.2,.72,1,-.30),(15.2,.34,.96,.30),(16.56,.10,.90,.62)],
    cockpit=3, cabin=(3.9,9.3,.80,.40,(.10,.58)), door=(9.9,.72),
    wing=[(0,5.75,2.05,2.67,.30),(5.0,5.75,2.05,2.71,.28),(7.6,6.45,1.25,2.73,.18),(8.485,7.25,.42,2.74,.07)],
    fin=[(2.36,12.1,3.7,.20),(2.9,13.0,2.9,.18),(4.86,14.55,1.75,.12)],
    tail=[(.2,14.3,1.50,2.16,.14),(3.25,14.6,1.15,2.22,.10)],
    engine=dict(y=2.45,z=2.34,r=.34,s0=4.35,s1=7.9,prop=1.25,blades=5),
    nose_gear=(1.75,.24,0), main_gear=(8.0,1.65,.34,0,0),
    sponson=(6.6,9.1,1.10,.92,.50,.34)),
 'regional70': dict(hw=1.435, hh=1.435, zc=2.15, e=2.0,
    hull=[(0,.07,-.30,-.46),(.45,.40,.02,-.72),(1.3,.70,.42,-.90),(1.75,.78,.58,-.93),(2.5,.90,.82,-.98),(3.1,.95,.92,-.99),
          (3.9,1,1,-1),(15.8,1,1,-1),(19.5,.80,1,-.35),(23.5,.45,.98,.25),(26.2,.14,.95,.72)],
    cockpit=3, side_windows=True, cabin=(4.9,18.4,.78,.30,(.16,.50)), door=(19.6,.70),
    wing=[(0,10.9,2.62,3.68,.47),(4.7,10.9,2.62,3.74,.45),(13.525,11.35,1.55,3.88,.24)],
    fin=[(3.44,17.2,8.6,.30),(4.4,20.6,5.4,.30),(7.65,24.5,2.5,.20)],
    tail=[(0,24.9,2.27,7.48,.20),(3.65,25.6,1.40,7.50,.14)],
    engine=dict(y=4.05,z=3.18,r=.50,s0=8.75,s1=15.2,prop=1.965,blades=6),
    nose_gear=(2.6,.23,.16), main_gear=(13.4,2.05,.42,.20,0),
    sponson=(11.0,15.8,1.50,1.20,.70,.52)),
 'narrowjet': dict(hw=1.975, hh=2.07, zc=3.72, e=2.0,
    hull=[(0,.06,-.12,-.30),(.6,.40,.18,-.62),(1.5,.64,.46,-.82),(2.25,.78,.66,-.90),(2.9,.86,.82,-.955),(3.6,.93,.92,-.98),
          (5.4,1,1,-1),(29.5,1,1,-1),(34,.86,1,-.55),(39,.52,.98,.05),(43.3,.20,.92,.52),(44.51,.07,.86,.70)],
    cockpit=3, side_windows=True, cabin=(6.6,36.4,.56,.30,(.30,.72)), door=(5.6,.90),
    wing=[(1.2,14.9,7.0,2.44,.85),(1.95,15.3,6.6,2.46,.80),(6.3,17.6,4.2,2.80,.50),(16.6,23.0,1.65,3.75,.18)],
    winglet=[(17.25,23.45,1.45,3.98,.16,.5),(17.70,23.95,1.15,4.60,.12,1),(17.84,24.85,.55,6.15,.10,1)],
    fin=[(5.58,34.0,6.6,.45),(11.76,41.0,2.3,.16)],
    tail=[(.3,37.4,4.4,4.45,.36),(6.22,41.3,1.5,5.0,.14)],
    engine=dict(y=5.75,z=1.74,r=1.22,s0=11.6,s1=16.4,cone=17.7),
    nose_gear=(5.6,.37,.25), main_gear=(22.4,3.8,.58,.42,0)),
 'widejet': dict(hw=2.98, hh=3.045, zc=5.10, e=2.0,
    hull=[(0,.06,-.15,-.32),(.8,.42,.20,-.66),(2.0,.66,.50,-.84),(3.1,.80,.70,-.91),(3.95,.88,.84,-.965),(4.9,.94,.93,-.985),
          (7.2,1,1,-1),(43.5,1,1,-1),(51,.86,1,-.50),(59,.50,.98,.08),(65,.20,.93,.55),(66.8,.07,.88,.72)],
    cockpit=3, side_windows=True, cabin=(8.8,54.5,.60,.32,(.28,.66)), door=(8.0,1.05),
    wing=[(1.5,23.0,13.0,3.25,1.5),(2.95,24.0,12.0,3.30,1.3),(10.2,29.3,6.6,3.95,.75),(28.5,42.2,2.6,6.10,.26),
          (30.6,44.6,1.7,6.75,.18),(31.8,46.6,.9,7.35,.12),(32.375,48.3,.35,7.90,.06)],
    fin=[(8.0,50.5,9.6,.70),(17.05,61.0,3.4,.24)],
    tail=[(.5,56.0,6.6,6.30,.50),(9.35,62.2,2.2,7.10,.20)],
    engine=dict(y=10.5,z=2.70,r=1.95,s0=23.4,s1=29.9,cone=31.6),
    nose_gear=(6.6,.50,.33), main_gear=(35.4,5.3,.68,.60,.95)),
}

def dot(a,b): return sum(x*y for x,y in zip(a,b))

def add_tris(mesh, name, tris):
    """One closed solid from explicit triangles (points, colour, glow)."""
    if sum(dot(v[0], mod.cross(v[1], v[2])) for v,_,_ in tris) < 0:
        tris = [([v[0],v[2],v[1]],c,g) for v,c,g in tris]
    start = len(mesh.t)
    mesh.t += [(list(v), P.get(c,c), g) for v,c,g in tris]
    mesh.solids.append(dict(name=name, start=start, count=len(tris)))

def loft(mesh, name, rings, color):
    """Closed skin over rings of equal count, capped at both ends. `color` is
    a colour or f(band, index) -> colour or (colour, glow); band is 'a' / 'b'
    on the caps."""
    def col(k,i):
        c = color(k,i) if callable(color) else color
        return c if isinstance(c, tuple) else (c, 0)
    n = len(rings[0]); tris = []
    for i in range(1, n-1):
        tris.append(([rings[0][0], rings[0][i+1], rings[0][i]], *col('a',i)))
        tris.append(([rings[-1][0], rings[-1][i], rings[-1][i+1]], *col('b',i)))
    for k in range(len(rings)-1):
        a, b = rings[k], rings[k+1]
        for i in range(n):
            j = (i+1) % n; c = col(k,i)
            tris.append(([a[i], a[j], b[j]], *c)); tris.append(([a[i], b[j], b[i]], *c))
    add_tris(mesh, name, tris)

def basis(d):
    u = mod.unit(mod.cross(d, (0,0,1) if abs(d[2]) < .9 else (1,0,0)))
    return u, mod.cross(d, u)

def cyl(mesh, name, a, b, r, color, n=10, r1=None, glow=0):
    d = mod.unit(mod.sub(b, a)); u, v = basis(d); r1 = r if r1 is None else r1
    ring = lambda p, rad: [mod.add(p, mod.add(mod.mul(u, rad*math.cos(2*math.pi*i/n)),
                                               mod.mul(v, rad*math.sin(2*math.pi*i/n)))) for i in range(n)]
    loft(mesh, name, [ring(a, r), ring(b, r1)], (color, glow))

def bar(mesh, name, a, b, w, h, color, up=(0,0,1), glow=0):
    """A rectangular bar from a to b: w across, h along `up`."""
    d = mod.unit(mod.sub(b, a)); side = mod.unit(mod.cross(up, d)); upv = mod.cross(d, side)
    ring = lambda p: [mod.add(p, mod.add(mod.mul(side, sx*w/2), mod.mul(upv, sz*h/2)))
                      for sx,sz in ((-1,-1),(1,-1),(1,1),(-1,1))]
    loft(mesh, name, [ring(a), ring(b)], (color, glow))

def beam(mesh, name, a, b, size, color):
    """A square beam from a to b (the fence's arms)."""
    d = mod.unit(mod.sub(b, a)); u0 = mod.unit(mod.cross(d, (0,0,1) if abs(d[2]) < .95 else (0,1,0)))
    u = mod.mul(u0, size/2); v = mod.mul(mod.cross(d, u0), size/2)
    ring = lambda p: [mod.add(p, mod.add(mod.mul(u, s), mod.mul(v, t))) for s,t in ((-1,-1),(1,-1),(1,1),(-1,1))]
    loft(mesh, name, [ring(a), ring(b)], color)

def slab(mesh, name, corners, color, glow=0, out=.02, back=.04):
    """A thin plate on a surface: four corners, pushed out along their normal."""
    n = mod.unit(mod.cross(mod.sub(corners[1], corners[0]), mod.sub(corners[3], corners[0])))
    loft(mesh, name, [[mod.add(p, mod.mul(n, -back)) for p in corners],
                      [mod.add(p, mod.mul(n, out)) for p in corners]], (color, glow))

def section(x, zc, hw, up, dn, n, e):
    pts = []
    for i in range(n):
        a = 2*math.pi*(i+.5)/n; c, s = math.cos(a), math.sin(a)
        pts.append((x, hw*math.copysign(abs(c)**(2/e), c),
                    zc + (up if s >= 0 else dn)*math.copysign(abs(s)**(2/e), s)))
    return pts

AEROFOIL = [(0,0),(.07,.58),(.30,1),(.66,.60),(1,.05),(.66,-.36),(.30,-.55),(.07,-.42)]
def aerofoil(le, chord, t, tdir=(0,0,1)):
    return [mod.add((le[0]-chord*c, le[1], le[2]), mod.mul(tdir, t*k*.5)) for c,k in AEROFOIL]

def wheel(mesh, x, y, r, w, far):
    cyl(mesh, 'tyre', (x, y-w/2, r), (x, y+w/2, r), r, 'tyre', 6 if far else 12)
    if not far:
        cyl(mesh, 'wheel-hub', (x, y-w/2-.012, r), (x, y+w/2+.012, r), r*.40, 'metal', 8)

def aircraft(mesh, kind, far, paint=None):
    L,W,H,_,_,wing,engine = SPECS[kind]; S = SHAPES[kind]
    paint = PALETTES[DEFAULT_PAINT[kind] if paint is None else paint][1]
    hw, hh, zc, e = S['hw'], S['hh'], S['zc'], S['e']
    X = lambda s: L/2 - s
    n = 16 if far else 24
    jet = engine == 'jet'
    # Fuselage: one closed skin. The windscreen, the belly and the painted
    # tail are colours of its own faces, so nothing floats on it.
    rings = [section(X(s), zc+hh*(top+bot)/2, hw*k, hh*(top-bot)/2, hh*(top-bot)/2, n, e)
             for s,k,top,bot in S['hull']]
    stations = S['hull']; tail_from = next(i for i,st in enumerate(stations) if st[0] > L*.5 and st[1] < 1) - 1
    def skin(k, i):
        if k in ('a','b'): return 'white' if k == 'a' else paint
        up = min(i, n//2-1-i)          # 0 is the face just above the waist, either side
        if k == S['cockpit'] and 1 <= up and i < n//2: return 'cockpit'      # the windscreen: a strip round the nose
        if S.get('side_windows') and k == S['cockpit']+1 and 1 <= up <= (1 if far else 2) and i < n//2: return 'cockpit'   # and the side windows behind it
        if k >= tail_from + (1 if jet else 2): return paint
        if jet and i >= n//2 and min(i-n//2, n-1-i) >= n//8: return 'belly'
        if not jet and (i == n-1 or i == n//2) and S['cockpit'] < k: return paint   # cheat line at the waist
        return 'white'
    loft(mesh, 'fuselage', rings, skin)
    side_y = lambda z: hw*(1-min(1,abs(z/hh))**e)**(1/e)
    def on_side(name, s0, s1, z0, z1, color, glow=0):
        for side in (-1,1):
            c = [(X(s0), side*side_y(z0), zc+z0), (X(s1), side*side_y(z0), zc+z0),
                 (X(s1), side*side_y(z1), zc+z1), (X(s0), side*side_y(z1), zc+z1)]
            slab(mesh, name, c if side > 0 else c[::-1], color, glow)
    s0, s1, pitch, width, (z0, z1) = S['cabin']
    if far:
        on_side('cabin-window', s0, s1, z0*hh, z1*hh, 'window', 1)
    else:
        for i in range(int((s1-s0)/pitch)+1):
            on_side('cabin-window', s0+i*pitch, s0+i*pitch+width, z0*hh, z1*hh, 'window', 1)
    door_s, door_w = S['door']; sill = zc - hh*.42
    if not far:
        for za, zb in ((-.42,-.14),(-.14,.14),(.14,.42)):
            c = [(X(door_s), side_y(za*hh), zc+za*hh), (X(door_s+door_w), side_y(za*hh), zc+za*hh),
                 (X(door_s+door_w), side_y(zb*hh), zc+zb*hh), (X(door_s), side_y(zb*hh), zc+zb*hh)]
            slab(mesh, 'door', c, 'belly', 0, .025, .03)
    # Wings, tailplane and fin: aerofoil sections, thick at the root.
    wing_sections = S['wing']
    for side in (-1,1):
        w = [aerofoil((X(s), side*y, z), chord, t) for y,s,chord,z,t in wing_sections]
        tips = len(w)
        for y,s,chord,z,t,lean in S.get('winglet', []):
            w.append(aerofoil((X(s), side*y, z), chord, t, mod.unit((0, side*lean, 1-lean))))
        tip_from = tips-1 if 'winglet' in S else len(w)-{'widejet':3,'commuter19':2}.get(kind,0)
        loft(mesh, 'left-wing' if side > 0 else 'right-wing', w,
             lambda k,i: paint if k != 'a' and tip_from < len(w) and (k == 'b' or k >= tip_from) else 'belly')
        t = [aerofoil((X(s), side*y, z), chord, th) for y,s,chord,z,th in S['tail']]
        loft(mesh, 'tailplane', t, 'belly')
    loft(mesh, 'vertical-tail', [aerofoil((X(s), 0, z), chord, t, (0,1,0)) for z,s,chord,t in S['fin']], paint)
    tip_y, tip_s, _, tip_z, _ = wing_sections[-1]
    if not far:
        for side in (-1,1):
            mesh.box('wingtip-strobe', X(tip_s)-.2, side*(tip_y-.42), tip_z+.02, .22, .18, .09, 'lamp', 1)
            mesh.box('nav-red' if side > 0 else 'nav-green', X(tip_s)-.02, side*(tip_y-.42), tip_z+.02, .20, .18, .09,
                     'lampred' if side > 0 else 'lampgreen', 1)
        mesh.box('tail-white', -L/2+.25, 0, zc+hh*stations[-1][2]-.02, .22, .14, .10, 'lamp', 1)
        mesh.box('anti-collision', X(L*.42), 0, zc+hh-.03, .30, .26, .16, 'lampred', 1)
        mesh.box('beacon-belly', X(L*.46), 0, zc-hh-.10, .28, .24, .13, 'lampred', 1)
    else:
        for name in ('wingtip-strobe','nav-red','nav-green','tail-white','anti-collision'):
            mesh.box(name, X(L*.42), 0, zc+hh-.03, .30, .26, .12, 'lampred', 1)
    eng = S['engine']; joints = []
    for side in (-1,1):
        ey = side*eng['y']; ez = eng['z']; r = eng['r']; m = 8 if far else 14
        ring = lambda s, rad, dz=0: [(X(s), ey+rad*math.cos(2*math.pi*i/m), ez+dz+rad*math.sin(2*math.pi*i/m)) for i in range(m)]
        if jet:
            a, b = eng['s0'], eng['s1']
            loft(mesh, 'underwing-engine', [ring(a, r*.84), ring(a+.22, r*.97), ring(a+.5, r), ring(a+(b-a)*.55, r), ring(b, r*.70)],
                 lambda k,i: 'cockpit' if k in ('a','b') else ('hub' if k == 0 else paint if k in (1,2) else 'belly'))
            loft(mesh, 'exhaust-cone', [ring(b-.2, r*.46), ring(eng['cone'], r*.12)], 'metal')
            if not far:
                loft(mesh, 'fan-spinner', [ring(a+.5, r*.30), ring(a-.12, r*.06)], 'hub')
            wz = S['wing'][2][3]
            le = S['wing'][2][1]; top = wz - .12
            py = lambda yy: [(X(a+(b-a)*.30), yy, ez+r*.85), (X(b+.3), yy, ez+r*.35), (X(le+(b-a)*.55), yy, top), (X(le-.2), yy, top)]
            loft(mesh, 'engine-pylon', [py(ey-.17), py(ey+.17)], 'belly')
        else:
            a, b = eng['s0'], eng['s1']
            loft(mesh, 'engine-nacelle', [ring(a, r*.62), ring(a+.5, r), ring(a+(b-a)*.5, r*.96, .04), ring(b, r*.22, .16)],
                 lambda k,i: 'metal' if k in ('a','b') else 'white')
            loft(mesh, 'prop-spinner', [ring(a+.02, r*.50), ring(a-.55, r*.10)], paint)
            hub = (X(a-.22), ey, ez); blades = eng['blades'] if not far else 3
            for k in range(blades):
                ang = 2*math.pi*k/blades + .3; radial = (0, math.cos(ang), math.sin(ang))
                bar(mesh, 'prop-blade', mod.add(hub, mod.mul(radial, r*.3)), mod.add(hub, mod.mul(radial, eng['prop'])),
                    eng['prop']*.13, .07, 'tyre', (1,0,0))
            joints.append({'part':f'propeller-{side}','kind':'rotation','pivot':list(hub),'axis':[1,0,0],
                           'unit':'radians','limit':[0,2*math.pi]})
    # Undercarriage: round wheels on struts that reach the airframe.
    s, r, off = S['nose_gear']
    cyl(mesh, 'gear-strut', (X(s), 0, r), (X(s), 0, zc-hh*.80), .09 if kind != 'widejet' else .14, 'metal', 6)
    for y in ((-off, off) if off and not far else (0,)):
        wheel(mesh, X(s), y, r, .16 if off else .20, far)
    s, y, r, off, bogie = S['main_gear']
    for side in (-1,1):
        top = S['wing'][1][3]-.1 if jet else zc-hh*.55
        cyl(mesh, 'gear-strut', (X(s), side*y, r), (X(s), side*(y if jet else y-.35), top), .13 if jet else .08, 'metal', 6)
        for dx in ((-bogie, bogie) if bogie else (0,)):
            if bogie: bar(mesh, 'bogie-beam', (X(s)-bogie, side*y, r), (X(s)+bogie, side*y, r), .2, .2, 'metal')
            for dy in ((-off, off) if off and not far else (0,)):
                wheel(mesh, X(s)+dx, side*y+dy, r, r*.62 if off else r*.7, far)
        if 'sponson' in S:
            a, b, cy, cz, sw, sh = S['sponson']
            loft(mesh, 'gear-sponson', [section(X(a+(b-a)*f), cz, sw*k, sh*k, sh*k, 8 if far else 12, 2.6)
                                        for f,k in ((0,.25),(.25,.9),(.6,1),(1,.3))], 'white')
            mesh.transform(mesh.solids[-1]['start'], lambda p, o=side*cy: (p[0], p[1]+o, p[2]))
    if jet:
        # The belly fairing under the wing, and the flap-track fairings behind it.
        ws = S['wing']; a = ws[1][1]-ws[1][2]*.12; b = ws[1][1]+ws[1][2]*1.12
        loft(mesh, 'belly-fairing', [section(X(a+(b-a)*f), zc-hh*.80, hw*1.06*k, hh*.36*k, hh*.36*k, 8 if far else 12, 2.6)
                                     for f,k in ((0,.3),(.2,.9),(.75,1),(1,.3))], 'belly')
        if not far:
            for side in (-1,1):
                for f in (.30,.52,.74):
                    y = ws[1][0]+(ws[-1][0] if 'winglet' in S else ws[3][0])*f
                    lo, hi = next((p,q) for p,q in zip(ws, ws[1:]) if p[0] <= y <= q[0]); u = (y-lo[0])/(hi[0]-lo[0])
                    s_te = lo[1]+lo[2]+(hi[1]+hi[2]-lo[1]-lo[2])*u; z = lo[3]+(hi[3]-lo[3])*u; c = lo[2]+(hi[2]-lo[2])*u
                    loft(mesh, 'flap-fairing', [section(X(s_te-c*.55+c*.85*g), z-.10-c*.03, hw*.085*k+.04, hw*.075*k+.04, hw*.075*k+.04, 6, 2)
                                                for g,k in ((0,.4),(.35,1),(1,.25))], 'belly')
                    mesh.transform(mesh.solids[-1]['start'], lambda p, o=side*y: (p[0], p[1]+o, p[2]))
    if kind == 'regional70' and not far:
        loft(mesh, 'wing-fairing', [section(X(s), zc+hh-.05, 1.05*k, .50*k, .2, 12, 2.4)
                                    for s,k in ((9.2,.3),(10.6,1),(13.6,1),(16.2,.3))], 'white')
    return {'length_m':L,'wingspan_m':W,'height_m':H,
            'door':{'position':[X(door_s+door_w/2), side_y(0), sill],'heading':[0,1,0]},
            'nose_gear':[X(S['nose_gear'][0]),0,0],
            'joints':joints+[{'part':'landing-gear','kind':'rotation','pivot':[X(S['main_gear'][0]),0,zc-hh*.55],
                              'axis':[0,1,0],'limit':[0,1.2],'fixed':kind=='commuter19'},
                             {'part':'door','kind':'rotation','pivot':[X(door_s),side_y(0),sill],
                              'axis':[0,0,1],'limit':[0,1.57]}],
            'night_flags':['nav-red','nav-green','tail-white','anti-collision','wingtip-strobe','cabin-window']}

# ---- ground ---------------------------------------------------------------

def disc(mesh, name, x, y, z, r, color, glow=0, n=8, h=.004):
    cyl(mesh, name, (x,y,z), (x,y,z+h), r, color, n, glow=glow)

def lit(color):
    """The pavement's colour for a pool of light: a shade under it, because a
    glowing face is drawn a shade brighter by day."""
    c = P[color]; return ((c>>16&255)-6)<<16 | ((c>>8&255)-6)<<8 | (c&255)-6

def lamp(mesh, name, x, y, color, pool, pool_r, pave=.08, far=False, size=.9, inward=(0,0)):
    """A light fitting and the pavement it lights: the pool is the pavement's
    own colour with the glow flag, so it only shows at night. `inward` moves
    the pool onto the pavement when the fitting stands at its edge."""
    if far: size *= 1.8          # the far model is seen small: its lamps are what is left of the runway at night
    mesh.box(name, x, y, pave, size, size, size*.38, color, 1)
    if not far: disc(mesh, 'light-pool', x+inward[0], y+inward[1], pave+.002, pool_r, lit(pool), 1)

def digit(mesh, d, x, y, z, h=7.0, w=2.8, t=.75):
    """Seven-segment runway numerals: tall along x, read from the threshold."""
    segs = {'0':'abcdef','1':'bc','2':'abged','3':'abgcd','4':'fgbc','5':'afgcd',
            '6':'afgedc','7':'abc','8':'abcdefg','9':'abfgcd'}[d]
    geo = {'a':(h-t/2,0,t,w),'g':(h/2,0,t,w),'d':(t/2,0,t,w),
           'f':(h*.75,w/2-t/2,h/2,t),'b':(h*.75,-(w/2-t/2),h/2,t),
           'e':(h*.25,w/2-t/2,h/2,t),'c':(h*.25,-(w/2-t/2),h/2,t)}
    for k in segs:
        dx, dy, l, ww = geo[k]; mesh.box('runway-number', x+dx, y+dy, z, l, ww, .015, 'white')

def mast(mesh, x, y, h, pools, far, pave='deck', z=.08):
    cyl(mesh, 'light-mast', (x,y,0), (x,y,h), .22, 'metal', 6, .14)
    mesh.box('mast-head', x, y, h, 1.0, 2.6, .35, 'metal')
    for dy in (-.8,0,.8): mesh.box('floodlight', x+.3, y+dy, h-.22, .5, .55, .22, 'lamp', 1)
    if not far:
        for px, py, pr in pools: disc(mesh, 'light-pool', px, py, z+.002, pr, lit(pave), 1, 14)

def pavement(mesh, name, x0, x1, y0, y1, color, joints=None, z=0, h=.08):
    mesh.box(name, (x0+x1)/2, (y0+y1)/2, z, x1-x0, y1-y0, h, color)
    if joints:
        k = math.ceil(x0/joints)*joints
        while k < x1-.01:
            if k > x0+.01: mesh.box('slab-joint', k, (y0+y1)/2, z+h+.004, .14, y1-y0-.2, .006, 'joint')
            k += joints
        k = math.ceil(y0/joints)*joints
        while k < y1-.01:
            if k > y0+.01: mesh.box('slab-joint', (x0+x1)/2, k, z+h+.004, x1-x0-.2, .14, .006, 'joint')
            k += joints

def runway_tile(mesh, far, end=False):
    mesh.box('sealed-pavement', 0, 0, 0, 60, 30, .08, 'asphalt')
    for y in (-13.6, 13.6): mesh.box('edge-line', 0, y, .09, 60, .9, .015, 'white')
    if end:
        for y in (-11.4,-9.0,-6.6,-4.2,4.2,6.6,9.0,11.4): mesh.box('threshold', -21, y, .09, 12, 1.5, .015, 'white')
        digit(mesh, '1', -11, 2.4, .09); digit(mesh, '0', -11, -2.4, .09)
        for y in (-7.5, 7.5): mesh.box('aiming-point', 17, y, .09, 14, 4.2, .015, 'white')
        mesh.box('centreline', 2.5, 0, .09, 5, .9, .015, 'white')
        for i in range(10):
            lamp(mesh, 'threshold-light', -29.5, -12.6+i*2.8, 'lampgreen', 'asphalt', 2.2, far=far or i % 3 != 0, size=.8, inward=(1.8,0))
    else:
        for x in (-20, 0, 20): mesh.box('centreline', x, 0, .09, 12, .9, .015, 'white')
        if not far:
            for x in (-18, 18):
                for y in (-9, 9): mesh.box('touchdown', x, y, .09, 9, 1.4, .015, 'white')
    for x in (-22.5,-7.5,7.5,22.5):
        for y in (-14.5, 14.5): lamp(mesh, 'edge-light', x, y, 'lamp', 'asphalt', 2.6, far=far, inward=(0, -math.copysign(2.1, y)))
    for x in range(-25, 30, 10): mesh.box('centreline-light', x, 0, .09, 1.1 if far else .7, 1.1 if far else .7, .03, 'lamp', 1)

def taxi_tile(mesh, far, length=30):
    mesh.box('sealed-pavement', 0, 0, 0, length, 12, .08, 'taxi')
    mesh.box('yellow-centreline', 0, 0, .09, length, .36, .015, 'warm')
    for y in (-5.2, 5.2): mesh.box('yellow-edge', 0, y, .09, length, .22, .015, 'warm')
    for x in [-length/2+5+i*10 for i in range(int(length/10))] if length == 30 else [-length/2+10+i*20 for i in range(int(length/20))]:
        for y in (-5.65, 5.65): lamp(mesh, 'blue-edge-light', x, y, 'lampblue', 'taxi', 1.6, far=far, size=.7, inward=(0, -math.copysign(1.3, y)))

def vehicle_wheels(mesh, xs, w, r, far):
    for x in xs:
        for side in (-1,1): wheel(mesh, x, side*(w/2-.16), r, .30, far)

def part(mesh, kind, far):
    if kind == 'runway':
        runway_tile(mesh, far)
        return {'thresholds':[{'position':[x,0,0],'heading':[1 if x<0 else -1,0,0],'length_m':60} for x in (-30,30)],
                'taxiway':[{'position':[0,15,0],'heading':[0,1,0]}]}
    if kind == 'runway-end':
        runway_tile(mesh, far, True)
        return {'threshold':{'position':[-30,0,0],'heading':[1,0,0],'length_m':60},'continues':[30,0,0]}
    if kind == 'taxiway':
        taxi_tile(mesh, far)
        return {'ends':[{'position':[x,0,0],'heading':[1,0,0]} for x in (-15,15)]}
    if kind == 'apron':
        pavement(mesh, 'sealed-apron', -40, 40, -40, 40, 'deck', None if far else 10)
        for y in (-24,0,24):
            mesh.box('stand-centreline', 0, y, .09, 24, .30, .015, 'warm')
            mesh.box('nose-stop', 9, y, .09, .40, 3, .015, 'warm')
        for y in (-36, 36): mesh.box('apron-edge-line', 0, y, .09, 76, .30, .015, 'red')
        for y in (-12, 12): mast(mesh, -37, y, 14, [(-27, y, 9)], far)
        return {'stands':[{'id':f'S{i+1}','nose_stop':[9,y,0],'heading':[1,0,0],'max_wingspan_m':w,'class':c}
                          for i,(y,w,c) in enumerate(zip((-24,0,24),(17,36,65),('A','C','D')))]}
    if kind == 'papi':
        mesh.box('papi-pad', 0, 3.3, 0, 2.2, 9.4, .10, 'deck')
        for i in range(4):
            y = i*2.2
            for dy in (-.3,.3): mesh.box('papi-leg', 0, y+dy, .10, .10, .10, .40, 'metal')
            mesh.box('papi-unit', 0, y, .50, 1.0, .9, .42, 'orange')
            mesh.box('PAPI-lamp', .52, y, .58, .06, .62, .26, 'lampred' if i < 2 else 'lamp', 1)
    elif kind == 'windsock':
        mesh.box('mast-footing', 0, 0, 0, .9, .9, .12, 'deck')
        cyl(mesh, 'mast', (0,0,.12), (0,0,6.2), .08, 'metal', 6)
        n = 6 if far else 10
        rings = [[(x, r*math.cos(2*math.pi*i/n), 5.75-.14*x+r*math.sin(2*math.pi*i/n)) for i in range(n)]
                 for x,r in ((.12,.45),(.9,.40),(1.7,.34),(2.5,.27),(3.3,.20))]
        loft(mesh, 'sock', rings, lambda k,i: 'white' if k in (1,3) else 'orange')
        mesh.box('sock-lamp', 0, 0, 6.2, .22, .22, .16, 'lampred', 1)
    elif kind == 'fence':
        for x in (-4,0,4):
            mesh.box('post', x, 0, 0, .10, .10, 2.5, 'steel')
            beam(mesh, 'barbed-arm', (x,0,2.45), (x,.32,2.8), .06, 'steel')
        for z in (.15,1.25,2.35): mesh.box('horizontal-rail', 0, 0, z, 8, .055, .055, 'steel')
        mesh.box('barbed-wire', 0, .32, 2.78, 8, .04, .04, 'steel')
        if not far:
            for i in range(-15,16): mesh.box('vertical-wire', i*.25, 0, .2, .028, .03, 2.15, 'metal')
    elif kind == 'tug':
        # A low pushback tractor: wide flat body, the cab at one end.
        L, W, r = 5.2, 2.4, .50
        vehicle_wheels(mesh, (-1.55, 1.55), W, r, far)
        mesh.box('chassis', 0, 0, .30, L, W-.5, .40, 'tyre')
        mesh.box('body', 0, 0, .55, L, W, .55, 'white')
        mesh.box('hazard-band', 0, 0, .55, L+.02, W+.02, .16, 'warm')
        mesh.box('engine-cover', -1.2, 0, 1.10, 2.4, W*.82, .30, 'white')
        mesh.box('cab', 1.45, 0, 1.10, 1.7, W*.80, 1.05, 'white')
        mesh.box('cab-glass', 1.45, 0, 1.55, 1.74, W*.82, .48, 'cockpit')
        mesh.box('cab-roof', 1.45, 0, 2.15, 1.8, W*.84, .08, 'white')
        mesh.box('beacon', 1.45, 0, 2.23, .22, .22, .16, 'orange', 1)
        mesh.box('tow-hitch', L/2+.25, 0, .45, .5, .22, .16, 'tyre')
    elif kind == 'baggage':
        # A small tractor and two dollies with containers.
        vehicle_wheels(mesh, (-4.3,-2.9), 1.4, .30, far)
        mesh.box('tractor-body', -3.6, 0, .30, 2.3, 1.4, .50, 'white')
        mesh.box('tractor-band', -3.6, 0, .30, 2.32, 1.42, .14, 'warm')
        mesh.box('tractor-seat', -3.9, 0, .80, .9, 1.1, .45, 'tyre')
        mesh.box('tractor-frame', -3.9, 0, 1.25, 1.0, 1.3, .08, 'white')
        for y in (-.6,.6): mesh.box('frame-post', -3.45, y, .80, .07, .07, .45, 'metal')
        for i, x in enumerate((-.6, 2.8)):
            vehicle_wheels(mesh, (x-.9, x+.9), 1.5, .24, far)
            mesh.box('dolly-deck', x, 0, .40, 2.9, 1.6, .12, 'metal')
            mesh.box('tow-bar', x-1.75, 0, .40, .7, .10, .08, 'tyre')
            mesh.box('container', x, 0, .52, 2.3, 1.5, 1.45, 'belly' if i else 'blue')
            if not far: mesh.box('container-door', x, .76, .62, 1.9, .04, 1.2, 'wall')
    elif kind == 'stairs':
        L, W = 6.4, 2.2
        vehicle_wheels(mesh, (-2.1, 1.9), W, .42, far)
        mesh.box('chassis', 0, 0, .35, L, W-.4, .35, 'tyre')
        mesh.box('driver-cab', -2.45, 0, .70, 1.4, W, 1.35, 'white')
        mesh.box('cab-glass', -2.45, 0, 1.35, 1.44, W+.02, .45, 'cockpit')
        steps = 5 if far else 10; x0, x1, z0, z1 = -1.6, 2.6, .78, 3.55
        for side in (-1,1):
            y = side*(W/2-.08)
            ring = lambda yy: [(x0,yy,z0-.1),(x1+.9,yy,z1-.4),(x1+.9,yy,z1+1.0),(x1,yy,z1+1.0),(x0,yy,z0+1.0)]
            loft(mesh, 'stair-side', [ring(y-.05), ring(y+.05)], 'blue')
        body = lambda yy: [(x0,yy,.70),(x1+.9,yy,.70),(x1+.9,yy,z1-.12),(x1,yy,z1-.12),(x0,yy,z0)]
        loft(mesh, 'stair-flight', [body(-W/2+.2), body(W/2-.2)], 'white')
        for i in range(steps):
            mesh.box('stair-tread', x0+(i+.5)*(x1-x0)/steps, 0, z0+(i+1)*(z1-z0)/steps-.12, (x1-x0)/steps+.02, W-.3, .12, 'metal')
        mesh.box('upper-landing', x1+.45, 0, z1-.12, .9, W-.3, .12, 'metal')
        for x in (x1+.85,):
            for y in (-.9,.9): cyl(mesh, 'landing-leg', (x,y,.70), (x,y,z1-.12), .06, 'metal', 6)
    elif kind == 'fuel':
        L, W = 9.0, 2.5
        vehicle_wheels(mesh, (-3.4,-2.2, 3.1), W, .50, far)
        mesh.box('chassis', 0, 0, .45, L, W-.5, .30, 'tyre')
        mesh.box('fuel-cab', 3.35, 0, .75, 2.0, W, 1.75, 'white')
        mesh.box('cab-glass', 3.75, 0, 1.55, 1.24, W+.02, .62, 'cockpit')
        mesh.box('cab-band', 3.35, 0, .75, 2.02, W+.02, .18, 'warm')
        n = 8 if far else 14
        rings = [[(x, k*1.18*math.cos(2*math.pi*i/n), 1.82+k*1.02*math.sin(2*math.pi*i/n)) for i in range(n)]
                 for x,k in ((-4.4,.72),(-4.1,1),(2.0,1),(2.25,.72))]
        loft(mesh, 'sealed-fuel-tank', rings, lambda k,i: 'red' if k == 1 and i in (n-1, n//2) else 'white')
        mesh.box('tank-cradle', -1.1, 0, .75, 6.3, W-.5, .22, 'metal')
        mesh.box('tank-walkway', -1.1, 0, 2.84, 5.4, .5, .06, 'metal')
        if not far:
            mesh.box('hose-cabinet', -4.1, 0, .75, .6, W-.3, .85, 'metal')
            mesh.box('beacon', 3.35, 0, 2.50, .22, .22, .16, 'orange', 1)
    return {'mount':'ground-z0'}

def arch_block(mesh, name, x0, x1, y0, y1, wall, rise, along, wall_color, roof_color, over=1.5, steps=8, ribs=()):
    """A hall under a shallow arched roof. `along` is the ridge's axis."""
    a0, a1, b0, b1 = (y0, y1, x0, x1) if along == 'y' else (x0, x1, y0, y1)   # extrude a, arch across b
    pt = (lambda a, b, z: (b, a, z)) if along == 'y' else (lambda a, b, z: (a, b, z))
    mid, half = (b0+b1)/2, (b1-b0)/2
    arc = lambda scale, dz: [(mid + (half+over*scale)*math.cos(math.pi*(1-i/steps)), wall + dz + rise*math.sin(math.pi*i/steps))
                             for i in range(steps+1)]
    body = [(b0, 0), (b0, wall)] + [(b, z) for b, z in arc(0, -.05)][1:-1] + [(b1, wall), (b1, 0)]
    loft(mesh, name, [[pt(a, b, z) for b, z in body] for a in (a0, a1)], wall_color)
    top = arc(1, .45); under = arc(1, .0)[::-1]
    loft(mesh, name+'-roof', [[pt(a, b, z) for b, z in top+under] for a in (a0-over, a1+over)], roof_color)
    for end in (a0-over-.3, a1+over-.3):          # white barge boards close the roof's ends
        loft(mesh, name+'-fascia', [[pt(a, b, z) for b, z in arc(1.02, .62)+arc(1.02, -.12)[::-1]] for a in (end, end+.6)], 'white')
    for rib in ribs:
        loft(mesh, name+'-rib', [[pt(a, b, z) for b, z in arc(1, .68)+arc(1, .40)[::-1]] for a in (rib-.45, rib+.45)], 'white')

BRIDGES = (-66, -22, 22, 66)
def jetbridge(mesh, y, end, far, x0=14.0):
    """From the concourse to `end` (x, y, sill): rotunda, tunnel, cab, drive legs."""
    rot = (x0+3.2, y)
    cyl(mesh, 'rotunda-column', (rot[0], rot[1], 0), (rot[0], rot[1], 3.5), .55, 'metal', 8)
    cyl(mesh, 'rotunda', (rot[0], rot[1], 3.5), (rot[0], rot[1], 6.6), 2.3, 'white', 8 if far else 12)
    cyl(mesh, 'rotunda-roof', (rot[0], rot[1], 6.6), (rot[0], rot[1], 6.8), 2.5, 'roof', 8 if far else 12)
    mesh.box('bridge-link', x0+1.0, y, 3.6, 2.4, 2.6, 2.7, 'white')
    a = (rot[0], rot[1], 5.0); b = (end[0], end[1], end[2]+1.25)
    bar(mesh, 'jetbridge', a, b, 2.6, 2.6, 'white')
    d = mod.unit(mod.sub(b, a)); side = mod.unit(mod.cross((0,0,1), d))
    if not far:
        for s in (-1,1):
            o = mod.mul(side, s*1.31)
            bar(mesh, 'bridge-glazing', mod.add(mod.add(a, mod.mul(d, 2.6)), o), mod.add(mod.add(b, mod.mul(d, -2.4)), o), .06, 1.0, 'pane', glow=1)
    bar(mesh, 'bridge-roof', mod.add(a, (0,0,1.36)), mod.add(b, (0,0,1.36)), 2.8, .14, 'roof')
    cab = mod.add(b, mod.mul(d, -1.0))
    cyl(mesh, 'bridge-cab', (cab[0], cab[1], end[2]-.15), (cab[0], cab[1], end[2]+2.75), 1.9, 'white', 8 if far else 10)
    cyl(mesh, 'cab-roof', (cab[0], cab[1], end[2]+2.75), (cab[0], cab[1], end[2]+2.95), 2.05, 'roof', 8 if far else 10)
    leg = mod.add(b, mod.mul(d, -4.2))
    for s in (-1,1):
        p = mod.add(leg, mod.mul(side, s*1.6))
        cyl(mesh, 'bridge-legs', (p[0], p[1], .45), (p[0], p[1], leg[2]-1.2), .16, 'metal', 6)
        wheel(mesh, p[0], p[1], .45, .32, far)
    bar(mesh, 'bridge-axle', (leg[0]-side[0]*1.8, leg[1]-side[1]*1.8, leg[2]-1.25), (leg[0]+side[0]*1.8, leg[1]+side[1]*1.8, leg[2]-1.25), .3, .3, 'metal')

def tower(mesh, x, y, h, far, r=3.0):
    n = 8
    oct_ring = lambda z, rad: [(x+rad*math.cos(2*math.pi*(i+.5)/n), y+rad*math.sin(2*math.pi*(i+.5)/n), z) for i in range(n)]
    loft(mesh, 'tower-shaft', [oct_ring(0, r), oct_ring(h, r*.82)], 'wall')
    loft(mesh, 'tower-collar', [oct_ring(h, r*1.45), oct_ring(h+.6, r*1.55)], 'base')
    loft(mesh, 'tower-cab', [oct_ring(h+.6, r*1.25), oct_ring(h+3.8, r*1.62)], ('pane', 1))
    loft(mesh, 'tower-roof', [oct_ring(h+3.8, r*1.75), oct_ring(h+4.3, r*1.50)], 'roof')
    cyl(mesh, 'tower-antenna', (x, y, h+4.3), (x, y, h+8.0), .12, 'metal', 6)
    mesh.box('tower-beacon', x, y, h+8.0, .3, .3, .22, 'lampred', 1)
    if not far:
        for i in range(3):
            loft(mesh, 'tower-band', [oct_ring(h*(.25+.22*i), r*(.955-.04*i)+.04), oct_ring(h*(.25+.22*i)+.5, r*(.95-.04*i)+.04)], 'base')

def airport(mesh, kind, far):
    if kind == 'city':
        # Airside is +x. Everything stands on one plate: forecourt road, hall,
        # concourse, tower and hangar are a single place, not four objects.
        pavement(mesh, 'ground-plate', -104, 14, -92, 130, 'deck')
        mesh.box('car-park', -88, 0, .08, 24, 150, .02, 'asphalt')
        mesh.box('verge', -72.5, 0, .08, 5, 150, .10, 'grass')
        for i, y in enumerate(range(-70, 71, 5)):
            for x in (-94.5, -81.5):
                if not far and i % 2 == 0: mesh.box('parking-bay-line', x, y, .10, 5, .15, .012, 'white')
                if (i*7+int(x)) % 3 == 0:
                    mesh.box('parked-car', x, y+2.5, .10, 4.2, 1.8, .9, ('wall','red','blue','belly','navy')[(i+int(x)) % 5])
                    if not far: mesh.box('parked-car-roof', x-.2, y+2.5, 1.0, 2.2, 1.6, .5, 'cockpit')
        mesh.box('forecourt-road', -62, 0, .08, 14, 176, .02, 'asphalt')
        for y in range(-80, 81, 16): mesh.box('road-dash', -62, y, .10, .25, 6, .012, 'white')
        mesh.box('kerb-island', -51.5, 0, .08, 3, 150, .14, 'wall')
        arch_block(mesh, 'main-hall', -40, 0, -45, 45, 9.5, 5.2, 'y', 'white', 'roof', 2.0, 6 if far else 10, range(-36, 37, 12))
        mesh.box('ridge-skylight', -20, 0, 14.95, 6, 84, .35, 'pane', 1)
        mesh.box('landside-canopy', -45, 0, 5.4, 10, 84, .30, 'roof')
        for y in range(-36, 37, 12): cyl(mesh, 'canopy-column', (-49, y, 0), (-49, y, 5.4), .28, 'white', 6)
        bays = 6 if far else 12
        for i in range(bays):
            y = -42 + (i+.5)*84/bays
            mesh.box('facade-window', -40.06, y, 1.0, .14, 84/bays-.9, 7.6, 'pane', 1)
        mesh.box('facade-sill', -40.1, 0, .0, .22, 86, 1.0, 'base')
        for y in (-45.06, 45.06): mesh.box('gable-glazing', -20, y, 2.0, 30, .14, 6.5, 'pane', 1)
        mesh.box('concourse', 7, 0, 0, 14, 176, 7.6, 'white')
        mesh.box('concourse-base', 7, 0, 0, 14.12, 176.12, 3.0, 'base')
        mesh.box('concourse-roof', 7, 0, 7.6, 14.6, 176.6, .35, 'wall')
        for x in (.0, 14.0): mesh.box('concourse-fascia', x, 0, 7.6, .7, 176.8, .7, 'roof')
        mesh.box('roof-monitor', 7, 0, 7.95, 4, 150, .9, 'pane', 1)
        for y in (-70, 70): mesh.box('roof-plant', 7, y, 7.95, 6, 9, 1.6, 'metal')
        mesh.box('airside-glazing', 14.06, 0, 3.5, .14, 172, 3.0, 'pane', 1)
        if not far:
            for y in range(-80, 81, 10): mesh.box('facade-pier', 14.12, y, 3.0, .22, .5, 4.6, 'white')
        mesh.box('tower-podium', -30, -72, 0, 18, 14, 7, 'wall')
        mesh.box('podium-band', -30, -72, 3.2, 18.1, 14.1, 1.2, 'pane', 1)
        tower(mesh, -30, -72, 27, far)
        arch_block(mesh, 'hangar', -38, 4, 92, 126, 11, 4.4, 'x', 'belly', 'metal', 1.0, 6 if far else 10, (-28, -17, -6))
        for i, y in enumerate((98.6, 109, 119.4)):
            mesh.box('hangar-door', 4.08, y, 0, .18, 9.8, 9.2, 'metal')
            mesh.box('hangar-door-light', 4.12, y, 9.4, .2, 9.8, 1.0, 'pane', 1)
        for y in BRIDGES: jetbridge(mesh, y, (37.0, y, 3.45), far)
        return {'jetbridges':[{'id':f'J{i+1}','pivot':[17.2,y,3.75],
                               'joint':{'kind':'translation','axis':[1,0,0],'limit_m':[0,7]},
                               'end':[37.0,y,3.45]} for i,y in enumerate(BRIDGES)],
                'boarding':'jetbridge','airside_face_x':14.0}
    # The island terminal: one low white block with a red band, a small
    # control cab on its roof and porches on both sides.
    pavement(mesh, 'ground-plate', -30, 6, -20, 20, 'deck')
    mesh.box('car-park', -23, 0, .08, 12, 34, .02, 'asphalt')
    if not far:
        for y in range(-15, 16, 5): mesh.box('parking-bay-line', -23, y, .10, 5, .15, .012, 'white')
    mesh.box('main-building', -6.5, 0, 0, 13, 25, 3.7, 'white')
    mesh.box('roof-parapet', -6.5, 0, 3.7, 13.5, 25.5, .35, 'red')
    mesh.box('roof-deck', -6.5, 0, 3.7, 12.7, 24.7, .36, 'wall')
    mesh.box('red-band', -6.5, 0, 3.05, 13.56, 25.56, .40, 'red')
    for y in (2, 6): mesh.box('roof-unit', -9, y, 4.06, 1.6, 1.2, .9, 'metal')
    cyl(mesh, 'water-tank', (-3.5, 9.5, 4.06), (-3.5, 9.5, 5.7), .9, 'metal', 8)
    mesh.box('plinth', -6.5, 0, 0, 13.1, 25.1, .5, 'base')
    for side, x in ((1, .04), (-1, -13.04)):
        for i in range(5):
            y = -10 + i*5
            if side > 0 and i == 3: mesh.box('walk-boarding-door', x, y, .1, .12, 2.2, 2.4, 'cockpit')
            elif side < 0 and i == 2: mesh.box('entrance', x, y, .1, .12, 3.0, 2.5, 'cockpit')
            else: mesh.box('facade-window', x, y, 1.15, .12, 3.2, 1.5, 'pane', 1)
    mesh.box('airside-porch', 2.2, 2.5, 2.85, 4.4, 14, .18, 'red')
    for y in (-3.5, 2.5, 8.5): cyl(mesh, 'porch-post', (4.0, y, 0), (4.0, y, 2.85), .10, 'white', 6)
    mesh.box('entrance-canopy', -15.0, 0, 2.85, 4.0, 8, .18, 'red')
    for y in (-3.4, 3.4): cyl(mesh, 'porch-post', (-16.6, y, 0), (-16.6, y, 2.85), .10, 'white', 6)
    mesh.box('tower-stub', -8, -8.5, 4.05, 5, 5, 2.4, 'white')
    mesh.box('tower-band', -8, -8.5, 6.0, 5.06, 5.06, .30, 'red')
    n = 8
    ring = lambda z, r: [(-8+r*math.cos(2*math.pi*(i+.5)/n), -8.5+r*math.sin(2*math.pi*(i+.5)/n), z) for i in range(n)]
    loft(mesh, 'tower-cab', [ring(6.45, 2.3), ring(8.3, 2.9)], ('pane', 1))
    loft(mesh, 'tower-roof', [ring(8.3, 3.2), ring(8.65, 2.7)], 'red')
    cyl(mesh, 'tower-antenna', (-8, -8.5, 8.65), (-8, -8.5, 11.0), .07, 'metal', 6)
    mesh.box('boarding-path', 5.0, 2.5, .08, 2.0, 1.8, .02, 'warm')
    return {'jetbridges':[],'boarding':'walk','airside_face_x':0.0}

def place(mesh, sub, prefix, x=0, y=0, deg=0):
    c, s = {0:(1,0), 90:(0,1), 180:(-1,0), 270:(0,-1)}[deg % 360]
    start = len(mesh.t)
    mesh.t += [([(x+c*p[0]-s*p[1], y+s*p[0]+c*p[1], p[2]) for p in tri], col, g) for tri,col,g in sub.t]
    mesh.solids += [dict(q, name=prefix+q['name'], start=q['start']+start) for q in sub.solids]

def sub(fn, *args):
    m = mod.Mesh(); meta = fn(m, *args); return m, meta

def assembly(mesh, kind, far):
    stands = []
    if kind == 'city-scene':
        # Terminal, apron, parallel taxiway and a stretch of runway in one piece.
        mesh.box('grass', 46, 10, 0, 300, 240, .04, 'grass')
        airport(mesh, 'city', far)
        pavement(mesh, 'apron-sealed-apron', 14, 118, -110, 130, 'deck', None if far else 12)
        t, _ = sub(lambda m: taxi_tile(m, True, 240)); place(mesh, t, 'taxiway-', 127, 10, 90)   # far tiles: the scene's budget
        for i, end in enumerate((True, False, False, False)):
            r, _ = sub(lambda m: runway_tile(m, True, end)); place(mesh, r, 'runway-', 168, -80+i*60, 90)
        for y in (-22, 100): mesh.box('taxiway-link', 143, y, 0, 20, 12, .08, 'taxi'); mesh.box('link-centreline', 143, y, .09, 20, .36, .015, 'warm')
        for i, y in enumerate((-88, -44, 0, 44, 88)): mast(mesh, 17, y, 18, [(28, y, 9)], far)
        mesh.box('apron-edge-line', 116, 10, .09, .3, 236, .015, 'red')
        parked = (('narrowjet', None, -22, 1), ('narrowjet', 2, 22, 2), ('regional70', None, None, None))
        for i, (plane, paint, by, bridge) in enumerate(parked):
            a, meta = sub(aircraft, plane, far or i > 0, paint); door = meta['door']['position']   # one near aircraft keeps the scene in budget
            if by is None: ox, oy = 78.0, 84.0
            else: ox, oy = 37.0+door[0], by+door[1]+1.9        # the cab stands off the door
            place(mesh, a, 'plane-', ox, oy, 180)
            nose = ox-SPECS[plane][0]/2
            mesh.box('stand-centreline', nose+20, oy, .09, 40, .30, .015, 'warm')
            mesh.box('nose-stop', nose+meta['nose_gear'][0]*0+SPECS[plane][0]/2-meta['nose_gear'][0], oy, .09, .4, 3, .015, 'warm')
            stands.append({'id':f'A{i+1}','nose_stop':[nose,oy,0],'heading':[-1,0,0],
                           'max_wingspan_m':SPECS[plane][1],'class':'C' if plane == 'narrowjet' else 'B',
                           'door':[ox-door[0], oy-door[1], door[2]],
                           'jetbridge_end':[37.0, by, door[2]] if by is not None else None})
        # Bridges J2 and J3 are posed onto the two doors; J1 and J4 stay parked.
        for prefix, off in (('tug', (33.5, -22+2.0+1.9, 0)), ('fuel', (52, 4, 90)), ('baggage', (64, -42, 0)),
                            ('stairs', (78-9.0+3.2, 84-5.6, 90))):
            v, _ = sub(part, prefix, True); place(mesh, v, prefix+'-', *off)
        return {'stands':stands,'scene_only':True}
    mesh.box('grass', 40, 0, 0, 150, 200, .04, 'grass')
    airport(mesh, 'island', far)
    pavement(mesh, 'apron-sealed-apron', 6, 50, -28, 28, 'deck', None if far else 10)
    t, _ = sub(lambda m: taxi_tile(m, far)); place(mesh, t, 'taxiway-', 65, 0, 0)
    for i, (end, deg) in enumerate(((True, 90), (False, 90), (True, 270))):
        r, _ = sub(lambda m: runway_tile(m, far, end)); place(mesh, r, 'runway-', 95, -60+i*60, deg)
    a, meta = sub(aircraft, 'commuter19', far, None); place(mesh, a, 'plane-', 26, -4, 90)
    mesh.box('stand-centreline', 26, -2, .09, .30, 30, .015, 'warm')
    stands.append({'id':'A1','nose_stop':[26,-4+SPECS['commuter19'][0]/2,0],'heading':[0,1,0],
                   'max_wingspan_m':SPECS['commuter19'][1],'class':'A'})
    v, _ = sub(part, 'baggage', far); place(mesh, v, 'baggage-', 14, -16, 0)
    v, _ = sub(part, 'windsock', far); place(mesh, v, 'windsock-', 76, 40, 0)
    v, _ = sub(part, 'papi', far); place(mesh, v, 'papi-', 76, -70, 90)
    for i in range(5):
        v, _ = sub(part, 'fence', far); place(mesh, v, 'fence-', -29.8, -16+i*8, 90)
    mast(mesh, 8, -22, 10, [(16, -18, 9)], far); mast(mesh, 8, 22, 10, [(16, 18, 9)], far)
    return {'stands':stands,'scene_only':True}

def build(kind, far):
    m = mod.Mesh()
    meta = (aircraft(m, kind, far) if kind in SPECS else airport(m, kind, far) if kind in ('city','island')
            else assembly(m, kind, far) if kind.endswith('-scene') else part(m, kind, far))
    return m, meta

def main():
    ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);args=ap.parse_args()
    root=args.output.resolve();assert HERE.parents[2] not in root.parents
    root.mkdir(parents=True,exist_ok=True)
    models=[]
    for kind in list(SPECS)+['city','island']+list(PARTS)+['city-scene','island-scene']:
        for far in (False,True):
            m,meta=build(kind,far)
            name=NAMES.get(kind,kind);id=kind+('-lod' if far else '-near')
            models.append(mod.write_model(root,id,name+('・遠景' if far else '・近景'),m,meta))
    (root/'manifest.json').write_text(json.dumps({'schema_version':1,'directions':['top','bottom','left','right','front','back','isometric'], 'models':models},ensure_ascii=False,indent=2)+'\n')
    print(len(models),'models',max(m['triangles'] for m in models),'max triangles')
    for m in models: print(' ',m['id'],m['triangles'])

if __name__=='__main__':main()
