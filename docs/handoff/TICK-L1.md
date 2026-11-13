# TICK-L1（2026-11-13）

- 派工：遊戲規劃第 64 任（#1579「高倍速時鐘跟不上（TICK-L1、L2）的安排」）。session_01YGNNupUxyvx7zDknZapcT9（雲端 Linux）。分支 `claude/tick-l1`。
- 存檔版本、決策號、golden schema：都沒用。`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 沒動。
- 細節與數字：`docs/research/TICK_L1_2026-11-13.md`。

## 做了什麼

- 先在 main 取樣：`trackHolders(memo:)` 的重建來自 `runServices` 一班一班發車（不是 `extendAuthorities`），另一半在 `trafficPlan`。
- `trackHolders(memo:)` 只改變動的那幾列（`Sources/GameCore/Railway/RouteReservation.swift`）；claim 與 `released` 照舊整段重算。
- 測試裡的檢查「增量 == 重建」（`GameWorld.holderAudit`）：`HolderUpdateTests`、以及每一個 property campaign。
- 基準加 `TICK_SCALE_LAYOUT=ring`（一條線很多列車）與 `TICK_SCALE_WARM`。
- 結果（雲端 Linux，600× 每 tick 中位數）：meet 100 列車 22.7–26.1 → 16.7–17.1 ms，150 列車 50.8–59.1 → 37.8–38.3 ms；閉塞開時中位數不變；ring 不變。

## 還留下什麼

1. **第二個 PR 沒做**：蓋軌道的 `firstConflict`／`addFouling` 格子索引。這個 session 壓縮過一次，不接新的，要另派。
2. **L2 的判斷**（研究文件第 6 節）：值得做，但先做 `inferTrafficMeets` 的（這一站，前一站）索引，不是先分連通塊。真實路網裡臺鐵是一整塊，分塊對它沒用；ring 地圖 40 列車約三分之二的時間在 `inferTrafficMeets`。索引可以做到逐位元相同，用和這次一樣的「測試裡打開檢查」保險。
3. ring 還看到 `resolveDeadlock → deadlock` 與 `isDispatchDue → plannedService → capacityLayout → ringSharedCapacitySegments` 各佔約四分之一的樣本，沒動。
4. `trackHolders` 剩下的時間主要在逐列比 `Train` 相等；要再省得讓列車帶版本號，沒做。
5. 閉塞開時中位數為什麼沒變，沒查。

## UNVERIFIED

- 作者存檔（iPhone 17 Pro、150 列車）的重播：存檔不在 repo。請在 Mac 上 main 與這個分支各跑一次 `PERF_SAVE=<存檔> swift test --filter SaveTickCostReportTests`。
- 真實路網（全臺）的改前改後：代理存檔在雲端做不出來（鋪線太慢）。
- 實機。
- 完整測試（所有分片）：交給 CI。
