# TOKYO RUSH mirror: a technical study for the 3D city (P0–P3)

Source: `https://github.com/galbenyosef/taipei-rush-tokyo`, cloned `--depth 1`
(HEAD `aa52d2b8b9d70eecd3519c9a46ffc252783abfc9`, 2026-10-27), by session_01YGNNunmjyoeMSdTvYbyZJm
for decisions 455–456 (2026-10-28). The mirror has no licence: read for ideas only, nothing copied.
I only read files. I ran no scripts, and the one parse I did used `python3 -I`.
Paths below are relative to `readable/tokyo/assets/` in that clone
(the prettified copy of `tokyo/assets/`) unless they start with `/`.
Line numbers refer to the `.pretty.js` files.

## 0. Licence: what the repository actually holds

- **There is no LICENSE, COPYING or NOTICE file for the game, and the repository has none of its own.**
  `README.md` calls it an "offline mirror" of the deploy at
  `https://www.taipei-rush.app/tokyo/`. It also says that "no public source repo exists for the game"
  (README §0.4, lines ~229–237). I treat the game code, data and art as proprietary.
- Licence files that do exist:
  - `tools/vendor/prettier/LICENSE`: MIT, "Copyright © James Long and contributors". This is the
    mirror's own formatting tool, not the game.
  - `tools/vendor/prettier/THIRD-PARTY-NOTICES.md`: the bundled dependencies of Prettier
    (MIT, ISC, BSD-3-Clause, Apache-2.0, BSD-2-Clause, BlueOak-1.0.0).
  - `avatars/manifest.json`, field `license`: "Microsoft Rocketbox Avatar Library — MIT License,
    Copyright (c) 2020 Microsoft (see CREDITS.md / LICENSE-ROCKETBOX.txt)". **Neither `CREDITS.md`
    nor `LICENSE-ROCKETBOX.txt` is in the mirror.**
  - `notice-*.js` is not a licence. It is a 22-line sessionStorage helper.
  - README line 15 says three.js r186 is bundled (`three-*.js`), but no three.js licence text ships.
- Conclusion: read it for ideas only. Copy no code, data, sign text, palettes or art. Nothing below
  proposes copying any of it.

## 1. How it renders the city

### 1.1 Assets: fully procedural city, no models or textures for buildings
- The tree has 46 `.glb` files, and all of them are Rocketbox avatars (`avatars/`). The city has no
  model files and no texture images. Building atlases and signs are painted on canvases at runtime.
  For example, `region-tokyo-sites-kit-*.pretty.js:7-50` uses `fillText`, and the facade atlas is
  `Yoe(u, 51741)` at `region-tokyo-55J_WESF.pretty.js:34952`.
- The generic city generator is the class `ece` at `region-tokyo-55J_WESF.pretty.js:32212–34679`.
  Its methods include `storefront` 32442, `awning` 32932, `flatRoof` 33025, `rooftop` 33064,
  `zakkyo` 33447, `tenantStack` 33547, `wallBoards` 33648, `office` 33830, `mansion` 34101,
  `shitamachi` 34197, `kura` 34338 and `depato` 34439.

### 1.2 Tile streaming: 256 m tiles in two tiers
- Grid: 256 m tiles in a 32 × 32 grid from (-2560, -2560), which covers 8.192 km × 8.192 km.
  See `fc()` and `cc/lc/uc` at `region-tokyo-55J_WESF.pretty.js:19600–19622`.
- The tiers are set up in `JNe()` (`region-tokyo-55J_WESF.pretty.js:139269–139470`):
  - **t1 tier (ground, roads and far "lots")**
    - Radius: `drawDistance + 180`. On mobile it is at least 600 m, or 450 m on low-memory devices
      (lines 139276–139283).
    - Drop margin 300 m, after 20 s (139383–139386). Pop radius `drawDistance*0.8` (139467).
  - **t2 tier (full buildings)**
    - Radius: `UNe[level]*1.2 + 110`, with `UNe` = {low 170, medium 220, high 260, ultra 380}
      (139264). That gives 314 / 374 / 422 / 566 m.
    - Drop margin 150 m, after 10 s. Look-ahead at 40 km/h (`WNe`, 139265).
    - Request radius `max(60, r-110)` (139470).
  - Tile builds are generator functions sliced with a 1.5 ms budget (`GNe`, 139266; `C()` at 139303).
