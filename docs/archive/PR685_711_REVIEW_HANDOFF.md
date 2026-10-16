# 交接：PR #685–#711 的審查與修正、上兩輪留下的 17 項、CI 時間

Session：https://claude.ai/code/session_01EsozfWmDmXd6Tp2f4fzExd（2026-10-16），由派工 session_01AaAj4wvJMxJQuLWAoYu6S8 派出。從 `main` 878adaf（#708 的合併）開始。上一輪 #647–#684 見 [`PR647_684_REVIEW_HANDOFF.md`](PR647_684_REVIEW_HANDOFF.md)。

- 存檔版本、決策編號、golden schema 都沒有用到。
- GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改。
- 三個 PR：
  - `claude/pr685-711-review`：這份交接，加上 GamePresentation 與 App 的修正（第三節）。
  - `claude/ui-test-demo-clock`（#716）：除錯啟動參數 `-demo-at HH:MM`，三支 UI 測試不再等時鐘（第九節）。
  - `claude/ci-shard-balance`：`swift-shards.sh` 重新分 shard（第九節）。
- GameCore 沒有找到要修的 bug，沒有開 core PR。

做法：

- 開了六個唯讀 agent 分工：
  - #231 的登記與號碼；
  - CI 時間；
  - GameCore（#687、#693、#695、#702、#709、#710）；
  - GamePresentation 與 App（#692、#694、#697、#699、#700、#701、#703、#706、#707、#708、#711）；
  - 3D（#690，以及 #697、#709 的 3D 部分）加上上兩輪的 17 項；
  - UI 測試（#686、#689、#698、#704、#705、#706、#707、#693 的拆分，以及還開著的 #712、#713）。
- 每個發現我都自己讀程式確認。寫得出 Linux 測試的，先在 `origin/main` 跑過、確認失敗，再修。

## 一、合併狀態

範圍 #685–#711 共 27 個號碼，**全部已合併**（`git log origin/main --merges` 每一個都找得到）。#712（時刻列測試）、#713（景點 UI 測試）是別的 session 還開著的 draft，沒有審，只看了它們改什麼，避免重疊。

## 二、`main` 的 CI（2026-10-16）

- `ci.yml` push：最近 10 個完整 run 全綠。
- full lane：最新兩次是紅的：
  - 38878787559：景點、`testHoldingAStationTracesItsBusiestTrips`、`testTheMapExpansionIsNotMistakenForBuilding`、時刻列、手機橫放的教學；
  - 38861445072：月台確認、Settings 三支、時刻列。
- 時刻列測試（`testTheStationBoardsTimesKeepToOneLine`）兩次都紅。根因是它在等遊戲時鐘，由 #716 修（第九節）。
- 景點由 #713 處理。另外三支（地圖擴張、握住車站、手機教學）在 #231 #1518 已派給別的 session，這裡沒碰。

## 三、修的 bug（`claude/pr685-711-review`）

「修改前／修改後」見第八節的對照表。

1. **「刷新紀錄！」顯示成失敗**（#699，`GameLauncher.recordChallengeResult`）：
   - #699 把 `kind: .success` 改成了 `.failure`，看起來是順手改錯，和那個 PR 的主題無關。
   - 玩家破紀錄時，訊息用錯誤的樣式，停留時間也和錯誤一樣長。
   - 改回 `.success`。
   - 測試：`WeeklyChallengeTests.testANewBestIsGoodNews`（新）。
2. **「繼續遊戲」退回最舊的存檔時，把剛讀的那份刪掉**（#699，`SaveLibrary.keepLatestAutosaveInSlot`）：
   - 情境：五格都有存檔，最新的和第 2–5 格都壞了，只有第 1 格能讀。
   - 讀完第 1 格後，壞掉的最新一份移進第 6 格，修剪時刪掉編號最小的，也就是剛讀的第 1 格。
   - 在背景存檔寫好之前，磁碟上沒有一份能讀。如果那次寫入失敗（存檔會壞，可能正是因為空間滿了），或 App 被關掉，這局就沒了。
   - 修法：`keepLatestAutosaveInSlot(sparing:)` 不刪退回去的那一格，改刪下一個最舊的（那幾格本來就壞了）。仍然是五格。
   - 測試：`SaveRecoveryTests.testContinueKeepsTheSlotItFellBackTo`（新）。
3. **快轉時，列車在站間只有一段軌道時還是會跳**（#709，`TrainMotion.swift`）：
   - #709 的備案只看新路徑已經進過的軌道段（`edges.prefix(cursor)`）。
   - 列車在同一個 tick 離站並進入新路徑的最後一段時，GameCore 會把路徑存成空的（`TrainMovement` 用完就清空），所以找不到路，列車就跳過去。
   - 實景地圖上兩站之間常常只有一段軌道，高速時常發生。
   - 修法：把列車現在所在的那段也加進去。
   - 測試：`TrainMotionTests.testATrainGlidesOnThroughACallOntoAOneEdgePath`（新，每格一站）。
4. **3D 區塊的範圍沒有算進行道樹、路燈、電線桿**（上一輪第四節，#679；`Map3DScene.Builder.chunks()`）：
   - 區塊範圍只算地面、建物和陰影，最高只到 0.4 m，但路燈有 8.9 m 高。
   - 區塊被判定在畫面外時整個不畫，所以桿子頂端還在畫面裡就被裁掉。
   - 只有道具的區塊也會被整個丟掉。
   - 修法：`Map3DInstance.bounds(in:)` 用模型的範圍乘上擺放的轉換，算進區塊範圍。
   - 測試：`Map3DNightAndGroundTests.testAChunksBoxHoldsItsProps`（新）。
