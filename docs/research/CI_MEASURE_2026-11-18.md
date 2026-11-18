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

## 6. 合併之後（CIOPT-10 補，2026-11-18）

`ios-compilation-cache.yml` 在 11-17 被 push 觸發 4 次（#2385、#2394、#2402、#2408 合併），建置加存快取 14.0–23.0 分，四次都存到，「Keep only the newest compilation cache」也都刪掉了較舊的那份。

11-17 17:57 到 23:49 的 26 個 PR 的 iOS build job（日誌裡每個編譯後面的 `Cache hit`／`Cache miss`）：

| 讀的快取 | PR 數 | GameCore hit／miss | 「Build for iOS Simulator」 |
| --- | ---: | ---: | ---: |
| 137 full lane（44085389506），main 已有新的 GameCore | 4 | 0／6 | 9.9–13.7 分（中位 12.2） |
| 新存的 main 快取（44148577366 之後） | 20 | 6／0 | 9.9–14.9 分（中位 12.8） |
| 新的，但 PR 自己改 GameCore（DEBUG-137） | 1 | 0／6 | 16.4 分 |
| 舊的：#2408 22:16 合進 main，快取 22:39 才存好，ROAD-UNDER-VIADUCT 22:22 併了 main | 1 | 0／6 | 16.9 分 |

- 命中時 GameCore 那段從約 1.6–2.5 分變成幾秒（日誌時間線：GamePresentation 的 emit-module 要等 GameCore），所以每個受影響的 PR 約省 2 分，不是 §3 推估的 4 分；SANTA-FLIGHT 的 17.5 分多半是同時和 GameCore 搶核心。
- 但同樣全命中的 PR，GamePresentation 那段就在 5.7–9.3 分之間跳（runner 快慢），比省下的 2 分大，所以表上兩組的中位數分不出來。
- 代價：11-17 四次共約 72 分 macOS；省下的約 18 個 PR × 2 分 ≈ 36 分。PR 的等待短了，macOS 的總用量反而多。20:26 那次（#2394）和 4 個 PR 的 iOS job 同時跑，佔滿 5 台，下一個 PR 排隊 11.8 分（它的 `ci.yml` 因此 40.5 分，那天最長）。
- 這次不改：一天 2–4 次、PR 每次少等 2 分，和偶爾的排隊相抵，算不出明顯的好壞。若之後 macOS 排隊超過 20 分的線（HANDOFF §1.1）常出現，先停它的 push 觸發。其他 138 發版後的數字在 §7。

## 7. 138 發版後（CIOPT-10，2026-11-18）

138 發版（`0067d9f`）後的例行 CI 優化（新專案協調者派工，工作串「做 138 版發版後 CI 優化」，分支 `claude/project-thread-2u3fly`）。量的是 11-17 17:50 到 11-18 00:30 已經跑完的 run，沒有為量測多開。

### 7.1 對 HANDOFF §1.1 的線

| 線 | 量到的 | 過線？ |
| --- | --- | --- |
| 完整 `ci.yml` 比上一輪慢 20% | 夜間 44203604168（`9b5cedf`）23.4 分；上一輪中位 22.9 | 沒有 |
| PR tier 超過 30 分 | 25 個成功的 PR run：中位 27.2 分，4 個 30.6–40.5 | 4 個過，見 7.2 |
| 最長的 shard 超過中位數 1.5 倍 | 完整 tier 的 rest-1／rest-2 是 campaign 中位的 1.5–2.7 倍（GameCore PR 44182350239 的 rest-1 16.4 分，其他 5.4–9.6） | **過**，見 7.3 |
| PR 的 iOS gate UI 測試超過 6 分 | 27 個 PR：UI 步驟 4.6–7.9 分，中位 6.1；四支測試本身平均 3.4 分，其餘約 2.7 分是 XCTest 第一次啟動與寫結果 | 貼著線（中位剛過），見 7.2 |
| macOS 排隊超過 20 分 | 最長 12.5 分（一次，5 台全滿） | 沒有 |
| full lane 離上限不到 10 分 | 137 那次 build job 88 分（上限 145） | 沒有 |

### 7.2 PR 最長的那條路

25 個 PR 的 `ci.yml`，Swift 部分（建置加 selected shards）15.0–19.3 分就跑完，gate 再等 iOS 的 build job：gate 結束的時間和 iOS build job 結束只差不到 1 分，22 個都是這樣。iOS build job 的步驟（中位）：建置 12.5 分、開模擬器 2.3 分、暖機 1.5 分、gate 的四支 UI 測試 4.9 分、其他約 2 分。

