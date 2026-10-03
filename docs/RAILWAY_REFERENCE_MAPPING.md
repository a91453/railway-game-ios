# Stage T–W 的參考對照（Railway 網站）

這份文件把作者 `Railway/` 網站的實體層，逐函式對照到 [ROADMAP](ROADMAP.md) 的 Stage T、U、V、W 與折返。內容包括：

- 對照表；
- 第三份參考 `Railway/railway_game_reference_clean/`（[RailwayCore 參考包](#railwaycore-參考包)）的對照；
- gap 分析；
- 建議的實作順序。

規則見 [WEB_REFERENCE_STUDY](WEB_REFERENCE_STUDY.md#來源與使用方式)：作者的程式照原樣翻成 Swift，只做 GameCore 需要的機械換算。參考沒有的東西標成 gap。

## 來源

- 私有 repo `a91453/railway-reference-private`，commit `b52f05c`（2026-09-30 讀取）。以唯讀方式附加，clone 在公開 repo 之外。
  - 2026-10-01 對 commit `1563ad0` 重新確認：`Railway/site_archive_clean/` 只改了隱私權與使用條款頁，`Ci/` 只改了三份說明文件（改成直接移植的政策），下文的對照不變。新增的 `Railway/railway_game_reference_clean/` 見 [RailwayCore 參考包](#railwaycore-參考包)。
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

### Stage W2a：時間改用秒

| 參考 | 行為 | 現有 GameCore | Swift（W2a） | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `Ci/` `app__q_c234188b7c397f91.js`：`GAME_SECONDS_PER_REAL_SECOND = 1`；每一畫格 `G.simMin += dt × GAME_SECONDS_PER_REAL_SECOND × simSpeed / 60` | 1× 是真實時間；時鐘是隨畫格前進的小數分鐘 | 一 tick 一整分鐘（決策 3） | `GameClock.now`（秒）、`pendingTenths`；`GameSpeed.x1` 每 tick 0.1 秒 | 秒；宿主 100 ms 一個 tick | faithful（1× 的意義）+ 機械：連續的小數分鐘換成整數秒，不足一秒的十分之一秒保留 |
| `Ci/` 同檔 `transportMaxSimSpeed()`（地鐵 200，航空 1000）與倍速滑桿 | 1× 到 200× | 1×、2×（一 tick 一、兩分鐘） | `x1`、`x10`、`x60`，保留 `normal`（600 倍）、`double`（1200 倍） | — | 部分 faithful：檔位不同；600、1200 倍保留給經營的節奏 |
| `Railway/` `index.html` 的 `<input id="speed" min="1" max="60">` 與 `setSpeed(v)`（刻度 1×、10×、30×、60×，預設 1×） | 依時間取樣的地圖可以從真實時間加速到 60 倍 | — | `x1`、`x10`、`x60` 對上它的 1、10、60 刻度 | — | faithful（檔位）；`Railway/` 依時間取樣、沒有步長 |
| RailwayCore 參考包：`TicksPerTimetableUnit`、`timetable_start` | OpenTTD 的 tick 與日曆脫鉤，時刻表的單位可以選 | 分鐘 | 不採用：列車的時間就是時鐘的時間（gap 2 的決定） | — | 不移植（決定） |
| 沒有參考 | 每分鐘的 rate 分到每一秒 | 一步走完 rate | `TrainMovement.distance(at:fromSecond:toSecond:)`：`⌊rate·(s+1)/60⌋ − ⌊rate·s/60⌋` | 單位／分鐘 → 單位／秒 | **gap**：自訂的整數規則，讓整分鐘與以前相同 |

### Stage W2b：停站、上下車與誤點

2026-10-02 檢查三份參考（`Ci/reference_snapshot/`、`Railway/site_archive_clean/`、`Railway/railway_game_reference_clean/`）。ARCHITECTURE 決策 39。`StationDwell` 的常數以十分之一秒保存（決策 35 第 9 點），W2b 換成整秒。

| 參考 | 行為 | 現有 GameCore | Swift（W2b） | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| 參考包 `02_W2_IMPLEMENTATION_CONTRACT.md`、`01_MIGRATION_MAP.md` 的狀態機（`LoadUnloadVehicle`、`load_unload_ticks`）：ARRIVED → DOORS_OPENING → ALIGHTING／BOARDING → DWELL_HOLD → DOORS_CLOSING → DEPARTING | 到站、開門、上下車、停留、關門、發車都由模擬的 tick 推進 | 上下車在離站時一次完成（決策 35 第 3 點） | `ServiceTimes`（`arrival`、`exchangeEnd`、`closing`、`departure`）、`GameWorld.stepDwell(_:at:)`、`departService(_:at:unroutable:)`；畫面的 `DwellPhase` | 秒 | faithful：下車與上車同時進行（參考的「before/while」擇 while） |
| 參考包 `serviceTicks = max(ceil(alighting / alightingRate), ceil(boarding / boardingRate))` | 上下車的時間取較多的一邊 | — | `ServiceDwell.exchangeSeconds(_:cars:)`，`GameWorld.exchangePassengers(_:at:)` 回傳 `max(下車, 上車)` | 人 → 秒，進位 | faithful |
| 參考包 `departureTick = max(arrival + minimumDwell, scheduledDeparture（timetable-hold）, arrival + dwellTicks)`，`dwellTicks = doorOpen + serviceTicks + doorClose + platformCongestionPenalty` | 早到等排定出發，誤點做完就走；沒有乘客也有最短停站 | 決策 20 的出發閘門：早到等、誤點的下一步就走，沒有停站時間 | `GameWorld.closingStart(of:stop:cycle:times:)` = `max(exchangeEnd, arrival + 最短停站 − 9, 排定出發 − 9)`；`departureDue(of:)` = `closing + 9` | 秒 | faithful；`platformCongestionPenalty` 沒有做（**gap**：包裡沒有數值） |
| 參考包 `TrainRun.actualArrival`、`actualDeparture`、`latenessTicks`，`lateness_counter`；「Delay must be a simulation value」 | 實際時刻是權威狀態，誤點由實際與排定算出 | 誤點只在 GamePresentation 由位置推導（決策 25） | `Train.times`（存檔）、`GameWorld.lateness(of:)`（秒） | 秒 | faithful |
| `Ci/` `app__q_c234188b7c397f91.js` `DWELL_GAME_SEC = 36` | 中間站停 36 秒 | `StationDwell.metroDwell`（360 十分之一秒，沒接上） | `ServiceDwell.minimum` = 36 | 十分之一秒 → 秒 | faithful |
| `Ci/` 同檔 `DWELL_TERMINAL_GAME_SEC = 42`，非環狀線的第一站與最後一站（`y===s[0]\|\|y===s[s.length-1]`）；來回 `2l + 2f × 36 + 2 × 42` | 端點停 42 秒 | `StationDwell.metroTerminalDwell`（420） | `ServiceDwell.terminalMinimum` = 42，時刻表的第一站、最後一站與折返的站 | 十分之一秒 → 秒 | faithful；折返的站也算端點（我們的線路在那裡折返，相當於 `Ci` 的路段終點） |
| `Ci/` 車門開 8 秒、關 8.3 秒 | 開關門的時間 | `StationDwell.metroDoorOpening`（80）、`metroDoorClosing`（83） | `ServiceDwell.doorOpening` = 8、`doorClosing` = 9 | 十分之一秒 → 秒，8.3 進位 | faithful（開）；機械（關：整秒步長，進位，不比參考短） |
| `Ci/` `PARAMS.BOARDING_RATE = 2`（有定義、沒被讀、沒有單位） | — | `StationDwell.referenceBoardingRate` | `ServiceDwell.passengersPerDoorPerSecond` = 2 | 每扇門每秒的人數 | 值 faithful；單位是 **gap**（gap 10 的決定） |
| 沒有參考 | 每節的門數 | — | `ServiceDwell.doorsPerCar` = 4 | — | **gap**：兩份網站都沒有門數，參考包只有 `doorCount` 的欄位名 |
| `Ci/` `updateTrainAtStation`（到站那一刻一次下車、上車） | 到站時上下車 | 離站時一次完成（過渡） | 到站 8 秒後車門開好時下車與上車（`exchangePassengers`），開著門時整分鐘釋出的人也上車（`boardPassengers`） | — | faithful（時機改回到站之後）；整分鐘的補上車是 gap（`Ci` 停站期間不再上車），因為我們的乘客在整分鐘釋出 |
| `Ci/` 客滿時留在月台的人 | — | 離站時把上不去的人記進 `refused` | 客滿的列車離站時，把還在等、可以搭它的人記進 `refused` | 次數 | faithful（決策 35 的次數）；計數的時刻是 gap |
| `Railway/site_archive_clean/data/*.json` 的每站停站、`TRTC_OFFICIAL_COAST_DWELL_SEC` 等 | 真實時刻表的停站 | `StationDwell` 的純函式（決策 35 第 9 點） | 不用 | — | 不移植（決定）：遊戲的停站照 `Ci/` 的遊戲規則；真實時刻表的停站留給之後匯入真實資料時 |
| 參考包「Transfer passengers re-enter station waiting demand」、`platformCongestionPenalty` | 轉乘、月台擁擠 | — | 沒有 | — | 延後：轉乘在 Phase 5；擁擠是 gap |

### Stage W2c：曲線接到行程與移動

2026-10-02 檢查三份參考（私有 repo `1563ad0`：`Ci/reference_snapshot/`、`Railway/site_archive_clean/`、`Railway/railway_game_reference_clean/`）。ARCHITECTURE 決策 40。W1 的曲線（`RunningCurve`，距離 1/64 m、時間毫秒、率千分之一 km/h/s）照舊；W2c 以整秒切段。

| 參考 | 行為 | 現有 GameCore | Swift（W2c） | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `Railway/` `index.html` `assignRunProfiles`（8367 行）：`runT = s[k1].arrSec − s[k0].depSec`，`buildProfile(runKm, runT, a, b, v, coast)`，再依序改用 `bAlt`、`aAlt` | 一段走班表給的時間 | 服務的列車照 rate 等速 | `GameWorld.leaving(_:stop:cycle:)` 算排定的時間（下一站在該輪的排定到達 − 這一站的排定出發），`run(of:length:scheduled:)` 以 `RunningCurve.init?(length:duration:performance:)` 建曲線，存成 `ServiceTimes.run`（`ServiceRun`） | 秒 → 毫秒 × 1000 | faithful |
| 同上：都建不出曲線時等速 | 沒有曲線時的退路 | — | 排定的時間建不出曲線（或不在 1 到 4,294,967 秒）時走最少的秒數；連最少的也沒有時沒有行駛，照 rate 移動 | 秒 | 部分 faithful：參考是等速走完班表的時間，我們是盡快跑（**gap**：參考的班表一定是真實的，排得太緊在參考裡不會發生） |
| `Railway/` `profTimeToProg`（8315 行）、`trainSeg`、`segProg`；`motion.js` `runOf`、`runBetween` | 依經過的時間取曲線上的位置 | 每秒走 rate 的份 | `ServiceRun.distance(on:from:to:)`、`GameWorld.travelShare(of:from:)`：每秒走曲線在這一秒結束與開始的距離差 | 毫秒 → 秒；距離無條件捨去 | faithful + 機械（整數步長） |
| `Railway/` `liveDelaySec`、21014 行 `sourceSec − delaySec − eventSec`；參考包「Actual departure updates delay for the next segment」 | 誤點的列車沿同一條曲線、整段往後移 | — | 行駛從實際出發的那一刻開始，長度與秒數照排定，所以晚出發就晚到同樣多；`lateness(of:)` 照 W2b | 秒 | faithful |
| `Ci/` `app__q_c234188b7c397f91.js` `METRO_TRAIN_ACCEL_MPS2 = 1.1`、`METRO_TRAIN_DECEL_MPS2 = 1.3`、`maxSpeedKmh: e.maxSpeedKmh \|\| 80` | 地鐵列車的加減速與路線的設計速度 | — | `TrainPerformance.metro` = 3960、4680、80 | m/s² × 3.6 × 1000 → 千分之一 km/h/s（精確） | faithful |
| `Ci/` 同檔：一段的時間是加速到路線速度、在下一站前煞停的最短時間 | 由性能推導行駛時間 | 線路一段 = ⌈距離 ÷ rate⌉ 分鐘 | `RunningCurve.leastSeconds(length:performance:)`：`buildProfile` 建得出曲線的最少整秒（二分搜尋）；`LineLeg.seconds`、`LineJourney.roundTripSeconds`，`roundTripMinutes` 無條件進位 | 秒 | faithful（gap 1 的決定）：梯形或三角形的最短時間，進位到整秒 |
| `Railway/` `PERF_*`、`resolvePerf`（依車名選） | 每台列車的性能 | W1 只有預設值 | `Train.performance`、`ServiceLine.performance`（預設 `standard`），`setTrainPerformance(_:to:)`、`setLinePerformance(_:to:)`（取代 `setLineRate`），`TrainPerformance.isValid`、`Codable` | 千分之一 km/h/s、km/h | 數值 faithful；選擇方式是 gap 4 的決定（見下面） |
| 參考包 `StopTiming.travelAllowance`、`CmdAutofillTimetable` | 時刻表的行駛時間由實際行駛時間填 | 線路的時刻表照 rate | 線路的時刻表照 `leastSeconds` 填（線路的性能） | 秒 | faithful（語義） |
| 沒有參考 | 被擋住的列車（rate 0、前方鐵軌被拆） | 等待，補回後續行 | 這一步結束時剩下的路比曲線剩下的長就丟掉行駛（`dropRunsHeldUp(endingAt:)`）；能動時從停止狀態以最少的秒數走剩下的路（`resumeRun(_:at:)`） | 秒 | **gap**：參考只依時間取樣，列車不會被擋住 |
| 沒有參考 | 很慢的一段整分鐘不動 | 閒置分鐘的捷徑 | `nextRunMove(from:)`：下一個讓列車往前的秒不被跳過 | 秒 | **gap**（GameCore 的機械） |
| `Railway/` `buildObsProfile`、`SPEED_ZONES`、`resolvePerf` 的車名規則 | 觀測曲線、限速區段、依車名選性能 | — | 不做 | — | 延後（gap 7；列車還沒有車名或車種） |

### Stage C1：任意角度的建造畫面

2026-10-02 唯讀檢查 `a91453/railway-reference-private`（`1563ad0`）的三份參考。只有 `Ci/reference_snapshot/` 有玩家的建造模式；`Railway/site_archive_clean/` 是真實路線的地圖，`Railway/railway_game_reference_clean/` 是 OpenTTD 的編譯檔，兩者都沒有可以移植的建造畫面。ARCHITECTURE 決策 41。下表的 `Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，文字是同目錄的 `ui-locales/zh-CN__q_8e57e7fa49d074d2.js`。GameCore 沒有修改，都在 GamePresentation 與 App。

| 參考 | 行為 | Swift（C1） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `G.editMode = "place"`、`executePlaceModeStationClick`、`placeStation`；`G.extendFromStart` | 點地圖放下一點，從線的任一端延伸 | `GameSession.tapNetwork(at:reach:)`、`networkStart`／`networkEnd`、`buildNetworkTrack()`（終點變成下一段的起點） | 畫面點 → 世界單位（`MapScale.worldPoint`） | faithful + 確認步驟：`Ci` 點了就建、可以復原（`pushMetroUndo`）；這裡沒有復原，所以先預覽再按「鋪設軌道」 |
| `Ci` 沒有吸附格線或角度 | 位置與角度自由 | 新節點就在點到的位置，四捨五入到整數單位 | 1/64 公尺 | faithful |
| `Ci` `catmullRom`（centripetal，指數 0.5）、`buildSplinePath`，第一點與最後一點重複 | 線通過各點，平順地延伸 | `NetworkBuilding.curve(from:leaving:to:leaving:)`：自由的一端控制點沿弦、在三分之一弦長（端點重複時的 Hermite 切線換成 Bézier）；接著既有軌道的一端沿那條軌道的方向，同樣三分之一弦長；兩端自由是直線 | 浮點 → 整數單位（四捨五入） | 部分 faithful：`Ci` 每加一點就重畫整條線，GameCore 的邊建好不變，所以已建的端點固定方向（C1 連續，相接由 GameCore 的 1/16 規則判斷） |
| `Ci` `_turnAngleDeg`、`MIN_TURN_ANGLE_DEG = 90`、`previewExtensionTurnInvalid`（`EXTENSION_TANGENT_LOOKBACK_M = 10`） | 在一點轉彎超過 90 度不能建 | `NetworkBuilding.turnsAtMostRightAngle(_:toward:)`（內積 ≥ 0）、`NetworkProblem.tooSharp` | — | faithful；切線直接用邊端的方向，不用往回 10 公尺的近似 |
| `Ci` `ANCHOR_MIN_SPACING_M = 22`、`metro.edit.node.too_close`「该位置与已有节点过近」 | 新節點離前一個節點不到 22 公尺時忽略 | `NetworkBuilding.minimumSpacing`（1408）、`NetworkProblem.tooClose` | 公尺 × 64 | faithful（值與訊息）；忽略改成顯示原因 |
| `Ci` `ANCHOR_PICK_RADIUS_M = 50`、`STATION_CLICK_SNAP_M = 20` | 點在既有節點、車站附近就選它 | `NetworkBuilding.touchRadius` = 24 點，`GameWorld.trackNode(near:within:)`、`trackEdgePoint(near:within:)` | 畫面點 | **改變**：`Ci` 的公尺數配合城市地圖；這張地圖畫得近十倍（一格 16 公尺、22–64 點），50 公尺會點到三格外，所以改以畫面距離計 |
| `Ci` `computePlacePreviewInvalid`、預覽線在不能建時是 `#666`；`updatePlaceDistanceHud` 顯示沿曲線的里程；`showMetroCostPreview` | 預覽變灰、顯示長度與費用 | `networkPreview`（在丟棄的世界副本上執行同樣的指令）、`NetworkPreview.text(in:)`、地圖的灰色虛線 | 單位 → 公尺 | faithful；費用是 GameCore 的 `ConstructionCosts.track` × 結構物倍數（`Ci` 的 `MetroEconomy` 不在快照裡） |
| `Ci` `metroBuildStationPlatformRingGcj`，`metroPlatformHalfLengthM = STATION_PLATFORM_HALF_LENGTH_M (100) × 節數 ÷ STATION_PLATFORM_BASE_CARS (6)` | 月台以站在線上的位置為中心，長度與節數成正比 | `networkPlatformStretch`：以點到的位置為中心、`節數 × Train.carLength`，移到不超出軌段；`addNetworkPlatform()` | 節 → 1024 單位 | 部分 faithful：中心與比例照搬；每節長度用 GameCore 的 16 公尺（決策 27），不是 `Ci` 的 33 公尺，讓同樣節數的列車剛好放得下 |
| `Ci` `findStationAtLatLng`（20 公尺內是既有車站） | 點在車站附近就用那一站 | `platformStationID` 預設是兩格內最近的車站，沒有就新建 | 格 | 部分 faithful：GameCore 的車站要放在一個方格上，新車站在月台中點下方的格子 |
| `Ci` `anchorActionDelete`、`deleteLine` | 刪除節點、整條線 | `removeNetworkEdge()`：拆軌段，再拆孤立的節點 | — | 部分 faithful：以軌段為單位；移動節點、在線上插站是 gap（要 GameCore 加切開的指令） |
| `Railway/site_archive_clean/rail-3d/integration/rail-structures.js` `VIADUCT_LIFT_M = 6` 等 | 依高度畫高架、橋墩、隧道口 | 不用；結構物由玩家選（`networkStructure`），高度每 2 公尺（`networkHeight`） | — | 不移植：繪製參數，留給 Phase 8 的 renderer |
| 參考包 `01_MIGRATION_MAP.md` §3、§10：建造指令分成 validate、estimateCost、execute | 先驗證、估價再執行 | 預覽在副本上執行 GameCore 的指令（驗證與估價），確認時在另一份副本上再執行一次 | — | faithful（語義） |
| `Ci` `MIN_STATION_DISTANCE_M = 400`、`MIN_CURVE_RADIUS_M`（`DEFAULT_BUILD_LIMIT_SETTINGS` 預設關閉） | 最小站距、最小半徑 | 不做 | — | 不移植：參考預設關閉 |
| 沒有參考 | 高度、結構物、豎曲線、把列車放到路網的月台 | `networkHeight`、`networkStructure`、`networkEasesGrade`、`place(_:atPlatformOf:)` | 公尺 × 64 | **gap**：`Ci` 的地鐵沒有高度；GameCore 的 S4、S5 規則已經有，畫面是自訂的 |

### Stage C3：性能的畫面

2026-10-02 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 42。GameCore 沒有修改。

| 參考 | 行為 | Swift（C3） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Railway/` `index.html` `PERF_RULES`（`/區間/`、`/自強/`、`/\(太/`、`/\(普/`、`/\(PP/`、`/\(3000\|110[KM]/`、`/\(D\d/`、`/普快車\|普通車/`、`/莒光\|復興/`、`/阿里山號…/`）、`PERF_BY_TYPE`、`PERF_HSR`、`PERF_DR1000`、`PERF_DEFAULT` | 依車名選性能 | `PerformancePreset`（以這些車名命名 GameCore 的預設）、`PerformanceMenu` | 千分之一 km/h/s（W1 已換算） | 數值 faithful；選擇方式改成玩家從選單選（遊戲的列車沒有車名，gap 4 的決定） |
| `Ci/` `game-dom__q_f4c03f23b8518a04.html` `#modal-line` 的 `line-speed-row-wrap`（`metro.line.design_speed`「设计时速」）；`app__q_c234188b7c397f91.js` `LINE_SPEED_MAIN_NON_SG = [80,100,120,160]`、`LINE_SPEED_ALL_NON_SG = [60,80,90,100,120,140,150,160,180,200]` | 建線時選設計時速 | `PerformancePreset.designSpeeds`、`TrainPerformance.withTopSpeed(_:)`；列車與線路都可以選 | km/h | faithful（選項）；`Ci/` 依城市換一組選項（`LINE_SPEED_HK` 等），這裡用非新加坡的全部選項 |
| `Ci/` `TRAIN_TYPES`（A 型 310 人／節、B 型 260、C 型 200 等）、`#modal-line` 的車型與編組 | 選車型決定容量 | 不做 | — | 延後：GameCore 的容量是固定的每節 352 人（決策 35） |
| `Ci/` `METRO_TRAIN_ACCEL_MPS2`、`METRO_TRAIN_DECEL_MPS2` | 地鐵列車的加減速 | `PerformancePreset.metro`（W2c 的 `TrainPerformance.metro`） | m/s² → 千分之一 km/h/s | faithful |
| 參考包 `BuildVehicleWindow`（只有符號） | 車輛的選購畫面 | 沒有可以移植的內容 | — | — |
| 沒有參考 | 線路各段與來回的時間、列車正在走的行駛 | `lineJourneyText(_:in:)`、`trainRunText(of:in:)` | 秒 | **gap**：顯示 W2c 的推導，讓實機上看得到 |

### Stage C2：營運與乘客的設定畫面

2026-10-02 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 43。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，畫面是同目錄的 `game-dom__q_f4c03f23b8518a04.html`，文字是 `ui-locales/zh-CN__q_8e57e7fa49d074d2.js`。GameCore 沒有修改，都在 GamePresentation 與 App。

| 參考 | 行為 | Swift（C2） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `#panel-station-flow-adjust`（「自定义客流」）、`applyStationFlowPreset`、`stationFlowKnownPresetKind`（office、residential、scenic、shopping） | 一鍵套用四種客流預設 | `StationPanel` 的四個按鈕、`GameSession.setSelectedStationDemandKind(_:)` → `setStationDemand` | — | faithful（曲線是 G1a 已移植的 `buildStationFlowPresetCurves`） |
| `Ci` `normalizeStationFlowPresetDailyVolume`、`metro.station.custom_ridership_help`「预设保持该车站默认的全天总量」 | 換預設時保留車站的全天總量 | 有客流時保留 `dailyTrips` | 人次 | faithful |
| `Ci` `stationFlowAuthorityBaseByHour`（伺服器的 `entryByHour`、`exitByHour`） | 車站的預設總量 | `StationDemand.defaultDailyTrips` = 10,000，`dailyTripSteps` 100 … 1,000,000 | 人次 | **gap**：總量來自伺服器資料，快照裡沒有；數值是自訂的 |
| `Ci` `copyStationFlowAdjustProfile`、`pasteStationFlowAdjustProfile`、`stationFlowProfileForTarget` | 複製客流設定，貼到另一站時依目標的總量正規化 | `copySelectedStationDemand()`、`pasteDemandToSelectedStation()`：目標保留自己的日客流 | — | faithful；目標沒有客流時用來源的日客流（**gap**：參考的每站都有總量） |
| `Ci` `applyStationFlowAdjustToAllServingLines`、`metro.notice.applied_to_lines`「已应用到 {lineCount} 条线路，共 {stationCount} 个物理站」、「当前车站没有可应用的线路」 | 套用到經過這一站的每條路線的每一站 | `applySelectedStationDemandToItsLines()`（在世界的副本上全部成功才生效） | — | faithful（訊息、計數含自己）；同上的 gap |
| `Ci` `resetStationFlowAdjustForCurrent`（曲線全部回到 1） | 恢復預設 | `removeSelectedStationDemand()`（`nil`） | — | **改變**：GameCore 沒有平的曲線，只能移除需求 |
| `Ci` `bindStationFlowAdjustDrag`、`applyStationFlowHubToggle`（機場、高鐵倍數） | 拖曳調整單一小時或全部時段；樞紐 | 不做 | — | 延後：需要 GameCore 的自訂曲線與樞紐規則 |
| `Ci` `drawStationFlowAdjustCanvas`、`stationFlowProfileArrayForUiMode`（「进站」畫 `out`、「出站」畫 `in`）、目前小時用 `selected` 色、`_stationFlowAdjShowTip` | 每小時的進站與出站長條圖，目前小時強調，指到的小時顯示數值 | `StationFlow`（加總 `hourlyDemand`）、`HourlyBarChart`、`summaryText`、`hourText`；點一下長條看那一小時 | 人次 | faithful（方向與強調）；高度是實際的人次，不是參考的視覺近似 |
| `Ci` `stationFlowAdjVisualBarHeight` 沒有基數時的預設形狀 | 還沒有資料時也畫出形狀 | `StationFlow.isShape`：`dayShape` × 預設曲線分配自己的日客流 | 人次 | 部分 faithful：形狀用 GameCore 的 `PEAK_FACTOR`，不是參考的正弦近似 |
| `Ci` 的 `station-icon-residential`、`-scenic`、`-shopping`（PNG）與辦公的 SVG | 預設的圖示 | SF Symbols `house.fill`、`building.2.fill`、`cart.fill`、`mountain.2.fill` | — | 部分 faithful：同樣的圖案；PNG 是 24–48 px 的黑色圖，不跟著深色模式與字級 |
| 參考包 `01_MIGRATION_MAP.md` §2（`timetable_start`、`CmdSetTimetableStart`、`CmdChangeTimetable`、`StopTiming.travelAllowance`、`minimumDwell`、`gui.timetable_arrival_departure`） | 時刻表的起點、每站的行駛與停留，以到達與出發顯示 | `TimetableEditing`（`movingArrival`、`movingDeparture`、`appending`）、`TimetableEditor` | 秒（每次 60 秒） | faithful（概念）；只有符號，畫面是自訂的 |
| 參考包 `CmdAutofillTimetable` | 依實際跑一趟填入行駛時間 | 新的停靠站預設 3 分鐘後到、停 1 分鐘 | 秒 | **gap**：App 還沒有自動填入 |
| 沒有參考（`Ci` 依線路派車，沒有每台列車的時刻表） | 重複週期 | `shortestPeriod(of:)`、`period(_:fitting:)` | 秒（整分鐘） | **gap**（Q1 的 `timetablePeriod`） |
| `Ci` `tutorial.transport.18`「使用＋添加停靠车站」、`metro.station.add_node_or_station` | 在線路加減停靠站 | `LineStopEditing`、`insertStopIntoSelectedLine`、`removeStopFromSelectedLine`、`moveStopOfSelectedLine` → `setLineStops` | — | faithful（語義）；上下移動是自訂的 |
| `Ci` `metroServiceSlotTimeRanges`、`metroResolveServiceSlotMain` | 提示各等級的時段，例如「07:00–10:00」換行「16:00–20:00」 | `ServiceDay.ranges(of:)`、`summaryText(in:)` | 分鐘 | faithful（逐分鐘掃描、合併、結束於 24:00） |
| 沒有參考（`Ci` 的時段寫死在程式裡） | 編輯服務日 | `ServiceDayEditing`（改等級、半小時移動、刪除、拆分最長的時段、標準服務日）→ `setServiceDay` | 分鐘（每次 30） | **gap** |
| `Railway/` `topology.js` `canTurn`（S1 已對照） | 道岔與平面交叉 | `TrackPieceKind`、`setTrackPieceKind`、`setTurnoutStem` → `buildTurnout`、`buildCrossing` | — | 已涵蓋（規則在 S1）；建造畫面是自訂的（`Ci` 沒有方格） |
| `Railway/` `index.html` `inferMeetPassTimes` 依賴的單雙線（S1 已對照） | 區段與單雙線 | `sectionTexts(at:in:)`、`trackSectionsSummary`、`lineTrackCountTexts`、`occupancyConflictTexts` | — | 唯讀顯示 S1 的推導；F3c-1 起也數路網（`networkSections()`、路網的 `parallelTracks`） |

### Stage F1：全面路網

2026-10-02 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 44。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`。`Railway/railway_game_reference_clean/` 的車站是 OpenTTD 以方格為單位的指令（只有符號），`Railway/site_archive_clean/` 是真實車站的經緯度，都沒有可以移植的擺設規則；作者 2026-10-02 決定車站自由擺設，所以照 `Ci` 的做法。

| 參考 | 行為 | Swift（F1） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `placeStation(e,t,r,n)`（`latlng: t`）、`placeStationInAddModeAtLatLng` | 車站放在任意一點，沒有方格 | `GameWorld.buildStation(named:at: PlanPoint)`、`Station.point`、`Station.location`（`tiles` 為空）；golden `buildStationAt` | 公尺 → 世界單位（1/64 公尺） | faithful |
| `Ci` `metroBuildStationPlatformRingGcj`（月台以車站在線上的位置為中心，C1 已對照） | 車站在線上，月台在它兩側 | 月台工具在月台中點建點車站（`addNetworkPlatform()`），取代 C1 的「中點下方的格子」 | 世界單位 | faithful（反過來由月台決定車站的點，因為 GameCore 的月台先於車站存在於邊上） |
| `Ci` `metroValidateCityBuildRegion`、`metroCanPlaceWithinQuota` | 只能建在城市範圍內、有配額 | 點必須在地圖上，否則 `outOfBounds`（點所在的格，向下取整）；收一座車站的費用 | 世界單位 | 部分 faithful：範圍是地圖；沒有配額（GameCore 以餘額限制） |
| `Ci` `metroHasCoincidentStation`（同一線 0.1 公尺內已有車站就不放） | 同一點不放兩座 | GameCore 不擋；月台工具在兩格內有車站時沿用它，所以不會在同一處建第二座 | — | **改變**：GameCore 的車站不屬於線路；兩座點車站可以在同一格（golden `free-station.json`） |
| `Ci` `STATION_CLICK_SNAP_M = 20`、`findStationAtLatLng`、`_findNearestDifferentLineStationWithin`（20 公尺內的他線車站成為轉乘） | 點在車站附近就用那一站 | `GameWorld.station(near:within:)`（依位置，同樣近時取 ID 小的）；`GameSession.tapMap(at:reach:)`（`NetworkBuilding.touchRadius` 24 點）；月台工具用兩格內最近的車站（點車站以點計） | 畫面點；格 | 部分 faithful：同 C1，距離以畫面點計；轉乘由 GameCore 的路線推導，不另外標記 |
| `Ci` `METRO_STATION_HIT_SIZE_PX = 22`、車站的 8 px 圓點 | 車站畫成圓點，點擊範圍 22 px | `TileArt.drawPointStation`（圓形徽章、列車符號、完整細節時的站名，選到時強調色外圈）；觸控範圍 24 點 | 畫面點 | 部分 faithful：圖樣是自己的 |
| `Ci` `MIN_STATION_DISTANCE_M = 400`（`DEFAULT_BUILD_LIMIT_SETTINGS.minStationDistance: false`） | 最小站距 | 不做 | — | 不移植：參考預設關閉 |
| `Ci` `ensureStationNameUnique`、`metroInstantStationSeedName` | 名字重複時換成預設名加編號 | `GameSession.suggestedStationName`（「車站 N」，跳過已用的）；GameCore 只拒絕空白的名字 | — | 部分 faithful：建議的名字不重複，玩家輸入的名字可以重複（與 C1 相同） |
| `Ci` 沒有格線 | 地圖不畫格線 | `TileArt.drawMap` 只畫地圖邊界；方格的軌道與車站（相容層）照舊畫在格上 | — | faithful |
| 參考包 `CmdBuildRailStation`、`CmdRemoveFromRailStation`（OpenTTD，以方格為單位，只有符號）；`01_MIGRATION_MAP.md` §3 `BuildStationCommand` | 方格車站；建造指令回傳結果 | 方格車站留作相容層（`buildStation(named:at: GridPosition)`、`extendStation`，F3 另議）；新指令一樣是 `GameWorld` 的指令，失敗不改變世界 | — | 不移植方格（作者決定）；指令的形式 faithful |
| `Railway/site_archive_clean/` 的 `stations/*`、`api/*.json` | 真實車站的經緯度 | 不用 | — | 延後：E2 實景模式把地圖中心對到經緯度（E2 ✅ 用 `data/tra.json` 的台鐵站點當開局的地點，[對照](#stage-e2實景地圖)） |
| 沒有參考 | 車站的規模 | `GameWorld.stationSummary(_:in:)`：路網上月台的數量與總長 | 世界單位 → 公尺 | **gap**：`Ci` 的車站沒有月台的數量；照 ROADMAP F1 以月台表示規模 |
| 沒有參考（`Ci` 沒有方格） | 方格的軌道、車站、拆除工具，方格道岔與單雙線資訊 | App 不再提供（`ConstructionTool.networkTools`）；GamePresentation 的相容層保留到 F3 | — | **改變**（作者決定） |

### Stage C4：存檔、開始畫面與示範地圖

2026-10-02 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 45。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，畫面是同目錄的 `game-dom__q_f4c03f23b8518a04.html`；參考包是 `Railway/railway_game_reference_clean/`。`Railway/site_archive_clean/` 只在 localStorage 存偏好設定，沒有遊戲存檔。

| 參考 | 行為 | Swift（C4） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `buildLocalSavePayload`：`{app: "城市设计师", version: 2, exportedAt, data: serializeGameState()}` | 存檔檔案：App 名稱、版本、時間、遊戲狀態 | `SaveLibrary` 的檔案 `{"app": "RailwayGame", "savedAt", "summary", "game": {"saveVersion", "world"}}` | ISO 8601 時間 | faithful（結構）；版本移到 GameCore 的 `SavedGame`，另加列清單用的 `summary` |
| 參考包 `01_MIGRATION_MAP.md`「P0/P1 infrastructure - save migration from the beginning」：`schemaVersion`，「Every schema change should have an explicit migration function and regression fixture」；`docs/savegame_format.md` 外層記版本 | 一開始就有版本，每次改格式都有遷移與回歸存檔 | `SavedGame.currentVersion` = 1、`init(from:)` 依版本讀取；`SaveFixtures/v1-demo-90-minutes.json` 與 `SavedGameTests` | — | faithful（規則）；格式是 JSON，不是 OpenTTD 的二進位 chunk |
| 參考包 `web_runtime/offline_persistence_file_io.md`：「load → detect schemaVersion → run vN → vN+1 → validate → commit」，不要在版本改變時清掉所有存檔 | 讀檔的步驟 | 檔頭檢查 App 與版本 → `SavedGame` 依版本讀取 → `GameWorld` 的不變量檢查 → 換成新的 `GameSession` | — | faithful |
| `Ci` `normalizeAndValidateSaveData`、`saveUi.crypto.invalid`、`saveUi.cloud.invalidFormat` | 讀檔前檢查與正規化，壞檔不載入 | `SaveError`：`notASave`、`newerVersion`、`damaged`、`fileSystem`，各有中英文訊息；清單上標出讀不進來的原因 | — | 部分 faithful：沒有正規化，壞檔一律拒絕（GameCore 的不變量） |
| `Ci` `screen-save-load-ui`：`metroSaveLoadEnterDirectClick`（直接進入）、`metroSaveLoadRestartFreshClick`（重新開始） | 開始時選擇繼續或重新開始 | `StartView` 的「繼續」「新遊戲」；`GameLauncher.continueGame()`、`startNewGame()` | — | faithful |
| `Ci` `archiveMetroAppCurrentDraftBeforeFreshStart` | 重新開始前先另存目前的草稿 | `SaveLibrary.archiveAutosave()`：另開一局之前把自動存檔改成玩家的存檔 | — | faithful |
| `Ci` 本機草稿（`LOCAL_DRAFT_NO_FLOW_SAVE_DEBOUNCE_MS` = 1800，建造後寫入）與雲端自動存檔（`AUTOSAVE_INTERVAL_MS` = 900 × 1000） | 自動存檔 | 離開前景、回到開始畫面、每 `GameLauncher.autosaveInterval`（900 秒）寫入 `autosave.json` | 毫秒 → 秒 | 部分 faithful：間隔照雲端自動存檔；不在每次建造後存（世界每一刻都在變，整個重寫太頻繁），改在離開前景時存 |
| `Ci` `saveUi.desktop.localSlots`、`gameMenuSave` | 本機存檔槽位、選單的「儲存」 | 玩家自己的存檔一個一個檔案、清單（讀取、刪除）；遊戲選單的「儲存遊戲」 | — | 部分 faithful：不限槽位數 |
| `Ci` `downloadLocalSave`、`importLocalSaveFromFile`（`saveUi.desktop.export`、`import`） | 匯出、匯入 JSON 存檔 | 遊戲選單的「匯出存檔」（`ShareLink`，`SaveLibrary.exportFile`）；開始畫面的「匯入存檔」（`fileImporter`，`GameLauncher.importSave`） | — | faithful |
| `Ci` `home.title`「城市设计师」、`home.language` | 首頁與介面語言 | `StartView` 的標題；「語言」打開 iOS 的「設定」 | — | **改變**：iOS 的每個 App 的語言在「設定」 |
| `Ci` 雲端存檔、加密（`metroEncryptSaveBlob`）、分享碼、`LOCAL_SAVE_MAX_IMPORT_BYTES` | 帳號、雲端與加密 | 不做 | — | 延後：沒有帳號與伺服器；iCloud 另議 |
| `Ci` 教學的示範（上海—南京）；舊的 `DemoLayout.swift`（方格） | 示範地圖 | `DemoWorld`：路網上的兩條線，中央一座兩個月台的點車站，全天營運、每站有客流；Release 也能從開始畫面開 | 格 → 世界單位 | **gap**：參考沒有可以移植的示範地圖（它的示範是真實路線），配置是自己的 |

### G1d：經濟平衡

2026-10-03 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 46。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`。`Railway/site_archive_clean/` 沒有經濟；`Railway/railway_game_reference_clean/` 只有 OpenTTD 的二進位與檔名（`binary_reference/relevant_source_paths.txt` 的 `src/economy.cpp`），沒有數值。參考的經濟引擎（`window.MetroEconomy`）不在快照裡。

| 參考 | 行為 | Swift（G1d） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `metroEconomySettleHourlyIfNeeded`：`Math.round(departures*75+trainKm*42+l*18)`、`Math.round(u*12+trainKm*9+c*8)` | 舊路徑的小時結算，用列車公里 | 不變（決策 36 已是列車公里，只改文件用字） | 64000 單位 = 1 km | faithful |
| `Ci` `metroEconomyFixedAssets`：依 `branchRootId` 分組，每組的車站集合相加 | 轉乘站每條線路各算一次 | `fixedAssets(memo:)`：每條線路的停靠站去掉重複，再相加 | — | faithful（更正） |
| `Ci` `metroFareDemandPenaltyForTrip`：`n>0\|\|(n=a)` | 0 以下的票價當成基準 | `demandFactor(fare:baseline:)`：0 以下是 1000‰ | — | faithful（更正） |
| `Ci` `metroFareDemandBaselineForCity`、`METRO_FARE_DEMAND_BASELINE_USD = 0.75` | 每個城市的基準票價 | `CompanyAccounts.fareBaseline`、`setFareBaseline(_:)`；App 的新遊戲 = $ 5 | 美元 → 美分 | 機制 faithful；值是 gap |
| `Ci` 編輯器 `flatFare ?? 5`、`lineInfoFareDefaultDistanceBands` | 預設的均一與距離票價 | `FareRules.standardFare`、`standardBands(for:)`（× 基準 ÷ 0.75，取到 0.05） | — | 機械換算 |
| `Ci` `stationFlowCustomEditingAllowed`、`syncStationFlowAdjustMode` | 只有自由模式能改客流，經營模式隱藏面板 | `GameSession.canEditStationDemand`；車站面板唯讀 | — | faithful（App 層） |
| `Ci` 經營模式的 `useGlobalODModel`（真實城市的客流） | 客流來自城市 | `StationDemand.cityDefault`（住宅區 10,000） | — | gap（Phase 5） |
| `Ci` `MetroSaveModePolicy`、`metroSaveModeError` | 自由模式的存檔只能在自由模式讀 | 經營 → 自由單向 | — | faithful（App 層） |
| `Ci` `metroQuotaPurchaseCatalogItems`（備用價目：10 km $ 100、5 站 $ 75、6 節 $ 60、快線 $ 350） | 配額的購買 | `ConstructionCosts.car`（每加一節收費）；不採用配額 | — | 部分 faithful：現金 |
| `Ci` `getTrainCap`：B 型 `ppc: 260`、6 節；`METRO_TRAIN_OPERATIONAL_LOAD_FACTOR = 1.1` | 新線的預設容量 | 不變：每節 320 × 1.1（決策 35） | — | 刻意保留，另外處理 |
| `Ci` `metroResolveStationWaitCap`：線路容量 × 8 | 車站候車上限 | 不變：4,000 | — | 刻意保留，另外處理 |
| 開局資金、建設價格、營運補貼（`operatingSubsidy`）、`serviceCost` | 在經濟引擎裡 | `GameWorld.startingBalance`、`ConstructionCosts.newGame` | — | gap：依回本天數訂 |

### Stage C5：最小教學

2026-10-03 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 47。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`（`TUTORIAL_STEPS` 在第 40 行，其餘函式在第 111 行），文字在 `Ci/reference_snapshot/lib/ui-locales/zh-CN__q_8e57e7fa49d074d2.js` 的 `tutorial.step.0`–`11`。`Railway/site_archive_clean/` 與 `Railway/railway_game_reference_clean/` 沒有教學：搜尋 `tutorial`、`onboarding` 沒有結果，`guide` 只出現在車站頁的「STATION GUIDE」介紹與文件用語。參考只有簡體中文；英文與繁體中文是這裡寫的。

| 參考 | 行為 | Swift（C5） | 分類 |
| --- | --- | --- | --- |
| `Ci` `TUTORIAL_STEPS[0]` 開始建線（`#nav-btn-add-line`、`#modal-line`） | 點「添加線路」，再依序點地圖放站 | `build.network`（選路網工具）、`build.track`（鋪設軌道） | 改寫成觸控：路網沒有「添加線路」 |
| `Ci` `TUTORIAL_STEPS[1]` 放置車站與節點 | 左鍵放站、右鍵加節點讓線路彎曲 | `build.firstStation`（月台模式放第一座車站）；彎曲是 `build.track` 的「終點變成下一段的起點」 | 改寫成觸控 |
| `Ci` `TUTORIAL_STEPS[4]` 確認建設線路：至少兩個站點 | 按 Enter 或雙擊結束建設 | `build.secondStation`（第二座車站）、`line.create`（建立路線） | 改寫成觸控 |
| `Ci` `TUTORIAL_STEPS[7]` 開始列車運營（`#panel-line-info`、`#line-info-capacity-row`） | 在線路資訊面板調高峰／平峰／低峰的上線列車數 | `line.service`（指派列車並設定上線列車數，框「路線」按鈕） | 改寫：這裡的列車要先購買、放置、指派 |
| `Ci` `TUTORIAL_STEPS[10]` 控制模擬（`#bottombar`） | 倍速、時間、人口 | `time.speed`（框 `hud.speed`，`.changeSpeed`） | faithful |
| `Ci` `TUTORIAL_STEPS[11]` 導覽結束 | 可以從選單重開 | `end`（框 `hud.menu`） | faithful |
| `Ci` `TUTORIAL_STEPS[2,3,5,6,8,9]`（快捷鍵：左鍵、右鍵、Shift、Ctrl+A、N） | 滑鼠與鍵盤快捷鍵 | — | 不移植：沒有觸控的對應 |
| `Ci` `tutorialStepText(e,t)`、`tutorial.step.<i>.title`／`.body` | 標題與說明，走翻譯鍵；內文有 HTML（`tutorial-shortcut-row`） | `TutorialStep.title(in:)`／`body(in:)`；純文字 | 機械換算 |
| `Ci` `startTutorial(force)`、`showTutorialStep(i)`、`dismissTutorial(skip)` | 開始、顯示某一步、結束 | 第 0 步的 `startTutorial()`、`showNextTutorialStep()`／`showPreviousTutorialStep()`、`skipTutorial()` | faithful（第 0 步） |
| `Ci` `_tutorialStepDoneAction`、`_tutorialOnAction`、`_tutorialStepActionDone` | 步驟要求的動作；快照裡 `_tutorialStepDoneAction` 從來沒被設定，只留下四個動作名稱 | `TutorialGoal`、`isTutorialStepDone`：由世界與 session 推導 | gap：參考沒有可移植的判斷，自己訂 |
| `Ci` `metrobuilder_tutorial_done`、`openUI`、`cardPosition` | 看過就不再自動開啟、步驟開面板、卡片位置 | — | 還沒有（決策 47 第 4 點） |
| 沒有對應 | — | `train.place`（購買並放置列車）、`station.ridership`（乘客） | gap：這個遊戲的列車要自己買，客流在車站面板 |

### Stage E1：大地圖

2026-10-03 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 48；繪製（只畫畫面內、分級、雙指縮放）是 CX-4（PR #69–#71），對照見 [UI_INTERFACES](UI_INTERFACES.md#6-參考對照)。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，虛構城市是 `lib/virtual_island_city__q_21ffa7f6ae58fc9e.js`，說明文字在 `lib/ui-locales/zh-CN__q_8e57e7fa49d074d2.js`（英文的 `en.js` 在清單上但沒有被抓下來）；`Railway/site_archive_clean/index.html`；參考包 `Railway/railway_game_reference_clean/` 只有 `web_runtime/touch_pinch_zoom.js` 與 `binary_reference/relevant_source_paths.txt` 的 `src/viewport.cpp` 檔名，沒有相機的數值。

| 參考 | 行為 | Swift（E1） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` 虛構海島城市：`E=[[-.1124,-.18],[.1124,.18]]`、圖例「25 × 40 km · 虚构海岛城市」 | 虛構城市的大小 | `GameWorld.newGameMapSize` = 1024 格（16,384 公尺） | 一格 16 公尺（1024 單位 × 1/64 公尺） | 部分 faithful：取 `GridMap` 的上限，比參考小 |
| `Railway` `TW_BOX`、`ROAM_PAD`、`setMaxBounds(state._panFence)` | 平移的範圍 | `PlanCamera` 的 `clampCenter`：停在地圖邊緣，放得下的方向置中 | — | faithful（第 0 步） |
| `Ci` `#custom-zoom-in`／`#custom-zoom-out`：`g.zoomIn()`／`g.zoomOut()`；`Railway` `NavigationControl({showZoom:true})` | 一個縮放等級 | `MapScale.zoomFactor` = 2：`zoomedIn()`／`zoomedOut()` | MapLibre 一級 = 比例 × 2 | faithful（取代第 0 步的每次 ± 8 點） |
| `Ci` `createAmapMapSafe` 的 `zooms:[2,20]`；虛構城市 `minZoom:9.1, maxZoom:18`；`Railway` `setMaxZoom(19/20)`、`applyTaiwanFloor`（開局再縮一級） | 縮放範圍 | 最大每格 `MapScale.largestSize`（64 點），最小到整張地圖放得下（`minimumSize(fitting:)`） | — | 機制 faithful；值沿用第 0 步 |
| `Ci` `fitAnycityImportedSaveNetworkView`：`fitBounds(所有車站, {padding:72, maxZoom:12})`，太小時各加 0.02° | 讀入存檔時對準路網 | `PlanCamera(map:viewport:showing:)`，`WorldRegion.built(in:)`（節點、車站、方格鐵軌）；不比 `automaticSize` 更近 | padding：點 | faithful；padding 照 `Railway`，`maxZoom` 對應 `automaticSize` |
| `Railway` `fitData(pts, …)`：`M.fitBounds(b, {padding:[30,30]})` | 開局對準車站 | `PlanCamera.focusPadding` = 30 點 | — | faithful |
| `Ci` 新城市：`initialCenterGcj` 或城市中心、`initialZoom` 或城市的縮放；`metroOsmCityOverviewZoom` | 沒有存檔時的開局 | 沒有東西時在地圖中央，`automaticSize`（手機每格 32 點） | — | 部分 faithful：沒有城市，中心是地圖中央 |
| `Ci` `persistLastAnycityEntryOptions`（localStorage `metro:anycity:last-entry:v1`）；`serializeGameState` 不存相機 | 相機不進存檔 | 相機是 view 的狀態，不存檔 | — | faithful；「上次的位置」還沒有 |
| `Ci` `guide.metro.shortcut.1`「缩放地图：滚动鼠标滚轮以放大或缩小地图。」、`guide.flight.shortcut.5`「移动地图：使用 W / A / S / D 平移地图。」；`TUTORIAL_STEPS` 沒有這一步 | 說明畫面的縮放與平移 | 教學的第三步 `map.move`（`TutorialGoal.moveMap`，框 `map` 與 `map.zoom`）；`GameSession.mapDidMove()` | — | gap：參考的教學沒有這一步，文字照說明畫面改成觸控 |
| `Ci` `serializeGameState`（地圖是真實的經緯度，沒有格子） | 存檔裡的地圖 | `SavedGame` 版本 2：`{"width","height","occupied":[{"x","y","tile"}]}`，版本 1 的 `tiles` 照舊讀 | — | gap：參考沒有格子地圖；格式是這裡的（量測見決策 48） |

### 環線

2026-10-03 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 49。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`；`Railway` 是 `Railway/site_archive_clean/index.html` 與 `rail-3d.js`；參考包 `Railway/railway_game_reference_clean/` 沒有環線。時間是秒（`DWELL_GAME_SEC` = 36 對應 `ServiceDwell.minimum`），班距與一圈在 GameCore 無條件進位到整分鐘（決策 22、40）。

| 參考 | 行為 | Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `completeRingLine`（三站以上，`e.isRing = true`）、`metroSplitOpenRing` | 把線路設成環線、打開成一般線路 | `GameWorld.setLineRing(_:to:)`、`ServiceLine.isRing`；`isRingStopList`（三站以上、第一站與最後一站不同） | — | faithful；打開時不改站序（參考從切開的地方重排） |
| `Ci` `normalizeRingPairedTrainCaps`、`metroRingPairedTrainCountAtOrBelow`（t − t mod 2） | 環線的列車數是偶數，無條件捨去 | `ServiceLine.paired(_:)`：`setLineRing`、`setLineTrainsInService` | — | faithful |
| `Ci` `metroRingDirectionTrainCounts`（內 ⌈t/2⌉、外 ⌊t/2⌋）、`metroRingDirectionalHeadways`（一圈 ÷ 該方向的列車數） | 兩個方向各一半、各自的班距 | `ServiceLine.ringService(_:_:at:lap:)`：每個方向 t/2（偶數），班距 ⌈一圈 ÷ 每個方向的列車數⌉、不短於目標 | 分鐘，進位 | faithful；班距進位到整分鐘照決策 22 |
| `Ci` `metroHeadwayRoundTripMinutes(…, isRing)`：各段 + 最後一站回第一站 + `n × DWELL_GAME_SEC`；`(isRing ? 2 : 1) × floor(…)` | 一圈的時間、最多列車數 | `GameWorld.driveLap(_:calling:from:)`：各段 + 每站 `dwellMinutes`；`lineMaximumTrains` = 2 × max(1, ⌊一圈 ÷ 2⌋) | 每站 60 秒（決策 22 的 1 分鐘，不是 36 秒） | faithful 結構；停站沿用決策 22 的整分鐘 |
| `Ci` `metroBuildRingServiceTimeline(e, t, dir)`：依方向 1／−1 排一圈的各段，每段行駛 + `DWELL_GAME_SEC` | 一圈的時刻 | `LineTrip.timetable(calling:sentOutAt:)` 的環線分支：派車後 36 秒離開，每站 + 1 分鐘，回到第一站結束；`ServiceLine.ringCalls(_:)` | 秒 | faithful；第一站 36 秒（`ServiceDwell.minimum`） |
| `Ci` 每個方向一組列車（`dir`） | 列車的方向 | `ServiceLine.ringDirection(of:)`：依 ID 輪流內環、外環 | — | 改寫：我們的列車屬於線路，不屬於方向 |
| `Ci` `applyRingTrainTimePhase`、`equalRedistributeRingServiceTrains` | 列車沿一圈的時間相位連續繞行、平均分布 | `DispatchStream`：每個方向從第一站依班距派車，各自記 `lastDispatch`／`outerLastDispatch` | — | **gap**：沿用決策 23 的派車模型 |
| `Ci` 環線的停站一律 `DWELL_GAME_SEC`（沒有 `DWELL_TERMINAL_GAME_SEC`） | 環線沒有端點 | `closingStart`：環線列車的第一站與最後一站最少停 36 秒，折返的站 42 秒 | 秒 | faithful |
| `Ci` `metroCollectRawTargetsForBoarding`：環線讀兩個方向的佇列 `[n, -n]` | 上車 | `boardingPlan`：環線不看方向，只看這一圈會不會到 | — | faithful；**刻意的差異**：不坐過第一站 |
| `Ci` `consolidateRingRouteLegs`（環線只有一條涵蓋全線的 route leg） | 環線沒有區間車 | `setLineRing`／`addLinePattern` 在有服務模式時拒絕（`invalidLinePattern`） | — | faithful |
| `Ci` `expressStops`、`calcLineHeadwayMinForRingExpress`、`getRingExpressRouteLeg` | 環線快車 | 沒有 | — | **gap** |
| `Railway` `buildLineSchedule`：`ln.loop` 時依序各站再回到第一站；`termName: null`；`rail-3d.js` 的「環線最後一站到第 0 站仍是一段真的軌道」 | 真實的環狀線 | 同上（一圈、沒有終點站） | — | faithful |
| `Railway` `runBetween`：環線走較短的方向 | 乘客的方向 | 沒有：乘客搭哪個方向都可以，只要這一圈會到 | — | **gap** |
| `Railway` `DWELL_SEC` = 25 | 停站 | 沒有採用：照 `Ci` 的 36 秒與決策 22 的 1 分鐘 | — | 不採用 |
| （參考沒有） | 示範地圖的環線 | `DemoWorld`：兩圈軌道（半徑 12、13 格）各一個方向，每站三個月台 | — | gap：這裡的配置 |

### Stage E2：實景地圖

2026-10-03 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 50。`Ci` 檔案是 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`（城市表 `CITIES` 用 Node 從原始碼取出比對）；`Railway` 是 `Railway/site_archive_clean/index.html`、`vendor/` 與 `data/tra.json`；參考包 `Railway/railway_game_reference_clean/` 沒有地圖。座標的倍率：千萬分之一度（1e-7°），兩份參考的小數（`Ci` 四位、`tra.json` 七位）都換得精確。

| 參考 | 行為 | Swift（E2） | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` `CITIES`（53 座：`name`、`center: [lat, lng]`、`zoom`、`pop`、`districts`） | 開局的城市 | `RealWorldPlace.ciCities`：依原本的順序，`center` 換成 `GeoAnchor`；名字改成台灣用語的繁體，加上英文 | 1e-7° | faithful（座標逐一比對）；`zoom` 不用（開局的相機照 E1），`pop`、`districts` 留給 Phase 5、6 |
| `Railway` `data/tra.json`（OpenStreetMap 的台鐵站點，`lines[].stations[]` 的 `name`、`lat`、`lon`） | 台灣的真實車站 | `RealWorldPlace.taiwan`：基隆、臺北、桃園、新竹、臺中、嘉義、臺南、高雄、宜蘭、花蓮、臺東，每個站名第一次出現的點 | 1e-7° | faithful（座標逐一比對）；挑哪幾站是這裡的 |
| `Ci` `startGameAnyCity(cityKey, {lng, lat})`、`fetchAnycityManifest`、`registerAnycityFromManifest`（`center` 或 `bbox` 的中心） | 任意地點開局 | `RealWorldPicker`：清單或搜尋把地圖移過去，玩家拖到想要的中心，「在這裡建造」→ `GameLauncher.startNewGame(at:)` | — | 部分 faithful：選點的 `anycity-ui.js`、`anycity-bbox-map.js` 不在快照裡（gap）；搜尋用 Apple 的 `MKLocalSearch`；只存中心 |
| `Ci` `anycity-virtual-island`（`lng: 0, lat: 0`，creative） | 不在真實地點的城市 | 空白地圖：`GameWorld.geoAnchor == nil`，開始畫面的「新遊戲」 | — | 對應：空白地圖不放在地球上 |
| `Ci` `promptMetroGameModeChoice`（進城市前選 creative／management） | 進入前選模式 | 開始畫面分成「新遊戲」（空白）與「實景地圖」；經營模式照 G1d，兩種地圖相同 | — | 改寫：這裡的模式是地圖，不是經濟 |
| `Ci` `getMapEnginePolicy`（中國 IP 加中國大陸城市只用高德，其他只用 `osm`）、`setPreferredMapEngineFromMenu`、失敗時自動換另一套 | 地圖引擎 | MapKit（Apple 地圖；Attachment 6 說它在中國由高德提供） | — | **改變**（作者決定先用 MapKit）；E3 視需要照參考加 MapLibre |
| `Ci` `initOsmMapEngine` 加 OpenFreeMap 的 `positron`／`liberty`／`dark`／`fiord`／`satellite`；`Railway` `vendor/maplibre-gl.js`（v5.9.0）、`vendor/ofm-positron.json`、CARTO 點陣備援、Esri World Imagery（`needsToken: 'esri'`） | 底圖與樣式 | `AppleMapStyle`：地圖（`MKStandardMapConfiguration`，`.muted`）、衛星（含標示）、衛星，都是平面；App 的設定 | — | 部分 faithful：淺色街道圖對應預設的 `positron`，衛星對應 `satellite`；沒有 `dark`、`fiord` |
| `Ci` 車站的 `latlng`（遊戲座標就是經緯度） | 世界與地球 | 世界照舊是整數的世界座標；只有地圖中心釘在 `GeoAnchor`（`RealWorldFrame`：x 東、y 南，地圖中心在錨點） | 1/64 公尺 | **改變**：GameCore 不用經緯度（決定性、既有的 golden 與存檔） |
| `Ci` `gameGcjToOsmWgs`、`initialCenterGcj`（中國大陸的遊戲座標是 GCJ-02，給 MapLibre 時換成 WGS-84） | 座標系統 | 沒有換算：錨點是 MapKit 給的座標，鐵路與地圖都經過 MapKit 換算（`MKMapPoint`、`MKMapPointsPerMeterAtLatitude`） | — | **gap**：換到 MapLibre（E3）時中國大陸的存檔可能偏約 500 公尺 |
| `Ci`／`Railway` 由 MapLibre 的相機處理平移、縮放與旋轉 | 地圖的相機 | 遊戲的 `PlanCamera` 決定看哪裡，`FollowingMapView` 用 `setVisibleMapRect` 跟著；平面、北朝上 | MapKit 的 map point | **改變**：相機在遊戲這邊（理由見決策 50 第 5 點）；旋轉與傾斜留給之後 |
| `Ci` entry-save-map 的「OpenFreeMap © OpenMapTiles © OpenStreetMap」 | 地圖的標示 | Apple 的標誌與「法律聲明」在地圖 view 底部 30 點的帶子裡，遊戲的畫面不蓋它、連結可以點（Attachment 6 §2.1） | 點 | faithful（保留地圖的標示） |
| `Railway` `offline-land`（沒有網路時的純色底圖） | 離線 | MapKit 畫它自己的空白格，路網照畫 | — | 部分 faithful：沒有另外的提示 |
| `Ci` `serializeGameState` 存 `cityKey`；`persistLastAnycityEntryOptions` | 存檔裡的地點 | `GameWorld.geoAnchor`（`{"latitude","longitude"}`），存檔版本 4；Apple 搜尋的名字、地址與識別碼不存（Attachment 6 §2.5） | 1e-7° | 部分 faithful：存點，不存城市名 |
| `Ci` `metroFareDemandBaselineForCity`（依城市的票價基準） | 城市決定票價基準 | 沒有：實景與空白的新遊戲都是標準票價（G1d） | — | **gap**：錨點不記城市 |
| `Railway` `TW_BOX`（整個台灣的平移範圍） | 地圖的範圍 | 新遊戲的 16 公里地圖（E1） | — | 不採用（E1 已決定） |

### Stage F3：移除方格

2026-10-03 唯讀檢查三份參考（`1563ad0`）。ARCHITECTURE 決策 51；盤點見 [F3_GRID_INVENTORY](research/F3_GRID_INVENTORY.md)。F3 不移植新的行為，只拿掉方格的相容層；這張表記下三份參考對「方格還是 graph」的做法，以及 F3 之後對應的 GameCore。

| 參考 | 行為 | F3 之後的 GameCore | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Ci` 車站的 `latlng` 與線路的折線（`placeStation`、`metroBuildStationPlatformRingGcj`） | 鐵路是地圖上的點與線，沒有格 | 路網的節點與邊（`TrackNodeID.node`、`TrackEdgeID.edge`）、點車站（`buildStation(named:at: PlanPoint)`）、邊上的月台 | 世界單位（1/64 公尺） | faithful（決策 28、29、44 已經是這樣；F3 拿掉另一種） |
| `Railway/site_archive_clean/` `data/tra.json` 等：沿線形的累積距離（`d`）與經緯度內插 | 列車位置是沿線的距離 | 列車位置 `onEdge(行進方向, offset)`：哪條邊、哪個方向、沿邊多遠 | 世界單位 | faithful（S3 起） |
| 參考包 `Railway/railway_game_reference_clean/`（OpenTTD／RailwayCore 15.3）：tile 上的 track piece、`trackdir`、`src/pathfinder/yapf/*` | 方格的軌道與尋路 | 不移植方格；選路、號誌與進路的規則之後照決策 28 轉成節點、邊與行進方向（U-min、V） | — | **不移植**（F1、F3 作者決定）；`01_MIGRATION_MAP.md` 要求移植行為與演算法結構，不是原實作 |
| （參考沒有） | 一格 1024 單位、地圖的大小與邊界 | 保留：`GridMap`、`GridPosition`、`TrainPosition.linkLength`、`WorldCoordinate.tileSize` | — | 保留（決策 51；改名另議） |

**F3c 要補的缺口，參考裡已有的做法**（2026-10-03 為 F3a-3 列出的缺口再查三份參考；F3c 照這些移植，不自己另訂規則）：

| 參考 | 行為 | F3c 預計的 GameCore | 倍率 | 分類 |
| --- | --- | --- | --- | --- |
| `Railway/site_archive_clean/data/tra_track_sections.json` 的 `source_notes` 與欄位（`tracks`、`parallelFrac`、`lengthM`）；讀表端 `index.html` 的 `traSectionKey`、`single(a,b)` | 相鄰兩站之間，有平行正線股道的長度佔比 ≥ 0.5 算雙線（`tracks=2`），否則單線 | F3c-1：`parallelTracks(between:and:)`、`lineTrackCounts(_:)` 也數路網，沿用 S1 的定義（不共用軌道的路徑數；路網上一段軌道是一條邊，在兩站的月台處切開） | 世界單位 | **沒有移植 ≥ 0.5 的規則**：產生器 `scripts/build_tra_track_sections.mjs` 不在 repo，「平行」的定義是缺口；它是真實路線的資料分類，參考唯一的使用者是交會推估（`index.html` 第 8460 行 `single(a,b)`），留到 V 和交會一起移植。路網的單雙線不是自訂新規則，而是 S1 已有的定義延伸到路網 |
| `Railway/site_archive_clean/rail-3d/physical/topology.js` 第 41–42 行 | 同一對節點之間重複的 way 共用一個佔用資源，不算第二股 | 不需要：GameCore 每條邊各自是一股、各有自己的 span（決策 29、S3A） | — | 不同（GameCore 的邊是玩家蓋的軌道，不是重複的 OSM 資料） |
| `topology.js` 的 `trackGroups`（第 47–57 行） | 從不是道岔、相鄰節點不超過兩個的節點出發填滿，得到兩個分歧點之間的一段軌道 | F3c-1：`networkSections()`（`NetworkSection`）：在分歧點（不是正好兩條相接的邊的節點：道岔、交叉、盡頭、兩條不相接的邊）切開的邊鏈，沒有分歧點的環另列 | 世界單位 | **已移植**。參考的一組是分歧點之間的普通節點；我們的區段另外列出邊、行進方向與兩端的分歧點。改寫的地方：參考數相鄰節點、看 `switch` 標記，我們數邊端並用相接規則（GameCore 沒有標記；同一對節點之間的兩條邊是兩股）；盡頭在參考裡屬於一組，在我們這裡是區段的端點（和方格的 `trackSections()` 一樣）；沒有邊的節點都不屬於任何一組 |
| `topology.js` 的 `canTurn`（第 77–101 行）與 `stableVector` | OSM 節點上能不能轉線：同一條 way、只有兩個鄰點、`switch`、交叉只接最直的一支、未標記的三叉點用 cos 門檻推斷 | 不改：GameCore 的邊是遊戲自己建的幾何，節點上兩端反向 1/16 以內才相接（決策 29），已經涵蓋道岔、菱形交叉與 slip | — | 不同（參考的門檻是為了從 OSM 資料推斷道岔；F3 不改相接規則） |
| `topology.js` 的 `shortestPath`（第 102–131 行） | Dijkstra，以「節點＋進入的邊」為狀態，每一步檢查 `canTurn`；路徑中重複的節點一律不要 | 不改：GameCore 同樣以進入的邊為狀態、不立即折返，但允許經過同一個節點兩次（折返線，`network-route.json`），同長依邊的編號遞增 | — | 不同，記給作者決定（F3 不改選路規則） |

### 折返

| 參考 | 行為 | 現有 GameCore | 預計 Swift | 倍率 | 分類 |
| --- | --- | --- | --- | --- | --- |
| `turnbacks.js` `isScheduledTurnback`、`AFR_TURNBACKS` | 之字形折返：前一段的終點是下一段的起點，而且同股反向（倒數第二個節點 = 下一段的第二個節點）；只限林鐵的四處 | `ScheduledStop.reverses`：只在停靠站、出發時折返（Q1）；S5 的 `reversedOnNetwork` | 之後：不停車的折返點 | — | 判定可以 faithful；**gap**：我們的折返只在停靠站，名單是真實地名 |
| `timing.js` `turnbackProgress` | 班表沒有列出停車秒數的折返點：在站間的時窗內漸停再起步，不捏造停留。視窗 w = min(0.15, 20 ÷ 段時間)，曲線 2u² − u³ 與 u + u² − u³ | 沒有 | W2 之後 | 秒 | faithful 候選 |
| `motion.js` `reversals` 與 `formationFacing`；`afr-operation.js` `afrInitialFacing` | 依折返次數的奇偶翻轉車頭方向；機車固定在一端，推或拉隨方向改變 | 反向時車頭移到車尾（S2、S3） | 不需要 | — | **呈現**（車輛模型的朝向）；車站序列是真實資料 |
| `dispatch.json` `handoffs`（`basis: "matching-timetable-turnaround"`） | 同一組車在終點折返，接下一班 | Q1 的重複、Q2b 的來回派車 | 不需要 | — | 已涵蓋 |
| `metro-motion.js` `routeFor`：停車點夾在 [半個編組長 + 2 m, 路徑長 − 半個編組長 − 2 m] | 車身不超出車止 | S5 的停車位置：車頭停在行進方向上月台的末端，只停放得下整列的月台 | 不需要 | — | 已涵蓋（規則不同，S5 在前） |

## RailwayCore 參考包

### 來源與性質

- 私有 repo 的 `Railway/railway_game_reference_clean/`，commit `1563ad0`（2026-10-01 讀取）。
- 逐檔讀過：`00_READ_ME_FIRST.md`、`01_MIGRATION_MAP.md`、`02_W2_IMPLEMENTATION_CONTRACT.md`、`MANIFEST.txt`、`binary_reference/` 的三份清單、`docs/linkgraph.md`、`web_runtime/` 的兩個檔案。`docs/` 其餘四份（`desync.md`、`debugging_desyncs.md`、`savegame_format.md`、`logging_and_performance_metrics.md`）讀了章節結構。
- `binary_reference/railway_core_15_3.wasm` 是編譯好的 OpenTTD 15.3，改名為 RailwayCore（字串裡有 `OpenTTD`、`Squirrel 2.2.5 stable - With custom OpenTTD modifications`）。`docs/` 是改名後的 OpenTTD 開發文件。
- 包裡**沒有原始碼**，只有符號名稱、原始碼路徑與設定名稱，用來定位行為。
- `01_MIGRATION_MAP.md` 與 `02_W2_IMPLEMENTATION_CONTRACT.md` 是為這個專案寫的移植清單與 W2 驗收規格。裡面的公式與資料結構是建議，不是從原始碼抽出來的。

### 授權

- 包裡沒有附授權檔；OpenTTD 本身是 GPL-2.0。
- 包自己的規則是「移植行為、狀態機、資料模型、測試與演算法結構，用獨立的實作，不複製原始碼」。這個 repo 是公開的、App 要上 App Store，所以照這條做：不把 OpenTTD 的原始碼或 wasm 放進 repo 或 App，符號與設定名稱只用來找行為。

### 對照表

| 參考包的項目 | 現有 GameCore | 預計 | 分類 |
| --- | --- | --- | --- |
| P0-1 到站 → 開門 → 下車 → 上車 → 停留 → 關門 → 發車的狀態機（`LoadUnloadVehicle`、`load_unload_ticks`、`order.gradual_loading`） | W2b ✅（決策 39）：`ServiceTimes` 與每秒的停站，見 [Stage W2b](#stage-w2b停站上下車與誤點) | — | faithful；停站依乘客人數延長（gap 10 的決定） |
| P0-2 時刻表與誤點（`lateness_counter`、`timetable_start`、`CmdChangeTimetable`、`TicksPerTimetableUnit`） | W2b ✅（決策 39）：實際的到達與出發時刻是存檔的權威狀態，`lateness(of:)` 是 GameCore 的查詢；早到的列車等到排定出發，誤點的列車停完最短停站就走 | — | faithful（語義）；`TicksPerTimetableUnit` 不採用（gap 2） |
| P0-3 以指令修改世界（`Cmd...`：驗證、成本、執行） | 已有：`GameWorld` 的指令、原子性、typed error（決策 4、5） | 預估成本與預覽可以在世界的 value 複本上試跑；需要時再加查詢 | 大部分已涵蓋 |
| P0-4 固定的模擬 tick，與畫面分離 | 已有（決策 3、12） | — | 已涵蓋 |
| P1-5 乘客群組（`CargoPacket`） | 已有：依起訖、線路、方向分組（G1a，決策 34） | 轉乘：Phase 5 | 已涵蓋；轉乘還沒有 |
| P1-6 Link graph 的乘客路徑 | 沒有（G1 不做路徑選擇） | Phase 5 | **gap**：`docs/linkgraph.md` 只講執行緒與重算間隔，沒有演算法 |
| P1-7 路徑成本（`pf.yapf.rail_*_penalty`：彎道、坡度、車站、月台長短、折返等） | `TrainRoute.shortest` 只看長度 | V 或之後，和 `Railway/` `topology.js` 的 `shortestPath` 加權一起做 | 項目可以參考；**gap**：包裡沒有數值 |
| P2-8 公司與經濟分離 | 已有：`GameEconomy`、帳本（G1c，決策 36） | — | 已涵蓋 |
| P2-9 城市成長、產業 | 沒有 | Phase 6 | **gap**：只有原始碼路徑 |
| P2-10 建設規則與成本在指令裡 | 已有：建設指令先驗證再扣款 | — | 已涵蓋 |
| 存檔版本與 migration（`docs/savegame_format.md`） | 沒有（決策 6）；App 目前不把存檔寫到裝置 | 正式存檔時（ROADMAP 的跨階段議題） | 延後 |
| 決定性除錯：種子、指令紀錄、checksum、重播（`docs/desync.md` §2.1 快取檢查、§2.2 紀錄、§3.1 重播、§3.2 比對 checksum 並從較晚的存檔重來，找出分歧的區間） | golden scenario 就是指令序列的重播；property campaign 比對 digest；F3b 起加上 [`ReplayFixtures/`](../ReplayFixtures/README.md)：路網 campaign 的指令紀錄、每 10 個指令一個狀態 checksum，`ReplayFixtureTests` 逐段重播比對，對不上就指出是哪一段指令；每個世界都檢查不變量（對應 §2.1 的快取檢查）；checksum 算的是遊戲狀態的描述，不是存檔的位元組 | 已移植（獨立實作，沒有原始碼） | 已涵蓋 |
| `web_runtime/`：雙指縮放、IndexedDB 存檔、存檔的匯入匯出 | 原生 App 不適用 | Web 宿主（[WEB_PORT_READINESS](WEB_PORT_READINESS.md)） | 只適用 Web |

### 和另外兩份參考的差異

- **停站**：`Ci/`、`Railway/` 的停站是固定的秒數，沒有一條規則依乘客人數或車門數改變停站；`Ci/` 的 `PARAMS.BOARDING_RATE` 有定義但沒有被讀（`StationDwell.referenceBoardingRate`）。參考包建議依人數與每扇門的速率計算，OpenTTD 的 gradual loading 也是依量逐 tick 裝卸。見 gap 10。
- **時間**：
  - `Ci/` 的時鐘是隨畫格前進的小數分鐘，1× 是真實時間（`GAME_SECONDS_PER_REAL_SECOND = 1`）；
  - `Railway/` 依時間取樣，以秒計；
  - OpenTTD 以 tick 計，時刻表的單位可以選（`TicksPerTimetableUnit`）；
  - 我們的基本步長原本是一遊戲分鐘，1× 每 100 ms 一步，是真實時間的 600 倍（決策 3、12）；Stage W2a 起是一秒，`x1` 是真實時間（決策 37）。

  見 gap 2、9。

## Gap 分析

需要作者決定或補資料的事，依影響大小排列。2026-10-01 作者決定 W2 先於 U-min，其餘採用建議的方案；已決定的寫在各項的「決定」。

1. **W 的時間從哪裡來？** 參考的 `buildProfile` 是「給定班表的時間 T，找出能準點的曲線」；ROADMAP 的 W 是「由性能推導時間，取代固定的 rate」。建議：
   - W1 只翻譯曲線，不改變任何行為；
   - W2 把線路一段的時間定為 `buildProfile` 建得出曲線的最短整秒。
   - 這是把參考的函式當成判斷條件使用，不是新公式；但「由性能決定時刻表」本身是參考沒有的行為，要作者同意。
   - **決定（2026-10-01）**：照上面的建議，一段的時間是建得出曲線的最短整秒（gap 2 改用秒之後）。時刻表以秒儲存，畫面顯示到分鐘，需要時顯示秒。
   - **W2c 的實作**（決策 40）：線路以自己的性能規劃一段的最少整秒（`RunningCurve.leastSeconds(length:performance:)`）；服務的列車照參考的 `assignRunProfiles` 走班表給的時間，排得太緊時走最少的秒數。見上面的 [Stage W2c 對照](#stage-w2c曲線接到行程與移動)。
2. **時間的解析度。** 參考以秒計：安全間隔 30 秒、等待最多 184 秒、跑段曲線以秒解。GameCore 的基本步長是一分鐘（決策 3）。
   - 交會與待避若照參考以秒判斷，時刻表、閘門與存檔就要有秒。
   - 或者把秒無條件進位成分鐘，但這會改變參考的結果。
   - 這是架構層級的決定。
   - **決定（2026-10-01）**：基本步長改成一秒（W2a）。不改成與遊戲時間脫鉤的 tick：真實時刻表、W1 的曲線與 `Ci/` 的每小時需求，都假設列車的時間就是時鐘的時間。
   - 為什麼不維持分鐘：地圖是真實比例（一格 16 公尺；手機預設一格 32 pt，也就是每公尺 2 pt）。100 km/h 的列車在 1 倍真實時間下每秒移動約 56 pt，10 倍約 560 pt（比一個手機畫面寬），60 倍以上就看不清楚。要看得到列車，1× 必須接近真實時間（gap 9）。在這種速度下，一分鐘的步長代表每 6 到 60 真實秒才前進一次，玩家的指令最多要等一分鐘才生效。
     - 先前（同一天稍早）的建議是「維持分鐘、列車在一步之內帶毫秒的餘數」，只在 1× 很快時成立，所以撤回。
   - 秒也解決 [TIMETABLE_DATA_STUDY](TIMETABLE_DATA_STUDY.md) 記錄的換算問題（站間不到一分鐘、行駛時間被壓縮）；V 的 30 秒安全間隔與以秒計的等待也能照參考表達。
   - 範圍（2026-10 量測）：`ServiceLine`、`GameWorld`、`LineJourney` 等約 15 個檔案的時間邏輯、23 個 golden fixture、測試裡約 560 處 `advance`。不只是乘以 60：每分鐘的整數 rate 換成每秒多半不是整數，乘客釋出的進位也可能改變。W2a 的做法：
     - 只換時間單位，不加新玩法；
     - 乘客釋出與經營結算仍然每分鐘做一次，這兩部分的行為不變，也省下大部分的計算；
     - 列車的 rate 仍以每分鐘的單位數表示，每秒走「rate × 累計秒數 ÷ 60」的整數部分與上一秒的差，沒有事件發生的整分鐘，位置與現在相同；
     - golden 的 schema 加上時間單位，舊 fixture 讀入時換算；真的改變的值在 W2a 的 PR 逐一說明（結果：schema 23，既有 22 個 fixture 只改版本號，沒有預期值改變）；
     - 同樣的遊戲時間要跑 60 倍的步數；最快的檔位維持現在的 600 倍時，每真實秒 600 步。
3. **整列車預約的演算法不在快照。** V 的「衝突時排定等待」只有結果（`holds`）與更新紀錄的文字；T 已經依自己的設計實作。建議作者把建置腳本加進私有 repo（`motion.js` 註解提到的 `scripts/lib/track_section_via.mjs`、`track_directions.mjs`，以及產生 `dispatch.json` 的腳本）。有了它們，V 就能翻譯而不是設計，也能回頭對照 T 的規則。2026-10-01 重新確認：RailwayCore 參考包也沒有這些腳本。
4. **車種性能怎麼選。** `PERF_RULES` 依真實車名（自強、區間、PP、DR1000 等）比對。遊戲的列車沒有車名或車種。W1 先把數值表照抄成具名的預設，列車帶哪一組要作者決定。
   - **決定（2026-10-02）**：每台列車與每條線路都有自己的性能，預設 `standard`，以指令更換（`setTrainPerformance`、`setLinePerformance`）；畫面的選擇之後與車種一起做。
   - **W2c 的實作**（決策 40）：另加 `Ci/` 的地鐵列車（`metro`：1.1、1.3 m/s²，80 km/h）。列車的性能只在不是標準時存檔。
5. **跟車規則的角色。** `updateBlockHolds` 是畫面層、隨畫格改變的顯示延後。U 若要採用它的距離（0.4 km、兩車長度的平均），要以基本步長重新表達；若 U 只用預約的資源，這組常數就只給畫面用。
6. **沒有號誌與閉塞。** 兩個網站都沒有號誌機、固定閉塞或聯鎖。U 的授權終點（到下一站、或到下一個可以停車的地方）是 gap，照 ARCHITECTURE 決策 29 第 12 點與 PR #31 的語義處理，並在 PR 裡列出。
7. **限速區段與觀測曲線。** 參考的限速區段綁定真實地名，觀測曲線要用實測資料；兩者都可以移植，W1 還沒做。虛擬地圖上的曲率限速參考沒有，要由我們的幾何推導，這是 gap。
8. **通過站。** 參考的通過站有推導出的通過時刻，我們的 Q3 快車通過站沒有時刻。V 的交會推估需要它。
9. **1× 的時間比例。** W2a 之前 1× 每 100 ms 走一遊戲分鐘，是真實時間的 600 倍（決策 12）。W2 接上真實的車速之後，100 km/h 的列車在 1× 下每一真實秒跑過約 1,000 格（一格 16 公尺），畫面上等於瞬間移動。`Ci/` 的 1× 是真實時間。
   - **決定（2026-10-01）**：1× 接近真實時間（照 `Ci/` 的 `GAME_SECONDS_PER_REAL_SECOND = 1`），另外提供加速的檔位，最快維持現在的 600 倍，經營時不必等。
   - **W2a 的實作**：1×、10×、60×（對上 `Railway/` 倍速滑桿的 1、10、60 刻度），保留 600 倍（`normal`）與 1200 倍（`double`）；見上面的 [Stage W2a 對照](#stage-w2a時間改用秒)與 ARCHITECTURE 決策 37。
   - 檔位與 tick 間隔（宿主仍每 100 ms 一個 tick）已在 W2a 定，擴充了 `GameSpeed`；決策 3 的「結果與速度無關」仍然成立。之後在實機（TestFlight）上調整。
10. **停站依不依乘客人數。** `Ci/`、`Railway/` 的停站是固定的秒數（`StationDwell`）。參考包建議 `max(下車人數 ÷ 下車速率, 上車人數 ÷ 上車速率)` 加上開關門的時間，OpenTTD 的 gradual loading 也是依量裝卸。兩邊不一致，要作者決定。
    - **決定（2026-10-01）**：以 `StationDwell` 為最短停站（參考包也要求沒有乘客時仍有最短停站），上下車的人多時才延長，延長的部分照參考包的 `max(下車人數 ÷ 速率, 上車人數 ÷ 速率)`。
    - 速率與門數是 gap，在 W2b 定：起點是 `Ci/` 有定義但沒被讀的 `PARAMS.BOARDING_RATE = 2`，它沒有單位，要由我們補上。
    - **W2b 的實作**（決策 39）：每扇門每秒 2 人、每節 4 扇門，上下車同時進行，時間是較多的一邊，進位到整秒；最短停站 36／42 秒包含開門 8 秒、關門 9 秒。見上面的 [Stage W2b 對照](#stage-w2b停站上下車與誤點)。

## 建議的實作順序

相依關係（箭頭是「需要」）：

```
T 進路預約 ✅（PR #40）
W1 行駛曲線核心 ✅ ── 不依賴其他 Stage；參考最完整
W2a 時間改用秒 ── 不依賴其他 Stage（gap 2、9 的決定）
W2b 停站、上下車與誤點 → W2a、G1b 的 StationDwell（gap 10）
W2c 曲線接到行程與移動 ✅ → W1、W2a（gap 1、4）
U movement authority → T；排在 W2c 之後，直接用曲線在授權終點前停下
V 交會與待避的推估 → W1（buildProfile、v/b）、S1 的單雙線，以及 gap 8
V 實際放行 → T、U（保證不互穿）
```

1. **W1** ✅（ARCHITECTURE 決策 33）：翻譯 `buildProfile`、`profTimeToProg`、`profProgToTime` 與性能表。純計算，golden 與 property digest 都不變。
2. **G1** ✅（第一個能玩的經營閉環，見 ROADMAP）：不依賴這份對照的任何 Stage。它對照的是 `Ci/` 的乘客與票價，不是 `Railway/`。
3. **W2a** ✅（ARCHITECTURE 決策 37）：時間改用秒（gap 2、9）。只換單位與速度檔位，不加新玩法。
4. **W2b** ✅（ARCHITECTURE 決策 39）：停站、上下車與誤點（gap 10）。驗收照參考包的 `02_W2_IMPLEMENTATION_CONTRACT.md`（見 ROADMAP 的 Stage W）。它是參考包的 P0，也是 G1 目前最明顯的缺口（上下車在離站時一次完成），只需要秒，不需要曲線。
5. **W2c** ✅（ARCHITECTURE 決策 40）：曲線接到行程與移動（gap 1、4）。
6. **C**（2026-10-02 作者決定）：已完成核心的操作畫面，讓所有功能都能在實機上測試；C1 是任意角度的建造（[對照](#stage-c1任意角度的建造畫面)），C2 是營運與乘客的設定畫面（[對照](#stage-c2營運與乘客的設定畫面)），C3 是性能的畫面（[對照](#stage-c3性能的畫面)）。見 ROADMAP 的 Stage C。
7. **F、E**（2026-10-02 作者決定，見 ROADMAP 的「目前的優先順序」）：F1 全面路網 ✅（車站自由擺設，App 只用路網；[對照](#stage-f1全面路網)）→ C4 ✅（[對照](#stage-c4存檔開始畫面與示範地圖)）→ C5 最小教學 ✅（[對照](#stage-c5最小教學)）→ E1 大地圖 ✅（[對照](#stage-e1大地圖)）→ 環線 ✅（[對照](#環線)）→ E2 空白／實景 ✅（MapKit，[對照](#stage-e2實景地圖)）→ F3 移除方格（進行中，[對照](#stage-f3移除方格)）→ F2 側向淨空；E3 MapLibre 視需要（照 `Ci/` 的 MapLibre 加 OpenFreeMap）。
8. **U-min**：建立在 T 上。參考只有畫面層的跟車距離（gap 5、6），授權規則照 T 的語義設計並標成 gap。
9. **V**：翻譯 `inferMeetPassTimes`、`planSameDirectionOvertakes` 與 `holds` 的語義。它也負責 T 留下的死結：單線兩端互等、時刻表造成的循環等待。

**順序（2026-10-01 作者決定）**：W2 先於 U-min。兩者互不依賴（U → T，W2 → W1），但後做的那個要處理「列車依曲線在授權終點前停下」；W2 先做，U-min 就直接建立在最終的移動方式上，不必先為固定的 rate 設計停車。

依 ARCHITECTURE 的依賴方向規則，G1 的乘客與經營只讀車站、線路與停站的查詢，所以之後的 U、V、W2 改變鐵路的物理層時，不必重寫它們。
