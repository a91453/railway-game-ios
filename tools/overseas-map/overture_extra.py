#!/usr/bin/env python3
"""The buildings OpenStreetMap has not drawn, from Overture Maps
(decision 1001), for an overseas map whose buildings are otherwise
OpenStreetMap's (`overseas_buildings.make`).

    python3 -I tools/overseas-map/overture_extra.py extract 2026-11-18.0 \\
        129.34,32.09,131.33,34.03 /tmp/fk/ov/japan.parquet

Overture's buildings are OpenStreetMap's plus machine-drawn outlines where
OpenStreetMap has none (in Japan, Microsoft's ML Building Footprints and
Shi et al.'s East Asian buildings, doi:10.5281/zenodo.8174931). `extract`
keeps the machine-drawn ones whose box reaches the map's, by id, with
their dataset and outline (WKB); `overseas_buildings.make` then drops any
that touches a building of the newer OpenStreetMap extract the pack is
made from, so a building mapped since Overture's release is not drawn
twice. They have no use and no storeys: the storeys are guessed by the
pack's own rule from the buildings OpenStreetMap tags.

Needs `pip install duckdb` (MIT; decision 93) and reads Overture's public
bucket, as `tools/overture-footprint-tiles/build_footprint_tiles.py`
does. The same release gives the same file.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'real-world-population'))

OSM = 'OpenStreetMap'
# The machine-drawn datasets kept, in the order they are laid: where two
# overlap, the first is kept.
DATASETS = ('doi:10.5281/zenodo.8174931', 'Microsoft ML Buildings')


def extract(release, box, out):
    import duckdb
    from build_overture_building_grid import release_files, sql_list
    west, south, east, north = (float(v) for v in box.split(','))
    connection = duckdb.connect()
    connection.sql('INSTALL httpfs; LOAD httpfs;')
    connection.sql('SET threads = 32')
    urls = release_files(release)
    boxes = {}
    for name, group, column, low, high in connection.sql(f"""
        SELECT file_name, row_group_id, path_in_schema, stats_min_value, stats_max_value
        FROM parquet_metadata({sql_list(urls)})
        WHERE path_in_schema IN ('bbox, xmin', 'bbox, xmax', 'bbox, ymin', 'bbox, ymax')
    """).fetchall():
        boxes.setdefault((name, group), {})[column.split(', ')[1]] = (float(low), float(high))
    files = sorted({name for (name, _), b in boxes.items()
                    if b['xmax'][1] >= west and b['xmin'][0] <= east and b['ymax'][1] >= south and b['ymin'][0] <= north})
    print(f'{len(urls)} files, {len(files)} reach the map', file=sys.stderr)
    connection.sql(f"""
        COPY (
            SELECT id, sources[1].dataset AS dataset, geometry AS footprint
            FROM read_parquet({sql_list(files)})
            WHERE bbox.xmax >= {west} AND bbox.xmin <= {east} AND bbox.ymax >= {south} AND bbox.ymin <= {north}
              AND NOT coalesce(is_underground, false) AND sources[1].dataset IN ({', '.join(f"'{d}'" for d in DATASETS)})
            ORDER BY id
        ) TO '{out}' (FORMAT parquet, COMPRESSION zstd)
    """)
    for dataset, count in connection.sql(f"SELECT dataset, count(*) FROM read_parquet('{out}') GROUP BY 1 ORDER BY 1").fetchall():
        print(f'{dataset}: {count}', file=sys.stderr)


def read(path):
    """(id, dataset, WKB) of the extract, by id."""
    import duckdb
    rows = duckdb.connect().sql(f"SELECT id, dataset, footprint FROM read_parquet('{path}') ORDER BY id").fetchall()
    return [(name, dataset, bytes(wkb)) for name, dataset, wkb in rows]


if __name__ == '__main__':
    if len(sys.argv) != 5 or sys.argv[1] != 'extract':
        sys.exit(__doc__)
    extract(*sys.argv[2:])
