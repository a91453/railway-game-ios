#!/usr/bin/env python3
"""Decision 874's preview: the old version's platform furniture on an
island and a side platform on the ground and a side platform on a viaduct,
drawn flat from the scene's own meshes.

    PLATFORM_FURNITURE_PREVIEW=/tmp/furniture.json swift test --skip-build \
        --filter Map3DPlatformPropsTests/testWriteTheFurniturePreviewsMeshes
    python3 -I tools/platform-furniture/preview.py /tmp/furniture.json overview.jpg

The rasteriser is decision 860's (`tools/underground-station/preview.py`):
flat colours, not Metal (no sun shadow, fog or bloom). Needs Pillow and
NumPy.
"""
import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("underground_preview", os.path.join(HERE, "..", "underground-station", "preview.py"))
underground = importlib.util.module_from_spec(spec)
spec.loader.exec_module(underground)


def near(scene, centre, reach=150.0, low=-3.0, high=22.0):
    """The scene's faces within `reach` metres of `centre` along and 45 m
    across, so the rasteriser has only one station to draw."""
    import numpy as np
    positions = np.array(scene["positions"], dtype=float).reshape(-1, 3)
    indices = np.array(scene["indices"], dtype=int).reshape(-1, 3)
    corners = positions[indices]
    keep = ((abs(corners[:, :, 0] - centre[0]) < reach).all(axis=1) & (abs(corners[:, :, 2] - centre[2]) < 45).all(axis=1)
            & (corners[:, :, 1] > centre[1] + low).all(axis=1) & (corners[:, :, 1] < centre[1] + high).all(axis=1))
    return dict(scene, indices=indices[keep].reshape(-1).tolist())


def main():
    source, out = sys.argv[1], sys.argv[2]
    scene = json.load(open(source))
    tile = (900, 520)
    top = 1.15  # the platform's top over the rails
    views = []
    for name, caption in [("island", "an island on the ground"), ("side", "a side platform on the ground"),
                          ("raised", "a side platform on a viaduct")]:
        x, y, z = scene[name]
        part = near(scene, (x, y, z))
        # The side platforms lie to the north (-z) of their track.
        across = z if name == "island" else z - 3.2
        views.append((underground.render(part, (x - 34, y + 13, across + 17), (x - 6, y + top + 0.5, across), tile, fov=40),
                      caption + ": from above"))
        views.append((underground.render(part, (x - 23, y + top + 1.7, across + (1.6 if name == "island" else 0.9)),
                                         (x + 10, y + top + 1.3, across - (0 if name == "island" else 0.8)), tile, fov=62),
                      caption + ": standing on it"))
    sheet = Image.new("RGB", (tile[0] * 2, (tile[1] + 30) * 3), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (image, caption) in enumerate(views):
        x, y = (index % 2) * tile[0], (index // 2) * (tile[1] + 30)
        draw.text((x + 10, y + 8), caption, fill=(40, 40, 40))
        sheet.paste(image, (x, y + 30))
    sheet.save(out, quality=85)


if __name__ == "__main__":
    main()
