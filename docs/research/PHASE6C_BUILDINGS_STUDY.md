# Phase 6c 建物、容量與地價，以及 Phase 8 素材管線：參考盤點與設計提案

查閱日期：2026-10-07（UTC）。本分支由當時最新 `origin/main` **`ea6ca31479c21d55650bcc904dbf529cdca02aab`** 開出；私有參考庫 `a91453/railway-reference-private` 已實際 clone，提交為 **`2db0c5a6963798e6b86723bb001189343a59940c`**。參考路徑均相對於私有庫根目錄；bytes 是實際檔案大小，MiB = 1,048,576 bytes，並非 IPA 壓縮後大小或 GPU 記憶體。本文只有研究與提案，型別、函式、數值和 PR 拆分尚待作者採納。PR #174 修訂時已同步最新 main **`66b5949`**（已合併 PR #173），設計依指定的 6b 提交 **`d2b383356514650197e7f94c060e88f4ac0e2486`** 重算；§2–§4、§8 的參考盤點保持原文。

**本次只新增此文件，沒有程式變更，沒有執行或宣稱任何測試通過。** GameCore 規則、存檔、golden、獨立模型與正式架構紀錄，仍依 `AGENTS.md` 由 Claude Code 負責。

## 1. 基準、已定方向與土地接點

開始前依序讀 `AGENTS.md`、`CLAUDE.md`、`docs/ARCHITECTURE.md`（決策 28、50、54、70）、`docs/ROADMAP.md` 的 Phase 6／7／8 與「跨階段議題」、Phase 6a 參考對照、`docs/research/PHASE6_LAND_USE_STUDY.md`，最後讀 `Sources/GameCore/City/Land.swift`。main 已合併 PR #172，因此土地研究讀 main；main 當時還沒有決策 72、Phase 6a 對照與 Land.swift，這三項讀 **`origin/claude/relaxed-curie-v8j2fp`，`5f1d8ccd48677cf8241d7b50308cc78043121806`**。上述為初稿查閱基準；本次修訂另外讀指定 `d2b3833` 的 `City/LandDemand.swift`、`City/Land.swift`、`GamePresentation/LandImport.swift` 與架構決策 72、73，並同步含 6a／6b 的最新 main。

本次指示已取代前一份研究的權威任意輪廓提案，以下四點視為既定條件：

- GameCore 的建物只以**佔用哪些 64 m 格**表示；任意輪廓、朝向、模型、LOD 與模型高度差異在畫面／素材層。鐵路與車站仍是連續世界座標，決策 28、54 不變。
- 一般住宅、商業、辦公建物由城市自動產生與升級，屬於城市存量；玩家自建、公司持有的房地產移到 Phase 7，6c 不提供建物購買、擺放、升級或拆除的玩家命令。
- 地價先即時推導，不存價格歷史；建造與維護費用、交易、租金、折舊與資產負債表由 Phase 7 處理，不放進 6c。
- GameCore 只用整數，結果固定；如需抽籤，只用存檔種子與 `SeedDraw` 的 FNV-1a。相機、載入順序、裝置設定、系統時間與系統亂數不影響模擬。

| 本專案檔案／名稱（指定 6b 提交） | 實際值／行為 | 6c 接點 |
| --- | --- | --- |
| `City/Land.swift`：`Land.cellLength`、`columns(in:)`、`rows(in:)` | 4096 世界單位 = 64 m；最後一行／列可超出 bounds。最大世界 256 × 256 = 65,536 格。 | 不能把 64 世界單位誤當格邊長；一格面積是 4096 m²。沿用 6b 的合法列／行範圍，末格按一個邏輯格計容量、畫面裁到 bounds；不另禁止 spread 原本可用的末格。 |
| 同檔：`LandCell {row,column,use,residents,jobs}`、`isValid` | 三種 `LandUse`：residential／commercial／office；居民與就業各 `0...100_000`，不能同時為 0。`Land.cells` 按 row、column 排序。 | 居民／就業只存土地一次；建物提供容量，不再存入住人數。初始化與 spread 同步建立城市建物；人口仍只存在 LandCell，不另造建物入住帳。 |
| 同檔：`middle`、`cell(at:)`、`totals(within:of:)`、`landCatchment(of:)` | 格中心 `column×4096+2048`、`row×4096+2048`；腹地半徑 51,200 單位 = 800 m，以 `d² < R²` 判定。 | 地價與 6b 使用相同嚴格小於規約，800 m 邊界不算入。`landCatchment` 是重疊腹地的顯示總量，不能直接拿來重複產生人口。 |
| 同檔：`setLand(_:)`、`foundTowns(seed:)`、`Land.towns(seed:in:)` | 整份替換；setLand 拒絕重複／越界／無效格。3 聚落；中心半徑 12 格、峰值 260 人；外側半徑 7–10 格、峰值 160–240；核心住 1/4、工作 3 倍，中心實際為 65 居民／780 就業。 | 6c 啟用後替換土地也必須驗證建物容量／用途，不能留下失配；初始核心的商業／辦公也有居民。 |
| 同檔：`Run`、encode／decode；決策 72 | `{row,column,use,residents:[...],jobs?:[...]}`；全 0 jobs 省略。6a／6b 已合併，存檔 12、golden schema 36。 | 本研究不升版；實作時以已合併的版本為基準。建物缺鍵的土地舊局如何建立既有存量，要明訂遷移。 |
| `City/LandDemand.swift`：`shares`、`Share.demand`、`growLand`、`grow`、`spread`；決策 73 | 重疊腹地依距離權重與最大餘數分配；每百居民＋就業 40 旅次，四捨五入；正成長每站分配增量並擴張一格 4 人住宅；固定成長上限 400 居民／1200 就業。 | 6c 啟用時以建物容量取代這兩個上限；保留站序、最大餘數與擴張，不改成另一套逐格成長。 |
| `Passenger/TownGrowth.swift`：`growth(served:trips:reached:)`、`Place`；決策 70、73 | 服務項最多 +10‰、每可達站 +1‰（最多 5）、無抵達 −2‰。6b 只處理正率，土地不衰退；Place 存 station／base／counted／lastGrowth，沒有保存昨日 served、服務比例或 reached。 | lastGrowth 是旅次實際變化，不是服務品質；§6 明訂需新增的兩個最新量測欄位。legacy 的 StationDemand 成長與四倍上限仍照決策 70。 |
| `Passenger/DemandEvents.swift`：6a 抽出的 `SeedDraw.hash/roll` | UTF-8 `seed\|key`，FNV-1a 32 位元，初值 2,166,136,261、乘數 16,777,619，乘法按 UInt32 wrapping。 | 使用獨立鍵如 `building:v1:<cell>:<purpose>`，不消耗事件 draws；型別與容量本身不必抽籤。 |

## 2. 台北場景：擺放、區域風格與 site

路徑前綴 **T = `Railway/city_world_reference/source/`**；表內 `T/assets/...` 均指這個完整前綴。先讀該包 `00_READ_ME_FIRST.md`，再展開 minified JS 到工作區的 scratch 閱讀，未改參考原檔。`T/assets/engine-Dl04UrJP.js` **172,446 bytes**；`T/assets/world-DCb11kLR.js` **1,413,781 bytes**。函式短名是 bundle 裡的實際名字，不推測不存在的 TypeScript 原始碼。

### 2.1 逐條合法性規則與格佔用改寫

`world` 的 `rO` 先收集鄰近 roads／blocks／landmarks／transit／mrt／已放 sites；`lO` 依下表順序回傳第一個拒絕原因。`RD` 是嚴格矩形交疊、`zD` 是包含、`VD` 是有朝向矩形與 AABB 的分離軸檢查、`HD` 是點到矩形的平方距離。這些是**場景配置規則**，來源沒有所有權、入住、工作容量或日成長。

