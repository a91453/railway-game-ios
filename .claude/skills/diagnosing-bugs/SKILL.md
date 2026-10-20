---
name: diagnosing-bugs
description: 難修的 bug 與效能退步怎麼查：先做出一個會在這個 bug 上變紅的指令（Linux 的 swift test、PROPERTY_REPLAY、問題回報重播、GameSim、批次對逐分），再列假說、一次改一個變數、修好後留下回歸測試。玩家回報壞掉、CI 紅、死結、取消變多、存檔讀不回、變慢時先讀。Use when diagnosing a hard bug, a failing CI shard, a deadlock, a save that does not load, or a performance regression, before reading code to guess the cause.
---

# 查 bug：先有會變紅的指令，再猜原因

改寫自 mattpocock/skills 的 `diagnosing-bugs`（MIT，`5beb35b`，授權全文在同目錄的
`LICENSE`）。保留它的主張：**先做出一個能在這個 bug 上變紅、每次結果相同、幾秒到幾分鐘跑完的
指令，才開始讀程式猜原因**；有了它，二分、假說、加 log 都只是消耗它。它通用的十種做法換成這個
repo 已經有的工具（第 1 節）；它的「等人回答」、`hitl-loop` 腳本、`GLOSSARY.md`／ADR 不用：
這裡決定由 session 自己做（CLAUDE.md 的 Workflow），記錄在 ARCHITECTURE 的決策。

## 0. 不寫出祕密

貼指令與輸出時，金鑰、token、帳號資料、玩家的個人資料一律寫 `<REDACTED>`。
TestFlight 與 App Store Connect 的東西不在這裡查（CLAUDE.md：那是作者的）。

## 1. 先做出會變紅的指令

**這一步就是這個 skill。** 照症狀選最近的一種，越前面的越好：

| 症狀 | 會變紅的指令 |
| --- | --- |
| GameCore 或 GamePresentation 的規則算錯 | 在 `Tests/GameCoreTests/`（或 `GamePresentationTests/`）寫一個只斷言這個症狀的測試；`swift build --build-tests -Xswiftc -warnings-as-errors`，再 `swift test --skip-build --filter <Class>/<method>` |
| property／differential campaign 失敗 | 失敗訊息有 `[suite] seed 0x… case n`：`PROPERTY_REPLAY=<suite>@<seed hex>@<case> swift test --skip-build --filter <Class>` 只跑那一個 case（`Tests/GameCoreTests/PropertySupport.swift`）|
| 作者或玩家在 iPhone 上碰到，有附「存檔與指令紀錄」（決策 193） | `swift run GameSim --state /tmp/s.json load report.json then apply report.json then dump`；能用 fixture 的指令說出來的，`PROBLEM_REPORT=report.json REPLAY_RECORD=<暫存目錄>` 跑 `ProblemReportFixtureTests/testConvertingAReport` 轉成 replay（要提交才寫進 `ReplayFixtures/`，而且是新增，不是重錄）|
| 跑一天才出現（死結、取消變多、晚點、錢不對） | GameSim：`swift run GameSim new-game --seed 1 then advance --days 3 then dump --sections economy,trains,deadlock`（決策 260）；高鐵示範的調度：`TRAFFIC_TIMING_REPORT=1`（加 `TRAFFIC_TIMING_ON=1` 打開行車控制）跑 `TrafficControlTimingReportTests`。之後把那一天縮成第 2 節的小世界 |
| 整批推進和逐分推進結果不同 | 同一個世界兩種推法，比較狀態（做法見 `DepotShuttleTests.testABatchEndsWhereMinutesDo`）|
| 和參照模型不同 | 對應的 differential 測試與 `Reference*.swift`（例如 `KernelDifferentialTests`、`ReferenceDeadlock.swift`）|
| 舊存檔讀不回、replay checksum 移動 | `--filter SavedGameTests`、`--filter ReplayFixtureTests`、`--filter LongLegReplayTests`。fixture 與期望值都不能改（CLAUDE.md Architecture rules）|
| CI 的某個 shard 紅 | 本機同一個 shard：`.github/scripts/swift-shards.sh run <shard>`；再縮成一個 `--filter`。不當成 flake 重跑 |
| 某個 commit 之後才壞 | 把上面任一條包成腳本，`git bisect run <腳本>`；`main` 上被取代的 push 在 CI 沒有結果，照 CLAUDE.md 手動跑 `ci.yml` 二分 |
| 原生 3D 畫面不對 | `tools/map3d-preview/`：`main` 與分支各畫同一個鏡頭（不是 Metal，實機要看 TestFlight）|
| 網站 CityView 變慢或畫錯 | `tools/cityview-benchmark/capture.cjs`：同鏡頭的 PNG 與 draw calls、triangles、frame ms |
| 只有 Simulator 才答得出來 | 先想辦法把邏輯移進 GamePresentation，用 Linux 測試（例如 `TutorialCardPlacementTests`）；真的要 Simulator，用 `ios-build.yml` 的 `only_testing`，一次只開一個，PR 的 run 已經在測同一個 commit 就不開 |
| GameCore 變慢 | 先量：`TICK_REPORT=300 swift test --filter TickCostReportTests`（要量的 tick 數）；網站用 cityview-benchmark。量到基準才改 |

