# SANTA-FLIGHT 暫用造型（決策 831）

`overview.jpg`：聖誕老人雪橇的暫用方塊造型（`SantaFlight.Model`，1,512 三角形），`tools/model-look/shoot.mjs` 拍的總覽（正投影、遊戲的平光，不是 Metal）。正式模型由工作室做（REINDEER），到了換掉再拍。

重建：從這個 commit 把 `SantaFlight.Model.model` 寫成 `.m3dmodel`（`tools/model-look/export-winter-lights.swift` 的 `write`），再
`node tools/model-look/shoot.mjs --model santa-sleigh-single.m3dmodel --title "聖誕老人雪橇 暫用造型（決策 831，等 REINDEER）" --out overview.jpg`。
