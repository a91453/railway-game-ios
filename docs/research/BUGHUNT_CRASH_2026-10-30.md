# 公測前抓蟲：當機（閃退）（派工單 BH8，2026-10-30）

派工：遊戲規劃第 32 任。session_01YGNNuocWPGBFMZqgdVi3pE，分支 `claude/bughunt-crash`，從 main `797687d`（#1522 之後）開始。

範圍：所有會讓 App 直接閃退的地方。卡住、凍結、很慢歸 BH9；在功能裡撞到的當機歸該功能的 BH（BH1–BH6）。

**結論：沒有找到 P1**，也就是沒有玩家做得到的操作會閃退。
- P2 一項，在 App 層，只讀程式。
- P3 五項，都要手改的指令或存檔才走得到。
- 這個 PR 沒有改遊戲程式。只加了：
  - 一個平常跳過的模糊測試：`Tests/GamePresentationTests/CrashFuzzTests.swift`，設 `CRASH_FUZZ` 才跑；
  - 這份文件。

## 1. 怎麼查的

**1. 靜態掃陷阱類別。**
- 用 grep 找這些寫法，再讀每一處與它的呼叫者，判斷玩家走不走得到：
  - `try!`、`as!`、`fatalError`、`precondition`、`preconditionFailure`；
  - 強制解包、`.first!`／`.min()!`、`removeFirst()`／`removeLast()`；
  - `Int(Double)`、整數 `/` 與 `%`、`a...b`、`stride`。
- 範圍：`Sources/GameCore`、`Sources/GamePresentation`、`RailwayGameApp`（不含 UITests）。
- App 層和 GamePresentation 各由一個子 agent 讀，我再抽查它們標出的地方。

**2. 存檔模糊測試（只在本機，腳本在 scratchpad，沒有進 repo）。**
- 對象：`SaveFixtures/` 的 79 個存檔（v1–v75），各隨機改 300 次，共 23,700 個。
- 改法有幾種，一次改 1 到 3 處：
  - 把數字換成 0、−1、±2³¹、2⁵³、2⁶²、`Int64.max`、`Int64.min`、1e300、0.5、×1000；
  - 把布林反過來；
  - 字串換成空字串、`\0` 或 5,000 字；
  - 陣列刪一個、重複一個、清空、交換、反轉。
- 每個改過的存檔包進 App 的存檔格式（`SaveFile`），用 `GameSim load <檔> then advance --hours 6 then dump` 讀進來再跑 6 個遊戲小時。
- 讀檔走的路和 App 一樣：`SaveLibrary.decode`。App 的「讀取」、「匯入」、別人分享的路網（`SharedNetwork`）都走 `SaveLibrary.decodeFile`。

**3. 玩家指令模糊測試（`CrashFuzzTests`，平常跳過）。**
- 準備：新遊戲種子 1，用 `third-town` 打法玩 2 天，有車站、路線與列車。
- 每個 case 從這個世界開始，送 300 個隨機的 `PlayerCommand.Edit`，涵蓋 52 種指令：
  - 買賣車、配車、編組、路線、停站模式、車站、轉乘、貨運場、道路、公車、建築、分區、買地圖、貸款等；
  - 參數混著用真的 ID 與不存在的 ID，數字用 0、負數、極大值；
  - 中間穿插讓時間跑 1 到 60,000 tick、復原與重做；
  - 最後存讀一次。
- 每個指令送出前先寫一行到 stderr，所以當掉時最後一行就是兇手。

**4. GameCore 的 property 與 differential campaign。** 21 個類別，`PROPERTY_STRESS=8`，即每個多 8 個種子。CI 的次數沒改。

**5. 時間跑很久。** `GameSim new-game --seed 3 then play --policy third-town --days 20 then advance --days 365`。

## 2. P1

沒有找到。

## 3. P2

