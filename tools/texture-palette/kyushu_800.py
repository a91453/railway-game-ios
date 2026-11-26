#!/usr/bin/env python3
"""作者舊版的 800 系（九州新幹線「つばめ」）：有貼圖的頭車與中間車 → 一個
材質一個色票色的 GLB，給 `tools/train-models/glb_to_swift.py` 寫進遊戲
（決策 978）。和 `kyushu_n700.py`（決策 977）同一條路，讀檔、切多邊形、寫檔
都用它的。

    uv run --with pillow --with numpy python tools/texture-palette/kyushu_800.py \
        --cab OLD_ASSETS/models/<頭車>.glb --middle OLD_ASSETS/models/<中間車>.glb \
        --out-dir OUT [--debug]

原檔是作者自己的作品，留在作者的電腦，不進這個公開 repo；這裡只有轉檔的
做法。兩節共用一張 512 × 256 的車身貼圖，原檔又驗 SHA-256，所以貼圖上每
一塊顏色的位置直接寫成表（`regions()`：長方形與凸多邊形，照貼圖的像素邊
量的），不從像素猜；`check_regions` 每次都把表對一次貼圖，對不上就停。
表以外的地方一律是車身白：文字、燕子標誌、扶手、陰影漸層都不畫。

做的事：

- 照表把每個三角形在貼圖上切開：紅屋頂、窗下一條紅線、一個一個的車窗與
  門窗、駕駛室的黑色窗罩與裡面的前窗、側窗、車鼻兩肩的直立燈罩（上兩顆頭
  燈、最下面一顆尾燈）、鼻尖下的黑線、灰裙板。
- 紅線照貼圖是兩個像素高（約 5 cm，和真車照片量的一樣），不為遊戲大小加
  粗；在門的地方斷開，和貼圖、真車一樣。
- 每扇門（門框、門板、門窗）在 GLB 裡自己一個 node（`DOOR_OUTLINES`、
  `name_doors`）：網格沿門框的外緣切開，拿掉一扇門只剩門框外緣的開口，牆是
  完整的。乘務員門的門板照斜框的下緣切，門框裡不留白牆。
- 拿掉：凸出側牆 3 cm 的行先表示器薄片、舊版的通道幌（整條在全周幌裡面）、
  重複的面。
- 車端的牆塗深色，每個連結端再補一圈全周幌（`hoods`）：真車兩節之間是和車身
  齊平、全高的黑色外幌，舊版只有中間一條窄的通道幌，兩節之間 0.6 m 看得穿。
  幌口從上面看是淺淺的 V，兩節在彎道上相對轉 4 度以內不相碰；連結面上只有
  車鉤的尖端。
- 存成毫米以前先把 T 形接點補上（`mend`），頂點放到毫米的格點上，沒有面積或
  翻了面的細條拿掉：不同顏色的面不會疊在同一平面上，也沒有朝內的碎面。
- 舊版把車壓成 21 m × 2.80 m × 3.96 m；這裡放回真車的尺寸：中間車 25.00 m、
  寬 3.38 m、屋頂高 3.65 m，頭車 27.35 m。頭車照真車的比例（作者 2026-11-25：
  看真車來評比；在真車照片上用窗格當尺量的，決策 978 第 3 點）：乘務員門
  起往後的車身沿車身乘 1.30、窗帶多排一格（13 → 14 格，窗距和中間車一樣），
  車鼻拿剩下的長度（乘 1.14，寬乘 1.21，形狀幾乎不變），鼻尖到乘務員門正
  中 7.86 m（真車約 7.85 m）。轉向架只平移不縮放，頭車的照真車
  的位置放（後轉向架中心離連結面 3.75 m、中心距 17.5 m）：輪子中心距
  1.50 m，就是 1,435 mm 軌距的鋼軌中心。
- 中間車的窗帶多排兩格（14 → 16）、沿車身乘 0.9，窗的寬與窗距和頭車一樣
  （1.04–1.08 m，真車約 1 m）；窗帶後面那扇門往車端移 0.5 m，門後的空牆收短
  同樣的長度（`more_windows`）。車長、另一扇門、車端不動。
- 輸出的軸與 `glb_to_swift.py` 讀的一樣：+y 上、車沿 x、駕駛室在 +x、連結面
  在 ±半車長、軌面 y 0。
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import kyushu_n700 as base

# 類別，也是輸出材質的順序（`glb_to_swift.py --materials` 用同一順序）。
MATERIALS = ["white", "red", "grey", "glass", "dark", "headlamp", "taillamp", "door"]
BODY, RED, GREY, GLASS, DARK, HEAD, TAIL, DOOR = range(8)
PREVIEW = [(0xED, 0xEF, 0xF0), (0x8C, 0x1C, 0x1C), (0x8A, 0x90, 0x99), (0x26, 0x31, 0x3D),
           (0x2B, 0x2F, 0x36), (0xFF, 0xF4, 0xD6), (0xE0, 0x39, 0x2C), (0xED, 0xEF, 0xF0)]

# 作者原檔的 SHA-256（頭車 d7f7f5e4…、中間車 652fb052…）：不是這兩個檔就停。
SHA256 = {
    "cab": "e9c1842f4a235b85905430baba5a836a8554916a7d0dececbc473612a737fca2",
    "middle": "c315038822a152ab29bf48a67407c4c7a59270729f4701e579f60b363abba2e0",
}

LENGTH = 12.5 / 10.501   # 連結面 ±10.501 → ±12.5（車距 25 m）
WIDTH = 3.38 / 2.80      # 側牆 ±1.40 → ±1.69
HEIGHT = 3.65 / 3.964    # 屋頂 3.964 → 3.65
CAB_LENGTH = 27.35        # 真車的頭車
CAB_BODY = 1.30           # 頭車的車身（乘務員門起往後）沿車身乘多少：窗距 0.80、0.83 → 1.04、1.08 m，和中間車一樣
CAB_BAYS = 1              # 頭車的窗帶多排幾格（13 → 14，真車 14 格）
NOSE_TO = -3.948          # 頭車：鼻尖 −10.5 到這裡（乘務員門門框的前緣）是車鼻，剩下的長度給它
MORE_WINDOWS = 2          # 中間車的窗帶多排幾格（14 → 16）
WINDOW_SCALE = 0.9        # 中間車的窗帶沿車身再乘多少：窗距 1.155、1.203 m → 1.04、1.08 m，和頭車一樣
BOGIE_FROM_END = 3.75     # 真車：轉向架中心離連結面
HOOD_SHORT = 0.02         # 全周幌的口（正中）離連結面多少：直線上兩節的幌相隔 4 cm
HOOD_TAPER = 0.025        # 幌口往兩側每離中線 1 m 再退多少（從上面看是淺淺的 V）
HOOD_YAW = 4.2            # 兩節相對轉這麼多度以內幌不相碰：2·atan(HOOD_TAPER + HOOD_SHORT / 1.69)
COUPLER = (0.95, 1.05)    # 車鉤（連結面上唯一的東西）離軌面的高度
BOGIE_CENTRES = 17.5      # 真車：轉向架中心距

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# 乘務員門上緣的斜邊：兩段兩個像素高的平行四邊形（對貼圖只要一半的像素是深灰）。
SLANTED = [([(157, 163.5), (166, 159.5), (166, 161.5), (157, 165.5)], GREY),
           ([(166, 159.5), (180, 155), (180, 157), (166, 161.5)], GREY)]


# 乘務員門的門板：上緣貼著斜框的下緣（門框裡面不留白牆）。
CREW_PANEL = [(158, 165.5 - 4 / 9), (166, 161.5), (180, 157), (180, 232), (158, 232)]

# 每扇門在貼圖上的外框（門框的外緣）：乘務員門、客室門。網格沿這條線切開，
# 外框裡的面（門框、門板、門窗）是那扇門的，在 GLB 裡自己一個 node。
DOOR_OUTLINES = [[(157, 163.5), (166, 159.5), (180, 155), (181, 155), (181, 233), (157, 233)],
                 rect(206, 155, 235, 233)]


def door_at(polygon):
    """貼圖上的這一塊在哪扇門的外框裡（`DOOR_OUTLINES` 的序號，-1：不在門上）。
    門框的外緣已經把每一塊切開，所以一塊不是整個在框裡就是整個在框外；跨過
    外框的就停（那樣門就不是自己的一塊）。"""
    for number, outline in enumerate(DOOR_OUTLINES):
        inside, outside = base.carve(polygon, outline)
        area_in = base.area(inside) if inside else 0.0
        area_out = sum(base.area(piece) for piece in outside)
        if area_in > 1e-4 and area_out > 1e-4:
            raise SystemExit(f"有一塊跨過第 {number} 扇門的外框：{polygon}")
        if area_in > 1e-4:
            return number
    return -1


def regions():
    """貼圖上每一塊顏色：（凸多邊形, 類別），前面的先切、蓋過後面的。"""
    out = []
    # 車鼻兩肩的燈罩裡三顆燈：上兩顆頭燈、最下面（最靠鼻尖）一顆尾燈。
    out += [(rect(8, 146, 15, 152), HEAD), (rect(6, 160, 15, 166), HEAD), (rect(5, 174, 14, 180), TAIL)]
    out.append(([(10, 139), (16, 139), (16, 183), (3, 183), (3, 166), (5, 153), (7, 146)], DARK))
    # 前窗（一片長方形）與駕駛室側窗（後緣直、前緣往前下斜）。
    out.append((rect(20, 83, 93, 115), GLASS))
    out.append(([(104, 62), (162, 62), (128, 112), (124, 115), (104, 115)], GLASS))
    # 黑色窗罩：車頂那一塊，與前窗、側窗周圍那一塊（前緣跟著側窗斜）。
    out.append((rect(0, 0, 187, 60), DARK))
    out.append(([(13, 60), (167, 60), (137, 112), (131, 117), (123, 119), (13, 119)], DARK))
    # 鼻尖下的黑線。
    out.append((rect(3, 236, 13, 238), DARK))
    # 門窗兩片、客室窗六格（貼圖沿車身重複用）。客室窗在貼圖上是 20 × 20 像
    # 素的方窗（250–270、178–198）；車身放回真車尺寸後長度放大、高度縮小，
    # 方窗會變成扁的（0.7 × 0.48 m）。真車的窗在照片上用窗格當尺量是 0.71 m
    # 寬、接近方的，所以寬照貼圖的 20 個像素（0.69–0.72 m），上緣加 5 個、下緣
    # 加 2 個（0.64 m 高）。先前看斜角的照片以為是直立的窄窗，左右各收了 3 個
    # 像素（0.5 m），量了才改回來。
    out += [(rect(163, 167, 175, 188), GLASS), (rect(213, 167, 228, 189), GLASS)]
    out += [(rect(250 + 30 * k, 173, 270 + 30 * k, 200), GLASS) for k in range(6)]
    # 門框：貼圖上每扇門外圍一圈一個像素的深灰線（約 5 cm）。客室門是長方形
    # （206–234、155–233）；乘務員門的上緣前低後高（157–180，斜邊量成兩段）。
    out += [(rect(206, 155, 235, 157), GREY), (rect(206, 232, 235, 233), GREY),
            (rect(206, 155, 207, 233), GREY), (rect(234, 155, 235, 233), GREY)]
    out += SLANTED
    out += [(rect(157, 232, 181, 233), GREY), (rect(157, 165, 158, 233), GREY), (rect(180, 155, 181, 233), GREY)]
    # 窗下的紅線：側牆那一條（從車鼻側面的燕子標誌後面起，到門框前停、過了門再
    # 斷開，和貼圖、真車一樣），與頭車門後那塊牆板上的同一條。
    out += [(rect(67, 226, 153, 228), RED), (rect(185, 226, 203, 228), RED), (rect(238, 226, 512, 228), RED),
            (rect(187, 98, 244, 100), RED)]
    # 門板：門框裡面的白，自己一個材質（顏色和車身一樣），之後要讓門在站上
    # 打開時認得出哪些面是門。門上的窗在前面已經切走，位置在門板裡。
    out += [(rect(207, 157, 234, 232), DOOR), (CREW_PANEL, DOOR)]
    # 紅屋頂。
    out.append((rect(244, 0, 504, 104), RED))
    # 床下機器箱兩側的灰裙板。頭車的那一條在貼圖上從 62 起，前 4 m 在車鼻
    # 底下；那一段留白（真車的車鼻到鼻尖都是白的），灰裙板從駕駛室門起。
    out.append((rect(164, 247, 512, 256), GREY))
    # 車端的牆（貼圖最右一行）與車底（貼圖上一個深色小方塊）。
    out += [(rect(504, 0, 512, 128), DARK), (rect(460, 112, 468, 120), DARK)]
    return out


def check_regions(image: Image.Image):
    """表對一次貼圖：每一塊裡該是那個顏色的像素要夠多。"""
    rgb = np.asarray(image.convert("RGB"), dtype=np.int32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    high, low = rgb.max(-1), rgb.min(-1)
    glass = (b - r >= 12) & (high < 110)
    looks = {
        RED: (r > 40) & (g < 30) & (b < 30),
        GLASS: glass,
        DARK: (high - low < 12) & (high < 150) | glass,
        GREY: (high - low < 12) & (high < 200),
        DOOR: (high - low < 16) & (high > 140),
        HEAD: (high - low < 40) & (high > 90),
        TAIL: (high - low < 40) & (high > 90),
    }
    # 紅線的兩端在貼圖上有半個像素的淡邊，所以紅色只要八成。
    # 客室窗改過形狀（見 `regions`），所以玻璃只要七成。
    # 門板那一塊裡還有門上的窗（前面已經切走），所以門板只要六成。
    least = {RED: 0.8, GLASS: 0.7, DARK: 0.6, GREY: 0.9, HEAD: 0.5, TAIL: 0.5, DOOR: 0.6}
    ys, xs = np.mgrid[0:image.height, 0:image.width] + 0.5
    for number, (polygon, kind) in enumerate(regions()):
        # 像素中心落在凸多邊形裡的那些像素。
        cx, cy = base.centre(polygon)
        inside = np.ones(xs.shape, bool)
        for i in range(len(polygon)):
            (ax, ay), (bx, by) = polygon[i], polygon[(i + 1) % len(polygon)]
            side = (bx - ax) * (ys - ay) - (by - ay) * (xs - ax)
            inside &= side * ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) >= 0
        share = float(looks[kind][inside].mean()) if inside.any() else 0.0
        if share < (0.5 if (polygon, kind) in SLANTED else least[kind]):
            raise SystemExit(f"貼圖和表對不上：第 {number} 塊（{MATERIALS[kind]}）只有 {share:.0%} 的像素是那個顏色")


def kind_at(table, x, y):
    for polygon, kind in table:
        inside, _ = base.carve([(x - 0.01, y - 0.01), (x + 0.01, y - 0.01), (x, y + 0.01)], polygon)
        if inside:
            return kind
    return BODY


def cut_body(part, table, debug=None):
    """車體：每個三角形照表切開，回傳（3 × 3 的原座標頂點, 類別）。"""
    width, height = part["image"].size
    pixel = np.stack([part["uv"][:, 0] * width, part["uv"][:, 1] * height], 1)
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
            # 貼圖上是一個點或一條線（車底、車端、車鼻中線）：照那一點的顏色。
            out.append((corners, kind_at(table, *base.centre(uv)), -1))
            continue

        def lift(point):
            px, py = point[0] - uv[0][0], point[1] - uv[0][1]
            s = (px * e2[1] - py * e2[0]) / det
            t = (e1[0] * py - e1[1] * px) / det
            return corners[0] + (corners[1] - corners[0]) * s + (corners[2] - corners[0]) * t

        cells, pending = [], [uv]
        for polygon, kind in table:
            left = []
            for piece in pending:
                inside, outside = base.carve(piece, polygon)
                if inside:
                    cells.append((inside, kind))
                left += outside
            pending = left
        cells += [(piece, BODY) for piece in pending]
        for polygon, kind in cells:
            points = [lift(p) for p in polygon]
            door = door_at(polygon)
            for i in range(1, len(points) - 1):
                out.append((np.array([points[0], points[i], points[i + 1]]), kind, door))
            if debug is not None:
                debug.polygon([(p[0] * 4, p[1] * 4) for p in polygon], fill=PREVIEW[kind], outline=(255, 0, 255))
    return out


def along(z: np.ndarray, nose: float | None = None) -> np.ndarray:
    """舊版沿車身的位置 → 真車尺寸的位置。中間車整節乘 LENGTH。頭車（給 `nose`，
    車鼻沿車身乘多少）：乘務員門起往後乘 CAB_BODY，車鼻乘 `nose`。"""
    if nose is None:
        return z * LENGTH
    return np.where(z <= NOSE_TO, (z - NOSE_TO) * nose, (z - NOSE_TO) * CAB_BODY)


def cut_at(triangles, value):
    """沿車身在 z = value 把三角形切開，切完沒有一個跨過這個面。"""
    out = []
    for c, kind, door in triangles:
        z = c[:, 2]
        if z.max() <= value + 1e-9 or z.min() >= value - 1e-9:
            out.append((c, kind, door))
            continue
        for low in (True, False):
            polygon = []
            for i in range(3):
                a, b = c[i], c[(i + 1) % 3]
                a_in = a[2] <= value if low else a[2] >= value
                b_in = b[2] <= value if low else b[2] >= value
                if a_in:
                    polygon.append(a)
                if a_in != b_in:
                    point = a + (b - a) * (value - a[2]) / (b[2] - a[2])
                    point[2] = value
                    polygon.append(point)
            out += [(np.array([polygon[0], polygon[i], polygon[i + 1]]), kind, door) for i in range(1, len(polygon) - 1)]
    return out


def spans(pieces, gap=0.05):
    """一堆面沿車身佔的區間，接在一起的併成一段。"""
    out = []
    for low, high in sorted((float(c[:, 2].min()), float(c[:, 2].max())) for c in pieces):
        if out and low - out[-1][1] < gap:
            out[-1][1] = max(out[-1][1], high)
        else:
            out.append([low, high])
    return out


def more_bays(triangles, bays: int, behind: float = -np.inf):
    """側牆的窗帶多排 `bays` 格窗（舊版的座標）：在一組等距的窗中間切出一段、照樣
    再排一次，後面的東西往後移。只看 z 大於 `behind` 的牆（頭車：車鼻以後）。
    回傳改好的面、多出來的長度，與原本的牆、門、窗的位置。"""
    wall = [(c, kind) for c, kind, _ in triangles if np.abs(c[:, 0]).min() > 1.39 and c[:, 2].min() > behind]
    doors_at = spans([c for c, kind in wall if kind == DOOR])
    windows = [w for w in spans([c for c, kind in wall if kind == GLASS])
               if not any(low - 0.1 < w[0] and w[1] < high + 0.1 for low, high in doors_at)]
    centres = [(low + high) / 2 for low, high in windows]
    steps = np.diff(centres)
    # 窗分幾組，每組的窗距差一點（貼圖沿車身用了幾次）。在最長的一組等距的窗
    # 中間再排，用那一組自己的窗距。
    runs, first = [], 0
    for i in range(1, len(steps) + 1):
        if i == len(steps) or abs(steps[i] - steps[first]) > 0.004:
            runs.append((first, i))       # 窗 first … i 等距
            first = i

    def outline(pieces, value):
        """切開以後，這些面落在 z = value 上的邊：每種顏色的總長與範圍。"""
        out = {}
        for c, kind, _ in pieces:
            on = c[np.abs(c[:, 2] - value) < 1e-9]
            if len(on) == 2:
                total, low, high = out.get(kind, (0.0, np.full(2, np.inf), np.full(2, -np.inf)))
                out[kind] = (total + float(np.linalg.norm(on[0, :2] - on[1, :2])),
                             np.minimum(low, on[:, :2].min(0)), np.maximum(high, on[:, :2].max(0)))
        return {kind: [round(total, 2), *np.round(low, 2), *np.round(high, 2)] for kind, (total, low, high) in out.items()}

    # 要照樣再排一次的那一段，兩頭的斷面要一樣（裙板的斜端、機器箱的端面落在
    # 裡面就不行）。從最長的一組等距的窗的正中找起，找到第一個兩頭一樣的。
    choice = None
    for first, last in sorted(runs, key=lambda run: run[0] - run[1]):
        centre = (first + last) / 2
        for middle in sorted(range(max(first, 1), last - bays + 1), key=lambda i: abs(i + bays / 2 - 0.5 - centre)):
            pitch = float(centres[middle + bays] - centres[middle]) / bays
            start = (centres[middle - 1] + centres[middle]) / 2          # 兩格窗中間的牆
            added = bays * pitch
            cut = cut_at(cut_at(triangles, start), start + added)
            slab = [face for face in cut if start < face[0][:, 2].mean() < start + added]
            if outline(slab, start) == outline(slab, start + added):
                choice = (start, added, cut)
                break
        if choice:
            break
    if not choice:
        raise SystemExit(f"找不到兩頭斷面一樣的一段窗：{[round(float(v), 3) for v in steps]}")
    start, added, triangles = choice
    out = []
    for c, kind, door in triangles:
        at = float(c[:, 2].mean())
        if start < at < start + added:
            again = c.copy()
            again[:, 2] += added
            out.append((again, kind, door))
        elif at > start:
            c = c + np.array([0, 0, added])
        out.append((c, kind, door))
    return out, added, wall, doors_at, windows, centres, steps


def more_windows(triangles):
    """中間車的窗和頭車排得一樣密（舊版的座標）：多排 MORE_WINDOWS 格窗，窗帶後面那扇門往車端移一點。

    舊版的中間車一側 14 格窗，放回 25 m 之後窗距 1.13–1.22 m；真車每排座位一格窗，
    窗距約 1 m（2 號車 80 席、20 格），頭車放大後是 1.04–1.08 m。做法：窗帶
    （第一格窗前半個窗距到最後一格窗後半個窗距）中間切出一段、照樣再排一次，
    整條窗帶沿車身乘 WINDOW_SCALE，窗的寬與窗距就和頭車一樣。窗帶因此長了約
    0.5 m：後面那扇門整扇往車端平移這麼多，門與車端之間那段沒有東西的牆（舊版
    有 4.3 m）收短同樣的長度（作者 2026-11-25：中間車 16 格，車門稍微移動）。
    車長、另一扇門、車端、車端的裙板都不動。回傳改好的面與報告用的數字。"""
    out, added, wall, doors_at, windows, centres, steps = more_bays(triangles, MORE_WINDOWS)
    front, back = centres[0] - steps[0] / 2, centres[-1] + steps[-1] / 2
    if not all(high < front or low > back for low, high in doors_at):
        raise SystemExit("窗帶碰到門了")
    moved = (back - front + added) * WINDOW_SCALE - (back - front)      # 窗帶長了多少＝門往車端移多少
    frames = spans([c for c, kind in wall if kind in (DOOR, GREY) and c[:, 1].min() > 1.0])
    behind = [high for low, high in frames if low > back]
    skirts = [low for low, high in spans([c for c, kind, _ in triangles if kind == GREY and c[:, 1].max() < 1.0]) if behind and low > behind[0]]
    if moved <= 0 or len(behind) != 1 or not skirts:
        raise SystemExit("窗帶後面要剛好一扇門，門後面要有車端的裙板")
    door, plain = behind[0] + 0.05, min(skirts) - 0.02       # 門框後緣；車端的裙板前緣
    if plain - door < 3 * moved:
        raise SystemExit("門與車端之間的牆不夠收")
    shrink = (plain - door - moved) / (plain - door)

    def settled(z: np.ndarray) -> np.ndarray:
        return np.where(z <= front, z,
               np.where(z < back + added, front + (z - front) * WINDOW_SCALE,
               np.where(z <= door + added, z - added + moved,
               np.where(z < plain + added, plain - (plain + added - z) * shrink, z - added))))

    out = [(np.stack([c[:, 0], c[:, 1], settled(c[:, 2])], 1), kind, where) for c, kind, where in out]
    numbers = {"windows": len(windows) + MORE_WINDOWS, "window_scale": WINDOW_SCALE, "door_moved_m": round(moved * LENGTH, 3),
               "plain_wall_scale": round(shrink, 4), "band_m": [round(front * LENGTH, 3), round((back + moved) * LENGTH, 3)]}
    return out, numbers


def hull(points: np.ndarray) -> list[tuple[float, float]]:
    """平面上一堆點的凸包，逆時針，同一條邊上的中間點拿掉。"""
    found = sorted({(round(float(x), 3), round(float(y), 3)) for x, y in points})

    def half(order):
        chain = []
        for point in order:
            while len(chain) >= 2 and ((chain[-1][0] - chain[-2][0]) * (point[1] - chain[-2][1])
                                       - (chain[-1][1] - chain[-2][1]) * (point[0] - chain[-2][0])) <= 1e-6:
                chain.pop()
            chain.append(point)
        return chain[:-1]

    return half(found) + half(found[::-1])


def hoods(body, cab: bool, joint: float):
    """全周幌：每個連結端，把車身端面的輪廓整圈往連結面延伸，口封起來，深色。
    真車兩節之間是和車身齊平、從屋頂到裙板的深色外幌；舊版只有中間一條 1.2 m
    寬的通道幌，兩節車身之間 0.6 m 看得穿。

    幌口從上面看是淺淺的 V：正中離連結面 `HOOD_SHORT`（直線上兩節相隔 4 cm），往
    兩側每離中線 1 m 再退 `HOOD_TAPER`，兩節車在彎道上相對轉 `HOOD_YAW` 度以內
    幌都不碰（平的口在 1.4 度就相交）。幌口兩半各是一個平面。

    連結面上只有車鉤：一塊深色的楔子，尖端豎在連結面的正中（兩節車轉彎時繞的
    那條線），兩節的尖端相碰、側面不碰；車長也靠它量到連結面。舊版的通道幌整條
    在幌裡面看不到，拿掉了。

    `body` 是放大後、還沒轉軸的車身（x 右、y 上、z 沿車身）；`joint` 是連結面的 z
    （中間車兩頭是 ±`joint`）。"""
    points = np.concatenate([face[0] for face in body])
    out = []
    for sign in ((1,) if cab else (-1, 1)):
        wall = float((points[:, 2] * sign).max())
        mouth = lambda x: joint - HOOD_SHORT - abs(x) * HOOD_TAPER
        if mouth(points[:, 0].max()) - wall < 0.05:
            raise SystemExit("車身已經到連結面，沒有地方放幌")
        ring = hull(points[points[:, 2] * sign > wall - 0.02][:, :2])
        # 幌口的 V 在中線上轉折：輪廓在中線上（上下各一處）要有頂點。
        split = []
        for a, b in zip(ring, ring[1:] + ring[:1]):
            split.append(a)
            if a[0] * b[0] < 0:
                t = a[0] / (a[0] - b[0])
                split.append((0.0, a[1] + (b[1] - a[1]) * t))
        ring = split
        if sign < 0:
            ring = ring[::-1]  # 從另一頭看，外側才朝外
        at = lambda point, z: (point[0], point[1], sign * z)
        for a, b in zip(ring, ring[1:] + ring[:1]):
            out.append((np.array([at(a, wall), at(b, wall), at(b, mouth(b[0]))]), DARK, -1))
            out.append((np.array([at(a, wall), at(b, mouth(b[0])), at(a, mouth(a[0]))]), DARK, -1))
        for half in (1, -1):
            # 幌口的一半（中線這一側，連中線上的兩個頂點）：凸多邊形、平面，扇形切開。
            cap = [point for point in ring if point[0] * half >= 0]
            start = next(i for i in range(len(cap)) if cap[i][0] == 0 and cap[i - 1][0] == 0)
            cap = cap[start:] + cap[:start]
            for a, b in zip(cap[1:], cap[2:]):
                out.append((np.array([at(cap[0], mouth(cap[0][0])), at(a, mouth(a[0])), at(b, mouth(b[0]))]), DARK, -1))
        # 車鉤：尖端在連結面，後面埋在幌裡。
        low, high = COUPLER
        tip, back, side = joint, joint - HOOD_SHORT - 0.01, 0.05
        corners = {"tip-low": (0, low, tip), "tip-high": (0, high, tip),
                   "left-low": (-side, low, back), "left-high": (-side, high, back),
                   "right-low": (side, low, back), "right-high": (side, high, back)}
        faces = [("tip-low", "right-low", "right-high"), ("tip-low", "right-high", "tip-high"),
                 ("tip-low", "tip-high", "left-high"), ("tip-low", "left-high", "left-low"),
                 ("tip-high", "right-high", "left-high"), ("tip-low", "left-low", "right-low"),
                 ("left-low", "left-high", "right-high"), ("left-low", "right-high", "right-low")]
        for face in faces:
            triangle = np.array([(x, y, sign * z) for x, y, z in (corners[name] for name in face)])
            if sign < 0:
                triangle = triangle[::-1]
            out.append((triangle, DARK, -1))
    return out


def build(path: Path, cab: bool, debug_dir: Path | None):
    gltf, blob, digest = base.read_glb(path)
    pieces = base.parts(gltf, blob)
    body = max(pieces, key=lambda p: np.ptp(p["world"][:, 2]))
    check_regions(body["image"])
    table = regions()
    canvas = draw = None
    if debug_dir:
        canvas = body["image"].resize((body["image"].width * 4, body["image"].height * 4), Image.NEAREST)
        canvas = Image.blend(canvas, Image.new("RGB", canvas.size, (0, 0, 0)), 0.6)
        draw = ImageDraw.Draw(canvas)
    triangles = cut_body(body, table, draw)
    nose, added = None, 0.0
    if cab:
        # 頭車照真車的比例：車身乘 CAB_BODY、窗帶多排 CAB_BAYS 格，車鼻拿剩下的長度。
        triangles, added, _, crew, windows, centres, _ = more_bays(triangles, CAB_BAYS, NOSE_TO)
        nose = (CAB_LENGTH - (10.501 + added - NOSE_TO) * CAB_BODY) / (NOSE_TO + 10.5)
        door = (crew[0][0] + crew[0][1]) / 2         # 乘務員門的正中
        numbers = {"windows": len(windows) + CAB_BAYS, "nose_scale": round(nose, 4), "body_scale": CAB_BODY,
                   "bay_m": round(added * CAB_BODY, 3),
                   "tip_to_crew_door_centre_m": round(float((NOSE_TO + 10.5) * nose + (door - NOSE_TO) * CAB_BODY), 3)}
    else:
        triangles, numbers = more_windows(triangles)
    joint = float(along(np.array([10.501 + added]), nose)[0])
    if debug_dir:
        canvas.save(debug_dir / f"{path.stem[:13]}-uv-cut.png")

    def grown(points: np.ndarray) -> np.ndarray:
        return np.stack([points[:, 0] * WIDTH, points[:, 1] * HEIGHT, along(points[:, 2], nose)], 1)

    # 原座標：x 右、y 上、z 沿車身（頭車的車鼻在 -z）。車體照真車尺寸放大。
    if cab:
        # 頭車沿車身的伸縮在乘務員門門框的前緣轉折（車鼻與車身的比例不同）：先切開。
        triangles = cut_at(triangles, NOSE_TO)
    scaled = [(grown(corners), kind, door) for corners, kind, door in triangles]
    scaled += hoods(scaled, cab, joint)
    for piece in pieces:
        if piece is body:
            continue
        world = piece["world"]
        low, high = world.min(0), world.max(0)
        size = high - low
        if size[2] > 2.5:
            # 轉向架：本身不縮放；中間車的位置跟著車體，頭車的照真車的位置。
            middle = (low[2] + high[2]) / 2
            target = float(along(np.array([middle]), nose)[0])
            if cab:
                rear = joint - BOGIE_FROM_END
                target = rear if middle > 0 else rear - BOGIE_CENTRES
            moved = world + np.array([0, 0, target - middle])
            scaled += [(moved[face], DARK, -1) for face in piece["faces"]]
        # （舊版中間那條窄的通道幌整條在全周幌裡面，不畫；見 `hoods`。）

    # 轉成輸出的軸（+y 上、車沿 x、駕駛室在 +x）：旋轉，行列式 +1。
    turned = [(np.stack([-c[:, 2], c[:, 1], c[:, 0]], 1), kind, door) for c, kind, door in scaled]
    xs = np.concatenate([face[0][:, 0] for face in turned])
    shift = -(xs.max() + xs.min()) / 2
    turned = [(corners + np.array([shift, 0, 0]), kind, door) for corners, kind, door in turned]
    seen, out = set(), []
    for corners, kind, door in mend(turned):
        # GLB 存到毫米：先放到毫米的格點上再看。格點上沒有面積（三點共線）或翻了面
        # （切面切出來的細條，放到格點上繞向反了）的就拿掉：都不到幾個平方毫米。
        snapped = np.round(corners * 1000) / 1000
        normal = np.cross(snapped[1] - snapped[0], snapped[2] - snapped[0])
        if np.linalg.norm(normal) < 2e-6 or normal @ np.cross(corners[1] - corners[0], corners[2] - corners[0]) <= 0:
            continue
        key = frozenset(tuple(int(round(v * 1000)) for v in corner) for corner in corners)
        if key in seen:
            continue  # 同一個面的另一面
        seen.add(key)
        out.append((snapped, kind, door))
    return name_doors(out), digest, numbers


def mend(triangles):
    """T 形接點：切面時一塊的頂點常落在隔壁一塊的邊中間。GLB 存到毫米，頂點各自
    放到毫米的格點上，邊中間那個點就會離開那條邊，兩塊顏色不同的面沿邊疊出細條
    （或裂一條縫）。凡是邊中間有同一平面上別種顏色的面的頂點，就把那條邊在那點切開（三角
    形加上邊上的點成凸多邊形，再切成三角形），兩邊才共用同一個頂點。"""
    corners = np.concatenate([c for c, _, _ in triangles])
    paints = np.repeat([kind for _, kind, _ in triangles], 3)
    normals = np.array([np.cross(c[1] - c[0], c[2] - c[0]) for c, _, _ in triangles])
    normals /= np.maximum(np.linalg.norm(normals, axis=1), 1e-15)[:, None]
    normals = np.repeat(normals, 3, axis=0)
    out = []
    for number, (c, kind, door) in enumerate(triangles):
        # 只看同一個平面上（夾角 2 度以內）的鄰面：疊出來的細條在那裡才看得到。
        flat = np.abs(normals @ normals[3 * number]) > np.cos(np.radians(2))
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
            on = (t > 1e-6) & (t < 1 - 1e-6) & (off < 1e-6) & flat
            for value in sorted({round(float(v), 9) for v in t[on]}):
                ring.append(a + edge * value)
        if len(ring) == 3:
            out.append((c, kind, door))
            continue
        out += [(piece, kind, door) for piece in clip(ring)]
    return out


def clip(ring):
    """凸多邊形（有幾個點在邊上）切成三角形：一次切掉一個角，那個角不共線、切線上
    也沒有別的頂點；能切的角裡挑最大的。"""
    ring, out = list(ring), []
    while len(ring) > 3:
        best = None
        for i in range(len(ring)):
            p, q, r = ring[i - 1], ring[i], ring[(i + 1) % len(ring)]
            size = np.linalg.norm(np.cross(q - p, r - p))
            chord = r - p
            ear = {(i - 1) % len(ring), i, (i + 1) % len(ring)}
            others = np.array([v for k, v in enumerate(ring) if k not in ear])
            t = np.clip((others - p) @ chord / (chord @ chord), 0, 1)
            touches = (np.linalg.norm(others - p - np.outer(t, chord), axis=1) < 1e-7).any()
            if size > 1e-12 and not touches and (best is None or size > best[0]):
                best = (size, i)
        if best is None:
            break
        i = best[1]
        out.append(np.array([ring[i - 1], ring[i], ring[(i + 1) % len(ring)]]))
        del ring[i]
    out.append(np.array(ring[:3]))
    return out


def name_doors(triangles):
    """貼圖上的一扇門在車上是好幾扇（兩側，中間車還有前後）：照側面與沿車的位置
    分開，由車頭端（+x）往後編號。回傳（頂點, 類別, 門名或 None）。"""
    groups = {}
    for number, (corners, kind, door) in enumerate(triangles):
        if door < 0:
            continue
        side = "left" if corners[:, 2].mean() < 0 else "right"  # 遊戲的 +y（左）是這裡的 -z
        groups.setdefault(side, []).append((float(corners[:, 0].mean()), number))
    names = {}
    for side, found in groups.items():
        clusters = []
        for x, number in sorted(found, reverse=True):
            if clusters and clusters[-1][-1][0] - x < 0.6:
                clusters[-1].append((x, number))
            else:
                clusters.append([(x, number)])
        for order, cluster in enumerate(clusters, 1):
            for _, number in cluster:
                names[number] = f"door-{side}-{order}"
    return [(corners, kind, names.get(number)) for number, (corners, kind, _) in enumerate(triangles)]


def doors(triangles, cab: bool):
    """每扇門在輸出座標的範圍（沿車身 x、離軌面的高度），從車頭往車尾、左右兩側。

    門 = 門框、門板與門上的窗，GLB 裡自己一個 node。網格沿門框的外緣切開，所以每個
    三角形不是整個在門裡就是整個在牆上。乘務員門的上緣前低後高：`top` 是它的上緣
    （沿車身 x、高度的折線，由後往前）。`Map3DKyushu800.doors(_:)` 抄這裡印的數字。"""
    out = []
    for name in sorted({name for _, _, name in triangles if name}, key=lambda n: (n.split("-")[1], int(n.split("-")[2]))):
        points = np.concatenate([c for c, _, where in triangles if where == name])
        door = {"name": name, "triangles": sum(1 for *_, where in triangles if where == name),
                "x": [round(float(points[:, 0].min()), 3), round(float(points[:, 0].max()), 3)],
                "z": [round(float(points[:, 1].min()), 3), round(float(points[:, 1].max()), 3)],
                "crew": cab and name.endswith("-1")}
        if door["crew"]:
            # 上緣：頂點在（x, 高度）上的上凸包，同一條線上的中間點拿掉。
            chain = []
            for x, y in sorted({(round(float(x), 3), round(float(y), 3)) for x, y in points[:, :2]}):
                while len(chain) >= 2 and ((chain[-1][0] - chain[-2][0]) * (y - chain[-2][1])
                                           - (chain[-1][1] - chain[-2][1]) * (x - chain[-2][0])) >= -1e-6:
                    chain.pop()
                chain.append((x, y))
            while len(chain) > 1 and chain[1][0] == chain[0][0]:
                chain.pop(0)      # 後緣那條直的邊不算
            door["top"] = [list(point) for point in chain]
        out.append(door)
    return out


def write_glb(path: Path, triangles):
    """`triangles`：（3 × 3 的頂點, 材質, 門名或 None）。車身一個 mesh、一個 node，
    每扇門（門框、門板、門窗）各自一個 mesh、一個 node（和 `kyushu_n700.py` 的
    一樣）；一個材質一個 primitive，頂點併起來。"""
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
        "asset": {"version": "2.0", "generator": "tools/texture-palette/kyushu_800.py"},
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


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cab", type=Path, required=True)
    parser.add_argument("--middle", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--debug", action="store_true", help="另外輸出 UV 切面圖")
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, path, cab in (("kyushu-800-cab", args.cab, True), ("kyushu-800-middle", args.middle, False)):
        triangles, digest, numbers = build(path.expanduser(), cab, args.out_dir if args.debug else None)
        expected = SHA256["cab" if cab else "middle"]
        if digest != expected:
            raise SystemExit(f"{path.name}: 不是這個工具認得的原檔（SHA-256 {digest}）")
        write_glb(args.out_dir / f"{name}.glb", triangles)
        points = np.concatenate([face[0] for face in triangles])
        counts = {MATERIALS[k]: sum(1 for _, kind, _ in triangles if kind == k) for k in range(len(MATERIALS))}
        report[name] = {"sha256": digest, "triangles": len(triangles), "materials": counts, "doors": doors(triangles, cab), **({"more_windows": numbers} if numbers else {}),
                        "min": [round(float(v), 3) for v in points.min(0)], "max": [round(float(v), 3) for v in points.max(0)]}
    (args.out_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
