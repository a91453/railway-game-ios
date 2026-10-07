# Phase 6 土地使用與建物：參考盤點與設計提案

查閱日期：**2026-10-07（UTC）**。本 repo 的基準是最新 `origin/main` **`ec55dccb59f64f13961f1c51a64b414b95ed45ff`**；私有參考 `a91453/railway-reference-private` clone 後的提交是 **`2db0c5a6963798e6b86723bb001189343a59940c`**。下文的參考路徑都相對於私有 repo 根目錄；大小是實際檔案位元組數，不是網路下載量或執行時記憶體。

這份研究文件供作者決定 Phase 6 的表示法、規則與遷移方式。**本 PR 只新增此文件，沒有程式變更，也沒有執行或宣稱任何測試通過。** 第 1、2 節是檔案查閱結果；第 3–5 節是尚未採納的提案，型別與函式名稱也只是草案。GameCore、fixture、獨立參考模型與正式設計紀錄的修改仍由 Claude Code 負責。

開始前依序讀了 `AGENTS.md`、`CLAUDE.md`、`docs/ARCHITECTURE.md`（含決策 13、28、50、54、65、68–71）、`docs/ROADMAP.md` 的 Phase 5–8 與跨階段議題，以及 `docs/RAILWAY_REFERENCE_MAPPING.md` 的「城鎮成長（決策 70）」。路線圖有保留較早的描述：土地服務範圍的「格子距離」應以 2026-10-02 的距離計算方針解讀；Phase 5F 的舊 WIP 文字應以決策 65 的 R1–R3 與現行程式為準。

## 1. 現況：目前有哪些接點

### 1.1 GameCore 的權威狀態與需求

| 檔案／型別／函式 | 實際行為與 Phase 6 的接點 |
| --- | --- |
| `Sources/GameCore/World/WorldBounds.swift`：`WorldBounds.maximum`、`maximumSide`、`contains(_:)`；`Sources/GameCore/Geometry/WorldCoordinate.swift`：`WorldCoordinate.unitsPerMetre` | 每邊最多 `2^20 = 1,048,576` 世界單位，`64` 單位／公尺，即 **16,384 m 見方**。世界點是半開範圍；鐵路不是方格。新的土地格不能成為鐵路 topology 或車站座標的限制（決策 28、54）。 |
| `Sources/GameCore/Passenger/StationDemand.swift`：`StationDemandKind`、`StationDemand`、`maximumDailyTrips` | 四種車站需求型別：`residential`、`office`、`shopping`、`scenic`；權威資料為 `kind` 與 `dailyTrips`。有效範圍 `0...1_000_000`，解碼也檢查。每種型別的出發／抵達曲線各有 24 個整數，比例為 **1/1000**；`dayShape` 與 `weekendShape` 也是 24 小時表。不是人口或就業模型。 |
| `Sources/GameCore/Passenger/PassengerDemand.swift`：`GameWorld.setStationDemand(_:to:)` | 先檢查車站存在，再檢查需求範圍；`nil` 清除需求。免費，已候車者保留。使 `PassengerPlanCache` 失效，並移除該站的 `townGrowth.places`，讓下次成長重新記錄起點。由車站 ID 排序的 `StationPassengers` 儲存需求。 |
| 同檔：`stationDemand(of:)`、`dailyDemand(from:to:)`、`hourlyDemand(from:to:)`、`makePassengerPlan()`、`makeNetworkPassengerPlan(memo:)` | 現在起點總量、迄點吸引力都讀車站每日旅次；直達模式依共同停靠線路分配，網路模式依可行旅程與廣義時間。日量分迄點、日量分小時用最大餘數法。Phase 6 要替換這裡的需求輸入，不另造一套候車或上下車系統。 |
| 同檔：`PassengerPlanKey`、`passengerPlanKey()`、`PassengerPlanCache`、`releaseUnit` | 網路計畫鍵含線路、車站含營運狀態、路網、列車長度／容量、服務日／等級、需求、票價、每週開關與事件。計畫是推導資料，不存檔、世界相等不看它。釋出單位 `3600`，每 OD 的餘數是權威狀態；土地需求改變也必須納入鍵或使計畫失效。 |
| `Sources/GameCore/Passenger/StationPassengers.swift`：`StationPassengers`、`WaitingGroup`、`PassengerLedger`；`Boarding.swift` 的上下車流程 | 候車、釋出、溢出、放棄、車上與抵達的守恆帳。轉乘者仍歸原起站；`arrived` 是該起站旅客完成旅程的累計，不是目的地站的下車人數。城市量測不能誤用這個方向。 |
| `Sources/GameCore/Passenger/PassengerRoutes.swift`：`PassengerRouteGraph`、`PassengerTransferRules`、`walkingTransfer(from:to:)`；`PassengerCrowding.swift`：`PassengerCrowding` | 決策 65：跨站步行距離 **嚴格小於 450 m**，5 km/h、最短換車 120 s；感知懲罰基準 15 分鐘，依級別乘 0.8／0.8／1.2／1.7。同站換線感知成本 12 分鐘。網路需求另有 BPR `0.15 × 負載^4`（負載上限 2）與超過 30 廣義分鐘的需求衰減。土地服務半徑不是這個轉乘半徑。 |

每週需求與事件（決策 68、69）的實際位置與常數：

- `StationDemand.weekdayFactors = [840, 1040, 1020, 1020, 1040, 1120, 920]`，週日起；`weekday(ofDay:)` 讓第 0 天為星期一。`trips(onDay:)` 用 `(dailyTrips × factor + 500) / 1000`，週六、週日換 `weekendShape`。
- `PassengerDemand.swift` 的 `setWeeklyDemand(_:)`、`demandDay`、`isDemandWeekend`、`trips(of:at:)`、`attraction(of:at:)`：每週係數乘起站出發量；事件乘出發量與迄點吸引權重。迄點權重沒有再乘星期係數。
- `DemandEvents.swift`：`DemandEventSchedule { seed: UInt32, events, nextDraw, draws }`、`setDemandEvents(seed:)`、`startDemandEventDay(_:)`、`drawDemandEvent(_:on:)`、`demandMultiplier(at:)`。FNV-1a 32 位元雜湊 UTF-8 的 `seed|key`，初值 `2_166_136_261`、乘數 `16_777_619`；第一次抽籤 3–7 天，之後 8–12 天除以 `max(1, 有需求站數 / 10)`，至少 1 天。熱門前五分之一的門檻以上旅次權重乘 10。展覽 3–7 天、加成 200–500 千分比；大客流 1–2 天、加成 500–1000；提前 2–5 天公布。同站多事件取最大加成，倍數 `1000 + max(boost)`。
- `World/GameWorld.swift` 的 `advance(ticks:)`：基本步長是一個遊戲秒，整分鐘釋出乘客；每日午夜先 `growTowns`，再 `startDemandEventDay`，儲存 OD 餘數並重建計畫，然後 `settleAccounts`、釋出與派車。`dayWake` 阻止 idle shortcut 跨過午夜。不能把 UI 的更新頻率當成每日更新時點。

### 1.2 決策 70：城鎮成長目前其實長的是車站旅次

`Sources/GameCore/Passenger/TownGrowth.swift` 同時定義型別與 `extension GameWorld`；**`growTowns(reached:)` 的實作在此檔，呼叫端才在 `World/GameWorld.swift`**。

| 名稱 | 實際行為 |
| --- | --- |
| `TownGrowth.Place { station, base, counted, lastGrowth }`、`TownGrowth.places` | 每站首次被看到的旅次起點、上次午夜的累計抵達數、上次實際成長千分比；依站號排序，存檔。沒有土地位置、居民、就業或建物。 |
| `TownGrowth.growth(served:trips:reached:)` | `served <= 0` 回傳 `-2`；否則服務比例上限 1000，乘 `serviceGrowth = 10` 再除 1000，加 `min(reached, 5) × reachGrowth(1)`，最多 `15` 千分比／日。分母是傳入的目前 `demand.dailyTrips`，不是另存的昨日星期／事件後日量。 |
| `GameWorld.setTownGrowth(_:)`、`townGrowth(of:)` | 開啟時建立空的成長記錄；關閉保留已長成的旅次。查詢供畫面顯示。 |
| `GameWorld.reachedStations(_:)` | 計數釋出計畫中各起站的 flow 數；是有旅次的迄點數，不是鐵路實體相接數。 |
| `GameWorld.growTowns(reached:)` | 只在 `.management` 且開啟成長時更新。有正旅次的站第一次只記基準；之後取 `record.arrived - counted`。增量 `(trips × rate + 正負500) / 1000`，正成長至少加 1；夾在 `base...min(base × 4, maximumDailyTrips)`，直接寫回 `StationDemand`，需求改變就清計畫。`lastGrowth` 依夾限後實際差值重算。 |
| `GameWorld.reachedStations(endingDayAt:release:workedOutAt:)`（`GameWorld.swift`） | 午夜讀前一天的計畫；若此次呼叫從午夜開始、計畫已是今天，就以昨日最後一秒的世界副本重算。保護跨午夜、切分呼叫與存檔續玩的一致性。 |
| `townGrowthProblem()`、`GameWorld` 的 Codable | 檢查站號不重複且排序、車站存在、`base` 在 `1...1_000_000`、`counted >= 0`、`lastGrowth` 在 `-1000...1000`。`townGrowth` 只在開啟時編碼；舊世界缺鍵為關閉。 |

