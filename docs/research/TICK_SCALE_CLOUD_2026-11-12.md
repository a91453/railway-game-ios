# 大型城市與列車模擬：Tick 效能與雲端化可行性（2026-11-12）

作者 2026-11-12 交辦，遊戲規劃第 62 任派工（TICK-SCALE，session_01YGNNumgSxrD9bRjhhA8vAs，工作登記 #1579）。分支 `claude/tick-scale-study`，從 main `d144ea41` 起。

**這是研究**：只加這份文件與一個平常不跑的基準測試（`Tests/GameCoreTests/TickScaleReportTests.swift`）。`Sources/` 一行都沒改，golden、存檔、重播 fixture 沒動，沒有建立任何雲端資源。每個提議都寫成「最小可行實驗」，要不要做、取哪個決策號由規劃決定。

標記的意思：
- **VERIFIED**：實際跑過，寫明在哪台機器、哪種建置。
- **讀程式**：讀原始碼得到的，附檔案與行號（行號是 main `d144ea41` 的）；沒有執行。
- **估算**：推算，寫明假設；不是實測。

量測的機器都是雲端 Linux 容器（x86-64，4 核心，15 GB，Swift 6.4.0）。**這些數字不代表 iPhone 或 iPad**；第 2.6 節列出要在 Mac 與實機補量的項目。

章節照交辦的六項交付：

1. 現有 Tick 架構與效能瓶頸
2. 基準測試：100 到 10,000 輛列車
3. 本地優化與雲端化的收益比較
4. 建議的模擬分層架構
5. 離線及同步設計
6. 分階段計畫、風險與驗收；值得先做、暫緩、不建議做

---

## 1. 現有 Tick 架構與效能瓶頸

### 1.1 一句話

整個模擬只有一個入口：`GameWorld.advance(ticks:)`（`Sources/GameCore/World/GameWorld.swift:3449–3714`）。它是單執行緒、純值語意的一個函式，App 每 100 ms 在背景執行緒上叫它一次、算完在主執行緒換上結果。GameCore 沒有第二個 tick 系統：城市、經濟、旅客、貨運都掛在這個迴圈的「整分」「整點」「午夜」上。

### 1.2 呼叫鏈與更新頻率

| 層 | 位置 | 做什麼 |
| --- | --- | --- |
| App | `RailwayGameApp/App/RailwayGameApp.swift:109` → `GameLauncher.setActive`（`Sources/GamePresentation/GameLauncher.swift:2141–2169`） | 只負責開始、停止遊戲迴圈與自動存檔；App 裡沒有 Timer、display link 在推 tick |
| 遊戲迴圈 | `GameSession.startGameLoop()`（`Sources/GamePresentation/GameSession.swift:2621–2650`） | 主 actor 上的一個 `Task`：睡 → 算該跑幾個 tick（`dueTicks`）→ `runLoopStep` → 照 `TickPace` 算下次睡多久 |
| tick 週期 | `GameSession.tickInterval = 100 ms`（`GameSession.swift:1163`，ARCHITECTURE 決策 12） | 倍速不改 tick 的頻率，改的是每個 tick 走多少遊戲時間 |
| 每 tick 的遊戲時間 | `GameSpeed.tenthsPerTick`（`Sources/GameCore/Time/GameClock.swift:89–98`） | 1×：0.1 秒；10×：1 秒；60×：6 秒；600×（`.normal`）：60 秒；1200×：120 秒；6000×（`.fast`）：600 秒 |
| 追不上時 | `TickAccumulator`（`Sources/GamePresentation/TickAccumulator.swift:12–45`）、`maximumStepDuration = 500 ms`（`GameSession.swift:1164`） | 一步最多補 5 個 tick；算 tick 花的時間算進經過的時間，所以追不上就是「遊戲時間變慢」，不會越欠越多（決策 143）；決策 464 在低於設定倍速 70% 持續 20 秒時提示一次 |
| 依機型 | `DeviceCPUTier`／`TickPace`（`Sources/GamePresentation/DeviceLoad.swift:96–158`，決策 460） | 算完一步後休息「工作時間 ×(1−share)/share」，share 是 0.6／0.8／1，過熱降到 0.6／0.4；**沒有依機型限制倍速或地圖大小**（決策 460 否決了） |
| 背景計算 | `LoopTick.work()`（`GameSession.swift:2350–2386`） | `Task.detached(priority: .userInitiated)` 裡叫 `GameSession.advanced(world, by: 1, …)`，一次一個 tick；之前先在所有核心上預算旅客路徑（`PassengerRoutesAhead`，決策 470） |
| 交回主執行緒 | `finish(_:fromLoop:)`（`GameSession.swift:2193–2289`） | `world = step.world`、記進指令紀錄 `.advance(ticks:)`、套用暫存的倍速 |
| 模擬本體 | `GameWorld.advance(ticks:)` | 見 1.3 |

其他直接叫 `advance` 的地方：無畫面的 `HeadlessGame`（`Sources/GamePresentation/HeadlessGame.swift:174–246`，一次最多一天）、政策試玩（`Policy.swift:497–518`）、跳過夜晚的試跑（`NightSkip.swift:66–82`，在世界的副本上）、示範與截圖場景的開局。

### 1.3 `advance(ticks:)` 裡面：一個迴圈、三種節拍

`advance` 把 tick 換成「基本步」（遊戲秒，`GameClock.basicSteps`），然後跑一個 `while remaining > 0` 的迴圈（`GameWorld.swift:3488–3699`）。每一圈走一段 `span`（1 到 60 遊戲秒），`span` 取到「這一分鐘結束、下一個停站事件、下一段進路走完、下一段軌道放出來」之中最近的一個（3573–3618）。所以它**已經是半事件驅動**：沒有事的秒數不逐秒走；整分鐘沒有任何列車變化時，還會一次跳到下一個可能有事的分鐘（3647–3698，「exact shortcut」，逐分的旅客釋出與結帳照做）。

| 節拍 | 做的事 | 位置 |
| --- | --- | --- |
| **每一圈**（1–60 遊戲秒） | 跟車列車延長授權 `extendAuthorities`；交會待避計畫 `trafficPlan`；停站與發車 `runServices`（含 `stepDwell`、`departService`、上下車）；真實班次的速度 `solveRuns`、間隔 `assessSpacing`；找下一個事件（`nextServiceEvent`、`secondsUntilARouteEnds`、`secondsUntilARouteFrees`、`secondsUntilTrafficChanges`）；移動列車 `moveTrains`；`dropRunsHeldUp`；記到站 `recordArrivals` | `GameWorld.swift:3493、3547、3554、3575–3618、3631、3644` |
| **每遊戲分鐘** | 各線班次等級 `serviceLevel`；貨運 `tickFreight`（內部整點才做，`Freight/Freight.swift:587`）；結帳 `settleAccounts`（內部整點才做，午夜做 `settleDay`，`Economy/Operations.swift:358–363`）；04:00 送走候車的人；釋出旅客 `releasePassengers`；派車 `dispatchTrains`；解死結 `resolveDeadlock`／`changeBerth`／`makeWayForDepot` | `GameWorld.swift:3496–3541、3564` |
| **午夜** | 城鎮成長 `growTowns`（`Passenger/TownGrowth.swift:129`）、活動日、觀光與機場的日結、當日旅客計畫重算；每月第一個午夜長路 `growRoads`（`City/RoadGrid.swift:445`） | `GameWorld.swift:3510–3531` |

公車、渡輪、纜車、機場**沒有自己的 tick**：只在午夜的日結裡算（`Passenger/BusRoute.swift:775`、`Ferry.swift:591`、`Cableway.swift:632`、`Airport.swift:370`）。城市的土地、人口也只在午夜或月初動。所以「城市人口與經濟」不是每 tick 的負擔；每 tick 的負擔幾乎都在列車與行車控制。

### 1.4 各項運算實際在哪裡

| 項目 | 位置 | 多久算一次 |
| --- | --- | --- |
| 列車運行 | `moveTrains`（`GameWorld.swift:5383`）、`solveRuns`（5483）、`Railway/RunningCurve.swift` | 每一圈 |
| 進路預約、閉塞 | `Railway/RouteReservation.swift`（`reserving` 185、`reservingDeparture` 321、`trackHolders` 977–1001、`alternativeRoute` 383）、`Railway/BlockSections.swift` | 每一圈；每個要發車或跟車的列車 |
| 交會、待避（調度） | `Railway/ScheduledTraffic.swift`（`trafficPlan` 258、`inferTrafficMeets` 435–470） | 每一圈查鍵，鍵變了就重算 |
| 死結 | `Railway/Deadlock.swift:249–278`、`passingPlace` 332–349 | 每遊戲分鐘 |
| 派車、車輛接班（下一趟由哪列車跑、出入庫） | `dispatchTrains`（`GameWorld.swift:3794`）、`readyTrain`（4002）、`Railway/LineRuns.swift:463–500`、`RunDepot.swift`、`Depot.swift:415–430`、`runTrainPutOnItsRun`（`GameWorld.swift:4596`） | 每遊戲分鐘 |
| 路線搜尋 | `Railway/TrainRoute.swift:63`（`shortest`，堆積在 129–141）、`ServicePath.swift:131–171`、`ServiceDirections.swift` | 沒命中記憶時；帶「避開」條件的搜尋不記（290–313） |
| 旅客需求、旅客路徑 | `Passenger/PassengerDemand.swift`（`passengerRelease` 918、`releasePassengers` 976）、`PassengerRoutes.swift`、`passengerPlan` 快取 | 釋出每分鐘；全網路徑只在鍵或日子變時重算 |
| 上下車 | `Passenger/Boarding.swift:153、323`、`DoorCrowding.swift` | 每列停站中的列車、每分鐘 |
| 經濟 | `Economy/Operations.swift:358–470` | 整點、午夜 |
| 城市人口、土地 | `Passenger/TownGrowth.swift:129`、`City/LandDemand.swift:391`、`City/RoadGrid.swift:445` | 午夜、月初 |

