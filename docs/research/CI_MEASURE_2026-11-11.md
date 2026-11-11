# CI 量測（2026-11-11）

> 派工單 CIOPT-7（session_01YGNNuqLntc6Wem467zU1ac，`claude/ciopt-7`），遊戲規劃第 60 任派。這份是量到的數字；改了什麼、為什麼，寫在 [決策 679](../decisions/679.md)。前兩輪是 [11-07 的量測](CI_MEASURE_2026-11-07.md)（決策 620）與決策 639、640（CI-SLIM，11-08）。

## 1. 量法

- GitHub Actions API：每個 job 的 `created_at`、`started_at`、`completed_at` 與每個步驟的開始、結束。
  - 排隊 = `started_at − created_at`；牆鐘 = 最後一個 job 結束 − run 開始。
- 每個測試 job 的日誌：XCTest 每個測試的秒數照類別加總（`swift-shards.sh` 的 `class_seconds` 同樣的算法），以及 `time_warnings` 印的警告。
- runner 快慢：每個類別取各 run 裡最快的一次當 1，同一個 job 裡所有類別的倍數取中位數。
- full lane：`ios-build.yml` 在 `main` 上 `workflow_dispatch` 的 run（`ios-full-lane.yml` 只是啟動它的那個，它綠不代表 full lane 綠）。失敗的那幾次讀了 `ipad-tutorial-trace` 與 xcresult 裡的 App 記錄。
- 本機：4 核，Swift 6.4.0，`swift build --build-tests -Xswiftc -warnings-as-errors`；gdb 每隔幾秒印一次跑著的測試程式所有執行緒的堆疊（45 個樣本）。

## 2. 完整 run

| run | 種類 | commit | 牆鐘 | 最久排隊 | build job（建置步驟） | rest-1（測試步驟） | rest-2（測試步驟） | 最慢的 campaign 片 |
| --- | --- | --- | ---: | ---: | --- | --- | --- | --- |
| 42414041231 | 夜間 11-07 | 7665f73c | 21.4 分 | 3 s | 7.1 分（347 s） | 7.2 分（359 s） | 13.8 分（769 s） | 7.3 分（campaigns-1） |
| 42489852187 | 手動 11-08 | dc4a436e | 22.2 分 | 2 s | 8.9 分（453 s） | 12.8 分（702 s） | 9.9 分（509 s） | 9.1 分（campaigns-9） |
| 42524746914 | 夜間 11-08 | d86bcdc9 | 23.2 分 | 3 s | 8.8 分（439 s） | 14.0 分（770 s） | 8.4 分（441 s） | 8.4 分（campaigns-7） |
| 42702212708 | 手動 11-09 | aeb3eef3 | 18.4 分 | 3 s | 7.0 分（340 s） | 9.1 分（473 s） | 10.8 分（576 s） | 9.2 分（campaigns-9） |
| 42731368945 | 夜間 11-09 | cd0fbab9 | **26.7 分** | 2 s | 12.8 分（686 s） | 13.4 分（717 s） | 10.7 分（561 s） | 10.1 分（campaigns-6） |
| 42915103667 | 夜間 11-10 | 2b75f91b | 23.2 分 | 2 s | 11.3 分（574 s） | 9.7 分（479 s） | 11.3 分（580 s） | 10.0 分（campaigns-6） |
| 42954245069 | push（完整 tier）11-11 | 50fdb1df | **25.7 分** | 2 s | 11.2 分（580 s） | 13.8 分（759 s） | 10.8 分（584 s） | 10.2 分（campaigns-6） |

完整 tier 的 pull request run：