`Tests/GameCoreTests/TownGrowthTests.swift` 已有批次／逐分鐘、存檔續玩、安靜午夜、從午夜開始與每週需求的案例。此處只閱讀測試內容，未執行。現行規則不能解讀為「人口每天成長 1.5%」；它沒有居民數，也沒有貨物或產業模型。

### 1.3 GamePresentation 如何給新站初始客流

完整呼叫鏈是 **`GameLauncher` 傳入資料 → `GameSession.newStationDemand(at:)` 推估 → `addNetworkPlatform()` 在世界副本建站 → 經營模式呼叫 `GameWorld.setStationDemand`**。資料格與熱圖不會自行改世界。

| 檔案／型別／函式 | 實際用途與常數 |
| --- | --- |
| `Sources/GamePresentation/PopulationGrid.swift`：`GridCounts`、`Run { r, c, p: [Int] }`、`PopulationGrid.init(data:)` | 讀西北角 `north`、`west`、`cellDegrees` 與列上的連續計數；row 向南、column 向東，非空格以 Dictionary 存。使用 Foundation 與 Double，不能原樣搬入 GameCore。 |
| 同檔：`GridCounts.count(within:ofLatitude:longitude:)`、`hasAny`、`PopulationGrid.people(within:ofLatitude:longitude:)` | 每 **50 m** 取圓內樣本，按所在格的密度估算圓面積人口並四捨五入。緯度 110,574 m／度，經度 `111,320 × cos(latitude)` m／度。5,000 m 內沒有有人格的中心時回傳 `nil`，這是涵蓋近似值，不是國界／海陸判斷。 |
| 同檔：`StationDemand.realWorld(residents:kind:)`、`catchmentRadius`、`tripsPerHundredResidents` | 半徑 **800 m**；每 100 居民每天 40 旅次，先整除，再四捨五入至 100 旅次；最少 100、最多 1,000,000。只有人口時型別為住宅。這是本 repo 的政策，不是參考伺服器公式。 |
| `Sources/GamePresentation/PlaceGrid.swift`：`PlaceGrid.Kind`、`places(within:ofLatitude:longitude:)`、`StationDemandKind.realWorld(residents:places:totals:population:)` | 四層 `shops/offices/schools/attractions`，沿用同一 `GridCounts`。以周邊地點量除「居民按全臺比例預期量」，最小預期 shops 30、offices 5、schools 3、attractions 1；office 合計辦公與學校。最高比率達 **1.5** 就採該類，否則住宅；平手依辦公、購物、景點。**地點數只選曲線，不增加旅次，也不是工作機會數。** |
| `Sources/GamePresentation/NetworkSession.swift`：`GameSession.newStationDemand(at:)`、`addNetworkPlatform()` | 有人口與 `RealWorldFrame` 才估算；人口未涵蓋或空白模式回 `.cityDefault`。建新站且經營模式才設定需求；替既有站增月臺不重設。先在世界副本完成建站與月臺指令，再換回，保持失敗原子性。 |
| `Sources/GamePresentation/StationDemandText.swift`：`defaultDailyTrips`、`cityDefault`、`dailyTripSteps` | 城市預設住宅 **10,000** 旅次；操作步階為 100 到 1,000,000 的 1／2／5 系列。`GameSession` 的客流操作也經世界指令，不能當作另一份需求權威。 |
| `Sources/GamePresentation/PopTravel.swift`：`PopTravelMode`、`PopTravel` | population／travel／movement 三頁、預設 8 時、每 1,200 ms 播一小時、透明度 0.1...1；人口預設 0.72，其他 0.85／窄螢幕 1。顏色與圖例；**不決定新站客流**。 |
| `Sources/GamePresentation/PopulationHeatmap.swift`：`PopulationHeatmap`、`tiles(in:blockSize:)`、`cellInfo(atX:y:)`、`blockSize(pointsPerUnit:)` | 把人口格投影為世界矩形，固定由北到南、西到東，螢幕尺寸不足 **6 points** 就以 2、4、8…格合併；依平均人口著色、提示人口與人／km²。只供呈現，不是城市模擬的細格。 |
| `Sources/GamePresentation/TravelDemandMap.swift`：`TravelDemandMap`、`cellMetres` | 從世界每小時需求產生旅次與需求變化圖層，以 **1,000 m** 格彙總；土地輸入改變後應繼續讀世界查詢，不自行產生旅次。 |
| `Sources/GamePresentation/NewGame.swift`：`GameWorld.newGame(anchor:balance:eventSeed:)` | 世界最大範圍、600 倍速、經營模式、交通控制、`.network`、每週需求、種子事件、城鎮成長全開，再設錨點。預設 `eventSeed = 1`；沒有初始化土地。`DemoWorld.make(in:)` 以普通指令設定五站固定旅次（20,000／30,000／10,000／15,000／5,000）。 |
| `Sources/GamePresentation/GameLauncher.swift`：`startNewGame(at:)`、`begin(_:keepingAutosave:)`；`GameSession.swift`：`population`、`places`、`stationCatchmentPopulation` | launcher 持有外部人口／地點資料，交給每局 session。新遊戲在 Presentation 用系統亂數產生 `UInt32` 事件種子後傳入世界；推進期間不抽系統亂數。session 的周邊人口查詢是顯示用途，不是已存需求的更新器。 |

### 1.4 實景錨點與臺灣資料

- `Sources/GameCore/World/GeoAnchor.swift`：`GeoAnchor` 的緯經度是 **1/10,000,000 度整數**，緯度 ±900,000,000、經度 `[-1,800,000,000, 1,800,000,000)`；`setGeoAnchor(_:)` 只改錨點，沒有模擬規則讀地理座標。`Sources/GamePresentation/RealWorldMap.swift` 的 `RealWorldFrame.worldPosition`、`metresFromAnchor`，以及 `PopulationGrid.swift` 的 `coordinate(worldX:worldY:)`，負責以錨點緯度的 Web Mercator 比例換算，x 東、y 南。這些 Double 換算應留在匯入／呈現端。
- `RailwayGameApp/Resources/RealWorld/taiwan_population.json`：**159,071 bytes**；WorldPop Taiwan 2025 constrained、30 角秒、R2025A v1、DOI `10.5258/SOTON/WP00840`、CC BY 4.0。`north = 26.391666897100002`、`west = 116.70833214650004`、`cellDegrees = 0.0083333333`；2,614 runs、**27,606 個正人口格**、合計 **23,163,504 人**、單格最大 38,240。此為直接讀 JSON 的結果；工具 README 的 28,924 格與目前檔案不一致，本 PR 不修改該檔案。
- `RailwayGameApp/Resources/RealWorld/taiwan_places.json`：**255,969 bytes**，同角點與格距；`layers[kind] = [{r,c,p:[整數計數]}]`。商店 3,003 runs／6,277 格／102,090 筆；辦公 1,380／2,481／8,614；學校 2,526／3,453／4,588；景點 2,377／3,241／6,511。`osmData` 記錄 `2026-10-05T14:27:06Z` 至 `2026-10-05T17:38:36Z`，ODbL 1.0。
- `tools/real-world-population/build_population_grid.py`：將固定 SHA-256 的 WorldPop GeoTIFF 四捨五入為整數人口，壓成 runs；操作與來源見同目錄 README。
- `tools/real-world-population/build_place_grid.py`：`TILE = 0.25` 度；`SETS` 用 OSM `shop`，或 restaurant/cafe/fast_food/food_court/marketplace/bar/pub；`office`；school/university/college；attraction/museum/zoo/theme_park/viewpoint/aquarium/gallery。`query` 每類先要求 `out count`，`incomplete` 檢查 remark 與筆數；`fetch` 只沿用完整快取。`main` 按 `(type,id)` 在每種類別去重，node 用點、way/relation 用中心，寫相同人口格；它**沒有儲存建物輪廓、樓層、樓地板面積、工作人數或地價**。

