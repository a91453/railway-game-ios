# 舊網站的程式碼能不能套用到遊戲（參考庫 `Railway/rail-reference/`，2026-11-23，RAIL-REFERENCE-1123）

作者的問題（11-23）：「我只要看我舊有的程序碼能套用遊戲嗎」。`Railway/rail-reference/` 就是作者舊版台灣與世界鐵道網站的快照（11-16 由兩個舊目錄合成，11-23 又加進台灣程序化地景引擎）。這份報告照模組逐一回答，每個模組給四選一：

- **直接用**：資料、數值、設定原樣帶進遊戲或工具。
- **翻成 Swift**：演算法、規則，要寫進 GameCore 或 GamePresentation。
- **當工具用**：node／Python 腳本放進遊戲 repo 的 `tools/` 產資料。
- **不能用**：寫出原因。原因可能是只能在瀏覽器用 WebGL／Three.js 即時畫、會把 `Math.random` 或即時輸入帶進 GameCore、受第三方授權限制，或遊戲已有更好的版本（寫出遊戲那個檔）。

工作量分小（一兩天、幾百行以內）、中（一週內、要接遊戲狀態或新資料）、大（新地圖、新系統，或要走工作室看照片三輪）。

讀的是私有參考庫 main `9298482` 的 sparse checkout，對照的是遊戲 `main` `4fbeda8`。網站沒有跑（協調者改了指示，不拍畫面），程式也沒有執行，分類是讀程式和遊戲檔得來的，**UNVERIFIED**。參考路徑下面都省略 `Railway/rail-reference/`，`TW` 指 `regions/taiwan/source/`，`W` 指 `regions/world/source/`。

這張 PR 只研究，不改程式、不移植。

## 1. 模組逐一判定

### 1.1 資料（`TW/data/`、`W/data/`）

