#!/usr/bin/env python3
"""The Rovaniemi map's base map, as vector tiles in its map pack
(`MapPacks/rovaniemi/basemap.pmtiles`, decision 789), as
`tools/hk-map/build_hk_basemap.py` makes Hong Kong's.

    python3 -I tools/rovaniemi-map/build_rovaniemi_basemap.py rovaniemi.pbf \\
        RailwayGameApp/Resources/MapPacks/rovaniemi/basemap.pmtiles

The tiles are Taiwan's (`tools/basemap/build_basemap.py`: the same layers,
classes and zooms, so the game's one style and its 3D map read both), made
from the Finland extract cut to the map (`osmium extract -b
25.15,66.27,27.65,66.83 -s smart`), with pyosmium.

What differs is the coastline: Lapland has none (the sea is 100 km south
west at Kemi). Its lakes and rivers are water as Taiwan's are; the land is
the whole box of the cut extract (`LAND`), one ring, and the sea only a
thin rim past it (`SEA_MARGIN`), outside the map.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'basemap'))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'real-world-population'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_basemap  # noqa: E402
import build_rovaniemi_rail  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'overseas-map'))
import overseas_ground  # noqa: E402

# The cut extract's box: west, south, east, north.
LAND = (25.15, 66.27, 27.65, 66.83)
SEA_MARGIN = 0.01


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build_basemap.SEA_MARGIN = SEA_MARGIN
    build_basemap.main(sys.argv[1], sys.argv[2], name='Rovaniemi base map', center=(25.73, 66.50, 10), coastline=overseas_ground.land_box(LAND))
    build_rovaniemi_rail.write_manifest(os.path.dirname(os.path.abspath(sys.argv[2])))
