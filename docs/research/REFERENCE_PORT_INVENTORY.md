# 私有參考的未移植盤點：V4 期間能平行移植什麼

查閱日期：**2026-10-05（UTC）**。基準：本 repo `main` 的 **`77b0443`**（V4a 合併後），私有參考 `a91453/railway-reference-private` `main` 的 **`2db0c5a`**（`25229af` 的 `Railway/` 更新與 `2db0c5a` 的 `Ci/` 更新都在內）。下文的參考路徑都相對於私有參考的根目錄，大小是 `du -sh` 的結果。

2026-10-05 作者表示 `Railway/` 網站不再維護，私有參考固定在 `2db0c5a`。實景鐵道的路線形狀之後由本 repo 自己修正（`tools/real-railways/`，PR #118）。

目的：Codex 正在依 [ROADMAP 的 Stage V](../ROADMAP.md#stage-v--dispatcher待避交會與月台分配) 做 V4b–V4e。這份筆記列出私有參考裡還沒移植的內容，並把它們分成三類：現在就能平行移植、不會影響 V4 的；要等 V4 合併以後才能做的；以及不能放進這個公開 repo 的。

本筆記是唯讀盤點：只新增這一份文件，沒有修改 GameCore、golden、存檔、重播 fixture、測試、CI、ROADMAP、ARCHITECTURE 或 RAILWAY_REFERENCE_MAPPING。「可以移植」是研究判斷，開工時仍照 CLAUDE.md 的 Reference check，在 PR 裡附對照表。

## 1. V4 會占用的範圍

V4 的範圍來自 ROADMAP 的 V4a 段落與 [ARCHITECTURE 決策 60](../ARCHITECTURE.md#60-同向待避的實體股道窗口stage-v4a) 的「後續順序」：

| 階段 | 內容 | 已知的版本號 |
| --- | --- | --- |
| V4b | 逐段指定路徑、股道與月台 | 存檔 10、golden schema 32 |
| V4c | 單線容量（修正線路的最多列車數，決策 22） | — |
| V4d | 中途換向與倒進側線 | — |
| V4e | 授權範圍與死結的圖示 | — |

查閱時 GitHub 上還沒有 V4b 的分支或 PR，所以下面的檔案清單是依範圍推估，**UNVERIFIED**。決策 60 寫明作者授權 V4 修改核心、獨立模型與設計紀錄，取代 AGENTS.md 的分工；V4 期間這些檔案視為 Codex 在改：

- `Sources/GameCore/Railway/*`（特別是 `ScheduledTraffic`、`ScheduledOvertakeTracks`、`ServicePath`、`ServiceLine`、`LineJourney`、`RouteReservation`、`TrainMovement`、`Deadlock`、`Timetable`）、`Sources/GameCore/World/GameWorld.swift`、`SavedGame.swift`；
- `GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、`Tests/GameCoreTests/Reference*.swift`、`.github/scripts/swift-shards.sh`（V4a 已用到 `campaigns-18`）；
- `docs/ARCHITECTURE.md`（下一個決策編號 61）、`docs/ROADMAP.md` 的 Stage V、`docs/RAILWAY_REFERENCE_MAPPING.md`；
- 地圖與營運畫面：`RailwayGameApp/Views/MapView.swift`、`MapArt.swift`、`TrainControls.swift`、`LinesPanel.swift`、`TimetableEditor.swift`；
- `Sources/GamePresentation/RealWorldDemo.swift` 與它的測試：V4a 在 `RealWorldDemoTests` 加了猴硐待避的驗收，後續階段很可能再用到。

**關鍵限制**：任何新的 GameCore 狀態都要升存檔版本與 golden schema。V4b 用掉 10／32，現在另外開工一定會撞號，所以 V4 期間能平行做的只有**不進 GameCore** 的部分。

## 2. 已經移植的（對照）

詳細對照見 [RAILWAY_REFERENCE_MAPPING](../RAILWAY_REFERENCE_MAPPING.md) 與 [WEB_REFERENCE_STUDY](../WEB_REFERENCE_STUDY.md)。

- `Railway/`：
  - `buildProfile` 與性能表移植成 `RunningCurve`；交會與待避推估成為 V3 的 `ScheduledTraffic`；`overtake-sidings.js` 與 `overtakeTrackFree` 成為 V4a 的 `ScheduledOvertakeTracks`；`topology.js` 成為 `networkSections`；`updateBlockHolds` 成為 U2 的跟車距離；停站規則成為 `StationDwell`。
  - 實景鐵道的 `track_lines.geojson`、`track_stations.geojson`、`track_style_layers.json`、`i18n/stations.json` 與 `data-sources/` 已移植（`RealRailways`、`DataSourceCredits`）。`rail-discovery.js` 只移了 `norm`。
  - 實景鐵道的高捷紅線（機場段）、橘線（鹽埕埔段）與林鐵祝山線一段，改用 OpenStreetMap 重畫（PR #118）。
- `railway_game_reference_clean/`：停站與誤點（W2b）、存檔遷移、desync 重播（`ReplayFixtures/`）、指令與固定步長。
- `Ci/`：服務規劃（時段、班距、交路、快車、環線）、地鐵停站與性能、需求、排隊、上下車、票價與帳本、車站客流面板、教學、`CITIES` 城市清單、存檔與開始畫面。

## 3. 現在就能平行移植（不碰第 1 節的檔案）

依建議的順序排列。每一項都只新增檔案，透過既有的 `GameWorld` 指令建立內容，不新增 GameCore 狀態。

| 順序 | 內容 | 參考來源 | 放在哪裡 | 注意 |
| --- | --- | --- | --- | --- |
| 1 | 實景車站資料：車站等級、站碼、站址與座標、月台範圍、相鄰站的單雙線 | `Railway/site_archive_clean/data/` 的 `tra_station_class.json`（4 KB，210 站）、`tra_station_info.json`（36 KB，246 站）、`tra_platforms.json`（16 KB，197 站實測、42 站推估）、`tra_track_sections.json`（40 KB，243 個相鄰站對） | `RailwayGameApp/Resources/RealRailways/` 加一個新的 GamePresentation 檔 | 用途：依站等級套用需求預設（`setStationDemand`）、實景月台長度，以及 ROADMAP Stage E 列為還沒有的「依最近的真實車站替新車站命名」。`tra_platforms` 來自 OSM，照 ODbL 1.0 在 `DataSourceCredits` 標示出處。不改 `RealWorldDemo` 現有的四台列車與驗收。 |
| 2 | 各系統的營運資料：每條線的站序、尖峰／離峰班距（peakHeadwaySec、offpeakHeadwaySec）、停站秒數（dwellSec，部分系統有） | `Railway/site_archive_clean/data/` 的 tra.json（260 KB）、trtc.json（107 KB）、krtc.json（43 KB）、tymc.json（36 KB）、afr.json（153 KB）、tmrt.json（5 KB）、ntdlrt.json（11 KB）、ntalrt.json（8 KB）、sanying.json（18 KB） | 新的 GamePresentation 檔，用既有指令套用班距 | 停站秒數若要改 StationDwell 屬於 GameCore，等 V4 合併後再做。 |
| 3 | 台北捷運站碼（例如 BL12） | `Railway/site_archive_clean/data/trtc_codes.json`（6 KB） | RealRailways 的站名顯示 | 只用在顯示。 |
| 4 | 路線導覽目錄（各系統的營運線、站序、顏色） | `Railway/site_archive_clean/rail-discovery.js`（12 KB，目前只移了 `norm`） | `RealRailways.swift`、`RealWorldPicker.swift` | 只讀路網，照來源的註解是唯讀功能。 |
| 5 | 真實時刻表轉成遊戲時刻表 | `data/tra_schedule_dense.json`（7.3 MB，1,159 班）、`afr_schedule_dense.json`（24 KB）、七份 `*_times.json`（約 2.1 MB）、`api/thsr-schedule.json`（156 KB）、`tra_special_trains.json`（28 KB） | 新的 GamePresentation 情境建構器，用 `buildStation`、`addTrackPlatform`、`setTrainTimetable` 等既有指令 | 只做到時刻表為止：把每班車綁到實體股道（`plan-binding.js` 與 `dispatch.json`）就是 V4b，等 V4b 合併後再接。整份台鐵時刻表 7.3 MB，先只打包一條線（[TIMETABLE_DATA_STUDY](../TIMETABLE_DATA_STUDY.md) 的第一個候選是平溪線）。 |
| 6 | 即時資料快照的顯示（列車位置、誤點統計、警報、月台標示） | `Railway/site_archive_clean/api/`（18 個檔，684 KB；**`basemap-token.json` 除外**，見第 6 節）、`ntm-live-model.js`（12 KB）、`rail-platform.js` 與 `rail-platform-ui.js`（各 4 KB） | GamePresentation 加一個新的 App 畫面，不畫在 `MapView` 上 | 只是畫面，模擬不讀它，所以不影響 deterministic。要變成世界的輸入時，照 TIMETABLE_DATA_STUDY 在明確時點記錄，那就是 GameCore 的工作了。 |
| 7 | 圖示與字型 | `Ci/reference_snapshot/` 的 `station-icon-*`（7 個 PNG）、`line-info-*`（2 個）、`hsr-train-icons/`（16 KB）、`quota-icons/`（8 KB）；`Railway/site_archive_clean/assets/` 的 `fonts/rail-emoji.woff2`、`tdx-logo.svg` | `Assets.xcassets`、`Resources` | `icons8-*` 照 Icons8 的條款標示出處。`Ci/` 的 `fonts/mtr-sung.woff2`（3.2 MB）先確認授權再用。字型另外要在 Info.plist 登記。 |
| 8 | 其他城市的站名英譯、品質規則與拼音 | `Ci/reference_snapshot/lib/` 的 `station_name_en_core`（212 KB）、`china-stationname-quality`（16 KB）、`international-stationname-quality`（76 KB）；`dist/vendor-pinyin`（296 KB） | GamePresentation | 優先度低：實景鐵道目前只有台灣，這些規則用在 `Ci/` 的中國、香港等城市。 |

## 4. 可以做，但現在不建議

| 內容 | 參考來源 | 為什麼不建議 |
| --- | --- | --- |
| 3D 車輛、建築與地形 | `Railway/site_archive_clean/rail-3d/assets/`（49 MB）、`rail-3d/vendor/`（1.3 MB，three.js、pmtiles）、`rail-3d/integration/` | Phase 8 的 renderer 還沒有，現在放進 App 只會讓它變大。 |
| 台南一日回放 | `Railway/site_archive_clean/memories/tainan-2026-09-12/`（4.9 MB） | 同上；要放可以放在 `Web/`，不進 App。 |
| Taipei GTA 整包 | `Railway/taipei_gta_reference/source/`（21 MB：three.js 遊戲、地標、任務、角色 GLB、啟動畫面） | 同上。 |
| 虛擬島城 | `Ci/reference_snapshot/lib/virtual_island_city`（16 KB） | 參考庫只有腳本，它讀的 `city.pmtiles` 圖磚不在快照裡，搬不完整。 |
| 車庫收藏、公車轉乘卡 | `Railway/site_archive_clean/train-garage*.{js,css}`（約 64 KB）、`bus-transfer-ui.js`（84 KB） | 車庫要有車種才有意義（車種是 GameCore 狀態，見第 5 節），縮圖也不在快照裡；公車轉乘卡的 `/api/bus-transfer` 後端不在快照裡。 |

## 5. 等 V4 合併以後

**會新增 GameCore 狀態**（V4b 合併後從新的 `main` 開工，排在存檔 11／schema 33）：

- 轉乘與路徑選擇（Phase 5C、5F）：`Ci/` app.js 的 `metroTransfer*`；`Railway/site_archive_clean/data/station_transfers.json`（200 KB）、`transfer_departures.json`（188 KB）。
- 每週需求與平假日：app.js 的 `metroWeeklyDemand*`。
- 事件與中斷：app.js 的 `metroEvent*`、`lib/aviation_disruptions`。
- 車種與每節定員：app.js 的 `TRAIN_TYPES`（A 型 310、B 型 260、C 型 200 人等）。
- 車站狀態（限流、封站）、自訂客流曲線、配額經濟（快照只有呼叫端，沒有引擎）、高鐵模式。
- 平交道：`data/crossings.json`（92 KB）、`rail_crossing_levels.json`（12 KB）。
- 觀測行駛曲線與限速區段：`data/tra_run_profiles.json`（824 KB）、`tra_pass_obs.json`（200 KB）、`index.html` 的 `buildObsProfile` 與 `SPEED_ZONES`。
- RailwayCore 參考包剩下的：linkgraph、城鎮與產業、曲線與坡度的選路成本。

**就是 V4 本身**：`rail-3d/physical/plan-binding.js`（12 KB）、`dispatch.json`（3.2 MB）、`network.json`（4.3 MB）、`metro-network.json`（1.3 MB）是 V4b；`rail-3d/physical/turnbacks.js` 與 `timing.js` 的 `turnbackProgress` 是 V4d。

**會改地圖畫面**（V4e 改的是同一批檔案）：

- MapLibre 與離線底圖：`Railway/site_archive_clean/vendor/`（1.1 MB）、`data/taiwan_land.json`（64 KB）、`offline_land_style.json`；
- 夜間模式：`night-map.js`、`night-board.js`、`night-theme.css`；
- `Ci/` 共用軌道的偏移（`metroBranchSharedTrackLaneLayout`）與地圖上的分析圖層。

**會大改 `Localizable.xcstrings`**：`Railway/site_archive_clean/i18n/translations.js`（英文與日文）、`content-translations.js`，以及 `Ci/` 的簡體中文 locale。每個 key 都要加一種語言，必然和 V4 新增的字串衝突。

## 6. 不能放進這個 repo

這個 repo 是公開的（CLAUDE.md：secrets 與 credentials 不進版控）。

| 檔案 | 內容 |
| --- | --- |
| `Ci/reference_snapshot/api/config.json` 與 `config__q_7fd2022b8a156b8b.json` | AMap key 與 `securityJsCode`、Supabase anon key、Stripe live publishable key |
| `Railway/site_archive_clean/api/basemap-token.json` | Esri 底圖 token |

帳號、會員、付款與法律頁（`Ci/` 的 `voyager-*`、`vendor-supabase`、`terms/`、`privacy/`）沒有遊戲內容。`Ci/reference_snapshot/privacy/` 是另一個網站的英文 GDPR 隱私權政策，不適合當作這個 App 的隱私權政策。

## 7. 和 V4 同時作業的規則

- 只新增檔案，不改第 1 節列出的檔案。
- 不升 `SavedGame.currentVersion`（目前 9）與 golden schema（目前 31）；不改 `swift-shards.sh`，新的測試 class 自動跑在 `rest` shard。
- 不新增 ARCHITECTURE 的決策編號，需要記錄的設計決定寫在 PR 說明裡，等 V4 合併後再補進設計紀錄。
- App 的新字串優先經由 GamePresentation 的 `language.text(...)`；一定要加進 `Localizable.xcstrings` 時，只加自己的 key，每個都附 `zh-Hant`（AGENTS.md）。
- App 新增的檔案（包括 `Resources/` 裡的資料檔）會改 `.xcodeproj`：用固定版本的 XcodeGen 重新產生並提交；衝突時也是重新產生，不手動合併。
- 打包的資料檔會讓 App 變大，PR 裡寫出增加的大小。

## 8. 怎麼做出這份盤點

- 依 `git show --stat` 列出私有參考最近兩次更新（`25229af`、`2db0c5a`）改了什麼，讀兩份 `REFERENCE_REFRESH_2026-10-05.md`、`Ci/PROJECT_ABSORPTION_GUIDE.md`、`railway_game_reference_clean/00_READ_ME_FIRST.md` 與 `01_MIGRATION_MAP.md`、`taipei_gta_reference/00_READ_ME_FIRST.md`。
- 「已移植」以本 repo 的 RAILWAY_REFERENCE_MAPPING、WEB_REFERENCE_STUDY、TIMETABLE_DATA_STUDY、ROADMAP 與 `Sources/` 的對應名稱為準。
- 資料檔的筆數以 Python 標準函式庫讀 JSON 得出；含金鑰的檔案只確認了欄位名稱，沒有把值寫進任何地方。
- V4 的檔案清單是推估（**UNVERIFIED**），V4b 的分支出現後應以實際 diff 校對。
