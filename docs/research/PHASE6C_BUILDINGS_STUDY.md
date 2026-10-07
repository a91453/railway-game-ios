# Phase 6c 建物、容量與地價，以及 Phase 8 素材管線：參考盤點與設計提案

查閱日期：2026-10-07（UTC）。本分支由當時最新 `origin/main` **`ea6ca31479c21d55650bcc904dbf529cdca02aab`** 開出；私有參考庫 `a91453/railway-reference-private` 已實際 clone，提交為 **`2db0c5a6963798e6b86723bb001189343a59940c`**。參考路徑均相對於私有庫根目錄；bytes 是實際檔案大小，MiB = 1,048,576 bytes，並非 IPA 壓縮後大小或 GPU 記憶體。本文只有研究與提案，型別、函式、數值和 PR 拆分尚待作者採納。

**本次只新增此文件，沒有程式變更，沒有執行或宣稱任何測試通過。** GameCore 規則、存檔、golden、獨立模型與正式架構紀錄，仍依 `AGENTS.md` 由 Claude Code 負責。

## 1. 基準、已定方向與土地接點

開始前依序讀 `AGENTS.md`、`CLAUDE.md`、`docs/ARCHITECTURE.md`（決策 28、50、54、70）、`docs/ROADMAP.md` 的 Phase 6／7／8 與「跨階段議題」、Phase 6a 參考對照、`docs/research/PHASE6_LAND_USE_STUDY.md`，最後讀 `Sources/GameCore/City/Land.swift`。main 已合併 PR #172，因此土地研究讀 main；main 當時還沒有決策 72、Phase 6a 對照與 Land.swift，這三項讀 **`origin/claude/relaxed-curie-v8j2fp`，`5f1d8ccd48677cf8241d7b50308cc78043121806`**，沒有把該分支合入本研究分支。

本次指示已取代前一份研究的權威任意輪廓提案，以下三點視為既定條件：

- GameCore 的建物只以**佔用哪些 64 m 格**表示；任意輪廓、朝向、模型、LOD 與模型高度差異在畫面／素材層。鐵路與車站仍是連續世界座標，決策 28、54 不變。
- 地價先即時推導，不存價格歷史；建造與維護費用、交易、租金、折舊與資產負債表由 Phase 7 處理，不放進 6c。
- GameCore 只用整數，結果固定；如需抽籤，只用存檔種子與 `SeedDraw` 的 FNV-1a。相機、載入順序、裝置設定、系統時間與系統亂數不影響模擬。

| 本專案檔案／名稱（6a 分支） | 實際值／行為 | 6c 接點 |
| --- | --- | --- |
| `City/Land.swift`：`Land.cellLength`、`columns(in:)`、`rows(in:)` | 4096 世界單位 = 64 m；最後一行／列可超出 bounds。最大世界 256 × 256 = 65,536 格。 | 不能把 64 世界單位誤當格邊長；一格面積是 4096 m²。新建物建議只佔完整在 bounds 內的格；既有末格人口保留。 |
| 同檔：`LandCell {row,column,use,residents,jobs}`、`isValid` | 三種 `LandUse`：residential／commercial／office；居民與就業各 `0...100_000`，不能同時為 0。`Land.cells` 按 row、column 排序。 | 居民／就業只存土地一次；建物提供容量，不再存入住人數。空置建物須能存在於獨立建物清單，不能靠人口為 0 的 LandCell 表示。 |
| 同檔：`middle`、`cell(at:)`、`totals(within:of:)`、`landCatchment(of:)` | 格中心 `column×4096+2048`、`row×4096+2048`；腹地半徑 51,200 單位 = 800 m，以 `d² < R²` 判定。 | 地價與 6b 使用相同嚴格小於規約，800 m 邊界不算入。`landCatchment` 是重疊腹地的顯示總量，不能直接拿來重複產生人口。 |
| 同檔：`setLand(_:)`、`foundTowns(seed:)`、`Land.towns(seed:in:)` | 整份替換；setLand 拒絕重複／越界／無效格。3 聚落；中心半徑 12 格、130 人；外側半徑 7–10 格、峰值 80–120；核心住 1/4、工作 3 倍。 | 6c 啟用後替換土地也必須驗證建物容量／用途，不能留下失配；初始核心的商業／辦公也有居民。 |
| 同檔：`Run`、encode／decode；決策 72 | `{row,column,use,residents:[...],jobs?:[...]}`；全 0 jobs 省略。土地版存檔 12、golden schema 36 是該分支的狀態。 | 本研究不升版；實作時以已合併的版本為基準。建物缺鍵的土地舊局如何建立既有存量，要明訂遷移。 |
| `Passenger/TownGrowth.swift`：`growth(served:trips:reached:)`、`growTowns(reached:)`；決策 70 | +10 千分比的服務項、每可達站 +1（最多 5）、無抵達 −2；上限原旅次 4 倍。現在長的是 StationDemand。 | 6b 土地世界改長居民／就業；6c 提供上限，不能同時再長車站旅次。服務只讀 Passenger／車站／線路的穩定量測。 |
| `Passenger/DemandEvents.swift`：6a 抽出的 `SeedDraw.hash/roll` | UTF-8 `seed\|key`，FNV-1a 32 位元，初值 2,166,136,261、乘數 16,777,619，乘法按 UInt32 wrapping。 | 使用獨立鍵如 `building:v1:<cell>:<purpose>`，不消耗事件 draws；型別與容量本身不必抽籤。 |

## 2. 台北場景：擺放、區域風格與 site

路徑前綴 **T = `Railway/taipei_gta_reference/source/`**；表內 `T/assets/...` 均指這個完整前綴。先讀該包 `00_READ_ME_FIRST.md`，再展開 minified JS 到工作區的 scratch 閱讀，未改參考原檔。`T/assets/engine-DKps_Gq_.js` **137,915 bytes**；`T/assets/world-gYgJkZNf.js` **1,357,123 bytes**。函式短名是 bundle 裡的實際名字，不推測不存在的 TypeScript 原始碼。

### 2.1 逐條合法性規則與格佔用改寫

`world` 的 `rO` 先收集鄰近 roads／blocks／landmarks／transit／mrt／已放 sites；`lO` 依下表順序回傳第一個拒絕原因。`RD` 是嚴格矩形交疊、`zD` 是包含、`VD` 是有朝向矩形與 AABB 的分離軸檢查、`HD` 是點到矩形的平方距離。這些是**場景配置規則**，來源沒有所有權、入住、工作容量或日成長。

| 參考函式／鍵 | 實際規則／值（m） | 改成 64 m 格佔用是否可行；整數常數／差異 |
| --- | --- | --- |
| `world: DO` | site anchors 的依賴已處理才選取，保留輸入索引的輸出；duplicate id 產生錯誤。同批 site 自指／批外依賴不阻塞；找不到可處理項（例如循環）就取剩餘第一項，交後續擺放檢查。 | 可改為依 BuildingID／CellKey 的固定順序，先計算整批佔格再原子提交。建議新核心拒絕循環或無效依賴，**不是來源 DO 已拒絕循環**；模型 anchors 仍屬匯入與畫面。 |
| `world: lO` 的 bounds | rect 不得越過 `plan.bounds`。 | 可逐一驗證格 row／column 與完整格界線；不用權威矩形。來源 engine 的 bounds x `[-900,900]`、z `[-960,560]` m，換算為 x `[-57_600,57_600]`、z `[-61_440,35_840]` 單位，再由匯入端加明確原點偏移。不能直接放入本遊戲非負座標。 |
| `lO` roads、`host`、`allowSidewalk` | host road 例外；`RD(rect,lot,-0.05)`；車道交疊回 `road`，其餘若未允許人行道回 `sidewalk`。 | 可把道路／人行道遮罩輸入為保留格，再驗證佔格交集；需要遮罩來源，**6a 沒有這份資料（gap）**。−0.05 m 建議離線四捨五入為 −3 單位；若直接升成整格禁建，公尺級退縮與 host 例外不會等價，需報量化誤差。不能讓整數格把鐵路吸附到方格。 |
| `lO` requireBlock、`zD` | 預設必須在一個 block 內，可容差 **0.5**；`requireBlock:false` 關閉此項。 | 可檢查全部佔格屬同一可建街廓 ID；0.5 m = **32** 單位只在匯入遮罩生成時使用。格跨街廓時的保守拒絕是新政策；不能默認細小街廓可塞下完整 64 m 格。 |
| `lO` landmarks、`RD` | 非 pedestrian 地標，擴 **2** m，回 `landmark:<id>`。 | 保留格不重疊可表達；**128** 單位外擴再格化。原來源在邊界相切不算交疊，整格化會多排除格。 |
| `lO` transit、`VD` | entrances／obstacles 的旋轉矩形，外擴 **3** m；`rO` 粗搜半徑 `max(hw,hl)×1.5+3`。 | 在匯入端將禁建區轉為佔格清單；**192** 單位，不在核心存朝向或做 sin／cos。高度／地下共構例外需要另訂；第一版不能因有 mesh 空隙就允許穿越。 |
| `lO` MRT、`HD` | 出口點離 lot 小於 **4** m，回 `mrt:<id>`。 | 禁建格遮罩可表達；半徑 **256**、平方 **65_536** 單位²。來源是點到 lot，不是格中心距離；離線格化要記錄所選規約。 |
| `lO` placed、`RD` | 與已成功放置 site 擴 **1** m交疊，回 `site:<id>`。 | 核心直接拒絕同格重複佔用；**64** 單位間距只保留為畫面擺放規則。相鄰格可接觸，不必在核心強迫空一格（會變 64 m 間距）。 |
| `lO` env.claimed、`BD` | lot 內縮 **0.2** m，再以 scope `buildings` 查 claims，回 `district-claim`。 | 建物類保留格能表達；離線內縮建議 **13** 單位（0.203125 m），scope `props` 不阻止建物。所有權／用途遮罩是新契約，不能把呈現 claim 當人口。 |
| `world: UD`、`PD`、`ID` | rect 四邊內縮 **0.3** m，x/z 各取低、中、高，共 **3×3 = 9 點**；第一個非允許 surface 就拒絕。預設 PD = lot／plaza／park；ID 是在預設集合加額外 surface。 | 核心逐一檢查佔格的可建旗標／用途；0.3 m 建議 **19** 單位（0.296875 m）。9 點無法證明全輪廓可建。plaza／park 可放 site 是來源場景需求，**不提案把城市公園自動改成住宅**。 |
| `world: WO`、`qO` | 臨路搜尋：setback 預設 **0.5**、search **60**；wide relaxation 將 search ×2；沿路偏移按 0、±2、±4…m，交叉口加 **4** m；undercroft 要 elevated 且 `oD(road,1.2) >= 2`。lane 僅在placement.lane且mode=lot時搜尋，步長2，score含 **8+lane距離+偏移**；side另一側懲罰 **100000**，off-frontage／允許sidewalk各可加 **8**。qO再加 **0.5×IE(targets,中心)**，比最佳分數小逾 **1e-9** 才替換。 | 候選佔格可以固定排序再驗證，但沒有必要把完整車道搜尋搬進核心；建議匯入／預覽端輸出格清單。32／3840／7680／128／256 單位；1.2 m 建議 **77**、2 m = **128**。score另用1/1000比例時0.5→500、8→8000、100000→100000000；它不是費用。核心不用1e-9或浮點tie-break，依固定候選索引平手。64 m 粗格不保持沿路2 m搜尋或高架下店面語意。 |
| `engine: hr.buildBlocks` | major x/z 道路按 at 排序，插入 minor roads；街廓扣 halfTotal；寬或深 **<20** m 跳過。路段範圍檢查容差 **1** m；生成 `{id,minX,maxX,minZ,maxZ,district,reserved,zones,north,south,west,east,edge}`。 | 可離線產生 block→可建格／保留格；20 m = **1280**、1 m = **64**。20 m 街廓可能沒有完整64 m格，所以**不能宣稱直接搬到核心等價**。小街廓與同格多棟外觀聚合成一個開發單元。 |
| `hr.districtAt(x,z,gen=false)` | 先 Kn 的 **5** 覆寫矩形，再 V 順序；半開範圍。gen=true 跳過 `gen:false` 覆寫；無命中回 V 最後的大安。 | 可將格中心所屬 style ID 放到場景匯入／畫面表；不作居民／就業規則。需保留順序、gen 旗標與後備，不能把未涵蓋處默認合法可建。 |
| `hr.surfaceAt` | x<**−960** 或 z<**−1030** 為 water；道路段 ends 容差 **0.01** m，車道→road 或 pedestrian plaza、人行道→sidewalk（curb corner→road）；城外 terrain；K 的 park 矩形→park；其餘 lot。 | water／保留地遮罩可格化；門檻 −61_440／−65_920 單位，0.01 m 建議 **1** 單位。road/plaza/sidewalk 的視覺形狀與 LandUse 三用途是不同資料。格面積很大，中心判定和任一交疊判定需明訂，不能每次由畫面 query 重算權威。 |

