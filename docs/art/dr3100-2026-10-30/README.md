# DR3100 柴聯自強號（決策 511，2026-10-30）

作者：「dr3100接入運行 先用dr1000代替 兩者差異不大」。外型是 #1530 的 45DR1000（`Map3D45DR1000`，revision-4），只換塗裝（`Map3D45DR1000.Livery.dr3100`）：

- 車身 `BFC8C9`、腰帶與車端的橘 `E89A27`：參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/garage-blender-v1/dr3100.json` 的 `specification`。
- 車端的黃 `ECC147`：同一檔 `drawGroups` 的 `yellow`。
- 車頂下沒有細帶（規格只有一條 accent）。

| 檔 | 內容 |
| --- | --- |
| `overview.png` | 上排白天、下排夜晚：DR3100 近景車頭、DR3100 遠景車頭、DR1000 近景車頭（對照） |
| `dr3100-front-day.png` | DR3100 近景正面，白天 |

重建（producer：本 PR 的 commit）：

```sh
tools/train-models/run.sh OUT --tag after --ids set-dieselExpress-head,set-dieselExpress-car,set-dieselExpress-tail,set-dieselExpressFar-head,set-dieselExpressFar-car,set-dieselExpressFar-tail,set-dieselRailcar-head,set-dieselRailcarFar-head
node tools/train-models/check.mjs OUT --new-set dieselExpress
node tools/train-models/render.mjs OUT --time both
python3 tools/train-models/overview.py OUT overview.png --time both set-dieselExpress-head set-dieselExpressFar-head set-dieselRailcar-head
```

外型與 DR1000 相同，完整七向與 GLB 沒有另外放進 `a91453/railway-assets-private`（45DR1000 的在 `game-art-previews/docs/art/45dr1000-2026-10-29/revision-4/`），用上面的指令可以重產。

狀態：技術（預算、雜湊、Linux 測試）VERIFIED；作者對塗裝的接受、iOS Metal、實機外觀與幀數 UNVERIFIED。圖是 Linux 的 WebGL 預覽，不是 Metal。
