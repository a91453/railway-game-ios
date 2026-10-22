# 交接：PR #873–#910 審查 A 組

Session：session_01SvQ285hMiSeRsER1EXzfT9，遊戲規劃 session_014rYHMtmqA5bEMkBBuKu6PV 派工，2026-10-21（作者：「開始派session做pr review 到最新 修復bug」）。審查基準 `main` **543770c**（#944 的合併）。#911–#944 是 B 組（session_017M3NJsMXLafGDsSvidGhD6，`PR911_944_REVIEW_HANDOFF.md`）。上一輪是 [PR786_872_A](PR786_872_A_REVIEW_HANDOFF.md)、[B](PR786_872_B_REVIEW_HANDOFF.md)、[C](PR786_872_C_REVIEW_HANDOFF.md)。

- 範圍：#873–#910 之間已合併的 36 個 PR。#900、#901 沒有合併，不在範圍內。
- 修正分成兩個 PR：
  - **GameCore**（`claude/pr-review-a-873-910`）：A1、A2，以及決策 309、315 的「後來」。
  - **GamePresentation、App、文件**（`claude/pr-review-a-873-910-presentation`）：A3–A5、A9，這份文件，以及 HANDOFF §7.1 的一行。
- 存檔版本、決策編號、golden schema 都**不動**；GoldenScenarios、SaveFixtures、ReplayFixtures 都沒有改。
- 以下的 **VERIFIED** 都是在 Linux、官方 Swift **6.4.0**（`/opt/swift`）實際跑過的，不代表 iOS 或實機的結果。
- 做法：每個 PR 讀它的 diff（`git diff M^1 M`）、描述，以及現在 `main` 上的程式。只有能在 Linux 用測試重現的才修，每個修正都附回歸測試，而且先確認那個測試在舊程式上是紅的。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 發現 | **11**：P1 兩個、P2 三個、P3 六個 |
| 已修 | **6**：A1–A5、A9 |
| 延後（附重現與建議） | **5**：A6–A8、A10、A11 |

全範圍的機械檢查（VERIFIED）：

- GoldenScenarios、SaveFixtures、ReplayFixtures：只新增了 `v65-dispatch-pattern.json`、`v66-line-acquisition.json` 兩份 fixture，改了 `SaveFixtures/README.md`。沒有改動任何 golden 期望值，也沒有重錄 replay。
- `Sources/GameCore` 沒有 import Foundation、SwiftUI 或 UIKit。
- `python3 -I tools/golden-checks/doc_numbers.py --check`：0 項差異（存檔 69、fixture 73、golden schema 74、golden 77、replay 9、決策到 328）。
- 每個 PR 新增的相對 markdown 連結都檢查過，只有 A9 那一個連不到。

## 二、發現

