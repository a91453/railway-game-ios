# 實景地圖的人口格網

公司（經營模式）在台灣的實景地圖上建新車站時，客流照車站周邊住了多少人決定，不再一律是「住宅區、每日 10,000 人次」。人口來自 WorldPop 的台灣人口格網，App 打包成 `RailwayGameApp/Resources/RealWorld/taiwan_population.json`，由 `GamePresentation` 的 `PopulationGrid` 讀取。

## 資料

- 來源：WorldPop，Taiwan 2025，constrained，30 角秒（約 1 公里）一格，R2025A v1（DOI [10.5258/SOTON/WP00840](https://doi.org/10.5258/SOTON/WP00840)）。
- 授權：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。遊戲的資料來源畫面（`DataSourceCredits` 的「實景地圖的車站客流」）已經標示出處、授權與修改方式（每格四捨五入到整數人）。
- 全台合計 23,163,504 人（四捨五入後），28,924 個有人的格子，檔案 159 KB。
- 範圍包含台灣本島、澎湖、金門與馬祖。

`Ci/` 參考也是用人口格網決定需求：LandScan 的 300 公尺格網（`landscan-grid-300m.pmtiles`，畫成它的人口圖層），再由它的伺服器換算成各站客流。格網檔和伺服器都不在快照裡，所以換算比例是這裡自己定的（gap）。

## 換算

- 車站半徑 800 公尺內住的人（大約步行十分鐘）：每格依圓落在它裡面的比例計算，每 50 公尺取一個樣本。
- 每 100 位居民每天 40 人次，四捨五入到 100 人次，最少 100、最多 1,000,000。類型一律是住宅區，玩家之後可以自己改。
- 例子：台北車站約 17,700 人次，板橋約 31,200，中壢約 12,600，平溪 200。
- 方圓 5 公里內完全沒有人的地方，視為格網沒有涵蓋（例如台灣以外的城市），照舊用城市預設的 10,000 人次。

**限制（試作）：**

- 只算居民，沒算上班、上學與觀光的人，所以台北車站這類轉乘、商業中心會偏低，住宅密集的永和、板橋偏高。之後可以用台鐵、北捷公開的各站進出站人數校正比例，或用 OSM 判斷住宅、辦公、商業、景點的類型。
- 「5 公里內有人」只是近似的國界：廈門靠近金門的一小部分會被當成格網涵蓋，那裡建的站會得到 100 人次左右；台灣深山裡離聚落超過 5 公里的地方，則會用城市預設值。
- 只影響新建的車站。實景示範地圖的車站、舊存檔裡的車站，以及空白地圖上的車站都不變。

## 重新產生

```sh
pip install tifffile imagecodecs numpy
curl -LO https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/TWN/v1/1km_ua/constrained/twn_pop_2025_CN_1km_R2025A_UA_v1.tif
python3 tools/real-world-population/build_population_grid.py \
  twn_pop_2025_CN_1km_R2025A_UA_v1.tif \
  RailwayGameApp/Resources/RealWorld/taiwan_population.json
```

腳本只接受 sha256 相符的 GeoTIFF（`eae984f0…`，2026-10-05 下載）。換成新年份或其他來源時，要一起更新腳本裡的 sha256、`PopulationGridTests` 的總人數與資料來源畫面的文字。