決策 50 的 MapKit 背景與 `RealRailways` 真實鐵道也都只是畫面。現有臺灣人口／地點資料可以當土地匯入來源；Apple 顯示的建物與搜尋結果不能因此被當作可存檔的初始土地資料。

## 2. 四處參考盤點

分類的意思：**可直接重用**是檔案或資料契約可直接打包／匯入；**需轉譯成 Swift**是核心所需的演算法需改為 Swift 與整數；**只是畫面**是來源只有呈現／場景用途，沒有相應的模擬語意。畫面資產仍可直接重用於合適的 renderer。找不到完整實作或必要檔案時另外標 **gap**，不補寫來源規則。

### 2.1 `Ci/reference_snapshot/`

| 檔案／函式／資料鍵 | 親眼看到的常數、格式、大小 | 分類與限制 |
| --- | --- | --- |
| `lib/virtual_island_city__q_21ffa7f6ae58fc9e.js`：`METRO_VIRTUAL_ISLAND_CITY_KEY`、`METRO_VIRTUAL_ISLAND_REFERENCE_MAP_URL`、`METRO_VIRTUAL_ISLAND_SEMANTIC_MAP_URL`；內部 `C`（公開 `metroVirtualIslandMapOptions`）、`M`（加入圖層）、`V`（公開 `metroVirtualIslandAttachMap`） | **13,906 bytes**。city key `anycity-virtual-island`；兩個 URL 都是 `/data/virtual-island/tiles/city.pmtiles?v=20260905-osm-city-v15`，**不是兩份圖**。範圍 `[[-0.1124,-0.18],[0.1124,0.18]]`，中心 `[0,0]`，圖例寫 25 × 40 km；zoom 10.3、min 9.1、max 18。MapLibre vector source `metro-virtual-island-city-form-v4`；`landuse` layer 的 `kind` 有 cbd／industrial／villa／institution／newtown，fill-opacity 0.74；另讀 island／terrain／water／waterways／parks／buildings 等圖層，terrain 的 `e` 預設 50，色階 50／180／350／550。 | **只是畫面**，圖層契約可轉作匯入對照。**gap：city.pmtiles 本體不在四處檔案清單裡**，沒有要素筆數、幾何、人口或就業容量可盤點；不能將樣式表冒充初始土地資料。SEMANTIC 名稱不代表已存在可讀的語意點陣圖。 |
| `lib/app__q_c234188b7c397f91.js`：`CITIES` | **4,378,323 bytes**（全檔）。53 城市、215 個 `districts` 項目。城市 `{name,pop,tag,center:[lat,lng],zoom,accent,districts}`；分區 `{name,c:[lat,lng],pop,r}`。上海 `pop:2487`；浦東 `{c:[31.222,121.544],pop:568,r:10000}`、黃浦 `r:2500`。沒有分區多邊形、工作人口或成長紀錄；本表不把未明示單位的 `pop` 數字直接當作人數。 | 城市清單／粗情境資料**可直接重用**，匯入座標與整數數量需轉換；不是遊戲的分區命令。 |
| 同檔：`registerAnycityFromManifest`、`fetchAnycityManifest`、`startGameAnyCity` | manifest 呼叫 `/api/anycity/manifest?cityKey=...`，可加 lng／lat／geofabrikId；讀 `cityKey/displayName/center/bbox`。bbox 必須四數，中心取兩端平均；註冊城市的 `pop` 固定 **50**，預設 zoom **12**。虛擬島入口另用 initialZoom **11.35**，creative 模式、零緯經度。 | 載入與選點流程**只是畫面／入口**；**gap：manifest 後端與完整回應資料未收錄**，`pop:50` 不能當真實人口。 |
| `anycity-regions__q_8175d1b1597b17dd.html`：`initAnyCityRegions`、`AnyCityUi.fetchJson/renderRegionsHtml`、`data-geofabrik-id` | **37,379 bytes**。呼叫 `/api/anycity/regions`，點選後去 `/anycity-bbox.html?region=...&engine=...`；靜態未支援區列表有 **17** 組區域／座標，前十組包含兩端經緯度，第 11 組是多點。 | **只是畫面**：regions 是來源資料涵蓋區選單，不是住宅／商業分區。**gap：regions 回應與 anycity-ui.js 未收錄**；只能列出呼叫與靜態 HTML，不能給完整 API schema／筆數。 |
| 同 app：`loadPopulationHexLayer`、`syncPopTravelPopulationLegendUi`、`G.populationDataCache`、`hourlyOD` | 300 m 圖層讀 `/data/<city>/tiles/landscan-grid-300m.pmtiles`，source-layer `landscan`、計數 `est_pop_sum`；色階閾值 10／25／50／100／200／400／800／1200／1600。另有香港／新加坡的 `data-precomputed/*-landscan-grid-300m.geojson` 載入。`hourlyOD` 是 24 個矩陣，呼叫端／存檔有 `hourlyODU8B64` 等壓縮形式。 | 人口與 OD **只是畫面／載入契約**；**gap：人口圖磚、這兩份 GeoJSON 與計算 `/api/flowFull` 的服務實作未收錄**，無法核對人口→就業→OD 公式或資料大小。 |
| 同 app：`buildStationFlowPresetCurves`、`normalizeStationFlowPresetRowToDailyBase`、`stationFlowCustomEditingAllowed` | 四種 preset；住宅／辦公的 8／18 時 Gaussian，幅度 0.6、sigma 1.15；購物 out 為 14 時 0.42／sigma 2.4 與 19 時 0.5／sigma 1.8，in 提前 1 小時；景點 out 16 時、in 11 時，0.75／sigma 2.1。24 小時初值 `1`，依城市 minHour／maxHour（預設 0–23）生成 `1 + Gaussian`。正規化以每小時基礎需求加權維持日量，無基礎權重時才使用等權平均 1；結果夾在 `0...11`。自訂編輯只允許 economy mode `free`。 | **需轉譯成 Swift**，曲線已移植為千分比表。可以讓「各土地用途」使用這些時段形狀，但來源沒有混合用途的旅次係數。 |
| `external/openfreemap-tiles/styles/liberty.json`：`layers[].source-layer = landuse`、`filter` 的 `class` | **43,079 bytes**、111 個樣式圖層。可見 residential、pitch、track、cemetery、hospital、school 的分類過濾。`worldLow-pixel-map__q_03872009ba4ca780.html` **31,584 bytes** 是全球地圖頁。 | **只是畫面**。樣式分類不是遊戲人口／地價／就業資料；全球地圖頁沒有查到土地模擬格。 |

**Ci 的 gap**：未查到土地所有權／玩家分區指令、建物入住與工作容量、地價、交通帶動人口成長、產業原料／產出引擎。關鍵字包括 `SEMANTIC_MAP_URL`、`LAND_`、`virtual island`／`virtual_island`、`landuse`、`land_use`、`zoning`、`AnyCity`／`regions`、`population`／`employment`／`jobs`、`building`、`landValue`／`land_value`／`landPrice`、`town growth`／`townGrowth`、`industry`、土地／分區／簡體與繁體的「地價」。`LAND_` 未找到遊戲土地型別常數；不能據此編造分類代碼。

### 2.2 `Railway/site_archive_clean/`