### 1.5 資料怎麼存、怎麼找

| 東西 | 存法 | 用 ID 找 |
| --- | --- | --- |
| 列車 | `[Train]`，照 ID 排序（`GameWorld.swift:18`） | `train(id:)` 是**線性搜尋** `trains.first { $0.id == id }`（2020–2022） |
| 路線 | `[ServiceLine]`（`GameWorld.swift:20`） | `line(id:)` 線性（2597–2599）；`assignedLine(of:)` 掃每條線每個服務的列車清單（3088–3090） |
| 車站 | `[Station]`（`GameWorld.swift:16`） | `station(id:)` 線性（347–349） |
| 軌道邊、節點 | 排序陣列（`Railway/RailwayNetwork.swift:157–158`） | 二分搜尋（327–343） |
| 月台 | `[TrackPlatform]`（`RailwayNetwork.swift:165`） | `platforms(on:)`、`platforms(of:)` 是線性 `filter`（284–291） |
| 候車、車上旅客 | `[StationPassengers]`、`[TrainRiders]`（`GameWorld.swift:40、44`） | 線性 `first { … }` |
| 誰佔哪段軌道 | 每列車自己帶 `reservation`（`Railway/Train.swift:101`） | 全世界的索引 `TrackHolders` 每次從所有列車重建（`RouteReservation.swift:977–1001`） |

沒有空間索引：GameCore 的規則都走軌道圖（邊與節點），不問「這附近有誰」；需要「這段軌道上有誰」時靠上面那個每次重建的 `TrackHolders`。

### 1.6 執行緒模型與資料複製

- **GameCore 完全單執行緒**：整個 `Sources/GameCore/` 沒有任何 `import`（連 Foundation 都沒有），沒有 Dispatch、Task、actor、鎖（讀程式，grep）。
- **tick 不在主執行緒**：`Task.detached`（`GameSession.swift:2350–2386`）。主執行緒只做交回後的收尾（聲音、新聞、跟車、記錄），站長建議每遊戲小時、地圖泡泡每 10 遊戲分鐘，都在背景那個 tick 裡先算好（決策 330、465、497）。
- **世界怎麼交接**：`beginLoopTick()`（`GameSession.swift:2391–2405`）把整個 `GameWorld` 值連同 `worldRevision` 交給背景。`GameWorld` 約 75 個儲存屬性（`GameWorld.swift:10–316`），大的都是陣列，copy-on-write：交出去時不複製，tick 第一次寫某個陣列時才整個複製那一個（ARCHITECTURE 4544 行）。量到的成本見 2.4。
- **tick 算到一半玩家下指令**：指令立刻改主執行緒上的 `world`，那個算好的 tick **整個丟掉**（`guard tick.revision == worldRevision else { return false }`，`GameSession.swift:2559`），遊戲時間落後一個 tick；只有改倍速會先存著等 tick 回來（1771–1777）。這已經是「在 tick 邊界套用」的最小形式，第 5 節的設計沿用它。
- **存檔**：`SaveFile` 包 `SavedGame(world:)`，JSON（`Sources/GamePresentation/SaveLibrary.swift:904–918`）；每 900 秒自動存（`GameLauncher.swift:40`），世界在主執行緒取值、編碼與寫檔在一條背景序列佇列（`GameLauncher.swift:141、1962`）。

### 1.7 找到的瓶頸

下面每一條都是讀程式找到、再用 2.3 節的取樣對過的。T 是列車數、L 是路線數、S 是車站數。

**A. 用線性搜尋當查表，包在逐列車的迴圈裡，變成 O(T²)**

| # | 哪裡 | 為什麼是平方 |
| --- | --- | --- |
| A1 | `nextServiceEvent`（`GameWorld.swift:5250`）→ `closingStart`（4873–4876） | 每一圈、每列停站的列車都跑 `lines.contains { $0.isRing && $0.trains.contains(train.id) }`：掃所有路線的列車清單 |
| A2 | `deadlock(memo:)`（`Deadlock.swift:257`） | 每列車 `lines.first(where: { assignedLine(of: train.id) == $0.id })`：`assignedLine` 本身掃所有線，外面再包一層 `lines.first`，每列車 O(L·T)，合計 O(T²·L)；每遊戲分鐘 |
| A3 | `assignedLine(of:)`（`GameWorld.swift:3088`） | 本身 O(T)；同樣的 `lines.first(where: { assignedLine… })` 寫法還有 `Deadlock.swift:118、148、180、197、442` 與 `GameWorld.swift:4392、4472、4501、4545` |
| A4 | 上下車：`Boarding.swift:105、330、334`、`DoorCrowding.swift:113–115` | 每列停站的列車各做幾次 `riders.first`、`assignedLine` |
| A5 | 派車：`readyTrain`（`GameWorld.swift:4002–4004`）、`LineRuns.swift:475–482`、`runningTrains`（`Depot.swift:415–419`） | 每條線的每列車 `trains.firstIndex`；`runningTrains` 掃全部列車；合計 O(L·T) 每分鐘 |
| A6 | `recordTrafficVisits`（`GameWorld.swift:6744、6757`）、`secondsUntilTrafficChanges`（5791） | 每列車 `plan.services.first(where:)` |
| A7 | `serviceLevel`（`Railway/LineJourney.swift:212`） | `lines.map { serviceLevel(of: $0.id…) }` 每分鐘，裡面 `line(id:)` 線性：O(L²) |

**B. 每一圈重建全世界的索引**

| # | 哪裡 | 說明 |
| --- | --- | --- |
| B1 | `trackHolders(memo:)`（`RouteReservation.swift:977–1001`） | 記憶的鍵是「整個 `[Train]` 相等」（978），只留 2 份（999）。列車一動鍵就不同，於是每一圈從所有列車重建；比對鍵本身就是 O(T) |
| B2 | `extendAuthorities`（`GameWorld.swift:5593–5625`） | 每延長一列跟車列車的授權就 `holders = nil`（5613、5623），下一列再重建一次：O(跟車數 × T) |
| B3 | `trafficPlanKey()`（`ScheduledTraffic.swift:248–253`） | 鍵含每列車的執行狀態與到發時間，任何一列車到站或發車就失效；重算時 `inferTrafficMeets`（435–470）是服務數的平方乘上每個服務的點數平方 |
| B4 | `runServices` 的 `standingEdges`／`movingEdges`（`Railway/RunSpacing.swift:515、529`）、沒開行車控制時的 `spacingIndex`（123–133） | 每一圈由所有列車重建集合 |

**C. 為了問「幾秒後有路空出來」把世界複製再往前走**

`secondsUntilARouteFrees`（`GameWorld.swift:5703–5724`）每試一個秒數就 `var moved = self`、移動所有列車、重建 `trackHolders`、再問每一組等路的發車。APP_TICK_COST 第 6 節量過：高鐵示範開閉塞時它佔一天的一半，改成加倍試之後一天仍要 348 秒（Linux release，35 組列車）。那份研究已經寫下結論：要再快一個數量級，得改成「只在等的那幾段軌道放出來時才重試」。

**D. 行程紀錄每次發車整個掃一遍**

`logArrival`（`Railway/TrainTrips.swift:226–239`）在每一趟的第一站叫 `dropTrips`（292–297），對整個 `tripLog` 做 `removeAll`，再在中間 `insert`。紀錄留今天與昨天的每一趟，所以每天的成本是「趟數 × 紀錄長度」。

**E. 指令這一側（不在 tick 裡，但同一個形狀）**

每個改軌道、路線的指令最後跑 `abandonUnservedPassengers()`（全地圖每一群候車的人重算行程）。PERF_REAL_MAP 第 1 節量過：67 站 13 線時一次幾十毫秒，一個收購要上百步，共 24 秒；已用 `editTrackAsOne` 包起來修掉兩個指令，其餘（`buildTrackChain`、`buildDoubleTrackChain`、`autoService`）還沒有。

**沒有找到的**：主執行緒上沒有模擬計算（決策 330、485、497 已經搬走）；城市、經濟不是每 tick 的負擔；軌道邊與節點的查找已經是二分搜尋。

### 1.8 已經做過的（不要重提）

| 做了什麼 | 出處 |
| --- | --- |
| tick 搬到背景執行緒、站長建議與交通讀數在背景算 | 決策 330、465、497 |
| 行程、容量、出庫空車跨 `advance` 記住（`RouteMemo.ServiceKey`）：高鐵示範一週 6000× 從 97 秒到 36 秒 | `docs/research/APP_TICK_COST_2026-10-18.md` 第 5 節 |
| 交會計畫的零件跨 `advance` 借用、`alternativeRoute` 一次問一條軌道、`secondsUntilARouteFrees` 加倍試、`releasePassedTrack` 少算、邊與節點先猜位置：開閉塞的一天 741 秒到 348 秒 | 同上第 6 節 |
| 死結搜尋共用一份 `DispatchMemo`：120 站 40 列車的搜尋從 0.97 秒降下來 | `docs/research/BUGHUNT_HANG_2026-10-30.md`、`Tests/GameCoreTests/DeadlockSearchCostTests.swift` |
| 收購與刪線包成一次編輯 | `docs/research/PERF_REAL_MAP_2026-10-30.md` |
| Linux 上 GameCore 與測試用 -O、iOS Debug 也用 -O | 決策 544、624 |
| 旅客路徑在所有核心上預算 | 決策 470 |
| 依機型的休息比例、跟不上倍速的提示 | 決策 460、464 |
| 月台軌道、待避位置、每段路徑、方向保護的路徑、待避計畫的軌道都記住 | 決策 597、620、622、637 |

