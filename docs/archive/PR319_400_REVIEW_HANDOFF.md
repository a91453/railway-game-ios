# 交接：PR #319–#400 的審查與修正

Session：`claude/pr319-400-review`（2026-10-13），由派工 session 派出。分支從 `main` 0a855c38（#524）開始。存檔版本、ARCHITECTURE 決策編號、golden schema 都沒有用到；GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改。GameCore 沒有改（修正都在 GamePresentation、App 與 CI 腳本），所以不佔 GameCore 的 CI 名額。

格式與做法照上一份 `PR200_290_REVIEW_HANDOFF.md`。

範圍說明：

- #319–#365 已有幾輪審查：#326、#357、#361、#366（#1–#365 全面），之後還有 #418／#420（全程式碼依領域）、#439／#441／#442（第三次查 bug）、#451、#454。這些 PR 列過的項目（修了的、留給作者的）這次都不重報，只對照 `main` 現況確認。
- #401 之後另派 session 處理，不在這份。

## 一、合併狀態

- #319–#400 共 82 個 PR 全部已合併。每個 head commit 都用 `git merge-base --is-ancestor` 確認過，都在 `main` 上（先 `git fetch --unshallow`）。
- 沒有關閉未合併的 PR，所以沒有遺漏的內容要補。
- #339 先合併到 `claude/freight-loop`，再隨 #340 進 `main`。

## 二、`main` 的 CI 紅燈與根因（#319 合併 2026-10-10 14:53 到 #400 合併 2026-10-12 03:11，以及到 10-12 為止的手動 run）

CI（Linux）在這段期間有 9 次 push run 失敗，Wasm Probe 沒有紅燈。iOS App Build 有 6 次失敗；另有 22 次被下一次推送取消。iOS Full Lane 的觸發 run 都是綠的（它只負責啟動 ios-build）。

| 合併／run | 失敗 | 根因 | 現況 |
| --- | --- | --- | --- |
| #332（#334、#335 跟著紅） | CI：`HolidayTests` 比對 JSON 的鍵順序 | 測試沒有用 `.sortedKeys`，Dictionary 的順序每個行程不同 | 已修 #337（#366 第十一節已記錄） |
| #340（#341–#344 跟著紅） | CI：教學測試 | 預期世界沒有關建材 | 已修 #345 |
| #349 | CI：`rest` 分片起不來 | 測試 ID 參數 131,536 bytes，超過 Linux 單一參數上限 | 已修 #352（分批跑） |
| 夜間 fbe31085（#325，10-10）、#331 push | iOS：`MapInteractionTests.testConstructionHUDAppearsDuringTrackPreview`，按「建造」後 `tool.network` 沒出現 | 站長頭像在 dock 量好尺寸之前擋在「建造」上，點擊被移到按鈕角落（#336 從 xcresult 查到）。夜間那次的斷言（:377）是同一步 | 已修 #336 |
| #345 push | iOS：`SettingsUITests.testTheCityPreviewLoadsItsPageAndCloses`，3D 頁面沒從 loopback 載入 | 本機伺服器只聽 IPv4 的 loopback，又沒等載入完成 | 已修 #348；之後 3D 試作改開官網（#368，決策 163），本機伺服器已移除 |
| #350 push | 同一個測試：`-1005`（連線中斷） | 回應送完，連線被立刻關掉 | 已修 #353（#366 已更正原因） |
| 手動 49de93fb（#391）、440736e6（#408），10-12 | iOS：`menu.backToStart` 按不到（`RealWorldMapUITests`、`StartSaveFlowSmokeTests` 兩項） | 手機橫拿時遊戲選單太長，「回到開始畫面」落在畫面外 | 已修 #423（681276df：另存新檔併到匯出那一列；50b584d9：選單固定六列） |
| 440736e6 | iOS：`SettingsUITests` 找不到 3D 城市試作 | 設定清單要捲動才看得到那一列 | 已修 #427 |

**`main` 現況**（交接時，0a855c38）：

- `ci.yml` 最近 6 次 push run 都綠。
- iOS 的完整 lane（手動與夜間）從 10-13 起有紅燈：
  - `LineRoutePreferenceUITests` 的兩項：進階開關等 5 秒不夠。
  - `MapInteractionTests.testTheStatusPillsButtonsAreTouchedBeyondTheirIcons`。
  - `RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`。
- 都在 #400 之後，由 full lane 那條線（session_01Wznwe1iBrHartyRUGmDUV9，#528）處理，這裡沒有動。

