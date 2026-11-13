# CI 量測（2026-11-13）

> 派工單 CIOPT-8（session_01YGNNunYM5mSwBDcxy53H9s，`claude/ciopt-8`），遊戲規劃第 64 任派。這份是量到的數字；改了什麼、為什麼，寫在 [決策 719](../decisions/719.md)。上一輪是 [11-11 的量測](CI_MEASURE_2026-11-11.md)（決策 679），門檻沿用它的 §7。

## 1. 量法

- GitHub Actions API：每個 job 的 `created_at`、`started_at`、`completed_at` 與每個步驟的開始、結束。排隊 = `started_at − created_at`。
- 日誌：release archive 的 `xcodebuild` 輸出裡每個模組第一行與最後一行的時間；rest 兩份的 XCTest 每個測試秒數照類別加總，以及 `time_warnings` 印的警告。
- 沒有為了量測多開任何 run。全部是 11-11 到 11-13 已經跑過的 run，加上這個 PR 自己的 run（§7）。
- 時間都是 UTC。

## 2. Release archive（超過門檻，改了）

`release-archive.yml` 只有一個 job，上限 30 分。11-13 的 12 次 PR run：

| 結果 | 次數 | 整個 run（分） |
| --- | ---: | --- |
| 成功 | 6 | 18.8、24.2、26.1、27.4、28.1、28.7 |
| 在 30 分被取消 | 6 | 30.4、30.4、30.5、31.0、31.3、32.1（其中 43379717776 重跑一次，也被取消） |

11-10 到 11-12 的夜間與 PR run 成功時是 24.0–29.3 分：平常就離上限只有 1–6 分。

時間在哪裡（讀兩個 run 的日誌）：

| | 快的機器：run 43368544725（成功，18.8 分） | 慢的機器：run 43379717776 第 2 次（取消） |
| --- | ---: | ---: |
| checkout | 18 s | 37 s |
| `-showBuildSettings` | 25 s | 45 s |
| 抓套件 | 9 s | 差不多 |
| GameCore 編譯 | 2.3 分 | 4.0 分 |
| **GamePresentation 編譯** | **12.6 分** | **23.1 分** |
| 資源、Metal | 0.3 分 | 沒跑到 |
| App 編譯 | 2.1 分 | 開始 27 秒後被取消 |
| 連結、dSYM | 0.1 分 | 沒跑到 |
| 封存步驟合計 | 17.8 分 | 超過 28.8 分 |

- 排隊是 0。套件不用下載（`-disableAutomaticPackageResolution`，沒有外部套件）。
- 整個 run 幾乎是一件事：Release 把 GamePresentation（609 個檔、約 178,600 行）當成一個模組一次最佳化編譯。這一步在日誌裡是一行都不印的 12–23 分鐘。
- 慢的那台每一步都慢 1.5–1.8 倍（和 11-11 量到的 runner 三群一致），GamePresentation 那一步 23.1 分，後面還要約 4 分，所以一定超過 30。
- 同一天 PR 的 iOS gate 在 03:38–03:48 開始的三次 run，Debug 建置也從平常的 12–14 分變成 20–25 分（§5）：是同一批慢機器，不是 release archive 自己的問題。

結論：不是排隊、不是套件、不是快取能解的（任何一個檔改了，整個模組都要重編）。改法在決策 719：PR 的 run 逐檔編譯，夜間與手動維持整模組，上限 45 分。

## 3. 完整的 `ci.yml`（超過門檻，改了）

### 3.1 `main` 上的完整 run

| run | 種類 | commit | 牆鐘 | build job（建置步驟） | rest-1 測試步驟 | rest-2 測試步驟 | 最慢的 campaign 片 |
| --- | --- | --- | ---: | --- | ---: | ---: | --- |
| 43323678447 | 夜間 11-12 | cfc051d4 | 22.4 分 | 8.1 分（401 s，沒有快取） | 743 s（job 13.6 分） | 498 s | campaigns-6 538 s |
| 43345319124 | 手動 11-13 | 47d93bea | 23.7 分 | 12.2 分（650 s） | 495 s | 551 s | campaigns-6 409 s |
| 43395636723 | push（完整 tier） | 83449952 | 25.1 分 | 9.4 分（463 s） | 822 s（**job 15.1 分**） | 763 s | campaigns-13 432 s |
| 43406280254 | push（完整 tier） | 9a40b427 | 25.3 分 | 8.5 分（413 s） | 645 s | 907 s（**job 16.2 分**） | campaigns-9 433 s |
| 43406085807 | 手動 11-13 | 3be35084 | 26.8 分 | 8.5 分（426 s） | 614 s | 984 s（**job 17.5 分**） | campaigns-6 549 s |

Linux 排隊 2–3 s。5 次牆鐘的中位數 25.1 分，在 25 分的線上。

### 3.2 完整 tier 的 PR run（11-13，四次）

