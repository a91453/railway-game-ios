# ROAD-UNDER-VIADUCT（決策 822「後來（三）」）

- 派工：新專案協調者（`docs/handoff/ROAD-RAMP-HEIGHT.md` 留下第 1 項「三重一帶疊板」，與 `docs/priorities/ROAD-STRIP-WEDGE.md` 的 ROAD-UNDER-GRASS）。工作串「修高架下道路與三重疊板」，分支 `claude/project-thread-3nyvwl`。
- 只改 GamePresentation（`Map3DRoadBridge.swift`）與 `RoadLookRealTests`；存檔、golden、GameCore、決策號都不動。

## 狀態：做完

- ROAD-UNDER-GRASS 重量後不存在（霧與陰影看錯），三處文件已更正，不改程式。
- 三重：較低層的引道與側邊相接的匝道在橋內自己下到地面，主線底下的街回到地面。疊板 3,032 → 2,332 m²，三重一帶 1,936 → 1,140。做法、量測、五個角度在決策 822「後來（三）」；總覽圖 `docs/art/road-under-viaduct-2026-11-18/overview.jpg`。

## 留給之後的（評分 `docs/priorities/ROAD-UNDER-VIADUCT.md`）

1. 同一座甲板的橋照各自的 `layer` 分高度。現在整片高架一律照最高的 `layer`（三重、忠孝橋一帶 24 m），忠孝橋本身是 `layer` 1；所以較低的橋在高架底下穿過時（忠孝橋東端穿過市民大道高架）只能保持同高，本次刻意不讓它下坡。
2. 引道在主線旁 6–8 m 剛開始下坡的 30–40 m，邊緣在主線路面下方：(−800, −600) 208、(−700, −600) 116、(−300, 600) 96 m²。
3. 實機（Metal）沒看過。

## 量測

探針沒有提交，做法同 `docs/handoff/ROAD-RAMP-HEIGHT.md`。看某一點的橋片：`Map3DBaseMap(tiles:frame:region:originX:originY:)` 用 `Map3DScene(world:focus:)` 的 `region`、`originX`、`originY` 讀底圖，`Map3DScene.Builder(originX:originY:region:world:heights:)` 先 `addGround(water: false)` 再 `bridgeDecks(of:frame:)`，印每片的 `isRamp`、`opens`、`ramp` 與 `pieceRise`，以及 `ends` 的 `rise`、`plateau`、`roads`。
