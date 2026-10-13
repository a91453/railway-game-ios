# 交接：PR #401–#525 的審查與修正

Session：https://claude.ai/code/session_01CcVg86LCLZLWsgf43HtG5D（2026-10-13），由派工 session_01AaAj4wvJMxJQuLWAoYu6S8 派出。從 `main` 0a855c38 開始。範圍定在開工時 `main` 最新合併的 #525（#524 在它之後合併，但號碼最大的是 #525）。#319–#400 由 session_01P7tpgZrXZ3pW2rJZPGhyei 審查。存檔版本、ARCHITECTURE 決策編號、golden schema 都沒有用到；GoldenScenarios、ReplayFixtures、SaveFixtures 的期望值都沒有改。

做法：七個唯讀審查 agent 分組讀各 PR 的合併 diff（GameCore 模擬與經濟、存檔與效能、今天合併的 UI 兩組、指令日誌與存檔、#402–#434、#438–#496），一個讀 `main` 的 CI 紀錄。每個發現我自己讀程式確認；GameCore 與 GamePresentation 的修正都先寫測試，確認修正前會失敗。

## 一、合併狀態

- #401–#525 共 125 個號碼，123 個已合併。每個 head commit 都用 `git merge-base --is-ancestor` 確認過，都在 `main` 上（先 `git fetch --unshallow`）。
- 兩個沒合併：
  - #418（全程式碼依領域審查的第一個 PR）：修的兩項和先開的 #408（`removeStation` × 逐線帳）、#409（`sellTrain` × 車上的貨）重複，作者在 PR 上說明後關閉。其餘修正之後由 #420、#439、#441、#442、#445 送進 `main`。沒有遺漏。
  - #478（暫時用來檢查 Claude API key，標明 do not merge）。沒有內容要補。
- 開工時還開著、不在範圍內的：#526（寫實運轉，存檔 53）、#527（空狀態插圖）、#528（full lane 等待）、#529、#530（小 bug 一批）。
- 存檔 49→52 這段：50（#413 委託案）、51（#501 無限資金）、52（#507 靠左行駛）。每一版的遷移都是「缺的欄位讀成 nil／false」，編碼時只在有設定時才寫，所以舊世界編出來和以前逐位元相同；`SaveFixtures/v50-city-requests.json`、`v51-unlimited-funds.json`、`v52-keep-left.json` 都在，`SavedGameTests` 與各自的測試類別都讀。沒有發現問題。

## 二、`main` 的 CI 紅燈與根因（2026-10-12 03:48 – 2026-10-13 18:45 UTC）

範圍：#401（e30ce96，ci.yml run 建於 2026-10-12T03:48Z）到 #524（0a855c3，2026-10-13T18:44Z）之間在 `main` 上開的 run。根因取自各失敗 job 的 log（`gh api .../actions/jobs/<id>/logs`）與修正 PR 的說明。

### 次數

| Workflow | run 數 | 成功 | 失敗 | 取消 | 備註 |
| --- | --- | --- | --- | --- | --- |
| `ci.yml`（push；範圍內沒有手動 run） | 127 | 87 | **0** | 40 | 取消的都是 concurrency 換掉的 push run，下一次 push run 以上次成功的 head 為基準補測。#514（8bf6e50）在 `main` 上沒有任何 ci.yml run（API 查無），由下一個 run 補測 |
| `ios-build.yml` 完整 lane（`workflow_dispatch` 由 ios-full-lane.yml 啟動 15 次＋夜間 `schedule` 1 次） | 16 | 6 | **9** | 1 | 範圍內沒有 push run（push 觸發在 #372 之前就改由 ios-full-lane.yml 代啟） |
| `ios-build.yml` 手動「UI tests by hand」（`only_testing`） | 4 | 1 | 3 | 0 | 都是重現或驗證修正用 |
| `ios-full-lane.yml`（啟動器本身） | 107 | 107 | 0 | 0 | push 103、schedule 4 |
| `release-archive.yml` 夜間 | 1 | 1 | 0 | 0 | 2026-10-13 00:58（771c431） |