建議外部量化統一為**最近的 1/64 m，恰半向遠離 0**；以上 −0.05／0.01／0.2／0.3／1.2 m 是提案的量化值，並非來源已使用定點。若把參考footprint轉成有玩法的佔格，建議工具先量化輪廓，再取與輪廓**有正面積交集**的全部64 m格（相切不算），去重後按row／column輸出；禁建輪廓也採此保守規約，不能只採中心抽樣漏掉細道路。這項格化會排除更多小基地，是需量測的新政策；預設裝飾素材不必因此佔用核心格。GameCore只接收格清單與整數遮罩，不接收lot矩形、三角形或模型碰撞箱。`world` 的空間索引 `XD` 預設 **96 m**、每軸最多 **512**，只加速搜尋；不要當新的土地格規格。`GD` 的距世界邊 **10 m**（640單位）是fringe警告，不能誤寫成lO強制退縮。

### 2.2 V 的 9 區：可保留風格，不能冒充容量表

`engine: V[].style` 的原值如下；towers／old／shops／neon 改寫成 1/1000 時都能精確表示。邊界是來源平面 m，經匯入偏移後才乘 64，區域本身不是法定土地用途。

| id／區 | x 半開範圍 | z 半開範圍 | floors | towers | old | shops | neon |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| riverside／河濱 | −1200…−900 | −1400…1000 | 0…0 | 0 | 0 | 0 | 0 |
| shilin／士林 | −900…900 | −1400…−790 | 3…8 | .05 | .6 | .95 | .7 |
| ximending／西門町 | −900…−560 | −330…70 | 4…12 | .1 | .4 | 1 | 1 |
| wanhua／萬華 | −900…−560 | 70…1000 | 2…6 | 0 | 1 | .85 | .4 |
| zhongzheng／中正 | −560…−130 | −330…1000 | 4…14 | .25 | .35 | .6 | .2 |
| zhongshan／中山 | −900…230 | −790…−330 | 5…16 | .3 | .45 | .8 | .6 |
| songshan／松山 | 230…900 | −790…−330 | 5…14 | .25 | .5 | .75 | .5 |
| xinyi／信義 | 480…1200 | −330…1000 | 10…40 | .8 | .05 | .5 | .35 |
| daan／大安 | −130…480 | −330…1000 | 5…14 | .3 | .4 | .8 | .35 |

Kn 的 5 筆：大安 x[−212,−130)、z[280,1000)；中正 x[−700,−560)、z[−330,70)；大安 x[−202,−62)、z[140,266)；士林 x[−202,−62)、z[−883,−743)；松山 x[344,464)、z[−330,−300)。最後 4 筆 `gen:false`。

實際把 style 變成建物的是 `world: Eg.pickType/floorsFor/layoutBlock`：

- `pickType`：old≥.9 時 shophouse weight .55；old≥.55 時 .08；apt weight `.3+.9×old`；floors.max≥7 時 mid weight `.2+1.2×towers+(floors.min≥5 ? .25:0)`。這些是**相對權重，不是人口比例**。
- `floorsFor`：shophouse 2／3／4 樓權重 3／4／1；apt 候選 4／5／3／6 樓權重 4／5／1／1，再夾限；mid 介於 `max(7,min)` 與 `max(8,min(16,max))`；low／setback 1–2；其他塔樓 `max(18,min)` 到 `max(22,max+5)`。所以 V 的 floors 不能當每棟硬上限，信義 default tower 可到 **45** 樓。
- `layoutBlock` floors.max≤0 不生建物；tower 機率項是 towers≥.6 時 `.8×towers`，其他 `.22×towers`。`widthFor` 的 shophouse **4.4–6.6 m**、apt **6.5–12.5 m**、mid **14–26 m**，通常一個64 m格能畫多棟。`world` 簡化建物高度有 `max(7,floors×3.3)`，塔身外觀有 `floors×3.9`；兩者為畫面值。

**提案**：另建「LandUse × 密度 → 固定容量與名義樓層」表（§5）；畫面才讀這 9 區的 style 作 shophouse／apt／mid／tower、立面老舊與店面變體。shops 是場景店面分布，不能變成商業格的就業倍率；riverside 的 floors=0 也不能代替尚未存在的 water／park 可建遮罩。若作者要把原 weight 規則搬成核心抽籤，須整數化權重、固定候選序與 SeedDraw 鍵，容量仍由選定類型表決定。

### 2.3 地標與 site 欄位契約

`engine: K[]` 是 `{id,name:{zh,en},x,z,w,d,facing,kind,zone?}`；台北101 `x:745,z:200,w:110,d:110,facing:0`。這個 **110×110 m** 是場景 lot，與另一包101 footprint **146.218408×138.382879 m** 不是同一個資料，不混用。`block.reserved` 收 `!zone` 的 K，`block.zones` 收有 zone 的 K。

`world: xE` 直接回傳 metadata；`oA` 先按 defs 路徑排序與 `aA` 驗證，再按 priority 降序／id 排序；`lA` 快取且排除 cA 退役定義。`aA` 要求 placement.cross 1–2 組、lot.w/d>0、proxy 1–8 boxes、map.minimap 是 Bool、interior 為 none／partial／full，也檢查 name 不含 brandReal。這是來源的名稱與場景契約，不是本專案額外授權限制。

| 鍵／資料 | 實際 schema 與例值 | 移植用途 |
| --- | --- | --- |
| `id/name/category/district` | id 字串、雙語 name；donqi `category:shop,district:wanhua`，鐵道部 `museum,zhongzheng`。另有 blurb、houseNo、brandReal。 | 畫面 catalog；category 不自動推成工作人數。文案轉台灣用語，原資料鍵不改。 |
| `lot` | `{w,d,minW?,minD?}`，公尺；donqi **24×22**、min **19×18**；蜂達 **12×14**、min **10×11.5**；鐵道部 **40×30**、min **32×24**。 | 任意輪廓／縮小候選在匯入與畫面；核心收佔格結果。 |
| `claims[]` | local `{x0,z0,x1,z1,scope}`，scope buildings／props／all。donqi buildings `[−12,−11,12,11]`，props `[−12,−14.5,12,−11]`；鐵道部 all `[−20,−15,20,15]`，props `[−18,−17,−8,−15]`。 | 分開生成建物保留格與純 props 層；props 不加容量。 |
| `placement` | frontage／alt 道路 `{zh,sec?}`；cross 的道路或候選列表；side N/E/S/W；along、setback、search、gate `{alongFrom,offset}`；可有 mode／lane／replaces／anchors。donqi along **2**、setback **.5**、search **60**、gate.offset **6**；鐵道部 along **6**、search **210**（13,440 單位）。 | 臨路解算與資料查錯；replaces 是來源固定場景的輪廓調整，不能授權玩家拆除別人的建物。 |
| `anchors[]` | `{kind:landmark/site/mrt,id,exit?,bearing,dist,tolDeg?}`；方位角度／公尺。donqi redhouse **326°／215 m**、ximen **316°／262 m**；鐵道部 beimen **315°／150**、main-station **250°／600**、v-beimen **45°／130**。 | `OE/kE/ME` 處理點、方向與容差；方向 sin/cos 在素材匯入端，core 不存 anchors。`tolDeg` 預設 **35°**，ME另加 atan2(10,dist) 容差；距離 slack **8 m**。不是精確測繪。 |
| `proxy[]/solids[]` | proxy `{x,y?,z,w,d,h,roof,roofH?,mat,color?}`；solids `{x0,z0,x1,z1,y0?,y1}`。donqi proxy 主高 **18.2 m**；蜂達 **14.05 m**；鐵道部主館 **8.8+3.6 m 屋頂**、塔 **11.6+4.6 m**。 | 可以產生 iOS 低細節幾何；碰撞箱、室內與屋頂不能回寫土地容量。 |
| `map/interior/atlas/cluster/hero/priority` | map `{icon,minimap}`、interior enum、atlas.slots；donqi `partial,slots:1,cluster:ximen,hero:true,priority:60`；鐵道部 `partial,cluster:beimen,hero:true,priority:85`。 | 只影響載入、快取、顯示與場景排序。 |

現存 site 模組有 **3** 個，不能只說2個：`T/assets/site-donqi-ximen-BYSklXQx.js` **28,314 bytes**、`site-fongda-coffee-BLqPP37I.js` **32,315**、`site-railway-department-park-BykCBjAy.js` **25,070**。另外 `build-B3ahlmTh.js` **113,537**、`build-BQ6sPpWH.js` **109,307** 是場景幾何／atlas生成；後者有 atlas 預設 **2048**、固定 RNG seed **20,283,292**，不作本遊戲城市種子。

`world` 的 dynamic import 去重後 **46** 個 site 路徑，**43 個缺檔（gap）**。下列全部相對於 `T/assets/`；檢查每條實際檔案存在性，不把 metadata 已內嵌視為近景 module 已備妥：

```text
site-bolero-1934-BgXeuiXD.js
site-breezy-center-DvkL1nom.js
site-chensanding-pearl-milk-toJiE8bK.js
site-chiate-bakery-c4B85ikE.js
site-cisheng-temple-CAUhEvP9.js
site-dalongdong-baoan-temple-DjS06gDV.js
site-dalongdong-confucius-temple-BCbo4wxX.js
site-dongmen-market-BHhvjqYF.js
site-fubawang-pork-knuckle-CABJYCDA.js
site-fuhang-soymilk-Brx38OmX.js
site-gongguan-market-Ue9wl_Go.js
site-guling-book-street-CTW967hA.js
site-jianguo-brewery-2--nw9H8kS.js
site-jianguo-high-school-vKNlKfFh.js
site-jianguo-holiday-market-2-2-BkbE2xHa.js
site-jinfeng-lurou-sed-g6b0.js
site-judicial-yuan-DVm7IspG.js
site-kuangnan-wholesale-CdMVPXdb.js
site-legislative-yuan-BH2-FdEi.js
site-lin-an-tai-house-Cl12Bx6a.js
site-lindongfang-beef-DTdXF0i9.js
site-linhefa-oil-rice-CNMcu1oq.js
site-linjiang-market-j5DVB0yc.js
site-liting-bakery-SJ0XIpme.js
site-nanhai-botanical-history-museum-Cqz1r_43.js
site-nanjichang-market-DFgk6EeZ.js
site-national-central-library-UbqXrBgH.js
site-nishi-honganji-square-DqckGb_J.js
site-ntnu-Cp1V742u.js
site-ntue-campus-DP5wTdiG.js
site-qingtian-76-BrgYNfNG.js
site-regent-hotel-wqxFDpHj.js
site-shin-yieh-taiwanese-D9tUERbp.js
site-shuanglian-sweet-soup-ypfxrkzV.js
site-sunnyhills-minsheng-vaIigKhL.js
site-taipei-mosque-mk1AK1wH.js
site-taipei-public-library-main-aLKk2txv.js
site-tfg-high-school-DLqJWBX6.js
site-tianxia-beef-noodles-DV4nnR6L.js
site-treasure-hill-village-BnqkEf5h.js
site-water-museum-DWz28sMO.js
site-xinfangchun-CDuNuXEA.js
site-yansan-market-Uq9Y9hUs.js
```

