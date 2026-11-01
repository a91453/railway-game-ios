# 車站擴建三級的 3D 預覽（決策 506「續」）

`overview.png`：一般站與台北的站房、地面站與高架站的近景，原站／站廳擴建／大廳擴建。

全部 18 張（另有新竹、板橋站房）、總表與原生模型（`.m3dmodel`）在
a91453/railway-assets-private 的 `game-art-previews/docs/art/station-expansion-3d/revision-1/`。

做法：在 Linux 上把 `StationKitBuilder.house(_:expansion:)` 與 `Map3DScene.Builder` 的近景網格
寫成原生模型，用 `tools/station-kit/renderer.js` 在 Chromium（SwiftShader）裡等角渲染。
