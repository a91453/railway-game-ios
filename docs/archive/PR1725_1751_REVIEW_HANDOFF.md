# 交接：PR #1725–#1751 與 #1693 審查（審查 L7）

派工單 REVIEW-L7（遊戲規劃第 44 任 session_01YGNNukw5koUxDsjkSBmJJy，2026-11-03，109.1、110.1 發版後）：獨立審查 L6 之後已合併、改了程式的 PR，加上 L6 漏掉的 #1693（FLANE5），找正確性 bug。格式同 L6（`PR1696_1724_REVIEW_HANDOFF.md`）。

- Session：session_01YGNNuoFAjVAufrZuZyeVni，branch `claude/review-l7`。
- 基準：`main` **be51c86**（#1744 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff，和它的決策檔。
- 做法：全部由本 session 自己讀，沒有用子代理。L7-1、L7-2、L7-3 用 Linux 臨時測試重現，量完刪掉，沒有提交（測試寫在各節，修的人可以直接當回歸測試）。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

`git log --first-parent a4dddd4..be51c86` 逐一核對，只看改到 `Sources/`、`RailwayGameApp/`、`Tests/`、`.github/workflows`、`tools/` 的。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1723**（WENHUCAP，決策 549）、**#1731**（TOURFIX2，決策 551 續） |
| GamePresentation | #1733（WENHULIST，決策 552）、#1740（WENHUFIX，決策 552 續）、**#1741**（DEPOTADD，決策 557）、#1745（WENHUTRN，決策 558）、#1746（EMU700，決策 560）、#1748（機場捷運車型，決策 561）、#1738（TILT60，決策 555）、#1732（海風號山嵐號，決策 554）、#1734（新光摩天大樓，決策 550）、#1730、#1742（Codex 的 EMU700、文湖線兩款車模型） |
| App | #1693（FLANE5）、#1725、#1727、#1728（CRASHSWEEP-3）、#1737（SUNPCF，決策 357 續）、#1738 的 App 部分、#1741 的 `LinesPanel` |
| UI 測試 | #1739（FLANE7） |

沒有審：只改文件、圖或發版說明的 #1726、#1729、#1735、#1736、#1744、#1749、#1751。#1743、#1747、#1750 還沒合併，不在範圍。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **1**：L7-1（範圍外的舊 bug，與 L6-1 同一個根） |
| P3（記著） | **3**：L7-2～L7-4 |

沒有 P1，沒有 send_message 緊急通報。

### GameCore

- **#1723**（決策 549）：兩行。「正線」改用 `keepingLeft: true` 找，`PathMemo` 的 key 本來就含 `keepingLeft`，不會拿到不靠左的舊結果；世界沒開靠左時 `networkPath` 的 `keepLeft && keepingLeft` 照舊。最後一步帶 `rejoining`：正線月台本身一定接得回，所以「旁邊都被佔時仍停正線」不變；找不到時回 nil、照原路停自己的月台。行車控制開著時 `platformWaits` 回 nil，走不到。沒有找到錯。L6 說「L4-1 仍有一半在 #1723」，已補完。
- **#1731**（決策 551 續，修 L6-1）：L6-1 修好，L6-2（兩條營運時間不重疊的線接駁）也一起好了：圖改成每條線各用自己的時刻（`lineTime`），兩條線同時在圖裡。`countedAt(day:window:)` 的中點 `% minutesPerDay` 對跨午夜的營運時間落在當天凌晨，`ServiceWindow.contains` 把它算成前一晚的營運，測試逐一掃過 0–1440 開始、到 `latestClose` 的組合都在營運時間內。`attractionStatus` 與 `closeTourismDay` 兩處都換了。**沒換的兄弟函式見 L7-1**；「一刻」的做法還剩一個洞，見 L7-2。
- L6-3、L6-4、L6-5 在 main be51c86 仍在（`RunDepot.swift:129-133`、`GameWorld.swift:4088`、`HeadwayOvertake.swift:109` 都沒變），L6FIX 在修，不重報。

