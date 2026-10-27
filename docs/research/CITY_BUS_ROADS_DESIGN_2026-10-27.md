# 獨立的市區公車與玩家自己鋪路：設計（2026-10-27）

派工單 Z，研究 session_01YGNNup4WomZDkri2osruHG，遊戲規劃 session_01YGNNuovwuBJPdZWXamkhEp 派工。
NEXT_PRIORITIES §22.13 第 2 項（獨立公車，2.60）與第 3 項（玩家鋪路，2.45）。
這份**只出設計**：不改程式、golden、存檔；決策號、存檔版本、golden schema 都**不預約**，下面寫的號碼都是「預估」，實作時在 #1041 登記。

讀的版本：遊戲 main `77e412f`；參考庫 `a91453/railway-reference-private` 的預設分支（2026-10-27 sparse clone）。

## 0. 一句話

- 公車路線可以不接車站：兩端都是站牌，載「站牌附近的人到同一條路線其他站牌附近」的鎮內旅次；經過車站 400 m 內時，照現在的接駁規則把人送進那座車站。
- 玩家可以在公車工具裡切到「道路」，在格子上鋪路、拆自己鋪的路；城市長的路與底圖的路照舊，玩家的路另外存。
- 兩件在同一張 GameCore PR 裡做，存檔只升一次（預估 74 → 75）。公車加上載客量上限，票價照舊一段 $5，成本照舊每車公里 $20，讓公車每個座位公里的成本約是鐵路的 8–10 倍：公車可以賺，但不會比鐵路好賺。

## 1. 現況（main `77e412f`）

### 1.1 公車（決策 400 的 10i-2、平衡續篇、10i-5）

- `Sources/GameCore/Passenger/BusRoute.swift`
  - `BusRoute`（第 87 行）：`station`（第 90 行，**必填**，路線最後一站之後就是這座車站）、`stops`（道路格子，1–64 個）、`legMetres`、`service`（班距或時刻）、`buses`、`feederTrips`／`feederMinutes`（需求算出來的）、`ridersToday`、`days`。
  - 常數：`stopReach` 400 m（第 111 行）、`metresPerHour` 18 km/h（第 113 行）、`layoverMinutes` 10、`stopPrice` $10,000、`busPrice` $50,000、`fare` $5（第 120 行）、`costPerKilometre` $20（第 124 行）、`riderShare` 1/2（第 128 行）。
  - 指令：`createBusRoute(to:stops:legMetres:service:buses:)`（第 295 行）、`setBusRouteStops`、`setBusCount`、`setBusRuns`、`removeBusRoute`、`recordBusAcquisition`。路徑：`busRoadMetres(from:to:)`（第 400 行，8 鄰格 Dijkstra，直 64 m、斜 90 m）。
  - 需求：`refreshBusFeeders()`（第 489 行）。站牌 400 m 內、**不在任何車站 800 m（`Land.catchmentRadius`，`Land.swift` 第 128 行）內**的格子，給最近的站牌；人數 × `riderShare` 併進那條路線**所接車站**的 `LandDemand.Share`。門到門分鐘＝步行（直線 ×1.25、每分 75 m）＋半個班距＋車上分鐘。
  - 乘客：`countBusRiders(_:at:)`（第 553 行）在列車從那座車站載客（`Boarding.swift` 第 354 行）與乘客在那座車站下車（第 206 行）時，按接駁占車站旅次的比例記成公車乘客。**公車乘客全部是鐵路乘客的一段**；沒有車站，路線就沒有需求。
  - 帳：`settleBuses(day:time:)`（第 566 行，`Operations.swift` 第 429 行每日呼叫）：乘客 × $5 收入，`dailyCost`＝每日班次 × 來回公里 × $20；記在 `dailyBuses`，不算票收（決策 179）。
  - 讀檔檢查：`busRoutesProblem()`（第 588 行）：有路線就要有道路；車站要存在。
- `Sources/GameCore/Passenger/ModeShift.swift`：`modeShiftKept`（第 147 行）把接駁那部分旅次的一端步行 6 分（`accessMinutes`，第 30 行）換成 3 ＋公車門到門分鐘，再照決策 332 和機車、汽車比。
- `Sources/GameCore/City/LandDemand.swift`：`refreshLandDemand()`（第 276 行）一開始就呼叫 `refreshBusFeeders()`，把接駁的份額加進車站。
- 平衡（決策 400「續篇：公車接駁的平衡」，HEALTHY）：一條路線讓車站旅次多 7.8–20.5%；臺北東 +$68,800／日、一班平均約 65 人；空白地圖鎮裡繞的路線一天虧約 $8,700，開到沒有車站的第三鎮 +$21,500。**沒有載客量上限**（決策 400 寫成下一步）。
- GamePresentation：`BusRouteEditor.swift`（`BusRouteDraft.station` 第 28 行，第一下一定點車站）、`ConstructionTool.bus`（`ConstructionTool.swift` 第 21 行，工具列「公車」）、`PlayerCommandEdit.swift`（`createBusRoute` 第 146 行）、`BusRoadNetwork.swift`、`Map3DBuses.swift`、`BusMotion.swift`。

