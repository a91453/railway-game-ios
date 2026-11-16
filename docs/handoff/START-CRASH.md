# START-CRASH（開始畫面→入門→第一課時 App 被 SIGTRAP 結束）

## 進度

- 做到哪：PR #2308 開了（draft）；當機報告上傳、`TrapTrace`、`StallSampler`「so far」都在分支上。根因沒找到，另外接著查。
- 已驗證：Linux 上進第一課十幾毫秒（VERIFIED）；App 改動與工作流程新步驟要看 #2308 的 iOS job。
- 下一步的第一個指令：看 #2308 的 check runs；綠了轉 ready，在 #2118 回報。

- 派工：遊戲規劃，2026-11-16（bug）。session `session_01JMHz9bdXcTFrrku4stCHuN`，分支 `claude/start-crash`。
- 決策號沒取（807 沒用）；存檔版本、golden、`SaveFixtures/`、`ReplayFixtures/`、GameCore、GamePresentation 都不動。
- **根因沒有找到。** 這張交的是：下一次紅的時候拿得到當機位置的三樣東西、兩次紅的實際經過、嫌疑清單。沒有改任何測試，沒有跳過、停用、隔離或加長等待。

## 兩次紅其實是兩件事

同一支 `TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds`，都在 PR 的 iOS job（macos-26、iOS 26.4 模擬器），都是重跑一次就綠。

| | #2298（run 43819747972，job 133140016738） | #2306（run 43876311730，第 1 次） |
| --- | --- | --- |
| 測試的失敗訊息 | `TutorialUITests.swift:41` No tutorial card | `TutorialUITests.swift:165` Skip did not close the tutorial |
| App | **死了**：系統紀錄 `exited due to SIGTRAP \| sent by exc handler[33036], ran for 25012ms` | 沒死，一路 120 fps |
| 經過 | 碰「入門」後主執行緒 12,998 ms 沒畫（同一支綠的時候是 0.25 秒），清單出來後又停 1,928 ms；測試碰第 1 關「開始」（合成觸控 07:13:10.7–11.6），App 在 07:13:11.6 前後結束，App 的觸控紀錄裡沒有這一下 | 碰「略過」的合成觸控花了 10 秒才送到（測試 48.93 s 送出、58.93 s 才回來）；App 在 13:55:07.9 收到時，落點 (261, 300) 已經是地圖（`MapGestureView`），不是「略過」。這 10 秒裡主執行緒有 4,799 ms 停在系統的輔助使用（見下） |
| 是不是 App 的錯 | 是：trap 是 App 行程自己的例外，**哪一行不知道** | 看起來不是：觸控晚了 9 秒才到，卡片已經不在那裡 |

`SIGTRAP sent by exc handler` 是在結果包的系統紀錄（logarchive 的 tracev3）裡找到的；結果包沒有當機報告（XCTest 的「Checking for crash reports」等滿 20 秒沒等到）。

#2306 那 4.8 秒的堆疊（決策 659 的取樣寫下來的，70 次裡 70 次）：
`AXBinaryMonitor _handleLoadedImagePath:` → `+[AXMobileQuickLookGlue accessibilityInitializeBundle]` → `+[NSBundle bundleWithIdentifier:]` → `read`／`getdirentries64`。
也就是 XCTest 打開輔助使用之後，App 第一次載入某個系統框架時，系統在主執行緒上翻遍磁碟找 bundle。這是模擬器加 XCTest 才有的路（實機要開著旁白之類才會走到），不是遊戲的程式。

#2298 那 13 秒**沒有堆疊**：取樣有開（`-ui-test-stall-stacks`），但報告要等卡頓結束才寫，而且每一次取樣要約 30 ms 才查得完名字（#2306 的紀錄：70 次取樣晚 2.3 秒才寫出），13 秒約 240 次取樣要 7 秒左右，App 在 3.5 秒後就沒了。

## 這張改了什麼

