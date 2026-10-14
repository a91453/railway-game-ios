# 交接：PR #526–#626 的審查與修正

Session：https://claude.ai/code/session_01JXRA49xoPT4VypY1gTwWy2（2026-10-14），由派工 session_01AaAj4wvJMxJQuLWAoYu6S8 派出。從 `main` bd44ae21（#620 的合併）開始。#401–#525 由 session_01CcVg86LCLZLWsgf43HtG5D 審查（[`PR401_525_REVIEW_HANDOFF.md`](PR401_525_REVIEW_HANDOFF.md)）。

- 存檔版本、ARCHITECTURE 決策編號、golden schema 都沒有用到。
- GoldenScenarios、ReplayFixtures、SaveFixtures 的期望值都沒有改。

做法：

- 七個唯讀審查 agent 分組讀各 PR 的合併 diff：
  - GameCore 運轉（寫實運轉、機廠、區間閉塞）；
  - GameCore 規則（彎道限速、車站商業、班次紀錄、假日）；
  - 存檔與遷移；
  - 介面兩組；
  - CI 與測試腳本。
- 另一個 agent 讀 `main` 的 CI 紀錄，一個讀 #231。
- 每個發現我自己讀程式確認，有一項判定為照設計（第五節最後）。
- GameCore 與 GamePresentation 的修正都先寫測試，確認修正前會失敗。

開工時 #231 有凍結（#1188，18:39，合併 session 轉達作者）：#622、#623、#624、高鐵存檔 61（#627）、trip-log-off 合完之前不開新工作。派工 session 確認先做唯讀審查與本機測試；登記、推送、開 PR 等它通知。

## 一、合併狀態

範圍 #526–#626 共 101 個號碼：

| 狀態 | 數量 | 號碼 |
| --- | --- | --- |
| 已合併 | 94 | #526–#589、#591–#609、#611–#621 |
| 關閉沒合併 | 1 | #590 |
| 不是 PR | 1 | #610（Codex 連線測試的 issue） |
| 還開著 | 5 | #622–#626 |

- 每個已合併 PR 的 head commit 都用 `git merge-base --is-ancestor` 確認過在 `main` 上（先 `git fetch --unshallow`）。
- #590（PLAYER_FEEDBACK：61.1 從 b12394a 建置）沒合併，被 #592 取代：61.1 實際從 34bd32e 發出，`docs/research/PLAYER_FEEDBACK.md` 由 7832a30e 寫成 34bd32e。沒有遺漏。
- 還開著、不在範圍內的：
  - #622：內容目錄，決策 225；
  - #623：圖層測試等暫停鍵定位；
  - #624：#603 的開局取景修正；
  - #625：高鐵示範機廠第三段；
  - #626：iPhone 左欄。
- 範圍外但相關：#627（高鐵機廠存檔 61），見第六節。

## 二、`main` 的 CI 紅燈與根因（2026-10-13 18:45 – 2026-10-14 約 18:50 UTC）

範圍：#524（0a855c3）之後，到 #620（bd44ae2）為止在 `main` 上開的 run。資料來源：

- 各 run 與失敗 job 的 log；
- 修正 PR 的說明；
- #231 的 #1180（UI 測試 session 的分析）。

### 次數

| Workflow | run 數 | 成功 | 失敗 | 取消 | 備註 |
| --- | --- | --- | --- | --- | --- |
| `ci.yml`（push；範圍內沒有手動 run） | 95 | 62 | **0** | 32 | 另 1 個在跑：38615317464（bd44ae2）。取消的都是 concurrency 換掉的 push run。dfeade5（#600）的兩個 run 都被換掉 |
| `ios-build.yml` 完整 lane（由 ios-full-lane.yml 啟動） | 4 | **0** | **3** | 1 | 38458089903 取消；38521818299、38548848760、38599636375 紅 |
| `ios-build.yml` 完整 lane（session 手動開，沒有 `only_testing`） | 4 | 4 | 0 | 0 | 38491272700（#557）、38524240535（#558）、38559298780（#580）、38571794878（#591） |
| `ios-build.yml` 夜間 `schedule` | 1 | 0 | **1** | 0 | 38479608720（84618e3，#549） |
| `ios-build.yml` 手動 `only_testing`（在 `main` 上） | 1 | 1 | 0 | 0 | 38476430567 |
| `ios-full-lane.yml`（啟動器本身） | 67 | 67 | 0 | 0 | push 64、schedule 3；只有 4 次真的啟動，其餘因三小時間隔跳過 |
| `release-archive.yml` 夜間 | 1 | 1 | 0 | 0 | 38482306225（2c02ab1），10-13 23:07Z |

