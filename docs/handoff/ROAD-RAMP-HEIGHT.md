# ROAD-RAMP-HEIGHT（決策 822 的「後來」）

- 派工：新專案遊戲規劃，優先總表第 1 名 bug（3.15）。session_01YGNNuqAVGFdQ1soQieYhVP，分支 `claude/project-thread-he18iy`。
- 只改 GamePresentation（`Map3DBaseMap.swift`、`Map3DRoadBridge.swift`、`Map3DRoadJunctions.swift`）與 `RoadLookRealTests`；存檔、golden、GameCore、決策號都不動。

## 狀態：做完

做法、量測與五個角度寫在 [決策 822](../decisions/822.md) 最後一節「後來」。忠孝橋一帶疊板 3,608 → 2,924 m²（同一支探針量 main）。

## 留給之後的

1. **做了**（ROAD-UNDER-VIADUCT，決策 822「後來（三）」，三重一帶 1,936 → 1,140 m²）：三重一帶還有約 1,500 m² 疊板（(−1300, 0)、(−1000, −700)、(−900, −600)、(−1300, 100)、(−1200, 0)、(−900, −700)），沒有逐一查。先看那裡的橋片是不是 `ramp`、是不是「並排併成一座」（決策 822 第 3 項）的平行橋，或高架下的街。
2. 匝道在主線路面裡、離開口端又不到「兩倍坡度能下到地面」的長度時，照舊從那裡往下，會貼著主線低一點；這種短匝道沒有量到熱點，先不處理。
3. **做了**（決策 822「後來（三）」第 1 項）：這次的高度只看端對端相接的匝道橋；匝道的端點接在另一座匝道橋的側邊時不算相接。
4. 一個區塊單獨蓋時，匝道開口端若在讀進來的範圍（區塊外 450 m）以外，那條匝道不限高，和整個場景蓋的不同；匝道一般在 450 m 以內接地，沒有量。
5. 實機（Metal）沒看過；只有 Linux 的量測。

## 量測探針

沒有提交。做法同 `docs/handoff/ROAD-LOOK-REAL.md`：`MAP3D_WORLD=island` 那一套世界（新局中心 25.0478, 121.5170，場景原點 25.0495, 121.5030，底圖＋高度檔＋全部真實鐵路），對每個分塊的 `mesh` 與 `close` 裡路面顏色（`Map3DPalette.road`）的三角形，每 2 m 一格用重心座標插出高度，同一格排序後相鄰差 0.5–4.5 m 算疊板，按 100 m 方格加總熱點。要看某一點的橋片，用 `Map3DBaseMap(tiles:frame:region:originX:originY:)` 讀那附近，`Map3DScene.Builder(originX:originY:region:world:)` 的 `bridgeDecks(of:frame:)` 印每片的 `isRamp`、`opens`、`ramp.samples` 與 `pieceRise`。