- Quality presets live at `engine-wUBYs8Z3.pretty.js:615–727`.
  - drawDistance: low 420, medium 650, high 900, ultra 1300.
  - Mobile overrides: medium 560, high 700.
  - Under load the far plane shrinks by 15 % × `shed` (5265–5270, `applyShedFar` 5480–5486).

### 1.3 Near buildings (t2): one merged mesh per tile
- Each 256 m tile builds every lot into one `Bf(16384)` builder with four streams: body, sign,
  screen and ticker (31982–31992). Building happens in `cce()` → `C()` at 35081–35195.
- The result is a single mesh `tokyo-t2-<tile>` with one atlas material, `castShadow = true` and
  `matrixAutoUpdate = false` (35136–35147).
- Signs are UV cells in a shared, repaintable sign atlas, patched in place by `w()` (35168–35221).
- Colliders are capped at 1500 per tile (35118–35123).
- There is **no instancing** for buildings or their small details. Air conditioners, tanks,
  penthouses, awnings and lanterns are all merged into the tile mesh.

### 1.4 Far city (t1 "lots"): one box per lot, in a pooled BatchedMesh, no shadows
- `u$()` (`region-tokyo-55J_WESF.pretty.js:136031–136130`) draws one coloured box per lot, weighted
  by palettes per lot type.
  - It adds up to 6 lit window bands (quads) every 2 floors. 35 % of the bands are lit on
    offices/zakkyo, 55 % on others (`d$()`, 136132–136143).
  - Towers get a podium plus a set-back shaft. Low wooden houses get a pitched roof (`pNe`).
- Storage: `rr` "PooledBatch" (`region-tokyo-55J_WESF.pretty.js:1104–1270`).
  - It is a three.js `BatchedMesh` with **one geometry slot per tile**, and a vertex/index allocator
    with free lists.
  - Each slot has its own bounding box and sphere, so BatchedMesh culls each tile and draws all far
    tiles in one multi-draw.
  - Settings: `castShadow = false`, `receiveShadow = true`, `frustumCulled = false` (the mesh as a
    whole).
- Pools: `tokyo-t1-ground`, `tokyo-t1-lots` and `tokyo-t1-road` (139532–139552).
- The far lot box is hidden while that tile's t2 mesh is resident (`ne.setVisible(a, !se(t))`,
  139420; `shown`/`dropped` at 139446–139456). The renderer skips BatchedMeshes with
  `_multiDrawCount === 0` (`engine:5489–5503`).
- Edge skyline outside the play area: "far buildings" and props are built into one merged geometry
  and cut into 200 m tiles (`dg`, `world-CAmHK742.pretty.js:26548–26637`).
  - The view `fg` (26639–26709) rewrites the index buffer with the visible tiles only.
  - "detail" tiles are drawn only within `detailDist` (380 m; 28642).
  - There is a separate `farScene` (`B.scene`, 28651–28662).

### 1.5 Instancing that does exist (trees and shrubs)
- Trees and shrubs use `InstancedMesh` with the helper `pg` (`world-CAmHK742.pretty.js:26710–26810`):
  - instances are bucketed into 100 m grid cells, each with an AABB;
  - each frame, a predicate (frustum/distance) marks which cells are visible;
  - the matrices and colours of visible cells are copied together into the instance buffer, and
    `count` is set, with an upper cap (`maxWithin(115 m)` for near trees, 95 m for shrubs;
    28776–28824).
- Shrub spacing is `7.5/sqrt(propDensity)` m (28817).

### 1.6 Landmark sites: four LOD tiers with budgets
- Tiers per site: proxy (far), mid, near and interior (`af`/`rf`, `world-CAmHK742.pretty.js:14729–14800`).
- Distances (`mt`, 1065–1097):
  - mid builds at 260 m and drops at 305 m; near builds at 130 m and drops at 160 m;
  - interior: desktop 35/47 m, mobile 25/35 m;
  - multipliers: quality ×0.6/0.8/1/1.3, mobile ×0.6, hero ×1.25, drop factor 1.12.
