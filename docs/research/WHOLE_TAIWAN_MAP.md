# 全島地圖研究：一張地圖放下整個台灣

2026-10-08。作者要求先做研究，不改任何遊戲行為：高鐵（台北—左營約 345 km）這類城際系統，在現在每邊 16 km 的地圖上蓋不出來。本文盤點程式裡「地圖不超過 16 km」的假設，量現在的成本，並提出設計草案與分步計畫。草案要作者同意後才實作，屆時另寫成 ARCHITECTURE 的決策。

基準：本 repo `9cdd7d7`（#220 合併後）；參考庫 `5f6ac80c233063c09c4c61571f629881af0b19ec`。

## 1. 結論

- **可以做，但不能只把上限調大。** 整數運算在 2^25 單位（約 524 km）下大多夠用；真正的問題是幾個「隨地圖面積長大」的密集結構、一個隨邊長平方長大的軌道間距檢查，以及把全島人口一次展開成 64 m 土地格的做法。
- **成本要跟著玩家蓋的東西走，不跟著地圖大小走。** 土地只在車站附近展開；城市圖層、地價改成只看有人的格子；軌道間距檢查改成沿線段走格子。
- **城際需求要另外算。** 64 m 土地格的腹地只有 800 m，台北—台中這種旅次要用「城市對城市」的需求；參考裡的城際運量都在伺服器上算（`Ci` 的 `hsr-flow/model`、MapBuilder 的 `buildRidershipPayload`），快照裡沒有，這是缺口。
- **投影建議維持 Web Mercator**，和 Apple 地圖完全對齊；全島南北兩端的比例誤差約 ±1.3%，必要時對距離做緯度修正。參考裡沒有 TWD97／TM2 的程式（缺口）。

## 2. 量測

Linux（雲端容器）、Swift 6.4、`swift test -c release`，暫時的量測測試（沒有提交）：台北車站為中心的 16 km 實景新遊戲。手機會更慢，這些只是相對的量級。

| 項目 | 16 km 台北 | 說明 |
| --- | --- | --- |
| 人口格（WorldPop 30″）讀入 | 0.024 s | 全島資料一次讀入 |
| 土地格匯入（`LandImport.cells`） | 64,342 格、0.021 s | 迴圈跑過邊界內每個 64 m 格 |
| 開新遊戲（`newGame(anchor:land:)`，含建物） | 0.026 s | 居民 4,687,421 人 |
| 跑一天（1440 tick），0／25／100 座車站 | 0.0001／0.007／0.031 s | 車站沒有路線，沒有起訖路徑計算 |
| 存檔大小 | 395,888 bytes | 100 座車站 |
| 存檔編碼／讀檔 | 0.038／0.094 s | |

從人口資料算出的全島規模（`RailwayGameApp/Resources/RealWorld/taiwan_population.json`）：

| 項目 | 數值 |
| --- | --- |
| 有人住的 30″ 人口格 | 27,606 格，共 23,163,504 人 |
| 一個人口格 | 約 0.783 km²，等於 191 個 64 m 土地格 |
| 全島人口全部展開成 64 m 土地格 | 約 527 萬格（現在一張圖最多 65,536 格，約 82 倍） |
| 台灣外框（394 × 144 km）的 64 m 格 | 約 1,385 萬格；2^25 正方形是 6,710 萬格 |
| 只展開車站 2 km 內：100／300／600 站 | 最多約 31／92／184 萬格（實際有人的會少很多） |
| 只展開車站 800 m 內：600 站 | 最多約 29 萬格 |

依 16 km 的量測線性外推（未實測）：全島人口一次展開時，存檔約 32 MB、讀檔約 8 s，土地匯入在台灣外框上約 4–5 s，在 2^25 正方形上約 20 s。這些在手機上都太慢，所以第 4 節改成按需展開。

## 3. 現況盤點

### 3.1 寫死的大小

