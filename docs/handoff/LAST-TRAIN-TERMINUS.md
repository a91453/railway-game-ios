# LAST-TRAIN-TERMINUS（2026-11-18）

## 做了什麼

- 派工：協調者，私有庫 `docs/priorities/DEADLOCK-SWEEP.md` 第 1 項（2.85）。雲端 Linux，分支 `claude/project-thread-l0xnc8`，決策 881。
- 存檔版本不動（110）、golden schema 不動；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。
- 原因：新局規則下，機廠滿的線收班車停在終點，末班車的預設路線指向其中一列占著的月台；去空月台要逆線，決策 57 不給，決策 571「續」的 `takingFreeBerthPastStandingTrain` 只認沒有排班表的線的備用車。三鶯線每晚 00:26–06:01 末班車停在前一站。
- 修法（GameCore `RouteReservation.swift`，`takingFreeBerthPastStandingTrain` 的 `case nil`）：擋路的是有排班表的線上沒有班的車時，若它停在那條線的一端、那條線沒有機廠還有空股給它、那站有班開出但沒有一班在末班車照時刻表到站之前開，末班車逆線進同站的空月台。
- 量到的（決策 881 §3）：三鶯線 335 分久停 ×2 → 0；淡海藍海線久停 2 → 0；淡海綠山線 4 → 2（只剩 20:05）；其餘 13 個世界（機捷三個世界、香港四種買法、文湖、高雄輕軌、安坑、新北投、示範世界、羅瓦涅米）兩天的雜湊與 `main` 相同；整天版體檢 `sanying:LB simple`、`ntdlrt:V simple`、`ntdlrt:VB simple`、`tymc:A simple` 與 `main` 相同。
- 新測試 `LastTrainTerminusTests`（修前紅）。

## 留下的

1. 三鶯線每天 06:32 一列車晚 24 分鐘開往永吉公園（決策 877 §4.1 第 3 項）。
2. 淡海綠山線每晚 20:05 兩次 22 分久停：回庫空車的 claim（DEPOT-CLAIM-LONG），不是這張單。
3. 評分在私有庫 `docs/priorities/LAST-TRAIN-TERMINUS.md`。

重現：

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=sanying DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 \
  DEPOT_RETURN_SAVE=/tmp/sanying-simple.json DEPOT_RETURN_SAVE_AT=0 DEPOT_RETURN_UNTIL=1 \
  swift test --skip-build --filter DepotReturnReportTests/testTheSanyingLine
DEADLOCK_SWEEP=/tmp/sanying-simple.json DEADLOCK_SWEEP_WATCH=87780-88140 \
  swift test --skip-build --filter DeadlockSweepReportTests 2>&1 | grep DEADLOCK_SWEEP
```

## UNVERIFIED

- iOS、實機沒有看（只改 GameCore，只在 Linux 上跑）。
- 整天版體檢只跑了四格，其餘靠兩天雜湊相同推定不變，交夜間 CI。
- 台灣 15 線全買沒有跑。
