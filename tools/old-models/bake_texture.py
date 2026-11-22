#!/usr/bin/env python3
"""Bring a model of the owner's earlier version (SwiftRailMac,
`assets/models/item_<hash>.glb`) into the game as one of its own: the
game draws no textures, so the texture each face wears becomes geometry
in the game's colours (decision 922).

    python3 -I tools/old-models/bake_texture.py japan-wooden-station \
        OLD/item_98459549367e2d2e4456f07d.glb OUT.swift

What it does, and only this:
- each flat panel of the old model (the triangles that share a plane and
  one mapping of the texture onto it, as a wall's two triangles do) is cut
  into a grid of cells about ``CELL`` m wide in the game; each cell takes
  the game colour its texture is nearest (each material of the model has
  its own short list, so a dark window and a dark roof tile do not mix),
  each cell takes the colour most of the nine round it are (twice), and the cells of one colour
  are joined into rectangles (a window's patch squared to the box round
  it first): a window drawn on a wall becomes a window
  of glazing in it, the plaster panels over it plaster, the boards timber;
- a panel that is not a rectangle in the texture (a gable's triangle)
  and every face of the far model take the one colour most of their
  texture is;
- the model is drawn ``scale`` times its old size (the earlier version
  drew its buildings larger than life) and turned onto the game's axes
  (+x along its length, +y its back, +z up), its middle at the origin,
  its ground at 0;
- it is written as `tools/train-models/glb_to_swift.py` writes the
  studio's models, each triangle's colour the index of its class in the
  model's ``classes``.

Standard library only (the PNG decoder is `tools/fukuoka-map`'s).
"""
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'train-models'))
from glb_to_swift import accessor, encode, read_glb  # noqa: E402

CELL = 0.4  # metres in the game a cell is, about

# Each model: the colour classes (the Swift palette's order), each
# material's references (a class and the texture's colour it stands for),
# the scale, and whether its back (the platform side) is the old +x.
MODELS = {
    'japan-wooden-station': {
        'classes': ['timber', 'plaster', 'glass', 'roof', 'concrete', 'stone'],
        'scale': 0.5,
        'backIsPlusX': True,
        # Classes a far model leaves out (a pane is too small to see).
        'nearOnly': ('glass', 'plaster'),
        # Classes whose patches are squared into rectangles, in order.
        'square': ('plaster', 'glass'),
        'materials': {
            0: [('roof', (36, 37, 37)), ('roof', (79, 78, 81)), ('concrete', (119, 117, 119))],
            1: [('timber', (42, 32, 28)), ('timber', (21, 18, 17)), ('roof', (62, 61, 63))],
            2: [('roof', (38, 36, 36)), ('timber', (38, 33, 27)), ('timber', (60, 54, 47)), ('timber', (21, 18, 15)), ('stone', (72, 72, 67))],
            3: [('timber', (44, 36, 30)), ('timber', (27, 23, 19)), ('glass', (62, 63, 64)), ('glass', (30, 32, 34)), ('plaster', (121, 118, 113))],
            4: [('timber', (46, 40, 33)), ('timber', (31, 26, 20)), ('glass', (98, 98, 94)), ('glass', (40, 42, 44)), ('plaster', (157, 151, 144))],
            5: [('timber', (38, 33, 27)), ('timber', (22, 19, 15)), ('glass', (63, 62, 60)), ('glass', (30, 32, 34)), ('plaster', (132, 128, 122))],
            6: [('timber', (49, 43, 40)), ('timber', (119, 105, 95))],
        },
    },
}


def png_pixels(data):
    """The RGB rows of an 8-bit RGB or RGBA PNG with no interlace."""
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    at, chunks, width, height, step = 8, b'', 0, 0, 3
    while at < len(data):
        length, kind = struct.unpack_from('>I4s', data, at)
        body = data[at + 8:at + 8 + length]
        if kind == b'IHDR':
            width, height, depth, colour, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and colour in (2, 6) and interlace == 0, (depth, colour, interlace)
            step = 3 if colour == 2 else 4
        elif kind == b'IDAT':
            chunks += body
        at += 12 + length
    raw, rows, prior = zlib.decompress(chunks), [], bytearray(width * step)
    stride = width * step
    for y in range(height):
        kind, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - step] if i >= step else 0
            b, c = prior[i], prior[i - step] if i >= step else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * step:x * step + 3]) for x in range(width)])
        prior = line
    return rows


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def affine(points, uvs):
    """The map (u, v) -> point of a triangle, as (origin, per u, per v), or
    None when its texture is degenerate."""
    (u0, v0), (u1, v1), (u2, v2) = uvs
    det = (u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)
    if abs(det) < 1e-9:
        return None
    e1, e2 = sub(points[1], points[0]), sub(points[2], points[0])
    du = tuple(((v2 - v0) * a - (v1 - v0) * b) / det for a, b in zip(e1, e2))
    dv = tuple((-(u2 - u0) * a + (u1 - u0) * b) / det for a, b in zip(e1, e2))
    origin = tuple(p - u0 * x - v0 * y for p, x, y in zip(points[0], du, dv))
    return origin, du, dv