| # | PR | 嚴重度 | 發現 | 處理 |
| --- | --- | --- | --- | --- |
| A1 | #890（決策 309） | **P1** | 「第二列晚 N 分」或「兩端對開」的路線改成環線之後，**存檔讀不回**。`setLineRing` 沒有把發車方式改回平均錯開，但解碼要求環線只能平均錯開（`ServiceLine.swift` 的 ring 檢查）。 | **已修**（GameCore PR）：改成環線時，發車方式回到平均錯開，`endLastDispatch`、`opensPair` 也清掉。回歸測試 `DispatchPatternTests.testALineMadeARingSpacesItsTrainsEvenly`；舊程式上兩種方式都紅，錯誤是 "Ring 1 needs three stops or more…"。 |
| A2 | #904（決策 315） | **P1** | 買下的線拆車站拆到剩不到兩站時，`removeStation` 會連線一起拆掉，但沒有註銷 `.acquiredLine` 資產，結果**存檔讀不回**（"An asset record names a acquiredLine that does not exist."）。`removeLine` 有註銷。 | **已修**（GameCore PR）：這條路也註銷資產。回歸測試 `LineAcquisitionTests.testABoughtLineRemovedWithItsStationsWritesItOff`，舊程式上紅。 |
| A3 | #899（決策 313 後來） | P2 | 3D 場景的快取只用 `FocusArea`（3 km 的方格）當 key。附近什麼都沒蓋的時候，場景只涵蓋焦點四周 1.5 km（`margin`），所以同一格裡 2–3 km 外的新焦點會重用舊場景，3D 開在場景外的空地上。這正是 78.1 #3 回報的症狀。 | **已修**（Presentation PR）：加 `Map3DScene.region(world:focus:)` 與 `holds(_:in:world:)`；快取記住場景涵蓋的範圍，新焦點四周沒有半個 margin 時就重蓋。Linux 測試 `Map3DOpenHereTests.testASceneRoundAnotherFocusInTheSameSquareHoldsItOnlyWhenItCoversIt` 重現了前提：同一格、但不在場景裡。App 的快取改了 4 行，**UNVERIFIED LOCALLY**，要等 macOS 的 CI 編譯。 |
| A4 | #875（決策 304） | P3 | 只有班距的真實路線（例如台鐵）在 00:00–05:00 地圖上沒有車（`headwayHours`），車站卡卻寫「約每 20 分一班」。 | **已修**（Presentation PR）：班距只在 `RealTrainTraffic.headwayHours` 內才顯示。回歸測試加在 `RealTrainMotionTests.testAStationsNextTrainsEachWay`。 |
| A5 | #906（決策 314） | P3 | 3D 路線色帶「上面那條線」的判斷，是用 `(edge, start, end)` 完全相同來比。單向的線加入雙向線旁邊時，雙向線的位置與寬度都不變，`LineMap` 會把它的 stretch 合併成一段，蓋過單向線的那一段。結果兩條色帶畫在同一段軌道上，互相閃爍（z-fight）。 | **已修**（Presentation PR）：在一條邊上，每個 stretch 的起點、終點都切開，每一小段只留 ID 最大的線。沒有重疊時，結果和以前完全相同。回歸測試 `Map3DLineBandsTests.testAStretchOverAShorterOneIsCut`。 |
| A6 | #883（決策 306） | P2 | 跟真實時刻表的列車（`followsRealTimetable`）晚點時，`run(of:length:scheduled:)` 拿到的是「到表定時刻還剩幾秒」。這段時間在彎道限速下跑不完，程式就把限速整個丟掉（原本的規則是給真實時刻表本身用的）。結果晚點車用超過彎道限速的速度追時間，違反決策 306 的「最快照車的性能與彎道限速」。 | **延後**，第三節。 |
| A7 | #897（決策 316） | P2 | 實景地圖的載入畫面（決策 307）被「新遊戲」頁蓋住。`RealWorldPicker` 是 `NewGamePicker` 裡面的 sheet，按「在這裡開始」只關掉選地點那一層；載入畫面是 `RootView` 的 overlay，畫在仍開著的「新遊戲」sheet 下面。載入的 1–2 秒裡，玩家看到的是「新遊戲」頁；這時按「空白地圖」，正在蓋的實景世界會被默默丟掉（`guard session == nil`）。 | **延後**：只在 Simulator 看得到，Linux 測不出來。第三節。 |
| A8 | #890（決策 309） | P3 | `setLineRuns` 不會把發車方式改回平均錯開，解碼也接受「有班次、又不是平均錯開」的路線。現在沒有影響（有班次的路線不照發車方式派車），但清掉班次後，舊的發車方式又會回來。 | **延後**：沒有錯誤的結果，只是規則不一致。交給下一個改決策 309 的 session，要不要比照 A1 一起改。 |
| A9 | #907 | P3 | 預覽圖搬到私有庫之後，還有地方指向已經搬走的檔案：`generated-2026-10-14-micro3d/README.md` 連到 `../generated-2026-10-13/index.html`（連結斷了）；5 個 App 檔案的註解寫 `railway-ui-redesign-2026-10-14/s1–s5-*.png`；ARCHITECTURE 第 8493 行寫 `solid-outline.png`。 | **已修**斷掉的連結，改指向該資料夾的 README（Presentation PR）。註解與 ARCHITECTURE 不改：資料夾的 README 第「搬到私有庫」節寫了這些檔案在私有庫的位置。 |
| A10 | #877（決策 305） | P3（效能） | 暫停中，`world` 的 `didSet` 每下一個指令都會呼叫 `refreshNightSkipOffer()`（`GameSession.swift:38`），可能在主執行緒重跑整天的試跑。決策 328 只把 tick 那條路移出主執行緒。 | **延後**：要在實機量才知道多慢。交給決策 328 的效能後續（HANDOFF §7.1「大世界的效能」）。 |
| A11 | #910（決策 318） | P3 | `Map3DSceneKitBuildings.swift`、`Map3DSceneKitPlaces.swift`（約 430 行），以及 `Map3DSceneKit.assets` 的大部分，遊戲都沒有用到，只有測試讀它們；遊戲只用列車那幾項（`Map3DTrainSets.swift`）。 | **延後**：不是 bug。等 3D 決定要不要把建築與地點接進場景（HANDOFF §7.3），再決定留或刪。 |

