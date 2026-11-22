#!/usr/bin/env python3
"""Japan's utility poles on Fukuoka's 3D map (decision 923): the owner's own
models from the earlier version (SwiftRailMac, its list's 「電柱」 401–405,
kept in `a91453/railway-assets-private-2`,
`game-art-previews/docs/art/jp-street-signals-2026-11/old-version/`), written
into the game's Swift source in `tools/train-models/glb_to_swift.py`'s
encoding, as `japan_signal.py` wrote the signal (decision 921).

    python3 -I tools/fukuoka-map/japan_pole.py OLD_DIR \
        Sources/GamePresentation/Map3DJapanPoleMesh.swift

The pedestrian signals and the bus stop beside them (the studio's
`jp-walk-*`, `jp-bus-stop`) are written by
`glb_to_swift.py --enum Map3DJapanStreet --materials steel,tankSteel,dark,red_lit,
red_unlit,green_lit,green_unlit,signWhite,signRed,concrete` into
`Map3DJapanStudioMesh.swift`.

OLD_DIR holds the earlier version's `item_<id>.glb` (`MODELS` below), or
the assets repository's copies, `<name>-item_<first 8 of id>.glb`. What
the tool changes, and only this:
- the old texture becomes the game's colours, one a triangle: the shaft
  (the long faces from the foot up and the cap) the concrete of Taiwan's
  pole (``Map3DPalette/concrete``), whether the old one was drawn in wood
  or concrete, as a city's poles in Japan are concrete; the crossarms, the
  braces, the transformers and the bolts the galvanised grey
  (``Map3DPalette/steel``); the small dark parts on the arms (the
  insulators, the fuse cut-outs) the insulators' white
  (``Map3DPalette/tileWhite``), as Taiwan's pole has them; the street
  light's shade the pale grey (``Map3DPalette/tankSteel``) and its lens
  the street lights' warm white (``Map3DProp/lampLight``), lit;
- it is turned half round (the old arm reached toward +z; the game's
  props reach toward −z, ``Map3DProp/lamp``): the crossarms, the cut-outs
  and the light toward the road;
- the size is the old one's (a 10 m pole, as Taiwan's 10.2 m).
"""
import io
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'train-models'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_to_swift import accessor, encode, read_glb  # noqa: E402
from japan_signal import png_pixels  # noqa: E402

MATERIALS = ['concrete', 'steel', 'insulator', 'tankSteel', 'lamp_lit']

# The game's model by name, from the old model by its id (the list's name
# in the comment). The wood ones are the shapes the list has only in wood.
MODELS = {
    'jp-pole': '2594988f7e4ca7db6b158e1d',               # 電柱(鉄筋): two crossarms, six insulators
    'jp-pole-transformer': '070f5afb79d8753ec99e515f',   # 電柱(木製 変圧器付): one transformer
    'jp-pole-transformers': 'cff51856e953adc3775a7ace',  # 電柱(木製 変圧器付): two transformers on a frame
    'jp-pole-plain': '06ff91325699b9f17d46acc1',         # 電柱(木製): the bare pole, its step bolts
    'jp-pole-lamp': '48ae680dda9e8d0050d013b7',          # 電柱(木製 街灯付): a light on a short arm
}

SHAFT = 0.17      # a face within this of the pole's axis…
TALL = 3.0        # …and this tall (or the cap at its top) is the shaft
SMALL = 0.7       # an arm's part no longer than this…
DARK = 75         # …and darker than this is an insulator or a cut-out


def texture(gltf, blob):
    image = gltf['images'][0]
    view = gltf['bufferViews'][image['bufferView']]
    rows = png_pixels(blob[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']])
    return rows, len(rows[0]), len(rows)


def colour(rows, width, height, uvs):
    """The texture's mean colour under a triangle (21 samples)."""
    samples = []
    for k in range(5):
        for m in range(5 - k):
            w = (k / 4, m / 4, 1 - k / 4 - m / 4)
            u = sum(a[0] * b for a, b in zip(uvs, w)) % 1
            v = sum(a[1] * b for a, b in zip(uvs, w)) % 1
            samples.append(rows[min(height - 1, int(v * height))][min(width - 1, int(u * width))])
    return tuple(sum(s[i] for s in samples) / len(samples) for i in range(3))


def paint(corners, rgb, top):
    """The palette name of one old triangle."""
    near = all(abs(c[0]) <= SHAFT and abs(c[2]) <= SHAFT for c in corners)
    ys = [c[1] for c in corners]
    if near and (max(ys) - min(ys) >= TALL or min(ys) >= top - 1e-3):
        return 'concrete'
    r, g, b = rgb
    light = (r + g + b) / 3
    # The lens: light and warm (not the wood's brown, whose red stands
    # well above its green).
    if light > 150 and r - g <= 12 and r - b > 25:
        return 'lamp_lit'
    if light > 135:
        return 'tankSteel'
    span = max(max(c[i] for c in corners) - min(c[i] for c in corners) for i in range(3))
    if light < DARK and span <= SMALL:
        return 'insulator'
    return 'steel'


def place(p):
    """Turned half round about the vertical: the arm toward −z."""
    return (-p[0], p[1], -p[2])


def model(path):
    gltf, blob = read_glb(path)
    rows, width, height = texture(gltf, blob)
    triangles = []
    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            points = accessor(gltf, blob, prim['attributes']['POSITION'])
            uvs = accessor(gltf, blob, prim['attributes']['TEXCOORD_0'])
            ids = accessor(gltf, blob, prim['indices'])
            top = max(p[1] for p in points)
            for t in range(0, len(ids), 3):
                tri = ids[t:t + 3]
                corners = [points[i] for i in tri]
                name = paint(corners, colour(rows, width, height, [uvs[i] for i in tri]), top)
                triangles.append(([place(c) for c in corners], name))
    # glTF (x, y up, z) -> the game's mesh axes (x, -z, y), as glb_to_swift.
    return [([(p[0], -p[2], p[1]) for p in pts], MATERIALS.index(name)) for pts, name in triangles]


def main(folder, swift):
    lines = [
        '// Generated by tools/fukuoka-map/japan_pole.py; do not edit by hand.',
        '// Palette order: ' + ', '.join(MATERIALS) + '.',
        '',
        'extension Map3DJapanStreet {',
        "    /// Each utility pole's encoded mesh, by its name.",
        '    static let poleEncoded: [String: String] = [',
    ]
    for name, item in MODELS.items():
        # The earlier version's file name, or the assets repository's
        # (`<name>-item_<first 8>.glb`).
        path = os.path.join(folder, f'item_{item}.glb')
        if not os.path.exists(path):
            path = os.path.join(folder, f'{name}-item_{item[:8]}.glb')
        text, count = encode(model(path))
        print(f'{name}: {count} triangles')
        lines.append(f'        // {count} triangles, from the earlier version\'s item_{item}.')
        lines.append(f'        "{name}": """')
        for i in range(0, len(text), 120):
            lines.append('        ' + text[i:i + 120])
        lines.append('        """,')
    lines += ['    ]', '}', '']
    open(swift, 'w').write('\n'.join(lines))


if __name__ == '__main__':
    main(*sys.argv[1:])
