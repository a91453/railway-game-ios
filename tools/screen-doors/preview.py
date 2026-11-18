#!/usr/bin/env python3
"""Decision 847's preview: the platform screen doors' meshes drawn flat.

The meshes come from the Linux test (the game's own geometry, not a copy):

    SCREEN_DOORS_PREVIEW=/tmp/doors.json swift test --skip-build \
        --filter Map3DScreenDoorsTests/testWriteThePreviewsMeshes
    python3 -I tools/screen-doors/preview.py /tmp/doors.json overview.jpg

Each platform twice, by day and after dark (what is not lit is dimmed to a
quarter, as the map's night does; the lit glass keeps its colour), from
above at the 3D map's usual 40 degrees and from the platform's end. A
depth-buffered rasteriser with flat colours: it is not Metal (no sun shadow, fog
or bloom). Needs Pillow and NumPy.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

LABELS = {
    "full": "full-height 2.5 m (Taipei Xinyi section, Wenhu, MTR underground)",
    "taipei-gate": "gate 1.45 m (Taipei older stations)",
    "mtr-gate": "gate 1.55 m (MTR urban lines above ground)",
}


def colour(value):
    return np.array([value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF], dtype=float)


def render(scene, eye, target, size, night, fov=32.0):
    w, h = size
    positions = np.array(scene["positions"], dtype=float).reshape(-1, 3)
    colours = np.array([colour(c) for c in scene["colours"]])
    lit = np.array(scene["lit"], dtype=bool)
    indices = np.array(scene["indices"], dtype=int).reshape(-1, 3)
    eye, target = np.array(eye, float), np.array(target, float)
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    rel = positions - eye
    cam = np.stack([rel @ right, rel @ up, rel @ forward], axis=1)
    focal = (h / 2) / math.tan(math.radians(fov) / 2)
    depth = np.maximum(cam[:, 2], 0.1)
    screen = np.stack([w / 2 + cam[:, 0] * focal / depth, h / 2 - cam[:, 1] * focal / depth], axis=1)
    sky = np.array((24, 30, 46) if night else (214, 226, 236), dtype=float)
    pixels = np.tile(sky, (h, w, 1))
    zbuffer = np.full((h, w), np.inf)
    sun = np.array([0.35, 0.85, 0.4])
    sun /= np.linalg.norm(sun)
    for a, b, c in indices:
        if min(cam[a, 2], cam[b, 2], cam[c, 2]) < 0.2:
            continue
        normal = np.cross(positions[b] - positions[a], positions[c] - positions[a])
        length = np.linalg.norm(normal)
        light = 0.78 + 0.22 * abs(float(normal @ sun) / length) if length > 0 else 1.0
        base = colours[a] * ((1.05 if lit[a] else 0.25) if night else light)
        (x0, y0), (x1, y1), (x2, y2) = screen[a], screen[b], screen[c]
        left, right_ = max(int(min(x0, x1, x2)), 0), min(int(max(x0, x1, x2)) + 1, w)
        bottom, top = max(int(min(y0, y1, y2)), 0), min(int(max(y0, y1, y2)) + 1, h)
        if left >= right_ or bottom >= top:
            continue
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        xs, ys = np.meshgrid(np.arange(left, right_) + 0.5, np.arange(bottom, top) + 0.5)
        w0 = ((x1 - xs) * (y2 - ys) - (x2 - xs) * (y1 - ys)) / area
        w1 = ((x2 - xs) * (y0 - ys) - (x0 - xs) * (y2 - ys)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        z = w0 * depth[a] + w1 * depth[b] + w2 * depth[c]
        window = zbuffer[bottom:top, left:right_]
        nearer = inside & (z < window)
        window[nearer] = z[nearer]
        pixels[bottom:top, left:right_][nearer] = np.minimum(base, 255)
    image = Image.fromarray(pixels.astype(np.uint8))
    return image


def main():
    source, out = sys.argv[1], sys.argv[2]
    scenes = json.load(open(source))["scenes"]
    tile = (720, 420)
    sheet = Image.new("RGB", (tile[0] * 3, tile[1] * len(scenes) + 40 * len(scenes)), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for row, scene in enumerate(scenes):
        middle = scene["length"] / 2
        y = row * (tile[1] + 40)
        draw.text((10, y + 12), LABELS.get(scene["name"], scene["name"]), fill=(30, 30, 30))
        views = [
            # The map's camera, 40 degrees down, across the platform.
            (render(scene, (middle - 20, 30, 38), (middle - 20, 0, 1), tile, False), "day, map camera"),
            (render(scene, (middle - 20, 30, 38), (middle - 20, 0, 1), tile, True), "night: only the glass lit"),
            # Standing on the platform, looking along it.
            (render(scene, (middle - 22, 2.9, 4.6), (middle + 10, 1.4, 1.2), tile, False), "on the platform"),
        ]
        for column, (image, caption) in enumerate(views):
            sheet.paste(image, (column * tile[0], y + 40))
            draw.text((column * tile[0] + 10, y + 28), caption, fill=(80, 80, 80))
    sheet.save(out, quality=85)


if __name__ == "__main__":
    main()
