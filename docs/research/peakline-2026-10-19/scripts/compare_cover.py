"""Compare ESA WorldCover 2021 (10 m window) with the game's current land data in the same box:
the OSM base map (taiwan.pmtiles z13: landcover wood/grass/wetland/sand, park, water), the
real-world zones (taiwan_places.json: farmland/industrial/park, a 7.5" cell counts at >= 8/16
samples, as LandImport does) and the water grid (taiwan_water.json).
Usage: venv/bin/python -I compare_cover.py wc.npy W S E N repo out_prefix"""
import sys, json, math, numpy as np, mercantile, mapbox_vector_tile
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from shapely.geometry import shape, mapping
from shapely.ops import transform as stransform
from PIL import Image, ImageDraw
sys.path.insert(0, sys.argv[0].rsplit('/', 1)[0]); from pmtiles_read import PMTiles
wc = np.load(sys.argv[1]); W, S, E, N = map(float, sys.argv[2:6]); repo = sys.argv[6]; out = sys.argv[7]
H, Wd = wc.shape; tr = from_bounds(W, S, E, N, Wd, H)
# 1. OSM base map
pm = PMTiles(repo + '/RailwayGameApp/Resources/BaseMap/taiwan.pmtiles'); Z = 13
shapes = {'wood': [], 'grass': [], 'wetland': [], 'sand': [], 'park': [], 'water': []}
for t in mercantile.tiles(W, S, E, N, Z):
    data = pm.get(Z, t.x, t.y)
    if not data: continue
    b = mercantile.bounds(t); layers = mapbox_vector_tile.decode(data)
    for lname in ('landcover', 'park', 'water'):
        lay = layers.get(lname)
        if not lay: continue
        ext = lay.get('extent', 4096)
        def to_ll(x, y, z=None):
            lon = b.west + (np.asarray(x) / ext) * (b.east - b.west)
            # y_coord_down=False default in decode: y grows north
            ym0, ym1 = math.log(math.tan(math.pi / 4 + math.radians(b.south) / 2)), math.log(math.tan(math.pi / 4 + math.radians(b.north) / 2))
            ym = ym0 + (np.asarray(y) / ext) * (ym1 - ym0)
            lat = np.degrees(2 * np.arctan(np.exp(ym)) - math.pi / 2)
            return lon, lat
        for f in lay['features']:
            g = f['geometry']
            if g['type'] not in ('Polygon', 'MultiPolygon'): continue
            geom = stransform(to_ll, shape(g))
            key = f['properties'].get('class') if lname == 'landcover' else lname
            if key in shapes: shapes[key].append(geom)
osm = {k: (rasterize([(mapping(g), 1) for g in v], out_shape=wc.shape, transform=tr, dtype='uint8') > 0) if v else np.zeros(wc.shape, bool) for k, v in shapes.items()}
# 2. zones
pl = json.load(open(repo + '/RailwayGameApp/Resources/RealWorld/taiwan_places.json'))
zn = pl['zones']; cd = float(pl['cellDegrees']) / zn['cuts']; north, west = float(pl['north']), float(pl['west'])
lat = N - (np.arange(H) + 0.5) * (N - S) / H; lon = W + (np.arange(Wd) + 0.5) * (E - W) / Wd
R = np.floor((north - lat) / cd).astype(int); C = np.floor((lon - west) / cd).astype(int)
zones = {}
for name, runs in zn['layers'].items():
    cells = set()
    for r in runs:
        for i, p in enumerate(r['p']):
            if p * 2 >= zn['samples']: cells.add((r['r'], r['c'] + i))
    zones[name] = np.array([[(rr, cc) in cells for cc in C] for rr in R])
# 3. water grid
wj = json.load(open(repo + '/RailwayGameApp/Resources/RealWorld/taiwan_water.json'))
wcd = float(wj['cellDegrees']); wn, ww = float(wj['north']), float(wj['west'])
WR = np.floor((wn - lat) / wcd).astype(int); WCc = np.floor((lon - ww) / wcd).astype(int)
wrows = {}
for rec in wj['water']:
    row, col = rec[0], rec[1]; segs = []; i = 2; c = col
    while i < len(rec):
        segs.append((c, c + rec[i])); c += rec[i]
        if i + 1 < len(rec): c += rec[i + 1]
        i += 2
    wrows[row] = segs
