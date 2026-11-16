# 冬季燈串與聖誕塗裝（WINTER-LIGHTS-2，決策 802）

`overview.jpg`：上半是燈串改前（決策 794，掛在站前廣場上空）與改後（掛在雨遮、屋簷的邊上），以及新加的地下站出入口、高架站樓梯口的燈串；下半是六款原本紅色少的車，原色與聖誕版並排。

- 畫法：`tools/station-kit/renderer.js`（WebGL 正投影），不是 Metal，也不是 App 的畫面；燈泡的夜間光暈沒有畫。
- 重拍：`tools/model-look/export-winter.sh lights <資料夾> [before]`、`tools/model-look/export-winter.sh livery <資料夾> commuter-cab set-pushPull-car set-ALISHAN-car set-puyuma-head set-emu800-head set-emu3000-head`，再用 `tools/model-look/shoot.mjs` 拍（`tools/model-look/README.md`）。
- 每種站型逐張的圖不到 2 MB 的門檻也沒放：用上面的指令可以重出。
