#!/usr/bin/env python3
"""Survey Overture Maps' buildings of Taiwan on the water grid's cells, the
same way ``build_building_grid.py`` surveys OpenStreetMap's, to see whether
Overture has the real houses OSM lacks (nothing in the app reads this).

    pip install duckdb osmium
    python3 tools/real-world-population/build_overture_building_grid.py \\
        extract 2026-09-23.1 overture_taiwan.parquet
    python3 tools/real-world-population/build_overture_building_grid.py \\
        survey RailwayGameApp/Resources/RealWorld/taiwan_population.json \\
        overture_taiwan.parquet overture_survey.json

`extract` reads the release's `theme=buildings/type=building` GeoParquet
from Overture's public S3 bucket over HTTPS (DuckDB's httpfs, no account):
first every file's footer, to keep the row groups whose bounding boxes reach
BOUNDS, then those row groups' buildings whose own box does, with their
storeys, height, sources and footprint. Some 2 million buildings, 190 MB, in
under a minute. BOUNDS is mainland Taiwan and Penghu; Kinmen and Matsu lie
outside it (their box would take in Xiamen's or Fuzhou's coast).

`survey` puts every building whole on the cell its footprint's centroid
falls in, as the OSM survey does: footprint on a local flat projection,
storeys `num_floors` or `height` / LEVEL_HEIGHT. It writes the OSM survey's
report three times: every Overture building, only those Overture took from
OSM, and only the others (in Taiwan, all from one machine-learning dataset);
plus, for each spot, how much of its footprint came from OSM. People count
only inside BOUNDS.

Overture's buildings are ODbL 1.0 as a whole; each building's source keeps
its own licence (`sources[].license`): OSM ODbL 1.0, the East Asian
buildings of Shi et al. (doi:10.5281/zenodo.8174931) CC BY 4.0. DuckDB is
MIT.
"""
import json
import math
import re
import sys
import urllib.parse
import urllib.request

import duckdb

from build_building_grid import CUTS, LEVEL_HEIGHT, EARTH, SPOTS, spot_cells, survey

BUCKET = 'https://overturemaps-us-west-2.s3.us-west-2.amazonaws.com/'
# West, south, east, north.
BOUNDS = (119.3, 21.8, 122.1, 25.4)
OSM = 'OpenStreetMap'


def release_files(release):
    """The URLs of a release's building files, from the bucket's listing."""
    prefix = f'release/{release}/theme=buildings/type=building/'
    keys, token = [], None
    while True:
        query = f'?list-type=2&prefix={prefix}' + (f'&continuation-token={urllib.parse.quote(token)}' if token else '')
        text = urllib.request.urlopen(BUCKET + query).read().decode()
        keys += re.findall(r'<Key>(.*?\.parquet)</Key>', text)
        more = re.search(r'<NextContinuationToken>(.*?)</NextContinuationToken>', text)
        if not more:
            return [BUCKET + key for key in keys]
        token = more.group(1)


def sql_list(urls):
    return '[' + ','.join(f"'{url}'" for url in urls) + ']'


def extract(release, out):
    west, south, east, north = BOUNDS
    connection = duckdb.connect()
    connection.sql('INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial;')
    # Reading footers is waiting on the network, not the processor.
    connection.sql('SET threads = 32')
    urls = release_files(release)
    # Each row group's box, from the files' footers.
    boxes = {}
    for name, group, column, low, high in connection.sql(f"""
        SELECT file_name, row_group_id, path_in_schema, stats_min_value, stats_max_value
        FROM parquet_metadata({sql_list(urls)})
        WHERE path_in_schema IN ('bbox, xmin', 'bbox, xmax', 'bbox, ymin', 'bbox, ymax')
    """).fetchall():
        boxes.setdefault((name, group), {})[column.split(', ')[1]] = (float(low), float(high))
    files = sorted({name for (name, _), box in boxes.items()
                    if box['xmax'][1] >= west and box['xmin'][0] <= east
                    and box['ymax'][1] >= south and box['ymin'][0] <= north})
    print(f'{len(urls)} files, {len(files)} reach Taiwan', file=sys.stderr)
    connection.sql(f"""
        COPY (
            SELECT id, num_floors, height, is_underground, has_parts,
                   list_transform(sources, s -> s.dataset) AS datasets,
                   list_transform(sources, s -> s.license) AS licenses,
                   ST_AsWKB(geometry) AS footprint
            FROM read_parquet({sql_list(files)})
            WHERE bbox.xmax >= {west} AND bbox.xmin <= {east}
              AND bbox.ymax >= {south} AND bbox.ymin <= {north}
        ) TO '{out}' (FORMAT parquet, COMPRESSION zstd)
    """)