**P2-1　車型目錄的列車小圖在寬度 0 時 `Int(NaN)` 閃退**（App 層，只讀程式，UNVERIFIED）
- **在哪裡**：`RailwayGameApp/Views/RollingStockCatalogView.swift:330–353`，`CatalogTrain`。
- **怎麼壞**：
  - `width = (proxy.size.width − 2·(count−1)) / count`，`height = min(proxy.size.height − 6, width·0.45)`，接著 `Int(width / (height * 0.7))`。
  - 只有 1 節車、GeometryReader 某一次排版給的寬度剛好是 0 時：`width = 0`、`height = 0`，0/0 = NaN，`Int(NaN)` 閃退。
  - 寬度剛好是 `2·(count−1)` 時，多節車也一樣。
  - 高度剛好 6 時會算出 ∞；但這一處有 `minHeight: 60`，走不到。
- **怎麼走到**：路線面板 → 配車 → 車型目錄（`LinesPanel.swift:2259`），把節數調到 1（`shownCars` 可以是 `Train.minimumCars`）。SwiftUI 在 sheet 剛出現、旋轉、版面還沒定的那一次排版有時會給寬度 0。要剛好這樣才會發生，所以列 P2。
- **重現**：Linux 跑不了 SwiftUI，沒有重現。
- **建議修法**（一行，不改畫面）：
  ```swift
  let windows = width > 0 && height > 0 ? max(1, Int(width / (height * 0.7))) : 1
  ```
- **為什麼這個 PR 沒修**：改 App 會觸發 `ios-build.yml`，而派工單說這段時間不用 macOS runner。這屬 BH4 的範圍（列車選型）；BH4 的 session 已經停止，訊息送不到。
- **五面向**：
  - 玩家：打開車型目錄時偶爾閃退，最傷信任；
  - 鐵道迷：無；
  - 開發：一行 guard，不影響其他畫面；
  - 美術：寬度為 0 時本來就看不到，不改外觀；
  - 音樂：無。

## 4. P3（理論上會，玩家走不到；記下來，建議修法）

以下都是指令模糊測試送出極端參數才當的。App 裡沒有從外面收指令的地方：
- 沒有連線多人；
- 指令紀錄（問題回報）只在 GameSim 與測試重播。

所以玩家的指令都來自畫面上的點擊、Stepper 與 Picker，給不出這些值。

**P3-1　放建築的位置在 ±2⁶³ 附近時溢位**
- **在哪裡**：`Sources/GameCore/City/PlacedBuilding.swift:378`，`GameWorld.lies(_:in:)`。這裡讀的 `minY = centre.y − 半邊長`，在中心點 y = `Int64.min` 時溢位。
- **重現**：
  ```swift
  var w = GameWorld.newGame(eventSeed: 1)
  _ = try? w.placeBuilding(.wharf, at: PlanPoint(x: 1000, y: .min))
  ```
- **玩家**：點地圖得到的點在地圖範圍附近，差得遠。
- **建議修法**：`placement` 一開始先 `guard bounds 擴大一個建築半邊長 contains(centre)`，再算四邊。動 GameCore，公測後。
- **五面向**：玩家無；鐵道迷無；開發：在一進門就拒絕，最便宜；美術無；音樂無。

**P3-2　鋪路的格子在 `Int.min`／`Int.max` 時溢位**
- **在哪裡**：`Sources/GameCore/City/RoadGrid.swift:366`，`roadQuote(along:)`。`abs($0.row − $1.row)` 在 row 是 `Int.min` 而下一格是正數時溢位。
- **重現**：
  ```swift
  buildRoad(along: [CellPosition(row: .min, column: .max), CellPosition(row: 2, column: 0)])
  ```
- **玩家**：格子由點擊換算，走不到。
- **建議修法**：把「每格都在地圖裡」的檢查（同一個 guard 的第三條）移到相鄰檢查之前。GameCore 一行換順序，公測後。
- **五面向**：玩家無；鐵道迷無；開發：換順序就好；美術無；音樂無。

**P3-3　「沒有停站模式 #N」的訊息在 N = `Int.max` 時溢位**
- **在哪裡**：`Sources/GamePresentation/DisplayText.swift:360`，`.unknownLinePattern(let index)` 的 `index + 1`。
- **重現**：
  ```swift
  assignTrain(train, line, pattern: Int.max)
  setLineTargets(line, …, pattern: Int.max)
  ```
  GameCore 正確拒絕，但組拒絕訊息時當掉。