**試過、退回的**：把 `GameWorld` 包成堆積上的 copy-on-write 物件（決策 590，CRASH114）：iOS Debug 會當，連 `network` 一起搬時高鐵示範的 tick 還慢 37%。沒有 macOS 上的重現不要重做。

**考慮過、沒做的**：把 `freePlatformOnTheWay` 改成事件驅動（決策 597 第 39 行：改動太大、會動重播 fixture）。這份研究第 3.1 節的 L3 是同一個方向，所以把它排在最後，並要求先有「結果逐位元相同」的證明方法。

### 1.9 已經在紀錄上的數字（這次沒有重量）

| 什麼 | 數字 | 機器、建置 | 出處 |
| --- | --- | --- | --- |
| 背景 tick，600×，中位數／p95 | 簡單示範 0.5／1.3 ms；高鐵示範（15 站 35 列車）3.6／6.3 ms；宜蘭線示範（13 站 34 列車）1.3／3.3 ms | Linux 4 核心，release | `PERF_TIERS_2026-10-30.md` §2.3 |
| 同上，6000× | 5.5／6.3；27.2／55.5；14.0／56.1 ms | 同上 | 同上 |
| 大存檔 81 站 145 列車，6000× | 約 240 ms／tick | — | 同上，引決策 460 |
| 作者的存檔（整個臺灣，16 線），600× | 平均 214 → 165 ms，p95 396 → 339 ms（預算 100 ms） | Linux release，1,440 tick | 決策 597 |
| 那個存檔的熱點 | `runServices` 74%（`freePlatformOnTheWay` 43%、`trainLeavingTowards` 31%）、`assessSpacing` 14% | gdb 取樣 | 決策 597 |
| 作者的實機回報（iPhone18,1，67 站 13 線 74 列車） | 6000× 每 tick 平均 127–172 ms、最長 1.0–1.2 s（重播，Linux release） | Linux release | `PERF_REAL_MAP_2026-10-30.md` §3 |
| 高鐵示範開號誌與閉塞跑一天 | 741 → 348 s（35 組列車） | Linux release | `APP_TICK_COST_2026-10-18.md` §6 |
| 每天 06:00 的旅客計畫 | 54 站 0.75 s、74 站 2.6 s（debug，約站數的三次方）；81 站 22 線約 14 s | Linux | 決策 143 的補充、NEXT_PRIORITIES（PLANDAY） |
| `MemoryLayout<GameWorld>.size` | 2,032 位元組 | Linux | 決策 590 |
| `advance(ticks:)` 的堆疊框 | 68,816 位元組 | -O，x86-64 | 決策 590 |

這些數字本身已經回答了一半的問題：**現在的遊戲在 74–145 列車、開行車控制時，600× 就已經超過每 tick 100 ms 的預算**。所以第 2 節的基準不是要證明「一萬輛跑不動」（那不用量），而是要量出成本隨列車數怎麼長、長在哪裡，才知道先修哪一條。

## 2. 基準測試：100 到 10,000 輛列車

### 2.1 怎麼量