5. **3D 屋頂在 18:00 一下子變暗**（不是 #690 造成的，#690 加上夜晚之後比較明顯；`Map3DLighting.init(minute:)`）：
   - 光的方向在 18:00 從低低的西邊太陽，一步跳到頭頂的月亮，兩邊的強度差不多。屋頂的綠色從 0.334 掉到 0.274，06:00 反過來。
   - 修法：在 06:00、18:00 前後各半小時內，光的方向從太陽慢慢轉到月亮（或反過來）。
   - 測試：`Map3DNightAndGroundTests.testARoofsLightHasNoStepAtDawnOrDusk`（新）。
6. **OpenStreetMap 的鳴謝說它提供了「台鐵示範的側線」**（上一輪第四節）：
   - 北端留置線是示範自己放的，只有宜蘭、蘇澳新的側線來自 OSM。
   - 改成「台鐵示範宜蘭、蘇澳新側線的位置」；英文版同樣改。
   - `TRADemo` 的註解「two depots」也改成三個。
   - 測試：`RealRailwaysTests.testEverySourceIsCredited` 加了一個斷言。
7. **3D 地圖舊的建置可能蓋掉新的場景**（上一輪第四節；`Map3DPreviewScreen.swift`）：
   - `.task(id:)` 取消時不會取消 `Task.detached`，比較慢的舊建置可能晚到，蓋掉新的。#690 讓高度檔一到就重建，#697 讓 3D 地圖可以開著過好幾週，這種情況更容易發生。
   - 修法：指定場景前先檢查 `Task.isCancelled`。
   - 這是 App 的 SwiftUI，寫不出 Linux 測試，**UNVERIFIED LOCALLY**。

## 四、沒修，只回報

### 這一輪

- **「升級為複線」在已經部分是複線的路段上也出現**（#695，`TrackUpgrade.swift` `canDoubleSelectedTrack`）：
  - 只檢查點的那一點旁邊有沒有軌道，但整段路（到道岔為止）可能已經有一段是複線。
  - 按下去會被拒絕，理由是一般的「軌道形狀不合」或 4 m 間距，不是真正的原因。
  - 世界不會改變，原子性是對的。
  - 只是使用體驗：要正確處理得把整段路逐段檢查，改動不小，留給 #695 的後續。
- **沒有道岔的環形軌道升級成複線**（#695）：只讀了程式，可能被拒絕，或在同一個點放兩個渡線。要建彎道才能測，沒證實。
- **狀態列在破產倒數時還是會變寬**（#711，決策 251；`HUDView.swift` `balance`）：
  - 挑戰模式現金變負時出現「破產倒數 30 天」，英文版約寬 140 pt。天數從兩位數變一位數時寬度也會變。
  - 小手機上可能換排法，按鈕就移位了。
  - 另外 `showsSeconds` 在 600 倍以上時，到整分會讓空間縮回來。
  - 這是版面設計，交給美術 session。
- **景點標記的計算量**（#701，`MapAttractionMarks.swift`）：
  - 每次世界改變，每個在畫面內的景點都算一次星等（`hotelsNear` 掃過所有建物），每個顯示的標記再找一次服務車站。
  - 214 個景點本身沒問題，但全島地圖會隨建物數量變慢。沒有量到實際卡頓，沒改。
- **3D 牆面的亮窗**（#690，`Map3DShaders.metal`）：
  - `plane` 是 `[[flat]]`，同一面牆的兩個三角形取不同角的值。`plane/4` 剛好落在整數上時，對角線兩邊的窗戶排法不同。
  - 只是靜態的瑕疵，要在裝置上看。
- **3D 地圖開著時跳出月底報表**（#697）：`fullScreenCover` 上面再出現 sheet，SwiftUI 可能吃掉它。要在 Simulator 上看。
- **UI 測試裡的固定等待**：這些不是這一輪造成的，也還沒有紅過，沒有逐一改。之後動到這些檔案時一起改。
  - `sleep(1)`：`StartSaveFlowSmokeTests` 268／355／430、`TutorialUITests` 168／211、`TutorialJourneyUITests` 115／165／444；
  - 出現後立刻問 `isHittable`：`ToolbarSmokeTests` 60／219、`MapInteractionTests` 301／914／1004；
  - 先 `app.swipeUp()` 再找元素：`MapInteractionTests` 31／108／1142／1151。
  - 教學測試要動的話，會多跑 iPad job。

### 上兩輪的 17 項

| # | 項目 | 現在 | 處理 |
| --- | --- | --- | --- |
| 1 | 狀態列寬度 | #711（決策 251）修了 | 完成；破產倒數見上面 |
| 2 | #644 跟隨列太窄時超出 | #711 大致修了 | 完成 |
| 3 | #638 Advanced 開關的 accessibility frame | 還在 | 要在 Simulator 上看 |
| 4 | #638 月台測試依賴真實地形 | 還在 | 測試問題，低 |
| 5 | `map.style`（`TutorialJourneyUITests.swift:417`） | 還在，無害 | 之後動到那個檔案時一起拿掉 |
| 6 | `unknownLinePattern` 的「pattern #3」 | 還在 | 和別處的「停站模式 N」一致，保留 |
| 7 | #657 坡道上切開軌道的錯誤訊息 | 還在 | 低；要把 GameCore 算切點的函式公開，工具才能共用 |
| 8 | #658 教學收合卡片 | #707 修了 | 完成 |
| 9 | #659 Advanced 開關沒反應 | 測試仍然點偏一點 | 要在 Simulator 上看 |
| 10 | #680 從清單底邊開始拖 | 還在（`ToolbarSmokeTests` 349／351） | 測試問題 |
| 11 | 3D 深度精度（反向 Z） | 還在 | 要在裝置上看 |
| 12 | 3D 道具沒算進區塊範圍 | **這裡修了**（第三節第 4 項） | 完成 |
| 13 | 3D 預覽的統計只有英文 | 刻意的（決策 229） | 保留 |
| 14 | `.task(id:)` 的舊建置 | **這裡修了**（第三節第 7 項） | 完成 |
| 15 | `RunSpacing.catches` 用 `Double` | 還在 | 實際上是決定性的，保留 |
| 16 | 台鐵示範北端側線的鳴謝 | **這裡修了**（第三節第 6 項） | 完成 |
| 17 | CI 的 Swift 6.4.1、hook 和 CLAUDE.md 寫 6.4.0 | 還在 | 低；之後 CI 換版本時 hook 和 CLAUDE.md 一起改 |

