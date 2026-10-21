# 日本的鐵路資料能用在哪：Mini Tokyo 3D、国土地理院、国土数値情報（2026-10-21）

> 作者 2026-10-21 貼了四份來源與一段日文的資料出處（「ひと駅」的署名），問「有哪些可以應用在此專案」。這份是研究，不改程式、不改 NEXT_PRIORITIES 的順序；要不要做、排在哪，由遊戲規劃照 §6 的分數決定。
> 數字是 Linux 上實際下載、解析得到的（VERIFIED，2026-10-21）；App 裡的畫面與效能沒有做（UNVERIFIED）。

## 0. 結論

| 來源 | 授權 | 能用的 | 用在遊戲哪裡 | 建議 |
| --- | --- | --- | --- | --- |
| 国土数値情報 鉄道データ N02（2025 年版） | CC BY 4.0（政府標準利用規約，與 CC BY 4.0 相容） | 全日本 177 家業者、597 條線的線形與 10,234 筆車站 | **日本實景地圖的真實鐵路與車站**（現在只有台灣有，HANDOFF §5） | 做，§4.A |
| 国土地理院 最適化ベクトルタイル（optimal_bvmap） | 国土地理院コンテンツ利用規約（PDL 1.0，與 CC BY 4.0 相容） | 鐵路中心線的「橋・高架／トンネル／地下」、單線／複線 | 日本真實鐵路的橋與隧道，描線時的高度（決策 279 的日本版） | A 之後，§4.B |
| 国土地理院 地名等の多言語表記（experimental_multil） | 同上；**實驗性、沒有公開規格** | 站名、地名的漢字、假名、英文 | 日本車站的英文名、日本新車站的自動命名 | 低，§4.F |
| Mini Tokyo 3D（nagix/mini-tokyo-3d `220adf8`） | **程式** MIT；**`data/` 沒有寫授權**（ODPT 的資料有各自條款） | 時刻表 → 位置的加減速內插、直通運轉的串接、日照、追蹤鏡頭 | 實景地圖「真實列車」（決策 304）的加減速；3D 跟車鏡頭 | 只移植演算法，不拿資料，§4.C、§4.E |
| 「ひと駅」的出處文字 | —（是別人的署名，不是資料） | 證實上面三份能做出 JR 東海、JR 西日本北陸、伊勢鉄道等的路網；日本 JR 沒有開放的時刻表，所以它的行駛與停站時間是模擬的估計值 | 日本的真實列車只能用估計班距（§4.D） | 參考做法 |

作者接著貼了ひと駅的音效、音樂與地圖出處，見 §7：
- **地圖**那一串，遊戲都已經有了，不用改。
- **ポケットサウンド**與 **TAM Music Factory** 禁止散布素材檔本身，這個 repository 是公開的，所以不能放進 App 的資源。
- **CC BY 的錄音**（OtoLogic、Freesound 的兩筆）可以用。

建議不直接打包錄音，改用遊戲自己的合成器，量錄音的頻譜當參考，做跟車時的行駛聲。

一句話：**台灣以外的實景地圖缺真實鐵路**這個洞，日本可以用 N02＋最適化ベクトルタイル補起來，資料都是 CC BY 4.0 相容、可以打包進 App；Mini Tokyo 3D 能用的是程式（MIT），它的東京資料不能拿。

## 1. 起因與範圍

作者貼的內容：
1. Mini Tokyo 3D 的 GitHub（固定在 commit `220adf8e8c4dae8251f4999502757d2cbc25c747`，v4.1.0）與 MIT 授權全文。
2. 国土地理院（GSI）的兩份資料與利用規約（PDL 1.0）：多言語表記的地名圖磚、最適化ベクトルタイル。
3. 国土数値情報 鉄道データ（N02，2025 年版）與 CC BY 4.0 全文。
4. 一段「ひと駅」的出處說明：JR 東海、JR 西日本、伊勢鉄道、IR いしかわ鉄道、ハピラインふくい 的資料從 N02 抽出、加工；駅名與讀音從 GSI 加工；山万 6 站的站名與讀音從 GSI 的多言語圖磚加工；駅順與接續照各公司官方網頁確認；「特急等は代表的な停車パターン、走行・停車時間は独自のシミュレーション推定値」。

遊戲是台灣為主，但從決策 262 起，實景地圖可以在日本 21 個城市開局。所以這份只問一件事：**這些資料與程式能讓遊戲裡哪一塊變得更好**。

## 2. 遊戲現在在日本有什麼、缺什麼

