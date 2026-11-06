# 車站外觀第一批 studies：第 2 次交付

這是獨立研究配方，沒有接到 `Map3DStationKit` 的站點選型、地圖或存檔。公開庫只有配方、測試與一張總覽；逐方向原生模型、GLB、日夜圖與離線檢視頁在私有素材庫的同名資料夾。

## 已完成：臺鐵臺中

| 部件 | 可核對的尺寸／資料 | 外觀判斷與推估 |
| --- | --- | --- |
| 新站主體 | OSM way [442234244](https://www.openstreetmap.org/way/442234244)，足跡最小旋轉矩形 318.276 × 118.043 m，`height=37` m、`building:levels=3`；地面邊界 45 個不重複頂點原樣轉為公尺坐標 | 延續現有 station kit 的曲棚零件；弧度、11.7 m 基座、柱距、玻璃帶與軌面高度均為外觀推估。Blender v1 只核對長屋頂相對基座的比例，沒有搬用網格。 |
| 舊臺中驛 | OSM way [223056023](https://www.openstreetmap.org/way/223056023)，足跡 57.949 × 14.772 m，`building:levels=2`、`roof:shape=hipped`；地面邊界 11 個不重複頂點 | 紅磚、中央鐘塔與深色四坡頂；總高 13 m、塔與窗比例是參考庫 Blender v1／外觀資料的展示推估。沒有中式屋頂。 |

地面邊界從 2026-11-06 下載的 osmtoday `asia/taiwan.pbf` 以 pyosmium 讀取；長寬、兩棟相對位置與旋轉角來自參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/tra-taichung-v1/metadata.json`，以相同 way 核對。座標的轉公尺為局部近似，範圍內誤差低於 2 m。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0；照片只作外觀參考，不含照片貼圖。參考庫 Blender v1 的 `tra-taichung-v1/model.json` 只量比例，沒有使用原網格。

外觀照片核對（僅看外形，未用貼圖）：Wikimedia Commons 的 [2022-03 TRA Taichung Station](https://commons.wikimedia.org/wiki/File:2022-03_TRA_Taichung_Station.jpg)、[2022 Space frames of the TRA Taichung Station](https://commons.wikimedia.org/wiki/File:2022_Space_frames_of_the_TRA_Taichung_Station.jpg) 顯示新站的長玻璃立面、白灰結構柱與金屬棚；[Facade of the old Taichung Station](https://commons.wikimedia.org/wiki/File:Facade_of_the_old_Taichung_Station.png) 顯示舊驛的紅磚、淺色飾帶、深色瓦頂、中央高窗與鐘塔。研究版抽象掉桁架和拱窗細雕，並以近景主體、遠景輪廓區分。

用既有 `StationKitBuilder` 的盒體、曲棚、四坡頂與鐘面組合；新站取 OSM 的基底和高度，舊驛用 OSM 站房輪廓與四坡屋頂標籤，紅磚色照外觀照片，窗與柱列以近景加細、遠景減省。最後調為淡白、暖牆、淡磚與灰褐屋頂，維持牆／屋頂／窗的明暗區分。近景 **1,166 三角**（上限 6,000）、遠景 **602 三角**（上限 2,500）；逐檔數量見私庫 `manifest.json`。

## 已完成：臺鐵新竹

| 部件 | 可核對的尺寸／資料 | 外觀判斷與推估 |
| --- | --- | --- |
| 新竹站房 | OSM way [293504390](https://www.openstreetmap.org/way/293504390)，16 個不重複頂點，最小旋轉矩形 **143.68 × 16.87 m**、長軸由東往北約 32.2°，`height=9` m、`building:levels=2` | OSM 沒有屋頂形狀、`building:part` 或 `roof:height`；本版把 9 m 當兩翼站房高度。站房中央綠瓦大屋頂的脊高約 13 m、鐘塔到 20.9 m 皆是照片與 Blender v1 比例推估，非 OSM 高度。 |

站房地面邊界從同一份台灣 PBF 量測。參考庫 `blender-buildings-v1/hsinchu-tra/model.json` 的 65 × 22 × 20 m 是舊展示估值，長度不足 OSM 143.68 m，僅用來看鐘塔與中段立面比例，不用原網格。外觀照片看 Wikimedia Commons [新竹火車站（巴洛克風格）](https://commons.wikimedia.org/wiki/File:新竹火車站(巴洛克風格).jpg) 與 [新竹市火車站夜景](https://commons.wikimedia.org/wiki/File:新竹市火車站.jpg)：淺色拱窗立面、中央高廳、鐘塔及綠色屋頂。沒有照片貼圖；使用 station kit 的四坡頂、盒體與鐘面，沒有中式屋頂。研究版的拱窗細部與屋頂坡度是視覺簡化。近景 **846 三角**、遠景 **318 三角**；逐檔數量見私庫 `manifest.json`。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0。

## 尚缺的九站

| 站 | 來源與目前量到的部件足跡（m） | 還缺的核對 |
| --- | --- | --- |
| 臺鐵花蓮 | 參考庫 `stations/hualien-v1/metadata.json` 的 OSM 輪廓：花蓮跨站大廳 153 × 46（554768918）；花蓮售票大廳 55 × 50（554768913）；迎客大傘 74 × 30（718223887）；花蓮前站 88 × 19（132937553）；花蓮後站 62 × 23（132937567）；月台棚 195 × 10（1342634750）；月台棚 195 × 11（1342634751）；月台棚 195 × 12（1352337182） | 8 部件的屋頂及真實高度。 |
| 臺鐵臺東 | 參考庫 `stations/taitung-v1/metadata.json` 的 OSM 輪廓：臺東車站 88 × 24（386900387）；前廊雨棚 90 × 24（724860888）；月台棚 226 × 10（386900423）；月台棚 239 × 10（386900424）；月台棚 227 × 11（386900425） | 5 部件的坡頂、前廊與真實高度。 |
| 臺鐵板橋 | 參考庫 `stations/banqiao-v1/metadata.json` 的 OSM 輪廓：板橋車站 199 × 122（232201616）；板橋站塔樓 44 × 42（1491394339）；板橋站塔樓 44 × 42（1491394340）；環狀線板橋 91 × 35（818694787） | 雙塔與站體真實高度及照片細節。 |
| 臺鐵南港 | 參考庫 `stations/nangang-v1/metadata.json` 的 OSM 輪廓：南港車站 213 × 134（233331393）；南港 A 棟 61 × 35（908843920）；南港 B 棟 84 × 39（411044008）；南港 C 棟 112 × 42（410390808）；南港東側站房 83 × 42（556511660） | A／B／C 棟真實高度與外觀。 |
| 高鐵桃園 | 參考庫 `stations/taoyuan-hsr-v1/metadata.json` 的 OSM 輪廓：高鐵桃園 122 × 74（23547222）；機捷 A18 154 × 52（560119012） | 挑簷、採光頂與真實高度。 |
| 高鐵新竹 | 參考庫 `stations/hsinchu-hsr-v1/metadata.json` 的 OSM 輪廓：高鐵新竹 344 × 101（321663134）；六家 48 × 34（321663135） | 長曲頂與真實高度。 |
| 高鐵台中（含新烏日） | 參考庫 `stations/xinwuri-complex-v1/metadata.json` 的 OSM 輪廓：高鐵臺中 360 × 96（544377825）；新烏日 210 × 84（337921979）；中捷高鐵臺中 180 × 22（862779522）；轉乘通廊 33 × 10（862779521）；轉乘通廊 48 × 12（862779520） | 高鐵／臺鐵／中捷共構關係與各屋頂、真實高度。 |
| 高鐵台南 | 參考庫 `stations/tainan-hsr-v1/metadata.json` 的 OSM 輪廓：高鐵臺南 114 × 57（r9351022:1）；高鐵月台棚 336 × 14（r9351022:0）；高鐵月台棚 332 × 11（266850895）；沙崙 149 × 27（316034163） | 挑簷、月台棚與真實高度。 |
| 高鐵左營 | 參考庫 `stations/zuoying-complex-v1/metadata.json` 的 OSM 輪廓：高鐵左營 186 × 78（111991261）；臺鐵新左營 168 × 67（303296097） | 大頂與真實高度。 |

上表尺寸是參考庫依 OSM 輪廓量出的最小矩形，括號內為 OSM way／relation 識別；這些站的 `displayHeightM` 都是展示推估，**尚未**作為真實高度。每站完成前須從整份 Taiwan PBF 重新核對 way、`building:part`、高度與屋頂標籤，再看照片選各部件，並另做近遠兩版。資料出處同為 © OpenStreetMap contributors，ODbL 1.0。

## 檢查與邊界

測試驗證新研究模型的三角預算、每個 OSM 地面頂點、近遠兩版，以及研究 ID 不進現有 station kit 查表。現有站型原始檔、營運映射與雜湊均未改；GameCore、golden、save 與 fixtures 未改。Metal/iPhone/iPad、正式地圖放置與作者外觀接受仍未驗證。