失敗的 job 全部是 `Xcode build (iOS Simulator)` 的 `UI smoke tests (English and Traditional Chinese)` 這一步，也就是 iPhone 的 UI 測試。App 編譯、專案漂移檢查、在地化檢查、iPad 教學測試、Linux CI 在範圍內都沒有紅過。

### 失敗清單

| 合併（run） | 失敗 | 根因 | 現況 |
| --- | --- | --- | --- |
| #391 之後（49de93f；完整 lane 38202914204，10-12 04:13） | `RealWorldMapUITests.testARealWorldGameStartsFromAPlaceAndIsSavedAsOne`、`StartSaveFlowSmokeTests.testAHouseBuiltOnABlankMapIsKeptBySavingAndContinuing`、`testCellsZonedByADragAreKeptBySavingAndContinuing`：`menu.backToStart` exists 但點不到（frame y=335, h=42） | 遊戲選單隨世界變長：#391 觀光加「觀光景點」、決策 183 委託案讓空白新遊戲也有「目標」，選單變八列，最後一列在手機橫放時落到點不到的地方。PR 閘門只跑示範地圖，所以沒抓到 | #423 已修（選單固定六列，其餘放進「更多」；兩個測試加進 PR 閘門） |
| #408（440736e；38211636581） | 同上三個 `menu.backToStart`；另加 `SettingsUITests.testTheCityPreviewLoadsItsPageAndCloses`：「Missing the 3D city preview」 | 選單同上。城市預覽：#402 在設定加了「地圖」一段，橫放時「試作」那一列在畫面外，`List` 不建出它，測試卻先等它出現才捲動 | 選單由 #423 修；城市預覽由 #427 修（拖到畫面中段、依框中心點擊；只改測試） |
| #429（73b4614；38249605095） | `TutorialUITests.testLargeTextTutorialNavigation`：「The tutorial card covers tool.select」 | #429 把細節卡片當成和控制項一樣重的面板；最大字體時教學卡片被擠到左下角蓋住「完成」。這個測試只在完整 lane 跑 | #434 已修（細節卡片改成 backdrop） |
| #449（06be5ab；38296188423） | `StartSaveFlowSmokeTests.testBackToStartWorksWhileTheClockRuns`：`menu.saveGame` 「Failed to determine hittability… Activation point invalid」 | 測試的問題：HUD 的 `ViewThatFits` 有沒放上畫面的副本，對沒有 frame 的副本問 `isHittable` 時 XCTest 直接判失敗（600× 負載重、一次快照約 9 秒）。錄影顯示選單沒有被重建 | #458 已修（只對畫面上的元素問 `isHittable`） |
| #463（46bf24b；夜間 38328152222） | `TutorialJourneyUITests.testTheWholeTutorialOnAPhoneOnItsSide`：找不到 `tutorial.unfold`（`TutorialJourneyUITests.swift:261`） | 競態：卡片在 `shownStep()` 讀 `folded.exists` 之後、讀 `.label` 之前收起或打開，查詢失敗。同一問題在 iPad 的 PR run 38326058322 也出現過 | #461 已修（commit 5797b2b「Read the tutorial's title from a snapshot」，標題與收合膠囊各從一次快照讀）；之後的完整 lane（38333032914，#469）綠 |
| #473（cb279f6；38345123226） | `RealWorldMapUITests.testTheRealWorldMapIsReachedWithTheLargestText`：「start.realWorld cannot be scrolled to」；`LineRoutePreferenceUITests.testALineLegCanSelectAPhysicalPlatform`：`Failed to launch … Timed out while launching` | 前者：#473 新增的 `scrollUntilShown` 用 swipe，每次甩過頭，20 次上下交替都沒落在可見帶（手動 run 38349073755 在 3197f71 重現，不是偶發）。後者：Simulator 啟動 App 逾時，測試本體沒跑，重跑通過 | #490 已修（改用停住再放開的拖曳、每次 30%、40 次）。啟動逾時看成偶發，沒改 |
| #480（3197f71；手動 38349073755） | `testTheRealWorldMapIsReachedWithTheLargestText` 同上 | 同上（#490 用來確認不是偶發的重現 run） | #490 已修 |
| #489（2567a58；38362099969） | `StartSaveFlowSmokeTests.testThePerformanceMenuStaysStillAndChoosesWhileTheClockRuns`：`train.performance` 點不到（frame h=15.7）；`MapInteractionTests.testPlatformModeKeepsItsStatusAndActionInTheCard`：「A tap on the track must place a platform」 | 運轉方式選單：App 只有一行 footnote 字可點（15.7 pt），加上 #485 讓列車卡多一行，測試每次拖 160 pt 讓選單跳到固定標題底下。月台：月台其實放好了，測試確認後又等一次，那輪查一次元素要 4 秒而超時 | #509 已修（選單觸控區至少 44 pt；測試改沿卷動區左緣短拖；月台只問一次） |
| #501（b3ba449；手動 38369495213） | `testThePerformanceMenuStaysStillAndChoosesWhileTheClockRuns` 同上 | 同上（重現 run；`testPlatformMode…` 在這輪通過） | #509 已修 |
| #505（c41c9a1；38383002402）；#513（c89c724；38404565525 取消，紅的是同三個） | `LineRoutePreferenceUITests.testALineLegCanSelectAPhysicalPlatform`、`testTheAdvancedSwitchFoldsTheTracksAndTheServiceDay`（`ToolbarSmokeTests.swift:139` 等待逾時）；`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`（找不到「Problem」橫幅） | #505：一次性「軌段與進路」提示卡（alert）在 `-ui-testing` 下每次都跳出蓋住畫面；「Edge #N」改名「Track #N」、路線選單文字改了，測試還等舊字。#499：側面板縮成 270 pt，測試點在寬度 95% 落在列的右邊距，沒點到「進階」開關 | #523 已修（DEBUG＋`-ui-testing` 預設看過提示卡；測試改字、改從右緣往內 42 pt 點） |
| #522（4e7b694；38430642081，最新一次完整 lane） | 上一列的三個（#523 在這輪開始後 16:58 才合併）；另加 `MapInteractionTests.testTheStatusPillsButtonsAreTouchedBeyondTheirIcons`：「A tap 1 point above the drawn pause button pauses the game」 | 三個同上。狀態膠囊：只紅這一次，在 c41c9a1、c89c724 的完整 lane 與 710716c 的手動 run（38441429093）都綠，看成偶發 | 三個由 #523 修。狀態膠囊**沒修**（偶發，未查根因） |
| #523（710716c；手動 38441429093） | `LineRoutePreferenceUITests.testALineLegCanSelectAPhysicalPlatform`：`setAdvanced` 等「進階」開關的值逾時（`ToolbarSmokeTests.swift:145`） | 冷啟動的 Simulator：它是 job 第一個測試，XCUITest 每次查無障礙樹 10–20 秒，開關的值在點下 17 秒後才讀到，等待只有 5 秒。不是 App 的錯（App 這段約 3 秒）；同 run 的另兩個測試綠 | **未合併**：open PR #528（等待改 20 秒；分支 run 38445860940 綠） |

