# NATURE-BASE：鄉間的地表覆蓋與森林的樹

## 進度

- 這個 session 在 2026-11-17 第 2 次壓縮後停手（實作 session 的上限），PR #2336 交給規劃或下一個 session 收尾。
- 做完的：
  - CI 紅（`HongKongAirportTests`，`groundMixes` 含了底圖的草地色）已修；
  - 網站版 `build_worldcover.py` 比對過，同樣 4 個圖塊（SHA-256 相同），移植了類別表、SHA-256 檢查與出處；向量圖磚格式與「大片林地不長樹」刻意不照做，理由在決策 811 §5；
  - 裸地改用既有的 `paved`，只留 `forestFloor` 一個新色，五方理由在決策 811 §3；
  - 規劃 05:08 看過總覽圖，方向對。它問遠處新種的樹是否像深色雜點：在遊戲鏡頭距離（約 2600 m）看，這些樹和既有 OSM 林地的針葉樹（決策 458）一樣是小深點，深色主要來自每棵樹的影子；試過較淡的葉色，2600 m 變成灰色髒點，700 m 樹被洗白，所以葉色不改。這一行寫在 PR 說明裡（對照圖沒有提交，免得 CI 重跑）。
- 已驗證：Linux 快檢與 `LandCoverGridTests|Map3DGroundTintTests|Map3DNorthernMapTests|HongKongAirportTests|Map3DSceneryPropsTests` 通過。
- 下一步（接手的人）：等 #2336 這一版 head 的 CI（Swift CI gate 與 iOS App Build）全綠，把 PR 轉成 ready，在 #2118 留「可合併、head <SHA>」。CI 若紅，照失敗訊息修，不要跳過測試。

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
