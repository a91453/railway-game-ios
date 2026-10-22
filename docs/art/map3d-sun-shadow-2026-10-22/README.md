# 3D 地圖的太陽陰影貼圖（決策 357）預覽

`overview.jpg`：左邊是之前（`MAP3D_SUN=0`，等於省電畫質：只有決策 232 的團狀影子），右邊是之後。由上而下：台中車站往北看 14:00、17:00（`near`，320 m），車站東南的街廓 14:00、17:00（`low`，260 m）。

用 `tools/map3d-preview/` 畫（`MAP3D_WORLD=taichung MAP3D_BASEMAP=1 MAP3D_CITY=1 MAP3D_CROP=-200:0:650`，鏡頭 `near:0:0:320:35;mid:0:0:800:-25;low:-150:120:260:120`，見那裡的 README）。這個預覽是 WebGL 的移植，沒有決策 347／349 的天空、薄霧與色調映射，顏色和 App 不完全一樣；實機還沒看。

其他的比較圖（`cmp-near.png`、`cmp-mid.png`、`cmp-low.png`：每張上中下是 09:00、14:00、17:00，左之前右之後）與每一張原圖在 `a91453/railway-reference-private` 的 `Railway/game-art-previews/docs/art/map3d-sun-shadow-2026-10-22/`。
