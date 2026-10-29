# 把遊戲的位置資料輸出成 GeoJSON（給 geolibre.app 檢查）

`export_geojson.py` 把車站、路線、機廠和遊戲內部的道路輸出成 GeoJSON（WGS84，經度在前），作者可以拖進 [geolibre.app](https://geolibre.app)（MIT，網頁 GIS）和底圖比對位置。只讀資料、不放進遊戲，不改 App 和 GameCore。標準函式庫，不加依賴。

## 怎麼跑

在 repo 根目錄：

```sh
# 車站、路線、機廠（全台，約 0.4 MB）
python3 -I tools/geojson-export/export_geojson.py all

# 一個範圍內的底圖道路（west,south,east,north）
python3 -I tools/geojson-export/export_geojson.py roads --bbox 120.525,24.057,120.565,24.093 --suffix _dashe

# 遊戲「有路」的 64 m 格子：以地圖中心（--anchor）和半徑（公尺）
python3 -I tools/geojson-export/export_geojson.py cells --anchor 24.075,120.545 --radius 1200 --suffix _dashe
```

輸出放在 `tools/geojson-export/out/`（不提交，`--out` 可改）。`samples/` 是提交的範例：全台的 `stations`、`lines`、`depots`，以及竹中（新竹）和彰化大社路一帶的 `roads_*`、`road_cells_*`。

## 怎麼在 geolibre.app 打開

1. 開 https://geolibre.app。
2. 把 `.geojson` 檔直接拖進頁面（也可以用它的「Add data／Open file」選檔）；一次可以拖好幾個，每個檔一層。
3. 點圖上的點或線看屬性（名稱、系統、`class`、`kind`…）；在圖層面板可以改顏色、開關。
4. 道路用法：先拖 `roads_*`（底圖的線，`game_road_cell` 為 true 的是遊戲算成「有路」的），再拖 `road_cells_*`（遊戲內 64 m 格子，`kind=road` 一般道路、`highway` 國道快速道路，另外存）。格子該蓋到每條線，沒蓋到就是遊戲沒算。

## 各層

| 檔 | 內容 | 來源 | 授權 |
| --- | --- | --- | --- |
| `stations` | 車站點 608 個，屬性 `name`、`system`、`line`、`color` | `RailwayGameApp/Resources/RealRailways/track_stations.geojson`（App 打包的，遊戲畫車站用的位置） | © OpenStreetMap 貢獻者（ODbL 1.0）；TDX 資料依政府資料開放授權條款第 1 版 |
| `lines` | 路線 79 條（台鐵、高鐵、阿里山、捷運、輕軌），屬性 `name`、`system`、`id`、`color` | `.../track_lines.geojson`（同上） | 同上 |
| `depots` | 機廠：高鐵 OSM 機廠的約略範圍（停車長度 × 股數 × 5 m，沿主軸）、中心、轉轍器；三峽機廠岔出點與停車線；高鐵與台鐵示範用的機廠點 | `tools/hsr-depots/hsr_depots.json`；`RealLineDepotSite.sanxia`、`HighSpeedDemo.realDepots`、`TRADemo.depots`（程式裡的數字，抄在腳本裡，改程式時要同步） | © OpenStreetMap 貢獻者（ODbL 1.0） |
| `roads` | 底圖 `transportation` 層的線，屬性 `class`、`brunnel`、`name`、`in_game`、`highway`、`game_road_cell` | `BaseMap/taiwan.pmtiles` zoom 14（App 底圖，OpenMapTiles 欄位，內容 OSM） | © OpenStreetMap 貢獻者（ODbL 1.0） |
| `road_cells` | 遊戲內「有路」的 64 m 格子（多邊形），屬性 `kind`、`row`、`column` | 同上，照 `RealRoadCells.add` 的算法：每 8 m 取一點、隧道不算（國道快速道路例外並另存為 `highway`）、世界 16,384 m 見方，中心在 `--anchor` | 同上 |

## 注意

- 格子要和遊戲一致，`--anchor` 必須是那一局地圖的中心；範例的中心是為了看效果隨手選的，不是某個存檔。新局的世界邊長用 16,384 m（`WORLD_METRES`）；別的大小要改腳本裡這個值。
- 格子沒有套用 `LandBlock`（只算已讀入土地的區塊），範圍內全部算。
- 玩家自己鋪的路不在資料檔裡（在存檔），這裡只有底圖來的路。
- 機廠的範圍是估的，只有中心和轉轍器是 OSM 的點。

## 授權

道路、路線、機廠都來自 OpenStreetMap，© OpenStreetMap 貢獻者，ODbL 1.0；遊戲的資料來源畫面（`DataSourceCredits`）標示 OpenStreetMap。TDX 的站線資料依政府資料開放授權條款第 1 版。每個 GeoJSON 的 `license` 欄位寫了這些。
