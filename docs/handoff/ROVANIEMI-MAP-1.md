# ROVANIEMI-MAP-1：羅瓦涅米的地圖資料線

- 派工：主規劃（WINTER-EVENT 第 2 張，§29.11 E），2026-11-15，雲端 thread session，分支 `claude/project-thread-mc6bet`。
- 決策 789（`docs/decisions/789.md`）。存檔版本、golden、replay、GameCore：不動。
- 做了：`tools/rovaniemi-map/`；地圖包 `MapPacks/rovaniemi/`（鐵道、真實時刻、班次、人口、底圖、地形、水域、機場、不蓋區，13.4 MB）；`OverseasMap.rovaniemi`（**沒有**加進 `OverseasMaps.open`）；資料來源頁的羅瓦涅米一節（打開後才列）；`RovaniemiRailwaysTests`。

## 還留下的（照順序）

1. **凱米耶爾維的備用車擋住夜車一分鐘**：週六晚上到週四，一列備用車停在凱米耶爾維的本線月台；PYO 265 08:50 到站時被判卡住 1 分鐘，遊戲再把它送到側線（測試釘住「最多 1 分鐘」）。修法二選一：(a) `extract_rovaniemi_runs.py` 改成週四下午才從羅瓦涅米回送過去；(b) 收購時，整天沒班的車停到最後一股。(a) 只動資料，先試。
2. **ROVANIEMI-MAP-2**：建物（OSM 的外形、樓層，照 `build_hk_buildings.py` 改）、雪景色票接地形；企劃 §3.3。
3. **開關打開那一張**：`OverseasMaps.open` 加 `.rovaniemi`、加 `RailwayGameApp/AssetPacks/rovaniemi.json`（照 `hongkong.json`，決策 776）、新遊戲清單直接列（不用航班解鎖，企劃 §3.1）、網站 `credits.html`、`economy-balance` 量兩條線的價格（`.branch` 一人 300 萬，可能太貴）。
4. 3D 列車：先借現有的機車＋客車，Sr3、Sr2 與雙層客車交工作室（企劃 §4.2 第 5 項）。
5. 軌距 1,524 mm：3D 軌道有沒有寫死軌距沒查。

## UNVERIFIED

- 雲端 Linux 跑過：`swift build --build-tests -Xswiftc -warnings-as-errors`、`RovaniemiRailwaysTests`（5 項）與相關的香港、資料來源、分包下載測試。
- 沒在 iOS Simulator、iPhone 上看過：2D 底圖與山影、3D 地形、湖面、列車的樣子；地圖包 13.4 MB 的記憶體與載入時間沒量。
- 開關沒打開，玩家看不到；價格與平衡沒量。