另外 gap：world import 的 `postfx-pHdVmtPd.js`；`T/assets/content-Bs2Ca5A2.js`（**1,850,065 bytes**）所指 `build-Bz4uAL4f.js`、`build-CN7_0enk.js`、`build-Cx8EeQJB.js`、`build-nn2qgmtJ.js`、`register-DEjbkm8D.js` 皆缺。查找用 `import(`、`site-`、`./defs/`、`lot`、`claims`、`placement`、`anchors`、`proxy`、`build-`、`postfx`。沒有下載缺檔，不能宣稱原網頁場景可完整跑起來。

## 3. rail-3d 的 Blender／歷史建物資料與遠景網格

路徑前綴 **R = `Railway/site_archive_clean/rail-3d/`**。`R/blender-buildings.js` **3,240 bytes**；`R/landmark-catalog.js` **1,984 bytes**。兩組共 **47** 個 catalog entries，各有實際 `model.json` 與 `far.mesh.bin`，**全部 near.mesh.bin、near.glb、far.glb 缺檔**，catalog 的 hero thumbnail 也未見實檔。沒有 `.blend` 原始專案；不能靠 model.json 宣告的 GLB／sourceSnapshot path 推論檔案存在。

### 3.1 catalog 與 placement：逐欄位

| 檔案／鍵 | 型別、實值與語意 |
| --- | --- |
| `R/assets/blender-buildings-v1/catalog.json` | JSON array，**22** 筆、**14,267 bytes**。entry 的全部鍵如下；historic 為 **25** 筆、**2,799 bytes**，只含 id／name／category／metadata。 |
| `catalog[].id`／`name`／`category` | String；101 `taipei101-landmark-v1`／台北101／landmark。也有 station、historic；不含容量。 |
| `catalog[].metadata`／`thumbnail` | 相對路徑；101 `models/taipei101-landmark-v1/model.json`、`models/.../hero.png`。**實際 loader 忽略 metadata 路徑**，用 `entry.id+'/model.json'`；不可直接照 metadata 路徑載入。thumbnail 僅 blender 宣告，缺檔。 |
| `catalog[].files` | 僅 blender；鍵 model.json／near.mesh.bin／far.mesh.bin，各 `{sha256:String,bytes:Int}`；101 far **329,184**、near 宣告 **396,576**。缺檔大小不算入 App 預算。 |
| `R/assets/blender-buildings-v1/placement.json` root | **64,086 bytes**，`version:1,at:"2026-09-07",entries:{id:...}`。historic **37,232 bytes**、`version:2,entries`，沒有 at。 |
| `entries[id].anchor` | `[longitude,latitude]` Double；101 `[121.56455513294843,25.033946307135494]`，山佳 `[121.3927955832114,24.972590044833833]`。畫面／工具轉成世界位置，GameCore 不讀經緯度。 |
| `rotationDeg`／`orientationBasis`／`facadeBearingDeg` | Double／String／null；101 **89.03489627577518°**，山佳 **0°**。blender 的 orientationBasis **11 OSM-footprint-axis-fit + 11 ENU-baked**；historic **25 ENU-baked**。ENU-baked 已將部件擺向烘焙進頂點，不能再套用每部件校正一次。facadeBearingDeg 皆 null。 |
| `railElevationM` | 每筆 null；`buildingCatalog()` 要 placement 明確 null、source 不能有非 null railElevationM。建物不改軌道高程。 |
| `footprintExtentM` | 部分 blender placement 有 `[width,depth]`，台北大巨蛋 `[226.79431825770965,169.56251738607978]`；historic 無此鍵。 |
| `footprint` | GeoJSON FeatureCollection，features[] 的每筆有 type／properties／geometry。geometry 是 Polygon 的經緯度 rings；properties 用 component 與 `osmWay`，或 `osmType/osmId`（山佳 way **236033179**）。保留洞／封閉 ring／來源 ID，任意輪廓只在畫面和匯入。 |
| `sources[]` | `{url,use,license?,snapshot?}`；placement 山佳 OSM URL、`license:"ODbL-1.0"`。不能用單一 entry 的授權覆蓋整包。 |

### 3.2 model.json：全部頂層鍵與巢狀格式

兩组鍵的聯集如下；不存在的 optional key 不填假值。m／degrees／ENU 都是素材單位，浮點數不搬入 GameCore。每件大小見 §3.4。

| 鍵（型別） | 親眼看到的用途／數值 |
| --- | --- |
| `id,name`（String）、`version`（Int）、`category,kind`（String） | 101 version **1**、category landmark／kind taipei101；山佳 version **1**、historic／shanjia-old。placement historic version=2 是另一個版本，不混淆。 |
| `landmarkType`（String，部分）、`stationId`（String，部分）、`stationPoint`（array/null） | 對應地標／站區；都是資產識別，沒有遊戲 StationID／BuildingID。 |
| `anchor`（array/null）、`rotationDeg`（number，部分）、`facadeBearingDeg`（null） | metadata 本身的初始定位；真正載入時 anchor／rotation 被 placement 覆寫，不能兩次相加。 |
| `displayHeightM,realBuildingHeightM`（number/null，部分） | 101 **508／508**；不是地面海拔。historic 多以 sizeM／estimatedDimensionsM 高度估值，沒有 displayHeightM。 |
| `footprintWidthM,footprintDepthM`（number，部分）、`footprintQuality,heightQuality`（String，部分） | 101 **146.21840838439167／138.3828788680668**、OSM polygon／官方總高但分件比例示意。不可據此推入住量。 |
| `absoluteGroundAltitudeM,railElevationM,engineeringDimensionsM`（null，railElevationM 可省略） | absoluteGroundAltitudeM／engineeringDimensionsM 的47筆皆 null；railElevationM 是42筆 null、5筆缺鍵，loader 的 `source.railElevationM!=null` 也接受缺鍵。現地地面另取地形，沒有工程尺寸。null 不能當海拔0。 |
| `application`（String） | **"5.2.1 LTS"**。是來源標示，不證明本工作區具有該 Blender 版本或原始專案。 |
| `axes`（object） | `up:+Z,units:meters,groundAnchor:[0,0,0]`；local-facade 為 `right:+X,front:-Y`；ENU-baked 有 `east:+X,north:+Y,front:null`。所有鍵：up／right?／front／east?／north?／units／groundAnchor。 |
| `gltfAxes`（object）、`orientationMode`（String） | gltfAxes `{up:"+Y",toZUp:"rotateX(+PI/2)"}`；orientationMode local-facade 或 ENU-baked。bin 是 Z-up；輸出 iOS Y-up需一次明確軸向轉換。 |
| `bounds`（object）、`sizeM`（3 numbers） | bounds `{min:[x,y,z],max:[x,y,z]}`；101 min `[-68.29000091552734,-61.790000915527344,0]`、max `[68.29000091552734,61.790000915527344,508]`、sizeM `[136.5800018310547,123.58000183105469,508]`，與 footprint 尺寸不同。 |
| `lods`（object） | near／far，各鍵與 drawGroups 逐欄位見 §3.3；這一批沒有 mid。 |
| `sources`（array）、`sourceSnapshot`（object，部分） | sources[].url／use／license?／snapshot?；sourceSnapshot `{path,sha256}`，101 指 `source-layouts/taipei101-landmark-v1/metadata.json`，snapshot 本體缺。不是模型授權全文。 |
| `notes,features`（String arrays） | 外觀範圍與限制；101 明記立面／室內／結構非測繪，地表底座不改軌道。 |
| `placementStatus,status`（String，status 部分） | 101 existing-layout-unverified-facade；台北站 status simplified-exterior；山佳 calibrated-plan。不是入住／施工進度。 |
| `modelUse`（String）、`modelScope,excluded`（String arrays，部分） | map-exterior；台北站 modelScope 站房外殼／紅屋頂／柱列／中央採光區／簡化大廳；excluded 地下月台、真實地下軌道、地下街、機捷A1、北捷地下站體。 |
| `nativeObjectCount`（Int）、`sourcePhotosIncluded,operatorLogoIncluded`（Bool） | 101 **339**、山佳 **106**；本批照片與營運標誌 flags 均 false。不是 draw calls 計數，亦不代表引用照片可重新打包。 |
| `components`（object array） | 部件資訊，全部可見鍵：id／name／type?／anchor／rotationDeg／widthM?／depthM?／displayHeightM?／baseM?／heightQuality?／realBuildingHeightM?／railElevationM?／sign?／clock?／offsetENU?／footprintAreaM2?／placementStatus?／scaleXY?／basis?／facadeBearingDeg?／flatGroundOffsetM?／terrainAnchor?。高鐵桃園部件 width **121.821**、depth **73.541**、height **20**、base **0**、offsetENU `[33.339537620493644,-50.52592159982893,0]`、area **6981.04515864605**；山佳部件 rotation **18.75**、scaleXY `[.990233753320811,.9749101632827885]` 已烘焙。數值型欄位以m／m²／degrees使用，offsetENU是3數、scaleXY是2數、sign／clock是Bool；terrainAnchor是經緯度2數（泰安 `[120.74911150328163,24.32252234980541]`），flatGroundOffsetM **4.5 m**。 |
| `county`（String）、`priority`（Int）、`scope,railRelation`（String，historic） | 山佳 新北市／priority **1**／外觀估計非工程測繪／新舊站並存。 |
| `verifiedDimensionsM`（object）、`estimatedDimensionsM`（object） | verified 多為空 object；總統府 `{centralTowerHeightApprox:60,source:"https://www.president.gov.tw/Page/91"}`。estimated `{width,depth,height,basis}`，山佳 **20.73443603515625／15.23936128616333／6.8779425621032715 m**。 |
| `referenceReviewDate`（String/null）、`geometryStatus,referenceStatus,planCalibration`（String，部分） | 山佳 2026-09-12、plan-calibrated-exterior-estimated、partial-exterior-review；planCalibration 是校正方法文字。不能視為完整立面已核實。 |
| `reviewedPhotos`（array）、`pendingChecks,omittedUnlocatedComponents`（String arrays）、`mapEligible`（Bool） | reviewedPhotos 每項 `{url,page,viewedOn,scope}`；山佳 mapEligible true，待核高度／正面方向；omitted 舊月台／舊站棚。照片 URL 是參考，不是內含貼圖。 |
| `footprintReference`（object） | 所有鍵 osmType／osmId／name／url／timestamp／longSideM／shortSideM／source／license／scope／referenceFile；山佳 way **236033179**、2026-09-08T15:19:44Z、長 **17.26**／短 **6.1 m**、ODbL-1.0；referenceFile `source-layouts/shanjia-old.json` 缺。 |
| `completionReview`（object，部分） | `{date,changes:[String],precision}`；山佳 2026-09-12、補低平台，局部寬高仍外觀估計。 |
| `calibration`（object，historic） | `{version,basis,parts:[...],verticalDatum,sourceFile}`；山佳 version **2**、verticalDatum terrain-relative、sourceFile placements-source.json。parts 用 id／name／placementStatus／anchor／rotationDeg／scaleXY／basis／facadeBearingDeg，與 components 校正資訊相應；原校正檔未收錄。 |

