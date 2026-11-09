# 11-08 夜 full lane：build job 的 App 起不來（LAUNCH-TIMEOUT，2026-11-09）

派工單 LAUNCH-TIMEOUT（session_01YGNNunZw5P948dG6PSGhmg，遊戲規劃第 57 任派），決策 667。

## 症狀

ios-build run 42527935599（main fa313857，11-08 22:00 UTC 的 full lane）只有「Xcode build (iOS Simulator)」job（128875666034）紅，步驟 UI smoke tests。map、lessons、second、iPad 教學都綠。

| 時間（xcodebuild 自己的時間） | test | 怎麼壞 |
| --- | --- | --- |
| 22:19:41 → 22:21:16（95 s） | `CoverageShortcutUITests`（:20），這一步**第一個開 App 的** class（前面的 `BaseMapProjectionUITests` 不開 App） | `Launch` 之後 84.9 s「Failed to launch … via Xcode: Timed out」 |
| 22:21:17 → 22:29:17（481 s） | `FinanceCompositionUITests`（:14） | 22:21:40 `DTServiceHub - Error resuming pid 36262 … Failed to send signal 19 to process 36262: 3`（Xcode 要讓停著的 App 繼續，App 的行程已經不在：ESRCH），之後等到 8 分鐘的上限，「Failed to get launch progress」 |
| 22:29:18 → 22:30:20（61 s） | `LoadChartUITests`（:13） | 「Failed to launch … via Xcode」，之後 runner「Restarting after unexpected exit, crash, or test timeout」 |
| 22:30:31 起 | 其餘 45 支與重跑的兩支 | 全綠，`FinanceCompositionUITests`、`LoadChartUITests` 重跑也綠 |

壞掉的是 Xcode 開 App 的那一段，不是斷言，也不是 App 自己當掉：同一個 App、同一台模擬器，runner 重開以後每一次都開得起來。

## 和前幾晚綠的 build job 比

| run（job） | commit | UI smoke 步驟 | 第一次經 XCTest 開 App（`Launch` 到下一步） | Coverage／Finance／LoadChart |
| --- | --- | --- | --- | --- |
| 42417467175（128538637568），11-07 夜 | 7665f73 | 36 分鐘 | 17 s（另等 springboard 20 s） | 70 s／204 s／145 s，綠 |
| 42489862739（128759757254），11-08 下午，0.6.0 (122) 那一版 | dc4a436 | 37 分鐘 | 47 s | 88 s／111 s／141 s，綠 |
| 42527935599（128875666034），11-08 夜 | fa31385 | 44 分鐘 | **85 s 逾時** | 紅／紅／紅（重跑綠） |

- 11-08 夜少掉的時間：三支壞掉的約 10.5 分鐘加 runner 重開。扣掉以後是 33.5 分鐘，跟前兩晚一樣。其他 test 的時間也都一樣（例如 `StartSaveFlowSmokeTests` 10 支 601 s），所以 App 沒有變慢。
- Build（13 分鐘；前兩晚 9.5、15）、開機（2.5 分鐘）、「Warm up the app's first launch」（69 s）都在平常的範圍。
- 三晚都有 49 行 `IDELaunchParametersSnapshot: no debugger version`，綠的晚上也有，跟這次無關。

## #1993、#1998 有沒有關係

- **#1993（決策 658）**只改 iPad job：iPad 在開機前先 `build-for-testing`，測試改 `test-without-building`，加長 iPad job 的時限。build job 的步驟和順序沒動（`git diff 4cbf651^1 4cbf651 -- .github/workflows/ios-build.yml`）。full lane 的四個 macOS job 本來就各在自己的 runner 上，iPad job 要等 iPhone job 跑完才開始，所以 build job 的 runner 也沒有更吃緊。
- **#1998（決策 659）**：workflow 只改 iPad 的 trace 步驟什麼時候存。App 這邊改了 `StallSampler`（卡住以後每秒看 20 次，只在 UI 測試模式下跑，還沒卡住時仍是 0.2 秒一次）和 3D 街道的種子（`Map3DScene`、`Map3DStreets`，要開 3D 地圖才會跑）。開 App 的路上兩樣都沒有。
- App 自己若變慢，應該每一支都慢。實際上第一次開 App 之後，每一支的時間都跟前兩晚一樣。

## 原因：build job 少了 XCTest 的暖身

另外三個 iPhone job（`ui-full-lane`）在測試前有兩次暖身：「Warm up the app's first launch」（`simctl launch`）和「Warm up XCTest's first launch」（只跑一支 `StartSaveFlowSmokeTests/testTheAppOpensOnItsStartScreen`）。第二次暖身的註解寫的就是這次的症狀：simctl 那次暖身不走 XCTest，job 裡第一次走 XCTest 開 App 還是可能逾時（cd93d78 的 lessons「Timed out while launching application via Xcode」67 s，App 的 trace 裡什麼都沒有），排在最前面的那個 class 就紅（0149127 的 run 39992945211 也是）。

build job 只有第一次暖身。所以 full lane 裡，只有 build job 第一個開 App 的 class，是這個 job 第一次經 XCTest 開 App。綠的晚上這一次也要 17–47 s，遠多於之後每次開 App 的幾秒。慢一點的 runner 就會超過 Xcode 的開 App 時限。超過之後，Xcode 跟模擬器之間開 App 的那條路會壞一陣子（Finance 的 signal 19），直到 test runner 自己重開。

**修法（決策 667）**：把 `ui-full-lane` 同一個「Warm up XCTest's first launch」步驟加到 build job，放在 simctl 暖身之後、UI smoke 之前。照抄它的寫法：先 terminate、只跑那一支、`continue-on-error`、8 分鐘上限，result bundle 叫 `ui-smoke-warm-up.xcresult`，失敗只留警告。不在 pull request 上跑：gate 守在約 6 分鐘（決策 199），這一步多 2–3 分鐘（另外三個 job 是 1.7–3.5 分鐘）。build job full lane 的時限 115 分鐘，11-08 夜整個 job 約 63 分鐘，放得下。

## 驗證

- 本分支用 `ios-build.yml` 的 `only_testing` 跑 `CoverageShortcutUITests FinanceCompositionUITests LoadChartUITests` 一次（workflow_dispatch，所以暖身步驟會跑）。結果寫在決策 667。
- 真正的證明要看之後幾晚 full lane 的 build job：「Warm up XCTest's first launch」綠（或只有警告），UI smoke 第一個開 App 的 class 不再出現「Failed to launch … via Xcode」。

## 以後怎麼認

- 「Failed to launch … via Xcode: Timed out」、「Failed to get launch progress」、`Error resuming pid … signal 19 … 3`，而且**落在 job 第一個開 App 的 class**，runner 重開以後全綠：這是第一次經 XCTest 開 App 太慢，不是 App 的問題。先看那個 job 有沒有「Warm up XCTest's first launch」，有的話看它花了多久、有沒有警告。
- 同樣的訊息若落在 job 中間、開過好幾次 App 以後，才要懷疑 App 開起來變慢或當掉。看 `ui-*-trace` 的 App trace，比較同一支 test 在綠的晚上 `Launch` 到「Setting up automation session」的時間。