**GameCore 是決定論的**：同一個世界、同一串指令，結果應該每次相同。如果「有時候會壞」，
不一致本身就是 bug（字典順序、Linux 與 Apple 的浮點函式不同、時間或亂數混進核心），先找它。
App 與網站層（`Math.random()`、觸控、動畫）才可能真的時好時壞：把觸發條件跑很多次，提高重現率，
1% 的 bug 查不了，50% 的可以。

### 完成條件

能寫出**一條已經跑過**的指令（附上指令與輸出），而且：

- [ ] **會在這個 bug 上變紅**：走真正出錯的那條路，斷言回報的那個症狀，不是「沒有當掉」。
- [ ] **每次結果相同**。
- [ ] **夠快**：Linux 上幾秒到幾分鐘。整個 shard 要十幾分鐘的，縮到一個 `--filter`。
- [ ] **不用人**：session 自己能跑。

還沒有這條指令就在讀程式、想原因：停下來，那正是這個 skill 要擋的。

**真的做不出來**（只在實機發生、只在 TestFlight 的 Release、只有 VoiceOver……）：明說做不出來，
列出試過的方法，請作者下一次附「存檔與指令紀錄」、螢幕錄影與時間，或寫進 `docs/HANDOFF.md`
§7.5 讓測試者看。不要憑猜測改。

## 2. 重現，然後縮小

跑那條指令，看它變紅，確認：

- [ ] 紅的是**回報的那個症狀**，不是旁邊另一個錯。修錯 bug 等於沒修。
- [ ] 重跑還是紅。
- [ ] 記下確切的症狀（訊息、錯的數字、慢了多少），之後拿來確認修好的是它。

再縮小：世界、車站、列車、指令、天數**一次拿掉一個**，每拿一次重跑一次，只留拿掉就會變綠的。
示範地圖一天的死結，常常能縮成兩站、一段單線、兩列車的幾分鐘。縮到每一樣都不能再拿掉才算完。
縮好的這個就是第 5 節的回歸測試。

## 3. 列假說

測任何一個之前，先寫 **3 到 5 個**，排好順序。每個都要能被推翻：

> 「如果原因是 X，那麼改 Y 會讓它消失／改 Z 會讓它更糟。」

說不出預測的不算假說，丟掉或寫清楚。把排序寫在回報或 PR 裡；作者常一眼就知道哪個已經排除，
但不等回答，照自己的排序往下做（作者 2026-10-14：「我不再做決定，都以這個當預設」）。

先查過去的決策有沒有同一類：`grep -n "<關鍵字>" docs/ARCHITECTURE.md`，看它的「後來」「試過、
不採用」。很多死結與調度問題已經有人量過哪一種修法會變差。

## 4. 加探針

每一個探針對應第 3 節的一個預測，**一次只改一個變數**。

- 先用測試裡的斷言或 `dump` 的輸出，再考慮印 log。
- 要印就在邊界印，前面加同一個標記，例如 `[DEBUG-a4f2]`，結束時一個 `grep` 就能全部拿掉。
  GameCore 不用 Foundation，`print` 可以，`FileHandle`、`Date` 不行。
- 不要「全部印出來再 grep」。
- **效能**：通常不是 log 能看出來的。先量出基準（第 1 節最後一列），再二分。先量，再修。

## 5. 修好，留下回歸測試

修之前先把第 2 節縮好的重現寫成測試，**看它在舊程式上紅**。這個 repo 的 PR 一直這樣寫：
「新的 Linux 測試在舊規則下會失敗」。如果是改程式或 fixture 硬讓它紅的，用 `git diff`
確認那個改動真的生效了，再相信它。

然後修，看它變綠，再跑一次第 1 節那條原本的（沒縮小的）指令。

- 找不到能重現真正出錯路徑的地方（只能測一個太淺的函式）：**這本身就是發現**，寫進 PR，
  不要留一個不會在這個 bug 上紅的測試充數。
- 修法動到 golden 期望值、存檔或 replay：那是行為改變，PR 要逐一說明每個值為什麼變
  （`GoldenScenarios/README.md`、`SaveFixtures/README.md`）；格式改到舊存檔讀不了，要升
  `SavedGame.currentVersion`、加遷移與新版本的 fixture。
- 改到錢、運量、城市成長：先讀 `economy-balance` skill，附改之前與之後的數字。
- 本機只跑快的檢查（CLAUDE.md 的 Environments and validation）：warnings-as-errors 的 build、
  這次碰到的測試、改到的 campaign 的 shard。其餘交 CI。

## 6. 收尾與回報

- [ ] 原本那條指令現在是綠的。
- [ ] 回歸測試通過（或寫明為什麼沒有適合的地方放）。
- [ ] `grep -rn "DEBUG-a4f2"` 沒有結果。
- [ ] 臨時的腳本、縮小用的世界放在 scratchpad，不進 repo。
- [ ] PR（與決策的「後來」，如果有決策）寫出**最後證實的那個假說**，以及第 3 節被推翻的幾個，
      下一個查同類 bug 的人才知道。
- [ ] 每項檢查寫 **VERIFIED**（跑了、在哪裡）或 **UNVERIFIED**（例如「需要 macOS CI」）。
- [ ] 沒修完、留給別人：寫進 `docs/HANDOFF.md`（CLAUDE.md 的 Workflow）。