- LRU caps on mobile: near 4 (max 6), mid 16. Near triangle cap 45 k on mobile.
- Per-tier budgets (`ft`, 1045–1056): high near 6 calls / 60 k tris, mid 2 / 10 k; low near 3 / 25 k.
  Proxy 25 k/12 k tris. Cluster radius 130 m.

### 1.7 Shadows (relevant to P1)
- There is one directional light with one ortho shadow map (no cascades) (`Zt`/`Qt`,
  `world-CAmHK742.pretty.js:27711–27766`).
  - Half extent 55 / 70 / 90 m (medium / high / ultra).
  - Map size: desktop 1024/2048/4096; **mobile 1024** for medium and high (`engine:699–723`).
    Low quality has no shadows.
  - The centre is placed 35 % of the extent ahead of the player along the view direction, and
    **snapped to shadow texels**. Near/far are refit to the sun elevation and terrain each frame.
  - `bias -3.5e-4`, `normalBias 0.045`, `radius` 1.6/2.2/2.6.
- Updates are throttled (27845–27870): `autoUpdate = false`, re-rendered at most every 1/30 s on
  medium (and on high when a load metric is < 7), 1/60 s on ultra.
  - Shadows are off when `shadowStrength` is under a threshold, e.g. at night unless moonlit.
  - Under heavy load (`shed > 0.5`) the shadow pass is skipped every other frame (`engine:5521–5522`).
- What casts shadows:
  - near t2 tile meshes cast;
  - far lot pools, environment props and the t1 ground do not cast (they receive only);
  - a 4×4 placeholder map is used before the real one exists (17306–17330).

### 1.8 Small-detail pools and pixel-size culling (relevant to P2)
- **There is no separate pool for small details**, and no instancing for them. They are merged per
  tile and limited by a quality knob, `detail = max(0.35, propDensity)`, where propDensity is
  low 0.45, medium 0.7, high/ultra 1 (34993).
  - Water tanks need `detail ≥ 0.5` (`$se`, 31981), so **low-quality phones get no roof tanks**.
  - Side-wall AC units and the roof AC need `detail > 0`.
  - `signDensity` is 0.75 on low/mobile (34994).
- **No pixel-size or screen-size culling was found** in the engine, world or region chunks. Searches
  for screenSize, pixelSize, projected and minPixel found only a shader early-out
  (`world:23269`, `rPx < 1.5`). Detail selection is by distance tier only.

## 2. Region kits

### 2.1 Generic lots (every district): types, widths, floors
- Lot types (`uu`, `region-tokyo-55J_WESF.pretty.js:25766`): OFFICE, ZAKKYO (mixed-tenant), MANSION,
  SHITAMACHI (low wooden), KURA (storehouse), DEPATO (department store).
- **Frontage widths per type** (`wae`, 25774–25781), in m:

  | Type | Frontage (m) |
  |---|---|
  | OFFICE | 24–64 |
  | ZAKKYO | 5–8.5 |
  | MANSION | 14–30 |
  | SHITAMACHI | 4.5–8 |
  | KURA | 6–11 |
  | DEPATO | 36–70 |

  Lots inside a block are 6–11 m (or 16–30 m for a mansion). The last lot absorbs any leftover under
  `max(4, min*0.6)` (`yu()`, 26032–26061).
- Blocks are split as follows (`yu`, 26019–26061):
  - blocks ≤ 52 m deep are cut in two at 42–58 %;
  - deeper blocks get street strips 15–24 m deep, and the middle is cut every ~20 m.
- Department stores appear with a per-district probability on boulevard blocks between 30–90 and
  30–110 m (`Eae`).
- Floors and heights per type (`Pae`, 26118–26172):
  - ZAKKYO: 4–10 floors (+1 on a boulevard, +0–2 in Akihabara), ground floor 3.8–4.3 m, upper floors
    3.15–3.5 m, parapet 0.9 m;
  - SHITAMACHI: 2–3 floors, ground 2.9–3.2 m;
  - lots off the street get ×0.75 floors;
  - the cap is 160 m.
- Exposed side walls (`Iae`, 26173–26210): for each side not on a street, 1.5 m samples measure
  the neighbour's height (`cover[]`).
  - Only the wall above the neighbour is drawn (`covered`/`sideFace`, 32399–32432).
  - That exposed wall gets windows, or blank concrete with up to 2 AC units (0.8 × 0.32 × 0.62 m)
    chosen by a hash.
