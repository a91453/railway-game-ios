# 附錄 D／E：全部來源與補充聲明

查核日：2026-10-19 UTC。原圖26列逐項保留；D01三種發行形式仍只算一列，D26與E01交叉引用同一上游。

下表每個「查得入口」本次HTTP 200，僅表示可讀官方目錄；不是下載資料或完成可用性驗證。原入口為待查的列仍保留原狀態，另列本次解析網址。資料批次未下載者，年份、schema、CRS、有效欄位及實際條款仍待選批次再驗；不能由目錄直接推定素材已可散布。HTTP結果／頁面SHA見[sources.json](sources.json)，完整機讀表見[sources.csv](sources.csv)。

D01–D21均為香港來源，沒有拿它們補臺灣原地地物。香港實景、虛構生成城市的素材再利用是兩種用途；後者不因地理涵蓋範圍而被一概禁止，但仍需個別版本條款、美術加工與署名。

| ID／原名／提供者 | 原始入口 | 本次查得官方入口 | 型態／地理範圍 | 《沿線》現有能力 | 結論／證據與待查 |
| --- | --- | --- | --- | --- | --- |
| D01 3D Visualisation Map；Lands Department | https://www.landsd.gov.hk/en/survey-mapping/mapping/3d-mapping.html | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-landsd-openmap-3d-visualisation-map-individualised-models) | 單體貼圖模型／無貼圖模型／航空影像整片 mesh 分型；香港全境 | 已有量體與模型讀取器；缺資料規格正規化 | 有條件；香港實景可補真實外形；生成城市可精選重組，不能提供臺灣原地建物。官方確認 MAX/FBX/GLTF；選2.4 MB圖幅下載403，未取得模型、版本與包內條款；補充#820 cf05be2取得11-NW-10B GLTF0及貼圖Range樣本，三件烘色暴露塗裝誤判；本環境未獨立重現，詳主報告§3 |
| D02 3D Spatial Data (3D-BIT00)；Lands Department | https://portal.csdi.gov.hk/csdi-webpage/dataset/landsd_rcd_1637306559892_42396 | [官方資料頁](https://portal.csdi.gov.hk/csdi-webpage/dataset/landsd_rcd_1637306559892_42396) | 建物／基礎設施／TIN地形；L1量體、地標L2/L3；香港全境 | 已有輪廓擠出與DEM；不是缺一個引擎 | 香港實景有條件；L1較接近現有路徑，L2/L3精選候選。官方頁確認 L1不貼寫實照片、L2/L3貼圖；未下載批次，費用依CSDI與HKMS路徑分查 |
| D03 Buildings；Lands Department | https://data.gov.hk/en-data/dataset/hk-landsd-openmap-landsd-building | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-landsd-openmap-landsd-building) | 建物輪廓與名稱／類型／高度屬性；香港 | 已有CityTile輪廓＋高度＋遊戲材質 | 香港實景量體的最低成本候選；不當完整帶貼圖模型。官方標題Building；未取得schema與高度樣本，不宣稱每棟都有有效高度 |
| D04 Digital Topographic Map iB1000；Lands Department | https://www.hkmapmeta.gov.hk/mcs/home/web/data/lands/iB1000.html | [官方資料頁](https://www.hkmapmeta.gov.hk/mcs/home/web/data/lands/iB1000.html) | 詳細向量地形底圖；批次格式待查；香港 | 已有OSM向量底圖 | 無香港計畫則暫緩；可補詳細地物但需schema對照。官方metadata入口查核；未下載批次／條款包 |
| D05 Digital Topographic Map iB5000；Lands Department | https://www.hkmapmeta.gov.hk/mcs/home/web/data/lands/iB5000.html | [官方資料頁](https://www.hkmapmeta.gov.hk/mcs/home/web/data/lands/iB5000.html) | 概化向量地形底圖；批次格式待查；香港 | 已有向量圖磚與zoom簡化 | 暫緩；僅香港底圖方案有條件。官方metadata入口查核；不概括成免費素材包 |
| D06 Pavement Polygon；Highways Department | https://portal.csdi.gov.hk/csdi-webpage/dataset/hyd_rcd_1632210918434_60749 | [官方資料頁](https://portal.csdi.gov.hk/csdi-webpage/dataset/hyd_rcd_1632210918434_60749) | 路面polygon／分類屬性；香港路政署維護範圍 | 已有依道路級別推估路面／遊戲材質 | 有香港街景才值得；可改善實際路幅，不是3D材質包。官方資料頁；未量道路高程、交叉層級及缺漏 |
| D07 Lamp Post Location Data；Highways Department | https://data.gov.hk/en-data/dataset/hk-hyd-plis-lamppostdata | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-hyd-plis-lamppostdata) | 路燈點位／設施屬性；香港 | 已有程序路燈模型與擺放 | 暫緩；香港場景可改用位置，仍須自己的3D模型。官方資料頁；未下載版本 |
| D08 Barrier Fence；Highways Department | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-hyd-csdi-barrier-fence) | 防護欄中心線／設施屬性；香港路政署範圍 | 可沿線實例擺放；尚無此資料接線 | 暫緩；香港街道候選，非現成欄杆模型。已解析資料頁與CSDI hyd_rcd_1632210391486_52565；schema/版本未驗 |
| D09 Tree；Highways Department | https://data.gov.hk/en-data/dataset/hk-hyd-csdi-tree-hyd | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-hyd-csdi-tree-hyd) | 個別樹木點位與屬性；香港路政署範圍 | 已有程序樹與實例 | 暫緩；香港實景可取代推估點位。官方標題Tree (HyD)；不提供樹木3D mesh；未下載schema |
| D10 Trees (Major Parks)；Leisure and Cultural Services Department | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-lcsd-csdi-tree-information-major-parks) | 主要公園樹木點位／屬性（schema未驗）；香港主要公園 | 已有樹木實例 | 暫緩；地理覆蓋限特定公園。已解析CSDI lcsd_rcd_1730101435734_98947；未下載版本 |
| D11 Trees (LCSD Venues other than Major Parks)；Leisure and Cultural Services Department | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://portal.csdi.gov.hk/csdi-webpage/dataset/lcsd_rcd_1760154188966_59086) | 其他康文署場地樹木點位／屬性（schema未驗）；香港指定場地 | 已有樹木實例 | 暫緩；不能當全港樹木普查。CSDI官方DatasetListJSON核對名稱Trees (LCSD Venues (other than Major Parks))；版本未下載 |
| D12 Trees on Registered Man-made Slopes Maintained by ArchSD；Architectural Services Department | https://portal.csdi.gov.hk/csdi-webpage/dataset/archsd_rcd_1629267205233_1276 | [官方資料頁](https://portal.csdi.gov.hk/csdi-webpage/dataset/archsd_rcd_1629267205233_1276) | 指定人造斜坡樹木位置／屬性；香港建築署維護斜坡 | 已有樹木／DEM地形 | 暫緩；只改善指定香港場景。官方資料頁；管理範圍不等於全境森林；未下載版本 |
| D13 Vegetation；Highways Department | https://data.gov.hk/en-data/dataset/hk-hyd-csdi-vegetation | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-hyd-csdi-vegetation) | 植被區域幾何／覆蓋屬性；香港路政署範圍 | 已有OSM landcover與植被實例 | 暫緩；香港小範圍補漏；不是全域地表分類。官方資料頁；下載schema/更新日期未驗 |
| D14 Registered Man-made Slopes；Civil Engineering and Development Department | https://portal.csdi.gov.hk/csdi-webpage/dataset/cedd_rcd_1636517655915_91216 | [官方資料頁](https://portal.csdi.gov.hk/csdi-webpage/dataset/cedd_rcd_1636517655915_91216) | 登記人造斜坡幾何／管理屬性；香港 | 已有DEM衍生陡坡規則 | 暫緩；不以香港管理清冊覆寫臺灣坡度或建造規則。官方資料頁；非全球DEM，未驗圖形精度 |
| D15 Grass-cutting Sites under LandsD's Grass-cutting Programme；Lands Department | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-landsd-openmap-grass-cutting-sites-under-landsd-grass-cutting-programme) | 除草管理地點（官方列GML/GeoJSON）；香港地政總署除草計畫範圍 | 已有草地外觀 | 暫緩；管理清冊不等於實際草地全面覆蓋。已解析CSDI landsd_rcd_1637226571051_261；未下載版本 |
| D16 Road Network；Transport Department | https://data.gov.hk/en-data/dataset/hk-td-tis_6-road-network | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-td-tis_6-road-network) | 道路線網／連通性／屬性；香港 | 已有OSM道路與遊戲鐵路圖 | 暫緩；香港路網可用；另查層級與高架，不換成第二代資料。保留原Road Network資料頁；未下載版本，不宣稱與2nd Generation相同 |
| D17 Traffic Aids Drawings；Transport Department | 精確官方資料集／原文網址原先待查；相關入口 https://www.td.gov.hk/en/public_services/intelligent_road_network_package/ | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-td-tis_8-traffic-aids-drawings) | 標誌／標線／號誌等圖則與向量位置；香港 | 已有部分程序道具與道路 | 暫緩；可做擺放資料，仍須3D資產與交通語意。已解析原世代資料頁；第二代另列hk-td-tis_16-traffic-aids-drawings-v2，未混用 |
| D18 Terrestrial Habitat Map of Hong Kong 2021；Agriculture, Fisheries and Conservation Department | https://bih.gov.hk/en/feature-studies/index-id-7.html | [官方資料頁](https://bih.gov.hk/en/feature-studies/index-id-7.html) | 2021生境分類圖；資料目錄年份另查；香港 | 已有OSM覆蓋；無生態分類接線 | 暫緩；香港場景可比WorldCover更細分生境。保留2021原名稱；CSDI afcd_rcd_1639382960762_55768不可未核年份直接替換；未取得2021批次 |
| D19 Digital Orthophoto DOP5000；Lands Department | https://www.landsd.gov.hk/en/survey-mapping/mapping/aerial-photo-photogrammetric-products/digital-orthophoto.html/1000 | [官方資料頁](https://www.landsd.gov.hk/en/survey-mapping/mapping/aerial-photo-photogrammetric-products/digital-orthophoto.html) | 正射影像／地表顏色取樣；香港；實際航攝年份依批次 | 已有遊戲調色盤與淡灰材質 | 暫緩；可離線測色；航照不是單棟模型且寫實貼圖不合現行風格。原入口含/1000仍保留；官方總頁另核DOP5000產品，未下載版本或核費用 |
| D20 Hours of reduced visibility at Hong Kong International Airport；Hong Kong Observatory | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-hko-rss-daily-number-of-hours-of-reduced-visibility) | 歷年每日低能見度時數／CSV時間序列；香港機場測站 | 已有日夜天氣與霧 | 低優先暫緩；不是全港煙霞體積場。已找到HKIA All Year resource fb27581a-9ed4-4d92-969d-13f24b363bdb；未核原圖實際期間 |
| D21 Hiking Trails；Agriculture, Fisheries and Conservation Department | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://data.gov.hk/en-data/dataset/hk-afcd-afcdlist-hikingtrailscp) | 郊野公園遠足徑線／路線資料；香港郊野公園 | 已有路徑／鐵路地圖；非健行遊戲需求 | 暫緩；僅香港步道／觀光示範用途。已解析CSDI afcd_rcd_1665568199103_4360；Lion Rock Historic Walk精確原路線仍未核對 |
| D22 OpenStreetMap；OpenStreetMap contributors | https://www.openstreetmap.org/copyright | [官方資料頁](https://www.openstreetmap.org/copyright) | 全球向量資料庫；surface/steps標籤；全球，地方完整度不一 | 已用臺灣PMTiles、水域、分區、OSM/Overture足跡 | 繼續既有路徑；海外用OpenFreeMap；步道屬性有需求才補。ODbL；原圖另列https://chungtau.github.io/peakline-site/osm，本研究不以其資料庫代替OSM提供者 |
| D23 ESA WorldCover project 2021；ESA WorldCover consortium | https://esa-worldcover.org/en/data-access | [官方資料頁](https://esa-worldcover.org/en/data-access) | 2021 v200全球約10m／11類uint8柵格COG；全球 | 目前底圖工具未接入；曾有相關研究；參考庫指定SHA已有918塊z6–11／22,967,839B的WorldCover成品與產生器，主repo未接入，詳主報告§5 | 有條件採用；只補視覺缺漏或遠景；不改水域、農地工作、建造權威。已取得N21E120 2021 v200；集集720×720比較見主報告；CC BY4.0 |
| D24 Bright Star Catalogue, 5th revised edition；D. Hoffleit and W. H. Warren Jr. (1991), through CDS | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://cdsarc.cds.unistra.fr/viz-bin/cat/V/50) | V/50恆星表（9110筆）；天球位置／亮度；天空資料，非地面地圖 | 已有藝術化天空與日夜 | 低優先暫緩；無精確星空產品需求。已解析官方目錄；1991 Preliminary Version；頁面未給清楚再散布授權，採用前仍需查條款 |
| D25 Approximate Positions of the Planets；E. M. Standish and J. G. Williams (1992), via JPL Solar System Dynamics | 精確官方資料集／原文網址原先待查 | [官方資料頁](https://ssd.jpl.nasa.gov/planets/approx_pos.html) | 行星軌道要素／近似演算法；太陽系天空位置，有限有效年代 | 已有日夜，不需星曆 | 低優先暫緩；需時間與觀測位置模型才畫天空。已解析官方公式與適用時間；原1992引文對應版本及再散布條款未完成 |
| D26 meshoptimizer；Arseny Kapoulkine | https://github.com/zeux/meshoptimizer | [官方資料頁](https://github.com/zeux/meshoptimizer) | 幾何編解碼／最佳化工具；Peakline只聲明解碼；軟體，非地理資料 | 普通GLB轉檔器；已授權tools-only接線 | 優先試作離線靜態模型正規化；不重寫Rust解碼器。對應E01，同一上游不重複計數；本次1.3.0解碼與減面樣本通過，MIT |

## D01子型別與補充入口（不增計）

- 單體化模型：[DATA.GOV.HK](https://data.gov.hk/en-data/dataset/hk-landsd-openmap-3d-visualisation-map-individualised-models)、[CSDI](https://portal.csdi.gov.hk/csdi-webpage/dataset/landsd_rcd_1671676915450_88604)。
- 無貼圖模型：[DATA.GOV.HK](https://data.gov.hk/en-data/dataset/hk-landsd-openmap-3d-visualisation-map-non-textured-models)、[CSDI](https://portal.csdi.gov.hk/csdi-webpage/dataset/landsd_rcd_1742809441342_98380)。
- 整片航空攝影mesh：[CSDI](https://portal.csdi.gov.hk/csdi-webpage/dataset/landsd_rcd_1671677054006_62261)。
- [下載API文件](https://3d.map.gov.hk/mapviewer/app/download-api?l=en-US)、[單體模型大小清單](https://3d.map.gov.hk/mapviewer/app/grid/INDIVIDUAL_MODELS_DATA_SIZE.csv)、[圖幅索引](https://3d.map.gov.hk/mapviewer/app/grid/GRID_WGS84_B1K_INDEX_INDIVIDUAL_WHOLEHK.geojson)。
- D08、D10、D11、D15等名稱與provider另以[CSDI官方全目錄JSON](https://portal.csdi.gov.hk/csdi-webpage/DatasetListJSON)交叉核對。
- D18原文另列[CSDI生境目錄](https://portal.csdi.gov.hk/csdi-webpage/dataset/afcd_rcd_1639382960762_55768)，其下載年份未核，不取代原2021識別。
- D22原圖另列資料庫：https://chungtau.github.io/peakline-site/osm；來源聲明為Open Database Licence。未下載該資料庫，本次比較使用App既有OSM。
- D23原致謝保留：© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium. CC BY 4.0.
- D24原引文：The stars: the Bright Star Catalogue, 5th revised edition (D. Hoffleit and W. H. Warren Jr., 1991), through CDS.
- D25原引文：The planets: E. M. Standish and J. G. Williams (1992), "Approximate Positions of the Planets", via JPL Solar System Dynamics.
- D26原致謝：meshoptimizer © 2016–2025 Arseny Kapoulkine, under the MIT licence. 這是原圖文字，不以本次1.3.0授權檔年份覆寫。

## 附錄 E

| ID | 原聲明／版本 | 本次判斷與證據 |
| --- | --- | --- |
| E01（D26） | meshoptimizer's decoders, ported to Rust in the engine (index codec 0 and 1, vertex codec 0)；MIT；https://github.com/zeux/meshoptimizer；**未標套件版本** | 只是特定解碼器相容性聲明。用官方meshoptimizer 1.3.0在Linux解開所選623個buffer（index e1、vertex a0），另驗新編碼器a0/a1都能被本次解碼器讀。未取得Peakline Rust移植原始碼，不能替它驗證filters、整檔、減面或LOD；codec編號不當版本。 |
| E02 | uniffi and its parts are under the Mozilla Public License 2.0, unchanged; their source is at https://github.com/mozilla/uniffi-rs. | 對應C120–C127共8列，非新增套件。0.32.2的8個crate metadata／Cargo.toml宣告MPL-2.0，本次包中沒找到獨立LICENSE檔；另讀官方tag LICENSE與Mozilla FAQ。未修改仍須依散布型態告知／提供受涵蓋原始碼取得方法。C129 weedle2包內是MIT。 |
| E03 | 使用者提供的Jonas Schievink ISC形式文字（下列保留） | 尚未可靠對應特定套件；C053 libloading 0.8.9的包內ISC作者是Simonas Kazlauskas，且其permission含保留告示條件，**不能把Jonas這段指派給C053**。本次只逐包查20項，不宣稱其餘包均無該文字。散布前依實際來源包找正確歸屬。非新套件。 |
| E04 | Apache License Version 2.0, January 2004，第1–9節與附錄；https://www.apache.org/licenses/LICENSE-2.0 | 官方文本是適用元件的授權，不是Peakline引擎／shader／資產的授權。C列的OR/AND/WITH和斜線原樣保留；實際散布依所選授權處理LICENSE、copyright、NOTICE與修改告示。非新增專案。 |

E03原文（使用者提供，未改寫成另一種標準ISC條款）：

```text
Copyright (C) Jonas Schievink <jonasschievink@gmail.com>

Permission to use, copy, modify, and/or distribute this software for
any purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

計數：141筆有版本套件＋25項圖資／天空資料＋1項未標版本軟體＝167。D26/E01一項；E02–E04為補充聲明，不能加成新專案。多個crate共用repo，不把137種套件名稱當137個獨立上游。