### 目前狀態（2026-10-13 約 19:00 UTC，`main` = 0a855c3，#524）

- `ci.yml`：最新 push run 38449272912（0a855c3，#524）**綠**；範圍內沒有失敗。
- 完整 lane：最新一次是 38430642081（4e7b694，#522）**紅**（4 個測試）。其中 3 個由 #523 修好，並在 710716c 的手動 run（38441429093）確認其中 `testTheAdvancedSwitchFoldsTheTracksAndTheServiceDay` 與 `testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 綠；剩下 `testALineLegCanSelectAPhysicalPlatform` 的冷啟動逾時等 #528。#523 之後（710716c 起）還沒有一次完整的完整 lane：ios-full-lane.yml 在 #523–#524 的 push 都成功但沒有啟動新的一輪（推測是三小時的間隔還沒到；上一輪 16:27 開始）。
- `release-archive.yml` 夜間：綠。

範圍之外：10-11 的 #332–#349 有 9 次 ci.yml push run 紅（在 #401 之前，不在本表）。

## 三、修的 bug（GameCore 與 GamePresentation 的每一項都先寫了測試，確認修正前會失敗）

分兩個 PR：GameCore 的放在 `claude/pr401-525-review-core`，其餘放在 `claude/pr401-525-review-presentation`（這份文件也在這個 PR）。

