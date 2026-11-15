#!/usr/bin/env python3
"""Turn the standing commuter of the assets repository
(railway-assets-private `game-art-previews/docs/art/commuter-figure-2026-11/
revision-1/commuter-figure-300.glb`, made with Meshy and cut down in
Blender) into the game's Swift source,
Sources/GamePresentation/Map3DCommuterFigureMesh.swift (decision 787).

    python3 -I tools/commuter-figure/to_swift.py FIGURE-300.glb \
        Sources/GamePresentation/Map3DCommuterFigureMesh.swift

What it does (no third-party modules):
- reads the GLB's five primitives, one a colour (skin, hair, shirt,
  trousers, shoes_backpack), joins the corners they share and leaves out
  triangles with no area, then keeps only the closed body (the largest
  piece joined by corners: 288 triangles), dropping six loose slivers;
- turns the figure to face straight ahead (away from its backpack);
- mends the colours the generated texture gave wrongly: the hair triangle
  over the forehead and the one over the ear become skin, and the dark
  triangles on the chest and shoulders (the backpack's straps, which at
  this size read as holes in the shirt) become shirt;
- makes the walking figure: the legs swung 16 degrees about the hip,
  one forward and one back, the hands (in the pockets) staying, the
  figure lowered so that its feet stand on the ground;
- turns both into the game's axes (+x the front, +y the left, +z up, the
  feet's middle at the origin);
- writes each as base64 of: the vertex count (UInt16), each vertex x, y,
  z in millimetres (Int16), the triangle count (UInt16), each triangle's
  three vertex indices (UInt16) and palette index (UInt8), little-endian:
  Map3DRedCommuter.decodedMesh's format, with Map3DCommuterFigure's
  palette (0 skin, 1 hair, 2 the shirt, in the instance's colour,
  3 trousers, 4 shoes and backpack).
"""

import base64
import hashlib
import json
import math
import struct
import sys

NAMES = ["skin", "hair", "shirt", "trousers", "shoes_backpack"]
SKIN, HAIR, SHIRT, TROUSERS, DARK = range(5)
STRIDE_DEGREES = 16.0
HIP = 0.86