範圍外：`testflight.yml` 2 次都綠（38486471876 在 a272c69、38544627996 在 34bd32e），是作者發的版本。

失敗的 job 全部是 `Xcode build (iOS Simulator)` 的 `UI smoke tests (English and Traditional Chinese)`，也就是 iPhone 的 UI 測試。Linux CI、App 編譯、專案漂移檢查、在地化檢查、iPad 教學測試在範圍內都沒有紅。紅過的測試都不在 PR 閘門名單裡，所以 PR run 抓不到。

### 失敗清單

| 合併（run） | 失敗 | 根因 | 現況 |
| --- | --- | --- | --- |
| #529 之後（81f3d4f；38458089903，**取消**） | `MapInteractionTests.testZoomButtonsRemainUsableWithoutPinching`：`:271` 「64 points per 16 m is the maximum zoom」；之後 UI 步驟撞到 40 分鐘上限，job 在 60 分鐘被取消 | 縮放是測試的問題：慢的 Simulator 丟了那一下點擊，錄影裡點擊前後的縮放一樣。取消是完整 lane 太長 | #545 已修（沒到最大倍率就再點一次；UI 步驟上限 60 分鐘）。#550 把兩個選單測試合成一次啟動 |
| #549（84618e3；夜間 38479608720） | `MapInteractionTests.testTheStatusPillsButtonsAreTouchedBeyondTheirIcons`：`:845` 「A tap 1 point above the drawn pause button pauses the game」 | 第二次紅（上一段 4e7b694 第一次）。點擊在觸控範圍內卻沒被當成按下。判定為測試問題：Simulator 丟點擊，或橫拿時上緣吞掉觸控 | #557 已修（先等定位，5 秒內沒暫停再點一次）。之後的完整 lane 沒有再紅 |
| #559（cc4c8df；38521818299） | `SettingsUITests.testTheCityPreviewLoadsItsPageAndCloses`：`:86` 「Close did not close the 3D city preview」 | App 的問題，偶發，之前就有。#569 試修沒修好 | 見下一列 |
| #556（506d67d；38548848760） | 同上 | 觸控按下 45 ms 後被系統取消，Button 和 TapGesture 都不觸發 | #582 已修（手指按下就關）。之後三輪都綠 |
| #603（7eb3892；38599636375，最新一次） | `MapInteractionTests` 三支：`:114` `testDemoMapOpensOnItsNetwork`（畫面中央是 East 不是 Central）；`:167` `testHoldingAStationTracesItsBusiestTrips`；`:537` `testMapLayersSheetTogglesAndDismisses` | 前兩支是 #603 造成的 App 問題：開局重新取景用到版面還在移動時量的框，鏡頭拉遠，路網縮到左上角。#603 分支上的手動 run 一紅一綠，所以合併時沒擋下。第三支是測試競態：HUD 還沒排好就點暫停，點落到地圖上 | **未合併**：#624 修 App（它的手動 run 38611568341 紅在 `testSwitchingFollowTargetWhilePausedCentersTheCamera`，38615552456 還在跑）；#623 修測試（`only_testing` 38610911320 綠） |

### 目前狀態（2026-10-14 約 18:50 UTC，`main` = bd44ae2，#620）

- `ci.yml`：最新完成的 38615232362（6e18bcf，#611）**綠**。範圍內沒有失敗。
- 完整 lane：最新一次 38599636375（7eb3892，#603）**紅**。
  - 修正在 #624 與 #623，都還沒合併。
  - 最後一次綠的是 38571794878（b28a81e，#591，13:26 手動）。
  - #604–#621 還沒經過完整 lane。
- `release-archive.yml` 夜間：38482306225 **綠**。

## 三、修的 bug（GameCore 與 GamePresentation 的每一項都先寫了測試，確認修正前會失敗）

分兩個 PR：

- `claude/pr526-626-review-core`：GameCore；
- `claude/pr526-626-review-presentation`：其餘，加上這份文件。

### GameCore（`claude/pr526-626-review-core`）

1. **存檔裡班次紀錄的票款或人數很大，讀進來之後遊戲當掉**（#614，決策 223，`TrainTrip.isValid`）：
   - 讀檔只檢查不是負數。
   - 下一批乘客上車時，`creditTrip` 用一般的 `+` 加總，溢位後 trap。
   - 現在超過遊戲自己的上限（`maximumHourly`）就拒絕讀檔。
   - 測試：`TrainTripLogTests.testABrokenLogIsRefused` 新增「a fare beyond the cap」「riders beyond the cap」兩例。
