#!/usr/bin/env python3
"""Fukuoka's spherical gas holders and water towers from the owner's
earlier version (SwiftRailMac's ガスタンク and 給水タンク), as registered
landmarks (decision 895) where OpenStreetMap maps them (decision 924).

    python3 -I tools/old-models/old_tanks.py \
        OLD/item_a14610e919ffb965d418ca71.glb OLD/item_2cedf43508c08f24c37b0c88.glb \
        Sources/GamePresentation/Map3DFukuokaTanksMesh.swift

What it does, and only this:
- reads each old model, leaves out its ground plate (the triangles flat
  on the ground) and gives every other triangle one of two colours by
  where it is, not by its texture (the texture is one pale green over
  the sphere and its legs alike): ``tank`` (the gas holder's sphere, the
  water tower's tank above its catwalk) or ``stand`` (legs, braces,
  catwalk, ladder);
- draws it at each size in ``SIZES`` (the scale of the old model), its
  footprint's middle at the origin, its foot at 0, glTF's axes (the
  landmark tool turns them onto +x east, +y north, +z up);
- builds each far model itself, coarser than the near one (the registry
  wants at most half its triangles): the sphere or tank and four legs;
- writes each model as a GLB in a scratch folder and encodes it with
  `tools/landmarks/glb_to_swift.py`'s ``encode``, so the Swift side reads
  it as every other registered landmark.

Standard library only.
"""
import json
import math
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'landmarks'))
import glb_to_swift as landmarks  # noqa: E402

MATERIALS = ['tank', 'stand']

# Each model's name: the old file's argument index, and its scale.
SIZES = {
    # Saibu Gas's large spheres (PLATEAU: 36.9 and 37.4 m high, OSM
    # outlines 34.5 to 37.4 m across): the old model at its own size,
    # 35.8 m high, the sphere 34 m across.
    'fukuoka-gas-holder-large': (0, 1.0),
    # The smaller ones beside them (outlines 15 to 27 m across).
    'fukuoka-gas-holder': (0, 0.6),
    # Water towers (outlines 5 to 8 m across): 21 m high, the tank 8 m.
    'fukuoka-water-tower': (1, 0.7),
    # 原団地給水塔, 30 m high (OSM `height`): the old model's own size.
    'fukuoka-water-tower-tall': (1, 1.0),
}


def old_triangles(path):
    """The old model's triangles in its own metres (glTF axes), each with
    its material index, its ground plate left out."""
    gltf, blob = landmarks.read_glb(path)
    for node in gltf['nodes']:
        assert not any(k in node for k in ('matrix', 'rotation', 'scale', 'translation')), node
    out = []
    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            pos = landmarks.accessor(gltf, blob, prim['attributes']['POSITION'])
            idx = landmarks.accessor(gltf, blob, prim['indices'])
            for k in range(0, len(idx), 3):
                pts = [tuple(pos[i]) for i in idx[k:k + 3]]
                if max(p[1] for p in pts) < 0.05:
                    continue  # the plate (and the grass it is drawn with)
                out.append((pts, prim['material']))
    return out


def components(tris):
    """The triangles in groups that share corners (welded at 2 cm): a
    leg, a brace, the sphere, the catwalk."""
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def key(p):
        return tuple(round(c * 50) for c in p)
    for pts, _ in tris:
        for p in pts[1:]:
            parent[find(key(p))] = find(key(pts[0]))
    groups = {}
    for tri in tris:
        groups.setdefault(find(key(tri[0][0])), []).append(tri)
    return sorted(groups.values(), key=len, reverse=True)


def radius(tris):
    return [math.hypot(p[0], p[2]) for pts, _ in tris for p in pts]


