# WINTER-LIVERY-2 交接（2026-11-16）

session_01JMHz9bvL9kMdQXnJy9h3VW，分支 `claude/winter-livery-2`，決策 806。存檔、golden、GameCore、fixtures、模型包的模型與雜湊：都不動。

## 做完的

- 三個方案加一格推薦的圖：`docs/art/winter-livery-2-2026-11-16/`（遊戲實際大小與放大，白天與夜晚），三輪看圖的紀錄在那裡的 README。
- 預覽匯出器 `tools/model-look/export-winter.sh options <資料夾>` 與拍圖腳本 `tools/model-look/shoot-livery.mjs`（遊戲不讀）。
- 推薦與五方理由在決策 806 §3；貼在 #2118 等作者選。

## 還沒做的

1. **等作者選**（規劃轉告）。選定前 `Map3DChristmasLivery` 與 main 相同。
2. **實作**：決策 806 §4 列了做法（雪頂用每頂點表、其餘另加實例、光暈上限、閃爍、遠景與方塊車、顏色對到已有的色）。路線頁開關、第 4 週任務、偏好紀錄沿用決策 795，不重做。匯出器裡 `Decoration` 的算法（沿側面找寬度、沿車頂找高度、貼帶子）可以搬進 `Sources/GamePresentation`，搬的時候把每段 0.2 m 改成 1 m、只畫單面。
3. 實作後要補的測試：每款跑的車的裝飾不浮空（離表面 ≤ 0.1 m）、不超出車的外框太多、三角形數在預算內、雪頂不動玻璃與燈。

## UNVERIFIED

- Metal、實機、效能、夜裡的光暈與閃爍；圖全部是離線 WebGL。
- 只看過一張真實照片（Commons 限流）。