2. **存檔裡機廠的「重量×小時」很大，讀進來之後遊戲當掉**（#548，決策 209，`CompanyAccounts` 的 `depotHours`）：
   - 讀檔只檢查大於 0。下一個整點有車在機廠時 `+=` 溢位。
   - 現在超過上限就拒絕讀檔。累加時也封頂，所以遊戲自己寫的檔一定讀得回來；一般遊戲碰不到上限，結果不變。
   - 測試：`DepotTests.testDepotHoursBeyondTheCapAreRefused`。
3. **台灣的假日讓乘客計畫變慢一倍以上**（#551，決策 211，效能退步）：
   - 台灣假日改成每年依規則算之後，每次問「今天是不是假日」都要算一整年的放假日，約 21 µs。
   - 乘客計畫每一對車站都問一次：60 站的計畫從 0.09 s 變成 0.21 s，而且隨站數平方成長。
   - 新遊戲預設就是台灣的假日。
   - 現在每個計畫只問一次，結果逐位元不變。
   - 測試：`HolidayTests.testAPlanAsksForTodaysHolidayOnce`，比較台灣和中國假日的計畫時間，台灣不得超過 1.5 倍。修正前是 2.26 倍，失敗。
4. **開往機廠空位的列車不靠左行駛**（#611，決策 221 × 決策 202）：
   - #611 讓進機廠的列車先找空的股道。用的是「路線指定月台」那個搜尋，那個搜尋刻意不靠左。
   - 結果複線上可能走右邊、逆向，就是 TestFlight 56.1 的問題，影響所有機廠，包括決策 209 的。
   - 現在進機廠時靠左。搜尋快取的鍵也加上「靠不靠左」。
   - 測試：`KeepLeftTests.testTheWayIntoADepotKeepsLeft`：修正前走北線（e6, e4, e2, e1），現在走南線。
5. **剛出庫的列車在首班前被送回機廠，首班誤點**（#548，決策 209，`trainEnteringDepot`）：
   - 出庫的判斷看「出庫時間之後」要幾列車。入庫的判斷卻看「現在」要幾列車。
   - 列車到首站時，可能比首班早一到兩分鐘，那時營運時段還沒開始，要的列車是 0，所以它被當成多出來的車送回機廠。
   - 結果首班 06:05 才開，不是 06:00，中間多跑兩趟空車。
   - 現在入庫時也看兩分鐘後要幾列車（`waitingLead`）。醒來時間也一併算進去，所以批次快轉與逐分鐘仍然一致。
   - 測試：`DepotTests.testATrainOutOfTheDepotWaitsForTheFirstTrip`：最高速 3、Alpha 在第 4 或第 7 欄，修正前 06:00 被送回機廠。
6. **照班次跑的路線進出機廠，沒有記進班次紀錄**（#611 × #614）：
   - #611 的出入庫沒有開一筆班次紀錄。
   - 結果營運概覽、列車運用表、運行圖都缺這些空車回送。上一趟最後一站的出發時間，也被記成去機廠的時間。
   - 測試：`RunDepotTests.testTheRunsIntoAndOutOfTheDepotsAreLogged`。
7. **繞路的誤點列車不追時間**（#556 × #526，決策 212 × 決策 207，`rerouted`）：
   - 寫實運轉下，誤點的列車本來會用「離表定到站還剩的秒數」跑，以追回時間。
   - 但開著區間閉塞、繞過停著的車走另一條路時，仍用時刻表的整段秒數，所以一直誤點，準點率也算得不一致。
   - 新遊戲預設兩個都開。
   - 現在和原路一樣算。
   - 測試：`RealisticOperationTests.testALateTrainOnAnotherWayMakesUpItsMarginToo`：修正前 58 秒，應為 44 秒。
8. **註解寫錯存檔版本**（`ServiceRun.swift`：彎道限速是存檔 58，不是 57）。只改註解，沒有測試。

golden 與 replay：

- 第 1、2 項只影響讀檔驗證。
- 第 3 項結果逐位元不變。
- 第 4–6 項只在有機廠時有作用，沒有一個 golden、replay 有機廠（決策 221 第 4 點）。
- 第 7 項只在寫實運轉、區間閉塞都開，而且繞路時有作用。
- `GoldenScenarioTests`、`ReplayFixtureTests`、`SavedGameTests` 在本機都通過，沒有值改變。

### GamePresentation 與 App（`claude/pr526-626-review-presentation`）

