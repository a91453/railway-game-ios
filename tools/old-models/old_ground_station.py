#!/usr/bin/env python3
"""Bring the owner's earlier version's general ground station (its three
station buildings, its 20 m platform canopies and its platform-end
railing) into the game, restyled as the game's own (decision 1042).

    python3 -I tools/old-models/old_ground_station.py \
        ../railway-assets-private-2/game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1 \
        Sources/GamePresentation/Map3DOldGroundStationMesh.swift

The studio already turned the old models into the game's palette and
half their old size (`a91453/railway-assets-private-2`
`game-art-previews/docs/art/old-port-station-ground-2026-11/revision-1`,
#662); this tool reads those GLBs (each checked by its SHA-256) and the
owner's word that the game's should look *like* the old ones, not *be*
them (2026-11-28: 「記得稍微修一下符合遊戲風格而不是照搬」「相似就好
不要一模一樣不然老玩家會沒新鮮感」). Their shapes stay; what changes is
what makes a station the game's (decisions 899, 940):

- the small station's brown hip roof takes the green of the game's own
  station canopies, with a dark edge under its eaves (decision 940's
  roof edge);
- each building carries a station name board in the game's sign blue
  (the small one's white roof board painted, the two big ones' a board
  standing on the front parapet);
- the middle station's entrance canopy is the game's station green, not
  steel;
- the two big ones' flat roofs are the light concrete of the game's own
  station roofs, not the old dark slate, which read from the game's
  camera as a dark slab over the platforms.

The canopies and the railing keep their shape; their colours are the
game's through the Swift palette (``Map3DOldGroundStation/meshPalette``).

It writes the models as `tools/train-models/glb_to_swift.py` does, each
triangle's colour the index of its material in ``MATERIALS``. Standard
library only.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'train-models'))
from glb_to_swift import encode, triangles  # noqa: E402

# The studio's 13 material names (revision-1 README §4), then the game's
# two added here.
MATERIALS = ['tileWhite', 'wallBeige', 'concrete', 'stone', 'canopyRoof', 'steel', 'roofSlate', 'roofBrown',
             'roofRed', 'glassDark', 'glassBlue', 'dark', 'yellowRail', 'signBlue', 'stationGreen']

PREFIX = 'old-port-station-ground-'

# Each GLB this tool reads and its SHA-256 (revision-1 `stats.json`).
SOURCES = {
    's': 'ae4943846f9a8dd2a20b9cc09a61496de0939f8c0cb99ebc7860f82ed626480f',
    's-far': '182ac354e29e1023cc2ef2f6e51c9317db3ae98c04db561174877f82cc791bf0',
    'm': '63dd6214efcb44d65b4b2cfec92ee8e4e489ed694643cd8e2c0b894c7db9c4fb',
    'm-far': 'e72d9a8db8e665deb94e5998927828f3429fcde344f013441be0adecadbb92ae',
    'l': 'c1f1f2fbd65b18aa7edf6a739b5a6c5e8937f269fabd93054d06e3bee30f4a24',
    'l-far': '2df39ff7b55480f384fa526fa8f63978821bea0a8242e8f2de700f9dabbc2bf2',
    'canopy-side': 'dc1d585bd37a54f78f72b2c63da8dfc0b4c8087b56ffa50a1ab7eac7ef7677c1',
    'canopy-island': 'e9afd4d22f54a1e067e3e19bc40a63d62e45641a59c0aa8b421b1583ba5cdaa4',
    'end-side': '2258bf75285336d92ed8d35b4475883e83a06346ea14732fdbcef491097ffd91',
}


def within(points, low, high):
    """Whether every corner of a triangle lies in the box `low`..`high`."""
    return all(all(lo - 0.005 <= v <= hi + 0.005 for v, lo, hi in zip(p, low, high)) for p in points)


def box(low, high, material):
    """A closed box's 12 triangles, each wound to face out."""
    (x0, y0, z0), (x1, y1, z1) = low, high
    c = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    # Each face's four corners (indices into c: x*4 + y*2 + z), any order
    # round the face, and the way it faces.
    faces = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 6, 7, 5), (1, 0, 0)), ((0, 4, 5, 1), (0, -1, 0)),
             ((2, 3, 7, 6), (0, 1, 0)), ((0, 2, 6, 4), (0, 0, -1)), ((1, 5, 7, 3), (0, 0, 1))]
    out = []
    for quad, facing in faces:
        a, b, d, e = (c[i] for i in quad)
        for tri in ((a, b, d), (a, d, e)):
            u = [tri[1][i] - tri[0][i] for i in range(3)]
            v = [tri[2][i] - tri[0][i] for i in range(3)]
            n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            if sum(n[i] * facing[i] for i in range(3)) < 0:
                tri = (tri[0], tri[2], tri[1])
            out.append((list(tri), MATERIALS.index(material)))
    return out