| 模組 | 做什麼 | 判定 | 遊戲目標、工作量 |
| --- | --- | --- | --- |
| `TW/data/tra.json`、`trtc.json`、`krtc.json`、`tmrt.json`、`tymc.json`、`ntalrt.json`、`ntdlrt.json`、`sanying.json`、`afr.json`、`*_times.json`、`thsr_track.json`、`track_lines.geojson`、`track_stations.geojson`、`station_transfers.json`、`tra_station_info.json`、`tra_station_class.json`、`tra_platforms.json`、`tra_overtake_tracks.json`、`tra_track_sections.json`、`trtc_codes.json` | 台鐵、高鐵、各捷運輕軌的路線、站、時刻、股道、轉乘 | **直接用**（**已用**） | `RailwayGameApp/Resources/RealRailways/` 帶的同名檔；GameCore `PassengerRoutes.swift` 讀轉乘 |
| `TW/data/tra_schedule_dense.json`、`thsr_schedule_dense.json` | 台鐵、高鐵全日時刻 | **直接用**（**已用**，經 `tools/real-timetables/` 轉成 `tra-schedule.json`、`thsr-schedule.json`） | — |
| `TW/data/tra_special_trains.json` | 觀光列車與支線 | **直接用**（**已用**） | `BranchLineChallenge.swift`、GameCore `TrainTypeCatalog.swift` |
| `TW/data/thsr_fare.json` | 高鐵票價 | **直接用**（**已用**） | `HighSpeedFares.swift` |
| `TW/data/tw_daytype.json` | 2026 年辦公日曆 | **已用其規則** | GameCore `Holidays.swift`（已翻成規則；遊戲不讀檔，因為遊戲年份會往後走，這份只有 2026） |
| `TW/data/rail_structures_official.json`、`rail_crossing_levels.json`、`crossings.json`、`track_style_layers.json` | 官方橋隧修正、平交道位置與高程、軌道配色 | **直接用**（部分已用：`tools/real-railways/` 讀前兩個；`MapArt.swift` 依配色） | `crossings.json` 平交道位置還沒用，可給平交道路面（§2 的第 1 項）定位，小 |
| `TW/data/tra_run_profiles.json`、`tra_seg_cumdist.json` | 台鐵站間行駛曲線、累計里程 | **直接用** | `RealTrainMotion.swift` 已用同一套曲線的規則；累計里程遊戲由 `tools/real-railways/` 自己算，不用 |
| `TW/data/tra_pass_obs.json`、`tra_pass_obs_model.json` | TDX 歷史誤點觀測與通過時刻模型（2026-10-09～15） | **不能用**（遊戲已有更好的） | 誤點遊戲自己模擬（GameCore），研究用的 `tools/tra-delay-analysis/` 讀的是 `Railway/tdx-snapshot-2026-10/` 341 天的資料 |
| `TW/data/tra_gps_runs.json` | 乘客 GPS 匿名彙整的行駛曲線 | **不能用**（權利） | 來源是乘客資料，檔裡自己寫「僅供私有研究、使用權另見 rights」；權利沒確認前不進遊戲 |
| `TW/data/bus-transfer/`（542 檔）、`bus_stops_index.*`、`bus_providers.json`、`bus_transfer_stations.json`、`transfer_departures.json` | 公車站點與轉乘 | **直接用**（部分已用：`tools/real-buses/` 讀站點索引） | 轉乘出發表沒用；遊戲的公車是自己的路網（`BusRoadNetwork.swift`），用處小 |
| `TW/data/events.json`、`special_ops.json`、`holiday_names.json` | 真實營運公告、臨時班表、假日名稱 | **不能用** | 都是 2026 年的特定日期，遊戲的時間是自己的；臨時班表的規則遊戲沒有對應玩法 |
| `TW/data/music.json` | 網站配樂清單 | **不能用** | 只有清單沒有音檔（快照排除影音），曲子是 Suno 生成，遊戲有自己的配樂（`RailwayGameApp/Resources/Audio`） |
| `TW/data/bounty_rules.json`、`bounty_units.json` | 網站「搭車任務」的門檻（客端與伺服器共讀） | **不能用** | 依賴真實搭乘紀錄與伺服器驗證；遊戲的挑戰是 `ChallengeStory.swift` |
| `TW/data/taiwan_land.json`、`offline_land_style.json` | 離線底圖的陸地與樣式 | **不能用**（遊戲已有） | 遊戲底圖 `RailwayGameApp/Resources/BaseMap`、`RealWorld/taiwan_*.dat` |
| `TW/data/trip_impact_lines.json`（11-23） | 台鐵 12 線、高鐵站序公里 | **不能用**（遊戲已有） | `tools/real-railways/` 從同一來源產生 |
| `TW/data/data_manifest.json`、`data_provenance.json`、`official/` | 資料清單與來源紀錄、官方原始下載 | **直接用**（來源紀錄） | 寫進 `DataSourceCredits.swift` 的依據，已用 |
| `W/data/<城市>.json`、`<城市>_schedule_dense.json`（倫敦、巴黎、東京、紐約、新加坡、雪梨、墨爾本、維也納、伊斯坦堡、布達佩斯、瑞士、挪威） | 12 個城市的官方 GTFS／API 路網與全日時刻，每檔有 `source_notes` 與授權 | **直接用**（**沒用**） | 遊戲海外地圖只有香港、福岡、羅凡涅米（`RailwayGameApp/Resources/MapPacks/`）。開新城市地圖時路網、站、時刻可以直接搬，署名照各檔 `source_notes`（OSM 線形 ODbL、各營運者開放授權）。大（每城一張地圖） |
| `W/data/route_scope.json` | 世界版收錄範圍與品質政策 | **直接用**（當開新城市的檢查清單） | 小 |
| `W/data/` 的台灣同名檔（`tra.json`、`trtc.json`…） | 世界版帶的台灣副本 | **不能用**（重複） | 以 `TW/data/` 為準 |

### 1.2 網頁主程式與介面（`TW/*.js`、`W/*.js`、`TW/app/`）

| 模組 | 做什麼 | 判定 | 遊戲目標、工作量 |
| --- | --- | --- | --- |
| `TW/main-reference.js`、`W/main-reference.js`（1.2 MB，1,445 個函式） | 網站本體：地圖、依時刻推算列車位置、搜尋、時刻表檢視、日型 | **大部分不能用，少數規則已翻成 Swift** | 已用：`RealTrainMotion.swift`（依時刻推位置）、GameCore `Holidays.swift`（`TW_DAYTYPE`）、`InterfaceMotion.swift` 的轉北（`resetMapNorth`）。其餘是 DOM 與 MapLibre 介面，遊戲有自己的 SwiftUI 畫面 |
| `TW/rail-3d.js`、`W/rail-3d.js` | 3D 圖層入口 | **不能用**（WebGL） | 遊戲的 3D 是 Metal（`Map3D*.swift`） |
| `TW/rail-discovery.js`、`W/rail-discovery.js` | 「去哪裡」導覽與路線瀏覽 | **不能用**（遊戲已有） | 遊戲的路線清單與景點（`AttractionCatalog.swift`） |
| `TW/rail-platform.js`、`rail-platform-ui.js` | 即時月台看板比對（StationLiveBoard） | **不能用** | 依賴即時資料 API |
| `TW/ntm-live-model.js` | 淡海、安坑輕軌即時推估 | **不能用** | 即時資料 |
| `TW/night-board.js`、`night-map.js`（兩區） | 夜間看板與地圖配色 | **不能用**（遊戲已有） | `Map3DNight.swift`、`DayNight.swift` |
| `TW/bus-transfer-ui.js` | 三階段轉乘卡 | **不能用** | 網頁介面；遊戲沒有真實轉乘導航玩法 |
| `TW/train-garage.js`、`train-garage-catalog.js`、`train-garage-scenes.js` | 車庫（車型收藏與展示） | **不能用**（遊戲已有） | 遊戲的車種型錄（`TrainRoster.swift`、`TrainPortrait.swift`）；收藏依真實「護照」搭乘紀錄，遊戲沒有 |
| `TW/app/`（273 檔：iOS widget、Android 外殼、`RailNativeL10n.json`） | 網站的原生 App 外殼與小工具 | **不能用** | 遊戲本身就是原生 App；Widget 的時刻資料遊戲已有 |
| `TW/i18n/`、`W/i18n/` | 介面與站名的中英日翻譯 | **直接用**（站名部分） | 遊戲站名英文在 `RealRailways/station_names.json`；日文遊戲沒有。開海外城市地圖時，城市站名的翻譯可直接搬，小 |
| `TW/assets/`、`TW/vendor/`、`*.css` | 網站圖示、字型、Three.js、樣式 | **不能用** | 樣式是網頁的；Three.js 只在瀏覽器用 |

