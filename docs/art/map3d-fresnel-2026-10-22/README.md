# 3D 地圖的玻璃與水面反光（決策 356）預覽

`overview.jpg`：左邊是之前（`MAP3D_MIRROR=0`，等於省電畫質），右邊是之後。上面三列是台中的河（低角度鏡頭 `riverlow`），下面三列是辦公大樓與運河（`glass`）；每組由上而下是 14:00、17:30、21:00。

用 `tools/map3d-preview/` 畫（`MAP3D_BASEMAP=1 MAP3D_CITY=1 MAP3D_CROP=-300:0:800`，見那裡的 README）。這個預覽是 WebGL 的移植，沒有決策 347／349 的天空、薄霧與色調映射，顏色和 App 不完全一樣；實機還沒看。

其他的比較圖（`cmp-river.png`、`cmp-glass.png`、`cmp-riverlow.png`、`cmp-wide.png`）與每一張原圖在 `a91453/railway-reference-private` 的 `Railway/game-art-previews/docs/art/map3d-fresnel-2026-10-22/`。
