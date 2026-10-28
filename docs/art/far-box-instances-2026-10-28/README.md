# 遠景城市的方塊實例：前後圖（決策 455）

`overview.png`：台北車站新局，相機在 1,400 m 遠、方向 30°，用的是 App 的底圖、城市磚與真實輪廓（`MAP3D_DETAIL=far`）。左邊是 `main` e818ff4，右邊是本分支；上排 14:00，下排 20:30。

**這是 WebGL 預覽（`tools/map3d-preview`），不是 iPhone 的 Metal 畫面。** 本分支的圖由頁面照 `map3dBoxVertex` 的算式展開實例後畫出。

不同的像素（`diff.cjs`）：

| 鏡頭 | 14:00 | 20:30 |
| --- | --- | --- |
| 1,400 m | 0.01% | 0.21% |
| 3,000 m | 0.01% | 0.18% |

夜裡的差別來自決策 455 第一步：長方形輪廓遠看畫成方盒以後，夜窗亮的格子換了一組。同一個分支上，Swift 展開的頂點對照 shader 算式展開的實例，只差 1 個像素。

全尺寸的圖、兩個鏡頭和差異圖放在 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/far-box-instances-2026-10-28/revision-1/`。

重建方法：見 `tools/map3d-preview/README.md`。參數如下：

```sh
MAP3D_WORLD=taipei MAP3D_BASEMAP=1 MAP3D_CITY=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1
MAP3D_DETAIL=far MAP3D_MINUTE=840   # 20:30 時用 1230
MAP3D_CROP=0:0:3500
MAP3D_VIEWS="far1400:0:0:1400:30;far3000:0:0:3000:-40"
```

`main` 與本分支各跑一次，再用 `render.sh` 拍下 `*-shadows.png`。
