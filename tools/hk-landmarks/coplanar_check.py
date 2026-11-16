"""Count pairs of faces of different materials on nearly the same plane
(0.5 mm to 5 cm apart) in each GLB: where the map may flicker.

    python3 -I tools/hk-landmarks/coplanar_check.py [GLB ...]

With no GLB it reads every `*.glb` in the current folder. Each line gives
two counts:

- `boxes`: the pairs whose bounding boxes overlap. It counts too many
  (two faces side by side on one wall count), never too few.
- `overlap`: of those, the pairs whose triangles really overlap on the
  plane by more than 1 cm2. This is the number a model must bring to 0.

Needs numpy (Blender's Python has it:
/Applications/Blender.app/Contents/Resources/5.3/python/bin/python3.13).
"""
import glob
import json
import struct
import sys
from collections import defaultdict

import numpy as np


def load(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    blob = data[20 + length + 8:]
    triangles, materials = [], []
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            view = gltf["bufferViews"][acc["bufferView"]]
            points = np.frombuffer(blob, np.float32, acc["count"] * 3,
                                   view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(-1, 3)
            if "indices" in prim:
                acc = gltf["accessors"][prim["indices"]]
                view = gltf["bufferViews"][acc["bufferView"]]
                kind = {5125: np.uint32, 5123: np.uint16}[acc["componentType"]]
                index = np.frombuffer(blob, kind, acc["count"],
                                      view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(-1, 3)
            else:
                index = np.arange(len(points)).reshape(-1, 3)
            triangles.append(points[index].astype(np.float64))
            materials += [prim["material"]] * len(index)
    return np.concatenate(triangles), np.array(materials)


def shared_area(subject, clipper):
    """The area two triangles on one plane share (Sutherland-Hodgman)."""
    def area(p):
        return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))
    if area(clipper) < 0:
        clipper = clipper[::-1]
    out = list(subject)
    for i in range(len(clipper)):
        a, b = clipper[i], clipper[(i + 1) % len(clipper)]
        inside, out = out, []
        if not inside:
            break

        def side(p):
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        for j in range(len(inside)):
            p, q = inside[j], inside[(j + 1) % len(inside)]
            sp, sq = side(p), side(q)
            if sp >= 0:
                out.append(p)
            if (sp >= 0) != (sq >= 0) and sp != sq:
                t = sp / (sp - sq)
                out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return abs(area(out)) if len(out) >= 3 else 0.0


def count(path):
    T, M = load(path)
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    a = np.linalg.norm(n, axis=1)
    ok = a > 1e-6
    T, M, n = T[ok], M[ok], n[ok] / a[ok, None]
    d = (n * T[:, 0]).sum(1)
    lo, hi = T.min(1), T.max(1)
    groups = defaultdict(list)
    for i, key in enumerate(map(tuple, np.round(n * 20).astype(int))):
        groups[key].append(i)
    boxes = overlap = 0
    for group in groups.values():
        if len(group) < 2:
            continue
        group = np.array(group)
        order = group[np.argsort(d[group])]
        dd = d[order]
        for x in range(len(order)):
            y = x + 1
            while y < len(order) and dd[y] - dd[x] < 0.05:
                i, j = order[x], order[y]
                if dd[y] - dd[x] > 0.0005 and M[i] != M[j] and np.all(lo[i] <= hi[j]) and np.all(lo[j] <= hi[i]):
                    boxes += 1
                    u = T[i, 1] - T[i, 0]
                    u /= np.linalg.norm(u)
                    w = np.cross(n[i], u)
                    flat = lambda t: [((p - T[i, 0]) @ u, (p - T[i, 0]) @ w) for p in t]
                    if shared_area(flat(T[i]), flat(T[j])) > 1e-4:
                        overlap += 1
                y += 1
    return len(T), boxes, overlap


if __name__ == "__main__":
    for path in sys.argv[1:] or sorted(glob.glob("*.glb")):
        triangles, boxes, overlap = count(path)
        print(f"{path.rsplit('/', 1)[-1]}: {triangles} triangles, boxes {boxes}, overlap {overlap}")
