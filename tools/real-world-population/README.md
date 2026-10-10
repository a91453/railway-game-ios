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

- 地點來自 OpenStreetMap（ODbL 1.0），由 `build_place_grid.py` 數到人口格網的同一批格子，打包成 `RailwayGameApp/Resources/RealWorld/taiwan_places.json`。來源可以是 Overpass API（逐區下載），或一整包台灣的 OSM 檔（決策 93 起打包的資料用這個，和分區同一份）。osmtoday.com 2026-10-06 的台灣檔：商店 101,189（含餐廳、咖啡、小吃、市場、酒吧）、辦公 8,485、學校 4,393（含大學、專科）、景點 6,300（景點、博物館、觀景台、動物園、水族館、藝廊、主題樂園）。路和建物以外框的中心點計，同一筆只算一次。之前 2026-10-05 從 Overpass 抓的是 102,090、8,614、4,588、6,511：金門那一格的範圍蓋到廈門，把廈門的地點也算進來了，整包檔只有台灣。
- 判斷：辦公（辦公加學校）、商業、景點三類，各自把附近的數量跟「這麼多居民照全台平均該有多少」比較，但期望值至少 30 間商店、5 間辦公加 3 所學校、1 個景點，免得小村子的幾間店被當成商圈。超過期望最多的一類，達到 1.5 倍就是那一類，否則是住宅區；平手時依辦公、商業、景點的順序。
- 門檻用台灣 544 個真實車站調整過：335 站住宅、130 站商業、57 站景點、22 站辦公（學校分開之後是 328、107、57、50 與 2 所學校；決策 93 的整包檔是 326、107、58、51、2：機捷台北車站從商業變辦公、中里從住宅變景點、老街溪從住宅變商業）。台北車站、西門、公館是商業，市政府是辦公，永安市場、頂溪、板橋是住宅，猴硐、菁桐、十分、平溪、動物園、阿里山、鶯歌是景點。
- 限制：OSM 標得少的地方會判成住宅，例如南港軟體園區（辦公標得少）、新北投（溫泉旅館不算景點）。人數仍照居民計算，類型只改變一天中出發與到達的時段。

## 工業區、公園與農地（分區，決策 93）

實景地圖的土地除了人和地點，還有 OSM 畫成**面積**的三種土地：工業區（`landuse=industrial`、礦場）、公園（`leisure=park`、高爾夫球場、運動公園）與農地（`landuse=farmland`、果園、魚塭、農舍、溫室、苗圃；決策 96，標籤在 `build_zone_grid.py` 的 `TAGS`）。森林、墓地、軍事區與水域不是用途（決策 96 說明原因）。`build_zone_grid.py` 經 Overpass 逐區、逐種下載它們的多邊形，加進 `taiwan_places.json` 的 `zones`：

- 每個人口格（30″）切成 4 × 4 個分區格（7.5″，約 230 × 210 公尺），每個分區格取 4 × 4 = 16 個點，記下有幾點落在那種土地裡（奇偶規則，relation 的內環是洞；同一種土地重疊的地方只算一次）。
- 作法照參考 MapBuilder 的 `fetchAndHandleParks`（Overpass 抓公園、算面積），見 `docs/RAILWAY_REFERENCE_MAPPING.md` 的「實景的工業區、公園與農地（決策 93）」。
- 遊戲裡，一個 64 公尺格的中點所在的分區格至少一半是同一種土地，那格就是那種用途：公園沒有人，工廠與農地有固定的就業，人口只住在沒有分區的格（`LandImport`）。

2026-10-08 的資料（osmtoday.com 的台灣整包檔，2026-10-06，決策 96 的標籤）：工業區 454.6 km²（8,826 塊）、公園 182.3 km²（8,886 塊）、農地 2,677.6 km²（61,650 塊）；`taiwan_places.json`（地點與分區同一份整包檔）1.17 MB。工廠每格 29 個就業、農地每格 1 個，依製造業約 300 萬人、農業約 53 萬人與分出來的格數（102,817、677,182）定的（決策 93、96）。

## 水域（決策 105）

實景地圖的海、河川與湖泊是 GameCore 的地形層（`GameWorld.terrain`）：水上城鎮不擴張、不升級，玩家建物不能蓋，也不能劃分區。`build_water_grid.py` 從同一份 OSM 整包檔產生 `RailwayGameApp/Resources/RealWorld/taiwan_water.json`（`GamePresentation` 的 `WaterGrid` 讀取）：