def read(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    offset = 20 + length
    blob_length = struct.unpack_from("<I", data, offset)[0]
    blob = data[offset + 8:offset + 8 + blob_length]

    def accessor(index):
        acc = gltf["accessors"][index]
        view = gltf["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        width = {"SCALAR": 1, "VEC3": 3}[acc["type"]]
        fmt = {5126: "f", 5123: "H", 5125: "I"}[acc["componentType"]]
        size = struct.calcsize(fmt)
        stride = view.get("byteStride", size * width)
        out = []
        for i in range(acc["count"]):
            values = struct.unpack_from("<" + fmt * width, blob, start + i * stride)
            out.append(values if width > 1 else values[0])
        return out

    keys, points, faces, paints = {}, [], [], []
    for primitive in gltf["meshes"][0]["primitives"]:
        paint = NAMES.index(gltf["materials"][primitive["material"]]["name"])
        position = accessor(primitive["attributes"]["POSITION"])
        ids = accessor(primitive["indices"])
        for t in range(0, len(ids), 3):
            corner = []
            for i in ids[t:t + 3]:
                key = tuple(round(c, 5) for c in position[i])
                if key not in keys:
                    keys[key] = len(points)
                    points.append(list(position[i]))
                corner.append(keys[key])
            if len(set(corner)) == 3:
                faces.append(corner)
                paints.append(paint)
    return points, faces, paints, hashlib.sha256(data).hexdigest()


def body(faces, paints):
    """Only the largest piece of faces joined by their corners: the six
    loose slivers beside the hand, the sleeves and over the backpack (the
    local studio's review, round 1, F1) are left out; the body is closed."""
    parent = {}

    def root(i):
        while parent.setdefault(i, i) != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for f in faces:
        for i in f[1:]:
            parent[root(i)] = root(f[0])
    sizes = {}
    for f in faces:
        sizes[root(f[0])] = sizes.get(root(f[0]), 0) + 1
    largest = max(sizes, key=sizes.get)
    kept = [(f, p) for f, p in zip(faces, paints) if root(f[0]) == largest]
    return [f for f, _ in kept], [p for _, p in kept]


def compacted(points, faces):
    """The points the faces use, renumbered in order."""
    used = sorted({i for f in faces for i in f})
    index = {old: new for new, old in enumerate(used)}
    return [points[i] for i in used], [[index[i] for i in f] for f in faces]


def centre(points, face):
    return [sum(points[i][k] for i in face) / 3 for k in range(3)]


def mean(rows):
    return [sum(r[k] for r in rows) / len(rows) for k in range(3)]


def faced(points, faces, paints):
    """Turned about the vertical so that the front (away from the
    backpack, the dark triangles at the torso's height) is +z."""
    centres = [centre(points, f) for f in faces]
    torso = mean([c for c in centres if 0.9 < c[1] < 1.4])
    pack = mean([c for c, p in zip(centres, paints) if p == DARK and c[1] > 0.9])
    angle = math.atan2(torso[0] - pack[0], torso[2] - pack[2])
    cos, sin = math.cos(-angle), math.sin(-angle)
    return [[x * cos + z * sin, y, -x * sin + z * cos] for x, y, z in points]


def mended(points, faces, paints):
    """The colours the texture gave wrongly (see the module's notes)."""
    centres = [centre(points, f) for f in faces]
    head = mean([c for c in centres if c[1] > 1.45])
    out = []
    for c, paint in zip(centres, paints):
        front = c[2] - head[2]
        if paint == HAIR and ((c[1] < 1.6 and front > 0.08) or (c[1] < 1.53 and front > -0.04)):
            paint = SKIN
        elif paint == DARK and 0.85 < c[1] < 1.45 and c[2] > -0.065:
            paint = SHIRT
        out.append(paint)
    return out


def walking(points, faces, paints):
    """The legs swung about the hip, the left (+x) forward."""
    held = {i for f, p in zip(faces, paints) if p == SKIN for i in f}
    legs = [points[i] for f, p in zip(faces, paints) if p == TROUSERS for i in f if points[i][1] < 0.6]
    middle = mean(legs)
    out = []
    for i, (x, y, z) in enumerate(points):
        weight = 0.0 if i in held else min(max((HIP - y) / 0.12, 0.0), 1.0)
        side = min(max((x - middle[0]) / 0.05, -1.0), 1.0)
        turn = math.radians(STRIDE_DEGREES) * side * weight
        dy, dz = y - HIP, z - middle[2]
        out.append([x, HIP + dz * math.sin(turn) + dy * math.cos(turn), middle[2] + dz * math.cos(turn) - dy * math.sin(turn)])
    low = min(p[1] for p in out)
    return [[x, y - low, z] for x, y, z in out]


def game_axes(points, origin):
    """glTF's (+y up, the front +z, the left +x) onto the game's (+x the
    front, +y the left, +z up): a rotation, so the winding is kept."""
    return [[z - origin[2], x - origin[0], y] for x, y, z in points]


def encoded(points, faces, paints):
    out = bytearray(struct.pack("<H", len(points)))
    for p in points:
        out += struct.pack("<hhh", *(round(c * 1000) for c in p))
    out += struct.pack("<H", len(faces))
    for f, p in zip(faces, paints):
        out += struct.pack("<HHHB", *f, p)
    return base64.b64encode(bytes(out)).decode()


def wrapped(text, indent="        "):
    return "\n".join(indent + text[i:i + 100] for i in range(0, len(text), 100))


def main():
    source, target = sys.argv[1], sys.argv[2]
    points, faces, paints, digest = read(source)
    low = min(p[1] for p in points)
    points = [[x, y - low, z] for x, y, z in points]
    points = faced(points, faces, paints)
    paints = mended(points, faces, paints)
    feet = [p for p in points if p[1] < 0.05]
    origin = mean(feet)
    # After the turn, the mending and the origin, which the slivers took
    # part in (as the studio's reviewed GLBs were made).
    faces, paints = body(faces, paints)
    points, faces = compacted(points, faces)
    standing = game_axes(points, origin)
    walk = game_axes(walking(points, faces, paints), origin)
    counts = {NAMES[k]: paints.count(k) for k in range(5)}
    text = f"""// Generated by tools/commuter-figure/to_swift.py from the assets
// repository's commuter-figure-2026-11/revision-1/commuter-figure-300.glb
// (sha256 {digest[:16]}…). Do not edit: run the tool again
// (tools/commuter-figure/README.md).
//
//   {len(faces)} triangles a figure, {len(points)} corners
//   {", ".join(f"{k} {v}" for k, v in counts.items())}

extension Map3DCommuterFigure {{
    /// The figure standing, base64 of ``decodedMesh``'s bytes.
    static let encodedStanding = \"\"\"
{wrapped(encoded(standing, faces, paints))}
        \"\"\"

    /// The figure mid-stride, its left leg forward.
    static let encodedWalking = \"\"\"
{wrapped(encoded(walk, faces, paints))}
        \"\"\"
}}
"""
    open(target, "w").write(text)
    print(f"{len(faces)} triangles, {len(points)} corners, {counts}, sha256 {digest}")


if __name__ == "__main__":
    main()