### 1.3 3D 圖層（`TW/rail-3d/`、`shared/rail-3d/`、`W/rail-3d/`）

| 模組 | 做什麼 | 判定 | 遊戲目標、工作量 |
| --- | --- | --- | --- |
| `rail-3d/integration/tunnel-portals.js`、`portal-clearance.js`、`tunnel-apertures.js` | 隧道口位置與淨空 | **翻成 Swift**（**已翻**） | `Map3DTunnels.swift`、`Map3DTrench.swift` |
| `rail-3d/integration/rail-structures.js`、`profile-lines.js` | 高架、路堤與縱坡；路線疊地形 | **翻成 Swift**（**已翻**；11-23 新加的山擋線透出沒翻） | `DoubleTrack.swift`、`TrackSlopes.swift`；透出 → `Map3DXRay.swift`，小 |
| `rail-3d/integration/map3d.js` | 地下層透視 | **翻成 Swift**（**已翻**） | `Map3DXRay.swift` |
| `rail-3d/integration/camera-motion.js`、`follow-framing.js`、`follow-camera-lock.js` | 跟車鏡頭 | **翻成 Swift**（**已翻**） | `Map3DFollow.swift` |
| `rail-3d/integration/train-path.js`、`terrain-elevation.js`、`rail-clearance.js`、`layer-order.js`、`readability.js` | 列車沿軌道的位置、取地面高、軌道淨空、圖層順序 | **翻成 Swift**（**已翻**，散在 `RealTrainMotion.swift`、`Map3DStreaming.swift`、`TrackSlopes.swift`） | — |
| `rail-3d/integration/train-lighting.js`、`train-halo.js`、`train-halo-style.js`、`headlight-spill.js` | 列車燈、地面光暈、前燈投光 | **翻成 Swift**（部分已翻） | `Map3DTrainLights.swift`、`Map3DHeadlamp.swift`；地面光暈 `headlight-spill` 沒翻，小 |
| `rail-3d/integration/formations.js`、`FORMATIONS.md` | 62 款車型的編組與尺寸出處 | **直接用**（**已用**） | `tools/five-section-lrt/`、`three-car-urban/` 等 |
| `rail-3d/integration/landscape-trees.js` | 沿線樹木 | **翻成 Swift**（遊戲已有自己的） | `Map3DScene` 的樹與 `tools/worldcover/` |
| `rail-3d/integration/place-guide.js`、`view-controls.js` | 網站導覽、觀看設定 | **不能用** | 網頁介面 |
| `rail-3d/environment/sun.mjs` | 太陽位置 | **翻成 Swift**（**已翻**） | `Map3DSunPath.swift` |
| `rail-3d/environment/station-hours.js`、`model-hours.js`、`venue-hours.js`（11-23） | 車站依班表亮燈、共構站規則、展館點燈 | **翻成 Swift**（規則）＋**直接用**（展館時段） | `Map3DNight.swift`＋新 `Map3DStationHours.swift`；中 |
| `rail-3d/terrain.js`、`terrain-source.js`、`geo.js`、`shared/rail-3d/terrain.js`、`geo.js`、`landcover/` | 地形、座標、地表覆蓋 | **當工具用**（**已用**） | `tools/worldcover/build_landcover_grid.py`、`RealWorld/taiwan_heights.dat`；地形執行時不用 JS |
| `rail-3d/station-catalog.js`、`landmark-catalog.js`、`station-layer.js`、`station-models.js`、`landmark-models.js`、`blender-buildings.js` | 12 個車站複合體與地標清單、站體模型 | **直接用**（清單、尺寸）；模型**不能用** | 清單已給 `StationLandmarks.swift`、`Map3DStations.swift`；模型依 CLAUDE.md 的 model-look 由工作室照照片重做原生版 |
| `rail-3d/assets/`（156 檔：Blender 站體、車庫 JSON） | 車站、車輛的 Blender 原始檔與尺寸 | **直接用**（尺寸 JSON） | `tools/sanying/` 已讀 `garage-blender-v1/sanying.json`；其餘可給工作室當尺寸依據，各案小 |
| `rail-3d/garage-scenes/`（31 檔：十分、集集、阿里山、嘉義、新竹、文湖、高捷、北捷……） | 各站的 Three.js 微縮場景 | **不能用**（WebGL 場景）；尺寸與配置可參考 | 遊戲各站由工作室做原生站房（決策 937 十分、932 菁桐等）；`crossing-cycle.js` 的落桿時序（車頭到前落桿、車尾清空才開）可**翻成 Swift** 給 `Map3DCrossingGate.swift` 對照，小 |
| `rail-3d/garage-scenes/consist-3d.js`、`separate-coplanar.js` | 轉向架共用路徑、車身俯仰；同平面閃爍分離 | **翻成 Swift**（遊戲已有對應） | 遊戲的車身沿軌（`TrainCars.swift`）；同平面問題由 kit 測試處理 |
| `rail-3d/physical/network.json`、`level-profiles.json`、`dispatch.json`、`metro-network.json`、`display-profiles.json` | 實體股道網、縱斷面、派車表 | **直接用**（**已用**） | `tools/real-railways/` → `rail_tracks.json`、`rail_structures.json`、`rail_dispatch.json` |
| `rail-3d/physical/topology.js`、`motion.js`、`timing.js`、`reservations.js`、`overtake-sidings.js`、`turnbacks.js`、`route-runtime.js`、`plan-binding.js`、`metro-motion.js`、`afr-timing.js`、`afr-operation.js`、`client.js` | 網站的列車執行期：沿股道動、佔用預約、待避、折返 | **不能用**（遊戲已有更好的版本） | GameCore 的閉塞與調度：`BlockSections.swift`、`RouteReservation.swift`、`SwitchInterlocking.swift`、`ScheduledOvertakeTracks.swift`、`HeadwayOvertake.swift`。網站的版本是「把時刻表畫成動畫」，不解衝突；遊戲要決定性、要處理玩家改的線。阿里山推拉規則（`afr-operation.js`：機車端固定）若做阿里山線可**翻成 Swift**，小 |
| `rail-3d/physical/portal-paths.js`、`display-level.js`、`structure-kind.js` | 隧道口切線、示意列車高度、結構種類 | **翻成 Swift**（`structure-kind` 已用；其餘遊戲已由 `TrackSlopes.swift` 處理） | — |
| `W/rail-3d/`（22 檔，大多是 `shared/` 的轉接） | 世界版 3D | **同台灣版** | — |

