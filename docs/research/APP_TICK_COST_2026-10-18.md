# 600 倍跟不上、主執行緒卡頓：量出來的結果（2026-10-18）

#791 的審查記下兩件事，遊戲規劃派工追查（session_01Q48iRY9H6EmeUL8NPyfiDW，工作登記 #231）：

- 新遊戲買 15 列車、600 倍時，UI 測試的錄影裡 9 秒只走了 14 分鐘，應該是 90 分鐘。
- 時鐘停著時，App 的主執行緒也有好幾秒沒回應（一次查詢卡了 46 秒）。

**結論**：遊戲本身跟得上，模擬也很便宜。慢的是 XCTest 的無障礙查詢：每次查詢都在 App 的主執行緒上建一份畫面快照，時鐘在跑的時候更久。玩家不受影響（沒有測試在查詢），所以 App 不用改；UI 測試照 #791 的做法，查詢前先暫停、期限迴圈每一次都算。

## 1. 模擬便宜（Linux）

`Tests/GamePresentationTests/TickCostReportTests.swift`，只在要求時跑：

```sh
TICK_REPORT=200 swift test --filter TickCostReportTests
```

debug 建置，每個 tick（600 倍是 1 遊戲分鐘，每 100 ms 一個）的時間：

| 遊戲 | GameCore ms／tick | session ms／tick | 其中步後的工作 |
| --- | ---: | ---: | ---: |
| 新遊戲，買 15 列車（UI 測試那一局） | 0.16 | 0.23 | 0.06 |
| 簡單示範 | 22.5 | 23.0 | 0.5 |

畫面每次重畫向 session 讀的值（選取文字、列車與車型選單、路徑狀態、等待原因、路線選單），在 UI 測試那一局都在 0.1 ms 以下。示範地圖的 `LineMap(world:)` 是 4.3 ms，有快取（每次指令建一次）。
真實世界的資料讀取是 1.1 s，在主執行緒外跑；裝到 launcher 上不到 1 ms。

## 2. 不打擾 App 時，600 倍跟得上（macOS CI，iPhone 17 Pro 模擬器，Debug）