| 項目 | 現況 | 出處 |
| --- | --- | --- |
| 日本開局 | 21 個城市（東京、橫濱、大阪、名古屋、札幌……那霸），點是各城市主要車站的 Wikidata 座標 | 決策 262，`RealWorldStations.swift` |
| 真實鐵路、車站 | **只有台灣**。日本開局時底圖（Apple 地圖或 OpenFreeMap）上看得到鐵路，但遊戲不認得：沒有建議站點（決策 295）、沒有轉乘來源（決策 298）、沒有真實列車（決策 304）、不能照真實鐵路描線（決策 213） | 決策 262「台灣以外能玩到什麼」；HANDOFF §5 |
| 人口、水域、分區 | 只有台灣；台灣以外新車站一律 10,000 人次、住宅區 | 同上 |
| 真實列車 | 台灣的捷運、高鐵照時刻表，台鐵照班距；**站間等速**（參考網站的加速曲線 `buildProfile` 沒有移植） | 決策 304，`RealTrainMotion.swift` |
| 作者參考庫的東京 | `Railway/world-rail-reference-clean/source/data/tokyo.json`：東京都界內 75 條（都營 6、Tokyo Metro 9、JR 東日本 18、私鐵 41…），OSM 線形、官方色、繁中／英／日站名；`tokyo_schedule_dense.json` 40 MB 是**合成班距**（`route_scope.json`：JR 東日本與大手私鐵的 ODPT 時刻是「公共交通オープンデータチャレンジ限定ライセンス」，不能公開使用） | 參考庫 `route_scope.json` 的 `tokyo_sched` |

所以這些來源的用處集中在第二列：**日本的真實鐵路**。

## 3. 各來源的事實

### 3.1 国土数値情報 鉄道データ N02（2025 年版）

- 頁面：https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html（2026 年 4 月更新）。基準日 2025-12-31；JGD2011 經緯度（EPSG:6668，與 WGS-84 的差在遊戲裡可以忽略）。
- 全國一包 `N02-25_GML.zip` 14.2 MB，內含 GML、Shapefile（Shift-JIS 與 UTF-8）與 **GeoJSON**：`N02-25_RailroadSection.geojson`（14.2 MB）、`N02-25_Station.geojson`（3.3 MB）。
- 屬性：
  - 線（RailroadSection）：`N02_001` 鉄道区分、`N02_002` 事業者種別、`N02_003` 路線名、`N02_004` 運営会社。
  - 站（Station）：同上四個，加 `N02_005` 駅名、`N02_005c` 駅コード、`N02_005g` グループコード。
  - `N02_001`：11 普通鉄道 JR、12 普通鉄道、13 鋼索、14 懸垂式、15 跨座式、16 案内軌条式、17 無軌条；21–25 是軌道法的路面電車與單軌。
  - `N02_002`：1 JR 新幹線、2 JR 在來線、3 公營、4 民營、5 第三部門。
- 實測（2025 年版）：線段 21,933 筆、車站 10,234 筆（站碼 10,154 個、群組碼 9,046 個）、業者 177、（業者, 線）597 組、線形總長約 27,750 km。
- 「ひと駅」列的業者都在：東海旅客鉄道 439 站列、西日本旅客鉄道 1,264、伊勢鉄道 10、IR いしかわ鉄道 19、ハピラインふくい 19、山万 6。
- 遊戲的 21 個日本城市：主要車站 12 km 內有 264 條線、2,783 筆車站，壓成 GeoJSON（小數 5 位）約 3.1 MB；45 km 內 431 條、6,116 筆、約 7.8 MB。東京站 8 km 內 413 筆、大阪 266、名古屋 155、札幌 88、那霸 19。
- **要注意的**：
  - 車站是**一段折線**（月台長），不是一個點；同一站每條線一筆。
  - `N02_005c` 是「依緯度排序後編的號」，**每年會變**，不能當永久 id；`N02_005g`（300 m 內同名站的群組）正好是轉乘群組。
  - 沒有：高度、單複線、橋隧、站序、里程、路線色、英文名、班次。貨物線與側線不在裡面。
  - 路線名是《鉄道要覧》的正式名（「東海道線」，不是「東海道本線」），玩家熟的愛稱要另外對照。
- 授權：頁面寫「2020 年以降：オープンデータ（CC_BY_4.0）」；利用規約（https://nlftp.mlit.go.jp/ksj/other/agreement_01.html）允許複製、改作、商用，寫明與 CC BY 4.0 相容。加工後的署名例：「『国土数値情報（鉄道データ）』（国土交通省）（URL）を加工して作成」，且不能讓人以為是國家做的。

### 3.2 国土地理院 最適化ベクトルタイル（optimal_bvmap）

