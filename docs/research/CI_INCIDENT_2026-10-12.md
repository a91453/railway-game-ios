# 2026-10-12 CI 事故檢討與改善計畫

> **狀態（2026-10-12 整理）**：歷史紀錄。4A 已由決策 187 實作；4B、4C 等作者決定，列在 [NEXT_PRIORITIES_2026-10-12.md](NEXT_PRIORITIES_2026-10-12.md)。

> 讀者：專案作者
> 資料範圍：台灣時間 10/12 00:00 到 19:20（UTC 10/11 16:00 到 10/12 11:20），共 416 個 workflow run、2,801 個 job，全部從 GitHub API 抓取。
> 時間以台灣時間為主，括號裡是 UTC。資料推不出來、或沒有實際驗證的地方標「未確認」。
> 文中的數字是實際抓到的資料（VERIFIED）。第 4 節的改善項目都還沒實作，也沒有在 CI 上驗證（UNVERIFIED）。

## 結論

1. **今天會卡，是我們自己把帳號「同時最多 40 個 job」的上限塞滿了，GitHub 沒有出事。**
   - 最嚴重是台灣 08:29–11:37：同時執行的 job 數一直停在 40。
   - Linux 排隊最多 122 個 job，最久等了 82.7 分鐘。
   - 一次完整 CI 從頭到尾最長花了 120 分鐘，半夜只要 16 分鐘。
   - 塞滿 40 格的是 Linux 的 Swift CI shard（一次完整 run 有 18 個 job），不是 macOS。
2. **「連環紅」：有 14 個 merge commit 帶紅 X，原因分三種。**
   - **真的壞了，已修**：當時還沒有必要檢查，#387、#389、#388 沒等自己的 CI 跑完就合併了。由 #389、#393 修好。
   - **假紅，機制還沒修**：有人手動取消 main 的 CI run，gate 把「被取消」當成失敗。這些 run 裡沒有任何測試失敗。
   - **只有 main 的 full lane 抓到，已修**：#391 讓遊戲選單太長、#402 弄壞設定頁的測試。由 #423、#427 修好。
3. **現在 main（3f97f18）全綠。** Linux 全套測試從 83b8bc8 起一路綠，iOS full lane 29/29 通過。紅 X 後面沒有藏著還沒修的程式 bug。
4. **還沒處理的四件事：**
   - 手動取消就會塗紅 gate 的機制。
   - `rest` shard 已經跑到 18.9 分鐘（上限 20 分鐘），快要逾時。
   - PR 上有幾個看起來不穩（flaky）的 UI 測試。
   - 台灣 08:43 上傳到 TestFlight 的那一版，是從壞掉的 commit b0722e7 打包的。
5. **GitHub Pro 有幫忙，但不夠。** 總上限從 20 提高到 40；macOS 上限仍是 5。Linux 一樣能把 40 格全部佔滿。
6. **兩個已合併的修正已經見效：**
   - #400：main push 改成共用一個排隊群組。
   - #422：PR 只跑它需要的那一級測試。
   - 之後 Linux 排隊時間的 p90 從 24.6 分鐘降到 0.1 分鐘。下午負載本來就比較輕，所以不全是修正的功勞。
7. **接下來最划算的四件事：**
   - 流程規則：不手動取消 main 的 run，也不要一次把 main 合進所有 PR。
   - iOS 加上「同一份改動已經通過就不重跑」。
   - main push 也分級，另外每晚跑一次全量。
   - 重新分配 `rest` shard。

## 1. 今天 CI 為什麼卡

### 1.1 時間線

| 台灣時間（UTC） | 發生什麼事 |
|---|---|
| 00:00–07:30（16:00–23:30Z） | 平靜，所有等待都不到 1 分鐘。19:56Z 同時跑了 27 個 job，超過 Free 的 20 個，所以 Pro 最晚在台灣 03:56 已經生效。更早什麼時候生效，資料看不出來。 |
| 07:51–08:01（23:51–00:01Z） | 第一次塞滿。21 個 Linux job 排隊，最久等 5.5 分鐘。 |
| 08:29（00:29Z） | 同時執行數開始停在 39–40，一直到 11:37。這 189 分鐘裡大約有 182 分鐘是滿的。 |
| 08:33–09:42（00:33–01:42Z） | 那時每個 main push 還各自排隊，9 個完整的 main run（每個 18 個 job）陸續啟動。同時還有約 70 個完整的 PR run 在跑。 |
| 08:42（00:42Z） | #387 flex-dispatch（裡面有一個 WIP commit）在自己的 PR CI 還沒跑完時被合併。main 的 b0722e7 有 8 個 shard 失敗。 |
| 08:43（00:43Z） | TestFlight run 38189078951 從 **b0722e7（紅的）** 上傳了一版。 |
| 09:03（01:03Z） | 用來修 #387 的 #389 也沒等 CI 跑完就合併，教學測試變紅（d9ad407）。 |
| 09:04（01:04Z） | #387 自己的 PR run 到這時才判定失敗，已經是合併後 22 分鐘。 |
| 09:19（01:19Z） | #388 合併，跟著繼承了紅（e479a40）。 |
| 09:32（01:32Z） | #393 合併。main 的 83b8bc8 16 個 shard 全綠（run 38192293606）。從這裡開始，Linux 測試在 main 上沒有再真的失敗過。 |
| 09:53–10:04（01:53–02:04Z） | 三個 main 完整 run 的 shard 建立以後，等了 60–83 分鐘才拿到 runner。 |
| 10:00（02:00:50Z） | Linux 排隊最高峰：122 個 job。 |
| 10:15（02:15:17Z） | 建立 ruleset `main-gate`。從此 PR 必須等 `Swift CI (gate)` 綠才能合併。 |
| 11:11（03:11Z） | #400 合併。main push 改成共用 `ci-main` 群組：同時只跑一個、只留最新一個在等。判斷要不要跑測試，也改成跟上一次成功的 push 比較（下文稱 push-base）。 |
| 11:17–11:59（03:17–03:59Z） | 大量手動取消 main 的 run（03:17–03:22、03:36、03:49–03:59）。b0722e7、d9ad407、e479a40 那三個真的有失敗的 run 也被取消，所以結果顯示 cancelled，而不是 failure。 |
| 11:37（03:37Z） | 最糟的時段結束。 |
| 12:13（04:13Z） | main 的 full lane 在 49de93f（#391 觀光）失敗：iPhone 橫放時按不到「回到開始畫面」。iOS full lane 從約 12:40 一直紅到 18:05。 |
| 13:34–14:05（05:34–06:05Z） | 第二波塞滿，持續 31 分鐘。80 個 Linux job 排隊，最久等 16 分鐘。14:01–14:05 又一波大量取消，才結束。 |
| 14:14–14:32（06:14–06:32Z） | 440736e 的 main CI 重跑（attempt 2），14:32 轉綠。 |
| 14:15（06:15Z） | 440736e 的 full lane 有 4 個 UI 測試失敗，比上次多了設定頁的 3D 城市預覽。 |
| 14:48–15:30（06:48–07:30Z） | 第三波。31 個 Linux job 排隊，最久等 14 分鐘。macOS 5 台全滿時，iPad 教學 job 等了 7–10 分鐘。 |
| 15:30（07:30Z） | #422（決策 185，PR 分級）合併。之後每個 PR run 用的 Linux 時間，中位數從 174 分鐘降到 10 分鐘。 |
| 15:31:39–43（07:31Z） | 有一個 orchestrator 在 4 秒內把 main 合進 5 個 PR，5 個全部重跑。 |
| 15:50（07:50Z） | 最後一波手動取消 main 的 run。 |
| 16:00 以後 | 平靜，等待都不到 1 分鐘。 |
| 17:27（09:27Z） | #427 合併（3f97f18），full lane 38230034913 29/29 綠。 |
| 17:28（09:28Z） | TestFlight 38230113268 從 3f97f18 上傳。 |
| 19:19（11:19Z） | main 沒有任何 run 在排隊或執行，全綠。 |

