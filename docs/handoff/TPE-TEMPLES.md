# TPE-TEMPLES：臺北廟宇照真實外形上 3D 地圖

- 派工單：`docs/research/TW_3D_MODELS_2026-11-13.md` §7 的 TPE-TEMPLES（遊戲規劃第 64 任派工）。
- Session：TPE-TEMPLES（`claude/tpe-temples`，PR 2146）；決策 725。存檔版本、golden schema 不動；GameCore、存檔、golden、fixtures 不動。

## 做了什麼

- `tools/tpe-temples/`：讀臺北市宗教建築 3D 模型庫的 KMZ（`fetch.sh` 下載並核對 SHA-256），只取外形、刷遊戲的顏色、以 meshoptimizer 簡化，寫成 `.m3dmodel`。
- 十座（龍山寺、行天宮、指南宮、臺灣省城隍廟、霞海城隍廟、天后宮、清水巖、濟南教會、慈諴宮、惠濟宮）在 `RailwayGameApp/Resources/Models/tpe-*.m3dmodel`。
- 場景：`Map3DTaipeiTemples.swift`，和決策 457 的地標一起放，取代決策 331 的套件廟。
- 資料來源頁新增「臺北廟宇模型」（中英文）。
- 細節在 `docs/decisions/725.md`。

## 還留下什麼

- **山上的廟**（指南宮、惠濟宮）：地面取模型四角最低的地面，坡上的地形會穿過模型。要嘛把模型的地面照地形切，要嘛把那幾格的地形壓平到模型的台階。還沒做。
- **另外四座**（保安宮、關渡宮、清真寺、青山宮）：資料集裡是 Google 3D Warehouse 的匯出、作者不明，這批不做。要做的話先找有授權的來源。
- **資料集其他的廟**：CSV 裡還有約七十座。做下一批時沿用 `recipes.mjs`：加一行配方，照 model-look 拍三輪。
- **惠濟宮的牌樓**（111003_archway）：在山下，地形接好之後再放。
- **實機（Metal）沒有看**：UNVERIFIED，要 TestFlight。
- **照片**：
  - 清水巖在維基共享資源只找到室內照，外觀照沒找到（找的時候被限流）。
  - 臺灣省城隍廟只有一張照片。
