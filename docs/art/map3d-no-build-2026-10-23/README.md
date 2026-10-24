# 機場不蓋房子、房子沿街排（決策 385）

`xiaogang-before-after.png`：高雄小港機場一帶，實景 3D 地圖的 Linux WebGL 預覽（照 `Map3DShaders.metal` 畫，不是實機）。左邊改之前（main），右邊改之後；上面從正上方看 2,400 m，下面斜 30° 看 900 m。

- 改之前：跑道上、沒有路的地方都是同一種小房子，排成固定間距的棋盤格，全部朝同一個方向。
- 改之後：機場裡沒有住宅，只有 OSM 的航廈與機棚；其他地方的房子沿最近的街、面向馬路，寬窄、退縮、樓高與種類不同，沒有路的地方留白。

原尺寸的八張圖（前後 × 俯看／斜看 × 貼圖／陰影）在 `a91453/railway-reference-private` 的 `Railway/game-art-previews/docs/art/map3d-no-build-2026-10-23/`。重做：`tools/map3d-preview/README.md`（`MAP3D_WORLD=xiaogang`、`MAP3D_BASEMAP=1`，改之後加 `MAP3D_NOBUILD=1`；鏡頭 `top:0:0:2400:0;tilt:-300:300:900:30`，`MAP3D_CROP=0:0:1200`）。