### GamePresentation

- **#1733**（文湖線上架）：木柵機廠改 `compact`；`groundSamples` 只在 `site.beyond != nil` 時讀；`yard` 找「越過水面」的位置用 `TrackRise.spacing` 一步步往後推，最多 `furthestYardShift`，都不行時留在原處、由 GameCore 拒絕（失敗原子）。`water` 的預設 `{ _ in false }` 只給沒傳的舊呼叫點，行為不變。沒有找到錯。
- **#1740**（WENHUFIX）：只在「兩種抬高都被拒」時才多鋪兩次（`clearingTrack`），平常的線不變。`crossingLevels` 走 `world.network.edges`（陣列，順序固定），同一公尺取最後一條，結果確定。`crossings` 空時回「坡度」的拒絕訊息，但外層最後回的是第一次鋪的 `laid.offer`，玩家看到的訊息不會錯。效能：每條既有軌道每 4 m 取一次位置（先算位置才比外框），全台灣台鐵的大圖上一次約數十萬次；只在兩次都被拒時跑，記著不列。
- **#1741**（DEPOTADD）：命令可編解碼（`realDepot` 欄位）、`editTrackAsOne` 包住整段（一步失敗全退）。`realDepotOffer(for:site:)` 的 `sites[0]` 在沒有缺的機廠時會當掉，但唯一的呼叫點先檢查過 `missingRealDepots` 不空；公開 API，順手修時改 `guard`。**確認框用的是點按鈕當下的報價，見 L7-3。**
- **#1745／#1746／#1748**（新車型進營運）：新的 set 都接在清單最後，前面的模型索引不動；`drawn` 在模型包沒有頭車模型時退回 `fallback`，`farModel`、`layout`、`isTurned` 都改用 `drawnSet`，一致。`expressKey` 的 `E` 前綴只加在有 `kind` 的班表（只有 `tymc_times.json`），`number(ofRealTrain:)` 取尾端數字，`E12` 也拿到 12。EMU700 比例 8:5:4:3＝20，`share` 0–19 都有車型。沒有找到錯。
- **#1738**（TILT60）：`leaned(dy:)` 與 `tilt(atDistance:from:lean:)` 互為反函數（`lean = (wanted − own)·mostTilt/own`）；`own` 很小時 `lean` 被夾在 `mostLean`，所以遠一點的相機斜不到 60°，是設計（決策 555：隨距離淡掉）。`groundCorners` 的射線看向地平線以上時用遠平面，不會除以 0。`Map3DCamera` 的 `==`／`hash` 都加了 `lean`。手勢：傾斜判定前捏合與旋轉照常；判定為傾斜後兩者各自 `scale = 1`／`rotation = 0`，手指少於兩根時 `fingers()` 回 nil、不動。沒有找到錯。
- **#1732**、**#1734**、**#1730**、**#1742**：只加或改模型；新檔的 `!` 都在固定資料上（`points.last!` 等），模型測試會建每一個。

### App

