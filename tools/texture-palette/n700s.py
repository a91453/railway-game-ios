#!/usr/bin/env python3
"""作者舊版的 N700S「のぞみ」：有貼圖的頭車、中間車與集電弓車 → 一個材質
一個色票色的 GLB，給 `tools/train-models/glb_to_swift.py` 寫進遊戲（決策 979）。

    uv run --with pillow --with numpy python tools/texture-palette/n700s.py \
        --cab OLD_ASSETS/models/<頭車>.glb --middle OLD_ASSETS/models/<中間車>.glb \
        --pantograph OLD_ASSETS/models/<集電弓車>.glb --out-dir OUT [--debug]

原檔是作者自己的作品，留在作者的電腦，不進這個公開 repo；這裡只有轉檔的
做法。和九州新幹線的 N700 系（`kyushu_n700.py`，決策 977）同一條路，切三角形
的函式直接用它的：先把貼圖讀成「長方形」（車窗、門窗、兩條藍線、裙板），照
長方形的邊把三角形切成格子；前窗照量出來的三個凸多邊形切；其餘的格子照多數
的顏色定。

和 N700 系不同的地方：

- 三節車共用一張 1,024 × 1,024 的貼圖；頭車的側窗是一格一格的小面，各自貼
  同一塊車窗，中間車的側牆是幾個大三角形。兩種都照同一套長方形切。
- 貼圖座標有負的（同一張圖往左、往上重複），每個三角形先平移回圖裡。
- 窗下是一粗一細兩條藍線，照貼圖留兩條（N700S 認得出來的地方）；車鼻兩側
  那段藍線是斜的尖角，不是長方形，照量出來的三個凸多邊形（`NOSE_LINES`）切。
- 標誌、文字、禁菸與車號的小牌、行先表示器塗回車身色（遊戲不畫字）；門框
  的細線不畫。
- 車鼻兩頰的燈切成兩格：前半頭燈、後半尾燈。
- 拿掉：車鼻外露的連結器（實車有蓋）、通道幌的兩個端面（編組時兩節的端面
  會疊在同一平面）、重複的面。
- 舊版把車壓成 21 m × 2.80 m；這裡放回真車的 25 m 車距、3.36 m 寬、3.60 m 高
  （車體與通道幌：長 × 12.5/10.501、寬 × 1.2、高 × 3.6/3.625）。轉向架只平移
  不縮放：輪子中心距 1.50 m，就是 1,435 mm 軌距的鋼軌中心。
- 輸出的軸與 `glb_to_swift.py` 讀的一樣：+y 上、車沿 x、駕駛室在 +x、連結面
  在 ±半車長、軌面 y 0。集電弓車的集電弓在 -x 那一半。
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kyushu_n700 as cut  # noqa: E402  切三角形的函式（決策 977）

# 類別，也是輸出材質的順序（`glb_to_swift.py --materials` 用同一順序）。
MATERIALS = ["white", "navy", "grey", "glass", "dark", "headlamp", "taillamp"]
BODY, NAVY, GREY, GLASS, DARK, HEAD, TAIL = range(7)
PREVIEW = [(0xF4, 0xF2, 0xEC), (0x26, 0x2C, 0x57), (0x8A, 0x90, 0x99), (0x40, 0x55, 0x60),
           (0x2B, 0x2F, 0x36), (0xFF, 0xF1, 0xCF), (0xD9, 0x47, 0x3F)]
assert len(MATERIALS) <= len(cut.MATERIALS)  # `cut.settle` 數類別用的是它的長度（九州 N700 多一格門縫線）

# 作者原檔的 SHA-256（頭車 c264b30b…、中間車 2cf2255b…、集電弓車 8d903762…）：
# 不是這三個檔就停。
SHA256 = {
    "cab": "214871fd7c9741d999fd64c1796ed66d6e3eedb9a16542db17dcd959ecedfc53",
    "middle": "2cf2255b345e32868908de7e88d2b3b66e8e981f3d63902b6661439f4551dd04",
    "pantograph": "d2dfea89a6ae0e924c440d57561fb2c07bc1f23b0e99db9361cc5b0b8cdd3dd3",
}

# 貼圖（1,024 × 1,024）上塗回車身色的框：標誌、文字、小牌、行先表示器，與
# 四扇門下的踏板陰影。
TEXT_MASKS = [
    (3, 545, 31, 615), (668, 298, 698, 345), (733, 300, 772, 322), (818, 303, 838, 320),
    (674, 553, 734, 577), (739, 546, 767, 592), (836, 552, 980, 632), (676, 672, 728, 694),
    (161, 793, 189, 838), (212, 800, 248, 820), (880, 793, 908, 840),
    (612, 438, 665, 450), (770, 684, 830, 696), (100, 930, 160, 944), (910, 930, 970, 944),
    # 裙板上緣凸出來的小塊（門下的踏階、車端的連結器座）。
    (425, 466, 457, 473), (984, 710, 1024, 717), (0, 957, 42, 965), (938, 958, 982, 965),
]
# 裙板與車底設備的三條橫帶（貼圖上畫了鉚釘、格柵、檢修蓋）：整條灰。
SKIRT_BANDS = [(473, 529), (717, 771), (965, 1024)]
# 車鼻兩頰的燈在貼圖上的位置，切成前半頭燈、後半尾燈（車鼻尖在貼圖左邊）。
LAMP = (128, 408, 175, 425)

# 前窗在貼圖上的外形，三個凸多邊形：中間的正面窗與上下兩側往後繞的側窗
# （馬蹄形，開口朝車鼻）。照貼圖的像素邊量的，上下對稱（對稱軸 y 234）。
_ARM = [(245, 182), (252, 170), (296, 169), (334, 177), (367, 189), (385, 205), (253, 205), (246, 196)]
WINDSCREEN = [
    [(282, 205), (385, 205), (390, 216), (393, 234), (390, 252), (385, 263), (282, 263)],
    _ARM,
    [(x, 468 - y) for x, y in reversed(_ARM)],
]

# 頭車車鼻兩側的藍線：上面那條往車鼻收成尖角，粗線與細線的前端各是一個
# 斜角；門後（x 600 起）才是兩條平的線。照貼圖的像素邊量的。
NOSE_LINES = [
    [(296, 384.5), (505, 369.5), (598, 384.5)],
    [(505, 387), (600, 387), (600, 404.5), (577, 404.5)],
    [(586, 408), (612, 408), (612, 415.5)],
]
NOSE_LINE_BOX = (280, 365, 600, 420)
# 窗下的兩條藍線，貼圖上三排側牆各一組（頭車、兩側各一排）：一粗一細。門框
# 的細線在貼圖上把它們切成幾段，所以不從貼圖讀，照量到的列給整條。
LINES = [(600, 387, 1024, 404.5), (612, 408, 1024, 415.5),
         (0, 635, 1024, 651), (0, 655, 1024, 662), (0, 881, 1024, 897), (0, 901, 1024, 908)]

# 門框：貼圖上每扇門是一圈兩個像素寬的細線，自動讀會碎，所以照量到的外框給
# （x0, y0, x1, y1）與兩側直線要讓開藍線的那一段（左線、右線各一段）。依序是
# 頭車那一排的乘務員門、客室門，與另外兩排側牆的三扇客室門。沒有門框，門就
# 只剩門上的小窗浮在牆上（擁有者 2026-11-25：「車門很怪」）。
DOORS = [
    ((555, 314, 593, 439), (377, 400), (383, 410.5)),
    ((614, 304, 663, 445), (387, 415.5), (387, 415.5)),
    ((772, 551, 826, 692), (635, 662), (635, 662)),
    ((102, 797, 156, 938), (881, 908), (881, 908)),
    ((913, 797, 967, 938), (881, 908), (881, 908)),
]
DOOR_FRAME = 3  # 門框線的寬，像素：車上約 4 cm
DOOR_SILL = 4   # 門檻

LENGTH = 12.5 / 10.501   # 連結面 ±10.501 → ±12.5（車距 25 m）
# 頭車：真車 27.35 m。整節沿車長等比例放大，車鼻不另外拉長、不改形（擁有者
# 2026-11-25 的定案：尺寸照真車，車頭不可單獨拉長）。
CAB_LENGTH = 13.675 / 10.501
WIDTH = 3.36 / 2.80      # 側牆 ±1.40 → ±1.68
HEIGHT = 3.60 / 3.625    # 車頂 3.625 → 3.60
# 全周幌：舊版車與車之間只有一條 1.2 m 寬的通道幌，車體端面之間空 0.6 m，
# 看得穿（擁有者 2026-11-25：「第一節跟第二節車廂靠得太遠了」；遊戲自己的車
# 只空 0.24 m）。真車的車體也是這個長度，空的地方由和車體同外形的全周幌蓋
# 住：照端面的外形往連結面拉一圈，離連結面留這麼多（兩車之間一條細縫）。
HOOD_GAP = 0.02  # `Map3DN700S.hoodGap`


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
    labels[np.abs(rgb - np.array([32, 53, 82])).max(-1) <= 8] = NAVY
    labels[high < 24] = DARK
    # 車窗由上到下漸深，中間有幾列像素接近藍線的顏色：上下都是玻璃的算玻璃。
    glass = labels == GLASS
    above = np.zeros_like(glass)
    below = np.zeros_like(glass)
    for shift in range(1, 7):
        above[shift:] |= glass[:-shift]
        below[:-shift] |= glass[shift:]
    labels[(labels != GLASS) & (labels != BODY) & above & below] = GLASS
    for y0, y1 in SKIRT_BANDS:
        labels[y0:y1] = GREY
    # 藍線另外給（NOSE_LINES、LINES），那幾塊貼圖的藍不讀。
    for box in [NOSE_LINE_BOX] + [(int(a), int(b) - 2, int(c), int(d) + 2) for a, b, c, d in LINES]:
        x0, y0, x1, y1 = box
        patch = labels[y0:y1, x0:x1]
        patch[patch == NAVY] = BODY
    # 燈的位置另外給（LAMP），那一小塊貼圖不讀。
    x0, y0, x1, y1 = LAMP
    labels[y0 - 3:y1 + 3, x0 - 3:x1 + 3] = BODY
    return labels


def read_rectangles(labels: np.ndarray):
    """長方形（x0, y0, x1, y1, 類別）與剩下讀不成長方形的類別圖。"""
    rectangles = []
    rest = np.full(labels.shape, BODY, np.int32)
    for part in cut.components(labels):
        x0, y0, x1, y1 = part["box"]
        area = (x1 - x0) * (y1 - y0)
        if part["count"] < 6 or min(x1 - x0, y1 - y0) < 2:
            continue  # 雜點，與一個像素寬的門框線
        if part["kind"] == GREY and (y0, y1) in SKIRT_BANDS:
            continue  # 裙板的橫帶另外給
        if part["kind"] == GLASS and part["count"] > 4000:
            continue  # 前窗：照 WINDSCREEN 的多邊形切
        if part["kind"] == GLASS and min(x1 - x0, y1 - y0) < 12:
            continue  # 門下的踏板陰影，不是窗
        if part["kind"] == NAVY:
            continue  # 藍線以外的藍（小牌的殘邊）
        if part["kind"] in (GREY, DARK) and min(x1 - x0, y1 - y0) < 8:
            continue  # 門縫、扶手、窗角的細線與小點：遊戲大小看不到，只會多出碎面
        if part["count"] >= 0.86 * area and part["kind"] == GLASS:
            rectangles.append((x0, y0, x1, y1, GLASS))
        elif part["count"] < 0.35 * area:
            continue  # 門框、扶手的細線：不畫
        else:
            for y, x in part["cells"]:
                rest[y, x] = part["kind"]
    for y0, y1 in SKIRT_BANDS:
        rectangles.append((0, y0, labels.shape[1], y1, GREY))
        rest[y0:y1] = GREY
    rectangles += [(x0, y0, x1, y1, NAVY) for x0, y0, x1, y1 in LINES]
    for (x0, y0, x1, y1), left, right in DOORS:
        rectangles.append((x0, y0, x1, y0 + DOOR_FRAME, GREY))
        rectangles.append((x0, y1 - DOOR_SILL, x1, y1, GREY))
        for a, b, (g0, g1) in ((x0, x0 + DOOR_FRAME, left), (x1 - DOOR_FRAME, x1, right)):
            rectangles.append((a, y0 + DOOR_FRAME, b, g0, GREY))
            rectangles.append((a, g1, b, y1 - DOOR_SILL, GREY))
    x0, y0, x1, y1 = LAMP
    middle = (x0 + x1) // 2
    rectangles.append((x0, y0, middle, y1, HEAD))
    rectangles.append((middle, y0, x1, y1, TAIL))
    return rectangles, rest


# ---------------------------------------------------------------- 切三角形

def door_pieces(polygon):
    """把貼圖上的一塊照每扇門的外框先切開：（多邊形, 第幾扇門或 -1）。這樣
    沒有一個面跨過門的外框，門板連門框是自己的一塊。"""
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    pieces = [(polygon, -1)]
    for number, ((x0, y0, x1, y1), _, _) in enumerate(DOORS):
        if not (x0 < max(xs) and x1 > min(xs) and y0 < max(ys) and y1 > min(ys)):
            continue
        region = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        after = []
        for piece, door in pieces:
            if door >= 0:
                after.append((piece, door))
                continue
            inside, outside = cut.carve(piece, region)
            if inside:
                after.append((inside, number))
            after += [(rest, -1) for rest in outside]
        pieces = after
    return pieces


def cut_body(part, rectangles, rest, debug=None):
    """車體：每個三角形照貼圖切開，回傳（3 × 3 的原座標頂點, 類別, 貼圖上第幾扇門或 -1）。"""
    width, height = part["image"].size
    out = []
    for face in part["faces"]:
        corners = part["world"][face]
        # 貼圖座標往左、往上重複：整個三角形平移回圖裡。
        u = part["uv"][face, 0]
        v = part["uv"][face, 1]
        u = (u - np.floor(u.min() + 1e-9)) * width
        v = (v - np.floor(v.min() + 1e-9)) * height
        uv = [(float(u[i]), float(v[i])) for i in range(3)]
        e1 = (uv[1][0] - uv[0][0], uv[1][1] - uv[0][1])
        e2 = (uv[2][0] - uv[0][0], uv[2][1] - uv[0][1])
        det = e1[0] * e2[1] - e1[1] * e2[0]
        if abs(det) < 1e-6:
            # 貼圖上是一個點或一條線（車頂的小零件）：照那一點的顏色。
            cx, cy = cut.centre(uv)
            out.append((corners, int(cut.classify_point(rectangles, rest, cx, cy)), -1))
            continue

        def lift(point):
            px, py = point[0] - uv[0][0], point[1] - uv[0][1]
            s = (px * e2[1] - py * e2[0]) / det
            t = (e1[0] * py - e1[1] * px) / det
            return corners[0] + (corners[1] - corners[0]) * s + (corners[2] - corners[0]) * t

        cells = []
        for whole, door in door_pieces(uv):
            for polygon, kind in cut.slabs(whole, rectangles):
                if kind is not None:
                    cells.append((polygon, kind, door))
                    continue
                pending = [polygon]
                for regions, paint in ((WINDSCREEN, GLASS), (NOSE_LINES, NAVY)):
                    for region in regions:
                        left = []
                        for piece in pending:
                            inside, outside = cut.carve(piece, region)
                            if inside:
                                cells.append((inside, paint, door))
                            left += outside
                        pending = left
                for piece in pending:
                    cells += [(polygon, kind, door) for polygon, kind in cut.settle(piece, rest)]
        for polygon, kind, door in cells:
            points = [lift(p) for p in polygon]
            for i in range(1, len(points) - 1):
                out.append((np.array([points[0], points[i], points[i + 1]]), kind, door))
            if debug is not None:
                debug.polygon([(p[0] * 2, p[1] * 2) for p in polygon], fill=PREVIEW[kind], outline=(255, 0, 255))
    return out


# ---------------------------------------------------------------- GLB

def write_glb(path: Path, triangles):
    """`triangles`：（3 × 3 的頂點, 材質, 門名或 None）。車身一個 mesh、一個
    node，每扇門（門板連門框、門窗、門上那一段藍線）各自一個 mesh、一個
    node；一個材質一個 primitive，頂點併起來。"""
    binary = bytearray()
    views, accessors, meshes = [], [], []
    parts = [None] + sorted({part for _, _, part in triangles if part})
    for part, material in [(part, material) for part in parts for material in range(len(MATERIALS))]:
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
        "asset": {"version": "2.0", "generator": "tools/texture-palette/n700s.py"},
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


# ---------------------------------------------------------------- 一節車

def build(path: Path, debug_dir: Path | None, length: float = LENGTH, cab: bool = False):
    gltf, blob, digest = cut.read_glb(path)
    pieces = cut.parts(gltf, blob)
    body = max(pieces, key=lambda p: np.ptp(p["world"][:, 2]))
    labels = classify(body["image"])
    rectangles, rest = read_rectangles(labels)
    canvas = draw = None
    if debug_dir:
        canvas = body["image"].resize((body["image"].width * 2, body["image"].height * 2), Image.NEAREST)
        canvas = Image.blend(canvas, Image.new("RGB", canvas.size, (0, 0, 0)), 0.6)
        draw = ImageDraw.Draw(canvas)
    triangles = cut_body(body, rectangles, rest, draw)
    if debug_dir:
        canvas.save(debug_dir / f"{path.stem[:13]}-uv-cut.png")
        shown = np.array(PREVIEW, np.uint8)[labels]
        Image.fromarray(shown).save(debug_dir / f"{path.stem[:13]}-classes.png")

    # 原座標：x 右、y 上、z 沿車身（頭車的車鼻在 -z）。車體照真車尺寸放大。
    scaled = [(corners * np.array([WIDTH, HEIGHT, length]), kind, door) for corners, kind, door in triangles]
    for piece in pieces:
        if piece is body:
            continue
        world = piece["world"]
        low, high = world.min(0), world.max(0)
        size = high - low
        if size[2] > 2.5:
            # 轉向架：位置跟著車體放大，本身不縮放。
            middle = (low[2] + high[2]) / 2
            moved = world + np.array([0, 0, middle * length - middle])
            scaled += [(moved[face], DARK, -1) for face in piece["faces"]]
        elif size[1] > 1.5:
            # 通道幌：照車體放大；兩個端面拿掉（一個在車體裡，一個在連結面上）。
            grown = world * np.array([WIDTH, HEIGHT, length])
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
    seen, out = set(), []
    for corners, kind, door in turned:
        corners = corners + np.array([shift, 0, 0])
        key = frozenset(tuple(int(round(v * 1000)) for v in corner) for corner in corners)
        if len(key) < 3 or key in seen:
            continue  # 沒有面積，或同一個面的另一面
        if np.linalg.norm(np.cross(corners[1] - corners[0], corners[2] - corners[0])) < 1e-7:
            continue
        seen.add(key)
        out.append((corners, kind, door))
    out += hoods(out, (-1,) if cab else (-1, 1))
    return name_doors(out), digest


def hoods(triangles, ends):
    """每個連結端的全周幌：端面外形（凸包）拉到離連結面 HOOD_GAP 的一圈，
    裙板的高度以下是裙板的灰，以上是車體的白（藍線不接過去，和真車一樣）。"""
    points = np.concatenate([corners for corners, _, _ in triangles])
    half = float(np.abs(points[:, 0]).max())
    body = [(corners, kind) for corners, kind, _ in triangles if kind != DARK]
    # 既有的面朝外的那一面是哪一種繞法：拿側牆的面量。
    walls = [c for c, _ in body if np.abs(c[:, 2]).min() > 1.6]
    turn = np.sign(sum(float(np.cross(c[1] - c[0], c[2] - c[0])[2] * c[:, 2].mean()) for c in walls))
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
        centre = np.mean(outline, 0)
        x0, x1 = end * wall, end * (half - HOOD_GAP)
        for a, b in zip(outline, outline[1:] + outline[:1]):
            pieces = [(a, b)]
            if min(a[0], b[0]) < skirt - 1e-4 and max(a[0], b[0]) > skirt + 1e-4:
                t = (skirt - a[0]) / (b[0] - a[0])
                m = (skirt, a[1] + (b[1] - a[1]) * t)
                pieces = [(a, m), (m, b)]
            for p, q in pieces:
                kind = GREY if (p[0] + q[0]) / 2 < skirt else BODY
                quad = [np.array([x0, *p]), np.array([x1, *p]), np.array([x1, *q]), np.array([x0, *q])]
                for corners in (np.array(quad[:3]), np.array([quad[0], quad[2], quad[3]])):
                    normal = np.cross(corners[1] - corners[0], corners[2] - corners[0])
                    outward = np.array([0, (p[0] + q[0]) / 2 - centre[0], (p[1] + q[1]) / 2 - centre[1]])
                    if np.sign(np.dot(normal, outward)) != turn:
                        corners = corners[::-1]
                    out.append((corners, kind, -1))
    return out


def name_doors(triangles):
    """貼圖上的一扇門在車上是好幾扇（兩側、前後）：照側面與沿車的位置分開，
    由車頭端往後編號。回傳（頂點, 類別, 門名或 None）與每扇門的範圍。"""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cab", type=Path, required=True)
    parser.add_argument("--middle", type=Path, required=True)
    parser.add_argument("--pantograph", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--debug", action="store_true", help="另外輸出貼圖分類圖與 UV 切面圖")
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = {}
    for unit, path in (("cab", args.cab), ("middle", args.middle), ("pantograph", args.pantograph)):
        (triangles, doors), digest = build(path.expanduser(), args.out_dir if args.debug else None,
                                           CAB_LENGTH if unit == "cab" else LENGTH, unit == "cab")
        if digest != SHA256[unit]:
            raise SystemExit(f"{path.name}: 不是這個工具認得的原檔（SHA-256 {digest}）")
        name = f"n700s-{unit}"
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
