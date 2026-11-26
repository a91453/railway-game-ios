# KYUSHU-BUILDINGS 交接（決策 1001）

2026-11-26，分支 `claude/project-thread-0knzs9`，PR #2721。存檔、golden、GameCore 不動。

## 做了什麼

- 日本四包的 `buildings.pmtiles` 疊上 PLATEAU 官方建物與實測高度，最後才 Overture：197 萬 → 359 萬棟，113 萬棟用實測樓層，
  四份 47.5 MB（決策 1005 的 `footprints/3`）。併了 #2719（長崎包）與決策 1005（瘦身）之後重生，只切建物，底圖沒動。
- 已驗證（Linux 本機）：swift build 無警告；FukuokaBuildings、FukuokaGround、FukuokaRailways、MapPackDownloads、DataSourceCredits、
  OverseasStartLand、MapPackExtents 全過；doc_numbers --check 過。
- UNVERIFIED：實機上建物多了約八成之後的載入速度與記憶體（發版後實機看）。

## 還留下的（另開新串）

1. 芬蘭羅瓦涅米換 MML（Maanmittauslaitos）官方建物：外形與樓層用 MML，用途留 OSM（作者 2026-11-26「都行」）。
   `overseas_buildings.make` 的 `plateau=` 這一層（`added_where_none`、`measured_by_building`）可以直接拿來疊官方建物。
2. 台灣：查高雄、新北、台南等城市與國土測繪中心有沒有可商用的樓層或 3D 建物（格式的 `nlsc` 已留位）；
   作者「然後都不行最後的替代方案就是overture」，官方優先。
3. 「隨機建物照當地 64 m 人口格生成」已拆到另一串。
