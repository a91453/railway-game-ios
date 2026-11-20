#!/usr/bin/env python3
"""Write the owner's earlier Sun Moon Lake models into the game's Swift
source as encoded meshes (no third-party modules). Decision 879.

    python3 -I tools/sunmoon-landmarks/glb_to_swift.py \
        --assets <railway-reference-private>/OpenWorld/reference_snapshot/play/assets/sunmoon \
        --out Sources/GamePresentation/Map3DSunMoonLandmarkMeshes.swift

The GLBs are the owner's own (`a91453/railway-reference-private`,
`OpenWorld/reference_snapshot/play/assets/sunmoon/`, made in Blender;
`manifest.json` there: metres, +X right, +Y up, +Z front, the origin on
the ground or a boat's waterline). `play/src/sunmoon-main.js` stands them
in its scene with a scale each (`assetParts`), which this tool bakes in:

    pier      0.67 × 1 × 2.5    (the Shuishe pier, 7.9 m by 30 m)
    temple    2.1 × 1.3 × 2     (the Wenwu temple, 37 m by 27 m, 14.5 m tall)
    boat, pavilion  as they are

This tool

- applies each node's translation, rotation and scale, then the scene's
  scale above;
- welds the vertices at 1 cm and turns glTF's axes onto the landmark's own
  (+x right, +y back, +z up; the front faces -y) by a rotation, so the
  winding is kept;
- gives each triangle the index of its material's name in ``MATERIALS``
  (``Map3DSunMoonLandmark.materialColours`` holds the game's colour for
  each, so the game, not the GLB, decides each colour; the GLBs' textures
  are not read);
- writes each model as base64 of: the vertex count (UInt16), each vertex
  x, y and z in centimetres (Int16), the triangle count (UInt16), each
  triangle's three vertex indices (UInt16) and material index (UInt8),
  little-endian (``Map3DSunMoonLandmark/decoded(_:)`` reads it).

`pavilion-lod1.glb` is in the manifest but not in the snapshot, so the
pavilion has no far model.
"""

import argparse
import base64
import json
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hk-landmarks"))
import ground_plate  # noqa: E402

MATERIALS = ["stone", "wood", "tile", "red", "gold", "plaster", "metal", "rubber", "boat", "accent", "glass", "seat"]

# sunmoon-main.js's `assetParts`: each asset's scale (x, y up, z).
SCALES = {"pier": (0.67, 1, 2.5), "temple": (2.1, 1.3, 2), "boat": (1, 1, 1), "pavilion": (1, 1, 1)}
MODELS = ["pier", "pier-lod1", "temple", "temple-lod1", "boat", "boat-lod1", "pavilion"]


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


def rotate(q, v):
    """`v` turned by the unit quaternion `q` (x, y, z, w)."""
    x, y, z, w = q
    vx, vy, vz = v
    # t = 2 q × v; v' = v + w t + q × t
    tx, ty, tz = 2 * (y * vz - z * vy), 2 * (z * vx - x * vz), 2 * (x * vy - y * vx)
    return (vx + w * tx + y * tz - z * ty, vy + w * ty + z * tx - x * tz, vz + w * tz + x * ty - y * tx)


def encode(path, scale):
    gltf, blob = read_glb(path)
    keys, points, triangles = {}, [], []
    for node in gltf["nodes"]:
        if "mesh" not in node:
            continue
        if "matrix" in node or "children" in node:
            raise SystemExit(f"{path}: node {node.get('name')} has a matrix or children")
        t = node.get("translation", (0, 0, 0))
        q = node.get("rotation", (0, 0, 0, 1))
        s = node.get("scale", (1, 1, 1))
        flipped = s[0] * s[1] * s[2] < 0
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            name = gltf["materials"][prim["material"]]["name"]
            if name not in MATERIALS:
                raise SystemExit(f"{path}: material {name} is not in the table")
            paint = MATERIALS.index(name)
            pos = accessor(gltf, blob, prim["attributes"]["POSITION"])
            idx = accessor(gltf, blob, prim["indices"]) if "indices" in prim else list(range(len(pos)))
            local = []
            for p in pos:
                x, y, z = rotate(q, (p[0] * s[0], p[1] * s[1], p[2] * s[2]))
                x, y, z = (x + t[0]) * scale[0], (y + t[1]) * scale[1], (z + t[2]) * scale[2]
                # glTF (+x right, +y up, +z front) onto (+x right, +y back, +z up).
                key = (round(x * 100), round(-z * 100), round(y * 100))
                if key not in keys:
                    keys[key] = len(points)
                    points.append(key)
                local.append(keys[key])
            for k in range(0, len(idx), 3):
                a, b, c = local[idx[k]], local[idx[k + 1]], local[idx[k + 2]]
                if flipped:
                    b, c = c, b
                if a != b and b != c and a != c:
                    triangles.append((a, b, c, paint))
    if len(points) > 65535 or len(triangles) > 65535:
        raise SystemExit(f"{path}: too many vertices or triangles")
    out = bytearray(struct.pack("<H", len(points)))
    for p in points:
        if not all(-32768 <= v <= 32767 for v in p):
            raise SystemExit(f"{path}: vertex {p} cm out of range")
        out += struct.pack("<hhh", *p)
    out += struct.pack("<H", len(triangles))
    for a, b, c, paint in triangles:
        out += struct.pack("<HHHB", a, b, c, paint)
    low = [min(p[k] for p in points) / 100 for k in range(3)]
    high = [max(p[k] for p in points) / 100 for k in range(3)]
    return bytes(out), len(points), len(triangles), low, high


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--allow-ground-plate", action="store_true", help="a level plate beyond the body belongs to the model")
    args = parser.parse_args()
    lines = [
        "// Generated by tools/sunmoon-landmarks/glb_to_swift.py from the owner's",
        "// earlier Sun Moon Lake models (railway-reference-private,",
        "// OpenWorld/reference_snapshot/play/assets/sunmoon). Do not edit by hand.",
        "",
        "extension Map3DSunMoonLandmark {",
        "    /// Each model, by its file name, as `tools/sunmoon-landmarks/glb_to_swift.py` encodes it.",
        "    static let encodedMeshes: [String: String] = [",
    ]
    for name in MODELS:
        data, v, t, low, high = encode(os.path.join(args.assets, name + ".glb"), SCALES[name.replace("-lod1", "")])
        ground_plate.check(data, name, signed_z=True, allow=args.allow_ground_plate)
        print(f"{name}: {v} vertices, {t} triangles, {len(data)} bytes, {low} to {high}")
        lines.append(f"        // {v} vertices, {t} triangles; {low} to {high} m.")
        lines.append(f'        "{name}": "{base64.b64encode(data).decode()}",')
    lines += ["    ]", "}", ""]
    open(args.out, "w").write("\n".join(lines))


if __name__ == "__main__":
    main()
