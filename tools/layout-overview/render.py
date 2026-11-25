#!/usr/bin/env python3
"""Draw the meshes `LayoutOverviewDumpTests` writes, with a depth buffer.

    LAYOUT_OVERVIEW_DIR=/tmp/layouts swift test --skip-build --filter LayoutOverviewDumpTests
    python3 -I tools/layout-overview/render.py OUT.jpg COLUMNS NAME@YAW[,PITCH] ...

e.g. the school and the hospital from three sides each:

    python3 -I tools/layout-overview/render.py docs/art/x/overview.jpg 3 \\
        /tmp/layouts/school-0@200 /tmp/layouts/school-0@20 /tmp/layouts/school-0@110 ...

Each cell is an orthographic view from YAW degrees round the up axis and
PITCH (default 40) above the horizon, each triangle flat in its colour,
lit from one side. A layout with a pad stands on it as the game draws it
(`Map3DScene.Builder.placedPadHeight`). Nearer surfaces hide farther ones
pixel by pixel (a depth buffer, as the game's Metal view), not by sorting
whole triangles: sorting draws a big flat triangle (a pitch, a roof) over
or under its neighbours by its middle's depth and shows diagonal wedges
that are not in the model (2026-11-25, the school's pitch and the
hospital's and Hong Kong stations' roofs). It is a sketch, not the game's
light, shadow or textures. Needs numpy and Pillow.
"""
import math
import struct
import sys

import numpy as np
from PIL import Image

PAD_HEIGHT = 0.1
BACKGROUND = (236, 238, 246)


def load(path):
    data = open(path, "rb").read()
    nv, ni = struct.unpack_from("<II", data, 0)
    vertex = np.dtype([("p", "<f4", 3), ("n", "<f4", 3), ("c", "<u4"), ("l", "<f4")])
    v = np.frombuffer(data, dtype=vertex, count=nv, offset=8)
    idx = np.frombuffer(data, dtype="<u4", count=ni, offset=8 + nv * 32).reshape(-1, 3)
    pad, side = struct.unpack_from("<If", data, 8 + nv * 32 + ni * 4)
    points = v["p"].astype(np.float64)
    colours = v["c"][idx[:, 0]]
    if pad:
        points = points + [0, PAD_HEIGHT, 0]
        h, s = PAD_HEIGHT, side / 2
        box = np.array([[x, y, z] for y in (0, h) for x in (-s, s) for z in (-s, s)])
        faces = [(4, 5, 7), (4, 7, 6), (0, 1, 5), (0, 5, 4), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 3, 7), (1, 7, 5)]
        idx = np.vstack([idx, np.array(faces) + len(points)])
        points = np.vstack([points, box])
        colours = np.concatenate([colours, np.full(len(faces), pad, dtype=np.uint32)])
    return points, idx, colours


def render(path, yaw, pitch=40.0, size=600, supersample=2, margin=0.05):
    points, idx, colours = load(path)
    rgb = np.stack([(colours >> 0) & 255, (colours >> 8) & 255, (colours >> 16) & 255], 1).astype(np.float64)
    yaw, pitch = math.radians(yaw), math.radians(pitch)
    toward = np.array([math.cos(pitch) * math.cos(yaw), math.sin(pitch), math.cos(pitch) * math.sin(yaw)])
    right = np.cross([0.0, 1.0, 0.0], toward)
    right /= np.linalg.norm(right)
    up = np.cross(toward, right)
    sx, sy, depth = points @ right, points @ up, points @ toward
    w = size * supersample
    span = max(np.ptp(sx), np.ptp(sy)) * (1 + 2 * margin)
    x = (sx - (sx.min() + sx.max()) / 2) * w / span + w / 2
    y = w / 2 - (sy - (sy.min() + sy.max()) / 2) * w / span
    zbuffer = np.full((w, w), -np.inf)
    image = np.empty((w, w, 3))
    image[:] = BACKGROUND
    light = np.array([0.45, 0.8, 0.35]) / np.linalg.norm([0.45, 0.8, 0.35])
    for t, (a, b, c) in enumerate(idx):
        area = (x[b] - x[a]) * (y[c] - y[a]) - (x[c] - x[a]) * (y[b] - y[a])
        if abs(area) < 1e-9:
            continue
        normal = np.cross(points[b] - points[a], points[c] - points[a])
        normal /= np.linalg.norm(normal)
        if normal @ toward < 0:
            normal = -normal  # the game draws both sides
        colour = rgb[t] * (0.55 + 0.45 * max(0.0, normal @ light))
        x0, x1 = int(max(0, math.floor(min(x[a], x[b], x[c])))), int(min(w - 1, math.ceil(max(x[a], x[b], x[c]))))
        y0, y1 = int(max(0, math.floor(min(y[a], y[b], y[c])))), int(min(w - 1, math.ceil(max(y[a], y[b], y[c]))))
        if x0 > x1 or y0 > y1:
            continue
        px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        wa = ((x[b] - px) * (y[c] - py) - (x[c] - px) * (y[b] - py)) / area
        wb = ((x[c] - px) * (y[a] - py) - (x[a] - px) * (y[c] - py)) / area
        wc = 1 - wa - wb
        inside = (wa >= 0) & (wb >= 0) & (wc >= 0)
        z = wa * depth[a] + wb * depth[b] + wc * depth[c]
        window = zbuffer[y0:y1 + 1, x0:x1 + 1]
        nearer = inside & (z > window)
        window[nearer] = z[nearer]
        image[y0:y1 + 1, x0:x1 + 1][nearer] = colour
    picture = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8))
    return picture.resize((size, size), Image.LANCZOS)


def main(out, columns, *cells):
    columns = int(columns)
    tiles = []
    for cell in cells:
        path, view = cell.rsplit("@", 1)
        angles = [float(v) for v in view.split(",")]
        tiles.append(render(path if path.endswith(".bin") else path + ".bin", *angles))
    size = tiles[0].width
    rows = (len(tiles) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * size, rows * size), BACKGROUND)
    for n, tile in enumerate(tiles):
        sheet.paste(tile, (n % columns * size, n // columns * size))
    sheet.save(out, quality=85) if out.endswith(".jpg") else sheet.save(out)


if __name__ == "__main__":
    main(*sys.argv[1:])
