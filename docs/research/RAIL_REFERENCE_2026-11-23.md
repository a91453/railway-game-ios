# 參考庫 `Railway/rail-reference/` 研究（2026-11-23，RAIL-REFERENCE-1123）

讀的是私有參考庫 `a91453/railway-reference-private` main `9298482`（#155 合併），只 sparse-checkout `Railway/rail-reference/`。11-23 的兩個 commit：`8f337fa`「refresh Taiwan procedural landscape and rail 3D research」與 `2e20ab5`「清理參考識別與來源連結，補齊地景依賴」（比較基準是前一個動到這個目錄的 `95c646e`）。讀過：`README.md`、`INVENTORY.json`、`rights/README.md`、`regions/taiwan/rights/SOURCE_UPDATE_2026-11-23.json`、`regions/taiwan/rights/REFERENCE_PROVENANCE_2026-11-16.json`、`regions/taiwan/source/landscape-engine/README.md`，以及每個新檔的開頭與匯出函式。GLB、影像、二進位一律沒下載（這次也沒有收錄）。程式沒有執行，下面寫的行為是讀程式得來的，**UNVERIFIED**。

這張只研究，不改程式、不移植。移植項目由協調者照 §4 的評分另派。

## 0. 目錄怎麼變的（11-16）

- `Railway/taiwan-rail-reference-clean/` 與 `Railway/world-rail-reference-clean/` 已**刪除**，換成 `Railway/rail-reference/`（`INVENTORY.json` 的 `replaces`）。
- 換算規則：舊 `taiwan-rail-reference-clean/source/X` → `rail-reference/regions/taiwan/source/X`；舊 `taiwan-rail-reference-clean/rights/` → `rail-reference/regions/taiwan/rights/`；世界版相同，換成 `regions/world/`。兩區相同、不靠相對網址的 15 個 3D ES Module 移到 `shared/`，原路徑留 `export * from` 轉接檔，所以舊檔名都還在。
- 遊戲引用過的舊路徑在新位置逐一確認都在：`rail-3d/physical/`、`data/tra_schedule_dense.json`、`data/tra_special_trains.json`、`data/station_transfers.json`、`data/track_style_layers.json`、`main-reference.js`、`rail-3d/integration/{portal-clearance,tunnel-portals,rail-structures,camera-motion,map3d}.js`、`rail-3d/assets/garage-blender-v1/sanying.json`、`rail-3d/README.md`、`data/data_provenance.json`、`app/THIRD_PARTY_NOTICES.md`、世界區的 `source/docs/HANDOFF-2026-10-01.md` 與 `source/tools/build_singapore.mjs`。

## 1. 11-23 新增與更新了什麼

`SOURCE_UPDATE_2026-11-23.json` 記上游 `bedd0d1` → `cc9d461`：新增 63、更新 100、移除 5 個路徑。在參考庫裡實際落成：`8f337fa` 加 63 個檔、改 6 個；`2e20ab5` 加 2 個、刪 5 個、改 140 個（多半是去識別的文字清理）。

### 1.1 新增：台灣程序化地景引擎 `regions/taiwan/source/landscape-engine/`（59 個檔）

全部是 JavaScript（Three.js，MIT，`rail-3d/vendor/` 的那一份，`engine/vendor/three.module.js` 只是轉接）。**沒有**圖磚資料（`/tiles/`、`./routes/*.json` 不在）、沒有宿主介面（`globalThis.__LANDSCAPE_HOST__` 要專案自己給，`host-stubs.js` 只是關掉可選圖層）、沒有二進位模型。所以它不能單獨跑，能用的是**規則、常數與幾何寫法**。

