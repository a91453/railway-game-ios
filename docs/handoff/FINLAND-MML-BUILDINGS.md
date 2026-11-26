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
2. ~~#2723（羅瓦涅米人口，決策 1007）合併後重跑人口~~：**已做**（2026-11-26 併 main e3c1fbc6c，照 MML 建物重跑
   `finland_census_grid.py build`：住 69,768、上班 28,534；`pack.json`、`finland_sources.json` 跟著改）。瘦身合併後
   重生建物時，人口要再跑一次 `finland_census_grid.py build`（建物「猜」照人口、人口照樓地板，各跑一次就好，不要來回）。

## 第二張：台灣官方樓高（決策 1011，同一張 PR）

- 做到：`tools/overture-footprint-tiles/usage_permits.py`（新北、臺北使用執照的地上層數，用兩市門牌坐標對到輪廓），
  內建 `taiwan_buildings.pmtiles` 改了 11,138 棟（仍是 `footprints/2`）、署名（`buildingStoreys`）、測試（林口）、決策 1011。
- 已驗證（Linux 本機）：build 無警告；Map3DFootprintsTests、RealRailwaysTests、DataSourceCredit*、Map3DFrontageTests、
  Map3DRealFacadeReportTests、ScreenshotSceneTests 全過。
- 瘦身合併後：`git show origin/main:RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles > main.pmtiles`，照工具開頭的
  指令下載執照與門牌，`usage_permits.py apply main.pmtiles …` 再覆蓋；**不要對已經跑過的檔再跑**。報告與決策 1011 §4 的數字跟著改。
- 還沒做：臺南（只有地號）、臺中（存根沒有地址）、高雄、桃園（沒找到）。國土測繪中心三維建物不能用（決策 1011 §2）。

## 第三張（作者 2026-11-26 新要求，還沒做）：其他縣市的官方樓高

作者：「所以其他縣市沒有官方資料嗎 再仔細找找」。本串壓縮兩次後停手，交下一串做。

- 要找的地方：各市開放資料平臺（高雄、桃園、臺中、臺南、新竹、基隆等）的建管處使用執照／建造執照、
  三維城市模型（高雄、桃園、臺中都有 3D 城市計畫，看授權與能否下載）、內政部營建署建管 e 化「使用執照公開查詢」、
  TGOS（雲端 curl 403，改用 web-fetch）、國土測繪雲開放項目、都發局 GIS；臺南用地號＋地籍圖、臺中用建照套繪或地號。
- 每個縣市寫：找到什麼、授權（能不能商用）、能不能對到輪廓；能用的就實作。
- 目前知道的：臺南使用執照（data.gov.tw 121026）只有地段地號；臺中建築執照存根（108507）沒地址、筆數少；
  高雄、桃園還沒找到；國土測繪中心三維建物付費且不能轉散布（決策 1011 §2）。
- 門牌坐標不是問題：Overture addresses 主題有全台 1,015 萬筆（OpenAddresses `tw/<縣市>/regionwide`，每個縣市都有），
  只要找到「門牌地址＋地上層數（最好有高度）」的資料，就在 `usage_permits.py` 加一個讀檔函式、把縣市加進 `DATASETS`
  跑 `apply`（同樣只在 main 的未處理檔上跑一次）。結果另寫決策或補進決策 1011。