- **Corner lots**: a lot has a `street` bitmask over 4 sides, and a `big` mask for boulevard sides.
  `zakkyo` runs a full `storefront` on **every street side**
  (`for g in 0..3 if (street>>g)&1`, 33478–33505). A corner lot therefore gets two shop fronts.
  The main side (`streetSides` sorted by boulevard, then by length) receives the sign stack.

### 2.2 Storefront subdivision and street-level dressing (`storefront`, 32442–32762)
- Units: the frontage is cut into `round(len / (50 % 4.2 m | 50 % 6.5 m))` units (32501). Mapped
  POIs carve their own unit, at least 2.4 m. An optional lobby entrance of 1.5–2.0 m sits at one end.
- Closed or vacant units: chance 5 % on a boulevard or in Ginza, Marunouchi and Nihonbashi, else
  `0.07 + 0.12*(1-shops)` (32492).
  - A closed unit gets a shutter, with 15 % a small wicket (潜り戸) variant.
  - 25 % of closed units get a "vacant" plate.
- Trade choice: the genre is picked per district (`tse`), and up to 3 rerolls avoid repeating the
  neighbour's trade (32568–32570).
  - Konbini: `max(2, round(len/3.3))` glass bays with the door in the middle (32584).
  - Other shops: `round(len/4.2)` bays with one glass-door bay (32604–32626).
- Fascia: height `min(0.9, (w-0.2)/4)`. It is a sign-atlas cell with a frame, and a brand or generic
  word picked from the trade. Its glow level depends on trade and district neon (32628–32680).
- Street-level extras, chosen by trade:
  - eateries: noren with 30 % chance (always for traditional ones), up to 2.4 m wide (32697–32727);
  - trades with the `chochin` genre: paper lanterns with 85 % chance, a second one when the unit is
    wider than 4 m (32738–32755);
  - otherwise, on non-food shops, **an awning only 30 % of the time** (32757–32760). It is 1.1 m
    deep with a 0.45 m drop, from a weighted 6-colour palette `kae` (25871–25877).
- Trade data: 93 trades carry a `genres` list of sign styles (`region-tokyo-55J_WESF.pretty.js:5411–7349`).
  Most common: `window` 50, `kanban-h` 35, `pop` 23, `noren` 19, `led` 18, `tenant-stack` 17,
  `kanban-v` 15, `brass-plate` 14, `a-board` 14, `awning` 10.

### 2.3 Upper-floor signs: the most "station-front" element
- `tenantStack` (33547–33646): a **vertical stack of per-floor tenant panels**.
  - One panel per floor, 0.8–1.05 m deep, on a steel frame near one end of the main facade.
  - It is placed on zakkyo buildings of 3+ floors with chance `0.62*signDensity + 0.08` (33500).
  - It covers 70–100 % of the floors. 14 % of panels read "tenant wanted" (テナント募集).
  - Small floor tags ("2F", "3F") go under each panel.
- Otherwise `wallBoards` (33648–33691): horizontal boards on the facade, 3.6–5.2 m wide, on 60 % of
  the upper floors. Used with chance < 0.9.
- Per-floor window type is chosen once per building (33455–33466): Z-windows 55 %, ribbon 25 %,
  plain 20 %. 18 % of floors are "LETTER" floors, with words on the glass (窓文字).
- Akihabara: extra multi-storey signs on zakkyo buildings of 5+ floors with 65 % chance (33507–33511).

### 2.4 Rooftops (`rooftop`, 33064–33175), on roofs at least 4 × 4 m
- 75 %: a concrete stair/lift penthouse, half-size 1.3–2.3 m, 2.6 m tall.
- 65 %: a water tank box, half-size 1–1.6 × 0.8–1.3 m, 1.9 m tall, white or grey (only when
  detail ≥ 0.5).
- 0–2 AC boxes of 0.84 × 0.32 × 0.65 m.
- Rooftop billboard band:
  - chance `0.25 + 0.4*district.neon`, on facades longer than 6 m;
  - 4–10 m wide, height = width/8, 1.2 m above the roof, set 1.2 m back;
  - on two steel posts;
  - text is a chain-store word (65 %) or a generic headline.
