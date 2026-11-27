# DEBUG-153（2026-11-27）

- 派工：協調者（153 發版後例行的除錯，加上 full lane 連三晚紅）。雲端 Linux，分支 `claude/project-thread-depunj`。
- 範圍：152→153（`60a9c5f0..66497db25`，first-parent 47 個合併；`Sources/` 的 Swift +27,049／−512 行，大多是九州的模型網格與翻譯表）。
- GameCore、存檔版本、golden schema、決策號都不動。**沒有找到當機。** 修了一個玩家碰得到的教學 bug（最後一步的卡片會跳），和 iPad 教學測試的一個觸發點。

## full lane 連三晚紅：三晚是不同的原因

| 晚 | main | 紅的 | 結論 |
|---|---|---|---|
| 11-26 | `415a771`（run 45737940783） | `testTheFleetListScrollsFromADragOnACard`、`testTheTrackOptionsShowWhetherTheyAreOn`（Snap to track） | Snap to track 已由 #2760（`bab8b20`）修好，在 main。 |
| 11-26 | `f1da01c`（run 45805119006） | Snap to track 同上；iPad `testTheLineStepLeavesTheLinesPanelUsable` 紅一次、重跑過；`testTraditionalChineseTutorialNavigation` 超過 8 分 | iPad 見下面「iPad 變慢」。 |
| 11-27 | `d557284`（run 45924059254） | iPhone `testTheWholeTutorialOnAPhoneOnItsSide`：Finish 沒有可點的點；iPad job 在 80 分被取消 | iPhone 見下面「最後一步的卡片會跳」。iPad 的 log 因為被取消沒有留下（BlobNotFound）。 |

### 最後一步的卡片會跳（真的 bug，修了）

- 失敗錄影（xcresult 裡的影片）：手機橫拿、600 倍速，「等第一筆車資進帳」完成、Finish 亮著。車站 2 的車站卡開在右邊，教學卡片在左下（蓋著圖層鈕）。遊戲時間 07:11、07:30、08:00、08:25，卡片跳到畫面中間、壓在車站卡上，然後又跳回來。XCTest 的 Finish 位置在 (218.7, 324.1) 和 (423.7, 235.8) 之間來回，點下去的那一刻剛好在動，所以沒有可點的點。
- 原因：每個地方都會蓋到東西（左下蓋圖層鈕，中間蓋車站卡和它的一列）。車站卡的候車列隨乘客變多變少，那一列移進移出中間；移出時中間比較便宜，卡片就搬過去，移回來再搬回去。「卡片留在原地」只在打平時贏，所以擋不住。
- 修法（`TutorialCardPlacement.previousCost`）：卡片記住放下時蓋到多少，之後原地蓋到的沒有變多就不動；有新的東西跑到卡片底下（蓋到的變多）才照原來的規則重找位置。App 在卡片的位置變了時順便記下那裡的花費（`TutorialOverlay.swift` 的 `placed`）。
- Linux 測試：`TutorialCardPlacementTests.testTheCardStaysWhileItCoversNoMoreThanWhenPlaced`（車站卡的一列往下移：只看花費會跳，記得花費就不跳；一列移到卡片底下：會搬開）。

### iPad 變慢

- `f1da01c` 那晚 iPad job 有 17 次「Wait for com.apple.springboard to idle」等滿 60 秒（`App animations complete notification not received`），前一晚 0 次。`testTheLineStepLeavesTheLinesPanelUsable` 32 秒→315／252 秒，`testTheTutorialStartsWithoutADataLayer` 35→269 秒。
- 第一次是 `testLargeTextTutorialNavigation` 結束時：App 已經 `terminate`，才把方向轉回 Landscape Left，等於轉 iPad 的主畫面；之後每支測試的點擊都會等 60 秒。前一晚同樣的步驟沒事，所以是 Simulator 時好時壞，不是 App 的程式。
- 改：`checkNavigation` 的 `defer` 先轉回方向、再 `terminate`，不轉主畫面。只拿掉一個觸發點，UNVERIFIED（要看之後幾晚的 iPad job）。
- `d557284` 那晚 iPad job 跑了 81 分才被整個 job 的 80 分時限取消，測試那一步自己的 40 分時限沒有生效；log 沒留下，原因不明。下一次再發生，看那晚的 iPad log 是否也是 60 秒的等待。

