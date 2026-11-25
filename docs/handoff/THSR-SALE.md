# THSR-SALE（2026-11-25）

## 進度

- 做到哪：台灣高鐵（南港–左營 12 站）已經可以在台灣新局整條收購，鋪線、高架、兩端機廠和真實一天的班次都齊了。**擬實規則第一天早上就死結（台中以南），價錢也還沒定，所以這張 PR 不能合。**
- 已驗證：收購成功（release 與 debug 都是 problem none）；`ThsrSaleTests.testTheRunsAreTheRealDay` 過；擬實規則的一天檢查 not sent 202／202（全部沒發，2938 s）。
- 下一步的第一個指令：重現死結（見下面「死結」，release 約 10 分鐘到 06:48）。

## 派工與範圍

- 派工：專案協調者（Chien 11-26：「台灣高鐵先整條買、價錢照一年淨利約 3～5 年回本＋每月維護費，分段買之後另開；買下的線要體檢自動行車／排班／機廠沒問題才開」）。專案串 cmsg_014Ruc34op9T1GrfC3q17ogBPxXxhjRgHHWFTXCzr5t4xr。
- 雲端 Linux，分支 `claude/project-thread-pnaujm`，決策 993（已在 #2118 認領，**檔還沒寫**）。
- 存檔版本不動、golden schema 不動；`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 沒動。
- **GameCore 有改一行**（`TrackGauge.swift` 的 `fitsGauge` 短路），所以 CI 是全部 shard。
- 避開 OVERSEAS-BUY-LAND（決策 992、存檔 115）的檔：`RealWorldExpansion.swift`、`RealWorldStartArea.swift`、`GameLauncher.swift`、`AirRoutes.swift`、`GameMenuLayout.swift`、`RealWorldPicker.swift`、`OverseasStartLand.swift`、GameCore `GameWorld.swift`、`SavedGame.swift`、`OverseasMaps.swift` 的 `newOverseasGame`。

## 做了什麼

| 檔 | 內容 |
| --- | --- |
| `tools/real-timetables/extract_thsr_runs.py` | 從 rail-reference 台灣高鐵時刻表抽出一天的車次（169 班營運＋33 班回送，40 組車，夜間留置 南港 10、左營 30；`--sets` 印排班）。 |
| `RailwayGameApp/Resources/RealRailways/metro_runs.json` | 加 `thsr_sched:THSR`。各站股道：南港 5、台北 3、板橋 2、桃園 3、新竹 2、苗栗 2、台中 3、彰化 2、雲林 2、嘉義 2、台南 2、左營 5。 |
| `Sources/GamePresentation/RealLineAcquisition.swift` | `urbanLines` 加 `("thsr_sched", "THSR", …, .metro, false)`；`RealLineLayout.holding(half:)`：待避線的直線段至少要放得下月台（高鐵 12 節 300 m，原本 metro 的待避線只有 150 m、其中 50 m 是坡，月台放不下，兩端站的待避線就疊在正線上，收購被「交叉…高度差不到 8 公尺」擋下）。其他線月台放得下，鋪法不變。 |
| `Sources/GamePresentation/RealLineDepot.swift` | `thsrNangang`（南港留置線，10 股）、`thsrZuoying`（左營機廠，30 股；真的機廠在站北，這裡放站南，註解有寫）。 |
| `Sources/GameCore/Railway/TrackGauge.swift` | `fitsGauge`：網路上沒有一般軌道是這班車跑不了的，就直接回 true，不再算每條服務的行程（收購時 40 組車 × 169 班，原本收購 2/3 的時間在這裡）。**改後收購花多久還沒重量。** |
| `Tests/GamePresentationTests/ThsrSaleTests.swift` | `testTheRunsAreTheRealDay`（常駐）；報告用：`THSR_SALE_REPORT`、`THSR_WHERE`（`THSR_DEPOT=0` 不蓋機廠，印每一段軌與月台的經緯度）、`THSR_SALE_PROFIT=<天數>`（印每天搭乘、票收、成本、淨利、稅，最後印「價錢＝幾年的淨利」）。 |
| `Tests/GamePresentationTests/TimetableCheckupTests.swift` | 高鐵用 `side: 1 << 25` 的地圖與 NT$1 兆的錢（不然「餘額不足…需要 NT$ 1,073,541,223」）。 |
| `Tests/GamePresentationTests/DepotReturnReportTests.swift` | `bought(…balance:)` 參數；`testTheHighSpeedRail`。 |
| `Tests/GamePresentationTests/TimetableCheckupAllBoughtTests.swift` | 台灣全買 15 → 16 條。 |
| `Sources/GamePresentation/WhatsNewNext/new/2026-11-25-taiwan-high-speed-rail.txt` | 新功能說明（中英）。 |

## 量到的數字（Linux 雲端 release，VERIFIED）

- **一般玩家**（`ACQUIRE_REPORT=720 ACQUIRE_ONLY=player`，`AcquisitionReportTests.testWhatAnOrdinaryPlayerHas`）：台北起家第 180 天現金 NT$1.67 億（每天營業利益 NT$181 萬）、第 360 天 NT$3.90 億（每天 NT$228 萬）；新竹起家第 360 天 NT$1.93 億。
- **高鐵價錢（現在的算法）**：沒有地的檢查世界是 NT$10.7 億（建設＋車＋搭乘人數的價值，`.metro` 等級每位每日乘客 $100）。擴張局另要買沿線約 27 格地（每格依序 +NT$1,500 萬），沒印出總價。
- 粗算：照現在的價錢，一般玩家大約第 2～3 年買得起（不含地）。**一年淨利還沒量到**（30 天的利潤報告跑到一半被我停掉；而且擬實規則死結，利潤量不準）。所以「新局第幾年買得起、買了幾年回本」還不能跟 Chien 講。

## 死結（擬實規則，未修）

重現（release，約 10 分鐘到 06:48）：

```sh
swift build -c release -Xswiftc -enable-testing --build-tests --scratch-path /home/user/rel-build
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=thsr DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_STUCK_MIN=2 \
  /home/user/rel-build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testTheHighSpeedRail