| 參考函式／鍵 | 實際規則／值（m） | 改成 64 m 格佔用是否可行；整數常數／差異 |
| --- | --- | --- |
| `world: DO` | site anchors 的依賴已處理才選取，保留輸入索引的輸出；duplicate id 產生錯誤。同批 site 自指／批外依賴不阻塞；找不到可處理項（例如循環）就取剩餘第一項，交後續擺放檢查。 | 可改為依 BuildingID／CellKey 的固定順序，先計算整批佔格再原子提交。建議新核心拒絕循環或無效依賴，**不是來源 DO 已拒絕循環**；模型 anchors 仍屬匯入與畫面。 |
| `world: lO` 的 bounds | rect 不得越過 `plan.bounds`。 | 可逐一驗證格 row／column 與完整格界線；不用權威矩形。來源 engine 的 bounds x `[-900,900]`、z `[-960,560]` m，換算為 x `[-57_600,57_600]`、z `[-61_440,35_840]` 單位，再由匯入端加明確原點偏移。不能直接放入本遊戲非負座標。 |
| `lO` roads、`host`、`allowSidewalk` | host road 例外；`RD(rect,lot,-0.05)`；車道交疊回 `road`，其餘若未允許人行道回 `sidewalk`。 | 可把道路／人行道遮罩輸入為保留格，再驗證佔格交集；需要遮罩來源，**6a 沒有這份資料（gap）**。−0.05 m 建議離線四捨五入為 −3 單位；若直接升成整格禁建，公尺級退縮與 host 例外不會等價，需報量化誤差。不能讓整數格把鐵路吸附到方格。 |
| `lO` requireBlock、`zD` | 預設必須在一個 block 內，可容差 **0.5**；`requireBlock:false` 關閉此項。 | 可檢查全部佔格屬同一可建街廓 ID；0.5 m = **32** 單位只在匯入遮罩生成時使用。格跨街廓時的保守拒絕是新政策；不能假定細小街廓可塞下完整 64 m 格。 |
| `lO` landmarks、`RD` | 非 pedestrian 地標，擴 **2** m，回 `landmark:<id>`。 | 保留格不重疊可表達；**128** 單位外擴再格化。原來源在邊界相切不算交疊，整格化會多排除格。 |
| `lO` transit、`VD` | entrances／obstacles 的旋轉矩形，外擴 **3** m；`rO` 粗搜半徑 `max(hw,hl)×1.5+3`。 | 在匯入端將禁建區轉為佔格清單；**192** 單位，不在核心存朝向或做 sin／cos。高度／地下共構例外需要另訂；第一版不能因有 mesh 空隙就允許穿越。 |
| `lO` MRT、`HD` | 出口點離 lot 小於 **4** m，回 `mrt:<id>`。 | 禁建格遮罩可表達；半徑 **256**、平方 **65_536** 單位²。來源是點到 lot，不是格中心距離；離線格化要記錄所選規約。 |
| `lO` placed、`RD` | 與已成功放置 site 擴 **1** m交疊，回 `site:<id>`。 | 核心直接拒絕同格重複佔用；**64** 單位間距只保留為畫面擺放規則。相鄰格可接觸，不必在核心強迫空一格（會變 64 m 間距）。 |
| `lO` env.claimed、`BD` | lot 內縮 **0.2** m，再以 scope `buildings` 查 claims，回 `district-claim`。 | 建物類保留格能表達；離線內縮建議 **13** 單位（0.203125 m），scope `props` 不阻止建物。所有權／用途遮罩是新契約，不能把呈現 claim 當人口。 |
| `world: UD`、`PD`、`ID` | rect 四邊內縮 **0.3** m，x/z 各取低、中、高，共 **3×3 = 9 點**；第一個非允許 surface 就拒絕。預設 PD = lot／plaza／park；ID 是在預設集合加額外 surface。 | 核心逐一檢查佔格的可建旗標／用途；0.3 m 建議 **19** 單位（0.296875 m）。9 點無法證明全輪廓可建。plaza／park 可放 site 是來源場景需求，**不提案把城市公園自動改成住宅**。 |
| `world: WO`、`qO` | 臨路搜尋：setback 預設 **0.5**、search **60**；wide relaxation 將 search ×2；沿路偏移按 0、±2、±4…m，交叉口加 **4** m；undercroft 要 elevated 且 `oD(road,1.2) >= 2`。lane 僅在placement.lane且mode=lot時搜尋，步長2，score含 **8+lane距離+偏移**；side另一側懲罰 **100000**，off-frontage／允許sidewalk各可加 **8**。qO再加 **0.5×IE(targets,中心)**，比最佳分數小逾 **1e-9** 才替換。 | 候選佔格可以固定排序再驗證，但沒有必要把完整車道搜尋搬進核心；建議匯入／預覽端輸出格清單。32／3840／7680／128／256 單位；1.2 m 建議 **77**、2 m = **128**。score另用1/1000比例時0.5→500、8→8000、100000→100000000；它不是費用。核心不用1e-9或浮點tie-break，依固定候選索引平手。64 m 粗格不保持沿路2 m搜尋或高架下店面語意。 |
| `engine: hr.buildBlocks` | major x/z 道路按 at 排序，插入 minor roads；街廓扣 halfTotal；寬或深 **<20** m 跳過。路段範圍檢查容差 **1** m；生成 `{id,minX,maxX,minZ,maxZ,district,reserved,zones,north,south,west,east,edge}`。 | 可離線產生 block→可建格／保留格；20 m = **1280**、1 m = **64**。20 m 街廓可能沒有完整64 m格，所以**不能宣稱直接搬到核心等價**。小街廓與同格多棟外觀聚合成一個開發單元。 |
| `hr.districtAt(x,z,gen=false)` | 先 Kn 的 **5** 覆寫矩形，再 V 順序；半開範圍。gen=true 跳過 `gen:false` 覆寫；無命中回 V 最後的大安。 | 可將格中心所屬 style ID 放到場景匯入／畫面表；不作居民／就業規則。需保留順序、gen 旗標與後備，不能把未涵蓋處假定合法可建。 |
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

現存 site 模組有 **3** 個，不能只說2個：`T/assets/site-donqi-ximen-C4Uhuz6T.js` **28,315 bytes**、`site-fongda-coffee-ncv_Ui7v.js` **32,316**、`site-railway-department-park-CeP4zM45.js` **25,073**。另外 `build-BU46ZK3j.js` **118,851**、`build-2kUI5-ha.js` **109,698** 是場景幾何／atlas生成；後者有 atlas 預設 **2048**、固定 RNG seed **20,283,292**，不作本遊戲城市種子。

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

另外 gap：world 仍缺 43 個 `site-*.js`；`postfx-D80OZstt.js` 已在 2026-10-10 refresh 補齊。`T/assets/content-DcQ2Whr5.js`（**1,855,122 bytes**）所指 `build-Bz4uAL4f.js`、`build-CN7_0enk.js`、`build-Cx8EeQJB.js`、`build-nn2qgmtJ.js`、`register-DEjbkm8D.js` 皆缺。查找用 `import(`、`site-`、`./defs/`、`lot`、`claims`、`placement`、`anchors`、`proxy`、`build-`、`postfx`。沒有下載缺檔，不能宣稱原網頁場景可完整跑起來。

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

四處來源以完整詞搜尋地價／租金後，T另有外觀命中：`T/assets/content-DcQ2Whr5.js` 的 `trade:"realestate"`、`category:"房屋仲介"`、names／menu（買屋、賣屋、租屋、捷運宅）、`weight:1/2`、`AL.realestate:"09:30-21:00"`，是店面樣式與營業時間；`T/assets/world-DCb11kLR.js` 的 **"Tap to Rent"** 是借車畫面，shader的for-rent是出租鐵捲門外觀（關店用tile **24**，不顯示出租變體）。沒有租金、美分價格或房產交易。查找 `realestate`、完整詞 `rent`、`出租`、`trade`、`AL`、`bShopOpen`，不把招牌文案當經濟引擎。

## 4. Ci：建物圖層與地價／租金／開發搜尋