### 1.2 排隊數字

| | Linux | macOS |
|---|---|---|
| 拿到 runner 的 job 數 | 2,257 | 148 |
| 等待中位數 | 0.17 分 | 0.20 分 |
| p90 / p95 | 16.9 / 25.0 分 | 3.8 / 5.6 分 |
| 最久 | 82.7 分 | 9.9 分（從 10/11 00:57Z 起算的較大窗口是 12.4 分） |
| 等超過 10 / 30 / 60 分 | 423 / 83 / 11 | 0 / 0 / 0 |
| 還在排隊就被取消 | 285 個（中位數等 4.1 分，合計 2,437 job-分鐘） | 5 個 |
| 今天用掉的時間 | 17,387 job-分鐘 | 2,153 job-分鐘 |

- 最糟的 3 小時（08:29–11:37）裡建立了 854 個 Linux job，等待中位數 9.2 分鐘、p90 29.4 分鐘。
- 粗估那段時間 Linux 需要超過 8,000 job-分鐘。40 格 × 189 分鐘的容量只有約 7,560。需求比容量大，隊伍只會越排越長。
- 這個粗估用 shard 的中位數 10.9 分鐘計算，並扣掉很短的 changes / gate job。

### 1.3 根本原因

1. **40 格的總上限被 Linux 的 Swift shard 吃滿。**
   - 一次完整 CI 有 18 個 job：changes、15 個 campaign shard、rest、gate，合計約 190 runner-分鐘。
   - #422 之前，每次 PR push 和每次 main push 都會跑全部 16 個 shard。
   - 112 個 PR run 用了 12,414 分鐘，48 個 push run 用了 4,549 分鐘。
   - 三個 GameCore PR 同時 push，就是 54 個 job，已經超過 40。
2. **#400 之前，每個 main push 各自排隊。** 08:33–09:42 有 9 個完整的 main run 同時在搶位子。
3. **把 main 合進 PR 分支，引發大量重跑。**
   - 44 個 CI run 和 41 個 iOS run 是「Merge main into branch」commit 觸發的。
   - 佔 PR 的 Linux 時間 39%（4,823 分），macOS 時間 41%（614 分）。
   - 其中約三分之二的合併根本沒改到 PR 自己的內容（用 git patch-id 比對）。
4. **被取消的 run 白跑了。**
   - 結果是 cancelled 的 run 共用掉 3,769 Linux 和 212 macOS job-分鐘，約 66 runner-小時，約是今天 Linux 時間的 22%。
   - 新 push 取代舊的 PR run：2,595 分。
   - 手動取消 PR run：407 分。
   - 手動取消正在跑的 main run：729 分。
5. **平行的 session 很多。**
   - 有 46 個分支跑了 PR CI。tourism push 了 8 次，hsr、flow-layer-board、rolling-stock-economics 各 6 次。
   - 早上大家同時開工，尖峰全擠在 08:30–11:30。
6. **macOS 不是主因。**
   - macOS 的 p90 只等 3.8 分鐘。
   - macOS 的等待約有一半（53%）發生在 macOS 還沒滿 5 台、但 40 格已經被 Linux 佔滿的時候。
   - 在 macOS 5 台全滿時發生的等待約佔 43%。
7. **快取幫不上大忙。** 每個 shard 的 build 只要約 1.6 分鐘，測試要 8.9 分鐘，快取 build 能省的有限。

另外，排程（cron）今天大幅延遲或根本沒觸發：
- ios-build 的夜間 run 晚了 3 小時 39 分。
- release-archive 晚了 3 小時 42 分。
- full lane 03:17Z、06:17Z 這兩個時段沒有觸發。

GitHub 的排程本來就是盡量準時、尖峰時會延遲（這點本次沒有重新查官方網址，未確認）。合併後自動觸發的 full lane 補上了空缺。

### 1.4 GitHub 有沒有事故

沒有，10/11、10/12 都沒有事故。

- 台灣 19:21（11:21Z）查了 githubstatus.com 的 Statuspage API（https://www.githubstatus.com/api/v2/incidents.json，另外查了 incidents/unresolved.json 和 summary.json）：狀態是 All Systems Operational，Actions 正常，沒有未解決的事故。
- 最近跟 Actions 有關的事故：
  - 10/7：兩次約 10 分鐘的全站降級。
  - 10/5：指派 runner 延遲。
  - 10/1：Ubuntu / Windows job 延遲。