### 1.4 程序化地景引擎（`TW/landscape-engine/`，11-23 新增，59 檔）

細節在附錄 A（§A.1.1）與附錄 B 的對照表。總結：

| 模組 | 判定 | 遊戲目標、工作量 |
| --- | --- | --- |
| `engine/integration/level-crossing.js` | **翻成 Swift** | 新 `Map3DLevelCrossingDeck.swift`，小 |
| `engine/shared/sky-ephem.mjs` | **翻成 Swift** | `Map3DSunPath.swift`、`Map3DSky.swift`，小 |
| `engine/shared/night-sky.mjs`（城市光暈） | **翻成 Swift** | `Map3DSky.swift`，小 |
| `engine/shared/tw2-infra.mjs`（鐵塔、風機） | **翻成 Swift** | 新 `Map3DPowerLines.swift`，中（風場位置要另找資料） |
| `engine/tw-facade.js`、`kit-building-appearance.js`、`kit-city-atlas.js`、`hill-styles.mjs`、`cvs-look.mjs` | **翻成 Swift**（規則與尺寸表） | `Map3DFacadeVariety.swift`、`Map3DRealFacade.swift`，中 |
| `heritage-geometry.mjs`、`places/heritage.json`、`tw2-temple.mjs` | **直接用**（29 座輪廓）＋**翻成 Swift**（裁瓦、配色） | `tools/temples/`、`RealTemples.swift`，中 |
| `foguang-buddha.mjs`、`presidential-facade.mjs`、`models/duoliang/model.json` | **直接用**（尺寸、部件色）給工作室 | 工作室地標單，大 |
| `follow-rain.mjs`、`road-ribbons.mjs`、`deck-lines.mjs`、`surface-markings.mjs`、`night-city.mjs`、`street-objects.mjs` | **翻成 Swift**（遊戲多已有對應，挑缺的補） | `Map3DRain.swift`、`RoadSmoothing.swift`、`Map3DRoadBridge.swift`、`Map3DRoadMarkings.swift`，各小 |
| `engine/main.js`、`buildings.worker.js`、`tile.worker.js`、`fetch-v.mjs`、`fx2.mjs`、`fx3.mjs`、`terrain.mjs`、`proj/tm2.mjs`、`airports.js`、`host-stubs.js` | **不能用** | 依賴瀏覽器 worker、不在庫內的圖磚與宿主；遊戲地形、投影、機場已有自己的（`TerrainMap.swift`、`AirportCatalog.swift`） |

