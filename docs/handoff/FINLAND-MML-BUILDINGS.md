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

## 第三張：其他縣市的官方樓高（2026-11-26 下一串做完，同一張 PR）

- 查過全國開放資料目錄與各縣市平臺，結果在決策 1011 §2：**臺南**（使用執照＋宗地地號坐標）與**新竹市**（使用執照＋門牌）
  接上了；臺中本來就用市府建物圖；高雄、桃園、新竹縣與其他縣市沒有開放的使用執照，改用**內政部實價登錄**的總樓層數
  （18703，全台門牌坐標對輪廓），再改 268,659 棟。
- `usage_permits.py`：`addresses` 現在抓全台 18 縣市的門牌（約 3 分鐘）；新的 `registry registry.tsv.gz` 抓 101 年起每季
  實價登錄（約 8 分鐘，只留門牌與總樓層數）；`apply <檔> <輸出> <報告> addresses=… ntpc=… taipei=… hsinchu=…
  tainan=<執照夾>:<地號夾> registry=registry.tsv.gz` 一次從 `main` 的檔跑（約 5 分鐘）。內建檔已換成從 `main`（瘦身前）
  跑一次的結果，293,257 棟。
- 新竹市執照與高雄統計表在 `a91453/railway-reference-private` PR #164（Mac 下載，雲端連不上新竹網站）。臺南兩份從
  data.tainan.gov.tw 直接抓（各 13、37 個 CSV，網址在 data.gov.tw 121026、176361 的資料集頁）。
- 瘦身串合併後重生時，四市一起跑一次（第二張那段的「不要對已經跑過的檔再跑」照舊），報告與決策 1011 §4 的數字跟著改。