1. `.github/workflows/ios-build.yml`：三個跑 UI 測試的 job（`build` 的 UI smoke、`ui-full-lane` 的兩個分區、`ipad-tutorial`；full lane 走的是同一個檔）在 **UI 測試那一步失敗或被取消時**多兩步，成功時不跑：
   - 收 Mac 的 `~/Library/Logs/DiagnosticReports/RailwayGame*`（模擬器 App 的當機報告寫在 Mac 這裡；`.ips`、`.crash`、`.diag`、`.hang`、`.spin`）、模擬器裝置自己的 `data/Library/Logs/CrashReporter` 與 `DiagnosticReports`、以及下面第 2 點 App 自己寫的堆疊檔。
   - 上傳成 artifact：`ui-smoke-crash-reports`、`ui-<分區>-crash-reports`、`ipad-tutorial-crash-reports`（7 天），和原本的 `…-xcresult`、`…-trace` 放在同一次 run。一個檔都沒有就不傳。job 的摘要多一行「Crash reports and trap stacks: N」。
   - gate job 的名字、觸發條件、`testflight.yml` 都沒動。
2. `RailwayGameApp/App/RailwayGameApp.swift`（只有 Debug，而且只在 `-ui-testing`）：`TrapTrace`。App 被 SIGTRAP／SIGILL／SIGABRT／SIGSEGV／SIGBUS／SIGFPE 結束前，先把訊號號碼、出事的位址與那條執行緒的呼叫堆疊（每格有映像與符號名）寫進 App 容器的 `tmp/ui-test-trap-<pid>.txt`，再照原樣結束（每個訊號只接一次，原本的當機報告不受影響）。Mac 沒寫當機報告的時候（#2298 那次就是）還有這一份。
3. 同一個檔的 `StallSampler`：卡住約 4 秒（60 次取樣）時先寫一次「so far, and still stalled:」（最近 20 次取樣），不等卡頓結束。#2298 那種 13 秒下一次會有堆疊。順手把取樣裡兩處會 trap 的算術改掉（`fp + 16` 溢位、位址 0 減 1）：它讀的是被停住的執行緒當下的暫存器與堆疊，什麼值都可能。

## 下一次紅，去哪裡拿

那次 run 的 Artifacts（7 天）：

1. `ui-smoke-crash-reports`（full lane 是 `ui-second-crash-reports` 之類，iPad 是 `ipad-tutorial-crash-reports`）：
   - `mac/RailwayGame-<日期>.ips`：有的話直接看 `faultingThread` 那條堆疊，Debug 版有符號。
   - `trap/ui-test-trap-<pid>.txt`：第一行是訊號號碼（05＝SIGTRAP、06＝SIGABRT、11＝SIGSEGV），第二行是出事的函式，再下面是呼叫它的。
2. `ui-smoke-trace`：`stall so far` 與 `stall #n` 是卡住時主執行緒在做什麼；`touch`、`action` 是 App 收到的觸控與按鈕動作。
3. 兩樣都沒有時：`ui-smoke-xcresult` 的 `Data/` 是 zstd 壓的，裡面有系統紀錄（tracev3，LZ4 區塊），搜尋 `exited due to` 可以確認是哪個訊號。這次就是這樣確認 SIGTRAP 的。

## 嫌疑清單（都沒有證實）

排序是我的判斷，不是量出來的。

1. **主執行緒上真的有一個 Swift trap，在課程清單出現後、進課前後的 1–3 秒內。** 證據：系統說是例外處理送的 SIGTRAP；App 沒收到「開始」那一下就沒了，所以不一定是進課的程式，也可能是清單出現後主執行緒正在做的事（那 1.9 秒）。App 與 GamePresentation 裡會 trap 的寫法我看過的：
   - `MainActor.assumeIsolated`（不在主執行緒就 trap）：`GameAudio.swift:110`、`FrameTimeRecorder.swift:58/61/174/177`、`RailwayGameApp.swift`（`BackgroundSave`）、`MapView.swift:3843/3846`、`OSMMapBackground.swift:258–270/781`、`Map3DMetalView.swift:1911/1914`。讀起來都排在主佇列或主 run loop 上，沒看到錯的。
   - `withCheckedContinuation`（resume 兩次會 trap）：`GameLauncher.swift:342/1524/1689/2152`、`OneShotLocation.swift:43`、`Map3DPreviewScreen.swift:716/735`。前四個都是 `saveQueue.async` 裡 resume 一次；沒看到兩次的路。
   - `fatalError`／`preconditionFailure`：`RailwayGameApp.swift` 與 `FeatureUITestWorld.swift` 的都在啟動時讀測試參數，這支測試不帶那些參數。
