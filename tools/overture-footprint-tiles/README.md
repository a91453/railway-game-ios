# Overture 足跡圖塊（決策 386、389）

把 Overture Maps 在台灣的建物（約 196 萬棟）轉成 App 讀得動的精簡圖塊：每個 z16 Web Mercator 方格一塊（台灣上 553–568 m，3D 地圖 512 m 一格的大小），gzip，裝進 PMTiles v3。全台一個檔，各縣市各一個檔。報告與量測：`docs/research/OVERTURE_FOOTPRINT_TILES_2026-10-23.md`。

全台的檔照決策 389 打包進 App：`RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles`（29.6 MB，就是 `build` 的 `out/taiwan.pmtiles` 改名），由 `Map3DFootprints.swift` 讀。各縣市的檔不提交，是 Background Assets 的退路（決策 386）。

## 需要的東西

- `pip install duckdb`（MIT；作者已同意，決策 93、`build_overture_building_grid.py`）。DuckDB 2.0 起 lambda 寫成 `lambda s: s.dataset`。
- 參考庫的縣市界（只拿來分縣市、排除廈門與福州海岸，不打包）：
  `a91453/railway-reference-private` 的 `Railway/geo-scene-reference-clean/source/public/statistics/county-reference-2025.geojson`（內政部）。
- App 的 `RailwayGameApp/Resources/RealWorld/taiwan_population.json`（WorldPop，CC BY 4.0），`heights`、`storeys` 與 `window` 用。
- `storeys` 的樓高來源（只在建檔時讀，都不打包；下載點與欄位在報告 §8）：
  - 臺中市建物圖 114 年版（data.gov.tw 158889，全市 29 區，7z）、113 年版（152106，19 區，RAR）、111 年版（162900，原臺中市，zip）；欄位 `B1D` 是樓層。
  - 臺北市建築執照套繪圖（151936，zip）。一張建照的基地常蓋住裙樓與塔樓，所以只在合理時用（`permit_fits`：101 層以下、樓高不超過足跡邊長的 8 倍、20 層以上的足跡不超過 5,000 m²）。
  - GHS-BUILT-H ANBH R2023A 的 R6_C30、R7_C30 兩塊 GeoTIFF（`tiff.py` 讀）。
- 解 113、114 年版的壓縮檔用 libarchive 的 `bsdtar`（BSD 授權；作者 2026-10-23 同意，只用在這個工具，不進 App）。macOS 內建；Linux 是 `apt-get install libarchive-tools`。檔名是 UTF-8，在沒有 UTF-8 locale 的環境要加 `LC_ALL=C.UTF-8`：

  ```sh
  LC_ALL=C.UTF-8 bsdtar -xf 114.7z -C t114   # 01-SHP/114期末_B0001_1216n.shp
  LC_ALL=C.UTF-8 bsdtar -xf 113.rar -C t113  # 113期末_B0001_19區.shp（RAR 5）
  ```

## 指令

```sh
T=tools/overture-footprint-tiles/build_footprint_tiles.py
C=../railway-reference-private/Railway/geo-scene-reference-clean/source/public/statistics/county-reference-2025.geojson
P=RailwayGameApp/Resources/RealWorld/taiwan_population.json

# 約 1 分鐘：從 Overture 的公開 S3 讀台灣、金門、馬祖三個框，留下在縣市內或 2 km 內的建物
python3 $T extract 2026-09-23.1 $C footprints.parquet
# 約 6 秒：有樓層的建物，依人口密度、足跡大小、用途分組的四分位數（決策 386 第 5 點）
python3 $T heights footprints.parquet $P heights.json
# 約 1 分鐘：每棟的樓層與來源（決策 389 的順序）。臺中的圖新的在前，用 : 隔開
python3 $T storeys footprints.parquet $P heights.json ghsl/ "t114/01-SHP/114期末_B0001_1216n.shp:t113/113期末_B0001_19區.shp:t111/111_B0001.shp" taipei.shp storeys.parquet
# 約 40 秒（4 核）：out/taiwan.pmtiles、out/counties/<代碼>.pmtiles、out/report.json
python3 $T build footprints.parquet out 0.5 storeys.parquet
cp out/taiwan.pmtiles RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles
# 一個方框裡的建物（從 out/taiwan.pmtiles 解回來，驗證格式），給 3D 量測用
python3 $T window out/taiwan.pmtiles 25.0133 121.4637 3072 heights.json $P window.json
```

