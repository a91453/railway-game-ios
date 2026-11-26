# THSR-SALE（2026-11-25～26）

## 進度

- 做到哪：台灣高鐵（南港–左營 12 站）可以在台灣新局整條收購。第一串鋪好線、高架、班次與兩端機廠；第二串（分支 `claude/project-thread-9t5f5d`）修好擬實規則的死結（台中折返渡線）、加烏日基地、兩端改 7 股、加每月維護費（GameCore）並定價。決策檔 `docs/decisions/993.md`。
- 已驗證（雲端 Linux release，`-warnings-as-errors`）：建置乾淨；`LineAcquisitionTests` 19 個全過；擬實規則一天檢查（兩端 7 股）沒發 0、晚點 36、出庫晚 10、尖峰 +12 分；收支（從台北開局，帶每月 1 億維護費）第 0、1、2 天公司現金 +955 萬、+903 萬、+905 萬（一年約 33 億；含地 136.6 億約 4.1 年回本、不含地約 2.3 年）。之前以為「每晚結的費用 994 萬」其實是**每天結的所得稅**（`dailyTax`）。
- **沒過：簡易規則（新局預設）一天檢查。** 兩端 5 股沒發 59；改 7 股後沒發 62、晚點 83、出庫晚 25、尖峰 +30 分，沒卡死。所以不是端點股數的問題。沒發的班從第二天 06:55 左營開始，之後兩端整天都有。簡易規則入庫 175 次，擬實 143 次。
- 這串在 11-26 壓縮第 2 次停手。作者把 0.7.0 延到 11/27 晚上（「好好做，不用趕」）。
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

1. **修簡易規則的沒發（擋住開賣的唯一一項）。** 已排除：端點股數（5→7 沒變好）、卡死（0）。嫌疑依序：
   - 決策 297、609：簡易規則沒有閉塞區間，`countsSurplus(blockSections:)`／`runDepotEntryCandidates` 把端點「多出來」或擋路的車送回機廠，送進烏日或另一端，第二天早上該端就缺車。先比兩種規則在第 1 天 05:00（時鐘 104400）每組車停在哪裡：
     ```sh
     DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=thsr DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_SAVE=<檔>.json DEPOT_RETURN_SAVE_AT=104400 DEPOT_RETURN_UNTIL=104460 $B GamePresentationTests.DepotReturnReportTests/testTheHighSpeedRail
     # 拿掉 SIMPLE、CONTROLLED 兩個變數就是擬實規則的對照
     ```
     （這串最後起了這兩個，存在 scratchpad，串結束就沒了，要重跑；約 35 分。）照真實時刻表夜裡南港 10、左營 30 組（烏日 0）；若簡易規則的早上不是這個分佈，就是收班時送錯機廠。
   - 簡易規則跑得比擬實快，車提早到端點，在「下一班的車」還沒輪到時就被當成多的車送走。
   - 修法候選：高鐵的端點不做「多的車回機廠」（只對高鐵或只對有 `endLevels` 3 的端），或讓入庫照時刻表的回送班，不照當下的多寡。
   - 修好後，用 `TIMETABLE_CHECKUP … THSR simple` 量，把預算寫進 `CheckupBudgets/Taiwan.swift`。
   - **到 11/27 下午還修不好**：把 `RealBranchLine.urbanLines` 的高鐵那一列拿掉（程式、月費、測試留著；`testTheRunsAreTheRealDay` 不靠清單），PR 改成「高鐵先不開賣」再交協調者合。
2. 常駐測試：買得下、跑得完一天（`RealLineBoughtAgainTests`、`SharedStationLayoutTests` 若和台鐵共站）。
3. 夜間 `timetable-checkup` 的台灣捷運那個 job 會多約 25 分（擬實）＋1 小時（簡易）：看要不要把高鐵移到自己的 job。
4. `real-line-laying` skill 加一行：月台比待避線長就鋪不下（`holding(half:)`）；中間站有班次起訖要折返渡線；端點股數不是簡易規則沒發的原因（5→7 股沒變好）。
5. 分段買（高鐵與九州新幹線）是另一張單。

## UNVERIFIED

- 一般玩家第幾年買得起：只量到第 360 天（台北起家現金 NT$3.9 億、每天營業利益 NT$228 萬），之後沒量；光地就 61 億，是後期目標（估計，不是量的）。
- 全部 shard、iOS 建置與 UI 測試交給 CI；卡片上那一行沒截圖。