| run | PR | 牆鐘 | build job（建置步驟） | rest-1／rest-2 | 備註 |
| --- | --- | ---: | --- | --- | --- |
| 42949150339 | #2028 | **26.4 分** | 12.0 分（644 s） | 13.9 分（754 s）／9.0 分（450 s） | campaigns-6 10.2 分 |
| 42942144469 | #2028 | **27.2 分** | 11.3 分（604 s） | 9.2／8.9 分 | gate 等 iOS 6.2 分 |
| 42930405065 | #2025 | 25.0 分 | 12.1 分（635 s） | 11.3／10.8 分 | |
| 42894320577 | | **27.4 分** | 12.1 分（631 s） | rest-1 13.7 分（751 s） | |
| 42883123127 | | **26.4 分** | 12.0 分（632 s） | rest-1 13.7 分（757 s） | |
| 42877510998 | | **26.8 分** | 12.3 分（651 s） | 8.9／11.4 分 | campaigns-9 10.1 分 |
| 42629054354 | （11-09） | 24.8 分 | 9.6 分（468 s） | rest-1 13.6 分（749 s） | |

- Linux 的排隊最多 2–4 s：慢的不是 runner 不夠。
- 沒有任何一片印「30-minute limit」或「weight out of date」；每一輪都只印兩行「has no CLASS_WEIGHTS entry」：`RealLineRebuildTests`、`RealLineListingTests`。

### 2.1 runner 有三種快慢，沒有越來越慢

- 同一個類別在不同 job 的秒數落在三群：最快的 1.0 倍、約 1.35–1.4 倍、約 1.7–1.87 倍。11-07 到 11-11 的每一輪，15 片裡都有 7–13 片在 1.3 倍以上；比例沒有隨日期變。
- 建置步驟也是兩群：340–470 s 與 574–686 s。最近 10 次從頭建置有 9 次落在慢的一群。
- 本機同一台機器從頭建置：11-07 的 commit 7665f73c 392.8 s，`main` b72f1b3f 386.9 s。**建置變長是抽到的 runner，不是程式變多。**
- 所以牆鐘 = 慢 runner 的 build 約 12 分 + 慢 runner 上最慢的一片約 14 分。build 這半邊這一輪沒有不靠快取或改 runner 的辦法（下一步在決策 679）；能動的是最慢的那一片。

### 2.2 最慢的類別（秒，各 run 的類別加總，最快到最慢）

| 類別 | 秒 | 在哪一片 | 權重（改前） |
| --- | ---: | --- | ---: |
| `Map3DStationExteriorsTests` | **172–289** | rest-1 | 231 |
| `Map3DSceneMemoryTests` | **202–257** | campaigns-1 | 221 |
| `KaohsiungLightRailDayTests` | 103–188 | campaigns-5 | 187 |
| `Map3DModelPackLockTests` | 58–165 | campaigns-4 | 152 |
| `WenhuLineTests` | 68–125 | campaigns-3 | 139 |
| `TaoyuanAirportLineTests` | 73–121 | campaigns-9 | 107 |
| `HighSpeedDemoTests` | 92–119 | | 77 |
| `RealLineRebuildTests`（決策 639 之後新加） | 66–106 | rest-1 | 沒有 |
| `RealLineListingTests`（決策 639 之後新加） | 58–100 | rest-2 | 沒有 |

- rest-1 在慢 runner 上（run 42949150339）：336 個類別、679 s，其中 `Map3DStationExteriorsTests` 279 s、`RealLineRebuildTests` 106 s；同一輪 rest-2 378 s。
- `Map3DStationExteriorsTests` 裡一個測試 `testClearOfTheTrackAndThePlatforms` 佔 154 s（快的 runner，全類別 182 s）到約 250 s（慢的）；它是第一個把 11 個研究的場景建出來的測試，其他測試用它留下的。
- `Map3DSceneMemoryTests` 有 7 個測試，最大的 `testThe3DMapRoundBanqiaoFitsAPhone` 69.6 s：時間平均散在各測試，這一輪沒有取樣。

### 2.3 GamePresentation 的 PR tier（8 份，測試步驟秒數）