- All boxes are placed at random points via `d()`, inset 0.4 m.

### 2.5 Variety, seeds and palettes
- Each lot gets a 32-bit seed from `ge(dataset.seed, "tokyo-lots", blockId)` and then `ie` RNG
  draws (25995, 26074). Building recipes reseed with `t.seed ^ 1540483477` (32361).
- FNV-1a (`Wf`, 32056) hashes sign keys for style choices.
- Weighted wall palettes per type: `du` zakkyo 12 colours, `fu` mansion 9, `pu`/`mu` office,
  `hu` shitamachi 7, `_u` depato 4, `gu`/`Oae` roofs (25797–25869).
- Per-district style knobs: `zakkyo`, `wooden`, `office`, `towers`, `floors`, `neon`, `old`,
  `shops`.
- Wall tint is jittered ×0.93 on side walls (`Uf`). The facade shader adds world-space weathering
  and per-cell hashes so repeated tiles do not form a pattern (`world:3364–3420`).
- Shopfront glass uses **shader-only interior mapping**: the view ray passes through a box "room"
  per glass cell, with SDF people drawn in it, and no geometry (`world:3006–3060`).

### 2.6 Hand-placed district kits (`region-tokyo-d-*`, 13 files; `region-tokyo-sites-kit` + 15 `region-tokyo-site-*`)
- District files (1,900–5,963 lines each) hold **per-building data records written by hand** on
  real streets, plus their own procedural drawing functions.
- Example from Kanda: `region-tokyo-d-kanda-*.pretty.js`.
  - The record schema is applied by `it()` (1893–1915) and listed in the table starting at 1916.
  - Fields: `a/b` (span along the street), `floors`, `gh` 4 m, `fh` 3.3 m, `wall`, `wallKind`,
    `win`, `winWords`, `shop`, `front` (glass/open/lattice), `fascia`, `bands`, `vsign`, `vsign2`,
    `roofBoard`, `awning`, `noren`, `lanterns`, `hours`, `corner`, `coverL/R/B`.
  - Drawing: `et()` (1577–1737) and `tt()` (1738–1856).
    - Window bays: `round(L/3.4)`; shopfront bays: `round(L/3)`.
    - Vertical sign up to 14 m on buildings of 5+ floors (7.5 m otherwise).
    - Second vertical sign at the far end.
    - Roof box with 55 % chance.
    - Rooftop board 2.4 m tall on 2 posts.
    - Lantern row under the fascia; noren up to 2.4 m wide or 45 % of the frontage.
    - Shutters outside opening hours (`nt()`, 1857–1871).
- Measured over the files that use `a/b` records (python `-I` parse):

  | District | Buildings | Width min / median / max (m) | Median floors | Max floors |
  |---|---|---|---|---|
  | Kanda | 40 | 6.6 / 8.5 / 42.4 | 5 | 9 |
  | Hongo | 47 | 6.6 / 10.9 / 37.6 | 3 | 11 |
  | Suidobashi | 53 | 5.5 / 8.6 / 27.6 | 4 | 10 |

  - Corner records: Kanda 5, Hongo 15, Suidobashi 17.
  - Akihabara has 12 corners and 21 vertical signs; Roppongi has 14 corners.
- Other districts (Akihabara, Ginza, Shimbashi, Ueno, Marunouchi, Nihonbashi, Ameyoko, Asakusa,
  Roppongi) use their own record shapes and function sets. Each has its own copy of the primitive
  helpers (box, wall, quad and others).
- `region-tokyo-sites-kit` and `sites-kit` hold shared recipes for 15 real "sites":
  - the paint palette `L`, 19 colours (1015–1034);
  - a generic mid-rise recipe `R()` (1036–1216): ground floor 4.2 m, floors 3.1 m,
    bays `round(w/3.2)`, window modes grid/band/balcony/none, side-wall windows on exposed sides;
  - an AC unit helper `z()` (1241–1251): 0.8 × 0.6 × 0.3 m, under 1 in 5 bays, 3 on the roof;
  - a roof tank, a cylinder of r 0.9 m and 2.2 m tall, only at quality `high`;
  - an open shop front with a shallow lit "room" box 2.4 m deep (`B()`, 1252–1276);
  - sash and lattice doors (`V()`);
  - figure-recolour tables (`sites-kit-*:11-63`);
  - canvas sign painters (`region-tokyo-sites-kit:4-145`).
