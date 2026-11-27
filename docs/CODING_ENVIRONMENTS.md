# 程式單環境分級：哪一種單在哪裡寫、在哪裡驗

作者 2026-11-27 定下（「由簡單到困難的程序碼，所選擇的環境就不一樣」「有高價值程序碼才用高 token 的環境」）。
派程式單、開工時照這份選環境與模型。測試方法本身（命令列、模擬器、實機、Mac 上開）在
[`TESTING_SOP.md`](TESTING_SOP.md)；自架 runner 怎麼裝在 [`MAC_RUNNER.md`](MAC_RUNNER.md)。
這份只回答「這張單用哪一種環境、哪個模型，才不會把 token 花錯地方」。

## 1. 三種環境

| 環境 | 誰寫程式 | CI 在哪跑 | iOS 檢查多久（2026-11-26 量） | token 花在哪 |
| --- | --- | --- | --- | --- |
| **A. 雲端＋GitHub 機器** | 雲端 session（Linux，能跑 `swift test`） | GitHub 的 macOS 機器 | 約 34 分 | 寫程式、Linux 測試、看 CI 結果 |
| **B. 雲端＋自己的 Mac 跑 CI** | 雲端 session | 作者的 Mac（runner `chien-mac`） | 約 8.5 分 | 同 A |
| **C. 全本地** | 作者 Mac 上的 Claude Code（Remote Control 或直接開） | 本機 Xcode、iPhone 模擬器自己建置與截圖；推上去後 CI 照常跑 | 本機一次建置數分鐘 | 同 A，再加上 Xcode 輸出、截圖、操作模擬器的畫面 |

- **A 和 B 不用自己選**：PR 的 iOS 檢查由 `pick-mac.yml` 自動挑，Mac 開著又空閒就用 B，否則 A。兩者花的 token
  幾乎一樣（程式一樣寫、結果一樣讀），B 只是等得短，紅了重修時少等一輪。所以下面的表把 A／B 寫成同一格「雲端」。
- **C 最貴**：每張截圖都是一張圖進對話，Xcode 的輸出很長，操作模擬器每一步都要再拍一張；同一件事在 C 做，
  token 通常是雲端的數倍（估計，未逐張量過）。它的好處只有一個：**能親眼看畫面、快速改了再看**。
- 實機手感、fps、記憶體、iCloud 不是 Claude 的環境：作者的 iPhone 或 TestFlight（TESTING_SOP §2.3）。

## 2. 先看價值，再看難度

**token 只花在值得的單上。** 一張單要升到 C，必須同時是：

1. **高價值**：玩家會碰到的 bug、上架或發版前必修的、或優先清單加權分數 ≥ 3.0
   （權重照 NEXT_PRIORITIES §19；分數在私有 `docs/priorities/`）；**而且**
2. **雲端看不到答案**：要看畫面、動作或手感，而 CI 的 UI 測試、`website-screenshots.yml` 一次截圖答不了。

價值低的單（加權 < 3.0、不影響玩家、可以晚點做的整理）**就算麻煩也不升到 C**：留在雲端，
畫面靠一次截圖（ui-review §3「只試一次」）加作者發版後在手機上看；看起來不對就開下一張單，不在這張單上燒 token。

## 3. 分級表（由簡單到困難）

| 級 | 程式單類型 | 例子 | 預設環境 | 什麼時候升級 | 模型 |
| --- | --- | --- | --- | --- | --- |
| **1** | 只改文件、發版說明、資料表 | `docs/`、`WhatsNew`、地圖資料 JSON、時刻表資料 | 雲端（只跑 `WhatsNewTests` 等，決策 1017） | 不升級 | Opus 5.5 high |
| **2** | 模型、地標登錄接入 | 工作室交件的 GLB 轉 Swift、`registration`、雜湊鎖 | 雲端（UI 冒煙只跑工具列那支，決策 1019；審過的模型不拍截圖） | 不升級；模型外觀問題退回工作室，不在程式單上看 | Opus 5.5 high |
| **3** | 一般邏輯：GameCore 規則、數值、GamePresentation 的邏輯、一般 bug | 票價、需求、選單列什麼、卡片放哪 | 雲端（Linux `swift test --filter`，其餘交 CI） | 只在 bug 只出現在 iOS（Linux 重現不出）**且**高價值時，借 C 重現一次；修法回雲端寫 | Opus 5.5 high |
| **4** | 畫面、版面的小改 | 面板加一列、按鈕位置、文字長度、顏色 | 雲端＋一次截圖（`website-screenshots.yml`） | 高價值，且截圖看出要來回改兩次以上 → C | Opus 5.5 high |
| **5** | 要看動態、手感的：新畫面、動畫、觸控、3D 場景的鏡頭與光 | 新面板、轉場、拖曳建造、夜景 | 高價值 → **C**；價值低 → 雲端＋一次截圖 | 手感、幀數 → 作者實機（TestFlight） | Opus 5.5 high |
| **6** | Xcode 專案設定、Info.plist、Asset Catalog、權限、簽章與發版流程 | `project.yml`＋XcodeGen、entitlements、`release-archive.yml` | 雲端（Linux 上用 XcodeGen 產生、`release-archive.yml` 驗）；簽章與 TestFlight 只在 GitHub 或發版專用 runner | CI 的錯誤訊息看不懂、要在 Xcode 裡點開設定才知道 → C 看一次，改法仍寫進 `project.yml` | Opus 5.5 high |
| **非常難** | 跨級：查三輪還沒找到原因的 bug、死結、效能退步、存檔遷移、決定論、GameCore 大改 | 收班死結、tick 變慢、存檔讀不回 | 照它本來的級 | — | 開工標「非常難」才用 **Fable 5.2**（額度少，週額度只能用一半） |

