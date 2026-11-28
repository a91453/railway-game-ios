# 舊版橋上駅舎接進遊戲（決策 1043）

`overview.jpg`（決策 1043 §7）：左舊外型（決策 1043 第一次接進來的樣子：舊版的山形屋頂改綠）、右新外型（工作室重做，assets-2 #691：鋼灰懸浮屋頂、綠色採光罩、折梯、雙細柱墩），遊戲鏡頭 40° 從站前與月台側看。三個場景由上到下：兩座岸式擴建一級（overtrack-1）、一座島式（overtrack-2）、岸式再往外一座島式（工作室的五線配置：overtrack-1 ＋ 廊道 ＋ overtrack-stair，廊道下兩條通過線之間立墩）。

重建：`tools/old-models/export-old-overtrack.swift`（檔頭寫怎麼編）把六個場景寫成 `.m3dmodel`。舊外型是 commit `7b7f7804`（#2845 的 `Map3DOldOvertrackMesh.swift`）編出來的 `*-after`，新外型是這次的 `*-after`，再

```sh
node tools/model-look/shoot.mjs --model <new>/side-after.m3dmodel --before <old>/side-after.m3dmodel \
    --labels 舊外型,新外型 --focus 0,2,7,17,13,7 --max-triangles 20000 --out side.jpg
```

island 用 `--focus 0,0,7,17,14,7`，further 用 `--focus 0,-8,7,18,22,7`；總覽是三張的第二部分接起來。決策 1043 第一次的改前改後（站房在旁加天橋 → 舊外型的橋上站）在 git 歷史裡這個檔案的上一版。完整的看圖表在 assets-2 `game-art-previews/docs/art/old-port-station-ground-2026-11/in-game/`（`overtrack-*.jpg`）。
