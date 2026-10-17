# 交接：PR #755–#784 的審查（72.1 那一天）

Session：PR #755–#784 審查（2026-10-17），由遊戲規劃 session_01V1xd3H9vNkuZoSA3czNfGm 派工。從 `main` abb306a（#784 的合併）開始。上一輪 #712–#754 見 [`PR712_754_REVIEW_HANDOFF.md`](PR712_754_REVIEW_HANDOFF.md)。

- 存檔版本、決策編號、golden schema 都沒有用到。
- GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改。
- 一個 PR：`claude/pr755-784-review`，這份交接加上第三節的修正。GameCore 沒有改。
- 這個 session 沒有權限在 #231 留言（`403 Resource not accessible by integration`），也沒有 `send_message`、Actions 的工具；登記與通知的原文交給作者轉貼（第七節）。

做法和上一輪一樣，只是這次沒有分出子 agent，30 個 PR 都是我自己讀的。深度依序：#761、#763、#777、#767、#774、#781、#779、#780、#769、#772、#771 逐行讀；其餘的程式 PR 讀 diff 找權威性、原子性、決定論與玩家文字的問題；3D 的 PR 只查了決定論（亂數、字典走訪順序），沒有看畫面。寫得出 Linux 測試的，先在 `origin/main` 跑、確認會失敗，再修。

## 一、合併狀態

- #755–#784 共 30 個號碼**全部是 PR，全部已合併**，`git log origin/main --merges` 每一個都找得到。開工時沒有開著的 PR。
- 依合併時間：#755（10-16 19:01 UTC）→ #756、#757、#758 → #760、#762、#761、#759、#763、#765、#766、#768、#769、#764、#767、#770、#771、#775、#773、#774、#772、#777、#776、#778、#779、#780、#781、#782、#783 → #784（10-17 17:27 UTC）。
- 只改文件或工具的：#755、#760（`tools/`）、#762、#766、#778、#782；只改 CI 的：#758；只改 UI 測試的：#775、#783；試看素材：#773。

### 合併當下 iOS App Build

- 決策 265（#756，10-16 23:26 合併）之後，PR 的 `Swift CI (gate)` 會等同一個 commit 的 iOS App Build，所以 gate 綠就代表 iOS 也綠了。
- 抽查 8 個動到 App 的 PR 的 check runs（#764、#767、#772、#779、#780、#781、#783、#784）：都是 gate 綠了之後才合併；最後一個 head 只改文件的，iOS 顯示「Remember that this change passed」skipped，前一個 head 有跑過、綠。其餘 PR 的「CI 全綠」紀錄在 #231，和合併時間對得上。
- **這一輪沒有像上一輪 #746 那樣「iOS 還在跑就合併」的 PR**。#759 的 iOS 第一次紅（實景開局測試逾時），重跑綠、gate 也重跑之後才合，照決策 265 的做法。

## 二、72.1 發版與 `main` 的 CI

### 72.1（testflight.yml run #72）

- run 39026212708，commit **8c305a6**（#782 的合併），**成功**（10:47 UTC 起，14 分 39 秒）。
- 派工單寫的「72.1 = main c3a3ec7」不準：c3a3ec7 是 #783 的合併，比 8c305a6 晚 75 分鐘。兩者只差 #783 一個 UI 測試檔（`StartSaveFlowSmokeTests.swift`），App 完全一樣。

### 時間線

| 時間（UTC） | 事件 | full lane |
| --- | --- | --- |
| 09:20 | d530311 的 full lane（39020766185） | **紅**：iPad 教學（`TutorialJourneyUITests` 第 15 步，#781 修）＋第一個 job（`StartSaveFlowSmokeTests` 兩支，#783 修） |
| 10:42–10:44 | #781、#782 合併 → 8c305a6 | |
| 10:45 | 8c305a6 的 full lane（39026081385）手動開始 | |
| **10:47** | **72.1 開始發版（8c305a6）** | 還在跑 |
| 約 11:28 | 39026081385 結束 | **紅**：第一個 job（`StartSaveFlowSmokeTests` 兩支）＋第二個 job（`MapInteractionTests/testHoldingAStationTracesItsBusiestTrips`） |
| 11:59 | #783 合併 → c3a3ec7；c3a3ec7 的 full lane（39030772448）手動開始 | |
| 12:39 | 39030772448 結束 | **綠**（第一個 job 32 分、第二個 39 分 40 秒、iPad 16 分） |
| 17:27 | #784 合併 → abb306a；full lane（39053855189，`ios-full-lane.yml` 啟動）| **紅**：第一個 job，exit 65，1 小時 1 分（見下） |

