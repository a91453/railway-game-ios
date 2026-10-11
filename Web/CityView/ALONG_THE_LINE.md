# Procedural Tokyo in Along the Line

This folder is [jeantimex/tokyo](https://github.com/jeantimex/tokyo) at commit
`17c8bbe5a6c57c75fe504a58ac3fb16004a27573` (MIT, Copyright (c) 2026 Yong Su; `LICENSE`), copied whole
for the app's 3D city preview (ARCHITECTURE decision 152). Its own README is `UPSTREAM_README.md`.
The built page goes into `RailwayGameApp/Resources/CityView/` (`tools/procedural-city/build_city_view.sh`).

Every change is marked `Along the Line` in the code:

| File | Change |
| --- | --- |
| `tools/pipeline/taiwan.mjs` (new) | Overture buildings in place of PLATEAU's: usage from Overture's subtype and class, storeys estimated from the footprint where Overture has none; road outlines from the OpenStreetMap centrelines (PLATEAU has the right-of-way) |
| `tools/pipeline/config.mjs` | The `kaohsiung` area: `source: 'taiwan'`, a square of `half` metres round the origin, its own attribution |
| `tools/pipeline/compile.mjs` | A Taiwanese area: flat ground, no PLATEAU, Overture's buildings, road outlines from the centrelines; keeps right (`roads.json` `rightHand`); Taiwan's clock in the manifest (`utcOffset`, `zone`) |
| `tools/pipeline/markings.mjs` | `rightHand`: lane symbols and stop lines on the right half; no 止まれ |
| `src/world/traffic.js` | Cars keep right where `roads.json` says `rightHand` |
| `src/world/signs.js` | Traditional Chinese fonts first |
| `src/main.js` | The clock in the area's time zone (the manifest's `utcOffset`) |
| `src/world/atmosphere.js` | The environment map is baked 10 m above the ground: from 0 m, at Kaohsiung's latitude, the sky gives NaNs and the city goes black |
| `index.html` | The loading screen says 沿線 instead of 東京 |

The raw data (`data/raw/`), the compiled tiles (`public/tiles/`), the textures (`public/textures/`) and
`node_modules/` are not committed (`.gitignore`); `tools/procedural-city/README.md` has the commands.