| 檔 | 內容 | 來源、授權、資料日期 |
| --- | --- | --- |
| `engine/shared/terrain.mjs` | 1,280 m 圖磚的地形編碼：粗格 65×65（20 m）＋細格 513×513（2.5 m）分 32×32 塊，容差 0.05／0.35 m，三級 LOD（1、4、12） | 程式本身；地形值由 `main.js` 註明為內政部 20 m DEM 與 Copernicus（資料不在庫內） |
| `engine/proj/tm2.mjs` | TWD97 TM2（中央經線 121°、k0 0.9999）正反算、子午線收斂角、尺度係數 | 公開的投影公式 |
| `engine/shared/sky-ephem.mjs` | 月亮與太陽的黃道位置、章動、格林威治恆星時、儒略日（台灣時間）；以台北 25.05°N 121.5°E 為預設 | 天文公式（Meeus 系的級數），程式本身 |
| `engine/shared/night-sky.mjs`、`night-bloom.mjs`、`night-mix.mjs` | 夜空 shader、八方向的城市光暈（`GLOW_CITIES`、`cityGlow`）、泛光 | 程式本身 |
| `engine/shared/night-city.mjs`、`model-lights.mjs`、`night-tunnels.mjs` | 路燈沿路放置（避開橋面、鐵軌）、模型個別投光、隧道依地下里程重算夜燈 | 程式本身 |
| `engine/shared/road-marks.mjs`、`surface-markings.mjs`、`road-ribbons.mjs`、`deck-lines.mjs`、`tunnel-roads.mjs`、`street-mesh.mjs` | 道路等級表（`RANK`）、路口偵測、雙線道配對、標線沿中心線、急彎斜接長度限制、橋面邊線與護欄、隧道段取地表段 | 程式本身；道路來自 OSM 圖磚（ODbL，資料不在庫內） |
| `engine/shared/street-objects.mjs`、`road-trees.mjs` | 路口號誌、機車停放列（`MOTO_COLORS`、密度 0.55、間距 0.8 m）、行道樹 | 程式本身 |
| `engine/shared/tw2*.mjs`（`tw2`、`tw2-bridge`、`tw2-infra`、`tw2-roof`、`tw2-temple`、`tw2-tone`）、`tw-variety.mjs`、`hill-styles.mjs` | 台灣式地景第二版：橋梁與月台幾何、**輸電鐵塔與跨距線、風力機與轉子、電車線（`ocsGeo`）**、屋頂、**廟宇屋瓦與牆色表**、山邊社區的樓層規則 | 程式本身（廟的顏色、山坡社區規則依實景描述） |
| `engine/shared/cvs-look.mjs` | 三家便利商店的招牌色帶 | 依實景色 |
| `engine/shared/rail-hl.mjs`、`station.mjs`、`fx2.mjs`、`fx3.mjs` | 鐵道依系統上色（`railColor`）、遠景距離 2,600 m、屋頂與沿太陽方向的影子遮罩 | 程式本身 |
| `engine/kit-city-atlas.js`、`kit-building-appearance.js`、`tw-facade.js` | 程式畫出的立面圖集（BAY 4.4 m；校舍走廊、消防車庫、廟門、格窗）、農村與城市的建物外觀規則、透天立面（鐵窗尺寸表、一樓店面／鐵捲門／大廳、牆腳髒污） | 程式本身（canvas 畫，不是圖片） |
| `engine/integration/level-crossing.js` | **平交道路面**：黃黑警示、白線、坡道（平段 3.2 m、坡 5 m、抬高 0.15／0.32 m） | 程式本身 |
| `engine/integration/portal-clearance.js`、`tunnel-portals.js`、`road-underpass.js`、`rail-structures.js` | 隧道口淨空體積、隧道口分組（半淨寬 3.2 m、深 12 m、翼牆 8 m）、道路下穿、高架抬升 6 m | `rail-3d/integration/` 同名檔的地景版 |
| `engine/integration/airports.js`、`airports-worker.js` | 機場接合（第 125 包） | 程式本身 |
| `engine/main.js`、`buildings.worker.js`、`tile.worker.js`、`fetch-v.mjs` | 引擎入口與 worker（143 KB／65 KB／27 KB） | 程式本身 |
| `foguang-buddha.mjs` | 佛光大佛（佛身 48 m、手印、盤坐） | 佛陀紀念館的典藏說明 |
| `presidential-facade.mjs` | 總統府立面（兩翼、天井、拱、白帶、複柱） | 總統府建築介紹 |
| `place-models.mjs`、`place-structures.mjs`、`places.mjs` | 摩天輪等地點模型（中心與高度、車廂數）、遊具與道路洞口、校舍與運動場 | OSM（ODbL）；車廂數取自業者刊物與票券介紹 |
| `heritage-catalog.mjs`、`heritage-geometry.mjs`、`heritage-models.mjs`、`places/heritage.json`（`2e20ab5` 補） | **29 座古廟**（艋舺清水巖、彰化孔子廟、鹿港文武廟、北港鎮安宮……）的屋緣輪廓、方位、高度，屋面依輪廓裁切 | 輪廓：國土測繪中心正射影像描繪（`maps.nlsc.gov.tw`）；說明：內政部全國宗教資訊網；高度「依實景估製」 |
| `landmark-fix.mjs` | 圖磚把圍牆、牌樓當建物時改專屬型別 | 程式本身 |
| `follow-rain.mjs` | 雨絲與山霧（共用鏡頭與公尺座標、靜態緩衝） | 程式本身 |
| `models/duoliang/model.json` | 多良車站的錨點、LOD 與各部件色（粉刷牆、洗石子、欄杆…）；mesh.bin **不在** | 台東觀光網、OSM 四個 way |