### 1.2 道路（決策 400 的 10i-1 與續篇、決策 428）

- `Sources/GameCore/City/RoadGrid.swift`
  - `RoadGrid`（第 17 行）：`cells`（有路的 64 m 格）、`towns`（空白地圖的城鎮中心）、`readBlocks`（實景地圖讀過底圖的土地塊）。
  - `pricePerMetre` $50（第 38 行，鐵軌的一半）、`stationRoadMetres` 512 m、直 64 m／斜 90 m。
  - `enableRoads(towns:)`（第 157 行）：空白地圖每個城鎮中心 3×3 種子路。`turnOnRoads(towns:)`（第 171 行，決策 428）。
  - `setRoads(_:in:)`（第 227 行）：GamePresentation 把底圖 z14 圖磚 `transportation` 層算成格子交給 GameCore（`RealRoadCells.swift`；國道與快速道路不算，作者選 B）。
  - `buildStationRoad(at:)`（第 248 行）／`stationRoadQuote(at:)`（第 271 行）：**玩家唯一能鋪的路**，從車站到最近的路，最長 512 m，每公尺 $50，記資本支出；鋪好就併進 `cells`，和城市的路分不開，也拆不掉。
  - `growRoads()`（第 322 行）：每 30 天一次，城鎮朝最近的車站、其他每座車站從最近的路朝自己，各長一格；沒有亂數。
  - 存檔：`cells` 用行程長度（run）存，讀檔先檢查總數（決策 400 下一步第 2 點）。
- **舊存檔的道路**（決策 428）：`roads` 是選填 key，存檔 72 以前沒有。決策 428 不在讀檔時自動打開，改成玩家在「公車」工具按「打開道路與公車」：
  - 空白地圖：種子路放在原本的城鎮（`GameWorld.startingTowns()`，依序試幾個存檔裡的種子；都不符合就只用正中央），買過的地塊照 `seedBoughtTilesRoads()` 開它們的城鎮路。
  - 邊用邊讀土地的實景地圖：打開後由 `readRoads` 讀底圖的路。
  - 一開始就給全部土地、或沒有土地的實景地圖（台灣以外的城市、v4 的實景示範）：`.unreadable`，不能開。
- 存檔版本 72 加 `roads`，73 加 `busRoutes`（`SavedGame.swift` 第 375–386、574–586 行），現在 74（第 393 行）。
- golden、replay 都沒有道路與公車（`grep busRoutes\|"roads"` 只在 `SaveFixtures/v72-roads.json`、`v73-bus-route.json`）。

## 2. 前例

### 2.1 參考庫（照 CLAUDE.md 的順序先找）

