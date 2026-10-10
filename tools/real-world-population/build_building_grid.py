#!/usr/bin/env python3
"""Survey OpenStreetMap's buildings of Taiwan on the water grid's cells, to see
whether a real-world map's city buildings could stand where its real houses
do (the step after ARCHITECTURE decisions 142 and 144; nothing in the app
reads this yet).

    pip install osmium numpy
    curl -LO https://osmtoday.com/asia/taiwan.pbf
    python3 tools/real-world-population/build_building_grid.py \\
        RailwayGameApp/Resources/RealWorld/taiwan_population.json \\
        taiwan.pbf \\
        building_survey.json

The grid is the water grid's (``build_water_grid.py``): each 30″ population
cell cut into CUTS × CUTS cells of 1.875″, some 58 × 53 m in Taiwan, about one
of the game's 64 m cells. Every building (a closed way or a multipolygon
tagged `building=*`, not `building=no`, read as an area by pyosmium) is put
whole on the cell its footprint's centroid falls in, with:

- its footprint's area, outer rings less inner ones, on a local flat
  projection (metres east and north of the cell);
- its storeys: `building:levels`, or `height` / LEVEL_HEIGHT, when tagged;
- its centroid.

Each cell sums the footprint (its share of the cell is the coverage; a large
building whose footprint spills into the next cell counts on its centroid's
only, so a few cells read over 100 %), the storeys of the footprint whose
storeys are known (area-weighted), and the centroid of its built area.

The output is a survey, not an app resource: totals, how many of the people
of WorldPop's grid live where OSM has buildings, and for a list of places
(SPOTS) the cells of a 2 × 2 km square round them: their coverage, how many
have a building, how much of their footprint has its storeys tagged and the
density class those storeys would give (D1 up to 3 storeys, D2 4 to 11, D3 12
to 28, D4 29 and more: halfway between the game's 2, 6, 18 and 40), and how
far the built area's centroid lies from the cell's middle.

OpenStreetMap data is ODbL 1.0; the extract is read with pyosmium (BSD
2-Clause), in about a minute.
"""
import json
import math
import sys

import osmium

CUTS = 16
# Metres a storey, for a building tagged with its height only.
LEVEL_HEIGHT = 3.2
EARTH = 6_371_008.8
# Places to look at: a station or a town's middle.
SPOTS = [
    ('Taipei Main', 25.0478, 121.5172),
    ('Daan', 25.0330, 121.5434),
    ('Xinyi', 25.0330, 121.5654),
    ('Banqiao', 25.0143, 121.4637),
    ('Keelung', 25.1316, 121.7397),
    ('Zhubei', 24.8390, 121.0095),
    ('Taichung', 24.1372, 120.6869),
    ('Chiayi', 23.4793, 120.4413),
    ('Tainan', 22.9971, 120.2126),
    ('Kaohsiung', 22.6394, 120.3025),
    ('Yilan', 24.7546, 121.7584),
    ('Hualien', 23.9928, 121.6011),
    ('Yuanlin', 23.9590, 120.5735),
    ('Pingxi', 25.0257, 121.7397),
]
# Half the side of the square looked at round each spot, in metres.
SPOT_HALF = 1_000
CLASSES = ((3, 'D1'), (11, 'D2'), (28, 'D3'), (math.inf, 'D4'))


def storeys(tags):
    """A building's storeys from its tags, or None."""
    for key, scale in (('building:levels', 1.0), ('height', 1 / LEVEL_HEIGHT)):
        value = tags.get(key)
        if not value:
            continue
        try:
            number = float(value.split(';')[0].replace('m', '').strip()) * scale
        except ValueError:
            continue
        if 0 < number < 200:
            return number
    return None


class Buildings(osmium.SimpleHandler):
    """Each building's area, centroid and storeys, summed on its cell."""

    def __init__(self, north, west, step):
        super().__init__()
        self.north, self.west, self.step = north, west, step
        self.cells = {}
        self.count = 0
        self.tagged = 0

    def area(self, area):
        tags = area.tags
        kind = tags.get('building')
        if not kind or kind == 'no':
            return
        total = 0.0
        sum_lat = sum_lon = 0.0
        for outer in area.outer_rings():
            for ring, sign in [(outer, 1.0)] + [(inner, -1.0) for inner in area.inner_rings(outer)]:
                points = [(node.lat, node.lon) for node in ring if node.location.valid()]
                if len(points) < 3:
                    continue
                lat0, lon0 = points[0]
                scale = math.cos(math.radians(lat0))
                xs = [math.radians(lon - lon0) * EARTH * scale for _, lon in points]
                ys = [math.radians(lat - lat0) * EARTH for lat, _ in points]
                twice = cx = cy = 0.0
                for i in range(len(points)):
                    j = (i + 1) % len(points)
                    cross = xs[i] * ys[j] - xs[j] * ys[i]
                    twice += cross
                    cx += (xs[i] + xs[j]) * cross
                    cy += (ys[i] + ys[j]) * cross
                if abs(twice) < 1e-9:
                    continue
                part = abs(twice) / 2 * sign
                # The ring's centroid, back in degrees.
                centre_x, centre_y = cx / (3 * twice), cy / (3 * twice)
                total += part
                sum_lat += part * (lat0 + math.degrees(centre_y / EARTH))
                sum_lon += part * (lon0 + math.degrees(centre_x / (EARTH * scale)))
        if total <= 0:
            return
        lat, lon = sum_lat / total, sum_lon / total
        row = math.floor((self.north - lat) / self.step)
        column = math.floor((lon - self.west) / self.step)
        level = storeys(tags)
        self.count += 1
        cell = self.cells.setdefault((row, column), [0.0, 0.0, 0.0, 0.0, 0.0, 0])
        cell[0] += total
        cell[1] += total * lat
        cell[2] += total * lon
        if level is not None:
            self.tagged += 1
            cell[3] += total
            cell[4] += total * level
        cell[5] += 1


