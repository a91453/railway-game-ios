#!/usr/bin/env python3
"""Decision 888's preview: diamond crossings in the 3D map, drawn flat
from the scene's own meshes.

The meshes come from the Linux test (the game's own geometry and colours):

    DIAMOND_PREVIEW=/tmp/diamond.json swift test --skip-build \
        --filter Map3DDiamondCrossingsTests/testWriteThePreviewsMeshes
    python3 -I tools/diamond-crossing/preview.py /tmp/diamond.json overview.jpg

One row for each crossing the test lays (90°, 45° and 1 in 4): from above
at the game's camera angle, close up over the node, and straight down. The rasteriser is
decision 860's (`tools/underground-station/preview.py`): flat colours, no
Metal (no sun shadow, fog, bloom or the ballast's painted sleepers).
Needs Pillow and NumPy.
"""
import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

_spec = importlib.util.spec_from_file_location(
    "underground_preview", os.path.join(os.path.dirname(__file__), "..", "underground-station", "preview.py"))
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)
render = _module.render

CAPTIONS = {"90": "90°", "45": "45°", "15": "1 in 4 (14.5°)"}


def main():
    source, out = sys.argv[1], sys.argv[2]
    scenes = json.load(open(source))
    tile = (560, 400)
    rows = []
    for scene in scenes:
        rails = scene["rails"]
        name = CAPTIONS.get(scene["name"], scene["name"])
        rows.append([
            (render(scene, (-14, rails + 16, 18), (0, rails, 0), tile, fov=45), f"{name}: from the game's camera"),
            (render(scene, (-3.5, rails + 4.5, 4.5), (0, rails, 0), tile, fov=60), f"{name}: close over the node"),
            (render(scene, (0, rails + 30, 0.01), (0, rails, 0), tile, fov=50), f"{name}: straight down"),
        ])
    sheet = Image.new("RGB", (tile[0] * 3, (tile[1] + 30) * len(rows)), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for r, row in enumerate(rows):
        for c, (image, caption) in enumerate(row):
            x, y = c * tile[0], r * (tile[1] + 30)
            draw.text((x + 10, y + 8), caption, fill=(40, 40, 40))
            sheet.paste(image, (x, y + 30))
    sheet.save(out, quality=85)


if __name__ == "__main__":
    main()
