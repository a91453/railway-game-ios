> MODEL-AGE 的附表（2026-11-17，讀程式與 git 紀錄寫成的英文筆記），結論與分數見 `docs/research/MODEL_AGE_2026-11-17.md`。

# 3D map buildings and structures: inventory (2026-11-17)

Read-only survey of `origin/main` @ `19f3cc5` (2026-11-17). Full git history was used (after `--unshallow`).
Dates are first/last commit of the file (`git log --follow`). "D N" = decision N
(`docs/decisions/N.md` for 329+, `### N.` in `docs/ARCHITECTURE.md` below 329).

Method codes:
- **(a)** early procedural boxes + shared atlas `Map3DSurfaces.png` (D 229/231/235/242), hand-written Swift in the scene builder.
- **(b)** kit recipe pipeline: Codex/agent-made Swift recipes (`Map3D*Kit*.swift`, `StationKitBuilder`), with `tools/<kit>/` exporters (.m3dmodel/GLB/seven-view PNG) for previews. No look-at-photos rounds.
- **(c)** model-look process (D 685, `.claude/skills/model-look/SKILL.md`): real photos, game-camera shots, 3+ rounds; either a Swift recipe or local-Mac-studio Blender -> GLB -> Swift/.m3dmodel.
- **(c')** "reference-matched" before D 685 existed: Swift recipe from OSM plan + reference `landmarks.py`/Blender comparison (D 370/457), several rounds but not the D 685 checklist.
- **(d)** Meshy: no Meshy *building* is in the game. Only `meshy-bus-stop-pole.m3dmodel` and `meshy-post-boxes.m3dmodel` (street props) are bundled (`RailwayGameApp/Resources/Models/`).

Maps: **TW** = real-world Taiwan maps; **HK** = Hong Kong map pack; **ROV** = Rovaniemi (map pack, `OverseasMaps.open` still closed per HANDOFF); **GEN** = maps with no geo anchor (generated/demo town).

---

## 0. Answers to the specific questions

### 0.1 `Map3DSurface` (it is in `Map3DGeometry.swift`, not Map3DScene/Map3DShapes)

- Enum: `Sources/GamePresentation/Map3DGeometry.swift:129` `public enum Map3DSurface: Int, CaseIterable, Sendable {` ... first case `grass` at :131, last case `laneArrows` at :186. **24 cases**:
  grass, paving, ballast, concrete, roof, plaster, homeWindows, homeBalcony, shopfront, shutter, **flatWindows**, **officeGlass**, metalSheet, shopOptical, shopPhone, shopEatery, shopTea, **flatBlinds**, formConcrete, brickTile, mosaicTile, terrazzo, crosswalk, laneArrows.
- The only window surfaces a multi-storey block can get:
  - `Map3DGeometry.swift:191` `public static let flats: [Map3DSurface] = [.flatWindows, .flatBlinds]`
  - `Map3DGeometry.swift:190` `public static let shops: [Map3DSurface] = [.shopfront, .shopOptical, .shopPhone, .shopEatery, .shopTea]` (ground floor / podium only)
  - `.officeGlass` for offices.
  - `homeWindows`/`homeBalcony` are the 透天厝 bays (6 m bays), used up to 5 storeys (`Map3DRealBuildings.swift:174`: `storeys <= 5 ? ... .homeBalcony/.homeWindows ... : ... Map3DSurface.flats`).
- **Confirmed: tall buildings get only flatWindows / flatBlinds / officeGlass** (plus shop/glass podiums), with an optional under-material (formConcrete, brickTile, mosaicTile, terrazzo; D 242):
  - Generic tower/slab: `Map3DScene.swift:2117` (residential/commercial density>=3 -> `facade: .flatWindows`), `:2121` (office -> `facade: .officeGlass`); `:2354` `let windowSurface = facade == .flatWindows ? Self.pick(Map3DSurface.flats, r(3)) : facade`; density 3 slab 7–16 floors (`:2368`), density 4 podium + tower 18–40 floors (`:2390`), podium `:2391`.
  - Real footprints: `Map3DRealBuildings.swift:174-175` (shophouse >5 storeys -> flats), `:183` (flats), `:191-192` (office -> officeGlass), `:201` (civic -> flatWindows), `:216` (airport terminal -> officeGlass bay 4).
  - Nordic: `Map3DRealBuildings.swift:235,250`, `Map3DNordicBuildings.swift:110` (flatWindows / flats).
  - HK branch (D 812, not merged) also only reuses `.flats`, `.homeWindows`, `.officeGlass`, `.flatWindows` (`Map3DHongKongBuildings.swift:102-141` on `origin/claude/region-look-hk`), just at different bay widths (tower 2.6 m, mullion 1.6 m).
  - Old player box: `Map3DScene.swift:2439` `.flatWindows`.
- Since D 370 the shader takes only the atlas's luminance as a faint pattern + night-window mask; the face colour is the vertex palette colour (`RailwayGameApp/Views/Map3D/Map3DShaders.metal:349` `float3 base = in.color;`; model-look SKILL §6).

### 0.2 Atlas: 24 layers, full

- `RailwayGameApp/Resources/Map3D/Map3DSurfaces.png` is 512 x 6144 px = 24 layers of 256² (colour left half, tint mask right half), loaded as a 2D texture array of `Map3DSurface.allCases.count` slices (`RailwayGameApp/Views/Map3D/Map3DMetalView.swift:869-878`, strip check `:938` `image.width == 2 * side, image.height == side * count`).
- File history: first `537ceb0d3 2026-10-15 Native 3D map, step 3: textures from the asset library` (D 231), last `4270498b7 2026-10-22 Map3D road markings and street furniture (decision 355)`. Unchanged since 2026-10-22.
- "Full": D 355 point 3 added layers 22–23 (crosswalk, laneArrows) and says the shader's `nightWindows[12]` "剛好容納 24 層，所以只加兩層"; D 447 point 5 and `docs/research/TAIWAN_STREETSCAPE_2026-10-28.md:55` say `Map3DSurfaces.png` "已經用到 24 層的上限". HANDOFF.md:3411: "新增 `Map3DSurface` 時要加 rule，總層數不能超過 24。" (HANDOFF.md:3347 still says 22 layers/512 px: stale.)

### 0.3 Night-window table: capped at 24 **layers (surfaces), not 24 floors**

- `Map3DCamera.swift:547` `public static let nightWindowRowCount = 12`; `:554` `precondition(values.count <= nightWindowRowCount * 4, "the shader's nightWindows holds 24 layers")` (two surfaces per float4 row: share + brightest).
- Shader: `Map3DShaders.metal:39` `float4 nightWindows[12];`, `:494` `float4 row = uniforms.nightWindows[min(surface / 2u, 11u)];`.
- Per-surface rule: `Map3DCamera.swift:568-581` (`Map3DNightWindows.rule`): shops 0.75, officeGlass 0.4, home/flat 0.35, the rest 0.
- Floors are not capped by a table: windows are per bay x floor from `Map3DPaint.bays(..., floors:)`; towers reach 40 floors (`Map3DScene.swift:2390`). The vertex `layer` encoding allows up to 64 surfaces (`Map3DGeometry.swift:245` `detailStep = 64`), so the hard limit for a 25th surface is the 12-row uniform + precondition, not the encoding. **Adding any new facade surface means widening `nightWindows` (Swift + Metal) and the PNG.**

---

## 1. Generic procedural city buildings

| Item | Swift file(s) | When (first / last) & decisions | Method | Far/LOD | In game? where, how often | Doc remarks |
|---|---|---|---|---|---|---|
| Towers & slabs ("density blocks": flats, offices, 18–40-floor towers on podiums) | `Map3DScene.swift:2346-2428` `addBlock` | `1d7f4b0be 2026-10-15` native 3D step 1 (D 229); facades D 231, materials D 242, balconies D 238, roof plant D 235, roof colours D 764 | (a) boxes + atlas (flatWindows/flatBlinds/officeGlass) | Yes, D 238: far drops roof plant, balconies, ads (`!far` at :2373, :2397, :2402) | GEN: every res/com/office lot of density>=3. TW/HK/ROV: only lots of density>=3 that no footprint/landmark/station takes (`Map3DScene.swift:2064-2121`) | The "box with window texture" generation. HK branch D 812 recolours them only. No remake doc yet |
| Row houses / 透天厝 on generated lots | `Map3DScene.swift:2252` `addRowHouses` | `4270498b7 2026-10-22` (D 355 era; earlier versions inline since D 229) | (a) | far: simpler (D 238) | GEN: every res/com lot density<=2 | HANDOFF.md:3552: facade detail is texture on flat walls; D 267 added protruding parts close up |
| Street-front houses on real maps (透天厝 / small flats along real roads) | `Map3DFrontage.swift` (`addFrontage` :243, `addTownHouse` :459, `addFarTownHouse` :435), `Map3DLowRise.swift`, `Map3DFootprintCover.swift` | Frontage `0b37b12f6 2026-10-23` (D 385) -> last `5260040f1 2026-11-16` (D 802); LowRise `353a47bd7 2026-11-12` (D 707); FootprintCover `d8fdb0f6d 2026-11-13` (D 723); D 516 (office/civic/leisure low lots) | (a) boxes + atlas (shop/shutter ground, homeWindows/homeBalcony or flats upper), water tanks, sheet-steel roof rooms (D 235/267) | Yes: separate `addFarTownHouse` | TW/HK/ROV: every low-density cell with no real footprints, and thin cells (<1/4 covered, D 723). Very common where Overture has gaps | HANDOFF.md:1040 "決策 669 的牌樓老街屋立面要比屋頂高出更多" (that is the civic-kit old street house, not this) |
| Factories, schools, clinics, fire stations, procedural temple, mall | `Map3DBuildings.swift` (`addFactory` :78, `addCivic` :195, `addSchool` :208, `addClinic` :259, `addFireStation` :285, `addLeisure` :311, `addTemple` :329, `addMall` :453), roof shapes `Map3DShapes.swift` | `847d391ab 2026-10-15` (D 235) -> `5260040f1 2026-11-16`; Map3DShapes `bf163f58c 2026-10-15` | (a) recombined rules from `procedural_assets_reference_clean` (gable, sawtooth, arched sheds, chimneys, tanks); "a few boxes and roofs, a few hundred triangles" (file header) | partly (`isFar` checks) | GEN: industrial/civic/leisure lots. TW: only where no footprints (industrial lots among real buildings get the coal bunker instead, D 767, `Map3DScene.swift:2058-2062`) | `docs/research/MODEL_PALETTE_REVIEW_2026-11-15.md:69`: factory colours (`tinRoofs`, `shedWalls`, `brick`) never entered the t001 palette |
| Player-owned house / shop / office | `Map3DScene.swift:2430-2450` `addPlacedBuildings` fallback | `1d7f4b0be 2026-10-15` (D 229) | (a) **yellow box + navy rim + flatWindows** | no separate far (box anyway) | All maps, wherever the player builds `house`, `shop`, `office` (`PlacedBuildingKind`, `Sources/GameCore/City/PlacedBuilding.swift:39-43`). The other 11 kinds go to kits (§3) | Oldest look still in game; no remake ticket found |
| Finnish houses and blocks | `Map3DNordicBuildings.swift` (`addNordicHouse` :87), branches in `Map3DRealBuildings.swift:153-256`, `Map3DRegionLook.swift` | `5260040f1 2026-11-16` (D 802) | (a) same parts and atlas, no new texture (file header) | far version is **flat-roofed** (handoff item 5) | ROV only | `docs/handoff/REGION-LOOK-ROVANIEMI.md`: far houses flat roofs; station, signals, lights still Taiwan's; BACKLOG_AUDIT_2026-11-17.md:47 "北歐建築逐棟模型 ... 工作室" (3.20), :56 station/signals pending |
| Region look switch | `Map3DRegionLook.swift` | `5260040f1 2026-11-16` (D 802) | config only | — | TW (default), ROV (nordic); HK on branch | — |
| Station-front shop street shops | `Map3DShopStreet.swift` + `Map3DSceneKitBuildings.swift` (`commercialBlock`) + detail-kit goods | ShopStreet `78755f8be 2026-10-21` (D 322) -> `896e84e0f 2026-10-22` (D 352); SceneKit `1afbf012b 2026-10-21` (D 318) | (b) SceneKit commercialBlock (#900) + town-scene striped awning; "close up only, a box each far off" | yes (box far) | Every ordinary station plaza (D 321 cells), all maps; big city / HSR stations get commerce scenes instead | — |
| SceneKit house / apartment / tower families | `Map3DSceneKitBuildings.swift:3-30`, `Map3DSceneKit.swift:200` | `1afbf012b 2026-10-21` | (b) | — | **Not placed** (only via `Map3DModelPack(sceneKit:)` in tests); only `commercialBlock` is used by the shop street | — |

## 2. Real-world footprints

| Item | Swift file(s) | When & decisions | Facade / roof | Far/LOD | In game | Remarks |
|---|---|---|---|---|---|---|
| City-tile real buildings (Kaohsiung, Taichung stations) | `Map3DRealBuildings.swift` (`addRealBuildings` :54, `addRealBuilding` :136) | `172448da9 2026-10-15` (D 239) -> `58dd52409 2026-11-16` (D 802); D 764 colours, D 765 no windows on halls | by kind (`RealKind`): shophouse = shop/shutter ground + home bays (<=5 st.) or flats; house = homeWindows/Balcony; flats = flats (+50% shop ground); office = officeGlass (+formConcrete 40%); civic = flatWindows on formConcrete/brickTile; industry = metalSheet; temple = plaster on terrazzo + **hipped roof** (single small hall, :277); transport = concrete, big station = **canopy on pillars** (:282); terminal = officeGlass + `addTerminalRoof`; hall = no windows (D 765). Roofs otherwise **flat** with clutter; **pitched** only where `look.buildings.pitchesLowRoofs` (nordic) (:292) | Yes: D 455 far rectangles as `Map3DBoxInstance` instances (:304) | TW (two station areas) | — |
| Overture/OSM footprints (whole Taiwan; HK and ROV from their packs' `buildings.pmtiles`, D 712) | `Map3DFootprints.swift` (`addFootprints` :255) -> same `addRealBuilding` | `2469ac510 2026-10-23` (D 389, tiles D 386) -> `14bf9e634 2026-11-16` | same as above | same (D 455) | TW/HK/ROV: every building with a footprint ("some 1.96 million" outlines, D 610 header). The dominant building look on real maps | HK is about to change (D 812 branch): towers with roof crowns, 唐樓, grey roofs; its own "還有哪裡不好": towers "直上直下的盒子", no cross/Y plans |
| Street-front close layer (騎樓 pillars, grilles, ACs, blade signs, 頂樓加蓋) | `Map3DRealFacade.swift` (`addRealFacade` :102) | `d8794dcbc 2026-11-05` (D 610) -> `93709537d 2026-11-07` | geometry parts on street-facing walls, close only; off on low tiers / low power (:15-20) | close only | TW (and wherever `hasStreetFronts`; HK keeps fronts, no arcades on branch) | HANDOFF.md:1378-1379, §4.55: first screenshots showed nothing; fixed later |
| Airport terminals and hangars from OSM | `Map3DFrontage.swift:179` `addAirportBuildings` (only when no footprint tiles), terminal roof `Map3DAirfields.swift:199` | D 385 / D 698-699 | terminal: white glass + blue-grey roof; hangar: industry | D 455 | TW, HK (D 733) | — |

## 3. Kits: which are actually placed

| Kit | Files | When (first / last) | Placed in game? by what, where, how often |
|---|---|---|---|
| station-kit (general types) | `Map3DStationKit*.swift` (Catalog: 544 stations, `tools/station-kit/catalog.py`) | `4d799a574 2026-10-21` (#913) -> `431c31647 2026-11-12` | **Yes, every station** on every map: `Map3DStations.swift` (D 321, `dfa7eb42c 2026-10-21`) `addHouse` :421, canopies :389, entrances :544. Catalog profile counts: halt 112, regional 108, elevated 107, underground 99, lightRail 61, timber 23, highSpeed 4, heritage 4; plus named profiles. HK/ROV/GEN stations always get the general type by layout (catalog is Taiwan only). Close: kit model; far: a box + flat canopy. Catalog header: "building profiles are illustrative art". Method (b). |
| civic-kit | `Map3DCivicKit*.swift` | `f5e72843f 2026-10-21` -> `48541b617 2026-11-09` (D 669 Chinese roof) | **Yes**: Taiwan's temples (`Map3DLandmarks.swift`, D 331; 19,201 temples in `taiwan_temples.json`, capped at 60,000 triangles per scene / 10,000 per chunk, nearest first, `Map3DLandmarks.swift:15-16`), close only, far a box in the hall; player temple/school/hospital/night market (`Map3DPlacedBuildingKits.swift`, D 361/398). TW only for real temples |
| commercial-kit | `Map3DCommercialKit*.swift` | `a948d6630 2026-10-22` (single commit) | **Yes**: four scenes before big city/HSR stations (`Map3DStationCommerce.swift`, D 331 cont. 4, `dd56b50b0 2026-10-22`), close only; night-market stalls for player night markets; recycling bins on platforms (D 436) |
| park-kit | `Map3DParkKit*.swift` | `b741e1482 2026-10-21` (single commit) | **Yes**: real parks' scenes (`Map3DParks.swift`, D 331 cont. 3), close only; player parks (D 361) |
| estate-kit | `Map3DEstateKit*.swift` | `31ef7ef05 2026-10-23` (single commit) | **Yes, player-built only**: hotel, department store, amusement park (D 398); far a box per tall part |
| coastal-kit | `Map3DCoastalKit*.swift` | `fb80b93f1 2026-10-23` (single commit) | **Yes, player-built only**: wharf, marina (D 398) |
| detail-kit | `Map3DDetailKit*.swift` | `42c72ad80 2026-10-21` (single commit) | **Yes**: goods in front of shop-street shops (`Map3DShopStreet.swift`) |
| depot-yard kit | `Map3DDepotYardKit.swift` | `8ccd8c06d 2026-11-06` -> `effa45a4f 2026-11-16` | **Yes**: maintenance shed beside every depot station (D 785 via `Map3DDepotFacilities.swift:211-220`) |
| residential-kit | `Map3DResidentialKit*.swift` | `8773d4d5c 2026-10-21` -> `48541b617 2026-11-09` | **No** (no reference outside its own files; studies/tools only) |
| recreation-kit | `Map3DRecreationKit*.swift` | `9313507a4 2026-10-23` | **No** |
| works-kit | `Map3DWorksKit*.swift` | `79c8a8ace 2026-10-21` | **No** |
| SceneKit (156 subjects) | `Map3DSceneKit*.swift` | `1afbf012b 2026-10-21` (D 318) | Only trains (`Map3DTrainSets.swift`, `Map3DTrainLocomotives.swift`) and the shop street's `commercialBlock` |

Player-placed kinds (`Map3DPlacedBuildingKits.swift:29-80`): park, temple, railwayMuseum, hotel, departmentStore, amusementPark, wharf, marina, school, hospital, nightMarket -> kit/own models. house, shop, office -> old yellow box (§1).

## 4. Stations

| Item | Files | When & decisions | Method | Far | In game | Remarks |
|---|---|---|---|---|---|---|
| Generic station buildings, canopies, entrances | `Map3DStations.swift`, `Map3DStationKit*.swift` | D 321 (2026-10-21); last `b467f1fb7 2026-11-16` (winter lights D 804) | (b) | box + flat canopy | every station, all maps | Rovaniemi: "車站本體 ... 還是台灣的模型" (REGION-LOOK-ROVANIEMI handoff item 4); D 685 README: kit `heritage` type "紅磚盒子加紅四坡頂"; 日南、談文、大山、新埔 still generic |
| Named catalog profiles (taipei, taichung, kaohsiung, hsinchu, tainan, chiayi, keelung, nangang, banqiao, hualien, taitung, zuoying, HSR x4, formosa, centralPark) | `Map3DStationKitBuildings.swift`, `Map3DStationKitCatalog.swift` | `4d799a574 2026-10-21` | (b) | box | TW, at those stations when no exterior study stands | Most are now overridden by exterior studies (below) |
| Zhuifen (coastTimber, 1922 wooden) | `Map3DStationKitBuildings.swift:266` | D 685 (2026-11-11), `docs/art/model-look-2026-11-11/` | (c) recipe, 4 rounds | (kit far box) | TW, one station | README "還有哪裡不好": 800 m only grey rectangle; flat roof surface; Metal not verified |
| Jiji, Bao'an | `Map3DStationKitBaoan.swift`, catalog profiles `.jiji`, `.baoan` | `431c31647 2026-11-12` (D 705), `docs/art/station-look-2026-11-12/` | (c) recipe, 4+3 rounds | kit far | TW, two stations | 800 m read as dark-grey blocks (round 0); see README |
| Exterior studies batch 1 (TRA Taichung, Hsinchu, Hualien, Taitung, Banqiao, Nangang; HSR Taoyuan, Hsinchu, Taichung, Tainan, Zuoying) | `Map3DStationExteriorBatch1.swift`, placed by `Map3DStationExteriors.swift` | studies `d6a361f9e 2026-11-06` -> `c92a8972b 2026-11-07`; placement `486176236 2026-11-07` (D 625) -> `7a31924ba 2026-11-14` | Swift recipes from Blender refs + OSM outlines (`docs/art/station-exteriors-batch1`); pre-D 685, not the 3-round photo process | near/far LOD (`LevelOfDetail`) | TW, 11 places (+ stations within them) | — |
| Exterior studies batch 2 (Keelung, Chiayi, Tainan, Beimen, Fenqihu, Alishan, Wushulin, Xihu, Qiaotou) | `Map3DStationExteriorBatch2.swift` | `7a3820c62 2026-11-07` -> `985d5087d 2026-11-09` (D 626, placed D 665) | as above (OSM + official data only) | near/far | TW, 9 places | — |
| Taipei Main Station, Kaohsiung Station | landmarks (§5) | D 370, D 431 | (c') | near/far | TW | — |
| Station-front commerce | `Map3DStationCommerce.swift` | D 331 cont. 4 | (b) | close only | big stations, TW (and any map's big stations) | — |
| Platform props | `Map3DPlatformProps.swift` | `6a92bf1e5 2026-10-27` (D 436) | (a)/(b) small parts | closest only | all stations | not buildings |
| Depot shed, Changhua turntable | `Map3DDepotFacilities.swift` | `2739ab181 2026-10-27` (D 441) -> `7a801007f 2026-11-15`; shed via depot-yard kit (D 785) | (b) (laid again from reference pack `railway_facilities_pack01.py`) | — | every depot station; turntable once (Changhua) | BACKLOG_AUDIT:87 "機廠附屬建物" low importance |

## 5. Landmarks and other single structures

| Item | Files | When & decisions | Method | Far | In game |
|---|---|---|---|---|---|
| Taipei 101, Taipei Main Station | `Map3DTaipeiLandmarks.swift` | `debcf4504 2026-10-23` (D 370 step 2) -> `d82832cf7 2026-11-13`; D 555 re-shot (`docs/art/landmark101-2026-11-03`) | (c') Swift from OSM + reference `landmarks.py` | near/far (no small parts afar) | TW, once each |
| Kaohsiung Station; 85 Sky Tower; Shin Kong Life Tower; Changhua Roundhouse; Great Harbor Bridge, Music Center, Gushan/Cijin ferry terminals | same file | D 431 (Gemini), D 548, D 550, D 581, D 592 | (c') Swift recipes | near/far | TW, once each |
| CKS Memorial Hall, Liberty Square gate, National Theater, Concert Hall, Presidential Office, Ximen Red House, Sun Yat-sen Hall, Grand Hotel, North/East/South/Small South gates | `Map3DTaipeiLandmarks.swift`, `Map3DTaipeiPalaces.swift`, `Map3DChineseRoof.swift` | Palaces `208697ad3 2026-10-28` (D 457) | (c') 3 rounds vs Blender meshes (`docs/art/taipei-landmarks-457/README.md`) | near/far | TW, once each |
| Ten Taipei temples/church in their own shape | `Map3DTaipeiTemples.swift`, `Resources/Models/tpe-*.m3dmodel`, `tools/tpe-temples/` | `fc329972e 2026-11-13` (D 725) | open-data KMZ shape -> simplified .m3dmodel, game colours | near / roofs only far | TW, 10 places |
| Generic temples (civic kit) | `Map3DLandmarks.swift` | `1c514e617 2026-10-22` (D 331 cont.) | (b) | far box | TW, up to budget of 19,201 sites |
| Hong Kong landmarks (ICC, Two IFC, Central Plaza, Bank of China, Cheung Kong, HSBC, The Center, TST Clock Tower, Cultural Centre, Convention Centre) | `Map3DHongKongLandmarks.swift`, `Map3DHongKongLandmarkMeshes.swift` (generated by `tools/hk-landmarks/glb_to_swift.py`) | `16538340d 2026-11-15` (D 791) -> `2669c8527 2026-11-17` (HSBC D 793, HKCEC D 798) | (c) local studio Blender -> GLB -> Swift, Lands Dept 3D shapes | studio `-far` model | HK, once each |
| Railway museum | `Map3DRailwayMuseum.swift`, `tools/model-look/export-museum.*` | `eedda76d5 2026-11-12` (D 696) | (c) recipe after old Taipei Workshop | stand-in boxes | player-built, any map |
| Airfields: runways, aprons, jet bridges, control towers | `Map3DAirfields.swift` | `ff19d35b1 2026-11-12` (D 699; tower look D 698) | Swift; tower redone in D 698 studies | — | TW + HK airports |
| Coal bunker in old yards | `Resources/Models/coal-bunker.m3dmodel`, `tools/coal-bunker` | D 767 | owner's old white model, recoloured | — | TW, "now and then" in industrial lots among real buildings |
| Viaducts, tunnels, tunnel portals, road tunnel portals, road bridges | `Map3DViaducts.swift` (D 407, `53d52f37a 2026-10-25`), `Map3DTunnels.swift` (`760ff7bf6 2026-10-23`), `Map3DRoadTunnelPortals.swift` (`072a6aa7b 2026-11-06`) | — | (a)/(b) parametric along track | — | all maps along track |
| Not structures despite names | `Map3DTaoyuanAirport.swift` = Airport MRT **train** studies (`a38118a1e 2026-11-02`); `Map3DTaipei610.swift` = Taipei Metro 610 **train** (`488b29994 2026-10-27`) | — | — | — | — |

## 6. Street furniture (short)

- `Map3DProps.swift` (`0ffa2dcc4 2026-10-15`): trees, streetlights (6-sided cylinder + box arm + box head, :74-79), utility poles (:84-92), traffic signals `addSignal` :123-133 (cylinder pole, box arm, box head, box lamps). Early primitive boxes, though recoloured 2026-11-15. Pedestrian signals D 445, HK signals D 732 (same primitive style). Meshy props: bus-stop pole, post boxes only. ROV still uses Taiwan's signals, lights, stops (REGION-LOOK-ROVANIEMI handoff item 4).

## 7. Other session in flight

- **REGION-LOOK-HK**, PR #2330, D 812, branch `claude/region-look-hk` (session_01JMHz9ZyBkSeXL3qpPx5JUD). `git diff --stat origin/main...origin/claude/region-look-hk`: 11 files, +484/−27: new `Map3DHongKongBuildings.swift` (+227), `Map3DFrontage.swift` (+12), `Map3DRealBuildings.swift` (24), `Map3DRegionLook.swift` (29), `Map3DScene.swift` (13), tests (`Map3DRealFacadeTests`, `Map3DRegionLookTests`), `docs/decisions/812.md`, `docs/handoff/REGION-LOOK-HK.md`, `docs/art/region-look-hk-2026-11-17/`. It recolours HK footprints / frontage / `addBlock` (towers + roof crowns, 唐樓, glass offices, grey roofs) with **no new texture layer**: still flats/homeWindows/officeGlass. Avoid editing `addBlock`, `addRealBuilding`, `Map3DFrontage` and `Map3DRegionLook` in parallel.

## 8. Candidates for "old generation" (facts only)

1. **Player house/shop/office yellow boxes** (`Map3DScene.swift:2430-2450`, D 229, 2026-10-15). Oldest; everywhere the player builds those three kinds.
2. **Generic `addBlock` towers/slabs** (D 229/231/235/238/242): plain boxes with three window textures; GEN everywhere, real maps in gaps. Atlas full (24/24), so a richer facade needs either geometry or widening the atlas + `nightWindows`.
3. **Footprint extrusions** (D 239/389, ~1.96 M outlines): flat roofs + same three facade textures; this is most of what players see on TW/HK/ROV. D 610 adds a close-up street layer only.
4. **Procedural factories/schools/clinics/temples/malls** (`Map3DBuildings.swift`, D 235).
5. **Station-kit general types** (D 321, 2026-10-21; 500+ stations, plus all HK/ROV/GEN stations): D 685 calls the `heritage` type a red-brick box; only Zhuifen, Jiji, Bao'an went through model-look.
6. Placed but kit-made, never model-looked: civic-kit temples (TW), commercial/park/estate/coastal kits. Not placed at all: residential, recreation, works kits, SceneKit buildings.
7. Already newer generation: HK landmarks (studio), railway museum, Zhuifen/Jiji/Bao'an, exterior studies (D 625/665, partial process), Taipei landmarks (D 370/457, reference-matched), Taipei temples (D 725).

## Unknowns

- Whether GEN maps are reachable by ordinary players today (tutorial/demo?) was not checked.
- Exact per-scene counts of procedural `addBlock` buildings on real maps were not measured.
- Model-look rounds for D 698 control tower and D 696 museum: found in the model-look grep, but their READMEs were not read in detail.
