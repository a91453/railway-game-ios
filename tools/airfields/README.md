# 機場場面資料（決策 699）

`build_airfields.py` 讀一整包台灣的 OpenStreetMap（osmtoday.com 的 `asia/taiwan.pbf`，ODbL 1.0），寫出 App 內建的 `RailwayGameApp/Resources/BaseMap/taiwan_airfields.json`，3D 地圖用它畫機場（`RealAirfields`、`Map3DAirfields`、`Map3DAircraft`）。

```sh
pip install osmium            # pyosmium，BSD 2-Clause（決策 93）；只有這個工具用
curl -fLO https://osmtoday.com/asia/taiwan.pbf
python3 -I tools/airfields/build_airfields.py taiwan.pbf RailwayGameApp/Resources/BaseMap/taiwan_airfields.json
```

約 70 秒。只讓需要的東西進 Python（`TagFilter`）；把全台灣的建物都送進來要半小時以上。

## 留下什麼

有 IATA 代碼的機場（有定期航班的那些，19 座）各一筆：

| 欄位 | 內容 | OSM 標籤 |
| --- | --- | --- |
| `runways` | 中線兩端、寬度、兩端漆的號碼（第一個號碼在線的第一點那一端） | `aeroway=runway`；同名相接的幾段併成一條；草地與土面不留；`runway=displaced_threshold` 只丟 1,000 m 以內的（決策 733：赤鱲角 07C/25C 整條被這樣標） |
| `taxiways` | 中線（簡化到約 1 m；和別的滑行道、跑道、機位相接的點都留著，App 靠它們接出滑行的路網）、寬度 | `aeroway=taxiway`／`taxilane`／`stopway`；沒寫寬度的用 23 m、15 m |
| `aprons` | 外框（簡化到約 2 m），1,500 m² 以上 | `aeroway=apron` |
| `stands` | 機鼻停的位置、機頭朝向（度，順時針自北） | `aeroway=parking_position`：線的終點與方向；點則朝最近的航廈（160 m 內），沒有就是 −1，由 App 轉成背對跑道 |
| `bridges` | 空橋兩端 | `aeroway=jet_bridge` |
| `towers` | 塔台位置與高度 | `aeroway=tower`／`control_tower`、`man_made=control_tower`、`tower:type=airport_control`、`service=aircraft_control` |

座標是 1e-6 度的整數（約 0.1 m），每條線第一點是完整的值，之後是和前一點的差。

**不是 OSM 畫的**：OSM 上機位不到 6 個的機場（臺中、馬公、金門、臺東等），在最靠近航廈的停機坪上、背對跑道的那一側排一列機位（每 46 m 一個，最多 8 個，`row_of_stands`）；機鼻、機尾與兩個翼尖都要在停機坪上、離航廈 8 m 以上。這些位置是本專案排的，不是實際機位。

2026-11-12 的結果（osmtoday 當天的檔）：桃園 2 條跑道、234 段滑行道、303 個機位、72 座空橋、1 座塔台；松山 1 條、44 個機位、12 座空橋；高雄 1 條、84 個機位、16 座空橋；臺中 1 條、OSM 2 個機位（補到 8 個）、8 座空橋、1 座塔台。檔案約 98 KB。松山與高雄的塔台 OSM 沒有上面那些標籤，所以沒有畫。

## 香港（決策 733）

同一支工具讀香港整包（osmtoday `asia/china/hong_kong.pbf`），寫進香港地圖包，App 和台灣的一起讀：

```sh
python3 -I tools/airfields/build_airfields.py hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong/airfields.json
python3 -I tools/no-build-land/build_no_build.py hong_kong.pbf RailwayGameApp/Resources/MapPacks/hongkong/no_build.json
```

之後更新 `pack.json` 裡這兩個檔的 `bytes` 與整包的 `bytes`。檔的 `source` 照讀的整包檔名寫（`EXTRACTS`）。
