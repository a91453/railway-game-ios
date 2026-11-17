# NATURE-BASE：鄉間的地表覆蓋與森林的樹

## 進度

- 做到哪：台灣做完（決策 811）。ESA WorldCover → `taiwan_landcover.dat`（1.82 MB）→ 3D 地圖的鄉間地面上色、森林種樹；draft PR 開了，等 CI 與遊戲規劃看截圖（新的外觀，ui-review 第三級）。
- 已驗證：Linux 的快檢與 `Map3D*`、`LandCoverGridTests` 全過；花蓮縱谷 23.60, 121.40 的樹 1807 → 5380，場景建置時間不變；前後對照圖在 PR。
- 下一步的第一個指令：看 PR 的 CI（`Swift CI (gate)` 與 `iOS App Build`）；紅了照紀錄修，綠了在 #2118 留 head 與截圖。

## 派工與範圍

- 派工單：NATURE-BASE（評分 2.95），session `session_01JMHz9ZReBekPHAWGED1RZv`，分支 `claude/nature-base`。
- 決策 811（`docs/decisions/811.md`）。存檔版本、golden schema 不動；`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 不動；GameCore 不動。

## 還留下的

1. **網站的資料來源頁**：railway-reference-private 的 `Website/site/credits.html` 要加 ESA WorldCover（© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium，CC BY 4.0，doi:10.5281/zenodo.7254221）。這個 session 沒改那個庫。
2. 芬蘭（羅瓦涅米）：Maastotietokanta（CC BY 4.0）的林地與沼澤，讀成同一種格子；香港：地政總署 iB1000/iB5000 的植被。兩者都在 WorldCover 的範圍內，也可以先直接把 WorldCover 的圖塊加進去（工具只要換格子與圖塊）。
3. 樹冠高度（Meta / WRI 1 m canopy height）讓樹高照實際；MapLibre 的 2D 地圖還沒有這一層。
4. UNVERIFIED：Metal 的實際畫面、iPhone／iPad 的效能與記憶體（TestFlight 才看得到）。

## 重做資料

`tools/worldcover/README.md`：下載 5 個圖塊（約 120 MB），`python3 -I tools/worldcover/build_landcover_grid.py …`，約 2 分鐘。