| 參考庫的檔／函式 | 有什麼 | 本設計怎麼用 |
| --- | --- | --- |
| `Railway/island_city_reference_clean/source/js/g11.js` 第 3–24 行 `TYPES.road`（10 金一格）、`TYPES.bus`（80 金，要接道路）、`TYPES.mrt`（400 金） | 玩家一格一格鋪路；公車站、捷運站要蓋在路邊（`needRoad`，第 249 行） | 價格比例：路是公車站的 1/8、捷運站的 1/40。本作的路 $50/m（站前路的價），一格約 $3,200，是站牌 $10,000 的 1/3、車站 $200,000 的 1/60，同一個量級，**不改價** |
| 同上第 311–317 行（每日結算） | 捷運站每個員工一天 `(2 + 0.12 × 人口) × r − 1`，公車站 `2r − 1`：**捷運的收入隨人口長，公車的固定** | 「公車不能比鐵路好賺」的前例：參考把公車的收入上限定得比軌道低。本作用載客量上限做到同一件事（§3.4） |
| 同上 `g5.js` 第 123–131 行 `demolish` | 拆任何建築退一半錢 | 不搬：本作的公車與車都是「減的不退」（決策 400）；拆路不退錢，見 §3.2 |
| 同上 `g23.js` 第 3–15 行 `LV_W`（地價權重）：捷運 12、火車 6、公車 3 | 公車對地價的影響是火車的一半 | 鐵道迷與平衡的參考值：本作接駁份額 `riderShare` 已是步行的一半；鎮內旅次也用同一個 1/2 起算（§3.1） |
| 同上 `g11.js` 第 349 行（幸福度）：捷運 4 格內 +6、公車 3 格內 +4 | 公車的服務圈比捷運小 | 本作站牌 400 m、車站 800 m，比例一樣，不改 |
| `Railway/city_world_reference/source/assets/jobs-*.js`、`roadClearance-*.js` | `jobs` 是音訊工作模組，`roadClearance` 是幾何碰撞 | 沒有可用的（名字像，內容無關） |
| `Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` | 「每個 schema 改動要有明確的遷移函式與回歸 fixture」 | §3.3 存檔照這條：一次升版、加 fixture |
| `city_map_reference_clean/REFERENCE_COMPARISON.md` | 經緯度投影、OSM 道路分類 | 道路分類已在決策 400 續篇用過（`Map3DBaseMap.roadKind`）；沒有新的規則可搬 |
| `OpenWorld/reference_snapshot/play/src/world/road-network.js`（`RoadNetwork`、`RoutePath`） | 開車遊戲的道路圖（edge 拓撲、多段路徑） | 不搬：GameCore 已用 64 m 格子找路（決策 400「沒選的」：不把 OSM 路網放進 GameCore） |
| `Railway/geo-scene-reference-clean/source/docs/features/bus/design.md`、`src/engines/BusEngine.ts` | 照 GPS 與路線進度畫真實公車 | 已用於 10i-3、10i-6（畫面）；沒有需求或票價規則 |
| `Railway/taiwan-rail-reference-clean/source/data/bus-transfer/`、`bus-transfer-ui.js` | 車站 600 m 內的公車站牌、步行 ×1.25、每分 75 m | 已用（決策 400 的步行分鐘）；轉乘規則照舊 |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`（`ensureCityBusStopIndexLoaded`、`busstops`） | 公車站牌只用來替車站取名 | 沒有公車營運 |
| `Railway/tdx-bus-history-2026-10/data/Bus_Taipei_A1_2026-10-21.jsonl.gz`、`Bus_Kaohsiung_A1_2026-10-15.jsonl.gz` | TDX 市區公車的 GPS 位置與速度 | **量了公車的平均速度**（下面），給 §3.4 的鐵道迷依據 |
| `Railway/commuter_journey_reference_clean/`、`street_scene_reference_clean/`、`tw3d-reference-clean/` | 站內人流、街景車輛 | 只有畫面；本設計的畫面沿用決策 317、259、263 已搬的 |

**量到的**（VERIFIED，Linux 雲端容器，`python3 -I`，腳本只在 scratchpad）：同一輛車相鄰兩筆 GPS 相隔 5–120 秒、換算不超過 108 km/h 的段，距離和 ÷ 時間和：

| 檔 | 用的筆數 | GPS 距離 ÷ 時間 | `Speed` 欄平均 |
| --- | --: | --: | --: |
| 臺北，2026-10-21（週三），`DutyStatus` 1 | 338,449 | **13.6 km/h** | 17.0 km/h |
| 高雄，2026-10-15（週四），`DutyStatus` 0 | 339,670 | **16.2 km/h** | 13.2 km/h |

- 含停站、紅燈的營運速度。遊戲的 18 km/h 稍快（臺北的 1.3 倍）；取樣是 `$top` 截斷的，不是全天全線（資料夾的 README）。
- **缺口**：參考庫沒有「不接車站的公車需求」、「玩家的路與城市的路並存」、「公車與鐵路的票價比較」的規則，都是這份設計自己寫的。

### 2.2 外部專案（只看想法）

| 專案 | 授權 | 看到的 | 拿了什麼 |
| --- | --- | --- | --- |
| A 列車で行こう 9／Exp.（ARTDINK，商業遊戲；只看玩法說明 <https://arx.neorail.jp/appendix/>、<https://wikiwiki.jp/a-train9/>（搜尋摘要；本頁 403）、<https://weekly.ascii.jp/elem/000/004/048/4048696/3/>） | 商業 | 道路由「自動發展」長出，也可以自己敷設、撤去；新路長在車站正面；沒有建物的路會消失。公車與列車一樣帶動發展，但定員小（近距離公車 56 × 200% ＝ 112 人，通勤電車 1,507 × 200%）；**公車的營收記在每台車**，站牌與巴士總站只有成本（資產稅）。攻略的結論：先鐵路、後公車，「為了公車去鋪路」不划算 | 公車要有載客量上限、單車的成本比鐵路高；玩家的路要錢（`はじまる観光計画` 的路是公共物，費用當期全部列支）；城市的路照舊自己長 |
| OpenTTD（<https://github.com/OpenTTD/OpenTTD>、<https://wiki.openttd.org/en/Manual/Game%20Mechanics/Cargo%20income>） | GPL-2.0，只看想法 | 乘客收入＝費率 × 人數 × 起訖站的曼哈頓距離 × 時間係數；同一種貨物不分車種。玩家鋪的路歸公司，城鎮的路拆了要扣評價（`town_type.h` 的 `RATING_ROAD_*`） | 收入照起訖距離、不分公車鐵路 → §3.4 用「同距離每人公里收入」比較；城市的路玩家不能拆 |
| Simutrans（<https://github.com/simutrans/simutrans>、<https://www.wiki.simutrans.com/en_extended_Passengers>） | Artistic License 1.0，只看想法 | 乘客從住宅產生，往有工作或訪客需求的建物；起訖在同一個站的服務圈內就走路 | 鎮內旅次的終點照「有工作的人數」分配（§3.1 的引力）；同一個站牌附近的人走路，不搭公車 |
| A/B Street（<https://github.com/a-b-street/abstreet>） | Apache-2.0 | 起訖矩陣切成個人旅次，旅次有走路→公車→走路的多段；可以改車道 | 沒有拿程式（Rust、旅次層級太細）；「多段旅次」列在沒選的 C |

## 3. 設計

### 3.1 (a) 獨立公車：需求從哪來

**路線**
- `BusRoute.station` 改成選填（`StationID?`）。有車站的照舊（接駁路線，最後一站之後是車站）；沒有車站的是「市區路線」，至少 2 個站牌，兩端都是站牌。
- 找路、長度、班距、車數、成本的算法照舊：市區路線的來回就是第一個站牌到最後一個站牌。

**鎮內旅次**（新的，GameCore，`refreshBusFeeders` 旁邊一個 `refreshCityBusTrips`，每次 `refreshLandDemand` 一起算）：
1. 每條在跑的路線（至少一輛車），每個站牌 400 m 內、**不在任何車站 800 m 內**的格子，照現在的規則給最近的站牌（同距離取路線、站牌在前的）。接駁與市區路線一起分，一格只屬於一個站牌。
2. 一格的人（住戶＋工作）每 100 人一天 40 旅次（`LandDemand.tripsPerHundred`，和車站同一個數），乘上 **`BusRoute.localShare`（預估 1/4）**：這是這些人在鎮內、不搭火車的那部分旅次。接駁份額 `riderShare`（1/2）照舊另算，兩者不重疊：一個是去車站，一個是去同一條路線的其他站牌。
3. 站牌 i 的旅次分給同一條路線的其他站牌 j，**照 j 的人數比例**（`dailyDemand` 的引力，最大餘數，同數取站牌在前的）；Simutrans 的做法：住戶往有工作的地方，所以住宅站牌的人往工作多的站牌去。
4. 照 i、j 兩個站牌的直線距離打折，和鐵路同一條規則（`DistanceDemand`）：500 m 內只剩 10%、2 km 起全部、中間直線。所以一條 1 km 的路線幾乎沒有鎮內旅次，**跨鎮或長一點的路線才有**。
5. 和機車、汽車比（決策 332 的 `ModeShift`，簡單與寫實的上限照舊）：公車的分鐘＝兩端步行＋半個班距＋車上分鐘；道路的分鐘照 i、j 的直線距離。
6. 剩下的是這條路線一天的鎮內乘客。和接駁乘客加起來，**不多於載客量**（§3.4）：每天的班次 × 2（來回）× 70 人；超過的不搭（不往回影響鐵路）。
7. 鎮內乘客每人付一段 $5，和接駁同一個 `ridersToday`、同一筆 `dailyBuses`。在每日結帳時加進 `ridersToday`（鎮內旅次不經過列車的上下車，照日計，決定性）。

**和鐵路怎麼轉乘**
- 接駁路線照舊。
- 市區路線經過車站：任一個站牌離車站不到 400 m，這條路線就是那座車站的轉乘路線（最近的那座；同距離取車站編號小的）。不在車站 800 m 內的站牌，它們的人照現在的接駁規則（`riderShare`、門到門分鐘）併進那座車站，`countBusRiders` 照樣把轉乘的人記成公車乘客。這個「轉乘站」是每次算需求時推出來的，**不存**。
- 鐵路的旅程規劃（`PassengerRoutes`）不走公車：沒有「公車→鐵路→公車」的多段旅次（沒選的 C）。
- **不搶鐵路的人**：鎮內旅次只來自車站 800 m 以外的格子，而這些格子現在對鐵路的需求只有接駁那一半；鎮內旅次是另外加的旅次，不從車站的份額扣。報告要量「加一條市區路線後，鐵路票收旅次不少於之前」（§3.4 第 6 項）。

### 3.2 (b) 玩家鋪路

**存**
- `RoadGrid.built: Set<CellPosition>`：玩家鋪的路（存檔 key `"built"`，和 `cells` 一樣用 run 存；缺 key＝沒有）。
- `cells` 照舊是城市的路（種子、長的、底圖讀的、舊的站前路）。
- 「有路」＝`cells ∪ built`：`hasRoad`、找路（`busRoadMetres`）、站前路找最近的路、`growRoads` 都看聯集。改成一個 `RoadGrid.contains(_:)`；GamePresentation 讀 `cells` 的 10 處改用它。
- 以後鋪的站前路也進 `built`（可以拆）。已經在 `cells` 裡的站前路不搬（分不出來），照舊拆不掉。

**鋪**（新指令 `buildRoad(along cells: [CellPosition])`）
- 一串相鄰（8 鄰格）的格子，最多 256 格（16 km）。每一格要在世界裡、不是水、不是陡坡（和 `canHaveRoad` 同一條）；不合的就整個拒絕（`onWater`、新的 `GameError.roadTooSteep`），世界不變。
- 已經有路的格子不收錢、不重複放（可以從城市的路接出去，也可以穿過）。
- 價格＝新格子的公尺數 × $50（直 64 m、斜 90 m，和站前路同價），記資本支出（不是資產，和站前路一樣）。錢不夠就拒絕。
- 不管鐵軌：路可以穿過軌道（平交道），和站前路現在一樣；3D 照決策 259／263 畫交叉。
- 不碰土地：路不佔房子（格子的住戶與工作照舊），只有格子上「有路」。和城市自己長的路同一套。

**拆**（新指令 `removeRoads(_ cells: [CellPosition])`）
- 只能拆 `built` 裡的格子；拆到城市的路（`cells`）就拒絕（新的 `GameError.notOwnRoad`）。
- 有公車路線的路徑經過那格（照 `busRoadMetres` 找出的路），就拒絕（新的 `GameError.roadInUse(BusRouteID)`），面板寫是哪一條路線。
- 不收錢、不退錢（和「減的不退」的車、站牌一樣）。

**和城市自己長的路並存**
- 城市照舊每 30 天長一格；從聯集裡最近的路長，所以玩家的路接近車站時，城市就不再朝那座車站長（目標已有路）。
- 城市長進玩家的格子：不會（已有路就不長）；長在玩家的路旁邊：照舊。
- 拆掉玩家的路之後，城市照規則再長；不會自己「衰退」（沒選 A 列車的衰退：要動土地規則）。

**實景地圖**
- 底圖的路照舊由 `setRoads` 進 `cells`；玩家的路進 `built`。
- 玩家在底圖沒有路的地方鋪（新開發區、接兩條斷開的路）。底圖已經有路的格子不收錢。
- 之後才讀到的土地塊，底圖的路照舊併進 `cells`；同一格在兩個集合裡時，拆掉玩家那份，城市的還在。
- 國道與快速道路照舊不算（作者選 B）；玩家鋪的是一般道路。
- **讀不到路的實景地圖**（台灣以外、v4 示範，決策 428 的 `.unreadable`）：打開道路時沒有城市的路，只有玩家鋪的。`roadsOffer` 改成 `.ownRoadsOnly`（可以打開），說明「這張地圖沒有現成的道路，可以自己鋪」。新遊戲照舊不開（不改決策 400 續篇第 4 點）。

### 3.3 (c) 一起改，存檔只升一次

**新欄位**（預估存檔 **75**；實作時照 #1041 取下一個空號）
| 欄位 | 在哪 | 缺 key 時 |
| --- | --- | --- |
| `BusRoute.station` 改選填 | `busRoutes[].station` | 75 以前一定有 → 接駁路線，照舊 |
| `RoadGrid.built` | `roads.built`（run） | 沒有玩家的路 |

- 也存的：每條路線的鎮內旅次與分鐘 `localTrips`、`localMinutes`，和 `feederTrips`、`feederMinutes` 一樣存、一樣檢查（讀檔後第一天的乘客和存檔前一樣）；缺 key＝0，下一次 `refreshLandDemand` 會補。
- 不存的：轉乘站（每次算需求時推出來）。
- **遷移步驟**：74 → 75 沒有要轉換的值（缺 key 的意思就是舊的行為）；`SavedGame` 的版本說明加第 75 條：「舊 build 讀不到沒有車站的路線，也會丟掉玩家的路，所以說存檔比它新」。
- **新 fixture**：`SaveFixtures/v75-city-bus-roads.json`：空白地圖、一條市區路線（沒有車站）、一條接駁路線、幾格玩家的路。
- **golden 會動哪些值**：**預估不動**。golden 與 replay 都沒有道路與公車（§1.2）；沒有公車的世界，`refreshCityBusTrips` 直接返回，載客量上限也碰不到。實作時跑 `GoldenScenarioTests`、`ReplayFixtureTests`、`SavedGameTests` 確認；golden 的錯誤名稱表（`GoldenScenario.swift`）要加三個新錯誤名稱，**schema 不動**（決策 428 的 `roadsEnabled` 同樣的做法）。
- **已有公車的存檔會變的**：載客量上限也套在接駁路線上。決策 400 量到最擠的臺北東一班平均 65 人、一天 240 班，上限 33,600 人遠大於 15,623 人，所以量過的路線都不變；更擠的路線會少記一些乘客。PR 要在 `BusFeederReportTests` 寫前後。

### 3.4 (d) 經濟（照 `.claude/skills/economy-balance/SKILL.md`）

**定的值**（預估，PR 1 量完可以調，調了寫回決策）
| 值 | 定為 | 理由 |
| --- | --- | --- |
| 票價 | 照舊一段 $5（`BusRoute.fare`），市區與接駁同價 | 臺北市公車一段 NT$15，NT$3＝$1；新遊戲鐵路沒設票價時也是一趟 $5（`FareRules.standard`） |
| 成本 | 照舊每車公里 $20 | 台灣市區公車每車公里 NT$52–66（決策 400） |
| **載客量** | 新的 `BusRoute.capacity` ＝ **70 人**一班一個方向 | 臺北市區公車滿載約 60–80；A9 近距離公車 112（200%）。決策 400 量到最擠的一班平均 65 |
| 鎮內份額 | 新的 `BusRoute.localShare` ＝ **1/4** | 起算值：接駁是 1/2，鎮內不搭火車、又要和機車比，取一半；交通部 2024 民眾日常使用運具狀況調查（決策 332 用的同一份）表 4 的公共運輸占比在實作時查來對 |
| 速度 | 照舊 18 km/h | TDX 量到 13.6–16.2 km/h（§2.1），稍快；改了會動決策 400 已 HEALTHY 的接駁，PR 1 在報告裡多跑一次 15 km/h 看差多少，不改值 |
| 道路 | $50／m（站前路的價），拆不收不退 | 鐵軌的一半（決策 400 研究 3.2） |

**為什麼公車不會比鐵路好賺**（現有常數算的，不是量的）：
- 每個座位每公里的成本：公車 $20 ÷ 70 ＝ **$0.29**；鐵路一列 4 節（`Train.capacityPerCar` 352 × 4 ＝ 1,408 人）每列車公里 $42，加每班 $75 攤在 10 km ＝ $49.5 ÷ 1,408 ＝ **$0.035**（未算車重的成本）。公車約是鐵路的 **8 倍**（2 節車時約 4 倍）。
- 收入：兩者都是一趟 $5（玩家沒設鐵路的距離票價時）。所以**同距離每人公里的收入，公車＝鐵路的 10 成**；台灣真實也是如此（臺北公車一段 NT$15、台鐵 10 km 內最低 NT$15）。差別在成本與載客量，不在票價。
- 載客量上限讓一條公車路線的收入有天花板：每 10 分一班、一天 144 班，來回最多 20,160 人、$100,800；同樣路線鐵路一列 4 節的座位多 20 倍。

**目標**（實作的報告要對這些數字；現在都是 **NOT ASSESSED — NO DATA**，因為規則還沒寫）

| # | 數字 | 目標 | 出處 |
| --: | --- | --- | --- |
| 1 | 同距離（2、5、10 km）每人公里收入，公車 ÷ 鐵路 | **≤ 1.0**（預設票價下＝1.0） | 這份；台灣的真實票價 |
| 2 | 每人公里的營業利益，公車 ÷ 鐵路（同一對城鎮、同樣班距） | **≤ 0.5** | 這份（「主角是鐵路」）；島城 `g11.js` 公車收入固定、捷運隨人口長 |
| 3 | 空白地圖兩鎮之間（種子 1，第一站到第三鎮 6,254 m）一條市區路線每天淨額 ÷ 同兩鎮一條鐵路每天營業利益 | **≤ 0.3** | 這份 |
| 4 | 實景地圖（臺北、竹北、豐原、屏東，同決策 400 的四站）最好的一條市區路線每天淨額 ÷ 同城第一條鐵路第 331–360 天的每天營業利益（臺北 $637,631，決策 400 10j-3） | **≤ 0.25** | 這份 |
| 5 | 一條市區路線（3 站牌、2 輛車、$130,000）回本天數 | **≥ 10 天**（鐵路第一條線 4–10 天，`NewGameBalanceTests`） | 決策 46、137；這份 |
| 6 | 加一條市區路線後，鐵路票收旅次 | **不少於之前**（加了反而變差＝bug） | economy-balance §4 |
| 7 | 一班平均載客 | 20–70，沒有一條長期頂到上限 | 這份；A9 定員 |
| 8 | 接駁路線（決策 400 的 16 條）的乘客與淨額 | 改前後差 **< 1%** | 決策 400 的 HEALTHY 不被打破 |
| 9 | 鎮裡繞的市區路線（1–2 km） | **虧錢**（和接駁一樣：不合理的路線虧） | 決策 400 平衡續篇 |

判定：照最壞的那一項；1–9 有一項超出就是 CONCERNS，調 `localShare`（第一個調）或 `capacity`，不調票價與成本（它們有真實出處）。

**要寫的報告測試**（只在要求時跑，release）：
- `Tests/GamePresentationTests/CityBusReportTests.swift`，`CITY_BUS_REPORT=<天>`：
  - `testACityRouteBetweenTowns`：空白地圖種子 1，(i) 只有鐵路、(ii) 鐵路＋第一站到第三鎮的市區路線、(iii) 只有市區路線；量 #2、#3、#5、#6、#7。
  - `testACityRouteInsideATown`：鎮裡 1–2 km 的三條（同決策 400 的三個方向），量 #9。
  - `testACityRouteOnTheRealMap`：四座真實車站各一條不接車站、離車站 1–3 km 的市區路線，配決策 400 的鄰站鐵路；量 #4、#6、#7。
  - `testFareAndCostPerPassengerKilometre`：2、5、10 km 的公車與鐵路各一條，量 #1、#2。
  - `CITY_BUS_SPEED=15` 再跑一次（只看，不判）。
- `BusFeederReportTests` 照舊跑，量 #8。

### 3.5 (e) 畫面

**工具列**：不加新按鈕（手機側拿時工具欄已經滿，決策 382）。「公車」工具裡上方多一個兩段切換：**路線｜道路**。
- **路線**（現在的流程，多一種開法）：
  - 先點車站：照舊，接駁路線。
  - 先點路面：開一條市區路線，第一個站牌就在那裡；再點路面加站牌；✓ 要至少兩個站牌。
  - 預覽卡照舊寫價錢、每天成本，「每天的乘客」改成接駁加鎮內兩行；經過車站時寫「在○○站可以轉乘」。
- **道路**：
  - 按住拖過格子，畫出一條路的預覽（新的格子實線、已經有路的格子淡色），卡片寫「鋪路 · $價錢」，✓ 才送出；水或陡坡那一段紅色虛線，寫「這裡不能鋪路」。
  - 點自己鋪的路：「拆掉這段路」（確認一次）；點城市的路：「這是城市的路，不能拆」。
  - 道路模式只在有道路的世界；沒有道路時照決策 428 先出「打開道路與公車」。
- **路線卡**：車站面板的公車卡照舊；市區路線沒有車站，放在新的「公車路線」清單（資料面板的一頁），每條一張同樣的卡。
- **2D**：玩家的路和城市的路同一種街（決策 263 的種子街），不另外上色；道路模式開著時，自己的路描一圈細框，看得出哪些能拆。市區路線的線色用藏青（沒有車站可以借色），站牌照舊白點藏青框。
- **3D**：空白地圖照舊畫格子的街；實景地圖多畫 `built` 的格子（決策 259 的街道畫法，沿格子中心連線）。
- **說明頁**（`HelpGuide` 的「城市」）：
  - 改「道路從哪裡來？怎麼開公車？」：路是城市自己長的，也可以自己鋪；公車可以從車站開，也可以只在城裡開，從一個站牌開到另一個站牌。
  - 加「怎麼自己鋪路？」：在「公車」工具切到「道路」，拖過要鋪的地方；只能拆自己鋪的路，有公車走的路要先改路線。
  - 照玩家看的文字規則：不寫係數、份額、格子大小。
- 字（兩種語言）列在 PR 2 的 String Catalog。

## 4. 分 PR

| # | PR | 主要的檔 | tier | 存檔 | 決策 | 測試 |
| --: | --- | --- | --- | --- | --- | --- |
| 1 | **GameCore：市區路線、鎮內旅次、載客量、玩家的路** | `Sources/GameCore/Passenger/BusRoute.swift`（`station` 選填、`localShare`、`capacity`、`refreshCityBusTrips`、轉乘站、結帳）、`Sources/GameCore/City/RoadGrid.swift`（`built`、`contains`、`buildRoad`、`removeRoads`、`growRoads` 看聯集）、`LandDemand.swift`（呼叫）、`GameError.swift`（`roadTooSteep`、`notOwnRoad`、`roadInUse`）、`SavedGame.swift`、`GoldenScenario.swift`（錯誤名稱）、`SaveFixtures/v75-city-bus-roads.json`、`docs/decisions/<N>.md` | 完整 tier（GameCore） | **升，預估 75** | 預估 1 個 | `BusRouteTests`（市區路線、轉乘站、載客量、讀檔拒絕）、新的 `CityBusTripsTests`（引力、距離打折、不搶鐵路、決定性）、`RoadGridTests`（鋪、拆、拒絕、聯集、成長）、`SavedGameTests`（v75 fixture、74 讀成接駁）、`GoldenScenarioTests`／`ReplayFixtureTests` 不變；報告 `CityBusReportTests`、`BusFeederReportTests` |
| 2 | **畫面：公車工具的路線｜道路、說明、2D／3D、沒有底圖的地圖** | `Sources/GamePresentation/BusRouteEditor.swift`（先點路面）、新 `RoadDraft.swift`（拖格子的預覽、價錢）、`PlayerCommandEdit.swift`（`buildRoad`、`removeRoads`、`createCityBusRoute`）、`RoadsTurnOn.swift`（`.ownRoadsOnly`）、`BusRoadNetwork.swift`、`Map3DStreets.swift`／`Map3DBuses.swift`（`built`）、`HelpGuide.swift`、`Achievements.swift`（讀 `cells` 的地方）、App 的 `ControlPanel.swift`、String Catalog | GamePresentation（五個 job） | 不動 | PR 1 決策的續篇（0 個；畫面另有取捨時預估 1 個） | `BusRouteEditorTests`、新的 `RoadDraftTests`、`RoadsTurnOnTests`、`CommandEditTests`（新指令寫進讀回）、`HelpGuideTests`；UI 測試不進 gate（拖格子不穩，照 10i-5 的理由），要加就放 full lane |
| 3 | （**有條件**）平衡調整 | `BusRoute.swift` 的 `localShare`／`capacity`、決策的「量到的」 | 完整 tier | 不動 | 不加 | PR 1 的報告判 CONCERNS 時才開；判 HEALTHY 就不開 |

- 順序：1 → 2（2 要 1 的指令）。3 只在 1 的報告不過時開，而且在 2 之前或之後都可以。
- PR 1 的報告只量規則（沒有玩家操作），所以 PR 1 就能判 #1–#9；PR 2 合併後在 TestFlight 看玩家實際怎麼畫。
- 和其他線：決策 429（紅綠燈）只在畫面，不衝突；`Map3DStreets.swift` 有人改時，PR 2 先協調。

## 5. 五方（選的：一起設計、GameCore 一張升一次存檔、市區路線載鎮內旅次並可轉乘、玩家的路另外存）

- **玩家**：兩位測試者要的「在城裡自己開公車」與「路不夠自己鋪」一次給齊；工具列不多按鈕，學過畫公車的人就會；鎮裡繞的路線會虧、跨鎮的會賺，畫得好不好有差。
- **鐵道迷**：台灣的市區公車多半不是鐵路接駁，市區路線比較真；票價一段 NT$15、每車公里 NT$52–66、營運速度用 TDX 量過（13.6–16.2 km/h）；載客量讓公車像公車，不會一班載一列車的人，鐵路仍是主角。
- **開發**：兩件在同一張 GameCore PR，存檔只升一次；缺 key＝舊行為，golden 與 replay 預估不動；鎮內旅次重用車站的引力、距離打折與 `ModeShift`，不另寫一套旅次模型；玩家的路分開存，拆路只要看一個集合。
- **美術**：玩家的路和城市的路同一套街（決策 259、263），只在道路模式描框；市區路線用藏青、站牌沿用；實景地圖的玩家路照決策 259 畫，和底圖的路分得出又不突兀。
- **音樂**：無（鋪路與開路線沿用建造的聲音）。

**加權**（權重照 NEXT_PRIORITIES §19：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）：

| 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --- | --: | --: | --: | --: | --: | --: |
| **選的** | **5** | 3 | 3 | **4** | 1 | **3.45** |
| A 維持只接車站 | 1 | 5 | 1 | 2 | 1 | 2.15 |
| B 公車不用車站但需求照舊 | 1 | 4 | 2 | 1 | 1 | 1.90 |
| C 公車進鐵路的旅程規劃（多段） | 4 | 1 | 3 | 5 | 1 | 2.80 |
| D 兩件分開設計、各升一次存檔 | 4 | 2 | 3 | 4 | 1 | 2.90 |
| E 道路決定房子長在哪（A9 式發展與衰退） | 3 | 1 | 4 | 2 | 1 | 2.20 |
| F 玩家的路直接併進城市的 `cells` | 3 | 4 | 3 | 1 | 1 | 2.65 |

## 6. 沒選的（預覽是玩家會看到的）

- **A 維持「公車接車站」，只回覆玩家這是設計**：預覽「公車路線要從車站開出去。」兩位測試者各自提了同一件，表示這個限制讓人困惑。
- **B 公車路線不用車站，需求照舊**：預覽「市區 1 號 · 每天的乘客 0」。現在的需求全部是接駁到鐵路的人，沒有車站就是 0，路線開了也沒人搭，比現在更困惑。
- **C 公車進鐵路的旅程規劃**（公車→鐵路→公車都算一趟、選最快的組合）：預覽「從○○社區到台北車站：公車 12 分＋區間車 25 分」。最真，但 `PassengerRoutes` 要加公車的邊、每分鐘的上下車要算公車，模擬變慢、replay 全部要重驗；接駁的門到門分鐘已經做到「公車讓遠處的人搭火車」的效果。
- **D 兩件分開，各升一次存檔**：玩家要的是同一件事（在城裡開公車，路不夠就鋪），分兩次升版就要兩次 fixture、兩次完整 tier，中間還有一段「能開市區公車卻不能鋪路」的版本。
- **E 道路決定房子長在哪**（A 列車 9 的自動發展：路長出去房子跟著長，拆路房子跟著消失）：預覽「拆掉這段路，旁邊 12 戶也會消失。」要改土地與城市成長的規則，golden 全動；玩家鋪路變成都市計畫，不是公車的配角。
- **F 玩家的路直接併進城市的路**：預覽「這段路不能拆。」少一個欄位，但玩家鋪錯就拆不掉；決策 400 的站前路已經是這樣，玩家也問過。
- **票價照距離分段**（2 km 內 $3、之後每 5 km 加 $2）：預覽「市區 1 號 · 票價 $3–$7」。和臺北公車一段票不同；鐵路預設也是一趟 $5，分段要另做一個票價編輯器。
- **沒有載客量上限**：一條路線可以一班載上千人，跨鎮的市區路線會比鐵路好賺（座位公里成本的優勢不見了）。
- **鎮內份額和接駁一樣 1/2**：只是起算值的另一個；1/4 先量，報告不過再調（PR 3）。
- **拆路退一半錢**（島城 `demolish` 的做法）：預覽「拆掉這段路，退回 $1,600。」鋪了拆、拆了鋪可以套錢；本作的車、站牌也不退。
- **能拆城市的路，扣城市的好感**（OpenTTD 的評價）：本作沒有城市好感，加一個系統只為了拆路。
- **道路工具放在「路網」工具**：路網的模式已經很多（鋪軌、月台、拆除、描線），路也不是軌道。
- **工具列多一個「道路」按鈕**：手機側拿時工具欄要捲動（決策 382），多一個按鈕就多擠一格。
- **公車速度改成 15 km/h**（照 TDX）：會動決策 400 已判 HEALTHY 的接駁平衡；先在報告裡看差多少。
- **讀不到路的地圖照舊不能開公車**：預覽「這張地圖讀不到道路，不能開公車。」台灣以外的城市永遠沒有公車；能自己鋪路之後，這個限制就沒有理由了。

## 7. 驗證（這份文件）

- `python3 -I tools/golden-checks/doc_numbers.py --check`：見 PR。
- TDX 公車速度：VERIFIED（Linux 雲端容器，`python3 -I`，參考庫的兩個 A1 檔）。
- 所有平衡目標：**NOT ASSESSED — NO DATA**（規則還沒寫；PR 1 的報告量）。
- 現有程式的行號：在 main `77e412f` 上讀的；實作時以當時的 main 為準。