9. **路線照班距跑時，列車卡的「加開到 N 列」按了沒用**（#565，`lineUnusedTrains`）：
   - 用「每幾分一班」配車（`LineStaffing`）會在三個時段都設目標班距。設了目標班距的時段，列車數由班距決定，不看設定的列數。
   - 按鈕改的是列數，所以什麼都不變，指派訊息卻叫玩家去按它。
   - 現在路線有目標班距時不提供這個按鈕，改顯示「受班距或軌道限制」。
   - 測試：`LineDispatchTextTests.testALineRunToAHeadwayIsNotOfferedToRunMoreByTheCounts`。
10. **「不在首站」的提示叫玩家「開啟彈性發車」，可是沒有任何開關**（#565，CLAUDE.md 的玩家文字規則）：
    - 彈性發車只在新遊戲（開）和劇本、挑戰、教學、示範（關）時設定。
    - 這個提示只會在關著時出現，所以每次都指向玩家找不到的東西。
    - 現在只說「派它到首站」。
    - 測試：`LineDispatchTextTests.testATrainAwayFromTheFirstStopIsToldToBeSentThere`（改期望值，加英文）。
11. **路線上有一列從沒放上軌道的車時，「減少列車」整個失敗**（#538，`GameSession.removeTrains`）：
    - 等車的列車退出後要收回機廠（`unplaceTrain`）。從沒放上軌道的車會丟 `trainNotPlaced`，整個指令失敗，這條路線就減不了車。
    - `assignTrain` 不要求列車已放上軌道，買了沒放的車可以指派。
    - 測試：`LineTrainCountTests.testFewerTrainsTakeOffAnUnplacedTrain`。
12. **兩個方向等的人一樣多時，「為何在等」說反了方向**（#540，決策 210，`stationWaitReason`）：
    - 文件寫同數時取去程（往最後一站），比較式卻讓回程勝出。
    - 測試：`MapProblemsTests.testOnATieTheWayOutIsNamed`，修正前說「往 Alpha」。
13. **停在彎道上、沒有營運的列車也顯示限速**（#607，`curveLimit(of:)`）：
    - 先看所在的邊有沒有限速，才看列車有沒有在營運，和文件相反。
    - 列車卡會對停著的車寫「彎道限速 60 km/h」。
    - 測試：`CurveSpeedTextTests.testATrainRunningNoServiceHasNoReading`。
14. **高速時月台忙碌度一直寫「最近 36 分」**（#602，`PlatformUse`）：
    - 每一步取樣一次。高速時一步跨好幾分鐘，取樣數少於經過的分鐘數，一小時後仍寫「（最近 36 分）」。
    - 現在寫取樣涵蓋的分鐘數。百分比照舊用取樣算。
    - 測試：`StationOperationsTests.testTheMinutesNamedAreThoseSpannedNotTheSamples`，30 分鐘兩次取樣，修正前寫 2 分。
15. **描線完成的訊息寫「edges」**（#558，玩家文字規則：內部術語）：
    - 英文改成「pieces of track」，中文本來就寫「段」。
    - 測試：`RealRailwayTracingTests.testTheTracedMessageSaysHowFarAndForHowMuch`。
16. **蓋或升級車站商店錢不夠時，訊息沒說是什麼動作**（#596 × #606，`PlayerCommand.actionText`）：
    - #596 讓「餘額不足」說出動作與整個價錢。#606 後來加的商店兩個指令沒有列進去。
    - 測試：`InsufficientFundsTests.testTheShopsAreNamedInTheRefusal`。
17. **車種型錄寫「1 cars」**（#608，SwiftUI `RollingStockCatalogView`）：
    - 現在一節寫「1 car」。
    - **UNVERIFIED LOCALLY**：App 的 SwiftUI 檔，Linux 不能建置，要看 PR 的 iOS 建置。沒有測試。
18. **只改 TestFlight 說明的 PR 也跑 macOS 建置與 UI 測試**（#592，CI）：
    - `.github/testflight-whats-new.md` 不在頂層，`"*.md"` 管不到。所以只改說明的 PR 跑 iPhone UI 閘門，合併後還可能啟動完整 lane。
    - 現在把它加進三個清單：`ios-build.yml` 的 `paths-ignore`、patch-id 的排除清單，以及 `ios-full-lane.yml` 的 `paths-ignore`。
    - 沒有測試，要看 CI。

## 四、轉給其他 session

- **#603 留下的兩件事**：已用 `send_message` 告訴 #624 的 session（session_015sjfVDP73n28zRE98QcyFy），只是資訊，不要求改 #624 的範圍。內容見第五節第 B1、B2 項。
- **關掉路線帳後，班次紀錄沒清掉**（#614，`setLineAccounts(false)`）：
  - 這正是 trip-log-off（session_016VRigrvN5QBAEFrxwLKxdd，#231 凍結清單上的一項）的工作，這裡不修。
  - 影響：再打開時，舊的「行駛中」那一趟會被接上後來無關的停站。