## 三、本分支修的 bug（每項都先寫了重現測試，確認修之前會失敗）

修正分成兩個 PR：CI 腳本一個，GamePresentation／App 一個。

### PR A：CI（`claude/pr319-400-review-ci`）

0. **`swift-shards.sh` 過不了 shellcheck**：見第六節最後一段。修好之前，任何改到 TestFlight 腳本的 PR，TestFlight Checks 都會紅。
1. **TestFlight 的 What to Test 寫錯上一版的編號**（#377，`testflight-changes.py`）
   - **原因**：讀的是上一次 run 的 `run_attempt`，那是 run 最新一次的 attempt。workflow 本身建議處理逾時時只重跑 processing job；這樣 attempt 變成 2，上傳的卻是 N.1，下一版就會寫「Changes since build N.2」。
   - **修正**：改讀成功的上傳 job（「Archive, sign, export, check and upload」）的 attempt；GitHub 沒列出 job 時退回 run 的 attempt。
   - **測試**：`testflight-selftest-processing.py` 的 `test_names_the_attempt_that_uploaded_not_a_later_rerun_of_processing`（修之前寫成 51.2）。
2. **完整 lane 的排程備援常常隔 6 小時才跑**（#372，`ios-full-lane.yml`）
   - **原因**：排程每 3 小時一格，判斷「上一次完整 run 不到 3 小時就不跑」。每一格都會晚幾分鐘，晚的分鐘數每次不同；只要這一格比上一格少晚一點，算出來就差幾秒不到 3 小時，於是跳過。
   - **修正**：排程觸發時容許 15 分鐘。
   - **驗證**：沒有測試框架涵蓋這個 workflow，只做了 YAML 解析與 `bash -n`。

### PR B：GamePresentation／App（`claude/pr319-400-review`）

3. **時代劇本裡「改編組」用路線預設會全部失敗**（#341 的規則 × #395 的改編組，決策 153、180）
   - **原因**：「依路線預設」在買車時是時代的車種，改編組時卻是標準車，而時代沒有標準車。
   - **結果**：例如劉銘傳劇本只改節數，每列車都「沒有改：這個時代沒有標準車」。
   - **修正**：`lineStaffingPlan` 在時代裡預設時代的車種。
   - **測試**：`RollingStockSessionTests.testReformingInAnEraKeepsTheErasType`。
   - 兩個審查 agent 分別找到這一項。
4. **配車、加車或改編組成高鐵車組，路線沒有變成高鐵**（#395，違反決策 168 第 7 點）
   - 一列一列配屬時會變，`staff`、`addTrains`、`reform` 卻直接呼叫 `assignTrain`。
   - **結果**：票價、腹地、城際旅次都不算，畫面也沒說。
   - **修正**：配車在算班數之前先以高鐵規劃（車數照高鐵的來回時間算）；改編組與加車在之後規劃。訊息會說「現在以高鐵規劃」。
   - **測試**：`RollingStockSessionTests.testStaffingOrReformingWithHighSpeedSetsMakesAHighSpeedLine`。
5. **改車種後還照舊車種的性能跑**（#380 的條件 × #381 的 EMU3000 性能）
   - **結果**：
     - EMU3000 改成高鐵車組，仍以 135 km/h 跑；配到高鐵線上，每一段都誤點。
     - 高鐵車組改成 A 型，仍以 300 km/h 跑。
   - **修正**：原本照舊車種性能跑的列車，改照新車種的性能（沒有自己的性能就是標準）；玩家另外設定的性能保留。選單改車種與改編組都一樣（`GameWorld.runAsItsType`）。
   - **測試**：`RollingStockSessionTests.testATrainGivenAnotherTypeRunsAsThatType`。
6. **財務趨勢的標題拿公司還不存在的期間比較**（#385，決策 176）
   - **結果**：新遊戲第 34 天，每天收入一樣，卻寫「過去 30 天：票收成長 500%」。90 天與 1 年的範圍也一樣，1 年那個範圍會持續到第 719 天。
   - **修正**：只有前一個期間整段都在公司帳上時才比較，否則寫「沒有更早的期間可比」。帳本滿 720 天、舊的日子被刪掉時，照常比較。
   - **測試**：`FinanceHistoryTests.testAWindowBeforeTheCompanyBeganIsNotCompared`。
7. **趨勢圖的橫軸仍有負的天數**（#385；09fcf158 只修了文字標籤）
   - 圖表的 x 值改用 GamePresentation 的 `FinanceTrendPoint.axisKey(for:)`，從第 1 天起算，每個柱仍各自唯一。
   - **測試**：`FinanceHistoryTests.testAYoungGamesFirstBucketIsLabelledFromDayOne` 加了三個斷言。
   - App 的圖表是 SwiftUI，UNVERIFIED LOCALLY。
