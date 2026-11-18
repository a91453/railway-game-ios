# TSINGMA-TOWERS（青馬大橋的橋塔、主纜與吊索）

雲端工作串「做青馬大橋的橋塔」，分支 `claude/project-thread-g53zud`，決策 869。不動 GameCore、存檔版本、golden、replay；沒有新色。

## 進度

- 做完：兩座橋塔、主纜、吊索、公鐵之間的橋身外殼；吊著的範圍不立墩（`Map3DSuspensionBridge.swift`，決策 869）。
- 已驗證（Linux）：`Map3DSuspensionBridgeTests` 7 個、`Map3DRoadBridgeTests`、`Map3DViaductTests` 通過；預覽工具拍過改前改後（`docs/art/tsingma-towers-2026-11-18/overview.jpg`）。沒在 Metal 與實機看過。
- 下一步的第一個指令：沒有待做的；要重拍用 `tools/map3d-preview` 加 `MAP3D_BUY=hkmtr:TCL`。

## 還留下什麼

- 橋面只有 18 m 高（實物淨空 62 m），路面以下的塔柱很短；要抬橋面得和 HK-ROAD-TILT（#2465）的路床一起看。
- #2465 也改 `Map3DRoadBridge.swift`（`roadRise`）；這裡只在畫墩那一行加了 `hangsFromCables`，後合的那一張要併 main。
- 汲水門橋、汀九橋、昂船洲橋是斜張橋，還沒有塔與索（HK-BRIDGES-CHECK 之後另評）。
- 夜裡不亮；吊索與錨碇很簡單（決策 869 §4「還有哪裡不好」）。
- 參考照片的作者與授權還沒取得（雲端查 Wikimedia Commons API 被限流），所以沒放進素材庫。
- 青衣塔腳旁邊地上的灰色斜板是原本就有的（改前的圖也有），不是這張做的，沒查是什麼。
