# CI 量測（2026-11-07）

> 派工單 CIOPT（session_01YGNNukiXhE7LK51UdBYf4o，`claude/ciopt-5`），遊戲規劃第 54 任派。這份是量到的數字；改了什麼、為什麼，寫在 [決策 620](../decisions/620.md)。前一輪是決策 563（CIOPT-6）與 HANDOFF §1.1 記的 27 分（run 42211389525）。

## 1. 量法

- GitHub Actions API（`gh api`），每個 job 的 `created_at`、`started_at`、`completed_at`，以及每個步驟的開始與結束。
  - 排隊 = `started_at − created_at`。
  - 牆鐘 = 最後一個 job 結束 − run 開始。
- 每個測試 job 的日誌，XCTest 每個測試的秒數照類別加總（`swift-shards.sh` 的 `class_seconds` 同樣的算法）。
- 本機：4 核，Swift 6.4.0，`swift build --build-tests -Xswiftc -warnings-as-errors`（GameCore -O，決策 544）。
  - 用 `swift test --skip-build --filter KaohsiungLightRailDayTests` 量改前與改後。
  - 用 gdb 每隔幾秒對跑著的測試程式印一次所有執行緒的堆疊（42 個樣本），照 GameCore 的函式名數。

## 2. 完整 run：沒有排隊，`rest` 一片變長

| run | 種類 | commit | 牆鐘 | 最久排隊 | build job（建置步驟） | `rest` job（測試步驟） | 最慢的 campaign 片 |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| 41928730361 | 夜間 11-04 | 7ca083b9 | 18.2 分 | 3 s | 8.6 分（430 s） | 9.1 分（470 s） | 7.5 分（campaigns-6、-12） |
| 42124703223 | 夜間 11-05 | 4e244db0 | 20.9 分 | 2 s | 7.5 分（367 s） | 13.1 分（707 s） | 7.9 分（campaigns-6） |
| 42211389525 | 手動 11-06 | 690b669d | 26.7 分 | 7 s | 8.9 分（457 s） | 17.4 分（982 s） | 8.1 分（campaigns-6） |
| 42303936063 | 夜間 11-06 | 0e1e0bd5 | 31.8 分 | 3 s | 9.0 分（452 s） | **22.3 分（1,268 s）** | 8.1 分（campaigns-6） |
| 42317048280 | 手動 11-07 | a3c83a0b | 31.7 分 | 2 s | 8.6 分（434 s） | **22.6 分（1,270 s）** | 7.3 分（campaigns-1） |
| 42343885098 | #1924 PR（完整） | 8de46fa7 | 32.9 分 | 2 s | 7.0 分（332 s，快取） | **25.4 分（1,459 s）** | — |

- 排隊最多 7 s：慢的不是 runner 不夠。
- build、存快取、campaign 片的時間都和決策 563 的數字差不多（build 7.5–9 分、campaign 片 3–8 分）。
- 多出來的 14 分全在 `rest`。它離 job 的 30 分上限只剩 7 分；決策 563 量過慢的 runner 會慢 1.35 倍，那就會逾時。

### 2.1 `rest` 裡變慢的類別（秒，各 run 的類別加總）

| 類別 | 11-04 | 11-05 | 11-06 手動 | 11-06 夜間 | 11-07 手動 | #1924 PR | 權重（改前） |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `KaohsiungLightRailDayTests`（11-06 新加，決策 612） | — | — | — | **428** | **426** | **362** | 沒有 |
| `WenhuLineTests` | 87 | 95 | 119 | 94 | 94 | 119 | 139 |
| `TaoyuanAirportLineTests` | — | 58 | 105 | 83 | 83 | 104 | 45 |
| `Map3DModelPackLockTests` | 60 | 80 | 137 | 81 | 81 | 145 | 100 |
| `Map3DSceneRebuildTests`（11-06 新加） | — | — | — | 64 | 66 | 84 | 沒有 |
| `SingleTrackLengthTests` | — | 46 | 59 | 46 | 46 | 59 | 沒有 |
| `RealLineDepotAdditionTests` | 21 | 28 | 36 | 28 | 28 | 36 | 25 |
| `OldStationCrossoverTests` | 19 | 25 | 34 | 25 | 25 | 34 | 沒有 |
| `rest` 全部的測試秒數 | 359 | 586 | 840 | 1,143 | 1,150 | 1,334 | |
| `rest` 的類別數 | 605 | 626 | 631 | 640 | 640 | | |

- 11-06 手動那一輪，每個類別都慢了約 1.3–1.7 倍（`Map3DModelPackLockTests` 137 s，同一個類別在 11-06 夜間是 81 s）：是那台 runner 慢。
- `KaohsiungLightRailDayTests` 的兩個測試（run 42303936063 的日誌）：
  - `testTheRingRunsTwoRealDays`（簡單、擬實各跑 51 小時，交通管制開著）：401.9 s，其中簡單 189.2 s、擬實 207.0 s。
  - `testTheRingRunsTwoRealDaysWithoutTrafficControl`：25.8 s。

## 3. GamePresentation 的 PR tier

| run | PR | 牆鐘 | build 步驟 | 最慢的一份 | 其他份 |
| --- | --- | ---: | ---: | --- | --- |
| 42339021851 | #1925 road-tunnel | 24.4 分 | 182 s | selected-3 956 s（`KaohsiungLightRailDayTests` 548 s、`Map3DModelPackLockTests` 142 s） | 271–548 s |
| 42341873125 | #1922 map3d-bounce | 17.1 分 | 79 s | selected-3 716 s | 317–551 s |

