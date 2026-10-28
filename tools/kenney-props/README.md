# Kenney 的針葉樹、灌木叢、臥式儲槽（決策 458）

3D 地圖的三種景物：山區樹林的針葉樹（三款）、站前廣場與沿線空地的灌木叢（兩款）、工廠空地的臥式儲槽。原件是 Kenney 的 CC0 模型（來源、版本、授權見 `SOURCE.md`），照 `.claude/skills/art-style/SKILL.md` §7 改了形狀（不只換色）再轉成 `.m3dmodel`。

```sh
# 從 repo 根目錄；Node 22；先在 tools/glb-to-m3dmodel 跑過 npm ci --ignore-scripts
tools/kenney-props/build.sh [WORK_DIR]
```

`reshape.mjs` 讀 `source/` 的三個 GLB，寫 `WORK_DIR/<id>.glb` 與 `<id>.manifest.json`；`build.sh` 再用 `tools/glb-to-m3dmodel/bridge.mjs` 轉檔，複製到 `RailwayGameApp/Resources/Models/kenney-*.m3dmodel`。重跑逐位元相同。

| id（`Map3DSceneryProp`） | 怎麼改 | 三角形 | 長×寬×高（m） |
|---|---|--:|---|
| `kenney-pine-tall`（`pineTall`） | 原件三層樹冠取出，換成自家六角樹幹（3.2 m），疊成五層、每層縮小並轉 30° | 136 | 3.10 × 3.14 × 12.48 |
| `kenney-pine`（`pine`） | 自家樹幹 2.0 m，三層較寬、最上層壓扁 | 88 | 3.76 × 3.98 × 7.67 |
| `kenney-pine-young`（`pineYoung`） | 樹幹 0.9 m，兩層 | 64 | 2.26 × 1.90 × 5.02 |
| `kenney-bushes`（`bushes`） | 兩叢不同大小、轉向的灌木，腳埋進土裡 0.1 m | 120 | 2.40 × 1.70 × 1.00 |
| `kenney-bushes-large`（`bushesLarge`） | 三叢 | 180 | 3.22 × 2.68 × 1.25 |
| `kenney-tank`（`tank`） | 罐身拉長 2.4 m、改白，加混凝土墊與中間鞍座 | 332 | 9.76 × 4.40 × 3.26 |

樹冠（`Map3DPalette.crown`）與灌木（`embankment`）的顏色讀進遊戲時改成 alpha 0，由每個實例給自己的綠（`Map3DSceneryProp.coniferGreens`、`bushGreens`）。檔案讀不到時，`Map3DModelPack.standard` 裡同尺寸的程式替身照畫。

glTF-Validator：這一版沒有加進 CI（加工具屬於加依賴，等規劃回覆）；本機檢查見 PR 說明。
