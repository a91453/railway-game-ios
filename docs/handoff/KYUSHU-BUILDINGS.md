# KYUSHU-BUILDINGS 交接（決策 1001）

2026-11-26，分支 `claude/project-thread-0knzs9`（從 #2719 長崎包的 head 開）。存檔、golden、GameCore 不動。

## 進度

- 做到：工具、測試、決策做完，四包建物試做版 359 萬棟（54.9 MB）進了分支；等 #2719 與瘦身串合併。
- 已驗證（Linux 本機）：swift build 無警告；FukuokaBuildings、FukuokaGround、FukuokaRailways、MapPackDownloads、DataSourceCredits、
  Map3DMapLoadReport、RealUnderground、SharedStationLayout、HongKongRailways 全過；doc_numbers --check 過。
- 下一步第一個指令：`git fetch origin main && git merge origin/main`，再照 README 建物步驟重生（PLATEAU 資料要重抓約 40 分鐘，
  暫存資料夾不會留）。

## 狀態

- 工具、測試、資料來源畫面、決策都做好了；四包的 `buildings.pmtiles` 是試做版（舊精度 `footprints/2`）。
- **要等兩張先合**：#2719（長崎包，重做整個日本地面）與「縮小地圖包下載大小」那串的 PR（建物圖磚改 `footprints/3`，
  `tools/basemap/slim_tiles.py` 在 `overseas_buildings.make` 寫檔前轉）。兩張都合了，併 `main`，照
  `tools/fukuoka-map/README.md` 的建物步驟重生（同一個 session 內 Overture 的 extract、PLATEAU 抓好的資料夾可重用），**只切建物**：
  `split_prefectures.py ... buildings.pmtiles`，不要重寫 `basemap.pmtiles`（會把瘦身的底圖蓋回去）。
- 重生後再跑 `FukuokaBuildingsTests`、`FukuokaGroundTests`、`MapPackDownloadsTests`、`DataSourceCredits*`，
  把決策 1001 §3 的數字換成新的。

## 下一步（同一串接的單）

1. 芬蘭羅瓦涅米換 MML（Maanmittauslaitos）官方建物：外形與樓層用 MML，用途留 OSM（作者 2026-11-26「都行」）。
2. 台灣：查高雄、新北、台南等城市與國土測繪中心有沒有可商用的樓層或 3D 建物（格式的 `nlsc` 已留位）；
   作者「然後都不行最後的替代方案就是overture」，官方優先。
3. 「隨機建物照當地 64 m 人口格生成」已拆到另一串，這裡不做。
