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

## 其他地方

台灣、芬蘭的下一步寫在 `docs/handoff/JAPAN-CENSUS-GRID.md`。新的國家照這裡的格式寫一支 `<地方>_census_grid.py`，
遊戲端不用改。