### 「Warm up the app's first launch」的 5 分時限

- `continue-on-error: true`，到時只是警告，不會讓 job 紅；沒做完的暖機由第一支測試接著付。沒改。

## 550e1377 的 full lane（run 46018530736，16:35 UTC 仍紅）

- 收了：build job `ToolbarSmokeTests.testJapaneseThenTraditionalChineseGetsChinese` :29。不是 App 的 bug：這支是日文介面 #2815 以前寫的，那時沒有日文介面，日文優先要退到繁中。#2815 之後日文優先就該是日文（標題「鉄道ゲーム」）。改成兩支：`testKoreanThenTraditionalChineseGetsChinese`（App 沒有的語言排第一、繁中第二→繁中）、`testJapaneseThenTraditionalChineseGetsJapanese`。
- 沒收（這串壓縮過一次，照 CLAUDE.md 不接新工作，交回協調者）：second job `RealWorldMapUITests` 三項 :788（`realWorld.start`／`place.tra-taipei` 捲不到）、lessons job `Feature284To286UITests` 四項 :177、iPad `testLargeTextTutorialNavigation` :674（`dock.build` 點不到）。550e1377 早於 #2833（`9c0c5c4`），iPad 那項要先看 #2833 之後的 full lane 還紅不紅。紀錄在 assets-2 `docs/memory/post-release-log-2.md` 第 4 項。

## DEBUG 例行

1. **讀新增的程式找當機寫法**（強制解包、`try!`、`as!`、`fatalError`、`precondition`）：新的都安全。
   - `RouteNeeds` 的 `memo.foulingByEdge!`（上一行剛設）、`entry.holders.held[$0]!`（`held` 每台車都有一筆，`replace` 只換不刪）；`precondition(... matches ...)` 只在測試開了 `holderAudit` 時跑。
   - `LandLocation` 的 `factors[$0]!`：鍵來自同一個字典。
   - `Map3DFrontage` 的 `registry[key]![$0]`：`registryHouse` 找不到 `registry[key]` 就回 `nil`，不會走到。
   - `Map3DHongKongLandmarks`、`Map3DTrussBridges` 的 `models[...]!`：字典固定有 `true`、`false` 兩鍵，或上一行剛補上。
   - `Map3DStationLandmarks` 的 `body.map(\.x).min()!`：`corners` 固定四點。
   - `TranslationTable` 的 `words.first!`／`last!`：`words` 從 `[""]` 開始，只會變多。
2. **Xcode 警告**（`d557284` 的 build job log，排掉 `Accessing Environment` 與 `appintentsmetadataprocessor`）：**0 個**。`Accessing Environment<Bool>'s value outside of being installed on a View` 這個 job 76 次，DEBUG-146 已記。
3. **完整 `ci.yml`**：最近一次全綠是 11-27 的夜間 run 45920779013（`1ed26fd`）；之後的合併由各自的 push run 測過。沒有另外在 153 上手動跑（只花額度）。
4. **full lane**：`550e137`（153 加上 #2825）的手動 run 46018530736 由另一串跑，結果記在那邊。

## 給下一個做 DEBUG 的人

- 失敗的 UI 測試：xcresult 的 artifact 下載後，`Data/` 裡的檔是 zstd，解開後有 `.mov` 失敗錄影，用 `ffmpeg -vf "select='gte(t,96)',fps=4"` 抽格看。卡片「為什麼在那裡」看不到，要對照 `TutorialCardPlacement` 的花費自己算。
- iPad job 被取消時沒有 log（BlobNotFound），只能看別晚的。

## UNVERIFIED

- 卡片的修正在 App 裡的樣子（只在 Linux 測試驗過放置規則；Simulator 看這個 PR 的 iOS 檢查與之後的 full lane）。
- iPad 的修正：只拿掉一個觸發點，要看之後幾晚。
- 實機、Metal、聲音。