def ground_s(tris):
    """The small station: its hip roof green with a dark edge under the
    eaves, its white roof board blue."""
    out = []
    for points, paint in tris:
        name = MATERIALS[paint]
        # The roof (its door, lower down, keeps its brown).
        if name == 'roofBrown' and min(p[2] for p in points) >= 4.0:
            paint = MATERIALS.index('stationGreen')
        # The name board on the front of the roof.
        elif name == 'tileWhite' and within(points, (-1.25, -3.50, 4.30), (1.25, -3.10, 5.36)):
            paint = MATERIALS.index('signBlue')
        out.append((points, paint))
    # The edge under the eaves (the roof is 18.22 x 8.20 m, its eaves at
    # 4.10 m), 5 cm thick, just under the roof so not on its plane.
    x, y, inside, low, high = 9.11, 4.10, 0.05, 3.93, 4.09
    for sign in (-1, 1):
        out += box((-x, sign * y - (inside if sign > 0 else 0), low), (x, sign * y + (0 if sign > 0 else inside), high), 'dark')
        out += box((sign * x - (inside if sign > 0 else 0), -y + inside, low), (sign * x + (0 if sign > 0 else inside), y - inside, high), 'dark')
    return out


def name_board(front, parapet, half):
    """A name board `half` x 2 m long standing on the front parapet (its
    face `front`, its top at `parapet`) on two short legs, set back a
    little from the face."""
    face, depth = front + 0.08, 0.26
    legs = []
    for x in (-half * 0.7, half * 0.7):
        legs += box((x - 0.06, face + 0.07, parapet - 0.02), (x + 0.06, face + 0.19, parapet + 0.30), 'steel')
    return legs + box((-half, face, parapet + 0.30), (half, face + depth, parapet + 1.50), 'signBlue')


def light_roofs(tris):
    """The flat roofs (level slate faces 6 m up and more) concrete."""
    out = []
    for points, paint in tris:
        if MATERIALS[paint] == 'roofSlate' and min(p[2] for p in points) >= 6 and max(p[2] for p in points) - min(p[2] for p in points) < 0.01:
            paint = MATERIALS.index('concrete')
        out.append((points, paint))
    return out


def ground_m(tris):
    """The middle station: its entrance canopy the game's station green,
    its flat roofs light, a name board on its front parapet."""
    out = []
    for points, paint in tris:
        if MATERIALS[paint] == 'steel' and within(points, (-5.62, -9.96, 3.08), (5.62, -9.20, 4.56)):
            paint = MATERIALS.index('stationGreen')
        out.append((points, paint))
    return light_roofs(out) + name_board(-9.50, 10.12, 4.5)


def ground_l(tris):
    """The big station: its flat roofs light, a name board on its front
    parapet."""
    return light_roofs(tris) + name_board(-11.53, 12.62, 5.5)


RESTYLE = {'s': ground_s, 's-far': ground_s, 'm': ground_m, 'm-far': ground_m, 'l': ground_l, 'l-far': ground_l}


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.split('\n\n')[1])
    source, target = sys.argv[1], sys.argv[2]
    lines = [
        '// Generated by tools/old-models/old_ground_station.py; do not edit by hand.',
        '// Palette order: ' + ', '.join(MATERIALS) + '.',
        '',
        'extension Map3DOldGroundStation {',
        '    /// Each model\'s encoded mesh, by its name.',
        '    static let encoded: [String: String] = [',
    ]
    for name, digest in SOURCES.items():
        path = os.path.join(source, PREFIX + name + '.glb')
        with open(path, 'rb') as f:
            if hashlib.sha256(f.read()).hexdigest() != digest:
                raise SystemExit(f'{path}: not the studio\'s revision-1 file')
        tris = triangles(path, MATERIALS)
        tris = RESTYLE.get(name, lambda t: t)(tris)
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