- https://github.com/gsi-cyberjapan/optimal_bvmap ；PMTiles 一個檔：`https://cyberjapandata.gsi.go.jp/xyz/optimal_bvmap-v1/optimal_bvmap-v1.pmtiles`（2026-07-01 版，每季更新）。舊的 `{z}/{x}/{y}.pbf` 停在 2023-10，將停止。z4–16。
- 試驗性的資料，不是基本測量成果；網址與格式可能改。
- 鐵路層 `RailCL`（鉄道中心線）：
  - `vt_railstate`：z14–16 有 通常部／**橋・高架**／**地下**／雪覆い／運休中／その他／不明；z4–10 只有 通常部／トンネル。
  - `vt_sngldbl`：單線／複線以上／側線，z11 起加「駅部分」（車站範圍）。
  - `vt_rtcode`：JR／JR 以外／地下鉄／路面／索道／特殊鉄道／側線（z8–16）；`vt_lvorder` 是上下疊的順序。
  - **線上沒有路線名、業者或站名**；站名與路線名只在註記層 `Anno`（`vt_code` 421 路線名、422 駅名、423 鐵道構造物）。所以要和 N02 用幾何對起來。
- 規格書在 https://maps.gsi.go.jp/help/pdf/vector/（`optbv_dataspec.xlsx`、`optbv_attribute.docx`、`optbv_featurecodes.xlsx`）。repo 的 `style/std.json` 有 GSI 自己畫橋、隧道、車站的篩選條件可以參考。
- 授權：国土地理院コンテンツ利用規約（2025-11-20 版，https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html）套用 PDL 1.0，與 CC BY 4.0 相容；署名「出典：国土地理院最適化ベクトルタイル」，加工的要寫「…を加工して作成」。

### 3.3 国土地理院 地名等の多言語表記（experimental_multil）

- `https://maps.gsi.go.jp/xyz/experimental_multil/{z}/{x}/{y}.geojson`，點的 GeoJSON；z5、9、10、12、15、16 有資料。
- 屬性：`knj` 漢字、`kana` 讀音（站名含「えき」）、`name` 英文（GSI 的英文表記，「Tokyo Sta.」「Toei Asakusa Line」「Tama R.」）、`roma` 羅馬字（部分）、`ftCode`（2930 車站、100 註記…）、`annoCtg`（110 市區町村、210 町丁目、322 河川、421 路線名）。
- **沒有**列在 GSI 的圖磚一覽，沒有公開規格；是 GSI「多言語表記の日本地図」試作背後的資料。沒有站碼、沒有路線與業者，大站有好幾個點，要靠名字與距離對到 N02。
- 授權同 §3.2。圖磚一覽頁說「即時讀取」只要署名；**打包加工過的資料**要確認不是基本測量成果（多言語表記不在一覽，判斷不了，UNVERIFIED）。

### 3.4 Mini Tokyo 3D（`220adf8`，2026-10-05，v4.1.0）

- `LICENSE` 是 MIT，Copyright (c) 2019-2026 Akihiko Kusanagi；沒有 NOTICE 或其他授權檔。MIT 只涵蓋「the Software」。
- **資料不能拿**：`data/`（時刻表 105 MB／179 線／93,143 班、`coordinates.json` 手描線形、`stations.json` 2,610 站…）是作者手動維護、提交在同一個 repo 的，README 與 `docs/user-guide/about-data.md` 說資料來自公共交通オープンデータセンター（ODPT），**沒有寫資料的授權**。ODPT 每份資料各有條款（基本授權、Challenge 限定、部分 CC BY 4.0），作者的參考庫已經查過 JR 東日本與大手私鐵是 Challenge 限定、不能公開使用。所以照 CLAUDE.md「資料保留自己的授權」，不移植。即時資料要 ODPT 的金鑰，也不用。
- 沒有附 3D 模型：列車是一節一個方塊（`CarGeometry(.88, 1.76, .88)`），樹與建物是 Mapbox 的模型。遊戲的原生 3D 已經一節一節沿軌道排（決策 205、229），沒有可以拿的。
- **能移植的程式**（都是決定論的純計算，數字見 §4 的對照表）：
  1. 站間的加減速內插：`map.js` `trainRepeat`（1489–1609 行）與 `src/gpgpu/compute-fragment.glsl`。三角形或梯形速度曲線（最高 80 km/h、加速 3 km/h/s），再把加速度與最高速度解到「時刻表給的時間窗」裡；位置 = 兩站里程之間照曲線的比例內插，再沿折線（每點先算好累積距離、方位、坡度）二分搜尋。
  2. 直通運轉：每條線一份時刻表，用 `pt`（前一段）與 `nt`（下一段）串起來（`data-classes/train-timetable.js` 115–160 行）；多個 `nt` 是分割，多個 `pt` 是併結。
  3. 共用走廊的平行偏移：`src/loader/features.js` `featureWorker`（163–444 行），偏移量 × 0.1 km × 2^(14−zoom)，換邊用 easeInOutQuad，每個縮放層級（13–18）各算一份，拉遠時並行的線不會疊成一條。
  4. 日照：`helpers/helpers-mapbox.js` `setSunlight`（216–360 行），用 suncalc（BSD-2）算日出日落，夜、日出、白天、日落四組環境光與方向光顏色，日出前 30 分到後 60 分、日落前 60 分到後 30 分線性混合。
  5. 追蹤鏡頭：`map.js` `_jumpTo`、`updateTrackingParams`：後方／前方（zoom 18.5、俯角 85°）、上後方／上前方（15、60°）、直升機（每 400 ms 轉 1°）、空拍（17、75°）、鳥（每 30–50 秒隨機換角度，用單調三次插值）。
  6. 服務日從 03:00 開始（`helpers.getTimeOffset`）；週六、週日與假日、12/30–1/3 用不同班表（`clock.js` `getCalendar`）。
  7. 列車資訊卡欄位：車種、往、車次、前一站與時刻、下一站與時刻、晚分（`getTrainDescription`）。

