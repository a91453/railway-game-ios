# Architecture

## 分層

```
┌──────────────────────────┐
│ App（RailwayGameApp）     │  SwiftUI 畫面、輸入、HUD、地圖繪製
├──────────────────────────┤
│ GamePresentation          │  GameSession、tick 換算、顯示文字（無 SwiftUI）
├──────────────────────────┤
│ Rendering (未來)          │  SpriteKit / Metal、動畫
└────────────┬─────────────┘
             │ 讀取狀態、送出指令
┌────────────▼─────────────┐
│ GameCore                  │  權威狀態與遊戲規則
│  World / Railway /        │
│  Economy / Time           │
└──────────────────────────┘
```

- **GameCore** 是唯一的 source of truth。它只依賴 Swift 標準函式庫（連 Foundation 都沒有 import），CI 在 Linux 上建置，因此任何 SwiftUI / UIKit / SpriteKit / Metal 依賴都會直接編譯失敗。
- **Presentation / Rendering** 只負責呈現、輸入與動畫。它們可以保存「畫面用」的衍生資料（sprite、插值中的列車位置、動畫進度），但這些資料**不得**成為模擬的真實狀態；所有遊戲狀態的變更都必須透過 `GameWorld` 的指令。
- **GamePresentation**（Phase 2B 起）是與平台無關的 Presentation 邏輯：持有世界的 `GameSession`、`TickAccumulator`、玩家看到的文字（錯誤訊息、時間、金額；英文與繁體中文，決策 38）與地圖縮放換算；Stage C4 起還有開始畫面與存檔（`GameLauncher`、`SaveLibrary`）。它只依賴 GameCore、Swift 標準函式庫的 `Observation`，以及只為存檔的 JSON 與檔案使用的 Foundation（決策 45；Linux 的 Swift 工具鏈也有），不 import SwiftUI / UIKit，因此與 GameCore 一起在 Linux CI 上測試。
- **App**（`RailwayGameApp/`）只有 SwiftUI 畫面：`@main` App 以 `@State` 持有 `GameLauncher`，它持有正在玩的那一局的 `GameSession`（同時只有一個，決策 45）；畫面讀取 `session.world` 並呼叫 session 的方法。GameCore 維持不變、不為 UI 加上 observation。App 唯一的外部套件是 MapLibre Native（決策 97，實景地圖的 OpenStreetMap 底圖；BSD 2-Clause，版本鎖在 `Package.resolved`），GameCore 與 GamePresentation 不依賴它。

### GameCore 內部的依賴方向（2026-09 決定）

GameCore 裡的經營層（Passenger、City、Economy）不得依賴鐵路的物理層：

```
鐵路的物理層：軌道、預約、movement authority、dispatcher、行駛曲線（S1–S5、T、U、V、W）
        ↓ 只經過穩定的查詢
車站、路線、服務與停站：哪台車停在哪一站、服務的執行進度、路線的行程與班距
        ↓
乘客（Passenger）→ 經營（Economy）
        ↑
城市的需求（City）
```

- 乘客、城市與經營**不讀**這些：`TrackTraversal`、`TrackResource`、`TrackSpan`、`Train.reservation`、movement authority、`TrainMovement`、列車在邊上的位置與里程。
- 它們也**不改**：時刻表的執行進度、列車的移動或預約。
- 它們只透過這些取得資訊：車站與月台的身分、路線與服務的身分、停站的查詢（例如 `stationsStoppedAt(by:)`）、服務的執行進度，以及路線的行程與班距。
- 為什麼：V（誰先走、在哪裡交會）與 W（怎麼加減速）之後還會改變鐵路的物理層。守住這條規則，那些改變只會讓乘客「晚幾分鐘到」，不必重寫乘客、城市或經營的資料模型。
- 沒有事件匯流排（決策 13）：上下車等經營的規則在 `advance` 每個基本步長的固定階段裡執行，只讀上面的查詢，所以結果仍然 deterministic，存檔也不依賴處理順序。

## GameCore 模組

| 目錄 | 內容 |
| --- | --- |
| `World` | `GameWorld`（狀態協調點與指令入口）、`WorldBounds`（世界的範圍，決策 54）、`GameError`、`SavedGame`（帶版本的存檔）、`GeoAnchor`；只給舊存檔解碼用的 `LegacyGrid` |
| `Geometry` | 整數世界座標（`WorldCoordinate`、`PlanPoint`、`PlanVector`）、軌道的曲線與取樣（`TrackCurve`、`TrackGeometry`）、整數運算（`FixedPoint`）（Stage S3，決策 28、29）；縱斷面、坡度與結構物（`TrackProfile`、`TrackGrade`、`TrackStructure`）與淨空（`TrackClearance`）（Stage S4，決策 30）；128 位元的整數運算（`WideInteger`，Stage W1，決策 33） |
| `Railway` | `Station` / `StationID`（世界座標的一點）、`Train` / `TrainID`、`TrainPosition`（列車在路網邊上的位置，`onEdge`）、`TrainMovement`（rate、路與移動 kernel）、路徑搜尋（`route(from:to:)`）、停站（`trackPlatforms(of:)`、`path(from:toStation:length:)`、`stationsStoppedAt(by:)`）、時刻表（`ScheduledStop`、`Train.timetable`、`Train.timetablePeriod`）、時刻表服務（`TimetableExecution`、`Train.execution`）、服務路線（`ServiceLine`、`ServiceDay`、`TargetHeadways`、`lineJourney(_:)` 等推導查詢）、自動派車（`assignTrain(_:to:)`、`advance(ticks:)` 的派車階段）、鐵路圖（`TrackNodeID`、`TrackEdgeID`、`TrackTraversal`、`TrackResource`）與連續路網（`RailwayNetwork`、路網上的列車與 renderer 查詢，Stage S3）、路網上的月台（`TrackPlatform`、`Station.trackPlatforms`）與 renderer 的唯讀快照（`RailwaySnapshot`、`TrackAlignment`，Stage S4）、服務路徑（`TrainPath`，Stage S5）、交通控制與進路預約（`Train.reservation`、`reservedResources(of:)`、`heldResources(of:)`、`trainHoldingRoute(of:)`，Stage T）；行駛曲線與車種性能（`RunningCurve`、`TrainPerformance`，Stage W1，決策 33）；停站時間的純計算（`StationDwell`，G1b，決策 35） |
| `Passenger` | 車站需求（`StationDemand`、`StationDemandKind`）、乘客與守恆稽核（`StationPassengers`、`WaitingGroup`、`PassengerLedger`）、每對車站的旅次與每分鐘的釋出（`passengerTrip(from:to:)`、`dailyDemand(from:to:)`、`hourlyDemand(from:to:)`，`advance(ticks:)` 的乘客階段）（G1a，決策 34）；上下車與容量（`TrainRiders`、`RidingGroup`、`Train.capacity`、`riders(of:)`，`advance(ticks:)` 的上下車階段）（G1b，決策 35） |
| `Economy` | `Money`、`GameEconomy`、`ConstructionCosts`；經營模式、票價、帳本與結算（`EconomyMode`、`FareRules`、`CompanyAccounts`、`LedgerEntry`、`tripFare(from:to:)`、`financeReport(_:)`，`advance(ticks:)` 每步一開始的結算）（G1c，決策 36） |
| `Time` | `GameClock`、`GameSpeed`、`GameTime` |

## 架構決策

### 1. Money 不用 Double

`Money` 是包裝 `Int64` 的 struct，以最小貨幣單位計算。浮點數在加減累積後會產生誤差，對「餘額是否足夠」這類比較與存檔重現都不可接受。使用獨立型別而不是裸 `Int64`，避免與座標、時間等整數混用。`Int64` 範圍遠大於遊戲可能出現的金額，因此目前不處理溢位。

### 2. Track 連接方向

`TrackConnections` 是 `OptionSet`（`UInt8` bit set），`TrackDirection` 是單一方向的 enum。

- 一格鐵軌可以同時連接多個方向（直線、彎道、T 字、十字），單一 enum 無法表達。
- 相較 `Set<TrackDirection>`：每格只佔 1 byte、比較便宜，且編碼結果穩定（`Set` 的迭代順序每個 process 都不同，會讓存檔輸出不 deterministic）。
- `TrackConnections(rawValue:)` 接受任何 byte，驗證放在邊界：地圖（`GridMap`）解碼與 `buildTrack` 對鐵軌格都只接受四個方向的 bit（rawValue 1…15）。空連接與含未知 bit 的值一律拒絕，不會把未知 bit 遮掉後接受；`buildTrack` 丟出 `invalidTrackConnections`，而且這項檢查先於範圍、佔用與資金。

### 3. 遊戲時間

`GameTime` 是自開局以來的整數「遊戲分鐘」（Stage W2a 起改為遊戲秒，基本步長是一秒，速度是每 tick 的十分之一秒，見決策 37；本節其餘的說法是當時的設計，速度與步長的規則以決策 37 為準）。`GameClock` 從不讀取 wall clock：宿主（Presentation 層的 game loop，見決策 12）把真實經過時間換算成整數 tick，再呼叫 `advance(ticks:)`。每個 tick 在 paused / 1x / 2x 下分別執行 0 / 1 / 2 個**基本步長**（basic step），每個基本步長是一遊戲分鐘。相同的 tick 序列必定得到相同結果，測試不需要 sleep。

2x 以「每 tick 執行兩次基本步長」實作，而不是把步長加倍，讓結果與速度無關（Phase 3 Stage K 起列車移動就是逐步執行，見決策 15）。

`advance(ticks:)` 會 throw（`throws(GameError)`）：在改動任何東西之前，先以 checked 運算確認 `ticks × 每 tick 步數` 不溢位、且時鐘加上這些分鐘後仍放得下（`Int64` 分鐘）；任一項不成立就丟出 `clockOverflow`，整批不執行、世界完全不變。paused 的步數永遠是 0，多大的 ticks 都不會因此被拒絕。負數 ticks 仍是程式錯誤（`precondition`）。`GameClock.advance(ticks:)` 本身也用同一套檢查。

### 4. GameWorld ownership

`GameWorld` 是 value type（struct），所有欄位 `private(set)`，唯一的修改方式是它的指令方法（`buildTrack`、`removeTrack`、`buildStation`、`purchaseTrain`、`placeTrain`、`unplaceTrain`、`reverseTrain`、`setTrainMovementRate`、`setTrainContinuation`、`setTrainTimetable`、`startTrainService`、`stopTrainService`、時間控制與 `advance(ticks:)`）。

- **原子性**：每個指令先完成所有驗證，最後一個可能失敗的步驟是扣款，扣款成功後才寫入地圖 / 清單。因此丟出錯誤時狀態保證不變，測試直接以 `XCTAssertEqual(world, before)` 驗證。
- **單一事實來源**：地圖格子本身記錄內容（`TileType.track(connections:)`、`TileType.station(id:)`），`Track` 只是查詢時產生的唯讀快照，不另存一份鐵軌清單。車站名稱等非格子資料放在 `stations` 陣列，並以 ID 與地圖互相對應。
- **避免 God Object**：規則分散在各自型別（`GridMap` 負責邊界、`GameEconomy` 負責扣款、`GameClock` 負責時間），`GameWorld` 只負責協調與跨物件不變量。等功能增加再拆分，而不是先建立 service / manager 層。
- value semantics 讓 undo/redo 與背景計算可以直接使用快照；陣列採 copy-on-write，單一擁有者原地修改不會複製。

### 5. 錯誤處理

正常的規則錯誤使用 typed throws：`throws(GameError)`。`GameError` 是 `Hashable` enum，帶結構化資料（位置、所需 / 可用金額），不含 UI 文案，方便測試比較與未來在 Presentation 層做在地化。`precondition` 只用於程式設計錯誤（例如負數金額、負數 tick），不用於玩家可觸發的情況。

### 6. Codable 策略

所有需要保存的型別都是 `Codable`：`GameWorld`、`GridMap`、`Station`、`Train`、`GameClock`、`GameEconomy`、`Money` 等。唯讀快照（`MapTile`、`Track`）不需保存。

- ID 由世界依序配發（`StationID`、`TrainID`，從 1 開始、永不重用），而不是 `UUID`，讓同樣的操作序列產生同樣的 ID 與同樣的存檔。「同樣的存檔」指 key 排序後的 JSON：`JSONEncoder` 預設的 key 順序由 encoder 決定，每個 process 可能不同，需要逐位元相同時用 `.sortedKeys`（測試都這樣做）。車站與列車各有一個 `Int` 計數器（`nextStationID`、`nextTrainID`），存的是下一個要配發的 ID：配發時取它的值再加 1，世界裡同類的 ID 都小於它。因此只有在加 1 仍放得下時才能配發：最後一個 ID 是 `Int.max − 1`，之後計數器停在 `Int.max`；`Int.max` 本身永遠不會是 ID。用盡之後，`buildStation` / `purchaseTrain` 丟出 `idsExhausted`，在扣款與任何改動之前檢查（順序：名稱 → 格子 → ID → 資金），世界完全不變、不會溢位、繞回或重用 ID；另一類 ID 不受影響。計數器停在 `Int.max` 的世界能由指令到達（從接近上限的存檔開始），照常存讀；計數器不是正數、或不大於同類既有 ID 的存檔，解碼時由下面的不變量檢查拒絕。存檔格式不變。
- 集合使用有序陣列而非 `Dictionary` / `Set`，編碼輸出穩定。
- `GridMap` 與 `GameWorld` 解碼時驗證不變量（格子數量、車站與地圖一致、ID 唯一且小於下一個配發值、已放置的列車位在鐵軌上：節點是鐵軌格，連結的兩端相接；列車的 continuation 與位置一致且在地圖範圍內；時刻表的每一站都是存在的車站），壞資料會丟出 `DecodingError` 而不是產生不一致的世界或之後 crash。`ConstructionCosts` 與 `GameClock` 的解碼同樣拒絕任何指令都不會產生的值：負數的建設成本（花費負數金額是程式錯誤，這種存檔以前能讀入，下一次購買就 crash），以及與 `resume()` 不一致的時鐘：恢復速度是 paused，或執行中的速度與恢復速度不同（`resume()` 回到暫停前正在執行的速度）；存檔格式不變。列車位置、移動與時刻表的存檔格式與舊資料相容性見決策 14、15、19。
- 目前沒有存檔版本或 migration；等正式 save system 時再加入版本欄位。

### 7. Sendable 策略

所有 GameCore 型別都是由值型別組成的 struct / enum，宣告 `Sendable` 不需要任何 `@unchecked` 或鎖。這讓未來可以把整個 `GameWorld` 快照傳給背景 task（例如路徑搜尋、存檔編碼）而不違反 Swift 6 的資料競爭檢查。

### 8. 為什麼本輪不使用 actor

目前的模擬是單執行緒、同步、deterministic 的狀態轉換。把 `GameWorld` 做成 actor 會讓每次讀取都變成 `await`、讓 UI 取得一致快照變難，並引入執行順序的不確定性，卻沒有解決任何現存問題。

未來可演進方向：由一個擁有者（例如 `@MainActor` 的 game session 或專用 actor）持有 `GameWorld` 並執行 tick；重計算（pathfinding、乘客需求）在背景以 `Sendable` 快照計算，再把結果以指令套回世界。核心型別不需要改變。

### 9. Train 只放目前需要的資料

`Train` 有 ID、名稱、位置（`position`，Stage J，決策 14）、移動狀態（`movement`，Stage K，決策 15）與時刻表（`timetable`，Stage O，決策 19）。路線所有權、編組與閉塞都還沒設計；等對應的 Stage 真的需要時才加入，不預先放空欄位（見 ROADMAP）。

### 10. Track connectivity：由地圖推導，不建立 graph

鐵軌是否相接，每次查詢時直接由地圖推導（`GameWorld.connectedNeighbors(of:)`、`isConnected(_:to:)`，Phase 3 Stage I）。地圖上的 `TileType.track(connections:)` 仍是鐵軌唯一的權威紀錄，`Track` 仍只是唯讀快照。

- **相接規則**：格子 p 往方向 d 的鄰格 q，只有在 p、q 都在地圖內、都是鐵軌、p 有 d 出口、q 有 `d.opposite` 出口時才相接。目前所有實體連結都是雙向的，因此 `isConnected(p, q) == isConnected(q, p)`。同一格、斜對角、相隔一格以上、地圖外、空格與車站都不相接；車站目前不是鐵軌。
- **雙向出口是通行條件，不是鋪設條件**：孤立的鐵軌、只有一個出口的鐵軌，以及朝向空格、車站、不相配的鐵軌或地圖邊界外的出口，都可以鋪設。GameCore 不會自動補齊、旋轉或修改鄰格的出口。拆軌後，下一次查詢立即反映斷開；鄰格的出口保持原樣，成為懸空（dangling）出口。
- **Junction**：每一格鐵軌是一個互通節點。兩個出口是直線或彎道，三個是互通的 T 字，四個是互通的十字。四個出口不代表「交叉但不互通」的兩條鐵軌；這種交叉、轉轍器狀態與入口—出口配對目前都不支援。
- **查詢回傳所有相接的鄰格**，包括列車之後可能的身後方向。要不要折返、走哪個出口，是列車移動與路徑搜尋的責任，不屬於拓撲查詢。
- **順序固定為北、東、南、西**，沒有重複項；由 `TrackDirection` 的宣告順序決定，不依賴 `Dictionary` / `Set` 的迭代順序。
- **沒有 graph cache**：不另存 graph、registry、revision counter 或索引，因此不可能與地圖不同步，每個 `GameWorld` 快照也自然保留它自己的連通結果。每次查詢只讀取起點與最多四個鄰格，不使用 `tracks` 或 `map.tiles` 掃描整張地圖。先確認起點在地圖內才計算鄰格，因此極端座標（`Int.min` / `Int.max`）不會溢位。

### 11. GameSession：UI 如何持有唯一的 GameWorld

`GameSession` 是 `@MainActor`、`@Observable` 的 class，`world` 為 `private(set)`，是 App 執行期間唯一一份 `GameWorld`。

- SwiftUI 需要一個可觀察的 reference 擁有者；把這個責任放在 Presentation 層，GameCore 就能維持 value type、`Sendable`、不 import Observation。
- 每個玩家動作都是 session 方法 → 對應的 `GameWorld` 指令。session 不預先檢查遊戲規則（空格、資金、名稱），由 GameCore 決定並丟出 `GameError`；session 只把結果轉成畫面訊息（`GameError.playerMessage(in:)`，定義在 GamePresentation）。失敗時世界保持不變（GameCore 的原子性保證）。
- session 另外只保存 UI 暫時狀態：選取的格子、目前工具、下一段鐵軌的方向、車站名稱草稿、選取的列車 ID、放置列車時的朝向、最後一則訊息。現金、時間、速度、地圖、車站、列車的位置與移動都直接從 `world` 讀取，不另存副本（列車見決策 17）。
- 全部在 main actor 上執行，不需要鎖或 `@unchecked Sendable`。
- 放在獨立的 SwiftPM target 而不是 App target，是為了讓 session 與其規則在 Linux 上以 `swift test` 驗證（App target 只能在 macOS CI 編譯）。

### 12. 宿主 game loop：真實時間 → 整數 tick

wall clock 只存在於 Presentation 層；GameCore 只收到 `advance(ticks:)`。

- `GameSession` 的 loop 以 `ContinuousClock` 量測經過時間，交給 `TickAccumulator` 換算成固定間隔（100 ms）的整數 tick，不足一個 tick 的餘數留到下一次，因此 tick 頻率不會隨畫面節奏漂移。`Task.sleep` 只負責節奏，不影響正確性。
- 速度不改變 tick 頻率：1× 與 2× 都是每 100 ms 一個 tick，由 GameCore 決定每個 tick 執行幾個基本步長（決策 3）。Stage W2a 起速度的名稱就是 100 ms 一個 tick 下真實時間的倍數（`x1` 是真實時間），tick 頻率仍然不變（決策 37）。暫停時丟棄經過的時間，不累積。
- `advance(ticks:)` 被拒絕（`clockOverflow`，遊戲時間已到上限）時，session 不改變世界，只把錯誤顯示為狀態訊息。
- 單次最多換算 500 ms（5 個 tick）：主執行緒卡頓或除錯暫停不會變成一次大量補跑。
- App 以所有 scene 合併的 `scenePhase` 啟停 loop：只有 `.active` 時執行；離開前景即停止並丟棄殘餘，回到前景不補跑背景時間（prototype 不做離線進度）。loop 由 session 持有且只會有一個，iPad 多視窗也不會重複推進。

### 13. 可移植邊界與 golden scenarios

目前**不**移植到 Unity 或 Godot，也不同時維護 Swift、C#、GDScript 多份實作。這個決策只確保將來真的要移植時，可以逐一子系統搬過去並用同一批測試證明行為沒變。

- **Swift GameCore 是參考實作**，擁有所有 deterministic 的模擬與遊戲規則。
- **GameSession 是可替換的 shell**：持有世界、把輸入轉成 `GameWorld` 指令、把真實時間換算成 tick。它可以依平台而定（現在是 `@Observable` + SwiftUI；將來可以是 Unity 的 MonoBehaviour 或 Godot 的 Node），但不擁有任何遊戲規則。
- **邊界本身就是現有的 public API**：輸入是 `GameWorld` 的指令與 `advance(ticks:)`；輸出是指令的回傳值、`GameError` 與唯讀狀態。GameCore 不另建 adapter、事件匯流排或 snapshot 型別，等真正的需求出現再加；golden scenario 用的指令與狀態摘要型別只存在於測試中，而且只使用 public API。
- **畫面頻率與模擬頻率是兩件事**：模擬只以整數 tick 前進（目前 10 Hz，見決策 12），畫面依自己的節奏讀取最新狀態，一個畫面 ≠ 一個 tick。將來需要平滑動畫時，宿主以目前 tick 的進度（`TickAccumulator.pending / tickInterval`；`GameSession` 目前沒有公開它，屆時再加）在兩個 tick 之間插值；插值結果只用於顯示，不寫回 GameCore。
- **可移植的值**：跨邊界與寫進 fixture 的值使用整數（金額、遊戲分鐘、tick、ID、格子座標、列車位置的 offset）與固定名稱（方向、速度、指令、錯誤），不使用浮點數或 Swift 專屬的編碼。`GameWorld` 的 `Codable` 是 Swift 的存檔格式，**不是**可移植契約。
- **Golden scenarios**（`GoldenScenarios/*.json`）保護行為相容性：起始狀態、依序的指令、每個指令的預期結果與最終狀態都寫在同一個 JSON 檔，預期值由人手寫並 review。測試只讀取、從不寫回；改變預期值就是改變遊戲行為，必須在 PR 裡逐一說明（參考 Pebble 的 golden 流程）。Schema 見 `GoldenScenarios/README.md`。
- **Determinism 規則**：GameCore 不讀取 wall clock、不使用未排序的 `Dictionary` / `Set` 迭代決定結果。將來加入亂數時，seed 與狀態放在 `GameWorld` 裡並可編碼；UI 需要的隨機值以指令參數傳入（參考 OpenTTD 分開 `_random` 與 `_interactive_random`）。不承諾不同語言或 CPU 之間浮點運算逐位元相同，因此會進入 fixture 的規則以整數計算。

將來的移植流程（目前不實作）：

```
Swift 參考實作
  → 選一個子系統（例如時鐘，或之後的列車運行）
  → 移植到目標語言的純邏輯元件（Unity：noEngineReferences 的 assembly；Godot：不依賴 Node 的類別）
  → 以該語言讀取同一批 GoldenScenarios 並執行
  → 結果完全一致才移植下一個子系統
```

不採取「一次把整個 Swift 專案翻譯成 C#」的做法。

### 14. 列車位置（Phase 3 Stage J）

`Train.position` 的型別是 `TrainPosition?`：`nil` 表示**未放置**（unplaced）。`TrainPosition` 沒有另外的 unplaced case，所以「未放置」只有一種表示。新購列車一律未放置，GameCore 不會自動把列車放到任何鐵軌上。

- **兩種位置**
  - `atNode(tile, heading:)`：停在一格鐵軌的中心，面向 `heading`（北、東、南、西）。heading 是列車離開這格時會走的方向，**不要求**該方向有出口或相接的鐵軌：孤立的鐵軌、死路、朝向地圖邊界都合法。
  - `onLink(from:to:offset:)`：在兩格相接鐵軌的中心之間，距 `from` `offset` 單位，面向 `to`。行進方向由 `from → to` 推導，不另存 heading，因此不可能與端點矛盾。
  - 連結就是一對相鄰的格子，不建立 edge ID、registry 或 graph（與決策 10 一致）。
- **距離單位**：相鄰兩格中心之間的每條連結固定 `TrainPosition.linkLength` = **1024 單位**，直線、彎道都一樣。這是抽象的格距，不是公尺、像素，也不代表速度。1024 讓解析度細於千分之一格，且 1/2、1/4、1/8 格都能精確表示。`offset` 是 `Int64`；常數只定義在 `TrainPosition.linkLength` 一處。
- **唯一表示（canonical）**：恰好在格子中心一律是 `atNode`；`onLink` 必須 `0 < offset < 1024`。offset 為 0 或 1024 的連結位置**不會**被正規化成節點，而是與其他越界值一樣被拒絕（放置與解碼皆然），也沒有提供正規化用的 API。同一個地點因此只有一種寫法。
- **兩層驗證**
  - 位置本身（不需地圖）：連結兩端必須上下左右相鄰，offset 在範圍內。相鄰判斷以 `subtractingReportingOverflow` 計算差值，`Int.min` / `Int.max` 之類的極端座標不會溢位 trap。`TrainPosition` 的解碼只做這一層。
  - 對照地圖（`GameWorld`）：節點必須是地圖內的鐵軌格；連結兩端必須依決策 10 相接（都在地圖內、都是鐵軌、各自有朝向對方的出口）。空格、車站、地圖外、只有一邊有出口、同一格、斜對角、隔格都拒絕。`placeTrain` 與 `GameWorld` 解碼使用同一個檢查。
  - enum 本身接受任何值（和 `TrackConnections(rawValue:)` 一樣，驗證放在邊界）；但只有通過驗證的值能進入世界：`Train.position` 的 setter 是 `internal`，只有 `GameWorld` 的指令會寫入，`trains` 陣列本身也是 `private(set)`。
- **指令**（都免費，不動資金）
  - `train(id:)`：查詢列車。
  - `placeTrain(_:at:)`：把**未放置**的列車放到合法位置。錯誤依序為 `unknownTrain` → `trainAlreadyPlaced` → `invalidTrainPosition`。已放置的列車不能直接重新放置，必須先取下：放置不是移動，也就不會成為繞過之後移動規則的捷徑（與「在已佔用的格子鋪軌會被拒絕、要先拆除」的慣例一致）。多台列車可以在同一節點或同一連結上；Stage J 沒有碰撞規則。
  - `unplaceTrain(_:)`：取下列車，保留 ID 與名稱（Stage O 起也保留時刻表，決策 19）。錯誤依序為 `unknownTrain` → `trainNotPlaced`；重複取下會被拒絕（與拆除空格被拒絕的慣例一致），不是 no-op。（Stage P 起，時刻表服務執行中的列車接著丟出 `trainServiceActive`，`reverseTrain` 相同，見決策 20。）
  - `reverseTrain(_:)`：原地反向，不移動。節點：heading 取反；連結：`from`、`to` 對調，offset 變成 `1024 − offset`（例如 256 → 768），指的是同一點。反向兩次完全還原。錯誤依序為 `unknownTrain` → `trainNotPlaced`；未放置的列車不會被自動放置。
  - 所有檢查都在寫入之前完成，失敗時整個世界（列車、地圖、資金、時鐘、ID 配發）不變。
- **支撐列車的鐵軌不能拆**：`removeTrack` 先做原本的 `outOfBounds`、`noTrackToRemove` 檢查；若該格是任一已放置列車所在的節點，或其連結的任一端，丟出 `trackInUse`。其他鐵軌照常可拆，包括緊鄰列車、但不屬於其連結的鐵軌；列車取下後，原本支撐它的鐵軌也可以拆。拆除仍免費、不退款。目前沒有修改既有鐵軌出口的指令（鋪軌只能在空格），所以沒有其他會破壞支撐連結的入口。
  - 每次拆軌掃描一次所有列車，成本 O(列車數)；在有量測證據之前，不保存佔用索引或全圖快取。
  - 這條規則只保證**目前的位置**永遠有效：不是碰撞偵測，不保留路線或未來行程，也不保存已拆除的鐵軌。
- **存檔（Swift `Codable`，不是可移植契約）**：已放置的列車存 `"position": {"atNode": {"tile", "heading"}}` 或 `{"onLink": {"from", "to", "offset"}}`；未放置的列車**不寫** `position` key。因此 Stage J 之前的存檔（列車只有 `id`、`name`）照樣解碼為未放置。明確的 `null`、空物件、沒有 `atNode` / `onLink` 任一 tag（例如只有未知的 tag）、同時出現兩種 tag、缺欄位、offset 為 0 / 1024 / 越界 / 帶小數、端點不相鄰都會丟出 `DecodingError`，不會降級成未放置。與其他 GameCore 型別的解碼一樣，已知 tag 以外多出的 key 會被忽略，而 `JSONDecoder` 會把 `256.0` 之類小數部分為零的數字讀成整數 256；這是 Swift 存檔的行為，可移植的 golden fixture 另以整數規則檢查。接著 `GameWorld` 解碼再確認每個位置都在該地圖的鐵軌上（節點是鐵軌格，連結的兩端相接）；ID 與 `nextTrainID` 的既有檢查不變。
- **Golden scenarios**：schema v3 新增列車指令、結果與最終狀態的列車位置，數值一律是整數（見 `GoldenScenarios/README.md`）。浮點的顯示座標不寫回 GameCore。
- **時間**：列車以速率（rate）移動，見決策 15；rate 預設為 0，所以沒有設定 rate 的列車在時間推進時仍然不動。

Stage K（決策 15）沿用本決策的位置契約（1024 單位、唯一表示、兩層驗證、`trackInUse`）作為移動的輸入與輸出，沒有改變它。

### 15. 列車移動（Phase 3 Stage K）

列車沿著**明確指定**的路徑，以整數距離逐基本步長移動。移動本身從不選路（路徑由呼叫端提供，或先以決策 16 的 `route` 查詢產生）、不自動折返，也不做碰撞、號誌或加減速。

- **狀態（`Train.movement: TrainMovement`，只有 `GameWorld` 能改）**
  - `rate: Int64`：每個基本步長（一遊戲分鐘）可走的邏輯單位數，1024 = 一格（Stage W2a 起仍是每分鐘的單位數，分到這一分鐘的每一秒，見決策 37）。不是 km/h；與 `GameSpeed` 的 1× / 2× 分開命名。範圍是 `0...Int64.max`：移動時先比較剩餘距離與到下一節點的距離，只有剩餘距離較短時才把它加到 offset 上（結果必小於 1024），否則相減，所以任何非負 rate 都不會溢位；負數以 `invalidMovementRate` 拒絕。rate 0 表示原地不動，但保留 continuation。
  - `continuation: [GridPosition]`：列車之後依序要進入的節點。起點是「目前所在的節點」或「目前連結的 `to` 端」，這個節點本身不列入。例如在 `onLink(A→B)` 上，`[C, D]` 表示先走完 A→B，再走 B→C、C→D。
  - `cursor: Int`：已經**開始進入**的 continuation 項數。恰好抵達節點不前進 cursor；真的開始走下一條連結（消耗正距離）時才 +1。前面已進入的項保留在陣列裡，只移動 cursor，不做 `removeFirst` 搬移。全部項目都進入後，continuation 視為用完，存成 `[]`、cursor 0；因此 `cursor < continuation.count`，或兩者皆為空。
  - 未放置的列車永遠是 `TrainMovement.idle`（rate 0、無 continuation）。**被阻擋不存成狀態**：它可以由位置、continuation 與地圖推導，每一步都重新檢查。
- **指令**（皆免費，錯誤依序檢查；失敗時世界完全不變）
  - `setTrainMovementRate(_:to:)`：`unknownTrain` → `trainNotPlaced` → `invalidMovementRate`。
  - `setTrainContinuation(_:to:)`：`unknownTrain` → `trainNotPlaced` → `invalidContinuation`（Stage P 起，時刻表服務執行中的列車在 `invalidContinuation` 之前丟出 `trainServiceActive`，見決策 20）。先對**當前地圖**驗證整份清單，再整份替換、cursor 歸 0；空清單就是清除。每一項都必須與前一項（第一項則是列車所在節點或目前連結的 `to` 端）依決策 10 相接，且不能立即折返：`atNode` 往 heading 的反方向離開、`onLink(A→B)` 後接回 A、或清單中 X→Y→X 都算 U-turn，必須先 `reverseTrain`。同格、斜對角、隔格、地圖外、空格與車站都拒絕；有限迴圈與重複經過同一節點可以。清除 continuation 不會把列車瞬移到節點：在連結上的列車若 rate > 0，仍會走到該連結的端點；要立即停住就把 rate 設為 0。
  - 未放置的列車不接受任何移動指令（`trainNotPlaced`），也不會因此被放上軌道。
  - `reverseTrain`：位置照決策 14 轉換，continuation **原子清空**，rate 保留；因此在連結上反向的列車會走到反向後連結的端點停下，不會自行延伸行程。
  - `unplaceTrain`：清空 continuation 並把 rate 設為 0。重新 `placeTrain` 一律從 idle 開始，不恢復舊行程。
- **移動 kernel**（純函式，只透過「兩格是否相接」的唯讀查詢讀取地圖，不改世界、不碰資金、ID 或時鐘）
  1. 距離為 0 時位置與 cursor 都不變。
  2. 在連結上先比較剩餘距離與到 `to` 的距離：不夠就只增加 offset（結果仍是 `onLink`，offset 必在 1…1023）；夠的話扣掉這段，抵達 `to`，成為 `atNode`，heading 為抵達方向。
  3. 恰好用完距離時停在節點（`atNode`），不看、不進入、不消耗下一項，不論下一段是否存在。
  4. 在節點且還有距離時，只在下一項與目前節點**當下**相接、且不是 U-turn 時才進入並 cursor +1；否則停在這個節點，下一項不消耗，剩下的距離作廢。沒有下一項時同樣停下。
  5. 一步可以跨越任意多條連結；每進入一條就消耗一項有限的 continuation，所以巨大的距離也一定在 continuation 結束時終止。沒有遞迴，也沒有人為的迴圈上限。
- **固定步長編排（`advance(ticks:)`）**：先做決策 3 的時鐘容量檢查（早於任何列車或時鐘變動），再執行 `ticks × 每 tick 步數` 個基本步長。每個基本步長依 `TrainID` 遞增順序讓每台已放置、rate > 0 的列車走 rate 單位，最後時鐘 +1 分鐘；同一步裡所有列車看到同一個開始時間。列車彼此不互動，順序只決定更新先後，不影響結果。因此只要時鐘容得下整批，`advance(n)` 等同 n 次 `advance(1)`，2× 的一個 tick 等同 1× 的兩個 tick（只差速度設定本身）。接近時鐘上限時，整批會被拒絕，而逐次的單一 tick 仍可能一個個放得下。
  - 若某一步沒有任何列車改變，同一次呼叫裡之後的步驟也不可能改變任何東西（地圖與每台列車的輸入在下一個指令前都不變），所以時鐘直接前進剩下的分鐘數。這是精確的捷徑，不是近似；它讓一次推進大量 tick 在列車停下之後不必逐步空轉。Stage P 起，時刻表服務的出發時刻也是會讓列車改變的事件，所以捷徑只跳到下一個服務的排定出發時刻為止（決策 20）；沒有服務時與這裡相同。
  - 每步成本是 O(列車數 + 本步跨越的連結數)，每次相接查詢只讀常數個格子，不掃描整張地圖、不建立 graph 或佔用快取。
- **拆軌後自動續行**（固定決策）：continuation 提交後，前方未被列車支撐的鐵軌仍可以拆（`trackInUse` 只保護目前位置，決策 14）。列車會走完目前仍合法的連結，停在無法進入下一條指定連結的節點；rate、continuation 與 cursor 都保留。之後每個基本步長（rate > 0 且未暫停時）都重新檢查同一條指定連結；只要那條雙向連結重新接通，下一個基本步長就用**該步**的距離繼續。等待期間沒用到的距離直接作廢，不跨步累積、不追趕，也不改走其他出口。只有一端補回、雙向出口沒有對上時仍不通行。單一列車受阻不影響其他列車與時鐘，也不會讓 `advance` 失敗。
- **存檔**：`Train` 在非 idle 時寫 `"movement": {"rate", "continuation", "cursor"}`；idle 不寫。因此 Stage K 之前的存檔讀成 idle。`null`、缺欄位、負 rate、帶小數的數值、cursor 超出範圍或未正規化（`cursor == count`、空清單配非 0 cursor）、相鄰項不是上下左右鄰格、清單內 X→Y→X 都拒絕，不會降級成 idle（與決策 14 相同，`JSONDecoder` 會把 `5.0` 之類小數部分為零的數字讀成整數 5）。`Train` 解碼再確認 movement 與位置一致（不看地圖）：未放置必為 idle；已進入的項必須通到列車所在處（最後進入的節點就是目前節點或連結的 `to`，進入兩項以上時 heading 等於最後一條連結的方向；只進入一項時，第一條連結的起點沒有保存，無法再核對抵達方向）；剩下的項從該處出發不得折返。`GameWorld` 解碼另外要求所有 continuation 節點都在地圖範圍內（地圖尺寸不會改變），但**不要求**未來路段的鐵軌仍然存在：等待修復中的世界是合法存檔。目前位置仍必須在相接的鐵軌上（決策 14）。
- **本 Stage 不做**：route / pathfinding、自動選路、停站、乘客、時刻表、碰撞、號誌、編組、加減速、UI（放置、指定路徑或動畫）與任何引擎 adapter。Stage K 當時 App 無法操作列車，列車移動只透過單元測試與 golden fixture 驗證；App 的操作畫面見決策 17。

**之後的接點**：Stage L 的路徑搜尋（決策 16）只輸出一份 continuation（節點清單），再交給 `setTrainContinuation`；kernel 不需要知道目的地或路徑成本。最小的畫面整合可以只讀 `Train.position`、`movement.remainingContinuation` 與 `TrainPosition.linkLength` 換算顯示位置，列車的指令一律透過 `GameWorld`；平滑動畫需要的「本步走過哪些連結」可在那時再從步前、步後的 cursor 推導，或讓 kernel 另外回傳暫態資料，不寫回 GameCore。

### 16. 路徑搜尋（Phase 3 Stage L）

`GameWorld.route(from:to:)` 是唯讀查詢：給一個列車位置與目的地鐵軌格，回傳一份可以**原封不動**交給 `setTrainContinuation` 的節點清單，或 `nil`。它不改變世界、不保存 graph 或快取，也不改變決策 15 的移動契約。

- **輸入與輸出**
  - 起點是 `TrainPosition`（通常取自 `train(id:)?.position`）。路徑從列車前方的節點開始：所在節點，或目前連結的 `to` 端；這個節點本身不列入。
  - 回傳的清單以目的地結尾；每一步都依決策 10 相接，且不會立即折返（包括違反列車目前 heading 的折返），所以在同一張地圖上 `setTrainContinuation` 一定接受它。
  - 前方節點就是目的地時回傳 `[]`。
  - 回傳 `nil` 的情況：起點不是這張地圖上合法的位置（與 `placeTrain` 相同的判斷）；目的地不是鐵軌格（空格、車站、地圖外）；或沒有不折返的路可以到達。
- **最短與決定性**
  - 最短是指連結數最少；每條連結都是 1024 單位，所以也是距離最短。
  - 同樣最短的路徑之間，選「出口方向序列」依北、東、南、西順序逐步比較最先的那一條。這個規則只依賴地圖、起點與目的地，與鋪設順序、執行次數或平台無關，也可以在其他語言照樣實作。
- **不折返**：路徑從不包含 reverse。它可以繞圈、重複經過同一節點，或經由迴圈掉頭；如果唯一的路一開始就必須折返，就沒有路徑，要先 `reverseTrain`（之後再從反向後的位置查詢）。
- **演算法**：因為不能立即折返，列車能去哪裡取決於「節點 + 面向」，所以對 (節點, heading) 狀態做 breadth-first search，每格鐵軌最多 4 個狀態。鄰格來自決策 10 的 `connectedNeighbors(of:)`（固定北、東、南、西順序），依發現順序展開；因此每一層的狀態依路徑方向序列的順序被發現，第一個找到的目的地狀態就是最短、且在最短之中方向序列最先的那條。第一次找到目的地就停止，最多在走訪完所有可達狀態後結束。
- **成本**：只走訪起點可達的鐵軌，時間與記憶體 O(可達鐵軌格數)，不掃描整張地圖、不建立 graph 或快取。最壞情況是 1024 × 1024 幾乎全滿的地圖、目的地很遠或到不了：約 400 萬個狀態。Stage L 審查時以 release build 在 Linux x86-64 量測 1024 × 1023 全為十字鐵軌的地圖：證明到不了約 4.5 秒、對角路徑（2045 條連結）約 4.5 秒，峰值記憶體約 420 MB（含世界本身）。小地圖則是毫秒級。所以之後的 App 不應在 main actor 上對大地圖同步呼叫 `route`（可在背景以 `Sendable` 的世界快照計算，決策 7、8）；是否加入快取或更快的搜尋，等實際地圖與使用方式的量測再決定（決策 10 的原則不變）。
- **與移動的分工**：路徑搜尋只產生 continuation；是否採用、何時採用由呼叫端（UI 或之後的服務／時刻表）以 `setTrainContinuation` 決定。移動 kernel 不會自己選路；路徑提交後鐵軌被拆時，仍依決策 15 等待修復，不自動重新搜尋。
- **Golden scenarios**：schema v5 新增 `route` 觀察（見 `GoldenScenarios/README.md`）。
- **本 Stage 不做**：多個途經點或停站、以車站為目的地（車站目前不是鐵軌，屬停站的 Stage N，見決策 18）、依時間或擁擠度改變成本、自動重新搜尋、碰撞與號誌，以及任何 UI（App 的操作畫面見決策 17）。

### 17. 最小列車畫面（Phase 3 Stage M）

App 的「Train」工具讓玩家走完真正的 GameCore 列車流程：放置 → 選目的地 → 設定 rate → `route` → `setTrainContinuation` → game loop 推進 → 讀取並顯示位置。GameCore 沒有修改；新增的只有 `GameSession`（GamePresentation）的方法、顯示文字與 SwiftUI 畫面。

- **一個操作對一個 GameCore 指令**：購買（`purchaseTrain`，名稱是下一個未使用的「Train N」，購買後即選取）、放置在選取的鐵軌格中心（`placeTrain`，朝向由畫面選擇）、設定 rate（`setTrainMovementRate`）、反向（`reverseTrain`）、取下（`unplaceTrain`）。與決策 11 相同，session 不預先檢查遊戲規則；失敗時世界不變，錯誤以 `GameError.playerMessage` 顯示。沒有選取列車（或放置、送出時沒有選取格子）時，這些方法顯示提示而不呼叫 GameCore；未放置的列車沒有位置可以求路，送出時 session 直接顯示 GameCore 的 `trainNotPlaced` 訊息。`applyTool()` 維持 Phase 2B 的行為：沒有選取格子時什麼都不做（App 也會停用按鈕）。
- **送出 = 求路 + 提交，在同一次呼叫**：以按下按鈕當下選取的格子為目的地，先用 `route(from:to:)` 從列車**目前**的位置求路，再把結果原封不動交給 `setTrainContinuation`。兩步在同一個 main actor 同步方法裡、對同一份世界執行，中間沒有 `await`，game loop 無法插入，所以路徑不會過時，也只會交給求路的那台列車；依決策 16，GameCore 一定接受它。沒有路徑（不是鐵軌，或不折返到不了）時什麼都不改，列車保留原本的 continuation。UI 從不自己找路、截斷或修補路徑。App 的地圖固定 32 × 24，同步查詢最多走訪約 3,000 個狀態；將來地圖變大、要在背景求路時（決策 16），必須另外處理計算期間世界已經改變的情況。（E1 起新遊戲是 1024 × 1024，但 F1 起 App 只用路網，求路只走訪可達的軌道，成本跟著蓋了多少軌道，不跟地圖大小，見決策 48。）Stage N 起，選取的格子是車站時改用 `route(from:toStation:)`，送到該站最近的月台（決策 18）；其他格子照舊。
- **UI 暫時狀態**只有選取的列車 ID 與放置朝向；目的地不另存。列車的位置、朝向、rate 與 continuation 一律在需要時從 `world` 讀取（`selectedTrain`），畫面文字（`positionText`、`pathText`、`rateText`）也是讀取時換算：節點顯示格子與朝向，連結顯示兩端與 offset（例如 `(3, 2) → (4, 2), 640 / 1024`），路徑顯示 `remainingContinuation` 剩幾個節點與最後一個節點。rate 控制項綁定的 `selectedTrainRate` 讀的是 GameCore 的值，寫入時呼叫指令，本身不保存數值。
- **推進**：只有決策 12 的 game loop 呼叫 `advance(ticks:)`（HUD 的暫停 / 1× / 2×）。Stage M 沒有加入第二個推進入口，所以不會重複推進；暫停時列車不動。
- **繪製**：地圖在 GameCore 目前的位置畫出每台已放置的列車（節點中心，或兩端中心之間 offset / 1024 的點，`MapScale.center(of:)`），並以短線標出朝向；選取的列車加上外框。每個 tick 之後直接跳到新位置，**沒有插值**；顯示座標只在繪製時計算，不保存、不寫回。地圖 canvas 只在地圖、列車、選取或縮放改變時重畫。
- **本 Stage 不做**：停站與以車站為目的地（Stage N，見決策 18）、時刻表、乘客、號誌、碰撞與多台列車的互動、動畫插值、存檔，以及正式的遊戲 UI。

### 18. 停站（Phase 3 Stage N）

車站仍然不是鐵軌（決策 10 不變）：列車停在車站旁的鐵軌上。Stage N 在 GameCore 只新增三個唯讀查詢，沒有新指令、新錯誤或新的存檔欄位；停站由既有的位置、continuation 與地圖推導。移動 kernel 與決策 10、14、15、16 的契約都沒有改變。

- **月台（platform）**：車站格正北、正東、正南、正西的鐵軌格。
  - 月台沿著鐵軌，不需要朝向車站的出口，也不需要與其他鐵軌相接。斜對角、空格、其他車站與地圖外都不算。
  - 同一格鐵軌可以同時是多個車站的月台（例如夾在南北兩個車站之間）。同一車站的月台彼此不相鄰（兩兩是斜對角或相隔一格），不會直接相接。
  - 每次查詢由地圖推導，不保存（與決策 10 相同）：鋪軌、拆軌、建站之後，下一次查詢立即反映。
  - `platforms(of:)` 依北、東、南、西順序列出；未知的車站、旁邊沒有鐵軌的車站是 `[]`。鄰格以 `GridMap.neighbor` 取得（先確認車站格在地圖內），不會溢位。
- **以車站為目的地**：`route(from:toStation:)` 用決策 16 的同一個搜尋，把車站的每個月台都當作目的地。
  - 最少連結；同樣最少時，出口方向序列依北、東、南、西逐步比較，取最先的一條。因此結果等於對每個月台呼叫 `route(from:to:)` 之後取最好的一條。
  - 到達第一個月台就結束，途中不經過該站的其他月台。前方節點（所在節點，或連結的 `to`）已是月台時回傳 `[]`。
  - 回傳 `nil`：起點不是這張地圖上合法的位置、車站不存在或沒有月台，或不折返到不了任何月台。
  - 結果可以原封不動交給 `setTrainContinuation`；列車走完它就停在該站。
  - 實作：`TrainRoute.shortest` 的目的地從「一格」改成「判斷式」，`route(from:to:)` 傳入「等於目的地」，行為不變（Stage L 的 property digest `route.reference 31A64EEA8E625E89` 在修改前後相同）。
- **停站（stop）**：列車停在某站，若且唯若它在該站某個月台格的中心（`atNode`，朝向不限），而且沒有剩下的 continuation；與 rate 無關。
  - 這就是「行程在月台結束」：依決策 15，節點上沒有下一項的列車不會自己移動，所以停站會一直持續，直到有指令改變它。
  - 經過月台（continuation 還有剩）、在月台上被給了新的 continuation（即使 rate 是 0）、在月台上等待被拆的鐵軌修復，都**不是**停站。在連結上的列車也不是，即使 continuation 已清空；走到連結端點的月台才停站。
  - 在月台上反向、清除 continuation，或把列車放在月台上，都會停站；在停站的列車旁建站，列車立即也停在新車站。
  - 停站列車所在的鐵軌不能拆（決策 14 的 `trackInUse`），車站目前也不能拆，所以停站只會因這台列車的指令結束：設定非空的 continuation，或 `unplaceTrain`。（Stage P 起還有一種：這台列車的時刻表服務在出發時刻給它 continuation，見決策 20。）
  - `stationsStoppedAt(by:)` 依 `StationID` 遞增列出列車停的車站；未知、未放置或沒有停站的列車是 `[]`。一格月台旁可能有多個車站，所以回傳清單而不是單一車站。
  - 停站不存成狀態（與決策 15 的「被阻擋」相同），因此不會殘留、不會提早消失，存讀後也相同；存檔格式不變。
- **成本**：`platforms(of:)` 與 `stationsStoppedAt(by:)` 只讀常數個格子（找車站與列車用既有的 O(車站數)、O(列車數) 查詢）；`route(from:toStation:)` 與 `route(from:to:)` 相同。
- **App（GamePresentation）**：Train 工具選取的格子是車站時，送出改用 `route(from:toStation:)`，同樣在同一次呼叫中原封不動交給 `setTrainContinuation`（決策 17 的其他規則不變）；成功訊息寫出車站名稱與月台，沒有路徑時世界不變。列車狀態另外顯示 `stationStopText(of:)`（例如 `Stopped at Market, Hill`），每次從世界讀取。這改變了決策 17 對車站格的行為：Stage M 時車站格一律沒有路徑。
- **Golden scenarios**：schema v7 新增 `platforms`、`routeToStation`、`stationStops` 觀察與 `station-stop.json`。
- **本 Stage 不做**：停留時間（dwell）、時刻表、途經多站或指定停靠站的服務模式（Phase 4）、乘客、拆除車站、月台容量或佔用、多格車站。

### 19. 時刻表基礎（Phase 4 Stage O）

Stage O 只回答：「這台列車被排定在哪些遊戲分鐘到達、離開哪些車站？」它**不**回答「列車現在是否該出發？」，那是 Stage P 的問題。時刻表是列車的權威狀態，但在 Stage O 是 **inert** 的計畫資料：模擬的任何部分都不讀它。

（Stage P 起：只有以 `startTrainService` 明確啟動的服務會讀取時刻表，見決策 20。沒有執行中的服務時，本決策的 inert 保證完全不變；服務執行中時，`setTrainTimetable` 在 `unknownTrain` 之後先檢查 `trainServiceActive`。）

- **資料模型**
  - `Train.timetable: [ScheduledStop]`：依序的停靠。**陣列順序就是停靠順序**，是權威的；不另存序號，也不會被排序。
  - `ScheduledStop`：`station: StationID`、`arrival: GameTime`、`departure: GameTime`（排定的到達與離開）。
  - 空陣列表示沒有時刻表；新購列車一律是空的，不會繼承其他列車的時刻表。
  - 與 `TrainPosition` 一樣，`ScheduledStop` 本身接受任何值，驗證放在進入世界的邊界（指令與解碼）。`Train.timetable` 的 setter 是 `internal`，只有 `GameWorld` 的指令會寫入。
- **時間：開局以來的絕對遊戲分鐘**
  - 型別是既有的 `GameTime`（`Int64` 整數分鐘），與 `GameClock.now` 同一個尺度。不使用 `Date`、wall clock、浮點數、時區或「HH:mm」字串；`Day 1 · 08:30` 之類的顯示只在 Presentation 層換算（決策 3、12）。
  - 採用絕對時間而不是「一天中的幾點」或相對時間：GameCore 沒有日曆（`GameTime` 只是分鐘數），絕對時間可以直接和時鐘比較，不需要換算、週期或日期規則，也最 deterministic。每天重複的班次屬於之後的服務模式（Stage Q）；屆時再決定是以「一天中的分鐘 + 週期」表示，還是由服務模式展開成絕對時間。Stage O 不預先建立日曆或服務框架。
- **不變量：時間從分鐘 0 起不倒流**，也就是 `0 ≤ arrival₁ ≤ departure₁ ≤ arrival₂ ≤ departure₂ ≤ …`。
  - 允許相等：停留 0 分鐘（`arrival == departure`），以及在前一站離開的同一分鐘到達下一站。
  - 允許重複的車站（包括連續兩站相同）、沒有月台的車站、時鐘已經過去的時間、空的時刻表。
  - 每一站都必須是這個世界存在的車站（跨物件不變量，由 `GameWorld` 檢查）。
  - **不**檢查：兩站之間是否有路、行駛時間是否足夠、列車是否已放置或目前在哪裡、時鐘是否已超過、是否形成循環。這些屬於執行時刻表（Stage P、Q）。
  - 只比較時間、不做加減，所以任何 `Int64` 都不會溢位；到 `Int64.max` 為止都合法。
- **指令 `setTrainTimetable(_:to:)`**
  - 一次提交整份依序的停靠，完整驗證後原子替換；`[]` 就是清除（清除空的時刻表也不是錯誤）。免費，列車放置與否都可以。
  - 錯誤依序檢查：`unknownTrain` → `invalidTimetable` → `unknownStation(id)`，後者是依時刻表順序**第一個**不存在的車站（不是最小的 ID）。先檢查本身的形狀、再檢查引用，與解碼的兩層一致（`Train` 解碼檢查形狀，`GameWorld` 解碼檢查車站存在）。
  - 失敗時整個世界不變。成功時只有該列車的時刻表改變：位置、movement、其他列車、地圖、車站、資金、時鐘與 ID 配發都不變。
  - 沒有新增、刪除、移動或修改單一停靠的指令；等真的做編輯器（Stage R）時再考慮。
  - 成本 O(停靠數 × 車站數)：每一站以既有的 `station(id:)` 線性查詢。
- **讀取**：`train(id:)?.timetable`。沒有另外的 `GameWorld` 查詢，也沒有「下一站」、「目前停靠」、「誤點」之類的推導（Stage P）。
- **生命週期**：時刻表是計畫，不是位置或移動狀態。`placeTrain`、`unplaceTrain`、`reverseTrain`、`setTrainMovementRate`、`setTrainContinuation` 與 `advance(ticks:)` 都保留它；它們對位置與 movement 的效果照決策 14、15 不變（`unplaceTrain` 仍把 movement 重設為 idle，`reverseTrain` 仍清空 continuation 並保留 rate）。
- **Inert**：
  - `advance(ticks:)` 不讀時刻表：不會因為時刻到了而出發、設定 continuation、求路、改變 rate、標記到達或離開，也不會消耗或修改時刻表。停在時刻表車站的列車，時間超過它的出發時刻後仍停著。
  - `stationsStoppedAt(by:)`、`route`、`platforms` 與所有 Stage I–N 的查詢都不看時刻表。
  - 在同一個世界、同一串指令下，有沒有時刻表不改變 Stage I–N 的任何結果：`TimetablePropertyTests` 讓有時刻表的世界與從不設定時刻表的雙胞胎世界逐步比較（清除時刻表後必須完全相等、每個指令的結果相同、停站相同）。Stage I–N 的 property digest（`kernel.differential`、`route.reference`、`stationStop.routes` 等）在修改前後相同。
- **存檔（Swift `Codable`）**
  - 非空時寫 `"timetable": [{"arrival", "departure", "station"}, ...]`（整數）；空時不寫 key，與 idle 的 movement 相同。因此沒有時刻表的世界，存檔與 Stage O 之前逐位元相同；Stage O 之前的存檔（沒有這個 key）讀成空的時刻表。明確寫出的 `"timetable": []` 也讀成空。
  - `null`、不是陣列、缺欄位、不是整數（字串、`10.5`、超出 `Int64`）、負數時間、到達晚於離開、停靠之間時間倒流，一律丟出 `DecodingError`：不會被清除、排序、夾住、修正、截斷，也不會丟掉個別停靠。`ScheduledStop` 解碼檢查單站（`0 ≤ arrival ≤ departure`），`Train` 解碼檢查整份順序，`GameWorld` 解碼檢查每一站的車站存在。與其他型別相同，多出的 key 會被忽略，`10.0` 會讀成 10（決策 14）。
  - 不建立存檔版本或 migration（仍是跨階段議題）。
- **車站目前不能拆除**，所以被時刻表引用的車站在遊戲中一直存在。將來加入拆除車站時，必須同時決定被引用的車站怎麼處理（拒絕拆除，或同時修改時刻表）。
- **Golden scenarios**：schema v8 新增 `setTrainTimetable` 指令、`invalidTimetable` 與 `unknownStation` 結果、`timetable` 觀察，最終狀態每台列車必填的 `timetable`，以及 `train-timetable.json`。`train` 觀察仍然只回答位置與 movement，時刻表以獨立的 `timetable` 觀察讀取，所以既有 fixture 的觀察不需要改變。
- **GamePresentation**：只為兩個新錯誤加上 `playerMessage`（`GameError` 的 switch 必須完整）；沒有時刻表的畫面或行為（Stage R），App 沒有修改。
- **本 Stage 不做**：自動發車、自動求路或設定 continuation、改變 rate、到達與離開事件、停留時間的倒數、錯過出發的處理、誤點計算、循環或每日重複的班次、服務模式、乘客、碰撞、號誌、月台容量、拆除車站、時刻表畫面或編輯器、動畫，以及存檔版本框架。

**Stage P 的接點**：Stage P 把時刻表接上停站（決策 18）與時鐘。它需要決定：怎樣算「到達」某一站（例如列車開始在該站停站，決策 18）、到達後如何停留到 `departure`、何時以及如何出發（由誰求路並提交 continuation）、早到與誤點怎麼處理、錯過出發時刻時怎麼辦，以及執行進度（目前在第幾站）要不要成為存檔的權威狀態。這些都是新的行為，必須在 Stage P 另外決定並以新的 golden fixture 固定；Stage O 的資料契約（順序、時間、不變量、指令、存檔）可以原樣作為輸入。（已由決策 20 回答；Stage O 的資料契約沒有改變。）

### 20. 時刻表服務：到達、停留、出發（Phase 4 Stage P）

Stage P 回答決策 19 留下的問題：「這台列車現在是否該出發？」它在時刻表（計畫）與移動之間只加入**一個**概念：執行進度 `TimetableExecution`，並讓 `advance` 知道出發時刻。Stage I–O 的資料模型、指令與契約都沒有重寫。

```
時刻表（plan，決策 19）
  → 執行進度（execution，本決策，權威且存檔）
  → 路徑（route(from:toStation:)，決策 16、18）→ continuation
  → 移動（TrainMovement，決策 15）
```

- **為什麼這樣分層**（Stage P 前的第三方研究）：TrainApp 把 schedule、per-train controller、dispatcher、interlocking 與 movement authority 分開；OpenTTD 把 orders 與 timetable 的時間分開，並標示早到與誤點；OSRD 把 target arrival、停留、路徑與模擬結果視為不同概念；Simutrans 以固定出發時刻作為「在此之前不得出發」的閘門；真實時刻表的呈現則是把班表沿軌道顯示。本決策採用「計畫 / 執行 / 路徑 / 移動」分離與「排定出發時刻是閘門」；**不**採用 TrainApp 的整段進路預約、OpenTTD 的 shared／循環 orders 與追趕、OSRD 的連續物理與日曆時間、Simutrans 的月份班表，也不把時刻表沿軌道的插值當成交通模擬。待避、交會這類決策需要軌道資源、進路與 dispatcher，不能寫進 `ScheduledStop`。
- **資料模型**
  - `Train.execution: TimetableExecution?`：`nil` 表示沒有執行中的服務（新購列車一律是 `nil`）。
  - `TimetableExecution` 只有兩種：`.waitingAtStop(i)`（停在時刻表第 `i` 站，等待它的排定出發）與 `.travellingToStop(i)`（已離開第 `i − 1` 站，正前往第 `i` 站）。`i` 一律是**時刻表的索引**，不是車站 ID：決策 19 允許重複的車站，只看列車在哪裡或哪個車站，無法知道現在是第幾個停靠。
  - 不另存目前車站、路徑、到達車站、實際到達時刻或誤點：車站來自時刻表，路徑就是列車的 continuation，停站由決策 18 推導。
- **一次、有限的服務**：服務依時刻表順序從第一站跑到最後一站**一次**。它不循環、不每日重複、不自動折返或反向、不產生下一班，也不複製服務模式（Stage Q）。
- **指令**（皆免費，錯誤依序檢查；失敗時世界完全不變）
  - `startTrainService(_:)`：`unknownTrain` → `trainServiceActive`（已在執行）→ `noTimetable`（時刻表為空）→ `trainNotPlaced` → `trainNotAtFirstStop`（列車必須依決策 18 停在第一站的車站；月台由多站共用時，只要包含第一站即可）。成功時只把 execution 設為 `.waitingAtStop(0)`，其他都不變；出發要等時間前進（見下）。**不會**依目前時間跳過任何一站：即使所有時刻都已過去，仍從第 0 站開始，每一站都在最早可以的步長離開。時刻表永遠不會因為讀到存檔或設定時刻表而自己啟動。
  - `stopTrainService(_:)`：`unknownTrain` → `trainServiceNotActive`。只結束自動化：execution 變成 `nil`，時刻表、位置、rate 與 continuation 全部保留。正在前往某站的列車會照原本的 continuation 繼續走到該站停下，之後由玩家手動控制。停止服務不是緊急煞車；要停住列車請把 rate 設為 0。
  - 重新啟動一律從第 0 站開始（必須再停在第一站的車站）。要修改執行中的時刻表：`stopTrainService` → `setTrainTimetable` → `startTrainService`；Stage P 不嘗試把舊的索引對應到新時刻表。
- **服務擁有 continuation**：服務執行中，`setTrainContinuation`、`reverseTrain`、`unplaceTrain` 在 `unknownTrain` → `trainNotPlaced` 之後丟出 `trainServiceActive`（服務執行中的列車一定已放置，所以兩者不會同時成立），`setTrainContinuation` 的這項檢查早於 `invalidContinuation`；`setTrainTimetable` 在 `unknownTrain` 之後、`invalidTimetable` 之前丟出 `trainServiceActive`（清除也一樣）。`setTrainMovementRate` 仍然允許：服務從不設定 rate，rate 0 就是目前最小的人工暫停。`removeTrack` 不變（列車所在的鐵軌照決策 14 是 `trackInUse`）。
- **一個基本步長**（從分鐘 `T` 到 `T + 1`，每一段都依 `TrainID` 遞增順序處理每台列車）：
  1. **出發（`T`）**：每個 `.waitingAtStop(i)` 且 `departure(i) <= T` 的服務離開第 `i` 站：
     - `i` 是最後一站：服務完成，execution 變成 `nil`；列車留在原地，保留時刻表與 rate，不求路、不設定 continuation、不反向、不移動。所以最後一站的排定出發仍有意義：列車停到那時才結束服務。
     - 否則以 `route(from:toStation:)` 從列車目前位置求路到第 `i + 1` 站的車站：
       - 空路徑表示列車已停在該站（重複的車站，或多站共用的月台）：**零距離到達**，立即成為 `.waitingAtStop(i + 1)`；若那一站的出發也已到，就在同一段繼續離開它。每次處理都讓索引遞增，所以最多處理到時刻表的最後一站，不會無限循環。
       - 非空路徑：原封不動設為 continuation（cursor 0），成為 `.travellingToStop(i + 1)`。rate 為 0 的列車也會拿到 continuation，但不會移動。
       - 沒有路徑：列車繼續 `.waitingAtStop(i)`，不 crash、不跳站、不取消、不瞬移、不反向、也不讓 `advance` 失敗。之後的步長會再試；地圖因指令改變後可能就有路。同一次 `advance` 呼叫中地圖不可能改變、等待中的列車也不會移動，所以每次呼叫對每台列車最多求路一次（精確的最佳化）。
  2. **移動**：照決策 15 讓每台列車走 rate 單位。
  3. 時鐘 +1 分鐘，成為 `T + 1`。
  4. **到達（`T + 1`）**：每個 `.travellingToStop(i)` 的列車若依決策 18 停在第 `i` 站的車站，就成為 `.waitingAtStop(i)`。到達時刻就是 `T + 1`。
- **核心規則：可以晚走，但不會因服務而早於排定出發時刻離開**：`實際出發 >= departure`。**不**另加最短停留時間：`arrival == departure` 的零停留是合法的；晚到的列車（到達時已過 `departure`）不補回原本的停留，下一個步長就離開。早到的列車等到 `departure`。排定的 `arrival` 不是閘門，只是計畫與日後準點率分析的基準；Stage P 不依 arrival 控速。
- **每步最多移動一次**：在第 4 段到達的列車，最早在下一個步長的第 1 段離開，即使它的出發時刻就是到達的那一分鐘；到達那一步剩下的距離照決策 15 作廢。例如 10:00 的出發在 `clock.now == 10:00` 那一步取得 continuation，並在 10:00 → 10:01 移動；10:05 → 10:06 到站、出發排在 10:06 的列車在 10:06 → 10:07 那一步離開。
- **行駛中被擋住不重新求路**：`.travellingToStop` 的列車照決策 15 移動；前方鐵軌被拆時在原地等待修復，服務**不**另外求路（那是之後 dispatcher 的工作）。玩家若要改路，先 `stopTrainService`。
- **事件感知的快轉**：決策 15 的捷徑改成「若某一步沒有任何改變（沒有列車移動，也沒有服務出發、到達或完成），在下一個等待中服務的排定出發時刻之前，同一次呼叫的之後步驟也不會有任何改變」，所以時鐘只直接跳到 `min(本批結束, 下一個出發時刻)`，到了再重新執行服務邏輯。已經過去但找不到路的出發不算喚醒時刻（同一次呼叫中地圖不變，仍然找不到）。仍然精確：`advance(ticks: n)` 等同 n 次 `advance(ticks: 1)`，2× 的一個 tick 等同 1× 的兩個 tick（只差速度設定本身），大量 tick 在列車都停下、服務都在等待時仍是一次跳過。時鐘可以在分鐘 0 之前（存檔可以有這種時鐘），所以到下一個出發的間隔超出 `Int64` 時以 `Int64.max` 表示，而不是溢位（save mutation 測試發現的問題，已有回歸測試）。
- **存檔（Swift `Codable`）**
  - 有服務時寫 `"execution": {"phase": "waiting" | "travelling", "stop": 索引}`；沒有服務時不寫 key，所以沒有服務的世界存檔與 Stage P 之前逐位元相同，舊存檔讀成沒有服務。明確的 `null`、未知的 phase、負數或非整數的索引一律拒絕。
  - `Train` 解碼（不看地圖）確認：時刻表有這個索引、列車已放置；等待中的列車在節點上而且沒有剩下的 continuation；行駛中的列車前往的不是第 0 站，而且行程還沒結束（在連結上，或還有 continuation）。
  - `GameWorld` 解碼確認：等待中的列車確實停在該站的車站；行駛中的列車，其行程終點（continuation 的最後一個節點，已用完時是連結的 `to`）緊鄰該站的車站格。這裡檢查「緊鄰車站格」而不是「是月台」，因為最後那格鐵軌可能在列車抵達前被拆掉又補回，車站本身不會移動（目前也不能拆除），所以列車補回後一定在那一站到達。
  - 壞資料一律拒絕：不修正索引、不排序時刻表、不自動取消服務。仍不建立存檔版本或 migration。
- **Golden scenarios**：schema v9 新增 `startTrainService`、`stopTrainService` 指令，`trainServiceActive`、`trainServiceNotActive`、`noTimetable`、`trainNotAtFirstStop` 結果，`execution` 觀察，最終狀態每台列車必填的 `execution`，以及 `train-service.json`。既有 8 個 fixture 只把版本改成 9、並為最終狀態的 14 台列車加上 `"execution": { "type": "inactive" }`（它們從未啟動服務），其他預期值都沒有改變。
- **驗證**：`TrainServiceTests` 以手算的預期值逐條驗證上面的規則；`ServicePropertyTests` 讓產生的指令序列同時在 GameCore 與 `ReferenceWorld`（逐分鐘步進、沒有捷徑、每次出發都重新求路、以「已停在該站」而非空路徑判斷零距離）上執行，逐步比較結果與狀態，並檢查每次 advance 與逐 tick、2× 與 1× 的結果相同；`SaveMutationTests` 新增針對 execution 的變異存檔。Stage I–O 的 property digest（`kernel.differential`、`timetable.differential`、`route.reference`、`stationStop.routes` 等）在修改前後相同。
- **GamePresentation**：只為四個新錯誤加上 `playerMessage`；沒有服務的畫面或操作（Stage R），App 沒有修改。App 的 Train 工具對執行中服務的列車會收到 `trainServiceActive` 的訊息。
- **已知限制**：停止服務後只能從第 0 站重新開始（是否需要從指定站續跑，留給 Stage Q / R）；行駛中不重新求路；出發時的求路照決策 16 的成本在 `advance` 裡同步執行（宿主每個 tick 呼叫一次 `advance`，所以找不到路的列車每個 tick 最多求路一次）；`departure` 為 `Int64.max` 的一站永遠不會出發（時鐘無法再前進一分鐘）；日後加入拆除車站時，必須同時決定被執行中服務引用的車站怎麼處理。
- **日後的 dispatcher 接點**：出發時的 `route(from:toStation:)` 將來可以換成向 dispatcher 請求 movement authority。「沒有路就等待、之後再試」與「拿不到 authority 就等待」語義相同，時刻表與執行進度的契約不需要重寫。月台、股道、待避線與號誌屬於之後的交通資源模型，不放進 `Station` 或 `ScheduledStop`。
- **本 Stage 不做**：循環或每日重複的服務、自動折返或反向、複製服務、班距調整、乘客上下車、依時刻表控速、誤點追趕、列車碰撞、軌道佔用、月台容量、進路預約、movement authority、號誌、聯鎖、dispatcher 優先順序、真正的待避／超越決策，以及時刻表畫面（Stage R）。

### 21. 折返與重複的時刻表（Phase 4 Stage Q1）

Stage Q1 回答決策 20 留下的兩個問題：服務只跑一次，而且停在死路終點站的列車無法往回開（`route` 不會原地掉頭，決策 16）。它在時刻表加入兩項計畫資料，在執行進度加入一個計數。Stage I–P 的資料模型、指令與契約都沒有重寫。

- **為什麼這樣做**（[網頁參考研究](WEB_REFERENCE_STUDY.md)）：
  - 參考遊戲的高鐵模式用逐班的時刻表，並配對回程；捷運模式的列車在區間車終點折返，整天來回。
  - 本決策採用「在指定的停靠站折返」與「同一份時刻表週而復始」。
  - **不**採用「沒有路時自動掉頭」：這會改變決策 20「沒有路就等待、不反向」的規則，也可能讓被擋住的列車在錯誤的地方掉頭。
  - 也還不採用參考捷運「由列車數推導班距」的做法，那屬於 Q2。
- **資料模型**
  - `ScheduledStop.reverses: Bool`（預設 `false`）：服務離開這一站時，先讓列車在原地折返，再求路到下一個停靠。位置的變換與 `reverseTrain` 相同。
  - `Train.timetablePeriod: Int64?`：`nil` 表示只跑一次，否則每 `period` 分鐘重複。
    - 時刻表仍只記錄第 0 輪的時刻。
    - 第 `k` 輪的時刻是記錄的時刻加上 `k × period`，由規則推導，不展開、不存檔。
  - `TimetableExecution` 的兩種狀態都加上 `cycle: Int64`（預設 0），表示目前在第幾輪。只跑一次的時刻表永遠是 0。
  - 週期放在列車上，而不是另一個「服務模式」物件：Q1 只讓一台列車重複自己的時刻表。多台列車共用的路線服務屬於 Q2，屆時由它設定每台列車的時刻表。
- **指令**
  - `setTrainTimetable(_:to:repeatingEvery:)`
    - `period` 預設 `nil`，所以 Stage O 的呼叫方式不變。
    - 時間照決策 19 檢查。有週期時另外要求：至少一站、`period >= 1`，而且重新開始時時間不倒流，也就是 `最後一站的 departure − 第一站的 arrival <= period`。
    - 兩者相等也可以：下一輪會在上一輪最後一站離開的那一分鐘，到達第一站。這裡用減法比較，兩個時間都 ≥ 0，所以不會溢位。
    - 錯誤順序不變：`unknownTrain` → `trainServiceActive` → `invalidTimetable`（時間或週期）→ `unknownStation`。沒有新的錯誤。
    - 設定時刻表時同時設定週期；`[]`（不帶週期）同時清除兩者。
  - `startTrainService`
    - 只跑一次的時刻表照決策 20，從第 0 輪開始。
    - 重複的時刻表從第一站出發時刻不早於現在的第一輪開始（等於現在也算）。列車因此準時出發，不會把過去的每一輪都補跑一遍。
    - 如果連時刻放得下的最後一輪都已經過去，就從那一輪開始，也就是誤點出發。
    - 仍然從第 0 站開始，不會從一輪的中間加入。
  - `stopTrainService`、放置、取下、反向與時間都保留週期。週期和時刻表一樣是計畫資料。
- **一個基本步長**：決策 20 的四段不變，只有出發這一段擴充。`.waitingAtStop(i, cycle: k)` 在 `departure(i) + k × period <= T` 時離開：
  1. 第 `i` 站標記 `reverses` 時，先在原地折返。等待中的列車一定停在節點上、沒有剩下的 continuation，所以只改變朝向。
  2. 決定下一個停靠：
     - 通常是同一輪的第 `i + 1` 站。
     - 最後一站之後，重複的時刻表接第 `k + 1` 輪的第 0 站，前提是那一輪的時刻都放得下：`最後一站的 departure + (k + 1) × period <= Int64.max`。
  3. 沒有下一個停靠時服務完成，列車留在原地（有折返就已折返）。這發生在只跑一次的時刻表的最後一站，以及重複時刻表最後一輪的最後一站。
  4. 否則照決策 20 求路到下一個停靠的車站：
     - 空路徑是零距離到達；
     - 非空路徑成為 continuation；
     - **沒有路時整次出發都不發生，列車也不折返**。之後的步長再試，屆時會先再折返一次。所以求路失敗不會讓列車停在反方向，也不會每分鐘來回轉向。
- **零距離到達的連鎖**
  - 在決策 20，連鎖最多到時刻表的最後一站。
  - 重複的時刻表如果所有停靠都在同一個車站（或共用的月台），而且列車誤點，連鎖可以一直繞下去。
  - 所以每台列車在一個出發段**最多離開時刻表站數那麼多站**：
    - 只跑一次的時刻表不受影響，它本來最多就離開這麼多站；
    - 重複的時刻表最多走一整輪，剩下的在下一步繼續。
  - 這樣 `advance` 一定會結束，「有改變就不快轉」的捷徑也仍然精確。
- **到達**照決策 20，帶著同一個 cycle。
- **核心規則不變**：每一輪都照決策 20 執行：不早於排定出發離開、不另加停留、每步最多移動一次、不跳站。誤點的列車也不跳過輪次，而是靠時刻表的餘裕追回（`TrainRepeatTests` 有逐分鐘的例子）。
- **事件感知的快轉**：下一個出發時刻改用該輪的時刻（`departure + cycle × period`）。其他推論與決策 20 相同：一步沒有任何改變時，下一個出發時刻之前也不會有改變。
- **存檔（Swift `Codable`）**
  - 只在用到時寫入：列車有週期時寫 `"period"`，停靠要折返時寫 `"reverse": true`，服務到了第 1 輪以後寫 `"cycle"`。
  - 因此沒有用到這些功能的世界，存檔與 Stage Q1 之前逐位元相同；舊存檔讀成只跑一次、不折返、第 0 輪。
  - 一律拒絕：明確的 `null`、非整數或負數的週期與輪次，以及非布林值的 `reverse`。
  - `Train` 解碼檢查：
    - 時刻表與週期必須合法，規則同 `setTrainTimetable`；
    - 輪次大於 0 時必須有週期，而且那一輪的時刻放得下；
    - 前往第 0 站的 `travelling` 只允許在第 1 輪以後，也就是從上一輪最後一站回到第一站的行程。
  - `GameWorld` 解碼照決策 20：等待中的列車停在該站的車站；行駛中的列車，行程終點緊鄰該站的車站格。
  - 壞資料一律拒絕，不修正週期、輪次或折返。仍不建立存檔版本或 migration。
- **Golden scenarios**：schema v10 新增：
  - 停靠的 `reverse`；
  - `setTrainTimetable` 與最終狀態的 `repeat`（`once` 或 `every`）；
  - 服務的 `cycle`；
  - `train-repeat.json`。

  既有的 9 個 fixture 只加上中性的值：`"reverse": false`、`"repeat": { "type": "once" }` 與 `"cycle": 0`。其他預期值都沒有改變。
- **驗證**
  - `TrainRepeatTests` 以手算的預期值，驗證折返、重複、開始的輪次、最後一輪、連鎖的上限、批次推進與存檔。
  - `ServicePropertyTests` 新增 `service.repeating`：產生的時刻表部分停靠會折返、多數會重複，也有不合法的週期。每一步都在 GameCore 與 `ReferenceWorld` 上比較，並檢查整批推進與逐 tick、2× 與 1× 的結果相同。`ReferenceWorld` 用加法而非減法檢查週期，每次用到時都重新計算該輪的時刻。
  - `SaveMutationTests` 新增 `save.repeatMutation`。
  - Stage I–P 的 property digest（`kernel.differential`、`timetable.differential`、`service.differential`、`route.reference`、`stationStop.routes` 等）在修改前後相同。
- **GamePresentation**：只更新 `invalidTimetable` 的訊息。App 沒有修改，因為還沒有時刻表的畫面（Stage R）。
- **已知限制**
  - 週期是整數分鐘，沒有日曆，也不分平日與週末。
  - 時段、班距與多台列車的路線服務屬於 Q2；區間車與快慢車屬於 Q3。
  - 誤點超過一個週期的列車會照順序把每一輪跑完，不會取消班次。之後若需要取消落後的班次，再另外決定。
  - 停止服務後重新啟動，只能從第 0 站開始。
  - 列車之間仍然互不阻擋，要到 Phase 4.6 才處理。
- **本 Stage 不做**：自動折返、服務模式與路線（Q2）、區間車與停站模式（Q3）、取消班次、時刻表畫面（Stage R）、車廠，以及佔用與進路（Phase 4.5、4.6）。

### 22. 服務路線：資料與推導（Phase 4 Stage Q2a）

Stage Q2 把網頁參考遊戲捷運模式的營運方式移植過來：時段 × 上線列車數，班距由系統推導（[網頁參考研究](WEB_REFERENCE_STUDY.md)）。

和 Stage O、P 一樣拆成兩步：
- **Q2a（本決策）**：只建立路線的資料契約與推導查詢，路線不派車、不影響任何列車。
- **Q2b**：自動派車。

Stage I–Q1 的契約都不變。

- **移植的規則**（整數分鐘；「參考」指參考遊戲的做法）：
  - **時段**：參考把一天分成三個等級。尖峰 07:00–10:00 與 16:00–20:00；低峰 00:00–07:00 與 21:00 起；其他是離峰。
    - 這成為新世界的 `ServiceDay.standard`，存在世界裡，可以用 `setServiceDay` 改。
    - 研究文件列為「不採用」的是寫死在核心的時段，所以這裡讓它可以修改。
  - **營運時間**：參考預設 06:00 開始、24:00 結束，最晚可以到次日 06:00（`1800`）。開始時間之前的分鐘算作隔天的。這成為 `ServiceWindow`；新路線是 06:00–24:00，也可以全天營運。
  - **來回時間**：參考的公式是「各區間行駛時間 × 2 + 中間站停留 × 2 × (站數 − 2) + 終點停留 × 2」，停留是 36 秒與 42 秒。
    - 這裡的區間行駛時間由實際路徑推導：連結數 × 1024 ÷ 路線的 `rate`，無條件進位成整數分鐘。去程與回程分開求路，所以兩者可以不同。
    - 停留改成整數分鐘：中間站 1 分鐘，終點站 2 分鐘（多 1 分鐘給折返）。
  - **最多列車數**：參考的最短班距是 1.5 分鐘，並以二分搜尋找出「來回時間 ÷ 列車數 ≥ 最短班距」的最大列車數；來回時間連一台都不夠時是 1。
    - 這裡的最短班距取整數 2 分鐘，最多列車數化簡成 `max(1, 來回時間 / 2)`。`ReferenceWorld` 保留參考的二分搜尋寫法，交叉驗證兩者相同。
  - **實際列車數與班距**：一個等級實際跑的列車數是設定的數量，但不超過最多列車數。班距是 `來回時間 ÷ 列車數`，無條件進位；沒有列車就沒有班距。
- **資料模型**
  - `ServiceLine`（`LineID`，世界依序配發，刪除後不再使用）包含：
    - `name`；
    - `stops`：至少兩站，同一個車站不連續出現；
    - `rate`：至少 1，新路線是 1024，也就是每分鐘一個連結；
    - `window`；
    - `trainsInService`：各等級的列車數，不可為負。
  - `GameWorld.serviceDay`：所有路線共用，由一段一段組成，從分鐘 0 開始、嚴格遞增。
- **推導**：都不存檔，每次由地圖重新推導，與連通、路徑、停站一樣。
  - `serviceLevel(of:at:)`
  - `lineJourney(_:)`
  - `lineMaximumTrains(_:)`
  - `lineTrainsInService(_:at:)`
  - `lineHeadway(_:at:)`
- **行程（`lineJourney`）**
  - 參考遊戲的路線是一條幾何折線，但這裡的路線只是車站的順序，列車實際怎麼走要由地圖決定。
  - 所以行程的定義是「列車會怎麼開」：從第一站的月台出發，依序以 `route(from:toStation:)` 求路；到最後一站原地折返（決策 14 的反向），再依相反順序回到第一站。
  - 起點會試遍第一站的每個月台與四個朝向，取來回時間最短的，同樣短時取最先的。
  - 任何一段沒有路時沒有行程。之後的查詢也都沒有答案，而不是回傳 0。
- **為什麼折返是固定的**：去回兩端一律原地折返，這是網頁參考非環狀線的行為。環狀線（不折返、繞一圈）留到之後（決策 49 加入）。
- **指令**：都免費。
  - `createLine(named:stops:)` 的檢查順序：`invalidName` → `invalidLineStops` → `unknownStation`（第一個不存在的車站）→ `idsExhausted`。
  - `removeLine`、`setLineStops`、`setLineRate`、`setLineServiceWindow`、`setLineTrainsInService` 先檢查 `unknownLine`，再檢查自己的值。
  - `setServiceDay` 只會丟出 `invalidServiceDay`。
  - 設定的列車數照原樣保存，即使超過最多列車數，所以之後地圖變動讓行程變長時，設定仍然有效。
- **存檔**
  - 只在有值時寫入：
    - `"lines"`：有路線時；
    - `"nextLineID"`：建立過路線時（即使全部刪除了，也要記住，避免 ID 重複使用）；
    - `"serviceDay"`：不是標準的服務日時。
  - 因此沒有路線的世界，存檔與之前逐位元相同；舊存檔讀成沒有路線、ID 從 1 開始、標準的服務日。
  - 一律拒絕：明確的 `null`，以及不合法的路線、營運時間、列車數或服務日。
  - 世界解碼另外確認：路線 ID 唯一、遞增、小於 `nextLineID`；名稱合法；每一站都存在。
- **Golden scenarios**：schema v11 新增：
  - 7 個指令、6 個結果、5 個觀察；
  - 最終狀態必填的 `lines` 與 `serviceDay`；
  - `service-line.json`。

  既有的 10 個 fixture 只加上 `"lines": []` 與標準的服務日。
- **驗證**
  - `ServiceLineTests` 以手算的預期值驗證指令、服務等級、行程（包括「最先的起點不是最短時，選最短的」）、列車數、班距與存檔。
  - `ServiceLinePropertyTests`（`line.differential`）讓產生的指令序列同時在 GameCore 與 `ReferenceWorld` 上執行：
    - 指令是鋪軌、拆軌與列車操作，混合路線指令，其中刻意包含不合法的值；
    - 每一步比較所有路線的等級、行程、列車數與班距；
    - `ReferenceWorld` 另外寫成：營運時間分成一段或兩段檢查，時段從頭掃描，每段分鐘數用 `(單位 − 1) / rate + 1` 計算，最多列車數用參考的二分搜尋。
  - Stage I–Q1 的 property digest 在修改前後相同。
- **GamePresentation**：只為六個新錯誤加上 `playerMessage`。App 沒有修改，路線畫面屬於 Stage R。
- **已知限制**
  - 環狀線還沒有做（決策 49 加入）；區間車與快車在 Q3 加入（決策 24）。
  - 平日與週末不分，也沒有日曆。
  - 行程是規劃值：實際列車的 rate 可能不同，誤點由 Stage P 的規則吸收。
  - 行程查詢每次要求路最多 16 × 2 ×（站數 − 1）次；還沒有快取，畫面若頻繁詢問，之後量測後再考慮。
  - **最多列車數假設上下行互不干擾**，等於把路線當成雙線：只要間隔 2 分鐘，就能一直發車。單線區段的列車只能在交會站錯車，實際能跑的列車會比這個值少。目前列車互不阻擋，所以和現在的規則一致；Phase 4.5、4.6 加入佔用、進路與交會時，要一併修正這個上限（真實時刻表的研究見 [TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）。
- **本 Stage 不做**：派車、把列車指派給路線、依時段增減列車、到終點才退出（Q2b），以及路線畫面（Stage R）。

### 23. 自動派車與目標班距（Phase 4 Stage Q2b）

Stage Q2b 讓決策 22 的路線真正跑起來：路線把指派給它的列車，一趟一趟地從第一站派出去。每一趟都是決策 20、21 的一般服務，所以執行、誤點、折返與存檔的規則都不變；本決策只加入「誰、何時、帶著什麼時刻表出發」。

- **為什麼這樣做**
  - [網頁參考研究](WEB_REFERENCE_STUDY.md)的捷運模式（已對原始碼確認）：時段改變時重新計算上線列車數。
    - 減車：多出的列車標記為「到終點站後退出」，跑到下一個終點（兩端皆可）就移除；之後又要增車時，先取消這些標記。
    - 增車：新車直接出現在線上最大的空檔，不是從車廠開出。
    - 這裡的列車是買來、實體放在鐵軌上的（決策 14），不能憑空出現或消失，所以改成：減車時列車跑完這一趟、回到第一站停下；增車時只派已經停在第一站的列車（研究文件列為「不採用」的就是憑空出現）。
  - [真實時刻表研究](TIMETABLE_DATA_STUDY.md)：真實路線通常先定班距（例如每小時一班），多出來的時間讓列車在終點站等；支線的班距比幹線長很多。只用「列車數推導班距」表達不了「1 台車、來回 45 分鐘、每小時一班」。所以兩種方式都支援：預設用列車數，各等級可以另外設定目標班距。
  - 派出的每一趟都是有限、具體的時刻表，由 Stage P 的核心執行，符合 Stage Q 的方針：服務模式產生班次，交給既有的執行核心。
- **資料模型**（都在 `ServiceLine` 上）
  - `targetHeadways: TargetHeadways`：各等級的目標班距（分鐘），`nil` 表示該等級用 `trainsInService` 的列車數。目標是 2…1440 分鐘。
  - `trains: [TrainID]`：指派給路線的列車，依 ID 遞增。一台列車最多屬於一條路線。
  - `lastDispatch: GameTime?`：上次從第一站派車的時刻。
- **每個等級跑幾台、班距多少**（`lineTrainsInService`、`lineHeadway` 一併更新）
  - 沒有目標：列車數是設定值，但不超過最多列車數；班距是 `來回時間 ÷ 列車數`，無條件進位（與決策 22 相同）。
  - 有目標 `H`：列車數是 `來回時間 ÷ H` 無條件進位，也不超過最多列車數；班距是 `H`，但若列車數被最多列車數截斷，就取 `來回時間 ÷ 列車數`（無條件進位）與 `H` 較長的一個。
  - 例：來回 12 分鐘，目標 20 → 1 台，每 20 分鐘一班，列車在第一站等 8 分鐘；目標 5 → 3 台，每 5 分鐘一班。
- **指令**（都免費，失敗時世界不變）
  - `setLineTargetHeadways(_:to:)`：`unknownLine` → `invalidHeadway`。
  - `assignTrain(_:to:)`：`unknownTrain` → `unknownLine` → `trainOnLine`（已經屬於某條路線，包括同一條）→ `trainServiceActive`（正在跑自己的服務，要先停止）。列車放置與否、在哪裡都可以；只有停在第一站的列車才會被派出。指派本身只改變路線的列車清單。
  - `unassignTrain(_:)`：`unknownTrain` → `trainNotOnLine`。只結束指派：正在跑的這一趟保留時刻表，繼續當一般服務跑完，之後可以像一般服務一樣停止。
  - `removeLine` 同樣只結束指派，列車跑完這一趟。
  - **路線擁有列車的時刻表與服務**：屬於路線的列車，`setTrainTimetable`、`startTrainService`、`stopTrainService` 在 `unknownTrain` 之後丟出 `trainOnLine`，早於原本的其他檢查。閒置時仍可手動移動、反向、取下、放置與設定 rate，玩家才能把列車開到第一站。
- **一個基本步長**：決策 20 的四段之前加上第 0 段 **派車**，依 `LineID` 遞增處理每條路線，每條路線每步最多派一台。路線在 `T` 派車的條件：
  1. `T` 是分鐘 0 以後（時刻表的時間不能是負數）；
  2. 營運時間內，行程可以行駛，而且 `T` 的等級有列車要跑；
  3. 距上次派車已經過了該等級的班距（`上次 + 班距 <= T`）；
  4. 路線的列車中，正在跑服務的少於該等級的列車數；
  5. 有一台**就緒**的列車：沒有服務、已放置、rate 大於 0、停在第一站的車站（決策 18），而且從那裡能開完整個來回。依 ID 取第一台。
- **派出的一趟**
  - 時刻表從列車實際的位置推導，而不是路線的規劃起點：列車照原本朝向，或先原地折返，取來回時間較短的（相同時不折返）；兩種都開不完就不就緒。需要折返時，第一站標記 `reverses`。
  - 時刻：第一站 `T` 到、`T` 離；之後每一站在前一站離開後加上該段的分鐘數到達（路線的 rate，決策 22 的算法）；中間站停 1 分鐘，最後一站停 2 分鐘並折返；回到第一站時到達、折返，服務就此結束，列車在原地等下一次派車。準點的列車在 `T + 來回時間` 時已可再出發（第一站的 2 分鐘終點停留在等待中度過）。
  - 設定時刻表（不重複）與 `.waitingAtStop(0)`，記錄 `lastDispatch = T`，列車在同一步的第 1 段就出發。時刻超出 `Int64` 時不派車。
  - 所以：減車時，回到第一站的列車因為條件 4 不再被派出，就停在那裡（「到終點站後退出」）；增車時只有停在第一站的列車能出發；晚回來的列車讓下一班晚發，但永遠不會早發。
- **事件感知的快轉**：一步沒有任何改變時，時鐘可以跳到下一個出發時刻，或下一個「有就緒列車的路線可能派車」的分鐘，取較早的。後者是：若現在就符合條件就是現在；否則是分鐘 0、`上次 + 班距`、營運時間開或關、服務日換段這幾個時刻中最早的。列車只能因為到達或服務結束才變成就緒，而這兩者都算「有改變」；營運時間、等級與班距只在這些時刻改變。所以仍然精確：`advance(n)` 等於 n 次 `advance(1)`，2× 的一個 tick 等於 1× 的兩個 tick。
- **每次呼叫只算一次**：同一次 `advance` 中沒有指令，地圖、路線的站與 rate、閒置列車的位置都不變，所以每條路線的行程、每台閒置列車的一趟各只求一次（精確的最佳化）。
- **存檔**：只在用到時寫入 `"targetHeadways"`（只列出有目標的等級）、`"trains"`、`"lastDispatch"`，所以沒有用到的路線存檔與之前逐位元相同，舊存檔讀成沒有目標、沒有列車、從未派車。一律拒絕：明確的 `null`、超出範圍的目標、沒有遞增或重複的列車、分鐘 0 以前的派車。世界解碼另外確認：列車存在、不屬於兩條路線、路線的列車不在跑重複的時刻表、上次派車不晚於現在。
- **Golden scenarios**：schema v12 新增 3 個指令、3 個結果、路線必填的 `targetHeadways`、`trains`、`lastDispatch`，以及手算的 `line-dispatch.json`。既有的 11 個 fixture 只把版本改成 12，`service-line.json` 的兩條路線加上中性的值（沒有目標、沒有列車、從未派車）。
- **驗證**
  - `LineDispatchTests` 以手算的預期值驗證：指令與錯誤順序、目標班距的列車數與班距、兩台列車每 6 分鐘一班地來回、朝錯方向的列車先折返、只有就緒的列車會出發、等級改變時的增減車、目標班距讓列車在第一站等待、營運時間與分鐘 0、取回列車與刪除路線、長批次等於逐 tick，以及存檔。
  - `LineDispatchPropertyTests`（`line.dispatch`）讓產生的指令序列同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，並檢查批次與逐 tick、2× 與 1× 相同。`ReferenceWorld` 另外寫成：目標存成以等級為 key 的字典，班距用「現在 − 上次派車」檢查，每分鐘都檢查派車，沒有快轉。
  - `SaveMutationTests` 新增 `save.dispatchMutation`。
  - Stage I–Q2a 的 property digest 在修改前後相同。
- **GamePresentation**：只為三個新錯誤加上 `playerMessage`。App 沒有修改，路線畫面屬於 Stage R。
- **已知限制**
  - 列車之間仍然互不阻擋（Phase 4.6）；同一條路線的列車可能在同一段鐵軌上重疊。
  - 最多列車數仍然假設雙線（見決策 22 的已知限制）。
  - 只從第一站派車；停在最後一站的列車不會從那裡出發。
  - 派車時只看列車停在第一站的哪個月台、朝哪個方向，不會把列車開到規劃的起點。
  - 不設定列車的 rate：rate 為 0 的列車不會被派出，rate 與路線不同的列車會提早或誤點。
  - 平日與週末不分，也沒有日曆。
- **本 Stage 不做**：區間車與快慢車（Q3）、從最後一站派車、依乘客調整班次，以及路線畫面（Stage R）。

### 24. 區間車與停站模式（Phase 4 Stage Q3）

Stage Q3 讓一條路線除了自己的全線站站停服務之外，還能跑其他的**服務模式**（`LinePattern`）：只跑一段的區間車（短程折返），或跳過部分車站的快車。每個模式有自己的列車數或目標班距、自己的列車與派車紀錄，照決策 23 的規則派車。多個服務共用同一段鐵軌時，班次相加後仍要守住最短班距。

- **為什麼這樣做**
  - [網頁參考研究](WEB_REFERENCE_STUDY.md)的捷運模式（已對原始碼確認）：
    - 一條線可以有多個區間車，各有起訖站與各時段的列車數；各區間車的班距由它自己的來回時間推導。
    - 區間車重疊的區段把各自的頻率（列車數 ÷ 來回時間）相加，總和不能超過最短班距的頻率；依序處理，後面的區間車被削減。
    - 快車是從整條線依序挑出的停靠站，至少 2 站，有自己的列車數。
  - 參考遊戲裡快慢車「擁有獨立路權」，快車不和慢車一起算容量。我們的快車和慢車實際共用同一條鐵軌，所以快車也算進它經過的每一段，即使它不停那些站。
  - [真實時刻表研究](TIMETABLE_DATA_STUDY.md)：真實路線同一條線上有區間車與區間快、自強號，快車停靠的是慢車停靠站的子集合。
  - 參考遊戲的區間車**取代**預設的全線區間車，所以要求所有區間車連續覆蓋整條線。這裡路線自己的服務永遠存在、跨越全線，結構上一定覆蓋；可能沒有列車的是某個等級的某一段（例如深夜只跑中間一段的區間車），所以改成推導的查詢：某等級負載為 0 的區段就是沒有覆蓋，交給玩家判斷，而不是拒絕指令。
- **資料模型**
  - `ServiceLine.patterns: [LinePattern]`，順序就是分配容量的順序（路線自己的服務永遠在最前面）。
  - `LinePattern`：
    - `calls: [Int]`：停靠的站，是路線 `stops` 的索引，至少 2 個、嚴格遞增。連續的索引是區間車，跳過的索引是快車通過的站；「區間車」或「快車」只是從 `calls` 看出來的。
    - `trainsInService`、`targetHeadways`、`trains`、`lastDispatch`：和路線自己的服務相同的意義（決策 22、23）。
  - 模式以索引識別；刪除一個模式時，後面的模式往前移一格。
- **行程**
  - 模式的行程從第一個停靠站的月台出發，依 `calls` 求路到下一個停靠站，在最後一個停靠站折返，再依相反順序回來。和決策 22 相同：起點是每個月台朝四個方向，取來回最短的。
  - 快車到下一個停靠站的路是最短路，不刻意經過跳過的車站。
  - `LineLeg.from`、`to` 仍是路線 `stops` 的索引。
  - 停留：中間的停靠站 1 分鐘，兩端各 2 分鐘；跳過的車站不停。
- **容量**（`lineTrainsInService`、`lineHeadway` 一併更新）
  - 區段 `i` 是路線第 `i` 站到第 `i + 1` 站。每段每天每個方向最多 `segmentCapacity = 1440 ÷ 2 = 720` 班，也就是最短班距 2 分鐘。
  - 一個服務在它從第一個停靠站到最後一個停靠站之間的每一段（停不停都算），加上**負載** `⌈1440 ÷ 班距⌉`：以它的班距跑一整天的班次，無條件進位，所以不會低估。
  - 各服務依序取得容量：路線自己的服務、模式 0、模式 1……。每個服務先照決策 23 算出它單獨時的列車數；然後在不超過這個數字的前提下，取負載在它經過的每一段都放得下（加上前面服務的負載不超過 720）的最多列車數。少一台列車負載不會變大，所以用二分搜尋。放不下任何一台時，這個等級不跑。
  - 列車數減少時，班距照決策 23 重算：`max(目標, ⌈來回 ÷ 列車數⌉)`。
  - 路線自己的服務排第一，而且單獨時的負載一定不超過 720（它的列車數不超過 `來回 ÷ 2`，而來回至少 4 分鐘），所以永遠不會被削減。沒有模式的路線，行為和 Q2 完全相同。
  - 行程無法行駛的服務不跑，也不佔容量。
  - 以整數的每日班數表示頻率，比參考遊戲的浮點數頻率（加上 1e-9 的誤差容許）精確，而且 1440 的因數多，常見的班距剛好整除。
- **指令**（都免費，失敗時世界不變）
  - `addLinePattern(_:calling:)`：`unknownLine` → `invalidLinePattern`（少於 2 個、沒有嚴格遞增、或不是路線的站的索引）。加在最後，沒有列車數、目標與列車；回傳索引。
  - `removeLinePattern(_:at:)`：`unknownLine` → `unknownLinePattern`。它的列車不再屬於路線；正在跑的這一趟繼續當一般服務跑完，和 `removeLine` 相同。
  - `setLineTrainsInService(_:to:pattern:)`、`setLineTargetHeadways(_:to:pattern:)`、`assignTrain(_:to:pattern:)`：`pattern` 為 `nil` 時是路線自己的服務（原本的行為）。錯誤順序在 `unknownLine` 之後插入 `unknownLinePattern`。
  - `setLineStops`：模式保留原本的索引；新的站數讓某個模式超出最後一站時，在原本的檢查之後丟出 `invalidLinePattern`。
  - 一台列車最多屬於一個服務（任何路線的任何服務）；`unassignTrain` 從它所在的服務移除。`assignedLine(of:)` 也找模式，`assignedPattern(of:)` 回傳模式的索引。
- **派車**：決策 23 的第 0 段依 `LineID` 遞增，每條路線依序處理自己的服務、模式 0、模式 1……，每個服務每步最多派一台。條件和決策 23 相同，只是換成該服務的列車數與班距（已經扣掉前面服務的容量）、該服務的列車、該服務的上次派車，以及停在**第一個停靠站**的列車。派出的時刻表只列出停靠的車站。快轉的喚醒時刻也逐一服務計算；前面服務的列車數只在營運時間與服務日換段時改變，所以仍然精確。
- **查詢**：`lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway` 加上 `pattern` 參數；新增 `lineSegmentLoads(_:at:)`，回傳該等級每一段的負載（為 0 就是沒有覆蓋）。
- **存檔**：路線只在有模式時寫入 `"patterns"`，模式只在用到時寫入 `"targetHeadways"`、`"trains"`、`"lastDispatch"`，所以沒有模式的存檔與之前逐位元相同。一律拒絕：明確的 `null`、不合規則的 `calls`（包括超出路線站數）、負的列車數、超出範圍的目標、沒有遞增或重複的列車、分鐘 0 以前的派車。世界解碼另外確認：列車存在、不屬於兩個服務、不在跑重複的時刻表、上次派車不晚於現在。
- **Golden scenarios**：schema v13 新增 `addLinePattern`、`removeLinePattern`，`setLineTrainsInService`、`setLineTargetHeadways`、`assignTrain` 與四個路線觀察可以加上 `"pattern"`（沒有這個 key 就是路線自己的服務），新增 `lineSegmentLoads` 觀察、`invalidLinePattern` 與 `unknownLinePattern` 結果，路線必填 `"patterns"`，以及手算的 `line-patterns.json`。既有的 12 個 fixture 只把版本改成 13，兩個有路線的 fixture 加上中性的 `"patterns": []`。
- **驗證**
  - `LinePatternTests` 以手算的預期值驗證：指令與錯誤順序、`setLineStops` 保留或拒絕、刪除模式、區間車與快車的行程、各段依序分配容量（尖峰時區間車被削到 2 台、快車沒有位置；深夜只覆蓋中間一段）、路線自己的服務不會被削減、無法行駛的模式不佔容量、區間車與快車的派車（快車等到離峰才出發，時刻表只有兩端）、批次等於逐 tick，以及存檔與拒絕。
  - `LinePatternPropertyTests`（`line.patterns`）讓產生的指令序列同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，以及每條路線每個服務的行程、列車數、班距與各段負載。`ReferenceWorld` 另外寫成：每一段都把前面服務的負載重新加總，列車數從單獨時的數字往下數，而不是二分搜尋。
  - `SaveMutationTests` 新增 `save.patternMutation`。
  - Stage I–Q2b 的 property digest 在修改前後相同。
- **GamePresentation**：只為兩個新錯誤加上 `playerMessage`。App 沒有修改，路線畫面屬於 Stage R。
- **已知限制**
  - 列車之間仍然互不阻擋（Phase 4.6）：快車會「穿過」同一段上的慢車，真正的待避與超越屬於 Stage V。
  - 容量只在同一條路線的服務之間分配；不同路線共用鐵軌時不互相限制，要等 Phase 4.5 的軌道資源。
  - 最多列車數與每段容量仍然假設雙線（決策 22 的已知限制）。
  - 快車到下一個停靠站走最短路，不保證經過跳過的車站。
- **本 Stage 不做**：支線、環線、跨線直通、同一路線快慢車之間的轉乘（乘客屬於 Phase 5），以及路線畫面（Stage R）。

### 25. 服務與時刻表畫面（Phase 4 Stage R）

Stage R 讓玩家在 App 裡看到並操作 Stage O–Q3 的時刻表、服務與路線。GameCore 沒有修改。

- **分層**（沿用決策 1、7、17）
  - 顯示的文字與推導（班距的說法、服務的種類、覆蓋缺口、列車的早到或誤點）放在 GamePresentation，只讀 `GameWorld` 的公開查詢，可以在 Linux 上測試。
  - `GameSession` 的新指令（建立與刪除路線、各等級的列車數與目標班距、營運時間、新增與刪除服務模式、指派與取回列車、啟動與停止自己的時刻表）每個只呼叫一個 `GameWorld` 指令；拒絕時顯示 `GameError.playerMessage`，世界不變。
  - 畫面只保存暫時的 UI 狀態：選定的路線 ID、新路線的車站草稿、sheet 是否開啟、新模式的兩端。路線、列車數與時刻都每次從世界讀取。
- **早到與誤點**（推導，不存檔）：停在某站時，超過該站排定出發就是誤點（分鐘數 = 現在 − 排定出發），還沒到排定到達就已經在站上是早到；行駛中超過下一站的排定到達就是誤點。排定時刻包含重複時刻表的輪次。列車不會早於排定出發離開（決策 20），所以行駛中不會早到。Stage W2b 起改由 GameCore 的 `lateness(of:)` 依實際時刻計算（決策 39），畫面只把秒換成整分鐘。
- **服務的種類**從 `calls` 推導：停靠每一站是「All stops」，連續但沒有涵蓋全線是「Short working」，有跳過的站是「Express」，並列出通過的站。
- **細節分級**：每格小於 20 點時只畫鐵軌線、車站標記與列車（`MapScale.detail(forTileSize:)`），減少縮小時的繪圖量與雜訊。只影響呈現，模擬結果與裝置無關（網頁參考研究的結論 4）。
- **App**：HUD 的「Lines」按鈕開啟路線面板（半高 sheet，地圖仍可點選車站）；列車工具顯示所屬服務、下一站與準點狀態。新增的檔案以 XcodeGen 重新產生專案。
- **驗證**：`LineSessionTests` 以手算的文字與世界比較驗證推導與每個 session 指令；`MapScaleTests` 驗證細節分級。SwiftUI 畫面只能在 macOS CI（`ios-build.yml`）編譯與建置，無法在 Linux 驗證。
- **留給之後**：逐站編輯時刻表的畫面、班次預覽的時刻列表、拖曳時隱藏覆蓋層。

### 26. 軌道資源：轉轍器、平面交叉、佔用、區段與股道數（Phase 4.5 Stage S1）

Stage S1 讓鐵軌成為列車可以佔用的資源，並補上真實轉轍器的轉向規則。概念參考真實時刻表研究的「實體鐵路層」（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）：路網由節點與邊組成、轉轍器不能從一支線倒車轉進另一支線、平面交叉只能直行、每段邊是一個資源、單雙線由平行的正線判定。

- **新的鐵軌種類**（`TileType` 新增兩個 case，`TrackLayout` 描述轉向規則）
  - `turnout(connections:stem:)`：三個以上的出口，其中一個是 `stem`。從 stem 可以走到任一支線，從支線只能走到 stem，支線之間不互通。四個出口時是三向轉轍器。
  - `crossing`：四個出口，每個出口只接到正對面：兩條直線交叉而不相接。
  - 原本的 `track(connections:)` 就是 `TrackLayout.open`：每個出口都接到其他出口（只禁止原地掉頭）。**既有的鐵軌、存檔、路徑與 golden 值都不變。**
  - `buildTurnout(at:connections:stem:)`：`invalidTrackConnections`（少於三個出口、有四個方向以外的位元、或 stem 不在出口中）→ `outOfBounds` → `tileOccupied` → `insufficientFunds`；`buildCrossing(at:)`：`outOfBounds` → `tileOccupied` → `insufficientFunds`。兩者都收鐵軌的費用，並以 `removeTrack` 拆除。
  - `Track` 新增 `layout`；`track(at:)`、`tracks` 與相接的判定把三種都當成鐵軌。
- **轉向規則**：`exits(from:facing:)` 回傳列車在某節點、朝某方向時可以前往的相接格，依北、東、南、西排列。規則是：不能原地掉頭，而且該格的 layout 要允許「從列車身後的那一邊進來、從那個出口出去」。列車身後不是該格的出口時（例如放置時朝向沒有出口的一側），不套用 layout 的規則。
  - 路徑搜尋（`route(from:to:)`、`route(from:toStation:)`）、`setTrainContinuation` 的檢查與移動（`TrainMovement.travel`）都改用同一條規則；對 `open` 的鐵軌，答案和之前完全相同。
  - 列車沿著 continuation 前進時，遇到不允許的轉向就停在該節點等待，和前方鐵軌被拆掉時相同（決策 15）。
- **佔用資源**（推導，不存檔）
  - `TrackResource`：`node`（鐵軌格；平面交叉是一格，兩個方向共用它）或 `link`（相鄰兩格之間的連結，較北、同列較西的格在前）。
  - `occupiedResources(of:)`：列車站在的格，或所在的連結。列車還沒有長度（Stage S2），所以每台列車佔用一個資源。
  - `occupancyConflicts()`：兩台以上列車佔用同一資源的清單。列車之間仍然互不阻擋，這只是唯讀的查詢，給 Phase 4.6 的進路預約與 movement authority 使用。
- **區段**：`trackSections()`。區段是兩個分岔點之間的一串連結，內部的格都是只接兩格的一般鐵軌；分岔點是轉轍器、平面交叉，或相接格數不是 2 的一般鐵軌（包括端點）。每條連結恰好屬於一個區段。沒有分岔點的環狀線是一個 `isLoop` 的區段。順序見 API 文件，只由地圖決定。
- **股道數**：`parallelTracks(between:and:)` 是兩站月台之間不共用任何連結的路徑最多幾條（最大流，每條連結容量 1），忽略轉向規則與列車：0 是不相連，1 是單線，2 以上是雙線或更多。`lineTrackCounts(_:)` 回傳路線相鄰兩站之間的股道數，Stage V 修正路線容量時使用（決策 22 的已知限制）。
- **存檔**：`TileType` 的新 case 以既有的方式編碼（`{"turnout": {"connections", "stem"}}`、`{"crossing": {}}`），沒有新種類的存檔逐位元不變。地圖解碼拒絕不合規則的轉轍器。
- **Golden scenarios**：schema v14 新增 `buildTurnout`、`buildCrossing` 指令，`exits`、`occupancy`、`conflicts`、`trackSections`、`parallelTracks` 觀察，最終狀態的鐵軌必填 `layout`，以及手算的 `track-resources.json`。既有的 13 個 fixture 把版本改成 14，85 條鐵軌加上中性的 `"layout": { "type": "open" }`。
- **驗證**
  - `TrackResourceTests` 以手算的預期值驗證：建造的錯誤順序與費用、轉轍器與平面交叉的轉向、路徑與 continuation、改成轉轍器後停在轉轍器等待的列車、佔用與衝突、區段（包括環狀線）、股道數，以及存檔與拒絕。
  - `TrackResourcePropertyTests`（`track.resources`）：把產生的路網中的分岔隨機改成轉轍器或平面交叉，讓列車穿過它們，同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，以及每格每個方向的出口、佔用、衝突、區段與每對車站的股道數。`ReferenceWorld` 另外寫成：轉向規則是允許的（進、出）配對表，區段由連結的 union-find 得到，股道數用深度優先的增廣路徑。另外檢查每條連結恰好在一個區段、區段內部都是一般鐵軌。
  - `SaveMutationTests` 新增 `save.trackMutation`。
  - 刻意把轉轍器改成支線互通時，campaign 在前幾個 case 就失敗（驗證後還原）。
  - Stage I–Q3 的 property digest 在修改前後相同。
- **GamePresentation / App**：格子說明加上轉轍器與平面交叉；地圖畫出轉轍器（在 stem 那一側加一條橫槓）與平面交叉（中央一個方塊，兩條直線不相接）。建造轉轍器的畫面留待之後。
- **本 Stage 不做**：阻擋、進路預約與 movement authority（Phase 4.6）、列車長度與月台（S2）、依股道數修正路線容量（Stage V）、建造轉轍器與平面交叉的畫面。

### 27. 車站設施與列車長度（Phase 4.5 Stage S2）

Stage S2 讓車站可以佔多格、列車可以有多節車廂，停站也開始看整列車有沒有在月台邊。概念參考真實時刻表研究的「月台與編組」（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）：月台有實際的長度，編組有節數，列車要整列在月台內才算停妥。

- **多格車站**
  - `extendStation(_:to:)`：讓車站長到它某一格旁邊（正北、正東、正南、正西）的空格上，收一座車站的費用。檢查順序：`unknownStation` → `outOfBounds` → `tileOccupied` → `invalidStationTile`（不在車站任何一格旁邊）→ `insufficientFunds`。
  - `Station.annexes` 依長出的順序記錄新增的格，`Station.tiles` 是原本的格加上 annexes。每一格都是地圖上該站的格。
  - 月台是每一格車站正北、正東、正南、正西的鐵軌格，依車站的格、再依方向排列，重複的只列一次。停站、服務的到達與路徑都看整座車站的月台。
  - `platformTracks(of:)`：把月台依鐵軌相接分組，每組是一條月台股道，組內的格數就是月台長度（以格計）。車站兩側都有鐵軌時是兩條月台股道。
- **列車長度**
  - `Train.cars`：1 到 16 節，每節一格，新購的列車是 1 節。`setTrainCars(_:to:)` 只能在列車不在軌道上時設定，免費：`unknownTrain` → `invalidTrainLength` → `trainAlreadyPlaced`。
  - 列車的位置仍然是車頭（第一節的中心）。第二節以後每節往後一個連結，所以 `length` = (節數 − 1) × 1024，`tileCount` = 節數。1 節的列車沒有車身，行為和之前完全相同。
  - 長度是整數個連結，所以停在節點的列車原地反向後仍然停在節點。這是刻意的選擇：如果每節只有半格，奇數節的列車反向後車頭會落在兩格之間，就不能停站，路線也無法再派出它。
- **車身（trail）**
  - 分岔處無法從地圖推導車身在哪條線上，所以列車存 `trail`：車頭後方車身經過的節點，由近到遠，到第一個位於或超過車尾的節點為止。在節點的列車從它身後那一格開始；在連結上的列車從連結的 `from` 端開始。
  - 放置時，從車頭沿列車可能開來的方向往回走，分岔時選北、東、南、西第一個可走的方向。在節點的列車一定是從身後那一格開來的（和開到那裡的列車一樣），所以車身永遠在它的出口之外，列車不會開進自己的車身。後方鐵軌不夠長時拒絕（`invalidTrainPosition`）。
  - 車頭移動時，車身跟著經過的節點前進。
  - 反向時，車頭移到車尾的位置，面向離開原車頭的方向，車身沿同一段鐵軌往原車頭延伸。從節點出發的長列車反向後仍在節點；在連結上的長列車反向後也在連結上，反向兩次會回到原位。
  - 車身下的鐵軌不能拆（`trackInUse`），所以車身永遠在相接的鐵軌上、轉向合法。
  - 取下列車時清空車身，節數保留。
- **停站**
  - 停站的判定不變：車頭停在月台格中心、沒有剩下的 continuation。
  - `stationsBesideWholeTrain(_:)`：停在該站，而且車身經過的每一格都是該站的月台，也就是整列車都在月台邊。整列在月台邊的長列車原地反向後，車頭仍在月台上。
  - `route(from:toStation:length:)`：到達第一個月台後，長列車再沿著月台往前開，每多一節多走一格，直到車身都在月台邊或月台走完為止。延伸時每一格選北、東、南、西第一個是該站月台的出口。
  - 服務與路線的出發、路線的行程估算（`trip`）都使用長度：長列車折返時車頭移到車尾，並沿月台延伸。行程估算從停在月台的列車開始，每一段都從節點出發。
  - 月台比列車短時，長列車在路線第一站折返後車頭會離開月台，路線就不會再派出它。玩家要把車站加長，這也是月台長度在遊戲中的意義。
- **佔用**：`occupiedResources(of:)` 加上車身經過的連結，以及車身到達或經過的節點。
- **存檔**
  - `Station` 只在有 annexes 時寫入 `"annexes"`，`Train` 只在節數不是 1 時寫入 `"cars"`、有車身時寫入 `"trail"`，所以沒有新資料的存檔逐位元不變。
  - 明確的 `null` 一律拒絕。以下也拒絕：annex 不在前面某一格旁邊或重複、節數超出範圍、車身的形狀不符合節數與位置（數量、相鄰、起點、不回頭）、車身不在相接的鐵軌上或轉向不合法、車站的格和地圖不符。
- **Golden scenarios**
  - schema v15 新增 `extendStation`、`setTrainCars` 指令，`invalidStationTile`、`invalidTrainLength` 結果，以及 `wholeTrainStops`、`platformTracks` 觀察。`routeToStation` 可以加上 `cars`。
  - 最終狀態的車站必填 `annexes`，列車必填 `cars` 與 `trail`。
  - 既有的 14 個 fixture 只改版本，並加上中性的 `"annexes": []`、`"cars": 1, "trail": []`。
  - 新增手算的 `station-facilities.json`，第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過。
- **驗證**
  - `StationFacilityTests`（手算）：
    - 長站的錯誤順序與費用；
    - 月台股道；
    - 節數；
    - 放置與車身、拆軌；
    - 車身跟隨；
    - 反向（節點與連結）；
    - 沿月台延伸、整列在月台邊；
    - 路線派出長列車；
    - 存檔與拒絕。
  - `StationFacilityPropertyTests`（`station.facilities`）：長站、設定節數、放置、送往車站、反向、移動、取下重設、在車身下拆軌，以及派出長列車的路線，同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，以及月台、月台股道、停站、整列停站與佔用。`ReferenceWorld` 另外寫成：車身是帶著與車頭距離的點列，裁切時逐點走距離；反向時沿點列找車尾；延伸時逐格累加；月台股道用標籤擴散求得。
  - `WorldInvariants` 加上車站與車身的規則，`SaveMutationTests` 新增 `save.facilityMutation`。
  - 刻意讓放置選最後一個分岔、或把月台延伸多算一格時，campaign 在前幾個 case 就失敗（驗證後還原）。
  - Stage I–S1 的 property digest 在修改前後相同。
- **GamePresentation / App**
  - 車站工具可以切換成「Grow a station」，讓選取格旁邊的車站長到該格。
  - 列車不在軌道上時可以設定節數。
  - 送往車站時使用列車長度。
  - 停站文字會說明月台太短。
  - 地圖沿車身畫出整列車。
- **留給之後**
  - 依車站等級決定規模：由 GameCore 以外的情境轉換工具處理，放在 Phase 5A。
  - 月台的分配與股道指定（Stage V）。
  - 列車之間的阻擋（Phase 4.6）。

### 28. Topology ≠ Geometry ≠ Rendering（Phase 4.5 起的鐵路核心分層）

產品方向是「以 deterministic 模擬核心為基礎的 360° 3D 鐵道城市建造遊戲」：任意方向的鐵軌、平滑曲線、真正的轉轍器、高架、地下與立體交叉，列車沿著 3D 鐵軌連續行駛。Stage I–S2 的鐵路是方格：節點是格子、連結是相鄰兩格、方向是北東南西，這三件事綁在一起。從 Stage S3 起把它們拆成三層，每一層只依賴下面那一層：

| 層 | 內容 | 權威資料 | 誰可以讀 |
| --- | --- | --- | --- |
| **Topology** | 節點與邊的身分、相接、節點上允許的轉向（轉轍器、平面交叉）、路徑搜尋、佔用與預約的資源身分、月台的綁定點 | GameCore（`TrackNodeID`、`TrackEdgeID`、`TrackTraversal`、`TrackResource`） | 路徑、移動、佔用；之後的 T 進路預約、U movement authority、V dispatcher |
| **Geometry** | 世界座標、任意方向、曲線、長度、之後的縱斷面與結構物、平面上的交叉與淨空 | GameCore（整數的 `WorldCoordinate` 與 `TrackCurve`；取樣、長度、切線都是由整數規則推導） | 建造時的驗證、長度、畫面查詢 |
| **Rendering** | mesh、相機、LOD、插值、動畫 | 不屬於 GameCore；只讀 GameCore 的查詢結果 | 畫面 |

- 交通控制（T/U/V）只讀 topology 與整數長度，**不得**依賴北東南西方向、格子、Canvas、3D 引擎或相機。方格的北東南西只存在於舊的方格 adapter 裡。
- Geometry 在**建造與解碼時**推導一次 topology 需要的東西（邊的長度、節點上哪兩個邊端可以通行），之後的每一個 tick 都不再碰幾何：移動只用整數長度，路徑只用轉向表。
- Rendering 不回寫 GameCore。浮點數只出現在畫面換算。
- 權威資料一律是整數；取樣點、長度、切線是由固定的整數演算法推導出來的值，不存檔（存檔只存端點與控制點），因此不會出現第二份真相。

### 29. 連續軌道幾何（Phase 4.5 Stage S3）——設計決策

這一段是 S3 開工前的架構審查（review gate），回答 12 個問題；實作與驗證的細節完成後補在同一節的後半。

**S3 的兩個里程碑。** S3 分成兩層，後一層只建立在前一層上：

- **S3A — 鐵路網的權威**：`RailwayNetwork` 是唯一的鐵路資料；泛用的節點、邊、行進方向、節點上的轉向規則、資源（span）與查詢介面；方格鐵軌遷移進 `RailwayNetwork`，在它上面得到與以前相同的行為。
- **S3B — 連續幾何**：任意方向、任意長度、平滑曲線與 S 曲線的邊，以及給 renderer 的幾何。

S3B 的實作先寫成（第一版 PR），S3A 的「唯一權威」與 span 在之後的架構要求中補上；兩者的分層以下面的回答為準，驗證也分開列出。

**S3A-1. 鐵路的權威在哪裡？** `GameWorld` 的狀態分成：

- `GridMap`：土地（空地、車站所在的格），之後的地形、分區與粗略的空間索引。它**不再**表示鐵路：`TileType` 只剩 `empty` 與 `station`。
- `RailwayNetwork`：所有鐵軌。方格時代的鐵軌是錨定在格上的節點（`TrackNodeID.tile(p)`，保存它的出口與配置：一般、轉轍器、平面交叉），連續路網是編號的節點與邊。兩者都只存在這裡。
- 車站、列車、路線照舊。

**S3A-2. 舊存檔何時轉成 `RailwayNetwork`？轉換點在哪裡？** 只有兩個轉換點，都是單向的：

- 讀檔：`GameWorld` 的解碼器讀入存檔的 `map.tiles`，土地放進 `GridMap`，鐵軌格變成 `RailwayNetwork` 的方格節點。之後執行期的 `GridMap` 裡沒有鐵路。
- 存檔：`GameWorld` 的編碼器把 `GridMap` 的土地與 `RailwayNetwork` 的方格節點合成存檔裡的 `map.tiles`（相容的序列化格式），所以只有方格的存檔逐位元不變。這是由權威資料推導出的投影，不是第二份資料。

**S3A-3. 指令修改哪一份資料？** 鋪軌、轉轍器、平面交叉、拆軌（方格的舊指令）與建造、拆除節點和邊（路網的指令）都只修改 `RailwayNetwork`；建站、車站長大只修改 `GridMap` 的土地與車站。「格上已經有東西」由兩者一起判斷：方格節點與車站不能在同一格（舊規則），連續路網不佔用任何格（見決策 30 的淨空）。

**S3A-4. 如何避免兩份資料不一致？** 型別上就不可能：`TileType` 沒有鐵路的 case，`GridMap` 無法表示鐵軌；存檔的鐵軌格只在解碼時讀一次、編碼時由網路產生。沒有任何雙向同步。

**S3A-5. 方格節點的身分。** 方格節點的 ID 是 `TrackNodeID.tile(p)`：錨點 `p` 是這個節點不變的名字（方格的鐵軌不會移動，一格最多一個方格節點）。泛用層（路徑、佔用、之後的 T/U/V）把 `TrackNodeID` 當成不透明的值，不讀格子、不讀北東南西；新的建造只產生 `TrackNodeID.node(n)`。

**S3A-6. 邊與資源的身分。**

- 邊（`TrackEdgeID`）是拓撲上的連接：兩端的節點、幾何與整數長度。方格的連結是 `.link(a, b)`，由兩個方格節點互相朝向對方的出口推導；路網的邊是 `.edge(n)`。
- 資源（`TrackResource`）是 `.node(TrackNodeID)` 或 `.span(TrackSpan)`。`TrackSpan` 是一條邊上的一段里程區間（邊、`start`、`end`）。
- **一條邊可以有很多個 span**：預設把邊等分成最少段、每段不超過 `RailwayNetwork.spanLength`（1024，一格）：段數 n = ⌈L ÷ 1024⌉，第 k 個分界在 ⌊k·L ÷ n⌋。方格的連結恰好是一個 span，所以 S1 的資源不變；一條 2 公里的邊是 125 個 span，第一台列車不會鎖住整條邊。
- 之後的分界可以來自轉轍器、平面交叉、月台端點（S4）、號誌與閉塞、營運區段；T 只要加分界，不必改幾何或邊。
- 佔用與預約只讀邊的整數里程與分界，不讀 renderer 的取樣：列車佔用它車頭到車尾之間經過或到達的節點，以及有一點嚴格落在區間內的 span。

**S3A-7. 路徑。** 路徑的成本是整數的長度總和（不是邊數），同長時依出口順序決定；結果是 `TrackTraversal` 的序列，不含控制點。方格上每條連結都是 1024，所以結果與舊的廣度優先搜尋相同。交通狀態、限速與轉轍器的額外成本留給 V/W。

**S3A-8. 列車。** 方格上的列車保留舊的位置與 continuation（`atNode`、`onLink`、`[GridPosition]`），它們是方格節點上的相容表示，不是鐵路的第二份資料；路網上的列車用 `onEdge` 與邊的序列。泛用查詢讓交通控制不必分辨兩者：`occupiedResources(of:)`（資源）與 `pathAhead(of:)`（列車之後要進入的 `TrackTraversal`）。把方格列車也改成 `onEdge` 需要重寫 J–S2 的行為與參考模型，不在 S3 做。

**1. 權威的幾何表示是什麼？**
連續路網（`RailwayNetwork`）與舊的方格並存。一條邊（edge）的權威資料只有：起點節點、終點節點，以及 `TrackCurve`：`straight`（直線），或 `cubic(control1, control2)`（兩個整數平面控制點的三次 Bézier）。節點的權威資料只有位置（`WorldCoordinate`）。其餘一切（取樣折線、長度、某個距離的位置與切線、節點上的轉向）都由固定的整數演算法推導。S3 只有水平線形；S4 另外加上沿里程的縱斷面，不改變水平線形。

**2. 為什麼不選其他候選？**（8 項準則）

| 準則 | A 浮點 spline | B 純整數折線 | C 圓曲線＋緩和曲線 | D 方格／固定零件 | **E 整數控制點 Bézier（採用）** |
| --- | --- | --- | --- | --- | --- |
| 1. 跨平台逐位元相同 | ✗ | ✓ | △（需要定點三角函數） | ✓ | ✓ |
| 2. 整數存檔、可移植 fixture | ✗ | ✓ | △ | ✓ | ✓ |
| 3. 360° 任意方向 | ✓ | ✓ | ✓ | ✗（8 或 16 方向） | ✓ |
| 4. 平滑曲線與一段內的 S 曲線 | ✓ | ✗（只有折角，曲線要很多節點） | ✓（曲率最好） | △ | ✓（切線連續，一段就能反曲） |
| 5. 長度確定、位置查詢便宜 | ✗ | ✓ | △（弧長公式要超越函數） | ✓ | ✓（建造時取樣一次，查詢 O(log n)） |
| 6. 之後的 spline 編輯器與 mesh | ✓ | △ | △ | ✗ | ✓（Bézier 是編輯器與 renderer 的共通語言） |
| 7. 移植到其他語言／引擎 | ✗ | ✓ | ✗ | ✓ | ✓（整數 Bernstein 多項式與整數平方根，數十行） |
| 8. 溢位安全、驗證簡單 | △ | ✓ | ✗ | ✓ | ✓（座標有界，Int64 範圍可證明） |

E 的弱點是曲率不固定，行駛曲線（Stage W）的曲線限速要由取樣推導；需要時再給 `TrackCurve` 加一個整數的圓弧 case，topology 不受影響。

**3. 定點刻度？**
- 1 單位＝既有的邏輯單位（`rate`、`offset` 用的單位），一格邊長 1024 單位；名目上 1 單位 = 1/64 公尺（一格 16 公尺），只給 renderer 與坡度換算用，模擬不依賴公尺。
- 軸向：x 向東、y 向南（與方格相同）、z 向上。方格 (x, y) 的中心是世界座標 (1024x + 512, 1024y + 512, 0)，所以方格與連續路網共用同一個世界座標系。
- 型別層級：每個分量的絕對值不超過 2^29（`WorldCoordinate.limit`）；世界層級：路網的點都在地圖範圍內（0 ≤ x < 寬 × 1024，0 ≤ y < 高 × 1024）；S3 的 z 一律是 0。
- 可證明的界限：差值 ≤ 2^30、平方 ≤ 2^60、三個平方的和 < 2^62、Bernstein 加權和 ≤ 2^30 × 2^29 = 2^59，全部在 `Int64` 內，不需要 `Int128`。

**4. 邊的長度如何確定？**
- 直線：`round(√(dx² + dy²))`，以整數平方根計算。
- 三次曲線：取樣數 N 是 2 的冪次，不小於控制多邊形長度 ÷ 64（無條件進位），限制在 8…1024；第 i 個取樣點是 Σ Bernstein 權重 × 控制點 ÷ N³ 的精確整數值，以四捨五入（half up）取整；連續相同的點去掉；長度是各段 `round(√(dx² + dy²))` 的總和。
- 長度與取樣都在建造與解碼時推導，不存檔；golden fixture 釘住數值，其他語言必須得到同樣的整數。
- 長度是水平里程（chainage），這也是移動用的權威長度；S4 的坡度不改變它（坡度 3.5% 時與 3D 弧長相差不到千分之一）。

**5. 列車的前進如何表示？**
- 不刪除 `TrainPosition`：新增 `onEdge(TrackTraversal, offset:)`，`TrackTraversal` 是一條邊加上行進方向（`forward` 從 `from` 到 `to`，`backward` 相反），`offset` 是從這個方向起點量起的距離，`0 ≤ offset ≤ 長度`。舊的 `atNode`、`onLink` 完全不變。
- 路網上的 continuation 是依序要進入的邊（`TrainMovement` 新增的 `edges`），cursor 與方格共用同一個欄位與規則。
- 移動 kernel 只用整數長度；邊不假設是 1024。移動永遠不會停在 offset 0。
- 唯一表示：有車身的列車 offset 一定大於 0（在節點時寫成「沿著剛走完的邊到達終點」），所以反向兩次一定還原。只有一節的列車可以停在 offset 0（面向一條邊的起點，例如在盡頭反向後）。

**6. 車身如何跨越多條邊？**
- 以路徑歷史表示：`Train.trailEdges` 是車頭所在邊之後、車身經過的邊，由近到遠，恰好到車尾所在的那一條為止（最少的邊數）。存的是邊而不是節點，所以兩個節點之間的平行邊不會有歧義。
- 車尾位置、車身區間、佔用資源都由邊長推導；反向時車頭移到車尾，車身沿同一段鐵軌往原車頭延伸，反向兩次還原。
- 列車長度（`Train.length`，車頭到車尾的中心距離）是實體長度，不再等於「格數」：路網上的車尾可以落在一條邊的任何位置。方格仍維持每節 1024（決策 27）。

**7. 舊方格怎麼接上？**
- 方格的鐵軌遷移進 `RailwayNetwork`（S3A）：錨定在格上的節點保存出口與配置，S1/S2 的規則照舊由它們推導。
- 泛用的身分把方格當成一個 adapter：`TrackNodeID.tile(p)`、`TrackEdgeID.link(a, b)`（長 1024，幾何是兩格中心之間的直線，轉向用 `exits(from:facing:)`）；連續路網是 `TrackNodeID.node(n)`、`TrackEdgeID.edge(n)`。
- 泛用查詢（邊的資訊、`transitions(after:)`、到節點的路徑、佔用資源、車身路徑）同時接受兩種。
- 方格的路徑搜尋改用與路網同一個最短路徑搜尋；方格的結果不變，由既有的 property digest 證明。
- 只有方格的存檔逐位元不變。

**8. 月台如何從「格子旁邊」轉到路網？**
S2 的月台（車站格旁的鐵軌格）照舊服務方格。S4 讓車站在路網上綁定月台：一條邊上的一段區間（邊、起訖距離、長度、層），整列車都在區間內才算停妥；層（level）留給 Phase 5F 的步行轉乘成本。S3 不做月台綁定，路網上的列車只能手動操作。（S5 之後路網上的列車也能停站、跑時刻表與路線，見決策 31。）

**9. 交叉與相接如何區分？**
- 只有**共用的節點**會相接。兩條邊在平面上交叉、但沒有共用節點，就不相接、不共用資源、路徑也不會從一條轉到另一條（S4 再決定這種交叉在同一高度是否允許，以及立體交叉的淨空）。
- 節點上哪兩個邊端可以通行，在建造與解碼時由邊端的切線推導一次，存成 topology：兩個邊端離開節點的方向相反、夾角誤差在 1:16（約 3.6°）以內才相通。轉轍器（一個邊端通往兩個以上）、菱形平面交叉（兩組互不相通的直行）與雙交分轉轍器都由此自然成立，不需要另外的轉轍器旗標，也不會因為拆掉某條邊而讓其他邊的設定失效。
- 路徑、移動與之後的交通控制只讀這張轉向表，不讀切線。
- 兩條線共用一個節點就是平面交叉：那個節點是一個資源，兩個方向的列車共用它，與 S1 相同。

**10. 高程與坡度？**
S3 的 z 一律是 0（地面）。S4 加入：節點的高程、沿里程的縱斷面（平坡、上坡、下坡、拋物線的豎曲線）、以整數（千分比或有理數）表示的坡度與最大坡度、結構物（地面、高架、橋、隧道，隧道口是 topology 的節點）。長度仍是水平里程，S3 的存檔與長度在 S4 不變。

**11. 存檔相容？**
- 新的 key 只在用到時寫入：世界的 `network`、移動的 `edges`、列車的 `trailEdges`、位置的 `onEdge`。
- 方格節點照舊寫在 `map.tiles`（S3A-2 的相容序列化），不另外寫一份。
- S2 的存檔照常讀入；只有方格的存檔逐位元不變，所以 14 個 property digest 都不變。
- 壞的幾何（超出範圍、退化的控制點、尖點、自環、重疊的節點、未知的節點或邊）一律拒絕、不修補；明確的 `null` 拒絕。
- 陣列依 ID 排序，推導值不存檔，所以來回存讀是 deterministic。

**12. PR #31（舊的 Stage T）將來如何移植？**
PR #31 建立在 S3 之前的方格上，暫停、不合併、不 cherry-pick。新的 Stage T 在 S3/S4 之後重寫：
- 保留的語義：
  - 交通控制旗標，新世界預設關閉，舊存檔與 digest 不變；
  - 預約由位置、車身與前方路徑推導，不另存第二份真相；
  - 一次預約到下一個停靠站的整條路；
  - `trackReserved` 的拒絕；
  - 路被佔用時服務在原站等待、每步重試；
  - `trainHoldingRoute`。
- 要重寫的實作：沿 `[GridPosition]` 走出 `.link` / `.node` 的預約，改成走泛用的 `TrackTraversal` 與 `TrackResource`；參考模型改成泛用資源。
- 可以沿用的測試：方格上的手算情境，以及 `traffic.reservation` campaign 的結構。
- 新的 T 依賴：`TrackResource`（`.node(TrackNodeID)` / `.span(TrackSpan)`）、`pathAhead(of:)` 的 `TrackTraversal`、`occupiedResources(of:)`，以及「平面交叉共用節點、立體交叉不共用任何資源」這條規則（決策 30）。預約的範圍是 span，不是整條邊。
- S5 之後（決策 31 第 21 點）：新的 T 直接使用統一好的服務路徑 `TrainPath`（`path(from:toStation:length:)`，方格與路網同一個 canonical route）、`TrackTraversal`、`pathAhead(of:)` 與移動的 `end`（預約到停車位置為止）、`occupiedResources(of:)` 與 span、`TrackPlatform` 與停車位置，以及車身的佔用。T **不負責**路網上以車站為目的地的路、路網的時刻表整合或 LineJourney 的遷移：這些 S5 已經完成，服務與派車在方格與路網上是同一段程式，T 只要在它們交給移動之前加上預約。PR #31 裡沿 `route(from:toStation:length:)` 的格序列預約到下一站的部分，改成沿 `TrainPath.traversals` 預約到 `end`。

**PR #31 的遷移檢查**（逐項對照它的程式碼，唯讀檢視，不修改 PR #31）

| PR #31 依賴的方格表示 | 在哪裡 | 新的 T 改成 |
| --- | --- | --- |
| `GridPosition`：`.node(tile)` 資源、拆軌保護 `reservation(of:).contains(.node(position))` | `reservation(at:trail:length:ahead:)`、`removeTrack(at:)` | `TrackNodeID` 與 `TrackSpan`；拆軌、拆邊都查「有沒有被預約的節點或 span」 |
| `TrackDirection`：`position.ahead` 回傳（格、朝向），預約從那一格開始 | `reservation(at:…)`、`reverseTrain` | `pathAhead(of:)` 的第一個 `TrackTraversal`；折返後的前方由 `reversedOnNetwork` / 方格的 `reversed` 推導 |
| 固定 1024 的連結：`.link(between:and:)` 就是整條連結 | `reservation(at:…)` 逐格加 `.link` | 每條走過的 traversal 的 span（方格連結恰好一個 span，長邊是很多個） |
| `[GridPosition]` continuation 與 `route(from:toStation:length:)` 的格序列 | `setTrainContinuation(_:to:)`、`trainHoldingRoute(of:)`、派車階段 | `[TrackTraversal]`（`route(from:to:)`、`pathAhead(of:)`），方格與路網同一個型別 |
| 節點與連結的 `TrackResource` | 整個 `TrackReservation.swift` | `.node` / `.span`；`Set<TrackResource>` 的比較方式不變 |
| 以格為單位的車身 `trail: [GridPosition]` 與 `Train.distanceBehind` | `occupiedResources(at:trail:length:)`、`bodyResources` | `occupiedResources(of:)`（泛用，路網用 `trailEdges` 與里程），不另寫車身資源 |

- **可以直接沿用的語義**：一次預約到下一個停靠站的整條路（最小的防死結規則）；整批原子取得（任何一個資源被佔就整個拒絕，世界不變）；路被佔時服務在原站等待、每步重試，不折返；衝突回報取編號最小的列車（`reservationHolder`、`firstSharedTrack` 依 ID 順序）；`trafficControl` 旗標只在開啟時寫入存檔、舊存檔讀成關閉；`trackReserved`、`trainsShareTrack` 兩個錯誤；預約由位置、車身與前方路徑推導、不另存第二份真相。
- **可以沿用的測試意圖**：`TrafficControlTests` 的手算情境（持有的資源、開啟時的檢查、各指令的拒絕與拆軌、連結上的反向、等待路徑的服務、存檔）、`traffic.reservation` campaign 的結構與參考模型的寫法（持有者逐一檢查每台其他列車、重疊逐對檢查）、`save.trafficMutation`，以及它的兩個刻意植入的錯誤（預約漏掉前方節點、出發忽略預約）。
- **要重新評估的設計**：
  - 資源身分：span 由邊長與月台推導，新增或移除月台會改變 span（決策 30）；T 存的預約應是邊上的里程區間，或在有預約時拒絕改動月台，不能假設 span 永遠不變。
  - 路徑表示：預約沿 `[TrackTraversal]`；列車所在的邊只預約車頭之後的 span。
  - 拆除保護：方格的 `trackInUse` 與路網的 `trackEdgeInUse` 都要看預約，而且以 span 為單位回報。
  - 預約範圍：到下一個停靠站（或 U 之後的下一個號誌）；長邊不再整條鎖住。
  - 車身資源：一律用 `occupiedResources(of:)` 推導，方格與路網同一條規則。

**S3 不做**：進路預約、movement authority、dispatcher、renderer、行駛動態、城市、乘客、完整的 spline 編輯器與建造畫面；GameCore 只提供最小的開發者 API。

#### 實作

- **型別**（`Sources/GameCore/Geometry/`、`Railway/TrackGraph.swift`、`RailwayNetwork.swift`、`RailwayNetworkTrains.swift`）
  - `WorldCoordinate`（x、y、z）、`PlanPoint`（平面的點，控制點用）、`PlanVector`（沒有正規化的方向）。解碼拒絕超過 `WorldCoordinate.limit` 的值。
  - `TrackCurve`（`straight` / `cubic`）與 `TrackGeometry`（取樣點、到每一點的距離、兩端的切線、`location(at:)` 與 `location(at:going:)`）。
  - `TrackNodeID`（`tile` / `node`）、`TrackEdgeID`（`link` / `edge`）、`TrackEdgeDirection`、`TrackTraversal`。`TrackResource` 改成 `.node(TrackNodeID)` / `.span(TrackSpan)`（S3A）；方格的連結是一個完整的 span，所以方格的資源與順序不變（`.tile(p)`、`.link(between:and:)` 是方便的寫法）。
  - `RailwayNetwork`（S3A，原本的 `TrackNetwork`）：方格的鐵軌（依格位置保存的 `Track`，`track(at:)`、`tracks`），以及依 ID 排序的 `TrackNode`（位置與推導出的 `ends`：每個邊端的方向與可以通往的邊）與 `TrackEdge`（兩端、曲線、推導出的長度），二分搜尋查找。`GridMap` 與 `TileType` 只剩土地（`empty`、`station`）。
  - `TrackSpan`（邊、`start`、`end`）與 `RailwayNetwork.spans(of:length:)`：n = ⌈L ÷ 1024⌉ 段，第 k 個分界 ⌊k·L ÷ n⌋，只由整數長度推導。
- **指令**（都在 `GameWorld`；失敗時世界不變）
  - `buildTrackNode(at:)`：`invalidTrackGeometry`（地圖外、不在地面、已有節點）→ `idsExhausted`。免費。
  - `buildTrackEdge(from:to:curve:)`：`unknownTrackNode`（先 `from` 再 `to`）→ `invalidTrackGeometry`（同一個節點、控制點在地圖外、曲線不成立）→ `idsExhausted` → `insufficientFunds`。費用是每格鐵軌的費用乘上長度的格數（無條件進位，至少 1）；乘積放不進 `Money` 時以 `insufficientFunds(required: Int64.max)` 拒絕。
  - `removeTrackEdge(_:)`：`unknownTrackEdge` → `trackEdgeInUse`（有列車的車頭或車身在上面）。`removeTrackNode(_:)`：`unknownTrackNode` → `trackNodeInUse`（還有邊）。免費、不退款。ID 永不重用，所以 continuation 指向已拆除的邊的列車會停在那條邊之前的節點等待，直到換上新的 continuation。
  - `setTrainContinuation(_:along:)`：方格與路網共用的 continuation 指令，檢查順序同 `setTrainContinuation(_:to:)`。路網上的列車對 `setTrainContinuation(_:to:)` 只接受空陣列（清除）。
  - `placeTrain`、`reverseTrain`、`unplaceTrain`、`setTrainMovementRate`、`advance` 都接受路網上的列車。
- **轉向**：`transitions(after:)` 對方格是 `exits(from:facing:)`，對路網是建造時推導的 `TrackNodeEnd.exits`，依邊的編號遞增；兩者都不讀幾何。
- **路徑**：`TrainRoute.shortest` 是唯一的搜尋：先依距離（Dijkstra）找出最近的目的地距離，再倒著標出能以最短距離到達目的地的狀態，最後從起點每一步取第一個這樣的出口。結果只由規則決定：總長最短，同長時出口序列依各節點的順序逐步比較取最先。方格的每條連結都是 1024，所以與舊的廣度優先搜尋完全相同（`route.reference`、`stationStop.routes` 與所有服務、路線的 digest 不變）。`route(from:to:)` 對 `TrackNodeID` 回傳 `[TrackTraversal]`。
- **移動**：`TrainMovement.travel(along:offset:length:distance:edges:cursor:enter:)` 與方格的 kernel 規則相同，但每條邊用自己的長度；恰好走到終點停下、不看下一項；不可進入時停在終點等待。
- **車身**：放置時從車頭所在邊的起點往回走，分岔時選編號最小、能通往前一條邊的邊；移動時由路徑歷史裁切；反向時車頭移到車尾（`reversedOnNetwork`），車身沿同一段鐵軌往原車頭延伸。
- **佔用**：車頭到車尾之間經過或到達的每個節點，以及與列車有一個共同點、而且那一點不在邊的兩端的每個 span（`networkResources(of:)`）：碰到兩個 span 分界的列車同時佔用兩個。方格的連結只有一個 span，所以方格的結果不變。
- **S3A 查詢**：`trackSpans(of:)`（一條邊的 span，方格連結是一個）與 `pathAhead(of:)`（列車之後要進入的 `TrackTraversal`：方格是 continuation 中剩下的連結，不論現在是否鋪著；路網是剩下的邊，到第一條進不去的為止）。
- **存檔（S3A）**：`GameWorld` 的私有 `SavedMap` 在讀檔時把 `map.tiles` 分成土地（`GridMap`）與方格鐵軌（`RailwayNetwork`），存檔時再合成同樣的格式；鐵軌格的驗證（至少一個出口、轉轍器的規則）從 `GridMap` 移到這裡。`GameWorld` 的不變量另外確認方格的鐵軌只在地圖內的空地上。
- **Renderer 查詢**（唯讀，給畫面用，不寫回）：`trackNode(_:)`、`trackEdge(_:)`、`trackGeometry(of:)`（方格的連結是兩格中心之間的直線）、`location(of:)`、`bodyPath(of:)`。邊建好後不再改變、ID 不重用，所以 renderer 可以依邊的 ID 快取幾何。
- **存檔**：世界只在路網用過時寫 `"network"`（`nodes`、`edges`、`nextNodeID`、`nextEdgeID`），移動只在有路網 continuation 時寫 `"edges"`，列車只在有路網車身時寫 `"trailEdges"`，位置寫成 `{"onEdge": {"edge", "direction", "offset"}}`。長度、取樣與節點的 ends 都不存，解碼時重新推導。解碼拒絕：
  - 超過範圍的座標、同一點的兩個節點、未知的端點、自環、不成立的曲線、ID 未遞增或不小於下一個 ID、明確的 `null`；
  - 路網上的列車帶方格車身、方格 continuation、服務（S5 起接受路網上的服務，見決策 31），或有車身卻在 offset 0；
  - 超出邊的 offset、接不上或多一條、少一條的車身，連續兩次同一條邊的 continuation，從未建過的邊。
  - `GameWorld` 另外確認路網在地圖內、在地面。
- **效能**：模擬的每一步只讀整數長度與建造時推導的轉向表，不做取樣。在這個 Linux 容器的 debug build 上量測（`testGeometryCostIsPaidOnceAndLookupsAreCheap`，只印出不斷言）：取樣 500 條 1024 段的長曲線約 0.2 秒（每條約 0.4 毫秒，只在建造與讀檔時發生）；十萬次位置查詢約 0.06 秒；40 台三節列車在曲線環線上跑 500 分鐘約 0.05 秒。因此 GameCore 只快取長度與轉向表，不快取取樣點；畫面需要時自己依邊的 ID 快取。

#### 驗證

- `ContinuousTrackTests`（手算）：
  - 任意方向的直線（3-4-5 的邊長 5120、45° 的邊長 1448）與位置；
  - 以八分之一取樣、長 396 的四分之一曲線（每個取樣點與每段長度都手算）；
  - 等距控制點的曲線、S 曲線、不合法的幾何與溢位邊界、整數平方根；
  - 指令的錯誤順序與費用；
  - 沒有共用節點的交叉、平面交叉、轉轍器、折角、平行的邊；
  - 方格的 adapter（轉轍器、平面交叉的轉向與 `exits(from:facing:)` 一致，路徑與 continuation 兩種寫法相同）；
  - 在不同長度的邊上前進、等待被拆的邊、長列車跨越多條邊、反向兩次還原、放置的唯一表示、長度不等於邊數或格數；
  - 存檔、只有方格的存檔逐位元不變、壞存檔被拒絕、renderer 查詢。
- `ContinuousTrackPropertyTests`（`network.differential`）：產生共線節點的直線、沿節點方向的曲線與任意曲線組成的路網，放上 2 到 4 台 1 到 4 節的列車，再執行隨機的建造、拆除、放置、反向、路徑、速率與時間推進，同時在 GameCore 與 `ReferenceWorld` 上執行。每一步比較結果、整個狀態、每條邊的長度與取樣點、每個行進方向的轉向、每台列車的位置、移動、車身、佔用與世界座標，以及到抽樣節點的路徑；並檢查不變量與存讀。`ReferenceWorld` 另外寫成：字典、以 de Casteljau 在放大的整數上取樣、二分搜尋平方根、逐單位移動、以沿路徑的絕對距離表示車身、鬆弛法求路。
- `SaveMutationTests` 新增 `save.networkMutation`，`WorldInvariants` 加上 `NetworkInvariants`。
- `RailwayNetworkAuthorityTests`（S3A，手算）：地圖只有土地、鋪軌不改變地圖；方格鐵軌與車站仍各佔一格；以 Stage I 以來的格式寫成的存檔，鐵軌讀進 `RailwayNetwork`、再逐位元寫回；壞的鐵軌格被拒絕；span 的切法（1、396、1024、1025、2048、2560、5120 與 1…5000 的每個長度：首尾相接、每段不超過 1024、長度相差最多 1）；方格連結是一個 span；列車只佔用它所在的 span、在分界上同時佔用兩個；同一條長邊上的兩台列車只在共用 span 時衝突；span 只由長度推導，不看取樣；兩種鐵軌上的 `pathAhead(of:)`。
- S3A 讓 `continuous-track.json` 的四個佔用預期從 `networkEdge` 改成 `networkSpan`，數值手算（見 GoldenScenarios README 的 schema 16）；`ContinuousTrackTests` 的佔用預期也改成 span。
- 刻意植入的錯誤都在前幾個 case 被抓到，驗證後還原：
  - 讓同方向的邊端也相接；
  - 車身多保留一條邊；
  - 長度改用無條件捨去的平方根。
- Stage I–S2 的 14 個 property digest 在修改前後完全相同，所有既有的 golden 預期值不變。
- Golden schema v16 與手算的 `continuous-track.json`，第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過。

#### GamePresentation / App

- `MapScale` 把世界座標換算成地圖座標（一格 1024 單位）；列車的位置、朝向與車身線可以帶入世界，路網上的列車沿中心線畫出。
- 顯示文字：路網上的位置（「Edge #2 forward, 1024 units along」）與新錯誤的訊息。
- 地圖在方格之上畫出路網的俯視 debug 投影（每條邊的取樣中心線與節點），不畫高度；這是 prototype，不是 renderer。
- Debug 的示範配置在東側加上一條由四段曲線組成的環線與一台在上面行駛的三節列車，供在 Debug build 以 `-demo-layout` 啟動時檢視。

#### 已知限制與留給之後

- 高程、坡度、結構物、立體交叉的淨空、隧道口與路網上的月台（Stage S4）。
- 路網與方格不相接，也不做空間衝突檢查：路網的節點可以蓋在任何格上。
- 平面上交叉、同一高度而沒有共用節點的邊目前允許，彼此不影響；S4 決定它們是否需要立體交叉（S4 的決定：必須相差 512 以上，見決策 30）。
- 曲率不固定，曲線限速留給 Stage W。
- 路網上的列車還不能停站、跑時刻表或路線（S4 的月台綁定之後）。S5 已解決，見決策 31。
- 真正的 renderer、建造連續軌道的畫面與 spline 編輯器。
- 方格上的列車仍用 `atNode`、`onLink` 與 `[GridPosition]` 的相容表示（S3A-8）；泛用的交通控制只經過 `occupiedResources(of:)` 與 `pathAhead(of:)` 讀它們。
- span 的分界是等分與月台端點（S4，決策 30）；號誌與閉塞（T 之後）再加分界。

### 30. 立體鐵路與結構物（Phase 4.5 Stage S4）——設計決策

這一段是 S4 開工前的架構審查，回答 S4 的 12 個問題；實作與驗證的細節完成後補在同一節的後半。S4 只加 geometry，不改 S3 的 topology：節點上的轉向、路徑、移動與佔用的規則都不變；唯一碰到資源的是月台的兩端切開 span（第 7 點），佔用的規則本身不變。

**1. 高程如何表示？**
- 節點的 `WorldCoordinate.z` 就是軌面高度，單位與 x、y 相同（名目上 1/64 公尺）。地面是 z = 0；地形之後才有，在那之前「地面」處處是 0。
- 世界層級：節點高度在 `RailwayNetwork.heightRange`（−4096…4096，約 ±64 公尺）之內。S3 的「一律在地面」改成這個範圍。
- 邊沒有自己的高度欄位：兩端的高度由節點給出，中間由縱斷面推導。

**2. 縱斷面怎麼表示？**
- 每條邊的權威資料多一個 `TrackProfile`：起點與終點的**豎曲線長度** `startTransition`、`endTransition`（整數里程，預設都是 0）。
- 高度沿水平里程 s（0…L）推導，R 是兩端的高差，D = 2L − T₀ − T₁：
  - 起點的豎曲線 0 ≤ s < T₀：z = z₀ + R·s² / (T₀·D)（坡度從 0 均勻變到 g）；
  - 中間：z = z₀ + R·(2s − T₀) / D（固定坡度 g = 2R / D）；
  - 終點的豎曲線 L − T₁ < s ≤ L：z = z₀ + R − R·(L − s)² / (T₁·D)。
  - 每一段都是精確的整數分數，四捨五入（half up）一次。
- 兩個豎曲線長度都是 0 時是固定坡度（高差 0 就是平坡）；大於 0 時那一端是平的，拋物線過渡到固定坡度。所以平坡、上坡、下坡與過渡（豎曲線）都是同一個公式的特例，就像 S3 的轉轍器由轉向規則自然成立。
- 限制：T₀、T₁ ≥ 0、T₀ + T₁ ≤ L；平坡的邊沒有豎曲線（唯一表示）。
- 高度沿一條邊單調（坡度不變號），四捨五入也保持單調，所以一條邊的最高點與最低點一定在兩端。
- 長度仍是 S3 的水平里程，移動、路徑與佔用都不讀高度。坡度對行駛的影響屬於 Stage W。

**3. 坡度？**
- `TrackGrade` 是約分後的有理數 rise / run（run > 0），不用浮點數比較。沿行進方向取號：上坡為正。
- 最陡的坡度是中間段的 |2R| / D。**最大坡度**是 GameCore 的遊戲參數 `TrackProfile.maximumGrade` = 40‰（1/25），不代表真實鐵路的普遍值；超過就拒絕（`trackTooSteep`）。比較用交叉相乘，全是整數。
- 溢位：型別層級上有坡度的邊要求 |R| ≤ 2¹³、L ≤ 2²⁴，否則 `TrackGeometry` 不成立；此時 R·s² ≤ 2⁶¹、R·T·D ≤ 2⁶²。世界層級的高差最多 8192（= 2¹³）、邊長小於 2²³，遠在界限內。零長度的邊在 S3 就不成立（兩端平面上重合、只差高度的「垂直鐵軌」也不成立）。

**4. 結構物？**
- 每條邊一個 `TrackStructure`：`surface`（地面，含路堤與路塹）、`elevated`（高架）、`bridge`（橋）、`tunnel`（隧道），預設 `surface`。整條邊同一種結構物，結構物改變的地方一定是節點。
- 建造規則（高度帶，沿邊單調所以只查兩端）：
  - `surface`：|z| ≤ 128（約 2 公尺的路堤或路塹）；
  - `elevated`、`bridge`：z ≥ 0；
  - `tunnel`：z ≤ 0。
  - 不符合時拒絕（`invalidTrackStructure`）。
- 費用的 hook：每格的鐵軌費用乘上結構物的係數（地面 1、高架 3、橋 4、隧道 5，都是暫定的遊戲參數）。地面是 1，所以 S3 的費用不變。
- Renderer metadata：邊的結構物、隧道口、縱斷面的分段（平坡、上坡、下坡、過渡）。GameCore 不存橋墩、隧道壁或 mesh。
- `elevated` 與 `bridge` 目前的差別只有費用與 metadata；跨越水面等差異等地形之後再加。

**5. 立體交叉與平面交叉？**
- 平面上兩條中心線相交或重疊的地方，兩條邊在那裡的高度差必須至少 `TrackStructure.clearance` = 512（約 8 公尺，軌面到軌面）。有足夠高差就是**立體交叉**：不共用任何資源、不互相阻擋、路徑不會從一條轉到另一條。
- 高差不夠、又沒有共用節點，就是在同一高度穿過另一條鐵軌，建造時拒絕（`trackConflict`，指出編號最小的那條邊）。真正的**平面交叉**必須是共用的節點（S3 的菱形交叉），那個節點是兩個方向共用的資源，與 S1 相同。
- 加上第 4 點的高度帶，上下關係自然成立：地面的鐵軌之間高差不到 512，不能互相跨越；地面下方只能是隧道；高架或橋下方可以是地面、隧道或較低的高架。
- **共用節點附近**：在同一個節點相接的兩條邊（轉轍器的兩條支線、平行的邊）在節點附近本來就重疊（取樣點的四捨五入也會讓相切的支線在一開始重合）。所以對共用節點的兩條邊，離那個節點 `RailwayNetwork.junctionZone` = 1024（一格）以內的部分不檢查；更遠的地方照常檢查。這一格相當於轉轍器與它的限界範圍，之後由 T/U 的資源處理。
- 精確的整數規則（取樣折線對取樣折線）：
  - 用方向的外積判斷兩段相交、端點落在另一段上或共線重疊。
  - 交點在每一段上的里程是兩端里程之間的線性內插，四捨五入；以 64×64 → 128 位元的標準庫乘除計算，不溢位。
  - 共線重疊時取重疊兩端的點。兩條邊的高度都沿各自的邊單調，所以比較「一條邊在這些點的最低高度」與「另一條邊的最高高度」是否相差至少 512。
- 只在建造與讀檔時計算：先用端點與控制點的外框（Bézier 在控制點的凸包內）篩選，只有外框重疊的邊才取樣比較。每個 tick 都不碰它。
- 路網與方格仍是互不相干的兩層（S3 的限制不變）。

**6. 隧道？**
- 隧道是一般的邊：路徑、位置、移動、佔用、月台與之後的預約全部照常。
- **隧道口**是 topology 的節點：一個節點同時有隧道的邊與非隧道的邊，就是隧道口（由邊推導、不存檔，`isTunnelPortal`）。列車穿過隧道口就是從一條邊進入下一條邊，沒有特殊規則。
- 地下的線形由高度帶（z ≤ 0）與縱斷面保證；地質、照明與隧道壁都不模擬。

**7. 多層車站與月台？**
- S2 的方格月台（車站格旁的鐵軌格）完全不變。
- 車站另外可以有**路網上的月台**（`TrackPlatform`）：車站（`StationID`）、一條路網邊、起訖里程 `start < end`（從邊的 `from` 端量起），長度是 `end − start`。邊可以是曲線，所以月台也可以是彎的；一個車站可以有任意多條月台股道。規則：
  - 區間在邊內，而且整段是平的（兩端高度相同；高度單調，所以中間也相同）；
  - 同一條邊上的月台彼此不重疊（不論屬於哪個車站）。
- 月台的**層**由它所在的邊推導：高度（軌面高度）與結構物（地面、高架、橋、隧道）。同一個車站可以有不同高度的月台，Phase 5F 的步行轉乘成本可以直接用月台之間的高差與距離。
- **月台是鐵路網的基礎設施**（S3A 的「唯一權威」）：存在 `RailwayNetwork.platforms`（沿鐵軌的順序：依邊、再依起點），不存在 `Station` 裡；車站只是它指向的對象。`trackPlatforms(of:)` 列出一個車站的月台（與 S2 的方格月台 `platforms(of:)` 區分）。有月台的邊不能拆（`trackEdgeHasPlatform`）。新增與移除月台是免費的 `GameWorld` 指令（`addTrackPlatform`、`removeTrackPlatform`）。
- **月台的兩端切開 span**：一條邊的 span 是 S3A 的等分，再在每個月台的起點與終點切開（`trackSpans(of:)`），所以月台恰好是整數個 span；整列停在月台上的列車只佔用月台內的 span，不會多佔月台外的軌道。span 由當下的月台推導，新增或移除月台會改變那條邊的 span；Stage T 的預約要存的是邊上的里程區間（或在有預約時拒絕改動月台），不能假設 span 永遠不變。
- S2 的方格月台照舊由車站格與鐵軌推導，不遷移成路網月台：方格沒有邊上的里程，那是 S3A-8 的相容表示；等方格列車改成 `onEdge` 時再一起遷移。
- 整列車都在某個月台的區間內時，查詢 `trackPlatformsAlongWholeTrain(_:)` 會列出它。路網上的列車仍然不能跑服務（服務與派車在 T/V 之後才上路網），S4 只提供資料與查詢。（後來改由 S5 在 T 之前完成：路網上的停站、服務與派車都以這些月台為基礎，見決策 31。）

**8. 3D 的位置與車身？**
- `TrackLocation` 多一個 `grade`：沿行進方向的坡度（pitch）；`direction` 是平面方向（yaw）；位置的 z 由縱斷面精確算出，不在取樣點之間內插。橫向傾斜（cant、roll）留給之後。
- 車身路徑（`bodyPath(of:)`）的每一點都有縱斷面的高度，所以跨越隧道口、坡道、高架的長列車會畫在正確的高度。
- 佔用只看 topology：車頭在隧道裡、車尾在外面的列車，佔用的就是它經過的節點與 span（S3A），與高度無關。

**9. 給 renderer 的查詢？**
- `railwaySnapshot()` 一次回傳路網的唯讀快照：節點（位置、是否隧道口）、邊（兩端、長度、曲線、縱斷面、結構物、取樣中心線與里程、縱斷面的分段、最陡的坡度）、月台（`TrackPlatform`：車站、邊、起訖；加上高度、結構物、中心線）與每台已放置列車的車頭位置、方向、坡度與車身路徑。
- 另有逐條邊的 `trackAlignment(of:)`。邊建好後不再改變、ID 不重用，renderer 可以依 ID 快取；快照每次呼叫時重新計算，GameCore 不另存。
- Renderer 可以自由轉成浮點數或 SIMD，但不寫回。

**10. 存檔相容？**（7 點）
1. S2 的存檔照常讀入，逐位元不變（沒有路網）。
2. 只有方格的存檔語義不變；14 個 Stage I–S2 的 property digest 不變。
3. S3 的路網存檔照常讀入：新 key 只在用到時寫入（邊的 `"profile"` 只在有豎曲線時、`"structure"` 只在不是地面時、路網的 `"platforms"` 只在有月台時），所以在地面的 S3 路網存檔讀入再寫出逐位元不變。**唯一的例外**：S3 允許同一高度、沒有共用節點的交叉，S4 拒絕它（兩列車會互相穿過卻不共用資源）。S3 的決策 29 第 9 點本來就把這個決定留給 S4；S3 沒有進 `main`，App 也不存檔，所以沒有玩家的存檔受影響。
4. S4 的立體路網存檔可以來回存讀。
5. 壞的幾何一律拒絕、不修補：高度超出範圍、負的或過長的豎曲線、平坡上的豎曲線、超過最大坡度、不符合結構物的高度帶、沒有足夠淨空的交叉、不在邊內、不是平的或互相重疊的月台、未知的結構物。
6. 明確的 `null` 拒絕，與 S3 相同。
7. 陣列依 ID 排序、推導值不存檔，所以來回存讀是 deterministic。

**11. 效能？**
- 縱斷面的高度與坡度是 O(1) 的公式，位置查詢仍是二分搜尋 O(log n)。
- 淨空檢查只在建造（一條新邊對所有邊，先比外框）與讀檔（所有邊兩兩比外框）時做；先量測，再決定是否需要空間索引。

**12. 對 Stage T 的意義？**
新的 T 只讀 topology：`TrackResource`、`TrackTraversal` 的路徑、`occupiedResources(of:)` 與月台綁定。S4 保證「兩條鐵軌在空間上相遇的地方，要嘛共用一個節點（一個資源），要嘛高差至少 512（沒有共用資源也安全）」，所以 T 不需要讀高度或幾何，也不需要另外的「空間衝突資源」。共用節點附近一格內的限界（fouling）由 T/U 的預約範圍處理。

**S4 不做**：進路預約、movement authority、dispatcher、行駛動態（坡度對速度的影響）、最終的 3D renderer、隧道照明、橋梁素材、地形、完整的建造畫面與地下模式的畫面。

#### 實作

- **型別**
  - `Geometry/TrackProfile.swift`：`TrackGrade`（約分的 rise / run，以 128 位元的交叉相乘比較陡度）、`TrackProfile`（兩端的豎曲線長度；`uniform` 與 `maximumGrade`）、`TrackProfileSegment`、`TrackStructure`（高度帶 `allows(height:)`、`clearance`、`embankment`、費用的 `costFactor`）。
  - `TrackGeometry` 多了兩端高度與縱斷面：`height(at:)`、`grade(at:)`、`steepestGrade`、`segments`、`points(from:to:)`；取樣點帶縱斷面的高度，`location(at:)` 的 z 與坡度精確計算。`TrackLocation` 多了 `grade`。
  - `Geometry/TrackClearance.swift`：`ClearanceShape`（兩端、控制點外框、幾何）與 `TrackClearance.isClear`；`RailwayNetwork.firstConflict` 與 `firstConflictingPair(geometries:)`。
  - `TrackEdge` 多了 `profile`、`structure`；`RailwayNetwork` 多了 `heightRange`、`junctionZone`、`isTunnelPortal(_:)`。
  - `Railway/TrackPlatform.swift`：`TrackPlatform`（車站、邊、起訖、長度）。`RailwayNetwork` 多了 `platforms`、`platforms(on:)`、`platforms(of:)` 與把月台兩端切進 span 的 `spans(of:length:)`；`GameWorld.trackPlatforms(of:)`。
  - `Railway/RailwaySnapshot.swift`：`TrackAlignment`、`RailwaySnapshot`（節點、邊、月台、列車）與 `GameWorld` 的 `trackAlignment(of:)`、`isTunnelPortal(_:)`、`trackPlatformsAlongWholeTrain(_:)`、`railwaySnapshot()`。
  - `FixedPoint`：`roundedProduct(_:times:over:)`（標準庫的 64×64 → 128 位元乘除）與 `greatestCommonDivisor`。
- **指令**（失敗時世界不變）
  - `buildTrackNode(at:)`：高度在 −4096…4096，否則 `invalidTrackGeometry`。
  - `buildTrackEdge(from:to:curve:profile:structure:)`：`unknownTrackNode` → `invalidTrackGeometry` → `trackTooSteep` → `invalidTrackStructure` → `trackConflict(編號最小的邊)` → `idsExhausted` → `insufficientFunds`。費用 = 每格鐵軌費用 × 結構物係數 × 格數。
  - `removeTrackEdge`：`unknownTrackEdge` → `trackEdgeInUse` → `trackEdgeHasPlatform`。
  - `addTrackPlatform(_:on:from:to:)`：`unknownStation` → `unknownTrackEdge`（方格的連結也是）→ `invalidPlatform`。`removeTrackPlatform(_:on:from:)`：`unknownStation` → `invalidPlatform`。
- **淨空**：共用節點的兩條邊各自去掉離那個節點 1024 以內的部分，剩下的取樣折線逐段比較；先比兩條邊的外框（控制點）與高度範圍，再只比落在對方外框內的段。
- **存檔**：邊只在有豎曲線時寫 `"profile"`（`startTransition`、`endTransition`），只在不是地面時寫 `"structure"`；路網只在有月台時寫 `"platforms"`（`[{ "station", "edge", "start", "end" }]`，沿鐵軌的順序）。`RailwayNetwork` 的解碼器檢查形狀（縱斷面是否成立、結構物名稱、月台的順序、不重疊、邊存在），`GameWorld` 的解碼器檢查世界規則（高度範圍、最大坡度、高度帶、淨空、月台在邊內而且平、車站存在）；讀檔時每條邊的幾何只算一次，供規則與淨空共用。
- **效能**：模擬的每一步仍只讀整數長度與轉向表。淨空只在建造與讀檔時計算。在這個 Linux 容器的 debug build 上，`vertical.differential` 一開始把約 7 毫秒花在每次讀檔的淨空檢查；只比對方外框內的段之後降到約 4 毫秒（其中大部分是 JSON 解碼），所以目前不加空間索引。

#### 驗證

- `VerticalRailwayTests`（手算，14 個）：
  - 固定坡度的坡道（上、下、平）與高度的四捨五入；
  - 豎曲線（9、37、256、503 與 1/56、1/28）；
  - 溢位的邊界（2¹³、2²⁴、128 位元的乘除與坡度比較）；
  - 最大坡度、結構物的高度帶、費用與錯誤順序；
  - 同一高度的交叉被拒絕、差 511 被拒絕、恰好 512 可以、隧道在地面下、兩層高架、沿同一條線的高架差 256 被拒絕；
  - 坡道跨越隧道時只看交叉點的高度；
  - 共用節點附近可以相碰、遠處不行、端點落在別的邊上被拒絕；
  - 隧道口、一半在地下的長列車、在坡道上折返與反向兩次還原；
  - 多層車站的月台與它們的錯誤；
  - 存讀與新 key、S3 存檔、壞存檔被拒絕；
  - renderer 快照。
- `VerticalRailwayPropertyTests`（`vertical.differential`，40 個 case × 4 個種子）：
  - 產生不同高度的直線、坡道（有時太陡）、豎曲線、各種結構物、曲線、月台與列車，同時在 GameCore 與 `ReferenceWorld` 上執行；
  - 每一步比較結果、節點高度、邊的縱斷面與結構物、3D 的中心線、兩個方向隨機距離的姿態、縱斷面分段、隧道口、月台與層、列車的位置、佔用、姿態與 3D 車身，以及整列在月台上的查詢與路徑；
  - 並檢查不變量與存讀。
  - `ReferenceWorld` 另外寫成：
    - 高度以「坡度形狀下的面積」計算、分段的邊界取另一側；
    - 以相減求最大公因數；
    - 交點以同時解兩個參數求得，共線時沿較長的軸比較；
    - 淨空逐對檢查；
    - span 在月台端點逐一切開等分的段（GameCore 是把所有分界排序後相接）。
  - digest `3668E75DCD0A98F8`（160 個 case、14,219 個操作，結束時共有 332 個月台；在這個容器的 debug build 約 142 秒）。
- `SaveMutationTests` 新增 `save.verticalMutation`；`NetworkInvariants` 以參考模型自己的取樣與規則檢查坡度、高度帶、淨空與月台（沿鐵軌的順序、車站存在、兩端是 span 的分界）。
- 刻意植入的錯誤都在前幾個 case 被抓到，驗證後還原：
  - 淨空要求嚴格大於 512；
  - 固定坡度段的高度改成無條件捨去；
  - 路堤的高度帶不含 ±128；
  - 月台的兩端不切開 span（`vertical.differential` 在第 0 個 case 由不變量、第 1 個 case 由佔用與參考模型不一致抓到，`testPlatformEndsCutTheEdgesSpans` 也失敗）。
- S3 的 `network.differential` 在 S4 的 digest 從 `D1E85EA30C734274` 變成 `92FA34EF016602C6`：它產生的路網裡有 217 次同一高度、沒有共用節點的交叉，S4 依第 5 點拒絕（GameCore 與參考模型一致）。Stage I–S2 的 14 個 digest 不變。
- Golden schema v17 與手算的 `vertical-railway.json`（75 步），第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過。建立在 S3A 之上之後，它的三個佔用預期改成手算的 span（例如 12800 的邊是 13 段，分界 ⌊k × 12800 ÷ 13⌋），同樣在兩邊都通過；月台改存在路網後，最終狀態的月台從車站移到 `network.platforms`，數值不變。S3 的 `continuous-track.json` 第 7 步從 `z: 5` 改成 `z: 5000`：它原本驗證的是 S3「一律在地面」的規則，S4 取消了這條規則。

#### GamePresentation / App

- 新錯誤的玩家訊息（坡度、結構物、淨空、月台）。
- 俯視 debug 投影依平均高度由低到高畫：隧道是虛線、高架與橋有陰影，隧道口的節點加一圈。仍不是 renderer。
- 示範配置加上跨越環線的高架（512）、從地面經隧道口下到 −512 的隧道，隧道上方的地面交叉，以及一台駛入隧道的三節列車。

#### 已知限制與留給之後

- 沒有地形：「地面」處處是 0，結構物的高度帶以 0 為準；地形之後改成相對地表。
- 路網與方格仍然互不相干，也不做兩者之間的空間檢查。
- 淨空只看中心線，不看軌道的寬度與側向間距；共用節點 1024 以內的轉轍器區由 T/U 的資源處理。
- 節點上的坡度變化不受限制（豎曲線是玩家的選擇）；坡度對行駛的影響與曲線限速屬於 Stage W。
- 路網上的月台只有資料與查詢；路網上的列車還不能跑服務或路線。S5 已解決，見決策 31。
- 橫向傾斜（cant）、橋墩、隧道壁、照明、真正的 3D renderer、建造畫面與地下模式都還沒有。

### 31. 路網上的營運（Phase 4.5 Stage S5）——設計決策

這一段是 S5 開工前的架構審查（review gate）。S5 是 S3、S4 的路網與 Phase 3–4 營運系統（N 停站、P 時刻表、Q1 折返與重複、Q2a 路線、Q2b 派車、Q3 區間車與快車）之間的橋：路網上的列車要能停在 `TrackPlatform`，照時刻表到達、停留、出發、折返、重複，被路線自動派出，跑區間車與快車，而且以整數的實際距離計算行程。S5 不做進路預約、movement authority、dispatcher 與行駛動態（T、U、V、W）。

**開工前的檢查：哪些營運 API 仍然只能處理方格？**（對照 `main` 逐一閱讀，不只看題目列出的）

| API | 方格的假設 | 路網上的結果 |
| --- | --- | --- |
| `platforms(of:)`、`platformTracks(of:)` | 月台是車站格旁的鐵軌格（`[GridPosition]`） | 看不到 `TrackPlatform`（S4 只給資料與查詢） |
| `route(from:toStation:length:)` | 從 `start.ahead`（格與朝向）出發，回傳 `[GridPosition]`，沿月台一格一格延伸 | `ahead` 是 `nil`，一律找不到 |
| `stationsStoppedAt(by:)`、`isStopped(_:at:)` | 列車要 `atNode`、continuation 用完、旁邊是車站格 | 路網上的列車永遠不算停站 |
| `stationsBesideWholeTrain(_:)` | 車身經過的每一格都是月台（`trail`） | 永遠是空的 |
| `TimetableExecution.fits` | 「行程結束」只對 `atNode` 成立 | 路網上的列車不能等待 |
| `Train` 的解碼 | 路網上的列車有服務就拒絕 | 存不了 |
| `GameWorld` 解碼的服務檢查 | 行駛中的服務用 `position.ahead` 找行程終點 | 拒絕 |
| `startTrainService` | `isStopped` | `trainNotAtFirstStop` |
| 出發 | `reversed(_:trail:length:)`、`route(from:toStation:length:)`、`movement.continuation = route` | 找不到路；折返會停止程式（`TrainPosition.reversed` 只給方格） |
| 到達 | `isStopped` | 永遠不到達 |
| 派車的就緒與快取 | `isStopped`；一趟的快取以位置與方格車身為 key | 路網上的列車永遠不就緒 |
| `LineLeg.route` | `[GridPosition]` | 無法表示路網上的路 |
| `journey(of:service:)`（`lineJourney`） | 從每個方格月台朝四個方向出發 | 看不到路網的月台 |
| `drive(...)` | 距離 = `route.count × 1024`；`position.ahead!`；方格車身 | 距離錯誤、停止程式 |
| `trip(of:service:for:)` | 方格的折返與車身 | 同上 |
| `lineMaximumTrains`、`lineTrainsInService`、`lineHeadway`、`lineSegmentLoads` | 經由上面的行程 | 路網上的路線一律沒有行程 |
| 路網的移動 kernel 與 `TrainMovement` | 路徑一定走到最後一條邊的終點 | 無法停在邊中段的月台 |
| `setTrainContinuation(_:along:)` | 同上 | 同上 |
| `GameSession.sendSelectedTrain`（Presentation） | 送往車站只用方格的路 | 路網上的列車一律「沒有路」 |
| 測試的 `WorldInvariants.serviceViolations`、`NetworkInvariants` | 用 `ahead(of:)`；「路網上的列車有服務」算違規 | 要一起泛化 |

`trainServiceStatus(of:)`、`lineServiceSummaries(_:)`、`lineStatusText(_:at:)` 與地圖的畫法只讀上面的查詢，本身不假設方格。

**1. 方格與路網共用一套營運語義嗎？** 是。分層與決策 20 相同，只把「路徑」泛化：

```
時刻表、路線（計畫）→ 執行進度（TimetableExecution）→ 服務路徑（TrainPath）→ 移動（TrainMovement）
```

- 時刻表的狀態機（`advance` 的五段、出發、停留、完成、重複、零距離到達、找不到路時等待）、路線的一趟（`LineTrip`）、行程（`drive`）、派車與服務模式都只有**一份**實作。沒有 `GridTimetableEngine` 與 `NetworkTimetableEngine`。
- 只在最底層依鐵軌種類分成兩個 adapter，每個都是一個小函式：
  - **找月台**（resolvePlatforms）：方格是車站格旁的鐵軌格（S2）；路網是車站的 `TrackPlatform` 與它們的停車位置（第 4 點）。
  - **找路**（resolveRoute）：`path(from:toStation:length:)`。方格用既有的搜尋，路網用第 6 點的搜尋，兩者都回傳 `TrainPath`。
  - **交給移動**（applyPathToMovement）：方格寫成 `continuation`（每條 link 的終點），路網寫成 `edges` 與 `end`（第 12 點）。
  - **列車的位置與車身**：原地折返（方格 `reversed(_:trail:length:)`、路網 `reversedOnNetwork`）、走完一段路之後的位置與車身（方格 `trail(after:...)`、路網 `networkTrail(after:...)`），以及停站的判定（第 13 點）。
- 列車「在哪裡、車身怎麼放」在內部用一個值表示（`TrainPlacement`：位置、方格車身、路網車身、長度）；出發、行程與派車都只經過它與上面的 adapter。

**2. 服務路徑的 canonical 表示是什麼？** `TrainPath`：

- `traversals: [TrackTraversal]`：列車在目前這條邊（或 link）之後依序進入的行進方向。方格是 `.link` 的 traversal，所以兩種鐵軌是同一個型別。
- `end: Int64?`：車頭停在最後一條 traversal（沒有 traversal 時是列車所在的那一條）的哪裡，沿行進方向從它的起點量起；`nil` 是走到它的終點。方格一律是 `nil`：方格的列車停在節點。
- `distance: Int64`：車頭從現在的位置走到終點的精確距離（第 7 點）。
- 只由 topology 與整數長度決定，不含控制點、取樣點或 renderer 的資料。
- 為什麼是它：S3 的 `route(from:to:)`、`pathAhead(of:)` 與 `setTrainContinuation(_:along:)` 已經以 `TrackTraversal` 表示路，只要再加上「停在最後一條的哪裡」，就能表示邊中段的月台。之後 T 的預約（沿 traversal 預約到停車位置為止的 span）、U 的 movement authority（授權到路徑上的某一點）與 V 的 dispatcher（換一條 `TrainPath`）都讀同一個型別，不必再換表示。
- `TrainPath` 是查詢的結果，不存檔。存檔的仍然只有 `TrainMovement`：方格的 `continuation`（S3A-8 的相容表示，就是 link 的終點序列）；路網的 `edges` 加上新的 `end`。沒有第二份存檔的路徑。

**3. 月台是停站的正式基礎。** 路網上的停站只看 `TrackPlatform`：以車站為目的地的路、到達、停站、整列停妥、派車的就緒與路線的行程都經由它。方格的月台（S2）完全不變。同一個車站可以同時有兩種月台；列車只用它所在那種鐵軌上的月台。

**4. 停車位置（berth）。**

- 規則：車頭停在**行進方向上月台的末端**，車身向後延伸（S2「到了月台繼續往前，直到整列在月台邊」的連續版本）：
  - 沿 `forward` 進站：車頭的里程是 `platform.end`，也就是 `onEdge(forward, offset: end)`；
  - 沿 `backward` 進站：車頭的里程是 `platform.start`，也就是 `onEdge(backward, offset: L − start)`（`L` 是邊長）。
- 檢查過的性質：
  - 一個月台、一個方向恰好一個停車位置，與列車長度無關（長度只決定能不能停，見第 5 點）；整數、不讀幾何，每個平台都相同。
  - 停車位置一定大於 0（`end > start ≥ 0`，`L − start > 0`），所以有車身的列車也能以 S3 的唯一表示停在那裡。月台的末端就是邊的端點時（`end = L`，或後退時 `start = 0`），停車位置就是那個節點，寫成「沿剛走完的邊到達終點」（offset = L），與 S3 相同。
  - 同一條邊上的月台不重疊，所以同一個方向上不同月台的停車位置一定不同。
  - 月台只在一條邊上。跨越節點的月台要分成幾個 `TrackPlatform`；整列停妥看單一個月台，與 S4 的 `trackPlatformsAlongWholeTrain(_:)` 相同。
- 折返不改變停車規則：折返就是 S3 的 `reversedOnNetwork`，車頭移到車尾，反向兩次逐位元還原。停在停車位置、整列在月台上的列車折返後，車頭在原本車尾的里程，仍在同一個月台上（第 5 點），所以仍然停在那個車站；下一站又是這個車站時，它會往新方向的停車位置前進。

**5. 月台長度與整列停妥。**

- 路網的月台有精確的長度，所以採用**比方格更嚴格的規則**：`TrackPlatform` 只對不比它長的列車算停車位置（`train.length ≤ end − start`）。以車站為目的地的路只考慮這些月台，所以列車走到停車位置時，整列車（車頭到車尾的區間）一定都在那個月台的範圍內、在同一條邊上。
- 結果：服務與路線永遠不會把列車送到放不下它的月台；沒有夠長的月台就是沒有路（服務等待；列車不就緒，路線不派出）。
- `stationsStoppedAt(by:)` 仍然只看車頭，與方格相同：路徑走完、車頭在該站某個月台的範圍內。`stationsBesideWholeTrain(_:)` 另外要求整列車都在該站的**同一個**月台內（車身沒有跨到別的邊，車頭到車尾的里程區間在 `[start, end]` 內）。所以「車頭在月台、車尾在外」是停站但不是整列停妥，與 S2 相同；玩家把列車手動開到太短的月台時看得到這個差別。
- 方格不變：長列車到第一個月台後照 S2 沿月台延伸，月台太短時車尾在月台外，路線在第一站折返後不再派出它（決策 27）。S5 不偷偷改這個行為。

**6. 以車站為目的地。** `path(from:toStation:length:)`：

- 方格上的列車：`route(from:toStation:length:)` 的結果寫成 link 的 traversal，行為與以前完全相同。
- 路網上的列車：到該站某個夠長的月台的停車位置（第 4、5 點）的最短路（第 7、8 點）。
- 方格與路網不相接（S3 的限制），所以不假裝能跨越：方格上的列車只找方格的月台，路網上的列車只找 `TrackPlatform`。同一條路線或時刻表的每一段，只要在列車所在的鐵軌上找得到路即可。
- 找不到路時沿用決策 20、21：服務在原站等待，不瞬移、不改線、不丟掉時刻表、不先折返，之後的步長再試。

**7. 精確的行程距離。**

- 路網：車頭在 `(T₀, o₀)`、邊長 `L₀`，依序進入 `t₁ … t_k`，停在 `t_k` 的 `e`：
  - `k = 0`：`e − o₀`；
  - `k ≥ 1`：`(L₀ − o₀) + L(t₁) + … + L(t_{k−1}) + e`。
  - 例：目前的邊 A 還剩 8,300，中間的邊 B 長 21,470，最後在邊 C 的 3,200 停下，距離是 8,300 + 21,470 + 3,200 = 32,970，不是 3 × 1024。
- 方格：在連結上時先加 `1024 − offset`，再加每條連結 1024。行程的每一段都從節點出發，所以就是以前的 `route.count × 1024`。
- 一段的分鐘數是 ⌈距離 ÷ 路線的 rate⌉，以整數計算（`距離 / rate + (距離 % rate == 0 ? 0 : 1)`，rate ≥ 1，不會溢位）。各段與停留照舊以會回報溢位的加法累加，溢位時沒有行程。
- 距離本身也以會回報溢位的加法累加，溢位時當作沒有路。任何實際的地圖都遠小於這個界限：邊長小於 2²³，而最短路不會重複同一條 traversal。

**8. 確定的選擇順序（不依字典、集合、建造時間或記憶體位址）。**

- 路網的搜尋就是 S3 的 `TrainRoute.shortest`，狀態是「出發點」、「剛進入某條 traversal」與「某個停車位置」：
  - 從出發點：同一條 traversal 前方的停車位置（距離 `b − o₀`），以及轉進下一條 traversal（距離 `L₀ − o₀`）；
  - 從剛進入的 traversal：它上面的每個停車位置（距離 `b`），以及轉進下一條（距離是這一條的長度）。
  - 距離從不為負；只有從出發點的一步可能是 0（列車已在停車位置，或在邊的終點）。
- 結果只由規則決定：
  1. 總距離最短；
  2. 同樣短時，依各步的選擇順序逐步比較：同一條 traversal 上的停車位置在前（依里程），轉向在後，依邊的編號遞增（S3 的 `transitions(after:)` 順序）。
  - 同一條 traversal 上前方的停車位置，一定比經過它之後的任何停車位置近；兩個月台也不會共用停車位置。所以同樣短只會發生在兩條路於某個節點分開時：取在第一個分開的節點轉進編號較小的那一條。
- 路線行程的起點：先是方格的月台 × 北、東、南、西（S2 的順序），再是路網的月台依 `RailwayNetwork.platforms` 的順序（邊的編號、起點里程）× 前進、後退的兩個停車位置；取來回最短的，同樣短時取最先的。所以只有方格的世界與以前完全相同。
- 字典只用來查表，從不依它的順序走訪。

**9. LineJourney 的泛化。**

- `LineLeg` 改存 `path: TrainPath` 與 `minutes`（⌈`path.distance` ÷ rate⌉）。這是公開 API 的變更：舊的 `route` 改成由 path 推導的唯讀屬性（方格是每條 link 的終點，路網是空的）。`LineJourney.start` 仍是 `TrainPosition`，路網上是一個停車位置。
- `drive` 從 `TrainPlacement` 出發：每一段用 `path(from:toStation:length:)` 求路，走完後依第 1 點的 adapter 移動位置與車身；在最後一個停靠站原地折返。全線站站停、區間車、快車、去程、終點折返與回程都是同一段程式。
- 多個候選月台與多條可能的路，由第 8 點決定。
- `ServiceLine` 的資料（站、rate、營運時間、各等級的列車數、目標班距、服務模式）與存檔格式都不變：路線是營運計畫，不是實體路徑。

**10. 列車自己的一趟：`trip(of:service:for:)`。** 從列車的 `TrainPlacement`（路網上是 `onEdge` 與 `trailEdges`）出發，照原本朝向或先原地折返，取來回較短的（相同時不折返）。編組長度影響：

- 候選月台（第 5 點）；
- 折返後的車頭位置（車頭到車尾）；
- 每一段之後的位置與車身，也就是下一段的出發點。
- 例（手算測試）：長列車停在地下的彎曲月台，整列在月台內；折返後車尾成為車頭，仍在同一個月台內；回程照常建立。

**11. 時刻表的執行（決策 20、21 不變）。** 每個基本步長仍是派車 → 出發 → 移動 → 時鐘 → 到達：

- 不早於排定出發離開、不另加停留、每步最多移動一次；
- 已經停在下一站：路徑的距離是 0，零距離到達（方格的空路徑就是距離 0）；
- 沒有路就等待，不先折返，同一次呼叫中不再找；
- 最後一站停到排定出發才結束；重複的時刻表接下一輪；
- 標記折返的停靠先原地折返，再找路。
- 路網的差別只在最底層：路網上沒有路的列車會走到邊的終點（S3），所以服務折返列車之後，讓它的路徑在原地結束（`end` 設為新的車頭位置）：列車站在折返的地方，等待下一次出發或派車。方格的列車本來就停在節點，不受影響。

**12. 路網上的 continuation。**

- `TrainMovement` 新增 `end: Int64?`：路網上路徑的最後一條邊（`edges` 的最後一條；用完時就是列車所在的邊）上，車頭停下的位置；`nil` 是走到那條邊的終點（S3 的行為）。
- 移動 kernel：在路徑的最後一條邊上，走到 `end` 就停；其他規則不變，只讀整數長度。
- 路徑走完（沒有剩下的邊，車頭在 `end`；`end` 是 `nil` 時在邊的終點）的列車不會移動。
- 指令：
  - `setTrainContinuation(_:along:stoppingAt:)`：新參數預設 `nil`，S3 的呼叫方式與行為不變。`path(from:toStation:length:)` 的結果可以原封不動以 `along: path.traversals, stoppingAt: path.end` 交給它。檢查：方格不能有 `end`；在最後一條邊上 `0 ≤ end < 邊長`；有剩下的邊時 `end ≥ 1`（0 就是前一條邊的終點）；沒有剩下的邊時不能在車頭後面。
  - `reverseTrain` 與以空陣列呼叫的 `setTrainContinuation(_:to:)` 照 S3 清除整條路，包括 `end`：列車會走到邊的終點。
- 這不是第二份路徑：`edges` 與 `end` 合起來就是列車唯一的路。`pathAhead(of:)` 不變，它回傳的 traversal 在最後一條的 `end` 結束。
- 不把路網的路轉回 `[GridPosition]`。

**13. 到站與停站。**

- 方格不變（決策 18）。
- 路網：列車停在某站，若且唯若：
  1. 路徑走完（沒有剩下的邊，車頭在路徑的終點）；
  2. 車頭所在的邊上有該站的月台，車頭的里程在它的 `[start, end]` 內（含兩端）。
- 只看車頭所在的那一條邊：停在節點的列車在它剛走完的那一條邊上；下一條邊從這個節點開始的月台不算。
- 經過月台（還有路），或停在邊中段但路還沒走完（例如放在月台上、沒有路、會繼續走到邊的終點），都不算停站。
- 到達（第 4 段）、`startTrainService`、派車的就緒與存檔的檢查都用這一條規則。停站不存檔。
- 要讓放在月台上的列車停站，給它一條在原地結束的路：`setTrainContinuation(_:along: [], stoppingAt: offset)`。

**14. Q1–Q3。**

- Q1：單次與重複的時刻表、終點折返、反向兩次逐位元還原、輪次的邊界都照舊；位置都是整數，路徑的表示不會造成漂移。
- Q2a：`ServiceLine` 的格式不變，只有推導的行程可以在路網上。
- Q2b：派車的條件與順序不變。就緒改用泛用的停站判定，所以路網上的列車不會因為 `position.ahead == nil` 永遠被忽略；一趟的快取以 `TrainPlacement`（位置加上兩種車身）為 key。沒有夠長的月台或沒有路時，列車不就緒、不派出。
- Q3：`calls` 仍是路線站的索引；快車沒有自己的路權；容量的算法不變；跳過的車站不會變成停站；快車走到下一個停靠站的最短路，不綁定實體路徑（之後由 V 深化）。

**15. 高架、地下、隧道。** 路徑、距離與停站只讀 topology 與水平里程（S3、S4），不因結構物分岔：隧道口、坡道與高架都是一般的邊。結構物只影響幾何、費用與之後的 W。

**16. 存檔。**

- 唯一新的存檔資料是移動的 `"end"`，只在有值時寫入。沒有它的存檔（包括所有舊存檔）讀成 `nil`，所以只有方格的存檔與 S3、S4 的路網存檔都逐位元不變。
- 一律拒絕：明確的 `null`、負數、和方格的 continuation 一起出現、有剩下的邊時為 0、沒有剩下的邊時在車頭後面（`Train` 的解碼），以及不小於最後一條邊的長度（那條邊還在時，`GameWorld` 的解碼）。
- `Train` 的解碼接受路網上有服務的列車。`execution`、`timetable` 與路線的格式都不變。
- 停車位置、停站、整列停妥與路徑的距離都由存檔的狀態推導，不存檔。

**17. 不變量與拆除月台。**

- 等待中的服務：列車依第 13 點停在該站（方格與路網同一條規則）。
- 行駛中的服務（路網）：路徑還沒走完，而且路徑的終點是目的地車站某個不比列車短的月台的停車位置。路徑還能沿剩下的邊走到最後時，檢查方向與位置；中間有被拆的邊時（ID 不重用，列車會一直在它之前等待），只檢查最後一條邊上那個月台的兩個停車位置之一。
- 為了讓這兩條在任何指令之後都成立，`removeTrackPlatform` 在 `invalidPlatform` 之後多一個拒絕：**有服務正在用這個月台**時，丟出 `trainServiceActive`（編號最小的那台列車）：
  - 等待中的服務，這一站是該月台的車站，車頭在這個月台上；
  - 行駛中的服務，目的地是該月台的車站，路徑的最後一條邊就是這個月台的邊（保守：同一條邊上同一站的其他月台也算）。
  - 要拆就先停止服務（路線的列車先取回）。沒有服務的列車不受影響，所以 S4 的行為與 `vertical.differential` 都不變。
- 其他：移動的 `end` 符合第 12 點；路徑的邊都曾經建過（S3）；路線與服務模式的指派不因鐵軌種類而不同。

**18. 舊行為與 property digest。** 方格經過 adapter 後得到完全相同的路、距離、狀態與存檔，所以預期 16 個 property digest 全部不變，包括 `network.differential` 與 `vertical.differential`（S3、S4 的 campaign 從不設定 `end`，也沒有服務）。實作後逐一確認；若有改變，逐項說明原因。

**19. 效能。** 服務的查詢只讀 topology、邊長與月台區間：

- 找路只走到最近的停車位置為止，與 S3 的路相同；
- 每次找路先把該站的停車位置依 traversal 整理一次（該站的月台數）；
- 停站的判定掃描一次月台清單，不取樣、不掃描地圖；
- 不建立全域快取，等有量測再決定。派車的快取照舊是每次 `advance` 呼叫一份。

**20. S5 不做。** 進路預約、movement authority、號誌、閉塞佔用的阻擋、dispatcher、交會、超越、月台分配的衝突處理（T、U、V），以及加減速、煞車曲線、牽引、坡度與曲線的速度影響、能耗（W）。列車之間照舊互不阻擋，可以佔用同一個資源、互相穿過。路線的 rate 仍是時刻表行程的固定速度。

**21. 對 Stage T 的意義。** 新的 T 直接使用 S5 統一好的：`TrainPath`（`path(from:toStation:length:)`）、`TrackTraversal`、`pathAhead(of:)` 與移動的 `end`、`occupiedResources(of:)` 與 span、`TrackPlatform` 與停車位置，以及車身的佔用。T 不需要再處理路網上以車站為目的地的路、路網的時刻表或 LineJourney 的遷移。

#### 實作

- **型別與 adapter**（`Sources/GameCore/Railway/ServicePath.swift`）
  - `TrainPath`（公開：`traversals`、`end`、`distance`）是唯一的服務路徑；`TrackTraversal.tileAhead` 是方格 link 的終點，方格的 continuation 由它推導。
  - 內部的 `TrainPlacement`（位置、方格車身、路網車身、長度）與 `Train.placement`；`turnedRound(_:)`（方格 `reversed(_:trail:length:)`、路網 `reversedOnNetwork`）與 `placement(_:after:)`（方格 `trail(after:...)`、路網 `networkTrail(after:...)`）。
  - `Berth` 與 `berths(of:length:)`（第 4、5 點）；`path(from:toStation:length:)`：方格是 `route(from:toStation:length:)` 寫成 link，路網是 `TrainRoute.shortest` 在「出發點、剛進入的 traversal、停車位置」上的一次搜尋（第 6–8 點）。
- **移動**（`TrainMovement.swift`）：`end`（`internal(set)`）、kernel 的 `travel(along:...end:enter:)` 在最後一條邊上停在 `end`；`isWellFormed`、`fits` 與 `"end"` 的存讀（第 12、16 點）。
- **指令**（`GameWorld`；失敗時世界不變）
  - `setTrainContinuation(_:along:stoppingAt:)`：檢查順序不變（`unknownTrain` → `trainNotPlaced` → `trainServiceActive` → `invalidContinuation`），`end` 的檢查屬於 `invalidContinuation`。
  - `reverseTrain` 與以空陣列清除的 `setTrainContinuation(_:to:)` 也清除 `end`。
  - `removeTrackPlatform`：`unknownStation` → `invalidPlatform` → `trainServiceActive`（`serviceNeeds`，第 17 點）。
- **停站**（`StationStop.swift`）：`stationsStoppedAt(by:)` 與 `isStopped` 的路網分支用 `standingPoint(of:)`（路走完時車頭所在的邊與里程）；`stationsBesideWholeTrain(_:)` 的路網分支要求 `trackPlatformsAlongWholeTrain(_:)` 裡有該站的月台（同一個月台）。
- **服務與派車**（`GameWorld.advance`）：出發段對兩種鐵軌是同一段程式：`reverses` 時 `turnedRound`，再 `path(from:toStation:length:)`；距離 0 是零距離到達；否則 `follow` 交給移動（方格寫 `continuation`，路網寫 `edges` 與 `end`）；折返後服務結束或已在下一站時，`stand` 讓路在原地結束。派車的就緒改用泛用的停站判定，一趟的快取（`DispatchMemo.trips`）以 `TrainPlacement` 為 key。
- **路線**（`LineJourney.swift`）：`LineLeg(from:to:path:minutes:)`，`route` 是由 path 推導的唯讀屬性（方格是每條 link 的終點，路網是空的）；`journey(of:service:)` 的起點先是方格的月台 × 北、東、南、西，再是路網月台的兩個停車位置；`drive(_:calling:from:)` 從 `TrainPlacement` 出發，每段 ⌈`distance` ÷ rate⌉ 分鐘。`trip(of:service:for:)` 也從 `TrainPlacement` 出發。
- **存檔**：`TrainMovement` 的 `"end"`；`Train` 的解碼接受路網上的服務；`TimetableExecution.fits` 對兩種鐵軌用同一個「路走完」的判定；`GameWorld` 的解碼檢查 `end` 小於最後一條邊的長度，以及行駛中的服務的路停在下一站的停車位置（`pathEndsAtBerth`）。
- **效能**：本輪沒有做效能量測。找路只走到最近的停車位置，停站掃描一次月台清單，都不取樣、不掃描地圖，也沒有全域快取（第 19 點）；`service.network` 在 debug build 上跑 12,800 個操作約 4.4 分鐘，其中大部分是參考模型與逐步的整個狀態比較，不是效能數字。

#### 驗證

- `NetworkServiceTests`（手算，20 個；曲線長度以獨立的精確分數移植核對）：
  - 兩個方向的停車位置、精確距離、月台長度的篩選、同樣短時依邊的編號決定；
  - 路走完才停站、`end` 的檢查、整列停妥與車頭停站的差別；
  - 時刻表從月台到月台、誤點的列車到站後下一步就出發、沒有路時等待而且不折返、路恢復後出發、重複的時刻表來回並回到同一個位置；
  - 長列車進隧道到地下的彎曲月台再回來（整列在月台內，折返後車尾成為車頭，仍在同一個月台）、高架月台兩個方向都能停；
  - 路線的行程是精確距離、派車與再次派出、服務等級決定派出的列車數、月台太短時不派出、區間車與快車、服務需要的月台不能拆、存讀。
- `ReferenceWorld`（`ReferenceNetworkService.swift` 等）另外寫一次決策 31，而且盡量寫得不同：月台沿列車所在的方向看、以車站為目的地的路用「到最近停車位置的距離」鬆弛到不動點再貪婪地走、停車位置由站的位置判定、每段之後的車身由整條走過的路讀出。
- `NetworkServicePropertyTests`（`service.network`，40 個 case × 4 個種子 × 80 個操作 = 12,800 個操作，digest `B5FBE91125ADA10C`）：產生多層的路網（直線、S 曲線、坡道、高架、隧道、支線）、長短不同的月台與 1 到 4 節的列車，執行時刻表（單次與重複、折返）、路線與服務模式、手動的路、拆建月台，同時在 GameCore 與 `ReferenceWorld` 上執行。每一步比較結果與整個狀態：位置、車身、路與 `end`、服務與時刻表、停站與整列停妥、到每一站的路與距離、每個服務的行程、各等級的列車數與班距、各路線的上次派車；並檢查不變量與存讀。量：出發 548、到達 219、折返 375、服務結束 113、下一輪 519、派車 55、服務模式派車 19、長列車在服務中移動 315、離開地面的移動 715、整列停妥 20,245、跨多條邊的路 5,936、被拒絕的拆月台 270、成功的拆月台 362。
- `SaveMutationTests` 新增 `save.networkServiceMutation`（10 個 case × 4 個種子，每個 30 次變異）：載入 503、拒絕 697、瞄準服務、路、路線與月台的變異 916、載入的路網服務 955、停在邊中段的路 1,197；載入的世界都保持不變量、可以存讀，之後的指令也保持一致。
- `WorldInvariants` 與 `NetworkInvariants` 泛化：路網上可以有服務；等待中的服務停在該站；行駛中的服務還有路，路停在下一站某個放得下列車的月台的停車位置；每個 `end` 都合法。
- Golden schema v18 與手算的 `network-service.json`（77 步：地面的 Harbour、彎道、隧道裡 1/32 的坡道與地下彎道上的 Deep；三節的 Mole 重複 Harbour → Deep → Harbour，去程 45,258（23 分鐘）、回程 47,306（24 分鐘）；路線 Tube 每 52 分鐘派出一節的 Shuttle），第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過；既有的 17 個 fixture 只把 `schemaVersion` 改成 18。
- 刻意植入的錯誤，各自單獨植入、驗證後完整還原（`git diff -- Sources` 為空）；四個都在 `service.network` 的第一個種子的前兩個 case 被抓到，手算測試與 golden 也都失敗：
  - 行程距離寫成 `邊數 × 1024`：case 0（距離 3072 對 14429）；
  - 後退方向的停車位置用錯月台端點（`L − end`）：case 0；
  - 停車位置不看列車長度：case 0（放不下的月台也找到路）；
  - 終點折返後車頭差一個列車長度：case 1（6193 對 8241，差 2048，三節列車的長度）。
- 舊行為：16 個 property digest（Stage I–S4，包括 `network.differential` 與 `vertical.differential`）在修改前後完全相同；所有既有的 golden 預期值不變。

#### GamePresentation / App

- 列車工具可以把路網上的列車送往車站：`path(from:toStation:length:)` 的結果原封不動交給 `setTrainContinuation(_:along:stoppingAt:)`；沒有路時說明原因（選的是一般的格、月台太短、車站在路網上沒有月台）。
- `Train.pathText` 以文字表示路網上的路（剩下幾條邊、停在最後一條的哪裡）。路網上的列車的停站、服務名稱、下一站、早到或誤點與路線狀態本來就只讀 GameCore 的查詢，新的測試確認它們在路網上也正確。
- 地圖在路網的鐵軌下方畫出車站的月台。
- Debug 的示範配置讓 Harbor 在環線上多一個月台、在環線上建 North Gate，路線 Circle 讓三節的 Loop 在兩站之間往返（每端折返）。它仍然從一般的新遊戲開始、付一般的費用；以原樣的 `DemoLayout.swift` 在 Linux 上編譯並模擬 240 分鐘，全程準時。

#### 已知限制與留給之後

- 方格與路網不相接：列車只找它所在那種鐵軌上的月台，一條路線或時刻表的每一段都要在同一種鐵軌上找得到路。
- 列車之間互不阻擋，可以佔用同一個資源、互相穿過；進路預約、movement authority、dispatcher（T、U、V）。路線的 rate 是固定速度，沒有加減速（W）。
- 行駛中的服務不重新求路：路中間的邊被拆時照移動規則等待（S3），直到服務停止。
- 拆月台的拒絕是保守的：行駛中的服務的路停在某條邊上時，同一條邊上同一站的其他月台也不能拆。
- `lineJourney` 仍是一節列車的行程（與方格相同）；每台列車的一趟用它自己的長度。
- 建造路網、月台與路線的畫面、spline 編輯器與 3D renderer 仍然沒有；示範配置用指令建造。

### 32. 進路預約（Phase 4.6 Stage T）——設計決策

這一段是 T 開工前的架構審查（review gate）。T 只做**進路預約**：一台列車開始使用一條已經決定好的路（`TrainPath`、手動的 continuation，或它本來就會走完的那一段）之前，先一次、原子地取得整列車走完這條路所需要的鐵路資源；拿不到就不走。T 建立在 S3–S5 統一好的 `RailwayNetwork`、`TrackTraversal`、`TrackResource`（節點與 span）、`TrackPlatform` 與 `TrainPath` 上，不再處理方格與路網的遷移，也不延續舊 PR #31 的方格實作（第 20 點）。

**T 不做**（分屬之後的 Stage）：號誌顯示、movement authority 與「進入每個資源前檢查授權」、通過後逐段釋放（U）；dispatcher、繞路、超越、交會、月台分配、快車優先（V）；加減速與煞車（W）。

**1. 預約是權威狀態，存在哪裡？**

- `Train.reservation: [TrackResource]`：這台列車已經鎖住、準備使用的資源，依資源的既有順序排列、不重複（canonical）；沒有預約時是空的。只有 `GameWorld` 會寫入（`internal(set)`），公開讀取。
- `GameWorld.isTrafficControlEnabled: Bool`：交通控制開關，新世界預設關閉（第 8 點）。
- **為什麼放在列車上，而不是世界的預約表**（依五個準則比較）：
  - value semantics、`Sendable`：兩者相同。
  - `Codable`：放在列車上時，只在非空時多寫一個 `"reservation"` key，和 `trail`、`trailEdges`、`movement` 一樣；舊存檔逐位元不變。
  - 不變量：擁有者就是那台列車本身，不可能指向不存在的列車、不可能一台列車有兩份預約，也不需要依擁有者排序或檢查唯一；取下列車時和位置一起清掉。預約表則要另外驗證這三件事。
  - 之後的 U（通過後釋放）：U 在移動 kernel 裡逐台列車移動時，就地縮小 `trains[i].reservation`，不必再用 ID 查表。
  - 查詢成本：衝突判定本來就要掃描每一台列車（第 6 點），兩種放法都是 O(列車數)。
- **只有一份真相**：預約只記「哪些資源被這台列車鎖住」。列車走哪條路仍然只有 `TrainMovement`（方格的 `continuation`、路網的 `edges` 與 `end`）；預約不另存路徑、`TrainPath` 或停車位置。預約只在「取得」的那一刻由列車的路推導出來，之後就是獨立的權威狀態：它包含列車已經走過、但 T 還不釋放的資源，這些無法由目前的位置重新推導，所以存檔、驗證時不會因此刪掉或修正它（第 14 點）。

**2. 資源是什麼？** 只用既有的 `TrackResource.node(TrackNodeID)` 與 `.span(TrackSpan)`：方格的格（`.tile`）與連結（一整個 span），路網的節點與邊上的 span（S3A 的等分，再由月台的兩端切開，決策 30）。不退回 `GridPosition`、整條邊或北東南西。一條長邊有很多個 span，列車只預約它真的會用到的那幾個。

**3. 列車的「路」與預約範圍（envelope）。** 列車的路 = 它之後**會自己走完**的那一段，由移動狀態決定：

- 方格：剩下的 continuation（`pathAhead(of:)`，不論現在鋪著沒有：被拆的鐵軌補回後列車會繼續走，決策 15）；在連結上的列車至少還會走到連結的 `to` 端。
- 路網：剩下的邊中目前還能進入的那些（`pathAhead(of:)`；ID 不重用，進不去的邊永遠進不去），停在最後一條的 `end`（沒有 `end`，或路在中途斷掉時，是那條邊的終點）。沒有剩下的邊時，列車仍會在自己的邊上走到 `end`（或終點）：放在邊中段的列車、`reverseTrain` 之後的列車都是這樣（S3、S5 的規則）。
- 路的長度為 0（方格停在節點且沒有 continuation；路網上 `standingPoint` 成立，或路斷在列車所在的邊的終點）時，列車**站著**，不需要預約。

預約範圍 = 從**車尾現在的位置**沿著列車來的路（車身）與要去的路，一直到**路的終點**這一整段軌道所碰到的資源，也就是：

```
目前整列車佔用的資源（occupiedResources 的規則）
∪ 車頭從現在的位置沿路走到終點所經過的資源
∪ 這一整段在路網交會點附近的限界資源（第 5 點）
```

- 這等於「列車在走完這條路的每一個時刻所佔用的資源」的聯集：列車只往前走，車身跟著車頭，每一點都落在這一整段裡；反過來，這一段的每一點都會被列車在某一刻碰到。整列車（長列車的車身）因此自然包含在內，停車位置的月台也是：車頭停在終點，車身在它後面，都在這一段裡。
- 精確處理（全部以整數里程計算，不讀幾何取樣）：目前這條邊只取車頭**之後**的部分（它之前的部分只在車身蓋到時才算）；中間的節點與邊整條；最後一條邊只到 `end`；路在列車所在的邊上就結束時，只取車頭到 `end` 之間；路重複經過同一條邊（繞圈）時取聯集；路回到自己的車身也只是聯集。不能簡化成 `path.traversals.map(edge)`。

**4. Span 的分界：與佔用同一條規則。** 佔用的規則（決策 29 S3A-6）是：列車中心線碰到（到達或經過）的每個節點，以及和列車有一個「嚴格落在邊的兩端之間」的共同點的每個 span；碰到兩個 span 的分界時同時佔用兩個。預約範圍用**同一個**以里程區間計算資源的 helper（`networkResources(covering:)`），把「車身」與「車頭要走的路」都寫成邊上的里程區間交給它：

- 這條規則是逐點的（一個資源被算進去，若且唯若區間裡有某一點碰到它），所以「車身的資源 ∪ 路的資源」恰好等於「整段的資源」，不會因為分開算而少掉分界另一側的 span；車頭剛好停在分界上時，兩邊的 span 都在預約裡，不會留下只拿到一邊的 race。
- 方格的連結只有一個 span（0 到 1024），格就是它的兩端，所以同一個 helper 在方格上給出：連結上的列車加上 `to` 端的格，之後每一步加上連結與它通往的格。方格的佔用本身沿用決策 26、27 的程式，結果不變。
- `ReferenceWorld` 另外寫一次這條規則（以沿路的絕對距離計算，見驗證），不共用 GameCore 的 helper。

**5. 交會點、轉轍器、平面交叉與限界（fouling）。** T 只讀 topology 與整數里程，不讀高度、取樣點、3D mesh 或畫面。分析既有的保護夠不夠：

- **經過交會點的進路**：任何經過某個節點的路都包含那個節點（第 4 點）。轉轍器的兩條支線、平面交叉的兩個方向、雙交分轉轍器，都在共用的節點上衝突，所以兩條經過同一個交會點的進路不能同時成立。方格的轉轍器與平面交叉是一格，同理（S1）。
- **立體交叉**：S4 保證平面上相遇但沒有共用節點的兩條邊高度差至少 512，它們不共用任何資源，所以互不衝突；T 不需要任何特別的規則，也不讀高度。
- **不夠的地方——停在交會點附近**：S4 讓共用節點的兩條邊在那個節點 `RailwayNetwork.junctionZone`（1024）以內不檢查淨空，因為轉轍器的支線在那裡本來就並排、甚至重疊。一台列車停在支線 a 上、離節點 300 的地方（車尾已經離開節點），它只佔用 a 的 span，不佔用節點；另一台列車這時經過節點轉進支線 b，兩者沒有共用資源，實際上卻會互相穿過。span 最長 1024、節點預約與車身佔用都擋不住這種情況。
- **最小的限界規則**：
  - 節點上一條邊的端點是**限界端**（fouling end），若且唯若這個節點上還有另一條邊的端點**不和它相通**（兩者不是反方向離開，決策 29 第 9 點）。轉轍器的兩條支線、平面交叉的四個端點、在節點相交成角度的兩條邊都是；普通的直通節點（兩個相通的端點）與盡頭都不是；轉轍器的 stem 和每條支線都相通，所以也不是。
  - 列車（車身，或預約範圍）在某條邊上的區間，離這條邊的一個限界端的節點不到 `junctionZone`（里程距離 < 1024，與 S4 不檢查淨空的範圍相同）時，列車也**持有那個節點**。
  - 所以停在支線 a 的限界範圍內的列車持有交會點，經過交會點的進路就拿不到它；停在 stem 上、離轉轍器 300 的列車不持有交會點，在同一條線上接近轉轍器的列車不會被多擋。
  - 限界只存在於路網：方格的連結彼此垂直，除了格本身（節點）不會碰在一起，所以方格的節點就是整個交會範圍，和 S1 相同。
  - 限界是資源集合上的規則，不是幾何碰撞：只讀節點上端點的相通關係（`TrackNodeEnd.exits`）與整數里程。`occupiedResources(of:)` 不變（它回答「列車實際在哪裡」，之前所有 Stage 的 digest 都比較它），限界只加在交通控制的「持有」裡（第 6 點）。
  - 限界端由節點上有哪些邊決定，在節點加邊會改變它，所以交通控制開啟時，`buildTrackEdge` 不能在列車正持有的交會範圍上加邊（第 13 點）；拆邊只會讓限界變少，不會讓任何預約失效。

**6. 佔用、預約與持有。**

- **佔用**（occupied）：`occupiedResources(of:)`，列車現在實際站在哪裡，由位置與車身推導，不存檔。
- **預約**（reserved）：`Train.reservation`，列車已經取得、準備使用的資源，存檔。
- **持有**（held）：交通控制判斷衝突用的集合 = 佔用 ∪ 限界節點 ∪ 預約（查詢 `heldResources(of:)`）。行駛中的列車的佔用與限界一定落在它的預約裡（第 3 點），站著的列車沒有預約，只持有佔用與限界。
- **衝突**：一台列車要取得的預約範圍，和**其他**列車的持有有交集。自己的佔用與舊預約不算：列車可以換一條與舊路重疊的新路。只看預約、不看佔用是不夠的：一台沒有預約、實際停在某段軌道上的列車，仍然擋住那段軌道。
- **阻擋者**：有交集的其他列車中編號最小的一台（依 `TrainID` 遞增逐台檢查），不依字典、集合或建造順序。

**7. 生命週期。**

- **取得**（交通控制開啟時，第 9–11 點）：給列車新路的指令（`setTrainContinuation` 兩種、`placeTrain`、`reverseTrain`）、服務的出發、路線的派車，以及開啟交通控制。一律先完整驗證、算出候選的新狀態與它的預約範圍、和其他列車的持有比較，全部成立才一次寫入新的移動、位置與預約；否則世界完全不變。新預約**取代**舊預約。路的長度為 0 時不存預約（空）。
- **保留**：列車沿路移動時整份保留，T 不逐段釋放（第 16 點）；`setTrainMovementRate`（包括 0）、`stopTrainService`、`unassignTrain`、刪除路線或服務模式都不動它：停止服務不是緊急煞車，列車仍會走完它的路。
- **解除**：路走完（第 3 點的「站著」，包括路網上停在邊中段的 `end`，不只看 `remainingEdges` 是否為空）時，在那一步的移動之後清除；`unplaceTrain`；關閉交通控制。之後列車站著的軌道仍由佔用（與限界）保護。
- 因此交通控制開啟時的不變量是：列車還有路要走 ⇔ 它有預約，而且預約包含它現在的預約範圍（佔用、限界與剩下的路）；站著的列車沒有預約；任兩台列車的持有不相交。

**8. 交通控制的開關。**

- `GameWorld` 的新世界預設**關閉**：Stage I–S5 的所有 fixture、測試與 digest 不改變語義，也能證明關閉時的行為與 S5 完全相同。App 建立的新遊戲**開啟**（`GameWorld.newGame()` 之後呼叫 `setTrafficControl(true)`）。沿用舊 PR #31 的做法，沒有更好的現有機制（服務與路線都沒有「全域模式」可以借用）。
- `setTrafficControl(true)`（原本關閉時）不是只改旗標：依 `TrainID` 遞增為每台已放置的列車算出它現在應有的持有（站著的列車：佔用 ∪ 限界；有路的列車：它的預約範圍），任兩台相交就拒絕，回報 `trainsShareTrack(a, b)`：`b` 是第一台與前面某台相交的列車，`a` 是與它相交的最小編號。全部成立才一次寫入旗標與每台列車的預約；失敗時沒有任何列車拿到預約，世界完全不變。已經開啟時再開啟什麼都不做。
- 開啟時已經在等待被拆鐵軌的列車（決策 15）：方格的路包含之後可能補回的連結，預約範圍照樣包含它們的格與連結（它們的身分就是格的位置），所以補回後列車仍在預約內前進；路網的路斷在被拆的邊之前，永遠不會再前進，預約只到那裡為止。
- `setTrafficControl(false)` 一定成功：清除每台列車的預約，位置、移動、時刻表、執行進度與路線都不變，不瞬移、不反向；之後回到 S5 的互不阻擋。

**9. 指令與錯誤順序。** 既有的檢查與順序都不變，交通控制的拒絕一律排在它們**之後**（最後才判斷），所以任何以前會失敗的指令仍然以同一個錯誤失敗：

| 指令 | 錯誤順序（新的以粗體標示） |
| --- | --- |
| `setTrafficControl` | **`trainsShareTrack`**（只在開啟時） |
| `placeTrain` | `unknownTrain` → `trainAlreadyPlaced` → `invalidTrainPosition` → **`trackReserved`** |
| `reverseTrain` | `unknownTrain` → `trainNotPlaced` → `trainServiceActive` → **`trackReserved`** |
| `setTrainContinuation(_:to:)`、`(_:along:stoppingAt:)` | `unknownTrain` → `trainNotPlaced` → `trainServiceActive` → `invalidContinuation` → **`trackReserved`** |
| `removeTrack` | `outOfBounds` → `noTrackToRemove` → `trackInUse` → **`trackReserved`** |
| `removeTrackEdge` | `unknownTrackEdge` → `trackEdgeInUse` → `trackEdgeHasPlatform` → **`trackReserved`** |
| `addTrackPlatform` | `unknownStation` → `unknownTrackEdge` → `invalidPlatform` → **`trackReserved`** |
| `removeTrackPlatform` | `unknownStation` → `invalidPlatform` → `trainServiceActive` → **`trackReserved`** |
| `buildTrackEdge` | …… → `trackConflict` → `idsExhausted` → **`trackReserved`** → `insufficientFunds`（扣款仍是最後一個可能失敗的步驟，決策 4） |

- `trackReserved(TrainID)`：交通控制開啟時，那台列車（編號最小的一台）持有這個指令需要的軌道。
- `placeTrain`：放上去的列車要求它站的軌道、限界，以及它本來就會走完的那一段（在連結上到 `to` 端；路網上沒有路時到邊的終點）。
- `reverseTrain`：照舊清除路；列車反向後的佔用與反向前相同（車頭移到車尾，決策 27、29），但它會走完反向後的連結或邊（決策 15、S5），這一段要能取得。停在節點的方格列車反向後站著，預約解除。
- `unplaceTrain`、`setTrainMovementRate`、`setTrainTimetable`、`startTrainService`（列車一定站著）、`stopTrainService`、路線指令：不需要新的檢查。

**10. 服務的出發與路線的派車。**

- **出發**：S5 仍然先得到 `TrainPath`；標記折返的停靠先在**假設**的折返位置上求路。然後 T 算出「折返後、走這條路」的候選狀態的預約範圍：
  - 成立：一次寫入折返、路、預約與 `.travellingToStop`，列車離站；
  - 被持有：什麼都不改（不折返、不寫路、不取消服務），列車保持 `.waitingAtStop`，下一個基本步長再試。和「沒有路」不同，這個結果不會記在同一次 `advance` 的「找不到路」清單裡：其他列車移動、走完路之後，軌道就會空出來。
  - 零距離到達與服務完成（原地站著、必要時折返）不需要新的軌道：折返不改變佔用，所以不會被擋。
- **派車**（Q2b、Q3）：就緒的條件多一條：交通控制開啟時，列車的第一個出發（折返與否照它的一趟決定）要能取得預約。取不到的列車不就緒：路線不派出它、不改 `lastDispatch`、不寫時刻表或執行進度、不折返，下一分鐘再試；依 ID 下一台就緒的列車可以派出。
- **派出的列車立刻出發**：派車（第 0 段）之後，被派出的列車在同一段就依出發的規則離開第一站，而不是等到第 1 段依 ID 輪到它。交通控制關閉時結果完全相同（出發彼此不互動，派車的判斷也不讀這台列車的位置）；開啟時，這讓「派出」與「取得進路」成為同一件事：第 1 段的其他出發不可能在中間搶走它剛確認可以取得的進路，所以不會發生「記了派車卻沒出發」。
- **規劃查詢不受影響**：`lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway`、`lineSegmentLoads` 繼續回答「計畫上能怎麼開」，不讀預約。
- 事件感知的快轉仍然精確：一步沒有任何改變時，被擋住的出發與派車在之後也不會被放行（只有其他列車移動、走完路或指令才會釋放軌道），所以喚醒時刻不變。

**11. 等待原因的查詢。** `trainHoldingRoute(of:) -> TrainID?`，唯讀、即時推導，不存等待原因：

- 服務停在某站、排定出發已到（`<=` 現在）時：候選出發（折返後的路）的預約範圍被哪台列車持有，回報編號最小的一台；
- 路線的列車：沒有服務、停在它的服務的第一個停靠站、路線現在該派車、除了預約之外都就緒時，同樣回報第一個出發的阻擋者；
- 其他情況（交通控制關閉、還沒到出發時刻、沒有路、路是空的、未知的列車）是 `nil`。方格與路網同一段程式。

**12. 同時的要求與決定性。** 同一個基本步長裡：第 0 段依 `LineID`、服務的順序派車（被派出的列車立刻取得進路），第 1 段依 `TrainID` 遞增處理出發；先處理的先取得，後處理的等待。這只是 T 的最小決定性規則，不是 dispatcher 的優先順序（V 才做快慢車、交會與待避）。預約的資源依既有的順序排序存放；阻擋者取最小編號；沒有任何結果依字典或集合的走訪順序決定。

**13. 基礎設施的變更與 span 身分的持久性。** 交通控制開啟時，預約中的基礎設施不能被偷偷拆掉或改變意義，但不相干的建設不受影響：

- `removeTrack`：任何列車預約了那一格或以它為一端的連結時拒絕。`removeTrackEdge`：任何列車預約了那條邊的 span 時拒絕。（列車實際站在上面的情況照舊是 `trackInUse`、`trackEdgeInUse`。）
- `addTrackPlatform`、`removeTrackPlatform`：月台的兩端會切開或合併那條邊的 span，所以任何列車**持有**那條邊的 span（預約或站在上面）時拒絕：前者讓已存的 span 失去意義，後者可能把兩台列車所在的相鄰 span 合成一個而產生衝突。沒有列車的邊照常可以改。
- `buildTrackEdge`：新邊的兩端節點若被列車持有，或有列車持有這個節點上某條邊離它不到 1024 的 span（限界範圍），拒絕，因為新邊可能改變那裡的限界端（第 5 點）。其他地方照常建造。
- `removeTrackNode` 只能拆沒有邊的節點；被預約的節點一定還有被預約（因此不能拆）的邊，所以不需要新的檢查。方格的鋪軌、轉轍器、平面交叉只能在空格，不會改變既有的格與連結。
- **證明：一份預約存活期間，它的每個 `TrackResource` 身分不會變成另一個意思。**
  - 節點：路網節點的 ID 不重用；方格節點就是格的位置，格不會移動。
  - 方格的連結永遠是一整個 span（0 到 1024），沒有月台會切開它。
  - 路網的 span 是邊的區間，由邊長與這條邊上的月台決定。邊的幾何建好後不再改變、ID 不重用；被預約的邊不能拆；它上面的月台不能新增或移除。所以它的切法在預約存活期間不變，存下來的 `TrackSpan` 一直是目前切法中的一段。
  - 關閉交通控制會清掉所有預約，之後的改動不受限；再開啟時從當下的切法重新計算。讀檔時以存檔裡的路網重新驗證每個 span（第 14 點）。

**14. 存檔。**

- 世界只在開啟時寫 `"trafficControl": true`；列車只在有預約時寫 `"reservation"`。所以交通控制關閉、沒有預約的世界與 S5 逐位元相同；舊存檔讀成關閉、沒有預約。明確的 `null`、不是布林值的旗標一律拒絕。
- 資源的存檔格式（`TrackResource` 的 `Codable`）：方格的格 `{"tile": {"x", "y"}}`、路網節點 `{"node": n}`、方格連結 `{"link": [{"x", "y"}, {"x", "y"}]}`（逐列由北到南、每列由西到東較前面的一格在前）、路網的 span `{"edge": n, "start", "end"}`。恰好一種 tag。
- `Train` 的解碼（不看地圖）拒絕：形狀不對的資源（沒有或多於一種 tag、編號小於 1、連結的兩格不相鄰或順序顛倒、`start < 0`、`start >= end`）、沒有依順序排列或重複、未放置的列車有預約、明確的 `null`。
- `GameWorld` 的解碼（對照地圖與路網）拒絕：交通控制關閉卻有預約；預約的資源不存在（節點、連結、邊，或不是那條邊目前切法中的一段 span；唯一的例外是第 8 點的方格等待修復：列車之後的路上還沒補回的格與連結）；列車還有路要走卻沒有預約、預約沒有包含它現在的預約範圍，或站著的列車有預約；任兩台列車的持有相交。
- 不修正、不刪除：預約裡列車已經走過的資源是合法的鎖，即使無法由目前位置推導；多預約的資源只是保守，不是錯誤。
- 仍然沒有存檔版本或 migration。

**15. 避免死結的最小規則。** T 一次取得到下一個停靠點（服務的下一站、手動的路的終點）的**整條**進路，拿不到就一點都不拿、原地等待；不會一邊走一邊取得下一小段，所以沒有「拿一半、等另一半」的基本 hold-and-wait。仍然可能出現的等待，T 不解決，留給 Stage V 的 dispatcher：

- 單線上兩端的列車各自等對方讓出的軌道；
- 時刻表的安排造成循環等待；
- 兩台站著的列車各自站在對方需要的軌道上。

T 也不繞路：最短的 canonical `TrainPath` 被擋住時就等待，不找第二短的路、不改月台、不讓快車先走。

**16. 與 Stage U 的分界。** T 的安全來自「出發前一次取得整條路」，移動 kernel **不改**：列車照 S3、S5 的規則移動，不在進入每個 span 前檢查授權，也不在通過後釋放。所以 T 比真實的號誌保守、容量較低（後車要等前車走完整條路才能出發），這是預期的。U 可以直接建立在這裡：

- 權威、存檔的 `Train.reservation`，依資源順序排列；
- 移動路徑（`TrainMovement`、`pathAhead(of:)`）、`TrackTraversal`、`TrackSpan`、佔用與限界的 helper；
- 路走完的 hook（移動之後清除預約的那一處）。

U 只需要加上：movement authority 的檢查、只能進入已預約的資源、通過後釋放；不需要重新設計預約的表示、路、月台或存檔。

**17. 效能。** 預約與衝突只讀 topology、`TrackTraversal`、`TrackSpan`、邊長、月台區間、`TrainPath.end` 與車身，不取樣、不讀畫面。找阻擋者時掃描每台列車算它的持有（O(列車數 × 車身與路的 span 數)）。在有量測證據之前，不建立全域的佔用索引、鎖管理器的快取或空間樹。

**18. 舊行為。** 交通控制關閉時，所有指令、`advance` 與查詢的結果和 S5 相同，存檔逐位元相同；預期 Stage I–S5 的所有 property digest 不變（派車後立刻出發在關閉時結果相同，第 10 點）。實作後逐一確認；若有改變，逐項說明。

**19. 與舊 PR #31 的關係。** 保留的語義：交通控制旗標（新世界關閉、App 開啟、只在開啟時存檔）、一次預約到下一個停靠點的整條路、整批原子取得、路被佔時服務原地等待並每步重試、不折返、阻擋者取最小編號、`trackReserved` 與 `trainsShareTrack`、`trainHoldingRoute`。改變的設計：預約改成**存檔的權威狀態**（PR #31 由位置與 continuation 即時推導，無法表示 U 之後的部分預約，也無法保存已經走過、尚未釋放的軌道）；資源改成泛用的節點與 span；路改成 `pathAhead(of:)` 與 `TrainPath`；加上路網的限界規則、月台與加邊的保護。沒有沿用 PR #31 的程式。

#### 實作

- **錯誤**（`GameError`）：`trackReserved(TrainID)`、`trainsShareTrack(TrainID, TrainID)`；玩家看到的文字在 `DisplayText`。
- **資源的存檔**（`TrackResources.swift`）：`TrackResource` 的 `Codable`（第 14 點的四種 tag 與形狀檢查）。佔用的推導抽成 `occupied(_ train:)`，交通控制與 `occupiedResources(of:)` 共用。
- **列車**（`Train.swift`）：`reservation`（`internal(set)`，公開讀取），只在非空時存檔；解碼拒絕沒有排序、重複、未放置的列車有預約。
- **預約**（`RouteReservation.swift`，新檔）：
  - `TrackStretch`（一條邊或方格連結上沿行進方向的一段里程）；`routeStretches(of:)`（車頭自己會走完的路，第 3 點）、`bodyStretches(of:)`（車頭到車尾）。
  - `resources(covering:)`：佔用與預約共用的逐點規則（第 4 點）；路網的 `networkResources(of:)` 改成以它計算車身，結果不變。`foulingNodes(covering:)` 與 `isFoulingEnd(of:at:)`（第 5 點）。
  - `routeEnvelope(of:)`（佔用 ∪ 路的資源 ∪ 車身與路的限界，以及路是否還有距離）、`held(_:)`、`holder(of:except:)`（依 ID 第一台）、`reserving(_:)`（`granted` 或 `held(by:)`）。
  - 公開查詢：`reservedResources(of:)`、`heldResources(of:)`、`trainHoldingRoute(of:)`（服務用出發的同一個 `leaving(_:stop:cycle:)`；路線用派車的 `readyTrip(of:on:_:memo:)` 與 `firstDeparture(of:on:calling:)`）。
- **指令**（`GameWorld`；失敗時世界不變）：
  - `setTrafficControl(_:)`（第 8 點）。
  - `placeTrain`、`reverseTrain`、`setTrainContinuation` 兩種先算出候選的列車，交給 `admit(_:at:)` 一次寫入位置、移動與預約；`unplaceTrain` 清除預約。
  - `removeTrack`、`removeTrackEdge`、`add/removeTrackPlatform`（`requireSpansUnheld(on:)`）、`buildTrackEdge`（在 `idsExhausted` 之後、扣款之前）的保護（第 13 點）。
- **`advance`**：
  - 派車段的 `readyTrain` 在交通控制下跳過第一個出發被持有的列車；被派出的列車由 `departService(_:unroutable:)` 在同一段出發（第 10 點）。
  - 出發段把每一次離站寫成 `Leaving`（`completes`、`arrives`、`setsOff`、`noRoute`），由 `leaving(_:stop:cycle:)` 在不改世界的情況下算出，再交給 `reserving(_:)`；被持有時什麼都不寫、也不記進「找不到路」。
  - 移動之後 `releaseEndedRoute(_:)` 清除走完的路的預約（U 的接點）。
- **存檔與驗證**（`GameWorld` 的 `Codable`）：`"trafficControl"` 只在開啟時寫；`trafficProblem()` 與 `resourceExists(_:)` 檢查第 14 點的每一條（包括方格等待修復的例外），不修正、不刪除。
- **效能**：本輪沒有做效能量測。取得與查詢都是對每台列車算一次持有（第 17 點），沒有索引或快取。`traffic.reservation` 在 debug build 上跑 12,800 個操作約 2.5 分鐘，其中大部分是參考模型與逐步的整個狀態比較，不是效能數字。

#### 驗證

- `TrafficControlTests`（手算，27 個）：
  - 關閉時與之前相同；開關；開啟時共用與相遇的路被拒絕；方格的整條路、連結跑到 `to` 端與反向、長列車從車尾預約、後車等前車走完整條路、平面交叉與轉轍器是一格；
  - 服務在站等待且不折返、`trainHoldingRoute`、路線不派出等不到路的列車且不改上次派車、等待修復的方格路；
  - 路網的 span：只取需要的 span、第一條與最後一條邊的一部分、停在分界上兩邊都取、長列車從車尾；彎道（7 段，906…5439）、高架與地下月台（月台切開的 span、兩個方向的停車位置）；
  - 轉轍器在節點相遇、停在支線限界內的列車持有交會點而 stem 上的不持有、兩條支線都在限界內時不能開啟、持有的交會點不能加邊；平面交叉共用節點、立體交叉互不相干；
  - 持有的邊不能加減月台、預約的邊不能拆；路網的服務等待並只在能走時折返；存讀、壞掉的存檔被拒絕（多預約的資源可以讀）。
- `ReferenceWorld`（`ReferenceTrafficControl.swift` 等）另外寫一次決策 32，而且盡量寫得不同：列車需要的軌道由整條來路與去路上的一個絕對距離區間讀出，限界端每次查詢時掃描每條邊，阻擋者逐台比較，開啟時逐對檢查，路線是否就緒、出發會拿什麼在世界的複本上實際執行一次。
- `TrafficControlPropertyTests`（`traffic.reservation`，40 個 case × 4 個種子 × 80 個操作 = 12,800 個操作，digest `C6419E59862453C5`，CI campaign shard，分配見 `swift-shards.sh` 的 `classes_of`）：方格（轉轍器、平面交叉、兩格的車站）與路網（直線、S 曲線、坡道、高架、隧道、支線，有時有菱形平面交叉與 1024 高的立體交叉，每站兩三個月台）上的 3 到 4 台 1 到 4 節的列車，執行交通控制的開關、放置與取下、手動的路與到車站的路、反向、時刻表、路線與服務模式、拆建鐵軌、邊與月台、在節點加支線與時間，同時在 GameCore 與 `ReferenceWorld` 上執行。每一步比較結果與整個狀態，以及每台列車的預約、持有、佔用與 `trainHoldingRoute`；並檢查不變量與存讀。量：取得的預約 787、被拒絕的取得 258、出發與派車取得 162、服務出發 622、服務等待 2,501、路線派車等待 203、方格衝突 126、路網 span 衝突 234、長列車的預約 523、停在邊中段的預約 240、開啟被拒絕 115、基礎設施被拒絕 102、走完路釋放 342。
- `SaveMutationTests` 新增 `save.trafficMutation`（12 個 case × 4 個種子，每個 30 次變異，也翻轉布林值）：載入 516、拒絕 924、瞄準交通控制與路的變異 1,098、翻轉 77、載入的有預約的世界 134；載入的世界都保持不變量、可以存讀，之後的指令也保持一致。
- `WorldInvariants` 在每個 campaign 的每一步檢查決策 32：關閉時沒有預約；開啟時任兩台列車的持有不相交，預約依資源順序、屬於已放置的列車、包含它站著的軌道，明顯站著的列車沒有預約、明顯在路上的有。
- Golden schema v19 與手算的 `traffic-reservation.json`（72 步：轉轍器 J 的限界讓開啟被拒絕；Up 與 Down 在第 1 分鐘爭同一段單線，Up 先取得從車尾（2048，分界）到 East 停車位置的整條路，Down 等待；Freight 移到立體交叉上並預約兩條邊；Up 在第 9 分鐘那一步到站並釋放，Down 在第 10 分鐘那一步出發，停在 West 的後退停車位置（里程 1024，分界）；預約中的邊不能加月台或拆除），第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過；既有的 18 個 fixture 只加上中性的值。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄（主工作目錄的 `Sources` 從未改動）；四個都在 `traffic.reservation` 第一個種子的 case 0 被抓到，golden 也都失敗：
  - 路中間相接的節點沒有預約（立體交叉上的 node 6 也漏掉）：case 0 的第 7 步，另有 12 個手算測試失敗；
  - 只預約車頭的路、不含車身：case 0 的第 38 步，另有 7 個手算測試與 1 個 GamePresentation 測試失敗；
  - 服務出發不看預約：case 0 的第 3 步，另有 3 個手算測試失敗；
  - 路的最後一條邊少算 1（停在分界上時漏掉另一邊的 span）：case 0 的第 49 步，另有 1 個手算測試失敗。

#### GamePresentation / App

- `GameSession.setTrafficControl(_:)` 套用同一個指令並回報結果；被拒絕的路與開啟以玩家的文字說明是哪台列車。
- `routeWaitText(of:)` 由 `trainHoldingRoute(of:)` 即時推導「Waiting for <列車> to clear the route」，不存檔。
- App 的新遊戲開啟交通控制；路線面板有開關（開啟被拒絕時開關回到關閉、狀態列說明原因）；列車面板顯示等待。
- Debug 的示範配置讓 Local 在 Hill 等主線上的列車讓出四向交叉；新遊戲的資金只夠三台列車，所以 Local 取代了隧道裡的 Mole（隧道、高架與交叉的鐵軌仍在）。以原樣的 `DemoLayout.swift` 在 Linux 上編譯並模擬 130 分鐘：Local 從第 1 分鐘等到第 95 分鐘，第 96 分鐘出發，之後照時刻表往返。

#### 已知限制與留給之後

- 容量比真實的號誌低：後車要等前車走完整條路才能出發，通過的軌道不逐段釋放（U）。
- 死結不解決：單線上兩端的列車各自等對方、時刻表造成的循環等待、兩台站著的列車各自擋住對方（V）。`traffic.reservation` 的量也因此偏低。
- 不繞路、不換月台、不讓快車先走（V）；規劃查詢（`lineJourney` 等）不讀預約。
- 限界範圍固定是節點 1024 以內，只看邊端的相通關係與里程、不讀幾何：分岔角度很小、1024 以外仍然很靠近的兩條邊（S4 只檢查平面上的相交，還沒有軌道寬度的側向淨空）不受保護；側向淨空屬於之後的幾何工作。
- 交通控制下沒有「強制」的操作：玩家要先讓持有軌道的列車離開、取下它，或關閉交通控制。

### 33. 行駛曲線的計算核心（Phase 4.7 Stage W1）

W1 照原樣移植作者 `Railway/` 網站的跑段曲線，還不接到任何列車：決策 1–32 的行為、存檔、golden 與 property digest 都不變。

- **翻譯的對象**（私有 repo `b52f05c` 的 `Railway/site_archive_clean/index.html`）：
  - `buildProfile` → `RunningCurve.init?(length:duration:acceleration:braking:topSpeed:coast:)`；
  - `assignRunProfiles` 裡依序改用 `bAlt`、`aAlt` 的三次嘗試 → `RunningCurve.init?(length:duration:performance:)`；
  - `profTimeToProg` × L → `distance(at:)`；
  - `profProgToTime` → `time(atDistance:)`；
  - `PERF_DEFAULT`、`PERF_HSR`、`PERF_DR1000`、`PERF_RULES`、`PERF_BY_TYPE` 的數值 → `TrainPerformance` 的預設值。
- **照原樣保留的**（faithful）：
  - 公式：D = 1/(2a) + (1 − ρ)²/(2c) + ρ(2 − ρ)/(2b)，vc 是 D·v² − T·v + L = 0 的較小根；
  - 四段：加速、定速、惰行、煞車；
  - 沒有曲線的條件：判別式為負、vc ≤ 0、定速時間為負、超過最高速；
  - 惰行：先試 ρ₀，超速時在 [ρ₀, 1] 二分 14 次，保留最後一個合格的；
  - 改用備用性能的順序，以及所有性能數值。
- **機械換算**（公式不變）：
  - 距離用世界單位（1/64 公尺），時間用毫秒；
  - 加速度、煞車與惰行減速用千分之一 km/h/s（參考的值最多三位小數），最高速用 km/h；
  - ρ 用千分之一；二分在分母 1000 × 2¹⁴ 上進行，參考的 14 次二分因此都是精確的；
  - 內部刻度：D × 2²⁴、速度（每毫秒的單位）× 2³²、時間與距離 × 2¹⁶，其餘一律無條件捨去；
  - 平方根改成整數平方根；
  - vc 以等價的 2L ÷ (T + √(T² − 4DL)) 計算，避免整數相減的精度損失；
  - 超速的解在 `solve` 裡就捨棄：參考的每個呼叫端都會丟掉它，這樣也讓之後的乘積留在 128 位元內；
  - 參考的梯形分支不夾住結果，整數結果可能差一個單位，所以 `distance(at:)` 夾在 `0...length`、`time(atDistance:)` 夾在 `0...duration`。
- **128 位元**：`WideInteger` 只用標準函式庫的 `multipliedFullWidth` 與 `dividingFullWidth`。不用 `UInt128`，因為 App 支援的 iOS 17 沒有它。
- **範圍**：長度 ≤ 2⁴⁰ 單位、時間 ≤ 2³² 毫秒、各率 ≤ 2²⁰；超出範圍或不為正時沒有曲線，就像參考遇到非正值時回傳 `null`。
- **這次沒有移植的**（之後的 W，或等作者決定）：
  - 通過實測時刻的曲線（`buildObsProfile`）；
  - 限速區段（`SPEED_ZONES` 與相關函式）；
  - 依車名選車種性能（`resolvePerf`）：遊戲的列車還沒有車名或車種；
  - 由性能反推時刻表的時間，以及秒與分鐘的解析度（留給 W2）。
- **驗證**：
  - `RunningCurveTests` 的手算案例：2 km、105.25 秒、a = 2.5、b = 3，判別式是 22,750² 的完全平方，vc 正好是每毫秒 2 單位；每一段的時間與距離，以及抽樣的距離與時間都是精確整數。
  - 沒有曲線的案例、備用性能的順序、無效的惰行、極端值不溢位。
  - 所有預設值與參考的數值相同。
  - 差分：`ReferenceRunningProfile` 在測試裡把 JavaScript 逐行寫成 `Double`，4,000 個案例涵蓋所有預設值、200 m 到 80 km、從最快時間的 0.9 倍到 4 倍。
    - 有沒有曲線、惰行的 ρ 都一致；
    - 距離相差不到 2 個單位（3 公分），時間相差不到 2 毫秒；只有接近停車、參考的平方根本身病態的地方，依當時的速度放寬。
  - `WideIntegerTests` 對照 64 位元的結果與全寬的邊界。
  - 刻意植入的錯誤都被抓到，驗證後還原：二分 13 次、定速段用了煞車速度、忽略惰行的 ρ₀、備用性能的順序錯誤。
- **不變的**：沒有新的指令、錯誤、存檔欄位或 golden schema；既有的 golden 預期值與 property digest 全部不變。

### 34. 車站需求、釋出、排隊與守恆（G1a）

G1 的第一步：車站有需求，需求推導出每對車站之間每天、每小時的旅次，每分鐘以整數釋出成等車的乘客，乘客在起點依路線、方向與目的地排隊，每一位都記在守恆稽核裡。還沒有上下車（G1b）、票價與帳本（G1c）。車站沒有需求時什麼都不發生：決策 1–33 的行為、存檔、既有 golden 的預期值與 property digest 都不變。

**來源**：作者的 `Ci/` 網站（私有 repo `7cfb300` 的 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，minified，以 prettier 展開後閱讀）。

| 參考 | Swift | 分類 |
| --- | --- | --- |
| `buildStationFlowPresetCurves(e, kind)`：四種 preset（`office`、`residential`、`shopping`、`scenic`）的 `1 + a·exp(−½((h − μ)/σ)²)` | `StationDemandKind` 與 `departureShape`、`arrivalShape` 的 24 小時千分比表 | 公式 faithful；GameCore 沒有 `exp`，事先算成表（機械換算），測試用 Foundation 的 `exp` 逐格重算 |
| `normalizeStationFlowPresetRowToDailyBase`（沒有伺服器的基數時：乘上 24 ÷ Σ，夾在 0…11） | 同一張表已正規化，四捨五入到千分之一（`Math.round`） | faithful＋機械換算 |
| `getStationFlowAdjustXDomainHours`（預設 0–23 時） | 固定 24 小時 | faithful |
| `applyStationHourlyODMultsToHourlyOD`：`base[o][d][h] × out_o[h] × in_d[h]` | `hourlyDemand(from:to:)`：`dayShape[h] × departureShape_o[h] × arrivalShape_d[h]` 的權重 | 公式 faithful；`base` 是 gap（見下） |
| `PARAMS.PEAK_FACTOR`（夜間 0.1、7–9 與 16–19 時 1.5、8 與 18 時 1.8、其餘 6–22 時 0.6 + 0.02h） | `StationDemand.dayShape`（千分比） | 參考的數值照抄；參考裡定義了但沒有被呼叫，這裡拿來補 `base` 的時間形狀 |
| `metroSpawnPassengersFromDispatchRuntime`：`(1 − f)·R_h + f·R_{h+1}`（`f` 是分鐘在這一小時裡的比例）÷ 60 × 分鐘數 | `advance` 的乘客階段：`((60 − m)·R_h + m·R_{h+1}) ÷ 3600` | faithful＋機械換算 |
| `_metroFlowSpawnCountFromRate`：每個 key 的小數累加器，取 floor | `StationPassengers.remainders`（1/3600 位，存檔） | faithful＋機械換算 |
| `_metroAdmitDispatchPassengers`、`metroAddWaitingQueueTarget`：`waitingQueue[dir].targets["路線_迄點索引_迄點"] += n`，放不下的加進 `overflow` | `StationPassengers.release(_:to:along:at:)`、`WaitingGroup`、`overflowed` | 結構 faithful；排隊順序見第 5 點 |
| `metroGetStationWaitAdmitHeadroom`、`metroResolveStationWaitCap`（整個車站等車的總數 ≤ `line.cap × 8`，沒有 cap 時 `STATION_CAPACITY 500 × 8`） | `StationPassengers.capacity = 4000` | faithful（還沒有列車容量，所以用預設值；G1b 再看） |
| `spawnPassengersFromGlobalOD` 的後備路徑：從起點的路線裡找第一條同時停兩站的，用 `findStationIndexOnLine`（第一個索引）比大小決定方向 | `passengerTrip(from:to:)`：編號最小、同時停兩站的路線，第一次停靠的索引 | faithful |
| `spawnPassengersFromGlobalOD` 的 `poissonSample` 與 `Math.random` | 不採用 | 參考的舊路徑，不是 deterministic；現行路徑是上面的累加器 |

**1. 需求**：`StationDemand { kind, dailyTrips }`，`dailyTrips` 在 `0...1_000_000`（讓所有整數乘積都遠在 `Int64` 以內）。`setStationDemand(_:to:)` 設定或以 `nil` 清除，免費；檢查順序 `unknownStation` → `invalidStationDemand`。清除需求不影響已經在等的人。

**2. 每天的旅次（gap 的補法）**：參考的基數是伺服器由真實人口算好的 OD，快照裡沒有。這裡：起點一天的 `dailyTrips` 分給它能到、而且自己有需求的車站，比例是那些車站自己的 `dailyTrips`，以最大餘數法變成整數（平手給站號小的）。沒有需求的車站不產生也不吸引旅次。

**3. 每小時的旅次**：一對車站一天的旅次，依 `dayShape[h] × departureShape_o[h] × arrivalShape_d[h]` 以最大餘數法分到 24 小時（平手給較早的小時），合計正好等於一天。起點用 `out`、迄點用 `in`，和參考相同。

**4. 每分鐘釋出**：基本步長從 `T` 到 `T + 1` 的第一個階段（在派車之前）。在一天中第 `h` 小時第 `m` 分，每一對把 `(60 − m)·R_h + m·R_{h+1}` 加到自己的餘數，整除 3600 的部分就是這一分鐘釋出的人數，餘數留到下一分鐘。每個小時的旅次在自己與前一個小時裡合計被算 1830 + 1770 = 3600 次，所以任何連續 1440 分鐘，每一對正好釋出一天的旅次，餘數回到原來的值。同一分鐘依（起點、迄點）的順序釋出。
- 這一階段不讀、也不改任何列車。`advance` 跳過沒有列車變化的步長時，照樣逐分鐘釋出被跳過的那幾分鐘，結果和逐步推進完全相同。
- 每一對的每小時旅次只由需求與路線的停靠推導，算好的計畫（`PassengerPlan`）留在世界裡，跨 `advance` 呼叫沿用；`setStationDemand`、`createLine`、`setLineStops`、`removeLine` 與讀檔時丟掉，下一次推進時重算。它不是遊戲狀態：不存檔，也不影響兩個世界是否相等。餘數在每次呼叫開始時讀出、結束時寫回。

**5. 排隊**：釋出的人在起點排隊，一分鐘、一個迄點一組（`WaitingGroup { line, direction, destination, since, count }`），依釋出的順序排在最後，所以先來的在前（ROADMAP 5D 的先進先出；參考只有依 key 加總的人數，沒有順序）。車站等車的總數最多 4000：放得下的部分成為一組，其餘立刻離開，記進 `overflowed`。

**6. 路線改變**：`removeLine` 或 `setLineStops` 之後，等的路線已經不再以那個方向載他們去迄點的組離開車站，記進 `abandoned`；其他組保持原來的順序。參考裡刪除路線時連同那條路線的車站物件一起刪掉，等車的人也跟著消失；這裡把他們記下來，讓守恆可以稽核。新增路線不影響已經在等的人（他們仍等原來的路線）。

**7. 守恆稽核**：每一站 `released = waiting + overflowed + abandoned`（`PassengerLedger`）。G1b 加上車上與到達的人（決策 35）。

**8. 依賴方向**：乘客只讀車站的身分、路線的停靠與編號，以及時間；不讀 `TrackTraversal`、`TrackResource`、預約或 `TrainMovement`，也不改列車。

**9. 存檔**：`"passengers"` 只在有乘客紀錄時寫；每一筆是 `{ station, demand?, waiting, released, overflowed, abandoned, remainders }`，依車站排序。沒有需求、從未釋出、也沒有餘數的車站沒有紀錄。解碼拒絕：
- 數不合（`released` ≠ 等車 + `overflowed` + `abandoned`）、負數、超過容量；
- 組不照來的順序（依釋出的分鐘，同一分鐘依迄點遞增，不重複）、組的人數小於 1、釋出時間不早於現在（從 T 開始的步長在 T 釋出、結束在 T + 1）、組的路線不存在或不再以那個方向載他們；
- `released` 超過 2⁶²（一站一天最多釋出一百萬人，從這個數要幾百萬年才會溢位）；
- 餘數不在 1…3599、重複或沒有排序、給自己或不存在的車站；
- 紀錄沒有排序、屬於不存在的車站、或什麼都沒有；`"demand": null`。

**Gap（參考沒有，這裡補上）**：每天的基數與迄點的分配（第 2 點）、先進先出（第 5 點）、放棄等車的人與守恆稽核（第 6、7 點）。

**沒有移植的**（之後的 Stage）：
- 轉車樞紐的倍率（`STATION_FLOW_HUB_AIRPORT_MULT`、`STATION_FLOW_HUB_RAIL_MULT`）：遊戲還沒有機場或轉車站的種類。
- 票價對需求的影響（`metroFareOdMultiplier`，G1c 之後）、事件的需求倍率（`metroEventDemandMultiplier`）。
- 伺服器的路徑選項與 `choiceProb`（5C），轉車（5F），車站的進出管制（`metroStationBlocksEntry`）。
- 玩家自訂曲線（參考的自由模式可以逐小時拖曳）：只有四種 preset。

#### 實作

- `Passenger/StationDemand.swift`（新目錄）：`StationDemandKind` 與四組曲線、`StationDemand`、`dayShape`。
- `Passenger/StationPassengers.swift`：`LineDirection`、`PassengerTrip`、`WaitingGroup`、`DemandRemainder`、`PassengerLedger`、`StationPassengers`（等車人數的總和與組一起維護），以及各自的 `Codable`。
- `Passenger/PassengerDemand.swift`：`setStationDemand(_:to:)`；查詢 `stationDemand(of:)`、`waitingPassengers(at:)`、`passengerLedger(of:)`、`passengerTrip(from:to:)`、`dailyDemand(from:to:)`、`hourlyDemand(from:to:)`；推導、最大餘數法、釋出的計畫（`PassengerPlan`，每條路線的第一次停靠只查一次，24 小時的旅次存成一個連續陣列）與它的快取（`PassengerPlanCache`）、每次呼叫的釋出（`PassengerRelease`）、路線改變時的放棄與存檔驗證。
- `GameWorld`：`passengers`（`internal(set)`，只由乘客的規則寫入）、`advance` 的乘客階段、`removeLine`／`setLineStops` 之後的放棄、`Codable`；`GameError.invalidStationDemand` 與玩家的文字。

#### 驗證

- `PassengerDemandTests`（手算，18 個）：
  - 曲線表與 `dayShape` 由參考的公式（Foundation 的 `exp`、正規化、`Math.round`）逐格重算；
  - 指令的檢查順序、清除需求時丟掉空的紀錄；路線的選擇（編號最小、第一次停靠、方向）；最大餘數法的平手；
  - 每天的分配（1000 → 750 : 250 等）、沒有需求的車站不吸引旅次；一天一個旅次落在 8 時（或回程的 18 時）；
  - 一天一個旅次在 08:59（第 539 分鐘）釋出：07:00–07:59 累加 1770，08:00–08:58 再加 1829，第 539 分鐘補滿 3600；
  - 從第 0、777、1439 分鐘起的任何 1440 分鐘都正好釋出一天的量、餘數回到原值；
  - 排隊的順序、容量 4000 與溢出（一百萬旅次的一天：等車 4000、溢出 996,000）、一次推進與逐分鐘推進的世界相同（也跨 2x）；
  - 路線改停靠、反向、刪除時的放棄與保留、清除需求時等車的人留下；存讀、沒有乘客的存檔沒有 `"passengers"`、20 種壞掉的存檔都被拒絕（包括同一分鐘的組順序顛倒或重複、`released` 超過 2⁶²）；
  - 跨呼叫保留的計畫在每個改變需求或路線的指令之後都和重算的相同，讀檔的世界沒有計畫、而且和原來的世界相等。
- `ReferencePassengers`：`ReferenceWorld` 另外寫一次決策 34，而且寫得不同：曲線每次由 `exp` 算出、每分鐘重新找旅次（不保留一次呼叫的計畫）、最大餘數法逐一挑最大的餘數而不是排序、一分鐘的份寫成 `60·R_h + m·(R_{h+1} − R_h)`、等車人數需要時才加總。每個 golden scenario 都在它上面重跑。
- `PassengerPropertyTests`（`passenger.differential`，20 個 case × 4 個種子 × 50 個操作 = 4,000 個操作，digest `62042B9B922FCE2C`，CI campaign shard）：3 到 6 座車站，從隨機的分鐘（也有第 0 分鐘以前）開始，執行各種大小的需求（含最大值與不合法的值）、建立、改停靠與刪除路線、各種速度與長短的時間，同時在 GameCore 與 `ReferenceWorld` 上執行。沒有鐵軌與列車，所以 GameCore 的每一步都可能被當成閒置跳過，被跳過的分鐘的釋出因此也和逐分鐘推進的參考比對。每一步比較結果、每一站的排隊、數與餘數、每一對的旅次與每小時的旅次，並檢查不變量與存讀。量：釋出 61,314,671 人；有釋出的站次 1,188、溢出 675、放棄 158；不合法的需求 93、不存在的車站 69、刪除路線 142、改停靠 225。
- `SaveMutationTests` 新增 `save.passengerMutation`（12 個 case × 4 個種子，每個 30 次變異）：載入 506、拒絕 934、瞄準乘客、路線、車站與時鐘的變異 1,053、載入後有人在等的世界 189；載入的世界都保持不變量、可以存讀，之後的指令也保持一致。
- `WorldInvariants` 在每個 campaign 的每一步檢查守恆：每一站 `released = waiting + overflowed + abandoned`、不超過容量、組依來的順序、組的旅次仍然存在、紀錄依車站排序而且不是空的。
- Golden schema v20 與手算的 `station-demand.json`（41 步；預期值另以獨立的 Python 實作依規則算出），第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過；既有的 19 個 fixture 只加上 `"passengers": []`。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄（主工作目錄的 `Sources` 從未改動）；五個都在 `passenger.differential` 第一個種子的 case 0 被抓到，手算測試與 golden 也都失敗：
  - 內插的兩個權重對調（`m·R_h + (60 − m)·R_{h+1}`）：2 個手算測試、golden 10 處；
  - 最大餘數法的平手給站號大的：2 個手算測試、golden 1 處；
  - 不看容量：3 個手算測試、golden 5 處；
  - 改停靠之後不放棄等車的人：8 個手算測試（存讀被拒絕）、golden 4 處；
  - 跳過的閒置步長不釋出：35 處手算測試、golden 12 處。
- **不變的**：決策 1–33 的行為與存檔；18 個既有的 property digest 與 `main` 完全相同（見 PR）。

#### 已知限制與留給之後

- 還沒有人上車：列車到站不會帶走任何人（G1b，決策 35 已補上）。在那之前車站很快就會滿，之後的人都記進 `overflowed`。
- 每天的旅次是自訂的比例分配，不是城市模擬（Phase 6）。
- 只坐同一條路線；同時停兩站的路線不只一條時，一律坐編號最小的那條。
- 一天之內的旅次不因營運時間或班距改變：營運時間之外也會有人來等。參考的釋出同樣不看營運時間。

### 35. 上下車與容量（G1b）

G1 的第二步：列車離開一站時讓到站的人下車，再依容量讓等車的人上車；上不去的記下來。車上的人記在列車上，每一站的守恆稽核加上車上與到達的人。還沒有票價與帳本（G1c）。沒有需求就沒有乘客，所以沒有需求時決策 1–34 的行為、存檔、既有 golden 的預期值與 property digest 都不變。

**來源**：作者的 `Ci/` 網站（私有 repo 的 `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，minified，以 prettier 展開後閱讀）。

| 參考 | Swift | 分類 |
| --- | --- | --- |
| `updateTrainAtStation(train, station, line)`：到站那一刻一次先下車、再上車 | `GameWorld.serve(_:)`：`advance` 的上下車階段，列車每離開一站處理一次（W2b 起改為車門開好時的 `exchangePassengers(_:at:)`，見決策 39） | 順序與「一次完成」faithful；在到站還是離站處理是**過渡**做法（第 3 點），W2 取代 |
| `metroResolveTrainAlighting`：下車 = `paxBuckets[這一站]`；非環狀線在路段兩端（`releaseAll`）全員下車 | 迄點是這一站的人下車（`arrived`）；在折返或服務結束的一站，還在車上的人也下車 | faithful；後者在這裡永遠沒有人（第 4 點） |
| `getMetroTrainRatedCap`（`{cars: 6, cap: 1920}`） | `Train.ratedCapacityPerCar = 320`、`ratedCapacity` = 輛數 × 320 | 機械換算（1920 ÷ 6） |
| `getMetroTrainOperationalCap`、`METRO_TRAIN_OPERATIONAL_LOAD_FACTOR = 1.1`（高鐵以外） | `Train.capacityPerCar = 352`、`capacity` = 輛數 × 352 | 機械換算（320 × 1.1 = 352，剛好整除）；還沒有高鐵，所以一律 × 1.1 |
| 空位 `max(0, floor(operationalCap − pax))` | `capacity − riderCount(of:)` | faithful |
| 上車方向：列車的 `dir`，在路段起點強制往前、終點強制往回 | 由來回時刻表的位置決定：遠端之前是 `outbound`，遠端起是 `inbound` | 機械換算 |
| `metroCollectRawTargetsForBoarding`、`isValidTargetForLeg`（依快慢車種類與路段篩選） | 同一條線、同一方向，而且迄點是這班車到下一次折返之前會停的站；pattern 不停的站的人繼續等 | faithful；分支線共用段的轉乘（`metroSharedBranchBoardingTarget`）是 gap，G1 沒有轉乘 |
| `allocateSeats`：依下車站由遠到近排序，依序填滿空位，最後一組部分上車 | 同樣由遠到近；同一迄點先來的先上 | faithful；同一迄點的先後是 G1a 的先進先出 |
| `metroDeductBoardingPlanFromTransferQueues` | `StationPassengers.board(_:)`：從組裡扣掉，扣完的組離開，其餘保持順序與釋出的分鐘 | faithful |
| `paxBuckets` / `paxBucketDest`（依下車站的人數） | `TrainRiders { train, groups }`、`RidingGroup { origin, destination, count }` | 機械換算：多記起點，讓每一站的守恆可以稽核 |
| `flow.off`、`exitSumToday`、`hourlyOut` | 起點帳本的 `arrived` | 總數 faithful；每小時的統計留給 G1c 的畫面 |
| （沒有） | 起點帳本的 `refused` | gap，照 ROADMAP 5E 補上 |
| 停站時間、車門、上車速度（見下面「停站時間」） | `Railway/StationDwell.swift`（純計算，還沒接到 `advance`） | faithful＋機械換算（十分之一秒）；接到遊戲時間是 W2 |

**1. 容量**：`Train.capacity` = 輛數 × 352，`ratedCapacity` = 輛數 × 320。輛數只能在列車不在軌道上時改，所以跑車中的容量不會變。

**2. 誰上車**：列車必須指派在一條路線上（`assignedLine(of:)`）。路線的列車只跑路線派出的來回，所以時刻表的形狀固定：第一站、往遠端的各站、遠端（折返）、回程的各站、回到第一站（折返，服務結束）。離開第 `i` 站時：
- 方向：`i < (停靠數 − 1) ÷ 2` 是 `outbound`，其餘是 `inbound`；
- 可以上車的組：那一站等車、路線與方向相同、迄點是第 `i + 1` 站到下一個折返站（含）之間某一站的組；
- 順序：迄點第一次出現的停靠越遠越先，同樣遠（同一迄點）的依排隊的順序；
- 依序整組上車，放不下的那一組部分上車（剩下的保留原來的分鐘與位置），之後的組都上不去；
- 可以上車卻沒上去的人數加進那一站的 `refused`。這是次數，同一個人可能被好幾班車拒絕，所以不在守恆式裡，累加到 2⁶² 為止。

**3. 時機（過渡做法，W2b 已取代，見決策 39）**：`Ci/` 的遊戲在列車**到站**那一刻一次讓所有人下車、上車（`_stationCallGuard` 讓同一幀只處理一次），然後固定停 36 秒（終點 42 秒），停站時間與人數無關（見下面「停站時間」）。GameCore 目前以分鐘為步長、停站時間是整數分鐘，所以暫時改在列車**離開**一站的那一刻處理：先下車、再上車。停站期間來的人都搭得上，結果也不依停站被切成幾段而改變。這**不是永久的語義**：W2 會把「到站 → 開門 → 上下車 → 關門 → 發車」以已移植的秒級停站規則接到遊戲時間、`RunningCurve` 與行程上，取代這個時機；誰上車、順序與容量（第 1、2、4、5 點）不變。
- 派車（階段 0）與出發（階段 1）把每一次離站依發生的順序記下來，兩個階段結束後依序處理（新的「上下車」階段，在移動之前）。上下車只讀列車、只改乘客，而出發不讀乘客，所以先記下再處理，和每次離站立刻處理的結果相同。`ReferenceWorld` 刻意用後者，驗證了這一點。
- 代價：下車的時間記在離站那一刻，比實際到站晚一個停站時間。
- 閒置跳步仍然精確：離站本來就算「有變化」，沒有離站的步長沒有上下車。

**4. 下車**：離開第 `i` 站時，迄點是這一站的人下車，加進起點的 `arrived`。在折返或最後一站，還在車上的人也下車（參考的 `releaseAll`）；因為沒有人會搭到下一個折返站之後，這種人永遠不存在，這一條只是保險，記進 `abandoned`。

**5. 服務提早結束**：
- 行程中被 `unassignTrain` 拿掉、或路線被 `removeLine` 刪掉的列車，照舊把車上的人載到迄點，但不再有人上車。
- 這樣的列車之後被 `stopTrainService` 停掉時，車上的人記進起點的 `abandoned`。路線上的列車不能被停掉（`trainOnLine`），所以這是唯一會丟下乘客的路。
- `setLineStops` 不影響車上的人：時刻表在派車時就固定了。

**6. 守恆稽核**：每一站 `released = waiting + riding + arrived + overflowed + abandoned`（`PassengerLedger` 新增 `riding`、`arrived`、`refused`）。`riding` 由各列車的 `RidingGroup` 加總，不另存。

**7. 依賴方向**：上下車讀路線的指派、列車的時刻表、執行進度（`TimetableExecution`）與輛數；不讀 `TrackTraversal`、`TrackResource`、預約或 `TrainMovement`，也不改列車。

**8. 存檔**：
- `"riders"` 只在有列車載客時寫；每一筆是 `{ train, groups: [{ origin, destination, count }] }`，依列車排序，組依（起點、迄點）排序、不重複。
- 車站紀錄的 `"arrived"`、`"refused"` 只在不是 0 時寫，所以 G1a 的存檔照舊能讀，沒有乘客的世界存檔完全不變。
- 解碼拒絕：
  - 沒有組、組的人數不在 1 到 16 × 352、起點等於迄點、組沒有排序或重複；
  - 列車重複、沒有排序、不存在或沒有在跑服務，載客超過容量；
  - 起點沒有乘客紀錄；迄點不是列車從目前（或正要去）的一站到下一個折返站之間會停的站；
  - 車站的數：`arrived`、`refused` 是負數，`refused` 超過 2⁶²，`waiting + arrived + overflowed + abandoned` 超過 `released`，或加上車上的人不等於 `released`。

**9. 停站時間（純計算；W2b 以捷運的 36／42 秒與車門時間接到遊戲時間，見決策 39）**：`Ci/` 與 `Railway/` 兩邊找到的所有停站、車門與上車速度的規則，都在 `Railway/StationDwell.swift` 移植成純整數函式（單位是十分之一秒，讓 8.3 秒、10.2 秒、半個週期都精確）。G1b 還沒有把它們接進 `advance`、時刻表或路線的行程。兩邊都**沒有**依乘客人數、上下車速度、車門數或車門容量計算停站時間的規則：唯一的候選是 `Ci/` 的 `PARAMS.BOARDING_RATE`（2，沒有單位）與 `PARAMS.TRAIN_DWELL_TIME`（44 秒），兩者都只有定義、從來沒有被讀取。它們以原值保留成常數（`referenceBoardingRate`、`referenceTrainDwellTime`），不另外發明公式。這是 reference gap。

| 參考 | Swift（`StationDwell`） | 分類 |
| --- | --- | --- |
| `Ci` `DWELL_GAME_SEC = 36`、`DWELL_TERMINAL_GAME_SEC = 42`；`_advanceTrainOneStep` 到站時設定：關閉的車站 0（通過）、環狀線一律 36、路段終點 42、其餘 36 | `metroDwell`、`metroTerminalDwell`、`metroDwell(isServed:isRing:isTerminal:)` | faithful；終點的判定（`_isTrainRouteLegTerminalMove`，快車、路段）由 W2 的呼叫端提供 |
| `Ci` 停站的消耗：`remain = max(0, remain − step)`，到 0 才能發車，發車的那一步不帶剩餘時間 | `remainingDwell(_:after:)` | faithful |
| `Ci` 停站到 0 後，共用軌道的班距未清空時繼續等（`metroSharedTrackHeadwayClearance`） | 不在這裡 | 屬於運轉控制（Stage T 之後），W2 |
| `Ci` `metroHeadwayRoundTripMinutes`：線狀 `2·行駛 + 2·(站數 − 2)·36 + 2·42`，環狀 `行駛 + 站數·36`（÷ 60 成分鐘） | `metroRoundTrip(travel:stops:isRing:)`（不除以 60） | faithful |
| `Ci` `metroHeadwaySegmentTravelSeconds`（加速 1.1、減速 1.3 的梯形／三角形） | 不在這裡 | 行駛時間，不是停站；和 W1 的 `RunningCurve` 一起在 W2 處理 |
| `Ci` 路徑搜尋同一路線續乘時加的 `36`、時刻表建構的 36／42 | 同上的常數 | faithful（呼叫端在 W2） |
| `Ci` `bootstrap-lazy` 的 `Bt`（捷運：開門 8 秒、剩 8.3 秒關門）、`Ta`（高鐵：7 秒、9 秒）；總時間至少 1 秒，剩餘時間夾在 0…總時間 | `doorPhase(total:remaining:opening:closing:)`、`metroDoorOpening`／`Closing`、`highSpeedDoorOpening`／`Closing` | faithful（參考裡是聲音與畫面用的；這裡只是純計算） |
| `Ci` `METRO_TRAIN_DOOR_CLOSE_REAL_SEC = 10.2`（真實秒 × max(1, 速度)，預備發車的關門警告） | `metroDoorCloseWarning(speed:)` | faithful |
| `Ci` `PARAMS.BOARDING_RATE 2`、`PARAMS.TRAIN_DWELL_TIME 44`、`DWELL_SEC 60`、`LONG_DWELL_DEBUG_SEC 45` | 前兩個保留為常數；後兩個不移植 | 參考裡都沒有被讀取（`LONG_DWELL_DEBUG_SEC` 讀的 `_longDwellDebug` 從未被設定） |
| `Ci` 高鐵：`hsrTrainDetailDwell` 等（離站 − 到站，負的加一天）、實際時刻匯入（端點 0，否則 `max(0, (離 − 到 + 1440) % 1440)`）、沒有停站時間時的估計（列出的區間時間 − 離站到下一站的分鐘，1…60 才採用）、插入的停靠 2 分鐘 | `stopMinutes`、`importedStopMinutes`、`estimatedStopMinutes`、`insertedStopMinutes` | faithful；插入停靠之後的 `GuangdongHsrSchedule.recalcService` 不在快照裡（gap） |
| `Railway` `DWELL_SEC = 25`、`trtcOfficialDwellAt`（車站自己的 `dwell` → 路線的 `dwellSec[i]` → 25，非正數視為沒有） | `defaultDwell`、`stationDwell(own:line:)` | faithful |
| `Railway` `trtcOfficialCoastCycle`（週期：給定的 → 最近兩次到站的間隔 → 行駛 + 25；停站 = 週期 − 行駛，至少 15、至多半個週期） | `coastCycle(given:lastArrivalGap:run:)`、`minimumCoastDwell` | faithful（整數秒的輸入完全精確） |
| `Railway` `buildLineSchedule`（沒有時刻表的週期性運行：第一站 → 最後一站 → 第一站，環狀線繞一圈；每站停自己的 dwell 或 25；起點在週期兩端各停一次） | `periodicTimetable(dwells:runs:isLoop:)` | faithful；缺行駛時間時以距離 ÷ 速度補的部分由呼叫端提供 |
| `Railway` 由倒數看板觀測的路線停站（每段相鄰站的觀測，8 個以上取中位數（偶數取上面那個）；有行駛時間時 0 < 中位數 < 180，否則第一段行駛 + 中位數在 40…240）、`TRTC_BR_DWELL_FALLBACK = 29` | `observedLineDwell(samples:hasRunningTimes:firstRun:)`、`observedDwellFallback` | faithful（收集觀測的部分依即時資料，不移植） |
| `Railway` `retimeLoopTrains`（環島列車：08:00 發、12 小時、起點與中間每個停靠站停 120 秒，其餘依區間長度分配，四捨五入到秒） | `loopTimetable(lengths:stops:)`、`loopDeparture`、`loopDuration`、`loopDwell` | faithful |
| `Railway` `HSR_DEP_MID_SEC = 30`（分鐘精度的高鐵資料，除了最後一站都在該分鐘的中間發車） | `highSpeedDepartureOffset` | faithful |
| `Railway` 的真實停站資料：`data/trtc.json`、`krtc.json`、`tmrt.json`、`sanying.json` 每站的 `dwell` 與路線的 `dwellSec[]`（秒）；`tra_schedule_dense.json`、`api/thsr-schedule.json`、`afr_schedule_dense.json` 的 `depSec − arrSec`；`*_times.json` 隱含的停站 | 還沒有匯入 | 資料；真實藍本情境的轉換工具（Phase 6）匯入時用 `stationDwell(own:line:)` 與 `periodicTimetable` |
| `Railway` 台鐵的待避停站（`planSameDirectionOvertakes`：`OVERTAKE_CLEAR_SEC 30`、`OVERTAKE_MAX_WAIT_SEC 600`）與交會推定（`inferMeetRun`：`MEET_HEADWAY_SEC 300`）、`rail-3d` 的 `dispatch.json` 發車保留 | 不在這裡 | 依賴 `buildProfile` 的可行性與台鐵的行駛曲線，屬於 W2／待避與交會；產生 `dispatch.json` 的程式不在封存裡（gap） |
| `Railway` 畫面用的門檻（剩餘 > 3 秒且總停站 ≥ 20 秒才顯示停站中、≥ 180 秒標為長停站、看板的 30 秒寬限） | 不在 GameCore | 畫面；G1c 的畫面需要時移植到 `GamePresentation` |

**Gap（參考沒有，這裡補上）**：`refused`（第 2 點）、起點的守恆（第 6 點）、服務停止時放棄車上的人（第 5 點）。**Reference gap（兩邊都沒有，沒有發明）**：依乘客人數、上下車速度、車門數或車門容量決定停站時間。

**沒有移植的**（之後的 Stage）：
- 把停站時間接到遊戲時間（第 3、9 點）：W2。
- 轉乘（5F）：分支線共用段的轉乘目標、下車後在轉乘站重新排隊（`metroUsesGlobalOdPathTransfer` 的路徑）。
- 環狀線（參考的 `isRing` 不在路段兩端全員下車）：遊戲的路線都是來回。
- 高鐵不超載（`lineKind === "hsr"`）：還沒有路線種類。
- 擁擠與滿載的通知（`emitCrowdAndFullTrainNotices`）：畫面在 G1c。

#### 實作

- `Passenger/Boarding.swift`：`RidingGroup`、`TrainRiders`、`Train` 的容量、查詢 `riders(of:)`、`riderCount(of:)`，上下車階段（`StopDeparture`、`serve(_:)`、`board(_:at:)`）、`abandonRiders(of:)`、存檔驗證 `riderProblem()` 與各自的 `Codable`。
- `Railway/StationDwell.swift`：兩個參考的停站、車門與高鐵停站分鐘的純計算（第 9 點），不讀也不改世界。
- `Passenger/StationPassengers.swift`：`PassengerLedger` 新增 `riding`、`arrived`、`refused`；`StationPassengers` 新增 `arrived`、`refused`、`board(_:)`、`refuse(_:)`，解碼改為只要求不超過 `released`（車上的人由 `GameWorld` 核對）。
- `GameWorld`：`riders`（`internal(set)`，只由乘客的規則寫入）、派車與出發記下離站、`advance` 的上下車階段、`stopTrainService` 放棄車上的人、`Codable`。

#### 驗證

- `BoardingTests`（手算，10 個）：容量（320／352 與輛數）、離站時上車與到迄點下車（在 Beta 停站期間還在車上）、下車站遠的先上與同一迄點先來的先上、放不下的那一組部分上車並保留分鐘、`refused`、滿載時全部被拒絕直到有人下車、遠端折返後載回程、只載自己的路線與方向與前方停靠的人、pattern 不停的站的人繼續等、離開路線的列車照舊載到迄點但不載新的人、停止服務時放棄車上的人、一天的營運逐分鐘守恆而且一次推進與逐分鐘相同、存讀與 11 種壞掉的存檔。
- `StationDwellTests`（11 個）：每一個預期值都是參考的 JavaScript（原樣抽出）在 Node 執行同一組 case 的結果；第一次執行就全部一致。
- `ReferencePassengers`：`ReferenceWorld` 另外寫一次決策 35，而且寫得不同：每次離站**立刻**處理（證明先記下、之後依序處理的結果相同）、車上的人是依列車、起點、迄點的字典、逐一挑最遠而且最早的組而不是排序、容量寫成 `輛數 × 320 × 11 / 10`。每個 golden scenario 都在它上面重跑。
- `BoardingPropertyTests`（`boarding.differential`，16 個 case × 4 個種子 × 70 個操作，digest `B105FCE7743F269F`，CI campaign shard）：派車 campaign 的小路網、路線與列車，加上各種大小的需求、2 到 3 輛的列車、離開路線後停止服務，同時在 GameCore 與 `ReferenceWorld` 上執行，每一步比較所有狀態（包括每一站的排隊、帳本與每台列車的乘客）；每次推進也逐 tick 重跑。量（逐 tick 計數）：到達 4,673、上下車 4,434、滿載 4,461、被拒絕 1,417、2 輛以上載客 142、多個迄點 281、停止服務而放棄乘客 26。
- `SaveMutationTests` 新增 `save.riderMutation`（10 個 case × 4 個種子，每個 30 次變異）：載入 386、拒絕 814、瞄準乘客與服務的變異 890、載入後有列車載客的世界 95。
- `WorldInvariants` 在每個 campaign 的每一步檢查擴充後的守恆與車上乘客的規則（另外寫一次）。
- Golden schema v21 與手算的 `boarding.json`（預期值另以獨立的 Python 實作依規則算出），在 GameCore 與 `ReferenceWorld` 上都通過；既有 fixture 的預期值沒有改變。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄：下車站近的先上、空位不扣車上的人、不下車、遠端的方向算錯、不記拒絕、停止服務不放棄乘客。六個都被手算測試、golden（含 `ReferenceWorld`）與 `boarding.differential` 第一個種子抓到。
- 完整測試（本機 Linux Swift 6.4，六個 shard，521 個測試）全部通過；18 個既有的 property digest 與 `main` 完全相同，`passenger.differential` 與 G1a 相同（`62042B9B922FCE2C`）。
- **不變的**：沒有需求時決策 1–34 的行為與存檔。

#### 已知限制與留給之後

- 上下車在離站那一刻一次完成是過渡做法（第 3 點），W2 以停站規則（第 9 點）取代；下車的時間因此暫時記在離站而不是到站。
- 只有路線的列車載客；手動時刻表的列車不載客。
- 同一分鐘同一站的兩班同線車，依派車與列車編號的順序上車。
- 還沒有票價、收入與畫面（G1c）。

### 36. 票價、帳本與經營（G1c）

G1 的最後一步：乘客上車時付票價，路線的列車每次離站記下班次、列車公里、載客與座位，每小時結算營運與維修，每天結算能源與人事，寫進帳本與每日的帳；票價設定後也影響需求。新的世界是「自由模式」（`EconomyMode.free`），什麼都不收、不記，所以決策 1–35 的行為、存檔、既有 golden 的預期值與 property digest 都不變；App 的新遊戲是「經營模式」（`management`）。

**來源**：作者的 `Ci/` 網站（`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，minified，以 prettier 展開後閱讀）的捷運經濟「舊路徑」（`metroEconomy*` 函式）；`window.MetroEconomy` 引擎本身（`economy.js`、`metro_economy_rules.js` 等）不在快照裡。`Railway/` 沒有經濟模型（只有即時資料與時刻表），兩邊都搜尋過。

| 參考 | Swift | 分類 |
| --- | --- | --- |
| `economyMode`（free／management） | `EconomyMode`、`setEconomyMode(_:)`、`CompanyAccounts.openedAt` | faithful；開始經營的那一刻記下 `openedAt`，第一次結算在下一個整點（第 5 點） |
| `MetroEconomy.setFareRules("metro", …)`、票價編輯器的 `lineInfoFareModeValue`（flat／distance）、`metroFareDefaults().flatFare ?? 5`、`lineInfoFareDefaultDistanceBands`（0／6／12／22／32 km：0.55／0.70／0.85／1.00／1.20） | `FareRules.flat`、`.distance([FareBand])`、`FareRules.standard`（`.flat(500)`）、`standardBands` | faithful＋機械換算（美元 → 美分） |
| 引擎的票價檢查（1–64 段、從 0 起、首尾相接、只有最後一段沒有終點） | `FareRules.isValid`、`setFareRules(_:)` 的 `invalidFareRules` | faithful；上限（票價 ≤ 1e9 美分、距離 ≤ 1e7 m）是 gap，為了整數不溢位 |
| `metroEconomyStationDistanceKmByNetIdx`（起迄兩站的大圓距離） | `tripFare(from:to:)`：兩站格子的直線距離（1 格 = 1024 單位 = 16 m），以平方比較，完全精確 | 機械換算（平面地圖沒有經緯度） |
| `metroEconomyAccrueHourlyFare`：`fare ≤ 0` 收 5；`fareRevenue += Math.round(count × fare)` | `FareRules.charged(_:)`、`chargeFares(_:from:to:)`：每個迄點 `floor((count·fare + 50) ÷ 100) × 100` 美分 | faithful＋機械換算 |
| `updateTrainAtStation` 的 `fareTrips`（上車時依迄點收） | `board()` 依迄點彙整後收費 | faithful；時機是 G1b 的過渡做法（離站），W2 改到真實的上車 |
| `metroEconomyAccrueDeparture`（班次、列車公里、乘客、座位） | `countDeparture(distance:passengers:seats:)`、`HourlyAccrual` | faithful；距離是派車時到下一站的路徑距離（世界單位），座位是額定容量（輛數 × 320） |
| `metroEconomySettleHourlyIfNeeded`（`metro.hourly.netSettlement`）：營運 `round(75·班次 + 42·列車公里 + 18·車站)`、維修 `round(12·路線公里 + 9·列車公里 + 8·列車)`（舊路徑用 `trainKm`，不乘輛數） | `settleAccounts(at:memo:)`、`settleHour`：以 1/64000 美元計算再四捨五入到整美元 | faithful＋機械換算（64000 單位 = 1 km） |
| 小時結算的 `crowdingMetrics`（等車 > 1500 的站、滿載列車、最多等車、最大載客千分比） | `CrowdingMetrics` | faithful；只記錄，不收費 |
| `metroEconomySettleDailyForEndedDay`：能源 `round(220·路線公里 + 360·列車)`（`metro_route_energy`、`metro_train_energy`）、人事 `620·車站 + 480·列車`（`metro_station_staff`、`metro_train_staff`），`allowNegativeBalance` | `settleDay`、`GameEconomy.settle(_:)` | faithful；各項各自四捨五入，總額是加總後四捨五入（與參考相同，可能差 1 美元） |
| 固定資產：車站（每條路線自己的停靠站，各算一次再相加，決策 46 更正）、路線長度、列車 | `fixedAssets(memo:)`：路線自己服務的行程去程各段的路徑距離、各服務各等級列車數的最大值相加 | 機械換算；參考由地圖的路線幾何量，這裡由已推導的行程（決策 22） |
| 帳本列（`metro_hourly_net`、`metro_daily_energy`、`metro_daily_staff`），保留最後 50 列 | `LedgerEntry`、`CompanyAccounts.entries`（`keptEntries = 50`） | faithful |
| `FLOW_DASHBOARD_FINANCE_BUCKETS`（日／週／月／年 = 1／7／30／360 天）、`summarizeFinanceForTransport` | `FinancePeriod`、`DayAccount`（保留 720 天）、`financeReport(_:)`（本期與上期） | faithful；參考保留整個帳本（年報表最多 50 年），這裡保留兩年，讓年報表的本期與上期都完整 |
| `metroFareDemandPenaltyForFare`（相對 `METRO_FARE_DEMAND_BASELINE_USD = 0.75` 的比值的曲線） | `FareRules.demandFactor(fare:)`：每 0.05 一格、95 格的千分比表，線性內插 | 公式 faithful；GameCore 沒有 `exp`，事先算成表（機械換算），測試以 Foundation 逐格重算，誤差 ≤ 1.6‰ |
| 需求乘上票價的影響 | `dailyDemand(from:)` 與乘客計畫：每對 `(trips × factor + 500) ÷ 1000` | faithful；只在經營模式而且玩家設定過票價時（第 6 點） |
| `metroEconomyMoneyText`：`"$ " + Math.round(dollars)` 加千分位 | `GamePresentation` 的 `Money.moneyText` | faithful |
| 經濟明細的分類標籤（`economy.ledger.*`、`economy.group.*`，只有 zh-CN） | `LedgerItem.displayName(in:)`、`LedgerEntry.Kind.displayName(in:)`（英文；繁體中文照參考轉換，決策 38） | 翻譯 |

**1. 金額**：`Money` 是參考美元的**美分**。之前的建設費用與餘額數值不變，只是從 G1c 起以美元顯示（`$ 10,000` 是 1,000,000）：一般四捨五入到整美元（`moneyText`），票價與「餘額不足」的訊息精確到美分（`centsText`），以免顯示成「需要 $ 10、只有 $ 10」。

**2. 票價**：`tripFare(from:to:)` 是規則對兩站直線距離的票價，0 以下收 5 美元；距離段 `[from, to)`，正好在終點的距離屬於下一段。沒有設定規則時用 `FareRules.standard`（均一 5 美元）。

**3. 收入**：乘客上車時（G1b 的上下車階段）依迄點收費，進入這一小時的 `pending`；只在經營模式。

**4. 班次**：路線的列車每次離站（`Leaving.setsOff`，帶有到下一站的距離）在上車之後記一次班次、距離、車上人數與座位。手動時刻表的列車不載客也不記。

**5. 結算**：
- 每個基本步長一開始，經營模式、`now` 是整點、而且 `openedAt < now` 時，結算剛結束的一小時：營運與維修，寫一列（票價、營運、維修三項都是 0 時不寫），餘額加上淨額，`pending` 歸零，`openedAt = now`。
- 這一小時屬於 `now − 1` 那一天（參考先結算小時，再換日）。
- `now` 是午夜時，接著寫前一天的能源與人事，時間記為 `now − 1`。
- 餘額可以變成負數；之後建設仍然需要足夠的餘額（決策 4）。
- 閒置跳步：經營模式下逐分鐘檢查，不會跳過任何一次結算（一次推進與逐分鐘相同）。
- 自由模式下什麼都不累積、不結算；切回經營模式時重新從那一刻開始。

**6. 需求**：經營模式而且設定過票價規則時，每對車站每天的旅次乘上票價的影響（基準 0.75 美元時是 1000‰；0 元算基準，也是 1000‰，決策 46 更正；基準是公司所在城市的，決策 46）。沒有設定過時需求完全不變，所以 G1a、G1b 的 golden 在經營模式下也不變。

**7. 存檔**：
- `"accounts"` 只在不是初始狀態時寫：`{ mode, fareRules?, pending, openedAt?, entries, days }`。
- 解碼拒絕：不認得的模式或票價規則、`pending` 是負數或超過上限（每小時的數 ≤ 2⁴⁰、班次 ≤ 2³⁰）、票價收入不是整美元、列的時間晚於現在、經營模式卻沒有 `openedAt`、`openedAt` 晚於現在、超過 50 列或 720 天、日期沒有遞增、金額超過 ±2⁵⁰、每日的合計是負數、列的項目不符種類（順序、正負、加總等於金額、只有小時列有擁擠資料），以及餘額超過 ±2⁶²（讓結算永遠不會溢位）。

**Gap（參考沒有，這裡補上）**：票價與距離的上限（溢位）、`openedAt`（第一次結算的時機）、存檔的上限與驗證、英文標籤。**Reference gap**：開局的資金（在缺少的 `economy.js` 裡），App 沿用之前的 1,000,000（`$ 10,000`），之後平衡時再調整。

**沒有移植的**（之後的 Stage 或需要決定）：
- 以配額（quota）購買建設：參考的經營模式以配額而不是現金蓋路線與車站，需要使用者決定是否取代現在的建設費用。
- 高鐵與航空的結算、取消與擁擠的賠償與退票、網路營運費：還沒有這些運具或事件。
- 貸款與利息：參考的快照裡沒有。
- 結算的動畫、擁擠與滿載的通知。

#### 實作

- `Economy/Fares.swift`：`EconomyMode`、`FareBand`、`FareRules`（驗證、票價、需求影響的表）與 `Codable`。
- `Economy/Accounts.swift`：`HourlyAccrual`、`LedgerItem`、`LedgerLine`、`CrowdingMetrics`、`LedgerEntry`、`DayAccount`、`FinancePeriod`、`FinanceSummary`、`CompanyAccounts` 與 `Codable`。
- `Economy/Operations.swift`：指令、查詢、收費、班次、結算與存檔驗證（`accountsProblem()`）。
- `GameWorld`：`accounts`、`advance` 每步一開始的結算與逐分鐘的閒置跳步、離站帶距離；`Passenger/Boarding.swift` 收費與記班次；`Passenger/PassengerDemand.swift` 的需求影響。
- `GamePresentation/EconomyText.swift`：金額、票價、標籤、最近一小時的分項、最近的帳本列、每站依路線方向的等車人數、列車的載客率；`GameSession.setEconomyMode(_:)`、`setFareRules(_:)`。
- App：HUD 的餘額以美元顯示（負數為紅色），點一下開啟 `EconomyPanel`（餘額、模式、票價、最近一小時、本期與上期的報表、最近 12 列）；檢視器顯示車站的等車、列車控制顯示載客；新遊戲是經營模式；建設費用以美元顯示。

#### 驗證

- `EconomyAccountsTests`（手算，10 個）：自由模式不記帳、存檔不變；沒有任何東西在動的世界仍然每小時、每天結算；均一與距離票價、正好在段的終點、0 元收 5 元；票價規則的檢查；60 分的小時列（票價 1500、營運 142800、維修 1400、18 班）；午夜的能源（−37400 = 路線 −1400、列車 −36000）與人事（−234000）、日期與餘額；一次推進與逐步相同；需求影響 1000／1080／487 與表對公式；存檔往返與 12 種壞掉的存檔。
- `EconomyDisplayTests`（4 個）：金額的四捨五入（含負數與 Int64 的兩端）、精確到美分的金額（票價與「餘額不足」的訊息）、帳本列與最近一小時、等車與載客率、session 的指令。
- `ReferenceEconomy`：`ReferenceWorld` 另外寫一次決策 36，而且寫得不同：每站離站時立刻收費、以 1/64000 美元累積、票價規則逐步檢查、每日的帳是字典、固定資產以集合計算。每個 golden scenario 都在它上面重跑。
- `EconomyPropertyTests`（`economy.differential`，12 個 case × 4 個種子 × 60 個操作，digest `C6B29457D984AF1`，CI campaign shard）：上下車 campaign 的路網、路線與需求，九成是經營模式，途中設定與被拒絕的票價規則、切換模式、跨小時與跨日的推進，同時在 GameCore 與 `ReferenceWorld` 上執行，每一步比較所有狀態（餘額、帳、四種報表與票價）；每次推進也逐 tick 重跑，2× 與 1× 比較。量：結算的小時 1932、有票價收入的小時 234、結算的日 82、設定的票價規則 241、被拒絕的 30、餘額變成負數 27。
- `SaveMutationTests` 新增 `save.accountsMutation`（10 個 case × 4 個種子，每個 30 次變異）：載入 418、拒絕 782、瞄準帳的變異 923、載入後有帳本的世界 182。它在第一次執行時找到一個溢位（變異後巨大的班次在結算時溢位），因此加上了每小時與餘額的上限。
- `WorldInvariants` 在每個 campaign 的每一步檢查帳的規則（另外寫一次）。
- Golden schema v22（新的指令、觀察與最終狀態的 `accounts`）與 `economy.json`（預期值以獨立的 Python 實作依規則算出），在 GameCore 與 `ReferenceWorld` 上都通過；既有 21 個 fixture 只升級版本並加上初始的 `accounts`，預期值沒有改變。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄：0 元不收 5 元、收費不四捨五入到整美元、小時記到 `now` 那一天、營運的係數 75 改成 74、閒置跳步不結算、沒有設定票價也影響需求、帳本保留 51 列。七個都被抓到：`economy.differential` 抓到全部七個；手算測試抓到最低票價、日期、係數、閒置跳步與需求（閒置跳步原本只有 campaign 抓到，因此新增了 `testAQuietWorldStillSettlesEveryHour`）；golden 抓到捨入、日期與係數。
- 完整測試（本機 Linux Swift 6.4，六個 shard）全部通過；18 個既有的 property digest 與 `main` 完全相同，`passenger.differential`（`62042B9B922FCE2C`）與 `boarding.differential`（`B105FCE7743F269F`）也不變。Swift 6.0 的 light shard（592 個測試）通過。
- **不變的**：自由模式（新世界的預設）下決策 1–35 的行為與存檔。

#### 已知限制與留給之後

- 收費的時機跟著 G1b 的過渡做法（離站），W2 改到真實的上車。
- 參考以地圖的經緯度量距離；這裡是格子的直線距離。
- 開局資金、配額建設與平衡留給之後（需要決定）。

### 37. 遊戲時間改以秒計（Phase 4.7 Stage W2a）

W2 要接上真實車速與以秒計的停站（ROADMAP 的 Stage W；[對照文件](RAILWAY_REFERENCE_MAPPING.md#gap-分析)的 gap 2、9，作者 2026-10-01 的決定）。地圖是真實比例（一格 16 公尺，手機預設每公尺 2 pt），真實車速的列車只有在接近真實時間的速度下才看得清楚；在那種速度下，一分鐘的基本步長會讓移動每 6 到 60 真實秒才前進一次，玩家的指令最多晚一分鐘才生效。所以基本步長改成一秒。這一步只換時間的單位與速度檔位，不加新玩法。

- **`GameTime`**：開局以來的整數遊戲秒（`seconds`，也可以是負數）。
  - `init(minutes:)` 是整分鐘的便利寫法，乘以 60 溢位是程式錯誤。
  - `minute`（向下取整，也適用負數）、`secondOfMinute`、`isWholeMinute`，以及 `secondsPerMinute`、`secondsPerHour`、`secondsPerDay`。
  - 沒有讀出「分鐘」的屬性：每一處都改成明確的秒或分鐘，編譯器找得出所有用到舊單位的地方。
- **速度與 tick**：
  - `GameSpeed` 加上 `x1`、`x10`、`x60`，保留 `normal`、`double`（W2a 之前僅有的 1×、2×：一 tick 一分鐘、兩分鐘）。
  - `tenthsPerTick` 依序是 0、1、10、60、600、1200 個十分之一秒。宿主每 100 ms 一個 tick（決策 12），所以名稱就是真實時間的倍數：`x1` 是真實時間，`normal` 是 600 倍。
  - `x1` 每個 tick 不到一秒：不足一秒的十分之一秒存在 `GameClock.pendingTenths`（0…9），跨過暫停與速度的改變。只有非 0 時存檔，所以 W2a 之前的時鐘讀成 0；超出範圍或 `null` 拒絕。
  - 一批 tick 的秒數，以 ticks = 10q + r 拆成 `ticks·⌊t/10⌋ + q·(t mod 10) + ⌊(r·(t mod 10) + pending)/10⌋`（t 是每 tick 的十分之一秒）：只有秒數本身放不下時才是 `clockOverflow`，不會因為十分之一秒的乘積溢位而誤判。檢查仍在任何改變之前（決策 3）。
  - `GameClock.runningSpeed`：時鐘在跑的速度，暫停時是 `resume()` 會回到的速度。
- **基本步長是一秒**：
  - 列車的 `rate` 仍是每分鐘的單位數，分到這一分鐘的每一秒：第 `s` 秒（從 0 起）走 `⌊rate·(s+1)/60⌋ − ⌊rate·s/60⌋`（`TrainMovement.distance(at:fromSecond:toSecond:)`，以 rate = 60q + r 拆開計算，任何 rate 都不溢位）。整分鐘加起來正好是 rate。
  - 一分鐘之內只有移動，而移動只讀地圖（決策 15），所以 `advance` 把同一分鐘裡剩下的秒（或這一批剩下的秒）一次走完；結果與逐秒走相同，以整分鐘推進時的成本也與以前相同。
- **其他事件仍在整分鐘**（過渡做法，W2b 改到秒）：
  - 帳的結算、乘客釋出、派車、出發與上下車在每分鐘開始時處理。
  - 到站每一秒都判定（列車在它這一秒的移動之後停在停靠站就是到站）。停在停靠站的列車在出發之前不會再動，所以在分鐘之內記下到站，整分鐘看到的結果與以前相同；這也讓分鐘中間的存檔裡，沒有「路已經走完還在行駛」的服務（`TimetableExecution` 的解碼拒絕這種狀態）。
  - 時刻表的時間可以是任何一秒，但在 W2b 之前，出發等到排定出發當時或之後的第一個整分鐘。路線推導的時間（行程、停留、班距）仍是整分鐘。
  - 整分鐘沒有任何列車改變時，跳過的仍是整分鐘，到下一個出發或派車可能發生的整分鐘為止（決策 15、20、23 的精確捷徑）。落在兩個整分鐘之間的出發，算在它之後的第一個整分鐘。
- **等價**：以整分鐘推進（`normal`、`double`）時，每個整分鐘的狀態都與 W2a 之前相同。
  - 22 個既有 golden fixture 的預期值不變；schema 23 只加上 `gameSeconds`、`pendingTenths` 與新的速度名稱，以及 `clock-seconds.json`。
  - 參考模型（`ReferenceWorld`）逐秒走、不用捷徑；Kernel 差分與 property campaign 也從分鐘中間的時刻、以新的速度推進，與它對照。
- **存檔**：所有時間（時鐘、時刻表、週期、`lastDispatch`、乘客的 `since`、`openedAt`、帳本列的 `time`）都以秒存。沒有存檔版本（決策 6），App 也還不把存檔寫到裝置，所以不換算舊存檔：W2a 之前以分鐘寫的時間讀進來會被當成秒。
- **週期**：`Train.timetablePeriod` 與 `setTrainTimetable(_:to:repeatingEvery:)` 的週期改以秒計，至少 1 秒。
- **畫面**：
  - HUD 的時鐘在比一分鐘一 tick 慢的速度、或落在分鐘中間時顯示秒。
  - 速度控制改成暫停／播放加上速度選單（六個按鈕在 iPhone 上放不下）。
  - 早到與誤點仍以整分鐘顯示，向下取整，不到一分鐘算準點。
  - App 的新遊戲仍以 `normal`（600 倍）開始，經營的節奏不變；確切的檔位之後在實機上調整。
- **不做**：停站狀態機、依乘客人數的停站時間、實際的到達與出發時刻、誤點存檔（W2b）；行駛曲線接到移動（W2c）；畫面在一秒之內的插值。

### 38. 繁體中文與英文（Stage L1）

第二版內部 TestFlight（0.2.0）之前，App 加上繁體中文（台灣用語）。英文保留為來源語言，跟著系統語言切換。只換畫面文字，不改任何規則或存檔。

- **語言從哪裡來**：iOS 在啟動時依使用者的語言設定，從 App 有的語系（`en`、`zh-Hant`）選一個；App 讀 `Bundle.main.preferredLocalizations.first`，換成 `DisplayLanguage` 交給 `GameSession`。String Catalog 用的也是同一個語系，所以兩邊的文字一致。使用者在設定改語言時 iOS 會重新啟動 App，所以 `GameSession.language` 是 `let`。
- **GamePresentation（Linux 上測試）**：
  - `DisplayLanguage`（`english`、`traditionalChinese`）；`init(localization:)` 把任何 `zh` 開頭的識別碼對到繁體中文，其他都是英文。
  - 每個產生文字的函式都明確接收語言（`playerMessage(in:)`、`tileSummary(at:in:)`、`displayText(in:)` 等），沒有全域狀態，文字仍是世界與語言的純函數，兩種語言都在 Linux 上測試。
  - 新增 `waitingSummary(at:in:)`、`levelSettingText`、`targetHeadwayText`：原本由 App 拼字的地方移進來，App 不再組合文字。
  - `GameSession(world:language:)` 的語言預設英文（測試用）；App 一律明確傳入。建議的名稱（`車站 1`、`路線 1`、`列車 1`）是存進世界的玩家資料，之後換語言不會改名。
- **App（Xcode）**：
  - `RailwayGameApp/Resources/Localizable.xcstrings`（String Catalog，來源英文，加上 `zh-Hant`）：SwiftUI 的字面字串（`Text`、`Button`、`Label`、`Section`、無障礙標籤等）自動查表。
  - App 自己算出的字串用 `String(localized:)`；只有格式、沒有文字的字串用 `Text(verbatim:)`，不進表。
  - XcodeGen 2.46.0 從 String Catalog 讀出語系，寫進專案的 `knownRegions`；`project.yml` 只改了版本號（0.2.0）。
- **用語的來源**，依序：
  1. `Railway/site_archive_clean/` 的繁體中文（作者的台灣鐵道網站）：準點、誤點 {n} 分、早到 {n} 分、尖峰、離峰、已收班、班距、月台、停靠、發車、到站、終點站、時刻表、區間車、普通車、快車、倍速、暫停。
  2. 參考 `Ci/` 的簡體中文介面（`ui-locales/zh-CN`），轉成繁體與台灣用語：經濟明細、經濟流水、小時淨額、能源費用（日結）、員工費用（日結）、票價收入、營運成本、維護成本、路線供電與牽引用電、列車日用電、車站員工、司機與調度員工、本期、上期、固定票價、階梯票價、票價規則、餘額不足、服務模式、上線列車數、開班、收班、候車、載客、第 N 日。`Ci/` 的高峰／平峰、站台、运营、快速列车、普通列车、发车间隔，改用上面台灣網站的說法（尖峰／離峰、月台、營運、快車、普通車、班距）。
  3. 兩者都沒有的（gap，自訂）：交通控制、進路、軌段、轉轍器的共用端、平面交叉，以及所有錯誤訊息與建設、列車操作的說明。
- **不翻譯**：GameCore（沒有介面文字）；金額（兩種語言都是 `$ 1,234`，與參考相同）、時鐘、座標、倍速（`600×`）；玩家取的名稱；Debug 的示範配置；App 的顯示名稱「Railway Game」（由作者決定中文名稱）。
- **驗證**：GamePresentation 的中文由 Linux 測試逐字固定；String Catalog 的鍵由腳本從 App 原始碼的字面字串抽出，每個鍵都有翻譯。Xcode 編譯 String Catalog 與實機上的中文排版要靠 CI 的 iOS 建置與 TestFlight。

### 39. 停站、上下車與實際時刻（Phase 4.7 Stage W2b）

W2a 把基本步長換成一秒；W2b 讓服務在秒上運作：列車在每一站依參考的停站規則停留，乘客在車門開著的時候上下車，實際的到達與出發時刻存檔，誤點由實際時刻與時刻表算出。取代 G1b 在離站那一刻一次完成上下車的過渡做法（決策 35 第 3、9 點）與決策 25 在畫面層推導的早到、誤點。

參考（2026-10-02 檢查）：

- `Railway/railway_game_reference_clean/02_W2_IMPLEMENTATION_CONTRACT.md` 與 `01_MIGRATION_MAP.md`（RailwayCore 15.3 的 `LoadUnloadVehicle`、`load_unload_ticks`、`lateness_counter`）：狀態 ARRIVED → DOORS_OPENING → ALIGHTING／BOARDING → DWELL_HOLD → DOORS_CLOSING → DEPARTING；`serviceTicks = max(⌈下車 ÷ 速率⌉, ⌈上車 ÷ 速率⌉)`；`departure = max(到達 + 最短停站, 早到時的排定出發, 到達 + 開門 + serviceTicks + 關門)`；沒有乘客也有最短停站；誤點是實際與排定的差，不能只存在畫面。
- `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`：`DWELL_GAME_SEC = 36`、`DWELL_TERMINAL_GAME_SEC = 42`（非環狀線的第一站與最後一站；來回的時間 `2 × 行駛 + 2f × 36 + 2 × 42`），車門開 8 秒、關 8.3 秒，`PARAMS.BOARDING_RATE = 2`（決策 35 第 9 點移植成 `StationDwell` 的常數）。
- `Railway/site_archive_clean/`：每站的實測停站時間屬於真實時刻表（決策 35 第 9 點已移植成純函式），遊戲的停站不用它們（見下面「不做」）。

規則（`Railway/ServiceDwell.swift`）：

- **`ServiceTimes`**：與列車一起存檔的權威狀態，服務執行時才有。`arrival`（到達正在等待的這一站；行駛中則是上一個等待過的站）、`exchangeEnd`（上下車到哪一刻為止；開門之前沒有）、`closing`（開始關門的時刻；開著門時沒有）、`departure`（實際離開前一站的時刻；還沒離開過任何一站時沒有）。都是秒。
- **啟動服務與派車算是到達第一站**：在那一刻開始停站。零距離的下一站（重複的車站、共用的月台、在同一站結束與開始的重複時刻表）也是一次新的到達，照樣停站。
- **停站的順序**，每一步依列車 ID：
  1. 到達後 8 秒車門開好（`doorOpening`，`Ci` 的 8 秒）；那一步讓坐到這一站的人下車（折返的站與最後一站，車上的人都下車），再讓等車的人上車（G1b 的規則，最後一站不上車）。兩者同時用車門，花 `⌈max(下車, 上車) ÷ (2 × 4 × 節數)⌉` 秒：每扇門每秒 2 人（`Ci` 的 `BOARDING_RATE`，單位是本專案定的），每節 4 扇門（gap：兩份參考都沒有門數）。
  2. 車門開著的時候，每個整分鐘釋出的人也上車，接在還在上車的人後面：`exchangeEnd = max(exchangeEnd, 現在) + 秒數`。
  3. 開始關門的時刻是 `max(exchangeEnd, 到達 + 最短停站 − 9, 排定出發 − 9)`：最短停站 36 秒（`Ci` 的 `DWELL_GAME_SEC`），時刻表的第一站、最後一站與折返的站是 42 秒（`DWELL_TERMINAL_GAME_SEC`）；都包含開關門的時間。早到的列車等到排定出發，誤點的列車只停最短停站與上下車需要的時間。
  4. 關門 9 秒（`Ci` 的 8.3 秒進位到整秒，不比參考短）之後出發，在任何一秒都可以。沒有路、或進路被占用（決策 32）時關著門原地等，每一步重試。
  5. 客滿的列車離開時，那一站還在等、它本來可以載的人記進 `refused`（決策 35 的次數）；有空位的列車在關門之前已經載走所有它能載的人。路線的列車照舊記下班次與距離（決策 36）。
- **路線的時刻表**：派車的那一刻到達第一站，42 秒後離開（端點的最短停站），之後的時間都由這個離開推算。路線原本留在第一站的 2 分鐘終點停留，分成出發前的 42 秒與回到第一站後剩下的 78 秒（比最短停站 42 秒長），所以準點的列車仍在 `roundTripMinutes` 之後可以再被派出，派車的分鐘不變。
- **誤點（`GameWorld.lateness(of:)`，秒，負數是早到）**：停站時，排定出發之後是超過的秒數，之前則是比排定到達早到的秒數（晚到但還趕得上排定出發算 0）；行駛時是離開前一站晚了多少與超過排定到達多少中較大的（都不算早到）。重複時刻表的排定時刻加上週期 × 輪次。
- **`advance`**：每一秒先處理整分鐘的帳、乘客與派車，再處理每台列車的停站與出發，再移動。兩個事件之間只有移動：一次走完到下一個整分鐘、停站事件（開門、開始關門、出發）或某台列車走完它的路為止，結果與逐秒相同，到站的時刻也是精確的。整分鐘沒有任何改變時，跳到下一個停站事件所在的分鐘（含剛好在下一分鐘開始的事件）或下一個可能派車的分鐘；有乘客釋出而且有列車開著門時不跳，因為新釋出的人會上車。
- **存檔**：`Train` 的 `times` 與 `execution` 同時有或同時沒有；開門、上下車、關門的順序要合理（`exchangeEnd ≥ arrival + 8`、`closing ≥ exchangeEnd`、等待時 `departure ≤ arrival`、行駛時必有 `departure ≥ arrival` 而且沒有停站的欄位），而且都不晚於時鐘（`exchangeEnd` 可以晚於時鐘：上下車還在進行；但有 `exchangeEnd` 時，開門的時刻 `arrival + 8` 不晚於時鐘）。沒有存檔版本（決策 6），App 也還沒有把存檔寫到裝置，所以執行中的服務沒有 `times` 的舊存檔被拒絕，不換算。
- **決定性**：全部是整數；時刻相加以飽和運算避免溢位（列車 ID 順序、乘客的處理順序不變）。

驗證：

- 參考模型（`ReferenceWorld`）以不同的寫法逐秒執行同樣的規則（沒有捷徑），Kernel 差分與所有 property campaign 都比對 `times`；所有 golden fixture 也在參考模型上重播。
- 手算的 `ServiceDwellTests`（參考包要求的情境：到達、沒有乘客的最短停站、上下車延長停站、開著門時加入的乘客、早到等排定出發、誤點不多等、停站中存檔、剛好落在整分鐘的事件不被跳過）與 golden `station-dwell.json`。
- golden schema 24：時刻表可以寫秒（`arrivalSeconds`、`departureSeconds`），列車的 `times`，`serviceTimes`、`lateness` 觀察；既有 fixture 改變的值逐一說明在 `GoldenScenarios/README.md`。

GamePresentation／App：早到與誤點改由 `lateness(of:)` 推導（仍以整分鐘顯示，不到一分鐘算準點）；新增 `DwellPhase`（開門中、乘客上下車中、開門停站、關門中、準備發車），列車面板在停站時顯示，英文與繁體中文。

不做：月台擁擠的延長（參考包的 `platformCongestionPenalty`）、轉乘（參考包要求的「轉乘的人帶著剩下的路線回到車站」，乘客目前只有單一路線的旅次）、依車種的門數與速率、`Railway/` 的每站實測停站時間、時刻表的停留（`dwellMinutes`）改用秒；行駛曲線接到移動（W2c）。

### 40. 行駛曲線接到行程與移動（Phase 4.7 Stage W2c）

W1 翻譯了跑段曲線（決策 33），W2a、W2b 讓服務在秒上運作（決策 37、39）；W2c 把曲線接上：服務的列車在兩站之間跟著 `RunningCurve` 走，不再照 rate 等速前進；路線以自己的性能規劃一段的秒數，取代 `ServiceLine.rate`；列車與路線各有性能（`TrainPerformance`）。

參考（2026-10-02 檢查，私有 repo `1563ad0`）：

- `Railway/site_archive_clean/index.html` `assignRunProfiles`（8367 行）：兩個停靠站之間是一段，`runT = s[k1].arrSec − s[k0].depSec`，以 `buildProfile(L, runT, a, b, v, coast)` 建曲線，建不出來時依序改用 `bAlt`、`aAlt`；列車的位置是 `profTimeToProg(rp, (t − runDep) ÷ runT)`。誤點的列車（`liveDelaySec`、21014 行的 `sourceSec − delaySec − eventSec`）沿同一條曲線、整段往後移。
- `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`：捷運列車 `METRO_TRAIN_ACCEL_MPS2 = 1.1`、`METRO_TRAIN_DECEL_MPS2 = 1.3`，新路線的設計速度 `maxSpeedKmh: e.maxSpeedKmh || 80`；一段的時間是加速到路線速度、在下一站前煞停的最短時間（梯形或三角形）。
- `Railway/railway_game_reference_clean/02_W2_IMPLEMENTATION_CONTRACT.md`：「Actual departure updates delay for the next segment」，`01_MIGRATION_MAP.md` 的 `StopTiming.travelAllowance` 與 `CmdAutofillTimetable`（由實際的行駛時間填時刻表）；`RUNNING → APPROACHING → ARRIVED` 由模擬推進。

規則（`Railway/RunningCurve.swift`、`Railway/ServiceRun.swift`、`World/GameWorld.swift`）：

- **性能**：`TrainPerformance` 可以存檔（`{ acceleration, braking, topSpeed }`，另有 `alternativeAcceleration`、`alternativeBraking`、`coast`），也有 `isValid`：每個率與最高速度在 1 到 2²⁰，惰行的減速度小於煞車、速度比在 0 到 999（`RunningCurve` 會默默忽略不合的惰行，指令則拒絕它）。新增 `metro` 預設：`Ci/` 的 1.1、1.3 m/s²（3.96、4.68 km/h/s，精確）與 80 km/h。
- **列車與路線的性能**（gap 4 的決定）：`Train.performance` 與 `ServiceLine.performance`，新的都是 `standard`；`setTrainPerformance(_:to:)`（`unknownTrain` → `trainServiceActive` → `invalidTrainPerformance`）與 `setLinePerformance(_:to:)`（`unknownLine` → `invalidTrainPerformance`，取代 `setLineRate` 與 `invalidLineRate`）。列車的性能只在不是標準時存檔，沒有的舊存檔讀成標準；路線以 `performance` 取代 `rate`（舊的 `rate` 鍵被忽略）。
- **一段的最少秒數**（gap 1 的決定）：`RunningCurve.leastSeconds(length:performance:)` 是性能建得出曲線的最少整秒（1 到 4,294,967）。建不建得出對時間是單調的（判別式只會變大、定速只會變小，加減速的時間也是），所以用二分搜尋。
- **路線的行程**：`LineLeg.seconds` 是路線的性能走完那段精確距離的最少秒數（零距離是 0），`LineJourney.roundTripSeconds` 是各段加上停站；路線以 `roundTripMinutes`（無條件進位到整分鐘）規劃列車數與班距，派車仍在整分鐘。時刻表的到達由這些秒數推算。比較行程時用秒。
- **一段行駛（`ServiceRun`）**：服務離開一站時，列車得到 `{ start, length, seconds }` 存在 `ServiceTimes.run`：
  1. 排定的時間 T = 下一站在該輪的排定到達 − 這一站的排定出發；
  2. T 在 1 到最多秒數之間、而且列車的性能建得出 T 秒的曲線時，這一段走 T 秒（參考的 `runT`）；
  3. 否則走最少的秒數（排得太緊：盡快跑、晚到）；
  4. 連最少的也沒有時沒有行駛，列車照 rate 移動（gap：參考建不出曲線時等速）。
  因為從實際出發的那一刻開始，晚出發的列車整段往後移、晚到同樣多（參考的 `liveDelaySec`）；準時出發就準時到達，不會早到。
- **移動**：跟著行駛的列車每一秒走曲線在這一秒結束與開始的距離差（`travelShare(of:from:)`）；rate 只決定動或不動（0 不動）。一段的結束（`run.end`）是一個服務事件。
- **被擋住**（gap：參考只依時間取樣，沒有被擋住的列車）：這一步結束時剩下的路比曲線剩下的長（rate 為 0，或前方鐵軌被拆）就丟掉這段行駛（`dropRunsHeldUp(endingAt:)`）；之後 rate 大於 0、還有路、而且能往前走 1 單位時，從停止狀態以最少的秒數走剩下的路（`resumeRun(_:at:)`）。不這樣做的話，放行的列車會以被擋住時曲線的速度瞬間起跑。
- **閒置分鐘的捷徑**：很慢的一段可能整分鐘都不動，之後才往前一個單位；`nextRunMove(from:)` 找出下一個會讓某台列車往前的秒，閒置的分鐘不跳過它。
- **存檔**：`run` 只在行駛中有，`start` 不早於實際出發；列車的性能必須建得出它的曲線（`Train` 的解碼器檢查），長度至少 1、秒數在 1 到最多秒數。
- **決定性**：全部是整數；曲線是 W1 的整數實作。

驗證：

- 參考模型（`ReferenceWorld`）另外寫了最少秒數（從全程最高速的時間往上逐秒試）、剩下的路（沿連結與 continuation，或沿路網的邊）、能不能動（在複本上走 1 單位）與每秒的行駛；Kernel 差分、所有 property campaign 與 golden 重播都比對 `run`。
- campaign 在小地圖上用 1 km/h 的慢速性能（約每分鐘一格，和以前的 rate 相近），讓行駛持續幾分鐘、狀態看得到；`PerformanceSamples` 也包含所有預設與不合法的性能。
- 手算的單元測試：最少秒數（√(2L·(1/a + 1/b)) 與最高速的情形）、準時的行駛、排得太緊、晚出發整段後移、被擋住與放行、拆軌、指令的檢查順序、存檔與拒絕、批次與逐秒相同；golden schema 25 與手算的 `service-run.json`。

GamePresentation／App：`invalidTrainPerformance` 的英文與繁體中文訊息；示範地圖不再設定路線的 rate。畫面還沒有選性能的控制（之後與車種一起做）。

不做：限速區段與觀測曲線（gap 7）、依車名選性能（列車還沒有車種）、曲率與坡度限速、跟車與號誌（U）、通過站的推導時刻（gap 8）。

### 41. 任意角度的建造畫面（Stage C1）

S3–S5 讓 GameCore 有了任意角度的路網、高程、結構物與路網上的月台，S5 起停站、時刻表、路線與派車都在路網上運作；但 App 只能在方格上鋪軌，Release 版的新遊戲沒有路網（示範地圖只在 Debug）。2026-10-02 作者決定，U-min 之前先補齊已完成核心的操作畫面（ROADMAP 的 Stage C），C1 是第一步：在 App 裡建造路網、月台，並把列車放上去。**GameCore 沒有修改**：golden 與 property digest 都不變。

參考（2026-10-02 檢查三份）：只有 `Ci/reference_snapshot/` 有玩家的建造模式（`app__q_c234188b7c397f91.js`）；`Railway/site_archive_clean/` 是真實路線的地圖，只有結構物的繪製參數，沒有建造工具；`Railway/railway_game_reference_clean/` 是 OpenTTD 的編譯檔與文件，只有建造指令的名稱與「驗證、估價、執行」分開的建議（`01_MIGRATION_MAP.md`）。對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-c1任意角度的建造畫面)。

**GamePresentation**（Linux 上測試）：

- `NetworkBuilding.curve(from:leaving:to:leaving:)`：照 `Ci/` 的建造模式。
  - 位置自由：不對齊格線、角度不限（`Ci/` 沒有吸附）。
  - `Ci/` 把一條線畫成通過各點的 centripetal Catmull-Rom 曲線（`catmullRom`），端點重複；換成 Bézier，端點的控制點在弦上、弦長的三分之一。`Ci/` 每加一點就重畫整條線；GameCore 的邊建好後不會改，所以接著既有軌道的一端沿那條軌道的方向（控制點同樣在三分之一弦長），自由的一端照 `Ci/` 沿弦。兩端都自由時是直線，與 `Ci/` 相同。
  - 轉彎超過 90 度拒絕（`Ci/` 的 `_turnAngleDeg` 與 `MIN_TURN_ANGLE_DEG = 90`）：以內積的正負判斷，整數、精確。`Ci/` 以曲線往回 10 公尺的點近似切線（`EXTENSION_TANGENT_LOOKBACK_M`），這裡直接用邊端的方向。
  - 控制點四捨五入到整數單位，方向的誤差遠小於 GameCore 相接的 1/16，所以接得上。
- 接到哪一端：節點上每個邊端都是一個可以接的方向（與邊端離開的方向相反）；選最接近目標、而且轉彎不超過 90 度的那個。節點有邊端但都轉太多時拒絕（`Ci/` 的訊息「小於最小轉彎半徑」）。關掉「平順曲線」時一律是直線，不保證相接。
- 新節點離另一端不到 22 公尺時拒絕（`Ci/` 的 `ANCHOR_MIN_SPACING_M`，訊息「該位置與既有節點過近」）。
- 點選的範圍：以畫面的 24 點計（`NetworkBuilding.touchRadius`）。`Ci/` 以 50 公尺（`ANCHOR_PICK_RADIUS_M`）在城市地圖上點選；這張地圖畫得近十倍，同樣的公尺數會一次點到好幾格外。
- `GameSession` 的路網工具（`ConstructionTool.network`）：
  - 模式：鋪設、月台、拆除（`NetworkToolMode`）。
  - 草稿（只存在 session，不是權威狀態）：起點與終點（`NetworkAnchor`：既有節點，或新節點的位置）、在軌段上點到的位置（`NetworkEdgePoint`）。
  - 設定：結構物、新節點的高度（每 2 公尺，地面上下 64 公尺）、平順曲線、緩和坡度（高度不同時兩端各有四分之一長的豎曲線）、月台的節數、月台所屬的車站。
  - 預覽（`networkPreview`）：在世界的副本上執行建造會用的同一串指令，再丟掉副本；費用是餘額的差，拒絕時顯示 GameCore 的訊息。`Ci/` 的預覽在不能建時變灰（`computePlacePreviewInvalid`），這裡相同。
  - 建造（`buildNetworkTrack()`）：新的端點先 `buildTrackNode`，再 `buildTrackEdge`；終點變成下一段的起點。
  - 月台（`addNetworkPlatform()`）：以點到的位置為中心、`節數 × Train.carLength` 長，移到不超出軌段；所屬車站預設是兩格內最近的車站，沒有就在月台中點下方的格子 `buildStation`，再 `addTrackPlatform`。
  - 拆除（`removeNetworkEdge()`）：`removeTrackEdge`，再拆掉兩端沒有其他軌段的節點。
  - 列車工具：選到的車站在路網上有月台時，`placeSelectedTrain()` 把列車放到第一個放得下的月台（沒有就最長的），朝向決定行進方向，車頭在月台的遠端，並以沒有路段、停在原地的 continuation 讓它停住。
  - **原子性**：幾個指令組成的操作都在 `var draft = world` 上執行，全部成功才換掉 session 的世界；任何一步被拒絕，世界完全不變（例如建造被拒時不會留下新節點）。每一步仍是 `GameWorld` 的指令，session 不判斷遊戲規則。
- 畫面要畫的東西（`NetworkOverlay`）與地圖座標的換算（`MapScale.worldPoint`、`worldDistance`）也在 GamePresentation，可以測試。
- 文字：英文與繁體中文（軌段、節點、月台、高架、隧道等沿用決策 38 的用語）；`networkSummary` 在有軌段時加上軌段數。

**App**：

- 工具列多了「路網」；它的選項（`NetworkControls`）有模式、結構物、高度、兩個切換與預覽，月台模式有節數、所屬車站與這個軌段上的月台（可以拆）。動作按鈕依模式建造（顯示費用）、設置月台或拆除。
- 地圖：路網工具的點選換成世界座標，交給 session；畫出起點（實心圓）、終點（圓環）、可以建的段（實線加光暈）或不能建的段（灰色虛線），以及要拆的軌段（紅色）或月台的範圍（車站色）。形狀不同，不只靠顏色。
- 檢視列在路網工具下顯示點選了什麼。

**驗證**：`NetworkBuildingSessionTests` 以手算的控制點、長度與費用，比對 session 的世界與直接對 GameCore 執行同一串指令的世界：直線、平順延伸（GameCore 確實把兩段接起來）、太近、轉太多、被拒絕時不留下節點、高架爬升與太陡、豎曲線、月台與新車站、既有車站的月台、依朝向放置列車、拆除與孤立節點、中文。SwiftUI 只能在 macOS CI 編譯，實機的操作要用 TestFlight 檢查。

**已知限制與留給之後**：

- 沒有拖曳：兩次點選加確認。`Ci/` 每次點選直接建站或節點、可以復原；這裡沒有復原，所以先預覽再確認。
- 不能移動或刪除單獨的節點、不能在軌段中間切開接上新的軌段（`Ci/` 有節點的移動與刪除、在線上插站）；GameCore 的邊建好後不變，要加切開的指令。
- 車站仍然要放在一個方格上（月台中點下方的格子），那一格被方格的鐵軌或其他車站佔用時無法新建車站。
- 側向淨空（平行的軌道太近時拒絕）是新的 GameCore 規則，不在 C1。
- VoiceOver 無法在路網工具裡指定任意位置。

### 42. 性能的畫面（Stage C3）

W2c（決策 40）讓每台列車與每條路線都有自己的 `TrainPerformance`，預設 `standard`，由 `setTrainPerformance`、`setLinePerformance` 更換，但留下「選性能的畫面」。W2c 合併之後，作者要求一起做，所以 C3 排在 C2 之前。**GameCore 沒有修改**。

參考（2026-10-02 檢查三份，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-c3性能的畫面)）：

- `Railway/site_archive_clean/index.html` 的 `PERF_*`、`PERF_RULES`、`PERF_BY_TYPE`：依真實車名選性能。數值在 W1 已移植成 `TrainPerformance` 的預設；畫面以參考配對的車名命名每個預設。
- `Ci/reference_snapshot/` 的建線畫面（`game-dom` 的 `#modal-line`）：「設計時速」（`metro.line.design_speed`），選項是 `LINE_SPEED_MAIN_NON_SG`（80、100、120、160）與其他（`LINE_SPEED_EXTRA_NON_SG`），合起來是 `LINE_SPEED_ALL_NON_SG`；車型（`TRAIN_TYPES`）只決定每節的容量。
- `Railway/railway_game_reference_clean/`：OpenTTD 的 `BuildVehicleWindow` 只有名稱，沒有可以移植的內容。

**GamePresentation**（Linux 上測試）：

- `PerformancePreset`：GameCore 的 14 個預設，依參考的規則命名（區間車、普通車、莒光／復興、自強、EMU3000、推拉式自強、太魯閣、普悠瑪、柴聯自強、DR1000、阿里山林鐵、高鐵），加上標準與捷運（`Ci/` 的捷運列車）。`init?(matching:)` 找加減速與惰行相同的第一個預設（不看最高速度，因為設計時速只改它）；DR1000 與柴聯自強的數值相同，顯示為先列出的柴聯自強。
- `PerformancePreset.designSpeeds`：`Ci/` 的 `LINE_SPEED_ALL_NON_SG`，60 到 200 km/h。`TrainPerformance.withTopSpeed(_:)` 只換最高速度。
- 文字：`displayText(in:)`（「區間車 · 120 km/h · 2.5 / 3 km/h/s」，對不上預設時是「自訂」）、`durationText(seconds:in:)`、路線的 `lineJourneyText(_:in:)`（以路線的性能規劃的各段與來回）、列車的 `trainRunText(of:in:)`（`ServiceTimes.run`：秒數、距離、預計到達）。
- `GameSession.setSelectedTrainPerformance(_:)`、`setSelectedLinePerformance(_:)`：各呼叫一個 `GameWorld` 指令；行駛中的列車被拒絕（`trainServiceActive`），不合法的性能被拒絕（`invalidTrainPerformance`），世界不變。

**App**：`PerformanceMenu`（現在的性能與一個選單：車種、設計時速），放在列車工具與路線面板；路線面板另外顯示各段與來回的時間，列車工具顯示正在走的行駛。

**驗證**：`PerformanceSessionTests` 以手算的值比對：兩個連結在標準性能是 16 秒、在 1 km/h 是 120 秒（W2c 的手算值），來回加上 480 秒的停站；派車後 08:00:42 出發、08:02:42 到。

**留給之後**：自訂加速度與減速度、依車種的容量（`Ci/` 的 `TRAIN_TYPES`）、指派列車時沿用路線的性能。

### 43. 營運與乘客的設定畫面（Stage C2）

Stage C 的第二步（ROADMAP 的盤點表）：GameCore 已有、App 卻沒有畫面的營運與乘客功能。最重要的是車站需求：App 從來沒有呼叫 `setStationDemand`，所以實機上沒有乘客，也沒有票價收入，G1 的經營閉環無法在 TestFlight 上測試。依作者指示先做車站需求，再做時刻表、路線停靠站與服務日、轉轍器與平面交叉、唯讀資訊。**GameCore 沒有修改**：golden 與 property digest 都不變。

參考（2026-10-02 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-c2營運與乘客的設定畫面)）：

- `Ci/reference_snapshot/`：自訂運量面板（`game-dom` 的 `#panel-station-flow-adjust`；`app__q_c234188b7c397f91.js` 的 `applyStationFlowPreset`、`copyStationFlowAdjustProfile`、`pasteStationFlowAdjustProfile`、`applyStationFlowAdjustToAllServingLines`、`drawStationFlowAdjustCanvas`、`stationFlowProfileArrayForUiMode`），以及服務時段的提示（`metroServiceSlotTimeRanges`）。`Ci/` 沒有每台列車的時刻表、沒有方格，時段固定寫在程式裡。
- `Railway/railway_game_reference_clean/`：時刻表的概念（`01_MIGRATION_MAP.md` §2，編譯檔的 `TimetableWindow`、`CmdSetTimetableStart`、`CmdChangeTimetable`、`CmdAutofillTimetable`、`gui.timetable_arrival_departure`）。只有符號，沒有原始碼。
- `Railway/site_archive_clean/`：真實的時刻表與股道，沒有玩家編輯的畫面；轉轍器、單雙線在 S1 已經對照過。

**GamePresentation**（Linux 上測試）：

- **車站運量**（`StationDemandText.swift`）：
  - `StationDemandKind.title(in:)`：參考的四種預設（居民區、辦公區、購物中心、景區），台灣用語住宅區、辦公區、購物中心、景點。
  - 換預設時保留車站的日運量（參考的「預設保持該車站預設的全天總量」）。沒有運量的車站從 `StationDemand.defaultDailyTrips`（10,000）開始：參考的總量來自伺服器資料，快照裡沒有，這是 gap；10,000 的尖峰小時約 870 人次，幾列車的量。
  - `dailyTripSteps`：100、200、500 … 1,000,000（1、2、5 的級距），`dailyTrips(above:)`、`dailyTrips(below:)`。
  - 複製、貼上、套用到整條路線：照參考的 `stationFlowProfileForTarget`，目標站保留自己的總量；目標原本沒有運量時用來源的日運量（gap：我們的車站沒有預設總量）。套用到整條路線是經過這一站的每條路線的每個停靠站（含自己），在世界的副本上全部成功才生效（決策 41 的原子性）。訊息照參考的「已套用到 N 條路線，共 M 座車站」。
  - `StationFlow`：進站（從這一站出發的旅次，參考 `in` 畫布畫的 `out` 曲線）與出站（在這一站結束的旅次）每小時的人次，加總 GameCore 的 `hourlyDemand`。還沒有路線連到其他有運量的車站時（`isShape`），以 `StationDemand.dayShape` × 該預設的曲線，用最大餘數法把自己的日運量分到 24 小時，對應參考沒有基數時畫預設形狀。`summaryText`（全日總量與最多的小時）、`hourText`（某一小時）。
  - 唯讀：`stationDemandPairs`（往返各站的每日旅次，`dailyDemand` 兩個方向）、`passengerLedgerRows`（`passengerLedger` 的各列）、`lines(callingAt:)`。
  - `GameSession`：`selectedStation`（選取格上的車站；F1 起改為選取的車站，決策 44）、`demandClipboard`（只存在 session 的剪貼簿，不是權威狀態），以及設定預設、日運量、移除、複製、貼上、套用的方法，各呼叫 `setStationDemand`。
- **列車的時刻表**（`TimetableEditing.swift`）：照參考包的時刻表概念，起點時刻、每站的行駛與停留時間，顯示成到達與出發，加上重複週期。
  - 直接編輯世界，不另存草稿：每個操作讀出列車的時刻表、改一份副本，呼叫一次 `setTrainTimetable`。
  - 新增停靠站：第一站在下一個整分鐘到達，之後每站在上一站出發 3 分鐘後到達；每站停 1 分鐘。參考由實際跑一趟填入行駛時間（`CmdAutofillTimetable`），App 還沒有，這是 gap。
  - 移動到達：這一站與之後的停靠站一起移動，所以只改到這一站的行駛時間；不早於前一站出發（第一站不早於第 0 秒，移動第一站就是參考的「起點」）。移動出發：只改停留，不早於到達。
  - 折返、刪除停靠站、清除、重複：開啟重複時週期是涵蓋整份時刻表的最短整分鐘（至少一分鐘），每次加減一分鐘；編輯讓時刻表超過週期時，週期跟著加長，不讓 GameCore 拒絕。刪到沒有停靠站時不再重複。
  - 服務執行中、或列車屬於路線時，GameCore 拒絕（`trainServiceActive`、`trainOnLine`），畫面顯示原因並停用控制項。
- **路線的停靠站與服務日**（`LineEditing.swift`）：
  - `LineStopEditing`：插入、刪除、上下移動，各呼叫一次 `setLineStops`。GameCore 拒絕連續兩次同一站與少於兩站；不再提供的行程，等車的乘客記進 `abandoned`。區間車照 GameCore 的規則保留停靠的位置。
  - `ServiceDay.ranges(of:)`：照參考的 `metroServiceSlotTimeRanges`，逐分鐘找出某一等級的時段，相鄰的同等級合併，最後一段結束在 24:00。`summaryText` 取代路線面板原本寫死的標準時段說明。
  - `ServiceDayEditing`：參考的時段寫死在程式裡，編輯是 App 自己的（gap）。改等級、每次半小時移動開始時間（介於前後時段之間，第一段固定 00:00）、刪除（由前一段延續）、拆分最長的時段（在中點，取整到半小時，兩半同等級，所以行為不變）、回到標準服務日，各呼叫一次 `setServiceDay`。
- **方格的轉轍器與平面交叉**：`TrackPieceKind`（一般、轉轍器、平面交叉）、`GameSession.trackPieceKind`、`turnoutStem`。
  - 轉轍器至少要三個出口，所以從 T 字岔開始；共用端預設是第一個直線穿過的出口（西、北、東、南），跟著旋轉，而且一定是出口之一。`buildTurnout(at:connections:stem:)`。
  - 平面交叉有四個出口；改任一方向或選四向以外的形狀時變回一般。`buildCrossing(at:)`。
  - `trackPieceKindText`、`trackPieceLayout`：選單與預覽用。
- **唯讀的軌道資訊**（`TrackInfoText.swift`）：`sectionTexts(at:in:)`（經過某一格的區段，分歧點是好幾個區段的端點）、`trackSectionsSummary`、`lineTrackCountTexts`（路線相鄰停靠站之間的單線、雙線或更多，方格上沒有軌道時說明）、`occupancyConflictTexts`（兩台以上列車佔用同一段軌道）、`TrackResource.displayText(in:)`。`parallelTracks` 只數方格的軌道（S1），路網的單雙線是 V 的範圍（F3c-1 起也數路網，區段也有路網版 `networkSections()`，見決策 51）。

**App**：

- 檢視列選到車站時多一個「運量」按鈕，打開運量面板（`StationPanel`，半高的 sheet，地圖仍可操作）：四種預設（SF Symbols 的房子、大樓、購物車、山，對應參考的圖示；參考的 PNG 是 24–48 px 的黑色圖，不會跟著深色模式與字級）、日運量、複製、貼上、套用到整條路線、移除；進站與出站的每小時長條圖；往返各站的每日旅次、候車與乘客帳。可以從選單換車站。
- 長條圖（`HourlyBarChart`）：照參考的畫布，每小時一根、從同一條基線長出，目前的小時用強調色、其他用次要色；點一下長條或用 VoiceOver 上下滑動可以看那一小時；下方文字一定寫出全日總量、最多的小時與顯示的小時，不只靠顏色。
- 列車工具多一個時刻表按鈕（顯示摘要），打開 `TimetableEditor`：停靠站、到達與出發的加減、折返、重複與週期、開始或停止服務、清除；不能修改時說明原因。
- 路線面板：服務日（各時段的等級、開始時間、刪除、拆分、標準服務日）；選取的路線多了停靠站的編輯，以及相鄰停靠站之間的單雙線；路線說明改成依目前服務日的時段。
- 軌道工具的形狀旁多一個選單：一般、轉轍器（與共用端）、平面交叉；預覽照地圖畫出共用端與平面交叉。
- 選取工具顯示方格的區段、經過選取格的區段，以及共用軌道的列車。

**驗證**：`StationDemandSessionTests`（每小時的值以參考的曲線手算）、`TimetableEditingTests`、`LineEditingTests`、`TrackLayoutSessionTests`、`TrackInfoTextTests`，比對手算的值與直接對 GameCore 執行同一串指令的世界。SwiftUI 只能在 macOS CI 編譯，實機的操作要用 TestFlight 檢查。

**已知限制與留給之後**：

- 運量：參考可以拖曳單一小時或整天的曲線，也有機場、高鐵的樞紐倍數；GameCore 的需求只有四種類型與日運量，要加自訂曲線與樞紐需要新的 GameCore 規則。參考的「恢復預設」是平的曲線，GameCore 沒有，所以只有移除。
- 時刻表：沒有自動填入行駛時間；以分鐘為單位加減（GameCore 接受秒）；不能重新排序停靠站。
- 服務日是全部路線共用一份（GameCore 的設計）；參考沒有編輯畫面。
- 單雙線只數方格的軌道（F3c-1 起也數路網）。

### 44. 全面路網：任意座標的車站（Stage F1）

2026-10-02 作者決定（C2 合併之後）：鐵軌全部改用路網，車站與土地自由擺設，不再以方格為單位（ROADMAP 的 Stage F）。F1 是第一步：車站可以放在世界座標的任意一點，App 只用路網建造。方格與方格車站留作相容層，舊存檔與既有 golden 的預期值不變；移除方格是 F3，要作者另外同意。

參考（2026-10-02 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-f1全面路網)）：`Ci/reference_snapshot/` 的 `placeStation` 把車站放在任意經緯度，沒有方格；`findStationAtLatLng`、`STATION_CLICK_SNAP_M`（20 公尺）點在車站附近就用那一站；`metroHasCoincidentStation`（同一線 0.1 公尺內）不重疊；`MIN_STATION_DISTANCE_M`（400 公尺）預設關閉。`Railway/railway_game_reference_clean/` 只有 OpenTTD 以方格為單位的 `CmdBuildRailStation` 符號；`Railway/site_archive_clean/` 是真實車站的經緯度，留給 E2。

**GameCore**：

- `Station.point: PlanPoint?`：建在一個點上的車站。它不佔格：`tiles` 是空的，`annexes` 是空的，地圖不變，`position` 是點所在的格（只為了既有以格為鍵的查詢，向下取整）。`Station.location` 是車站在平面上的位置：點，或方格車站第一格的中心。
- `buildStation(named:at: PlanPoint)`：檢查順序與方格版相同（名字 → 位置 → 配發 ID → 扣款），點不在地圖上時以點所在的格回報 `outOfBounds`；不檢查格上有沒有東西，同一格可以有好幾座點車站，也可以在方格軌道或方格車站的格上（它們互不相干）。一樣收一座車站的費用，失敗不改變世界。
- 點車站沒有方格的月台：`platforms(of:)` 是空的，`extendStation` 以 `invalidStationTile` 拒絕。它只在路網的邊上有月台（`addTrackPlatform`，S4、S5），所以找路、停站、路線、乘客與經營都不用改：它們本來就以車站 ID 與月台為準。
- `station(near:within:)`：依 `location` 找最近的車站，同樣近時取 ID 小的；`reach` 是負數或超出範圍時是 `nil`。
- 存檔：點車站寫成 `{ "id", "name", "point": { "x", "y" } }`，沒有 `position` 與 `annexes`；讀檔拒絕兩者並存、負的點，以及不在地圖上的點。方格車站的格式不變。
- golden schema 26：`buildStationAt` 指令、最終狀態的 `point` 形式、手算的 `free-station.json`；既有的二十五個 fixture 只改 `schemaVersion`。差分模型（`ReferenceWorld`）自己實作同樣的規則，`KernelDifferentialTests` 比對 `point`。

**GamePresentation**：

- `GameSession.selectedStationID`：選取的車站，只存 ID。點車站不佔格，所以不能再由「選取格上的車站」推出。`tapMap(at:reach:)`：選取或列車工具點地圖時，選那一格的方格車站，否則觸控範圍內最近的車站（`station(near:within:)`），否則點在那一格裡的點車站；`selectStation(_:)` 從清單選。`select(_:)`（鍵盤與 VoiceOver 的逐格移動）選那一格的車站。`selectedStation` 是選到的那一站，否則是選取格上的方格車站（相容層：在選取格上建的方格車站也算）。
- 列車工具與新路線用選取的車站：放到它的路網月台，送往它（`path(from:toStation:)`）；點車站沒有月台時說明要先加月台。方格的放置與送往仍以選取格進行（相容層）。
- 路網的月台工具在月台中點建一座點車站，取代 C1 的「月台中點下方的格子」；兩格內已有車站時沿用它（點車站以點計距離），所以同一處的第二條軌道加入同一站。
- `GameWorld.stationSummary(_:in:)`：車站的規模以路網上月台的數量與總長表示（「2 座月台，共 128 公尺」）；`Station.placeText(in:)`：點車站以公尺寫出位置。`selectionText()`：檢視列的文字。
- `ConstructionTool.networkTools`：App 提供的工具（選取、路網、列車）。方格的軌道、車站、拆除工具與 C2 的方格轉轍器、區段資訊留在 GamePresentation 當相容層的一部分，測試照舊；App 不再提供，F3 再一起移除。

**App**：工具列只有選取、路網、列車；拿掉方格軌道的編輯器（`TrackPieceEditor`）、車站工具、拆除工具與選取工具的方格區段資訊。地圖不畫格線，只畫邊界；點車站畫成圓形徽章、列車符號與站名，選到時有強調色的外圈；方格的軌道與車站照舊畫在格上。點地圖改成世界座標加觸控範圍。檢視列、站名清單與運量面板用選取的車站。

**驗證**：`FreeStationTests`（GameCore，手算）、golden `free-station.json`（GameCore 與 `ReferenceWorld` 都跑）、`FreeStationSessionTests`（GamePresentation）。既有的 golden 預期值、差分與 property campaign 都不變。SwiftUI 只能在 macOS CI 編譯，實機要用 TestFlight 檢查。

**已知限制與留給之後**：

- 車站沒有服務範圍；乘客仍是車站之間的需求（G1a）。以距離計算服務範圍是 Phase 5–7（ROADMAP）。
- 車站不能移動、改名或拆除；`Ci` 可以拖曳車站，GameCore 還沒有對應的指令。
- 平行軌道之間沒有側向淨空（F2）。
- 示範地圖仍以方格建造，C4 用路網重做。

### 45. 存檔、開始畫面與路網的示範地圖（Stage C4）

Stage C 的測試輔助：每次開 App 都要重蓋路網，是實機測試成本最高的地方。C4 加入存檔與讀檔（含存檔版本與遷移）、開始畫面，並把示範地圖改用路網重做、在 Release 也能開。開始畫面是 2026-10-02 作者加入的（教學排在 C5）。

參考（2026-10-02 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-c4存檔開始畫面與示範地圖)）：

- `Ci/reference_snapshot/` 的本機存檔是 `{app, version, exportedAt, data}`（`buildLocalSavePayload`）；建造時自動寫入草稿；開始時的存檔卡片可以「直接進入」或「重新開始」（`screen-save-load-ui`），重新開始前先把目前的草稿另存（`archiveMetroAppCurrentDraftBeforeFreshStart`）；雲端存檔每 15 分鐘自動存一次（`AUTOSAVE_INTERVAL_MS`）；桌面版有本機槽位、匯出與匯入 JSON。
- 參考包（`Railway/railway_game_reference_clean/`）：`01_MIGRATION_MAP.md` 建議存檔一開始就有 `schemaVersion`，「每次格式改變都要有明確的遷移函式與回歸存檔」；`docs/savegame_format.md` 是 OpenTTD 的二進位格式（外層記版本、各欄位依版本範圍讀取）；`web_runtime/offline_persistence_file_io.md` 是匯入與匯出，並要以版本遷移取代「版本一變就清掉所有存檔」。
- `Railway/site_archive_clean/` 只把偏好設定存在 localStorage，沒有遊戲存檔。

**GameCore**：`SavedGame`：`{"saveVersion": n, "world": {...}}`。

- 版本屬於 GameCore，因為只有它知道世界的格式。版本 1 就是 C4 時 `GameWorld` 的 `Codable` 形式；它本來就讀得進更早的世界（之後加的 key 都可以省略），所以 C4 之前沒有需要遷移的存檔（App 也從來沒有存過檔）。
- 讀檔時拒絕比這個 build 新的版本，不去猜；也拒絕 1 以下的版本。之後格式改到舊存檔讀不進來時，提高 `currentVersion`，在 `SavedGame.init(from:)` 加上從前一版轉換的一步。
- `SaveFixtures/`：每個版本留一份回歸存檔，之後的 build 都必須讀得進來、能來回編碼、能繼續跑（`SavedGameTests`）。規則和 golden 一樣：不能為了讓測試通過去改或重產它（`CLAUDE.md`）。版本 1 的存檔是示範地圖跑了 90 分鐘：點車站、一座兩個月台的車站、地面與高架的邊、兩條路線、交通控制下的列車、等車的乘客與公司的帳。
- golden 與 property digest 都不變。

**GamePresentation**：

- **Foundation**：只為存檔的 JSON 與檔案使用。它是 Linux 的 Swift 工具鏈的一部分，所以存檔一樣在 Linux CI 上測試；GameCore 仍然不 import Foundation。
- `SaveLibrary`：一個資料夾裡的存檔，自動存檔是 `autosave.json`，玩家自己的存檔一個一個檔案（`save-<UTC 時間>.json`）。檔案是 `{"app": "RailwayGame", "savedAt", "summary", "game": SavedGame}`，對應參考的 `{app, version, exportedAt, data}`；`summary`（遊戲時間、現金、車站、路線、列車數）讓清單不必解出每一個世界。
  - 讀檔先看檔頭：不是本遊戲的檔案、比這個 build 新的版本，在清單上就標出原因；世界本身由 GameCore 在讀取時檢查。寫入是整個檔案原子替換。
  - 匯出：寫一個檔案到暫存資料夾，再交給分享（`exportFile`）。
- `GameLauncher`：開始畫面與遊戲選單的動作；持有正在玩的 `GameSession`（沒有就是開始畫面），存檔只讀它的世界、不改它。
  - 新遊戲、示範地圖、繼續（自動存檔）、讀取、匯入。
  - 自動存檔的時機：App 離開前景、回到開始畫面、遊戲中每 15 分鐘（參考的 `AUTOSAVE_INTERVAL_MS`）。
  - 另開一局（新遊戲、示範地圖、讀取別的存檔、匯入）之前，先把自動存檔另存成玩家的存檔，所以上一局永遠不會被蓋掉（參考的重新開始前另存草稿）。
  - `setActive(_:)`：只有在前景時跑 game loop 與定時自動存檔。
- `GameWorld.newGame()` 從 App 移到這裡，開始畫面才能開新局。
- `DemoWorld`：路網的示範地圖，從新遊戲開始，用一般的指令、照常付費建好。
  - 地面的 1 號線（西站、中央、東站）與跨越它的高架 2 號線（北站、中央、南站），不共用軌道。
  - 中央是一座點車站，在兩條線上各有一個月台。
  - 兩條線全天營運，各有一列四節列車；每站都有運量，所以一開就有乘客、票價與成本。
  - 舊的方格示範配置（`DemoLayout.swift`）刪除。

**App**：

- **開始畫面**（`StartView`）：繼續（顯示存檔的遊戲時間、現金與規模，以及存檔時間）、新遊戲、示範地圖、存檔清單（點一下讀取、滑動刪除；讀不進來的寫出原因）、匯入（「檔案」App）。
- **語言**：參考的首頁有語言選單；iOS 的每個 App 的語言在「設定」裡，所以這裡是一個打開「設定」的按鈕。
- **遊戲選單**（HUD）：儲存遊戲、匯出存檔（分享時才寫出檔案）、回到開始畫面（先自動存檔）。
- **`-demo-layout` 啟動參數**：仍然只有 Debug 有，`release-archive.yml` 確認 Release 的執行檔不含它（參數名太短，Swift 把 15 位元組以內的字串放在程式碼裡而不是二進位的資料裡，直接找不到；所以改找 Debug 專用的 `DebugLaunch.marker`，`ios-build.yml` 也確認 Debug 的 App 找得到它）；示範地圖本身在 Release 由開始畫面開啟。

**驗證**：`SavedGameTests`（GameCore：格式、拒絕的情況、回歸存檔）、`SaveLibraryTests`、`GameLauncherTests`、`DemoWorldTests`（GamePresentation，用暫存資料夾與固定的時間）。SwiftUI 只能在 macOS CI 編譯，實機要用 TestFlight 檢查。

**已知限制與留給之後**：

- 沒有雲端存檔與帳號（參考的雲端槽位、加密、分享碼）；iCloud 之後另議。
- （決策 46 已處理）示範地圖照當時的經濟數值，大約 1.5 個遊戲小時後現金變成負的：新遊戲只有 $ 10,000，兩條線每小時的營運成本約 $ 4,500，票價約 $ 1,400。這是 G1c 的數值與新遊戲資金的平衡問題，不在 C4 修改。
- （已由決策 47 處理）教學。

### 46. 經濟平衡（G1d）

2026-10-03 核對經濟的平衡（作者交給 Claude Code 決定做法）。G1c（決策 36）照 `Ci/` 經濟的**舊路徑**移植，逐項核對後公式都對；但舊路徑只在參考的經濟引擎（`window.MetroEconomy`：`economy.js`、`metro_economy_rules.js`、`MetroFarePolicy`）載入時才執行，而引擎本身不在快照裡：開局資金、建設的配額與價格、營運補貼、新版的成本公式與票價政策都在引擎裡。`Railway/` 沒有經濟；`Railway/railway_game_reference_clean/` 只有 OpenTTD 的二進位與檔名（`src/economy.cpp`），沒有可用的數值。

**實測**（GameCore 模擬一天，修改前）：示範地圖每天票價收入 $ 400,000、成本 $ 113,500，開局只有 $ 10,000、蓋示範地圖花 $ 7,380，所以一個遊戲日就賺開局資金的 29 倍；在票價編輯器儲存同樣的 $ 5 均一票價後，乘客剩 1%，每天虧 $ 109,500；照參考自己的票價水準（距離票價 $ 0.55–1.20），每一種線都虧錢。另外，經營模式下玩家可以把任何車站設成每天 1,000,000 人次，列車買一節之後加到 16 節也不用錢。

| 參考 | Swift | 分類 |
| --- | --- | --- |
| `metroEconomyFixedAssets`：依 `branchRootId` 分組，每組各自的車站集合，相加 | `fixedAssets(memo:)`：每條路線的停靠站各算一次，再相加 | faithful（更正決策 36：原本全路網只算一次） |
| `metroFareDemandPenaltyForTrip`：`n>0\|\|(n=a)`，0 以下的票價當成基準 | `FareRules.demandFactor(fare:baseline:)`：0 以下是 1000‰ | faithful（更正決策 36 第 6 點的 1080‰） |
| `metroFareDemandBaselineForCity`（預設城市 0.75，香港 1.55、東京 1.45、倫敦 4.1、灣區 5.5 等） | `CompanyAccounts.fareBaseline`、`GameWorld.setFareBaseline(_:)`；GameCore 的新世界 0.75；App 的新遊戲是標準票價 $ 5 | 機制 faithful；遊戲城市的值是 gap |
| 編輯器的 `flatFare ?? 5`、`lineInfoFareDefaultDistanceBands`（為預設城市寫的 0.55–1.20） | `FareRules.standardFare`、`FareRules.standardBands(for:)`：× 基準 ÷ 0.75，取到 0.05 | 機械換算 |
| `stationFlowCustomEditingAllowed`：只有自由模式能改運量 | `GameSession.canEditStationDemand`；車站面板在經營模式唯讀 | faithful（App 層，和參考一樣在畫面層） |
| 經營模式的運量來自真實城市的資料（`useGlobalODModel`） | `StationDemand.cityDefault`（住宅區每天 10,000 人次） | gap（遊戲還沒有城市，Phase 5） |
| `MetroSaveModePolicy`、`metroSaveModeError`：自由模式的存檔只能在自由模式讀 | `GameSession.setEconomyMode` 只能從經營切到自由 | faithful（App 層） |
| `metro.cars` 配額（快照的備用價目 `metroQuotaPurchaseCatalogItems`：6 節 $ 60） | `ConstructionCosts.car`：`setTrainCars` 每加一節收費 | 部分 faithful：以現金計價，沒有配額 |
| 開局資金與建設價格（在引擎裡，快照沒有） | `GameWorld.startingBalance`、`ConstructionCosts.newGame` | gap：依回本天數訂（第 6 點） |

**1. 車站數**：營運的 `18·車站` 與人事的 `620·車站` 裡的車站是每條路線自己的停靠站，各算一次（同一條路線停兩次也算一次），再相加：兩條路線都停的站兩條路線各算一次，和參考一樣。

**2. 0 元的票價**：需求的影響把 0 以下的票價當成基準，是 1000‰（參考唯一的呼叫者這樣替換）。收費照舊：0 以下收 5 美元。

**3. 城市的基準票價**：
- 公司有 `fareBaseline`，需求的影響拿票價和它比（`demandFactor(fare:baseline:)`，表與公式不變）。`setFareBaseline(_:)` 接受 0.01 到 `FareRules.maximumFare`，其他拒絕（`invalidFareRules`），免費。
- GameCore 的新世界是 0.75（參考的預設城市），所以既有 golden 的預期值不變。
- App 的新遊戲把它設成標準票價 $ 5：沒有設定票價時每趟收 $ 5、需求不變；設定同樣的 $ 5 之後需求也不變。這是參考依城市換基準的做法，值是這個遊戲的城市的（gap），E2 的實景模式之後可以照參考的城市表設。
- 編輯器的距離票價依基準縮放（`standardBands(for:)`）：基準 $ 5 時是 $ 3.65／4.65／5.65／6.65／8.00。

**4. 車廂的價格**：`ConstructionCosts.car`，`setTrainCars` 每加一節收一次，減少不退；價格乘上節數會溢位時，視為比任何餘額都多（`insufficientFunds(required: Money.max)`）。價格是 0 時不扣款，餘額為負也照加（`spend` 會拒絕「0 元對負餘額」，所以只在價格大於 0 時才呼叫；決策 46 之前的經營存檔車廂不收費，而且很快就虧損）。檢查順序 `unknownTrain` → `invalidTrainLength` → `trainAlreadyPlaced` → `insufficientFunds`。

**5. 存檔**：`"accounts"` 的 `"fareBaseline"` 只在不是 0.75 時寫，`"costs"` 的 `"car"` 只在不是 0 時寫；沒有的時候讀成 0.75 與 0，所以舊存檔、golden 與 `SaveFixtures/` 照舊讀取、行為不變，不需要提高存檔版本。讀檔拒絕 0 以下或超過上限的基準、負的車廂價格。

**6. 新遊戲的價格與資金**（gap，Claude Code 訂）：
- 量測：照標準票價與城市的運量，0.45 到 12 公里、3 到 9 站、一列車的線，扣掉營運成本後每站每天約賺 $ 30,000–40,000（收入是每站每天 10,000 人次 × $ 5，主要成本是每次離站 $ 75）。
- 目標：合理的第一條線約 10 個遊戲日回本（一般速度約 24 分鐘）。
- 價格：地面軌道每公里 $ 100,000（每格 $ 1,600；高架 ×3、橋 ×4、隧道 ×5，照 S4 的倍數），車站 $ 200,000，列車 $ 150,000（含第一節），每加一節 $ 40,000；開局 $ 3,000,000。
- 結果：三站、28 格地面軌道、一列 4 節車的第一條線花 $ 914,800，約 10 天回本；示範地圖花 $ 1,680,800，剩 $ 1,319,200；6 公里五站的線約 11 天、12 公里九站約 9 天、6 公里高架約 18 天。多放列車會多出離站的成本，運量沒有多到要它時會減少利潤。
- GameCore 自己的世界與測試仍用 `ConstructionCosts.standard`（不變）。

**7. 經營模式的運量**（App）：
- 經營模式下不能修改車站的運量（車站面板唯讀，修改的指令回報原因），複製仍然可以。
- 路網工具在經營模式下建的新車站，同一個操作裡拿到 `StationDemand.cityDefault`；打開一局經營模式的遊戲時，沒有運量的車站也拿到它（決策 46 之前的存檔可能有這樣的車站）。
- 經濟面板只能從經營切到自由（先確認），自由模式不能再切回經營。自由模式沒有收入，蓋東西仍然要花餘額，所以餘額為負的公司不能切（`GameSession.setEconomyMode` 拒絕並說明）：切過去就什麼都蓋不了，而且不能反悔。自由模式的建設是否該免費是另一個決定，會改變 golden，這裡沒有動。
- GameCore 照舊允許任何時候設定運量與兩個方向的模式：這是 App 的規則，和參考一樣在畫面層；示範地圖由指令直接設定它的運量。

**刻意保留的差異**（之後再處理）：
- 列車數：參考只算路線本身的列車數，這裡連區間車也算，比較完整。
- 每節的容量：決策 35 的 320 人取自參考的新加坡車型資料；參考新線的預設是 B 型每節 260 人、6 節。改它會動到上下車的 golden 與 campaign，另外處理。
- 車站的候車上限：參考是路線容量 × 8，這裡固定 4,000 人。
- 決策 46 之前的經營模式存檔保留 0.75 的基準：在那些存檔裡儲存票價仍會讓乘客大減；開新遊戲即可。

#### 實作

- GameCore：`Economy/Operations.swift`（每條路線的車站、`setFareBaseline`、讀檔檢查）、`Economy/Fares.swift`（`demandFactor(fare:baseline:)`、0 元、`standardFare`、`standardBands(for:)`）、`Economy/Accounts.swift`（`fareBaseline` 與存檔）、`Economy/GameEconomy.swift`（`ConstructionCosts.car` 與存檔）、`World/GameWorld.swift`（`setTrainCars` 收費）。
- GamePresentation：`NewGame.swift`（`startingBalance`、`ConstructionCosts.newGame`、新遊戲的基準）、`StationDemandText.swift`（`cityDefault`、`canEditStationDemand`、修改前的檢查、打開遊戲時的城市運量）、`NetworkSession.swift`（新車站的城市運量）、`GameSession.swift`（單向的模式、加節回報花費）。
- App：`StationPanel`（經營模式唯讀）、`EconomyPanel`（單向切換與確認、依基準的距離票價），新字串附繁體中文。

#### 驗證

- 手算：`EconomyAccountsTests`（兩條路線共用的站各算一次：24 小時 × 18 × 4 站與 620 × 4；0 元與 1 美分的需求；基準 $ 5 時 $ 5 是 1000‰、$ 10 是 487‰、$ 0.75 是 1068‰；拒絕的基準不改任何東西；依基準縮放的距離票價；存檔往返與兩種壞掉的基準）、`CarPriceTests`（加三節收三次、減少不退、再加再收、餘額不足與溢位不改任何東西、存檔不寫 0、舊存檔讀成 0、負的價格拒絕）、`NewGameBalanceTests`（第一條線 $ 914,800、7 到 14 天回本；示範地圖花 $ 1,680,800）、`StationDemandSessionTests`、`FreeStationSessionTests`、`EconomyDisplayTests`（經營模式的運量、單向的模式）。
- `ReferenceWorld` 另外寫一次：每條路線的停靠站排序後去掉重複再相加、基準的指令與檢查、加節的收費。`economy.differential` 每個 case 隨機給車廂價格（0 到超過餘額），途中設定合法與不合法的基準：digest 從 `main` 的 `26F551283DD6DD20` 變成 `5F83C6BC399CC681`（只改車站數與 0 元時是 `39A6E1D1B6F6C6DD`，量不變）；量：設定的基準 106、拒絕的 17、付了錢的加節 32、餘額不足的 14。
- golden 的預期值與 `SaveFixtures/` 都沒有改變。

### 47. 教學的步驟與完成條件（Stage C5）

2026-10-03。教學只是 GamePresentation 與 App 的畫面狀態：不存檔，GameCore 不知道它，沒有修改 GameCore、golden 與存檔。介面（`Tutorial`、`TutorialStep`、`TutorialGoal`、`TutorialTarget`）在第 0 步定下（[UI_INTERFACES](UI_INTERFACES.md)），C5 只換成真正的步驟、增加完成條件。

**參考**（2026-10-03 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-c5最小教學)）：`Ci/` 的 `TUTORIAL_STEPS` 有 12 步；`Railway/site_archive_clean/` 與 `Railway/railway_game_reference_clean/` 沒有教學。

**1. 步驟**：`Tutorial.standardSteps` 十步，照一條線從無到有的順序：路網工具、鋪設軌道、第一座車站、第二座車站、建立路線、購買並放置列車、開始營運、乘客（運量）、控制時間、結束。參考的內容步驟（0、1、4、7、10、11）改寫成觸控與這個 App 的工具；滑鼠與鍵盤快捷鍵步驟（2、3、5、6、8、9）沒有觸控的對應，不移植。參考沒有「購買並放置列車」與「乘客」：它的路線自帶列車，運量在建線畫面裡。

**2. 完成條件由世界與 session 的現在推導**，不另外記錄（第 0 步的規則）。要求「蓋了什麼」的條件（`buildTrack`、`buildStation`、`createLine`、`placeTrain`、`startService`）比較的是**這一步第一次出現時**的世界：已經有軌道、車站、路線、列車的遊戲（示範地圖，或從選單重開）也要把每一步做一次。快照是每一步第一次出現時記下的 ID 集合與速度；回到上一步沿用第一次的快照，所以做完的步驟維持做完。`changeSpeed` 比較速度（含暫停）：改回原來的速度就又變成沒做完，和 `chooseTool` 一致。
- `startService` 要兩件事都成立：新指派給路線的列車，而且那條路線（或它的區間車）設了要跑的列車數；新路線的列車數預設是 0，所以只指派不會發車。

**3. 畫面沒有改**：覆蓋層是通用的（第 0 步）。步驟只框主畫面的控制項（路網工具與模式、地圖、動作按鈕、列車工具、路線按鈕、速度、遊戲選單）；路線面板與車站面板是 sheet，preference 不會離開 sheet，所以步驟 5、7 只框「路線」按鈕，面板裡的操作用文字說明，沒有框。

**4. 沒有的**（留給之後）：~~縮放與平移的步驟（E1）~~（決策 48 已加入）、實景模式的步驟（E2）、參考的「看過就不再自動開啟」（`metrobuilder_tutorial_done`）、步驟自動打開面板（`openUI`）、sheet 裡的框。

### 48. 大地圖：稀疏的地圖與存檔版本 2、相機的開局與縮放（Stage E1）

2026-10-03。新遊戲的地圖從 32 × 24 格放大到 1024 × 1024 格（`GridMap.maximumSideLength`，每格 16 公尺，約 16 公里見方），要能蓋幾公里長的線、看得出 W2c 的加減速。大地圖的繪製（只畫畫面內、依縮放分級、雙指縮放與平移）由 CX-4 照第 0 步的相機介面做好（PR #69–#71）；E1 剩下 GameCore 的存檔、新遊戲與示範地圖、相機的開局與縮放步長、教學的一步。

**參考**（2026-10-03 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-e1大地圖)）：

- 地圖大小：`Ci/` 的虛構海島城市是 25 × 40 公里（`virtual_island_city` 的圖例）；`Railway/site_archive_clean/` 是整個台灣（`TW_BOX`）。16 公里在兩者之間，而且是 `GridMap` 的上限。
- 縮放按鈕：兩份網頁參考都是 MapLibre／高德的一個縮放等級（`zoomIn()`，比例 × 2）；沒有鍵盤的 +／−。
- 開局的相機：`Ci/` 讀入存檔後 `fitBounds` 到所有車站（`fitAnycityImportedSaveNetworkView`，padding 72，`maxZoom: 12`）；`Railway/` 的 `fitData` 也是 `fitBounds` 到車站（padding 30）。兩者都不把相機存進存檔（`Ci/` 另外在 localStorage 記每個城市上次的位置）。
- 教學：三份都沒有縮放或平移的步驟；`Ci/` 只在說明畫面寫了「缩放地图：滚动鼠标滚轮以放大或缩小地图」（`guide.metro.shortcut.1`）與飛行模式的「移动地图」（W／A／S／D）。
- 參考包（`Railway/railway_game_reference_clean/`）只有 `touch_pinch_zoom.js`（兩指距離每變 5% 送一格滾輪，CX-4 已對照）與 `src/viewport.cpp` 的檔名，沒有相機的數值。

**1. 量測**（Linux、debug build，改之前）：1024 × 1024 的空地圖存檔 13.6 MB（每格一個 `{"empty":{}}`，pretty print 是 58.7 MB），編碼 3.6 秒、讀取 4.5 秒；讀檔時的不變量檢查與 `GridMap` 本身（每格 16 位元組）也各是一百多萬格。自動存檔在離開前景時與每 15 分鐘執行，存檔清單也要讀每個檔案的檔頭（`JSONDecoder` 會剖析整份文件），所以這不能只改畫面。

**2. GameCore：`GridMap` 只存不是空地的格子**：內部從密集的陣列改成「row-major 索引 → `TileType`」的字典，永遠不存 `.empty`，所以相等的地圖有相等的內容。公開的介面不變：`tile(at:)`、`tiles`（每一格，照舊 row-major；大地圖上有一百多萬個，App 不用它）；新增 `occupiedTiles`（不是空地的格子，row-major）。F1 之後車站不佔格，新遊戲的地圖永遠是空的；舊存檔的方格車站與方格鐵軌照舊。`GridMap` 自己的 `Codable`（密集的 `tiles`）沒有改，存檔不用它。

**3. 存檔版本 2**：世界的 `"map"` 寫成 `{"width", "height", "occupied": [{"x", "y", "tile"}, ...]}`：只寫不是空地的格子，依 row-major 排序，每一格的 `tile` 和以前一樣（`{"station":{"id":…}}`、`{"track":{"connections":…}}`、turnout、crossing）。
- 讀檔兩種都接受：`occupied`，或版本 1 以前的 `tiles`（每一格）。兩個都有、都沒有，`occupied` 的格子在地圖外、重複或不照 row-major 順序、寫了空地，都拒絕；其餘的檢查（方格鐵軌沒有出口、turnout 不成立、車站與格子不一致）不變。
- `SavedGame.currentVersion` 從 1 提高到 2。版本 1 的世界不需要轉換的步驟（世界照樣讀得進密集的形式），但只讀得懂版本 1 的舊 build 遇到版本 2 的存檔，要說「這是較新版本的存檔」，而不是「存檔損壞」（`SaveLibrary` 的檔頭檢查）。
- 結果：新遊戲的存檔是幾百位元組（`SavedGameTests` 釘住 1024 × 1024 的地圖加一座方格車站小於 1,000 位元組），示範地圖跑 90 分鐘是 13.7 KB。
- `SaveFixtures/v2-demo-90-minutes.json`：這個 build 寫的版本 2（16 公里地圖中央的示範地圖，跑 90 分鐘）；`v1-demo-90-minutes.json` 沒有改，照舊讀得進來。
- 兩個釘住存檔位元組的測試（`RailwayNetworkAuthorityTests`、`TrainTimetableTests` 的「存回原樣」）改成：舊的密集 JSON 讀得進同一個世界，存回時是 `occupied` 的形式，每一格的內容位元組不變。存檔的變異 campaign 原本避開 `.map.tiles`，改成避開 `.map.occupied`。
- golden 與 property digest 都不變：GameCore 的規則沒有改，golden 不比較存檔的 JSON。

**4. GamePresentation**：
- `GameWorld.newGameMapSize` = `GridMap.maximumSideLength`，新遊戲 1024 × 1024。E1 之前的存檔照舊是 32 × 24。
- `DemoWorld` 搬到地圖中央（它的 32 × 24 格的西北角在第 (496, 500) 格），四周都能延伸；配置、運量與營運不變。
- 相機的開局：`PlanCamera(map:viewport:showing:)`，`showing` 是 `WorldRegion.built(in:)`（路網的節點、車站，以及舊存檔的方格鐵軌）。有東西時置中在它上面、縮小到它放得下而四周各留 `focusPadding`（30 點，`Railway/` 的 padding；`Ci/` 的 72 是桌面的螢幕）；但不比沒有它時的開局大小（`automaticSize`）更近，對應 `Ci/` 的 `maxZoom`。沒有東西時在地圖中央（原本是西北角）。手機打開示範地圖約每格 12 點，是概覽。
- 縮放按鈕：`MapScale.zoomStep`（每次 ± 8 點）改成 `zoomFactor`（× 2），照參考的一個縮放等級。手機上 16 公里的地圖整張放得下時每格不到 0.4 點，到最大的 64 點約 7 步；固定 8 點的步長一步就從 8 點跳到整張地圖。縮放範圍不變：最大每格 64 點，最小到整張地圖放得下。
- 教學的第三步 `map.move`（「移動與縮放地圖」，框 `map` 與 `map.zoom`）：參考沒有這一步（gap），文字照 `Ci/` 說明畫面的縮放與移動改成觸控。新的 `TutorialGoal.moveMap`：相機是地圖 view 的狀態，不在 session 裡，所以地圖 view 在玩家捏合、拖曳或按縮放按鈕時呼叫 `GameSession.mapDidMove()`；只有在等這個動作的那一步第一次呼叫時才改變 session（手勢的每一幀都呼叫也只觸發一次畫面更新）。旋轉裝置、改變大小、選到遠方的車站時自動置中都不算。回到上一步沿用，和決策 47 的快照一樣。
**5. App**：`MapView` 用 `showing` 開局，手勢與縮放按鈕呼叫 `mapDidMove()`；iPad 直向的地圖 view 固定 4:3（`ContentView`；原本跟著地圖的長寬比，正方形的大地圖會吃掉控制項的空間）。
- 教學的標記 `tutorialTarget(_:)` 改成和裡面的標記合併（`transformAnchorPreference`）：原本的 `anchorPreference` 會取代子 view 回報的值，`ContentView` 給整個地圖的 `map` 蓋掉了地圖裡縮放按鈕的 `map.zoom`。第 0 步以來沒有步驟用到 `map.zoom`，直到地圖這一步的 UI 測試在 iPhone 上發現卡片蓋住縮放按鈕（卡片不知道它們在那裡）。UI 測試：教學的「鋪了軌道之後」改成先按放大鍵通過地圖這一步；縮放按鈕的測試改成一次就到最大（32 → 64 點）。

**效能**：模擬不因地圖變大而變慢。GameCore 不掃描整張地圖（只查個別的格子，例如方格車站）；路網的求路只走訪可達的軌道（決策 16、31），成本跟著蓋了多少軌道，不跟地圖大小；`GridMap` 的大小只決定邊界。繪製只畫畫面內的東西（CX-4）。實機的繪製效能沒有在 Linux 驗證（TestFlight）。

**已知限制與留給之後**：
- 相機不存檔，每次打開遊戲都對準已建的部分（參考也不存；`Ci/` 的「上次的位置」之後可以加在畫面層）。
- 車站與節點的觸控查找還是逐一比對（`NetworkBuilding`），幾千個節點以內不成問題；更大時再加空間索引。
- 方格的 GameCore 相容層仍然以 1024 為上限（F3 另議）。

### 49. 環線（作者 2026-10-03 要求）

2026-10-03。作者在示範地圖上測試，發現環狀的軌道跑不成環線：決策 22 的路線一律在兩端折返，環狀的軌道只能「繞一圈再原路折返」。這一版照 `Ci/` 的 `isRing` 移植環線，示範地圖改成有環線、一站多月台的配置，排在 E2 之前。

**參考**（2026-10-03 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#環線)）：

- `Ci/`（`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`）：`completeRingLine` 把三站以上的路線設成環線（`e.isRing = true`），`metroSplitOpenRing` 在一站或一段把環線打開成一般路線。`normalizeRingPairedTrainCaps` 把每個等級的列車數變成不超過它的偶數（`metroRingPairedTrainCountAtOrBelow`：t − t mod 2）；`metroRingDirectionTrainCounts` 分成內環 ⌈t/2⌉、外環 ⌊t/2⌋；`metroRingDirectionalHeadways` 每個方向的班距是一圈 ÷ 該方向的列車數。`metroHeadwayRoundTripMinutes` 的環線分支：各段加上最後一站回第一站的那一段，再加上每一站一次 `DWELL_GAME_SEC`（36 秒），沒有端點的 `DWELL_TERMINAL_GAME_SEC`；最多列車數是 `(isRing ? 2 : 1) × floor(…)`。`metroBuildRingServiceTimeline` 依方向（1 或 −1）排一圈的各段，每段是行駛加 36 秒停站。`consolidateRingRouteLegs` 把環線的 route legs 合成一條涵蓋全線的（環線沒有區間車）；環線另有快車（`expressStops`、`calcLineHeadwayMinForRingExpress`）。上車：`metroCollectRawTargetsForBoarding` 讀環線車站兩個方向的佇列（`[n, -n]`）。
- `Railway/site_archive_clean/index.html`：真實路線的 `ln.loop`（例如環狀線）：`buildLineSchedule` 把環線排成依序的各站再回到第一站（一般路線是去程加回程），每站停 `DWELL_SEC`；`runBetween` 在環線上走較短的方向；環線沒有終點站名（`termName: null`）。`rail-3d.js` 也把最後一站回第 0 站當成真的一段軌道。
- 參考包（`Railway/railway_game_reference_clean/`）：沒有環線。

**1. 資料**：`ServiceLine.isRing` 與 `outerLastDispatch`（外環方向上次派車的時刻；`lastDispatch` 在環線上是內環方向的）。`setLineRing(_:to:)` 免費，檢查順序 `unknownLine` → 設成環線時少於三站或第一站與最後一站相同是 `invalidLineStops` → 有服務模式是 `invalidLinePattern`（參考的環線只有一條涵蓋全線的服務；環線快車沒有移植）。設成環線時各等級的列車數變成偶數（無條件捨去，`normalizeRingPairedTrainCaps`）；設回一般路線時忘掉 `outerLastDispatch`，列車數不變（`metroSplitOpenRing` 也不改列車數）。已經派出的列車照原本的時刻表跑完。環線上 `setLineStops` 也要符合環線的條件，`addLinePattern` 一律拒絕，`setLineTrainsInService` 存成偶數。

**2. 方向**：列車依 ID 遞增輪流分到兩個方向：第 1、3、5…台走內環（依 `stops` 的順序），其餘走外環（反過來）；拿掉一台時，它後面的列車跟著換方向（`ringDirection(of:)`）。參考是每個方向各有一組列車；我們的列車屬於路線而不是方向，所以用順序決定，不另存。

**3. 一圈與規劃**：`lineJourney` 是內環方向的一圈：起點的試法和一般路線相同，依序到每一站，最後一段回到第一站，從不折返（`LineJourney.isRing`）；秒數是各段加上每一站 `dwellMinutes`（1 分鐘），沒有端點的 2 分鐘。每個方向當成一條以一圈為來回時間的路線：最多列車數 2 × max(1, ⌊一圈 ÷ 2⌋)，每個方向的列車數是該等級的一半（有目標班距時是 ⌈一圈 ÷ 目標⌉），班距是每個方向的；`lineTrainsInService` 是兩個方向的合計。區段有 `stops` 段（最後一段是最後一站回第一站），每一段的負載是 `⌈1440 ÷ 班距⌉`（每個方向各自的量，不超過 720）。

**4. 派車**：每個方向各自派車（`DispatchStream`），內環先：該方向的列車從第一站派出，班距從該方向自己的上次派車算起，執行服務的該方向列車少於列車數的一半時才派。時刻表：派車那一刻到達第一站，36 秒後離開（`ServiceDwell.minimum`；先折返時 42 秒），之後每一站是一段的秒數加上停 1 分鐘，最後回到第一站結束；只有先折返時第一站的 `reverses` 是 `true`。列車跑完一圈停在第一站，面向它繞過來的方向，等下一次派車。這和一般路線的派車是同一個模型；參考讓列車沿著一圈的時間相位連續繞行（`applyRingTrainTimePhase`），這裡沒有移植。

**5. 停站與乘客**：環線列車的第一站與最後一站不是端點，最少停 36 秒（參考在每一站都是 `DWELL_GAME_SEC`）；折返的站仍是 42 秒。上車時環線列車接走該路線兩個方向排隊的乘客，只要目的地在這一圈結束之前會停靠（參考讀兩個方向的佇列）；刻意的差異：乘客不坐過第一站，所以一圈結束時車上沒有人被丟下。

**6. 驗證與格式**：
- golden schema 27：`setLineRing` 指令，路線的 `ring`（只寫 `true`）與 `outerLastDispatch`（只在環線上，必填），環線行程的 `"ring": true`，以及手算的 `ring-line.json`；既有的二十六個 fixture 只改 `schemaVersion`。
- 差分模型（`ReferenceWorld`）另外實作同樣的規則（每個方向的名冊、一圈的各段、規劃、時刻表、停站與上車），golden 也在它上面跑；路線與派車的 campaign 抽 `setLineRing`。
- **存檔版本 3**：路線的 `"ring": true` 與 `"outerLastDispatch"`。只讀得懂版本 2 的 build 會把環線當成兩端折返的路線，所以改成說「較新版本的存檔」；版本 2 的世界沒有環線，不需要轉換。`SaveFixtures/v3-demo-90-minutes.json` 是這個 build 寫的。讀檔拒絕：環線少於三站、第一站與最後一站相同、有服務模式、列車數是奇數、寫了 `"ring": false`、不是環線卻有 `outerLastDispatch`、外環的派車晚於現在。

**7. 示範地圖**：Central 在地圖正中央，Line 1（地面，東西向）與 Line 2（高架 8 公尺，南北向）各 18 格長、在 Central 上下交會；環狀線繞 Central 一圈，經過西、北、東、南四站，內外兩圈軌道（半徑 12 與 13 格，各四段三次曲線，互不相接），內圈給內環方向、外圈給外環方向，所以兩個方向不會在單線上對撞（交通控制下會卡死）。西站與東站各有三個月台（Line 1 與兩圈），北站與南站也是三個（高架的 Line 2 在上、兩圈在下），Central 兩個。Line 1、2 各一列四節車，環狀線兩列兩節車（每個方向一列）。建造花 $ 2,291,200，剩 $ 708,800，夠教學在旁邊蓋第一條線（兩站與一列車）；E1 之前的大小（半徑 20 格、四節車）會剩不到教學需要的錢。

**8. 畫面**：路線面板有「環線」開關（`GameSession.setSelectedLineRing(_:)`）；環線的列車數每次加減 2、不顯示加入區間車，服務顯示「環線」、一圈的各站與每個方向的列車數和班距，行程顯示「一圈」。環線的涵蓋是全有或全無：沒有列車的等級顯示「沒有服務：整條環線」（之前沒有環線，這個檢查會在環線上超出最後一站）。

**已知限制與留給之後**：
- 環線快車（參考的 `expressStops`）與環線上的服務模式。
- 列車沿一圈連續繞行（參考的時間相位）；現在每圈都從第一站派出。
- 乘客走較短的方向（`runBetween`）；現在乘客搭哪個方向都可以，只要這一圈會到。
- 指定月台（Stage V）：一站多月台時，列車停在路線經過的第一個合適的月台。

### 50. 實景地圖：地理錨點、存檔版本 4、跟著遊戲相機的 Apple 地圖（Stage E2）

2026-10-03。遊戲分成空白與實景兩種地圖（作者 2026-10-02 的決定）：實景的新遊戲選一個真實的地點，16 公里的地圖中心放在那裡，Apple 地圖畫在鐵路下面。作者這次決定照路線圖先用 MapKit，MapLibre 留給 E3。

**參考**（2026-10-03 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-e2實景地圖)）：

- `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`：兩套地圖引擎，`osm` 是 MapLibre 加 OpenFreeMap 的向量圖磚（`initOsmMapEngine`，樣式 `positron`、`liberty`、`dark`、`fiord`、`satellite`），`amap` 是高德的 JS API 2.0（`initAMap`）。`getMapEnginePolicy` 只在「中國的 IP、中國大陸的城市」用高德，其他一律 MapLibre；載入失敗時換另一套，玩家可以設預設。遊戲的座標是經緯度，中國大陸是 GCJ-02，給 MapLibre 時換成 WGS-84（`gameGcjToOsmWgs`）。開局的城市是 `CITIES`（53 座，`center`、`zoom`、人口與行政區），「任意城市」由伺服器的 manifest 給中心或範圍（`startGameAnyCity`、`registerAnycityFromManifest`；選點的 `anycity-ui.js`、`anycity-bbox-map.js` 不在快照裡）；虛構海島城市是 `lng: 0, lat: 0`。地圖的標示「OpenFreeMap © OpenMapTiles © OpenStreetMap」。
- `Railway/site_archive_clean/index.html`：只用 MapLibre GL v5.9.0（自己打包在 `vendor/`，預設樣式 `vendor/ofm-positron.json`），CARTO 的點陣圖磚備援，衛星是要 token 的 Esri World Imagery；沒有網路時底圖是純色（`offline-land`）。`data/tra.json` 是 OpenStreetMap 的台鐵車站（七位小數）。
- `Railway/railway_game_reference_clean/`：沒有地圖。

**Apple 的條款**（Apple Developer Program License Agreement，2026-10-03 從 Apple 網站的 PDF 讀；MapKit 照 §3.3 受 Attachment 6 約束）：
- Attachment 6 §2.1：不能移除、遮住或改動 Apple 與合作者的標誌、法律聲明與連結；§4 舉例「遮住或移除 Apple 地圖的標誌或內嵌的連結」可以被撤銷使用權。
- §2.4、§2.5：地圖資料（明列包含經緯度）只能和 Apple 地圖一起顯示，除了暫時、為了使用服務所必需之外不能快取、預先抓取或儲存。
- §2.2、§2.3：不能大量下載、不能拿來做衍生資料庫或另一個地圖服務；§2.6 不能單獨為地圖收費；§2.7 Apple 可以限制用量。
- 主約的 §3.3（iii）：疊在 Apple 地圖上的自己的資料（例如路線），由開發者負責對齊。
- 所以：地點清單用參考自己的資料；搜尋結果（名字、地址、座標）只在選點的畫面上和地圖一起顯示，不存；存檔只存玩家停下來的地圖中心；Apple 的標誌與法律聲明放在一條不被遊戲蓋住的帶子裡；鐵路與地圖用 MapKit 自己的換算對齊。

**1. GameCore：`GeoAnchor`**：地圖中心的緯度與經度，整數的千萬分之一度（約 1 公分）：緯度 ±90°、經度 −180° 到 180°（不含 180°，東經 180° 寫成西經 180°）；超出的 `GeoAnchor(latitude:longitude:)` 是 `nil`，讀檔拒絕。`GameWorld.geoAnchor`（新的世界是 `nil`，空白地圖）與 `setGeoAnchor(_:)`（免費，只改錨點）。**沒有規則讀它**：世界照舊是整數的世界座標，GameCore 不知道地圖在哪裡、也沒有浮點數；同一個世界加不加錨點，模擬完全相同（`GeoAnchorTests`）。錨點不是 golden 的指令（golden 釘的是規則），差分模型與 property digest 都不變。存檔的 `"geoAnchor": {"latitude", "longitude"}` 只寫在實景地圖上，明寫的 `null` 拒絕。

**2. 存檔版本 4**：只讀得懂版本 3 的 build 會丟掉錨點，下一次存檔就把實景的遊戲變成空白的，所以改成說「較新版本的存檔」；版本 3 的世界是空白地圖，不需要轉換。`SaveFixtures/v4-real-world-demo-90-minutes.json` 是這個 build 寫的：示範地圖放在台北車站（`Railway/` 的 `tra.json`），跑 90 分鐘，除了版本與錨點之外和版本 3 的存檔位元組相同。存檔清單的摘要多一個 `"realWorld": true`（只在實景地圖），顯示「實景地圖 · …」；之前的摘要沒有這個鍵，讀成空白地圖。

**3. GamePresentation**：
- `RealWorldFrame`：地圖中心在錨點，x 東、y 南，一個世界單位 1/64 公尺。底下的地圖是 Web Mercator（Apple 地圖，參考的 MapLibre 與高德也是）：App 把世界的一公尺畫成錨點緯度上的一公尺，整張地圖都用這個比例，所以鐵路和地圖處處對齊；離錨點的緯度越遠，世界的一公尺和地面的一公尺差一點（Mercator 的比例隨緯度變），16 公里的地圖在台北的緯度最多 0.06%，60° 是 0.22%。
- `GeoAnchor(latitudeDegrees:longitudeDegrees:)`：四捨五入到千萬分之一度，經度轉回 −180° 到 180°（地圖繞過地球時會回報 190°）。
- `RealWorldPlace`：64 個地點，`Railway/` 的 11 個台鐵主要車站（台灣，每個站名第一次出現的點）與 `Ci/` 的 53 座城市（`center`，名字改成台灣用語的繁體），依地區分組；座標和兩份參考逐一比對過，完全相同。預設是臺北車站。
- `GameWorld.newGame(anchor:)`、`GameLauncher.startNewGame(at:)`：實景的新遊戲就是放在地球上的新遊戲，資金、價格、城市都一樣。

**4. App**：
- 開始畫面多一個「實景地圖」，打開選點的畫面（`RealWorldPicker`）：上面是 Apple 地圖，畫出 16 公里的方框與中心的十字；下面是地點清單與搜尋（`MKLocalSearch`，按下搜尋才查）。點清單或搜尋結果把地圖移過去，玩家可以再拖，按「在這裡建造」時地圖中心就是錨點。
- 遊戲的地圖（`MapView`）在實景時：底下是 `AppleMapBackground`（`MKMapView`，平面、北朝上，自己的手勢全部關掉），遊戲的 canvas 不填土地的顏色、只畫地圖的邊界；地圖 view 底部 30 點是標示的帶子，遊戲的畫面與手勢不蓋它，Apple 的標誌與「法律聲明」連結在那裡、可以點。左下角的按鈕選地圖的樣式（地圖、衛星（含標示）、衛星；是 App 的設定，不是遊戲的）。街道圖用 `.muted` 讓鐵路突出，對應參考預設的淺色 `positron`。
- 換算：`FollowingMapView.mapRect`：遊戲相機的左上與右下在世界的哪裡 → 離錨點幾公尺（`RealWorldFrame`）→ 乘上 `MKMapPointsPerMeterAtLatitude(錨點的緯度)`，加上錨點的 `MKMapPoint`，就是 `setVisibleMapRect` 的範圍。選點畫面的方框用同一個換算。

**5. 為什麼相機在我們這邊**：第 0 步原本設想實景時由 MapKit 的相機實作 `MapProjection`（手勢交給 MapKit，畫面用 `MapProxy` 逐點換算）。實作時改成反過來：遊戲的 `PlanCamera` 照舊決定看哪裡，Apple 地圖跟著它。理由：
- 手勢、縮放按鈕、地圖邊界、教學的「移動與縮放地圖」與既有的 UI 測試全部不變，空白與實景是同一套操作。
- 鐵路與地圖在同一次畫面更新裡由同一個相機決定，不會有疊在 MapKit 上的 SwiftUI 畫面常見的延遲一幀、拖曳時漂移。
- 地圖只能平面、北朝上；可以旋轉、傾斜的相機（MapKit 的 3D 建築與地形）留給之後，`MapProjection` 仍然支援它。
- 遊戲的最大縮放（每格 64 點，每公尺 4 點，約 MapKit 的第 19 級）在 MapKit 可以顯示的範圍內，所以地圖跟得上；實機沒有驗證。

**教學**：教學在空白的新遊戲上進行，模式在開始畫面就選了，所以沒有加步驟（第 0 步寫的「視需要」）。

**驗證**：GameCore 與 GamePresentation 在 Linux 上測試（`GeoAnchorTests`、`RealWorldMapTests`、`SavedGameTests` 的版本 4）。App 的程式只在 macOS 的 CI 編譯與測試（`ios-build.yml`；`RealWorldMapUITests` 在完整的那一輪：從清單選台北開局、換衛星、回開始畫面看到「實景地圖」、繼續仍是實景），地圖的圖磚要網路，測試不看圖磚。實機上地圖與鐵路是否對齊、拖曳時是否跟得上，要 TestFlight。

**已知限制與留給之後**：
- 地圖不能旋轉、傾斜，沒有 3D 建築與地形高度（Phase 8 前可以先用 MapKit 的）。
- 沒有 GCJ-02 的換算：錨點是 MapKit 給的座標。中國大陸的存檔之後換到 MapLibre（E3）可能偏約 500 公尺，那時照 `Ci/` 的 `gameGcjToOsmWgs` 處理。
- 沒有網路時 MapKit 只畫它自己的空白格，沒有另外的提示（`Railway/` 是純色底圖）；搜尋也需要網路。
- 錨點只記點，不記地名；參考依城市設定的票價基準（`metroFareDemandBaselineForCity`）、城市的人口與起訖需求（Phase 5、6）沒有接上。
- 已經開始的遊戲不能換錨點（GameCore 允許，畫面沒有）。

**台灣的真實鐵道**（2026-10-05 追加，作者要求從私有 repo 直接移植；對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#實景地圖的台灣鐵道與車站)）：
- `Railway/` 網站的 `track_lines.geojson`、`track_stations.geojson` 與 `i18n/stations.json` 原檔放在 App 的 `Resources/RealRailways/`（約 940 KB）。GamePresentation 的 `RealRailways` 讀它們（Foundation 的 `JSONDecoder`，Linux 上用 repo 裡的同一份檔案測試）；App 啟動時在背景讀一次（`GameLauncher.loadRealWorldData`，與人口、地點格一起；讀好前開始畫面的實景按鈕停用）。
- 實景的遊戲地圖：`FollowingMapView` 把錨點 16 公里內的路線畫成 MapKit 的 overlay，照網站的寬度與疊放順序（顏色一律用官方色、不自製，也不用網站的代表色（2026-10-05 作者要求）：台鐵、高鐵與阿里山林鐵沒有路線色，整個系統統一用公司色（台鐵藍 `#005792`、高鐵橘 `#DB5009`、林鐵紅 `#C41229`）；捷運與輕軌每條線用營運機構官網宣告的路線色，官網沒有的用交通部 TDX 的 `LineColor`；找不到官方色的線不載入（`LoadError.noOfficialColor`）；深色、淡化與隱藏照網站的 `railMix` 混出），放在 `.aboveRoads`（道路之上、地圖的標籤之下，和網站在 MapLibre 的位置相同）；車站是 `StationDotsRenderer` 畫的固定大小的圓，網站的第 11 級以上才畫。地圖樣式選單多一個「真實鐵道」（自動、淡化、隱藏，App 的設定，預設淡化），以及「資料來源」。
- 選點的畫面：地圖畫出全部路線；清單在台灣之後依系統列出 544 個車站，輸入時照網站的比對方式即時列出符合的車站。
- 標示：交通部 TDX 依政府資料開放授權條款第 1 版，OpenStreetMap 依 ODbL 1.0。畫了真實鐵道的地圖在底部帶子的中間顯示短標示（Apple 的標誌在左、法律聲明在右，標示最多佔帶子寬度的 45%）；完整的來源與授權在 `DataSourcesView`（開始畫面、地圖樣式選單）。ODbL 的衍生資料庫（兩個 GeoJSON）在公開的 repo 依同一授權提供。
- 都只是畫面：GameCore 不知道真實鐵道，存檔不存它，玩家的鐵路照舊自己蓋；golden、存檔版本與 property digest 都沒有改。

**實景示範地圖**（2026-10-05 追加，作者要求；對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#實景示範地圖)）：
- 開始畫面的「實景示範地圖」：錨點在瑞芳、三貂嶺與菁桐之間，平溪線（三貂嶺–菁桐）、宜蘭線（四腳亭–三貂嶺）與深澳線（瑞芳–八斗子）照真實路線蓋成遊戲的軌道，平溪線兩台、宜蘭線與深澳線各一台列車開局就在跑，用來在真實路線上測 V3 的交會、待避與共線。
- 和示範地圖一樣是 GamePresentation 用一般的 `GameWorld` 指令蓋（`RealWorldDemo`），照常付費；開局資金是新遊戲的加上先算好的建造費，蓋完剩下和新遊戲一樣。GameCore、golden、存檔都沒有改。
- 真實線形先平滑（每 5 m 取樣、前後 15 m 平均），再擬合成 cubic 的邊：節點兩側用同一個切線，所以每個節點都互通；擬合誤差 3 m，深澳線與宜蘭線並行的 1.3 km 內 1 m，守住 4 m 的線間距。
- 經緯度到世界的換算是 `RealWorldFrame.worldPosition(latitude:longitude:)`，和 `AppleMapBackground` 用的 MapKit map point 是同一個 Web Mercator，所以蓋出來的軌道疊在底下畫的真實鐵道上。
- 簡化：只有中心線一股，瑞芳、猴硐、三貂嶺、十分加 400 m 的待避線；真實的宜蘭線是雙線。運量是遊戲的數字，不是真實的運量。
- 建造的時間：Linux 的 release 約 0.4 秒、debug 約 8 秒，幾乎都在 GameCore 每段軌道的間距與交叉檢查（約 200 段）；實機沒有量。

### 51. 移除 GameCore 的方格（Stage F3）——計畫與作者的決定

2026-10-03。E2 合併、實機確認之後，作者決定**現在**做 F3，排在 F2、U-min、V 之前，並交給 Claude Code 選「對未來幫助最大、又不影響新功能」的做法。這一條記下範圍與步驟；每一步的細節在各自的 PR 補上。

**為什麼現在**：決策 28 起鐵路的權威是節點與邊（topology），方格只是同一個 graph 的另一個 adapter；F1 之後 App 只建路網，C4 的存檔又在 F1 之後，所以玩家的世界不會有方格。但方格的程式還在共用函式裡（移動、預約、停站、路徑、行程各有方格分支），大部分的 golden、property 與差分 campaign 也建在方格上。U-min 與 V 會大改的正是這些共用函式；方格留著，每一次都要同時顧兩種軌道、讓兩套測試都通過。

**盤點**（`docs/research/F3_GRID_INVENTORY.md`，Codex，PR #82；Claude Code 另做一份獨立的盤點，兩份一致，差異已併入下面）：GameCore 約 1,600 行方格程式（9 個只給方格的型別或檔案，加上約 15 個共用函式的方格分支）；27 份 golden 有 25 份依賴方格；約 40 個 property／差分 campaign 與 11 個存檔變異 campaign 的世界產生器是方格；差分模型約 880 行方格。`SaveFixtures/` 的四份存檔都沒有方格內容。

**作者的決定**（2026-10-03）：
1. 完整移除，不只凍結。
2. 不改任何遊戲行為：票價照舊以點車站底下那一格算距離（`squaredDistance`，`Station.position`），換成精確的點距離要另外決定；一格 1024 單位（車長、建造費、座標）的數值不變。
3. 手做、含方格內容的舊存檔在 F3c 之後拒絕並說明原因；App 寫過的存檔都不受影響（存檔在 C4 才有，那時 App 已經沒有方格工具）。
4. golden 的遷移照下面的規則，預期值的每一個變化在 PR 裡說明。

**保留的**（名字裡有「格」，但不是方格鐵路）：`GridMap` 的大小與邊界（新遊戲 1024 × 1024、E2 的地圖中心）、`GridPosition`（越界錯誤、點車站底下的格）、一格 1024 單位（`TrainPosition.linkLength`、`WorldCoordinate.tileSize`、`Train.carLength`、`edgeCost`）、存檔裡 `movement` 的 `"continuation": []`（每份存檔都有，讀檔要繼續接受）。改名另外處理，不和刪除混在一起。放列車時選的東南西北（GamePresentation 的 `placementHeading`）在 F3c 換成路網的說法。

**三步，每步一個或幾個 PR**：
- **F3a — golden 搬到路網，GameCore 不動**。新舊實作與差分模型同時通過，證明每條規則在路網上都測得到。
  - 只為了路網月台或車站 ID 才建方格車站的 4 份（`network-service`、`traffic-reservation`、`vertical-railway`、`station-demand`）：改成那一格中心的點車站（1024x + 512, 1024y + 512）。底下的格相同，所以費用、票價與其他預期值都不變，只有最終狀態的車站寫法從 `{x, y, annexes}` 變成 `{point}`。
  - 規則和軌道種類無關、只是蓋在方格上的 12 份（`boarding`、`clock-seconds`、`economy`、`line-dispatch`、`line-patterns`、`ring-line`、`service-line`、`service-run`、`station-dwell`、`train-repeat`、`train-service`、`train-timetable`）：在路網上重寫，盡量讓距離、秒數與時刻相同；建造費（方格每格收一次、路網依邊長進位）、位置的寫法、ID、路網的轉彎要用曲線這些一定會變的值逐一說明。
  - 只有一部分能搬的 6 份（`build-starter-line`、`free-station`、`station-facilities`、`station-stop`、`train-movement`、`train-route`）與只屬於方格的 3 份（`track-connectivity`、`track-resources`、`train-position`）：能在路網表達的規則寫成路網的 golden，路網上缺的對應規則補新的 golden；方格的原檔留到 F3c 和方格程式一起刪。方格才有的契約（格的出口與相接、相鄰擴站、格月台、北東南西的平手順序、拆掉再重建同一格會接著走、格的 offset 範圍）不搬。
- **F3b — 測試搬到路網，GameCore 不動**：路網的世界產生器、campaign、存檔變異 campaign 與差分模型改成路網；方格的單元測試留到 F3c。產生器改了 digest 就會變，新的 digest 記在文件裡，不當成「行為沒變」。
- **F3c — 刪掉方格**：GameCore 的方格型別、case、指令、錯誤、方格分支與存檔的方格格式；GamePresentation 的方格工具、方格選取與文字；App 的方格繪圖與「選取北邊的格子」這類 VoiceOver 動作；golden schema 28 拿掉方格的指令、觀察與寫法；`Web/WasmProbe`。
  - **F3c-1**（刪除之前）：只有方格版的兩個唯讀查詢先有路網版，刪方格時功能不跟著消失。區段 `networkSections()`（`NetworkSection`）移植參考 `topology.js` 的 `trackGroups`：在分歧點切開的邊鏈；分歧點是不是正好兩條邊相接的節點（轉轍器、交叉、盡頭、兩條邊不相接的節點），沒有分歧點的環另列。單雙線 `parallelTracks` 沿用 S1 的定義（不共用軌道的路徑數），路網上一段軌道是一條邊、在兩站的月台處切開，路徑只在相接的邊之間轉換，可以折返。兩者都是唯讀查詢，沒有規則讀它們，所以遊戲行為不變；改變的是路網世界的查詢結果（原本沒有區段、一律 0 線）與路線面板的文字。參考 `tra_track_sections.json` 的「平行比例 ≥ 0.5 算雙線」沒有移植：產生器不在 repo，「平行」的定義是缺口；參考唯一的使用者是交會推估（`inferMeetPassTimes` 的 `single(a,b)`），留到 V。
  - **F3c-2**（GameCore 不動）：GamePresentation 與 App 不再呼叫方格的鐵軌、車站與列車位置。方格工具（F1 起 App 已不提供）、`GameSession` 的軌道形狀與擴站、方格的放置與送車、方格選取（`selectedTrack`、`moveSelection`、佔格車站優先）、方格文字與繪圖、地圖上「選取北邊的格子」等 VoiceOver 動作拿掉。列車只放在選取車站的路網月台、只送到選取的車站。放置方向改成 GamePresentation 的 `CompassHeading`，畫面一樣是北東南西。`selection` 仍是點到的那一格土地。剩下的只有對 GameCore 列舉的完整 switch（方格位置、節點、連結的文字與方格錯誤訊息），F3c-3 和 GameCore 的 case 一起刪。
  - **F3c-3**：先在路網上補測只有方格測試測到的規則（F3c-3a），再刪方格的測試與 fixture（F3c-3b），最後刪 GameCore 的方格（F3c-3c）。F3c-3c 刪掉 `Track`、`TrackDirection`、`TrackConnections`、`TrackLayout`、`TrackSection` 與方格的相接、出口、月台、選路、停站和移動；`TrackNodeID`、`TrackEdgeID`、`TrainPosition`、`TrackResource` 只剩路網的 case（名字照舊，改名另外處理）；`Station` 只有點，`position` 是點底下的格（票價照舊用它）；`Train` 沒有 `trail`，`TrainMovement` 沒有 continuation；`GameWorld` 的方格指令（鋪軌、轉轍器、平交道、拆軌、佔格建站、擴站、方格的 continuation）、查詢與五個方格錯誤（`tileOccupied`、`invalidTrackConnections`、`noTrackToRemove`、`trackInUse`、`invalidStationTile`）；地圖只有空地，存檔的 `occupied` 一律是 `[]`。存檔格式對路網世界逐位元組不變：`movement` 照舊寫 `"continuation": []`，讀檔仍接受空的 `"continuation"` 與 `"trail"`。照第 3 點，手做的方格內容（地圖上的鐵軌或車站格、佔格或擴過的車站、在方格節點或連結上的列車、非空的方格車身或 continuation、方格的格或連結資源）讀檔時拒絕，錯誤訊息說明方格在 F3c 移除、只有手做的存檔才會有。golden 執行器、差分模型與 campaign 支援一起刪掉方格；fixture 仍是 schema 27（`tracks`、`trail`、`continuation` 只能是 `[]`，方格的指令與觀察拒絕並說明），所以每份 golden、存檔與重播 fixture、每個 campaign 的 digest 都不變。schema 28 與 `Web/WasmProbe` 是 F3c-4。
  - **F3c-4**：golden schema 28。fixture 拿掉只能是 `[]` 的三個方格鍵：最終狀態的 `tracks`、列車的 `trail` 與列車移動的 `continuation`；25 份 fixture 的其他內容逐一不變，只有版本從 27 改成 28。方格的指令、觀察、結果、位置與資源不屬於 schema 28，照舊拒絕並說明。`Web/WasmProbe` 照原樣複製執行器與 fixture，不用改。存檔格式不變：`movement` 照舊寫 `"continuation": []`（第 3 點，改名另外處理）。

**參考**（2026-10-03 唯讀檢查三份，私有 repo `1563ad0`）：`Ci/` 的鐵路是經緯度上的車站與折線（沒有格）；`Railway/site_archive_clean/` 沿既有線形用累積距離與經緯度內插（沒有格）；參考包 `Railway/railway_game_reference_clean/` 是 OpenTTD（RailwayCore 15.3）的 tile／trackdir 系統，`01_MIGRATION_MAP.md` 要求移植行為與演算法結構而不是保留原實作。F3 與前兩份一致；OpenTTD 的選路、號誌與進路規則之後照決策 28 轉成節點、邊與行進方向，不把方格搬回來。

### 52. 線間距（Stage F2）

2026-10-04。F3 之後的 F2（ROADMAP 的順序；S4 的「留給之後」）：平行的軌道靠得太近時拒絕。

**參考**（2026-10-04 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-f2線間距)）：三份都**沒有**線間距或側向淨空的建造規則。`Railway/site_archive_clean/` 的軌道照 OSM 的線形擺放，程式明寫不以座標接近合併或橫移軌道（`rail-3d/physical/topology.js` 第 1 行、`rail-3d/integration/map3d.js` 第 347–348 行），側向的數字都只用在畫面：`rail-structures.js` 的 `NEIGHBOR_M = 6.5`（2–6.5 公尺內有同向高架段就不畫那一側的護欄）、`DECK_W = 5`（每股道一片橋面）、`GAUGE = 1.435`；`formations.js` 的車寬最寬 3.38 公尺（700T）。`Ci/reference_snapshot/` 只有共路線段畫面上 5 像素的錯開（`metroBranchSharedTrackLaneLayout`）與車站、節點的最小距離（`MIN_STATION_DISTANCE_M` 400 公尺、預設關閉，`ANCHOR_MIN_SPACING_M` 22 公尺，C1 已移植）。`Railway/railway_game_reference_clean/` 是 OpenTTD 的 tile 系統，平行的月台各佔一格，間距是方格的性質，沒有數值。所以線間距是缺口，照下面自訂。

1. **規則**：兩條邊在高度差不到 `TrackStructure.clearance`（512，8 公尺）的地方，中心線在平面上至少相距 `RailwayNetwork.trackSpacing` = **256（4 公尺）**；比這近的兩點，沿著軌道必須相距不超過 `RailwayNetwork.partingReach` = **32768（512 公尺，32 格）**。沿軌道近的兩點是同一個交會點分開的軌道（轉轍器的支線、連續的轉轍器、平面交叉），不算違規；沿軌道遠、或根本沒有軌道相連的兩點，是蓋得太近的兩條軌道。4 公尺是遊戲參數：參考最寬的車（3.38 公尺）兩列並排還有餘裕，也是 1/4 格。512 公尺讓 1/64 的支線（4 公尺時離轉轍器 256 公尺）也算分開。S4 的立體交叉（高差至少 512）照舊可以在平面上重疊；S4 的交叉規則照舊先檢查。
2. **精確的量法**（整數，不用浮點數）：每條邊的**檢查點**是從 `from` 端起每 64（1 公尺，曲線取樣的最大間距）一個，加上 `to` 端；位置是取樣折線上的內插（`TrackGeometry.location(at:)`，四捨五入），高度照縱斷面。檢查點到另一條邊某一段取樣折線最近的點（端點，或在那一段旁邊時的垂足）不到 256，而且另一條邊在那個最近點（垂足的里程是那一段兩端里程的內插，四捨五入）的高度和檢查點的高度差不到 512，這兩點就**太近**。垂足的距離以 `外積² < 256² × 段長²` 比較，用 128 位元（`WideInteger`），不會溢位。兩條邊互相檢查。
3. **沿軌道的距離**：兩點之間沿軌道最短的路：從檢查點沿它的邊到一端，再沿路網到另一條邊的一端，再沿那條邊到最近點；路網上的路不管邊在節點相不相接、往哪個方向（Dijkstra，邊長是精確的整數），超過 32768 就不必再找。共用的節點距離是 0。新邊建造時用的是還沒有它的路網：經過新邊本身的路，一定不比從那個點直接沿新邊走短。只有外框（加 256）重疊、高度範圍差不到 512 的邊對才逐點計算；建造與讀檔時算，tick 不碰它。
4. **建造與拆除**：`buildTrackEdge` 在 `trackConflict` 之後檢查，太近時拒絕 `trackTooClose(edge)`，指出編號最小的那條邊；被拒絕的指令不改變世界、不用掉 ID。拆邊只會讓沿軌道的路變長，可能讓留下的兩條邊變成太近（例如拆掉連續轉轍器之間的一段，兩條支線就沒有軌道相連）：`removeTrackEdge` 在 `trackReserved` 之後檢查，會留下太近的邊對時拒絕 `tracksWouldBeTooClose(a, b)`（依序第一對），要先拆掉其中一條。只有經過被拆的邊的路會變長，那些路都在它兩端的 32768 以內，所以只檢查兩端都在這個範圍內有節點的邊。蓋新邊只會讓路變短，不會產生新的太近的邊對。
5. **讀檔與舊存檔**：F2 之前蓋的世界可能已經有太近的邊對，所以存檔版本升到 **5**：
   - `RailwayNetwork.spacingExemptions`：F2 之前蓋得太近、留下來的邊對（編號小的在前，依序，不重複），存檔寫成網路的 `"spacingExemptions": [[a, b], ...]`，沒有時不寫，所以一般的存檔逐位元組不變。
   - 版本 1–4 的存檔照樣讀取：讀檔時把當下太近的邊對全部記成豁免（不能已經有 `"spacingExemptions"`）。再存就是版本 5。
   - 版本 5 的存檔（與直接解碼的 `GameWorld`）：太近的邊對必須**正好**是 `spacingExemptions`，多了或少了都拒絕並說明。
   - 豁免只屬於那一對：拆掉其中一條就從清單拿掉；新的邊一律檢查，不能靠近任何邊（包括清單裡的）；新的邊讓清單裡的一對沿軌道變近、不再太近時，那一對就從清單拿掉，之後拆掉那條新邊會被拒絕（不會再變回豁免）。所以清單永遠正好是太近的邊對，而它們只會來自 F2 之前的存檔。
   - `SaveFixtures/` 加上版本 4 的 `v4-demo-siding-90-minutes.json`（版本 4 的 build 寫的：示範地圖加一條離 Line 1 3 公尺、不接任何軌道的側線）與版本 5 的 `v5-demo-siding-90-minutes.json`（F2 的 build 讀進來再存，只多了版本與 `[[1, 11]]`）。
6. **golden 與差分模型**：schema 29 加上 `trackTooClose`、`tracksWouldBeTooClose` 與手算的 `track-spacing.json`；既有的 25 份只改版本，沒有任何預期值改變（`network-construction.json` 的 c 離支線 255.5，但沿軌道約 8200，是分開的那一段）。差分模型另寫一份（`ReferenceSpacing.swift`：依序走取樣點找檢查點、不用 128 位元而以長度的整數平方根夾出比較、沿軌道的距離是所有節點之間反覆放鬆到不再變（不是 Dijkstra、也不在 32768 截斷）、不先以外框或高度略過；拆邊時檢查剩下的每一對邊；沒有豁免，campaign 的世界都是指令蓋的），campaign 的 digest 因為新的拒絕而改變（新值記在 ROADMAP 的 F2）。
7. **F2b**（決策 53）：沿軌道近而平面上不到 4 公尺的兩點上，兩列車會並排靠得比 4 公尺近。決策 32 第 5 點只讓交會點 `junctionZone`（1024）以內的列車持有交會點；F2b 讓靠得太近的兩段軌道上的列車互相排斥（分開的那一段，與連續轉轍器之間的那一段），差分模型與 golden（`traffic-reservation.json` 的支線約 4240 才分開）隨之改變。豁免的邊對照舊，不另外處理。

### 53. 太近的軌道互相排斥（Stage F2b）

2026-10-04。決策 52 第 7 點留下的：沿軌道近、平面上不到 4 公尺的兩點（轉轍器分開之前的那一段、連續轉轍器之間），兩列車會並排靠得比 4 公尺近；F2 之前的存檔留下的豁免邊對也一樣。參考沒有警衝標或限界的規則（決策 52 的參考檢查），自訂。

1. **規則**：兩條不同的邊上，同一高度（高差不到 512）、平面上不到 `trackSpacing`（256）的兩點，沿軌道相距超過 `RailwayNetwork.foulingLength` = **512（8 公尺，線間距的兩倍）**（或沒有軌道相連）時，兩點**並排**：兩點所在的 span 互相**妨礙**（foul）。沿軌道 512 以內的兩點是繞過同一個節點的同一段軌道：前後相接的兩列車，或都在交會點旁、都持有交會點的列車（決策 32 第 5 點），不算。量法與決策 52 相同：每 64 一個檢查點對另一條邊的取樣折線，最近點的里程；落在 span 分界上的點兩邊的 span 都算。
2. **交通控制**：一列車不能取得與其他列車持有的軌道相同、或互相妨礙的軌道：`trackReserved`（取得路、放置、派車、服務出發）與開啟交通控制時的 `trainsShareTrack` 都照這個判斷。`heldResources`、預約與佔用照舊只列列車自己的軌道；妨礙是比較兩列車的軌道時才看的關係。沒有交通控制時沒有任何改變。
3. **拆邊**：拆掉一條邊只會讓沿軌道的路變長，可能讓兩列車已經持有的軌道變成互相妨礙：交通控制下，這樣的拆邊拒絕 `trackReserved`（依 ID 第一對的較小編號），在 `trackReserved`（預約了那條邊）之後、`tracksWouldBeTooClose` 之前。蓋邊只會讓路變短、新的邊上沒有列車，不會產生新的妨礙；加減月台會改變那條邊的 span，但持有那條邊的列車本來就會被拒絕。
4. **只在建造與讀檔時計算**：妨礙的 span 對是 `RailwayNetwork` 的推導資料（不存檔），蓋邊、拆邊、加減月台時更新：只重算與改變的邊有關、或兩端都在改變的邊兩端 512 以內的邊對（只有經過那裡的路會變），其他照舊；讀檔時全部算一次。交通控制只讀結果，不碰幾何。
5. **讀檔**：存檔的交通控制檢查照舊只看相同的軌道，不看妨礙：F2b 之前的存檔裡，交通控制下兩列車可能已經持有互相妨礙的軌道，這樣的存檔照樣讀得進來；它們已經取得的預約照舊有效，之後新的取得才照新的規則。
6. **golden**：新增手算的 `track-fouling.json`。`traffic-reservation.json` 的 South 月台原本從 e3 的 3875 開始，那裡 e3 離 e2 只有約 235：停在那裡的 Down 會妨礙 e2，Up 與 Down 從第 1 分鐘起互相等待，fixture 原本要測的單線輪流使用就不成立。所以月台移到 5813–7751（同樣的長度、都在既有的 span 分界上，e3 在 4844 以後離 e2 已經超過 294），Down 改停在 5813；其他預期值只有 Down 第 66、67 步的位置與預約（從 5813 出發，同樣的 8 分鐘跑 9909 而不是 7971）與最終狀態的月台改變（見 GoldenScenarios/README）。差分模型另寫一份（`ReferenceSpacing.swift` 的 `workOutFouling`：每一對有序的邊、所有節點之間反覆放鬆的路、只在被問到時算並以路網本身為鍵記住）。
7. **留給之後**：妨礙是 span 的粒度（S3A 的 span 最多 1024），所以並排的範圍以 span 為單位、偏保守。同一條邊彎回自己旁邊不檢查（決策 52 亦同）。U-min 的移動授權與 V 的待避可以直接用這個關係。

### 54. 拿掉殘留的方格語意（Stage F3d）

2026-10-04。F3c（決策 51）刪掉了方格的鐵路，但留下「一格 1024 單位」的世界：`GridMap`（地圖的大小與邊界）、`GridPosition`（越界錯誤、車站底下的格、選取）、`MapTile`／`TileType`（只剩 `.empty`）、`Station.position`（票價從底下那一格算，決策 51 作者的決定第 2 點）、`TrainPosition.linkLength` 與 `WorldCoordinate.tileSize`。作者決定現在拿掉（順序 F2b ✅ → **F3d** → U-min → V），模型變成：世界的範圍 → 連續的世界座標 → 節點／邊／曲線 → 車站的點與月台 → 列車在邊上的位置。不是重做 F3，也不是重做 T：`RailwayNetwork`、`TrackNodeID`／`TrackEdgeID`、`TrackTraversal`、`TrackCurve`、`TrackSpan`、`TrackResource`、`TrainPosition.onEdge`、交通控制、F2a 與 F2b 都不動。

**參考**（2026-10-04 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-f3d拿掉殘留的方格語意)）：`Ci/` 的票價用兩站經緯度的大圓距離（`app__q_c234188b7c397f91.js` 的 `stationDistanceM` → `haversine`，再 `calculateMetroFare({distanceKm})`），不量化；選站是半徑內最近的（`_collectUniqueStationsByDistanceAround`、`ANCHOR_PICK_RADIUS_M`）。`Railway/site_archive_clean/` 的位置是經緯度換成公尺的平面距離（`rail-3d/geo.js` 的 `distanceToSegment`、`rail-3d/integration/landscape-trees.js` 的 `MX`、`MY`），格子只當空間索引與擺樹的亂數（`polygonIndex`、`randomAt`），不是遊戲規則。參考包 `Railway/railway_game_reference_clean/` 是 OpenTTD 的 tile 系統（`docs/savegame_format.md` 的 MAP chunk、`binary_reference/relevant_symbols_and_settings.txt` 的 `rail_*_platform_per_tile_penalty`），決策 51 已決定不沿用 tile，F3d 沒有要搬的東西。三份都沒有「世界範圍以世界單位表示」的規則，`WorldBounds` 自訂。

1. **世界的範圍**：`WorldBounds`（`World/WorldBounds.swift`）是世界單位的 `width`、`height`，每邊 `1...WorldBounds.maximumSide`（2^20 單位，16,384 公尺），否則 `invalidMapSize(width:height:)`（現在是 `Int64` 的世界單位）。點在世界裡是 `0 <= x < width`、`0 <= y < height`（半開區間），沒有格子。`GameWorld.bounds` 取代 `GameWorld.map`；節點、曲線控制點、車站與解碼時的不變量都用 `bounds.contains`。新遊戲是 `WorldBounds.maximum`（E1 的 1024 格 × 1024 單位，數值不變）。
2. **刪掉的型別**：`GridMap`、`GridPosition`、`MapTile`、`TileType`（與 `tiles`、`occupiedTiles`）、`Station.position`、`TrainPosition.linkLength`、`WorldCoordinate.tileSize`、`WorldCoordinate(centreOf:)`、`FareRules.unitsPerMeter`。`outOfBounds` 帶世界的點（`PlanPoint`）。舊存檔還要讀的部分只留在解碼器裡：`LegacyGrid`（`tileLength` 1024、`maximumTiles` 1024、只為拒絕而讀的格座標 `Cell`）與 `GameWorld` 私有的 `LegacyMap`；遊戲規則都不用它們。
3. **票價與需求**：`squaredDistance(from:to:)` 是兩站**點**之間精確的平方距離（世界單位，不量化）；`tripFare` 與票價對需求的影響（`demandFactor`）都讀它。以前從兩站底下的格算：同一格的兩站距離是 0，跨一條格線的兩站至少差一格。車站都在世界裡，所以差值小於 2^20、平方和小於 2^41，不會溢位。差分模型（`ReferenceEconomy.ruleFare`）另寫一份：取平方根的整數部分再比較分段的終點（終點是整公尺，所以「比終點短」在取整後不變）。
4. **常數依用途分開**（數值都不變）：`WorldCoordinate.unitsPerMetre` = 64（世界唯一的比例：公尺換單位只用它）；`Train.carLength` = 1024（車廂中心距）；`RailwayNetwork.spanLength` = 1024（span 的上限、列車持有軌道的單位）；`ConstructionCosts.trackPricingLength` = 1024（鐵軌每 16 公尺收一次 `track`）；`MapScale.referenceLength` = 1024（畫面的縮放、細節與線寬以 16 公尺為單位）；`NetworkSession.platformStationReach` = 2048；示範地圖的排版步長（`DemoWorld` 私有的 `step`）。它們不再互相引用，也不叫「格」。
5. **GamePresentation 的選取**：`GameSession.selectedPoint`（`PlanPoint?`）取代 `selection: GridPosition?`；`select(_: GridPosition)` 與 `station(onTile:)` 刪掉。`tapMap(at:reach:)` 只看距離：半個 reach 內的車站、否則 reach 內最近的列車、否則 reach 內最近的車站，點本身照原樣保留；世界外的點忽略。`selectStation(_:)` 選車站和它的點。相機（`PlanCamera(bounds:viewport:)`、`WorldRegion(bounds:)`）、真實地圖（`RealWorldFrame(anchor:bounds:)`、`halfExtent(of:)`）與新遊戲（`newGameBounds`）都讀 `WorldBounds`；地圖的 VoiceOver 標籤是公里（`WorldBounds.mapLabel(in:)`：「Map, 16.4 by 16.4 kilometres」／「地圖，16.4 × 16.4 公里」），不再數格。
6. **存檔版本 6**（`SavedGame.currentVersion`）：世界寫 `"bounds": {"width", "height"}`（世界單位），不再寫 `"map"`；列車移動不再寫方格留下的空 `"continuation"`。版本 1–5 的 `w × h` 格地圖讀成 `1024w × 1024h` 單位（每一格都是空地），空的 `"continuation"` 照讀照丟；兩者都有、兩者都沒有、或範圍不合法都拒絕。只讀到版本 5 的 build 讀版本 6 時會說存檔比它新。任何版本裡手做的方格內容照舊拒絕並說明（決策 51）。`SaveFixtures/` 加上 `v6-demo-siding-90-minutes.json`：版本 5 的存檔由 F3d 的 build 讀進來再存，只差版本、`bounds` 取代 `map`、四個 `"continuation": []` 拿掉。
7. **golden schema 30**：`initialState` 的 `mapWidth`、`mapHeight`（格）改成 `worldWidth`、`worldHeight`（世界單位，數值 × 1024），`outOfBounds` 的結果帶被拒絕的點（以前是底下的格）。所有 golden 的車站都在格子中心，所以點的距離等於格的距離：**沒有任何預期值改變**（逐檔見 GoldenScenarios/README.md 的 schema 30）。ReplayFixtures 的起始世界照舊是 `"map"`，由解碼器讀成範圍，checksum 不含範圍，逐一不變。
8. **不變的**：T（交通控制只讀節點與 span）、F2a（線間距）、F2b（妨礙）、鐵軌的價格、車長、span、座標、新遊戲的大小與真實地圖的 16 公里框都不變；campaign 的產生器照舊以 1024 的步長抽點、在建世界時乘上 1024，所以抽籤順序不變。
9. **留下的舊名**：`GameError.invalidMapSize`、`outOfBounds`（玩家看到的錯誤，名字不提格）；舊存檔的 `"map"`、`"tiles"`、`"occupied"`、`"continuation"`、`"trail"`、`"position"`、`"annexes"` 等鍵只在解碼器裡讀；ReplayFixtures 與 `Web/` 的舊 fixture 不改。
### 55. 通過後釋放（Phase 4.6 Stage U 的第一步，U1）

2026-10-04。F2 之後的 U-min（ROADMAP「目前的優先順序」第 7 項）。U-min 是 movement authority 的最小穩定契約，分兩步：

- **U1**（這一條）：列車只走進它預約到的軌道，通過後逐段釋放（ROADMAP 的「列車只能進入預約到的資源，通過後釋放」）。授權照 T 一次取得到下一個停靠點，所以授權終點就是路的終點。
- **U2**（之後）：授權終點可以在路的終點之前（在站間跟在前車後面），列車依曲線在授權終點前停下。

**參考**（2026-10-04 唯讀檢查三份，私有 repo `1563ad0`，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-u列車只能進入預約到的軌道)）：

- `Railway/site_archive_clean/index.html` 的 `updateBlockHolds`（8856 行）與 `BLOCK_*` 常數（8780–8787 行）：畫面層的跟車，延後同股道後車的顯示時間，結果隨畫格間隔（`dSim`）改變；沒有預約或釋放的規則（對照文件 gap 5、6）。
- `Ci/reference_snapshot/`：`MIN_TRAIN_GAP` 等常數只有定義（`lib/app__q_c234188b7c397f91.js` 只出現一次）。`PROJECT_ABSORPTION_GUIDE.md` 只寫了流程「departure due → request authority → reserve resources → approved continuation → movement」，並把「reservation release」列為之後 dispatcher 的基礎，沒有程式。
- `Railway/railway_game_reference_clean/`（RailwayCore 15.3，OpenTTD 的編譯檔）：只有名稱：`pf.yapf.rail_pbs_cross_penalty`、`rail_pbs_station_penalty`、`rail_pbs_signal_back_penalty`、`rail_look_ahead_max_signals`、`CmdBuildSingleSignal`、`CmdBuildSignalTrack`，以及 `src/train_cmd.cpp`、`src/pathfinder/yapf/yapf_base.h` 的路徑；沒有原始碼。這些名稱代表的 path-based signalling 的結構是：列車先預約到一個可以安全停下的地方，最後一節離開一段軌道時釋放那一段。T 加上 U1 照這個結構：T 的「可以安全停下的地方」是下一個停靠點（路的終點），U1 是「車尾離開時釋放」。我們沒有號誌，所以 `rail_look_ahead_max_signals` 與號誌的懲罰沒有對應（U2、V）。

所以釋放的規則是 gap，照 T 的語義（決策 32）自訂：

1. **規則**：交通控制下，列車每次移動之後，它的預約變成「原本的預約中，它從現在的位置還需要的部分」：`routeEnvelope(of:)`，也就是佔用、車頭還要走過的路，與這兩者碰到的限界節點（決策 32 第 3–5 點）。路沒有距離時清空（T 的解除）。所以車尾嚴格越過一個 span 的終點時那個 span 釋放（落在分界上時兩邊都還持有），車身不再碰到的節點、不再在 1024 以內的限界節點也在同一步釋放；F2b 的妨礙（決策 53）是比較兩台列車時才看的關係，跟著持有的 span 一起消失。
2. **只縮不增**：列車只沿路往前，「車尾到路的終點」這一段只會從後面變短，而資源的規則是逐點的，所以預約範圍只會變小；T 保證預約範圍一直在預約之內（決策 32 第 7 點：取得時兩者相同，之後拆邊、加減月台與在持有的交會點加邊都被拒絕）。所以 U1 不取得任何軌道，也不釋放列車還會用到的軌道，而列車只走進它的預約：這就是 U1 的 movement authority。授權終點是路的終點，W2c 的曲線本來就在那裡停下（決策 40），所以移動 kernel 不需要另外的上限；授權終點早於路的終點時的上限與煞車是 U2。
3. **在哪裡**：移動段（`advance` 的第 2 段）每台列車移動之後，`releasePassedTrack(_:)`（取代 T 的 `releaseEndedRoute(_:)`，決策 32 第 16 點留下的接點）。沒有移動的列車不變。
4. **以秒批次推進仍然精確**：同一個基本步長裡，路被持有的出發（服務停在站上、出發時刻已到）每一步重試。T 的軌道只在某台列車走完路時釋放，批次在那一秒結束就夠了（`secondsUntilARouteEnds`）。U1 的釋放是連續的，所以批次也在「等待中的出發需要的軌道空出來」的那一秒結束（`secondsUntilARouteFrees(_:from:within:)`）：
   - 出發段（第 1 段）被擋的出發把它需要的軌道記下（`HeldRoute`，`Reserving.held` 多帶 `needs`）；
   - 在世界的複本上讓列車移動 k 秒（同一個 `moveTrains`，會釋放），看是否有一個等待的出發已經沒有持有者；其他列車的持有在批次裡只會變小，所以這是單調的，對 k 二分搜尋；
   - 批次結束在最小的那個 k，下一步從那一秒開始，出發照 ID 順序重試，與逐秒推進相同。
   - 只在有等待的出發時才計算。派車只在整分鐘，批次本來就在整分鐘結束；指令在兩次 `advance` 之間，看到的都是釋放之後的狀態。釋放在批次結束時一次做，結果與逐秒相同（預約範圍單調）。
5. **存檔**：格式不變（沒有新的 key，存檔版本不變：U1 寫成時是 5，F3d 之後是 6）。U1 之前的存檔裡，行駛中的列車可能還預約著已經走過的軌道（T 保留到路的終點）；照決策 32 第 14 點照樣讀取（多預約的資源只是保守），那段軌道一直被持有，列車下一次移動時釋放。讀檔的檢查不變：預約必須包含預約範圍。
6. **不變的**：取得的規則、時機與錯誤順序（決策 32 第 7–12 點）、限界、妨礙、`trainHoldingRoute`、交通控制關閉時的一切。基礎設施的保護不變，但只保護列車還持有的軌道：列車通過之後，那條邊可以拆、可以加減月台，交會點可以加邊。
7. **效果**：後車不必等前車走完整條路，前車的車尾一離開後車需要的軌道，後車就能出發。同方向的一串站：T 下後車要等前車到了下一站才能開進前車剛離開的那一站；U1 下前車一離開那一站的月台，後車就能開進來。也就是從「兩個站間一台」變成「一個站間一台」，站間的閉塞（例：`testAFollowerLeavesOnceTheTrainAheadHasLeftItsTrack`，後車在第 359 秒出發，T 下要到第 768 秒）。
8. **golden 與差分模型**：schema 不變；只有 `traffic-reservation.json` 改變五個預期值（Up 在第 2 分鐘的預約少了車尾後面的 span；Down 在 9:00 而不是 10:00 出發，之後的位置、預約與時刻），逐值說明在 GoldenScenarios/README 的「U1」。差分模型另寫一次（`ReferenceTrafficControl.swift` 的 `releaseBehind`：逐秒推進、每秒移動之後把預約換成它自己以絕對距離算出的需要；GameCore 是批次推進、在原本的預約裡過濾），兩者都得到同樣的新值。

**驗證**：

- `TrafficControlTests`（手算）：改了 6 個 T 的測試的預期值（走過的 span 與節點不再在預約裡，各自寫出手算的位置），新增 4 個：通過後的軌道可以立刻拆、放上別的列車，前方仍是自己的；通過轉轍器的列車在支線上離交會點 1024 以內時仍預約著交會點，之後才釋放；後車在前車的車尾離開它需要的軌道的那一秒（359）出發，以分鐘推進與 3,600 個 0.1 秒的 tick 結果相同；U1 之前的存檔多預約已經走過的 span，照樣讀取並在列車下一次移動時釋放。
- `traffic.reservation` campaign（12,800 個操作，digest `58747680E8B1D600`）：每一步比較 GameCore 與 `ReferenceWorld` 的預約、持有與等待；新增計數「通過後釋放」（494，下限 200）與「前車還在走時後車就出發」（7）。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄（主工作目錄的 `Sources` 從未改動），都被抓到：
  - 不釋放（T 的行為）：`traffic.reservation` 第一個種子的 case 0 第 19 步；golden 與 7 個手算測試失敗；
  - 批次不在等待的路空出來的那一秒結束：case 18 第 22 步；後車的手算測試失敗（golden 的 Down 剛好在整分鐘出發，看不出來）；
  - 只留車頭之後的路、放掉自己的車身：case 0 第 39 步；golden 失敗；
  - 釋放時忘了限界節點：case 1 第 12 步；為它新增的通過轉轍器的手算測試失敗。

**留給之後**：

- **U2**：授權終點在路的終點之前（站間跟車）：部分取得、移動 kernel 的上限、依曲線在授權終點前停下、授權延長時重新出發。部分取得會造成「拿一半、等另一半」（決策 32 第 15 點），要先解決它在單線上造成的死結（只在前車一定會讓出的情形才部分取得，或交給 V）。參考的跟車距離（`BLOCK_GAP_KM` 0.4 km）可以當作授權終點前的保留距離（對照文件 gap 5）。
- 死結（單線兩端互等、時刻表造成的循環等待、兩台站著的列車互擋）照舊留給 V。
- 畫面還不顯示預約或授權的範圍。

### 56. 站間跟車（Phase 4.6 Stage U 的第二步，U2）

2026-10-04。U-min 的第二步（決策 55 的「U2」）：授權終點可以在路的終點之前，服務在站間跟在前車後面。

**參考**（2026-10-04 唯讀檢查三份，對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#stage-u2站間跟車)）：

- `Railway/site_archive_clean/index.html` 的 `updateBlockHolds`（8856 行）：同一條線、同方向的列車依位置排序，後車與前車的距離（`blockSep2d`）保持在 `BLOCK_GAP_KM` = 0.4 km（8780 行）以上；停在站上的前車擋住後車（`blockStoppedAtStop`、`blockParkedBlocks`）。移植的是距離與結構：後車停在前車後面 400 m 的地方、前車讓出後再前進。它在畫面層延後顯示時間、隨畫格間隔改變（gap 5），所以不移植作法：GameCore 以預約的資源與整數距離表達，逐秒決定。
- `Ci/PROJECT_ABSORPTION_GUIDE.md`：Stage T 的「departure due → request authority → reserve resources → approved continuation → movement」，Stage U 的「列車在哪裡等」；沒有程式。
- `Railway/railway_game_reference_clean/`：OpenTTD path-based signalling 的名稱（`pf.yapf.rail_pbs_*`），結構是「預約到一個可以安全停下的地方」：U2 的安全停車點是前車持有的軌道之前 400 m。

規則：

1. **跟車的距離**：`GameWorld.followingGap` = 25,600 單位（0.4 km × 64,000，`BLOCK_GAP_KM`）。
2. **誰可以跟車**：交通控制下，服務出發（`departService`）與路線派出的列車出發（`readyTrain`）時，如果路被其他列車持有（決策 32），而且每一台持有、妨礙或等著它的路（第 6 點）的列車都是**前車**，就跟車出發。前車：執行服務、行駛到下一個停靠點、rate 大於 0、整條路都預約到（自己不在跟車），沒有在後車經過的任何一條邊上反方向行駛（參考只讓同一條線、同方向的列車互相跟車：`updateBlockHolds` 依 `路線|方向` 分組；對向來的車不跟），而且它停靠時站的地方（佔用與限界）不在後車的路上，或它從那一站不折返、繼續開往下一個停靠點。站著的、要折返或結束服務的、自己在跟車的列車，照舊要等它讓出整條路（U1）。手動的路、放置與反向不跟車，照舊整條取得。
3. **授權**：沿後車的路，找出最遠的距離 L，使得從車尾到那裡整列車會碰到的軌道（`authorityEnvelope(of:to:)`：佔用、車頭在 L 之內走過的路與這些碰到的限界）沒有被其他列車持有、妨礙或等著；授權到 L − 25,600，至少 1 才跟車，否則照舊等待。預約是到那裡的 `authorityEnvelope`，以 span 為單位，所以車頭可以走到最後一個 span 的終點：實際距離至少 25,600 − 1,023。
4. **移動的上限**：`authorityLeft(of:)` 從預約推導（最遠的、`authorityEnvelope` 都在預約裡的距離），不存檔。`travelling` 不超過它：列車照行駛曲線走，到授權終點就停下；曲線被擋住的那一秒丟掉（決策 40），授權延長後從停止重新出發。
5. **延長**：每一秒開始時、在派車與出發之前（`extendAuthorities()`），跟車中的列車依 ID 順序：路上已經沒有別的列車持有或等著時取得整條路（不再跟車）；否則延長到第一段被持有的軌道之前 25,600，比現在遠才延長。已經在路上的列車先取得。
6. **等著的軌道**：跟車中的列車路上還沒預約到、也沒有人持有的部分，別的列車不能取得（`holder(of:except:)` 也回報它），除非那台列車自己持有它路上的軌道（它的前車）。所以第三台列車不能從中間插進前後車之間。
7. **停止的服務**：跟車中的服務被停止時，列車保留它的路與部分預約，照舊跟車、延長（跟車由預約判定）。
8. **以秒批次推進仍然精確**：`secondsUntilARouteFrees(_:from:within:)` 也在「等待的出發可以跟車出發」或「跟車中的列車可以延長」的那一秒結束批次；跟著移動中的前車時幾乎每一秒都會延長，所以先檢查第一秒。
9. **存檔**：版本 7。行駛中的列車的預約可以不包含整條路（跟車）；讀檔時要求預約至少包含 `authorityEnvelope(of:to: 0)`（佔用與限界）。版本 6 以前的存檔照樣讀取（遷移不改內容），舊版的程式讀到版本 7 時明確拒絕，而不是讀進部分預約。
10. **不變的**：交通控制關閉時的一切；整條取得的規則與錯誤順序（決策 32）；通過後釋放（決策 55）；27 份既有 golden fixture 的每一個預期值。
11. **效能**：跟車時每一秒都可能延長，所以這幾處只在結果不變的前提下改快：`RailwayNetwork` 記住每條邊的 span（`edgeSpans`，和 `foulingSpans` 一樣在邊與月台改變時重算、不存檔），切 span 時月台的端點與等分點直接依序合併、不再排序；同一台列車在多個距離上的授權範圍（`AuthorityEnvelopes`）先算好與距離無關的部分；批次判斷「有沒有列車可以延長」只看授權之後一個跟車距離的地方，不做整個二分搜尋。

**驗證**：

- `TrafficControlTests.testAServiceNeverFollowsATrainComingTheOtherWay`（手算）：對向來的車在後車路上的 M 停靠後繼續開，後車照舊等它讓出整條路。
- `TrafficControlTests.testAServiceFollowsAServiceAheadOfItBetweenCalls`（手算）：前車在 M 站著時後車等待；1:00 同一秒出發，後車預約到 e1 的 21504；逐秒檢查兩車的持有不相交、跟車時距離至少 25,600 − 1,023；第 640 秒到 N；以分鐘推進與逐秒推進結果相同。
- `train-following.json`（新的 golden，schema 30）：GameCore 與 `ReferenceWorldGoldenTests` 各自得到同樣的值。
- `traffic.following` campaign（`TrafficControlPropertyTests.testFollowingMatchesTheReferenceAtEveryStep`，12 個 case × 4 個種子 × 60 個操作）：六站的直線上三到五台列車同時往東出發、互相追上，再隨機加上時刻表、停止、rate、交通控制的開關與手動的路；每一步比較 GameCore 與 `ReferenceWorld`（逐秒、斷點掃描地求授權，寫法和 GameCore 的二分搜尋不同）的結果與整個狀態，並檢查不變量與存讀。量：跟車出發 20、跟車時取得更多 18、取得剩下的全部 16；digest `1EF4AAB19D63FDE2`。
- `traffic.reservation` campaign 不變：digest `7916D02C7E554D3C`，與 main 相同。
- 移到新的 CI shard `campaigns-9`（`TrafficControlPropertyTests`，`swift-shards.sh`）。

**留給之後**：

- 依煞車曲線在授權終點前減速：現在到授權終點就停下（和 W2c 被擋住的列車一樣），授權延長後從停止重新出發。
- 參考的跟車距離逐步回到 0.4 km（`BLOCK_GAP_GROW`、`BLOCK_GAP_MIN_KM`）、依編組長度的最小距離（`blockClearance3d`）與顯示時間的延後：沒有移植（畫面層）。
- 對向的列車、單線兩端互等與其他循環等待（決策 32 第 15 點）照舊留給 V；跟車只在前車一定會讓出時才發生。
- 畫面還不顯示預約或授權的範圍。

### 57. 避開被占用軌道的選路與月台分配（Stage V1）

2026-10-04。服務出發與路線派車的就緒判斷，在交通控制下依序嘗試：預設的最近停車位置的路整條取得；在預設路上跟車（決策 56）；到同站任何合適停車位置、避開其他列車持有軌道的最短路整條取得；原地等待。只有 `GameWorld` 提交最後取得的候選列車。手動路、放置、反向與交通控制關閉時照舊。同日作者要求做 V2，並以最佳選擇定案原本待決定的兩件事（先跟車還是先改路、繞路上限），見下。

- **搜尋**：移植 `Railway/site_archive_clean/rail-3d/physical/topology.js` 的 `shortestPath({blocked})`。`ServicePath.networkPath` 每一步（到當前邊的終點或一個停車位置）以 `resources(covering:) ∪ foulingNodes(covering:)` 對 `blockedTrack(except:)` 做 `network.fouls` 判定；被持有的 span、限界節點、F2b 妨礙與 U2 等著的軌道都避開。停車位置之前沒有衝突時，即使同邊後段被擋也能停靠。平手沿用決策 31 的順序。找到路後仍以 `reserving` 檢查整個 envelope（含車身）；失敗時不提交，也不在替代路上部分取得。
- **替代路的方向限制 / gap**：只限制替代路新增借用的 traversal：不得逆向使用**還會開的列車**會走的方向。(a) 每台已放置、服務執行中的其他列車，從它**現在的位置**起：行駛中時剩下的路；路的終點不在呼叫站時（決策 58 的待避站）再到呼叫站的路；然後依時刻表從那一站往後逐段選既有預設最短路，先依該站的 reverses 折返，停車位置與車身依該路逐段推導，重複時刻表包含末站回第一站與之後的循環，直到「停靠索引＋車頭／車身位置」重複或無路，不是有限 N 段的前瞻；已經走過的段與它沒有停的第一站 berth 不算。(b) 每條路線的每個服務（含服務模式）只要 roster 裡有候選車以外的已放置列車，就照 #103 保護整個計畫（2026-10-07，#100–#147 審查：路線不對自己唯一的那台車保護計畫，否則單線來回的路線列車在死結時連倒入待避線都被自己的去程方向禁止，永遠解不開）：從第一站每個放得下車身的方向性 berth 出發，完整來回或環線兩方向，以候選車以外每台已放置列車的車長計算；不看營運時段、派車時間或上線數。路線列車回到第一站後可能停在任何 berth，所以這裡保留枚舉。沒有執行的時刻表（跑完、停止或從未啟動）、roster 沒有已放置列車的路線、未放置的列車都不保護：它們要開時，出發本來就要整條取得路，衝突時等待或由決策 58 處理。候選車預設路本來就會走的同向 traversal 不受此額外方向限制，否則單線共用的預設走廊會被對向計畫禁行，連空月台也到不了；blocked span、限界與整個 envelope 的取得仍照常檢查。這份方向集合不是持有或預約、也不是永久 one-way 屬性，不存檔、不依渡線曲線形狀判斷。對向服務在任意多段之外、路線尚未營運（但已有列車）時，新增借用的對向正線仍受保護。死結的偵測與解除見決策 58，它的待避路也守同一個方向限制。（#103 的原始版本對每台有時刻表的列車都從第一站每個 berth 枚舉整份時刻表，也保護沒有列車的路線；融合的理由與量測見下面「融合」。）
- **先跟車，再改月台**（定案）：預設路被持有時先試 U2 跟車，只有不能跟車（前車站著、要折返、對向而來、或不到 400 m 的空間）才找替代路。理由：U2 只在前車一定會讓出時成立，等待有上限，不必改路；列車留在路線平常的月台，乘客與時刻表可預期，參考的 `updateBlockHolds` 也是同線同向跟車；待避線與其他月台留給對向列車交會，V2 要處理的死結較少；也少一次行駛曲線重算。代價是同向列車不能利用平行月台超前，同向待避屬於之後的排定待避（`planSameDirectionOvertakes`）。測試：`testAServiceFollowsAMovingLeaderBeforeTakingAnotherPlatform`。
- **繞路上限**（定案）：替代路最多比預設路長 `GameWorld.detourAllowance` = 25,600 單位（400 m，與參考的 `BLOCK_GAP_KM` 同一尺度）。進同站另一月台或待避線只多出轉轍器的幾公尺到幾十公尺（`single-track-meet.json` 多 636 單位，約 10 m）；離開本線去借別條線則多出數公里。用固定距離而不用倍數，長的站間也不會因此允許長距離繞行。超過上限時照舊等待（`testAnAlternativeMoreThanTheDetourAllowanceLongerIsNotTaken`）。參考的渡線懲罰沒有移植：路網沒有渡線種類，而方向限制已經排除逆向借線。
- **出發**：`reservingDeparture` 共用於 `departService`、`readyTrain`、等待查詢、批次喚醒與待避站續行（決策 58）；能整條取得替代路時，等待查詢不回報預設路的持有者。替代路的行駛曲線按新距離與原排定的段間秒數重算；經營的離站距離讀實際採用的路。反向仍先在候選位置求路，不能取得時不反向。
- **快轉**：等待出發的批次喚醒也重試替代路，在它首次可取得的秒數結束；否則整分鐘批次可能錯過已空出的另一月台。路線計畫，以及執行中服務從路的終點（或停靠的位置）往後的推導，在批次內都不變；其他列車只釋放軌道、縮短剩餘實際路，方向集合只會變小；新出發、到站與時刻表變化在批次邊界處處理，可取得性仍為單調。
- **狀態 / 存檔**：只改決定出發時選哪條既有 `TrainPath`；沒有新權威欄位、key 或驗證格式，V1 本身不改 `SavedGame.currentVersion`（存檔版本 8 來自決策 58 的待避站）。避占用路不快取，ownership 每秒可能改變；span 使用 `RailwayNetwork` 已有快取，不重切。`DispatchMemo.directions` 僅存在單次 advance，服務就緒、出發與批次喚醒共用它；路線計畫按完整停靠／折返順序、車長與是否重複快取；執行中服務的逐段推導另以「計畫＋起點位置＋停靠索引」為 key 快取（行駛中的起點是路的終點，整段行駛期間不變），都不含時刻。路網在 advance 內不能變；路線派出新 timetable 時讀其新順序 key，來源集合與當下實際路仍每次重新合併。查詢使用自己的短期 memo；指令、存讀或下一次 advance 一律沒有沿用快取。
- **參考檢查**：三份乾淨參考於私有 repo `1563ad0` 唯讀讀取。Ci 的 absorption guide 提供 request/reserve/approved continuation 流程與月台分配目標，snapshot 的 `MIN_TRAIN_GAP` 只有定義；RailwayCore migration map 提供 path cost/PBS 概念，只有編譯符號而無此選路原始碼。完整對照與倍率見 [Stage V 對照](RAILWAY_REFERENCE_MAPPING.md#stage-v避占用選路與月台分配)。
- **獨立模型**：`ReferenceNetworkService.distancesToBerths` 在鬆弛前排除被擋住的 run 區間與禁止方向，保留可達的近端 berth，再依距離貪婪選第一個選項；`ReferenceTrafficControl.unblocked` 使用它自己的絕對距離資源時窗，`contraryRuns` 對執行中服務讀它的絕對距離時窗，從時窗終點（必要時先到呼叫站）以「停靠索引＋車頭／車身位置」工作清單獨立求可達狀態（`serviceRuns`）；有已放置列車的路線／服務模式／雙向環線則從所有第一站 berth 起求（`directionRuns`），不經派車就緒判斷；最後排除候選車預設時窗本來使用的同向 run。`chosenRoute(from:to:)` 先試預設路（整條或跟車），再試 `alternative`（400 m 上限）。不能呼叫 GameCore 選路。可通行 run 與後繼只算一次，再進行鬆弛；模型的 `RouteMemo.BlockedKey` 在單次 `advance`（路網不變）內以起點、目標、車長、完整 blocked 資源及禁止方向集合為 key，包括找不到路的結果。資源或方向一變就重搜，每次仍檢查當下整個 envelope；這份測試快取不算模型狀態，返回前清空。GameCore 的避占用路不快取。

**驗證狀態**：VERIFIED（Linux workspace，Swift 6.4）：第二輪 review 的「Z→E→M→W 兩段之外對向服務」及「營運時間尚未到的路線」在修正前共五個失敗斷言；修正後通過，保留上一輪雙線回歸、單線交會／改月台、等待、就緒與批次喚醒。另驗證空 roster 路線仍保護完整路，刪除路線後下一次 advance 清除推導保護（融合後空 roster 路線不再保護，見下面「融合」）。`traffic.occupiedRouting` 保留原六組單線與兩組雙線 case，新增兩段之外服務及未營運路線兩組，10 case × 4 seed，逐步比較結果／整個狀態／持有／預約／等待、不變量與存讀，量的下限保持或增加。warnings-as-errors、42 個 TrafficControlTests、campaigns-10、rest、campaigns-9、Swift 6.0 light 與最終 CI 結果記在本次修正 PR；未執行的標 UNVERIFIED。所有 golden（含 49 步 / 7 遊戲分鐘的 schema 30 `single-track-meet.json`）、SaveFixtures、ReplayFixtures 與存檔版本 7 保持不變。

**定案後的驗證**（Stage V2 PR）：VERIFIED（Linux workspace，Swift 6.4）：warnings-as-errors 建置；44 個 `TrafficControlTests`，含兩個定案測試 `testAServiceFollowsAMovingLeaderBeforeTakingAnotherPlatform`（GameCore 與獨立模型逐步比較）及 `testAnAlternativeMoreThanTheDetourAllowanceLongerIsNotTaken`。`traffic.occupiedRouting` 的 digest 仍是 `C084C3CBDA88B0CB`，數量也相同：它的情境裡沒有一處同時能跟車又能改月台，用到的替代路都在 400 m 以內，也沒有被送去待避站的死結，所以兩個定案與 V2 不改變它任何一步的狀態。`traffic.following`（`1EF4AAB19D63FDE2`）、`traffic.reservation`（`7916D02C7E554D3C`）與其他 campaign 的 digest 不變。所有既有 golden（含 `single-track-meet.json`）、SaveFixtures 與 ReplayFixtures 的值不變。

**融合**（2026-10-04，作者要求「最佳融合」）：#103 的方向保護完整但偏保守，Stage V2 開發中另寫的版本（只看執行中列車從所在位置往後的路）精準但不保護未來路線。融合後取兩者的長處：執行中服務用後者，路線用前者但只限有已放置列車的，其他不保護（上面 (a)(b)）。量測（`traffic.deadlock`，同一組 1352 個操作）：#103 原版待避 24、完成服務 101、留下的死結 14（digest `366A22C95DBC8D3F`）；融合後待避 37、完成服務 111、留下的死結 11（`42AE3745A3FF09E8`）。逐項還原的對照：只把「執行中服務也從第一站每個 berth 枚舉整份時刻表」加回去，digest 就回到 `366A22C95DBC8D3F`；只把「沒有執行的時刻表」加回去則完全不變，所以損失來自前者：停在交會站正線、要往東開的列車，被當成也可能從待避線出發，待避線因此對西行列車禁行，兩車互等且沒有待避站可解（回歸測試 `testARunningServiceLeavesTheLoopItDoesNotUseToAnOpposingService`，在 #103 原版上兩車永久死結）。`traffic.occupiedRouting` 的 digest 不變（`C084C3CBDA88B0CB`）：兩段之外的對向服務、營運時間前的路線與雙線的保護全部照舊。唯一刻意改變的行為：沒有已放置列車的路線不再保護（#103 的 `testRemovingAnUnassignedLineReleasesItsDerivedDirectionProtection` 改為 `testALineProtectsItsPlanOnlyWhileAPlacedTrainIsAssigned`：指派列車才開始保護、取消指派就解除）。

**融合後的驗證**：VERIFIED（Linux workspace，Swift 6.4）：warnings-as-errors 建置；57 個 GameCoreTests 類別（含全部 campaign，未縮減）與 GamePresentationTests 全部通過，其中 45 個 `TrafficControlTests`（新的 `testARunningServiceLeavesTheLoopItDoesNotUseToAnOpposingService`、改寫的 `testALineProtectsItsPlanOnlyWhileAPlacedTrainIsAssigned`，以及 #103 的兩段之外對向服務、營運時間前的路線）。新的回歸測試在 #103 原版的三個檔案（`ServiceDirections.swift`、獨立模型的 `ReferenceTrafficControl.swift`、`ReferenceWorld.swift`）上實際跑過：兩車每一步都在 `deadlockedTrains()` 裡。campaign digest 只有 `traffic.deadlock` 改變（`366A22C95DBC8D3F` → `42AE3745A3FF09E8`），其他全部不變（含 `traffic.occupiedRouting` `C084C3CBDA88B0CB`、`traffic.following` `1EF4AAB19D63FDE2`、`traffic.reservation` `7916D02C7E554D3C`）。所有 golden、SaveFixtures 與 ReplayFixtures 的值不變，存檔版本維持 8。

**Deferred（暫時沒有改的地方）**：排定的等待與時刻表交會、待避推估（`inferMeetPassTimes`、`planSameDirectionOvertakes`、`resolveTraTraffic`）；單線區段的路線容量（決策 22 的限制）；畫面顯示授權範圍。死結的偵測與解除見決策 58。

### 58. 死結的偵測與解除（Stage V2）

2026-10-04。作者要求做 V2。交通控制下 T 只取整條路、U2 只跟一定會讓出的前車、V1 只在不逆向時改月台，剩下的就是互相等待：單線兩端對向的快車、月台不夠的交會站（決策 32 第 15 點）。參考沒有死結的偵測或解除（三份乾淨參考都沒有，gap），規則是本專案自己的。

1. **誰在等**（`waitingRoute(of:memo:)`）：到出發時間的服務、到派車時間且就緒的路線列車、待避站上的服務（第 4 點），它們的出發（決策 57 的整條、跟車、替代路）都取不到；或是跟車中的列車，已走到授權終點、路上仍被持有而動不了。還能移動的列車不算在等，因為它一移動，持有的軌道就會改變。
2. **死結**（`deadlock(memo:)`，公開查詢 `deadlockedTrains()`）：從所有在等的列車開始，依 ID 反覆拿掉「假設只有剩下這些在等的列車保留軌道，它就走得了」的列車：預設路不被它們擋住，或出發時有一條只避開它們的替代路。直到再也拿不掉為止，剩下的就是死結：每一台等的軌道只被同一組裡的列車持有，外面任何列車讓出都幫不上忙。這是經典的死結偵測（reduction）。等一台會自己開走的列車（行駛中，或還沒到出發時間）永遠不算死結。
3. **解除：待避站**（`passingPlace(for:in:memo:)`、`resolveDeadlock(memo:)`）：每個整分鐘、服務階段之後，死結裡依 ID 第一台「到出發時間的服務，或停在待避站的服務」，找一個待避站：呼叫站以外每一個車站（依 ID）最近的停車位置，條件是 (a) 現在就能整條取得，避開其他列車持有的軌道；(b) 到那裡的路，以及從那裡續行到呼叫站的路，新借用（不在預設路上）的軌道都不逆向還會開的列車的方向（決策 57 的方向限制）；(c) 經過待避站的全程不超過預設路加 400 m（`detourAllowance`）；(d) 列車停在那裡時，死結裡的另一台列車能出發（決策 57 的三種方式之一）。取全程最短的，平手取車站 ID 較小的。列車整條取得到待避站的路，照最快的曲線開過去。從車站出發時照一般出發記帳（G1b 的拒載、G1c 的離站），距離算經過待避站到呼叫站的全程。每分鐘最多送一台去待避。路線還沒派出的列車與跟車中的列車不會被送去待避：它們沒有可以改的出發。
4. **待避中**（`isAtPassingPlace(_:)`，公開查詢 `passingPlace(of:)`）：服務開往某一站，路已走完，停在另一站的停車位置。每一步的服務階段（`goOn`）照一般出發的規則（整條、跟車、替代路）取得續行到呼叫站的路，取得就照最快的曲線出發；取不到就原地等，並加入批次喚醒的等待清單。待避站不是停靠站：不開門、不上下客，也不記到站。交通控制關閉時立刻續行。
5. **只在整分鐘**：死結的組成只在列車開始等待時（出發時間到、到站、路線到派車時間）改變。調度只在整分鐘動作，而整分鐘一定是批次的邊界，所以以秒批次推進仍然精確（`testBatchedMinutesResolveExactlyAsSingleSeconds`）。閒置分鐘的快轉多了一個喚醒點：路線上只因路被占用而沒派出的列車，開始或停止到派車時間的那一分鐘（`minutesUntilLineWaitsChange`）。這只影響效能，不影響結果。
6. **解不開的死結**：沒有任何待避站能讓另一台出發時（例如兩端各只有一個月台、中間沒有待避線，或待避線被停著的列車占住），死結保留，畫面告訴玩家：列車面板的等待文字是「Deadlocked with X」／「與 X 互相卡住（死結）」，等玩家改路網、月台或列車數。需要多次換向的折返或調車解法不做（gap）。
7. **存檔**：版本 8。格式不變，但開往或停在待避站的服務，它的路不在下一個停靠站結束，或者已經走完；版本 7 的程式會當成損毀，所以版本 8 讓它說「較新版本的存檔」。`Train` 的解碼器（沒有地圖）不再拒絕路已走完的行駛中服務，改由 `GameWorld` 的檢查要求它停在另一站的停車位置；開往待避站的路必須在某一站的停車位置結束。`SaveFixtures/v8-demo-siding-90-minutes.json` 是 v7 存檔用這個 build 重存的結果，只差版本號。
8. **畫面**：列車面板的等待文字（`routeWaitText`）新增「Standing aside at M until X clears the route」／「在 M 待避，等待 X 讓出進路」與上面的死結文字。App 的程式不用改：`TrainControls` 本來就顯示這段文字。
9. **不變的**：交通控制關閉時的一切；沒有死結時的一切（所有既有 golden 與 replay 不變）；決策 32、55、56 的取得、釋放與跟車規則。

**獨立模型**（`ReferenceDeadlock.swift`）：逐秒推進；死結以「回合」找出：每一回合同時留下仍然走不了的列車，直到不再變小（GameCore 依 ID 一台一台拿掉，兩者得到同一個最大集合）。在等與能否出發，都用 `chosenRoute(from:to:)` 在世界本身或把列車搬到待避站的副本上試。待避站續行的路逐 run 檢查方向。不呼叫 GameCore。

**驗證**：VERIFIED（Linux workspace，Swift 6.4）：
- `DeadlockTests`（8 個）：對向快車在 M 主線待避後錯開並完成服務（手算：W 到 M 主線 5120 + 9216 = 14336，續行 7168 + 7168 = 14336，全程 28672，等於預設路）；沒有待避線時死結保留並回報；等一台會開走的列車不是死結；以分鐘批次與逐秒結果相同；參考模型逐秒一致（含 `deadlockedTrains`、`trainHoldingRoute` 與預約）；在待避站存讀後繼續跑結果相同；關閉交通控制後立刻續行。
- `traffic.deadlock` campaign（`DeadlockPropertyTests`，新的 CI shard `campaigns-11`）：8 case × 4 seed，對向的快車與站站停列車、待避線被停著的列車占住的情形，以及跑完後換向再開；每一步比較結果與整個狀態、持有、預約、等待、死結清單、不變量及存讀。digest `42AE3745A3FF09E8`（死結步數 424、留下的死結 11、操作 1352、待避 37、完成服務 111），約 2.5 分鐘；決策 57 融合之前是 `366A22C95DBC8D3F`（618、14、1352、24、101）。
- golden `single-track-passing.json`（schema 30，47 步、10 遊戲分鐘），GameCore 取值、`ReferenceWorldGoldenTests` 獨立確認。
- `SavedGameTests`（版本 8 fixture 與版本 4、6、7 重存逐位元組相同）、GamePresentation 的 `testADeadlockAndAPassingPlaceAreToldInThePlayersWords`。

**Deferred（暫時沒有改的地方）**：事前規劃的排定等待、時刻表交會與待避推估（`inferMeetPassTimes`、`planSameDirectionOvertakes`）：V2 是發生後才解除，不是事前避免；需要換向的折返與調車解法；單線區段的路線容量（決策 22）；地圖上標示死結與授權範圍。

### 59. 排定交會、同向待避與月台成本（Stage V3）

2026-10-05。作者授權本任務修改核心、獨立模型、schema 與存檔版本。從 PR #105 之後的 `origin/main`（`0158d52`）開工；唯讀檢查四份參考 repo main `ddff2be4b4daeee8de3ab31a0a9a6873ad71b79e`。V1／V2 是執行時後備；`ScheduledStop`、`Station` 與決策 22 的路線容量公式沒有改。

**來源與直接移植。** `Railway/site_archive_clean/index.html` 的 `inferMeetPassTimes`／`inferMeetRun`、`reanchorRunProfile`／`applyRunProfile`、`planSameDirectionOvertakes`／`overtakeRunBuildable`、`resolveTraTraffic` 翻成 `ScheduledTraffic.swift`。保留共同站順序、相鄰共同區間先後次序對調、單線區間時間重疊、按距離插值對向通行時刻（沒有共同端點時用保守時間 envelope）、最小調整量／站序／ID 排序、跑段可建性，以及先交會、最多八輪待避、每次待避重算該車交會的順序。常數照搬：300 秒、1800 秒、25 km、30 秒、600 秒；m × 64、km × 64000、秒 × 1。性能沿用 W1 整數，煞停秒數向上取整 `ceil(topSpeed × 1000 / braking)`，加上 30 秒後才准待避。

**必要調整及理由：**

1. 參考的站名／`sections[tracks === 1]` 換成 StationID 與 `parallelTracks(between:and:)`。在名義跑段的相鄰站之間檢查單線；既有 S1 的排除中間車站、同方向可達走廊與平行軌數語義沿用，不另造一張 sections 表。待避／交會位置使用 V1 的 `berths(of:length:)`：同方向能續往下一停靠站、有另一條月台邊、且整個車身放得下，才是可等待站；同軌上兩個停車點不能讓快車越過，故不算第二條待避線。少了必要的月台或方向性續行路就不排，讓 V1／V2 處理。已停在第一停靠站正線上的車不排在原站等待：它不能在原地換到待避線，額外調車不在範圍內；已在待避線的第一站則可以（2026-10-05，PR #110 的修正併入 #111）。
2. 本專案沒有有時刻的「通過站」。從完整時刻表的第一站各方向 berth 求各段無成本的名義最短路，總距離最短者為走廊；平手沿用 berth／edge ID 搜尋順序。沿走廊遇到的其他車站是虛擬通過點，從 W1 曲線反查第一個到達該距離的整秒。沒有物理可建曲線的跑段不插值。虛擬點隸屬前方真正停靠站的 stop／cycle；不修改時刻表。圖上的幾何距離是世界單位，毫秒只是 W1 曲線內部尺度。
3. 參考主要重排通過時刻，遊戲要求列車真的停在區間入口等待。`交會(等它到)` 因此是虛擬站到站後的出發 anchor：對方到站加 `min(30, floor(dwell/3))`，終點 30 秒。`交會(趕它開)` 的同一個 hiMeet 約束改成對向停站車等待該通過車到站／通過加 margin；兩者所需調整量相同。理由是決策 20 不准提前離開排定停站，且誤點時只把通過車的名義曲線提前不能保證它真的趕得上；綁定實際事件才不會放對向車進入已被占用的單線。兩類每次調整仍 ≤300 秒，只看 1800 秒內。前後拆成從靜止起步的 W1 跑段，各自必須可建；保持下一真正停靠的排定到達 anchor，不把等待秒數任意向後傳遞。這是移植到權威執行模型的刻意調整，非照搬參考的浮點觀測 profile。
4. 同向待避沿用來源的 backward scan、`tooClose`、25 km／600 秒與兩段曲線可建性，停到快車開出加 30 秒。來源只在通過站新增 dwell；本專案也准慢車原本停靠的站延長等待（符合任務的停站／待避月台需求）。領先時間仍從兩車到站時刻算，原停留時間能滿足 anchor 時不新增等待。參考 `rebuilt`／`reliedOn` 防止一輪互相循環依賴照搬；平手加 ID，沒有 randomness。
5. 有排定衝突的站才啟用 RailwayCore `01_MIGRATION_MAP.md` §7 的 station、PBS station、停站／通過與月台不合之 generalized route cost。**binary_reference 只有設定名稱與 wasm，未找到可讀預設值**；沒有把自訂值稱為參考值，也沒有逆向 wasm。實作成本：走待避月台邊加 400 m（25,600），通過卻借待避線再加 800 m（51,200），需停站／等待卻選正線 berth 加 800 m。理由：停車位置不合的 800 m 壓過 V1 允許的 400 m 局部繞行，而一般站成本保留正線的優先；總幾何路徑仍不得超過無成本名義路加 V1 的 400 m，所以高成本不會授權任意繞遠路。成本只選路，TrainPath.distance、曲線與帳本仍用真實幾何長度。**正線**是該方向完整無成本名義最短走廊上該站的月台邊，其他平行月台邊為待避線；不是用最大／最小 edge ID 猜。沒有標籤的非典型配置由最短走廊定義，這是 gap 的定案，V4 指定股道可覆蓋它。沒有排定時完全走 V1 的原選擇；V1 避占用／U2 跟車與 V2 仍可作安全後備。
6. 計畫是純狀態推導的 `TrafficPlan`，不存檔、不寫 Station 或 ScheduledStop。來源只含已放置、執行中的時刻表，以及已結束但留有實際見證的服務（等它的車可能還需要那些見證）；沒有列車、未執行的手動時刻表與路線還沒派出的車都不產生假想衝突（2026-10-05 修正，見下）。Web 的系統／日期集合由遊戲的 ID、時刻表 cycle 與遊戲時鐘替代；不引入真實日曆、TRA system filter 或真實站名正規化。
7. 執行解除需要**實際到站**（交會）或**實際出發／通過**（待避），再加 margin；同時不得早於計畫出發 anchor。只到時刻而對方未到，繼續等待。完整 track-span／車身／fouling 預約安全檢查仍優先於出發。實際通過以當秒物理路徑越過該方向 berth 判定，rate 0 或授權截斷不會製造事件。交通控制關閉時不推導、不記新事件、不阻擋服務。
8. **存檔版本 9** 僅新增 `Train.trafficVisits` 的必要實際見證（station、stop、cycle、arrival、可選 departure），空陣列不寫。理由：W2b 的 ServiceTimes 進入下一跑段或完成服務就換掉／清掉，讀檔後無法重建被等車究竟在何時通過、30 秒是否已過；這些事件是執行事實，不是存計畫。只記計畫涉及的訪站；時刻表重設、服務啟停、新派車與取下列車清除；服務完成保留供仍等待的車使用。讀取 1–8 缺欄位時明確遷移為空見證；已越過該真正停靠的舊服務用最後實際到達加 margin 作保守後備。拒絕 null、重複、無效 station／stop／cycle、出發早於到達與未來事件。新增 `v9-scheduled-meet.json`、`v9-scheduled-clearance.json`；所有既有 SaveFixtures 原字節保留。
9. 有排定衝突時在每一整秒邊界處理實際事件與重試，批次不跨過實際解除秒；沒有計畫時沿用既有批次／閒置跳躍。這是精確性優先的必要調整，不增添任意喚醒容差。計畫出發秒與實際加餘裕秒取較晚者；每一步開頭從當時的列車狀態重新推導，同一指令序列與分秒推進結果一致（2026-10-05 修正，見下）。
10. 列車面板等待優先顯示「在 M 等候 X 交會」／「在 M 待避 X」，英文對應 `Waiting at M to meet X`／`Standing aside at M for X`。只新增本任務的兩個 xcstrings 條目；App 檔案結構和 project.yml 不變。

**四份檢查的差異：**網站是 V3 演算法來源；RailwayCore 是立即可移植的成本結構，但預設數值為 gap；`Ci/PROJECT_ABSORPTION_GUIDE.md` Stage U 的優先順序／等待位置／快車超越／單線交會／月台分配是概念，snapshot 更新記錄沒有實作；`Railway/taipei_gta_reference/source/assets/actors-*.js` MRT 是兩條軌的往返、終點 14 秒折返與同線車距／煞車限制，沒有單線交會或待避，V3 對應為「無」。完整四份對照見 RAILWAY_REFERENCE_MAPPING 與 PR。

**測試與驗證：**手算、逐秒獨立模型、誤點、關閉、邊界、ID 平手、存讀／解除精確秒、雙語文字；schema 31 新增 scheduledWaits 觀察、仍讀 schema 30，新增兩份短 golden 的值先由 GameCore 取得，再由 ReferenceWorldGoldenTests 確認。既有 GoldenScenarios／SaveFixtures／ReplayFixtures 的 JSON 一個都不改。獨立 `ReferenceScheduledTraffic` 使用 reverse relaxation 選路、native UInt128 的 `ReferenceTrafficCurve`、另寫的事件越站判定，V3 規劃不呼叫 GameWorld／RunningCurve。新 `traffic.scheduledMeets`：12 case ×4 seeds、1,728 操作，`campaigns-12`；既有 campaign 不縮小。最終 digest 與實際驗證結果記在 PR。

**2026-10-05 修正（PR #109 合併後的審查）。** 合併後發現三個問題，各有在 main 上會失敗的回歸測試（`ScheduledTrafficTests`）：兩列都是重複來回的服務會永久停住且沒有死結顯示；一次長的 advance 和逐秒推進結果不同；待避站續行改走替代路時用了整段排定時間而不是最快曲線。規則改成：

11. **排定路線只是偏好。** 出發與從待避站或排定等待站續行時，排定路線（排定成本選的月台、待避站）只在現在能整條取得時採用，並照排定曲線；否則完全照沒有計畫時的規則：預設路整條、U2 跟車、V1 替代路（決策 56、57），從待避站續行照決策 58 用最快曲線。原因：排定路線取代預設路之後，V1 的方向保護只豁免候選車自己的路，原本預設路走的正線反而變成「新借用」而被禁行；被等的車（停站，所以也偏好待避線）找不到路，等它的車又在那條待避線上等它。排定路線從不經過 V1 替代路，所以 V1 替代路的目的站照 V3 之前一律是呼叫站：#109 曾改成依候選路的路尾決定目的站，連帶改變了 V2 待避站的解除（`traffic.deadlock` 多留下死結），恢復後該 campaign 與 V3 之前完全相同。查詢（`trainHoldingRoute`、死結偵測）照沒有計畫的出發來問；排定路線整條可取得的車會在同一步出發，所以兩者只在出發那一刻之前可能不同。
12. **不等不會來的車。** 從等待的車沿「誰等誰」走下去，回到已經走過的車（互相等）或停在一台正在等進路的車（決策 58 的 `waitingRoute`），這個等待就不成立；被等的服務已經結束而沒有經過該站，等待也解除。這時列車像沒有計畫一樣要進路，V2 的死結偵測看得到它（原本 V3 等待中的列車不算在等，循環永遠找不到也不顯示）。代價：被等的車只是暫時被別的車擋住時，也會提早放行，回到 V1／V2 的處理，安全仍由預約保證。
13. **計畫只看列車狀態。** 第 6 點拿掉路線未派出列車的假想下一趟（它隨時鐘移動）。每一步開頭用當時的列車狀態推導一次，該步的所有決定（出發、續行、死結偵測、見證）都用它；推導依據（每台已放置列車的執行進度與最後見證的 cycle、交通控制）沒變時沿用上次的結果（`DirectionMemo.traffic`）。一步裡的出發或見證改變了推導依據、而新的計畫有排定等待時，這一步只走一秒，下一秒重新推導，和每秒一步完全相同。原本一次 advance 只推導一次，列車在呼叫中進入下一輪時計畫不會更新。

參考模型（`ReferenceWorld`）同樣改成每秒重新推導、排定路線先試整條、不等不會來的車；`traffic.scheduledMeets` 加入重複來回的 case、一次 15–29 分鐘的長推進（每次都和逐秒推進比較），以及「重複來回的 case 結束時還在第一輪的列車必須顯示在死結裡」的檢查。

**2026-10-05 CI 時間（PR #111 合併後）。** 規則不變，結果不變。#111 合併後 main 的 `campaigns-9`、`campaigns-12` 超過 20 分鐘的 job 上限被取消。推導改成不做結果用不到的工作：沒有排定等待時不再找排定路線（沒有等待就沒有成本，也沒有改時刻）；交會推導的「有沒有待避線」只在另一個服務在該點停站時才問，每點一次；`parallelTracks` 在一次推導裡每對相鄰車站只算一次（`TrafficPlan.tracks`）；參考模型的計畫在推導依據（每台已放置列車的服務、時刻表、最後見證的 cycle、在第一站時站的位置，以及交通控制）沒變時沿用（一次 advance 內）。`traffic.following` 移到自己的 class 與 shard（`campaigns-13`），`traffic.scheduledMeets` 每個 seed 的第 9–17 個 case 移到 `campaigns-14`；case 本身不變（每個 case 只由 seed 與 index 產生），只是 digest 分成兩半。

**Deferred（V4 與以後）：**每段路徑／股道／月台指定、單線容量重算（決策 22）留 V4；需要換向的折返／調車解法、地圖授權範圍與死結標示、E3。W1 尚未有的 speed-zone／觀測 profile 不在本輪重新實作；直接用既有 fixed-point 曲線調整上述 anchors。

### 60. 同向待避的實體股道時窗（Stage V4a）

2026-10-05。作者授權本任務修改核心、獨立模型與設計紀錄，取代 AGENTS.md 的分工限制；從最新 `origin/main` `b15de82` 開分支。四份來源均在私有參考 repo main `25229af` 檢查。對 `ddff2be` 的 `planSameDirectionOvertakes` 做函式範圍逐行 diff；V3 常數、排序與決策 59 第 11–13 點仍適用。

**25229af 相對 V3 的差異與處理：**

1. `planSameDirectionOvertakes` 多了必需的 `tracks`，來源缺表就不排待避。遊戲有完整玩家路網，從 V1 方向性 `berths` 與同站進出路徑推導表；無可達股道或無法推導其他車的路線時也不排。
2. `at` 索引納入同站所有服務；`overtakeTrackFree` 在候選站選擇與接受 proposal／建曲線前各檢查一次。兩個接點均移植，不只檢查超越的快車。
3. 時窗 `[慢車到站 − 30, 待避出發 + 30]`，其他車 `departure < lo` 或 `arrival > hi` 才排除，端點包含在內。秒 ×1；負的 lo 合法，hi 飽和避免 Int64 溢位。
4. 來源 `moves` 是同「前站 > 後站｜停靠／通過」派過的所有路線，`dirs` 是各候選停車股道被哪些路線擋住。遊戲用相鄰名義訪站的 StationID、停靠／通過種類與資源集合表達；保持所有已知路線選項。來源 `reach` 的 OR mask 直接翻成 UInt32：只要有一個其他車路線組合可能覆蓋全部候選股道就拒絕，不能只挑對自己有利的一種。0 股拒絕，超過 30 股也照來源拒絕。
5. 同時窗裡已有 `_plannedDwell` 的車，以到站時間、再以車次先後優先：較早者使新待避拒絕，較晚者忽略。遊戲對應 `.overtake` waits，車次依既有 TrainID 順序（決策 59）；proposal 接受後更新的 points／waits 在第二次檢查立即生效。
6. `attachOvertakePeers`／`motion.sidingsFor` 不只關乎畫面：選進站路時列車必須真停到避開時窗內其他車進出資源的 berth。`scheduledBerthPath` 使用同一時窗及各車自己的名義實體路（第一站已停好的車使用實際位置），全車身與 span／限界節點均不得妨礙它們；照 `servedFirst` 忽略較晚／相同到站較大車次的已排定待避，避免互等對方選股。可用 berth 集合交回既有一次廣義成本搜尋，保留 V3 成本及逐步平手；不能逐股取路後只比幾何距離。找不到偏好路或無法整條取得，依決策 59 第 11 點回 V1／V2；不提交半條路，不改 ScheduledStop 或 Station。
7. `noTrack` 是來源統計欄位，遊戲沒有來源的規劃統計面板，因此不新增權威計數器；規則上的拒絕完整保留。

**必要調整及理由：**

- 不把 `tra_overtake_tracks.json` 的 241 站、OSM 股道 id 或站內路線編號當遊戲輸入。該檔 version 1、halfM 137.4 是參考列車中心點前後各半列的資料產物；遊戲車頭為位置、尾部落後 `train.length`，長度是每車 1024 單位，m ×64。由列車自己的車長與 V1 berth 推導全身資源，並使用既有 `network.fouls`／fouling nodes，不能把 137.4 m 寫死為所有列車的身長。
- 來源只用打包且派過的實體 paths；玩家建好的 RailwayNetwork 邊與放得下全列的 TrackPlatform 是遊戲裡可用的實體股道。停靠進出路線表只取本計畫名義服務已使用的路線，不猜未知動線；沒有來源永久 service／electrified tags，不新增柴電限制。相鄰訪站路徑必須前後可接、不倒車、到指定方向的 berth；整個局部繞行仍受 V1 的 400 m 上限。來源 MAX_SPAN=4 的跨多站派車路徑重綁屬於 V4b 的指定路徑，V4a 使用既有逐站名義走廊。
- 來源 ≥20 次／逆向 ≤2% 的單向正線使用統計沒有遊戲歷史資料；規劃排除逆向借用其他名義服務的 traversal（自己的預設共用單線保留），實際偏好路再守 V1 完整執行中服務／已放置路線的方向保護。沒有新增永久 one-way 欄位。取得路時既有 T／U 的全身 envelope、原子預約仍是最後安全判定。
- 來源車次是字串，遊戲使用既有數值 TrainID；來源日期 union 是真實班表可用日期，遊戲使用 V3 的執行中 cycle／實際見證，不引入真實日曆。V3 准延長既有停靠（來源只在通過站新增 dwell）、實際事件解除、八輪重排及固定點曲線保持不變。
- 實景地圖的「正線」仍按決策 59 由名義最短走廊推導，沒有永久正線標籤；猴硐的建造待避線幾何上較短，會成為快車名義走廊，因此此驗收的慢車停到另一條已建實體股道（建造中心線），並檢查全身與快車預約互不妨礙。不能用月台陣列的最後一項判定待避股；V4b 的逐段指定才讓玩家固定通過股道。
- 來源 `routeAt` 會遞迴取得其他車在別站已重綁的整份 pathIds，循環則回原綁定；遊戲尚無這種持久逐段綁定，V4a 使用各車自己的名義局部路與首站實際位置，跨站重綁由 V4b 接續。已取得的實際預約仍由 V1 全資源原子檢查保護，不把名義表當成實際 movement authority。
- 股道與路線表只在一份 TrafficPlan 內暫存不可變的拓撲／路線關係；時窗時間與 planned-dwell 優先每次重新查。新計畫／新指令／存讀不沿用，不存權威計畫。存檔仍 9、golden schema 仍 31，既有三種 fixture 不修改。

**獨立驗證：**ReferenceOvertakeTracks 使用反向距離鬆弛到指定 berth、絕對距離資源時窗與候選索引集合的笛卡兒組合；不呼叫 GameWorld 或 production planner。手算包括三車擋住待避線、時窗兩端、先到優先、相同到站的 ID 平手、未知路線、30 股上限及「每種路線組合都必須留一股」。`traffic.scheduledMeets` 原 18 case ×4 seeds 不縮減，新增 18–23 六個三車 case ×4 seeds，在獨立 campaigns-15–18；每步比較整個世界、計畫、預約、持有、死結、存讀與批次＝逐秒。實景示範新增四腳亭出發、猴硐另一股道待避的同向超越驗收；原三線運行驗收保留。實際 VERIFIED／UNVERIFIED 狀態與 shard 時間見 PR。

**四份來源：**網站是函式與物理換股來源；Ci snapshot 只有快慢車／超越說明與一次 `MIN_TRAIN_GAP` 定義；RailwayCore §7 只有成本結構／設定符號，沒有此股道時窗原始碼；Taipei GTA source 的 MRT 是雙線往返、同線車距與煞車限制，沒有此待避時窗，後三者對 V4a 列為 gap。完整對照見 RAILWAY_REFERENCE_MAPPING 與 PR。

**後續順序：**V4b 指定逐段路徑／股道／月台與存檔 10、schema 32；V4c 單線容量；V4d 中途換向與倒進側線；V4e 授權範圍與死結圖示。每階段各一個 draft PR，前階段經作者合併後才從新的 main 開下一階段；agent 不合併、不啟用 auto-merge。

### 61. 路線與服務模式共用的逐段實體路徑偏好（Stage V4b）

來源固定為私有參考 main `25229af`。`rail-3d/physical/dispatch.json` 的 `plans[trainKey].pathIds` 是逐段實體路徑，`network.json.paths.walk` 以有向 ways 範圍組成路徑；`assignmentBasis: inferred`、`conflictPolicy: scheduled-hold`，另有 arrival／departure holds、departureHolds、handoffs 與 groups。這些是來源資料的語義，不把台鐵站名、車次、OSM id 或現實派車表寫成遊戲規則輸入。四份來源的查核與對照見 RAILWAY_REFERENCE_MAPPING 的 V4b 表。

1. **儲存位置**：新增 `LineRoutePreference`，`from`／`to` 是路線停站索引（區間車也用路線索引），`tracks` 是包含起點邊與終點邊的有向股道 walk，`platform` 是目的站的 `TrackPlatform`（station／edge／start／end）。路線本線 `ServiceLine.routePreferences` 與每個 `LinePattern.routePreferences` 各有自己的偏好，所有同服務模式班次共用。空 walk 只指定月台，路徑仍自動；空偏好陣列全部自動。沒有往 ScheduledStop 或 Station 加資料（決策 20）。
2. **有效性與原子性**：設定指令先檢查路線、區間車，再檢查有向相鄰停靠對；快車的相鄰停靠可以跨越本線數段。往返、環線兩向分開設定。同一對不得重複；目的月台的 station 必須是 `stops[to]`；股道 id 從 1 起，月台 start≥0、end>start，非空 walk 的最後邊必須是月台邊。任何錯誤不改世界（`invalidLineRoutePreference`）。拓撲不連通、月台已拆或股道不存在的偏好可保留：它是計畫，不是基礎設施，讀檔不能因此丟掉玩家重建後仍可用的計畫。
3. **取得路徑**：月台須仍存在且停得下全列。固定 walk 從列車所在有向邊的第一個可用出現位置開始，逐對檢查既有 transitions，不逆向即刻回頭，終點為該月台 V1 berth。距離逐段用 checked Int64 加法，保留真實幾何長度。月台偏好用 V1／V3 一次尋路的 eligible berth 集合，同距離仍取原本逐步股道順序。不能取得偏好就使用原本幾何尋路。
4. **初始月台／朝向**：推導 lineJourney、實際 trip 和交通名義路徑時，先比較可滿足的逐段偏好數，多者先；同數仍比較原本來回秒數（交通名義路徑比較總距離），再保留原本初始 berth／朝向順序。必要理由：較長指定路不能被另一個起點的較短自動路徑蓋過。無偏好時分數都為 0，舊行為與平手完全不變。
5. **執行優先**：V3 排定交會／待避的路徑與時間仍先嘗試；之後嘗試實體偏好，**只有可原子取得整條授權時採用**。拿不到就照決策 59 第 11 點回到原本 V1／U2／V2 路徑、跟車、替代股道或等待；不把偏好路當成永久硬限制，不拿一半偏好授權。交通控制關閉時指定可用 walk，但不建立預約；沒有偏好的關閉控制行為不變。
6. **待避後續行與查詢**：在 V2 passing place 可由固定 walk 的後段重新接回，仍須整條授權；取得時以最快曲線續行，否則按原本 V1／V2。held／deadlock 查詢也檢查完整可用的偏好，不能把有可用偏好路的車報成互等。預約依舊保護 body、span 與限界節點。
7. **名義進出／方向表**：ScheduledTraffic 的各站與通過時刻從指定路徑推導。V4a 的 moves／dirs 用這份 walk 到中間站 berth 的前綴與可重接後段，替代待避 berth 才回局部 V1 搜尋；不重新拿更短的通過路覆蓋指定走廊。方向保護的 memo key 含各段偏好，保護已放置路線與執行服務的全計畫。指定待避股已是名義 berth 時，若同向另一列的同站前後走廊使用不同股道，該名義 berth 也列候選，仍完整檢查 body／moves／dirs。來源是單向班表，遊戲往返重複訪同站；有偏好服務的共站序分成各折返點之間的有向 run，局部走廊用實際正向 head span 的正長度重疊辨識（不同月台可在站外匯合）。無偏好表仍是 V4a 的路徑與順序。
8. **變更中的班次**：只有整份執行時刻表的站序等於當前路線／區間車的完整往返或該環線方向，才依索引套用當前偏好。刪線／刪區間車／改站序後，原班次仍按自己的時刻表跑完，不誤套另一段。改站序若使已有偏好無效，原子拒絕，先清除相關偏好；切換環線模式清除本線偏好，因其有向段集合改變。
9. **月台成本**：沿用決策 59 的 station 400 m、mismatch 800 m 廣義成本及 detour 400 m；明確偏好是整條取路的優先項，不虛構另一組加權常數。RailwayCore §7 列出 `rail_shorter_platform_penalty`、`rail_longer_platform_penalty`／platformMismatchCost，但 clean pack 只有編譯符號與建議公式，沒有可讀的實作或預設值。短月台沿用 V1 全列可停限制，過長月台不加猜測成本。
10. **畫面**：每個服務模式列出各有向路段，可選自動、只指定月台、或固定從各起站 berth 到該月台的有向 walk。選項由已建路網推導，按目的平台、起站 berth、目的 berth 順序去重；不依賴現實地名或股道資料。股道編號與箭頭讓玩家辨識實體路徑，設定由 GameSession 呼叫世界指令，無第二份權威計畫。新增字串有 zh-Hant 台灣用語；新增 UI 測試只放 full lane。
11. **存檔／可攜契約**：版本 **10**，9→10 由路線／區間車 validated decoder 將缺少 routePreferences 遷移為空陣列；explicit null 拒絕。非空陣列才編碼；有向邊寫 `{edge, forward}`，月台寫 `{station, edge, start, end}`。新增 `SaveFixtures/v10-line-route-preferences.json`。golden schema **32** 新增設定指令與路線／區間車偏好觀測，繼續讀 30／31；新增 `GoldenScenarios/line-route-preference.json` 手算 3072／3584 單位、20／21 秒、來回 281 秒。新增 `ReplayFixtures/line-route-preferences.json`；checksum 只在非空偏好時加入相應行，舊 checksum 串不變。所有既有三種 fixture 檔案未修改。
12. **交叉驗證**：ReferenceWorld 用 signed runs、絕對距離時窗及另一份設定／取路／班次比對實作，不呼叫 GameWorld 或 production planner；每步比完整狀態、授權、held、deadlock、計畫、存讀，所有 advance 另比批次＝逐秒。`traffic.lineRoutes` 新 campaign（4 個單列車 case×4 seeds×20 步，加 2 個雙列車／完整往返 case×4 seeds×45 步，共 680 步），獨立 campaigns-19，既有 campaign 不縮減。實景圖新增猴硐指定原有月台的實際停靠驗收；原平溪／宜蘭／深澳發車與無永久停住測試保留。

**必要調整及理由（逐來源）**：

- dispatch 的逐車 pathIds 改為作者要求的路線／服務模式共用 walk；來源的 path→way→node 表改成遊戲有向 edge 與平台，距離 m×64、秒×1、車長 1024／車，整數 checked 加法代替浮點 lengthM。不能把真實 id 當成玩家路網 id。
- `planSameDirectionOvertakes` 來源以單向班表的唯一共站排序與方向判定；有逐段偏好的遊戲服務是完整往返，不能讓回程重複站使去程失去待避。沿現有 reverses 點分向；固定月台不同時比同向實體 span 重疊，不能以月台邊相同當走廊相同。已指定待避股若安全，可留在原股等待，避免為了待避強迫換回正線。提案門檻、平手、重建順序與空股檢查均沿用；沒有偏好的既有 V4a 走原分支。
- arrival／departure holds 仍由 V3 TrafficPlan 與 actual visits 推導，不保存 dispatch 表的派生秒數，避免讀檔後使用過期衝突計畫；scheduled-hold 保留完整預約與實際到站解除語義，偏好不可用退 V1／V2 是作者既有決策 59 第 11 點。
- handoffs 的 matching-timetable-turnaround 用既有一台車跑往返、末站折返與下一趟派車；groups 的資料來源／日期分組沒有遊戲對應資料，不創造現實日期與車次鍵。需要中途換向／調車由 V4d 接續。
- `rail-platform.resolvePlatform` 的 live feed 資料新鮮度與最新事件／矛盾拒選不是玩家設定：遊戲選已建實體月台，驗證目的站與路段，已拆月台回自動，不移植 Date.now 或網路資料到 GameCore。只有此事件歸屬語義是 adapted，feed 的 180000 ms 期限列 gap，不能稱已移植即時月台。
- `stationTrackRef` 是畫面 nearest-track anchor；`sharedTrackGroups`／`boardSharedTrack` 識別共同站對與共線，不是派車路徑選擇。遊戲直接依相同實體 span／限界保護共享路徑，不用站名相等假設股道相等；這些畫面與統計資料沒有添加到規則。
- `Ci/` routeLegs 是班型／班距段，Taipei GTA 的 platform spots 是可步行的捷運場景，兩者沒有逐段 physical dispatch 算法；列 gap，新增玩家選路 API／SwiftUI 操作與獨立 oracle 為本專案補足。

**V4a 合併後修正一併承接**：作者已合併 #116；安全 berth 全域廣義成本／平手搜尋修正（第七項手算）由 V4b 保留。觸控修正已獨立為 #119 並由作者合併；V4b 整合最新 main `d2de3d5`（含 #117 inventory、#118 實景軌道更新及 #119），不再包含 StartSaveFlow 差異。#117 使用私有 `2db0c5a` 作平行移植盤點，本階段四源仍固定 `25229af`，不據此擴大範圍。

**指定待避股的手算事件時窗**：保留的 WIP `fastPassed` failure 是 450 秒觀察時窗早於事件，並非快車阻塞。W→F 距離 `(8192−1024)+16384+8192+1536=33280` 單位，出發 180 秒、抵達 600 秒，跑段 420 秒。無惰行，a=1500、b=2500（換成單位／秒²為 80/3、400/9），由 `L=vT−v²(1/a+1/b)/2` 得巡航速度約 79.69172 單位／秒。edge 3 起點距離 23552，時刻 `180+23552/v+v/(2a)=477.033…`，首次整秒位置為 478；M 名義通過 374，實際通過 388（與原 V3 手算一致），不能只拿名義等待解除證明實際超越。測試改驗精確的 478 秒、600 秒終點到達和慢車續行，保留完整獨立模型、批次＝逐秒、股道佔用與存讀比對。沒有變更 production 規則或既有 fixture 值。

### 62. 由單線與交會站推導服務容量（Stage V4c）

2026-10-05；從作者合併 V4b／修正 #120、#123 後的 main `18ff248` 開分支。四源固定私有 `25229af`。網站 `tra_track_sections.json`／`traSectionKey` 提供站間 tracks；`inferMeetPassTimes`／`inferMeetRun` 檢查對向單線時窗與交會餘裕。Ci 的 `MIN_HEADWAY_MINUTES=1.5`／`enforceMinHeadway` 提供最短班距及按班距限制列車的概念。**四源沒有可直接移植的單線最大列車數公式**；以下是本專案的保守名義容量公式，列 adapted／gap，不宣稱來源原公式或最優排點。

1. **啟用範圍**：只在交通控制啟用時套用。`parallelTracks == 1` 的相鄰站間是單線；0 股是不可達，不當成可用單線，≥2 股維持原容量；環線另比兩向名義 lap 的正長度實體 head span，兩條繞圈弧線不能充當上下行兩股，若兩向同一區間重疊則列單線。方向未知也不能證明 paired 容量。關閉控制、純雙線保留決策 22／24／49 的結果與排序。由 RailwayNetwork、TrackPlatform、V1 berths 推導，不以台鐵站名、OSM id 或來源 tracks 表當玩家路網規則。
2. **交會與資源**：同站有至少兩條不同實體平台邊，均容得下該線全部 roster 最長列車，並可無換向接到前後站，才是可用交會點。兩個同邊停點不算兩股。相鄰單線在不能交會的站合成一個 meet-to-meet block；雙線或可交會站切開。環線首尾在 stop 0 不能交會時相接。取拓撲、可達與全列 fit；當下占用由既有實際預約處理，不能把暫時空股當永久容量。
3. **每趟占用 B（秒）**：對各服務的完整名義往返，累加跨該 block 的 `LineJourney` 跑段秒數；不能交會的已停靠站加 dwell（端點一次 120 秒、中間去回各 60 秒）。到達服務跨度內的可交會 block 端點，各加 30 秒上界餘裕。來源 m 是端點 30 秒或 min(30,floor(dwell/3))；這裡採保守 30 秒上界，非逐事件 faithful 翻譯。未到達的遠方交會點不收費。快車略過交會站時，一段完整跑段時間計入它跨的每個 block，不創造新停站或猜線性中途時間；因此可能低估可排容量。部分區間車占用同一未切 block 的所有段，不能把沒有交會點的相鄰區間分給互相獨立的區間車。
4. **單一服務**：`G=max(2,ceil(max(B)/60))` 分鐘；2 是原 Ci 1.5 min 在遊戲整分鐘 dispatcher 的向上取整，沒有改為小於來源 90 秒。來回 `R=ceil(roundTripSeconds/60)`，一般線最大 `max(1,floor(R/G))`；有效 count 保持原本 requested／target 決策，再受最大限制，`H=max(target?,ceil(R/N))`。requested 設定不被覆寫。單車名義往返不可能超出 R；沒有 passing endpoint 的整條單線 B=完整往返秒數，仍可跑一列。
5. **服務共用預算**：每個 block 每天 86400 秒，服務按既有本線→區間車索引順序使用 `ceil(B*1440/H)`。本線優先和平手不變；用二分找不超過 wanted 且可共用的 count，沒有餘額可為 0。保留原每方向 720 列／日的 segment load 限制，對所有 block 段檢查占用，即使該服務只覆蓋部分站序。不能用 `ceil(1440/H)*B` 把跨午夜的一趟全部重複算入每天。UInt64 full-width 乘除、checked／飽和加法避免 Int64 溢位；預算成立後才累加。
6. **環線**：內外向名義 lap 分別推導，block 的 B 合計兩向跑段與各不能交會站兩次 dwell。每向最大 `floor(innerLapMinutes/G)`，總數乘 2；無法容納一對時可為 0，不能硬塞兩列到無交會的整圈單線。外向不可達也是零 paired 容量。新手算環線沿用唯讀舊 ring geometry：四段各182秒＋四站60秒，內外lap皆968秒／17分；兩向同圈合計1936秒、G=33分，floor(17/33)=0每向，不能強迫至少一對。獨立模型以自己正反Run絕對區間交叉比對，與完整世界一致。純雙線仍沿原 decision 49，公共 lineJourney 仍回內向 lap。
7. **權威與存檔**：查詢、load 及實際 dispatch 使用同公式；一次 advance 的 DispatchMemo 暫存不可變拓撲／名義 profile，結束即丟，無跨指令／存讀權威 cache。執行中班次仍按既有時刻表與 T/U/V 原子授權跑完，不撤銷半條路。沒有新增儲存欄位，SavedGame **10 不變**，不需要格式遷移或新 save fixture；每步存讀驗證 derived 答案一致。golden 行為契約升 **33**，繼續讀 30／31／32，只新增 `single-track-capacity.json`；所有既有 GoldenScenarios／SaveFixtures／ReplayFixtures（含 README）不改。
8. **手算與新 golden**：3072／3584 單位的跑段為 20／21 秒，加兩端各 120 秒，Rsec=B=281、R=5、G=5。request=4 不變；控制關閉最大／有效列車=2、H=ceil(5/2)=3、load=ceil(1440/3)=480；啟用後最大／有效列車=1、H=5、load=288，占用 ceil(281×1440/5)=80928 秒／日。新 fixture 的每個變值均由這些式子手填，不改舊期望值。
9. **獨立驗證**：ReferenceLineCapacity 自己以 signed Run／berth 可達、DFS components 推導 block，用 1440 次整數餘數累加算 utilization，服務 allocation 倒數搜尋，無 GameWorld 或 production capacity helper 呼叫。新增 `line.singleTrackCapacity` 6 case×4 seeds×24 步＝576 步，含有／無交會月台、本線／快車、控制開關、requested count／逐段偏好變更、雙端列車。每步完整狀態、名義計畫、授權／held／deadlock、不變量、存讀；advance 比批次＝逐秒。平溪實景手算：跑段序列 208/140/178/152/115/126/87/115/117/87/126/115/152/178/140/208 秒，往返 3324 秒取整56分。四個 block 分別 2×208+60=476、2×140+60=340、2×(178+152)+120+60=840、888+4×120+30=1398秒；G=24、N=floor(56/24)=2，原 request2 的 H=28分，控制關閉最大28列。新增容量驗收並保留原實景運行驗收；四源映射與 VERIFIED／UNVERIFIED 狀態見 mapping／PR／handoff。
10. **CI 時間**：#123 的全部 780 項已通過，但 SaveMutation 732 秒超過約 560 秒目標。原 14 項方法的全部 seeds／cases／mutations／量下限／assertions 不變，分成兩個 7 項 class 在 campaigns-3／21；新容量 campaign 放 campaigns-22。20 分鐘 timeout 不改，分區／coverage／失敗保護仍由 shard runner 驗證。全套留 CI。

**限制**：這是每線共用 block 的名義穩態上界，不是跨線全域最佳時刻表或即時可取得授權的保證；共享同股的不同路線、誤點與實際占用仍由原預約／排定等待保護。快車整段多 block 計費與固定 30 秒上界刻意保守；不把保守估計包裝成現實台鐵最大容量。clean pack（先 READ_ME／migration §7）及 Taipei GTA（先 READ_ME／source）沒有可讀的單線容量公式，列 gap。下一段中途換向／倒入側線 V4d 仍須作者先合併 V4c。

### 63. 中途站折返與反向側線待避（Stage V4d）

2026-10-05。接續作者已合併的 V4c；保留 PR128 WIP，整合 main `3fd1e9d`。四來源固定私有 `25229af`，詳見 RAILWAY_REFERENCE_MAPPING 的 V4d 表。這是玩家自建拓撲的換向及單次反向待避，不是任意調車搜尋器。

1. **中途折返**：非環線完整往返逐腿先用既有正向 `linePath`（含實體路徑偏好）；只有無路、交通控制 ON、且非首站／遠端終站時，才在該站的全列 berth 翻轉 head／tail 後再找路。保留有正向繞圈時的原選擇。首發 `turnsFirst`、終端既有反向與環線語義不變。`LineJourney.intermediateTurnbacks` 是出發 leg 的索引，推導而非保存。時刻表在對應離站點設既有 `reverses`，只在停站時間結束、取得授權後提交翻向。
2. **時間與量綱**：m×64、sec×1；保留原端點 120 秒、中途 60 秒名義 dwell、實際車門／乘客停留與 W1 加減速。來源 `turnbackProgress` 是既有站間時窗內的動畫 ease，`min(.15,20/window)` 的 20 不是反轉停留秒數；不另加 20 秒。GTA 兩軌端點 layover 14 秒亦不套用。clean pack 只有 reverse penalty 名称，沒有可讀数值，不能杜撰忠實反轉成本。
3. **反向待避**：先保留 V2 正向最近 berth 候選、全程距離／station 平手；找不到時，僅控制 ON 且原列車全車已停於站內才考慮翻向。反向 fallback 枚舉每個非呼叫站所有容全車的 berth，逐一找避開 blocked／forbidden 的進路，確認全程 detour ≤400 m、完整原子預約及限界安全，而且把列車放到該 berth 後確實能放行死結中另一車。選全程距離最短，平手依 station ID、平台既有順序與 forward／backward berth 順序。最近正線停點不能放行，不會遮住稍遠的側線。仍每整分鐘最多調度一車。
4. **待避續行**：先正向，無正向路才 whole-body 反轉以離開 dead-end berth。查詢及候選計算不改世界；取得授權後才提交 head／trail／path，拿不到不先翻車、不保存半條預約。沒有新增待避 dwell：非呼叫站不開門、不上下客，路一安全就按既有最快曲線續行。已倒入側線後關閉控制仍能反向離開；控制 OFF 不啟動新反向解死結。rate 0 暫停物理移動並保留授權，恢復後完成。
5. **計畫與偏好**：逐段偏好比對按實際中途翻向的 placement 走。執行服務用時刻表 `reverses`；尚未派出的路線方向保護也在中途正向無路時嘗試翻向，memo key 包含此規則，避免只保護第一次折返前的軌道。dead-end 待避續行的方向保護包括反向出口。V3 排定等待仍優先，完整預約、body／span／fouling 與替代路方向檢查沒有放寬。
6. **契約**：save **10 不變**，沒有新增權威／Codable 欄位；時刻表既有 reverses、head/trail、passing-place execution 都已有合法表示。測試在停站、倒車途中、側線等待及續行存讀，再接續比對。golden **34** 增加可省略 `intermediateTurnbacks` 摘要，空陣列省略；繼續接受 30–33。只新增 `intermediate-turnbacks.json`，既有三種 fixture 及 README 不修改。
7. **手算**：A–C–B 物理排列、服務 A–B–C，單邊32768，A[2048,4096]、B[24576,26624]、C[12288,14336]。3cars body2048 的四腿22528/12288/12288/22528，三角曲線 `ceil(sqrt(distance*0.12))` 為52/39/39/52，名義542秒；實際 arrival[0,94,193,352,464]、departure[42,154,313,412,464]。golden 的名義點車四腿22528/14336/14336/24576，52/42/42/55秒，加360 dwell=551秒，10分鐘，turnbacks[1,3]。沒有把点車與實際編組當同一長度。
8. **倒側線手算**：SingleTrackMeet 移除 e4、保留 e5/e6 形成東端入口的袋狀側線。e6 的128段取樣整數長4732。A 全車在 e3 的新站平台，與 E→W 車互等；正線 berth 11264雖較近但不能放行，改選側線。倒車2048+4732+5120=11900；在e5翻回後4096+4732+7168=15996；全程27896，相對原4096繞行23800≤25600。測試要求兩車實際完成，不能只以離開死結清單代替。
9. **獨立驗證**：ReferenceWorld 的 signed Run、relaxation 路徑、逐秒推進與另一份全車翻向／候選枚舉，不呼叫 production planner。新增 `traffic.turnbacks` 6cases×4seeds×32步=768，含中途折返、可用／過短側線、出發平台過短、控制開關、rate0／恢復；每步完整狀態／預約／held／等待／死結／invariants、存讀及 batch=second。與原容量 campaign 同在 campaigns-22，原量不變。RealWorldDemo 新增玩家「十分→菁桐→平溪」服務，驗兩次中途折返並回十分，並非聲稱真實台鐵班表。

**限制**：V4c 的名義單線容量（決策62）仍按路線站序的相鄰區段計費，中途折返線在實體上重疊的區段不另行拆分；它只限制請求列車數，實際安全仍由完整預約與死結處理保證。多次調車、無平台倒車與全域最佳解仍是 gap。

**驗證狀態**：見 PR128、接手分支 `claude/takeover-and-complete-mp89w9` 的 draft PR 與 docs/STAGE_V_HANDOFF.txt 的實際 head/run。新重現首跑無候選失敗；修正後雙車完整完成。新 golden 首跑的 final requested count 與 createLine 預設 none 不符，改新增明確設定 count=1 指令，沒有改既有期望值或產品預設。實景新測試首跑 unplace 後 rate=0 未發車，補測試的 setRate 指令後重驗。保留所有失敗記錄，不以早期成功代替最新 head。V4e 仍等作者合併。

### 64. 地圖上的行車授權與死結互等位置（Stage V4e）

2026-10-05。作者合併 V4d（#131，main `812247b`）後開工。四來源固定私有 `25229af`，詳見 RAILWAY_REFERENCE_MAPPING 的 V4e 表。這是 Presentation／App 的顯示，GameCore 只補一個缺少的唯讀查詢，不改任何規則、存檔或 golden。

1. **缺的查詢**：既有公開查詢已有預約（`reservedResources`，即 movement authority）、持有（`heldResources`）、擋住者（`trainHoldingRoute`）與死結（`deadlockedTrains`），沒有「等的那條路被擋在哪裡」。新增 `contestedResources(of:)`：等候路線所需資源中，擋住者持有或 foul（`RailwayNetwork.fouls`，逐一資源判定）的部分；擋住者是 U2 跟隨車時，含它仍在等的路段（與 `holder(of:except:)` 同一判定）。V3 排定等待是依計畫在站等車、不是等軌道，回空陣列。`trainHoldingRoute` 改由同一個 `awaitedRoute` 推導，行為不變。
2. **一次算完**：地圖每次要所有列車，逐車呼叫三個查詢會各自重算交通計畫與方向 memo。新增 `routeWaits()`：同一個 memo 依 ID 順序給出每輛等候車的 holder、contested 與是否死結，必須等於逐一呼叫的結果（性質測試每步比對）。實景 demo 60 分鐘、4 列車：debug build 逐車三查詢約 227 ms／次，改 `routeWaits` 後約 95 ms（實測，Linux）。App 只在時間、列車、路線、路網或控制開關變動時重算，平移縮放不重算。
3. **衍生模型**：GamePresentation 的 `TrafficOverlay`（`GameWorld.trafficOverlay()`）只含世界座標：每車預約的 span 依邊與里程合併相鄰段成折線，加上預約的 junction 節點；每輛等候車的 holder、死結旗標、contested 折線／節點、車頭位置，以及「等的位置」＝contested 上最近車頭的點，沒有 contested（排定等待）時是 holder 車頭。控制關閉為空。不保存、不進 GameSession 權威狀態。
4. **畫法**：四來源都沒有畫 movement authority 或死結；只有 `Railway/site_archive_clean/index.html` 跟隨列車路線的樣式（`followCase` 8.5 寬外框、4.4 寬列車色線、`FOLLOW_DIM` 0.62），移植為授權的畫法：外框色照搬 `followCase`（#fffdf6／#10141c），線寬比 8.5 : 4.4 保留，線色用 `metroGreen`，非選取列車乘 0.62、選取的最後畫且不調暗。位置在路網之上、車站與列車之下。等候：contested 用 1.3 倍寬，黃（`metroAmber`，與既有等候文字同色），死結紅（`metroRed`）；車頭到等的位置畫虛線（整條畫，同隧道虛線理由）；列車之上畫等候車的外圈，死結再加警示符號。來源的 block hold 是畫面延遲（`trainPos` 減 `blockHoldSec`），不是預約，不移植；`_blockCapped` 永不清除，不仿。
5. **文字保留**：列車面板的 `routeWaitText` 原文不變。地圖左上角的小圖例只顯示三種顏色的列車數，不擋點選；VoiceOver 讀 `TrafficOverlay.summary`（「Movement authority for 2 trains · 1 waiting · 2 deadlocked」／「2 列車有行車授權 · 1 列等候 · 2 列死結」），identifier `map.traffic`。
6. **契約**：save **10**、golden schema **34**、既有三種 fixture 與 README、workflow、gate、timeout 都不變。沒有新 App 檔案（不需重產 Xcode 專案）。
7. **手算**：W–M–E（邊 1、2、3 直線，起點 x=1024、9216、25600，y=4096）。0:42 互等：東行車頭在邊 1 的 3072（x=4096），等西行車占用的邊 3 4096–7168（x=29696–32768）；西行車頭在邊 3 的 8192−3072=5120（x=30720），等東行車的邊 1 1024–4096（x=2048–5120）；各自等的位置是最近端 29696、5120，contested 恰為對方 held。1:00 東行在 M 正線（邊 2 的 9216，x=18432）待避，等 M 東端 junction 附近（邊 2 自 14336 起，最近點 x=23552，節點 3 在 x=25600），西行的授權含整條邊 1（x=1024–9216）。
8. **獨立驗證**：ReferenceWorld 另做 `contestedResources`（對擋住者的 `blocking` 集合逐資源 `foul`），在 DeadlockTests 逐秒、`traffic.deadlock` 與 `traffic.turnbacks` campaign 每步比 production；兩個 campaign 也每步比 `routeWaits()` 與逐一查詢。實景 demo 首小時每分鐘檢查授權折線、等候與死結一致，每列車都有授權；新 UI 測試（實景 demo 出現 `map.traffic` 且含 Movement authority）只在 full lane。

**限制**：只顯示目前狀態，沒有預測未來授權或號誌；畫面延遲式 block hold、平行同軌標籤錯位（`blockSideShift`）與死結閃爍仍是 gap。Canvas 繪圖本身不在 Linux 驗證，只由 macOS CI 編譯與 UI 測試。

### 65. 跨站步行轉乘與新遊戲啟用全網路徑（Phase 5F）

2026-10-06。作者指示依優先順序直接移植（轉乘與全網路徑是第 1 項）。四來源固定私有 `2db0c5a`，詳見 RAILWAY_REFERENCE_MAPPING 的 Phase 5F 節。

1. **步行轉乘由距離推導，不存檔**：兩個有服務停靠的不同車站，點與點的平面距離嚴格小於 450 m（`Railway/` 的 `station_transfers.json` `criteria.maxDistanceM` 與 `haversine_meters < maxDistanceM`）就能步行轉乘。時間是同站轉乘的 4 分鐘加上以每分鐘 80 m 走完距離的整分鐘（向上取整；來源沒有步行速度，這是原生政策），在平方距離上精確比較。車站不能移動，所以這是世界的純函數，不新增存檔欄位；`walkingTransferMinutes(from:to:)` 公開。來源的同名規則只用在真實資料的跨系統配對，玩家自己蓋的車站沒有來源系統與站名，因此原生只用距離。資料的明確 pairs 匯入仍是 gap。
2. **路徑圖**：剛下車（onboard）的狀態可以步行到附近車站的任一服務停靠點，成本是步行分鐘＋該服務的半個班距等候，轉乘次數加一。旅程不能以步行開始或結束（只有搭乘抵達迄點），也不會連續步行。`PassengerRoute.transfers` 把換線或換站都算一次。
3. **旅程與上下車**：`PassengerJourney` 的相鄰 leg 可以是同站，或下一段從步行可達的車站開始；連通性由世界檢查（候車群組的 `isServed`、乘車群組的 `riderProblem`），所以把車站搬到 450 m 外的手改存檔會被拒絕。乘客在 A 站下車、下一段從 B 站開始時，直接排進 B 站的佇列，`readyAt` 是下車時刻加步行分鐘；仍歸原起站的守恆帳，B 站滿時記原起站 abandoned。
4. **新遊戲啟用 `.network`**：`GameWorld.newGame()`（App 的空白、實景、示範與教學地圖）設定 `.network`。`GameWorld` 自己的新世界、舊存檔、golden 與 replay 仍是 `.direct`，行為不變。
5. **效能**：網路需求原本每次 `advance` 都重算每對 OD，而且每對都重建路徑圖、每次取出都整個排序候選。現在 (a) 一份計畫共用一張圖；(b) Dijkstra 的 open list 改為二元堆積，比較函數是同一個嚴格全序，取出順序與排序完全相同；(c) 建圖時每個服務只駕駛一次，結果等於逐服務呼叫 `lineHeadway`／`lineJourney`（測試逐服務比對）；(d) 不存檔的 `PassengerRouteMemo` 以衍生的路徑圖本身（服務路徑與步行）為鍵保留每對的選擇，圖不同就整個丟掉，所以不可能過期。實測（Linux，各 60 次一分鐘的 `advance`）：示範地圖 debug build direct 2.3 s；network 未優化 33.0 s，(a)(b) 後 4.5 s，(d) 後 3.8 s。實景 demo（12 站、3 線）在 (a)(b)(d) 之後：debug direct 15.6 s／network 24.3 s，release direct 2.16 s／network 3.23 s（每 tick 約 36／54 ms）。(c) 之後未再量測。
6. **契約**：存檔版本不變（11）：舊存檔都讀得進來；新存檔可能含步行旅程，舊 build 不讀新存檔不是要求。golden、replay、save fixtures 與 README 都不變。

**限制**：沒有站內通道／同月台的分級成本（來源沒有數值），也沒有來源的封站／流量管制 operationMode；步行不檢查站外通道容量。

**修訂（2026-10-06，R1：來源轉乘常數、封站狀態、計畫鍵）**：作者決定保留本決策的架構（共用圖、堆積、memo、`Walk`、新遊戲 `.network`），只把原生常數換成 `Ci/` 來源值，並補上：

1. **常數集中**：所有轉乘常數在 `PassengerTransferRules`（`PassengerRoutes.swift`）一處，各附來源：基準 15 分鐘（`metroDebugCompareCentralToAirportTimings` 的 `r = 15`）、分級係數 overlap 0.8／same-platform 0.8／passage 1.2／virtual 1.7（同函式的 `l`）、分級距離 ≤20／≤50／≤250 m（`MOVE_TRANSFER_*_MAX_M`、`_classifyMoveTransferDistance`），其餘 <450 m 是 virtual（`station_transfers.json`）、步行 5 km/h（`metroNavigationTransfers`）、最短換車 120 s（`METRO_NAVIGATION_MIN_TRANSFER_SEC`）。調整平衡只改一行。
2. **兩種時間分開**：分級懲罰（同站換線＝same-platform 12 分鐘，取代原生 4 分鐘；跨站依距離分級）只是**路徑選擇的感知成本**，加上步行秒數；**實際上車延遲**是 max(120 s, 步行秒數)（同線另一服務 0）。`PassengerRoute.transferMinutes` 是懲罰、`walkMinutes` 是步行；`walkingTransferMinutes(from:to:)` 改為 `walkingTransfer(from:to:)`（`PassengerWalk`：秒數與分級）。
3. **車站營運狀態**：`StationOperationMode` normalFlow／flowControl／closed 與 `setStationOperationMode(_:to:)`（`applyStationOperationToStation`）。flowControl 不再釋出新乘客（`metroStationAllowsEntryForLine`），仍可轉乘、抵達；closed 不上下車、不轉乘、不作迄點（`metroStationAllowsTrainServiceAtStation`／`AllowsTransfer`／`AllowsPassengerDestination`），關站時清空候車（`clearStationWaitingPassengers`）記回原起站，需要它的候車旅程也放棄。列車仍停靠封閉站但不上下車（來源 `metroStationAllowsTrainServiceAtStation`）；收班後的自動狀態 `metroComputeStationAutoOperationMode` 未移植（gap），模式只由玩家設定。設定模式會丟棄釋出計畫，並讓其他車站仍須在此上下車或轉乘的候車旅程離站。讀檔拒絕明寫 `"normalFlow"` 的車站，存檔只有一種寫法。旅程的步行連通只看距離、不看狀態，所以車上乘客的下車站被關閉時存檔仍有效；他們在方向終點離車記 abandoned。直達與網路需求都遵守。存檔版本不變（11）：`Station.operationMode` 只在不是 normalFlow 時寫出、讀檔選填，所以舊存檔照讀（CLAUDE.md：只有舊存檔讀不了的格式才升版）；`SavedGameTests` 驗證帶封站的 v11 存檔往返。App 的車站面板有三段選擇（`GameSession.setSelectedStationOperationMode`，雙語文字）。
4. **計畫鍵**：網路計畫不再於每次 `advance` 丟棄；`PassengerPlanKey`（路徑圖所讀的路線、車站含狀態、路網、交控、列車長度、各線當下等級，以及紀錄、需求、票價）相同時沿用，結果與重算相同（`PassengerPlanKeyTests`）。不存檔，世界相等不看它。
5. **擁擠與需求衰減（R2，原生規則）**：來源沒有公式（`Ci/` 的 `choiceProb` 來自快照外的 flow service，`metroEconomyCollectCrowdingMetrics` 只回報負載；`01_MIGRATION_MAP.md` §6 只列 offered／used capacity 欄位），所以是**原生**、只在 `.network`：每條服務路徑每向一天的供給 = 各等級開放分鐘 ÷ 班距 × 列車容量（無車時 6 × 352）；使用量 = 本計畫各 OD 的日旅次按未擁擠權重以最大餘數分到各選項、累加到每段；擁擠秒數 = 乘車秒數 × 0.15 ×（使用 ÷ 供給）^4（BPR，比例上限 2）；選項權重 = 10000 ÷（整分鐘成本 + 擁擠秒數 ÷ 60），以秒計算，無擁擠時恰等於原權重。需求：一對 OD 最快路徑的廣義分鐘 ≤ 30 時全數，超過按 30 ÷ 分鐘比例遞減（四捨五入）；`dailyDemand` 與計畫一致。計畫仍只是世界的函數（不存檔），計畫鍵加入列車容量與服務日。常數集中於 `PassengerCrowding`。
6. **App 與契約（R3）**：`GameSession.setPassengerRoutingMode(_:)` 經 `GameWorld` 指令切換，路線面板有開關（zh-Hant 字串）；golden schema 35 加 `setPassengerRoutingMode`、`setStationOperationMode`、選填的最終狀態 `passengerRoutingMode`／車站 `operationMode` 與轉乘群組的 `sinceSeconds`／`readyAtSeconds`，既有 fixture 一個值都沒變；`ReferenceWorld` 只有直達路徑，跳過用到這兩個指令的 fixture。

### 66. 車種、每節定員與門數

2026-10-06。作者的移植順序第 2 項。來源：`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` 的 `TRAIN_TYPES`、`getTrainCap`、`getMetroTrainOperationalCap`（固定私有 `2db0c5a`）。

1. **車種表照搬**：`TrainType` 九種，每節額定人數（`ppc`）A 310、B 260、C 200、L 243、D 230、APM 138、磁浮 240、雲軌 140、單軌 224；A、B、C 是來源的主要車種，其餘是額外車種。來源的新線預設 B（`TrainType.referenceDefault`）。
2. **容量**：額定 = 節數 × 每節額定（來源 `round(ppc × cars)`，整數相乘本來就精確）；可載 = 額定 × 1.1 四捨五入（`round(rated × METRO_TRAIN_OPERATIONAL_LOAD_FACTOR)`，以 `(額定 × 11 + 5) / 10` 精確計算）。沒有車種的列車是既有的標準車（每節 320／352），所以舊存檔、golden 與 replay 的行為完全不變；它也是每節最多的，存檔中乘車群組的上限不變。
3. **門數（gap）**：來源沒有車門模型（上車瞬間完成、停站固定 36／42 秒）。原生延續決策 39 的每門每秒 2 人，門數依車種：A、D 5 門，B、C 4 門（與標準車相同），L、磁浮 3 門，APM、雲軌、單軌 2 門。上下車秒數 = 人數 ÷（2 × 門數 × 節數）進位。
4. **命令**：`setTrainType(_:to:)`，`nil` 是標準車；免費，只在列車不在軌道上時（與節數相同）。存檔只在有車種時寫 `"type"`，舊存檔讀成標準車，所以存檔版本不變；未知的車種拒絕。
5. **畫面**：列車控制在節數下方有車種選單（`train.type`），顯示「B型 · 每節 260 人 · 4 門」；App 的新購列車仍是標準車，不改變決策 46 的經濟平衡。依車種的購車價格來源沒有（車廂用配額購買），列為 gap，與營運成本一起在第 3 項處理。

### 67. 貸款與利息（Phase 7）

2026-10-06。作者的移植順序第 3 項（營運成本與公司帳：購車、維修、人事、能源、貸款）。購車（決策 46）、營運與維修（每小時）、能源與人事（每日）已依 `Ci/` 的舊版經濟公式移植（決策 36）；`window.MetroEconomy` 引擎不在快照裡，`Ci/` 與 `Railway/` 都沒有貸款、利息或折舊（`railway_game_reference_clean` 只有 OpenTTD 編譯核心的字串，例如 `EXPENSES_LOAN_INT`、`max_loan`，沒有數值；它的原始碼是 GPL-2.0，沒有收錄）。所以貸款是原生規則（gap → 原生）。

1. **借與還**：`borrow(_:)`／`repayLoan(_:)`，每次 $100,000 的整數倍（`CompanyAccounts.loanStep`），總額最多 $5,000,000（`maximumLoan`，新遊戲起始資金的 5/3）。只有經營模式能借（`loanNeedsManagement`）；自由模式仍能還。還款要有錢（`insufficientFunds`），不合法的金額 `invalidLoanAmount`。失敗不改任何東西。
2. **利息**：每個午夜與能源、人事一起結算，欠款 × 5% ÷ 360（財報的一年 360 天），四捨五入到整美元（$1,000,000 每天 $139）；寫一列 `dailyInterest`（項目 `loanInterest`），餘額可以變負。只在經營模式結算（與其他帳一致）。
3. **財報**：`DayAccount`／`FinanceSummary` 加上 `interestCost`；它不是營運成本，`totalCost` 與 `operatingProfit` 不變，另有 `netProfit` = 營業利益 − 利息。
4. **存檔**：`accounts.loan` 與日帳的 `interestCost` 只在非零時寫，舊存檔讀成沒有貸款，所以存檔版本不變；讀檔拒絕不是整步或超過上限的貸款。golden、replay、save fixtures 都不變（沒有貸款的世界寫出的 JSON 與之前相同）。
5. **畫面**：經濟面板的「貸款」區有欠款與每日利息、借入／償還一步的按鈕與條件；有利息時財報多「利息」與「淨利」兩列。文字都由 GamePresentation 依遊戲語言提供。

**限制**：沒有折舊、資產負債表與信用評等；利率固定。

### 68. 每週需求：平假日係數與週末時段

2026-10-06。作者的移植順序第 4 項（每週需求、平假日、事件與中斷）的第一部分。來源：`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` 的 `METRO_WEEKDAY_FACTORS`、`getWeekdayFactor`、`isWeekend`、`H_FACTOR_WD`／`H_FACTOR_WE`（固定私有 `2db0c5a`）。

1. **每天的旅次**：開啟每週需求時，車站某天出發的旅次 = 每日旅次 × 該日係數（千分比，週日起 840、1040、1020、1020、1040、1120、920，即來源的 0.84…0.92），四捨五入；七天的係數加起來正好是七天。遊戲第 0 天是星期一（來源的 `simDay % 7`，0 是週日，起點來源未定）。分給各迄點的權重仍是迄點的每日旅次。
2. **週末時段**：週六、週日用 `StationDemand.weekendShape`：每小時 = `dayShape` × `H_FACTOR_WE[h] ÷ H_FACTOR_WD[h]`，四捨五入（測試以來源的數值精確重算）。平日照舊用 `dayShape`。來源的 `peakFlowMult`（週末尖峰 0.7）作用於它的流量／班次，不是需求，本遊戲的服務日另有等級，不移植（gap）。
3. **整數釋出不變**：一份計畫只屬於一天。午夜的整分鐘（批量推進的 idle shortcut 也會在午夜醒來）保存 OD 餘數、重建當天的計畫。同一份計畫 1440 分鐘釋出 3600 × 當天旅次個單位，所以每一天正好釋出當天的旅次，一週正好是 7 × 每日旅次（測試逐日驗證）。批量與逐分鐘、存檔續玩都相同。
4. **開關**：`setWeeklyDemand(_:)`，存檔只在開啟時寫 `"weeklyDemand": true`。`GameWorld` 的新世界與舊存檔關閉（golden、replay、save fixtures 不變）；`GameWorld.newGame()` 開啟。

**限制**：事件（展覽、大量人潮）與中斷（停駛、封站）、國定假日尚未移植：來源的事件產生器 `MetroEconomy.advanceMetroEvents` 不在快照，需原生的種子與事件模型，之後的 PR 處理。

### 69. 需求事件：展覽與大量人潮

2026-10-06。作者的移植順序第 4 項的第二部分。來源：`Ci/.../app__q_c234188b7c397f91.js` 的 `metroUpdateDemandEvents`、`metroEventStationTrafficWeights`、`metroEventDemandMultiplier`、事件文字 `metro.event.exhibition`／`crowdSurge`；`aviation_disruptions__q_dc8f79f5de24b024.js` 的 FNV-1a 雜湊亂數與事件節奏（固定私有 `2db0c5a`）。捷運事件的產生器 `MetroEconomy.advanceMetroEvents` 不在快照。

1. **確定性**：`DemandEventSchedule` 存種子（`UInt32`）、未結束的事件、下一次抽籤的日子與抽籤次數。每個隨機值是 FNV-1a 32 位元對 `種子|鍵` 的雜湊（來源 `d(state, key)`），鍵含抽籤序號，所以與推進方式無關；批量、逐分鐘、存檔續玩都相同（測試）。符合跨階段議題「隨機性由存檔的種子雜湊產生」。
2. **節奏**：第一次在 3–7 天後，之後每 8–12 天（來源 `firstMin/firstMax`、`gapMin/gapMax` 的秒數換成整天），除以 `max(1, 有需求的車站數 ÷ 10)`。事件以整天為單位，在午夜開始與結束；午夜時先處理事件，再重建當天的需求計畫（與決策 68 共用每日計畫）。
3. **抽站**：依車站的每日旅次加權，最熱的前五分之一（無條件進位）乘 10（來源 `metroEventStationTrafficWeights`，以流量／最大流量並乘 10）。
4. **種類與數值（gap → 原生）**：展覽持續 3–7 天、需求 +20%–50%；大量人潮 1–2 天、+50%–100%；都在 2–5 天前公布。來源的捷運事件數值在缺少的引擎裡。
5. **效果**：車站的需求倍數 = 1 + 進行中事件的最大加成（來源 `1 + max(boost)`），乘在它當天出發的旅次上，也乘在它作為迄點的吸引權重上（來源提高車站的進出流量）。
6. **開關**：`setDemandEvents(seed:)`，`nil` 關閉。`GameWorld` 的新世界與舊存檔關閉（golden、replay、save fixtures 不變）；`GameWorld.newGame(eventSeed:)` 開啟，App 的新遊戲用隨機種子。讀檔檢查事件的形狀、車站存在、已公布且未結束。
7. **畫面**：車站面板「活動」區列出公布或進行中的事件（「大型展覽：需求 +35%，2 天後開始，持續 5 天」）。

**限制**：中斷（停駛、封站、颱風）與國定假日尚未移植。封站的營運模式已由決策 65 的 R1 修訂加入（`setStationOperationMode`），事件自動封站尚未接上。

### 70. 城鎮成長（Phase 6 的第一步）

2026-10-06。作者的移植順序第 5 項（城鎮成長與產業，A 列車的核心循環）。來源檢查：`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` 第 9 項「Town growth / industry demand」只列出 OpenTTD 的 `src/town_cmd.cpp`、`src/industry_cmd.cpp`、`src/subsidy.cpp` 路徑並要求它們「consume transport accessibility metrics rather than directly controlling train movement」，原始碼與數值不在參考包；`Ci/` 沒有成長規則（人口格與 poptravel 只是資料與畫面）；`Railway/site_archive_clean`、`taipei_gta_reference` 也沒有。所以規則是原生的（gap → 原生），只讀遊戲已有的量測，不控制列車。

1. **量測**：服務 = 昨天從該站出發、已抵達迄點的乘客（該站守恆帳 `arrived` 的日增量）佔當天旅次的比例；可達性 = 昨天的釋出計畫裡該站有旅次的迄點數（第 1 項的全網路徑）。
2. **成長率**（每日千分比）：滿載服務 +10（1%），每個可達車站 +1，最多 5 個，所以每天最多 +1.5%；整天沒有任何乘客抵達則 −2（−0.2%）。四捨五入，正成長至少 +1 人次。
3. **範圍**：每站第一次被看到時記下起點（`base`），最多長到起點的 4 倍（也不超過 `maximumDailyTrips`），衰退不低於起點。
4. **時點**：每個午夜先成長、再處理事件、再重建當天的需求計畫；批量推進會在午夜醒來，所以批量、逐分鐘、存檔續玩都相同（測試）。只有經營模式成長：自由模式由玩家設定運量。
5. **存檔**：`townGrowth`（每站的起點、上次午夜的抵達數、上次成長率）只在開啟時寫；`GameWorld` 的新世界與舊存檔關閉，golden、replay、save fixtures 不變。`GameWorld.newGame()` 開啟。
6. **畫面**：車站面板的運量下方顯示「每日旅次由 1,000 成長到 1,250 · 昨日 +1.2%」。

**限制**：沒有土地使用、建物、地價與人口格的連動；產業（貨物）沒有模型；起點之外的上限是固定倍數。這些是 Phase 6 之後的工作。

### 71. 車站與路線更名、路線自訂顏色

2026-10-06。作者「隨時」一項的小型資料模型。來源：`Ci/.../app__q_c234188b7c397f91.js` 的 `PRESET_COLORS`（20 色）與路線的 `color`、車站與路線的名稱編輯（固定私有 `2db0c5a`）。

1. **命令**：`renameStation(_:to:)`、`renameLine(_:to:)`（同建立時的名稱規則，免費）、`setLineColor(_:to:)`（`LineColor`，`0xRRGGBB`，`nil` 是 App 依 ID 的配色；免費，沒有規則讀它）。
2. **存檔**：名稱本來就存；顏色只在設定時寫 `"color"`（整數），讀檔拒絕 `0...0xFFFFFF` 以外的值。舊存檔都讀得進來，所以**不升存檔版本**（作者曾說兩者可以一起進一次升版；格式是向後相容的新增，依規則不需要升版）。golden、replay、save fixtures 不變。
3. **畫面**：車站面板最上方「車站更名」、路線面板選取的路線有「更名」與「顏色」選單（自動＋來源 20 色）；路線列表的圓點與跟隨列的圓點用自訂顏色。

建造的 Undo／Redo 仍未做（工作量大，另做）。

### 72. 土地（Phase 6a）

2026-10-07。作者決定開始 Phase 6 的「土地使用與建物」，並採用研究文件（PR #172，`docs/research/PHASE6_LAND_USE_STUDY.md`）審查時的建議：64 m 的隱藏網格、每格一種主要用途、空白模式以種子產生起始聚落、實景模式用人口資料（沒有涵蓋的地方同空白模式）、800 m 服務範圍、舊存檔保留現有的車站需求。來源檢查（私有參考 `2db0c5a`）：四處參考都沒有可移植的土地、居民、就業或成長模型（`Ci/` 的 `city.pmtiles` 語意圖沒有收錄，人口格只決定新站初始運量；參考包只有 OpenTTD `town_cmd.cpp` 的路徑；`Railway/` 與 `taipei_gta_reference` 的建物與街區只是畫面），所以規則是原生的（gap），對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#phase-6a土地決策-72)。

1. **網格**：土地是 4096 × 4096 世界單位（64 m）的格，從世界原點起算（`Land.cellLength`），`Land.columns(in:)`、`rows(in:)` 由世界範圍推導，最後一列／行可以超出邊界。網格不畫出、不約束鐵路與車站（決策 28、54 的連續世界不變），只有土地按格計。最大世界 256 × 256 格。
2. **格的內容**：`LandCell { row, column, use, residents, jobs }`；用途 `residential`、`commercial`、`office`（第一版只有這三種，空地就是沒有列出）；居民與就業各 0 到 100,000（`Land.maximumPerCell`，遠超真實城市，只有損壞的存檔會碰到），不能都是 0。`GameWorld.land` 依列、再依行遞增，每格一次。
3. **指令**：`setLand(_:)` 以任意順序的格整個替換土地（`[]` 清除），世界外、重複、數量超出範圍或空的格以 `invalidLand` 拒絕，世界不變；`foundTowns(seed:)` 以 `Land.towns(seed:in:)` 替換土地。兩者免費，GamePresentation 在開新遊戲時呼叫。
4. **起始城鎮**（gap，原生）：三座。第一座在世界中心（地圖打開的地方），半徑 12 格（768 m），中心格 260 人；第二座在中心東或西 2–5 km、北或南 2–5 km（象限由種子抽出），第三座在對角象限同樣遠，半徑 7–10 格、中心格 160–240 人（密度在 6b 定案：最早是 130 與 80–120，運量改由土地推導後，第一條線要 33 天才回本，加倍後是 8 天，合乎決策 46 的約十天，見決策 73）。離中心 `d` 格（`d² < r²`）的格有 `peak × ((r² − d²) × 1000 / r²) / 1000` 人（每一步向下取整）；核心（`9d² < r²`）每格抽出商業或辦公，住四分之一的人、提供三倍的就業；其餘是住宅。抽籤是 `SeedDraw`：種子與鍵的 FNV-1a（需求事件同一套，從 `DemandEventSchedule` 抽出共用，雜湊值不變）。三座城鎮不會重疊（外側兩座離中心兩個方向都至少 2 km，最寬的兩座半徑 768 m 與 640 m）。種子 1 在新遊戲的地圖上是 887 格、90,900 位居民、67,413 個就業；第一座城鎮 437 格、50,189 位居民、33,276 個就業。
5. **實景地圖**（GamePresentation 的 `LandImport`，畫面層用 Double，只在開局算一次）：每個 64 m 格取中心點所在的 WorldPop 格；WorldPop 格的人平均分給它的 64 m 格，餘數依列優先順序給前面的格（最大餘數法）。完全在世界裡的 WorldPop 格保留全部的人；碰到世界邊緣的（有一格在第一或最後一列／行）以「面積 ÷ 64² m²」四捨五入為份數，只拿裡面的部分。就業與用途在 6b 加入（決策 73）。世界裡沒有人（台灣以外、全是海）時改用起始城鎮。台北車站為中心的新遊戲約 64,800 格、469 萬人（WorldPop 中心落在地圖裡的格合計 4,777,604，邊緣只取部分）、206 萬個就業，存檔約 420 KB；Linux debug build 匯入約 0.09 秒。存檔只存格，之後不再讀人口資料。
6. **查詢**：`Land.cell(row:column:)`、`cell(at:)`、`totals(within:of:)`（格的中心離那一點的平方距離小於半徑平方，精確整數）；`GameWorld.landCatchment(of:)` 是車站 800 m（`Land.catchmentRadius` = 51,200 單位）內的居民與就業。
7. **存檔**：版本 12。土地只在有時寫 `"land"`：同一列相鄰、同用途的格寫成一段 `{ "row", "column", "use", "residents": [...], "jobs": [...] }`（`jobs` 全為 0 時省略）；讀檔檢查順序、範圍與世界邊界。版本 11 以前沒有土地；只讀到 11 的 build 會丟掉土地，所以升版。
8. **6a 的規則還不讀它**：需求仍是各站自己的（`StationDemand`）；改由土地推導需求、重疊腹地的分配與土地的成長是 6b（決策 73）。golden schema 36（`foundTowns`、`setLand`、`landCatchment`、`landCell`、`land-towns.json`），既有 fixture 的預期值都沒有改變；`ReferenceWorld` 不含土地，`LandTests` 另有逐格重算的參考實作。replay 只在有土地時把每格寫進狀態描述，既有錄製的 checksum 不變。
9. **畫面**：空白地圖的「人口密度」圖層畫土地（每格的居民換算成每平方公里，用人口圖層同一套色階；實景地圖仍畫 WorldPop）；車站面板的「土地」欄顯示 800 公尺內的居民與就業。

**限制**：只有住宅、商業、辦公三種用途，沒有工業、公園、水域與建物；地價、建物與費用是 6c 之後。

### 73. 運量由土地推導（Phase 6b）

2026-10-07。作者把 6b 的決定交給 Claude Code（「用你覺得對遊戲最好的決定」）。來源檢查同決策 72：`Ci/` 的人口→就業→旅次在沒有收錄的後端（`/api/flowFull`），參考包只有 OpenTTD 城鎮的路徑，所以規則是原生的（gap），建立在既有的需求模型上。

1. **開關**：`GameWorld.landDemand`（`setLandDemand(_:)`）。開啟而且公司是經營模式時，每座車站的運量由它分到的土地決定；GameCore 的新世界與舊存檔關閉（照舊），App 的新遊戲開啟。自由模式的運量仍由玩家設定，土地不改它；切回經營模式時土地重新決定每一站。關閉時每站保留土地給的運量，玩家可以再設定。
2. **何時推導**：開啟時、建站時（新站從鄰站分走一部分）、土地被設定或建立城鎮時、切到經營模式時，以及每個午夜成長之後。推導出來的運量寫進車站的 `StationDemand`（之後的釋出、事件、票價與路徑照舊讀它）；推導的時點固定，所以批量、逐分鐘與存檔續玩相同。土地決定運量時，`setStationDemand` 以 `stationDemandFromLand` 拒絕。
3. **分配**（`LandDemand.shares(of:among:)`）：格的中心在某站 800 m 內就屬於那一站的腹地；在幾站的腹地裡時，依 `1000 − ⌊1000 d² / R²⌋`（1 到 1000，越近越多）以最大餘數法分給它們，平手給編號小的站；居民與就業分開分。每個人、每個就業只算一次。
4. **運量**（`LandDemand.Share.demand`）：分到的居民與就業，每 100 個每天 40 旅次（實景地圖新站的每 100 位居民 40 旅次，決策 50），四捨五入，最多 1,000,000。就業也產生旅次：早上從住宅出發、傍晚從辦公與商店出發，既有的重力模型再依各站的旅次分配去向，不另設吸引力。類型是佔最多的：居民（住宅）、辦公的就業（辦公）、商店的就業（購物），平手依這個順序。沒有旅次時沒有需求。
5. **土地成長**（取代決策 70 的每站成長，只在土地決定運量時；決策 70 的世界照舊）：每個午夜，城鎮成長看過的每一站依決策 70 算出昨天的成長率 `g`（服務比例最多 +10‰、可達車站每個 +1‰ 最多 5 個；沒有服務 −2‰）。依車站編號，每個 `g > 0` 的站：
   - 它分到的居民 `R` 增加 `max(1, (R × g + 500) / 1000)`，依腹地裡各格的居民以最大餘數法分配，每格最多長到 400 人（約每平方公里 98,000 人）；就業同樣，每格最多 1,200；放不下的不加（6c 的建物再提高上限）；
   - 在腹地裡、世界內、旁邊（上下左右）有人的空格中，離車站最近的一格（再依列、行）蓋一格 4 位居民的住宅：城鎮沿著好的服務往車站長。
   土地不衰退。之後重新推導運量；每站的 `lastGrowth` 是它每日旅次的實際變化（千分比），車站面板照舊顯示。
6. **實景地圖的就業**（`LandImport`）：打包的 OSM 地點（同一個 WorldPop 格網）每個算作 `LandImport.jobsPerPlace` 個就業：商店 25、辦公 500、學校 300、景點 50（OSM 幾乎每間商店都有、辦公大樓很少，所以一個辦公點代表很多人；全台合計約 856 萬，略少於人口的五分之二，約是工作人口）。和居民一樣平均分到 64 m 格；格的用途是辦公與學校的就業最多時為辦公、商店與景點最多時為商業，其餘住宅。台北車站單獨一站時，800 m 內約 4.3 萬居民、11.5 萬就業，是辦公站，每日 63,514 旅次。
7. **平衡**：起始城鎮的密度加倍（決策 72 第 4 點），新遊戲在第一座城鎮蓋三站一車的第一條線約 8 天回本（`NewGameBalanceTests`，決策 46 的約十天）。示範地圖與實景示範關閉土地需求，保留它們給每站的運量（畫面與測試依賴那些數字），土地仍在地圖上。
8. **存檔與 fixture**：`"landDemand": true` 只在開啟時寫，併入存檔版本 12（6a、6b 同一個尚未發佈的 PR）；新的 `SaveFixtures/v12-land-demand.json`。golden schema 36 加上 `setLandDemand`、`stationDemandFromLand`、最終狀態的 `landDemand` 與手算的 `land-demand.json`；`land-towns.json` 的數值隨密度加倍（同一個 PR 裡的新 fixture）。既有 fixture 的預期值都沒有改變；replay 只在開啟時寫 `landDemand`，既有 checksum 不變。`LandDemandTests` 有分配與一天成長的逐格參考實作，以及成長在批量、逐分鐘、存檔續玩都相同的測試。

**限制**：土地不衰退、只往外長住宅；成長上限是固定的密度（6c 的建物再決定容量）；就業不成長成新的辦公格；類型只取最多的一種，不混合時段曲線；實景就業的係數是遊戲的數字；示範地圖還沒有改用土地需求。

### 74. 城市建物、容量表與初始化（Phase 6c-1）

2026-10-07。作者同意研究文件（PR #174，`docs/research/PHASE6C_BUILDINGS_STUDY.md` §5、§7、§10）的 6c-1 範圍，並定案下面的作法；與研究文件不同的一點是第 4 項的選級只看主要用途。來源檢查（私有參考 `2db0c5a`）：`Ci/` 的建物只是向量圖磚的 2D／3D extrusion（`liberty.json` 的 `building`、`building-3d` 讀 `render_height`），`Railway/taipei_gta_reference` 的 `floorsFor`、`pickType` 與區域樓層範圍（例如 `[2,6]`、`[10,40]`）只決定外觀，`rail-3d` 的 Blender／歷史建物只有模型與地理錨點；四處都沒有居民、就業容量或建物升級規則，所以容量表與規則是原生的（gap），對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#phase-6c-1城市建物決策-74)。

1. **誰蓋**：一般建物（住宅、商業、辦公）由城市自動產生，之後（6c-2）自動升級；沒有玩家的建造、升級或拆除指令。玩家自建的公司建物是 Phase 7。
2. **資料**（`City/Building.swift`）：`Building { id, kind, use, density, cells }`：`BuildingID` 從 1 依序配發；`kind` 是 `city`（一般建物）或 `existingStock`（既有存量，密度一律 D4）；`use` 是那幾格土地的用途；`density` 是 D1–D4；`cells` 是佔用的格（`CellPosition`）。不存座標、旋轉、輪廓或模型，那些是畫面層的事。第一版一棟建物佔一格。`GameWorld.buildings`（`CityBuildings`）依 ID 遞增，每格最多一棟。
3. **容量表**（每格；`Building.tableCapacity(of:_:)`）：每層樓板 1536 m²（4096 m² 的八分之三）、每位居民 48 m²、每個就業 32 m²，D1–D4 是 2／6／18／40 層；住宅、商業、辦公的樓板各有 7／2／1 個八分之一是住家，其餘是工作。容量 = 樓板 × 住家八分之幾 ÷ 8 ÷ 48 與樓板 × 其餘 ÷ 8 ÷ 32，每步向下取整（都沒有餘數）：

   | 用途 | D1 | D2 | D3 | D4 |
   | --- | --- | --- | --- | --- |
   | 住宅（居民／就業） | 56／12 | 168／36 | 504／108 | 1120／240 |
   | 商業 | 16／72 | 48／216 | 144／648 | 320／1440 |
   | 辦公 | 8／84 | 24／252 | 72／756 | 160／1680 |

4. **選級**（`Building.fitting(_:id:)`）：只看主要用途的人數：住宅格依居民數，商業與辦公格依就業數，選最低足夠的密度。另一項（住宅格的就業、商辦格的居民）的容量取表上的值與現有人數較大者，不裁掉任何人（例如台北最滿的辦公格 78 居民／285 就業是辦公 D3，容量 78／756；若兩項都要放得下，它會被迫選 40 層的 D4）。主要用途四級都放不下時建既有存量：兩項容量都是現有人數與 D4 的較大者。容量由建物與那一格的人數推導（`Building.capacity(on:)`、`GameWorld.buildingCapacity(row:column:)`／`buildingCapacity(at:)`），不另存；土地不衰退，6c-2 的成長也不會超過容量，所以既有存量不會自己提高。
5. **開關**：`GameWorld.cityBuildings`（`setCityBuildings(_:)`）。開啟時依上一項為每一格土地建一棟，依列、再依行從 1 編號；關閉時建物全部移除。App 的新遊戲（`GameWorld.newGame`）開啟；GameCore 的新世界與舊存檔關閉。
6. **與土地同步**：開啟時 `setLand(_:)`、`foundTowns(seed:)` 先驗證、再一起換掉土地與建物（重新從 1 編號），被拒絕的土地不改兩者；6b 的擴張（`spread`）新增 4 人住宅格時同時建立住宅 D1 建物，編號接在最後；沒有編號可用時（只有手改的存檔會碰到）連土地也不加。有人的格一定有建物、建物只在有人的格上，而且用途相同，讀檔也檢查（`buildingProblem()`）。
7. **6c-1 只記錄容量**：成長上限仍是每格 400 居民、1200 就業（決策 73），建物不自動升級，不新增 `lastService`／`lastReached`，沒有地價；這些是 6c-2、6c-3。所以建物開或關，土地的成長完全相同（測試），成長可能讓一格的人數超過它的表上容量，6c-2 再處理（已超過的保留、不倒扣）。
8. **存檔**：版本 13。`"cityBuildings": true` 只在開啟時寫；`"buildings"` 是同一列相鄰、編號相連、同用途同種類的一格建物寫成一段 `{ "id", "row", "column", "use", "density": [1–4, ...], "kind" }`（`kind` 只在既有存量時寫），台北的約 6.5 萬棟約與土地同樣多段。遷移：版本 12 以前沒有建物，讀成關閉，照舊用 400／1200；之後開啟才依當時的土地建物。新的 `SaveFixtures/v13-city-buildings.json`；既有 fixture 都沒有改。
9. **Golden 與 replay**：schema 37 加上 `setCityBuildings`、`setTownGrowth` 指令、`building` 觀察與最終狀態選填的 `cityBuildings`，手算的 `city-buildings.json` 與 `city-buildings-growth.json`，另以獨立的 Python 實作（`tools/golden-checks/city_buildings.py`）核對；既有 fixture 的預期值都沒有改變。replay 只在開啟時寫建物，既有 checksum 不變。
10. **實算**：種子 1 的新遊戲（887 格）是住宅 D1 200、D2 416、D3 168，商業 D3 18、D4 33，辦公 D3 47、D4 5，沒有既有存量；台北（錨點 25.047882, 121.517219，64,829 格）是住宅 26,392／32,303／2,214／0，商業 1,462／0／0／0，辦公 390／1,873／195／0（D1–D4），沒有 D4，也沒有既有存量。
11. **畫面**：車站面板的「土地」欄加一行 800 公尺內的建物：「800 公尺內建物：低層 88 棟 · 中層 188 棟 · 高層 134 棟 · 超高層 27 棟」，有既有存量時加「既有存量 n 棟」。

**限制**：一棟一格；容量還不限制成長、建物不升級（6c-2）；沒有地價（6c-3）；地標不供容量；沒有禁建遮罩，邊緣不足 64 m 的格仍按一整格計容量。

### 75. 容量接上成長、自動升級（Phase 6c-2）

2026-10-07。作者定案研究文件（PR #174，`docs/research/PHASE6C_BUILDINGS_STUDY.md`）§6.1、§7.1、§7.2 的作法。來源檢查（私有參考 `2db0c5a`）：`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §9 只列 `town_cmd.cpp` 的路徑並要求城鎮「consume transport accessibility metrics」，同檔的固定 tick 順序是經濟之後才城鎮（`EconomySystem.tick()` → `TownSystem.tick()`）；四處參考都沒有建物升級、容量限制或服務門檻，所以門檻與配額是原生的（gap），對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#phase-6c-2容量接上成長與自動升級決策-75)。

1. **容量取代固定上限**：城市建物開啟（決策 74）時，6b 的 `grow` 每格改用該格建物的容量（`Building.capacity(on:)`），不再另外套 `LandDemand.grownResidents`／`grownJobs`（400／1200）；居民與就業各自限制。已達或超過容量的那一項保留原值、不倒扣；放不下的成長直接捨棄，不轉給其他格、不留到隔天。城市建物關閉的世界照舊用 400／1200。分配、成長率、站序與最大餘數都不變。
2. **兩個量測欄位**：`TownGrowth.Place` 加 `lastService`（0…1000）與 `lastReached`（0…5），由 `growLand` 每晚更新一次：`lastService` 是 `TownGrowth.serviceShare(served:trips:)`（served ≤ 0 為 0、served ≥ trips 為 1000、其餘 `floor(served × 1000 / trips)`，與 `TownGrowth.growth` 用的同一個比例，`growth` 也改呼叫它，值不變）；`lastReached` 是 `min(reached, 5)`。第一次看到的站與舊存檔都是 0。`counted`、`lastGrowth` 保持原意。決策 70 的每站成長（土地需求關閉）不更新它們。
3. **自動升級**（`LandDemand.upgradesPerStation` = 2、`upgradeService` = 800、`upgradeReached` = 1，原生）：午夜開始時先快照「已滿」的一般建物（D1–D3，居民或就業任一項達到或超過正的容量）。依車站編號遞增，每個今晚 `g > 0`、`lastService ≥ 800`、`lastReached ≥ 1` 的站，在自己腹地裡依（列、行）遞增，把快照中、今晚還沒有站升過的格各升一級，最多 2 格；較小編號的站先選，已升過的格後面的站略過、不佔配額，所以同一格一天最多一級。D4 與既有存量不升，當晚才滿的格與當晚擴張的新格不在快照裡。升級只改密度，不改用途、人數或建物編號，不用亂數。每站依「升級 → 成長 → 擴張」執行，所以剛升級的格當晚就能長進新容量。快照與「今晚升過」都在午夜重算，不存檔。
4. **決定性**：午夜的順序固定，升級與成長只讀當時的世界；批量、逐分鐘、任意切分、午夜前後存檔續玩與閒置跨越午夜都相同（`CityGrowthTests.testTheCityGrowsTheSameHoweverTheDaysAreAdvanced`）。
5. **存檔**：版本 14。`"lastService"`、`"lastReached"` 只在不是 0 時寫（明確的 `null` 拒絕，超出範圍拒絕）；版本 13 以前讀成 0，下一個午夜才量測。新的 `SaveFixtures/v14-city-growth.json`；既有 fixture 都沒有改。
6. **Golden 與 replay**：schema 38 加上 `townGrowth` 觀察（`base`、`lastGrowth`、`lastService`、`lastReached`），新的 `city-buildings-raise.json`（容量限制成長、每站兩格的配額、重疊腹地一天一級、當晚才滿不升、D4 與既有存量不升），另以獨立的 Python 實作（`tools/golden-checks/city_growth.py`）核對；既有 fixture 的預期值都沒有改變（`city-buildings-growth.json` 的格都沒有滿、也沒有碰到容量，結果相同）。replay 只在量測不是 0 時寫，既有 checksum 不變。
7. **平衡**：新遊戲在第一座城鎮蓋三站一車的線，30 天後 971 格、110,742 位居民、80,499 個就業，116 次升級（住宅 D2 → D3 為主，辦公 D3 → D4）；容量讓居民比沒有建物時少約 0.5%。第一條線約 8.03 天回本（`NewGameBalanceTests`，7–14 天）。
8. **畫面**：車站面板的土地欄改成「800 公尺內各密度的格：低層 88 格 · ……」（決策 74 第 11 項的「建物 … 棟」），並加一行「昨日：旅次服務 100% · 可達 2 站 · 滿格的建物會升級」，不符合時寫出條件。

**限制**：沒有地價（6c-3）、玩家建物（Phase 7）、土地衰退或 D4 以上的密度；升級只看服務與可達，不看地價；邊格與地標規則同決策 74。

### 76. 地價與城市圖層（Phase 6c-3、6d）

2026-10-07。作者定案研究文件（PR #174，`docs/research/PHASE6C_BUILDINGS_STUDY.md`）§6 的地價與 6d 的城市圖層。來源檢查（私有參考 `2db0c5a`，以及加入 `Simulator/` 的 `3a19671`）：四處參考都沒有地價、租金、房地產或開發規則（研究文件 §4 的關鍵字搜尋；`Ci/` 的土地用途圖來自沒有收錄的向量圖磚），`Simulator/` 是模型火車佈景模擬器，建物只是佈景；所以公式、係數與圖層的顏色都是原生的（gap），對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#phase-6c-36d地價與城市圖層決策-76)。

1. **只是查詢**：`GameWorld.landValue(row:column:) -> LandValue?`（世界外為 `nil`）與一次算整張圖的 `landValues()`、`landValues(rows:columns:)`。`LandValue` 有總價（美分／m²）與分項 `base`、`servicePremium`、`accessPremium`、決定價格的車站（可能為 `nil`）。不存檔、不存歷史、不進帳本，沒有交易、租金或費用（Phase 7）。存檔版本不變。
2. **公式**（`LandValueRules`，全部整數、原生）：`base = floor(B × D / 1000)`；B 是用途基準（空格 1000、住宅 2000、商業 3000、辦公 3500 美分／m²，用途取建物的，沒有建物時取土地格的）；D 是密度係數（D1 1000、D2 1250、D3 1600、D4 2000，既有存量用它的 D4，沒有建物 1000）。每個腹地涵蓋這格（`d² < R²`，R = 51,200）而且 `lastService > 0` 的站算 `score = floor(w × lastService / 1000)`，`w = 1000 − floor(d² × 1000 / R²)`；取 score 最高的站（平手取編號小的），S 是它的 score、A 是它的 `lastReached`，沒有符合的站時 S = A = 0。`value = clamp(base + 15 × S + 1000 × A, 500, 50000)`。土地不決定運量的世界（自由模式、土地需求關閉或沒有城鎮成長）S = A = 0。目前的係數下最高是辦公 D4 滿服務、可達 5 站的 27,000（$270／m²）。
3. **不回頭影響規則**：成長與升級（決策 75）都不讀地價，6c-2 的規則一律不變。
4. **畫面**（GamePresentation 的 `CityMap`，6d）：地圖圖層表多三個圖層，和人口、旅次三個同一組（`PopTravelMode` 的 `landUse`、`landValue`、`coverage`），一次只顯示一個：
   - 用途：住宅綠、商業藍、辦公橙，密度越高顏色越深（既有存量畫成 D4）；
   - 地價：9 段色階（$0、20、40、60、90、120、160、200、250+／m²），圖例寫單位；只畫有土地或比沒有服務的空格值錢的格；
   - 腹地涵蓋：車站 800 m 內有人的格與沒人的格兩種藍，有人但不在任何車站腹地的格洋紅色。
   `CityMap(world:)` 在土地、建物、車站或城鎮成長的量測改變時（而且只在城市圖層開著時）才重算一次，台北實景新遊戲整張 65,536 格在 Linux debug 約 0.07 秒；畫的時候只取畫面內的格，縮小時合併成 2、4、8… 格的區塊（同 `PopulationHeatmap`），所以一次最多畫幾千個矩形。點一格的提示框寫用途、密度、居民、就業、地價與三個分項、決定價格的車站。實景地圖開用途圖層時，Apple 地圖蓋一層 60% 的底色，讓格的顏色不和底圖的建物混在一起。
5. **車站面板**：土地欄加「腹地平均地價：每平方公尺 $ …」（800 m 內每格地價的平均，空格也算）。
6. **Golden**：schema 39 加上 `landValue` 觀察（`row`、`column`，回答總價、三個分項與車站），手算的 `land-value.json`，另以獨立的 Python 實作（`tools/golden-checks/land_value.py`）核對；既有的預期值都沒有改。replay 不變。

**限制**：沒有交易、租金、費用與價格歷史（Phase 7）；地價只看用途、密度與最好的一站，不看離市中心的距離或周邊的格；圖層沒有隨時間的動畫。

### 77. 滿格只看主要用途、關閉的車站不分土地（修正決策 75、73）

2026-10-07。作者把 #160–#178 審查留下的待決項交給 Claude Code（「用你覺得對遊戲最佳的方式」）。兩項規則改變，都是原生的（gap），參考庫沒有對應的規則。

1. **滿格只看主要用途**（修正決策 75 第 3 項）：午夜快照的「已滿」改成只比主要用途的人數與表上的容量：住宅看居民、商業與辦公看就業，和決策 74 選密度的依據相同。另一項（住宅的就業、商辦的居民）的容量仍是表上的值與現有人數的較大者，只用來限制成長、不再觸發升級。原因：那一項只要達到表上的值，容量就等於現有人數，永遠「已滿」；台北實景新遊戲開局時，D4 以下的一般建物只有 446 格是主要人數滿的，卻有 20,930 格只因另一項而算滿，有服務的車站每晚都把配額用在這些格上，升級和居民或就業的成長無關。種子 1 的空白新遊戲沒有這種格（8 格與 0 格），所以新遊戲的平衡與決策 75 的報告不變。
2. **關閉的車站不分土地**（修正決策 73 第 3 項）：`LandDemand.shares` 只在沒有關閉的車站間分配（`GameWorld.landStations`）。關閉的站沒有運量、不成長、不決定地價（決策 76），腹地也不算進涵蓋圖層；它的腹地由鄰站依原本的距離權重分回。重新開啟時立刻分回它的那一份。限制進站（flow control）的站照舊分配：它只是暫時不讓人進站，乘客仍可轉乘與到達，也免得開開關關讓鄰站的運量跳動。`setStationOperationMode` 之後重新推導運量。
3. **相容性**：存檔格式不變（不升版）。既有 golden、replay 與 save fixture 的預期值都沒有改變：`city-buildings-raise.json` 的升級格都是主要人數滿的，有車站營運模式的 fixture 都沒有開土地需求，`v14-city-growth.json` 續玩的升級也相同。`CityGrowthTests` 的參考實作改成同一條規則，並加上只有另一項滿時不升級的測試；`LandDemandTests` 加上關站、限制進站與重開的測試。

### 78. 示範地圖改用土地決定運量（修正決策 73 第 7 項）

2026-10-07。作者要求下一版 TestFlight 的實機測試能看到「運量由土地決定、城鎮成長、建物升級、地價」，所以空白示範地圖（`DemoWorld`）要和 App 的經營新遊戲一樣，不能再保留固定運量。參考庫沒有示範地圖的城市（gap），城鎮的形狀沿用決策 72 第 4 點。

1. **空白示範地圖用新遊戲的設定**：`DemoWorld` 本來就從 `GameWorld.newGame()` 開始（土地、城市建物、土地決定運量、城鎮成長、週需求、需求事件都開著），不再 `setLandDemand(false)`，也不再設定每站的 `StationDemand`；每站的運量由它分到的土地推導（決策 73），之後每個午夜照常成長、升級（決策 75、77），地價與城市圖層照常（決策 76）。
2. **示範的城市**（`DemoWorld.land(replacingTheMiddleOf:in:)`，GamePresentation）：示範的五站都在 Central 的 144 m 內，腹地幾乎完全重疊，新遊戲的第一座城鎮（約 8.3 萬位居民與就業）分給五站只有每天約 3.5 萬旅次，示範的三條線、四列車每天的營運成本 $262,174，每天虧 $89,569。所以示範地圖用自己的城市取代第一座城鎮：同樣的公式（離中心 `d` 格的格有 `peak × ((r² − d²) × 1000 / r²) / 1000` 人，中間三分之一是商辦，住四分之一的人、提供三倍的就業），半徑 14 格（896 m，幾乎每格都在某站的 800 m 內），中心格 600 人；商辦格在中心那一行以西是辦公、其餘是商業（原本由種子抽，示範地圖取固定的配置，土地用途圖層看得出辦公區與商店街）。合計 609 格、154,938 位居民、117,108 個就業。新遊戲另外兩座城鎮（種子 1，離中心 2 km 以上）不變，留給玩家延伸路線。
3. **結果**：開局每站約 2.1–2.3 萬旅次（西 21,012、中央 21,191、東 22,647、北 21,009、南 22,642，五站都是住宅類型），合計約 10.9 萬，比原本固定的 8 萬多；第一個整天的營運利潤 $301,823，示範的建設費 $2,291,200 約 7.6 天回本（第二天 $296,066、7.7 天；原本固定運量 $153,668、約 14.9 天），合乎決策 46／73 新遊戲第一條線約 8 天的目標（`NewGameBalanceTests`）。服務好的五站每天成長約 0.8%，城鎮往車站長出新的住宅格，滿格的 D1–D3 建物每晚升級（開局 D1–D4 為 168／344／439／108 格，十天後 185／318／413／160）。中心 54 個商辦格的就業超過 D4 的容量，是既有存量（決策 74），不升級。
4. **實景示範不改**：`RealWorldDemo` 仍關閉土地需求、保留每站的運量。平溪線一帶大多是靠景點的運量，土地沒有景點；用 WorldPop 與 OSM 的土地推導，12 站合計每天只有約 1.4 萬旅次（十分 405、菁桐 552），沒有 App 的人口資料時是 0。土地仍在地圖上，圖層照常。
5. **相容性**：GameCore 不變；存檔格式、golden schema 都不變，既有 golden、save fixture 與 replay 的預期值都沒有改變（`SaveFixtures/` 的示範存檔是之前寫好的檔案，照舊讀得進來）。示範的路網、建設費（$2,291,200）與站名都不變，所以 UI 測試依賴的 Central 在地圖中心照舊。

**限制**：示範的城市比新遊戲的第一座城鎮大、密（約 3.3 倍的人），因為示範有三條線、四列車的營運成本；五站腹地重疊，運量類型都是住宅。實景示範仍是固定運量。

### 79. 音樂與音效

2026-10-07。作者要求遊戲的聲音和第一支介紹影片一樣：影片的配樂與音效成為遊戲的音樂與音效。不是 Stage，GameCore 不變，存檔版本不變。

1. **來源**：`tools/audio/make_game_audio.py` 用正弦波與固定種子的雜訊合成（沒有取樣或第三方音源），和影片的配樂是同一套合成：I – vi – IV – V 的和弦墊、琶音與鐵軌接縫聲，以及到站鈴、「咻」聲與鐵軌接縫。每次輸出相同。音樂 100 bpm，兩輪和弦正好 38.4 秒、1,843,200 個取樣，是 IMA4 封包（64 個取樣）的整數倍，所以 `music-loop.caf` 結尾沒有補零、循環沒有空隙。檔案在 `RailwayGameApp/Resources/Audio/`。
2. **音效由世界推導**（GamePresentation 的 `SoundCue`）：`GameSession` 只說要播什麼，由 App 播放；音效不改變世界，也不存檔。
   - 到站（到站鈴）：遊戲迴圈推進前記下每台營運中列車的 `ServiceTimes.arrival`，推進後比較。推進前已在服務中的列車，到站時刻變了就是到站（600× 下一個 tick 內到站又離站也算）；這次推進才開始服務的列車，要停在後面的一站、而且到站不早於離開前一站（`arrival >= departure`）才算。所以開始服務與路線派車（GameCore 當成在第一站到站）不響；600× 下路線在整分鐘派車、42 秒後出發，也在同一個 tick 裡，這時列車還在路上，`arrival < departure`，不響。手動送車（沒有服務）不響。只記到站時刻，不保留推進前的整個世界，避免每個 tick 複製被改動的狀態。
   - 到站分兩種（`SoundCue.arrival(watched:)`）：玩家在看的列車（鏡頭跟隨的、地圖上點選的、列車工具開著時選取的，`GameSession.watchedTrainIDs`）正常音量；其他列車小聲，而且最多每 6 秒一次，路網忙的時候不會一直響。
   - 鋪軌（鐵軌接縫聲）：路網工具建好一段軌道或 X 型交叉渡線時；被拒絕時不響。
   - 換場（「咻」）：換工具、開始遊戲，或從遊戲回到開始畫面時。
3. **播放**（App 的 `GameAudio`，AVFoundation）：音訊工作階段是 ambient：和其他 App 的聲音混在一起，靜音開關會讓它安靜。音樂只在 App 於前景時循環播放；來電、鬧鐘或其他 App 中斷音訊之後，iOS 通知中斷結束時接著播（App 沒有離開前景時也是，例如從橫幅拒接來電）。同一種音效有最短間隔（在看的列車的到站鈴 0.5 秒、其他列車的 6 秒、「咻」0.25 秒、接縫聲 0.1 秒），高速時多台列車同時到站只響一次。「設定」畫面（開始畫面與遊戲選單都能打開）有「音樂」與「音效」兩個開關，存在裝置上（`UserDefaults`），不在存檔裡。

**限制**：只有到站、鋪軌與換場三種音效；沒有音量調整；這次推進才開始服務、又在同一個 tick 內到站並離開下一站的列車不響（要派車、行駛、停站與出發都在一個 tick 內，1200× 也很少見）；服務結束與重新派車並出發都在同一個 tick 內時會多響一次。

### 80. 路線編輯：自動排入車站、反轉站序、複製路線

2026-10-08。移植 MapBuilder（`MapBuilder/reference_snapshot/_next/static/chunks/611-2cd22d6d6f5c40f4.js`）的三個路線編輯：`handleAddStationToLine` 與它挑位置的 `ef`、`handleReverseStationOrder`、`handleLineDuplicate`。存檔格式不變（不升版），golden、replay 與 save fixture 都不變。

1. **自動排入車站**（GamePresentation，`LineStopEditing.insertionIndex(of:into:)` 與 `GameSession.addStationToSelectedLine(_:)`）：照 `ef` 對每個位置（第一站前、兩站之間、最後一站後）算分數：路線在那裡轉的角度（兩段方位角的差，0…180°；車站離兩端連線的距離換成弧度的「度」若較大就用它）÷ 180，加上新的一段長度 ÷ 典型距離（車站到各站距離排序後第 min(9, (n − 1) / 2) 個）。取分數最低而且不超過 2 的，同分取後面的；都超過 2 時放第一站前；不到兩站時也放第一站前。方位與距離在平面上算（世界單位，弧度的「度」以 turf 的地球半徑 6,371,008.8 m 換算）。這是浮點數，但只用來選位置，結果交給 `setLineStops`，由 GameCore 檢查。**只用在既有路線**：建立新路線的草稿（`lineDraft`）照舊依點選順序，教學的「建立路線」步驟與 UI 測試不受影響。插入後服務模式照舊停在清單上的相同位置（Stage C2 的規則，路線面板的說明也這樣寫）。
2. **反轉站序**（GameCore，`GameWorld.reverseLineStops(_:)`）：站序倒過來；每個服務模式的停靠與每條路徑偏好的起訖索引 `i` 換成 `n − 1 − i`（停靠再排回遞增），所以服務模式停的站、偏好的實體路徑都跟著原本的車站。環線改成往另一個方向繞，所以內環與外環的上次發車時間對調。等車的乘客若路線不再經過他們的行程就離開（`abandoned`），和 `setLineStops` 相同。免費。決策 134 起只有沒有列車的路線能反轉（原本「指派的列車不變，已發出的列車照自己的時刻表跑完」會讓路線停擺）。
3. **複製路線**（GameCore，`GameWorld.duplicateLine(_:named:)`）：新路線拿下一個路線 ID，複製站序、路徑偏好、性能、營運時間、各等級列車數、目標班距、服務模式（不含列車與上次發車時間）、環線與顏色；**不複製列車**，因為一台列車只屬於一條路線，新路線要指派列車才會發車，上次發車時間也是空的。名稱照參考加「 - Fork」（中文「 - 分支」）。免費。名稱空白、路線不存在、ID 用完時拒絕，世界不變。
4. **畫面**（App 的 `LinesPanel`）：站序區加「加入車站（自動排入適當位置）」選單與「反轉站序」，路線區加「複製路線」。三者都經過 `perform`，所以都能復原（決策 82）；複製後選取新路線。字串有 zh-Hant。

**限制**：參考的刪除車站（`handleStationDelete`）沒有移植，車站目前仍不能拆除；參考的 `handleRemoveStationFromLine` 依車站移除，這裡沿用依位置移除。`Ci/` 的 `metroRemapLineOperationsAfterMiddleStationInsert` 在中間插站後會把快車停靠與路徑偏好的索引往後移；這裡照 Stage C2 的規則讓服務模式停在相同位置，沒有改。

### 81. 轉乘群組

2026-10-08。移植 MapBuilder 的轉乘站（`handleCreateInterchange`、`handleRemoveStationFromInterchange`，`interchanges`）與 `Ci/` 捷運遊戲的轉乘群組（`transferGroupId`、`metroSameTransferStationRef`）。決策 65 的步行轉乘只到 450 m 內的車站，`PassengerTransferRules` 的註解原本就寫明參考「超過步行距離的車站只能透過玩家建立的轉乘群組相連」；這裡補上那個群組。存檔版本 15。

1. **資料**（GameCore，`TransferGroup`、`TransferGroupID`、`GameWorld.transferGroups`）：每個群組有自己的 ID（從 1 起，`nextTransferGroupID`，存檔）與至少兩個車站，依 ID 遞增；一個車站最多在一個群組。
2. **連結**（`GameWorld.linkTransfer(_:_:)`，照 `handleCreateInterchange`）：兩站都不在群組時建立新群組（下一個 ID）；一站在群組時另一站加入；兩站各在不同群組時合併成一個，保留站數多的群組的 ID（一樣多時取第一站的），另一個群組刪除；已經在同一群組時不變。車站不存在時拒絕（`unknownStation`），同一站拒絕（新的 `invalidTransferGroup`），ID 用完時拒絕。免費。參考的 `ey`（依連線長度排站序，只用來畫轉乘站的連線）沒有移植：群組的站一律依 ID 排。
3. **離開**（`GameWorld.unlinkTransfer(_:)`，照 `ev`）：車站離開群組，剩一站時群組刪除，它的 ID 不再發出；不在群組時不變。需要這段步行的等車乘客離開（`abandoned`，`abandonUnservedPassengers` 檢查行程各段能否相接），守恆不變。
4. **乘客**：同一群組的兩站之間，不論距離都可以步行轉乘：`walkingTransfer(from:to:)` 與路徑圖的步行邊都納入群組。轉乘等級照距離分（決策 65 的 overlap／same-platform／passage），450 m 以上算 virtual（15 分鐘 × 1.7）；步行時間照 5 km/h 算，實際等候是 max(120 s, 步行)。例如相距 600 m：步行 432 秒（顯示 8 分鐘），轉乘成本 26 分鐘。群組不影響旅次的起訖、票價與守恆帳（照舊算在原起站），也不把到達群組裡的另一站當成到達（`Ci/` 的 `metroHasReachedDestAtTransferGroup` 沒有移植）。
5. **ID 與復原**：復原（決策 82）把整份世界換回快照，`nextTransferGroupID` 也一起倒回，所以「建立群組 → 復原 → 再建立」會拿到同一個 ID；世界照樣有效、能存檔（`TransferGroupSessionTests`）。
6. **存檔**：版本 15。世界只在有群組時寫 `"transferGroups"`，發過 ID 時寫 `"nextTransferGroupID"`；版本 14 以前讀成沒有群組、ID 從 1 發。讀檔檢查：ID 遞增且小於下一個 ID、每組至少兩站且依序、車站存在、一站只在一組。新的 `SaveFixtures/v15-transfer-group.json`；既有 fixture 都沒有改，golden 與 replay 不變（新的拒絕名稱 `invalidTransferGroup` 只加在測試的對照表）。
7. **畫面**（App 的 `StationPanel`）：車站面板加「轉乘」區：顯示群組（「A / B / C」，照 `Ci/` 的 `_buildTransferGroupDisplayName`）、「設為轉乘」選單（最近的 20 站，附距離）與「離開轉乘群組」。都經過 `perform`，可以復原。字串有 zh-Hant。

**限制**：群組不改變轉乘等級以外的規則（例如不讓群組變成同站轉乘的 12 分鐘）；參考的轉乘類型（`transferType`）不另存，一律由距離決定。

### 82. 復原（undo）

2026-10-08。移植 MapBuilder 的 `handleUndo`（`MapBuilder/reference_snapshot/_next/static/chunks/611-2cd22d6d6f5c40f4.js`）：每次編輯前存一份完整快照，上限是 `B.I6`（模組 73277 的 `O`，在 `pages/_app-70b32b07723ca1d7.js`，值是 25）。三個並行 PR 協調時本來分配 79，但 79 已經是「音樂與音效」，所以用 82。GameCore 不變，存檔格式、golden、replay 都不變。

1. **統一的編輯入口**：`GameSession.performEdit(_:)`（GamePresentation，`public`）在 `world` 的副本上執行指令，成功才把原本的世界推進復原紀錄、換上副本，並回傳指令的回傳值；指令拋出時（`throws(GameError)`，或不會失敗的指令）世界與紀錄都不變，即使指令在拋出前已經改了副本的一部分（failure atomicity）。成功但世界沒有變（`==`）時不留快照，免得復原一步什麼都沒發生。`GameSession` 原本所有改變世界的操作都改走它：`perform(_:)`（建造／拆除軌道、交叉渡線、月台與車站、路線與服務模式、列車與時刻表、車站運量與營運模式、票價、交通控制、乘客路徑、貸款、服務日、性能……）都經過它，原本直接改世界的 `setEconomyMode` 與 `setSelectedTrainRate` 也改走它。之後的新指令一律接上 `performEdit` 或 `perform`。
2. **不算編輯**：暫停、改速度、選取、工具、相機、圖層、草稿都不推快照；遊戲迴圈的 `advance` 也不是編輯。
3. **紀錄**：快照就是整份 `GameWorld`（值型別，未改的部分共用儲存空間），最多 `GameSession.undoLimit`（25）份，超過時丟掉最舊的。拖動中會一直改值的控制項（例如綁 `selectedTrainRate` 的滑桿）在 `onEditingChanged` 呼叫 `beginEditGesture()`／`endEditGesture()`：一次拖動只有第一個真的改變世界的值推一份快照（拖動開始時的世界），一次復原回到拖動前；拖動中有 tick 清空紀錄、或拖動中復原，下一個改變再推一份。參考的歷史含目前狀態、最多 26 份，可以退 25 步，相同。紀錄只在 session 裡、不存檔。
4. **時鐘前進就清空**：`advance(realElapsed:)` 只要走了任何 tick（`advance(ticks:)` 成功），立刻清空整個紀錄；暫停時真實時間不變成 tick，所以紀錄保留。實際上只有暫停時，或兩次 tick 之間的編輯能復原；這避免復原把列車、乘客與帳倒回過去，讓遊戲時間與世界不一致。新遊戲、讀檔、繼續與回開始畫面都是新的 session（或沒有 session），紀錄是空的。參考是編輯器，沒有時鐘，這是本專案的決定。
5. **還原**：`GameSession.undo()` 把整份世界換成最後一份快照，包含資金（建造費退回，與參考一致；拆除本來不退款，復原會把拆掉的東西放回來）。暫停與速度不是編輯，所以保留目前的（`setSpeed(runningSpeed)`，暫停中再 `pause()`）；遊戲時間就是快照的時間，因為走過任何 tick 紀錄就清空了。還原後放掉指向已不存在實體的選取與草稿：選取的車站、月台要接的車站、路線草稿裡不存在的站、選取／點選／跟隨的列車、選取的路線、路網工具指到不存在的節點或邊的起點、終點與邊上位置；選取的點不是實體，保留。紀錄是空的時候顯示「沒有可復原的編輯。」（參考的 `Undo history is empty`）。
6. **教學期間停用**：教學的步驟用第一次顯示時看到的 ID 判斷「新的」軌道、車站、路線與列車，而復原會把計數器也倒回去，下一個車站會拿到被復原的那個 ID；在第二個「蓋車站」步驟復原再重蓋，Next 會一直等第二座車站。所以教學在畫面上時 `canUndo` 是 `false`、`undo()` 拒絕並說明，復原按鈕也隱藏（和控制項的展開按鈕一樣，教學的聚光位置不變）。教學結束後紀錄照常可用。
7. **畫面**：工具列（`ControlPanel` 的工具選擇器右邊）加一個復原按鈕（`arrow.uturn.backward`，`controls.undo`），`canUndo` 為 `false` 時停用。字串有 zh-Hant。

**限制**：沒有重做（參考也沒有）；目前 App 沒有列車速率滑桿（只有暫停／恢復列車），`beginEditGesture()`／`endEditGesture()` 只有 GamePresentation 的測試在用；遊戲在跑的時候幾乎每 0.1 秒就有一個 tick，所以要先暫停才能復原。

### 83. 拆除車站

2026-10-08。移植 MapBuilder 的 `handleStationDelete`（`MapBuilder/reference_snapshot/_next/static/chunks/611-2cd22d6d6f5c40f4.js`）與 `Ci/` 捷運遊戲的 `confirmDeleteStationAllLines`、`_applyRemoveStationFromLine`、`clearStationWaitingPassengers`（`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`）。Phase 2B 起延後的「拆除車站」（ROADMAP Phase 2B、Stage N）補上。存檔格式不變（不升版），golden、replay 與 save fixture 都不變；沒有新的 `GameError`。對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#拆除車站決策-83)。

1. **指令**（GameCore，`GameWorld.removeStation(_:)`）：免費、不退款（和拆軌道相同；`Ci/` 退還里程配額，本專案沒有配額經濟）。車站 ID 不再發出。
2. **拒絕**（依序）：不存在的車站（`unknownStation`）；有列車的服務停靠這站、需要它的月台（和 `removeTrackPlatform` 相同的 `serviceNeeds`），或車上載著從這站出發、要到這站或在這站換車的乘客時，`trainServiceActive` 指出編號最小的那台（作者決定：先停止經過這站的列車，所以車上不會有乘客要處理；路線的列車要先離開路線才能停止）；交通控制下有列車持有月台所在軌段的區段時 `trackReserved`。拒絕時世界不變。參考是編輯器，刪站後重新派車（`spawnTrains`），沒有這些條件。
3. **在站裡等車的乘客**：照 `Ci/` 封站的 `clearStationWaitingPassengers`（決策 65 的 `abandonPassengers(waitingAt:)`），全部離開，算在各自的起站放棄。`Ci/` 刪站時車站物件連同它的計數一起消失；這裡車站的乘客紀錄（需求、帳本、餘數）也一起刪除，所以從這站出發、正在別站等車的旅客跟著這站的帳本一起消失，不算在任何一站。其他站要到這站、經過或在這站換車的旅客，照 `setLineStops` 的 `abandonUnservedPassengers` 離開，算在起站放棄。其他站給這站的需求餘數、經過這站的路線分配（`passengerRouteBalances`）一起刪除。
4. **路線**（`ServiceLine.removingStation(_:)`）：照 MapBuilder 把它從每條路線的站序拿掉。原本夾在同一站兩次之間時合成一站（環線也看最後一站與第一站）。剩下的站不足（非環線少於 2 站、環線少於 3 站）時整條路線刪除，照 `Ci/` 的「已删除不足两站的线路」（`metro.edit.line.deleted_too_short`），和 `removeLine` 相同：它的列車不再屬於路線。服務模式照新的索引停靠原本的車站；剩不到 2 站的服務模式刪除，和 `removeLinePattern` 相同（`reindexPassengerJourneys`）。路徑偏好跟著原本兩站之間的那一段；終點是這站、或那一段不再是路線走的段時刪除（`ServiceLine.isValidRoute(_:order:)`，從 `validRoutePreferences` 抽出，規則不變）。
5. **列車**：沒有在跑服務的列車，時刻表拿掉這站；重複的時刻表剩 0 站時不再重複；它的交通到訪紀錄清空（和 `setTrainTimetable` 相同）。在跑服務的列車（一定沒有停靠這站）只拿掉在這站的到訪紀錄。
6. **其他**：月台全部拆除；車站離開轉乘群組，剩一站的群組刪除（ID 不再發出）；這站的需求事件與城鎮成長紀錄刪除；經營模式下，鄰近車站收回它的腹地（`refreshLandDemand`）。
7. **畫面**（GamePresentation 的 `GameSession.removeSelectedStation()`、App 的 `StationPanel`）：車站面板最下面加「拆除車站」，先確認（說明月台、路線與等車乘客會怎樣，不退款）。經過 `performEdit`，可以復原（決策 82）。成功後放掉指向已不存在實體的選取與草稿（`dropSelectionOfMissing`，原本只在復原後呼叫）。被路線的列車擋下時，訊息說要先讓它離開路線再停止服務。字串有 zh-Hant。

**限制**：只拆一整座車站；`Ci/` 的「只從這條線移除」（`confirmDeleteStationSingleLine`）用既有的路線站序編輯；不能在地圖上直接拆，要從車站面板；拆站不會順便拆掉月台所在的軌道。

### 84. 地圖畫出路線、共線區段與轉乘群組，改用 App 圖示的畫風

2026-10-08，作者決定：地圖畫法不等 Phase 8，先換成 App 圖示的畫風，並畫出路線與轉乘群組（補上決策 81 的限制「地圖還不畫群組的連線」）。移植 MapBuilder 的地圖（`MapBuilder/reference_snapshot/_next/static/chunks/352-cc4c9866d08d4d04.js` 的 `js-Map-segments--solid` 與 `js-Map-interchanges--inner`／`--outer` 圖層；共線區段與偏移在 `pages/_app-70b32b07723ca1d7.js` 建立）。只改畫面：GameCore、存檔、golden、replay 都不變。對照見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md#地圖畫出路線共線區段與轉乘群組決策-84)。

1. **路線沿軌道畫**（GamePresentation，`LineMap(world:)`）：MapBuilder 的路線是站到站的直線；這裡的路線跑在軌道上，所以沿列車實際走的軌道畫：每條路線取本線服務的行程（`lineJourney(_:)`，環線是一圈），從第一站的停車位置沿每一段的路徑（`TrainPath` 的 traversal 與停車點）記下走過的邊與邊上的範圍；某段從邊的另一端出發，表示在上一個停車點折返。範圍以邊的 `from` 端起算，同一條路線的範圍合併。行程開不出來的路線不畫。只取本線服務，區間車與快車（`patterns`）走不同的路時不另外畫。
2. **共線並排**（MapBuilder 的 interline segments 與 `offsets`）：參考把每一段站間（兩站相鄰的路線集合）當成一段，依路線的 `color|icon` 排序後並排；這裡以軌道邊為單位，在路線集合改變的地方切開，每一小段上的路線依 `LineID` 排序（顏色不唯一，ID 穩定），偏移照參考的公式（單位是一條線寬）：奇數條時第一條在軌道上、其餘依序往兩側 0、−1、1、−2、2……；偶數條時 0.5、−0.5、1.5、−1.5……，所以相鄰的線剛好相接、不重疊。正數往邊的方向（`from` 到 `to`）的左側。相鄰而且偏移相同的小段合併。
3. **轉乘群組**（MapBuilder 的 interchanges）：每個群組依群組的站序（ID 遞增）連一條線穿過各站，白色內線（參考 8 px 白線）加深藍外框（參考 2 px 黑框），畫在路線之上、車站之下。
4. **何時重算**（App 的 `MapView`）：軌道與月台、路線的站序／路徑偏好／環線／顏色、車站位置與轉乘群組改變時（`LineMapKey`），在背景執行緒重算（每條路線一次行程，大地圖上太慢，不能放在一個畫面裡）；列車移動、時間前進不重算。
5. **畫法**（`MapArt`）：順序是軌道 → 路線 → 轉乘連線 → 移動授權 → 車站 → 列車。線寬細節模式 `max(2.5, 0.22 × 參考尺寸)`、概覽 `max(2, 0.16 × 參考尺寸)`；偏移在螢幕座標上做，轉角沿角平分線外移（最多兩倍，相當於 Mapbox 的 `line-offset`）；端點平切（參考 `line-cap: butt`）。路線用路線面板的顏色（`Palette.lineColor`）；隧道裡淡化一半，和軌道一樣。
6. **圖示畫風**（`Palette`）：地面 `#ECEEF6`（深色 `#262C57`）；軌道綠松色道床（淺色 `#10917F`，比圖示的 `#12A08F` 稍深，讓它對地面有 3.37:1，達到圖形 3:1；深色 `#45D3C0`，7.17:1）加中間的淺色線（`#BDEFE7`，深色 `#D4FAF4`）；高架與橋加深藍外框；車站是暖黃 `#FFC86B` 加深藍外框（1.5 pt）與深藍符號（8.69:1）；站名、節點與隧道用深藍（深色模式用淺色，11.47:1／9.64:1）；列車深藍（深色模式淺色，外圈照舊）。交通控制、人口與城市圖層的顏色不變（`docs/UI_THEME.md`）。實景選點的 16 km 方框改成暖黃底、深藍框（暖黃細線在 Apple 的淺色地圖上看不見）。

**限制**：只畫本線服務走的軌道；偏移以每條邊自己的方向為準，相鄰兩條邊方向相反時，同一條路線可能換到另一側；參考的路線圖示（`line-pattern`）、車站依轉乘與否換圖示、聚焦路線的閃爍與模擬車輛沒有移植；沒有日夜變化；地圖不能關掉路線（參考也一直畫）。Phase 8 的 renderer 仍會重做整個地圖。

### 85. 資產、折舊、資產負債表與年度決算（Phase 7a）

2026-10-08，P7-1（`docs/research/REFERENCE_PORT_INVENTORY.md`）。參考 `Ci/` 的財務儀表板（`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`）有三張表：損益表（`flowDashboardBuildModeIncomeStatement`）、現金流量表（`flowDashboardBuildModeCashFlowStatement`：營業活動、投資活動、本期淨增加額）與資產負債表（`balanceSheet: {cash, metroQuotas, …, assetValuation: 0}`，資產估值固定為 0）；它的 `metroEconomyFixedAssets` 只是營運量（站數、路線長、列車數），沒有購入成本、折舊或年度結算（`docs/research/PHASE7_COMPANY_STUDY.md` §2、§3.4）。所以三張表的結構與現金流量的分類照參考，成本、折舊、報廢與年度決算是原生規則（gap → 原生）。存檔版本 16。

1. **資產紀錄**（GameCore，`AssetRecord`，`CompanyAccounts.assets`）：經營模式的公司每買一樣東西就記一筆：軌道邊（`track`，邊的編號）、車站（`station`）、列車與第一節車廂（`train`）、一次加購的車廂（`cars`，記節數）。記的是實際付的錢、購入時間、已提列的折舊與已提列的天數。自由模式不記（參考的創意模式「不計算財務」），所以 `EconomyAccountsTests` 的「自由模式存檔不變」照舊成立。紀錄的成本總和以 `maximumAccrued`（2^50）為上限，遠超過任何遊戲，讓資產負債表的加總不會溢位。
2. **折舊**（原生）：直線法、殘值 0；軌道與車站 20 年（7200 天）、列車與車廂 10 年（3600 天），一年是財報的 360 天（PHASE7 研究 §3.4 的提案）。每個經營中的午夜，在能源、利息、人事之後，每筆紀錄的天數加 1，累計折舊變成 `floor(成本 × 天數 ÷ 年限)`，當天的費用是兩者的差，所以每天的捨去不會累積，年限到時剛好折完。只有經營中的天數會折舊。
3. **分割與移除**：分割軌道邊時，兩段依長度分成本與累計折舊（第一段捨去，其餘給第二段），天數與購入時間沿用；拆軌、拆站不退費（決策 83、Stage S3），剩下的帳面價值記為資產報廢損失。減少車廂時從最後加購的紀錄扣，依節數比例扣成本與折舊，差額記為報廢損失。
4. **帳**（`CapitalDay`，`CompanyAccounts.capitalDays`）：折舊、報廢損失、購置現金、借入與償還記在每日的資本帳，和既有的營運帳（`DayAccount`、`LedgerEntry`）分開。`LedgerEntry.amount` 仍然等於現金的變化，帳本與既有的報表欄位都不變，所以 golden scenario 與 replay fixture 的 checksum 都沒有動。保留 720 天，和營運帳一樣。
5. **報表**（`FinanceSummary`）：新增折舊、報廢損失、購置、借入、償還。`netProfit` 改成營業利益 − 利息 − 折舊 − 報廢損失（之前只扣利息）；現金流量照參考分三段：營業活動（票價 − 營運成本 − 利息，參考的 `operatingCashFlow`，加上參考沒有的利息）、投資活動（−購置，參考是配額購買）、籌資活動（借入 − 償還，原生）與本期現金淨增減。
6. **資產負債表**（`GameWorld.balanceSheet()`，`BalanceSheet`）：現金（可以是負的）、軌道與結構物、車站、車輛（各類的成本與累計折舊，以帳面價值計）、銀行借款與權益；權益是資產減負債，所以資產總計恆等於負債與權益總計。買東西是現金換資產，借錢是現金與負債一起增加，權益都不變；權益只隨淨利改變。
7. **年度決算**（`AnnualStatement`，`CompanyAccounts.years`）：每 360 天的最後一個午夜，在當天的折舊之後，把這一年的損益表與現金流量（`financeReport(.year)`）和當下的資產負債表存成一筆，保留最近 50 年（參考的年報表 `FLOW_DASHBOARD_FINANCE_BUCKETS` 最多 50 年）。日帳只留兩年，所以決算要另外存，否則年底的資產負債表之後無法重算。
8. **舊存檔**：版本 15 以前沒有紀錄，之前蓋的東西以 0 入帳、不折舊也不報廢（PHASE7 研究 §6 第 7 題的建議：不用現在的價格假造歷史成本）；`unrecordedAssetCount()` 數出沒有紀錄的軌道邊、車站與列車，資產負債表下方註明。讀檔檢查：紀錄指向存在的東西、每條邊／每座站／每列車最多一筆、車廂紀錄的節數合計不超過加購的節數、0 ≤ 折舊 ≤ 成本、天數在年限內、購入時間不在未來；資本日與決算依序、不在今天（今年）之後、金額在界線內。新的 `SaveFixtures/v16-assets-closed-year.json`；既有 fixture 都沒有改。
9. **畫面**（GamePresentation 的 `FinancialStatements.swift`、App 的 `EconomyPanel`、`YearEndReport`）：經營面板的報表照參考的 `flow-dashboard-statement-switch` 切換損益表與現金流量表（本期與上期），下面是目前的資產負債表（旁邊是上一個年底）、各類的成本與累計折舊，以及年度決算的列表。遊戲進行中一年結束時，自動打開年度決算（有其他面板開著時，等它關掉）。字串都由 `DisplayLanguage` 提供中英文。

**限制**：沒有出售、房地產、稅與信用評等（P7-2、P7-3）；決算時遊戲不會暫停；資產沒有依路線分攤（參考的 `branchRootId` 分組只用在營運量）；自由模式改成經營模式之前蓋的東西沒有成本。

### 86. 目標、挑戰與快轉

2026-10-08，作者交給 Claude Code 決定（「用台灣玩家會想玩的角度，以及對未來耐玩性的選擇」）。教學結束後玩家沒有方向，這是 A 列車式遊戲最大的缺口。參考庫沒有可移植的鐵路目標：`Ci/` 有一個已停用的挑戰模式（`openMetroChallengeStartModal` 直接回傳「挑战模式已从当前经济设计中移除」；`startMetroChallengeFromModal` 跑 1 個模擬日、以當天載客數 `metroChallengeCurrentPassengerScore` 計分，事件是 Holiday Peak／May Day Rush，計分引擎 `MetroEconomy.startChallenge`、`calculateChallengeScore` 不在快照），是單日的計分賽而不是目標與期限；`Railway/taipei_gta_reference/` 的 missions 是動作遊戲的小任務。所以目標、評等與期限是原生（gap → 原生）；`Ci/` 挑戰模式的成績上傳與排行榜留給決策 87 之後的排行榜。存檔版本 17。

1. **目標**（GameCore，`Goal`）：只讀遊戲已經有的資料，判定是 deterministic 的。
   - `connect(points:radius:)`：每個地點半徑內都有路線停靠的車站，而且這些車站在同一個路網（路線共用車站，或停靠同一個轉乘群組的車站，決策 81）。
   - `dailyRiders`：前一天付費的乘客人次（`DayAccount.fareTrips`，每小時結算時記下）。
   - `population`：地圖土地上的居民總數；`tallBuildings`：D4 城市建物數（Phase 6）。
   - `annualNetProfit`：任一個已決算年度的淨利；`equity`：資產負債表的權益（決策 85）。
2. **劇本**（`Scenario`、`ScenarioState`，`GameWorld.scenario`）：目標（1–16 個）、金牌／銀牌／期限的天數（從開始那天算，那天是第 1 天）、連續幾個午夜現金為負就破產、以及年代可用的車種（`trainTypes`；`setTrainType` 拒絕其他車種，新的 `trainTypeUnavailable`；沒有車種的列車一律可以）。`startScenario(_:)` 只能在經營模式開始（新的 `invalidScenario`）。
3. **判定**：每個經營中的午夜，在折舊、年度決算之後：還沒達成的目標若現在達成，記下這一天；全部達成時依花的天數給金、銀、銅牌；超過期限或連續赤字太久就失敗。結束之後不再改變，遊戲照樣繼續（A 列車的無限模式）。所以不論怎麼推進時間（逐分鐘、批次、快轉），結果都一樣。
4. **快轉**（`GameSpeed.fast`）：每個 tick 10 遊戲分鐘，真實時間的 6000 倍，一天約 14 秒、一年約 1.5 小時。正常速度（600×）一年要 14 小時，以「年」為單位的目標與年度決算玩不到；快轉和其他速度一樣逐分鐘結算，所以只影響實際時間。實機效能待 TestFlight 量測。
5. **挑戰**（GamePresentation，`Challenge`）：開始畫面的「挑戰」在空白地圖開新遊戲，城鎮用新的隨機種子，每局不同。第一批三個沙盒挑戰：「三鎮連線」（連通三座城鎮、每日運量 10 萬人次，60／120／360 天）、「鐵道造鎮」（城市人口 100 萬、高樓 500 棟、每日運量 50 萬人次，1／1.5／2 年）、「鐵道大亨」（年度淨利 $3 億、公司權益 $10 億，1.5／2／3 年）；都是連續 60 個午夜赤字就破產。目標以無頭模擬量過：一條固定不擴張的第一條線（`BalanceReportTests` 的那條），每日運量第 1、60、120、180 天約 3.5、6.8、11.1、18 萬人次，人口 9.1、14.1、24.0、34.2 萬，D4 38（開局）、56、279、325 棟，權益 $3.1M、$14M、$37M、$75M；所以只蓋一條線拿不到金牌，要擴張路網。之後依實機調整。`Land.townCentres(seed:in:)` 給出城鎮中心（從 `towns(seed:in:)` 抽出，行為不變）。
6. **畫面**：遊戲選單與經營面板的「目標」顯示狀態（第幾天、下一個評等的期限、結果）、每個目標的進度條與達成日，以及各評等的天數；挑戰結束時自動打開（年度決算同時發生時，先看決算再看目標）。字串都有台灣用語的中文。
7. **存檔**：版本 17。世界只在有劇本時寫 `"scenario"`，日帳只在有乘客時寫 `"fareTrips"`，時鐘可以是 `"fast"`；版本 16 以前沒有劇本。讀檔檢查：規則有效、達成日在開始與今天之間、完成時每個目標都在完成那天以前達成而且評等符合天數、失敗日在遊玩期間。新的 `SaveFixtures/v17-scenario-fast.json`；既有 fixture、golden 與 replay 都不變（新的拒絕名稱只加在測試的對照表）。

**限制**：台灣鐵道史的劇本（平溪線觀光、劉銘傳鐵路、木柵線）是下一步，會用這裡的年代車種限制與實景地圖；平溪線的運煤史實版等貨運（O10）。目標數值只用無頭模擬量過一條固定的第一條線，沒有玩家擴張；挑戰的劇情文字是原創的，不是史實。

### 87. 每週挑戰與個人最佳紀錄

2026-10-08，作者同意的順序：先做能公平比較的每週挑戰，TestFlight 回饋之後再接 Game Center 的排行榜與成就，官網排行榜最後（要帳號、後端與隱私權政策的修改；屆時可以用 GameCore 的確定性重播在伺服器上驗證成績）。每週的地圖是原生（gap）；成績的欄位照 `Ci/` 已停用的挑戰模式（`metroChallengeLeaderboardPayload` 的 `eventId`、`rulesVersion`、`scorePassengers`，上傳到 `/api/challenge-scores`，伺服器回傳前 20 名與名次或百分位），之後的排行榜可以直接用。

1. **週**（GamePresentation，`WeeklyChallenge`）：以台灣時間（UTC+8，全年不變）週一 00:00 為一週的開始，從 1970-01-05 起算。開局時讀裝置的時鐘決定是哪一週；之後的遊戲是 GameCore 的劇本（決策 86），不讀時鐘，所以仍然是確定性的。
2. **同一張地圖**：城鎮的種子是 `"weekly.<週>"` 的 FNV-1a 雜湊，所以同一週所有玩家的地圖、城鎮位置與目標都一樣，下一週換新的。挑戰內容是「三鎮連線」，評等天數相同，劇本 ID 是 `"weekly.<週>"`（`Challenge.named` 認得它，存檔不需要新欄位）。
3. **最佳紀錄**（`ChallengeRecords`）：每個劇本 ID（參考的 `eventId`）保留完成天數最少的一次，天數相同時取完成那天載客較多的（參考的 `scorePassengers`），連同評等與規則版本（參考的 `rulesVersion`，目前 `2026-10-goals-v1`；目標數值改變時換新版本，舊版本的紀錄讀檔時略過），存在存檔資料夾裡的 `challenge-records.data`（不是 `.json`，所以不會被當成存檔）；只留在裝置上，不傳到任何地方。挑戰完成時（以及每次自動存檔時）記錄，刷新紀錄時狀態列顯示。
4. **畫面**：挑戰選單最上面是「本週」，顯示日期範圍、剩幾天與最佳紀錄；其他挑戰每次都是新地圖，也顯示最佳紀錄。

**限制**：沒有連網，看不到別人的成績（下一步的 Game Center）；裝置時間可以手動改，所以本機紀錄不防作弊；週的界線用台灣時間，其他時區的玩家換週時間不同。GameCore、存檔版本、golden 與 replay 都不變。

### 88. 全島地圖：放大上限、全台灣的實景地圖、土地按需展開

2026-10-08，作者同意研究（`docs/research/WHOLE_TAIWAN_MAP.md`，PR #223）的步驟 B，並定下三件事：範圍是本島加澎湖（不含金門、馬祖）；車站附近展開 2 公里的土地；存檔升版，舊存檔不轉換，舊版 App 讀到新的存檔顯示「存檔版本較新」。研究寫的是版本 16，但 #221 與 #224 已用掉 16、17，所以是**版本 18**。決策 87 是 #225 的每週挑戰。

1. **上限**：`WorldBounds.maximumSide` 從 2^20 改成 2^25 單位（524,288 m），`WorldBounds.maximum` 是 2^25 的正方形；原本的 16 km 正方形改名 `WorldBounds.standard`。座標上限 2^29 不變；整數運算的範圍見研究 §3.2（距離平方最多約 2^51）。有坡度的邊仍最長 2^24（約 262 km）。
2. **新遊戲的大小分開**：`GameWorld.newGameBounds` 是 `WorldBounds.standard`，空白新遊戲、示範、教學、挑戰與一般實景地圖都還是 16 km。只有「全台灣」（`WholeTaiwan`，GamePresentation）用大地圖。
3. **全台灣的範圍**：東經 119.25°–122.05°、北緯 21.85°–25.35°（澎湖花嶼以西到三貂角以東，富貴角與基隆嶼以北到鵝鑾鼻以南；綠島、蘭嶼在框內）。錨點是框的中心：經度取平均，緯度取 Web Mercator 的中點（23.6116811°N、120.65°E），世界範圍是錨點兩側較遠的邊的兩倍：18,278,391 × 24,938,704 單位（約 285.6 × 389.7 km）。投影照舊是 Web Mercator（研究 §3.4 的建議）：地面的一公里在基隆算成約 1.012 公里、在鵝鑾鼻約 0.988 公里，這一步不修正。
4. **土地按需展開**（GameCore）：
   - `LandBlock`：16 × 16 格（1,024 m）的區塊，從世界原點起算。`Land.blocks(within:of:in:)` 是任何一部分（到區塊最近的一點）比半徑近的區塊，平方精確比較。
   - `GameWorld.landBlocks`：已展開的區塊（依列、行排序）；`nil` 表示土地是完整的（以前的世界與所有 16 km 地圖）。`setLandOnDemand()` 清空土地與建物、開始按需展開；`setLand(_:)` 與 `foundTowns(seed:)` 讓土地回到完整（`nil`）。
   - `expandLand(_:cells:)`：讀入一批還沒讀的區塊和其中的格。已經有的格（區塊讀入前土地已經長到那裡）保留原樣；城市建物開啟時，新格依列、行在所有建物之後編號；接著重算土地需求。拒絕（`invalidLand`，世界不變）：土地是完整的、區塊在世界外、重複或已讀過、格不在這批區塊裡、重複或數值超出範圍。
   - 拆站不收回已讀的區塊。
5. **人口匯入**（GamePresentation，`LandImport`）：Web Mercator 讓 64 m 格的中點落在哪一個 WorldPop 列只看 y、哪一欄只看 x，所以每個 WorldPop 格的 64 m 格是一個「列 × 欄」的矩形。匯入改成對每個 WorldPop 格依列優先在它的矩形上分配，不再逐一走過世界的每個 64 m 格（全島約 2,700 萬格）。結果與之前逐格比較完全相同（8 個地點，16 km 與另一個長方形世界，有無地點資料，用暫時的測試比對過，沒有提交）。`cells(in:population:places:frame:bounds:)` 只給指定區塊的格，正好是整張圖匯入時那些區塊的格，所以土地不因讀入的先後而不同。
6. **蓋站時展開**（`GameSession`）：每次編輯（`performEdit`）在命令之後，對每座車站讀入 2 km（`WholeTaiwan.landReach`）內還沒讀的區塊，所以車站和它的土地是同一個編輯，復原會一起拿掉。App 沒有人口資料時不讀；之後的編輯或開始遊戲時（`readLandRoundStations()`）補讀。
7. **復原的記憶體**：每個讀入土地的編輯讓復原的快照各留一份土地與建物（每格約 110 bytes：100 站約 45 MB，600 站約 220 MB）。按需展開的地圖上，復原最多保留 3 個讀入土地的編輯（`GameSession.landReadingUndoLimit`），更早的編輯忘掉；其他編輯照舊最多 25 個。量測：600 站時峰值記憶體從約 6.9 GB 降到約 1.6 GB（Linux，含量測本身多留的幾份世界）。
8. **讓成本跟著蓋的東西走**（行為不變）：
   - 研究步驟 A 的大部分已由另外的 PR 合併進 `main`：城市圖層只存有土地或在腹地內的格、`GameWorld.landValues(at:)`、人口匯入每列與每欄只換算一次（#226），軌道間距沿線段逐欄分格（#228）。這個 PR 合併 `main` 時採用它們的版本與測試（`SparseCityLandTests`、`TrackSpacingTests`）。
   - 人口匯入改用這個 PR 的寫法：逐個 WorldPop 格在它的「列 × 欄」矩形上分配（第 5 點），因為按需展開要能只給指定區塊的格；整張圖的結果和 #226 的版本、也和最早逐格走的版本相同（`LandImportTests`，以及合併前沒有提交的逐格比對）。
   - 土地需求的分配（`LandDemand.shares`）改用排序的陣列，只有一座車站的格整格給它（最大餘數法對一個權重的結果）。300 站時從 150 ms 降到 15 ms。
   - golden、replay 與存檔 fixture 都不變，間距的 campaign（`ContinuousTrackPropertyTests`、`VerticalRailwayPropertyTests`）、`SaveMutationTests` 都通過。
9. **畫面**：實景選點畫面多一個「全台灣」，App 的人口資料讀好之後才能按。真實鐵路的背景改成依地圖大小決定範圍（至少 16 km），所以全台灣畫出全部的路線。
10. **存檔**：版本 18。世界只在按需展開時寫 `"landBlocks"`（`{"row", "column", "count"}` 的一列連續區塊）；版本 17 以前的世界土地完整。讀檔檢查區塊在世界裡、依序、不重複，一段不超過一列能有的 512 個。新的 `SaveFixtures/v18-whole-island-land.json`：一個 2^25 × 3·2^23 的世界，一座車站和它 2 km 內的 22 個區塊。

**量測**（Linux 雲端容器、Swift 6.4、`-c release`；車站放在人口最多的 WorldPop 格、彼此至少 3 km；手機會更慢，只是量級）：

| 車站 | 土地格 | 每蓋一站（含展開） | 存檔大小 | 存檔／讀檔 | 城市圖層建立 | 跑一天（車站沒有路線） |
| --: | --: | --: | --: | --: | --: | --: |
| 0（開局） | 0 | — | 763 bytes（16 km 空白新遊戲 25.7 KB，因為它有三座城鎮） | — | — | — |
| 1 | 5,120 | 43 ms | 59 KB | 7／12 ms | 4 ms | 0.3 ms |
| 100 | 414,800 | 56 ms | 4.0 MB | 0.46／1.18 s | 0.50 s | 11 ms |
| 300 | 1,185,380 | 104 ms | 11.1 MB | 1.18／3.06 s | 1.68 s | 0.10 s |
| 600 | 2,010,658 | 220 ms | 19.2 MB | 2.06／6.54 s | 3.29 s | 0.51 s |

開局（`newWholeTaiwanGame`）0.1 ms；讀人口與地點的格各約 0.03、0.05 s。

**限制**：
- 全島縮小時的畫面是下一步：城市圖層在主執行緒上重建（100 站 0.5 s、600 站 3.3 s，只在顯示城市圖層時），站名與路線沒有依縮放分級。
- 讀檔隨土地格數變慢（600 站 6.5 s），建物每棟各帶一個格的陣列，是每格記憶體的大宗。
- 城際需求（重力模型）與高鐵規則是步驟 C。
- 參考庫沒有按需展開的土地（缺口，原生實作）。

### 89. 全島縮小時的畫面

2026-10-08，步驟 B 的第二個 PR（決策 88 之後）。全台灣縮到整個島時，站名全部藏起來、城市圖層在主執行緒重建、地圖開在南投附近幾百公尺的地方。只改畫面：GameCore、存檔、golden、replay 都不變。

1. **站名依路線的等級出現**（GamePresentation，`StationLabels`、`MapLineLevel`）：移植 MapBuilder 的路線等級（`MapBuilder/reference_snapshot/_next/static/chunks/pages/_app-70b32b07723ca1d7.js` 的 `W`：`LOCAL`、`REGIONAL`、`LONG`、`XLONG`，`spacingThreshold` 2、10、50 km、無限，`zoomThreshold` 9.5、7、3.5、1.1）。
   - MapBuilder 用 `getLevel({avgSpacing})` 為整張地圖選一個等級：第一個平均站距小於門檻的。這裡每條路線各自算：相鄰停靠站之間直線距離的平均（環線加上最後一站回第一站），世界公里。
   - 車站取停靠它的路線裡最高的等級，沒有路線是 `local`。
   - 縮小（`MapDetail.overview`）時，地圖的縮放超過車站等級的門檻才寫站名。縮放用 MapLibre 的定義（地球 512 · 2^z 點寬），以錨點緯度換算；空白地圖用赤道。
   - 順序：等級高的先，再來是停靠路線多的，再來是編號小的。會蓋住已經寫上的名字就略過，一個畫面最多 60 個名字、最多量 150 個。名字下面墊一塊淡色底（`Palette.land`，80%）。放大到完整細節時照舊每站都寫。
   - 手機看整個台灣約是縮放 6.6：長途（高鐵這類）的站有名字，區域線（台鐵區間）要到 7 以上，捷運要到 9.5 以上。
2. **城市圖層在背景算**：`CityMap` 改成和路線圖（`LineMap`）一樣用 `Task.detached` 建，算好之前畫面留著上一份。決策 88 量到 100 站 0.5 s、600 站 3.3 s。
3. **空的全島地圖開在整個島**：`WorldRegion.opening(in:)` 是蓋了東西的範圍，或按需展開、還沒蓋東西的地圖的整張圖；其他地圖照舊（`built(in:)`）。
4. **真實鐵路的背景沒有改**：MapKit 只畫畫面裡的圖磚，車站點本來就只在網站的 `stationsMinimumZoom` 以上才畫，所以不需要照 `Railway/` 網站的 `visibleRoutes` 自己裁切（網站用 MapLibre 的 GeoJSON 才需要）。

**限制**：
- 路線的線寬與共線偏移在縮小時沒有改，路線很多時會擠在一起。
- 站名的分級只看路線；城際需求（步驟 C）之後可以再加上車站的運量。
- 實機的手感要 TestFlight 確認。
### 90. 台灣鐵道史劇本：平溪線（觀光版）與年度節慶

2026-10-08，作者同意的順序：每週挑戰之後，先做台灣鐵道史的第一個劇本「平溪線」觀光版；運煤的史實版等貨運（O10）。

1. **地圖與開局**（GamePresentation，`PingxiChallenge.make(in:railways:land:)`）：用實景示範的世界（`RealWorldDemo`）：平溪線、宜蘭線、深澳線照真實路線鋪好並開始營運，各站的客流照示範的設定（十分、平溪、菁桐等是景點）。在這上面開始劇本，所以需要 App 的真實鐵路資料（`launcher.railways`），還沒讀完時挑戰選單的按鈕停用、launcher 拒絕並說明。
2. **目標**：某一天的運量 8 萬人次與一個年度淨利 $200 萬；金牌 360 天、銀牌 720 天、銅牌 1080 天（剛好是第一、二、三年的年度決算），連續 60 個午夜赤字就破產。以無頭模擬量過示範的開局（release build、沒有玩家操作）：各站需求合計每天 7.1 萬，第一週每天載 5.5–7.1 萬人次，票價收入約 $31 萬、營運成本約 $34 萬，每天虧約 $2.5 萬、一年約 $900 萬，正好是真實平溪線差點停駛時的處境。所以運量目標只有在天燈節、而且列車載得下時才達得到，淨利目標要靠調票價、減成本或重整路線讓路線轉虧為盈。
3. **天燈節**（GameCore，`ScenarioEvent`、`DemandEventKind.festival`）：劇本可以有每年同一天的節慶：在某站從每年（360 天）的第 `dayOfYear` 天起 `days` 天，需求提高 `boost` 千分比，提前 `notice` 天公布，成為種類 `festival` 的需求事件（沿用作者清單第 4 項的需求事件，畫面照常顯示）。在每天開始、移除過期事件之後排入；車站已拆除就不辦；需求事件的總數照舊以 64 為上限。平溪線的天燈節在每年第 45 天（遊戲曆從第 0 天算，所以畫面寫第 46 天）起 3 天，十分與平溪的需求是平常的 2.5 倍（+1500‰），提前 7 天公布。遊戲的曆法沒有農曆，所以用固定的一天代替元宵節。隨機抽出的事件不會是節慶。
4. **劇情**：平溪線 1921 年為了運煤而建（臺陽礦業出資），1929 年由總督府收購並開始載客；煤礦沒落後在 1980 年代一度因虧損差點停駛，地方奔走才保留下來，之後成為觀光鐵道。來源：英文維基百科「Pingxi line」、天下雜誌《微笑台灣》〈回憶平溪支線的黑金歲月〉；年份與出資者各來源略有出入，劇情只寫多數來源一致的部分。目標數值、天燈節的日子與倍率是本專案的。
5. **存檔**：版本 19。劇本只在有節慶時寫 `"events"`；需求事件多了 `"festival"` 種類。讀檔照舊檢查需求事件（天數、倍率、車站存在）；`startScenario` 拒絕節慶在不存在的車站（`invalidScenario`）。新的 `SaveFixtures/v19-scenario-festival.json`；既有 fixture、golden 與 replay 不變。
6. **畫面**：挑戰選單新增「台灣鐵道史」區塊，平溪線的卡片多一行天燈節的說明。

**限制**：運煤（貨運）、劉銘傳鐵路與木柵線是之後的劇本；天燈節的日子固定，不跟真實的元宵節；平溪線各站的客流仍是示範固定的數字，不由土地推導。

### 91. 八種土地用途

2026-10-08，作者：「一次補完全部」。研究文件（`docs/research/PHASE6_LAND_USE_STUDY.md`）列的八種用途裡，6a 只做了住宅、商業、辦公；作者的分析把它分成三層：用途（這一步）、密度（D1–D4，決策 74，不變）與城市風格（Phase 8，不在這一步），並要求車站需求的種類和土地分區分開。學校的時間依作者的選擇用新的曲線，不借用最接近的種類。存檔版本 20，golden schema 40（依工作登記 #231：存檔 19 與決策 90 已預留給平溪線劇本）。

參考檢查（`a91453/railway-reference-private`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「八種土地用途（決策 91）」）：`Ci/` 的 `landuseLabelByClass`（居住、商務辦公、商業服務、工業、行政辦公、教育、醫療、體育文化、公園綠地等 11 類）與 zh-CN 語系的建物類別（農業、市政、工業、公共設施、教育……）支持這八種的分法；`Ci/` 的 `buildStationFlowPresetCurves` 是四種車站曲線的來源（決策 34），學校的曲線照它的形式寫；參考沒有學校或公共設施的曲線、地價、公園溢價或各用途的容量，這些是原生（gap → 原生）。

1. **用途**（GameCore，`LandUse`）：`residential`、`commercial`、`office` 之後加 `industrial`（工廠與倉儲，貨運之後再說）、`civic`（學校、醫院與公部門）、`leisure`（景點、遊樂與度假）、`agricultural`（農地）、`park`（公園）。空地、水域與不能蓋的地不是用途：沒有人的格不列出（地形另外一層，下一個 PR）。
2. **公園**：唯一可以沒有人的用途，而且必須沒有人（`residents + jobs == 0`）；其他用途仍然至少要有一個人（`invalidLand`）。存檔的格式不變（公園一段是 `"residents": [0, …]`、沒有 `"jobs"`）。公園的建物是 D1、容量 0；永遠不算「已滿」，不升級；成長分配依現有人數，所以不會分到人；新住宅只蓋在有人的格旁邊（公園旁邊不算）。
3. **建物**（決策 74 的表）：住宅占樓板的八分之幾：住宅 7、商業與農業 2（農舍）、辦公、學校與觀光 1、工業 0；公園 0／0。主要人數：住宅看居民，其他看就業。
4. **車站需求**（`StationDemandKind.civic`，排在最後）：新的曲線，沿用參考曲線的形式 `1 + 0.6 · g(h; μ, 1.15)`（`g` 是常態分布的峰形，正規化成平均 1、以千分之一表示）：到達 μ = 7（學生上學）、出發 μ = 16（放學）。其他四種曲線不變。
5. **腹地的種類**（`LandDemand.Share`）：辦公、工業與農業的就業算辦公（照辦公的時間通勤），學校與公共設施算 `civicJobs`，觀光算 `leisureJobs`，住宅、商業（與公園，永遠是 0）的就業算商業。種類取人數最多的，平手依住宅、辦公、商業、學校、觀光的順序；只有舊用途時和以前完全相同。成長的就業是四種的總和。
6. **地價**（決策 76）：基準：工業 1,500、學校與公共設施 2,500、觀光 3,000、農業 600、公園 1,200（舊的三種不變）。新的公園溢價 P：格的中點離某個公園的中點不到 400 m（25,600 單位）時加 600（$6／m²），公園自己也算；`value = clamp(base + 15·S + 1000·A + P, 500, 50000)`。`LandValue.parkPremium` 記下 P。只是查詢，不存檔。
7. **空白地圖的城鎮**（`Land.towns(seed:in:)`）：核心（9d² < r²）不變。核心外每格多一次抽籤 `town.<n>.district.<dr>.<dc>`（0–19，key 和以前的不同，所以其他格不變）：內圈（4d² < r²）0 是學校（就業 = 那格的居民數，居民剩四分之一）、1 是觀光（就業 = 居民數，沒有人住）、2 是公園；外圈 0、1 是工廠（就業 = 兩倍居民數，沒有人住）；其他照舊是住宅。半徑外三格是農地帶：`town.<n>.farm.<dr>.<dc>`（0–5）抽到 0 的格是 3 人、8 個就業的農地。城鎮仍然不會重疊（最外的農地帶離中心 15 格，外面兩座最遠 13 格，相距至少 31 格）。種子 1 的新遊戲：887 格 → 1,000 格，居民 90,900 → 81,427、就業 67,413 → 83,339。
8. **實景**（GamePresentation，`LandImport`、`StationDemandKind.realWorld`）：學校與觀光景點不再併進辦公與商業。一個 WorldPop 格的用途是辦公、商業、學校、觀光之中就業最多的那一種（平手依這個順序），而且要不少於居民數，否則是住宅。工業、農地與公園沒有實景資料（OSM 的 `landuse=industrial`、`leisure=park`、`landuse=farmland` 要重新產生 `taiwan_places.json`；這個環境連不到 Overpass，列為 gap）（決策 93 補上）。實景車站的類型多了學校（最少 3 所，門檻同樣是 1.5 倍）：台灣 544 站從 335 住宅、130 商業、57 觀光、22 辦公變成 328、107、57、50 與 2 所學校；台北車站從商業變成辦公。
9. **畫面**：用途圖層八種顏色（工業紫、公共設施紅、觀光青綠、農業棕、公園淺綠），圖例兩欄；點格的提示框寫用途，鄰近公園時多一行「鄰近公園 +$6／m²」；地價圖層畫出公園附近的空格。車站面板的類型按鈕多一個「公共設施」。腹地涵蓋圖層裡公園不算有人。
10. **存檔**：版本 20。格式不變，但之前的讀取端不認得新的用途與 `civic`，會說存檔損壞，所以升版；版本 20 以前的世界只有三種用途、四種需求，照舊讀。新的 `SaveFixtures/v20-land-uses.json`。
11. **golden**：schema 40。新的 `land-uses.json`；`land-towns.json` 與 `city-buildings.json` 的城鎮值逐項改變（見 `GoldenScenarios/README.md` 的「決策 91」）。replay 不變（沒有用到城鎮）。

**限制**：
- 工業沒有貨運，農地沒有季節；學校只有平日的曲線（週末照每週需求的係數，決策 68）。
- 公園溢價只看距離，不看公園大小；之後可以照 MapBuilder 或 OSM 的公園面積調整。
- 空白地圖的分區是抽籤，不是規劃；城市風格與分區規則（例如工業區集中在鐵路旁）留給 Phase 8。
- 平衡（新遊戲的回本與成長）以 `NewGameBalanceTests` 量過，見 PR。

### 92. 城市建造 P0-A：玩家放置建物

2026-10-08，作者：「《沿線》現在最大的玩法缺口，是玩家能建鐵路，卻不能真正親手建造城市」，要求立刻插入「城市建造 P0」，P0-A 先做直接建築；驗收：開啟空白地圖 → 選擇小住宅 → 點選地面 → 看到房子 → 儲存並重新開啟仍然存在。建物用自由的世界座標擺放，64 m 的土地格只負責統計與規劃。號碼依工作登記 #231：存檔 21（19 是平溪線劇本，20 是八種土地用途）、golden schema 41（40 是八種土地用途）。參考庫沒有玩家放置建物的實作（`Ci/` 的 build mode 是蓋地鐵路線，`Railway/taipei_gta_reference/` 的 `buildMode` 是載入場景），所以是原生（gap → 原生）。

1. **資料**（GameCore，`City/PlacedBuilding.swift`）：`PlacedBuilding { id, kind, centre }`，`PlacedBuildingID` 從 1 依序配發、不重用；`PlacedBuildingKind` 是 `house`（16 m 見方）、`shop`（24 m）、`office`（32 m），用途分別是住宅、商業、辦公。建物是邊與南北、東西平行的正方形，涵蓋 `centre − side/2 ..< centre + side/2`。和城市自己的建物（決策 74，一格一棟、由城市產生與升級）分開存：`GameWorld.placedBuildings`。
2. **指令** `placeBuilding(_:at:)`：整個正方形要在世界裡（`outOfBounds`），不和其他玩家建物重疊（`buildingOverlaps`，碰到邊不算），軌道中心線要離正方形至少 2 m（`buildingOnTrack`，檢查每條邊的折線與擴大 2 m 的正方形，整數運算），車站的點也要離 2 m（`buildingOnStation`），依這個順序檢查；失敗時世界不變。免費、還沒有人住：費用、拆除、選取與人口和就業是 P0-C。
3. **之後蓋的軌道與車站**：這一步不檢查是否壓到建物（讀檔也不檢查），列為限制；P0-C 決定是拆除還是拒絕。
4. **畫面**：工具列多一個「建築」工具（`ConstructionTool.building`），選項是小住宅、商店、辦公樓三個按鈕與「已蓋 N 棟」；點地圖就蓋（`GameSession.placeBuilding(at:)`，一次可以復原的編輯），結果顯示在狀態列。地圖一直畫出每一棟（依種類上色、深色邊框，縮小時至少 4 點大），不是圖層。
5. **存檔**：版本 21。世界只在有玩家建物時寫 `"placedBuildings"`、配發過時寫 `"nextPlacedBuildingID"`；讀檔檢查編號遞增並小於下一個、整個在世界裡、互不重疊。新的 `SaveFixtures/v21-placed-buildings.json`。
6. **golden**：schema 41，新指令 `placeBuilding`、觀察 `placedBuilding`、結果 `buildingOverlaps`／`buildingOnTrack`／`buildingOnStation`、最終狀態選填的 `placedBuildings`；新的 `placed-buildings.json`。既有 fixture 的預期值都沒有改變。
7. **UI 測試**：`StartSaveFlowSmokeTests.testAHouseBuiltOnABlankMapIsKeptBySavingAndContinuing` 就是作者的驗收流程。

**限制**：建物不住人、不影響運量與地價；沒有旋轉；軌道與車站可以蓋在建物上；只有三種、一種大小。

### 93. 實景的工業區、公園與農地

2026-10-08，作者要求補上決策 91 留下的缺口：實景地圖的工業、公園、農地改用 OpenStreetMap 的真實資料。作者同意產生資料的工具多一個依賴 pyosmium（BSD 2-Clause），只用在讀整包的 OSM 檔；App 與遊戲不用它。

參考檢查（`a91453/railway-reference-private`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「實景的工業區、公園與農地（決策 93）」）：`MapBuilder/` 的 `fetchAndHandleParks` 用 Overpass 抓 `leisure=park` 的多邊形、算車站範圍內的公園面積，這裡同樣取**面積**；參考沒有工業區與農地的就業、也沒有把面積放到格網上，這些是原生（gap → 原生）。

1. **資料**（`tools/real-world-population/build_zone_grid.py`）：`landuse=industrial`、`leisure=park`、`landuse=farmland` 的 way 與 multipolygon relation。每個人口格（30″）切成 4 × 4 個分區格（7.5″，約 230 × 210 m），每個分區格取 4 × 4 = 16 個點，記下落在那種土地裡的點數（奇偶規則，relation 的內環是洞；同一種土地重疊只算一次）。來源可以是 Overpass（逐區、逐種，伺服器忙時把一塊切成四小塊再問），或一整包 `.pbf`（pyosmium，約 20 秒）。打包的是 osmtoday.com 2026-10-06 的台灣檔：工業區 429.0 km²、公園 134.7 km²、農地 2,244.7 km²，加進 `taiwan_places.json` 的 `zones`（檔案 256 KB → 1.06 MB）。
2. **地點也用同一份**（作者：「統一比較好」）：`build_place_grid.py` 也能讀整包檔（約 1 分鐘；路與 relation 取外框的中心，和 Overpass 的 `center` 相同），商店、辦公、學校、景點改從同一份 2026-10-06 的檔重算：101,189、8,485、4,393、6,300（之前 2026-10-05 從 Overpass 抓的是 102,090、8,614、4,588、6,511）。差別幾乎都在廈門：金門那一格的 0.25° 範圍蓋到對岸，舊資料把廈門的商店與學校也算進來，整包檔只有台灣；本島每塊最多差 4 間。地點的就業從 8,561,200 變成 8,405,125。真實車站 544 站的類型從 328 住宅、107 商業、57 景點、50 辦公、2 學校變成 326、107、58、51、2：機捷台北車站從商業變辦公（和台鐵台北車站一致）、中里從住宅變景點、老街溪從住宅變商業。
3. **讀取**（`PlaceGrid`）：`zones` 可以沒有（舊檔或測試）；有的話三種都要在，點數在 0…`samples`。一個分區格至少一半的點是同一種土地時就是那一種，取點數最多的，平手依工業、公園、農地；`zone(atLatitude:longitude:)`、`area(of:)`。
4. **土地**（`LandImport`）：一個 64 m 格的中點所在的分區格有分區時，那格就是那種用途：
   - 公園：沒有人（`residents == jobs == 0`）；
   - 工業：每格 30 個就業（`industrialJobsPerCell`；製造業約 300 萬人 ÷ 97,356 格約 31，取整為 30），沒有人住；
   - 農業：每格 1 個就業（`farmJobsPerCell`；農業約 53 萬人 ÷ 569,425 格約 0.93）；
   - WorldPop 格的人口與地點的就業只分給**沒有分區**的格（最大餘數法，依列、行的順序）；全部都是分區時依序分給農地、工廠；只有公園時照舊分給全部的格，那些格不當公園，用途照決策 91。
   - 邊緣的 WorldPop 格照舊先算出世界裡那一部分的人數（`inside` 個 slot 的份），再分給上面的格，所以總人數和沒有分區時完全相同。
   - 有工廠或農地、但沒有人的 WorldPop 格也有土地；只有公園的地方不算「有人」，新遊戲照舊建立城鎮。
5. **數字**：16 km 的地圖，人數都不變；就業（兩份資料一起，之前是舊的地點、沒有分區）：台北 2,061,993 → 2,129,610、新竹 319,048 → 427,731、彰化 143,796 → 193,817。台北有 4,481 格公園、2,244 格工廠、297 格農地，其他格因為多住了人而變密（`LandImportTests` 列出前後的各密度格數）。地圖中心的車站：新竹從住宅（22,989 人次）變成商業（22,977）——站旁的公園與工廠不再有人住，腹地的居民少了；台北仍是辦公。
6. **不動**：GameCore、存檔（版本 20）、golden（schema 40）與 replay；舊存檔的土地是存下來的格，不重新產生。
7. **畫面**：資料來源畫面的 OSM 說明多了工業區、公園與農地；用途圖層與地價（公園溢價，決策 91）照舊。

**限制**：
- OSM 標得少的地方沒有分區（例如彰化平原有些農地沒有標）；工業區的就業不看廠房大小，科學園區與一般工業區相同。
- 分區格約 230 × 210 m，比 64 m 格粗；格裡的位置照分區格決定，不是精確的邊界。
- 打包的整包檔沒有時間戳，`osmData` 是那些地點（或三種土地）裡最新的一筆編輯時間。

### 94. 城市建造 P0-C1：公司的建物（A 列車式）

2026-10-08，作者選「A 列車式並融合兩者優點」：玩家蓋的建物是公司的資產，有建造費、租金、維護、拆除（A 列車），也帶來居民與就業、讓車站有運量（SimCity），並要求把 P0 與 7b／7c 融合（`docs/research/CITY_BUILDING_STUDY.md`）。研究列的六個問題作者交給本專案決定（「用你覺得對遊戲行最好的方式」），採用研究的建議。P0-C 拆成 C1（這一步：費用、帳上資產、入住、運量、每日租金維護土地稅、拆除）與 C2（收購城市的建物、軌道穿過建物的費用、預覽與旋轉）。號碼依工作登記 #231：存檔 22、golden schema 42；決策 93 是實景的工業區、公園與農地。參考庫沒有不動產經營（`Ci/` 只有運輸與票價），所以規則是原生的，公式來自 Phase 7 研究（`docs/research/PHASE7_COMPANY_STUDY.md` §3.3）（gap → 原生）。

1. **大小與容量**（`PlacedBuildingKind`）：小住宅與商店 2 層、辦公樓 6 層；占地 256、576、1,024 m²，樓地板 512、1,152、6,144 m²。容量照決策 74 的規則（住宅 7/8、商業 2/8、辦公 1/8 的樓地板給居民，每人 48 m²，其餘就業每人 32 m²）：小住宅 9 人／2 個、商店 6／27、辦公樓 16／168。
2. **建造費**（`placedBuildingQuote`）：經營模式下 = 樓地板 × $40（`PlacedBuildingRules.floorCost`）＋ 占地 × 中心那一格的地價（土地使用權，A 列車的「土地代」）；餘額不足拒絕（`insufficientFunds`，檢查在位置之後）。記成一筆資產（`AssetClass.buildings`、`AssetRecord.Kind.building`），30 年（10,800 天）直線折舊，土地使用權也一起折舊（沒有永久土地）。自由模式免費、不記帳，P0-A 的行為不變。
3. **入住**（`fillPlacedBuildings`，每個午夜在土地成長 `growLand` 的最後）：建物中心那一格地價的服務 `S`（0…1000，服務溢價 ÷ 15）> 0 時，居民與就業各加 `max(1, 容量 × (20 + S × 80 / 1000) / 1000)`，不超過容量；沒有車站服務時各減 `max(1, 現有 × 20 / 1000)`。蓋好時是空的。
4. **運量**：有人的建物加入 `LandDemand.shares`，和土地一樣以中心點分給 800 m 內的車站（每 100 人每天 40 旅次），依 ID 順序；入住或拆除後立刻重算。
5. **每日收支**（`settleProperty`，午夜結算在折舊之前，一列 `.dailyProperty`）：租金 `floor((R×1000 + J×1500) × (1000 + floor(S/2)) × V / 10,000,000)` 美分（R、J 是居民與就業、V 是地價）、維護 `ceil(建造費 × 2 / 10,000)`、土地資產稅 `round(土地使用權 × 1 / 10,000)`。用的是當晚入住之後的人數。三項都是 0 時不寫。`DayAccount` 與 `FinanceSummary` 多 `propertyRevenue`、`propertyCost`（不算 `totalCost`），營業利益 = 票收 − 營運成本 ＋ 不動產收入 − 不動產支出；只在不是 0 時寫進存檔。
6. **拆除** `removePlacedBuilding(_:)`：依序拒絕不存在的建物（`unknownPlacedBuilding`）、餘額不足；經營模式付建造費的 10%（進位），寫成一列 `.buildingDemolition`（`propertyDemolition`），算進當天的 `propertyCost`，所以現金流量和餘額的變化一致；剩下的帳面價值記為報廢損失，不退款；人立刻離開、車站的運量重算；ID 不重用。自由模式免費。
7. **畫面**：建築工具多「建造／拆除」切換（`GameSession.buildingMode`、`tapBuildingTool(at:reach:)`；拆除點建物上或觸控半徑內最近的一棟），經營模式顯示估價（`buildingQuoteText`）與每日租金、維護與稅（`buildingEconomyText`）；蓋與拆的訊息帶金額，損益表、現金流量表與資產負債表多「建物」的列（不是 0 時才出現）。
8. **存檔**：版本 22。建物只在不是 0 時寫 `residents`、`jobs`、`buildingCost`、`landCost`；讀檔檢查人數在容量內、費用在範圍內，`.building` 的資產要對到存在的建物。版本 21 的建物讀成空的、免費的建物（沒有資產紀錄）。新的 `SaveFixtures/v22-company-buildings.json`。
9. **golden**：schema 42，新指令 `removePlacedBuilding`、結果 `unknownPlacedBuilding`、`placedBuildings` 選填的 `residents`、`jobs`、`buildingCost`、`landCost`；新的 `company-buildings.json`。既有 fixture 的預期值都沒有改變。

**限制**（C2 以後）：不能收購城市自己的建物；之後蓋的軌道與車站仍可壓在建物上（不收費）；沒有預覽與旋轉；建物不影響地價；沒有出售（拆除是唯一的處分）。

### 95. 城市建造 P0-C2：收購城市建物、軌道穿過公司建物、建造前預覽

2026-10-08，接決策 94，作者把研究 #236 的六個問題交給本專案（「用你覺得對遊戲行最好的方式」），採用研究的建議：自動收購城市建物、軌道可以穿過建物但要付費、出售後留給城市（P0-D）。號碼依工作登記 #231：決策 95；存檔版本與 golden schema 都不動（沒有新的格式或欄位）。參考庫沒有收購、拆遷或建造預覽的實作（研究 §2），是原生（gap → 原生）；預覽 → 確認 → 一筆投資現金流的做法沿用 `Ci/` 的 `metroCanPlaceWithinQuota`。

1. **城市建物的位置**：城市建物（決策 74）仍是一格一棟、沒有自己的座標；這一步給它一個位置：格子中央 40 m 見方（`PlacedBuildingRules.cityBuildingSide` = 2,560 單位，1,600 m²，約一層樓板 1,536 m²）。格子其餘是街道與空地，所以小住宅可以蓋在格子邊上、不碰城市建物。
2. **收購**（`placeBuilding`）：玩家建物的正方形加 2 m 間距和城市建物的正方形重疊（碰到邊不算，`cityCells(claimedBy:)`）時，收購並拆除那些城市建物。收購價 = （樓地板 1,536 m² × 層數 × $40 ＋ 1,600 m² × 該格地價）× 120%（`buyOutPrice(of:)`，公園沒有樓地板；城市建物關閉時用城市會蓋的密度）。收購價併入土地使用權（`landCost`），一起記成資產、繳土地資產稅。被收購格的居民與就業搬進玩家建物，最多到它的容量，其餘離開；那一格土地與城市建物一起移除，其他城市建物的編號不變。自由模式免費收購，人一樣搬進來。錢不夠時整個拒絕。
3. **城市不再長回來**：被玩家建物佔住的格（`isClaimedByPlacedBuilding`），城市擴張（`spread`）不會蓋新格，`setLand`／`foundTowns` 與全島地圖按需讀入（`expandLand`）也跳過。App 在選建地時先讀入那裡的土地（全島地圖），讓預覽與收購算到城市建物。
4. **之後蓋的軌道與車站**：新的軌道邊（不是隧道）的中心線離公司建物不到 2 m、或新車站的點離它不到 2 m，就拆除那些建物，各付拆除費（建造費的 10%，寫成 `.buildingDemolition` 一列），帳面價值報廢；軌道或車站的費用加拆除費一起檢查餘額，不夠就整個拒絕（`insufficientFunds`，`required` 是合計）。**隧道從建物下方通過**：隧道邊不拆建物，玩家建物也可以蓋在隧道上方（P0-A 原本連隧道也拒絕）。城市建物不受軌道影響：64 m 格只是統計，軌道穿過城市不收收購費（只有玩家建物存在時結果才改變，既有 golden 與 replay 不變）。
5. **建造前預覽**（App）：建築工具點地圖只選建地（`GameSession.buildingSite`），地圖畫出建物的虛影（可以蓋綠色、不行紅色）、會被收購的城市建物（紅框），選建地時也淡淡畫出可見範圍內每棟城市建物的位置；面板寫出費用分項（建物、土地、收購）或不能蓋的原因；動作按鈕「建造 · $X」才真的蓋（`confirmBuilding()`，一次可以復原的編輯）。換模式或工具會清掉建地。拆除模式仍是點了就拆。路網工具的預覽標出會被拆的公司建物，費用含拆除費，完成訊息寫出拆了幾棟。
6. **旋轉延後**：三種建物都是正方形，旋轉 90° 不改變足跡與任何規則，只是外觀；等有長方形的建物（P0-D 之後的旅館、遊樂設施）再做。
7. **golden**：新的 `company-buildings-clearing.json`（schema 42）：收購 D4 住宅、人搬進辦公樓、軌道拆小住宅、車站拆辦公樓。既有 fixture 的預期值都沒有改變。

**限制**：城市建物的位置是固定的格子中央，不是真實的足跡；軌道不影響城市建物；收購後那一格的地價回到空地的基準（玩家建物不算土地用途）。

### 96. 分區收更多 OSM 標籤；森林、墓地、軍事區不是用途

2026-10-08，作者同意把 OSM 的細分類歸進現有的八種用途，並問「森林、墓地、軍事區放進地形層」是否正確，要以玩家的角度判斷。決策 94、95 已由城市建造 P0-C 登記（工作登記 #231）。

台灣整包檔（osmtoday.com，2026-10-06）各標籤的面積是判斷的依據：`natural=wood` 22,050 km²、`leisure=nature_reserve` 13,328、`landuse=farmland` 2,264、`natural=water` 902、`landuse=forest` 825、`landuse=residential` 519、`landuse=industrial` 472、`landuse=military` 351、`landuse=aquaculture` 233、`landuse=orchard` 183、`leisure=park` 137、`landuse=cemetery` 75（另有 `amenity=grave_yard` 22）、`landuse=harbour` 49、`leisure=golf_course` 42、`landuse=quarry` 25、`landuse=commercial` 23、`landuse=retail` 15。

1. **只擴充有面積、沒有點的三種**（`build_zone_grid.py` 的 `TAGS`）：
   - 工業：`landuse=industrial`、`quarry`（礦業也算工業部門）；
   - 公園：`leisure=park`、`golf_course`，`landuse=recreation_ground`；
   - 農業：`landuse=farmland`、`orchard`、`vineyard`、`aquaculture`（魚塭，農林漁牧的「漁」）、`farmyard`、`greenhouse_horticulture`、`plant_nursery`。

   結果：工業區 429.0 → 454.0 km²、公園 134.7 → 181.7、農地 2,244.7 → 2,681.6（`taiwan_places.json` 1.06 → 1.17 MB）。
2. **不收的**：
   - `landuse=commercial`、`retail`、`education`：商業與學校已經用點計算（商店、學校，決策 91），再收面積會重複算就業。
   - `landuse=harbour`：常常是港內的水面，水上不該有工廠的就業。
   - `leisure=pitch`：多半是學校的操場，屬於學校。
3. **就業數**：工廠格 102,817 格，製造業約 300 萬人 ÷ 格數約 29，`industrialJobsPerCell` 從 30 改成 29；農地 677,182 格，農業約 53 萬人 ÷ 格數不到 1，`farmJobsPerCell` 仍是 1（沒有人的農地至少要一個就業才是土地）。
4. **森林、墓地、軍事區不是用途，也不全是「不能蓋」**（以玩家的角度）：
   - **森林**：占台灣約六成，阿里山、平溪、南迴、花東這些最有名的鐵道都穿過森林。列為不能蓋，玩家就蓋不了山線，所以森林不能是障礙。之後的地形層用**坡度與高度**決定隧道、橋梁與造價；森林最多讓城鎮長得慢、鐵路多一點整地費。
   - **墓地**：真實的鐵路、捷運與高鐵常常要遷葬，這本身是個有意思的選擇（繞路，或付遷葬費直線通過）。之後的地形層：城鎮不往墓地長、建物不能蓋，軌道與車站可以通過但要付遷移費。
   - **軍事區**：351 km²，好幾處緊鄰城市與機場。對玩家來說，一大塊不能動的地只有阻擋、沒有選擇；參考的 `Ci/` 也刻意隱藏軍事設施的標示（`applyOsmSensitiveFacilityLabelFilter`）。所以先**不建模**：WorldPop 本來就幾乎沒有人住在那裡，就是一般的空地，不另外標示。
   - **水域**（海、河、湖、`natural=water`）：真正的障礙，只能用橋或隧道過，城鎮不蓋到水上。這是 ROADMAP「地形與土地狀態」的第一步（海岸線的遮罩）。
   - **自然保護區**（13,328 km²，多半和森林重疊）：同森林，不當障礙；之後可以讓保護區裡的建設比較貴。
5. **數字**（16 km 地圖，居民都不變）：台北的公園格 4,481 → 4,568、農地 297 → 325；彰化的公園 85 → 247、農地 10,781 → 10,960；雲林口湖（魚塭區）的農地 20,161 → 22,446。地圖中心車站的類型與運量幾乎不變（口湖 672 → 674 人次）。
6. **不動**：GameCore、存檔（版本 21）、golden（schema 41）、replay；地點（商店、辦公、學校、景點）與車站類型。

### 97. 實景地圖的 OpenStreetMap 底圖（MapLibre，E3）

2026-10-08，作者問 3D 模型要不要先搬，接著問「還是底層圖層先換 OSM」。判斷：先換底圖。遊戲的鐵道、車站、分區、地點都來自 OSM（決策 93、96），底圖用 Apple 地圖會和它們對不齊；參考 `Ci/` 的地圖引擎就是 MapLibre ＋ OpenFreeMap；MapLibre 本身能傾斜、旋轉、畫 OSM 建物的 3D 量體與地形，是之後 3D（Phase 8）的捷徑。作者同意新增依賴 MapLibre Native，並選「先加成選項」：地圖樣式選單多一個「OpenStreetMap」，預設仍是 Apple 地圖，實機確認後再決定預設。

參考檢查（`a91453/railway-reference-private` `a7e377b6`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「實景地圖的 OpenStreetMap 底圖（決策 97）」）：`Ci/` 的 `initOsmMapEngine`（MapLibre GL）、`osmStyleKey` 預設 `positron`（另有 `dark`、`fiord`、`liberty`）、`osmLabelLang` 預設 `local`、地圖下方的「OpenFreeMap © OpenMapTiles Data from OpenStreetMap」。

1. **依賴**：`maplibre-gl-native-distribution` 6.31.0（2026-09-11，`exactVersion`；二進位 XCFramework，sha256 `de3aaa43…` 由套件清單核對），只給 App target。`project.yml` 加套件、XcodeGen 2.46.0 重新產生；CI 與 Xcode Cloud 不自動解析套件（`-disableAutomaticPackageResolution`），所以提交 `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`（版本 6.31.0，commit `13e41ab3`）。
2. **授權**：MapLibre Native 是 BSD 2-Clause，二進位散布要附上著作權與條款：`Resources/Licenses/MapLibre-iOS-LICENSE.md`（官方 `platform/ios/LICENSE.md`，含它包含的第三方軟體的聲明）隨 App 打包，資料來源畫面多「MapLibre Native」與「OpenFreeMap」兩項。MapLibre 的標誌不是授權要求，所以隱藏；地圖底部的帶子（沿用 `AppleMapBackground.attributionHeight`）左邊是 OpenFreeMap 要求的文字（`DataSourceCredits.openStreetMapBaseMap`），畫了真實鐵道時接著鐵道的來源，右邊是 MapLibre 的來源按鈕。
3. **圖磚與樣式**：OpenFreeMap 的公開服務（免費、免金鑰、可商用，沒有服務保證），淺色用 Positron、深色外觀用 Dark（`OpenStreetMapBase.styleURL`）。
4. **相機**（`OpenStreetMapBase.camera`，GamePresentation，有測試）：MapLibre 的中心是遊戲畫面中點下的地點，縮放等級讓一個世界公尺（錨點緯度的一公尺）畫成和遊戲一樣多的點：z = log2(每公尺點數 × 赤道周長 × cos 錨點緯度 ÷ 512)，沿用 `StationLabels.zoom`。測試確認畫面兩角換到 MapLibre 的像素正好差畫面的寬與高。平面、北朝上，不接受自己的手勢，和 Apple 地圖相同（決策 50）。
5. **標籤**：OpenFreeMap 的樣式把拉丁名稱與當地名稱疊成兩行；照 `Ci/` 的 `osmLabelLang`，改成一種語言：中文介面依序取 `name:zh-Hant`、`name:zh`、`name`，英文取 `name:en`、`name_en`、`name:latin`、`name`（`OpenStreetMapBase.labelText`）。只換顯示名稱的圖層，道路編號（`ref`）、門牌照舊（`showsName`）。
6. **真實鐵道**：和 Apple 地圖上相同的資料、順序、顏色與寬度（決策 50）：每個 `sortKey` 先畫外框再畫各色路線，最後畫車站圓點，全部插在樣式第一個標籤圖層下面（道路之上、地名之下）。MapLibre 的圓圈外框畫在半徑外，所以中心半徑是 `stationRadius − stationRing / 2`；`stationsMinimumZoom` 起才畫。
7. **不動**：GameCore、存檔、golden、replay；Apple 地圖與它的三種樣式照舊（仍是預設）。

**限制**：
- 這個環境（Linux）不能編譯 App，App 端只由 CI 的 Xcode 建置驗證；畫面是否對齊、好不好看要在實機（TestFlight）確認。
- 沒有網路或 OpenFreeMap 停止服務時，底圖是空白的（Apple 地圖也一樣）；沒有離線圖磚。
- 還沒有傾斜、旋轉、3D 建築與地形，也還沒照 `Ci/` 隱藏軍事設施的標示（`applyOsmSensitiveFacilityLabelFilter`）；選點的畫面（`RealWorldPicker`）仍是 Apple 地圖。

### 98. 城市建造 P0-B：土地分區

2026-10-08，作者要求做城市建造 P0-B，方向照研究文件（`docs/research/CITY_BUILDING_STUDY.md` §4.4）的建議：分區另存一層，不用沒有人的 `LandCell` 假裝；城市擴張只在劃了分區的空格長出那個用途，沒劃分區的地方照舊；「不開發」與「保留地」兩種保護區；玩家建物 400 m 內地價加成（誘導開發）；App 單點或拖曳劃分區、圖層顯示分區；玩家建物佔住的格（決策 95）仍不長。號碼依工作登記 #231：存檔 23、golden schema 43（決策 97 是 OSM 底圖的登記）。

參考檢查（`a91453/railway-reference-private`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「城市建造 P0-B：土地分區（決策 98）」）：參考庫沒有分區、保護區、地價或依分區成長的規則（gap → 原生）。可以用的是操作與顏色：`Simulator/` 的地形筆刷（`onTerrainStroke`：一筆拖曳只存一次復原快照）是「一次拖曳是一個編輯」的做法；`Ci/` 的 `landuseColorByClass` 與 `map.legend.reserveExtent`／`airportExtent` 是分區圖層的顏色。

1. **資料**（GameCore，`City/Zoning.swift`）：`Zone` 有八種：住宅、商業、辦公、工業、公共設施、觀光（`use` 是同名的 `LandUse`），以及「不開發」（`noDevelopment`）與「保留地」（`reserved`，`use` 是 `nil`）。`GameWorld.zones`（`Zoning`）是依列、行排序、每格一次的 `ZonedCell`，和土地（`land`）分開：分區不是人，土地格與城市建物的意義都不變。玩家建物佔住的格可以劃分區，但城市照決策 95 不在那裡長。
2. **指令** `setZone(_:rows:columns:)`：把矩形裡每一格劃成那個分區，`nil` 清除；回傳改變的格數。矩形要在世界裡、每邊最多 128 格（`Zoning.maximumSide`，8 km），否則 `invalidZoneArea`，世界不變。免費，當下不改土地：城市成長時才照分區。
3. **照分區開發**（`spread(towards:)`，決策 75 的成長每站每晚蓋一格）：
   - 車站腹地裡有**劃了用途、空的、沒被玩家建物佔住**的格時，蓋在**地價最高**的那格（再依距離、列、行），用途是分區的用途，不必在有人的格旁邊（玩家允許了）；新格的人數照空白地圖城鎮的比例（決策 72、91）以 4 人為底：住宅 4／0、商業與辦公 1／12、公共設施 1／4、觀光 0／4、工業 0／8。
   - 沒有這種格時照舊：離車站最近、在有人的格旁邊的空格蓋 4 人住宅，但**跳過劃了分區的格**（走到這一步時，腹地裡劃了分區的空格只剩不開發與保留地）。
   - 腹地裡沒有任何分區時，結果和之前完全相同；沒有分區的世界不查地價。
4. **兩種保護區**（A 列車的開發凍結與保留地）：
   - 不開發：不蓋新格；已有的格不再成長（`grow` 不加人，那一份不補給別格）、不升級（`raiseBuildings` 跳過）。
   - 保留地：不蓋新格；已有的照常成長與升級（留給玩家之後蓋軌道或公司建物）。
5. **誘導開發**（地價，決策 76 的公式多一項 `C`）：**劃了用途分區**的格，中點離任何一棟玩家建物的中心不到 400 m（25,600 單位）時加 600 美分／m²（`LandValueRules.companyPremium`，和公園溢價相同）；`LandValue.companyPremium`。只加在劃了用途的格，所以沒有分區的世界地價不變（P0-C 的建造費、租金、收購價也不變）；玩家可以在自己的建物旁劃分區，提高那裡的地價，城市就先往那裡長。成長只為了選分區格讀地價，升級仍不讀（決策 75）。
6. **畫面**：建築工具的模式多了「分區」（`BuildingToolMode.zone`）：選八種分區或「清除」，點一格劃一格，單指拖曳劃一個矩形（雙指仍可移動、縮放地圖；第二指放下時取消這次拖曳）；拖曳時地圖畫出矩形（分區的顏色，清除是灰框），放開才是一個可以復原的編輯（`GameSession.dragZone`、`endZoneDrag`、`zone(_:)`）。切到分區模式時地圖自動開「土地分區」圖層（`PopTravelMode.zoning`，也在地圖圖層表的「城市」）：每格依分區著色，縮小時區塊取最多的分區；點格的提示框寫出分區與「鄰近公司建物」的溢價。
7. **存檔**：版本 23。世界只在有分區時寫 `"zones"`：同一列相鄰、同一分區的格寫成一段 `{"row", "column", "zone", "count"}`；讀檔檢查每格在世界裡、依序、不重複。版本 22 以前沒有分區。新的 `SaveFixtures/v23-zoning.json`。
8. **golden**：schema 43，新指令 `setZone`、觀察 `zone`、結果 `invalidZoneArea`、最終狀態選填的 `zones`（各分區的格數）、`landValue` 選填的 `companyPremium`；新的 `zoning.json`（`city-buildings-growth.json` 加上分區：新格蓋在商業區、跳過不開發）與 `zoning-land-value.json`。既有 golden、存檔與 replay 的預期值都沒有改變（規則只在有分區時改變結果）。
9. **UI 測試**：`StartSaveFlowSmokeTests.testCellsZonedByADragAreKeptBySavingAndContinuing`（拖曳劃商業區，存檔、繼續後仍在），在完整的 UI 測試，不在 PR 的 gate。

**限制**：分區不會把已經有的格改成那個用途（只影響空格）；沒有住商工的需求閥（模擬城市的 RCI），成長量仍是決策 70／75 的車站服務；分區格的地價基準仍是空地，不因分區而提高；拖曳只能畫矩形（參考的筆刷是圓形一筆一筆畫，之後需要時再加）。

### 99. 建造時自動暫停

2026-10-08，作者要求的 UI/UX 改版第一步（UX-0）：決策 82 第 4 點讓遊戲時間前進就清空復原紀錄，遊戲在跑時幾乎每 0.1 秒就有一個 tick，所以建造時一失手常常已經不能復原。只改 GamePresentation：GameCore、存檔、golden、replay 都不變。參考庫（MapBuilder 是編輯器，沒有時鐘；`Ci/`、`Simulator/` 也沒有「建造時暫停」）沒有可移植的做法，這是本專案的規則。

1. **哪些工具**：`ConstructionTool.pausesGame`，路網與建築兩個會建造、拆除的工具是 `true`；選取與列車是 `false`（列車工具要看列車出發、行駛，暫停反而礙事）。
2. **選工具時**（`GameSession.selectTool(_:)`）：選了會暫停的工具，而遊戲在跑，就暫停（`GameWorld.pause()`），記下 `isPausedForBuilding`，並顯示一則訊息說明為什麼時間停了、怎麼繼續。遊戲本來就是暫停的，不記、不顯示。
3. **離開時**：換到不會暫停的工具時，若 `isPausedForBuilding` 而且時鐘仍是暫停，就恢復（`GameWorld.resume()`，回到暫停前的速度，`GameClock.resumeSpeed`）。在路網與建築兩個工具之間切換，維持暫停。
4. **玩家自己的選擇優先**：玩家按暫停／播放（`togglePause()`）或選速度（`setSpeed(_:)`）就放掉 `isPausedForBuilding`：之後離開工具不再改速度。玩家在建造時按播放，遊戲照跑；之後再選一次會暫停的工具，又會暫停。
5. **不算編輯**：暫停與恢復本來就不是編輯（決策 82 第 2 點），不推快照；復原保留目前的暫停與速度。`isPausedForBuilding` 只在 session 裡、不存檔；存檔裡的時鐘照原本記錄暫停與否。
6. **測試**：`BuildPauseSessionTests`；`TrainSessionPropertyTests` 的參考模型照第 2、3 點對時鐘做同樣的事；原本假設選了路網工具時鐘仍在走的兩個測試（`UndoSessionTests`、`TrainControlTests`）改成先回到選取工具。

**限制**：沒有設定可以關掉；路線面板的編輯（站序、停站模式）不是工具，不會自動暫停。

### 100. 起點＋終點建立路線

2026-10-08，作者要求的 UI/UX 改版（UX-1a）：新路線原本要逐站「選車站 → 加入選取的車站」。改成玩家只點起點與終點，沿途車站依真實的軌道找出，再選停靠方式。只改 GamePresentation 與 App：GameCore、存檔、golden、replay 都不變。

1. **沿途車站**（GamePresentation，`GameWorld.stationsAlongTrack(from:to:)`）：在世界的副本上建一條只有兩站的路線，取 GameCore 自己的 `lineJourney(_:)`（Stage S5，列車實際會開的路徑）的去程，沿它走過的每一段軌道（`LineMap.pieces(of:in:)`，從決策 84 的 `ranges(of:in:)` 抽出，畫路線的結果不變），列出月台與走過的範圍重疊的車站，依經過的順序。不看車站站在哪裡（決策 80 把車站排進既有路線時用的是位置，這裡不用）。月台全在另一條軌道上的車站（雙線的另一側）不算經過。開不出這條路線（任一站不存在、同一站、沒有軌道接到兩站的月台）時是 `nil`。
2. **經過點選的站**（`stationsAlongTrack(through:)`）：玩家點了兩站以上時，每相鄰兩站各找一次再接起來。有分岔時，點中間的車站就決定走哪一邊；不另外做「挑選候選路徑」的畫面。
3. **停靠方式**（`LineDraftStopping`）：沿途各站停靠（預設，新手最直覺）、只停點選的車站（只點兩端就是直達）、自訂（逐站開關，兩端一定停）。做法是決定路線的站序（`createLine` 的 `stops`），不是加停站模式（`LinePattern`）：停站模式要另外把列車指派到它，對第一次建線的玩家太繞；只停兩端的路線，列車照樣沿軌道經過中間的車站。
4. **在地圖上選站**（`GameSession.startPickingLineStops()`）：開始後，地圖上點到的車站（`tapMap(at:reach:)`）直接加到草稿，不用每站按一次「加入選取的車站」（按鈕保留）。路線面板開著時，App 本來就把地圖的點擊交給 `tapMap`，不論目前的工具；面板關閉或路線建立後停止選站。
5. **跟著軌道更新**：草稿的路線（`lineDraftRoute`）在草稿改變、草稿有兩站以上時軌道改變（`performEdit`）、復原或拆站（`dropSelectionOfMissing`）時重算；建立時再算一次。沒有軌道相連時，照舊用點選的車站建立，並提醒玩家列車要等軌道接通才能開。
6. **畫面**（`LinesPanel`）：「新路線」移到面板最上面（半高的面板在選站時看得到）；顯示已點選的站、停靠方式、自訂時逐站開關、最後的站序與站數，「建立路線」與「清除」。教學「建立路線」一步的說明改成新的做法（完成條件不變）。

**行為改變**：點兩站而軌道經過其他車站時，預設會多停那些車站（`LineSessionTests` 的 Alpha → Gamma 現在是 Alpha → Beta → Gamma）。

**參考**：`Ci/` 一次加一站（`tutorial.transport.18`），MapBuilder 依位置插入（決策 80），兩者都沒有沿軌道找站；私有參考庫的其他尋路（`Railway/taipei_gta_reference` 的人物 worker）與這個問題無關。外部專案沒有可直接用的；用的是本專案 GameCore 既有的路徑搜尋。

**限制**：只取最短（列車實際會開）的一條路；分岔要靠點中間的站。環線仍照舊在路線面板設定。


### 101. 一步為路線配置列車

2026-10-08，作者要求的 UI/UX 改版（UX-4）：建好路線後，原本要對每一列車各做一次購買、放置（選車站、選朝向）、指派，再到各時段設定班距。改成玩家只選「多久一班」，一步完成。只改 GamePresentation 與 App：GameCore、存檔、golden、replay 都不變。

1. **計畫**（`GameWorld.lineStaffingPlan(_:headway:)`）：需要的列車數 = 路線本線行程的來回分鐘（`LineJourney.roundTripMinutes`）÷ 班距，無條件進位，至少 1 列，最多是路線能跑的列車數（`lineMaximumTrains`）；費用 = 列車單價 × 列車數（`purchaseTrain` 的價格）。實際班距 = 來回 ÷ 列車數，進位（受上限限制時會比要求的長，畫面照實顯示）。班距選項 3、5、10、15、20、30 分鐘，最短 2 分鐘（`ServiceLine.minimumHeadwayMinutes`）。開不出行程（沒有軌道接到各站的月台）與環線（兩個方向各要自己朝向的列車）沒有計畫。
2. **執行**（`GameSession.staffSelectedLine(headway:)`，一次編輯，可以一步復原）：逐列購買；放在路線行程起點的停車位置（`lineJourney` 的 `start`，正是派車時會找的「停在第一站、能開完整趟」的位置），設好停車點與性能；指派到路線本線；最後把本線三個時段的目標班距都設成選的班距。錢不夠時整個拒絕。
3. **疊在同一個停車位置**：交通控制關閉時，放置不在意同處的其他列車（`placeTrain` 的規則），所以列車一列一列排在起點，路線依班距逐一送出（測試 `LineStaffingTests` 在直線四站上跑 12 小時，確認每一列都發車、間隔至少一個班距）。交通控制開啟時，放不上去的列車留在軌道外、已指派，訊息請玩家之後放到起點站；本專案沒有車庫，之後若加車庫再改。
4. **畫面**（`LinesPanel`）：選取的路線還沒有列車、不是環線時，在「新路線」下面出現「〈路線〉的列車」：班距（分段選擇）、來回分鐘與需要幾列、實際班距、費用（錢不夠時紅字並停用按鈕）、「購買 N 列並開始營運」。建立路線後它就是選取的路線，所以這一段緊接著出現。各時段的列車數照舊在下方調整。

**參考**：`Ci/` 的路線建立時自帶列車（`spawnTrains`），列車數是加減按鈕；沒有依班距計算列車數的做法可移植，這是本專案自己的計算，用的是既有的行程與上限。

**限制**：只處理本線，不處理停站模式；環線照舊用列車工具；列車用預設編組（1 節）與路線的性能。

### 102. 用手指拖曳鋪軌

2026-10-08，作者要求的 UI/UX 改版（UX-1b）：鋪軌原本要點起點、點終點、再按建造。加上拖曳：從起點或既有軌道開始拖，就畫出下一段軌道，預覽（曲線、費用、問題）跟著手指；放手後預覽留著，按「建造軌道」才建造、扣款。只改 GamePresentation 與 App：GameCore、存檔、golden、replay 都不變。

1. **哪一種拖曳畫軌道**（`GameSession.networkDragDraws(from:reach:)`）：路網工具在鋪設模式時，起點在已選的起點附近（觸控半徑內），或在既有軌道上（節點、或吸附軌道開啟時邊上的一點）。其他拖曳照舊移動地圖，兩指照舊移動與縮放；所以在空地上拖曳不會選到任何一端（`MapInteractionTests` 的規則不變）。空地上要先點一下放下起點，再從它拖出去；建好一段後終點就是下一段的起點，所以可以一段接一段地拖。
2. **拖曳中**（`dragNetwork(from:to:reach:)`）：第一次呼叫決定起點：在已選的起點上就沿用，否則用拖曳開始處的軌道（和點選相同的吸附規則，`networkAnchor(at:reach:)`，從 `tapNetwork` 抽出）。終點跟著手指，吸附規則同點選；回到起點觸控半徑內就沒有終點（等於取消這一段）。`networkPreview` 跟著更新，和點兩下時是同一個預覽、同一套 GameCore 檢查。
3. **放手**（`endNetworkDrag`）：預覽留著，不建造、不扣款；建造照舊是「建造軌道」按鈕，可以復原（決策 82，建造時遊戲自動暫停見決策 99）。**取消**（第二根手指、系統中斷，`cancelNetworkDrag`）：終點回到拖曳前。
4. **手勢**（App 的 `MapGestures`）：決策 98 的 `paintsWithOneFinger`（整個工具一律單指畫）改成 `paintsFrom`：每次拖曳開始時依起點決定畫或移動。分區照舊一律畫。
5. **邊緣捲動**：畫的時候手指離畫面邊緣 44 點以內，地圖往那邊捲動，越靠邊越快（最快每秒 480 點）；拖曳開始處跟著地圖移動，所以分區的矩形與軌道的起點都不會錯位。
6. **提示**：路網工具已有起點時的說明改成「請點終點，或從起點拖曳過去」。

**參考**：MapBuilder、`Simulator/` 的編輯器是點選與拖放零件，沒有畫軌道；外部專案（例如 OpenTTD 的拖曳鋪軌）是 GPL，只參考想法、沒有複製程式碼。這是本專案在 C1 的點選建造上自己加的。

**限制**：一次拖曳只畫一段（一條邊，曲線由兩端方向決定）；拖出長的折線自動切成多段，留到之後。邊緣捲動只在 iOS 上，Linux 上無法測試（`NetworkDragTests` 測 session 的部分）。


### 103. 一棟接一棟地蓋：再點一下就蓋、點一下直接蓋、拖曳虛影

2026-10-08，作者要求的 UI/UX 改版（UX-2）：P0-C2（決策 95）起建築工具是「點地圖顯示虛影 → 按動作按鈕建造」，安全但每棟要在地圖與按鈕之間來回。研究 `CITY_BUILDING_STUDY.md` §4.5 的「虛影可以拖曳」也還沒做。只改 GamePresentation 與 App：GameCore、存檔、golden、replay 都不變。

1. **再點一下就蓋**（`tapBuildingTool`）：已顯示的虛影可以蓋（沒有問題）時，點在虛影上就建造（`confirmBuilding()`，和動作按鈕相同，一次編輯、可以復原）；點在別處照舊把虛影移過去。不能蓋的虛影（紅色）點了只是移動，所以絕不會蓋在被拒絕的地方。
2. **點一下直接蓋**（`buildingBuildsOnTap`，預設關閉）：開啟時每點一下就在那裡建造，連續蓋一排房子只要一棟一下；每一棟都是一次可以復原的編輯，建造時遊戲自動暫停（決策 99）。GameCore 拒絕時照舊顯示原因、不扣款。
3. **拖曳虛影**（`buildingDragMoves(from:)`、`dragBuildingSite`、`endBuildingDrag`、`cancelBuildingDrag`）：從虛影上開始的單指拖曳移動虛影，預覽（費用、收購、問題）跟著它；放手後讀入那裡的土地（和點選相同），取消時回到原處。其他拖曳照舊移動地圖。App 用決策 102 的 `paintsFrom` 判斷。
4. **畫面**（`BuildingControls`）：經營模式下每種建物的按鈕顯示建造費（`buildingStartingCost`，不含依地價而定的土地使用權）；「點一下直接蓋」開關；可以蓋的虛影下方提示「再點一下就蓋，或把它拖到別的地方」。

**參考**：`Simulator/` 的 `onDropStructure`（拖放後確認、拖曳區）是這裡拖曳虛影與確認的想法來源（`CITY_BUILDING_STUDY.md` §2）；旋轉把手不需要，三種建物都是正方形。程式是本專案自己寫的。

**限制**：沒有「拖出一排自動蓋滿」；虛影的拖曳只在 iOS 上（`BuildingFlowTests` 測 session 的部分）。

### 104. 底部工具列：圖示加名稱、路線與資料入口、再點一下回到檢視

2026-10-08，作者要求的 UI/UX 改版（UX-3 的第一步，主畫面以地圖為主）：路線原本只是 HUD 上一個沒有名字的圖示，經營資料只能點現金開啟，新玩家找不到；離開建造工具要特地按「選取」。只改 App：GamePresentation、GameCore、存檔、golden、replay 都不變。

1. **工具改成「圖示在上、名稱在下」**（`TabLabel`，像遊戲的底部列），省下寬度。按鈕、識別字（`tool.*`）、無障礙名稱與教學的聚光目標都不變。
2. **路線與資料入口**（`QuickEntries`）：工具旁加「路線」（開啟路線面板）與「資料」（開啟經營面板），有名字。只放在單列的工具列（手機的抽屜、iPad 收起的卡片、手機橫放）；iPad 展開的卡片照舊用 HUD 的按鈕。無障礙名稱是「開啟路線」「開啟經營資料」，不和 HUD 的「Lines」同名（UI 測試用名字找它）；識別字 `entry.lines`、`entry.economy`。HUD 的路線按鈕與點現金照舊。
3. **再點一下目前的工具回到檢視**：建造工具（路網、列車、建築）再點一下就回到選取工具，地圖恢復點選查看；有決策 99 時遊戲同時恢復。教學進行中不這樣做：教學的步驟等某個工具保持選著，而教學 UI 測試的重試會再點一次。

**沒有做的**（需要實機截圖判斷，留給作者決定）：手機抽屜展開時固定 42% 的高度（改成依內容會讓地圖每分鐘跟著文字長短跳動，原本就是為此固定）；拿掉「選取」按鈕（UI 測試與教學都用它）；把路網與建築合成一個「建設」入口。

**參考**：`Ci/` 的底部列（`cities/anycity-global/index.html` 的 `#bottombar`）把「添加線路」（`nav-btn-add-line`）與「控制中心」（`nav-btn-control-center`，運量與線路資料）做成底部的圓形工具按鈕，只有圖示與提示框；這裡照它把路線與資料放到底部的工具旁，另外加上名稱（觸控沒有滑鼠提示框）。程式是本專案自己寫的。

### 105. 地形：水域（海岸線、河川與湖泊）

2026-10-09，作者要求 ROADMAP Phase 6「地形與土地狀態」的第一步：實景地圖上城鎮會往海上、河上長，玩家建物也蓋得上去。決策 96 已以玩家的角度定好：水域（海、河、湖）是唯一真正的障礙；森林、自然保護區不是障礙；墓地、坡度之後再做；軍事區不建模。這一步只做水域。號碼依工作登記 #231：存檔 24、決策 105、golden schema 44。

參考檢查（`a91453/railway-reference-private`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「地形：水域（決策 105）」）：`Railway/site_archive_clean/data/taiwan_land.json`（內政部縣市界合併的海岸線，政府資料開放授權 1.0）是決策 91 預定的海陸遮罩資料，這次拿來和 OSM 的海岸線比較（第 2 點）；`taipei_gta_reference` 的 `surfaceAt`（地面是一種，`'water'` 是其中之一）與 `UD()`（建物的取樣點都要落在允許的地面）是「地形是另一層、建物檢查腳下的地面」的範本；參考沒有河湖的資料、也沒有「城鎮不往水上長」的規則（gap → 原生）。外部專案（只取想法，沒有程式碼）：OpenTTD（GPL-2.0）的水是一種格（`MP_WATER`），城鎮的房子與道路不蓋在上面（`DC_NO_WATER`），過水要橋；Simutrans（Artistic License）的水是低於水位的地面，另有水位的格網；OSMCoastline（GPL-3.0）把 `natural=coastline` 的 way 頭尾接成環、陸地在左邊。

1. **地形是另一層**（GameCore，`City/Terrain.swift`）：`Terrain` 記哪些 64 m 格是水，存成每列的連續段（`WaterRun {row, column, count}`，依列、行排序，段與段不重疊也不相鄰，所以同一組格永遠是同一組段）。不是第九種用途：`LandUse`、土地格與建物的意義都不變。`GameWorld.terrain`，`isWater(row:column:)`。
2. **資料**（`tools/real-world-population/build_water_grid.py`，打包成 `taiwan_water.json`，530 KB）：
   - 格網是人口格（30″）切成 16 × 16（1.875″，約 58 × 53 m，大約一個 64 m 格），範圍是台灣的陸地（本島、澎湖、金門、馬祖與小島）外加 0.1°（約 11 km，比 16 km 地圖的一半多），9,296 × 8,064 格。一格的中點落在水裡就是水。
   - **海**：OSM 的 `natural=coastline`（osmtoday.com 2026-10-06 的整包檔，pyosmium 讀）頭尾接成 704 個封閉的環，環外（奇偶規則）是海；本島 35,978 km²。被整包檔的邊界切斷、接不成環的一段（金門北邊的中國大嶝島）不是台灣的，不算。
   - **河湖**：`natural=water`、`waterway=riverbank`、`waterway=dock`、`landuse=reservoir` 的面（內環是島），但**魚塭**（同時是 `landuse=aquaculture`，或 `water=fishpond`）不算：決策 96 把它當農業。`natural=bay`、`strait`（海已經由海岸線決定，海灣的面常常蓋到岸上）、`natural=wetland`、`landuse=salt_pond`、`landuse=basin`（常常是乾的滯洪池）、`natural=shingle` 的河床都不算水。結果：陸地 36,381.6 km²，其上的河湖 798.4 km²（整包檔的 `natural=water` 約 902 km²，扣掉魚塭與海岸線外的部分）。
   - **為什麼用 OSM 的海岸線、內政部的只用來核對**：內政部的縣市界合併後以約 150 m 簡化（只是參考網站圖磚載入前的底圖），比 64 m 格粗；而且縣市界畫到低潮線，彰化、雲林的潮間帶、新竹香山與金門的潮灘都算陸地。兩者在 99.79% 的格一致；內政部算陸地、OSM 算海的有 434.5 km²，集中在彰化鹿港到雲林麥寮的潮間帶（每 0.1° 見方 25–36 km²）、嘉義與台南的沿海、新竹香山與金門；反過來的只有 53.1 km²。城鎮不該長在潮灘上，OSM 也和 OSM 底圖（決策 97）畫的水一致，所以遮罩用 OSM，內政部的檔只在工具裡核對（第四個參數）。
   - **限制**：整包檔只有台灣，所以格網範圍裡**對岸的陸地**（金門對面的廈門、馬祖對面的連江）算海；那裡 WorldPop 本來就沒有人，只影響金門、馬祖的 16 km 地圖邊緣（玩家不能在那裡蓋建物或劃分區，鐵路照樣能蓋）。格網範圍外沒有水（例如東京的地圖照舊）。
3. **規則**（GameCore）：
   - 城市擴張（`spread(towards:)`）不把新格蓋在水上（劃了分區的水格也一樣）；水上沒有土地，所以不成長、不升級。
   - 玩家建物（P0-A／C，`placeBuilding`）的正方形碰到任何一格水（只碰到邊不算）就拒絕：`GameError.onWater(row:column:)`，指名第一格（依列、行），檢查順序在軌道與車站之後。建築工具的預覽照常把原因寫出來（「水上不能蓋建物，也不能劃分區。」）。
   - 分區（P0-B，`setZone`）：矩形裡的水格不劃分區（原本有的也清掉），其餘照劃；**整個矩形都是水**而且不是清除時拒絕（`onWater`，指名矩形的第一格）。
   - 鐵路與車站：這一步**不擋**，照樣能蓋在水上。
4. **指令**：
   - `setWater(_:)`：以任意順序的格整個替換水（`[]` 清除）。拒絕（`invalidTerrain`，世界不變）：格在世界外、列兩次、上面有土地，或世界的土地是按需展開的。地面先於土地：實景新遊戲先 `setWater` 再 `setLand`。
   - `setLand(_:)` 拒絕水上的格（`invalidLand`）；`foundTowns(seed:)` 略過水上的格（實景地圖沒有人時的城鎮）。
   - `expandLand(_:cells:water:)`（決策 88）：區塊帶著自己的水一起讀入；水要在這批區塊裡、不重複、不在這批的土地下面（`invalidTerrain`）。區塊讀入前城鎮已經長到的格（只有 App 沒有人口資料時才會）保持是陸地，那格不算水。水是區塊自己的，段會在區塊之間接起來，所以**讀入的順序不影響結果**。`setLandOnDemand()` 也清空水。
5. **實景地圖**（GamePresentation）：
   - `WaterGrid` 讀 `taiwan_water.json`（`RealWorldData.load` 多讀一個檔，`GameLauncher.water`、`GameSession.water`），`cells(frame:bounds:in:)` 給整張地圖或指定區塊的水格：每個 64 m 格看它中點所在的水格（Web Mercator 讓列只看 y、欄只看 x，和 `LandImport` 找 WorldPop 格一樣），指定區塊時正好是整張圖在那些區塊裡的格。
   - `LandImport` 多一個 `water`：水上的格沒有土地；WorldPop 格的人、地點的就業與分區（決策 93）只分給它乾的格，規則照舊；一個 WorldPop 格在地圖裡的部分全是水時，它的人不算（他們住在地圖外的那一部分，或兩份資料的海岸線畫得不同）。
   - 新遊戲（`startNewGame(at:)`）、實景示範與平溪線挑戰都帶著水；全台灣地圖每讀一批區塊就帶那批的水（`readLand(...water:)`）。
   - **不畫水域圖層**：Apple 地圖與 OSM 底圖本來就畫了水；城市圖層裡水格本來就是空的。資料來源畫面的 OSM 說明加上海岸線、河川與湖泊。
6. **數字**（16 km 地圖，地圖中心為台北車站、基隆、高雄、馬公等；`WaterGridTests`、PR 說明有完整的表）：

   | 地圖 | 水格 | 土地格（前 → 後） | 居民 | 就業 | 中心車站 |
   | --- | --: | --: | --: | --: | --- |
   | 台北 | 4,048 | 64,829 → 61,017 | 4,687,421（不變） | 2,127,394 → 2,126,285 | 辦公 63,097 → 63,057 |
   | 基隆 | 18,806 | 35,437 → 32,424 | 459,120（不變） | 195,659 → 194,122 | 住宅 18,628 → 17,776 |
   | 高雄 | 21,113 | 48,310 → 43,912 | 1,628,103 → 1,628,096 | 470,122 → 466,174 | 住宅 18,266 → 18,270 |
   | 馬公 | 47,130 | 19,166 → 15,631 | 66,521（不變） | 36,029 → 35,856 | 住宅 6,624 → 6,545 |

   原本在水上的土地格（台北 3,825、基隆 3,237、高雄 4,501、馬公 4,731）的人搬到同一個 WorldPop 格的乾格，所以居民幾乎不變；少的就業是工廠與農地每格固定的就業（決策 93）隨著那些格消失。存檔變大約 5–25%（水的段，加上土地的段被水切開）。匯入一張圖多約 0.01 s（Linux debug）。
7. **存檔**：版本 24。世界只在有水時寫 `"terrain": {"water": [{"row", "column", "count"}, …]}`；讀檔檢查段在世界裡、依序、分開、不在土地下，按需展開的世界只在讀過的區塊裡。版本 23 以前沒有水，照舊讀；只讀到 23 的 build 會丟掉水（城鎮又會往海上長），所以升版。新的 `SaveFixtures/v24-water.json`。
8. **golden**：schema 44，新指令 `setWater`（`runs`）、觀察 `water`、結果 `invalidTerrain`、`onWater`（`row`、`column`），最終狀態選填的 `water`（水格數）；新的 `water-terrain.json`（`zoning.json` 的世界，(1, 1) 是水）。既有 golden、存檔與 replay 的預期值都沒有改變（規則只在有水時改變結果；空白地圖沒有水）；replay 的狀態描述只在有水時多寫水的段。
9. **空白地圖**：先不產生水域。由種子產生河湖要決定形狀、會不會切斷起始城鎮與平衡（新遊戲的回本，決策 46），不是小代價；留給之後的「由種子產生的地形」。

**限制與之後**：
- 鐵路與車站可以蓋在水上、沒有額外費用；之後要決定橋梁的造價（`TrackStructure.bridge` 已有 4 倍的價格，但沒有規定水上一定要是橋）與水上車站要不要禁止。
- 水上格的地價查詢照舊回答空地的值（沒有人會在那裡蓋）；城市圖層與分區圖層不特別標出水格。
- 對岸的陸地算海（第 2 點）；格網 1.875″，比 64 m 格略細，窄於約 50 m 的河道（多半只有中心線的 `waterway=river`）不算水。
- 墓地、坡度與高度、森林與保護區的整地費（決策 96）是之後的地形層。

### 106. 地圖優先的主畫面：手機只橫拿、地圖滿版、狀態膠囊、底部工具列、細節卡片、地區外觀

2026-10-09，作者看了實機截圖（手機直拿時：兩行的 HUD、往下疊的訊息、固定佔 42% 高度的抽屜，地圖只剩約三分之一），比較 TheoTown、SimCity BuildIt 的實機截圖、參考庫的網站與遊戲，以及開源遊戲之後決定的 UI/UX 改版第一步（UX-5a）。只改 App 與 GamePresentation 的一處訊息時間：GameCore、存檔、golden、replay 都不變。

1. **iPhone 只橫拿**（`project.yml` 的 `UISupportedInterfaceOrientations_iPhone` 只剩左右橫向，Xcode 專案重新產生）；iPad 照舊四個方向。建造類遊戲的工具列、類別選單與確認鈕在橫向排得下，直向要另做一套；作者提供的 TheoTown 與 SimCity BuildIt 都只有橫向。以後要做各國，國家的形狀各不相同，方向不依某國決定。
2. **同一個版面給所有裝置**（`ContentView.gameLayout`）：地圖鋪滿，控制項浮在邊上，不再擠壓地圖。
   - 左上是**狀態膠囊**（`StatusPill`，裡面是 `HUDView`：現金、時間、速度、選單），放得下時一行，寬度跟著內容。
   - 左下是**工具列**（`ControlDock`：工具、路線與資料、復原、顯示／隱藏細節的按鈕）。
   - 右側是**細節卡片**（`DetailsCard`：選取的東西與工具的選項，`ControlPanel` 的 details），只在有東西要看時出現（`ControlDetails`，規則不變）。寬 min(340, 畫面的 40%)；高度跟著內容，最高到畫面可用的高度，再多就捲動；卡片浮在地圖上，內容隨時間變長變短不會移動地圖。工具列和卡片並排放不下時（窄的手機），卡片停在工具列上方。選取工具選到車站時，卡片頂端是車站的站名牌（第 6 點）；iPad 在下方附路網總覽（原本 iPad 卡片裡就有）。
   - **路線、車站、經營資料改在地圖旁邊**（`GameScreenState.Panel.isBesideMap`）：手機橫拿時 iOS 把每個 sheet 都蓋滿整個畫面（半高的 detent 不適用），在地圖上選站建路線（決策 100）、換選另一座車站都會做不到，所以這三個面板改從右側滑出，寬 min(420, 畫面的一半)，在狀態膠囊下方，地圖照樣看得到、點得到；開著時細節卡片讓位。它們的「完成」改成直接關掉面板（`screen.panel = nil`），不再用 `dismiss`。其他面板（時刻表、車隊、圖層、資料來源、設定、年報、目標）照舊是 sheet。
   - 拿掉手機直拿的 42% 抽屜（決策 104「沒有做的」第一項）與 360 點寬的控制卡片（含 iPad 卡片展開時的工具說明清單）。`mapInsets` 多了頂端（膠囊）與底部（工具列）；地圖左下的圖層與底圖按鈕移到工具列上方。
3. **路線只從工具列開**：HUD 上沒有名字的路線圖示拿掉；工具列的「路線」接下它的無障礙名稱「Lines」、提示與教學的聚光目標（`TutorialTarget.linesButton`，原始值 `hud.lines` 不變）。改了決策 104 第 2 點：那時為了不和 HUD 同名才叫「開啟路線」。
4. **工具列的名稱改用 caption**（原本 caption2，在玻璃上太小）。
5. **訊息**：問題訊息也會自己消失，越長留越久：4 秒加每字 0.1 秒，至少 6 秒、最多 10 秒（`StatusMessage.autoDismissDelay`，成功照舊 4 秒）；VoiceOver 開著時問題訊息照舊留到關掉。新的訊息（包括同樣的文字再出一次）讓橫幅彈一下，不另外疊一張。
6. **地區外觀**（`RegionStyle`，環境值 `regionStyle`）：一個國家「長得像那裡的鐵道」的少數顏色與造型，疊在各國共用的 `Theme` 之上；換國家只換它，版面與控制項不變。目前只有台灣，只有站名牌（`StationNameboard`）用到：藍皮普快的藍（2021 年藍皮解憂號復駛時考證恢復的車身色）#1D4F91、白字（8.1:1），深色模式 #8DB6EE、深藍字 #162544（7.3:1）。台鐵、高鐵都沒有公開色碼，這是近似值，要在實機上確認。作者要求不用網站（參考庫 `Railway/site_archive_clean/`）的配色；查到但還沒有東西用的台灣鐵道色（台鐵公司新指標的北上藍、南下綠，2026 年起從新臺南地下站開始；鳴日號與高鐵的橘）等用到時再加。以後的日本外觀照同樣方式另做一組。
7. **各國化的版面規則**（之後的介面 PR 都照做）：用 leading／trailing，不寫死左右；站名等名字會縮小或換行，不只照中文長度設計；地區的顏色與造型只經過 `RegionStyle`；金額一律走 `moneyText` 等既有的格式化，換國家時只改那裡；地圖一開始看哪裡由劇本決定，介面不假設台灣。
8. **開始畫面**：手機橫拿時標題在左、按鈕在右邊自己的捲動欄，前幾個按鈕不必捲動就看得到（`StartView`，依 `verticalSizeClass`）；直拿的 iPad 照舊一欄。
9. **UI 測試**：原本設成直拿的改成橫拿；轉向測試改成從一側轉到另一側。點地圖的位置移到地圖的前半：選了工具時細節卡片浮在後半。教學的鋪軌測試在地圖上找兩個不被任何控制項蓋住的點（教學卡片在寬螢幕上可能站在地圖中間旁邊，只找空的一列不夠；也避開圖層按鈕、工具列與細節卡片），失敗時寫出各框的位置；開始畫面的按鈕看不到時先捲動那一欄。

**沒有做的**（之後的 UX-5b 起）：拿掉「選取」按鈕與「建設」入口（UI 測試與教學都用 `tool.select`）；鋪軌時的側邊工具列、預覽終點旁的確認與費用、起終點旗子；點一下物件浮出的小標籤與地圖上的狀態泡泡；車站選址的人口熱度與涵蓋人數。

**參考**：參考庫的網站（`Railway/site_archive_clean/index.html`）iPhone 上地圖約佔 85%：頂端一顆時鐘膠囊（`#clock`）、底部分頁（`.tabbar`）、點列車時左下的小卡片（`.follow-panel`）而不是半屏面板，訊息最多 3 則、5 秒（`showToast()`）；`Ci/` 的底部列（`#bottombar`）只有一排圓形圖示；`Simulator/` 手機版的進階選項收在預設關閉、有把手的抽屜（`.mobile-sheet-handle`）；`Railway/taipei_gta_reference/` 的 `notify()`（`game-vXklz4A8.js`）訊息時間 `min(9, 3.2 + 長度 × 0.09)` 秒、同樣的訊息不疊而是彈一下。外部的遊戲只看做法：TheoTown、SimCity BuildIt（作者的實機截圖）、Mindustry（GPL-3.0）、Unciv（MPL-2.0）、OpenTTD Android（GPL-2.0），沒有拿程式碼。程式是本專案自己寫的。

### 107. 建造模式：起終點插旗、在預覽旁確認、進階選項收起

2026-10-09，UI/UX 改版第二輪的 UX-5b（決策 106 之後）：作者的實機截圖裡，鋪軌時卡片塞滿工程選項（構造、新節點高度、平順曲線、緩和坡度、清除、吸附軌道），主要的「鋪設軌道」按鈕在選好兩點之前一直是灰的，而且在畫面的另一邊。只改 App 與 GamePresentation 的兩個小介面：GameCore、存檔、golden、replay 都不變。

1. **起終點插旗**：路網工具預覽一段軌道時，起點插一面旗（`flag.fill`）、終點插一面方格旗（`flag.checkered`），旗子立在點的上方，點本身不被擋住（`MapBuildConfirm`）。位置由 `GameSession.networkStartPlanPoint`、`networkEndPlanPoint` 給（決策 102 的 `planPoint(of:)`：點、節點或軌道上的位置）。
2. **在預覽旁確認**：終點下方（下方放不下時在上方）浮出一顆膠囊：「✗」取消（`clearNetworkDraft`）、「✓ $費用」建造（`buildNetworkTrack`），有問題或沒有費用時 ✓ 不能按。建築工具的虛影下方也是同一顆（✗ 是新的 `clearBuildingSite()`，✓ 是 `confirmBuilding()`）。膠囊避開狀態膠囊、工具列與細節卡片（`mapInsets`）。細節卡片的「鋪設軌道」按鈕照舊（教學與 UI 測試用它）；膠囊的無障礙名稱是「建造這一段，$…」「蓋在這裡，$…」，不以「Build Track」開頭，教學 UI 測試用這個前綴只找到卡片上那一顆。識別字 `map.build.confirm`、`map.build.cancel`。
3. **進階選項收起**：構造、新節點高度、平順曲線、緩和坡度、吸附軌道收進「進階選項」，預設收起（每次選路網工具都收起，是畫面狀態）；收起時一行字說目前的設定（構造，以及關掉的開關）。「清除」與交叉渡線（只在選到兩條軌道時出現）照舊在外面。

**參考**：參考庫 `Simulator/` 手機版的進階選項在預設關閉的抽屜（`.mobile-sheet-handle`，控制分頁）；`Ci/` 的費用膠囊（`.metro-cost-preview-pill`）已經是決策 102 的 `MapConstructionHUD`。作者的 SimCity BuildIt 截圖在拉好的路徑與擺好的建築旁放 ✗ 與 ✓、起終點插旗；OpenTTD Android（`build_confirmation_gui.cpp`，GPL-2.0）與 Mindustry（`MobileInput.java`，GPL-3.0）在拖曳結束處確認，只看做法。程式是本專案自己寫的。

### 108. 車站選址：涵蓋圈、800 公尺內的居民與工作、顯示人口

2026-10-09，UI/UX 改版第二輪的 UX-5d：鐵道經營最好玩的決定之一是「車站蓋在哪裡」，但以前要蓋好車站、打開車站面板才看得到它服務多少人。只改 App 與 GamePresentation：GameCore、存檔、golden、replay 都不變。

1. **選了月台位置就看得到它服務誰**：路網工具的月台模式在軌道上點了位置時（`GameSession.platformSitePlanPoint`），`platformSiteCatchment` 給出那裡 800 公尺內的居民與工作：GameCore 車站需求用的同一份土地（`Land.totals(within: Land.catchmentRadius, of:)`），所以空白地圖與實景地圖都一樣，數字就是車站蓋好後實際的客源。實景地圖車站面板的「涵蓋人口」用的是人口格網（`stationCatchmentPopulation`），兩者來源不同，這裡用會影響運量的那一份。
2. **地圖上**：那個位置畫出 800 公尺的虛線涵蓋圈，旁邊的膠囊（決策 107 的 `MapBuildConfirm`）上方一行「800 公尺內：居民 N · 工作 M」（`catchmentText`），下面「✗ 取消／✓ 在這裡加月台」（`addNetworkPlatform`，和細節卡片的「加月台」相同）。無障礙名稱不和卡片的按鈕同名。
3. **顯示人口分布**：月台模式的選項多一顆「顯示人口分布」，把地圖的人口與交通圖層切到人口（`mapPopTravelMode` 偏好，和圖層選單是同一個）；圖層的圖例可以關掉它。

**參考**：參考庫沒有可以移植的選址提示（`Ci/` 的車站服務範圍是建好之後畫的 800 m 圈，決策 84 的 `showsCatchmentRings`）。作者的 SimCity BuildIt 截圖在擺放中的建築上顯示它帶來的效果（「+0 👥」），TheoTown 擺放時把地面染成好或不好；只看做法。程式是本專案自己寫的。

### 109. 地圖上的狀態泡泡：擁擠、滿站、沒有列車的路線

2026-10-09，UI/UX 改版第二輪的 UX-5c：要知道哪裡出了問題，以前得一座座點車站、打開面板看；玩家看著地圖就該知道哪裡要處理。只改 App 與 GamePresentation：GameCore、存檔、golden、replay 都不變。

1. **哪些事會冒泡**（`GameWorld.mapAlerts()`，每次畫地圖時由世界算出，不存、不必關掉，原因沒了泡泡就消失）：
   - 候車人數到車站容量（`StationPassengers.capacity`，4,000）的一半以上：「擁擠 · N 人」；到容量：「滿了」（之後來的乘客會離開）。
   - 路線本身與它的服務模式都沒有任何列車：在路線第一站上方「〇〇線：沒有列車」。
   順序：車站依 ID，再來路線依 ID；同一站有兩個時疊起來。
2. **點泡泡就前往**（`GameSession.respond(to:)`，不改世界）：擁擠或滿站選取那座車站（細節卡片顯示它，決策 106）；沒有列車的路線選取那條路線並打開路線面板，那裡可以一步配車（決策 101）。
3. **只在檢視時出現**：選取工具時才畫，建造工具時不畫，泡泡不會擋住正在蓋的東西；泡泡避開狀態膠囊、工具列與細節卡片（`mapInsets`），站在畫面外的不畫。

**參考**：參考庫 `Ci/` 把擁擠與滿車做成訊息，有 10 分鐘的冷卻（`emitCrowdAndFullTrainNotices`）、通知盒只留最新一則（`renderNotifBox`）；這裡改成畫在地圖上、由狀態算出，不另外記冷卻。作者的 SimCity BuildIt 截圖把要處理的事做成建物上方的小泡泡；Unciv（MPL-2.0）把通知收到畫面邊緣，只看做法。程式是本專案自己寫的。

### 110. 路線示意條、主要按鈕用主題樣式

2026-10-09，UI/UX 改版第二輪的 UX-5e：路線面板只用文字列出站名（「甲 → 乙 → 丙」），看不出一條線的樣子；主要的動作（「建立路線」「購買 N 列並開始營運」）是一般的表單按鈕，和次要按鈕看起來一樣（之前的主題檢查列出的缺口）。只改 App：GamePresentation、GameCore、存檔、golden、replay 都不變。

1. **路線示意條**（`RouteStrip`）：站點橫排在一條線上，像月台上方的路線圖：每站一個圓點、兩端較大，站名在下（最多兩行、太長縮小），太長時左右捲動。新路線的草稿用主題色，選取的路線用它自己的顏色（`Palette.lineColor`）；文字的站名清單照舊在下方（UI 測試與無障礙讀它）。
2. **主要按鈕**：「建立路線」與「購買 N 列並開始營運」改用 `ThemeProminentButtonStyle`，滿寬、44 點高，不能按時用主題的灰底。識別字不變。

**參考**：參考庫 `Ci/` 的路線資訊面板把一條線畫成直的站點條（`renderLineInfoPanel`、`#line-info-pipeline-bar`），上面有移動的列車點；這裡先畫橫的站點條，列車點之後再加。程式是本專案自己寫的。

### 111. 水岸建物與臨水地價

2026-10-09，作者看了 SimCity BuildIt 的海岸截圖（碼頭、遊艇港、海上建物；景觀的池塘與湖泊；跨河的橋），問要不要讓玩家擺水上建築與景觀，順序交給 Claude Code 判斷。判斷：水是障礙（決策 105），岸邊是機會；先做水岸建物與臨水地價（改動小、立刻讓海邊和河岸有意義），之後依序是玩家挖湖與填海造陸、軌道過水要用橋、坡度與高度。號碼依工作登記 #231：存檔 25、golden schema 45（106–110 是 UX-5a 到 UX-5e 的登記）。

參考檢查（`a91453/railway-reference-private`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「水岸建物與臨水地價（決策 111）」）：參考庫沒有水岸建物、也沒有地價（決策 76 已查過），規則與數值是本專案的（gap → 原生）。作者的 SimCity BuildIt 截圖只參考玩法（商業遊戲，不取數值與素材）。外部專案（只取想法）：OpenTTD（GPL-2.0）的碼頭要蓋在海岸格；Cities: Skylines（商業遊戲）的港口沿著岸線放。

1. **兩種岸邊的建物**（GameCore，`PlacedBuildingKind`）：**漁人碼頭**（`wharf`，24 m、商業、2 層，像淡水漁人碼頭，容量同商店 6／27）與**遊艇港**（`marina`，32 m、觀光、2 層，5／56）。`standsOnShore`：正方形碰到的格要**同時有水和陸地**，否則拒絕（`GameError.needsShore`）；整個在陸地或整個在海上都不行。其餘照 P0-C（決策 94、95）：付建造費與占地 × 地價（中心那格的地價）、住人、帶運量、收租；陸地那一側的城市建物照樣收購。小住宅、商店、辦公樓照舊碰到水就拒絕（`onWater`）。
2. **臨水地價**（決策 76 的公式多一項 W）：格的中點離任何一格水的中點不到 160 m（10,240 單位，兩格半），地價加 600 美分／m²（`LandValueRules.waterPremium`、`waterReach`，`LandValue.waterPremium`），水格本身也算（所以蓋在岸邊、中心落在水上的建物也有）。`Terrain.isNearWater` 只看上下兩列各一段，所以全圖的地價圖層不會因此變慢。和公園溢價一樣只是查詢；**沒有水的世界地價不變**，所以既有 golden 與存檔不變。效果：劃了分區的海邊、河岸格先被開發（決策 98 依地價選格），岸邊的公司建物占地費與租金都高一點。實景地圖的人口匯入不受影響。
3. **App**：建築工具的種類多兩個按鈕（圖示 `fish.fill`、`sailboat.fill`，名稱「漁人碼頭」「遊艇港」），地圖上用棕色與海藍色畫出；預覽在不是岸邊的地方寫「漁人碼頭與遊艇港要蓋在岸邊，一部分在水上。」；城市圖層點格的提示框多一行「臨水 +」加上溢價（和「鄰近公園」同一種寫法）。
4. **存檔**：版本 25。格式不變，但只讀到 24 的 build 不認得 `"wharf"`、`"marina"`，會說存檔損壞，所以升版。新的 `SaveFixtures/v25-shore-buildings.json`（版本 24 的世界加一座遊艇港；小住宅的占地費因臨水變成 409,600）。`v24-water.json` 不變：它的小住宅照當時付的 256,000 讀進來，測試改成照存檔本身檢查（同版本 21 的做法），不再和現在的建構函式比。
5. **golden**：schema 45，結果 `needsShore`、`landValue` 選填的 `waterPremium`（不是 0 時才寫）；`placeBuilding` 的 `kind` 多了 `wharf`、`marina`；新的 `waterfront.json`（全部手算）。既有 golden、存檔與 replay 的預期值都沒有改變。

**限制與之後**：
- 臨水地價只看距離，不分海、河、湖，也不看景觀；之後可以讓海景、湖景不同。
- 水岸建物只有兩種、都是公司的；城市自己不會長出水岸建物。
- 之後（依序）：玩家挖湖與填海造陸（編輯水格，空白地圖也就有水）、軌道過水要用橋或隧道與水上車站、坡度與高度（山、隧道、整地費）、空白地圖由種子產生的地形。

### 112. 車站的路線標籤、從車站開新路線

2026-10-09，UI/UX 改版第二輪的 UX-5f：在地圖上選了車站，細節卡只有站名板與一行文字，看不出哪些路線停這站，要開路線也得先打開路線面板、再按「在地圖上選」。改成選取的車站就是路線的入口。GameCore、存檔、golden、replay 都不變。

1. **路線標籤**（`StationLineChips`）：選取工具下選了車站，細節卡的站名板下排出停靠這站的路線（`GameWorld.lines(callingAt:)`，依 ID），每條一個路線色外框的標籤（色點加路線名，32 點高）；點了選取那條路線（`selectLine`）並打開路線面板。路線多時左右捲動。
2. **從這站開新路線**：標籤列最後一個按鈕（識別字 `station.newLine`）。`GameSession.startLineFromSelectedStation()` 丟掉進行中的草稿，以選取的車站為第一站，開始在地圖上點選（決策 100 的 `isPickingLineStops`），提示玩家點終點站；沒有選取車站時照 `addSelectedStationToLineDraft()` 回報失敗。App 同時打開路線面板。不改世界。

**參考**：參考庫的網站在停靠站旁用有外框的轉乘標籤（`Railway/site_archive_clean/index.html` 的 `.xfer-tag`：路線色的 1.5 px 外框、圓角、粗體小字），這裡照它的樣子做成可點的標籤。從車站開路線是本專案自己的設計（SimCity BuildIt 與 TheoTown 點建物後的資訊框裡有動作按鈕），程式是本專案自己寫的。

### 113. 路線示意條上的列車

2026-10-09，UI/UX 改版第二輪的 UX-5g：路線面板的示意條（決策 110）只有站，看不到車在哪裡、班距排得勻不勻；要知道得回到地圖上找。改成在示意條上畫出這條路線正在跑的列車。GameCore、存檔、golden、replay 都不變。

1. **列車的位置**（`GameWorld.lineTrainDots(_:)`，GamePresentation）：路線（含服務模式）每台正在跑一趟的列車一個點，依列車 ID。停站時在那一站的位置（`stops` 的索引）；在兩站之間時，從離開的那一站往要去的那一站，走到它這一段行駛（`ServiceRun`）經過的時間比例。往路線最後一站的方向是去程，反之是回程。等下一趟、還沒有一趟的列車沒有點。環線從最後一站開回第一站的那一段示意條上沒有畫，列車顯示在比較近的那一端。每次從世界讀出，不存。
2. **示意條**（`RouteStrip`）：選取的路線的示意條上，每台列車一個路線色的小圓（電車圖示），去程在線的上方、回程在下方，位置變化時以 0.5 秒線性移動。新路線的草稿沒有列車。

**參考**：參考庫 `Ci/` 的路線資訊面板在站點條上畫列車點（`updateLineInfoTrainDots`）：依路線的 `_stationProgress` 把列車的進度換成兩站之間的位置；這裡用列車的時刻表執行（`TimetableExecution`）與行駛找出它在哪兩站之間，用行駛的時間比例代替進度。程式是本專案自己寫的。

### 114. 「建設」入口：底部只留一顆建設鈕，工具改在地圖邊緣直排

2026-10-09，UI/UX 改版第二輪的 UX-6a（研究紀錄 `docs/research/UX_REDESIGN_STUDY.md` 第 8 節的前兩項；決策 104、106 的「沒有做的」）。底部工具列一排是「選取、路網、列車、建築」四顆加路線、資料、復原與細節鈕，手機橫拿時佔掉大半個底邊；而「選取」只是「不用工具」。只改 App 與 UI 測試：GamePresentation、GameCore、存檔、golden、replay 都不變。

1. **底部的四顆工具換成一顆「建設」**（`BuildEntry`，錘子圖示，識別字 `dock.build`，無障礙名稱「Construction／建設」）。沒有工具時按它，選路網工具（最常用）並打開工具列；建造中再按一次，回到選取（同決策 104 的「再點一下回到檢視」；教學進行中照舊不這樣做）。平常在地圖上點就是選取，不需要「選取」按鈕。
2. **建造中，工具在地圖左側（leading）直排**（`BuildToolRail`，寬 72 點，在狀態膠囊下、底部工具列上，放不下時捲動）：路網、列車、建築，分隔線下是「完成」（✕，回到選取）。按目前的工具不再回到選取：離開用「完成」或「建設」，避免誤觸。按鈕的識別字、無障礙名稱與教學的聚光目標照舊（`tool.network`、`tool.train`、`tool.building`）；「完成」接下 `tool.select`，無障礙名稱改成「Done building／完成建設」。
3. **只在建造時出現**（有工具，或教學進行中：教學的步驟會指著工具，包括選取）。出現時 `mapInsets` 的 leading 讓出它的寬度：交通圖例、狀態訊息、圖層與底圖按鈕、提示框、確認膠囊（決策 107）與狀態泡泡（決策 109）都往右讓。研究紀錄原本想放右側（TheoTown、SimCity BuildIt 都在右），但我們右側是細節卡片（工具的選項與動作鈕），所以放左側，和底部的「建設」上下相連。
4. **UI 測試**：要用工具的測試先按 `dock.build`；新遊戲一開始就是選取，不再按 `tool.select`；工具列的測試依「建設 → 三個工具 → 完成」的順序按；教學的鋪軌測試在地圖上找空位時，也避開左側的工具列；教學結束後按「完成」，等工具列消失。

**沒有做的**：研究紀錄的側邊工具列還有鋪設／月台／拆除、橋與隧道、上／下、吸附與「↶ n」（現在仍在細節卡片的路網工具裡）；「建設」展開分類選單（現在直接進路網）；點一下看、長按改。

**參考**：參考庫 `Ci/` 的底部列（`#bottombar`）只有一排圓形圖示，多的收進「更多」（`#nav-btn-more`），這裡照它讓底部只留少數入口；參考庫沒有「建造模式換掉工具列」的介面（MapBuilder 的工具在網頁的固定側欄）。外部遊戲只看做法：TheoTown 的主畫面只有一把錘子，進入建造後右側直排工具與「✕ 離開」；SimCity BuildIt 建造模式時平常的按鈕消失、側邊直排三顆（作者的實機截圖）。程式是本專案自己寫的。

### 115. 地形：陡坡（城市不能開發的山坡地）

2026-10-09，作者問要不要先做山、再用地形坡度限制。判斷（作者同意）：山比挖湖、填海重要，台灣的鐵道難處在山線；但坡度要分兩層。這一步是第一層：只限制**城市**（地形層多一份陡坡格），鐵路照舊不擋；第二層是軌道與地形的高度（隧道、高架、挖填方的造價、過水用橋），會動到既有的軌道規則與 golden，先寫設計說明再做。作者另外要求避開 UI 改版 #256–#260 會改的檔案：這一步不動 `RailwayGameApp/Views/`、`GameSession`、`BuildingSession`、`NetworkDrag`、`project.yml`／xcodeproj（陡坡併入既有的 `taiwan_water.json`，不新增資源檔），也不畫高度圖層。號碼依工作登記 #231：存檔 26、golden schema 46。

參考檢查（`a91453/railway-reference-private`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「地形：陡坡（決策 115）」）：`Simulator/` 有稀疏的地形格（`cells[{col,row,layers}]`、`cellMm`、B-spline 取樣）與地形筆刷，`Railway/site_archive_clean/rail-3d/` 從 Mapterhorn 的 DEM 圖磚讀高度（`terrain-source.js`），`railway_game_reference_clean` 只列了 OpenTTD 的 `heightmap.cpp`、`terraform_cmd.cpp` 路徑：都是軌道與地形那一層（下一步）用得到的；參考沒有「陡坡不能開發」的規則或資料（gap → 原生）。外部（只取想法）：SimCity 4 與 Cities: Skylines 的建物不放在太陡的地形上（商業遊戲）。

1. **門檻**：建築技術規則建築設計施工編第 262 條，山坡地依坵塊圖的平均坡度區劃，**超過 30% 的部分不得開發建築**。遊戲照這條線：坡度超過 30% 的乾格是陡坡。
2. **資料**（`tools/real-world-population/build_slope_grid.py`，併入 `taiwan_water.json` 的 `"steep"`，檔案 530 KB → 2.1 MB）：
   - 來源：**Copernicus DEM GLO-30**（1″，約 30 m；馬祖那一塊只有 GLO-90，3″）。內政部的 20 m 數值地形模型（政府資料開放授權）是首選，但下載站（tgos.tw）在這個環境回 403，而且只有本島與澎湖；Copernicus 涵蓋本島、澎湖、金門、馬祖，授權允許免費使用與再散布，要標示「Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA」（資料來源畫面的「地圖」多一項）。
   - 作法：水域檔的 1.875″ 格（約 58 × 53 m）每格取中點的高度；它是**地表**模型（含建物與樹），所以先做 3 × 3 的中位數（約 170 m）去掉高樓（台北 101 是一格裡 100 m 以上的落差，山坡不是）；坡度取東西、南北兩個方向跨兩格的中央差分較陡的一個；超過 30% 而且周圍 3 × 3 至少 5 格也是，才算陡坡（去掉梯田、路塹的零星格，也補上山坡中零星的平格）。水不算陡坡。
   - 結果：陸地 35,583 km² 中 17,059 km² 是陡坡（48%），326,886 段。抽查：台北市中心 0.1%、台中市中心 0%、高雄市中心 0%、基隆港邊 4%、九份 55%、陽明山 41%、玉山 95%、馬公與金門 0%。
3. **規則**（GameCore，`Terrain.steep`，段和水的一樣，不能在水上）：
   - 城市不在陡坡上擴張（`spread`），陡坡上的建物不升級（`raiseBuildings`）；已有的格照常住人（九份的山城本來就在坡上）。
   - 玩家建物碰到陡坡就拒絕：`GameError.onSteepSlope(row:column:)`，指名第一格（檢查在水與岸邊之後），漁人碼頭與遊艇港也一樣。
   - 分區跳過陡坡格；矩形裡沒有能劃的格時拒絕：第一格是水就 `onWater`，否則 `onSteepSlope`。
   - `foundTowns` 略過陡坡（實景地圖沒有人時的城鎮，在山裡）。
   - 鐵路與車站照舊能蓋在陡坡上（軌道本身的坡度限制 `trackTooSteep` 不變）。
   - **土地可以在陡坡上**（和水不同）：`setLand`、`LandImport` 都不受影響，人口數字不變。
4. **指令**：`setSteep(_:)` 整個替換陡坡（只給土地完整的世界；格在世界外、重複或在水上是 `invalidTerrain`）；`setWater` 也拒絕陡坡上的格；`expandLand(_:cells:water:steep:)` 讓全台灣地圖的區塊帶著自己的陡坡讀入，讀入順序不影響結果。實景新遊戲先 `setWater`、再 `setSteep`、再 `setLand`。
5. **數字**（16 km 地圖；`WaterGridTests`）：

   | 地圖 | 陡坡格 | 陡坡上的土地格（照舊有人） |
   | --- | --: | --: |
   | 台北車站 | 2,959 | 2,784（39,379 人） |
   | 基隆 | 7,628 | 3,295（18,177 人） |
   | 高雄 | 786 | 785 |
   | 澎湖馬公 | 20 | 6 |
   | 瑞芳 | 11,793 | 4,192 |
   | 花蓮 | 13,985 | 1,604 |
   | 阿里山 | 51,912（全圖 83%） | 4,079 |

   存檔多 0–16%（台北 928 → 956 KB、基隆 446 → 518 KB、馬公幾乎不變）。App 讀檔多約 0.3 s（Linux debug，在背景執行緒）。
6. **存檔**：版本 26，`"terrain"` 多一個 `"steep"`（沒有時不寫）；只讀到 25 的 build 會丟掉陡坡（城市又會往山上長），所以升版。新的 `SaveFixtures/v26-steep-slopes.json`。
7. **golden**：schema 46，新指令 `setSteep`（`runs`）、觀察 `steep`、結果 `onSteepSlope`（`row`、`column`），最終狀態選填的 `steep`（格數）；新的 `steep-slopes.json`（全部手算）。既有 golden、存檔與 replay 的預期值都沒有改變（空白地圖沒有陡坡）。

**限制與之後**：
- 只有「是不是陡坡」，沒有高度；高度怎麼存（每格、或像 `Simulator/` 的稀疏格加 B-spline）要看軌道規則怎麼用它，放在下一步的設計說明。
- 不畫高度或陡坡圖層、點格的提示框不寫陡坡（避開 UI 改版的檔案）；玩家看到的是建造預覽的錯誤訊息。UI 改版合併後再加。
- Copernicus 是地表模型：中位數去掉了大部分建物與樹，但密集高樓區或森林邊緣可能還有零星誤判；門檻 30% 與 3 × 3 多數決之後再依實機調整。
- 空白地圖沒有山；由種子產生起伏放在軌道與地形那一步之後。

### 116. 小地圖

2026-10-09，UI/UX 改版第二輪的 UX-6b（研究紀錄第 8 節的「小地圖」）。大地圖（全島、1024 × 1024 的示範地圖）放大時看不出自己在哪裡，要回到別處得一直縮小再放大。GameCore、存檔、golden、replay 都不變。

1. **畫什麼**（GamePresentation `MiniMap`）：整張地圖（`WorldRegion(bounds:)`）的地面；每段軌道兩端之間的直線（那個大小看不出彎道）；每條路線依站序連起來的直線（路線色，環狀線回到第一站，決策 49）；車站的點。只讀世界，和路線圖（`LineMap`）同一個背景工作在軌道、路線或轉乘改變時算一次（`LineMapKey`），不是每一格都算。
2. **怎麼放**（`MiniMapProjection`）：整張地圖等比例放進長邊 120 點的框，短邊至少 44 點（台灣這樣細長的地圖也點得到），多出的邊置中。畫面目前看到的範圍（`PlanCamera.visibleRegion`）畫成主題色的框，超出地圖的部分切掉。
3. **點或拖就移過去**：位置換回世界座標（點在地圖外就取最近的邊），地圖的鏡頭移到那裡（`PlanCamera.centered(atX:y:)`，照舊受地圖邊緣限制）；正在跟著列車時先停止跟隨；算一次「移動地圖」（教學的地圖步驟，Stage E1）。
4. **在哪裡**（`MiniMapView`）：地圖右下、縮放鈕上方。顯示人口或旅次等圖層的圖例時讓給圖例（手機橫拿時高度不夠兩個都放）；細節卡片或地圖旁的面板打開時也收起：縮放鈕在它們旁邊讓位，小地圖跟著過去會落在手機地圖的正中間，蓋住手指要點的地方（`main` 的 UI 測試在地圖中央點選與捏合都點到了小地圖，#272）。右上角的 ⌄ 收成一顆地圖按鈕，再按打開；開或收記在 `UserDefaults`（`map.minimap.open`），預設打開。小地圖本身對 VoiceOver 隱藏（和大地圖重複，位置點選也不適合朗讀），收合與打開的按鈕有名字。
5. **只在內容改變時重畫**：畫布是 `Equatable`，鏡頭移動只重畫上面的框。

**沒有做的**：地形與水域（海岸線、河湖，決策 105）還沒畫進小地圖；列車的位置；在小地圖上縮放。

**參考**：參考庫只有 `Railway/taipei_gta_reference/` 有小地圖（`game-vXklz4A8.js` 的 `sr`：右上角 200 px 的畫布，跟著玩家轉，位置或縮放沒變就不重畫）；這裡的地圖是固定的整張地圖，只借用「沒變就不重畫」。網站與 `Ci/` 用網頁地圖的縮小代替小地圖。外部只看做法：TheoTown 的狀態列有小地圖、OpenTTD（GPL-2.0）有「世界地圖」視窗，都點了就移過去。程式是本專案自己寫的。

### 117. 建造完成與收到錢：一下動態與音效

2026-10-09，UI/UX 改版第二輪的 UX-6c（研究紀錄第 8 節的「遊戲感」：開關與確認的音效、獎勵的出現）。蓋好東西與收到錢只有一行文字訊息，沒有「做到了」的感覺。GameCore、存檔、golden、replay 都不變。

1. **蓋好了**：放好建物（`placeBuilding(at:)`，含決策 103 的點一下就蓋）、加好月台或新車站（`addNetworkPlatform()`）成功時，`GameSession.buildPulse` 記下位置與序號（`BuildPulse`），並播新的「完成」音效（`SoundCue.built`，`build-done.wav`）。地圖在那裡畫一圈往外擴散、淡去的綠圈，中間的 ✓ 彈出後消失，約 0.9 秒（`BuildPulseMark`）。鋪軌照舊是決策 79 的鐵軌接縫聲。
2. **收到錢**：每一步（`advance(realElapsed:)`）前記下最新的帳簿列，之後新寫入的列裡「車資收入」與「建物租金」（`CompanyAccounts.incomeItems`）加起來大於零，就記下金額與序號（`IncomePulse`，`noteIncome(since:)`），並播新的「錢」音效（`SoundCue.income`，`coins.wav`）。車資每小時結算一次（決策 36），租金每日一次（決策 94），所以 600× 時約 6 秒一次。狀態膠囊的現金下方浮出「+$ 金額」，往下飄並淡去，約 1.6 秒（`IncomeFloat`）。帳簿只留最新的列：之前那列已經不在時，留著的列都算新的。
3. **音效的間隔**：「完成」至少 0.15 秒、「錢」至少 3 秒一次（高速時一小時一兩秒就結算，一聲代表幾次）；照舊受遊戲選單的音效開關控制，UI 測試不播。
4. **減少動態效果**：開著時不畫擴散的圈、✓ 不縮放、金額不移動，只淡入淡出。動畫只對畫面出現後才來的事件播放：裝置轉向重建畫面時，不會再播一次舊的。
5. **音效素材**：`tools/audio/make_game_audio.py` 用和決策 79 同一套合成產生（正弦波與固定種子的雜訊，本專案自己的素材）：`build-done.wav` 是輕輕的「咚」加上往上的兩個撥弦音（G、高八度的 C），`coins.wav` 是兩個相隔五度的高音鈴。重新產生時既有的四個檔案位元組不變。

**沒有做的**：升級、配車、開新路線的回饋；年度結算或達成目標的大獎勵畫面；觸覺回饋（haptics）。

**參考**：參考庫 `Ci/` 的按鈕帶 `data-metro-sfx`，有 12 套音效主題，並照顧「減少動態效果」；`Railway/taipei_gta_reference/` 的 `notify()` 伴隨音效、超出再彈回的進場動畫（研究紀錄 3.2、3.5 節）。這裡沒有拿它們的音檔（音效由本專案合成）。外部遊戲只看做法：SimCity BuildIt 蓋好時的彈跳與收錢時金額從建物上浮起、TheoTown 的建造音效。程式是本專案自己寫的。

### 118. 站長：一句話說現在最該做的事

2026-10-09，UI/UX 改版第二輪的 UX-6d（研究紀錄第 8 節的「站長角色」）。新玩家不知道下一步做什麼，出了問題（車站擠滿、路線沒有車、現金是負的）也只在地圖的泡泡或經營面板裡。GameCore、存檔、golden、replay 都不變。

1. **說什麼**（GamePresentation `StationMasterAdvice`，每次從世界算，不存）：先說煩惱，再說建第一條路線的下一步，只說一件：經營模式現金是負的 → 有車站滿了（決策 109 的 `mapAlerts`）→ 有路線沒有車 → 有車站擠了（各取 ID 最小的）→ 還沒有軌道 → 還沒有車站 → 只有一座車站 → 還沒有路線。都沒有就不說話。中英兩種說法（`text(in:)`），煩惱（`isWorry`）用警告色。
2. **在哪裡**（`StationMasterCorner`）：底部工具列右邊，一張 44 點的臉；有新的建議時自己冒出對話泡泡，7 秒後收起；同一句不再自己冒出。點臉再說一次，點泡泡收起。有建議但泡泡收起時，臉上有一個小點（煩惱是警告色）。泡泡最寬 320 點，放得下一行就一行，不會蓋到細節卡片或地圖旁的面板；地方不夠（少於 140 點）就只有臉。VoiceOver 讀「站長」與建議；泡泡本身隱藏（不重複朗讀）。
3. **長什麼樣**（`StationMasterAvatar`）：用 SwiftUI 圖形畫的圓臉、眼睛、微笑與帽子，不需要美術素材；帽子與帽徽的顏色是地區外觀的（`RegionStyle.stationMasterCap`、`stationMasterBadge`，台灣是台鐵的深藍帽與金色帽徽，近似值，要實機確認）。換國家只換顏色，之後有美術時換掉這個 View。（決策 122 起換成黃山雀的圖，帽子的顏色拿掉。）
4. **教學也是站長說的**：教學卡片的「第 n 步」前面是同一張臉（28 點）。教學進行時角落的站長不出現（卡片已經在說話）。

**沒有做的**：事件的即時報告（年度結算、達成目標、第一班車到站）；多位顧問（SimCity BuildIt 每類一位）；美術素材。

**參考**：參考庫 `Railway/taipei_gta_reference/` 有一行持續顯示的目標句（`.hud-obj`）與只在需要時出現的提示（`.hud-prompts`，研究紀錄 3.5 節）；這裡照它一次只說一件事、有需要才說。外部遊戲只看做法：SimCity BuildIt 用顧問的頭像加一句話通知，TheoTown 的教學是一個小人加對話泡泡、不蓋地圖（研究紀錄 4.1、4.2 節）。程式是本專案自己寫的，臉是本專案畫的。


### 119. 點一下看、長按改

2026-10-09，UI/UX 改版第二輪的 UX-6e（研究紀錄第 8 節的「點擊看、長按改」）。選取時點一下車站，右側的細節卡整張滑出來蓋住地圖的三分之一，只為了看站名；要改車站（改名、月台、拆除）又得先找到細節卡裡的入口。GameCore、存檔、golden、replay 都不變。

1. **點一下是看**：選取（沒有工具）時點到車站，細節卡不再自己打開（`ControlDetails.isOpen`：選取工具下選到車站時預設收起）；改在車站**下方**浮出小標籤（`MapStationTagView`，資料是 GamePresentation 的 `StationTag`）：停靠路線的顏色條（最多 4 條）、站名、候車人數（沒有人就不寫）與 ›。放在下方，因為決策 109 的狀態泡泡在車站上方；下方放不下就放上方，並避開地圖四邊的控制項。點選的若不是車站（列車、空地），照舊打開細節卡。
2. **點標籤才打開細節卡**（`GameScreenState.detailsRequests` 加一，畫面把細節卡設為打開）。細節卡、地圖旁的面板打開時，或教學進行中（細節卡一直開著），標籤不出現。工具列的「顯示控制項」照舊能打開細節卡。
3. **長按是改**：選取時在車站上按住 0.45 秒（`UILongPressGestureRecognizer`），選取那座車站（`GameSession.holdMap(at:reach:)`，找車站的方式和點一下相同）並打開車站面板（地圖旁滑出，決策 106），同時輕震一下。按住的地方沒有車站、或正在用工具、或路線面板開著時，長按不成立，那一下照舊是點擊（多久都算）。
4. **長按一定有按鈕可以代替**：標籤右邊的鉛筆（`map.stationTag.edit`）同樣打開車站面板，VoiceOver 與切換控制不必長按。標籤本身的名字是站名與候車人數（`map.stationTag`）。

**沒有做的**：列車的標籤（車次、下一站、誤點；列車在動，標籤要跟著）；長按時畫出腹地圈；把蓋好的東西拿起來移動（需要 GameCore 的新指令）。

**參考**：參考庫 `MapBuilder/` 點車站旁邊跳出捷徑（`Shortcut`，`renderButtons()`，研究紀錄 3.4 節），`Simulator/` 選取物件時浮出一條動作列（`.canvas-selection-actions`：名稱與刪除等，3.3 節）；這裡照它們把動作放在物件旁而不是側欄。外部遊戲只看做法：SimCity BuildIt 點一下只在建物頭上浮出名字與加成的小標籤、長按把建物拿起來（4.2 節）；TheoTown 點建物是畫面中央的對話框、地圖變模糊（不要學）。程式是本專案自己寫的。

### 120. 地圖畫到螢幕邊緣

2026-10-09，作者的實機截圖（橫拿的 iPhone）：地圖左右兩側與底部各留一條白邊，像沒有瀏海的 iPhone 7／8。決策 106 寫的是地圖滿版，但整個畫面一直排在 iOS 的安全區域（safe area）裡：左右讓出瀏海與動態島，底部讓出 Home 指示條，地圖也跟著停在裡面，外面露出視窗的底色。Apple 的「地圖」App 是地圖畫到邊緣、只有按鈕在安全區域內。GameCore、存檔、golden、replay 都不變。

1. **地圖到邊緣，控制項在安全區域內**（`ContentView.gameLayout`）：地圖改放在控制項的背景，自己忽略安全區域（`.ignoresSafeArea(.container)`，鍵盤照舊）；狀態膠囊、底部工具列、建設工具列、細節卡片與地圖旁的面板留在原處。安全區域經 `EnvironmentValues.mapSafeArea` 交給地圖。
2. **地圖上的東西避開螢幕邊緣**（`MapView`）：`mapInsets` 的意思不變（畫面的控制項蓋住多少），地圖上浮著的東西改避開兩者相加（`clear`）：上方的狀態列與鋪軌資訊、圖層鈕、縮放鈕與小地圖、決策 107 的確認膠囊、決策 109 的泡泡、決策 119 的車站標籤、人口與城市的提示框、教學的地圖範圍。
3. **蘋果的標誌與「法律資訊」留在安全區域內**（Apple Developer Program License Agreement 附件 6 §2.1：不能遮住）：實景地圖底部的條（決策 106、E2）變成 30 點加上安全區域的底部（第 5 點起遊戲畫面畫進這條，只繞開標誌與連結），`AppleMapBackground` 的邊距加上安全區域，所以標誌與連結在 Home 指示條上方、瀏海內側；鐵道資料的來源字樣跟著邊距走。OpenStreetMap（決策 97）的來源字樣同樣內縮；MapLibre 的版權按鈕本來就靠 UIKit 的安全區域（`updateConstraintsForOrnament` 對齊 `safeAreaLayoutGuide`，6.31.0），只補上 UIKit 沒算到的部分，兩者不會重複內縮。
4. **同一段版面的兩個問題**（同一批截圖）：手機上細節卡片打開時，右下的縮放鈕跟著往左移，落到底部工具列下面看不到——往左移時也移到工具列上方。鋪一段很長的軌道、終點出了畫面時，確認膠囊被推到上緣，蓋住鋪軌資訊（長度與費用）——膠囊的上緣改在地圖上方那一欄（狀態列、鋪軌資訊或交通圖例）的下面。

5. **底部也畫到底**（同日，作者看了 #273 的實機截圖：實景地圖底部那條沒有人口格子、軌道與列車，而且加上 Home 指示條之後更明顯）：遊戲的地圖畫面（底圖格子、人口與城市圖層、軌道、列車、決策 107 的旗子與涵蓋圈、決策 117 的完成動畫、土地使用圖層的淡化）不再停在一整條之上，而是畫到螢幕最底，只在標誌、法律連結與資料來源字樣的框（MapLibre 是版權按鈕與字樣）外加 4 點挖空（`AttributionCutout`，`Path.subtracting`）。那幾個框由地圖視圖每次排版後回報（`onAttributionFrames`）：蘋果的標誌與法律連結 MapKit 沒有公開位置，所以找底部邊距那一帶的小視圖（往下找三層），找不到時用左下、右下兩個預設框；MapLibre 的按鈕與兩邊的來源字樣位置是知道的。挖空的框點下去不是地圖的手勢（`MapGestureView.point(inside:with:)`），所以法律連結與版權按鈕照舊點得到。地圖上的按鈕（圖層、縮放、小地圖）與提示框照舊停在 30 點的帶子與 Home 指示條之上。

**沒有驗證的**：Linux 不能建置 App；版面要看 CI 的模擬器與實機。第 5 點找蘋果標誌與法律連結的方式要在實機上確認挖空的位置對得上。

**參考**：參考庫沒有 iOS 安全區域的對應（網頁版鋪滿瀏覽器視窗）。外部只看做法：Apple「地圖」（作者的截圖）地圖到邊緣、按鈕在安全區域內；MapLibre Native（BSD 2-Clause，已是依賴）讀它的原始碼確認版權按鈕的位置，沒有複製程式。程式是本專案自己寫的。

### 121. 地圖上的圖示改用 App 圖示的畫風

2026-10-09，作者問遊戲該像《A 列車》還是 SimCity BuildIt，Claude Code 建議玩法照 A 列車的深度、外觀與操作照 BuildIt，作者同意，並要求先把地圖上的圖示換成同一個畫風。地圖鋪滿畫面之後（決策 106、120），地圖上的東西就是玩家最常看的畫面，但車站、泡泡和警告用的還是 Apple 的 SF Symbols，線條細，和 App 圖示的扁平、粗線、圓角對不起來。GameCore、存檔、golden、replay 都不變。

1. **自己畫的圖示**：`Assets.xcassets` 的 `MapGlyph*` imageset，每個是 24 × 24 的 SVG，只用實心形狀（挖空用 even-odd），粗到縮成幾點也看得出來，轉角是圓的。共十個：列車（`MapGlyphTrain`）、住宅、商店、辦公、漁人碼頭、遊艇港、人群、客滿的車廂、警告，和警告的實心外形（墊在警告下面）。程式用 `MapGlyph`（`Palette.swift`）取用，不寫字串。（2026-10-09 照 art-style skill 檢查整組：漁人碼頭原本只有一條魚，比其他圖示小、淡很多，墨量 21%、高 9 格，其他是 32–43%、約 18 格；改成魚躍過一道浪，墨量 36%，16 點與模糊後也看得出是水邊。擁擠與客滿照 Google 地圖的擁擠度圖示改成同一組等級，用人數表示：擁擠是兩個圓肩的人，客滿是三個（先試過三人中一人空心，但 13 點、3 倍螢幕時和客滿只差 3.5% 的像素，一眼分不出；兩個人對三個人差 32%，模糊後 38%，灰階下也分得出）；之前試過的車廂畫法（窗裡的人頭、擠出車頂、車門夾人、容量條、對齊像素格的簡化版）都比較難讀，沒有採用。）
2. **單色模板，顏色由程式給**：每個 imageset 都設 `template-rendering-intent: template`、保留向量，在哪裡畫就用那裡的顏色（Canvas 的 `shading`、SwiftUI 的 `foregroundStyle`）。一張圖同時用在淺色與深色，顏色仍只來自 `Theme` 與 `Palette`。
3. **換掉的地方**（只換地圖上的東西）：
   - 車站徽章裡的符號：`tram.fill` → 列車，照舊是 `Palette.stationSymbol`。
   - 死結的警告（`drawWaitMarks`）：先墊一個大一號、系統底色的實心外形，再畫紅色的警告，驚嘆號是挖空的，所以在任何底圖上都讀得到。
   - 狀態泡泡（決策 109）：圖示改放在泡泡顏色的圓上，圖示用 `Theme.panel`（淺色 5.5:1 以上、深色 5.5:1 以上），像 App 圖示的膠囊；擁擠是兩個人，客滿是三個人（同一組等級，照 Google 地圖的擁擠度圖示：人越多越擠），沒有列車是列車。
   - 玩家建物（決策 92、111）：方塊有 14 點以上時，中間畫它種類的圖示，大小是邊長的 62%，用固定的藏青 `Palette.buildingGlyph`（建物的顏色在深色地圖上偏淺，跟著換色的 `ink` 會看不清；十種底色上最低 3.11:1）。建築工具的種類按鈕用同一組圖示（`PlacedBuildingKind.mapGlyph`，取代 `systemImage`），跟著字的大小縮放。
   - 路線示意條（決策 113）上的列車：`tram.fill` → 列車。
4. **照舊用 SF Symbols 的**：工具列、面板、表單裡的按鈕與標示。它們是介面，和系統的樣子一致比較好讀；地圖上的列車本身仍是圓點加車頭方向的短線。

**沒有驗證的**：Linux 不能建置 App；Asset Catalog 的 SVG、Canvas 與按鈕上的樣子要看 CI 的 Xcode 建置與實機。

**參考**：參考庫 `Ci/reference_snapshot/` 的車站與路線圖示（`station-icon-residential`、`-shopping`、`-scenic`、`-waiting`，icons8 的 `get-on-bus` 等）與 `MapBuilder/reference_snapshot/assets/map/` 的車站、轉乘標記是黑白的細線圖，只取它們標示的東西（住宅、商業、等車、轉乘），圖形重畫；icons8 的素材要標示出處，重畫就不用帶進來。外部只看做法：SimCity BuildIt（作者的截圖，商業遊戲）泡泡裡的圓形圖示。圖示和程式是本專案自己畫、自己寫的。

### 122. 站長的角色：提著號誌燈的黃山雀

2026-10-09，作者從 Claude Code 畫的三批草稿（台鐵站長、Q 版站務員、火車頭、站長貓；App 圖示黃點長出臉的四種；黃山雀、石虎、提燈站長）裡選定組合：**黃山雀的身體，提著號誌燈，戴台鐵藍的領巾與站徽**。作者不要黃色圓臉配點點眼睛，因為太像別的表情符號角色，所以黃色只用在羽毛與燈上。先做 2D，3D 等 Phase 8。GameCore、存檔、golden、replay 都不變。

1. **角色**：黃山雀是台灣特有種，黑色的羽冠天生就是站長帽，冠上別著黃色站徽；黃色的身體與燈都取自 App 圖示的黃點（`#FFC86B`），燈也是 UI_THEME 裡黃色的意思「燈光／車站」。線條、配色照 App 圖示的畫風（決策 121）。
2. **圖**：`Assets.xcassets` 的 `StationMasterTaiwanNormal`、`…Happy`、`…Worried`，120 × 120 的多色 SVG（含淺綠松的底與一段軌道），保留向量；同一張圖用在淺色與深色（插圖，不跟著換色）。三種表情只差眼睛（作者看過正面、3/4、朝右之後，選回最初的側面朝左）：平常是實心的豆豆眼、開心是 ∩、擔心是用力閉起的「＜」（尖角朝嘴喙）加一滴汗，燈也變暗；都不畫白眼球（白眼球配小黑點看起來在瞪人）。另有單色模板 `StationMasterLantern`（提環、燈罩、挖空的火焰）。60 點以下（角落的 44 點、教學的 28 點）只放大頭部（放大 1.45 倍），表情才看得清楚，燈在畫面外。
3. **哪一個國家用哪個角色**：`RegionStyle.stationMasterArt` 是圖名的前半（台灣是 `StationMasterTaiwan`），加上 `StationMasterMood` 的後半（決策 106：地區的樣子只透過 `RegionStyle`）。決策 118 的 `stationMasterCap`、`stationMasterBadge` 沒有用處了，拿掉。
4. **表情**：角落的站長在有煩惱（`isWorry`）時擔心、有一般建議時平常、沒事時開心；教學卡片的站長在這一步完成時開心。每次開口（新的建議，或點它）跳一下（`keyframeAnimator`，上 8 點再彈回）；開了「減少動態效果」就不跳。
5. **教學**：「完成這一步」前的手指（`hand.tap.fill`）換成站長的燈；教學的暖黃外框加上同色的光暈，像燈照著要按的地方。
6. **改成正面的圓胖黃山雀**（2026-10-09 補）：作者指出第一版整隻偏黃，不像真的黃山雀（農業部鳥類圖鑑：臉、喉、胸腹黃；頭頂與羽冠黑；背暗灰綠；翅膀深灰黑）。作者用 Gemini 生了幾張，看過側面的幾種（只換顏色的、照真鳥羽色描的）之後，選定一張**正面、圓胖**的：圓頭頂一撮圓羽冠、黃臉與黃色身體、台鐵藍領巾配黃色站徽、用翅膀提著燈。原圖的頭是藍色，作者選了「頭換成 App 圖示的藏青 `#262C57`」的版本；翅膀用作者另一張圖（同一隻的改版）的形狀：一道波浪形的藍灰羽緣 `#6482A3` 與三個白點，顏色和頭冠一樣是藏青（作者要求），背上（翅膀與頭之間）原本露出的一小塊白拿掉；**頭上不加黃色站徽**（正面時正中間的黃點像第三隻眼睛；站長的身分由胸前的站徽表示）。作者看過後決定可以用正面圓臉，所以第 2 點「選回側面朝左」與 art-style skill 原本「不要正面的黃色圓臉配兩顆點點眼睛」由這一點取代。做法：原圖放大兩倍、壓成平塗色，每個顏色的範圍模糊後取 0.5 等高線（scikit-image，BSD，只在 scratchpad 用），一層一層疊（每層畫自己和疊在上面的顏色，不露細縫）；藍頭換成藏青後眼睛會黏在頭冠邊上，所以眼睛外圍留一圈黃色；軌道照原圖的位置自己畫（描圖時拿掉）。表情照舊只換眼睛：開心兩個 ∩、擔心「＞＜」（尖角朝嘴喙）加頭旁一滴汗，燈變暗、沒有光暈。

**沒有做的**：驚訝等其他表情（還沒有用得到的地方）；3D 版（Phase 8）；其他國家的角色；燈的光暈像呼吸一樣明暗、眨眼（要把光暈拆成另一層，由 SwiftUI 做動畫）。

**沒有驗證的**：Linux 不能建置 App；SVG、動畫與教學的光暈要看 CI 的 Xcode 建置與實機。

**做法的參考**：作者提供的兩個 skill，只取做法、沒有複製內容。`neonwatty/logo-designer-skill`（MIT）：先做幾種差異明顯的方案讓作者挑，每一版都在淺色與深色、從大到 28 點檢查認不認得出來，實心色塊多於細線。`supermemoryai/skills` 的 `svg-animations`（沒有授權，只讀）：光暈的呼吸、分層做動畫、照顧「減少動態效果」。

**參考**：參考庫 `Railway/taipei_gta_reference/source/avatars/` 有八個 3D 人物（`.glb`，寫實的貼圖），畫風不合，沒有用；其餘的參考沒有角色。外部只看做法：SimCity BuildIt 的顧問頭像（作者的截圖）、和歌山電鐵的站長貓「小玉」（只作為「動物站長」的前例，造型沒有參考）。角色與圖是本專案自己畫的。

### 123. 實機截圖的修正（TestFlight #37）

2026-10-09，作者在 iPhone 上用 TestFlight #37（含決策 106–122）拍了 22 張橫拿的截圖：空白地圖、實景示範（瑞芳一帶，OSM 底圖）、台北車站（Apple 地圖）、各圖層、車站卡片、路線面板、經營明細與開始畫面。這裡是從截圖找到的問題與修法，一點一個 commit。GameCore、存檔、golden、replay 都不變。

1. **指到不存在的按鈕的文字**：站長的第一句「先選軌道工具」改成「點「建設」，再選「路網」」（決策 114 起工具在「建設」後面，鋪軌的是「路網」）；細節卡片沒有選工具時的提示原本說「「選取」只會檢視」，改成「點「建設」再選「路網」……沒有選工具時，點地圖只是查看」（工具列已經沒有「選取」）。
2. **一個東西一個名字**：工具列的「建設」（Build）打開的工具裡，建築工具英文也叫 Build（中文「建築」），兩種工具的第一個模式又都是 Build。建築工具改叫「建物」（Buildings），路網的第一個模式英文改 Lay（中文照舊「鋪設」），建物的改 Put up（中文照舊「建造」）。
3. **底圖選單的「地圖」改成「Apple 地圖」**，和 OpenStreetMap 並列時看得出是誰的地圖。
4. **兩端都是新節點的一段**：路網卡片的「新節點 → 新節點」改成「一段新的軌道」；有一端接既有節點或軌道時照舊寫兩端。
5. **Apple 地圖不顯示興趣點**（`pointOfInterestFilter = .excludingAll`，標準與衛星含標示兩種）：台北車站一帶的店家、餐廳與停車場圖示蓋過遊戲的車站與路線；地名與路名照舊。
6. **OSM 底圖的地名讓開遊戲的站名**：和車站同名的村里名（四腳亭）印在遊戲的站名牌下面，同一個名字出現兩次。MapLibre 的 style 多一層看不見的文字（`game.stations.room`，每座車站一個、字是站名、用 style 自己的字型），放在所有文字層之上：高的圖層先排，這層可以壓在任何東西上（`text-allow-overlap`）、別人不能壓它（`text-ignore-placement` 為 false），底圖的地名就避開站名所在的地方。Apple 地圖沒有這種接口，拿掉興趣點之後地名仍可能落在車站下。
7. **不同的按鈕不同的圖示**：收起的小地圖原本和底圖選單一樣是 `map`，改成大框角落一個小框（`rectangle.inset.bottomright.filled`）；底部工具列的細節卡片鈕原本收起時是 ⓘ，和 MapLibre 的版權鈕一樣，改成不論開關都是卡片的側欄（`sidebar.trailing`，選取的樣式照舊分得出開關）。
8. **行車圖例寫出它數的是什麼**：左上的「●3」「●2 ●1」改成「● 3 可行駛」「● 1 等候」「● 死結」。
9. **縮放鈕讓開寬的卡片與面板**：手機橫拿時車站卡片、細節卡片與地圖旁的面板佔寬度的 40–50%，縮放鈕跟著移進來（決策 120 第 4 點）就站在地圖中間、蓋住剛選的車站。卡片或面板比寬度的三分之一寬、而且長到縮放鈕的位置時，縮放鈕像小地圖（決策 116）一樣讓位，捏合照舊能縮放；判斷用縮放鈕自己固定的高度（44 點加上下各兩層 12 點），不用它離開後的欄高，不會開開關關。教學會指到縮放鈕，教學進行時照舊顯示。iPad 的卡片不到三分之一，照舊在卡片旁。
10. **建設工具列放得進橫拿的手機**：狀態膠囊和底部工具列之間的高度比四顆有名字的按鈕矮，工具列捲動、最後的「完成」只露出一半。有名字的一欄放不下時只放圖示（32 點高、間距 4、沒有分隔線），名字照舊是無障礙標籤；用哪一種只看有名字那一欄量到的高度，所以不會來回切換。還放不下時照舊捲動。
11. **車站卡片看得到全部的標籤與摘要**：停靠路線的標籤原本橫向捲動，最後的「＋ 從這站開新路線」只露出「＋ 從」；改成放不下就換行（`ChipFlow`）。摘要「車站 · 瑞芳 · 2 座月台，共 128 公尺」可以到三行。
12. **車站的小標籤不蓋自己的站名**：決策 119 的標籤在車站下方 16 點，蓋住地圖畫在那裡的站名下半；改成 34 點，在站名下面。
13. **地圖的邊界外面淡淡地上色**：實景截圖左右各一條貫穿畫面的細線，是遊戲地圖的邊（`Palette.mapEdge` 的 1 點線），在 Apple 或 OSM 的地圖上像畫壞了。邊界外加 12% 的同色，線就看得出是地圖到這裡為止。
14. **空的土地分區圖層說明為什麼是空的**：分區圖層只畫玩家劃的分區（決策 98）；地點檔的工業、公園與農地只決定實景地圖的人與工作放在哪裡（決策 93），所以沒有人劃過分區的遊戲在這個圖層什麼都沒有。沒有分區時圖例多一行「還沒有劃分區：點「建設」→「建物」→「分區」來劃」。
15. **現金流量表最後是期初與期末現金**：實景示範一開始多給它三條路線的造價、馬上花掉，第一天的報表寫「購置 −$6,636,800」，銀行裡卻還有 $3,000,000，看不出怎麼對得上。帳是對的；`cashFlowRows(previous:closingCash:in:)` 給了期末現金時多兩列「期初現金」（期末減本期淨增減）與「期末現金」。經營明細用現在的現金當本期期末、本期期初當上期期末；年報用年底資產負債表的現金。
16. **沒有建議時點站長**：原本沒有反應，像壞掉；改成跳一下說「一切順利，繼續保持！」（`StationMasterAdvice.allWellText(in:)`），VoiceOver 的值也是這句。
17. **建物的細節卡片太擠**（之後的截圖，iPhone 橫拿）：五種建物排成一列，名字被截成「小…」「辦…」「漁…」「遊…」；最上面「點選車站即可選取」在建物工具裡沒有用（點地圖選的是建地）；說明太長，底下的費用要捲動才看得到。建物種類改成一列三個（和分區一樣），建物工具不顯示選取列，說明縮成「點地圖選位置；擋到的城市建物會被收購拆除」（不能蓋的地方，預覽本來就會說）。

**沒有改的**：小地圖鈕蓋住底圖的站名（浮在地圖上的按鈕都會蓋住下面的東西）；鋪軌時確認膠囊後面的淡淡殘影（程式裡只有一個膠囊，可能是截圖時的動畫，要在實機上再看）。

**沒有驗證的**：Linux 不能建置 App；第 5–13、16、17 點的畫面要看 CI 的 Xcode 建置、模擬器 UI 測試與實機。第 6 點 MapLibre 的避讓、第 7 點 SF Symbol 的樣子、第 10 點手機上是否剛好放得下，都要實機確認。

**參考**：參考庫沒有對應（網頁版的地圖文字由 MapLibre 自己排、沒有遊戲另畫的站名牌；網頁版沒有 iPhone 橫拿的版面）。外部只看文件：MapLibre 的 symbol 排列規則（高的圖層先排、`text-allow-overlap`／`text-ignore-placement`），Apple MapKit 的 `MKPointOfInterestFilter`。程式是本專案自己寫的。

### 124. 地面高度（軌道與地形的高度，第一步）

2026-10-09。設計說明 `docs/research/TERRAIN_HEIGHT_DESIGN.md`（#283，定案 #284：作者把六個選擇交給 Claude Code 以玩家的角度決定，全部照建議）的第一步 H1：把地面高度的資料放進遊戲。這一步**沒有任何規則讀地面高度**；軌道的結構物與造價改成量地面是 H2，畫面（縱斷面、費用分項、高度圖層）是 H3。號碼依工作登記 #231：存檔 27、golden schema 47。

參考檢查（`a91453/railway-reference-private` `05d7000`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「地面高度（決策 124）」）：參考沒有遊戲能用的地面高度資料。`Railway/site_archive_clean/rail-3d/` 讀 Mapterhorn 的 DEM 圖磚，但圖磚沒有存在參考裡（只有 manifest）；`Simulator/` 的地形是模型鐵道的整數層；`terrain-elevation.js` 的「海邊 0 m 是有效值」照用。外部只取想法：OpenTTD（GPL-2.0）的高度存在格的角點；GraphHopper（Apache-2.0）的橋與隧道內部不跟 DEM 起伏，留給 H2。

1. **GameCore 怎麼存**（`Sources/GameCore/City/Ground.swift`）：
   - 以土地的 1 km 區塊（`LandBlock`，16 × 16 格）為單位，每塊存 **17 × 17 個 64 m 格角點**的高度，整數公尺（`Int16`），逐列由北而南（`GroundBlock`）。
   - 每塊多存東、南兩邊（和鄰塊重複），所以一塊自己就能算出塊內任何一點；設計說明原本寫 16 × 16 加鄰塊，讀入時要多讀三塊，改成這樣比較簡單，存檔每塊多 13%。
   - `GameWorld.ground`（`Ground`）是讀過的區塊；`setGround(_:)` 加入區塊，每塊只讀一次（沒有區塊、在世界外、重複或已讀過是 `GameError.invalidGround`），失敗時什麼都不變。
2. **任一點的高度**（`groundHeight(at:)`，世界單位）：
   - 所在格四個角點的雙線性內插：權重是點在格裡的位置（0…4096），`Σ h × 權重 × 64 / 4096²`，整數運算，最後四捨五入一次（剛好一半時往上，海平面以下也是）；分子最多約 2¹⁵ × 2²⁴，不會溢位。
   - **沒有讀過任何地面的世界處處是 0**（空白地圖、所有舊存檔，和決策 30「地面處處是 0」相同）；讀過一些的世界，在沒讀過的區塊或世界外是 `nil`。
3. **台灣的資料**（`RailwayGameApp/Resources/RealWorld/taiwan_heights.dat`，`tools/real-world-population/build_slope_grid.py` 的第四個參數）：
   - 決策 115 算陡坡時已經在水域的 1.875″ 格網上取 Copernicus GLO-30 的高度、做 3 × 3 中位數，算完就丟掉；這次把同樣的高度四捨五入到公尺寫出來，水與沒有圖磚的地方是 0。
   - 格式（設計說明原本用 zlib；GameCore 不匯入 Foundation、Linux 的 Foundation 也沒有 zlib，所以改成純 Swift 就能解的格式，大小差不多）：每一列各自以「和前一格的差」存成 varint，連續的 0 另記長度，表頭與每列的位移讓 App 只解它要的列。11,990,289 bytes（zip 約 8.4 MB）；整張 9,296 × 8,064 的 `Int16` 是 150 MB。
   - 抽查：阿里山車站 2,221 m（實際 2,216 m）、武嶺 3,270 m（3,275 m）、玉山 3,901 m（3,952 m，中位數削平山頂）；台北車站約 20 m（實際約 7 m：地表模型的市區建物沒有完全去掉）。
4. **App**（GamePresentation 的 `HeightGrid`）：啟動時和其他實景檔一起讀（`RealWorldData.heights`，交給 `GameSession.heights`）；格之間是四個格中點的雙線性內插（浮點數）；`ground(of:frame:)` 給 GameCore 一塊的角點，四捨五入到公尺，相鄰兩塊的同一個角點一定相同。實景地圖的路網卡片在點的兩端後面寫「地面海拔 20 → 35 公尺」。資料來源畫面的 Copernicus 一項寫上地面高度的用途，並補上授權要求的免責句。
5. **和設計說明不同的地方：這一步還不讓遊戲讀入地面。**設計說明的 H1 寫「新實景遊戲標記有地面、App 沿新軌道讀入區塊」；但現在軌道的高度是絕對值、地面的結構物只能在 0 m 上下 2 m，在有地面的世界裡蓋在 0 m 的軌道，到 H2 改成量地面時會在讀檔時不合法。所以新遊戲照舊沒有地面，H2 把「讀入地面」與「結構物量地面」一起打開；H1 只有 GameCore 的層、存讀檔、golden 與 App 的顯示。
6. **存檔**：版本 27，世界多一個 `"ground"`（`{"blocks": [{"row", "column", "heights": [...]}]}`，依列、行排序；沒有時不寫）。只讀到 26 的 build 會丟掉地面，所以升版。新的 `SaveFixtures/v27-ground-height.json`。
7. **golden**：schema 47，新指令 `setGround`（`blocks`）、觀察 `groundHeight`（`point`）、結果 `invalidGround`，最終狀態選填的 `groundBlocks`；新的 `ground-height.json`（全部手算）。既有 golden、存檔與 replay 的預期值都沒有改變（沒有世界讀過地面）。

**限制與之後**：
- 沒有遊戲讀入地面（第 5 點）；H2 才打開，同時把結構物、節點的高度範圍改成量地面，加上自動的結構物、過水用橋與土方費（見下面的 H2）。
- 台北等市中心的地面偏高約 10 m；H2 的規則看軌道和地面的高差，整片市區一起偏高時不受影響。
- 實景示範與平溪線劇本預先蓋好的軌道在 0 m，H2 要一起處理（照舊平地，或改用地面高度重蓋）。H2 選了照舊平地；決策 132 用地面重蓋了實景示範，平溪線劇本照舊平地。
- 空白地圖沒有山；由種子產生的地形用同一種區塊。

**沒有驗證的**：Linux 不能建置 App；路網卡片的文字與新的資源檔要看 CI 的 Xcode 建置與實機。

#### H2：軌道量地面、自動的結構物與造價（2026-10-09）

設計說明第 5、6 節的第二步，作者說「做 h2」。號碼依工作登記 #231：存檔 28、golden schema 48，決策仍是 124。參考檢查（`05d7000`，和 H1 同一版）：設計說明第 10 節的清查不變；參考沒有土方、橋與隧道的造價，也沒有過水的規則（gap，自己寫）；分界取自 `rail-3d/integration/rail-structures.js` 的 `VIADUCT_LIFT_M = 6`（遊戲用 8 m，配合造價的交叉點）。

1. **世界「有地面」**（`Ground.isMapped`）：讀入第一塊地面，或新實景遊戲在蓋任何軌道前呼叫 `mapGround()`，世界就有地面；之後沒讀過的區塊高度是未知（`nil`），不是 0。已經有軌道的世界不能再 `mapGround()`（`invalidGround`）：蓋在平地上的軌道不會被後來的地面改量。空白地圖、示範地圖、平溪線劇本與所有舊存檔沒有地面，**照 Stage S4 的規則與價格**，既有的 golden、存檔與 replay 都不變。
2. **App 讀入地面**（GamePresentation）：`GameLauncher` 的新實景遊戲與全島地圖在建好世界後 `mapGround()`；鋪軌的預覽、建造與剪刀式交叉在下指令前，先用 `setGround` 讀入軌道點下的區塊（`readGround(under:from:)`，`HeightGrid.ground(of:frame:)`）。預覽仍在副本上執行同一個指令。缺高度檔時 GameCore 回 `groundNotLoaded`。
3. **高度相對地面**：節點只能在所在點地面 ±4096（±64 m）；新節點的「地面以上 N 公尺」是點下去那一點的地面加 N。沒有地面的世界地面是 0，和以前一樣。
4. **區段**：每 16 m（計價長度）取中點的 Δ（軌面 − 地面）與水，分成地面（|Δ| ≤ 2 m）、路堤（≤ 8 m）、路塹（≥ −11 m）、高架（> 8 m）、隧道（< −11 m）；水上 Δ ≥ 4 m 是橋、Δ ≤ −10 m 是隧道，其他是 `trackOverWater`。短於 4 段（64 m）的區段併入兩旁之一：只併入仍然合法的類別，兩旁都行時併入較貴的一側，一樣貴時併入左邊；併入時路堤可到 15 m、路塹可到 20 m。高於地面 64 m 是 `structureTooHigh`。常數在 `TrackSectionRules`（`Sources/GameCore/Railway/TrackSections.swift`）。
5. **新的結構物 `automatic`**（App 的預設，選單第一項「自動」）：邊存它的區段（`TrackEdge.sections`，`[{kind, lengths}]`，由 `from` 起，相鄰兩段不同類）。另外四種是「整條邊強制」，在有地面的世界每 16 m 對地面檢查一次（高架不在水上、地面在 ±2 m、隧道 Δ ≤ 0、高架與橋最高 64 m）。切開一條邊時兩半各自重算區段。隧道口可以在邊的中間（區段的邊界）；節點上的隧道口照舊看兩旁的區段。
6. **造價**（每 16 m 一段）：軌道費 × 係數（地面類 1、高架 3、橋 4、隧道 5），加上自動的邊或有地面的世界才有的：
   - 土方費（地面類的段，h = |Δ| − 128 > 0）：`track × Σ 7h(1280 + 3h) / 3,276,800`，整條邊加總後四捨五入一次。就是設計說明的梯形斷面（頂寬 10 m、邊坡 1:1.5）乘每立方公尺 track × 7/6400（新遊戲 $1.75）。**和設計說明不同**：單價跟著軌道費走，不另加 `costs.earthwork`，所以 `ConstructionCosts` 與存檔格式不變。
   - 墩高費（高架與橋的段，Δ > 15 m）：`track × Σ(Δ − 960) / 640`，加總後四捨五入一次。
   - 拆遷照舊，但只拆露天的區段下的公司建物；隧道段上的建物留著（`openStretches`）。
7. **車站**：有地面的世界裡車站的點不能在水上（`onWater`）；月台可以在橋上。
8. **讀檔**：`structureProblem` 用同樣的規則重查（區段要蓋滿整條邊、只有自動的邊有區段、每段的類別要合地面）。版本 27 有 `"ground"` 的存檔讀成有地面：沒有任何 build 寫過有地面又有軌道的存檔（App 在 H2 之前不讀入地面）。
9. **畫面**：自動的邊依區段畫（隧道段虛線、高架與橋的畫法），路線色在隧道段變淡；`RailwaySnapshot` 的月台結構物是它所在區段的（不會是 `automatic`）。路網卡片與建造訊息寫「自動：地面 48 公尺、高架 176 公尺」。
10. **存檔 28**：邊可以是 `"automatic"` 並帶 `"sections"`；世界可以有 `"ground": {"blocks": []}`（有地面、還沒讀）。fixture `SaveFixtures/v28-terrain-track.json`。
11. **golden schema 48**：新指令 `mapGround`，結構物 `"automatic"`，結果 `groundNotLoaded`、`trackOverWater`、`structureTooHigh`，最終狀態的邊選填 `sections`；`terrain-track.json` 全部手算。

**平衡（量過的）**：`BalanceReportTests` 的第一條線（448 m、三站、一列四節，$914,800）在第 8 天回本（108%）。它的軌道只有 28 段 × $1,600 = $44,800：整條是 8 m 路堤或高架多約 $89,600，整條隧道多 $179,200，以頭一週每天約 $11–14 萬的營業利益算，回本晚約 1–1.5 天。山線的造價主要是長度乘係數；數字先照設計說明，實機再調。

**沒有驗證的**：Linux 不能建置 App，`MapArt` 與 `NetworkControls` 的改動要看 CI 的 Xcode 建置與實機；全島地圖上沿新軌道讀入區塊的速度要實機量。

#### H3：縱斷面、費用分項、邊坡與高度圖層（2026-10-09）

設計說明第 7、8 節的第三步。號碼依工作登記 #231：存檔、golden schema 都不動，決策仍是 124。**不改任何規則或價格**：GameCore 只多了唯讀的查詢，既有的 golden、存檔與 replay 都不變。參考檢查（`05d7000`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「畫面（決策 124 的 H3）」）：參考沒有縱斷面的圖、沒有分項的造價畫面（`Ci/` 的 `showMetroCostPreview` 只有一個總額，也沒有人呼叫）、沒有平面地圖上的邊坡；高度圖層照用 `rail-3d` 的 MapLibre `landscape-hillshade`（光從 315°、強度 0.42、陰影 `#5c785f`、亮面 `#fff4d6`），它沒有依高度的配色（gap）。

1. **GameCore 的唯讀查詢**（`TrackSections.swift`）：
   - `GameWorld.longSection(of:)`：一條邊的 `TrackLongSection`：兩端與每 16 m 中點的軌面高度、地面高度、類別、是否在水上（`TrackGroundSample`），區段，以及分項的造價。量法和建造時的規則相同（`survey`）。
   - `TrackCostParts`：軌道（每段一倍軌道費）、土方、高架與橋（多出來的係數加墩高費）、隧道（多出來的四倍）。四項的捨入和 `price(of:track:extras:)` 一樣，加起來就是建造時扣的錢（測試逐項手算）。`price` 本身沒有改，只把「乘以軌道費再四捨五入」抽成 `share(of:_:_:)` 共用；`edgeCost` 取每段類別的部分抽成 `pricedPieces`。
2. **建造卡片**（`NetworkControls`）：預覽仍在丟棄的副本上建造，再向副本問新邊的 `longSection`：
   - **縱斷面**（`LongSectionChart`，GamePresentation）：橫軸里程、縱軸海拔，上下各留一成、至少 16 m；水上的段塗淺藍，每個區段在軌面與地面之間塗它的顏色，再畫地面線與軌道線（隧道段虛線），標出上下的高度、長度與出現的類別。
   - **費用分項**（`NetworkCostParts.lines(in:)`）：軌道、土方、高架與橋、隧道、拆遷（`clearingCost`），沒有花費的項目不列，最後是合計，和預覽的費用相同。X 型交叉渡線列四段的合計，不畫縱斷面（平的）。
3. **路堤與路塹的邊坡**（`TrackSlope`，GamePresentation；`MapArt.drawSlopes`）：自動的邊每 16 m 依中點的高差，在路基（寬 10 m）兩旁畫出邊坡的寬度（每公尺高差 1.5 m，和土方的梯形斷面相同），再畫橫向的短線（每 4 m 一條，長短交錯）：路堤的短線從路基邊往外，路塹的從坡頂往內。路堤用參考的路基色加深，路塹用較深的土色。只在近看（`detail == .full`）時畫，和邊的幾何一起算一次。
4. **高度與陡坡圖層**（`PopTravelMode.terrain`、`TerrainMap`，圖層選單的「地形」）：
   - 實景地圖讀 App 的高度檔（`HeightGrid`），在 64 m 格的角點取樣一次（在背景執行緒）；地圖超過 1,025 個角點寬時（全島）隔幾格取一個。沒有高度檔時讀世界已讀入的地面；沒有地面的世界（空白地圖）是平地，不畫，圖例寫「這張地圖是平地」。
   - 每格（拉遠時併成 2、4、8… 格的區塊，和城市圖層相同）依中點高度著色（本專案的配色：0 m 淡綠到 3,500 m 淡灰，每 25 m 一階），再依跨過區塊的坡度以西北方的光加陰影或亮面（強度分八階，畫面上只有幾百種顏色）；水不畫。陡坡（決策 115）的格畫斜線。點一格顯示「海拔 N 公尺」與是不是陡坡。
5. **字串**：圖層選單的三句加進 `Localizable.xcstrings`（繁中已翻）；其他新文字用 `Text(verbatim:)` 與 `DisplayLanguage.text`。
6. **卡片的高度**（2026-10-10，PR #293）：H3 合併後，`main` 的 `TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds` 在 iPhone 橫向失敗（`Build Track` 不能點）。詳細卡片超過最大高度就捲動，動作按鈕排在最後，縱斷面與分項把它推出畫面，玩家也要先捲動才按得到。改成：沒有地面的世界（空白地圖、教學）不畫縱斷面與分項（地面是 0 m 的平地，費用就是軌道的，上一行已寫）；手機上兩者預設收起，按「縱斷面與費用」（`network.section`）才展開，iPad（兩個方向都是 regular）照舊直接顯示。只改 `NetworkControls`；GamePresentation 的 `NetworkPreview` 照舊算出兩者。

**沒有驗證的**：Linux 不能建置 App：`NetworkControls`、`MapArt`、`MapView`、`PopulationLegendView`、`MapLayerSheet`、`Palette` 的改動要看 CI 的 Xcode 建置；縱斷面、邊坡、圖層的顏色與在全島地圖上拉近拉遠的速度要實機看。設計說明第 7 節的「節點顯示地面高度」已在 H1 的路網卡片；側邊工具列的「橋／隧道」「上／下」與參考 `Simulator` 的「覆土不足」提示（`shallowBores`）沒有做，留給之後。

### 125. 第一條線一條龍：教學走路線面板的配車，等到第一筆車資

2026-10-09，作者的評估：「玩家選兩個車站，系統找出沿途停靠站，接著提示購車與營運，最後帶玩家看到第一筆收入。這些底層能力大多已經存在，應該整合，而不是再做另一套路線系統。」底層確實都在：在地圖上選站並自動找出沿途的站（決策 100）、建立路線後選好新路線，路線面板接著出現「購買 N 列並開始營運」（決策 101，一步買車、放到起點、指派與設定班距）。但教學（C5）還在教決策 101 以前的手動流程：「列車」工具買車、選站放車，再到「路線」把列車指派過去；而且最後一步只說「票價是你的收入」，沒有等到錢真的進來。

1. **兩步併成一步**：「購買並放置列車」（`train.place`）與「開始營運」（`line.service`）換成一步 `line.staff`「開始營運」：新路線已在路線面板選好，選班距、按「購買…列並開始營運」。目標照舊是 `startService`（有一列新指派的車、路線設了要跑車），所以手動的流程也照樣算數；只有放車的目標 `placeTrain` 沒有步驟用，拿掉。教學框指的是那顆按鈕（新的 `TutorialTarget.staffLine`，`line.staff.start`，和它的無障礙識別碼同名）與「路線」鈕；按鈕捲出路線面板時只框「路線」鈕。
2. **控制時間接在開車之後**：建造時遊戲會暫停（決策 99），開車那一步還在「路網」工具裡，所以這一步出現時通常是暫停的；文字改成「建造時時間會暫停。按繼續，或從選單選倍速」。按繼續就算改了速度（原本的規則）。
3. **新的一步「第一筆車資」**（`first.fare`，目標 `earnFare`）：等到這一步出現之後寫進帳本的結算裡有車資（`CompanyAccounts.income(writtenAfter:in:of:)`，決策 117 的同一個算法，只數 `fareRevenue`）。框住狀態膠囊的現金（新的 `TutorialTarget.cash`，`hud.cash`；決策 117 的「+$」就從那裡浮起）與倍速。自由模式不收車資，這一步直接算完成。文字提醒一直沒人搭的原因：車站 800 公尺內要有人住或工作（決策 108 選址時就會顯示）。
4. **乘客那一步移到最後**，文字從「票價是你的收入」改成「車站附近住和工作的人越多，搭車的人就越多」：收入上一步已經看到了，這一步帶到城市。

步驟還是十一步：路網、鋪軌、移動地圖、兩座車站、建立路線、開始營運、控制時間、第一筆車資、乘客、結束。UI 測試只走到第二座車站之前，不受影響。GameCore、存檔、golden、replay 都不變。

**沒有驗證的**：Linux 不能建置 App；教學框是否框得到路線面板裡的按鈕（`Form` 加了 `tutorialClip()`）、現金的框，要看 CI 的 Xcode 建置與實機。

**參考**：`Ci/` 的 `TUTORIAL_STEPS[7]`「设置发车」框的就是路線資訊面板的上線列車數（`#panel-line-info`、`#line-info-capacity-row`，並替玩家打開第一條線的面板），和這裡指向路線面板的配車按鈕相同；`[10]`「控制模拟」照舊。參考沒有等收入的步驟，第 3 點是本專案自己的。

### 126. 城市建物畫在一般地圖上

2026-10-09，作者的評估：「城市現在主要是色塊和圖示……應讓玩家直接看到住宅、商店、高樓逐漸出現」。查下來比那更少：城市自己長的建物（決策 74、75）只在用途、地價、腹地、分區四個圖層才畫，而且是一格一色的方塊；不開圖層時一般地圖上看不到城市，只看得到玩家自己的建物（決策 92）。建物的用途與密度（D1–D4 = 2／6／18／40 層）GameCore 早就有，缺的只是畫出來。

1. **`CitySkyline`**（GamePresentation）：從 `GameWorld.land` 與 `GameWorld.buildings` 推導，每格一個「地塊」：建物的用途與密度（既有存量畫成 D4），公園與農地是空地（城市在每一格土地上都有一筆建物資料，公園、農地也有，所以看的是用途不是有沒有建物）；被收購的格（決策 95）沒有地塊。依列、再依行排好，只取畫面內的部分（`lots(in:rowsBelow:)`，往南多看一列，因為那裡的高樓會長進畫面）。不存檔，也不是世界的第二份：地圖在土地或建物改變時（最多每晚一次）在背景重算，和城市圖層（決策 89）一樣。
2. **畫法**：每棟畫在格子中央的 40 m 見方（`PlacedBuildingRules.cityBuildingSide`，就是決策 95 收購時用的建地），淺色屋頂加深色外牆、藏青細框，屋頂依密度往上抬：D1 0.2、D2 0.45、D3 0.8、D4 1.4 倍邊長。不照比例（照比例 D4 會蓋住北邊兩格，整個市中心變成一排柱子）。D3、D4 在建物夠大（14 點）時，外牆上有淺色的樓層帶。顏色依用途，色相和用途圖層一樣（住宅綠、商業藍、辦公橘、工業紫、公共紅、觀光綠松），比玩家的建物淡，玩家的建物仍然有自己的圖示（決策 121），一眼分得出來。公園、農地是淺綠、淺米色的地面。
3. **由北往南畫**：前面（南邊）的建物蓋住後面的牆腳；同一列裡同一種顏色一次填完，所以一列只要十幾次填色。
4. **縮放**：一格（64 m）不到 9 點時變成平面的方塊，不到 3 點時不畫。
5. **只在空白地圖**：實景地圖的背景（Apple 地圖或 OSM）已經畫出真的城市，再疊一層方塊會蓋住它；實景的城市照舊看用途圖層。打開四個城市圖層之一時，也改畫圖層，不畫建物。
6. **看得到長大**：每晚建物升級（決策 75）、城鎮往車站擴張（決策 73）之後，地圖重算，樓就變高、新的房子出現。沒有做成長動畫：一晚的變化在 600 倍速下是幾秒內一起發生，之後要的話在這一層上加。

GameCore、存檔、golden、replay 都不變。

**沒有驗證的**：Linux 不能建置 App；樣子是用 Chromium 照同一個畫法、用新遊戲第一座城鎮的真實資料模擬的（PR 附圖），實際的 Canvas、效能與深色模式要看 CI 的 Xcode 建置與實機。

**參考**：參考庫沒有可以移植的 2D 城市畫法：`Ci/` 的土地來自它沒有附上的向量圖磚；`Railway/taipei_gta_reference/` 是 three.js 的 3D 台北（真實的建物幾何），留給 Phase 8 的 3D renderer。畫法是本專案自己的；SimCity BuildIt（作者的截圖，商業遊戲）只取「建物依密度長高、用途用顏色分」的想法。

### 127. 設定頁的版本與「回報問題」

2026-10-09，作者的評估把「玩家問題回報入口、版本資訊」列為開放測試前必做。之前設定頁只有音樂與音效；App 裡找不到版本，測試者回報時說不出是哪一版。

1. **版本**：設定頁多一段「關於」，第一列是 `CFBundleShortVersionString (CFBundleVersion)`，例如「0.4.0 (12)」，可以選取複製。
2. **回報問題**：`ShareLink` 分享一則寫好的訊息（`ProblemReport`）：三個問題（發生了什麼事、原本預期、怎麼重現），下面是版本、系統與機型代碼（`utsname.machine`，例如 `iPhone17,1`），從遊戲選單打開時再加一行遊戲的狀態（`GameSession.problemReportGame`：空白或實景、自由或經營、劇本的 id、時間、現金、站數、路線數、列車數、存檔版本）。主旨是「沿線 0.4.0 (12)：問題回報」。
3. **不寫死收件者**：App 不知道也不放任何人的信箱或網址（這個 repository 是公開的，也不放個人資料）；玩家在分享表選郵件、訊息或其他 App，按下傳送前什麼都沒有送出。TestFlight 的測試者也可以照舊用 TestFlight 的截圖回饋，說明寫在這一段的註腳。
4. **文字不進字串目錄**：新的字用 `DisplayLanguage.app` 選語言、`Text(verbatim:)` 顯示，和其他 GamePresentation 寫的文字一樣，翻譯檢查不需要新的條目。

GameCore、存檔、golden、replay 都不變。

**沒有驗證的**：Linux 不能建置 App；分享表、版本列的樣子與 iPhone 橫拿時放不放得下，要看 CI 的 Xcode 建置與實機。

**參考**：參考庫沒有對應（`Ci/` 是網站，沒有 App 的版本與回報）；做法是 iOS 的 `ShareLink`，本專案自己寫的。

### 128. 建站時說出腹地，站長講城市怎麼長

2026-10-09，作者的評估：「告訴玩家新站讓多少人受益、人口增加多少」「把站長提示擴充到人口、城市成長與經營狀況」。之前選址時已經會顯示 800 公尺內的居民與就業（決策 108），蓋好之後卻只說「已建造車站」；城市每晚的成長（決策 70、73、75）只寫在車站面板的一行字，站長（決策 118）在第一條線開了之後就只會說「一切順利」。

1. **建站的訊息加上腹地**：新車站（不是既有車站加月台）建好時，有土地的世界在訊息後面接「800 公尺內：居民 N · 工作 M。服務好，附近的城市就會長大。」，數字和選址時的一樣（`Land.totals(within:of:)`）；800 公尺內沒有人時改成「800 公尺內還沒有人住或工作，搭車的人會很少。」沒有土地的世界（自由的測試世界、舊存檔）照舊。
2. **站長的兩句新話**（`StationMasterAdvice`），排在原本的擔心與第一條線的步驟之後，只在土地會成長的世界（`GameWorld.landDemand`）、依昨晚量到的數字：
   - `underserved`（擔心）：有車站昨天的服務率低於 80%（`LandDemand.upgradeService`，建物升級的門檻）：「昨天「X」只有 64% 的旅客搭上車。到 80% 附近的城市才會長高，加開列車吧。」取編號最小的；服務率 0 是還沒量過，不算。
   - `townGrew`（好消息，站長是開心的表情）：沒有上面的情況時，昨天成長最多的城市：「「X」附近的城市昨天成長了 1.2%。服務好，城市就會繼續長大。」同樣多時取編號最小的。
   - 都沒有時照舊「一切順利」。數字每晚會變，站長每晚會自己說一次新的。
3. 關閉的車站不算（決策 77）。

GameCore、存檔、golden、replay 都不變（只讀 `TownGrowth.Place` 已有的 `lastService`、`lastGrowth`）。

**沒有驗證的**：Linux 不能建置 App；站長泡泡放不放得下較長的句子（原本就會換行）要看實機。

**參考**：參考庫沒有對應（`Ci/` 的提示是固定的導覽；`Railway/taipei_gta_reference/` 的 `.hud-obj` 是決策 118 已參考的一行目標）。SimCity BuildIt 的顧問會說城市發生了什麼（作者的截圖，只取想法）。

### 129. 站前長得快、九成滿就改建（城市長高的速度）

2026-10-10，ROADMAP 平衡報告「待觀察」第 5 項。作者要求：一般玩家在 1 小時內看得到車站附近冒出新的高樓，第一條線約 8 天回本不要被破壞。

**量到的原因**（`BalanceReportTests`，`main` `761116f`，第一條線 70 天，新增「最滿的 D3」一欄）：開通後第 1–7 天 D4 從 29 格長到 45 格，都是開局時就已滿的 D3；之後 D4 停在 45 格，第 63 天才又有新的 D4。這段時間最滿的 D3 從 49% 每天只長約一個百分點。成長依各格的人數比例分給整個 800 m 腹地，每格每天大約都長 1.2%，D3 升到 D4 要多 2.2 倍的人，從半滿到滿要將近兩個月。600 倍速下一天約 2.4 分鐘，1 小時約是第 25 天。

**比較過的調法**（第一條線；「新的 D4」指開局就滿的那一批之後，由成長長出的第一棟）：

| 調法 | 新的 D4 | 回本 | 第 30／60 天現金 | 外圍的 D2→D3 |
| --- | --- | --- | --- | --- |
| 現況 | 第 63 天 | 第 8 天 | $6.80M／$14.12M | 照常 |
| 升級先挑最滿的格 | 第 63 天（沒有差別：沒有格是滿的） | 第 8 天 | 不變 | 照常 |
| 滿格門檻改成九成 | 約第 55 天 | 第 8 天 | 不變 | 照常 |
| 服務好的車站成長率 +1%／天（整個腹地） | 第 36 天 | 第 8 天 | +15%／+33% | 照常 |
| 同上 +2%／天 | 第 12–21 天零星，第 26 天起每天 | 第 8 天 | +26%／+51% | 照常 |
| 只重新分配：站前 256 m ×8、九成 | 第 20 天 | 第 8 天 | 0%／−2% | 幾乎停住（升級總數少約六成） |
| 站前 256 m ×2、九成 | 第 29 天 | 第 8 天 | +15%／+24% | 照常 |
| **站前 256 m ×3、九成（採用）** | **第 19 天**，第 25 天起幾乎每天 | 第 7 天（100%） | +25%／+40% | 照常 |

只重新分配不加總量時，現金不變，但外圍的 D2 有五十天不再升級，整座城市每天看得到的變化反而變少，所以不用。整個腹地都加速則多出太多現金與運量，換到的 D4 又比只加站前的少。

1. **站前**：一座成長中的車站，中心離它不到 256 m（16,384 單位，四格，`LandDemand.stationFrontRadius`）的格是它的站前。成長時，站前的格以三倍（`LandDemand.stationFrontGrowth`）的成長率長：一晚加上 `((R + 2F) × g + 500) / 1000` 位居民（至少 1），`R` 是這站分到的居民，`F` 是輪到這站時站前各格的居民，再依各格的居民、站前的格算三倍，以最大餘數分配；就業也一樣。仍然受每格建物的容量限制，放不下的照舊不給別格（決策 75 第 1 項），所以站前已滿或是既有存量的格，它的那份也會丟掉。成長率 `g` 照舊依服務與可達車站數（決策 70），服務不好的車站，站前也長得慢。
2. **九成滿就算滿**：建物的主要人數（住宅的居民、其他的就業，決策 77）到表上的九成（`LandDemand.upgradeFullness` = 900‰）以上，午夜開始時就是滿的，可以升一級。每站每晚最多兩格、每格一晚一級、依列與行的順序都不變。「升級先挑最滿的格」量不出差別，不採用。
3. **畫面**：車站面板的那一行改成「昨日：旅次服務 100% · 可達 2 站 · 90%滿的建物會升級」；站長的 `townGrew` 句子加上「車站 250 公尺內長得最快」，讓玩家知道往哪裡看。
4. **量到的結果**（第一條線）：回本第 7 天剛好 100%（原本第 8 天 108%），仍約 8 天；第 19 天第一棟成長長出的新 D4（600 倍速約 46 分鐘），第 30 天 D4 76 格（原本 45 格），第 60 天 168 格；D3 第 25 天 215 格（原本 205 格），外圍照常升級。示範地圖：第 8 天回本不變，第 30 天 D4 289 格（原本 203 格），現金 +8%。代價是回本之後的現金與運量長得更快（第 2 項，交給 Phase 7）。

存檔格式不變（只改規則的數字），舊存檔讀入後從下一個午夜起照新規則成長，SaveFixtures 不變。Golden：五份 fixture 的值改變，改成 schema 49（沒有新的指令或欄位，表示這一版的成長規則），逐項說明在 `GoldenScenarios/README.md`；新值都由 GameCore 取得，再由照新規則改寫的 `tools/golden-checks/city_growth.py`、`city_buildings.py` 與手算核對。ReplayFixtures 沒有土地，不變。

**參考**：參考庫沒有成長規則（`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §9 只點名 OpenTTD 的 town growth）。OpenTTD（GPL-2.0，只取想法）的城鎮在受服務的車站越多時長得越快，並以較大的建物取代舊的；A 列車的站前開發是同一個方向。數字是本專案自己的（gap），由 `BalanceReportTests` 選出。

### 130. 城市建造 P0-D：出售公司的建物（賣給城市）

2026-10-10，`docs/research/CITY_BUILDING_STUDY.md` §4.3 的「出售」與 §5 的 P0-D；接決策 94、95。作者定的範圍：GameCore 的出售指令、賣掉的建物留給城市、App 建築工具的「出售」模式、財務畫面的出售收入與已實現損益、用 `BalanceReportTests` 量出售對現金的影響。旋轉（等有長方形建物）與買入既有城市建物另做。號碼依工作登記 #231：存檔 29、golden schema 50。參考庫沒有不動產或出售（`docs/RAILWAY_REFERENCE_MAPPING.md`「出售公司的建物」）：規則與數字是原生的（gap → 原生），只有現金流量表把出售收入放在投資活動的流入，照 `Ci/` 的 `investingCashFlow = quotaReturnCashInflow − Math.abs(quotaPurchaseCashOutflow)`。

1. **售價**（`GameWorld.saleQuote(of:)`、`PlacedBuildingSaleQuote`）：目前的土地使用權 × 95%（`PlacedBuildingRules.saleLandPercent`，捨去）＋ 建物帳面價值 × 入住係數。
   - 土地使用權照建造時的算法：中心那一格**現在**的地價 × 占地。付過的收購費（決策 95，併在 `landCost` 裡）不算進去，賣掉拿不回來。
   - 建物帳面價值只算建物本身：建物費依資產紀錄的天數直線折舊 30 年，`建物費 − ⌊建物費 × 天數 ÷ 10,800⌋`（不超過整筆紀錄的帳面價值）。沒有資產紀錄（版本 22 以前、自由模式）是 0。
   - 入住係數：入住（居民＋就業）÷ 容量（兩者合計）達一半以上全額；以下照比例，`⌊帳面價值 × 入住 × 2 ÷ 容量⌋`。從 0 到半滿連續增加，半滿時剛好全額，不會在 50% 跳一級（研究寫的「以下照比例」取這個連續的讀法）。
   - 自由模式不記帳：售價 0，城市一樣接手。
2. **指令** `sellPlacedBuilding(_:)`：不存在的建物拒絕（`unknownPlacedBuilding`），不改世界；沒有其他拒絕的理由（賣出只會收錢）。經營模式收到售價，資產紀錄下帳。ID 不重用。
3. **已實現損益**（照決策 85 的資本日）：`CapitalDay` 多 `saleProceeds`（出售收入）與 `saleBookValue`（下帳的整筆紀錄帳面價值，土地與收購費都在內），都是非負的，0 時不寫。`FinanceSummary` 多同名兩欄與 `realizedGain = saleProceeds − saleBookValue`。本期淨利 = 營業利益 − 利息 − 折舊 − 報廢損失 ＋ 已實現損益；投資活動 = 出售收入 − 購置。權益只隨已實現損益改變（現金多了售價、資產少了帳面價值），資產負債表恆等式照舊成立。出售不寫帳本列，和買進一樣只記在資本日；`LedgerEntry.amount` 與營運帳不變。
4. **城市接手**（`handOverToCity(_:)`）：建物從公司的清單拿掉，它佔的格不再被佔（`isClaimedByPlacedBuilding`），城市之後可以在那裡長。居民與就業搬到中心那一格（漁人碼頭、遊艇港的中心在水上時，是建物下第一格陸地，依列、行）：
   - 那一格沒有土地：變成建物用途的一格（小住宅住宅、商店與漁人碼頭商業、辦公樓辦公、遊艇港觀光），城市建物開啟時蓋上裝得下的建物（決策 74 的 `fitting`），編號接在最後。
   - 那一格已有土地：用途不變、人數相加（每項最多 10 萬）；公園不住人，改成建物的用途。城市建物還裝得下主要人數就照舊，否則換成裝得下的建物、編號接在最後。
   - 沒有人的建物不留土地。
   - 人從建物的中心移到格子中心，所以 800 m 腹地邊上的建物可能換一座車站；一般情況運量不變（`BuildingSaleTests` 驗證）。
5. **畫面**（GamePresentation `BuildingSaleSession.swift`、App `ControlPanel`、`MapBuildConfirm`）：建築工具的模式變成「建造／拆除／出售／分區」。出售模式點自己的建物（或觸控半徑內最近的一棟）只是選它（`GameSession.saleCandidate`）：地圖用綠色虛線框標出；卡片寫出入住、土地（目前的土地使用權 × 95%）、建物（帳面價值 × 入住係數）、售價與帳面價值、已實現損益（虧損用紅字）；地圖旁的膠囊（✗／✓ $售價，上面一行損益）或下方「出售 · $X」按鈕才真的賣（`confirmSale()`，一次可以復原的編輯）。換模式、換工具會清掉選取。經濟明細與年度決算共用的損益表多三列「出售建物收入」「出售建物的帳面價值」「出售建物損益（已實現）」，現金流量表的投資活動多「出售建物收入」，都只在本期或上期有出售時出現。字串都由 `DisplayLanguage` 提供，`Localizable.xcstrings` 不必改。
6. **存檔**：版本 29。資本日與年度決算多選填的 `saleProceeds`、`saleBookValue`；版本 28 以前沒有這兩個鍵，讀成 0（沒有賣過），淨利與投資現金流和以前一樣。新的 `SaveFixtures/v29-building-sale.json`；既有 fixture 都沒有改。
7. **golden**：schema 50，新指令 `sellPlacedBuilding`、觀察 `buildingSale`、`financeReport` 每一期選填的 `saleProceeds`、`saleBookValue`；新的 `company-buildings-sale.json`（手算）。既有 fixture 的預期值都沒有改變，replay 不變。

**量到的影響**（`BalanceReportTests.testAFirstLineWithBuildingsToSell`，release，`BALANCE_REPORT=180`；第一條線照舊第 8 天回本，第 30 天現金 $8.50M）：第 30 天在中間站旁買兩棟辦公樓。

| | A：車站旁，收購 D4 | B：鎮邊的空地，768 m 外 |
| --- | --- | --- |
| 買價 | $7,338,355（建物 $245,760、土地 $251,443、收購 $6,841,152） | $846,131（建物 $245,760、土地 $64,307、收購 $536,064） |
| 入住 | 收購的人搬進來，當天 100% | 4% → 第 45 天 49% → 第 75 天 100% |
| 第 30 天就賣 | $426,263（5.8%） | $72,734（8.6%） |
| 第 60 天賣 | $425,580 | $296,441（35%） |
| 第 180 天賣 | $422,849 | $293,710 |

- 兩棟合計每天的不動產淨收入約 $8,100（租金減維護與土地稅），只有鐵路營業利益（第 180 天約 $94 萬／天）的 1%。第 180 天兩棟一起賣，收入 $716,560，已實現損失 $7,354,252，現金從 $97,836,120 變成 $98,552,680；沒買的第一條線同一天是 $105,932,531。
- 出售對現金的影響只有售價這一筆，約等於兩棟留著再收 88 天的淨收入。所以照現在的數字，留著不如賣掉，但兩者都遠低於買價。
- 虧損主要是收購費（決策 95 的 120%）。土地依現在的地價計，收購付的 D4 樓地板賣掉時不算錢。A 收購後那一格成了空地，地價從 $245／m² 掉到約 $185／m²（決策 95 的限制），售價跟著降。
- 不收購的建物入住過半就能拿回建物的帳面價值，所以「在空地上蓋、等車站把它住滿再賣」最划算，和 A 列車的玩法一致。

這一步只照研究的規則做出售；租金的水準、收購費要不要算進售價、地價受收購影響，屬於 Phase 7 的平衡，寫進 ROADMAP 的待觀察，不在這裡改。

**限制**：只能賣給城市，不能買回或買入既有城市建物（之後另做）；沒有旋轉；出售不另外課稅（A 列車的出售稅留給 Phase 7 的稅制；決策 131 起，已實現損益算進每天的營利事業所得稅的稅前淨利）；城市接手只留在一格，不保留建物的實際大小與位置。

### 131. 營利事業所得稅（回本後的現金）

2026-10-10，ROADMAP 平衡報告「待觀察」第 2 項。作者要求：回本之後現金一直滾，大約第 30 天以後錢就沒有意義；調整之後第 30 天以後錢仍然要有意義，同時不破壞第一條線約 8 天回本與決策 129 的城市長高速度（成長長出的新 D4 約第 19 天）。

**量到的原因**（`BalanceReportTests`，`main` `a874b5a`，release build）：第一條線第 7 天回本，第 30 天 $8.50M、第 60 天 $19.77M（起始資金 $3M 的 6.6 倍）；示範地圖第 8 天回本，第 30 天 $12.60M（4.2 倍）。第一條線的費用每天約 $58,000，60 天都不變，票價收入卻跟著城市從每天 $180,825 長到 $520,065（運量 35,917 → 100,979），所以每天的營業利益從 $122,457 長到 $461,696。另外，8 天回本就是每天約 12% 的報酬：即使利潤一點都不長，第 60 天也有約 3 倍，目標只能訂在這之上。

**目標**（由 Claude Code 依耐玩性提出）：沒有玩家操作的第一條線第 60 天不超過起始資金的 5 倍（$15M）、第 30 天不超過 2.5 倍；示範地圖第 30 天不超過 3 倍；第一條線仍約 8 天回本；城市的成長完全不變；城市長大仍然多賺（第 60 天每天的淨利仍約是回本那週的 2 倍）。一般玩家會擴張，所以更重要的是：越大的公司，下一筆投資回本越慢。

**比較過的調法**（第一條線 60 天、示範地圖 30 天；標「估」的是用現況的逐日損益算的，稅不改運量與城市，採用的那一組實跑與估算只差 $1 萬）：

| 調法 | 第一條線回本 | 第 30 天 | 第 60 天 | 示範地圖回本 | 示範第 30 天 | 其他 |
| --- | --- | --- | --- | --- | --- | --- |
| 現況 | 第 7 天 | $8.50M（2.8 倍） | $19.77M（6.6 倍） | 第 8 天 | $12.60M（4.2 倍） | |
| 營運成本隨運量：每位付費乘客 $0.50 | 第 8 天 | $7.69M | $17.65M（5.9 倍） | — | — | 只是平移，形狀不變；再高就破壞回本 |
| 維護費隨規模：車站人事每天多 $2,000 × 站數² | 第 8 天 | $7.96M | $18.69M（6.2 倍） | — | — | 一條線的規模不變，只是固定費用變高 |
| 壓低成長後的運量：每站 30,000 人以上每 100 人 20 旅次 | 第 8 天 | $7.23M | $14.78M（4.9 倍） | 第 12 天 | $7.33M（2.4 倍） | 乘客少三成；示範地圖的站一開始就超過 |
| 同上，40,000 人以上 10 旅次 | 第 7 天 | $7.69M | $14.79M（4.9 倍） | 第 12 天 | $7.02M（2.3 倍） | 同上 |
| 同上，30,000 人以上 10 旅次 | 第 8 天 | $6.59M | $12.29M（4.1 倍） | 第 19 天 | $4.71M（1.6 倍） | 同上 |
| 稅：每天稅前淨利超過 $100,000 的部分課 40%（估） | 第 8 天 | $7.14M | $15.09M（5.0 倍） | 第 11 天 | $9.04M（3.0 倍） | |
| **稅：超過 $100,000 的部分課 50%（採用）** | **第 8 天（103%）** | **$6.80M（2.3 倍）** | **$13.93M（4.6 倍）** | **第 11 天（101%）** | **$8.16M（2.7 倍）** | 城市與運量完全不變 |
| 稅：超過 $100,000 課 40%、超過 $200,000 課 70%（估） | 第 8 天 | $6.83M | $13.21M（4.4 倍） | 第 12 天 | $7.28M（2.4 倍） | 邊際 70% 太重 |
| 稅：超過 $150,000 的部分課 50%（估） | 第 7 天 | $7.47M | $15.36M（5.1 倍） | 第 10 天 | $8.90M（3.0 倍） | 第一條線幾乎到回本才開始課 |
| 回本後的再投資出口 | — | — | — | — | — | 沒有量：模擬裡沒有玩家，不用它的玩家照樣滾；建物出售在決策 130 另外做 |

壓低運量的三組都沒有改到城市（新的 D4 仍第 19 天），但每一站各算各的，新蓋的線又是一條每天 12% 的線，擴張的玩家照樣滾；它也改掉「每 100 人每天 40 旅次」這條玩家看得到的規則，乘客變少。依絕對金額或人數的調法都會拉長示範地圖的回本，因為示範地圖第 1 天的利潤（$301,898）就是第一條線第 30 天的水準。稅以整間公司計算，擴張的玩家也一樣受限，所以採用稅；示範地圖回本從第 8 天變成第 11 天是預期的代價：它第 1 天就是一間三條線的公司。

1. **稅**：每個經營中的午夜，在當天的折舊之後、年度決算與目標判定之前，公司付當天稅前淨利超過 $100,000（`CompanyAccounts.taxFreeProfit`）部分的 50%（`CompanyAccounts.taxPercent`），四捨五入到整美元（`GameWorld.dailyTax(on:)`）。稅前淨利是營業利益（票價 − 營運、維護、能源、人事 ＋ 建物收支）− 利息 − 折舊 − 報廢損失 ＋ 出售建物的已實現損益（決策 130）：賣建物賺的錢當天一起課，賠的錢減少當天的稅。台灣的房地合一稅是分開計稅的，之後若另做出售稅，再把它從這裡拿出來。虧損或不到 $100,000 不課，虧損不往後扣抵。自由模式什麼都不課。
2. **帳**：帳本多一種列 `dailyTax`（項目 `incomeTax`，「營利事業所得稅（日結）」），日帳多 `taxCost`。稅不是營運成本：營業利益不變，`FinanceSummary.profitBeforeTax` 是稅前淨利，本期淨利 = 稅前淨利 − 稅，營業活動的現金流量也扣稅。年度報表一起記，所以挑戰的「年度淨利」與權益都是稅後。
3. **畫面**：損益表在有稅的期間（本期或上期）多「稅前淨利」與「營利事業所得稅」兩列，現金流量表多「所得稅支出」；經營面板的報表下面寫「營利事業所得稅：每天的稅前淨利超過 $ 100,000 的部分課 50%，午夜支付」。`BalanceReportTests` 多一欄「Tax」。
4. **量到的結果**：第一條線第 8 天回本（103%，決策 129 之前也是第 8 天），第 30 天 $6.80M、第 60 天 $13.93M；每天的淨利從回本那週約 $13 萬長到第 30 天 $21 萬、第 60 天 $28 萬，城市長大仍然多賺，但多賺的部分少了一半。示範地圖第 11 天回本，第 30 天 $8.16M。城市、運量、地價與服務率的欄位與現況逐日相同（新的 D4 第 19 天，第 30 天 D4 76 格）。之後每一條新線的利潤在公司超過 $100,000 之後只留一半，所以第二條線起回本大約要兩倍的時間。

存檔格式不變：`taxCost` 只在非零時寫（日帳與年度報表），舊存檔讀成沒有稅，和決策 67 的利息一樣，存檔版本不變；SaveFixtures 不變。之後決策 133 把存檔升到 30，所以有稅的新存檔也是 30，只讀到 29 的 build 會說存檔較新，不會丟掉稅額；#295 到 #300 之間寫的 29 版存檔可能帶著稅額，只有那段期間發出過版本時才有影響，不另外處理（見決策 134 第 5 點）。Golden 不變：沒有一份 fixture 一天賺超過 $100,000（golden schema 51 沒有用到）。ReplayFixtures 不變。

之後要看：鐵道大亨挑戰（一年淨利 $3 億、權益 $10 億）現在以稅後計算，變難了，實機或模擬看到達不到時再調目標；平溪線的挑戰（一年 $200 萬）每天遠低於 $100,000，不受影響。

**參考**：參考庫沒有稅（這次在整個參考庫搜尋 `tax`，只有地圖圖層名稱與 OpenTTD 的文件；`docs/research/PHASE7_COMPANY_STUDY.md` 已盤點 `Ci/reference_snapshot/lib/` 的 `taxRate`、`propertyTax` 等詞，沒有命中；`Ci/` 的經濟只有票價與營運、維護、能源、人事，見決策 36），也沒有通貨膨脹或費用隨規模。OpenTTD（GPL-2.0，只取想法）以通貨膨脹讓錢長期保持意義，但它以年計，這裡要的是 60 天內；《A 列車》系列的法人稅是同一個方向。稅率與門檻是本專案自己的數字（gap），由 `BalanceReportTests` 選出。

### 132. 實景示範地圖用地面重建，路線加長

2026-10-10，作者要求：「把示範實景平溪地圖原樣套用新地形模組重建。這是太久之前的了，然後能長一點，或者車多一點沒關係，反正是示範，以後還能測試。」決策 124 的 H2 讓新實景遊戲量地面，但實景示範（2026-10-05）與平溪線劇本預先蓋好的軌道照舊在 0 m 的平地上。號碼依工作登記 #231：決策 132；存檔版本、golden schema 都不動。

1. **地面**：`RealWorldDemo.make(in:railways:land:water:steep:heights:)` 開一個有地面的新遊戲（`mapGround`），用 App 的高度檔讀入路線下的區塊（每 32 m 一點，四周各 16 m），全部結構物是「自動」。App 的「實景示範」把 `GameLauncher.heights` 傳進去；沒有高度檔時改開原本的平地示範（沒有地面時，有些在地面上一上一下的路線在 0 m 會交叉）。
2. **縱坡**（`TrackRise`，GamePresentation）：每 8 m 一個樣本，加上每段水平區間的兩端：
   - 目標是沿線地面前後 160 m 的平均。
   - 限制：坡度不超過 25‰（`RealWorldDemo.rulingGrade`，參考 `rail-3d/physical/level-profiles.json` 的 `basis` 給台鐵的值，遊戲上限 40‰）；車站整段水平，在站點地面 ±8 m 內；過水至少高出水面 5 m（橋），做不到時改在水下 12 m 以下（隧道）；離地不超過 56 m（遊戲的高架與橋最高 64 m）。
   - 解法：先正反兩趟求出每個樣本在坡度限制下還到得了的高度範圍，再從頭依序取最接近目標的值。若沒有解，先把最近的一段水改成隧道；水都試過了，就讓車站多離地 4、8、12 m 再試（例：海科館月台的盡頭離一條溪 12 m，±8 m 內橋與隧道都放不下）。
   - 節點的高度取整到世界單位；節點離地不超過 60 m（遊戲是 64 m），在比這更深的隧道裡不放節點，那段就是一條長邊。邊依直線坡度和縱坡差 1 m 以內為原則再切（`TrackPlan` 多了 `rise`）。
3. **路線加長、車多一點**：
   - 主線從七堵（縱貫線）經八堵接宜蘭線到牡丹，兩端各多 300 m。
   - 縱貫線在八堵西邊 250 m 分出，沿自己的軌道經三坑到基隆。
   - 平溪線在三貂嶺待避線南端分出，深澳線在瑞芳待避線西端分出（和平地示範相同）。
   - 待避線在七堵、四腳亭、瑞芳、猴硐、三貂嶺、牡丹、三坑、十分。
   - 合計 18 站（原本 12 站），約 47 km 軌道。
   - 四條路線：平溪線（瑞芳–菁桐）2 列、宜蘭線（牡丹–七堵）2 列、深澳線（八斗子–瑞芳）1 列、縱貫線（七堵–基隆）1 列，共 6 列（原本 4 列）。決策 133 起有真實班次檔時，平溪線與深澳線合成照真實班次開的平溪線（3 列），宜蘭線改為 1 列，見決策 133 第 8 點。
   - 列車數照單線容量：縱貫線七堵到三坑一長段單線只容 1 列；宜蘭線容 3 列，但第一站牡丹只有兩個月台，而遊戲只從第一站派車。縱貫線在八堵用路線的月台偏好（`setLineRoutePreferences`）停自己軌道上的月台，否則路線會停在宜蘭線的月台、無法往基隆。
   - 新車站的運量是本專案的數字：七堵 12,000、八堵 6,000、暖暖 5,000、牡丹 1,000、三坑 4,000（住宅），基隆 24,000（辦公）。
4. **為了地面改的幾何**：
   - 待避線離主線改成 6 m（平地 5 m）；主線與待避線在待避區間內緊貼路線（1 m）。這樣在彎道上兩條軌道也保持遊戲要的 4 m 間距。
   - 待避線一次以 `buildTrackEdges` 蓋完，全部接上後才檢查間距。逐條蓋時，遠端那一條還沒接上，沿軌道的距離超過 512 m，坡道段會被判太近。
5. **價格**：GameCore 新增唯讀的 `GameWorld.trackEdgePrice(from:to:curve:profile:structure:)`。它用和 `buildTrackEdge` 相同的區段規則與價格報出一條邊的造價，不必真的蓋。
   - 示範先在讀好地面的世界上規劃與報價，加上車站與列車，開局資金是新遊戲的 $3,000,000 加上這些（約 $15.21M），蓋完剩下的正好是新遊戲的錢。
   - 原本要蓋兩次（先試蓋算出價格），報價讓建置時間減半（Linux debug 約 18 秒）。
   - 量到的結構物（有水域時）：地面 19.0 km、路塹 11.8 km、路堤 9.2 km、隧道 5.9 km、高架 2.4 km、橋 1.6 km。
6. **高度檔的水**（`tools/real-world-population/build_slope_grid.py`、`taiwan_heights.dat`）：決策 124 把所有的水寫成 0 m，算中位數時也把水當 0。結果山裡的每條河都是一個坑：十分附近 180 m 的溪讀成 0 m，溪邊的格也被拉低到約 50 m，平溪線過溪的橋高於地面 64 m 以上，蓋不了（玩家自己沿真實路線蓋也一樣）。
   - 改成中位數取在水還在的 DEM 上：離乾地 8 格（約 450 m）內的水（河、湖、岸邊）是它的水面高度（不低於 0）；外海、台灣 OSM 整包當成水的對岸大陸、沒有圖磚的地方仍是 0。
   - 陡坡照舊以水為 0 計算，`taiwan_water.json` 逐位元組不變（重跑原本的程式先確認可以逐位元組重現兩個檔）。
   - 檔案 11,990,289 → 12,029,523 bytes；208,027 格水高於海面。`HeightGridTests` 的抽查不變。
   - 已存的遊戲照舊用它讀過的區塊（存在存檔裡），之後才讀的區塊用新的高度。
7. **平溪線劇本不動**（決策 90）：它的目標是在平地示範上量的，所以改呼叫 `RealWorldDemo.makeFlat(in:railways:land:water:steep:)`，就是原本的示範，蓋出來的世界和之前相同（`TrackPlan` 加的參數都有預設值，`close` 由一段改成一串，平地示範照舊只傳一段）。`RealWorldDemoTests` 照舊測它，釘住的行車時間與容量都沒有變。

**參考**（`a91453/railway-reference-private` `05d7000`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「實景示範用地面重建（決策 132）」）：
- `rail-3d/physical/level-profiles.json` 有 6,283 條 OSM 鐵路擬合好的縱斷面，但它的地面是 Mapterhorn DEM，和遊戲的 Copernicus 地面不同，直接搬過來會和遊戲量的地面對不上。所以只採用它的方法與數字：台鐵 25‰、高架至少離地 6 m。
- 用它估的站高可以對照：瑞芳 55、三貂嶺 113、十分 176、菁桐 234 m；這裡是 59、133、181、249 m，地表模型的樹與房子讓山區偏高。
- 解縱坡的寫法是本專案自己的。外部沒有用到程式碼：坡度限制的投影是一般的做法。

**沒有驗證的**：Linux 不能建置 App；實機上開實景示範要多久（Linux release 的時間寫在 PR）、六列車在地圖上的樣子、縱斷面卡片在這些邊上的樣子，要看實機。

### 133. 路線照真實班次發車（實景示範的平溪線）

2026-10-10，作者在決策 132 之後說「能套用真實班次更好」，選了「路線照時刻發車」（GameCore 的新功能，先套平溪線與深澳線；宜蘭線、縱貫線維持班距，因為它們現實是雙線，示範的單線容不下）。號碼依工作登記 #231：決策 133、存檔版本 30、golden schema 51。

1. **班次（`LineRun`，`Sources/GameCore/Railway/LineRuns.swift`）**：
   - 一班車從路線的一站到另一站，往哪個方向都可以，中間每站都停。
   - 每站有到、開的時刻，是那天的秒數，過午夜就超過 86,400，但在第二個午夜之前結束；時刻不能倒退。
   - `days` 是星期幾開：位元 0 是星期日，照 `StationDemand.weekday(ofDay:)`，遊戲第 0 天是星期一。
   - 路線多兩個欄位：`runs`，以及 `runDays`（每班最後一次開出的遊戲日）。
   - 只有不是環線、沒有停站模式、不重複停靠同一站的路線能有班次。
2. **派車**：有班次的路線不照班距派車（決策 23），改照班次：
   - 一班車在當天的第一個出發時刻前 5 分鐘（`LineRun.earliestDispatch`）就派出一列，條件是那列停在這班的起站、沒有服務、在軌道上、速率大於 0、開得完這一班，交通控制下還要拿得到第一段的進路。開得完的意思是照現在的方向或先折返都行，取較短的；中間可以在 V4d 的中途折返。
   - 時刻表：起站到達是現在、開車是班次的時刻（若比現在加最短停站還早，就用後者）；其他各站照班次，但不早於前一站開車；終點站就是服務的終點。
   - 列車通常比真實的快，所以在各站等到真實的開車時刻，照時刻走。
   - 找不到列車時一直等，晚 30 分鐘（`LineRun.latestDispatch`）還沒派出就取消這一天。
   - 開完一班的列車停在終點站，等下一班從那裡開的車。
   - 閒置快轉在班次開始或結束可派的那一秒醒來；交通控制等進路的列車與死結偵測（V2）也算進班次的列車。
   - `LineRunsTests` 驗證一次推進 3,000 分鐘和逐分鐘推進的結果相同。
3. **乘客**：
   - 照常搭（決策 35），方向是這一班沿路線站序的方向，坐到這一班的終點。原本「來回各一半」的規則用在班距的路線。
   - 全網路徑與需求要的班距由班次推出（`runHeadway`）：所有班次的第一個出發到最後一個出發，除以班次較多那個方向的班數減一，無條件進位到分鐘；一個方向只有一班時是一天。
   - 列車數是指派的列數。
   - 有班次的路線的路線偏好（決策 61）照它這一班的站序對應。
4. **指令**：
   - `setLineRuns(_:to:)` 免費，依序檢查 `unknownLine`、`invalidLineRuns`、`trainServiceActive`（有列車在跑時不能改，因為乘客的方向跟著班次）。
   - 有班次的路線加停站模式是 `invalidLinePattern`、改成環線是 `invalidLineRuns`。
   - 換站序或拆掉一站時清掉班次，因為班次以站的索引記；反轉站序時把班次對應到反轉後的索引（決策 134 起只有沒有列車的路線能反轉）。
   - 複製路線時一起複製班次，但都還沒開過。
5. **存檔 30**：路線多了 `"runs"`（`{"from", "to", "times": [[到, 開], …], "days"}`，`days` 是每天時省略）與 `"runDays"`。只讀到 29 的 build 會丟掉班次、照班距開，所以升版。新的 `SaveFixtures/v30-line-runs.json`。
6. **golden schema 51**：新指令 `setLineRuns`、結果 `invalidLineRuns`，最終狀態的路線有班次時寫 `runs` 與 `runDays`。新的 `line-runs.json`，時刻與餘額手算。參考模型（`ReferenceWorld`）不跑班次，所以這份 fixture 不在它上面重播（同土地），由 `LineRunsTests` 驗證。既有的 golden、存檔與 replay 都不變。
7. **真實的平溪線**（`tools/real-timetables/extract_pingxi_runs.py` → `tra_pingxi_runs.json`，12 KB）：
   - 資料：參考 `Railway/site_archive_clean/data/tra_schedule_dense.json`，即臺鐵開放資料 14 天的每一班車，依「政府資料開放授權條款第 1 版」使用，資料來源畫面新增「臺鐵開放資料」。
   - 一條路線八斗子—菁桐（經瑞芳、三貂嶺）。停平溪線車站的 38 班車都取：八斗子的直通車整班；八堵的車從瑞芳起，因為八堵—瑞芳是宜蘭線、照班距開。
   - 星期幾開取第一週（2026-10-02 到 10-08），因為 10-09 是國慶補假，開週末的車。平日 34 班、週末 34 班，週末少 4 班平日車、多 4 班八斗子車。
   - 真實的車組會往返主線，每天不會回到原處，所以加一班回送：十分 04:15 → 瑞芳，時刻照 4735 次。
   - 程式檢查每天開始與結束時三組車都在十分、菁桐、瑞芳各一，這也是開局放車的位置。
8. **示範的配合**（`RealWorldDemoGround`）：
   - 有班次檔時，平溪線與深澳線合成一條有班次的平溪線，3 列；真實的深澳線班次全是直通平溪線的車。
   - 瑞芳多一條在另一側的待避線（決策 132 的 6 m），平溪線進瑞芳偏好停在那裡，主線與第一條待避線留給宜蘭線。
   - 宜蘭線與縱貫線照台鐵的營業時間 05:00–24:00，夜裡停駛，閒置快轉也因此跳得過夜裡。
   - 宜蘭線改為 1 列。兩列宜蘭線在瑞芳會車時，若兩列平溪線正在瑞芳等下一班，三條股道都被占住，從猴硐來的宜蘭線進不來、要往猴硐的車也出不去，就是死結（無頭模擬第 6 小時就發生）。
   - 合計 3 條線、5 列車，平地示範是 4 列。沒有班次檔時照決策 132（4 條線、6 列）。
9. **量到的**（Linux release，有水域與高度，`advance` 逐分鐘）：
   - 連跑一週：沒有死結，每一班都開出。
   - 第一天 16 次到站晚超過 2 分鐘，最多約 14 分鐘，原因是在猴硐與三貂嶺等會車。
   - 模擬一天約 167 秒；照班距的同一張圖約 265 秒，平地示範約 76 秒。跑多快要看實機。

**參考**（`a91453/railway-reference-private` `05d7000`，對照表在 `RAILWAY_REFERENCE_MAPPING.md` 的「路線照真實班次發車（決策 133）」）：
- 網站（`index.html` 的 `sched` 系統）照臺鐵時刻表在地圖上逐班開車：列車在第一站的開車時刻出現，照時刻沿站移動，跑完就消失。遊戲的列車是買來放在軌道上的（決策 14），所以改成從停在起站的列車派出，跑完留在終點。
- 時刻資料直接取用。網站的交會推算（`inferMeetPassTimes`）已在決策 59 移植，這裡的班次照常用它與交通控制。
- 參考沒有讓真實班次載客、也沒有車組回到原處的處理（gap）：回送與開局放車的位置是本專案自己的。

**沒有驗證的**：Linux 不能建置 App，開始畫面與資料來源畫面的文字要看 CI 的 Xcode 建置與實機；路線面板對有班次的路線仍顯示推出的班距，沒有逐班的時刻表畫面，留給之後。

### 134. 有列車的路線不能反轉站序

2026-10-10，`docs/PR200_290_REVIEW_HANDOFF.md` 第四節第 1 項，作者選了 (a)。號碼依工作登記 #231：決策 134；存檔版本、golden schema 都不動。

**問題**：決策 80 的反轉站序保留指派的列車，已發出的列車照自己的時刻表跑完。照班距的路線只從第一站派車，列車跑完舊的一趟停在舊的起站，也就是反轉後的最後一站，之後再也不發車；同時等這條線的乘客全部離開。環線已發出的列車，方向標籤也會和實際行駛方向相反。

1. **規則**（GameCore，`GameWorld.reverseLineStops(_:)`）：路線本身或任一個服務模式有指派的列車（不論有沒有發出）時拒絕，沿用 `trainOnLine`，指出編號最小的那一列（新的唯讀 `ServiceLine.assignedTrains`：路線與各服務模式的列車，依 ID 遞增）。檢查順序：`unknownLine`、`trainOnLine`。拒絕時世界不變。把列車從路線移除（`unassignTrain`）後就能反轉，再重新指派。
2. **畫面**（App 的 `LinesPanel`）：有列車時「反轉站序」停用，站序區的說明多一句「這條路線有列車時不能反轉站序，請先把列車從路線移除。」。從其他路徑呼叫時，`GameSession.reverseSelectedLine()` 顯示 `trainOnLine` 的訊息，不留復原步驟。
3. **沒有採用**：(b) 從任一端發車並翻轉乘客與列車的方向標籤（改動大）；(c) 反轉時自動撤下列車（玩家不容易察覺列車被撤下）。
4. **有班次的路線**（決策 133）：一樣拒絕。班次從起站派車，反轉本身不會讓它停擺，但等車乘客的方向跟著站序，規則統一比較好懂。`LineRunsTests.testLineEditsKeepOrEndTheRuns` 改成先把列車移除再反轉。
5. **所得稅的存檔版本**（同一份交接文件第五節「需要作者決定」）：決策 131 的 `dailyTax`、`incomeTax`、`taxCost` 沒有升版；決策 133 已升到 30，所以不再另外升版，只在 `SavedGame` 的版本 30 與決策 131 補上說明。

存檔、golden、replay 都不變：golden 與 replay 沒有反轉路線的指令。

**參考**：MapBuilder 的 `handleReverseStationOrder`（決策 80 的來源）只編輯路線圖，沒有列車；參考裡沒有營運中路線的反轉規則（gap），這條規則是本專案自己的。

## 目前規則摘要

- 世界的範圍：`WorldBounds`，世界單位的寬與高，每邊 `1...WorldBounds.maximumSide`（2^25 單位，524,288 公尺，決策 88；之前是 2^20，16,384 公尺，E1 起是新遊戲的大小，現在叫 `WorldBounds.standard`）；點在世界裡是 `0 <= x < width`、`0 <= y < height`。世界沒有格子：鐵軌只在路網上、車站在點上（決策 48、51、54）。
- 鐵軌只在路網上（下面的連續軌道與立體鐵路，決策 29、30）。F3c 之前另有方格的鐵軌、轉轍器、平面交叉與佔格車站（決策 10、26、27），已經移除（決策 51）。
- 拆邊（`removeTrackEdge`）依序拒絕：不存在的邊、有列車（車頭或車身）在上面（`trackEdgeInUse`）、有月台（`trackEdgeHasPlatform`）、交通控制下被預約（`trackReserved`）；拆節點要先拆掉接在它上面的邊（`trackNodeInUse`）。拆除免費且**不退款**。
- 新購列車未放置。列車放在路網的邊上，`0 <= offset <=` 邊長，有車身時 `offset > 0` 而且後方的軌道放得下整列；放置、取下、反向都免費。
- 已放置的列車以非負整數 rate（每遊戲分鐘的邏輯單位）沿明確的路（`edges`，可以停在最後一條的中段 `end`）移動；沒有路時只走到目前邊的端點。服務的列車在兩站之間改跟著行駛曲線，rate 只決定動或不動（決策 40）。前方被拆的鐵軌讓列車在最後一個可達節點等待，補回後自動續行，等待的距離不累積（決策 15）。
- 推進時間時若遊戲秒會溢位，整批拒絕（`clockOverflow`）。
- 遊戲時間以秒計，基本步長是一秒；速度是每 tick 的十分之一秒（`x1` 是真實時間，`normal` 一 tick 一分鐘），不足一秒的部分留到下一個 tick。列車每秒走它每分鐘 rate 的份，整分鐘加起來正好是 rate，到站也每秒判定；帳、乘客釋出與派車在整分鐘處理，停站、上下車與出發在任何一秒（決策 37、39）。
- 車站或列車的 ID 已配發到最後一個（`Int.max − 1`）時，建站或購車被拒絕（`idsExhausted`），不扣款（決策 6）。
- `route(from:to:)` 回傳從列車位置到路網節點的最短路，或 `nil`；它是唯讀查詢，不會自己設定列車的路（決策 16、29）。
- 車站的月台是它在路網邊上的月台；`path(from:toStation:)` 回傳到停車位置的路（決策 31）。列車的路走完、車頭在該站的月台上時停在該站（`stationsStoppedAt(by:)`）；停站由狀態推導，不另存（決策 18、31）。
- 列車有 1 到 16 節，車廂中心相距 `Train.carLength` = 1024 單位（16 公尺），只能在不在軌道上時設定，每加一節收 `ConstructionCosts.car`、減少不退（決策 46）；車頭後方的車身記錄在 `trailEdges`，移動時跟著走，反向時車頭移到車尾。車身下的邊不能拆。整列都在同一個月台上時才算整列停妥（`stationsBesideWholeTrain`，決策 27、31）。
- 列車的時刻表是依序的停靠（車站、排定的到達與離開，開局以來的遊戲秒，決策 37），時間從 0 起不倒流、每站都是存在的車站；`setTrainTimetable` 整份原子替換、`[]` 清除、免費。時刻表是計畫資料：放置、取下、反向、移動指令與時間都保留它；只有明確啟動的服務會讀它（決策 19、20）。
- 時刻表可以每隔固定的秒數重複（`setTrainTimetable(_:to:repeatingEvery:)`），停靠可以標記在離開時折返；週期至少 1 秒，而且重新開始時時間不倒流（決策 21、37）。
- `startTrainService` 讓停在第一站車站的列車依時刻表執行服務：只跑一次，或一輪接一輪重複（`execution` 記錄目前是第幾輪的第幾個停靠，存檔；重複的時刻表從下一個準時的輪次開始）。每一秒先處理停站與出發，再移動、推進時鐘、判定到達（決策 37、39）：列車在每一站停站（到達後 8 秒開門、上下車、至少停 36 秒，時刻表的第一站、最後一站與折返的站 42 秒，關門 9 秒），不會早於排定出發時刻離開，誤點時停完就走；兩站之間跟著行駛曲線，走排定出發到排定到達的時間，排得太緊時走最少的秒數，晚出發時整段往後移（決策 40）；啟動服務與零距離到達下一站（已停在那一站的車站）都算到達；沒有路就關著門等待；最後一站停完、而且到了排定出發才結束服務，重複的時刻表則接著下一輪。實際的到達與出發時刻（`times`）存檔，誤點（`lateness(of:)`）由它們與排定時刻算出。服務執行中不能手動設定 continuation、反向、取下或換時刻表（`trainServiceActive`），rate 仍可調整；`stopTrainService` 只結束自動化（決策 20）。標記折返的停靠在出發時先讓列車原地反向，找不到路時不反向（決策 21）。
- 服務路線是計畫資料：依序的車站、規劃行程用的性能（一段是性能建得出曲線的最少整秒，決策 40）、營運時間，以及各服務等級的列車數或目標班距；服務日決定一天中每分鐘的等級。行程、最多列車數（最短班距 2 分鐘）、實際列車數與班距由地圖推導，不存檔（決策 22、23）。
- 指派給路線的列車由路線派出：每個整分鐘在停站與出發之前，營運中、該等級有列車、距上次派車已過一個班距、跑車中的列車少於該等級的列車數時，路線讓第一台停在第一站、rate 大於 0、能開完來回的列車跑一趟來回（產生該趟的時刻表並啟動服務，在第一站停 42 秒後出發，必要時出發時先折返）。列車回到第一站後折返等待；路線的列車不能手動設定時刻表或啟停服務（`trainOnLine`，決策 23）。
- 路線可以另有區間車與快車等服務模式：停靠路線部分的站（站的索引、嚴格遞增），各有自己的列車數或目標班距與列車，從自己的第一個停靠站派車。每段鐵軌每天每個方向最多 720 班；各服務依序（路線自己的服務最先）以 `⌈1440 ÷ 班距⌉` 佔用它經過的每一段，放不下的服務減少列車數（決策 24）。
- 路線可以是環線（`setLineRing`，三站以上、第一站與最後一站不同、沒有服務模式）：列車從最後一站接著開回第一站，從不折返，依 ID 順序輪流走內環與外環；一圈是各段加上每站 1 分鐘，每個方向跑列車數的一半、各自派車、各自的班距；列車數是偶數；環線列車的第一站與最後一站最少停 36 秒；上車接走兩個方向排隊、這一圈會到的乘客（決策 49）。
- 連續軌道（決策 29）：節點是世界範圍內的整數世界座標點（`WorldCoordinate.unitsPerMetre` = 64 單位一公尺），邊是兩個節點之間的直線或整數控制點的三次曲線，長度由固定的整數取樣規則推導，每 `ConstructionCosts.trackPricingLength`（1024 單位）收一次鐵軌的費用（決策 54）。只有共用節點的邊才相接，而且只在兩個邊端離開節點的方向相反（誤差 1/16 以內）時互通；平面上交叉但沒有共用節點的邊互不相干。路網上的列車在邊上，`0 <= offset <=` 邊長，有車身時 `offset > 0`；它沿 `edges` 移動，車身記錄在 `trailEdges`，反向時車頭移到車尾。資源身分是節點，以及邊上不超過 `RailwayNetwork.spanLength`（1024）的 span（S3A）。所有鐵軌只記在 `RailwayNetwork`。
- 立體鐵路（決策 30）：節點的高度在地面（0）上下 4096 以內；邊的高度沿水平里程依縱斷面變化（固定坡度，或兩端的拋物線豎曲線），最陡 40‰。結構物決定高度帶（地面 ±128、高架與橋 ≥ 0、隧道 ≤ 0）與費用倍數（1、3、4、5）。兩條邊在平面上相遇（共用節點 1024 以內除外）時高度差至少 512，否則拒絕；同一高度的交叉必須共用節點。同一高度（高差不到 512）的兩條邊中心線至少相距 256（4 公尺），沿軌道 32768 以內的兩點（同一個交會點分開的軌道）除外，否則拒絕（`trackTooClose`）；會留下這種邊對的拆邊也拒絕（`tracksWouldBeTooClose`，決策 52）。交通控制下，平面上不到 4 公尺而沿軌道超過 512 的兩段軌道互相妨礙，列車不能取得妨礙別的列車持有的軌道（決策 53）。隧道口是隧道與非隧道的邊相接的節點。車站可以在路網上平坦的一段邊上有月台；月台屬於鐵路網，同一條邊上的月台不重疊，兩端切開那條邊的 span，有月台的邊不能拆。
- 路網上的營運（決策 31）：停站、時刻表、折返與重複、路線、派車與服務模式都在路網上（F3c 之前方格另有一套找月台、找路與移動，決策 51）。以車站為目的地的路（`TrainPath`：行進方向、停在最後一條的哪裡、精確距離）在路網上停在行進方向上月台的末端（停車位置），只考慮不比列車短的月台；總距離最短，同樣短時依邊的編號逐步決定。一段的秒數是路線的性能走完距離的最少整秒（決策 40）。路網上列車的路可以停在最後一條邊的中段（`end`，只在有值時存檔）；路走完、車頭在該站月台上（車頭所在的邊）時停在該站，整列都在同一個月台上時整列停妥。服務正在使用的月台不能拆（`trainServiceActive`）。
- 交通控制與進路預約（決策 32）：`GameWorld` 的新世界關閉交通控制，行為與之前完全相同；App 的新遊戲開啟。開啟時，列車出發、被派車或拿到新的路（手動的路、放置、反向）之前，一次取得從車尾到路的終點整列車會碰到的每個節點與 span（與佔用同一條規則，落在 span 分界上時兩邊都算），以及它接近的交會點（在交會點 1024 以內、而那裡另有不相通的邊）；任何一個被其他列車持有（佔用、限界或預約）就整個不取得，指令以 `trackReserved` 拒絕，服務原地等待（不折返）、每步重試，路線不派出那台列車。預約存檔；列車每次移動之後只留下它還需要的部分，車尾離開的軌道立刻釋放，走到路的終點時全部釋放（決策 55）。服務出發時路被行駛中、一定會讓出的前車持有，就跟車出發：只預約到前車持有的軌道之前 400 m（25,600 單位）、走到那裡停下，每一秒在出發之前延長，前車離開它的路之後取得剩下的全部（決策 56）；`unplaceTrain` 與關閉交通控制也清除它。服務出發的路被持有、又不能跟車時，改走同站另一個停車位置的避占用最短路：新借用的軌道不逆向還會開的列車的方向（執行中的服務從所在位置往後、有列車的路線整個計畫），最多長 400 m（決策 57）。只互相等待的列車是死結，每個整分鐘把其中一台服務送到途中某站的待避站，讓另一台先走，解不開時告訴玩家（決策 58）。立體交叉不共用資源。預約中的鐵軌不能拆，持有的邊不能加減月台，持有的交會點不能加邊。開啟時兩台列車需要同一段軌道就拒絕（`trainsShareTrack`）。
- 車站需求與乘客（決策 34）：車站可以有需求（五種類型之一：住宅、辦公、商業、觀光，以及決策 91 的公共設施，每天 0 到 1,000,000 個旅次）。每天的旅次分給同一條路線能到、自己有需求的車站（依它們的旅次，最大餘數法），再依一天的形狀與兩端類型的曲線分到 24 小時。每個整分鐘一開始，每一對依這一小時與下一小時內插釋出這一分鐘的份，保留不到一人的餘數；任何連續 1440 分鐘正好釋出一天的旅次。乘客在起點依路線、方向、迄點與釋出的分鐘成組排隊，先來的在前；一站最多 4000 人，放不下的離開（`overflowed`）。路線刪除或改停靠而不再載某一組時，那一組離開（`abandoned`）。每一站 `released = 等車 + overflowed + abandoned`。沒有需求時什麼都不發生。
- 車種（決策 66）：列車可以設定車種（來源 `TRAIN_TYPES`，九種），容量 = 節數 × 每節額定 × 1.1 四捨五入，門數決定上下車速度；沒有車種是標準車（每節 320／352、4 門）。
- 每週需求（決策 68）：App 的新遊戲每天的旅次乘上來源的星期係數（週日起 0.84、1.04、1.02、1.02、1.04、1.12、0.92），週末依週末的時段曲線；第 0 天是星期一，每天正好釋出當天的旅次。
- 需求事件（決策 69）：App 的新遊戲每 8–12 天由存檔的種子抽出一個展覽或大量人潮事件，提前 2–5 天公布，進行時該站的需求乘 1 + 加成。
- 城鎮成長（決策 70）：經營模式下，App 的新遊戲每個午夜依昨天的服務比例與可達車站數讓每站的每日旅次成長（最多每天 1.5%、起點的 4 倍），沒有服務時每天 −0.2%，不低於起點。
- 土地（決策 72、90）：世界可以有 64 m 格的土地，每格一種用途（住宅、商業、辦公、工業物流、學校與公共設施、觀光休閒、農業、公園；公園沒有人，其他至少一人）與居民、就業；App 的空白新遊戲有種子產生的三座城鎮，實景新遊戲有 WorldPop 的人口與 OSM 地點換算的就業，以及 OSM 的工業區、公園與農地（決策 93）。車站的腹地是 800 m 內的格。
- 運量由土地推導（決策 73）：App 的新遊戲（經營模式）每站的運量是它分到的腹地（重疊時依距離分）每 100 位居民與就業每天 40 旅次，類型是佔最多的；每個午夜服務好的車站讓腹地的人口成長並往車站蓋新的住宅格，土地不衰退。 關閉的車站不分土地（決策 77）。空白示範地圖也由土地決定運量（自己的城市取代第一座城鎮），實景示範保留固定運量（決策 78）。
- 城市建物（決策 74）：城市建物開啟時（App 的新遊戲）每格土地有一棟建物（D1–D4 或既有存量），容量依主要用途的人數選最低足夠的密度，另一項不裁人；與土地一起設定、建立城鎮與擴張。
- 容量與升級（決策 75）：城市建物開啟時土地長到每格建物的容量；每個午夜服務 ≥ 80%、可達 ≥ 1 站而且成長中的車站，依列、行把腹地裡午夜開始主要人數已滿（決策 77；決策 129 起到表上的九成就算滿）的 D1–D3 一般建物升一級，每站每天最多 2 格、每格每天最多一級；`TownGrowth.Place` 保存最近一天的 `lastService`、`lastReached`。決策 129：成長中車站 256 m 內的站前以三倍的成長率長。
- 地價與城市圖層（決策 76）：`landValue(row:column:)` 即時算出每格的地價（美分／m²）＝用途基準 × 密度係數 ＋ 最好車站的服務與可達溢價 ＋ 400 m 內有公園時 600（決策 91）＋ 劃了用途分區、400 m 內有玩家建物時 600（決策 98），夾在 500…50,000；不存檔；成長只用它選分區格（決策 98）。地圖有用途、地價、腹地涵蓋與土地分區四個圖層，車站面板顯示腹地平均地價。
- 土地分區（決策 98）：玩家可以把 64 m 格劃成住宅、商業、辦公、工業、公共設施、觀光，或不開發、保留地（`setZone`，一次最多 128 × 128 格，免費）。成長中的車站先在腹地裡地價最高的空分區格蓋那種用途，沒有時照舊在有人的格旁邊蓋住宅（跳過劃了分區的格）；不開發的格不蓋、不長、不升級，保留地只是不蓋。存檔版本 23。
- 上下車與容量（決策 35、39）：列車到達一站 8 秒後車門開好，坐到那一站的人下車（`arrived`），同時路線上的列車讓那一站等它的路線、方向、而且迄點是它到下一次折返之前會停的站的人上車：下車站遠的先上，同一迄點先來的先上，最多到容量（每輛 352 人：額定 320 × 1.1）；花的時間是較多的一邊 ÷ 每節每秒 8 人，進位到整秒；開著門時每個整分鐘釋出的人也上車。客滿的列車離開時，還在等、本來可以搭的人記進 `refused`（次數，不是人數）。列車的服務在載客時被停止，車上的人記進 `abandoned`。每一站 `released = 等車 + 車上 + arrived + overflowed + abandoned`。
- 全網路徑與轉乘（Phase 5F，決策 65）：App 的新遊戲以 `.network` 釋出乘客，每對 OD 最多三條路徑（整數分鐘的候車、乘車、轉乘成本），依持久化的配額分配；乘客按旅程在同站換車或步行到 450 m 內的另一站（路徑選擇的感知成本：`Ci/` 的 15 分鐘 × 分級係數，同站換線 12 分鐘，加 5 km/h 步行；實際換車 max(120 s, 步行)，同一路線 0；常數集中於 `PassengerTransferRules`）；車站可設 flowControl／closed（車站面板），只在第一段付原起訖票價，守恆帳歸原起站。`GameWorld` 的新世界與舊存檔是 `.direct`。
- 轉乘群組（決策 81）：玩家可以把車站連成轉乘群組，同一群組的車站之間不論距離都能步行轉乘（450 m 以上算 virtual，5 km/h）；群組有自己的 ID，存檔版本 15。
- 地圖（決策 84）：路線沿列車實際走的軌道畫，共線時依 `LineID` 並排（MapBuilder 的偏移公式），轉乘群組畫成穿過各站的白色連線；地圖改用 App 圖示的配色。只是畫面，不影響規則與存檔。縮小時站名依停靠路線的等級（MapBuilder 的站距等級與縮放門檻）出現，互相重疊時等級高的優先（決策 89）。
- 經營（決策 36）：新的世界是自由模式，什麼都不收、不記。經營模式下乘客上車時付票價（均一或依兩站的點之間精確的直線距離分段（決策 54），0 以下收 5 美元，每個迄點四捨五入到整美元），路線的列車每次離站記下班次、距離、乘客與座位；每個整點結算剛結束的一小時（營運 `75·班次 + 42·列車公里 + 18·車站`、維修 `12·路線公里 + 9·列車公里 + 8·列車`，車站是每條路線各自的停靠站），每個午夜結算前一天的能源（`220·路線公里 + 360·列車`）與人事（`620·車站 + 480·列車`），都以美元四捨五入，寫進帳本（最後 50 列）與每日的帳（720 天）。結算可以讓餘額變成負數。設定過票價時票價影響需求，以公司所在城市的基準票價比較（預設 0.75 美元，決策 46）。金額是美分。
- 行駛曲線（決策 40）：列車與路線各有性能（加速、煞車、最高速度，可以有備用值與惰行；預設是標準性能），服務執行中不能換列車的性能。服務離開一站時得到一段行駛（出發時刻、長度、秒數），存檔；被擋住時丟掉，能動時從停止狀態以最少的秒數重新出發。
- 貸款（決策 67）：經營模式的公司以 $100,000 為一步借入，最多 $5,000,000，隨時以一步償還；每個午夜付欠款 × 5% ÷ 360 的利息（整美元），寫進帳本，不算營運成本。
- 營利事業所得稅（決策 131）：經營模式的公司每個午夜付當天稅前淨利（營業利益 − 利息 − 折舊 − 報廢損失 ＋ 出售建物的已實現損益）超過 $100,000 部分的 50%，整美元，寫進帳本（`dailyTax`）與日帳；不是營運成本，本期淨利、年度報表與挑戰的淨利、權益都是稅後。虧損不課、不扣抵。
- 資產與年度決算（決策 85）：經營模式的公司記下每條軌道邊、車站、列車與加購車廂的成本，每個經營中的午夜以直線法折舊（軌道與車站 7200 天、車輛 3600 天）；拆除與減少車廂把剩下的帳面價值記為報廢損失。淨利扣利息、折舊與報廢損失；現金流量分營業、投資、籌資。資產負債表是現金、三類資產的帳面價值、借款與權益（資產 = 負債 + 權益）。每 360 天的最後一個午夜存下該年的報表與年底的資產負債表，留 50 年。
- 目標與挑戰（決策 86）：經營模式的世界可以有一個劇本：目標（連通地點、每日運量、人口、高樓、年度淨利、權益）、金銀銅的天數、破產條件與年代車種。每個經營中的午夜在年度決算之後判定，結束後遊戲繼續。快轉 6000×，每 tick 10 分鐘。
- 全島地圖（決策 88）：實景的「全台灣」是本島加澎湖、約 285.6 × 389.7 km 的世界，土地按需展開：以 1,024 m 的區塊（`LandBlock`）讀入，世界記下讀過的區塊（`landBlocks`，存檔版本 18），蓋站時讀入 2 km 內還沒讀的區塊。其他新遊戲還是 16 km、土地完整。
- 年度節慶（決策 90）：劇本可以有每年同一天、在某站提高需求的節慶，提前公布，成為種類 festival 的需求事件；平溪線劇本的天燈節在十分與平溪。
- 玩家建物（決策 92、94、95）：建築工具先選建地、看預覽，再按「建造」蓋小住宅、商店或辦公樓（自由座標的正方形，不綁土地格），不能出界、重疊或離軌道（隧道除外）與車站不到 2 m。經營模式下建物是公司的資產：付樓地板 × $40 加占地 × 地價，30 年折舊；有車站服務時每個午夜住進居民與就業、帶來運量，收租金、付維護與土地資產稅；拆除付建造費的 10%；出售（決策 130）收目前的土地使用權 × 95% 加建物帳面價值 × 入住係數（半滿以上全額），已實現損益記在資本日，建物交給城市、人留在中心那一格。擋到的城市建物（格子中央 40 m 見方）以 120% 收購並拆除，人搬進來，城市不再在那裡長；之後蓋的軌道（隧道除外）與車站穿過公司建物時付拆除費拆掉它。自由模式免費、不記帳。
- 水域（決策 105）：地形是土地用途以外的另一層，實景地圖的海、河、湖是水（OSM 的海岸線與水域，魚塭除外）。水上沒有土地：城市不往水上擴張，玩家建物碰到水就拒絕（`onWater`），水格不劃分區（整個矩形都是水時拒絕）；鐵路與車站暫時照樣能蓋。空白地圖沒有水。決策 111：漁人碼頭與遊艇港一定要蓋在岸邊（一部分在水上，否則 `needsShore`）；水邊 160 m 內地價加 $6／m²。決策 115：坡度超過 30% 的乾格是陡坡，城市不在上面擴張或升級，玩家建物與分區都不行（`onSteepSlope`）；已有的土地照舊，鐵路照舊能蓋。決策 124：世界可以讀入地面高度（1 km 區塊、17 × 17 個 64 m 角點的整數公尺，`setGround`），任一點的高度是格四角的整數雙線性內插；沒有地面的世界處處是 0 m。H2：新實景遊戲有地面，軌道量地面、每 16 m 分成地面、路堤、路塹、高架、橋、隧道（結構物「自動」），過水要橋或隧道，加土方與墩高費，車站不在水上；沒有地面的世界照舊。
- 車站建在世界座標的一點（`buildStation(named:at: PlanPoint)`）：只在路網的邊上有月台；點必須在世界範圍內（否則 `outOfBounds(點)`），收一座車站的費用（決策 44、54）。F3c 起這是唯一的車站（決策 51）。
- 存檔是 `{"saveVersion": n, "world": {...}}`：讀檔拒絕比這個 build 新的版本與 1 以下的版本；`SaveFixtures/` 的每一份存檔之後都必須讀得進來（決策 45）。版本 2 的地圖只寫不是空地的格子（`occupied`），版本 1 的每一格（`tiles`）照舊讀得進來（決策 48）。版本 3 的路線可以是環線（決策 49）。版本 4 的世界可以有地理錨點（`geoAnchor`，地圖中心的經緯度，千萬分之一度）；沒有規則讀它，沒有錨點是空白地圖（決策 50）。任何版本裡手做的方格內容都拒絕並說明原因（決策 51）。版本 5 的路網列出 F2 之前蓋得太近的邊對（`spacingExemptions`）；版本 1–4 讀檔時把太近的邊對記成豁免，版本 5 的清單必須正好是太近的邊對（決策 52）。版本 6 的世界寫 `"bounds"`（世界單位），版本 1–5 的 `w × h` 格地圖讀成 `1024w × 1024h` 單位（決策 54）。版本 12 的世界可以有土地（`"land"`，決策 72）與土地需求的開關（`"landDemand"`，決策 73）。
- 車站目前不能拆除（未實作）。
- 餘額不足時不做任何修改，建設不會讓餘額變成負數（經營的結算可以，決策 36）。
