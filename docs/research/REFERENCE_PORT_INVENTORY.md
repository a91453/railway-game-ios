# 私有參考移植盤點：已完成、Phase 7、Phase 8 與其他待辦

更新日期：**2026-10-08（UTC）**。已重新讀 `CLAUDE.md`，並 fetch 兩個 repo 的 `main`：

| 基準 | 固定 commit |
| --- | --- |
| `a91453/railway-game-ios` 的 `origin/main` | `6dfccad069b183cb8dd8bc9f28e124819ef3600d`（PR #217 合併後） |
| 實際 clone 的 `a91453/railway-reference-private` | `5f6ac80c233063c09c4c61571f629881af0b19ec`（加入 `MapBuilder/`） |

本次更新與拆除車站（ARCHITECTURE 決策 83）放在同一個 PR：該 Stage 的參考檢查本來就要讀 `MapBuilder/`，所以順便把 2026-10-07（`e7447f4`／參考庫 `f27339b`）的基準更新到存檔版本 15，補上 `MapBuilder/` 的盤點（§5.4）與 #203–#210 已完成的移植（§2.1）。§3–§5 其他各列沒有重新查閱，仍是 10-07 的判讀。

依 `CLAUDE.md`，**`Ci/`、`Railway/`、`Simulator/`、`MapBuilder/` 都是授權的實作來源**，可直接重用、打包、轉換或調整。未另標條款的作者內容視為可用；明示第三方授權／署名逐項保留。階段表示工作分組，有跨階段相依時可一起移植。部署密鑰、憑證與個資仍不得進公開 repo。

## 1. 判讀方式與目前契約

「已完成」表示目標功能已在上述 main，包含來源調整或在來源缺口上完成的原生規則，不表示整個來源模組照搬。「部分完成」把已使用範圍放在 §2，其餘列到 §3–§5；研究文件合併不等於素材已進 App。參考路徑相對於私有參考庫，使用以下前綴：

| 前綴 | 參考庫路徑 |
| --- | --- |
| C | `Ci/reference_snapshot/` |
| R | `Railway/site_archive_clean/` |
| R3 | `Railway/site_archive_clean/rail-3d/` |
| O | `Railway/railway_game_reference_clean/` |
| T | `Railway/city_world_reference/source/` |
| S | `Simulator/reference_snapshot/` |
| M | `MapBuilder/reference_snapshot/` |

目前 `Sources/GameCore/World/SavedGame.swift` 的 **`currentVersion = 15`**（#210 轉乘群組）；`Tests/GameCoreTests/GoldenScenario.swift` 的 **`schemaVersion = 39`**，讀取端接受 30–39。拆除車站不改存檔格式，兩者都不變。待辦表的四個影響欄是**實作範圍的預估（UNVERIFIED）**，本 PR 只做拆除車站，不執行其他工作：

- **存檔**：「否」表示只做呈現或用既有指令／查詢；「是」表示提案需要新的持久化契約與遷移；「條件式」列出觸發範圍。相容選填欄位不必一律升版：車種、車站狀態、貸款、每週需求已有維持版本的實例。格式讓舊存檔無法讀取時，依 `CLAUDE.md` 升版、加遷移及新 fixture；其他新契約由存檔負責者定案，不預占下一個號碼。
- **golden schema**：新增 fixture 或改變行為不等於一定升 schema；新增指令、觀察、結果名稱或欄位契約才需評估新 schema。行為改變即使不升 schema，也須逐值說明預期差異，不能為過關重寫答案。
- **字串**：指 `RailwayGameApp/Resources/Localizable.xcstrings`，不把站名／模型 metadata 當介面翻譯。`GamePresentation` 的雙語文字可能更新而不動此檔；新增 App 字面字串才加自己的 key 與 `zh-Hant` 台灣用語。
- **地圖**：指地圖呈現、背景、覆蓋層、相機或圖上互動；只改面板／解析記「否」。顯示偏移、LOD、插值不能回寫權威幾何。

## 2. 已完成與部分完成的範圍

本節各項**不再排新的存檔／golden schema 升版、字串或地圖修改**；表內版本是歷史成果，擴充依 §3–§5 判定。證據以 main 的實際檔案為準；[RAILWAY_REFERENCE_MAPPING](../RAILWAY_REFERENCE_MAPPING.md) 與 ROADMAP 的歷史段落仍可能描述當時缺口。

### 2.1 從舊待辦移到完成