| 檔案／函式／資料鍵 | 親眼看到的常數、格式、大小 | 分類與限制 |
| --- | --- | --- |
| `data/taiwan_land.json`、`data/offline_land_style.json` | **65,075／1,828 bytes**。前者是單一 GeoJSON **Feature**（不是 FeatureCollection），geometry **MultiPolygon**：39 多邊形、39 rings、2,833 座標點。bbox `[118.151366,21.895601,122.085059,26.383474]`。properties 寫內政部縣市界線、版次 `1140318`、政府資料開放授權條款第 1 版、dissolve 後 RDP 約 150 m 簡化，僅供海陸墊底；style 的 source ID `offline-land`，fill／line 兩層、light／dark／sat 三種主題。 | 海岸粗遮罩**可直接重用**，不是可建性／地形／都市分區真值。用於土地初始化要另決定簡化海岸附近的處理；目前用途**只是畫面**。 |
| `index.html`：`building-3d`、`LANDSCAPE_BUILDING_COLOR`；`rail-3d/integration/map3d.js`：`setAppearance` | **1,848,084／65,644 bytes**。`openmaptiles` 的 `building` source-layer，minzoom **13**，13→14 級高度由 0 漸進到 `render_height/height`，預設 **8 m**；底高 `render_min_height/min_height` 預設 0；透明度 landscape 1、dark 0.30、其他 0.72。高度色階 0／12／35／90 m。另有 `LAND_FS_HINT_KEY = 'trainmap-land-xl-hint'`，只是全螢幕提示狀態。 | **只是畫面**。沒有以樓層或高度生成住戶／工作機會。`LAND_*` 命中不能當成土地使用 enum。 |
| `rail-3d/integration/landscape-trees.js`：`createLandscapeTrees`、`inRing`、`inside`、`noise`、`rebuild` | **10,276 bytes**。讀已呈現的 `landcover_wood`／`landscape-worldcover-wood` 多邊形；避開 water／building／道路／farmland／farmyard／grass／sand／rock／industry。`MX=101700`、`MY=111320`、`STEP=26 m`、索引格 `.001` 度；面積 >100,000 m² 或最長邊 >400 m 的大片林地跳過；半徑 1,000 m、zoom ≥14.5、檢查上限 10,000、裝置樹數 cap 700／1400。noise 的乘數 374761393／668265263／1274126177，除以 2^32。 | **只是畫面**：可參考洞、多邊形與空間索引，不能把視窗、縮放、裝置 cap 或 `queryRenderedFeatures` 當土地權威。`landscape-industry` 是避樹圖層，不是產業產銷。所需線上土地覆蓋來源完整內容未核對。 |
| `rail-3d/blender-buildings.js`：`buildingCatalog()`、`buildBlenderBuilding(record,lod)`、`inspectBlenderBuilding` | **3,240 bytes**。讀兩套 catalog＋placement＋各 model；以 placement 的 `anchor/rotationDeg/footprint` 為定位，`railElevationM` 必須 null。網格是 Float32 position 3＋normal 3、每頂點 **24 bytes**，drawGroups 帶 start/count/color/metalness/roughness；載入端可核對 SHA-256。檢視透明度 **0.24**。 | catalog／輪廓／現存網格**可直接重用於匯入或 Phase 8**；Three.js 繪製需目標 renderer adapter。**只是畫面**，不可由材質或模型 ID 推定人口／工作容量。 |
| `rail-3d/assets/blender-buildings-v1/{catalog,placement}.json` 與 `*/model.json` | **22** 筆；catalog **14,267 bytes**、placement **64,086 bytes**；此目錄現存檔案合計 **8,064,361 bytes**。placement 為 `{version,at,entries:{id:{anchor:[lng,lat],rotationDeg,orientationBasis,footprint:FeatureCollection,...}}}`。 | 元資料與 footprint **可直接重用**。**gap：22 筆 near.mesh.bin 都缺檔，22 筆 far.mesh.bin 存在**，不能說模型近景完整。 |
| `rail-3d/assets/historic-buildings-v2/{catalog,placement}.json` 與 `*/model.json` | **25** 筆；catalog **2,799 bytes**、placement **37,232 bytes**；目錄合計 **7,643,664 bytes**。山佳舊站房例：anchor `[121.3927955832114,24.972590044833833]`、rotationDeg 0、orientationBasis `ENU-baked`，footprint 含 OSM way `236033179` 與 ODbL-1.0 來源。 | 同上；**gap：25 筆 near.mesh.bin 都缺檔，25 筆 far.mesh.bin 存在**。此盤點檢查了 metadata／檔案存在與大小，未解碼全部 mesh 或逐件驗證外觀。 |
| `rail-3d/assets/blender-buildings-v1/taipei101-landmark-v1/model.json`、同目錄 `far.mesh.bin`；`rail-3d/landmark-catalog.js`：`landmarkCatalog` | 101 model **6,562 bytes**；高 **508 m**，anchor `[121.56455513294843,25.033946307135494]`，`sizeM=[136.5800018310547,123.58000183105469,508]`，旋轉 89.03489627577518°。far 13,716 頂點／4,572 三角形／**329,184 bytes**。metadata 宣告 near 16,524 頂點／396,576 bytes，實檔缺少。地標選單 JS **1,984 bytes**，包含高、寬深、中心、zoom/pitch/bearing。 | 尺寸、位置與現存 far 資產**可直接重用**；只是地標畫面。`heightQuality`／`placementStatus` 明列示意外觀／未核實立面，不能當工程測繪或土地容量。 |

**Railway 網站的 gap**：沒有查到土地價格、居民／就業模擬、車站可達性驅動開發、產業庫存或原料／產出。使用 `landuse`、`landcover`、`worldcover`、`landscape`、`LAND_`、`building`、`placement`、`footprint`、`population`、`employment`、`land value`／`landValue`／`landPrice`、`town growth`、`industry`、土地／地價／城市成長／產業搜尋；樹與建物的命中是呈現，海岸是背景資料。模型各自的 sources／license 要隨實際移植保留，不能用一筆的授權概括所有資產。

### 2.3 `Railway/railway_game_reference_clean/`

先讀 `00_READ_ME_FIRST.md`、`01_MIGRATION_MAP.md`；此包共 16 個檔案，沒有 `src/` 原始碼樹。

| 檔案／函式／資料鍵 | 親眼看到的常數、格式、大小 | 分類與限制 |
| --- | --- | --- |
| `01_MIGRATION_MAP.md` §9、§10 | **8,192 bytes**。§9 指向 `src/town_cmd.cpp`、`src/industry_cmd.cpp`、`src/subsidy.cpp`，要求以運輸可達性量測為輸入、不直接控制列車；§10 列 map／landscape／terraform／rail／tunnelbridge 等模組，建造合法性與成本要在 command。 | 架構接點**需轉譯成 Swift**；**gap：只有路徑與文字，沒有城鎮成長率、產業、建物或地價公式／常數**。 |
| `binary_reference/relevant_source_paths.txt`、`relevant_symbols_and_settings.txt` | **1,139／2,904 bytes**。前者列 `genworld.cpp`、`heightmap.cpp`、`industry_cmd.cpp`、`town_cmd.cpp` 等路徑；後者有 linkgraph `demand_size/demand_distance`、CargoPacket 與鐵路 penalty 名稱，沒有此任務的成長或產業數值表。 | 搜尋索引**可直接重用**於後續定位；沒有實作可移植。不能依熟悉 OpenTTD 而補上快照裡沒有的數值。 |
| `docs/savegame_format.md`：`CH_RIFF`、`CH_SPARSE_ARRAY`、`CH_TABLE` 等 | **8,577 bytes**。chunk tag 四 bytes；type 的低 4 bits：0 RIFF、1 array、2 sparse array、3 table、4 sparse table；自存檔 295 起 RIFF 用在含 tile bit 資訊的 MAP chunks。 | 存檔組織方式**需轉譯成 Swift**；沒有本案土地格 payload schema／每格大小，不能直接套用它的版本號或估算 Swift 存檔。 |

**gap 的搜尋**：`town`、`growth`、`industry`、`subsidy`、`house`、`building`、`population`、`land`、`map`、`heightmap`、`terraform`、`land value`、`employment`。查閱 migration map、source-path／symbol 清單與 savegame 格式文件後，能確認依賴方向，不能確認成長／產銷／地價演算法。符合決策 70 已記錄的 gap。

### 2.4 `Railway/taipei_gta_reference/` 與 `source/`

先讀 `00_READ_ME_FIRST.md` 並列出 `source/`；實際 **102 檔、20,962,045 bytes**。以下函式名保留 bundle 內真實的短名，括號才是用途說明，不假稱未收錄的 TypeScript 原始函式名。