另外：#632 拖曳時工具變淡卡住，上一輪已改成換工具或面板時恢復，現在只剩極少見的情況。沒在用的 String Catalog key 要在 Xcode 匯出才查得到，沒有重查。

## 五、審查後判定不成立

- **#702 的 `advance(n)` 等於 n 次 `advance(1)`**：
  - 測了五種情境：快車跟在慢車後面、單線兩端對開、站內停車加對向車、真實班次混著沒有班次的路線、同一分鐘內停站。
  - 每種情境用五種分段方式（7、13／47／1／59、17／3／600／29、60、600 秒），從整分和第 3、5、13、25、31 秒開始。
  - 每個分段點的列車和 `spacingAllowances` 都一樣。
- **#700 的色帶除以零、長度為零**：都有防護。環形路線的色帶偏在軌道一邊，是設計如此。同一條軌道兩個方向的路線各在一邊。
- **#699 的自動存檔**：
  - 壞掉的最新一份是移走，不是覆蓋。
  - 全部都讀不了時，不移動也不寫入任何檔案。
  - 比這個版本新的存檔（`.tooNew`）會被濾掉。
  - 匯出時帶的新聞是可省略的欄位，舊版會略過。
- **#690 地面區塊的接縫**：讀過的區塊和高度檔，在角上算出的高度完全一樣。

## 六、存檔、遷移與 GameCore 檢查

- **存檔 63（#702，決策 248）**：
  - `currentVersion` 是 63；`SaveFixtures/v63-spacing-allowances.json` 在，被 `SavedGameTests` 的迴圈和 `RunSpacingMinuteTests` 讀。
  - 讀檔時檢查：照列車排序、不能重複、`left` 不能是負的、ID 小於 `nextTrainID`。
  - 62 版沒有這個欄位。在某分鐘第 25 秒存的世界，拿掉這個欄位再讀回來，接下來 12 分鐘的結果完全一樣。
  - 存了再讀回來，和原本相等。
- **#695 複線（決策 247）**：
  - 在副本上做，失敗時世界不變（測過）。
  - 反向的軌道段，控制點和豎曲線都跟著對調；月台的位移對應正確。
  - X 渡線在坡道上會被拒絕；渡線放不下時說「沒有空間」，其餘照建。
- **#710 台鐵車款（決策 252）**：加速度換算 E200 1256、E500 1657、R100 583、R200 920（單位：千分之一 km/h 每秒），車長和代碼都對。
- **#693、#687** 的逐秒程式已經被 #702 取代。

## 七、審查過、沒有問題（摘要）

- **GameCore**：#687、#693、#702、#710；#695 除第四節兩項。
- **GamePresentation 與 App**：
  - #692、#694、#703、#706、#707、#708；
  - #697 除第四節「月底報表」；
  - #699 除第三節第 1、2 項；
  - #700、#701 除第四節的計算量；
  - #711 除破產倒數。
  - 新的玩家文字兩種語言都只說效果。
  - 沒有找到 Xcode 和 Linux 的編譯差異：`import UIKit`、`NSString.size` 只在 App 裡；`DateFormatter` 在 Linux 上也能用。
- **3D**：#690 除第三節第 5 項（舊問題）和亮窗；`addPool` 用 UInt32 索引；夜窗表 384 bytes，和 `Map3DUniforms` 一致；跟隨鏡頭是緩動，不會衝過頭。
- **UI 測試**：
  - #686、#689、#706、#707 修的是根因；
  - #704 好一點，但還是點固定位置；
  - #698、#705 是治標，由 #716 取代。

## 八、修改前失敗／修改後通過

| 項目 | 測試 | `origin/main`（878adaf） | 修正後 |
| --- | --- | --- | --- |
| 1 | `WeeklyChallengeTests.testANewBestIsGoodNews` | 失敗：`.failure` ≠ `.success` | 通過 |
| 2 | `SaveRecoveryTests.testContinueKeepsTheSlotItFellBackTo` | 失敗：剩下的都是 `autosave-2…6`，第 1 格被刪了 | 通過 |
| 3 | `TrainMotionTests.testATrainGlidesOnThroughACallOntoAOneEdgePath` | 失敗：跳了 50 次 ≠ 0 | 通過 |
| 4 | `Map3DNightAndGroundTests.testAChunksBoxHoldsItsProps` | 失敗：路燈 y 8.86 超出區塊範圍（最高 0.4） | 通過 |
| 5 | `Map3DNightAndGroundTests.testARoofsLightHasNoStepAtDawnOrDusk` | 失敗：0.274 ≠ 0.334 ±0.01（18:00） | 通過 |
| 6 | `RealRailwaysTests.testEverySourceIsCredited`（加的斷言） | 失敗：兩種語言都沒有提到宜蘭、蘇澳新 | 通過 |
| #716 | `DemoAtTests`（新，3 個） | 新功能，main 上沒有這個 API | 通過 |
| 7 | 寫不出 Linux 測試（SwiftUI 的 task 取消） | — | 交給 `ios-build.yml` 編譯 |