- **72.1 發版時，發版的 commit 沒有自己的綠 full lane**：它的 full lane 在發版前 2 分鐘才開始，後來是紅的。CLAUDE.md 要求「發版前 commit 的 full ci.yml 與 full lane 都綠」。
- 事後看：紅的三支都不是 App 的問題。`StartSaveFlowSmokeTests` 是測試的捲動條件（#783 只改測試），第二個 job 的那支在 c3a3ec7 沒改任何第二個 job 的類別就綠了（時好時壞，第四節）。c3a3ec7 的 full lane 全綠，App 和 72.1 一樣，所以 **72.1 發出去的 App，等於事後全綠的那一份**。
- `ci.yml` 的 push run：#761 到 #784 每一個合併都是綠的（#776、#781 那兩次被下一次 push 取代、取消，不算紅）。

### `main` 現在的 full lane 是紅的（abb306a）

- run 39053855189：第一個 job（`Xcode build (iOS Simulator)`，跑 full lane 的前半）`Process completed with exit code 65`，整個 job 1 小時 1 分；第二個 job 與 iPad 綠。
- 失敗的是哪一支測試，**我看不到**：job log 要登入，這個 session 的 GitHub 工具沒有 Actions。
- 可疑的：#784 把 `LessonUITests` 12 支（它自己量的是 XCTest 1,472 秒，約 24.5 分鐘）加進第一個 job，第一個 job 從約 30 分鐘變成約 60 分鐘，而它的步驟上限是 75 分鐘。
- **給合併協調**：用 `get_job_logs` 拿 job 117457795375 的 log，`grep -aE "error: -\[|' failed \(|Executed [0-9]+ tests, with"` 找出失敗的測試；下一次發版前這一輪一定要綠。

### Swift CI 時間（`ci.yml` push）

- 這一輪 18 次跑完 Swift 的 push run（只改文件、工具或 UI 測試的不跑 Swift，不算）：15.8–32.7 分鐘，中位數約 18.7 分鐘。#759（32.7）、#770（30.0）兩次特別長，沒有查是排隊還是某個 shard 變慢。
- 上一輪是 16.0–18.4 分鐘，中位數往上走了約 2 分鐘。

## 三、修的（`claude/pr755-784-review`）

| # | 項目 | 來源 | 修法 | 驗證 |
| --- | --- | --- | --- | --- |
| 1 | 路線卡「營運狀況」兩端的候車人數，算進了**別條線**的乘客：兩條線同一個起點站時，每條線都說「N 人在等」是兩條線的總和，「一班車載不完」也是拿總和比這條線的一列車 | #780，`LineFeedback.swift` 的 `lineFeedback(_:)` 用 `passengers.first { … }?.waitingCount` | 只數 `waitingPassengers(at:)` 裡 `line == 這條線` 的人 | `LineFeedbackTests.testAnEndCountsOnlyThoseWaitingForTheLine`（新）。在 `origin/main` 失敗：`Optional(296) is not equal to Optional(148)`；修正後通過 |
| 2 | 列車面板的座位圖，長編組會撐出卡片：每節車約 40 點寬，手機橫拿時卡片最寬 300 點，7 節以上就超出；高鐵示範的 12 節約 476 點 | #780，`TrainLoadBar.swift` 的 `SeatMapView` 一排畫完所有車廂 | 一排最多 6 節（約 240 點），多的換行；換行的規則放在 `SeatMap.rows` | `LineFeedbackTests.testALongTrainsSeatMapWraps`（新，`rows` 是新的 API，在 `origin/main` 編譯不過）。畫面交給 `ios-build.yml` 編譯，實機 UNVERIFIED |
| 3 | 關卡結果卡按「繼續玩」之後，遊戲還停著：達成目標時遊戲自己暫停（決策 175），結果卡只把卡片關掉，玩家要再找「繼續」 | #767 的結果卡；Codex 在 #784 的 UI 測試裡看到，交回 App 作者評估 | `GameSession.keepPlaying()`：遊戲是自己為事件暫停的，就照原來的速度繼續；玩家自己按的暫停不動。結果卡的「繼續玩」呼叫它 | `LessonTests.testKeepPlayingRunsTheGameAGoalPaused`（新）。在 `origin/main` 沒有這個方法；前半（達成目標後 `isPausedForEvent`、時鐘停著）就是 `main` 的行為。`LessonUITests.testKeepPlayingClosesTheResultAndKeepsTheRailwayRunning` 兩種都接受，不會因此變紅 |
| 4 | 3D 場景快取會把**上一局**的場景給下一局：鍵只數軌道、月台、建物與第幾週，兩個新局（例如入門第 1 關，再開自由模式）都是 0 條軌道、第 0 週，鍵一樣 | #769，`Map3DPreviewScreen.swift` 的 `Map3DSceneCache` | 快取多記一個 `weak var game: GameSession?`，不是同一局就重蓋（換局都會建新的 `GameSession`） | App 的程式，Linux 測不到；交給 `ios-build.yml` 編譯，實機 UNVERIFIED |
| 5 | 診斷：`testHoldingAStationTracesItsBusiestTrips` 的長按沒開面板，現有的 trace 只記得「手指按了 0.59 秒」，不知道是哪一關沒過 | 第四節 | 長按的三個分岔各寫一行 `UITestTrace.action`（只在 Debug 加 `-ui-testing` 時寫）：被拒（工具、面板）、按到的位置有沒有車站、開始時選到哪一站 | 下一次紅的時候看 `ui-second-half-trace`。App 的程式，交給 `ios-build.yml` |
| 6 | 決策 266 寫「入門 · ★ n/9」，程式是 `3 × Lesson.all.count`（10 關之後是 n/30） | 文件 | 決策 266 第 6 點補一句 | `doc_numbers.py --check` 差異 0 |

