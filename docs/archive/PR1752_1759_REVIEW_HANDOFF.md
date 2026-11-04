# 交接：PR #1752–#1759 與 #1747 審查（審查 L8）

派工單 REVIEW-L8（遊戲規劃第 44 任 session_01YGNNukw5koUxDsjkSBmJJy，2026-11-03，111.1 發版前）：審查 L7 之後已合併的 PR，重點是要進 111.1 的 #1757、#1758、#1759，順帶 #1747。格式同 L7（`PR1725_1751_REVIEW_HANDOFF.md`）。

- Session：session_01YGNNuomLSqwARXBcD4FSVP，branch `claude/review-l8`。
- 基準：`main` **d8d2b32**（#1758 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff，和它的決策檔。
- 做法：全部由本 session 自己讀，沒有用子代理。L8-1 用 Linux 臨時測試重現，量完刪掉，沒有提交（測試寫在該節，修的人可以直接當回歸測試）。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

`git log --first-parent 62b3220^..d8d2b32` 逐一核對。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1758**（DAYPASS-MIDNIGHT，決策 551 續，修 L7-1、L7-2）、**#1759**（L6FIX，決策 542、547 續，修 L6-3、L6-4、L6-5）、**#1747**（TYMCLIST2 的 `comesPast`，決策 559） |
| GamePresentation | **#1757**（DEPOTADD-2，決策 557 續，修 L7-3、L7-4）、#1752（LANDMARK101，決策 555 續，截圖場景）、#1758 的 `BalanceReportTests` |
| App | #1759 的 `LinesPanel`（停車線太短的提示） |
| CI | #1756（CIOPT-6，決策 563：self-test 獨立成 job、類別權重、`Map3DModelTests` 的型別檢查） |

沒有審：只改文件的 #1753、#1754（L7 本身）、#1755。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **0** |
| P3（記著） | **1**：L8-1 |

沒有會讓 111.1 玩家漏班、當機、存檔讀不回或錢算錯的，**沒有** send_message 緊急通報。#1757、#1758、#1759 都可以照常進 111.1。

### GameCore

- **#1758**（修 L7-1、L7-2）：
  - `dayPassDay(onDay:)` 改用 `Tourism.countingGraph(of:day:)`，午夜結算與白天看的是同一張「那一天」的圖；子公司的一日券客人（`Subsidiary.swift` 兩處）也經過它，一起好了。L7-1 的回歸測試（`testTheDayPassSettlesWhenTheLinesCloseAtMidnight`）在 `.allDay` 與 `.standard` 都跑，還比對了午夜後讀昨天和中午讀今天相同。**L7-1 修好。**
  - `countedAt(day:line:serviceDay:)`：先試原本的時刻；那時線沒有車，就從「每個等級帶的開始」加上「營運時間的開始」中，排序後取第一個「在營運時間內、而且那個等級有車」的分鐘。逐一推過：任何在營運時間內、有車的分鐘，它所在的等級帶若在營運時間內開始，那個開始就在候選裡；若在開門前就開始，開門那一分就在候選裡；所以只要有一刻能跑，就找得到。跨午夜的營運時間（如 22:00–02:00）也一樣，挑到的凌晨分鐘照 L7 已確認的規則算前一晚的營運。候選都是整數、排序後取，確定性沒問題。
  - `ServiceLine.setsTrains(at:)`：有 runs 的線看有沒有車（runs 不分等級，和 `services(at:)` 一致）；環狀線要 2 列。若環狀線某等級只設 1 列，`setsTrains` 說沒車、會改挑別的時刻，但別的時刻也一定能跑才會被選，最壞是不換時刻，不會讓原本算得到的線算不到。
  - **L7-2 還剩一種沒修好，見 L8-1**（看的是「整條線」有沒有車，圖卻是每個 service 各自要有班距）。
  - 效能：`dayPassToday()` 原本就每次建一張圖，現在仍是一張，只是每條線多算一次時刻，不變重。