| 位置 | 內容 | 要怎麼處理 |
| --- | --- | --- |
| `Sources/GameCore/World/WorldBounds.swift:12-18` | `maximumSide = 1 << 20`，`init` 與解碼都拒絕更大的邊 | 改成 `1 << 25`；升存檔版本 |
| `Sources/GameCore/Geometry/WorldCoordinate.swift:36-39` | 座標上限 `1 << 29`，幾何已證明在這之內不溢位 | 不用改 |
| `Sources/GameCore/World/LegacyGrid.swift:17-19` | 1024 格，只用於版本 6 以前的存檔 | 不改 |
| `Sources/GameCore/Geometry/TrackGeometry.swift:91-96` | 有坡度的邊最長 `1 << 24`（約 262 km）；註解說地圖最多 2^20 | 單一條邊不需要那麼長，保留上限、改註解 |
| `Sources/GameCore/City/Land.swift:228-250` | 空白地圖的三座城鎮離中心 2–5 km | 空白新遊戲維持 16 km，不受影響 |
| `Sources/GamePresentation/NewGame.swift:78-81` | `newGameBounds = WorldBounds.maximum` | **要拆開**：空白新遊戲、示範與教學維持 16 km，只有實景選全島時才用大地圖 |
| `Sources/GamePresentation/Tutorial.swift:264,299-301` | 「地圖大約 16 公里見方」 | 教學維持 16 km，不用改 |
| `RailwayGameApp/Views/RealWorldPicker.swift:10,95,156`、`Localizable.xcstrings` | 「這個方框就是你的地圖，每邊 16 公里」 | 加大小選項，字串跟著改 |
| `RailwayGameApp/Views/AppleMapBackground.swift:44,123-125` | 真實鐵路只畫 16 km 內（`railwayReach = 16_000`） | 改成依畫面範圍 |
| `RailwayGameApp/Views/MapView.swift:457` | 軌道樣式選單的 `lines(near:within: 16_000)` | 同上 |
| `GoldenScenarios/README.md:39` | schema 30：每邊 1 到 2^20 | golden 只讀，不用改；文件說明上限改了 |
| 測試 | `WorldBoundsTests`（1,048,576）、`DisplayTextTests`（16.4 km）、`RealWorldMapTests`、`MapCameraTests`、`LandImportTests`、多個用中心 524_288 的測試 | 多數用 `newGameBounds`，拆開後不變；只有直接斷言上限的要改 |

### 3.2 整數溢位（座標到 2^25、距離到約 2^25.5）

都在範圍內：距離平方最多約 2^51；票價分段最多約 2^58.5；三次曲線取樣最多約 2^59；坡度規則因為坡長上限 2^24，最多約 2^61；軌道費用用 `multipliedReportingOverflow`，約 2^33；步行時間約 2^37；營運成本約 2^45；腹地半徑固定 800 m，約 2^41；路徑加總都用 `addingReportingOverflow`。世界座標沒有用 `Float` 或 `Int32`，畫面用 `Double`，精確到 2^53。

### 3.3 隨地圖面積（或邊長平方）長大的工作

| 位置 | 結構 | 在全島的問題 | 草案 |
| --- | --- | --- | --- |
| `LandImport.cells`（`Sources/GamePresentation/LandImport.swift:52-63`） | 迴圈跑邊界內每個 64 m 格，每格做一次反 Mercator 與字典查詢 | 外框 1,385 萬格、正方形 6,710 萬格，開局同步執行 | 改成迴圈跑人口格（27,606 個），只展開需要的範圍 |
| `GameWorld.landValues()`（`Sources/GameCore/City/LandValue.swift:106-127`） | 每格一筆的密集陣列，每格再跑所有有服務的車站 | 格數 × 車站數 | 只算有人的格與車站附近 |
| `CityMap`（`Sources/GamePresentation/CityMap.swift:35-72,110-178`） | 每格約 11 bytes 的密集陣列；每次畫面都走過畫面內的每一格 | 6,710 萬格約 740 MB；縮小時每次畫都走過全部 | 改成稀疏（只存有人的格）或以 1 km 區塊彙總 |
| `TrackSpacing.Pieces.init`（`Sources/GameCore/Geometry/TrackSpacing.swift:158-176`） | 每一小段用它的外框登記 1024 單位的格子 | 一條斜的直線邊是一段，外框格數是 (長/1024)²：2^25 的斜邊約 10.7 億格；16 km 時已有約 100 萬格 | 改成沿線段走格子（DDA），格數只隨長度線性增加；這在 16 km 也有好處 |
| `fullBuildingCells()`（`Sources/GameCore/City/LandDemand.swift:284-306`） | 每個午夜掃全部土地格 | 跟土地格數成正比 | 土地按需展開後就小；或只看車站腹地 |
| `Land.insert`（`Land.swift:174-176`） | 排序陣列的 O(n) 插入 | 按需展開時會頻繁插入 | 批次插入，或改成依列分桶 |
| `CityMapKey`（`RailwayGameApp/Views/MapView.swift:792-807`） | 每次畫面更新比較整份 `Land` 與 `CityBuildings` | 格數大時每幀都慢 | 改用版本號 |

