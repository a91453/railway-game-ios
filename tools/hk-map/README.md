# 香港港鐵的地圖資料（決策 697）

把香港港鐵十條鐵路綫（機場快綫、東涌綫、屯馬綫、東鐵綫、荃灣綫、港島綫、觀塘綫、將軍澳綫、南港島綫、迪士尼綫；輕鐵不在內）做成一個自成一包的地圖包 `RailwayGameApp/Resources/MapPacks/hongkong/`：檔名與格式和台灣的真實鐵道一樣，`pack.json` 列出每個檔的大小與每一部分的來源。研究、來源與授權在 `docs/research/HK_MAP_2026-11-12.md`。

遊戲會讀這一包（`OverseasMaps.open` 有香港，決策 712 第三個 PR 起）；玩家要先開航（一座飛香港的機場一天有 500 人搭自己的列車）才能在選地圖畫面開這張地圖。

## 來源

| 檔案 | 從哪裡來 | 授權 |
|---|---|---|
| `hong_kong.pbf` | OpenStreetMap 香港整包，`https://osmtoday.com/asia/china/hong_kong.pbf`（約 44 MB） | ODbL 1.0，© OpenStreetMap 貢獻者 |
| `mtr_lines_and_stations.csv` | 港鐵開放資料「港鐵路綫及車站」，`https://opendata.mtr.com.hk/data/mtr_lines_and_stations.csv` | 「資料一線通」使用條款及條件；知識產權屬香港鐵路有限公司 |
| 下一班列車 | 港鐵開放資料「下一班列車」，`https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=<綫>&sta=<站>` | 同上 |

| `hkg_pop_2025_CN_1km_R2025A_UA_v1.tif` | WorldPop，香港 2025，constrained，30 角秒（約 1 公里）一格，R2025A v1（和台灣的 `taiwan_population.json` 同一個系列），`https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/HKG/v1/1km_ua/constrained/hkg_pop_2025_CN_1km_R2025A_UA_v1.tif`（12 KB） | CC BY 4.0，WorldPop |
| `Building_Outline_Public_v20261020_Building_converted.geojson` | 地政總署 Building（建物外形、`BaseHeight`／`TopHeight`），經 CSDI 提供，資料集 `landsd_rcd_1637211194312_35158`；下載的 zip `https://static.csdi.gov.hk/csdi-webpage/download/common/c0623f7db229af2dfb5bdfe62a8fdbc9d094d459b50baa200da4ddbe4e6b5c62`（73,920,546 B，SHA-256 `7f47f7cc…9f44`，資料版本 v20261020，2026-11-13 下載；網址是內容雜湊，資料更新後要從 metadata 重新取） | CSDI 使用條款及免責聲明；知識產權屬香港特別行政區政府與地政總署（決策 729） |
| `Digital Terrain Model.tif` | 地政總署數碼地形模型（5 m，HK1980 方格網 EPSG:2326），經空間數據共享平台（CSDI）提供，資料集 `landsd_rcd_1638158088368_93806`；下載的 zip `https://static.csdi.gov.hk/csdi-webpage/download/common/e9a836d098a3a9ccf55a7f61f69a93e71923c722fb94ddf7b36be83a67b99140`（24,206,651 B，SHA-256 `6dbcdfb5…1af`，2026-11-13 下載；網址是內容雜湊，資料更新後要從 metadata 重新取） | CSDI 使用條款及免責聲明；知識產權屬香港特別行政區政府與地政總署（決策 726） |

四個來源這個環境都連得到，不用改網路設定（地形的 DTM 與 2026-11-13 的整包例外，見第 8 步）。OSM 用整包加 pyosmium（`pip install osmium`，BSD 2-Clause，決策 93），不問 Overpass。

每次建出來讀了什麼（檔案的 SHA-256、取樣的時段、每條綫用的 OSM 路線關係與公里數）寫在 `hk_sources.json`。

## 重做