- 今天另外有 macOS 14 映像的停用演練（brownout），時間是台灣 10/12 22:00 到 10/13 08:00，只影響 `macos-14` 標籤。本專案用 `macos-26`，不受影響。

## 2. Merge 連環紅：每一個紅的原因與現在狀態

- 台灣 00:00 以來 main 合併了 48 個 PR，其中 14 個 merge commit 帶紅 X。
- `Swift CI (gate)` 今天失敗 66 次，其中 57 次發生在被取消的 run 裡。很多紅 X 其實只是「被取消」。

### 2.1 main 上的紅

| # | commit（PR） | 失敗的地方 | 類別 | 原因 | 狀態 |
|---|---|---|---|---|---|
| 1 | b0722e7（#387 flex-dispatch） | ci.yml run 38189051220：16 個 shard 有 8 個失敗（campaigns-2/3/6/7/8/12/13 和 rest） | 真 bug | 合併時自己的 PR CI（38188513054）還在跑，22 分鐘後才判紅。當時還沒有必要檢查（`main-gate` 到 10:15 才建立）。詳細見表下說明。這個 run 被手動取消，所以顯示 cancelled，裡面其實有 8 個真的失敗。 | **已修**：#389（d9ad407），內容見表下。d9ad407 上的 main run 38190404502 15 個 campaign shard 全過。 |
| 2 | d9ad407（#389）、e479a40（#388） | rest：`TutorialSessionTests.testTheStartScreenStartsANewGameWithTheTutorial`（第 324 行）。兩份 GameWorld 只差在 `flexDispatch` | 測試寫錯 | #389 讓教學關掉彈性調度，但沒有改測試裡預期的世界。#389 也沒等 CI 就合併（PR run 38189810162 在 09:25 判紅）。#388 只是疊在上面，繼承了紅。 | **已修**：#393（83b8bc8）補上 `expected.setFlexDispatch(false)`。run 38192293606 16/16 綠，之後每個完整 main run 都綠。 |
| 3 | 6b3e220（#392） | 不是紅，是**假綠** | CI 邏輯 | 舊的 push 判斷只跟 `github.event.before` 比。#392 只改了 RailwayGameApp.swift，Swift job 就被跳過，套件明明是壞的卻顯示綠。 | **已修**：#400 改成跟 push-base（上一個成功 push run 的 head）比較。 |
| 4 | #386 | 開始畫面的 `start.demoMap` 按不到（PR run 38188889922、38189810083） | 真 bug | 一樣是沒等 CI 就合併。 | **已修**：#392 在 main 下一次 full lane（38190455758，綠）之前修好。 |
| 5 | 37d2904（#390）、baf6162（#397）、98749b9（#400）、5de5dcd（#398）、e30ce96（#401）、af7175e（#399）、77b2229（#407）、46a9ee7（#406）、440736e（#408）、a72d323（#423） | 只有 `Swift CI (gate)` 紅，訊息是 "A Swift job did not succeed (Swift 6.4: cancelled)" 或 "The change detection did not succeed." | 基礎設施（假紅） | 這些 run 被手動取消，或被 session 用作者的 token 取消。詳細見表下。**沒有任何測試失敗。** | **機制未修**。440736e 已經重跑轉綠，其餘 9 個還是紅 X。修法見 2.2 (A)。 |
| 6 | 49de93f（#391 觀光）首次發現，440736e 也有 | full lane（38202914204、38211636581）：`menu.backToStart` 按不到；`RealWorldMapUITests.testARealWorldGameStartsFromAPlaceAndIsSavedAsOne` 和 `StartSaveFlowSmokeTests` 的兩個存檔測試失敗 | 真 bug（App） | #391 在遊戲選單加了「觀光景點」。詳細見表下。 | **已修**：#423（a72d323），內容見表下。full lane 38230034913 在 3f97f18 通過。 |
| 7 | 440736e（由 #402 引入） | full lane 38211636581：`SettingsUITests.testTheCityPreviewLoadsItsPageAndCloses`（第 63 行）"Missing the 3D city preview" | 測試寫錯 | #402（日夜，決策 182）在設定頁加了「地圖」區塊，iPhone 橫放時「實驗功能」那一列跑到畫面外。SwiftUI List 要捲到那一列才會建立它，測試卻先等它出現才捲。 | **已修**：#427（3f97f18）只改測試，改成先捲到整列可見再點。29/29 通過。 |

表中幾列的補充說明：

- **第 1 列為什麼會壞**：#387 把彈性調度（決策 172）無條件打開，造成：
  - 所有差分測試和屬性測試都跟參考模型對不上。
  - line-patterns.json 重播的第 12 個 checksum 變了。
  - SaveFixtures/v45-flex-dispatch.json 沒有 commit 進來。
  - 一個中文字串多了一個空格。
- **第 1 列怎麼修的**：#389 做了這些事：
  - 把功能放到 `GameWorld.flexDispatch` 開關後面：舊世界和重播預設關、新遊戲開、教學和高鐵示範明確關。
  - 補上存檔 fixture 和 golden。
  - 修好字串。
  - 沒有重錄任何 ReplayFixtures。
- **第 5 列為什麼是假紅**：
  - 被取消的 job 註記都是 "The run was canceled by @a91453."。repo 裡沒有任何 workflow 或腳本會取消 run。
  - gate 設定成 `if: always()`，run 被取消後它照樣執行。`swift-shards.sh gate` 把 cancelled 當成失敗，那個 commit 就永遠掛著一個紅 X。
  - push-base 串起來的鏈 83b8bc8 → 49de93f → … → 390bcd7 → 3f97f18 證明，這些 commit 的改動後來都被完整測過，也都通過。
- **第 6 列為什麼會壞**：
  - 空白新遊戲或真實地圖的選單太長。後來 #413 再加上城市請求目標，變成 8 列。iPhone 橫放時，最後一列「回到開始畫面」超出可以點到的範圍。
  - PR 的 UI 測試只跑示範地圖的存檔流程，那裡沒有觀光、也沒有目標，所以只有 main 的 full lane（最多 3 小時跑一次）抓得到。
- **第 6 列怎麼修的**：#423 把選單固定成 6 列，目標、觀光、說明收進「更多」，並把那兩個測試加進 PR 的 UI 測試清單。

**現在狀態（台灣 19:19）**：main HEAD 是 3f97f18。