## 九、CI 時間

### Swift（`ci.yml` push）

一次 run 從第一個 job 開始到最後一個 job 結束（`main` 最近 10 個完整 run，38856199600–38878358538）：

| | 上一輪 | 這一輪（優化前） |
| --- | --- | --- |
| 中位數 | 15.8 分 | **18.2 分** |
| 最長的 shard | rest 15.9 | **campaigns-12 17.8**（10 次裡 9 次最後結束） |
| 第二長 | — | campaigns-14 16.6 |
| 最短 | — | campaigns-16 9.8 |
| 建置步驟 | 2.3 | 2.4 |

- 原因：#702（決策 248）讓高鐵一天又變快，campaigns-16 空出來了；但台鐵一天（2.8 分）還在 campaigns-12，高鐵批次測試（1.5 分）在 campaigns-14。
- #718（`claude/ci-shard-balance`）：把 `TRADemoDayTests`、`HighSpeedDemoBatchTests` 移到 campaigns-16。
  - 本機 `swift-shards.sh run campaigns-16`：測試共 719 秒（批次 112、高鐵一天 404、台鐵一天 204）。
  - #718 自己的完整 tier（commit 5ddead3）：一次 run **15.7 分**（優化前中位數 18.2 分）。
  - 各 shard：rest 15.7（最長）、campaigns-8 15.3、campaigns-1 15.2、campaigns-14 15.0、campaigns-12 10.9、campaigns-16 10.2。
  - 只有一次的數字；合併後要再看 main 上的幾次。
- 改 CI 腳本會跑完整一層（19 個 job），推之前和合併 session 排了名額。

### iOS full lane（`ios-build.yml`，`workflow_dispatch`）

#693 把 iPhone 的 UI 測試拆成兩個 job 之後，**已經在 40 分以下**，不用再拆：

| | 拆之前（10 個 run） | 拆之後（4 個 run） |
| --- | --- | --- |
| iPhone UI 步驟中位數 | 44.3（最多 63.8） | 23.5 ／ 24.4（兩個 job，最多 28.9 ／ 29.6） |
| 最長的 job | 59.1（最多 77.9） | 36.6（最多 41.2） |
| iPad 教學 | — | 16.7 |

- 每三小時最多多佔一台 macOS（上限 5 台），這是 #693 加的。
- 每個 class 的合計（綠的 run 38849566648，紅的寫在括號裡）：
  - 第二個 job：`MapInteractionTests` 12.6（16.7）、`RealWorldMapUITests` 9.2（11.2）；
  - 第一個 job：`StartSaveFlowSmokeTests` 7.7、`LineRoutePreferenceUITests` 4.3、`TutorialUITests` 3.2、`SettingsUITests` 3.1、`ShellLayoutUITests` 3.0。
- 最慢的單支測試：

| 測試 | 秒 |
| --- | --- |
| `TutorialJourneyUITests.testTheWholeTutorialOnAnIPad` | 157–262 |
| `LineRoutePreferenceUITests.testALineLegCanSelectAPhysicalPlatform` | 105–204 |
| `TutorialJourneyUITests.testTheWholeTutorialOnAPhoneOnItsSide` | 119–161 |
| `RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` | 123–148 |
| `StartSaveFlowSmokeTests.testTheTrainAndTypeMenusStayStillAndChooseWhileTheClockRuns` | 116–130 |
| `RealWorldMapUITests.testTheHighSpeedDemoOpensOnTheMapAndRuns` | 103–122 |

- 沒有測試被重試。

### PR gate

- UI 步驟中位數 7.1 分（4.8–11.1），上一輪 7.2，沒有變。
- 報告的「一支 88 秒」是 gate 裡的 `RealWorldMapUITests.testARealWorldGameStartsFromAPlaceAndIsSavedAsOne`：88.3 秒（38876591223），失敗時 169.5 秒。full lane 裡 44–53 秒。

### 不穩定的 UI 測試：#716

根因是測試在等遊戲時鐘。示範地圖從 00:00 開始，06:00 才發車，所以測試得等時鐘走到某個時段，而 Simulator 跑多快、剛好讀到哪一分鐘，每次都不一樣。

#716 加了除錯參數 `-demo-at HH:MM`：示範地圖在背景先跑到那個時刻再打開，加上 `-ui-testing-paused` 就是打開時已暫停。

| 測試 | 以前 | #716 |
| --- | --- | --- |
| 時刻列 | 最多等 120 秒到 07:00，沒車再走 90 秒（#712 改成最多約 270 秒的迴圈） | 07:00 打開並暫停；`DemoAtTests` 證明每一站都有車 |
| 列車卡片 | 從 00:00 開始，約 36 秒後才發車，只觀察 60 秒 | 06:30 打開，車在跑 |
| 狀態列寬度 | 固定 50 秒 | 23:58 打開，看到 3 個日期就停 |

- 手動跑 `only_testing`（run 38888496446）三支都通過。和之前 full lane（38849566648、38878787559、38861445072）比：

