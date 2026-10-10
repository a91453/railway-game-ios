#!/usr/bin/env python3
"""Overture Maps' buildings in a 1 km square round Kaohsiung and Taipei
stations, in a local metre frame, for ``measure_patch.mjs`` (nothing in the
app reads this; docs/research/PROCEDURAL_CITY_STUDY.md).

    pip install duckdb osmium
    python3 tools/procedural-city/extract_patch.py 2026-09-23.1 patches.json

Reads the release's GeoParquet over HTTPS the way
``tools/real-world-population/build_overture_building_grid.py`` does (its
``release_files``): the row groups whose boxes reach a square, then the
buildings whose box does. A building belongs to the square its footprint's
centroid lies in (as jeantimex/tokyo's compiler puts a building in a tile).
Frame: metres, x east, z south, the station at the origin (Tokyo's
``makeProjection``). Underground buildings are left out.

Overture's buildings are ODbL 1.0 as a whole (sources: OSM ODbL 1.0, Shi et
al. CC BY 4.0); the output is a derived database and is not committed.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'real-world-population'))

import duckdb

from build_overture_building_grid import release_files, sql_list

# Name: (latitude, longitude) of the square's centre.
SPOTS = {'kaohsiung': (22.6394, 120.3024), 'taipei': (25.0478, 121.5170)}
HALF = 500.0


def metres_per_degree(lat):
    """Tokyo's ``makeProjection`` (src/shared/geo.js): metres a degree of
    latitude and of longitude."""
    phi = math.radians(lat)
    return (111132.954 - 559.822 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi),
            111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi))


def main(release, out):
    connection = duckdb.connect()
    connection.sql('INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET threads = 32')
    urls = release_files(release)
    boxes = {}
    for name, group, column, low, high in connection.sql(f"""
        SELECT file_name, row_group_id, path_in_schema, stats_min_value, stats_max_value
        FROM parquet_metadata({sql_list(urls)})
        WHERE path_in_schema IN ('bbox, xmin', 'bbox, xmax', 'bbox, ymin', 'bbox, ymax')
    """).fetchall():
        boxes.setdefault((name, group), {})[column.split(', ')[1]] = (float(low), float(high))
    result = {}
    for spot, (lat0, lon0) in SPOTS.items():
        m_lat, m_lon = metres_per_degree(lat0)
        west, east = lon0 - HALF / m_lon, lon0 + HALF / m_lon
        south, north = lat0 - HALF / m_lat, lat0 + HALF / m_lat
        files = sorted({name for (name, _), box in boxes.items()
                        if box['xmax'][1] >= west and box['xmin'][0] <= east
                        and box['ymax'][1] >= south and box['ymin'][0] <= north})
        buildings = []
        for floors, height, dataset, shape, lon, lat in connection.sql(f"""
            SELECT num_floors, height, list_transform(sources, s -> s.dataset)[1],
                   ST_AsGeoJSON(geometry), ST_X(ST_Centroid(geometry)), ST_Y(ST_Centroid(geometry))
            FROM read_parquet({sql_list(files)})
            WHERE bbox.xmax >= {west} AND bbox.xmin <= {east}
              AND bbox.ymax >= {south} AND bbox.ymin <= {north}
              AND coalesce(is_underground, false) = false
        """).fetchall():
            if not (west <= lon <= east and south <= lat <= north):
                continue
            geometry = json.loads(shape)
            polygons = {'Polygon': [geometry['coordinates']], 'MultiPolygon': geometry['coordinates']}.get(geometry['type'], [])
            buildings.append({
                'floors': floors, 'height': height, 'osm': dataset == 'OpenStreetMap',
                # Rings open (GeoJSON repeats the first point last).
                'polygons': [[[[round((x - lon0) * m_lon, 2), round(-(y - lat0) * m_lat, 2)] for x, y in ring[:-1]]
                              for ring in polygon] for polygon in polygons],
            })
        result[spot] = {'centre': [lat0, lon0], 'buildings': buildings}
        print(f'{spot}: {len(buildings)} buildings', file=sys.stderr)
    with open(out, 'w') as file:
        json.dump(result, file)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
