# THSR-SALE（2026-11-25～26）

## 進度

- 做到哪：台灣高鐵（南港–左營 12 站）可以在台灣新局整條收購。第一串鋪好線、高架、班次與兩端機廠；第二串（分支 `claude/project-thread-9t5f5d`）修好擬實規則的死結（台中折返渡線）、加烏日基地、兩端改 7 股、加每月維護費（GameCore）並定價。決策檔 `docs/decisions/993.md`。
- 已驗證（雲端 Linux release，`-warnings-as-errors`）：建置乾淨；`LineAcquisitionTests` 19 個全過；擬實規則一天檢查（兩端 7 股）沒發 0、晚點 36、出庫晚 8→10、尖峰 +12 分；收支（從台北開局，帶每月 1 億維護費）第 0、1 天公司現金每天 +955 萬、+903 萬。
- 簡易規則（新局預設）一天檢查：兩端 5 股時沒發 59（原因：兩端停滿，擋路的車被趕回機廠）；**兩端 7 股的結果見 PR 說明**（量的時候還在跑）。
- 下一步的第一個指令：見下面「還要做的」。

## 派工與範圍

- 派工：專案協調者（Chien 11-26：「台灣高鐵先整條買、價錢照一年淨利約 3～5 年回本＋每月維護費，分段買之後另開；買下的線要體檢自動行車／排班／機廠沒問題才開」）。專案串 cmsg_014Ruc34op9T1GrfC3q17ogB2gZDYGTA57Nz7RKJq8vd53。
- 決策 993；存檔版本、golden schema、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 都沒動。
- GameCore 有改（`fitsGauge` 短路、每月維護費），CI 是全部 shard。

## 做了什麼

| 檔 | 內容 |
| --- | --- |
| `tools/real-timetables/extract_thsr_runs.py`、`metro_runs.json` | 一天 169 班＋33 回送、40 組車；兩端各 7 股（`DEPOT_END_TRACKS`）。 |
| `Sources/GamePresentation/RealLineAcquisition.swift` | `urbanLines` 加高鐵；`holding(half:)`（待避線放得下 300 m 月台）；`ends(of:)`（高鐵兩端三層 7 股）；`turnsBackBetween` 含高鐵（台中折返渡線）；`highSpeedMonthlyFee`（每月 NT$1 億）、`pricedTier`（乘客照支線算）；卡片的 `monthlyFeeText`。 |
| `Sources/GamePresentation/RealLineDepot.swift` | 南港留置線、烏日基地（真實位置）、左營機廠（站南，不是真實位置）；`mayLeaveTheFirstTrack` 含高鐵。 |
| `Sources/GamePresentation/RealLineBundle.swift`、`RailwayGameApp/Views/RealLineAcquisitionCards.swift` | 價錢區塊下面一行「買下後每月另付維護費」。 |
| `Sources/GameCore/Railway/LineAcquisition.swift`、`Economy/Accounts.swift`、`Economy/Operations.swift`、`Economy/LineAccounts.swift` | `monthlyFee`、`dailyFee`、`settleLineFees`、帳的 `dailyLineFee`／`lineFee`。 |
| `Sources/GameCore/Railway/TrackGauge.swift` | `fitsGauge` 短路（第一串）。 |
| `Tests/GameCoreTests/LineAcquisitionTests.swift` | 維護費的 3 個測試。 |
| `Tests/GamePresentationTests/ThsrSaleTests.swift` | `testTheRunsAreTheRealDay`（常駐）；報告：`THSR_SALE_REPORT`、`THSR_WHERE`、`THSR_SALE_PROFIT=<天>`（每天結完帳才印，含各類帳列）、`THSR_LATE=<時>`（各站到站晚點）。 |
| `Tests/GamePresentationTests/CheckupBudgets/Taiwan.swift` | 高鐵的體檢預算。 |

## 量法（release，約 30 分鐘建置）

```sh
swift build -c release -Xswiftc -enable-testing --build-tests --scratch-path /home/user/rel-build
B=/home/user/rel-build/release/GamePresentationTests-test-runner
TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_ONLY='thsr_sched:THSR simple' $B GamePresentationTests.TimetableCheckupFullTests/testTaiwanMetroLines   # 約 1 小時
TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_ONLY='thsr_sched:THSR realistic' $B GamePresentationTests.TimetableCheckupFullTests/testTaiwanMetroLines # 約 25 分
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=thsr DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 $B GamePresentationTests.DepotReturnReportTests/testTheHighSpeedRail  # 約 1 小時，列出沒發的班
THSR_SALE_PROFIT=3 $B GamePresentationTests.ThsrSaleTests/testProfit   # 一天約 30–60 分
```

用 `setsid nohup` 起背景、輸出寫檔（雲端閒置回收會殺掉一般背景程式）。

## 還要做的（照順序）

1. 簡易規則兩端 7 股的一天檢查若仍有沒發：用上面的 `DEPOT_RETURN` 指令看沒發的班從幾點開始、哪一端；兩端最多停幾列（`most standing at the ends`）。若仍是端點停滿，下一個要試的是讓車在端點折返後不被「擋路就回機廠」趕走（決策 297、609 的 `runDepotEntryCandidates`），或把左營機廠搬到站北的真實位置縮短出入庫。
2. 簡易規則量好後，把 `thsr_sched:THSR simple` 的預算寫進 `CheckupBudgets/Taiwan.swift`（擬實的已寫）。
3. 常駐測試：買得下、跑得完一天（`RealLineBoughtAgainTests`、`SharedStationLayoutTests` 若和台鐵共站）。
4. 夜間 `timetable-checkup` 的台灣捷運那個 job 會多約 25 分（擬實）＋1 小時（簡易）：看要不要把高鐵移到自己的 job。
5. `real-line-laying` skill 加一行：月台比待避線長就鋪不下（`holding(half:)`）；中間站有班次起訖要折返渡線；端點股數不夠時簡易規則會沒發。
6. 分段買（高鐵與九州新幹線）是另一張單。

## UNVERIFIED

- 一般玩家第幾年買得起：只量到第 360 天（台北起家現金 NT$3.9 億、每天營業利益 NT$228 萬），之後沒量。
- 全部 shard、iOS 建置與 UI 測試交給 CI；卡片上那一行沒截圖。
