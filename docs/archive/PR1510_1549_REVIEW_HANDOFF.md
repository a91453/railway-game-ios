# 交接：PR #1510–#1549 審查（L1）

派工單 審查 L1（遊戲規劃第 36 任 session_01YGNNunAp2WBFfGrmq3mXES，2026-10-30）：審查 #1510–#1549 合進 main 的程式 PR。只找會讓玩家壞掉的：當機、存檔讀不回、舊存檔行為改變、決定性被破壞、主執行緒卡頓、iPhone／iPad 直橫畫面跑版、錢算錯、玩家看的文字違反 `docs/UI_THEME.md`。另一段 #1551–#1578 是審查 L2，另一個 session 做。

- Session：session_01YGNNuq2kgbe3peC7BKSFEX，branch `claude/review-pr1510-1549`。
- 基準：每個 PR 讀 merge commit 對 first parent 的 diff；建置與測試在 `main` **d71ffec**。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。疑點用 Linux 的 `swift build`／`swift test --filter` 和臨時量測驗證（量完刪掉，沒有提交）。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

| PR | 內容 | 層 | 點數 |
| --- | --- | --- | --: |
| #1510 | 淡海綠山線和淡海機廠一起收購（決策 489） | GamePresentation＋資料工具＋CI | 1 |
| #1511 | 車庫：列車展示開放給所有玩家（決策 492） | App＋GamePresentation | 1 |
| #1512 | 教學「看誰在搭車」直接打開旅客組 | App＋GamePresentation | 1 |
| #1514 | 地圖上的雨不再比地圖畫得勤 | App＋GamePresentation | 1 |
| #1515 | 修 #1513 的 REV-1、REV-2 | App＋GamePresentation | 1 |
| #1516 | CI 分組權重（淡海、六家、公車） | CI 腳本 | 1 |
| #1517 | CI：GamePresentation 分七份 | CI 腳本 | 1 |
| #1518 | What's New 96 | GamePresentation（文字） | 1 |
| #1519 | 先買藍海線再買綠山線（決策 493） | GamePresentation | 1 |
| #1520 | 「資料」可再開上個月的月報 | App＋GamePresentation | 1 |
| #1521 | CI：campaigns-19（決策 495） | CI 腳本 | 1 |
| #1523 | 3D 公車回程鋪不上時不再當掉（BH4） | GamePresentation | 1 |
| #1524 | 鋪路草稿在復原後重算價錢（BH1） | GamePresentation | 1 |
| #1526 | 分享路網不帶城市請託與未入帳貨運（BH5） | GamePresentation | 1 |
| #1528 | 跳到早上途中存檔不再讀回 ×6000（BH2） | GamePresentation | 1 |
| #1531 | 大型死結時死結搜尋不再對每列車重算整條線（BH9） | **GameCore** | 2 |
| #1534 | 車型目錄 Int(NaN)（BH8） | App＋GamePresentation | 1 |
| #1536 | iPhone 橫拿：損益表、土地格提示、車站卡不再被切 | App＋GamePresentation | 1 |
| #1537 | 收購與刪線改成一次編輯（54 秒） | GamePresentation | 1 |
| #1538 | 3D 駕駛室：底下的 2D 地圖不再跟車重畫 | App＋GamePresentation | 1 |
| #1540 | 3D 的淡海、安坑、高雄輕軌照實車畫（決策 496） | GamePresentation | 1 |
| #1543 | iPhone 橫拿的教學卡停在整行（決策 498） | App＋GamePresentation | 1 |
| #1544 | 實景地圖：公車線要走的自己的路不給拆 | GamePresentation | 1 |
| #1545 | 收購報價卡在背景排版（決策 497） | App＋GamePresentation | 1 |
| #1546 | 車站標籤不再蓋住警告泡泡（決策 501） | App＋GamePresentation | 1 |
| #1547 | 新台幣 PR-0：金額集中到 Money 的格式函式 | App＋GamePresentation | 1 |
| #1548 | 3D：沿現有路鋪的路鋪了就重建 | App＋GamePresentation | 1 |
| #1549 | 回開始畫面的自動存檔移出主執行緒（決策 497 續） | App＋GamePresentation | 1 |

