# 作者 11-13 問的資料來源：哪些能用、先做哪個

日期：2026-11-13。基準是遊戲 `main` 2187840；香港地圖包的現況看分支 `claude/air-unlock-3`（#2115，還沒合）。
讀者：遊戲規劃、作者，以及接下去做前三名的 session。
派工單：DATA-PRIORITY（遊戲規劃第 64 任；作者 11-13：「開一個session排優先順序」）。只研究、只寫文件。

> **怎麼做出來的**
> - 在 Linux 雲端容器實際下載每一份樣本，用暫時的 Python 腳本量。腳本與下載的檔都沒有提交（大檔在 scratchpad），重抓的方法在第 8 節。
> - **VERIFIED**：文中帶數字的（筆數、大小、欄位、覆蓋率、HTTP 結果）都是 2026-11-13 這樣跑出來的。
> - **UNVERIFIED**：工作量與「地圖包會變多大」是估的；沒有任何一項接進遊戲試過；沒有看過畫面。
> - 3D Visualisation Map 由 Mac 上的 HK-3DVIS 在試，這裡不重做，寫「等 HK-3DVIS」。
> - 沒有讀、沒有複製 Peakline 自己的程式與衍生資料庫。星空那幾項與規劃沒點名的香港資料只查了入口與筆數，沒有下載全檔。

## 0. 結論先講

1. **香港政府那 24 項，條款上全部可以用**（商業也可以，免費），條件是標示來源，並接受一條賠償條款。DATA.GOV.HK 與 CSDI 是兩份條款，內容幾乎一樣（第 2 節）。賠償條款作者在 HK_MAP 研究時已經知道，港鐵資料就是在同一條下用的。
2. **最值得拿的是地形和建物，兩樣都下載到了、量過了**：
   - 地政總署 Digital Terrain Model：5 m 一格，全港一個檔（zip 24 MB）。香港現在全平；用遊戲現有的 Copernicus 也做得出地形，但它在市區把大樓算進地面（平地上最高量到 109 m），地政總署這份乾淨得多（第 3.2 節）。
   - 地政總署 Building：**342,233 棟，其中 235,852 棟有實測高度（68.9%）；永久建物（大樓與平台 222,451 棟）幾乎 100% 有高度。** 香港地圖包現在的 OSM 建物是 117,245 棟，只有 58,140 棟（49.6%）有標樓層，其餘是估的（第 3.1 節）。
3. **排法和規劃的初步判斷差一點**：規劃排 Buildings → DTM → Place Name → iGeoCom；這裡把 **地形排到建物前面**。理由：OSM 建物已經在 #2115 裡，天際線有了；地形與水域還是零，而且它們是新遊戲開局時寫進世界的，香港 130 一開，之後才補的地形進不了已經開的局。
4. **台灣官方統計那一批和香港這一批合排**：觀光人次第 1 步排第 3（便宜、不動 GameCore、所有玩家都看得到，而且不用等 #2115）。
5. **不拿的**：OpenNGC（CC BY-SA，照 CLAUDE.md 當 copyleft）、正射影像（台灣的不是開放資料；香港的 DOP5000 條款可用但寫實航照不合畫風）、星空那一批（對鐵道遊戲幫助小）。

**先後**（細節在第 5 節）：
① 香港地形與水域 → ② 香港建物改用地政總署 → ③ 台灣觀光人次第 1 步 → ④ 香港地名（Place Name ＋ iGeoCom 的地區）→ ⑤ 台灣觀光人次第 2 步 → ⑥ 台灣機場按月 → ⑦ 香港的地標與客源點（iGeoCom）→ ⑧ 香港地面顏色（生境圖）→ ⑨ 香港行道樹 → ⑩ 香港路燈 → ⑪ 香港路面與行人路 → ⑫ 夜間燈光 → 其餘之後或不接。

## 1. 怎麼查的

| 步驟 | 做了什麼 |
| --- | --- |
| 讀現有研究 | `docs/research/peakline-map-engine-study/SOURCES.md`（D01–D26，當時多半沒下載）、`HK_MAP_2026-11-12.md`、`OFFICIAL_STATS_2026-11-13.md`、決策 712（`claude/air-unlock-3`）、#2118 的留言 |
| 找下載網址 | DATA.GOV.HK 的 CKAN API（`/en-data/api/3/action/package_show?id=…`）；CSDI 的全目錄 `DatasetListJSON`（1,163 項）與每項的 ISO metadata（`/csdi-webpage/metadata/<id>`，裡面有每種格式的下載網址） |
| 量筆數與欄位 | CSDI 的 ArcGIS REST 服務（`/server/rest/services/common/<id>/FeatureServer`），不用金鑰；Buildings 的 342,233 筆屬性全部抓下來算 |
| 讀條款 | 兩份條款的網頁全文（第 2 節） |
| 參考庫與外面的專案 | 見第 7 節 |

這個環境的結果：

| 主機 | 結果 |
| --- | --- |
| `data.gov.hk`、`portal.csdi.gov.hk`、`static.csdi.gov.hk`、`plis.hyd.gov.hk`、`www.map.gov.hk` | HTTP 200 |
| `open.hkmapservice.gov.hk`（iGeoCom、iB1000、iB5000 的下載） | 一開始 curl 錯誤 60：這台主機只送自己的憑證，少送中間憑證（Hongkong Post e-Cert SSL CA 3 - 17）。從憑證寫的網址另外抓中間憑證、驗到系統信任的根之後就下載得到（沒有關掉憑證檢查）。做法在第 8 節 |
| `geodata.gov.hk` | 連不上（和 HK_MAP 那次一樣）；用不到 |
| `esa-worldcover.s3.eu-central-1.amazonaws.com`、`s3.openlandmap.org`、`copernicus-dem-30m.s3.amazonaws.com`、`osmtoday.com` | HTTP 200 |
| `cdsarc.cds.unistra.fr`（亮星表） | 連線被重設（curl 35），沒抓到 |

## 2. 條款

### 2.1 DATA.GOV.HK（`data.gov.hk/en/terms-and-conditions`，Version 1.2，2025-05-26 更新）

- 可以瀏覽、下載、**散布、重製**、連結、列印，**商業與非商業都可以，免費**。
- 條件：(1) 遵守條款；(2) **清楚標示資料來源**，承認政府與提供機構對資料的智慧財產權；(3) **賠償政府與提供機構**因你使用、重製、散布資料而起的任何侵權指控、索賠與費用損失；(4) 適當標示政府、提供機構與 DATA.GOV.HK。
- 照現狀提供，不保證正確；可以不通知就改條款、停止提供。香港法律，香港法院。

### 2.2 CSDI（`portal.csdi.gov.hk/csdi-webpage/doc/TNC`）

和 DATA.GOV.HK 幾乎逐句相同。差別只有：

| | DATA.GOV.HK | CSDI |
| --- | --- | --- |
| 標示誰 | 來源、政府、提供機構、DATA.GOV.HK | **政府與 CSDI Portal** 為來源，並承認政府與提供機構的智慧財產權 |
| 賠償條款 | 有 | 有，文字相同 |
| 管轄 | 香港法院 | 香港法院**專屬**管轄 |
| 版本日期 | 寫 1.2、2025-05-26 | 頁面沒寫版本 |
| 資料的定義 | 資料與內容 | 多寫了資料規格、metadata、API 也算 |

