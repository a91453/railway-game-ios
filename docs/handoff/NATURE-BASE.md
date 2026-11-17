# NATURE-BASE：鄉間的地表覆蓋與森林的樹

## 進度

- 做到哪：台灣的第一版在 draft PR #2336（head `ad787d1` 之後只多這個交接檔），CI 剛開始。2026-11-17 02:44 規劃說額度剩約 10 %，要停手，所以停在這裡，等規劃通知再繼續。
- 已驗證：Linux 快檢通過。整輪 `--filter Map3D`（1535 個）跑過一次，兩個類別失敗：`Map3DGroundTintTests`（森林地面原本太深、混色數改 209）和 `Map3DNorthernMapTests`，修好後這兩類重跑通過，整輪沒有再跑。花蓮縱谷的樹 1807 → 5380。
- 下一步：照規劃 2026-11-17 01:26 的補充（我開 PR 前沒讀到）改兩件事：
  - (1) 先讀 `Railway/taiwan-rail-reference-clean/source/scripts/build_worldcover.py`，能移植就換掉 `tools/worldcover/build_landcover_grid.py`，並寫進 PR 對照表。
  - (2) 規劃要求「地面顏色只對到既有的 `Map3DPalette`，不新增顏色」，但這版新增了 `bare` E7E3D9 和 `forestFloor` D4E8DA。要改成既有顏色（裸地可用 `paved` 或 `cover(.sand)`；森林要找一個在 5 L* 以內的既有綠，例如 `yard`），再跑 `Map3DGroundTintTests|Map3DNorthernMapTests|LandCoverGridTests`。
  - 規劃補充的其他要求，這版已符合：不寫進 GameCore、不走 `addArea(.wood)`、香港不做。

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
