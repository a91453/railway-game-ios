#!/usr/bin/env python3
"""Bring the owner's earlier version's station over the tracks (橋上駅舎:
its hall for two tracks between side platforms, its hall over an
island, and the stair down to a further island) into the game,
restyled as the game's own (decision 1043, the second step of decision
1042).

    python3 -I tools/old-models/old_overtrack.py \
        ../railway-assets-private-2/game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1 \
        Sources/GamePresentation/Map3DOldOvertrackMesh.swift

The studio turned the old models into the game's palette, half their old
size, their halls' underside 7.35 m over the ground (6.50 m over the
rails, the game's footbridge deck; `a91453/railway-assets-private-2`
`game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1`,
#662). This tool reads those GLBs (each checked by its SHA-256) and,
as the ground stations' tool does (`old_ground_station.py`), keeps their
shapes but makes them the game's (owner, 2026-11-28: 「相似就好 不要一模一樣」
「跟舊版不同比較好」):

- the old dark red roofs (the hall's gable roof, its wings', the stairs'
  covers) take the green of the game's stations (decisions 899, 1042: the
  small ground station's roof);
- the hall carries a name board in the game's sign blue on its street
  front (both fronts of the island's hall), as the ground stations do.

It also writes the corridor between the hall and a further island's
stair (the studio's `extension_faces`: a wall 2.06 m from the stair's
middle, from x -5 to 9, 7.35 to 11.34 m up, its roof to 11.74 m), one
metre long, for the game to stretch across: white walls with the hall's
band of windows each side and the green roof, no end faces (the hall's
and the stair's walls close it).

It writes the models as `tools/train-models/glb_to_swift.py` does, in the
ground stations' palette (``MATERIALS``, ``Map3DOldGroundStation/meshPalette``).
Standard library only.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'train-models'))
from glb_to_swift import encode, triangles  # noqa: E402
from old_ground_station import MATERIALS, PREFIX, box, name_board  # noqa: E402

# Each GLB this tool reads and its SHA-256 (revision-1 `report.json`).
SOURCES = {
    'overtrack-1': '79431cb1ba738371d2e0faf2ded88463f67e5632c6a3bde38ed534627fe0a715',
    'overtrack-1-far': '72f8e3a4a486174ffb0a377ef55a7bdb76961ec9eda66fb0f1e96837b701203c',
    'overtrack-2': 'c9fc561ee6fb5f1c0359c85f3c2843ac787a90cc3e0923ded5463efe40aac07b',
    'overtrack-2-far': '8826e45a3149920c6e6da24d9757215b3df1466d7ce1b6a5958516d792bc00bb',
    'overtrack-stair': 'fabf1a7cd4ec72dad072f53e55a22a49898d84d2fa8890189ca82b9abc378718',
}

# The street wings' fronts (their outer wall), the top of their roofs.
WING_FRONT = {'overtrack-1': [-11.78], 'overtrack-2': [-12.60, 12.60]}
WING_ROOF = 11.74


def green_roofs(tris):
    """Every old red face the game's station green."""
    red, green = MATERIALS.index('roofRed'), MATERIALS.index('stationGreen')
    return [(points, green if paint == red else paint) for points, paint in tris]


def mirrored(tris):
    """`tris` mirrored across y (each triangle's winding turned back)."""
    return [([(x, -y, z) for x, y, z in (points[0], points[2], points[1])], paint) for points, paint in tris]


def hall(name):
    """A hall: its roofs green, a name board on each street front."""
    def restyle(tris):
        out = green_roofs(tris)
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
    both ends, a band of windows along each side."""
    ends = [(1, 0.0), (1, 1.0)]
    tris = without(box((-5.0, 0.0, 7.35), (9.0, 1.0, 11.34), 'tileWhite'), ends)
    tris += without(box((-5.24, 0.0, 11.34), (9.24, 1.0, 11.74), 'stationGreen'), ends)
    for x0, x1 in ((-5.06, -5.0), (9.0, 9.06)):
        band = without(box((x0, 0.0, 8.55), (x1, 1.0, 10.15), 'glassBlue'), ends)
        # Its face on the wall would lie on the wall's plane.
        tris += without(band, [(0, -5.0), (0, 9.0)])
    return tris


RESTYLE = {
    'overtrack-1': hall('overtrack-1'), 'overtrack-1-far': hall('overtrack-1-far'),
    'overtrack-2': hall('overtrack-2'), 'overtrack-2-far': hall('overtrack-2-far'),
    'overtrack-stair': green_roofs,
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