### 1.2 新增：`rail-3d/environment/` 的營運時間（4 個檔）

| 檔 | 內容 | 來源、日期 |
| --- | --- | --- |
| `station-hours.js` | 每站每天（索引 0＝週日）第一班到最後一班有旅客的分鐘數，涵蓋台鐵、高鐵、北捷、高捷、中捷、機捷、阿里山林鐵…… | 由 `scripts/build_landscape_station_hours.mjs` 從班表產生（**產生器不在庫內**）；班表是庫內的 2026-10-16 台鐵與各系統時刻 |
| `model-hours.js` | 站體點燈規則：共構站任一系統有旅客就亮（台北、板橋、南港、新左營、新烏日、高鐵桃園……）；古蹟舊站房、展館和現役客站分開 | 程式本身 |
| `venue-hours.js` | 展館、紀念建築的開放或外觀點燈時段，每月休館日 | 文化資產局開放資料（`data.boch.gov.tw`）、政府資料開放平台、各館公告 |
| `station-name.js` | 站名比對鍵 | — |

### 1.3 新增：`data/trip_impact_lines.json`

台鐵 12 條、高鐵 1 條的依序站名與累計公里，加上「對號／非對號」車種分類、繞行線（`WL-C`、`CZ`）。來源：TDX v3 `Rail/TRA/StationOfLine`（2026-10-28T00:44:33Z）。產生器 `scripts/build_trip_impact_lines.mjs` **不在庫內**。

### 1.4 更新

- `rail-3d/integration/profile-lines.js`：路線疊在地形上時，深度沿視線往鏡頭拉近 `LINE_PULL`（0.015），被山坡擋住的地面段另畫一遍反向深度的半透明「透出」（`GHOST` 0.42）；遠處淡出。只畫地面段，山岳隧道照舊被山擋。
- `rail-3d/integration/rail-structures.js`：夜色調整可處理依種類分色的運算式（`hasColor`），換底圖時沿用基礎光。
- `rail-3d/integration/place-guide.js`：前往地點時若地形還沒載入，不用 0 當高程（山區會繞海平面轉），抵達後重算一次中心高度；拿掉下拉選單。
- `rail-3d/environment/sun.mjs`：只改一行註解。遊戲的 `Map3DSunPath.swift` 逐行譯自這個檔，**計算沒變，不用跟改**。
- `2e20ab5` 清理：`data/tra_special_trains.json`（台灣、世界兩份）的新聞來源網址改成空字串、其他值不變（`dataValueAndStructurePreservationCheckPassed`）；`prototypes/tiny-trains/blender/tw-v2/catalog-source.json` 同類清理；文件、i18n 去識別。
- 移除：`scripts/launch_watch.mjs`、`usage_split.mjs`、`lib/cf_analytics.mjs`、`lib/stadia_projection.mjs`、`verify_stadia_projection.mjs`（網站的分析與部署工具，遊戲沒用過）。

### 1.5 授權總結

