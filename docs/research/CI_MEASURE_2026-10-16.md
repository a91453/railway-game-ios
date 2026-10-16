# CI 量測與優化（2026-10-16）

> 作者 2026-10-16：「不用凍結了 但也先不要開工我要做pr review 跟ci優化」。遊戲規劃 session_01V1xd3H9vNkuZoSA3czNfGm 派工給 CI 優化 session（session_01LQE9Rif1ggbZsT3iYQiN7G）。這份是量到的數字、提出的方案，以及每個方案由哪個 PR 做或交給誰決定。規則以決策 265 為準。

## 1. 量了什麼

- **範圍**：GitHub Actions API，2026-10-13 16:00Z 到 10-16 19:00Z 建立的 2,305 個 run。
- **排除**：`Claude Code` 的 846 個 run。它們幾乎都是沒有提及 `@claude` 的留言，job 被跳過，不佔 runner。
- **實際分析**：剩下 1,459 個 run 的每個 job 與 step。
- **算法**：
  - job 的時間 = `completed_at − started_at`；
  - 排隊時間 = `started_at − created_at`；
  - 「手動」指 run 名稱以 `UI tests by hand:` 開頭的 `ios-build.yml`（`only_testing`）；
  - 「full lane」指其他不是 PR 觸發的 `ios-build.yml`。

## 2. 量到的

### 2.1 runner 的用量（10-14 00:00Z 起，約 67 小時）

| 種類 | run | macOS 分鐘 | Linux 分鐘 | 失敗的 run |
| --- | ---: | ---: | ---: | ---: |
| iOS PR（gate） | 276 | 4,041 | 86 | 15 |
| iOS full lane | 42 | 3,119 | 11 | 17 |
| iOS 手動（`only_testing`） | 94 | 1,603 | 24 | 38 |
| Release archive | 17 | 140 | 0 | 0 |
| TestFlight 與它的檢查 | 12 | 121 | 42 | 0 |
| 網站截圖 | 3 | 42 | 0 | 1 |
| `ci.yml` push | 197 | 0 | 21,143 | 0 |
| `ci.yml` PR | 363 | 0 | 18,349 | 5 |
| wasm probe | 84 | 0 | 531 | 0 |
| 合計 | | **9,067** | **40,202** | |

- **macOS**：平均同時約 2.3 台在跑（上限 5 台）。三大用量是 PR 的 gate（45%）、full lane（34%）、手動（18%）。
- **Linux**：平均約 10 個 job（上限 40）。

### 2.2 排隊

| | n | 中位數 | p90 | 最久 |
| --- | ---: | ---: | ---: | ---: |
| Linux job（`ci.yml`） | 4,997 | 0.0 分 | 0.1 分 | 8.4 分 |
| macOS job（`ios-build.yml`） | 520 | 0.1 分 | 7.7 分 | 32.8 分 |
| macOS job（`release-archive.yml`） | 26 | 0.1 分 | 4.9 分 | 19.5 分 |

- Linux 不用等。決策 187 時常排到 40 個的情況，這三天沒有再出現。
- macOS 偶爾會等很久：full lane 一次佔 3 台，再加上 PR 和手動的 run，就會排隊。

### 2.3 每個 job 的時間（分鐘，成功的）

| job | n | 中位數 | p90 | 最長 |
| --- | ---: | ---: | ---: | ---: |
| Swift 分片（push，最慢的 `rest`） | 115 | 15.1 | 17.5 | 19.9 |
| Swift 分片（push，`campaigns-6`／`-12`） | 115 | 14.6／13.6 | 16.8／16.8 | 18.1／18.2 |
| Swift 分片（push，最快的 `campaigns-16`） | 58 | 9.9 | 15.3 | 16.9 |
| PR 的 `selected-1..3`（GamePresentation 那一層） | 177 | 9.2–10.1 | 11.6–15.6 | 17.9 |
| iOS PR：Xcode build（含 UI 測試） | 282 | 17.4 | 20.1 | 56.2 |
| iOS PR：iPad 教學 | 30 | 15.4 | 18.8 | 27.3 |
| full lane：第一個 iPhone job | 10 | 36–44 | | |
| full lane：第二個 iPhone job | 10 | 25–38 | | |
| full lane：iPad 教學 | 10 | 14–20 | | |
| Release archive | 26 | 8.3 | 11.2 | 18.5 |

**iOS PR 的 Xcode build job**（195 次，步驟中位數）：
- UI 測試 7.4 分
- 翻譯匯出 2.2 分
- 建置 2.1 分
- 開機 2.0 分
- 暖機 1.8 分

**Swift 分片逾時**：三天內有 8 次碰到 20 分鐘上限而被取消。其中 2 次卡在建置步驟，6 次卡在測試；`main` 的 push run 有 2 次（38615317464、38746386552）。

### 2.4 full lane 的牆鐘時間（#693 拆成兩個 iPhone job 之後，10 次）

