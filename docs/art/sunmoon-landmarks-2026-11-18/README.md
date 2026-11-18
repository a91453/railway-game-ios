# 日月潭地標（決策 879）

`overview.jpg`：上三排是改前、改後（水社碼頭的遊戲鏡頭、水社岸邊、文武廟），下三排是改後的近看。預覽工具（`tools/map3d-preview/`）畫的，不是實機截圖。

怎麼重拍（`Map3DPreviewDump`，共同的環境變數 `MAP3D_WORLD=island MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 MAP3D_CROP=0:0:500`）：

- 碼頭：`MAP3D_AT=23.864247:120.911915`，`MAP3D_VIEWS=pier:-25:-25:95:320:749:60;boats:5:10:40:300:749:62;shore:-30:20:260:330:748:60;game:-30:0:420:0:748;pav:-81:44:40:300:749:60`
- 文武廟：`MAP3D_AT=23.869939:120.927681`，`MAP3D_VIEWS=temple:0:0:120:57:828:62;side:0:0:130:330:828:60;wide:0:0:300:57:828:55;game:0:0:420:0:828`

模型是作者舊版日月潭場景的（參考庫 `OpenWorld/reference_snapshot/play/assets/sunmoon/`）；位置來自 OpenStreetMap（ODbL）。
