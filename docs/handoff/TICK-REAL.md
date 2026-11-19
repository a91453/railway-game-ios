# TICK-REAL（2026-11-18）

## 進度

- 做到哪：第一批（五項備忘，決策 878）做完、開 PR；第二批（逐秒那一層）與台灣全買的秒級 tick **沒做**，這個 session 壓縮兩次停手。
- 已驗證：六個全買世界各一天，新舊 build 的整點雜湊相同（數字在決策 878 的表）；稽核模式香港一天；`swift build --build-tests -Xswiftc -warnings-as-errors`。
- 下一步的第一個指令：`BOUGHT_WORLDS=/tmp/worlds swift test --skip-build --filter BoughtWorldSaveTests`（約 15 分鐘，六個存檔），再照下面「怎麼量」。

## 派工

- 協調者派工（作者：「進量做 難度高一點的才值得 看要優化3d或是tick 死結 等」），雲端工作串「優化模擬 tick 並清查死結」，分支 `claude/project-thread-n8icjx`，決策 878。
- 存檔版本、golden schema：不動。`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 沒動。
- 第二部分（死結清查）在另一條工作串：DEADLOCK-SWEEP，決策 877，分支 `claude/project-thread-xmlajh`。它會修 holders 的時刻過期（見下），和這裡動到同一段（`DirectionMemo.holders`、`trackHolders`）；後合的併 main。

## 做了什麼

決策 878 寫了五項與各自「為什麼結果一樣」。檔案：`ServiceDirections.swift`（`RouteMemo.Key`、`DirectionMemo` 的 `runTrips`／`linePlans`／`HolderStore`／`answers`、`WorldAnswers`、`AnswerAudit`）、
`LineRuns.swift`（帶備忘的 `runTrip`、`dueRun*`、`readyRunTrain`）、`RunDepot.swift`（`trainsInTheWay`、`heldRunDepartures`）、`GameWorld.swift`（`dispatchTrains`）、`Deadlock.swift`、`RouteReservation.swift`（`holderChanges`）、`LineRoutePreference.swift`。

## 怎麼量（工具都在 repo）

```sh
# 1. 六個全買世界存檔（GamePresentation，debug，約 15 分鐘；BOUGHT_WORLDS_ONLY=hk-all-simple 只做一個）
BOUGHT_WORLDS=/tmp/worlds swift test --skip-build --filter BoughtWorldSaveTests
# 2. 一天的 tick 時間與整點雜湊（GameCore，-O；改 GameCore 後 swift build --target GameCoreTests 一分鐘到幾分鐘）
SAVED_WORLD=/tmp/worlds/hk-all-simple.json SAVED_WORLD_EACH=1 SAVED_WORLD_HOURS=1 \
  swift test --skip-build --filter SavedWorldTickReportTests