| 舊項目／狀態 | 已完成範圍與證據 | 剩餘界線 |
| --- | --- | --- |
| **實景車站資料：已完成**（舊 §3-1） | #143、#147；站等、站碼、地址／座標、月台、相鄰站股道載入並接上建造／面板。`Sources/GamePresentation/{RealStationData,RealRailwayGameplay}.swift`；`Resources/RealRailways/{tra_station_class,tra_station_info,tra_platforms,tra_track_sections}.json`。 | 月台預設用站等的 `estLenByTier` 換成 16 m 節數，單雙線是工具提示；站等運量預設、逐件實測月台匯入仍列 O1。 |
| **最近真實車站命名：已完成**（舊 §3-1） | #143、#147；`GameSession.suggestedStationName(for:at:in:railways:)`、`NetworkSession.swift`，實景新站依最近且未使用的真實站建議中／英文名，保留玩家輸入。 | 不再是等待 Stage E 的缺口。 |
| **九系統營運資料與班距：已完成；停站／run 秒數只讀**（舊 §3-2） | #143、#147；`RealRailwayOperations.swift`、`RealRailwayGameplay.swift`；`Resources/RealRailways/{tra,trtc,krtc,tymc,afr,tmrt,ntdlrt,ntalrt,sanying}.json`。新線符合真實線時用既有 `setLineTargetHeadways` 套用尖峰／離峰班距。 | 來源停站／行車秒數尚未取代核心 `ServiceDwell`／行程，列 O1。 |
| **北捷站碼：已完成**（舊 §3-3） | #143、#147；`RealStationData.swift`、`RealRailwayGameplay.swift`、`RailwayGameApp/Views/StationPanel.swift`、`Resources/RealRailways/trtc_codes.json`。面板顯示北捷及其他系統站碼。 | 無此部分待辦。 |
| **真實時刻表：部分完成**（舊 §3-5） | #147；七份 `*_times.json`、`thsr-schedule.json` 已打包與型別化，保留跨午夜秒數、平假日／指定日期選表，高鐵時刻表可供班距推估。`RealTimetables.swift`、`RealRailwayOperations.swift`。 | **尚未透過 `setTrainTimetable` 逐班匯入遊戲**；台鐵／林鐵 dense、特殊列車與逐班情境列 O1。 |
| **選路、分流、旅程與轉乘：已完成核心**（舊 §5） | #136、#139、#142、#151、#160；同站換車、跨站步行、分級成本、擁擠／需求衰減、新遊戲 `.network` 與切換開關。`Sources/GameCore/Passenger/{PassengerRoutes,PassengerJourney,PassengerCrowding,PassengerDemand,Boarding}.swift`、`NewGame.swift`。群組／餘額在 v11，R3 加 schema 35。 | 真實來源 ID／pairs 匯入列 O2；玩家路網轉乘由核心推導。 |
| **實景轉乘目錄：已完成顯示**（舊 §5） | #147；`RealStationTransfers.swift`、`RealRailwayGameplay.swift`、`Resources/RealRailways/station_transfers.json`。站名正規化、同系統／近距離比對及面板轉乘路線已使用。 | `pairs` 尚未轉成玩家世界的明確步行連結；`transfer_departures.json` 未使用，列 O2／O3。 |
| **正常／限流／封站：已完成手動規則**（舊 §5） | #160 合併決策 65 的 R1–R3；`StationOperationMode`、`GameWorld.setStationOperationMode`、`StationPanel.swift`。限流不釋出新進站運量；封站不上下車／轉乘、不作迄點。選填狀態維持 v11。 | 自動收班狀態、中斷事件列 O4。 |
| **車種與每節定員：已完成**（舊 §5） | #156、決策 66；`TrainType.swift`、`Train.swift`、`GameWorld.setTrainType`、`TrainControls.swift`。九種 `TRAIN_TYPES`、額定 × 1.1、原生門數與選單；選填車種維持版本。 | 車種價格／成本 P7-3，模型對應 P8-1。 |
| **每週需求：已完成**（舊 §5） | #156、決策 68；`StationDemand.swift`、`PassengerDemand.swift`、`GameWorld.setWeeklyDemand`。星期係數、週末形狀、午夜重建與整數釋出；選填開關維持版本。 | 國定假日需求 O4；時刻表的日期選表不等於需求日曆。 |
| **需求事件：部分完成**（舊 §5） | #156、決策 69；`DemandEvents.swift`、`StationDemandText.swift`。展覽／大量人潮、可重現種子、預告與倍率已完成；來源缺席的事件數值採原生規則，當時維持 v11。 | 天氣、停駛、自動封站列 O4。 |
| **城鎮、土地、城市建物與地價：已完成一般城市規則**（舊 §5 RailwayCore 城鎮） | #157；#173 的 6a／6b；#175、#177、#178 的 6c／6d；#181 修正主要用途與封站腹地；#186 示範地圖土地運量。`Passenger/TownGrowth.swift`、`City/{Land,LandDemand,Building,LandValue}.swift`。來源無可讀相同規則，屬 **gap → 原生**。6a v12／36、6c-1 v13／37、6c-2 v14／38、地價 v14／39。 | 64 m 土地、三用途 × D1–D4 容量／升級已完成；公司所有權 P7-2，產業 O10，3D 外觀 P8-2。 |
| **現有公司帳與貸款：已完成** | G1c／G1d 的票價、營運／維修／能源／人事、購車；#156／決策 67 的借還款、每日利息與淨利。`Economy/{Operations,Accounts,GameEconomy}.swift`、`GameWorld.borrow`／`repayLoan`、`EconomyText.swift`、`EconomyPanel.swift`；選填貸款／利息維持版本。 | 折舊、資產負債表與年度決算已完成（決策 85，存檔版本 16）；房地產列 P7-2。 |
| **V4b 逐段路徑／股道／月台偏好：已完成調整**（舊 §5） | #120、#123；`LineRoutePreference.swift`、`ServiceDirections.swift`、`LineJourney.swift`、`ScheduledTraffic.swift`、`GameWorld.setLineRoutePreferences`、`LinesPanel.swift`；v10／schema 32。 | `plan-binding.js`／`dispatch.json` 的共享路徑與等待語義已調整，來源網路／逐班借用資料未全匯入，列 O2。 |
| **V4c 單線服務容量：已完成**（舊 §1） | #125、決策 62；`LineCapacity.swift`，由玩家股道、可停全列月台與站間工作量推導。維持 v10、schema 33。 | 來源沒有可照抄的完整容量公式。 |
| **V4d 中途換向／倒進側線：已完成**（舊 §5） | #131（接續 #128）、決策 63；`ServiceDirections.swift`、`ServiceRun.swift`、`Deadlock.swift`、`RouteReservation.swift`，停妥全列反向、一次反向待避／安全續行。維持 v10、schema 34。 | 無列明停留的折返 easing、推拉外觀 P8-1；多次調車不是已完成範圍。 |
| **V4e 授權與死結位置：已完成**（舊 §1／§5） | #134、#137、決策 64；`GameWorld.contestedResources`／`routeWaits`、`TrafficOverlay.swift`、`MapArt.swift`；授權軌道、等候／死結外圈、互等位置與文字，維持 v10／34。 | 地圖檔案不再是 V4 未合併的占用範圍。 |
| **分析圖層：部分完成**（舊 §5） | #133 腹地圈；#138、#149 人口／旅次；#178 用途／地價／腹地涵蓋。`MapLayers.swift`、`PopulationHeatmap.swift`、`TravelDemandMap.swift`、`CityMap.swift`、`MapLayerSheet.swift`。 | 共線顯示偏移與額外指標 P8-8，不能概括全部分析圖層未做。 |
| **明暗外觀、更名、路線色：已完成目前功能** | `Palette.swift` 隨系統明暗切換；#157／決策 71 的 `renameStation`／`renameLine`／`setLineColor`、`ServiceLine.swift` 與來源 20 色色盤。 | 來源完整夜景／燈光仍列 P8-7。 |
| **復原：已完成**（M，10-08） | #203、#205、決策 82；M `chunks/611-2cd22d6d6f5c40f4.js` 的 `handleUndo`、上限 `B.I6`（25）。`GameSession.performEdit`／`undo`、`ControlPanel` 的復原按鈕。 | 重做（redo）：M 沒有；S 的 `app/simulator/page-38607521e5e99afd.js` 有 `past`／`future` 兩疊（各 80 份，Shift-Z／Y），列 M6。 |
| **路線編輯：已完成三項**（M，10-08） | #208、決策 80；M `611` 的 `handleAddStationToLine`／`ef`、`handleReverseStationOrder`、`handleLineDuplicate`。`LineStopEditing.insertionIndex`、`GameWorld.reverseLineStops`／`duplicateLine`、`LinesPanel.swift`。 | 車站／過路點互換與 `waypointOverrides` 列 M5。 |
| **轉乘群組：已完成**（M＋C，10-08） | #210、決策 81；M 的 `handleCreateInterchange`／`handleRemoveStationFromInterchange`，C 的 `transferGroupId`。`TransferGroup.swift`、`StationPanel.swift`；存檔 15。 | 地圖畫群組連線列 M4。 |
| **拆除車站：本 PR**（M＋C） | 決策 83；M `611` 的 `handleStationDelete`，C `lib/app__q_c234188b7c397f91.js` 的 `confirmDeleteStationAllLines`／`confirmDeleteStationSingleLine`／`_applyRemoveStationFromLine`、封站的 `clearStationWaitingPassengers`。`GameWorld.removeStation`、`ServiceLine.removingStation`、`StationRemoval.swift`、`StationPanel.swift`；存檔、golden schema 不變。 | 只從一條線移除（C 的 single-line）已有 `setLineStops`；C 的里程配額退款不適用（沒有配額經濟，P7-4）。 |
| **繁中／英文：已完成現行介面**（舊 §5） | L1／決策 38；`Resources/Localizable.xcstrings`、`DisplayLanguage.swift` 與 Presentation 文字檔。#171 移除只有 App 名稱的日文 locale，避免錯誤 fallback。 | 沒有整份移植來源所有語言；新增日文等列 O12。 |

