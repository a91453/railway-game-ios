# DRIVE-STOP：手動駕駛的停車

- 派工：遊戲規劃第 63 任（#1579 留言 6835372702，背景 6819435373）。雲端 session_01YGNNuoRZ5PwYwZGgYfKjtr。
- 決策 710（`docs/decisions/710.md`）。

## PR 1（畫面）：`claude/drive-stop`

- 存檔、golden、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、GameCore 都不動。
- 做了：進站最後 200 m 的停車條（`ManualDrive.StopBar`、`Map3DStopBar.swift`，取代「前方停車」那一行的位置）；停車點的停車位置標（`ManualDrive.StopMark`，方塊，畫在列車那一層）；停妥後鏡頭換到「旁邊」8 秒再回去、成績卡留著（`ManualDrive.StopLook`）；標記進目標與越位的觸覺。
- 第三級截圖：`website-screenshots.yml`，`tests: testManualDriveStop`。**規劃看過圖才合。**
- UNVERIFIED：實機觸覺、iPad、淺色、大字級、VoiceOver 實際念法；「旁邊」視角固定在列車左側，島式月台時月台在車的另一側。

## PR 2（輔助停車）：`claude/drive-stop-assist`，顯示層寫好，獎金上限等規劃

DRIVE-STOP 已壓縮 1 次（#1579 留言 6836133336），不再接新工作；這一段是交接。

**寫好的（疊在 `claude/drive-stop` 上，只動 GamePresentation 與 App）：**

- `ManualDrive.StopAssist`、`ManualDrive.assistAsked()`（`ManualDriveStop.swift`）：開著時，停車條的範圍內（200 m）、把手在空檔或煞車、不是緊急煞車、要停進目標所需的減速度在時刻表煞車的 0.6–1.0 倍之間，程式接手煞車；接手後最多用到 1.4 倍，所需減速度掉到 0.3 倍以下就滑行，停在目標內（測試量到約 3 cm）。玩家推回動力段就交還。太快衝進來（所需超過 1.0 倍）不接手。
- `ManualDrive.Result.assisted`、`Reading.isAssisting`；成績卡多一行「用了輔助停車」；停車條在輔助時左邊寫「輔助中」，VoiceOver 的值加一句。
- `GameSession.startManualDrive(assist:)`、`setManualDriveAssist(_:)`；開關是 `@AppStorage("manualDriveStopAssist")`，預設開，在駕駛時的視角選單裡（`Map3DDriveHeading.viewMenu`），不進存檔。
- VERIFIED（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`ManualDriveStopTests`（11）、`ManualDriveSessionTests`（14）、`ManualDriveTests`、`ReviewL19FixTests`。UNVERIFIED：App 的建置（要 macOS CI）、截圖。

**還沒做的：**

1. **獎金上限、沒有「無輔助」加分**：獎金與評分在 GameCore（決策 693：`DrivenRun.marks`、`DrivenRun.bonus`、`GameWorld.settleDrivenRun`，走指令紀錄與重播）。`DrivenRun` 沒有「用了輔助」的欄位，不改 GameCore 做不到。已在 #1579（留言 6835432186）與 send_message 問規劃，**還沒回覆**。建議：`DrivenRun` 加可省略的 `assisted`（預設 false、false 不寫出），世界在 `assisted` 時把獎金封頂；舊存檔、舊指令紀錄、現有 fixtures 與 golden 不變；新版寫出的指令紀錄舊版不認得，要不要升存檔版本（下一個是 92）由規劃定。現在 `Result.assisted` 只到成績卡，沒有送進 `settleDrivenRun`，所以**現在這個分支上用輔助也拿全額獎金，不能就這樣合**。
2. economy-balance 量改前改後（每趟獎金、一天能賺多少、會不會變成刷錢），數字寫進決策 710。`DrivenRunBonusReportTests`（`DRIVEN_RUN_REPORT=tymc:A`）是現成的報告測試。
3. 決策 710 加輔助停車的一節（五個角度、沒選的、上面那幾個倍數的理由）；現在只在「下一步」提到。
4. 截圖（第二級或第三級：選單多一列＋停車條的「輔助中」）：`testManualDriveStop` 加一張輔助中的圖；`-screenshot-drive-stand` 的假畫面目前不帶輔助。
5. 回饋稽核：輔助接手的那一刻目前只有停車條的字換成「輔助中」，沒有觸覺；要不要加一下輕的由接手的人照 ui-review 判。

接手的人：先看規劃在 #1579 對留言 6835432186 的回覆。