# 3. 稽核：每個借用的答案重算比對（慢幾倍，證明用）
SAVED_WORLD=/tmp/worlds/hk-all-simple.json SAVED_WORLD_AUDIT=1 swift test --skip-build --filter SavedWorldTickReportTests
```

- 比兩個 build：把 `.build/debug/GameCoreTests-test-runner` 與 `GameCoreTests.so` 各複製到一個目錄，分別跑
  `<目錄>/GameCoreTests-test-runner GameCoreTests.SavedWorldTickReportTests/testWhatASavedWorldCostsATick`，`diff` 兩邊的 `checksum` 行。全部相同＝世界沒被改到。
- 取樣：`perf record -F 99 -g -- <runner> …`（`/usr/lib/linux-tools/*/perf`），`SAVED_WORLD_HOLD=<秒>` 會先印 pid 並空轉，給外部取樣器接上。
- 一天要多久（雲端 4 核）：香港全買 3–5 分鐘，羅瓦涅米幾秒，**台灣全買改前 69–74 分鐘、改後約 41 分鐘**（平均每 tick 3 秒 → 1.7 秒）。台灣只想驗雜湊時用 `SAVED_WORLD_TICKS=600`（到 10 時，含晨峰）。
- 存檔是 `main` 當時的鋪法；鋪線規則（GamePresentation）一變要重存，新舊 build 要用同一份存檔比。

## 還留下什麼（第二批，都沒寫程式）

改後再取樣（香港簡單一天，含括比例、彼此重疊）：`trackHolders` 29.6 %、`extendAuthorities` 22.6 %、`cover(of:)` 19.1 %、`moveTrains` 16.7 %、`reservingDeparture` 15.1 %、
`authority(of:reserved:)` 13.8 %、`settleClaims` 7.9 %、`pathAhead` 5.7 %、`claimCover` 5.7 %、`clearOfBlocked` 5.5 %、`foulingNodes` 5.2 %、`trafficPlan(memo:)` 4.9 %。
有跟車時一步一秒、一格 16 m，所以保留每秒都在變；這一層要省，得從「整個重算」改成「只算變動的」，每一項都要像 `holderAudit`／`answerAudit` 那樣配一個稽核。想過、依把握排：

1. **`releasePassedTrack` 的慢路徑**（約 9 %）：現在是 `cover(of: 車身＋進路)` 再 `kept(of:)`；改成從「這一秒走過的那一段」直接算出放掉的資源。稽核：和舊算法的結果比。
2. **`pathAhead(of:)` 每列車記一份**（5.7 %，經 `routeStretches`）：鍵（traversal、`movement.edges`、cursor）；列車沒過節點就不變。
3. **`isFoulingEnd(of:at:)`／`foulingNodes(covering:)` 預先算**（約 5 %）：只看路網，路網不變就不變，可以放進 `RouteMemo`。
4. **「沒在跟車」往移動後的自己傳**（1.5–2 %）：`authority` 為 nil 的列車移動一秒後多半仍為 nil。
5. **`TrackHolders` 改成差量更新**：現在一列車變了是「拿掉舊的、放進新的」整列重做（TICK-L1 留下的第 4 點：逐列比 `Train` 相等也在這裡）。
6. **被擋住的出發每秒重問**（`reservingDeparture` 15.1 %）：擋住它的資源沒放之前答案不會變；可以記「上次被誰擋」，那個資源沒動就不重問。風險最高（要證明「不會變」）。
7. **台灣全買一個 tick 仍要 1.7 秒**（149 列車；改前 3 秒）：比香港（36 列車）慢的倍數遠超過列車數的比例，應該有超線性的項（猜：`trafficPlan` 的會車推論、`deadlock` 搜尋、holders 逐列比對）。**先取樣再說**，不要照香港的佔比猜。
   這次只在 main 的台灣簡單傍晚（17–18 時，那一小時要跑十幾分鐘）取了 20 秒：`trafficPlan(memo:)` 26.9 %（其中 `planTrafficOvertakes(_:lines:)` 18.8 %）、
   `runDepotEntryCandidates` 33 %（`runTrainEnteringDepot` 19.6 %＋`depotBoundMakingWay` 13.6 %，裡面是 `trainsInTheWay`／`heldRunDepartures`，第一批已經備忘）、`reservingDeparture` 12.4 %。
   所以台灣下一個要看的是 `planTrafficOvertakes`（待避推論隨線數與列車數長得快），改後的台灣還沒取樣。
   **後來**：TICK-TAIWAN 做了（決策 878「後來」，台灣到 10 時少一半），還剩的寫在 `docs/handoff/TICK-TAIWAN.md`。

另：把 `SavedWorldTickReportTests` 接進 nightly 當報告（香港全買一天的平均 tick 與雜湊），之後誰讓 tick 變慢或世界變了當晚就知道。沒做。

評分在私有庫 `a91453/railway-assets-private-2` 的 `docs/priorities/TICK-REAL.md`。

## 台灣全買的死結（main 既有，沒動）

- 寫實（閉塞開）：最多 5 列，在第 0 天 16:10，一天裡 31 個 tick 看得到；簡單：最多 3 列，在 09:02，1 個 tick。改前改後相同。已告訴 DEADLOCK-SWEEP。
- 要從那之前看：`SAVED_WORLD_SKIP=960 SAVED_WORLD_TICKS=30`（跳到 16:00）。

## 要小心的

- **holders 的時刻過期**：`settleClaims` 讀現在時刻，holders 備忘只用列車當鍵。這裡照原樣保留（改了世界會變）。DEADLOCK-SWEEP（決策 877）要修它；修了之後各世界的雜湊會和這裡的表不同，之後的「不改行為」比對要用修後的 main 重量基準。
  那邊的修法會在 `DirectionMemo.holders` 的 tuple 加 `at:`：`DirectionMemo.HolderStore.holders` 的型別要一起改；holders 每個變動處後面要 `memo.holderChanges += 1`（`WorldAnswers` 的戳記）。
- 派車（`dispatchRuns`）的 holders 與步進的分開（`exchangeHolders`），不要合成一份：合了就是用可能過時的 holders 判斷能不能發車，世界會變（修好過期之後才可以合）。
- 不要預先把 holders 算熱：那會改變「哪一份是舊的」，世界會變。
- 備忘只在一次 `advance` 裡、或 `RouteMemo` 鍵相同時借到下一次；新加的鍵若漏了一個輸入，`SAVED_WORLD_AUDIT=1` 與 `AnswerAuditTests` 會 trap。新加備忘時照樣加稽核。

## UNVERIFIED

- 實機的 tick 時間與倍速手感（iPhone／iPad）；作者自己的大存檔。
- Apple 平台編譯與完整測試、整天的時刻表體檢：交 CI。
- 時間都是雲端 Linux、同時有別的程序在跑時量的，只能看相對；雜湊是硬的。