表中的核心相對檔名位於 `Sources/GameCore/`，Presentation 相對檔名位於 `Sources/GamePresentation/`，View 位於 `RailwayGameApp/Views/`，`Resources/` 位於 `RailwayGameApp/`。

### 2.2 舊表已完成的基礎，繼續保留

| 來源 | 已完成目標／證據 |
| --- | --- |
| `R/index.html` 的 `buildProfile`、性能表、交會／待避、`updateBlockHolds`；`R3/physical/{topology,overtake-sidings}.js` | `RunningCurve.swift`、`StationDwell.swift`／`ServiceDwell.swift`、V3 `ScheduledTraffic.swift`（#109）、V4a `ScheduledOvertakeTracks.swift`（#116）、`networkSections()`、U2 跟車與預約。觀測／新限速 O7、曲線／坡度選路懲罰 O9。 |
| `R/data/track_lines.geojson`、`track_stations.geojson`、`track_style_layers.json`、`i18n/stations.json`、`data-sources/` | #107 起的 `RealRailways.swift`、`DataSourceCredits.swift`、實景 GeoJSON／`station_names.json` 與來源樣式常數；#118 的三段 OSM 線形修正保留在 `tools/real-railways/`。`rail-discovery.js` 的 `norm` 已用，目錄／導覽 O11。 |
| `O/01_MIGRATION_MAP.md`、`02_W2_IMPLEMENTATION_CONTRACT.md`、存檔／desync 文件 | W2b 停站／誤點：`ServiceDwell.swift`、`TimetableExecution.swift`；指令原子性／固定秒步長：`GameWorld.swift`；裝置存讀：`SavedGame.swift`、`SaveLibrary.swift`；F3b 的 `ReplayFixtures/`、`ReplayFixtureTests.swift`。是契約／行為調整，不是整個 OpenTTD wasm 移植。 |
| `C/lib/app__q_c234188b7c397f91.js` 與教學／DOM／樣式 | 服務時段、班距、區間車、快車／環線：`ServiceLine.swift`；需求、佇列、上下車、票價／帳：`PassengerDemand.swift`、`StationPassengers.swift`、`Boarding.swift`、`Economy/`；運量預設／複製貼上：`GameSession.swift`、`StationPanel.swift`；教學／開始：`Tutorial.swift`、`TutorialSession.swift`、`GameLauncher.swift`、`StartView.swift`；`CITIES` 名稱／座標：`RealWorldMap.swift`。逐時曲線／樞紐 O5；來源人口／行政區不是已移植的城市經濟模型。 |

## 3. 待辦：Phase 7 公司與房地產

[PHASE7_COMPANY_STUDY](PHASE7_COMPANY_STUDY.md)（#179）已合併，**是研究提案，不是實作完成**。目前 `BuildingKind.city/existingStock` 沒有公司所有權。來源地標外觀、商品價格與模型零件價不能當房價。

