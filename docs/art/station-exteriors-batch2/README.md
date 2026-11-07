# 車站外觀第二批 studies（決策 626）

九處站點的獨立研究配方。模型沒有接入 `Map3DStationKit` 選型、地圖或存檔。所有照片僅供外形比對，不作貼圖。站房高度、屋頂坡度、出簷、窗列、柱距及入口細節，除非表中另有 OSM 標籤，**全部是推估，並非實測**。

## 資料與比例

足跡來自 osmtoday `asia/taiwan.pbf`（2026-11-07），由 pyosmium 讀取並將每個 way 的全部非閉合頂點以 `x=(lon-lon₀)·111320·cos(lat₀)`、`y=(lat-lat₀)·111320` 轉成局部公尺。表中未另列的 height、building:levels 與 roof 標籤代表 OSM 沒有標記，不能當作實測高度。輪廓 © OpenStreetMap contributors，ODbL 1.0。參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/` 目前沒有這九站同站的 metadata；`blender-buildings-v1` 只作比例參考，沒有搬用網格。

| 站點／局部原點（經度、緯度） | OSM 輪廓與標籤 | 照片外形參考 |
| --- | --- | --- |
| 臺鐵基隆 `121.73923, 25.13303` | [way 929730121](https://www.openstreetmap.org/way/929730121)：89 頂點；height／levels／roof 無標籤<br>[way 1069178919](https://www.openstreetmap.org/way/1069178919)：21 頂點；layer=-1<br>[way 367861777](https://www.openstreetmap.org/way/367861777)：4 頂點；building:levels=3 | [File:North_Entrance,_TRA_Keelung_Station_20150705.jpg](https://commons.wikimedia.org/wiki/File:North_Entrance%2C_TRA_Keelung_Station_20150705.jpg)<br>[File:TRA_Keelung_Station_North_Exit_20170309.jpg](https://commons.wikimedia.org/wiki/File:TRA_Keelung_Station_North_Exit_20170309.jpg)<br>[File:KKMT_Keelung_Terminal_former_site_and_TRA_Keelung_Station_South_20181028.jpg](https://commons.wikimedia.org/wiki/File:KKMT_Keelung_Terminal_former_site_and_TRA_Keelung_Station_South_20181028.jpg) |
| 臺鐵嘉義 `120.44158, 23.4799` | [way 286891391](https://www.openstreetmap.org/way/286891391)：13 頂點；height／levels／roof 無標籤 | [File:嘉義火車站(嘉義車站).jpg](https://commons.wikimedia.org/wiki/File:%E5%98%89%E7%BE%A9%E7%81%AB%E8%BB%8A%E7%AB%99%28%E5%98%89%E7%BE%A9%E8%BB%8A%E7%AB%99%29.jpg) |
| 臺鐵臺南 `120.21332, 22.99714` | [way 204493488](https://www.openstreetmap.org/way/204493488)：15 頂點；height／levels／roof 無標籤<br>[way 204493489](https://www.openstreetmap.org/way/204493489)：12 頂點；height／levels／roof 無標籤<br>[way 1568887226](https://www.openstreetmap.org/way/1568887226)：4 頂點；building:levels=2<br>[way 1568933253](https://www.openstreetmap.org/way/1568933253)：4 頂點；start_date=2026-10-17 | [File:臺南車站前.jpg](https://commons.wikimedia.org/wiki/File:%E8%87%BA%E5%8D%97%E8%BB%8A%E7%AB%99%E5%89%8D.jpg)<br>[File:Tainan_Station_(2026)_-_exterior_-_img_01.jpg](https://commons.wikimedia.org/wiki/File:Tainan_Station_%282026%29_-_exterior_-_img_01.jpg) |
| 阿里山林鐵北門 `120.45438, 23.48763` | [way 353120128](https://www.openstreetmap.org/way/353120128)：4 頂點；height／levels／roof 無標籤 | [File:北門車站.jpg](https://commons.wikimedia.org/wiki/File:%E5%8C%97%E9%96%80%E8%BB%8A%E7%AB%99.jpg) |
| 阿里山林鐵奮起湖 `120.69492, 23.50534` | [way 444296747](https://www.openstreetmap.org/way/444296747)：4 頂點；height／levels／roof 無標籤 | [File:Funkiko Station of Arisan Railway.jpg](https://commons.wikimedia.org/wiki/File:Funkiko_Station_of_Arisan_Railway.jpg)（歷史木造站房）<br>[File:Fenqihu Station 2023.jpg](https://commons.wikimedia.org/wiki/File:Fenqihu_Station_2023.jpg)（現況站房與月台） |
| 阿里山林鐵阿里山 `120.80434, 23.51` | [way 344586161](https://www.openstreetmap.org/way/344586161)：8 頂點；height／levels／roof 無標籤 | [File:Alishan_station_阿里山車站_-_panoramio.jpg](https://commons.wikimedia.org/wiki/File:Alishan_station_%E9%98%BF%E9%87%8C%E5%B1%B1%E8%BB%8A%E7%AB%99_-_panoramio.jpg) |
| 糖鐵烏樹林 `120.37378, 23.32866` | 僅有 OSM 站點，無可確認的站房建物輪廓；此站外形、尺寸全為推估。 | [File:Wushulin Station building,Tainan Houbi,Taiwan.JPG](https://commons.wikimedia.org/wiki/File:Wushulin_Station_building,Tainan_Houbi,Taiwan.JPG) |
| 糖鐵溪湖 `120.481765, 23.95205` | 僅有 OSM 站點，無可確認的站房建物輪廓；此站外形、尺寸全為推估。 | 本輪無可確認的照片連結；外觀待照片核對。 |
| 糖鐵橋頭 `120.31468, 22.75303` | [way 112644875](https://www.openstreetmap.org/way/112644875)：4 頂點；layer=1，height／levels／roof 無標籤，名稱「橋頭糖廠」，實為捷運高架站體；它只作比例輪廓，**不能當成糖鐵站房的實測資料**。 | [File:Ciaotou Sugar Refinery Station 20240617.jpg](https://commons.wikimedia.org/wiki/File:Ciaotou_Sugar_Refinery_Station_20240617.jpg)（捷運站）<br>[File:五分車站 (5142751780).jpg](https://commons.wikimedia.org/wiki/File:%E4%BA%94%E5%88%86%E8%BB%8A%E7%AB%99_%285142751780%29.jpg)（糖鐵售票亭與雨棚） |

## 臺南地下化狀態

本次 PBF 把新臺南站的大範圍站體 [way 1568933253](https://www.openstreetmap.org/way/1568933253)、地下軌道 ways 1102288952／1102288953、地下月台 ways 1568933254／1568933255 都標為 `start_date=2026-10-17`，軌道標 `layer=-1`；因此可確認 **OSM 已把地下行車與新月台標為啟用部分**。這不能證明地面工程、全部出入口或老站修復已完工；上述部分本輪不宣稱完工。舊站地面建物 ways 204493488／204493489 與新地下站輪廓分列。新站的大範圍輪廓以 8 m 高的薄邊示意淨空，地面出入口則從地面起建；8 m 不是已測量的新站屋頂高度。

## 建模與限制

九站改成各自的建築組合：基隆南北站兩個曲棚並保留舊站輪廓；嘉義以米白立面、正面拱廊、中央方塔與紅瓦四坡頂表現 1933 年站房；臺南以中央廳連起 1936 年白色兩層站房的兩翼，並把它與新地下站地面入口分開；北門做檜木山牆；奮起湖做木造站房和獨立月台雨棚；阿里山是混凝土下層與兩個互不重疊的木構山牆；烏樹林、溪湖採不同長寬與雨棚排列；橋頭把 OSM 高架站輪廓回復到約 86 × 144 m，另依五分車照片放大紅磚售票亭與獨立雨棚。糖鐵售票亭與高架捷運站不是同一棟建築；售票亭的平面位置及尺寸是照片推估，後續仍需找到糖鐵站房的獨立 OSM 輪廓。只有真實站體是中式屋頂才會畫中式屋頂，本批沒有任意加上中式屋脊。

所有模型都使用 StationKitBuilder 的盒體、坡頂、曲棚、柱列及發光窗列。牆面、屋頂、窗框按可見照片分色；檜木站與糖鐵小站有木牆、深色瓦頂與出簷。斜屋頂的瓦條沿坡面走，不穿出屋面。所有 OSM 輪廓以非實心薄邊保留在原生模型及 GLB，預覽圖為了站房完整取景隱藏薄邊。沒有地面底板。

地面軌道與月台邊緣的 2.2 m 水平、5.5 m 高度包絡內三角形會裁掉；臺南地下月台與軌道依地下化標示處理，地面入口不受地下月台的地面包絡約束。橋頭高架站體從 8 m 起建。8 m 是保守研究推估，正式工程淨空須另測。近景目標 1,500–5,000 三角、上限 6,000；遠景上限 2,500。實際數量見下表及私庫 `manifest.json`。

| 站點 | 近景三角 | 遠景三角 |
| --- | ---: | ---: |
| 臺鐵基隆 | 4537 | 1303 |
| 臺鐵嘉義 | 2057 | 593 |
| 臺鐵臺南 | 4166 | 1958 |
| 林鐵北門 | 1898 | 230 |
| 林鐵奮起湖 | 1744 | 366 |
| 林鐵阿里山 | 2732 | 627 |
| 糖鐵烏樹林 | 2206 | 466 |
| 糖鐵溪湖 | 2050 | 394 |
| 糖鐵橋頭 | 2980 | 1048 |

烏樹林和溪湖在 OSM 只有站點，沒有可認定的站房輪廓，因此不借用附近咖啡館或工廠當站房。溪湖照片資料目前不足，站房和雨棚尺寸、顏色仍是待核對的推估。

## 交付與檢查

公開庫保留 Swift 配方、測試、本 README、九站各一張完整近景的 `overview.png`、舊版 `overview-before.png`、`before/` 原始近景與九張改前／改後對照圖。逐方向原生模型、GLB、日夜七向透明 PNG 和可離線 viewer 在私有素材庫 `game-art-previews/docs/art/station-exteriors-batch2/`，只保留最新一輪。測試鎖住站數、近遠景預算、夜間發光、OSM 非閉合頂點資料、無地面底板，以及地面軌道與月台包絡的逐三角淨空；不代表 iOS Metal 實機驗證。