`Tests/GameCoreTests/TickScaleReportTests.swift`，平常不跑（沒有 `TICK_SCALE_REPORT` 就跳過，CI 也跳過），不讀也不寫任何 fixture，`Sources/` 沒有為它加任何東西。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
TICK_SCALE_REPORT=10,25,50,100,200 swift test --skip-build --filter TickScaleReportTests
# 其他開關：TICK_SCALE_LAYOUT=solo、TICK_SCALE_CONTROL=0、TICK_SCALE_BLOCKS=1、
# TICK_SCALE_SPLIT=2、TICK_SCALE_TICKS=30、TICK_SCALE_BUDGET=600、TICK_SCALE_HOLD=120
```

- **地圖**：一個「單線、中間一個交會站」的小模組（西–中–東三站，測試裡現成的 `SingleTrackMeet`），在格子上重複。預設（`meet`）每個模組兩條對開的路線、各一列車，在中間站交會；`solo` 每個模組一條線一列車。模組之間軌道不相連。
- **為什麼用這個**：它是能讓「行車控制」（交會、待避計畫）真的有事做的最小地圖，而且模組彼此獨立，所以量到的超線性成長全部是程式的成長，不是地圖本來就該有的互動。它**不是**真實路網：一列車一條線，路線數比真實存檔多得多；沒有城市，所以沒有旅客（表裡「候車」都是 0）。真實存檔的數字在 1.9。
- **量什麼**：先跑 60 個 tick 暖身，再量 600×（每 tick 60 遊戲秒）的 tick，取中位數、p95、最慢；再量 6000× 的 tick。每 tick 的預算是 100 ms（1.2）。另外量：整個世界 JSON 存檔的大小與編、解碼時間；程序的常駐記憶體。
- **建置**：`swift build` 的 debug 組態。在 Linux 上 `Package.swift` 讓 GameCore 與 GameCoreTests 都用 `-O`（決策 544，`Package.swift:17–19`），所以量到的是最佳化過的 GameCore；沒有另外做 `-c release` 的測試建置（要另外編約半小時，而且和 debug 組態差的只是跨模組最佳化；這是這份報告的限制，2.6 列為要補量的項目）。
- **機器**：雲端 Linux 容器，x86-64，4 核心，15 GB，Swift 6.4.0。幾組同時跑（一組一個核心），所以數字有一成上下的誤差；結論只用到數量級。

以下每一列都是 **VERIFIED（這台雲端 Linux，debug 組態、GameCore `-O`）**。

### 2.2 結果

**(a) 現在的遊戲，行車控制開（玩家有交會的路網時的狀態），一個世界**

| 列車 | 路線 | 車站 | 600× 每 tick 中位數 | p95 | 最慢 | 6000× 中位數 | 有動的列車 | 死結 | 結果 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 10 | 10 | 15 | 1.26 ms | 4.44 | 5.73 | 15.1 ms | 10 | 0 | 在預算內 |
| 25 | 25 | 39 | 10.90 ms | 21.90 | 22.25 | 91.1 ms | 25 | 0 | 在預算內 |
| 50 | 50 | 75 | 73.58 ms | 123.02 | 123.51 | 525 ms | 50 | 0 | 600× 勉強，6000× 超過 |
| 100 | 100 | 150 | **617.69 ms** | 952.62 | 1,046.16 | 4,025 ms | 100 | 0 | 超過預算 6 倍 |
| 200 | 200 | 300 | **3,876.73 ms** | 6,407.60 | 6,691.61 | 26,557 ms | 200 | 0 | 超過預算 39 倍 |
| 500 | 500 | 750 | — | — | — | — | — | — | **沒有跑完**：暖身 60 個 tick 只跑了 8 個就到 420 秒的上限；那 8 個 tick 每個 23 到 98 秒（預算的 230 到 980 倍） |
| 1,000 | 1,000 | 1,500 | — | — | — | — | — | — | **沒有跑完**：暖身的第 1 個 tick 就花了 451 秒，超過上限 |
| 5,000、10,000 | — | — | — | — | — | — | — | — | **沒有跑**：照上面的成長，一個 tick 要以小時計 |

列車加倍，每 tick 的時間變 6.3 到 8.4 倍（25→50：6.8；50→100：8.4；100→200：6.3），也就是**大約列車數的 2.7 到 3 次方**。模組彼此不相連，理想的成長是 1 次方。

**(b) 同一張地圖，關掉行車控制（`TICK_SCALE_CONTROL=0`）**

| 列車 | 600× 中位數 | p95 | 最慢 | 6000× 中位數 | 建地圖 | 結果 |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 10 | 0.20 ms | 1.53 | 1.68 | 4.2 ms | 0.0 s | 在預算內 |
| 100 | 4.91 ms | 18.48 | 25.08 | 63.0 ms | 0.2 s | 在預算內 |
| 500 | 80.89 ms | 216.92 | 226.66 | 1,110 ms | 2.3 s | 中位數在預算內，p95 超過 |
| 1,000 | **306.03 ms** | 887.25 | 905.91 | 4,025 ms | 8.5 s | 超過預算 3 倍 |
| 5,000 | — | — | — | — | 209 s | **沒有跑完**：暖身 60 個 tick 跑了 50 個就到 600 秒的上限；每個 tick 6 到 20 秒（預算的 60 到 200 倍） |
| 10,000 | — | — | — | — | 超過 600 s | **沒有跑完**：連地圖都沒建完，600 秒的上限到時放了 8,672 列（蓋軌道是平方成長，2.3） |

列車變 2 倍（500→1,000）時間變 3.8 倍：**大約 2 次方**。

**(c) 同樣的模組，拆成每 2 列車一個獨立的世界，時間相加（`TICK_SCALE_SPLIT=2`，行車控制開，單執行緒）**

| 列車 | 世界數 | 600× 中位數 | p95 | 6000× 中位數 | 存檔 JSON | 編碼 | 解碼 | 常駐記憶體 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 50 | 6.08 ms | 29.93 | 107 ms | 0.13 MB | 12 ms | 40 ms | 49 MB |
| 500 | 250 | 31.19 ms | 152.89 | 471 ms | 0.64 MB | 55 ms | 189 ms | 63 MB |
| 1,000 | 500 | 68.13 ms | 395.75 | 981 ms | 1.29 MB | 109 ms | 420 ms | 80 MB |
| 5,000 | 2,500 | 374.36 ms | 1,736.47 | 5,634 ms | 6.43 MB | 548 ms | 1,988 ms | 214 MB |
| 10,000 | 5,000 | **670.13 ms** | 3,758.88 | 10,563 ms | 12.86 MB | 1,204 ms | 4,823 ms | 383 MB |

這一組是直線：每列車約 0.07 ms。它是「如果互不相干的列車真的互不影響成本」的**上限**，不是提議把存檔拆成幾千個世界。**10,000 輛列車只有在這個形式下跑完**，而且單執行緒仍是預算的 6.7 倍。

**(d) 其他**

| 變化 | 列車 | 600× 中位數 | 對照 (a) |
| --- | ---: | ---: | --- |
| 閉塞區間開（`TICK_SCALE_BLOCKS=1`） | 10／25／50／100 | 1.94／15.84／79.83／586.77 ms | 差不多：這張地圖的成本不在閉塞 |
| 每模組一條線一列車（`solo`） | 10／25／50／100 | 1.00／8.15／50.51／398.06 ms | 同一個形狀：沒有對向車也是 3 次方 |
| 每模組一條線一列車（`solo`） | 200 | 3,184.63 ms | 同上（100→200：8.0 倍） |

### 2.3 時間花在哪裡（取樣）

在 100 列車、行車控制開的那一組跑的時候，用 gdb 每 2 秒停一次、看堆疊，共 25 次（VERIFIED，同一台機器）：

| 堆疊裡有 | 次數（共 25） |
| --- | ---: |
| `GameWorld.advance` | 25 |
| `trafficPlan(memo:)` → `trafficPlan(parts:paths:headwayOvertakes:)` | 23 |
| `planTrafficOvertakes` → `hasRoutePreferences` | 20 |
| 　其中停在 `assignedLine(of:)` | 13 |
| 　其中停在 `line(id:)`（含複製 `ServiceLine` 的 retain／release） | 7 |

對照程式：`planTrafficOvertakes`（`Sources/GameCore/Railway/ScheduledTraffic.swift:618–628`）對**每一對**服務叫兩次 `hasRoutePreferences`（`Railway/LineRoutePreference.swift:294–301`），它每次叫 `assignedLine(of:)`（掃所有路線的列車清單，`GameWorld.swift:3088`）再 `line(id:)`（線性，2597）。服務數的平方乘上路線數，就是量到的 3 次方。計畫的鍵（`trafficPlanKey`，1.7 的 B3）在任何一列車到站或發車時就失效，100 列車時幾乎每一圈都有車到發，所以每一圈重算。

關掉行車控制、5,000 列車那一組的取樣（每 20 秒一次）：建地圖的 209 秒全部在 `buildTrackEdge` → `firstConflict`（`Geometry/TrackClearance.swift:219`）與 `addFouling`（`Geometry/TrackFouling.swift:87`）→ `planBox`：**每蓋一段軌道都和全地圖每一段比一次**，所以建地圖是軌道段數的平方（500 列車 2.3 秒、1,000 列車 8.5 秒、5,000 列車 209 秒）。進到 tick 之後的 16 次取樣：`runServices` 8 次（其中 `departService` 5、`routePreference` 3，底下是 `line(id:)` 與 `assignedLine(of:)`），`dispatchTrains` 5 次（其中 `isDispatchDue` → `runningTrains` 4，1.7 的 A5），`closingStart` 2 次（A1），`serviceLevel` 2 次（A7）。都是「每列車掃一遍全部路線或全部列車」，沒有一個是真的在算列車怎麼走。

**和真實存檔的差別**：作者那個整個臺灣的存檔，取樣是 `runServices` 74%（`freePlatformOnTheWay`、`trainLeavingTowards`）、`assessSpacing` 14%（決策 597，1.9）。那裡路線少（16 條）、每條線列車多、軌道相連，所以熱點在「等路」；這張合成地圖路線多、彼此不相連，熱點在「查表」與「整份計畫重算」。兩種都會隨規模變大而出現，要一起修。

### 2.4 複製與序列化的成本

- **交給背景執行緒**：copy-on-write，交出去不複製，tick 寫到哪個陣列才複製哪個（1.6）。基準裡「複製一份再走一步」那一欄（100 列車 921 ms，對照一個 tick 618–1,046 ms）分不出複製的部分：在這個規模，複製比 tick 本身的起伏還小。沒有單獨量出來，不下結論。
- **存檔（JSON）**：這張沒有城市、沒有旅客、沒有歷史的地圖，每 1,000 列車約 1.2–1.3 MB；編碼 88–109 ms、解碼 420–560 ms（Linux 的 Foundation；Apple 平台的 JSON 實作不同，要補量）。真實存檔大得多：`SaveFixtures/v84-festivals.json` 一個小遊戲就 0.69 MB。
- **意思**：把 1,000 列車的世界送出去再收回來，光編碼加解碼就約 0.5–0.7 秒，是 5 到 7 個 tick，還沒算網路。這是第 3 節「每 tick 上雲端不可行」的實測根據。

### 2.5 五種做法各能拿到多少（交辦第 5 項）

| 做法 | 現況 | 這次量到的上限 | 判斷 |
| --- | --- | --- | --- |
| **事件驅動** | 已經做了一半：沒事的秒與分鐘會跳過（1.3）。沒做的一半是「等路的列車登記在它等的軌道上，放出來才重問」；現在每一圈全部重問（1.7 的 C、決策 597 的 43%） | 這張地圖量不到（沒有人在等路）。真實存檔上，等路相關的函式佔 74%（決策 597） | 收益大，但會改 `advance` 裡的順序，重播的校驗和可能動；決策 597 已經因為太大而擱下。排在查表與索引之後（3.1 的 L3） |
| **遠方列車簡化** | 畫面層已經有（遠景模型、不畫的不算）；模擬沒有 | 關掉行車控制當作「全部簡化」的上限：100 列車 618 → 4.9 ms（126 倍） | **不建議放進 GameCore**：「遠」是相對鏡頭的，鏡頭不是指令，結果就會跟著玩家看哪裡而變，違反決定性（決策 13）與重播；而且交會、待避不算就是另一套調度規則。同樣的倍數可以靠「互不相干的不要一起重算」拿到（下一列），不必改規則 |
| **區域分層** | 沒有。交會計畫的鍵、`TrackHolders` 都是全世界一份 | (c)：100 列車 618 → 6.1 ms（100 倍）；1,000 列車 68 ms；成長變直線 | **最值得做的方向**，但單位不是地理區域，是「彼此會搶同一段軌道或同一個站的服務」的連通塊：計畫的鍵與重算以連通塊為單位（3.1 的 L2）。真實路網連在一起，連通塊比這張地圖大，收益會比 100 倍小，要用真實存檔量 |
| **批次更新** | 已經有：一圈走 1–60 秒、整分鐘跳過、6000× 的 tick（600 秒）只比 600× 的（60 秒）貴 6.5 倍而不是 10 倍 | — | 再做的空間小。把列車改成「結構的陣列」之類的批次寫法，取樣裡看不到 `moveTrains` 是熱點，沒有證據支持 |
| **空間索引** | 模擬的規則不問「附近有誰」，問的是「這段軌道誰佔著」「這列車屬於哪條線」 | 查表類（A、B）就是 2 次方到 3 次方的來源 | 要的是 **ID → 位置的索引**與**軌道 → 佔用者的增量索引**（L0、L1），不是四叉樹。真正的空間索引只有一個地方有用：蓋軌道時的 `firstConflict`／`addFouling`（2.3，5,000 列車的地圖建 209 秒）。那是指令側，影響的是匯入真實路線與讀大地圖 |

### 2.6 這些數字不能代表什麼、要補量什麼

- **不代表 iPhone／iPad**。x86-64 伺服器核心和 A 系列的效能核心、節能核心、過熱降頻都不同；決策 460 的休息比例（share）也不在這個基準裡。
- 要在 **Mac（Xcode，Release）** 補量：同一個 `TICK_SCALE_REPORT`（`swift test` 在 macOS 可以直接跑）；Apple 的 `JSONEncoder`／`JSONDecoder`；`-c release` 與這裡的 debug `-O` 差多少。
- 要在**實機**補量（作者或 TestFlight 的問題回報重播）：真實存檔在 600× 的每 tick 時間與跟不上倍速提示（決策 464）出現的頻率；過熱後的數字；記憶體。
- 這張地圖沒有旅客。旅客側最重的是每天 06:00 的計畫（81 站約 14 秒，1.9），它隨**車站數**長，不隨列車數長，要另外用 `DEVICE_LOAD_REPORT`／PLANDAY 的做法量。
- 一列車一條線是極端。真實存檔每條線 5–10 列車，路線數小得多，所以 (a) 的 3 次方在真實存檔上會晚一點出現；但作者的存檔在 74–145 列車已經超過預算（1.9），方向一致。

---

## 3. 本地優化與雲端化的收益比較

### 3.1 本地能做的，分五級

每一級都是「最小可行實驗」：只描述、沒有實作。共同的驗收：`GoldenScenarios`、`SaveFixtures`、`ReplayFixtures` 一個位元都不動而且全過（結果必須逐位元相同，不是「差不多」），`swift-shards.sh` 全部 shard 綠；量測用 `TICK_SCALE_REPORT` 與作者存檔的重播（PERF_REAL_MAP 的做法）前後對照。共同的退路：每一級是獨立的 PR，沒有達到預期就不合併，不留一半。

| 級 | 改哪裡 | 預期收益（估算，除非註明） | 怎麼量 | 風險與退路 |
| --- | --- | --- | --- | --- |
| **L0 查表不要線性** | ① `planTrafficOvertakes`（`ScheduledTraffic.swift:618–628`）：`hasRoutePreferences` 每個服務先算一次，不要每一對算兩次。② 「列車 → 路線」做成一次建好的對照（放在已有的 `RouteMemo`／`DispatchMemo` 這類不進存檔的暫存裡），取代 `assignedLine(of:)` 的掃描與 `lines.first(where: { assignedLine… })`（1.7 的 A2、A3）。③ `closingStart`（A1）、`runningTrains`（A5）、`serviceLevel`（A7）同樣處理 | (a) 的 3 次方降到 2 次方：100 列車時取樣有 80% 在這條路上，所以 618 ms 可望降到 150 ms 以下；(b) 的 2 次方裡 `closingStart`、`runningTrains` 的部分消失 | `TICK_SCALE_REPORT=25,50,100,200` 前後；gdb 取樣裡 `hasRoutePreferences` 消失 | 最低：純粹少算，不改順序、不改資料。暫存要跟著 `lines` 的變動失效，漏了會用到舊的對照；用「鍵 = 路線陣列」或每次 `advance` 開頭建一次來擋 |
| **L1 佔用索引不要每圈重建** | `trackHolders(memo:)`（`RouteReservation.swift:977–1001`）的鍵從「整個列車陣列相等」改成跟著預約的變動增量更新；`extendAuthorities`（`GameWorld.swift:5593–5625`）延長一列車後只更新那一列的佔用，不要 `holders = nil` | (b) 剩下的 2 次方再降；跟車多的地圖（每條線很多列車）收益最大 | 同上，加一組「一條線很多列車」的地圖（基準要加一種 layout） | 中：索引和列車的預約兩份要一致。先加一個只在測試裡開的檢查「增量的結果 == 重建的結果」，跑完整個重播與 PROPERTY_REPLAY 再拿掉 |
| **L2 交會計畫以連通塊為單位** | `trafficPlanKey`（`ScheduledTraffic.swift:248–253`）與 `trafficPlan(parts:…)`：把服務分成「共用車站或軌道」的連通塊，各自一把鍵、各自重算（零件跨 `advance` 借用的機制已經有，APP_TICK_COST 第 6 節） | 上限是 (c)：直線成長。真實路網連通塊大，實際倍數要量 | `TICK_SCALE_REPORT` 的 (a) 應該接近 (c)；作者存檔的重播 | 中高：`inferTrafficMeets`、待避是跨服務的，分塊錯了會少算一個交會。分塊必須是「不可能互相影響」的保守定義；驗收同樣是逐位元相同 |
| **L3 等路改成登記與叫醒** | `secondsUntilARouteFrees`（`GameWorld.swift:5703–5724`）、`freePlatformOnTheWay`：等路的發車登記在它等的軌道上，那段放出來才重問，不再複製世界往前試 | 作者的存檔上相關函式佔 74%（決策 597）；估算可降一個數量級，APP_TICK_COST 第 6 節同樣的判斷 | 作者存檔的重播、高鐵示範開閉塞跑一天（現在 348 秒） | **高**：會改到 `advance` 裡事件的先後，重播校驗和與 golden 可能動；決策 597 已經擱下一次。要先有「新舊兩條路並跑、逐 tick 比狀態」的測試工具，而且要一個新的決策號 |
| **L4 多核心** | GameCore 不能有執行緒（1.6）。能做的是決策 470 的形狀：在 GamePresentation 把**純函數**的零件（各連通塊的交會計畫、各站的旅客路徑）先在其他核心算好，交給 `advance` 當提示，`advance` 驗過鍵才用 | 最多核心數的倍數，而且只對可以先算的部分 | 同上，加實機 | 中：L2 做完才有東西可以分。節能核心與過熱時可能反而慢（決策 460） |

蓋軌道的 `firstConflict`／`addFouling`（2.3）是另一條線（指令側），和 PERF_REAL_MAP 的 E 類一起看：給軌道段的外框做一個格子索引，建地圖從平方變直線。它不影響每 tick，但決定「一張一萬輛列車的地圖讀不讀得進來、蓋不蓋得出來」。

### 3.2 雲端要付的成本

雲端不是免費的加速。要把一段計算搬出去，至少要付：

| 成本 | 數字 | 來源 |
| --- | --- | --- |
| 把世界編成資料 | 每 1,000 列車約 0.1 秒、1.2 MB（沒有城市與旅客的地圖；真實存檔更大） | VERIFIED，2.2 (c) |
| 伺服器解碼 | 每 1,000 列車約 0.4–0.6 秒 | VERIFIED，同上 |
| 上傳 | 1.2 MB 在行動網路上行 5 Mbps 約 2 秒；壓縮後可能是幾分之一 | **估算**（假設上行 5 Mbps；JSON 壓縮率沒有量） |
| 來回延遲 | 臺灣到最近的 Railway 區域（新加坡）約 50–100 ms，行動網路更高、會抖動 | **估算**（沒有量；附錄 B 只確認了區域） |
| 冷啟動 | 縮到零的服務第一個請求要等容器醒，可能回 502 | Railway 文件（附錄 B） |
| 伺服器算得比手機快嗎 | 不一定。GameCore 是單執行緒，雲端的共享 vCPU 單核通常**不比** A 系列效能核心快；這次的 x86 數字和手機沒有換算過 | 沒有量，2.6 |
| 結果送回來 | 如果結果是整個世界，再付一次解碼（手機上） | VERIFIED 的同一個數字 |

一個 tick 的預算是 100 ms。光是編碼加解碼就超過，所以**凡是每 tick 都要的計算，上雲端一定比本地慢**。雲端只可能幫到「要算好幾秒、晚幾秒拿到也沒關係、而且本地也能自己算」的工作。

### 3.3 比較

| | 本地優化（L0–L2） | 把 tick 搬上雲端 | 可選的雲端工作（第 4 節 B 類） |
| --- | --- | --- | --- |
| 能撐多大 | 量到的上限：(c) 的直線，1,000 列車 68 ms／tick（合成地圖，單執行緒） | 受限於伺服器單核，和本地同一個演算法就是同一個 3 次方 | 不改變能撐多大：tick 還是在手機上 |
| 手機 CPU | 直接降 | 降到只剩畫面；但要一直收狀態 | 只省下那幾件重工作（例如每天的旅客計畫） |
| 離線 | 不受影響 | **不能玩**，或者手機還是得有能力自己跑，那就沒有省到上限 | 不受影響：沒有網路就本地算 |
| 決定性、存檔、重播 | 不變（驗收就是逐位元相同） | 每一項都要重做 | 不變，前提是結果在 tick 邊界套用而且和本地算的一樣 |
| 花費 | 開發時間 | 每個同時在線的玩家至少一個 vCPU（6.3 的估算） | 很小（6.3） |
| 要先做什麼 | 現在就能做 | — | 先做完本地優化，不然搬出去的是沒修的 3 次方 |

**結論：先做本地。** 現在的瓶頸是演算法的形狀（平方、立方），不是機器不夠快；換一台機器跑同一個立方，只是把牆往後推一點。「保留完整離線遊玩」這個條件已經決定了：存檔有多大，手機就得自己跑得動多大，雲端不能提高這個上限。

---

## 4. 建議的模擬分層架構

### 4.1 三層

```
GamePresentation（主執行緒）  畫面、鏡頭、動畫、列車在兩個 tick 之間的滑動、指令的入口
        │  指令（PlayerCommand）            ▲  整個 GameWorld 的值（tick 邊界換上）
        ▼                                  │
