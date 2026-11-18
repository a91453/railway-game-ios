# 淡江大橋的橋塔與斜拉索（決策 873）

`overview.jpg`：左邊是改前（`main` 加 #2468），右邊是改後，同一個鏡頭。由上到下：側面全景、遊戲鏡頭（520 m）、橋塔近看、遊戲大小（1,300 m，手機畫面的大小）。

- 重建：這個 PR 的 commit，`tools/map3d-preview`（`MAP3D_WORLD=island MAP3D_AT=25.1754:121.4178 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 MAP3D_CROP=-50:150:1300`，鏡頭 `side:-50:150:1100:285:60:72;game:-30:120:520:300;mast:0:0:330:300:60:68;small:-30:120:1300:300`）。改前的圖是把 `Map3DSuspensionBridge.all` 改回只有青馬再拍的。
- 形狀的來源：塔形與索的配置照作者舊版的淡江大橋（參考庫 `OpenWorld/reference_snapshot/play/src/world/tamkang-bridge.js`）；橋塔位置取 OpenStreetMap 兩條車道分得最開的地方（和底圖同一份資料，ODbL），跨度與塔高取公路局公布的數字。
- 圖是預覽工具拍的，不是 Metal 或實機。圖裡不含照片。
- 每一輪改了什麼、還有哪裡不好：`docs/decisions/873.md` §4。
