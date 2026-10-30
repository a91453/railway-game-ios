# 實景地圖變慢：作者 96.1 的問題回報（2026-10-30）

遊戲規劃第 33 任派，分支 `claude/perf-real-map-600x`，main `a1e33214` 起。

作者在 iPhone（iPhone18,1，iOS 27.2）玩 0.5.0（96.1），說「還是有點卡」。回報附了存檔、指令紀錄與四張截圖。

- 遊戲：實景地圖、經營、第 53 日，67 站、13 線、74 列車，存檔版本 75。
- 最嚴重的一次：600× 時畫面停了 **54.5 秒**（「其他 54,376 ms」）。
- 其他：600× 的 p95 約 57 ms、p99 約 100 ms；6000× 有 0.5–0.9 秒的停頓；6000× 時「推進」一次 0.7 秒。

存檔與指令紀錄是作者的，不進 repo。量測用的臨時測試也不進 repo，做法寫在第 4 節。

## 1. 54 秒是收購淡海輕軌

指令紀錄最後幾筆：

1. 刪三條線（線 13、14、12）；
2. 收購 `ntdlrt:V`（淡海輕軌）；
3. 暫停。

在 Linux（release）照紀錄重播，逐筆計時。收購之前打開的報價卡也照 App 的做法量：

| 動作 | 修前 | 修後 |
| --- | ---: | ---: |
| 淡海輕軌的報價卡（`realLineOffer`） | 23,949 ms | 1,311 ms |
| 三鶯線的報價卡 | 32,709 ms | 2,065 ms |
| 收購淡海輕軌（指令本身） | 24,690 ms | 1,384 ms |
| 刪線 13 | 624 ms | 148 ms |
| 刪線 14 | 682 ms | 136 ms |
| 刪線 12 | 374 ms | 181 ms |

報價卡與收購兩者都在主執行緒上，加起來約 49 秒，和實機的 54 秒對得上。

**原因：**

- 收購是一個指令，但 `build(_:in:recording:)` 內部依序呼叫 GameCore 的很多步：
  - 每段軌道、每個月台；
  - 線的班次（`setLineRuns`）；
  - 每列車的購買、編組、擺放、指派。
- 每一步最後都跑一次 `abandonUnservedPassengers()`：檢查全地圖每一群候車的人，重算每條線的行程（尋路）。
- 在 64 站 15 線的地圖上，每次約幾十毫秒。收購淡海要上百步，所以要 24 秒。
- 報價卡在世界的副本上把整條線蓋一次，最多四次，所以也一樣慢。
- 小地圖上看不到：BH9 量的台北開局淡海報價是 544 ms。
- gdb 取樣 15 次，15 次都在 `abandonUnservedPassengers` 裡，呼叫者分別是 `buildTrackEdge`、`buildTrackEdges`、`addTrackPlatform`、`setLineRuns`、`setTrainCars`、`assignTrain`。

刪線（`removeLineSellingTrains`）也一樣：刪線以後，每列車都要經過撤出路線、停止營運、拿下軌道、賣掉，每一步都檢查一次。

## 2. 修法

用決策 275 已有的 `GameWorld.editTrackAsOne(_:)`。整個指令期間不檢查，做完才檢查一次。只改 GamePresentation，GameCore 不動：

- `GameSession.build(_:in:recording:)`（收購，報價卡也走這裡）包進 `editTrackAsOne`。原本的步驟留成 `buildStepByStep`，給測試比對。
- `GameSession.removeLineSellingTrains(_:in:)` 一樣處理，舊的留成 `removeLineSellingTrainsStepByStep`。

**為什麼結果不變：**

- 收購只「增加」服務，中間任何一步都不會讓本來有車可搭的人變成沒車；
- 刪線只「減少」服務，之後的步驟也不會把服務還回來；
- 所以「每步都檢查」和「最後檢查一次」送走的人是同一批。

**驗證：**

- 在作者的世界上，修前修後的世界（`GameWorld ==`）與價格完全相同，再跑 600 tick 也相同。
- 三次刪線修前修後也都相同。
- 整份指令紀錄用修後的程式重播，結尾與裝置記下的一致（`CommandLogReport.Summary`）。

**測試：** `PassengerCheckOnceTests`（Linux，平常就跑）

- `testOneEditBuysWhatTheStepsDid`：
  - 竹中有內灣線、六家線；先買六家線，跑八小時，讓候車的人在等；
  - 再買內灣線，一次編輯與逐步做的世界、價格相同；
  - 再跑一天，也還相同。
- `testOneEditRemovesWhatTheStepsDid`：
  - 兩條線都在跑、車上有人時，分別刪掉六家線與內灣線；
  - 一次編輯與逐步做的世界相同，半天後也相同。
- `testOneEditLooksAtTheWaitingGroupsOnce`：
  - 同一台機器上，逐步做要比一次編輯多花「檢查一次候車的人」20 次以上的時間；
  - Linux debug 量到：逐步 3.96 s、一次編輯 2.71 s，檢查一次 6.4 ms，約省了 195 次；
  - 這個世界只有兩條線，蓋軌道本身占大部分時間；在作者 15 條線的地圖上，省下的才是大頭；
  - 把 `build` 改回逐步做（舊程式），這個測試紅（VERIFIED，Linux debug）。