不隨地圖大小長大：人口熱圖（1 km 稀疏列）、旅次需求圖（每站的 1 km 方格）、腹地（每站 800 m 約 490 格）、乘客的起訖路徑（隨車站數平方，每對最多三條路徑）。

### 3.4 實景投影

- `RealWorldFrame`（`Sources/GamePresentation/RealWorldMap.swift:43-98`）把世界單位當成 Web Mercator 的線性縮放，比例取錨點的緯度；Apple 地圖背景（`AppleMapBackground.swift:276-290`）用同一套，所以兩者處處對齊。
- 世界的公尺只在錨點緯度是地面的公尺。16 km 時誤差約 0.06%；全島（北緯 21.9–25.3 度，錨點 23.7 度）南北兩端約 ±1.3%：台北 +1.07%、高雄 −0.82%。
- 選項：
  1. **維持 Web Mercator（建議）**：和 Apple 地圖、Ci 與 Railway 網站一樣；距離與票價最多差 1.3%，需要時依緯度修正「地面公尺」（票價、行駛曲線用的長度）。
  2. **改用 TWD97 TM2（EPSG:3826，`+proj=tmerc +lat_0=0 +lon_0=121 +k=0.9999 +x_0=250000 +ellps=GRS80`）**：全島距離誤差約萬分之一，但 MapKit 只有 Mercator，背景要逐點重投影，畫面可能對不齊；參考沒有實作，要從公式自己寫。

## 4. 設計草案（待作者同意）

1. **上限與新遊戲大小分開**：`WorldBounds.maximumSide` 改成 `1 << 25`；`newGameBounds` 獨立出來，空白新遊戲、示範、教學維持 16 km。實景選點多一個「全島」選項，邊界是台灣外框（含離島時另議），允許長方形。存檔升到版本 16（舊版遊戲讀到大地圖時要顯示「版本較新」而不是「地圖大小錯誤」），加一份新版本的 fixture；舊存檔不需要遷移。
2. **土地按需展開**：全島新遊戲開局時沒有土地格；蓋車站時（GamePresentation 讀人口格），把車站 2 km 內有人的 64 m 格用一個 GameWorld 指令加入世界（存檔、可重播、可復原）。拆站不收回。一般 16 km 實景遊戲照舊一次展開。
3. **密集結構改稀疏**：`landValues`、`CityMap`、`LandImport` 改成只看有人的格；`CityMapKey` 改用版本號。
4. **軌道間距檢查沿線段走格子**（DDA）。
5. **城際需求**（之後的步驟）：車站腹地外再加一層「城市對城市」的需求，用 1 km 人口格依距離衰減（重力模型）；OpenTTD 的 `demand_distance`、`demand_size` 只有設定名稱，公式要自己定（缺口）。
6. **高鐵**：App 已經內含 `thsr_track.json`（352.2 km、12 站）與 `thsr-schedule.json`；`Ci` 的高鐵規則可以移植：不超載、8／16／17 節（650／1,200／1,283 人）、200–350 km/h、票價 `max(20, 公里 × 0.45)`（人民幣，換算台幣要另定）。Railway 網站的 `PERF_HSR`（加速 1.4、減速 1.5、300 km/h、惰行參數）可以當行駛性能。
7. **畫面**：縮小時只畫幹線與車站名稱分級；真實鐵路背景依畫面範圍取；相機的最小縮放本來就由邊界決定。
8. **效能預算**：起訖路徑與城際需求在背景執行緒分批重算（`Ci` 的 `maxPathsPerOd: 5`、`maxTransferCount: 1`；OpenTTD 的 linkgraph 也是分執行緒、隔幾天合併）。