- Model files used by all region kits: **0**. Everything is procedural geometry plus runtime canvas
  textures.

## 3. Our station-front shops compared (railway-game-ios `main` e818ff43)

Read: `Sources/GamePresentation/Map3DShopStreet.swift`, `Map3DFrontage.swift`
(`addTownHouse` 430–502, `addFarTownHouse` 414–424), `Map3DBuildings.swift`
(`addFrontDetail` 480–521, `addStreetLevel` 529–556, `addRoofPlant` 589–602),
`Map3DRealBuildings.swift` (140–289), `Map3DPlacedBuildingKits.swift` and
`Map3DCamera.swift` 173–215.

What we already have:

| Topic | Ours | Tokyo |
|---|---|---|
| Station-front shop width | fixed 7.5 m frontage, 8.1 m pitch, 4–12 shops within 150 m, 1–3 floors × 3.2 m (`Map3DShopStreet` 25–38, 167–245) | 4.2 or 6.5 m units cut from lots of 5–8.5 m (zakkyo) |
| Street-house width | 4.4–6.6 m houses, flats 8–14 m, 9–15 m deep, 33–45 % gaps (`layFrontage` 280–322) | 4.5–8 m (shitamachi), 5–8.5 m (zakkyo) |
| Arcade 騎樓 | 80 % of shop houses, 3.64 m deep, pillars, parked scooters (`addTownHouse` 437, `addStreetLevel` 532–539) | none (Japanese streets have none) |
| Shop ground floor | texture bays of 5.4 m from 5 shop pictures or a shutter (`Map3DSurface.shops`) | per-unit glass/door bays plus a shader interior; 5–19 % closed shutters |
| Fascia / board | shop street: one coloured board with a word (`Map3DSign` .across); street houses: none apart from the texture | a fascia on every unit, plus a sub-label |
| Blade/vertical sign | one per shop house, 70 % chance, 2.4/3.2 m (`addFrontDetail` 514–520) | a stack of per-floor tenant panels (62 %), wall boards per floor, vertical signs up to 14 m |
| Awning | **every** shop house gets the counter, 3 crates and an awning (`addStreetLevel` 543–555); shop street: 7-stripe awning on every shop | awning only on 30 % of non-food shops; noren / lanterns by trade; many have none |
| Upper floors | tin window awnings on 50 % of floors, balconies with washing, AC under windows | window type per building, 18 % lettered floors; AC on exposed side walls |
| Roofs | tank 75 % (cylinder near, box far) or 頂樓加蓋 17 % (`addTownHouse` 474–501); blocks: stair house plus 1–3 plant boxes, near only | penthouse 75 %, tank 65 %, AC 0–2, rooftop billboard band 25–65 % |
| Rooftop sign | only the tallest station-front shop (`Map3DShopStreet` 228–242); real buildings: `addRealAds` near stations | any street-facing building, chance scaled by district neon |
| Corner lots | **none**: a house fronts one road; its flanks are always blank plaster (`addTownHouse` 455–462; `addFarTownHouse` 423) | a storefront on every street side; exposed side walls get windows and AC |
| Side walls above neighbours | always plaster | windows or AC above the neighbour's measured height |
| Far LOD | one box per house with painted windows (`addFarTownHouse`) | one box per lot plus up to 6 lit window bands, in a per-tile BatchedMesh slot |

What the Tokyo kits do that we lack, all cheap:

- **Signs that read per floor.** Tokyo stacks panels floor by floor. We put one sign at the ground
  floor.
- **Corner shops** with two lit shop fronts.
- **Variety in street-level dressing by trade**, including a share of closed shutters. Every one of
  our shops has the same counter, crate and awning set.
- **Rooftop billboards** on ordinary street buildings.
- **Treatment of exposed side walls.**

## 4. Proposals (at most 3; no new GLB, no interiors, no copied signs or words)

Ranked by recognisability for the cost on a phone.