- **玩家**：停站模式由 Picker 選，給的都是真的編號。
- **建議修法**：`index &+ 1`，或寫成 `index < Int.max ? index + 1 : index`。
- **五面向**：玩家無；鐵道迷無；開發：一個字；美術無；音樂無。

**P3-4　配車的班距極大時溢位**
- **在哪裡**：`Sources/GamePresentation/LineStaffing.swift:56`，`lineStaffingPlan`。`(roundTrip + headway − 1) / headway` 在 headway 接近 `Int64.max` 時溢位。
- **重現**：
  ```swift
  .staffLine(line, headway: Int64.max - 1, type: nil, cars: 5, language: .english)
  ```
- **玩家**：班距由 Picker 從 `GameWorld.staffingHeadways`（3–30 分）選，走不到。
- **建議修法**：guard 加上 `headway <= ServiceLine.maximumHeadwayMinutes`（或比照 `TargetHeadways` 的上限），或改成 `roundTrip / headway + (roundTrip % headway == 0 ? 0 : 1)`。
- **五面向**：玩家無；鐵道迷無；開發：一行；美術無；音樂無。

**P3-5　讀檔：軌道節點座標被手改得極大時，讀檔要好幾分鐘（不是閃退，已轉給 BH9）**
- **現象**：
  - 存檔模糊測試裡，有 22 個 case 在 300 秒內沒跑完：v3–v8 示範存檔 7 個、v70 1 個、v73 7 個、v75 7 個。
  - 共同點都是某個軌道節點的 x 或 y 被乘以 1000，約 3,000 萬到 5 億單位。
- **時間花在哪**：只讀檔就超過 2 分鐘。堆疊是 `RailwayNetwork.init(from:)`（`RailwayNetwork.swift:571`）→ `workOutFouling()`（`TrackFouling.swift:54`）→ `addFouling`：一條被拉得極長的邊，讓讀檔時算的 fouling 花了好幾分鐘。
- **玩家**：只有手改存檔才做得出來。正常建的軌道長度有上限。
- **建議**：已用 send_message 告訴 BH9，由 BH9 判斷優先度。
- **五面向**：玩家：別人傳來的壞檔會看起來卡在載入中；鐵道迷無；開發：讀檔時先檢查邊長上限再算 fouling；美術無；音樂無。

## 5. 查過、確定安全的類別（下次不用重查）

**存檔讀取**
- 23,700 個改過的存檔沒有一個閃退。3,366 個讀得進來並跑了 6 小時；其餘不合法的都被 `Codable` 驗證擋下，變成「存檔損壞」的訊息。
- GameCore 的解碼檢查很完整：
  - 餘額 ±2⁶²；
  - 累計值 2⁵⁰；
  - 地圖大小、格子在地圖內；
  - 建築的 `look` 在 `kind.looks` 內；
  - 時刻表與停站模式的索引；
  - 截斷的 JSON 先被 `SaveLibrary.header` 擋下。
- App 的讀取、匯入（`importSave` 另有 `SharedNetwork.maximumBytes` 上限）、別人分享的路網、自動存檔回退（`loadAutosave`，壞的跳下一個）都走同一個 `SaveLibrary.decodeFile`。

**GameCore**
- 沒有 `try!`、`as!`、`fatalError`。
- 38 個 `precondition` 與 8 個 `preconditionFailure` 有兩類：
  - 內部不變量，例如 `WideInteger`、`TrackGeometry.location(at:)`、`RailwayNetwork.removeEdge`；
  - 指令入口已先檢查過的值，例如 `Fares.demandFactor` 的 baseline 來自已驗證的票價規則，`GameEconomy.spend/earn` 的金額不為負。
- 指令模糊測試沒有打到任何一個。
- `removeFirst`／`removeLast` 的 15 處都先檢查了數量。

**GamePresentation**
- 唯一的 `try!` 是靜態資料。
- 57 個 `preconditionFailure` 有兩類：
  - 示範、挑戰、教學、真實世界示範的建構器，跑的是 App 內建的固定資料，CI 每次都會建一次；
  - 名稱表（`DisplayText.swift:862`、`PerformanceText.swift:79`），由 enum 窮舉。