water = np.array([[any(a <= cc < b for a, b in wrows.get(rr, [])) for cc in WCc] for rr in WR])
px_km2 = ((N - S) / H * 110.574) * ((E - W) / Wd * 111.320 * math.cos(math.radians((N + S) / 2)))
def km2(m): return round(float(m.sum()) * px_km2, 2)
tree, crop, built, wcw, grass = wc == 10, wc == 40, wc == 50, wc == 80, wc == 30
osm_green = osm['wood'] | osm['grass'] | osm['park'] | osm['wetland']
farmz = zones.get('farmland', np.zeros(wc.shape, bool)); parkz = zones.get('park', np.zeros(wc.shape, bool)); indz = zones.get('industrial', np.zeros(wc.shape, bool))
res = dict(box=[W, S, E, N], pixels=list(wc.shape), px_m2=round(px_km2 * 1e6, 1), area_km2=km2(np.ones(wc.shape, bool)),
    wc_km2={k: km2(wc == v) for k, v in dict(tree=10, shrub=20, grass=30, crop=40, built=50, bare=60, water=80, wetland=90).items()},
    osm_km2={k: km2(v) for k, v in osm.items()}, zones_km2={k: km2(v) for k, v in zones.items()}, water_grid_km2=km2(water),
    wc_tree_not_osm_green_km2=km2(tree & ~osm_green & ~water), wc_tree_in_osm_wood_pct=round(100 * float((tree & osm['wood']).sum()) / max(1, tree.sum()), 1),
    wc_crop_in_farm_zone_pct=round(100 * float((crop & farmz).sum()) / max(1, crop.sum()), 1),
    wc_crop_outside_any_zone_km2=km2(crop & ~farmz & ~parkz & ~indz & ~water),
    farm_zone_where_wc_built_km2=km2(farmz & built), farm_zone_where_wc_tree_km2=km2(farmz & tree),
    osm_wood_where_wc_not_tree_km2=km2(osm['wood'] & ~tree),
    wc_water_not_game_water_km2=km2(wcw & ~water), game_water_not_wc_water_km2=km2(water & ~wcw),
    unpainted_now_km2=km2(~osm_green & ~osm['sand'] & ~farmz & ~parkz & ~indz & ~water),
    unpainted_now_by_wc_km2={k: km2((wc == v) & ~osm_green & ~osm['sand'] & ~farmz & ~parkz & ~indz & ~water) for k, v in dict(tree=10, grass=30, crop=40, built=50, bare=60, water=80).items()})
json.dump(res, open(out + '.json', 'w'), indent=1); print(json.dumps(res, indent=1))
# images: WorldCover | current game data | where WorldCover would add something
COL = {10: (52, 120, 60), 20: (200, 170, 90), 30: (170, 200, 110), 40: (225, 205, 120), 50: (200, 90, 80), 60: (190, 190, 190), 80: (70, 130, 200), 90: (90, 170, 170)}
def blank(): return np.full(wc.shape + (3,), 246, np.uint8)
a = blank()
for k, c in COL.items(): a[wc == k] = c
b = blank(); b[farmz] = COL[40]; b[indz] = (160, 140, 180); b[osm['grass'] | parkz | osm['park']] = COL[30]; b[osm['wood']] = COL[10]; b[osm['wetland']] = COL[90]; b[osm['sand']] = (230, 220, 180); b[water] = COL[80]
c = blank(); c[(osm_green | farmz | parkz | indz | water)] = (225, 225, 225)
c[tree & ~osm_green & ~water] = (20, 150, 40); c[crop & ~farmz & ~parkz & ~indz & ~water] = (230, 160, 0)
c[farmz & built] = (220, 40, 40); c[wcw & ~water] = (40, 90, 230)
img = Image.new('RGB', (Wd * 3 + 40, H + 60), (255, 255, 255)); d = ImageDraw.Draw(img)
for i, (arr, t) in enumerate([(a, 'ESA WorldCover 2021 v200 (10 m)'), (b, 'Game now: OSM landcover+park, zones, water grid'), (c, 'Gaps: green=WC tree, no OSM green; orange=WC crop, no zone; red=farm zone on WC built; blue=WC water, game land')]):
    img.paste(Image.fromarray(arr), (i * (Wd + 20), 50)); d.text((i * (Wd + 20) + 4, 4), t[:95], fill=(0, 0, 0)); d.text((i * (Wd + 20) + 4, 20), t[95:], fill=(0, 0, 0))
img.save(out + '.png')