GameCore：GameWorld.advance（一條背景執行緒，決定性，唯一的權威）
        │  快照（Sendable 的值）＋鍵         ▲  結果＋同一把鍵（驗過才用）
        ▼                                  │
純函數的工作（其他核心；將來也可以是雲端）   旅客計畫、交會計畫的零件、站長建議、試算
```

和現在的差別只有最下面一層有了名字。它現在已經存在兩個例子：旅客路徑在所有核心上先算（`Sources/GamePresentation/PassengerRoutesAhead.swift:13`，決策 470），站長建議與交通讀數在背景算（決策 465、497）。決策 7、8 早就寫了這個方向：GameCore 不用 actor，將來的背景工作是「`Sendable` 的快照出去、結果當指令回來」（`docs/ARCHITECTURE.md` 決策 7、8）。

規則只有三條：
1. **權威只有一份**，在手機上的 `GameWorld`（決策 4）。下面那層的任何結果都只是「提示」：`advance` 用鍵確認它對應現在的世界才用，不對就自己算。`passengerPlan` 已經是這樣（`Passenger/PassengerRouteCache.swift:40`：鍵或日子不符就重算）。
2. **結果必須和本地自己算的一模一樣**（同一份 GameCore 原始碼、整數運算）。這樣在哪裡算、有沒有算完都不改變遊戲的結果，重播與存檔不受影響。
3. **只在 tick 邊界套用**。現在 `finish` 換上世界、`worldRevision` 不符就丟掉（1.6），就是這個邊界。

### 4.2 交辦第 6 項：三類

**A. 必須在本地**

| 什麼 | 為什麼（程式證據） |
| --- | --- |
| 每一圈的列車移動、進路預約、閉塞、交會待避、停站發車 | 每 tick（100 ms）都要，而且下一圈要用這一圈的結果（`GameWorld.swift:3488–3699` 是一個連續的迴圈）；來回一次就超過預算（3.2） |
| 派車、車輛接班、死結處理 | 每遊戲分鐘，在同一個迴圈裡（3496–3541、3564），讀寫的是同一批列車 |
| 玩家的指令 | 失敗原子性（決策 4）：指令要立刻成功或失敗、畫面立刻反應；`worldRevision` 的機制假設指令在本機立刻套用（`GameSession.swift:2559`） |
| 旅客釋出、上下車、結帳、城市成長 | 在 `advance` 的整分、整點、午夜（1.3），本身不重（1.3 末段） |
| 存檔與讀檔 | 離線要能存；存檔的資料夾在裝置上，iCloud 只是第二份（`Sources/GamePresentation/SaveSync.swift:4–11`，決策 397） |
| 畫面、列車滑動、3D | 每幀 |

**B. 可以當成「可選的雲端優化」**（本地一定也能算；雲端只是先算好）

| 什麼 | 為什麼可以（程式證據） | 現況 |
| --- | --- | --- |
| 每天的旅客計畫（全網路徑） | 是快照的純函數，有鍵（`passengerPlanKey`，`Passenger/PassengerDemand.swift:713`），一天只算一次，81 站約 14 秒（1.9） | 已經在本機其他核心先算（決策 470）。這是唯一一件「算很久、晚到沒關係」而且已經有鍵的工作 |
| 站長建議、真實路線的提案卡、政策試玩、跳過夜晚的試跑 | 都在世界的副本上算、不改世界（`Policy.swift:497–518`、`NightSkip.swift:66–82`） | 本機背景 |
| 長時間快轉的「先跑看看」（例如試算一個月） | `HeadlessGame`（`Sources/GamePresentation/HeadlessGame.swift:174–246`）與 `Sources/GameSim` 已經能在 Linux 上無畫面跑同一份 GameCore | 開發用 |
| 問題回報的重播、每週挑戰成績的驗證 | 開局存檔＋指令流＋校驗和已經有（決策 193、`ReplayFixtures/README.md`）；伺服器重播一次就能驗 | 現在在開發者的機器上重播 |

**C. 不適合雲端**

| 什麼 | 為什麼 |
| --- | --- |
| 整個 tick | 3.2、3.3：比本地慢、不能離線、每位玩家要一個核心 |
| 「遠方列車交給伺服器」 | 遠近相對鏡頭，不是世界的狀態（2.5）；而且兩邊的列車會搶同一段軌道，切不開 |
| 即時資料（真實誤點、即時到站）進模擬 | NEXT_PRIORITIES 第 7 節已經寫了：會破壞決定性 |
| 多人連線的權威伺服器 | 決策 193：連線不是優先。要做的話三樣零件（存檔、指令流、校驗）已經有離線版（附錄 A.2），但 `PlayerCommand` 在 GamePresentation、執行期的校驗和只在測試裡，都要先搬，是另一個題目 |

---

## 5. 離線及同步設計

這一節是**設計，沒有實作**；是「如果哪天要做 B 類」的最小形狀。它不需要任何新的存檔格式。

### 5.1 原則

- 離線是預設。沒有網路、伺服器睡著、回錯、回晚了，遊戲的結果都**完全一樣**，只是那件工作由手機自己算（和今天一樣）。
- 伺服器不存玩家的世界，不是存檔的任何一份。工作做完就丟。
- 伺服器跑的是同一份 GameCore（Linux 上已經每天在 CI 跑），所以結果逐位元相同；不同就是 bug，要當成重播不一致來查（`diagnosing-bugs`）。

### 5.2 帶版本的快照

工作的輸入 = 現有的存檔格式再加一個信封：

| 欄位 | 內容 | 現有的對應 |
| --- | --- | --- |
| `saveVersion` | 現在是 90 | `SavedGame.currentVersion`（`Sources/GameCore/World/SavedGame.swift:481`） |
| `build` | App 的版本與建置號：伺服器必須是**同一個** GameCore，不是「相容的」 | 信封裡新增的欄位 |
| `world` | `SavedGame(world:)` 的 JSON | 同存檔 |
| `stateChecksum` | 世界的校驗和 | **目前只有測試裡有**（`Tests/GameCoreTests/ReplayState.swift:17`）。要在執行期用，得把它搬進 `Sources/`：這需要一個決策（規劃決定） |
| `job` | 種類與參數，例如「旅客計畫，鍵 = …，日子 = …」 | `PassengerPlanKey` |

版本不符（伺服器還沒更新到玩家的 build，或反過來）：伺服器直接拒絕，手機本地算。不做跨版本的相容。

### 5.3 工作佇列

- 工作的身分 = （`stateChecksum`，種類，參數）。同一個身分重送是同一件事（冪等），所以重試、重複送、兩台裝置都送，都不會錯。
- 手機這邊一個很小的佇列：最多一件在外面；送出去的同時**本地照常開始算**（今天的 `PassengerRoutesAhead`）。誰先回來用誰的，另一個取消。所以雲端永遠不會讓遊戲比今天慢。
- 伺服器：收快照 → 解碼 → 跑 GameCore 的那個函式 → 回結果與同一個身分 → 丟掉快照。沒有資料庫、沒有帳號狀態。

### 5.4 結果驗證

1. **鍵要對**：結果帶的鍵必須等於世界現在的鍵（`passengerPlan.key != passengerPlanKey()` 就不用，`PassengerRouteCache.swift:40`）。玩家在等待時改了路網，鍵就變了，結果自然作廢。這和 `worldRevision` 丟掉過期 tick 是同一個機制（`GameSession.swift:2559`）。
2. **形狀要對**：結果經 `Codable` 的驗證解碼（GameCore 的型別在解碼時檢查不變量）。
3. **抽查**：隔一段時間，本地把同一件工作也算完，和雲端的結果比；不同就停用雲端、記進問題回報。因為結果應該逐位元相同，一次不同就足以判定有 bug 或有人動手腳。
4. 結果只能是 B 類的「提示」，不能是指令，不能直接寫世界。

### 5.5 在 tick 邊界套用

結果回來時先放著，等 `finish` 換上新世界之後、下一個 tick 交出去之前（`beginLoopTick`，`GameSession.swift:2391–2405`）才交給下一個 `advance`。OpenTTD 的貨物分配是同一個做法：在另一條執行緒算，在固定的遊戲時間接回（附錄 A.2）。差別是 OpenTTD 沒算完就讓遊戲等，這裡沒回來就本地算，因為這裡的結果在哪裡算都一樣。

### 5.6 斷線恢復

| 情況 | 處理 |
| --- | --- |
| 送出後斷線 | 本地那一份照常算完；回不來的結果沒有人等 |
| 結果回來時世界已經變了 | 鍵不符，丟掉 |
| App 被系統關掉 | 佇列不存檔。重開後從存檔讀回，需要的工作照鍵重新產生 |
| 伺服器回錯、回 502（冷啟動） | 當成沒回；一段時間內不再送（退避） |
| 伺服器版本落後 | 5.2：拒絕，本地算 |

### 5.7 離線存檔

不變。存檔在裝置上，自動存每 900 秒（1.6），iCloud 是玩家自己的第二份（決策 397）。雲端工作不產生、不持有任何存檔；所以也不會有「雲端和本地哪一份才對」的衝突。

### 5.8 隱私與審查

快照是整個世界（玩家取的站名、公司名都在裡面）。送出去之前要：玩家明確同意、隱私說明更新、傳輸加密、伺服器不落地、不記錄內容。`docs/HANDOFF.md` 規定碰到存檔、帳號、隱私、伺服器的 PR 要有獨立審查；App Store 的隱私標示是作者的帳號步驟。這些成本比伺服器的月費大，是「暫緩」的主要理由之一。

---

## 6. 分階段計畫、風險與驗收

### 6.1 留在 Swift、改用 Rust／C++、另開雲端服務（交辦第 8 項）

| | 留在 Swift（建議） | 核心改寫成 Rust 或 C++ | 獨立的雲端計算服務 |
| --- | --- | --- | --- |
| 解決的問題 | 演算法的形狀（L0–L3），這是量到的瓶頸 | 常數倍：少一些 retain／release（取樣裡看得到 `ServiceLine` 複製的 retain／release）、可以手動排記憶體 | 把 B 類工作移出手機 |
| 解決不了的 | 語言本身的常數 | **3 次方還是 3 次方**：同樣的寫法換語言不會變 | 每 tick 的成本（3.2） |
| 成本 | 每一級一個 PR | GameCore 52,099 行、GameCoreTests 76,786 行（`wc -l`，這次數的）、79 個 golden、每一版的存檔與重播 fixture 都要逐位元相同（包含自製的 128 位元整數與每一個捨入）；改寫期間兩份核心並存 | 伺服器、部署、監控、版本同步、隱私審查（5.8）、月費（6.3） |
| 風險 | 低到高（3.1 各級） | 很高：玩家的舊存檔讀不回來的風險；Linux 測試、Android 的實測（ANDROID_PORT_STUDY）都要重來 | 中：多一個會壞的東西；但照第 5 節設計，壞了只是回到今天 |
| Android | 已實測可用：Swift 官方 Android SDK，三套 fixture 在 ARM64 上全過（`docs/research/ANDROID_PORT_STUDY_2026-11.md` 第 11、15 行） | 可以，但那份研究已經否決重寫 | 無關 |
| 沒有的資料 | — | 沒有找到附人月的可信改寫紀錄（附錄 A.2），所以這裡**不給人月的數字** | — |

**建議：留在 Swift。** 和 ANDROID_PORT_STUDY 的結論一致。如果 L0–L3 做完、在實機上量到剩下的是語言常數，再回來看，而且先看的是 Swift 自己的寫法（少複製結構、用索引不用值），不是換語言。

### 6.2 Railway 當雲端 Worker 可不可行（交辦第 9 項）

技術上可行，**現在不值得**：
- 可行：GameCore 沒有任何 `import`，同一份原始碼今天就在 Linux 容器裡跑；Swift 有官方的 Linux 映像與靜態連結（附錄 B）。Railway 可以跑常駐或會睡的服務，有新加坡區域，WebSocket 與最長 15 分鐘的 HTTP 請求夠 B 類工作用。
- 限制：只有 amd64（未經官方文件確認）；縮到零的冷啟動；排程最短 5 分鐘；沒有 GPU（用不到）。
- 不值得的原因在 3.3 與 5.8，不在平台。

沒有註冊、沒有建立任何資源、沒有用任何金鑰。價目是 2026-11-12 的公開頁面（附錄 B）。

### 6.3 花費估算

**全部是估算，不是實測。** 單價：每 vCPU 每月 $20（每 vCPU·小時約 $0.028）、每 GB 記憶體每月 $10（每 GB·小時約 $0.014）、對外流量每 GB $0.05、Pro 方案每月 $20 含 $20 用量。

假設（每一條都可以換）：
- 每位每日活躍玩家每天玩 1 小時，一個月 30 小時。
- 情境一（B 類，只算旅客計畫）：600× 時一個遊戲日是現實 144 秒；大地圖一次計畫 14 秒 CPU（1.9 的 81 站，Linux）。所以玩的時候平均佔 14／144 ≈ 0.1 個 vCPU，記憶體算 0.5 GB。這是**大地圖、一直開 600×** 的上限；小地圖的計畫不到 1 秒，根本不必送。
- 情境二（整個 tick 上雲端，不建議，只為了對照）：每位在線玩家 1 個 vCPU、1 GB（1.9：作者的存檔一個 tick 165 ms，一個核心連一位玩家都跟不上 600×，所以這是低估）。
- 流量：情境一每個遊戲日回傳的計畫估 0.2 MB，每小時 25 個遊戲日 = 5 MB；情境二每秒 10 次、每次回傳 1,000 列車的位置估 16 KB，每小時約 0.6 GB。上傳不計費。
- 伺服器用量跟著在線人數伸縮、沒有閒置（實際上做不到，所以再乘 1.5 到 2 比較保險）。

| 每日活躍玩家 | 每月玩家·小時 | 情境一：B 類工作 | 情境二：整個 tick（對照） |
| ---: | ---: | ---: | ---: |
| 100 | 3,000 | CPU $8 + 記憶體 $21 + 流量 $1 ≈ **$30**（Pro 月費 $20 已含 $20 用量，帳單約 $30） | CPU $83 + 記憶體 $42 + 流量 $90 ≈ **$215** |
| 1,000 | 30,000 | ≈ **$300** | ≈ **$2,150** |
| 10,000 | 300,000 | ≈ **$3,000** | ≈ **$21,500** |

算式：情境一每玩家·小時 = 0.1 × $0.028 + 0.5 × $0.014 + 0.005 × $0.05 ≈ $0.010；情境二 = 1 × $0.028 + 1 × $0.014 + 0.6 × $0.05 ≈ $0.072。磁碟不用（不落地）。情境一的記憶體佔了七成：容器不能只開 0.1 個，所以實際取決於一個容器能同時服務幾位玩家的工作，這要實驗才知道。

對照：這個遊戲現在沒有任何伺服器成本。情境一換到的是「大地圖的玩家每個遊戲日少算 14 秒」，而同一件事本機已經放到其他核心上算了（決策 470），而且 PLANDAY 的本地優化還沒做完。

### 6.4 分階段

| 階段 | 做什麼 | 驗收 | 需要 |
| --- | --- | --- | --- |
| **0 量** | 合併這份研究與基準（平常不跑）。在 Mac 與實機補量 2.6 的項目 | 2.6 的表填上 Mac 與一台實機的數字 | 作者的 Mac 或 macOS runner；實機由作者 |
| **1 查表（L0）** | 3.1 的 L0，一個熱點一個 PR，先做 `planTrafficOvertakes` | 三套 fixture 不動且全過；`TICK_SCALE_REPORT` 100 列車的中位數降到 1／4 以下；作者存檔的重播不變慢 | 一個實作 session（GameCore 的 PR，佔一個完整的 CI 層級）。不需要決策號（不改行為）；規劃判斷要不要記一筆 |
| **2 索引（L1）與蓋軌道的格子索引** | 3.1 的 L1；`firstConflict`／`addFouling` | 同上；基準加「一條線很多列車」的地圖；5,000 列車的地圖建置從 209 秒降到 10 秒以下 | 同上 |
| **3 分塊（L2）** | 交會計畫以連通塊為單位 | `TICK_SCALE_REPORT` 的 (a) 落在 (c) 的 3 倍以內；作者的存檔 600× 的平均 tick 低於 100 ms（Linux release） | 一個決策號（計畫的鍵怎麼分是設計決定） |
| **4 等路的事件化（L3）** | 先做「新舊並跑、逐 tick 比狀態」的測試工具，再改 | 高鐵示範開閉塞一天從 348 秒降到 60 秒以下；重播 fixture 不動，或逐一說明為什麼動 | 決策號；決策 597 的擱置理由要先回答 |
| **5 多核心（L4）** | L2 的塊在其他核心先算 | 實機上 600× 的 tick 下降，過熱時不變慢 | 決策號；實機 |
| **6 雲端的最小實驗（只在 1–3 做完、而且旅客計畫仍是痛點時）** | **不建立雲端資源**：在本機（或 CI 的 Linux）用 `GameSim` 跑「存檔進、旅客計畫出」，量編碼、壓縮後大小、解碼、計算，各用一個真實的大存檔。有了這四個數字才知道 6.3 的假設對不對 | 一張表：來回的總時間對照本機其他核心算的時間。雲端沒有比較快就結案 | 不需要帳號。要建立任何付費資源之前，回到作者決定 |

### 6.5 風險

| 風險 | 怎麼擋 |
| --- | --- |
| 優化改了結果（少算一個交會、順序不同） | 驗收一律是逐位元相同：golden、存檔、重播、`PROPERTY_REPLAY`；增量索引先和重建的並跑比對 |
| 合成地圖的結論不適用真實存檔 | 每一級都同時用作者存檔的重播量；2.3 已經指出兩者熱點不同 |
| Linux 的數字不適用手機 | 階段 0；每一級的驗收都列實機 |
| 暫存用到過期的資料 | 鍵跟著輸入；讀檔、指令之後一律重建；暫存不進存檔 |
| 再踩一次決策 590（把世界搬到堆積） | 這份研究沒有提議任何改 `GameWorld` 記憶體配置的事 |
| 雲端帶來隱私與審查成本 | 5.8；排在最後而且先做不需要雲端的實驗 |
| 並行的 session 同時改 `advance` | 每一級在 #1579 登記；GameCore 的 PR 同時最多兩個（CLAUDE.md） |

### 6.6 值得先做、暫緩、不建議做

**值得先做**
1. **查表不要線性**（L0）：`planTrafficOvertakes` 裡的 `hasRoutePreferences`、「列車 → 路線」的對照、`closingStart`、`runningTrains`。量到的 3 次方的來源，改動最小，不改行為。
2. **佔用索引增量更新**（L1），連同蓋軌道時的格子索引。
3. **交會計畫以連通塊為單位**（L2）：量到的上限是直線成長。
4. 在 Mac 與實機補量（階段 0），並保留這個基準當之後每一級的尺。

**暫緩**
- 等路的事件化（L3）：收益大，風險也最大；等 1–3 做完、有並跑比對的工具再做。
- 多核心（L4）：等 L2。
- 可選的雲端工作（旅客計畫、試算）：等本地做完；先做 6.4 階段 6 那個不花錢的實驗。
- 把狀態校驗和搬進 `Sources/`、把 `PlayerCommand` 搬進 GameCore：只有要做雲端驗證或連線時才需要。
- 二進位的存檔格式：JSON 的編解碼只在存檔與（將來的）快照時付一次，不在 tick 裡。

**不建議做**
- 把整個 tick 搬上雲端（3.2、3.3、6.3）。
- 在 GameCore 裡依鏡頭距離簡化遠方列車（2.5）。
- 把核心改寫成 Rust 或 C++（6.1）。
- 現在就開伺服器做多人連線（決策 193）。
- 重做「世界放到堆積」（決策 590）。
- 把即時資料接進模擬（NEXT_PRIORITIES 第 7 節）。
- 在沒有先修演算法之前買更大的機器：同一個 3 次方，機器快 10 倍只多撐 2 倍多的列車。

### 6.7 五個角度（為什麼是這個順序）

- 玩家：先做本地，離線的人也變快；雲端只幫到有網路、大地圖的人。
- 鐵道迷：交會、待避、閉塞的規則一條都不改；不做「遠方列車簡化」正是為了不讓看不到的地方跑另一套規則。
- 開發者：L0–L2 都能用現有的 fixture 證明沒改結果；雲端要多維護一個服務與版本同步。
- 美術：無。
- 音樂：無。

### 6.8 和現有規則對過的地方（交辦第 10 項）

| 規則 | 這份研究怎麼遵守 |
| --- | --- |
| GameCore 不 import、平台無關（CLAUDE.md、決策 13） | 沒有提議在 GameCore 加執行緒或 Foundation；L4 與雲端都在 GamePresentation 那一側 |
| `GameWorld` 是唯一權威（決策 4） | 第 4 節規則 1 |
| 決定性、批次等於逐步（決策 13、15） | 每一級的驗收是逐位元相同 |
| golden、存檔、重播 fixture 不可為了過測試而改 | 沒有動；提議的驗收以它們不動為準 |
| Swift 6.4、不加依賴 | 基準只用 XCTest 與 Foundation；沒有新依賴 |
| 新決策是 `docs/decisions/<N>.md`，號碼在 #1579 登記 | 這次沒有取號；6.4 標出哪幾級需要 |
| 不建立付費資源、不合併、不發版 | 沒有做 |
| 碰存檔、隱私、伺服器要獨立審查（HANDOFF） | 5.8 |

---

## 附錄 A：前人怎麼做（只讀做法，沒有搬程式）

照 CLAUDE.md「先找前人做法」。網頁都是 2026-11-12 讀的；沒能從原始頁面確認的寫「未確認」。

### A.1 作者的參考庫（`a91453/railway-reference-private`，HEAD `fa053380`）

| 來源 | 有什麼 | 能用的做法 |
| --- | --- | --- |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`（地鐵、高鐵、航空的網頁遊戲，程式壓成一個檔） | `loop(e)`：`requestAnimationFrame` 變動步長，地鐵把一步夾在 1/30 秒、多的時間丟掉（`_metroDroppedLagSec`）；每幀動列車，**換分鐘**才檢查班次與 `spawnTrains`，**換小時**才 `updateLineFlow`、結帳，**換日**才日結。高鐵一幀的工作超過 8 ms 就把下一步延後。客流分配照幀時間給每幀 400–900 列的額度（`_metroFlowDispatchSliceBudget`） | 和本專案現在的分鐘／整點／午夜節拍相同；「一幀只做一份額度」的切片本專案用不到（tick 已在背景）。 |
| 同上，共用軌道 | `metroSharedTrackBeginHeadwayFrame`／`…RememberMove`／`…HeadwayClearance`：每幀一本帳，記每列車佔的距離區間與到期時間，後車只能走到淨空為止 | 比本專案的進路預約粗得多（沒有道岔、交會），不能取代；但「佔用記成區間、後車只問前面那一筆」正是第 3.1 節 L1 要的形狀 |
| 同上，列車的格子 | `hsrRuntimeIndexTrain`：`"floor(lng),floor(lat)"` 的 1° 格子，只給畫面裁切用 | 是顯示用的索引，不是模擬用的 |
| 同上，伺服器 | 客流路徑在伺服器算，客戶端讀 `X-Flow-Path-Cache` 標頭；每 900 秒雲端自動存檔；FNV-1a 驗存檔 | 伺服器的程式沒有在快照裡。「路徑在伺服器算、客戶端當快取」和第 4 節的「可選雲端」同一類 |
| `Railway/railway_game_reference_clean/docs/`（`desync.md`、`debugging_desyncs.md`、`linkgraph.md`、`logging_and_performance_metrics.md`） | 這是 OpenTTD 的文件（名稱換過；`binary_reference/` 的 wasm 是 OpenTTD 15.3）。內容見 A.2 | 只有文件與編譯好的 wasm，沒有原始碼；OpenTTD 是 GPL-2.0，照 CLAUDE.md 只讀做法。本專案的 `ReplayFixtures` 已經是照這兩份 desync 文件做的（ARCHITECTURE 6683 行） |
| `Simulator/reference_snapshot/` | 模型鐵道的軌道配置工具，列車只照道岔方向走 | 和規模無關 |
| `OpenWorld/reference_snapshot/play/src/engine/world-stream.js` | `WorldStream`：玩家周圍半徑 2 的區塊才啟用 | 是畫面的串流，不是模擬的分層 |