- 每一項的 metadata 在使用限制那一欄都只寫「請參閱平台的使用條款及免責聲明」，沒有哪一項另有條款。
- 同一份資料兩邊都有（Building、Tree、Lamp Post…）時，從哪一邊下載就標哪一邊；DATA.GOV.HK 上這幾項的資源連結其實指向 CSDI，所以**實際下載都走 CSDI，標「香港特別行政區政府（＜機關＞），經空間數據共享平台（CSDI）提供」**。
- **給作者的一句**：賠償條款兩邊都有，和港鐵開放資料（決策 697，已經在用）是同一條。它的意思是「因為你用了這份資料而有人告政府，費用你出」。地形、建物輪廓、地名這類事實資料被第三人主張權利的機會很小；這裡照 HK_MAP 當時的判斷當作可以接受。**作者若不接受，下面香港的每一項都有替代**（地形用 Copernicus、建物留 OSM、地名用 OSM），只是品質差一截。

### 2.3 其他

| 資料 | 條款 | 標示 |
| --- | --- | --- |
| ESA WorldCover 2021 v200 | CC BY 4.0 | © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium |
| VIIRS 夜間燈光（OpenLandMap 的年平均） | STAC 的 collection 寫 `CC-BY-4.0`，產生者 OpenGeoHub Foundation；上游是 Elvidge 等人（2021）的 Annual VNL V2 | OpenGeoHub／OpenLandMap 與 Elvidge et al. 2021 兩者都寫 |
| OpenStreetMap | ODbL 1.0 | 遊戲已有 |
| Copernicus DEM | 遊戲已有（決策 124），`DataSourceCredits` 已有聲明 | — |
| 亮星表、行星位置、星座名表、銀河底圖 | 沒有重查（SOURCES.md D24、D25：亮星表的再散布條款當時就沒查清） | — |
| OpenNGC | CC BY-SA 4.0，**不拿** | — |

## 3. 樣本驗證（規劃點名的十項）

座標系：香港政府的向量與地形都是 **Hong Kong 1980 Grid（EPSG:2326，公尺）**；CSDI 的 REST 可以要求直接回 WGS84（`outSR=4326`），GeoJSON 下載檔也是 WGS84。路燈與兩份康文署的樹本來就是 WGS84。

### 3.1 Building（地政總署）：**值得拿**

| | |
| --- | --- |
| 入口 | CSDI `landsd_rcd_1637211194312_35158`（DATA.GOV.HK `hk-landsd-openmap-landsd-building` 只是指過來） |
| 下載 | `static.csdi.gov.hk/csdi-webpage/download/common/c0623f7d…`（GeoJSON zip **73.9 MB**）、`…/a28dafe1…`（FGDB zip 88.2 MB）；HEAD 200。這次沒有抓整包，改用 REST 把 342,233 筆屬性全部抓下來（115 次請求，每次 3,000 筆） |
| 更新 | 每月；metadata 2026-10-22，資料裡最新一筆 2026-10-12 |
| 欄位 | `BuildingBlockType`、`BuildingNameEN`／`TC`、`BaseHeight`、`TopHeight`（公尺，香港主水平基準以上）、`Storeys`、`StoreysInBasement`、`BuildingCSUID`、`Shape__Area`；另有五張附表（名稱、入伙紙的樓層與樓面面積等） |

量到的：

| | 棟數 | 有實測高度（`TopHeight > BaseHeight`） | 佔地 |
| --- | --: | --: | --: |
| Tower（大樓） | 213,402 | 213,393（100.0%） | 35.0 km² |
| Podium（平台） | 9,049 | 9,049（100.0%） | 18.3 km² |
| Temporary Structure（臨時構築物） | 75,071 | 7,783（10.4%） | 8.7 km² |
| Open-sided Structure（開放式構築物） | 44,711 | 5,627（12.6%） | 4.0 km² |
| **合計** | **342,233** | **235,852（68.9%）** | **66.1 km²**（有高度的佔 83.3%） |

- 高度（頂減底）：中位數 7.9 m、第 90 百分位 23 m、最高 460.6 m；30 m 以上 17,844 棟、100 m 以上 2,705 棟、200 m 以上 27 棟。
- `Storeys` 只有 60,294 棟有（17.6%）：**要用高度，不要用樓層**（樓層 = 高度 ÷ 3.2 m 之類，照 `build_hk_buildings.py` 現有的換算）。
- 有名字的 68,189 棟（19.9%）。
- 面積不到 30 m² 的 86,472 棟（多半是臨時與開放式構築物）；30 m² 以上的 255,761 棟裡 74.6% 有高度。

和香港地圖包現有的 OSM 建物比（`tools/hk-map/hk_buildings.json`；今天重抓的 OSM 整包檔是 121,321 棟）：

| | OSM（現有） | 地政總署 Building |
| --- | --: | --: |
| 棟數 | 117,245 | 342,233（永久建物 222,451） |
| 高度來自資料 | 58,140（49.6%，`building:levels` 為主；有 `height` 的只有 2,017） | 235,852（68.9%）；永久建物 100% |
| 高度是估的 | 59,134 | 永久建物 9 棟 |
| 佔地 | 48.6 km² | 66.1 km²（永久建物 53.3 km²） |
| 大小 | `buildings.pmtiles` 2.26 MB | 估 4–5 MB（只收永久建物加 30 m² 以上有高度的構築物，約 23 萬棟，照現有每棟約 19 位元組推） |

- 平台與大樓分開，是香港建築的樣子（商場平台上面幾座塔樓）；OSM 多半畫成一整塊，現在是一整塊拉到塔樓的高度。
- 風險：臨時構築物九成沒有高度，要給一個固定的矮高度或不收；`BaseHeight` 是絕對高度，沒有地形時只能用頂減底；用途（住宅、商業）這份沒有，要留著 OSM 的用途或從 iGeoCom 補；每月更新，工具要記下載日期與 SHA-256。

### 3.2 Digital Terrain Model（地政總署）：**值得拿**

| | |
| --- | --- |
| 入口 | CSDI `landsd_rcd_1638158088368_93806` |
| 下載 | `static.csdi.gov.hk/csdi-webpage/download/common/e9a836d0…`，HTTP 200，zip **24,206,651 B**；解開是一個 GeoTIFF **498 MB**（未壓縮）加 `.tfw` |
| 格式 | 12,751 × 9,601 格，**5 m**，int32 公尺，無資料 −9999，EPSG:2326，範圍 E 800,000–863,750、N 800,000–848,000 |
| 日期 | 檔案 2022-03；metadata 寫由 DOP5000（2015 年 12 月版）衍生，更新「有需要時」 |
| 內容 | 最低 −22 m、最高 958 m（大帽山 957 m，位置對）；高於 1 m 的佔 36%（陸地），高於 100 m 的佔 16% |
| 官方註明的限制 | 「土地被植被遮蓋時，地形以植被的高度表示」：山上的樹林是樹頂的高度，不是地面 |

**和遊戲現在用的 Copernicus DEM 比**（九龍、港島北、沙田一帶，都取到約 58 m 一格，27,808 格）：

