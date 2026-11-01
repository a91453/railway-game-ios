# 貨運列車：R200 ＋ 貨櫃平車（決策 539）

- `overview.png`：四款貨櫃平車的近景（40 呎鐵鏽紅、20 呎兩只、40 呎深綠、尾車赭黃）與 20 呎那款的遠景，`tools/train-models/overview.py` 的日間模型光。
- 完整七向（日、夜）：`a91453/railway-assets-private` 的 `game-art-previews/docs/art/freight-r200-2026-11-01/revision-1/`。
- 重建：`tools/train-models/run.sh OUT --ids set-R200CK-head,set-FREIGHT-car,set-FREIGHT-fourth,set-FREIGHT-centre,set-FREIGHT-tail,set-R200CKFar-head,set-FREIGHTFar-car,set-FREIGHTFar-fourth,set-FREIGHTFar-centre,set-FREIGHTFar-tail`，再 `node tools/train-models/render.mjs OUT --time both`。
- Linux 的 WebGL 預覽不是 Metal；真機 UNVERIFIED。