| 測試 | 之前 | `-demo-at` |
| --- | --- | --- |
| 時刻列 | 失敗 77.5 秒、失敗 118.1 秒 | **通過 29.9 秒** |
| 列車卡片 | 33.2／43.3／50.6 秒 | 81.2 秒 |
| 狀態列 | 78.7 秒 | 93.3 秒 |

- 列車卡片變慢：它是那次 run 的第一支，包含 App 冷啟動約 12 秒；06:30 的世界列車多，每次快照要 1.5–2.5 秒。好處是不用再賭 1 號車剛好在 60 秒內發車。
- 狀態列跑滿了 50 秒：6000 倍下 Simulator 看不到第三個日期。#716 的 91ec683 改成日期變過一次、而且看了 20 秒就停。
- 主要的收穫是時刻列不再失敗（兩次 full lane 紅燈都有它）。整體秒數要看下一次 full lane。

### 還可以做（沒做）

- **教學全程**（手機約 2–3 分、iPad 約 3–4 分）：第 16 步就直接快轉，或從已經過了第一天的世界開始，可以省約 60–180 秒。要動教學的檔案，會多跑 iPad job。
- **實景**：加一個像 `-demo-layout realWorld` 的參數，直接打開某個地點，可以省掉開始畫面和資料載入，每支約 10–20 秒。另外 `RealWorldMapUITests:144` 有兩次固定 5 秒的等待。
- **示範地圖**：`MapInteractionTests` 有 5 支從開始畫面點進示範，可以改用 `-demo-layout`，每支約 3–5 秒。
- **高鐵示範**：Debug 版要建好幾分鐘。可以在 Linux 上驗證建置，UI 測試只看「建置中」和地圖打開。

## 十、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - 三個 branch 都 `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 第八節每個測試，都在把修正拿掉的 `origin/main` 原始碼上跑過、確認失敗；修正後通過。
  - 修正後通過：`SaveRecoveryTests`、`AutosaveSlotsTests`、`WeeklyChallengeTests`、`TrainMotionTests`、`Map3D*Tests`（77 個）、`RealRailwaysTests`、`DemoAtTests`。
  - `swift-shards-selftest.sh` 通過。
- **UNVERIFIED — 交給 CI**：
  - App 的編譯（第 7 項、#716）；
  - #716 的三支 UI 測試（`only_testing`）；
  - 完整的 Swift tier。
- **UNVERIFIED — 要在裝置上看**：3D 的樣子（第 4、5 項）。

## 總表

| | 發現 | 修了 | 沒修 |
| --- | --- | --- | --- |
| 上兩輪的 17 項 | 17 | 這裡修 3（道具範圍、舊建置、北端鳴謝）；別的 PR 已修 3（狀態列、跟隨列 #711，教學卡片 #707） | 11 |
| GameCore（這一輪） | 2 | 0 | 2（升級複線的提示、環形，都是 GamePresentation 的工具；GameCore 本身沒有 bug） |
| GamePresentation 與 App（這一輪） | 9 | 4（新紀錄、自動存檔、滑行、18:00 的光） | 5（破產倒數寬度、景點計算量、亮窗、月底報表、UI 測試的固定等待） |
| CI 與 UI 測試 | 3 | 2（等時鐘的三支測試 #716、shard 分配） | 1（教學與實景的啟動，第九節「還可以做」） |
| **合計（這一輪新發現）** | **14** | **6** | **8** |

另有判定不成立的項目（第五節），不計入。

## 十一、清理：現在修的、延後（等穩定）的、已經不成立的（2026-10-16）

審查回報清理 session（session_01FUXNvfnNmoSMf58pgakpsF，派工 session_01AaAj4wvJMxJQuLWAoYu6S8 開出）在 main 8cef1a4 逐項重看第四節。作者 2026-10-16 說：「牽涉小的話現在修，牽涉大等穩定再修」。

分類的標準：
- **小**：只動 App 或 GamePresentation、局部、不改存檔與 GameCore 行為、不動 golden／replay。
- **大**：動 GameCore 規則、存檔格式、效能架構、跨畫面的版面、要美術方案的、3D 渲染管線，或必須先在 Simulator／裝置上確認問題存在的。
- 拿不準的歸大。

### 現在修了

| 項目 | PR | 玩家感受到的改變 |
| --- | --- | --- |
| 「升級為複線」在部分已是複線的路段上 | #728 | 預覽直接說「這段路有一部分已經是複線」，請玩家選「只有這一段」。以前只說「軌道形狀不合」；第二條在另一側時甚至會蓋成三條。 |
| 沒有道岔的環形軌道升級成複線（原本「沒證實」） | #728 | 用六段的環線證實了：以前一樣只說「軌道形狀不合」，不會在同一點放兩個渡線，世界也不變。現在說「這是沒有道岔的環線」，請玩家一段一段升級。 |
| UI 測試裡的固定等待（`sleep(1)`、出現後立刻問 `isHittable`、先 `swipeUp()` 再找） | #730 | 沒有。測試比較不會亂紅。 |
| #680 從清單底邊開始拖（上兩輪第 10 項） | #730 | 沒有。拖曳的兩端夾在清單帶裡。 |
| `map.style`（上兩輪第 5 項） | #730 | 沒有。 |

### 延後（等穩定）