## 五、沒修，需要作者決定或只回報

每項寫明為什麼不在這裡修。依作者 2026-10-14 的規則，需要選擇的由這裡定案；這一輪沒有需要選的，都是「之後」或「回報」。

### GameCore

- **G3 排定交會的「改停站排得下嗎」仍用不限速的曲線**（#588，`ScheduledTraffic.swift` 的 `trafficStopBuildable`、`applyTrafficAnchor`）：
  - 決策 217 第 8 項自己寫明「只有距離沒有路徑，照舊用 `RunningCurve`（之後）」。
  - 影響：開限速時，預測的交會時刻和實際行駛可能差幾秒，排得下的待避可能其實排不下。
  - 要給這兩個函式路徑，屬於設計範圍，不在這裡修。
- **G5 沒有路線帳時，車站商店的營收用了隔天的假日與天氣**（#595，`stationCommercePeople`）：
  - 午夜結算 D 日時 `clock.now` 已是 D+1，`scaledTrips` 讀的是 D+1 的假日、天氣與活動。
  - 要改成依日算，得讓這三個乘數都能指定日期。活動在午夜已先換成新的一天（`startDemandEventDay` 在結算之前），所以只改假日與天氣會留下不一致。
  - 只影響關掉路線帳的世界，金額差一天的假日加成。
  - agent 說「閒置快轉時結果不同」，查過不成立：有假日或活動時，快轉會停在午夜（`dayWake`），午夜那一分鐘走一般流程。
- **G8 班次紀錄每次上車都線性掃一遍**（#614，`creditTrip` 的 `lastIndex`、開新一趟時的 `dropTrips`）：200 列車約 1.6 萬筆時，每次上車 O(N)。要量過再決定要不要加索引。
- **G9 兩個假日落在同一個週末日，會各補一天**（#551，`TaiwanHolidays`）：只在中秋與另一個假日同日又是週末時發生。遊戲自己的週曆上 2042、2061、2080 年都落在平日，所以目前碰不到。
- **F3 存檔 59／60／61 的號碼**：
  - #614（60）先合併，#611 帶著 59 後合併，`currentVersion` 停在 60，多機廠的 `"depots"` 沒有版本保護。
  - #627（session_01YNBmv76sfS8gJUnyRKEqHV）正在升到 61，這裡不動。
  - 待辦：`SaveFixtures/README.md:213` 那句「Version 59 … which this build does not have」已過時；#611 的 PR 說明寫「存檔 61」，與合併的內容（59）不符。交給 #627 一併處理。
- **F5 新欄位明寫 `null`（或三個開關寫 `false`）也讀得進來**（存檔 53–60）：
  - 新欄位都用 `decodeIfPresent`。
  - 和舊欄位「明寫 null 拒絕」的規則不一致；手寫的檔讀寫後不會逐位元相同。不會當掉。
- **F6 班次紀錄的車站、路線沒有檢查是否存在**（#614）：畫面都用 optional 查，目前不會出錯。
- **C3 `ServiceRepeatingPropertyTests` 拆成兩半後，「每個 case 都有跑」的檢查形同虛設**（#573，`ServicePropertyTests.swift:176`）：
  - 跳過的 case 也算進 `ran`。
  - 事件下限的檢查（減半）仍抓得到整半沒跑。只是檢查變弱，屬於測試衛生。

### 介面與 App

- **B1 #603 讓選取車站時常常重新置中**（`MapView.swift` 的 `keepSelectionClear` 改用 `framing`，含左下、右下角框）：
  - 手機橫拿、圖例開著時，靠角落的已選車站每次開關細節卡都重新置中。可用區很小時，`clearArea` 在一個軸退回整個畫面。
  - #624 沒有處理這件事。`MapView.swift` 也在 #626（美術 session，第 3 步會動右欄）的範圍內，所以只回報。
- **B2 #603 的站名改畫在列車之後**：現在蓋在鋪軌預覽、軌段編號之上，夜間也不變暗。屬於視覺取捨，交給 #603 的 session 或美術 session。
- **B3 #603 每次重繪算兩次候車數**（`MapView` 283、329 行）；`MapCanvas` 不畫站名了，卻仍比較候車數，所以照樣重繪。效能，小。
- **U4 車隊總覽每一列每次重繪都重新規劃等車的列車**（#565，`PerformanceText` 呼叫 `lineDispatchHoldText` → `readyTrip`，沒有快取）：
  - 大路網、很多列車在等時，打開總覽每一幀都要找一次路。
  - 要加每個 tick 的快取，屬於設計，之後量過再做。