沒有找到的：依距離簡化遠處車輛的模擬、四叉樹或 kd 樹、lockstep 連線的程式。

授權的觀察（留給作者判斷，這次沒有搬任何程式所以不影響）：`Ci/` 與 `Simulator/` 的快照裡沒有授權檔，`Ci/reference_snapshot/terms/index.html` 那一頁寫著禁止重製與還原工程；`Simulator/` 下沒有 CLAUDE.md 提到的 `REFERENCE_REFRESH_2026-10-07.md` 與 `SANITIZATION_REPORT.md`。

### A.2 外部專案

| 專案（授權） | 做法 | 出處 |
| --- | --- | --- |
| **OpenTTD**（GPL-2.0，只讀做法） | 一個 tick 27 ms、一天 74 tick；重的工作各有自己的週期（車站評價 185 tick、城鎮成長 70、工業 256），地形每 256 tick 輪完一遍，每 tick 只做 1/256 | `src/gfx_type.h`、`src/timer/timer_game_tick.h`、`src/landscape.cpp`（github.com/OpenTTD/OpenTTD） |
| | YAPF 把每一段連續軌道的成本記住，只有號誌前瞻範圍內重算（為了連線時不 desync） | `src/pathfinder/yapf/yapf_costrail.hpp` |
| | **貨物分配（link graph）在另一條執行緒算，在固定的遊戲時間接回**（每天第 21 tick 開與接；沒算完遊戲就等）：非同步但結果仍是決定性的 | `docs/linkgraph.md`、`src/linkgraph/linkgraphschedule.h` |
| | 連線：加入時下載伺服器當下的存檔，之後只收指令；指令由伺服器排進某個網路幀，所有人同一幀同一順序執行；定期送亂數狀態當校驗，不符就斷線；`-d desync=2/3` 記指令與定期存檔供重播 | `docs/desync.md`、`docs/multiplayer.md` |
| **Simutrans**（Artistic License） | 分 `sync_step`（列車移動，每步）與 `step`（找路、工廠生產，較慢）；連線時把存檔串流進雜湊當校驗 | `src/simutrans/world/simworld.h`（github.com/simutrans/simutrans） |
| **A/B Street**（Apache-2.0） | **離散事件模擬**：一個全域的事件優先佇列，「不是每一步掃每個代理人」；車輛狀態是 Crossing（排在最快到達的時間）、Queued 等；每條車道一個佇列，確切位置只在要畫時才算。先前「每 0.1 秒更新每個代理人」的設計因為白做工而放棄；塞車時的重試（每 0.1 秒）仍是熱點 | a-b-street.github.io/docs/tech/trafficsim/discrete_event/ |
| **Factorio**（專有，只有部落格） | 決定性 lockstep、只送輸入（FFF-188）；加入時下載地圖再快轉追上（FFF-149）；每 tick 的 CRC 抓 desync（FFF-55，未確認，來自搜尋摘要）；輸送帶合成一段、記物品間的空隙，更新變 O(1)（FFF-176）；閒置的物件睡眠、機器人最多隔 20–60 tick 才更新（FFF-421） | factorio.com/blog/post/fff-188、149、176、421 |
| Glenn Fiedler | lockstep 的頻寬只和輸入有關、要求逐位元相同；浮點數跨編譯器與架構不保證相同 | gafferongames.com/post/deterministic_lockstep/、floating_point_determinism/ |