- **#1693**（FLANE5）：`Map3DModelsWarmUp` 與 `-story-card-ms` 都在 `#if DEBUG`，Release 不變；預熱在 `.background` 的 detached task 做，好了才回 main actor 設 `isReady`。
- **#1725／#1727／#1728**（CRASHSWEEP-3）：`GeometryReader` 的閉包改 `@Sendable`、只抓值，內容抽成 struct；或改 `onGeometryChange` 量尺寸、量到之前不畫（`viewport != .zero`、`height != nil`、`tableSize != .zero`）。`Map3DTrainLabelsLayout` 的 `sizeThatFits` 回提議大小、每個標籤以底部中點放在 `foot`，修好了舊的 alignment guide 讓單一標籤跑到左上角的問題。`.environment(\.regionStyle, region)` 從 reader 裡面移到外面，環境照樣往下傳。`TrainDiagramView` 第一幀 `chartSize == .zero` 時 `plot` 寬高夾到 1，只畫一幀空圖，無害。`RailwayGameApp/Views` 裡沒有 `@Sendable` 的 `GeometryReader` 還有 3 處（`MapView.swift:285`、`TutorialOverlay.swift:19`、`ContentView.swift:469`），不在這幾個 PR 改的範圍，CRASHSWEEP 的清單自己決定要不要收。
- **#1737**（SUNPCF）：tent 權重每軸 `(3−2f)+(1+2f)=4`，四個取樣乘積加總 16，除以 16 對。16 位元深度的步距是 `2·depthReach/65536`（8 km 約 12 cm），#1738 讓陰影方塊變大只改 `extent`、不改 `depthReach`，0.3 m 的偏移仍蓋得住。
- **#1741** 的 `LinesPanel`：`missingRealDepots` 每次重畫都算，但只是 `filter` 加距離，不重；按鈕按下時才在主執行緒算報價（`pricingCopy` 兩次＋讀地形＋鋪一次），大地圖上可能頓一下，沒有量，**UNVERIFIED**。

### UI 測試

- **#1739**（FLANE7）：只放長等待、改用 `becomesHittable`，沒有放鬆斷言內容。

## 二、發現

### L7-1（P2）號誌網路（新局預設）下，一日券在午夜結算成 0，子公司的一日券客人也是 0（範圍外的舊 bug，與 L6-1 同根）

- **位置**：`Sources/GameCore/Economy/DayPass.swift:94-98`（`dayPassDay(onDay:)` 用 `PassengerRouteGraph(world: self)`，也就是「現在」的圖）、`:136`（`settleDayPasses` 在午夜呼叫它）、`Sources/GameCore/City/Subsidiary.swift:189`、`:300`（`settleSubsidiaries` 在午夜呼叫它）。
- **問題**：#1719／#1731 把觀光客的計數改成「每條線在它營運時的圖」，但同一份觀光客流量的另外兩個結算沒有換：一日券（決策 174 系）與子公司的一日券客人。它們在午夜 00:00 結算，那時預設營運時間（`ServiceWindow.standard`，06:00–24:00）的線全收班，圖裡沒有路，`reaches` 全部 false，一日券賣出 0 張。新局一律 `setPassengerRoutingMode(.network)`（`NewGame.swift:74`）而且是經營模式，所以**每個新局只要賣一日券就收不到錢**；`.direct`（舊存檔）不受影響，因為 `passengerTrip` 不看營運時間。
- **玩家看到**：設了一日券，白天看今天的一日券（`dayPassToday`）有賣，帳本卻沒有「一日券」那一列（營收 0、補給票價也 0）；遊樂園等子公司的一日券客人每天都是 0。晚上 00:00–06:00 看「今天的一日券」也是 0。
- **驗證**（Linux，臨時測試，量完刪掉）：四站的線（`TourismTests.touristLineWorld` 的鋪法，兩個景點在第 3、4 站旁、`.network`、經營模式、`setDayPass(4500)`），跑到中午讀 `dayPassToday()`，再跑到隔天 00:02 找 `dailyDayPass` 那一列：
  - `.allDay`：中午 120 張；結算 `dayPassSales 540,000`、`dayPassFares −720,000`；景點昨天 300。
  - `.standard`（06:00–24:00）：中午 120 張；**結算沒有這一列**；景點昨天 300（#1731 修好的那一邊是對的）。
  - 修前紅的指令：把下面的測試放進 `Tests/GameCoreTests/`，`swift build --build-tests -Xswiftc -warnings-as-errors && swift test --skip-build --filter L7DayPassProbeTests`。**VERIFIED**（main be51c86 上紅）。

  ```swift
  func testTheDayPassSettlesWhenTheLinesCloseAtMidnight() throws {
      var world = try touristLineWorld(window: .standard) // TourismTests 的鋪法，第 3 站也當景點
      world.setEconomyMode(.management)
      try world.setDayPass(Money(4_500))
      try world.advance(ticks: 12 * 60)
      XCTAssertEqual(world.dayPassToday().sold, 120)
      try world.advance(ticks: 12 * 60 + 2)
      XCTAssertNotNil(world.accounts.entries.last { $0.kind == .dailyDayPass }) // main：nil
  }
  ```