| 編號／項目 | 可重用來源、接點與缺口 | 升存檔 | 升 golden schema | 動字串 | 動地圖 |
| --- | --- | --- | --- | --- | --- |
| **P7-1 資產成本、折舊、資產負債表：已完成**（決策 85） | `C` 的 `metroEconomyFixedAssets`、期間報表／帳分項；`O/01_MIGRATION_MAP.md` §8。接 `Economy/Accounts.swift`／`Operations.swift`。fixedAssets 是營運量，來源沒有購入成本、折舊或資產負債表，需原生契約。 | **是（提案）**：歷史成本／結算與舊資產遷移。 | **是（提案）**：新資產／折舊／報表觀察。 | **條件式**：`EconomyText` 可提供文字；新 App 按鈕／標題需 key。 | **否**：先做帳與報表。 |
| **P7-2 公司土地／建物買入、自建、收益與出售** | O §8–§9 只列公司／城鎮路徑；T 的 lot／claims、R3 catalog 只供外觀。接 `Land`／`Building`／`LandValue`／`LandDemand`。所有權、成交成本、租金／維護、可選稅、出售損益均是 gap，按 #179 的 7b／7c 提案定案。 | **是（提案）**：所有權、成本、日結游標。 | **是（提案）**：交易／自建指令與物業／損益觀察。 | **是**：交易、報價與條件，也補 Presentation 雙語。 | **是**：選地、所有權、建造預覽；3D 接 Phase 8。 |
| **P7-3 依車種購車價格／營運成本** | `TRAIN_TYPES` 只有容量；`metroPurchaseQuote`／`window.MetroEconomy` 正式引擎缺。接 `TrainType.swift`、`GameEconomy.swift`／`Operations.swift`。車種已存在，價格／成本是原生平衡缺口。 | **否（固定價表）**；保存購入成本則與 P7-1 判定。 | **否（既有指令／帳）**；新報價／成本欄位才升，仍須說明金額差異。 | **條件式**：既有金額格式否；新價目／說明是。 | **否**。 |
| **P7-4 配額經濟與補貼**（舊 §5） | `metroQuotaRingItems`、`metroQuotaPurchaseCatalogItems`、`metroRules().operatingSubsidy` 只有備用 catalog／呼叫端，正式引擎缺。#179 建議維持現金經濟，不等於核定全面排除；採用時補完整購買／退回／消耗契約。 | **是（採持久化配額時）**；補貼沿現有分項另評估。 | **是（新配額指令／觀察）**；純平衡值否。 | **是（採用時）**。 | **條件式**：面板否；建造成本預覽／不足提示是。 |

## 4. 待辦：Phase 8 呈現與素材

逐件路徑、bytes、三角形／解析度、授權、SceneKit／RealityKit／SwiftGodot 處理與缺檔見 [PHASE8_ASSET_INVENTORY](PHASE8_ASSET_INVENTORY.md)（**#185 已合併**）。不沿用舊表的 `du -sh` 粗略量，也不把「盤點完成」標成素材已打包。

Phase 8 只讀 `railwaySnapshot()` 的中心線、縱斷面、結構物、洞口、月台、列車姿態／車身及城市 `Building`／`Land` 查詢。網格、相機、插值、LOD、顯示偏移留在呈現。最小試片沿 #185：E201、C321 頭／中間車、101 far、地面→高架→橋→洞口、兩種月台、三用途 × D1–D4 proxy；六份現存輸入 **3.916 MiB**，轉換產物未量測，不是已完成的 App 增量。

| 編號／項目 | 可重用來源、對應與缺口 | 升存檔 | 升 golden schema | 動字串 | 動地圖 |
| --- | --- | --- | --- | --- | --- |
| **P8-1 列車、軌道、橋梁／高架／隧道、月台**（舊 §4 3D） | `S/models/tra-e201/tra-e201.glb`；S chunks `2694-efba5e23a92b434e`／`5758-131911c5f04a436f`／`4193-d08071182eb33d9c`；`R3/assets/blender-map-v1/`、`integration/{formations,rail-structures,tunnel-portals}.js`、`physical/{turnbacks,timing}.js`。接 S4／車種／車長；40 列車 bin 現存、70 宣告 mesh 缺。真實車型不等於九種 TRAIN_TYPES；Simulator 毫米尺度不當公尺。折返 easing／推拉朝向先作呈現。 | **否（既有幾何／車種）**；新車種規則另案。 | **否**。 | **條件式**：純模型否；新顯示設定是。 | **是**。 |
| **P8-2 城市建物、站房、地標／遠景**（舊 §4 3D／台北包） | `R3/assets/{blender-buildings-v1,historic-buildings-v2}/<目錄>/{model.json,far.mesh.bin}`、`blender-buildings.js`、`station-{catalog,models}.js`；`T/assets/{engine-DKps_Gq_,world-gYgJkZNf,site-*}.js`；C liberty `building-3d`。47 far 為自訂 24-byte 頂點格式，near／宣告 GLB 缺；T 是程序外觀。接 `Building.cells/use/density`，先做 12 種外觀，不重做容量／升級。 | **否（衍生外觀）**。 | **否**。 | **條件式**：純外觀否；圖例／介紹是。 | **是**。 |
| **P8-3 角色、貼圖／動畫**（舊 §4 台北包） | `T/avatars/*.glb`（8 份）、manifest、`T/assets/anim-CQkLTvTS.bin` 與 avatar／rig adapter。meshopt／KTX2、獨立 ANM1 需解碼／對骨／烘焙，GLB 無動畫。缺 avatar／LOD／fallback、Rocketbox MIT 全文見 #185。先作裝飾群眾。 | **否（裝飾）**；可存讀角色玩法另案。 | **否（裝飾）**。 | **條件式**：署名／選擇介面才加。 | **是**。 |
| **P8-4 地形、景觀／虛擬島城**（舊 §4） | `R3/terrain/manifest.json`、`integration/landscape-*`、`C/lib/virtual_island_city__q_21ffa7f6ae58fc9e.js`／OpenFreeMap 樣式。14 地形 chunks 與 `city.pmtiles` 缺，先原生平面／簡單地形或既有 MapKit。土地模擬已完成，不被缺圖磚阻擋。 | **否（背景）**；權威施工地形另訂契約。 | **否（背景）**；新施工契約另評估。 | **條件式**：背景選擇／來源說明是。 | **是**。 |
| **P8-5 圖示、字型／貼圖管線**（舊 §3-7） | C 的 station-icon、line-info、hsr-train-icons、quota-icons／字型；`R/assets/fonts/rail-emoji.woff2`、`tdx-logo.svg`；T 圖像。已盤點、未整批打包。WOFF／WOFF2 需配合 iOS；Icons8 等逐來源核對署名，MTR Sung 明示第三方 copyright 卻缺 grant，單獨補條款。 | **否**。 | **否**。 | **條件式**：換圖／字型否；署名／圖示說明是。 | **條件式**：面板否；圖上符號／文字樣式是。 |
| **P8-6 MapLibre／離線底圖**（舊 §5） | `R/vendor/maplibre-gl.js`、`R/data/{taiwan_land,offline_land_style}.json`、C OpenFreeMap 設定／sprite。目前背景是 `AppleMapBackground.swift`；原生／Web adapter、實際離線圖磚與條款待補，token 設定不打包。 | **否（畫面設定）**；世界保存新背景來源另評估。 | **否**。 | **是（新增背景選項時）**。 | **是**：背景／投影／互動。 |
| **P8-7 完整夜景／夜間看板**（舊 §5） | `R/{night-map,night-board}.js`、`night-theme.css`。Palette 明暗色完成，來源 3D 燈光／看板未整套吸收；讀遊戲時間，不另造模擬時鐘。 | **否**。 | **否**。 | **條件式**：自動外觀否；開關／看板新文字是。 | **是（夜景）**；看板單獨改面板。 |
| **P8-8 共線顯示偏移／額外分析圖層**（舊 §5） | C 的 `metroBranchSharedTrackLaneLayout`；人口／旅次／腹地／用途／地價已完成。挑需用的共線圖樣／指標，不以顯示偏移修正實體股道。 | **否（衍生顯示）**；存新歷史另案。 | **否（既有查詢）**；新觀察另評估。 | **是（新增圖層時）**。 | **是**。 |
| **P8-9 台南一日回放展示**（舊 §4） | `R/memories/tainan-2026-09-12/` 的 snapshot／replay、fleet／station／surroundings 壓縮 mesh、roads。可調整展示場景／Web 檢視器，未進 App。不是 GameCore 的 `ReplayFixtures`；可玩情境另走 O1／O2。 | **否（展示）**。 | **否（展示）**。 | **是（新增入口時）**。 | **是（展示場景）**；Web-only 不動 App 地圖。 |
| **P8-10 車庫圖鑑／收藏展示**（舊 §4） | `R/train-garage{,-catalog}.js`、`train-garage.css`。核心車種已完成，真實車型仍須映射；縮圖宣告不是現存檔，可用現存模型產圖。唯讀圖鑑與保存收藏／解鎖分開定案。 | **否（唯讀）**；持久化收藏需新契約。 | **否（唯讀）**；收藏命令／觀察需評估。 | **是**。 | **否（圖鑑面板）**；旋轉模型是獨立展示。 |
| **P8-11 renderer／相機／資源匯入** | `R3/integration/` 相機／LOD、T engine／workers、S 2D／3D runtime；引擎／轉換見 #185 §3。對同一快照量測載入／幀時間／記憶體；適合的 JS 可直接重用，原生層再調整。尚未選引擎或新增依賴。 | **否**：不存第二份世界。 | **否**。 | **條件式**：新相機／品質／載入介面是。 | **是**：360° 呈現與互動。 |