- ci.yml：38230020485 成功。這次只改 UI 測試，Swift job 正確跳過。
- 最後一次完整 Linux run：38223356327（390bcd7），16/16 綠。
- ios-build full lane：38230034913 29/29 綠，iPad 教學也通過。
- ios-full-lane、wasm-probe、website-screenshots、TestFlight 在 3f97f18 都成功。

**main 上沒有還沒修的失敗。**

### 2.2 未修的項目與修法

**(A) 手動取消 main 的 run 會把 gate 塗紅**

嚴重度低：紅 X 本身不會擋任何東西，但會讓人以為 main 壞了。

1. **流程（這是根本原因）。** 在 CLAUDE.md 的 Workflow 一節，以及 ci.yml `concurrency:` 上方的註解，加一條規則：
   - 不要手動或從 session 取消 main 上的 ci.yml push run（`gh run cancel` 用的是作者的 token）。
   - `ci-main` 群組已經會把一連串合併壓成「正在跑的一個加上最新的一個」。
   - 要騰出位子，只取消 PR 的 run。
2. **程式（選做）。** 改 ci.yml 第 190 行的 `gate` job：
   ```yaml
   gate:
     name: Swift CI (gate)   # 名稱不能改，main 的規則要求它
     needs: [changes, swift-current]
     # 被取消的 push run 沒有結論可給，跳過它，就不會在沒有失敗的 commit 上掛紅 X。
     # PR 仍然 always()：被跳過的必要檢查會被當成通過。
     if: ${{ always() && !(cancelled() && github.event_name == 'push') }}
   ```
   - shard 逾時不會讓整個 run 變成 cancelled，所以逾時照樣會紅。
   - 重跑（attempt 2）時 gate 照常執行。
   - swift-shards.sh 不用改。
   - **未確認**：被取消的 shard 自己的 check 仍然留在 commit 上。GitHub 的 commit 摘要會顯示灰色還是紅色，本次無法驗證（GraphQL 被擋）。
3. **清掉既有的 9 個紅 X（選做，需要作者同意）。**
   - 對這些 run 執行 `gh run rerun`：38192920776、38196915104、38198784250、38201226606、38201230080、38201378495、38209722469、38210579728、38219811712。
   - 每個要跑 17 個 job。後來的綠 run 已經測過這些 commit，所以重跑沒有測試上的價值，只是讓歷史紀錄好看。
   - 本次沒有重跑任何東西。

**(B) `rest` shard 快要逾時**（潛在風險，還沒發生）

- 今天 `rest` 中位數 13.8 分鐘、最長 18.9 分鐘，有 10 次落在 17.8–18.9 分鐘，上限是 20 分鐘。
- 逾時會顯示 cancelled，gate 就會變紅。PR 和 main 都會出現沒有真正失敗的紅 X。
- 修法見 4A-3。

**(C) PR 上看起來不穩的 UI 測試**（未確認，建議交給下一個修 bug 的 session 查）

main 上今天的失敗都能重現，不是 flaky。但 PR 上有幾個可疑的：

- `MapInteractionTests.testMapLayersSheetTogglesAndDismisses`：fix-sell-freight-train 第 1 次失敗，同一個 commit 重跑就通過，這是 flaky 的直接證據。onboarding-newgame、flex-dispatch 也失敗過。
- `MapInteractionTests.testSwitchingFollowTargetWhilePausedCentersTheCamera`：line-ledger 兩次都失敗。
- `StartSaveFlowSmokeTests.testEnglishStartSaveFlow`：onboarding-newgame、flex-dispatch、qol-bundle 都失敗過。
- `TrainServiceTests.testATravellingTrainWaitsForRemovedTrackAndIsNotRerouted`：只在 full-code-review-2 的 PR 失敗過一次。

這些可能是那些分支自己的改動造成的，也可能是測試本身不穩，資料分辨不出來。

**(D) 有問題的 TestFlight 版本**

- 台灣 08:43（00:43Z）的 TestFlight run 38189078951 上傳的是紅的 b0722e7：彈性調度無條件打開，v45 的存檔 fixture 也缺。
- 建議不要把這個 build 發給測試者，或在 App Store Connect 讓它過期（這要作者自己操作）。
- 17:28 從 3f97f18 上傳的版本沒問題。

**(E) PR 分支上的 Website screenshots**

- claude/yanzhan-dev-progress-9ekqho 前兩次在 `WebsiteScreenshotTests` 的 testLineReportAndPassengerLoad、testTourism 失敗。
- 第三次在抓資料的時間點（19:12）還在跑。
- 這不在 main 上，結果未知，由那個 PR 自己處理。

## 3. 買了 GitHub Pro 為什麼還在排隊

官方的同時 job 上限（標準 GitHub-hosted runner，總數 / macOS），來源：https://docs.github.com/en/actions/reference/limits

| 方案 | 總數 | macOS |
|---|---|---|
| Free | 20 | 5 |
| **Pro（目前的方案）** | **40** | **5** |
| Team | 60 | 5 |
| Enterprise | 500 | 50 |

超過上限的 job 就只能排隊。

- **對公開 repo 來說，Pro 在 Actions 上唯一的效果是總上限從 20 變成 40。** 公開 repo 用標準 runner 本來就免費。Pro 多給的分鐘數（3,000 分）只對私有 repo 有意義。來源：https://docs.github.com/en/billing/concepts/product-billing/github-actions
- **macOS 上限在 Free、Pro、Team 都是 5**，只有 Enterprise 是 50。同一頁 limits 文件也寫明：macOS 的同時上限由標準 runner 和大型 runner 共用。
- **個人帳號不能用大型 runner（更快的 macOS）。** 大型 runner 只開放給 Team 或 Enterprise Cloud 的組織，而且公開 repo 也要付費。來源：https://docs.github.com/en/billing/reference/actions-runner-pricing
- **今天實測正好撞到 Pro 的天花板。**
  - 同時執行的總數最高正好 40，macOS 最高正好 5，從來沒有超過。
  - 台灣 08:29–11:37 有約 182 分鐘停在 39–40。
  - 如果還是 Free（20 格），同樣的需求會排得更久。Pro 有幫忙，只是需求比 40 還大。
