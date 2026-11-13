# CIOPT-8（CI 第八輪量測）

- 派工單 CIOPT-8，session_01YGNNunYM5mSwBDcxy53H9s，分支 `claude/ciopt-8`，[決策 719](../decisions/719.md)，數字在[量測](../research/CI_MEASURE_2026-11-13.md)。
- 存檔版本、golden schema、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、GameCore：不動。
- 做了：
  - `release-archive.yml`：PR 的 run 逐檔編譯，夜間與手動照舊整模組；上限 30 → 45 分。
  - `swift-shards.sh`：五個類別從 rest 移到最輕的五片 campaigns，23 個類別補權重。完整 tier 仍是 19 個 job。
- 還留下的（量測 §8，都沒有人在做）：
  - `HongKongMapTests` 184 s，超過「一個類別 150 s」。110 s 是 `testTheTungChungLineRunsOnTheMap`（買下東涌綫後跑 51 小時）。要讓它變快得看香港地圖上每個遊戲小時在算什麼。
  - `Stack frames over 32 KB (reminder)` 每個 run 佔一台 Linux 13–20 分；gate 不等它。
  - 截圖 run 一半時間是從頭建置；要省只能和 PR 的 iOS run 共用建好的 App。
- 合併之後要看的：
  - 下一次夜間 release archive（整模組，上限 45 分）有沒有過，花多久。超過 40 分照量測 §9 再看。
  - 下一次完整 `ci.yml` 的 rest-1、rest-2 與 campaigns-1、-2、-8、-10、-12 各花多久；`time_warnings` 再點名沒有權重的類別就補。