golden、存檔、replay、存檔版本都不動。

## 3. 還沒修的（公測後）

- **報價卡 1.3–2.1 秒、收購 1.4 秒，還在主執行緒上**（Linux release，手機上可能更久）。照 BH9 P2-1 的建議，在 `Task.detached` 裡排版，卡片先顯示「準備中」。剩下的時間是讀地、建軌道本身，沒有再細分。
- **6000× 一次推進 0.7 秒**（作者第二張截圖）。重播量到的每 tick（600 遊戲秒）：
  - 平均 127–172 ms，最長 1.0–1.2 s；
  - 這是背景執行緒的時間，不是主執行緒：遊戲時間跟不上 6000×，畫面不會停；
  - gdb 取樣 30 次，散在 `runServices`／`freePlatformOnTheWay`、`assessSpacing`／`spacingIndex`、尋路、`keepRemainders`、`solveRuns`，沒有單一熱點；
  - 要改 GameCore 的 tick，不適合公測前做。
- **600× 整點的 tick 結束時，主執行緒多 0.45–0.6 s**：這是重播的假象。`session.advance(ticks:)` 在主執行緒上算站長的整點建議（約 0.4–0.55 s）；App 的遊戲迴圈在背景算好再交回來（決策 330）。實機回報的「推進後」只有 1 ms，對得上。
- **站長建議**（`StationMasterAdvice`）在這張地圖一次約 0.4–0.55 s，路線提示（`watchRouteHint`）0.14–0.3 s。App 指令後走背景版本（決策 465 的 `stationMasterLook()`、`watchRouteHintOffTheMainActor()`），沒有確認是不是每個地方都是。
- **讀檔後的 `readLandRoundStations`**：0.63–0.75 s，在主執行緒，每次讀檔一次。
- **2D「軌道與路線」**：一次重畫約 34 ms，最長 57 ms，一秒 11 次，路線面板開著時（截圖 a，12 fps，遊戲暫停中）。這是 App 的 `MapArt.drawMap`（SwiftUI Canvas），Linux 量不到。
  - 重畫次數高的原因，可能是面板打開時鏡頭在動；
  - 下一步用 `MapRedrawCount` 看重畫的理由，再看 `drawMap` 對 3,384 段軌道每次畫多少。
- **其他一次下很多 GameCore 步驟的指令**，同樣可以用一次編輯：
  - `buildTrackChain`、`buildDoubleTrackChain`、`autoService`；
  - 每一步在這張地圖約幾十毫秒；
  - 沒有量，也沒有改。

## 4. 怎麼重現

存檔與指令紀錄在作者的問題回報裡，不在 repo。

- **逐筆計時：** 照 `Tests/GamePresentationTests/CommandLogTickReportTests.swift` 的做法：
  - `HeadlessGame(world: report.start.world)`；
  - `game.install(report.startData, from: CommandLogReplay.realWorld)`；
  - 每筆 `game.step(entry, realWorld:)` 前後用 `ContinuousClock` 量；
  - `advance` 一個 tick 一個 tick 量（`GameSession.advanced(_:by:listening:)` 是核心，`session.advance(ticks: 1)` 是核心加主執行緒的收尾）。
- **報價卡：** 收購那一筆之前設 `session.railways = RealWorldData.load(file: RealWorldDataLoadTests.file).railways`，再量每條 `session.buyableRealLines` 的 `session.realLineOffer(for:)`。
- **修前修後：** 同一個世界的兩份副本，一份跑 `buildStepByStep`／`removeLineSellingTrainsStepByStep`，一份跑新的，比 `==`。
- **建置：**
  - `swift build -c release -Xswiftc -enable-testing --build-tests`：第一次約 27 分鐘，只改測試約 9 分鐘；
  - 再跑 `swift test -c release -Xswiftc -enable-testing --skip-build --filter <Class>`。
- **取樣：** `gdb -p <test-runner 的 pid> -batch -ex "thread 1" -ex "bt 60"`。
  - 找 pid 用 `ps -eo pid,args`，比對 `GamePresentationTests-test-runner`；
  - 不要用 `pgrep -f`，它會找到自己的 shell。

## 5. 五面向

- **玩家：** 大地圖上收購路線與刪線不再停幾十秒，報價卡也快很多。
- **鐵道迷：** 無，蓋的線、班次與價格都不變。
- **開發：** 兩個指令各包一層既有的 `editTrackAsOne`，只改 GamePresentation；differential 測試鎖住結果不變。
- **美術：** 無。
- **音樂：** 無。

## 6. 查過什麼

- **參考庫：** 沒有可用的。`Ci/`、`Simulator/`、`MapBuilder/` 的編輯都是單一動作，沒有候車乘客的檢查；決策 275 的評估也這樣寫。
- **外部專案：** 沒有查。這是本專案自己的守恆規則，用的是決策 275 本來就有的機制。
