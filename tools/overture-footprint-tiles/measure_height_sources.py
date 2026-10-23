#!/usr/bin/env python3
"""How good each source of building heights is for Overture's buildings of
Taiwan (decision 386, the report's "樓高來源"). Nothing in the app reads this.

    python3 tools/overture-footprint-tiles/measure_height_sources.py \\
        footprints.parquet taiwan_population.json heights.json \\
        GLOBFP_DIR TAICHUNG.shp TAIPEI.shp out.json [GHSL_DIR]

GLOBFP_DIR holds 3D-GloBFP's shapefiles of the grids that reach Taiwan,
Kinmen and Matsu (2257, 2274, 2275, 2277, 2412, 2413; Che et al. 2024, CC BY
4.0, doi:10.5281/zenodo.15487037, each grid a zip on figshare). TAICHUNG.shp
is Taichung's building map of 2022 (data.gov.tw 162900, the original city,
TWD97, `B1D` storeys); TAIPEI.shp is Taipei's building permit map
(data.gov.tw 151936, TWD97, `bud_floor`). Both are under the Government Open
Data License 1.0. GHSL_DIR holds GHS-BUILT-H ANBH R2023A's 100 m Mollweide
tiles R6_C30 and R7_C30 (JRC, CC BY 4.0, doi:10.2905/85005901-3A49-48DD-
9D19-6261354F56FE), read by `tiff.py`: a footprint takes the value of the
cell its centroid is in (0 = no building there).

A source's polygons are matched to an Overture footprint by overlap: the
footprint takes the area-weighted mean of the polygons over it when they
cover at least half of it. Storeys from metres are metres / 3.2, at least 1.
The density guess is `proposed_storeys` with heights.json's table (hashed on
the centroid to 1e-5 degrees, a stand-in for step 2's tile coordinates).
"""
import glob
import json
import math
import os
import sys

import duckdb

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_footprint_tiles as T  # noqa: E402

BOXES = T.BOXES
COVER = 0.5
# The three samples the game-planning session asked for: two city centres
# (west, south, east, north) and a rural county.
SAMPLES = {'臺北市中心': (121.50, 25.02, 121.57, 25.07), '高雄市區': (120.28, 22.60, 120.35, 22.66),
           '雲林縣': '10009'}


def mollweide(lon, lat):
    """ESRI:54009, World Mollweide on the sphere of radius 6,378,137 m."""
    phi = math.radians(lat)
    theta = phi
    for _ in range(30):
        theta -= (2 * theta + math.sin(2 * theta) - math.pi * math.sin(phi)) / (2 + 2 * math.cos(2 * theta))
    return (2 * math.sqrt(2) / math.pi * T.EARTH * math.radians(lon) * math.cos(theta),
            math.sqrt(2) * T.EARTH * math.sin(theta))


def ghsl_lookup(directory):
    from tiff import Raster
    rasters = [Raster(path, cache=4000) for path in sorted(glob.glob(os.path.join(directory, '**', '*.tif'), recursive=True))]

    def at(lon, lat):
        x, y = mollweide(lon, lat)
        for raster in rasters:
            value = raster.at(x, y)
            if value is not None:
                return value
        return None
    return at


def connect(extract_path):
    connection = duckdb.connect()
    connection.sql('INSTALL spatial; LOAD spatial; SET geometry_always_xy = true;')
    connection.sql(f"""
        CREATE TABLE o AS SELECT id, num_floors, height, subtype, dataset, county, lon, lat,
               ST_GeomFromWKB(footprint) AS geom
        FROM read_parquet('{extract_path}')
    """)
    return connection


def load_globfp(connection, directory):
    within = ' OR '.join(f'ST_Intersects(geom, ST_MakeEnvelope({w}, {s}, {e}, {n}))' for w, s, e, n in BOXES)
    connection.sql('CREATE TABLE g (height DOUBLE, geom GEOMETRY)')
    for path in sorted(glob.glob(os.path.join(directory, '**', '*.shp'), recursive=True)):
        connection.sql(f"INSERT INTO g SELECT Height, ST_GeomFromWKB(ST_AsWKB(geom)) FROM ST_Read('{path}') WHERE {within}")


