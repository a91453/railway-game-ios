# 車站外觀第一批 studies：第 4 次交付

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

## 已完成：臺鐵花蓮

| 部件 | OSM 足跡最小旋轉矩形 | 高度與屋頂 |
| --- | --- | --- |
| 跨站大廳／自由廊道 | [way 554768918](https://www.openstreetmap.org/way/554768918)，152.754 × 45.547 m，`building:levels=3` | OSM 無高度或屋頂標籤；底部 6 m、頂部 17 m、玻璃帶和平頂推估。 |
| 售票大廳 | [way 554768913](https://www.openstreetmap.org/way/554768913)，54.908 × 50.028 m | 頂部約 11 m、直立肋條和屋頂推估。 |
| 迎客大傘 | [way 718223887](https://www.openstreetmap.org/way/718223887)，73.741 × 30.409 m，`building:levels=2` | 棚緣約 11–12 m、五段波浪與支柱位置推估。 |
| 前站舊站體 | [way 132937553](https://www.openstreetmap.org/way/132937553)，88.067 × 18.506 m | 約 9 m 低平屋頂與窗列推估。 |
| 後站 | [way 132937567](https://www.openstreetmap.org/way/132937567)，62.454 × 23.299 m | 約 9 m 低平屋頂與窗列推估。 |
| 三條月台棚 | [ways 1342634750](https://www.openstreetmap.org/way/1342634750)、[1342634751](https://www.openstreetmap.org/way/1342634751)、[1352337182](https://www.openstreetmap.org/way/1352337182)，依序 194.747 × 10.278、194.747 × 10.723、194.751 × 11.527 m；皆 `building:levels=1` | 棚面約 5.96 m；近／遠柱距 15／35 m 推估。 |

八個 way 的全部非閉合邊界頂點從 2026-11-06 下載的 osmtoday `asia/taiwan.pbf` 擷取。參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/hualien-v1/metadata.json` 只用來核對相同 way 的尺寸與相對位置，`blender-buildings-v1/hualien-v1/model.json` 只量比例，沒有搬網格。OSM 局部公尺座標原點為 121.60093265°E、23.992764°N。八個 way 均無實測 `height`、`roof:height`、`roof:shape`；上述高度和屋頂全部是推估。輪廓 © OpenStreetMap contributors，ODbL 1.0。

外觀只參考 Wikimedia Commons [東側站房與大傘](https://commons.wikimedia.org/wiki/File:Hualien_Station_east_20230504.jpg)、[西側舊站房](https://commons.wikimedia.org/wiki/File:Hualien_Station_west_20230504.jpg)、[大傘下方木肋](https://commons.wikimedia.org/wiki/File:Hualien_railway_station_east_entrance_2018.png)、[東側遠景](https://commons.wikimedia.org/wiki/File:Early_morning_view_of_TRA_Hualien_Station,_looking_northwest_from_the_room_window_at_the_five_floor_of_Hualien_WOW_Youth_Hostel_on_4_December_2021.jpg)。照片沒有作貼圖。以 station kit 盒體、曲棚、淡暖牆、淺色棚、木色肋與青灰玻璃簡化重建，保留明暗順序。近景 **3,234 三角**、遠景 **1,830 三角**；仍待作者驗收外觀。

## 已完成：臺鐵臺東

| 部件 | OSM 足跡最小旋轉矩形 | 外觀與推估 |
| --- | --- | --- |
| 臺東站房 | [way 386900387](https://www.openstreetmap.org/way/386900387)，**87.521 × 24.017 m**，12 個不重複頂點 | OSM 只標 `building=train_station`，沒有高度、層數或屋頂形狀。模型的粉灰牆、玻璃入口及約 13.5 m 的平緩後屋頂依照片與參考展示比例推估。 |
| 前廊雨棚 | [way 724860888](https://www.openstreetmap.org/way/724860888)，**89.527 × 24.091 m**，10 個不重複頂點；`building=roof`、`layer=1` | 兩排連續拱棚依站房正面照片重建；棚緣約 6.6／9.5 m、曲度、節距、柱位與色階均推估。 |
| 三條月台棚 | [ways 386900423](https://www.openstreetmap.org/way/386900423)、[386900424](https://www.openstreetmap.org/way/386900424)、[386900425](https://www.openstreetmap.org/way/386900425)，分別 **226.128 × 9.757 m**、**238.757 × 9.684 m**、**227.231 × 10.604 m**；各 4 個不重複頂點，皆 `building=roof` | OSM 無高度、屋頂形狀與支柱資訊；棚面約 5.62 m，近／遠柱距約 14／31 m 皆推估。 |

五個 way 的全部非閉合邊界頂點來自 2026-11-06 下載的 osmtoday `asia/taiwan.pbf`，以 pyosmium 擷取。局部公尺座標原點為 121.12276045°E、22.79349185°N；相同 way 的尺寸、相對位置和旋轉角與參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/taitung-v1/metadata.json` 核對。`blender-buildings-v1/taitung-v1/model.json` 只量站房／雨棚／月台棚比例，沒有搬網格。輪廓 © OpenStreetMap contributors，ODbL 1.0。

外觀只看 Wikimedia Commons [2018 年站房正面](https://commons.wikimedia.org/wiki/File:TRA_Taitung_Station_20180502.jpg)、[2013 年入口夜景](https://commons.wikimedia.org/wiki/File:TRA_Taitung_Station_main_entrance_20131203_night.jpg)、[2008 年月台棚下方](https://commons.wikimedia.org/wiki/File:Platform_2,_TRA_Taitung_Station_20080606.jpg)。照片沒有作貼圖。以現有 station kit 的盒體、封閉曲棚和淡色調組出近景／遠景；保留淺色拱棚比牆亮、窗與棚底較暗的順序。近景 **3,722 三角**、遠景 **1,754 三角**；拱棚桁架與細部仍需作者看外觀後確認。

## 尚缺的七站

| 站 | 來源與目前量到的部件足跡（m） | 還缺的核對 |
| --- | --- | --- |
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
