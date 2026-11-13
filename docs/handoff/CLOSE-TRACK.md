# CLOSE-TRACK：玩家手動封閉／開放一段軌道（決策 716）

- 派工：作者 2026-11-13 交辦（作者 Mac 的本機 session，由行車規則比較的 session 派出）。登記在 #2118。
- 分支 `claude/close-track`。決策 716、存檔版本 94；golden schema 不動，既有的 fixture 一個值都沒變。
- 來源：作者自己的桌面版鐵路模擬（私人，不在三個 repository 裡）。只照規則重寫，對照表在 `docs/decisions/716.md` 第 4 節。這是「以新版為底、把舊版規則一項一個 PR 搬過來」的第 1 項。

## 做了什麼（第一個 PR，只有 GameCore）

- `GameWorld.closeTrack(_:)`／`openTrack(_:)`、`closedTrack`、`isTrackClosed(_:)`、`trainUsing(_:)`（`Sources/GameCore/Railway/TrackClosure.swift`）。
- 封閉的邊記在 `RailwayNetwork.closedEdges`；尋路（`ServicePath.swift` 的 `networkPath`、`TrainRoute.swift` 的 `route(from:to:)`）不走；指令入口 `admit` 擋（`GameError.trackClosed`，中英文訊息、golden 的編解碼）。
- 存檔：網路的 `"closedEdges"`，有封閉才寫；`SaveFixtures/v94-closed-track.json`。
- 測試 `Tests/GameCoreTests/TrackClosureTests.swift`（12 個）。

## 第二個 PR：接進畫面（分支 `claude/close-track-ui`，疊在第一個上）

- 選取工具的軌道卡片多「封閉軌道／開放軌道」（`RailwayGameApp/Views/InspectorView.swift` 的 `TrackUpgradeControls`，識別碼 `inspector.track.close`、`inspector.track.open`、`inspector.track.closedNote`）。
- 一次封道岔到道岔的整段：`Sources/GamePresentation/TrackClosureSession.swift`（`canCloseSelectedTrack`、`isSelectedTrackClosed`、`toggleSelectedTrackClosure()`），指令 `PlayerCommand.Edit.closeTrack(edges:)`／`openTrack(edges:)`。
- 2D 地圖標示：`MapArt.swift` 的 `drawClosedTrack`。
- 測試 `Tests/GamePresentationTests/TrackClosureCardTests.swift`（3 個）。決策 716 第 9 節。

## 還留下什麼

1. 畫面的剩餘：3D 地圖沒有封閉標示；因為封閉而沒有路的列車，列車卡片上沒有寫原因（它們不在 `routeWaits()` 裡，要另外問）。
1a. **幹線上幾乎封不了**：高鐵示範地圖上，兩個道岔之間隨時有列車的路要經過，封閉每次都被拒絕。要好用需要「預約封閉」（決策 716 第 9 節末段），是規則的改動，還沒人做。
2. 大地圖（高鐵、整個臺灣）上封一段的行為沒有測（決策 716 第 8 節第 4 點）。
3. 作者排的後續，各自一個 PR、還沒開始：單線公平輪流 → 道岔扳轉動畫。
4. 與 #2122（存檔版本 93）誰先合，後合的那個要併 main 並解 `SavedGame.currentVersion`、版本說明、`SavedGameTests` 那一行、`SaveFixtures/README.md` 結尾的衝突（兩邊各加一段，版本取大的）。這個 PR 先合的話 main 會從 92 直接到 94；93 那一步本來就不用轉換。

## UNVERIFIED

- 只在 macOS（作者的 Mac，Xcode 的 Swift）跑過相關的測試類別；Linux 的完整 tier、iOS 建置由 CI 驗證。
- 模擬器（iPhone 18 Pro，高鐵示範地圖）上看過：軌道卡片有「封閉軌道」、按得到、被拒絕時出現訊息。封閉成功後的樣子（卡片的「已封閉」與「開放軌道」、地圖上的紅色虛線與打叉圓牌）沒有在模擬器上看到，因為那張地圖上每次都被拒絕；只有 GamePresentation 的測試證明狀態會變。
- 沒有 UI test；3D 地圖沒有標示。
