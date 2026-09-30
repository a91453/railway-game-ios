# Stage T–W 的參考對照（Railway 網站）

這份文件把作者 `Railway/` 網站的實體層，逐函式對照到 [ROADMAP](ROADMAP.md) 的 Stage T、U、V、W 與折返。內容包括：

- 對照表；
- gap 分析；
- 建議的實作順序。

規則見 [WEB_REFERENCE_STUDY](WEB_REFERENCE_STUDY.md#來源與使用方式)：作者的程式照原樣翻成 Swift，只做 GameCore 需要的機械換算。參考沒有的東西標成 gap。

## 來源

- 私有 repo `a91453/railway-reference-private`，commit `b52f05c`（2026-09-30 讀取）。以唯讀方式附加，clone 在公開 repo 之外。
- 下文的路徑都在 `Railway/site_archive_clean/` 之下；`index.html` 的行號以這個 commit 為準。
- 逐檔讀過的檔案：
  - `rail-3d/physical/` 的每一個 JS：`motion.js`、`timing.js`、`turnbacks.js`、`route-runtime.js`、`plan-binding.js`、`topology.js`、`client.js`、`metro-motion.js`、`afr-operation.js`、`structure-kind.js`、`display-level.js`、`portal-paths.js`。
  - 同一個目錄 JSON 的結構與統計：`dispatch.json`、`network.json`、`metro-network.json`、`display-profiles.json`、`level-profiles.json`。
  - `index.html` 裡被這些檔案呼叫、而且與派車、跑段曲線、交會、待避、跟車有關的函式（8082–9017 行），以及更新紀錄裡描述派車規則的條目。

### 這個網站是什麼

`Railway/` 顯示台鐵、高鐵、阿里山林鐵的真實班表。瀏覽器裡的列車位置是**依時間取樣**得到的：

```
位置 = f(班表, 事先算好的等待 holds, 跑段曲線, 實體路徑)
```

它不是逐 tick 的模擬。

- 在瀏覽器裡計算的：
  - 跑段曲線（`buildProfile`）；
  - 單線交會與同向待避的推估：挪動時刻表的通過時刻，或加入停留（`resolveTraTraffic`）；
  - 同股道後車的顯示延後（`updateBlockHolds`）。
- 事先由建置腳本算好、存成資料的：
  - 每班車綁定的實體路徑（`pathIds`）；
  - 整列車資源預約的結果，也就是各站的等待秒數（`holds`）；
  - 預約用的車長（`lengthM`）。
- **建置腳本不在快照裡。** `motion.js` 的註解提到 `scripts/lib/track_section_via.mjs` 與 `scripts/lib/track_directions.mjs`，私有 repo 裡找不到。所以整列車預約「怎麼算」沒有程式可以翻譯，只有結果和更新紀錄裡的文字。

### 哪些可以移植

| 內容 | 性質 | 移植 |
| --- | --- | --- |
| `rail-3d/physical/*.js`，以及 `index.html` 裡的函式與常數 | 作者自己的程式與平衡數值 | 可以，照原樣翻譯 |
| `network.json`、`metro-network.json` | 從 OpenStreetMap 導出（檔內標示 ODbL-1.0） | 可以使用，遵守 ODbL 的標示與分享義務；這次還沒移植 |
| `display-profiles.json`、`level-profiles.json` | OSM 加上 DEM 與國土測繪中心的橋隧幾何 | 可以使用，遵守各來源的授權義務；這次還沒移植 |
| `dispatch.json` | 由 OSM 路徑與真實班表導出的結果 | 可以使用，遵守 ODbL 的義務；V 會先移植格式的語義（`holds`、`lengthM`、`conflictPolicy`） |
| `data/tra_track_sections.json`、`tra_run_profiles.json`、`tra_pass_obs.json` 等 | 真實路線與觀測資料 | 可以使用；接進模擬時，依 TIMETABLE_DATA_STUDY 的規則在明確時點記錄成世界的輸入；這次還沒移植 |
| `PERF_RULES` 以車名比對、`SPEED_ZONES`、`AFR_TURNBACKS` | 綁定真實車種或地名的資料表 | 機制可以移植；表的內容對虛擬地圖沒有意義，見 gap |

`dispatch.json` 的統計，用來說明規模：

- 共 1,270 份計畫（台鐵 1,004、高鐵 214、林鐵 52），`conflictPolicy` 是 `"scheduled-hold"`。
- 有等待的計畫 48 份；非零的出發等待 59 筆，最長 184 秒。
- `lengthM` 依車種是 34、57、60、160、168、245.7、274.8、304 公尺。
- 這和 [TIMETABLE_DATA_STUDY](TIMETABLE_DATA_STUDY.md) 記錄的「約 4%，單次最長約 3 分鐘」一致。

## 重新確認：「參考沒有號誌、待避」

舊的 ROADMAP 寫「參考遊戲沒有號誌、閉塞或待避站」。這句話只適用 `Ci/`。

- **`Ci/`（交通經營遊戲）：確認沒有。**
  - 目前快照的 UI 字串與作者的程式裡，沒有待避、越行、閉塞或號誌（搜尋到的只有第三方的拼音字典與 `AbortSignal`）。
  - 有的只是班距與共線容量：`MIN_HEADWAY_MINUTES = 1.5`、`maxTrainCountWithNetworkSharedTrack` 等，已在 Q2、Q3 移植。
  - 舊研究推論的「同線同向防撞」在目前的快照只剩常數定義（`MIN_TRAIN_GAP = .04`、`SLOW_FACTOR = .24`、`MID_SLOW_FACTOR = .5`、`LAUNCH_FACTOR = .06`、`MIN_CURVE_RADIUS_M`），整個 bundle 裡各只出現一次，找不到使用的地方，所以無法再確認它的行為。
- **`Railway/`（股道網站）：有待避與交會，沒有號誌與固定閉塞。**
  - 同向待避：`planSameDirectionOvertakes`。
  - 單線交會：`inferMeetPassTimes`。
  - 排定的等待：`dispatch.json` 的 `holds`，`conflictPolicy: "scheduled-hold"`。
  - 股道與月台指派：`pathIds`、`plan-binding.js`。更新紀錄還寫到高鐵「停靠列車停外側到發線，通過列車走內側正線」。
  - 同股道的跟車：`updateBlockHolds`。
  - 沒有號誌機、閉塞區間或聯鎖的資料模型。`updateBlockHolds` 的 "block" 是依前車顯示位置保持的移動距離，不是固定閉塞。

## 對照表

欄位：參考檔案與函式 → 參考的行為 → Stage → 現有 GameCore 對應 → 預計的 Swift → 倍率 → 分類。

分類：

- **faithful**：照原樣翻譯；
- **機械**：只做固定小數、整數或 deterministic 的換算；
- **已涵蓋**：S1–S5 已有對等的規則；
- **gap**：參考沒有，或只有結果沒有演算法；
- **呈現**：屬於畫面，不進 GameCore。

### Stage T：進路預約

T 已經實作（PR #40，ARCHITECTURE 決策 32）。它和這個參考的關係：

- **一致的**：
  - 整列車一次預約到下一個停靠點，拿不到就在站上等待，對應參考「整列車的資源預約、衝突時排定等待」的結果；
  - 站著的列車仍然擋住它佔用的軌道，對應更新紀錄的「停站也算佔用」；
  - 資源由拓撲的身分決定，不因座標接近而合併。
- **T 自己的設計**（參考沒有程式可以翻譯）：
  - 預約的範圍與生命週期；
  - 限界（交會點 1024 以內也持有節點）；
  - 錯誤順序與存檔。
- **沒有採用的**：
  - 預約另有車長（`lengthM`）：T 用實際的車身；
  - 排除被佔資源的繞路（`shortestPath` 的 `blocked`）：T 不繞路，留給 V。

| 參考 | 行為 | 現有 GameCore | 預計 Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `topology.js` `makeTopology`：`edge.resource = 系統:排序後的兩端節點` | 佔用資源是一段股道；重複畫出的同一段共用一個資源，不能冒充第二股 | `TrackResource` 的 `.node` 與 `.span`（S1、S3A）；資源由邊與里程決定，不會重複 | 不需要新的 | — | 已涵蓋（我們的資源是 span，比參考的一整段邊細） |
| `topology.js` `canTurn` | 不能倒車轉進道岔另一支；平面交叉只走最直的一支；車止不能通過；未標記的分岔只在近乎平行時當道岔 | `transitions(after:)`：由切線推導，1:16 以內才相通（S3） | 不需要新的 | — | 已涵蓋（判準不同：我們用建造時的切線，參考用 OSM 標記與餘弦門檻） |
| `topology.js` `shortestPath({blocked, penalties, maxLength, allowYard})` | 以「從哪條邊進來」為狀態的 Dijkstra：可以排除被佔的資源、加權、限制總長；預設不走 yard 與 spur；渡線的成本加上 4 倍長度 | `TrainRoute.shortest`：只有長度，沒有排除或加權 | T 或 V：`TrainRoute.shortest` 加上排除的資源 | 長度：GameCore 單位 | 排除與加權是 faithful；**gap**：參考的建置腳本怎麼用它不在快照；我們沒有 yard、spur、crossover 的鐵軌種類 |
| `dispatch.json` `plans[].lengthM` | 預約用的車長，與畫面上的編組長度分開（台鐵區間車 60 公尺） | `Train.length`：一個長度同時用於佔用與畫面 | T：預約是否另有長度，待作者決定 | 公尺 × 64 → 單位 | **gap**：用法在建置腳本裡；數值綁定真實車種 |
| 整列車的資源預約（建置腳本） | 依實體路徑與班表，預約整列車經過的資源；衝突時排定等待。更新紀錄補充：停站也算佔用；佔用時刻與畫面的跑段曲線同源 | 沒有預約 | T：`Railway/TrackReservation.swift`，以及 `GameWorld.advance` 的出發段 | — | **gap**：演算法不在快照。只能沿用 PR #31 的語義（ARCHITECTURE 決策 29 第 12 點），加上上面兩條作者寫下的規則 |

### Stage U：列車只能進入預約到的軌道

| 參考 | 行為 | 現有 GameCore | 預計 Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `index.html` `updateBlockHolds`（8856 行），常數 `BLOCK_GAP_KM = 0.4`、`BLOCK_GAP_MIN_KM = 0.02`、`BLOCK_GAP_GROW = 10/3600`、`BLOCK_CAP_SEC = 120`、`BLOCK_MIN_V = 5/3600`、`BLOCK_AT_STOP_KM = 0.1`、`BLOCK_SNAP_SEC = 300`；`blockClearance3d`：min(0.4 km, 兩車編組長度的平均) | 同線同向的列車依位置排序。後車離前車太近時，它的**顯示時間**延後（最多 120 秒），距離門檻逐步回到 0.4 km；停在站上的車當作障礙物 | 列車互不阻擋 | U：movement authority 用預約的資源；跟車距離可以當作授權終點前的保留距離 | 距離：km × 64000 → 單位；時間：秒 | **呈現** + **gap**：它在畫面每一格執行，結果隨畫格間隔（`dSim`）改變。它延後的是顯示位置，不是模擬。移進 GameCore 就改變了它的角色，要作者決定 |
| `motion.js` `sample` | 依時間取樣位置：`arrSec + holds[i].arrival`、`depSec + holds[i].departure`；跨午夜；交接班次 | 位置由 `advance` 推進 | 不進 GameCore（Web 宿主的畫面可以沿用） | — | **呈現**（WEB_PORT_READINESS 已註明：宿主只插值） |

### Stage V：待避、交會、月台分配與排定的等待

| 參考 | 行為 | 現有 GameCore | 預計 Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `dispatch.json` 的 `holds[i] = {arrival, departure}` 與 `departureHolds`；`motion.js` `record` 的套用方式 | 排定的等待：第 i 站的到達與出發各自加上一個秒數，不自動往後傳遞（預設 `arrival` = 前一站的出發等待） | 決策 20 的出發閘門：`departure(i) ≤ now` 才出發 | V：閘門改成 `departure(i) + hold(i)` | 秒 → 分鐘：無條件進位，才不會早走 | faithful（語義）；等待的數值由 V 的規劃產生，參考的資料這次沒有移植 |
| `index.html` `inferMeetPassTimes` / `inferMeetRun`（8435–8563 行），常數 `MEET_HEADWAY_SEC = 300`、`MEET_NEAR_SEC = 1800` | 單線交會：在兩個停靠站之間的一段跑段裡，挪動通過站的通過時刻，讓對向車先到或先開。對向車在站上至少停 30 秒（終點站除外）；安全間隔 m = 30 秒，或 min(30, ⌊停留 ÷ 3⌋)；挪動不超過 300 秒；每段最多 8 輪，依挪動量、再依站序取最小；挪動後用 `reanchorRunProfile` 重建曲線 | 單雙線：`parallelTracks`、`lineTrackCounts`（S1）；時刻表沒有「有時刻的通過站」 | V：`Railway/Dispatcher.swift` 的交會推估 | 秒；距離單位 | faithful（演算法）+ **gap**：我們的時刻表以分鐘計，沒有有時刻的通過站；它依賴 W 的曲線 |
| `index.html` `planSameDirectionOvertakes`（8642 行）、`overtakeRunBuildable`、`resolveTraTraffic`（8716 行），常數 `OVERTAKE_LOOKAHEAD_KM = 25`、`OVERTAKE_CLEAR_SEC = 30`、`OVERTAKE_MAX_WAIT_SEC = 600` | 同向待避：找出在相鄰兩個共同車站之間先後順序對調的一對車（後車追越前車）。往回 25 km 內找前車的一個通過站，條件是前車領先至少 `30 + v/b` 秒；前車在那裡停到後車出發後 30 秒，最多等 600 秒；兩段曲線都要建得出來。整個流程先做交會，再做最多 8 輪待避 | Q3 的快車與慢車；列車互相穿過 | V：`Railway/Dispatcher.swift` 的待避推估 | 秒；km × 64000 → 單位；v/b 以 W1 的整數性能計算 | faithful；依賴 W1（`buildProfile`） |
| `plan-binding.js` `createPlanBinding` | 班表綁定實體路徑：完全相同 → 只改時刻 → 同車次改點 → 借同系統別班的路徑 → 分段接力借用（動態規劃：型態不符最少、段數最少、key 穩定）；`templateEligible: false` 的股道不借給別班 | 每次出發都重新求路（S5），同線班次不共用路徑 | V：同一條線路的班次共用各段的路徑 | — | 部分 faithful：「同線共用路徑、限定車種的股道不借」可以移植；比對真實班表改版的部分對虛擬地圖沒有意義，是 **gap** |
| 更新紀錄（`index.html` 4641、4667 行等） | 高鐵：停靠列車停外側到發線，通過列車走內側正線；待避優先利用前車原本的停站時間；依車種的煞車性能選待避站 | 沒有月台分配 | V：月台分配的規則 | — | 規則只有文字，程式在建置腳本裡：**gap**（可以照文字設計） |

### Stage W：行駛曲線

| 參考 | 行為 | 現有 GameCore | 預計 Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `index.html` `buildProfile(Lkm, T, aK, bK, vK, coast)`（8213 行） | 給定距離 L 與時間 T，解出定速 vc：D = 1/(2a) + (1−ρ)²/(2c) + ρ(2−ρ)/(2b)，vc = (T − √(T² − 4DL)) / (2D)。四段是加速、定速、惰行（有 coast 時）與煞車；判別式為負、vc ≤ 0、定速時間為負或 vc > vmax 時沒有曲線。有 coast 時先用 ρ₀，超速就在 [ρ₀, 1] 上二分 14 次 | 固定的 rate，⌈距離 ÷ rate⌉ 分鐘 | W1：`Railway/RunningCurve.swift` 的 `RunningCurve` | 距離：GameCore 單位（1/64 m）；時間：毫秒；a、b、c：千分之一 km/h/s；v：km/h；ρ：千分之一，二分在分母 1000 × 2¹⁴ 上精確 | faithful + 機械：平方根改成整數平方根；vc 以等價的 2L / (T + √disc) 計算，避免整數相減的精度損失 |
| `index.html` `profTimeToProg`、`profProgToTime`（8315、8333 行）；`timing.js` `profileProgress`、`segmentTime` | 時間 → 里程與里程 → 時間：分四段的解析式，反解用平方根 | 沒有 | W1：`RunningCurve.distance(at:)`、`RunningCurve.time(at:)` | 同上 | faithful + 機械 |
| `index.html` `PERF_DEFAULT`、`PERF_HSR`、`PERF_DR1000`、`PERF_BY_TYPE`、`PERF_RULES`、`resolvePerf`、`speedCapOf`（8082–8109 行） | 車種性能：a、b（km/h/s）、v（km/h）、備用的 aAlt、bAlt、惰行 {c, ρ}；依車名或車種選擇 | 只有 rate | W1：`TrainPerformance` 的預設值，數值照抄 | 千分之一 km/h/s、km/h、千分之一 | 數值 faithful；**gap**：我們的列車沒有車名或車種，用哪一組要作者決定 |
| `index.html` `assignRunProfiles`（8367 行） | 跑段是兩個停靠站之間（通過站不切段）；通過站的時刻由 `profProgToTime` 推導；依序改用 bAlt、aAlt；都建不出來就等速 | 線路的一段 = ⌈距離 ÷ rate⌉ | W2：`LineJourney` 的各段時間 | 秒 → 分鐘 | faithful；**gap**：參考的 T 來自班表，我們的班表由線路推導（見 gap 分析 1） |
| `index.html` `buildObsProfile`（8247 行） | 通過實測時刻點的單調三次 Hermite 曲線，速度上限 `VS_MID`、`VS_END = 0.85 × VS_MID` | 沒有 | 之後的 W | — | 可以移植；需要觀測資料，資料要在明確時點記錄成世界的輸入。W1 還沒移植 |
| `index.html` `SPEED_ZONES`、`runSpeedZones`、`speedZoneKnots`、`zoneProfileOk`、`zoneNatural`（8110–8212 行） | 綁定地名的限速區段；在曲線上插入節點，讓區段內不超速 | 沒有；ARCHITECTURE 決策 29 說曲線限速要由取樣推導 | 之後的 W | km/h | 機制 faithful；**gap**：區段資料是真實地名；我們要由曲率推導區段。`Ci/` 的 `MIN_CURVE_RADIUS_M` 在快照中沒有使用處 |
| `index.html` `trainSeg`、`segProg`；`motion.js` `runOf`、`runBetween` | 依時間求目前所在的站間與比例 | 移動 kernel 每分鐘走 rate | W2：移動改依曲線 | 毫秒 → 分鐘的取樣 | faithful 的是曲線；逐分鐘推進是 GameCore 的機械換算 |

### 折返

| 參考 | 行為 | 現有 GameCore | 預計 Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `turnbacks.js` `isScheduledTurnback`、`AFR_TURNBACKS` | 之字形折返：前一段的終點是下一段的起點，而且同股反向（倒數第二個節點 = 下一段的第二個節點）；只限林鐵的四處 | `ScheduledStop.reverses`：只在停靠站、出發時折返（Q1）；S5 的 `reversedOnNetwork` | 之後：不停車的折返點 | — | 判定可以 faithful；**gap**：我們的折返只在停靠站，名單是真實地名 |
| `timing.js` `turnbackProgress` | 班表沒有列出停車秒數的折返點：在站間的時窗內漸停再起步，不捏造停留。視窗 w = min(0.15, 20 ÷ 段時間)，曲線 2u² − u³ 與 u + u² − u³ | 沒有 | W2 之後 | 秒 | faithful 候選 |
| `motion.js` `reversals` 與 `formationFacing`；`afr-operation.js` `afrInitialFacing` | 依折返次數的奇偶翻轉車頭方向；機車固定在一端，推或拉隨方向改變 | 反向時車頭移到車尾（S2、S3） | 不需要 | — | **呈現**（車輛模型的朝向）；車站序列是真實資料 |
| `dispatch.json` `handoffs`（`basis: "matching-timetable-turnaround"`） | 同一組車在終點折返，接下一班 | Q1 的重複、Q2b 的來回派車 | 不需要 | — | 已涵蓋 |
| `metro-motion.js` `routeFor`：停車點夾在 [半個編組長 + 2 m, 路徑長 − 半個編組長 − 2 m] | 車身不超出車止 | S5 的停車位置：車頭停在行進方向上月台的末端，只停放得下整列的月台 | 不需要 | — | 已涵蓋（規則不同，S5 在前） |

## Gap 分析

需要作者決定或補資料的事，依影響大小排列：

1. **W 的時間從哪裡來？** 參考的 `buildProfile` 是「給定班表的時間 T，找出能準點的曲線」；ROADMAP 的 W 是「由性能推導時間，取代固定的 rate」。建議：
   - W1 只翻譯曲線，不改變任何行為；
   - W2 把線路一段的時間定為 `buildProfile` 建得出曲線的最短整分鐘。
   - 這是把參考的函式當成判斷條件使用，不是新公式；但「由性能決定時刻表」本身是參考沒有的行為，要作者同意。
2. **時間的解析度。** 參考以秒計：安全間隔 30 秒、等待最多 184 秒、跑段曲線以秒解。GameCore 的基本步長是一分鐘（決策 3）。
   - 交會與待避若照參考以秒判斷，時刻表、閘門與存檔就要有秒。
   - 或者把秒無條件進位成分鐘，但這會改變參考的結果。
   - 這是架構層級的決定。
3. **整列車預約的演算法不在快照。** V 的「衝突時排定等待」只有結果（`holds`）與更新紀錄的文字；T 已經依自己的設計實作。建議作者把建置腳本加進私有 repo（`motion.js` 註解提到的 `scripts/lib/track_section_via.mjs`、`track_directions.mjs`，以及產生 `dispatch.json` 的腳本）。有了它們，V 就能翻譯而不是設計，也能回頭對照 T 的規則。
4. **車種性能怎麼選。** `PERF_RULES` 依真實車名（自強、區間、PP、DR1000 等）比對。遊戲的列車沒有車名或車種。W1 先把數值表照抄成具名的預設，列車帶哪一組要作者決定。
5. **跟車規則的角色。** `updateBlockHolds` 是畫面層、隨畫格改變的顯示延後。U 若要採用它的距離（0.4 km、兩車長度的平均），要以基本步長重新表達；若 U 只用預約的資源，這組常數就只給畫面用。
6. **沒有號誌與閉塞。** 兩個網站都沒有號誌機、固定閉塞或聯鎖。U 的授權終點（到下一站、或到下一個可以停車的地方）是 gap，照 ARCHITECTURE 決策 29 第 12 點與 PR #31 的語義處理，並在 PR 裡列出。
7. **限速區段與觀測曲線。** 參考的限速區段綁定真實地名，觀測曲線要用實測資料；兩者都可以移植，W1 還沒做。虛擬地圖上的曲率限速參考沒有，要由我們的幾何推導，這是 gap。
8. **通過站。** 參考的通過站有推導出的通過時刻，我們的 Q3 快車通過站沒有時刻。V 的交會推估需要它。

## 建議的實作順序

相依關係（箭頭是「需要」）：

```
T 進路預約 ✅（PR #40）
W1 行駛曲線核心 ── 不依賴其他 Stage；參考最完整
U movement authority → T
W2 曲線接到行程與移動 → W1，以及 gap 1、2 的決定
V 交會與待避的推估 → W1（buildProfile、v/b）、S1 的單雙線，以及 gap 2、8
V 實際放行 → T、U（保證不互穿）
```

1. **W1**：翻譯 `buildProfile`、`profTimeToProg`、`profProgToTime` 與性能表。純計算，golden 與 property digest 都不變。
2. **U**：建立在 T 上。參考只有畫面層的跟車距離（gap 5、6），授權規則照 T 的語義設計並標成 gap。
3. **W2**：先請作者決定 gap 1、2。
4. **V**：翻譯 `inferMeetPassTimes`、`planSameDirectionOvertakes` 與 `holds` 的語義。它也負責 T 留下的死結：單線兩端互等、時刻表造成的循環等待。

W1 與 U 互不依賴，順序可以對調。
