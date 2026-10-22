# Taiwan's temples for the 3D map

Decision 331 (`docs/decisions/331.md`). `build_temples.py` reads the owner's
geo-scene reference's temples file
(`a91453/railway-reference-private`,
`Railway/geo-scene-reference-clean/source/public/religion/temples.pmtiles`)
and writes the app's `RailwayGameApp/Resources/BaseMap/taiwan_temples.json`:
each temple's latitude and longitude in 1e-5 degrees and its size, which is
2 for one of the hundred religious events' temples or a listed monument, 0
for a Tudigong shrine and 1 for the rest. The game reads it with
`RealTemples` (GamePresentation).

The script uses only Python's standard library (PMTiles v3 and Mapbox vector
tiles are decoded in it). Run it from the repository:

```sh
python3 -I tools/temples/build_temples.py \
  /path/to/railway-reference-private/Railway/geo-scene-reference-clean/source/public/religion/temples.pmtiles \
  RailwayGameApp/Resources/BaseMap/taiwan_temples.json
```

The run of 2026-10-22 wrote 19,201 temples (276 large, 1,378 shrines):
12,394 from the Ministry of the Interior's register, 6,702 from
OpenStreetMap and 105 from the Bureau of Cultural Heritage. Each point's
source is credited in the app (`DataSourceCredits`, id `temples`):
the Open Government Data License for the ministry's and the bureau's, the
ODbL for OpenStreetMap's.
