# TRACK-CURVE-COLOUR＋TRACK-ALIGN：鋪軌預覽依限速上色、對齊既有軌道（決策 826）

## 進度

- 做到哪：程式、Linux 測試、截圖場景、決策與這個檔都在 `claude/track-curve-colour`；PR 開 draft，等 CI。
- 已驗證：Linux（Swift 6.4）`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`TrackPreviewMarksTests` 10 個、`ScreenshotScene` 相關類別、27 個鋪軌與預覽相關類別（276 個測試）0 失敗。
- 下一步：CI 綠後轉 ready，#2118 留「可合併、head <SHA>」。

## 派工

- 遊戲規劃 2026-11-17 派，NEXT_PRIORITIES §29.16 第 2、3 項（3.25、2.95）。session_01JMHz9ambminugTbRq1gqEq，分支 `claude/track-curve-colour`，登記在 #2118。
- 決策 826。GameCore、存檔版本、golden schema、replay 都不動。

## 做了什麼

- `Sources/GamePresentation/TrackPreviewMarks.swift`：預覽依 GameCore 的彎道限速（決策 217）分三段上色、最急半徑與最陡坡的位置與字；跟著預覽記住（`NetworkPreview.marks`）。
- `Sources/GamePresentation/TrackAlignment.swift`：拖出的自由終點 3° 內對齊（沿起點軌道直直延伸、附近軌道平行或垂直），虛線與放大鏡的字；沒對齊時寫轉幾度。
- `NetworkDrag.swift`（`dragNetwork` 裡對齊）、`NetworkSession.swift`（`NetworkOverlay` 多 `slowStretches`、`marks`、`guides`）、`GameSession.networkDragGuide`。
- App：`MapArt.swift` 畫上色段、虛線、標記膠囊；`MapView.swift` 放大鏡第二行與觸覺回饋。
- 截圖場景 `trackCurve`、`trackAlign`，`WebsiteScreenshotTests.testTrackCurveColour`（`track-curve-colour`、`track-curve-colour-en`、`track-align`）。
- 測試 `Tests/GamePresentationTests/TrackPreviewMarksTests.swift`。

## 還留下什麼

分數寫在 NEXT_PRIORITIES §29.16 第 12–14 列：

1. 3D 地圖的鋪軌預覽沒有上色與標記（3D 不畫網路工具的預覽疊圖）。
2. 已鋪好的軌道沒有「限速圖層」（整張圖依限速上色，看哪裡卡住車）。
3. 點兩下鋪軌（不拖）的終點不對齊，只有拖的才對齊。

## UNVERIFIED

- App 的程式（`MapArt`、`MapView`、UI test）只在 macOS CI 編譯；上色寬度、膠囊會不會壓到 ✓ ✕、觸覺回饋要截圖或實機看（Simulator 沒有觸覺）。