### 3.5 「ひと駅」的出處文字告訴我們的事

- 它是**別人加工後的署名**，不是資料本身；參考庫裡找不到「ひと駅」（`grep` 全庫無結果）。如果它是作者自己的網站，把它的快照照 `world-rail-reference-clean` 的方式放進參考庫，就能直接移植（站序、接續、直通列車的路徑都已經整理好）；目前不是，所以只能從原始的 N02 與 GSI 自己做。
- 它證實了做法可行：N02 抽出業者 → 照官方網頁確認站序與接續 → GSI 補讀音。
- 它也說明了限制：**JR 東海、JR 西日本沒有開放的時刻表**，它的特急是「代表性的停車模式」，行駛與停站時間是「獨自的模擬估計值」，並寫明「不是實際運行或官方時刻表」。遊戲在日本做真實列車時，也只能這樣做，而且要照樣說清楚。

## 4. 能用在哪

### 4.A 日本實景地圖的真實鐵路與車站（N02）

**做什麼**：一支資料工具（例如 `tools/japan-railways/`，Python，讀 N02 的 GeoJSON，不需要 pyosmium），把 21 個日本城市周圍的線與站抽成和台灣 `RealRailways/track_lines.geojson`、`track_stations.geojson` 同樣形狀的檔，App 在日本開局時讀它。這樣決策 295（建議站點）、298（轉乘來源）、213（照真實鐵路描線）、304 的車站卡在日本都有東西可以用。

**資料要補的**（N02 沒有的）：
- 車站：一筆折線取中點當站位；同線同名合一；`N02_005g` 當轉乘群組（和遊戲 450 m 同名合一的規則一致）。
- 站序：照站點投影到線形上的距離排（作者參考庫 `tools/build_tokyo_rail.mjs` 也是這樣排東京的私鐵）。N02 的線是一段一段，要先依端點接成整條。
- 路線色：N02 沒有。各公司公開的路線色要做一張表（東京的 75 條可以直接用參考庫 `tokyo.json` 的 `color`）；表裡沒有的線用業者的代表色。
- 名字：日文站名直接用（漢字大多看得懂）。繁中模式要不要把「駅」以外的新字體換成正體（例如「沢」→「澤」）要定一次規則；英文從 GSI 多言語表記（§4.F）或參考庫 `tokyo.json` 取。

**東京的兩份資料怎麼分**：東京都界內，參考庫的 `tokyo.json`（作者的、OSM 線形、官方色、繁中／英／日站名、支線拆開）比 N02 好，用它；都界外與其他 20 個城市用 N02。這和 GEO_SCENE 研究的結論同一型：哪份準就用哪份，融合而不是換掉。

**大小**：12 km 內約 3.1 MB、45 km 內約 7.8 MB（未壓縮 GeoJSON，§3.1）。App 的 `Resources/RealWorld` 現在 19 MB。建議只抽玩家地圖可能涵蓋的範圍（新遊戲 16 km 見方，可以買到 5 × 5 塊，所以約 45 km），或照 HANDOFF §5 的寫法「一個國家一份資料」、需要時再下載。

**署名**（`DataSourceCredits` 的「地圖」）：
- 日文：「『国土数値情報（鉄道データ）』（国土交通省）https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html を加工して作成」，加 CC BY 4.0 的連結。
- 遊戲的兩種語言照 `DataSourceCredits` 現有的寫法翻成繁中與英文，註明「線形與車站經過加工；路線色是遊戲依各公司公開資料整理」。

**五方**：
- 玩家：日本開局時，地圖上的真實車站可以點、可以接，客人會從真實車站轉來，和台灣一樣好上手。
- 鐵道迷：全日本官方的線形與站，出處是國土交通省；站序與路線色另外核對官方網頁。
- 開發：只動資料工具、GamePresentation 的讀檔與 App 的資源；GameCore、存檔不動（真實鐵路本來就不進存檔）。最大的工作是站序與路線色的表。
- 美術：路線色照官方，不加新圖。
- 音樂：無。

### 4.B 日本真實鐵路的橋與隧道（最適化ベクトルタイル）

