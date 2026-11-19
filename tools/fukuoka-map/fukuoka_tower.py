#!/usr/bin/env python3
"""Fukuoka Tower on Fukuoka's 3D map (FUKUOKA-LANDMARKS): the owner's own
model from the earlier version (SwiftRailMac `item_5c80a900…`, kept in
`a91453/railway-assets-private-2`,
`game-art-previews/docs/art/fukuoka-landmarks-2026-11/old-version/fukuoka-tower.glb`,
sha256 f15957a0…), written into the game's Swift source in
`tools/hk-landmarks/glb_to_swift.py`'s encoding.

    python3 -I tools/fukuoka-map/fukuoka_tower.py OLD/fukuoka-tower.glb \
        Sources/GamePresentation/Map3DOverseasLandmarkMeshes.swift

What it changes, and only this (decision 854's later note FUKUOKA-LANDMARKS):
- the 40 m square of plaza under the tower is left out (the map draws
  its own ground and roads);
- the old textures become the landmarks' palette colours (one material,
  one colour, `MATERIALS` below);
- the body stays as it was (128 m, as tall as the real one's glass up to
  its slope); the mast above 128 m is stretched to the real 234 m (the
  earlier version's stopped at 172 m);
- it is turned 8.0° anticlockwise so its triangle lies as OpenStreetMap's
  outline of the real tower (way of Q847033), and its footprint's middle
  put at the origin (the tool prints where that middle stands);
- a far model: the outline of the body (and the spine on its back) and
  of the mast as plain prisms.
"""
import base64
import math
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'hk-landmarks'))
from glb_to_swift import MATERIALS, accessor, read_glb  # noqa: E402

SHA256 = 'f15957a0bb4bd04f84bba2e675791983d845a1512f3406b4410733b82014b1d3'
# The old materials (by index) onto the landmarks' materials; None: left out.
PAINT = {0: None, 1: 'glassBlueGrey', 2: 'steelGrey', 3: 'mast', 4: 'glassDark'}
BODY_TOP, OLD_TOP, REAL_TOP = 128.0, 172.0, 234.0
TURN = math.radians(8.0)
# OpenStreetMap's outline's middle (the triangle's centroid, 33.593313, 130.351483).
LATITUDE, LONGITUDE = 33.5933128, 130.3514835


def place(x, y, z):
    """glTF (+x east, +y up, +z south) onto (+x east, +y north, +z up),
    the mast stretched and the whole turned."""
    east, north, up = x, -z, y
    if up > BODY_TOP:
        up = BODY_TOP + (up - BODY_TOP) * (REAL_TOP - BODY_TOP) / (OLD_TOP - BODY_TOP)
    c, s = math.cos(TURN), math.sin(TURN)
    return east * c - north * s, east * s + north * c, up


def encode(points, triangles):
    out = bytearray(struct.pack('<H', len(points)))
    for x, y, z in points:
        out += struct.pack('<hhH', x, y, z)
    out += struct.pack('<H', len(triangles))
    for a, b, c, paint in triangles:
        out += struct.pack('<HHHB', a, b, c, paint)
    return bytes(out)


def main(glb, swift):
    import hashlib
    digest = hashlib.sha256(open(glb, 'rb').read()).hexdigest()
    if digest != SHA256:
        sys.exit(f'{glb}: sha256 {digest}, expected {SHA256}')
    gltf, blob = read_glb(glb)
    raw = []  # (a, b, c, paint) with float points
    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            paint = PAINT[prim['material']]
            if paint is None:
                continue
            pos = [place(*p) for p in accessor(gltf, blob, prim['attributes']['POSITION'])]
            idx = accessor(gltf, blob, prim['indices'])
            for k in range(0, len(idx), 3):
                raw.append((pos[idx[k]], pos[idx[k + 1]], pos[idx[k + 2]], MATERIALS.index(paint), paint))
    xs = [p[0] for t in raw for p in t[:3]]
    ys = [p[1] for t in raw for p in t[:3]]
    mid = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2)
    keys, points, triangles = {}, [], []

    def key(p):
        q = (round((p[0] - mid[0]) * 100), round((p[1] - mid[1]) * 100), round(p[2] * 100))
        if q not in keys:
            keys[q] = len(points)
            points.append(q)
        return keys[q]

    for a, b, c, paint, _ in raw:
        ka, kb, kc = key(a), key(b), key(c)
        if len({ka, kb, kc}) == 3:
            triangles.append((ka, kb, kc, paint))
    near = encode(points, triangles)

    # The far model: the outline of everything up to 128 m, and of the
    # mast above it, each a prism.
    def ring(low, high):
        pts = [(p[0] - mid[0], p[1] - mid[1]) for t in raw for p in t[:3] if low <= p[2] <= high]
        return convex_hull(sorted(set((round(x, 2), round(y, 2)) for x, y in pts)))

    far_points, far_triangles = [], []

    def prism(hull, top, paint, roof):
        base = len(far_points)
        for x, y in hull:
            far_points.append((round(x * 100), round(y * 100), 0))
            far_points.append((round(x * 100), round(y * 100), round(top * 100)))
        n = len(hull)
        for i in range(n):
            j = (i + 1) % n
            a0, a1, b0, b1 = base + 2 * i, base + 2 * i + 1, base + 2 * j, base + 2 * j + 1
            far_triangles.append((a0, b0, b1, paint))
            far_triangles.append((a0, b1, a1, paint))
        for i in range(1, n - 1):
            far_triangles.append((base + 1, base + 2 * i + 1, base + 2 * i + 3, roof))

    body = ring(0, BODY_TOP)
    mast = ring(BODY_TOP + 0.01, REAL_TOP)
    prism(body, BODY_TOP, MATERIALS.index('glassBlueGrey'), MATERIALS.index('steelGrey'))
    prism(mast, REAL_TOP, MATERIALS.index('mast'), MATERIALS.index('mast'))
    far = encode(far_points, far_triangles)

    # Where the footprint's middle stands.
    lat = LATITUDE + mid[1] / 110_540
    lon = LONGITUDE + mid[0] / (111_320 * math.cos(math.radians(LATITUDE)))
    print(f'near: {len(points)} vertices, {len(triangles)} triangles; far: {len(far_points)} vertices, '
          f'{len(far_triangles)} triangles; middle at {lat:.7f}, {lon:.7f}; '
          f'size {max(xs) - min(xs):.2f} x {max(ys) - min(ys):.2f} x {REAL_TOP:.1f} m')
    lines = [
        '// Generated by tools/fukuoka-map/fukuoka_tower.py from the owner\'s earlier',
        '// version\'s Fukuoka Tower (railway-assets-private-2,',
        '// game-art-previews/docs/art/fukuoka-landmarks-2026-11/old-version). Do not edit by hand.',
        '',
        'extension Map3DHongKongLandmark {',
        '    /// The overseas maps\' landmarks other than Hong Kong\'s, by file name,',
        '    /// in `tools/hk-landmarks/glb_to_swift.py`\'s encoding.',
        '    static let overseasMeshes: [String: String] = [',
        f'        // {len(points)} vertices, {len(triangles)} triangles.',
        f'        "fukuoka-tower": "{base64.b64encode(near).decode()}",',
        f'        // {len(far_points)} vertices, {len(far_triangles)} triangles.',
        f'        "fukuoka-tower-far": "{base64.b64encode(far).decode()}",',
        '    ]',
        '}',
        '',
    ]
    open(swift, 'w').write('\n'.join(lines))


def convex_hull(points):
    """Andrew's monotone chain, anticlockwise."""
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