## 四、延後（等穩定）

分類照上一輪：只動 App 或 GamePresentation、局部、不改存檔與 GameCore 行為的，現在修；其餘延後；拿不準的歸大。

| 項目 | 為什麼延後 | 建議做法 | 預估影響範圍 |
| --- | --- | --- | --- |
| **`main` 的 full lane 紅（abb306a，run 39053855189）** | log 要登入，我看不到是哪一支 | 第二節。若是 `LessonUITests` 的時間，把它移到第三個 iPhone job，或把它的 12 支分到兩個 job；第二個 job 的步驟上限是 45 分鐘，現在已經跑 35–40 分鐘，整個搬過去會超過 | `.github/workflows/ios-build.yml`（`FULL_LANE_SECOND_JOB`） |
| **`MapInteractionTests/testHoldingAStationTracesItsBusiestTrips` 時好時壞，根因沒有確認** | 失敗的 log 與 trace 要登入。下面是讀程式能確定與排除的 | 下一次紅時讀第三節第 5 項的 trace 行，三種結果各指向一個方向（見下） | `MapView.swift` 的長按、或測試 |
| 自動待避線一次蓋多處時，第二處以後在一個**沒有高度檔**的 `GameSession` 上規劃與試蓋 | 只在實景地圖、第一處待避線的側線碰到還沒讀進來的地面區塊時發生；結果是少蓋幾處（回到 #777 之前一次一處），不是錯 | `passingLoopsNeeded` 裡新建的 `planner` 帶上這個 session 的 `heights`（和 `water`） | `AutoService.swift` |
| 整平月台時，**轉乘中的乘客**（`journey` 不是 nil 的候車群）會被放棄 | 整平在同一個編輯裡拆掉月台與軌道再蓋回去，`removeTrackPlatform`、`removeTrackEdge` 每一步都會 `abandonUnservedPassengers()`，那一刻路線不通。決策 190 本來就這樣，#761 讓「有月台的軌道」也能整平，碰到的機會變多。直達的乘客不受影響：我在 `longLine()` 上加需求跑了一次，兩站的候車 148／146 人整平前後一樣（探測測試沒有提交） | 要改 GameCore（一個不在中途放棄乘客的批次編輯），或整平前後在 GamePresentation 比對候車並在訊息裡說明。歸大 | GameCore `GameWorld`、`LevelPlatformTrack.swift` |
| 3D 場景快取一直留著最後一個場景；2D 拉近到門檻一半就開始蓋 3D 場景，玩家沒有進 3D 也蓋 | 記憶體與電池，沒有在實機量 | 回到開始畫面與收到記憶體警告時清掉快取；「先蓋」改成拉近停在門檻附近一下才開始 | `Map3DPreviewScreen.swift`、`MapView.swift` |
| 兩端需求燈用路線**第一列車**的定員比 | 同一條線的列車通常同型；混編時才不準 | 用路線列車定員的最小值或平均 | `LineFeedback.swift` |
| 72.1 發版時，發版的 commit 沒有自己的綠 full lane（第二節） | 流程，合併協調與遊戲規劃的事；事後 c3a3ec7 全綠、App 相同 | 發版前照 HANDOFF §1.2「發版前」：要發的 commit 自己的 full lane 跑完、綠了才通知「可以發」；紅燈的修正（這次是 #781）合進去之後要再等一輪 | HANDOFF §1.2 |
| 72.1 沒有記進 `docs/research/PLAYER_FEEDBACK.md` | 遊戲規劃的工作（HANDOFF §1.1「發版後」） | 照 70.1、71.1 的格式記：run 72、8c305a6、10:47 UTC | `PLAYER_FEEDBACK.md` |
| `-lesson-stars` 把 `launcher-preferences.data` 寫成字串 | `GameLauncher.preferencesFileName` 是 internal，App 讀不到；檔名改了 UI 測試會默默沒效果 | 把那個常數改成 public，App 讀它 | `GameLauncher.swift`、`RailwayGameApp.swift` |
| `ci.yml` push 有兩次超過 30 分鐘（#759、#770） | 沒有拆 shard 時間 | 照上一輪的做法看各 shard；`rest` 連續超過 18 分鐘再搬 class | `.github/scripts/swift-shards.sh` |

