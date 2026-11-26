# FINLAND-MML-BUILDINGS 交接（決策 1009）

2026-11-26，分支 `claude/project-thread-b5jxfx`（PR #2729，決策 1009 與 1011）。存檔、golden、GameCore 不動。

## 進度

- 做到：工具（`tools/rovaniemi-map/mml_buildings.py`、`build_rovaniemi_buildings.py` 改寫）、羅瓦涅米包 `buildings.pmtiles`
  （舊格式 `footprints/2`）、`StoreysFrom.mml`、資料來源畫面、測試、決策 1009。
- 已驗證（Linux 本機）：`swift build --build-tests -Xswiftc -warnings-as-errors` 無警告；RovaniemiBuildingsTests、
  RovaniemiRailwaysTests、Map3DFootprintsTests、DataSourceCredits*、Map3DMapLoadReport 全過；`doc_numbers.py --check` 過。

## 要等

1. 「縮小地圖包下載大小」（決策 1005，分支 `claude/project-thread-2mh2fd`）合併後：`git merge origin/main`，
   照 `tools/rovaniemi-map/README.md` 5b 重跑建物（`overseas_buildings.py` 的 metadata 要用 `tiles.WRITTEN_EXTENT`，
   `build_rovaniemi_buildings.py` 同樣改），再跑上面的測試。
2. #2723（羅瓦涅米人口，決策 1007）合併後：人口是照建物樓地板分的，建物換了要重跑 `finland_census_grid.py build`；
   建物的「猜」又照人口，兩個各跑一次就好，不要來回。

## 第二張：台灣官方樓高（決策 1011，同一張 PR）

- 做到：`tools/overture-footprint-tiles/usage_permits.py`（新北、臺北使用執照的地上層數，用兩市門牌坐標對到輪廓），
  內建 `taiwan_buildings.pmtiles` 改了 11,138 棟（仍是 `footprints/2`）、署名（`buildingStoreys`）、測試（林口）、決策 1011。
- 已驗證（Linux 本機）：build 無警告；Map3DFootprintsTests、RealRailwaysTests、DataSourceCredit*、Map3DFrontageTests、
  Map3DRealFacadeReportTests、ScreenshotSceneTests 全過。
- 瘦身合併後：`git show origin/main:RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles > main.pmtiles`，照工具開頭的
  指令下載執照與門牌，`usage_permits.py apply main.pmtiles …` 再覆蓋；**不要對已經跑過的檔再跑**。報告與決策 1011 §4 的數字跟著改。
- 還沒做：臺南（只有地號）、臺中（存根沒有地址）、高雄、桃園（沒找到）。國土測繪中心三維建物不能用（決策 1011 §2）。