### 1.5 資料處理腳本（`TW/scripts/` 560 檔、`W/tools/` 68 檔）

| 模組 | 做什麼 | 判定 | 遊戲目標、工作量 |
| --- | --- | --- | --- |
| `TW/scripts/verify_*.mjs`（398 檔）、`TW/verify_*.mjs`、`diag_*`、`probe*`、`scan*`、`audit*`、`TW/fixtures/`、`TW/memories/` | 網站的回歸測試、診斷與測試資料 | **不能用** | 測的是網頁行為；遊戲有自己的 Swift 測試 |
| `TW/scripts/fetch_tra*.py`、`fetch_thsr*.py`、`fetch_tdx.py`、`fetch_tra_station_of_line.py`、`fetch_shapes.py`、`build_tdx.mjs` | 從 TDX 下載台鐵、高鐵資料 | **當工具用**（部分已改寫） | `tools/real-timetables/rebuild_tra_schedule.py` 已照 `fetch_tra_schedule.py`、`densify_schedule.py` 重寫；`tools/tdx-batch/`。TDX 要金鑰，遊戲端用 Python 重寫比搬 node 好，各小 |
| `TW/scripts/build_physical_routes.mjs`、`build_physical_track_graph.py`、`pack_physical_network.mjs`、`repair_physical_*.mjs`、`extend_tra_*.mjs`、`splice_*_profiles_*.mjs`、`build_tra_overtake_tracks.mjs`、`build_tra_track_sections.mjs`、`build_rail_structures_official.mjs`、`build_rail_levels.mjs`、`build_flat_rail_grade.mjs`、`optimize_physical_dispatch.*` | 產生實體股道網、縱斷面、待避線、派車 | **當工具用**（產出已用；腳本本身沒搬） | 產出 `physical/*.json` 已由 `tools/real-railways/` 讀。要重產股道網時才需要搬這批，大（彼此相依、還要 OSM） |
| `TW/scripts/build_metro_times.mjs`、`metro_times_gapfill.mjs`、`build_trtc_segtimes.mjs`、`build_thsr_schedule.mjs`、`build_thsr_fare.mjs`、`build_station_transfers.mjs`、`build_afr*.mjs` | 捷運、高鐵、林鐵時刻與轉乘 | **當工具用**（產出已用） | 要更新到新班表時搬進 `tools/real-timetables/`，各小 |
| `TW/scripts/build_crossings.mjs`、`build_crossing_levels.mjs` | 平交道位置與高程 | **當工具用** | 產出 `crossings.json` 可給平交道路面定位，小 |
| `TW/scripts/build_worldcover.py` | 地表覆蓋 | **當工具用**（**已用**） | `tools/worldcover/` |
| `TW/scripts/import_blender_*.py`、`import_garage_blender.py`、`import_historic_buildings.py` | Blender 站體匯入 | **不能用**（遊戲已有） | 遊戲由工作室 kit 產原生模型，`tools/glb-to-m3dmodel/` |
| `TW/scripts/build_music_data.mjs`、`build_aeo_pages.mjs`、`build_metro_pages.mjs`、`build_i18n_station_names.mjs`、`build_data_manifest.mjs`、`build-ofm-style.mjs`、`build_landscape_style.mjs`、`build_bounty_units.mjs`、`build_tainan_memory.mjs`、`bus_live_core.mjs`、`tra_wait_core.mjs`、`trtc_*`、`tainan_actuals.py` | 網站配樂、SEO 頁、底圖樣式、任務、即時看板 | **不能用** | 網站專用 |
| `W/tools/build_<城市>.mjs`、`build_<城市>_timetable.mjs`、`build_<城市>_i18n.mjs`、`gtfs2rail.mjs`、`headway2sched.mjs`、`fetch_lta_train_gtfs.mjs`、`build_*_shapes.py`、`check_line_geometry.mjs` | 12 個城市從 GTFS／OSM 產路網與時刻 | **當工具用**（`headway2sched` 的做法已用在香港） | 開新城市地圖時放進 `tools/<城市>-map/`；`tools/hk-map/build_hk_mtr.py` 已照 `build_singapore.mjs` 的做法。各城中 |
| `W/tools/verify_*.mjs`、`analyze_city_visual_scope.mjs`、`audit_route_coverage.mjs`、`W/tools/dev/` | 世界版測試 | **不能用** | 網頁測試 |
| `W/tools/fleet/`（24 個 Python，110 款東京車型的參數化產生器） | 日本通勤電車、地鐵、私鐵車型網格 | **當工具用** | 有東京地圖時給 `tools/train-models/`；照片的 Commons 授權寫在各車設定，要照抄署名。大 |
| `TW/prototypes/tiny-trains/`（95 檔，Blender 小火車型錄） | 台灣車型的 Blender 型錄與來源 | **直接用**（`catalog-source.json` 的尺寸與來源） | 工作室做車時當尺寸依據，各案小 |