其他只記一筆、不算發現的：

- #906 的描述說 3D 的 UI 測試會用 `only_testing` 跑、結果會貼出來，但 PR 上沒有那則留言（#910 有貼 run 39600192396）。
- #902：3D 細節面板的「wait … ms」只有英文，也用了內部單位。旁邊原本的 CPU、GPU、draws 也是這樣，屬於除錯資訊。
- #890 描述裡寫的 CI 是 `8b5dec6` 的；合併 main 之後的 head `f9a796a` 只多了文件的衝突解決。

## 三、延後的項目

### A6（#883，晚點的真實時刻表列車丟掉彎道限速），P2

- **重現**（VERIFIED，探針沒有加入測試 target）：在 `CurveSpeedRunTests` 用 `build(limits: true)`，加一班 A→B、10 分鐘的真實班次（`setLineRuns(main, to: [LineRun(from: 0, to: 1, times: [600/600, 1200/1200])])`）。每 tick 推進，直到列車出發。
  - 出發時拿到的 run：600 秒，`limits` 1 個（準點，照限速跑）。
  - 對同一列車呼叫 `world.run(of: moving, length: set.length, scheduled: 30)`（模擬晚點、只剩 30 秒）：得到 142 秒，`limits` 0 個。正確的結果應該仍然照限速跑。
- **為什麼延後**：
  - 丟限速的判斷在 `run(of:length:scheduled:)` 裡，但 `scheduled` 的意思在每個呼叫點都不一樣：出發（`GameWorld.swift` 約 3936 行）、重新起步（`resumeRun`，用剩下的長度）、改走別條路（`RouteReservation.rerouted`）。
  - 要改對，得把「這一段在真實時刻表上的時間」另外傳進去，只在那個時間本身跑不完時才丟限速。
  - 這會動到行車控制開、閉塞開時高鐵與台鐵示範日的數值。golden 與 replay 要一個一個重新驗證、在 PR 裡說明。
- **建議**：交給行車控制的 session（決策 306、308 的作者）。`run` 加一個 `timetabled: Int64?` 參數，預設等於 `scheduled`，所以其他呼叫點不變；出發與 `rerouted` 傳這一段在時刻表上的時間；`resumeRun` 只有一部分長度，維持現在的做法。

### A7（#897，載入畫面被「新遊戲」頁蓋住），P2

- **證據**：讀程式。`StartView.swift` 的 `NewGamePicker` 用 `.sheet(isPresented: $choosesPlace) { RealWorldPicker(launcher:) }`；`RealWorldPicker.start()` 只呼叫自己的 `dismiss()`；`RealWorldLoadingView` 是 `RailwayGameApp.swift` 的 `RootView` 上的 `.overlay`。Linux 沒有辦法跑 SwiftUI 的呈現。
- **建議修法**：`NewGamePicker` 在 `launcher.realWorldLoading` 變成非 nil 時呼叫自己的 `dismiss()`（`.onChange`），外層 sheet 關掉時，裡面的那層也會一起關。
- **怎麼驗**：在 `RealWorldMapUITests` 按 `realWorld.start` 之後，斷言 `loading.realWorld` 在地圖出現之前是 hittable。先在 main 上用 `ios-build.yml` 的 `only_testing` 跑一次，看它會不會紅（XCTest 對被 sheet 蓋住的元素回報的 hittable 不一定可靠），再修。
- **交給**：開始畫面與決策 316 的下一個 session。HANDOFF §7.1 有一行指過來。

