# 貨運研究：三個玩法方案與建議

狀態：**供作者選擇，未實作**。只寫文件，不改 App、GameCore、GamePresentation；存檔版本、ARCHITECTURE 決策編號、golden schema 都不動（工作登記 #231，branch `claude/freight-study`）。

盤點基準：`railway-game-ios` 的 `main` `b45e95b`（存檔版本 35、決策到 147、golden schema 56；另有 148–152 已被進行中的 session 登記），以及 2026-10-11 複製的 `a91453/railway-reference-private` `581db83`。本文的數字分三種：**來源**（讀到的檔案或網頁）、**量測**（`tools/freight-study/` 的腳本在已提交的資料上算出）、**原生起始值**（本文提議，gap，未經 `BalanceReportTests` 量過，只是讓方案能手算，不是結論）。

## 0. 摘要

1. **參考庫沒有貨運的規則或資料可以移植。** 沒有貨物種類表、產業表、貨運班次、運價、貨車車種，也沒有運煤史料。能用的只有三塊：OSM 的台鐵貨運線與貨運倉儲輪廓（ODbL）、一份 OpenTTD 的 link graph 文件（概念）、城市世界的送貨任務結構與一條時限公式（個人運送，不是鐵路貨運）。貨運的規則要原生設計，這點與 ROADMAP 的 O10（「沒有可讀規則，仍是原生 gap」）一致。
2. **外部專案全是只讀概念。** OpenTTD 是 GPL-2.0，Simutrans 是 Artistic License 1.0，A 列車系列是商用專有；本專案一行都不複製。可借的是結構：貨物易腐度、車站評等、產業產量隨服務浮動、城鎮成長要有被服務的車站。
3. **GameCore 的接點很乾淨。** 土地已有 `LandUse.industrial`（實景地圖的工業區 457 km²，每格 29 個就業），城市成長與建物升級集中在 `LandDemand.growLand`，帳本是 `LedgerItem` 加欄位。決策 137 的「外地連絡站」與 `distanceDemand` 示範了「世界開關＋選填存檔欄位」的做法，貨運照這個做法就不動既有 golden、存檔與 replay。
4. **一個量測改變了設計：實景地圖上工廠離車站很遠。** 全台工業區只有 4.5% 在台鐵車站 1 公里內（500 公尺內 1.0%）。貨運的集貨範圍不能照乘客的 800 m，玩家也必須「拉專用線」到工廠——這正好是這個遊戲自由鋪軌的強項。
5. **建議：先做最小版（方案 C）的核心，再往 A 列車式資材（方案 A）長。** 兩者共用同一套貨物、貨車、車站庫存與運費帳；C 約 3 個 PR 就有完整的貨運迴圈，A 再加 3 個 PR 把貨運接到城市成長。OpenTTD 式產業鏈（方案 B）工作量約 8 個 PR 以上，列為之後再說。詳見第 7 節。

## 1. 範圍與沒有做的事

- 做了：參考庫逐來源盤點（含全庫關鍵字搜尋）、外部專案概念與授權、GameCore 現況對照、一支量測腳本、三個方案與建議。
- 沒有做：任何遊戲程式碼；沒有新增資源檔；沒有取得歷史運煤的產量與路線（外部也查不到可靠數字，見第 8 節）。
- 與進行中工作的界線：#300–#326 待決項目（決策 148–150）、自製 OSM 底圖（151）、Tokyo 程序化城市（152）、史實劇本（劉銘傳鐵路）與故障事件研究，本文都不改它們的檔案。底圖若要畫工業或港口，是 151 的範圍；史實劇本若要做運煤，是第 6.4 節的接點。

## 2. 參考檢查：參考庫對照表

依 CLAUDE.md 的清單查了 `Ci/reference_snapshot/`、`Railway/site_archive_clean/`、`Railway/railway_game_reference_clean/`（先讀 `00_READ_ME_FIRST.md`）、`Railway/city_world_reference/`、`Simulator/`、`MapBuilder/`，另外 repo 根目錄還有 `OpenWorld/` 與 `Website/`，一併查了。方法：全庫以 `freight|cargo|貨運|貨物|貨車|運煤|coal|煤礦|資材|建材|物資|倉庫|industry|factory|wagon` 做關鍵字搜尋，再對命中的檔案取上下文，JSON 用 Python 檢查鍵與欄位。

### 2.1 有內容的項目