共 28 個程式 PR、29 點。不算點、只看了 diff：#1527（只改打包資料的防照搬標記，決策 494；確認 JSON 仍讀得進，標記細節照決策不寫在公開 repo）、#1530（45DR1000 模型，同時把營運的 `dieselRailcar` 換成它並加 `dieselRailcarFar`）、#1533、#1539（模型）、#1541（UI 測試）、#1542（TestFlight 說明）。#1513、#1522、#1525、#1529、#1532、#1535 只改文件，不審。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（必修） | **0** |
| P2（下一版修） | **1**：L1-1 |
| P3（記著） | **2**：L1-2、L1-3 |

唯一的 GameCore PR 和真的執行結果一致：

- **#1531**（`Deadlock.swift`）：`isSpare(_:memo:)` 把同一個 `DispatchMemo` 在一次死結搜尋裡跨列車共用。`DispatchMemo` 的欄位都是以線（`journeys`、`capacityLayouts`、`capacities`…）或以列車加位置（`trips`、`depotTrips`、`runDepotTrips`）為鍵，搜尋期間世界不變（`deadlock` 的過濾與 `spareStandingAside` 的迴圈都不改世界），所以共用只省重算、不改答案；每日派車（Phase 0）本來就這樣跨列車共用同一個 memo。`trains.lazy.filter` 改成 `trains.filter` 只差在一次算完，順序相同，決定性不變。沒有改存檔、golden、replay。

其他有改到行為、特別看過的：

- **#1537** 收購與刪線包進 `editTrackAsOne`：刪線時列車帶著乘客被賣，一次編輯和逐步的結果由 `PassengerCheckOnceTests.testOneEditRemovesWhatTheStepsDid` 比對過（有乘客在車上），通過。
- **#1524** 鋪路前重算價錢：`RoadPreview` 只有在城市長出新路、或復原時才會變，時間流逝不會讓它每次都不同，不會變成「一直要再按一次」。
- **#1528** 跳夜途中存檔改存跳之前的速度：`worldToSave` 只改存下去的副本，不動進行中的世界。
- **#1545** 報價在背景排：`commandRevision` 只在 tick 以外改世界時加一（`GameSession.swift:36`），遊戲照跑時不會讓它一直重排。
- **#1547** 金額格式集中：`signedText`、`wholeDollars` 和舊的 `signedMoneyText`、`shortfallTexts` 算法逐行相同（含「虧不到半元仍是 -$ 0」）；地價圖例 `Money(steps * 100).moneyText` 和舊的 `"$ \(steps)+"` 同字。
- **#1520** 月報：`lastMonthReport` 只存在 session，讀檔後要等下個月才有按鈕，不是錯。

## 二、發現

### L1-1（P2）#1544：實景地圖上點自己的路要拆，有公車線時主執行緒卡約 2 秒，隨線數長

- **位置**：`Sources/GamePresentation/RoadDraft.swift:275`（`routeBroken(byTakingUp:from:)`），呼叫在同檔 `:260`（點路的處理，主執行緒）。
- **問題**：每點一次自己的路，`routeBroken` 對**每一條**公車線算兩次沿地圖的路（`way(ofSaved:station:)`），中間 `useOwnRoads` 換掉玩家的路、`defer` 再換回來；`useOwnRoads` 每次都清掉 `BusRoadNetwork` 已經算好的路網（`BusRoadNetwork.swift:556` `built.removeAll()`），所以兩輪都從頭建，事後公車圖層也要再建一次。和要拆的那段路離得很遠的線也照算。
- **量到的**（Linux debug，臨時測試，全台地圖田中大社路附近，3 站一線的城市公車 19 條，要拆的是 5 格自己的路）：

  | 公車線 | 點一次 | 其中 `routeBroken` | 其中 GameCore `removeRoads` 試算 |
  | --: | --: | --: | --: |
  | 0 | 0 ms | — | — |
  | 19 | 2,125 ms | 2,100～2,257 ms | 261～271 ms |

  release 會快幾倍，但仍是點一下停零點幾秒、線越多越久；實機 **UNVERIFIED**。