- 格網：人口格（30″）切成 16 × 16 個水域格（1.875″，約 58 × 53 公尺，大約一個 64 公尺格），範圍是台灣的陸地（本島、澎湖、金門、馬祖與小島）外加 0.1°；一格的中點在水裡就是水。檔案寫每一列有水的段：`[列, 起始欄, 長度, 間隔, 長度, …]`。
- 海：`natural=coastline` 的 way 頭尾接成環，環外（奇偶規則）是海。被整包檔邊界切斷、接不成環的一段（金門北邊的中國大嶝島）不是台灣的，不算。整包檔只有台灣，所以範圍內對岸（廈門、連江）的陸地也算海；那裡 WorldPop 本來就沒有人。
- 河湖：`natural=water`、`waterway=riverbank`、`waterway=dock`、`landuse=reservoir` 的面，內環是島；魚塭（`landuse=aquaculture`、`water=fishpond`）不算，決策 96 把它當農業。海灣、濕地、鹽田、滯洪池與河床的礫石不算。
- 參考庫內政部的海岸線（`Railway/site_archive_clean/data/taiwan_land.json`，縣市界合併、約 150 公尺簡化，政府資料開放授權 1.0）可以當第四個參數，只用來核對：它畫到低潮線，彰化、雲林、嘉義、台南的潮間帶與金門的潮灘算陸地。

2026-10-09 的資料（osmtoday.com 2026-10-06 的整包檔）：9,296 × 8,064 格、82,806 段、530 KB；704 個海岸線的環（1 個被切斷、不算）、44,102 個水體；陸地 36,381.6 km²、陸地上的河湖 798.4 km²。和內政部的海岸線比：99.79% 的格一致，內政部算陸地、OSM 算海的 434.5 km²，反過來 53.1 km²。約 30 秒，需要 pyosmium 與 numpy。

## 陡坡（決策 115）

坡度超過 30% 的乾格是陡坡（建築技術規則建築設計施工編第 262 條：山坡地平均坡度超過 30% 的部分不得開發建築）：城市不在上面擴張或升級，玩家建物與分區都不行；已有的土地照舊。`build_slope_grid.py` 把它加進同一個 `taiwan_water.json` 的 `"steep"`（和 `"water"` 同樣的格式；同一個檔，App 的資源與 Xcode 專案不必改）：

- 高度：Copernicus DEM GLO-30（1″，約 30 m；馬祖 N26 E119 那一塊只有 GLO-90，3″），公開的 `copernicus-dem-30m`、`copernicus-dem-90m` S3 bucket，授權要求標示出處（資料來源畫面已列）。內政部 20 m 數值地形模型的下載站（tgos.tw）在雲端環境回 403，而且沒有金門、馬祖。
- 每個水域格取中點的高度；3 × 3 中位數（約 170 m）去掉地表模型裡的高樓與樹；坡度是東西、南北跨兩格的中央差分較陡的一個；超過 30%、而且周圍 3 × 3 至少 5 格也是，才算陡坡。水不算。
- 2026-10-09 的資料：陸地 35,583 km² 中 17,059 km² 是陡坡（326,886 段），`taiwan_water.json` 530 KB → 2.1 MB。台北、台中、高雄市中心 0–0.1%，九份 55%，陽明山 41%，玉山 95%。

## 地面高度（決策 124）

同一次執行給第四個參數，就把同樣的中位數高度（四捨五入到公尺）寫成 `taiwan_heights.dat`：和水域同一個 1.875″ 格網。決策 132 起，中位數取在水還在的 DEM 上：離乾地 8 格（約 450 m）內的水（河、湖、岸邊）是它的水面高度（不低於 0），外海、對岸的大陸（台灣的 OSM 整包把它當水）與沒有圖磚的地方是 0（海面）；陡坡照舊以水為 0 計算，`taiwan_water.json` 不變。之前所有的水都是 0，山裡的每條河都是一個坑（例如十分附近 180 m 的溪讀成 0 m，橋高超過 64 m 而蓋不了）。每一列各自以「和前一格的差」存成 varint，連續的 0 另外記長度，所以 App 只解它要的列（`HeightGrid`）；檔案格式寫在 `build_slope_grid.py` 的說明裡。

- 2026-10-09 的資料：11,643,079 個乾格，−9 到 3,901 m，11,990,289 bytes（壓縮成 zip 約 8.4 MB，App Store 的下載會再壓縮）。阿里山車站 2,221 m（實際 2,216 m），合歡山武嶺 3,270 m（3,275 m），玉山 3,901 m（3,952 m，3 × 3 中位數把山頂削平）。
- 已知的偏差：Copernicus 是地表模型（含建物），3 × 3 中位數去不完密集的市區，台北車站一帶讀成約 20 m（實際約 7 m）。只影響市中心的絕對高度；軌道與地面的高差（下一步的規則）用的是同一份資料，所以整片市區一起偏高時不受影響。
- 3.75″ 的格網只要約 3.4 MB，但雙線性內插對 1.875″ 的平均誤差 4.8 m、p95 15 m，和路堤／高架、路塹／隧道的分界同一個量級，所以不採用（`docs/research/TERRAIN_HEIGHT_DESIGN.md` 第 4 節）。

