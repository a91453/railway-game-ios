# 舊版橋上駅舎接進遊戲（決策 1043）

`overview.jpg`：左改前（決策 1042：舊版地面站房在月台旁，決策 936 的天橋在雨棚外；只有一座島式的站沒有上島的路）、右改後（日本：橋上駅舎跨在月台中段，屋頂改車站綠、街道側加站名板），遊戲鏡頭 40° 從站前與月台側看。三個場景由上到下：兩座岸式擴建一級（overtrack-1）、一座島式（overtrack-2）、岸式再往外一座島式（工作室的五線配置：overtrack-1 ＋ 廊道 ＋ overtrack-stair，廊道下兩條通過線之間立墩）。

重建：`tools/old-models/export-old-overtrack.swift`（檔頭寫怎麼編）把六個場景寫成 `.m3dmodel`，再

```sh
node tools/model-look/shoot.mjs --model <dir>/side-after.m3dmodel --before <dir>/side-before.m3dmodel \
    --labels 改前,改後 --focus 0,2,7,17,13,7 --max-triangles 20000 --out side.jpg
```

island 用 `--focus 0,0,7,17,14,7`，further 用 `--focus 0,-8,7,18,22,7`；總覽是三張的第二部分接起來。完整的看圖表在 assets-2 `game-art-previews/docs/art/old-port-station-ground-2026-11/in-game/`（`overtrack-*.jpg`）。
