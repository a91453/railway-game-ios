#!/usr/bin/env python3
"""Decision 860's preview: an underground station's box, platforms and the
old version's island module, drawn flat from the scene's own meshes.

The meshes come from the Linux test (the game's own geometry and colours,
the look's fading included):

    UNDERGROUND_PREVIEW=/tmp/underground.json swift test --skip-build \
        --filter UndergroundStationsTests/testWriteThePreviewsMeshes
    python3 -I tools/underground-station/preview.py /tmp/underground.json overview.jpg

Four views: the box cut open from above (what is over its ceiling left
out), standing on the island looking along it, from the cab coming in
along the track, and the head wall with the bores' openings. A
depth-buffered rasteriser with flat colours (the screen doors' preview's,
decision 847): it is not Metal (no sun shadow, fog or bloom); the lamps
are drawn at full colour as they glow. Needs Pillow and NumPy.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw


def colour(value):
    return np.array([value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF], dtype=float)


def subdivide(positions, colours, lit, indices, longest=3.0):
    """Long faces split until no edge is longer than `longest` metres, so a
    face reaching behind the eye (which this rasteriser drops, having no
    near-plane clipping) leaves only its pieces there."""
    positions, colours, lit = list(positions), list(colours), list(lit)
    out, work = [], [tuple(t) for t in indices]
    while work:
        a, b, c = work.pop()
        pa, pb, pc = (np.array(positions[i]) for i in (a, b, c))
        edges = [np.linalg.norm(pa - pb), np.linalg.norm(pb - pc), np.linalg.norm(pc - pa)]
        if max(edges) <= longest:
            out.append((a, b, c))
            continue
        # Split the longest edge at its middle.
        k = int(np.argmax(edges))
        i, j, other = [(a, b, c), (b, c, a), (c, a, b)][k]
        positions.append((np.array(positions[i]) + np.array(positions[j])) / 2)
        colours.append(colours[i])
        lit.append(lit[i])
        m = len(positions) - 1
        work += [(i, m, other), (m, j, other)]
    return np.array(positions), np.array(colours), np.array(lit), np.array(out)


def render(scene, eye, target, size, fov=50.0, cut=None):
    w, h = size
    positions = np.array(scene["positions"], dtype=float).reshape(-1, 3)
    colours = np.array([colour(c) for c in scene["colours"]])
    lit = np.array(scene["lit"], dtype=bool)
    indices = np.array(scene["indices"], dtype=int).reshape(-1, 3)
    if cut is not None:
        indices = indices[positions[indices][:, :, 1].max(axis=1) <= cut]
    positions, colours, lit, indices = subdivide(positions, colours, lit, indices)
    eye, target = np.array(eye, float), np.array(target, float)
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0, 1, 0])
    if np.linalg.norm(right) < 1e-6:
        right = np.array([1.0, 0, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    rel = positions - eye
    cam = np.stack([rel @ right, rel @ up, rel @ forward], axis=1)
    focal = (h / 2) / math.tan(math.radians(fov) / 2)
    depth = np.maximum(cam[:, 2], 0.1)
    screen = np.stack([w / 2 + cam[:, 0] * focal / depth, h / 2 - cam[:, 1] * focal / depth], axis=1)
    pixels = np.tile(np.array((20, 22, 30), dtype=float), (h, w, 1))
    zbuffer = np.full((h, w), np.inf)
    sun = np.array([0.35, 0.85, 0.4])
    sun /= np.linalg.norm(sun)
    for a, b, c in indices:
        if min(cam[a, 2], cam[b, 2], cam[c, 2]) < 0.2:
            continue
        normal = np.cross(positions[b] - positions[a], positions[c] - positions[a])
        length = np.linalg.norm(normal)
        light = 0.78 + 0.22 * abs(float(normal @ sun) / length) if length > 0 else 1.0
        base = colours[a] * (1.0 if lit[a] else light)
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
    return Image.fromarray(pixels.astype(np.uint8))


def main():
    source, out = sys.argv[1], sys.argv[2]
    scene = json.load(open(source))
    # The station's frame: its path's start and end at the rails, the
    # island's middle across it (the scene's x along, z across).
    start, end, rails, island = scene["start"], scene["end"], scene["rails"], scene["island"]
    sx, ex = start, end
    mid = (sx + ex) / 2
    tile = (900, 520)
    views = [
        (render(scene, (mid - 60, rails + 70, island + 55), (mid, rails, island), tile, fov=45, cut=rails + 5.9),
         "cut open from above (ceiling and ground left out)"),
        (render(scene, (sx + 20, rails + 1.15 + 1.6, island), (sx + 80, rails + 1.15 + 1.2, island), tile, fov=70),
         "standing on the island, looking along it"),
        (render(scene, (sx - 30, rails + 2.6, island - 5), (sx + 40, rails + 2.2, island - 5), tile, fov=60),
         "from the cab, coming in along the track"),
        (render(scene, (sx + 60, rails + 2.6, island), (sx - 10, rails + 2.0, island), tile, fov=70),
         "the head wall and the bores' openings"),
    ]
    sheet = Image.new("RGB", (tile[0] * 2, (tile[1] + 30) * 2), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (image, caption) in enumerate(views):
        x, y = (index % 2) * tile[0], (index // 2) * (tile[1] + 30)
        draw.text((x + 10, y + 8), caption, fill=(40, 40, 40))
        sheet.paste(image, (x, y + 30))
    sheet.save(out, quality=85)


if __name__ == "__main__":
    main()
