# 車站外觀第二批 studies（決策 626）

九處站點的獨立研究配方。模型沒有接入 `Map3DStationKit` 選型、地圖或存檔。所有照片僅供外形比對，不作貼圖。站房高度、屋頂坡度、出簷、窗列、柱距及入口細節，除非表中另有 OSM 標籤，**全部是推估，並非實測**。

## 資料與比例

足跡來自 osmtoday `asia/taiwan.pbf`（2026-11-07），由 pyosmium 讀取並將每個 way 的全部非閉合頂點以 `x=(lon-lon₀)·111320·cos(lat₀)`、`y=(lat-lat₀)·111320` 轉成局部公尺。輪廓 © OpenStreetMap contributors，ODbL 1.0。參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/stations/` 目前沒有這九站同站的 metadata；`blender-buildings-v1` 只作比例參考，沒有搬用網格。

| 站點／局部原點（經度、緯度） | OSM 輪廓與標籤 | 照片外形參考 |
| --- | --- | --- |
| 臺鐵基隆 `121.73923, 25.13303` | [way 929730121](https://www.openstreetmap.org/way/929730121)：89 頂點；height／levels／roof 無標籤<br>[way 1069178919](https://www.openstreetmap.org/way/1069178919)：21 頂點；layer=-1<br>[way 367861777](https://www.openstreetmap.org/way/367861777)：4 頂點；building:levels=3 | [File:North_Entrance,_TRA_Keelung_Station_20150705.jpg](https://commons.wikimedia.org/wiki/File:North_Entrance%2C_TRA_Keelung_Station_20150705.jpg)<br>[File:TRA_Keelung_Station_North_Exit_20170309.jpg](https://commons.wikimedia.org/wiki/File:TRA_Keelung_Station_North_Exit_20170309.jpg) |
| 臺鐵嘉義 `120.44158, 23.4799` | [way 286891391](https://www.openstreetmap.org/way/286891391)：13 頂點；height／levels／roof 無標籤 | [File:嘉義火車站(嘉義車站).jpg](https://commons.wikimedia.org/wiki/File:%E5%98%89%E7%BE%A9%E7%81%AB%E8%BB%8A%E7%AB%99%28%E5%98%89%E7%BE%A9%E8%BB%8A%E7%AB%99%29.jpg) |
| 臺鐵臺南 `120.21332, 22.99714` | [way 204493488](https://www.openstreetmap.org/way/204493488)：15 頂點；height／levels／roof 無標籤<br>[way 204493489](https://www.openstreetmap.org/way/204493489)：12 頂點；height／levels／roof 無標籤<br>[way 1568887226](https://www.openstreetmap.org/way/1568887226)：4 頂點；building:levels=2<br>[way 1568933253](https://www.openstreetmap.org/way/1568933253)：4 頂點；start_date=2026-10-17 | [File:臺南車站前.jpg](https://commons.wikimedia.org/wiki/File:%E8%87%BA%E5%8D%97%E8%BB%8A%E7%AB%99%E5%89%8D.jpg)<br>[File:Tainan_Station_(2026)_-_exterior_-_img_01.jpg](https://commons.wikimedia.org/wiki/File:Tainan_Station_%282026%29_-_exterior_-_img_01.jpg) |
| 阿里山林鐵北門 `120.45438, 23.48763` | [way 353120128](https://www.openstreetmap.org/way/353120128)：4 頂點；height／levels／roof 無標籤 | [File:北門車站.jpg](https://commons.wikimedia.org/wiki/File:%E5%8C%97%E9%96%80%E8%BB%8A%E7%AB%99.jpg) |
| 阿里山林鐵奮起湖 `120.69492, 23.50534` | [way 444296747](https://www.openstreetmap.org/way/444296747)：4 頂點；height／levels／roof 無標籤 | 本輪無可確認的照片連結；外觀待照片核對。 |
| 阿里山林鐵阿里山 `120.80434, 23.51` | [way 344586161](https://www.openstreetmap.org/way/344586161)：8 頂點；height／levels／roof 無標籤 | [File:Alishan_station_阿里山車站_-_panoramio.jpg](https://commons.wikimedia.org/wiki/File:Alishan_station_%E9%98%BF%E9%87%8C%E5%B1%B1%E8%BB%8A%E7%AB%99_-_panoramio.jpg) |
| 糖鐵烏樹林 `120.37378, 23.32866` | 僅有 OSM 站點，無可確認的站房建物輪廓；此站外形、尺寸全為推估。 | 本輪無可確認的照片連結；外觀待照片核對。 |
| 糖鐵溪湖 `120.481765, 23.95205` | 僅有 OSM 站點，無可確認的站房建物輪廓；此站外形、尺寸全為推估。 | 本輪無可確認的照片連結；外觀待照片核對。 |
| 糖鐵橋頭 `120.31468, 22.75303` | [way 112644875](https://www.openstreetmap.org/way/112644875)：4 頂點；layer=1 | 本輪無可確認的照片連結；外觀待照片核對。 |

## 臺南地下化狀態

本次 PBF 把新臺南站的大範圍站體 [way 1568933253](https://www.openstreetmap.org/way/1568933253)、地下軌道 ways 1102288952／1102288953、地下月台 ways 1568933254／1568933255 都標為 `start_date=2026-10-17`，軌道標 `layer=-1`；因此可確認 **OSM 已把地下行車與新月台標為啟用部分**。這不能證明地面工程、全部出入口或老站修復已完工；上述部分本輪不宣稱完工。舊站地面建物 ways 204493488／204493489 與新地下站輪廓分列。新站研究棚件在地面軌道上方以 8 m 起建，只代表淨空示意，不是已測量的新站屋頂。

## 建模與限制

使用 StationKitBuilder 的盒體、四坡頂、曲棚、柱列和發光窗列。林鐵北門、奮起湖與糖鐵的研究版採木牆、深色瓦頂、出簷；阿里山站則按照片分成混凝土下層與雙坡木構上層。沒有把非中式站房畫成中式屋頂。所有輪廓只用薄邊標出，不加入實心地面底板。跨軌的臺南新站示意與橋頭糖廠 `layer=1` 部分從 8 m 起建；8 m 淨空是保守展示推估，正式工程淨空須另測。近景上限 6,000 三角，遠景上限 2,500 三角，實際數量見下表與私庫 `manifest.json`。

| 站點 | 近景三角 | 遠景三角 |
| --- | ---: | ---: |
| 臺鐵基隆 | 1202 | 590 |
| 臺鐵嘉義 | 318 | 74 |
| 臺鐵臺南 | 968 | 320 |
| 林鐵北門 | 258 | 62 |
| 林鐵奮起湖 | 254 | 58 |
| 林鐵阿里山 | 392 | 196 |
| 糖鐵烏樹林 | 250 | 54 |
| 糖鐵溪湖 | 250 | 54 |
| 糖鐵橋頭 | 258 | 62 |

烏樹林和溪湖在 OSM 只有站點，沒有可認定的站房輪廓，因此不借用附近咖啡館或工廠當站房。糖鐵外形尚缺可確認的照片，這三站是較低信心的研究模型，待外觀審看。

## 交付與檢查

公開庫保留 Swift 配方、測試、本 README 和 `overview.png`（九站各近景日／夜、遠景日）。逐方向原生模型、GLB、日夜七向透明 PNG 和可離線 viewer 在私有素材庫 `game-art-previews/docs/art/station-exteriors-batch2/`，只保留最新一輪。測試鎖住站數、三角上限、夜間發光、OSM 非閉合輪廓頂點、無地面底板，以及跨軌示意件 8 m 起建；不代表 iOS Metal 實機驗證。