- **玩家看到**：實景地圖、公車工具的「道路」模式，點自己鋪的路要拆，畫面停住一下才出現拆除的提示；線多的存檔停得更久。
- **重現**：真實地圖，建幾條（十條以上）城市公車線，自己鋪一段路，公車工具 → 道路，點那段路。
- **建議修法**：只檢查路線經過範圍（站點外框加邊距）和要拆的格子重疊的線；換路時不要清掉整個快取（用一份暫時的路網算，或只讓碰到那幾格的區域失效）；或把檢查移到背景，先顯示「檢查中」。

### L1-2（P3）#1546：選了車站時，車站標籤每畫一次都重算全部警告泡泡的位置

- **位置**：`RailwayGameApp/Views/MapStationTagView.swift:127`（`placement(under:)`）呼叫 `MapAlertBubbles.placements(...)`（`MapAlertBubbles.swift:61`）。
- **問題**：泡泡圖層本來就算一次全部泡泡的位置（`placeBubbles`，要走過畫面內每個車站）；現在標籤的 body 每次重算又整套算一次，地圖拖動、每個 tick 都會。選了車站時這部分成本變兩倍。沒有量，泡泡少的時候看不出來；實景地圖泡泡多時可能多幾毫秒。
- **玩家看到**：實景地圖、選著車站拖地圖時，可能稍微不順。
- **建議**：泡泡圖層算好的位置放進 `GameScreenState`（或一個依 camera＋worldRevision 的記憶），標籤直接讀。

### L1-3（P3）#1549：按「回到開始畫面」後、自動存檔寫完前，地圖還能操作，那段時間做的事不會存

- **位置**：`Sources/GamePresentation/GameLauncher.swift`（`returnToStartInBackground(at:)`），按鈕在 `RailwayGameApp/Views/HUDView.swift:558`。
- **問題**：按下去時遊戲停了、世界在那一刻複製去存，存完（大存檔幾百毫秒）才換到開始畫面。這段時間地圖與工具還能點，玩家若在這時下了指令（例如蓋一段軌道、按了取消），會照常扣款與生效，但不在剛存的自動存檔裡，接著就離開遊戲，那一步就不見了。存檔失敗時遊戲繼續，這種情況沒問題。
- **玩家看到**：極少見；在大存檔上按了回開始畫面又馬上點地圖，回來讀檔時少了最後一步。
- **建議**：`isReturningToStart` 期間在遊戲畫面上蓋一層不收觸控的「儲存中」（或把 `session` 的指令擋掉）。

## 三、驗證

Linux、Swift 6.4.0、`main` d71ffec：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（通過）。
- `swift test --skip-build --filter`：`DeadlockSearchCostTests`、`IdleTrainDeadlockTests`、`SavedGameTests`、`ReplayFixtureTests`、`GoldenScenarioTests`、`RoadDrawRealMapTests`、`SelectionHeadLayoutTests`、`MapLabelPlacementTests`、`RealLineOfferPreparingTests`、`ReturnToStartInBackgroundTests`、`RoadCellCountTests`、`CoveredMapTests`、`Map3DShowcaseTests`、`FinancialStatementsTests`、`MoneyTextSourceTests`、`EconomyDisplayTests`、`TutorialCardPlacementTests`、`SharedNetworkTests`、`NightSkipTests`、`PassengerCheckOnceTests`、`BusStopLabelsTests`、`RollingStockCatalogTests`、`Map3DRainTests`、`StationPanelFocusTests`、`MonthlyReportTests`、`DanhaiDepotTests`：**VERIFIED**，全部通過（各測試目標合計 146 個，略過 4 個照常略過的）。
- L1-1 的毫秒數：臨時測試量的，量完刪掉，沒有提交。
- L1-2、L1-3：靜態閱讀，沒有量；**UNVERIFIED**。
- iPhone／iPad 實機、iOS UI 測試：**UNVERIFIED**（照派工單不跑 iOS workflow）。

## 四、下一步

- L1-1 交給規劃，派人修（公車工具／BUGHUNT_BUILD 那條線）。
- L1-2、L1-3 記著，有玩家回報再處理。
- 審查 L2（#1551–#1578）由另一個 session 做，報告另寫一份。