`measure_height_sources.py` 量各個樓高來源（3D-GloBFP、GHSL、臺中市建物圖、臺北市建築執照套繪圖）對 Overture 足跡的覆蓋與誤差，用法在它的開頭；結果在報告 §8。GHSL 的 GeoTIFF 用 `tiff.py` 讀（只用標準函式庫，BigTIFF、LZW／deflate、方塊或條帶）；測試 `python3 -I tools/overture-footprint-tiles/test_tiff.py`，CI 沒有跑，改讀檔器時在本機跑。

`FootprintWindowMeasure.swift.txt` 是量板橋 3 × 3 的測試範本：暫時複製進 `Tests/GamePresentationTests/`，用 `FOOTPRINT_WINDOW=window.json swift test --filter FootprintWindowMeasure` 跑，跑完刪掉（同 `tools/map3d-preview/` 的做法）。

## 每月換 Overture 新版（決策 1026）

Overture 大約每四週出一版，S3 只留最近兩版。`refresh_release.py` 把新版**逐棟**補進內建檔，不整檔重建
（整檔重建要重抓 GHSL、三年的臺中圖、臺北套繪圖、使用執照與實價登錄，見上面幾節）：

```sh
R=tools/overture-footprint-tiles/refresh_release.py
python3 -I $R latest                                   # S3 上最新的版本
python3 -I $R current $A                               # 內建檔現在是哪一版（metadata 的 overture）
python3 $T extract <新版> $C new.parquet               # 約 1 分鐘
python3 -I $R patch $A new.parquet $C $P <新版> out.pmtiles refresh.json   # 約 5 分鐘
cp out.pmtiles $A                                      # 只在 patch 結束碼是 0 時
```

- 新版每格照 `build` 的同一套簡化、取整重編，外形沒變的房子和內建檔的位元組一樣，就**留著原樣**（使用執照、實價登錄、
  臺中圖的樓層都不動）；只有原本是推算或 OSM 標的樓層、而新版有 OSM 標的，才換成新的標。
- 內建檔有、新版沒有的：拆了或 OSM 重畫了，**拿掉**；但在官方輪廓的縣市（`OFFICIAL`，現在只有臺中市）裡的留著，那些本來就不是 Overture 的。
- 新版有、內建檔沒有的：**補進來**，除非留下的房子蓋住它一成以上、或它蓋住某棟留下的房子一半以上（決策 1001 的去重，
  和 `official_outlines.py` 同一條，所以被臺中圖換掉的 Overture 房子不會回來）。樓層照 OSM 的標，沒有就照密度猜（`proposed_storeys`），但不高於周圍 3 × 3 格房子樓層的第 75 百分位（不到 10 棟就最多 2 層）。
- 寫檔前先比對（`LIMITS`）：縣市外形沒變的比例、每縣市拆掉與新增的比例、全台淨變化、單格掉多少。任何一條超過就**不寫檔**、
  報告寫哪一條、結束碼 3。
- 車站地標、地標、遊戲自己的車站在畫地圖時照位置拿掉底下的房子（`underLandmark`、`replacedPlots`、`underRailway`），
  不看房子的編號，所以換新版後照樣拿掉。
- 換完把 `DataSourceCredits.taiwanFootprintRelease` 改成新版本號；`FootprintReleaseTests` 守著兩邊一致。

## 決定性

同一份 `footprints.parquet`（與 `storeys.parquet`）產出位元完全相同的檔：每棟依 Overture id 讀、每格內依重心排序、環的方向固定、gzip 等級 9 不寫時間（`mtime=0`），PMTiles 寫法是 `tools/basemap/build_basemap.py` 的 `write_pmtiles`。2026-10-23 以 0.5 m 跑兩次，23 個檔逐一 SHA-256 相同；決策 389 加上樓層後再跑兩次，也相同。Python 的 zlib 版本不同時 gzip 位元組可能不同，解開後的內容相同。

## 格式（`footprints/2`）

PMTiles v3，只有 zoom 16，圖塊型別 0（未知），每塊 gzip。解開後全是 LEB128 varint，有號數用 zigzag：

