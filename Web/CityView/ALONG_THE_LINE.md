# Procedural Tokyo in Along the Line

This folder is [jeantimex/tokyo](https://github.com/jeantimex/tokyo) at commit
`17c8bbe5a6c57c75fe504a58ac3fb16004a27573` (MIT, Copyright (c) 2026 Yong Su; `LICENSE`), copied whole
for the app's 3D city preview (ARCHITECTURE decision 152). Its own README is `UPSTREAM_README.md`.
The built page goes onto the game's website, `/city/` (decision 163; `tools/procedural-city/build_city_view.sh`),
and the app opens it there.

Every change is marked `Along the Line` in the code:

| File | Change |
| --- | --- |
| `tools/pipeline/taiwan.mjs` (new) | Overture buildings in place of PLATEAU's: usage from Overture's subtype and class, storeys estimated from the footprint where Overture has none; road outlines from the OpenStreetMap centrelines (PLATEAU has the right-of-way) |
| `tools/pipeline/config.mjs` | The `kaohsiung` area: `source: 'taiwan'`, a square of `half` metres round the origin, its own attribution; the `taichung` area (decision 161), where the TRA runs on a viaduct |
| `tools/pipeline/compile.mjs` | A Taiwanese area: flat ground, no PLATEAU, Overture's buildings, road outlines from the centrelines; keeps right (`roads.json` `rightHand`); Taiwan's clock in the manifest (`utcOffset`, `zone`) |
| `tools/pipeline/markings.mjs` | `rightHand`: lane symbols and stop lines on the right half; no 止まれ |
| `src/world/traffic.js` | Cars keep right where `roads.json` says `rightHand` |
| `src/world/signs.js` | Traditional Chinese fonts first |
| `src/main.js` | The settings panel in Chinese when the page is (`GUI_ZH`); the city switch keeps the page's other parameters (the app's lighter settings) and drops only the camera; Kaohsiung when no area, or one other than Kaohsiung and Taichung, is asked for (the original opens Tokyo, which the website does not have); the clock in the area's time zone (the manifest's `utcOffset`); tells the railways a Taiwanese area (the manifest's `zone`); the credits as one line, as on the game's real-world maps, the 3D city's author first (`3D 城市：© Yong Su`), and the loading steps, in Traditional Chinese when the web view's language is Chinese |
| `src/world/rails.js` | Passes the train options on to `Trains` |
| `src/world/trains.js` | In a Taiwanese area every heavy-rail line runs the TRA's EMU3000 (the EMU900, still the original's box with no model, is out of the rotation: the owner's call); cars drawn with the Meshy models of `public/models/trains/` (`tools/meshy`, decision 161) when they are there, as boxes otherwise |
| `public/models/trains/` (new) | The Meshy train models and their `index.json` (file, the axis the cab faces) |
| `src/world/atmosphere.js` | The environment map is baked 10 m above the ground: from 0 m, at Kaohsiung's latitude, the sky gives NaNs and the city goes black |
| `public/boot.js` (new) | The scripts `index.html` had inline (the city's name on the loading screen, Kaohsiung when no area or an unknown one is asked for, the website link's language, and no website link in the game, `?app=1`; the idle callbacks' deadline), so that the website's Content-Security-Policy can forbid inline scripts |
| `index.html` | The settings panel (lil-gui's variables) and the info panel in the game's look; `viewport-fit=cover`, so the panel and the switch keep clear of the notch. The loading screen is the game's: its logo (`public/assets/ui/brand-mark.png`, the app's `BrandMark`), 沿線 / Along the Line and the website's colours, and the area's Chinese name; the game's website (官網, bottom right, opened by the app in Safari) where the GitHub link was; the credits at the bottom in the middle, on the same light band as the real-world maps' |

The raw data (`data/raw/`), the compiled tiles (`public/tiles/`), the textures (`public/textures/`) and
`node_modules/` are not committed (`.gitignore`); `tools/procedural-city/README.md` has the commands.
