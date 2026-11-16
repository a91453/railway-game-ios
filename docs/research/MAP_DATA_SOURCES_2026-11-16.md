# 地圖資料來源：適不適合遊戲（五方評分）

日期：2026-11-16。基準：`main` 7c3dec4。
派工：MAP-DATA-SOURCES（作者 11-16：「開一個 pr 五方評分研究適不適合遊戲」）。只研究、只寫文件，不改遊戲。
評估對象：

1. 作者 11-16 提的地面資料候選：ESA WorldCover 10 m 2021 v200、台灣國土利用調查、香港地政總署開放地圖／規劃署土地用途、芬蘭 Maastotietokanta、Meta/WRI 1 m 樹冠高度。
2. 作者同時貼來一份別的遊戲的第三方授權頁，當作範例；裡面提到的資料（地政總署 DTM 5 m、香港天文台日出日落 CSV、Kenney Isometric Roads）也評一次。那頁的軟體元件與 AI 素材只說明為什麼不適用（第 5 節）。

> **怎麼做出來的**
> - 讀 repo 既有研究：`DATA_PRIORITY_2026-11-13.md`（香港 24 項與 WorldCover 香港樣本）、`PEAKLINE_MAP_ENGINE_STUDY.md` §5（WorldCover 集集樣本）、`NLSC_OPEN_DATA_2026-11-13.md` §7.2（國土利用統計）、`WINTER_EVENT_2026-11-15.md`（極夜）、`tools/hk-map/README.md`、`tools/rovaniemi-map/README.md`、`Map3DCamera.swift` 的光線。已經量過的不重量，只引用。
> - 授權：2026-11-16 讀官方條款頁或官方目錄（每列附網址）。**VERIFIED** 只指「條款頁這樣寫」；沒有下載新樣本，沒有接進遊戲，沒看過畫面（**UNVERIFIED**）。
> - 這不是法律意見；進 App 前，負責那張單的 session 再讀一次當時版本的條款，存下版本與日期。

## 0. 結論先講

| 名次 | 項目 | 加權分 | 建議 |
| --: | --- | --: | --- |
| 1 | **日出日落照緯度與日期算**（天文公式，自己寫；香港天文台的表只拿來對答案、不打包） | **3.40** | 併進冬季活動的 I（極夜光線），那張單就做 |
| 2 | **香港規劃署「土地利用網格」10 m**（DATA.GOV.HK，每年一版，最新 2024） | **3.25** | 和漁護署生境圖（DATA_PRIORITY ⑧）合成一張「香港地面顏色」：生境圖管山上的植被，土地利用網格管市區與農地 |
| 3 | **ESA WorldCover 10 m 2021 v200**（CC BY 4.0） | **3.10** | 維持既有結論：只補台灣郊外的遠景地面顏色與自動種樹的範圍；香港不用；羅瓦涅米當備援 |
| 4 | **芬蘭 Maastotietokanta**（芬蘭國土測量局，CC BY 4.0） | **2.70** | 羅瓦涅米的森林、沼澤、農田、湖岸用它，比 WorldCover 準；等 ROVANIEMI-MAP-2 之後的雪景那張一起做 |
| 5 | 地政總署 DTM 5 m | — | **已經在用**（決策 726，`tools/hk-map/`），不用再評 |
| 6 | Meta/WRI 1 m 樹冠高度（CC BY 4.0） | 2.00 | 暫緩：資料大、樹高對這個畫風幫助小 |
| 7 | 台灣國土利用調查 | 1.80 | 圖不能用（要申請、不准轉交）；統計表維持「驗收尺」的用法 |
| 8 | Kenney Isometric Roads（CC0） | 1.25 | 不用：2D 斜角貼圖，遊戲的路是 3D 自己畫的 |
| — | 那份授權頁的軟體元件（Electron、Phaser、Express、sharp 等）、Suno 音樂、Unsplash 材質 | — | 不適用（第 5 節） |

順序照 CLAUDE.md：沒有 bug 類，全是功能／資料，照加權分。前三名都不動 GameCore，可以和 GameCore 單同時跑。

## 1. 評分方法