| | 地政總署 DTM | Copernicus GLO-30 |
| --- | --: | --: |
| 平地市區（地政總署 15 m 以下，10,574 格）的中位數 | 6.0 m | 9.3 m |
| 同一批格子的第 90 百分位／最高 | — | 23.9 m／**109.5 m** |
| 平地上相鄰兩格的高差：平均／第 95 百分位 | **1.2 m**／4.7 m | 3.3 m／10.6 m |
| 兩者相差超過 10 m 的格子 | 11.2%（超過 20 m 的 4.4%） | |

- Copernicus 是地表模型，把大樓算進去；香港的高樓密度讓市區平地變成一格一格的小丘。地政總署這份從量到的起伏看是去掉建物的地面（它叫地形模型，官方只註明植被沒去掉）。
- 所以香港的地形**用地政總署這份**，不照搬台灣的 `build_slope_grid.py` 加 Copernicus。Copernicus 留作作者不接受賠償條款時的退路。
- 大小：台灣是 1.875″（約 58 m）一格的 `taiwan_heights.dat`（12 MB）加 `taiwan_terrain.pmtiles`（10 MB）。香港同樣的格子約 1,100 × 830 格；量到 100 m 一格壓縮後 147 KB、30 m 一格 1.4 MB，58 m 一格估 **0.4–0.6 MB**，地形圖磚再加約 0.3 MB。
- 順帶一提（不在這張單的範圍）：台灣的市區用的也是 Copernicus，同樣把大樓算進地面。作者 11-13 說的「高速公路凹凸不平」（ROAD-LAYER）可能有一部分來自這裡，值得 ROAD-LAYER 量一次。

### 3.3 Place Name（地政總署）：**小，拿**

| | |
| --- | --- |
| 入口 | CSDI `landsd_rcd_1648571595120_89752` |
| 下載 | `…/download/common/4b90b9ac…`（CSV zip **87,680 B**），HTTP 200；兩個 CSV：點位 2,706 筆、名稱 2,826 筆 |
| 日期 | 2026-06-10 |
| 欄位 | 點位：`GEO_NAME_ID`、`PLACE_CLASS`、`PLACE_TYPE`、`DISTRICT`、東距、北距（EPSG:2326）；名稱：`NAME_EN`、`NAME_TC`、`NAME_STATUS`（Official 2,706、Alias 120） |
| 內容 | 聚落 1,613（村 1,299、地區 301、市鎮 13）、地形 796（山 315、海角 165、島 156…）、水文 297（海灣 209…）。中文名 2,714 筆、英文名 2,822 筆 |
| 限制 | **市區很稀**：油尖旺 7 筆、深水埗 10 筆、九龍城 11 筆、中西區 22 筆；新界北 484、西貢 482、離島 446。它是「地理名稱」，不是街區名 |

- 用處：山、島、海灣、村的官方中英名（地圖標註、新車站在郊區取名）。市區取名要靠 iGeoCom 的地區欄或 OSM 的 `place`（今天的整包檔有 3,222 個 `place` 節點）。

### 3.4 iGeoCom（地政總署）：**拿，分兩次用**

| | |
| --- | --- |
| 入口 | DATA.GOV.HK `hk-landsd-openmap-development-hkms-digital-geocom`；CSDI 上的 REST 要金鑰（HTTP 499），只能下載整檔 |
| 下載 | `open.hkmapservice.gov.hk/OpenData/directDownload?productName=iGeoCom&sheetName=iGeoCom&productFormat=CSV`，補上中間憑證後 HTTP 200，zip **2,724,531 B**，解開 `iGeoCOM_POI.csv` 9.7 MB |
| 日期 | 每季；最新一筆修訂 2026-08-28 |
| 筆數 | **37,379 個點** |
| 欄位 | 中英名稱、`CLASS`（18 類）、`TYPE`、`SUBCAT`、東距、北距（EPSG:2326）、樓層、所在建築、**`E_AREA`／`C_AREA`（地區，例如「啟德」）**、區、地址、電話、網址、修訂日期 |
| 內容（例） | 商場 805、酒店 331、小學 618、中學 539、專上院校 123、醫院 60、公園 194、廟宇 308、街市 199、碼頭 507、巴士總站 662、**港鐵站出入口 611** |

- 第一次用（排第 4）：`C_AREA`／`E_AREA` 給每個點一個街區名，是市區取站名最好的來源。
- 第二次用（排第 7）：商場、學校、醫院、酒店當地標與客源點。這會碰需求規則（GameCore），要另開決策、量平衡。
- 風險：電話、地址、網址不要帶進資料檔（用不到，也少一層顧慮）；工具要自己帶中間憑證。

### 3.5 Terrestrial Habitat Map（漁護署）：**之後**

| | |
| --- | --- |
| 入口 | CSDI `afcd_rcd_1639382960762_55768`（名稱「Territory-wide Terrestrial Habitat Map of Hong Kong」；metadata 的建立與修訂年份都寫 2021，就是 SOURCES.md 當時沒核到的那一份） |
| 下載 | FGDB zip **154.9 MB**、SHP 190 MB、GeoJSON 282 MB（HEAD 200）。這次沒抓整包，用 REST 的統計查詢量 |
| 內容 | 21 個圖層（每種生境一層）、**708,300 個多邊形、合計 1,125.8 km²**（香港陸地差不多全部） |
| 面積 | 樹林 270 km²（24.0%）、其他市區 197（17.5%）、木本灌叢 143（12.7%）、灌叢 96（8.5%）、灌草叢 88（7.8%）、草地 82（7.3%）、鄉郊植林 57（5.1%）、市區綠地 42（3.7%）、農地 40（3.6%）、裸岩裸土 35（3.1%）、水塘 22（2.0%）、魚塘等 9、紅樹林 6、沼澤 3… |

- 比 OSM 的土地覆蓋完整（OSM 有畫才有），也比 WorldCover 細：WorldCover 在香港同一塊沒有灌叢這一類（下一小節）。
- 香港底圖現在的綠地、水、土地覆蓋來自 OSM，已經看得到山是綠的。這份能讓山上分出樹林、灌叢、草坡三種顏色，是好看一點，不是從無到有。
- 70 萬個多邊形不能直接包；要先燒成 30–60 m 的格子（一格一個類別），估 0.3–0.6 MB。

### 3.6 ESA WorldCover：**香港不用；台灣遠景另案**

| | |
| --- | --- |
| 下載 | `esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N21E114_Map.tif`，HTTP 200，**53,611,017 B**（3° × 3° 一塊；香港西邊在另一塊 `N21E111`，87.7 MB） |
| 格式 | 36,000 × 36,000，uint8，EPSG:4326，約 10 m，2021 年，檔案日期 2022-10-26 |
| 香港（東經 114.0–114.47）的類別 | 水 58.6%、樹 29.5%、建成區 8.9%、草 1.8%、裸地 0.7%、農地 0.3%、紅樹林 0.2%、**灌叢 0.0%** |

- 香港的灌叢與灌草叢（生境圖合計約 29% 的陸地）在 WorldCover 裡全併進「樹」。香港有生境圖，不需要 WorldCover。
- 台灣：SOURCES.md D23 已寫參考庫有現成的 918 塊成品（23 MB）與產生器，當時結論「有條件採用，只補遠景」。這次沒有新發現；它不是香港這一批的事，維持原狀。

### 3.7 Pavement Polygon（路政署）：**之後**

