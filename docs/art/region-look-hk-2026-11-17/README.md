# 香港的建物（REGION-LOOK-HK，決策 812）

`overview.jpg`：左是改之前（`main`），右是改之後。每列一個鏡頭，都是 `tools/map3d-preview` 的 WebGL 預覽（不是 Metal），上午 10 點，香港建物圖包與底圖：

| 列 | 位置 | 鏡頭 |
|---|---|---|
| Mong Kok | 22.3193, 114.1694 | 近景，距離 380 m、傾 35° |
| Mong Kok, close | 同上 | 近拍，170 m、35° |
| Central | 22.2819, 114.1582 | 近景，420 m、35° |
| Sha Tin | 22.3817, 114.1878 | 中景，900 m、30° |
| Kowloon, far | 22.3050, 114.1700 | 遠景（遠的細節），2,600 m、20° |

重拍：`MAP3D_WORLD=hongkong MAP3D_AT=<lat:lon> MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_MINUTE=600 MAP3D_VIEWS=<name:0:0:距離:傾角>`，其餘照 `tools/map3d-preview/README.md`。
