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

<!-- 2–6 節在後續的 commit 補上 -->

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

