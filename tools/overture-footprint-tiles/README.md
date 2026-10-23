# Overture 足跡圖塊（決策 386）

把 Overture Maps 在台灣的建物（約 196 萬棟）轉成 App 讀得動的精簡圖塊：每個 z16 Web Mercator 方格一塊（台灣上 553–568 m，3D 地圖 512 m 一格的大小），gzip，裝進 PMTiles v3。全台一個檔，各縣市各一個檔。報告與量測：`docs/research/OVERTURE_FOOTPRINT_TILES_2026-10-23.md`。

輸出的資料檔（全台約 29 MB）**不提交**；這個工具與報告提交。

## 需要的東西

- `pip install duckdb`（MIT；作者已同意，決策 93、`build_overture_building_grid.py`）。DuckDB 2.0 起 lambda 寫成 `lambda s: s.dataset`。
- 參考庫的縣市界（只拿來分縣市、排除廈門與福州海岸，不打包）：
  `a91453/railway-reference-private` 的 `Railway/geo-scene-reference-clean/source/public/statistics/county-reference-2025.geojson`（內政部）。
- App 的 `RailwayGameApp/Resources/RealWorld/taiwan_population.json`（WorldPop，CC BY 4.0），只有 `heights` 與 `window` 用。

## 指令

```sh
T=tools/overture-footprint-tiles/build_footprint_tiles.py
C=../railway-reference-private/Railway/geo-scene-reference-clean/source/public/statistics/county-reference-2025.geojson
P=RailwayGameApp/Resources/RealWorld/taiwan_population.json

# 約 1 分鐘：從 Overture 的公開 S3 讀台灣、金門、馬祖三個框，留下在縣市內或 2 km 內的建物
python3 $T extract 2026-09-23.1 $C footprints.parquet
# 約 40 秒（4 核）：out/taiwan.pmtiles、out/counties/<代碼>.pmtiles、out/report.json
python3 $T build footprints.parquet out 0.5
# 約 6 秒：有樓層的建物，依人口密度、足跡大小、用途分組的四分位數（第 2 步的高度提案）
python3 $T heights footprints.parquet $P heights.json
# 一個方框裡的建物（從 out/taiwan.pmtiles 解回來，驗證格式），給 3D 量測用
python3 $T window out/taiwan.pmtiles 25.0133 121.4637 3072 heights.json $P window.json
```

`measure_height_sources.py` 量各個樓高來源（3D-GloBFP、GHSL、臺中市建物圖、臺北市建築執照套繪圖）對 Overture 足跡的覆蓋與誤差，用法在它的開頭；結果在報告 §8。GHSL 的 GeoTIFF 用 `tiff.py` 讀（只用標準函式庫，BigTIFF、LZW／deflate、方塊或條帶）；測試 `python3 -I tools/overture-footprint-tiles/test_tiff.py`，CI 沒有跑，改讀檔器時在本機跑。

`FootprintWindowMeasure.swift.txt` 是量板橋 3 × 3 的測試範本：暫時複製進 `Tests/GamePresentationTests/`，用 `FOOTPRINT_WINDOW=window.json swift test --filter FootprintWindowMeasure` 跑，跑完刪掉（同 `tools/map3d-preview/` 的做法）。

## 決定性

同一份 `footprints.parquet` 產出位元完全相同的檔：每棟依 Overture id 讀、每格內依重心排序、環的方向固定、gzip 等級 9 不寫時間（`mtime=0`），PMTiles 寫法是 `tools/basemap/build_basemap.py` 的 `write_pmtiles`。2026-10-23 以 0.5 m 跑兩次，23 個檔逐一 SHA-256 相同。Python 的 zlib 版本不同時 gzip 位元組可能不同，解開後的內容相同。

## 格式（`footprints/1`）

PMTiles v3，只有 zoom 16，圖塊型別 0（未知），每塊 gzip。解開後全是 LEB128 varint，有號數用 zigzag：

```
版本 (1)、建物數
每棟：
  屬性 = 樓層 << 5 | 用途 << 1 | 來源
      樓層：Overture 的 num_floors，沒有就 height ÷ 3.2 m 四捨五入，1–255；0 = 不知道
      用途：USES 的序號 + 1（agricultural … transportation），0 = 不知道
      來源：0 OpenStreetMap，1 Shi 等人
  環數（外環在前，洞在後）
  每環：點數（≥ 3，不重複起點），每點對上一個寫出的點的 zigzag dx、dy（整塊共用一個游標，從 0, 0 起）
```

座標是格內整數：一格 4096 單位（同向量圖塊的 extent），台灣上一單位 0.137–0.140 m，x 向東、y 向南，從格子西北角起。建物放在重心所在的格，大建物會伸出格外。外環從上往下看逆時針，洞順時針。MultiPolygon 每個多邊形算一棟。

座標是 Mercator 的線性比例，App 換到世界座標只要乘加（`RealWorldFrame.worldPosition(latitude:longitude:)` 也是 Mercator，以錨點的緯度縮放）。

## 授權

Overture Maps 的建物整體是 ODbL 1.0；台灣的足跡各自來自 OpenStreetMap（ODbL 1.0，「© OpenStreetMap contributors」）與 Shi 等人的 East Asian buildings（doi:10.5281/zenodo.8174931，CC BY 4.0）。每個檔的 metadata 寫了這段署名。放進 App 時 `DataSourceCredits` 與官網 credits.html 要加（決策 386 第 4 步）。