一個只在手動跑的 UI 測試，做法是：讀一次時鐘，10 秒內不問 App 任何東西，再讀一次。
- 結果（run [39083775376](https://github.com/a91453/railway-game-ios/actions/runs/39083775376)）：**10.1 s 走了 102 遊戲分鐘，應該 100**。
- 同一個 run 裡，原本的選單測試照樣通過。

## 3. 主執行緒忙在哪裡：幀數計（Debug、`-ui-testing`）

`RailwayGameApp.swift` 的 `FrameMeter`：
- 每 2 秒在 UI 測試的 trace 寫下畫了幾幀、兩幀之間最長隔多久；
- display link 只在主執行緒空著時觸發，所以長的間隔就是主執行緒忙了那麼久；
- Release 不寫。

`ios-build.yml` 在手動指定測試的 run 也保留這份 trace。

各狀態不打擾 8 秒（run [39085948745](https://github.com/a91453/railway-game-ios/actions/runs/39085948745)，每 2 秒 120 幀是 60 fps）：

| 狀態 | 每 2 秒的幀數 | 最長間隔 |
| --- | ---: | ---: |
| 開始畫面 | 120 | 16 ms |
| 600 倍，什麼都沒開 | 95–111 | 54–101 ms |
| 暫停 | 120 | 16 ms |
| 600 倍 | 102–108 | 47–67 ms |
| 600 倍，列車工具開著，15 列車 | 105–108 | 53–77 ms |
| **測試在點、在查詢的時候（各階段之間）** | **13–77** | **最長 3.9 s** |

另一次 run（[39084730913](https://github.com/a91453/railway-game-ios/actions/runs/39084730913)）的開始畫面，時鐘根本沒在走，主執行緒卻停了 24.8 s、3.8 s、6.2 s。
- 時間正好對上測試的一次 `Checking existence of "start.newGame"`：從 01:07:35 到 01:08:21，花了 46 s。
- 那次查詢時取得的畫面樹很小，大約 30 個元素（另一份失敗紀錄的 App UI hierarchy 只有 67 行）。

所以：
- 600 倍時，每個 tick 在模擬器的 Debug 建置裡大約讓主執行緒忙 50–100 ms（SwiftUI 跟著世界更新）。畫面維持 50 fps，遊戲時間跟得上。列車工具和 15 列車沒有多花。
- 大的卡頓都出在測試查詢的時候，連開始畫面都會。這是 XCTest 建無障礙快照的成本，不是遊戲的。

## 4. 沒有做的、之後可以做的

- App 沒有改：玩家（沒有 XCTest 在查詢）看到的是 50–60 fps，遊戲時間跟得上。
- **未驗證的缺口：VoiceOver**。
  - VoiceOver 也讀同一棵無障礙樹。XCTest 一次快照要好幾秒，VoiceOver 玩家在時鐘跑時可能一樣卡。
  - 沒有量：Linux 與 CI 的 UI 測試都量不到。
  - 下一版的 What to Test 請實機開 VoiceOver 跑 600 倍，看 HUD 的速度提醒（決策 195）和朗讀會不會延遲。
- 每個 tick 讓整個畫面重新計算（SwiftUI 觀察整個 `session.world`），是 Debug 模擬器裡 50–100 ms 的來源。真的要省，得把畫面讀的值切小，是大改，等實機量到不夠再做。
- 開始畫面查詢一次 46 s 的原因，從記錄看不出 App 在做什麼：畫面樹很小、時鐘沒走、資料早就讀完。可能是 CI 的模擬器本身慢，沒有追。

## 5. 高鐵示範的快轉（NEXT_PRIORITIES §16 第 4 項，分支 `claude/hsr-demo-speed`）

量法：高鐵示範開局（07:00，號誌關，出貨的設定）存成檔，Linux release 版 `GameSim` 改成臨時的量測程式（不提交），一個 tick 一個 tick 跑，記每個 tick 的時間，最後把世界存檔、算雜湊。`SWIFT_DETERMINISTIC_HASHING=1`，否則 JSON 的字典順序每次不同，雜湊對不起來。

callgrind（144 個 `.fast` tick，一天）：
- `advance` 裡 49% 在重算每條路線的整趟行程 `journey(of:service:direction:)`，大多從乘客轉乘的檢查來（`enqueueTransfer` → `isServed` → `isScheduled` → `lineJourney`）。每次 `advance` 的 `DispatchMemo` 會記住，但一次 `advance` 只走一個 tick，下一個 tick 又從頭算；一趟大約 1 億個指令（約 20 ms）。
- 改掉之後，下一個熱點是出庫：`runTrainLeavingDepot` 對每一站問一次 `runPullOut`，`runDepotTrips` 每列車只記一個答案，換一站就蓋掉重算（剩下的 23%）。

改法（結果逐位元不變，不升存檔、不改 golden、不取決策號）：
- `RouteMemo` 多記一份 `ServiceKey`：路網、路線（去掉發車時間，`withoutDispatchTimes`）、車站、車庫、彈性發車、靠左、寫實運轉、彎道限速、行車控制、服務日、列車與車長。只要這些沒變，下一次 `advance` 借用上一次算好的行程、容量、是否有班（`scheduledServices`）與出庫的空車（`runDepotTrips`）。
- `runDepotTrips` 改用（列車、位置、站）當鍵。

| 一週 `.fast`（1,008 個 tick，預算 100.8 s） | 中位數 | p90 | 最長 | 超過 100 ms | 總共 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 改之前 | 105.8 ms | 153.1 ms | 363.5 ms | 563 | 97.1 s |
| 只記行程 | 41.9 ms | 82.1 ms | 305.5 ms | 38 | 46.1 s |
| 再記出庫 | 38.7 ms | 60.6 ms | 284.6 ms | 16 | 36.3 s |

一天 `.normal`（288 個 tick）：5.9 s → 1.7 s。三種跑法改前改後的存檔雜湊都相同（一天 `.fast` `467851ce5ad12a46`、一週 `.fast` `30fca2e005bd01b5`、`.normal` `802c253e5e5000f9`）。

測試：`PassengerTransferTests.testTheServicesKeptBetweenAdvancesChangeNothing`（換服務日、班數、行車控制，和每次丟掉記憶的世界逐 tick 比，並檢查記住的答案等於現在算的；故意讓鍵不看服務日，這個測試會在第 50 步紅）、`RunDepotTests.testTheRunsOutOfTheDepotsKeptBetweenAdvancesChangeNothing`。

還沒做：最長的 tick（約 280 ms，零星）沒追；#669 的長進路死結與台南—左營交會（號誌開）也還沒開始。
