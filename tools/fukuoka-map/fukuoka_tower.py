#!/usr/bin/env python3
"""Fukuoka Tower on Fukuoka's 3D map (FUKUOKA-LANDMARKS): the owner's own
model from the earlier version (SwiftRailMac `item_5c80a900…`, kept in
`a91453/railway-assets-private-2`,
`game-art-previews/docs/art/fukuoka-landmarks-2026-11/old-version/fukuoka-tower.glb`,
sha256 f15957a0…), written into the game's Swift source as a
registered landmark's mesh file (decision 895), in
`tools/landmarks/glb_to_swift.py`'s encoding.

    python3 -I tools/fukuoka-map/fukuoka_tower.py OLD/fukuoka-tower.glb \
        Sources/GamePresentation/Map3DFukuokaTowerMesh.swift

What it changes, and only this (decision 854's later note FUKUOKA-LANDMARKS):
- the 40 m square of plaza under the tower is left out (the map draws
  its own ground and roads);
- the old textures become the landmarks' palette colours (one material,
  one colour, `MATERIALS` below, in ``Map3DFukuokaTower``'s palette
  order): the walls mirror glass, the mast steel,
  as photographs of the real one (FUKUOKA-TOWER-COLOUR);
- the body (128 m in the earlier version) is stretched to the real one's
  about 150 m, and the mast above it to the real 234 m (the earlier
  version's stopped at 172 m); the north face's middle is the white
  column of the lift shaft, and each southern face has its pale slit with a dark notch on top
  (FUKUOKA-TOWER-GLASS);
- it is turned 8.0° anticlockwise so its triangle lies as OpenStreetMap's
  outline of the real tower (way of Q847033), and its footprint's middle
  put at the origin (the tool prints where that middle stands);
- a far model: the outline of the body (and the spine on its back) and
  of the mast as plain prisms.
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'landmarks'))
import ground_plate  # noqa: E402
from glb_to_swift import accessor, mesh_file, read_glb  # noqa: E402

# The tower's materials, in ``Map3DFukuokaTower``'s palette order.
MATERIALS = ['glassSky', 'steelGrey', 'mullionWhite', 'bandDark']
SOURCE = ("the owner's earlier version's Fukuoka Tower (railway-assets-private-2,\n"
          "// game-art-previews/docs/art/fukuoka-landmarks-2026-11/old-version)")

SHA256 = 'f15957a0bb4bd04f84bba2e675791983d845a1512f3406b4410733b82014b1d3'
# The old materials (by index) onto the landmarks' materials; None: left out.
# FUKUOKA-TOWER-COLOUR: the walls (and the old dark band under the
# top, which the real tower does not have) one mirror glass, the mast
# the steel of the photographs. FUKUOKA-TOWER-GLASS: the sloping top is
# glass too; the old material 3 is painted by where it is (`paint_of`).
PAINT = {0: None, 1: 'glassSky', 2: 'glassSky', 3: 'steelGrey', 4: 'glassSky'}
# FUKUOKA-TOWER-GLASS: the glass body reaches about 150 m on the real
# tower (measured on photographs from the ground, with the lines of the
# body's edges giving the camera's tilt: 152 to 163 m; the top viewing
# floor is at 123 m), not the earlier version's 128 m; the mast above it
# to 234 m.
OLD_BODY_TOP, BODY_TOP, OLD_TOP, REAL_TOP = 128.0, 150.0, 172.0, 234.0
# The two dark slits of the southern faces, one each side of the south
# edge: metres from that edge, their width, how far up the body, and how
# far they stand off the glass.
SLIT_FROM_EDGE, SLIT_WIDTH, SLIT_SHARE, SLIT_OFF = 3.0, 1.5, 0.62, 0.06
SLIT_CAP = 3.0
TURN = math.radians(8.0)
# OpenStreetMap's outline's middle (the triangle's centroid, 33.593313, 130.351483).
LATITUDE, LONGITUDE = 33.5933128, 130.3514835


def place(x, y, z):
    """glTF (+x east, +y up, +z south) onto (+x east, +y north, +z up),
    the body and the mast stretched and the whole turned."""
    east, north, up = x, -z, y
    if up > OLD_BODY_TOP:
        up = BODY_TOP + (up - OLD_BODY_TOP) * (REAL_TOP - BODY_TOP) / (OLD_TOP - OLD_BODY_TOP)
    else:
        up = up * BODY_TOP / OLD_BODY_TOP
    c, s = math.cos(TURN), math.sin(TURN)
    return east * c - north * s, east * s + north * c, up


def paint_of(material, corners):
    """The old material 3 is the mast, and on the north face the lift
    shaft's column up its middle (white on the real tower) between two
    strips of the wall's glass."""
    paint = PAINT[material]
    if material != 3 or max(p[1] for p in corners) > OLD_BODY_TOP:
        return paint
    return 'glassSky' if all(abs(p[0]) >= 1.99 for p in corners) else 'mullionWhite'