- 程式：Three.js MIT（`rail-3d/vendor/three-LICENSE.txt` 保留）；其餘是業主自己的程式，依 CLAUDE.md 視為授權可用。
- 資料：OSM 衍生的（道路、地點中心與高度）照 ODbL，進遊戲時在 `DataSourceCredits` 已有的 OSM 那一行；國土測繪中心描繪的廟宇輪廓與 TDX、文化資產局資料是政府資料開放授權，進遊戲時要加一行署名。
- 沒有新的 copyleft 或無授權第三方程式碼。

## 2. 遊戲已經用了什麼、還沒用什麼

### 2.1 已用（從 `rail-3d/`，在 11-16 之前以舊路徑讀）

| 參考 | 遊戲 |
| --- | --- |
| `rail-3d/environment/sun.mjs` `sunPosition` | `Map3DSunPath.swift`（已寫新路徑） |
| `rail-3d/integration/tunnel-portals.js` | `Map3DTunnels.swift` |
| `rail-3d/integration/portal-clearance.js` | `Map3DTrench.swift` |
| `rail-3d/integration/rail-structures.js` | `DoubleTrack.swift`、`TrackSlopes.swift` |
| `rail-3d/integration/map3d.js`（地下層） | `Map3DXRay.swift` |
| `rail-3d/integration/camera-motion.js` | `Map3DFollow.swift` |
| `rail-3d/physical/` | `tools/real-railways/extract_tracks.py`、`extract_structures.py` |
| `data/tra_schedule_dense.json` | `tools/real-timetables/*`、`Map3DHeadSigns.swift`、`tools/tra-delay-analysis` |
| `data/tra_special_trains.json` | `BranchLineChallenge.swift`、GameCore `TrainTypeCatalog.swift` |
| `data/station_transfers.json` | GameCore `PassengerRoutes.swift` |
| `main-reference.js` `TW_DAYTYPE` | GameCore `Holidays.swift` |
| `rail-3d/landcover/` | `tools/worldcover/build_landcover_grid.py`（已寫新路徑） |
| 世界區 `tools/build_singapore.mjs` | `tools/hk-map/build_hk_mtr.py` |

遊戲另有自己的做法、和地景引擎重疊的：天空與月亮（`Map3DSky.swift`，月亮固定在太陽對面、永遠滿月）、雨（`Map3DRain.swift`）、夜色（`Map3DNight.swift`）、立面（`Map3DFacadeVariety.swift`、`Map3DRealFacade.swift`）、道路標線與路口（`Map3DRoadMarkings.swift`、`Map3DRoadJunctions.swift`）、道路橋與隧道（`Map3DRoadBridge.swift`、`Map3DRoadTunnelPortals.swift`）、平交道柵欄（`Map3DCrossingGate*.swift`）、機車（`Map3DScooters.swift`）、電車線（`Map3DOverheadLine.swift`）、廟（`RealTemples.swift` 的廟址、`Map3DTaipeiTemples.swift`）、總統府（`Map3DTaipeiPalaces.swift`）、地形（`TerrainMap.swift`）。佛光山、多良車站只在 `AttractionCatalog.swift` 當景點，沒有 3D。

### 2.2 還沒用（11-23 的新東西全部沒用）

- 真實月相與月亮位置（`sky-ephem.mjs`）；夜空城市光暈（`night-sky.mjs`）。
- 車站依班表點燈、共構站規則、展館點燈時段（`station-hours.js`、`model-hours.js`、`venue-hours.js`）。遊戲的 `Map3DSigns.swift` 只有商店打烊（夜市參考）。
- 平交道路面（`level-crossing.js`）：遊戲有柵欄，沒有黃黑鋪面與坡道。
- 輸電鐵塔、跨距線、風力機（`tw2-infra.mjs`）：遊戲完全沒有。
- 29 座古廟的屋緣輪廓與廟瓦配色（`heritage.json`、`heritage-geometry.mjs`、`tw2-temple.mjs`）。
- 透天立面規則：鐵窗尺寸、一樓店面／鐵捲門／大廳的判定、山邊社區樓層、便利商店色帶（`tw-facade.js`、`kit-building-appearance.js`、`hill-styles.mjs`、`cvs-look.mjs`）。
- 山霧（`follow-rain.mjs`）、道路急彎斜接與橋面邊線（`road-ribbons.mjs`、`deck-lines.mjs`）。
- 佛光大佛、總統府立面、多良車站部件尺寸（`foguang-buddha.mjs`、`presidential-facade.mjs`、`models/duoliang/model.json`）。
- 路線透出被山擋住的地面段（`profile-lines.js` 的 `GHOST`）：遊戲 `Map3DXRay.swift` 只透地下段。
- 不打算用：`tm2.mjs`（遊戲有自己的座標換算）、`terrain.mjs` 的圖磚編碼（遊戲地形另有來源與格式）、`trip_impact_lines.json`（遊戲的站序與公里已由 `tools/real-railways` 從同一來源產生）、`airports.js`（遊戲機場另有決策）、`place-guide.js`（網站導覽）。

