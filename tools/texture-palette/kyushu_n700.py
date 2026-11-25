#!/usr/bin/env python3
"""作者舊版的 N700 系 7000／8000 番台（九州新幹線「みずほ」「さくら」）：
有貼圖的頭車與中間車 → 一個材質一個色票色的 GLB，給
`tools/train-models/glb_to_swift.py` 寫進遊戲（決策 977）。

    uv run --with pillow --with numpy python tools/texture-palette/kyushu_n700.py \
        --cab OLD_ASSETS/models/<頭車>.glb --middle OLD_ASSETS/models/<中間車>.glb \
        --out-dir OUT [--debug]

原檔是作者自己的作品，留在作者的電腦，不進這個公開 repo；這裡只有轉檔的
做法。和 `cut_faces.py`（沿色塊的輪廓切）不同，這款車的側牆是幾個大三角形、
細節全在貼圖，所以先把貼圖讀成「長方形」（車窗、門窗、藍帶）
再照長方形的邊把三角形切成格子，窗就是整齊的長方形；前窗不是長方形，照
量出來的三個凸多邊形（`WINDSCREEN`）切；其餘的格子照多數的顏色定。

做的事：

- 貼圖分類成 車身／玻璃／藍帶／深色，標誌與文字塗回車身色（遊戲不畫字）；
  藍帶的兩條細線併成一條，上下各切出兩成當金線（真車是深藍帶鑲兩條金色細
  線）；貼圖畫成灰色的裙板歸回車身色（真車的裙板是車身色）。
- 車門（乘務員門與客室門）照貼圖上量出來的外框畫門縫線，門板是車身色。
  每扇門（門板連門縫線、門窗、門上那一段藍帶與金線）是自己的一塊：沒有一
  個面跨過門的外框，GLB 裡每扇門自己一個 mesh、一個 node（`…-door-left-1`
  由車頭端往後編號），之後做到站開門時不用再切網格。和 N700S（`n700s.py`，
  決策 979）同一種表示。
- 車頭兩頰的燈各切成兩格：外側頭燈、內側尾燈。
- 拿掉：凸出側牆 2 cm 的行先表示器薄片（和牆面相距不到 5 cm 的平行面）、
  車鼻外露的連結器（實車有蓋）、通道幌的兩個端面（編組時兩節的端面會疊在
  同一平面）、重複的面。
- 舊版把車壓成 21 m × 2.80 m × 3.82 m；這裡放回真車的 25 m 車距、3.36 m 寬、
  3.60 m 高（車體與通道幌：長 × 12.5/10.501、寬 × 1.2、高 × 3.6/3.819）。轉向
  架只平移不縮放：輪子中心距 1.50 m，就是 1,435 mm 軌距的鋼軌中心。
- 輸出的軸與 `glb_to_swift.py` 讀的一樣：+y 上、車沿 x、駕駛室在 +x、連結面
  在 ±半車長、軌面 y 0。
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# 類別，也是輸出材質的順序（`glb_to_swift.py --materials` 用同一順序）。
MATERIALS = ["whiteBlue", "navy", "gold", "glass", "dark", "headlamp", "taillamp", "doorLine"]
BODY, NAVY, GOLD, GLASS, DARK, HEAD, TAIL, LINE = range(8)
PREVIEW = [(0xD8, 0xE5, 0xEB), (0x21, 0x41, 0x68), (0x89, 0x74, 0x55), (0x40, 0x55, 0x60),
           (0x2B, 0x2F, 0x36), (0xFF, 0xF1, 0xCF), (0xE0, 0x39, 0x2C), (0x8A, 0x90, 0x99)]

# 作者原檔的 SHA-256（頭車 bc97d3e5…、中間車 fd0310c2…）：不是這兩個檔就停。
SHA256 = {
    "cab": "0388e95c22e7af6a0cb8a03c897359ca5f8c956d92b14af731fcaa5be575e73e",
    "middle": "69b448c06bead315af96f1fb1fcf22e6e0316f0a626456ece56f171aee9c4a65",
}

# 貼圖（512 × 256）上塗回車身色的框：兩處公司標誌與文字。
TEXT_MASKS = [(150, 60, 222, 112), (132, 168, 196, 190)]
# 真車的線是深藍帶、上下各鑲一條金色細線（實車照片：金 2.5 cm、深藍 10 cm）。
# 貼圖上的藍帶 15 cm 高，上下各切出這個比例當金線。
GOLD_SHARE = 0.2
# 車門在貼圖上的外框（門縫線的中心，x0, y0, x1, y1）：下排是頭車側面的乘務員
# 門與前後兩扇客室門，上排是中間車的客室門。貼圖上的門縫只有一個像素寬、顏色
# 又接近車身，讀不成色塊，所以位置直接量出來：沒有門框的話門上的小窗會孤零零
# 浮在牆上。門板是車身色，只畫門縫。
DOORS = [(200, 151, 217, 218), (222, 147, 240, 220), (443, 147, 460, 220), (455, 19, 472, 92)]
# 門縫線的寬：左右一個像素、上下兩個像素，在車上都是 5 cm 上下。
DOOR_SIDE, DOOR_END = 1, 2
# 沒有厚度的雙面薄片（頭車車頂的天線鰭）做成這麼厚的實心片。
PLATE = 0.025
# 車頭兩頰的燈在貼圖上的位置，切成外側頭燈、內側尾燈。
LAMP = (8, 211, 22, 219)

# 前窗在貼圖上的外形，三個凸多邊形：下面的大片與上面兩側往後繞的兩片
# （中間凹下去的是車頂）。照貼圖的像素邊量的，左右對稱。
WINDSCREEN = [
    [(22, 73), (84, 73), (84, 78), (72, 106), (68, 109), (38, 109), (34, 106), (22, 78)],
    [(22, 65), (24, 63), (31, 63), (39, 73), (22, 73)],
    [(67, 73), (75, 63), (82, 63), (84, 65), (84, 73)],
]

LENGTH = 12.5 / 10.501   # 連結面 ±10.501 → ±12.5（車距 25 m）
WIDTH = 3.36 / 2.80      # 側牆 ±1.40 → ±1.68
HEIGHT = 3.60 / 3.819    # 車頂 3.819 → 3.60


# ---------------------------------------------------------------- GLB 讀寫

COMPONENT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path: Path):
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit(f"{path}: not a GLB")
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    return gltf, data[20 + length + 8:], hashlib.sha256(data).hexdigest()


def accessor(gltf, blob, index) -> np.ndarray:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    width = WIDTHS[acc["type"]]
    kind = np.dtype("<" + COMPONENT[acc["componentType"]])
    stride = view.get("byteStride", kind.itemsize * width)
    if stride == kind.itemsize * width:
        out = np.frombuffer(blob, kind, acc["count"] * width, start).reshape(acc["count"], width)
    else:
        out = np.stack([np.frombuffer(blob, kind, width, start + k * stride) for k in range(acc["count"])])
    return out.astype(np.float64) if kind.kind == "f" else out.astype(np.int64)


def node_matrix(node) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    turn = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    out = np.eye(4)
    out[:3, :3] = turn @ np.diag(node.get("scale", [1, 1, 1]))
    out[:3, 3] = node.get("translation", [0, 0, 0])
    return out


def parts(gltf, blob):
    """每個掛了網格的節點：世界座標的頂點、UV、三角形、貼圖。"""
    out = []

    def walk(index, parent):
        node = gltf["nodes"][index]
        matrix = parent @ node_matrix(node)
        if "mesh" in node:
            for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                local = accessor(gltf, blob, primitive["attributes"]["POSITION"])
                world = (matrix[:3, :3] @ local.T).T + matrix[:3, 3]
                uv = accessor(gltf, blob, primitive["attributes"]["TEXCOORD_0"])
                faces = accessor(gltf, blob, primitive["indices"]).reshape(-1, 3)
                if np.linalg.det(matrix[:3, :3]) < 0:
                    faces = faces[:, ::-1]
                material = gltf["materials"][primitive["material"]]
                texture = gltf["textures"][material["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
                view = gltf["bufferViews"][gltf["images"][texture["source"]]["bufferView"]]
                start = view.get("byteOffset", 0)
                image = Image.open(io.BytesIO(blob[start:start + view["byteLength"]])).convert("RGB")
                out.append({"mesh": node["mesh"], "world": world, "uv": uv, "faces": faces, "image": image})
        for child in node.get("children", []):
            walk(child, matrix)

    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4))
    return out


def write_glb(path: Path, triangles):
    """`triangles`：（3 × 3 的頂點, 材質, 門名或 None）。車身一個 mesh、一個
    node，每扇門（門板連門縫線、門窗、門上那一段藍帶）各自一個 mesh、一個
    node；一個材質一個 primitive，頂點併起來。"""
    binary = bytearray()
    views, accessors, meshes = [], [], []
    for part in [None] + sorted({part for _, _, part in triangles if part}):
        primitives = []
        meshes.append({"name": path.stem + (f"-{part}" if part else ""), "primitives": primitives})
        for material in range(len(MATERIALS)):
            mine = [corners for corners, paint, where in triangles if paint == material and where == part]
            if not mine:
                continue
            points, lookup, indices = [], {}, []
            for corners in mine:
                for corner in corners:
                    key = tuple(int(round(v * 1000)) for v in corner)
                    if key not in lookup:
                        lookup[key] = len(points)
                        points.append([k / 1000 for k in key])
                    indices.append(lookup[key])
            position = np.array(points, "<f4")
            index = np.array(indices, "<u4")
            for array, target in ((position, 34962), (index, 34963)):
                while len(binary) % 4:
                    binary.append(0)
                views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": array.nbytes, "target": target})
                binary += array.tobytes()
            accessors.append({"bufferView": len(views) - 2, "componentType": 5126, "count": len(position), "type": "VEC3",
                              "min": position.min(0).tolist(), "max": position.max(0).tolist()})
            accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(index), "type": "SCALAR"})
            primitives.append({"attributes": {"POSITION": len(accessors) - 2}, "indices": len(accessors) - 1, "material": material})
    while len(binary) % 4:
        binary.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "tools/texture-palette/kyushu_n700.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(meshes)))}],
        "nodes": [{"mesh": number, "name": mesh["name"]} for number, mesh in enumerate(meshes)],
        "meshes": meshes,
        "materials": [{"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [((c / 255) ** 2.2) for c in PREVIEW[i]] + [1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0}}
            for i, name in enumerate(MATERIALS)],
        "buffers": [{"byteLength": len(binary)}], "bufferViews": views, "accessors": accessors,
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    path.write_bytes(b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I4s", len(text), b"JSON") + text
                     + struct.pack("<I4s", len(binary), b"BIN\0") + bytes(binary))


# ---------------------------------------------------------------- 貼圖 → 類別與長方形

def classify(image: Image.Image) -> np.ndarray:
    rgb = np.asarray(image, dtype=np.int32).copy()
    body = np.array([166, 191, 196])
    for x0, y0, x1, y1 in TEXT_MASKS:
        rgb[y0:y1, x0:x1] = body
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    high, low = rgb.max(-1), rgb.min(-1)
    labels = np.full(high.shape, BODY, np.int32)
    labels[high < 100] = GLASS
    # 貼圖下緣畫成灰色的裙板：真車的裙板是車身色，歸回車身（不歸玻璃）。
    labels[(high - low < 8) & (high >= 20) & (high < 150)] = BODY
    labels[(b - np.maximum(r, g) > 22) & (high < 140)] = NAVY
    labels[high < 12] = DARK
    # 藍帶的兩條細線之間（隔一到兩個像素的車身色）也算藍帶；門框線切斷的
    # 地方（左右三個像素內都是藍帶）也接起來。
    navy = labels == NAVY
    above = np.zeros_like(navy)
    below = np.zeros_like(navy)
    for shift in (1, 2):
        above[shift:] |= navy[:-shift]
        below[:-shift] |= navy[shift:]
    labels[(labels == BODY) & above & below] = NAVY
    navy = labels == NAVY
    left = np.zeros_like(navy)
    right = np.zeros_like(navy)
    for shift in (1, 2, 3):
        left[:, shift:] |= navy[:, :-shift]
        right[:, :-shift] |= navy[:, shift:]
    labels[(labels != NAVY) & left & right] = NAVY
    # 燈的位置另外給（LAMP），那一小塊貼圖不讀。
    x0, y0, x1, y1 = LAMP
    labels[y0 - 3:y1 + 3, x0 - 3:x1 + 3] = BODY
    return labels


def components(labels: np.ndarray):
    """四連通的同類別區塊（車身色除外）：類別、外框、像素數、遮罩。"""
    height, width = labels.shape
    seen = np.zeros(labels.shape, bool)
    out = []
    for y in range(height):
        for x in range(width):
            if seen[y, x] or labels[y, x] == BODY:
                continue
            kind = labels[y, x]
            stack, cells = [(y, x)], []
            seen[y, x] = True
            while stack:
                cy, cx = stack.pop()
                cells.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < height and 0 <= nx < width and not seen[ny, nx] and labels[ny, nx] == kind:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            ys = [c[0] for c in cells]
            xs = [c[1] for c in cells]
            out.append({"kind": int(kind), "box": (min(xs), min(ys), max(xs) + 1, max(ys) + 1), "count": len(cells), "cells": cells})
    return out


def read_rectangles(labels: np.ndarray):
    """長方形（x0, y0, x1, y1, 類別）與剩下讀不成長方形的類別圖。"""
    rectangles = []
    rest = np.full(labels.shape, BODY, np.int32)
    for part in components(labels):
        x0, y0, x1, y1 = part["box"]
        area = (x1 - x0) * (y1 - y0)
        if part["count"] < 6 or min(x1 - x0, y1 - y0) < 2:
            continue  # 雜點，與一個像素寬的門框線
        if part["count"] >= 0.86 * area and part["kind"] == NAVY and x1 - x0 > 4 * (y1 - y0):
            edge = (y1 - y0) * GOLD_SHARE
            rectangles.append((x0, y0, x1, y0 + edge, GOLD))
            rectangles.append((x0, y0 + edge, x1, y1 - edge, NAVY))
            rectangles.append((x0, y1 - edge, x1, y1, GOLD))
        elif part["count"] >= 0.86 * area:
            rectangles.append((x0, y0, x1, y1, part["kind"]))
        elif part["kind"] == GLASS and part["count"] > 800:
            continue  # 前窗：照 WINDSCREEN 的多邊形切
        else:
            for y, x in part["cells"]:
                rest[y, x] = part["kind"]
    x0, y0, x1, y1 = LAMP
    middle = (x0 + x1) // 2
    # 貼圖的左半在車上是內側（靠車鼻中線）：內側尾燈、外側頭燈。
    rectangles.append((x0, y0, middle, y1, TAIL))
    rectangles.append((middle, y0, x1, y1, HEAD))
    return rectangles, rest


# ---------------------------------------------------------------- 切三角形

def split(polygon, axis, value):
    """凸多邊形被 axis（0：x，1：y）= value 的線切成兩半：小的一邊、大的一邊。"""
    low, high = [], []
    count = len(polygon)
    for i in range(count):
        a, b = polygon[i], polygon[(i + 1) % count]
        da, db = a[axis] - value, b[axis] - value
        if da <= 0:
            low.append(a)
        if da >= 0:
            high.append(a)
        if (da < 0 < db) or (db < 0 < da):
            t = da / (da - db)
            point = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            point = (value, point[1]) if axis == 0 else (point[0], value)
            low.append(point)
            high.append(point)
    return (low if area(low) > 1e-9 else None), (high if area(high) > 1e-9 else None)


def area(polygon) -> float:
    if len(polygon) < 3:
        return 0.0
    total = 0.0
    for i in range(len(polygon)):
        a, b = polygon[i], polygon[(i + 1) % len(polygon)]
        total += a[0] * b[1] - b[0] * a[1]
    return abs(total) / 2


def centre(polygon):
    return (sum(p[0] for p in polygon) / len(polygon), sum(p[1] for p in polygon) / len(polygon))


def slabs(triangle, rectangles):
    """照長方形的邊把三角形切成格子：（多邊形, 類別或 None）。"""
    xs = [p[0] for p in triangle]
    ys = [p[1] for p in triangle]
    near = [r for r in rectangles if r[0] < max(xs) and r[2] > min(xs) and r[1] < max(ys) and r[3] > min(ys)]
    if not near:
        return [(triangle, None)]
    out = []
    rows = [triangle]
    for y in sorted({v for r in near for v in (r[1], r[3]) if min(ys) < v < max(ys)}):
        cut = []
        for polygon in rows:
            low, high = split(polygon, 1, y)
            cut += [p for p in (low, high) if p]
        rows = cut
    for row in rows:
        top, bottom = min(p[1] for p in row), max(p[1] for p in row)
        left, right = min(p[0] for p in row), max(p[0] for p in row)
        mid = (top + bottom) / 2
        across = [r for r in near if r[1] <= mid <= r[3] and r[0] < right and r[2] > left]
        cells = [row]
        for x in sorted({v for r in across for v in (r[0], r[2]) if left < v < right}):
            cut = []
            for polygon in cells:
                low, high = split(polygon, 0, x)
                cut += [p for p in (low, high) if p]
            cells = cut
        for cell in cells:
            cx, cy = centre(cell)
            kind = next((r[4] for r in across if r[0] <= cx <= r[2] and r[1] <= cy <= r[3]), None)
            out.append((cell, kind))
    return out


def split_line(polygon, nx, ny, value):
    """凸多邊形被直線 nx·x + ny·y = value 切成兩半：小的一邊、大的一邊。"""
    low, high = [], []
    count = len(polygon)
    for i in range(count):
        a, b = polygon[i], polygon[(i + 1) % count]
        da, db = a[0] * nx + a[1] * ny - value, b[0] * nx + b[1] * ny - value
        if da <= 0:
            low.append(a)
        if da >= 0:
            high.append(a)
        if (da < 0 < db) or (db < 0 < da):
            t = da / (da - db)
            point = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            low.append(point)
            high.append(point)
    return (low if area(low) > 1e-9 else None), (high if area(high) > 1e-9 else None)


def carve(polygon, region):
    """凸多邊形 polygon 落在凸多邊形 region 裡的部分，與外面剩下的幾塊。"""
    cx, cy = centre(region)
    inside, outside = polygon, []
    for i in range(len(region)):
        a, b = region[i], region[(i + 1) % len(region)]
        nx, ny = b[1] - a[1], a[0] - b[0]
        value = nx * a[0] + ny * a[1]
        if nx * cx + ny * cy > value:
            nx, ny, value = -nx, -ny, -value
        low, high = split_line(inside, nx, ny, value)
        if high:
            outside.append(high)
        inside = low
        if inside is None:
            return None, [polygon]
    return inside, outside


def samples(polygon, rest: np.ndarray):
    """多邊形裡的取樣點（約每半個像素一點）與各點的類別。"""
    ys = [p[1] for p in polygon]
    points, kinds = [], []
    step = 0.5
    y = min(ys) + step / 2
    while y < max(ys):
        hits = []
        for i in range(len(polygon)):
            a, b = polygon[i], polygon[(i + 1) % len(polygon)]
            if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                hits.append(a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]))
        if len(hits) >= 2:
            x = min(hits) + step / 2
            while x < max(hits):
                px = min(max(int(x), 0), rest.shape[1] - 1)
                py = min(max(int(y), 0), rest.shape[0] - 1)
                points.append((x, y))
                kinds.append(rest[py, px])
                x += step
        y += step
    return np.array(points, float).reshape(-1, 2), np.array(kinds, np.int64)


def settle(polygon, rest: np.ndarray, depth=0):
    """沒落在長方形裡的格子：照多數的類別；不夠一致（前窗的邊）就沿最能把
    兩種顏色分開的直線切開，再各自看。"""
    points, kinds = samples(polygon, rest)
    if len(kinds) == 0:
        cx, cy = centre(polygon)
        return [(polygon, int(rest[min(max(int(cy), 0), rest.shape[0] - 1), min(max(int(cx), 0), rest.shape[1] - 1)]))]
    counts = np.bincount(kinds, minlength=len(MATERIALS))
    best = int(counts.argmax())
    if counts[best] >= 0.93 * len(kinds) or depth >= 4 or area(polygon) < 4:
        return [(polygon, best)]
    mine = kinds == best
    normal = points[~mine].mean(0) - points[mine].mean(0)
    length = float(np.hypot(*normal))
    if length < 1e-6:
        return [(polygon, best)]
    normal /= length
    along = points @ normal
    order = np.argsort(along)
    # 門檻：多數色在小的一邊、其他在大的一邊，分錯的點最少。
    wrong = np.cumsum(~mine[order])[:-1] + (mine.sum() - np.cumsum(mine[order])[:-1])
    if len(wrong) == 0:
        return [(polygon, best)]
    at = int(wrong.argmin())
    value = (along[order[at]] + along[order[at + 1]]) / 2
    low, high = split_line(polygon, normal[0], normal[1], value)
    if low is None or high is None:
        return [(polygon, best)]
    return settle(low, rest, depth + 1) + settle(high, rest, depth + 1)


def door_at(polygon):
    """貼圖上的這一格在第幾扇門的外框裡（-1：不在門上）。門縫線的長方形已經
    沿每扇門的外框把格子切開，所以一格不是整個在門裡就是整個在門外；跨過外
    框的就停（那樣門就不是自己的一塊）。"""
    slack = 1e-6
    cx, cy = centre(polygon)
    for number, (x0, y0, x1, y1) in enumerate(DOORS):
        if x0 <= cx <= x1 and y0 <= cy <= y1:
            if not all(x0 - slack <= x <= x1 + slack and y0 - slack <= y <= y1 + slack for x, y in polygon):
                raise SystemExit(f"a face crosses the outline of door {number} at {polygon}")
            return number
        if any(x0 + slack < x < x1 - slack and y0 + slack < y < y1 - slack for x, y in polygon):
            raise SystemExit(f"a face crosses the outline of door {number} at {polygon}")
    return -1


def cut_body(part, rectangles, rest, debug=None):
    """車體：每個三角形照貼圖切開，回傳（3 × 3 的原座標頂點, 類別, 貼圖上第幾
    扇門或 -1）。"""
    width, height = part["image"].size
    pixel = np.stack([part["uv"][:, 0] * width, (part["uv"][:, 1] % 1.0) * height], 1)
    out = []
    for face in part["faces"]:
        corners = part["world"][face]
        # 行先表示器：凸出側牆的薄片。
        if np.all(np.abs(corners[:, 0]) > 1.41):
            continue
        uv = [tuple(pixel[i]) for i in face]
        e1 = (uv[1][0] - uv[0][0], uv[1][1] - uv[0][1])
        e2 = (uv[2][0] - uv[0][0], uv[2][1] - uv[0][1])
        det = e1[0] * e2[1] - e1[1] * e2[0]
        if abs(det) < 1e-6:
            # 貼圖上是一個點或一條線（車頂的天線）：照那一點的顏色。
            cx, cy = centre(uv)
            kind = int(classify_point(rectangles, rest, cx, cy))
            out.append((corners, kind, -1))
            continue

        def lift(point):
            px, py = point[0] - uv[0][0], point[1] - uv[0][1]
            s = (px * e2[1] - py * e2[0]) / det
            t = (e1[0] * py - e1[1] * px) / det
            return corners[0] + (corners[1] - corners[0]) * s + (corners[2] - corners[0]) * t

        cells = []
        for polygon, kind in slabs(uv, rectangles):
            if kind is not None:
                cells.append((polygon, kind))
                continue
            pending = [polygon]
            for region in WINDSCREEN:
                left = []
                for piece in pending:
                    inside, outside = carve(piece, region)
                    if inside:
                        cells.append((inside, GLASS))
                    left += outside
                pending = left
            for piece in pending:
                cells += settle(piece, rest)
        for polygon, kind in cells:
            points = [lift(p) for p in polygon]
            door = door_at(polygon)
            for i in range(1, len(points) - 1):
                out.append((np.array([points[0], points[i], points[i + 1]]), kind, door))
            if debug is not None:
                debug.polygon([(p[0] * 4, p[1] * 4) for p in polygon], fill=PREVIEW[kind], outline=(255, 0, 255))
    return out


def classify_point(rectangles, rest, x, y):
    for x0, y0, x1, y1, kind in rectangles:
        if x0 <= x <= x1 and y0 <= y <= y1:
            return kind
    return rest[min(max(int(y), 0), rest.shape[0] - 1), min(max(int(x), 0), rest.shape[1] - 1)]


# ---------------------------------------------------------------- 一節車

def build(path: Path, cab: bool, debug_dir: Path | None):
    gltf, blob, digest = read_glb(path)
    pieces = parts(gltf, blob)
    body = max(pieces, key=lambda p: np.ptp(p["world"][:, 2]))
    labels = classify(body["image"])
    rectangles, rest = read_rectangles(labels)
    # 門縫線排在最前面：和藍帶交叉的地方是門縫（門板上的藍帶照舊）。
    lines = []
    for x0, y0, x1, y1 in DOORS:
        lines.append((x0, y0, x0 + DOOR_SIDE, y1, LINE))
        lines.append((x1 - DOOR_SIDE, y0, x1, y1, LINE))
        lines.append((x0 + DOOR_SIDE, y0, x1 - DOOR_SIDE, y0 + DOOR_END, LINE))
        lines.append((x0 + DOOR_SIDE, y1 - DOOR_END, x1 - DOOR_SIDE, y1, LINE))
    rectangles = lines + rectangles
    canvas = draw = None
    if debug_dir:
        canvas = body["image"].resize((body["image"].width * 4, body["image"].height * 4), Image.NEAREST)
        canvas = Image.blend(canvas, Image.new("RGB", canvas.size, (0, 0, 0)), 0.6)
        draw = ImageDraw.Draw(canvas)
    triangles = cut_body(body, rectangles, rest, draw)
    if debug_dir:
        canvas.save(debug_dir / f"{path.stem[:13]}-uv-cut.png")
        shown = np.array(PREVIEW, np.uint8)[labels]
        Image.fromarray(shown).resize((labels.shape[1] * 3, labels.shape[0] * 3), Image.NEAREST).save(debug_dir / f"{path.stem[:13]}-classes.png")

    # 原座標：x 右、y 上、z 沿車身（頭車的車鼻在 -z）。車體照真車尺寸放大。
    scaled = [(corners * np.array([WIDTH, HEIGHT, LENGTH]), kind, door) for corners, kind, door in triangles]
    for piece in pieces:
        if piece is body:
            continue
        world = piece["world"]
        low, high = world.min(0), world.max(0)
        size = high - low
        if size[2] > 2.5:
            # 轉向架：位置跟著車體放大，本身不縮放。
            middle = (low[2] + high[2]) / 2
            moved = world + np.array([0, 0, middle * LENGTH - middle])
            scaled += [(moved[face], DARK, -1) for face in piece["faces"]]
        elif size[1] > 1.5:
            # 通道幌：照車體放大；兩個端面拿掉（一個在車體裡，一個在連結面上）。
            grown = world * np.array([WIDTH, HEIGHT, LENGTH])
            for face in piece["faces"]:
                corners = grown[face]
                if np.ptp(corners[:, 2]) < 1e-6:
                    continue
                scaled.append((corners, DARK, -1))
        # 其餘（車鼻外露的連結器）不要。

    # 轉成輸出的軸（+y 上、車沿 x、駕駛室在 +x）：旋轉，行列式 +1。
    turned = [(np.stack([-c[:, 2], c[:, 1], c[:, 0]], 1), kind, door) for c, kind, door in scaled]
    xs = np.concatenate([c[:, 0] for c, _, _ in turned])
    shift = -(xs.max() + xs.min()) / 2
    def normal(corners):
        return np.cross(corners[1] - corners[0], corners[2] - corners[0])

    def point(corner):
        return tuple(int(round(v * 1000)) for v in corner)

    # 同三個頂點的面只留一個。同向的是重複的面；反向的一對是沒有厚度的雙面
    # 薄片（頭車車頂的天線鰭）：只留一面會從另一側看不到，改成有厚度的實心片。
    faces, plates = {}, {}
    for corners, kind, door in turned:
        corners = corners + np.array([shift, 0, 0])
        key = frozenset(point(corner) for corner in corners)
        if len(key) < 3 or np.linalg.norm(normal(corners)) < 1e-7:
            continue  # 沒有面積
        if key not in faces:
            faces[key] = (corners, kind, door)
        elif np.dot(normal(faces[key][0]), normal(corners)) < 0:
            plates[key] = faces[key]
    out = [face for key, face in faces.items() if key not in plates]
    out += [(corners, kind, -1) for corners, kind in solid_plates([face[:2] for face in plates.values()], point, normal)]
    return name_doors(out), digest


def name_doors(triangles):
    """貼圖上的一扇門在車上是好幾扇（兩側，中間車還有前後）：照側面與沿車的
    位置分開，由車頭端（+x）往後編號。回傳（頂點, 類別, 門名或 None）與每扇門
    的範圍（公尺：沿車、離軌面、離中線）。"""
    groups = {}
    for number, (corners, kind, door) in enumerate(triangles):
        if door < 0:
            continue
        side = "left" if corners[:, 2].mean() < 0 else "right"  # 遊戲的 +y（左）是這裡的 -z
        groups.setdefault((side, door), []).append((float(corners[:, 0].mean()), number))
    names = {}
    doors = []
    for side in ("left", "right"):
        clusters = []
        for (where, _), found in sorted(groups.items()):
            if where != side:
                continue
            first = len(clusters)
            for x, number in sorted(found, reverse=True):
                if len(clusters) > first and clusters[-1][-1][0] - x < 0.6:
                    clusters[-1].append((x, number))
                else:
                    clusters.append([(x, number)])
        clusters.sort(key=lambda cluster: -cluster[0][0])
        for order, cluster in enumerate(clusters, 1):
            name = f"door-{side}-{order}"
            points = np.concatenate([triangles[number][0] for _, number in cluster])
            for _, number in cluster:
                names[number] = name
            doors.append({"name": name, "triangles": len(cluster),
                          "min": [round(float(v), 3) for v in points.min(0)], "max": [round(float(v), 3) for v in points.max(0)]})
    return [(corners, kind, names.get(number)) for number, (corners, kind, _) in enumerate(triangles)], doors


def solid_plates(plate, point, normal):
    """雙面薄片 → `PLATE` 厚的封閉實心片：兩個面各往外推一半，邊緣補上側面。"""
    out = []
    left = list(plate)
    while left:
        # 共用頂點的面是同一片。
        group = [left.pop()]
        keys = {point(c) for c in group[0][0]}
        grown = True
        while grown:
            grown = False
            for face in left[:]:
                if keys & {point(c) for c in face[0]}:
                    group.append(face)
                    keys |= {point(c) for c in face[0]}
                    left.remove(face)
                    grown = True
        towards = normal(group[0][0])
        fronts = [(c if np.dot(normal(c), towards) > 0 else c[::-1], kind) for c, kind in group]
        total = sum(normal(c) for c, _ in fronts)
        unit = total / np.linalg.norm(total)
        half = unit * PLATE / 2
        edges = {}
        for corners, kind in fronts:
            out.append((corners + half, kind))
            out.append((corners[::-1] - half, kind))
            for a, b in ((0, 1), (1, 2), (2, 0)):
                edge = (point(corners[a]), point(corners[b]))
                edges[edge] = (corners[a], corners[b], kind)
        for (a, b), (start, end, kind) in edges.items():
            if (b, a) in edges:
                continue  # 片裡面的邊
            out.append((np.stack([start + half, start - half, end - half]), kind))
            out.append((np.stack([start + half, end - half, end + half]), kind))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cab", type=Path, required=True)
    parser.add_argument("--middle", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--debug", action="store_true", help="另外輸出貼圖分類圖與 UV 切面圖")
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, path, cab in (("kyushu-n700-cab", args.cab, True), ("kyushu-n700-middle", args.middle, False)):
        (triangles, doors), digest = build(path.expanduser(), cab, args.out_dir if args.debug else None)
        expected = SHA256["cab" if cab else "middle"]
        if digest != expected:
            raise SystemExit(f"{path.name}: 不是這個工具認得的原檔（SHA-256 {digest}）")
        write_glb(args.out_dir / f"{name}.glb", triangles)
        points = np.concatenate([c for c, _, _ in triangles])
        counts = {MATERIALS[k]: sum(1 for _, kind, _ in triangles if kind == k) for k in range(len(MATERIALS))}
        report[name] = {"sha256": digest, "triangles": len(triangles), "materials": counts,
                        "min": [round(float(v), 3) for v in points.min(0)], "max": [round(float(v), 3) for v in points.max(0)],
                        "doors": doors}
    (args.out_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