- **建議修法**：`dayPassDay(onDay:)` 改用 `Tourism.countingGraph(of: self, day: day)`（決策 551 續的那張圖），結算與白天看的都是「那一天」的量，不受現在幾點影響。子公司跟著好。`.allDay` 的線結果不變。要跑 `GoldenScenarioTests`：有一日券、號誌網路、`.standard` 營運時間的場景現在結算 0，修了會變，那就是這個 bug，PR 要逐值說明。只動 GameCore 的 `DayPass.swift`；決策 551 寫續。`currentTouristFlows()`（`Tourism.swift:778`，乘客計畫的觀光客需求）也用「現在」的圖，但計畫在 06:00 服務等級改變時會重建（決策 470），白天的需求是對的，不列；修的人順手看一下要不要一起換。

### L7-2（P3）#1731：離峰沒有車的線，觀光客整天算 0

- **位置**：`Sources/GameCore/Passenger/Tourism.swift:116-121`（`countedAt(day:window:)`）、`Sources/GameCore/Passenger/PassengerRoutes.swift:245`（`plans[service]?.headway` 為 nil 就 `continue`）。
- **問題**：營運時間包含中午的線一律用 12:00。12:00 是離峰（`ServiceDay.standard`），玩家把離峰車數設 0（`TrainsInService` 每個等級 0 到上限都合法）時，那一刻這條線沒有班距、不進圖，整天的觀光客算 0、景點顯示「沒有人能搭車到這裡」，即使尖峰整天在跑。L6-2 說的「一天只用一刻」還剩這一種。
- **驗證**（Linux，臨時測試，量完刪掉）：同上的四站線、`.standard`、跑 1,442 tick：`TrainsInService(peak: 1, offPeak: 1, low: 1)` 昨天 240、`.ok`；`(peak: 1, offPeak: 0, low: 0)` **0、`.noSource`**。**VERIFIED**。
- **建議**：`countedAt` 依線挑「營運時間內、這條線有車」的一刻（例如先試中午，沒有車就試尖峰的開始），或圖在「整天」模式下把任一等級有車的線都放進去。罕見（要玩家自己把離峰設 0），可以和 L7-1 同一個 PR。

### L7-3（P3）#1741：加建機廠的確認框用按下時的報價，遊戲繼續跑到早上也照加，在路上的列車全部被拿下班次

- **位置**：`RailwayGameApp/Views/LinesPanel.swift:1349-1351`（按鈕按下時算 `realDepotOffer`，之後確認框一直用它）、`Sources/GamePresentation/RealLineDepotAddition.swift:156-170`（`addRealDepot` 只看報價裡的 `waitsForTheLastTrain`，不重算）、`:452-462`（`build` 把有 `execution` 的列車都 `unassignTrain`＋`stopTrainService`）。
- **問題**：`waitsForTheLastTrain` 是報價當下算的；確認框開著時遊戲照跑，過了首班車時間再按「加建」，`addRealDepot` 仍照舊報價加建，`build` 把正在跑班次的列車全部拿下班次、重新指派到線上，等新時刻表——也就是決策 557 想用「末班車收班後才加建」避免的「班次重發或掉班」。
- **玩家看到**：深夜打開加建，看說明看到天亮（或高倍速下幾秒）才按，早上線上的車一起停住、等下一班的時刻，當天早上的班次少發。
- **驗證**（Linux，臨時測試，量完刪掉）：`RealLineDepotAdditionTests.ankengBoughtWithoutItsDepot(rules: .simple)`，跑到第二天 02:00 取報價（`waitsForTheLastTrain == false`），再跑 6 小時到 08:00：新報價 `waitsForTheLastTrain == true`，舊報價 `addRealDepot` 回 **true**，在班次上的列車 6 → 0，機廠加上。**VERIFIED**（main be51c86）。
- **建議**：`addRealDepot` 先用現在的世界重算 `RealLineDepotAddition.isAtRest`（或整個重報價、比對價錢），不在休息時間就回失敗訊息；UI 不用改。回歸測試就是上面那個。

