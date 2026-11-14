# 車站月台型式表（決策 741）

`platform_types.json`：台鐵（`tra_sched`）與高鐵（`thsr_sched`）每站的月台是島式、岸式、混合或未知，以及 OSM 畫出的月台與站內並排股數。

## 來源

- © OpenStreetMap contributors，ODbL 1.0：osmtoday.com 的 `asia/taiwan.pbf`，2026-11-14 下載。
- 車站位置：`RailwayGameApp/Resources/RealRailways/track_stations.geojson`。

## 重新產生

```bash
pip install osmium
python3 -I tools/station-platform-types/build_platform_types.py taiwan.pbf RailwayGameApp/Resources/RealRailways/track_stations.geojson tools/station-platform-types/platform_types.json
```

（`python3 -I` 不讀使用者 site-packages，osmium 要裝在 venv 裡，用 venv 的 python 執行。）

## 注意

- `tracks` 股數含站場側線，不能當旅客股道數。
- 示範路線的島式月台以官方站內圖為準，見決策 741（`docs/decisions/741.md`）；OSM 與官方不一致的站（例如頭城、礁溪、蘇澳新、高鐵板橋）以官方為準。