- 會影響畫面的 `precondition` 都有呼叫端保護：
  - `MapCamera.worldDistance` 與 `NetworkSession.worldPoint` 要求 scale／size > 0，呼叫端保證；
  - `PolylineDetail.points` 的 `start < end`，`MapArt` 都先檢查；
  - `FareBandScale` 的 Stepper 範圍；
  - `Tutorial` 的步驟索引。
- 整數除法與 `%` 都先檢查分母 > 0 或用 `max(1, …)`，包括：
  - `EconomyText.percentage`、`LoadCharts`、`LineReportText`、`StatisticsCharts`；
  - `SectionFlow`、`NetworkFlowReport.share`、`DepartureBoard`、`TrainDiagram` 等。
- `Int(Double)` 有防護：
  - 相機與觸控（`MapCamera.wholeUnits` 擋 NaN 並夾住）；
  - `TrainDiagramViewport`、`CityMap.tiles`（先確認有限值）、`DeviceLoad`、`FrameTimeRecord`。
- `Dictionary(uniqueKeysWithValues:)` 都以唯一 ID 或 enum 為鍵。
- 平方距離的上限是 2⁶¹，不會溢位，因為 `WorldCoordinate.limit` 是 2²⁹。

**App 層（只讀程式，UNVERIFIED）**
- 沒有 `try!`、`as!`。
- `fatalError` 只有兩類：
  - 三個 `init(coder:)`，沒有 storyboard，不會被呼叫；
  - UI 測試的啟動參數（`-ui-test-world`、`-lesson-stars`、UI 測試存檔），玩家不會帶。
- 強制解包只有兩處，都先檢查過：`StationOperationsView.swift:84`、`Map3DMetalView.swift:940`。
- `removeFirst`／`removeLast` 都有保護。
- range 都在常數上或先比大小，例如 `MapArt` 的 `low <= high`、`GoalsPanel` 的 `1...max(1, stars)`。
- 只有一個 `%`（`Palette` 的色盤，非空常數）。
- 沒有變數步長的 `stride`。

**ForEach 的重複 id**
- 只會讓 SwiftUI 印警告，不閃退。幾處可能重複，留給之後整理：
  - `StationPanel.swift:1537` 的 `waitingBreakdown` 用字串當 id；
  - `LinesPanel.swift:1974` 的 `feedback.ends` 以車站當 id，頭尾同站的非環線會重複。

**3D**
- 載入、記憶體、資源找不到歸 BH6，這裡只看了 `!`，沒有找到。

## 6. 驗證

**Linux，VERIFIED**
- `swift build --build-tests -Xswiftc -warnings-as-errors`：乾淨。
- 存檔模糊測試：79 個存檔 × 300 = 23,700 個 case，0 個閃退，22 個逾時（P3-5）。
- 指令模糊測試：40 個 case × 300 個指令。
  - 參數放開時打到 P3-1 到 P3-4。
  - 把 `Int` 參數夾在 ±2⁴⁰（點擊不會更大）以後，40 個 case 中只剩 P3-4（班距仍用 Int64 極值）。其他沒有閃退，存讀也都回得來。
  - 另用 `two-towns` 打法跑 20 個 case（編號 100–119）× 300 個指令：一樣只打到 P3-4。
- property campaign `PROPERTY_STRESS=8`：<<PROP>>
- 長時間：<<LONG>>

**UNVERIFIED**
- App 層與 3D 是只讀程式，要 macOS／實機確認，包括 P2-1。

**怎麼再跑**
```sh
swift build --build-tests
CRASH_FUZZ=40 CRASH_FUZZ_STEPS=300 .build/out/Products/Debug-linux-x86_64/GamePresentationTests-test-runner \
  GamePresentationTests.CrashFuzzTests/testRandomCommandsDoNotTrap 2> fuzz.log
tail -1 fuzz.log   # 當掉時最後一行是兇手
```
- `CRASH_FUZZ_FIRST` 從第幾個 case 開始，`CRASH_FUZZ_POLICY` 換打法，`CRASH_FUZZ_DAYS` 先玩幾天。
- 這個測試不設 `CRASH_FUZZ` 時立即跳過，CI 不花時間。

**參考與外部專案**：這輪是抓蟲，沒有要移植的功能。模糊測試是這個專案自己寫的，沒有用外部程式碼。