## 5. 分步計畫

| 步 | 內容 | 動存檔 | 動 golden／replay | 驗證 |
| --- | --- | --- | --- | --- |
| A | 軌道間距改沿線段走格子；`landValues`、`CityMap`、`LandImport` 改稀疏；`CityMapKey` 改版本號 | 否 | 否（行為不變，要用測試證明結果相同） | Linux 測試；16 km 的時間不能變差 |
| B | 上限改 2^25、新遊戲大小分開、存檔版本 16、全島選項、土地按需展開、背景鐵路依畫面範圍 | 是（v16） | 否 | Linux 量全島開局、存檔、跑一天；TestFlight 實機 |
| C | 城際需求（重力模型）與高鐵規則；可選擇預先鋪好高鐵 | 視設計 | 視設計 | 同上 |

每一步都先在 Linux 量時間與記憶體，再用 TestFlight 確認手機上的開局時間、存檔大小與每天的計算時間。

## 6. 參考對照

| 參考檔案／函式 | 目標 | 方式 |
| --- | --- | --- |
| `Railway/site_archive_clean/data/thsr_track.json`（TDX，352.2166 km，571 點，12 站含里程） | 高鐵預設路線（步驟 C） | direct：App 已內含同一份（`RealRailways/thsr_track.json`） |
| `Railway/site_archive_clean/api/thsr-schedule.json`（169 班，`arrSec`／`depSec`） | 高鐵時刻表（步驟 C） | direct：App 已內含 |
| `Railway/site_archive_clean/index.html` 第 8153 行 `PERF_HSR = { a: 1.4, b: 1.5, aAlt: 2.0, bAlt: 2.7, v: 300, coast: {c: .45, rho: .45} }` | 高鐵的 `TrainPerformance` | adapted（步驟 C） |
| 同站 `client.js` `visibleRoutes(lines, bounds)`（依畫面外框裁切、±0.006°）；z ≥ 14 才畫細節 | 背景鐵路依畫面範圍、分級細節（步驟 B） | adapted |
| 同站 `rail-3d/integration/map3d.js`：`MercatorCoordinate.fromLngLat([121,24])` 當錨點的局部公尺 | 維持 Web Mercator 的決定 | 一致 |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`：`getMetroTrainOperationalCap`（高鐵不超載）、`HSR_TRAIN_CARS_CAPACITY = {8: 650, 16: 1200, 17: 1283}`、`HSR_TRAIN_SPEED_OPTS = [200, 250, 300, 350]`、`hsrFarePassengerPrice`（`max(20, round(km × .45))`） | 高鐵規則（步驟 C） | adapted：票價幣別要換算 |
| 同檔：`hsrPassengerFlowModelOptions(){ maxTransferCount: 1, maxPathsPerOd: 5 }`、延後分批重算（`hsrEnsurePassengerFlowsForAllLines({defer})`）、8 ms 的幀預算 | 起訖路徑的上限與背景重算 | adapted（步驟 B／C） |
| 同檔：`hsr-flow/model` 在伺服器算運量 | 城際需求 | gap：快照沒有模型，要自己定 |
| `Railway/railway_game_reference_clean/docs/linkgraph.md`：多商品流在獨立執行緒算、`recalc_time`、大地圖要調大時間 | 背景重算策略 | adapted |
| 同 pack `binary_reference/relevant_symbols_and_settings.txt`：`demand_distance`、`demand_size`、`linkgraph.accuracy` | 城際需求的參數名稱 | gap：只有名稱，沒有數值與公式 |
| `MapBuilder/.../pages/_app-*.js` 的路線尺度（`LOCAL`、`REGIONAL`、`LONG`，`zoomThreshold` 9.5／7／3.5） | 縮小時依路線尺度決定要不要畫 | adapted（步驟 B） |
| （參考沒有） | TWD97 TM2 投影、土地按需展開、稀疏地價／城市圖層、沿線段走格子的間距檢查 | gap → 原生 |

`Railway/taipei_gta_reference/` 是區域尺度的 3D 世界（繪製距離最多 1300 m），`Simulator/` 是模型鐵道的毫米座標，兩者都沒有全島尺度可用的東西。
