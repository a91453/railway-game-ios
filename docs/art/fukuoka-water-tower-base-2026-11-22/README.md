# 福岡給水塔的底部（決策 924 的「後來」，2026-11-22）

作者在 0.6.0 (144) 看到給水塔底部怪怪的。原因與改法在 `docs/decisions/924.md` 的「後來」。

| 圖 | 內容 |
| --- | --- |
| `near-before-after.jpg` | 近景：遊戲大小、遊戲鏡頭角度放大、放在地圖上，每格改前與改後 |
| `far-before-after.jpg` | 遠景（拉遠時畫的那個模型），同樣的格子 |
| `old-version-thumbnail.jpg` | 作者舊版的縮圖：腳之間是貼圖畫的 X 斜撐（黑底），不是實心板 |

改前：六支腳之間各有一片離地 0.5 m 的淡色實心板。改後：板換成斜撐與橫梁，看得到後面的地面。

重畫：

```sh
python3 -I tools/old-models/old_tanks.py <素材庫 -2>/game-art-previews/docs/art/old-port-fukuoka-tanks-2026-11/old-version/gas-holder.glb \
  <同一個資料夾>/water-tower.glb Sources/GamePresentation/Map3DFukuokaTanksMesh.swift
node tools/model-look/shoot.mjs --model 改後.m3dmodel --before 改前.m3dmodel --out near-before-after.jpg
```

`.m3dmodel` 是把 `Map3DFukuokaTanksMesh.swift` 的編碼解開、照 `waterPalette` 上色寫成的（一次性的腳本，沒有進 repo）。畫法是 `tools/station-kit/renderer.js`，不是 Metal；實機等 TestFlight。

來源：模型是作者自己的舊版內容（SwiftRailMac 的給水塔 `item_2cedf43508c08f24c37b0c88`）。