- **U7 描線的判斷在 SwiftUI body 裡做**（#558）：
  - `canTraceRealRailway` 第一次會建整個 `RealRailwayTraces`。
  - 拖曳時 `networkTracedWay` 每次重繪都跑一次沒有快取的最短路徑。
  - 效能，App 端，不能在 Linux 量。
- **U9 路網明信片每輸入一個字就重繪一張 1200×1500 的圖**（#566、#597，`PostcardView`）：打公司名稱時會卡；分享的圖與畫面上的預覽也可能不同。App 端。
- **B6 月台使用紀錄不管有沒有打開車站頁都在記**（#602，`PlatformUse.record`，每分鐘 O(列車 × 月台)）：效能，小。
- **B5 自己有來回時刻表（A→B→A）的列車，目的地寫錯**：
  - 涉及 #602 的月台列、#587 的列車卡、#615 的 `plannedTrips`。它們用 `timetable.last`，所以寫「A → A」或「往 A」。`DepartureBoard` 已有正確的 `destination(after:)`。
  - 路線的列車不受影響，只有自己有時刻表的列車。要三處一起改，留給下一輪。
- **B8 即將進站看板**（#587，`DepartureBoard.markingFollowers`）：
  - 前面一列只通過不停的誤點車，也會讓後車標「前車誤點」。
  - `.lateBehind` 的文字沒有寫自己的分鐘數。
  - 列車卡在兩趟之間顯示上一趟的時間（「300 分前出發」）。
  - 都是小事。
- **B10 跨午夜還在跑的那一趟不在今天的運用表裡**（#615，`TrainRoster` 用 `sentOut` 篩當天）：行駛中的列車那一列可能是空的。小。
- **B7 暫停中打開無限資金，舊的「餘額不足」橫幅要等時鐘走才收**（#596，`retireCoveredShortfall` 只在 `finish` 呼叫）。小。
- **U8 機廠**（#559）：
  - `trainsInDepot` 算的是停在任何機廠的車，不只自己路線的機廠。
  - S 形岔線蓋不出來時，`DepotYard` 回報「點軌道的端點」，原因不對。
  - 都是小事。
- **U3 「路線現在只開 N 列（受班距或軌道限制）」**（#565）：
  - 第 9 項之後，這句在有目標班距時出現，說法正確。
  - 但在「玩家把現在這個時段的列數設低」時，原因寫錯；跟隨列還會出現「尚未發車：列車已暫停：…」兩層前綴。
  - 文字小事。
- **U10 教學收合膠囊的「跳過這一步」在矮的畫面只有 36 pt 高**（#562），低於 44 pt。版面，App 端，UNVERIFIED。
- **U11 色盲配色的說明三句，有一句在講怎麼挑顏色**（#567），略超過「一兩句、只講效果」的規則。
- **玩家文字還違反規則的地方**（#599 之後仍在）：
  - 「Node #N／節點 #N」「Track #N／軌段 #N」：`DisplayText.swift:142、151`，經由鋪軌訊息、`RoutePreview` 顯示給玩家。
  - 錯誤訊息帶原始 ID：「There is no train #…」「Station #… already has a freight yard」。
  - 「node」「新節點」，以及「physical path／軌段與月台」。
  - 兩個沒在用的 xcstrings key。
  - 改這些會動到 UI 測試找的字（`ToolbarSmokeTests.swift:94、103、105`，`RealWorldMapUITests.swift:251`），而且範圍大，需要一個專門的 PR 連測試一起改。
- **本來就有、不算這些 PR 的**：描線、機廠岔線的預覽與訊息用「餘額減少多少」當價錢，無限資金下寫「$0」。一般鋪軌、待避線、月台、渡線工具一向如此。

### CI 與測試腳本

- **C1 `campaigns-6`、`campaigns-12` 接近 20 分鐘上限**（#572、#573）：
  - PR 自己估 850 s、800 s，再加約 5 分鐘建置，慢的 runner 可能逾時，讓 `main` 的 push run 無故紅。
  - 分片時間屬於 CI 的工作，要看實際時間再搬類別。
- **C2 分片權重沒算進 fixture 帶進來的 GameCore campaign**（#568，`CLASS_WEIGHTS`）：例如 `GoldenScenarioTests` 約 281 s 只算 1。不會漏跑測試，只是某一部分 job 會跑比較久。
- **C5 `.github/testflight-whats-new.md` 寫死「0.5.0 (62.1)」**（#592）：發版號碼不同時說明會錯。發版是作者的事，只回報。
- **C6 縮放測試的第二次點擊可能蓋掉「一步放大一倍」的退步**（#545）：建議先確認第一次有變再補點。是 UI 測試，這裡不改。
- **C8 iOS 建置 job 的上限由 60 改 80 分鐘，PR 也一樣**（#545）：卡住的 PR 建置會多佔 macOS runner 20 分鐘。
- 完整 lane 的三支紅：由 #623、#624 修，見第二節。

