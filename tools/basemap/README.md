# 台灣的 OSM 底圖（決策 151）

實景地圖的 OpenStreetMap 底圖在台灣用遊戲自己的向量圖磚：`RailwayGameApp/Resources/BaseMap/taiwan.pmtiles`，和實景地圖的水域、分區、地點（`tools/real-world-population/`）讀同一份 osmtoday.com 的台灣整包檔，所以底圖畫的海、河、公園和遊戲的地形、分區是同一份 OSM；隨 App 打包，不用網路。樣式是遊戲自己的（`Sources/GamePresentation/BaseMapStyle.swift`），台灣以外照舊用 OpenFreeMap 的圖磚、套同一份樣式。

## 圖磚

`build_basemap.py` 用 pyosmium（BSD 2-Clause，作者同意的資料工具依賴，決策 93）讀整包檔，切成 zoom 0–14 的 Mapbox Vector Tiles，寫成 PMTiles v3。圖層照 OpenMapTiles schema 的一部分（圖層名、`class` 與欄位；CC BY 4.0，地圖上標「© OpenMapTiles」），所以同一份樣式也畫得了 OpenFreeMap 的圖磚：

| 圖層 | 內容 | 從哪個 zoom |
| --- | --- | --- |
| `water` | 海（台灣陸地外 2° 的框，海岸線的環是洞）、湖泊、水庫、河面、船塢；魚塭不是水（決策 96） | 海 0；湖依面積 6–13 |
| `waterway` | 河 8、運河 12、溪流 13；沒有排水溝 | 8 |
| `landcover` | 森林、草地與灌叢、濕地、沙灘；沒有農地（遊戲的分區畫） | 依面積 7–12 |
| `park` | 國家公園 6、自然保留區、公園（依面積） | 6 |
| `boundary` | 縣市（admin_level 4）5、鄉鎮市區（7）10，`maritime` | 5 |
| `transportation` | 國道 5、快速道路 6、省道等主要道路 8、次要 9、三級 11、一般道路 13、服務道路 14（沒有停車場與車道）；匝道 9 起；`brunnel` | 5 |
| `transportation_name` | 路名與編號（多簡化四倍，只用來排字） | 10–14 |
| `place` | 直轄市與市 4、縣 7、鄉鎮 8、區 11、村里 12、聚落 13–14、島 | 4 |

沒有建物（遊戲畫自己的城市，決策 126）、土地使用（遊戲的分區）、興趣點與鐵道（遊戲畫真實鐵道），所以也沒有軍事設施的標示。

切法照 geojson-vt（ISC，Copyright (c) 2015, Mapbox）：每個圖形的點先排一次簡化的順序，再由上一層的圖磚切成四塊、留 64 單位的邊；移植成 Python。MVT 2.1 與 PMTiles v3 的編碼都用標準函式庫寫在同一個檔裡。zoom 7 以下各塊交給工作行程，四核心約 3.5 分鐘。

## 字型

`fetch_glyphs.py` 下載 OpenFreeMap 的字型 glyph（OpenMapTiles 版的 Noto Sans，SIL Open Font License 1.1，授權條款在 `Resources/Licenses/NotoSans-OFL.txt`；參考庫 `Ci/reference_snapshot/external/openfreemap-tiles/fonts/` 的三個檔逐位元相同）。MapLibre Native 用裝置的字型畫中文、假名與諺文，不會要那些範圍；其他範圍裡，地名用到的拉丁字母、標點與符號是真的 glyph，其餘是空的檔：MapLibre 等不到某個範圍時，整塊圖磚的文字都不排，所以意料外的文字也要有檔可讀（空的檔只少那幾個字）。`build_basemap.py` 最後會列出地名用到哪些範圍。

## 山的陰影

`build_terrain.py` 把遊戲的地面高度（`Resources/RealWorld/taiwan_heights.dat`，決策 124）寫成 `Resources/BaseMap/taiwan_terrain.pmtiles`：Terrarium 編碼（高度 = 紅 × 256 + 綠 + 藍 ÷ 256 − 32768 公尺）的 512 像素 PNG，zoom 0–10，只寫有陸地的圖磚。照 `Railway/` 網站的 `rail-3d/integration/map3d.js`（`raster-dem` 加 `hillshade`）。陰影和遊戲判斷路堤、隧道的高度是同一份資料。需要 numpy，約 1 分鐘；2026-10-10：115 塊、10.0 MB。

## 重新產生

```sh
pip install osmium
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 tools/basemap/build_basemap.py taiwan.pbf RailwayGameApp/Resources/BaseMap/taiwan.pmtiles
python3 tools/basemap/fetch_glyphs.py RailwayGameApp/Resources/BaseMap/fonts
python3 tools/basemap/build_terrain.py RailwayGameApp/Resources/RealWorld/taiwan_heights.dat RailwayGameApp/Resources/BaseMap/taiwan_terrain.pmtiles
```

`build_basemap.py` 需要 `tools/real-world-population/build_water_grid.py`（海岸線接成環的方法）。換了圖層、`class` 或欄位時，同時改 `BaseMapStyle` 與 `BaseMapStyleTests`。

## 2026-10-10 的資料

osmtoday.com 2026-10-10 下載的台灣檔（OSM 資料到 2026-10-08；水域、分區與地點是 2026-10-06 的檔）：988,019 筆圖形，接起來是 815,812 筆；海岸線 704 個島（1 段被整包檔切斷、不算）。353,695 塊圖磚、12,340 種不同的內容（大部分是整塊的海），檔案 47.4 MB；字型 15 個有 glyph 的範圍與 179 個空的，1.19 MB。

**限制**：整包檔只有台灣，所以金門、馬祖對岸（廈門、連江）的陸地畫成海，和水域格網（決策 105）一致；廈門的實景地圖用 OpenFreeMap 的圖磚（`BaseMapStyle.drawsTaiwan`）。
