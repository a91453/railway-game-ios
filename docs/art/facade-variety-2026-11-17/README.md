# 高樓的立面（FACADE-VARIETY，決策 817）

`overview.jpg`：左是改之前（分支起點的 `main`），右是改之後。每列一個鏡頭，都是 `tools/map3d-preview` 的 WebGL 預覽（不是 Metal），遊戲鏡頭（傾角由距離決定），真實建物圖包與底圖：

| 列 | 位置 | 鏡頭 |
|---|---|---|
| xb close | 新板特區 25.0125, 121.4668 | 近拍，距離 170 m、方位 30° |
| xb near | 同上 | 近景，280 m、方位 210° |
| mk close | 旺角 22.3193, 114.1694 | 近拍，170 m、30° |
| mk near | 同上 | 近景，280 m、210° |
| hkn night | 中環（香港的預設中心） | 20:30，900 m、20° |

`layers.png`：五個新圖層（`Map3DSurfaces.png` 第 24–28 層）的顏色半邊，`tools/map3d-facades/layers.py` 畫的。

重拍：`MAP3D_WORLD=island`（或 `hongkong`）`MAP3D_AT=<lat:lon> MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_CROP=0:0:700 MAP3D_VIEWS="close:0:0:170:30;near:0:0:280:210"`，夜間加 `MAP3D_MINUTE=1230`；其餘照 `tools/map3d-preview/README.md`。傾印現在也寫出決策 610 與 817 的近景立面（`chunk.facade`）與它的三角形數（`facadeTriangles`）。