### 審查後判定照設計（不算 bug）

- **照真實時刻表跑的路線，誤點的列車不減速過彎**（#588，`run(of:length:scheduled:)`）：
  - 兩個 agent 都報成 bug。
  - 決策 217「真實時刻表不被拖慢」寫明：真實班次的路線，在限速下排不下就不用限速；玩家自己排點的路線才沒有這條例外，所以真實路線的誤點車會為了追時間不減速。
  - 程式和決策一致，不改。

## 六、存檔遷移檢查（53–60）

| 版本 | PR | 新欄位 | 缺欄位時 | 只在有值時寫 | 讀檔驗證 | fixture 與測試 |
| --- | --- | --- | --- | --- | --- | --- |
| 53 | #526 | 世界 `realisticOperation`；路線 `dwellSeconds`；`LineTally` 的 `trips`、`lateTrips` | false；nil（60 s）；0 | 是 | 停站秒數在範圍內；`lateTrips <= trips` | `v53-realistic-operation.json`，`RealisticOperationTests.testVersionFiftyThreeKeepsRealisticOperation` |
| 54 | #548 | 車站 `depot`；路線 `depot`；帳 `depotHours` | false／無／[] | 是 | `"depot": false` 拒絕；路線的機廠必須是機廠站；`depotHours` **原本沒有上限**（第三節第 2 項已修） | `v54-depot.json`，`DepotTests.testVersionFiftyFourKeepsTheDepot` |
| 55 | #567 | 路線 `code` | nil | 是 | 1–3 個 A–Z／0–9 | `v55-line-code.json`，`RenameAndColourTests.testVersionFiftyFiveKeepsALinesCode` |
| 56 | #556 | 世界 `blockSections` | false | 是 | Bool | `v56-block-sections.json`，`BlockSectionsTests.testVersionFiftySixKeepsBlockSections` |
| 57 | #595 | 車站 `commerce`；`transferred`；`dailyStationCommerce` | nil；0 | 是 | 等級 1–3；機廠不能有商店；`transferred` 在 0…下車數之間 | `v57-station-commerce.json`，`StationCommerceTests.testVersionFiftySevenKeepsStationCommerce` |
| 58 | #588 | 世界 `curveSpeedLimits`；行駛的 `limits` | false；[] | 是 | 限速在行駛範圍內、`start < end`、速度 ≥ 1 | `v58-curve-speed-limits.json`，`CurveSpeedRunTests.testVersionFiftyEightKeepsCurveSpeedLimits` |
| 59 | #611 | 路線 `depots`（兩個以上）；照班次跑的路線可有機廠 | 舊的 `"depot"` 讀成一個 | 是（一個仍寫 `"depot"`） | 兩個鍵不能並存、不重複、至少兩個 | `v59-run-depots.json`，`RunDepotTests.testVersionFiftyNineKeepsTheDepots` |
| 60 | #614 | 世界 `tripLog` | [] | 是 | 停站依時間、首站是起站、列車 ID 已發出；票款與人數**原本沒有上限**（第三節第 1 項已修） | `v60-trip-log.json`，`TrainTripLogTests.testVersionSixtyKeepsTheTripLog` |

遷移步驟：

- 52→53 到 59→60 都只是註解（`SavedGame.swift:461-471`），這是對的：每個新欄位缺的時候就是舊的行為。
- `SavedGameTests.testEveryCommittedSaveStillLoads` 讀、存、往前跑每一個 fixture，所以 52 以前的存檔也在新程式上跑過。

新遊戲的預設：

- 寫實運轉、區間閉塞、彎道限速只在 `GamePresentation/NewGame.swift` 打開。
- GameCore 缺欄位時讀成關，所以舊存檔維持關。正確。

fixture 與期望值：

- **fixture**：範圍內 `SaveFixtures/*.json` 只有新增，沒有修改。`v55-block-sections` 改成 `v56-block-sections`、`v56-line-code` 改成 `v55-line-code`，都是合併前在各自分支上改名，舊名字從沒進過 `main`。每個檔的 `saveVersion` 與檔名相符。
- **ReplayFixtures**：沒有改。
- **GoldenScenarios**：
  - `holidays.json`（#551，決策 211）改了台灣假日的區間與觀測日，需求值（1000、1050、1025）不變。PR 說明逐值寫了理由，agent 也逐一重算過。
  - `station-commerce.json`（#595，schema 74）是新的。
  - #526 沒改期望值。
