# HK-BUILDINGS-GOV：香港建物改用地政總署的資料

- 派工：遊戲規劃第 65 任（2026-11-13），雲端 thread session，分支 `claude/project-thread-2pvrha`。決策 729。存檔版本、golden、fixtures、GameCore：不動。
- 做了：`tools/hk-map/build_hk_buildings.py` 改讀地政總署 Building（外形、高度）＋ OSM（用途）；`buildings.pmtiles` 重建（297,019 棟，5.1 MB）；`DataSourceCredits` 的「香港的建物」；`HongKongBuildingsTests` 的數字。
- 資料在作者 Mac 的 `~/Developer/hk-ground-downloads/`（`hk_buildings.zip` 與解開的 `hk_buildings/`、`hong_kong.pbf`、舊的 `buildings-osm-old.pmtiles`、`venv/` 有 osmium）。Mac 上的 worktree `~/Developer/hk-buildings-wt`。

## UNVERIFIED

- 雲端沒有 Swift；Mac 上跑過 `HongKongBuildingsTests` 以外的相關測試（綠），`HongKongBuildingsTests` 改數字之後的那一次交給 CI。
- 實機（iPhone）沒有看過；截圖只在 Mac 的模擬器（railway-assets-private #107）。

## 留下的

- 環球貿易廣場、國際金融中心二期蓋在車站正上方，買下機場快綫後被 `clearOf` 清掉（推測，決策 729 §5）：要地標模型或新決策。
- 青馬大橋畫成一般多墩高架、橋面上下起伏，沒有塔與纜（換之前就這樣，SHOTS-2173 的 5d）。

- 地標模型（HK-3DVIS 的四步）：做好時把那幾棟的 `BuildingCSUID` 加進工具的 `LANDMARKS`，重跑第 7 步。
- 卡其色方塊與藍色碎片（另一個工作串在修）。