權重照 `NEXT_PRIORITIES_2026-10-12.md` §19：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15。開發分是「好做、風險小」給高分（授權乾淨、已有工具或參考庫的程式可接、包不會太大）。

| 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --- | --: | --: | --: | --: | --: | --: |
| 日出日落照緯度算 | 3 | 4 | 4 | 4 | 2 | 3.40 |
| 香港土地利用網格 | 3 | 4 | 4 | 4 | 1 | 3.25 |
| ESA WorldCover | 3 | 4 | 4 | 3 | 1 | 3.10 |
| 芬蘭 Maastotietokanta | 2 | 3 | 4 | 4 | 1 | 2.70 |
| Meta/WRI 樹冠高度 | 2 | 2 | 3 | 2 | 1 | 2.00 |
| 台灣國土利用調查 | 1 | 3 | 1 | 3 | 1 | 1.80 |
| Kenney Isometric Roads | 1 | 2 | 1 | 1 | 1 | 1.25 |

## 2. 地面與植被

### 2.1 香港規劃署「土地利用網格」（Raster Grids on Land Utilization）：**拿，第 2 名**

| | |
| --- | --- |
| 入口 | DATA.GOV.HK `hk-pland-pland1-land-utilization-in-hong-kong-raster-grid`；2018 版也在 CSDI（`pland_rcd_1634281791890_21963`） |
| 內容 | 全港 GeoTIFF，10 m 一格，每格一個土地用途類別（住宅、商業、工業、機構、休憩、道路、鐵路、農地、林地、灌叢、草地、水體等；類別定義各年略有調整，不同年份不能直接比） |
| 年份 | 2018–2024 每年一版；2024 版 2025-10-24 更新 |
| 授權 | DATA.GOV.HK 條款：商業與非商業都可以免費下載、重製、散布，條件是清楚標示來源，並署名香港特別行政區政府、規劃署與 DATA.GOV.HK；不得轉售資料本身；有免責與賠償條款（作者在 HK_MAP 已接受同一條） |
| 署名 | 沒有固定字句。建議：「土地用途：香港特別行政區政府規劃署，經 DATA.GOV.HK 提供」／“Land use: Planning Department, HKSAR Government, via DATA.GOV.HK” |

- **五方**：玩家 3（香港地面分出住宅區、工業區、農地、山林，比現在只有 OSM 畫到的綠地完整）；開發 4（已經是 10 m 網格，不像生境圖要先把 70 萬個多邊形燒成格子；`tools/hk-map/` 已有讀 EPSG:2326 GeoTIFF 的 DTM 流程可照抄）；美術 4（色票直接對到既有 `Map3DPalette` 的地面色，不用新色）；鐵道迷 4（官方、每年更新，比 2021 年的衛星分類新，鐵路用地是一類）；音樂 1（無關）。
- **和生境圖的分工**：漁護署生境圖（DATA_PRIORITY §3.5）在山上分得更細（樹林、木本灌叢、灌叢、灌草叢、草地），但「其他市區」一類就占 17.5%，市區分不出用途；土地利用網格正好相反。建議同一張單：市區與農地看土地利用網格，植被看生境圖，衝突時植被以生境圖為準。
- **只做外觀**：和 WorldCover 的規矩一樣，不寫進 GameCore 的分區、不改人口與就業、不走會填 `taken` 的舊 `addArea(.wood)`。
- **UNVERIFIED**：這次沒下載 2024 版；類別表、檔案大小、全港格子數要那張單下載後再量。

### 2.2 ESA WorldCover 10 m 2021 v200：**有條件拿，第 3 名**

| | |
| --- | --- |
| 入口 | `esa-worldcover.org/en/data-access`；zenodo 7254221；S3 `esa-worldcover/v200/2021/map/` |
| 內容 | 全球 10 m、11 類（樹、灌叢、草地、農地、建成區、裸地、雪冰、水、草本濕地、紅樹林、苔蘚地衣），2021 年 |
| 授權 | CC BY 4.0：可商用、可修改、可散布 |
| 署名 | 「© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium」，附 CC BY 4.0 連結並註明有修改（裁切、重採樣、換色） |

