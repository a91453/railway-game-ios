# 普查網格：住的人與上班的人（決策 1000、1002、1007）

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

## 台灣：`taiwan_census_grid.py`（決策 1002）

寫的是 App 的 `RailwayGameApp/Resources/RealWorld/taiwan_population.json`（不是地圖包）。7.5″ 格、西北角和
`taiwan_places.json` 一樣，所以每格剛好是一個分區格（決策 93），也是 4 × 4 個水域格（1.875″）。

| 資料 | 出處 | 用在 |
|---|---|---|
| 統計區人口統計_最小統計區（113 年 12 月，戶籍） | 內政部統計處，data.gov.tw 18681（SEGIS，只有台灣連得上） | 住的人，157,933 區 |
| 最小統計區圖（2015） | 內政部統計處，data.gov.tw 25128 | 每區的邊界（TWD97 TM2） |
| 109 年人口及住宅普查 常住人口 | 主計總處，data.gov.tw 18447–18521（各縣市） | 各鄉鎮的人從戶籍換成實際住的 |
| 村里戶數、單一年齡人口（109 年 12 月） | 內政部戶政司，data.gov.tw 77132 | 上一列的分母 |
| 110 年工業及服務業普查 從業員工 | 主計總處，data.gov.tw 15706–15729（各縣市） | 上班的人（各鄉鎮總數） |

全部是**政府資料開放授權條款第 1 版**（可商用，要寫出處）。SEGIS 的「工商家數」細格表沒寫授權，沒用。

```sh
# 1. 抓雲端抓得到的（邊界、普查、戶籍，約 70 MB）
python3 -I tools/census-grid/taiwan_census_grid.py fetch /tmp/tw
#    SEGIS 的 22 個檔從 a91453/railway-reference-private Railway/segis-snapshot-2026-11/population/ 複製到 /tmp/tw/segis/
# 2. 先算住的人（第二個參數 - 表示還沒有地點），當成數地點的格網
python3 -I tools/census-grid/taiwan_census_grid.py build /tmp/tw - /tmp/tw-residents.json
# 3. 照 7.5″ 數 OSM 的店家、辦公室、學校、景點（Overpass 逐區，約 1 小時；有整包 taiwan.pbf 時約 1 分鐘）
python3 tools/real-world-population/build_place_grid.py /tmp/tw-residents.json /tmp/osm75 /tmp/places75.json
# 4. 寫 App 的檔，並把讀了哪些檔、sha256、各鄉鎮的換算比寫進 taiwan_sources.json
python3 -I tools/census-grid/taiwan_census_grid.py build /tmp/tw /tmp/places75.json \
  RailwayGameApp/Resources/RealWorld/taiwan_population.json
```

- **住的人**：每區的人照建物覆蓋（`taiwan_coverage.dat`，決策 147）分到區內的水域格（1.875″），沒有建物的區平均分；
  分區是公園或工業區的格子不住人（遊戲本來就不在那裡蓋住家），除非整區都是。再按鄉鎮乘「109 年常住 ÷ 戶籍」
  （金門金城約 0.46、竹北約 1.11、高雄燕巢約 1.56），最大餘數法取整，每個鄉鎮總數不變。
- **上班的人**：每個鄉鎮的從業員工照 OSM 地點分：店家 25、辦公室 500、學校 300、景點 50 人（`LandImport.jobsPerPlace`），
  工業區每個 64 m 格 29 人（`office`），公園裡的地點不算；鄉鎮裡什麼都沒標的，照住的人分。
  工商普查不含公務機關、軍隊與農林漁牧，所以全台約 966 萬人，比舊的 OSM 估算（約 1,200 萬）少；農地仍每格 1 人（遊戲加）。

## 香港：`hongkong_census_grid.py`（決策 1008）

| 資料 | 用途 |
|---|---|
| 2021 年人口普查，單元區小合併組（2,342 個）的總人口與界線（CSDI `censtatd_rcd_1635933365202_19171`） | `runs` |
| 表 215-16009，2021 年各小規劃統計區的就業人數（按行業主要類別，公務員除外） | `jobs` |
| 2021 年小規劃統計區及單元區界線（規劃署，CSDI `pland_rcd_1634022783366_65050`） | 把就業人數放到地上 |
| 2025 年土地利用網格（規劃署，10 m，`tools/hk-map/build_hk_landcover.py fetch` 取的那份） | 人放在住宅用地、工作放在工作用地 |

```sh
pip install numpy pillow osmium
# 1. 下載（約 120 MB，多半是兩份界線）
python3 -I tools/census-grid/hongkong_census_grid.py fetch /tmp/hk-census
# 2. 寫 population.json，讀了哪些檔、sha256、總數寫進 hongkong_sources.json；再更新 pack.json
python3 -I tools/census-grid/hongkong_census_grid.py build /tmp/hk-census RailwayGameApp/Resources/MapPacks/hongkong \
  --compare RailwayGameApp/Resources/MapPacks/hongkong/population.json
python3 -I -c "import sys; sys.path.insert(0, 'tools/hk-map'); import build_hk_mtr; \
  build_hk_mtr.write_manifest('RailwayGameApp/Resources/MapPacks/hongkong')"
```

- 格網和日本一樣是 7.5″ 正方格。每格取 10 × 10 個點，看點落在哪一區、哪一種用地；每區的人與工作按點數分到格子，
  最大餘數四捨五入，每區總數不變。分法、行業分四種的規則寫在工具開頭與決策 1008。
- 上班的人約 260 萬（調查不含公務員、建造地盤、漁農、外傭）。
- 授權：資料一線通（DATA.GOV.HK）與空間數據共享平台（CSDI）的使用條款，可商用，要標出處。
- WorldPop 的舊做法（`tools/hk-map/build_hk_ground.py`）留作備用。

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

日本、台灣、香港、芬蘭的下一步寫在各自的交接（`docs/handoff/JAPAN-CENSUS-GRID.md`、`TAIWAN-CENSUS-GRID.md`）。新的國家照這裡的格式寫一支 `<地方>_census_grid.py`，
遊戲端不用改。
