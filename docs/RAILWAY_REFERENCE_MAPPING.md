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
| 決定性除錯：種子、指令紀錄、checksum、重播（`docs/desync.md`） | golden scenario 就是指令序列的重播；property campaign 比對 digest | 世界的 checksum 與指令紀錄等需要時再加 | 大部分已涵蓋 |
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
6. **U-min**：建立在 T 上。參考只有畫面層的跟車距離（gap 5、6），授權規則照 T 的語義設計並標成 gap。
7. **V**：翻譯 `inferMeetPassTimes`、`planSameDirectionOvertakes` 與 `holds` 的語義。它也負責 T 留下的死結：單線兩端互等、時刻表造成的循環等待。

**順序（2026-10-01 作者決定）**：W2 先於 U-min。兩者互不依賴（U → T，W2 → W1），但後做的那個要處理「列車依曲線在授權終點前停下」；W2 先做，U-min 就直接建立在最終的移動方式上，不必先為固定的 rate 設計停車。

依 ARCHITECTURE 的依賴方向規則，G1 的乘客與經營只讀車站、線路與停站的查詢，所以之後的 U、V、W2 改變鐵路的物理層時，不必重寫它們。
