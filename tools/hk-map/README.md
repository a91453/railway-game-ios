# 香港港鐵的地圖資料（決策 697）

把香港港鐵十條鐵路綫（機場快綫、東涌綫、屯馬綫、東鐵綫、荃灣綫、港島綫、觀塘綫、將軍澳綫、南港島綫、迪士尼綫；輕鐵不在內）做成遊戲讀得進去的檔案，格式和台灣的真實鐵道一樣。研究、來源與授權在 `docs/research/HK_MAP_2026-11-12.md`。

遊戲現在**不會讀**這些檔案：`OverseasMaps.open` 是空的，等「開航解鎖」的規則接上才打開（決策 697 的下一步）。

## 來源

| 檔案 | 從哪裡來 | 授權 |
|---|---|---|
| `hong_kong.pbf` | OpenStreetMap 香港整包，`https://osmtoday.com/asia/china/hong_kong.pbf`（約 44 MB） | ODbL 1.0，© OpenStreetMap 貢獻者 |
| `mtr_lines_and_stations.csv` | 港鐵開放資料「港鐵路綫及車站」，`https://opendata.mtr.com.hk/data/mtr_lines_and_stations.csv` | 「資料一線通」使用條款及條件；知識產權屬香港鐵路有限公司 |
| 下一班列車 | 港鐵開放資料「下一班列車」，`https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=<綫>&sta=<站>` | 同上 |

三個來源這個環境都連得到，不用改網路設定。OSM 用整包加 pyosmium（`pip install osmium`，BSD 2-Clause，決策 93），不問 Overpass。

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
  /tmp/hk/mtr/mtr_lines_and_stations.csv tools/hk-map/service.json RailwayGameApp/Resources/RealRailways

# 4. 把每條綫一天的車排成車組的班次（買下之後照這個跑）。
python3 -I tools/hk-map/extract_hk_runs.py RailwayGameApp/Resources/RealRailways

swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter HongKongRailwaysTests
```

取樣的原始回應（幾十 MB）不進 repo；進 repo 的是算出來的 `service.json`。

## 每支工具做什麼

- **`build_hk_mtr.py`**：站序與中英文站名照港鐵的 CSV（上行方向 `UT`，落馬洲與康城兩條支綫各自成一條，從上水、將軍澳起）。每條綫在 OSM 找一條站名順序和 CSV 完全相同的路線關係（`route=subway|train`），沿它的軌道從第一站走到最後一站，得到綫形、每站的里程、橋與隧道。站序對不上就停，不猜。路綫色是 OSM 關係的 `colour`，和港鐵的標準色相同。時刻由 `service.json` 的班距與行車時間排出一整天雙向的車（`estimated: true`）：不是港鐵公布的時刻表（港鐵沒有公開）。
  寫出 `hkmtr.json`（營運資料）、`hkmtr_times.json`（時刻）、`hk_track_lines.geojson`、`hk_track_stations.geojson`、`hk_station_names.json`、`hk_rail_structures.json`。
- **`sample_next_train.py`**：把每條綫每一站的「下一班列車」問一輪，原樣存成一輪一個 JSON。
- **`next_train_service.py`**：同一班車在相鄰兩站的預計到站時間相減，是那一段的行車加停站時間；取每一段所有樣本的中位數。只收「A 站看得到的每一班車在 B 站都對得上」的差（15 秒內、至少兩班、30 秒內沒有第二個答案），其餘不算。班距是同一站開往終點的相鄰兩班的間隔，尖峰（07:30–09:30、17:30–19:30）與其餘時段各取中位數。頭班車取樣本裡 04:00 之後最早的一班；末班車樣本沒有涵蓋，寫 00:30（估計，檔案裡註明）。哪一段沒有可用的樣本，用這條綫的中位速度乘距離補，並在 `service.json` 寫 `runSamples: 0`。
- **`extract_hk_runs.py`**：用 `tools/real-timetables/extract_metro_runs.py` 同一套排法（一列車到終點後折返接下一班，夜裡停在哪就從哪出車），把 `hkmtr_times.json` 排成 `hk_metro_runs.json`。終點站停不下那麼多車的綫會被留在外面並列出來：那條綫就還不能買。

## 沒有的

港鐵沒有公開：正式時刻表、各站進出人次（只有全綫月總數）、車廠的位置與軌道配置、列車的編組資料。清單與之後可以怎麼補在 `docs/research/HK_MAP_2026-11-12.md` §4。

參考庫 `Railway/world-rail-reference-clean/` 沒有香港；這裡移植的是它的做法（`source/tools/build_singapore.mjs` 用營運者的站序定範圍、OSM 路線關係給綫形；`headway2sched.mjs` 用班距排出一天的車），沒有複製它的資料。