過 30 分的四個：ROAD-UNDER-VIADUCT 30.6（GameCore 舊快取，§6）、FREIGHT-LOOK（貨運看得見）30.7（runner 慢）、DEBUG-137 31.7（自己改 GameCore：Linux 建置 13.9 分加 rest 等完整 tier）、MAP-PACK-ONCE（REVIEW-L27 第 1 張）40.5（macOS 排隊 12.5 分）。

試過、不改的：

- **GamePresentation 的編譯分批**（677 個檔，swift-driver 預設每批 25 個 → 28 批，每批都要讀整個模組）。Swift 6.4 的 `swift build` 在雲端 Linux 4 核上、GamePresentation 照 iOS 用 `-O`、只建這個模組：預設 307–308 s，`-driver-batch-count 8` 320 s，`-driver-batch-count 4` 340 s。分批不是瓶頸，花時間的是 -O 本身。
- **開模擬器和建置重疊**：#211 試過，3 核心上建置變慢更多（決策 199 一帶的註解）。
- **PR 的建置改 -Onone**：決策 624 的「不選的」，CI 與作者會跑不同的程式。
- **gate 的 UI 測試**：四支本身 3.4 分；第一支（`testBackToStartWorksWithLargeTextWhileTheClockRuns`，平均 87 s，最少 47 s）多付 XCTest 第一次啟動的約 40 s，換哪一支排第一都一樣。PR 不跑 XCTest 暖機是決策 667 為了守 6 分選的。四支都還在守真的 bug（TestFlight 54.1 的選單、教學卡片擋觸控、開線步驟的面板），不拿掉。

### 7.3 完整 tier 的 shard（做了）

五個完整 tier（夜間 43992341049、44203604168，手動 43998595808、44085363286，GameCore PR 44182350239），每片的測試秒數：

| | campaigns（13 片）| rest-1 | rest-2 |
| --- | --- | ---: | ---: |
| 範圍 | 217–482 s，各片中位 223–322 | 472–782 | 439–528 |

rest 收的是沒有 campaign 點名的類別，11-15 以後新加的類別都進了 rest，`HongKongDepotTests`（110 s）沒有權重（當 1）、`Map3DRoadTunnelTests` 權重 7 實際 68 s。

做法（`swift-shards.sh`）：rest 最重的 10 個類別（五個 run 裡最慢的時間）搬到 6 片還有空的 campaign；16 個 13 s 以上沒有權重的類別、11 個權重差兩倍以上的類別改成最慢的那次。完整 tier 仍是 19 個 job。用這五個 run 的類別時間重算新的分法：

| run | 以前最長的一片 | 以後最長的一片 | rest-1／rest-2 以後 |
| --- | ---: | ---: | ---: |
| 44203604168（夜間） | rest-1 598 s | campaigns-11 454 s | 337／364 |
| 44182350239（GameCore PR） | rest-1 782 s | campaigns-6 421 s | 355／397 |
| 44085363286（137 手動） | rest-1 518 s | campaigns-5 388 s | 325／334 |

完整 tier 最長的一片少 2.4–6 分；DEBUG-137 那種改 GameCore 的 PR，Swift 部分（31 分，那次比 iOS 還長）約 25 分。

### 7.4 測試本身（TEST-JUMP 第 1 步：時間花在哪）

夜間 44203604168 的 7,455 支測試共 5,186 s。最貴的類別：`HongKongSharedTrackBuyOrderTests` 156 s（三條共線的線六種買法，每種從頭開一局香港）、`Map3DModelPackLockTests` 147 s、`Map3DSceneMemoryTests` 141 s、`HongKongTungChungDayTests` 102 s、`HighSpeedDemoTests` 99 s、`Map3DStationExteriorsTests` 98 s、`Map3DFarViewTests` 98 s。