- **指令日誌**：
  - 範圍內新增的 `setLineCode`、`setStationDepot`、`setLineDepot`、三個商店指令、`buildDepotYard` 都是 `PlayerCommand.Edit`，`CommandEditTests.testEveryEditKeepsItsFormThroughItsFile` 都有來回測。
  - `setLineDepots`、`setLineDwell` 與四個開關沒有 UI 呼叫（開關只在建立世界時設，記在日誌的起始世界裡）。等哪個面板開放它們，要一起加 `Edit` 與測試。

## 七、審查過、沒有問題（摘要）

- **GameCore**：
  - #530（每一級的紀念品店資產；首班讓備用車）。
  - #571（`anyTrainMayBeSentOut` 和逐列的判斷結果相同）。
  - #589、#542。
  - #556（除第三節第 7 項）、#611（除第 4、6 項）、#526（除第 7 項）。
  - #584、#531、#541、#546、#595（除 G5）、#614（除第 1 項與 G8）。
- **上一輪轉來的「關閉彈性發車時，備用車被移開後發不出去」**：#548 已修。`resolveDeadlock` 設 `isStandingAside`，`readyTrip` 讓它空車回到第一站，環狀線也一樣。#589 刻意讓照班次跑的路線不設這個旗標。
- **決定性、`Sendable`**：沒有發現問題。`Set` 只用來查詢；`ServiceRun` 的快取不進 `==` 與存檔。
- **介面**：
  - #527、#529、#532、#544、#547、#561、#569／#582、#579、#580。
  - #591、#593、#604、#605、#606、#609、#616、#617／#621、#618、#620。
  - 沒有繞過 `GameWorld` 指令的地方。
  - UI 測試用到的 accessibility identifier 都還在。
  - 新的在地化字串兩種語言都有。
- **CI 與文件**：
  - #528、#534、#550、#552、#557。
  - #574–#577、#583、#598、#600、#612、#619、#613。
  - 沒有新增 `testflight.yml` 的觸發，沒有洩漏秘密。
  - `swift-shards-selftest.sh` 本機通過。

## 八、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告，兩個分支都是。
  - 每個新測試都先在修正前跑過，確認失敗（第三節各項寫了修正前的結果）。
  - GameCore 分支修正後通過的類別：
    - `GoldenScenarioTests`、`ReplayFixtureTests`（1 項照設計略過）、`SavedGameTests`；
    - `HolidayTests`、`DepotTests`、`RunDepotTests`、`KeepLeftTests`、`TrainTripLogTests`；
    - `CurveSpeedRunTests`、`StationCommerceTests`、`RealisticOperationTests`、`BlockSectionsTests`、`LineRoutePreferenceTests`；
    - `DeadlockTests`、`IdleTrainDeadlockTests`；
    - GamePresentation 的 `DepotToolsTests`、`StationCommerceCardTests`、`CurveSpeedTextTests`、`LineLossFixesTests`、`CommandEditTests`、`RealisticOperationSessionTests`、`HighSpeedDemoTests`、`NewGameTests`。
  - 介面分支修正後通過的類別：
    - `LineDispatchTextTests`、`LineTrainCountTests`、`MapProblemsTests`、`CurveSpeedTextTests`、`StationOperationsTests`；
    - `RealRailwayTracingTests`、`InsufficientFundsTests`、`StationCommerceCardTests`；
    - `RouteEditingSessionTests`、`NewGameCampaignTests`、`BalanceReportTests`、`TutorialSessionTests`、`FlexDispatchTextTests`、`DepotToolsTests`、`TrainCardTests`。
- **UNVERIFIED LOCALLY — requires macOS/Xcode CI**：
  - `RollingStockCatalogView.swift`（第 17 項）；
  - `ios-build.yml`、`ios-full-lane.yml` 的清單（第 18 項）。
- 其餘分片交給 CI。

## 總表

| | 發現 | 修了 | 沒修 |
| --- | --- | --- | --- |
| GameCore（模擬、存檔、效能） | 17 | 8 | 9（G3、G5、G8、G9、F3、F5、F6、C3，以及轉給 trip-log-off 的一項） |
| 介面與 App | 25 | 9 | 16（B1–B3、B5–B8、B10、U3、U4、U7–U11、玩家文字） |
| CI 與測試腳本 | 6 | 1 | 5（C1、C2、C5、C6、C8） |
| **合計** | **48** | **18** | **30** |

另有 1 項經查證判定照設計（第五節最後），不計入。`main` 完整 lane 的 3 支紅由 #623、#624 處理，也不計入。
