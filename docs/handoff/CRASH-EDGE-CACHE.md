# CRASH-EDGE-CACHE（2026-11-13）

- 派工：作者直接交辦（貼了 0.6.0 (128) iPad 的 TestFlight 閃退報告，說「修」）。session_01JMHz9bSPeCrz7KpknGLx1J（雲端 Linux）。分支 `claude/dreamy-euler-q579qz`，PR #2159（draft）。
- 存檔版本、決策號、golden schema、fixtures：都沒動。GameCore 沒動。

## 閃退的原因

`TrackGeometry.stretch(from:to:)` 的前置條件（`end <= length`）不成立，從 `MapArt.drawNetwork` 畫月台那段進來。`MapView` 用軌道編號快取每條軌道的 `MapEdgeDrawing`，前提是「編號永不重用」；但復原把整個世界換回快照，編號計數跟著倒退，下一條新軌道拿到舊編號，快取還是舊軌道（較短）的幾何，月台範圍超出去。這是從堆疊與程式碼推出來的，沒有在裝置上重現。

## 做了什麼

- `Sources/GamePresentation/PolylineDetail.swift`：新 `TrackGeometry.follows(_:in:)`（長度、縱斷面、兩端節點位置都對得上才算同一條）。
- `RailwayGameApp/Views/MapView.swift`：快取的 `onChange` 只在 `MapEdgeDrawing.draws(edge, in: world)` 成立時沿用。
- `RailwayGameApp/Views/MapArt.swift`：六個取用快取的地方改成 `cached.drawing(of:)`（先比對軌道，不同就當場重算）；畫月台時幾何比月台短就不畫。
- `Tests/GamePresentationTests/UndoSessionTests.swift`：`testAnEdgeBuiltAfterUndoTakesTheIDButNotTheKeptGeometry`。

## 驗證

- VERIFIED（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`UndoSessionTests`、`PolylineDetailTests` 18 個通過。
- UNVERIFIED：`MapArt.swift`、`MapView.swift` 在 Linux 編不到，要看 #2159 的 `ios-build.yml`；實機沒有重現過閃退，也沒有在實機確認修好。

## 還留下什麼

- 等 #2159 的 CI：`Swift CI (gate)` 與 `Xcode build (iOS Simulator)`。App 兩個檔沒編過，若 Xcode 建置紅，多半是 `MapArt.swift` 新的 `extension [TrackEdgeID: MapEdgeDrawing]` 或 `MapView.swift` 的 `onChange` 閉包，照錯誤訊息修。綠了轉 ready，在 #2118 留「可合併、head」；合併由作者或規劃決定。
- 沒查的另一條路：載入另一個存檔或開新遊戲時 `MapView` 若沒有重建，快取同樣會留著舊世界的軌道。新的比對也擋得住這種情況，但沒有為它寫測試。
- 下一版實機：蓋軌道、復原、再蓋一條不同長度的並加月台，確認 2D 地圖不閃退、線畫在新位置。