| | |
| --- | --- |
| 入口 | CSDI `hyd_rcd_1632210918434_60749` |
| 下載 | FGDB zip **28.9 MB**（HEAD 200）；GeoJSON 與 KML 的連結 404，GML 的 zip 只有 682 B（壞的）；REST 可以用 |
| 日期 | 每季；2026-11-13 |
| 筆數 | 65,009 個多邊形 |
| 欄位 | `FEAT_TYPE`（車行道 19,427 個 30.6 km²、行人路 38,859 個 9.1 km²、後巷、單車徑、安全島…）、`SUR_TYPE_1`（柔性路面 23.7 km²、剛性 10.8、**地磚 5.1**）、`PAVER_TYPE`（黏土磚、混凝土磚、花崗石…）、**`LVL`（地面 62,376、高架一層 2,195、地下一層 370、高架二層 64…）** |

- 能給香港真實的路幅、行人路與路面材質，還有每一塊在第幾層。只涵蓋路政署維護的路。
- 遊戲的路是照 OSM 中心線加道路等級畫的；要改成畫真實路面多邊形是 3D 道路的大改，而 ROAD-LAYER（台灣的道路分層與高度）還沒做。等 ROAD-LAYER 做完、香港有人玩了再看。

### 3.8 Tree（路政署）：**之後，便宜**

| | |
| --- | --- |
| 入口 | CSDI `hyd_rcd_1632210213867_60179` |
| 下載 | `…/download/common/36a77e66…`（CSV zip **8,953,135 B**，解開 51 MB），HTTP 200 |
| 日期 | 每季；2026-10-29 |
| 筆數 | **302,009 棵** |
| 欄位 | 東距、北距、胸徑、**樹高（全部有；中位數 8 m、第 90 百分位 13 m）、樹冠寬（中位數 5 m）**、樹種（台灣相思 44,766、血桐、檸檬桉、木麻黃、朴樹、細葉榕…；57,935 棵未鑑別）、路名、地面高度 |

- 只有路政署管的路旁與斜坡的樹，不是全港。OSM 在香港只有 5,576 個樹的節點。
- 遊戲的行道樹是照路推的；換成真實位置、高度、樹冠是資料替換。只留位置、高度、樹冠三欄量化後估 0.8–1.2 MB。

### 3.9 Lamp Post（路政署）：**之後，便宜**

| | |
| --- | --- |
| 下載 | `plis.hyd.gov.hk/datagovhk/plis/lamppost_en.csv`，HTTP 200，**8,633,164 B**，144,995 筆；CSDI 的 CSV zip 3.5 MB（REST 144,873 筆） |
| 日期 | 每季；2026-06-30 |
| 欄位 | 燈柱編號、區、位置描述、緯度、經度（WGS84）。**沒有高度、型式** |

- 遊戲的路燈是沿路每隔一段擺的；真實位置讓夜裡的光點排得像真的（MAP-LIVELY 決策 721 的夜景）。OSM 在香港只有 718 盞。
- 只留座標量化後估 0.3–0.4 MB。

### 3.10 VIIRS 夜間燈光：**之後**

| | |
| --- | --- |
| 入口 | OpenLandMap 的 STAC：`s3.eu-central-1.wasabisys.com/stac/openlandmap/nightlights.average_viirs.v21/collection.json`（`license: CC-BY-4.0`） |
| 檔案 | `s3.openlandmap.org/arco/nightlights.average_viirs.v21_m_500m_s_20210101_20211231_go_epsg.4326_v20230823.tif`，全球一個 COG，可以只讀一小塊（HTTP 範圍請求，200） |
| 格式 | 86,400 × 35,849，int16，EPSG:4326，約 500 m，2021 年平均（collection 有 2000–2021；2012 年以前是回推的，說明寫「小心使用」） |
| 香港 | 161 × 108 格（原始 35 KB）：最高 2,390、中位數 30、第 90 百分位 410 |
| 台灣 | 528 × 864 格（原始 0.9 MB）：最高 2,580、中位數 0、有光的格子 24% |

- 用處：夜景的亮度分布（哪一區亮、哪一區暗）。500 m 一格太粗，分不出街道，只能當「這一帶整體多亮」的底。
- 遊戲的夜景現在照建物與路燈自己發光（決策 721），亮暗已經跟著建物密度走。這份要等 MAP-LIVELY 收完，看夜景還缺不缺整體亮度再說。很小（台灣量化後估 0.2 MB）。

### 3.11 OSM 的路面與階梯（沒有新下載的必要）

今天的香港整包檔（`osmtoday.com/asia/china/hong_kong.pbf`，43,966,311 B）：

| | 數量 |
| --- | --: |
| 有 `highway` 的路 | 188,999（有 `surface` 的 47,631，25%；車道 72,985 條裡有 `surface` 的 26,940、有 `lanes` 的 37,502、有 `width` 的 49） |
| `surface` 的值 | asphalt 23,175、concrete 9,815、paved 9,159、paving_stones 3,299… |
| 階梯（`highway=steps`） | 11,586（有 `step_count` 的 450） |
| 行人路（`footway=sidewalk`） | 14,992 |

- 遊戲已經在用 OSM，授權不用再談。香港是山城，階梯很多；但遊戲不畫行人路網，路面材質也只在很近的鏡頭才分得出來。**有需要再讀，不排**。

## 4. 總表（全部候選）

「動 GameCore／存檔」欄寫「否」表示只動工具、資料檔與 GamePresentation。「包」是香港地圖包（現在 10.4 MB）或 App 會多多少，都是估的。

### A. 香港政府資料（24 項）

