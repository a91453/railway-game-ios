# ROAD-LOOK-REAL（決策 822）

## 進度

- 做到哪：水面兩個原因已修並有測試（`RoadLookRealTests`）：(1) 河的輪廓連同島（洞）先切到每格三角形再三角化，島碰到格邊時整個三角形變成水 → 改成整塊先三角化再逐格凸切；(2) 圖磚沒給地被的河中島露出水下的地面（灰色長條）→ 河與湖的島先鋪一層濕地色。接著查道路：平行路面互疊、匝道 Z 字、交流道穿插、橋下水面的平面路。
- 已驗證（Linux）：島測試在 main 上紅（島上 16 點被水蓋、6547 點露地面），修後 0；忠孝橋一帶實景場景的俯視 raster 島緣不再有鋸齒三角形。
- 下一步的第一個指令：`cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift`（scratchpad 版另有 MAP3D_PROBE／MAP3D_RASTER／MAP3D_AT_XZ 探針），量道路的疊板。

- 派工單：ROAD-LOOK-REAL；session_01JMHz9bEFthgKRraGjXnPYN；分支 `claude/road-look-real`。
- 存檔、golden、GameCore 都不動。