- **40 格由 Linux 和 macOS 共用。**
  - Linux shard 把 40 格佔滿時，macOS 就算只用了 2–4 台也拿不到位子。
  - 今天等超過 2 分鐘的 35 個 macOS job 裡，有 18 個是在 macOS 還沒滿 5 台時等的。
- 文件說可以開 support ticket 請 GitHub 提高上限，但沒說個人 Pro 帳號會不會核准（未確認）。

一句話：**Pro 把容量從 20 格加到 40 格，但每推一個 GameCore 改動就要用掉 18 格，幾個 session 一起推就滿了。** 解法主要是減少每次用掉的格數（第 4 節）。

## 4. 改善建議（依效果排序）

估算方式：

- 只有需求超過 40 格時才會排隊。
- 全滿時，每省下約 190 runner-分鐘（一次完整 Swift run），排在後面的所有 job 大約可以早 5 分鐘（190 ÷ 40）拿到 runner。
- 以下的「省多少」用今天的實際資料回推。#400、#422 已經生效，明天同樣的工作量本來就會比今天輕，**實際省下的會比今天的數字少**。

### 4A 現在就能做（改流程或 workflow，不降低測試覆蓋）

**4A-1　流程規則：不手動取消 main、不要順手把 main 合進 PR、改好再一次 push**

效果最大，不花任何成本。

- **改哪裡**：CLAUDE.md 的 Workflow 一節；ci.yml `concurrency:` 上方的註解。
- **加三條規則：**
  1. 不要手動或從 session 取消 main 上的 ci.yml push run。要騰位子，只取消 PR 的 run。
  2. 只有 GitHub 顯示衝突、或 PR 需要 main 上的東西時，才把 main 合進 PR。
     - main 的規則不要求分支是最新的（`strict_required_status_checks_policy` 是 false）。
     - 不要一次把 main 合進所有 PR（今天 15:31 有一次 4 秒內合了 5 個）。
  3. 改動準備好才 push，CI 在跑的時候不要陸續推 docs 小修。
     - PR 的 iOS run 還在跑時，不要對同一個 commit 再手動 dispatch 一次 ios-build。今天 claude/fix-city-preview-test 有 3 次同時跑了兩份。
- **放棄的覆蓋**：PR 合併前不一定和最新的 main 一起測過。規則本來就沒要求這件事，main push 的完整 run 和 full lane 會接住整合問題。
- **預估省多少：**
  - 今天 merge-main 觸發的 run 佔 PR 的 Linux 時間 39%（4,823 分）、macOS 41%（614 分），其中約三分之二沒改到 PR 本身。
  - #422 分級之後，Linux 省下的主要在 GameCore PR（每次重跑約 190 分鐘）。macOS 每次 16 分鐘照樣省。
  - 今天手動取消 main 的 run 直接浪費了 729 Linux 分鐘，還造成 10 個假紅 X。

**4A-2　iOS 加上「同一份改動已經通過就不重跑」的標記**

這項最能省 macOS 時間。

- **改哪裡**：.github/workflows/ios-build.yml。
- **做法：**
  - 用 PR 對 App 相關路徑的改動算出一個 key（git patch-id）。
  - 查這個 PR 有沒有同一個 key 通過過。有，就跳過 macOS 的 job。
  - 全部通過後，由一個新的小 Linux job 把 key 存起來。
  - `changes` job 已經是 `fetch-depth: 2`，可以直接用 `HEAD^1`。
  - 用到的是 GitHub 官方的 `actions/cache`。
- **骨架**（實作的 session 可以照這個寫）：
  ```yaml
  # changes job 的 outputs 加上：
        key: ${{ steps.key.outputs.key }}
        passed: ${{ steps.passed.outputs.cache-hit }}
  # changes job 在 detect 之後加上：
        - name: Key of the pull request's change to the app
          id: key
          if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository
          env: { IPAD: "${{ steps.detect.outputs.ipad }}" }
          run: |
            id="$(git diff HEAD^1 HEAD -- RailwayGameApp Sources Package.swift Package.resolved \
              .github/workflows/ios-build.yml .github/actions .github/scripts/check-localization.py \
              .github/scripts/check-localization-selftest.py .github/scripts/localization-fixtures \
              | git patch-id --stable | cut -d' ' -f1)"
            echo "key=ios-pr-passed-v1-ipad-$IPAD-${id:-empty}" >> "$GITHUB_OUTPUT"
        - id: passed
          if: steps.key.outputs.key != ''
          uses: actions/cache/restore@v4
          with: { path: .ios-pr-passed, key: "${{ steps.key.outputs.key }}", lookup-only: true }
  # build：         needs: changes
  #                 if: needs.changes.outputs.passed != 'true'
  # ipad-tutorial： if: needs.changes.outputs.ipad == 'true' && needs.changes.outputs.passed != 'true'
  # 新的 Linux job `remember`：needs [changes, build, ipad-tutorial]。
  #   build 成功、而且 iPad 成功或被跳過時，用 actions/cache/save@v4 存下 .ios-pr-passed（key 同上）。
  ```
- **補充：**
  - 只對同一個 repo 的 PR 啟用。fork 的 PR 不算 key，避免有人偽造標記。
  - PR 存的 cache 只在 `refs/pull/N/merge` 範圍內有效，所以標記只對同一個 PR 有用。
  - 要強制重跑，就刪掉那筆 cache，或把 key 裡的 `v1` 改成 `v2`。
- **放棄的覆蓋：**
  - 乾淨地合進 main、沒動到 App 路徑的 PR，不會在 macOS 上對新的 main 再測一次。這跟 base 往前走、但 PR 沒有 push 的情況一樣。
  - main 的 full lane（合併後最多 3 小時）會抓到整合問題。
  - 解衝突時如果動到 App 路徑，patch-id 會變，照樣會跑。
  - ios-build 不是必要檢查，所以不會讓合併的檢查誤判成綠。
- **預估省多少：**
  - 今天 100 個 iOS PR run 裡有 35 個（524 macOS 分鐘，35%）重測了已經通過的同一份改動。
  - 等於每天少佔用約三分之一的 macOS 時間。
  - 今天 macOS 的等待有 43% 發生在 5 台全滿時，這部分大多會消失。
  - 代價是 `build` 要多等 `changes` 跑完，約 15 秒。

**4A-3　重新分配 `rest` shard**