def gas_holder(path):
    """The sphere is the largest group (``tank``); the catwalk round its
    equator, the fittings on top, the legs and braces ``stand``. The
    pieces standing out beyond the catwalk (20 to 21 m from the middle,
    on the plate) are left out with it. The far model keeps the catwalk
    and the fittings, and draws the sphere 8 by 5 on four legs."""
    groups = [g for g in components(old_triangles(path)) if min(radius(g)) < 19]
    near = [(pts, 'tank' if i == 0 else 'stand') for i, g in enumerate(groups) for pts, _ in g]
    sphere = groups[0]
    ys = [p[1] for pts, _ in sphere for p in pts]
    low, high, wide = min(ys), max(ys), max(radius(sphere))
    far = [(pts, 'stand') for g in groups[1:] if min(p[1] for pts, _ in g for p in pts) > 15 for pts, _ in g]
    segs, rings = 8, 5
    middle, tall = (low + high) / 2, (high - low) / 2
    ring = [[(wide * math.sin(math.pi * j / rings) * math.cos(2 * math.pi * (i + 0.5) / segs), middle - tall * math.cos(math.pi * j / rings),
              wide * math.sin(math.pi * j / rings) * math.sin(2 * math.pi * (i + 0.5) / segs)) for i in range(segs)] for j in range(rings + 1)]
    for j in range(rings):
        for i in range(segs):
            a, b = ring[j][i], ring[j][(i + 1) % segs]
            c, d = ring[j + 1][(i + 1) % segs], ring[j + 1][i]
            if j > 0:
                far.append(([a, c, b], 'tank'))
            if j < rings - 1:
                far.append(([a, d, c], 'tank'))
    legs = [g for g in groups if min(p[1] for pts, _ in g for p in pts) < 0.1]
    feet = sum(radius(legs[0])) / len(radius(legs[0])) / math.sqrt(2)
    for x, z in ((feet, feet), (-feet, feet), (-feet, -feet), (feet, -feet)):
        far += box(x, z, 0.4, 0.0, middle)
    return near, far


# A brace's width in the old model's metres (its texture draws them 4 to 6
# pixels of a 6.5 m bay's 91).
BRACE = 0.5


def strip(a, b, side):
    """A flat strip from `a` to `b`, reaching `side` to each side of
    that line, seen from both sides (the old panels were)."""
    p0, p1 = [a[k] - side[k] for k in range(3)], [a[k] + side[k] for k in range(3)]
    p2, p3 = [b[k] + side[k] for k in range(3)], [b[k] - side[k] for k in range(3)]
    return [([p0, p1, p2], 'stand'), ([p0, p2, p3], 'stand'), ([p0, p2, p1], 'stand'), ([p0, p3, p2], 'stand')]


def brace(a, b, normal):
    """A brace from `a` to `b` in the bay whose plane `normal` stands
    on: one strip in the plane, cut level at its ends, and one across
    it, so the brace is as wide from along the bay as from in front (a
    flat strip seen edge-on is a hair)."""
    along = [b[k] - a[k] for k in range(3)]
    if abs(along[1]) < 1e-6:
        side = (0.0, BRACE / 2, 0.0)
    else:
        run = math.hypot(along[0], along[2])
        grow = BRACE / 2 * math.sqrt(run * run + along[1] * along[1]) / abs(along[1])
        side = (along[0] / run * grow, 0.0, along[2] / run * grow)
    return strip(a, b, side) + strip(a, b, [n * BRACE / 2 for n in normal])


def braces(panel):
    """A bay between two legs: the old model draws it as a flat panel
    textured with cross braces on black (see-through in spirit); here
    each tier of the panel is its two diagonals and the beam on top of
    it, and nothing in between."""
    levels = {}
    for pts, _ in panel:
        for p in pts:
            levels.setdefault(round(p[1], 1), set()).add(tuple(round(c, 2) for c in p))
    rows = [sorted(levels[y]) for y in sorted(levels)]
    assert all(len(r) == 2 for r in rows), rows
    # The same end of the bay first at every level.
    for r in rows[1:]:
        if math.dist(r[0], rows[0][0]) > math.dist(r[1], rows[0][0]):
            r.reverse()
    out = []
    for low, high in zip(rows, rows[1:]):
        u, v = [low[1][k] - low[0][k] for k in range(3)], [high[0][k] - low[0][k] for k in range(3)]
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        size = math.sqrt(sum(c * c for c in n))
        normal = [c / size for c in n]
        out += brace(low[0], high[1], normal) + brace(low[1], high[0], normal) + brace(high[0], high[1], normal)
    return out


def leg(group):
    """A leg as four plain sides from its foot to its top (the far
    model's)."""
    pts = [p for t, _ in group for p in t]
    low, high = min(p[1] for p in pts), max(p[1] for p in pts)
    ends = []
    for y in (low, high):
        ring = [p for p in pts if abs(p[1] - y) < 0.05]
        x0, x1 = min(p[0] for p in ring), max(p[0] for p in ring)
        z0, z1 = min(p[2] for p in ring), max(p[2] for p in ring)
        cx, cz, h = (x0 + x1) / 2, (z0 + z1) / 2, 0.35
        ends.append([(cx - h, y, cz - h), (cx + h, y, cz - h), (cx + h, y, cz + h), (cx - h, y, cz + h)])
    out = []
    for i in range(4):
        a, b = ends[0][i], ends[0][(i + 1) % 4]
        c, d = ends[1][(i + 1) % 4], ends[1][i]
        out += [([a, c, b], 'stand'), ([a, d, c], 'stand')]
    return out


