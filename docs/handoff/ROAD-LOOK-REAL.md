# ROAD-LOOK-REAL（決策 822）

- 派工單：ROAD-LOOK-REAL；session_01JMHz9bEFthgKRraGjXnPYN（第 2 次壓縮後依規則停下）；分支 `claude/road-look-real`。
- 存檔、golden、GameCore 都不動；只改 GamePresentation。

## 進度

做完的三個原因，各有一個在 main `003a1bf` 上會紅的測試（`RoadLookRealTests`）：

1. **水面上的尖三角（IMG_5325、IMG_5322）**：河的輪廓連同島（洞）先切到每格三角形再三角化，島碰到格邊時整個三角形變成水。改成整塊先三角化（Earcut），再逐格用半平面凸切（`Map3DRealGround.swift` `addArea`）。main 上島內 16 點被水蓋 → 0。
2. **水裡的灰色長條（IMG_5324）**：圖磚沒給地被的河中島（例：華江旁洞 4，21,869 m²）露出水下的地面。河與湖（不是海，`Area.isSea`，圖磚 class `ocean`）的島先鋪一層濕地色（`islandCover`、`islandLift` 0.0175）。main 上 6,547 點露地面 → 0。
3. **橋下水面的平面路（IMG_5324）**：華江橋的機車道在地圖上是另一座 `service` 橋，離快車道中線 11–13 m、邊緣相隔最多 4.6 m，兩端只差約 4 m。決策 391 只在橋端 1.5 m 內併橋，快車道越過下方道路升高，機車道留在水面。新增並排併橋（`Map3DRoadBridge.swift` `alongside` = 6 m：同層、平行 |cos| ≥ 0.9、每 10 m 取樣至少 4 次邊距 ≤ 6 m 就併成一座）。測試裡機車道 0.28 m → 6.2 m，和快車道差 ≤ 0.05 m。

已驗證（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`RoadLookRealTests`（3）、`Map3DRoadBridgeTests`（12）、`Map3DInterchangeStreetTests`（1）全綠。實景（忠孝橋一帶，見下面指令）俯視 raster：島緣不再有鋸齒三角；道路壓在水面的面積 2,040 → 280 m²（剩 (250,50) 88、(−150,450) 84、(450,−750) 56、(450,−850) 48 m²）。

## 還沒做（下一個 session）

1. **疊板（IMG_5323、IMG_5322 的 Z 字匝道、交流道互穿）**：兩層路面相距 0.5–4.5 m 的「打架」面積 5,488 m²（main）→ 5,720 m²（新增的 148 m² 在 (−150,450)，華江橋東端，是併橋後橋端坡道與地面路相接處）。熱點：
   - (−750,−450) 1,260 m²：三重的 trunk 橋（layer 3）甲板 24.36 m，下面一條 tertiary 單行地面路（2,932 m 長）被橋端坡道或 `roadRise` 抬到 21.5–22.4 m，在甲板下約 2 m。旁邊一條地面 trunk 匝道（ramp=1）從 (−653,−535) 到 (−794,−403)。
   - (350,−50) 884 m²（忠孝橋東端）：trunk 面 24.36 m 與 21.2–22.7 m 互疊。附近：trunk 橋 layer 3 (135,104)→(466,−114)、trunk 匝道橋 layer 3 (326,−12)→(357,−86)、trunk 地面路 (374,−119)→(343,−29)、trunk 橋 layer 4 (125,253)→(438,−437)。
   - 其他：(−1250,50) 528、(1050,50) 444、(−950,−650) 352、(350,−150) 348 m²。
   - 推測原因：地面路或匝道被橋端坡道、或並排甲板的 `roadRise`（半寬 + 0.5 m 內）抬了一部分，停在甲板下 1–3 m，看起來就是錯層的板。先在 (−757,−427) 用 `MAP3D_AT_XZ` 印出三角形與道路，判斷該把它整段壓回地面（離甲板夠遠），還是整段併進甲板。
2. **尖刺**（`addStrip` 的半寬延伸在急彎處）：還沒量。
3. **買來路線的高架**（香港、機捷）急彎與引道：規劃說好拍就拍，有問題只記數字與圖進 PR 和 NEXT_PRIORITIES，不在這張單修。
4. `docs/decisions/822.md`（`### 822. <title>`，`python3 -I tools/golden-checks/doc_numbers.py --check`）。
5. NEXT_PRIORITIES 新節：main 上最大節號 + 1（規劃說到 §29.25），大修（疊板若要重做匝道高度）寫五角度分數與加權分。
6. 至少三輪 model-look（概念影片角度與四張截圖並排），改前改後總覽 JPEG（品質約 85）放 a91453/railway-assets-private `game-art-previews/docs/art/road-look-real-2026-11-17/`（分支 + PR，先跑 `python3 tools/asset_guard.py --base origin/main`），本 PR 附一張總覽。第三級：規劃看過總覽才合併。
7. PR 對照表：tw3d 與 slop-taipei 道路畫法（MIT）、city_world `roadClearance`、MapLibre line join（BSD-3）、osm2streets（Apache-2.0，LICENSE 還沒讀）。
8. CI 綠了轉 ready，在 #2118 留言。

## 下一步的第一個指令

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
```

（上一個 session 在這份之上加了探針：`MAP3D_GEO`、`MAP3D_FOCUS`、`MAP3D_PROBE=1` 與其下的 `MAP3D_ROADPROBE=x:z:r:cell`（水面上的路面積、0.5–4.5 m 互疊、4.5 m 以上）、`MAP3D_AT_XZ=x:z`（印出該點的三角形）、`MAP3D_RASTER=x:z:r:cell`；scratchpad 已不在，要重寫。提交前刪掉這個檔。）忠孝橋場景：

```sh
MAP3D_WORLD=island MAP3D_AT=25.0478:121.5170 MAP3D_FOCUS=25.0495:121.5030 \
MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 \
MAP3D_NOBUILD=1 MAP3D_REAL=1 MAP3D_DAY=1 MAP3D_MINUTE=460 \
MAP3D_DUMP=<dir>/r MAP3D_CROP=0:0:10 MAP3D_VIEWS="top:0:0:1300:0" \
swift test --skip-build --filter Map3DPreviewDump
```

場景座標與經緯度：x = 100850·(lon − 121.5) − 302.55，z = −111321·(lat − 25.05) − 55.66。
