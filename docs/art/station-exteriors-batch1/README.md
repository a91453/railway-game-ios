# 車站外觀第一批 studies：第 9 次交付

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

## 已完成：臺鐵板橋

| 部件 | OSM 足跡最小旋轉矩形 | 高度與外觀判斷 |
| --- | --- | --- |
| 板橋車站大樓母體 | [way 232201616](https://www.openstreetmap.org/way/232201616)，**199.488 × 121.932 m**，37 個不重複頂點；OSM 標 `height=116.8` m、`building:levels=25`、地下 5 層 | **116.8 m 是 OSM 母體標籤**，作雙塔頂標高。照片顯示低層長站體、兩端圓筒與中央深色玻璃；約 20 m 低層高度、柱窗和三段淺棚曲度都是推估，地下層不建模。 |
| 南側塔樓分件 | [way 1491394339](https://www.openstreetmap.org/way/1491394339)，**44.170 × 42.088 m**，4 個頂點；`building:part=commercial` | 分件沒有自己的高度標籤；以母體 116.8 m 為頂、約 20 m 為起點。淺粉灰窗格、頂部外挑檐板依照片推估。 |
| 北側塔樓分件 | [way 1491394340](https://www.openstreetmap.org/way/1491394340)，**44.169 × 42.086 m**，4 個頂點；`building:part=commercial` | 同上。雙塔及深色中段按照片和 OSM 分件相對位置組合，窗距不當作實測樓層分隔。 |
| 環狀線板橋站 | [way 818694787](https://www.openstreetmap.org/way/818694787)，**91.185 × 34.580 m**，13 個頂點；`layer=1` | OSM 沒有高度或屋頂形狀。底部約 7 m、頂部約 22 m、低弧棚與柱距依參考展示比例和外觀照片推估。 |

四個 way 的全部非閉合頂點取自 2026-11-06 下載的 osmtoday `asia/taiwan.pbf`，以 pyosmium 擷取；局部公尺座標原點為 121.4640451°E、25.0144511°N。同 way 尺寸和相對位置與參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/banqiao-v1/metadata.json` 核對；`blender-buildings-v1/banqiao-v1/model.json` 僅看雙塔、低層與高架站比例，不用網格。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0。

外觀照片只看 Wikimedia Commons [2014 年板橋車站大樓](https://commons.wikimedia.org/wiki/File:Banqiao_Station_Building_20140610.jpg)、[從新北市政府望向站體](https://commons.wikimedia.org/wiki/File:新北市_板橋車站大樓_Banciao_Station_From_New_Taipei_City_Hall_-_panoramio.jpg)、[塔樓入口](https://commons.wikimedia.org/wiki/File:Banqiao_Station_Building_N1A_20230909.jpg) 及[環狀線列車望向高架站](https://commons.wikimedia.org/wiki/File:Train_on_MRT_Circular_Line_Meeting_near_Banqiao_Station_01.jpg)。照片不作貼圖。以 station kit 盒體、圓柱、曲棚與淡色玻璃抽象重建；近景 **3,609 三角**、遠景 **1,693 三角**。窗格、低層平面、環狀線棚面與兩端圓筒仍待作者核對外觀。

## 已完成：臺鐵南港

| 部件 | OSM 足跡最小旋轉矩形 | 高度、屋頂與外觀判斷 |
| --- | --- | --- |
| 南港車站主體 | [way 233331393](https://www.openstreetmap.org/way/233331393)，**213.365 × 133.741 m**，39 個不重複頂點；`building:levels=7` | OSM 沒有高度或屋頂標籤。低層站體約 **28 m**、正面白色鋼架入口與平頂、紅褐牆面依外觀照片及參考展示比例推估。 |
| A 棟 | [way 908843920](https://www.openstreetmap.org/way/908843920)，**60.828 × 35.075 m**，8 個頂點；`building:part=commercial`、`building:levels=30`、`building:min_level=8` | OSM `height=139` m，作塔頂標高。從約 **28 m** 起建是推估；青灰玻璃窗格及頂部淺色檐板依照片簡化。 |
| B 棟 | [way 411044008](https://www.openstreetmap.org/way/411044008)，**84.334 × 39.439 m**，4 個頂點；`building:part=hotel`、`building:levels=30` | OSM `height=139` m，作塔頂標高。起建標高、窗格節距及屋頂邊線推估。 |
| C 棟 | [way 410390808](https://www.openstreetmap.org/way/410390808)，**112.123 × 41.657 m**，23 個頂點；`building:levels=14`、`layer=1` | OSM `height=70` m，作頂部標高。白色下層、玻璃上層與圓筒端部依開發商外觀照片；分層高度、窗距與圓筒尺寸推估。 |
| 東側站房 | [way 556511660](https://www.openstreetmap.org/way/556511660)，**83.080 × 42.289 m**，31 個頂點；`building=retail` | OSM 沒有高度或屋頂標籤。約 **23 m** 的淺色曲棚、玻璃入口及圓筒端部依外觀照片推估。 |

五個 way 的全部非閉合邊界頂點從 2026-11-06 下載的 osmtoday `asia/taiwan.pbf` 以 pyosmium 擷取，轉為局部公尺座標；原點為 121.60664345°E、25.0528905°N。尺寸、旋轉角及五棟相對位置與參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/nangang-v1/metadata.json` 核對；`blender-buildings-v1/nangang-v1/model.json` 只量大樓與低層站體比例，沒有搬用網格。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0。

外觀只看 Wikimedia Commons [2016 年忠孝東路側站體](https://commons.wikimedia.org/wiki/File:Nangang_Station_Building_face_to_Zhongxiao_East_Road_20160723b.jpg)、[2018 年 A／B 棟上段](https://commons.wikimedia.org/wiki/File:Nangang_Station_Building_A_%26_B_top_20180714.jpg)、[2012 年東側站房遠景](https://commons.wikimedia.org/wiki/File:Nangang_Station_view_from_Taipei_Extreme_Sports_Training_Center_20120909.jpg)、[東出口](https://commons.wikimedia.org/wiki/File:East_Exit,_Nangang_Station_20120909.jpg)，以及[三菱地所台灣南港開發案外觀](https://www.mectw.tw/project/investment/-MKzV0WreYKQtFywQCGo)。開發案頁面另列兩棟 30 層和商場 14 層，與 OSM 層數相符。照片不打包、不作貼圖。用現有 station kit 盒體、曲棚與圓柱組成淡色近／遠景，保留淺屋頂、紅褐牆、青灰玻璃與暗窗的明暗次序。近景 **5,565 三角**、遠景 **1,773 三角**；窗格、入口鋼架與東站房外形仍待作者核對。

## 已完成：高鐵桃園（含機捷 A18）

| 部件 | OSM 足跡最小旋轉矩形 | 高度、屋頂與外觀判斷 |
| --- | --- | --- |
| 高鐵桃園站房 | [way 23547222](https://www.openstreetmap.org/way/23547222)，**121.821 × 73.541 m**，26 個不重複頂點；`building=train_station` | OSM 沒有 `height`、層數或屋頂標籤。約 **20 m** 平頂是參考展示高度推估；成排採光帶、長玻璃立面、白色柱廊依外觀照片。 |
| 機捷 A18 高鐵桃園站 | [way 560119012](https://www.openstreetmap.org/way/560119012)，**153.716 × 52.474 m**，18 個不重複頂點；`building:levels=3`、`min_level=2`、`layer=1` | OSM 沒有 `height`、`min_height` 或屋頂標籤。架空基底約 **8 m**、簷約 **21–22 m**、弧棚最高約 **30 m** 全是參考展示比例推估；紅色立面、玻璃帶和鋼構弧棚依照片。 |

兩個 way 的全部非閉合邊界頂點從 2026-11-06 下載的 osmtoday `asia/taiwan.pbf` 以 pyosmium 擷取，轉為局部公尺座標；原點為 121.214539°E、25.01347985°N。尺寸、長軸角及兩棟相對位置與參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/taoyuan-hsr-v1/metadata.json` 核對；`blender-buildings-v1/taoyuan-hsr-v1/model.json` 僅量平頂站體與高架 A18 的比例，不使用原網格。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0。

照片只看 Wikimedia Commons [高鐵站房斜向外觀](https://commons.wikimedia.org/wiki/File:THSR_Taoyuan_Station_Exterior.jpg)、[2020 年高鐵站房與採光帶](https://commons.wikimedia.org/wiki/File:THSR_Taoyuan_Station_2020-08-15.jpg)、[高鐵站房正面](https://commons.wikimedia.org/wiki/File:THSR-Taoyuan.JPG)、[A18 高架站紅色立面與弧棚](https://commons.wikimedia.org/wiki/File:高鐵桃園站(機場捷運)外觀THSR_Taoyuan.jpg) 及[站區空照](https://commons.wikimedia.org/wiki/File:高鐵桃園站空照圖.jpg)。另核對[桃園捷運 A18 官方站頁](https://www.tymetro.com.tw/tymetro-new/tw/_pages/travel-guide/A18) 的站區配置，但不拿配置圖當比例尺。照片不打包、不作貼圖。現有 station kit 的盒體、曲棚、圓柱及柱列分件組成兩個獨立模型部分，最後調為淡灰白、淡砂牆、青灰玻璃與淡紅立面，保留明暗次序。採光帶節距、柱距、玻璃分格、弧棚曲率及所有估計高度仍待作者核對。近景 **2,124 三角**、遠景 **968 三角**。

## 已完成：高鐵新竹（含臺鐵六家）

| 部件 | OSM 足跡最小旋轉矩形 | 高度、屋頂與外觀判斷 |
| --- | --- | --- |
| 高鐵新竹站體 | [way 321663134](https://www.openstreetmap.org/way/321663134)，**343.597 × 101.181 m**，23 個不重複頂點；`building:levels=3`、`building:material=concrete`、`layer=2` | OSM 沒有高度或屋頂標籤。約 **28 m** 曲棚峰高是參考展示推估；長白色弧棚、玻璃大廳、鋼桁架及外側柱列依外觀照片簡化。 |
| 臺鐵六家站房 | [way 321663135](https://www.openstreetmap.org/way/321663135)，**47.533 × 33.789 m**，11 個不重複頂點；`building:levels=2`、`roof:shape=flat`、`layer=1` | OSM 有平頂形狀，沒有高度或 `roof:height`。約 **13 m** 總高、玻璃上層與低層柱距依參考比例和照片推估。 |

兩個 way 的全部非閉合邊界頂點從 2026-11-06 下載的 osmtoday `asia/taiwan.pbf` 以 pyosmium 擷取，轉為局部公尺座標；原點為 121.04001555°E、24.8083231°N。尺寸、方向與兩棟相對位置和參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/hsinchu-hsr-v1/metadata.json` 核對；`blender-buildings-v1/hsinchu-hsr-v1/model.json` 只量曲棚、站廳與六家站的體量比例，不用原網格。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0。

外觀只看 Wikimedia Commons [高鐵站長曲棚與玻璃大廳](https://commons.wikimedia.org/wiki/File:THSR_Hsinchu_Station_01.jpg)、[另一側弧棚與鋼構](https://commons.wikimedia.org/wiki/File:THSR_Hsinchu_Station_20120911.jpg)、[高鐵新竹與六家站相對位置](https://commons.wikimedia.org/wiki/File:THSR_Hsinchu_Station_and_TRA_Liujia_Station_2022-02-13.jpg)、[六家站正面](https://commons.wikimedia.org/wiki/File:TRA_Liujia_Station_2022-02-13.jpg) 及[轉乘外廊夜景](https://commons.wikimedia.org/wiki/File:The_walkway_between_THSR_Hsinchu_Station_and_TRA_Liujia_Station_night_scene_20111113.jpg)；[高鐵官方站區圖](https://www.thsrc.com.tw/ArticleContent/a7a04c89-900b-4798-95a3-c01c455622f4/assets/1f4c3f57-f8ec-4834-bb14-26fa003f8085.pdf) 只核對配置，沒有當測量尺度。照片不打包、不作貼圖。以現有 station kit 盒體、曲棚、柱與鋼架配方組成兩棟，淡白屋頂、淡混凝土、青灰玻璃和深色桁架保留明暗順序。棚面板縫、弧度、站廳比例、柱距與六家站高均為推估；未有 OSM 輪廓的轉乘通廊及精確月台位置未建模。近景 **1,950 三角**、遠景 **894 三角**，仍待作者核對外觀。

## 已完成：高鐵台中（含臺鐵新烏日、中捷與轉乘通廊）

| 部件 | OSM 足跡最小旋轉矩形 | 高度、屋頂與外觀判斷 |
| --- | --- | --- |
| 高鐵台中站體 | [way 544377825](https://www.openstreetmap.org/way/544377825)，**360.331 × 96.123 m**，25 個不重複頂點；`layer=2` | OSM 沒有高度或屋頂標籤。約 **30 m** 長棚峰、屋面肋線、支撐桁架、低層玻璃立面依參考展示比例與照片推估。 |
| 臺鐵新烏日站 | [way 337921979](https://www.openstreetmap.org/way/337921979)，**210.337 × 84.349 m**，32 個頂點；`layer=2` | OSM 沒有高度或屋頂標籤。約 **18 m** 平棚、正面高玻璃入口與柱列依照片和參考展示比例推估。 |
| 中捷高鐵臺中站 | [way 862779522](https://www.openstreetmap.org/way/862779522)，**180.108 × 21.553 m**，9 個頂點；`layer=2` | OSM 沒有高度或屋頂標籤。約 **8 m** 基底、**23 m** 弧棚峰、白色金屬波浪棚與玻璃立面依照片推估。 |
| 東西轉乘通廊 | [way 862779520](https://www.openstreetmap.org/way/862779520)，**47.628 × 11.664 m**，8 個頂點 | OSM 無高度、層數或屋頂標籤。約 **4–12 m** 架空玻璃通廊依參考展示和照片推估。 |
| 南北轉乘通廊 | [way 862779521](https://www.openstreetmap.org/way/862779521)，**32.640 × 10.002 m**，4 個頂點；`layer=1` | 同樣沒有高度、層數或屋頂標籤；約 **4–12 m** 為推估。 |

五個 way 的全部非閉合邊界頂點從 2026-11-06 下載的 osmtoday `asia/taiwan.pbf` 以 pyosmium 擷取，轉為局部公尺座標；原點為 120.61474665°E、24.1112536°N。尺寸、方向與五件相對位置與參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/xinwuri-complex-v1/metadata.json` 核對；`blender-buildings-v1/xinwuri-complex-v1/model.json` 只量三座站體和兩條通廊的相對比例，不用原網格。所有高度均屬展示／外觀推估。OSM 輪廓 © OpenStreetMap contributors，ODbL 1.0。

外觀只看 Wikimedia Commons [高鐵台中站長棚與入口鋼架](https://commons.wikimedia.org/wiki/File:THSR_Taichung_Station_01.jpg)、[高鐵與新烏日全景](https://commons.wikimedia.org/wiki/File:THSR_Taichung_Station_and_TRA_New_Wurih_Station_20111008a.JPG)、[新烏日正面玻璃入口](https://commons.wikimedia.org/wiki/File:新烏日車站.JPG)、[中捷白色曲棚與玻璃立面](https://commons.wikimedia.org/wiki/File:HSR_Taichung_Station_(Taichung_MRT).jpg)、[中捷與高鐵之間的空橋](https://commons.wikimedia.org/wiki/File:View_at_skyway_between_exit_2_and_the_main_building_of_TMRT_HSR_Taichung_Station.jpg)；[臺中觀旅高鐵頁](https://travel.taichung.gov.tw/zh-tw/Traffic/THSR) 只核對站區關係，沒有當測量尺度。照片不打包、不作貼圖。以現有 station kit 盒體、曲棚、梁柱和淡色玻璃組成近／遠景，保留淺屋頂、青灰窗與暗桁架的明暗次序。高鐵棚曲度、中捷波浪節奏、新烏日入口比例和通廊高程仍待作者核對。近景 **4,291 三角**、遠景 **2,011 三角**。

## 尚缺的兩站

| 站 | 來源與目前量到的部件足跡（m） | 還缺的核對 |
| --- | --- | --- |
| 高鐵台南 | 參考庫 `stations/tainan-hsr-v1/metadata.json` 的 OSM 輪廓：高鐵臺南 114 × 57（r9351022:1）；高鐵月台棚 336 × 14（r9351022:0）；高鐵月台棚 332 × 11（266850895）；沙崙 149 × 27（316034163） | 挑簷、月台棚與真實高度。 |
| 高鐵左營 | 參考庫 `stations/zuoying-complex-v1/metadata.json` 的 OSM 輪廓：高鐵左營 186 × 78（111991261）；臺鐵新左營 168 × 67（303296097） | 大頂與真實高度。 |

上表尺寸是參考庫依 OSM 輪廓量出的最小矩形，括號內為 OSM way／relation 識別；這些站的 `displayHeightM` 都是展示推估，**尚未**作為真實高度。每站完成前須從整份 Taiwan PBF 重新核對 way、`building:part`、高度與屋頂標籤，再看照片選各部件，並另做近遠兩版。資料出處同為 © OpenStreetMap contributors，ODbL 1.0。

## 檢查與邊界

測試驗證新研究模型的三角預算、每個 OSM 地面頂點、近遠兩版，以及研究 ID 不進現有 station kit 查表。現有站型原始檔、營運映射與雜湊均未改；GameCore、golden、save 與 fixtures 未改。Metal/iPhone/iPad、正式地圖放置與作者外觀接受仍未驗證。