| # | 項目 | 條款 | 玩家看得到的差別 | 工作量 | 動 GameCore／存檔 | 包 | 風險 | 結論 |
| --: | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | 3D Visualisation Map | DATA.GOV.HK／CSDI | 等 HK-3DVIS | — | — | — | — | **等 HK-3DVIS** |
| A2 | 3D Spatial Data (3D-BIT00) | CSDI | 地標的真實外形 | 大（3 天以上） | 否 | 看選幾棟 | 要用地政總署 3D 的下載 API（按圖幅，3,295 幅）；和 A1 是同一類問題，A1 有結論後一起看 | 之後（跟 A1） |
| A3 | **Buildings** | CSDI | 香港的樓高是真的：中環、九龍站的塔樓不再是估的；平台與塔樓分開；棟數多兩倍 | 1.5–2 天 | 否 | ＋2–3 MB | 臨時構築物沒高度；沒有用途欄；每月更新 | **接（第 2）** |
| A4 | Geographic Name／**Place Name** | CSDI | 山、島、海灣、村有官方中英名；郊區新車站的名字 | 併在第 4 名，0.5–1 天 | 否 | ＋0.1 MB | 市區很稀 | **接（第 4）** |
| A5 | **iGeoCom** | DATA.GOV.HK | 先：市區新車站取名用街區名。後：商場、學校、醫院當地標與客源 | 先 0.5 天（併第 4）；後 2–3 天 | 先否；後要（需求規則，另開決策） | ＋0.2–0.5 MB | 主機少送中間憑證；CSDI 的 REST 要金鑰；每季更新 | **接（第 4、第 7）** |
| A6 | **Digital Terrain Model** | CSDI | 香港有山：太平山、大帽山、獅子山立起來；鐵路該挖隧道的地方挖隧道；配上水域，維多利亞港不能平鋪軌道 | 1.5–2 天 | 否（地形是開新局時讀的資料；已開的局不變） | ＋0.7–1 MB | 樹林是樹頂高度；2015 年的航測；座標要自己從 EPSG:2326 轉 | **接（第 1）** |
| A7 | iB1000 | DATA.GOV.HK（地政總署） | 很細的地物（圍牆、樓梯、斜坡線） | 大 | 否 | 大 | 香港底圖已用 OSM；schema 要全部對一遍 | 不接 |
| A8 | iB5000 | 同上 | 同上，較粗 | 大 | 否 | 中 | 同上 | 不接 |
| A9 | **Pavement Polygon** | CSDI | 真實的路幅、行人路、地磚路面；每塊在第幾層 | 3 天以上 | 否 | ＋2–4 MB | 3D 道路要改畫法；只有路政署的路；GeoJSON 連結壞的 | 之後（第 11；等 ROAD-LAYER） |
| A10 | **Lamp Post** | DATA.GOV.HK／CSDI | 夜裡的路燈在真實位置 | 0.5–1 天 | 否 | ＋0.3–0.4 MB | 沒有型式與高度 | 之後（第 10） |
| A11 | Barrier Fence | CSDI | 路邊欄杆 | 1 天 | 否 | ＋0.5 MB | 19,148 條線；近看才看得到；沒有模型 | 不接 |
| A12 | **Tree（路政署）** | CSDI | 路旁的樹在真實位置，高矮與樹冠是真的 | 1 天 | 否 | ＋0.8–1.2 MB | 只有路政署的樹；樹種要對到遊戲的幾種樹形 | 之後（第 9） |
| A13 | Trees (Major Parks) | CSDI | 大公園裡的樹 | 併 A12，＋0.5 天 | 否 | 小 | 30,526 棵；只有幾座公園 | 之後（跟 A12 一起或不做） |
| A14 | Trees (LCSD other venues) | CSDI | 其他康文署場地的樹 | 同上 | 否 | 小 | 99,420 棵 | 同上 |
| A15 | Trees on slopes (ArchSD) | CSDI | 斜坡上的樹 | 同上 | 否 | 小 | 125,849 棵；斜坡上看不太到 | 不接 |
| A16 | Vegetation（路政署） | CSDI | 路旁植被塊 | 1 天 | 否 | 小 | 13,145 塊；生境圖已涵蓋 | 不接 |
| A17 | Registered Man-made Slopes | CSDI | 人造斜坡的範圍 | 1–2 天 | 否 | 中 | 61,525 塊；遊戲沒有擋土牆的畫法 | 不接 |
| A18 | Grass-cutting Sites | CSDI | 無 | — | — | — | 1,268 塊管理清冊，不是草地 | 不接 |
| A19 | Road Network（運輸署） | DATA.GOV.HK／CSDI | 官方的中心線、速限、轉向 | 大 | 否 | 中 | 遊戲的路用 OSM；兩套路網不能混 | 不接 |
| A20 | Traffic Aids Drawings | DATA.GOV.HK | 標誌與標線的位置 | 大 | 否 | 中 | 遊戲的標線是照規則畫的（`tools/map3d-road-markings`） | 不接 |
| A21 | **Terrestrial Habitat Map 2021** | CSDI | 山上分得出樹林、灌叢、草坡；市區綠地完整 | 1.5–2 天 | 否 | ＋0.3–0.6 MB | 155 MB、70 萬個多邊形，要先燒成格子 | 之後（第 8） |
| A22 | Digital Orthophoto DOP5000 | CSDI | 無（寫實航照不合畫風） | — | — | 很大 | 條款可用，但用不上 | 不接 |
| A23 | 機場低能見度時數（天文台） | DATA.GOV.HK | 香港的霧日 | 0.5 天 | 要（天氣規則） | 很小 | 只有機場一個測站；遊戲的天氣是氣候區規則 | 不接 |
| A24 | Hiking Trails（漁護署） | CSDI | 郊野公園的遠足徑 | 0.5–1 天 | 否 | ＋0.1 MB | 167 條；鐵道遊戲用不到，除非做觀光景點 | 不接（做香港觀光時再看） |

### B. 其他

| # | 項目 | 條款 | 玩家看得到的差別 | 工作量 | 動 GameCore／存檔 | 包 | 風險 | 結論 |
| --: | --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | ESA WorldCover | CC BY 4.0 | 香港：無（生境圖更好）。台灣：遠景地面顏色 | 台灣 1–2 天 | 否 | 台灣＋數 MB | 香港沒有灌叢類；台灣的結論在 SOURCES.md D23 | 香港不接；台灣維持原結論 |
| B2 | OSM 的路面與階梯 | ODbL（已有） | 很近才看得到的路面材質；階梯 | 1–2 天 | 否 | 小 | `surface` 只有 25% 的路有 | 不排 |
| B3 | **VIIRS 夜間燈光** | CC BY 4.0 | 夜景整體哪裡亮哪裡暗 | 1 天 | 否 | ＋0.2 MB | 500 m 一格，粗；2021 年 | 之後（第 12；等 MAP-LIVELY） |
| B4 | 亮星表（Bright Star Catalogue） | 再散布條款沒查清 | 夜空的星在真的位置 | 1–2 天 | 否 | 小 | 主機這次連不上；條款 | 不排 |
| B5 | 行星位置（JPL 近似公式） | 公式，JPL 公開 | 夜空有行星 | 1 天 | 否 | 無 | 看得到的人很少 | 不排 |
| B6 | 星座名表 | BSD-3（規劃查的） | 無（遊戲不標星座） | — | — | — | — | 不排 |
| B7 | 銀河底圖 | 沒查 | 夜空有銀河 | — | — | — | 沒有指定來源 | 不排 |
| B8 | OpenNGC | CC BY-SA 4.0 | — | — | — | — | copyleft | **不拿** |

### C. 台灣官方統計（`OFFICIAL_STATS_2026-11-13.md`，結論不重查）

| # | 項目 | 條款 | 玩家看得到的差別 | 工作量 | 動 GameCore／存檔 | 包 | 風險 | 結論 |
| --: | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | **觀光人次第 1 步**（data.gov.tw 8116） | 政府資料開放授權條款第 1 版 | 景點卡多一行官方一年人次 | 1–1.5 天 | 否 | 很小 | 沒有座標，要人工對照表；不同類型的數字不能互比 | **接（第 3）** |
| C2 | 觀光人次第 2 步（同類型內校正星等） | 同上 | 熱門景點真的比較多遊客 | 1–2 天 | 只換資料（星等）；月別曲線才動 GameCore | 無 | 動到觀光收入，要量平衡 | 接（第 5） |
| C3 | 機場按月營運量（31915、33238） | 同上 | 機場有淡旺季 | 1–1.5 天 | 待查（月別係數在哪一層） | 很小 | 見左 | 接（第 6） |
| C4 | 商港旅客（8366） | 同上 | 無（只有郵輪與長程客船） | — | — | — | — | 之後（做離島航線或郵輪時） |
| C5 | 國土測繪中心正射影像 | 不是開放資料 | — | — | — | — | 不能包進 App | **不接** |

### D. 3D Visualisation Map：等 HK-3DVIS（同 A1）

## 5. 先後