| 檔案／函式／資料鍵 | 親眼看到的常數、格式、大小 | 分類與限制 |
| --- | --- | --- |
| `source/assets/engine-DKps_Gq_.js`：`B`、`V`、`Kn`、`K`、`hr` class 的 `buildBlocks/districtAt/surfaceAt` | **137,915 bytes**。bounds `minX:-900,maxX:900,minZ:-960,maxZ:560`。`V` 有 9 區（河濱、士林、西門町、萬華、中正、中山、松山、信義、大安），矩形界線＋`style {floors:[min,max],towers,neon,old,shops}`；信義 floors `[10,40]`、towers 0.8；萬華 `[2,6]`、old 1。`Kn` 有 5 個矩形覆寫。`districtAt` 先覆寫，再依 V 順序與半開範圍查詢。`buildBlocks` 由道路間距建矩形街廓，寬／深 <20 時跳過；街廓帶 district／reserved／zones／四側道路。 | 區域與擺放演算法**需轉譯成 Swift**；style 是程序生成建物的外觀分布，**只是場景**，沒有居民、就業或城市日更新。其 x/z 不可直接當本遊戲世界原點。 |
| 同檔：`surfaceAt(x,z)`、`K` 的地標資料 | `x < -960 || z < -1030` 為 water；依道路寬度辨 road／plaza／sidewalk，城外 terrain，park 範圍 park，其他 lot。地標為 `{id,name,x,z,w,d,facing,kind,zone?}`；101 例 x745、z200、w110、d110、facing0。 | **需轉譯成 Swift**可做建造檢查的行為來源；不是語意點陣圖或法定土地使用分類。 |
| `source/assets/world-gYgJkZNf.js`：`On.kind/inCity/reachable/bankDist/edgeUrban` | **1,357,123 bytes**。kind 回 city／land／farbank／water；城界來自 plan；reachable 使用 x≥−960、z≥−1030；bankDist>6 才 farbank。westBank 為 `-1212 + 22 sin(z×0.0021+1.3) + 12 sin(z×0.0063+0.4)`；northBank 也有 sin／exp 地形形狀。 | **只是畫面／場景地形**。若採地形生成需離線量化或重寫整數，不能把 sin／exp／浮點運算放進 GameCore；沒有讀到語意圖 URL。 |
| 同檔：`DO`（多地標擺放順序）、`lO`（擺放拒絕）、`UD`（地表取樣）、`WO`（道路前緣搜尋） | `DO` 優先解決依賴其他 site 的 anchors，保持輸入索引；重複 ID 拒絕。`lO` 檢查 bounds／road／sidewalk／block／landmark／transit／mrt／site／district-claim／surface；預設地表 `PD={lot,plaza,park}`。block 容差 0.5、道路交疊容差 −0.05、landmark 2、transit 3、mrt 半徑 4、既有 site 1。`UD` 內縮 **0.3**，以邊／中點 **3×3** 取樣；`WO` 預設 setback **0.5**、search **60**。 | 擺放合法性與排序**需轉譯成 Swift**，可依距離／整數輪廓接到命令。3×3 取樣不是精確覆蓋測試；不應宣稱已證明任意輪廓不相交。 |
| 同檔：`dk` 的 `donqi-ximen`、`Ik` 的 `railway-department-park`；`lA`（取得 site metadata） | metadata 含 `{id,name,category,district,placement:{frontage,cross,side,along,setback,search,replaces,anchors},lot,claims,proxy}`。商店 lot `24×22`、min `19×18`、search60、setback0.5、proxy 高 18.2；鐵道部 lot `40×30`、min `32×24`、search210、along6、setback0.5，claims scope all／props；北門 anchor bearing315／dist150、臺北車站 250／600、捷運北門 45／130。 | 地標資料**可直接重用**於場景轉換，擺放規則需 Swift；地標／名店並沒有就業容量或地價。`replaces` 是場景輪廓調整，不能直接等同玩家拆除所有權。 |
| `source/assets/site-donqi-ximen-BYSklXQx.js`、`site-railway-department-park-BykCBjAy.js`；`build-B3ahlmTh.js`、`build-BQ6sPpWH.js` | **28,314／25,070／113,537／109,307 bytes**。前兩份是地標外觀／室內幾何與材質；build 模組是場景／atlas 生成，不是玩家都市開發的經濟命令。`build-BQ6sPpWH.js` 的 atlas 預設 2048、pad 依 4 縮放，含固定 RNG seed **20,283,292**。 | **只是畫面**，可供 Phase 8；固定場景 RNG 不能直接代替存檔的世界種子。 |
| `source/assets/content-Bs2Ca5A2.js`、`buildWorker-BPjJt4Vl.js` | **1,850,065／404,048 bytes**。可見 district 的建物／碰撞／claims／ensureResident、分片載入與 worker 呼叫；不是每日人口「入住」的 resident。 | **只是畫面／資源排程**。需要可取消、快照輸入的效能手段時再評估；不採 worker 完成先後作城市更新順序。 |

**缺檔與 gap**：world 的 import 路徑中實際缺 `postfx-pHdVmtPd.js` 與 **43** 個 `site-*.js`；content 的 import 中缺 4 個 build 模組及 `register-DEjbkm8D.js`。已存在的兩個地標不能代表所有近景可直接跑。未查到 `*_SEMANTIC_MAP_URL`、遊戲土地分類 `LAND_*`、人口／就業容量、地價或城鎮成長／產業引擎。搜尋 `SEMANTIC`／`semantic`、`LAND_`、`surfaceAt`、`districtAt`、`zones`、`lot`、`claims`、`placement`、`building`、`population`、`employment`、`jobs`、`landValue`／`landPrice`、`townGrowth`、`industry`；`districts`／`zones` 的命中是固定場景街廓與保留區，不是作者尚未決定的城市模擬。

## 3. 設計提案：土地是模擬資料，建物可以自由擺設

### 3.1 表示法：建議 64 m 的隱藏細網格

| 比較項目 | 看不見的細網格 | 權威多邊形 |
| --- | --- | --- |
| 決定性與整數 | 固定 row／column／CellID；面積、鄰接與迭代順序簡單，整數界線與距離。最末列／行依 bounds 截短。 | 整數頂點可決定，但裁切、洞、自交、重疊、共享邊與頂點排序要有完整規約；交點往往是有理數，要定點捨入或更寬整數。 |
| 存檔大小 | 上限可直接算；可用非預設格、runs、chunks，虛擬世界存種子＋修改。匯入世界需儲存量化結果或不可變來源版本。 | 稀疏而大片同用途時較省，但大量小地塊／建物輪廓會增加頂點與 ID；大小依頂點總數，不等於多邊形數。 |
| 人口格／語意來源 | WorldPop／PlaceGrid 可重取樣，以來源格總量守恆分到細格；有語意點陣圖時可直接定義 pixel→cell。既有 1 km 格不需也不應當成 64 m 真實精度。 | 人口格必須裁切面積；語意點陣圖要向量化／合併，增加匯入與邊界規則。現有參考沒有可直接採用的語意點陣圖本體。 |
| Phase 8 | chunks、可見範圍、LOD 與建物實例易分組；格線不用畫出。任意方向建物／鐵路照世界點擺放，mesh 只讀快照。 | 沿道路的自然輪廓較好；曲面／地塊 triangulation、LOD 與相鄰縫隙留在 renderer，但建造合法性還需要核心幾何。 |
| 《A 列車》鐵路帶動成長 | 可逐格算服務、增居民／工作容量、擴散開發，易控制成長前緣與開發總量；不用把「一站」當作一座城。 | 可表達基地／街廓與分割出售，但成長分裂／合併土地、重疊服務範圍與容量分配的第一版工作量較高。 |

**建議**：土地模擬單位 **64×64 m = 4096×4096 世界單位**，最大世界 **256×256 = 65,536 格**；`CellID = row × columns + column`，世界原點 `(0,0)` 對齊。建物仍用整數 `PlanPoint` 與任意輪廓，不吸附格心；建物影響哪些格是推導索引。64 m 與鐵路 span／定價長度的 16 m 沒有依賴關係。需要更自然分區筆刷時，UI 可用多邊形圈選，再依明訂涵蓋規則產生格修改命令。

以下是**大小估算，不是實作量測**。假設格內 payload 24 bytes（用途／分區／開發級別／旗標、人口、就業、基準價等固定整數欄位），不含索引、建物、歷史與編碼開銷：

| 格邊長 | 世界單位 | 最大格數 | 全圖固定 payload | 每非預設格以 32 bytes 計的稀疏紀錄 |
| --- | --- | --- | --- | --- |
| 16 m | 1024 | 1,048,576 | 24 MiB | 全滿 32 MiB |
| 32 m | 2048 | 262,144 | 6 MiB | 全滿 8 MiB |
| **64 m** | **4096** | **65,536** | **1.5 MiB** | 全滿 2 MiB；10% 約 0.2 MiB |
| 128 m | 8192 | 16,384 | 0.375 MiB | 全滿 0.5 MiB |

現有存檔是 JSON，不能把上表當磁碟大小；若每格 JSON 假設 100 bytes，64 m 全滿約 **6.25 MiB**，還要加 wrapper／建物。6a 應用真實初始城鎮與成長後稠密地圖量測 runs／稀疏編碼，決定是否需要分塊。多邊形可用「頂點座標兩個 Int64＝16 bytes／頂點＋ring／用途／人口等」比較，例如 10,000 基地 × 8 頂點就有 1.22 MiB 座標，不含屬性與 JSON；這只是同條件估算，不是來源模型大小。

### 3.2 資料模型草案與誰是權威

GameWorld 仍是唯一權威；新型別需保持值語意、`Codable` 解碼驗證與 `Sendable`，命令失敗不能留下部分修改。以下是建議欄位，不是新架構決策；歷史、種子與會累積誤差的餘數才需另外存檔，純查詢不得留下第二份真相。