**做什麼**：從 `RailCL` 的 z14–16 取 `vt_railstate` 是「橋・高架」「地下」或「トンネル」的段，用幾何對到 4.A 的線（線上沒有路線名），寫成和台灣 `rail_structures.json` 同樣的格式。描線（決策 213、279）在日本就照真實高架與隧道建。`vt_sngldbl` 的單線／複線也可以順便帶，給「一鍵雙線」參考。

- 讀 PMTiles 要一個解碼器（Python 的 `pmtiles` 與 `mapbox-vector-tile`）；這是新相依，只在 `tools/` 裡用，要作者同意（CLAUDE.md Workflow）。
- 排在 4.A 之後：沒有日本的真實鐵路，就沒有地方用橋隧。

**五方**：玩家：照真實鐵路描線時高架與隧道是對的；鐵道迷：國土地理院的官方構造；開發：幾何比對與新相依是主要成本；美術：無新圖；音樂：無。

### 4.C 實景地圖真實列車的加減速（Mini Tokyo 3D 的演算法，或作者參考庫的 `buildProfile`）

決策 304 的真實列車站間等速，看起來是一路滑過去。照 CLAUDE.md 找前例的順序：
1. **作者參考庫先**：`taiwan-rail-reference-clean/source/main-reference.js` `buildProfile`（4853 行起）已經有加速、巡航、惰行、減速四段，而且解到時刻表給的時間；決策 304 當時刻意沒有移植。它是同一個網站、同一份資料的做法，優先用它。
2. **Mini Tokyo 3D 補兩個它沒有的細節**（MIT，保留版權聲明）：
   - 曲線放不進時間窗時，把加速度與最高速度一起解小（`trainRepeat` 1570–1589 行），不會跑出一個不可能的速度；
   - 位置沿折線二分搜尋、方位與坡度事先算好（`updateDistances`），每幀只內插，200 列車的成本不變。

只改 `RealTrainMotion.swift`，GameCore 不動。量法照決策 304：`REAL_TRAINS_REPORT=1` 的幀成本報告前後各量一次。

**五方**：玩家：進站減速、出站加速，城市看起來是真的車在跑；鐵道迷：站間的速度形狀像真實電車；開發：一個 GamePresentation 的函式，Linux 測試；美術：同一個膠囊，只是動得不一樣；音樂：無。

### 4.D 日本的真實列車

日本的真實列車（決策 304 在日本）只能用**估計班距**：JR 與大手私鐵沒有可公開使用的時刻表（§2、§3.5），ODPT 一般授權的只有都營、筑波快線、臨海線等少數，而且要金鑰。做法照決策 304 台鐵的「只有班距的線」，班距表由遊戲自己定、寫明是估計值（像ひと駅寫「独自のシミュレーション推定値」）。參考庫 `tokyo_schedule_dense.json` 的東京合成班距可以直接用（作者的）。排在 4.A 之後，優先度低。

### 4.E Mini Tokyo 3D 其他能參考的

| 項目 | 遊戲的現況 | 建議 |
| --- | --- | --- |
| 追蹤鏡頭六種（§3.4 第 5 項） | 2D 有跟隨鏡頭（OVERVIEW §3「畫面」）；3D 沒有跟車的視角 | 給 3D 那條線：先做「後方」「上後方」兩種，數字照 Mini Tokyo 3D，換算成遊戲的 3D 相機 |
| 日照四組顏色與混合時段（第 4 項） | 已有晝夜與天氣，3D 有自己的光 | 只在 3D 的日出日落顏色要調時拿來對照，不換 |
| 直通運轉的 `pt`／`nt` 串接（第 2 項） | 真實列車每條線各跑各的 | 台灣的直通（例如捷運之間的直通、台鐵跨線）出現在打包資料時再用 |
| 平行偏移（第 3 項） | 2D 真實鐵路照 OSM 線形，複線是兩條真的軌道 | 不需要 |
| 03:00 服務日、週六與假日班表 | 決策 304 已經有「過午夜從前一天取」與平日／假日 | 已有，不用 |
| 列車資訊卡欄位 | 真實列車不能點（決策 304） | 不需要 |

### 4.F 日本車站的英文名與自動命名（GSI 多言語表記）

- 用法一：4.A 的車站英文名，用名字與 300 m 內的距離對到 `ftCode` 2930 的點，取 `name`（去掉「Sta.」）。
- 用法二：日本開局時新車站的自動命名（台灣用 `taiwan_place_names.json`，決策 159），用 `annoCtg` 110／210 的市區町村與町丁目。
- 限制：實驗性、沒有規格，打包是否需要申請判斷不了（§3.3）。所以只當補充，主要來源仍是 N02 的站名；用之前先寫信問國土地理院或改用 N02＋OSM 的 `name:en`。

## 5. 對照表（參考 → 遊戲）

