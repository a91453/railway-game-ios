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
- 拿掉：凸出側牆 3 cm 的行先表示器薄片、通道幌的兩個端面、重複的面。
- 車端的牆塗深色（真車兩節之間是全高的黑色外幌）。
- 舊版把車壓成 21 m × 2.80 m × 3.96 m；這裡放回真車的尺寸：中間車 25.00 m、
  寬 3.38 m、屋頂高 3.65 m，頭車 27.35 m。頭車和中間車同一個比例：車鼻的
  弧線、窗、門、窗距都不另外放大（作者 2026-11-25：只放大方形部分，車鼻
  彎曲的部分不放大）。到真車 27.35 m 還差的長度補在直線車身：窗帶中間多插
  兩格窗（把那一段車身照樣再排一次），剩下的加在乘務員門與第一格窗之間那
  段沒有東西的牆上。轉向架只平移不縮放，頭車的照真車的位置放（後轉向架
  中心離連結面 3.75 m、中心距 17.5 m）：輪子中心距
  1.50 m，就是 1,435 mm 軌距的鋼軌中心。
- 輸出的軸與 `glb_to_swift.py` 讀的一樣：+y 上、車沿 x、駕駛室在 +x、連結面
  在 ±半車長、軌面 y 0。
"""

from __future__ import annotations

import argparse
import json
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
NOSE_FROM = -4.03         # 頭車：直線車身從這裡（乘務員門的前緣）往後
BAYS = 2                  # 頭車多插幾格窗
WALL_ZONE = 0.2           # 乘務員門後那段牆上，拿來加長的一小段（舊版的公尺）
BOGIE_FROM_END = 3.75     # 真車：轉向架中心離連結面
BOGIE_CENTRES = 17.5      # 真車：轉向架中心距

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# 乘務員門上緣的斜邊：兩段兩個像素高的平行四邊形（對貼圖只要一半的像素是深灰）。
SLANTED = [([(157, 163.5), (166, 159.5), (166, 161.5), (157, 165.5)], GREY),
           ([(166, 159.5), (180, 155), (180, 157), (166, 161.5)], GREY)]


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
    # 方窗會變成扁的，真車的窗是直立的小窗，所以每格左右各收 3 個像素、
    # 上緣加 5 個、下緣加 2 個（約 0.5 m 寬、0.64 m 高）。
    out += [(rect(163, 167, 175, 188), GLASS), (rect(213, 167, 228, 189), GLASS)]
    out += [(rect(253 + 30 * k, 173, 267 + 30 * k, 200), GLASS) for k in range(6)]
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
    out += [(rect(207, 157, 234, 232), DOOR), ([(158, 165.5), (180, 156.5), (180, 232), (158, 232)], DOOR)]
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
            out.append((corners, kind_at(table, *base.centre(uv))))
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
            for i in range(1, len(points) - 1):
                out.append((np.array([points[0], points[i], points[i + 1]]), kind))
            if debug is not None:
                debug.polygon([(p[0] * 4, p[1] * 4) for p in polygon], fill=PREVIEW[kind], outline=(255, 0, 255))
    return out


def along(z: np.ndarray, cab: bool) -> np.ndarray:
    """舊版沿車身的位置 → 真車尺寸的位置。頭車和中間車同一個比例。"""
    return z * LENGTH


def cut_at(triangles, value):
    """沿車身在 z = value 把三角形切開，切完沒有一個跨過這個面。"""
    out = []
    for c, kind in triangles:
        z = c[:, 2]
        if z.max() <= value + 1e-9 or z.min() >= value - 1e-9:
            out.append((c, kind))
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
            out += [(np.array([polygon[0], polygon[i], polygon[i + 1]]), kind) for i in range(1, len(polygon) - 1)]
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


def lengthen(triangles):
    """頭車的直線車身加長到真車的長度（舊版的座標），車鼻不動。

    回傳加長後的面、把車身以外的東西（通道幌）移到新位置的函式、與報告用的數字。"""
    wall = [(c, kind) for c, kind in triangles if np.abs(c[:, 0]).min() > 1.39 and c[:, 2].min() > NOSE_FROM]
    doors_at = spans([c for c, kind in wall if kind == DOOR])
    windows = [w for w in spans([c for c, kind in wall if kind == GLASS])
               if not any(low - 0.1 < w[0] and w[1] < high + 0.1 for low, high in doors_at)]
    centres = [(low + high) / 2 for low, high in windows]
    steps = np.diff(centres)
    pitch = float(np.median(steps))
    if len(windows) < 6 or np.abs(steps - pitch).max() > 0.02 * pitch:
        raise SystemExit(f"頭車的窗不是等距的：{[round(float(v), 3) for v in steps]}")
    extra = CAB_LENGTH / LENGTH - 21.001          # 還差的長度（舊版的公尺）
    rest = extra - BAYS * pitch                   # 插完窗格還差的，加在牆上
    if rest < 0:
        raise SystemExit("插的窗格比要補的長度還長")
    middle = len(windows) // 2
    bay = (centres[middle - 1] + centres[middle]) / 2          # 兩格窗中間的牆
    plain = (doors_at[0][1] + windows[0][0]) / 2 - WALL_ZONE / 2   # 乘務員門與第一格窗之間
    if not doors_at[0][1] < plain and plain + WALL_ZONE < windows[0][0]:
        raise SystemExit("乘務員門與第一格窗之間沒有空的牆")
    for value in (plain, plain + WALL_ZONE, bay, bay + BAYS * pitch):
        triangles = cut_at(triangles, value)
    out = []
    for c, kind in triangles:
        at = float(c[:, 2].mean())
        c = c.copy()
        if at < plain:
            pass
        elif at < plain + WALL_ZONE:
            c[:, 2] = plain + (c[:, 2] - plain) * (WALL_ZONE + rest) / WALL_ZONE
        elif at < bay:
            c[:, 2] += rest
        elif at < bay + BAYS * pitch:
            c[:, 2] += rest
            again = c.copy()
            again[:, 2] += BAYS * pitch
            out.append((again, kind))
        else:
            c[:, 2] += rest + BAYS * pitch
        out.append((c, kind))

    def moved(points: np.ndarray) -> np.ndarray:
        points = points.copy()
        points[:, 2] += np.where(points[:, 2] > bay + BAYS * pitch, extra, 0)
        return points

    numbers = {"windows": len(windows) + BAYS, "pitch_m": round(pitch * LENGTH, 3),
               "bays_m": round(BAYS * pitch * LENGTH, 3), "wall_m": round(rest * LENGTH, 3)}
    return out, moved, extra, numbers


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
    moved, extra, numbers = (lambda points: points), 0.0, {}
    if cab:
        triangles, moved, extra, numbers = lengthen(triangles)
    if debug_dir:
        canvas.save(debug_dir / f"{path.stem[:13]}-uv-cut.png")

    def grown(points: np.ndarray) -> np.ndarray:
        return np.stack([points[:, 0] * WIDTH, points[:, 1] * HEIGHT, along(points[:, 2], cab)], 1)

    # 原座標：x 右、y 上、z 沿車身（頭車的車鼻在 -z）。車體照真車尺寸放大。
    scaled = [(grown(corners), kind) for corners, kind in triangles]
    for piece in pieces:
        if piece is body:
            continue
        world = piece["world"]
        low, high = world.min(0), world.max(0)
        size = high - low
        if size[2] > 2.5:
            # 轉向架：本身不縮放；中間車的位置跟著車體，頭車的照真車的位置。
            middle = (low[2] + high[2]) / 2
            target = float(along(np.array([middle]), cab)[0])
            if cab:
                rear = (10.501 + extra) * LENGTH - BOGIE_FROM_END
                target = rear if middle > 0 else rear - BOGIE_CENTRES
            moved = world + np.array([0, 0, target - middle])
            scaled += [(moved[face], DARK) for face in piece["faces"]]
        elif size[1] > 1.5:
            # 通道幌：照車體放大；兩個端面拿掉（一個在車體裡，一個在連結面上）。
            hood = grown(moved(world))
            for face in piece["faces"]:
                corners = hood[face]
                if np.ptp(corners[:, 2]) < 1e-6:
                    continue
                scaled.append((corners, DARK))

    # 轉成輸出的軸（+y 上、車沿 x、駕駛室在 +x）：旋轉，行列式 +1。
    turned = [(np.stack([-c[:, 2], c[:, 1], c[:, 0]], 1), kind) for c, kind in scaled]
    xs = np.concatenate([c[:, 0] for c, _ in turned])
    shift = -(xs.max() + xs.min()) / 2
    seen, out = set(), []
    for corners, kind in turned:
        corners = corners + np.array([shift, 0, 0])
        key = frozenset(tuple(int(round(v * 1000)) for v in corner) for corner in corners)
        if len(key) < 3 or key in seen:
            continue  # 沒有面積，或同一個面的另一面
        if np.linalg.norm(np.cross(corners[1] - corners[0], corners[2] - corners[0])) < 1e-7:
            continue
        seen.add(key)
        out.append((corners, kind))
    return out, digest, numbers


def doors(triangles, cab: bool):
    """每扇門在輸出座標的範圍（沿車身 x、離軌面的高度），從車頭往車尾；兩側各一扇、位置一樣。

    門 = 門框、門板與門上的窗。網格沿門框的外緣切開，所以每個三角形不是整個在門裡就是整個在牆上
    （乘務員門的上緣是斜的，它的範圍只是位置）。`Map3DKyushu800.doors(_:)` 抄這裡印的數字。"""
    own = [c for c, kind in triangles
           if kind in (DOOR, GREY) and c[:, 2].min() > 1.5 and c[:, 1].min() > 1.0]
    groups = []
    for corners in sorted(own, key=lambda c: -c[:, 0].max()):
        if groups and groups[-1][-1][:, 0].min() - corners[:, 0].max() < 1.0:
            groups[-1].append(corners)
        else:
            groups.append([corners])
    out = []
    for number, group in enumerate(groups):
        points = np.concatenate(group)
        out.append({"x": [round(float(points[:, 0].min()), 3), round(float(points[:, 0].max()), 3)],
                    "z": [round(float(points[:, 1].min()), 3), round(float(points[:, 1].max()), 3)],
                    "crew": cab and number == 0})
    return out


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
        base.write_glb(args.out_dir / f"{name}.glb", triangles, MATERIALS, PREVIEW, "tools/texture-palette/kyushu_800.py")
        points = np.concatenate([c for c, _ in triangles])
        counts = {MATERIALS[k]: sum(1 for _, kind in triangles if kind == k) for k in range(len(MATERIALS))}
        report[name] = {"sha256": digest, "triangles": len(triangles), "materials": counts, "doors": doors(triangles, cab), **({"lengthened": numbers} if numbers else {}),
                        "min": [round(float(v), 3) for v in points.min(0)], "max": [round(float(v), 3) for v in points.max(0)]}
    (args.out_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