```sh
mkdir -p /tmp/hk/osm /tmp/hk/mtr /tmp/hk/nexttrain
curl -L -o /tmp/hk/osm/hong_kong.pbf https://osmtoday.com/asia/china/hong_kong.pbf
curl -L -o /tmp/hk/mtr/mtr_lines_and_stations.csv https://opendata.mtr.com.hk/data/mtr_lines_and_stations.csv
pip install osmium

# 1. 取樣「下一班列車」：每 300 秒把每條綫每一站問一輪。
#    要涵蓋香港的尖峰（07:30–09:30 或 17:30–19:30）和離峰各至少一小時。
python3 -I tools/hk-map/sample_next_train.py /tmp/hk/mtr/mtr_lines_and_stations.csv /tmp/hk/nexttrain 48 300

# 2. 從取樣算出每條綫的站間行車時間、尖峰與離峰班距、頭班車。
python3 -I tools/hk-map/next_train_service.py /tmp/hk/osm/hong_kong.pbf \
  /tmp/hk/mtr/mtr_lines_and_stations.csv /tmp/hk/nexttrain tools/hk-map/service.json

# 3. 建地圖檔與時刻。
python3 -I tools/hk-map/build_hk_mtr.py /tmp/hk/osm/hong_kong.pbf \
  /tmp/hk/mtr/mtr_lines_and_stations.csv tools/hk-map/service.json RailwayGameApp/Resources/MapPacks/hongkong

# 4. 把每條綫一天的車排成車組的班次（買下之後照這個跑）。
python3 -I tools/hk-map/extract_hk_runs.py RailwayGameApp/Resources/MapPacks/hongkong

# 5. 香港的人口（決策 712），並把地圖的範圍寫進 pack.json。
pip install tifffile imagecodecs numpy
mkdir -p /tmp/hk/pop
curl -L -o /tmp/hk/pop/hkg.tif https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/HKG/v1/1km_ua/constrained/hkg_pop_2025_CN_1km_R2025A_UA_v1.tif
python3 -I tools/hk-map/build_hk_ground.py /tmp/hk/pop/hkg.tif RailwayGameApp/Resources/MapPacks/hongkong

# 6. 香港的底圖（決策 712 續三），並更新 pack.json。
python3 -I tools/hk-map/build_hk_basemap.py /tmp/hk/osm/hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong/basemap.pmtiles

swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter "HongKongRailwaysTests|HongKongMapTests|HongKongBaseMapTests"

# 7. 香港的建物（決策 712 續四、決策 729），並更新 pack.json。
#    外形與高度：地政總署 Building 的 GeoJSON zip（約 74 MB，解開約 550 MB，只用 *_Building_converted.geojson）；
#    用途：osmtoday 的 asia/china/hong_kong.pbf（約 44 MB），pip install osmium。
#    雲端容器連 static.csdi.gov.hk 會 403，在作者的 Mac 上下載。
curl -L -o /tmp/hk/hk_buildings.zip https://static.csdi.gov.hk/csdi-webpage/download/common/c0623f7db229af2dfb5bdfe62a8fdbc9d094d459b50baa200da4ddbe4e6b5c62
unzip -d /tmp/hk/buildings /tmp/hk/hk_buildings.zip
python3 -I tools/hk-map/build_hk_buildings.py /tmp/hk/buildings/Building_Outline_Public_*_Building_converted.geojson \
  /tmp/hk/osm/hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong

# 8. 香港的地形與水域（決策 726）：heights.dat、water.json、terrain.pmtiles，並更新 pack.json 與 hk_sources.json。
#    2026-11-13 雲端連 static.csdi.gov.hk 與 osmtoday.com 都 403，這兩個檔是在作者的 Mac 下載的。
pip install osmium tifffile imagecodecs numpy
curl -L -o /tmp/hk/hk_dtm.zip https://static.csdi.gov.hk/csdi-webpage/download/common/e9a836d098a3a9ccf55a7f61f69a93e71923c722fb94ddf7b36be83a67b99140
(cd /tmp/hk && unzip -o hk_dtm.zip)    # "Digital Terrain Model.tif"，解開 498 MB
python3 -I tools/hk-map/build_hk_ground_grids.py "/tmp/hk/Digital Terrain Model.tif" /tmp/hk/osm/hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong
swift test --skip-build --filter "HongKongGroundTests|HongKongMapTests|HongKongRailwaysTests"

# 9. 香港機場的場面與不蓋區（決策 733）：airfields.json、no_build.json（台灣那兩支工具），並更新 pack.json。
python3 -I tools/airfields/build_airfields.py /tmp/hk/osm/hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong/airfields.json
python3 -I tools/no-build-land/build_no_build.py /tmp/hk/osm/hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong/no_build.json
swift test --skip-build --filter "HongKongAirportTests|HongKongRailwaysTests"
```