def cell_size(lat, step):
    """A cell's width and height in metres at `lat`."""
    height = math.radians(step) * EARTH
    return height * math.cos(math.radians(lat)), height


def density(levels):
    return next(name for limit, name in CLASSES if levels <= limit)


def main(population_path, extract, out):
    population = json.load(open(population_path))
    size = population['cellDegrees']
    north, west = population['north'], population['west']
    step = size / CUTS
    handler = Buildings(north, west, step)
    handler.apply_file(extract, locations=True)
    cells = handler.cells
    footprint = sum(cell[0] for cell in cells.values())

    # The people of each population cell, and the footprint OSM has there.
    people = {}
    for run in population['runs']:
        for offset, count in enumerate(run['p']):
            people[(run['r'], run['c'] + offset)] = count
    built = {}
    for (row, column), cell in cells.items():
        key = (row // CUTS, column // CUTS)
        built[key] = built.get(key, 0.0) + cell[0]
    total_people = sum(people.values())
    # m² of footprint a resident in each 1 km cell; Taiwan builds some 10 to
    # 20 m² of footprint a resident (50 m² of floor on 3 to 5 storeys), so
    # under 2 m² is a town OSM has hardly mapped.
    bands = [(0, 'no building'), (2, 'under 2 m2 a resident'), (5, '2 to 5'), (10, '5 to 10'), (math.inf, '10 and more')]
    by_band = {name: 0 for _, name in bands}
    for key, count in people.items():
        share = built.get(key, 0.0) / count if count else 0.0
        if built.get(key, 0.0) == 0:
            by_band['no building'] += count
            continue
        for limit, name in bands[1:]:
            if share < limit:
                by_band[name] += count
                break

    spots = []
    for name, lat, lon in SPOTS:
        width, height = cell_size(lat, step)
        rows = math.ceil(SPOT_HALF / height)
        columns = math.ceil(SPOT_HALF / width)
        middle_row = math.floor((north - lat) / step)
        middle_column = math.floor((lon - west) / step)
        area = width * height
        looked = with_building = 0
        coverages = []
        known = tagged_area = 0.0
        classes = {name: 0 for _, name in CLASSES}
        offsets = []
        for row in range(middle_row - rows, middle_row + rows):
            for column in range(middle_column - columns, middle_column + columns):
                looked += 1
                cell = cells.get((row, column))
                if not cell:
                    coverages.append(0.0)
                    continue
                with_building += 1
                coverages.append(cell[0] / area)
                tagged_area += cell[0]
                known += cell[3]
                if cell[3] > 0:
                    classes[density(cell[4] / cell[3])] += 1
                # The built area's centroid from the cell's middle, in metres.
                middle_lat = north - (row + 0.5) * step
                middle_lon = west + (column + 0.5) * step
                dy = (cell[1] / cell[0] - middle_lat) / step * height
                dx = (cell[2] / cell[0] - middle_lon) / step * width
                offsets.append(math.hypot(dx, dy))
        coverages.sort()
        offsets.sort()
        spots.append({
            'name': name,
            'cells': looked,
            'withBuilding': with_building,
            'coverageMean': round(sum(coverages) / looked, 3),
            'coverageMedian': round(coverages[len(coverages) // 2], 3),
            'storeysTaggedShare': round(known / tagged_area, 3) if tagged_area else 0,
            'classesOfTaggedCells': classes,
            'centroidOffsetMedianMetres': round(offsets[len(offsets) // 2], 1) if offsets else None,
        })

    report = {
        'source': 'OpenStreetMap (ODbL 1.0), osmtoday.com asia/taiwan.pbf',
        'gridCellDegrees': step,
        'buildings': handler.count,
        'buildingsWithStoreys': handler.tagged,
        'footprintKm2': round(footprint / 1e6, 1),
        'cellsWithBuildings': len(cells),
        'peopleByFootprintPerResident': {name: round(count / total_people, 3) for name, count in by_band.items()},
        'spots': spots,
    }
    with open(out, 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
