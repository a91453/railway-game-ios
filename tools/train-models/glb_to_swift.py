#!/usr/bin/env python3
"""Write the local studio's palette-coloured GLB cars into the game's Swift
source as encoded meshes (no third-party modules).

    python3 -I tools/train-models/glb_to_swift.py \
        --enum Map3DMTRAirportLine \
        --materials aelBlue,teal,pearl,silver,cream,mtrRed,roof,mask,glass,headlamp,taillamp,steel,hardware,dark \
        --out Sources/GamePresentation/Map3DMTRAirportLineMesh.swift \
        DIR/mtr-airport-express-cab.glb DIR/mtr-airport-express-cab-far.glb ...

`--scale N` draws the models N times larger than the GLBs (the yellow tit,
decision 889, made at a real bird's 13 cm).

`--centimetres` writes each coordinate in centimetres instead of
millimetres, for a model reaching more than 32.7 m from its origin (decision
909: Hong Kong's 72 m ferry pier); the Swift side reads it with
`perMetre: 100`.

The studio builds a car in Blender with one material per palette colour
(`.claude/skills/model-look/SKILL.md`, the brief's material table) and
exports a GLB: glTF's axes, +y up, the car along x with its cab at +x, the
coupling planes at ±half its length, the rail at y 0. This tool

- gives each triangle the index of its material's name in `--materials`
  (the Swift enum's `meshPalette` holds the colours in the same order, so
  the game, not the GLB's linear baseColor, decides each colour);
- turns glTF's axes onto the game's (+x the front, +y the left, +z up) by
  a rotation, so the winding and the faces' outward sides are kept;
- writes each GLB, named by its file name, as base64 of: the vertex count
  (UInt16), each vertex x, y, z in millimetres (Int16), the triangle count
  (UInt16), each triangle's three vertex indices (UInt16) and palette index
  (UInt8), little-endian (``Map3DRedCommuter/decodedMesh(_:named:palette:)``
  reads it).
"""

import argparse
import base64
import json
import os
import struct


def read_glb(path):
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        raise SystemExit(f"{path}: not a GLB")
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    offset = 20 + length
    blob_length = struct.unpack_from("<I", data, offset)[0]
    return gltf, data[offset + 8:offset + 8 + blob_length]


def accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[acc["componentType"]]
    size = struct.calcsize(fmt)
    stride = view.get("byteStride", size * width)
    out = []
    for i in range(acc["count"]):
        values = struct.unpack_from("<" + fmt * width, blob, start + i * stride)
        out.append(values if width > 1 else values[0])
    return out


def triangles(path, materials, scale=1.0):
    gltf, blob = read_glb(path)
    # A node may only be moved (a translation, as Blender writes an
    # object's origin), not turned or scaled; each mesh is read where its
    # node puts it.
    offsets = {}
    for node in gltf.get("nodes", []):
        if any(k in node for k in ("matrix", "rotation", "scale")):
            raise SystemExit(f"{path}: node {node.get('name')} is transformed; apply the transform before export")
        if "mesh" in node:
            offsets[node["mesh"]] = node.get("translation", (0.0, 0.0, 0.0))
    out = []
    for number, mesh in enumerate(gltf["meshes"]):
        shift = offsets.get(number, (0.0, 0.0, 0.0))
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise SystemExit(f"{path}: only triangle lists are read")
            name = gltf["materials"][primitive["material"]].get("name")
            if name not in materials:
                raise SystemExit(f"{path}: material {name!r} is not in --materials")
            paint = materials.index(name)
            points = [tuple((v + d) * scale for v, d in zip(p, shift))
                      for p in accessor(gltf, blob, primitive["attributes"]["POSITION"])]
            ids = accessor(gltf, blob, primitive["indices"])
            for t in range(0, len(ids), 3):
                # glTF (x, y up, z right) -> game (x front, y left, z up).
                out.append(([(points[i][0], -points[i][2], points[i][1]) for i in ids[t:t + 3]], paint))
    return out


def encode(tris, per_metre=1000):
    index, points, faces = {}, [], []
    for pts, paint in tris:
        ids = []
        for p in pts:
            key = tuple(round(v * per_metre) for v in p)
            if any(abs(v) > 32767 for v in key):
                raise SystemExit(f"a vertex is more than {32767 / per_metre:g} m from the origin"
                                 + ("" if per_metre == 100 else "; try --centimetres"))
            if key not in index:
                index[key] = len(points)
                points.append(key)
            ids.append(index[key])
        if len(set(ids)) == 3:
            faces.append((ids, paint))
    if len(points) > 65535 or len(faces) > 65535:
        raise SystemExit("more than 65,535 vertices or triangles")
    out = bytearray(struct.pack("<H", len(points)))
    for p in points:
        out += struct.pack("<hhh", *p)
    out += struct.pack("<H", len(faces))
    for ids, paint in faces:
        out += struct.pack("<HHHB", *ids, paint)
    return base64.b64encode(bytes(out)).decode(), len(faces)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--enum", required=True, help="the Swift enum the extension is for")
    parser.add_argument("--materials", required=True, help="material names in palette order, comma-separated")
    parser.add_argument("--out", required=True)
    parser.add_argument("--scale", type=float, default=1.0,
                        help="how many times larger the game draws the models than the GLBs (default 1)")
    parser.add_argument("--centimetres", action="store_true",
                        help="write coordinates in centimetres, not millimetres (models over 32.7 m from the origin)")
    parser.add_argument("glbs", nargs="+")
    a = parser.parse_args()
    materials = a.materials.split(",")
    lines = [
        "// Generated by tools/train-models/glb_to_swift.py; do not edit by hand.",
        "// Palette order: " + ", ".join(materials) + ".",
        "",
        f"extension {a.enum} {{",
        "    /// Each model's encoded mesh, by its GLB's file name.",
        "    static let encoded: [String: String] = [",
    ]
    for path in a.glbs:
        name = os.path.splitext(os.path.basename(path))[0]
        text, count = encode(triangles(path, materials, a.scale), 100 if a.centimetres else 1000)
        print(f"{name}: {count} triangles")
        lines.append(f'        // {count} triangles.')
        lines.append(f'        "{name}": """')
        for i in range(0, len(text), 120):
            lines.append("        " + text[i:i + 120])
        lines.append('        """,')
    lines += ["    ]", "}", ""]
    open(a.out, "w").write("\n".join(lines))


if __name__ == "__main__":
    main()