### L7-4（P3）#1741：`realDepotOffer(for:site:)` 在沒有缺的機廠時當掉

- **位置**：`Sources/GamePresentation/RealLineDepotAddition.swift:150`（`?? sites[0]`）。
- **問題**：公開 API，`missingRealDepotSites` 空時 `sites[0]` 越界。現在唯一的呼叫點（`selectedLineRealDepotOffer`）先確認不空，不會發生；之後有人直接呼叫才會。讀程式推的，**UNVERIFIED**（沒有呼叫路徑可重現）。
- **建議**：改成 `guard let site = … else { 回 refused 的報價 }`，和 L7-3 同一個 PR。

### 沒列的

- #1740 `crossingLevels`：一條既有軌道和新線平行、距離在 `crossingReach`（約 9 m）內時，整段都會被要求高出或低於它，結果多半被拒、退回第一次的報價。只在兩次都被拒時才走到，不會讓原本鋪得上的線變得鋪不上。
- #1738：兩指傾斜時 `tiltStart` 記的是手勢被辨識當下（已移動約 10 點）而不是手指放下時的相機；判定為傾斜後把距離與方向退回 `tiltStart`，捏合在判定前動到的那一點點會留下，無害。
- L6 沒列的 `Map3DTrainOcclusion.baked`（只 `deallocate` 沒 `deinitialize`）仍在，這輪多了 EMU700、文湖線兩款、機場捷運兩款的模型，每款多一份，量仍小。

## 三、驗證

Linux、Swift 6.4.0、`main` be51c86：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（從零 482 s 通過；臨時測試刪掉後再建一次 390 s 通過）。
- `swift test --skip-build --filter` `TourismTests`、`DayPassTests`、`CallingLoopPlatformTests`、`Map3DLeanTests`、`RealLineDepotAdditionTests`、`Map3DWenhuTests`、`Map3DEMU700Tests`、`Map3DTaipeiLandmarksTests`、`WenhuLineTests`：**VERIFIED**（GameCore 三類 36 個、GamePresentation 六類 42 個全過；`WenhuLineTests.testTheFirstMorningPeakRuns` 要 `WENHU_MORNING=1`，照設計略過）。
- L7-1、L7-2、L7-3：臨時測試在 main 上重現（L7-1 紅、L7-2 印出 0、L7-3 印出加建成功），量完刪掉。**VERIFIED**。
- L7-4：讀程式，**UNVERIFIED**。
- App 與 Metal 的 PR（#1693、#1725、#1727、#1728、#1737、#1738 的手勢、#1741 的 `LinesPanel`）：讀程式；畫面、Simulator、真機的行為都 **UNVERIFIED**（沒有 macOS）。

## 四、下一步

- **L7-1（P2）**派一個小 session 修（GameCore 的 `DayPass.swift`，2 點），附上面的回歸測試；決策 551 續。L7-2 可以一起（同一個「一天只看一刻」的根），或記在決策 551 的下一步。
- **L7-3、L7-4（P3）**一個小的 GamePresentation PR（`RealLineDepotAddition.swift`），附 L7-3 的回歸測試；決策 557 續。
- L6-3、L6-4、L6-5 由 L6FIX 在修，不重派。
- 下一輪審查從 **#1752** 起數（含這輪時還開著的 #1743、#1747、#1750，若合併時編號在前面也要看）。