def load_twd97(connection, name, path, storeys):
    connection.sql(f"""
        CREATE TABLE {name} AS SELECT {storeys} AS height,
               ST_GeomFromWKB(ST_AsWKB(ST_Transform(geom, 'EPSG:3826', 'EPSG:4326', true))) AS geom
        FROM ST_Read('{path}')
    """)
    connection.sql(f'DELETE FROM {name} WHERE height IS NULL OR height <= 0')


def matched(connection, source):
    """Each Overture id the source covers by COVER or more, with the
    area-weighted mean of the source's values over it."""
    rows = connection.sql(f"""
        WITH pairs AS (
            SELECT o.id, ST_Area(ST_Intersection(o.geom, s.geom)) AS shared, s.height, ST_Area(o.geom) AS area
            FROM o JOIN {source} s ON ST_Intersects(o.geom, s.geom)
        )
        SELECT id, sum(shared * height) / sum(shared) FROM pairs
        GROUP BY id HAVING sum(shared) >= {COVER} * any_value(area) AND sum(shared) > 0
    """).fetchall()
    return dict(rows)


def errors(pairs):
    """Median and p90 of |guess − truth| in storeys, the share exactly right
    and within one, and the median signed error."""
    if not pairs:
        return None
    signed = sorted(guess - truth for guess, truth in pairs)
    absolute = sorted(abs(e) for e in signed)

    def at(values, p):
        return values[min(len(values) - 1, int(p * len(values)))]
    return {'buildings': len(pairs), 'median': at(absolute, 0.5), 'p90': at(absolute, 0.9),
            'exact': round(sum(e == 0 for e in absolute) / len(pairs), 3),
            'withinOne': round(sum(e <= 1 for e in absolute) / len(pairs), 3),
            'bias': at(signed, 0.5)}


