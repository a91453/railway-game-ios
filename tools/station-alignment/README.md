# 車站對位量測（決策 1021）

車站規則 (b)：量遊戲鋪的月台離真實（OpenStreetMap）月台多遠，真實站房有沒有壓到遊戲鋪的軌道。**只出表，不改遊戲。**
表給 (c)「把規則套到所有地圖」用：偏太多的站要修到對上，再用測試守住偏差上限。

## 量哪些站

作者 2026-11-27：「只需要目前可收購路線 月台/站房，還有不可收購但是站房已製作的 月台/站房資料，記得台灣高鐵也要納入」。

1. **可收購的路線**，每張地圖的每個線組照遊戲列出的順序依序買下（決策 862），量每條線的每一站：
   台灣的六條台鐵支線、淡海輕軌兩條、安坑輕軌、新北投與小碧潭支線、三鶯線、文湖線、桃園機場捷運、高雄環狀輕軌、台灣高鐵；
   香港目前賣的東涌綫、機場快綫、迪士尼綫、東鐵綫（落馬洲）、將軍澳綫（康城）、南港島綫；羅瓦涅米兩條；
   福岡地鐵三條、九州新幹線、西九州新幹線（從另一個起點開局才買得到，`NishiKyushuShinkansenTests` 的做法）。
2. **沒在賣、但遊戲畫了真實站房的站**：決策 625／626／665 的站房外觀（第一批 11 站、第二批 9 站）、決策 929 的工作室高鐵站（苗栗、彰化、雲林、嘉義），
   決策 370／431 的台北車站、高雄車站地標。每處 400 m 內的真實車站，用「收購單一真實車站」（決策 400 A.8）買下來量，玩家能這樣蓋的就是這樣鋪。

## 怎麼跑

```sh
# 1. 真實資料（已經抽好放在 data/；OSM 更新時才要重抽）
curl -LO https://osmtoday.com/asia/taiwan.pbf            # 也有 asia/japan/kyushu、asia/china/hong_kong、europe/finland/lapland
pip install osmium
python3 -I tools/station-alignment/extract_osm_platforms.py taiwan.pbf tools/station-alignment/data/taiwan.json

# 2. 量（Linux 約 5 分鐘）
swift build --build-tests
STATION_ALIGN_REPORT=/tmp/station-align.tsv swift test --skip-build --filter StationAlignmentReportTests
STATION_ALIGN_ONLY=taiwan-stations ...   # 只量一部分：taiwan-stations（有站房的站）、taiwan-lines、hongkong、rovaniemi、fukuoka
```

`data/` 四份檔是 2026-11-27 osmtoday.com 的整包檔抽出來的（`railway=platform` 或標了火車／地鐵／輕軌的 `public_transport=platform`，
以及 `building=train_station`、`building=transportation`、標了 `railway=station` 的建物），ODbL 1.0，© OpenStreetMap contributors。
台鐵各站另外對 App 裡的 `tra_platforms.json`（2026-08，各站所有月台頂點相距最遠的兩點）。

## 表的欄位（`REPORT-2026-11-27.tsv`，由偏最多排到最少）

| 欄 | 意思 |
| --- | --- |
| `how` | `收購路線 <線>` 或 `已做站房，收購單站` |
| `problem` | 買不下來的原因（遊戲給玩家的那句話）；有原因的列沒有量 |
| `game_platform_m`、`game_tracks`、`over_ground_m` | 遊戲鋪的月台沿線長度、月台股數、中間離地高度（地下為負） |
| `osm_platforms`、`osm_length_m` | 配到的 OSM 月台座數與它們合起來的沿線長度；空白＝OSM 這裡沒畫月台（缺資料） |
| `start_shift_m`、`end_shift_m` | 遊戲月台兩端減 OSM 月台兩端，沿遊戲的月台量（正＝往遊戲月台的前進方向） |
| `middle_shift_m` | 兩者中點沿線差多少 |
| `outside_real_m` | 遊戲月台伸出真實月台兩端外的長度合計；遊戲月台比真實短但在範圍內＝0 |
| `across_m` | 中線橫向偏差：遊戲月台股道群的中線對 OSM 月台群的中線 |
| `worst_m` | `outside_real_m` 與 `across_m` 取大的，排序用 |
| `other_osm_groups_across_m` | 80 m 內另一組月台（別條線、舊站）在橫向哪裡 |
| `track_through_real_platform_m` | 遊戲的軌道（月台前後 50 m）有多少公尺穿過真實月台的範圍：軌道鋪在真實月台上 |
| `tra_platforms_json_ends_m` | 台鐵站：遊戲月台兩端對 `tra_platforms.json` 兩端（`derived`＝OSM 沒畫、資料自己推估的） |
| `buildings_near` | 附近的真實站房與離遊戲軌道最近的距離：`外觀 …` 決策 625／626／665／929、`地標 …` 決策 370／431、`OSM w…/r…` |
| `buildings_on_track` | 站房輪廓 2.2 m 內有遊戲軌道的：`壓軌 N m`（軌道離地 −3～6 m）、`穿過`（高架或地下，不算撞） |

## 怎麼配對、哪裡不準

- OSM 月台：同一系統的（標了別的車種的不算）、橫向 80 m 內、沿線伸到遊戲月台 100 m 內的，挑橫向最近的一座，再收它 30 m 內的成一組。
  大站（台北、南港、博多）好幾條線的月台並排，會配到別條線的；`other_osm_groups_across_m` 看得出旁邊還有哪幾組。
- 單股岸式的站，遊戲月台畫在軌道旁，`across_m` 本來就會有 3～4 m。
- 站房外觀（決策 625、665）本來就照真實軌道切開，`壓軌` 只說軌道進了站房的輪廓，不一定畫出來會撞；要對照 3D 看。
- 福岡地鐵：OSM 幾乎沒畫地鐵月台（37 列缺資料）；博多那列配到的是 JR 的月台，不可信。香港九龍、青衣、將軍澳、康城也沒有。