8. **買名產店、蓋飯店後，車站客源與旅次圖層不更新**（#366 的 `RidershipInputs` × 決策 174）
   - **原因**：快取的鍵沒有觀光。景點的星等變了，觀光客就跟著變，GameCore 的乘客計畫鍵（`PassengerPlanKey`）有算進去，這裡沒有。
   - **修正**：鍵加上 `tourism` 與各景點的星等。
   - **測試**：`TourismSessionTests.testTheRidershipInputsSeeASouvenirShop`。
9. **已被自由模式中止的挑戰，秘書室仍倒數「挑戰剩 N 天」並暫停**（決策 175，#397 也照抄了條件）
   - 這是 #366 之前的舊存檔：挑戰中切到自由模式。
   - **修正**：只在經營模式倒數。
   - **測試**：`NewsSessionTests.testAChallengeStoppedByFreePlayIsNotCountedDown`。
10. **颱風預警寫「影響 0 個車站」**（決策 175）
    - 英文在 1 站時寫成「over 1 of our station」。
    - **修正**：沒有車站受影響時寫「不經過我們的車站」，英文 1 站時寫「one of our stations」，和站長的說法一致。
    - **測試**：`NewsSessionTests.testATyphoonOverNoStationSaysItMissesThem`；`testATyphoonWarningPausesTheGameOnlyWhenAskedTo` 加了一個斷言。
11. **雙線在彎道內側，緩和坡度讓整段被拒絕**（#375 把緩和坡度預設打開，決策 164 × 決策 204）
    - **原因**：彎道內側的那一軌比較短，坡度比較陡。主線的緩和坡度剛好放得下時，內側那軌會超過 40‰。
    - **結果**：整段雙線被當成「太陡」拒絕，但兩軌都用固定坡度是蓋得起來的。
    - **修正**：內側放不下時，兩軌都用固定坡度（`GameSession.doublePlans`）。
    - **測試**：`DoubleTrackSessionTests.testAParallelTooSteepEasedKeepsBothSteady`，條件是高架 352、右側、往東南的彎。
12. **載貨條的 VoiceOver 值沒有單位**（#374）：改念細節那一行（貨運寫噸）。App 檔，UNVERIFIED LOCALLY。

## 四、沒修、需要作者決定或只回報

需要作者決定：

1. **改到 `.github/scripts/` 的任何 PR 都跑完整的 Swift 18 個 job**（決策 185 的 `swift-shards.sh path_plan`）
   - 同一個改動推到 `main` 時，`relevant_paths` 判定與套件無關，直接跳過。
   - 例子：#377 只改 TestFlight 腳本，卻跑了整套。
   - 決策 185 寫明 `.github/scripts/` 算全部，所以要作者決定。
   - 建議：只有 `swift-shards*.sh` 與 `ci.yml` 算全部，其他腳本不跑 Swift。
2. **開著連假與事件的挑戰，玩家把事件關掉之後，成績又會被記下來**（#362）
   - `WeeklyChallenge` 只看目前的開關，設定頁卻寫「開著存的局只能關掉，成績不記」。
   - 情況：連假尖峰先達成每日乘客目標（達成的日子會一直留著），再關掉事件完成其他目標。
   - 選項：
     - (A) 挑戰中開著事件時，連關也不行。
     - (B) 記一個「曾經開過」的標記（要升存檔版本）。
     - (C) 改說明文字。
3. **沒有列車的路線，7 天後同時冒「沒有列車」與「連續虧損」兩個泡泡**（#396，決策 179）
   - 車站的費用每天照算。
   - 決策 177 的後續已讓站長不把沒車的線說成虧損。
   - 決策 179 的文字與它自己的測試（`testALineLosingMoneyForAWeekShowsOnTheMap` 用的就是沒車的線）都把這當成要的行為，所以沒有改。
   - 建議：`lineLosingMoney` 加上「有配屬列車」，同時改那個測試的世界。
4. **改編組選「依路線預設」，會把一般路線上的 EMU3000、B 型等改回標準車並收改裝費**：玩家可能只是想改節數。「預設」是指標準車，還是「保留各車原本的車種」，要作者定。

只回報（影響小、PLAUSIBLE 或範圍外）：

