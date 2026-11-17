# CI 量測（2026-11-18，CIOPT-9）

> 137 發版後的例行 CI 優化（新專案協調者派工，工作串「做 137 版發版後 CI 優化」，分支 `claude/project-thread-fb69a9`）。上一輪是 [11-13 的量測](CI_MEASURE_2026-11-13.md)（CIOPT-8，決策 719）；門檻照 `docs/HANDOFF.md` §1.1「CI 優化」：完整 `ci.yml` 比上一輪慢 20% 以上，或 PR tier 超過 30 分。改了什麼寫在 [決策 775 的後來](../decisions/775.md)。

## 1. 量法

- GitHub Actions API：每個 job、每個步驟的開始與結束；日誌裡 Xcode 每個編譯後面的 `Cache hit`／`Cache miss`。
- 沒有為量測多開 run；全部是 11-14 到 11-17 已經跑過的 run。時間都是 UTC。

## 2. 完整的 `ci.yml`（沒過線）

| run | 種類 | commit | 牆鐘 |
| --- | --- | --- | ---: |
| 43783061880 | 手動 11-16 | 36b5cb5 | 22.9 分 |
| 43936531115 | 手動 11-16 | 89ed04b | 22.1 分 |
| 43992341049 | 夜間 11-17 | 045cd9a | 20.8 分 |
| 43998595808 | 手動 11-17（136） | 19f3cc5 | 24.7 分 |
| 44085363286 | 手動 11-17（137） | 85507e2 | 25.5 分 |

中位數 22.9 分，上一輪 25.1 分，沒有變慢。137 那次：建置從零 11.7 分；rest-1 測試步驟 9.6 分（job 11.9 分）、rest-2 8.5 分、13 片 campaigns 4.4–7.0 分。最長的一段仍是從零建置，和 CIOPT-8 相同。

PR 的 Swift tier：完整 tier 21.9 分（DEPOT-REAL 44119326464）、26.1 分（ROVANIEMI 44117353238）；GamePresentation tier（SANTA-FLIGHT 44124277593）建置 7.6 分、八片 7.6–13.0 分，Swift 部分 24.5 分。都沒過 30 分。

## 3. PR 的 iOS run（PR 最長的一段）

SANTA-FLIGHT 的 `ci.yml` 36 分，其中最後 11 分是 gate 在等 iOS。iOS 的 build job（含 gate 的 UI 測試）：

| run | PR | 建置 | GameCore hit／miss | GamePresentation hit／miss | job |
| --- | --- | ---: | ---: | ---: | ---: |
| 44110776023 | TPE-MRT-ELEVATED 第 4 輪 | 9.1 分 | 7／0 | 0／28 | 18.7 分 |
| 44094491703 | ROAD-LOOK-REAL | 13.5 分 | 8／0 | 0／28 | 28.0 分 |
| 44094812453 | DEPOT-REAL | 13.4 分 | 8／0 | 0／28 | 28.4 分 |
| 44109296141 | ROVANIEMI-FARE（自己改 GameCore） | 13.5 分 | — | — | 25.3 分 |
| 44124277580 | SANTA-FLIGHT | **17.5 分** | **2／7** | 0／28 | 33.4 分 |

- 五個都讀 137 full lane（run 44085389506）存的快取 `xcode-cas-v1-d509f7e4757a27f5-44085389506-1`。
- SANTA-FLIGHT 只改 GamePresentation 與 App，但它跑的時候 main 已經合了 #2375（GameCore，16:15），快取裡沒有新的 GameCore：GameCore 先重編 2.4 分，GamePresentation 才開始，又和它搶 3 個核心（GamePresentation 11.8 分，其他 PR 10.0 分）。多出約 4 分。
- GamePresentation 是整模組 -O（決策 624），改到任何一個檔，28 個編譯全部 miss；App（RailwayGame）依賴它，也跟著 miss（約 2 分）。這是快取的上限，不是設定錯。
- 其他步驟：選模擬器 5 s（冷的 CoreSimulator 62–89 s）、開模擬器 1.4–2.9 分、暖機 1.7–3.1 分、gate 的 UI 測試 4.8–7.4 分。開機和建置重疊以前試過（#211），3 核心上整體更慢，不再試。
- main 合進 GameCore 的次數：11-15 兩次、11-16 兩次、11-17 四次；快取一天只在 nightly 存一次。→ 決策 775 後來：main 改到 GameCore 時也存。

## 4. Full lane

| run | commit | 結果 | 時間 |
| --- | --- | --- | ---: |
| 43647550011 | a9ee7e0 | 綠 | 86 分 |
| 43687762390 | 0798416 | 紅 | 114 分 |
| 43771142652 | 14bf9e6 | 紅（missing-button 證明逾時） | 108 分 |
| 43783072819 | 36b5cb5 | 紅（LessonUITests 一支） | 67 分 |
| 43936559208 | 89ed04b | 紅（三組各有） | 95 分 |
| 43998599964 | 19f3cc5 | 紅（橫拿教學第 8 步） | 98 分 |
| 44085389506 | 85507e2（137） | 綠 | 89 分 |

六晚紅了四晚，每一支都已經有人查過、修了：REVIEW-L24（missing-button 腳本補快取設定、LessonUITests）、FULLLANE-135（動態島上的拖曳）、FULLLANE-135-2（建造膠囊與速度選單）、FULLLANE-136（被取消的觸控）。137 的 full lane 綠。這次沒有新的不穩測試要修。

## 5. 結論

- 完整 `ci.yml`、PR 的 Swift tier、full lane 都沒過線。
- PR 最長的是 iOS run（19–34 分）；能省、又不用動程式的是 main 快取太舊：改成 main 合到 GameCore 也存一次（決策 775 後來）。

## 6. 合併之後

（合併後第一次 `ios-compilation-cache.yml` 的 run、以及之後幾個 PR 的 iOS 建置時間寫在這裡。）