| 項目 | 為什麼延後 | 建議做法 | 預估影響範圍 |
| --- | --- | --- | --- |
| 破產倒數時狀態列變寬（#711，決策 251） | 需要美術方案。牽涉 iPhone 和 iPad 的狀態列排法，也牽涉 `showsSeconds` 在 600 倍以上時的整分縮回。 | 美術 session 決定倒數放哪裡。可以疊在金額下方，或做成獨立的小膠囊。再把「破產倒數 9／30 天」兩種位數、兩種語言都加進 `StatusBarWidths` 的最寬文字，`HUDView.balance` 用 `WidestTextRoom` 保留空間。 | `HUDView.swift`、`StatusBarWidths.swift` 與測試、`ShellLayoutUITests` 的寬度斷言、`docs/UI_THEME.md` |
| 景點標記的計算量（#701，`MapAttractionMarks.swift`） | 效能架構，而且還沒量到實際卡頓。 | 先在全島地圖用 Instruments 量。如果真的慢，把每個景點的星等與服務車站，按 `worldRevision` 記在 GamePresentation：建物或車站改變才重算。`hotelsNear` 改成用格子索引，不要掃所有建物。 | `MapAttractionMarks.swift`、`TourismText.swift`、新的記憶結構與 Linux 測試 |
| 3D 牆面的亮窗（#690，`Map3DShaders.metal` 的 `plane [[flat]]`） | 3D 渲染管線，要在裝置上看。 | 在 vertex 端讓同一面牆的四個頂點帶一樣的 `plane`（建模時寫進 instance 資料），或在 fragment 用 `floor(plane/4 + 0.5)` 避開整數邊界。改完在 iPhone 上拍同一角度前後對照。 | `Map3DShaders.metal`、`Map3DModels.swift`（牆的頂點資料）、`Map3DTests` |
| 3D 地圖開著時跳出月底報表（#697） | 要先在 Simulator 上確認 sheet 是不是真的被吃掉。報表的時機牽涉月報、年報、挑戰結束三種。 | `ContentView` 的三個 `onChange`（月底、年底、挑戰結束）在 `screen.showsMap3D` 時先不設 `screen.panel`。加一個 `onChange(of: screen.showsMap3D)`：關掉 3D 時，如果有 `pendingReport` 就打開（和現有「關掉面板後 0.5 秒」同一套）。另外加一支 UI 測試：開 3D、快轉過月底、關 3D，看報表有沒有出來。 | `ContentView.swift`、一支新 UI 測試（full lane） |
| `TutorialJourneyUITests` 115（第二次縮小之後的 `sleep(1)`） | 等的是地圖鏡頭的縮放動畫，App 沒有給 UI 測試讀得到的狀態。要改 App。 | UI 測試時讓地圖的 accessibility value 帶鏡頭比例（和 `map.stations` 一樣只在 `-ui-testing` 時有）。測試等它連續兩次一樣。 | `MapView.swift`（只在 UI 測試時）、`TutorialJourneyUITests`、iPad 教學 job |
| #638 Advanced 開關的 accessibility frame（上兩輪第 3 項） | 要在 Simulator 上看。線路面板 `Form` 裡的 `Toggle`（`LinesPanel.swift` `advancedSection`）整列的框只到 x≈582，開關畫在 x≈735（run 38641908091）。如果框真的不對，VoiceOver 也會受影響，要改面板的版面。測試已經改點列裡的 switch 本身（`toggle.switches.firstMatch`），所以不會再紅。 | 用 Accessibility Inspector 看那一列的框，和畫出來的開關位置是否一致。不一致的話，查面板寬度（#626 之後側欄變窄）是不是讓 `Form` 列的框沒有跟著版面更新。 | `LinesPanel.swift`、可能還有側欄的寬度計算 |
| #638 月台測試依賴真實地形（上兩輪第 4 項，`RealWorldMapUITests`） | 要重新設計測試的地點，牽涉實景地圖的鏡頭和資料，不是局部改動。 | 讓測試讀 App 在 UI 測試時寫出的「平地位置」（像 `map.expansion.tiles`），或改用 demo 地圖測月台工具，把實景地圖的部分留給只看能不能打開的測試。 | `RealWorldMapUITests`、可能加一個 UI 測試專用的 accessibility value |
| #657 坡道上切開軌道的錯誤訊息（上兩輪第 7 項） | 要把 GameCore 算切點高度的函式公開，讓工具共用。是 GameCore 的 API 改動。 | 把 GameCore 算切點 chainage 的函式改成 `public`。工具改用它來判斷「轉轍器不能在變坡處」。行為不變，golden 不動。 | `Sources/GameCore/Railway/`（只改可見性）、GamePresentation 的切軌工具與測試 |
| 3D 深度精度（反向 Z，上兩輪第 11 項） | 3D 渲染管線，要在裝置上看。 | 投影矩陣改成反向 Z（near→1、far→0），深度比較改成 `greater`，深度格式維持 `depth32Float`。 | `Map3D` 的 renderer、shader、相機 |
| CI 用 Swift 6.4.1，hook 和 CLAUDE.md 寫 6.4.0（上兩輪第 17 項） | 會改到每個平行 session 的開機環境（重新下載工具鏈）。現在很多 session 同時在跑，等穩定再一起換。 | `session-start.sh` 的版本改成 6.4.1。CLAUDE.md、`install-swift-linux.sh` 註解裡的 6.4.0 一起改。下載網址已確認存在（`swift-6.4.1-RELEASE`）。 | `.claude/hooks/session-start.sh`、`CLAUDE.md`、`.github/scripts/install-swift-linux.sh` 的註解 |
| #632 拖曳時工具變淡卡住（剩極少見的情況） | 上一輪已經修了換工具和開面板的情況。剩下的是地圖 view 在拖曳中被拆掉，重現要 Simulator。 | 在地圖 `UIViewRepresentable` 的 `dismantleUIView` 把 `isDrawingUnderTools` 改回 false。 | `MapView.swift`、`ContentView.swift` |
| 沒在用的 String Catalog key | 要在 Xcode 匯出才查得到，Linux 上做不到。 | 在 macOS 上用 Xcode 的「Export Localizations」，看標成 stale 的 key，一次清掉。 | `Localizable.xcstrings` |