1. **Per-floor sign stack on station-front shop houses** (Taiwan's wall of signs (招牌牆), the
   counterpart of Tokyo's `tenantStack` and `wallBoards`).
   - Where: shop houses on primary or secondary roads within about 150 m of a station
     (`shopReach`), with floors ≥ 3, about half of them, and only on the main front.
   - What: one board per upper floor, either as a vertical stack of panels at one end or as
     horizontal boards 3–4 m wide.
   - Words: drawn from our own `Map3DSignAtlas` words (`streetWords`, plus clinic and cram-school
     words we already own or add as our own text). Some floors stay unlit or show a "for rent"
     board.
   - Cost: 1 box plus 1–2 `Map3DSign` quads per floor, in the near/close target only. That is
     about 20–40 triangles per house and no new draw calls, if the signs share the existing
     sign-atlas pass.
   - Functions touched: `addFrontDetail` (Map3DBuildings.swift 480–521) returns the extra signs;
     `bladeSigns` / `Map3DSignPlacement`; `addTownHouse` passes `floors` and a near-station flag;
     optionally `Map3DShopStreet.shop` for `tall` shops.

2. **Corner shop houses: a second shop front on the flank that faces a road.**
   - Where: in `layFrontage`, mark a house whose end wall lies within `road.half + 1 m` of another
     fronted piece (the same test `fits` already does in reverse).
   - What: in `addTownHouse`, swap `flankPaint` on that side from plaster to the ground-floor shop
     bays and the upper-floor windows. Optionally add a second blade sign at the corner.
     `addFarTownHouse` paints the flank with windows too.
   - Cost: **no extra triangles**, because the quads already exist and only the paint changes; a
     possible sign adds about 12 triangles.
   - Functions touched: `layFrontage` (a new field on `LaidFrontage.houses`), `addTownHouse`,
     `addFarTownHouse` (Map3DFrontage.swift) and `addFrontDetail`.
   - Variant at the same cost: paint side walls that rise above a lower neighbour with
     `homeWindows`/`flatWindows` instead of plaster (Tokyo's `cover[]` idea).
     - Our frontage already knows its neighbours in each run; a gap or a shorter neighbour means an
       exposed wall.

3. **Street-level dressing by trade instead of the same counter, crates and awning everywhere.**
   - What: tie the dressing to the shop's sign word or surface.
     - Eateries: counter and stools, as now.
     - Retail: awning only, from `shopAwnings`, about 40 %, with no crates.
     - Some: nothing.
     - 10–15 % of units: a closed shutter (`.shutter` paint, no props), more off the busy roads.
     - The awning takes the board's colour so shop and sign read as one.
   - In the station-front row (`Map3DShopStreet.shop`), split some 7.5 m slots into two narrow
     units of about 3.6 m. Each unit gets its own colour lane and board; the triangle budget is
     unchanged.
   - Cost: **fewer** triangles on average, because crates and counters are dropped on most units.
   - Functions touched: `addStreetLevel` and `addFrontDetail` (Map3DBuildings.swift),
     `addTownHouse` (it passes the shop surface or word), and `Map3DShopStreet.shop` / `shopColour`.

Not proposed, for the record:
- Tokyo's shader interior mapping (`world:3006–3060`). It is an interior, even if fake, and it is
  copyrighted code.
- Its hand-written district records.
- Any of its palettes or words.

## 5. Notes for P0–P2 (factual, from §1)

- **P0 (far city):**
  - Tokyo does **not** instance the far boxes. It merges one box per lot per 256 m tile and keeps
    each tile as one slot of a pooled BatchedMesh with its own bounds. That gives one multi-draw
    for all far tiles, per-tile culling, no shadow casting, and the far tile is hidden once its
    near tile is ready.
  - The closest instancing analogue is `pg` for trees: 100 m cells, visible cells compacted into
    one instance buffer with an upper count.
- **P1 (sun shadow):**
  - One 1024² map on mobile covering ±55–70 m.
  - The centre is shifted 35 % ahead of the view and texel-snapped; near/far are refit.
  - Re-render at most 30 Hz, skipped every other frame under load, off at night.
  - Far geometry and props never cast shadows.
- **P2 (small details):**
  - Merged per tile and gated by a quality factor (low loses roof tanks).
  - No pixel-size culling exists in this code ("not found"). Distance tiers only (t2 radius
    314–566 m; site near tier 130/160 m × 0.6 on mobile).
