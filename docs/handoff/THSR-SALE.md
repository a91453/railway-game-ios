# THSR-SALE（2026-11-25～26）

## 進度

- 做到哪：台灣高鐵（南港–左營 12 站）可以在台灣新局整條收購，**只在寫實規則（閉塞區間）的局**（Chien 11-26「用對遊戲最好的方式」，由第三串定案）。第一串鋪線、高架、班次與兩端機廠；第二串修擬實規則的死結（台中折返渡線）、烏日基地、兩端 7 股、每月維護費（GameCore）並定價；第三串（分支 `claude/project-thread-cmg93c`）把台北到台南九站改成四股、停站的車進側線月台，並讓簡易規則的局不賣高鐵。決策檔 `docs/decisions/993.md`。
- 已驗證（雲端 Linux release）：擬實規則一天檢查（四股）沒發 0、晚點 38、出庫晚 9、尖峰 +11.7 分（預算已寫）。
- **簡易規則還沒好**：兩端 5 股沒發 59、7 股 62、九站四股 51、再加側線月台 44（共 202 班），沒卡死。所以簡易規則的局先不賣。
- 下一步：「還要做的」第 1 項（另一張單，GameCore）。

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

1. **讓簡易規則也能賣高鐵（另一張單，要改 GameCore）。** 第三串量到的原因：簡易規則沒有閉塞區間，一班車要出發時，它往**下一個停站**的路上只要有一班車停著（停站、折返、收班），或那班車自己也在跟前車，它就不能出發（`RouteFollowing.swift` 的 `followingAuthority(of:route:limit:memo:)` 與 `isLeading(_:onto:for:)`：「A train standing, turning round, ending its service or following another itself, it waits for whole」；`holdsToItsApproach` 是唯一的例外）。高鐵站距長，直達車往下一停站一段就跨好幾站，路上幾乎總有一班在跟車，所以後面的車常常出不去，誤點一路傳下去，過了最晚的發車時間就算沒發。
   - 已排除／已做：端點股數（5→7 股沒變好）；卡死（0）；第 1 天早上車都在南邊是結果不是原因。九站四股＋停站車進側線月台（`RealLineAcquisition.routePreferences(_:stops:keepingRight:onLoops:)`）把 62 降到 44。
   - 修法候選：簡易規則下讓一班車可以跟「自己也在跟車、但路一直在動」的車（一列一列接著跟），或在中間站的月台前讓後車先開到前一站停（像閉塞區間只在站與站之間）。都會動到每條線的簡易規則，要量全部 `timetable-checkup` 與 golden。
   - 修好後：拿掉 `RealBranchLine.onSale` 的 `world.blockSections` 條件、`TimetableCheckupFullTests.testTaiwanMetroLines` 對高鐵只跑寫實的那行，量 `TIMETABLE_CHECKUP … THSR simple` 寫預算。
   - 量的時候：`DEPOT_RETURN_RUNS=1` 會印每班派出的時間與車；`DEPOT_RETURN_WATCH=<秒>-<秒> DEPOT_RETURN_WATCH_AT=<站名>` 印那站每列車在等誰（簡易規則的量法要 `THSR_` 或 `DEPOT_RETURN_SIMPLE` 測試先把 `onSale` 的條件拿掉，不然會 skip）。
2. 常駐測試：買得下、跑得完一天（`RealLineBoughtAgainTests`、`SharedStationLayoutTests` 若和台鐵共站）。
3. 夜間 `timetable-checkup` 的台灣捷運那個 job 多約 25–40 分（只有擬實）：看要不要把高鐵移到自己的 job。
4. `real-line-laying` skill 加一行：月台比待避線長就鋪不下（`holding(half:)`）；中間站有班次起訖要折返渡線；端點股數不是簡易規則沒發的原因；停站的車進側線月台（`onLoops`）。
5. 分段買（高鐵與九州新幹線）是另一張單。
6. 高鐵刻意留在量過的 `.metro` 鋪法（`stationLayout` 排除 `isTaiwanHighSpeedRail`）。改成決策 995 的 `.highSpeed`（待避線一座島寬、更真實）要重量，之後再做。
7. 真實的台中是兩座島式月台＋兩股通過線（六股），遊戲是四股；板橋是一座島式兩股，照舊。

## UNVERIFIED

- 一般玩家第幾年買得起：只量到第 360 天（台北起家現金 NT$3.9 億、每天營業利益 NT$228 萬），之後沒量；光地就 61 億，是後期目標（估計，不是量的）。
- 全部 shard、iOS 建置與 UI 測試交給 CI；卡片上那一行沒截圖。