GameCore：
1. **改車種時，帳面很大的列車會讓 App 當掉**（#412，決策 180，`GameWorld.setTrainType`）：
   - 出售收入按比例分給列車和車廂，用的是 `trainPart × proceeds ÷ tradeIn`，Int64 乘法沒有防溢位。
   - 存檔允許單筆資產帳面到 2^50，帳面約超過 1.2e12 分時乘積就溢位，App 直接 trap。
   - 一般遊戲碰不到，最大約 3e16；要壞掉或惡意的存檔才會遇到。
   - 現在改用已有的 `AssetRecord.share`（全寬乘除），結果在一般範圍內不變。
   - 測試：`RollingStockEconomicsTests.testARefitOfATrainWithHugeBooksDoesNotOverflow`。修正前測試程序以 signal 4 結束。
2. **委託案「新車站」的聚落點在地圖外，存檔照樣讀進來，之後才當掉**（#413，決策 183，`cityRequestsProblem`）：
   - 讀檔只檢查點有沒有，沒有檢查範圍。
   - 讀進來之後，下一列車停站時 `countRequestCall` 算 `dx * dx` 會溢位；下個月抽委託案的 `near` 也一樣。
   - 現在點必須在 `bounds` 內，否則拒絕讀檔。遊戲自己抽出的點是土地格的加權中心，一定在範圍內。
   - 測試：`CityRequestsTests.testASettlementOffTheMapIsRefused`。

GamePresentation 與 App：
3. **「五星景點」成就不算飯店加的星**（#403，之後 #421 加了飯店，`AchievementFacts`）：
   - 觀光面板、地圖提示、站長都用 `world.stars(of:)`，也就是每家附近的飯店加 0.25 星、最多兩家。成就卻讀原始的 `Attraction.stars`。
   - 結果是面板顯示 5.0 ★，成就卻永遠不解鎖，進度還寫 4.5。
   - 測試：`AchievementsTests.testTheBestStarsCountTheHotelsNearASight`。
4. **「一氣呵成」（50 km 路線）的環狀線少算最後一段**（#403）：從最後一站回到第一站那段沒加。測試：`AchievementsTests.testARingLineIsMeasuredAllTheWayRound`。
5. **列車全跑在停靠模式（pattern）上的路線，站長不說「第一條線虧錢」**（#414，`StationMasterAdvice`）：
   - 判斷「有沒有列車」只看 `line.trains`，沒看 `patterns` 裡的列車。其他地方都用 `assignedTrains`。
   - 現在也改用 `assignedTrains`。
   - 測試：`OnboardingTests.testAShortLineRunningItsTrainOnAPatternIsCalledLosing`。
6. **讀回的新聞檔，月報基準是「這個月」時，這個月的月報會不見**（#410，`restoreNews`）：
   - 只丟掉 `reportedMonth > month` 的基準。正常的基準最多是上個月，所以等於這個月的也是別局的檔案。
   - 留下來的話，月底 `closeMonth` 的 guard 會直接 return，這個月的月報不寫，基準也不換。
   - 現在 `>=` 都重來。
   - 測試加在 `MonthlyReportTests.testABaselineFromTheFutureIsReplacedWhenTheNewsIsRestored`。