def ghsl_report(rows, ghsl, globfp_metres, taichung_storeys, known, guess):
    """GHSL's cell height for every footprint, against the same truths;
    and in the three samples, cell by cell, against 3D-GloBFP."""
    cells, height, in_sample = {}, {}, {}
    for id_, county, lon, lat in rows:
        metres = ghsl(lon, lat)
        height[id_] = metres
        x, y = mollweide(lon, lat)
        cell = (int(x // 100), int(y // 100))
        for name, where in SAMPLES.items():
            inside = county == where if isinstance(where, str) else \
                where[0] <= lon < where[2] and where[1] <= lat < where[3]
            if inside:
                in_sample.setdefault(name, set()).add(cell)
                entry = cells.setdefault((name, cell), [metres, 0.0, 0.0])
                if id_ in globfp_metres:
                    entry[1] += globfp_metres[id_]
                    entry[2] += 1
    storeys = {k: max(1, round(v / T.LEVEL_HEIGHT)) for k, v in height.items() if v}

    def against(truth, estimate, only=None):
        return errors([(estimate[k], v) for k, v in truth.items() if k in estimate and (only is None or k in only)])
    samples = {}
    for name in SAMPLES:
        rows_here = [cells[(name, c)] for c in sorted(in_sample.get(name, ()))]
        both = [(g, total / n) for g, total, n in rows_here if g and n]
        gaps = sorted(abs(g - b) for g, b in both)
        samples[name] = {
            'cellsWithBuildings': len(rows_here),
            'noGhsl': round(sum(1 for g, _, _ in rows_here if not g) / max(1, len(rows_here)), 3),
            'noGlobfp': round(sum(1 for _, _, n in rows_here if not n) / max(1, len(rows_here)), 3),
            'neither': round(sum(1 for g, _, n in rows_here if not g and not n) / max(1, len(rows_here)), 3),
            'medianGapMetres': round(gaps[len(gaps) // 2], 1) if gaps else None,
            'p90GapMetres': round(gaps[int(0.9 * len(gaps))], 1) if gaps else None,
            'medianGhslMetres': round(sorted(g for g, _ in both)[len(both) // 2], 1) if both else None,
            'medianGlobfpMetres': round(sorted(b for _, b in both)[len(both) // 2], 1) if both else None,
        }
    return {
        'covered': len(storeys),
        'againstTaichung': against(taichung_storeys, storeys),
        'densityGuessOnSameTaichung': against(taichung_storeys, guess, storeys),
        'againstTagged': against(known, storeys),
        'densityGuessOnSameTagged': against(known, guess, storeys),
        'samples': samples,
    }


def main(extract_path, population_path, heights_path, globfp_dir, taichung, taipei, out, ghsl_dir=None):
    connection = connect(extract_path)
    load_globfp(connection, globfp_dir)
    load_twd97(connection, 'taichung', taichung, 'B1D')
    load_twd97(connection, 'taipei', taipei,
               "coalesce(nullif(bud_floor::INT, 0), try_cast(regexp_extract(budatt_no, '(\\d+)F$', 1) AS INT))")
    globfp_metres = matched(connection, 'g')
    globfp = {k: max(1, round(v / T.LEVEL_HEIGHT)) for k, v in globfp_metres.items()}
    taichung_storeys = {k: max(1, round(v)) for k, v in matched(connection, 'taichung').items()}
    taipei_storeys = {k: max(1, round(v)) for k, v in matched(connection, 'taipei').items()}

    density = T.density_lookup(population_path)
    table = {(r['group'], T.DENSITY_BANDS.index(r['density']), T.AREA_BANDS.index(r['area'])): r
             for r in json.load(open(heights_path))['table']}
    square = (math.radians(1) * T.EARTH) ** 2
    buildings = connection.sql(f"""
        SELECT id, num_floors, height, subtype, dataset, county, lon, lat,
               ST_Area(geom) * {square} * cos(radians(lat)) FROM o
    """).fetchall()
    known, guess, by_county, by_source = {}, {}, {}, {}
    for id_, floors, height, subtype, dataset, county, lon, lat, area in buildings:
        group = 'industrial' if subtype in ('industrial', 'agricultural', 'outbuilding') else \
            'other' if subtype not in (None, 'residential', 'commercial') else 'homes'
        guess[id_] = T.proposed_storeys(table, group, density(lon, lat), area, int(lon * 1e5), int(lat * 1e5))
        storeys = T.storeys_of(floors, height)
        if storeys:
            known[id_] = storeys
        count = by_county.setdefault(county, [0, 0])
        count[0] += 1
        count[1] += id_ in globfp
        source = 'OpenStreetMap' if dataset == 'OpenStreetMap' else 'Shi'
        count = by_source.setdefault(source, [0, 0])
        count[0] += 1
        count[1] += id_ in globfp

    def against(truth, estimate, only=None):
        return errors([(estimate[k], v) for k, v in truth.items() if k in estimate and (only is None or k in only)])
    report = {
        'buildings': len(buildings),
        'osmTaggedStoreys': len(known),
        'globfp': {
            'covered': len(globfp),
            'coveredWithoutStoreys': sum(1 for k in globfp if k not in known),
            'bySource': {k: {'buildings': v[0], 'covered': v[1]} for k, v in sorted(by_source.items())},
            'byCounty': {k: {'buildings': v[0], 'covered': v[1]} for k, v in sorted(by_county.items())},
            'againstTagged': against(known, globfp),
            'densityGuessOnSameBuildings': against(known, guess, globfp),
        },
        'taichung2022': {
            'polygons': connection.sql('SELECT count(*) FROM taichung').fetchall()[0][0],
            'covered': len(taichung_storeys),
            'coveredWithoutStoreys': sum(1 for k in taichung_storeys if k not in known),
            'tagged': against(taichung_storeys, known),
            'globfp': against(taichung_storeys, globfp),
            'densityGuessOnGlobfpBuildings': against(taichung_storeys, guess, globfp),
            'densityGuess': against(taichung_storeys, guess),
        },
        'taipeiPermits': {
            'polygons': connection.sql('SELECT count(*) FROM taipei').fetchall()[0][0],
            'covered': len(taipei_storeys),
            'coveredWithoutStoreys': sum(1 for k in taipei_storeys if k not in known),
            'tagged': against(taipei_storeys, known),
            'densityGuess': against(taipei_storeys, guess),
        },
    }
    if ghsl_dir:
        report['ghsl'] = ghsl_report([(b[0], b[5], b[6], b[7]) for b in buildings], ghsl_lookup(ghsl_dir),
                                     globfp_metres, taichung_storeys, known, guess)
    with open(out, 'w') as file:
        json.dump(report, file, ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    if len(sys.argv) not in (8, 9):
        sys.exit(__doc__)
    main(*sys.argv[1:])