防止假紅，也讓完整 run 更快跑完。

- **改哪裡**：.github/scripts/swift-shards.sh 的 `classes_of`（第 176、180 行），並在上方的時間表加一行註明日期。CLAUDE.md 已經允許這種調整。
- **怎麼改：**
  ```bash
  campaigns-11) echo "ScheduledTrafficSecondHalfPropertyTests HighSpeedDemoTests" ;;
  campaigns-15) echo "TrafficFollowingPropertyTests RealWorldDemoTests" ;;
  ```
- **放棄的覆蓋**：無。`run` 一開始的分配檢查會確認沒有測試被漏掉或跑兩次。
- **預估（慢的 runner 上）：**

  | shard | 現在 | 改了以後 |
  |---|---|---|
  | rest（最長） | 約 18.9 分 | 約 15.8 分 |
  | campaigns-11 | 約 9.5 分 | 約 11.4 分 |
  | campaigns-15 | 約 10.1 分 | 約 11.5 分 |

  - 一次完整 run 的實際經過時間從約 19 分鐘變成約 16 分鐘（由 campaigns-1 決定）。
  - runner 總分鐘數不變，但每次完整 run 佔住格子的時間少約 3 分鐘。
  - 也消除了快要發生的逾時假紅。

**4A-4　被取消的 main push 不再塗紅 gate**

- **怎麼改**：改 ci.yml 第 190 行的 `if:`（見 2.2 (A)）。
- **放棄的覆蓋**：無。只影響 push，PR 照樣是 `always()`。
- **預估**：不會減少排隊，但今天那 10 個假紅 X 不會再出現。

**4A-5　手動執行 ios-build 時，可以只跑指定的 UI 測試**

- **改哪裡：**
  - ios-build.yml：
    - `workflow_dispatch` 加一個 `only_testing` 輸入。
    - 加 `run-name`。
    - 有輸入時設 `ipad=false`。
    - UI 測試步驟加上 `-only-testing:`。
  - ios-full-lane.yml 第 98、113 行：在 `select(.event != "pull_request")` 後面加上 `| select((.display_title // "") | startswith("UI tests by hand:") | not)`，讓這種只跑部分測試的 run 不被當成 full lane。
- **放棄的覆蓋**：無。輸入留空時，行為跟現在一樣。
- **預估省多少：**
  - 修 bug 階段最常用到。
  - 今天有 4 次只是為了驗證一兩個 UI 測試的修正，就手動跑了整條 full lane，共用約 191 macOS 分鐘。每次約 48 分鐘：iPhone 29–41 分鐘，加上 iPad 11–15 分鐘。
  - 只跑指定的測試，大約是建置、開模擬器、再跑幾個測試，粗估 10–15 分鐘（未實測）。每次能省 30 分鐘以上的 macOS 時間。

**4A-6　Website screenshots 不在 PR 上自動跑**

- **改哪裡**：.github/workflows/website-screenshots.yml，刪掉 `pull_request:` 和它的 `paths:`（第 14–18 行附近）。同時更新檔頭註解，以及 CLAUDE.md 裡「or on a pull request that changes them」那句。
- **以後怎麼跑**：需要截圖時，到 Actions 頁面對 PR 分支手動執行。
- **放棄的覆蓋**：如果 PR 弄壞了截圖測試，要等有人手動跑才會發現。這個 workflow 本來就不擋合併（決策 165：它不測任何東西）。
- **預估省多少**：今天 4 個 PR run 用了 76 macOS 分鐘（2 個失敗、1 個取消），每次佔一台 macOS 13–24 分鐘。

**4A-7　PR 的 UI 測試步驟上限從 40 分鐘降到 25 分鐘**

- **改哪裡**：ios-build.yml 第 342 行，改成 `timeout-minutes: ${{ github.event_name == 'pull_request' && 25 || 40 }}`。
- **放棄的覆蓋**：無。但如果 PR 的 UI 測試清單變長、或 runner 慢了兩倍以上，就可能逾時。PR #429（claude/tutorial-card-unblock）正在加一個測試進清單，要一起看。
- **預估**：平常不會省。App 卡住時（像 #207 那種情況），可以少佔一台 macOS 15 分鐘。今天 PR 上這個步驟最長是 12.7 分鐘。

**4A-8　三個觸發條件的小修正**

1. **ci.yml 第 44 行**：改成 `types: [opened, synchronize, reopened]`，拿掉 `labeled`。
   - 現在加任何標籤，都會取消正在跑的 run 再重來。
   - 要升級成全量時，就「加上 full-ci 標籤，再按 Re-run all jobs」。ci.yml 本來就從 API 讀標籤。
   - 今天沒用到標籤，所以目前沒有成本，這是預防。
2. **ios-full-lane.yml 的 `paths-ignore`**：補上 `.github/workflows/website-screenshots.yml`，跟 ios-build.yml 的 PR 過濾保持一致（它自己的註解就要求兩邊一致）。
3. **wasm-probe.yml 第 29–30 行**：
   ```yaml
   concurrency:
     group: wasm-probe-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
     cancel-in-progress: ${{ github.event_name == 'pull_request' }}
   ```
   - main 上的 run 不再互相取消（今天發生 3 次），每個 commit 都會有結果。
   - 代價是多花一點 Linux 時間，每次約 5 分鐘。

### 4B 免費，但會降低覆蓋或改變規則，需要作者同意

**4B-1　main push 也照決策 185 分級，另外每晚跑一次全量**

這項最能省 Linux 時間。

- **改哪裡：**
  - .github/scripts/swift-shards.sh 的 `ci_decide`（第 830–831 行）：讓 `push` 也分級。`full-ci` 標籤只對 PR 有效。
  - ci.yml 的 `on:`：加上 `schedule: - cron: "41 17 * * *"`（台灣 01:41）。
  - ci.yml 的偵測腳本（第 117 行附近）：把 `schedule` 當成全量，而且不要發警告。
  - swift-shards-selftest.sh：把「main push 只改 GamePresentation 仍然跑全量」改成 presentation，並新增「schedule 跑全量」。
  - CLAUDE.md 和決策 185：
    - 改掉「a push to main … run every test」這句。
    - 把已經過時的「GitHub Free 20 jobs」前提，改成 Pro 的 40 / 5。
