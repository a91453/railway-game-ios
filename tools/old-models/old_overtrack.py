#!/usr/bin/env python3
"""Bring the owner's earlier version's station over the tracks (橋上駅舎:
its hall for two tracks between side platforms, its hall over an
island, and the stair down to a further island) into the game (decision
1043, the second step of decision 1042).

    python3 -I tools/old-models/old_overtrack.py \
        ../railway-assets-private-2/game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1 \
        Sources/GamePresentation/Map3DOldOvertrackMesh.swift

The studio turned the old models into the game's palette, half their old
size, their halls' underside 7.35 m over the ground (6.50 m over the
rails, the game's footbridge deck; `a91453/railway-assets-private-2`
`game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1`,
#662), and then, the owner having seen them in the game (2026-11-28:
「外型還是一樣」「一些模型可以一起用 但外型要不同」), drew them again in a
shape of their own: a steel roof floating over the hall with a green
clerestory over the tracks, tall windows between slim white ribs, stairs
that turn at a landing, slim twin-column piers (#691). The connections
and sizes stayed. This tool reads those GLBs (each checked by its
SHA-256) and:

- checks that none keeps the old dark red;
- gives the hall a name board in the game's sign blue on its street
  front (both fronts of the island's hall), on the wing's flat roof, as
  the ground stations have;
- writes the corridor between the hall and a further island's stair (the
  studio's `extension_faces`: a wall 2.06 m from the stair's middle, from
  x -5 to 9, 7.35 to 11.34 m up, its eave to 11.74 m), one metre long, for
  the game to stretch across, in the new hall's dress: pale walls with
  the band of windows and the green band under the eave each side, the
  slate eave and the steel roof, no end faces (the hall's and the
  stair's walls close it).

It writes the models as `tools/train-models/glb_to_swift.py` does, in the
ground stations' palette with the new shape's four colours after it
(``MATERIALS``, ``Map3DOldOvertrack/meshPalette``).
Standard library only.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'train-models'))
from glb_to_swift import encode, triangles  # noqa: E402
from old_ground_station import MATERIALS as GROUND_MATERIALS, PREFIX, name_board  # noqa: E402
from old_ground_station import box as ground_box  # noqa: E402

# The ground stations' palette, then the new shape's own four (the
# studio's slots 13, 14, 15 and 17; its stationGreen is the ground
# stations' own).
MATERIALS = GROUND_MATERIALS + ['wallPale', 'roofSilver', 'timber', 'arcade']


def box(low, high, material):
    """The ground stations' box, painted from this palette."""
    return [(points, MATERIALS.index(material)) for points, _ in ground_box(low, high, 'tileWhite')]

# Each GLB this tool reads and its SHA-256 (revision-1's new shapes, #691).
SOURCES = {
    'overtrack-1': 'cecc35e7d92103d94f81bcf11922ec0820fe4236433d5a17a84e7e1a95f6de0b',
    'overtrack-1-far': '9d403a160d319278594f97c44db2968babe78d0c238885c58f71b22ae99f0654',
    'overtrack-2': '7616f4bab1cb91782e98632a12697b695db2651b720fecf4d951406c5b2de693',
    'overtrack-2-far': '8f87f0240cb13769ae0e71f6b81d1a1b9d4fb563ba0a61ac9d850c426e9d7635',
    'overtrack-stair': '74c298de5fcdeba2d967806b0b5af5bbe46ddb6b661268ac00858de3bb80aa54',
}

# The street wings' fronts (their outer wall), the top of their roofs.
WING_FRONT = {'overtrack-1': [-11.78], 'overtrack-2': [-12.60, 12.60]}
WING_ROOF = 11.74


def no_red(tris):
    """`tris`, checked to keep none of the old dark red."""
    if any(paint == MATERIALS.index('roofRed') for _, paint in tris):
        raise SystemExit('a model keeps the old red')
    return tris


def mirrored(tris):
    """`tris` mirrored across y (each triangle's winding turned back)."""
    return [([(x, -y, z) for x, y, z in (points[0], points[2], points[1])], paint) for points, paint in tris]


def hall(name):
    """A hall: a name board on each street front."""
    def restyle(tris):
        out = no_red(tris)
        for front in WING_FRONT[name.replace('-far', '')]:
            board = name_board(-abs(front), WING_ROOF, 3.5)
            out += mirrored(board) if front > 0 else board
        return out
    return restyle


def without(tris, faces):
    """`tris` less those whose every corner lies on one of `faces` (an
    axis and a value)."""
    return [(points, paint) for points, paint in tris
            if not any(all(abs(p[axis] - value) < 1e-6 for p in points) for axis, value in faces)]


def corridor():
    """The corridor's metre (y 0 to 1): its walls and roof, open at
    both ends; along each side, as on the hall's wings, the band of
    windows and the green band under the slate eave."""
    ends = [(1, 0.0), (1, 1.0)]
    tris = without(box((-5.0, 0.0, 7.35), (9.0, 1.0, 11.34), 'wallPale'), ends)
    eave = without(box((-5.24, 0.0, 11.34), (9.24, 1.0, 11.74), 'roofSlate'), ends)
    steel = MATERIALS.index('steel')
    tris += [(points, steel if all(abs(p[2] - 11.74) < 1e-6 for p in points) else paint) for points, paint in eave]
    for x0, x1 in ((-5.06, -5.0), (9.0, 9.06)):
        for z0, z1, paint in ((8.65, 10.75, 'glassBlue'), (10.85, 11.24, 'stationGreen')):
            band = without(box((x0, 0.0, z0), (x1, 1.0, z1), paint), ends)
            # Its face on the wall would lie on the wall's plane.
            tris += without(band, [(0, -5.0), (0, 9.0)])
    return tris


RESTYLE = {
    'overtrack-1': hall('overtrack-1'), 'overtrack-1-far': hall('overtrack-1-far'),
    'overtrack-2': hall('overtrack-2'), 'overtrack-2-far': hall('overtrack-2-far'),
    'overtrack-stair': no_red,
}


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.split('\n\n')[1])
    source, target = sys.argv[1], sys.argv[2]
    lines = [
        '// Generated by tools/old-models/old_overtrack.py; do not edit by hand.',
        '// Palette order: ' + ', '.join(MATERIALS) + '.',
        '',
        'extension Map3DOldOvertrack {',
        '    /// Each model\'s encoded mesh, by its name.',
        '    static let encoded: [String: String] = [',
    ]
    models = []
    for name, digest in SOURCES.items():
        path = os.path.join(source, PREFIX + name + '.glb')
        with open(path, 'rb') as f:
            if hashlib.sha256(f.read()).hexdigest() != digest:
                raise SystemExit(f'{path}: not the studio\'s revision-1 file')
        models.append((name, RESTYLE[name](triangles(path, MATERIALS))))
    models.append(('corridor', corridor()))
    for name, tris in models:
        text, count = encode(tris)
        print(f'{name}: {count} triangles')
        lines.append(f'        // {count} triangles.')
        lines.append(f'        "{name}": """')
        for i in range(0, len(text), 120):
            lines.append('        ' + text[i:i + 120])
        lines.append('        """,')
    lines += ['    ]', '}', '']
    with open(target, 'w') as f:
        f.write('\n'.join(lines))


if __name__ == '__main__':
    main()