| 資料 | 草案 | 權威／推導 |
| --- | --- | --- |
| 土地使用與分區 | `LandUse`: vacant／residential／commercial／office／industrial／civic／park／water。`zoning` 是允許發展用途，`use` 是目前用途；另存 `developable`、開發級別。第一版單格一種主要用途，混合基地由建物各用途容量表達。水域、保留地不能自動轉成可建地。 | 玩家修改的分區、目前用途／開發級別為**存檔權威**；來源遮罩屬不可變基底或明存匯入格。分類是原生提案，不是抄到的 LAND_* enum。 |
| 人口 | 每格 `residents: Int64`，只能在明確日更新／命令改變；人數非負且有界。住房容量約束人口，人口增減作為移入／移出記錄，不能由旅次直接叫作人口。 | **存檔權威**；全市、站區、個別建物分配的人口是**推導**。不在每個建物再儲存另一份居民總數。 |
| 就業與活動 | 每格 `jobs: Int64` 為實際工作機會；可另有上學／訪客的活動基數。商店／辦公 POI 到工作數的對照需作者定政策。工業先只提供工作機會，貨物另提案。 | 每格工作數／活動基數為**存檔權威**；工作容量、站點吸引權重為**推導**。不能將 OSM 一筆 office 算成一名員工而不標原生規則。 |
| 建物 | `Building { id, type, anchor:PlanPoint, footprint:[PlanPoint], floors, heightUnits, constructionDay }`；必要時存擺放角度的整數代碼與版本化定點旋轉規則。建物型別表決定每層住房／工作／訪客容量。既有建物不得因換模型而變容量。 | 存在、幾何、型別、樓層、完成日為**存檔權威**；容量、覆蓋格、入住分配、mesh／材質／LOD 為**推導**。若 height 可由型別×floors 唯一得出就不另存。 |
| 初始建物／既有存量 | 6a 尚未有可見建物時，可存每格的「初始住房／工作容量」代表抽象既有存量；6c 遷移成抽象建物或明確建物後扣掉／移除相同容量。純裝飾地標另標不增加容量。 | 初始存量為**存檔權威**；**不得同時計算初始存量與同一批匯入建物的容量**。6c 驗收需證明轉換前後人口與容量不重複。 |
| 地價 | 初版 `landValue(at:)`：情境基準＋距離服務／可達性／用途／開發指標，以**美分／m²**整數計算、明確夾限。先沒有平滑滯後或土地買賣。 | 基準與政策版本為**存檔／不可變規則**，當前價為**推導**；Phase 7 真有買賣時，交易實付金額是**存檔權威**。若作者要逐日平滑價格，上一日價格也必須升級為權威。來源無公式，暫不捏造平衡值。 |
| 車站影響 | `stationInfluence(at:)`／`landCatchment(of:)`，整數平方距離；站區常住人口、就業、出發／抵達活動各自有聚合。 | 全為**推導**；車站點原已存檔。索引或 revision cache 不作城市真值。 |
| 城市日更新 | `CityGrowthState { seed, rulesVersion, lastUpdatedDay, yesterdayMetrics, remainders }`。每日量測含釋出／抵達／未服務、可達性，依 cell→station 昨日配額分回土地。 | 種子、已結算日期、昨日基準／不可從現狀重建的歷史與餘數為**存檔權威**；今日可達性圖、計畫、彙總為**推導**。 |

建議服務半徑先沿用 **800 m = 51,200 世界單位**，以格中心至站點的 `d² < R²` 判定；不使用鐵路格距，也不拿 450 m 轉乘範圍替代。權重可先提案 `w = 1000 - floor(d² × 1000 / R²)`，範圍內為 1...1000，外為 0；這是**原生候選**，不是來源公式。64 m 格的服務邊緣有量化誤差；若作者要求精確圓／格交集，應另選固定子取樣與明確面積分母。

**重疊站區必須分配，不得每站重複加總整份居民與工作。** 同格的活動依各站距離權重以最大餘數法分配，平手給站號小者；無可服務站就保留為未服務活動。站點上限 1,000,000 只是相容保護，不能讓 cap 多出旅客；超出量要記為未服務或依明確政策再分配，不靜默消失。各欄位與乘積上限在 6a／6b 定案；距離平方 <2^41，`d² × 1000` 安全，但跨站／全城數量乘權重不能僅憑單站上限宣稱安全，需 checked arithmetic／現有 `WideInteger` 或先正規化。

### 3.3 需求由土地推導，取代 5A 的單一站型曲線

建議在世界增加明確的需求來源模式（例如 `.legacyStations`／`.landUse`）。舊存檔缺鍵為 legacy，新土地遊戲為 landUse；不要因開啟新版 App 就把既有玩家曲線重算掉。

土地模式的資料流：

1. 每格居民、就業與訪客活動分別產生整數活動量；住宅出發／回家、辦公上班／下班、商業／景點活動沿用既有四種千分比形狀。居民→旅次可先保留目前 **40／100** 作試算基準；工作／上學／訪客係數是 gap，作者定案前不能宣稱完整 OD。
2. 先按距離將每種活動分給服務站，得到站的各用途貢獻；再由不同的出發量與目的吸引力形成 OD。**不要只挑最高用途，重新把整站設成一種 `StationDemandKind`**；應保留混合出發／抵達 24 小時權重。
3. 迄點可達性、票價、廣義時間／擁擠、車站營運狀態仍經現有 Passenger 查詢與計畫。住宅人口與就業吸引力不再共用同一個 `dailyTrips` 權重。規則須明訂「住宅回程也吸引旅次」以免純住宅站只有出發。
4. 將可行日量分 OD、小時與路徑，最後沿用原有整分鐘釋出、OD 3600 餘數、候車／轉乘／守恆。新增土地活動總帳，辨別潛在活動、未覆蓋／不可達、票價／時間衰減與實際釋出；現行 `PassengerLedger` 只稽核已釋出者。
5. 站面板上的日量／曲線改為查詢；`PassengerPlanKey` 要涵蓋量化土地輸入與政策，或使用保證隨所有相關修改更新的 revision。快取仍不存檔。`StationPassengers.demand` 在 legacy／自由模式 override 才是權威，土地模式不能儲存一份可獨立編輯的同義快取。

6a 可先只存土地、不接釋出；6b 才引入模式與混合 profile（例如 `LandDemand.stationProfile`）。`setStationDemand` 的 legacy 行為保留。土地經營模式若要禁止玩家改總旅次，應由**核心指令驗證**，不只隱藏 UI；自由模式可保留按站覆蓋值，必須存 mode／override 並定義 `nil` 是恢復推導還是停用。未定前以新指令區分，不改舊 `nil` 的意思。

### 3.4 和 townGrowth、每週需求、事件及初始世界銜接

**TownGrowth 建議雙路過渡**：legacy 世界繼續按決策 70 長車站旅次；土地世界的城市日更新改長土地居民／就業／開發容量，停用同站的旅次成長，避免乘兩次成長率。可沿用服務比例＋可達性「先量測再成長」的接點，不把 1.5%／日、4 倍起點直接宣告為人口規則。新成長以住房／工作容量、分區、保留地與鄰近開發約束；率、人口移入的基準與產業依賴由作者定案。

從已有 `townGrowth` 轉換時，`base/counted/lastGrowth` 沒有足夠資訊反推人口與土地。建議舊局**不自動轉換**；如果提供明確遷移，需以**目前**旅次與另定的人口／就業配置保留開局量，重設城市量測基準、保留候車／車上與 OD 餘數，並記來源／遷移版本。僅用 `base × 100/40` 會丟掉成長，也無法反推出辦公工作數；這是政策問題，不是資料解碼技巧。

每週係數與事件維持需求的獨立層：先算土地基礎量，再套決策 68 的星期與週末時段，再套決策 69 的事件出發／吸引倍率，最後做可達性／票價／擁擠與分配。事件增加旅次，**不永久增加人口或就業**；城市服務評估若用事件後需求作分母，須採昨日實際計畫量，而不是今天基礎量。新土地需求會改變事件抽站權重，有相同 seed 也可能抽到不同站，不能宣稱事件序列必然不變。

經營模式允許自動成長、正常結算；自由模式建議土地依然可產生需求，但自動成長關閉，玩家可編輯土地與明確的 station override。切換模式時立即重設每日基準或記錄時間切片，避免把自由模式期間的抵達數補算成經營成長；這是要補定的行為。

初始土地來源建議：