7. **運行圖上，停在站裡誤點的列車，預測線把誤點算了兩次**（#525，決策 206，`TrainDiagram.pointsAhead`）：
   - 停站時，預測的出發點取 `max(departure, now)`，呼叫端再加上誤點。
   - 停站超過表定出發時，誤點正好是 `now − departure`，所以出發點畫在 `now + 誤點`。
   - 實測：誤點 60 秒的列車，預測出發 545 s，應為 485 s。
   - 現在取表定出發，加上誤點後就是現在。
   - 測試：`TrainDiagramTests.testALateTrainWaitingAtAStopIsExpectedToLeaveNow`。
8. **指令日誌：月報、負債、颱風自動暫停後，問題回報就重播不下去**（#468，決策 193）：
   - session 自己為事件暫停時，也記成 `.pause`。重播用的 session 在同一個 tick 也會自己暫停，讀到這一筆就停下，說「already paused」。
   - 結果是一般經營遊戲的回報，過了第一個月底就重播不下去。
   - 現在重播端遇到 `.pause` 時，如果自己的 session 已經為事件暫停，就當作同一件事（`CommandLogReplay`，只改測試端的重播器，日誌格式不變，舊回報也適用）。
   - 測試：`CommandLogTests.testAPauseForTheMonthlyReportReplays`。
9. **在地圖上建線時，路線的 ✓ 會蓋掉月台或擴建地塊的 ✓**（#503，決策 100 之後，SwiftUI `MapBuildConfirm`）：
   - 從車站膠囊開始建線之後，換到路網工具（月台模式）或開始選擴建地塊，地圖上仍是路線那顆停用的 ✓（「點路線的下一站」）。月台或地塊沒辦法在地圖上確認，除非按 ✗ 丟掉路線草稿。
   - 現在路線的 ✓ 只在地圖點擊真的會選站時出現，和 `MapView` 的點擊分派一致：路線面板開著，或選取工具且沒在選地塊。
   - **UNVERIFIED LOCALLY**：App 的 SwiftUI 檔，Linux 不能建置，要看 PR 的 iOS 建置。

## 四、轉給其他 session

- 沒有。備用車那一項（第五節第一條）先轉給修 bug 一批的 session（session_01BaYoZFYZoHZ8tKFtt64THL）。它的「首班被備用車擋住」已在 #530 修，改的是 `resolveDeadlock` 的前提；它判斷這一項是另一個 bug，回給這裡。

## 五、沒修，需要作者決定或只回報

- **關閉彈性發車時，讓路的備用車被移到別站後，再也發不出去**（#455，決策 58 之後的修正，`Deadlock.spareStandingAside` 與 `isSpare`）：
  - 原因：兩個函式都不看 `flexDispatch`，備用車可能被移到任何一站的股道。關閉彈性發車時（舊存檔、示範、挑戰的預設），`readyTrip` 只發停在第一個停靠站的列車，沒有空車回送。
  - 情境：W–M–E 單線，W 只有一個月台，M 有待避。路線 2 列跑 1 列，備用車停在 W。服務列車回到 W 時，備用車被移到 M。之後把服務列車數調成 2，路線仍然只跑 1 列，備用車一直停在 M。
  - 簡單的修法都會更糟：
    - 不讓它移動，或只准移到第一站，單一月台的起站就會永遠卡死。今天的行為至少讓服務列車繼續跑。
  - 選項：
    - (a) 關閉彈性發車時，被移開的備用車在路線需要它、而且第一站的股道空著時，空車回到第一站。這等於只為這個情況開放決策 172 的空車回送。
    - (b) 維持現狀，路線面板提示「備用車停在 M，發不出去」。
  - 只讀程式確認，還沒寫重現測試。

- **一鍵減少列車，等車的列車退出路線後仍停在路線的第一站股道上**（#515，`GameSession.removeTrains`）：
  - 開了行車控制時，它佔著那條股道。
  - 單一月台的起站，回來的列車會進不了站。
  - 這和手動「退出路線」（`unassignTrain`）一向的行為一樣：列車留在原地。所以沒有當成 bug 改。
  - 選項：(a) 一鍵減車時把等車的列車收回車庫（`unplaceTrain`）；(b) 維持現狀，訊息寫明它停在哪裡。