### 2.3 還指向舊路徑的地方與改法

舊路徑在新庫已不存在，照 §0 的規則一律換成 `Railway/rail-reference/regions/taiwan/source/…`（世界版 `regions/world/source/…`）。

| 位置 | 數量 | 建議 |
| --- | --: | --- |
| `CLAUDE.md` 參考庫清單 | 1 段 | **本 PR 已改**：換成 `Railway/rail-reference/`，寫換算規則與 11-23 的地景引擎 |
| `tools/` 的 README 與腳本用法說明：`real-railways/{README.md,extract_tracks.py,extract_structures.py,measure_osm_offset.py}`、`real-timetables/{README.md,extract_branch_runs.py,rebuild_tra_schedule.py}`、`tra-delay-analysis/{README.md,analyze.py}`、`real-world-population/{README.md,build_water_grid.py}`、`hk-map/{README.md,build_hk_mtr.py}`、`map3d-preview/README.md`、`real-coaches/README.md`、`real-buses/README.md`、`five-section-lrt/README.md`、`three-car-urban/README.md` | 19 檔 | 改成新路徑（下一張工具 PR；腳本都是用參數收路徑，只改說明與範例指令） |
| 寫進產出資料的字串：`tools/real-timetables/extract_tra_schedule.py` 的來源說明、`tools/five-section-lrt/bundle.py`、`tools/lrt-pair/bundle.py`、`tools/three-car-urban/bundle.py` 的 `private_reference_use`、`tools/sanying/source-record.json` | 5 檔 | **不改**：它們進 App 帶的 `RailwayGameApp/Resources/RealRailways/tra-schedule.json` 與模型包的來源記錄，改了資料雜湊跟著變；記錄的是當時讀的位置，照實保留。下次重新產生時再寫新路徑 |
| 程式註解：GamePresentation 13 檔（`BranchLineChallenge`、`DoubleTrack`、`HighSpeedFares`、`Map3DFollow`、`Map3DHeadSigns`、`Map3DStreaming`、`Map3DTrainLabels`、`Map3DTrench`、`Map3DTunnels`、`Map3DXRay`、`RealTrainMotion`、`RealWorldMap`、`TrackSlopes`）、GameCore 3 檔（`Holidays`、`PassengerRoutes`、`TrainTypeCatalog`）、`Tests/GameCoreTests/HolidayTests.swift`、`RailwayGameApp/Views/MapArt.swift` | 18 檔 | 下次動到該檔時順手改；不值得單獨開一張動 GameCore（會跑完整一層 CI） |
| `docs/decisions/`（123 檔）、`docs/research/`（25 檔）、`docs/ARCHITECTURE.md`、`docs/RAILWAY_REFERENCE_MAPPING.md`、`docs/art/`（19 檔） | 170 檔 | **不改**：歷史紀錄，記的是當時讀的路徑；靠 CLAUDE.md 的換算規則找新位置 |

## 3. 可移植的新東西：對照表

全部屬 Presentation（`Sources/GamePresentation/`，Metal shader 在 `Map3DShaders.metal`）。沒有一項碰遊戲規則，**不進 GameCore**，所以沒有定點比例；Presentation 用 `Float`，單位照參考是公尺、度、分鐘。班表點燈讀的是 `GameWorld` 已有的時刻（玩家的線）或 App 帶的真實時刻，不另存狀態。