- 已經量過：集集樣本補得出約 12.6 km² 的未分類林地與草地（PEAKLINE §5）；香港的灌叢在它裡面全併進「樹」，所以香港不用（DATA_PRIORITY §3.6）。參考庫 `Railway/taiwan-rail-reference-clean/source/scripts/build_worldcover.py` 有現成產生器與 918 塊成品（約 23 MB），可直接移植。
- **用途**：①台灣郊外的遠景地面顏色（補 OSM 沒畫的農田與林地；`NLSC_OPEN_DATA` §7.2 量到遊戲的農地只有官方的 38%）；②自動種樹的範圍（樹用 Blender 腳本做好的那幾種，照 WorldCover「樹」的格子撒，避開道路、軌道、建物、水域與遊戲分區）；③OSM 少的海外地圖當備援。
- **限制**：2021 年的分類，新開發區會過時；農地與果園會互相錯分；10 m 一格在近景會看到格子，所以只用在遠景或當撒樹的遮罩，市區仍以 OSM 為主（作者 11-16 已提到）。
- **包的大小**：台灣全島的成品約 23 MB，要放進分包下載（`MapPackDownloader`），不進 App 本體。
- **五方**：玩家 3、開發 4（產生器現成）、美術 4、鐵道迷 3（全球衛星分類，不如官方圖）、音樂 1。

### 2.3 芬蘭 Maastotietokanta（Topographic Database）：**拿，第 4 名，只給羅瓦涅米**

| | |
| --- | --- |
| 入口 | 芬蘭國土測量局（Maanmittauslaitos）開放資料，產品頁見文末來源 |
| 內容 | 1:5,000–1:10,000 精度的向量：森林、沼澤、農田、湖泊與河流、道路、鐵路、建物、高壓線等；持續更新 |
| 授權 | 國土測量局開放資料一律 CC BY 4.0（2015-01-16 起） |
| 署名 | 「Contains data from the National Land Survey of Finland Topographic Database 11/2026」（資料集名稱與取得年月） |

- 羅瓦涅米地圖包（ROVANIEMI-MAP-1、2）現在的地面來自 OSM 與 Copernicus GLO-30。芬蘭北部的 OSM 有不少就是從這份匯入的，但沼澤與林地邊界不齊；這份是官方原圖，**沼澤**（WorldCover 只有「草本濕地」）在拉普蘭的雪景特別顯眼。
- 同一個機構還有 **2 m 數值地形**（Korkeusmalli 2 m，也是 CC BY 4.0），比現在的 GLO-30 細得多，河谷與凱米河岸會更像；值得在同一張單一起看。
- **注意**：CC BY 4.0 和 OSM 的 ODbL 不相容，只能各自當遊戲的一層，不能把它寫回 OSM，也不能在工具裡混成一份再標成 OSM。
- **五方**：玩家 2（只有羅瓦涅米一張地圖）、開發 3（新來源、要新的讀取，GeoPackage 或 GML；EPSG:3067 投影）、美術 4（雪地、沼澤、針葉林分得開）、鐵道迷 4（官方資料）、音樂 1。

### 2.4 Meta／WRI 1 m 樹冠高度：**暫緩**

- 入口：AWS Open Data `dataforgood-fb-forests`（v1，2024）與 v2（CHMv2）；授權 CC BY 4.0。署名要附 Meta 與 WRI，以及影像來源「Source imagery for CHM © 2016 Maxar」（v1 的引用範本）。v2 的授權欄位這次只在第三方轉存頁看到，用之前要在官方頁再確認。
- 能給每一棵樹（大約）多高，但遊戲的樹是幾種固定的 Blender 腳本模型，按顏色平塗，高度差在遊戲鏡頭下幾乎看不出來；1 m 一格的全台檔案是好幾 GB 級，處理成本高。
- 若之後做「近地面視角」或森林鐵道（阿里山）的近景，再拿來決定山坡上大樹小樹的比例。
- **五方**：玩家 2、開發 2、美術 3、鐵道迷 2、音樂 1。

### 2.5 台灣國土利用調查：**圖不用；統計維持驗收尺**