Transport Fever 2、Cities: Skylines、NIMBY Rails、Mini Metro：沒有找到公開的技術說明，略過。從 Swift 或 C# 把模擬核心改寫成 Rust／C++ 的事後檢討：沒有找到附人月成本的可信文章。

和本專案對照：
- 本專案的 `advance` 已經有 OpenTTD 的「重的工作各有週期」與一半的 A/B Street（沒事的秒數跳過）；缺的是 A/B Street 的另一半：**等路的列車登記在它等的資源上，資源放出來才叫醒**（現在是每一圈全部重問）。
- OpenTTD 的 link graph 是「可選雲端」最好的範本：重的、純函數的工作在別處算，**在固定的遊戲時間接回**，結果不因為在哪裡算而不同。
- 連線同步要的三樣（開局存檔、指令流、定期校驗）本專案已經有離線版：`SavedGame`、指令紀錄（`CommandLog`）、`ReplayFixtures` 的校驗和。

## 附錄 B：Railway 平台的公開價目（2026-11-12 讀的，沒有註冊、沒有建立資源）

出處：railway.com/pricing、docs.railway.com/reference/pricing/plans、/reference/app-sleeping、/reference/cron-jobs、/networking/public-networking/specs-and-limits、/reference/regions。

| 方案 | 月費 | 含的用量 | 每個服務上限（含副本） |
| --- | --- | --- | --- |
| Free | $0 | $1／月 | 1 vCPU、0.5 GB、磁碟 0.5 GB |
| Hobby | $5 | $5 | 48 vCPU、48 GB、磁碟 5 GB、6 個副本 |
| Pro | $20／工作區 | $20 | 1,000 vCPU、1 TB、磁碟 1 TB、42 個副本 |