| run | 最快–最慢 | 倍數 | gate 等 iOS |
| --- | --- | ---: | ---: |
| 42869958124 | 307–553 s | 1.80 | 10.2 分 |
| 42740284470 | 297–637 s | 2.14 | |
| 42722033636 | 328–651 s | 1.98 | 17.8 分 |
| 42503185596 | 304–684 s | 2.25 | |

最慢與最快的差和 §2.1 的 runner 倍數（1.7–1.87）差不多：是抽到的 runner，不是哪一份特別重。

## 3. 四條門檻（11-07 量測 §6）

| 門檻 | 這一輪 | 過線 |
| --- | --- | --- |
| 完整 tier 牆鐘超過 25 分 | PR run 25.0–27.4 分（7 次有 5 次超過）；夜間 26.7 分一次；push 25.7 分 | **過** |
| 任何一片的 job 超過 15 分 | 最長 14.0 分（rest-1） | 沒過，差 1 分 |
| GamePresentation PR tier 最慢比最快多一倍以上 | 1.80–2.25 倍 | 在線上，原因是 runner |
| 一個類別超過 150 s | `Map3DStationExteriorsTests`、`Map3DSceneMemoryTests`（另兩個只在慢 runner 上） | **過** |

## 4. iOS

### 4.1 PR 的 iOS gate（`Xcode build` job）

| 日期 | 次數 | 排隊中位／最久／超過 20 分的次數 | UI 測試步驟中位／最久／超過 6 分的次數 |
| --- | ---: | --- | --- |
| 11-04 | 20 | 0.1／5.3 分／0 | 8.7／10.9 分／18 |
| 11-05 | 61 | 0.1／48.2 分／5 | 7.7／10.3 分／51 |
| 11-06 | 42 | 0.1／49.2 分／6 | 7.8／14.0 分／35 |
| 11-07 | 52 | 0.1／52.7 分／6 | 6.6／10.9 分／35 |
| 11-08 | 43 | 0.1／74.8 分／9 | 6.1／8.6 分／22（42 次裡） |
| 11-09 | 19 | 0.0／14.1 分／0 | 4.9／8.1 分／5 |
| 11-10 | 5 | 0／0.1 分／0 | 6.0／7.2 分／2 |
| 11-11 | 3 | 0／0.1 分／0 | 6.1／6.6 分／2 |

- 決策 640（#1970，11-08）之後 UI 步驟從 7.7–8.7 分降到約 6 分，貼著線。run 42949150252 的 gate 是 4 個測試、160.8 s 的測試時間（`StartSaveFlowSmokeTests` 大字 71.4 s、`TutorialUITests` 路線那步 31.7 s、`ToolbarSmokeTests` 英文 29.4 s、`TutorialUITests` 蓋軌道 28.3 s），其餘是開模擬器與裝 App。
- macOS 排隊：11-09 起沒有超過 20 分的。11-05 到 11-08 每天 5–9 次超過，是那幾天 PR 多（每天 42–61 次）。
- 這裡不改：四個測試都是只有模擬器能答的，剩下的秒數不在測試裡。

### 4.2 full lane（`ios-build.yml`，`main`）最近 5 輪離上限多遠

上限：build job 115 分（UI 步驟 90）；second、lessons、map 各 103 分（步驟 75）；iPad 80 分（步驟 30）。

| run | 結果 | build（UI 步驟） | second | lessons | map | iPad（步驟） |
| --- | --- | --- | ---: | ---: | ---: | --- |
| 42921933667（11-10 23:16） | 綠，112.5 分 | 54.9（30.1） | 61.2 | 52.5 | 37.8 | 21.7（10.0） |
| 42736226266（11-10 01:30） | 紅 | 51.6 | 39.2 | 43.6 | 38.8 | 27.7，**測試紅**（12.0） |
| 42702233354（11-09） | 重跑後綠 | 60.0（34.4） | 57.4 | 50.1 | 33.3 | 29.1（12.6） |
| 42527935599（11-08 21:59） | 紅 | 63.8，**紅**（44.5：三次「Failed to launch」） | 47.5 | 45.6 | 46.9 | 20.6 |
| 42489862739（11-08 14:27） | 紅 | 60.7 | | | | **步驟撞到 30 分上限** |