- **放棄的覆蓋：**
  - campaign 不再每次 main push 都跑。只有動到 GameCore、測試、fixture、Package、CI 腳本時才跑，再加上每晚一次。
  - 環境變動（例如 swift:6.4-noble 換了小版號）要等夜間那次才抓得到。
  - 今天的排程晚了 3 個多小時，有的還沒觸發，所以夜間全量也可能晚跑。可以考慮比照 full lane「合併後補跑」的做法。
- **預估省多少：**
  - #422 之後的 4 個 main push 裡，有 2 個（66fd098 #411、390bcd7 #416）只動到 GamePresentation。
  - 這種 push 每個可省約 190 runner-分鐘（18 格 × 約 17 分鐘）。
  - 尖峰時，每個這樣的合併大約讓排隊少 5 分鐘。

**4B-2　Swift gate 也加上「同一份改動已經通過」的標記**

- **改哪裡：**
  - ci.yml 的 `changes` job：用 patch-id 加上測試分級當 key，命中就讓 `swift` 輸出 false。
  - `gate` job：通過後存下 key。
  - swift-shards.sh gate：訊息改成「已通過」。
- **放棄的覆蓋**：**必要檢查會在一個沒跑任何測試的 run 上通過**，依據是同一份改動先前在比較舊的 main 上跑出的綠。這改變了 `Swift CI (gate)` 的意義，需要作者同意，並寫一條 ARCHITECTURE 決策。
- **預估省多少：**
  - 今天 112 個 PR run 裡有 19 個（1,970 Linux 分鐘，16%）重跑了已經通過的同一份改動。
  - 其中大多發生在 #422 之前。做了 4A-1 之後，剩下的量會更少。
  - **建議排在後面，先看 4A-1 的效果。**

**4B-3　每個 PR 不要為了繁中翻譯檢查再完整編譯一次**

- **改哪裡**：ios-build.yml，以及 .github/scripts/check-localization.py。
- **方案 A（不降低覆蓋，但要改腳本）：**
  - 模擬器建置加上 `SWIFT_EMIT_LOC_STRINGS=YES`。
  - PR 上改由 check-localization.py 讀 `.stringsdata`。
  - 非 PR 的 run 保留 `-exportLocalizations`。
  - 風險：`.stringsdata` 是 Xcode 沒有公開文件的格式。
- **方案 B（只改 YAML）：**
  - 翻譯匯出只在 full lane 跑。
  - 放棄的覆蓋：PR 加了沒翻譯的字串不會再被擋。最晚合併後 3 小時由 full lane 發現，而且那個結果不擋任何東西。
- **預估省多少：**
  - 每個 iPhone job 中位數 1.7 分鐘（p90 2.9 分鐘）。
  - 今天 85 個 job 共 156 macOS 分鐘，約佔 PR macOS 時間的 10%。
  - #356 曾經試過重用模擬器的建置，後來被 revert。

**4B-4　PR 跑全量時，先跑 `rest`，通過了才展開 15 個 campaign**

- **改哪裡：**
  - ci.yml：拆成 `swift-rest` 和 `swift-campaigns` 兩個 job，只在 pull_request 時這樣拆。
  - swift-shards.sh：`ci_decide` 輸出兩個 matrix，gate 合併兩邊的結果，selftest 跟著更新。
- **放棄的**：綠的 GameCore PR 要等約 30 分鐘才跑完（現在空閒時 17–19 分鐘）。只有在搶位子的時候才划算。
- **預估省多少：**
  - 今天有 38 個全量 PR run 被新的 push 取代（約 3,000 分鐘），6 個失敗（1,074 分鐘）。
  - 粗估可省約 1,100 分鐘。
  - 這項會動到 gate 的邏輯，排最後。

### 4C 需要作者決定（花錢或自架 runner）

| 選項 | 對 macOS 排隊有幫助嗎 | 成本 | 說明與建議 |
|---|---|---|---|
| 請 GitHub Support 提高上限 | 可能 | 免費 | 文件說 support 可以用 ticket 提高上限。個人 Pro 帳號會不會核准、會不會連 macOS 一起提高，都未確認。值得問，但不要把它當成計畫。 |
| 用作者自己的 Mac 當 self-hosted runner（repo 層級） | 會 | GitHub 不收費；要作者的硬體、電費和維護 | 不算在 GitHub 的上限裡。但 GitHub 明講公開 repo「幾乎不應該」用 self-hosted：別人開一個 fork PR，就能在這台機器上跑程式，甚至長期入侵（https://docs.github.com/en/actions/reference/security/secure-use）。安全做法見表下。**建議：只用來跑 full lane 或夜間這類非 PR 的工作。** |
| Xcode Cloud 分擔夜間或發布建置 | 會（不在 GitHub 的隊伍裡） | Apple Developer 會員每月含 25 小時；加購 100 小時 $49.99/月、250 小時 $99.99/月（https://developer.apple.com/xcode-cloud/） | 本專案目前延後導入（docs/XCODE_CLOUD_ONBOARDING.md）。今天約 40 小時內就用了約 35 小時 macOS，每月 25 小時只夠一小部分（夜間或發布）。 |
| 第三方 macOS runner（WarpBuild、Depot、Bitrise Build Hub、Tenki、Namespace） | 會 | 例如 WarpBuild M4 Pro：$0.08/分（6 vCPU）、$0.16/分（12 vCPU）（https://www.warpbuild.com/pricing）。Depot 方案 $20/月起，macOS 每分鐘價格未確認 | 不受 GitHub 上限限制，硬體也比較快（這是廠商的說法）。個人帳號能不能用未確認，Depot 可能要求 repo 屬於組織。要安裝第三方 GitHub App，算是新的依賴，需要作者同意。 |
| 搬到組織並改用 GitHub Team | 不會 | 前 12 個月每人 $4/月（https://github.com/pricing）；大型 runner 另外計費 | 總數變 60，macOS 仍是 5，而且跟大型 runner 共用。要重新設定 secret、environment、分支規則和 TestFlight。**不建議**：麻煩又對 macOS 沒幫助。 |
| GitHub Enterprise Cloud | 會（macOS 50） | 每人 $21/月起，另加大型 runner 費用 | 唯一能提高 macOS 上限的方案。對一人專案太貴，也要先有組織。**不建議。** |
| macOS 大型 runner（macos-26-xlarge M2 Pro $0.102/分、-large Intel $0.077/分） | 不會（共用那 5 格） | 公開 repo 也要付費 | 個人 Pro 帳號不能用。 |
| concurrency 的 `queue: max`（2026-05 新功能） | 不會 | 免費 | 只是讓同一個群組最多排 100 個，不會增加容量。還可能讓被取代的 run 不再被取消，反而加重負擔。**不建議。** |
| 等 GitHub 修 | 不會 | — | 今天沒有事故，是我們自己的上限。 |