- **指令日誌沒有記 session 的暫停設定**（#468）：`pausesForImportantEvents`、`monthlyReportMode`、教學、示範、讀檔時的新聞狀態都沒有記。
  - 裝置和重播端設定不同時，重播端會在裝置沒停的地方停下，下一筆 `.advance` 就對不上時間。
  - 第三節第 8 項只處理了兩邊都停的情況。要完整解決，得把這些設定記進回報，會改格式。
- **日誌滿 5,000 筆、起點移到中間時，復原歷史沒有跟著截**（#468）：記錄的 `.undo` 在重播時可能「nothing to undo」。要在暫停中連續記兩千多筆才會遇到，很罕見。
- **閒置快轉跨過午夜時，飯店住客用的是預估值，不是當天實數**（#421）：
  - 那時 `clock.now` 還在前一天，而且 `closeTourismDay` 也沒跑。
  - 只有關閉每週需求與城市成長的世界才會走到；App 的新遊戲兩者都開。
- **待避線的號誌站名可能重複**（#521，`signalStationName` 算了關閉的車站）：只是名字，GameCore 允許重名。
- **`LineLossFix.isAffordable(with:)` 不看無限資金**（#491）：App 實際用的是 `economy.canAfford`，這個函式只剩測試在用，沒有影響。
- 第二節的狀態膠囊 UI 測試（只紅一次）沒有查根因；冷啟動逾時等 #528。

## 六、審查過、沒有問題（摘要）

- **GameCore**：
  - #408、#409、#417、#420、#426、#442、#445、#454、#518、#519。
  - #501（無限資金：每個花錢的地方都經過 `canAfford`／`spend`）。
  - #507（靠左行駛：方向符號、兩個 memo 的鍵、路線選路都不靠左）。
  - #459、#462、#479、#480、#513（效能重寫：索引邊界與原本的條件一致，memo 的鍵涵蓋所有讀到的值）。
  - #436、#444。
- **一鍵操作的失敗原子性**：#515 的增減車、#521 的一鍵複線與待避線，每一個都是一個 `PlayerCommand`，在世界的副本上執行，失敗時世界、復原、重做都不變，成功時一次復原整個收回。
- **指令日誌**：#475、#477 每個 Edit 與計畫的 Codable 對稱，沒有剩下 closure 形式的 `performEdit`。
- **背景存檔與自動存檔輪替**：#452、#469 沒有競態或寫錯槽。
- **快取**：#471、#472、#474、#488、#489、#492。
- **今天合併的其他 PR**：#485、#491、#497、#498、#499、#505、#506、#509、#510、#511、#516、#521、#522、#523、#524。
- **其他介面 PR**：#402、#406、#407、#411、#416、#423、#425、#429、#432、#433、#434、#438–#496 中列出的那些。
- **只改文件、CI 與工具的 PR**：沒有逐行找 bug（#401、#405、#415、#419、#422、#424、#427、#428、#430、#431、#435、#437、#447、#450、#453、#456–#458、#460、#464、#467、#470、#482、#490、#493、#494、#500、#502、#504、#508、#512、#514、#517、#520）。CI 腳本的 selftest 由 CI 跑。

## 七、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告，兩個分支都是。
  - 每個新測試都先在修正前跑過，確認失敗。改車種那一項修正前是 signal 4 trap。
  - 修正後通過的類別：`RollingStockEconomicsTests`、`CityRequestsTests`、`SavedGameTests`、`AchievementsTests`、`OnboardingTests`、`StationMasterAdviceTests`、`TrainDiagramTests`、`CommandLogTests`、`MonthlyReportTests`、`NewsSessionTests`、`NewsLogTests`。
  - GameCore 分支另跑了 `GoldenScenarioTests`、`ReplayFixtureTests`：48 項通過（1 項照設計略過）。
- **UNVERIFIED LOCALLY — requires macOS/Xcode CI**：`MapBuildConfirm.swift` 的修正。
- 其餘分片交給 CI。
