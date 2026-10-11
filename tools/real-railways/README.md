# 實景鐵道以 OSM 為準

App 的實景鐵道（`RailwayGameApp/Resources/RealRailways/track_lines.geojson`、`track_stations.geojson`）的路線、站名、顏色、畫的順序是作者 `Railway/` 網站的原檔（交通部 TDX，私有參考 `581db83` 的 `Railway/site_archive_clean/data/`，自 `2db0c5a` 沒有改過），**線形以 OpenStreetMap 為準**（決策 151，2026-10-11 作者：「既然底圖都是了就線形以 OSM 為準」）：

- `match_osm.py`：讀和底圖、水域、分區同一份 osmtoday 整包檔（pyosmium），把每條線沿 OSM 的軌道重畫，車站移到線上；
- `osm_exceptions.json`：刻意保留 TDX 線形的路段，以及兩個原檔的 sha256。

```sh
pip install osmium
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 tools/real-railways/match_osm.py taiwan.pbf \
  <railway-reference-private>/Railway/site_archive_clean/data/track_lines.geojson \
  <railway-reference-private>/Railway/site_archive_clean/data/track_stations.geojson \
  tools/real-railways/osm_exceptions.json \
  RailwayGameApp/Resources/RealRailways/track_lines.geojson \
  RailwayGameApp/Resources/RealRailways/track_stations.geojson
```

## 怎麼對到 OSM

照參考庫 `Railway/site_archive_clean/rail-3d/physical/topology.js` 的原則：軌道靠共用的節點相接，不靠座標接近合併。

1. **軌道**：OSM 的 `railway=rail|subway|light_rail|monorail|tram|narrow_gauge`，不含側線、站場、支線、渡線（`service=siding|yard|spur|crossover`），也不含名字寫著已崩塌、已廢的線。每條軌道用參考的 `railwaySystem`（營運者、路網、名稱、軌距）判斷屬於哪個系統；沒有標的月台線（參考也說「月台線常省略 operator/gauge」）同種類的系統都能用。
2. **錨點**：沿原線每 2 km 一個，吸到 80 m 內的軌道上（軌道每 20 m 補一點，隧道裡 OSM 的節點常相隔一百多公尺）。
3. **兩個錨點之間**：在那個系統的軌道上找最便宜的路，每段的成本是長度 ×（1 +（離原線的距離 ÷ 15 m）²），所以會留在原線那一側的雙線、不會跑到別條線。每一段接在上一段的終點，雙線只走其中一條（渡線不算）。
4. **檢查**：一段離原線超過 100 m、長度差太多，或附近沒有軌道，就保留原線並列在輸出裡；沒有軌道的那一段會切成每 200 m 再試，只有真的沒有軌道的那一小截保留。結果用 Douglas–Peucker 1 m 簡化，小數 6 位（約 0.1 m）。原本首尾相接的線，新的也接在同一點。
5. **車站**：同一系統、同名的車站（一站多條線各有一筆）一起移到那個系統的新線上最近的一點，60 m 內才移，否則留在原處。

## 2026-10-11 的結果

整包檔 osmtoday.com 2026-10-10 下載（OSM 資料到 2026-10-08；軌道最新的編輯 2026-10-03）：4,626 條軌道。79 條線中，原線離新線的中位數多半 0–5 m，最多的是高捷紅線 77 m（草衙–機場，原本手動修正的那段）、林鐵本線 76 m（獨立山一帶）、高捷橘線 42 m、北迴線 41 m、機捷 39 m。549 個站點移到線上，中位數 4 m、最多 57 m。

**保留原線的地方**（輸出會列出）：

- 林鐵本線的多林一帶（約 49.5–50.5 km）：`osm_exceptions.json` 的 `afr-main-duolin`。OSM 在這裡只有「阿里山森林鐵路登山本線 (已崩塌舊線)」的多林隧道（way 340255673），離現行線最多 90 m；TDX 的才是現行路線。作者決定只保留這一段。
- 高鐵南港端約 1.4 km、左營端約 1 km：TDX 的線畫進車輛基地，OSM 那裡只有站場的股道（`service=yard`）。
- 林鐵嘉義站的頭 200 m：OSM 站內的林鐵軌道沒有標，離原線 120 m 以上。
- 板南線一段 12 m 的短線（太短，不對）。
- 不在線上 60 m 內、留在原處的車站：台鐵車埕、高鐵板橋、機捷機場第一航廈。

原本 `osm_patches.json` 手動修正的三段（高捷紅線草衙–機場、高捷橘線鹽埕埔、林鐵祝山線的髮夾彎）由這次的比對自動涵蓋：三段修正點到新線的距離都在 2.5 m 以內，所以修正檔與 `apply_osm_patches.py` 退休。

## 新增一段例外

只有 OSM 確定過時或標錯（在衛星影像上確認過），才在 `osm_exceptions.json` 加一段：`from` 與 `to` 是原線上的兩點，之間保留 TDX 的線形；`middle` 是中間的一個原線頂點，`RealRailwaysTests` 檢查打包的線經過它。其他時候改 OSM 本身，再重新產生。

## 授權

線形與車站位置來自 OpenStreetMap：© OpenStreetMap 貢獻者，依 ODbL 1.0 使用。遊戲的資料來源畫面（`DataSourceCredits`）已經標示，產生的 `track_lines.geojson`、`track_stations.geojson` 依同一授權在本 repo 提供。

---

以下是 2026-10-05 第一次比對的紀錄（那時以網站原檔為準，只修正三段）。

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