| run | 分支 | 到最後一個測試 job（分） | 到 gate（分） | 建置步驟 | rest-1 job／測試 | rest-2 job／測試 | 最慢的 campaign 片 |
| --- | --- | ---: | ---: | ---: | --- | --- | --- |
| 43402962214 | claude/close-track | 26.8 | 28.4 | 488 s | **16.4 分**／917 s | 10.0 分／521 s | campaigns-9 438 s |
| 43402960284 | claude/pending-close | 24.9 | 26.6 | 373 s | **15.5 分**／862 s | **16.6 分**／928 s | campaigns-6 509 s |
| 43398073587 | claude/pending-close | 28.4 | 28.6 | 554 s | **16.5 分**／923 s | 10.4 分／553 s | campaigns-7 430 s |
| 43392035945 | claude/term-loans | 27.1 | 27.2 | 395 s | 11.2 分／552 s | **17.3 分**／979 s | campaigns-13 436 s |

中位數 27.0 分（到 gate 27.8 分）。四次都是 rest 的其中一份最後跑完。四次都用了 `main` 的建置快取。

GamePresentation tier 的 PR run（四次：43402963340、43393758324、43385800445、43379717224）：到最後一個測試 job 21.5–25.3 分；`selected-1`…`selected-8` 的測試步驟最快 292–360 s、最慢 668–945 s，差 1.9–3.2 倍。11-11 已經查過這是 runner 的三群加上類別分配；這次最慢的一片（`selected-8` 945 s，job 17.6 分）在 43379717224，同一個時段 macOS 也慢。沒有動它，留在 §8。

### 3.3 對門檻

| 門檻（11-11 §7） | 這次 | 過線？ |
| --- | --- | --- |
| 完整 tier 牆鐘 5 次中位數 > 25 分 | `main` 25.1 分；PR 27.0 分 | 過 |
| 任何一片的 job > 15 分 | rest-1 或 rest-2 15.1–17.5 分，8 個完整 tier 有 7 個 | **過** |
| 一個類別 > 150 s | `HongKongMapTests` 184 s | **過** |
| CI 快的一群建置 > 500 s | 373–463 s（慢的 488–650 s） | 沒過 |
| PR 的完整 tier > 30 分（派工單） | 最長 28.4 分 | 沒過 |

### 3.4 rest 為什麼變長

rest 兩份的測試合計，11-11 是 1,050–1,340 s，現在 1,360–1,790 s。各類別的秒數（run 43406085807 的 rest-2 與 43395636723 的 rest-1，兩台都是慢的那群）：

| 類別 | 秒 | 權重 | 在哪一份 |
| --- | ---: | --- | --- |
| `HongKongMapTests`（11-12 新加） | 184 | 沒有 | rest-2 |
| `Map3DFarViewTests`（新加） | 135 | 沒有 | rest-1 |
| `RealLineRebuildTests` | 105 | 106 | rest-2 |
| `RealLineListingTests` | 99 | 100 | rest-2 |
| `Map3DStationExteriorsTests` | 94 | 231 | rest-1 |
| `DemoRealLinesEverySystemTests`（新加） | 78 | 沒有 | rest-2 |
| `SingleTrackLengthTests` | 55 | 有 | rest-2 |
| `WenhuUndergroundTests`（新加） | 52 | 沒有 | rest-2 |
| `AirportLineWholeIslandTests`、`HongKongRailwaysTests` | 各 38 | 沒有 | rest-1 |

- `time_warnings` 點名三個「沒有權重」：`HongKongMapTests`、`Map3DFarViewTests`、`DemoRealLinesEverySystemTests`。沒有權重的類別當 1 秒分配，所以 184 秒的 `HongKongMapTests` 和另外三個最重的落在同一份。
- 5 秒以上、沒有權重的類別一共 23 個，合計約 760 s。
- `HongKongMapTests` 的 184 s 裡，`testTheTungChungLineRunsOnTheMap` 110.5 s（買下東涌綫、跑 51 個小時）、`testTheDemoLaysEveryLineWithTrains` 44.5 s。
- `Map3DFarViewTests` 的 135 s 是一個測試：`testTheFarthestViewOfTaipeiIsWithinBudget` 134.5 s（整個台北的場景建一次）。

campaigns 各片的測試步驟（43406085807、43406280254、43395636723、43402960284 四次的中位數）：-1 285 s、-2 309、-3 353、-4 367、-5 329、-6 460、-7 377、-8 273、-9 339、-10 317、-11 343、-12 311、-13 379；單次 189–549 s。rest 是 734 與 918 s。

## 4. 其他不算在門檻裡、但看到的

- `Stack frames over 32 KB (reminder)` 這個 job 在 8 個 PR run 裡跑 13.3–20.1 分（它自己把 GamePresentation 和 GameCore 最佳化編一次）。gate 不等它，所以不影響 PR 能不能合併，但每個 run 佔一台 Linux 機器十幾分鐘。沒有動，留在 §8。