def at(map_, u, v):
    origin, du, dv = map_
    return tuple(o + u * x + v * y for o, x, y in zip(origin, du, dv))


def inside(u, v, tri):
    (x0, y0), (x1, y1), (x2, y2) = tri
    d1 = (u - x1) * (y0 - y1) - (x0 - x1) * (v - y1)
    d2 = (u - x2) * (y1 - y2) - (x1 - x2) * (v - y2)
    d3 = (u - x0) * (y2 - y0) - (x2 - x0) * (v - y0)
    neg = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
    pos = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
    return not (neg and pos)


def bake(glb, name, far):
    spec = MODELS[name]
    classes, scale = spec['classes'], spec['scale']
    gltf, blob = read_glb(glb)
    images = []
    for image in gltf['images']:
        view = gltf['bufferViews'][image['bufferView']]
        images.append(png_pixels(blob[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]))

    def colour_class(material, rgb, far=False):
        # How light, and how warm (red over blue, which tells boards from
        # a tile or a pane of the same lightness), weighted three times.
        def feature(c):
            return (sum(c) / 3, 3 * (c[0] - c[2]))
        refs = [r for r in spec['materials'][material] if not (far and r[0] in spec.get('nearOnly', ()))] or spec['materials'][material]
        f = feature(rgb)
        return min(refs, key=lambda ref: sum((a - b) ** 2 for a, b in zip(feature(ref[1]), f)))[0]

    def sample(pixels, u, v):
        h, w = len(pixels), len(pixels[0])
        return pixels[int((v % 1.0) * h) % h][int((u % 1.0) * w) % w]

    # The old model's faces, each with its material, texture and corners.
    faces = []
    for node in gltf['nodes']:
        assert not any(k in node for k in ('matrix', 'rotation', 'scale', 'translation')), node
    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            material = prim['material']
            texture = gltf['materials'][material]['pbrMetallicRoughness']['baseColorTexture']['index']
            pixels = images[gltf['textures'][texture]['source']]
            points = accessor(gltf, blob, prim['attributes']['POSITION'])
            uvs = accessor(gltf, blob, prim['attributes']['TEXCOORD_0'])
            ids = accessor(gltf, blob, prim['indices'])
            for t in range(0, len(ids), 3):
                tri = ids[t:t + 3]
                faces.append((material, pixels, [points[i] for i in tri], [tuple(uvs[i]) for i in tri]))

    out = []  # (three old points, class)

    def whole(material, pixels, pts, uv, *rest):
        votes = {}
        for k in range(7):
            for m in range(7 - k):
                w = (k / 6, m / 6, 1 - k / 6 - m / 6)
                u = sum(a[0] * b for a, b in zip(uv, w))
                v = sum(a[1] * b for a, b in zip(uv, w))
                c = colour_class(material, sample(pixels, u, v), far)
                votes[c] = votes.get(c, 0) + 1
        out.append((pts, max(sorted(votes), key=votes.get)))

    # Panels: faces of one material sharing a texture mapping.
    panels = {}
    for material, pixels, pts, uv in faces:
        m = affine(pts, uv)
        if far or m is None:
            whole(material, pixels, pts, uv)
            continue
        flat = [x for part in m for x in part]
        for key, group in panels.items():
            if key[0] == material and max(abs(a - b) for a, b in zip(key[1:], flat)) < 0.02 * max(1.0, max(abs(x) for x in flat)):
                group.append((material, pixels, pts, uv, m))
                break
        else:
            panels[(material,) + tuple(flat)] = [(material, pixels, pts, uv, m)]
    for group in panels.values():
        material, pixels, _, _, m = group[0]
        normal = cross(sub(group[0][2][1], group[0][2][0]), sub(group[0][2][2], group[0][2][0]))
        us = [p[0] for f in group for p in f[3]]
        vs = [p[1] for f in group for p in f[3]]
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        area = sum(abs((f[3][1][0] - f[3][0][0]) * (f[3][2][1] - f[3][0][1]) - (f[3][2][0] - f[3][0][0]) * (f[3][1][1] - f[3][0][1])) / 2
                   for f in group)
        if area < 0.98 * (u1 - u0) * (v1 - v0):
            for f in group:
                whole(*f[:4])
            continue
        width = math.dist(at(m, u0, v0), at(m, u1, v0)) * scale
        height = math.dist(at(m, u0, v0), at(m, u0, v1)) * scale
        h_px, w_px = len(pixels), len(pixels[0])
        nx = max(1, min(int(width / CELL + 0.5), int((u1 - u0) * w_px + 0.5), 96))
        ny = max(1, min(int(height / CELL + 0.5), int((v1 - v0) * h_px + 0.5), 96))
        grid = []
        for j in range(ny):
            row = []
            for i in range(nx):
                votes = {}
                for a in range(3):
                    for b in range(3):
                        u = u0 + (u1 - u0) * (i + (a + 0.5) / 3) / nx
                        v = v0 + (v1 - v0) * (j + (b + 0.5) / 3) / ny
                        c = colour_class(material, sample(pixels, u, v))
                        votes[c] = votes.get(c, 0) + 1
                row.append(max(sorted(votes), key=votes.get))
            grid.append(row)
        # Each cell takes the class most of the nine round it are (ties
        # keep its own), twice: specks of shadow painted on the boards go,
        # a window of two cells or more stays.
        clean = grid
        for _ in range(2):
            grid, clean = clean, [r[:] for r in clean]
            for j in range(ny):
                for i in range(nx):
                    near = [grid[y][x] for x in range(i - 1, i + 2) for y in range(j - 1, j + 2) if 0 <= x < nx and 0 <= y < ny]
                    best = max(sorted(set(near)), key=near.count)
                    if near.count(best) > near.count(grid[j][i]):
                        clean[j][i] = best
        # A window or a panel is a rectangle: each patch of a class in
        # ``square`` becomes the box round it when it fills half of it or
        # more (a smaller patch is left as it is), the later class on top.
        for c in spec.get('square', ()):
            seen = [[False] * nx for _ in range(ny)]
            for j in range(ny):
                for i in range(nx):
                    if seen[j][i] or clean[j][i] != c:
                        continue
                    stack, cells = [(i, j)], []
                    seen[j][i] = True
                    while stack:
                        x, y = stack.pop()
                        cells.append((x, y))
                        for x2, y2 in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                            if 0 <= x2 < nx and 0 <= y2 < ny and not seen[y2][x2] and clean[y2][x2] == c:
                                seen[y2][x2] = True
                                stack.append((x2, y2))
                    xa, xb = min(x for x, _ in cells), max(x for x, _ in cells)
                    ya, yb = min(y for _, y in cells), max(y for _, y in cells)
                    if len(cells) * 2 >= (xb - xa + 1) * (yb - ya + 1):
                        for y in range(ya, yb + 1):
                            for x in range(xa, xb + 1):
                                clean[y][x] = c
        # Join cells of one class into rectangles.
        used = [[False] * nx for _ in range(ny)]
        for j in range(ny):
            for i in range(nx):
                if used[j][i]:
                    continue
                c = clean[j][i]
                w = 1
                while i + w < nx and not used[j][i + w] and clean[j][i + w] == c:
                    w += 1
                h = 1
                while j + h < ny and all(not used[j + h][x] and clean[j + h][x] == c for x in range(i, i + w)):
                    h += 1
                for y in range(j, j + h):
                    for x in range(i, i + w):
                        used[y][x] = True
                ua, ub = u0 + (u1 - u0) * i / nx, u0 + (u1 - u0) * (i + w) / nx
                va, vb = v0 + (v1 - v0) * j / ny, v0 + (v1 - v0) * (j + h) / ny
                corners = [at(m, ua, va), at(m, ub, va), at(m, ub, vb), at(m, ua, vb)]
                for tri in ((0, 1, 2), (0, 2, 3)):
                    pts = [corners[k] for k in tri]
                    if dot(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])), normal) < 0:
                        pts = [pts[0], pts[2], pts[1]]
                    out.append((pts, c))

    # Onto the game's axes: +x along the old z, +y the back, +z up.
    sign = 1 if spec['backIsPlusX'] else -1
    xs = [p[0] for pts, _ in out for p in pts]
    zs = [p[2] for pts, _ in out for p in pts]
    mx, mz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    game = []
    for pts, c in out:
        game.append(([((p[2] - mz) * scale * sign, (p[0] - mx) * scale * sign, p[1] * scale) for p in pts], classes.index(c)))
    return game


def main(name, glb, swift, enum='Map3DJapanStation'):
    lines = [
        '// Generated by tools/old-models/bake_texture.py; do not edit by hand.',
        '// Palette order: ' + ', '.join(MODELS[name]['classes']) + '.',
        '',
        f'extension {enum} {{',
        "    /// Each model's encoded mesh, by its name.",
        '    static let encoded: [String: String] = [',
    ]
    for far in (False, True):
        key = name + ('-far' if far else '')
        text, count = encode(bake(glb, name, far))
        print(f'{key}: {count} triangles')
        lines.append(f'        // {count} triangles.')
        lines.append(f'        "{key}": """')
        for i in range(0, len(text), 120):
            lines.append('        ' + text[i:i + 120])
        lines.append('        """,')
    lines += ['    ]', '}', '']
    open(swift, 'w').write('\n'.join(lines))


if __name__ == '__main__':
    main(*sys.argv[1:4])
