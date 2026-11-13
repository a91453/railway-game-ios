# DRIVE-STOP：手動駕駛的停車

- 派工：遊戲規劃第 63 任（#1579 留言 6835372702，背景 6819435373）。雲端 session_01YGNNuoRZ5PwYwZGgYfKjtr。
- 決策 710（`docs/decisions/710.md`）。

## PR 1（畫面）：`claude/drive-stop`

- 存檔、golden、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、GameCore 都不動。
- 做了：進站最後 200 m 的停車條（`ManualDrive.StopBar`、`Map3DStopBar.swift`，取代「前方停車」那一行的位置）；停車點的停車位置標（`ManualDrive.StopMark`，方塊，畫在列車那一層）；停妥後鏡頭換到「旁邊」8 秒再回去、成績卡留著（`ManualDrive.StopLook`）；標記進目標與越位的觸覺。
- 第三級截圖：`website-screenshots.yml`，`tests: testManualDriveStop`。**規劃看過圖才合。**
- UNVERIFIED：實機觸覺、iPad、淺色、大字級、VoiceOver 實際念法；「旁邊」視角固定在列車左側，島式月台時月台在車的另一側。

## PR 2（輔助停車＋看成績的鏡頭拉近）：`claude/drive-stop-assist`

- 派工：遊戲規劃第 64 任（#1579 留言 6841570600）。DRIVE-STOP-2，雲端 session_01YGNNummBUa5QE8kukAvvaZ，接 DRIVE-STOP 的 `ad1d3b5`。
- 決策 710「輔助停車」一節（沿用，不取新號）。**存檔版本 92**。golden schema、`GoldenScenarios/`、既有的 `SaveFixtures/` 與 `ReplayFixtures/` 都沒動；新增 `SaveFixtures/v92-assisted-run.json`。
- 做了：
  - 顯示層（DRIVE-STOP 寫的）：`ManualDrive.StopAssist`、`assistAsked()`、開關 `@AppStorage("manualDriveStopAssist")`（預設開，在駕駛時的視角選單）、停車條的「輔助中」、成績卡的「用了輔助停車」。
  - GameCore：`DrivenRun.assisted`（false 不寫出）；`DrivenRun.bonus(marks:riders:assisted:)` 用了輔助的一趟最多照 `assistedBonusMarks`（75 分）給，也就是滿分獎金的一半；`DrivingRecord.assisted`（停妥的趟數裡用了輔助的，0 不寫出），最高分 `best` 只算沒用輔助的；`DrivenRunSettlement.isCapped`。
  - `ManualDrive.Result.run(of:)` 把 `assisted` 帶進結算的指令；成績卡的獎金那一行在被封頂時多一句「不用輔助賺更多」。
  - 看成績的鏡頭拉近（PR 1 欠的）：`Map3DFollow.lookScale`、`ManualDrive.StopLook.scale`（0.45）；`Map3DMetalView.follow` 換視角時一起帶過去，玩家捏合的距離不變。
  - 輔助接手那一刻一下軟的觸覺（`.impact(flexibility: .soft)`）。
  - `WhatsNew` 129 的第一筆。
- 第三級截圖：`website-screenshots.yml`，`tests: testManualDriveStop testManualDriveStopAssist`：`drive-stop-look`、`drive-stop-back`（鏡頭拉近）、`drive-stop-assist`（輔助中）、`drive-stop-assist-menu`（選單裡的開關）、`drive-stop-assisted-result`（用了輔助的成績卡）。圖出來了：run 43367263085（前兩張）與 43373839425（後三張）的 `website-screenshots` artifact，總覽 `docs/art/drive-stop-2026-11-12/overview-assist.png`。**規劃看過圖才合。**
- 沒做的：
  - 帶 `assisted` 的 ReplayFixture：`ReplayFixtures/` 的指令是 GameCore 測試自己的 `ReplayCommand`，裡面沒有結算手動駕駛的指令（決策 693 也沒加），要加得先擴那一套；改由 `ManualDriveSessionTests.testAnAssistedRunIsSettledAsAssistedAndTheCardSaysSo` 用指令紀錄重播（`CommandLogReplay`）驗。
  - `.github/testflight-whats-new.md` 的 129：照決策 415 由規劃在發版前寫。
  - HEALTH-126 第 5.3 節的缺口（GameCore 不驗那一趟真的開了）照舊：`assisted` 也是顯示層報上來的。
- UNVERIFIED：實機觸覺、iPad、淺色、大字級、VoiceOver 實際念法；島式月台時「旁邊」看到的是車的外側（PR 1 就有的限制）。