- 開放的只有統計表（鄉鎮市區 3 級，data.gov.tw 178038 等），政府資料開放授權條款第 1 版，可商用。沒有位置，補不了地圖（NLSC_OPEN_DATA §7.2 已量）。
- 成果圖（向量）要向國土測繪中心申請，條件寫明「不得自行重製或交付於使用目的外之第三方使用」，打包進 App 等於轉交給每個玩家，**不能用**。國土測繪圖資服務雲的 WMS 也只是瀏覽服務，不能抓下來包。
- 用法維持：等 WorldCover 那張單做完，拿統計表量「換完之後每個縣市的農地、工業、公園面積接近官方的幾成」。
- **五方**：玩家 1、開發 3、美術 1、鐵道迷 3、音樂 1。

## 3. 地形：地政總署 DTM 5 m

已經在用：`tools/hk-map/` 第 8 步讀 CSDI 的 `Digital Terrain Model.tif`（5 m、EPSG:2326），產生香港地圖包的 `heights.dat`、`water.json`、`terrain.pmtiles`（決策 726）。來源與條款寫在 `tools/hk-map/README.md` 與資料來源頁。那份授權頁的做法（重新取樣成 20 m、高度分 9 級）是 2D 斜角遊戲的需要；本遊戲照自己的 64 m 角點高度（決策 124），不用跟。

## 4. 晝夜：日出日落

### 4.1 現況

`Map3DCamera.swift` 的光線把太陽固定在 06:00 升、18:00 落（`dayShare = (hour - 6) / 12`），各地各季都一樣。台灣冬夏差一個多小時還說得過去；羅瓦涅米 12 月中午前後只露一下（極夜邊緣），WINTER_EVENT §4.1 第 3 點已經排了「照緯度與日期算」（I，3.30）。

### 4.2 香港天文台的表：**不打包**

- 那份授權頁用的是香港天文台經 DATA.GOV.HK 提供的 2026 年日出、日中天、日落、月出月落 CSV。
- DATA.GOV.HK 條款本身允許商用，但天文台自己的條款（`hko.gov.hk/textonly/readme.htm`）寫：天文台資料的商業用途「strictly prohibited unless all the conditions provided in the Commercial Conditions are complied with and prior written authorisation is obtained from the Hong Kong Observatory」。兩份都沒說誰優先；安全的讀法是**商業遊戲要先拿天文台書面授權**。這是那份授權頁沒處理到的一點。
- 而且只有香港、只有一年，羅瓦涅米與台灣都用不到。

### 4.3 建議：**自己用天文公式算，第 1 名**

- 太陽位置是公開的天文算法（例如 NOAA Solar Calculator 的公式，美國政府作品；或 Meeus《Astronomical Algorithms》的近似式，照書自己寫）。自己寫一個「給緯度、經度、日期，回日出、日落、太陽高度角」的函式放在 GamePresentation（外觀，不進 GameCore），Linux 測試可測。
- **對答案**：用中央氣象署（台灣）與香港天文台公開網頁上的幾個日期當測試期望值（只寫幾個時刻當常數、註明出處，不打包整份表）；誤差在一兩分鐘內即可。手抄幾個事實時刻不構成重製資料庫；若要更保險，改用 NOAA 計算器的值當期望值。
- 月出月落、月相也能用同一套公式算，給夜景的月亮用，不需要天文台的表。
- **五方**：玩家 3（黃昏時刻跟著季節變，羅瓦涅米有真的極夜）；開發 4（純函式、無資料檔、無授權負擔，接到現有 `sunDirection` 一處）；美術 4（夕陽角度、陰影長度跟著季節）；鐵道迷 4（頭班車摸黑、末班車天亮這類真實感）；音樂 2（環境音的晝夜切換跟著真的日落，例如蟲鳴、夜間廣播）。

## 5. 那份授權頁裡不適用的部分