## 建物量測（只量測，App 不讀）

`build_building_grid.py` 從同一份 OSM 整包檔，在水域的格網上（約 58 × 53 m）算每格的建物足跡、樓層與建地重心，再比對人口格網與十幾個地方，寫成一份量測 JSON（不提交）。結果與結論在 `docs/research/OSM_BUILDING_SURVEY.md`：OSM 的建物只在台北、台南、花蓮的市區比較完整，大約一半的人住在建物明顯不完整的地方，所以還不能直接拿來決定實景地圖的城市建物。指令寫在那份報告的最後。

`build_overture_building_grid.py` 用 DuckDB 從 Overture Maps 的公開 bucket 只讀台灣範圍的 buildings（約 35 秒，190 MB），再用同一個格網與同一份彙整（`build_building_grid.py` 的 `survey()`）量一次。結果在同一份報告的「Overture Maps」：Overture 的足跡（OSM 加上 Shi 等人以影像擷取的 East Asian buildings，CC BY 4.0）在全台大致完整，但樓層全是 OSM 的，只有約 4% 的建物有。

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

用整包檔時把 `osm-tiles/` 換成 `taiwan.pbf`（需要 pyosmium，約 1 分鐘）。這會重寫整個地點檔，所以之後要再跑一次下面的分區。

分區（接在地點之後；第一個參數是地點檔，其他內容原樣保留）。最快的是一整包台灣的 OSM 檔，約 20 秒，需要 pyosmium（`pip install osmium`，BSD 2-Clause；只有這個用法需要）：

```sh
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 tools/real-world-population/build_zone_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json \
  taiwan.pbf \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json
```

水域（第一個參數是人口檔，只用它的格網；第四個參數可以省略）：

```sh
python3 tools/real-world-population/build_water_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_population.json \
  taiwan.pbf \
  RailwayGameApp/Resources/RealWorld/taiwan_water.json \
  taiwan_land.json
```

重新產生水域後要一起更新 `WaterGridTests` 的格數與地圖的數字。水域重新產生會蓋掉陡坡，所以之後要再跑一次陡坡（Copernicus 的圖磚放在一個資料夾，約 260 MB；第一個參數是水域檔，其他內容原樣保留，約 1 分鐘，需要 `pip install tifffile imagecodecs numpy`）：

```sh
for t in N21_00_E120 N22_00_E120 N22_00_E121 N23_00_E119 N23_00_E120 N23_00_E121 N24_00_E118 N24_00_E120 N24_00_E121 N25_00_E119 N25_00_E121 N26_00_E120; do
  n=Copernicus_DSM_COG_10_${t}_00_DEM; curl -o copernicus-dem/$n.tif https://copernicus-dem-30m.s3.amazonaws.com/$n/$n.tif
done
for t in N24_00_E119 N26_00_E119; do
  n=Copernicus_DSM_COG_30_${t}_00_DEM; curl -o copernicus-dem/$n.tif https://copernicus-dem-90m.s3.amazonaws.com/$n/$n.tif
done
python3 tools/real-world-population/build_slope_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_water.json \
  copernicus-dem/ \
  RailwayGameApp/Resources/RealWorld/taiwan_water.json \
  RailwayGameApp/Resources/RealWorld/taiwan_heights.dat
```

重新產生高度後要一起更新 `HeightGridTests` 的數字。

沒有整包檔時也可以問 Overpass（只用 Python 內建模組；伺服器忙的時候可以用逗號列出幾個，輪流使用，一塊一直失敗會切成四小塊再問，可能要幾個小時）：

```sh
OVERPASS_URL=https://maps.mail.ru/osm/tools/overpass/api/interpreter,https://overpass.private.coffee/api/interpreter \
python3 tools/real-world-population/build_zone_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json \
  osm-zone-tiles/ \
  RailwayGameApp/Resources/RealWorld/taiwan_places.json
```

人口的腳本只接受 sha256 相符的 GeoTIFF（`eae984f0…`，2026-10-05 下載）。地點會隨 OSM 更新而變，重新產生後要一起更新 `PlaceGridTests` 的總數（分區是 `LandZoneTests` 的面積），並重新檢查真實車站的判斷結果。換成新年份或其他來源時，要一起更新腳本裡的 sha256、`PopulationGridTests` 的總人數與資料來源畫面的文字。
