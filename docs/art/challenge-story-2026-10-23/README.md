# 挑戰劇情的角色頭像（決策 387）

`portraits.png`：站長（決策 122，不變）和平溪線劇情的三個新角色：阿松伯（`StoryAhSong`）、小葳（`StoryXiaoWei`）、Mia（`StoryMia`）。art-style skill 的預覽：120／64／44／28 點，面板與地圖的淺色、深色底，最後兩格是模糊與灰階。

SVG 在 `RailwayGameApp/Resources/Assets.xcassets/Story*.imageset/`，用 scratchpad 的 Python 腳本產生（不放進 repo），只用 `svg`、`path`、`circle`、`ellipse`、`rect`。顏色見 `docs/UI_THEME.md`「挑戰劇情的角色」。

第一版和這版只差兩處：小葳的天燈原本在圓的邊上被切掉，往裡移；Mia 的背包肩帶原本是綠松色，和小葳的圍裙像，改成藍灰。