取樣的原始回應（幾十 MB）不進 repo；進 repo 的是算出來的 `service.json`。

## 每支工具做什麼

- `build_hk_buildings.py`（決策 729）：地政總署 Building 的建物外形與高度寫成 `buildings.pmtiles`（台灣 `footprints/2` 的格式）：Tower、Podium 全收，臨時與開放式構築物只收 30 m² 以上；樓層是 `TopHeight` 減底（自己的 `BaseHeight`，站在平台上的大樓取平台的底）÷ 3.2 m，`Storeys` 欄只拿來核對。用途取同一位置的 OpenStreetMap 建物；沒有高度的照有實測的建物分布估（構築物一層）。`LANDMARKS` 是之後由地標模型畫、這裡不畫的建物清單（現在是空的）。統計寫在 `hk_buildings.json`。

- **`build_hk_mtr.py`**：每條綫在 OSM 找一條路線關係（`route=subway|train`），它停的站要和港鐵 CSV 的站序（上行方向 `UT`；落馬洲與康城兩條支綫各自成一條，從上水、將軍澳起）一站一站相同；沿它的軌道從第一站走到最後一站，得到綫形、站位、每站的里程、橋與隧道。中英文站名取 OSM 的，逐站和 CSV 核對，對不上就停，不猜；只有「茘景」「茘枝角」照港鐵的寫法（`MTR_SPELLING`）。車站代號取 CSV。路綫色是 OSM 關係的 `colour`，和港鐵的標準色相同。時刻由 `service.json` 的班距與行車時間排出一整天雙向的車（`estimated: true`）：不是港鐵公布的時刻表（港鐵沒有公開）。
  寫出 `hkmtr.json`（營運資料）、`hkmtr_times.json`（時刻）、`track_lines.geojson`、`track_stations.geojson`、`station_names.json`、`rail_structures.json`、`pack.json`。
