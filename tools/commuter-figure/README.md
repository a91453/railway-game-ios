# tools/commuter-figure

決策 787：把素材庫的站立通勤乘客轉成遊戲的 Swift 網格。

```sh
# 素材庫 a91453/railway-assets-private 的 revision-1（PR #121）
python3 -I tools/commuter-figure/to_swift.py \
  ../railway-assets-private/game-art-previews/docs/art/commuter-figure-2026-11/revision-1/commuter-figure-300.glb \
  Sources/GamePresentation/Map3DCommuterFigureMesh.swift
```

只用 Python 標準庫。它做的事（修取色、走路的擺腿、轉軸、編碼）寫在腳本開頭與決策 787。GLB 換了一輪時，先看輸出印的三角形數與各色面數，再用 `tools/model-look/shoot.mjs` 看圖，`Map3DModelPackLockTests` 與 `hashes.lock.json` 的兩個 `life-commuter…` 跟著更新。

來源：Meshy AI 生成（作者的付費方案，輸出歸作者，Meshy 條款 §3.2），在 Blender 減面（素材庫 README）；資料來源頁標示「AI 生成」（§2.4）。