- `KaohsiungLightRailDayTests` 沒有權重，和 `Map3DModelPackLockTests` 分在同一份。這一份比其他份多 4–7 分。
- gate 等 iOS 的時間（決策 563「等 macOS」）這次只有 0–2 分。

## 4. 為什麼環狀線慢（取樣）

gdb 取樣 42 次（改前，本機）。下面是包含該函式的樣本數，一個樣本可能算進好幾列：

| 函式 | 樣本 |
| --- | ---: |
| `GameWorld.advance` | 29 |
| └ `trafficPlan` | 28 |
| 　└ `trafficPoints` | 17 |
| 　　├ 第 256 行 `plannedPath` | 9 |
| 　　└ 第 257 行 `preferredPath`（同一段路又找一次） | 10 |
| └ `dispatchTrains`、`runDepot*` | 9 |
| （其他 13 個是開局與買線） | |

第 257 行為了知道這段路是不是線的指定路徑，用同樣的參數把 `preferredPath` 又找了一次，而且兩次都沒用世界已經留著的 `PathMemo`。決策 620 改成只找一次，存進那份 memo。

## 5. 改前改後（本機，同一台機器）

| | 改前（`main` fd90b5b4） | 改後 |
| --- | ---: | ---: |
| 簡單 51 小時 | 148.9 s | 97.6 s |
| 擬實 51 小時 | 173.9 s | 116.5 s |
| `testTheRingRunsTwoRealDays` | 331.4 s | 222.6 s |
| 交通管制關掉 51 小時 | 29.4 s | 28.6 s |
| `KaohsiungLightRailDayTests` 合計 | **364.6 s** | **255.1 s**（−30%） |

- 兩天的結果改前改後每一項都一樣：
  - 290 班 0 班沒發；
  - 簡單 0 趟誤點，擬實 168 趟裡 5 趟誤點；
  - 跑了 3,744 km、空車 40 km；交通管制關掉時 3,742 km、空車 38 km；
  - 最多誤點 5 分（交通管制關掉時 3 分），沒有死結。
- `rest` 分兩片的模擬（11-06 夜間與 11-07 手動 run 的逐類別秒數、改後的權重，環狀線照本機比例算成 300 s）：兩片 548／467 s 與 555／467 s，原本一片 1,015–1,022 s。

### 5.1 3D 跟車 10×（CABVIEW-3 的報告測試，規劃要求加量）

在 #1930 的分支 `d325139` 上，加決策 620 的 GameCore 修正前後各跑兩次。指令是 `CABVIEW_REPORT=1 CABVIEW_STEPS=1 CABVIEW_LOOP_SECONDS=40 CABVIEW_CPU=standard swift test --skip-build --filter CabViewTickCostReportTests`，本機 debug 建置。

| | 修正前 | 修正後 |
| --- | --- | --- |
| 迴圈 40 s 跑的遊戲秒數（of 10x） | 161 s（0.40）、139 s（0.35） | 139 s（0.35）、154 s（0.38） |
| 每 tick `advance` | 209–270 ms | 210–270 ms |
| 每 tick work 中位數／最長 | 287／568、283／578 ms | 276／567、274／609 ms |
| `trafficPlan`（空的 memo） | 3,052、3,371 ms | 316、284 ms |
| `deadlock`（空的 memo） | 3,814、3,913 ms | 554、532 ms |
| `routeWaits`（借 `RouteMemo`） | 194、229 ms | 250、246 ms |

- 跟車 10× 沒有變快。穩定跑著時，路徑本來就在借來的 memo 裡，修正只讓 memo 是空的時候快約 10 倍。
- 每 tick 的 200–270 ms 在別處，要另外取樣（決策 620「下一步」第 3 項）。
- `routeWaits` 前後的差（194–229 對 246–250 ms）在兩次重跑之間的起伏之內（每 tick 的 traffic 本身就在 200–314 ms 之間跳）。

## 6. 之後的門檻

下一輪 CIOPT 看下面幾項（每發一版之後看，HANDOFF §1.1）：

- **完整 tier 的牆鐘超過 25 分**：這次改後估約 20–21 分。
- **任何一片的 job 超過 15 分**：`rest-1`／`rest-2` 估約 11 分，campaign 片約 7–8 分。
- **GamePresentation PR tier 最慢的一份比最快的多一倍以上**：通常是一個沒有權重的類別。
- **一個類別超過 150 s**：先看 `time_warnings` 有沒有印「has no weight」或「weight out of date」；再像這次一樣取樣，看是不是 GameCore 的哪一段重複算。

## 7. 驗證

- VERIFIED（Linux 本機）：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；
  - `KaohsiungLightRailDayTests` 改前改後（上表）；
  - `.github/scripts/swift-shards-selftest.sh` 通過；
  - `swift test --skip-build --filter 'ScheduledTrafficTests|CurveSpeedRunTests|GoldenScenarioTests|ReplayFixtureTests|SavedGameTests|QuestionMemoTests|TrafficControlTests|KaohsiungLightRailTests\b'`：147 個測試、0 失敗（1 個要環境變數的跳過）；
  - `.github/scripts/swift-shards.sh run campaigns-12`（`TrafficControlPropertyTests` 等）：106／106 通過，374 s；
  - `.github/scripts/swift-shards.sh run campaigns-9`（`ScheduledTrafficPropertyTests` 等）：88／88 通過，346 s；
  - §5.1 的跟車量測，在 #1930 的分支上。
- 交給 CI：這個 PR 的完整 tier（所有分片）與合併後的夜間 run 的實際牆鐘。
