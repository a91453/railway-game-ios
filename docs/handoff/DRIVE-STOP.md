# DRIVE-STOP：手動駕駛的停車

- 派工：遊戲規劃第 63 任（#1579 留言 6835372702，背景 6819435373）。雲端 session_01YGNNuoRZ5PwYwZGgYfKjtr。
- 決策 710（`docs/decisions/710.md`）。

## PR 1（畫面）：`claude/drive-stop`

- 存檔、golden、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、GameCore 都不動。
- 做了：進站最後 200 m 的停車條（`ManualDrive.StopBar`、`Map3DStopBar.swift`，取代「前方停車」那一行的位置）；停車點的停車位置標（`ManualDrive.StopMark`，方塊，畫在列車那一層）；停妥後鏡頭換到「旁邊」8 秒再回去、成績卡留著（`ManualDrive.StopLook`）；標記進目標與越位的觸覺。
- 第三級截圖：`website-screenshots.yml`，`tests: testManualDriveStop`。**規劃看過圖才合。**
- UNVERIFIED：實機觸覺、iPad、淺色、大字級、VoiceOver 實際念法；「旁邊」視角固定在列車左側，島式月台時月台在車的另一側。

### PR 1 還欠的一件：看成績的鏡頭拉近（規劃第 63 任，2026-11-12 看圖後）

停穩後從旁邊看成績那一下，列車大約佔畫面寬的六成（現在約三成半），成績卡不要蓋到車；**只改這個鏡頭的距離，不動既有的「旁邊」跟隨視角**。DRIVE-STOP 沒做（已壓縮 1 次；要動別的 session 正在改的 `Map3DMetalView.swift`）。

- 距離是 `Map3DFollow.scale`（`Map3DFollow.swift`，`.side` 的鏡頭位置乘上它；範圍 `Map3DFollow.scales` 0.4…4）。照現在的圖估，`scale` 約 0.55–0.6 會到六成。
- 卡住的地方：`Map3DMetalView.follow(_:reduceMotion:)` 在同一班車換視角時只換 `view` 與 `lookout`，**保留畫面自己的 `scale`**（玩家捏合的距離），所以從 `Map3DPreviewScreen.followed(ambient:)` 傳進去的 `scale` 沒有用。
- 建議：`ManualDrive.StopLook` 加一個 `scale` 常數（GamePresentation，可測）；`Map3DFollow` 加一個可省略的「這次看的距離」（例如 `lookScale: Float?`，不為 nil 時 `.side` 的 `k` 用它、不用 `scale`），`follow(_:reduceMotion:)` 換視角時把它一起帶過去。這樣玩家捏合的距離不會被蓋掉，8 秒後回去還是原來的。`Map3DMetalView.swift` 只多一行；動之前在 #1579 看 PERF-FAR（#2098）合了沒。
- 驗收：`website-screenshots.yml`，`tests: testManualDriveStop`，看 `drive-stop-look`（列車約六成寬、卡不蓋車）與 `drive-stop-back`（按鈕寫「好」）。

## PR 2（輔助停車）：`claude/drive-stop-assist`，顯示層寫好，獎金上限等規劃

DRIVE-STOP 已壓縮 1 次（#1579 留言 6836133336），不再接新工作；這一段是交接。

**寫好的（疊在 `claude/drive-stop` 上，只動 GamePresentation 與 App）：**

- `ManualDrive.StopAssist`、`ManualDrive.assistAsked()`（`ManualDriveStop.swift`）：開著時，停車條的範圍內（200 m）、把手在空檔或煞車、不是緊急煞車、要停進目標所需的減速度在時刻表煞車的 0.6–1.0 倍之間，程式接手煞車；接手後最多用到 1.4 倍，所需減速度掉到 0.3 倍以下就滑行，停在目標內（測試量到約 3 cm）。玩家推回動力段就交還。太快衝進來（所需超過 1.0 倍）不接手。
- `ManualDrive.Result.assisted`、`Reading.isAssisting`；成績卡多一行「用了輔助停車」；停車條在輔助時左邊寫「輔助中」，VoiceOver 的值加一句。
- `GameSession.startManualDrive(assist:)`、`setManualDriveAssist(_:)`；開關是 `@AppStorage("manualDriveStopAssist")`，預設開，在駕駛時的視角選單裡（`Map3DDriveHeading.viewMenu`），不進存檔。
- VERIFIED（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`ManualDriveStopTests`（11）、`ManualDriveSessionTests`（14）、`ManualDriveTests`、`ReviewL19FixTests`。UNVERIFIED：App 的建置（要 macOS CI）、截圖。

**還沒做的：**

1. **獎金上限、沒有「無輔助」加分**（GameCore）。**規劃已決定**（#1579 留言 6835443671，2026-11-12）：
   - 可以動 GameCore：`DrivenRun`（`Sources/GameCore/Railway/DrivenRun.swift`）加可省略的 `assisted`（預設 false、false 不寫出）；`GameWorld.settleDrivenRun` 在 `assisted` 時不給無輔助加分、獎金封頂。不要在 GamePresentation 假報成績來繞。
   - **存檔版本 92 保留給這件事**（照 #2088 加 `coachStops` 升 91 的前例）：加遷移步驟與 `SaveFixtures/v92-*.json`。既有的 `SaveFixtures/`、`ReplayFixtures/`、golden **一個值都不能變**，變了就停下來報；需要的話新增一份帶 `assisted` 的 ReplayFixture。golden schema 不動（要動先問規劃）。
   - 開關放 `@AppStorage`、不進存檔（已照做）。
   - 封頂的數字用 economy-balance 量了再定，寫進決策 710，五個角度各一行。
   - 這是 GameCore 的 PR（完整 tier）：開之前看當時有沒有超過 2 個 GameCore PR 在跑 CI。PR 1（#2102）先給規劃看圖。
   - 現況：`Result.assisted` 只到成績卡，還沒送進 `settleDrivenRun`（`ManualDriveSession.swift` 組 `DrivenRun` 的地方要帶上），所以**這個分支上用輔助仍拿全額獎金，不能就這樣合**。
2. economy-balance 量改前改後（每趟獎金、一天能賺多少、會不會變成刷錢），數字寫進決策 710。`DrivenRunBonusReportTests`（`DRIVEN_RUN_REPORT=tymc:A`）是現成的報告測試。
3. 決策 710 加輔助停車的一節（五個角度、沒選的、上面那幾個倍數的理由）；現在只在「下一步」提到。
4. 截圖（第二級或第三級：選單多一列＋停車條的「輔助中」）：`testManualDriveStop` 加一張輔助中的圖；`-screenshot-drive-stand` 的假畫面目前不帶輔助。
5. 回饋稽核：輔助接手的那一刻目前只有停車條的字換成「輔助中」，沒有觸覺；要不要加一下輕的由接手的人照 ui-review 判。

DRIVE-STOP 不再做 PR 2（已壓縮 1 次）；規劃另派人接。接手的人從 `claude/drive-stop-assist` 接著做（還沒開 PR），PR 1 若有再改，先把 `claude/drive-stop` 合進來。
