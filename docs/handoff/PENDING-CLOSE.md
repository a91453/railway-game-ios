# PENDING-CLOSE：預約封閉（決策 716 第 10 節）

- 派工：作者 2026-11-13（作者 Mac 的本機 session，由行車規則比較的 session 派出）。登記在 #2118。接 `docs/handoff/CLOSE-TRACK.md`。
- 分支 `claude/pending-close`，疊在 #2125（`claude/close-track-ui`）上，#2125 疊在 #2123 上。三個要照順序合：#2123 → #2125 → 這個。
- 存檔版本 95；決策沿用 716（第 10 節）；golden schema 不動，既有的 fixture 一個值都沒變。

## 做了什麼

- GameCore：`closeTrack(_: [TrackEdgeID])`（整組一起）、`closingTrack`、`isTrackClosing(_:)`、`closeTrackTrainsHaveLeft()`（`Sources/GameCore/Railway/TrackClosure.swift`）；封閉中的邊記在 `RailwayNetwork.closingEdges`；`advance` 每一步開頭與結尾把沒有列車在用的那一群變成封閉（`GameWorld.swift`）；尋路與 `admit` 把封閉中當封閉，只有從封閉中的軌道出發的例外。
- 存檔：網路的 `"closingEdges"`，有才寫；`SaveFixtures/v95-closing-track.json`。
- 畫面：軌道卡片的「列車通過後封閉」與「取消封閉」（識別碼 `inspector.track.closingNote`、`inspector.track.cancelClosing`）；`GameSession.selectedTrackClosure`；2D 地圖的封閉中標示（`MapArt.drawClosedTrack(closing:)`），和已封閉的標示一起改畫在路線顏色上面（`MapArt.drawTrackClosures`）：#2125 畫在軌道那一層，有路線的軌道上整個被色帶蓋住，高鐵示範地圖上看不到。
- 測試：`TrackClosureTests`（17 個）、`TrackClosureCardTests`（3 個）。改了哪些舊測試、為什麼，在決策 716 第 10.5 節。

## 還留下什麼

1. 決策 716 第 10.8 節的限制，最值得做的是第 1 點（整條線都在封閉範圍裡時封不起來）：可以在卡片上說明，或讓玩家選「讓裡面的列車停在下一站」。
2. 3D 地圖沒有封閉與封閉中的標示；沒有路的列車在列車卡片上沒有原因（CLOSE-TRACK 留下的）。
3. 沒有 UI test。模擬器（iPhone 18 Pro，高鐵示範地圖，雲林北邊的正線）手動看過一次：按「封閉軌道」→ 訊息與卡片「列車通過後封閉」、地圖琥珀圓點 → 放時間約一小時（遊戲內）→ 卡片「已封閉，列車不能通過」與「開放軌道」、地圖紅色虛線。開放與取消沒有在模擬器上按（測試有）。
4. 作者排的後續，各自一個 PR、還沒開始：單線公平輪流 → 道岔扳轉動畫。
5. 合併順序與衝突：#2122（存檔 93）若先合，#2123 要併 main 解 `SavedGame.currentVersion` 那幾處；這個分支跟著再併一次，版本留 95。
- 這個 session 已壓縮 1 次，不再接新工作。
