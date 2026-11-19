#!/usr/bin/env python3
"""Decision 882's preview: the platform name boards on decision 874's three
stations (an island and a side platform on the ground, a side platform on
a viaduct), seen from beside the track and from along the platform,
drawn flat from the scene's own meshes.

    PLATFORM_FURNITURE_PREVIEW=/tmp/furniture.json swift test --skip-build \
        --filter Map3DPlatformPropsTests/testWriteTheFurniturePreviewsMeshes
    python3 -I tools/platform-name-board/preview.py /tmp/furniture.json overview.jpg

Decision 860's rasteriser (`tools/underground-station/preview.py`): flat
colours, not Metal. Needs Pillow and NumPy.
"""
import importlib.util
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, "..", *path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


underground = load("underground_preview", ("underground-station", "preview.py"))
furniture = load("furniture_preview", ("platform-furniture", "preview.py"))
INK = 0x5C3826  # the palette navy as the meshes store it (its bytes the other way)


def board_near(scene, centre, island):
    """The middle of the name board nearest `centre`: its ink's x, z and
    height (an island's on its middle line, a side platform's more than
    4 m from its track, never a stop board's figures by the edge)."""
    positions = np.array(scene["positions"], dtype=float).reshape(-1, 3)
    colours = np.array(scene["colours"])
    off = abs(positions[:, 2] - centre[2])
    ink = positions[(colours == INK) & (abs(positions[:, 0] - centre[0]) < 120) & ((off < 0.5) if island else (off > 4) & (off < 12))
                    & (positions[:, 1] > centre[1] + 2)]
    if island:
        # The half whose face looks to +z: its ink the furthest that way.
        ink = ink[ink[:, 2] > ink[:, 2].mean()]
    best = ink[np.argmin(abs(ink[:, 0] - centre[0]))]
    same = ink[abs(ink[:, 0] - best[0]) < 3]
    return same[:, 0].mean(), same[:, 2].mean(), same[:, 1].mean()


def main():
    source, out = sys.argv[1], sys.argv[2]
    scene = json.load(open(source))
    tile = (900, 520)
    views = []
    for name, caption in [("island", "高雄 island on the ground"), ("side", "板橋 side platform on the ground"),
                          ("raised", "松山機場 side platform on a viaduct")]:
        x, y, z = scene[name]
        part = furniture.near(scene, (x, y, z))
        bx, bz, by = board_near(scene, (x, y, z), name == "island")
        # From the track's side: the board's face towards the track.
        # An island's ink stands out from its middle towards that half's
        # track; a side platform's board faces back to its track.
        toward = 1 if name == "island" else np.sign(z - bz)
        views.append((underground.render(part, (bx - 4, by + 0.2, bz + toward * 9), (bx, by - 0.3, bz), tile, fov=50),
                      caption + ": from the train"))
        views.append((underground.render(part, (bx - 22, by + 0.6, bz + toward * 2.6), (bx, by - 0.4, bz), tile, fov=55),
                      caption + ": along the platform"))
    sheet = Image.new("RGB", (tile[0] * 2, (tile[1] + 30) * 3), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (image, caption) in enumerate(views):
        x, y = (index % 2) * tile[0], (index // 2) * (tile[1] + 30)
        draw.text((x + 10, y + 8), caption.encode("ascii", "ignore").decode().strip(), fill=(40, 40, 40))
        sheet.paste(image, (x, y + 30))
    sheet.save(out, quality=85)


if __name__ == "__main__":
    main()
