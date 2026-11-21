# DRIVING-SPLIT：行車規則拆檔（五刀）

## 進度

五刀做完（決策 910 §1–§5）；剩下的是下面「還留下什麼」的兩件，都等有新工作時順便做。

## 做了什麼

- 派工單：DRIVING-SPLIT（assets-2 `docs/priorities/DRIVING-SPLIT.md`，#196；評估在 assets-2 `docs/planning/DRIVING-RULES-SPLIT-2026-11-20.md`）。工作串「拆分行車規則成模組」，分支 `claude/project-thread-oqz3d0`。
- 決策 910。存檔版本、golden schema、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 都不動（純搬家）。
- 第 1 刀 #2561：解死結的救援一步一檔＋順位表（`Sources/GameCore/Railway/DeadlockRescue/`，表檔 `merge=union`，加一步＝加一檔＋表一列）。
- 第 2 刀 #2567：`RouteReservation.swift` 依段落拆四檔。
- 第 3 刀：`GameWorld.swift` 的時間推進／派車／發車／行進拆成 `WorldAdvance`／`WorldDispatch`／`WorldDeparture`／`WorldMovement`。
- 第 4 刀：時刻表全日檢查的門檻一張地圖一檔（`Tests/GamePresentationTests/CheckupBudgets/`）。
- 第 5 刀：存檔版本說明一版一檔（`SaveFixtures/versions/<N>.md`，`SaveVersionNotesTests` 擋缺檔）；新功能狀態放自己小 struct 的規則（決策 910 §5）。
- 每刀：Linux 本機建置（`-warnings-as-errors`）＋ Replay／Golden／SavedGame 測試；CI 全層、手動 `ci.yml` 的時刻表全日檢查與 main 數字相同。

## 還留下什麼

1. **小 struct 的第一次示範**（決策 910 §5）：下一個要加 `GameWorld` 狀態的功能，把它的狀態放自己的 struct＋自己的 keyed container，並在那張 PR 加「每個 `SaveFixtures/` 存檔讀進再寫出，逐位元組和改之前相同」的測試。沒證明前不推廣，舊欄位不專程搬。
2. **其他可拆的熱點**（評估同一份文件；建議順序，由先到後，各自先照 §19 五方評分再派）：
   1. `WebsiteScreenshotTests` 與 `ScreenshotScene`：一個畫面一檔（加截圖的 PR 都改同一檔）。
   2. `Map3DScene` 的圖層：改成登錄表（評估 2.30），每層一檔、表 `merge=union`，做法同第 1 刀。
   3. `WhatsNew`：一版一檔（同第 5 刀的存檔說明）。
   4. `GameSession`：依職責拆（存讀檔、指令轉送、計時）。
   5. `Map3DPreviewScreen` 裡的 `differsOnlyInTrack`：搬出成自己的檔與測試。
   6. `RealLineAcquisition` 的 `offer`：依步驟拆函式（純搬家，要跑全日檢查）。
   7. `DataSourceCredits`：一張地圖一檔。
   8. 之後：`RouteNeeds.swift` 裡的 `counterflowRoute` 一段再搬出（第 2 刀後它仍有 1,600 多行）。

## UNVERIFIED

- 未在實機驗證：五刀都是純搬家，畫面沒有變化；iOS 模擬器建置交給 CI。