2. **卡頓取樣自己**（這支測試才開）。它在卡住時每 50 ms 停一次主執行緒讀暫存器；我改掉的兩處算術是真的會 trap 的寫法。但 App 結束時取樣那條執行緒照時間推算還在寫 13 秒那份報告，不在取樣，所以多半不是它。改掉之後下一次若再 trap，至少排除這一項。
3. **13 秒本身多半是模擬器與 XCTest 的系統路徑，不是遊戲的程式**（推定）：#2306 的 4.8 秒是輔助使用找 bundle；其他測試的 2 秒級卡頓是模擬器第一次編 Metal 管線（`MTLSimDevice newRenderPipelineWithDescriptor` 同步等 XPC）。課程清單是第一張 sheet 加第一個 `List`，兩條路都會走到。清單本身很輕：10 關的固定文字，Linux 上量到的見下。**實機會不會卡 13 秒：沒有證據說會**；實機沒有 XCTest 開的輔助使用，Metal 管線也不是同步跨行程編。
4. **進課時主執行緒同步等存檔佇列**：`GameLauncher.begin` → `afterSaves` → `saveQueue.sync`（先 `archiveAutosave`）。啟動時讀存檔清單也排在同一個佇列，磁碟慢時主執行緒會等。這是卡，不是 trap；實機上 iCloud 存檔夾慢時也會等（PERF-DEVICE 1 已經知道）。
5. 134 full lane 的 `LessonUITests.passFirstLesson()`「第二次觸控沒收到」（POST-134）：和 #2306 那次同一型（觸控晚到或落空），不是 #2298 這型（App 死掉）。兩件不同源。

## Linux 上量到的

用一支不提交的 GamePresentation 測試量（`swift build --build-tests -Xswiftc -warnings-as-errors` 後 `swift test --skip-build`，Linux、Swift 6.4，**VERIFIED**）：

| 段 | 耗時 |
| --- | --- |
| `GameLauncher` 建立（空的存檔夾） | 4 ms |
| 課程清單要顯示的全部文字（10 關的標題、故事、目標、星數、教什麼） | 1 ms |
| `launcher.startLesson(第 1 關)`（建世界、開始教學），連做三次 | 12、19、10 ms |

遊戲規則這一層進第一課是十幾毫秒，13 秒不在這裡。量不到的是 SwiftUI 排版、Metal、地圖底圖與模型包、模擬器的系統路徑。

## 還留下什麼

- 根因。等下一次這支（或任何 UI 測試）因為 App 死掉而紅，照「去哪裡拿」看 `trap/` 與 `mac/`；拿到函式名再開一張修。五方（我的評分）：玩家 3、開發 4、美術 1、鐵道迷 1、音樂 1，加權 2.35，是 bug。
- #2306 那一型（合成觸控晚 9 秒才到，卡片已經不在原地）：測試在送出觸控前算好座標，系統晚送就落空。要不要讓「略過」那一步在沒關掉時、卡片還在就再碰一次（`startFirstLesson` 對「入門」已經這樣做），留給規劃決定；這張沒改測試。加權約 1.9（玩家 1、開發 4、其餘 1）。
- `StallSampler` 查一個名字要約 30 ms（`dladdr` 在 Debug 的大符號表上慢）；要更快得先存位址、之後再查。沒做，「so far」先頂著。

## UNVERIFIED

- `TrapTrace` 與 `StallSampler` 的改動：Linux 不能編 App，編不編得過、寫不寫得出檔，要看這個 PR 的 iOS job；而且只有真的再當一次才知道 `trap/` 檔有沒有內容。
- 工作流程新加的兩步只在 UI 測試失敗時跑：這個 PR 的 iOS job 若是綠的，它們沒有被執行過，只驗過 YAML 讀得進去。
- 「13 秒是模擬器系統路徑」「實機不會」是從另一次的堆疊推的，沒有那 13 秒自己的堆疊。
- 重現：見 PR 的說明（跑了幾輪、有沒有再紅）。
- iOS 實機、畫面：沒看，這張沒有改畫面。
