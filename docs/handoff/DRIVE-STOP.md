# DRIVE-STOP：手動駕駛的停車

- 派工：遊戲規劃第 63 任（#1579 留言 6835372702，背景 6819435373）。雲端 session_01YGNNuoRZ5PwYwZGgYfKjtr。
- 決策 710（`docs/decisions/710.md`）。

## PR 1（畫面）：`claude/drive-stop`

- 存檔、golden、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、GameCore 都不動。
- 做了：進站最後 200 m 的停車條（`ManualDrive.StopBar`、`Map3DStopBar.swift`，取代「前方停車」那一行的位置）；停車點的停車位置標（`ManualDrive.StopMark`，方塊，畫在列車那一層）；停妥後鏡頭換到「旁邊」8 秒再回去、成績卡留著（`ManualDrive.StopLook`）；標記進目標與越位的觸覺。
- 第三級截圖：`website-screenshots.yml`，`tests: testManualDriveStop`。**規劃看過圖才合。**
- UNVERIFIED：實機觸覺、iPad、淺色、大字級、VoiceOver 實際念法；「旁邊」視角固定在列車左側，島式月台時月台在車的另一側。

## PR 2（輔助停車）：還沒開始，等規劃決定

獎金與評分在 GameCore（決策 693：`DrivenRun.marks`、`DrivenRun.bonus`、`GameWorld.settleDrivenRun`，走指令紀錄與重播）。`DrivenRun` 沒有「用了輔助」的欄位，所以「用了輔助獎金有上限」不改 GameCore 做不到。已在 #1579（留言 6835432186）與 send_message 向規劃說明，建議的做法：

1. `DrivenRun` 加可省略的 `assisted`（預設 false、false 不寫出）；世界在 `assisted` 時把獎金封頂。舊存檔、舊指令紀錄、現有 fixtures 與 golden 不變；新版寫出的指令紀錄舊版不認得，要不要升存檔版本由規劃定。
2. 開關放 `@AppStorage`（不進存檔），預設開。
3. 輔助的做法（還沒寫）：開著時，進到停車條的範圍、玩家已把速度降到合理值後，由程式接手最後一段的煞車段位把車頭停進目標；玩家太快衝進來就不接手。寫進決策 710 的後續。
4. 用 economy-balance 量改前改後（每趟獎金、一天能賺多少、會不會變成刷錢），數字寫進決策 710。`DrivenRunBonusReportTests` 是現成的報告測試。

接手的人：先看規劃在 #1579 的回覆。
