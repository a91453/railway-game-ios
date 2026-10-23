# 挑戰劇情的角色頭像（決策 387）

`portraits.png`：站長（決策 122，不變）和平溪線劇情的三個新角色：阿松伯（`StoryAhSong`）、小葳（`StoryXiaoWei`）、Mia（`StoryMia`）。art-style skill 的預覽：120／64／44／28 點，面板與地圖的淺色、深色底，最後兩格是模糊與灰階。

SVG 在 `RailwayGameApp/Resources/Assets.xcassets/Story*.imageset/`，用 scratchpad 的 Python 腳本產生（不放進 repo），只用 `svg`、`path`、`circle`、`ellipse`、`rect`。顏色見 `docs/UI_THEME.md`「挑戰劇情的角色」。

改了兩輪：
- 第一版：小葳的天燈在圓的邊上被切掉，往裡移；Mia 的背包肩帶原本是綠松色，和小葳的圍裙像，改成藍灰。
- 第二版（遊戲規劃看過後）：三人原本只有頭髮不同、臉一樣，改成阿松伯臉略方、粗眉、眼角紋與法令紋；小葳齊瀏海、笑瞇的弧形眼；Mia 上揚的細眉、雀斑、張口大笑。小葳的天燈改到圍裙胸前、放大，整盞在圓裡；Mia 的背包從兩肩後面露出，肩帶加黃色扣環。28 點的灰階也分得出三個人。