| 名次 | 任務 | 來源 | 一句理由 |
| --: | --- | --- | --- |
| 1 | **HK-GROUND**：香港的地形與規則用的水域 | A6（＋OSM 水域，現有工具） | 香港現在全平、海在規則上是陸地；這兩樣是開新局時寫進世界的，130 開香港之後越晚補，越多已開的局用不到 |
| 2 | **HK-BUILDINGS-GOV**：香港建物改用地政總署 | A3 | 永久建物 100% 有實測高度（OSM 一半是估的），棟數多兩倍，平台與塔樓分開；排第 2 是因為 OSM 建物已經讓天際線存在，這是從「有」到「對」 |
| 3 | **TOURISM-OFFICIAL-1**：景點卡顯示官方人次 | C1 | 便宜、不動 GameCore、所有玩家都看得到、不用等 #2115，可以和第 1 名同時做 |
| 4 | HK-NAMES：香港的地名網格 | A4＋A5 的地區欄＋OSM `place` | 香港新蓋的車站現在沒有在地的名字；資料小（合計不到 0.5 MB） |
| 5 | TOURISM-OFFICIAL-2：同類型內校正星等 | C2 | 第 3 名的對照表做好才能做；要量平衡 |
| 6 | AIRPORT-MONTHS：機場按月 | C3 | 小；先查月別係數在哪一層 |
| 7 | HK-POI：商場、學校、醫院當地標與客源 | A5 | 香港沒有各站人次，客源點是之後校正需求最好的材料；但要動需求規則，另開決策 |
| 8 | HK-HABITAT：山上的地面顏色 | A21 | 好看一點，不是從無到有；要先有第 1 名的地形，顏色貼在山上才有意義 |
| 9 | HK-TREES：行道樹用真實位置與高度 | A12（A13、A14 可併） | 資料完整、便宜；近景才看得到 |
| 10 | HK-LAMPS：路燈用真實位置 | A10 | 最便宜；等決策 721 的夜景定了再接，才知道要幾盞 |
| 11 | HK-PAVEMENT：真實路面與行人路 | A9 | 3D 道路要改畫法；等 ROAD-LAYER |
| 12 | NIGHT-LIGHTS：夜景亮度分布 | B3 | 粗，而且夜景已經跟著建物密度亮；等 MAP-LIVELY 收完看缺不缺 |
| — | 等 HK-3DVIS | A1、A2 | 不重做；A2（3D-BIT00）跟它的結論一起看 |
| — | 之後 | C4、A24、B1（台灣遠景） | 有對應的功能要做時再接 |
| — | 不排 | B2、B4–B7、A13–A14（單獨做時） | 幫助小 |
| — | 不接 | A7、A8、A11、A15–A20、A22、A23、B8、C5 | 第 4 節各列的理由 |

### 5.1 和 NEXT_PRIORITIES 現有的項目怎麼合

- 這一批**全是資料線**：前六名都不動 GameCore 的程式、不動存檔版本、golden、fixtures，不佔「同時最多 2 個 GameCore PR」的名額。**不改 §24–§27 的順序。**
- **第 1、2、4 名接在 AIR-UNLOCK-4（#2115）後面**：三張都要改 `tools/hk-map/`、`MapPacks/hongkong/pack.json`，#2115 沒合之前開工會撞檔。#2115 合了就可以派第 1 名；第 1、2 名改的資料檔不同（地形與水域對建物），但都改 `pack.json` 與 `tools/hk-map/README.md`，**一次派一張**，或派給同一個 session 連著做。
- **能不能趕上 130**：第 1 名約 2 天，要看 130 什麼時候發。趕得上最好（玩家第一次開香港就有山有海）；趕不上就照舊發，更新說明寫「香港的地形下一版加」，已開的香港局維持平的。這是規劃與作者的時機判斷，這裡不定。
- **第 3 名現在就可以派**：和香港無關，只動 `tools/tourism-spots/`、景點卡、`DataSourceCredits`。
- **ROAD-LAYER**（作者 11-13 的道路破圖與高速公路凹凸）不在這份清單裡，但 3.2 的發現（Copernicus 在市區把大樓算進地面）和它有關，建議 ROAD-LAYER 開工時先量台北、高雄市區平地的地面高度起伏。
- 第 7 名（HK-POI）要動需求規則，到時照 economy-balance 量，並排進 GameCore 那條線的名額。

## 6. 前三名的任務單

### 6.1 HK-GROUND：香港的地形與水域

**範圍**
- 新工具 `tools/hk-map/build_hk_ground_grids.py`（名字可改；`build_hk_ground.py` 已經是別的用途，先讀它）：
  - 讀地政總署 DTM 的 GeoTIFF（EPSG:2326，5 m），取樣成和 `taiwan_heights.dat` 同一種格式、同一種格距（1.875″）的香港高度檔；每格取範圍內的平均。座標轉換自己寫（EPSG:2326 是橫麥卡托，參數在 GeoTIFF 裡：原點北緯 22.3121333°、東經 114.1785556°，假東 836,694.05、假北 819,069.8，橢球 International 1924；再加 HK80 到 WGS84 的基準位移，兩三百公尺，**不能省**），用幾個已知點核對：大帽山頂約 957 m（這份量到 958 m，在 E 830,872／N 830,127）、太平山、獅子山。不加 pyproj 之類的依賴進工具的必要條件時，要先問；能用標準函式庫加 numpy 寫就用。
  - 規則用的水域：照 `tools/real-world-population/build_water_grid.py` 的做法讀 `hong_kong.pbf`，產出香港的水域網格。
  - 地形圖磚：`tools/basemap/build_terrain.py` 吃香港的高度檔，產出地圖包自己的地形圖磚（2D 地圖的山影）。
- `MapPacks/hongkong/`：新增高度檔、水域檔、地形圖磚；`pack.json` 的 `files`、`bytes`、`licences` 加「Lands Department, HKSAR Government, via CSDI Portal」。
- GamePresentation：`GameLauncher`（約 2305–2341 行讀 `taiwan_heights`、`taiwan_water` 的地方）與 `HeadlessGame` 改成香港開局時讀地圖包的檔；`MapPack` 加這兩個檔；3D 地圖的地面照高度起伏（台灣已經有，確認香港走同一條路）。
- `DataSourceCredits`：香港那一段加一筆「香港的地形」，出處「地政總署數碼地形模型，香港特別行政區政府，經空間數據共享平台提供」／“Digital Terrain Model, Lands Department, Government of the Hong Kong SAR, via the CSDI Portal”，連到資料集頁與條款。給玩家的說明只寫一句作用（「香港的山與海」）。
- 決策：712 再加一節或取新號，照 #2118 登記。

**主要檔案**：`tools/hk-map/`（新工具、README、`hk_sources.json`）、`RailwayGameApp/Resources/MapPacks/hongkong/`、`Sources/GamePresentation/GameLauncher.swift`、`HeadlessGame.swift`、`MapPack.swift`、`HeightGrid.swift`、`WaterGrid.swift`、`DataSourceCredits.swift`、`Tests/GamePresentationTests/HongKongMapTests.swift`（或新的測試檔）、String Catalog。

**不動**：`Sources/GameCore/`、存檔版本、golden、三套 fixture、台灣的任何資料檔。