## 2. 結論

以檔案數算：快照約 3,900 個檔，其中程式檔（`.js`、`.mjs`、`.py`）982 個。程式檔約**八成不能用**，裡面將近一半（463 個）是網站自己的測試與診斷，其餘是網頁介面、App 外殼、瀏覽器 WebGL 場景，以及網站的列車執行期（遊戲 GameCore 已有更完整的閉塞與調度）。約**兩成能用**，大約 200 個，要翻成 Swift 或當工具用：3D 與地景的規則、數值約 80 個（其中 3D 圖層那批多半已經翻過），產資料的腳本約 110 個，車型型錄約 10 個。**資料**（JSON）大多可以直接用：台灣的幾乎都已進遊戲，世界 12 城一個都還沒用。

最值得先套的五項（評分在 §3）：
1. 平交道黃黑路面與坡道（`level-crossing.js`＋`crossings.json` 定位）→ 翻成 Swift，小。
2. 真實月相與月亮位置（`sky-ephem.mjs`）→ 翻成 Swift，小。
3. 車站依班表點燈、共構站規則（`model-hours.js`）→ 翻成 Swift，中。
4. 世界 12 城的路網與時刻（`W/data/`＋`W/tools/build_<城市>.mjs`）→ 直接用＋當工具用，開新地圖時用，大。
5. 透天立面規則與便利商店色帶（`tw-facade.js` 等）→ 翻成 Swift，中。

另有一項 bug：`tools/` 有 19 檔的說明與範例指令還寫已刪除的舊路徑（附錄 A §A.2.3）。

## 3. 五方評分（只評最值得先套的）

權重照 NEXT_PRIORITIES §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。評分檔在 `a91453/railway-assets-private-2` 的 `docs/priorities/RAIL-REFERENCE-1123.md`，內容與下表相同。

| 順位 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --: | --- | --: | --: | --: | --: | --: | --: |
| 1 | bug：工具說明指向已刪除的參考庫舊路徑（19 檔） | 1 | 4 | 1 | 2 | 1 | 1.90 |
| 2 | 平交道黃黑路面與坡道 | 3 | 4 | 4 | 4 | 1 | 3.25 |
| 3 | 真實月相與月亮位置 | 3 | 4 | 4 | 3 | 1 | 3.10 |
| 4 | 車站依班表點燈、共構站規則 | 3 | 3 | 4 | 4 | 1 | 3.00 |
| 5 | 世界 12 城路網與時刻（新城市地圖的資料） | 4 | 2 | 2 | 5 | 1 | 2.90 |
| 6 | 透天立面規則與便利商店色帶 | 3 | 3 | 5 | 2 | 1 | 2.85 |

（bug 排第一，其餘依加權。）

五方：
- 玩家：平交道每條地面線都有，月亮和車站夜燈每晚都看得到；新城市是全新的地圖可玩（4），但要等地圖做好；工具路徑玩家看不到。
- 開發：平交道和月亮有現成程式可以逐行翻（4）；點燈要接 `GameWorld` 的時刻；新城市要做整張地圖（2）；工具路徑修好後，下一個讀參考庫的 session 就找得到檔。
- 美術：立面規則最能改變整片城市的樣子（5）；平交道、月相、夜燈都讓畫面更像台灣；新城市的資料本身不帶畫面（2）。
- 鐵道迷：官方 GTFS 的真實路網與全日時刻最真（5）；平交道路面和「末班車後車站熄燈」貼近真實鐵道的日常（4）。
- 音樂：都沒有關係（1）。

## 4. 驗證