- **軟體元件**：Electron、electron-updater、electron-builder、Express、Phaser、sharp 都是網頁／桌面版的執行環境或建置工具。本遊戲是原生 Swift（SwiftUI、Metal），不用任何一個，不適用。只有一點可借：那頁把「npm 盤點不包含 Electron 內部元件」講清楚的寫法，和本 repo `DataSourceCredits` 已在做的逐項署名一致，不必另改。
- **Kenney Isometric Roads**（CC0）：2D 斜角道路貼圖。本遊戲的路是 3D 自己畫（3D 路面與路面標線），畫風照 art-style；不用。Kenney 的 3D 套件（Nature Kit、City Kit Industrial）已在用（資料來源頁有）。
- **Unsplash 材質、OpenAI 產生的模型、Suno 音樂、自錄音效**：都是那個遊戲自己的素材問題。本遊戲的模型由本地工作室與 Blender 腳本做，平塗色票不用照片材質；不用 Suno。可借的提醒只有一條：AI 產生的音樂或圖，商用權看產生當時的方案與條款，不能事後假設，本遊戲日後若用，照同樣規矩逐項記錄。

## 6. 進 App 時的署名（給之後的單）

拿進遊戲的那張單，在 `DataSourceCredits` 加一列，資料來源頁兩種語言都寫：

| 來源 | 中文 | English |
| --- | --- | --- |
| 香港土地利用網格 | 土地用途：香港特別行政區政府規劃署，經 DATA.GOV.HK 提供 | Land use: Planning Department, HKSAR Government, via DATA.GOV.HK |
| ESA WorldCover | © ESA WorldCover project 2021／含經修改的 Copernicus Sentinel 資料（2021），由 ESA WorldCover consortium 處理；CC BY 4.0 | © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; CC BY 4.0 |
| 芬蘭 Maastotietokanta | 含芬蘭國土測量局地形資料庫（年月）；CC BY 4.0 | Contains data from the National Land Survey of Finland Topographic Database (MM/YYYY); CC BY 4.0 |
| Meta／WRI（若用） | 樹冠高度：Meta、World Resources Institute；影像 © 2016 Maxar；CC BY 4.0 | Canopy height: Meta and World Resources Institute; source imagery © 2016 Maxar; CC BY 4.0 |

## 7. 下一步（排進優先清單時照這裡的分數）

1. **I 極夜光線**那張單（WINTER_EVENT §4.1 第 3 點）改成「日出日落照緯度與日期算」的通用版：台灣、香港、羅瓦涅米都用，3.40。
2. **HK-GROUND-COLOUR**：香港地面顏色，土地利用網格＋生境圖，取代 DATA_PRIORITY 的 ⑧ 單用生境圖的做法，3.25。
3. **TW-WORLDCOVER**：台灣郊外遠景地面顏色＋自動種樹範圍，移植參考庫產生器，進分包下載，用國土利用統計驗收，3.10。
4. **ROVANIEMI-GROUND**：芬蘭地形資料庫＋2 m 地形，接在 ROVANIEMI-SNOW 前後，2.70。
5. Meta/WRI 樹冠高度、國土利用成果圖、Kenney Isometric Roads：不排。

## 來源

- DATA.GOV.HK 條款：https://data.gov.hk/en/terms-and-conditions
- 規劃署土地利用網格：https://data.gov.hk/en-data/dataset/hk-pland-pland1-land-utilization-in-hong-kong-raster-grid ；CSDI 2018 版：https://portal.csdi.gov.hk/csdi-webpage/dataset/pland_rcd_1634281791890_21963
- 香港天文台條款：https://www.hko.gov.hk/textonly/readme.htm ；商業條件：https://www.hko.gov.hk/en/appweb/commercial.htm
- ESA WorldCover：https://esa-worldcover.org/en/data-access ；https://doi.org/10.5281/zenodo.7254221
- 芬蘭國土測量局開放資料授權：https://www.maanmittauslaitos.fi/en/node/10329 （地形資料庫）；INSPIRE 目錄的授權欄位（CC BY 4.0）：https://inspire-geoportal.ec.europa.eu/srv/api/records/a7889960-2d49-4129-bc6a-7f871710425e
- Meta／WRI 樹冠高度：https://registry.opendata.aws/dataforgood-fb-forests/
- 國土利用調查統計：https://data.gov.tw/dataset/178038
- Kenney Isometric Roads：https://kenney.nl/assets/isometric-roads
- CC BY 4.0：https://creativecommons.org/licenses/by/4.0/