**驗收**
- Linux 測試：香港開局的世界在大帽山、太平山的格子高度在 ±30 m 內；維多利亞港中央、吐露港是水；中環、九龍的填海地高度在 0–15 m；港鐵買得到的每條線仍然從頭到尾連得通、過海段仍走隧道（`HongKongMapTests` 原有的測試不變紅）。
- 在香港的海上平鋪軌道被拒絕（和台灣一樣的錯誤）。
- 台灣開局逐位元組不變（現有測試）。
- `pack.json` 的大小與 SHA-256 更新；工具的 README 寫重抓方法與 DTM 的下載日期、SHA-256（這次的 zip：`6dbcdfb5…1af`）。
- 已知限制寫進決策：樹林的高度是樹頂；130 之前或之後開的香港局差在哪。

**截圖**：要。3D 地圖的畫面變了（山立起來），屬「現有畫面的改動」但幅度大，**取第三級**：`testHongKongMap` 重拍，加一張看得到太平山與維多利亞港的，規劃看過才合。

**工作量**：1.5–2 天。**先決條件**：#2115 已合。

### 6.2 HK-BUILDINGS-GOV：香港建物改用地政總署的資料

**範圍**
- 改 `tools/hk-map/build_hk_buildings.py`（或旁邊加一支）：輸入換成地政總署 Building 的 GeoJSON（WGS84，zip 73.9 MB，不提交）。
  - 收：Tower、Podium 全部；Temporary 與 Open-sided 只收 30 m² 以上的，沒有高度的給一層樓高。
  - 高度：`TopHeight − BaseHeight`；樓層數照工具現有的換算（÷ 3.2 m）。`Storeys` 欄只當核對，不當來源（只有 17.6% 有）。
  - 用途：這份沒有。從現有的 OSM 建物取（同一位置重疊的 OSM 建物的用途），沒有對到的照現有的估法。
  - 輸出格式不變（`buildings.pmtiles`，現有的讀取程式不改）。
- 核對：工具印出並寫進 `hk_buildings.json`：棟數、有實測高度的比例、100 m 與 200 m 以上各幾棟（這次量到 2,705 與 27）、最高一棟（460.6 m，應該是環球貿易廣場一帶，約 484 m 的那一棟；差的是底的高度與天線，核對一下）。
- `pack.json`、`DataSourceCredits`（「香港的建物」那一筆改成地政總署，OSM 留在用途）、`tools/hk-map/README.md` 第 7 步。
- 做之前先看 HK-3DVIS 的結論：它若建議地標用 3D Visualisation Map 的模型，這張單的輪廓仍然是一般建物的底，不衝突；但要留「這幾棟由地標模型畫」的清單位置。

**主要檔案**：`tools/hk-map/build_hk_buildings.py`、`hk_buildings.json`、`hk_sources.json`、README；`MapPacks/hongkong/buildings.pmtiles`、`pack.json`；`DataSourceCredits.swift`；`Tests/GamePresentationTests/HongKongBuildingsTests.swift`。

**不動**：`Sources/GameCore/`、存檔、golden、fixtures、讀圖磚的 `Map3D*` 程式（格式不變）。

**驗收**
- `HongKongBuildingsTests` 更新數字並通過：棟數、高度來自資料的比例 ≥ 95%（收進來的永久建物）、中環與九龍站一帶 150 m 以上的建物數量和資料一致。
- `buildings.pmtiles` 不超過 6 MB；超過就提高構築物的面積門檻，並在 PR 寫大小。先在 #2118 說會多幾 MB（超過 2 MB 的規矩）。
- 3D 地圖的三角形預算（決策 711）在九龍、中環不超標：用 `tools/map3d-preview` 或現有的預算測試量一次，棟數多兩倍，這是最大的風險。
- 車站與軌道清建物的規則（`clearOf`）照舊。

**截圖**：要，**第三級**（3D 的樣子變了）：`testHongKongMap` 重拍，加一張維多利亞港兩岸的天際線，和換之前的同一張並排。

**工作量**：1.5–2 天。**先決條件**：#2115 已合；建議在 6.1 之後（建物站在有高度的地面上，一起看圖）。

### 6.3 TOURISM-OFFICIAL-1：景點卡顯示官方遊客人次

範圍、資料檔、工具、出處文字都已經寫在 `OFFICIAL_STATS_2026-11-13.md` 5.1，這裡只補派工要的幾項。

**範圍**
- `tools/tourism-spots/build_official_visitors.py`：讀 data.gov.tw 8116 的 CSV（596 KB，不提交），照人工對照表產出 `official_visitors.json`（每個對上的景點的 2024 年人次與 12 個月）。年度不滿 12 個月、對照表的名稱在 CSV 找不到就失敗。
- `tools/tourism-spots/official_names.json`：從 `docs/research/official-stats-2026-11-13/attraction_matches_2024.csv` 的 95 個自動比對開始，**逐個人工看過**；有疑問的留空。官方寫明不同類型的數字不能互比，所以這一步只顯示，不排名、不改星等。
- 景點卡多一行「一年約 N 萬人次（2024，交通部觀光署）」；沒有對上的景點不顯示這一行。
- `DataSourceCredits` 新的一筆 `sightVisitors`（文字草稿在 OFFICIAL_STATS 5.1）。

**主要檔案**：`tools/tourism-spots/`、`RailwayGameApp/Resources/RealWorld/` 下一個小 JSON、`Sources/GamePresentation/` 的景點卡內容與 `DataSourceCredits.swift`、`RailwayGameApp/Views/` 的景點卡、String Catalog、對應的 Linux 測試。

**不動**：`Sources/GameCore/`、存檔、golden（`GoldenScenarios/tourism.json` 不讀這份）、星等。

**驗收**
- Linux 測試：資料檔讀得進來；每一筆的 12 個月相加等於年合計；對照表裡每個景點 id 都在 `AttractionCatalog`；沒有對上的景點卡不出現那一行；中英文各一句，照 UI_THEME「玩家看的文字」。
- 對照表在 PR 裡列出：對上幾個、留空幾個、哪幾個是多個官方據點相加。

**截圖**：**第一級**（既有卡片多一列），不用規劃看圖；session 自己拍一張有那一行的景點卡放 PR。

**工作量**：1–1.5 天。**先決條件**：無，現在可派。

## 7. 查了什麼、找到什麼（CLAUDE.md 的搜尋紀錄）

| 找了什麼 | 找到什麼 | 用了什麼 |
| --- | --- | --- |
| 遊戲自己的研究 | `peakline-map-engine-study/SOURCES.md`（26 項逐項結論，當時沒下載）、`HK_MAP_2026-11-12.md`（條款 §2.1、連得到的網域）、`OFFICIAL_STATS_2026-11-13.md` | C 整批沿用；A 的入口網址沿用，數字全部重量 |
| 遊戲現有的工具 | `tools/hk-map/build_hk_buildings.py`（OSM 建物）、`tools/real-world-population/build_slope_grid.py`（Copernicus → 高度）、`build_water_grid.py`、`tools/basemap/build_terrain.py`、`tools/place-names/` | 任務單都接在這些工具上 |
| 參考庫 | 這次沒有重新 clone。SOURCES.md 已記：參考庫有 WorldCover 的成品與產生器（D23）；`world-rail-reference-clean` 沒有香港（HK_MAP §4） | 無新的 |
| 外面的專案 | 沒有另外找：這次要回答的是「資料能不能用、先用哪個」，不是演算法。座標轉換（EPSG:2326）是公開的橫麥卡托公式，任務單寫明自己寫並用已知點核對 | 無 |
| Peakline | 只用作者貼的鳴謝清單當候選名單；沒有讀它的程式、沒有下載它的衍生資料庫 | 無 |

