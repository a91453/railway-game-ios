# DEBUG-137（2026-11-18）

- 派工：新專案協調者（137 發版後例行的除錯，交接時漏派後補）。雲端 Linux，分支 `claude/project-thread-l7jant`，決策 836。
- 存檔版本不動（108）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動，三組測試在分支上原樣通過。

## 做了什麼

- 在 `main` `b4ae9c5`（DEPOT-REAL 之後）用 HEALTH-137 的「重現」重量香港與機捷：
  - 香港簡＋控沒發 31/740 → 23/732，全在南港島綫（東涌綫有了小蠔灣車廠後 9 → 0）。
  - **東涌綫多了 `main` 才有的死結**（第一天 14:25 起 6 列、17 分）：修了，決策 836。
  - 機捷新線擬實沒發 2/333（05:56、05:58 長庚醫院）照舊，是 DEPOT-DAWN-QUEUE，沒動。
- 決策 836：`RouteReservation.swift` 的 `settleClaims` 與新的 `leavingCover(of:memo:)`。回歸測試 `HongKongDepotTests.testTheTungChungLineAfternoonHasNoDeadlock`。
- 29 個世界簡＋控：27 個逐字相同；香港死結 0、沒發 23 → 26；機捷舊線沒發 6 → 3。擬實香港、機捷新線逐字相同。

## 還留下什麼

評分在 `docs/priorities/DEBUG-137.md`：
1. HK-PEAK-CONTROL（重評 2.15）：南港島綫尖峰在金鐘的咽喉排不進去。GameCore 進路，死結類。
2. TCL-DAWN（2.10）：東涌綫清晨出庫來不及，併進 DEPOT-DAWN-QUEUE。

## 怎麼重現

```sh
swift build -c release -Xswiftc -enable-testing --build-tests
# 香港兩線、簡＋控（約 5 分鐘）
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 \
  .build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testHongKong
# 南港島綫尖峰，看金鐘（第二天 08:25–08:50）
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_ONLY=hk-sil \
  DEPOT_RETURN_WATCH=116700-118200 DEPOT_RETURN_WATCH_AT=金鐘 \
  .build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testHongKong
```

## UNVERIFIED

- iOS 實機、畫面：沒看（雲端沒有 Xcode）。
- 量測都是 Linux release；CI 的 shard 由 PR 的 CI 跑。
