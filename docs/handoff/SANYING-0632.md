# SANYING-0632（2026-11-19）

## 做了什麼

- 派工：協調者，私有庫 `docs/priorities/LAST-TRAIN-TERMINUS.md`（2.40）。雲端 Linux，分支 `claude/project-thread-wmpuap`，決策 881 的「後來（SANYING-0632）」。
- 存檔版本、golden schema 不動；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。
- 原因：三峽機廠開往鶯桃福德的空車（接 06:57 的班）跟在班次後面走半條線，claim 蓋到鶯桃福德的進站道岔；06:32 到點的車出站要經過，被綁 24 分鐘。決策 836、850 只放開空車前車出站路上的車。
- 修法（`RouteReservation.swift` `settleClaims`）：空車開往的終點是一條線的一端、照時刻還要 2 分鐘以上才到時，它的 claim 不綁那站到點要開的車。
- 量到的、試過不收的六種寫法：決策 881「後來」一節。
- `TimetableCheckup` 的 `TIMETABLE_CHECKUP_RUNS=1` 多印每班誤點的班次、分鐘與表定時刻。

## 留下的

1. 機捷改建線新局規則兩天久停 6 → 10 次（沒有死結、沒發 8 → 7）：放開後次序改變的連鎖，時段都換了。沒有細看每一次。重現：`tymc-rebuilt` 新局存檔，`DeadlockSweepReportTests`。
2. 三鶯線 06:36 到鶯桃福德、沒有班的車仍被同一列空車的 claim 綁到 06:56，06:38–06:50 三班改由後到的車開、晚 6–9 分鐘。放開沒有班的車在機捷會大量死結（決策 881「後來」的表），要另找條件。
3. 時刻表體檢把「班次發出後在起站等」算成準點（發出時刻照表），06:32 這種等待只有清查工具看得到。

評分在私有庫 `docs/priorities/SANYING-0632.md`。

## 重現

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=sanying DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 \
  DEPOT_RETURN_SAVE=/tmp/sanying-simple.json DEPOT_RETURN_SAVE_AT=0 DEPOT_RETURN_UNTIL=1 \
  swift test --skip-build --filter DepotReturnReportTests/testTheSanyingLine
DEADLOCK_SWEEP=/tmp/sanying-simple.json DEADLOCK_SWEEP_WATCH=23400-25200 \
  swift test --skip-build --filter DeadlockSweepReportTests 2>&1 | grep DEADLOCK_SWEEP
TIMETABLE_CHECKUP_RUNS=1 swift test --skip-build --filter TimetableCheckupTaiwanTests/testTheSanyingLineMorning
```

`swift test` 同一個 `.build` 一次只能跑一個；要並排量幾個世界，直接執行 `.build/debug/GameCoreTests-test-runner GameCoreTests.DeadlockSweepReportTests`（環境變數照上）。

## UNVERIFIED

- iOS、實機沒有看（只改 GameCore）。
- 整日體檢只跑了七格；台灣 15 線全買、香港六線全買沒有跑。