| 參考 | 函式／欄位 | 遊戲的檔案／函式 | 備註 |
| --- | --- | --- | --- |
| N02 `RailroadSection` | `N02_003`、`N02_004`、線形 | 新的 `tools/japan-railways/` → `track_lines` 同格式 → `RealRailways` | 依端點接線；度，小數 6 位 |
| N02 `Station` | `N02_005`、`N02_005g`、折線中點 | `track_stations` 同格式；`RealRailways.stationKey` 的同名合一 | `N02_005c` 每年會變，不當 id |
| 參考庫 `world-rail-reference-clean/source/data/tokyo.json` | `lines[].color`、`stations[].name`、`shape` | 東京都界內優先於 N02 | 署名照它的 `source_notes`（OSM ODbL） |
| 參考庫 `tools/build_tokyo_rail.mjs` | 站投影到線形排序 | 新工具的站序 | 同一種排法 |
| optimal_bvmap `RailCL` | `vt_railstate`、`vt_sngldbl` | 日本版 `rail_structures.json`（決策 279 的格式） | 幾何比對；PMTiles 解碼器是新相依 |
| GSI multil | `knj`、`name`、`ftCode` 2930 | 車站英文名、日本地名 | 實驗性 |
| `main-reference.js` | `buildProfile` | `RealTrainMotion.swift` 的站間位置 | 公尺、秒；畫面用 `Double`，不進 GameCore |
| Mini Tokyo 3D `map.js` | `trainRepeat` 的時間窗求解（80 km/h、3 km/h/s、`minDelay` 25 s、`minStandingDuration` 30 s） | 同上，`buildProfile` 解不出時的退路 | MIT，檔頭保留版權聲明 |
| Mini Tokyo 3D `helpers-geojson.js` | `updateDistances` | `RealTrainMotion` 的折線累積距離 | 台灣版已有累積距離（`ensureCum`），只補方位快取 |
| Mini Tokyo 3D `map.js` | `_jumpTo`、`updateTrackingParams` | 3D 的跟隨相機 | 3D 那條線 |

沒有用的：Mini Tokyo 3D 的 `data/`（沒有授權）、即時資料（要金鑰與網路）、列車方塊模型、Mapbox 的模型與字型；GSI 的底圖圖磚（遊戲已有 Apple 地圖與 OpenFreeMap）。

## 6. 分數（照 NEXT_PRIORITIES §19 的權重：玩家 30%、開發 25%、美術 15%、鐵道迷 15%、音樂 15%）

| 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權分 | 依賴 |
| --- | --: | --: | --: | --: | --: | --: | --- |
| 4.C 真實列車的加減速 | 2 | 4 | 3 | 5 | 1 | 2.95 | 無；R2（決策 304）已合併 |
| 4.A 日本的真實鐵路與車站 | 3 | 2 | 2 | 5 | 1 | 2.60 | 無；路線色表是主要工作 |
| 4.B 日本的橋與隧道 | 2 | 3 | 2 | 4 | 1 | 2.40 | 4.A；新相依要作者同意 |
| 4.D 日本的真實列車（估計班距） | 2 | 2 | 2 | 4 | 1 | 2.15 | 4.A |
| 4.E 3D 追蹤鏡頭 | 2 | 3 | 3 | 1 | 1 | 2.10 | 3D 那條線 |
| 4.F GSI 的英文站名與地名 | 2 | 3 | 1 | 2 | 1 | 1.95 | 4.A；授權要先問 |

- 4.C 落在 §19 第 3 名（2.95）附近，是唯一不必等其他工作、也不碰別人檔案的；4.A 和收購支線（2.60）同分。
- **不改順序**：甲、乙兩線與 GameCore 的排隊都照舊。這些全在 `tools/`、GamePresentation 與 App 的資源，不升存檔，可以放進「修正 lane」或乙線 R2 之後。
- 玩家分不高的理由：大多數玩家玩台灣；日本開局是決策 262 才加的，還沒有玩家回報要日本的真實鐵路。

## 7. 音效、音樂與地圖的出處（作者 2026-10-21 第二批）

作者接著貼了「ひと駅」的音源與地圖出處，問這些能不能用。

### 7.1 遊戲的聲音現在怎麼做

- App 的 15 個音檔（`RailwayGameApp/Resources/Audio/`）全部由 `tools/audio/make_game_audio.py` 用正弦波與固定種子的雜訊合成。沒有取樣，也沒有第三方音源（決策 79、219）。
- `--check` 重新產生，要和提交的檔案一個位元組都不差。
- 決策 219 的研究（`RAILWAY_SOUND_2026-10-14.md` §2.2）定了用自己的合成器，理由有兩個：
  - 聲音和遊戲、介紹影片一致；
  - 沒有授權問題。
