# 熊本市電低地板電車接進遊戲（決策 1041 續）

`overview.jpg`：上排左起是原本的替身（高雄輕軌 Citadis 半列）、工作室的熊本低地板電車近景、遠景，上白天下夜間；
下排是近景的斜看、側面、正面（白天、有車窗反光）。

- 模型：`a91453/railway-assets-private-2` `game-art-previews/docs/art/kumamoto-tram-lowfloor-2026-11/revision-6`
  （GLB SHA-256 近景 `100c4d26…`、遠景 `1adcf7e6…`，和那一輪 README 寫的一樣）。
- 重建：在這個 PR 的 commit 跑
  `tools/train-models/run.sh OUT --ids set-kumamotoTram-single,set-klrtCitadis-head`、
  `node tools/train-models/render.mjs OUT --time both --features 1`、
  `python3 -I tools/train-models/overview.py OUT overview.png --time both set-klrtCitadis-head set-kumamotoTram-single set-kumamotoTramFar-single`，
  再把總覽和 `png/day/set-kumamotoTram-single-{isometric,left,front}.png` 拼成一張 JPEG。
- 授權：作者自己的作品（工作室為遊戲做的模型與遊戲的出圖工具）。
