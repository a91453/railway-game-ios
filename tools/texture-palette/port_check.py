#!/usr/bin/env python3
"""舊版車轉成遊戲 GLB 之後的自動檢查：工作室換家審查歷次退回的項目，轉檔的人
送審前先自己跑到全過（流程見私有素材庫 `docs/studio/rolling-stock-studio.md`「舊版轉新版」）。

    uv run --with numpy python -I tools/texture-palette/port_check.py OUT_DIR \
        [--old OLD_CAB.glb --nose-scale 1.19036,0.99310,1.2 --nose-from 4.9] \
        [--max-yaw 4] [--gauge 1.435] [--md OUT_DIR/port-check.md]

`OUT_DIR` 是轉檔工具（`kyushu_800.py`、`kyushu_n700.py`、`n700s.py` 等）輸出的資料夾：
每一節車一個 GLB（軸照 `glb_to_swift.py` 讀的：+y 上、車沿 x、駕駛室在 +x、連結面在
±半車長、軌面 y 0），旁邊有 `report.json` 就一起對。只用 numpy；舊版原檔只在
`--old` 時讀，不寫出任何東西（作者的原檔不進這個公開 repo）。

查的項目（括號裡是第一次退回它的審查）：

1. 異色共面重疊：毫米格點上同一平面、不同顏色的兩個三角形，投影交疊 > 1 mm²
   （800 系 r1 14 對、N700S r1 46／19／7 對）；放寬版：法線夾角 ≤ 2°、兩邊頂點離對方
   平面都 < 5 cm（照 studio-brief §2 的「同平面不同色的量法」）。顏色看 GLB 材質的
   baseColorFactor，同色不同格位（門板與車身白）算同色。
2. 退化面：取整到毫米後三點共線（800 系 r1 第 345 面）。
3. 朝內的面：側牆（離中線 > 九成半寬、在車頂肩部以下）與車頂的面，法線指向車裡
   （800 系 r1 肩部兩片、N700S r1 一片玻璃）。
4. 每扇門一個 node：名字有 `-door-` 的 node 各是一扇門；拿掉它以後，門四周外擴
   10 cm 的方框裡，牆加門剛好蓋滿：缺口與重疊都 ≤ 1 mm²（800 系 r1、N700S r1）。
   `report.json` 有門的範圍時，再照遊戲 `Door.contains` 的判法，用 0.5 mm 與 2 mm
   兩種容差數框進去的面：門 node 的面全在框裡、牆的面一個都不在（800 系 r2 在
   2 mm 多框 12 面白牆）。遊戲裡的 `contains` 預設容差要用 0.5 mm。
5. 全周幌轉角：任兩節的連結端（車頭有頭燈的那端不算）面對面，兩節各繞連結點轉
   相對偏航的一半，左右彎、0 到 `--max-yaw` 度每 0.5 度，在離軌面 0.6 m 到 3.4 m 的
   切面量交疊面積，> 1 mm² 就不過（800 系 r1 從 1.36° 起相交、N700S r1 從 1.364° 起）。
6. 燈：頭車頭燈與尾燈都有、左右兩肩面數相同、位置左右對稱 5 mm 內；中間車沒有燈面
   （N700S r1 白燈左右 11／12 面）。
7. 車鼻和舊版一樣（`--old` 才查）：舊版頭車照 `--nose-scale`（沿車、高、寬）縮放、
   鼻尖對齊，`x > --nose-from` 的新殼頂點與面心到舊殼的距離、舊殼到新殼的距離，左右
   兩側分開報，p95 ≤ 1 mm、最大 ≤ 2 mm（N700S r2：右半整個換成左半的鏡像，差 147 mm）。
8. 軌距：離軌面 5 cm 內的輪子踏面，兩側橫向範圍都蓋住軌距的一半（標準軌 ±0.7175 m）。
9. `report.json` 的面數和 GLB 一樣。

全過時結束碼 0，有一項不過就是 1。印出的表照抄進送審的 REQUEST.md。
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from math import cos, radians, sin
from pathlib import Path

import numpy as np

AREA_MM2 = 1.0          # 交疊、缺口的門檻（mm²）
NEAR_ANGLE = 2.0        # 放寬版共面：法線夾角（度）
NEAR_DIST = 0.05        # 放寬版共面：離對方平面（m）
DOOR_BOX = 0.10         # 門四周外擴的方框（m）
LAMP_MIRROR = 0.005     # 燈左右對稱（m）
NOSE_P95 = 0.001        # 車鼻和舊版的距離（m）
NOSE_MAX = 0.002
NOSE_ABOVE = 1.2        # 車鼻只比離軌面這個高度以上（m）
HEIGHTS = (0.6, 1.0, 1.5, 2.0, 2.5, 3.0, 3.4)
END_ZONE = 1.0          # 連結端往車裡取多長來切（m）
OUTER_SKIN = 0.03       # 朝內檢查：離斷面最外層多近算外殼（m）


# --- 讀 GLB -------------------------------------------------------------------

def read_glb(path: Path):
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit(f"{path}: not a GLB")
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + length]), data[20 + length + 8:]


def _accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    kind = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[acc["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    item = np.dtype(kind).itemsize
    stride = view.get("byteStride", item * width)
    if stride == item * width:
        out = np.frombuffer(blob, kind, acc["count"] * width, start).reshape(acc["count"], width)
    else:
        out = np.stack([np.frombuffer(blob, kind, width, start + k * stride) for k in range(acc["count"])])
    return out.astype(float) if kind == "<f4" else out.astype(np.int64)


def _matrix(node):
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


class Car:
    """一節車的三角形：`tri` (n,3,3) 公尺、`mat` 材質序號、`colour` 顏色鍵、`node` node 名。"""

    def __init__(self, path: Path | None, swift=None):
        if swift is not None:
            self._from_swift(*swift)
            return
        gltf, blob = read_glb(path)
        self.name = path.stem
        materials = gltf.get("materials", [])
        self.material_names = [m.get("name", str(i)) for i, m in enumerate(materials)]
        colours = []
        for m in materials:
            factor = m.get("pbrMetallicRoughness", {}).get("baseColorFactor")
            colours.append(tuple(round(v, 4) for v in factor) if factor else m.get("name"))
        tris, mats, nodes = [], [], []

        def walk(index, parent):
            node = gltf["nodes"][index]
            matrix = parent @ _matrix(node)
            if "mesh" in node:
                for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                    local = _accessor(gltf, blob, prim["attributes"]["POSITION"])
                    world = (matrix[:3, :3] @ local.T).T + matrix[:3, 3]
                    faces = _accessor(gltf, blob, prim["indices"]).reshape(-1, 3)
                    if np.linalg.det(matrix[:3, :3]) < 0:
                        faces = faces[:, ::-1]
                    tris.append(world[faces])
                    mats.extend([prim.get("material", -1)] * len(faces))
                    nodes.extend([node.get("name", str(index))] * len(faces))
            for child in node.get("children", []):
                walk(child, matrix)

        for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
            walk(root, np.eye(4))
        self.tri = np.concatenate(tris) if tris else np.zeros((0, 3, 3))
        self.mat = np.array(mats, int)
        self.node = np.array(nodes, object)
        self.colour = np.array([hash(colours[m]) if m >= 0 else -1 for m in self.mat])
        self.node_names = [n.get("name", str(i)) for i, n in enumerate(gltf["nodes"])]
        lo, hi = self.tri.reshape(-1, 3).min(0), self.tri.reshape(-1, 3).max(0)
        self.lo, self.hi = lo, hi
        self.half_width = max(abs(lo[2]), abs(hi[2]))

    def _from_swift(self, name, text, palette):
        """`glb_to_swift.py` 寫的一節（base64）：毫米整數點、三角形與色票序號；遊戲軸轉回 GLB 軸。"""
        import base64
        data = base64.b64decode("".join(text.split()))
        count = struct.unpack_from("<H", data, 0)[0]
        points = np.array(struct.unpack_from(f"<{count * 3}h", data, 2), float).reshape(-1, 3) / 1000
        points = np.stack([points[:, 0], points[:, 2], -points[:, 1]], 1)
        at = 2 + count * 6
        faces = struct.unpack_from("<H", data, at)[0]
        rows = np.array(struct.unpack_from("<" + "HHHB" * faces, data, at + 2), int).reshape(-1, 4)
        self.name = name
        self.material_names = list(palette)
        self.tri = points[rows[:, :3]]
        self.mat = rows[:, 3]
        self.node = np.array([name] * len(rows), object)
        self.colour = np.array([hash(self.material_names[m]) for m in self.mat])
        self.node_names = [name]
        self.lo, self.hi = self.tri.reshape(-1, 3).min(0), self.tri.reshape(-1, 3).max(0)
        self.half_width = max(abs(self.lo[2]), abs(self.hi[2]))

    def same_colour(self, pairs):
        """`--same door=white`：這兩個格位當同色。"""
        for a, b in pairs:
            if a in self.material_names and b in self.material_names:
                ia, ib = self.material_names.index(a), self.material_names.index(b)
                target = self.colour[self.mat == ib][0] if (self.mat == ib).any() else -ib - 2
                self.colour[self.mat == ia] = target

    def material(self, name):
        return self.material_names.index(name) if name in self.material_names else None

    def where(self, i):
        c = self.tri[i].mean(0)
        return f"#{i} {self.material_names[self.mat[i]]} ({c[0]:.3f}, {c[1]:.3f}, {c[2]:.3f})"


# --- 2D 幾何（三角形都是凸的，交集用 Sutherland–Hodgman 就準） ---------------------

def _ccw(p):
    a = 0.5 * float(np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1]))
    return (p[::-1], -a) if a < 0 else (p, a)


def poly_area(p):
    if len(p) < 3:
        return 0.0
    return abs(0.5 * float(np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])))


def clip(subject, window):
    """凸多邊形 `subject` ∩ 凸多邊形 `window`（都是 (k,2)）。"""
    window, _ = _ccw(np.asarray(window, float))
    out = [tuple(v) for v in np.asarray(subject, float)]
    for k in range(len(window)):
        if not out:
            break
        a, b = window[k], window[(k + 1) % len(window)]
        edge = b - a

        def inside(p):
            return edge[0] * (p[1] - a[1]) - edge[1] * (p[0] - a[0]) >= -1e-15

        def cross(p, q):
            d = np.subtract(q, p)
            den = edge[0] * d[1] - edge[1] * d[0]
            t = (edge[1] * (p[0] - a[0]) - edge[0] * (p[1] - a[1])) / den if den else 0.0
            return (p[0] + t * d[0], p[1] + t * d[1])

        inp, out = out, []
        for i, cur in enumerate(inp):
            prev = inp[i - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(cross(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(cross(prev, cur))
    return np.array(out) if len(out) >= 3 else np.zeros((0, 2))


def overlap(p, q):
    return poly_area(clip(p, q))


# --- 1、2、3：共面、退化、朝內 ---------------------------------------------------

def coplanar(car: Car):
    """毫米格點上同一平面（整數法線＋平面常數）、不同色的兩個三角形，投影交疊 > 1 mm²。"""
    grid = np.round(car.tri * 1000).astype(np.int64)
    normals = np.cross(grid[:, 1] - grid[:, 0], grid[:, 2] - grid[:, 0])
    degenerate = [i for i in range(len(grid)) if not normals[i].any()]
    groups = {}
    for i, n in enumerate(normals):
        if not n.any():
            continue
        n = n // np.gcd.reduce(np.abs(n[n != 0]))
        if next(v for v in n if v) < 0:
            n = -n
        groups.setdefault((tuple(int(v) for v in n), int(n @ grid[i, 0])), []).append(i)
    found = []
    for (n, _), members in groups.items():
        if len(members) < 2 or len({car.colour[i] for i in members}) < 2:
            continue
        keep = [a for a in range(3) if a != int(np.argmax(np.abs(n)))]
        for x, i in enumerate(members):
            pi = grid[i][:, keep].astype(float)
            for j in members[x + 1:]:
                if car.colour[i] == car.colour[j]:
                    continue
                pj = grid[j][:, keep].astype(float)
                if (pi.max(0) < pj.min(0)).any() or (pj.max(0) < pi.min(0)).any():
                    continue
                area = overlap(pi, pj)
                if area > AREA_MM2:
                    found.append((area, i, j))
    return sorted(found, reverse=True), degenerate


def near_coplanar(car: Car):
    """放寬版：法線夾角 ≤ 2°（同向或反向）、兩邊頂點離對方平面都 < 5 cm、不同色、投影交疊 > 1 mm²。"""
    c = car.tri
    n = np.cross(c[:, 1] - c[:, 0], c[:, 2] - c[:, 0])
    length = np.linalg.norm(n, axis=1)
    ok = length > 1e-12
    n = n / np.maximum(length, 1e-15)[:, None]
    lo, hi = c.min(1) - NEAR_DIST, c.max(1) + NEAR_DIST
    limit = cos(radians(NEAR_ANGLE))
    found = []
    for i in range(len(c)):
        if not ok[i]:
            continue
        rest = slice(i + 1, None)
        cand = np.nonzero(ok[rest] & (lo[rest] <= c[i].max(0)).all(1) & (hi[rest] >= c[i].min(0)).all(1)
                          & (car.colour[rest] != car.colour[i]) & (np.abs(n[rest] @ n[i]) >= limit))[0] + i + 1
        for j in cand:
            if np.abs((c[j] - c[i][0]) @ n[i]).max() >= NEAR_DIST or np.abs((c[i] - c[j][0]) @ n[j]).max() >= NEAR_DIST:
                continue
            keep = [k for k in range(3) if k != int(np.argmax(np.abs(n[i])))]
            area = overlap(c[i][:, keep], c[j][:, keep]) * 1e6
            if area > AREA_MM2:
                found.append((area, i, j))
    return sorted(found, reverse=True)


def _ray_hits(origin, direction, tri, reach):
    """從 `origin` 往 `direction` 的射線，在 `reach` 公尺內打到 `tri` 裡的幾個三角形（Möller–Trumbore）。"""
    e1, e2 = tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    p = np.cross(direction, e2)
    det = (e1 * p).sum(1)
    good = np.abs(det) > 1e-12
    inv = np.where(good, 1 / np.where(good, det, 1), 0)
    t0 = origin - tri[:, 0]
    u = (t0 * p).sum(1) * inv
    q = np.cross(t0, e1)
    v = (q * direction).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    return int((good & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4) & (t < reach)).sum())


def inward(car: Car, skin=OUTER_SKIN):
    """車殼外層朝內的面（800 系 r1 肩部兩片白、N700S r1 一片玻璃）。

    斷面看成繞車身中心線（x 軸、高度在車高的 55%）的一圈：沿車每 0.5 m、繞中心每 7.5°
    一格，離中心最遠的那層（`skin` 以內）是外殼。外殼上法線指向中心線、而且背面那一側
    （往外）什麼都沒有的面就是翻了；背面有東西的（例：集電弓擋風板的內側面，背面是它
    自己的外側面）是薄板的另一面，不算。朝下的格子（車底）、車端（法線大多沿車）不查。"""
    c = car.tri
    n = np.cross(c[:, 1] - c[:, 0], c[:, 2] - c[:, 0])
    length = np.linalg.norm(n, axis=1)
    ok = length > 1e-12
    n = n / np.maximum(length, 1e-15)[:, None]
    centre = c.mean(1)
    yc = 0.55 * car.hi[1]
    radial = np.stack([np.zeros(len(c)), centre[:, 1] - yc, centre[:, 2]], 1)
    r = np.linalg.norm(radial, axis=1)
    u = radial / np.maximum(r, 1e-9)[:, None]
    angle = np.degrees(np.arctan2(radial[:, 1], radial[:, 2]))
    key = np.stack([np.floor(centre[:, 0] / 0.5), np.floor(angle / 7.5)], 1).astype(int)
    outer = {}
    for k, rr in zip(map(tuple, key), r):
        outer[k] = max(outer.get(k, 0.0), rr)
    shell = np.array([rr >= outer[tuple(k)] - skin for k, rr in zip(key, r)])
    downward = (angle < -45) & (angle > -135)
    sideways = np.linalg.norm(n[:, 1:], axis=1) >= 0.5
    candidates = np.nonzero(ok & shell & ~downward & sideways & (r > 0.5) & ((n * u).sum(1) < -0.3))[0]
    # 背面 0.5 m 內沒東西、而且往背面一路打穿整節車打到偶數個面（0：外面什麼都沒有；2：
    # 穿過一個突出物）才算翻了。奇數是從車殼裡面打出去：面朝外是對的（九州 N700 低低的
    # 車鼻頂面在中心線下面、法線朝上，背面的車底在 1 m 以外）。
    return [int(i) for i in candidates
            if _ray_hits(centre[i], -n[i], c, 0.5) == 0 and _ray_hits(centre[i], -n[i], c, 50.0) % 2 == 0]


# --- 4：門 ----------------------------------------------------------------------

def door_nodes(car: Car):
    return sorted({n for n in car.node if "-door-" in n})


def door_pieces(car: Car):
    """拿掉每扇門以後牆面完整：門四周外擴 10 cm 的方框裡，牆＋門剛好蓋滿。"""
    rows = []
    for name in door_nodes(car):
        own = np.nonzero(car.node == name)[0]
        pts = car.tri[own].reshape(-1, 3)
        side = float(np.sign(pts[:, 2].mean()))
        x0, y0 = pts[:, 0].min() - DOOR_BOX, pts[:, 1].min() - DOOR_BOX
        x1, y1 = pts[:, 0].max() + DOOR_BOX, pts[:, 1].max() + DOOR_BOX
        box = np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])
        # 這一側的面（三點都在這一側、最外的點到 3/4 車寬以外）：門頂靠近肩部的（九州
        # N700 的乘務員門），框上緣蓋到的是肩部往裡彎的車殼，從側面看也是牆。
        wall = [i for i in np.nonzero(car.node != name)[0]
                if (car.tri[i][:, 2] * side).min() > 0 and (car.tri[i][:, 2] * side).max() > 0.75 * car.half_width
                and car.tri[i][:, 0].max() > x0 and car.tri[i][:, 0].min() < x1
                and car.tri[i][:, 1].max() > y0 and car.tri[i][:, 1].min() < y1]
        door2 = [clip(car.tri[i][:, :2], box) for i in own]
        wall2 = [clip(car.tri[i][:, :2], box) for i in wall]
        door2 = [p for p in door2 if len(p)]
        wall2 = [p for p in wall2 if len(p)]
        both = overlap_sum(wall2, door2)
        covered = sum(poly_area(p) for p in door2 + wall2) - both - overlap_self(wall2) - overlap_self(door2)
        missing = max(0.0, poly_area(box) - covered)
        rows.append((name, len(own), missing * 1e6, both * 1e6))
    return rows


def overlap_sum(a, b):
    total = 0.0
    for p in a:
        for q in b:
            if (p.max(0) < q.min(0)).any() or (q.max(0) < p.min(0)).any():
                continue
            total += overlap(p, q)
    return total


def overlap_self(a):
    total = 0.0
    for k, p in enumerate(a):
        for q in a[k + 1:]:
            if (p.max(0) < q.min(0)).any() or (q.max(0) < p.min(0)).any():
                continue
            total += overlap(p, q)
    return total


def report_doors(entry):
    """`report.json` 一節車的門：（名字, 沿車範圍, 高度範圍, 斜上緣）。兩種寫法都讀。"""
    out = []
    for door in entry.get("doors", []):
        if "x" in door and "z" in door:
            out.append((door["name"], tuple(door["x"]), tuple(door["z"]), door.get("top") or []))
        elif "min" in door and "max" in door:
            out.append((door["name"], (door["min"][0], door["max"][0]), (door["min"][1], door["max"][1]), []))
    return out


def _height(top, along, upper):
    if not top:
        return upper
    if along <= top[0][0]:
        return top[0][1]
    for (ax, ay), (bx, by) in zip(top, top[1:]):
        if along <= bx:
            return ay + (by - ay) * (along - ax) / (bx - ax) if bx != ax else by
    return top[-1][1]


def door_boxes(car: Car, entry, margin):
    """照遊戲 `Door.contains` 的判法（三個頂點都在框裡、在同一側牆上），數框進去的面。"""
    rows = []
    for name, (x0, x1), (z0, z1), top in report_doors(entry):
        node = f"{car.name}-{name}" if f"{car.name}-{name}" in set(car.node) else name
        own = car.node == node
        side = float(np.sign(car.tri[own].reshape(-1, 3)[:, 2].mean())) if own.any() else (1.0 if "right" in name else -1.0)
        inside = np.ones(len(car.tri), bool)
        for k in range(3):
            p = car.tri[:, k]
            ok = (p[:, 2] * side > 0.5 * car.half_width) & (p[:, 0] >= x0 - margin) & (p[:, 0] <= x1 + margin) \
                & (p[:, 1] >= z0 - margin)
            ok &= np.array([y <= _height(top, x, z1) + margin for x, y in zip(p[:, 0], p[:, 1])])
            inside &= ok
        rows.append((name, int(own.sum()), int((inside & own).sum()), int((inside & ~own).sum())))
    return rows


# --- 5：全周幌轉角 ---------------------------------------------------------------

def coupling_ends(car: Car):
    """連結端：±半車長的兩端，有頭燈或尾燈的那端（車鼻）不算。回傳 (+1/-1)。"""
    lamps = [car.material(n) for n in ("headlamp", "taillamp") if car.material(n) is not None]
    lamp = np.isin(car.mat, lamps) if lamps else np.zeros(len(car.mat), bool)
    ends = []
    for sign in (1, -1):
        edge = car.hi[0] if sign > 0 else car.lo[0]
        near = np.abs(car.tri.mean(1)[:, 0] - edge) < 4.0
        if not (lamp & near).any():
            ends.append(sign)
    return ends


def end_piece(car: Car, sign):
    """`sign` 那一端放在原點、車身往 -x 伸（面對 +x 的另一節）。"""
    edge = car.hi[0] if sign > 0 else car.lo[0]
    tri = car.tri.copy()
    if sign < 0:
        tri = tri * np.array([-1, 1, -1])  # 轉 180°：沿車與橫向都反
        edge = -edge
    tri = tri - np.array([edge, 0, 0])
    return tri[tri[:, :, 0].max(1) > -END_ZONE]


def _turn(tri, angle):
    a = radians(angle)
    r = np.array([[cos(a), 0, -sin(a)], [0, 1, 0], [sin(a), 0, cos(a)]])
    return tri @ r.T


def _reach(tri, height, toward, zs):
    """切面 y = height 上，每個橫向 z，這節往 +x（toward=+1，取最大 x）或 -x 伸到哪。"""
    y = tri[:, :, 1] - height
    out = np.full(zs.shape, np.nan)
    points = []  # 每個三角形和切面最多兩個交點：(三角形序號, (x, z))
    for a, b in ((0, 1), (1, 2), (2, 0)):
        cross = (y[:, a] > 0) != (y[:, b] > 0)
        if not cross.any():
            continue
        t = (y[cross, a] / (y[cross, a] - y[cross, b]))[:, None]
        p = tri[cross, a] + (tri[cross, b] - tri[cross, a]) * t
        points.append((np.nonzero(cross)[0], p[:, [0, 2]]))
    if not points:
        return out
    idx = np.concatenate([i for i, _ in points])
    pts = np.concatenate([p for _, p in points])
    order = np.argsort(idx, kind="stable")
    idx, pts = idx[order], pts[order]
    pair = np.nonzero(idx[1:] == idx[:-1])[0]
    p0, p1 = pts[pair], pts[pair + 1]
    for (x0, z0), (x1, z1) in zip(p0, p1):
        if abs(z1 - z0) < 1e-12:
            continue
        lo, hi = (z0, z1) if z0 < z1 else (z1, z0)
        sel = (zs >= lo) & (zs <= hi)
        if not sel.any():
            continue
        x = x0 + (x1 - x0) * (zs[sel] - z0) / (z1 - z0)
        near = x * toward >= -END_ZONE  # 轉過的長側牆在車裡深處的那段不算
        sel = np.nonzero(sel)[0][near]
        x = x[near]
        cur = out[sel]
        out[sel] = np.where(np.isnan(cur), x, np.maximum(cur, x) if toward > 0 else np.minimum(cur, x))
    return out


def hoods(cars, max_yaw):
    """任兩個連結端面對面、各轉偏航的一半，每個切面的交疊面積（mm²）與最小間隙（mm）。"""
    ends = [(car, s) for car in cars for s in coupling_ends(car)]
    width = max(c.half_width for c in cars)
    zs = np.arange(-width - 0.05, width + 0.05, 0.002)
    angles = np.arange(-max_yaw, max_yaw + 1e-9, 0.5)
    rows = []
    seen = set()
    for a, (car_a, sa) in enumerate(ends):
        for car_b, sb in ends[a:]:
            key = (car_a.name, sa, car_b.name, sb)
            if key in seen:
                continue
            seen.add(key)
            front = end_piece(car_a, sa)                       # 往 +x 面對
            back = end_piece(car_b, sb) * np.array([-1, 1, -1])  # 轉過來往 -x 面對
            worst = (0.0, None, None)
            gap_at_max = np.inf
            for angle in angles:
                ta, tb = _turn(front, angle / 2), _turn(back, -angle / 2)
                for h in HEIGHTS:
                    ra = _reach(ta, h, +1, zs)
                    rb = _reach(tb, h, -1, zs)
                    both = ~np.isnan(ra) & ~np.isnan(rb)
                    if not both.any():
                        continue
                    room = rb[both] - ra[both]
                    area = float(np.clip(-room, 0, None).sum() * 0.002) * 1e6
                    if area > worst[0]:
                        worst = (area, float(angle), h)
                    if abs(abs(angle) - max_yaw) < 1e-9 and h >= 1.4:
                        gap_at_max = min(gap_at_max, float(room.min()) * 1000)
            label = f"{car_a.name}{'+' if sa > 0 else '-'} / {car_b.name}{'+' if sb > 0 else '-'}"
            rows.append((label, worst, gap_at_max))
    return rows


# --- 6：燈 -----------------------------------------------------------------------

def lamps(car: Car):
    rows = []
    for name in ("headlamp", "taillamp"):
        m = car.material(name)
        if m is None:
            rows.append((name, 0, 0, 0.0))
            continue
        sel = car.mat == m
        centre = car.tri[sel].mean(1)
        area = 0.5 * np.linalg.norm(np.cross(car.tri[sel][:, 1] - car.tri[sel][:, 0], car.tri[sel][:, 2] - car.tri[sel][:, 0]), axis=1)
        left, right = centre[:, 2] < 0, centre[:, 2] > 0
        mirror = 0.0
        if left.any() and right.any():
            cl = (centre[left] * area[left, None]).sum(0) / area[left].sum()
            cr = (centre[right] * area[right, None]).sum(0) / area[right].sum()
            mirror = float(np.linalg.norm(cl * np.array([1, 1, -1]) - cr))
        rows.append((name, int(left.sum()), int(right.sum()), mirror))
    return rows


# --- 7：車鼻和舊版 ---------------------------------------------------------------

def old_shell(path: Path, axes: str, scale):
    """舊版頭車，轉成輸出的軸並縮放；鼻尖（最大 x）放在 0。"""
    car = Car(path)
    tri = car.tri
    picks = []
    for token in axes.split(","):
        sign = -1.0 if token.startswith("-") else 1.0
        picks.append((sign, "xyz".index(token.strip("+-"))))
    out = np.stack([sign * tri[:, :, k] for sign, k in picks], -1) * np.array(scale)
    return out - np.array([out[:, :, 0].max(), 0, 0])


def _point_triangle(points, tri):
    """每個點到一組三角形的最短距離（Ericson, Real-Time Collision Detection §5.1.5）。"""
    best = np.full(len(points), np.inf)
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    ab, ac = b - a, c - a
    for start in range(0, len(points), 256):
        p = points[start:start + 256][:, None, :]
        ap = p - a
        d1, d2 = (ab * ap).sum(-1), (ac * ap).sum(-1)
        bp = p - b
        d3, d4 = (ab * bp).sum(-1), (ac * bp).sum(-1)
        cp = p - c
        d5, d6 = (ab * cp).sum(-1), (ac * cp).sum(-1)
        va = d3 * d6 - d5 * d4
        vb = d5 * d2 - d1 * d6
        vc = d1 * d4 - d3 * d2
        denom = np.where(np.abs(va + vb + vc) < 1e-30, 1e-30, va + vb + vc)
        v, w = vb / denom, vc / denom
        q = a + ab * v[..., None] + ac * w[..., None]
        # 落在三角形外的，退到三條邊上最近的點
        inside = (va >= 0) & (vb >= 0) & (vc >= 0)
        dist = np.where(inside, np.linalg.norm(p - q, axis=-1), np.inf)
        for s, e in ((a, b), (b, c), (c, a)):
            se = e - s
            t = np.clip(((p - s) * se).sum(-1) / np.maximum((se * se).sum(-1), 1e-30), 0, 1)
            dist = np.minimum(dist, np.linalg.norm(p - (s + se * t[..., None]), axis=-1))
        best[start:start + 256] = dist.min(1)
    return best


def nose(car: Car, old: np.ndarray, nose_from: float, above: float = NOSE_ABOVE):
    """新車鼻與舊版的距離，左右分開。只比離軌面 `above` 以上、門 node 與全寬直側牆以外的
    車殼（轉向架只平移不縮放、車鼻外露的連結器轉檔時拿掉、門與側牆的窗格是轉檔新切的，
    都不在比的範圍）。沿車方向的對齊用最小中位距離找
    （鼻尖可能被拿掉的連結器帶偏），報對齊量。"""
    new = car.tri - np.array([car.hi[0], 0, 0])
    cut = nose_from - car.hi[0]
    body = np.array(["-door-" not in name for name in car.node])  # 門是轉檔新切的，不和舊版比
    wall = 0.99 * car.half_width  # 全寬的直側牆不算車鼻（轉檔會在那裡切門、加窗格）
    new = new[body & (new[:, :, 0].max(1) > cut) & (new.mean(1)[:, 1] > above) & (np.abs(new[:, :, 2]).min(1) < wall)]
    old = old[(old[:, :, 0].max(1) > cut - 0.3) & (old.mean(1)[:, 1] > above - 0.05) & (np.abs(old[:, :, 2]).min(1) < wall)]
    sample = np.concatenate([new.reshape(-1, 3), new.mean(1)])
    sample = sample[sample[:, 0] > cut + 0.3][:: max(1, len(sample) // 300)]
    best = (np.inf, 0.0)
    for step, span in ((0.01, 0.6), (0.001, 0.012)):
        for dx in np.arange(best[1] - span, best[1] + span + 1e-12, step):
            d = np.median(_point_triangle(sample, old + np.array([dx, 0, 0])))
            if d < best[0]:
                best = (d, float(dx))
    # 橫向也對齊（5 mm 以內）：舊版車鼻可能整個偏離中線幾毫米（九州 N700 偏 2.23 mm），
    # 轉檔放回正中是改位置、不是改形狀。
    side = (np.inf, 0.0)
    for dz in np.arange(-0.005, 0.0050001, 0.0005):
        d = np.median(_point_triangle(sample, old + np.array([best[1], 0, dz])))
        if d < side[0]:
            side = (d, float(dz))
    old = old + np.array([best[1], 0, side[1]])
    rows = []
    for label, sign in (("左（-z）", -1), ("右（+z）", 1)):
        nn = new[(new.mean(1)[:, 2] * sign) > 0]
        oo = old[(old.mean(1)[:, 2] * sign) > 0]
        if not len(nn) or not len(oo):
            rows.append((label, None, None, (best[1], side[1])))
            continue
        pn = np.concatenate([nn.reshape(-1, 3), nn.mean(1)])
        pn = pn[(pn[:, 0] > cut) & (pn[:, 1] > above)]
        po = np.concatenate([oo.reshape(-1, 3), oo.mean(1)])
        po = po[(po[:, 0] > cut + 0.05) & (po[:, 1] > above)]
        to_old = _point_triangle(pn, old)
        to_new = _point_triangle(po, new)
        rows.append((label, (np.percentile(to_old, 95), to_old.max(), pn[np.argmax(to_old)]),
                     (np.percentile(to_new, 95), to_new.max(), po[np.argmax(to_new)]), (best[1], side[1])))
    return rows


# --- 8：軌距 ---------------------------------------------------------------------

def gauge(car: Car, gauge_m: float):
    pts = car.tri.reshape(-1, 3)
    low = pts[pts[:, 1] <= 0.05]
    rail = gauge_m / 2
    rows = []
    for sign in (-1, 1):
        s = low[low[:, 2] * sign > 0.3]
        if not len(s):
            rows.append((sign, None, None, False))
            continue
        z = np.abs(s[:, 2])
        rows.append((sign, float(z.min()), float(z.max()), bool(z.min() <= rail <= z.max())))
    return rows


# --- 主程式 ----------------------------------------------------------------------

def swift_cars(path: Path):
    """`Map3D…Mesh.swift` 裡的每一節（`"名字": \"\"\" … \"\"\"`）。"""
    import re
    text = path.read_text()
    palette = re.search(r"// Palette order: (.*)\.", text).group(1).split(", ")
    return [Car(None, swift=(m.group(1), m.group(2), palette))
            for m in re.finditer(r'"([^"]+)": """\n(.*?)"""', text, re.S)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("out_dir", type=Path, help="轉檔輸出的資料夾，或 `glb_to_swift.py` 寫的 Map3D…Mesh.swift")
    parser.add_argument("--old", type=Path, help="舊版頭車原檔（查車鼻）")
    parser.add_argument("--old-axes", default="-z,y,x", help="舊檔的哪一軸變成輸出的 沿車,上,橫向（預設 -z,y,x）")
    parser.add_argument("--nose-scale", default=None, help="車鼻的倍率：沿車,高,寬")
    parser.add_argument("--nose-from", type=float, default=None, help="車鼻從輸出座標 x 多少起（m）")
    parser.add_argument("--cab", default=None, help="哪個 GLB 是頭車（預設：有頭燈的那個）")
    parser.add_argument("--max-yaw", type=float, default=4.0)
    parser.add_argument("--gauge", type=float, default=1.435)
    parser.add_argument("--skip", default="", help="不查的項目，逗號分開（例：near,hoods）")
    parser.add_argument("--same", default="door=white", help="當同色的格位，逗號分開（預設 door=white）")
    parser.add_argument("--md", type=Path, help="把結果另寫成 Markdown")
    args = parser.parse_args(argv)
    skip = set(filter(None, args.skip.split(",")))

    if args.out_dir.suffix == ".swift":
        cars = swift_cars(args.out_dir)
        skip.add("doors")  # Swift 網格沒有 node：門另外由遊戲的 testEachDoorIsAPieceOfItsOwn 查
    else:
        paths = sorted(args.out_dir.glob("*.glb"))
        if not paths:
            raise SystemExit(f"{args.out_dir}: 沒有 GLB")
        cars = [Car(p) for p in paths]
    same = [tuple(pair.split("=")) for pair in filter(None, args.same.split(","))]
    for car in cars:
        car.same_colour(same)
    report = {}
    if args.out_dir.is_dir() and (args.out_dir / "report.json").exists():
        report = json.loads((args.out_dir / "report.json").read_text())
    lines, failed = [], []

    def say(text=""):
        lines.append(text)
        print(text)

    def verdict(item, ok, detail):
        mark = "過" if ok else "**不過**"
        say(f"| {item} | {mark} | {detail} |")
        if not ok:
            failed.append(item)

    head = None
    for car in cars:
        m = car.material("headlamp")
        if (args.cab and args.cab in car.name) or (not args.cab and m is not None and (car.mat == m).any()):
            head = head or car

    say(f"# 舊版轉換自動檢查：{args.out_dir.name}")
    say()
    say("| 項目 | 結果 | 數字 |")
    say("| --- | --- | --- |")
    for car in cars:
        entry = report.get(car.name, {})
        if entry.get("triangles") is not None:
            verdict(f"{car.name} 面數對 report.json", entry["triangles"] == len(car.tri),
                    f"GLB {len(car.tri)}、report {entry['triangles']}")
        pairs, degenerate = coplanar(car)
        verdict(f"{car.name} 異色共面重疊", not pairs,
                f"{len(pairs)} 對" + (f"；最大 {pairs[0][0]:.1f} mm²：{car.where(pairs[0][1])} ／ {car.where(pairs[0][2])}" if pairs else ""))
        if "near" not in skip:
            near = near_coplanar(car)
            verdict(f"{car.name} 異色近共面（2°、5 cm）", not near,
                    f"{len(near)} 對" + (f"；最大 {near[0][0]:.1f} mm²：{car.where(near[0][1])} ／ {car.where(near[0][2])}" if near else ""))
        verdict(f"{car.name} 毫米格點退化面", not degenerate,
                f"{len(degenerate)} 面" + (f"；{car.where(degenerate[0])}" if degenerate else ""))
        flipped = inward(car)
        verdict(f"{car.name} 側牆與車頂朝內的面", not flipped,
                f"{len(flipped)} 面" + (f"；{car.where(flipped[0])}" if flipped else ""))
        doors = door_nodes(car)
        expected = len(report_doors(entry))
        if "doors" not in skip:
            verdict(f"{car.name} 每扇門一個 node", bool(doors) and (not expected or len(doors) == expected),
                    f"{len(doors)} 個門 node" + (f"、report 寫 {expected} 扇" if expected else ""))
            for name, faces, missing, both in door_pieces(car):
                verdict(f"{name} 拿掉後牆面完整", missing <= AREA_MM2 and both <= AREA_MM2,
                        f"{faces} 面；缺口 {missing:.1f} mm²、牆和門重疊 {both:.1f} mm²")
            for margin in (0.0005, 0.002):
                for name, faces, got, wall in door_boxes(car, entry, margin):
                    ok = got == faces and wall == 0
                    if margin > 0.001:
                        tag = f"{car.name} {name} 框（容差 2 mm，只提醒）"
                        say(f"| {tag} | {'過' if ok else '提醒'} | 門 {got}/{faces} 面、框進牆 {wall} 面"
                            + ("" if ok else "：遊戲 `Door.contains` 的預設容差要用 0.5 mm") + " |")
                    else:
                        verdict(f"{car.name} {name} 框（容差 0.5 mm）", ok, f"門 {got}/{faces} 面、框進牆 {wall} 面")
        lamp_rows = lamps(car)
        lit = sum(l + r for _, l, r, _ in lamp_rows)
        if car is head:
            for name, left, right, mirror in lamp_rows:
                verdict(f"{car.name} {name} 左右", left > 0 and left == right and mirror <= LAMP_MIRROR,
                        f"左 {left}、右 {right} 面；左右對稱差 {mirror * 1000:.1f} mm")
        else:
            verdict(f"{car.name} 沒有燈面", lit == 0, f"{lit} 面")
        for sign, lo, hi, ok in gauge(car, args.gauge):
            where = "右（+z）" if sign > 0 else "左（-z）"
            verdict(f"{car.name} 軌距 {args.gauge} m 踏面{where}", ok,
                    "沒有輪子" if lo is None else f"踏面 {lo:.3f}–{hi:.3f} m，鋼軌 {args.gauge / 2:.4f} m")

    if "hoods" not in skip:
        for label, (area, angle, height), gap in hoods(cars, args.max_yaw):
            detail = f"最大交疊 {area:.1f} mm²" + (f"（偏航 {angle:+.1f}°、離軌面 {height} m）" if angle is not None else "")
            detail += f"；{args.max_yaw:g}° 時最小間隙 {gap:.1f} mm" if np.isfinite(gap) else ""
            verdict(f"全周幌 {label} 偏航 0–{args.max_yaw:g}°", area <= AREA_MM2, detail)

    if args.old:
        if head is None or not args.nose_scale or args.nose_from is None:
            raise SystemExit("--old 要和 --nose-scale、--nose-from 一起給，而且要有頭車")
        scale = [float(v) for v in args.nose_scale.split(",")]
        old = old_shell(args.old, args.old_axes, scale)
        for label, to_old, to_new, shift in nose(head, old, args.nose_from):
            if to_old is None:
                verdict(f"車鼻{label}和舊版", False, "這一側沒有面")
                continue
            ok = to_old[0] <= NOSE_P95 and to_old[1] <= NOSE_MAX and to_new[0] <= NOSE_P95
            worst = to_old[2] + np.array([head.hi[0], 0, 0])
            verdict(f"車鼻{label}和舊版", ok,
                    f"新→舊 p95 {to_old[0] * 1000:.2f}／最大 {to_old[1] * 1000:.2f} mm（{worst[0]:.3f}, {worst[1]:.3f}, {worst[2]:.3f}）；"
                    f"舊→新 p95 {to_new[0] * 1000:.2f}／最大 {to_new[1] * 1000:.2f} mm；沿車對齊 {shift[0] * 1000:+.0f} mm、橫向 {shift[1] * 1000:+.1f} mm")

    say()
    say("全部通過" if not failed else f"不過 {len(failed)} 項：" + "、".join(failed))
    if args.md:
        args.md.write_text("\n".join(lines) + "\n")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
