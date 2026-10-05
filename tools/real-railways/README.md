# 實景鐵道的 OSM 修正

App 的實景鐵道（`RailwayGameApp/Resources/RealRailways/track_lines.geojson`）以作者 `Railway/` 網站的原檔為底（私有參考 `2db0c5a` 的 `Railway/site_archive_clean/data/track_lines.geojson`）。2026-10-05 作者表示網站不再維護，所以路線形狀偏離真實軌道的地方，改由遊戲自己從 OpenStreetMap 修正：

- `osm_patches.json`：每一段修正的路線、原因、取用的 OSM way、資料時間，以及取代原線的點；
- `apply_osm_patches.py`：把修正套到網站原檔，產生 App 打包的檔案（只用 Python 標準函式庫）。

```sh
python3 tools/real-railways/apply_osm_patches.py \
  <railway-reference-private>/Railway/site_archive_clean/data/track_lines.geojson \
  RailwayGameApp/Resources/RealRailways/track_lines.geojson
```

腳本只接受修正所依據的那份原檔（比對 sha256），每段修正的兩端也必須落在被取代的原線上，否則拒絕。`RealRailwaysTests` 檢查打包的檔案含有每一段修正，所以之後若有人把網站原檔直接複製回來，測試會失敗。

## 2026-10-05 的比對

方法：從 Overpass API（maps.mail.ru 鏡像）下載台灣所有 `railway=rail|subway|light_rail|tram|monorail|narrow_gauge` 的 way（OSM 資料時間 2026-10-05 11:32–11:42 UTC），沿 App 每條線每 25 m 取一點，量到最近一條同類軌道的距離（台鐵對一般鐵路、高鐵對 `highspeed=yes`、林鐵對 762 mm 軌距、捷運與輕軌對都市軌道）。

| 系統 | 中位數 | 最大 | 結果 |
| --- | --- | --- | --- |
| 台鐵 16 條 | 0 m | 29 m | 網站本來就取自 OSM，一致 |
| 北捷 9 條 | 0–5 m | 28 m | 一致 |
| 機捷、淡海、安坑、三鶯、台中綠線、高雄環狀輕軌 | 1–2 m | 5–25 m | 一致 |
| 高鐵 | 1.5 m | 24 m | 一致；左營附近一段 OSM 沒有標 `highspeed=yes`，改量到最近的軌道 |
| 高捷紅線 | 3 m | 78 m | **修正**：草衙–高雄國際機場 |
| 高捷橘線 | 3 m | 43 m | **修正**：鹽埕埔 |
| 林鐵祝山線 | 1 m | 55 m | **修正**：祝山下方的髮夾彎 |
| 林鐵本線 | 2 m | 約 120 m | 不修正，見下面 |

三段修正都先在 Esri World Imagery 衛星影像上疊圖確認：高捷兩段的 OSM 隧道沿著街道到車站，網站的線形抄了近路；祝山線的 OSM 沿著影像上看得到的路基。修正的點取自同一條相連的 OSM 軌道（雙線的捷運取其中一條，離中心線幾公尺），兩端接在原線離 OSM 不到 2 m 的地方。

**不修正的：**

- 林鐵本線多林一帶：OSM 在那裡只有「阿里山森林鐵路登山本線 (已崩塌舊線)」的多林隧道（仍標為 `railway=narrow_gauge`），網站（交通部 TDX）的線是現行路線，OSM 反而過時。
- 林鐵本線獨立山一帶 40–100 m 的幾處小偏差：沒有逐段用影像確認，保留原檔。
- OSM 有、App 沒有畫的：糖業鐵路、舊山線、花蓮臨港線與臺中港線（貨運）、北迴線的新永春隧道（OSM 的新舊兩座都標成正線，原檔走永春隧道）、機場航廈電車、義大單軌、草衙道電車，以及萬大線的施工路段與各系統機廠、尾軌的短線。都不是一般客運路線，或是同一條線的另一條軌道。

## 新增一段修正

1. 下載當時的 OSM 軌道，找出 App 的線偏離的路段。
2. 在衛星影像上確認哪一邊才是真實的軌道；OSM 也可能過時或標錯（例如上面的多林隧道）。
3. 在 `osm_patches.json` 加一段：`afterVertex` 與 `beforeVertex` 是保留的原線頂點（取代兩者之間的頂點），`points` 的第一點與最後一點必須在原線的 `afterVertex → afterVertex+1` 與 `beforeVertex−1 → beforeVertex` 兩段上，中間是 OSM 軌道的點（經緯度小數 6 位）。
4. 執行 `apply_osm_patches.py`，並把新的一段加進 `RealRailwaysTests` 期望的 id 清單。

## 授權

修正的點來自 OpenStreetMap：© OpenStreetMap 貢獻者，依 ODbL 1.0 使用。遊戲的資料來源畫面（`DataSourceCredits`）已經標示，修改後的 `track_lines.geojson` 依同一授權在本 repo 提供。