def slits():
    """The southern faces' slits as thin pale panels just off the glass,
    each ending in a dark notch (glTF coordinates, before `place`)."""
    out = []
    apex = (0.0, 12.0)
    for corner in ((-10.0, -6.0), (10.0, -6.0)):
        dx, dz = corner[0] - apex[0], corner[1] - apex[1]
        length = math.hypot(dx, dz)
        ux, uz = dx / length, dz / length
        # Outward: away from the triangle's middle (0, 0).
        nx, nz = -uz, ux
        if nx * apex[0] + nz * apex[1] < 0:
            nx, nz = -nx, -nz
        a = [apex[0] + ux * d + nx * SLIT_OFF for d in (SLIT_FROM_EDGE, SLIT_FROM_EDGE + SLIT_WIDTH)]
        b = [apex[1] + uz * d + nz * SLIT_OFF for d in (SLIT_FROM_EDGE, SLIT_FROM_EDGE + SLIT_WIDTH)]
        top = OLD_BODY_TOP * SLIT_SHARE
        for low, high, paint in ((0.0, top - SLIT_CAP, 'mullionWhite'), (top - SLIT_CAP, top, 'bandDark')):
            quad = [(a[0], low, b[0]), (a[1], low, b[1]), (a[1], high, b[1]), (a[0], high, b[0])]
            # Anticlockwise seen from outside.
            e1 = [quad[1][i] - quad[0][i] for i in range(3)]
            e2 = [quad[2][i] - quad[0][i] for i in range(3)]
            facing = (e1[1] * e2[2] - e1[2] * e2[1]) * nx + (e1[0] * e2[1] - e1[1] * e2[0]) * nz
            if facing < 0:
                quad = [quad[1], quad[0], quad[3], quad[2]]
            out += [(quad[0], quad[1], quad[2], paint), (quad[0], quad[2], quad[3], paint)]
    return out


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
            if PAINT[prim['material']] is None:
                continue
            old = accessor(gltf, blob, prim['attributes']['POSITION'])
            pos = [place(*p) for p in old]
            idx = accessor(gltf, blob, prim['indices'])
            for k in range(0, len(idx), 3):
                paint = paint_of(prim['material'], [old[i] for i in idx[k:k + 3]])
                raw.append((pos[idx[k]], pos[idx[k + 1]], pos[idx[k + 2]], MATERIALS.index(paint), paint))
    for corners in slits():
        a, b, c = (place(*p) for p in corners[:3])
        raw.append((a, b, c, MATERIALS.index(corners[3]), corners[3]))
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
    # OLD-PORT-AUDIT: the old plaza (material 0) must stay out.
    ground_plate.check(near, "fukuoka-tower")

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
    prism(body, BODY_TOP, MATERIALS.index('glassSky'), MATERIALS.index('steelGrey'))
    prism(mast, REAL_TOP, MATERIALS.index('steelGrey'), MATERIALS.index('steelGrey'))
    far = encode(far_points, far_triangles)

    # Where the footprint's middle stands.
    lat = LATITUDE + mid[1] / 110_540
    lon = LONGITUDE + mid[0] / (111_320 * math.cos(math.radians(LATITUDE)))
    print(f'near: {len(points)} vertices, {len(triangles)} triangles; far: {len(far_points)} vertices, '
          f'{len(far_triangles)} triangles; middle at {lat:.7f}, {lon:.7f}; '
          f'size {max(xs) - min(xs):.2f} x {max(ys) - min(ys):.2f} x {REAL_TOP:.1f} m')
    models = [('fukuoka-tower', near, len(points), len(triangles)),
              ('fukuoka-tower-far', far, len(far_points), len(far_triangles))]
    open(swift, 'w').write(mesh_file('Map3DFukuokaTower', MATERIALS, SOURCE, models, tool='tools/fukuoka-map/fukuoka_tower.py'))


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
