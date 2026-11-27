#!/usr/bin/env python3
"""Japan's traffic signal on Fukuoka's 3D map (JP-STREET-SIGNALS): the
owner's own model from the earlier version (SwiftRailMac
`item_ebd5cc627de55b8fb6e7ded9`, its list's 「三灯式信号」, kept in
`a91453/railway-assets-private-2`,
`game-art-previews/docs/art/jp-street-signals-2026-11/old-version/japan-signal-3lamp.glb`),
written into the game's Swift source as three models, one a light it shows,
in `tools/train-models/glb_to_swift.py`'s encoding.

    python3 -I tools/fukuoka-map/japan_signal.py OLD/japan-signal-3lamp.glb \
        Sources/GamePresentation/Map3DJapanSignalMesh.swift

What it changes, and only this:
- the old texture becomes the game's colours, one a part (triangles that
  share a corner): each triangle votes, by its area, for the palette grey
  nearest how light the texture is under it, and the part takes the grey
  with the most: the housing and the hoods the pale grey (``Map3DPalette/tankSteel``), the
  post and the arm the galvanised grey (``Map3DPalette/steel``), a dark
  grey the signals' housing. One a triangle, as it first was, painted two
  of the post's six long triangles and half the arm's dark: their edge
  falls on the texture's dark seam beside the post's strip, and the post
  showed a black stripe in the game (2026-11-27);
- each light's square face (the texture's lens) becomes the pale face
  with a dark ring and a round lens of 27 cm on it, the lens the
  signals' red, amber or green (``Map3DProp/signalLights``), lit in the
  model that shows it; its hood 1.3 times as wide, so the ring and the
  lens fit between its walls;
- the earlier version's 12 m post is drawn at the game's scale: the whole
  model 0.64 of its size, so a light is 45 cm square (the lens 30 cm),
  the arm 0.9 m longer, so the lights hang over the lane as Taiwan's
  (``Map3DProp/signalGo``), and the top 0.7 m lower, so the lights'
  middle stands at 5.6 m as Taiwan's;
- it is turned so the lights look toward −x (the traffic they face comes
  from −x, as every signal of the game) and the arm reaches toward +z:
  Japan keeps left, the post stands at the left kerb and the arm reaches
  right, over the lanes, the green next to the post and the red at the
  arm's end, by the road's middle (as the earlier version drew it).
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'train-models'))
from glb_to_swift import accessor, encode, read_glb  # noqa: E402

# The palette, in ``Map3DJapanSignal``'s order.
MATERIALS = ['steel', 'tankSteel', 'dark', 'red_lit', 'red_unlit', 'amber_lit', 'amber_unlit', 'green_lit', 'green_unlit']
# How light each grey of the palette is (0–255), to match the texture.
GREYS = {'steel': 142, 'tankSteel': 203, 'dark': 48}
# The lights by the texture's quarter their lens is in (u, v from the top left).
LENSES = {(0, 0): 'green', (1, 0): 'amber', (0, 1): 'red'}
MODELS = {'jp-signal-red': 'red', 'jp-signal-amber': 'amber', 'jp-signal-green': 'green'}

SCALE = 0.64
REACH, FROM = 0.9, 0.5      # the arm's far part (beyond 0.5 m) moved out 0.9 m
DROP, ABOVE = 0.7, 4.0      # everything above 4 m lowered 0.7 m
LENS, RING = 0.135, 0.155   # the lens's and its dark ring's radius
SIDES = 12
# The old hoods' walls stand 12.5 cm from a light's middle, inside the
# ring's and the lens's edge, so the ring stuck out past them and their
# walls cut into the lens: the round frame looked broken in the game
# (2026-11-27). Each hood is made this much wider about its light's
# middle (its walls about 16 cm out, its outside 21.5 cm, short of the
# next hood's 22.4 cm), and the ring (15.5 cm) and the lens fit inside it.
HOOD_WIDEN = 1.3
FACE = -0.184               # in front of the lights' faces (x = −0.182, the game's x): a hood


def png_pixels(data):
    """The RGB pixels of an 8-bit RGB or RGBA PNG with no interlace."""
    import zlib
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    at, chunks, width = 8, b'', 0
    while at < len(data):
        length, kind = struct.unpack_from('>I4s', data, at)
        body = data[at + 8:at + 8 + length]
        if kind == b'IHDR':
            width, height, depth, colour, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and colour in (2, 6) and interlace == 0
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


def place(p):
    """The old model's point at the game's scale and in its axes (glTF's,
    +y up): scaled, the arm lengthened, the top lowered, turned."""
    x, y, z = (v * SCALE for v in p)
    if x > FROM:
        x += REACH
    if y > ABOVE:
        y -= DROP
    return (-z, y, x)


def main(glb, swift):
    gltf, blob = read_glb(glb)
    image = gltf['images'][0]
    view = gltf['bufferViews'][image['bufferView']]
    pixels = png_pixels(blob[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']])
    size = len(pixels)

    def lightness(uvs):
        """The texture's mean lightness under a triangle."""
        samples = []
        for k in range(5):
            for m in range(5 - k):
                w = (k / 4, m / 4, 1 - k / 4 - m / 4)
                u = sum(a[0] * b for a, b in zip(uvs, w))
                v = sum(a[1] * b for a, b in zip(uvs, w))
                r, g, b = pixels[min(size - 1, max(0, int(v * size)))][min(size - 1, max(0, int(u * size)))]
                samples.append((r + g + b) / 3)
        return sum(samples) / len(samples)

    def area(corners):
        a, b, c = corners
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        return math.sqrt(sum(x * x for x in n)) / 2

    triangles, faces, shaded = [], {}, []
    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            points = accessor(gltf, blob, prim['attributes']['POSITION'])
            uvs = accessor(gltf, blob, prim['attributes']['TEXCOORD_0'])
            ids = accessor(gltf, blob, prim['indices'])
            for t in range(0, len(ids), 3):
                tri = ids[t:t + 3]
                corners = [points[i] for i in tri]
                mu = sum(uvs[i][0] for i in tri) / 3
                mv = sum(uvs[i][1] for i in tri) / 3
                quarter = (int(mu >= 0.5), int(mv >= 0.5))
                flat = all(abs(c[2] - corners[0][2]) < 1e-4 for c in corners)
                front = flat and corners[0][2] > 0.2 and quarter in LENSES and max(uvs[i][0] for i in tri) <= 1.001
                if front:
                    faces.setdefault(LENSES[quarter], []).extend(corners)
                    triangles.append(([place(c) for c in corners], 'tankSteel'))
                else:
                    shaded.append((len(triangles), corners, lightness([uvs[i] for i in tri])))
                    triangles.append(([place(c) for c in corners], None))
    assert sorted(faces) == ['amber', 'green', 'red'], faces.keys()

    # Each part (triangles sharing a corner) takes the palette grey most of
    # its area is nearest to.
    parent = {}

    def root(key):
        parent.setdefault(key, key)
        while parent[key] != key:
            parent[key] = parent[parent[key]]
            key = parent[key]
        return key

    def key(corner):
        return tuple(round(v, 5) for v in corner)

    for _, corners, _ in shaded:
        first = root(key(corners[0]))
        for corner in corners[1:]:
            parent[root(key(corner))] = first
    def nearest(light):
        return min(GREYS, key=lambda name: abs(GREYS[name] - light))

    votes = {}
    for _, corners, light in shaded:
        part = votes.setdefault(root(key(corners[0])), {})
        part[nearest(light)] = part.get(nearest(light), 0.0) + area(corners)
    for index, corners, _ in shaded:
        part = votes[root(key(corners[0]))]
        triangles[index] = (triangles[index][0], max(sorted(part), key=lambda name: part[name]))

    # Each light's lens and ring, a hair in front of its face (the face is
    # at the old z; in front is toward the old +z, the game's −x).
    lenses = {}
    for light, corners in faces.items():
        xs = [c[0] for c in corners]
        ys = [c[1] for c in corners]
        middle = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, corners[0][2])
        lenses[light] = middle

    def disc(middle, radius, ahead, paint):
        out = []
        cx, cy, cz = middle
        rim = [(cx + radius / SCALE * math.cos(2 * math.pi * k / SIDES), cy + radius / SCALE * math.sin(2 * math.pi * k / SIDES),
                cz + ahead / SCALE) for k in range(SIDES)]
        centre = (cx, cy, cz + ahead / SCALE)
        for k in range(SIDES):
            out.append(([place(centre), place(rim[k]), place(rim[(k + 1) % SIDES])], paint))
        return out

    models = []
    for name, shown in MODELS.items():
        hoods = 0
        tris = list(triangles)
        for light, middle in sorted(lenses.items()):
            tris += disc(middle, RING, 0.006, 'dark')
            tris += disc(middle, LENS, 0.012, f'{light}_lit' if light == shown else f'{light}_unlit')
        # glTF (x, y up, z) -> the game's mesh axes (x, -z, y), as glb_to_swift.
        game = [([(p[0], -p[2], p[1]) for p in pts], paint) for pts, paint in tris]
        middles = [-place(middle)[2] for middle in lenses.values()]
        widened = []
        for pts, paint in game:
            if paint in ('steel', 'tankSteel') and all(p[0] < FACE for p in pts):
                y = sum(p[1] for p in pts) / 3
                centre = min(middles, key=lambda m: abs(m - y))
                pts = [(p[0], centre + (p[1] - centre) * HOOD_WIDEN, p[2]) for p in pts]
                hoods += 1
            widened.append((pts, MATERIALS.index(paint)))
        game = widened
        assert hoods == 48, hoods
        text, count = encode(game)
        print(f'{name}: {count} triangles')
        models.append((name, text, count))

    lines = [
        '// Generated by tools/fukuoka-map/japan_signal.py; do not edit by hand.',
        '// Palette order: ' + ', '.join(MATERIALS) + '.',
        '',
        'extension Map3DJapanSignal {',
        "    /// Each model's encoded mesh, by its name.",
        '    static let encoded: [String: String] = [',
    ]
    for name, text, count in models:
        lines.append(f'        // {count} triangles.')
        lines.append(f'        "{name}": """')
        for i in range(0, len(text), 120):
            lines.append('        ' + text[i:i + 120])
        lines.append('        """,')
    lines += ['    ]', '}', '']
    open(swift, 'w').write('\n'.join(lines))


if __name__ == '__main__':
    main(*sys.argv[1:])