| # | 參考檔／函式 | 遊戲目標檔／函式 | 單位與比例 | 層 |
| --: | --- | --- | --- | --- |
| A | `sky-ephem.mjs` `jdTw`、`moonEcliptic`、`nutation`、`sunEcliptic`、`gmst` | `Map3DSunPath.swift` 加 `moonPosition(date:latitude:longitude:)` 與月相照度；`Map3DSky.swift` 的 `moon`、`moonShown` 改用它，shader 加月相遮罩 | 度、儒略日（Double 算，交給 shader 用 Float） | Presentation |
| B | `station-hours.js` 的格式、`model-hours.js` 的共構站與古蹟站規則 | 新 `Map3DStationHours.swift`：由該站的第一班與最後一班（`GameWorld` 時刻）算每站亮燈區間；`Map3DNight.swift` 的站房窗光乘上它 | 營運日的分鐘（Int，0–1,440 之後可跨日） | Presentation |
| C | `venue-hours.js` `venueHours`、`monthlyMondayClosures` | 地標點燈：`Map3DNight.swift` 的地標窗光＋`Map3DSigns.swift` 的打烊同一套 | 分鐘；索引 0＝週日 | Presentation |
| D | `integration/level-crossing.js` `levelCrossingGeometry`（`FLAT` 3.2、`RAMP` 5、`RAISE` 0.15、`LIFT` 0.32，色 `YEL`、`BLK`、`WHITE`） | 新 `Map3DLevelCrossingDeck.swift`，放在 `Map3DCrossingGate.swift` 已找到的平交道上；顏色收進 `Map3DPalette` | 公尺 | Presentation |
| E | `tw2-infra.mjs` `towerLines`、`towerSolid`、`spanLines`、`turbineMesh`、`rotorGeo` | 新 `Map3DPowerLines.swift`（鐵塔＋懸鏈）、`Map3DWindTurbines.swift`（台灣西海岸風場位置要另找開放資料，參考沒附） | 公尺；跨距 `N`＝6 段 | Presentation（模型照 model-look 看照片） |
| F | `night-sky.mjs` `GLOW_CITIES`、`cityGlow`、`NIGHT_SKY_GLOW_GLSL` | `Map3DSky.swift` 加八方向城市光暈，城市清單由 `RealWorldMap` 的城市人口算，不寫死台北 | 0–1 強度 | Presentation |
| G | `heritage.json`（29 座）、`heritage-geometry.mjs`（依屋緣裁瓦面）、`tw2-temple.mjs` `TEMPLE_TILE`、`TEMPLE_WALL`、`templeRoofHex` | `RealTemples.swift` 的廟址遇到這 29 座時改用真實輪廓與方位；`Map3DTaipeiTemples.swift` 的屋瓦色改用依 id 雜湊挑色 | 經緯度→公尺；色是 sRGB 十六進位 | Presentation；`tools/temples/` 讀 heritage.json 轉成 App 資料 |
| H | `tw-facade.js`（`CAGE` 鐵窗表、一樓 quiet／lobby 判定）、`kit-building-appearance.js`（農村、城市規則）、`hill-styles.mjs`、`cvs-look.mjs` | `Map3DFacadeVariety.swift`、`Map3DRealFacade.swift` 的款式選擇；便利商店色帶進 `Map3DStationExteriorBatch1.swift` 已有的店面 | 公尺（BAY 4.4） | Presentation（立面圖集照 art-style） |
| I | `follow-rain.mjs`（山霧與雨共用鏡頭座標、霧色跟著樹冠與地面） | `Map3DRain.swift`＋`Map3DWeather.swift` 加山霧 | 公尺 | Presentation |
| J | `foguang-buddha.mjs`、`presidential-facade.mjs`、`models/duoliang/model.json` 的部件與色 | 工作室派單（地標 kit）；總統府對照 `Map3DTaipeiPalaces.swift` 現有的 | 公尺；色 0–1 線性 | Presentation（model-look，工作室） |
| K | `road-ribbons.mjs` 急彎斜接限制、`deck-lines.mjs` `DECK_LINE`、`edgeSkips` | `RoadSmoothing.swift`、`Map3DRoadBridge.swift` | 公尺（inset 0.35、margin 0.3） | Presentation |
| L | `profile-lines.js` `LINE_PULL` 0.015、`GHOST` 0.42 的反向深度透出 | `Map3DXRay.swift` 加地面段被山擋住時的半透明一遍 | 比例 0–1 | Presentation（Metal） |

