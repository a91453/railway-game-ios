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
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_rovaniemi_rail  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "overseas-map"))
import overseas_ground  # noqa: E402

SOURCE_SHA256 = "a9080fd06d4538507fec23280d27011bbfc5f9963946956b804f22d9921c9c98"
SOURCE_URL = ("https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/FIN/v1/1km_ua/constrained/"
              "fin_pop_2025_CN_1km_R2025A_UA_v1.tif")


def main(source, folder):
    fields, digest, cut = overseas_ground.population(source, SOURCE_SHA256, build_rovaniemi_rail.EXTENT)
    runs = fields["runs"]
    build_rovaniemi_rail.write(folder, "population.json", {
        "source": "WorldPop, Finland 2025, constrained, 30 arc-second (about 1 km), R2025A v1, cut to the Rovaniemi map",
        "from": SOURCE_URL,
        "licence": "CC BY 4.0",
        **fields,
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