5. **載客量圖層對有固定班次的路線，兩個方向、全天都用同一個容量**（#390，`SectionFlow.capacities`）：只開一個方向的班次時，另一方向會顯示有容量。PLAUSIBLE，沒有重現。
6. **貨運列車載貨中被減節，載貨條可以超過 100%**（#335）：要先解除配屬、取下列車才能減節，存檔仍讀得回來。只影響顯示，PLAUSIBLE。
7. **解除配屬的貨運列車，貨在車上的那一小時內載貨條寫「載客 0」**：`isFreightTrain` 看的是配屬，貨到下一個整點才算損失。
8. **建物讀土地的範圍 64 m，比遊樂園的半對角線約 79 m 小**（`BuildingSession.buildingLandReach`）：依面積收購時，角落可能有一小塊沒讀到。一格的幾個百分比。
9. **空車回送算進路線的發車數與座位**，所以報表的滿載率會低一點。可能是刻意的。
10. **範圍外（#400 之後）**：
    - `MonthlyReportText` 的「創紀錄」只比票收，沒算貨運。
    - 景點與名產店不檢查是否在已買的地圖區塊。

## 五、逐 PR 結果

| PR | 結果 |
| --- | --- |
| #319、#336、#337、#348、#353、#360、#370、#392、#393 | 修紅燈或 UI 測試，現況正確 |
| #320、#321、#323、#328、#329 | 只有研究文件與量測工具 |
| #322、#324、#325、#330、#333、#357、#361 | 沒有新發現（之前的審查已修過的不重報） |
| #326、#366、#373 | 審查與決定的 PR；#366 的 `RidershipInputs` 缺觀光（第三節第 8 項），其他沒有新發現 |
| #327、#332、#344、#345、#349、#364 | 沒有新發現 |
| #331、#334、#343、#346、#376、#379 | 沒有新發現 |
| #335、#339、#340、#342、#374、#398 | 只有第三節第 12 項與第四節第 6、7 項 |
| #341 | 第三節第 3 項（與 #395 一起） |
| #352、#354、#355、#356、#358、#359、#400 | CI 腳本，沒有新發現 |
| #362 | 第四節第 2 項 |
| #372 | 第三節第 2 項 |
| #375 | 第三節第 11 項 |
| #377 | 第三節第 1 項 |
| #378、#383、#384、#389 | 沒有新發現 |
| #380、#381、#395 | 第三節第 4、5 項，第四節第 4 項 |
| #382、#387 | 沒有新發現（彈性發車從終點出發的方向、兩端閒置車等已列在之前的清單） |
| #385 | 第三節第 6、7 項 |
| #386、#388、#394、#399 | 沒有新發現（已知的子公司用錯日子、自動暫停被存成玩家暫停等不重報） |
| #390 | 第四節第 5 項 |
| #391 | 觀光：沒有新發現（名產店折舊另一條線在修） |
| #396 | 第四節第 3 項 |
| #397 | 第三節第 9 項 |
| #338、#347、#350、#351、#363、#365、#367、#368、#369、#371 | 3D 城市試作與車輛模型工具，見第六節（兩項只回報） |

## 六、3D 城市試作、工具與文件 PR

這些 PR 都沒有在 GameCore、存檔、決定性或失敗原子性留下問題。只有 #336、#337 改到 3D 頁面以外的 Swift，兩者都沒問題。

只回報、沒有修的兩項：

1. **重跑列車工具會蓋掉作者烤好的 N700ST 模型**（#365 的 `bake_model.py`，疊在 #363 的 `build_train.py` 與 #347／#350 的 `meshy.mjs pack` 上）
   - `index.json` 裡烤好的 `n700st-cab` 項目有 `colour`、`aoChannel: 0`、`fit: false`。
   - 照 `tools/trains/README.md` 跑 `build_train.py`（不帶參數）時：
     - 同名的 GLB 與 AO 會被改寫成程式畫的外殼。
     - `index.update` 會整項換掉，`colour` 與 `aoChannel` 就不見了。
   - 跑 `meshy.mjs pack n700st-cab` 會蓋掉 GLB，項目重設成 `{file, front}`。少了 `fit: false`，車就被重新縮放。
   - 只在有人重跑工具時發生。建議：
     - `meshy.mjs` 改成合併項目：`{ ...index[id], file, front }`。
     - 程式畫的版本另取名字，或在項目有 `colour` 時拒絕覆寫。