## 5. 待辦：其他

### 5.1 真實資料、營運與交通規則

| 編號／項目 | 可重用來源、現況與缺口 | 升存檔 | 升 golden schema | 動字串 | 動地圖 |
| --- | --- | --- | --- | --- | --- |
| **O1 真實情境／逐班時刻表匯入**（舊 §3-1／2／5） | `R/data/{tra_schedule_dense,afr_schedule_dense,tra_special_trains}.json`、已解析七份 `*_times.json`／高鐵時刻表；站等需求、實測月台、來源停站／run 秒數。透過既有 `buildStation`／`addTrackPlatform`／`setTrainTimetable` 建局，第一候選仍平溪線。逐班綁車／股道、服務日期與匯入驗證未做；接 `RealTimetables.swift` 或新情境建構器，公尺 ×64、秒 ×1，保留跨午夜。 | **否（既有指令建局）**；保存來源 ID／日期、新停站契約則評估。 | **否（既有 DSL）**；新增逐站停站／匯入欄位才升。 | **是（提供匯入／情境選擇時）**。 | **條件式**：建局沿既有 renderer；地理預覽／進度是。 |
| **O2 真實班表綁定／路徑與轉乘 pairs 匯入**（舊 §5） | `R3/physical/{plan-binding.js,network.json,metro-network.json,dispatch.json}`、`R/data/station_transfers.json`。V4b 調整已完成，exact／retimed／byTrain／跨班 DP 借用、OSM ID → TrackEdgeID、來源 pair → StationID／明確步行 leg 未匯入。群組可能多 pair 連通，不能將全 members 當任意兩站可走；來源 network／dispatch 不直接替換遊戲存檔。 | **否（轉成既有指令）**；保存來源對照／新步行連結時評估。 | **否（既有契約）**；新綁定／連結命令觀察才升。 | **是（提供匯入／綁定操作時）**。 | **條件式**：純轉換否；路徑／步行連結預覽是。 |
| **O3 即時快照／誤點／警報／月台**（舊 §3-6） | `R/api/` 的營運快照（排除部署設定）、`R/{ntm-live-model,rail-platform,rail-platform-ui}.js`、`R/data/transfer_departures.json`。平台偏好不等於 live eventAt／freshness 已搬。先獨立資訊面板；若作世界輸入須在明確時點記錄，網路／系統時間不進 GameCore。 | **否（面板）**；權威外部事件需新契約。 | **否（面板）**；新事件指令／觀察才升。 | **是**。 | **否（先做面板）**；外部列車位置覆蓋層是。 |
| **O4 中斷／自動封站／國定假日**（舊 §5） | C 的 `metroComputeStationAutoOperationMode`、事件呼叫及 `aviation_disruptions__q_dc8f79f5de24b024.js`。手動狀態與展覽／大量人潮完成；天氣／停駛、復原順序、假日需求未做。`RealTimetables.publicHolidays` 只是來源選表，不是模擬事件排程。 | **是（保存事件提案）**；固定情境以既有封站指令執行可維持。 | **是（新事件／日曆契約）**；純既有指令情境否。 | **是**。 | **條件式**：面板否；封站／停駛範圍與徽章是。 |
| **O5 自訂逐時運量／樞紐規則**（舊 §5） | C 的 `bindStationFlowAdjustDrag`、`applyStationFlowHubToggle`。站型預設、總量、複製貼上已完成；逐時拖曳、機場／高鐵倍率尚缺權威曲線，接 `StationDemand.swift`、`StationPanel.swift`。 | **條件式**：保存曲線／樞紐需新欄位；相容選填能否維持版本由存檔負責者定案。 | **是（提案）**：新設定指令／曲線欄位。 | **是**。 | **否（運量面板）**；樞紐地圖圖示另案。 |
| **O6 平交道**（舊 §5） | `R/data/{crossings,rail_crossing_levels}.json` 未匯入。先區分位置／等級標示，與限制列車／道路通行的規則；S4 高架／橋／隧道不等於平交道完成。 | **否（標示）**；施工／通行狀態需評估新契約。 | **否（標示）**；新施工／通行命令觀察才升。 | **是（資訊／操作介面）**。 | **是**。 |
| **O7 觀測曲線／限速區段**（舊 §5） | `R/data/{tra_run_profiles,tra_pass_obs}.json`、`R/index.html` 的 `buildObsProfile`／`SPEED_ZONES`。W1／W2c 計算與移動完成，這批觀測／區段限速尚未接上；分開處理離線情境轉換與玩家可改／需保存的限速。 | **否（轉成既有資料）**；保存新限速／profile 時評估。 | **否（既有契約）**；新限速命令／profile 欄位才升，仍須說明行為差異。 | **條件式**：純轉換否；速限編輯／說明是。 | **條件式**：計算否；限速標示／預覽是。 |
| **O8 Link graph 剩餘的大型流量／重算策略**（舊 §5 RailwayCore） | `O/docs/linkgraph.md`、`01_MIGRATION_MAP.md` §6。群組、廣義成本選路、擁擠、memo 已完成；非同步／分批重算、額外 flow balancing 可評估。文件未提供可讀完整路由演算法，不能再寫成所有乘客路徑都沒有。 | **否（衍生計畫／暫存）**；保存工作／流量歷史另評估。 | **否（契約不變）**；新路徑觀察才升，仍須保持／明訂確定性。 | **否（純計算）**；分析新介面才是。 | **否（純計算）**；新圖層歸 P8-8。 |
| **O9 曲線／坡度與載具別選路成本**（舊 §5 RailwayCore） | O §7、YAPF penalty 符號。V3 站內／停站／月台不合成本、全列 fit 完成；曲線、坡度、平交道、載具別權重未做，來源缺完整值。接 `ServicePath.swift`／`TrainRoute.swift`，符號不是現成常數。 | **否（固定衍生成本）**；存設定／權重才評估。 | **否（格式不變）**；新設定／成本觀察才升，仍須說明選路差異。 | **條件式**：固定值否；設定／新拒絕原因是。 | **否（核心選路）**；成本視覺化另案。 |
| **O10 產業／貨運／補貼需求**（舊 §5 RailwayCore） | O §9、`binary_reference/relevant_source_paths.txt` 的 industry／subsidy 路徑。城鎮／一般建物完成；產業、產消、貨物、貨運旅程沒有可讀規則，仍是原生 gap，可與 Phase 7 資產／補貼相依工作一起安排。 | **是（若實作）**：產業／貨物流量。 | **是（若實作）**：新命令與貨物／產業觀察。 | **是**。 | **是**。 |
| **O17 高鐵專屬經營模式**（舊 §5） | C 的 `getMetroTrainOperationalCap` 高鐵不超載分支及高鐵模式呼叫；高鐵路網／時刻表已載入，專屬容量／票價／成本／服務限制未完成，正式經濟引擎缺。依車種成本／模型分別接 P7-3／P8-1，不把 THSR 資料讀取當模式完成。 | **條件式**：固定資料沿既有狀態否；保存新模式／規則才評估。 | **條件式**：新模式命令／欄位才升。 | **是（新增模式介面時）**。 | **條件式**：面板否；新造型／工具是。 |

