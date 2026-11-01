# 阿里山林鐵 DL-38 與阿里山客車（決策 531）

`overview.png`：上排日、下排夜（遊戲的模型光，`tools/train-models/render.mjs`），左起整列（DL-38＋三節客車）、DL-38、客車；第二列是遠景版；右下是沒選的塗裝（紅車身、奶油帶）。

- 重建：`tools/train-models/run.sh OUT --night-lights --ids set-ALISHAN-head,set-ALISHAN-car,set-ALISHAN-tail,set-ALISHANFar-head,set-ALISHANFar-car,set-ALISHANFar-tail`，再 `render.mjs OUT --time both`。
- 七向圖、整列與沒選的塗裝：`a91453/railway-assets-private` 的 `game-art-previews/docs/art/alishan-dl38/revision-1/`。
- 來源與尺寸：`docs/decisions/531.md`。
- Linux 的 WebGL 預覽不是 Metal；實機樣子與幀數 UNVERIFIED。夜裡的頭燈與尾燈由遊戲每格點亮（決策 449），預覽看不到。