### 不成立或保留

- 上兩輪第 1、2、8、12、14、16 項：已經修好（見第四節的表）。
- 第 6 項 `unknownLinePattern` 的「pattern #3」：和別處的「停站模式 N」一致，保留。
- 第 9 項 #659 Advanced 開關 390 ms 的觸控沒反應：已經查清楚，不是 App 的問題。清單還在減速時，點一下只會讓它停住，這是 iOS 本來的行為，玩家也一樣。兩次失敗都發生在最後一次短拖曳的一秒後；沒有拖曳的五次啟動，每次都一點就切換。測試現在先等清單停穩才點（`ToolbarSmokeTests` `setAdvanced` 的 `waitUntilSettled`）。
- 第 13 項 3D 預覽的統計只有英文：刻意的（決策 229），保留。
- 第 15 項 `RunSpacing.catches` 用 `Double`：實際上是決定性的，保留。
- 這一輪 `TutorialJourneyUITests` 444 的 `sleep(1)`：在 main 上已經不在了（現在那裡是點擊後的 0.5 秒，屬於點擊本身的節奏）。

### 第二批：`docs/HANDOFF.md` §7.1（舊審查交接 #200–#684 留下的 30 項）

派工 session 在第一批之後加派。規則一樣。標「待查」的先確認是不是刻意的設計：是的話，在原決策補一節「後來」說明理由後結案，不改程式。

**現在修了**

| 項目 | PR | 玩家感受到的改變 |
| --- | --- | --- |
| 「前車誤點」沒寫自己誤點幾分（PR526_626 B8） | #735 | 看板寫「前車誤點 4 分」。 |
| 待避線的號誌站名可能重複（PR401_525） | #735 | 拆掉或關掉車站之後，新的號誌站不會和現有的同名。 |
| `LineLossFix.isAffordable` 不看無限資金（PR401_525） | #735 | 沒有。這個函式只有測試在用，App 的按鈕不受影響；直接拿掉。 |
| 車隊總覽、列車控制每次重繪都重算列車狀態（U4） | #737 | 車隊總覽比較不卡，字一樣。 |
| 描線時每次重繪都跑一次最短路徑（U7） | #737 | 描真實鐵路時拖曳比較順。 |
| 描真實鐵路的總價沒有自己的測試（決策 245 的缺口） | #738 | 沒有（補測試，main 的行為本來就對）。 |
| `meshy.mjs pack` 覆寫 index.json，丟掉 N700ST 的設定（PR319_400 §6-1） | #738 | 重新打包模型時，高鐵的顏色和陰影不會不見。 |
| 解除配屬的貨運列車，車上還有貨時被當成客車顯示（PR319_400 §4-7） | #739 | 撤下的貨車照實寫車上還有幾噸，不是「載客 0」。 |

**刻意的設計，已在原決策補「後來」結案**

| 項目 | 決策 | 理由（一句） |
| --- | --- | --- |
| 無限資金時，完成訊息寫「$0」 | 200、245 | 決策 200 寫明訊息寫實際付的 $0；預覽在價錢副本上量出的也是 0，兩者一致。審查時試過改成原價，因為和兩個決策不一致，沒有採用。 |
| 貨運載貨中被減節，載貨百分比超過 100%（待查） | 155 | 照參考：條封頂，數字照實，超載用超載的樣式。 |
| 空車回送算進發車數與座位（待查） | 172 | 回送照記一次離站，滿載率才反映空車跑的那一段。 |
| 地價圖層不畫只因臨水而加價的空格（待查） | 111 | 圖層跟著蓋了什麼長大、不跟著地圖大小，全島的海岸線很長。 |
| 手機上只選了起點時，地圖上沒有 ✕（待查） | 136 | 第 4 點的設計：打開細節卡按「清除」，或按「完成」。 |
| iPad CI 偶爾「Unable to find a device」 | — | 交接寫「之後沒再出現；再出現時才做」。條件還沒成立。 |

**延後（等穩定）**

