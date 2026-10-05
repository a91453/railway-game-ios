#!/usr/bin/env python3
"""Turn WorldPop's 1 km population grid of Taiwan into the app's resource.

    pip install tifffile imagecodecs numpy
    curl -LO https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/TWN/v1/1km_ua/constrained/twn_pop_2025_CN_1km_R2025A_UA_v1.tif
    python3 tools/real-world-population/build_population_grid.py \\
        twn_pop_2025_CN_1km_R2025A_UA_v1.tif \\
        RailwayGameApp/Resources/RealWorld/taiwan_population.json

The output keeps WorldPop's own grid (30 arc-seconds, north-west origin):
each run is a row, its first column and the people in each cell from there
on, rounded to whole people. Empty cells (sea, no data, or fewer than half
a person) are left out.
"""
import hashlib
import json
import sys

import numpy as np
import tifffile

SOURCE_SHA256 = 'eae984f0d741db820081f82ea989a743fb2a75c53da30af85a8618aaac682f0e'


def main(source, out):
    raw = open(source, 'rb').read()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit(f'{source}: sha256 {digest}, expected {SOURCE_SHA256}')
    page = tifffile.TiffFile(source).pages[0]
    scale = page.tags[33550].value
    tie = page.tags[33922].value
    nodata = float(page.tags[42113].value)
    cells = page.asarray().astype('float64')
    people = np.where((cells == nodata) | ~np.isfinite(cells), 0, np.rint(cells)).astype('int64')
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
            runs.append({'r': row, 'c': start, 'p': [int(v) for v in people[row, start:col]]})
    grid = {
        'source': 'WorldPop, Taiwan 2025, constrained, 30 arc-second (about 1 km), R2025A v1',
        'doi': '10.5258/SOTON/WP00840',
        'licence': 'CC BY 4.0',
        'north': tie[4],
        'west': tie[3],
        'cellDegrees': scale[0],
        'runs': runs,
    }
    text = json.dumps(grid, ensure_ascii=False, separators=(',', ':')) + '\n'
    open(out, 'w', encoding='utf-8').write(text)
    print(f'{out}: {len(runs)} runs, {int(people.sum())} people, {len(text)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
