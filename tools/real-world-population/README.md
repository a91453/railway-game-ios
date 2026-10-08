# 實景地圖的人口與地點格網

公司（經營模式）在台灣的實景地圖上建新車站時，運量照車站周邊住了多少人決定，不再一律是「住宅區、每日 10,000 人次」。人口來自 WorldPop 的台灣人口格網，App 打包成 `RailwayGameApp/Resources/RealWorld/taiwan_population.json`，由 `GamePresentation` 的 `PopulationGrid` 讀取。

## 資料

- 來源：WorldPop，Taiwan 2025，constrained，30 角秒（約 1 公里）一格，R2025A v1（DOI [10.5258/SOTON/WP00840](https://doi.org/10.5258/SOTON/WP00840)）。
- 授權：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。遊戲的資料來源畫面（`DataSourceCredits` 的「人口與運量」）已經標示出處、授權與修改方式（每格四捨五入到整數人）。
- 全台合計 23,163,504 人（四捨五入後），28,924 個有人的格子，檔案 159 KB。
- 範圍包含台灣本島、澎湖、金門與馬祖。

`Ci/` 參考也是用人口格網決定需求：LandScan 的 300 公尺格網（`landscan-grid-300m.pmtiles`，畫成它的人口圖層），再由它的伺服器換算成各站運量。格網檔和伺服器都不在快照裡，所以換算比例是這裡自己定的（gap）。

## 換算

- 車站半徑 800 公尺內住的人（大約步行十分鐘）：每格依圓落在它裡面的比例計算，每 50 公尺取一個樣本。
- 每 100 位居民每天 40 人次，四捨五入到 100 人次，最少 100、最多 1,000,000。類型一律是住宅區，玩家之後可以自己改。
- 例子：台北車站約 17,700 人次，板橋約 31,200，中壢約 12,600，平溪 200。
- 方圓 5 公里內完全沒有人的地方，視為格網沒有涵蓋（例如台灣以外的城市），照舊用城市預設的 10,000 人次。

**限制（試作）：**

- 只算居民，沒算上班、上學與觀光的人，所以台北車站這類轉乘、商業中心會偏低，住宅密集的永和、板橋偏高。之後可以用台鐵、北捷公開的各站進出站人數校正比例，或依周邊的商店、辦公、學校與景點加上非居民的運量（下面的地點格網目前只決定類型）。
- 「5 公里內有人」只是近似的國界：廈門靠近金門的一小部分會被當成格網涵蓋，那裡建的站會得到 100 人次左右；台灣深山裡離聚落超過 5 公里的地方，則會用城市預設值。
- 只影響新建的車站。實景示範地圖的車站、舊存檔裡的車站，以及空白地圖上的車站都不變。

## 車站類型（地點格網）

同一個地方建站時，類型（住宅、辦公、商業、景點）照半徑 800 公尺內的地點決定：

- 地點來自 OpenStreetMap（ODbL 1.0），由 `build_place_grid.py` 經 Overpass API 逐區下載、數到人口格網的同一批格子，打包成 `RailwayGameApp/Resources/RealWorld/taiwan_places.json`（256 KB）。2026-10-05 的資料：商店 102,090（含餐廳、咖啡、小吃、市場、酒吧）、辦公 8,614、學校 4,588（含大學、專科）、景點 6,511（景點、博物館、觀景台、動物園、水族館、藝廊、主題樂園）。路和建物以中心點計，同一筆只算一次。
- 判斷：辦公（辦公加學校）、商業、景點三類，各自把附近的數量跟「這麼多居民照全台平均該有多少」比較，但期望值至少 30 間商店、5 間辦公加 3 所學校、1 個景點，免得小村子的幾間店被當成商圈。超過期望最多的一類，達到 1.5 倍就是那一類，否則是住宅區；平手時依辦公、商業、景點的順序。
- 門檻用台灣 544 個真實車站調整過：335 站住宅、130 站商業、57 站景點、22 站辦公。台北車站、西門、公館是商業，市政府是辦公，永安市場、頂溪、板橋是住宅，猴硐、菁桐、十分、平溪、動物園、阿里山、鶯歌是景點。
- 限制：OSM 標得少的地方會判成住宅，例如南港軟體園區（辦公標得少）、新北投（溫泉旅館不算景點）。人數仍照居民計算，類型只改變一天中出發與到達的時段。

## 工業區、公園與農地（分區，決策 93）

實景地圖的土地除了人和地點，還有 OSM 畫成**面積**的三種土地：工業區（`landuse=industrial`）、公園（`leisure=park`）與農地（`landuse=farmland`）。`build_zone_grid.py` 經 Overpass 逐區、逐種下載它們的多邊形，加進 `taiwan_places.json` 的 `zones`：

- 每個人口格（30″）切成 4 × 4 個分區格（7.5″，約 230 × 210 公尺），每個分區格取 4 × 4 = 16 個點，記下有幾點落在那種土地裡（奇偶規則，relation 的內環是洞；同一種土地重疊的地方只算一次）。
- 作法照參考 MapBuilder 的 `fetchAndHandleParks`（Overpass 抓公園、算面積），見 `docs/RAILWAY_REFERENCE_MAPPING.md` 的「實景的工業區、公園與農地（決策 93）」。
- 遊戲裡，一個 64 公尺格的中點所在的分區格至少一半是同一種土地，那格就是那種用途：公園沒有人，工廠與農地有固定的就業，人口只住在沒有分區的格（`LandImport`）。

ZONES_SUMMARY

## 重新產生

```sh
pip install tifffile imagecodecs numpy
curl -LO https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/TWN/v1/1km_ua/constrained/twn_pop_2025_CN_1km_R2025A_UA_v1.tif
python3 tools/real-world-population/build_population_grid.py \
  twn_pop_2025_CN_1km_R2025A_UA_v1.tif \
  RailwayGameApp/Resources/RealWorld/taiwan_population.json
```

地點格網（會向 Overpass 逐區下載，中斷後可接著跑；已下載的區塊放在第二個參數的資料夾裡會直接沿用）：

```sh
python3 tools/real-world-population/build_place_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_population.json \
  osm-tiles/ \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json
```

分區（接在地點之後；第一個參數是地點檔，其他內容原樣保留。Overpass 伺服器忙的時候可以用逗號列出幾個，輪流使用）：

```sh
OVERPASS_URL=https://maps.mail.ru/osm/tools/overpass/api/interpreter,https://overpass.private.coffee/api/interpreter \
python3 tools/real-world-population/build_zone_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json \
  osm-zone-tiles/ \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json
```

人口的腳本只接受 sha256 相符的 GeoTIFF（`eae984f0…`，2026-10-05 下載）。地點會隨 OSM 更新而變，重新產生後要一起更新 `PlaceGridTests` 的總數（分區是 `LandZoneTests` 的面積），並重新檢查真實車站的判斷結果。換成新年份或其他來源時，要一起更新腳本裡的 sha256、`PopulationGridTests` 的總人數與資料來源畫面的文字。