- 再往前兩輪（42444107304、42417467175）iPad 步驟也撞到 30 分；#1966、#1993、#1998、#2004（決策 667）之後是 8.4–12.6 分，離 30 分有 17 分以上。
- 其他 job 離上限都在 40 分以上。沒有一項在 10 分以內。
- 規劃單上寫「最近四晚都綠」，那是 `ios-full-lane.yml`（啟動的那個）；`ios-build.yml` 的 full lane 在 11-07、11-08（三次）、11-10 01:30 是紅的。

### 4.3 七天內紅過兩次、沒有程式原因的測試

`TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds`，iPad，「The folded card did not open」（`openCard`，教學第 5 步「點車站」）：

| | run | job |
| --- | --- | --- |
| #1999 的 PR run（11-08 21:06） | 42523483957 | 128861971905 |
| `main` cd0fbab 的 full lane（11-10） | 42736226266 | 129595753264 |

兩次的 App 記錄（`UITestTrace`）與 xcresult 是同一件事：

1. XCTest 讀到收起的卡片（膠囊 `tutorial.unfold`）在 (726.5, 876)、寬 287.5 高 44，連續約 1 秒沒動（`waitUntilSettled` 通過）。
2. XCTest 按它的中心 (870, 898)。
3. App 記下「touch began at (870, 898) view MapGestureView」，沒有「action tutorial.unfold」：手指落下時那裡已經是地圖。
4. 失敗當下的畫面樹裡，膠囊在 (94, 104)（左上角），大小一樣。

所以不是按鈕沒反應：膠囊在站穩 1 秒之後換了位置（`TutorialCardPlacement` 的輸入——目標、控制列、面板、地圖的框——有一個晚到）。哪一個晚到，Linux 上重現不了（UNVERIFIED，要模擬器）。決策 679 讓 `openCard` 在沒按到時就它現在的位置再按一次；膠囊為什麼在這一步過了幾秒才搬家，交給規劃判斷要不要另外派（玩家也可能看到它跳一下）。

七天內其他的 PR iOS 紅：11-07 四次「Export Swift strings with Xcode」（#1949 已修）、`ipad-fixes` 分支自己的改動。

## 5. 為什麼 `Map3DStationExteriorsTests` 慢（取樣）

`testClearOfTheTrackAndThePlatforms`，本機改前 210.5 s，gdb 取樣 45 次。包含該函式的樣本數（一個樣本可能算進好幾列）：

| 函式 | 樣本 |
| --- | ---: |
| `Map3DStationExteriorsTests.built(round:)` | 24 |
| └ `Map3DScene.Builder.addTrack` | 10 |
| 　└ `Builder.contains(x:y:)` | 8 |
| └ `addGround(water:)` | 6 |
| └ `Map3DTrenches.cut`、`outsideTrenches` | 5 |
| `HighSpeedDemo.make`（高鐵示範開局，全程只做一次） | 10 |
| `world(round:)`（六個台鐵研究各開一局、鋪真實路線） | 9 |
| `inTheGauge`（測試自己的檢查） | 5 |
| 最裡層是「複製整個 `Map3DScene.Builder`」或「釋放那份複製」 | **11** |

- 那 11 個樣本有 7 個在 `addTrack` 裡：它對每一條取樣線的每一個點問 `contains(x:y:)`（點在不在這塊區域裡，只比四個數）。Linux 上 GamePresentation 不開 -O（決策 544），沒最佳化的建置每問一次就把整個 Builder（幾十個字典與陣列）複製一份再釋放。
- iOS 的建置開 -O（決策 624），沒有這份複製；這是 Linux 測試才付的錢。
- 其餘 4 個散在 `addGround`、`Map3DTrackCover.init`、`addPlatforms` 各一兩個樣本，沒有動。

