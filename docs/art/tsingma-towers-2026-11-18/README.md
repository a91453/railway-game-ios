# 青馬大橋的橋塔、主纜與吊索（決策 869）

`overview.jpg`：左邊是改前（`main`），右邊是改後，同一個鏡頭。由上到下：全景、遊戲鏡頭、馬灣側、青衣塔腳。

- 重建：這個 PR 的 commit，`tools/map3d-preview`（`MAP3D_WORLD=hongkong MAP3D_AT=22.3511:114.0740 MAP3D_BUY=hkmtr:TCL`，其餘開關見工具的 README）。
- 形狀的來源：地政總署三維視像化地圖（位置與尺寸量成常數，模型檔不進遊戲）；程式是本專案自己的。
- 圖是預覽工具拍的，不是 Metal 或實機。圖裡不含照片。
- 每一輪改了什麼、還有哪裡不好：`docs/decisions/869.md` §4。
