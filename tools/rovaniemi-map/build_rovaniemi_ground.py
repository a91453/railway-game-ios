#!/usr/bin/env python3
"""The Rovaniemi map's people, as the pack's `population.json`
(decision 789), as `tools/hk-map/build_hk_ground.py` makes Hong Kong's.

    pip install tifffile imagecodecs numpy
    curl -L -o /tmp/rv/pop/fin.tif https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/FIN/v1/1km_ua/constrained/fin_pop_2025_CN_1km_R2025A_UA_v1.tif
    python3 -I tools/rovaniemi-map/build_rovaniemi_ground.py /tmp/rv/pop/fin.tif RailwayGameApp/Resources/MapPacks/rovaniemi

WorldPop's 1 km grid of Finland (2025, constrained, R2025A v1, CC BY 4.0),
the series of Taiwan's and Hong Kong's, cut to the cells whose middle lies
in the pack's extent (`build_rovaniemi_rail.EXTENT`), in the format of
`taiwan_population.json`: WorldPop's own grid (30 arc-seconds), its north
west corner the cut's, each run a row, its first column and the people of
each cell from there on, rounded to whole people.
"""
import hashlib
import json
import math
import os
import sys

import numpy as np
import tifffile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_rovaniemi_rail  # noqa: E402

SOURCE_SHA256 = "a9080fd06d4538507fec23280d27011bbfc5f9963946956b804f22d9921c9c98"
SOURCE_URL = ("https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/FIN/v1/1km_ua/constrained/"
              "fin_pop_2025_CN_1km_R2025A_UA_v1.tif")


def main(source, folder):
    raw = open(source, "rb").read()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit(f"{source}: sha256 {digest}, expected {SOURCE_SHA256}")
    page = tifffile.TiffFile(source).pages[0]
    scale = page.tags[33550].value
    tie = page.tags[33922].value
    nodata = float(page.tags[42113].value)
    cells = page.asarray().astype("float64")
    people = np.where((cells == nodata) | ~np.isfinite(cells), 0, np.rint(cells)).astype("int64")
    north, west, step = tie[4], tie[3], scale[0]
    extent = build_rovaniemi_rail.EXTENT
    # The rows and columns whose middle is in the extent.
    top = math.ceil((north - extent["north"]) / step - 0.5)
    bottom = math.floor((north - extent["south"]) / step - 0.5)
    left = math.ceil((extent["west"] - west) / step - 0.5)
    right = math.floor((extent["east"] - west) / step - 0.5)
    cut = people[top:bottom + 1, left:right + 1]
    runs = []
    for row in range(cut.shape[0]):
        col = 0
        while col < cut.shape[1]:
            if cut[row, col] <= 0:
                col += 1
                continue
            start = col
            while col < cut.shape[1] and cut[row, col] > 0:
                col += 1
            runs.append({"r": row, "c": start, "p": [int(v) for v in cut[row, start:col]]})
    build_rovaniemi_rail.write(folder, "population.json", {
        "source": "WorldPop, Finland 2025, constrained, 30 arc-second (about 1 km), R2025A v1, cut to the Rovaniemi map",
        "from": SOURCE_URL,
        "licence": "CC BY 4.0",
        "north": north - top * step,
        "west": west + left * step,
        "cellDegrees": step,
        "runs": runs,
    })
    build_rovaniemi_rail.write_manifest(folder)
    record = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rovaniemi_sources.json")
    with open(record, encoding="utf-8") as f:
        sources = json.load(f)
    sources["inputs"]["fin_pop_2025_CN_1km_R2025A_UA_v1.tif"] = {
        "sha256": digest, "from": SOURCE_URL, "licence": "CC BY 4.0, WorldPop",
    }
    build_rovaniemi_rail.write(os.path.dirname(record), "rovaniemi_sources.json", sources)
    print(f"population.json: {len(runs)} runs, {int(cut.sum())} people, {cut.shape[0]} x {cut.shape[1]} cells")


if __name__ == "__main__":
    main(*sys.argv[1:])
