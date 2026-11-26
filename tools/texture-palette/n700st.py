#!/usr/bin/env python3
"""作者舊版的 N700S 三節網格 → 台灣高鐵 N700ST 塗裝：一個材質一個色票色的 GLB，
給 `tools/train-models/glb_to_swift.py` 寫進遊戲。

    uv run --with pillow --with numpy python revision-2/tools/n700st.py \
        --cab OLD/item_c264b30bdcd2d6c06bd11a45.glb \
        --middle OLD/item_2cf2255b345e32868908de7e.glb \
        --pantograph OLD/item_8d903762bac47c2b84da2a0f.glb \
        --out-dir revision-2

設計原則（照派工單 `game-art-previews/docs/art/n700st-paint-2026-11/README.md`）：
- 舊版 N700S 三節（c264b30b 頭車、2cf2255b 中間車、8d903762 集電弓車）的幾何外形、
  門位置與獨立 node、窗位、頭尾燈、27.35 m／25.00 m 車長、3.36 m 寬、3.60 m 高、
  1.435 m 軌距與淺 V 全周幌（`HOOD_GAP=0.02, HOOD_TAPER=0.025`）全部沿用 `n700s.py`，
  不動任何外形頂點位置。
- 刪除 N700S 原有的兩條藍線與車鼻藍尖，還原白色車身，並補齊四邊門框線。
- 照實車參考圖（`ref-thsrc-render-2025-08.jpg`、`ref-ettoday-photo-2026-04.jpg`）與
  `thsr_700t.py` 3D 切塊做法，在車身上直接切出台灣高鐵 N700ST 塗裝：
  1. 駕駛室擋風玻璃外圍加上平滑黑色橢圓遮罩（`dark`，在 3D 俯視 `(x, z)` 切面，
     跨過 UV 接縫、左右對稱、包住前窗與兩側小窗及車頂眉部）；
  2. 頭車第一扇門附近大塊高鐵橘色斜塊（`orange`，前緣往前下方斜至裙板上緣、
     蓋住乘務員門與第一扇客室門下半段）＋緊接平行黑色斜帶（`dark`，共用同一斜邊、
     從裙板上緣斜至橘帶底緣）；
  3. 側身與中間車／集電弓車窗下緊鄰雙線：上方細黑線（`dark`，y 1.74–1.84 m）、
     下方略寬橘帶（`orange`，y 1.52–1.74 m），深灰裙板（`grey`），全周幌不帶雙線；
  4. 零標誌、零文字、零車號；色票完全沿用遊戲 700T 與 N700S 既有 7 格。

本檔為獨立腳本（內含自 `kyushu_n700.py`／`n700s.py` 沿用的讀檔與切多邊形函式），
僅需 `numpy` 與 `Pillow`。
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# 類別與輸出材質順序（`glb_to_swift.py --materials white,orange,grey,glass,dark,headlamp,taillamp`）。
MATERIALS = ["white", "orange", "grey", "glass", "dark", "headlamp", "taillamp"]
BODY, ORANGE, GREY, GLASS, DARK, HEAD, TAIL = range(7)
PREVIEW = [
    (0xF2, 0xF0, 0xEA),  # white   : Map3DTrainShapeRefresh.highSpeedBodyColor (#F2F0EA)
    (0xEA, 0x6A, 0x1E),  # orange  : Map3DTrainShapeRefresh.highSpeedBandColor (#EA6A1E)
    (0x8A, 0x90, 0x99),  # grey    : Map3DPalette.steel (#8A9099)
    (0x26, 0x31, 0x3D),  # glass   : Map3DTrainStyle.glass (#26313D)
    (0x2B, 0x2F, 0x36),  # dark    : Map3DPalette.dark (#2B2F36)
    (0xFF, 0xF4, 0xD6),  # headlamp: Map3DTrainStyle.headlamp (#FFF4D6)
    (0xE0, 0x39, 0x2C),  # taillamp: Map3DPalette.lantern (#E0392C)
]


def _srgb_to_linear(channel: int) -> float:
    s = channel / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

# 作者舊版 N700S 原檔的 SHA-256（與 n700s.py 一致；不是這三個檔就停）。
SHA256 = {
    "cab": "214871fd7c9741d999fd64c1796ed66d6e3eedb9a16542db17dcd959ecedfc53",
    "middle": "2cf2255b345e32868908de7e88d2b3b66e8e981f3d63902b6661439f4551dd04",
    "pantograph": "d2dfea89a6ae0e924c440d57561fb2c07bc1f23b0e99db9361cc5b0b8cdd3dd3",
}

# 貼圖（1,024 × 1,024）上塗回車身色的框：標誌、文字、小牌、行先表示器、踏板陰影。
TEXT_MASKS = [
    (3, 545, 31, 615), (668, 298, 698, 345), (733, 300, 772, 322), (818, 303, 838, 320),
    (674, 553, 734, 577), (739, 546, 767, 592), (836, 552, 980, 632), (676, 672, 728, 694),
    (161, 793, 189, 838), (212, 800, 248, 820), (880, 793, 908, 840),
    (612, 438, 665, 450), (770, 684, 830, 696), (100, 930, 160, 944), (910, 930, 970, 944),
    (425, 466, 457, 473), (984, 710, 1024, 717), (0, 957, 42, 965), (938, 958, 982, 965),
]
SKIRT_BANDS = [(473, 529), (717, 771), (965, 1024)]
LAMP = (128, 408, 175, 425)

# 前窗（沿用 n700s.py 貼圖量測，三個凸多邊形，對稱軸 v=234）。
_ARM = [(245, 182), (252, 170), (296, 169), (334, 177), (367, 189), (385, 205), (253, 205), (246, 196)]
WINDSCREEN = [
    [(282, 205), (385, 205), (390, 216), (393, 234), (390, 252), (385, 263), (282, 263)],
    _ARM,
    [(x, 468 - y) for x, y in reversed(_ARM)],
]

# 舊版 N700S 藍線區域（全部抹回車身白，不切藍線）。
OLD_NOSE_LINE_BOX = (280, 365, 600, 420)
OLD_LINES = [
    (600, 385, 1024, 418),
    (0, 633, 1024, 664),
    (0, 879, 1024, 910),
]

# 門外框（沿用 n700s.py 五扇門位置；因改畫 N700ST 塗裝，四邊門框線補齊不留舊藍線缺口）。
DOORS = [
    (555, 314, 593, 439),  # 頭車乘務員門
    (614, 304, 663, 445),  # 頭車前客室門
    (772, 551, 826, 692),  # 頭車後客室門 / 中間車門
    (102, 797, 156, 938),  # 中間車 / 集電弓車門
    (913, 797, 967, 938),  # 中間車 / 集電弓車門
]
DOOR_FRAME = 3
DOOR_SILL = 4

# 真車尺寸與全周幌參數（與 n700s.py 完全相同）。
LENGTH = 12.5 / 10.501
CAB_REAL = 27.35
BAY = (-4.09, 0.9195)
CAB_WINDOWS = 13
CAB_PITCH = 1.023
CAB_WINDOW = 0.52
CAB_DOOR = 0.74
WIDTH = 3.36 / 2.80
HEIGHT = 3.60 / 3.625
HOOD_GAP = 0.02
HOOD_TAPER = 0.025
HOOD_YAW = 4.2
COUPLER = (0.95, 1.05)

BOGIE = -2
GANGWAY = -3
TOUCH = 4e-4
FOLD = 30

# ---------------------------------------------------------------- N700ST 3D 塗裝參數
# 高度（公尺，軌面起算；對照 ref-thsrc-render-2025-08.jpg 與 ref-ettoday-photo-2026-04.jpg）：
# 客室窗底 1.98 m、灰裙板上緣 0.95 m；窗下黑線 1.74–1.84 m（細，0.10 m），
# 橘帶 1.52–1.74 m（略寬，0.22 m，緊貼黑線下方），下方白身 0.57 m 接灰裙板。
BLACK_Y = (1.74, 1.84)
ORANGE_Y = (1.52, 1.74)
SKIRT_REF_Y = 0.95
SKIRT_CUT_Y = 0.85

# 頭車大橘斜塊與平行黑色斜帶（沿車 x，車頭朝 +x）：
# 乘務員門 x=5.00..5.50、前客室門 x=3.99..4.73、第一客室窗 x=2.70..3.22、前轉向架中心 x=7.04。
# 三條斜邊完全平行，斜率 LEAN = dx / (-dy) = 1.55（往車頭方向下斜約 32.8°）：
# - 大橘前緣：裙板上緣 y=0.95 處 x=7.35（前轉向架前中段、駕駛窗黑罩後緣下方），
#   斜上至橘帶頂緣 y=1.74 處 x=6.126（乘務員門前 0.63 m）。
# - 橘／黑共用斜邊：裙板上緣 y=0.95 處 x=4.48（前客室門中段下方），
#   在門檻 y=1.272 處 x=3.981（貼齊前客室門後下角），至橘帶底 y=1.52 處 x=3.597，
#   向上順接窗下黑線起端（y=1.74 處 x=3.256、y=1.84 處 x=3.101，落於第一客室窗前緣）。
# - 黑斜帶後緣：寬 0.96 m（沿車），裙板上緣 x=3.52 斜至橘帶底 y=1.52 處 x=2.637。
STRIPE_LEAN = 1.55
ORANGE_FRONT_AT_SKIRT = 7.35
SPLIT_AT_SKIRT = 4.48
BLACK_DIAG_WIDTH = 0.96

# 駕駛室黑色橢圓遮罩（revision-2 r2：俯視 (x, z) 後段微收超橢圓與正面 (z, y) 24 邊圓滑橢圓交集，左右對稱）：
# - 沿車長範圍維持 revision-1 不變（x = 6.60..9.58 m，MASK_CENTER_X = 8.09, MASK_RX = 1.49），
#   並以 MASK_XZ_TAPER = 0.11 讓後段（x ≈ 7.0 m）略收貼近 revision-1 側視下緣（降幅由 -118 mm 收至 -47 mm），
#   使七向全車側視與 revision-1 目視無差別。
# - 移除舊版 MASK_MIN_Y = 2.02 水平切面，改由正面 (z, y) 圓滑橢圓界定下緣與左右圓角：
#   底緣自中心 y = 2.215 m（吻合 x = 9.58 鼻脊高 2.219 m）往兩側平滑上彎，頂緣 y = 3.235 m（吻合 x = 6.60 車頂高 3.223 m 且俯視無缺口），
#   橫向加寬至 |z| = 1.037 m（約佔整車寬 61.7%、車鼻局部寬 ~67%），24 邊圓滑且頭車總面數 < 5,500。
MASK_CENTER_X = 8.09
MASK_RX = 1.49
MASK_RZ = 1.15
MASK_XZ_TAPER = 0.11
MASK_POWER = 2.05
MASK_SIDES = 24

MASK_ZY_CENTER_Y = 2.63
MASK_ZY_RY_TOP = 0.605
MASK_ZY_RY_BOT = 0.415
MASK_ZY_RZ = 1.07
MASK_ZY_POWER_TOP = 1.95
MASK_ZY_POWER_BOT = 2.35


def _make_cab_mask_xz():
    pts = []
    for k in range(MASK_SIDES):
        a = 2.0 * math.pi * k / MASK_SIDES
        ca, sa = math.cos(a), math.sin(a)
        x = MASK_CENTER_X + MASK_RX * math.copysign(abs(ca) ** (2.0 / MASK_POWER), ca)
        z = MASK_RZ * (1.0 + MASK_XZ_TAPER * ca) * math.copysign(abs(sa) ** (2.0 / MASK_POWER), sa)
        pts.append((x, z))
    return pts


def _make_cab_mask_zy():
    pts = []
    for k in range(MASK_SIDES):
        a = 2.0 * math.pi * k / MASK_SIDES
        ca, sa = math.cos(a), math.sin(a)
        power, ry = (MASK_ZY_POWER_TOP, MASK_ZY_RY_TOP) if sa >= 0 else (MASK_ZY_POWER_BOT, MASK_ZY_RY_BOT)
        z = MASK_ZY_RZ * math.copysign(abs(ca) ** (2.0 / power), ca)
        y = MASK_ZY_CENTER_Y + ry * math.copysign(abs(sa) ** (2.0 / power), sa)
        pts.append((z, y))
    return pts


CAB_MASK_XZ = _make_cab_mask_xz()
CAB_MASK_ZY = _make_cab_mask_zy()
MASK_ZY_MIN_Y = MASK_ZY_CENTER_Y - MASK_ZY_RY_BOT


def _diag_x(x_at_skirt: float, y: float) -> float:
    return x_at_skirt - STRIPE_LEAN * (y - SKIRT_REF_Y)


# ---------------------------------------------------------------- GLB 讀取（自 kyushu_n700.py）

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
    turn = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    out = np.eye(4)
    out[:3, :3] = turn @ np.diag(node.get("scale", [1, 1, 1]))
    out[:3, 3] = node.get("translation", [0, 0, 0])
    return out


def parts(gltf, blob):
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


# ---------------------------------------------------------------- 2D UV 切多邊形（自 kyushu_n700.py）

def components(labels: np.ndarray):
    height, width = labels.shape
    seen = np.zeros((height, width), bool)
    found = []
    for y0 in range(height):
        for x0 in range(width):
            kind = int(labels[y0, x0])
            if kind == BODY or seen[y0, x0]:
                continue
            stack = [(y0, x0)]
            seen[y0, x0] = True
            cells = []
            x_min = x_max = x0
            y_min = y_max = y0
            while stack:
                y, x = stack.pop()
                cells.append((y, x))
                x_min, x_max = min(x_min, x), max(x_max, x)
                y_min, y_max = min(y_min, y), max(y_max, y)
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < height and 0 <= nx < width and not seen[ny, nx] and labels[ny, nx] == kind:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            found.append({"kind": kind, "box": (x_min, y_min, x_max + 1, y_max + 1), "count": len(cells), "cells": cells})
    return found


def area2d(polygon) -> float:
    total = 0.0
    n = len(polygon)
    for i in range(n):
        x0, y0 = polygon[i]
        x1, y1 = polygon[(i + 1) % n]
        total += x0 * y1 - x1 * y0
    return abs(total) / 2


def centre2d(polygon):
    n = len(polygon)
    return sum(p[0] for p in polygon) / n, sum(p[1] for p in polygon) / n


def split_half2d(polygon, a, b, c):
    low, high = [], []
    n = len(polygon)
    for i in range(n):
        p, q = polygon[i], polygon[(i + 1) % n]
        dp, dq = a * p[0] + b * p[1] - c, a * q[0] + b * q[1] - c
        if abs(dp) < 1e-9:
            dp = 0.0
        if abs(dq) < 1e-9:
            dq = 0.0
        if dp <= 0:
            low.append(p)
        if dp >= 0:
            high.append(p)
        if (dp < 0 < dq) or (dq < 0 < dp):
            t = dp / (dp - dq)
            point = (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)
            low.append(point)
            high.append(point)
    return (low if len(low) > 2 and area2d(low) > 1e-4 else None), (high if len(high) > 2 and area2d(high) > 1e-4 else None)


def carve2d(polygon, region):
    cx, cy = centre2d(region)
    inside, outside = polygon, []
    for i in range(len(region)):
        (x0, y0), (x1, y1) = region[i], region[(i + 1) % len(region)]
        a, b = y1 - y0, x0 - x1
        c = a * x0 + b * y0
        if a * cx + b * cy > c:
            a, b, c = -a, -b, -c
        low, high = split_half2d(inside, a, b, c)
        if high:
            outside.append(high)
        inside = low
        if inside is None:
            return None, [polygon]
    return inside, outside


def slabs2d(polygon, rectangles):
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    near = [r for r in rectangles if r[0] < max(xs) - 1e-6 and r[2] > min(xs) + 1e-6
            and r[1] < max(ys) - 1e-6 and r[3] > min(ys) + 1e-6]
    if not near:
        return [(polygon, None)]
    rows = [polygon]
    for y in sorted({v for r in near for v in (r[1], r[3]) if min(ys) + 1e-6 < v < max(ys) - 1e-6}):
        rows = [half for row in rows for half in split_half2d(row, 0.0, 1.0, y) if half]
    out = []
    for row in rows:
        top, bottom = min(p[1] for p in row), max(p[1] for p in row)
        left, right = min(p[0] for p in row), max(p[0] for p in row)
        mid = (top + bottom) / 2
        across = [r for r in near if r[1] <= mid <= r[3] and r[0] < right - 1e-6 and r[2] > left + 1e-6]
        cells = [row]
        for x in sorted({v for r in across for v in (r[0], r[2]) if left + 1e-6 < v < right - 1e-6}):
            cells = [half for cell in cells for half in split_half2d(cell, 1.0, 0.0, x) if half]
        for cell in cells:
            cx, _ = centre2d(cell)
            kind = next((r[4] for r in across if r[0] <= cx <= r[2]), None)
            out.append((cell, kind))
    return out


def classify_point(rectangles, rest: np.ndarray, x: float, y: float) -> int:
    for x0, y0, x1, y1, kind in rectangles:
        if x0 <= x <= x1 and y0 <= y <= y1:
            return kind
    h, w = rest.shape
    return int(rest[min(max(int(y), 0), h - 1), min(max(int(x), 0), w - 1)])


def raster_counts(polygon, rest: np.ndarray):
    h, w = rest.shape
    x0 = max(0, int(np.floor(min(p[0] for p in polygon))))
    y0 = max(0, int(np.floor(min(p[1] for p in polygon))))
    x1 = min(w, int(np.ceil(max(p[0] for p in polygon))))
    y1 = min(h, int(np.ceil(max(p[1] for p in polygon))))
    if x1 <= x0 or y1 <= y0:
        cx, cy = centre2d(polygon)
        counts = np.zeros(len(MATERIALS), np.int64)
        counts[int(rest[min(max(int(cy), 0), h - 1), min(max(int(cx), 0), w - 1)])] = 1
        return counts
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).polygon([(p[0] - x0, p[1] - y0) for p in polygon], fill=1)
    inside = np.asarray(mask, bool)
    if not inside.any():
        cx, cy = centre2d(polygon)
        counts = np.zeros(len(MATERIALS), np.int64)
        counts[int(rest[min(max(int(cy), 0), h - 1), min(max(int(cx), 0), w - 1)])] = 1
        return counts
    return np.bincount(rest[y0:y1, x0:x1][inside], minlength=len(MATERIALS))


def settle2d(polygon, rest: np.ndarray, depth: int = 0):
    counts = raster_counts(polygon, rest)
    total = int(counts.sum())
    winner = int(counts.argmax())
    if counts[winner] >= 0.94 * total or area2d(polygon) < 16 or depth >= 4:
        return [(polygon, winner)]
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    x_span, y_span = max(xs) - min(xs), max(ys) - min(ys)
    if x_span >= y_span:
        lo, hi = split_half2d(polygon, 1.0, 0.0, (min(xs) + max(xs)) / 2)
    else:
        lo, hi = split_half2d(polygon, 0.0, 1.0, (min(ys) + max(ys)) / 2)
    out = []
    for half in (lo, hi):
        if half:
            out += settle2d(half, rest, depth + 1)
    return out


# ---------------------------------------------------------------- 3D 凸多邊形切面（自 thsr_700t.py）

def area3d(polygon) -> float:
    total = np.zeros(3)
    for i in range(1, len(polygon) - 1):
        total += np.cross(polygon[i] - polygon[0], polygon[i + 1] - polygon[0])
    return float(np.linalg.norm(total)) / 2


def halves3d(polygon, a: float, b: float, c: float, axis0: int, axis1: int):
    """3D 凸多邊形被平面 a·p[axis0] + b·p[axis1] = c 切成兩半。"""
    low, high = [], []
    count = len(polygon)
    for i in range(count):
        p, q = polygon[i], polygon[(i + 1) % count]
        dp = a * p[axis0] + b * p[axis1] - c
        dq = a * q[axis0] + b * q[axis1] - c
        if abs(dp) < 1e-9:
            dp = 0.0
        if abs(dq) < 1e-9:
            dq = 0.0
        if dp <= 0:
            low.append(p)
        if dp >= 0:
            high.append(p)
        if (dp < 0 < dq) or (dq < 0 < dp):
            point = p + (q - p) * (dp / (dp - dq))
            low.append(point)
            high.append(point)
    return (
        low if len(low) > 2 and area3d(low) > 1e-8 else None,
        high if len(high) > 2 and area3d(high) > 1e-8 else None,
    )


def carve3d(polygon, region, axis0: int = 0, axis1: int = 1):
    """polygon 落在 region（(axis0, axis1) 平面上的凸多邊形柱）內的部分與外面剩下的幾塊。"""
    c0 = sum(p[0] for p in region) / len(region)
    c1 = sum(p[1] for p in region) / len(region)
    inside, outside = polygon, []
    for i in range(len(region)):
        (u0, v0), (u1, v1) = region[i], region[(i + 1) % len(region)]
        a, b = v1 - v0, u0 - u1
        c = a * u0 + b * v0
        if a * c0 + b * c1 > c:
            a, b, c = -a, -b, -c
        low, high = halves3d(inside, a, b, c, axis0, axis1)
        if high:
            outside.append(high)
        inside = low
        if inside is None:
            return None, [polygon]
    return inside, outside


# ---------------------------------------------------------------- 貼圖 → 類別與長方形

def classify(image: Image.Image) -> np.ndarray:
    rgb = np.asarray(image, dtype=np.int32).copy()
    body = np.array([189, 192, 187])
    for x0, y0, x1, y1 in TEXT_MASKS:
        rgb[y0:y1, x0:x1] = body
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    high, low = rgb.max(-1), rgb.min(-1)
    labels = np.full(high.shape, BODY, np.int32)
    labels[(high - low < 14) & (high < 150)] = GREY
    labels[(high < 105) & ((g - r >= 8) | (b - r >= 8))] = GLASS
    # 舊版 N700S 藍線像素先暫標為 ORANGE 以便抹除回白，不留殘留。
    navy_mask = np.abs(rgb - np.array([32, 53, 82])).max(-1) <= 12
    labels[navy_mask] = ORANGE
    labels[high < 24] = DARK
    # 車窗由上到下漸深，中間有幾列像素接近藍線顏色：上下都是玻璃的算玻璃。
    glass = labels == GLASS
    above = np.zeros_like(glass)
    below = np.zeros_like(glass)
    for shift in range(1, 7):
        above[shift:] |= glass[:-shift]
        below[:-shift] |= glass[shift:]
    labels[(labels != GLASS) & (labels != BODY) & above & below] = GLASS
    for y0, y1 in SKIRT_BANDS:
        labels[y0:y1] = GREY
    # 舊版 N700S 藍線區域全部清回白色車身。
    for x0, y0, x1, y1 in [OLD_NOSE_LINE_BOX] + OLD_LINES:
        patch = labels[y0:y1, x0:x1]
        patch[patch == ORANGE] = BODY
    labels[labels == ORANGE] = BODY
    # 燈的位置另外給（LAMP），那一小塊貼圖不讀。
    x0, y0, x1, y1 = LAMP
    labels[y0 - 3:y1 + 3, x0 - 3:x1 + 3] = BODY
    return labels


def read_rectangles(labels: np.ndarray):
    rectangles = []
    rest = np.full(labels.shape, BODY, np.int32)
    for part in components(labels):
        x0, y0, x1, y1 = part["box"]
        area = (x1 - x0) * (y1 - y0)
        if part["count"] < 6 or min(x1 - x0, y1 - y0) < 2:
            continue
        if part["kind"] == GREY and (y0, y1) in SKIRT_BANDS:
            continue
        if part["kind"] == GLASS and part["count"] > 4000:
            continue
        if part["kind"] == GLASS and min(x1 - x0, y1 - y0) < 12:
            continue
        if part["kind"] == ORANGE:
            continue
        if part["kind"] in (GREY, DARK) and min(x1 - x0, y1 - y0) < 8:
            continue
        if part["count"] >= 0.86 * area and part["kind"] == GLASS:
            rectangles.append((x0, y0, x1, y1, GLASS))
        elif part["count"] < 0.35 * area:
            continue
        else:
            for y, x in part["cells"]:
                rest[y, x] = part["kind"]
    for y0, y1 in SKIRT_BANDS:
        rectangles.append((0, y0, labels.shape[1], y1, GREY))
        rest[y0:y1] = GREY
    # 四邊門框線完整保留（不留 N700S 舊藍線缺口）。
    for x0, y0, x1, y1 in DOORS:
        rectangles.append((x0, y0, x1, y0 + DOOR_FRAME, GREY))
        rectangles.append((x0, y1 - DOOR_SILL, x1, y1, GREY))
        rectangles.append((x0, y0 + DOOR_FRAME, x0 + DOOR_FRAME, y1 - DOOR_SILL, GREY))
        rectangles.append((x1 - DOOR_FRAME, y0 + DOOR_FRAME, x1, y1 - DOOR_SILL, GREY))
    x0, y0, x1, y1 = LAMP
    middle = (x0 + x1) // 2
    rectangles.append((x0, y0, middle, y1, HEAD))
    rectangles.append((middle, y0, x1, y1, TAIL))
    return rectangles, rest


# ---------------------------------------------------------------- 切三角形（UV 門／窗／裙／燈）

def door_pieces(polygon):
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    pieces = [(polygon, -1)]
    for number, (x0, y0, x1, y1) in enumerate(DOORS):
        if not (x0 < max(xs) and x1 > min(xs) and y0 < max(ys) and y1 > min(ys)):
            continue
        region = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        after = []
        for piece, door in pieces:
            if door >= 0:
                after.append((piece, door))
                continue
            inside, outside = carve2d(piece, region)
            if inside:
                after.append((inside, number))
            after += [(rest, -1) for rest in outside]
        pieces = after
    return pieces


def cut_body(part, rectangles, rest):
    width, height = part["image"].size
    out = []
    for face in part["faces"]:
        corners = part["world"][face]
        u = part["uv"][face, 0]
        v = part["uv"][face, 1]
        u = (u - np.floor(u.min() + 1e-9)) * width
        v = (v - np.floor(v.min() + 1e-9)) * height
        uv = [(float(u[i]), float(v[i])) for i in range(3)]
        e1 = (uv[1][0] - uv[0][0], uv[1][1] - uv[0][1])
        e2 = (uv[2][0] - uv[0][0], uv[2][1] - uv[0][1])
        det = e1[0] * e2[1] - e1[1] * e2[0]
        if abs(det) < 1e-6:
            cx, cy = centre2d(uv)
            out.append((corners, int(classify_point(rectangles, rest, cx, cy)), -1))
            continue

        def lift(point):
            px, py = point[0] - uv[0][0], point[1] - uv[0][1]
            s = (px * e2[1] - py * e2[0]) / det
            t = (e1[0] * py - e1[1] * px) / det
            return corners[0] + (corners[1] - corners[0]) * s + (corners[2] - corners[0]) * t

        cells = []
        for whole, door in door_pieces(uv):
            for polygon, kind in slabs2d(whole, rectangles):
                if kind is not None:
                    cells.append((polygon, kind, door))
                    continue
                pending = [polygon]
                for region in WINDSCREEN:
                    left = []
                    for piece in pending:
                        inside, outside = carve2d(piece, region)
                        if inside:
                            cells.append((inside, GLASS, door))
                        left += outside
                    pending = left
                for piece in pending:
                    cells += [(poly, kind, door) for poly, kind in settle2d(piece, rest)]
        for polygon, kind, door in cells:
            points = [lift(p) for p in polygon]
            for i in range(1, len(points) - 1):
                out.append((np.array([points[0], points[i], points[i + 1]]), kind, door))
    return out


# ---------------------------------------------------------------- 3D N700ST 塗裝切塊

def align_flat_door_seams(triangles):
    """平直側牆（|z|>1.67）上的客室門在舊版貼圖裡有約 0.03° 微傾，使門邊上下端差 0.5–1.0 mm；
    切水平色帶後鄰牆可能落在門框外接矩形內。將各平直客室門左右接縫頂點（門與鄰牆共同頂點）
    垂直對齊至門框中值 x（動幅 ≤ 0.6 mm，不動車鼻與曲面乘務員門）。"""
    # 先依 (側, door id, 沿車聚類) 找出每扇平直側牆門的左右 x 邊界
    by_side_door = {}
    for idx, (c, _, door) in enumerate(triangles):
        if door < 1 or np.abs(c[:, 2]).min() < 1.67:
            continue
        side = -1 if c[:, 2].mean() < 0 else 1
        by_side_door.setdefault((side, door), []).append((float(c[:, 0].mean()), idx))
    seams = []  # (side, x_lo, x_hi, x_target, y_lo, y_hi)
    for (side, _), items in by_side_door.items():
        clusters = []
        for x, idx in sorted(items, reverse=True):
            if clusters and clusters[-1][-1][0] - x < 0.6:
                clusters[-1].append((x, idx))
            else:
                clusters.append([(x, idx)])
        for cl in clusters:
            pts = np.concatenate([triangles[idx][0] for _, idx in cl])
            y_lo, y_hi = float(pts[:, 1].min()) - 0.005, float(pts[:, 1].max()) + 0.005
            for edge_x in (float(pts[:, 0].min()), float(pts[:, 0].max())):
                near = pts[np.abs(pts[:, 0] - edge_x) < 0.004][:, 0]
                if len(near) >= 2 and (near.max() - near.min()) > 1e-4:
                    target = round(float(0.5 * (near.min() + near.max())), 3)
                    seams.append((side, float(near.min()) - 0.001, float(near.max()) + 0.001, target, y_lo, y_hi))
    if not seams:
        return triangles
    out = []
    for c, kind, door in triangles:
        if door in (BOGIE, GANGWAY) or np.abs(c[:, 2]).max() < 1.67:
            out.append((c, kind, door))
            continue
        side = -1 if c[:, 2].mean() < 0 else 1
        moved = c.copy()
        for s, x_lo, x_hi, target, y_lo, y_hi in seams:
            if s != side:
                continue
            hit = (np.abs(moved[:, 2]) > 1.67) & (moved[:, 0] >= x_lo) & (moved[:, 0] <= x_hi) & (moved[:, 1] >= y_lo) & (moved[:, 1] <= y_hi)
            if hit.any():
                moved[hit, 0] = target
        out.append((moved, kind, door))
    return out


def paint_n700st(triangles, cab: bool):
    """在已縮放並完成 real_cab 的 3D 座標（+x 車頭、+y 向上、±z 車寬）上切出 N700ST 塗裝。
    先照水平高度 y 切出橫帶（最少碎面），頭車再照三條平行斜線切出大橘斜塊與平行黑斜帶。
    只切 BODY（白色車身與白色門板），保留原門 node 歸屬、不碰玻璃／裙板／門框／燈／轉向架。"""
    o0, o1 = ORANGE_Y
    b0, b1 = BLACK_Y
    # 平行斜線平面：x + STRIPE_LEAN * y = x_at_skirt + STRIPE_LEAN * SKIRT_REF_Y
    c_front = ORANGE_FRONT_AT_SKIRT + STRIPE_LEAN * SKIRT_REF_Y
    c_split = SPLIT_AT_SKIRT + STRIPE_LEAN * SKIRT_REF_Y
    c_back = (SPLIT_AT_SKIRT - BLACK_DIAG_WIDTH) + STRIPE_LEAN * SKIRT_REF_Y

    out = []

    def emit(poly, kind, door):
        for i in range(1, len(poly) - 1):
            tri = np.array([poly[0], poly[i], poly[i + 1]])
            if np.linalg.norm(np.cross(tri[1] - tri[0], tri[2] - tri[0])) > 1e-7:
                out.append((tri, kind, door))

    for corners, kind, door in triangles:
        if kind != BODY or door in (BOGIE, GANGWAY):
            out.append((corners, kind, door))
            continue
        normal = np.cross(corners[1] - corners[0], corners[2] - corners[0])
        nlen = float(np.linalg.norm(normal))
        if nlen < 1e-9:
            continue
        normal = normal / nlen

        pending = [[corners[0], corners[1], corners[2]]]

        # (A) 頭車駕駛室黑色橢圓遮罩：俯視 (x, z) 與正面 (z, y) 24 邊雙向橢圓取交集，限定朝前上方車鼻白面。
        if (
            cab
            and door < 0
            and corners[:, 1].max() > MASK_ZY_MIN_Y - 0.01
            and corners[:, 0].max() > MASK_CENTER_X - MASK_RX - 0.05
            and corners[:, 0].min() < MASK_CENTER_X + MASK_RX + 0.05
            and normal[0] > -0.05
        ):
            next_pending = []
            for poly in pending:
                xs = [p[0] for p in poly]
                ys = [p[1] for p in poly]
                zs = [p[2] for p in poly]
                if (
                    max(ys) > MASK_ZY_MIN_Y
                    and max(xs) > MASK_CENTER_X - MASK_RX
                    and min(xs) < MASK_CENTER_X + MASK_RX
                    and min(abs(z) for z in zs) < max(MASK_RZ, MASK_ZY_RZ) + 0.05
                ):
                    in_xz, out_xz = carve3d(poly, CAB_MASK_XZ, axis0=0, axis1=2)
                    next_pending += out_xz
                    if in_xz:
                        in_both, out_zy = carve3d(in_xz, CAB_MASK_ZY, axis0=2, axis1=1)
                        if in_both:
                            emit(in_both, DARK, door)
                        next_pending += out_zy
                else:
                    next_pending.append(poly)
            pending = next_pending

        # (B) 車身側面塗裝：先依水平 y 切成橫帶（只在該高度實際有色帶的 x 範圍切，避免無謂碎面）。
        is_side = abs(normal[0]) < 0.85 and float(np.abs(corners[:, 2]).max()) > 1.0
        if is_side and corners[:, 1].min() < b1 + 0.01 and corners[:, 1].max() > SKIRT_CUT_Y - 0.01:
            slices = []
            for poly in pending:
                rows = [poly]
                x_min_poly = min(p[0] for p in poly)
                if cab:
                    y_cuts = []
                    if x_min_poly < c_front - STRIPE_LEAN * o0 + 0.02:
                        y_cuts.append(o0)
                    if x_min_poly < c_front - STRIPE_LEAN * o1 + 0.02:
                        y_cuts.append(o1)
                    if x_min_poly < c_split - STRIPE_LEAN * b0 + 0.02:
                        y_cuts.append(b1)
                else:
                    y_cuts = [o0, o1, b1]
                for y_cut in y_cuts:
                    nxt = []
                    for r in rows:
                        ys = [p[1] for p in r]
                        if min(ys) < y_cut - 1e-6 and max(ys) > y_cut + 1e-6:
                            lo, hi = halves3d(r, 0.0, 1.0, y_cut, 0, 1)
                            if lo:
                                nxt.append(lo)
                            if hi:
                                nxt.append(hi)
                        else:
                            nxt.append(r)
                    rows = nxt
                slices += rows

            for piece in slices:
                y_mid = sum(p[1] for p in piece) / len(piece)
                if y_mid > b1:
                    emit(piece, BODY, door)
                elif y_mid > b0:
                    # 窗下細黑線帶（b0..b1）
                    if not cab:
                        emit(piece, DARK, door)
                    else:
                        lo, hi = halves3d(piece, 1.0, STRIPE_LEAN, c_split, 0, 1)
                        if lo:
                            emit(lo, DARK, door)
                        if hi:
                            emit(hi, BODY, door)
                elif y_mid > o0:
                    # 連續橘帶（o0..o1）
                    if not cab:
                        emit(piece, ORANGE, door)
                    else:
                        lo, hi = halves3d(piece, 1.0, STRIPE_LEAN, c_front, 0, 1)
                        if lo:
                            emit(lo, ORANGE, door)
                        if hi:
                            emit(hi, BODY, door)
                else:
                    # 橘帶下方（裙板上緣至 o0）
                    if not cab:
                        emit(piece, BODY, door)
                    else:
                        # 依三條平行斜線由後往前切：white | dark(c_back..c_split) | orange(c_split..c_front) | white
                        lo_b, hi_b = halves3d(piece, 1.0, STRIPE_LEAN, c_back, 0, 1)
                        if lo_b:
                            emit(lo_b, BODY, door)
                        if hi_b:
                            lo_s, hi_s = halves3d(hi_b, 1.0, STRIPE_LEAN, c_split, 0, 1)
                            if lo_s:
                                emit(lo_s, DARK, door)
                            if hi_s:
                                lo_f, hi_f = halves3d(hi_s, 1.0, STRIPE_LEAN, c_front, 0, 1)
                                if lo_f:
                                    emit(lo_f, ORANGE, door)
                                if hi_f:
                                    emit(hi_f, BODY, door)
            continue

        for poly in pending:
            emit(poly, BODY, door)

    return out


# ---------------------------------------------------------------- 幾何整理（自 n700s.py，完全不動外形）

def even_lamps(triangles):
    key = lambda point: tuple(int(round(v * 1000)) for v in point)
    for lamp in (HEAD, TAIL):
        while True:
            sides = {sign: [n for n, (c, kind, _) in enumerate(triangles) if kind == lamp and np.sign(c[:, 2].mean()) == sign]
                     for sign in (-1, 1)}
            if len(sides[-1]) == len(sides[1]):
                break
            more = sides[max(sides, key=lambda sign: len(sides[sign]))]
            edges = {}
            for n in more:
                c = triangles[n][0]
                for i in range(3):
                    edge = frozenset((key(c[i]), key(c[(i + 1) % 3])))
                    edges.setdefault(edge, []).append((c[i], c[(i + 1) % 3]))
            rim = [pair[0] for edge, pair in edges.items() if len(pair) == 1]
            a, b = min(rim, key=lambda pair: float(np.linalg.norm(pair[0] - pair[1])))
            gone, into = key(b), a
            moved = []
            for corners, kind, door in triangles:
                corners = np.array([into if key(p) == gone else p for p in corners])
                if len({key(p) for p in corners}) == 3:
                    moved.append((corners, kind, door))
            triangles = moved
    return triangles


def mend(triangles):
    corners = np.concatenate([c for c, _, _ in triangles])
    normals = np.array([np.cross(c[1] - c[0], c[2] - c[0]) for c, _, _ in triangles])
    normals /= np.maximum(np.linalg.norm(normals, axis=1), 1e-15)[:, None]
    normals = np.repeat(normals, 3, axis=0)
    out = []
    for number, (c, kind, door) in enumerate(triangles):
        flat = np.abs(normals @ normals[3 * number]) > np.cos(np.radians(FOLD))
        ring = []
        for i in range(3):
            a, b = c[i], c[(i + 1) % 3]
            ring.append(a)
            edge = b - a
            length = float(edge @ edge)
            if length < 1e-10:
                continue
            t = (corners - a) @ edge / length
            off = np.linalg.norm(corners - a - np.outer(t, edge), axis=1)
            on = (t > 1e-6) & (t < 1 - 1e-6) & (off < TOUCH) & flat
            for value in sorted({round(float(v), 9) for v in t[on]}):
                ring.append(a + edge * value)
        if len(ring) == 3:
            out.append((c, kind, door))
            continue
        out += [(piece, kind, door) for piece in clip(ring, normals[3 * number])]
    return out


def clip(ring, normal):
    ring, out = list(ring), []
    while len(ring) > 3:
        best = fallback = None
        for i in range(len(ring)):
            p, q, r = ring[i - 1], ring[i], ring[(i + 1) % len(ring)]
            size = np.linalg.norm(np.cross(q - p, r - p))
            if np.cross(q - p, r - q) @ normal <= 0:
                continue
            chord = r - p
            ear = {(i - 1) % len(ring), i, (i + 1) % len(ring)}
            others = np.array([v for k, v in enumerate(ring) if k not in ear])
            t = np.clip((others - p) @ chord / max(float(chord @ chord), 1e-18), 0, 1)
            touches = (np.linalg.norm(others - p - np.outer(t, chord), axis=1) < TOUCH * 1.01).any()
            if fallback is None or size > fallback[0]:
                fallback = (size, i)
            if size > 1e-12 and not touches and (best is None or size > best[0]):
                best = (size, i)
        if fallback is None:
            break
        i = (best or fallback)[1]
        out.append(np.array([ring[i - 1], ring[i], ring[(i + 1) % len(ring)]]))
        del ring[i]
    out.append(np.array(ring[:3]))
    return out


def snap(triangles):
    seen, out = set(), []
    for corners, kind, door in triangles:
        snapped = np.round(corners * 1000) / 1000
        normal = np.cross(snapped[1] - snapped[0], snapped[2] - snapped[0])
        if np.linalg.norm(normal) < 2e-6 or normal @ np.cross(corners[1] - corners[0], corners[2] - corners[0]) <= 0:
            continue
        key = frozenset(tuple(int(round(v * 1000)) for v in corner) for corner in snapped)
        if key in seen:
            continue
        seen.add(key)
        out.append((snapped, kind, door))
    return out


def split_at(triangles, plane):
    out = []
    for corners, kind, door in triangles:
        xs = corners[:, 0]
        if door == BOGIE or xs.max() <= plane + 1e-6 or xs.min() >= plane - 1e-6:
            out.append((corners, kind, door))
            continue
        for low in (True, False):
            polygon = []
            for i in range(3):
                a, b = corners[i], corners[(i + 1) % 3]
                a_in = a[0] <= plane if low else a[0] >= plane
                b_in = b[0] <= plane if low else b[0] >= plane
                if a_in:
                    polygon.append(a)
                if a_in != b_in:
                    point = a + (b - a) * ((plane - a[0]) / (b[0] - a[0]))
                    point[0] = plane
                    polygon.append(point)
            for i in range(1, len(polygon) - 1):
                piece = np.array([polygon[0], polygon[i], polygon[i + 1]])
                if np.linalg.norm(np.cross(piece[1] - piece[0], piece[2] - piece[0])) > 1e-7:
                    out.append((piece, kind, door))
    return out


def spans(found, gap=1e-3):
    merged = []
    for low, high in sorted(found):
        if merged and low <= merged[-1][1] + gap:
            merged[-1][1] = max(merged[-1][1], high)
        else:
            merged.append([low, high])
    return merged


def real_cab(triangles):
    start, pitch = BAY
    end = start + pitch
    bogies = {}
    for corners, _, door in triangles:
        if door == BOGIE:
            bogies.setdefault(bool(corners[:, 0].mean() > 0), []).append(corners[:, 0])
    centres = {front: (np.concatenate(xs).min() + np.concatenate(xs).max()) / 2 for front, xs in bogies.items()}
    assert all(not start - 2 < centre < end + 2 for centre in centres.values()), "多的那一格下面不該有轉向架"
    longer = []
    for corners, kind, door in split_at(split_at(triangles, start), end):
        if door == BOGIE:
            continue
        middle = corners[:, 0].mean()
        if middle < start:
            longer.append((corners, kind, door))
        elif middle < end:
            longer += [(corners + np.array([pitch * k, 0, 0]), kind, door) for k in range(2)]
        else:
            longer.append((corners + np.array([pitch, 0, 0]), kind, door))

    def side(corners, sign):
        return (sign * corners[:, 2]).min() > 1.5

    body = np.concatenate([corners for corners, kind, _ in longer if kind != DARK])
    tip = float(body[:, 0].max())
    back = float(np.concatenate([corners for corners, _, _ in longer])[:, 0].min())
    straight = float(body[(np.abs(body[:, 2]) > WIDTH * 1.40 - 0.005) & (body[:, 1] > 2.5)][:, 0].max())
    doors = spans([(float(c[:, 0].min()), float(c[:, 0].max())) for c, _, door in longer
                   if door >= 1 and (side(c, 1) or side(c, -1))], gap=0.1)
    assert len(doors) == 2 and doors[-1][1] < straight, doors
    glass = [spans([(float(c[:, 0].min()), float(c[:, 0].max())) for c, kind, door in longer
                    if kind == GLASS and door < 0 and side(c, sign) and c[:, 0].max() < doors[-1][0]]) for sign in (-1, 1)]
    assert all(len(found) == CAB_WINDOWS for found in glass), [len(found) for found in glass]
    width = np.mean([high - low for found in glass for low, high in found])
    windows = spans([tuple(span) for found in glass for span in found])
    assert len(windows) == CAB_WINDOWS, windows
    window = CAB_WINDOW / width
    marks = sorted([(low, high, window) for low, high in windows]
                   + [(low, high, CAB_DOOR / (high - low)) for low, high in doors])
    pieces, at = [], back
    for number, (low, high, factor) in enumerate(marks):
        between = None
        if number and marks[number - 1][2] == window and factor == window:
            between = (CAB_PITCH - (high - low) * window) / (low - at)
        pieces.append((at, low, between))
        pieces.append((low, high, factor))
        at = high
    pieces.append((at, straight, None))
    fixed = sum((high - low) * factor for low, high, factor in pieces if factor is not None)
    plain = sum(high - low for low, high, factor in pieces if factor is None)
    rest = (CAB_REAL - (tip - straight) - fixed) / plain
    assert 0.97 < rest < 1.03, f"其餘的牆要改 {rest:.3f} 倍：不是原樣了"
    knots, values = [back], [0.0]
    for low, high, factor in pieces:
        knots.append(high)
        values.append(values[-1] + (high - low) * (rest if factor is None else factor))
    knots.append(tip)
    values.append(values[-1] + tip - straight)
    assert abs(values[-1] - CAB_REAL) < 1e-6
    knots, values = np.array(knots), np.array(values) - CAB_REAL / 2

    out = [(np.column_stack([np.interp(corners[:, 0], knots, values), corners[:, 1:]]), kind, door)
           for corners, kind, door in longer]
    for corners, kind, door in triangles:
        if door == BOGIE:
            centre = centres[bool(corners[:, 0].mean() > 0)]
            moved = float(np.interp(centre + (pitch if centre > end else 0), knots, values)) - centre
            out.append((corners + np.array([moved, 0, 0]), kind, door))
    return [(corners, kind, door) for corners, kind, door in out
            if len({tuple(int(round(v * 1000)) for v in corner) for corner in corners}) == 3]


def hoods(triangles, ends):
    points = np.concatenate([corners for corners, _, _ in triangles])
    half = float(np.abs(points[:, 0]).max())
    body = [(corners, kind) for corners, kind, door in triangles if door not in (BOGIE, GANGWAY)]
    walls = [c for c, _ in body if np.abs(c[:, 2]).min() > 1.6]
    turn = np.sign(sum(float(np.cross(c[1] - c[0], c[2] - c[0])[2] * c[:, 2].mean()) for c in walls))

    def facing(corners, outward):
        normal = np.cross(corners[1] - corners[0], corners[2] - corners[0])
        return corners if np.sign(np.dot(normal, outward)) == turn else corners[::-1]

    out = []
    for end in ends:
        wall = max(float((end * corners[:, 0]).max()) for corners, _ in body)
        cap = [(corners, kind) for corners, kind in body if np.abs(end * corners[:, 0] - wall).max() < 1e-3]
        skirt = max(float(corners[:, 1].max()) for corners, kind in cap if kind == GREY)
        ring = sorted({(round(float(y), 4), round(float(z), 4)) for corners, _ in cap for _, y, z in corners})

        def hull(sequence):
            chain = []
            for q in sequence:
                while len(chain) >= 2 and ((chain[-1][0] - chain[-2][0]) * (q[1] - chain[-2][1])
                                            - (chain[-1][1] - chain[-2][1]) * (q[0] - chain[-2][0])) <= 1e-9:
                    chain.pop()
                chain.append(q)
            return chain[:-1]

        outline = hull(ring) + hull(ring[::-1])
        split = []
        for a, b in zip(outline, outline[1:] + outline[:1]):
            split.append(a)
            crossings = []
            if a[1] * b[1] < 0:
                t = a[1] / (a[1] - b[1])
                crossings.append((t, (a[0] + (b[0] - a[0]) * t, 0.0)))
            if min(a[0], b[0]) < skirt - 1e-4 and max(a[0], b[0]) > skirt + 1e-4:
                t = (skirt - a[0]) / (b[0] - a[0])
                crossings.append((t, (skirt, a[1] + (b[1] - a[1]) * t)))
            split += [point for _, point in sorted(crossings)]
        outline = split
        centre = np.mean(outline, 0)
        mouth = lambda z: end * (half - HOOD_GAP - abs(z) * HOOD_TAPER)
        x0 = end * wall
        if end * mouth(1.7) - wall < 0.05:
            raise SystemExit("車體已經到連結面，沒有地方放幌")
        for p, q in zip(outline, outline[1:] + outline[:1]):
            kind = GREY if (p[0] + q[0]) / 2 < skirt else BODY
            quad = [np.array([x0, *p]), np.array([mouth(p[1]), *p]), np.array([mouth(q[1]), *q]), np.array([x0, *q])]
            outward = np.array([0, (p[0] + q[0]) / 2 - centre[0], (p[1] + q[1]) / 2 - centre[1]])
            for corners in (np.array(quad[:3]), np.array([quad[0], quad[2], quad[3]])):
                out.append((facing(corners, outward), kind, -1))
        for side in (1, -1):
            mine = [point for point in outline if point[1] * side >= 0]
            start = next(i for i in range(len(mine)) if mine[i][1] == 0 and mine[i - 1][1] == 0)
            mine = mine[start:] + mine[:start]
            at = lambda point: np.array([mouth(point[1]), *point])
            for a, b in zip(mine[1:], mine[2:]):
                out.append((facing(np.array([at(mine[0]), at(a), at(b)]), np.array([end, 0, 0])), DARK, -1))
        low, high = COUPLER
        tip, back, width = end * half, end * (half - HOOD_GAP - 0.01), 0.05
        corners = {"tip-low": (tip, low, 0), "tip-high": (tip, high, 0),
                   "left-low": (back, low, -width), "left-high": (back, high, -width),
                   "right-low": (back, low, width), "right-high": (back, high, width)}
        middle = np.mean([corners[name] for name in corners], 0)
        faces = [("tip-low", "right-low", "right-high"), ("tip-low", "right-high", "tip-high"),
                 ("tip-low", "tip-high", "left-high"), ("tip-low", "left-high", "left-low"),
                 ("tip-high", "right-high", "left-high"), ("tip-low", "left-low", "right-low"),
                 ("left-low", "left-high", "right-high"), ("left-low", "right-high", "right-low")]
        for face in faces:
            triangle = np.array([corners[name] for name in face], float)
            out.append((facing(triangle, triangle.mean(0) - middle), DARK, -1))
    return out


def name_doors(triangles):
    groups = {}
    for number, (corners, kind, door) in enumerate(triangles):
        if door < 0:
            continue
        side = "left" if corners[:, 2].mean() < 0 else "right"
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
            doors.append({
                "name": name,
                "triangles": len(cluster),
                "min": [round(float(v), 3) for v in points.min(0)],
                "max": [round(float(v), 3) for v in points.max(0)],
            })
    return [(corners, kind, names.get(number)) for number, (corners, kind, _) in enumerate(triangles)], doors


def write_glb(path: Path, triangles):
    binary = bytearray()
    views, accessors, meshes = [], [], []
    parts_list = [None] + sorted({part for _, _, part in triangles if part})
    for part, material in [(part, material) for part in parts_list for material in range(len(MATERIALS))]:
        if material == 0:
            primitives = []
            meshes.append({"name": path.stem + (f"-{part}" if part else ""), "primitives": primitives})
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
        "asset": {"version": "2.0", "generator": "tools/texture-palette/n700st.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(meshes)))}],
        "nodes": [{"mesh": number, "name": mesh["name"]} for number, mesh in enumerate(meshes)],
        "meshes": meshes,
        "materials": [{"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [_srgb_to_linear(c) for c in PREVIEW[i]] + [1.0],
            "metallicFactor": 0.0, "roughnessFactor": 1.0}}
            for i, name in enumerate(MATERIALS)],
        "buffers": [{"byteLength": len(binary)}], "bufferViews": views, "accessors": accessors,
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    path.write_bytes(
        b"glTF" + struct.pack("<II", 2, total)
        + struct.pack("<I4s", len(text), b"JSON") + text
        + struct.pack("<I4s", len(binary), b"BIN\0") + bytes(binary)
    )


def build(path: Path, cab: bool = False):
    gltf, blob, digest = read_glb(path)
    pieces = parts(gltf, blob)
    body = max(pieces, key=lambda p: np.ptp(p["world"][:, 2]))
    labels = classify(body["image"])
    rectangles, rest = read_rectangles(labels)
    triangles = cut_body(body, rectangles, rest)

    scaled = [(corners * np.array([WIDTH, HEIGHT, LENGTH]), kind, door) for corners, kind, door in triangles]
    for piece in pieces:
        if piece is body:
            continue
        world = piece["world"]
        low, high = world.min(0), world.max(0)
        size = high - low
        if size[2] > 2.5:
            middle = (low[2] + high[2]) / 2
            moved = world + np.array([0, 0, middle * LENGTH - middle])
            scaled += [(moved[face], DARK, BOGIE) for face in piece["faces"]]
        elif size[1] > 1.5:
            grown = world * np.array([WIDTH, HEIGHT, LENGTH])
            for face in piece["faces"]:
                corners = grown[face]
                if np.ptp(corners[:, 2]) < 1e-6:
                    continue
                scaled.append((corners, DARK, GANGWAY))

    turned = [(np.stack([-c[:, 2], c[:, 1], c[:, 0]], 1), kind, door) for c, kind, door in scaled]
    xs = np.concatenate([c[:, 0] for c, _, _ in turned])
    shift = -(xs.max() + xs.min()) / 2
    seen, out = set(), []
    for corners, kind, door in turned:
        corners = corners + np.array([shift, 0, 0])
        key = frozenset(tuple(int(round(v * 1000)) for v in corner) for corner in corners)
        if len(key) < 3 or key in seen:
            continue
        if np.linalg.norm(np.cross(corners[1] - corners[0], corners[2] - corners[0])) < 1e-7:
            continue
        seen.add(key)
        out.append((corners, kind, door))
    out = mend(out)
    if cab:
        out = real_cab(out)
    out = align_flat_door_seams(out)
    out = paint_n700st(out, cab=cab)
    out += hoods(out, (-1,) if cab else (-1, 1))
    out = [(corners, kind, door) for corners, kind, door in out if door != GANGWAY]
    out = snap(mend(snap(mend(out))))
    if cab:
        out = even_lamps(out)
    return name_doors(out), digest


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cab", type=Path, required=True)
    parser.add_argument("--middle", type=Path, required=True)
    parser.add_argument("--pantograph", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = {}
    stats = {}
    for unit, path in (("cab", args.cab), ("middle", args.middle), ("pantograph", args.pantograph)):
        (triangles, doors), digest = build(path.expanduser(), unit == "cab")
        if digest != SHA256[unit]:
            raise SystemExit(f"{path.name}: 不是這個工具認得的原檔（SHA-256 {digest}）")
        name = f"n700st-{unit}"
        glb_path = args.out_dir / f"{name}.glb"
        write_glb(glb_path, triangles)
        first = sum(1 for _, _, where in triangles if where is None)
        for door in sorted(doors, key=lambda d: d["name"]):
            door["first"] = first
            first += door["triangles"]
        points = np.concatenate([c for c, _, _ in triangles])
        counts = {MATERIALS[k]: sum(1 for _, kind, _ in triangles if kind == k) for k in range(len(MATERIALS))}
        lo = [round(float(v), 3) for v in points.min(0)]
        hi = [round(float(v), 3) for v in points.max(0)]
        report[name] = {
            "sha256": digest,
            "triangles": len(triangles),
            "materials": counts,
            "min": lo,
            "max": hi,
            "doors": doors,
        }
        stats[name] = {
            "file": f"{name}.glb",
            "tris": len(triangles),
            "length": round(hi[0] - lo[0], 3),
            "width": round(hi[2] - lo[2], 3),
            "height": round(hi[1] - lo[1], 3),
            "min_y": lo[1],
            "max_y": hi[1],
            "materials": counts,
            "door_nodes": len(doors),
            "glb_bytes": glb_path.stat().st_size,
            "glb_sha256": hashlib.sha256(glb_path.read_bytes()).hexdigest(),
        }
    (args.out_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    (args.out_dir / "stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
