#!/usr/bin/env python3
"""Decision 940: the local studio's Taiwan post boxes (tw-post-boxes r2)
written as the 3D map's `meshy-post-boxes.m3dmodel` (version 1), standard
library only.

Each triangle keeps the GLB's position (glTF's +y up turned to the file's
+z up: x, -z, y), and takes the game's own colour of its material's name;
the GLB's colours are not read. The same input writes the same bytes.

    python3 -I tools/tw-post-boxes/build.py [--output RailwayGameApp/Resources/Models/meshy-post-boxes.m3dmodel]
"""
import argparse
import hashlib
import json
import pathlib
import struct

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/tw-post-boxes/source/tw-post-boxes.glb"
OUTPUT = ROOT / "RailwayGameApp/Resources/Models/meshy-post-boxes.m3dmodel"

# The studio's material names and the game's colours (the brief's §4):
# Map3DSceneryProp.postRed, .postGreen, .signWhite, Map3DPalette.dark.
COLOURS = {"postRed": 0xC8382E, "postGreen": 0x2E8B4E, "slotFrame": 0xF2F3F1, "slot": 0x2B2F36}

COMPONENTS = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTH = {"SCALAR": 1, "VEC3": 3}


def read_glb(data):
    if data[:4] != b"glTF":
        raise SystemExit("not a GLB")
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    at = 20 + length
    binary_length = struct.unpack_from("<I", data, at)[0]
    return gltf, data[at + 8:at + 8 + binary_length]


def accessor(gltf, binary, index):
    entry = gltf["accessors"][index]
    view = gltf["bufferViews"][entry["bufferView"]]
    code, size = COMPONENTS[entry["componentType"]]
    width = WIDTH[entry["type"]]
    stride = view.get("byteStride", size * width)
    start = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    return [struct.unpack_from("<" + code * width, binary, start + i * stride) for i in range(entry["count"])]


def build(data):
    gltf, binary = read_glb(data)
    nodes = gltf["nodes"]
    if any(key in node for node in nodes for key in ("matrix", "rotation", "scale", "translation", "children")):
        raise SystemExit("the GLB's nodes must have no transform")
    triangles = []
    for node in nodes:
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise SystemExit("only triangle lists")
            name = gltf["materials"][primitive["material"]]["name"]
            if name not in COLOURS:
                raise SystemExit(f"material {name!r} has no game colour")
            rgb = COLOURS[name]
            # Red in the low byte, alpha 255: the model's own colour.
            colour = (rgb >> 16) | (rgb & 0xFF00) | ((rgb & 0xFF) << 16) | 0xFF000000
            positions = accessor(gltf, binary, primitive["attributes"]["POSITION"])
            indices = [i[0] for i in accessor(gltf, binary, primitive["indices"])]
            for t in range(0, len(indices), 3):
                corners = [positions[i] for i in indices[t:t + 3]]
                triangles.append([((x, -z, y), colour) for x, y, z in corners])
    provenance = {
        "asset": gltf["asset"],
        "source": {
            "kind": "non-ai",
            "reference": "Taiwan's red and green post boxes, made for the game in the author's local studio (task tw-post-boxes-r2, revision-2, reviewed)",
            "revision": "a91453/railway-assets-private-2 game-art-previews/docs/art/tw-post-boxes-2026-11/revision-2 (d7bb4e6)",
            "license": "the game author's own work, used in the game and its public repository with the author's permission",
            "attribution": "the game's author",
            "files": [{"uri": "tw-post-boxes.glb", "sha256": hashlib.sha256(data).hexdigest()}],
            "materials": {name: f"#{rgb:06X}" for name, rgb in COLOURS.items()},
        },
    }
    text = json.dumps(provenance, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    out = bytearray(b"M3DM" + struct.pack("<HHII", 1, 0, len(triangles), len(text)))
    out += text + b"\0" * ((-len(text)) % 4)
    for triangle in triangles:
        out += struct.pack("<I", 0)
        for (x, y, z), colour in triangle:
            out += struct.pack("<fffI", x, y, z, colour)
    return bytes(out), len(triangles)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=pathlib.Path, default=SOURCE)
    parser.add_argument("--output", type=pathlib.Path, default=OUTPUT)
    args = parser.parse_args()
    data, count = build(args.source.read_bytes())
    args.output.write_bytes(data)
    print(f"{args.output.name}: {count} triangles, {len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