**`testHoldingAStationTracesItsBusiestTrips` 讀到的東西**：
- 每一次失敗都在同一個地方：#783 說明裡的 trace 是「在 (437, 201) 按了 0.59 秒，超過 0.45 秒的長按門檻，沒有面板」；更早的 38798340562、38888973282 也是 (437, 201)。那是 874×402 地圖的正中央，也就是示範一開始鏡頭對準的 Central。失敗的是第一個斷言（面板沒開），不是第二個（軌跡）。
- 排除：軌跡的計算（`JourneyTraceKey` 用 `RidershipInputs`，裡面的路網、車站、需求在一天之內不會變，不會每個 tick 重算到算不完）——而且失敗根本沒走到那裡。
- 排除：車站的標籤（只在選了車站時出現）、按到列車（`holdMap` 只找車站）。
- 沒能排除：(a) 長按被拒：`holdsAt` 要 `tool == .select` 而且 `panel != .lines`；(b) 按的位置換算成地圖座標時，鏡頭已經移了（`projection` 是上一次重畫時的）；(c) 按的那 0.59 秒裡，手勢所在的 UIView 被重建，進行中的手勢被取消。
- 第三節第 5 項加的 trace：寫「refused」就是 (a)；寫「station none」就是 (b)；什麼都沒寫（連 `map.hold at` 都沒有）就是 (c) 或觸控沒到 `MapGestureView`（trace 的 `touch … view …` 那一行會說是哪個 view）。

## 五、審查後判定沒有問題

- **#761 整平有月台的軌道**：
  - 月台在 GameCore 本來就要水平（`addTrackPlatform` 要求起訖高度相同、高度不回頭），所以每座舊月台照它原本的高度切成自己的水平段是對的。
  - 一次 Undo 全部還原；舊的指令日誌（`stretchStart`／`stretchEnd`）照樣讀得進來，解碼時檢查節點數與 `kept` 的段號。
  - 路線的「選定路徑」照新軌道接起來；接不起來的維持原樣，和 GameCore 對拆掉軌道的路徑一樣。
  - 列車在那段軌道上就拒絕，訊息說是「軌道上有列車」（測試改了期望訊息，是刻意的）。
- **#763、#777 自動待避線**：被抬起的列車放不回去就整個指令拒絕，三條入口（開新線、加開列車、一鍵待避線）都先試算；`feasible` 回報「待避線沒蓋是因為有列車」時，開新線的訊息會說等它開過去再按。#777 的第二處以後在副本上試蓋，指令 ID 照順序產生，和真的套用時一樣（只有上面延後的高度檔一項）。
- **#767、#774 關卡**：
  - 解鎖只看世界的 scenario id（`lesson.N`），存檔帶著它；不是關卡的局全部工具都有，舊存檔不受影響。
  - 10 關的解鎖加起來正好是 8 樣工具；第 10 關說「過了這關，所有工具都歸你」是對的。
  - 貨運：第 8 關以前車站面板與路線卡都不顯示（`showsFreight`），一鍵雙線與 X 型渡線在第 5 關以前不顯示。
  - 入門不算成就（`checkAchievements` 多了 `lesson == nil`）。