- **空白模式**：固定情境基底（至少兩處已有居民／工作或活動的初始聚落），加存檔 seed 的地形／可開發遮罩；固定 generatorVersion。完全零人口的全空世界依服務成長無法起步，應由作者選「預設聚落」或另外的先驅移入規則。虛擬島樣式可參考用途，但 PMTiles 缺檔，不能拿來當已備妥地圖。
- **臺灣實景模式**：在 GameCore 外將現有 WorldPop／OSM 地點格與明確取得的海陸／土地使用來源轉為同一份 64 m 整數資料包；儲存採用的來源版本／量化後格值，不能每次讀檔重新向網路抓。按來源格與細格重疊權重，以最大餘數法儲存裁切範圍內總人數。現有人口檔沒有海陸／可建判定，POI 只給活動用途提示；真實就業／建築容量仍是估計且需標明。
- **臺灣以外／資料未涵蓋**：作者選可見的「使用情境預設」或限制土地模式；不要把「5 km 內沒有居民」當成海洋，更不要沿用建站就憑空出現 10,000 旅次作為土地規則。錨點仍只是背景定位；同一份量化世界的模擬與錨點／圖磚載入無關。

匯入端可以為地理投影使用 Double，但它的輸出必須是固定的整數世界快照；跨裝置如要自行轉換，應釘住量化規則並驗證輸出雜湊，或由工具預先產生資料包。GameCore 不執行 Mercator、cos、網路請求或圖片色彩辨識。未來若取得語意點陣圖，另外定義寬高、bbox、座標系、像素類別代碼、unknown／邊界值、版本／checksum，再接匯入；此次沒有這份可盤點的本體。

### 3.5 每日午夜的決定性契約

以下固定順序以舊一天結束、下一個基本步長開始為界；第 0 天只初始化基準，不虛構前一天成長。`lastUpdatedDay` 防止在同一午夜續玩或切分推進時重做。

1. 儲存昨天的候車釋出餘數、服務／抵達差值、按昨天土地→站配額歸屬的量測與可達性。讀**昨天**需求／事件／服務日，不以今天路徑重解釋昨天。仍在車上的旅客依既定到達日量測政策處理，不能把累計 `arrived` 當成當日新旅客。
2. legacy 世界照既有 `growTowns`；landUse 世界按 **CellID 全序** 計算成長候選，全部讀同一份昨日城市快照。分配開發額度／移入人口／工作，寫入新土地與建物狀態；不能前面寫入的格影響同日後面格的候選。
3. 重建今天土地基礎站 profile，再 `startDemandEventDay` 移除結束事件／公布新事件；抽站用更新後基礎量，隨機鍵順序固定。事件不反向改本次土地成長。
4. 套星期／週末與事件，重建今天 OD／路徑計畫，繼承相容的 OD 餘數／路徑分配配額。排序 `(起站,迄站,用途,小時,路徑索引)`；容量不足或不可達分配要有未服務帳。
5. 維持既有帳本結算在午夜需求處理之後、當分鐘釋出／派車之前；只結算剛結束期間，利息不因重建城市重複。若 6c／Phase 7 新增土地費用，再定義獨立的一次性結算順序。
6. 正常跑當分鐘釋出與逐秒列車／上下車。把城市 `dayWake` 納入 idle shortcut，即使沒有列車、沒有每週需求或事件，啟用城市仍不能跳過午夜。

全程只用整數／定點；成長率、曲線與距離權重建議 1/1000，Money 仍為美分。小量成長保留權威餘數，避免「先切分再捨去」使批次結果變化。分配一律最大餘數法，平手依 CellID／StationID／明確索引；Dictionary／Set 不作結果順序。若背景或分片計算，每片只計算同一快照的候選，合併後再按全序分配，片大小不改結果。

亂數只能來自存檔種子，沿用 `(seed,用途,序號)` 雜湊概念；城市用途鍵可為 `city:<rulesVersion>:<day>:<cellID>:<purpose>`，不能挪用事件抽籤次數或受訪問順序影響。Presentation 可以開局產生種子後傳入命令；之後系統亂數、Date、相機、fps、裝置效能模式都不參與。

**後續實作驗收契約**：同種子與同命令流，跨午夜 `advance` 一次／逐分鐘／任意切分／午夜前後存檔續玩／無列車 idle 必須得到相同世界、城市歷史、人口就業總量、需求、餘數、事件與帳本；必要時再比逐秒。不只比畫面日量。此 PR 沒有執行這些測試。

## 4. 相容性與預期值的影響

| 範圍 | 目前基準與提案影響 | 哪些值可能變、原因 |
| --- | --- | --- |
| 存檔 | `Sources/GameCore/World/SavedGame.swift` 的 `currentVersion = 11`。建議土地權威／新需求模式初次落地由作者評估升到 **12**（若期間其他 PR 已用，改取下一版），加入遷移與新版本 fixture；舊版缺土地保持 legacy。 | 不改／不再產生任何既有 SaveFixtures。新版即使欄位選填，舊 build 可能悄悄丟掉土地並回到舊需求，因此不能只因新解碼器可讀 v11 就斷言不用升版。舊存檔讀入後的車站需求、正在旅行者、事件／成長若被自動遷移也會改行為，必須另審。 |
| Golden | `Tests/GameCoreTests/GoldenScenario.swift` 的 schema **35**；支援 30–35。新土地初態、命令、拒絕原因、人口／就業／地價最終摘要需要新的契約（候選 schema 36，編號由 Claude Code 協調）。 | legacy fixtures 不應被新預設影響；若明確採土地需求，`daily/hourlyDemand`、released／waiting／overflowed／abandoned／arrived、旅程選項／轉乘時刻、票價收入、餘額、停站秒數與後續交通狀態都可能變。先由新增情境釘規則，不能重寫舊期望來消紅燈。 |
| Town／週／事件測試與 Presentation 情境 | `TownGrowthTests`、`WeeklyDemandTests`、`DemandEventTests`；`PopulationGridTests`、`PlaceGridTests`、`NewGameBalanceTests` 等已依現行初始化。 | 雙路保留時舊測試仍保護舊行為；newGame、DemoWorld、RealWorldDemo／教學若啟用土地，站的初量、成長邊界與經濟回收示例會變。應明確選擇逐個情境接入，不能悄悄把示範固定旅次當居民。 |
| ReplayFixtures | schema 1；`Tests/GameCoreTests/ReplayState.swift` 的 `describe/checksum` 以排序描述世界與 JSON 摘要計算；現有 7 份（含 `network-economy.json`），沒有土地摘要。 | 新土地狀態必須納入 checksum，否則土地已不同卻可能漏報；legacy 沒有土地時避免無意插入預設行導致每份摘要都變。若舊需求實際改，network-economy 等乘客／收入／停站變化會移動 checksum；只在已審的行為變更下逐一說明，不能為了通過測試而重錄。新增土地 replay 包含午夜、存檔與種子，不要求改舊 recipe。 |
| 差分參考模型 | `Tests/GameCoreTests/ReferenceWorld.swift`、`ReferencePassengers.swift` 獨立算直達需求與最大餘數；`ReferenceWorldGoldenTests` 對 `setPassengerRoutingMode/setStationOperationMode` 明確跳過，不能稱它已驗證 network 城市路徑。 | 6a 應另寫獨立土地計數／幾何／校驗模型；6b 能以小世界獨立列舉分配，不呼叫正式實作的 LandDemand 當 oracle。若繼續跳過 network case，PR 要寫此驗證邊界；舊 campaign digest 可保持 legacy，新土地 campaign／golden 提供新證據。 |
| Phase 7／8 | 土地交易、建物建設費／維護費尚未有規則；renderer 不決定容量或價格。 | 6c 若加入現金支出，ConstructionCosts、分類帳、資產與淨利才受影響；不要先由外觀模型的體積推成本。6d／Phase 8 的 mesh、LOD、相機與圖磚失敗都不能移動 GameCore golden／replay。 |

這些是因果預估，**不是保證舊預期值不變，也不是實測差分**。正式 PR 要逐個列出有意改變的數值與理由，舊存檔／golden／replay 的分工與保護照 AGENTS.md／CLAUDE.md。

## 5. 建議 PR 拆分與參考對照表草案

### 5.1 PR 範圍、驗收與作者要決定的問題

