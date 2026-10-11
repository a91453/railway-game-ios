#!/usr/bin/env python3
"""The raw data of a Taiwanese area for the 3D city view (Web/CityView, the
vendored jeantimex/tokyo; ARCHITECTURE decision 152): what Tokyo's
compiler reads from PLATEAU and Overpass, taken from Overture Maps and the
OpenStreetMap extract of Taiwan instead.

    pip install duckdb osmium
    curl -LO https://osmtoday.com/asia/taiwan.pbf
    python3 tools/procedural-city/taiwan_area.py buildings 2026-09-23.1 kaohsiung Web/CityView/data/raw/kaohsiung
    python3 tools/procedural-city/taiwan_area.py osm taiwan.pbf kaohsiung Web/CityView/data/raw/kaohsiung
    (cd Web/CityView && node tools/pipeline/compile.mjs --area=kaohsiung --no-ads)

`buildings` writes `overture_buildings.json`: every Overture building whose
box reaches the area (with a margin), its footprint in longitude and
latitude, and what Overture knows of it (floors, height, subtype, class,
name). Read over HTTPS as ``build_overture_building_grid.py`` does.

`osm` writes `osm.json`, `osm_land.json`, `osm_extra.json` and
`osm_poi.json` in the shape the Overpass queries of Tokyo's
``tools/pipeline/fetch.mjs`` return: the same tag filters, ways and
relations with all their nodes, the POI file with a centre per way. A way
or relation belongs to the area when one of its nodes lies inside the box
(Overpass also takes a way that only crosses it; the margin makes up for
that). The extract is read twice: relations first, then nodes and ways
with their locations (about a minute for Taiwan).

Overture's buildings are ODbL 1.0 as a whole (OSM ODbL 1.0, Shi et al.
CC BY 4.0); OpenStreetMap is ODbL 1.0. The output is a derived database:
the compiled tiles credit both (DataSourceCredits).
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'real-world-population'))

# Name: (latitude, longitude) of the centre, half the side in metres. Must
# match the area in Web/CityView/tools/pipeline/config.mjs.
AREAS = {'kaohsiung': ((22.6394, 120.3024), 750.0)}
# Data are read this far beyond the area, so that roads and parks reach its
# edge; the compiler cuts at the area itself.
MARGIN = 150.0


def box(name, margin=MARGIN):
    """West, south, east, north in degrees: the area and `margin` metres."""
    (lat, lon), half = AREAS[name]
    half += margin
    phi = math.radians(lat)
    m_lat = 111132.954 - 559.822 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    return lon - half / m_lon, lat - half / m_lat, lon + half / m_lon, lat + half / m_lat


# ---------------------------------------------------------------- Overture buildings
def buildings(release, name, out_dir):
    import duckdb
    from build_overture_building_grid import release_files, sql_list

    west, south, east, north = box(name)
    connection = duckdb.connect()
    connection.sql('INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET threads = 32')
    urls = release_files(release)
    groups = {}
    for file, group, column, low, high in connection.sql(f"""
        SELECT file_name, row_group_id, path_in_schema, stats_min_value, stats_max_value
        FROM parquet_metadata({sql_list(urls)})
        WHERE path_in_schema IN ('bbox, xmin', 'bbox, xmax', 'bbox, ymin', 'bbox, ymax')
    """).fetchall():
        groups.setdefault((file, group), {})[column.split(', ')[1]] = (float(low), float(high))
    files = sorted({file for (file, _), b in groups.items()
                    if b['xmax'][1] >= west and b['xmin'][0] <= east and b['ymax'][1] >= south and b['ymin'][0] <= north})
    out = []
    for id_, floors, height, subtype, class_, name_, shape in connection.sql(f"""
        SELECT id, num_floors, height, subtype, class, names."primary", ST_AsGeoJSON(geometry)
        FROM read_parquet({sql_list(files)})
        WHERE bbox.xmax >= {west} AND bbox.xmin <= {east} AND bbox.ymax >= {south} AND bbox.ymin <= {north}
          AND coalesce(is_underground, false) = false
        ORDER BY id
    """).fetchall():
        geometry = json.loads(shape)
        polygons = {'Polygon': [geometry['coordinates']], 'MultiPolygon': geometry['coordinates']}.get(geometry['type'])
        if not polygons:
            continue
        out.append({'id': id_, 'floors': floors, 'height': height, 'subtype': subtype, 'class': class_, 'name': name_,
                    'polygons': [[[[round(x, 7), round(y, 7)] for x, y in ring] for ring in polygon] for polygon in polygons]})
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'overture_buildings.json'), 'w') as file:
        json.dump({'release': release, 'buildings': out}, file)
    print(f'{name}: {len(out)} buildings from {len(files)} files', file=sys.stderr)


# ---------------------------------------------------------------- OpenStreetMap
def matches(value, pattern):
    return value is not None and re.fullmatch(pattern, value) is not None


# The filters of Tokyo's OSM_QUERIES (tools/pipeline/fetch.mjs), file by file.
def road_way(t):
    return (matches(t.get('highway'), r'motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|'
                                      r'tertiary|tertiary_link|unclassified|residential|living_street|service')
            or matches(t.get('railway'), r'rail|light_rail|subway|monorail|narrow_gauge'))


def land_way(t):
    return (matches(t.get('leisure'), r'park|garden|playground|pitch')
            or matches(t.get('landuse'), r'grass|forest|cemetery|religious|recreation_ground|village_green|meadow')
            or matches(t.get('natural'), r'wood|water|scrub|grassland|tree_row')
            or t.get('footway') == 'crossing')


def land_relation(t):
    return (matches(t.get('leisure'), r'park|garden') or matches(t.get('landuse'), r'grass|forest|religious')
            or matches(t.get('natural'), r'wood|water'))


def land_node(t):
    return (t.get('natural') == 'tree' or matches(t.get('highway'), r'traffic_signals|crossing')
            or t.get('amenity') == 'vending_machine')


def extra_way(t):
    return (matches(t.get('highway'), r'footway|path|pedestrian|steps|cycleway') or t.get('railway') == 'platform'
            or t.get('public_transport') == 'platform' or t.get('amenity') == 'parking'
            or matches(t.get('barrier'), r'fence|hedge|wall|retaining_wall|guard_rail')
            or matches(t.get('waterway'), r'river|stream|canal|ditch') or matches(t.get('man_made'), r'bridge|ceremonial_gate')
            or t.get('building') == 'roof' or t.get('leisure') == 'swimming_pool'
            or ('building' in t and ('building:colour' in t or 'building:material' in t)))


def extra_node(t):
    return (t.get('highway') == 'stop' or t.get('railway') == 'level_crossing' or t.get('man_made') == 'ceremonial_gate'
            or t.get('emergency') == 'fire_hydrant'
            or (t.get('tourism') == 'information' and matches(t.get('information'), r'map|board'))
            or t.get('leisure') == 'picnic_table' or 'playground' in t)


def poi(t, node):
    if 'name' in t and ('shop' in t or 'amenity' in t or 'tourism' in t or 'office' in t or 'building' in t
                        or matches(t.get('leisure'), r'fitness_centre|sports_centre|amusement_arcade|adult_gaming_centre|dance|bowling_alley')):
        return True
    return node and (matches(t.get('railway'), r'station|subway_entrance') or t.get('highway') == 'bus_stop'
                     or matches(t.get('amenity'), r'bench|bicycle_parking|post_box|telephone|toilets|taxi|police')
                     or 'historic' in t or matches(t.get('man_made'), r'flagpole|surveillance') or t.get('barrier') == 'bollard')


def osm(pbf, name, out_dir):
    import osmium

    west, south, east, north = box(name)
    inside = lambda lon, lat: west <= lon <= east and south <= lat <= north

    class Relations(osmium.SimpleHandler):
        """Land relations and POI relations, and the ways they are made of."""
        def __init__(self):
            super().__init__()
            self.land, self.poi, self.members = [], [], set()

        def relation(self, r):
            t = dict(r.tags)
            ways = [m.ref for m in r.members if m.type == 'w']
            if land_relation(t):
                self.land.append({'type': 'relation', 'id': r.id, 'tags': t,
                                  'members': [{'type': 'way', 'ref': m.ref, 'role': m.role} for m in r.members if m.type == 'w']})
                self.members.update(ways)
            elif poi(t, False):
                self.poi.append((r.id, t, ways))
                self.members.update(ways)

    relations = Relations()
    relations.apply_file(pbf)

    class Elements(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.files = {f: {'ways': {}, 'nodes': {}} for f in ('osm', 'land', 'extra', 'poi')}
            self.coords, self.member_ways, self.tagged = {}, {}, {}

        def node(self, n):
            if not n.tags or not n.location.valid() or not inside(n.location.lon, n.location.lat):
                return
            t = dict(n.tags)
            self.tagged[n.id] = t
            element = {'type': 'node', 'id': n.id, 'lat': round(n.location.lat, 7), 'lon': round(n.location.lon, 7), 'tags': t}
            if land_node(t):
                self.files['land']['nodes'][n.id] = element
            if extra_node(t):
                self.files['extra']['nodes'][n.id] = element
            if poi(t, True):
                self.files['poi']['nodes'][n.id] = element

        def way(self, w):
            t = dict(w.tags)
            refs, points = [], []
            for node in w.nodes:
                if node.location.valid():
                    refs.append(node.ref)
                    points.append((node.ref, round(node.location.lon, 7), round(node.location.lat, 7)))
            if not points:
                return
            touches = any(inside(lon, lat) for _, lon, lat in points)
            if w.id in relations.members:
                self.member_ways[w.id] = (refs, points, touches)
            if not touches or not t:
                return
            for key, wanted in (('osm', road_way), ('land', land_way), ('extra', extra_way)):
                if wanted(t):
                    self.files[key]['ways'][w.id] = {'type': 'way', 'id': w.id, 'nodes': refs, 'tags': t}
                    for ref, lon, lat in points:
                        self.coords[ref] = (lon, lat)
            if poi(t, False):
                lons, lats = [p[1] for p in points], [p[2] for p in points]
                self.files['poi']['ways'][w.id] = {'type': 'way', 'id': w.id, 'tags': t,
                                                   'center': {'lat': round((min(lats) + max(lats)) / 2, 7), 'lon': round((min(lons) + max(lons)) / 2, 7)}}

    elements = Elements()
    elements.apply_file(pbf, locations=True, idx='flex_mem')

    land_relations = []
    for r in relations.land:
        members = [elements.member_ways.get(m['ref']) for m in r['members']]
        if not any(m and m[2] for m in members):
            continue
        land_relations.append(r)
        for m in r['members']:
            way = elements.member_ways.get(m['ref'])
            if way:
                elements.files['land']['ways'].setdefault(m['ref'], {'type': 'way', 'id': m['ref'], 'nodes': way[0], 'tags': {}})
                for ref, lon, lat in way[1]:
                    elements.coords[ref] = (lon, lat)
    poi_relations = []
    for id_, t, ways in relations.poi:
        points = [p for ref in ways if ref in elements.member_ways for p in elements.member_ways[ref][1]]
        if points and any(inside(lon, lat) for _, lon, lat in points):
            lons, lats = [p[1] for p in points], [p[2] for p in points]
            poi_relations.append({'type': 'relation', 'id': id_, 'tags': t,
                                  'center': {'lat': round((min(lats) + max(lats)) / 2, 7), 'lon': round((min(lons) + max(lons)) / 2, 7)}})

    def nodes_of(ways):
        refs = sorted({ref for w in ways for ref in w['nodes']})
        return [{'type': 'node', 'id': ref, 'lat': elements.coords[ref][1], 'lon': elements.coords[ref][0],
                 **({'tags': elements.tagged[ref]} if ref in elements.tagged else {})} for ref in refs if ref in elements.coords]

    os.makedirs(out_dir, exist_ok=True)
    counts = {}
    for key, file, extra in (('osm', 'osm.json', []), ('land', 'osm_land.json', land_relations), ('extra', 'osm_extra.json', []), ('poi', 'osm_poi.json', poi_relations)):
        part = elements.files[key]
        ways = [part['ways'][k] for k in sorted(part['ways'])]
        if key == 'poi':
            listed = [part['nodes'][k] for k in sorted(part['nodes'])] + ways + extra
        else:
            nodes = {n['id']: n for n in nodes_of(ways)}
            nodes.update(part['nodes'])
            listed = [nodes[k] for k in sorted(nodes)] + ways + extra
        with open(os.path.join(out_dir, file), 'w') as handle:
            json.dump({'elements': listed}, handle, ensure_ascii=False)
        counts[file] = len(listed)
    print(f'{name}: {counts}', file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == 'buildings' and sys.argv[3] in AREAS:
        buildings(*sys.argv[2:])
    elif len(sys.argv) == 5 and sys.argv[1] == 'osm' and sys.argv[3] in AREAS:
        osm(*sys.argv[2:])
    else:
        sys.exit(__doc__)