| 參考的檔案或函式 | 內容 | 可移植性 | 遊戲裡要接的地方 |
| --- | --- | --- | --- |
| `Railway/site_archive_clean/rail-3d/physical/network.json`：`ways[]` 中 `tags["railway:traffic_mode"] == "freight"` | 台鐵 OSM 貨運線 33 個 way（共 5,637 個 way）：`service=yard` 27、`crossover` 3、`siding` 2、無 service 1（名稱「臺中港線」，軌距 1067 mm，25 kV／60 Hz）。另有 4 個名為「隆田車站東側貨運待避線」；`nodeTags` 有 4 個「貨櫃場」節點。（已用 Python 重數 33 與分類，與盤點一致） | 資料可直接用（OSM，ODbL，要在 `DataSourceCredits` 標示） | 實景地圖的貨運專用線與調車場幾何；方案 C／A 的「貨運站」預設位置 |
| `Railway/site_archive_clean/rail-3d/assets/historic-buildings-v2/jingtong-coal/`（`model.json`、`catalog.json`、`placement.json`、`far.mesh.bin`） | 「菁桐站與選洗煤場」，新北市，錨點 [121.72392636, 25.02388123]，寬 139.0 × 深 66.6 × 高 16.3 m；部件含菁桐站房、選洗煤場（OSM way 281242237）、保存站區月台；footprint 為 GeoJSON Polygon；授權標註 ODbL-1.0 | 輪廓可直接用；mesh 是美術資產（P8） | 平溪線運煤劇本的「煤礦產業」位置與輪廓；`Phase 8` 資產盤點（`PHASE8_ASSET_INVENTORY.md`）已列同一個目錄 |
| 同目錄 `dounan-warehouses/`、`longtian-warehouses/`、`taoyuan-warehouse/`、`erjie-granary/`、`qiaotou-sugar/`、`chiayi-sawmill/` | 斗南倉庫群（約 100 × 127 m）、隆田儲運站與倉庫群（43 × 381 m）、桃園舊倉庫、二結穀倉、橋頭糖廠（127 × 355 m）、嘉義製材所；欄位 `id/name/county/category/kind/features/sources[]/placementStatus/anchor/estimatedDimensionsM` | 輪廓可直接用；視覺是美術資產 | 貨運倉儲設施與農產加工類產業的位置、尺寸參考 |
| `Railway/railway_game_reference_clean/docs/linkgraph.md`（30 行） | OpenTTD 的 link graph 說明：cargodist 的 MCF（multi-commodity flow）為何放獨立執行緒、重算時間與精度取捨。沒有程式碼或資料。同目錄 wasm（`railway_core_15_3.wasm`）內含 "OpenTTD" 字串，來源是 OpenTTD（GPLv2）的 build | **只是概念**；不從 wasm 反推原始碼 | 遠期的貨物流量分配（方案 B 的 B4）；GameCore 的 `PassengerRoutes` 已有自己的路徑圖，貨物可共用 |
| `Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §5（165–180 行）、237 行 | 建議把 CargoPacket 改成 `PassengerPacket{originStationID, destinationStationID, nextTransferStationID, count, createdTick}`；237 行「local, express, freight and depot moves can choose differently」只是路徑成本權重 | 概念 | 貨物的「群組」資料結構：沿用 `WaitingGroup`／`RidingGroup` 的做法，多一個貨物種類欄位 |
| `Railway/railway_game_reference_clean/binary_reference/relevant_source_paths.txt` 第 4、5、12 行（`src/cargopacket.cpp`、`src/cargotype.cpp`、`src/industry_cmd.cpp`）、`relevant_symbols_and_settings.txt` 第 38、71 行 | 只有符號與路徑，沒有原始碼；wasm 內有約 271 行含 "cargo" 的字串（`difficulty.industry_density`、`IndustriesChangeInfo` 等） | 無法用，只當 OpenTTD 概念目錄 | `RAILWAY_REFERENCE_MAPPING.md` 已把「產業」列為 gap，本文沿用 |
| `Railway/city_world_reference/source/assets/missions-CgvPSaGo.js`（任務 `mk-teadelivery`） | 任務資料模型 `{id, category, reward, repeatable, start, giver, steps[]}`；步驟 `enterVehicle` → `drive(target, timeLimit)` → `exitVehicle` → `interact`；貨物只是文字「新茶」，沒有種類或數量 | 結構可參考；數值是固定值 | 若之後做「專案運送」類的劇本任務（方案 A 之後的選配），可借這個模型；與鐵路貨運本身無關 |
| `Railway/city_world_reference/source/assets/content-DcQ2Whr5.js` 的 `s2_delivery`（外送） | 限時公式 `jp=(e,t,n)=>Math.round(28+n/6.2)`（n 為路程，單位推測為公尺）；到達給錢，沒有扣分 | 公式可直接翻成 Swift，但是個人外送，不是鐵路 | 方案 C 的「限時貨」選配（易腐貨的時限）可借「基本秒數＋距離÷常數」的形式；常數仍要自訂 |
| `Simulator/reference_snapshot/api/templates/Nxq1plIzDmWIf5VQjyFQ.json`（「四組道岔的貨物調車場」） | Kato N 規軌道拼裝，`layout.placed[85]`（`trackId/x/y/rotation/turnoutRoute`），不是貨運資料 | 配置資料可用 | 遠期：貨運調車場的軌道配置範本 |
| `Railway/site_archive_clean/train-garage-catalog.js` | 只有 `ppcoach`（推拉自強「客貨車」）名稱帶「貨」；機車有 R 系（含調車用 DHL100）與 E 系電力機車。**沒有貨車車種** | 機車清單可用 | 貨運列車的牽引動力選項；貨車本身要自訂 |
| `Railway/site_archive_clean/data/crossings.json`、`data/tra_special_trains.json`、`index.html` | 備註「貨運／專用／已停用線平交道不在模擬路網上」；平溪線 story「運煤鐵道轉生的人文支線」；猴硐「昔日產煤重鎮」。只有文字，沒有數量、年代、噸位 | 文字可用，數據零 | 劇本的說明文字 |

### 2.2 已查、沒有貨運內容

- `Ci/reference_snapshot/`：只命中中國高鐵車廂音效檔名與 mdi 圖示字型（`mdi-truck-cargo-container`）；`virtual_island_city` 的 `harbour` 只是地圖樣式顏色。
- `MapBuilder/reference_snapshot/`、`Website/`：無。
- `OpenWorld/reference_snapshot/`：只有機車後箱 `cargoBox` 的 3D 外觀選項。
- 真實時刻表：`Railway/site_archive_clean/data/tra_schedule_dense.json` 對 `貨`、`freight`、`cargo` 搜尋為 0，車種只有自強、莒光／復興、區間快、區間車、其他，來源是台鐵開放資料的旅客列車。**沒有貨物列車班次**；`tra.json`、`tra_station_info.json`、`tra_run_profiles.json` 同樣沒有。
- **運煤史料：沒有。** 全庫搜尋 `運煤|煤礦|採煤|煤業|礦業|礦坑|選洗煤|煤炭`，只命中上表的文字與 jingtong-coal 輪廓；沒有產量、年代、噸位、礦場位置、煤運站。
- **貨物種類、產業表、貨運運價、貨車車種、台鐵貨運班次：都沒有。**

### 2.3 授權提醒

參考庫的 OpenTTD 文件與 wasm 來源是 GPLv2 專案。依 CLAUDE.md，這份 repo 是作者自己的授權範圍，但內含的 OpenTTD 內容仍帶它自己的授權：只讀概念，不複製文字或碼，不反編譯 wasm。OSM 來源的輪廓是 ODbL，用了要在 `DataSourceCredits` 標示（現有的實景資料已有這個機制）。

## 3. 外部專案（只讀概念）

| 專案 | 授權 | 可否複製 | 本文用到的概念 |
| --- | --- | --- | --- |
| OpenTTD | 程式碼 GPL-2.0（`COPYING.md`）；OpenGFX 圖像同為 GPL-2.0 | **否**（copyleft）。圖像也不拿 | 貨物易腐度、車站評等、產業產量浮動、城鎮成長與被服務車站數、集貨半徑 |
| Simutrans | Artistic License 1.0（官方 README 與 `LICENSE.txt`）；各 pakset 的資料授權不一，現況未查到 | 理論上可，需遵守修改標示與散布條款；本專案是 Swift 重寫，**只讀概念** | 產業鏈（煤礦→發電廠）、供電提升工廠產量、消費端只吃生產端的一部分 |
| A 列車系列（Artdink） | 商用專有（依一般情況判斷，未查授權條文） | **否** | 資材工廠→貨運站→資材置場→建築工地的物流，資材庫存是建築的門檻 |
| Transport Fever 2 | 商用專有 | **否** | 貨物供給對城鎮成長有加成（只有玩家社群說法，不可當規格） |

### 3.1 OpenTTD 的貨物與產業（來源：wiki.openttd.org 的 Manual／Game Mechanics 頁）

- **貨物與運費。** 運費＝基礎費率 × 貨量 × 起訖站距離 × 時間係數；時間係數由 `days1`、`days2` 劃出快／中／慢三段。完整公式在 wiki 的圖裡，文字抓不到，**公式本身未查到**。溫帶費率（基礎費率／days1／days2）：煤 5916／7／255、貨品 6144／5／28、鋼 5688／7／255、鐵礦 5120／9／255、穀物 4778／4／40、牲畜 4322／4／18、乘客 3185／0／24。**概念：** 大宗貨（煤、鐵礦）`days2`＝255，幾乎不受時間影響；易腐貨（牲畜、乘客）時間一拖運費就掉。
- **車站評等**（每貨種分開算，點數÷255）：最後裝貨車輛速度（0–17%）、車齡（0 年 33 點、1 年 20、2 年 10）、距上次取貨的時間（<15 為 130 點，逐級降到 60–105 的 25 點）、等候貨量（<100 為 +40，1001–1500 為 −35，>1500 為 −90）；每 2.5 天重算一次、每次最多動 2 點；評等低於 50% 開始掉貨。**概念：** 服務越勤、車越快、貨堆越少，來的貨越多。
- **產業。** 原生產業每月產 8–9 次；平滑經濟下運送率超過 60% 產量傾向上升、低於 60% 傾向下降。鏈：煤礦→發電廠；鐵礦→鋼廠→工廠；森林→鋸木廠→貨品→城鎮；農場→食品廠→食物→城鎮。二級產業投入對產出的比例**未查到**。
- **城鎮成長。** 50 天內鎮影響範圍內最多 5 個車站有裝卸任何貨物，成長加快，貨種不限；亞北極與亞熱帶的沙漠城鎮要送食物（與水）才會成長。**概念：** 貨運與城市成長的連結是「有被服務」，不是特定貨物的量。
- **集貨範圍。** 火車站半徑 4 格。貨車編組容量**未查到**。
- **cargodist。** Manual／Symmetric／Asymmetric 三種分配；單向貨（煤）適合 asymmetric。供給換算成需求的公式**未查到**。

### 3.2 Simutrans（來源：官方 repo README、維基百科、論壇說法）

運費＝商品基礎價 × 距離 × 速度加成（距離上限為直線距離 2 倍，論壇說法）。產業鏈同樣是煤礦→發電廠、油井→煉油廠；供電提升工廠產量。論壇的平衡建議是消費端只吃生產端的一部分，一座工廠可供應多家店。官方 input／output 具體數字**未查到**，論壇也說細節未定論。

### 3.3 A 列車系列的資材運輸（日文來源：trafficnews.jp 的 A9 介紹、game.watch.impress.co.jp 的評測）

**確定（有出處）：**

- 蓋房子要消耗資材；庫存不夠，大建築放不下，會出現「建設用資材不足」。
- 資材來自資材工廠（大中小三種，設置後自動產出）、港口搬入、地圖外連線搬入。
- 運送：工廠旁設「操車場」把資材裝上貨車，運到建設地附近的車站，卸到車站範圍內的「資材置場」（大中小）；置場有可設置範圍與供應範圍。置場滿了，列車不卸貨折返。貨車也可改用卡車，量比鐵路少。
- 評論只說資材供給是都市發展的關鍵；大工廠先蓋反而運不動，要從小規模擴張。

**未查到：** 各建築的資材消耗量、貨運收入計算式、裝卸時間、編組上限、資材與成長速度的數量關係。所以下面方案 A 的數字全是原生起始值。

### 3.4 小結：可借的結構

1. 貨物有「易腐度」（運費隨時間衰減的速率）。
2. 車站對每種貨物有評等，影響貨量。
3. 產業產量隨服務好壞浮動。
4. 城鎮成長要求「有被服務」。
5. A 列車式的庫存門檻（資材）：直接、好懂，與本作「鐵路帶動城市成長」的方針（ROADMAP Phase 6 地圖方針）最貼。

## 4. 對照現有 GameCore：貨運接在哪裡

### 4.1 現況（讀過的檔案）

| 面向 | 現況 | 貨運的接點 |
| --- | --- | --- |
| 土地（`City/Land.swift`） | `LandUse.industrial` 已存在，註解寫「Factories and warehouses: jobs, commuting as offices do (freight is a later stage)」。64 m 格（`cellLength` 4,096 單位），每格居民、就業各最多 100,000；`catchmentRadius` 800 m。實景地圖的工業格每格 29 個就業（`LandImport.industrialJobsPerCell`，決策 93），來源是 OSM `landuse=industrial` 與礦場 | **貨源**：工業格的就業數（或另存的產能）。目前工業只是通勤的辦公室，沒有貨物 |
| 乘客（`Passenger/StationPassengers.swift`、`Boarding.swift`、`PassengerDemand.swift`） | 乘客以「群組」計數：`WaitingGroup {line, direction, destination, since, count, journey}`、`RidingGroup`；上車先下後上、遠者先、受容量限制；容量＝節數 × 車種額定 × 1.1（`TrainType.ratedCapacityPerCar`，B 型 260 → 286 人）；車資在上車時一次收（`fareRevenue`） | **貨物群組**：同一種結構多一個貨物種類；`Boarding` 是乘客專用，貨物要有自己的裝卸，不能混進去 |
| 列車（`Railway/Train.swift`、`TrainType.swift`） | `Train.cars`（節數）、`type`（來源 `TRAIN_TYPES` 九種，全是客車）；車種容量表是參考庫 `Ci/` 來源值 | 貨車**不放進 `TrainType`**（那張表對應來源），另加「編組種類」：客車或某種貨車，選填存檔欄位 |
| 路線與班次（`Railway/ServiceLine.swift`、`LineRuns.swift`） | 路線有站序、服務模式、固定班次；乘客依路線方向搭乘 | 貨運路線＝同一套路線＋「貨運」標記，停靠有貨運設施的車站 |
| 車站（`Railway/Station.swift`） | 只有點與月台，沒有設施種類 | 加「貨運設施」旗標與貨物庫存（放在 `passengers` 旁的選填紀錄，仿 `StationPassengers`） |
| 城市成長（`City/LandDemand.swift`、`CityDemand.swift`） | `growLand(reached:)` 每個午夜：服務好的車站讓居民與就業長、升級至多 2 棟滿格建物（`upgradesPerStation`）、擴張一格新住宅（`spread`）；決策 129：站前 256 m 三倍成長、九成滿算滿；決策 139：RCI 需求閥 | **方案 A 的閘門**：升級、擴張、新格需要資材；沒有資材時成長打折 |
| 玩家建物（`City/PlacedBuilding.swift`、`CompanyBuildings.swift`） | 房、店、辦公、碼頭、遊艇港；`floorArea`＝佔地 × 層數；`floorCost` $4,000／m² | 建造也要資材；**新增「資材工廠」「倉庫」等工業類建物**是自然的擴充（仿決策 111 加碼頭與遊艇港） |
| 帳本（`Economy/Accounts.swift`） | `LedgerItem`（`fareRevenue`、`operatingCost`…、`propertyRent`、`incomeTax`）；`DayAccount`、`FinanceSummary`；選填欄位只在非零時寫（稅的 `taxCost` 前例） | 加 `freightRevenue`；營運成本、維修、能源、人事照現有公式算貨運列車 |
| 外地連絡站（決策 137，`outsideConnections`） | 地圖邊緣的車站帶來地圖外的旅次，多付連絡運費 | **港口與外地供貨的現成雛形**：貨運版的「邊緣站」每天固定送進一些資材（方案 A 的保底） |
| 世界開關與存檔（`World/GameWorld.swift`、`SavedGame.swift`） | `distanceDemand`、`outsideConnections` 等是世界上的開關，**只在開啟時才寫進存檔**；舊存檔、GameCore 新世界、golden 都照舊 | 貨運也做成世界開關 `freight`，預設關閉 |

### 4.2 會動到哪些檔案（估計，依方案不同）

- GameCore（package 內，xcodeproj 不必重新產生）：新檔 `Freight/`（貨物種類與規則、貨運車站庫存、裝卸、運費）；`Railway/Train.swift`（編組種類）、`Railway/Station.swift`（貨運設施）、`Railway/ServiceLine.swift`（貨運標記）、`City/Land.swift` 或新檔（產能）、`City/LandDemand.swift`（方案 A 的資材門檻）、`City/PlacedBuilding.swift`（資材工廠）、`Economy/Accounts.swift`、`Economy/Operations.swift`（`freightRevenue`、貨運列車的成本）、`World/GameWorld.swift`（世界開關、指令、`advance` 的接線與 `isWellFormed`）、`World/GameError.swift`、`World/SavedGame.swift`（新版本與升版步驟）。
- GamePresentation：貨運顯示文字（`DisplayText`／`EconomyText`）、`GameSession` 的指令轉接、地圖圖層（工業與貨量）。
- App：路線面板的貨運開關與貨車選擇、車站面板的庫存、`EconomyPanel` 的貨運收入列、地圖圖層。這些有動到檔案新增時才要重新產生 xcodeproj。
- 測試：`Tests/GameCoreTests/` 新的貨運測試類（`rest` 分片自動包含）、`BalanceReportTests` 量平衡、`GoldenScenarios/` 新 fixture、`SaveFixtures/` 新版本 fixture。

### 4.3 存檔、golden 與 replay 的影響

- **存檔版本：** 需要升版（目前 35；取號時以 `main` 與 #231 未釋出的登記為準，下一個是 36 起，與 148–152 無關但要看當時的最大號）。理由與前例相同：舊版本的 build 讀到有 `"freight"` 的存檔，會丟掉貨運狀態，所以要讓它說「存檔比我新」（版本 30–35 的說明都是這個寫法）。新增一份 `SaveFixtures/vNN-freight.json`；既有的存檔 fixture **不改**。
- **世界開關：** `freight` 預設關閉，只在開啟時寫進存檔、才進帳本與狀態描述。這樣 `GoldenScenarios/` 既有的預期值**一個都不變**，既有 `ReplayFixtures/` 的檢查碼也不變。
- **golden：** 新增 fixture（例如 `freight-supply.json`、`freight-delivery.json`、方案 A 再加 `materials-growth.json`），golden schema +1（目前 56，取號時再確認）。讀取端仍接受舊 schema。`tools/golden-checks/` 的 Python 對照只需補城市成長那兩支（`city_growth.py`、`city_buildings.py`），**方案 A 會改到它們的前提**（資材門檻）；開關關閉時兩者不變。
- **replay：** `ReplayFixtureTests` 的檢查碼取自 `ReplayState`（時間、現金、路網、車站、列車、路線、乘客、帳）。貨運欄位**只在開關開啟時才併入描述**，舊 fixture 的檢查碼就不會動。另可新增一份 `ReplayFixtures/freight-*.json`。**絕不重新錄既有檔案**（CLAUDE.md）。
- **決定性：** 貨量、運費、資材消耗全用整數與最大餘數法（仿 `PassengerDemand`），不用浮點、不用亂數；產量浮動若要有，只用存檔種子（仿 `DemandEvents`）。

## 5. 量測：工廠離車站有多遠

腳本 `tools/freight-study/measure_industry_near_stations.py`（只讀已提交的檔案、不連網）讀 `taiwan_places.json` 的 `zones.layers.industrial`（7.5″ 分區格，每格 16 個取樣點，決策 93、96）與 `tra.json` 的 242 個台鐵站點，算工業區面積與離車站的距離。2026-10-11 的結果：

| 離任一台鐵車站 | 工業區面積 | 佔全部工業區 | 工業區 ≥ 0.25 km² 的車站數 |
| --- | --- | --- | --- |
| 500 m 內 | 4.8 km² | 1.0% | 2 |
| 1,000 m 內 | 20.6 km² | 4.5% | 28 |
| 2,000 m 內 | 78.7 km² | 17.2% | 101 |

檔案中工業區共 457.0 km²（19,037 個分區格）。1 km 內最多的車站：新豐 1.03、仁德 0.94、竹北 0.88、南樹林 0.85、後庄 0.79、永康 0.58、大橋 0.47 km²（工業用地面積）。和平、蘇澳、八堵也在前 25 名內；它們是否真有貨運，本文沒有查證。

**設計含義：**

1. 乘客的 800 m 集貨半徑套在工廠上，幾乎沒有貨源。貨運站要有自己的**集貨半徑**：建議起始值 1,600 m（2,000 m 內有 101 站可用；半徑太大等於整個縣的工廠都給同一站）。這個半徑是原生值，要量過。
2. 在實景地圖上，玩家要為多數工廠**拉專用線並蓋貨運站**。這是優點：自由鋪軌（路網不受格子限制）在這裡變成玩法，不是缺點。
3. 工業格只有「就業」，沒有產能。起始提議：每日貨量＝範圍內工業就業 × 係數（見方案）。工業就業在實景地圖是 29／格，一格 64 m 範圍的日產量因此很小，要用集貨半徑內的格數累計；數字待 `BalanceReportTests` 量。

## 6. 三個玩法方案

三個方案共用同一套「貨運核心」（第 6.0 節），差別只在貨從哪來、到哪去、和城市成長有沒有關係。

### 6.0 共用的貨運核心

- **貨物種類：** 一個 `CargoKind` 列舉。C 只有「貨物」一種（可加「煤」給劇本）；A 加「資材」；B 有多種。
- **貨車與編組：** 貨車是客車以外的編組種類，容量以噸計。起始提議：一節 40 t（原生值，來源沒有貨車容量）；一列最多沿用現有的節數上限；牽引沿用現有列車。購車價沿用 `ConstructionCosts` 的列車價與每節車廂價（新遊戲：列車 $150,000、加一節 $40,000），貨車價另訂，先設同價。
- **貨運站：** 車站可標「貨運設施」（花錢、有庫存上限，滿了不收新貨；仿 A 列車的置場滿了不卸貨的規則，在此是不再收貨）。庫存以群組計數，仿 `WaitingGroup`。
- **貨運路線：** 路線加貨運標記；貨運站依路線站序裝卸；貨運列車與客車共用軌道與 dispatcher（待避、交會照現有規則）。這也是貨運在營運層「免費」得到的：整個路網、時刻表與單線交會都已存在。
- **運費：** 貨量（噸）× 起訖站直線距離（公里）× 費率 × 時間係數（易腐度）。起始提議費率 $0.75／噸公里，和客運同量級：一節 40 t 載 20 km＝$600；對照客運一節 286 座以預設平價 $5 滿載＝$1,430，但客車有空座且雙向載客，貨車單向、回程空車。這只是量級對照，不是平衡結論。**實作後更正（決策 155）**：$0.75 量出來太低，貨運線收入只有客運的幾分之一、永遠不回本（`BalanceReportTests.testAFreightLine`）；採用 $5／噸公里，5.4 km 的貨運線 10–18 天回本（客運 5 天）。
- **成本：** 貨運列車照現有 `operatingCost`、`maintenanceCost`、能源與人事公式（這些公式依班次、列車公里、車站數、列車數算），所以不需要新的成本規則。
- **帳：** `LedgerItem.freightRevenue`，歸入營業收入；財報與年報多一列。稅沿用決策 131。

### 6.1 方案 C：最小版，「工廠與港口的貨物收入」

**玩家做什麼：**

1. 在工業區旁蓋貨運站，必要時拉專用線過去。
2. 買貨車、建貨運路線，兩個以上的貨運站之間來回載貨。
3. 看貨運收入進帳：每天各站的貨量、載運量、收入出現在經營面板。

貨源：貨運站集貨半徑內的工業就業 × 係數（起始值：每就業每日 0.5 t，一格實景工業 29 就業 → 14 t／日；一個工業園區若有 30 格，約 430 t／日，約等於一列 10 節貨車一趟的量）。港口：外地連絡站型的邊緣站「港口」，每日固定送來一批貨（沿用決策 137 的做法），讓空白地圖也有貨源。目的地：同一路線上的下一個貨運站（不做貨物配對）。

**和城市成長的關係：** 沒有直接關係。間接：貨運站與專用線佔地、工業就業也計入通勤需求（已有）。可以選配「貨運收入計入權益、讓挑戰與目標多一項」。

**平衡上要注意：**

- 不能讓貨運成為壓倒性的賺錢方式，否則客運的 8 天回本（決策 129 之後的第一條線）失去意義；起始費率偏低，由 `BalanceReportTests` 加貨運場景量，目標是貨運收入約為同投入客運的 0.5–1 倍。
- 單向載貨、回程空車是正常的（煤都是單向）；是否需要「回程貨」留給方案 B。
- 玩家把兩個貨運站放在同一座工廠旁、距離極短時收入趨近零，不需要特別處理；反過來把貨運站設得離很遠則運費高、列車公里也高，成本照現有公式自然平衡。
- 集貨半徑與庫存上限要避免「一站吃掉全縣工廠」。

**PR 拆分（約 3 個）：**

| PR | 內容 | 大小 |
| --- | --- | --- |
| C1 | GameCore：`CargoKind`、貨運編組、貨運站設施與庫存、集貨（工業就業 → 庫存）、裝卸與運費、`freightRevenue`、世界開關；存檔 +1、決策 +1、golden schema +1；新 fixture（存檔、golden、replay） | L（約 1 個長 session，是整個方案的核心） |
| C2 | App 與 GamePresentation：貨運路線與貨車選擇、車站的貨運設施與庫存顯示、`EconomyPanel` 的貨運收入列、地圖工業圖層、繁中字串 | M |
| C3 | 平衡與實景：`BalanceReportTests` 的貨運場景、港口（邊緣站）、新遊戲與挑戰的選用開關、教學一步 | S–M |

**總工作量：** 約 3 個 PR；GameCore 部分是最重的一個。

### 6.2 方案 A：A 列車式資材運輸，「城市要建材才長」

**玩家做什麼：**

1. 蓋**資材工廠**（玩家建物，仿決策 111 的新種類）或在實景地圖上利用既有水泥、採石的工業區；從港口、外地連絡站也有保底進口。
2. 建貨運路線，把資材運到有成長需求的車站，卸到**資材置場**（車站的庫存，有上限，仿 A 列車置場滿了就不卸貨的規則）。
3. 資材被該車站範圍內的城市成長與玩家建造消耗：升級建物、擴張新格、蓋自己的房店辦公都吃資材。
4. 看著車站前的高樓一棟棟升起，資材庫存是「儀表板」。

**和城市成長的關係：** 這是本方案的核心。把 `growLand` 的三件事接上資材（起始值，原生）：

- 資材需求＝新增樓地板面積 ÷ 200 m²／噸（`Land.cellArea` 一格 4,096 m²，一層 1,536 m²）。
  - 擴張一格新住宅（D1，2 層 3,072 m²）：15 t。
  - 升級 D1→D2（+4 層）：31 t；D2→D3（+12 層）：92 t；D3→D4（+22 層）：169 t。
  - 玩家建物：房（512 m²）2.6 t、店（1,152 m²）5.8 t、辦公（6,144 m²）31 t。
- 一個成長中的車站一晚最多升級 2 棟＋擴 1 格，最壞約 350 t／晚、一般 80–200 t；一列 10 節（400 t）貨車一天一趟就供得起。
- **軟閘門（建議預設）：** 庫存不夠時，成長率打到 25%（不卡死）；庫存夠則全速，並且比現況（決策 129）再快一點點。這樣沒有貨運的玩家仍然能玩，有貨運的玩家成長更快。
- **硬閘門（選配難度）：** 庫存不夠就不升級、不擴張（A 列車原味）。僅在作者想要時開，並且必須保證有保底進口，否則新玩家第一天會卡死。
- 保底：邊緣的「外地連絡站」與港口每日送進一批資材到所在車站（沿用決策 137），讓第一條線在沒有貨運時仍有基礎成長。

**平衡上要注意：**

- 決策 129 剛把「第一棟 D4」壓到約第 19 天；資材閘門不能把這個節奏拉回 60 天。軟閘門的保底量要讓新手第一條線沒有貨運也維持這個速度，貨運只是加速與放大。
- 資材運得太順會讓城市暴衝；`growLand` 現在每站每晚最多升級 2 棟，這個上限本身就是閥，不需要再加一個。
- 資材工廠的產量要能被「一列貨車」搬完又不太輕鬆：起始 200 t／日，約半列貨車；多蓋工廠或升級是玩家的投資。
- 房地產收入與成長互相放大（決策 74、94、146、147）：玩家建物也吃資材，不能讓資材成為玩家建物的新瓶頸而打亂決策 130 的出售與已實現損益。先讓玩家建物**免資材**，只有城市建物吃，減少一個耦合。
- `tools/golden-checks/city_growth.py` 與 `city_buildings.py` 要同步（開關關閉時結果不變）。

**PR 拆分（約 5–6 個，含共用核心）：**

| PR | 內容 | 大小 |
| --- | --- | --- |
| A1 | 同 C1（貨運核心）；若已先做方案 C，這個 PR 已經完成 | L |
| A2 | GameCore：`CargoKind.materials`、資材工廠（玩家建物）、資材置場（車站庫存的一種）、資材進口（邊緣站與港口）；存檔 +1、決策 +1、golden schema +1 | M–L |
| A3 | GameCore：`growLand` 的資材門檻（軟閘門，硬閘門為世界設定）、`BalanceReportTests` 的成長場景、`golden-checks` 同步 | L（因為動到最敏感的成長規則） |
| A4 | App：資材置場庫存與缺料提示（地圖狀態泡泡，仿 UX-5c）、車站面板的「建材」列、站長建議一句、字串 | M |
| A5 | 平衡與實景：資材需求係數、工廠產量、保底進口量的調校；實景地圖利用水泥、採石的工業格當資材來源 | M |

**總工作量：** 含共用核心約 5 個 PR；先做過方案 C 則為 3–4 個新 PR。

### 6.3 方案 B：OpenTTD 式產業鏈

**玩家做什麼：**

1. 辨認產業（煤礦、採石場、農場、發電廠、水泥廠、鋼廠、工廠、港口），每座產業有產量與需求。
2. 為每種貨物建貨運站與路線：煤礦→發電廠（煤）、採石場→水泥廠（石灰石）→城鎮（水泥）、鋼廠→工廠（鋼）→城鎮（貨品）、農場→食品廠→城鎮（食物）。
3. 車站評等（服務勤不勤、車快不快、貨堆多不多）決定每座產業有多少貨肯讓你運；服務好產量會漲，服務差會跌。
4. 目的地由貨物配對決定（類似 cargodist），需要流量分配。

**和城市成長的關係：** 沿用 OpenTTD：城鎮成長要求有被服務的車站；食物與建材（水泥、貨品）成為城鎮需求，不足則限制成長（接 `CityDemand` 的需求閥，決策 139）。

**平衡上要注意：**

- 產業鏈的二級投入／產出比例、產量浮動機率，外部都查不到數字，需要整套自己訂並量。
- 產業的位置：虛擬地圖要由種子產生產業；實景地圖要從 OSM 取（`landuse=industrial`、`power=plant`、`landuse=quarry`、港口等，已有的工業區只有就業，沒有產業種類），這會碰到自製 OSM 底圖（151）。
- 每種貨物的路徑配對（cargodist）是重的計算；link graph 文件自己都說 MCF 的成本可觀。起初可以不做配對，只做「產業指定目的地」。
- 玩家的學習成本高：新手要同時理解八種產業與六種貨物。

**PR 拆分（約 8–10 個）：** B1 貨運核心（同 C1）；B2 產業物件與放置（虛擬地圖的種子產生、實景地圖的 OSM 匯入）；B3 生產與消耗（產業鏈、庫存、產量浮動）；B4 車站評等；B5 貨物配對與流量分配；B6 城市成長接食物與建材；B7 App（產業圖層、產業面板、評等顯示）；B8 平衡與教學；B9 實景資料（OSM 工具與資源檔）；B10 劇本與挑戰。

**總工作量：** 約 8–10 個 PR，且是作者列為「長期」的層級；不建議作為第一步。

### 6.4 運煤史實版（O10）怎麼接

ROADMAP 把「平溪線運煤史實版」列為等貨運（O10）。三個方案都能接，但**資料是缺口**：

- 位置與輪廓：菁桐的選洗煤場在參考庫（第 2.1 節）；礦場位置、煤的產量與年代、煤運站、運往何處（基隆港、八斗子、發電廠）參考庫與外部都沒查到可靠數字，**不能自己編**。
- 做法：先完成方案 C（有「煤」一種貨物、一座煤礦＝一個工業貨源、一個港口＝邊緣站），再以劇本（仿決策 90 的平溪線）提供：煤礦位置、日產量、運價與目標。史料要另外由作者或另一個研究 session 蒐集；這是與「史實劇本（劉銘傳鐵路）」session 的共同需求，先對資料來源再動工。
- 劇本機制已有：年代車種限制（決策 86）與固定事件（天燈節 2.5 倍，決策 90）。貨運劇本需要的新東西只有「劇本帶的貨源」。

## 7. 比較與建議

| | C 最小版 | A 資材（含 C 的核心） | B 產業鏈 |
| --- | --- | --- | --- |
| 玩家的新動作 | 蓋貨運站、跑貨運線 | 加：蓋資材工廠、補資材給城市 | 加：認識整條產業鏈 |
| 與城市成長 | 無 | **直接（資材門檻）** | 間接（食物、建材需求） |
| 與本作定位（鐵路帶動城市） | 弱 | **強** | 中 |
| 平衡風險 | 低 | 中（動到成長規則） | 高（八種產業、浮動、配對） |
| 動到的既有規則 | 無（世界開關） | `growLand`（開關關閉時不變） | `growLand`、`CityDemand`、地圖產生 |
| PR 數 | 約 3 | 約 5（先做 C 則新增 3–4） | 約 8–10 |
| 資料缺口 | 小 | 小（全原生） | 大（產業種類與位置） |

**建議：分兩步，C → A。**

1. **第一步做方案 C 的核心**（C1–C3，約 3 個 PR）：先有完整的貨運迴圈（貨源、貨車、貨運站、運費、帳），並且全用世界開關隔離，既有 golden、存檔、replay 一個都不動。它同時是 A 與 B 的共同底層，所以不是白做。
2. **第二步加資材（A2–A5，約 3–4 個 PR）**，用**軟閘門**把貨運接到城市成長，硬閘門留成難度選項。這最符合本作「鐵路帶動城市成長」的方針，並且資料缺口小（全是原生數字，由 `BalanceReportTests` 量）。
3. **不建議現在做方案 B。** 工作量是 A 的近兩倍，產業鏈的數字外部查不到、參考庫也沒有，八種產業會讓新手卻步。等 C、A 上線並看過 TestFlight 回饋，再決定要不要往產業鏈長。
4. 運煤史實版在 C 之後做最便宜；先對好史料來源。

C1 是風險最集中的 PR（存檔、golden、決策編號、`GameWorld` 的接線），建議由一個 session 專責，並先在 #231 登記存檔、golden schema 與決策編號。

## 8. 待作者決定

1. 走哪個方案？（建議 C → A。）
2. 方案 A 的閘門：軟閘門（建議）還是硬閘門？是否做成難度選項？
3. 玩家建物要不要吃資材？（建議第一版不要，減少與房地產經濟的耦合。）
4. 貨運站的集貨半徑：1,600 m（建議起始值）、2,000 m，還是玩家可升級？
5. 貨車是否分種類（煤斗車、貨櫃車、有蓋貨車）？參考庫沒有貨車車種，種類越多，美術與平衡越重；建議第一版只有一種通用貨車。
6. 運煤史實版要不要排？若要，史料（礦場位置、產量、年代、運往何處）由誰蒐集？
7. 港口（邊緣站）要不要在虛擬地圖也有？實景地圖的港口位置（基隆、台中、高雄、花蓮）要不要從 OSM 取（碰到底圖，決策 151）？

## 9. 查閱方法與尚未檢查到的部分

- 外部專案是用網頁查（wiki、官方 README、日文與英文評論），標「未查到」的就是沒有明確數字，沒有用記憶補。OpenTTD 的運費公式、二級產業的投入產出比例、貨車容量，Simutrans 的官方數字，A 列車的資材量，Transport Fever 2 的官方規格，都沒有查到。若之後要更準，OpenTTD 的原始碼文件（docs.openttd.org）可讀概念，但同樣不複製。
- 台鐵貨運的真實歷史（貨運站名單、停辦年代、貨種、運量）沒有查；參考庫只有幾何。如果方案要貼近台灣史實，需要另一個資料研究。
- 量測只涵蓋台鐵車站與 OSM 的工業區；沒有量港口、發電廠、礦場（`taiwan_places.json` 的工業區已把礦場併進去，但沒有分種類）。
- 本文沒有跑任何 GameCore 測試（只寫文件）；平衡數字都是起始值，**UNVERIFIED**，要由 `BalanceReportTests` 的貨運場景量過才算數。
- 量測腳本可重跑：`python3 -I tools/freight-study/measure_industry_near_stations.py`（需 Python 3，不連網）。
