# 普查網格：住的人與上班的人（決策 1000）

把各國官方普查的「住在哪裡」與「在哪裡上班」做成地圖包的 `population.json`，格式和 `taiwan_population.json` 一樣
（`PopulationGrid`），多一個選填的 `jobs`：

```json
{"north": 34.03125, "west": 129.73125, "cellDegrees": 0.00208333,
 "runs": [{"r": 0, "c": 12, "p": [3, 3, 2]}],
 "jobs": {"office": [...], "shop": [...], "civic": [...], "leisure": [...]}}
```

- `runs`：住的人；`jobs` 四層：辦公、商店、學校與公家、休閒（`LandImport` 的四種用途）。四層和 `runs` 同一個格網。
- 有 `jobs` 的格網，遊戲開局時用它決定每個 64 m 小格的上班人數與用途，不讀 OSM 的 places。
- 格子一律是**緯度、經度一樣大的正方格**（遊戲讀人口格的程式與 `grid_box` 都這樣假設），西北角對齊 WorldPop 30″ 的格線。

## 日本：`japan_census_grid.py`

| 表 | statsId |
|---|---|
| 令和 2 年國勢調查 人口及び世帯（JGD2011），500 m 網格 | `T001141` |
| 令和 3 年經濟普查‐活動調查 產業（大分類）別事業所數及從業者數（JGD2011），500 m 網格 | `T001162` |

```sh
# 1. 下載範圍碰到的每個 1 次網格（80 km）的兩張表（福岡到長崎 12 格、約 3.5 MB）
python3 -I tools/census-grid/japan_census_grid.py fetch RailwayGameApp/Resources/MapPacks/fukuoka /tmp/estat
# 2. 寫 population.json（範圍讀 pack.json 的 extent），並把讀了哪些檔、sha256、總數寫進 japan_sources.json
python3 -I tools/census-grid/japan_census_grid.py build /tmp/estat RailwayGameApp/Resources/MapPacks/fukuoka \
  --compare RailwayGameApp/Resources/MapPacks/fukuoka/population.json
```

- 500 m 網格是 15″ × 22.5″，剛好 2 × 3 個 7.5″ 正方格；每格的人平均分給 6 格，餘數給西北邊的前幾格。
- 國勢調查人少的格子會把細項併到鄰格（秘匿），但「人口總數」每格都有，照用。
- 上班人數（従業者数，含公部門）：商店＝I＋M，學校與公家＝O＋P＋S，休閒＝N，辦公＝總數減掉以上。
- 授權：政府統計の総合窓口（e-Stat）利用規約（政府標準利用規約 2.0，和 CC BY 4.0 相容，可商用）。
  署名：「令和2年国勢調査」「令和3年経済センサス‐活動調査」（総務省統計局）（政府統計の総合窓口（e-Stat））を加工して作成。

## 芬蘭：`finland_census_grid.py`（決策 1007）

芬蘭統計局的 250 m 格與上班格網（Ruututietokanta）是付費、不能轉發的，所以只用它的開放資料（CC BY 4.0，WFS
`geo.stat.fi`，雲端連得到）：

| 層 | 內容 |
|---|---|
| `vaestoruutu:vaki2025_1km` | 1 km 人口格 2025（2024 年底的住民，`vaesto`；人少的格也有總數），ETRS-TM35FIN |
| `postialue:pno_tilasto_2025` | 郵遞區統計 Paavo 2025：工作人數 `tp_tyopy` 與各行業（TOL 2008） |

```sh
pip install shapely numpy
python3 -I tools/census-grid/finland_census_grid.py fetch RailwayGameApp/Resources/MapPacks/rovaniemi /tmp/statfin
python3 -I tools/census-grid/finland_census_grid.py build /tmp/statfin RailwayGameApp/Resources/MapPacks/rovaniemi \
  --compare <舊的 population.json>
```

- 格子和日本一樣是 7.5″ 正方格（羅瓦涅米約 231 × 93 m）。
- 住的人：每個 1 km 格的人，照格內住宅（OSM 的 residential 與沒標的 `building=yes`）的樓地板面積（包內 `buildings.pmtiles`
  的外框 × 樓層）分到 7.5″ 格；沒有住宅就照所有建物，都沒有就平均。最大餘數法取整，每個 1 km 格總數不變。
- 上班的人：商店＝G 批發零售＋I 住宿餐飲；學校與公家＝O 公務＋P 教育＋Q 醫療社福；休閒＝R 藝文娛樂＋S 其他服務；
  辦公＝總數減掉以上。每個郵遞區每種工作的八成照那一類建物的樓地板分、兩成照所有建物分。郵遞區跨出地圖的，
  只留「區內住在地圖裡的人」占「區內全部住民」那個比例的工作。
- 讀了哪些檔、sha256、每個郵遞區留了多少寫在 `finland_sources.json`。

## 其他地方

台灣、香港的下一步寫在 `docs/handoff/JAPAN-CENSUS-GRID.md`。新的國家照這裡的格式寫一支 `<地方>_census_grid.py`，
遊戲端不用改。
