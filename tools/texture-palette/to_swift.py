#!/usr/bin/env python3
"""Turn cut_faces.py's GLB of the owner's old car e752e7a2 into the game's
Swift source, Sources/GamePresentation/Map3DRedCommuterMesh.swift.

    python3 -I tools/texture-palette/to_swift.py CUT.glb \
        Sources/GamePresentation/Map3DRedCommuterMesh.swift

What it does (no third-party modules):
- reads the GLB's two primitives (`body`, `glass`) and each triangle's
  COLOR_0 (linear, as glTF stores it), turned back to sRGB;
- gives each triangle a palette index (Map3DRedCommuter.meshPalette); the
  glass primitive is its own index, whatever its colour;
- turns the car from glTF's axes (+y up, the car along z) to the game's
  (+x the front, its cab there, +y the left, +z up, the car's middle at
  x 0 and its lowest point at z 0);
- writes the cab car, and a middle car made of the cab car's back half and
  that half mirrored (the cab car has only one plain end);
- each as base64 of: the vertex count (UInt16), each vertex x, y, z in
  millimetres (Int16), the triangle count (UInt16), each triangle's three
  vertex indices (UInt16) and palette index (UInt8), little-endian.
"""

import base64
import json
import struct
import sys

# The sRGB colours cut_faces.py paints with, and their palette indices in
# Map3DRedCommuter.meshPalette (the glass is index 6, from its primitive).
COLOURS = {
    0x8A9099: 0,  # steel: roof, door frames
    0xC9CECC: 1,  # grey-white body
    0x2B2F36: 2,  # dark: underframe, gangway, the cab's dark panels
    0xE9EBE5: 3,  # the light band round the windows
    0x711604: 4,  # the red body (Map3DPalette.trainRed in the game)
    0x2F6DB5: 5,  # blue marks
}
GLASS = 6


def read_glb(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    offset = 20 + length
    blob_length = struct.unpack_from("<I", data, offset)[0]
    blob = data[offset + 8:offset + 8 + blob_length]
    return gltf, blob


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


def to_srgb(linear):
    c = max(0.0, min(1.0, linear))
    s = c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return round(s * 255)


def triangles(path):
    gltf, blob = read_glb(path)
    out = []
    for primitive in gltf["meshes"][0]["primitives"]:
        material = gltf["materials"][primitive["material"]]
        glass = material.get("name") == "glass" or primitive.get("extras", {}).get("glass")
        points = accessor(gltf, blob, primitive["attributes"]["POSITION"])
        colours = accessor(gltf, blob, primitive["attributes"]["COLOR_0"])
        ids = accessor(gltf, blob, primitive["indices"])
        for t in range(0, len(ids), 3):
            corner = ids[t:t + 3]
            r, g, b = (to_srgb(colours[corner[0]][k]) for k in range(3))
            hexa = r << 16 | g << 8 | b
            if glass:
                paint = GLASS
            elif hexa in COLOURS:
                paint = COLOURS[hexa]
            else:
                raise SystemExit(f"colour #{hexa:06X} is not one cut_faces.py paints with")
            out.append(([points[i] for i in corner], paint))
    return out


def cab_end(tris):
    """+1 when the windscreen (the glass at the car's end) is at the GLB's +z."""
    zs = [p[2] for pts, _ in tris for p in pts]
    low, high = min(zs), max(zs)
    near = lambda end: sum(1 for pts, paint in tris if paint == GLASS and all(abs(p[2] - end) < 1.5 for p in pts))
    return 1 if near(high) > near(low) else -1


def turned(tris):
    """The GLB's axes (glTF: +y up, the car along z) onto the game's: its
    length onto x with the cab at +x, up onto z, and across onto y so the
    turn is a rotation and keeps the winding; the middle at x 0 and the
    lowest point at z 0."""
    s = cab_end(tris)
    out = [([(s * p[2], s * p[0], p[1]) for p in pts], paint) for pts, paint in tris]
    xs = [p[0] for pts, _ in out for p in pts]
    xmid = (min(xs) + max(xs)) / 2
    zmin = min(p[2] for pts, _ in out for p in pts)
    return [([(x - xmid, y, z - zmin) for x, y, z in pts], paint) for pts, paint in out]


def clip_back(tris):
    """The triangles' parts at x ≤ 0."""
    out = []
    for pts, paint in tris:
        poly = []
        for i in range(3):
            a, b = pts[i], pts[(i + 1) % 3]
            if a[0] <= 0:
                poly.append(a)
            if (a[0] <= 0) != (b[0] <= 0):
                t = a[0] / (a[0] - b[0])
                poly.append((0.0, a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])))
        for k in range(1, len(poly) - 1):
            out.append(([poly[0], poly[k], poly[k + 1]], paint))
    return out


def middle(tris):
    back = clip_back(tris)
    # Mirrored in x, its winding reversed so it still faces out.
    front = [([(-x, y, z) for x, y, z in reversed(pts)], paint) for pts, paint in back]
    return back + front


def encode(tris):
    index, points, faces = {}, [], []
    for pts, paint in tris:
        ids = []
        for p in pts:
            key = tuple(round(v * 1000) for v in p)
            if key not in index:
                index[key] = len(points)
                points.append(key)
            ids.append(index[key])
        if len(set(ids)) == 3:
            faces.append((ids, paint))
    assert len(points) < 65536 and len(faces) < 65536
    out = bytearray(struct.pack("<H", len(points)))
    for x, y, z in points:
        out += struct.pack("<hhh", x, y, z)
    out += struct.pack("<H", len(faces))
    for ids, paint in faces:
        out += struct.pack("<HHHB", *ids, paint)
    return bytes(out), len(faces)


def wrapped(data):
    text = base64.b64encode(data).decode()
    return "\n".join("        " + text[i:i + 100] for i in range(0, len(text), 100))


def main():
    source, target = sys.argv[1], sys.argv[2]
    cab = turned(triangles(source))
    cab_bytes, cab_count = encode(cab)
    middle_bytes, middle_count = encode(middle(cab))
    with open(target, "w") as f:
        f.write(f"""// Generated by tools/texture-palette/to_swift.py from cut_faces.py's cut of
// the owner's old car e752e7a2 (SwiftRailMac). Do not edit: run the tool
// again (tools/texture-palette/README.md).
//
//   cab car: {cab_count} triangles
//   middle car: {middle_count} triangles

extension Map3DRedCommuter {{
    /// The cab car, its cab at +x, base64 of ``decodedMesh(_:named:)``'s bytes.
    static let encodedCab = \"\"\"
{wrapped(cab_bytes)}
        \"\"\"

    /// The middle car: the cab car's back half and that half mirrored.
    static let encodedMiddle = \"\"\"
{wrapped(middle_bytes)}
        \"\"\"
}}
""")
    print(f"cab {cab_count} triangles, middle {middle_count} triangles")


if __name__ == "__main__":
    main()
