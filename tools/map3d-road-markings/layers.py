"""Decision 355: the road markings' two layers of Map3DSurfaces.png.

Draws `crosswalk` and `laneArrows` (Map3DSurface 22 and 23) and writes them
in at their place, replacing them when they are already there; the other
layers stay as they are. Each layer is 256 x 256, its colour on the left
and its tint mask on the right (white tints with the vertex's colour, the
road's; black keeps the paint's own white).

    python3 -I tools/map3d-road-markings/layers.py RailwayGameApp/Resources/Map3D/Map3DSurfaces.png

Shapes after this repository's 3D city view (MIT, decision 152):
`Web/CityView/tools/pipeline/markings.mjs` (zebra bars 0.45 m at a 0.9 m
pitch; decision 447 lays a repeat on 0.8 m, bars 0.4 m and 0.4 m apart) and `Web/CityView/src/world/props.js` `decalTexture` (arrows on a
1.7 x 5 m cell, the far end up). Needs Pillow and NumPy.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

SIDE = 256
FIRST = 22  # Map3DSurface.crosswalk's raw value
PAINT = (238, 238, 232)
ASPHALT = 128  # mid grey: tints to the road's own colour


def worn(mask, seed):
    """Paint a little uneven, a few specks worn through."""
    rng = np.random.default_rng(seed)
    shade = rng.normal(0, 3, (SIDE, SIDE))
    specks = rng.random((SIDE, SIDE)) < 0.006
    paint = mask & ~specks
    colour = np.empty((SIDE, SIDE, 3))
    for channel in range(3):
        colour[..., channel] = np.where(paint, PAINT[channel] + shade, ASPHALT + shade * 0.5)
    tint = np.where(paint, 0, 255)
    return np.clip(colour, 0, 255).astype(np.uint8), np.repeat(tint[..., None], 3, axis=2).astype(np.uint8)


def crosswalk():
    # u across the road, one repeat a bar and its gap (0.8 m, decision 447);
    # v along it.
    u = (np.arange(SIDE) + 0.5) / SIDE
    bar = (u >= 0.25) & (u < 0.75)
    return worn(np.tile(bar, (SIDE, 1)), 355)


def arrows():
    # Two cells of 1.7 x 5 m side by side, the far end (the way traffic
    # goes) at the top: a through arrow, and a through-and-left one (on
    # the left as the driver sees it). Drawn four times over, then shrunk.
    scale = 4
    image = Image.new("L", (SIDE * scale, SIDE * scale), 0)
    draw = ImageDraw.Draw(image)
    cell_w, cell_h = SIDE * scale / 2, SIDE * scale

    def at(cell, x, y):
        return (cell * cell_w + x / 1.7 * cell_w, y / 5 * cell_h)

    def shaft(cell, x, top, bottom, width=0.17):
        draw.polygon([at(cell, x - width / 2, top), at(cell, x + width / 2, top), at(cell, x + width / 2, bottom),
                      at(cell, x - width / 2, bottom)], fill=255)

    def head(cell, tip, way, length, half):
        (tx, ty), (dx, dy) = tip, way
        draw.polygon([at(cell, tx, ty), at(cell, tx - dx * length - dy * half, ty - dy * length + dx * half),
                      at(cell, tx - dx * length + dy * half, ty - dy * length - dx * half)], fill=255)

    # Through.
    shaft(0, 0.85, 1.7, 4.9)
    head(0, (0.85, 0.1), (0, -1), 1.7, 0.33)
    # Through and left: the shaft right of the middle, a branch bending left.
    x = 1.15
    shaft(1, x, 1.7, 4.9)
    head(1, (x, 0.1), (0, -1), 1.7, 0.33)
    # The branch leaves the shaft at 3.6 m and runs up and to the left to
    # its head.
    ax, ay, bx, by = x, 3.6, x - 0.45, 3.1
    length = np.hypot(bx - ax, by - ay)
    nx, ny = -(by - ay) / length * 0.085, (bx - ax) / length * 0.085
    draw.polygon([at(1, ax + nx, ay + ny), at(1, bx + nx, by + ny), at(1, bx - nx, by - ny), at(1, ax - nx, ay - ny)], fill=255)
    head(1, (x - 0.95, 2.55), (-0.7, -0.71), 0.75, 0.28)
    mask = np.array(image.resize((SIDE, SIDE), Image.LANCZOS)) > 127
    return worn(mask, 356)


def main(path):
    sheet = np.array(Image.open(path).convert("RGB"))
    layers = [crosswalk(), arrows()]
    rows = (FIRST + len(layers)) * SIDE
    if sheet.shape[0] < rows:
        sheet = np.concatenate([sheet, np.zeros((rows - sheet.shape[0], 2 * SIDE, 3), np.uint8)])
    for index, (colour, mask) in enumerate(layers):
        top = (FIRST + index) * SIDE
        sheet[top:top + SIDE, :SIDE] = colour
        sheet[top:top + SIDE, SIDE:] = mask
    Image.fromarray(sheet, "RGB").save(path, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
