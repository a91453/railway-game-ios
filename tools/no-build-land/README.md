# 不蓋房子的地與機場建物

決策 385。實景 3D 地圖在機場、軍事用地、墓地、高爾夫球場、鐵路用地與港區不畫城市的房子；機場只畫 OpenStreetMap 的航廈、機棚等建物。這個工具把它們從台灣的 OSM 整包檔取出，寫成 App 打包的 `RailwayGameApp/Resources/BaseMap/taiwan_no_build.json`，由 `GamePresentation` 的 `RealNoBuildLand` 讀。

## 重建

約 1 分鐘，需要 pyosmium（`pip install osmium`，BSD 2-Clause，決策 93；只在這裡用，不進 App）。幾何（面積、簡化、點在多邊形內）用標準函式庫。

```sh
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 -I tools/no-build-land/build_no_build.py taiwan.pbf \
  RailwayGameApp/Resources/BaseMap/taiwan_no_build.json
```

## 取哪些

| 種類 | OSM 標籤 |
| --- | --- |
| `airport` | `aeroway=aerodrome` |
| `military` | `landuse=military`，或任何 `military=*`（`no` 除外） |
| `cemetery` | `landuse=cemetery`、`amenity=grave_yard` |
| `golf` | `leisure=golf_course` |
| `railway` | `landuse=railway` |
| `port` | `landuse=port`、`industrial=port`、`man_made=pier` |

- 只取外環；小於 2,500 m² 的不要；Douglas–Peucker 簡化 3e-5°（約 3 m）。
- 機場的建物：重心在某個機場的外環內、150 m² 以上的 `building=*`，簡化 1.5e-5°。高度依序取 `height`、`1 + 3.5 × building:levels`、依 `building`／`aeroway` 的預設（`hangar` 14 m、`terminal` 與 `transportation` 16 m、`control_tower` 30 m），否則 7 m，限 3–80 m。用途：機棚 1、航廈 2、其他 0。
- 公園與水域不取：底圖的 `park`、`water` 層與 LandImport 的公園分區已經有。

## 格式

```json
{"source": "...", "newest": "2026-10-21T16:46:33Z",
 "kinds": ["airport", "military", "cemetery", "golf", "railway", "port"],
 "counts": {...},
 "areas": [[種類, 緯度, 經度, Δ緯度, Δ經度, ...], ...],
 "buildings": [[高度 m, 用途, 緯度, 經度, Δ緯度, Δ經度, ...], ...]}
```

座標是 1e-5° 的整數，每個環的第一點是絕對值，之後是和前一點的差；不重複最後一點。

## 2026-10-23 的資料

osmtoday.com 的整包檔，最新的編輯 2026-10-21：機場 43、軍事 724、墓地 2,797、高爾夫 117、鐵路 108、港區 64 個範圍；機場建物 1,460 棟（機棚 114、航廈 27）；檔案 624 KB。

資料 © OpenStreetMap 貢獻者，依 ODbL 1.0 使用；遊戲的「資料來源」頁（`DataSourceCredits` 的 `noBuildLand`）與官網 `credits.html` 有署名。
