# ROAD-LAYER-HEIGHT（決策 822「後來（四）」）

- 派工：新專案協調者（`docs/priorities/ROAD-UNDER-VIADUCT.md` 兩列，一項一個 PR）。工作串「讓甲板橋照樓層分高度」，分支 `claude/project-thread-het49f`。
- 只改 GamePresentation（`Map3DRoadBridge.swift`）與 `RoadLookRealTests`；存檔、golden、GameCore、決策號都不動。

## 狀態

1. **ROAD-LAYER-HEIGHT 做完**：同一座甲板的橋照各自的 `layer`，只在相接、並排處抬高（`levelHeights(into:others:)`）。五個交流道的同高交叉 113 → 58、拉開一層以上 8 → 61；疊板面積多 5%（原因、量測、五個角度在決策 822「後來（四）」）。
2. **RAMP-EDGE-OVERLAP 做完**（#2420 之後的下一張，同一個分支）：引道在主線旁下坡時，被主線路面蓋住的那半邊不畫（`underHigherDeck`、`uncovered`）。五個交流道疊板 10,128 → 6,272 m²（決策 822「後來（五）」）。

## 留給之後的

- LAYER-LEVEL-CROSSING（1.85，`docs/priorities/ROAD-LAYER-HEIGHT.md`）：交流道糾結處較低的橋降不滿一層，照舊同高平交。
- 剩下的疊板散在各處，最大一格（100 m 方格）約 330 m²（五股 (−1200, −1300)、圓山 (−1500, 1100)），多半是較低層的橋端下坡經過旁邊的平面道路；沒有另外評分（單格太小）。
- 實機（Metal）沒看過；只有 Linux 的量測與 WebGL 預覽。

## 量測探針

沒有提交，做法同 `docs/handoff/ROAD-UNDER-VIADUCT.md`，另外：一個 XCTest 用 `MAP3D_WORLD=island` 那一套世界（`MAP3D_AT` 台北 25.0478:121.5170、高雄 22.6394:120.3024），`Map3DScene(world:focus:baseMap:heights:railways:)` 蓋整個場景，路面顏色的三角形每 2 m 一格量疊板；再用 `Map3DScene.Builder` 的 `bridgeDecks(of:frame:)`，對同一座甲板裡以 20° 以上交叉的每一對橋，在交點用 `pieceRise` 比兩邊的高度。五個地點的場景原點：忠孝橋 25.0495:121.5030、圓山 25.0735:121.5260、五股 25.0700:121.4560、鼎金 22.6620:120.3230、中正交流道 22.6260:120.3400。
