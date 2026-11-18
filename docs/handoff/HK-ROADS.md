# HK-ROADS（決策 391「後來（HK-ROADS）」）

- 派工：協調者（作者 2026-11-18「香港路歪七扭八沒有修」「青馬大橋都在海底了」「青馬大橋上面啊 閘道都超怪的」）。工作串「修香港道路歪七扭八」，分支 `claude/project-thread-vmqfmt`。
- 只改 GamePresentation（`Map3DRoadBridge.swift`）、`Map3DRoadBridgeTests`、`tools/map3d-preview`；存檔、golden、GameCore、決策號都不動。

## 狀態：青馬大橋與兩端交流道做完

買下機場快綫或東涌綫後整座橋與兩端匝道被壓平的兩個原因、改法、測試與五方在 `docs/decisions/391.md` 最後一節。對照圖 `docs/art/hk-roads-2026-11-18/overview.jpg`。

## 留給之後的（評分在私有庫 `docs/priorities/HK-ROADS.md`）

1. **香港的路側傾**：照決策 737 的 `measure.py` 改讀香港地圖包量（腳本沒有提交：把兩個檔名換成 `MapPacks/hongkong/heights.dat`、`basemap.pmtiles`，經度基準 121 換 114）。縱坡 95 百分位：港島北 secondary 17.5%、九龍 trunk 12.3%、荃灣青衣 motorway 13.8%（台北各級 4.7–4.9%）；路面左右高差 95 百分位 3–8 m（台北 0.4–0.9 m）。原因是香港的地形是真的陡，加上 58 m 一格的高度在海邊從陸地直接斜到海面。要治本得沿路把地面切成路床（決策 834 只做了國道的縱斷面）。
2. 青馬大橋沒有塔與懸索，公路的墩和鐵路的墩各站各的（`docs/handoff/HK-LANDMARKS.md` 第 4 項）。
3. 汲水門橋、汀九橋、昂船洲橋、深圳灣公路大橋與台北、高雄沒有逐一重拍。
4. 實機（Metal）沒看過。

## 重拍

`tools/map3d-preview` 這次加了三件：香港、羅瓦涅米的 `MAP3D_HEIGHTS`／`MAP3D_LANDCOVER` 讀地圖包自己的檔；`MAP3D_REAL=1` 在這兩張地圖上連地圖包的鐵路一起讀；`MAP3D_VIEWS` 第七欄是鏡頭傾角（度，從正上方算起）。

```sh
MAP3D_WORLD=hongkong MAP3D_AT=22.3513:114.0740 MAP3D_BUY=hkmtr:TCL MAP3D_REAL=1 \
MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 MAP3D_DAY=1 MAP3D_MINUTE=600 \
MAP3D_CROP=0:0:1600 MAP3D_VIEWS="end:700:-250:500:70:10:70;low:0:0:300:20:5:80;w1:-1500:380:700:250:10:55" \
MAP3D_DUMP=<dir>/a swift test --skip-build --filter Map3DPreviewDump
```
