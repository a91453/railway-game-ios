# FUKUOKA-GROUND：福岡地圖包的地面

- 派工：協調者（工作串「做福岡地圖並開放」），2026-11-19，雲端 thread session，分支 `claude/project-thread-08of3m`。
- 決策 854「後來（FUKUOKA-GROUND）」。存檔版本、golden、replay、GameCore：不動。
- 做了：人口、底圖、高度、水域、地形、機場、不蓋區；`tools/overseas-map/overseas_ground.py`（羅瓦涅米改用、輸出逐位元組相同）；`tools/fukuoka-map/fetch_gsi_dem.py`、`build_fukuoka_ground.py`；`FukuokaGroundTests`；資料來源頁福岡一節多三項。重做的指令在 `tools/fukuoka-map/README.md`。

## 同一串接下來（照順序，一步一張）

1. **FUKUOKA-BUILDINGS**：`buildings.pmtiles`，照羅瓦涅米（`build_rovaniemi_buildings.py`，OSM 外形＋人口推估樓層）；先量 PLATEAU 福岡市（CC BY 4.0）的真實樓高值不值得接。能共用的抽進 `tools/overseas-map/`。
2. **FUKUOKA-STREETS**：`Map3DStreetRegion` 加日本（靠左、白／黃分向線、沒有機車格與紅線、行人燈不倒數）；`Map3DRegionLook` 加日本。
3. **FUKUOKA-LANDMARKS**：福岡塔、福岡巨蛋、博多站等交工作室（Mac 只在 23:00–09:00）。
4. **MAP-PACK-MANAGE**：設定裡刪除／重新下載地圖包，處理已刪地圖上的存檔（記憶 map-opening：福岡開放前做）。
5. **FUKUOKA-PACK**：`AssetPacks/fukuoka.json`。每上傳一次 Apple 要審一次，資料都定了才加。
6. **FUKUOKA-OPEN**：見 `JAPAN-FUKUOKA-1.md` 第 3 項。

## UNVERIFIED

- 雲端 Linux 跑過（VERIFIED）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`FukuokaGroundTests`、`FukuokaRailwaysTests`、`SharedStationLayoutTests`、`RealLineBundleTests`、`RealLineBoughtAgainTests`、`UndergroundStationsTests`、`RealUndergroundTests`、`Map3DMapLoadReportTests`、`RealRailwaysTests`、`MapPackDownloadsTests`、`HongKongRailwaysTests`、`RovaniemiRailwaysTests` 共 100 項通過（4 項本來就跳過）。
- 沒在 iOS Simulator、iPhone 上看過：開關關著。
- 沒做土地覆蓋（`landcover.dat`）。