- VERIFIED（本機 Linux）：`python3 -I tools/golden-checks/doc_numbers.py --check`；評分檔 `--priorities --root ../railway-assets-private-2`。
- VERIFIED（讀檔）：各模組在遊戲有沒有用，是在 `Sources/`、`tools/`、`RailwayGameApp/Views`、`docs/` 裡用檔名逐一 grep 得來；附錄 A §A.0 的舊路徑在新位置都存在。
- UNVERIFIED：網站沒有跑，參考的 JavaScript 沒有執行；「不能用」的原因是讀程式得來的。

---

## 附錄 A：11-23 這次的更新與舊路徑

（RAIL-REFERENCE-1123 原本的題目。節號前加 A。）

### A.0 目錄怎麼變的（11-16）

- `Railway/taiwan-rail-reference-clean/` 與 `Railway/world-rail-reference-clean/` 已**刪除**，換成 `Railway/rail-reference/`（`INVENTORY.json` 的 `replaces`）。
- 換算規則：舊 `taiwan-rail-reference-clean/source/X` → `rail-reference/regions/taiwan/source/X`；舊 `taiwan-rail-reference-clean/rights/` → `rail-reference/regions/taiwan/rights/`；世界版相同，換成 `regions/world/`。兩區相同、不靠相對網址的 15 個 3D ES Module 移到 `shared/`，原路徑留 `export * from` 轉接檔，所以舊檔名都還在。
- 遊戲引用過的舊路徑在新位置逐一確認都在：`rail-3d/physical/`、`data/tra_schedule_dense.json`、`data/tra_special_trains.json`、`data/station_transfers.json`、`data/track_style_layers.json`、`main-reference.js`、`rail-3d/integration/{portal-clearance,tunnel-portals,rail-structures,camera-motion,map3d}.js`、`rail-3d/assets/garage-blender-v1/sanying.json`、`rail-3d/README.md`、`data/data_provenance.json`、`app/THIRD_PARTY_NOTICES.md`、世界區的 `source/docs/HANDOFF-2026-10-01.md` 與 `source/tools/build_singapore.mjs`。

### A.1 11-23 新增與更新了什麼

`SOURCE_UPDATE_2026-11-23.json` 記上游 `bedd0d1` → `cc9d461`：新增 63、更新 100、移除 5 個路徑。在參考庫裡實際落成：`8f337fa` 加 63 個檔、改 6 個；`2e20ab5` 加 2 個、刪 5 個、改 140 個（多半是去識別的文字清理）。

#### A.1.1 新增：台灣程序化地景引擎 `regions/taiwan/source/landscape-engine/`（59 個檔）

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

#### A.1.2 新增：`rail-3d/environment/` 的營運時間（4 個檔）

| 檔 | 內容 | 來源、日期 |
| --- | --- | --- |
| `station-hours.js` | 每站每天（索引 0＝週日）第一班到最後一班有旅客的分鐘數，涵蓋台鐵、高鐵、北捷、高捷、中捷、機捷、阿里山林鐵…… | 由 `scripts/build_landscape_station_hours.mjs` 從班表產生（**產生器不在庫內**）；班表是庫內的 2026-10-16 台鐵與各系統時刻 |
| `model-hours.js` | 站體點燈規則：共構站任一系統有旅客就亮（台北、板橋、南港、新左營、新烏日、高鐵桃園……）；古蹟舊站房、展館和現役客站分開 | 程式本身 |
| `venue-hours.js` | 展館、紀念建築的開放或外觀點燈時段，每月休館日 | 文化資產局開放資料（`data.boch.gov.tw`）、政府資料開放平台、各館公告 |
| `station-name.js` | 站名比對鍵 | — |

#### A.1.3 新增：`data/trip_impact_lines.json`

台鐵 12 條、高鐵 1 條的依序站名與累計公里，加上「對號／非對號」車種分類、繞行線（`WL-C`、`CZ`）。來源：TDX v3 `Rail/TRA/StationOfLine`（2026-10-28T00:44:33Z）。產生器 `scripts/build_trip_impact_lines.mjs` **不在庫內**。

#### A.1.4 更新

- `rail-3d/integration/profile-lines.js`：路線疊在地形上時，深度沿視線往鏡頭拉近 `LINE_PULL`（0.015），被山坡擋住的地面段另畫一遍反向深度的半透明「透出」（`GHOST` 0.42）；遠處淡出。只畫地面段，山岳隧道照舊被山擋。
- `rail-3d/integration/rail-structures.js`：夜色調整可處理依種類分色的運算式（`hasColor`），換底圖時沿用基礎光。
- `rail-3d/integration/place-guide.js`：前往地點時若地形還沒載入，不用 0 當高程（山區會繞海平面轉），抵達後重算一次中心高度；拿掉下拉選單。
- `rail-3d/environment/sun.mjs`：只改一行註解。遊戲的 `Map3DSunPath.swift` 逐行譯自這個檔，**計算沒變，不用跟改**。
- `2e20ab5` 清理：`data/tra_special_trains.json`（台灣、世界兩份）的新聞來源網址改成空字串、其他值不變（`dataValueAndStructurePreservationCheckPassed`）；`prototypes/tiny-trains/blender/tw-v2/catalog-source.json` 同類清理；文件、i18n 去識別。
- 移除：`scripts/launch_watch.mjs`、`usage_split.mjs`、`lib/cf_analytics.mjs`、`lib/stadia_projection.mjs`、`verify_stadia_projection.mjs`（網站的分析與部署工具，遊戲沒用過）。