- **#1759**（修 L6-3、L6-4、L6-5）：
  - L6-4：`pathOutOfDepot` 改回傳 `(path, standing)`，`lineDirectionPath(avoiding:)` 在 `standing` 不空時用新的 `path(from:toStation:length:forbidden:avoiding:)`（`forbidden` 照擋、站著的列車所在的邊加 `standingPenalty`）。`standing` 空的時候走舊路徑，所以不是從機廠出來的列車行為不變。`edgePenalty` 由 `Set` 轉 `Dictionary` 只拿來查，不影響順序。若唯一避開 `against` 的路要經過站著的列車，會回傳那條路（懲罰不是禁止），和修前一樣，可接受。
  - L6-5：`timetabled` 改成兩列任一照班表就算。只是讓「兩列都在起點站時的假越行」與「要先離開才算追上」的判斷也適用在玩家的線與實際班表的線共軌時；沒有找到反例。
  - L6-3：`depotFits` 用 `berths(of:length:)`（不看有沒有被佔），所以「機廠滿了」不會被誤報成「太短」。`tooShortDepots` 只在**每一條**停車線都太短時才提示；有一條夠長、其他都太短時，第二列以後一樣放不進去、留在端點，但不提示——這是設計（決策 547 寫「都比…短」），記著不列。玩家文字只寫做什麼與怎麼處理（加長停車線），符合規則。
  - 測試：`DepotPullOutStandingTests`、`LiveOvertakeTests`、`DepotToolsTests` 都過。
- **#1747**（決策 559，`comesPast`）：在路上的列車若「前面的路經過 `train` 身體所在的邊」或「在同一條邊、同一方向、在 `train` 後面」，就不算它先到。後者成立時它一定要先經過 `train` 才能往前，對。前者用的是整條邊：同一條很長的月台邊上，若 `other` 的停車位在 `train` 的後半段之前，理論上它不必經過 `train` 就到得了；但那時它要停的位置和 `train` 在同一條邊上，`train` 等它也只會互等，忽略它不會讓兩列撞在同一段（行車控制關閉時本來就不保留月台）。讀程式推的，**可能**，不列。`PlatformWaitBehindTests` 過。

### GamePresentation

- **#1757**（修 L7-3、L7-4）：
  - L7-4：`realDepotOffer(for:site:)` 沒有缺的機廠時回「這條線沒有可以加建的機廠」的拒絕報價，不再越界。
  - L7-3：`addRealDepot` 按下時用現在的世界重拿報價：要等末班車就回失敗（說明照新報價），地點或價錢和卡片上的不同（`addition == offer.addition`）就請玩家重開，不會用舊價錢扣錢，也不會在早上把線上的車拿下班次。`RealLineDepotAdditionTests` 9 個都過，含 L7-3 的情境。
  - 邊角（不列）：`realDepotOffer` 用名字找地點，找不到時退回第一個。卡片開著時切換語言，名字對不上，若那條線缺兩個以上的機廠會拿到另一個地點的報價、`addition` 不同，結果是「請重新打開」——失敗得安全，不會加錯。
- **#1752**：截圖場景的線改在地標北邊 300 m，只影響 `-screenshot-3d-view` 的截圖；`ScreenshotLandmarkTests` 過。
- #1758 的 `BalanceReportTests`：只有 `BALANCE_STANDARD_HOURS=1` 時改營運時間，平常不變。

### App

- #1759 的 `LinesPanel`：多一行 `Theme.warning` 的註腳文字，只在 `tooShort` 不是 nil 時出現。畫面 **UNVERIFIED**（沒有 macOS）。

### CI

- **#1756**（決策 563）：self-test 從 change-detection 拆出成自己的 job，gate 多看 `SELFTEST`；self-test 本身的新案例涵蓋 failure、無結果、不需要卻跑了三種。本機跑 `.github/scripts/swift-shards-selftest.sh` 通過。

## 二、發現

### L8-1（P3）#1758：一條線的主班次只在尖峰、另一個 service（區間車或快車）在離峰有車時，主班次的觀光客與一日券整天算 0