### 3.3 far.mesh.bin、LOD 與 drawGroups

`buildBlenderBuilding(record,lod)` fetch `source.id+'/'+source.lods[lod].file`；以 vertexCount×24 檢查長度，可用 crypto.subtle 檢查 sha256。來源 `Float32Array(bytes)` 以主機 byte order讀；本批按 **little-endian Float32** 靜態解碼，47份數值皆 finite，stride／triangle count／draw ranges 相符，SHA-256 皆與 lod metadata 相同。這是檔案結構核對，沒有載入 Three.js 或驗證畫面。

| 格式／鍵 | 位元組與語意 |
| --- | --- |
| binary header／indices | **沒有 header、magic、UV、顏色、index buffer、骨架或動畫**；模型描述在 JSON。non-indexed triangle list，每連續3個頂點是三角形。檔案不可當成GLB。 |
| 每頂點 stride 24 | offset **0/4/8** 是 position x/y/z（公尺）；**12/16/20** 是 normal x/y/z，各 Float32。JS InterleavedBuffer stride **6 floats**；position offset0、normal offset3。Swift/Metal可用相同24 bytes vertex descriptor；不要因 Swift SIMD3 padding 誤讀成32 bytes。 |
| `lods.near/far.file`／`glb` | mesh.bin 路徑與宣告的 GLB 路徑；GLB皆缺。 |
| `sha256,glbSha256` | 各自64位十六進位字串，兩種格式的hash不可混用。只有現存bin能核對。 |
| `strideBytes,vertexCount,triangleCount,byteLength` | 本批stride **24**；byteLength=vertexCount×24；triangleCount=vertexCount/3。47個far共 **625,323 頂點／208,441 三角形／15,007,752 bytes**。 |
| `drawGroups[].component/name` | String或可轉字串的component ID；101 component main，name stone／cream／green／metal／gold。inspectBlenderBuilding 的 clearance 以 component字串完全比對；modelId命中則全棟。 |
| `drawGroups[].start/count` | 頂點索引與頂點數，**不是bytes或三角形數**。101 far `(0,36),(36,108),(144,684),(828,12432),(13260,456)`；總13716，皆3的倍數。 |
| `drawGroups[].color` | 3個線性RGB Float；101 green `[.05612849071621895,.25015828013420105,.2345505803823471]`。轉sRGB UI色需另換算，不直接當8bit RGB。 |
| `metalness/roughness` | 0…1 PBR Float；101 green **.2199999988079071／.30000001192092896**。來源 MeshStandardMaterial、DoubleSide；須對應目標材質的雙面／法線與PBR語意。 |
| `inspectBlenderBuilding(root,inspection,clearance,solidAppearance,modelId)` | 檢查模式 opacity **.24**，transparent／depthWrite隨檢查狀態切換；只影響顯示。每drawGroup一個mesh，來源frustumCulled=false，iOS不用照搬關掉剔除。 |

bin沒有貼圖UV，這批是純材質色的外觀網格。SceneKit 可直接建立 SCNGeometrySource／SCNGeometryElement，RealityKit 需轉 MeshDescriptor與submesh/material，Metal 可直接建 MTLBuffer與vertex descriptor；**「可重用資料」不代表 Apple framework 有這種bin的內建檔案loader**。可選離線輸出 USD／USDZ，或在畫面層寫這個小型loader（§8）。

### 3.4 逐件近景缺檔與現存大小

blender目錄現存共 **8,064,361 bytes**（far **7,756,272**）；historic共 **7,643,664**（far **7,251,480**）。合計 **15,708,025 bytes = 14.980 MiB**，含JSON等。近景宣告合計 **27,691,416 bytes = 26.408 MiB**，目前沒有檔案，若補齊同格式near再加far，僅bin就約 **40.721 MiB**，尚未算metadata／App／貼圖。以下列完所有缺近景的ID，也列實際model與far數值。

#### `blender-buildings-v1` 的逐件檔案盤點

路徑前綴：`Railway/site_archive_clean/rail-3d/assets/blender-buildings-v1/`。每列的近景路徑為 `<id>/near.mesh.bin`，全部缺檔；near bytes 只是 metadata 宣告，未計入現存素材量。

| id（子目錄） | model.json bytes | sizeM 高 m | far 頂點／drawGroups | far.mesh.bin bytes | near 宣告 bytes（缺檔） |
| --- | ---: | ---: | ---: | ---: | ---: |
| `taipei-dome` | 5,117 | 64.000000 | 12,774／4 | 306,576 | 349,776 |
| `taipei101-landmark-v1` | 6,562 | 508.000000 | 13,716／5 | 329,184 | 396,576 |
| `taipei-main-v1` | 7,245 | 48.000000 | 8,748／5 | 209,952 | 422,496 |
| `shinkong-landmark-v1` | 5,915 | 244.149994 | 1,788／4 | 42,912 | 118,944 |
| `cksmh-landmark-v1` | 5,642 | 70.000000 | 12,885／4 | 309,240 | 438,264 |
| `sunyatsen-landmark-v1` | 6,404 | 30.876314 | 15,288／5 | 366,912 | 441,792 |
| `national-theater` | 5,782 | 37.476315 | 24,276／5 | 582,624 | 732,384 |
| `national-concert-hall` | 5,803 | 35.476315 | 24,222／5 | 581,328 | 731,088 |
| `nanshan-plaza` | 5,871 | 272.010742 | 27,948／5 | 670,752 | 700,128 |
| `tower85-landmark-v1` | 4,335 | 378.000000 | 3,552／2 | 85,248 | 185,472 |
| `hsinchu-tra` | 5,914 | 20.000000 | 8,388／5 | 201,312 | 213,408 |
| `banqiao-v1` | 15,816 | 136.800003 | 8,766／12 | 210,384 | 731,664 |
| `hsinchu-hsr-v1` | 9,466 | 28.150000 | 9,174／6 | 220,176 | 454,464 |
| `hualien-v1` | 25,641 | 23.000000 | 12,777／20 | 306,648 | 848,952 |
| `kaohsiung-main-v1` | 16,146 | 64.000000 | 52,881／13 | 1,269,144 | 1,735,704 |
| `nangang-v1` | 18,937 | 167.000000 | 13,554／15 | 325,296 | 1,467,216 |
| `tainan-hsr-v1` | 14,413 | 27.055500 | 10,506／10 | 252,144 | 802,800 |
| `taitung-v1` | 16,129 | 14.150000 | 9,459／11 | 227,016 | 750,312 |
| `taoyuan-hsr-v1` | 9,374 | 30.150000 | 6,297／6 | 151,128 | 378,504 |
| `tra-taichung-v1` | 10,824 | 37.150002 | 18,942／8 | 454,608 | 877,392 |
| `xinwuri-complex-v1` | 18,949 | 31.150000 | 18,741／15 | 449,784 | 1,024,776 |
| `zuoying-complex-v1` | 9,451 | 32.150002 | 8,496／6 | 203,904 | 468,864 |

#### `historic-buildings-v2` 的逐件檔案盤點

路徑前綴：`Railway/site_archive_clean/rail-3d/assets/historic-buildings-v2/`。每列的近景路徑為 `<id>/near.mesh.bin`，全部缺檔；near bytes 只是 metadata 宣告，未計入現存素材量。

| id（子目錄） | model.json bytes | sizeM 高 m | far 頂點／drawGroups | far.mesh.bin bytes | near 宣告 bytes（缺檔） |
| --- | ---: | ---: | ---: | ---: | ---: |
| `shanjia-old` | 10,194 | 6.877943 | 1,566／6 | 37,584 | 58,608 |
| `qidu-old` | 10,982 | 6.277942 | 1,740／7 | 41,760 | 84,384 |
| `hexing-old` | 8,991 | 5.577942 | 1,098／6 | 26,352 | 37,008 |
| `guanshan-old` | 9,344 | 7.603923 | 3,204／6 | 76,896 | 121,248 |
| `zhutian-old` | 13,508 | 6.877943 | 3,216／9 | 77,184 | 168,480 |
| `presidential-office` | 10,406 | 60.000000 | 124,539／7 | 2,988,936 | 5,203,080 |
| `red-house` | 9,163 | 15.000000 | 7,530／6 | 180,720 | 323,280 |
| `hsinchu-prefecture` | 7,712 | 15.500000 | 16,734／5 | 401,616 | 712,368 |
| `taichung-prefecture` | 9,585 | 20.799999 | 16,794／5 | 403,056 | 735,984 |
| `taian-old` | 18,784 | 9.050000 | 4,980／12 | 119,520 | 152,064 |
| `taoyuan-warehouse` | 8,427 | 9.077942 | 3,738／6 | 89,712 | 164,880 |
| `erjie-granary` | 8,053 | 13.077942 | 3,120／4 | 74,880 | 128,160 |
| `changhua-roundhouse` | 10,127 | 10.425000 | 13,176／5 | 316,224 | 710,208 |
| `jingtong-coal` | 18,059 | 16.277943 | 4,998／14 | 119,952 | 209,808 |
| `takao-old` | 17,136 | 8.577942 | 6,270／14 | 150,480 | 235,440 |
| `luodong-forest` | 12,241 | 7.477942 | 4,080／9 | 97,920 | 220,608 |
| `railway-department` | 13,151 | 17.277943 | 22,350／10 | 536,400 | 943,920 |
| `hualien-railway` | 21,868 | 11.077942 | 7,596／17 | 182,304 | 413,568 |
| `longtian-warehouses` | 33,126 | 7.877943 | 3,666／30 | 87,984 | 186,768 |
| `checheng-wood` | 8,468 | 10.977942 | 7,584／5 | 182,016 | 368,064 |
| `beimen-old` | 9,127 | 6.677942 | 2,394／7 | 57,456 | 123,696 |
| `shengxing` | 11,827 | 6.533434 | 2,844／8 | 68,256 | 128,160 |
| `chiayi-sawmill` | 18,095 | 11.539455 | 18,210／14 | 437,040 | 786,960 |
| `dounan-warehouses` | 26,804 | 7.477942 | 2,988／24 | 71,712 | 133,920 |
| `qiaotou-sugar` | 26,975 | 32.000000 | 17,730／23 | 425,520 | 1,069,776 |


### 3.5 landmark-catalog.js

`landmarkCatalog` 是5筆靜態objects；全部欄位 `key,id,kind,name,heightM,widthM,depthM,center:[lng,lat],zoom,pitch,bearing,detail`。kind皆landmark、pitch皆 **55°**；height不是absolute海拔，也不是樓層／容量。

| key → id | height／width／depth m | center | zoom／bearing |
| --- | --- | --- | --- |
| taipei101 → taipei101-landmark-v1 | 508／146.21840838439167／138.3828788680668 | 121.56455513294843,25.033946307135494 | 15.6／−20 |
| cksmh → cksmh-landmark-v1 | 70／147.23775835877845／124.04207350062963 | 121.52171584846401,25.03468634617782 | 17.1／−20 |
| sunyatsen → sunyatsen-landmark-v1 | 30.4／112.37752366356055／108.57825851157736 | 121.56029177639518,25.040003828251123 | 17.1／−20 |
| shinkong → shinkong-landmark-v1 | 244.15／84.84382727439635／40.22211114309814 | 121.51531117744537,25.04598631427511 | 16.25／70 |
| tower85 → tower85-landmark-v1 | 378／142.7237180592633／67.699350330997 | 120.3001601108381,22.611616109117193 | 15.9／70 |