```

- 第 0 天 06:34：13、14 號在台中（往南、彰化方向，走 773→774），15 號在 774 上往北（773→772 進台中）；15 等 13、17 等 14，06:35 自己解開。14 號那趟是回送（「左營機廠@05:34 台中@06:25」）。
- 06:48 起越卡越多：14、16（彰化）、17、18（雲林）、19（嘉義）、20…到 08:56 已經 22 列，北段（南港–台中）的車照常跑。
- 推測（**UNVERIFIED，沒逐條印出來**）：台中 3 股在台中折返的班次＋左營出庫往北的回送，在台中南邊咽喉的單一 edge 上對頭；擬實規則的進路保留比簡化規則長。先懷疑：(1) 台中到彰化間的正線與渡線是不是只有一條 edge 兩個方向共用（`THSR_WHERE=1` 印出 772–774 的段落與 `together` 第二正線是不是真的有接上）；(2) 左營→台中的回送是否該從左營發而不是左營機廠；(3) 台中待避線長度是否因 `holding(half:)` 變長而跟渡線重疊。
- 簡化規則的一天檢查跑到一半被停掉，**沒結果**（`TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_ONLY="thsr_sched:THSR simple"`，`TimetableCheckupFullTests/testTaiwanMetroLines`）。

## 還要做的（照順序）

1. 修擬實規則的死結，再跑簡化與擬實兩種一天檢查（runs not sent、死結、空跑）和 `DEPOT_RETURN` 看機廠進出正常。修不好就先把 `urbanLines` 那一行拿掉（不開賣），其餘留著。
2. 擬實一天要 2938 s，夜間 `timetable-checkup` 那五個 job 會多很多時間：看要不要把高鐵放到自己的 job，或只跑簡化。
3. 量 30 天利潤（`THSR_SALE_PROFIT=30`，`ThsrSaleTests/testProfit`；stdout 會被緩衝，等它跑完再看），定價錢：一年淨利 × 3～5 年＋每月維護費（可能要在 GamePresentation 給高鐵自己的等級，`LineAcquisition.Tier`）。然後跟 Chien 講「新局大概第幾年買得起、買了幾年回本」。
4. 重量收購要幾秒（`fitsGauge` 短路後）。
5. 常駐測試：買得下、跑得完一天；`RealLineBoughtAgainTests`（再買一次）；`SharedStationLayoutTests` 若台北／板橋／左營和台鐵共站。檢查的預算（budget）照量到的設。
6. 寫決策 993（五方各一行、參考對照表：`rail-reference/regions/taiwan/source/` 的高鐵時刻表 → `extract_thsr_runs.py` → `metro_runs.json`），`real-line-laying` skill 加一行「月台比待避線長就鋪不下」的教訓。
7. 分段買（高鐵和九州新幹線）是另一張單，不在這裡。

## UNVERIFIED

- 死結原因是推測。
- `fitsGauge` 短路後的收購時間沒重量；全部 shard 交給 CI。
- 利潤、回本年數都沒量完。