單價：CPU 每 vCPU 每月 $20（每分鐘 $0.000463）；記憶體每 GB 每月 $10（每分鐘 $0.000231）；對外流量每 GB $0.05；磁碟每 GB 每月 $0.15。

行為：
- 可以縮到零（Serverless）：約 5–10 分鐘沒有對外封包就睡，第一個請求叫醒，會慢、可能回 502。
- HTTP 請求最長 15 分鐘、閒置 5 分鐘關；WebSocket 可以一直開；每個網域約 10,000 條連線。
- 排程最短 5 分鐘一次。
- 區域：美西、美東、阿姆斯特丹、**新加坡**（離臺灣最近的一個）。
- 只有 amd64（社群論壇的回覆，官方文件未確認）。
- 常駐的服務是預設的模型，背景 worker 沒有另外的限制（從文件推得）。

對照：Fly.io shared-cpu-1x 1 GB 每月 $6.70、亞太流量每 GB $0.04（docs.fly.io/about/pricing）；Cloudflare Workers 付費 $5／月含 3,000 萬 CPU 毫秒、之後每百萬 CPU 毫秒 $0.02，每次最多 5 分鐘 CPU、128 MB（developers.cloudflare.com/workers/platform/pricing、limits）：Swift 核心得編成 Wasm 才放得進去，128 MB 放不下大地圖；AWS Lambda x86 每 GB·秒 $0.0000166667（aws.amazon.com/lambda/pricing）。

Swift 在伺服器與其他平台（swift.org 文件，6.4.2）：官方 Docker 映像有 amd64 與 arm64、有 `-slim` 執行版；Static Linux SDK（musl）可以出完全靜態的執行檔；Android 與 Wasm 都有官方 SDK。GameCore 沒有任何 `import`，所以同一份原始碼今天就能在 Linux 容器裡跑（CI 與這次的量測就是）。

