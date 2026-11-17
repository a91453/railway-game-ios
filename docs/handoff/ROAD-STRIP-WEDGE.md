# ROAD-STRIP-WEDGE（決策 822「後來（二）」）

- 派工：新專案協調者，總表 bug 第 3 名（2.65）；工作串「修正橋端楔形與尖刺」，分支 `claude/project-thread-tmgn4n`。
- 存檔、golden、GameCore、決策號都不動；只改 GamePresentation（`Map3DRealGround.swift` 的 `addStrip`、新的 `addStripJoin`）、新測試 `RoadStripJoinTests`、文件。

## 狀態：做完

內容、量測、參考檢查、五個角度在 `docs/decisions/822.md` 的「後來（二）」。總覽圖 `docs/art/road-strip-wedge-2026-11-18/overview.jpg`。

## 留給之後的

1. **ROAD-UNDER-GRASS**（bug，評分在 `docs/priorities/ROAD-STRIP-WEDGE.md`）：忠孝橋東邊甲板下（場景約 (455, 85)），一條地面路被草地蓋住：草地面 0.38 m、路面 0.32 m，路的中心線（0.38 m）和草地同高閃爍。原本被延伸出來的斜板擋住，所以沒人看到。
2. 兩條不同的路在同一點轉彎相接，兩邊仍各延伸半寬（路自己的端點要靠這半寬和別的路合起來），小角度有一點耳朵，沒量。要修得先知道哪些路在那點相接（`Map3DRoadJunctions` 有節點表）；作者參考庫 slop-taipei `js/taipei-ribbons.js` 的 `jointFramesFor`（MIT）就是這個：兩條路相接、方向差 30° 以內時共用端點的邊，三條以上保持方頭。
3. 實機（Metal）沒看過。

## 重拍與量測

場景與指令同 `docs/handoff/ROAD-LOOK-REAL.md`「重拍與量測」。三角形數量讀輸出的 `<前綴>.json` 的 `triangles`。
