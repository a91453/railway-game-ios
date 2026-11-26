# FINLAND-MML-BUILDINGS 交接（決策 1009）

2026-11-26，分支 `claude/project-thread-b5jxfx`（PR #2729，決策 1009 與 1011）。存檔、golden、GameCore 不動。

## 進度

- 做到：工具（`tools/rovaniemi-map/mml_buildings.py`、`build_rovaniemi_buildings.py` 改寫）、羅瓦涅米包 `buildings.pmtiles`
  （舊格式 `footprints/2`）、`StoreysFrom.mml`、資料來源畫面、測試、決策 1009。
- 已驗證（Linux 本機）：`swift build --build-tests -Xswiftc -warnings-as-errors` 無警告；RovaniemiBuildingsTests、
  RovaniemiRailwaysTests、Map3DFootprintsTests、DataSourceCredits*、Map3DMapLoadReport 全過；`doc_numbers.py --check` 過。

## 瘦身之後（已做，2026-11-26）

1. #2725（決策 1005）合併後併了 main。羅瓦涅米 `buildings.pmtiles` 用 `tools/basemap/slim_tiles.py buildings` 轉成
   `footprints/3`（1,059,876 → 937,780 bytes；MML 原始檔已不在容器，轉檔和工具現在寫的一樣），
   `build_rovaniemi_buildings.py` 的 metadata 改用 `tiles.WRITTEN_EXTENT`，`rovaniemi_buildings.json` 的大小與雜湊跟著改。
2. 再跑一次 `finland_census_grid.py fetch`、`build`（住 69,768、上班 28,534，`population.json` 127,023 bytes）與
   `write_manifest`（`pack.json`）。
3. 台灣檔從 `main` 的 `footprints/3` 檔重跑 `usage_permits.py apply`（所有來源一次），決策 1011 §4 的數字跟著改。

## 第二張：台灣官方樓高（決策 1011，同一張 PR）

- 做到：`tools/overture-footprint-tiles/usage_permits.py`（新北、臺北使用執照的地上層數，用兩市門牌坐標對到輪廓），
  內建 `taiwan_buildings.pmtiles` 改了 11,138 棟（仍是 `footprints/2`）、署名（`buildingStoreys`）、測試（林口）、決策 1011。
- 已驗證（Linux 本機）：build 無警告；Map3DFootprintsTests、RealRailwaysTests、DataSourceCredit*、Map3DFrontageTests、
  Map3DRealFacadeReportTests、ScreenshotSceneTests 全過。
- 之後要重跑（執照、實價登錄更新）：`git show origin/main:RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles > main.pmtiles`
  是 #2729 合併後已經改過的檔；要從頭跑得用它合併前的版本（`git show <#2729 合併前的 main>:…`），**不要對已經跑過的檔再跑**。
- 還沒做：臺南（只有地號）、臺中（存根沒有地址）、高雄、桃園（沒找到）。國土測繪中心三維建物不能用（決策 1011 §2）。

## 第三張：其他縣市的官方樓高（2026-11-26 下一串做完，同一張 PR）

- 查過全國開放資料目錄與各縣市平臺，結果在決策 1011 §2：**臺南**（使用執照＋宗地地號坐標）與**新竹市**（使用執照＋門牌）
  接上了；臺中本來就用市府建物圖；高雄、桃園、新竹縣與其他縣市沒有開放的使用執照，改用**內政部實價登錄**的總樓層數
  （18703，全台門牌坐標對輪廓），再改 268,659 棟。
- `usage_permits.py`：`addresses` 現在抓全台 18 縣市的門牌（約 3 分鐘）；新的 `registry registry.tsv.gz` 抓 101 年起每季
  實價登錄（約 8 分鐘，只留門牌與總樓層數）；`apply <檔> <輸出> <報告> addresses=… ntpc=… taipei=… hsinchu=…
  tainan=<執照夾>:<地號夾> registry=registry.tsv.gz` 一次從 `main` 的檔跑（約 5 分鐘）。內建檔是從瘦身後 `main` 的
  `footprints/3` 檔跑一次的結果，293,269 棟。
- 新竹市執照與高雄統計表在 `a91453/railway-reference-private` PR #164（Mac 下載，雲端連不上新竹網站）。臺南兩份從
  data.tainan.gov.tw 直接抓（各 13、37 個 CSV，網址在 data.gov.tw 121026、176361 的資料集頁）。
- 遠景三角形預算已修（下一節），CI 綠了就合 #2729。

## 遠景預算（2026-11-26，已修）

`Map3DFarViewTests.testTheFarthestViewOfTaipeiIsWithinBudget` 曾經紅：實價登錄讓臺北多了真的高樓，12 km 外畫
1,026,195 個三角形，預算 1,000,000。改成遠處（正上往下看）建物的樓高只算透視露出的那部分
（`Map3DFarDetail.heightSeen` 0.755），12 km 臺北降到 955,698；預算與 `slope` 都沒動。寫在決策 709 最後一段。