#### A.1.5 授權總結

- 程式：Three.js MIT（`rail-3d/vendor/three-LICENSE.txt` 保留）；其餘是業主自己的程式，依 CLAUDE.md 視為授權可用。
- 資料：OSM 衍生的（道路、地點中心與高度）照 ODbL，進遊戲時在 `DataSourceCredits` 已有的 OSM 那一行；國土測繪中心描繪的廟宇輪廓與 TDX、文化資產局資料是政府資料開放授權，進遊戲時要加一行署名。
- 沒有新的 copyleft 或無授權第三方程式碼。

### A.2 遊戲已經用了什麼、還沒用什麼

#### A.2.1 已用（從 `rail-3d/`，在 11-16 之前以舊路徑讀）

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

#### A.2.2 還沒用（11-23 的新東西全部沒用）

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

#### A.2.3 還指向舊路徑的地方與改法

舊路徑在新庫已不存在，照 §A.0 的規則一律換成 `Railway/rail-reference/regions/taiwan/source/…`（世界版 `regions/world/source/…`）。

| 位置 | 數量 | 建議 |
| --- | --: | --- |
| `CLAUDE.md` 參考庫清單 | 1 段 | **本 PR 已改**：換成 `Railway/rail-reference/`，寫換算規則與 11-23 的地景引擎 |
| `tools/` 的 README 與腳本用法說明：`real-railways/{README.md,extract_tracks.py,extract_structures.py,measure_osm_offset.py}`、`real-timetables/{README.md,extract_branch_runs.py,rebuild_tra_schedule.py}`、`tra-delay-analysis/{README.md,analyze.py}`、`real-world-population/{README.md,build_water_grid.py}`、`hk-map/{README.md,build_hk_mtr.py}`、`map3d-preview/README.md`、`real-coaches/README.md`、`real-buses/README.md`、`five-section-lrt/README.md`、`three-car-urban/README.md` | 19 檔 | 改成新路徑（下一張工具 PR；腳本都是用參數收路徑，只改說明與範例指令） |
| 寫進產出資料的字串：`tools/real-timetables/extract_tra_schedule.py` 的來源說明、`tools/five-section-lrt/bundle.py`、`tools/lrt-pair/bundle.py`、`tools/three-car-urban/bundle.py` 的 `private_reference_use`、`tools/sanying/source-record.json` | 5 檔 | **不改**：它們進 App 帶的 `RailwayGameApp/Resources/RealRailways/tra-schedule.json` 與模型包的來源記錄，改了資料雜湊跟著變；記錄的是當時讀的位置，照實保留。下次重新產生時再寫新路徑 |
| 程式註解：GamePresentation 13 檔（`BranchLineChallenge`、`DoubleTrack`、`HighSpeedFares`、`Map3DFollow`、`Map3DHeadSigns`、`Map3DStreaming`、`Map3DTrainLabels`、`Map3DTrench`、`Map3DTunnels`、`Map3DXRay`、`RealTrainMotion`、`RealWorldMap`、`TrackSlopes`）、GameCore 3 檔（`Holidays`、`PassengerRoutes`、`TrainTypeCatalog`）、`Tests/GameCoreTests/HolidayTests.swift`、`RailwayGameApp/Views/MapArt.swift` | 18 檔 | 下次動到該檔時順手改；不值得單獨開一張動 GameCore（會跑完整一層 CI） |
| `docs/decisions/`（123 檔）、`docs/research/`（25 檔）、`docs/ARCHITECTURE.md`、`docs/RAILWAY_REFERENCE_MAPPING.md`、`docs/art/`（19 檔） | 170 檔 | **不改**：歷史紀錄，記的是當時讀的路徑；靠 CLAUDE.md 的換算規則找新位置 |

## 附錄 B：11-23 地景引擎可移植項目的對照表

以下全部屬 Presentation（`Sources/GamePresentation/`，Metal shader 在 `Map3DShaders.metal`）。沒有一項碰遊戲規則，**不進 GameCore**，所以沒有定點比例；Presentation 用 `Float`，單位照參考是公尺、度、分鐘。班表點燈讀的是 `GameWorld` 已有的時刻（玩家的線）或 App 帶的真實時刻，不另存狀態。

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