- **`sample_next_train.py`**：把每條綫每一站的「下一班列車」問一輪，原樣存成一輪一個 JSON。
- **`next_train_service.py`**：同一班車在相鄰兩站的預計到站時間相減，是那一段的行車加停站時間；取每一段所有樣本的中位數。只配開往兩站都列得出的目的地的車（終點站不列到站的車）；只收「A 站看得到的每一班車在 B 站都對得上」的差（15 秒內、至少兩班），幾個都對得上時取配到最多班的、再取最短而列車跑得到的（130 km/h）：開放資料只給整分鐘，班距平均時晚一個班距的差也對得上。班距是同一站開往終點的相鄰兩班的間隔，尖峰（07:30–09:30、17:30–19:30）與其餘時段各取中位數。頭班車取樣本裡 04:00 之後最早的一班；末班車樣本沒有涵蓋，寫 00:30（估計，檔案裡註明）。哪一段可用的樣本不到 5 個、或中位數不是列車的速度（低於 20 km/h 或高於 130），用這條綫的中位速度（整條綫都沒有時用全部綫的）除距離補，並在 `service.json` 寫 `runSamples: 0`。
- **`build_hk_ground.py`**（決策 712）：把 WorldPop 的香港人口格網寫成 `population.json`，格式和台灣的 `taiwan_population.json` 一樣（`PopulationGrid` 讀），合計 7,396,724 人、277 段、12 KB；檢查每一格有人的地方都在地圖範圍內。地圖範圍是 `build_hk_mtr.py` 的 `EXTENT`（WorldPop 香港格網的外框，北 22.5584、南 22.15、西 113.8333、東 114.4417，約 62.6 × 45.5 公里），寫進 `pack.json` 的 `extent`；遊戲照它開香港的世界（`MapPack.extent()`、`OverseasGround`），不再是 16 公里見方。
- **`build_hk_basemap.py`**（決策 712 續三）：用台灣底圖的工具（`tools/basemap/build_basemap.py`，同樣的圖層與 zoom）把整包檔切成 `basemap.pmtiles`，2D 與 3D 地圖、土地的真實道路都讀它。香港的新界與九龍連著大陸，整包檔把大陸的海岸切斷：開口的海岸線頭尾相接、從北邊繞回去閉合，大陸那一側算陸地（檔頭有說明）。2026-11-13 下載的整包檔（SHA-256 `20b9e1fc…1e3310`，OSM 資料到 2026-11-11）：152,099 筆圖形，海岸線 911 圈（其中 2 條開口的線接成 1 圈）；45,296 塊圖磚、786 種不同的內容，7,072,817 位元組，約 30 秒；同一份輸入每次建出來逐位元相同。這一份整包檔比建港鐵那幾個檔時（`hk_sources.json`）新，那幾個檔沒有重建。
- **`build_hk_ground_grids.py`**（決策 726）：香港的地形與水域，格式和台灣的 `taiwan_heights.dat`、`taiwan_water.json`、`taiwan_terrain.pmtiles` 一樣（`HeightGrid`、`WaterGrid`、2D 地圖的山影讀）。格網是台灣那一種（1.875″，從 `population.json` 的角起算，蓋滿 `pack.json` 的範圍，816 × 1,200 格）。水域照 `build_water_grid.py` 的規則，海岸線照底圖那樣把大陸被切開的海岸繞北方閉合（深圳是陸地）。高度是地政總署 DTM 每格範圍內 5 m 樣本的平均：格子中心從 WGS 84 用地政總署的簡化位移（緯度 +5.5″、經度 −8.8″）轉 HK80，再用國際 1924 橢球的橫麥卡托轉成方格網，都自己寫（標準函式庫加 numpy）；水邊照決策 132 取水面，外海 0；DTM 沒有涵蓋的陸地（深圳）是 0。陡坡照決策 115 的規則。核對：大帽山附近最高 953 m（官方 957 m）；DTM 高於 1 m 的格子有 98.03% 在 OSM 的陸上（位移正負號反過來是 89%，不加位移 93%），低於 97% 就停。
- **`extract_hk_runs.py`**：用 `tools/real-timetables/extract_metro_runs.py` 同一套排法（一列車到終點後折返接下一班，夜裡停在哪就從哪出車），把 `hkmtr_times.json` 排成 `metro_runs.json`，並更新 `pack.json`。終點站停不下那麼多車的綫會被留在外面並列出來：那條綫就還不能買。

## 哪些來自哪一邊

`build_hk_mtr.py` 的 `SOURCES` 是唯一的一張表，寫進 `pack.json`：綫形、站位、里程、橋隧、綫色、站名來自 OpenStreetMap；車站與路綫代號、兩個「茘」字、班距與行車時間（以及由它們排出來的時刻與班次）來自港鐵開放資料。要抽掉港鐵那一邊：拿掉 `code` 與 `MTR_SPELLING`，班距與行車時間另找來源寫成同格式的 `service.json`，重跑第 3、4 步；綫、站、站名、橋隧不變。

## 沒有的

港鐵沒有公開：正式時刻表、各站進出人次（只有全綫月總數）、車廠的位置與軌道配置、列車的編組資料。清單與之後可以怎麼補在 `docs/research/HK_MAP_2026-11-12.md` §3.5。

參考庫 `Railway/world-rail-reference-clean/` 沒有香港；這裡移植的是它的做法（`source/tools/build_singapore.mjs` 用營運者的站序定範圍、OSM 路線關係給綫形；`headway2sched.mjs` 用班距排出一天的車），沒有複製它的資料。