### 5.2 資料導覽、語言與其他玩法

| 編號／項目 | 可重用來源、現況與缺口 | 升存檔 | 升 golden schema | 動字串 | 動地圖 |
| --- | --- | --- | --- | --- | --- |
| **O11 營運路線導覽目錄**（舊 §3-4） | `R/rail-discovery.js` 的 `catalog/search/ordered/points/scenes`。`norm`、真實站搜尋、背景線形、營運資料、轉乘面板已用；按營運線站序／顏色導覽與來源場景預設未搬。接 `RealRailways.swift`／`RealRailwayOperations.swift`／`RealWorldPicker.swift`，唯讀，不重排權威班表。 | **否**。 | **否**。 | **是（加入目錄介面時）**。 | **是（導覽／預覽）**：相機、路線強調與站序。 |
| **O12 更多語言／站名英譯品質工具**（舊 §3-8／§5） | `C/lib/{station_name_en_core,china-stationname-quality,international-stationname-quality}*.js`、`C/dist/vendor-pinyin*.js`、`R/i18n/{translations,content-translations}.js`、C locale。台灣站名英譯、繁中／英文介面完成；其他城市品質／拼音、完整日文未採用。`CITIES` 已有其他城市，舊表「只有台灣」不再適用。 | **否（顯示／名稱工具）**：已存玩家名字不重寫。 | **否**。 | **是（新增介面語言）**；純站名資料／拼音工具否；Presentation 語言 API 也需擴充。 | **條件式**：站名／圖例會變；離線品質工具否。 |
| **O13 公車轉乘資訊卡**（舊 §4） | `R/bus-transfer-ui.js`、`i18n/bus-transfer-translations.js`；`/api/bus-transfer` 後端缺，先接可用靜態資料或補資料源，UI 仍可重用。資訊卡不等於新增公車模擬。 | **否（資訊卡）**；公車玩法另訂契約。 | **否（資訊卡）**。 | **是**。 | **否（面板卡片）**；公車圖層另案。 |
| **O14 台北包任務／內容／建造流程**（舊 §4 整包） | `T/assets/{content-Bs2Ca5A2,missions-*,build-*,actors-Cx0CrTrM}.js`。美術／renderer 已拆 P8-2／3／11；任務、互動商品、場景建造不是房地產規則。可調整有用流程，content／world 缺依賴見 #185，不把整包標成已移植或不可用。 | **否（教學／展示）**；保存任務／角色玩法需新契約。 | **否（呈現）**；新權威命令需評估。 | **是（採用互動內容時）**。 | **條件式**：面板否；場景建造／任務位置是。 |
| **O15 Simulator 模板／零件資料匯入**（新增來源） | `S/api/templates/*.json`（9 份／865 放置）、`api/track-sets.json`（6 套／101 零件）、catalog／幾何 chunk。可作展示／建造情境，需明訂模型毫米 → 遊戲公尺／世界單位、轉轍器／接點映射。`priceNTD` 是模型零件估價，不套作遊戲建造費。10-08 補查：`4193` 的零件型錄約 93 種（直軌、曲軌、轉轍器、交叉、雙線、橋），各零件的端點公式與接合判定（距離 ≤ 1.5 mm、角度差 ≤ 1°）、`nodes`／`joints` 拓樸格式（回報未接合、斷開），可對應 `RailwayNetwork` 的節點接合與「接在端點上放置」；路線圖的端點合併 16 mm、列車只有等速（80／160／320 mm/s），沒有加減速、閉塞或號誌。 | **否（既有建造指令）**；新零件狀態才評估。 | **否（既有 DSL）**；新接點／模板命令才評估。 | **是（加入模板選擇時）**。 | **是（預覽／放置）**。 |
| **O16 Web 宿主縮放／存檔 I/O** | `O/web_runtime/` 的雙指縮放、IndexedDB／虛擬檔案系統、匯入匯出。原生已具相機／`SaveLibrary`；這批程式可直接用未來 Web 宿主，尚未完成 Web 產品，包裝既有 `SavedGame` 不另定權威格式。 | **否（既有 SavedGame）**。 | **否**。 | **否（純 Web）**：Web 翻譯另處理。 | **否（iOS）**；Web 地圖／觸控是。 |