- **`Map3DModelPackLockTests`（做了）**：鎖檔用的 FNV-1a 雜湊每個頂點建一個 10 個字的陣列、每個字再走一次 `stride`；測試在 Linux 是 -Onone，這兩樣就佔了大半。改成不建陣列、四個位元組直接算（同樣的字、同樣的順序，雜湊逐位元相同，鎖檔的測試照樣過）：本機 `testEveryModelIsAsLocked` 62 → 27 s、`testTheOrderAndTheLampsAreAsBefore` 44 → 1.6 s。另外 6 個類別（EMU700／800／900、C341 整合、阿里山、客車塗裝）各有一份一模一樣的抄本，改成叫這一份：C341 整合 49.6 → 23.7 s、EMU900 整合 27.9 → 4.9 s、EMU700 整合 12.7 → 4.0 s（本機；第一個建模型包的類別多付約 16 s）。合計每個完整 tier 約省 100–130 s 的測試時間，落在 campaigns-4、-8、-11 與 rest。
- **UI 測試從頭點到某個狀態**：full lane 的 `LessonUITests` 有三支（Again、Next、Keep Playing）各自從第一課的「開線」步驟一路鋪軌、蓋站、開線、跑到過關（各 215–221 s），只為了按結果卡上不同的鈕；要直接跳到結果卡得在 App 加 Debug 啟動參數，只能在 macOS 驗。full lane 的最長路徑是 build job（88 分），lessons job（59 分）不在上面，所以省下的約 6 分不會讓 full lane 早結束。寫成評分 LESSON-RESULT-JUMP，沒做。
- **GameCore 的長 campaign 從存好的中途狀態開始**：`handoff/SUN-TIMES.md` 的 TEST-JUMP (3)。property、mutation campaign 的時間花在每個案例自己的模擬，不是開局；中途存檔一改規則就要重錄，和 `ReplayFixtures` 同樣的風險。不做。

### 7.5 盤點：過時、重複、該拿掉的測試

作者 11-18 要的（「有哪些 ci 測試已經過時需移除或更新測試內容的」）。逐類看：

| 類 | 找到的 | 處理 |
| --- | --- | --- |
| 測已刪掉的功能 | 沒有。刪掉的型別或函式，測試會編不過；名字有 legacy 的（舊存檔的地圖格、舊票價公式、舊的單線計畫）都是在守舊存檔讀得回來或舊規則不變，要留。 | 不動 |
| 長期跳過 | 夜間 230 支 skipped，全部是只在設環境變數時跑的報告或除錯工具（`*_REPORT`、`KLRT_TRACE`、`TYMC_DIAG`、`REPLAY_RECORD` 等），CI 上一支 0.1 s 以內。除錯工具（高雄輕軌死結追蹤、文湖線機廠傾印、機場捷運死結形成）修好的 bug 會再用到（diagnosing-bugs skill 的做法）。 | 不動（省不到時間） |
| 重複的程式 | 模型雜湊有 7 份一樣的抄本，而且是全套件最慢的寫法。 | 留一份、改快（7.4），約省 100–130 s |
| 重複的工作 | `LessonUITests` 三支各跑一次第一課（約 650 s macOS）；`HongKongSharedTrackBuyOrderTests` 六種買法各開一局香港（買法不同，不算重複）。 | 前者寫評分，後者不動 |
| 數值鎖過時 | 鎖檔（`hashes.lock.json`、`locks/*.json`）、golden、存檔、重播在 CI 都是綠的，沒有被跳過或放寬的；過時的是 `swift-shards.sh` 的 27 個類別權重。 | 權重照實測更新（7.3） |
| 不穩（flaky） | full lane 11-14 到 11-17 紅的四晚都已修（§4）；137 與 138 的 full lane 綠（138：44207122637，build job 與 iPad 在本文寫時仍在跑）。UI 測試裡寫著「沒按到再按一次」的註解有 47 處，每一處都寫了是哪一次 run 查到的原因（被取消的觸控、慢 runner 漏掉的點按）。 | 不動 |
| 不是測試、但每個 PR 都跑的 | `Stack frames over 32 KB (reminder)` 每個改 Swift 的 PR 佔一台 Linux 13–20 分，gate 不等、紅了也不擋。 | 不動（不在最長路徑上） |

**能省多少**：PR 最長的路是 iOS build job，這次沒動，所以一般 PR 等的時間不變（約 27 分）。改到 GameCore 的 PR 與夜間、手動的完整 tier，Swift 部分少 2.4–6 分（7.3），每個完整 tier 少約 100–130 s 的 Linux 測試時間（7.4）。

### 7.6 合併後要看的

1. 下一次完整 `ci.yml`（夜間或手動）每片的測試秒數：最長一片要在 8 分以內，rest-1、rest-2 不再是最長的兩片。
2. `Map3DModelPackLockTests` 在 campaigns-4 的時間（夜間 147 s → 預估 35–45 s）。