```
版本 (2)、建物數
每棟：
  屬性 = 樓層 << 8 | 樓層來源 << 5 | 用途 << 1 | 來源
      樓層：1–255；0 = 不知道（沒給 storeys.parquet 時，沒有標記的都是 0）
      樓層來源：STOREYS_FROM 的序號：0 推算、1 OSM 標記、2 市府建物圖、3 臺北建照、4 國土測繪中心（留著，還沒接）
      用途：USES 的序號 + 1（agricultural … transportation），0 = 不知道
      來源：0 OpenStreetMap，1 Shi 等人
  環數（外環在前，洞在後）
  每環：點數（≥ 3，不重複起點），每點對上一個寫出的點的 zigzag dx、dy（整塊共用一個游標，從 0, 0 起）
```

座標是格內整數：一格 4096 單位（同向量圖塊的 extent），台灣上一單位 0.137–0.140 m，x 向東、y 向南，從格子西北角起。建物放在重心所在的格，大建物會伸出格外。外環從上往下看逆時針，洞順時針。MultiPolygon 每個多邊形算一棟。

座標是 Mercator 的線性比例，App 換到世界座標只要乘加（`RealWorldFrame.worldPosition(latitude:longitude:)` 也是 Mercator，以錨點的緯度縮放）。

## 授權

Overture Maps 的建物整體是 ODbL 1.0；台灣的足跡各自來自 OpenStreetMap（ODbL 1.0，「© OpenStreetMap contributors」）與 Shi 等人的 East Asian buildings（doi:10.5281/zenodo.8174931，CC BY 4.0）。每個檔的 metadata 寫了這段署名。App 的署名在 `DataSourceCredits` 的 `overtureBuildings`（決策 389）；官網 credits.html 還沒加（`docs/HANDOFF.md` §4.8）。

## 使用執照的樓層（決策 1011）

`usage_permits.py` 把新北市建築執照存查（data.gov.tw 123639）、臺北市歷年使用執照摘要（128203）、新竹市使用執照清冊（163823）的地上層數，用門牌坐標（OpenAddresses 收錄、Overture Maps addresses 轉載）對到內建檔的輪廓；臺南市使用執照（121026）只有地號，用臺南市宗地地號屬性資料（176361）的地號中心點對到輪廓，其他縣市用內政部實價登錄（18703）每筆買賣的總樓層數，以全台門牌坐標對到輪廓（過半的交易同一個層數才用）；
改那幾棟的樓層（來源 `permits`），其他位元組不動。指令在它的開頭；`footprints/2`、`/3` 都讀。結果在 `usage_permits.json`。從 `main` 的檔跑，不要對已經跑過的檔再跑。

## 縣市官方輪廓（決策 1015）

`official_outlines.py` 在 `usage_permits.py apply` 之後跑：把縣市政府以政府資料開放授權條款第 1 版公開的建物輪廓換進內建檔，
官方的先鋪，Overture 的只補官方沒有的地方（決策 1001 的去重：被官方蓋住 10% 以上，或蓋住某棟官方建物一半以上，就拿掉）。
牆貼牆、樓層相同的相鄰房子併成一棟（遠景預算，決策 1015 §5）。官方的樓層照圖上的（來源 `cityMap`），圖上沒有的才取蓋得最多的那棟原有建物的樓層與來源；用途取那棟的，沒有的話鐵皮構造當工業。
目前只有臺中市建物圖（data.gov.tw 158889，114 年，全市 29 區）可用；各縣市查過的結果在決策 1015。指令在它的開頭，結果在 `official_outlines.json`。
從跑過 `usage_permits.py` 的檔跑，不要對已經換過的檔再跑。

換樓高來源（國土測繪中心、其他縣市的建物圖、新一年的臺中圖）只要改 `storeys` 的來源順序、重跑 `storeys` 與 `build`，格式與 App 都不用改；樓層來源 3 位元還有 1 個空位（7；`nlsc` 留給國土測繪中心）。

`footprints/1`（決策 386 第一版，樓層 << 5）App 不讀，`decode_tile` 也只收 2。

樓層署名：臺中市建物圖與臺北市建築執照套繪圖是政府資料開放授權條款第 1 版，GHS-BUILT-H 是 CC BY 4.0，人口密度是 WorldPop（CC BY 4.0）；有 `storeys.parquet` 時寫進 metadata 的 `attribution`，App 的署名是 `DataSourceCredits` 的 `buildingStoreys`。
