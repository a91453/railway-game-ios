#!/usr/bin/env python3
"""Hong Kong's people, as the pack's `population.json` (decision 712).

    pip install tifffile imagecodecs numpy
    curl -L -o /tmp/hk/pop/hkg.tif https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/HKG/v1/1km_ua/constrained/hkg_pop_2025_CN_1km_R2025A_UA_v1.tif
    python3 -I tools/hk-map/build_hk_ground.py /tmp/hk/pop/hkg.tif RailwayGameApp/Resources/MapPacks/hongkong

WorldPop's 1 km grid of Hong Kong (2025, constrained, R2025A v1, CC BY 4.0),
the series Taiwan's `taiwan_population.json` is of, in that file's format
(`tools/real-world-population/build_population_grid.py`): WorldPop's own
grid (30 arc-seconds, north-west origin), each run a row, its first column
and the people of each cell from there on, rounded to whole people.

The grid's box must lie inside the pack's extent (`build_hk_mtr.EXTENT`,
written to `pack.json`): the map is as large as the land the people live on.
"""
import hashlib
import json
import os
import sys

import numpy as np
import tifffile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_hk_mtr  # noqa: E402

SOURCE_SHA256 = "913fd1d72d312f12768748d4cb9779a025c4581ecee5fe0aff61230352f8c6d6"
SOURCE_URL = ("https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/HKG/v1/1km_ua/constrained/"
              "hkg_pop_2025_CN_1km_R2025A_UA_v1.tif")


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
    runs = []
    for row in range(people.shape[0]):
        col = 0
        while col < people.shape[1]:
            if people[row, col] <= 0:
                col += 1
                continue
            start = col
            while col < people.shape[1] and people[row, col] > 0:
                col += 1
            runs.append({"r": row, "c": start, "p": [int(v) for v in people[row, start:col]]})
    # Everyone lives on the map.
    extent = build_hk_mtr.EXTENT
    lived = [(north - (run["r"] + edge) * step, west + (run["c"] + side * len(run["p"])) * step)
             for run in runs for edge in (0, 1) for side in (0, 1)]
    for latitude, longitude in lived:
        if not (extent["south"] <= latitude <= extent["north"] and extent["west"] <= longitude <= extent["east"]):
            sys.exit(f"people at {latitude}, {longitude} live outside the pack's extent {extent}")
    build_hk_mtr.write(folder, "population.json", {
        "source": "WorldPop, Hong Kong 2025, constrained, 30 arc-second (about 1 km), R2025A v1",
        "from": SOURCE_URL,
        "licence": "CC BY 4.0",
        "north": north,
        "west": west,
        "cellDegrees": step,
        "runs": runs,
    })
    build_hk_mtr.write_manifest(folder)
    record = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hk_sources.json")
    with open(record, encoding="utf-8") as f:
        sources = json.load(f)
    sources["inputs"]["hkg_pop_2025_CN_1km_R2025A_UA_v1.tif"] = {
        "sha256": digest, "from": SOURCE_URL, "licence": "CC BY 4.0, WorldPop",
    }
    with open(record, "w", encoding="utf-8") as f:
        json.dump(sources, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"population.json: {len(runs)} runs, {int(people.sum())} people")


if __name__ == "__main__":
    main(*sys.argv[1:])