如果真的要用 self-hosted runner，至少要做到：

- 只接受 push 到 main 和 workflow_dispatch，或在 job 上加 `if: github.event.pull_request.head.repo.full_name == github.repository`。
- repo 設定成「所有外部貢獻者的 workflow 都要核准」。
- 用 ephemeral 或 JIT runner，跑在獨立的 macOS 使用者帳號或可以丟掉的 VM 裡。
- TestFlight 的 secret 絕對不能放上去。
- Mac 要一直開著，Xcode 版本也要對。

**建議順序**：先把 4A 全部做完（尤其是 4A-1、4A-2、4A-3），觀察幾天。macOS 還是不夠，再考慮 4C 的 self-hosted（只跑非 PR 的工作），或用 Xcode Cloud 分擔夜間建置。

## 5. 建議的合併節奏

1. **一批一批合併。**
   - 一次合 3–5 個已經全綠的 PR，幾分鐘內合完。
   - `ci-main` 群組會把這一串壓成「正在跑的一個加上最新的一個」，所以一批大約只花兩次完整 main run，不是 N 次。
   - 等 main 的 ci.yml 變綠（空閒時約 17–20 分鐘），再合下一批。
2. **不要每次合併前都 update branch。**
   - main 的規則不要求分支是最新的。每合一個就把 main 合進所有 PR，只會讓全部重跑（就是今天 Linux 39%、macOS 41% 的重跑）。
   - 只有這三種情況才更新：
     - 有衝突。
     - PR 需要 main 上的東西。
     - PR 是 GameCore 改動，而且它上次變綠之後，main 又合了別的 GameCore 改動（可能有語意衝突）。
   - 要更新時，**只更新那一個 PR，而且在準備合併前才更新**，不要一次更新全部。
3. **合併順序**：GameCore 的 PR 先合（main 上本來就會跑全量），GamePresentation 和 App 的 PR 後合。
4. **一定要等 PR 的 CI 綠了才合。**
   - `Swift CI (gate)` 現在已經是必要檢查。
   - **iOS App Build 不是必要檢查。** 今天 #386、#391 的 App 問題都要靠人看。合併的人（session 或作者）請確認 iOS App Build 也是綠的。
   - 如果要把它設成必要檢查，要小心：被 paths 過濾掉而沒有觸發的 workflow，它的必要檢查會一直停在「等待中」。要先做一個一定會回報結果的 gate job（還沒實作，需要另外評估）。
5. **不要手動取消 main 的 run。** 要騰位子只取消 PR 的 run，優先取消已經被新 push 取代、或確定要重推的。
6. **同時在跑 CI 的 GameCore PR 最多 2 個。** 一個全量要 18 格，兩個就是 36 格，第三個進來就會塞滿 40。App / Presentation 的 PR 每次只佔約 1 台 macOS 和幾個 Linux job，可以多開一些。
7. **修 bug 階段的 session 節奏**（對應你說的「一次叫一個修，或等一群合併完再開一個大量查 bug」）：
   - 一波開 3–4 個修 bug 的 session，每個都改好了再 push。
   - 等這一波合併完、main CI 和 full lane 都綠了，再開一個「大量查 bug」的 session，從乾淨的 main 開始查。
   - 然後再開下一波。
8. **避開尖峰。** 今天台灣 00:00–07:30 和 16:00 以後完全不用排隊；08:30–11:30 最塞，因為大家同時開工。比較重的工作（GameCore 大改、手動跑 full lane）可以排到下午或晚上。
9. **發 TestFlight 之前**，先確認那個 commit 在 main 上的 ci.yml 全量是綠的、full lane 也是綠的。今天 08:43 那次就是從紅的 b0722e7 上傳的。
10. **每批合完看一次 full lane。**
    - PR 只跑一小組 UI 測試。今天選單、設定頁這類問題只有 full lane 抓到。
    - full lane 在合併後最多 3 小時才會跑一次。合完一批想早點知道結果，就手動 dispatch 一次。做了 4A-5 之後，可以只跑相關的測試。

## 附註：不確定或沒驗證的地方

- **Pro 的確切生效時間**：資料只能推到「最晚台灣 10/12 03:56」（19:56Z 同時跑了 27 個 job）。另一份分析看到上限從 18–20 跳到 40 是在 19:00–23:00Z 之間。兩者不衝突，但都不是確切時間。
- **需求估算**：「最糟時段 Linux 需要超過 8,000 job-分鐘」是用 shard 中位數粗估的。
- **4A-5 的耗時**：只跑指定 UI 測試要多久（10–15 分鐘）沒有實測。
- **4A-4 的顯示效果**：改完以後，被取消的 shard check 在 GitHub 的 commit 摘要上顯示灰色還是紅色，沒有驗證（GraphQL 被擋）。
- **誰取消了 main 的 run**：API 只記錄執行者是 a91453，可能是作者本人，也可能是用作者 token 的 session，分不出來。
- **flaky 的判斷**：PR 上疑似 flaky 的 UI 測試，只有 testMapLayersSheetTogglesAndDismisses 有「同一個 commit 重跑就通過」的證據。其他幾個分不出是分支本身的問題，還是測試不穩。
- **排程延遲**：今天實測確實有延遲，但官方文件的網址本次沒有重新查證。
- **改善項目都還沒做**：每一項都要另外開 PR，照 CLAUDE.md 由作者決定要不要合併。會改到 CLAUDE.md 規則或 gate 意義的（4B-1、4B-2），需要作者明確同意。
- **原始資料**放在本 session 的暫存目錄，session 結束後可能消失：（分析 session 的暫存目錄，已不保留）（runs_all.json、jobs/、jobs_table.csv、logs/、checkruns_live/）。