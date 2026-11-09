# 車站外觀第二批 studies（決策 626）

九處站點的研究配方。決策 665 把它們照決策 625 的做法接進 3D 地圖（OSM 位置、切開讓出軌道、代替套件的站房）；存檔不動。所有照片僅供外形比對，不作貼圖。站房高度、屋頂坡度、出簷、窗列、柱距及入口細節，除非表中另有 OSM 標籤，**全部是推估，並非實測**。

接進地圖後的近景截圖（九站白天，阿里山、溪湖晚上）：`map-overview.png`；原圖在 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/station-exteriors-batch2-map-2026-11-09/`。

## 資料與比例

足跡來自 osmtoday `asia/taiwan.pbf`（2026-11-07），由 pyosmium 讀取並將每個 way 的全部非閉合頂點以 `x=(lon-lon₀)·111320·cos(lat₀)`、`y=(lat-lat₀)·111320` 轉成局部公尺。表中未另列的 height、building:levels 與 roof 標籤代表 OSM 沒有標記，不能當作實測高度。輪廓 © OpenStreetMap contributors，ODbL 1.0。參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/` 目前沒有這九站同站的 metadata；`blender-buildings-v1` 只作比例參考，沒有搬用網格。

| 站點／局部原點（經度、緯度） | OSM 輪廓與標籤 | 照片外形參考 |
| --- | --- | --- |
| 臺鐵基隆 `121.73923, 25.13303` | [way 929730121](https://www.openstreetmap.org/way/929730121)：89 頂點；height／levels／roof 無標籤<br>[way 1069178919](https://www.openstreetmap.org/way/1069178919)：21 頂點；layer=-1<br>[way 367861777](https://www.openstreetmap.org/way/367861777)：4 頂點；building:levels=3 | [File:North_Entrance,_TRA_Keelung_Station_20150705.jpg](https://commons.wikimedia.org/wiki/File:North_Entrance%2C_TRA_Keelung_Station_20150705.jpg)<br>[File:TRA_Keelung_Station_North_Exit_20170309.jpg](https://commons.wikimedia.org/wiki/File:TRA_Keelung_Station_North_Exit_20170309.jpg)<br>[File:KKMT_Keelung_Terminal_former_site_and_TRA_Keelung_Station_South_20181028.jpg](https://commons.wikimedia.org/wiki/File:KKMT_Keelung_Terminal_former_site_and_TRA_Keelung_Station_South_20181028.jpg) |
| 臺鐵嘉義 `120.44158, 23.4799` | [way 286891391](https://www.openstreetmap.org/way/286891391)：13 頂點；height／levels／roof 無標籤 | [File:嘉義火車站(嘉義車站).jpg](https://commons.wikimedia.org/wiki/File:%E5%98%89%E7%BE%A9%E7%81%AB%E8%BB%8A%E7%AB%99%28%E5%98%89%E7%BE%A9%E8%BB%8A%E7%AB%99%29.jpg) |
| 臺鐵臺南 `120.21332, 22.99714` | [way 204493488](https://www.openstreetmap.org/way/204493488)：15 頂點；height／levels／roof 無標籤<br>[way 204493489](https://www.openstreetmap.org/way/204493489)：12 頂點；height／levels／roof 無標籤<br>[way 1568887226](https://www.openstreetmap.org/way/1568887226)：4 頂點；building:levels=2<br>[way 1568933253](https://www.openstreetmap.org/way/1568933253)：4 頂點；start_date=2026-10-17 | [File:Front Station, TRA Tainan Station 20060110.jpg](https://commons.wikimedia.org/wiki/File:Front_Station,_TRA_Tainan_Station_20060110.jpg)（2006 年正面）<br>[File:臺南車站前.jpg](https://commons.wikimedia.org/wiki/File:%E8%87%BA%E5%8D%97%E8%BB%8A%E7%AB%99%E5%89%8D.jpg)<br>[File:Tainan_Station_(2026)_-_exterior_-_img_01.jpg](https://commons.wikimedia.org/wiki/File:Tainan_Station_%282026%29_-_exterior_-_img_01.jpg) |
| 阿里山林鐵北門 `120.45438, 23.48763` | [way 353120128](https://www.openstreetmap.org/way/353120128)：4 頂點；height／levels／roof 無標籤 | [File:北門車站.jpg](https://commons.wikimedia.org/wiki/File:%E5%8C%97%E9%96%80%E8%BB%8A%E7%AB%99.jpg) |
| 阿里山林鐵奮起湖 `120.69492, 23.50534` | [way 444296747](https://www.openstreetmap.org/way/444296747)：4 頂點；height／levels／roof 無標籤 | [File:Funkiko Station of Arisan Railway.jpg](https://commons.wikimedia.org/wiki/File:Funkiko_Station_of_Arisan_Railway.jpg)（歷史木造站房）<br>[File:Fenqihu Station 2023.jpg](https://commons.wikimedia.org/wiki/File:Fenqihu_Station_2023.jpg)（現況站房與月台） |
| 阿里山林鐵阿里山 `120.80434, 23.51` | [way 344586161](https://www.openstreetmap.org/way/344586161)：8 頂點；height／levels／roof 無標籤 | [File:Alishan_station_阿里山車站_-_panoramio.jpg](https://commons.wikimedia.org/wiki/File:Alishan_station_%E9%98%BF%E9%87%8C%E5%B1%B1%E8%BB%8A%E7%AB%99_-_panoramio.jpg) |
| 糖鐵烏樹林 `120.37378, 23.32866` | 僅有 OSM 站點，無可確認的站房建物輪廓；此站外形、尺寸全為推估。 | [File:Wushulin Station building,Tainan Houbi,Taiwan.JPG](https://commons.wikimedia.org/wiki/File:Wushulin_Station_building,Tainan_Houbi,Taiwan.JPG) |
| 糖鐵溪湖 `120.481765, 23.95205` | 僅有 OSM 站點，無可確認的站房建物輪廓；此站外形、尺寸全為推估。 | [File:溪湖車站 2020.jpg](https://commons.wikimedia.org/wiki/File:%E6%BA%AA%E6%B9%96%E8%BB%8A%E7%AB%99_2020.jpg)（Pbdragonwang，2020-08-16，CC BY-SA 4.0，可確認的溪湖糖廠五分車站）<br>[File:Sihu Station 01.jpg](https://commons.wikimedia.org/wiki/File:Sihu_Station_01.jpg)（2008 年站房） |
| 糖鐵橋頭 `120.31468, 22.75303` | [way 112644875](https://www.openstreetmap.org/way/112644875)：4 頂點；layer=1，height／levels／roof 無標籤，名稱「橋頭糖廠」，實為捷運高架站體；它只作比例輪廓，**不能當成糖鐵站房的實測資料**。 | [File:Ciaotou Sugar Refinery Station 20240617.jpg](https://commons.wikimedia.org/wiki/File:Ciaotou_Sugar_Refinery_Station_20240617.jpg)（捷運站）<br>[File:五分車站 (5142751780).jpg](https://commons.wikimedia.org/wiki/File:%E4%BA%94%E5%88%86%E8%BB%8A%E7%AB%99_%285142751780%29.jpg)（糖鐵售票亭與雨棚） |

## 臺南地下化狀態

本次 PBF 把新臺南站的大範圍站體 [way 1568933253](https://www.openstreetmap.org/way/1568933253)、地下軌道 ways 1102288952／1102288953、地下月台 ways 1568933254／1568933255 都標為 `start_date=2026-10-17`，軌道標 `layer=-1`；因此可確認 **OSM 已把地下行車與新月台標為啟用部分**。這不能證明地面工程、全部出入口或老站修復已完工；上述部分本輪不宣稱完工。舊站地面建物 ways 204493488／204493489 與新地下站輪廓分列。新站的大範圍輪廓以 8 m 高的薄邊示意淨空，地面出入口則從地面起建；8 m 不是已測量的新站屋頂高度。

## 建模與限制

依 [STATION-B2-REVIEW](https://github.com/a91453/railway-game-ios/pull/1938#issuecomment-6710977468) 的逐站照片對照，再修正外形：

| 站 | 本輪照片判讀與模型修正 |
| --- | --- |
| 基隆 | 北站為灰色石材量體，正面長招牌及橘色楣板，入口前是鋼格弧形玻璃頂；第四輪將頂寬縮至 52 m，落在 62 m 站房正面範圍內，肋與柱同步收齊。南站弧頂內的鋼件壓到屋面以下，窗後有與背景 `#E2E8EE` 可區分的淺灰石材色；第四輪移除牆外細柱，將主盒體拆成與窗列齊寬的短段，避免淨空裁掉整片牆後只剩孤立端面，並在中央被裁掉的牆段後方加深色退縮門洞與門楣。舊站輪廓上的孤立深色三角已移除。南北站照片年代分別為 2015、2018 年。 |
| 嘉義 | 1933 站房是米白平屋頂、中央較高塊體，五扇高圓拱窗、赭黃拱圈及牆角、鐘面、屋頂立牌；入口平頂雨庇置於一樓頂高度，厚約 0.48 m、前伸約 4 m，第四輪將兩根赭黃直條底端精確止於雨庇頂面。不沿用第一稿的紅瓦四坡頂。 |
| 臺南 | 2006 年正面照片顯示米白色兩層、中央挑高、兩翼對稱、上層拱窗、下層三拱入口與圓窗；平屋頂藏於女兒牆後，入口有厚車寄，頂部有立牌旗桿。第三輪加亮牆面原始色以抵消預覽光照的灰化，一樓仍保留淺粉褐牆裙。新地下化車站地面入口獨立呈現；OSM 的啟用與未證實完工範圍見上節。 |
| 北門 | 2021 照片的現況檜木板牆**刷深綠漆**，非裸檜木咖啡色；四面白框窗、灰黑陡坡瓦頂與深色屋脊。 |
| 奮起湖 | 以 2023 現況照的灰色木板牆、灰綠瓦頂與月台雨棚為準；歷史照片只說明舊站年代，沒有混入此模型。第四輪發現原來的 1.16 比值只量到少數未被淨空裁掉的牆體頂點，左半屋頂下方沒有牆。故將站房移至 OSM 輪廓中不佔用軌道包絡的區域，主屋頂縮為約 10 × 20 m，牆體約 8 × 18 m、高約 4 m；四邊出簷約 1 m，實際投影面積比約 1.39。左前孤柱已移除，獨立月台雨棚接在主屋簷下。OSM way 444296747 的 18.6 × 16.2 m 斜向輪廓仍完整保留作來源線；它鄰接月台，不能直接當作可落地的站房牆體外緣。尺寸皆為推估，非實測。 |
| 阿里山 | 照片下層是封閉的淺灰混凝土量體與三個入口，前方寬石階通往上層；上層兩座山牆加紅褐木桁架和欄杆。第三輪把下層混凝土量體延伸到上層平台四角下方，取消左側懸空。石階為獨立可選情境零件。 |
| 烏樹林 | 深褐木板牆、白與淺藍窗框、灰黑陡坡瓦頂、同色山牆及站名匾。月台與淺藍欄杆置於獨立情境零件。 |
| 溪湖 | 新找到的 2020 [溪湖車站照片](https://commons.wikimedia.org/wiki/File:%E6%BA%AA%E6%B9%96%E8%BB%8A%E7%AB%99_2020.jpg) 可確認是五分車站；可見深褐木構、淺色填牆、長而低的木柱雨棚。審查圖原照片中的右側混凝土建物身分不明，故不以它作站房外形依據。 |
| 橋頭 | 捷運橋頭糖廠站是灰色混凝土高架站體與弧頂；紅磚僅屬糖鐵售票亭。第三輪將售票亭正面的「五分車售票亭」示意招牌前移，補紅底白框長條；字樣仍以幾何色塊示意。旁側淺灰綠單斜雨棚低於亭頂、與亭體分離。月台與欄杆置於獨立情境零件。 |

照片只用於觀察輪廓、顏色和比例，不作貼圖。站名以幾何色塊示意，不是真實文字。模型均使用 StationKitBuilder 的盒體、坡頂、曲棚、柱列及發光窗列；牆高、屋頂坡度、出簷、窗框和裝飾尺寸仍屬照片推估，非實測。小木站屋頂平面約為牆面的 1.2–1.4 倍。OSM 輪廓以非實心薄邊保留在原生模型及 GLB，近鏡預覽隱藏薄邊。站房本體沒有實心地面底板；阿里山石階、烏樹林及橋頭的月台欄杆是可選、獨立模型，不參與遊戲選型。

地面軌道與月台邊緣的 2.2 m 水平、5.5 m 高度包絡內三角形會裁掉；臺南地下月台與軌道依地下化標示處理，地面入口不受地下月台的地面包絡約束。橋頭高架站體從 8 m 起建。8 m 是保守研究推估，正式工程淨空須另測。近景目標 1,500–5,000 三角、上限 6,000；遠景上限 2,500。實際數量見下表及私庫 `manifest.json`。

| 站點 | 近景三角 | 遠景三角 |
| --- | ---: | ---: |
| 臺鐵基隆 | 3537 | 1783 |
| 臺鐵嘉義 | 2334 | 1119 |
| 臺鐵臺南 | 4600 | 2278 |
| 林鐵北門 | 1982 | 686 |
| 林鐵奮起湖 | 1548 | 492 |
| 林鐵阿里山 | 3015 | 1047 |
| 糖鐵烏樹林 | 1558 | 598 |
| 糖鐵溪湖 | 2374 | 562 |
| 糖鐵橋頭 | 2492 | 1280 |

烏樹林和溪湖在 OSM 只有站點，沒有可認定的站房輪廓，因此不借用附近咖啡館或工廠當站房。溪湖已有可確認的 2020 年站房照片，但站房與雨棚的三維尺寸仍是推估。

## 交付與檢查

公開庫保留 Swift 配方、測試、本 README、九站各有日間近景、夜間近景與日間遠景的 `overview.png`、舊版 `overview-before.png`、`before/` 原始近景、十張同審查鏡頭的改前／改後對照圖（本輪四張以第三輪為改前，其餘沿用原審查改前；基隆南北站各一）及 `front/` 正面平視圖。基隆、臺南、橋頭的對照圖另用站房局部近鏡頭，主體占畫面過半；橋頭局部圖隱藏被近鏡裁成碎片的捷運墩柱，完整高架站與售票亭均保留在原生模型與遠景。私有庫 `review/pairs/` 另有十張真實照片／修改後模型同角度並排圖，其照片來源、作者與授權列於 `REVIEW-README.md`。逐方向原生模型、GLB、日夜七向透明 PNG 和可離線 viewer 在私有素材庫 `game-art-previews/docs/art/station-exteriors-batch2/`，只保留最新一輪。測試鎖住站數、近遠景預算、夜間發光、OSM 非閉合頂點資料、無地面底板，以及地面軌道與月台包絡的逐三角淨空；不代表 iOS Metal 實機驗證。
