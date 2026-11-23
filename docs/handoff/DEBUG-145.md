# DEBUG-145（2026-11-23）

- 派工：協調者（145 發版後例行 B）。雲端 Linux，分支 `claude/post-release-145-b`。
- 範圍：144→145（`e6728ee..fcaa3f0`，first-parent 31 個合併）。HEALTH-145 在 `docs/research/HEALTH_145_2026-11-23.md`；REVIEW-L33 與 CIOPT-14 是例行 A（#2624），運用表「編排」閃退是 ROSTERCRASH-2，這裡都沒碰。
- GameCore、存檔版本、golden schema、決策號都不動。沒有找到要修的 bug。

## 做了什麼

1. **release 建置**（`swift build -c release -Xswiftc -enable-testing --build-tests`）：`fcaa3f0` 從頭 1,864 秒，**0 個警告**；HEALTH-145 的基準 `e6728ee` 另建一次 2,173 秒，**0 個警告**。
2. **release 下跑這個範圍動到的測試**：`e6728ee..fcaa3f0` 新增或改過的 GamePresentation 測試檔裡的 50 個類別，加上 `Map3DLandmarkRegistryTests`、`WhatsNewTests`，共 52 類、362 支，**沒有當機、沒有失敗**。5 支照設計跳過，都是要設環境變數才寫圖或報告的測試：`Map3DModelPackLockTests.testThePacksTime`、`Map3DRoofContrastTests.testReport`、`Map3DStationExteriorBatch2MapTests.testReportWhatStands`、`Map3DStationExteriorsTests.testReportWhatStands`、`TrainPortraitTests.testWritePictures`。
   GameCore 唯一的改動是 #2612（決策 934，`RouteNeeds.swift` 十行）。它和相鄰的測試在 release 下也都過：`FoulingClaimTests` 3、`FollowerClaimDeadlockTests` 1、`EmptyRunClaimDueServiceTests` 4、`GoldenScenarioTests` 24、`SavedGameTests` 38、`ReplayFixtureTests` 3（1 個本來就跳過）。
3. **讀新增的程式找當機寫法**：在 `Sources/` 新增的約 29,000 行裡找強制解包、`try!`、`as!`、`fatalError`、`precondition`，共 4 處，都安全：
   - `RouteNeeds.swift` 的 `network.foulingSpans[$0]!`：和同檔第 923、959 行原本的寫法相同，鍵來自同一張 fouling 表。
   - `Map3DGuanduBridge.swift:112` 的 `xs.max()!`、`xs.min()!`：陣列固定兩個元素（橋的兩端），照抄 `Map3DSuspensionBridge.swift`。
   - `Map3DRoadBridge.swift` 的 `deckOf[root(piece)]!`：#2619 從原檔搬過來的既有寫法。
4. **死結與取消**：見 HEALTH-145。#2612 把 `tymc-rebuilt` 簡化＋管制的整線死結修好（146/333、26 列不解 → 4/333、0 卡死），其餘 0 格變差、0 格新出現死結。
5. **full lane**：
   - `fcaa3f0`（ios-build run 45159162579，協調者 10:46 開）只紅 1 支：`MapInteractionTests.testTheDepotModeOffersItsSidings`，在第 1476 行 `sidings.becomesHittable` 失敗：步進器存在但碰不到，crash report 0 份。這是版面類，已交給例行 A。A 判斷是 #2614（模式列移到卡片頂端）造成的退步，正在單跑確認。second、lessons、iPad 三個 job 都綠。
   - 發版前的 `559162f`（run 45118451204）紅兩支：`MapInteractionTests.testConstructionHUDAppearsDuringTrackPreview`，以及 iPad 的 `TutorialUITests.testTraditionalChineseTutorialNavigation`（第 672 行）。兩支的 crash report 都是 0 份，在 `fcaa3f0` 也都過，看來是不穩。
   - **這兩次 full lane 都沒有當機類的紅**。
6. **CI**：`fcaa3f0` 的 push `ci.yml`（45151050502）綠。

## 注意（給下一個做 DEBUG 的人）

- 把 full lane 的失敗訊息讀出來：`get_job_logs` 的尾巴大多是上傳與清理的步驟，看不到斷言。改用 `get_workflow_run_logs_url` 下載整個 run 的 zip（約 2 MB），解開後在 `4_Xcode build (iOS Simulator).txt` 裡 grep `error:`。
- 兩版的 release 建置與報告同時跑在 4 核上，牆鐘會被拉長；這次的秒數不拿來比快慢。

## UNVERIFIED

- 實機、Metal、聲音。
- macOS／Xcode：只看了 CI 的 full lane，沒有自己開 `only_testing`（那支版面紅由例行 A 單跑）。
- 本機沒跑 debug 的 `swift build --build-tests -Xswiftc -warnings-as-errors`。這個 PR 只動文件，CI 的 Swift jobs 會跳過。