- **#781**：最後一步不自己往下走，只有「完成」能結束教學（決策 177），iPad 與手機都有測。
- **#779 關卡計時的隱私**：
  - 只記每關的星數、前景的秒數、過關時的秒數、停在引導第幾步（只寫步數，不寫內部 id）、開始幾次。沒有名稱、位置、裝置識別或時間戳記。
  - 只存在裝置上（`LauncherPreferences`），只在玩家按「回報問題」時寫進那則訊息，送出前看得到全文；說明文字（兩種語言）有寫「每一關花了多久」。
  - App 在背景不計時（`setActive` 停表），回到開始畫面、換局都停表。
  - 入門的解鎖不會漏到自由模式（`allows(_:)` 只看這一局的 lesson）。
- **#769、#772 拉近交給 3D**：交回只給「拉近交接開的 3D」，而且只在拉遠、越過 max(960 m, 開啟距離 × 1.2) 那一下；按鈕開的 3D 永遠不交回。建造工具拿著、教學進行中都不交接。判斷在 `Map3DHandoff`，有 Linux 測試。
- **#771 2D 的種子道路**：字典走訪之後照鍵排序，決定論；實景地圖不畫；MapView 每一局換 identity（`.id(ObjectIdentifier(session))`），不會留著上一局的道路。
- **#759**：寬度上限是純函式，有 Linux 測試。
- **#784**：`-lesson-stars` 只在 Debug 加 `-ui-testing`、寫進每次啟動都清掉的測試資料夾；UI 測試 target 連結 GameCore 與 GamePresentation 只拿關卡地圖的座標，不送指令。
- **3D（#764、#765、#768、#770、#776）**：新加的程式沒有用亂數或時鐘，走訪的都是陣列或排序後的鍵。畫面沒有看。
- **決策 266–274 與文件**：`python3 tools/golden-checks/doc_numbers.py --check` 差異 0（存檔 63、fixture 67、golden schema 74、golden 77、replay 9、最後的決策 274）；ARCHITECTURE 有 266–274 各一節，OVERVIEW §9 的索引每一號都在，內容和程式對得上（只有第三節第 6 項那一句）。附註裡「ARCHITECTURE 沒有 203」是更早就有的（索引寫「141、150、203 曾保留但沒有使用」）。

## 六、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 第三節第 1 項的測試在 `origin/main` 失敗（296 對 148），修正後通過。
  - `LineFeedbackTests`、`LessonTests`、`ReleaseUIFixesTests`、`TutorialSessionTests`、`AutoServiceTests` 全部通過（0 失敗）。
  - `doc_numbers.py --check` 差異 0。
- **UNVERIFIED — 交給 CI 與實機**：
  - 第三節第 2、4、5 項是 App 的 SwiftUI，只有 `ios-build.yml` 會編譯；座位圖換行後的樣子、換局後 3D 是不是新的場景，要在實機看。
  - PR 的 GamePresentation tier。
- 72.1、full lane 與 Swift CI 的時間與結果，是從 GitHub 公開的 Actions 頁面讀的（不登入看得到摘要與 annotation，看不到 log）。

## 七、#231 與通知（這個 session 發不出去，請轉貼）

- 開工的登記：存檔版本、決策編號、golden schema 都「不動」；branch `claude/pr755-784-review`。
- 開 PR 後：PR 號、這份交接的路徑、發現 15 項、修 6 項（其中 1 項是診斷、1 項是文件）、延後 10 項。

## 總表

長按那一項兩邊都算：加了診斷（修），根因還要等下一次紅（延後）。所以「修」加「延後」比「發現」多 1。

| | 發現 | 現在修 | 延後 |
| --- | --- | --- | --- |
| GameCore | 0 | 0 | 0 |
| GamePresentation 與 App | 9 | 4（需求燈只數這條線、座位圖換行、繼續玩會繼續、3D 快取分局） | 5（多處待避線的高度檔、整平時的轉乘乘客、3D 快取的記憶體與先蓋、需求燈的定員、`-lesson-stars` 的檔名） |
| UI 測試與 CI | 4 | 1（長按的診斷 trace） | 4（main 的 full lane 紅、長按的根因、72.1 沒有自己的綠 full lane、Swift CI 時間） |
| 文件 | 2 | 1（決策 266 的 n/9） | 1（72.1 沒記進 PLAYER_FEEDBACK） |
| **合計** | **15** | **6** | **10** |
