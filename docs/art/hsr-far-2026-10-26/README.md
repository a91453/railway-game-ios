# 高鐵 700T 與 N700S-G 的遠景車（決策 422）

`overview.png`：上半 700T、下半 N700S-G 的頭車；三欄是近景、新遠景（這次做的）、舊遠景（main 的 `highSpeedFar` 與 `n700sGFar`）。

- 「250 m／500 m／750 m」幾列：車在 iPhone 橫拿的畫面上（高 1,179 像素、3D 地圖的 35° 鏡頭）在那個距離有多大，就縮成多大（一節車 250 m 約 190 像素寬、500 m 約 94、750 m 約 62），再把每個像素放大成 3 × 3 好看清楚。「斜前」是從車頭左前上方看，「側面」是正側面。遊戲在 500 m（弱裝置或負荷重時 250 m，決策 417）換遠景、900 m 外換盒子。
- 「近看」：同一節車放大，看形狀與塗裝有沒有走樣。

用 `tools/hsr-far-422/`（README 有指令）產生：`export.swift` 寫出模型，`tools/mesh-lod-420/render.mjs` 平塗算圖（WebGL，不是 iPhone 的 Metal），`distance.py` 排成這張。各車廂、各角度的單張圖照指令重做就有，不放進 repository。數字與結論在 `docs/decisions/422.md`。