### A8、A10、A11

見第二節的表格。

## 四、逐 PR

| PR | 類別 | 結論 |
| --- | --- | --- |
| [#873](https://github.com/a91453/railway-game-ios/pull/873) | 上一輪 C 組的修正 | 無問題 |
| [#874](https://github.com/a91453/railway-game-ios/pull/874) | 上一輪 B 組的修正 | 無問題 |
| [#875](https://github.com/a91453/railway-game-ios/pull/875) | 決策 304，真實列車照時刻表跑 | A4（已修）。跨午夜、環線走較短的一邊、班距段的回程索引都對 |
| [#876](https://github.com/a91453/railway-game-ios/pull/876) | 決策 302 | 無問題；下一步在 HANDOFF §2 |
| [#877](https://github.com/a91453/railway-game-ios/pull/877) | 決策 305，快轉到早上 | A10（延後，效能） |
| [#878](https://github.com/a91453/railway-game-ios/pull/878)、[#879](https://github.com/a91453/railway-game-ios/pull/879) | 上一輪的交接文件 | 無問題 |
| [#880](https://github.com/a91453/railway-game-ios/pull/880)、[#891](https://github.com/a91453/railway-game-ios/pull/891) | full lane 的 UI 測試 | 無問題；用的是 `appears(within:)`、`waitUntilSettled` |
| [#881](https://github.com/a91453/railway-game-ios/pull/881) | 3D 指北針 | 無問題；±180° 的處理正確，有照「減少動態效果」 |
| [#882](https://github.com/a91453/railway-game-ios/pull/882)、[#903](https://github.com/a91453/railway-game-ios/pull/903) | NEXT_PRIORITIES | 無問題；用 30/25/15/15/15 的權重重算過分數 |
| [#883](https://github.com/a91453/railway-game-ios/pull/883) | 決策 306，晚點追回 | A6（延後） |
| [#884](https://github.com/a91453/railway-game-ios/pull/884)、[#905](https://github.com/a91453/railway-game-ios/pull/905) | 換手、決策索引 | 無問題 |
| [#885](https://github.com/a91453/railway-game-ios/pull/885) | 沒買的地塊畫鎖頭 | 無問題 |
| [#886](https://github.com/a91453/railway-game-ios/pull/886)、[#888](https://github.com/a91453/railway-game-ios/pull/888) | 潮汐的量尺與資料選擇 | 無問題；`tools/real-ridership/test_tools.py` 14 個都過 |
| [#887](https://github.com/a91453/railway-game-ios/pull/887) | 決策 310，地圖提示 | 無問題；兩種語言都有 |
| [#889](https://github.com/a91453/railway-game-ios/pull/889) | 決策 307，載入畫面 | 它本身沒有問題，但被 #897 蓋住（A7） |
| [#890](https://github.com/a91453/railway-game-ios/pull/890) | 決策 309，發車方式，存檔 65 | A1（已修）、A8（延後）。遷移、fixture、README 都對 |
| [#892](https://github.com/a91453/railway-game-ios/pull/892) | 決策 312，實景開局 | 無問題；「用我的位置」在 HANDOFF §3 等作者 |
| [#893](https://github.com/a91453/railway-game-ios/pull/893) | 決策 311，潛力熱圖 | 無問題；chunk 與前綴和在負的原點也對 |
| [#894](https://github.com/a91453/railway-game-ios/pull/894) | 決策 313，2D 與 3D 的交接 | 無問題 |
| [#895](https://github.com/a91453/railway-game-ios/pull/895) | 3D 的 CPU 與 GPU | 無問題 |
| [#896](https://github.com/a91453/railway-game-ios/pull/896)、[#898](https://github.com/a91453/railway-game-ios/pull/898) | 決策 315 的設計、決策號的預約 | 無問題；`### 325` 排在「目前規則摘要」之後，是別的 PR 寫的，doc_numbers 只列為附註 |
| [#897](https://github.com/a91453/railway-game-ios/pull/897) | 決策 316，新遊戲一個入口 | A7（延後） |
| [#899](https://github.com/a91453/railway-game-ios/pull/899) | 3D 開在 2D 看的地方 | A3（已修） |
| [#902](https://github.com/a91453/railway-game-ios/pull/902) | 3D 畫質 | 無問題；三處 `@AppStorage` 的預設都是 `.automatic` |
| [#904](https://github.com/a91453/railway-game-ios/pull/904) | 決策 315 第 2 步，存檔 66 | A2（已修）。遷移、fixture、`recordLineAcquisition` 的失敗原子性都對 |
| [#906](https://github.com/a91453/railway-game-ios/pull/906) | 決策 314，3D 標籤與色帶 | A5（已修） |
| [#907](https://github.com/a91453/railway-game-ios/pull/907) | 預覽圖搬到私有庫 | A9（斷掉的連結已修） |
| [#908](https://github.com/a91453/railway-game-ios/pull/908) | 捷運的真實高架與隧道 | 無問題；剩下的 (a)–(c) 在 HANDOFF §5 |
| [#909](https://github.com/a91453/railway-game-ios/pull/909) | 3D 預覽工具加 pixelmatch | 無問題；作者同意的依賴，ISC 授權檔留著，不進 App |
| [#910](https://github.com/a91453/railway-game-ios/pull/910) | 決策 318，3D 列車模型 | A11（延後）。選模型與 `isTurned` 一致 |

所有 PR 的「下一步」都檢查過：每一項不是已經做完，就是在 HANDOFF 有一行。沒有找到沒人接、也沒有記錄的後續。

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（main，以及兩條分支） | **VERIFIED**，乾淨 |
| A1、A2 的回歸測試在舊程式上（修之前） | **VERIFIED**，紅（錯誤訊息見第二節） |
| A6 的探針 | **VERIFIED**，重現（600 秒有 1 個限速，30 秒變成 142 秒、0 個限速） |
| GameCore PR：`DispatchPatternTests`、`LineAcquisitionTests`、`RealLineAcquisitionTests`、`RingLineTests`、`StationRemovalTests`、`AssetAccountsTests`、`LineAccountsTests`、`LineEditingCommandTests`、`LineRunsTests`、`GoldenScenarioTests`、`SavedGameTests`、`ReplayFixtureTests`、`LongLegReplayTests`、`ReferenceWorldGoldenTests`，以及 property 類的 `FlexDispatchPropertyTests`、`LineDispatchPropertyTests`、`ServiceLinePropertyTests`、`KernelDifferentialTests`（debug） | **VERIFIED**，全過（兩次執行：第一次跑到 30 分鐘的上限時，前 15 個類別已經過了，剩下 3 個另外跑，49 個測試 672 秒）。golden 與 replay 都沒有移動 |
| A4、A5 的回歸測試在舊程式上（把 `RealTrainMotion.swift`、`Map3DLineBands.swift` 換回 `main` 的版本） | **VERIFIED**，紅 |
| Presentation PR：`Map3DOpenHereTests`、`Map3DLineBandsTests`、`RealTrainMotionTests`、`LineMapTests`、`Map3DOpenEveryStartTests` | **VERIFIED**，34 個測試全過（1 個照原本的條件跳過） |
| 其他 GamePresentation 類別與 campaign shard | 交給 CI |
| App 的 `Map3DPreviewScreen.swift`（A3 的 4 行） | **UNVERIFIED LOCALLY**，要等 macOS 的 CI（`ios-build.yml`） |