外部專案：月亮位置的公式 Meeus《Astronomical Algorithms》是公開的天文算法，參考已寫成程式，不需要另找；其餘這次沒有另找 GitHub 專案，參考庫已有可移植的實作。

## 4. 五方評分

權重照 NEXT_PRIORITIES §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。評分檔另放 `a91453/railway-assets-private-2` `docs/priorities/RAIL-REFERENCE-1123.md`，下表與它相同。

| 順位 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --: | --- | --: | --: | --: | --: | --: | --: |
| 1 | bug：工具說明指向已刪除的參考庫舊路徑（§2.3 的 19 檔） | 1 | 4 | 1 | 2 | 1 | 1.90 |
| 2 | 平交道黃黑路面與坡道（D） | 3 | 4 | 4 | 4 | 1 | 3.25 |
| 3 | 真實月相與月亮位置（A） | 3 | 4 | 4 | 3 | 1 | 3.10 |
| 4 | 車站依班表點燈、共構站規則（B） | 3 | 3 | 4 | 4 | 1 | 3.00 |
| 5 | 透天立面規則與便利商店色帶（H） | 3 | 3 | 5 | 2 | 1 | 2.85 |
| 6 | 佛光大佛、總統府立面、多良車站（J） | 3 | 3 | 4 | 3 | 1 | 2.85 |
| 7 | 路線透出被山擋住的地面段（L） | 2 | 4 | 3 | 3 | 1 | 2.65 |
| 8 | 29 座古廟的真實輪廓與廟瓦配色（G） | 3 | 2 | 4 | 3 | 1 | 2.60 |
| 9 | 夜空城市光暈（F） | 2 | 4 | 4 | 1 | 1 | 2.50 |
| 10 | 輸電鐵塔與風力機（E） | 2 | 3 | 4 | 2 | 1 | 2.40 |
| 11 | 地標與展館點燈時段（C） | 2 | 3 | 3 | 2 | 1 | 2.25 |
| 12 | 山霧（I） | 2 | 3 | 4 | 1 | 1 | 2.25 |
| 13 | 道路急彎斜接與橋面邊線（K） | 2 | 3 | 3 | 1 | 1 | 2.10 |

（bug 排第一，其餘依加權。）

五方：
- 玩家：看得到、天天會碰到的排前面——平交道是每條地面線都有的，月亮與車站夜燈是每晚都看到的；地標與古廟要走到那裡才看得到；工具路徑玩家看不到。
- 開發：平交道、月亮、光暈、透出都是幾十到兩百行的純幾何或公式，有現成程式可逐行翻；車站點燈要接 `GameWorld` 時刻；古廟要寫工具轉資料；地標與風機要走工作室與看照片三輪，最花工。工具路徑修了下一個讀參考的 session 就不會找不到檔。
- 美術：立面規則最能改變整片城市的樣子（5）；平交道、月相、夜燈、古廟、地標、鐵塔都讓畫面更像台灣；斜接與邊線是細節。
- 鐵道迷：平交道路面與「末班車後車站熄燈」最貼近真實鐵道的日常（4）；多良車站是有名的鐵道景點；古廟、立面、光暈和鐵道無關。
- 音樂：全部沒有關係（1）；遊戲已有的雨聲與天氣音效不因山霧改變。

## 5. 驗證

- VERIFIED（本機 Linux）：`python3 -I tools/golden-checks/doc_numbers.py --check`；assets-2 評分檔 `doc_numbers.py --priorities --root ../railway-assets-private-2`。
- VERIFIED（讀檔）：§0 的舊路徑在新位置都存在；§2.3 的檔案清單由 `grep -rlE 'taiwan-rail-reference-clean|world-rail-reference-clean'` 在 `main` `4fbeda8` 得出。
- UNVERIFIED：參考庫的 JavaScript 沒有執行，沒有在瀏覽器看過它畫出的樣子；§3 的目標檔是設計建議，還沒寫。