### 5.3 MapBuilder（M，10-08 新增來源）

M 是 Next.js 的路線圖編輯器：玩家在地圖上畫路線、車站與轉乘站。專案自己的邏輯在 `chunks/611-2cd22d6d6f5c40f4.js`（編輯指令、自動命名、自動存檔）、`338-b3d18c994bd13868.js`（路線與車站面板）、`352-cc4c9866d08d4d04.js`（地圖圖層、車輛動畫）與 `pages/_app-70b32b07723ca1d7.js` 的常數模組（73277）。其餘 bundle 多是第三方：Mapbox GL JS 3.4.0（專有條款，不重用；遊戲用 MapKit）、Firebase（Apache-2.0）、Turf（MIT，地球半徑 6,371,008.8 m）、recharts／chroma／lodash（`371`）、Mapbox geocoder（`783`）、linkify-it（`650`）。已移植的復原、路線編輯、轉乘群組與拆除車站見 §2.1。

| 編號／項目 | 可重用來源、對應與缺口 | 升存檔 | 升 golden schema | 動字串 | 動地圖 |
| --- | --- | --- | --- | --- | --- |
| **M1 運輸模式表與行車時間估算** | `_app` 的 `H=[...]`：纜車、公車、路面電車、渡輪、BRT、輕軌、捷運（預設）、區域、中長途、高鐵、飛機，各有 `speed`（km／分）、`acceleration`、`pause`（ms）、`defaultGrade`、`useAdminName`；`338` 的 `renderStats` 以「加速、巡航、減速＋每站停留」估算路線時間。可給路線面板快速估算；加入公車／輕軌／渡輪時是模式的起點。定點：速度換 m／分 × 1000、停留換秒。 | **否（只估算）**；路線存模式才是。 | **否（衍生）**；新模式指令才評估。 | **是**。 | **否**。 |
| **M2 車站自動命名** | `611` 的 `ed`／`el`：Overpass 查 25 m 內建物的 `addr:street`、100 m 內具名道路、25 m 內具名建物；`useAdminName` 模式改查行政區（`admin_level` ≤ 8，優先 `name:en`）與 500 m 內道路。實景模式可改用 MapKit 反向地理編碼，照它的優先順序；既有的最近真實車站命名（§2.1）保留在前。 | **否**。 | **否**。 | **是**。 | **否**。 |
| **M3 車站密度與用途分數** | `338` 的 `getInfo`／`fetchAndHandleBuildings`：0.5 × 0.5 英里（647,497 m²）內的 OSM 建物分住宅、旅館、商業、工業、公共、其他，樓高 3.048／3.6576／3.3528 m，`densityScore` 公式與圓餅色。可接實景模式的人口需求與 Phase 6 土地。**缺口**：運量、造價、人口、就業（`/ridership`、`/density`）在伺服器，快照只有欄位名。 | **否（衍生顯示）**；改權威需求才評估。 | **否**。 | **是**。 | **條件式**：面板否；圖層是。 |
| **M4 共線區段並排與轉乘群組連線** | `_app` 的 `$()` 與 `352` 的圖層：共線段依顏色／圖示分組，每條偏移 `奇數 ? ⌊(i+1)/2⌋·8 : 4 + ⌊i/2⌋·8` px、正負交替，線寬 8；轉乘連線是白色 8 px 內線加黑色 2 px 外框。與 P8-8 的 C `metroBranchSharedTrackLaneLayout` 擇一或合併；顯示偏移不改實體股道。 | **否**。 | **否**。 | **否**。 | **是**。 |
| **M5 過路點與 `waypointOverrides`** | `611` 的車站／過路點互換、移除過路點、某線通過某站不停（`waypointOverrides`）。遊戲的「不停」已由服務模式（Q3）表達；過路點對應路網上的路徑，路線本身不需要。若要做，是路線編輯的呈現。 | **條件式**：保存每線不停站才是。 | **條件式**。 | **是**。 | **是**。 |
| **M6 重做（redo）** | M 沒有；S 的 page bundle 有 `past`／`future`（各 80，`canRedo`）。接 `GameSession.performEdit`／`undo`，紀錄只在 session 裡、時鐘前進就清空（決策 82）。 | **否**。 | **否**。 | **是**。 | **否**。 |
| **M7 地圖圖示、線色與色名** | `assets/map/{station,station-discon,transfer,waypoint-dark,waypoint-light}.png`；`_app` 的 21 色預設（第一個未用的顏色、21 條以上隨機）與亮度判斷 `.2126R+.7152G+.0722B > 128`；`assets/colors.json` 的 801 個色名（自訂色找最近的色名）。遊戲已有 20 色預設（`LineColor.presets`，來自 C），換色盤要另行決定。 | **否**。 | **否**。 | **條件式**：色名是。 | **是（圖示）**。 |
| **M8 字型與圖示的授權** | Lato（8 份 `.woff2`，SIL OFL 1.1）；Font Awesome Free 5／6 字型（OFL 1.1）與圖示（CC BY 4.0），`assets/line/*.svg` 也是 Free 6.5.2，使用時保留署名。**`assets/user/*.svg` 13 份裡 12 份標示 Font Awesome Pro 6.2.1（Commercial License）**，這是明示的第三方條款，沒有 Pro 授權不能放進公開 repo，改用 SF Symbols 或 Free 圖示；只有 `basic.svg` 是 Free 6.5.1。 | **否**。 | **否**。 | **否**。 | **條件式**。 |

