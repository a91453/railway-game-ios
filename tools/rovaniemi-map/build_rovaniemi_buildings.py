#!/usr/bin/env python3
"""Rovaniemi's buildings, as footprint tiles in its map pack
(`MapPacks/rovaniemi/buildings.pmtiles`, decision 799).

    python3 -I tools/rovaniemi-map/build_rovaniemi_buildings.py \\
        rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi

The tiles are Taiwan's (`tools/overture-footprint-tiles/`, `footprints/2`:
one gzipped z16 tile of outlines, storeys and uses, in a PMTiles archive),
written by that tool's own encoder as Hong Kong's are
(`tools/hk-map/build_hk_buildings.py`, whose reader of the extract and
table of uses this one runs), so the 3D map's one reader
(`Map3DFootprints.swift`) reads all three.

Everything is OpenStreetMap's (osmtoday.com's `europe/finland.pbf`, cut to
the map as the README says and read with pyosmium): Finland's National
Land Survey has no key-free download (decision 789), and Lapland has no
measured heights like Hong Kong's Lands Department's.

Left out: a building under SMALLEST m² that is not tagged as somewhere
people live or work (the sheds, wood stores and carports beside every
house, a third of the extract, which the 3D map would strew round each
house as boxes).

Storeys, in this order:

1. OpenStreetMap's `building:levels`, or its `height` at the game's 3.2 m
   a storey (origin `tags`); levels that would make a storey under half a
   metre of the tagged height are a slip and are not used, as in Hong
   Kong's tool.
2. A guess from the tagged buildings (origin `guess`), as Taiwan's
   `heights` step makes it: grouped by what they are (the tool's groups,
   and houses apart from flats), the people living round them (the pack's
   `population.json`, WorldPop) and their footprint, between the group's
   lower and upper quartiles, picked by a hash of where it stands. One in
   fifty of Rovaniemi's buildings is tagged, so a band with fewer than
   KNOWN tagged buildings takes every group's of the same footprint among
   as many people (so a village hall is not guessed from the town's
   flats), then its group's of that footprint anywhere, then every
   group's, then one storey. (The tool's own fallback, two to four
   storeys, is Taiwan's towns; here it would have stood four storeys on
   a lakeside cabin.)

A building's use is its `building` tag's (Hong Kong's table, with
Finland's `sauna`, `outbuilding`, `boathouse` and `allotment_house`).

Also writes `tools/rovaniemi-map/rovaniemi_buildings.json` (what was read
and made) and the pack's `pack.json`.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'overseas-map'))
sys.path.insert(0, os.path.join(HERE, '..', 'hk-map'))
sys.path.insert(0, HERE)
import build_hk_buildings as hk  # noqa: E402
import build_rovaniemi_rail  # noqa: E402
import overseas_buildings  # noqa: E402

USE_OF = dict(hk.USE_OF, sauna='outbuilding', outbuilding='outbuilding', boathouse='outbuilding',
              allotment_house='residential')


def main(extract, folder):
    overseas_buildings.make(
        extract, folder, build_rovaniemi_rail.EXTENT, title='Rovaniemi building footprints', use_of=USE_OF,
        report_path=os.path.join(HERE, 'rovaniemi_buildings.json'),
        extract_from='https://osmtoday.com/europe/finland.pbf, cut with osmium extract -b 25.15,66.27,27.65,66.83 -s smart',
        decision=799, write_manifest=build_rovaniemi_rail.write_manifest)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
