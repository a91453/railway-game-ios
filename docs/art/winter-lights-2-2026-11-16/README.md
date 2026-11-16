# 冬季燈串與聖誕塗裝（WINTER-LIGHTS-2，決策 802）

`overview.jpg`：上半是燈串改前（決策 794，掛在站前廣場上空）與改後（掛在雨遮、屋簷的邊上），以及新加的地下站出入口、高架站樓梯口的燈串；下半是六款原本紅色少的車，原色與聖誕版並排。

- 畫法：`tools/station-kit/renderer.js`（WebGL 正投影），不是 Metal，也不是 App 的畫面；燈泡的夜間光暈沒有畫。
- 重拍：`tools/model-look/export-winter.sh lights <資料夾> [before]`、`tools/model-look/export-winter.sh livery <資料夾> commuter-cab set-pushPull-car set-ALISHAN-car set-puyuma-head set-emu800-head set-emu3000-head`，再用 `tools/model-look/shoot.mjs` 拍（`tools/model-look/README.md`）。
- 每種站型逐張的圖不到 2 MB 的門檻也沒放：用上面的指令可以重出。

## 塗裝方案（給作者選，還沒實作）

`livery-options.jpg`：九款車，左半白天、右半夜晚（夜晚是把不發光的面壓暗的示意，不是遊戲的夜景）。每列三格：原塗裝｜方案 A「裝飾，不重漆」｜方案 B 整車紅（這張 PR 修過比例的現況）。

- 方案 A：車身大面不動；腰線的色帶改深莓紅（原本就是紅車身的改冷杉綠）、細線改金；窗上緣一串暖白小燈（另加的發光小面，不改模型包）；頭車正面一個冬青綠花圈加紅結。
- 重出：`tools/model-look/export-winter.sh preview <資料夾> commuter-cab set-emu500-head …`（只是預覽用的匯出器，遊戲不讀）。
- 看圖的毛病：花圈直徑 0.9 m，在遊戲大小幾乎看不到；小燈白天只是幾個點，晚上才明顯；淡海輕軌沒有腰線可換，A 與原塗裝幾乎一樣；EMU500 的駕駛室前面被當成細線染成金色。