## 5. PR 的 iOS gate 與 full lane（沒超過要動手的門檻）

PR 的 `Xcode build (iOS Simulator)`，11-12 的 12 次與 11-13 的 13 次：

| 日 | 次數 | 排隊中位／最長 | 排超過 20 分 | 建置步驟中位／最長 | UI 步驟中位／最長 | job 中位／最長 |
| --- | ---: | --- | ---: | --- | --- | --- |
| 11-12 | 12 | 0.1／9.2 分 | 0 | 13.3／15.5 分 | 6.3／7.5 分 | 26.0／29.4 分 |
| 11-13 | 13 | 0.1／16.4 分 | 0 | 13.7／25.0 分 | 6.6／8.2 分 | 27.4／42.2 分 |

- UI 步驟的中位數 6.3–6.6 分，比「約 6 分」多一成；24 次有 14 次超過 6 分。派工單的線是慢兩成才動，沒到。決策 679 已經記過：四個測試都只有模擬器能答，160 s 以外是開模擬器。
- 排隊最長 16.4 分，沒有超過 20 分的。排超過 2 分的 9 次。
- 11-13 03:38–03:48 開始的三次（43358462164、43359247659、43360276382）排隊 9–16 分、建置 20–25 分：同時有 full lane、好幾個截圖 run 與 release archive 在搶五台 macOS。

full lane（`main` 上的 `ios-build.yml`）：

| run | 牆鐘 | 結果 |
| --- | ---: | --- |
| 43123257974（11-11） | 105.5 分 | 綠 |
| 43164222232（11-12） | 114.8 分 | 綠 |
| 43200623442（11-12） | 139.3 分 | 綠 |
| 43330145389（11-12 夜間） | 122.3 分 | 綠 |
| 43345979625（11-13） | 118.0 分 | 綠 |

| job | 最長的 UI 步驟／上限 | 最長的 job／上限 | 離上限 |
| --- | --- | --- | ---: |
| build | 38.2／90 分 | 63.0／115 分 | 52 分 |
| second | 38.8／75 分 | 62.5／103 分 | 36 分 |
| lessons | 38.0／75 分 | 61.9／103 分 | 37 分 |
| map | 27.9／75 分 | 50.8／103 分 | 47 分 |
| iPad | 14.4／30 分 | 33.0／80 分 | 16 分（步驟） |

- 沒有任何 job 或步驟離上限不到 10 分。五次都綠，沒有同一個測試紅兩次。
- map 那個 job「排隊」35–62 分不是等機器：矩陣 `max-parallel: 2`，它等前兩個之一跑完（決策 604）。
- 43406269578（11-13 10:04 開始）量的時候還在跑，沒有算進來。

## 6. `website-screenshots.yml`（沒有便宜的改法，沒動）

11-12 到 11-13 的 13 次：

| | 排隊 | job | `Build for testing` | 開模擬器 | `Take the screenshots` | 其他 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 中位數 | 0.0 | 23.8 分 | 12.1 分 | 2.7 分 | 7.2 分 | 1.3 分 |
| 最短 | 0.0 | 19.0 | 8.2 | 1.2 | 4.1 | 1.0 |
| 最長 | 25.5 | 34.1 | 14.3 | 4.0 | 17.9 | 2.2 |

- 一半是建置。它和 `ios-build.yml` 一樣每次從頭建（兩邊都沒有建置的快取，也沒有互相傳建好的 App）。
- 能省的只有建置：把 PR 的 iOS run 建好的東西傳給截圖 run，或快取 DerivedData。前者要兩個 workflow 對同一個 commit 互等，後者 Xcode 在新 checkout 上多半整個重編（檔案時間都是新的）。兩個都不是「便宜的」，這一輪不做。
- 四次失敗（43354338527、43358097691 兩次、43376989911）都是建置與開模擬器成功之後、在拍照那一步失敗，三次有 App 當掉的記錄、一次是卡住；是測試或 App 的事，不是機器。
- 併發是每個分支一組，不同分支的截圖 run 會同時各佔一台 macOS。「一次一個」是 session 之間的約定，workflow 沒有強制。

## 7. 改前改後

見決策 719 的「驗證」：這個 PR 自己的 release archive run 與完整 tier。

## 8. 沒有做、留給之後的

- `HongKongMapTests` 184 s 超過 150 s 的線：這一輪只把它移到最輕的 campaign 並給權重，沒有讓它變快。110 s 是買下東涌綫後跑 51 小時那一個測試。
- `Stack frames over 32 KB (reminder)` 每個 run 13–20 分。
- GamePresentation tier 的 `selected-N` 快慢差 1.9–3.2 倍。
- PR 的 iOS gate UI 步驟 6.3–6.6 分。
- 截圖 run 與 iOS run 共用建置。

## 9. 門檻

沿用 11-11 §7，加一條：

- **release archive**：PR 的 run 超過 30 分，或夜間的 run 超過 40 分（上限 45），就再看 GamePresentation 那一步。
