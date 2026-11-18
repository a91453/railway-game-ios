# HK-PEAK-CONTROL（2026-11-18）

- 派工：新專案協調者（`docs/priorities/REVIEW-L27.md` 第 1、8 列，`docs/priorities/DEBUG-137.md` 第 1 列）。雲端 Linux，分支 `claude/project-thread-yrhzre`，決策 842。
- 存檔版本不動（108）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。

## 做了什麼

- 決策 842：沒有閉塞區間時，有班次路線的服務整條路空著才出發時，只拿到下一站咽喉前的進站號誌，離號誌 1 km 內才拿進站的路；停在號誌前的車只 claim 拿著的路與它的月台，後面的車可以跟它。`ApproachLocking.swift`（`homeLimit`、`throatPoint`、`claimCover`、`holdsToItsApproach`、`approachLimit(of:holding:_:)`）。
- 香港新局預設（簡化＋管制）南港島綫第二天沒發 21 → 0/458；29 個世界的比對在決策 842 §3。
- HK-CTRL-DEADLOCK（REVIEW-L27 第 8 列）：決策 836 之後 `main` 已是 0 死結，結案。
- 測試：`HomeSignalTests`（GameCore）、`HongKongDepotTests.testTheSouthIslandLineMorningPeakSendsEveryRun`。

## 還留下什麼

- `docs/priorities/HK-PEAK-CONTROL.md`：HK-PEAK-REALISTIC 2.10（擬實的南港島綫仍 10/458）。
- TCL-DAWN（東涌綫清晨 06:17 等 3 班）照舊歸 DEPOT-DAWN-QUEUE（決策 841 那一串）。

## UNVERIFIED

- iOS 實機、畫面：沒看（雲端沒有 Xcode）。運行圖上金鐘出站的車先過渡線、進站車在號誌前停一下，是規則推出來的，沒在畫面上看過。
- 量測是 Linux debug（GameCore -O）；CI 的 shard 由 PR 的 CI 跑。