| run | commit | 第一個 iPhone job（UI 步驟） | 第二個（UI 步驟） | iPad | 牆鐘 |
| --- | --- | --- | --- | --- | --- |
| 38829246728 | e41f923 | 37.1（23.8） | 31.7（23.9） | 14.1 | 38 |
| 38849566648 | 742f92a | 34.8（23.2） | 30.8（23.8） | 18.1 | 42（含排隊 11） |
| 38861445072 | 84a792e | 36.1（22.7）紅 | 31.8（24.9）紅 | 16.2 | 37 |
| 38878787559 | 878adaf | 41.2（28.9）紅 | 38.0（29.6）紅 | 17.2 | 44 |
| 38894898231 | 2912cd8 | 43.6（31.4） | 30.3（24.4） | 18.6 | 44 |
| 38902675580 | 72fc1bd | 35.3（26.7） | 25.0（20.2） | 19.9 | 36 |
| 38918828801 | f70786b | 40.7（28.1）紅 | 38.5（30.1） | 19.4 | 43 |
| 38933058668 | 45fcde4 | 44.2（29.2） | 35.7（28.1）紅 | 20.4 | 45 |

**第一個 job 比第二個慢 5–13 分**：
- 它多做了專案檢查與翻譯匯出（約 3 分）；
- 開機比 PR 慢（中位數 4.5 分，PR 是 2.0）；
- 它的 UI 測試比較多。三次的 class 合計：
  - 第一個 job：
    - `StartSaveFlowSmokeTests` 487–554 秒
    - `SettingsUITests` 279–349 秒
    - `LineRoutePreferenceUITests` 237–262 秒
    - `TutorialUITests` 216–231 秒
    - `ShellLayoutUITests` 144–248 秒
    - `TutorialJourneyUITests` 107–124 秒
    - `ToolbarSmokeTests` 約 40 秒
  - 第二個 job：
    - `MapInteractionTests` 597–809 秒
    - `RealWorldMapUITests` 486–692 秒

**full lane 跑得很頻繁**：67 小時跑了 42 次，平均 1.6 小時一次，45 個 commit 各一次。
- 由 `ios-full-lane.yml`（合併後最多每三小時一次）啟動的只有 7 次。
- 其他都是用作者帳號手動在 `ios-build.yml` 按的。主要是合併協調照 HANDOFF §1.2「合了會影響 App 的 PR 後」跑的，另外有發版前的確認。
- 這 44 對相鄰的 full lane 之間，每一對的 App 內容都不同（照 `ios-build.yml` 的 `paths-ignore` 比對）。所以「App 內容相同就沿用」這個做法，在這三天一次都省不到。

### 2.5 今晚提到的四個問題

1. **自動合併搶在 iOS 跑完之前**（確認）：
   - #746 開著自動合併。`Swift CI (gate)` 17:56:27 綠，17:56:33 就合併了；它的 iOS run（38940806603）18:02 才紅：`RealWorldMapUITests` 失敗，這個錯到 #748 才發現。
   - #753 開了 3 分鐘就合併（18:30 開、18:33 合），iOS run 18:43 才跑完。
   - 原因：`main` 的 branch rule 只要求 `Swift CI (gate)`。只要 gate 綠了，自動合併或手動合併都不會等 iOS。
2. **full lane 42–45 分鐘、佔 3 台**（確認，見 2.4）。另一個主要成本是頻率：67 小時 42 次，約 3,100 macOS 分鐘。
3. **字串匯出在 run 38929483452 超過 15 分鐘**（確認，但是個案）：
   - 這是手動的 `only_testing` run，只跑 `SettingsUITests LineRoutePreferenceUITests`。
   - 匯出要另外用 device SDK 從頭編譯 GameCore、GamePresentation 和 App，在這台 runner 上從 16:31 編到 16:46 被停。同一台的 UI 測試也比平常慢約 1.7 倍。
   - 362 次匯出中位數 2.4 分，p95 4.3 分，p99 5.3 分，逾時只有這一次。
   - 手動 run 每次都做匯出：94 次合計 283 分鐘，和這些 run 的 UI 測試本身（301 分鐘）差不多。
4. **開成 ready 時同一個 commit 的 Xcode build 跑兩輪**（沒有重現）：
   - `ios-build.yml` 的 `pull_request` 用預設的 types（opened、synchronize、reopened），不含 `ready_for_review`，所以按 ready 不會再觸發。
   - 三天內同一個 commit 有兩次 Xcode build 的 PR run，共 10 個 commit：9 個是按了重跑（attempt 2），1 個（77b9f80）是同一分鐘建了兩個 run。
   - #753 看到的「兩輪」是：開 PR 前 18 秒，有人在同一個 commit 手動跑了 `only_testing` run（38947778366），接著 PR 自己的 run 才開始。
   - 94 個手動 run 裡有 84 個，跑的 commit 同時也有 PR 的 run（1,481 macOS 分鐘）。大多是 session 在修不穩的測試，有理由這樣跑。不過 CLAUDE.md 的規則是：PR 的 run 已經在測的 commit，不要再手動跑。

