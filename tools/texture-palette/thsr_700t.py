#!/usr/bin/env python3
"""作者舊版的 700 系 → 台灣高鐵 700T：有貼圖的頭車與中間車 → 一個材質一個
色票色的 GLB，給 `tools/train-models/glb_to_swift.py` 寫進遊戲（決策 988）。

    uv run --with pillow --with numpy python tools/texture-palette/thsr_700t.py \
        --cab OLD_ASSETS/models/<頭車>.glb --middle OLD_ASSETS/models/<中間車>.glb \
        --out-dir OUT

原檔是作者自己的作品，留在作者的電腦，不進這個公開 repo；這裡只有轉檔的
做法。讀檔與輸出的軸和 N700S（`n700s.py`，決策 979）、九州新幹線的 N700 系
（`kyushu_n700.py`，決策 977）相同，塗色的做法不同：

- 那兩輛照貼圖的顏色切三角形。這輛的塗裝要換成台灣高鐵的（舊版是白底藍
  線），而且舊版的側牆把同一段「五扇窗」的貼圖重複貼，所以**不照貼圖，直接
  在車身上畫**：每一塊顏色是（沿車, 高度）平面上的一個凸多邊形，往車寬方向
  拉成柱；三角形在 3D 裡對這些柱切開。高度與位置是量台灣高鐵 700T 的照片
  （Wikimedia Commons）定的：白車身，窗下一條黑線疊在橘帶上，裙板深灰；
  橘帶穿過車門一路到車鼻，在前門前面往下加厚到裙板，頂緣向鼻尖收低，繞過
  鼻尖；前門後面裙板上方有一塊往後斜的黑色平行四邊形；黑線從前門後面約
  2 m 起尖。
- 貼圖只用來認三樣：前窗（三個凸多邊形）與兩組燈（外側頭燈、內側尾燈），
  照貼圖上量出來的位置切；貼在貼圖最下面那一條的面是裙板與車鼻底面。
- 車窗、車門重新畫在側牆上：窗 0.64 m 寬；每扇門一圈鐵灰色的門縫線、一扇
  小門窗，門板上的橘帶與黑線照車身接過去。每扇門是 GLB 裡自己的一個 node。
- 舊版頭車駕駛室旁的乘務員門不畫（700T 的頭車沒有，只有客用門）。
- 標誌、文字與車號的小牌拿掉；行先表示器畫成門旁的一小塊深色。
- 拿掉：車鼻外露的連結器、通道幌的兩個端面、重複的面。車頂的天線鰭改成
  有厚度的實心片。
- 尺寸放回真車：車距 25 m、寬 3.38 m、高 3.65 m（長 × 12.5/10.501、寬 ×
  3.38/2.80、高 × 3.65/3.818）。**頭車 27 m**：車鼻、車門與中間車同一個比例
  （不單獨拉長車鼻），直線的車身多出 2 m，窗子照中間車的窗距排成 14 扇（舊
  版 12 扇），不把窗子拉寬。轉向架只平移不縮放（輪子中心距 1.50 m，就是
  1,435 mm 軌距的鋼軌中心）。
- 舊版沒有集電弓車：集電弓車是中間車加上寫出來的集電弓、絕緣子蓋與兩片
  導風板（真車第 4、9 節）。
- 輸出的軸：+y 上、車沿 x、駕駛室在 +x、連結面在 ±半車長、軌面 y 0。集電弓
  車的集電弓在 -x 那一半。

同一套幾何也出舊版原本的塗裝（`--train series700`，決策 989）：白車身，窗下
一條寬藍帶、再下面一條細藍線，藍帶在頭車乘務員門前面斜著起頭；高度與位置
照舊版的貼圖量。這一款畫乘務員門，另外多兩節車：另一端的頭車（`--tail`，
舊版 14 扇窗、後門在車尾）與一扇門的寬窗車（`--green`，17 扇寬窗、車端一扇
小窗；車上的標誌不畫）。

    uv run --with pillow --with numpy python tools/texture-palette/thsr_700t.py \
        --train series700 --cab … --tail … --middle … --green … --out-dir OUT
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kyushu_n700 as cut  # noqa: E402  讀檔與 2D 切多邊形的函式（決策 977）

# 類別，也是輸出材質的順序（`glb_to_swift.py --materials` 用同一順序）。
MATERIALS = ["white", "orange", "black", "skirt", "glass", "dark", "headlamp", "taillamp", "frame"]
WHITE, ORANGE, BLACK, SKIRT, GLASS, DARK, HEAD, TAIL, FRAME = range(9)
PREVIEW = [(0xF2, 0xF0, 0xEA), (0xEA, 0x6A, 0x1E), (0x2B, 0x2F, 0x36), (0x6E, 0x74, 0x7B), (0x26, 0x31, 0x3D),
           (0x2B, 0x2F, 0x36), (0xFF, 0xF1, 0xCF), (0xD9, 0x47, 0x3F), (0x8A, 0x90, 0x99)]

SHA256 = {
    "cab": "50d5b0f57980943f5e36a6ede8ad0c35f57323f8c64c17c9a4fbec0c33dd8621",
    "tail": "6038b19def0ec9bbd7a80f9b23b7154be698766d0a85f2ee1e4dbf33d68d817e",
    "middle": "1471d2d6df2cb7643ce859abf4fb3d5991defeaa9b928a9586509107dabfdc2d",
    "green": "30f038cc9564a5f577b4b84447f52aef24db102977ea31b8c7ed98061ee2cb74",
}

# 兩款車：台灣高鐵的 700T（決策 988）與舊版原本塗裝的 700 系（決策 989）。
# `materials` 是輸出材質的名字（順序就是類別的編號），`units` 是（輸出的名字,
# 原檔是哪一節, 幾何照哪一節）。
TRAINS = {
    "thsr": {
        "prefix": "thsr-700t",
        "materials": ["white", "orange", "black", "skirt", "glass", "dark", "headlamp", "taillamp", "frame"],
        "units": [("cab", "cab"), ("middle", "middle"), ("pantograph", "middle")],
    },
    "series700": {
        "prefix": "series-700",
        "materials": ["white", "band", "line", "skirt", "glass", "dark", "headlamp", "taillamp", "frame"],
        "units": [("cab", "cab"), ("tail", "tail"), ("middle", "middle"), ("green", "green"), ("pantograph", "middle")],
    },
}

# ---------------------------------------------------------------- 尺寸
# 原座標：x 右、y 上、z 沿車身（頭車的車鼻在 -z），單位公尺。

LENGTH = 12.5 / 10.501   # 連結面 ±10.501 → ±12.5（車距 25 m）
WIDTH = 3.38 / 2.80      # 側牆 ±1.40 → ±1.69
HEIGHT = 3.65 / 3.818    # 車頂整流罩 3.818 → 3.65
CAB = 27.0               # 頭車全長（鼻尖到連結面）
CAB_OLD = (-10.5, 10.501)
# 頭車多出來的長度加在這一段（原座標的 z）：只有等斷面的車身，沒有門、沒有
# 轉向架的凹槽（車底的凹槽從 4.825 開始），車頂整流罩也是等斷面。`build`
# 會量這一段兩端與中間的斷面（`same_section`），不一樣就停。
STRETCH = (-1.9, 4.8)
SECTION = 0.02           # 斷面外形最多差這麼多（公尺）
WALL = 1.40              # 側牆的 |x|（原座標）
TOP = 0.6                # 法線的 y 大於這個數的面算朝上（車鼻的上面與兩肩）

# 貼圖（512 × 256）上的像素。
SKIRT_ROW = 234          # 這一列以下是裙板與車鼻底面
FRONT = (100, 170)       # 左上角這一塊是車鼻上面：前窗與燈
WINDSCREEN = [
    [(10, 72), (90.5, 72), (90.5, 76), (89.5, 81), (87, 86), (84, 90), (80, 94), (76.5, 96),
     (23, 96), (20, 94), (16, 90), (13, 86), (11, 81), (10, 76)],
    [(10, 72), (10, 67), (13, 64), (17, 61), (19, 60), (20.5, 60.5), (23, 64), (25, 67), (26.5, 69), (26.5, 72)],
    [(90.5, 72), (90.5, 67), (87.5, 64), (84, 61), (82, 60), (80, 60.5), (78, 63), (76, 65), (74, 68), (73, 70), (73, 72)],
]
# 700T 的黑色面罩：真車的前窗與燈在同一片黑色裡，從燈一路到前窗的上緣，上寬
# 下窄（照片）。舊版的前窗與燈是分開的兩塊，中間是白的；700T 把兩者之間、
# 前窗兩耳之間都補成黑色。一個凸多邊形，排在前窗與燈的後面切。原塗裝的
# 700 系（決策 989）前窗與燈本來就分開，不畫。
MASK = [(10, 76), (10, 67), (13, 64), (17, 61), (19, 60), (82, 60), (84, 61), (87.5, 64), (90.5, 67), (90.5, 76),
        (88.5, 84), (74.5, 123), (25, 123), (12, 84)]
# 兩組燈，各切成外側頭燈、內側（靠中線）尾燈。
LAMPS = [((26.5, 112.5, 37.5, 121.5), HEAD), ((37.5, 112.5, 44.5, 121.5), TAIL),
         ((54.5, 112.5, 61.5, 121.5), TAIL), ((61.5, 112.5, 73, 121.5), HEAD)]

# 車上的高度（公尺，軌面起算；量真車照片）。
SKIRT_TOP = 1.10
ORANGE = (1.58, 1.88)
BLACK_LINE = (1.88, 1.99)
WINDOW = (2.06, 2.56)
WINDOW_WIDTH = 0.64
DOOR = (1.38, 3.07)
DOOR_WINDOW = (2.22, 2.78)
DOOR_WINDOW_WIDTH = 0.30
DOOR_LINE = 0.035
SIGN = (2.84, 3.00)       # 行先表示器
SIGN_FROM, SIGN_WIDTH = 0.95, 0.50

# 門（原座標的 z）。頭車另有一扇乘務員門（-4.423…-3.976），700T 不畫。
CAB_DOORS = [(-3.764, -3.129), (7.591, 8.214)]
MIDDLE_DOORS = [(-9.959, -9.336), (9.333, 9.956)]
# 窗：舊版每扇 0.635 寬、間距 0.8155；頭車 12 扇、中間車 20 扇。這裡記第一扇
# 與最後一扇的中心。
CAB_WINDOWS = (-2.2715, 6.6685)
MIDDLE_WINDOWS = (-8.0065, 7.444, 20)
# 另一端的頭車：14 扇窗，後門在車尾。寬窗車：一扇門，17 扇 0.761 寬的窗
# （間距 0.979），另一端一扇小窗（z0, z1, y0, y1）。
TAIL_DOORS = [(-3.764, -3.129), (9.497, 10.12)]
TAIL_WINDOWS = (-2.2715, 8.315)
GREEN_DOORS = [(9.333, 9.956)]
GREEN_WINDOWS = (-7.9495, 7.653, 17)
GREEN_WINDOW_WIDTH = 0.761
GREEN_SMALL = (-9.752, -9.195, 2.151, 2.837)

# 舊版原本的塗裝（原座標，量舊版的貼圖）：寬藍帶、細藍線的高度；藍帶在頭車
# 上由 BAND_TIP 斜到 BAND_FULL 才是整條寬，細線從 LINE_FROM 起；窗寬、門窗；
# 乘務員門與它的窗。
OLD_BAND = (1.866, 2.080)
OLD_LINE = (1.748, 1.795)
BAND_TIP, BAND_FULL, LINE_FROM = -6.082, -5.102, -5.06
OLD_WINDOW_WIDTH = 0.635
OLD_DOOR_WINDOW = (2.409, 2.951, 0.353)
CREW_DOOR = (-4.423, -3.976, 1.537, 3.029)
CREW_WINDOW = (-4.329, -4.07, 2.399, 2.819)

# 全周幌（做法與 N700S 的相同，`n700s.py`，決策 979）：舊版的車體端面離連結面
# 0.30 m，兩節車體之間空 0.6 m，中間只有一條 1.2 m 寬的通道幌，看得穿。真車
# （Commons 的照片）連結處是和車體同外形的一圈幌，只留一條細縫：照端面的外形
# 往連結面拉一圈，離連結面留這麼多；裙板的高度以下是裙板的灰，以上是車體的
# 白（色帶不接過去）。
HOOD_GAP = 0.02           # `Map3DTHSR700T.hoodGap`

PANTOGRAPH_AT = 6.0       # 集電弓車：集電弓的位置（中間車的 +z 那一半）
PLATE = 0.025             # 天線鰭的厚度


# ---------------------------------------------------------------- 在 3D 裡切

def area(polygon) -> float:
    total = np.zeros(3)
    for i in range(1, len(polygon) - 1):
        total += np.cross(polygon[i] - polygon[0], polygon[i + 1] - polygon[0])
    return float(np.linalg.norm(total)) / 2


def halves(polygon, a, b, c, across=1):
    """凸多邊形（3D，點是 x、y、z）被平面 a·z + b·y = c 切成兩半：小的一邊、
    大的一邊。平面沿車寬方向無限延伸，所以哪一種朝向的面都切得開。`across`
    是 0 的時候改成 a·z + b·x = c（從上面看的平面，沿高度無限延伸）。"""
    low, high = [], []
    count = len(polygon)
    for i in range(count):
        p, q = polygon[i], polygon[(i + 1) % count]
        dp, dq = a * p[2] + b * p[across] - c, a * q[2] + b * q[across] - c
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
    return (low if len(low) > 2 and area(low) > 1e-8 else None), (high if len(high) > 2 and area(high) > 1e-8 else None)


def carve(polygon, region, across=1):
    """polygon 落在 region（（z, y）平面上的凸多邊形拉成的柱）裡的部分，與外面
    剩下的幾塊。`across` 是 0 的時候 region 是從上面看的（z, x）。"""
    cz = sum(p[0] for p in region) / len(region)
    cy = sum(p[1] for p in region) / len(region)
    inside, outside = polygon, []
    for i in range(len(region)):
        (z0, y0), (z1, y1) = region[i], region[(i + 1) % len(region)]
        a, b = y1 - y0, z0 - z1
        c = a * z0 + b * y0
        if a * cz + b * cy > c:
            a, b, c = -a, -b, -c
        low, high = halves(inside, a, b, c, across)
        if high:
            outside.append(high)
        inside = low
        if inside is None:
            return None, [polygon]
    return inside, outside


def grid(polygon, rectangles):
    """照長方形（z0, y0, z1, y1, 類別）的邊把多邊形切成格子：（多邊形, 類別或
    None）。先照高度切成橫列，每一列只照跨過它的長方形切，格子最少。排在前面
    的長方形蓋住後面的。"""
    zs = [p[2] for p in polygon]
    ys = [p[1] for p in polygon]
    near = [r for r in rectangles if r[0] < max(zs) - 1e-6 and r[2] > min(zs) + 1e-6
            and r[1] < max(ys) - 1e-6 and r[3] > min(ys) + 1e-6]
    if not near:
        return [(polygon, None)]
    rows = [polygon]
    for y in sorted({v for r in near for v in (r[1], r[3]) if min(ys) + 1e-6 < v < max(ys) - 1e-6}):
        rows = [half for row in rows for half in halves(row, 0.0, 1.0, y) if half]
    out = []
    for row in rows:
        bottom, top = min(p[1] for p in row), max(p[1] for p in row)
        left, right = min(p[2] for p in row), max(p[2] for p in row)
        # 高度是一條線的列（水平的面）照那個高度算。
        mid = (bottom + top) / 2
        across = [r for r in near if r[1] - 1e-6 <= mid <= r[3] + 1e-6 and r[0] < right - 1e-6 and r[2] > left + 1e-6]
        cells = [row]
        for z in sorted({v for r in across for v in (r[0], r[2]) if left + 1e-6 < v < right - 1e-6}):
            cells = [half for cell in cells for half in halves(cell, 1.0, 0.0, z) if half]
        for cell in cells:
            cz = sum(p[2] for p in cell) / len(cell)
            kind = next((r[4] for r in across if r[0] <= cz <= r[2]), None)
            out.append((cell, kind))
    return out


# ---------------------------------------------------------------- 一節車的塗裝

class Paint:
    """一節車的塗裝：`z` 是原座標 → 放大後的沿車位置。"""

    def __init__(self, unit: str, train: str = "thsr"):
        self.cab = unit in ("cab", "tail")
        own = train == "series700"
        self.mask = not own  # 700T 的黑色面罩（`MASK`）
        if self.cab:
            a, b = STRETCH
            extra = CAB - (CAB_OLD[1] - CAB_OLD[0]) * LENGTH
            inside = LENGTH + extra / (b - a)
            self.z = lambda z: z * LENGTH if z <= a else (a * LENGTH + (z - a) * inside if z <= b else z * LENGTH + extra)
            doors = CAB_DOORS if unit == "cab" else TAIL_DOORS
            # 窗距與中間車相同：照這個窗距排得下幾扇就排幾扇，整排置中。
            first, last = (self.z(v) for v in (CAB_WINDOWS if unit == "cab" else TAIL_WINDOWS))
            pitch = (MIDDLE_WINDOWS[1] - MIDDLE_WINDOWS[0]) * LENGTH / (MIDDLE_WINDOWS[2] - 1)
            count = round((last - first) / pitch) + 1
            spare = (last - first) - pitch * (count - 1)
            first, last = first + spare / 2, last - spare / 2
        else:
            self.z = lambda z: z * LENGTH
            doors = GREEN_DOORS if unit == "green" else MIDDLE_DOORS
            first, last, count = (v if n == 2 else v * LENGTH for n, v in enumerate(GREEN_WINDOWS if unit == "green" else MIDDLE_WINDOWS))
        self.doors = [(self.z(z0), self.z(z1)) for z0, z1 in doors]
        # 每扇門的高度與門窗（y0, y1, 寬）；乘務員門（只有舊版原本的塗裝畫）排在
        # 最前面，是第 1 扇。
        self.door_height = [DOOR] * len(self.doors)
        self.door_window = [(*DOOR_WINDOW, DOOR_WINDOW_WIDTH)] * len(self.doors)
        self.crew = 0
        window_width = WINDOW_WIDTH
        if own:
            window_width = (GREEN_WINDOW_WIDTH if unit == "green" else OLD_WINDOW_WIDTH) * LENGTH
            self.door_window = [(OLD_DOOR_WINDOW[0] * HEIGHT, OLD_DOOR_WINDOW[1] * HEIGHT, OLD_DOOR_WINDOW[2] * LENGTH)] * len(self.doors)
            if self.cab:
                self.crew = 1
                self.doors.insert(0, (self.z(CREW_DOOR[0]), self.z(CREW_DOOR[1])))
                self.door_height.insert(0, (CREW_DOOR[2] * HEIGHT, CREW_DOOR[3] * HEIGHT))
                self.door_window.insert(0, (CREW_WINDOW[2] * HEIGHT, CREW_WINDOW[3] * HEIGHT, (CREW_WINDOW[1] - CREW_WINDOW[0]) * LENGTH))
        self.windows = [float(c) for c in np.linspace(first, last, count)]
        far = 99.0
        if own:
            # 舊版原本的塗裝：寬藍帶與細藍線；頭車上藍帶斜著起頭。車鼻上面全白。
            band = (OLD_BAND[0] * HEIGHT, OLD_BAND[1] * HEIGHT)
            line = (OLD_LINE[0] * HEIGHT, OLD_LINE[1] * HEIGHT)
            self.slanted, self.tongue = [], None
            if self.cab:
                tip, full = self.z(BAND_TIP), self.z(BAND_FULL)
                self.slanted.append(([(tip, band[1]), (full, band[1]), (full, band[0])], ORANGE_KIND))
                self.bands = [(full, band[0], far, band[1], ORANGE_KIND), (self.z(LINE_FROM), line[0], far, line[1], BLACK)]
            else:
                self.bands = [(-far, band[0], far, band[1], ORANGE_KIND), (-far, line[0], far, line[1], BLACK)]
            self.walls(window_width)
            if unit == "green":
                z0, z1, y0, y1 = GREEN_SMALL
                self.wall.append((z0 * LENGTH, y0 * HEIGHT, z1 * LENGTH, y1 * HEIGHT, GLASS))
            return

        # 斜的幾塊（凸多邊形），排在前面的先切。
        self.slanted = []
        # 長方形：橘帶與黑線。
        if self.cab:
            tip = self.z(CAB_OLD[0])
            # 車鼻上橘色的頂緣由斜的那一塊定，橘帶從頂緣回到帶頂的地方才開始。
            self.bands = [(tip + 4.2, ORANGE[0], far, ORANGE[1], ORANGE_KIND)]
            # 白色的頂（從上面看，（z, x））：真車的車鼻上面是白的。鼻尖後 NOSE_TOP[0] m
            # 起寬 ±NOSE_TOP[1]，到 NOSE_TOP[2] m 寬 ±NOSE_TOP[3]，到 NOSE_TOP[4] m 超出
            # 車寬，一直到鼻尖後 40 m（只到 9 m 的話後面的車頂也會變橘）。朝上的面在它
            # 外面（鼻尖與兩肩）是橘色：作者先要全白（2026-11-25），看了圖又在上面把
            # 鼻尖與兩肩塗成橘色，「塗多一點比較像」；三版裡選第 2 版（橘色最多）。
            front, w1, mid, w2, full = NOSE_TOP
            self.tongue = [(tip + front, -w1), (tip + front, w1), (tip + mid, w2), (tip + full, 2.0), (tip + 40.0, 2.0),
                           (tip + 40.0, -2.0), (tip + full, -2.0), (tip + mid, -w2)]
            door = self.doors[0][1]              # 前門的後緣
            lean = 1.0 / (ORANGE[0] - SKIRT_TOP)   # 斜邊：每高 1 m 往後多少
            low = SKIRT_TOP - 0.15
            back = lambda s, y: (door + s + (y - SKIRT_TOP) * lean, y)  # noqa: E731  斜邊上的點
            # 車鼻的橘色：前門前面由裙板到橘帶頂，頂緣向鼻尖收低；後緣斜著收回橘帶。
            self.slanted.append(([(tip - 0.3, 0.2), (tip - 0.3, 1.22), (tip + 1.2, 1.50), (tip + 2.6, 1.72),
                                  (tip + 4.2, ORANGE[1]), (back(0.0, ORANGE[0])[0], ORANGE[1]),
                                  back(0.0, ORANGE[0]), back(0.0, 0.2)], ORANGE_KIND))
            # 前門後面那塊往後斜的黑色。
            self.slanted.append(([back(0.6, low), back(0.6, ORANGE[0]), back(2.6, ORANGE[0]), back(2.6, low)], BLACK))
            # 黑線的尖端。
            start, full = door + 2.3, door + 3.1
            self.slanted.append(([(start, BLACK_LINE[0]), (full, BLACK_LINE[1]), (full, BLACK_LINE[0])], BLACK))
            self.bands.append((full, BLACK_LINE[0], far, BLACK_LINE[1], BLACK))
        else:
            self.bands = [(-far, ORANGE[0], far, ORANGE[1], ORANGE_KIND), (-far, BLACK_LINE[0], far, BLACK_LINE[1], BLACK)]

        self.walls(WINDOW_WIDTH)

    def walls(self, window_width):
        """只畫在側牆上的長方形：車窗、客用門旁的行先表示器。"""
        self.wall = [(c - window_width / 2, WINDOW[0], c + window_width / 2, WINDOW[1], GLASS) for c in self.windows]
        doors = self.doors[self.crew:]
        middle = (doors[0][0] + doors[-1][1]) / 2
        for z0, z1 in doors:
            if (z0 + z1) / 2 < middle:
                self.wall.append((z1 + SIGN_FROM, SIGN[0], z1 + SIGN_FROM + SIGN_WIDTH, SIGN[1], DARK))
            else:
                self.wall.append((z0 - SIGN_FROM - SIGN_WIDTH, SIGN[0], z0 - SIGN_FROM, SIGN[1], DARK))

    def door_parts(self, number):
        """一扇門裡的長方形：門縫線一圈、門窗。"""
        (z0, z1), (y0, y1), (w0, w1, width) = self.doors[number], self.door_height[number], self.door_window[number]
        middle = (z0 + z1) / 2
        return [(z0, y0, z0 + DOOR_LINE, y1, FRAME), (z1 - DOOR_LINE, y0, z1, y1, FRAME),
                (z0, y0, z1, y0 + DOOR_LINE, FRAME), (z0, y1 - DOOR_LINE, z1, y1, FRAME),
                (middle - width / 2, w0, middle + width / 2, w1, GLASS)]

    def body(self, polygon, wall: bool, side: bool = False):
        """車身上的一塊（放大後的座標）→（多邊形, 類別, 第幾扇門或 -1）。`side`：
        朝側面但不在平的側牆上的面（車鼻收窄的地方），只有乘務員門畫在上面。"""
        pieces = [(polygon, -1)]
        if wall or side:
            for number, (z0, z1) in enumerate(self.doors):
                if not wall and number >= self.crew:
                    continue
                y0, y1 = self.door_height[number]
                region = [(z0, y0), (z1, y0), (z1, y1), (z0, y1)]
                after = []
                for piece, door in pieces:
                    if door >= 0:
                        after.append((piece, door))
                        continue
                    inside, outside = carve(piece, region)
                    if inside:
                        after.append((inside, number))
                    after += [(rest, -1) for rest in outside]
                pieces = after
        out = []
        for piece, door in pieces:
            first = self.door_parts(door) if door >= 0 else (self.wall if wall else [])
            for cell, kind in grid(piece, first):
                if kind is not None:
                    out.append((cell, kind, door))
                    continue
                pending = [cell]
                for region, paint in self.slanted:
                    left = []
                    for part in pending:
                        inside, outside = carve(part, region)
                        if inside:
                            out.append((inside, paint, door))
                        left += outside
                    pending = left
                for part in pending:
                    out += [(final, WHITE if paint is None else paint, door) for final, paint in grid(part, self.bands)]
        return out


# 車鼻白色的頂：鼻尖後幾 m 起、寬 ±幾 m，到幾 m 寬 ±幾 m，到幾 m 超出車寬（見 Paint）。
NOSE_TOP = (1.8, 0.2, 3.0, 0.8, 5.5)
ORANGE_KIND = 1  # `ORANGE` 是橘帶的高度，類別另外記


# ---------------------------------------------------------------- 車體

def front_pieces(uv, mask: bool):
    """車鼻上面的一個三角形（貼圖座標）：（多邊形, 類別或 None）。"""
    cells, pending = [], [uv]
    regions = [(region, GLASS) for region in WINDSCREEN]
    regions += [([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], kind) for (x0, y0, x1, y1), kind in LAMPS]
    if mask:
        regions.append((MASK, BLACK))
    for region, paint in regions:
        left = []
        for piece in pending:
            inside, outside = cut.carve(piece, region)
            if inside:
                cells.append((inside, paint))
            left += outside
        pending = left
    return cells + [(piece, None) for piece in pending]


def cut_body(part, paint: Paint):
    """車體 →（3 × 3 放大後的頂點, 類別, 第幾扇門或 -1）與天線鰭的面。"""
    width, height = part["image"].size
    grow = lambda p: np.array([p[0] * WIDTH, p[1] * HEIGHT, paint.z(p[2])])  # noqa: E731
    out, fin = [], []
    stretched = 0

    def add(polygon, kind, door=-1):
        for i in range(1, len(polygon) - 1):
            out.append((np.array([polygon[0], polygon[i], polygon[i + 1]]), kind, door))

    top = False

    def tongue(polygon):
        """朝上的面：白色舌頭裡的部分直接記成白的，回傳外面剩下的幾塊。"""
        if not top or paint.tongue is None:
            return [polygon]
        inside, outside = carve(polygon, paint.tongue, across=0)
        if inside:
            add(inside, WHITE)
        for piece in outside:
            add(piece, ORANGE_KIND)
        return []

    for face in part["faces"]:
        old = part["world"][face]
        normal = np.cross(old[1] - old[0], old[2] - old[0])
        size = np.linalg.norm(normal)
        if size < 1e-9:
            continue
        normal /= size
        u = part["uv"][face, 0]
        v = part["uv"][face, 1]
        u = (u - np.floor(u.min() + 1e-9)) * width
        v = (v - np.floor(v.min() + 1e-9)) * height
        corners = [grow(p) for p in old]
        # 頭車加長那一段的兩個邊界：跨過去的面先在邊界切開，每一塊各自放大，
        # 斜的面也不會變形。
        whole = [[p for p in old]]
        if paint.cab:
            for edge in STRETCH:
                whole = [half for piece in whole for half in halves(piece, 1.0, 0.0, edge) if half]
        pieces = [[grow(p) for p in piece] for piece in whole]
        stretched += len(pieces) > 1

        if np.abs(old[:, 0]).min() > WALL + 0.005:
            continue  # 貼在牆外的小牌（標誌、車號、行先表示器）
        if np.abs(old[:, 0]).max() < 0.05 and old[:, 1].min() > 3.7:
            fin.append((np.array(corners), DARK))  # 天線鰭
            continue
        if v.min() >= SKIRT_ROW or old[:, 1].max() <= 1.16:
            for piece in pieces:
                add(piece, SKIRT)  # 裙板、車鼻底面、車底
            continue
        if abs(normal[2]) > 0.99:
            add(corners, WHITE)  # 連結面那一端的端牆
            continue

        wall = abs(normal[0]) > 0.99 and np.abs(old[:, 0]).min() > WALL - 0.02
        # 乘務員門在車鼻剛開始收窄的地方：朝側面的面都算。
        side = paint.crew > 0 and abs(normal[0]) > 0.9
        # 車鼻朝上的面：中間那條「舌頭」是白的，其餘照橘色的頂緣畫。
        top = paint.cab and normal[1] > TOP
        uv = [(float(u[i]), float(v[i])) for i in range(3)]
        e1 = (uv[1][0] - uv[0][0], uv[1][1] - uv[0][1])
        e2 = (uv[2][0] - uv[0][0], uv[2][1] - uv[0][1])
        det = e1[0] * e2[1] - e1[1] * e2[0]
        if paint.cab and u.max() <= FRONT[0] and v.max() < FRONT[1] and abs(det) > 1e-6:
            def lift(point):
                px, py = point[0] - uv[0][0], point[1] - uv[0][1]
                s = (px * e2[1] - py * e2[0]) / det
                t = (e1[0] * py - e1[1] * px) / det
                return corners[0] + (corners[1] - corners[0]) * s + (corners[2] - corners[0]) * t

            for polygon, kind in front_pieces(uv, paint.mask):
                lifted = [lift(p) for p in polygon]
                if kind is not None:
                    add(lifted, kind)
                    continue
                for rest in tongue(lifted):
                    for cell, colour, door in paint.body(rest, False):
                        add(cell, colour, door)
            continue
        for piece in pieces:
            for rest in tongue(piece):
                for cell, colour, door in paint.body(rest, wall, side):
                    add(cell, colour, door)
    return out, fin, stretched


def same_section(part):
    """頭車加長的那一段是不是等斷面：兩端與中間各切一刀，外形（取樣）離第一刀
    最遠多少公尺。加長是把這一段沿車長拉開，斷面不一樣的話拉出來的面會歪。"""
    def outline(z):
        points = []
        for face in part["faces"]:
            corners = part["world"][face]
            ends = []
            for i in range(3):
                p, q = corners[i], corners[(i + 1) % 3]
                if (p[2] - z) * (q[2] - z) < 0:
                    ends.append((p + (q - p) * ((z - p[2]) / (q[2] - p[2])))[:2])
            if len(ends) == 2:
                steps = max(2, int(np.linalg.norm(ends[1] - ends[0]) / 0.01) + 1)
                points.append(ends[0] + (ends[1] - ends[0]) * np.linspace(0, 1, steps)[:, None])
        return np.concatenate(points)

    def apart(one, other):
        return max(float(np.min(np.linalg.norm(other - p, axis=1))) for p in one)

    a, b = STRETCH
    first = outline(a + 1e-3)
    worst = 0.0
    for z in np.linspace(a + 1e-3, b - 1e-3, 9)[1:]:
        cut_here = outline(float(z))
        worst = max(worst, apart(first, cut_here), apart(cut_here, first))
    return worst


# ---------------------------------------------------------------- 集電弓

def box(x0, x1, y0, y1, z0, z1):
    """長方體的 12 個三角形（原座標的軸，面朝外）。"""
    return prism([(z0, y0), (z1, y0), (z1, y1), (z0, y1)], x0, x1)


def prism(profile, x0, x1):
    """（z, y）上的凸多邊形 profile 沿 x 由 x0 拉到 x1：側面與兩個端面，面朝外。"""
    count = len(profile)
    twice = sum(profile[i][0] * profile[(i + 1) % count][1] - profile[(i + 1) % count][0] * profile[i][1] for i in range(count))
    if twice > 0:
        profile = profile[::-1]  # 從 +x 看逆時針（z 往左），就是（z, y）上的順時針
    near = [np.array([x1, y, z]) for z, y in profile]
    far = [np.array([x0, y, z]) for z, y in profile]
    out = []
    for i in range(1, count - 1):
        out.append(np.array([near[0], near[i], near[i + 1]]))
        out.append(np.array([far[0], far[i + 1], far[i]]))
    for i in range(count):
        j = (i + 1) % count
        out.append(np.array([near[i], far[i], far[j]]))
        out.append(np.array([near[i], far[j], near[j]]))
    return out


def beam(start, end, thick, wide):
    """（z, y）上由 start 到 end 的一根桿子：斷面 thick（在 z-y 平面裡）× wide（沿 x）。"""
    (z0, y0), (z1, y1) = start, end
    length = float(np.hypot(z1 - z0, y1 - y0))
    nz, ny = -(y1 - y0) / length * thick / 2, (z1 - z0) / length * thick / 2
    return prism([(z0 + nz, y0 + ny), (z1 + nz, y1 + ny), (z1 - nz, y1 - ny), (z0 - nz, y0 - ny)], -wide / 2, wide / 2)


def pantograph(at: float):
    """集電弓、絕緣子蓋與兩片導風板（放大後的座標，原座標的軸）：（頂點, 類別）。"""
    roof = 3.65
    out = []
    # 絕緣子蓋：車頂中央一個兩頭斜的矮罩。
    out += [(t, WHITE) for t in prism([(at - 1.7, roof - 0.05), (at - 1.1, roof + 0.26), (at + 1.1, roof + 0.26),
                                       (at + 1.7, roof - 0.05)], -0.62, 0.62)]
    # 導風板：車頂兩側各一片梯形的板。
    for side in (-1, 1):
        x0, x1 = sorted((side * 1.33, side * 1.41))
        out += [(t, WHITE) for t in prism([(at - 2.7, 3.42), (at - 1.8, 4.12), (at + 1.8, 4.12), (at + 2.7, 3.42)], x0, x1)]
    # 單臂式集電弓：底座、下臂、上臂、弓頭。
    out += [(t, DARK) for t in box(-0.38, 0.38, roof + 0.26, roof + 0.34, at - 0.55, at + 0.55)]
    out += [(t, DARK) for t in beam((at + 0.45, roof + 0.34), (at - 0.45, roof + 0.66), 0.09, 0.12)]
    out += [(t, DARK) for t in beam((at - 0.45, roof + 0.66), (at + 0.10, roof + 0.90), 0.08, 0.10)]
    out += [(t, DARK) for t in box(-0.95, 0.95, roof + 0.88, roof + 0.96, at - 0.02, at + 0.22)]
    return out


def solid_plate(plate, point, normal):
    """一片沒有厚度的薄片（頂點, 類別）→ `PLATE` 厚的封閉實心片：兩面各往外推
    一半，邊緣補上側面。"""
    if not plate:
        return []
    towards = normal(plate[0][0])
    fronts = [(c if np.dot(normal(c), towards) > 0 else c[::-1], kind) for c, kind in plate]
    total = sum(normal(c) for c, _ in fronts)
    half = total / np.linalg.norm(total) * PLATE / 2
    out, edges = [], {}
    for corners, kind in fronts:
        out.append((corners + half, kind))
        out.append((corners[::-1] - half, kind))
        for a, b in ((0, 1), (1, 2), (2, 0)):
            edges[(point(corners[a]), point(corners[b]))] = (corners[a], corners[b], kind)
    for (a, b), (start, end, kind) in edges.items():
        if (b, a) in edges:
            continue  # 片裡面的邊
        out.append((np.stack([start + half, start - half, end - half]), kind))
        out.append((np.stack([start + half, end - half, end + half]), kind))
    return out


# ---------------------------------------------------------------- GLB

def write_glb(path: Path, triangles, materials=None):
    """`triangles`：（3 × 3 的頂點, 材質, 門名或 None）。車身一個 mesh、一個
    node，每扇門各自一個 mesh、一個 node；一個材質一個 primitive，頂點併起來。"""
    materials = materials or MATERIALS
    binary = bytearray()
    views, accessors, meshes = [], [], []
    parts = [None] + sorted({part for _, _, part in triangles if part})
    for part, material in [(part, material) for part in parts for material in range(len(materials))]:
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
        "asset": {"version": "2.0", "generator": "tools/texture-palette/thsr_700t.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(meshes)))}],
        "nodes": [{"mesh": number, "name": mesh["name"]} for number, mesh in enumerate(meshes)],
        "meshes": meshes,
        "materials": [{"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [((c / 255) ** 2.2) for c in PREVIEW[i]] + [1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0}}
            for i, name in enumerate(materials)],
        "buffers": [{"byteLength": len(binary)}], "bufferViews": views, "accessors": accessors,
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    path.write_bytes(b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I4s", len(text), b"JSON") + text
                     + struct.pack("<I4s", len(binary), b"BIN\0") + bytes(binary))


# ---------------------------------------------------------------- 一節車

def build(path: Path, unit: str, train: str = "thsr"):
    gltf, blob, digest = cut.read_glb(path)
    pieces = cut.parts(gltf, blob)
    body = max(pieces, key=lambda p: np.ptp(p["world"][:, 2]))
    paint = Paint("middle" if unit == "pantograph" else unit, train)
    section = same_section(body) if paint.cab else 0.0
    if section > SECTION:
        raise SystemExit(f"{path.name}: 加長的那一段不是等斷面（外形差 {section:.3f} m）")
    scaled, fin, stretched = cut_body(body, paint)
    for piece in pieces:
        if piece is body:
            continue
        world = piece["world"]
        low, high = world.min(0), world.max(0)
        size = high - low
        if size[2] > 2.5:
            # 轉向架：位置跟著車體，本身不縮放。
            middle = (low[2] + high[2]) / 2
            moved = world + np.array([0, 0, paint.z(middle) - middle])
            scaled += [(moved[face], DARK, -1) for face in piece["faces"]]
        elif size[1] > 1.5:
            # 通道幌：照車體放大；兩個端面拿掉（一個在車體裡，一個在連結面上）。
            grown = np.stack([world[:, 0] * WIDTH, world[:, 1] * HEIGHT, np.array([paint.z(z) for z in world[:, 2]])], 1)
            for face in piece["faces"]:
                corners = grown[face]
                if np.ptp(corners[:, 2]) < 1e-6:
                    continue
                scaled.append((corners, DARK, -1))
        # 其餘（車鼻外露的連結器）不要。
    if unit == "pantograph":
        scaled += [(corners, kind, -1) for corners, kind in pantograph(PANTOGRAPH_AT)]

    def normal(corners):
        return np.cross(corners[1] - corners[0], corners[2] - corners[0])

    def point(corner):
        return tuple(int(round(v * 1000)) for v in corner)

    # 天線鰭是沒有厚度的薄片：改成有厚度的實心片，兩側都看得到。
    plates, seen = [], set()
    for corners, kind in fin:
        key = frozenset(point(c) for c in corners)
        if len(key) == 3 and key not in seen and np.linalg.norm(normal(corners)) > 1e-7:
            seen.add(key)
            plates.append((corners, kind))
    scaled += [(corners, kind, -1) for corners, kind in solid_plate(plates, point, normal)]

    # 轉成輸出的軸（+y 上、車沿 x、駕駛室在 +x）：旋轉，行列式 +1。
    turned = [(np.stack([-c[:, 2], c[:, 1], c[:, 0]], 1), kind, door) for c, kind, door in scaled]
    xs = np.concatenate([c[:, 0] for c, _, _ in turned if True])
    shift = -(xs.max() + xs.min()) / 2
    seen, out = set(), []
    for corners, kind, door in turned:
        corners = corners + np.array([shift, 0, 0])
        key = frozenset(point(corner) for corner in corners)
        if len(key) < 3 or key in seen:
            continue  # 沒有面積，或同一個面的另一面
        if np.linalg.norm(normal(corners)) < 1e-7:
            continue
        seen.add(key)
        out.append((corners, kind, door))
    out += hoods(out, (-1,) if paint.cab else (-1, 1))
    return name_doors(out), digest, {"stretched": stretched, "windows": len(paint.windows),
                                     "window_pitch": round(paint.windows[1] - paint.windows[0], 4),
                                     "section": round(section, 4), "crew_doors": paint.crew}


def hoods(triangles, ends):
    """每個連結端的全周幌（輸出的軸）：端面外形（凸包）拉到離連結面 HOOD_GAP 的
    一圈。"""
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
        skirt = max((float(corners[:, 1].max()) for corners, kind in cap if kind == SKIRT), default=SKIRT_TOP)
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
                kind = SKIRT if (p[0] + q[0]) / 2 < skirt else WHITE
                quad = [np.array([x0, *p]), np.array([x1, *p]), np.array([x1, *q]), np.array([x0, *q])]
                for corners in (np.array(quad[:3]), np.array([quad[0], quad[2], quad[3]])):
                    normal = np.cross(corners[1] - corners[0], corners[2] - corners[0])
                    outward = np.array([0, (p[0] + q[0]) / 2 - centre[0], (p[1] + q[1]) / 2 - centre[1]])
                    if np.sign(np.dot(normal, outward)) != turn:
                        corners = corners[::-1]
                    out.append((corners, kind, -1))
    return out


def name_doors(triangles):
    """每扇門照側面分開，由 +x 那一端（頭車的車頭）往後編號。回傳（頂點, 類別,
    門名或 None）與每扇門的範圍。"""
    groups = {}
    for number, (corners, _, door) in enumerate(triangles):
        if door >= 0:
            side = "left" if corners[:, 2].mean() < 0 else "right"  # 遊戲的 +y（左）是這裡的 -z
            groups.setdefault((side, door), []).append(number)
    names, doors = {}, []
    for (side, door), found in sorted(groups.items()):
        name = f"door-{side}-{door + 1}"
        points = np.concatenate([triangles[number][0] for number in found])
        for number in found:
            names[number] = name
        doors.append({"name": name, "triangles": len(found),
                      "min": [round(float(v), 3) for v in points.min(0)], "max": [round(float(v), 3) for v in points.max(0)]})
    return [(corners, kind, names.get(number)) for number, (corners, kind, _) in enumerate(triangles)], doors


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--train", choices=sorted(TRAINS), default="thsr")
    parser.add_argument("--cab", type=Path, required=True)
    parser.add_argument("--middle", type=Path, required=True)
    parser.add_argument("--tail", type=Path, help="另一端的頭車（series700）")
    parser.add_argument("--green", type=Path, help="一扇門的寬窗車（series700）")
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    train = TRAINS[args.train]
    materials = train["materials"]
    report = {}
    for unit, source in train["units"]:
        path = getattr(args, source)
        if path is None:
            raise SystemExit(f"--train {args.train} 要 --{source}")
        (triangles, doors), digest, notes = build(path.expanduser(), unit, args.train)
        if digest != SHA256[source]:
            raise SystemExit(f"{path.name}: 不是這個工具認得的原檔（SHA-256 {digest}）")
        name = f"{train['prefix']}-{unit}"
        write_glb(args.out_dir / f"{name}.glb", triangles, materials)
        points = np.concatenate([c for c, _, _ in triangles])
        counts = {materials[k]: sum(1 for _, kind, _ in triangles if kind == k) for k in range(len(materials))}
        report[name] = {"sha256": digest, "triangles": len(triangles), "materials": counts,
                        "min": [round(float(v), 3) for v in points.min(0)], "max": [round(float(v), 3) for v in points.max(0)],
                        "doors": doors, **notes}
    (args.out_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