- 作者的參考庫裡沒有任何音檔（同一份研究 §9）。
- **這個 repository 是公開的**（CLAUDE.md）：放進 App 資源的檔案，任何人都能從 GitHub 下載原檔。

### 7.2 每一筆音源

| 音源 | 授權 | 公開 repo 能不能放 | 是什麼 | 遊戲用得到嗎 |
| --- | --- | --- | --- | --- |
| ポケットサウンド（pocket-se.info） | 自己的規約（2023-05-31 版） | **不能**：禁止「音素材そのものの二次配布・転売」，公開 repo 等於散布原檔 | ひと駅沒有寫用了哪幾個檔 | 不用。要用，得先用問い合わせフォーム問清楚公開原始碼的情況 |
| OtoLogic | CC BY 4.0（作者貼的；官網有 Cloudflare 驗證，這裡打不開，UNVERIFIED） | 可以，署名「OtoLogic」並附連結 | 印表機（紙）、改札的嗶聲、新幹線行駛音 | 新幹線行駛音：跟隨高鐵時的行駛聲。印表機：之後一日券（NEXT_PRIORITIES §21）的票券卡。改札嗶聲：遊戲沒有剪票口的畫面 |
| uair01「train_wheels_ringing_curve」（Freesound 57786） | CC BY 3.0（頁面確認） | 可以 | 11 秒，慢速過彎的輪緣摩擦聲；沒寫是哪裡的車 | 跟隨列車慢速通過急彎時（決策 217 由曲率算出限速的地方） |
| Shuhmi「Modern Diesel Train (BR 622 LINT)」（Freesound 850682） | CC BY 4.0（頁面確認） | 可以 | 32 秒，德國 Alstom Coradia LINT 54 柴聯車怠速與起步 | 只當頻譜參考：它是德國的車，不是台灣的柴油車。ひと駅也只用平均頻譜做穩定的質感，沒有用原錄音 |
| Chihayasassas「Toden Arakawa Line-bell」（Wikimedia Commons） | CC BY-SA 3.0（另有 2.5、2.0、1.0 與 GFDL，任選） | 可以，但改作後的檔案仍是 CC BY-SA 3.0，要分開標明 | 2.2 秒，都電荒川線的發車信號鈴 | 不用：東京路面電車特有的聲音，台灣的輕軌不是這樣；日本開局之後再說 |
| TAM Music Factory | 自己的規約 | **不能**：禁止「素材そのものの販売・二次配布」；有課金就算商用，要寫「音楽：TAM Music Factory」 | 配樂 | 不用。遊戲的配樂是自己的 MML 與分軌（決策 219），不換成現成曲 |

CC 3.0 的授權（uair01、荒川線的鈴）不允許加上限制使用者權利的技術保護。App Store 的 FairPlay 算不算，有爭議。公開 repo 本身就是一份沒有保護的原檔，一般認為這樣就夠了。真的要打包時，再查一次 CC 的 FAQ。

### 7.3 建議：不打包錄音，用合成器照錄音的頻譜做

ひと駅處理柴聯車的方法是：
- 照原錄音的平均頻譜做一段穩定的質感，再濾波、合成、做成循環；
- 不用原錄音的時間變化、相位、人聲與發車信號。

遊戲的合成器（固定種子的雜訊）可以照同樣的方法做行駛聲。

**做法**：
1. 量 CC BY 錄音的平均頻譜：OtoLogic 的新幹線行駛音、uair01 的過彎聲，柴油車用 Shuhmi 的。
2. 用量到的頻譜塑形 `make_game_audio.py` 的雜訊，做成三種循環：
   - 高速（高鐵）；
   - 一般電車；
   - 過彎的摩擦聲。
3. 頻譜的數字寫進工具（它也是改作的依據），`DataSourceCredits` 照 CC BY 署名，註明「參考其頻譜重新合成」。
4. 輸出仍然每次相同，`--check` 照舊。

**什麼時候播**：
- 決策 219 第二階段的「跟隨列車、60 倍速以下」才播，和配樂淡出同一個時機。
- 過彎聲只在跟隨的列車通過有曲線限速的地方時播。

**五方**：
- 玩家：跟著自己的車看時，聽得到車在跑、過彎時的聲音。
- 鐵道迷：聲音的質感來自真實錄音，但不是逐車的真實錄音，要寫明。
- 開發：只動資料工具與 App 的播放，GameCore 不動；頻譜量一次，之後重產都相同。
- 美術：無。
- 音樂：音色仍是同一套合成器，和鈴聲、配樂不衝突。直接放錄音會是遊戲第一個真實取樣，和柔和的合成音色混在一起會突兀。

**沒選的**：
- **直接打包 OtoLogic 與 uair01 的錄音**：最快，授權也允許。但會破壞決策 219 的「一套合成器」，循環點也要另外處理。合成的版本聽起來不夠真時，這是退路，預覽留在 PR 給作者比較。
- **ポケットサウンド、TAM**：公開 repo 不能放。私有庫加建置時注入可以避開，但要動 CI 與祕密，不值得。