| 檔案／函式／鍵 | 實際看到的值與大小 | 對6c／8的意義 |
| --- | --- | --- |
| `Ci/reference_snapshot/external/openfreemap-tiles/styles/liberty.json`：layers `building`、`building-3d` | **43,079 bytes**；2D fill 的 source openmaptiles、source-layer building、minzoom **13**、maxzoom **14**；3D fill-extrusion minzoom **14**，height `get(render_height)`、base `get(render_min_height)`、opacity **.8**，色 hsl(35,8%,85%)。 | 高度直接來自圖磚欄位，無樓層→容量公式、也未在此expression加後備高度。可作畫面extrusion adapter；不把圖磚當存檔建物。 |
| `Ci/reference_snapshot/external/openfreemap-tiles/planet.json`：vector_layers[id=building] | **19,254 bytes**；fields `colour:String,hide_3d:Boolean,render_height:Number,render_min_height:Number`；minzoom **13**、maxzoom **14**。 | 是圖磚schema，建物本體圖磚沒在此檔；hide_3d 是呈現旗標。高度與底高以地圖extrusion的公尺語意使用，不是居民、租金或造價。 |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`：`initOsmMapEngine`、`metroEnsureNonHongKongOsmBuilding3d` | 全檔 **4,378,323 bytes**；呼叫 `metroCreateOsmMapLikeSingaporeDemo`，傳 `pitch:0`、`initialBuilding3dEnabled:!香港2D模式`，其他城市以 `setBuilding3dEnabled(true)` 保持3D。 | 建物顯示開關；外部 `metroCreateOsmMapLikeSingaporeDemo/setBuilding3dEnabled` 定義未收錄（只找到呼叫，gap），不能假稱完整renderer已取得。 |
| 同 app：`mlLayerBeforeBuilding3d` | 優先找 building-3d，再找fill-extrusion且id符合building/3d/extrud，最後找非metro-ridership-hex-ml的extrusion。 | 疊圖順序查詢，沒有建立建物或開發人口。 |
| 同 app：`renderRidershipFlowCirclesMaplibre`／`renderHsrStationFlowCirclesMaplibre` | fill-extrusion使用 properties `extrudeH`，base **0**、opacity **.92／.9**；根據流量正規化產生高度，分別為一般路網與高鐵站運量。 | **是運量統計柱狀圖，不是建物高度**。不能將每個fill-extrusion命中都算為建物。 |
| `Ci/reference_snapshot/lib/virtual_island_city__q_21ffa7f6ae58fc9e.js`：內部 `M`、`w` | **13,906 bytes**；id `virtual-island-original-buildings-v10`、source-layer **buildings**（複數）、type **fill**、minzoom **12**；`u` = office／retail／industrial／institution選色，opacity在zoom12為 **.4**、13.5為 **.95**。 | 此包虛擬島建物是2D；沒有從這個圖層讀height／樓層／入住容量。不能把 `u:retail` 當作工作人數。 |
| 同 island：`METRO_VIRTUAL_ISLAND_SEMANTIC_MAP_URL`／`REFERENCE_MAP_URL` | 同一 `/data/virtual-island/tiles/city.pmtiles?v=20260905-osm-city-v15`；landuse.kind cbd／industrial／villa／institution／newtown。 | **gap：city.pmtiles本體缺**，無法盤點要素量、真實高度或用途數量。 |

**地價／租金／房地產／開發規則為 gap**：在 `Ci/reference_snapshot/` 的js/json/html搜尋 `landValue`、`land_value`、`landPrice`、`land_price`、`propertyValue`、`realEstate`、`real estate`、`rent`、`rental`、`地價/地价`、`租金`、`房地產/房地产`、`開發/开发`、`development`、`building`、`render_height`、`render_min_height`、`fill-extrusion`。沒有查到遊戲土地定價、租金結算、房產交易、建物容量或車站驅動開發引擎。寬搜rent／develop會命中current／parent／SDK函式或網站開發文字；按完整詞再查、閱讀應用bundle命中後，app的「火炬开发区」是CITIES分區名，`voyager-about` 的「开发团队」是網站介紹，皆不是開發規則。

另外依 `CLAUDE.md` 查 `Railway/railway_game_reference_clean/00_READ_ME_FIRST.md`、`01_MIGRATION_MAP.md`（**8,192 bytes**）§9／§10與相關source-path清單：town_cmd.cpp／industry_cmd.cpp只有路徑，沒有原始碼／建物容量／地價公式。關鍵字 `house`、`building`、`town`、`growth`、`land`、`value`、`industry`、`terraform`；沒有用外部OpenTTD知識補數值。

## 5. 6c建物與容量提案（全部容量數值都是gap→原生）

### 5.1 權威表示與城市內部更新

建議 `Sources/GameCore/City/Building.swift` 的 `Building` 只存 `id`、`kind`（城市普通建物／既有存量）、`use`、`density`、`occupiedCells:[CellKey(row,column)]`；規則表用固定 `buildingRulesVersion`。容量、樓層與名義高度由 kind／use／density 的整數表推導，**不存 PlanPoint、rotation、lot 輪廓、模型 ID、mesh 或 LOD**。資料表示可容納多格集合，第一版城市自動建物則一格一個開發單元，方便沿用 6b 逐格容量與升級配額；同格可在畫面畫多棟小公寓、店屋，4.4 m 店面不各佔一格。

**普通建物由 GameWorld 的城市流程自動產生與升級，不新增 `placeBuilding/replaceBuilding/removeBuilding` 玩家命令。** 名稱僅為內部草案：`initializeCityBuildings()` 在新局／啟用容量／土地遷移時依 §5.3 建立建物；既有 `setLand(_:)`、`foundTowns(seed:)` 在容量開啟的世界須原子同步土地與城市建物；`LandDemand.swift` 的 `spread(towards:)` 同時新增 4 人 LandCell 與住宅 D1；同檔 `upgradeCityBuildings(around:...)` 依 §7.2 升級。容量查詢為 `buildingCapacity(at:)`／`remainingCapacity(at:)`，都唯讀。

土地與建物的用途必須相同，同格只由一個權威建物供應容量；格按 row→column、建物按 ID 排序。初始化不能裁人口或把 LandCell 與建物人數加總；升級只改密度，不換用途、不生人、不配新建物 ID。第一版沒有自動降級、拆除或遷出。將來多格有容量的建物也必須逐格驗證，不能用總容量掩蓋單格超額；公司建物的擺放、所有權、資產、拆除與搬遷契約交 Phase 7。

合法列／行沿用 `Land.problem(in:)`、`Land.rows(in:)`／`columns(in:)`，包括最後不足完整 64 m 的邏輯格。為保留 6b `spread` 行為，第一版不另加「整格完全在 bounds 內」門檻：容量按邏輯格表計，畫面裁到世界邊界；這是原生邊界政策，不代表邊格真有 4096 m² 可交易面積。Phase 7 估值面積須另訂裁切。

可建遮罩／道路保留資料仍為 gap：6b 沒列出的格不等於水、道路、公園；`spread` 只知道世界列／行、800 m 與相鄰有人格。6c 沿用這項語意。未來要加禁建遮罩，須另提供固定整數核心資料並標示行為變更，不能讓 `surfaceAt`、MapKit 或模型載入決定城市是否生長；裝飾地標不自動供容量或排擠居民。

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

**6c 啟用世界用本表的逐格容量取代 `LandDemand.grownResidents = 400`／`grownJobs = 1200`，不是再與 400／1200 取較小值。** 例如住宅 D2 在 168／36 停住，D3 可長到 504／108，D4 到 1120／240；商業 D4 到 320／1440，辦公 D4 到 160／1680。不同用途對住房與就業的限制不同；滿格可依 §7.2 自動升一級，D4 已無更高普通級別。未開啟建物容量的 6b 舊局保留 400／1200，不把它的存量或行為偷偷改掉。

400／1200 是成長夾限，並不是 `LandCell` 的合法上限（各 100000）。6b 的 `grow(around:residents:jobs:)` 對已達／超限的該項保留現值、停止該項成長，另一項仍可長。實際盤點：種子 1 起始城鎮最大居民 230、就業 780；§5.3 兩種台北錨點的最大居民為 197／211、就業皆 285；**這三個初始化資料集各有 0 格居民 >400、0 格就業 >1200**，不可宣稱台北匯入已超限。任何 `setLand` 匯入或其他存檔仍可合法超限，須逐格比較／遷移；6b 自己的成長不會從未超限狀態長過 400／1200。本次沒有枚舉所有玩家存檔，也不把這個 0 推論到所有選點。另唯讀檢查已合併的 `SaveFixtures/v12-land-demand.json`、`v12-land-towns.json`（各68個土地 Run），兩者也是0格居民>400、0格就業>1200；只是JSON存量盤點，沒有執行保存例測試。

這些是遊戲平衡用容量，不是真實城市人口密度，也不推算參考地標的員工。例如101高508 m、地標catalog kind並沒有等於o-tower；地標若要具有容量，須作者選普通型別與格清單，且不能與同格既有容量重複。

### 5.3 既有土地容量初始化、台北實算與相容性

啟用 6c 時，逐格建立城市建物，選**同用途、同時容納現有居民與就業的最低密度**，兩項都要比較。這只是容量初始化，土地存量、用途、需求計算均不因模型高度改變。

| 6b 實際值／容量例 | 同用途最低足夠等級與理由 |
| --- | --- |
| 中心峰值 260；以 260 居民／0 就業的住宅例計 | R D2 只能容納 168，R D3 的 504／108 足夠，選 r-high。注意 `Land.towns` 的真正中心在核心，260 是用途轉換前的 peak；不會直接保存為 260 居民住宅。 |
| 中心核心格：`jobs = 3×260 = 780`、`residents = 260/4 = 65` | 抽到辦公：O D3 的 72／756 就業不足，選 O D4 160／1680。抽到商業：C D3 的 144／648 就業不足，選 C D4 320／1440。初稿的 32／390 與 r-mid／o-high 已不適用。 |
| 核心外住宅、外側城鎮 | 每格按 `peak×floor((r²−d²)×1000/r²)/1000` 向下整除，核心才另作 1/4、3 倍。不是整座城鎮統一等級；R D2 可容納至 168 居民且 36 就業，其餘需同時比較。中心城鎮實際最高住宅居民 230（`d²=16`、share=888），仍選 R D3。 |

**台北實際重算（VERIFIED，雲端 Linux 的 Python 標準函式庫重現指定 d2b3833 算式；沒有執行 Swift 匯入函式或測試）**：使用專案打包的 `RailwayGameApp/Resources/RealWorld/taiwan_population.json` **159071 bytes**、SHA-256 `2b5a318abd96d3fc45915675c3a001759756569e3f69db002746908c41b0a759`；`taiwan_places.json` **255969 bytes**、SHA-256 `d892674e9bd05dcb07f1aba17b11258fcfbd51603f238fde2ea97b7287100739`。不是參考庫缺失的 LandScan 或 PMTiles。

兩檔的 `north=26.391666897100002`、`west=116.70833214650004`、`cellDegrees=0.0083333333`。按 `GridCounts.init` 累加 `runs.{r,c,p}`／`layers[kind]`；`LandImport.jobsPerPlace` 是 shops **25**、offices **500**、schools **300**、attractions **50**，全台換算 **8561200** 就業。以下使用 `WorldBounds.maximum`，寬高 **1048576 世界單位**，即 256×256 格、中心 (524288,524288)。

重算方法：逐 row 0…255、column 0…255，將 `(column×4096+2048,row×4096+2048)` 交 `RealWorldFrame.coordinate(worldX:worldY:)` 的同一 Mercator 逆投影（`RealWorldDemo.swift` 的 `worldPoints=268435456`、`earthRadius=6378137`）；再以 `GridCounts.cell` 的 floor 找來源格。按 `LandImport.cells` 收集非空來源格的 row-major members，內部來源格的 slots=members.count；碰首末列／行的則 `max(members.count,round(area/4096))`，area 沿用 `GridCounts.area` 的 **110574**、**111320×cos(latitude)** 公尺／度。居民與總就業各取 `total/slots + (index < total%slots ? 1 : 0)`，最後夾到 100000、略過兩者皆 0；用途比較 officeJobs、shopJobs、people，平手依來源先辦公再商業。畫面層投影用 Double，GameCore 收到與保存的都是整數。

| 錨點（緯度、經度）與來源 | 匯入格數 | 總居民／總就業 | 每格最大居民／最大就業 | >400 居民格／>1200 就業格 |
| --- | ---: | ---: | ---: | ---: |
| **25.0479308, 121.5170046**，`RealWorldMap.swift` 的 `RealWorldPlace.standard`／tra-taipei | 64897 | 4682180／2058577 | **197／285** | **0／0** |
| **25.047882, 121.517219**，`LandImportTests.swift` 的 `Self.taipei` | 64829 | 4687421／2061993 | **211／285** | **0／0** |

不同錨點讓 64 m 格中心略移，members／slots 與邊緣份額也會變，不能省掉錨點就說「台北最大值」。以下是各最大值的第一個 row-major 格，row、column 從 0 起；居民與就業最大值不在同一格：

| 錨點／最大項 | 目標格與現有存量 | 來源 WorldPop 格與可手算資料 | 初始化 |
| --- | --- | --- | --- |
| standard／居民 | (197,114)，住宅 197／28；197 居民共 166 格 | (166,576)，people=35838，officeJobs=2300，shopJobs=2725，slots=182。`35838/182=196 餘166`，前166格為197；`5025/182=27 餘111`。 | R D3 504／108。 |
| test／居民 | (197,127)，住宅 211／30；211 居民共 20 格 | (166,577)，people=38240，officeJobs=3700，shopJobs=1725，slots=182。`38240/182=210 餘20`，前20格為211；`5425/182=29 餘147`。 | R D3 504／108。 |
| 兩錨點／就業 | (124,114)，辦公 78／285；285 就業各有 170 格 | (161,576)，people=15071，officeJobs=35800，shopJobs=19750，slots=195。POI offices=71、schools=1、shops=762、attractions=14；`55550/195=284 餘170`，前170格為285；`15071/195=77 餘56`。 | 此格 O D3 雖容納 285 就業，居民容量72不足，選 O D4 160／1680；同來源其餘77居民格也需 D4。 |

同時檢查整份匯入：兩錨點各 **0 格超出同用途 D4 的兩項容量**，都能按普通表初始化。不過 standard 有 **3045 個住宅格、1272 個辦公格**因混合人口／就業需要 D4（test 為3240／1396）；例如辦公的 78 居民會選40樓，這是本表原生配比的結果，**不是來源真實樓高**。作者需決定是否調整混合用途配比，不能改用途或裁居民來使模型看起來較矮。

另外重現 `SeedDraw.hash/roll` 的 FNV-1a 與 `Land.towns(seed:1,in:.maximum)`：**887 格、90900 居民、67413 就業，最大居民230、就業780**，與決策72的總量相同；這是整數重算核對，沒有執行該測試。一般規則允許其他合法匯入／玩家存檔超過400／1200，不代表本次三組初始化已超過。

若同用途四級仍容納不下，建立 `existingStock`，選定密度 D4，每格一次保存 `residentCapacity=max(existingResidents,D4居民容量)`、`jobCapacity=max(existingJobs,D4就業容量)`，各不超100000。它替代普通容量，不額外相加，不假裝真有40樓；只由匯入／遷移建立，第一版保持容量、不能由一般自動升級無限提高覆寫值。有人格必有足夠建物容量，不因「目前未建立建物」阻止6b存量初始化。邊格照 §5.1 邏輯格政策，不因面積不足再裁居民。

舊存檔：版本11以前沒有土地，保留 legacy；6b 土地版缺建物的舊局在明確啟用6c容量時一次初始化，未啟用仍用固定400／1200。重新讀檔不可重生一次存量；保存建物、existingStock 覆寫與 buildingRulesVersion，格式／升版與新增保存例由作者定案。本研究不改現有 fixtures。普通城市建物只升不降；公司房地產的拆除／降級與搬遷另屬 Phase 7。

## 6. 地價：即時整數推導提案（gap→原生）

### 6.1 輸入、6b 已存資料與明確新增量測欄位

建議 `City/LandValue.swift` 的 `GameWorld.landValue(at:CellKey)` 回傳 `centsPerSquareMetre:Int64` 與分項，即時讀目前用途／建物密度及最近完成一日的服務量測；不保存 price 或價格歷史，不結算交易／租金／維護費。沒有土地或建物的格可用 vacant 基準估值（不新增 LandUse）；未來有固定不可建遮罩的格為0，目前未列出的土地不直接當水域。

先釐清指定6b實作：`TownGrowth.Place.counted` 是**上次午夜的累計 arrived**。`LandDemand.swift` 的 `growLand(reached:)` 先算 `served=record.arrived−place.counted`，再覆寫 counted；因此覆寫後無法只靠 counted 還原昨天 served。`lastGrowth=clamp((nowTrips−beforeTrips)×1000/beforeTrips,−1000,1000)` 是午夜前後日旅次的實際變化，受成長夾限、擴張與整數旅次影響，不能拿來當 q 或 rate。`base` 也不是昨日旅次分母。**6b 沒有保存昨日服務比例，也沒有保存 reached**，初稿「已保存服務量測」不成立。

為使日內唯讀地價、存檔續玩與滿格自動升級都能使用相同量測，**明確提議6c新增 `TownGrowth.Place.lastService:Int64`（0…1000）與 `lastReached:Int64`（0…5）兩個存檔欄位**，定義在既有 `Sources/GameCore/Passenger/TownGrowth.swift`，由既有 `City/LandDemand.swift` 的 `growLand(reached:)` 每晚更新一次。只保存最後一次量測，不存日序列或地價。升級在午夜直接用此次局部量測；價格在其後與日內讀保存值，避免存讀後失去午夜 reached 或另造運量統計。

| 輸入／資料鍵 | 規約與整數界線 |
| --- | --- |
| 800 m 腹地與距離權重 w | 格中心對各站用 `d² < 51200² = 2621440000`，`w=1000−floor(d²×1000/R²)`，1…1000，直接沿用 `LandDemand.shares` 的距離規約；用來定價的政策為原生。 |
| 昨日服務分母 trips／分子 served | 與 `growLand` 完全相同：更新前 `record.demand.dailyTrips`（正數且 ≤1000000）、原起站守恆帳 `record.arrived−oldPlace.counted`。不假設另有 potentialTrips 欄位，不改用星期／事件調整後旅次或今日的累計差值。 |
| **新增存檔 lastService（q）** | `served<=0` 或 trips<=0 為0；`served>=trips>0` 為1000；否則 `floor(served×1000/trips)`。這是 `TownGrowth.growth` 既有的 share 比例，6c 只把它保存。新 place 只有 counted 基準，第一次看見不成長，q=0；舊存檔缺鍵預設0，完成下一個有基準的午夜才量測。 |
| **新增存檔 lastReached（k）** | 保存 `min(max(Int64(reached[station] ?? 0),0),TownGrowth.reachedStations)`，上限沿用5。`reached` 直接來自 6b `GameWorld.reachedStations(endingDayAt:release:workedOutAt:)`，其 `reachedStations(_:)` 按昨日 release.plan.flows 計各 origin 的迄站數；不另查可行旅程、不取腹地各站目的地聯集。新 place／缺鍵預設0。 |
| 格的服務分 S 與可達數 A | 對有 place 且 lastService>0 的腹地站取 `score=floor(w×lastService/1000)`，最高者為 s*，平手較小 StationID；`S=score_s*`（0…1000），`A=lastReached_s*`（0…5）。沒有 q>0 的站則 S=A=0；最佳站選擇是原生定價政策，A 的量測與 cap 完全沿用6b。換另一個好站可改變估值，不把站數／同目的地加總。 |
| 既存 counted／lastGrowth | 保持6b原義，counted繼續作下次 arrived 差值基準，lastGrowth繼續供車站面板；不借用它們的欄位存 q／k。公司非經營、landDemand關閉或townGrowth不存在時，第一版估值的服務／可達溢價定義為0，基準用途／密度價仍可查。 |
| 用途基準 B | vacant **1000**、residential **2000**、commercial **3000**、office **3500** 美分/m²，原生相對價，不是台灣公告地價或成交價。用途與 LandCell 相符，不由貼圖決定。 |
| 密度係數 D | D1 **1000**、D2 **1250**、D3 **1600**、D4 **2000**，分母1000；vacant取1000，existingStock用初始化選定D4，不按人口每次重猜。 |

q／k 是最近完成日，站的 reached 即使日內改線也要等下一次6b午夜量測才更新，不能宣稱它即時反映新路網。用途／密度與站距的查詢則按目前世界即時推導。未知／剛開啟量測取0；不從今日 `arrived−counted` 猜昨天，也不重建一套過去的服務計畫。若作者不接受新增這兩個欄位，應另定估值指標，本案不把 lastGrowth 冒充服務比例。

解碼驗證新增兩欄界線，既存欄位照舊；缺鍵為0且重新保存為相同結果，啟用／關閉與舊局遷移須由存檔負責者釘住。這項新增量測是 §10 的作者待決項，本文沒有改任何存檔程式。

### 6.2 公式、範圍與可重算例

```
若格不可建：value = 0
base = floor(B × D / 1000)
servicePremium = 15 × S
accessPremium = 1000 × A
value = clamp(base + servicePremium + accessPremium, 500, 50_000)
```

單位為**美分／m²**；可建格下限500、上限50000（$5…$500/m²）。B/D、係數15、每站1000、上下界皆gap建議值：服務滿分加$150/m²、最多5可達站加$50/m²，使鐵路服務能明顯提高價值，並以密度2倍內控制高樓的基準價差。這些不是建造費，不納入公司帳本。實際這組初值的最大普通價是office D4 **27,000**，50000是未來仍需遵守的防護上限；不假稱目前能到50000。

例：住宅D2，距一站 **400 m=25,600單位**，站已保存 lastService=800、lastReached=3：`w=750,S=600,base=2500,value=2500+9000+3000=14_500`，即 **$145/m²**。沒有服務、沒有可達站的同格價 **2500**；office D4滿服務、5站 **7000+15000+5000=27000**。同樣世界與日量測，換模型或相機不改這個數字。

`d²×1000` 在世界範圍內小於2^51；B×D≤7,000,000；w×q≤1,000,000；value≤50000。q 沿用 `TownGrowth.growth` 的先判 `served>=trips` 再乘法規約，僅 `0<served<trips≤1000000` 才乘1000，所以該乘積小於1000000000；不對任意累計 arrived 直接乘1000。A 讀最佳站保存的6b reached（已夾0…5），不建集合或做目的地聯集；平手由 StationID 決定。

若Phase7之後要把單價乘面積，完整64 m格 `4096×value` 最大 **204,800,000美分**，全圖上限 **13,421,772,800,000美分**，仍在Int64；但那時要另訂地界裁切、交易／估值時間與租金政策。這裡不先記一筆建造或地產收入。

## 7. 與6b土地成長的接點：保留既有 LandDemand 流程

### 7.1 指定6b實作的每日計算與容量替換

接點是既有 **`Sources/GameCore/City/LandDemand.swift`**，不是另建 LandService／LandGrowth。`drawsDemandFromLand` 只在 landDemand 開啟且經營模式為真，`growLand(reached:)` 還要求 townGrowth 存在；其餘世界保留決策70／6b原行為。一般建物提供容量，6b決定人口與就業。

1. 每晚由既有 `GameWorld.reachedStations(endingDayAt:release:workedOutAt:)` 提供昨日 reached，維持午夜末秒計畫與批量切分的處理。在 `growLand` 原有 record 迴圈記錄 beforeTrips；已見過的 place 算 `served=arrived−counted`、更新 counted，再用 `TownGrowth.growth(served:trips:reached:)` 得 g。新 place 只建立基準，該晚不成長。6c 在這裡保存 §6 的 q／k，不重訂成長率。
2. `g<=0` 不加入 growing，所以**6b土地不衰退**，無服務不扣居民或工作。正率為 `floor(q×10/1000)+min(reached,5)`，最多15‰。不能把 legacy 每站需求的 −2‰ 衰退或四倍上限移植成土地規則。
3. 既有 `LandDemand.shares(of:among:)` 在站成長迴圈前算一次，重疊腹地的居民／就業按距離權重、最大餘數分享，平手站ID。`Share.demand` 為 `min(1000000,((residents+officeJobs+shopJobs)×40+50)/100)`，種類依居民→辦公就業→商店就業的最多者；住宅的工作也歸 shopJobs。這是分享存量與需求，與下步的成長量分配不同。
4. 按 StationID 遞增處理 growing。每站從上述 share 算 `ΔR=grown(R,g)`、`ΔJ=grown(officeJobs+shopJobs,g)`；`grown(amount,rate)` 對正 amount、rate 為 `max(1,(amount×rate+500)/1000)`，amount=0 則0。**先每站算整數成長量，再分給腹地；沒有逐格千分比餘數或跨日土地餘數。**
5. 既有 `grow(around:residents:jobs:)` 收集腹地格（row→column），各以當時格的居民／就業數作權重，呼叫 `GameWorld.apportion` 最大餘數法，平手較小格索引。較早車站已變動的格／擴張格可成為較晚車站的權重，這是既有順序，不能改成全部格同時套率。6c 在這個方法把固定400／1200換成該格 `buildingCapacity`，兩項各夾剩餘空間；**不再額外 min(400/1200)**。已達／超過上限者保留原值、不倒扣；正常初始化已保證cap≥現值。放不下的分配直接丟棄，不重新分給其他格、不累積候補人數，也不留下小數餘數。
6. 同一個正成長站隨後呼叫既有 `spread(towards:)`：在800 m腹地、合法列／行中，沒有 LandCell 且上下左右有 LandCell 的格，以 `(d²,row,column)` 最小者新增住宅 **4居民／0就業**（`newCellResidents=4`）。有候選才新增，每個成長站每天最多一格；即使原腹地容量全滿、所有分配都放不下，g>0仍會嘗試擴張。較早站的新格可成為較晚站的相鄰格。**6c 同時自動生成該新格的住宅 D1 建物（56居民／12就業容量）**，保留4位初始居民，不要求玩家先蓋房，也不以原本沒建物而把容量設0。
7. 最後沿用 `refreshLandDemand()` 與 `lastGrowth` 更新：每站記 midnight 前後 dailyTrips 的實際千分比變化，仍夾 −1000…1000；沒有再次套城鎮成長率到旅次。人口／就業只在 Land 保存一次，需求與計畫照6b原接點更新；地價其後唯讀，不回頭控制本日升級。

手算：某站 share 為70居民、g=11‰，`grown(70,11)=(770+500)/1000=1`；腹地兩格56、14居民，最大餘數將1給56那格。若該格滿D1且當晚未獲升級配額，夾限後這1人不加入、不轉給14那格；仍可按 spread 規則新增一格4人。沒有「該格今天剩0.56人、明天補上」的土地帳；乘客釋出用的OD餘數是另一項既有狀態，不能混用。

§5.3的起始城鎮與台北匯入目前沒有超過400／1200的格；任意合法高存量存檔須初始化成足夠普通級別或 existingStock。6c不能先裁到400／1200再選建物；例如合法的R格500居民選D3後可在504停住、滿格再升D4，不能因保留舊固定400而永遠停在500。這個500例為原生設計手算，不是台北匯入觀察值。

### 7.2 城市自動升級：可重算的原生規則

以下門檻與配額是 **gap→原生提案**，來源與6b沒有建物升級規則。一般R／C／O由城市更新，不是玩家指令、不買公司資產、不付Phase7費用。

| 規則／建議常數 | 整數定義 |
| --- | --- |
| 滿格 | 午夜開始時，普通建物 D1…D3 的某項正容量已滿：`residents==residentCap>0` **或** `jobs==jobCap>0`。任一項阻住就可升，不要求住房與工作同時滿；existingStock與D4不在候選。 |
| 腹地服務好 | 該站有舊place、g>0，且同一次6b量測 `q>=800`、`k>=1`（80%服務，至少1個可達站）。q、k定義見§6，門檻800與至少1為原生初值；不能用受容量影響的 lastGrowth 判斷，否則滿格可能永遠無法升級。 |
| 每站每日升級配額 | **2格**（`cityUpgradesPerStationPerDay=2`，原生）；成功升一格扣1，沒有候選不借給別站或累到次日。第一版一格建物，故不需多格建物的配額折算。 |
| 順序與重疊 | 沿用 growing 的 StationID 遞增；每站候選是800 m內午夜開始已滿的普通格，按 `(row,column)` 遞增。全晚局部 `upgradedCells` 防同格重疊站重複升；較小站先選，已升格略過、不再扣後站配額。集合只做成員查詢，不用迭代次序決定結果。 |
| 升一級 | D1→D2→D3→D4，保留use、occupiedCells、ID與人口／工作；一天同格最多一級。升級本身不長人，容量已變大後交原 `grow` 分配填入。D4滿了只可依6b繼續嘗試邊緣住宅，不發明D5或無限覆寫容量。 |

建議把升級放在 §7.1 第5步、同站 `grow` 之前：午夜開始快照只記「哪些格已滿與原等級」，不新增存檔餘數／升級候補；各站仍按既有順序執行 **upgrade→grow→spread**。shares與rate照6b先算一次；升級不改計算share的存量。當晚才長滿的格要等次晚，當晚 spread 的新格不在開始快照；跨站重複升級也禁止。這是新增升級的時點政策，不把既有 grow／spread 改成全圖同時提交。

手算：滿的R D1格56居民／0就業，站q=800、k=3，因此g=`800×10/1000+3=11`。若是該站排序前2個候選之一，先升D2（168／36），再由6b成長分配入人；若站只有此格，share=56，`grown(56,11)=(616+500)/1000=1`，該格成57居民；有邊緣候選再新增4人D1。第三個滿格當天不升，D4不升，q=799或k=0不升；g仍為正的站照6b執行其成長與擴張。數值可逐步手算，不使用亂數或地價觸發。

城市初始化、兩個最新量測欄位、buildingRulesVersion須保存；當晚局部快照／upgradedCells從每次午夜世界重算，不另存歷史。所有核心常數為整數；一般建物類型與升級順序不抽籤，畫面變體若抽籤才用存檔 SeedDraw/FNV-1a。

### 7.3 介面草案與後續驗收

在既有 `City/LandDemand.swift` 接三處即可：`growLand(reached:)` 保存q／k並建立滿格快照，在既有 growing 迴圈內呼叫私有 `upgradeCityBuildings(around:measurement:...)`；`grow(around:residents:jobs:)` 查 `BuildingCapacity` 取代400／1200；`spread(towards:)` 原子建立4人土地與R D1建物。`shares(of:among:)`／`Share.demand`／`grown`／`GameWorld.apportion` 的算式與順序不變。`City/Building.swift`／`BuildingTypes.swift` 提供資料與容量；`Passenger/TownGrowth.swift` 只補最新量測欄位；**不另造 LandService.swift、LandGrowth.swift 或另一份都市成長權威**。

`setLand`／`foundTowns` 在容量啟用時先驗證、初始化兩份相符資料，再沿用 `refreshLandDemand`；單純升級未改人口，無須提前改運量，原growLand結尾一起刷新。spread的土地／建物不能只建立其中一份，ID不足或合法性失敗須留下相符世界。

後續驗收（本文件未執行）：用6b的站成長量與最大餘數手算、容量替換後的168／504／1440／1680邊界、剩1位／已超舊限、分配不足不重分、g≤0不衰退但g>0滿格仍擴張、新格4人與D1自動配對；q=799／800、k=0／1、同站第2／第3候選、站ID與row／column平手、重疊格一天一級、當天才滿不升／D4不升、模型失敗不改容量；舊存檔初始化保留所有人口與工作、同用途兩項一起選級、兩個新量測缺鍵為0；午夜、idle、批量／逐秒／任意切分及存讀一致。地價獨立重算14500例與800m嚴格邊界，驗證不改世界且不寫價格歷史。

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
| `T/avatars/basis/basis_transcoder.js`／`.wasm` | **57,529／527,333 bytes**，WASM magic `\0asm` version1；JS是Emscripten loader。`T/assets/avatar-BUA-61rs.js` **112,468 bytes** 含GLTFLoader／KTX2Loader／meshopt decoder。 | JS＋WASM不是Swift framework可直接link的native轉碼器；建議離線處理。Metal自訂loader路線才考慮native Basis／meshoptimizer，不把WebWorkers與JS載入器搬進GameCore。 |
| `T/assets/anim-CQkLTvTS.bin`；`clips-Cb5uFd0j.js` | bin **439,720**、JS **2,708**；AnimLibrary／Clip的格式如下。`animator-CHWSGVhN.js` **26,675**、`rig-BjRdQXtM.js` **614**、`avatar`的Rocketbox骨架adapter。 | 動畫獨立於GLB，必須還原／retarget後輸出skeletal animation；不能只用GLB轉USDZ就假稱動畫會出現。 |
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
| PNG／WebP／SVG | PNG可直接圖片使用；其他先轉換／decoder | 同左，與幾何loader分開 | 解碼後upload；ASTC壓縮texture用相符格式 | 材質sRGB/linear、alpha premultiplication、normal方向、mips分開核對。 |

RealityKit／SceneKit的選擇不在這份研究鎖定；先用同一份代表素材比較，依Phase8量測決定。軸向建議Z-up ENU的 `(east,north,up)` 轉iOS常用Y-up `(east,up,-north)`，右手座標與normal一起轉，local-facade先依一次placement旋轉；與本遊戲平面y向南的世界位置adapter也要明確。模型公尺與GameCore世界單位僅在快照邊界乘／除64，**Float32網格不為了模擬而量化成整數**。

第一批建議47個far外觀候選＋普通用途程序幾何，不先bundle整個T網站。兩組現存建物檔 **14.980 MiB**，加8個現存角色GLB **3.061 MiB**，原格式約 **18.041 MiB**；若直接加整個T樹，則約 **34.971 MiB**，其中Web啟動圖／JS就有大量不需要的內容。轉成USDZ／解量化頂點／ASTC後大小可能變大，尚未實際轉換，不能宣稱會節省多少IPA。

manifest對8件現存角色的 `gpuBytes` 加總 **19,279,808 bytes**，fallbackGpuBytes宣告 **103,459,496 bytes**；這是**來源估算**，不是本次iOS量測。英雄單件6247984、群眾1130640；轉PNG或RGBA可能顯著放大GPU佔用。遠景625323頂點若同時全載至少14.313MiB原vertex payload，還有material／framework複製；drawGroup逐件mesh會增加draw calls，不能只算檔案bytes就保證效能。

產物manifest建議每件存source repo SHA、source path/hash/bytes、轉換工具版本／參數、axis/unit、輸出hash/bytes、vertex/material counts、LOD可用性、license／source標示。loader先驗這份契約；可見分塊、screen-size LOD、相同材質合批、普通建物instancing／遠景proxy；性能設定只影響畫面。缺near時放大仍用far或明示低細節後備，不能產生來源不存在的模型資料。

### 8.4 授權與來源要求

依CLAUDE.md，作者提供的Ci／Railway資料視為授權可移植來源，不另發明整包禁用政策；仍保留特定素材明示條款。

- **Microsoft Rocketbox**：`T/avatars/manifest.json.license`及8份GLB asset.copyright明記 **MIT License、Copyright (c) 2020 Microsoft**，含原avatar來源與頭部來源。manifest指 `CREDITS.md / LICENSE-ROCKETBOX.txt`，GLB指LICENSE-ROCKETBOX.txt，**本包兩檔均缺（gap）**。發佈素材前補入正確MIT全文與copyright，轉換不能刪掉來源標示；這不是要求重買模型。
- **OSM建物輪廓**：兩組model.sources中有 **91個ODbL-1.0 source標示（49＋42）**；另89個source entry未寫license（25＋64），多為官方／觀光／外觀參考頁，不能把「沒寫license」全部叫成未授權模型。保留每件sources及placement/footprintReference的OSM標示；顯示 © OpenStreetMap contributors與ODbL連結，若發佈衍生輪廓資料庫，提供對應資料與同授權。材質網格是來源作者外觀建模，照片／商標flags為false，不把參考照片URL當可打包貼圖。
- **Basis／meshopt／Three.js**：`T/avatars/basis/*`、`T/assets/avatar...`、`T/assets/three-CUv1qSsi.js`（**737,923 bytes**）的現存檔未找到完整license/copyright告示；只辨認到技術名稱，**不能以記憶替這個bundle宣告MIT或Apache版本（gap）**。若採native dependency，選定確切版本後附其實際LICENSE／NOTICE；若只離線轉出自己的資料，仍記錄工具與輸出來源，依所用工具真正條款處理。R/vendor/three.module.js的license不能替T所有bundle一概背書。
- **site／標題／atlas／動畫**：本包沒有另外的逐素材license文件；來源作者授權可用的前提仍成立。維持site source、動畫clips.src等來源，對明示第三方項再補告示；沒有證據要求任意替換角色或場景。PNG／WebP與程序生成atlas不因可解碼就自動有新的授權。
- **實景背景**：決策50的MapKit標誌／法律連結與資料限制照原決策；自有建物／OSM素材可畫在背景上，但不擷取Apple建物、地形或搜尋結果做可保存模型資料庫。OpenFreeMap樣式／圖磚契約與iOS自有模型來源分開記錄。

授權gap搜尋：`LICENSE`、`LICENCE`、`NOTICE`、`CREDITS`、`copyright`、`license`、`Rocketbox`、`Microsoft`、`ODbL`、`sources`、`reviewedPhotos`、`sourcePhotosIncluded`、`operatorLogoIncluded`。只盤點檔案內標示，沒有逐站開網站、下載照片或重查外部條款。

## 9. 參考對照表草案（目標名稱尚未採納）

| 參考檔案／函式／鍵 | 目標檔案／函式草案 | 定點比例與保留／改變 |
| --- | --- | --- |
| `T/assets/world-DCb11kLR.js`：DO／lO／UD／WO、RD／zD／VD／HD | `tools/building-assets/import_taipei_scene.*` 產生佔格／保留格；`Sources/GameCore/City/Building.swift`：validateOccupiedCells／initializeCityBuildings（城市內部流程） | 米→64世界單位；cell4096；小距離量化見§2.1。來源旋轉矩形／3×3細查不進核心；格化差異需明示。 |
| `T/assets/engine-Dl04UrJP.js`：hr.buildBlocks／districtAt／surfaceAt、V／Kn／K | 同匯入工具；`Sources/GamePresentation/BuildingStyle.swift`：style(for:)；`RailwayGameApp/Rendering/BuildingLayer.swift` | bounds偏移後×64；style機率若需要整數則×1000；9區外觀保持，容量為原生表。 |
| `T/assets/world-DCb11kLR.js`：Eg.pickType／floorsFor／layoutBlock、site lot／claims／placement／anchors | `GamePresentation/BuildingStyle`與工具；`City/BuildingTypes.swift`：capacity(for:) | 類型外觀可adapt；樓層2/6/18/40、面積1536、48/32㎡為gap新值，不能稱直接移植。任意輪廓只在畫面。 |
| `R/blender-buildings.js`：buildingCatalog／buildBlenderBuilding／inspectBlenderBuilding | `Sources/GamePresentation/BuildingAssets.swift`：loadCatalog；`RailwayGameApp/Rendering/BuildingMeshLoader.swift`：loadMesh／inspectionMaterial；或離線USDZ | 24byte Float32 vertex格式只畫面；metres與axis一次轉換；opacity.24可保留。GameCore不importFoundation/SceneKit/RealityKit/Metal。 |
| `R/assets/{blender-buildings-v1,historic-buildings-v2}/{catalog,placement}.json`、各model／far bin；`R/landmark-catalog.js` | `tools/building-assets/convert.*`、轉換manifest、App Resources/Buildings；GamePresentation landmark catalog | anchor地理投影在GameCore外；GeoAnchor仍1/10,000,000度；rotationDegrees只畫面；缺near明列，尺寸不推容量。 |
| `T/avatars/*.glb`、manifest、basis/*；`T/assets/avatar-BUA-61rs.js` | `tools/building-assets/convert_avatars.*`、App Renderer character assets | meshopt／quantization／KTX2解碼後native輸出；GLB非GameCore資料；保留MIT告示。 |
| `T/assets/anim-CQkLTvTS.bin`、clips-Cb5uFd0j.js：AnimLibrary／Clip | 同工具decodeAnimPack／retarget；App character animation | Int16位置1e-4m、root1e-3m、yaw4π/32767僅畫面；輸出骨架動畫，世界位置讀GameCore。 |
| `Ci/.../styles/liberty.json`、planet.json；app的mlLayerBeforeBuilding3d／setBuilding3dEnabled呼叫 | App實景建物extrusion／疊圖；已有背景保留 | render_height/min_height公尺；opacity.8；只有畫面，PMTiles／外部建物API缺檔。 |
| 6a `Sources/GameCore/City/Land.swift`：cellLength／middle／totals；SeedDraw | `City/Building.swift`／BuildingCapacity；`City/LandValue.swift`：landValue(at:) | 4096單位格、51200半徑、rate/weights1/1000；FNV-1a原值不變。建物容量／地價全部原生gap。 |
| `City/LandDemand.swift`：shares／Share.demand／growLand／grow／spread；`Passenger/TownGrowth.swift`：growth／Place；`GameWorld.swift`：reachedStations(endingDayAt:release:workedOutAt:) | 沿用 `City/LandDemand.swift`：grow 查 BuildingCapacity、spread 自動建R D1、growLand 內部升級；既有 Place 新增 lastService／lastReached | 服務share與成長率1/1000；40/100旅次；400／1200由表容量取代；新格4人；升級q≥800、k≥1、每站2格為原生值。reached沿用6b，不另做聯集。 |
| 四處來源的地價／容量／費用搜尋（無規則） | `City/BuildingTypes.swift`／LandValueRules；費用另Phase7提案 | 容量人／職位整數；地價美分/m²；本PR不新增經濟成本或資料程式。 |

T、R前綴在§2／§3明訂。目標檔案是供後續作者設計的草案，不表示已建立這些檔案，也不要求覆蓋已合併的6b實作。

## 10. 建議PR拆分、驗收與作者要決定的問題

普通建物屬城市，由內部流程自動產生／升級；下列6c PR不含玩家建物指令。GameCore、存檔／schema由Claude Code依作者定案實作，本研究不修改那些檔案。

| PR | 範圍 | 後續驗收條件（本研究沒有跑） |
| --- | --- | --- |
| 6c-1 城市建物、容量表與初始化 | BuildingID／佔格資料、三用途×四密度、唯讀容量；新局與既有土地的內部初始化、existingStock、保存／遷移 | 同格只供一次cap、用途相符；中心260住宅例D3、65／780核心C/O皆D4；台北最大197／285與測試錨點211／285可重算、78／285辦公選D4；初始化保留總人口／工作、超表存量不裁、末格合法；舊保存例仍可讀、不重生；不新增玩家place/replace/remove。 |
| 6c-2 接上6b容量、邊緣建物與自動升級 | **修改既有LandDemand.swift**的growLand／grow／spread接點，容量取代400／1200、新格4人配R D1、q／k最新量測、滿格自動升級與配額；Place存檔欄位 | shares／Share.demand／grown／最大餘數與站序不改；兩項逐格cap、放不下不重分也不留餘數；土地不衰退、g>0滿格仍嘗試擴張；q=799/800、k=0/1、每站第2/3格、重疊一天一級、D4／existingStock不上調；午夜／idle／切分／存讀一致，新增獨立手算／模型與保存例，由作者協調schema，不改既有fixture期望來湊結果。 |
| 6c-3 即時地價查詢與顯示 | §6公式、保存的lastService／lastReached唯讀查詢、面板分項／地價圖層 | 獨立算14500例、無服務2500、最高27000；800m嚴格邊界、最佳站平手按ID、A直接取6b量測不聯集；缺量測為0、界線與乘法安全；lastGrowth不冒充服務比例；日內路網變動等次晚量測，讀存檔同價；不寫price歷史、沒有公司房產指令或費用／租金帳。 |
| 8a 素材manifest與far建物試片 | 工具固定版本／來源hash／axis／licenses；47far和3種代表素材（101、山佳、總統府）；不改核心 | 輸出hash與bytes／頂點／材質報告；和來源bounds／orientation對照、缺near後備、double-sided／linear RGB核對；macOS loader與實機外觀驗證，OSM來源可見；不同LOD下core digest不變。 |
| 8b 角色／動畫轉換試片 | 先1英雄jie＋1群眾student-m；meshopt/KTX2／骨架／ANM1轉換、MIT全文 | 骨架joint數、rest pose／idle/walk回圈／root方向、alpha hair／mask／normal/mips；輸出格式能在選定iOSrenderer讀取，量測輸出大小／GPU記憶體；不聲稱缺LOD／fallback已存在。 |
| 8c 量測後擴充renderer | 程序普通建物／site外觀、分塊／剔除／LOD／instancing、其他素材按需要加入 | iPhone／iPad最低目標裝置報告frame time、峰值記憶體、冷啟動與切區I/O、draw calls；明確選裝置與同場景，不預設未測數字；性能設定／模型失敗不改模擬。 |

**Phase 7另外拆公司房地產PR**：玩家自建／購買／持有建物、公司資產與負債、建造／維護費、交易、租金、拆除／搬遷，按作者的經濟規則設計；不能把城市自動升級當公司買樓或收費。這個階段歸屬已定，不列為問題。

| 作者需要決定 | 建議答案與理由 |
| --- | --- |
| 容量表與混合用途配比是否先採本表？ | 原生初值為1536m²／層、48m²／居民、32m²／職位、2/6/18/40樓、R/C/O住宅配比7/8、2/8、1/8。先採可手算版本，但應以6b密度重跑平衡：65／780核心要D4、台北78／285辦公也要D4，僅容納原有人口即可造成40樓。若過高，先調混合配比／代表樓層表，不改來源人口或假稱來自模型。 |
| 滿格門檻、好服務與每日升級配額是否採§7.2？ | 建議任一正容量達滿、昨日q≥800且k≥1、每站最多2格，StationID→row→column、同格一天一級，滿格判斷用午夜開始快照；升級放同站grow之前，當晚即可用新增容量。數值全原生，可再用案例調平衡；不用地價或lastGrowth觸發。 |
| 是否新增lastService／lastReached兩個存檔欄位？ | 建議同意，只保存最後一筆0…1000／0…5量測，缺鍵0、下一個有基準午夜更新；counted無法保留昨日差值，lastGrowth不是服務率，reached目前不保存。欄位讓日內估價與存讀一致，且滿格仍能判斷好服務，不新增價格歷史。 |
| 表外既有存量如何處理？ | 同用途最低足夠級別；超表用一次性existingStock、D4密度與兩項max覆寫，保留全部存量，第一版不自動再提高。兩份台北初始化都無表外格；不能據此忽略其他合法匯入或舊局。 |
| 小site與多格資料如何使用？ | 城市第一版一格一開發單元，畫面可多棟細模型；地標預設裝飾，不以508m推就業。核心資料保留occupiedCells集合，真正多格有容量建物與配額可在另案定，公司建物屬Phase7。 |
| 未有禁建遮罩與不足64m邊格怎麼辦？ | 沿用6b的合法列／行與spread；邊格按一個邏輯格capacity、畫面裁切，不以模型決定水／道路。新增固定禁建資料會變更6b擴張，須另案明訂；Phase7交易面積另按bounds裁切。 |
| 地價係數與代表站是否採§6？ | 建議最近完成日q／k、最佳w×q站（平手小ID）、A讀該站6b reached，沿用B/D與15×S＋1000×A公式。日內改線等下次午夜量測；只即時推導價格，不另做目的地聯集。 |
| Phase8先選哪種iOSrenderer與素材範圍？ | 先47far＋程序普通建物，拿相同3建物與2角色試片比較SceneKit／RealityKit（必要時Metal），實測後選；本研究不鎖定。現階段不等43site／47near缺檔補齊才開始。 |
| 缺近景與授權全文的補齊優先序？ | 先保留far後備；角色發佈前補Rocketbox MIT全文，native dependency選版後帶LICENSE/NOTICE；按真正需要取得near／缺site，來源metadata保留，不替整包捏造授權。 |

未放入的成長不跨日累積、沒有逐格餘數、土地不衰退、正成長站每晚至多一格4人住宅，是既有6b規則，沿用而不再列為待決。既定64m格表示、整數核心／SeedDraw、價格不存歷史、一般建物城市自動生成／升級、公司建物與費用Phase7也不再重問。正式決策由作者寫入架構／路線圖；本PR不動那三份共享文件。

## 11. 查閱方法、gap清單與驗證邊界

**VERIFIED（雲端Linux工作區，靜態查閱／檔案結構核對）**：按順序讀規範與指定分支；clone私有庫並釘住上述commit；rg列檔與搜尋；Prettier **3.6.2**只在repo外展開world／engine／Ci app／island／avatar／clips等bundle；Python標準函式庫解析catalog／placement／全部47 model與far，核對bytes、SHA-256、finite floats、stride／triangle數與drawGroup總數／界線；讀8GLB header／JSON／skin／extensions／KTX2 header與ANM1 header；逐條檢查dynamic imports、near／GLB／fallback／source-path存在性。file工具查WebP／PNG尺寸。不是Swift或iOS執行驗證。

**本次修訂 VERIFIED（同一雲端Linux工作區）**：讀指定6b提交d2b3833的LandDemand／Land／LandImport、TownGrowth.Place與growth、GameWorld的午夜reached處理、決策72／73；Python依實際資源檔、Mercator逆投影、members／slots／最大餘數逐格重算兩種台北錨點與FNV-1a種子1城鎮，結果與來源逐步算式見§5.3。用提交前原稿逐段比對，§2–§4、§8未修改。這是來源閱讀與算式重現，不是Swift執行、成長模擬或測試結果。

集中gap及實際搜尋：

| gap | 用過的關鍵字／查法 | 提案處理 |
| --- | --- | --- |
| 原生建物容量、自動升級、入住／就業、地價／租金／開發公式 | population／residents／employment／jobs／capacity／building／floors／landValue／landPrice／propertyValue／realEstate／rent／rental／townGrowth／development／地價／地价／租金／開發／开发；四處來源按命中讀code／metadata | §5容量、§7.2升級門檻／配額與§6價格明確原生，不稱來源值。 |
| 43site、postfx、5個content依賴 | import(／site-／build-／postfx／register-DEjbkm8D、逐路徑exists | §2列完；現存proxy／far後備，不宣稱完整網頁能跑。 |
| 47near、94 GLB宣告、hero thumbnails／source snapshots／.blend | catalog.files／metadata／thumbnail、lods.file/glb、sourceSnapshot／referenceFile／sourceFile／source-layouts／near.mesh.bin／near.glb／far.glb／.blend | §3列每件大小；只有現存far是可用mesh。 |
| 9avatar／17fallback／角色LOD | manifest.avatars.file/fallback/lod1、.glb與實際存在性 | §8列缺檔；manifest totals與實際總量分開。 |
| 完整建物圖磚／語意圖／Ci外部3D介面 | PMTiles／city.pmtiles／render_height／building-3d／metroCreateOsmMapLikeSingaporeDemo／setBuilding3dEnabled | 僅採現有style/schema，不抓外部資料、不給不存在的要素統計。 |
| 原生可建遮罩／公尺輪廓到64m量化精度 | Land／surfaceAt／claims／water／park／road／placement／footprint | 明定粗格語意，另補整數遮罩；沒有量測就不宣稱等價。 |
| Rocketbox與依賴完整LICENSE/NOTICE | LICENSE／CREDITS／NOTICE／copyright／license／Microsoft／Rocketbox／ODbL與源metadata | 已有來源授權照規範，特定明示條款補告示；不替未知bundle推測條款。 |

**UNVERIFIED／沒有檢查到**：未執行Swift的LandImport／Land.towns、Swift建置或測試、CI、網頁場景、Three.js、Blender、SceneKit／RealityKit／Metal、Xcode／Simulator／實機；未進行任何資產轉換，沒有轉後USDZ／ASTC／IPA大小或frame-time／GPU基準；未解meshopt後逐三角形看角色外觀，沒有retarget動畫驗證；未逐件目視47外觀／立面／高度或核查所有原照片；未驗證缺near／GLB／sourceSnapshot的hash；未下載外部PMTiles／site／模型／照片、未對每個vendor與網站做全面授權調查；未量測64m佔格對道路／小基地的量化誤差，也未跑容量／地價平衡或6b成長情境。靜態核對不能代替這些檢查。

本文件為可審查的參考事實與設計提案；後續PR依§10逐項驗證並如實報VERIFIED／UNVERIFIED。