## 8. 怎麼重抓

大檔都沒有提交。以下是這次用的網址與結果（2026-11-13）；`static.csdi.gov.hk` 的網址是內容雜湊，資料更新後會變，要從 metadata 重新取。

```sh
# 1. 一項資料有哪些下載檔：讀它的 metadata，找 <gmd:URL>
curl -s https://portal.csdi.gov.hk/csdi-webpage/metadata/landsd_rcd_1637211194312_35158 | grep -o '<gmd:URL>[^<]*'

# 2. 筆數、欄位、分頁抓屬性（不用金鑰；一次最多 3,000 筆；outSR=4326 可直接要 WGS84）
curl -s 'https://portal.csdi.gov.hk/server/rest/services/common/landsd_rcd_1637211194312_35158/FeatureServer/0?f=json'
curl -s 'https://portal.csdi.gov.hk/server/rest/services/common/landsd_rcd_1637211194312_35158/FeatureServer/0/query?where=1%3D1&returnCountOnly=true&f=json'
curl -s 'https://portal.csdi.gov.hk/server/rest/services/common/landsd_rcd_1637211194312_35158/FeatureServer/0/query?where=1%3D1&outFields=*&returnGeometry=false&orderByFields=OBJECTID&resultOffset=0&resultRecordCount=3000&f=json'

# 3. iGeoCom：主機少送中間憑證，另外抓來驗（不要關憑證檢查）
curl -s -o ecert.crt http://www1.eCert.gov.hk/root/ecert_ssl_ca_3-17.crt
openssl x509 -inform DER -in ecert.crt -out ecert.pem
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt ecert.pem     # 要印 OK
cat "$SSL_CERT_FILE" ecert.pem > bundle.pem                              # 沒有 SSL_CERT_FILE 就用系統的 CA 檔
curl --cacert bundle.pem -L -o igeocom.zip 'https://open.hkmapservice.gov.hk/OpenData/directDownload?productName=iGeoCom&sheetName=iGeoCom&productFormat=CSV'
```

| 樣本 | 網址 | 大小 | SHA-256（前 12 碼） |
| --- | --- | --: | --- |
| DTM GeoTIFF zip | `static.csdi.gov.hk/csdi-webpage/download/common/e9a836d098a3a9ccf55a7f61f69a93e71923c722fb94ddf7b36be83a67b99140` | 24,206,651 | `6dbcdfb50bbc` |
| Place Name CSV zip | `…/common/4b90b9ac8748d428918b086b382a544fc197693acb81c63b4b4b70ba7570d833` | 87,680 | `37583a6b7c3f` |
| Tree (HyD) CSV zip | `…/common/36a77e66badc818fa5b44dc6469dcad003d2710c0d4391aa38cd3678a5c6815c` | 8,953,135 | `d64f565ce467` |
| iGeoCom CSV zip | 上面第 3 步 | 2,724,531 | `d96118a4782b` |
| Lamp Post CSV | `plis.hyd.gov.hk/datagovhk/plis/lamppost_en.csv` | 8,633,164 | `c82d05cb082e` |
| Building GeoJSON zip（只 HEAD，沒抓） | `…/common/c0623f7db229af2dfb5bdfe62a8fdbc9d094d459b50baa200da4ddbe4e6b5c62` | 73,920,546 | — |
| Habitat FGDB zip（只 HEAD） | `…/common/2c5401b49ea4237d72916c679426ce4dcfc4d301c68c50c71fce566bab7c2953` | 154,891,754 | — |
| Pavement FGDB zip（只 HEAD） | `…/common/4393d90e1e94c870d4ee8b131e10ccb5df16761e4ba389fad732b314c04086c7` | 28,877,659 | — |
| WorldCover `N21E114` | 3.6 節的網址 | 53,611,017 | `7a67580730d8` |
| VIIRS 2021 | 3.10 節的網址（只讀香港與台灣兩塊） | — | — |
| Copernicus `N22_00_E114_00` | `copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N22_00_E114_00_DEM/Copernicus_DSM_COG_10_N22_00_E114_00_DEM.tif` | 25,030,462 | — |
| OSM 香港整包檔 | `osmtoday.com/asia/china/hong_kong.pbf`（轉到 geo2day.com） | 43,966,311 | `f24a6808b505` |

讀柵格用了 `rasterio`（`pip install rasterio`，只在這次的暫時腳本裡；沒有加進任何工具）。任務單裡的工具要不要用它，照「加依賴先問」處理；GeoTIFF 這一份未壓縮、單一波段，用 numpy 直接讀得出來。

## 9. 五個角度

- **玩家**：香港現在是一塊平地上的樓；先給山與海（第 1 名），再把樓高弄對（第 2 名），是開香港地圖的人第一眼的差別。台灣這邊所有玩家都在玩，所以便宜又看得到的觀光人次排第 3，不讓香港佔滿前面。路燈、樹、路面要拉很近才看得到，排後面。
- **鐵道迷**：地形決定鐵路哪裡是隧道、哪裡是高架，香港的鐵路幾乎都在山與海之間，沒有地形就不像港鐵；地形、建物、地名都用地政總署的官方資料，講得出出處與日期。各站人次香港沒有公開，客源點（第 7 名）是之後唯一有出處的校正材料。夜空的星與行星和鐵路無關，不排。
- **開發**：前六名都不動 GameCore 的程式與存檔；香港三張都接在現有的 `tools/hk-map/` 與地圖包格式上，不加執行期的依賴。最大的技術風險是建物多兩倍之後的三角形預算，以及 EPSG:2326 的座標轉換要自己寫對。要動規則的（第 5 名的月別曲線、第 7 名的客源點）排在後面、各自開決策。
- **美術**：地形與真實樓高是香港 3D 畫面最大的兩個缺口，都取第三級截圖審。生境圖讓山有層次，但要先有山；寫實航照（DOP5000、正射影像）不合畫風，不拿。
- **音樂**：無。

## 10. 驗證

**VERIFIED（2026-11-13，Linux 雲端容器）**
- 兩份條款的網頁全文讀過（2.1、2.2）。
- 規劃點名的十項：Buildings（屬性全抓、342,233 筆）、DTM（整檔）、Place Name（整檔）、iGeoCom（整檔）、Habitat（REST 統計）、WorldCover（一塊）、Pavement（REST 統計與一筆幾何）、Tree（整檔）、Lamp Post（整檔）、VIIRS（香港與台灣兩塊）。
- 其餘香港項目：CSDI 上的筆數（A9–A21、A24）與下載檔大小（HEAD）。
- DTM 與 Copernicus 的比較（3.2）。

**UNVERIFIED**
- 沒有任何一項接進遊戲；工作量、地圖包大小是估的。
- Buildings 的幾何沒有抓（只抓屬性與面積欄）；`buildings.pmtiles` 會變多大是照現有每棟的位元組數推的。
- 3D 的三角形預算在建物多兩倍後會不會超標，沒有量。
- A1（3D Visualisation Map）、A2（3D-BIT00）的模型沒有下載（等 HK-3DVIS）。
- A7、A8（iB1000、iB5000）、A19、A20、A22、A23 只確認入口與條款，沒有看資料內容。
- 星空那幾項沒有重查；亮星表的主機這次連不上。
- 賠償條款「可以接受」是照 HK_MAP 當時的判斷沿用，不是法律意見。
