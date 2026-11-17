# ROAD-LOOK-REAL（決策 822）

- 派工單：ROAD-LOOK-REAL；session_01JMHz9bEFthgKRraGjXnPYN 做第 1–3 項（壓縮兩次後停下），session_01JMHz9bn8HzazZzMYbhURDh 接手做第 4–5 項、量測、看圖與文件；分支 `claude/road-look-real`，PR #2364。
- 存檔、golden、GameCore 都不動；只改 GamePresentation、它的測試與文件。

## 狀態：做完，等規劃看總覽

五項都做完，各有一個在 main 上會紅的測試（`RoadLookRealTests`，5 個）；內容、量測、三輪看圖與參考檢查在 `docs/decisions/822.md`。總覽圖 `docs/art/road-look-real-2026-11-17/overview.jpg`；五個角度的改前改後與作者的四張截圖在 a91453/railway-assets-private `game-art-previews/docs/art/road-look-real-2026-11-17/`。

忠孝橋一帶（半徑 1.3 km、每 2 m）：水面上的路面 2,040 → 288 m²；兩層路面相距 0.5–4.5 m 5,488 → 3,920 m²。

## 留給之後的（已打分，NEXT_PRIORITIES §29.29）

1. **ROAD-RAMP-HEIGHT**（3.15）：剩下的疊板多半是匝道橋併進主橋後整座站在主橋高度。移植 slop-taipei `build-elevated.mjs`（MIT）的 portal Dijkstra（坡度上限 6%），讓匝道在橋裡自己往下。熱點：(1100,0) 612、(−800,−400) 512、(−1300,0) 304、(−900,−600) 304、(−1000,−700) 296 m²。`levelRun` 的 150 m 上限試過 300 m：總面積 3,004 m²，但三重高架下的街在新的地方被抬起來，所以沒有採用。
2. **ROAD-STRIP-WEDGE**（2.65）：`addStrip` 在橋端與急彎前後各延伸半個路寬，橋端後面那一小塊沒有被抬高，成了斜的楔形；急彎的尖刺是同一個原因，還沒量。
3. **ELEVATED-BOUGHT-LOOK**（2.40）：香港、機捷的高架（買來的路線）沒拍。
4. **ROAD-OVER-WATER-REST**（1.95）：剩下 288 m² 是河岸的服務道路，路面 0.28 m、水面 0.25 m。
5. 實機（Metal）沒看過；只有 Linux 的量測與 WebGL 預覽。

## 重拍與量測

預覽：`cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift`，再照 `tools/map3d-preview/README.md` 拍。本 PR 用的場景（`MAP3D_FOCUS` 把場景原點放在忠孝橋一帶，本 PR 加進工具）：

```sh
MAP3D_WORLD=island MAP3D_AT=25.0478:121.5170 MAP3D_FOCUS=25.0495:121.5030 \
MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 \
MAP3D_NOBUILD=1 MAP3D_REAL=1 MAP3D_DAY=1 MAP3D_MINUTE=460 MAP3D_CROP=0:0:1100 \
MAP3D_VIEWS="top:0:0:1300:0;hj:-150:450:350:30;zx:350:-50:300:200;sc:-750:-450:320:0;river:0:0:700:300" \
MAP3D_DUMP=<dir>/r swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh <dir>/r <dir>/p views
```

量測探針（疊板與水面上的路面積、某一點的三角形與橋端）沒有提交；做法：對每個 chunk 的三角形，在格點上用重心座標插出高度，路面顏色（`Map3DPalette.road`）的高度排序後相鄰差 0.5–4.5 m 算疊板，最高的路面高出水面（`Map3DVertex.water` 層）不到 1 m 算水面上的路。

場景座標與經緯度：x = 100850·(lon − 121.5) − 302.55，z = −111321·(lat − 25.05) − 55.66。
