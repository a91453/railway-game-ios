# Meshy 街道小物（決策 467）

作者用 Meshy 生成的街道小物（`a91453/railway-assets-private` 的 `meshy-batch-2026-10/`，`glb-hq/` 的高模），簡化、換成遊戲的配色，寫成 3D 地圖讀的 `.m3dmodel`。

```sh
# 從 repo 根目錄；Node 22；先在 tools/glb-to-m3dmodel 跑過 npm ci --ignore-scripts
node tools/meshy-props/build.mjs <meshy-batch-2026-10 資料夾> <輸出資料夾>
cp <輸出資料夾>/meshy-*.m3dmodel RailwayGameApp/Resources/Models/
```

| 檔案（`Map3DSceneryProp`） | 原件 | 原件三角形 | 遊戲裡 | 誤差上限 | 長×寬×高（m） |
|---|---|--:|--:|--:|---|
| `meshy-post-boxes`（`postBoxes`） | `mailbox-green` | 433,504 | 1,724（一支 862，兩支） | 6 mm | 1.04 × 0.43 × 1.15 |
| `meshy-bus-stop-pole`（`busStopPole`） | `bus-stop-pole` | 84,268 | 300 | 10 mm | 0.59 × 0.58 × 2.80 |
| `garbage-truck`（`Map3DStreetModel.garbageTruck`，決策 437） | `garbage-truck` | 97,281 | 2,704 | 6 cm | App 讀檔時縮成 6.5 × 2.3 × 2.8 |

做法（`build.mjs`）：

1. 每個三角形用 `tools/glb-to-m3dmodel` 的取樣（三角形內 21 點）烤出貼圖顏色，依配方分到遊戲的幾種顏色（郵筒紅綠、投信口與門、底座；站牌的白面、藍框、鋼柱）。原件貼圖是斑駁的，所以郵筒只有正面的深色算投信口與門；它們畫成車身同色深一階（凹進去，不是破洞），新三角形要三分之二的點落在上面才上這個色，免得細長三角形畫出尖刺。
2. 立起來、縮到配方的高度，轉到遊戲的方向：郵筒投信口朝 +y（馬路），站牌的薄邊沿 x（牌面朝來車方向）。
3. 用 meshoptimizer 1.3.0（MIT，`tools/glb-to-m3dmodel/package.json` 已經釘的版本）的 `simplify`，以公尺為單位的誤差上限簡化到配方的三角形數；誤差先到上限就停（郵筒停在 862）。
4. 每個新三角形的顏色由它面上 21 個點投票：每點取最近的原件三角形（大三角形先在面上撒點，免得被旁邊細碎的框搶走）。
5. 垃圾車（`outward`）：簡化會把少數三角形折反，所以沿共用邊把每片相連的面統一繞序，整片再依底下原件表面的朝向決定朝外（決策 437 的 2026-10-29 修正：Meshy remesh 版有破洞與反面，實機晚上看到黑三角）。
6. 郵筒複製成一對，左邊那支改紅色（一個形狀兩用）。
7. 檔頭 provenance 記下 Meshy 的任務編號、模型、credits、原件的 SHA-256 與配方，並標明是 AI 生成（Meshy 條款 §2.4）。生成記錄另在 `tools/meshy/generated.json`、`models.json`。

同樣的輸入，輸出逐位元相同。列車不用 Meshy、不用這個工具（決策 467）。