## 6. 改前改後

### 6.1 本機（同一台機器）

| | 改前（`main` b72f1b3f） | 改後 |
| --- | ---: | ---: |
| `testClearOfTheTrackAndThePlatforms` | 210.5 s | **167.4 s**（−20%） |
| `Map3DStationExteriorsTests` 全類別（16 個測試） | 沒量 | 201.4 s |

- `addTrack` 回傳的格子與畫出的軌道沒有變：改的只是「點在不在區域裡」問誰，四個比較式一字不差。`Map3DStationExteriorsTests`（16 個測試）、`Map3DSceneRebuildTests`（4 個測試）改後全過。

### 6.2 `rest` 兩片照新的權重重分（用同一輪日誌的類別秒數重算）

| run | 改前 rest-1／rest-2 | 只加權重 | 加權重，車站外觀照本機比例快 17% |
| --- | --- | --- | --- |
| 42949150339（rest-1 抽到慢的） | 679／378 s | 632／425 s | 584／425 s |
| 42954245069（rest-1 抽到慢的） | 681／489 s | 655／515 s | 607／515 s |
| 42915103667（rest-1 抽到快的） | 435／486 s | 447／474 s | 416／474 s |

- 加了權重之後 `RealLineRebuildTests` 與 `RealLineListingTests` 都在 rest-2，`Map3DStationExteriorsTests` 自己在 rest-1。
- 慢 runner 上最慢的一片少約 75–95 s 的測試（約 1.3–1.6 分）。估完整 tier 的 PR run 從 26–27 分到約 25 分：**還是貼著線**，因為另一半是慢 runner 的 build（約 12 分），這一輪沒有動它。
- 這個 PR 自己的 CI 時間寫在決策 679「驗證」與 PR 說明。

## 7. 之後的門檻

沿用 11-07 的四條，改兩處：

- **完整 tier 的牆鐘**：看 5 次的中位數，不看單次。一次抽到慢的 build（約 12 分）加慢的 rest（約 12–14 分）就是 25–27 分，和程式無關；中位數超過 25 分才算過線。
- **build job 的建置步驟**：這一輪新加。本機從頭建置超過 430 s（這次 387–393 s），或 CI 快的那一群超過 500 s（這次 340–470 s），才是程式讓建置變慢，要看是哪個模組。
- 任何一片的 job 超過 15 分、GamePresentation PR tier 差一倍以上、一個類別超過 150 s：照舊。差一倍先用 §2.1 的算法看是不是 runner。
- full lane：任何一個 job 或步驟離上限不到 10 分；同一個測試七天內紅兩次。

## 8. 驗證

- VERIFIED（Linux 本機）：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；
  - `swift test --skip-build --filter 'Map3DStationExteriorsTests|Map3DSceneRebuildTests'`：20 個測試、0 失敗（1 個要環境變數的跳過），293.2 s；
  - `testClearOfTheTrackAndThePlatforms` 改前 210.5 s、改後 167.4 s；
  - `.github/scripts/swift-shards-selftest.sh` 通過；
  - `SWIFT_TEST_LIST_FILE=… swift-shards.sh select rest-1`／`rest-2`：兩個新權重的類別在 rest-2，`Map3DStationExteriorsTests` 在 rest-1；
  - `python3 -I tools/golden-checks/doc_numbers.py --check`。
- UNVERIFIED LOCALLY（要 macOS／Xcode 的 CI）：`TutorialUITests.openCard` 的再按一次。這個 PR 動了教學的檔案，PR 的 iOS run 會跑 iPad 教學測試。
- 交給 CI：這個 PR 的完整 tier 與合併後夜間 run 的實際牆鐘。
