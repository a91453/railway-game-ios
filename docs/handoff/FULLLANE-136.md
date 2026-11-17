# FULLLANE-136：136 full lane 唯一的紅（橫拿教學卡在第 8 步）

## 進度（收尾）

- 做了什麼：查出 136 full lane 的紅是系統取消了第 8 步那一下地圖點擊（不是 #2325、玩家不會卡）；測試的放車站點擊沒前進就再點一次。PR #2341。
- 已驗證：`ios-build.yml` 的 `only_testing=TutorialJourneyUITests`（run 44020758876，`d5cf85d`）通過，`testTheWholeTutorialOnAPhoneOnItsSide` 102 秒；這次沒有用到重點（log 沒有 "tapping once more"）。PR 的 Swift CI (gate) 與 Xcode build 綠。
- 剩下：無。下一次 full lane 確認仍綠即可。

## 派工

- 派工：遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed（#2118，2026-11-17），bug。
- session：session_01JMHz9Y9jwMxA4MmWcauuiE（雲端），分支 `claude/fulllane-136`。
- 號碼：決策、存檔、golden 都不動。

## 判斷：測試的問題，玩家不會卡住，也不是 #2325

- 紅的：`TutorialJourneyUITests/testTheWholeTutorialOnAPhoneOnItsSide`（build 組的 UI smoke），main `19f3cc58`，run 43998599964：「Stuck after step 8 … step 9 never came. Folded card at (346.7, 315.0, 362.7, 44.0)」。
- 測試在第 8 步點了地圖 (352.8, 274)。App 的 trace（`ui-smoke-trace`）記到 `02:56:38.435 touch began at (352, 274) view MapGestureView`，接著 `02:56:38.614 touch cancelled`：系統把這次觸控取消了，App 沒有收到點擊，所以第二站沒有放下。整份 trace 546 次觸控只有 3 次取消，前後幾秒的畫面更新都正常（最長間隔 150 ms）。
- xcresult 的錄影：第一站已經蓋好，畫面上方是「Built station」的通知，折起的教學卡在 y 315–359。點的那一點 (352, 274) 上面什麼都沒有。訊息裡的「Folded card at …」只是 `onScreen()` 描述當時畫面，不是說卡片蓋住了那一點。
- 這次觸控根本沒進 App，所以和 #2325 改的 ✕ ✓ 擺法無關；而且那時第一站的 ✓ 膠囊已經收起來了。玩家碰到被取消的觸控，再點一次就好，教學不會卡住。

## 修法

- `TutorialJourney.tap(_:movingOnTo:)`：第 6、8 步放車站的地圖點擊，10 秒內步驟沒前進、還停在同一步、那一點也沒被卡片蓋住，就再點一次，並在 log 印一行。點到了步驟就會前進，所以不會多點。這和 `TutorialUITests`、`HUDAlignmentUITests`、`MapInteractionTests` 處理取消觸控的方式一樣。
- 沒有跳過或放寬任何斷言。第二次也沒點到，照樣紅在同一個訊息。
- 鋪軌的兩點（第 3 步）沒改：起點被取消時，終點那一下會變成起點，再點一次終點反而錯。真的發生時再看。

## 驗證

- VERIFIED（macOS CI）：`ios-build.yml` 的 `only_testing=TutorialJourneyUITests`，run 44020758876，手機橫拿那支通過（102 秒），iPad 那支照規則略過。
- UNVERIFIED：實機沒看（不需要：畫面沒改）。