## 3. 方案與決定

每個方案都附玩家、開發、美術、音樂四方各一行。作者 2026-10-14 起由 session 自己決定；作者保留的事項另外列出。

### A. PR 的 `Swift CI (gate)` 等同一個 commit 的 iOS App Build（#756，決策 265 第 1 點，已合併）

- **做法**：gate 在 Swift 判定之後加一步 `swift-shards.sh ios-gate`。
  - 找同一個 head commit 最新的 `ios-build.yml` PR run，等它跑完；成功或跳過才綠。
  - 沒有 iOS run（`paths-ignore` 的改動）就直接綠。
  - job 名稱不變，所以 branch rule 不用改，自動合併也會等。
- **四方**：
  - 玩家：TestFlight 不會再拿到 UI 測試已經紅掉的 build，主線上也不會整晚掛著紅燈，等下一個 PR 才修。
  - 開發：一個必要檢查就涵蓋 Swift、Xcode build 與 UI gate。代價是 App 的 PR 等 iOS 時，gate 多佔一台 Linux 約 20 分鐘；Linux 平均只用約 10 台（上限 40）。
  - 美術：無。
  - 音樂：無。
- **其他選項**（留給作者）：
  - **把 iOS 的 job 也設成必要檢查**：要作者改 branch rule。而且 `ios-build.yml` 對 `paths-ignore` 的 PR 根本不會啟動，必要檢查會永遠停在等待；要先拆成一個一定會回報的 job，所以這次不做。
  - **在 repo 設定關掉「Allow auto-merge」**：要作者改設定，而且擋不住手動提早合併。
  - **只靠規則（決策 187 已經寫了「合併前確認 iOS 綠」）**：今晚證明規則擋不住。
- **代價**：iOS 失敗、重跑通過之後，要再對 CI 的那一輪按 Re-run failed jobs，gate 才會重新判。gate 的訊息會這樣寫。

### B. 手動 run 不做翻譯匯出；full lane 的第二個 job 多跑 `SettingsUITests`（第二個 PR，決策 265 的之後的修正）

- **做法**：
  - `only_testing` 的 run 跳過翻譯檢查的三步。這類 run 是為了修某一支 UI 測試，翻譯在 PR 和 full lane 都還會檢查。每次約省 3 分。
  - `FULL_LANE_SECOND_JOB` 加上 `SettingsUITests`（279–349 秒）。估計第一個 iPhone job 從 35–44 分降到 31–39，第二個從 25–38 升到 30–43，兩個 job 差不多同時結束。
- **四方**：
  - 玩家：無。
  - 開發：手動 run 快約 3 分，也不會再因為和測試無關的匯出逾時而紅；full lane 的牆鐘少約 4 分。
  - 美術：無。
  - 音樂：無。

### C. full lane 不在每批合併後手動跑（HANDOFF §1.2，隨 #756 合併）

- **做法**：
  - 合併後由 `ios-full-lane.yml` 自己啟動（最多每三小時一次，main 的 push 會觸發，另有排程補位）；
  - 合併協調只在兩種情況手動跑：發版前要用的那個 HEAD，以及 full lane 紅了要二分的 commit。
- **估計**：67 小時 42 次 → 約 22 次，少約 1,600 macOS 分鐘（全部 macOS 用量的 18%）。PR 的 macOS 排隊也跟著變短。
- **四方**：
  - 玩家：發版前一定要在 HEAD 跑過一輪，所以玩家拿到的 build 涵蓋範圍不變。
  - 開發：壞掉要最多約三小時才知道，二分的範圍也比較大；但 PR 的 gate 有 UI 測試，加上 A 之後 gate 紅了就不能合，所以只有 full lane 才有的測試會晚一點發現。
  - 美術：無。
  - 音樂：無。

### D. 沒有做的

- **App 內容相同就沿用上一輪 full lane**：這三天一次都省不到（2.4），不值得加程式。
- **Swift 分片的逾時上限 20 → 25 分**：三天 8 次逾時，有 2 次是建置就卡住的慢 runner。分片中位數 10–15 分、p90 最高 17.7 分。目前先不改；`rest` 的最長已經到 19.9 分，下次重新分配分片時一起看。
- **iPhone UI 測試拆成第三個 job**：full lane 會變成同時佔 4 台 macOS（上限 5），PR 會排更久。
- **自架、付費或第三方 macOS runner**（HANDOFF §3：CI 4C 現在不做）、**改 branch rule**、**加依賴**：都是作者的事。

## 4. 要作者決定的

- **要不要直接把 iOS 也列為 `main` 的必要檢查**，取代 A 的「gate 等 iOS」：要改 GitHub 設定，`ios-build.yml` 也要改成一定會回報。
- **要不要在 repo 設定關掉 auto-merge**：A 做了之後不是必要的，但開著的自動合併還是會在 gate 綠的那一刻合併，不會等合併協調的批次。