**gap／搜尋**：`near.mesh.bin`、`near.glb`、`far.glb`、`.blend`、`hero.png`、`source-layouts`、`placements-source.json`；以catalog／lods／sourceSnapshot/referenceFile指向的實際路徑核對，沒有近景或重建來源。metadata的品質說明與sources保留；既有far可以做Phase8候選，不承諾能從near缺檔還原原始外觀。

四處來源以完整詞搜尋地價／租金後，T另有外觀命中：`T/assets/content-Bs2Ca5A2.js` 的 `trade:"realestate"`、`category:"房屋仲介"`、names／menu（買屋、賣屋、租屋、捷運宅）、`weight:1/2`、`AL.realestate:"09:30-21:00"`，是店面樣式與營業時間；`T/assets/world-gYgJkZNf.js` 的 **"Tap to Rent"** 是借車畫面，shader的for-rent是出租鐵捲門外觀（關店用tile **24**，不顯示出租變體）。沒有租金、美分價格或房產交易。查找 `realestate`、完整詞 `rent`、`出租`、`trade`、`AL`、`bShopOpen`，不把招牌文案當經濟引擎。

## 4. Ci：建物圖層與地價／租金／開發搜尋

| 檔案／函式／鍵 | 實際看到的值與大小 | 對6c／8的意義 |
| --- | --- | --- |
| `Ci/reference_snapshot/external/openfreemap-tiles/styles/liberty.json`：layers `building`、`building-3d` | **43,079 bytes**；2D fill 的 source openmaptiles、source-layer building、minzoom **13**、maxzoom **14**；3D fill-extrusion minzoom **14**，height `get(render_height)`、base `get(render_min_height)`、opacity **.8**，色 hsl(35,8%,85%)。 | 高度直接來自圖磚欄位，無樓層→容量公式、也未在此expression加後備高度。可作畫面extrusion adapter；不把圖磚當存檔建物。 |
| `Ci/reference_snapshot/external/openfreemap-tiles/planet.json`：vector_layers[id=building] | **19,254 bytes**；fields `colour:String,hide_3d:Boolean,render_height:Number,render_min_height:Number`；minzoom **13**、maxzoom **14**。 | 是圖磚schema，建物本體圖磚沒在此檔；hide_3d 是呈現旗標。高度與底高以地圖extrusion的公尺語意使用，不是居民、租金或造價。 |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`：`initOsmMapEngine`、`metroEnsureNonHongKongOsmBuilding3d` | 全檔 **4,378,323 bytes**；呼叫 `metroCreateOsmMapLikeSingaporeDemo`，傳 `pitch:0`、`initialBuilding3dEnabled:!香港2D模式`，其他城市以 `setBuilding3dEnabled(true)` 保持3D。 | 建物顯示開關；外部 `metroCreateOsmMapLikeSingaporeDemo/setBuilding3dEnabled` 定義未收錄（只找到呼叫，gap），不能假稱完整renderer已取得。 |
| 同 app：`mlLayerBeforeBuilding3d` | 優先找 building-3d，再找fill-extrusion且id符合building/3d/extrud，最後找非metro-ridership-hex-ml的extrusion。 | 疊圖順序查詢，沒有建立建物或開發人口。 |
| 同 app：`renderRidershipFlowCirclesMaplibre`／`renderHsrStationFlowCirclesMaplibre` | fill-extrusion使用 properties `extrudeH`，base **0**、opacity **.92／.9**；根據流量正規化產生高度，分別為一般路網與高鐵站客流。 | **是客流統計柱狀圖，不是建物高度**。不能將每個fill-extrusion命中都算為建物。 |
| `Ci/reference_snapshot/lib/virtual_island_city__q_21ffa7f6ae58fc9e.js`：內部 `M`、`w` | **13,906 bytes**；id `virtual-island-original-buildings-v10`、source-layer **buildings**（複數）、type **fill**、minzoom **12**；`u` = office／retail／industrial／institution選色，opacity在zoom12為 **.4**、13.5為 **.95**。 | 此包虛擬島建物是2D；沒有從這個圖層讀height／樓層／入住容量。不能把 `u:retail` 當作工作人數。 |
| 同 island：`METRO_VIRTUAL_ISLAND_SEMANTIC_MAP_URL`／`REFERENCE_MAP_URL` | 同一 `/data/virtual-island/tiles/city.pmtiles?v=20260905-osm-city-v15`；landuse.kind cbd／industrial／villa／institution／newtown。 | **gap：city.pmtiles本體缺**，無法盤點要素量、真實高度或用途數量。 |

**地價／租金／房地產／開發規則為 gap**：在 `Ci/reference_snapshot/` 的js/json/html搜尋 `landValue`、`land_value`、`landPrice`、`land_price`、`propertyValue`、`realEstate`、`real estate`、`rent`、`rental`、`地價/地价`、`租金`、`房地產/房地产`、`開發/开发`、`development`、`building`、`render_height`、`render_min_height`、`fill-extrusion`。沒有查到遊戲土地定價、租金結算、房產交易、建物容量或車站驅動開發引擎。寬搜rent／develop會命中current／parent／SDK函式或網站開發文字；按完整詞再查、閱讀應用bundle命中後，app的「火炬开发区」是CITIES分區名，`voyager-about` 的「开发团队」是網站介紹，皆不是開發規則。

另外依 `CLAUDE.md` 查 `Railway/railway_game_reference_clean/00_READ_ME_FIRST.md`、`01_MIGRATION_MAP.md`（**8,192 bytes**）§9／§10與相關source-path清單：town_cmd.cpp／industry_cmd.cpp只有路徑，沒有原始碼／建物容量／地價公式。關鍵字 `house`、`building`、`town`、`growth`、`land`、`value`、`industry`、`terraform`；沒有用外部OpenTTD知識補數值。

## 5. 6c建物與容量提案（全部容量數值都是gap→原生）

### 5.1 權威表示與命令

建議 `Sources/GameCore/City/Building.swift` 的 `Building` 只存 `id`、`kind`（普通開發／既有存量）、`use`、`density`、`occupiedCells:[CellKey(row,column)]`；規則表用固定 `buildingRulesVersion`。普通建物的容量、樓層與名義高度由kind／use／density的整數表推導，**不存PlanPoint、rotation、lot輪廓、模型ID、mesh或LOD**。佔格可以是L形等格集合，任意細部輪廓在畫面；同一個64 m開發單元可畫多棟來源的小公寓與商店，不要求每棟4.4 m店面各佔64 m格。

`GameWorld.placeBuilding/replaceBuilding/removeBuilding` 名稱僅提案：依固定順序驗證ID、類型／密度、非空且唯一的格、完整bounds、相同用途、保留格、既有佔用、每格容量；全部通過後一次提交。多格建物建議要求上下左右連通（格之間可有洞），每格只能有一個權威建物；裝飾地標不佔容量、不排擠居民。查詢index可推導，但不能另存會獨立變動的容量總量。格排序row→column、建物排序ID，失敗不配發ID、不修改任何格。

可建遮罩／道路保留資料尚是gap：6a只列有人格，**沒列出的格不等於水、道路或公園**。第一個容量PR不假設已經有地形禁建資料；沒有遮罩的空白情境視為情境指定可建，實景模型先作裝飾。若後續啟用保留格，必須把它作為核心可驗證的固定整數輸入；不能直接用 `surfaceAt` 或 MapKit／queryRenderedFeatures 在每次命令判斷。

放在已有LandCell的普通建物必須use相符，容量不得小於居民／就業。放在無LandCell的格可以是空置建物，等6b移入才產生土地紀錄；其用途由建物查詢取得。用途修改命令要一起驗證，不能在兩份use之間失配。新建物不放最後不足64 m的邊格，避免按4096 m²計容量卻實際只有狹窄邊帶；6a已有人口的邊格保留為既有存量。

### 5.2 用途×四級密度表

來源沒有住宅面積／每人面積／就業面積／容積率，以下**全部為gap的建議值**。用透明的整數換算給一組可調初值：每格有效樓板面積 `4096×3/8 = 1536 m²`（含未建空間與退縮），住宅每居民 **48 m²**、工作每職位 **32 m²**（含公共空間／設備）。用途是主要用途，允許6a已有的商業／辦公居民；R把樓板7/8分給住宅、C為1/4、O為1/8，其餘工作。不增加學校／工業／公園等LandUse。

密度 D1／D2／D3／D4 的名義樓層為 **2／6／18／40**，參考shophouse、apt、tower與信義上端的外觀跨度，但選這四個代表值是原生政策。住宅樓高 **3 m = 192單位**，商業／辦公 **4 m = 256單位**；與來源3.3／3.9 m外觀不同，不聲稱是移植常數。

| 主要用途×密度 | 建議type key／外觀 | 每格居民容量 | 每格就業容量 | 名義樓層 | 名義高m／世界單位 |
| --- | --- | ---: | ---: | ---: | ---: |
| residential D1 | r-low／低層住宅群 | 56 | 12 | 2 | 6／384 |
| residential D2 | r-mid／公寓群 | 168 | 36 | 6 | 18／1152 |
| residential D3 | r-high／住宅大樓 | 504 | 108 | 18 | 54／3456 |
| residential D4 | r-tower／高密住宅 | 1120 | 240 | 40 | 120／7680 |
| commercial D1 | c-low／店屋群 | 16 | 72 | 2 | 8／512 |
| commercial D2 | c-mid／商業街廓 | 48 | 216 | 6 | 24／1536 |
| commercial D3 | c-high／商場與混合住宅 | 144 | 648 | 18 | 72／4608 |
| commercial D4 | c-tower／高密商業 | 320 | 1440 | 40 | 160／10240 |
| office D1 | o-low／低層辦公 | 8 | 84 | 2 | 8／512 |
| office D2 | o-mid／辦公街廓 | 24 | 252 | 6 | 24／1536 |
| office D3 | o-high／辦公大樓 | 72 | 756 | 18 | 72／4608 |
| office D4 | o-tower／高密辦公 | 160 | 1680 | 40 | 160／10240 |

表格可重算：`G=1536×floors`，住宅配比 `p=7／2／1`（分母8，依R/C/O）；`residentCap=G×p/8/48`，`jobCap=G×(8-p)/8/32`，每步非負整除向下。此組數值整除無餘數；多格建物每格各算一次，不把總容量都灌到anchor格。最大普通容量1120／1680遠低於Land.maximumPerCell=100000，全圖上限乘積在Int64內，解碼仍先驗證後計算。升級只加容量、不直接生居民／工作；§7的6b日更新才填入。

這些是遊戲平衡用容量，不是真實城市人口密度，也不推算參考地標的員工。例如101高508 m、地標catalog kind並沒有等於o-tower；地標若要具有容量，須作者選普通型別與格清單，且不能與同格既有容量重複。

### 5.3 既有土地容量、拆除與相容性

不能把初始人口裁到D1，也不能把每格初始存量與新建物加總兩次。建議啟用6c時逐格選**同用途、同時容納現有居民與就業的最低密度**，建立一格建物；例如中心住宅130人選r-mid，核心辦公390工作／32居民選o-high。這是容量初始化，不搬動任何居民／工作，沒有推論真實建物高度。

若四級皆容納不下、或是世界邊格，建立 `existingStock`：每格明存一次 `residentCapacity=max(existingResidents,選定表容量)`、`jobCapacity=max(existingJobs,選定表容量)`，各不超100000；不足完整格的邊格用現有人數作底線。這是**尚未遷移的抽象存量（gap→政策）**，不另加普通建物容量、不假畫40樓替代真實建物。一般建物沒有任意cap覆寫；existingStock只由明確匯入／遷移建立，不能讓玩家以此逃過普通容量限制。

替換existingStock時要刪同格的舊存量，再放足夠容量的新建物；總居民／工作不變。建議第一版**有人或工作機會時拒絕拆除／縮小容量**，空置才可拆；不自動逐出、不搬到旁格、不靜默刪人。未來若作者要搬遷，需單獨原子命令與移出帳。跨格建物不可藉總容量足夠而容許某格超額，避免6b的逐格成長契約被破壞。

舊存檔：v11以前沒有土地照legacy；土地版缺buildings的世界只有明確啟用容量時才依以上政策初始化。重新讀存檔不能再生一次存量；既有存量與buildingRulesVersion須保存，新版本由作者依當時main決定，不搶先指定13。現行fixtures不改，後續實作以新增保存例／golden釘住這項遷移。

## 6. 地價：即時整數推導提案（gap→原生）

### 6.1 輸入與規約

建議 `City/LandValue.swift` 的 `GameWorld.landValue(at:CellKey)` 回傳帶型別的 `centsPerSquareMetre:Int64` 與可解釋的分項；不寫price到Land、建物、日歷或存檔。沒有交易／租金／維護費用。普通用途取建物use，無建物取LandCell.use；兩者都有時已由不變量要求相同。沒有建物也沒人口的可建格視為vacant估值用途（不是新增LandUse enum）；保留／水域格為0。

| 輸入 | 建議定義與整數界線 |
| --- | --- |
| 800 m腹地內可用服務 | 對格中心 `d² < 51_200² = 2_621_440_000` 的各站，距離權重 `w=1000-floor(d²×1000/R²)`，範圍內1…1000。closed／無可用服務的站不貢獻。這個平方距離權重是原生，來源沒有地價距離衰減。 |
| 站的服務品質q | 讀6b已保存的**最近完成一日**服務量測：`q=min(1000,floor(served×1000/max(1,potentialTrips)))`；potentialTrips=0時定義q=0，served是原起站旅客完成旅程、與6b歸屬一致。沒有6b日量測時q=0。只存城市服務量測，不存地價歷史；查詢以現有量測即時計算。不能拿今日累計arrived除今天基礎旅次。 |
| 格的服務分S | `S=max(floor(w×q/1000))`，0…1000；取最佳站，不把兩個同等站服務直接加倍。若6b採另一服務歸屬政策，需共用其公開結果，而非6c另造客流帳。 |
| 可達車站數A | 從800 m內目前可用起站的Passenger可行旅程，取可達迄站ID聯集，排除這些起站自身、封站與無可用服務站，去重後 `A=min(count,5)`。由現行路徑／服務查詢推導，不讀TrackTraversal／TrainMovement。與決策70同樣cap5，**聯集規約是新提案**，不能把6a catchment總量當可達站數。 |
| 用途基準B | vacant **1000**、residential **2000**、commercial **3000**、office **3500** 美分/m²。都是遊戲相對價初值，非台灣公告地價／市場成交價。 |
| 密度係數D | D1 **1000**、D2 **1250**、D3 **1600**、D4 **2000**（分母1000）；vacant取1000，existingStock用初始化選定密度但不由人數每次重猜。 |

服務品質不是即時每幀改寫；它是6b最近完成日的量測。可達性／用途／密度一改，查詢立即反映；次日服務量測更新，查詢自然改變。沒有平滑、價格快取權威或往日價格。若作者希望日內服務敏感，建議之後獨立改量測契約，仍不存price歷史。

### 6.2 公式、範圍與可重算例

```
若格不可建：value = 0
base = floor(B × D / 1000)
servicePremium = 15 × S
accessPremium = 1000 × A
value = clamp(base + servicePremium + accessPremium, 500, 50_000)
```

單位為**美分／m²**；可建格下限500、上限50000（$5…$500/m²）。B/D、係數15、每站1000、上下界皆gap建議值：服務滿分加$150/m²、最多5可達站加$50/m²，使鐵路服務能明顯提高價值，並以密度2倍內控制高樓的基準價差。這些不是建造費，不納入公司帳本。實際這組初值的最大普通價是office D4 **27,000**，50000是未來仍需遵守的防護上限；不假稱目前能到50000。

例：住宅D2，距一站 **400 m=25,600單位**，站q=800，可達3站：`w=750,S=600,base=2500,value=2500+9000+3000=14_500`，即 **$145/m²**。沒有服務、沒有可達站的同格價 **2500**；office D4滿服務、5站 **7000+15000+5000=27000**。同樣命令／世界，換模型或相機不改這個數字。

`d²×1000` 在世界範圍內小於2^51；B×D≤7,000,000；w×q≤1,000,000；value≤50000。q的served來自累計差值，**不能直接假定乘1000永不溢位**：6b需有界日計數，或用checked／WideInteger／先除後餘數的精確算式，壞輸入拒絕且不改世界。A只需集合去重後排序計數，Dictionary/Set的迭代不決定結果。

若Phase7之後要把單價乘面積，完整64 m格 `4096×value` 最大 **204,800,000美分**，全圖上限 **13,421,772,800,000美分**，仍在Int64；但那時要另訂地界裁切、交易／估值時間與租金政策。這里不先記一筆建造或地產收入。

## 7. 與6b土地成長的接點

6b會讓服務好的腹地內居民／就業成長；6c只提供 `buildingCapacity(at:) -> {residents,jobs}` 與 `remainingCapacity(at:)`。普通建物的多格容量逐格限制；existingStock替代過渡容量。沒有建物也沒有既有存量的格，容量 **0**，不能只因在車站腹地就生人。

固定午夜順序建議：

1. 6b凍結昨日土地、建物容量、服務與重疊腹地配額的同一份快照；日量測仍由Passenger穩定查詢取得，沒有去控制列車。
2. 6b算每格居民／工作的候選增量與千分比餘數；6c取同格cap，正增量夾到 `max(0,cap-current)`。例如r-mid **167/168**，候選+3，只能+1；滿168時+0。就業另算，不能把剩餘住房借給工作。
3. 未放入的候選成長記為「容量不足」，**不存成未來無限排隊的移入量**；小數餘數僅保留分母內的不足一人部分。滿容量後升級，從新一天服務增量重新開始，不能一次釋出累積十年的候選人口。這是需與6b協調的原生政策。
4. 全部格按固定CellKey序一次提交；6b重建今天的土地需求、星期／事件／OD。legacy世界继續決策70；land世界不再乘一次station townGrowth。地價是其後的唯讀查詢，不回頭增加同日成長。

6b的無服務衰退與人口底線仍由6b決定；6c不重訂成長率。玩家升級到高密度或在空格放建物，只開放容納空間，不能把cap當當天人口或工作總量；地價也不自動決定當天升級，避免成長→價→密度→成長的同日循環。

需共用的接口草案：`City/LandService.swift` 提供站可用性、可達迄站ID與昨日服務品質；`City/LandGrowth.swift` 在夾限前查 `BuildingCapacity`。6b若已用別的檔名，就接已存在的接口，不為本研究另造service/manager。`setLand`／用途變更／建物替換都要使土地需求計畫失效；容量純查詢不改OD餘數。

後續驗收（此研究未執行）：滿容量／剩1位／多格／重疊站／無站／封站／升級後次日／存讀／午夜idle、批次與任意切分推進得到相同世界；居民與就業只在Land記錄一次，模型載入失敗與LOD切換不改cap；遷移保留所有土地總量，拒絕有人拆除時完整原子。地價公式要獨立手算上例與800 m邊界，並驗證存讀與換錨點的模擬一致性。

## 8. Phase8素材管線：現存角色、貼圖、動畫與iOS轉換

### 8.1 T/source實際檔案與壓縮格式

T的全樹 **102檔／20,962,045 bytes = 19.991 MiB**：35 JS **9,167,633**；8 GLB **3,209,176**；45 PNG **6,132,453**；6 WebP **1,188,840**；WASM **527,333**；2 bin **441,575**（動畫439720＋manifest.webmanifest.bin1855）；CSS **102,622**、HTML **128,266**、wssrc **48,719**、JSON **15,020**、SVG **408**。這不是一包建物GLB；**8個GLB全部是角色**。

`T/avatars/manifest.json` **15,020 bytes** 有17 avatar entries；totalBytes宣告 **4,935,292**、fallbackTotalBytes **3,816,920**，textureFormat ktx2、transcoder basis/。實際只有下表8件；現存sum **3,209,176**，不能拿manifest總量當可用檔案量。

| GLB 路徑（`source/avatars/`） | bytes | 三角形（manifest） | joints（GLB） | embedded KTX2 bytes（manifest） | source／head |
| --- | ---: | ---: | ---: | ---: | --- |
| `jie.glb` | 981,936 | 6,732 | 80 | 892,164 | `Male_Adult_10`／`Male_Adult_10` |
| `wen.glb` | 1,010,100 | 8,612 | 81 | 899,856 | `Female_Adult_04`／`Sports_Female_02` |
| `student-m.glb` | 191,944 | 3,517 | 20 | 149,395 | `Male_Adult_01`／`Business_Male_02` |
| `student-f.glb` | 204,264 | 4,380 | 20 | 154,311 | `Female_Adult_01`／`Female_Adult_11` |
| `casual-m.glb` | 198,600 | 3,709 | 20 | 155,441 | `Male_Adult_09`／`Male_Adult_09` |
| `casual-f.glb` | 217,792 | 4,792 | 20 | 159,299 | `Female_Adult_03`／`Female_Adult_03` |
| `elder-m.glb` | 189,592 | 3,490 | 20 | 148,000 | `Male_Adult_03`／`Business_Male_02` |
| `elder-f.glb` | 214,948 | 4,452 | 20 | 162,739 | `Female_Adult_14`／`Female_Adult_11` |

全部GLB header version **2**、JSON asset.version **2.0**，generator標示Blender4.5＋glTF-Transform4.5＋KTX-Software v4.4.2；各1 mesh、1 skin、**animations[]為0**。extensionsUsed與extensionsRequired均含 **EXT_meshopt_compression／KHR_mesh_quantization／KHR_texture_basisu**；images內嵌 `image/ktx2`。manifest寫wen bones=80，但實際GLB skin.joints是**81**，轉換須以實際骨架為準。

| 素材／鍵 | 格式、大小與實值 | iOS處理 |
| --- | --- | --- |
| `T/avatars/manifest.json` 的maps | 英雄7張：body-color1024²、mask256²、normal512²；head-color2048×1024、mask256×128、normal512×256；hair-color1024²。群眾3張：atlas-color1536×512、mask192×64、normal384×128。color ETC1S（hair／atlas帶alpha），mask／normal UASTC。 | 不是獨立png；需從GLB bufferView取KTX2，維持baseColor sRGB、mask／normal線性與channel語意。 |
| 同maps.bytes與KTX2 header | 8件嵌入貼圖合計 **2,721,205 bytes**；KTX2 vkFormat **0**、typeSize **1**、faceCount **1**；ETC1S supercompressionScheme **1**、UASTC **2**，已有 **8–12** mip levels。jie body-color **145,195**、head-color **286,122**、hair-color **158,101** bytes；完整jie textureBytes **892,164**。 | Basis Universal／UASTC不是GPU可直接吃的ASTC；要轉碼或離線解碼再轉ASTC／目標USD貼圖。輸出保留所有mips，透明髮片測試alpha。 |
| `T/avatars/basis/basis_transcoder.js`／`.wasm` | **57,529／527,333 bytes**，WASM magic `\0asm` version1；JS是Emscripten loader。`T/assets/avatar-CUFURxPX.js` **112,468 bytes** 含GLTFLoader／KTX2Loader／meshopt decoder。 | JS＋WASM不是Swift framework可直接link的native轉碼器；建議離線處理。Metal自訂loader路線才考慮native Basis／meshoptimizer，不把WebWorkers與JS載入器搬進GameCore。 |
| `T/assets/anim-CQkLTvTS.bin`；`clips-Cb5uFd0j.js` | bin **439,720**、JS **2,708**；AnimLibrary／Clip的格式如下。`animator-DGt1NqrS.js` **26,675**、`rig-BjRdQXtM.js` **614**、`avatar`的Rocketbox骨架adapter。 | 動畫獨立於GLB，必須還原／retarget後輸出skeletal animation；不能只用GLB轉USDZ就假稱動畫會出現。 |
| `T/title/*.webp` | menu-2560 **325,032**（2560×1440）、menu-1600 **171,522**（1600×900）、menu-portrait **163,788**（960×1706）、menu-phone **168,866**（1600×738）、loader-1600 **181,686**（1600×900）、loader-portrait **177,946**（960×1706）。 | 只是標題／載入畫面，不是建物表面貼圖。原生asset流程先轉PNG／HEIF並核對色彩與尺寸，或使用明確WebP decoder；不假定所有SceneKit／RealityKit材質loader都讀WebP。 |
| `T/splash/launch-*.png`、`icons/*.png`、`_favicon.png`、`icons/icon.svg` | 共45 PNG **6,132,453**；42張launch檔名即目標解析度，含1125×2436、2064×2752等；apple-touch-icon180² RGB、favicon32² RGBA；SVG **408 bytes**。 | PNG可用原生圖片loader；不用把42種Web/PWA啟動圖全部塞進iOS bundle。SVG要由asset工具轉成支援的向量／點陣輸出；它們不是3D貼圖。 |

avatar gap：`jie-lod1.glb`（宣告186800）、`wen-lod1.glb`（202992）、`office-m.glb`（185368）、`office-m2.glb`（193296）、`office-f.glb`（212612）、`vendor.glb`（167648）、`uncle.glb`（208072）、`auntie.glb`（211236）、`police.glb`（158092）共9件缺；17個 `*.webp.glb` fallback全部缺。查找 `manifest`、`fallback`、`lod1`、`.glb`、`image/ktx2`、`extensionsRequired`、`textures`、`gpuBytes`，核對header與檔案存在，不由宣告補檔。

### 8.2 ANM1動畫逐欄位

| 位置／鍵 | 實際格式與值 |
| --- | --- |
| bytes0…3、4…7 | ASCII **ANM1**；UInt32LE JSON長 **10,852**。JSON自offset8開始，補到4bytes對齊，Int16LE樣本區從 **10,860** 起。 |
| header | `{version:1,fps:30,nk:19,per:82,hipY:.9768000000000001,rig:"jie",legLen:.8452635043916361,clips:[...]}`。AnimLibrary強制nk=19；總樣本區 **428,860 bytes／214,430 Int16**。 |
| clips[].name/n/loop/offset | 名稱／幀數／Bool／Int16元素offset（**不是byte offset**）；idle n150 offset0 loop；walk n35 offset39524 loop；run n21 offset46740 loop；sprint n17 offset207214 loop；strafe_l n35 offset211560 loop。共 **43 clips**。 |
| clips[].contact | base64每幀contact byte，供contactAt／contactW bit判斷；walk35幀，解碼後35bytes。 |
| clips[].speed/dur/cycle/phaseR/vx/vz/move/tags/src/events | optional移動、標籤與來源資訊；walk speed **1.1058812472688282**、run **4.124087837074677**；jump events takeoff **.3455**、land **.5636**（正規化時間）。檔案含戰鬥／舞蹈等clips，Phase8第一批只需idle/walk等候選，不把事件當遊戲打擊規則。 |
| 每幀82個Int16 | 0…75是 **19個四元數×4**；Clip.sample做符號同向、線性內插後正規化。76…78位置乘 **1e-4**；79、80 root x/z乘 **.001**；81 root yaw除 **32767**再乘 **4π**。不可把全部Int16統一除32767。 |
| frame／duration | loop duration=n/fps，非loop `max(1,n-1)/fps`；loop frame取模，非loop夾端。root與骨架retarget需接avatar的骨架名稱／rest pose。 |

43個clip實際名稱與幀數：idle150、idle_look163、idle_stretch169、walk35、walk_fast29、jog24、run21、walk_back38、strafe_r35、stop_run48、stop_walk45、dodge_l36、jump56、jump_run37、jump_over40、drop_land52、roll49、jab24、cross24、hook23、uppercut19、kick35、fight_idle48、knockdown_back47、knockdown_front34、getup_back121、getup_front115、stagger43、sit_down73、sit_idle40、stand_up55、push69、wave118、cheer52、point55、bow88、clap106、dance_macarena124、dance_chicken108、dance_twist79、sprint17、dodge_r36、strafe_l35。播放與root motion只作畫面，不能回寫人口或列車位置。

### 8.3 建議iOS管線與檔案大小

| 來源類型 | SceneKit | RealityKit | Metal | 建議步驟 |
| --- | --- | --- | --- | --- |
| 47 far.mesh.bin＋model/placement | 自訂SCNGeometry，PBR材質；bin不具內建loader | MeshDescriptor／submesh adapter，或離線USDZ | 可沿用24bytes緩衝與draw ranges；自訂shader/material | 驗hash／bounds／drawGroups→米尺度／Z-up轉目標軸→按placement一次定位→material mapping→批次／實例／LOD。保留源JSON與轉換manifest，普通容量不用這些浮點數。 |
| 3現存site／proxy、build JS | 幾何／材質重建或離線烘焙 | 同左，再轉USD／USDZ | 重建mesh／atlas，Three shader要改寫 | JS不是Swift可直接載入的模型；先以完整依賴產生網格與atlas，再輸出iOS格式。來源缺模組時可從現存proxy做低細節外觀，不稱為原近景。 |
| 8角色GLB＋KTX2 | 無內建完整GLB／meshopt／basisu支援，需離線／loader | 一般走USD／USDZ，不直接吃這些required extensions | 自訂glTF／meshopt解碼、頂點解量化、native轉碼／骨架 | 解EXT_meshopt→展開quantization→貼圖Basis/UASTC解碼／ASTC或目標USD貼圖→骨架rest pose→ANM1 retarget/bake→USD/USDA/USDC/USDZ或renderer自訂資料。 |
| PNG／WebP／SVG | PNG可直接圖片使用；其他先轉換／decoder | 同左，與幾何loader分開 | 解碼後upload；ASTC壓縮texture用匹配格式 | 材質sRGB/linear、alpha premultiplication、normal方向、mips分開核對。 |

RealityKit／SceneKit的選擇不在這份研究鎖定；先用同一份代表素材比較，依Phase8量測決定。軸向建議Z-up ENU的 `(east,north,up)` 轉iOS常用Y-up `(east,up,-north)`，右手座標與normal一起轉，local-facade先依一次placement旋轉；與本遊戲平面y向南的世界位置adapter也要明確。模型公尺與GameCore世界單位僅在快照邊界乘／除64，**Float32網格不為了模擬而量化成整數**。

第一批建議47個far外觀候選＋普通用途程序幾何，不先bundle整個T網站。兩組現存建物檔 **14.980 MiB**，加8個現存角色GLB **3.061 MiB**，原格式約 **18.041 MiB**；若直接加整個T樹，則約 **34.971 MiB**，其中Web啟動圖／JS就有大量不需要的內容。轉成USDZ／解量化頂點／ASTC後大小可能變大，尚未實際轉換，不能宣稱會節省多少IPA。

manifest對8件現存角色的 `gpuBytes` 加總 **19,279,808 bytes**，fallbackGpuBytes宣告 **103,459,496 bytes**；這是**來源估算**，不是本次iOS量測。英雄單件6247984、群眾1130640；轉PNG或RGBA可能顯著放大GPU佔用。遠景625323頂點若同時全載至少14.313MiB原vertex payload，還有material／framework複製；drawGroup逐件mesh會增加draw calls，不能只算檔案bytes就保證效能。

產物manifest建議每件存source repo SHA、source path/hash/bytes、轉換工具版本／參數、axis/unit、輸出hash/bytes、vertex/material counts、LOD可用性、license／source標示。loader先驗這份契約；可見分塊、screen-size LOD、相同材質合批、普通建物instancing／遠景proxy；性能設定只影響畫面。缺near時放大仍用far或明示低細節後備，不能產生來源不存在的模型資料。

### 8.4 授權與來源要求

依CLAUDE.md，作者提供的Ci／Railway資料視為授權可移植來源，不另發明整包禁用政策；仍保留特定素材明示條款。

- **Microsoft Rocketbox**：`T/avatars/manifest.json.license`及8份GLB asset.copyright明記 **MIT License、Copyright (c) 2020 Microsoft**，含原avatar來源與頭部來源。manifest指 `CREDITS.md / LICENSE-ROCKETBOX.txt`，GLB指LICENSE-ROCKETBOX.txt，**本包兩檔均缺（gap）**。發佈素材前補入正確MIT全文與copyright，轉換不能刪掉來源標示；這不是要求重買模型。
- **OSM建物輪廓**：兩組model.sources中有 **91個ODbL-1.0 source標示（49＋42）**；另89個source entry未寫license（25＋64），多為官方／觀光／外觀參考頁，不能把「沒寫license」全部叫成未授權模型。保留每件sources及placement/footprintReference的OSM標示；顯示 © OpenStreetMap contributors與ODbL連結，若發佈衍生輪廓資料庫，提供對應資料與同授權。材質網格是來源作者外觀建模，照片／商標flags為false，不把參考照片URL當可打包貼圖。
- **Basis／meshopt／Three.js**：`T/avatars/basis/*`、`T/assets/avatar...`、`T/assets/three-DoD3b_mB.js`（**737,923 bytes**）的現存檔未找到完整license/copyright告示；只辨認到技術名稱，**不能以記憶替這個bundle宣告MIT或Apache版本（gap）**。若採native dependency，選定確切版本後附其實際LICENSE／NOTICE；若只離線轉出自己的資料，仍記錄工具與輸出來源，依所用工具真正條款處理。R/vendor/three.module.js的license不能替T所有bundle一概背書。
- **site／標題／atlas／動畫**：本包沒有另外的逐素材license文件；來源作者授權可用的前提仍成立。維持site source、動畫clips.src等來源，對明示第三方項再補告示；沒有證據要求任意替換角色或場景。PNG／WebP與程序生成atlas不因可解碼就自動有新的授權。
- **實景背景**：決策50的MapKit標誌／法律連結與資料限制照原決策；自有建物／OSM素材可畫在背景上，但不擷取Apple建物、地形或搜尋結果做可保存模型資料庫。OpenFreeMap樣式／圖磚契約與iOS自有模型來源分開記錄。

授權gap搜尋：`LICENSE`、`LICENCE`、`NOTICE`、`CREDITS`、`copyright`、`license`、`Rocketbox`、`Microsoft`、`ODbL`、`sources`、`reviewedPhotos`、`sourcePhotosIncluded`、`operatorLogoIncluded`。只盤點檔案內標示，沒有逐站開網站、下載照片或重查外部條款。

## 9. 參考對照表草案（目標名稱尚未採納）

| 參考檔案／函式／鍵 | 目標檔案／函式草案 | 定點比例與保留／改變 |
| --- | --- | --- |
| `T/assets/world-gYgJkZNf.js`：DO／lO／UD／WO、RD／zD／VD／HD | `tools/building-assets/import_taipei_scene.*` 產生佔格／保留格；`Sources/GameCore/City/BuildingPlacement.swift`：validateOccupiedCells；GameWorld.placeBuilding | 米→64世界單位；cell4096；小距離量化見§2.1。來源旋轉矩形／3×3細查不進核心；格化差異需明示。 |
| `T/assets/engine-DKps_Gq_.js`：hr.buildBlocks／districtAt／surfaceAt、V／Kn／K | 同匯入工具；`Sources/GamePresentation/BuildingStyle.swift`：style(for:)；`RailwayGameApp/Rendering/BuildingLayer.swift` | bounds偏移後×64；style機率若需要整數則×1000；9區外觀保持，容量為原生表。 |
| `T/assets/world-gYgJkZNf.js`：Eg.pickType／floorsFor／layoutBlock、site lot／claims／placement／anchors | `GamePresentation/BuildingStyle`與工具；`City/BuildingTypes.swift`：capacity(for:) | 類型外觀可adapt；樓層2/6/18/40、面積1536、48/32㎡為gap新值，不能稱直接移植。任意輪廓只在畫面。 |
| `R/blender-buildings.js`：buildingCatalog／buildBlenderBuilding／inspectBlenderBuilding | `Sources/GamePresentation/BuildingAssets.swift`：loadCatalog；`RailwayGameApp/Rendering/BuildingMeshLoader.swift`：loadMesh／inspectionMaterial；或離線USDZ | 24byte Float32 vertex格式只畫面；metres與axis一次轉換；opacity.24可保留。GameCore不importFoundation/SceneKit/RealityKit/Metal。 |
| `R/assets/{blender-buildings-v1,historic-buildings-v2}/{catalog,placement}.json`、各model／far bin；`R/landmark-catalog.js` | `tools/building-assets/convert.*`、轉換manifest、App Resources/Buildings；GamePresentation landmark catalog | anchor地理投影在GameCore外；GeoAnchor仍1/10,000,000度；rotationDegrees只畫面；缺near明列，尺寸不推容量。 |
| `T/avatars/*.glb`、manifest、basis/*；`T/assets/avatar-CUFURxPX.js` | `tools/building-assets/convert_avatars.*`、App Renderer character assets | meshopt／quantization／KTX2解碼後native輸出；GLB非GameCore資料；保留MIT告示。 |
| `T/assets/anim-CQkLTvTS.bin`、clips-Cb5uFd0j.js：AnimLibrary／Clip | 同工具decodeAnimPack／retarget；App character animation | Int16位置1e-4m、root1e-3m、yaw4π/32767僅畫面；輸出骨架動畫，世界位置讀GameCore。 |
| `Ci/.../styles/liberty.json`、planet.json；app的mlLayerBeforeBuilding3d／setBuilding3dEnabled呼叫 | App實景建物extrusion／疊圖；已有背景保留 | render_height/min_height公尺；opacity.8；只有畫面，PMTiles／外部建物API缺檔。 |
| 6a `Sources/GameCore/City/Land.swift`：cellLength／middle／totals；SeedDraw | `City/Building.swift`／BuildingCapacity；`City/LandValue.swift`：landValue(at:) | 4096單位格、51200半徑、rate/weights1/1000；FNV-1a原值不變。建物容量／地價全部原生gap。 |
| `Passenger/TownGrowth.swift`：growth／reachedStations；6b土地成長 | `City/LandGrowth.swift`／capGrowth；`City/LandService.swift`／serviceQuality | 6b控制人口變化，6c每格cap；不改鐵路物理層，不以render height改成長。 |
| 四處來源的地價／容量／費用搜尋（無規則） | `City/BuildingTypes.swift`／LandValueRules；費用另Phase7提案 | 容量人／職位整數；地價美分/m²；本PR不新增經濟成本或資料程式。 |

T、R前綴在§2／§3明訂。目標檔案是供後續作者設計的草案，不表示已建立這些檔案，也不要求覆蓋已合併的6b實作。

## 10. 建議PR拆分、驗收與作者要決定的問題

| PR | 範圍 | 後續驗收條件（本研究沒有跑） |
| --- | --- | --- |
| 6c-1 格佔用與普通容量 | BuildingID／佔格資料、三用途×四密度、place/replace/remove、普通cap查詢；由Claude Code實作GameCore | 重複／越界／末格／用途／保留格拒絕；同格不重複佔用；失敗不配ID／不改世界；多格每格cap正確、空置可建、有人縮小／拆除拒絕；獨立手算表值。 |
| 6c-2 既有存量與6b夾限 | 一次性容量初始化／existingStock、存檔版本與遷移、6b午夜接點、計畫失效 | 所有舊存檔仍可讀；土地總人數／工作完全保留；普通與既有存量不雙算；滿cap零成長、剩1夾1；切分／存讀／午夜與idle一致；新增golden/replay／獨立模型，由作者協調schema。 |
| 6c-3 即時地價查詢與顯示 | §6規則、服務／可達性唯讀接口、面板分項／地價圖層 | 獨立算14500例、無服務2500、最高27000；800m嚴格邊界；重複站去重；closed／空分母與overflow安全；查詢不改世界、存檔沒有price歷史；沒有費用或租金帳。 |
| 8a 素材manifest與far建物試片 | 工具固定版本／來源hash／axis／licenses；47far和3種代表素材（101、山佳、總統府）；不改核心 | 輸出hash與bytes／頂點／材質報告；和來源bounds／orientation對照、缺near後備、double-sided／linear RGB核對；macOS loader與實機外觀驗證，OSM來源可見；不同LOD下core digest不變。 |
| 8b 角色／動畫轉換試片 | 先1英雄jie＋1群眾student-m；meshopt/KTX2／骨架／ANM1轉換、MIT全文 | 骨架joint數、rest pose／idle/walk回圈／root方向、alpha hair／mask／normal/mips；輸出格式能在選定iOSrenderer讀取，量測輸出大小／GPU記憶體；不聲稱缺LOD／fallback已存在。 |
| 8c 量測後擴充renderer | 程序普通建物／site外觀、分塊／剔除／LOD／instancing、其他素材按需要加入 | iPhone／iPad最低目標裝置報告frame time、峰值記憶體、冷啟動與切區I/O、draw calls；明確選裝置與同場景，不預設未測數字；性能設定／模型失敗不改模擬。 |

建造／維護費、地產交易與租金單獨列Phase7研究／實作PR，等作者定經濟規則，不藏進6c上述PR。

| 作者需要決定 | 建議答案與理由 |
| --- | --- |
| 普通容量是否採本表四級、樓板／人／職位係數？ | 先採1536㎡／層、48㎡／居民、32㎡／職位與2/6/18/40樓；全部標原生可調值。先以初始城鎮和6b成長跑平衡案例，再改版本化表，不跟模型自動改。 |
| 6a已有高人口格如何遷移，是否容許existingStock？ | 採同用途最低足夠密度，超表／末格用一次性existingStock保留總人數與工作；不裁人口、不重複加cap。這讓WorldPop高密格仍可讀。 |
| 拆除／降級時人口怎麼辦？ | 第一版有人或工作時拒絕，空置才拆。搬遷是另案原子命令，不讓玩家按一次拆除就靜默消失。 |
| 佔格與小site同格多棟怎麼對應？ | 核心一個佔格開發單元、畫面可以多棟細模型；地標預設裝飾零容量。真有玩法效果時作者選型別與格清單，不用508m推就業。 |
| 道路／公園／水域是否已備妥禁建格？ | 尚無遮罩的情境先明確可建；實景模型只畫面。另取得固定資料再產保留格，不能用畫面圖磚當核心權威。64m格太粗時不強求來源2m搜尋完全等價。 |
| 地價係數與服務時間窗是否採§6？ | 先採最近完成日服務分＋目前可達站、最佳站距離分、cap5、B/D與15×S公式；只推導price。不再重問要不要價格歷史或加費用，兩者本次已定。 |
| 滿容量的未實現成長是否累積？ | 不累積容量不足候選，僅留不足一人的分母餘數；升級從次日再長，避免爆量。與6b共同釘住這項契約。 |
| Phase8先選哪種iOSrenderer與素材範圍？ | 先47far＋程序普通建物，拿相同3建物與2角色試片比較SceneKit／RealityKit（必要時Metal），實測後選；本研究不鎖定。現階段不等43site／47near缺檔補齊才開始。 |
| 缺近景與授權全文的補齊優先序？ | 先保留far後備；角色發佈前補Rocketbox MIT全文，native dependency選版後帶LICENSE/NOTICE；按真正需要取得near／缺site，來源metadata保留，不替整包捏造授權。 |

既定的64m格表示、整數核心／SeedDraw、價格不存歷史、費用分Phase7，不列為待決問題。正式決策由作者寫入架構／路線圖；本PR不動那三份共享文件。

## 11. 查閱方法、gap清單與驗證邊界

**VERIFIED（雲端Linux工作區，靜態查閱／檔案結構核對）**：按順序讀規範與指定分支；clone私有庫並釘住上述commit；rg列檔與搜尋；Prettier **3.6.2**只在repo外展開world／engine／Ci app／island／avatar／clips等bundle；Python標準函式庫解析catalog／placement／全部47 model與far，核對bytes、SHA-256、finite floats、stride／triangle數與drawGroup總數／界線；讀8GLB header／JSON／skin／extensions／KTX2 header與ANM1 header；逐條檢查dynamic imports、near／GLB／fallback／source-path存在性。file工具查WebP／PNG尺寸。不是Swift或iOS執行驗證。

集中gap及實際搜尋：

| gap | 用過的關鍵字／查法 | 提案處理 |
| --- | --- | --- |
| 原生建物容量、入住／就業、地價／租金／開發公式 | population／residents／employment／jobs／capacity／building／floors／landValue／landPrice／propertyValue／realEstate／rent／rental／townGrowth／development／地價／地价／租金／開發／开发；四處來源按命中讀code／metadata | §5容量與§6價格明確原生，不稱來源值。 |
| 43site、postfx、5個content依賴 | import(／site-／build-／postfx／register-DEjbkm8D、逐路徑exists | §2列完；現存proxy／far後備，不宣稱完整網頁能跑。 |
| 47near、94 GLB宣告、hero thumbnails／source snapshots／.blend | catalog.files／metadata／thumbnail、lods.file/glb、sourceSnapshot／referenceFile／sourceFile／source-layouts／near.mesh.bin／near.glb／far.glb／.blend | §3列每件大小；只有現存far是可用mesh。 |
| 9avatar／17fallback／角色LOD | manifest.avatars.file/fallback/lod1、.glb與實際存在性 | §8列缺檔；manifest totals與實際總量分開。 |
| 完整建物圖磚／語意圖／Ci外部3D接口 | PMTiles／city.pmtiles／render_height／building-3d／metroCreateOsmMapLikeSingaporeDemo／setBuilding3dEnabled | 僅採現有style/schema，不抓外部資料、不給不存在的要素統計。 |
| 原生可建遮罩／公尺輪廓到64m量化精度 | Land／surfaceAt／claims／water／park／road／placement／footprint | 明定粗格語意，另補整數遮罩；沒有量測就不宣稱等價。 |
| Rocketbox與依賴完整LICENSE/NOTICE | LICENSE／CREDITS／NOTICE／copyright／license／Microsoft／Rocketbox／ODbL與源metadata | 已有來源授權照規範，特定明示條款補告示；不替未知bundle推測條款。 |

**UNVERIFIED／沒有檢查到**：未跑Swift建置或測試、CI、網頁場景、Three.js、Blender、SceneKit／RealityKit／Metal、Xcode／Simulator／實機；未進行任何資產轉換，沒有轉後USDZ／ASTC／IPA大小或frame-time／GPU基準；未解meshopt後逐三角形看角色外觀，沒有retarget動畫驗證；未逐件目視47外觀／立面／高度或核查所有原照片；未驗證缺near／GLB／sourceSnapshot的hash；未下載外部PMTiles／site／模型／照片、未對每個vendor與網站做全面授權調查；未量測64m佔格對道路／小基地的量化誤差，也未跑容量／地價平衡或6b成長情境。靜態核對不能代替這些檢查。

本文件為可審查的參考事實與設計提案；後續PR依§10逐項驗證並如實報VERIFIED／UNVERIFIED。