def cells_of(connection, population, step, where):
    """The OSM survey's cells of the buildings matching `where`, each with
    its footprint from OSM appended."""
    north, west = population['north'], population['west']
    # m² a square degree at the equator.
    square = (math.radians(1) * EARTH) ** 2
    rows = connection.sql(f"""
        WITH footprints AS (
            SELECT ST_GeomFromWKB(footprint) AS shape,
                   datasets[1] = '{OSM}' AS osm,
                   CASE WHEN num_floors > 0 AND num_floors < 200 THEN num_floors
                        WHEN height > 0 AND height / {LEVEL_HEIGHT} < 200 THEN height / {LEVEL_HEIGHT}
                   END AS storeys
            FROM buildings WHERE {where}
        ), placed AS (
            SELECT ST_X(ST_Centroid(shape)) AS lon, ST_Y(ST_Centroid(shape)) AS lat,
                   ST_Area(shape) AS degrees, osm, storeys
            FROM footprints
        ), measured AS (
            SELECT *, degrees * {square} * cos(radians(lat)) AS area FROM placed WHERE degrees > 0
        )
        SELECT floor(({north} - lat) / {step})::BIGINT AS row,
               floor((lon - {west}) / {step})::BIGINT AS col,
               sum(area), sum(area * lat), sum(area * lon),
               coalesce(sum(area) FILTER (storeys IS NOT NULL), 0),
               coalesce(sum(area * storeys) FILTER (storeys IS NOT NULL), 0),
               count(*),
               coalesce(sum(area) FILTER (osm), 0),
               count(storeys)
        FROM measured GROUP BY ALL
    """).fetchall()
    return {(row[0], row[1]): list(row[2:]) for row in rows}


def osm_share(population, step, cells):
    """For each spot, the share of its footprint Overture took from OSM."""
    shares = {}
    for name, lat, lon in SPOTS:
        total = osm = 0.0
        for key in spot_cells(lat, lon, population['north'], population['west'], step):
            cell = cells.get(key)
            if cell:
                total += cell[0]
                osm += cell[6]
        shares[name] = round(osm / total, 3) if total else 0
    return shares


def main_survey(population_path, extract_path, out):
    population = json.load(open(population_path))
    step = population['cellDegrees'] / CUTS
    connection = duckdb.connect()
    connection.sql('INSTALL spatial; LOAD spatial;')
    connection.sql(f"CREATE VIEW buildings AS SELECT * FROM read_parquet('{extract_path}')")
    report = {
        'source': 'Overture Maps buildings (ODbL 1.0), ' + extract_path,
        'bounds': BOUNDS,
        'datasets': [
            {'dataset': dataset, 'license': license, 'buildings': count}
            for dataset, license, count in connection.sql(
                'SELECT datasets[1], licenses[1], count(*) FROM buildings GROUP BY ALL ORDER BY 3 DESC').fetchall()
        ],
    }
    for name, where in (('all', 'true'), ('osm', f"datasets[1] = '{OSM}'"), ('others', f"datasets[1] <> '{OSM}'")):
        cells = cells_of(connection, population, step, where)
        part = survey(population, step, cells, bounds=BOUNDS)
        part['buildingsWithStoreys'] = sum(cell[7] for cell in cells.values())
        if name == 'all':
            part['osmFootprintShareOfSpots'] = osm_share(population, step, cells)
        report[name] = part
    with open(out, 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'extract':
        extract(*sys.argv[2:])
    elif len(sys.argv) == 5 and sys.argv[1] == 'survey':
        main_survey(*sys.argv[2:])
    else:
        sys.exit(__doc__)