- 模型規則和工作室一樣：**一律先 Opus 5.5 high**；只有開工時就標「非常難」的單才用 Fable 5.2，
  Opus 做到一半卡住的，先照 `.claude/skills/diagnosing-bugs` 做出會變紅的指令再判斷要不要換。
- 一張單跨兩級，照高的那級；但**升到 C 仍要先過第 2 節的價值門檻**。

## 4. Mac 太忙時退回（作者 2026-11-27：「本地真的太忙也要有退回半雲端、全雲端機制」）

Mac 同時是 C 的工作機、B 的 CI 機器和工作室的建模機。忙的時候一律往雲端退，不等 Mac。

### 4.1 C → 雲端寫程式（CI 仍可能用 Mac）

有下面任一條就不開 C，已經在 C 的退回雲端：

| 條件 | 怎麼看 |
| --- | --- |
| Mac 離線、Remote Control 2 分鐘內接不上 | `list_devices`、`start_remote_control` 的回覆 |
| 工作室正在跑建模（會吃滿 CPU 與 GPU） | Mac 的工作室任務清單有進行中的單 |
| 本機一次建置超過 15 分（平常幾分鐘） | 建置指令的時間 |
| Mac 剩下的磁碟不到 50 GB | `df -h ~`（清法見 TESTING_SOP §5） |

**怎麼退**：C 把手上的改動推到分支（推不了就把 patch 交回雲端的串），PR 說明寫清楚在 C 看過什麼、
還沒看的寫 UNVERIFIED；之後由雲端接著寫，畫面照第 2 節用一次 `website-screenshots.yml`（在 GitHub 的機器跑，不用 Mac）。
高價值又非看不可的，在交接寫「等 Mac 空了再看」，不讓整張單停著。

### 4.2 B → A（CI 改用 GitHub 的機器）

**自動的那一半已經做好**：每個 PR 的 iOS 檢查開跑前，`pick-mac.yml` 先問 Mac 的狀態，下面任一種都直接排到
GitHub 的機器（`xcode-27`），不等 Mac：Mac 離線、Mac 正在跑別的 job、Mac 的 Xcode 版本標籤對不上、
`MAC_RUNNER` 設成 `off`、讀不到 runner 狀態、從別的 repository 開來的 PR。這一步出任何錯都選 GitHub，所以只會跳過 Mac，不會卡在 Mac。
PR 的 iOS run 第一個 job「Pick the Mac or a hosted runner」的摘要寫著這次用哪台、為什麼。

**要手動退的另一半**：`pick-mac.yml` 只看得出「Mac 有沒有在跑別的 job」，看不出工作室或 C 正在吃 CPU。
所以 job 已經排給 Mac 之後：

| 條件 | 怎麼辦 |
| --- | --- |
| 排給 Mac 的 job 10 分鐘還沒開始（runner 中途被停掉，會一直等） | 取消這個 PR 的 run、重跑；Mac 離線時重跑就會改排 GitHub |
| 在 Mac 上跑超過 25 分（平常約 8.5 分；GitHub 約 34 分，再等也不會比較快） | 請作者把 Actions 變數 `MAC_RUNNER` 設成 `off`（或在 `cirunner` 帳號 `./svc.sh stop`），再取消、重跑這個 PR 的 run |
| 工作室要連跑幾小時 | 開工前就請作者設 `MAC_RUNNER=off`，跑完刪掉或改成別的值 |

- 只取消 PR 的 run，**`main` 的推送 run 一律不取消**（CLAUDE.md）。
- 變數與 runner 是作者的設定，session 只提醒、不自己改；`MAC_RUNNER` 怎麼設見 [`MAC_RUNNER.md`](MAC_RUNNER.md) §4。
- 退回 A 只是等得久，token 不會多花：照第 6 節等事件，不要因為慢就去輪詢。

## 5. 在 C 怎麼省 token

C 只用在要看的那一段，看完就回雲端：

- **只做要看的事**：寫程式、跑 Linux 測試仍在雲端；C 只負責建置、截圖、確認畫面。改法定了就推分支，交給 CI。
- **Xcode 的輸出不整段讀**：`xcodebuild … 2>&1 | tail -40`，或只撈 `error:`、`warning:`、`failed` 的行；
  測試結果用 `xcrun xcresulttool` 撈失敗的那幾個。
- **截圖少拍**：每個狀態改前改後各一張，同一台模擬器、同一個鏡頭（TESTING_SOP §2.2）；能用 UI 測試或無障礙元素回答的
  （「按鈕在不在」「文字對不對」），不用截圖。
- **不用滑鼠一步一步點模擬器**：用 UI 測試或啟動參數直接進到要看的畫面，再拍一張。
- C 在作者的 Mac 上跑時，同一台 Mac 的 runner（B）和工作室也在用：本機建置會讓 PR 的 iOS 檢查變慢；
  一次只開一個 C。

## 6. 雲端怎麼省 token

- 推一次完整的改動，不要一段一段推（每推一次就多一輪 CI、多讀一次結果）。
- 等 CI 不輪詢：訂閱 PR 的事件，結束這一回合，結果來了再醒。
- CI 紅了只讀失敗那個 job 的最後幾十行，修好只重跑失敗的（CLAUDE.md「Environments and validation」）。
- 截圖、full lane、`full-ci` 都不是預設：照 ui-review 的三級與 CLAUDE.md 的規則，用得到才開。
