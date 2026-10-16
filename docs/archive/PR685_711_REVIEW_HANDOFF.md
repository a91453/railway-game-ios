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
