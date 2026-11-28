# 舊版地面站接進遊戲（決策 1042）

`overview.jpg`：左改前（台灣款一般站與套件雨棚）、右改後（日本：舊版站房 s／m／l、20 m 雨棚、端頭欄杆，改成遊戲的顏色），遊戲鏡頭 40° 從站前與月台側看。三個場景：兩座側式月台（s）、島式加側式（m）、同一組月台擴建兩級（l）。

重建：`tools/old-models/export-old-ground.swift`（檔頭寫怎麼編）把六個場景寫成 `.m3dmodel`，再

```sh
node tools/model-look/shoot.mjs --model <dir>/s-after.m3dmodel --before <dir>/s-before.m3dmodel \
    --labels 改前,改後 --focus 0,-8,3,22,12,5 --out s.jpg
```

m、l 用 `--focus 0,-12,5,32,20,8`；總覽是三張的第二部分接起來。完整的看圖表在 assets-2 `game-art-previews/docs/art/old-port-station-ground-2026-11/in-game/`。
