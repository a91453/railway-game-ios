# The 3D city view and its data

The app's 3D city preview (ARCHITECTURE decision 152) is the web page of
[Procedural Tokyo](https://github.com/jeantimex/tokyo) (MIT), copied into `Web/CityView/` and adapted to
Taiwan (`Web/CityView/ALONG_THE_LINE.md`). The app bundles the built page as
`RailwayGameApp/Resources/CityView/`. The research that led to it: `docs/research/PROCEDURAL_CITY_STUDY.md`.

## Rebuilding the bundled page

Needs Node 22, Python 3 with `pip install duckdb osmium`, and the network (Overture's S3 bucket, osmtoday.com,
Poly Haven, npm). From the repository root:

```sh
(cd Web/CityView && npm ci && node tools/assets/fetch_textures.mjs)   # libraries; CC0 textures, 14 MB
curl -LO https://osmtoday.com/asia/taiwan.pbf                          # some 350 MB
python3 tools/procedural-city/taiwan_area.py buildings 2026-09-23.1 kaohsiung Web/CityView/data/raw/kaohsiung
python3 tools/procedural-city/taiwan_area.py osm taiwan.pbf kaohsiung Web/CityView/data/raw/kaohsiung
python3 tools/procedural-city/taiwan_area.py buildings 2026-09-23.1 taichung Web/CityView/data/raw/taichung
python3 tools/procedural-city/taiwan_area.py osm taiwan.pbf taichung Web/CityView/data/raw/taichung
tools/procedural-city/build_city_view.sh
```

- `taiwan_area.py buildings`: Overture's buildings round the area (about 30 s).
- `taiwan_area.py osm`: the area's roads, railways, green space, crossings, signals, shops and street furniture
  out of the Taiwan extract, in the shape of the Overpass answers Tokyo's `fetch.mjs` asks for (about 2½ min).
- `build_city_view.sh`: compiles the tiles of both areas (`Web/CityView/tools/pipeline/compile.mjs --area=kaohsiung --no-ads`,
  a few seconds), shrinks the textures to 512 px (`shrink_textures.mjs`), builds the page with Vite into
  `RailwayGameApp/Resources/CityView/`, and writes the notices of the bundled libraries
  (`notices.mjs` → `RailwayGameApp/Resources/Licenses/CityView-NOTICES.md`).

2026-10-11 (Overture `2026-09-23.1`, osmtoday's Taiwan extract downloaded on 2026-10-10): 1,212 buildings in the area (1,179 of
them without storeys in Overture, so estimated), 70.2 km of road, 147 shop signs, 54 tiles of 256 m (2.0 MB);
the whole page 12 MB.

Taichung Station (decision 161; Overture `2026-09-23.1`, osmtoday's extract of 2026-10-11): 1,404 buildings in the
area (1,229 estimated), 14 elevated railway lines (the TRA viaduct), 508 shop signs, 41 tiles (2.1 MB); Kaohsiung's
tiles came out byte for byte the same from the newer extract. The whole page 14 MB.

The trains' Meshy models (`Web/CityView/public/models/trains/`) are made with `tools/meshy/` (its README).

## Trying it in a browser

Serve `RailwayGameApp/Resources/CityView/` over HTTP (`python3 -m http.server`) and open
`/index.html?area=kaohsiung&radius=400&clouds=0&birds=0&traffic=0`, the page the app opens. A `file:` URL does
not work: the page needs a web origin for its modules, its worker and its tiles.

## Licences

The code: Procedural Tokyo (MIT) and the libraries its page bundles (MIT, Zlib, ISC), whose notices come with the
app. The textures: Poly Haven, CC0. The data: Overture Maps buildings (ODbL 1.0; OpenStreetMap ODbL,
Shi et al. CC BY 4.0) and OpenStreetMap (ODbL 1.0); the compiled tiles are a derived database under the ODbL,
credited on the data sources screen and available from this repository.

## Measuring (`extract_patch.py`, `measure_patch.mjs`)

The two scripts of the study (#323): Tokyo's mesher on 1 km² of Kaohsiung and Taipei, to size the iOS budget.
Their commands are in their own headers.