- **位置**：`Sources/GameCore/Passenger/Tourism.swift:130-140`（`countedAt(day:line:serviceDay:)` 一條線只挑一刻）、`Sources/GameCore/Railway/ServiceLine.swift:653-658`（`setsTrains(at:)` 看的是「任一 service」有車）、`Sources/GameCore/Passenger/PassengerRoutes.swift:245`（圖是每個 service 各自 `plans[service]?.headway` 為 nil 就跳過）。
- **問題**：`setsTrains` 回答「這條線任一個 service 在這個等級有車」，所以中午只要區間車有車，整條線就在中午讀；但中午主班次（全程車）沒有班距，不進圖，只有區間車會到的站有路。主班次只在尖峰跑的那一段（例如末端的景點站），觀光客整天算 0，一日券也跟著少（同一張圖）。L7-2 的根（一天只看一刻）在 service 這一層還在。
- **玩家看到**：一條線設了區間車、離峰只開區間車，景點在區間車不到的末端時，景點顯示「沒有人能搭車到這裡」，一日券也少賣，雖然尖峰全程車整天在跑。要玩家自己把離峰與尖峰設成這樣，罕見。
- **驗證**（Linux，臨時測試，量完刪掉）：`TourismTests.touristLineWorld(window: .standard)`（四站、景點在第 4 站旁），主班次設 `TrainsInService(peak: 1, offPeak: 0, low: 0)`：
  - 沒有區間車：昨天 **240**、`.ok`（#1758 修好的情況）。
  - 加區間車 `addLinePattern(line, calling: [0, 1])`、`TrainsInService(peak: 0, offPeak: 1, low: 0)`、派一列車：昨天 **0**、`.noSource`。
  - **VERIFIED**（main d8d2b32）。回歸測試（放進 `TourismTests`，修前紅）：

  ```swift
  func testAMainServiceOnlyAtThePeakCountsBesideAPatternOffPeak() throws {
      var world = try touristLineWorld(window: .standard)
      let line = LineID(rawValue: 1)
      let pattern = try world.addLinePattern(line, calling: [0, 1])
      try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 0, low: 0))
      try world.setLineTrainsInService(line, to: TrainsInService(peak: 0, offPeak: 1, low: 0), pattern: pattern)
      try world.assignTrain(try world.purchaseTrain(named: "P").id, to: line, pattern: pattern)
      try world.advance(ticks: 1_442)
      XCTAssertEqual(world.attraction(id: AttractionID(rawValue: 1))?.yesterday, 240) // main：0
      XCTAssertEqual(world.attractionStatus(of: AttractionID(rawValue: 1)), .ok)      // main：.noSource
  }
  ```
- **建議修法**：時刻改成每個 service 各挑一刻：`PassengerRouteGraph.init` 的 `lineTime` 改成 `(ServiceLine, Int) -> GameTime`（第二個是 service 索引），`countedAt` 用 `setsTrains(at:service:)`（只看那個 service 的 `trainsInService`／`targetHeadways`）。注意 `services(at:)` 的每個 service 的班距會受前面 service 的佔用影響（`loads`），不同 service 用不同等級時，前面的 service 要用同一個等級算佔用；最簡單是每個 service 用它自己的時刻、各自呼叫一次 `services(at:)`。只動 GameCore；`.allDay` 與每個 service 都在中午有車的線結果不變。要跑 `GoldenScenarioTests`、`TourismTests`、`DayPassTests`、`SubsidiaryTests`。決策 551 寫續。

### 沒列的

- `tooShortDepots` 只在「每一條」停車線都太短時提示（上面 #1759）。
- `comesPast` 用整條邊判斷（上面 #1747）。
- #1757 卡片開著時切換語言（上面 #1757）。
- L7 沒列的 `currentTouristFlows()`（乘客計畫的觀光客需求用「現在」的圖）#1758 沒動；理由同 L7（06:00 重建計畫），仍不列。

## 三、驗證

Linux、Swift 6.4.0、`main` d8d2b32：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（從零 441 s 通過；加臨時測試後增量建置通過）。
- `swift test --skip-build --filter`：`TourismTests`（28）、`DayPassTests`（11）、`SubsidiaryTests`（16）、`DepotPullOutStandingTests`（3）、`LiveOvertakeTests`（5）、`PlatformWaitBehindTests`（3）、`RealLineDepotAdditionTests`（9）、`DepotToolsTests`（12）、`ScreenshotLandmarkTests`（2）：**VERIFIED**，全過。
- `.github/scripts/swift-shards-selftest.sh`：**VERIFIED**，通過。
- L8-1：臨時測試在 main 上印出 0 與 `.noSource`，量完刪掉。**VERIFIED**。
- `comesPast` 的「可能」與 #1757 的語言切換：讀程式，**UNVERIFIED**。
- App（#1759 的 `LinesPanel`）：畫面、Simulator、真機都 **UNVERIFIED**（沒有 macOS）。

## 四、下一步

- **L8-1（P3）**：不擋 111.1。之後派一個小 GameCore session（`Tourism.swift`、`PassengerRoutes.swift`、`ServiceLine.swift`），附上面的回歸測試；決策 551 續。
- L6-3、L6-4、L6-5、L7-1～L7-4 都已由 #1757、#1758、#1759 修好，下一輪不用再追。
- 下一輪審查從 **#1760** 起數（含這輪時還開著、編號在前面但之後才合併的 PR，例如 #1743、#1750）。