| 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權分 | 依賴 |
| --- | --: | --: | --: | --: | --: | --: | --- |
| 跟車行駛聲（合成，參考 CC BY 錄音的頻譜） | 3 | 3 | 1 | 4 | 4 | 3.00 | 決策 219 第二階段（跟隨列車、音量分開） |
| 直接打包 CC BY 錄音（退路） | 3 | 4 | 1 | 4 | 2 | 2.95 | 同上 |

### 7.4 地圖：遊戲都已經有了

| ひと駅的 | 遊戲 | 出處 |
| --- | --- | --- |
| OpenMapTiles（格式 CC BY 4.0，地圖角落要看得到署名） | 有：地圖角落「© OpenMapTiles © OpenStreetMap」（決策 191），資料來源頁有格式的連結 | `DataSourceCredits.swift` 100–102、366 行 |
| OpenStreetMap（ODbL 1.0） | 有 | 同上 |
| OpenFreeMap | 有：台灣以外的實景地圖用它的圖磚 | `BaseMapStyle.openFreeMapTiles` |
| Positron 樣式（程式 BSD 3-Clause、設計 CC BY 4.0，衍生自 CartoDB CC BY 3.0） | **不用**：遊戲是自己的樣式（決策 151），不需要 Positron 的聲明。以後要借它的配色時才要加 | `BaseMapStyle.swift` 檔頭 |
| MapLibre Native 6.31.0（BSD 2-Clause） | 有，同一版（`project.yml` 的 `exactVersion: 6.31.0`），授權檔隨 App | `Resources/Licenses/MapLibre-iOS-LICENSE.md` |
| Noto Sans（OFL 1.1） | 有：ひと駅用 OpenFreeMap 的遠端字形；遊戲把字形打包在 App 裡，連 OFL 全文 | `Resources/BaseMap/fonts/`、`Resources/Licenses/NotoSans-OFL.txt` |

不用改。

## 8. 驗證與來源

**VERIFIED（Linux，2026-10-21）**：
- Mini Tokyo 3D：`git clone` 後 checkout `220adf8`，讀 `LICENSE`、`src/`、`data/`、README 與 `docs/`；沒有執行它的任何程式。數字（`configs.js` 的 80 km/h、3 km/h/s 等）是讀原始碼得到的。
- N02：下載 `N02-25_GML.zip`，用 Python 解析 GeoJSON，數出 §3.1 的筆數；21 個城市的範圍與大小用 `RealWorldStations.swift` 的座標算。
- GSI：抓 `experimental_multil/15/29140/12897.geojson` 等圖磚、`optimal_bvmap` 的 repo 與規格、利用規約頁。`www.gsi.go.jp` 要允許 OpenSSL 的舊式重新協商才連得上（憑證照常驗證）。
- §7：讀了ポケットサウンド（https://pocket-se.info/rules/）與 TAM Music Factory（https://www.tam-music.com/interface）的規約頁、兩筆 Freesound 與 Wikimedia Commons 的檔案頁；遊戲的地圖署名、樣式、MapLibre 版本與字形照 repo 的程式與 `project.yml` 核對。

**UNVERIFIED**：
- ODPT 各資料的條款原文（開發者網站要 JavaScript，抓不到）；本文照參考庫 `route_scope.json` 已查過的結論。
- 多言語表記打包時是否屬於基本測量成果、要不要申請。
- App 裡的大小、讀檔時間與幀成本（沒有實作）。
- OtoLogic 的規約原文（官網有 Cloudflare 驗證，打不開）；照作者貼的 CC BY 4.0。
- 頻譜重新合成的行駛聲聽起來夠不夠真（沒有做）。

**來源**：
- https://github.com/nagix/mini-tokyo-3d/tree/220adf8e8c4dae8251f4999502757d2cbc25c747（MIT）
- https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html 、https://nlftp.mlit.go.jp/ksj/other/agreement_01.html （CC BY 4.0）
- https://github.com/gsi-cyberjapan/optimal_bvmap 、https://maps.gsi.go.jp/help/pdf/vector/ 、https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html 、https://www.digital.go.jp/resources/open_data/public_data_license_v1.0 （PDL 1.0）
- https://maps.gsi.go.jp/xyz/experimental_multil/15/29140/12897.geojson 、https://maps.gsi.go.jp/development/ichiran.html
- 作者參考庫：`Railway/world-rail-reference-clean/source/data/route_scope.json`、`tokyo.json`；`Railway/taiwan-rail-reference-clean/source/main-reference.js`（`buildProfile`）、`source/docs/research-tw-jp.md`、`research-intl.md`（之前對 Mini Tokyo 3D 功能面的調查）