| PR | 範圍 | 驗收條件（後續實作時） | 作者決定 |
| --- | --- | --- | --- |
| **6a 土地資料與初始情境** | City 土地 enum／格／權威人口就業、世界命令與失敗原子性、非預設格編碼、種子／generator 版本、空白情境；實景匯入先處理現有臺灣資料。需求仍 legacy。GameCore／存檔由 Claude Code。 | 越界／重複／排序／負數／無效格拒絕；64 m 末格與小 bounds 正確；同種子同格；匯入裁切與最大餘數總量守恆；v1–11 仍可讀；新存檔往返；報告實際稀疏／稠密大小。不開城市時不影響現有需求。 | 64 m 是否接受；單格主要用途或分用途份額；初始聚落／地形政策；實景未涵蓋的後備；舊局保留或明確遷移；新存檔版本邊界。 |
| **6b 土地需求與城市成長** | 新需求來源模式、混合時段、分出發／吸引、重疊站區分配、接現有每週／事件／路徑／釋出；landUse 世界不再長 StationDemand；城市量測與整數餘數。 | 重疊站不重複人數；無站／不可達／封站／flowControl 與上限有明確未服務帳；OD／小時／路徑總量守恆；批次／逐分鐘／午夜續玩完全一致；新 golden／replay 與獨立小世界分配對照。記錄舊／新 fixture 實際影響。 | 800 m 與衰減；居民 40/100 是否保留；工作／學校／商業／景點活動係數；回程權重；成長率／容量約束；服務用昨日哪種分母；自由模式 override 與切換基準。 |
| **6c 建物、容量與地價** | building 型別與任意整數輪廓、placement 合法性、容量／施工完成、初始抽象存量轉建物；推導地價。地標先不變更客流；貨物產業另開規格。 | 移動／旋轉／拆除命令失敗不改世界；禁止水域／保留地；任意形狀重疊規約明確；初始存量轉換前後容量不重複、人口就業不丟失；價格單位、邊界、整數 overflow 明確；外觀更換不改容量。 | 允許輪廓與旋轉精度；開發密度／建物每層容量；拆除後的居民工作處理；地價靜態推導或每日滯後；是否一起加入土地買賣／維護費用（會觸及 Phase 7）；貨物另案的範圍。 |
| **6d 土地與建物畫面** | Population／PopTravel 接城市查詢；用途、站區、未服務與地價圖層；分區筆刷／建物預覽經核心命令；Phase 8 快照與 LOD adapter，先用既有 Canvas 也可。 | 畫面只讀世界；預覽結果與命令合法性一致；臺灣繁中與英文；可見範圍／LOD／效能模式不改 checksum；存檔載入後建物位置／資料來源可說明。資產缺檔有明確後備。 | 先做 2D 用途／量測或直接做 3D；哪些遠景模型先用；保留真實地圖建築背景時如何辨遊戲建物；近景缺資產是否補取得。 |

每個 PR 只有相關範圍；正式 ARCHITECTURE／ROADMAP／REFERENCE_MAPPING、schema 編號與 fixture 由 Claude Code 落地，Codex 可依確定規格做匯入工具／呈現。研究本身不鎖定演算法的平衡常數。**產業完整產銷、貨物運輸、道路可達性、土地所有權與買賣仍需後續規格**；第一版 industrial jobs 不表示已實現這些功能。

### 5.2 參考檔案／函式 → 目標檔案／函式

目標除現有接點外均為候選名稱；不是新增檔案清單或已完成移植紀錄。帶 gap 的行不能當作有完整來源程式碼。

| 參考檔案／函式／鍵 | 目標檔案／函式草案 | 比例與差異 |
| --- | --- | --- |
| `Ci/.../virtual_island_city__q_21ffa7f6ae58fc9e.js`／`M`、`METRO_VIRTUAL_ISLAND_SEMANTIC_MAP_URL`、landuse.kind | `tools/land-use/import_semantic_map.*` → `Sources/GameCore/City/LandGrid.swift` | **gap：PMTiles 未取得**。取得後用途對映、64 m 格、世界座標 64/m；不能只移植顏色。 |
| `Ci/.../app__q_c234188b7c397f91.js`／`CITIES`、`registerAnycityFromManifest`；regions 頁 | `Sources/GamePresentation/RealWorldMap.swift`／地點入口；候選情境匯入工具 | lat/lng→錨點 1/10^7 度；城市 pop 單位另核定；regions 維持入口，不映成 zoning。 |
| 同 app／`buildStationFlowPresetCurves`、`normalizeStationFlowPresetRowToDailyBase` | 既有 `Passenger/StationDemand.swift` 表 → 候選 `City/LandDemand.swift`／`stationProfile`，接 `PassengerDemand.makePassengerPlan` | 既有 **1/1000** 表沿用，改為按土地活動混合；日量依最大餘數分配。來源沒有活動／工作量係數。 |
| 同 app／LandScan、hourlyOD、`/api/flowFull` 呼叫 | 既有 `PopulationGrid/PlaceGrid` → 匯入工具 → `City/LandDemand.swift` | **gap：原圖磚與後端缺失**；臺灣先用現有 WorldPop／OSM，輸入人數／地點是整數；來源 300 m 與現有約 1 km 均重取樣為 64 m，不提升資料真實精度。 |
| `Railway/site_archive_clean/data/taiwan_land.json`／MultiPolygon | `tools/land-use/import_taiwan_land.*` → `City/LandGrid` 的海陸候選基底 | source 經緯度浮點留工具，輸出整數世界點 **64 單位/m**；150 m 海岸簡化有誤差，不能直接定義可建地。 |
| `Railway/.../rail-3d/blender-buildings.js`／`buildingCatalog`、`buildBlenderBuilding`、兩套 catalog/placement/model | `tools/land-use/import_buildings.*`；6c `City/Building.swift`（經選定容量政策）與 6d／Phase 8 renderer | source 米→64 單位/m，角度需固定整數規約；Float32 vertex/normal 僅 renderer；24 bytes stride 保持。容量為原生；47 份 far 存在、47 份 near 缺檔。 |
| `Railway/.../landmark-catalog.js`／`landmarkCatalog`；`landscape-trees.js`／`inside/noise` | GamePresentation 地標清單／renderer `BuildingSnapshot` 與環境植被 | 只畫面；700/1400 cap、26 m 樹間距不進入人口／就業；GameCore 若用隨機必須儲存種子。 |
| `Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §9／§10 | `City/CityGrowth.swift`／`GameWorld.updateCityDay`；世界建物／分區命令 | 接穩定車站／服務／旅客量測；**gap→原生**，成長率暫不聲稱來源值；整數千分比。 |
| 同包／`docs/savegame_format.md` | `World/SavedGame.swift`、`GameWorld` Codable，新增土地版 fixture | 參考稀疏／自描述思路，不複製 binary chunk 或來源版本 295。現行 v11 與候選新版本由作者協調。 |
| `Railway/taipei_gta_reference/source/assets/engine-DKps_Gq_.js`／`hr.buildBlocks/districtAt/surfaceAt`、`V/Kn/K` | `tools/land-use/import_taipei_scene.*`；`City/BuildingPlacement.swift` | 米尺度場景需明確原點平移、z→y 南向核對、定點 64/m；樣式 floors 是呈現，不能當入住人數。 |
| `Railway/taipei_gta_reference/source/assets/world-gYgJkZNf.js`／`DO/lO/UD/WO`、`dk/Ik` | `City/BuildingPlacement.swift`／`validatePlacement`、`GameWorld.placeBuilding`；地標場景轉換 | 0.5 m=32 單位、0.3 m 候選量化 19 單位、1 m=64、2 m=128、3 m=192、4 m=256；−0.05 m 須明訂負向捨入，不能悄悄近似。來源 3×3 檢查需另決定精確交疊契約；依 site 錨點依賴固定排序。 |
| 同 world／`On.kind` 與現存 site/build 模組 | 匯入工具的初始地形／renderer 場景 | sin/exp、材質與 atlas 不進入 GameCore；缺動態模組需取得或明訂後備。 |

## 6. 查閱方法與尚未檢查到的部分

**VERIFIED（雲端 Linux 工作區，靜態查閱／資料計數）**：clone 私有 repo、上述兩個提交；按指定順序讀規範；以 `rg --files`、`rg` 在四處列檔／搜尋，再讀命中的原始檔；用 Prettier 3.6.2 在 repo **外**展開 minified JS 後閱讀；JSON 用 Python 標準函式庫計數／欄位檢查，CITIES 只評估抽出的常數物件計數；用檔案存在與 bytes 核對 near/far 和動態 import 缺檔。沒有修改參考 repo 或重新產生臺灣資料。

**UNVERIFIED**：沒有執行 Swift 建置／測試、iOS Simulator／實機、網頁遊戲或 Three.js 場景；未跑效能／存檔大小基準、未量測提案的 64 m 量化誤差；未解碼每個二進位網格／驗證全部 SHA-256／逐件授權與外觀；未檢查所有 vendor／角色／任務模組的完整執行行為。沒有向來源站點抓取缺少的 PMTiles、AnyCity／flow 服務、近景資產或外部 OpenTTD 原始碼；沒有查到的資料格式／演算法明確列 gap，不以網路記憶補充。

作者最先需要決定的是：**64 m 格是否合適、初始聚落與實景後備、人口／就業到活動的係數、土地成長如何限制、舊局是否保留 legacy、自由模式如何覆寫、地價是否存歷史，以及 6c 是否同時含 Phase 7 費用**。這些決定齊備後再開實作 PR；本研究不增加正式決策編號，也不升存檔或 golden 版本。