| 項目 | 為什麼延後 | 建議做法 | 預估影響範圍 |
| --- | --- | --- | --- |
| 指令日誌滿 5,000 筆、起點往後移之後，復原歷史沒有跟著截（PR401_525） | 復原歷史是 `GameWorld` 的快照，沒有對應到日誌的位置，要加對應關係。只在暫停中連續記兩千多筆才會遇到，而且只影響回報的重播。 | 記下每個復原快照是在第幾筆日誌之後。日誌起點往後移時，丟掉起點之前的快照（重做也一樣）。 | `CommandLog.swift`、`GameSession` 的 undo／redo、`CommandLogTests` |
| 閒置快轉跨午夜時，飯店住客用預估值（PR401_525） | GameCore 觀光規則。改了會動到閒置快轉和逐分鐘的一致性，以及 golden／replay。 | 快轉在午夜切開：先結算當天，再用實際人數算住客。用 `FlexDispatchTests` 那種「一次推進＝逐分鐘」的測試鎖住。 | `Sources/GameCore/Passenger/Tourism.swift`、GameCore 測試，可能還有 golden |
| 載客量圖層對固定班次的路線，兩個方向、全天都用同一個容量（PR319_400 §4-5） | `SectionFlow` 的容量只按路段、不分方向。要照 `line.runs` 算，得把資料結構改成分方向、逐時。 | `capacities(of:)` 有班次時，改從每班的方向和經過各段的時間累加，結果改成 `[方向][段][時]`。 | `SectionFlow.swift` 與測試、App 的圖層 |
| 建物讀土地的範圍 64 m，小於遊樂園的半對角線約 79 m（PR319_400 §4-8） | 讀土地也發生在指令重播（`PlayerCommandEdit` 的 `readLand`），改範圍會改到重播出來的世界。 | 範圍改成「最大建物的半對角線加淨空」（約 96 m）。同時確認 `ReplayFixtures` 和舊回報的重播不受影響；受影響的話，把範圍記進日誌的 `readLand(reach:)`（它已經有 reach 欄位）。 | `BuildingSession.swift`、`PlayerCommandEdit.swift`、重播測試 |
| 月報的「創新高」只比票收和乘客，沒算貨運（PR319_400 §4-10） | 要新增一種標題（貨運收入創新高），是報表文字的設計。 | `MonthlyHeadline.Item` 加 `.freight`，排在票收、乘客之後；兩種語言的標題、月報測試一起加。 | `MonthlyReportText.swift`、`MonthlyReportTests` |
| 名產店沒檢查是否在已買的地圖區塊（PR319_400 §4-10） | GameCore 規則（觀光商店的建造驗證）。 | 和車站、建物一樣用 `isOwned` 檢查，拒絕時用既有的「這塊地還沒買」錯誤。要考慮舊存檔裡已經蓋在外面的店。 | `Sources/GameCore/Passenger/Tourism.swift`、GameCore 測試 |
| 縮放鈕讓位在 iPad 也會觸發，開 VoiceOver 時沒有別的縮放方式（PR200_290 §4-3） | App 版面，要 Simulator 驗證；`MapView.swift` 也有別的 PR 在改（#724）。 | 判斷條件改成「留給地圖的寬度」或只在手機上生效。開著 VoiceOver 或切換控制時，一律保留縮放鈕，另外給地圖加 `accessibilityZoomIn/Out` 動作。 | `MapView.swift`、決策 123、一支 UI 測試 |
| 拖曳鋪軌時，邊緣捲動區用整張地圖量，被卡片蓋住（PR200_290 §4-4） | App 手勢，要 Simulator 驗證，`MapView.swift` 同上。 | 邊緣區改用扣掉卡片與工具欄 inset 之後的可見區域來量（`MapCover` 已經算好可見區域）。 | `MapView.swift` |
| 城市需求幾乎沒有工作時，某些夜晚完全不成長（PR200_290 §9，待查） | 不是刻意的：權重以千分之一取整到 0。但這是 GameCore 城市規則，改了會動到 golden。 | 權重小於 1 但大於 0 時至少給 1，或改用餘數累積。先用經濟平衡的報告測試量影響。 | GameCore 城市成長、golden |
| 成長動畫在很窄的時間窗裡，仍把讀進的土地當成新建物（PR200_290 §10，待查） | 不是刻意的。只在 23:5x 讀進土地、背景計算跨午夜時發生，只影響動畫。要處理背景計算的取消。 | 天際線的背景計算被取消時，下一次比較改用最後一次完整算完的天際線，不用更舊的。 | App 的天際線計算、`CitySkyline` |
| 城市建物關閉時，出售建物的人可能搬進別棟的方塊（PR200_290 §10，待查） | 不是刻意的，但只有 GameCore API 會碰到（App 的新遊戲兩者都開）。 | 和 #325 的修法一樣，用搬進去之後那棟建物的方塊判斷，也涵蓋城市建物關閉的情況。 | GameCore 城市建物、測試 |
| 固定班次只服務部分方向時，另一方向的乘客一直等（PR200_290 §10，待查） | 不是刻意的，但只有 GameCore API 或示範資料會設定這種班次（平溪線兩個方向都有）。GameCore 乘客規則。 | 沒有班次服務的方向不產生乘客，或讓他們改搭其他路線。 | GameCore 乘客、固定班次、golden |
| 匯入的存檔會解鎖成就（決策 200） | 要升存檔版本（先在 #231 取號）。 | 世界記一個「從匯入來的」旗標，`checkAchievements` 看到就不解鎖；舊存檔缺 key 當作不是匯入的。 | `SavedGame`、`GameLauncher`、新的 SaveFixture |
| 官網 3D 頁的設定用中文名稱存，瀏覽器換語言就不見（PR319_400 §6-2） | 網頁（`Web/CityView`），要在瀏覽器裡驗證，也要讀得回舊的中文 key。 | 存的時候把中文名稱換回英文（`GUI_ZH` 的反查），讀的時候反過來；舊的中文 key 先換成英文再讀。 | `Web/CityView/src/main.js` |
| ARCHITECTURE 裡決策 240 排在其他決策後面（PR647_684 §4） | 現在決策 240 在檔案最後，開著的 PR 都把自己的決策插在「### 240.」前面。移動它會讓那些 PR 全部衝突。 | 等開著、動到 ARCHITECTURE 的 PR 都合併後，把 240 那一段搬到 239 和 241 之間，單獨一個 PR。 | `docs/ARCHITECTURE.md` |
| 把 `BoardingPropertyTests`（624 秒）、`LineDispatchPropertyTests`（602 秒）各拆成兩半（PR647_684 §9） | 改 CI 腳本會跑完整的 Swift tier（19 個 job），要向合併 session 排名額。 | 照 #718 的做法，在 `swift-shards.sh` 的 `classes_of` 把兩個 class 用 `--filter` 的 test 名稱拆成兩組，放到不同 shard，再看兩次 main 的時間。 | `.github/scripts/swift-shards.sh` |
