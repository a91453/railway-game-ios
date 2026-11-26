# JAPAN-CENSUS-GRID 交接（決策 1000）

2026-11-26，雲端工作串「改用更細的日本人口資料」（分支 `claude/project-thread-q0rhpd`）。

## 做到哪

- 第一張 PR #2718（已合併）：遊戲能讀 `population.json` 的 `jobs`（`PopulationGrid`、`LandImport`），修掉海外地圖用列行
  誤讀台灣 places 的問題；工具 `tools/census-grid/japan_census_grid.py`；測試 `CensusGridTests`；決策 1000。
- 第二張 PR（決策 997 長崎包合併後）：`MapPacks/fukuoka/population.json` 換成國勢調查＋經濟普查（四縣範圍，西 129.34：
  住 952.1 萬、上班 448.9 萬，931 × 955 格 7.5″，3.1 MB）；`pack.json` 的人口一列與出處、`DataSourceCredits` 的
  「福岡的人口」、`tools/fukuoka-map/README.md` 第 3 步；`build_fukuoka_ground.py` 拿掉 WorldPop 的 `population` 步驟，
  `grids` 的角落寫死成 `GRID_CORNER`（以前 WorldPop 30″ 的角，和現在的 `heights.dat` 逐位元一樣）；`FukuokaGroundTests`
  加 `testTheJobs`（天神、博多 800 m 內上班的人是住的 3 倍以上，姪濱住的是上班的 2 倍以上）；`MapGrowthLayoutTests`
  的四塊 `ridersStep` 93,000 → 95,000（四塊的土地照國勢調查與經濟普查算）。
- 建物（`buildings.pmtiles`）沒重做：樓層估計當初讀的是 WorldPop 的人口，下次重做 `buildings` 會改讀 7.5″ 的格
  （`density_lookup` 用每平方公里的密度，格子變小不影響算法，但數字會跟著真實街區變）。

## 之後可以做的

- **校正運量**：國土數值情報 S12「駅別乗降客数」（CC BY 4.0 相容）對照遊戲各站一天的運量，看 `LandDemand.tripsPerHundred`
  在日本要不要另外一個值。
- **250 m 的住**：國勢調查有 250 m（`T001142`），經濟普查沒有。要用的話，把上班的 500 m 平均分到 250 m 的格網上
  （250 m 是 7.5″ × 11.25″，正方格要用 3.75″，檔案會再大 4 倍）。
- **用建物分配**：現在 500 m 格平均分成 6 格。可以照 OSM 建物的面積（住宅給住的人、其他給上班的人）分。

## 其他地方（同一個 `population.json` 格式，遊戲端不用改）

查到的，還沒驗證能不能下載：

- **台灣**：內政部「社會經濟資料服務平台」SEGIS 的最小統計區人口（每季，多邊形），政府資料開放授權條款第 1 版（和 CC BY 4.0
  相容，可商用）。做法：多邊形依面積分到 7.5″ 正方格（要 shapely）。上班：主計總處工業及服務業普查（110 年）在 SEGIS 有
  村里或二級發布區的從業員工數；沒有的話保留 OSM places（`taiwan_places.json`）。注意台灣的 places、分區（決策 93）、不蓋區
  都和 `taiwan_population.json` 共用 30″ 格網：換成 7.5″ 要一起重做 `build_place_grid.py`、`build_zone_grid.py`。
- **香港**：政府統計處 2021 人口普查，街段（Street Block）或小規劃統計區（TPU）的人口；上班地點有按地區的「工作地點」
  統計。資料一線通（data.gov.hk）的條款可商用、要標出處。做法同台灣（多邊形 → 正方格）。
- **芬蘭**：做完了（決策 1007，`tools/census-grid/finland_census_grid.py`）。統計局的 250 m 格與上班格網是付費的，
  改用開放的 1 km 人口格＋郵遞區（Paavo）工作人數，依包內建物分到 7.5″ 格。
