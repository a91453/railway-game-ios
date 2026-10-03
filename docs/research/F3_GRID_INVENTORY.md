# F3：GameCore 方格相容層使用盤點

查閱日期：**2026-10-03（UTC）**。基準：`main` 的 **`b20cb2861843ba1bde460bd50e36848583c98921`**。以下行號均指這個 commit；連結使用儲存庫相對路徑，後續程式變動時請以此 commit 校對。

這是 Stage F3 計畫的唯讀輸入，依據 [ROADMAP 的 F3](../ROADMAP.md#stage-f--全面路網與自由擺設)、[ARCHITECTURE 決策 28](../ARCHITECTURE.md#28-topology--geometry--renderingphase-45-起的鐵路核心分層)、[決策 29](../ARCHITECTURE.md#29-連續軌道幾何phase-45-stage-s3設計決策) 與 [決策 44](../ARCHITECTURE.md#44-全面路網任意座標的車站stage-f1)。只新增本筆記；未修改 GameCore、golden、存檔、測試、差分模型、schema、ROADMAP 或架構決策。下文的「可改寫」是研究判斷，不是批准改動行為契約。

## 盤點結論與邊界

- **27 份 golden 中 25 份有方格依賴**；只有 `clock-speed-and-pause.json` 與 `continuous-track.json` 沒有方格指令／方格放置。`network-service`、`vertical-railway`、`traffic-reservation` 雖以路網行駛，仍建方格車站。
- **SaveFixtures 四份存檔均無方格鐵軌或方格車站**。但測試在記憶體內另造了舊方格存檔，不能由這四份 fixture 推論舊格式無人使用。
- **App 仍有方格相容呼叫**：舊世界的繪圖、選取、列車放置／送往；F1 隱藏的方格建造工具仍實作於 GamePresentation。
- **方格相關名稱不全是可刪的相容層**：路網仍依 `GridMap` 決定地圖大小，以 `Station.position` 算票價距離，並以 `TrackDirection` 選路網列車的初始朝向。F3 需要先定義這些使用的替代方式。

盤點涵蓋 `Sources/GameCore/`、全部 `GoldenScenarios/*.json`、全部 `Tests/GameCoreTests/`、全部 `SaveFixtures/*.json`、`Sources/GamePresentation/` 與 `RailwayGameApp/` 的 Swift 呼叫端。以 `rg -n` 搜尋型別、case、指令及欄位，讀取所在函式與共用 generator，再以 Python 標準函式庫解析 JSON（沒有寫回）。型別／API 的定義與同檔使用分支分開列出；共用函式只列方格分支，不能整個移除。

## 1. Sources/GameCore

### 1.1 方格鐵路專用型別、case 與欄位

下表是方格鐵路／方格車站的直接表示；含方格 case 的 enum／struct 本身常與路網共用。

| 項目 | 定義與使用位置 | 方格用途／移除範圍 |
| --- | --- | --- |
| `Track` | [Track.swift:9](../../Sources/GameCore/Railway/Track.swift#L9) | 格上的軌道零件：`position`、`connections`、`layout`；不是路網的 `TrackEdge`。 |
| `TrackLayout.open`、`.turnout(stem:)`、`.crossing`、`joins` | [Track.swift:23](../../Sources/GameCore/Railway/Track.swift#L23)、[35](../../Sources/GameCore/Railway/Track.swift#L35) | case 分別在 [25](../../Sources/GameCore/Railway/Track.swift#L25)、[28](../../Sources/GameCore/Railway/Track.swift#L28)、[30](../../Sources/GameCore/Railway/Track.swift#L30)，是方格零件的轉向規則。路網轉向由 `TrackNodeEnd.exits` 推導。 |
| `TrackDirection.north/east/south/west`、`opposite`、相鄰格初始化器 | [TrackDirection.swift:2](../../Sources/GameCore/Railway/TrackDirection.swift#L2)、[22](../../Sources/GameCore/Railway/TrackDirection.swift#L22) | 方格出口、heading、步進；Presentation 仍將它用作路網放置方向，見 §5。 |
| `TrackConnections`、四方向 bit、`directions` 與 Codable | [TrackDirection.swift:41](../../Sources/GameCore/Railway/TrackDirection.swift#L41)、[48](../../Sources/GameCore/Railway/TrackDirection.swift#L48)、[65](../../Sources/GameCore/Railway/TrackDirection.swift#L65)、[77](../../Sources/GameCore/Railway/TrackDirection.swift#L77) | 方格出口 bitmask、穩定順序、未知 bit 驗證。 |
| `TrackNodeID.tile(GridPosition)`；tile 排序 | [TrackGraph.swift:20](../../Sources/GameCore/Railway/TrackGraph.swift#L20)、[32](../../Sources/GameCore/Railway/TrackGraph.swift#L32) | 方格節點的身分；保留路網 `.node(Int)`。 |
| `TrackEdgeID.link(GridPosition, GridPosition)`、`link(between:and:)`、`precedes`；link 排序 | [TrackGraph.swift:48](../../Sources/GameCore/Railway/TrackGraph.swift#L48)、[54](../../Sources/GameCore/Railway/TrackGraph.swift#L54)、[59](../../Sources/GameCore/Railway/TrackGraph.swift#L59)、[70](../../Sources/GameCore/Railway/TrackGraph.swift#L70) | 兩格的 canonical 連結與 row-major 排序；保留 `.edge(Int)`。 |
| `TrackTraversal.link(from:to:)` | [TrackGraph.swift:108](../../Sources/GameCore/Railway/TrackGraph.swift#L108) | 將方格兩端換成有方向的連結；`TrackTraversal` 與 `TrackEdgeDirection` 是共用拓撲。 |
| `RailwayNetwork.pieces`、`track(at:)`、`tracks`、`lay`、`removeTrack(at:)` | [RailwayNetwork.swift:125](../../Sources/GameCore/Railway/RailwayNetwork.swift#L125)、[167](../../Sources/GameCore/Railway/RailwayNetwork.swift#L167)、[172](../../Sources/GameCore/Railway/RailwayNetwork.swift#L172)、[178](../../Sources/GameCore/Railway/RailwayNetwork.swift#L178)、[184](../../Sources/GameCore/Railway/RailwayNetwork.swift#L184) | 方格鐵軌唯一的權威儲存。`isPristine` 在 [160](../../Sources/GameCore/Railway/RailwayNetwork.swift#L160) 刻意不算方格：方格另存於 `SavedMap`。 |
| `TrainPosition.atNode`、`.onLink`、`linkLength` | [TrainPosition.swift:40](../../Sources/GameCore/Railway/TrainPosition.swift#L40)、[44](../../Sources/GameCore/Railway/TrainPosition.swift#L44)、[55](../../Sources/GameCore/Railway/TrainPosition.swift#L55) | 方格車頭；一格連結長 1024。路網使用 `.onEdge`。`linkLength` 另被共用車長引用，不能直接刪常數。 |
| `TrainPosition.isOnGrid`、`reversed`、`ahead`、`isSupported(by:)` | [TrainPosition.swift:78](../../Sources/GameCore/Railway/TrainPosition.swift#L78)、[88](../../Sources/GameCore/Railway/TrainPosition.swift#L88)、[105](../../Sources/GameCore/Railway/TrainPosition.swift#L105)、[122](../../Sources/GameCore/Railway/TrainPosition.swift#L122) | 方格反向、前方節點／heading、拆軌支撐檢查；`isWellFormed` 在 [65](../../Sources/GameCore/Railway/TrainPosition.swift#L65) 的方格分支。 |
| `TrainPosition` 的 `atNode/onLink` 存檔 tag 與 encode/decode | [TrainPosition.swift:138](../../Sources/GameCore/Railway/TrainPosition.swift#L138)、[170](../../Sources/GameCore/Railway/TrainPosition.swift#L170)、[208](../../Sources/GameCore/Railway/TrainPosition.swift#L208) | 舊位置序列化；路網 `onEdge` codec 共用同一個 enum。 |
| `TrainMovement.continuation`、`remainingContinuation` | [TrainMovement.swift:39](../../Sources/GameCore/Railway/TrainMovement.swift#L39)、[81](../../Sources/GameCore/Railway/TrainMovement.swift#L81) | 方格節點路徑。`rate`、`cursor`、`edges`、`end`、`hasRemainingPath` 仍供路網使用。 |
| `TrainMovement` 方格 `travel`、`isPath` 與 shape／位置驗證 | [TrainMovement.swift:145](../../Sources/GameCore/Railway/TrainMovement.swift#L145)、[245](../../Sources/GameCore/Railway/TrainMovement.swift#L245)、[270](../../Sources/GameCore/Railway/TrainMovement.swift#L270)、[306](../../Sources/GameCore/Railway/TrainMovement.swift#L306) | heading、1024 連結、continuation cursor；[351](../../Sources/GameCore/Railway/TrainMovement.swift#L351)、[367](../../Sources/GameCore/Railway/TrainMovement.swift#L367) 仍讀寫 `continuation`，路網也寫空陣列。 |
| `Train.trail` | [Train.swift:77](../../Sources/GameCore/Railway/Train.swift#L77)、[116](../../Sources/GameCore/Railway/Train.swift#L116)、[266](../../Sources/GameCore/Railway/Train.swift#L266)、[292](../../Sources/GameCore/Railway/Train.swift#L292)、[359](../../Sources/GameCore/Railway/Train.swift#L359) | 方格車身歷史與初始化、codec、驗證；路網使用 `trailEdges`。 |
| `Train.tileCount`、`trailCount`、`distanceBehind`、`isTrail` | [TrainLength.swift:29](../../Sources/GameCore/Railway/TrainLength.swift#L29)、[38](../../Sources/GameCore/Railway/TrainLength.swift#L38)、[54](../../Sources/GameCore/Railway/TrainLength.swift#L54)、[70](../../Sources/GameCore/Railway/TrainLength.swift#L70) | 格數、方格車身 shape。`cars`／`length` 與 `carLength` 在 [14](../../Sources/GameCore/Railway/TrainLength.swift#L14) 是兩種列車共用的物理長度。 |
| `GameWorld.trailBehind`、`isTrailOnTrack`、`trail(after:...)`、方格 `reversed`、`bodyResources` | [TrainLength.swift:104](../../Sources/GameCore/Railway/TrainLength.swift#L104)、[137](../../Sources/GameCore/Railway/TrainLength.swift#L137)、[161](../../Sources/GameCore/Railway/TrainLength.swift#L161)、[179](../../Sources/GameCore/Railway/TrainLength.swift#L179)、[217](../../Sources/GameCore/Railway/TrainLength.swift#L217) | 方格車身放置、跟隨、反向與資源；不是 `RailwayNetworkTrains` 的路網車身實作。 |
| `Station` 方格初始化器、`annexes`、`tiles`、`isConnected` | [Station.swift:35](../../Sources/GameCore/Railway/Station.swift#L35)、[40](../../Sources/GameCore/Railway/Station.swift#L40)、[63](../../Sources/GameCore/Railway/Station.swift#L63)、[76](../../Sources/GameCore/Railway/Station.swift#L76) | 多格車站與相鄰擴建。`position` 在 [30](../../Sources/GameCore/Railway/Station.swift#L30) 也為點車站保留格子投影；`location` 在 [69](../../Sources/GameCore/Railway/Station.swift#L69) 有方格中心 fallback。 |
| `Station` 的 `position/annexes` codec | [Station.swift:105](../../Sources/GameCore/Railway/Station.swift#L105)、[119](../../Sources/GameCore/Railway/Station.swift#L119)、[138](../../Sources/GameCore/Railway/Station.swift#L138) | 方格車站讀寫與相鄰性驗證；`point` 車站仍需保留。 |
| `TileType.station(id:)` | [MapTile.swift:10](../../Sources/GameCore/World/MapTile.swift#L10) | 方格車站佔地。執行期 `TileType` **沒有** `.track/.turnout/.crossing`；那三種 tag 在下述 `SavedMap.Tile`。 |
| `GridMap.neighbor(of:toward:)` | [GridMap.swift:67](../../Sources/GameCore/World/GridMap.swift#L67) | 方格四方向相鄰格；`GridMap` 的尺寸／範圍用途另列 §1.5。 |
| `TrackResource.tile`、`.link(between:and:)` 與 `tile/link` codec | [TrackResources.swift:26](../../Sources/GameCore/Railway/TrackResources.swift#L26)、[31](../../Sources/GameCore/Railway/TrackResources.swift#L31)、[74](../../Sources/GameCore/Railway/TrackResources.swift#L74)、[80](../../Sources/GameCore/Railway/TrackResources.swift#L80)、[98](../../Sources/GameCore/Railway/TrackResources.swift#L98)、[104](../../Sources/GameCore/Railway/TrackResources.swift#L104) | 這是工廠方法／wire tag，**不是** `TrackResource` 的 enum case；實際 case 是共用 `.node/.span`。 |
| `TrackSection`、`nodes`、`links`；私有 `Arc` | [TrackResources.swift:159](../../Sources/GameCore/Railway/TrackResources.swift#L159)、[176](../../Sources/GameCore/Railway/TrackResources.swift#L176)、[357](../../Sources/GameCore/Railway/TrackResources.swift#L357) | 方格支點間的 chain／loop，以及計算平行方格路徑的有向連結。 |
| `LineLeg.route`、`TrackTraversal.tileAhead`、`TrainPlacement.trail` | [LineJourney.swift:46](../../Sources/GameCore/Railway/LineJourney.swift#L46)、[ServicePath.swift:51](../../Sources/GameCore/Railway/ServicePath.swift#L51)、[63](../../Sources/GameCore/Railway/ServicePath.swift#L63) | 共用線路／服務模型裡的方格投影與車身欄位；保留路網 `path/traversals/trailEdges`。 |

### 1.2 方格指令與查詢

目前沒有名為 `layTrack` 的 GameCore 指令；公開指令與 golden wire 名都是 `buildTrack`。內部鋪設是 `RailwayNetwork.lay(_:)`。

| API | 檔案與行號 | 方格規則 |
| --- | --- | --- |
| `buildTrack(at:connections:)` | [GameWorld.swift:145](../../Sources/GameCore/World/GameWorld.swift#L145) | 方向 bit → 空格 → 扣款；允許孤立／懸空出口。 |
| `buildTurnout(at:connections:stem:)`、`isTurnout` | [GameWorld.swift:169](../../Sources/GameCore/World/GameWorld.swift#L169)、[185](../../Sources/GameCore/World/GameWorld.swift#L185) | 三出口以上、stem 是出口，格內 stem 與 branch 通行。 |
| `buildCrossing(at:)` | [GameWorld.swift:198](../../Sources/GameCore/World/GameWorld.swift#L198) | 四出口，只直行的格內平面交叉。 |
| `removeTrack(at:)` | [GameWorld.swift:220](../../Sources/GameCore/World/GameWorld.swift#L220) | 空格／範圍、車頭／車身支撐、tile/link 預約；不退款。 |
| `buildStation(named:at: GridPosition)` | [GameWorld.swift:494](../../Sources/GameCore/World/GameWorld.swift#L494) | 佔一格並扣款，與鐵軌互斥；`PlanPoint` overload [521](../../Sources/GameCore/World/GameWorld.swift#L521) 是自由車站。 |
| `extendStation(_:to:)` | [GameWorld.swift:553](../../Sources/GameCore/World/GameWorld.swift#L553) | 相鄰空格擴建與扣款。 |
| `setTrainContinuation(_:to: [GridPosition])` | [GameWorld.swift:795](../../Sources/GameCore/World/GameWorld.swift#L795) | 方格鄰接、禁止立即折返；路網車只接受空 list 以清除路徑，所以也有路網呼叫用途。 |
| `track(at:)`、`tracks`、`station(at: GridPosition)` | [GameWorld.swift:96](../../Sources/GameCore/World/GameWorld.swift#L96)、[101](../../Sources/GameCore/World/GameWorld.swift#L101)、[109](../../Sources/GameCore/World/GameWorld.swift#L109) | 方格鐵軌投影與佔格車站查詢。 |
| `connectedNeighbors(of:)`、`isConnected(_:to:)`、`exits(from:facing:)`、`canPass` | [TrackConnectivity.swift:25](../../Sources/GameCore/Railway/TrackConnectivity.swift#L25)、[41](../../Sources/GameCore/Railway/TrackConnectivity.swift#L41)、[54](../../Sources/GameCore/Railway/TrackConnectivity.swift#L54)、[66](../../Sources/GameCore/Railway/TrackConnectivity.swift#L66) | 雙方出口相向、N/E/S/W 順序與格內轉向。 |
| `route(from:to: GridPosition)`、方格 `TrainRoute.State/shortest` | [TrainRoute.swift:47](../../Sources/GameCore/Railway/TrainRoute.swift#L47)、[99](../../Sources/GameCore/Railway/TrainRoute.swift#L99)、[115](../../Sources/GameCore/Railway/TrainRoute.swift#L115) | `(格, heading)` 搜尋，等長時 compass 順序。泛用最短路徑／heap 仍供路網使用。 |
| `platforms(of:)`、`platformTracks(of:)` | [StationStop.swift:32](../../Sources/GameCore/Railway/StationStop.swift#L32)、[57](../../Sources/GameCore/Railway/StationStop.swift#L57) | 車站格旁的鐵軌與連續月台格 chain；不是路網 `trackPlatforms(of:)`。 |
| `route(from:toStation:length:)`、`tilesBehind` | [StationStop.swift:110](../../Sources/GameCore/Railway/StationStop.swift#L110)、[133](../../Sources/GameCore/Railway/StationStop.swift#L133) | 格上找站並拉整列車進月台；路網替代查詢為 `path(from:toStation:length:)`。 |
| `trackSections()`、`isBranchPoint` | [TrackResources.swift:256](../../Sources/GameCore/Railway/TrackResources.swift#L256)、[241](../../Sources/GameCore/Railway/TrackResources.swift#L241) | 只掃 `tracks`，以方格的 degree／layout 分 chain 與環。 |
| `parallelTracks(between:and:)`、`lineTrackCounts(_:)` | [TrackResources.swift:309](../../Sources/GameCore/Railway/TrackResources.swift#L309)、[350](../../Sources/GameCore/Railway/TrackResources.swift#L350) | 只計方格月台間不共 link 的路徑；不計路網。 |
| 方格專用錯誤 `tileOccupied`、`invalidTrackConnections`、`noTrackToRemove`、`trackInUse`、`invalidStationTile` | [GameError.swift:12](../../Sources/GameCore/World/GameError.swift#L12)、[15](../../Sources/GameCore/World/GameError.swift#L15)、[22](../../Sources/GameCore/World/GameError.swift#L22)、[25](../../Sources/GameCore/World/GameError.swift#L25)、[107](../../Sources/GameCore/World/GameError.swift#L107) | `outOfBounds(GridPosition)` 在 [10](../../Sources/GameCore/World/GameError.swift#L10) 仍被自由車站使用；`invalidTrainPosition`、`invalidContinuation`、`trackReserved` 等是共用錯誤。 |

### 1.3 共用 API／模擬中仍分流到方格的使用處

| 共用位置 | 方格分支（同檔行號） |
| --- | --- |
| `GameWorld` 列車指令 | `placeTrain` [633](../../Sources/GameCore/World/GameWorld.swift#L633) 建 `trail`；`unplaceTrain` [680](../../Sources/GameCore/World/GameWorld.swift#L680) 清它；`reverseTrain` [714](../../Sources/GameCore/World/GameWorld.swift#L714) 方格反向及清 continuation；`setTrainContinuation(along:)` [854](../../Sources/GameCore/World/GameWorld.swift#L854) 把 link traversals 換成格路徑。 |
| `GameWorld` 服務與移動 | `follow` [2081](../../Sources/GameCore/World/GameWorld.swift#L2081) 寫 continuation；`stand` [2092](../../Sources/GameCore/World/GameWorld.swift#L2092) 寫 trail；`moveTrains` [2288](../../Sources/GameCore/World/GameWorld.swift#L2288) 跟隨方格歷史、清已走完的格路徑；`travelling` [2364](../../Sources/GameCore/World/GameWorld.swift#L2364) 呼叫方格 kernel；`isOnTrack` [2442](../../Sources/GameCore/World/GameWorld.swift#L2442) 驗證 node/link。 |
| `GameWorld` 空格與解碼驗證 | `requireEmptyTile` [2384](../../Sources/GameCore/World/GameWorld.swift#L2384) 同時查土地與方格鐵軌；`invariantViolation` [2764](../../Sources/GameCore/World/GameWorld.swift#L2764) 車站格／土地一致、[2780](../../Sources/GameCore/World/GameWorld.swift#L2780) 軌與站互斥、[2798](../../Sources/GameCore/World/GameWorld.swift#L2798) trail、[2818](../../Sources/GameCore/World/GameWorld.swift#L2818) continuation 範圍；`serviceProblem` [2965](../../Sources/GameCore/World/GameWorld.swift#L2965) 方格終點須在目標站旁。 |
| `RailwayNetworkTrains` 泛用拓撲 adapter | `trackNode` 的 tile 分支 [21](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L21)、`trackEdge` 的 link 分支 [45](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L45)、`trackNodePosition` [65](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L65)、`transitions` [78](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L78)。`trackGeometry` [56](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L56) 由 adapter 得兩格中心線；`trackSpans` [228](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L228) 也接受 link。 |
| `RailwayNetworkTrains` 列車投影 | `pathAhead` [262](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L262) continuation → links；`location` [282](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L282) node/link 世界座標；`vector(of:)` [300](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L300) cardinal 向量；`bodyPath` [335](../../Sources/GameCore/Railway/RailwayNetworkTrains.swift#L335) trail → link 幾何。 |
| `TrackResources` 佔用 | `occupied` [210](../../Sources/GameCore/Railway/TrackResources.swift#L210) 方格 head resource，再併方格 `bodyResources`；`occupiedResources` 與 `occupancyConflicts` 是共用查詢。 |
| `RouteReservation` 預約 | `routeStretches` 的 node/link 分支 [168](../../Sources/GameCore/Railway/RouteReservation.swift#L168)、`stretchFacts` 的 link 分支 [201](../../Sources/GameCore/Railway/RouteReservation.swift#L201)；其餘資源集合與交通控制仍供路網使用。 |
| `StationStop` 停站 | `stationsBesideWholeTrain` [153](../../Sources/GameCore/Railway/StationStop.swift#L153) 的方格月台／trail 分支；`stationsStoppedAt` [206](../../Sources/GameCore/Railway/StationStop.swift#L206) 格中心、四鄰車站與 spent continuation；`isStopped` [227](../../Sources/GameCore/Railway/StationStop.swift#L227) 方格分支。三者均有路網用途。 |
| `TrainRoute` 共用 overload | `route(from:to: TrackNodeID)` [80](../../Sources/GameCore/Railway/TrainRoute.swift#L80) 區分 node 與 tile，把格路徑轉為 traversals。 |
| `ServicePath` | `path` [140](../../Sources/GameCore/Railway/ServicePath.swift#L140) 格路徑／剩餘 link 距離；`turnedRound` [222](../../Sources/GameCore/Railway/ServicePath.swift#L222) 方格車身；`placement(after:)` [242](../../Sources/GameCore/Railway/ServicePath.swift#L242) 方格抵達與 trail。路網 berth 搜尋仍需保留。 |
| `LineJourney` | 搜尋起始位置 [210](../../Sources/GameCore/Railway/LineJourney.swift#L210) 列舉所有方格月台 × cardinal heading，再加路網 berths；其餘行程／環線／時間計算共用。 |
| `TimetableExecution` | `fits` 的 node/link 分支 [75](../../Sources/GameCore/Railway/TimetableExecution.swift#L75)，用 remainingContinuation 判斷到站；路網另用 edges/end。 |

[RailwaySnapshot.swift:77](../../Sources/GameCore/Railway/RailwaySnapshot.swift#L77) 的 `trackAlignment`、[110](../../Sources/GameCore/Railway/RailwaySnapshot.swift#L110) 的 `railwaySnapshot` 與 Passenger 的停站查詢會經由上述泛用 API 讀到方格列車；它們沒有另一份方格權威，也不能因 adapter 移除而整個刪掉。Passenger、Boarding、服務／線路與 Economy 的規則本身多數以站／列車 ID 為準，測試建置資料卻大量使用方格，見 §3。

### 1.4 舊世界序列化橋接

| 位置 | 方格內容 |
| --- | --- |
| `GameWorld.init(from:)` [2499](../../Sources/GameCore/World/GameWorld.swift#L2499)；`encode` [2545](../../Sources/GameCore/World/GameWorld.swift#L2545) | `SavedMap` 解碼出土地與 tracks，前者進 `GridMap`，後者在 [2522](../../Sources/GameCore/World/GameWorld.swift#L2522) 單向 `network.lay`；編碼把兩份權威投影成相容 map。 |
| 私有 `SavedMap.Tile` [2599](../../Sources/GameCore/World/GameWorld.swift#L2599) | `.empty`、`.track(connections:)`、`.station(id:)`、`.turnout(connections:stem:)`、`.crossing`；是保存格式，不是執行期 `TileType`。 |
| `SavedMap` decode [2643](../../Sources/GameCore/World/GameWorld.swift#L2643)、[2662](../../Sources/GameCore/World/GameWorld.swift#L2662)、[2681](../../Sources/GameCore/World/GameWorld.swift#L2681) | 分離土地與方格鐵軌，讀 sparse `occupied` 或 dense `tiles`，拒絕混用、非法 bit、非法 stem、重複／超界格。 |
| `SavedMap` encode [2700](../../Sources/GameCore/World/GameWorld.swift#L2700) | 方格車站與方格 tracks 合成 `occupied`，按格排序，含 turnout/crossing tag。 |
| `SavedGame` [SavedGame.swift:35](../../Sources/GameCore/World/SavedGame.swift#L35)、[73](../../Sources/GameCore/World/SavedGame.swift#L73) | 目前版本 **4**，1–4 全交給 `GameWorld` 解碼；移除橋接會涉及既有世界資料，不代表可以在研究 PR 改版本或 fixture。 |

### 1.5 仍供路網使用，須另定替代方式的格子相關項目

| 項目與證據 | 與「方格鐵路」的區別 |
| --- | --- |
| `GridPosition` [GridPosition.swift:6](../../Sources/GameCore/World/GridPosition.swift#L6)、`GridMap` [GridMap.swift:11](../../Sources/GameCore/World/GridMap.swift#L11)、`MapTile` [MapTile.swift:14](../../Sources/GameCore/World/MapTile.swift#L14) | 地圖尺寸／土地、空格查詢、相容格式與 UI 選取仍用它們。移除方格鐵路不等於已決定如何移除整張 land map。 |
| `GameWorld.map`／初始化 [GameWorld.swift:13](../../Sources/GameCore/World/GameWorld.swift#L13)、[74](../../Sources/GameCore/World/GameWorld.swift#L74)；路網 `isOnMap` [468](../../Sources/GameCore/World/GameWorld.swift#L468) | 路網節點、控制點、點車站的邊界由 `width/height × 1024` 決定；E1 新遊戲也用 `GridMap.maximumSideLength`；E2 實景背景以同一地圖範圍定位，見 §5。 |
| `WorldCoordinate.tileSize`、`init(centreOf:)` [WorldCoordinate.swift:32](../../Sources/GameCore/Geometry/WorldCoordinate.swift#L32)、[52](../../Sources/GameCore/Geometry/WorldCoordinate.swift#L52) | 1024 是座標／範圍／建設成本尺度；`centreOf` 是方格 adapter，也被 Presentation 的格子定位使用。 |
| 路網 `edgeCost` [GameWorld.swift:481](../../Sources/GameCore/World/GameWorld.swift#L481)、`spanLength` [RailwayNetwork.swift:193](../../Sources/GameCore/Railway/RailwayNetwork.swift#L193)、`Train.carLength` [TrainLength.swift:14](../../Sources/GameCore/Railway/TrainLength.swift#L14) | 路網仍以 1024 作成本單位、span 上限與車長；只需解除方格命名依賴，不能憑 F3 改數值。 |
| 點車站 `position` 投影 [Station.swift:56](../../Sources/GameCore/Railway/Station.swift#L56)；`tile(under:)` [GameWorld.swift:534](../../Sources/GameCore/World/GameWorld.swift#L534) | 點車站也有 floor 到格子的 `position`；超界錯誤仍回報格子。 |
| **票價／需求距離** `squaredDistance` [Operations.swift:79](../../Sources/GameCore/Economy/Operations.swift#L79) | 現在讀兩站 `position` 差 × 1024，**不是** `location` 或點的精確距離。路網點車站亦受格子量化影響；換成精確點距離是行為差異，需另評估 golden／需求／經濟。差分同樣做法在 [ReferenceEconomy.swift:82](../../Tests/GameCoreTests/ReferenceEconomy.swift#L82)。 |
| 路網列車放置方向 | GamePresentation 的 `placementHeading: TrackDirection` 仍用於路網 tangent 判斷；App 仍顯示四方向選擇，見 §5。 |

## 2. GoldenScenarios：逐份指令與可改寫性

全部 27 份 JSON 都是 schema **27**。下表的數字是 `steps` 中的**指令出現次數，含被拒絕的指令**，不是成功建成的數量；`placeTrain(node/link)` 是 fixture 的 position `type`，對應 Core `atNode/onLink`。沒有列入的 `purchaseTrain`、`reverseTrain`、`unplaceTrain`、rate、timetable、線路、乘客、經濟與時鐘指令本身是共用的，但當世界／列車在方格上時仍走 §1 的方格分支。

「可以」表示規則可在現有路網 API 上重新表達，**不表示只改 command 名就能保留所有 expected 值**。`node/link` 與 `edge` 位置、ID、tracks／network final state、建設費用、月台停點、車身與路程都可能需要作者重新手算與 review。方格每格花一次軌道費；路網按邊長進位收費，兩者也不能自動視為相等。

路網改寫通常使用 `buildTrackNode`、`buildTrackEdge`、`buildStationAt`、`addTrackPlatform`、`placeTrain(edge)`、`setTrainPath`，以及 `pathToNode/pathToStation/transitions` 觀察。方格的 90° 轉彎不能直接換成兩條直線邊接一個角：路網依切線決定可通行，需設計曲線／接點；同長路徑平手在路網按邊序，方格則按 N/E/S/W。以下逐份判斷只描述未來工作，本次不改 fixture。

| Fixture | 方格指令（次數） | 規則與只用路網改寫的判斷 |
| --- | --- | --- |
| [boarding.json](../../GoldenScenarios/boarding.json) | `buildTrack` × 7、`buildStation` × 3、`placeTrain(node)` × 1 | 可以：上下車順序、容量、拒載、棄乘、守恆與 dwell 可用等距路網月台／同一線路重建；須核對每段距離、班表與經濟建設餘額。 |
| [build-starter-line.json](../../GoldenScenarios/build-starter-line.json) | `buildStation` × 10、`buildTrack` × 10、`removeTrack` × 4 | 部分可以：資金、空白名稱、ID 與拒絕原子性可重寫；格子佔用、空出口 bit、格座標越界、拆非軌格與檢查順序是方格 API 契約，不能只換路網指令保留。 |
| [clock-seconds.json](../../GoldenScenarios/clock-seconds.json) | `buildTrack` × 6、`placeTrain(node)` × 1、`setTrainContinuation` × 1 | 可以：tick 十分之一秒餘數、各速度、逐秒分配 1300 單位可換等長路網；車頭與 cursor 觀察須改 edge 表示。 |
| [clock-speed-and-pause.json](../../GoldenScenarios/clock-speed-and-pause.json) | 無 | 已無方格指令：只驗證速度、pause/resume 與時間；initial map 尺寸／空 tracks final summary 仍來自共用 schema。 |
| [continuous-track.json](../../GoldenScenarios/continuous-track.json) | 無 | 已無方格指令：連續幾何、長度、切線轉向、span、車身、反向與拆軌拒絕都在路網；1024 距離單位不是方格鐵軌。 |
| [economy.json](../../GoldenScenarios/economy.json) | `buildTrack` × 7、`buildStation` × 3、`placeTrain(node)` × 1 | 可以：票價級距／需求因子、上車收費與整點／午夜帳本可用等距路網重建；目前票價採站 position 格差，改點距離不能默認 expected 不變。 |
| [free-station.json](../../GoldenScenarios/free-station.json) | `buildTrack` × 2、`buildStation` × 1、`extendStation` × 1 | 部分可以：點車站名稱、範圍、成本、路網月台與停站保留；與格軌重疊、拒建方格站、沒有方格月台、拒格擴建是相容層交互契約，移除後不能原樣表達。 |
| [line-dispatch.json](../../GoldenScenarios/line-dispatch.json) | `buildTrack` × 7、`buildStation` × 5、`placeTrain(node)` × 3 | 可以：派車 ID 順序、班距、window、ready 條件、列車歸屬與服務完成可用路網 berths；須重算行程與位置觀察。 |
| [line-patterns.json](../../GoldenScenarios/line-patterns.json) | `buildTrack` × 9、`buildStation` × 4、`placeTrain(node)` × 2 | 可以：short working／express、區段容量分配、pattern 索引與派車可用路網；維持 stops、路程與服務時間後重核 expected。 |
| [network-service.json](../../GoldenScenarios/network-service.json) | `buildStation` × 2 | 可以：行駛已是路網，兩個 buildStation 換 buildStationAt；月台、timetable、repeat、車身停靠與路徑規則不需要格站，需改站 final summary。 |
| [ring-line.json](../../GoldenScenarios/ring-line.json) | `buildTrack` × 12、`buildStation` × 4、`placeTrain(node)` × 2 | 可以：環線整圈、雙方向派車、偶數車數、無終點 dwell 與 passenger 方向可用連續環路；格角須改曲線／切線相接，圈長與 timetable 重新手算。 |
| [service-line.json](../../GoldenScenarios/service-line.json) | `buildTrack` × 7、`buildStation` × 5、`removeTrack` × 1 | 可以：stops/window/level/headway、行程與移除軌道後查詢可換路網；格子 route 觀察與規劃距離／時間須改。 |
| [service-run.json](../../GoldenScenarios/service-run.json) | `buildTrack` × 7、`buildStation` × 3、`placeTrain(node)` × 1 | 可以：running curve、秒級位置、late run、performance 與線路計畫可用等距路網；改 edge 位置、stand/end 與距離觀察。 |
| [station-demand.json](../../GoldenScenarios/station-demand.json) | `buildStation` × 3 | 可以：只用三座方格站的 ID，需求曲線、旅次、釋出餘數、候車／溢出與守恆不需鐵軌；改 buildStationAt 即可承接規則及站 summary。 |
| [station-dwell.json](../../GoldenScenarios/station-dwell.json) | `buildTrack` × 7、`buildStation` × 3、`placeTrain(node)` × 1 | 可以：開門／關門、最低停站秒數、lateness 與 execution 可用同距離路網月台；需以 path end 表達停住。 |
| [station-facilities.json](../../GoldenScenarios/station-facilities.json) | `buildTrack` × 11、`buildStation` × 2、`extendStation` × 7、`placeTrain(node)` × 3、`removeTrack` × 1、`setTrainContinuation` × 3 | 部分可以：車長、整列車進月台、反向車身、佔用／拆軌拒絕可用路網；相鄰格擴站、扣一格站費、格月台 chain／一車一格的條件不能只換指令保留。 |
| [station-stop.json](../../GoldenScenarios/station-stop.json) | `buildTrack` × 6、`buildStation` × 6、`placeTrain(node)` × 2、`setTrainContinuation` × 2、`removeTrack` × 1 | 部分可以：有月台才找得到站、停車與全車靠站可改路網平台；四鄰格自動成月台、站格不是軌、heading 下的格 route、拆鄰軌立即失去月台均是方格契約。 |
| [track-connectivity.json](../../GoldenScenarios/track-connectivity.json) | `buildTrack` × 7、`removeTrack` × 2、`buildStation` × 1 | 不能完整只換：雙方出口 bit、懸空出口、N/E/S/W 查詢順序、一格／對角／站格不相接是方格規則；路網可另驗證相接拓撲，但它是不同契約。 |
| [track-resources.json](../../GoldenScenarios/track-resources.json) | `buildTrack` × 21、`buildTurnout` × 4、`buildCrossing` × 2、`buildStation` × 4、`placeTrain(node)` × 3、`placeTrain(link)` × 2、`setTrainContinuation` × 2 | 不能完整只換：格內 stem／crossing、heading、TrackSection 與格 parallelTracks 沒有同形的路網 API；轉向、資源佔用、衝突可另寫路網情境，不能保留整份規則。 |
| [traffic-reservation.json](../../GoldenScenarios/traffic-reservation.json) | `buildStation` × 3 | 可以：行駛與預約已是路網，三座 buildStation 改成點站；junction zone、span、全路徑原子預約、等待／釋放、flyover 與禁止改已預約邊等規則可保留。 |
| [train-movement.json](../../GoldenScenarios/train-movement.json) | `buildTrack` × 12、`buildStation` × 1、`setTrainContinuation` × 11、`placeTrain(link)` × 2、`removeTrack` × 2 | 部分可以：距離預算、rate/pause、批次推進、反向／unplace 清路徑可用路網；拆格軌後同格重建會沿舊 continuation 恢復，路網邊 ID 永不重用，不能只換 remove/buildEdge 取得同一規則。 |
| [train-position.json](../../GoldenScenarios/train-position.json) | `buildTrack` × 8、`buildStation` × 1、`placeTrain(node)` × 10、`placeTrain(link)` × 10、`removeTrack` × 10 | 不能完整只換：孤立格 node 任意 heading、link offset 嚴格 0<offset<1024、node/link 唯一表示與兩端格支撐是方格契約；路網端點允許 offset 0 或 length，反向／放置原子性可另驗證。 |
| [train-repeat.json](../../GoldenScenarios/train-repeat.json) | `buildTrack` × 7、`buildStation` × 3、`placeTrain(node)` × 2 | 可以：reverses、週期／cycle、排程驗證與晚開始的 cycle 選擇可用等距路網；車身反向／停點的 edge 表示與跑程須核對。 |
| [train-route.json](../../GoldenScenarios/train-route.json) | `buildTrack` × 11、`buildStation` × 1、`placeTrain(node)` × 2、`setTrainContinuation` × 3 | 部分可以：最短路、不立即折返、不可達、純查詢與跟隨可用路網；目的格、heading dead end、格前方節點的空路徑與 N/E/S/W 平手不能只換指令保留。 |
| [train-service.json](../../GoldenScenarios/train-service.json) | `buildTrack` × 7、`buildStation` × 5、`placeTrain(node)` × 2、`setTrainContinuation` × 2 | 可以承接服務規則：start/stop 檢查順序、dwell/departure/arrival、重複站、手動指令鎖定、rate 可改與無路等待可用路網；共享格月台與後建格軌改為明確路網月台／路徑，位置及 expected 重核。 |
| [train-timetable.json](../../GoldenScenarios/train-timetable.json) | `buildTrack` × 5、`buildStation` × 3、`placeTrain(node)` × 2、`setTrainContinuation` × 1 | 可以：時間有序、清空／取代、未知站、免費／不自動移動、在 reverse/unplace 後保留都不需要方格；改點站、edge 放置與 setTrainPath。 |
| [vertical-railway.json](../../GoldenScenarios/vertical-railway.json) | `buildStation` × 1 | 可以：行駛與幾何已是路網，只把 Deep 的 buildStation 換點站；縱坡／結構／淨空、平台切 span、車身與高度不需要方格站。 |


Golden 執行器本身也要遷移：`ScenarioCommand` 的格軌／站／列車路徑 case 在 [GoldenScenario.swift:425](../../Tests/GameCoreTests/GoldenScenario.swift#L425)，`apply` 在 [476](../../Tests/GameCoreTests/GoldenScenario.swift#L476)；方格觀察 `connectedNeighbors/isConnected/exits/route/platforms/routeToStation/platformTracks/trackSections/parallelTracks` 在 [1056](../../Tests/GameCoreTests/GoldenScenario.swift#L1056)。最終摘要保留方格 `StationSummary/TrackSummary` [1634](../../Tests/GameCoreTests/GoldenScenario.swift#L1634)、[1692](../../Tests/GameCoreTests/GoldenScenario.swift#L1692)，方向與位置／movement summary 在 [2465](../../Tests/GameCoreTests/GoldenScenario.swift#L2465)、[2533](../../Tests/GameCoreTests/GoldenScenario.swift#L2533)、[2616](../../Tests/GameCoreTests/GoldenScenario.swift#L2616)，資源的 tile/link summary 在 [3115](../../Tests/GameCoreTests/GoldenScenario.swift#L3115)。即使兩份無方格的情境，也仍經過這份共用 schema／摘要程式。

## 3. Tests/GameCoreTests

### 3.1 單元、回歸與 golden 測試類別

下表列依賴方格的測試類別，或有方格特定子測試的混合類別；行號指建置世界的 helper 或直接驗證處，不代表整個類別只能測方格。Property／差分／mutation 類別另列 §3.2，並非遺漏。

| 測試類別／證據 | 方格依賴與 F3 影響 |
| --- | --- |
| [TrackConstructionTests:5](../../Tests/GameCoreTests/TrackConstructionTests.swift#L5) | 格軌 bit、空格／範圍／成本與拆軌，主要就是相容 API 契約。 |
| [TrackConnectivityTests:11](../../Tests/GameCoreTests/TrackConnectivityTests.swift#L11) | 四鄰相接、方向順序、dangling 出口、拆建與快照／極端座標。 |
| [TrainPositionTests:12](../../Tests/GameCoreTests/TrainPositionTests.swift#L12) | 格 node/link placement、canonical offset、反向、拆軌支撐與 malformed save。 |
| [TrainMovementTests:19](../../Tests/GameCoreTests/TrainMovementTests.swift#L19) | 格 continuation、cursor、預算、拆軌等待／原格重建恢復、rate／tick partition、存檔。 |
| [TrainRouteTests:18](../../Tests/GameCoreTests/TrainRouteTests.swift#L18) | 目的格、heading、最短格路徑、compass 平手、pure query 與存檔。 |
| [StationAndTrainTests:7](../../Tests/GameCoreTests/StationAndTrainTests.swift#L7) | 方格站建置、土地對應、佔格、拒絕原子性／車站 ID；purchase 部分共用。 |
| [StationStopTests:23](../../Tests/GameCoreTests/StationStopTests.swift#L23) | 四鄰格月台、格站 route／停站；另內含 stationStop.routes property（543 行）。 |
| [TrainTimetableTests:22](../../Tests/GameCoreTests/TrainTimetableTests.swift#L22) | 格線與格站 helper；timetable 驗證、慣性、控制後保留的規則可改路網。 |
| [TrainServiceTests:34](../../Tests/GameCoreTests/TrainServiceTests.swift#L34) | 格月台、node/link 位置、服務下的 continuation 與共享月台。 |
| [TrainRepeatTests:29](../../Tests/GameCoreTests/TrainRepeatTests.swift#L29) | 格線／月台上反向、重複週期、cycle 與巨量 advance。 |
| [ServiceLineTests:31](../../Tests/GameCoreTests/ServiceLineTests.swift#L31) | 格線／站上算 line journey、跑程、班距與可達性。 |
| [LineDispatchTests:28](../../Tests/GameCoreTests/LineDispatchTests.swift#L28) | 格線、heading、派車 ready 與 timetable／位置斷言。 |
| [LinePatternTests:25](../../Tests/GameCoreTests/LinePatternTests.swift#L25) | 格線／站上 short working、express、區段負載與派車。 |
| [TrackResourceTests:25](../../Tests/GameCoreTests/TrackResourceTests.swift#L25) | 方格 turnout/crossing、資源、chain／loop section 與 parallelTracks。 |
| [StationFacilityTests:19](../../Tests/GameCoreTests/StationFacilityTests.swift#L19) | 多格擴站、格月台 chain、一車一格、trail／反向與全車停站。 |
| [RingLineTests:46](../../Tests/GameCoreTests/RingLineTests.swift#L46) | 環線 helper 建格軌、格站，78 行放 atNode；所有 ring 計畫／派車／乘客／存檔測試均以此為世界。 |
| [ServiceDwellTests:21](../../Tests/GameCoreTests/ServiceDwellTests.swift#L21) | 秒級 dwell／lateness 測試的格線、格站與格位置；不是純 StationDwell 計算。 |
| [ServiceRunTests:25](../../Tests/GameCoreTests/ServiceRunTests.swift#L25) | 行駛曲線與 lateness 測試仍建格線、格站，預期車頭是 node/link。 |
| [PassengerDemandTests:19](../../Tests/GameCoreTests/PassengerDemandTests.swift#L19) | 三座格站的 ID；需求、釋出、守恆規則可換點站，沒有必要格軌。 |
| [BoardingTests:38](../../Tests/GameCoreTests/BoardingTests.swift#L38) | 上／下車 helper 的格軌、格站、atNode；守恆與容量規則可換路網。 |
| [EconomyAccountsTests:29](../../Tests/GameCoreTests/EconomyAccountsTests.swift#L29) | 格線營運、格站距離、建設餘額、整點／日帳本與報表。 |
| [CarPriceTests（EconomyTests.swift）:72](../../Tests/GameCoreTests/EconomyTests.swift#L72) | 負餘額 helper 建格站／線路以結算，供 testFreeCarsAreAddedEvenWithANegativeBalance 與 testPricedCarsAreStillRefusedWithANegativeBalance 使用；其他車廂價格測試只需未放置列車。EconomyTests 本身不依賴方格鐵路。 |
| [IDAllocationTests:43](../../Tests/GameCoreTests/IDAllocationTests.swift#L43) | 格軌／格站 helper、ID 上限的保存 JSON、名字→格→ID→資金檢查順序。 |
| [PersistenceAndDeterminismTests:9](../../Tests/GameCoreTests/PersistenceAndDeterminismTests.swift#L9) | 建格線／站、dense map、站與格不一致、ID 延續與同操作同編碼；成本／clock malformed tests 是共用。 |
| [RailwayNetworkAuthorityTests:38](../../Tests/GameCoreTests/RailwayNetworkAuthorityTests.swift#L38) | 方格鐵軌的唯一權威、土地互斥、舊 map codec、grid link 一個 span 與兩類 pathAhead；路網 span 子測試保留。 |
| [ContinuousTrackTests:191](../../Tests/GameCoreTests/ContinuousTrackTests.swift#L191) | 拒 tile/link 作 network ID；357 行的方格 adapter；629 行 grid-only save／舊讀檔；renderer 子測試含格位置。幾何與路網移動主體可保留。 |
| [VerticalRailwayTests:426](../../Tests/GameCoreTests/VerticalRailwayTests.swift#L426) | Hub/Annex 等用格站建立路網月台；466 行拒 grid link 為 platform 邊。縱斷面／淨空主體不需格軌。 |
| [NetworkServiceTests:62](../../Tests/GameCoreTests/NetworkServiceTests.swift#L62) | 路網營運 helper 仍建方格站；另有格／路網隔離斷言，不能把全類視為已脫離方格。 |
| [TrafficControlTests:17](../../Tests/GameCoreTests/TrafficControlTests.swift#L17) | 混合：格軌預約／支撐與路網 junction-zone／span／服務；格資源 helper 從 21 行開始。 |
| [FreeStationTests:13](../../Tests/GameCoreTests/FreeStationTests.swift#L13) | 點站與格軌／格站相容交互、拒格擴建、格投影／outOfBounds；純點站／路網月台部分保留。 |
| [SavedGameTests:20](../../Tests/GameCoreTests/SavedGameTests.swift#L20) | 自造 mixed 世界含格站；[65](../../Tests/GameCoreTests/SavedGameTests.swift#L65) 注入舊 dense map 的格軌，[83](../../Tests/GameCoreTests/SavedGameTests.swift#L83) 大地圖格站，[89](../../Tests/GameCoreTests/SavedGameTests.swift#L89) sparse map mutation。[135](../../Tests/GameCoreTests/SavedGameTests.swift#L135) 起的四份 committed fixture 本身無格站／軌。 |
| [GoldenScenarioTests:138](../../Tests/GameCoreTests/GoldenScenarioTests.swift#L138) | 跑全部 golden，並故意變更 annexes／trail／continuation、格 direction／resource 等摘要以驗證 mismatch；須隨 schema 使用評估。 |
| [ReferenceWorldGoldenTests:10](../../Tests/GameCoreTests/ReferenceWorldGoldenTests.swift#L10) | 在差分 reference 上跑全部 golden，40 行起比對格站／軌摘要，105 行起 apply 方格指令；不只驗證 Core。 |

`GridMapTests` [GridMapTests.swift:4](../../Tests/GameCoreTests/GridMapTests.swift#L4) 驗證尺寸、格查詢、bounds、row-major 與 Codable，屬於 §1.5 的土地／邊界，不能直接當成方格鐵路測試刪除。沒有方格鐵路／方格站建置依賴的類別是 `GameClockTests`、`EconomyTests`、`StationDwellTests`、`RunningCurveTests`、`WideIntegerTests`、[GeoAnchorTests:9](../../Tests/GameCoreTests/GeoAnchorTests.swift#L9)；它們的數值單位或空世界不等於使用方格軌道。`CarPriceTests` 是同一個 EconomyTests.swift 檔中的另一個類別，已個別列出。

### 3.2 Property、差分與 campaign

Campaign 名稱照程式中的 `runCampaign` 字串，方便在 `PROPERTY_REPLAY=<suite>@<seed>@<case>` 回查。下表同一列多個名稱屬於同一測試類別；不是只以檔名含 Property 判斷。

| 類別／campaign 證據 | Campaign | 方格依賴 |
| --- | --- | --- |
| [TopologyPropertyTests:32](../../Tests/GameCoreTests/TopologyPropertyTests.swift#L32) | `topology.linkRule、topology.buildOrder、topology.components、topology.masks` | NetworkGenerator 格軌／站；對稱四鄰規則、順序、component 與 bitmask。 |
| [TrainPositionPropertyTests:40](../../Tests/GameCoreTests/TrainPositionPropertyTests.swift#L40) | `position.valid、position.invalid、position.reverse、position.codable、position.trackInUse` | PositionGenerator 的 node/link、格支撐與 offset；全為方格。 |
| [MovementPropertyTests:58](../../Tests/GameCoreTests/MovementPropertyTests.swift#L58) | `movement.reference、movement.hugeRate、movement.tickPartition、movement.distancePartition、movement.zero、movement.determinism.\(run)` | 格 walk 與逐單位 ReferenceMovement；批次／距離分割、巨大 rate、保存 determinism。 |
| [RoutePropertyTests:66](../../Tests/GameCoreTests/RoutePropertyTests.swift#L66) | `route.reference、route.reachability、route.tieBreak、route.consumable、route.readOnly、route.buildOrder` | 格 generator 與 ReferenceRoute；heading、compass 平手、路徑可消耗。 |
| [RouteMovementPropertyTests:54](../../Tests/GameCoreTests/RouteMovementPropertyTests.swift#L54) | `composition.follow、composition.staleRoute、composition.waitAndResume` | 格找路→commit→移動與拆格軌／重建恢復的 composition。 |
| [WorldStateMachineTests:177](../../Tests/GameCoreTests/WorldStateMachineTests.swift#L177) | `stateMachine.world、stateMachine.replay` | Operation 17–24 行含格 continuation、routeAndCommit、建拆軌／站；WorldInvariants／重播 digest。 |
| [IDAllocationPropertyTests:37](../../Tests/GameCoreTests/IDAllocationPropertyTests.swift#L37) | `ids.allocation` | 39–42 行建格軌／站，格上的 allocation、末端 ID 與拒絕原子性。 |
| [StationStopTests:543](../../Tests/GameCoreTests/StationStopTests.swift#L543) | `stationStop.routes` | 普通單元類別內的 property：格月台 route 等價與停站。 |
| [KernelDifferentialTests:759](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L759) | `kernel.differential、kernel.replay` | 基礎格世界，格 Operation、雙 model apply、每一步 grid/position/route 差異與 shrinker／digest。 |
| [TimetablePropertyTests:71](../../Tests/GameCoreTests/TimetablePropertyTests.swift#L71) | `timetable.differential、timetable.replay、timetable.generator` | 沿 Kernel Setup／Operation，格軌／站／位置；擴 timetable operation。 |
| [ServicePropertyTests:147](../../Tests/GameCoreTests/ServicePropertyTests.swift#L147) | `service.differential、service.repeating、service.replay` | 沿 Kernel makeSetup，scriptedService 選方格 platforms × heading，與格 reference 的服務／repeat 比較。 |
| [ServiceLinePropertyTests:124](../../Tests/GameCoreTests/ServiceLinePropertyTests.swift#L124) | `line.differential` | 27 行 generator 沿 Kernel 格世界，新增線路／level／window 指令。 |
| [LineDispatchPropertyTests:236](../../Tests/GameCoreTests/LineDispatchPropertyTests.swift#L236) | `line.dispatch、dispatch.replay` | 35 行格形狀 Setup，72–84 行用格月台與 heading 選 ready 位置；含 ring 設定。 |
| [LinePatternPropertyTests:182](../../Tests/GameCoreTests/LinePatternPropertyTests.swift#L182) | `line.patterns` | 30 行 Kernel 格世界，68–78 行格月台與 routes 決定 stops／pattern。 |
| [TrackResourcePropertyTests:161](../../Tests/GameCoreTests/TrackResourcePropertyTests.swift#L161) | `track.resources` | Kernel 格世界 + turnout/crossing；轉向表、tile/link 佔用、section／parallelTracks。 |
| [StationFacilityPropertyTests:171](../../Tests/GameCoreTests/StationFacilityPropertyTests.swift#L171) | `station.facilities` | Kernel 格世界 + extendStation/cars／全車進格月台；ReferenceTrainLength。 |
| [PassengerPropertyTests:172](../../Tests/GameCoreTests/PassengerPropertyTests.swift#L172) | `passenger.differential` | begin 在51行給每站 GridPosition，Core／reference 均建格站；乘客演算法與時段數值可保留。 |
| [BoardingPropertyTests:152](../../Tests/GameCoreTests/BoardingPropertyTests.swift#L152) | `boarding.differential` | 31 行 Kernel 格 Setup，served stations 依 platforms(of:)；沿 LineDispatch generator。 |
| [EconomyPropertyTests:86](../../Tests/GameCoreTests/EconomyPropertyTests.swift#L86) | `economy.differential` | 27 行 generator 沿 BoardingPropertyTests，因此即使此檔沒出現 GridPosition，仍是格站／軌的差分世界。 |
| [TrafficControlPropertyTests:624](../../Tests/GameCoreTests/TrafficControlPropertyTests.swift#L624) | `traffic.reservation` | beginGrid 71 行／beginNetwork 112 行分兩路，gridPath/build/removeTrack operation；路網路徑仍用格站。需保留路網 campaign 的對照能力。 |
| [VerticalRailwayPropertyTests:372](../../Tests/GameCoreTests/VerticalRailwayPropertyTests.swift#L372) | `vertical.differential` | 路網幾何／車輛本身無格軌，351、380–381 行建格站給路網月台；改點站仍需同步獨立模型。 |
| [NetworkServicePropertyTests:526](../../Tests/GameCoreTests/NetworkServicePropertyTests.swift#L526) | `service.network` | 路網營運，但 begin 481–482 行雙方建格站；屬站建置依賴，不是格 movement。 |
| [ContinuousTrackPropertyTests:300](../../Tests/GameCoreTests/ContinuousTrackPropertyTests.swift#L300) | `network.differential` | 沒有格軌／格站建置依賴，生成路網與 onEdge；仍呼叫共用 reference／WorldInvariants、存讀與摘要支援，不能刪除其路網驗證。 |

**SaveMutationTests 的 16 個 campaign 必須逐一區分**，不能把所有 save 測試當成 SaveFixtures 的存檔內容：

| Campaign／行號 | 建置世界的依賴 |
| --- | --- |
| [save.mutation:122](../../Tests/GameCoreTests/SaveMutationTests.swift#L122) | KernelDifferentialTests.generate：方格世界，mutation 涵蓋格 map、車頭與 continuation。 |
| [save.timetableMutation:192](../../Tests/GameCoreTests/SaveMutationTests.swift#L192) | TimetablePropertyTests.generate：方格建置與 timetable。 |
| [save.serviceMutation:278](../../Tests/GameCoreTests/SaveMutationTests.swift#L278) | ServicePropertyTests.generate：方格營運。 |
| [save.repeatMutation:379](../../Tests/GameCoreTests/SaveMutationTests.swift#L379) | ServicePropertyTests.generate(repeating:)：方格重複服務。 |
| [save.lineMutation:486](../../Tests/GameCoreTests/SaveMutationTests.swift#L486) | ServiceLinePropertyTests.generate：方格線路。 |
| [save.dispatchMutation:566](../../Tests/GameCoreTests/SaveMutationTests.swift#L566) | LineDispatchPropertyTests.generate：方格派車。 |
| [save.patternMutation:645](../../Tests/GameCoreTests/SaveMutationTests.swift#L645) | LinePatternPropertyTests.generate：方格 pattern。 |
| [save.trackMutation:724](../../Tests/GameCoreTests/SaveMutationTests.swift#L724) | TrackResourcePropertyTests.generate：turnout/crossing、方格 resources。 |
| [save.facilityMutation:802](../../Tests/GameCoreTests/SaveMutationTests.swift#L802) | StationFacilityPropertyTests.generate：annexes、方格 trail／格月台。 |
| [save.networkMutation:878](../../Tests/GameCoreTests/SaveMutationTests.swift#L878) | ContinuousTrackPropertyTests.generateWorld：無必要格建置；仍突變 trail 等相容 key、呼叫共用 invariants。 |
| [save.verticalMutation:953](../../Tests/GameCoreTests/SaveMutationTests.swift#L953) | VerticalRailwayPropertyTests.generateWorld：路網與方格站。 |
| [save.networkServiceMutation:1031](../../Tests/GameCoreTests/SaveMutationTests.swift#L1031) | NetworkServicePropertyTests.generateWorld：路網營運與方格站。 |
| [save.trafficMutation:1111](../../Tests/GameCoreTests/SaveMutationTests.swift#L1111) | TrafficControlPropertyTests.generateWorld：方格／路網兩種，保留 grid flag。 |
| [save.passengerMutation:1188](../../Tests/GameCoreTests/SaveMutationTests.swift#L1188) | PassengerPropertyTests.generateWorld：方格站。 |
| [save.riderMutation:1257](../../Tests/GameCoreTests/SaveMutationTests.swift#L1257) | BoardingPropertyTests.generateWorld：方格軌／站／營運。 |
| [save.accountsMutation:1333](../../Tests/GameCoreTests/SaveMutationTests.swift#L1333) | EconomyPropertyTests.generateWorld：間接沿 Boarding 的方格世界。 |

### 3.3 共用測試支援與差分接線

| 檔案與行號 | 方格部分 |
| --- | --- |
| [PropertySupport.swift:207](../../Tests/GameCoreTests/PropertySupport.swift#L207)、[218](../../Tests/GameCoreTests/PropertySupport.swift#L218)、[228](../../Tests/GameCoreTests/PropertySupport.swift#L228) | 全域 stepDirection、step 與 ahead(of:)：reference 自己的格方向／步進／前方節點 helper。 |
| [PropertySupport.swift:245](../../Tests/GameCoreTests/PropertySupport.swift#L245)、[291](../../Tests/GameCoreTests/PropertySupport.swift#L291) | `TileSpec`、`NetworkShape`、`NetworkGenerator` 的名稱雖叫 network，生成的是方格 line/grid/ladder/loop、出口 mask 與格站，build 用 `buildTrack/buildStation`。 |
| [PropertySupport.swift:456](../../Tests/GameCoreTests/PropertySupport.swift#L456)、[497](../../Tests/GameCoreTests/PropertySupport.swift#L497)、[564](../../Tests/GameCoreTests/PropertySupport.swift#L564) | `PositionGenerator` 生成方格 node/link／walk；`ReferenceMovement` 逐單位走格；`ReferenceRoute` 使用格與方向的獨立搜尋。 |
| [PropertySupport.swift:625](../../Tests/GameCoreTests/PropertySupport.swift#L625)、[994](../../Tests/GameCoreTests/PropertySupport.swift#L994)、[1057](../../Tests/GameCoreTests/PropertySupport.swift#L1057) | `WorldInvariants` 的格站／土地、方格 tracks、grid movement、body／service 分支；Passenger／Economy／路網 invariants 是共用，需保留。 |
| [NetworkSupport.swift:30](../../Tests/GameCoreTests/NetworkSupport.swift#L30) | `TrackResource.wholeLink` 是測試／reference 用的方格 span 工廠；同檔 `NetworkInvariants` 大部分是路網，不能整檔刪除。 |
| [KernelDifferentialTests.swift:22](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L22)、[145](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L145)、[165](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L165)、[207](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L207) | 方格 Operation、Setup specs、雙方 build 與格生成；格指令含 build/removeTrack、buildStation、setContinuation、sendToTile、sendToStation／sendWholeTrainToStation、turnout/crossing、extendStation。 |
| [KernelDifferentialTests.swift:330](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L330)、[398](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L398)、[464](../../Tests/GameCoreTests/KernelDifferentialTests.swift#L464) | Core／Reference 的 apply、逐格土地／track、站 annexes、train trail／continuation、連通／月台／route 比較；`firstFailure`／shrinker 與 replay 也沿這些 Operation。點站 point 比較不等於 generator 已生成點站。 |
| [ReferenceWorldGoldenTests.swift:40](../../Tests/GameCoreTests/ReferenceWorldGoldenTests.swift#L40)、[105](../../Tests/GameCoreTests/ReferenceWorldGoldenTests.swift#L105)、[156](../../Tests/GameCoreTests/ReferenceWorldGoldenTests.swift#L156) | Reference 的 golden 摘要、格 command apply 與格 observation answer；與 §2 的 fixture/schema 同步評估。 |

### 3.4 ReferenceWorld.swift 裡的方格模型

這是獨立規則模型，不是 GameCore adapter 的轉呼叫。F3 若需要遷移它，由擁有此範圍的代理另做；本次只列位置。

| 行號 | 方格資料／規則 |
| --- | --- |
| [45](../../Tests/GameCoreTests/ReferenceWorld.swift#L45)、[53](../../Tests/GameCoreTests/ReferenceWorld.swift#L53)、[70](../../Tests/GameCoreTests/ReferenceWorld.swift#L70) | `Tile.track/station/turnout/crossing`；Station `position/annexes/tiles`；Train 的 `continuation/trail`（與路網 edges/trailEdges 並存）。 |
| [249](../../Tests/GameCoreTests/ReferenceWorld.swift#L249) | 獨立 `linkLength = 1024`（共用車長／世界單位須另保留），不能以 reference 沿用此值推論它已脫離格軌。 |
| [136](../../Tests/GameCoreTests/ReferenceWorld.swift#L136)、[181](../../Tests/GameCoreTests/ReferenceWorld.swift#L181)、[271](../../Tests/GameCoreTests/ReferenceWorld.swift#L271) | 方格字典 `tiles`、`RouteMemo.grid`、世界 equality。 |
| [285](../../Tests/GameCoreTests/ReferenceWorld.swift#L285)、[290](../../Tests/GameCoreTests/ReferenceWorld.swift#L290)、[299](../../Tests/GameCoreTests/ReferenceWorld.swift#L299) | `inMap`、bit 對應與 mask 查詢。 |
| [311](../../Tests/GameCoreTests/ReferenceWorld.swift#L311)、[326](../../Tests/GameCoreTests/ReferenceWorld.swift#L326)、[334](../../Tests/GameCoreTests/ReferenceWorld.swift#L334)、[339](../../Tests/GameCoreTests/ReferenceWorld.swift#L339)、[344](../../Tests/GameCoreTests/ReferenceWorld.swift#L344) | 獨立 allowed-turns 表、heading/no-U-turn、雙方出口相接、N/E/S/W neighbors、node/link 的 isOnTrack。 |
| [359](../../Tests/GameCoreTests/ReferenceWorld.swift#L359)、[371](../../Tests/GameCoreTests/ReferenceWorld.swift#L371)、[375](../../Tests/GameCoreTests/ReferenceWorld.swift#L375) | 格月台、站旁格查詢與 atNode + spent continuation 停站；路網 networkStops 是另一分支。 |
| [393](../../Tests/GameCoreTests/ReferenceWorld.swift#L393)、[402](../../Tests/GameCoreTests/ReferenceWorld.swift#L402)、[411](../../Tests/GameCoreTests/ReferenceWorld.swift#L411)、[421](../../Tests/GameCoreTests/ReferenceWorld.swift#L421)、[428](../../Tests/GameCoreTests/ReferenceWorld.swift#L428) | requireEmpty、建格軌／turnout／crossing、拆格軌、支撐與預約拒絕。 |
| [447](../../Tests/GameCoreTests/ReferenceWorld.swift#L447)、[478](../../Tests/GameCoreTests/ReferenceWorld.swift#L478) | 建格站與相鄰擴站；[462](../../Tests/GameCoreTests/ReferenceWorld.swift#L462) 是點站 overload，仍作格投影／錯誤回報。 |
| [535](../../Tests/GameCoreTests/ReferenceWorld.swift#L535)、[559](../../Tests/GameCoreTests/ReferenceWorld.swift#L559)、[573](../../Tests/GameCoreTests/ReferenceWorld.swift#L573)、[592](../../Tests/GameCoreTests/ReferenceWorld.swift#L592) | place/unplace/reverse 的方格車身／路徑分支；`turned` node heading／link offset 反向。 |
| [611](../../Tests/GameCoreTests/ReferenceWorld.swift#L611)、[621](../../Tests/GameCoreTests/ReferenceWorld.swift#L621)、[632](../../Tests/GameCoreTests/ReferenceWorld.swift#L632) | `ahead`、`passable` 格路徑、`setContinuation`。 |
| [765](../../Tests/GameCoreTests/ReferenceWorld.swift#L765)、[928](../../Tests/GameCoreTests/ReferenceWorld.swift#L928)、[942](../../Tests/GameCoreTests/ReferenceWorld.swift#L942) | advance 的格 step 分流；departOnce 選格／路網；departOnGrid 用格 route memo、折返、零距離到站、寫 continuation。 |
| [991](../../Tests/GameCoreTests/ReferenceWorld.swift#L991)、[999](../../Tests/GameCoreTests/ReferenceWorld.swift#L999) | `stepped/steppedHead`：link 餘距離、1024 商餘、cursor 與方格 body 更新。 |
| [1045](../../Tests/GameCoreTests/ReferenceWorld.swift#L1045)、[1051](../../Tests/GameCoreTests/ReferenceWorld.swift#L1051)、[1087](../../Tests/GameCoreTests/ReferenceWorld.swift#L1087) | `(格,heading)` State、以 relaxation 算距離後 compass greedy walk、目的格 route overload。 |

方格的模型還分散在 extension，不能只刪 ReferenceWorld.swift 的 case：

| 檔案與行號 | 方格 extension |
| --- | --- |
| [ReferenceTrainLength.swift:27](../../Tests/GameCoreTests/ReferenceTrainLength.swift#L27)、[69](../../Tests/GameCoreTests/ReferenceTrainLength.swift#L69)、[123](../../Tests/GameCoreTests/ReferenceTrainLength.swift#L123)、[173](../../Tests/GameCoreTests/ReferenceTrainLength.swift#L173) | 格車身點／cut／body／反向、整車 route、platformTracks、佔用 resources。 |
| [ReferenceTrackResources.swift:19](../../Tests/GameCoreTests/ReferenceTrackResources.swift#L19)、[44](../../Tests/GameCoreTests/ReferenceTrackResources.swift#L44)、[130](../../Tests/GameCoreTests/ReferenceTrackResources.swift#L130) | tile/link 佔用與衝突、格 section、以獨立 augment 算 parallelTracks。 |
| [ReferenceNetwork.swift:316](../../Tests/GameCoreTests/ReferenceNetwork.swift#L316) | `setPath` 的 grid traversal → nodes 分支；路網幾何／移動主體仍保留。 |
| [ReferenceNetworkService.swift:135](../../Tests/GameCoreTests/ReferenceNetworkService.swift#L135) | 泛用 path 的格 route／剩餘 link 距離分支。 |
| [ReferenceLines.swift:188](../../Tests/GameCoreTests/ReferenceLines.swift#L188)、[209](../../Tests/GameCoreTests/ReferenceLines.swift#L209)、[505](../../Tests/GameCoreTests/ReferenceLines.swift#L505)、[625](../../Tests/GameCoreTests/ReferenceLines.swift#L625) | 格月台與 heading 的 line journey、格路徑／arrived、Place.trail、派車／折返。 |
| [ReferenceTrafficControl.swift:30](../../Tests/GameCoreTests/ReferenceTrafficControl.swift#L30)、[239](../../Tests/GameCoreTests/ReferenceTrafficControl.swift#L239) | 格 continuation 的預約資源與 reserves(tile:)。 |
| [ReferenceRuns.swift:94](../../Tests/GameCoreTests/ReferenceRuns.swift#L94) | running curve 的格路徑剩餘長度／link 餘距離。 |
| [ReferenceEconomy.swift:82](../../Tests/GameCoreTests/ReferenceEconomy.swift#L82) | 與 Core 一致，站 position 格距 × 1024 的票價／需求距離。 |

## 4. SaveFixtures

以 JSON 結構解析 map tile tag 與 Station 形式，不以全文含有 `"track"`／`"station"` 判斷（costs.track、timetable.station、network.platforms.station 都會造成誤判）。

| 存檔／證據 | 格子地圖 | 方格鐵軌／方格車站 | 路網內容 |
| --- | --- | --- | --- |
| [v1-demo-90-minutes.json:106](../../SaveFixtures/v1-demo-90-minutes.json#L106)、[4348](../../SaveFixtures/v1-demo-90-minutes.json#L4348) | 32 × 24；dense `tiles` 共 768 個，全是 empty | **0 / 0**；五座站全有 point，無 position/annexes | 4 nodes、2 edges、6 platforms；兩列車均 onEdge |
| [v2-demo-90-minutes.json:108](../../SaveFixtures/v2-demo-90-minutes.json#L108)、[511](../../SaveFixtures/v2-demo-90-minutes.json#L511) | 1024 × 1024；`occupied: []` | **0 / 0**；五座站全有 point，無 position/annexes | 4 nodes、2 edges、6 platforms；兩列車均 onEdge |
| [v3-demo-90-minutes.json:131](../../SaveFixtures/v3-demo-90-minutes.json#L131)、[736](../../SaveFixtures/v3-demo-90-minutes.json#L736) | 1024 × 1024；`occupied: []` | **0 / 0**；五座站全有 point，無 position/annexes | 12 nodes、10 edges、14 platforms；四列車均 onEdge，含 ring |
| [v4-real-world-demo-90-minutes.json:135](../../SaveFixtures/v4-real-world-demo-90-minutes.json#L135)、[740](../../SaveFixtures/v4-real-world-demo-90-minutes.json#L740)、[68](../../SaveFixtures/v4-real-world-demo-90-minutes.json#L68) | 1024 × 1024；`occupied: []`；另有 geoAnchor | **0 / 0**；五座站全有 point，無 position/annexes | 12 nodes、10 edges、14 platforms；四列車均 onEdge；除 geoAnchor 外 world 與 v3 相同 |

四份都保留共用 movement 的 `continuation: []`，但沒有 atNode/onLink／格 trail，不能以空 continuation key 誤算為方格列車。固定存檔皆無格軌／站，仍不免除 §1.4 舊 codec 與 §3 裡手寫／生成的方格存讀測試；玩家既有存檔內容也未由這次儲存庫研究驗證。

## 5. GamePresentation 與 App

### 5.1 GamePresentation 直接呼叫與相容欄位

| 檔案／行號 | 使用的方格 API／資料與呼叫關係 |
| --- | --- |
| [ConstructionTool.swift:10](../../Sources/GamePresentation/ConstructionTool.swift#L10)、[40](../../Sources/GamePresentation/ConstructionTool.swift#L40)、[71](../../Sources/GamePresentation/ConstructionTool.swift#L71)、[87](../../Sources/GamePresentation/ConstructionTool.swift#L87) | `buildTrack/buildStation/removeTrack` 工具；TrackPiece／TrackPieceKind；TrackConnections、cardinal 旋轉。23 行 `networkTools` 將這三工具從 App picker 排除，程式仍在。 |
| [GameSession.swift:38](../../Sources/GamePresentation/GameSession.swift#L38)、[52](../../Sources/GamePresentation/GameSession.swift#L52)、[60](../../Sources/GamePresentation/GameSession.swift#L60)、[81](../../Sources/GamePresentation/GameSession.swift#L81) | 格 selection、connections、turnoutStem、placementHeading；276–353 行格零件編輯／旋轉／stem 邏輯。 |
| [GameSession.swift:159](../../Sources/GamePresentation/GameSession.swift#L159)、[165](../../Sources/GamePresentation/GameSession.swift#L165)、[171](../../Sources/GamePresentation/GameSession.swift#L171)、[194](../../Sources/GamePresentation/GameSession.swift#L194)、[244](../../Sources/GamePresentation/GameSession.swift#L244)、[250](../../Sources/GamePresentation/GameSession.swift#L250) | `map.tile/contains`、`track(at:)`、`station(at:)`、點站的格 fallback；`select/tapMap/selectStation` 與 compass moveSelection。選站／點選對路網仍重要，須只移除方格 fallback 或另改選取表示。 |
| [GameSession.swift:546](../../Sources/GamePresentation/GameSession.swift#L546)、[570](../../Sources/GamePresentation/GameSession.swift#L570) | `placeSelectedTrain` 優先路網月台，無路網平台且為格站／格選取時 fallback `world.placeTrain(.atNode(...))`。點站無月台走說明訊息。 |
| [GameSession.swift:643](../../Sources/GamePresentation/GameSession.swift#L643)、[676](../../Sources/GamePresentation/GameSession.swift#L676) | `sendSelectedTrain` 的格分支呼叫 `route(toStation:length:)` 或 `route(to: GridPosition)`，commit `setTrainContinuation(to:)`；路網分支走 path／along，不可整方法刪掉。 |
| [GameSession.swift:1011](../../Sources/GamePresentation/GameSession.swift#L1011)、[1015](../../Sources/GamePresentation/GameSession.swift#L1015)、[1023](../../Sources/GamePresentation/GameSession.swift#L1023)、[1034](../../Sources/GamePresentation/GameSession.swift#L1034)、[1046](../../Sources/GamePresentation/GameSession.swift#L1046)、[1074](../../Sources/GamePresentation/GameSession.swift#L1074) | `applyTool` 仍直接呼叫 buildTrack/buildTurnout/buildCrossing、格 buildStation、removeTrack；growStation 呼叫 extendStation。App picker 隱藏不代表相容實作／測試不存在。 |
| [DisplayText.swift:7](../../Sources/GamePresentation/DisplayText.swift#L7)、[29](../../Sources/GamePresentation/DisplayText.swift#L29)、[60](../../Sources/GamePresentation/DisplayText.swift#L60)、[89](../../Sources/GamePresentation/DisplayText.swift#L89)、[113](../../Sources/GamePresentation/DisplayText.swift#L113) | cardinal／bitmask 文案、tileSummary 查 track 與 map、stationSummary 格數、Station.placeText 方格座標 fallback。 |
| [DisplayText.swift:154](../../Sources/GamePresentation/DisplayText.swift#L154)、[166](../../Sources/GamePresentation/DisplayText.swift#L166)、[183](../../Sources/GamePresentation/DisplayText.swift#L183)、[193](../../Sources/GamePresentation/DisplayText.swift#L193)、[272](../../Sources/GamePresentation/DisplayText.swift#L272)、[570](../../Sources/GamePresentation/DisplayText.swift#L570) | 全車停站提示、node/link 位置、tile/link ID、GameError 的格錯誤文案；selectionText 的格軌 fallback。路網摘要與錯誤文案共用，不整檔刪除。 |
| [TrackInfoText.swift:30](../../Sources/GamePresentation/TrackInfoText.swift#L30)、[44](../../Sources/GamePresentation/TrackInfoText.swift#L44)、[58](../../Sources/GamePresentation/TrackInfoText.swift#L58) | `sectionTexts`→trackSections、trackSectionsSummary、lineTrackCounts 文案；相容功能，App 現在沒有這三查詢的呼叫。 |
| [MapScale.swift:55](../../Sources/GamePresentation/MapScale.swift#L55)、[61](../../Sources/GamePresentation/MapScale.swift#L61)、[85](../../Sources/GamePresentation/MapScale.swift#L85)、[119](../../Sources/GamePresentation/MapScale.swift#L119)、[151](../../Sources/GamePresentation/MapScale.swift#L151) | 格 hit test／中心與列車 node/link／trail 的畫面換算；不是路網權威。MapScale 的其他 zoom／clip 等功能共用。 |
| [MapCamera.swift:72](../../Sources/GamePresentation/MapCamera.swift#L72)、[108](../../Sources/GamePresentation/MapCamera.swift#L108)、[222](../../Sources/GamePresentation/MapCamera.swift#L222) | 地圖 bounds 用 GridMap；builtContent 加入 network.tracks 的格中心（另有路網節點、點站與列車）。 |
| [StationDemandText.swift:241](../../Sources/GamePresentation/StationDemandText.swift#L241) | selectedStation 先 station ID，否則 selection→world.station(at:)。路網面板也經過它。 |
| **[NetworkSession.swift:296](../../Sources/GamePresentation/NetworkSession.swift#L296)** | 路網月台的 `place` 仍讀 cardinal placementHeading 與 tangent dx/dy 決定 forward/backward；312 行用 `along:[]/stoppingAt:`，它不是格 continuation。這是刪 TrackDirection 前的實際路網需求。 |
| [NewGame.swift:43](../../Sources/GamePresentation/NewGame.swift#L43)、[162](../../Sources/GamePresentation/NewGame.swift#L162)、[NetworkSession.swift:226](../../Sources/GamePresentation/NetworkSession.swift#L226) | 新遊戲尺寸是 GridMap 上限；demo 與路網工具使用 **PlanPoint** buildStation，沒有回用格站 overload。名字相同須辨識實參型別。 |
| [RealWorldMap.swift:63](../../Sources/GamePresentation/RealWorldMap.swift#L63)、[92](../../Sources/GamePresentation/RealWorldMap.swift#L92) | E2 的 RealWorldFrame 用 GridMap→WorldRegion 求地圖中心及半寬／半高，再換算地球上的公尺；這是實景背景的尺寸依賴，沒有方格鐵軌／車站建造。 |

GameLauncher／SaveLibrary 會呼叫共用 SavedGame 的 JSON encode/decode，間接承接 §1.4 的相容格式；沒有另存第二份方格權威。LineEditing、TimetableEditing、服務／乘客／經濟面板主要用站 ID 與共用查詢。

### 5.2 App 實際仍可抵達的使用

| App 位置 | 方格呼叫／資料 |
| --- | --- |
| [ControlPanel.swift:61](../../RailwayGameApp/Views/ControlPanel.swift#L61) | 工具列用 networkTools，沒有提供格建造／格擴站／格拆除；因此未找到 App 直接呼叫 buildTrack/buildTurnout/buildCrossing/extendStation/removeTrack 的建造入口。列車工具仍可經 session 抵達格 fallback。 |
| [TileArt.swift:55](../../RailwayGameApp/Views/TileArt.swift#L55)、[64](../../RailwayGameApp/Views/TileArt.swift#L64)、[73](../../RailwayGameApp/Views/TileArt.swift#L73)、[77](../../RailwayGameApp/Views/TileArt.swift#L77) | 畫 `Station.tiles`、`world.tracks`、格選取；drawTrack 的 layout／connections／stem 與 drawBar/trackPath 在 [233](../../RailwayGameApp/Views/TileArt.swift#L233)、[260](../../RailwayGameApp/Views/TileArt.swift#L260)、[268](../../RailwayGameApp/Views/TileArt.swift#L268)。332–386 行格框／格中心／cardinal edgePoint。 |
| [TileArt.swift:82](../../RailwayGameApp/Views/TileArt.swift#L82) | `world.location/bodyPath` 共用 renderer 查詢會畫格列車；間接進 RailwayNetworkTrains 的 adapter，路網繪圖也需保留。 |
| [MapView.swift:59](../../RailwayGameApp/Views/MapView.swift#L59)、[125](../../RailwayGameApp/Views/MapView.swift#L125)、[188](../../RailwayGameApp/Views/MapView.swift#L188)、[215](../../RailwayGameApp/Views/MapView.swift#L215) | 四方向 accessibility selection action→session.moveSelection；MapCanvas 的 GridPosition selection→TileArt。一般觸控是世界座標 tapMap，但 session 仍作格 fallback。 |
| [TrainControls.swift:55](../../RailwayGameApp/Views/TrainControls.swift#L55)、[178](../../RailwayGameApp/Views/TrainControls.swift#L178)、[111](../../RailwayGameApp/Views/TrainControls.swift#L111) | 未放置列車仍顯示 headingPicker／TrackDirection 四方向→setPlacementHeading；它也影響路網放置。列車 positionText 能顯示 node/link；控制按鈕經 session 放置／送往／反向／unplace。 |
| [InspectorView.swift:50](../../RailwayGameApp/Views/InspectorView.swift#L50)、[MapView.swift:122](../../RailwayGameApp/Views/MapView.swift#L122) | selectionText 間接讀格軌 tileSummary／格站 fallback。其他車站清單／站面板的共用 stationSummary/placeText 也保留格站文案。 |

## 6. 作為 F3 計畫輸入的待定事項

1. **定義移除邊界**：格軌／格列車／格站與 land map、bounds、成本／車長尺度分開。尤其票價格距與初始放置 heading 已影響路網，替代行為須明確。
2. **逐份處理契約**：可在路網承接的營運／乘客／經濟規則，與無法只換指令的格出口、格支撐、擴站、section／parallelTracks、平手順序、同格重建恢復分別列入遷移審查。沒有推論新 schema 或刪掉哪些 coverage 的決策。
3. **保留差分獨立性**：先列出 generator、Operation、summary、invariants、ReferenceWorld 與 extension 的替代工作，再評估 campaign digest／replay。改世界表示會改 digest，不能當作無行為差異的自動更新。
4. **保存相容性另有責任**：固定 SaveFixtures 無格鐵路，但自造舊世界測試與玩家存檔仍需有明確處理；本筆記不主張升版本、重寫／刪 fixture 或放棄讀檔。
5. **App 清理範圍**：隱藏的 session 工具、舊世界畫圖與 fallback 路徑要一起評估；路網選站、方向與純 renderer／map 功能仍需替代或保留。

## 7. F3b 進度

§3 的行號是盤點當時（F3a 之前）的基準，之後的修改會讓它們漂移。

### 7.1 F3b-1：只把方格當布景的單元測試（已搬到路網）

共用的 [`TestLine`](../../Tests/GameCoreTests/TestLine.swift) 用 F3a-2 golden 的同一種搬法（[GoldenScenarios/README](../../GoldenScenarios/README.md#f3fixture-搬到路網schema-不變)）：原本那排格的每個格心放一個節點，相鄰兩個之間一條 1024 的直邊；車站改成點車站，月台在節點兩側各半格，所以列車停在節點上，兩站之間開的距離和方格時一樣。

已搬：ServiceDwellTests、ServiceRunTests、PassengerDemandTests、BoardingTests、EconomyAccountsTests、CarPriceTests、RingLineTests（環線用 `ring-line.json` 的路網環）、ServiceLineTests、LineDispatchTests、LinePatternTests、TrainTimetableTests、TrainServiceTests、TrainRepeatTests、IDAllocationTests、PersistenceAndDeterminismTests 的腳本、NetworkServiceTests 與 VerticalRailwayTests 的車站（改點車站，底下的格不變，所以票價距離不變）。GameCore 沒有改。

預期值有變的地方（其餘只是位置寫法換成路網，數值照舊）：

| 類別 | 變化 | 原因（路網既有的規則） |
| --- | --- | --- |
| EconomyAccountsTests | 一天的能源 37400 → 37200、路線能源 1400 → 1200 | 路線長度取自 line 的計畫行程：從 Alpha 東側月台的 berth 出發，3584 而不是 4096；round(220 × 0.056) = 12 |
| ServiceLineTests | 行程起點 b 朝北 → 邊 2 正向 512；各段秒數第一段變短（標準 16 → 14、metro 11 → 9、forest 24 → 21、crawl 59 → 45），往返分鐘數不變；Alpha–Gamma [23,23] → [21,23] | 行程從往返最短的 berth 出發，第一段少 512 |
| ServiceLineTests | Gamma／Delta 共用月台 0+0 s、4 分 → 8+12 s、5 分；兩列車的尖峰／離峰班距 2 → 3 分 | 路網上兩站不能共用月台，只能在月台交界相接 |
| ServiceLineTests | 「開不了的行程」：拆 e 格 → 拆 Beta 在邊 4 的月台與邊 4，重建是新邊 7；各段 [14,16,18,14] | 邊 ID 不重用 |
| ServiceLineTests | 「選往返最短的起點」改在直線上寫：從邊 2 正向 512 出發 422 s，從 b 出發 424 s；沒有 Alpha 東側月台時 426 s | 方格的環與朝向起點在路網沒有對應寫法 |
| LineDispatchTests | crawl 計畫行程 [240,240]／720 → [211,240]／691（分鐘不變）；服務在 Alpha 結束時 b 朝東 → 邊 2 正向 0 | 同上第一段；折返停在原地 |
| LinePatternTests | pattern 0 起點 → 邊 4 正向 512；[120,120]／480 → [91,120]／451、express [350,350]／940 → [321,350]／911、Main 1200 → 1171（分鐘不變） | 同上第一段 |
| TrainTimetableTests | 放在 a 的列車 cursor 2 → 1；在 b 反向 → 邊 1 反向 0 | 路網的 cursor 只數進入的邊；反向在原地 |
| TrainServiceTests | Gamma → Delta → Beta：Delta 出發的一段 2048 → 2560 | Delta 的月台在 f 之後（邊 6 的後半） |
| TrainServiceTests | 「行駛中拆軌」：目的地 Beta → Gamma、2 分的行程；重建後仍等（方格時會接著走，6:12 到 Beta） | 服務路徑終點所在的月台不能拆（S5）；重建是新邊，原路徑一直被擋 |
| TrainServiceTests | 存檔中的服務：最後停在 Delta 的位置 f → g；「拆掉 Beta 唯一的月台」改成驗證拆除被拒（trainServiceActive） | Delta 往東的 berth 在月台尾端；S5 |
| TrainRepeatTests | 往返車從第 1 圈起：12:00 立刻到 Alpha → 先開 512 到 berth，12:08 到、12:50 開（原 12:42），往 Gamma 3584（原 4096），16:50 到（原 16:42）；1000 tick 後的位置 308 → 278 | 一節車在月台折返後停在新方向的近端，該站的 berth 在遠端 |
| TrainRepeatTests | 「一圈兩次停共用月台的兩站」→「一圈停同一站兩次」，時間不變 | 兩站月台交界只在一個方向是其中一站的 berth，繞圈時要移動 |
| IDAllocationTests | 拒絕順序少了「蓋在軌道上」（tileOccupied） | 點車站不佔格 |

### 7.2 F3b-1 之後暫時沒有改的地方

- **方格本身是主題的單元測試**：TrackConstructionTests、TrackConnectivityTests、TrainPositionTests、TrainMovementTests、TrainRouteTests、StationStopTests、TrackResourceTests、StationFacilityTests、StationAndTrainTests 的格站部分，以及 RailwayNetworkAuthorityTests、ContinuousTrackTests、FreeStationTests、SavedGameTests 的方格子測試、NetworkServiceTests 的格／路網隔離斷言、VerticalRailwayTests 的 grid link 斷言。留到 F3c 和方格程式一起刪；刪之前逐條確認路網有對應測試，沒有的補上。
- **TrafficControlTests 的方格段**：其中和軌道種類無關的規則（開關交通管制、共用軌道或相遇路線時拒開、跟車等整條路、派車等路、等被拆的軌）要在刪方格段之前有路網版本；路網段已有的（服務等路，只為出發才折返）不重寫。
- **TrainTimetableTests 的兩個方格存檔格式測試**（`testEmptyTimetablesAreNotSavedAndOldSavesReadAsEmpty`、`testASaveWithoutTimetablesKeepsItsFormat`）：主題是方格存檔，F3c 拒絕手做的方格存檔時一起處理。
- **Property、差分、save mutation campaign 與 ReferenceWorld 的方格模型**（§3.2–§3.4）：F3b-2 已搬（§7.3）。
- **觀察到、沒有改的 GameCore 行為**（F3b 不動 GameCore，記給之後的階段決定）：
  1. 一節車的列車在月台折返後停在新方向的近端；下一站若是同一站，服務先開到 berth 才算到站。`stationsStoppedAt` 已把它算在站裡，但「已停在下一站就立刻到站」看的是到 berth 的距離是否為 0。
  2. 服務路徑上的邊被拆掉再重建是新的邊，被擋住的服務列車一直等，不會改走新邊（方格時重建同一格會接著走）。
  3. 路網上兩站不能共用月台；在兩站月台的交界，每個方向只會是其中一站的 berth。

驗證：見 F3b-1 的 PR（Linux Swift 6.4 的完整測試與 warnings-as-errors 建置）。macOS／Xcode 不受影響，沒有在本機執行。

### 7.3 F3b-2：campaign 搬到路網

GameCore 沒有改。差分 campaign 和它們的存檔變異 campaign 改在路網上產生世界，獨立參考模型（`ReferenceWorld`）原本就有路網的指令，沒有改。

**共用的路網產生器** [`KernelNetwork`](../../Tests/GameCoreTests/KernelNetwork.swift)（取代方格的 `NetworkShape`）：節點在格心，橫豎的直邊各 1024，轉彎用曲線；邊在節點只有反方向、差 1/16 以內才相接，所以轉角是曲線、分岔是同方向離開的道岔。形狀對應方格的用途：

| 形狀 | 對應方格的 | 內容 |
| --- | --- | --- |
| `line` | `line` | 一條直線，偶爾有 2–3 格長的邊（長列車放得下的月台） |
| `loopWithTails` | `loopWithTails` | 兩條直邊加兩端曲線的環，轉角接出尾線（道岔） |
| `ladder` | `ladder` | 兩條平行線，用 S 形渡線同方向接起來：等長的替代路線 |
| `crossings` | `grid` | 共用節點但不相接的平面交叉：列車只能直走過去 |
| `twoLines` | `twoComponents` | 兩條不相通的線 |
| `balloons` | （方格的環） | 一條線兩端各一個迴圈，兩支都從線的端點同方向離開：列車繞迴圈就能掉頭，任何站兩個方向都到得了 |

車站是點車站，約一半的節點旁有一站，月台在該站節點兩側各邊離它近的那一半（最多兩格；偶爾整條邊，偶爾沒有）；偶爾有一站離軌道很遠。路網上只能在月台停的列車要能掉頭，方格的環很多、路網的形狀較稀疏，所以 `balloons` 補上方格那種「繞一圈回來」的路。

**核心 campaign 的路網指令**（`KernelDifferentialTests.nextOperation`；方格的版本改名 `nextGridOperation`，只剩方格本身是主題的 campaign 用，F3c 刪除）：建節點、建邊（直線或曲線）、拆邊、拆節點、在點上建站、加月台、拆月台、放到邊上、手動給路徑並停在某處、送到節點、送到車站（到 berth 的路），其餘指令照舊，各類比例與方格相同。每一步除了原本比對的狀態，還比對路網的節點、邊與月台、每列車的路徑、停點與車身、每列車到每一站的路。停站轉換規則多了路網的三條（決策 18 之外）：列車在路網上反向會開到邊的盡頭，所以反向可以結束停站；月台加在停著的列車底下會多停一站；拆掉列車底下（沒有服務需要）的月台會少停一站。

**產生器不再出方格的指令**：路網 campaign 故意放錯位置時改放到不存在的邊或邊外，不再用方格位置。這樣 F3c 刪掉方格的 case 時，這些 campaign 產生的指令一個都不變，digest 應該完全相同，可以拿來證明 F3c 沒有改遊戲行為。

**搬到路網的 campaign 與 digest（舊 → 新）**：

| Campaign（suite） | 測試類別 | 舊 digest（方格，PR #84 的 CI） | 新 digest（路網） |
| --- | --- | --- | --- |
| `kernel.differential` | KernelDifferentialTests | A62B8C4320C627D1 | F47A646FE640DF46 |
| `stateMachine.replay` | WorldStateMachineTests | 697A83B146954944 | D6365571232E943D |
| `ids.allocation` | IDAllocationPropertyTests | C8EB3DB7EB4AF977 | F758A3276BCE4233 |
| `timetable.differential` | TimetablePropertyTests | BD45BE9134085D0D | FE747524D42262A2 |
| `service.differential` | ServicePropertyTests | FD07836B770C9534 | C6651E0F3814DE72 |
| `service.repeating` | ServicePropertyTests | 5F64514EF59418D7 | FDE17B82B2F62E0E |
| `line.differential` | ServiceLinePropertyTests | BB6704D839F59654 | 5BC81327E09471FC |
| `line.dispatch` | LineDispatchPropertyTests | D4348AB9FD75ADBE | 64CE531B44C9168B |
| `line.patterns` | LinePatternPropertyTests | A6D6E8E03091E6BF | A501408567DFA643 |
| `passenger.differential` | PassengerPropertyTests | 45F665FB9CEF29DD | 7252126EEF12395A |
| `boarding.differential` | BoardingPropertyTests | 335CA1EE9BA64518 | B87EFD417F5CDA1B |
| `economy.differential` | EconomyPropertyTests | FCF21908F7AC0187 | B39027771D907D9D |
| `service.network` | NetworkServicePropertyTests（點車站） | DD5C9D48842DEB67 | 93B28EDC34398663 |
| `traffic.reservation` | TrafficControlPropertyTests（路網一半用點車站） | 830ED73A7B1DA205 | B4ACB2397A8CFAD1 |
| `vertical.differential` | VerticalRailwayPropertyTests（點車站） | B59222327C26BD3F | 304714C513B40EFB |

不變（方格本身是主題，或沒有用到方格車站）：`track.resources` 696BB5A1406DD105、`station.facilities` F1F33A66D49FC516、`network.differential` 0474078196C584BC、`movement.determinism` E57ED3F6BA74E16D、`route.reference` 31A64EEA8E625E89、`stationStop.routes` 3242A5341BD2789A。存檔變異 campaign 只印量（`[volume]`），沒有 digest；它們跟著上面的產生器改在路網上。

**量的下限有變的**：

| Campaign | 下限 | 原因 |
| --- | --- | --- |
| `kernel.differential` | 新增路網指令的下限：移動列車的 advance 300、給出路徑的送車 200、成功的 stand 250、place 350、buildEdge 200、removeEdge 200、addPlatform 100、removePlatform 200、buildStationAt 200、拆有列車的邊被拒 100 | 方格版沒有逐類的下限；路網版確認每一類指令都真的跑到 |
| `line.patterns` | case 6 → 10 | 路網的形狀較稀疏，6 個 case 跑不到足夠的交路與快車 |
| `line.differential` | 拿掉「沒有移動的一段」（≥ 100） | 路網上兩站不會共用 berth（方格可以共用月台格），兩站之間的一段一定要移動 |
| `line.dispatch` | 「跑完的趟」150 → 100 | 路網上一個 case 內跑完的趟較少：設定時四個 seed 共 134 |
| `boarding.differential` | 「同時載往幾個迄點」200 → 20 | 路網上的線路較稀疏：設定時四個 seed 共 43 |
| `service.differential` | 「沒有時刻表」60 → 40 | 設定時四個 seed 共 59 |

**修正的測試支援**：`WorldInvariants` 原本假設每座車站都佔一格，點車站（Stage F1）不佔格；改成點車站檢查「位置是點底下的格、沒有擴站」，格站照舊。存檔變異 campaign 的「車站在它的格上」也只對格站檢查。

點車站的存檔被變異成沒有車站、只剩一座車站或沒有列車時仍讀得進來（地圖沒有格指向它們；方格車站時這種變異會被拒絕），而存檔變異 campaign 會在讀進來的世界上接著跑各 campaign 的產生器。完整測試因此抓到三個產生器在這種世界會當掉：乘客（沒有車站、少於兩站時排停靠站）、路網服務與交通管制（沒有車站或列車；只剩一站時排時刻表）。它們在這種世界改送 advance 或空的時刻表（GameCore 拒絕）。只有那種世界才走新的分支，其他情況抽到的亂數不變，digest 不受影響（乘客、路網服務與交通管制的 digest 在加了防呆前後相同）。

方格本身是主題的 `station.facilities` 借用線路派車 campaign 的產生器（`scriptedLine`、`nextDispatchOperation`），那兩個改到路網後，它在方格上派不出長列車。它改用一份方格版的複本（`gridScriptedLine`、`gridDispatchOperation`，F3b-2 之前的寫法），digest 回到原值；F3c 和方格一起刪。

### 7.4 F3b-2 之後暫時沒有改的地方

- **方格本身是主題的 campaign** 留在方格上，digest 不變，F3c 和方格程式一起刪：`topology.*`、`position.*`、`movement.*`、`route.*`、`composition.*`、`stationStop.routes`、`track.resources`、`station.facilities`，以及它們的存檔變異（`save.trackMutation`、`save.facilityMutation`）。`traffic.reservation` 的方格一半也一樣。
- **`ReferenceWorld` 的方格模型**：只剩上面那些 campaign 用，F3c 一起刪。
- **觀察到的 GameCore 行為**（§7.2 的三條）照舊，F3b 不改 GameCore。

### 7.5 F3b-3：重播 fixture（移植參考的 desync 重播）

參考包的除錯工具（`Railway/railway_game_reference_clean/docs/desync.md` §2.1 快取檢查、§2.2 指令紀錄、§3.1 重播、§3.2 比對 checksum 找出分歧的區間；`01_MIGRATION_MAP.md` 的「Determinism / debugging」）以獨立實作移植成 [`ReplayFixtures/`](../../ReplayFixtures/README.md)：五個路網 campaign case 的起始世界、指令紀錄，以及每 10 個指令一個遊戲狀態的 checksum。`ReplayFixtureTests` 逐段重播，每個世界都檢查不變量；checksum 對不上時指出分歧的那一段指令。

| 參考 | Swift | 說明 |
| --- | --- | --- |
| `desync.md` §2.2 指令紀錄 | `ReplayCommand`（純值的 Codable，不用 GameCore 會拒絕無效值的 coding） | 有效與被拒的指令都記 |
| §3.2 每段 checksum | `ReplayState.checksum(of:)`：時間、金錢與帳、路網與月台、車站與乘客、列車的位置／車身／路徑／服務、線路與交路、乘客群（FNV-1a 64） | 算遊戲狀態的描述，不是存檔位元組：存檔格式改了但值不變時 checksum 不變 |
| §3.1 重播、§3.2 縮小區間 | `ReplayFixtureTests.testEveryRecordedStreamReplaysToTheSameStates`、`firstDifference` | 第一個不同的 checksum 指出分歧的指令區間 |
| §2.1 每 tick 檢查快取 | 每個指令後跑 `WorldInvariants` | |

這些 fixture 只有路網的指令與內容，F3c 刪方格時必須原樣重播；之後的行為變更若改動 checksum，要在該 PR 重新錄製並逐一說明（規則同 golden 與存檔 fixture）。

## 8. F3c 進度

### 8.1 F3c-1：區段與單雙線的路網版

方格刪掉之前，只有方格版的兩個唯讀查詢先有路網版，刪方格時功能不跟著消失（ARCHITECTURE 決策 51 的 F3c-1）。

| 參考 | Swift | 倍率 |
| --- | --- | --- |
| `Railway/site_archive_clean/rail-3d/physical/topology.js` 第 47–57 行 `trackGroups`（從普通節點填滿到分歧點） | [`GameWorld.networkSections()`](../../Sources/GameCore/Railway/TrackResources.swift)、`NetworkSection`；判斷普通節點的 `isPlain(_:)` | 世界單位（只看相接，不看長度） |
| 同上（參考只有一個實作） | 差分模型 [`ReferenceWorld.networkSections()`](../../Tests/GameCoreTests/ReferenceNetworkSections.swift)：邊的 union-find，再排出順序 | — |
| S1 的 `parallelTracks`（不共用連結的路徑數；`tra_track_sections.json` 的 ≥ 0.5 沒有移植，見下） | `GameWorld.parallelTracks(between:and:)` = 方格 + `networkParallelTracks`：每段軌道容量 1 的最大流，廣度優先 | 世界單位 |
| — | 差分模型 `ReferenceWorld.networkParallelTracks`：深度優先、以邊與段落命名的頂點 | — |

- **區段**：分歧點是「不是正好兩條相接的邊」的節點：道岔、交叉、盡頭，以及兩條邊在那裡不相接的節點。從分歧點出發的區段依（節點編號、邊編號）最小的那一端排，從那一端走；沒有分歧點的環依最小的邊編號排，從那條邊的 `from` 節點順著走。沒有邊的節點不屬於任何區段（方格的孤立格是一格的區段；路網的節點不是軌道）。
- **和參考不同的地方**：參考的一組只列普通節點；我們另外列出邊與行進方向，以及兩端的分歧點（和方格的 `trackSections()` 一樣）。參考數相鄰的節點、看 `switch` 標記；GameCore 沒有標記，所以數邊端並用相接規則（決策 29），同一對節點之間的兩條邊是兩股（參考是重複的 OSM way，共用一個資源）。盡頭在參考裡屬於一組，在我們這裡是區段的端點。
- **單雙線**：沿用 S1 的定義，路網上路徑不共用任何一段軌道：一條邊，在兩站的月台處切開（同一條邊上的兩站之間的那一段也算一段，長度 0 也算）。路徑只在相接的邊之間轉換，可以在邊上折返（S1 也不看轉向規則）；從月台往邊的兩個方向都可以出發。方格與路網不相連，兩個數相加。
- **驗證**：`NetworkSectionTests`（7 個，預期值手算：避車線、切斷避車線、環、同一條邊上的兩站、菱形交叉、空路網）；新的 campaign `network.sections`（`NetworkSectionPropertyTests`，16 個 case × 4 個 seed，kernel 的路網與指令，每一步比對區段與每一對車站的單雙線，另外檢查每條邊正好在一個區段、區段內的節點都是普通節點）。改壞 GameCore 的三處（每段容量 2、普通節點不看相接、環從另一端反向走）時這個 campaign 都會失敗。`track.resources` 的 digest 不變（696BB5A1406DD105），方格的查詢沒有變。
- **行為**：兩個都是唯讀查詢，沒有規則讀它們，golden 也沒有觀察路網的這兩個查詢，所以遊戲行為、golden、存檔與 replay fixture 都不變。改變的是路網世界的查詢結果（原本沒有區段、單雙線一律 0）與文字：線路面板的單雙線原本在路網世界一律是「方格上沒有軌道」，現在是單線、雙線或「沒有軌道」；區段摘要也數路網。

### 8.2 F3c-1 之後暫時沒有改的地方

- **tra 的「平行比例 ≥ 0.5 算雙線」**（`Railway/site_archive_clean/data/tra_track_sections.json`）沒有移植：產生器 `scripts/build_tra_track_sections.mjs` 不在 repo，「哪一段算平行」沒有定義；它是真實路線的資料分類，參考唯一的使用者是交會推估（`index.html` 第 8460 行 `single(a,b)`），留到 V 和交會一起移植。
- **路網區段的文字**：方格有 `sectionTexts(at:)`（經過某一格的區段）；路網沒有對應的「經過某條邊的區段」文字，App 也沒有呼叫這些查詢的畫面（C2 的方格選取已經拿掉）。要顯示時再加。
- **F3c 其餘步驟**：GameCore 的方格與 golden schema 28（F3c-3，方格版的 `trackSections()`／`TrackSection` 與方格的平行路徑在那時刪）、`Web/WasmProbe`（F3c-4）。

### 8.3 F3c-2：GamePresentation 與 App 不再用方格

GameCore 沒有改。GamePresentation 與 App 不再呼叫方格的鐵軌、車站與列車位置的 API，F3c-3 刪 GameCore 的方格時不必再動它們（只剩對 GameCore 列舉的完整 switch，見 §8.4）。

| 拿掉的 | 之後 |
| --- | --- |
| 工具 `buildTrack`、`buildStation`、`removeTrack`，`TrackPiece`、`TrackPieceKind`，`GameSession` 的軌道形狀、道岔共用端、擴站（F1 起 App 已經不提供） | 工具只有選取、路網、列車；車站由路網工具的月台模式建（F1） |
| 放置列車在選取的格（`placeTrain(.atNode)`） | 只放在選取車站的路網月台；沒選車站時說「請選擇要放置 T 的車站」 |
| 送到選取的格（方格路徑 `route(to:)`、`setTrainContinuation(to:)`） | 只送到選取的車站（`path(from:toStation:length:)`）；沒選車站時說「請選擇 T 要前往的車站」（原本是「路網上的列車只能前往車站」） |
| 放置方向用 GameCore 的 `TrackDirection` | GamePresentation 自己的 `CompassHeading`（北東南西，畫面不變） |
| `selectedTrack`、`selectedTile`、`moveSelection`；點地圖時「佔那一格的車站優先」；`selectedStation` 從格找車站 | `selection` 只是點到的那一格（土地）；車站只靠點與名字選（App 的世界沒有佔格的車站，所以結果相同） |
| 選取的方格軌道文字（`tileSummary`、`TrackConnections` 的名稱）、站的格數、`networkSummary` 的「格軌道」 | 「3 座車站 · 4 個軌段」 |
| `sectionTexts(at:)`（經過某一格的區段）；區段摘要數方格 | 區段摘要只數路網（F3c-1 的 `networkSections()`） |
| 方格的路徑文字 `TrainMovement.pathText` | `Train.pathText` 只說路網的路 |
| `MapScale` 的格中心與方格列車的換算 | 列車的位置、朝向與車身都經過世界查詢（`location(of:)`、`bodyPath(of:)`） |
| App：畫方格鐵軌、佔格的車站與選取的格；地圖的 VoiceOver 動作「選取北／東／南／西邊的格子」與提示（字串目錄的五筆一起拿掉） | 地圖只畫路網、點車站與列車；VoiceOver 從車站清單選站 |

**測試**：GamePresentationTests 只把方格當布景的都搬到路網（共用的 `TestLine` 複製一份到這個 target）：TrainControlTests、StationStopSessionTests、StationFacilitySessionTests、TrafficControlSessionTests、TrackInfoTextTests、LineSessionTests、PerformanceSessionTests、TimetableEditingTests、EconomyDisplayTests、TrainSessionPropertyTests（差分的 UI 動作改成選站、路網放置與送車），以及只用方格車站的 LineEditing、StationDemandSession、NetworkServiceSession、NetworkBuildingSession、FreeStationSession。只屬於方格工具的 TrackLayoutSessionTests、TrackActionTests 刪掉，其中和工具無關的兩條規則搬到 ToolActionTests；StationActionTests 改用月台工具建站。

預期值有變的（其餘只是寫法換成路網，數值照舊）：

| 測試 | 變化 | 原因 |
| --- | --- | --- |
| PerformanceSessionTests | 標準性能來回 9 分 36 秒 → 9 分 34 秒、第一段 16 → 14 秒；crawl 20 分 → 19 分 31 秒、第一段 2 分 → 1 分 31 秒 | 行程從往返最短的 berth 出發，第一段少 512（和 F3b-1 的 ServiceLineTests 同一條規則） |
| FreeStationSessionTests | 點在 (1000, 1000)：原本選佔格的 Tile，現在選半徑內的 Close | 沒有車站佔格了 |
| TrainControlTests、StationStopSessionTests | 訊息從「…，從 (1, 2) 起 4 段連結」變成「…，沿軌道 4096 單位」；送到非車站的格改成「請選擇…要前往的車站」 | 路網的送車訊息（S5） |
| DisplayTextTests、NetworkBuildingSessionTests、LocalizationTests | 「0 座車站 · 0 格軌道 · 1 個軌段」→「0 座車站 · 1 個軌段」 | 拿掉方格的格數 |

### 8.4 F3c-2 之後暫時沒有改的地方

- **對 GameCore 列舉的完整 switch**：`TrainPosition.atNode／onLink`、`TrackNodeID.tile`、`TrackEdgeID.link` 的顯示文字與方格的 `GameError` 訊息（以及測它們的 DisplayText、Localization、NetworkDisplay 測試）還在，GameCore 拿掉那些 case 時（F3c-3）一起刪。
- **`GameSession.selection`** 仍是 `GridPosition`：點到的那一格土地，決策 51 保留 `GridPosition`（點車站底下的格）。
- **VoiceOver 在地圖上移動選取**：方格的四個動作拿掉後，地圖沒有替代的動作；VoiceOver 使用者從車站清單（路網總覽、線路面板）選站。參考沒有這個功能，需要時另外設計。
- **UNVERIFIED — App（SwiftUI）**：Linux 不能編譯 App；`RailwayGameApp/` 的改動（ControlPanel、TrainControls、MapView、TileArt、字串目錄）要靠 macOS CI 的建置與 UI 測試確認。

## 驗證紀錄

- **VERIFIED — Linux `/workspace/railway-game-ios` 靜態盤點**：`rg -n` 搜尋並讀取定義、使用分支與 generator；全部 27 份 golden 與 4 份 save 使用 Python `json` 解析，逐份計數／檢查型態。這是靜態查核，不是 Swift 執行結果。
- **VERIFIED — Linux `/workspace/railway-game-ios` 文件檢查**：核對相對連結目標／行號範圍及目標檔案與基準一致、fixture 清單／指令次數，確認全部 63 個 GameCoreTests 測試類別列入或說明無方格依賴，以及 65 個 campaign 字串出現處均已涵蓋；`git diff --check`，確認對基準的差異只有本文件，受保護路徑保持不變。
- **UNVERIFIED — Swift build/test 與完整 property／差分／mutation campaign**：本次只寫研究文件，未執行；上表不是宣稱那些測試通過。
- **UNVERIFIED — macOS/Xcode／Simulator／實機**：本次只讀 App 呼叫，未執行 iOS build 或 UI 測試；未執行 TestFlight workflow。
