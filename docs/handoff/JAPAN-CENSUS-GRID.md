# JAPAN-CENSUS-GRID 交接（決策 1000）

2026-11-26，雲端工作串「改用更細的日本人口資料」（分支 `claude/project-thread-q0rhpd`）。

## 做到哪

- 第一張 PR：遊戲能讀 `population.json` 的 `jobs`（`PopulationGrid`、`LandImport`），修掉海外地圖用列行誤讀台灣
  places 的問題；工具 `tools/census-grid/japan_census_grid.py`；測試 `CensusGridTests`；決策 1000。
- **地圖包的 `population.json` 還是 WorldPop 1 km**：「完成長崎縣地圖包」那串（決策 997，分支
  `claude/project-thread-dzwmgt`）要把日本地圖西緣移到 129.34、重做整個地面，等它合併再換。
- 福岡試算的數字與比較圖在決策 1000 §4；圖在專案共用資料夾 `census-grid/fukuoka-before-after.jpg`。

## 下一張 PR（日本，決策 997 合併後從 main 開）

```sh
python3 -I tools/census-grid/japan_census_grid.py fetch RailwayGameApp/Resources/MapPacks/fukuoka /tmp/estat
python3 -I tools/census-grid/japan_census_grid.py build /tmp/estat RailwayGameApp/Resources/MapPacks/fukuoka \
  --compare RailwayGameApp/Resources/MapPacks/fukuoka/population.json
```

長崎包的範圍（西 129.34）先算好一份放在專案共用資料夾 `census-grid/population-nagasaki-extent.json`（952 萬人、449 萬個工作、3.1 MB），
範圍沒再變的話可以直接比對（重跑結果應該逐位元相同）。

再改：

1. `tools/fukuoka-map/README.md`「重做」第 3 步：人口改成上面兩行（WorldPop 那兩行拿掉）；`build_fukuoka_ground.py`
   的 `population` 步驟拿掉或改成呼叫它。
2. **`build_fukuoka_ground.py grids` 的格網角落**：它用 `build_hk_ground_grids.grid_box(population.json, EXTENT)`
   從人口檔的角落與格大小推高度格的角落。人口改成 7.5″ 以後，下次重做 `grids` 角落會移（每格 1.875″ 的高度全部位移）。
   要嘛在 `grids` 寫死 WorldPop 30″ 的角落與格大小，要嘛先把高度格的角落記在 `fukuoka_sources.json` 再讀回來。
   這張 PR 不重做高度與水域（每重做一次 git 多 45 MB），只換 `population.json`。
3. `buildings` 步驟（`overseas_buildings.py` 的 `density_lookup`）讀 `population.json` 估樓高。換了人口後不用重做建物；
   之後若重做，先確認 `density_lookup` 讀 7.5″ 的格沒問題（每格面積小了 16 倍，密度是每平方公里，應該不受影響）。
4. `DataSourceCredits`：日本地圖的人口出處改成 e-Stat（國勢調查、經濟普查），署名照決策 1000 §2。
5. `FukuokaGroundTests` 的人數（現在 850–980 萬）與博多、天神附近的檢查；加一條「天神 800 m 內上班的人比住的人多」。
6. 跑：`swift test --skip-build --filter 'FukuokaGroundTests|CensusGridTests|LandImportTests|FukuokaRailwaysTests'`，
   以及福岡的 timetable checkup（`CheckupBudgets/Fukuoka.swift`）看有沒有變。
7. 檔案大小：福岡現在的範圍 2.97 MB（WorldPop 0.14 MB）。asset pack 的 `bytes` 要更新（`build_fukuoka_rail.write_manifest`）。

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
- **香港**：做完了，決策 1008（`tools/census-grid/hongkong_census_grid.py`）。
- **芬蘭**：統計局 Statistics Finland 的格網資料庫：250 m 人口格（Väestöruudukko）與 1 km 的上班人數（Työpaikat），
  CC BY 4.0，WFS `geo.stat.fi`。格網是 ETRS-TM35FIN（公尺），要重投影到經緯度正方格；羅瓦涅米在北緯 66.5°，
  7.5″ 經度只有約 93 m，可以用 15″ 或 30″。