`edit/new/index.html`、`explore/index.html` 只是 Next.js 外殼；`pages/explore-*.js` 的社群排行（星數、分數）與 Firestore 自動存檔不是本 App 的功能，不列待辦。

### 5.4 舊項目追蹤，避免整包被誤標完成

| 舊表範圍 | 本次去向 |
| --- | --- |
| §3 八項「現在就能平行移植」 | 車站／命名／營運／站碼完成範圍 §2.1；站等需求／實測月台／逐班匯入 O1；目錄 O11；即時資訊 O3；圖示字型 P8-5；站名工具 O12。 |
| §4 的 3D、台南、台北整包、虛擬島城、車庫／公車 | P8-1／2／4／9；台北拆 P8-2／3／11、O14；車庫 P8-10、公車 O13。 |
| §5 的轉乘、每週需求、事件、車種、車站狀態／運量 | 完成範圍 §2.1；真實連結 O2、出發資訊 O3、中斷／假日 O4、客製曲線 O5、專屬高鐵模式 O17。 |
| §5 的配額、平交道、觀測／限速、RailwayCore | P7-4、O6／7／8／9／10；城鎮／建物已完成，公司所有權 P7-2。 |
| §5 的 V4、地圖與翻譯 | V4b–V4e 完成 §2；精確綁定資料 O2、折返／推拉呈現 P8-1；底圖 P8-6、夜景 P8-7、共線 P8-8，更多語言 O12。 |

### 5.5 部署與網站專屬內容

舊表的 `C/api/config.json`、`config__q_7fd2022b8a156b8b.json`、`R/api/basemap-token.json` 是部署設定位置，**不是可公開打包的遊戲資料**。本次不複製內容、不記錄任何值，也不以清理報告推定所有 bundle 都沒有敏感設定。採用 source 時仍須移除密鑰、憑證、部署識別及個資。

帳號、會員、付款、analytics、`terms/`／`privacy/`、`voyager-*`／Supabase 整合屬其他網站服務，目前不列遊戲移植待辦；有用的通用 UI／程式仍可依 `CLAUDE.md` 與個別條款重用，網站政策不能直接當本 App 政策。這兩類本次都**不升存檔／golden schema、不動 Localizable.xcstrings 或地圖**；未來若明確要新增服務，再做具體盤點，不從檔名推出整包禁用。

## 6. 查閱、驗證與接續方式

- **VERIFIED（Linux，靜態查閱）**：fetch 最新 main 並固定以上 commit；讀規則、舊盤點、ROADMAP、ARCHITECTURE 決策 61–78、RAILWAY_REFERENCE_MAPPING 及對應實作／資源；核對 #143／#147 PR 說明、相關合併紀錄，參考 #172／#174／#179／#185 研究。其他 PR 的測試結果不當作本次驗證。
- **VERIFIED（10-08，參考庫 `5f6ac80`，靜態查閱）**：讀 M 的 `REFERENCE_REFRESH_2026-10-08.md`、`SANITIZATION_REPORT.md`、`REFERENCE_FILELIST_2026-10-08.tsv` 與 snapshot 的 `611`／`338`／`352`／`_app` bundle、`assets/`；S 的 page／`4193` bundle 補查。§5.3 的常數與條款逐項對原始碼核對過（模式表、`B.I6`、Font Awesome Pro 標示、接合容差）。
- **VERIFIED（10-07，參考庫 clone，靜態查閱）**：讀 C／R refresh、`Ci/PROJECT_ABSORPTION_GUIDE.md`；O 的 `00_READ_ME_FIRST.md`／`01_MIGRATION_MAP.md`；T 的 `00_READ_ME_FIRST.md` 與 source 目錄；S 的 `REFERENCE_REFRESH_2026-10-07.md`／`SANITIZATION_REPORT.md` 與 snapshot 目錄。待辦路徑按實檔核對，素材明細沿同參考 commit 的 #185，未重做模型轉換。
- **UNVERIFIED**：沒有執行 Swift build／test、Xcode／iOS UI、golden、存檔／重播、素材載入／轉換、效能檢查。影響欄是提案估計；開工時重新 fetch，依實際 diff 定案，不照本表預占版本。

每個後續實作 PR 按 `CLAUDE.md` 做 Reference check，附「參考檔案／函式 → 目標檔案／函式／定點比例」對照與素材增量，保留具體授權／署名。新增 App 檔案／資源時依規則重生 Xcode 專案；字串只加自己的 key。核心規則、存檔、golden 契約、設計紀錄依 `AGENTS.md` 分工，不沿用已結束的 V4 特別授權。本次只更新本文件並開 draft PR，不觸發發佈或合併。