def water_tower(path):
    """The tank (material 1 above the catwalk, 17.5 m) is ``tank``, the
    rest ``stand``: legs, catwalk, ladder, and the bays between the legs
    as open cross braces (``braces``; decision 924's later note: the old
    model's textured panels, once given one colour, were a pale skirt
    hanging half a metre off the ground). The far model keeps the tank
    and the catwalk and draws each leg as four sides; no braces, ladder,
    middle pipe or fittings."""
    tris = old_triangles(path)

    def colour(pts, material):
        return 'tank' if material == 1 and sum(p[1] for p in pts) / 3 >= 17.5 else 'stand'
    near, far = [], []
    for g in components(tris):
        materials = {m for _, m in g}
        low = min(p[1] for pts, _ in g for p in pts)
        if materials == {0} and len(g) == 8 and 0.1 < low < 1:
            near += braces(g)  # a bay's panel
            continue
        near += [(pts, colour(pts, m)) for pts, m in g]
        high = max(p[1] for pts, _ in g for p in pts)
        if low < 0.05 and len(g) == 32 and high < 18:
            far += leg(g)
        elif len(materials) == 1 and len(g) >= 8 and low > 15:
            far += [(pts, colour(pts, m)) for pts, m in g]
    return near, far


def box(x, z, half, y0, y1):
    """A leg's four sides (no ends), as triangles."""
    c = [(x - half, z - half), (x + half, z - half), (x + half, z + half), (x - half, z + half)]
    out = []
    for i in range(4):
        (ax, az), (bx, bz) = c[i], c[(i + 1) % 4]
        a, b, cc, d = (ax, y0, az), (bx, y0, bz), (bx, y1, bz), (ax, y1, az)
        out += [([a, b, cc], 'stand'), ([a, cc, d], 'stand')]
    return out


def write_glb(path, triangles, scale):
    """`triangles` (three points, a material name) as a GLB, one
    primitive a material, `scale` times their size."""
    blob = bytearray()
    views, accessors, prims = [], [], []
    for m, name in enumerate(MATERIALS):
        tris = [pts for pts, c in triangles if c == name]
        if not tris:
            continue
        pos = [tuple(v * scale for v in p) for pts in tris for p in pts]
        start = len(blob)
        for p in pos:
            blob += struct.pack('<3f', *p)
        views.append({'buffer': 0, 'byteOffset': start, 'byteLength': len(blob) - start})
        accessors.append({'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(pos), 'type': 'VEC3',
                          'min': [min(p[k] for p in pos) for k in range(3)], 'max': [max(p[k] for p in pos) for k in range(3)]})
        start = len(blob)
        for i in range(len(pos)):
            blob += struct.pack('<I', i)
        views.append({'buffer': 0, 'byteOffset': start, 'byteLength': len(blob) - start})
        accessors.append({'bufferView': len(views) - 1, 'componentType': 5125, 'count': len(pos), 'type': 'SCALAR'})
        prims.append({'attributes': {'POSITION': len(accessors) - 2}, 'indices': len(accessors) - 1, 'material': m})
    gltf = {'asset': {'version': '2.0'}, 'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0}],
            'meshes': [{'primitives': prims}], 'materials': [{'name': n} for n in MATERIALS],
            'buffers': [{'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    text = json.dumps(gltf).encode()
    text += b' ' * (-len(text) % 4)
    blob += b'\0' * (-len(blob) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(blob)))
        f.write(struct.pack('<II', len(text), 0x4E4F534A) + text)
        f.write(struct.pack('<II', len(blob), 0x004E4942) + blob)


def main(gas_path, tower_path, swift):
    shapes = [gas_holder(gas_path), water_tower(tower_path)]
    models = []
    with tempfile.TemporaryDirectory() as scratch:
        for name, (which, scale) in SIZES.items():
            near, far = shapes[which]
            for key, tris in ((name, near), (name + '-far', far)):
                path = os.path.join(scratch, key + '.glb')
                write_glb(path, tris, scale)
                data, v, t, low, high = landmarks.encode(path, MATERIALS, centre=True)
                print(f'{key}: {t} triangles, {[round(h - l, 2) for l, h in zip(low, high)]} m')
                models.append((key, data, v, t))
    source = ("the earlier version's ガスタンク (item_a14610e919ffb965d418ca71) and 給水タンク (item_2cedf43508c08f24c37b0c88) "
              "by tools/old-models/old_tanks.py")
    open(swift, 'w').write(landmarks.mesh_file('Map3DFukuokaTanks', MATERIALS, source, models, tool='tools/landmarks/glb_to_swift.py'))


if __name__ == '__main__':
    main(*sys.argv[1:4])