2. **官網 3D 頁：瀏覽器語言改變後，保存的設定會遺失**（#369，`Web/CityView/src/main.js` 約 382–415 行）
   - 原因：控制項先依 `GUI_ZH` 改名，再 `gui.save()`，所以 localStorage 的鍵是中文名。
   - 換成英文瀏覽器時，`gui.load()` 認不得這些名字，設定變回預設；離開頁面時還會把預設值寫回去，蓋掉原本的中文設定。
   - App 帶參數開頁（`explicit`），不讀也不存，所以不受影響。
   - 建議：用 DOM 改顯示的文字，內部名稱保持英文。

逐 PR：

- #320、#321、#323、#328：量測工具與研究，沒有發現。
- #329：只有文件。
- #367、#368、#370、#371：沒有發現。
- #338、#347、#350、#351、#363、#365：只有第 1 項。
- #369：第 2 項。

另外，**PR #534 的 TestFlight Checks 抓到 `main` 的 `swift-shards.sh` 過不了 shellcheck**：
- 決策 185（1a85d0b6，#401 之後）的程式重用了 `names`、`parts` 兩個名稱，在不同函式裡一下是陣列、一下是字串。
- `testflight-checks.yml` 只在 TestFlight 檔案改動時跑，所以 `main` 一直沒有跑到。
- 修正在 #534（f90ed9ed）。

## 七、建議下一步

1. 第四節第 1–4 項請作者決定；第 1 項只改 `swift-shards.sh` 與它的 selftest，可以很快做完。
2. `main` 目前完整 lane 的紅燈由 #528 那條線處理。
3. 第四節第 5 項（固定班次的容量）若要做，照 `line.runs` 依方向、依小時算容量。

## 八、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 每個新測試都先在修正前跑過、確認失敗，修正後通過。
  - 通過的類別：`RollingStockSessionTests`、`HighSpeed*`、`LineStaffing*`、`LiuMingchuan*`、`LineTrainCount*`、`PlayerCommand*`、`Undo*`、`NewsSessionTests`、`NewsLogTests`、`FinanceHistoryTests`、`TourismSessionTests`、`StationDemandSessionTests`、`DoubleTrackSessionTests`、`NetworkBuildingSessionTests`、`TerrainPresentationTests`、`NetworkDragTests`。
  - `testflight-selftest-processing.py`：23 項全過。
  - `ios-full-lane.yml`：YAML 能解析，`bash -n` 通過。
- **UNVERIFIED LOCALLY — requires macOS/Xcode CI**：`FinanceTrendCharts.swift`、`TrainLoadBar.swift`，本機只做了 `swiftc -parse`。
- PR #534 改到 `.github/scripts/`，照決策 185 會跑完整 Swift tier（第四節第 1 項）。第一次的 run 已取消、讓出 runner，等合併 session 放行再推。
- 審查方法：8 個唯讀的審查 agent，各讀一組 PR 的 diff 並對照 `main` 現況。每個發現都由我自己讀程式確認，能寫測試的先寫失敗的測試。

## 九、第四節第 1–4 項：作者的決定與實作（2026-10-13）

作者請派工 session 從玩家、開發者、美術三方面替這 4 項做選擇。定案與實作如下，分支 `claude/pr319-400-decisions`：

| 項目 | 定案 | 實作 |
|---|---|---|
| 1. 改到 `.github/scripts/` 的 PR 跑完整 18 個 job | 維持不改。這種 PR 少，腳本決定要測哪些，判斷錯了代價大。 | 不改程式，只記在這裡。 |
| 2. 開著事件的挑戰，中途把事件關掉 | 這一局不記成績，記錄頁顯示「已關閉事件，不計紀錄」。 | 待定：照定案做要在 GameCore 的 `ScenarioState` 記「曾開過事件」，要升存檔版本。已請派工 session 在「升存檔 54」與「挑戰中不能關事件」之間選一個。 |
| 3. 沒有列車的路線冒兩個泡泡 | 只留「沒有列車」，沒有列車時不出「連續虧損」。 | `lineLosingMoney` 對沒有列車的路線回傳 false，地圖泡泡與路線列的紅字都跟著改。決策 179 加了之後的修正。測試：`LineReportTests.testALineLosingMoneyForAWeekShowsOnTheMap`（先改成會失敗的版本，再修）。 |
| 4. 改編組選「依路線預設」 | 路線有自己的車型時套用路線的；沒有時保留每列車原本的車型，不降回標準車。 | `GameSession.reform` 收到 `nil` 時保留各車車型，訊息寫「車型不變」。決策 180 加了之後的修正。測試：`RollingStockSessionTests.testReformingWithTheLinesDefaultKeepsEachTrainsType`（修之前改回標準車，還收了改裝費）。 |

