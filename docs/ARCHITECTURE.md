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
- **GamePresentation**（Phase 2B 起）是與平台無關的 Presentation 邏輯：持有世界的 `GameSession`、`TickAccumulator`、玩家看到的文字（錯誤訊息、時間、金額；英文與繁體中文，決策 38）與地圖縮放換算。它只依賴 GameCore 與 Swift 標準函式庫的 `Observation`，不 import SwiftUI / UIKit，因此與 GameCore 一起在 Linux CI 上測試。
- **App**（`RailwayGameApp/`）只有 SwiftUI 畫面：`@main` App 以 `@State` 持有唯一一個 `GameSession`，畫面讀取 `session.world` 並呼叫 session 的方法。GameCore 維持不變、不為 UI 加上 observation。

### GameCore 內部的依賴方向（2026-09 決定）

GameCore 裡的經營層（Passenger、City、Economy）不得依賴鐵路的物理層：

```
鐵路的物理層：軌道、預約、movement authority、dispatcher、行駛曲線（S1–S5、T、U、V、W）
        ↓ 只經過穩定的查詢
車站、線路、服務與停站：哪台車停在哪一站、服務的執行進度、線路的行程與班距
        ↓
乘客（Passenger）→ 經營（Economy）
        ↑
城市的需求（City）
```

- 乘客、城市與經營**不讀**這些：`TrackTraversal`、`TrackResource`、`TrackSpan`、`Train.reservation`、movement authority、`TrainMovement`、列車在邊上的位置與里程。
- 它們也**不改**：時刻表的執行進度、列車的移動或預約。
- 它們只透過這些取得資訊：車站與月台的身分、線路與服務的身分、停站的查詢（例如 `stationsStoppedAt(by:)`）、服務的執行進度，以及線路的行程與班距。
- 為什麼：V（誰先走、在哪裡交會）與 W（怎麼加減速）之後還會改變鐵路的物理層。守住這條規則，那些改變只會讓乘客「晚幾分鐘到」，不必重寫乘客、城市或經營的資料模型。
- 沒有事件匯流排（決策 13）：上下車等經營的規則在 `advance` 每個基本步長的固定階段裡執行，只讀上面的查詢，所以結果仍然 deterministic，存檔也不依賴處理順序。

## GameCore 模組

| 目錄 | 內容 |
| --- | --- |
| `World` | `GameWorld`（狀態協調點與指令入口）、`GridMap`、`GridPosition`、`MapTile` / `TileType`、`GameError` |
| `Geometry` | 整數世界座標（`WorldCoordinate`、`PlanPoint`、`PlanVector`）、軌道的曲線與取樣（`TrackCurve`、`TrackGeometry`）、整數運算（`FixedPoint`）（Stage S3，決策 28、29）；縱斷面、坡度與結構物（`TrackProfile`、`TrackGrade`、`TrackStructure`）與淨空（`TrackClearance`）（Stage S4，決策 30）；128 位元的整數運算（`WideInteger`，Stage W1，決策 33） |
| `Railway` | `TrackDirection` / `TrackConnections`、`Track`（唯讀快照）、軌道連通查詢（`connectedNeighbors(of:)`、`isConnected(_:to:)`，由地圖推導）、`Station` / `StationID`、`Train` / `TrainID`、`TrainPosition`（列車在鐵軌上的位置）、`TrainMovement`（rate、continuation 與移動 kernel）、路徑搜尋（`route(from:to:)`）、停站（`platforms(of:)`、`route(from:toStation:)`、`stationsStoppedAt(by:)`）、時刻表（`ScheduledStop`、`Train.timetable`、`Train.timetablePeriod`）、時刻表服務（`TimetableExecution`、`Train.execution`）、服務線路（`ServiceLine`、`ServiceDay`、`TargetHeadways`、`lineJourney(_:)` 等推導查詢）、自動派車（`assignTrain(_:to:)`、`advance(ticks:)` 的派車階段）、鐵路圖（`TrackNodeID`、`TrackEdgeID`、`TrackTraversal`、`TrackResource`）與連續路網（`RailwayNetwork`、路網上的列車與 renderer 查詢，Stage S3）、路網上的月台（`TrackPlatform`、`Station.trackPlatforms`）與 renderer 的唯讀快照（`RailwaySnapshot`、`TrackAlignment`，Stage S4）、服務路徑（`TrainPath`，Stage S5）、交通控制與進路預約（`Train.reservation`、`reservedResources(of:)`、`heldResources(of:)`、`trainHoldingRoute(of:)`，Stage T）；行駛曲線與車種性能（`RunningCurve`、`TrainPerformance`，Stage W1，決策 33）；停站時間的純計算（`StationDwell`，G1b，決策 35） |
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
- **Junction**：每一格鐵軌是一個互通節點。兩個出口是直線或彎道，三個是互通的 T 字，四個是互通的十字。四個出口不代表「交叉但不互通」的兩條鐵軌；這種交叉、道岔狀態與入口—出口配對目前都不支援。
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
  → 移植到目標語言的純邏輯組件（Unity：noEngineReferences 的 assembly；Godot：不依賴 Node 的類別）
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
- **送出 = 求路 + 提交，在同一次呼叫**：以按下按鈕當下選取的格子為目的地，先用 `route(from:to:)` 從列車**目前**的位置求路，再把結果原封不動交給 `setTrainContinuation`。兩步在同一個 main actor 同步方法裡、對同一份世界執行，中間沒有 `await`，game loop 無法插入，所以路徑不會過時，也只會交給求路的那台列車；依決策 16，GameCore 一定接受它。沒有路徑（不是鐵軌，或不折返到不了）時什麼都不改，列車保留原本的 continuation。UI 從不自己找路、截斷或修補路徑。App 的地圖固定 32 × 24，同步查詢最多走訪約 3,000 個狀態；將來地圖變大、要在背景求路時（決策 16），必須另外處理計算期間世界已經改變的情況。Stage N 起，選取的格子是車站時改用 `route(from:toStation:)`，送到該站最近的月台（決策 18）；其他格子照舊。
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
- **本 Stage 不做**：循環或每日重複的服務、自動折返或反向、複製服務、班距調整、乘客上下車、依時刻表控速、誤點追趕、列車碰撞、軌道佔用、月台容量、進路預約、movement authority、號誌、聯鎖、dispatcher 優先順序、真正的待避／越行決策，以及時刻表畫面（Stage R）。

### 21. 折返與重複的時刻表（Phase 4 Stage Q1）

Stage Q1 回答決策 20 留下的兩個問題：服務只跑一次，而且停在死路終點站的列車無法往回開（`route` 不會原地掉頭，決策 16）。它在時刻表加入兩項計畫資料，在執行進度加入一個計數。Stage I–P 的資料模型、指令與契約都沒有重寫。

- **為什麼這樣做**（[網頁參考研究](WEB_REFERENCE_STUDY.md)）：
  - 參考遊戲的高鐵模式用逐班的時刻表，並配對回程；地鐵模式的列車在交路終點折返，整天來回。
  - 本決策採用「在指定的停靠站折返」與「同一份時刻表週而復始」。
  - **不**採用「沒有路時自動掉頭」：這會改變決策 20「沒有路就等待、不反向」的規則，也可能讓被擋住的列車在錯誤的地方掉頭。
  - 也還不採用參考地鐵「由列車數推導班距」的做法，那屬於 Q2。
- **資料模型**
  - `ScheduledStop.reverses: Bool`（預設 `false`）：服務離開這一站時，先讓列車在原地折返，再求路到下一個停靠。位置的變換與 `reverseTrain` 相同。
  - `Train.timetablePeriod: Int64?`：`nil` 表示只跑一次，否則每 `period` 分鐘重複。
    - 時刻表仍只記錄第 0 輪的時刻。
    - 第 `k` 輪的時刻是記錄的時刻加上 `k × period`，由規則推導，不展開、不存檔。
  - `TimetableExecution` 的兩種狀態都加上 `cycle: Int64`（預設 0），表示目前在第幾輪。只跑一次的時刻表永遠是 0。
  - 週期放在列車上，而不是另一個「服務模式」物件：Q1 只讓一台列車重複自己的時刻表。多台列車共用的線路服務屬於 Q2，屆時由它設定每台列車的時刻表。
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
    - 如果連時刻放得下的最後一輪都已經過去，就從那一輪開始，也就是晚點出發。
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
  - 重複的時刻表如果所有停靠都在同一個車站（或共用的月台），而且列車晚點，連鎖可以一直繞下去。
  - 所以每台列車在一個出發段**最多離開時刻表站數那麼多站**：
    - 只跑一次的時刻表不受影響，它本來最多就離開這麼多站；
    - 重複的時刻表最多走一整輪，剩下的在下一步繼續。
  - 這樣 `advance` 一定會結束，「有改變就不快轉」的捷徑也仍然精確。
- **到達**照決策 20，帶著同一個 cycle。
- **核心規則不變**：每一輪都照決策 20 執行：不早於排定出發離開、不另加停留、每步最多移動一次、不跳站。晚點的列車也不跳過輪次，而是靠時刻表的餘裕追回（`TrainRepeatTests` 有逐分鐘的例子）。
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
  - 時段、班距與多台列車的線路服務屬於 Q2；交路與快慢車屬於 Q3。
  - 晚點超過一個週期的列車會照順序把每一輪跑完，不會取消班次。之後若需要取消落後的班次，再另外決定。
  - 停止服務後重新啟動，只能從第 0 站開始。
  - 列車之間仍然互不阻擋，要到 Phase 4.6 才處理。
- **本 Stage 不做**：自動折返、服務模式與線路（Q2）、交路與停站模式（Q3）、取消班次、時刻表畫面（Stage R）、車廠，以及佔用與進路（Phase 4.5、4.6）。

### 22. 服務線路：資料與推導（Phase 4 Stage Q2a）

Stage Q2 把網頁參考遊戲地鐵模式的營運方式移植過來：時段 × 上線列車數，班距由系統推導（[網頁參考研究](WEB_REFERENCE_STUDY.md)）。

和 Stage O、P 一樣拆成兩步：
- **Q2a（本決策）**：只建立線路的資料契約與推導查詢，線路不派車、不影響任何列車。
- **Q2b**：自動派車。

Stage I–Q1 的契約都不變。

- **移植的規則**（整數分鐘；「參考」指參考遊戲的做法）：
  - **時段**：參考把一天分成三個等級。尖峰 07:00–10:00 與 16:00–20:00；低峰 00:00–07:00 與 21:00 起；其他是離峰。
    - 這成為新世界的 `ServiceDay.standard`，存在世界裡，可以用 `setServiceDay` 改。
    - 研究文件列為「不採用」的是寫死在核心的時段，所以這裡讓它可以修改。
  - **營運時間**：參考預設 06:00 開始、24:00 結束，最晚可以到次日 06:00（`1800`）。開始時間之前的分鐘算作隔天的。這成為 `ServiceWindow`；新線路是 06:00–24:00，也可以全天營運。
  - **來回時間**：參考的公式是「各區間行駛時間 × 2 + 中間站停留 × 2 × (站數 − 2) + 終點停留 × 2」，停留是 36 秒與 42 秒。
    - 這裡的區間行駛時間由實際路徑推導：連結數 × 1024 ÷ 線路的 `rate`，無條件進位成整數分鐘。去程與回程分開求路，所以兩者可以不同。
    - 停留改成整數分鐘：中間站 1 分鐘，終點站 2 分鐘（多 1 分鐘給折返）。
  - **最多列車數**：參考的最短班距是 1.5 分鐘，並以二分搜尋找出「來回時間 ÷ 列車數 ≥ 最短班距」的最大列車數；來回時間連一台都不夠時是 1。
    - 這裡的最短班距取整數 2 分鐘，最多列車數化簡成 `max(1, 來回時間 / 2)`。`ReferenceWorld` 保留參考的二分搜尋寫法，交叉驗證兩者相同。
  - **實際列車數與班距**：一個等級實際跑的列車數是設定的數量，但不超過最多列車數。班距是 `來回時間 ÷ 列車數`，無條件進位；沒有列車就沒有班距。
- **資料模型**
  - `ServiceLine`（`LineID`，世界依序配發，刪除後不再使用）包含：
    - `name`；
    - `stops`：至少兩站，同一個車站不連續出現；
    - `rate`：至少 1，新線路是 1024，也就是每分鐘一個連結；
    - `window`；
    - `trainsInService`：各等級的列車數，不可為負。
  - `GameWorld.serviceDay`：所有線路共用，由一段一段組成，從分鐘 0 開始、嚴格遞增。
- **推導**：都不存檔，每次由地圖重新推導，與連通、路徑、停站一樣。
  - `serviceLevel(of:at:)`
  - `lineJourney(_:)`
  - `lineMaximumTrains(_:)`
  - `lineTrainsInService(_:at:)`
  - `lineHeadway(_:at:)`
- **行程（`lineJourney`）**
  - 參考遊戲的線路是一條幾何折線，但這裡的線路只是車站的順序，列車實際怎麼走要由地圖決定。
  - 所以行程的定義是「列車會怎麼開」：從第一站的月台出發，依序以 `route(from:toStation:)` 求路；到最後一站原地折返（決策 14 的反向），再依相反順序回到第一站。
  - 起點會試遍第一站的每個月台與四個朝向，取來回時間最短的，同樣短時取最先的。
  - 任何一段沒有路時沒有行程。之後的查詢也都沒有答案，而不是回傳 0。
- **為什麼折返是固定的**：去回兩端一律原地折返，這是網頁參考非環狀線的行為。環狀線（不折返、繞一圈）留到之後。
- **指令**：都免費。
  - `createLine(named:stops:)` 的檢查順序：`invalidName` → `invalidLineStops` → `unknownStation`（第一個不存在的車站）→ `idsExhausted`。
  - `removeLine`、`setLineStops`、`setLineRate`、`setLineServiceWindow`、`setLineTrainsInService` 先檢查 `unknownLine`，再檢查自己的值。
  - `setServiceDay` 只會丟出 `invalidServiceDay`。
  - 設定的列車數照原樣保存，即使超過最多列車數，所以之後地圖變動讓行程變長時，設定仍然有效。
- **存檔**
  - 只在有值時寫入：
    - `"lines"`：有線路時；
    - `"nextLineID"`：建立過線路時（即使全部刪除了，也要記住，避免 ID 重複使用）；
    - `"serviceDay"`：不是標準的服務日時。
  - 因此沒有線路的世界，存檔與之前逐位元相同；舊存檔讀成沒有線路、ID 從 1 開始、標準的服務日。
  - 一律拒絕：明確的 `null`，以及不合法的線路、營運時間、列車數或服務日。
  - 世界解碼另外確認：線路 ID 唯一、遞增、小於 `nextLineID`；名稱合法；每一站都存在。
- **Golden scenarios**：schema v11 新增：
  - 7 個指令、6 個結果、5 個觀察；
  - 最終狀態必填的 `lines` 與 `serviceDay`；
  - `service-line.json`。

  既有的 10 個 fixture 只加上 `"lines": []` 與標準的服務日。
- **驗證**
  - `ServiceLineTests` 以手算的預期值驗證指令、服務等級、行程（包括「最先的起點不是最短時，選最短的」）、列車數、班距與存檔。
  - `ServiceLinePropertyTests`（`line.differential`）讓產生的指令序列同時在 GameCore 與 `ReferenceWorld` 上執行：
    - 指令是鋪軌、拆軌與列車操作，混合線路指令，其中刻意包含不合法的值；
    - 每一步比較所有線路的等級、行程、列車數與班距；
    - `ReferenceWorld` 另外寫成：營運時間分成一段或兩段檢查，時段從頭掃描，每段分鐘數用 `(單位 − 1) / rate + 1` 計算，最多列車數用參考的二分搜尋。
  - Stage I–Q1 的 property digest 在修改前後相同。
- **GamePresentation**：只為六個新錯誤加上 `playerMessage`。App 沒有修改，線路畫面屬於 Stage R。
- **已知限制**
  - 環狀線還沒有做；交路與快車在 Q3 加入（決策 24）。
  - 平日與週末不分，也沒有日曆。
  - 行程是規劃值：實際列車的 rate 可能不同，晚點由 Stage P 的規則吸收。
  - 行程查詢每次要求路最多 16 × 2 ×（站數 − 1）次；還沒有快取，畫面若頻繁詢問，之後量測後再考慮。
  - **最多列車數假設上下行互不干擾**，等於把線路當成雙線：只要間隔 2 分鐘，就能一直發車。單線區段的列車只能在交會站錯車，實際能跑的列車會比這個值少。目前列車互不阻擋，所以和現在的規則一致；Phase 4.5、4.6 加入佔用、進路與交會時，要一併修正這個上限（真實時刻表的研究見 [TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）。
- **本 Stage 不做**：派車、把列車指派給線路、依時段增減列車、到終點才退出（Q2b），以及線路畫面（Stage R）。

### 23. 自動派車與目標班距（Phase 4 Stage Q2b）

Stage Q2b 讓決策 22 的線路真正跑起來：線路把指派給它的列車，一趟一趟地從第一站派出去。每一趟都是決策 20、21 的一般服務，所以執行、晚點、折返與存檔的規則都不變；本決策只加入「誰、何時、帶著什麼時刻表出發」。

- **為什麼這樣做**
  - [網頁參考研究](WEB_REFERENCE_STUDY.md)的地鐵模式（已對原始碼確認）：時段改變時重新計算上線列車數。
    - 減車：多出的列車標記為「到終點站後退出」，跑到下一個終點（兩端皆可）就移除；之後又要增車時，先取消這些標記。
    - 增車：新車直接出現在線上最大的空檔，不是從車廠開出。
    - 這裡的列車是買來、實體放在鐵軌上的（決策 14），不能憑空出現或消失，所以改成：減車時列車跑完這一趟、回到第一站停下；增車時只派已經停在第一站的列車（研究文件列為「不採用」的就是憑空出現）。
  - [真實時刻表研究](TIMETABLE_DATA_STUDY.md)：真實路線通常先定班距（例如每小時一班），多出來的時間讓列車在終點站等；支線的班距比幹線長很多。只用「列車數推導班距」表達不了「1 台車、來回 45 分鐘、每小時一班」。所以兩種方式都支援：預設用列車數，各等級可以另外設定目標班距。
  - 派出的每一趟都是有限、具體的時刻表，由 Stage P 的核心執行，符合 Stage Q 的方針：服務模式產生班次，交給既有的執行核心。
- **資料模型**（都在 `ServiceLine` 上）
  - `targetHeadways: TargetHeadways`：各等級的目標班距（分鐘），`nil` 表示該等級用 `trainsInService` 的列車數。目標是 2…1440 分鐘。
  - `trains: [TrainID]`：指派給線路的列車，依 ID 遞增。一台列車最多屬於一條線路。
  - `lastDispatch: GameTime?`：上次從第一站派車的時刻。
- **每個等級跑幾台、班距多少**（`lineTrainsInService`、`lineHeadway` 一併更新）
  - 沒有目標：列車數是設定值，但不超過最多列車數；班距是 `來回時間 ÷ 列車數`，無條件進位（與決策 22 相同）。
  - 有目標 `H`：列車數是 `來回時間 ÷ H` 無條件進位，也不超過最多列車數；班距是 `H`，但若列車數被最多列車數截斷，就取 `來回時間 ÷ 列車數`（無條件進位）與 `H` 較長的一個。
  - 例：來回 12 分鐘，目標 20 → 1 台，每 20 分鐘一班，列車在第一站等 8 分鐘；目標 5 → 3 台，每 5 分鐘一班。
- **指令**（都免費，失敗時世界不變）
  - `setLineTargetHeadways(_:to:)`：`unknownLine` → `invalidHeadway`。
  - `assignTrain(_:to:)`：`unknownTrain` → `unknownLine` → `trainOnLine`（已經屬於某條線路，包括同一條）→ `trainServiceActive`（正在跑自己的服務，要先停止）。列車放置與否、在哪裡都可以；只有停在第一站的列車才會被派出。指派本身只改變線路的列車清單。
  - `unassignTrain(_:)`：`unknownTrain` → `trainNotOnLine`。只結束指派：正在跑的這一趟保留時刻表，繼續當一般服務跑完，之後可以像一般服務一樣停止。
  - `removeLine` 同樣只結束指派，列車跑完這一趟。
  - **線路擁有列車的時刻表與服務**：屬於線路的列車，`setTrainTimetable`、`startTrainService`、`stopTrainService` 在 `unknownTrain` 之後丟出 `trainOnLine`，早於原本的其他檢查。閒置時仍可手動移動、反向、取下、放置與設定 rate，玩家才能把列車開到第一站。
- **一個基本步長**：決策 20 的四段之前加上第 0 段 **派車**，依 `LineID` 遞增處理每條線路，每條線路每步最多派一台。線路在 `T` 派車的條件：
  1. `T` 是分鐘 0 以後（時刻表的時間不能是負數）；
  2. 營運時間內，行程可以行駛，而且 `T` 的等級有列車要跑；
  3. 距上次派車已經過了該等級的班距（`上次 + 班距 <= T`）；
  4. 線路的列車中，正在跑服務的少於該等級的列車數；
  5. 有一台**就緒**的列車：沒有服務、已放置、rate 大於 0、停在第一站的車站（決策 18），而且從那裡能開完整個來回。依 ID 取第一台。
- **派出的一趟**
  - 時刻表從列車實際的位置推導，而不是線路的規劃起點：列車照原本朝向，或先原地折返，取來回時間較短的（相同時不折返）；兩種都開不完就不就緒。需要折返時，第一站標記 `reverses`。
  - 時刻：第一站 `T` 到、`T` 離；之後每一站在前一站離開後加上該段的分鐘數到達（線路的 rate，決策 22 的算法）；中間站停 1 分鐘，最後一站停 2 分鐘並折返；回到第一站時到達、折返，服務就此結束，列車在原地等下一次派車。準點的列車在 `T + 來回時間` 時已可再出發（第一站的 2 分鐘終點停留在等待中度過）。
  - 設定時刻表（不重複）與 `.waitingAtStop(0)`，記錄 `lastDispatch = T`，列車在同一步的第 1 段就出發。時刻超出 `Int64` 時不派車。
  - 所以：減車時，回到第一站的列車因為條件 4 不再被派出，就停在那裡（「到終點站後退出」）；增車時只有停在第一站的列車能出發；晚回來的列車讓下一班晚發，但永遠不會早發。
- **事件感知的快轉**：一步沒有任何改變時，時鐘可以跳到下一個出發時刻，或下一個「有就緒列車的線路可能派車」的分鐘，取較早的。後者是：若現在就符合條件就是現在；否則是分鐘 0、`上次 + 班距`、營運時間開或關、服務日換段這幾個時刻中最早的。列車只能因為到達或服務結束才變成就緒，而這兩者都算「有改變」；營運時間、等級與班距只在這些時刻改變。所以仍然精確：`advance(n)` 等於 n 次 `advance(1)`，2× 的一個 tick 等於 1× 的兩個 tick。
- **每次呼叫只算一次**：同一次 `advance` 中沒有指令，地圖、線路的站與 rate、閒置列車的位置都不變，所以每條線路的行程、每台閒置列車的一趟各只求一次（精確的最佳化）。
- **存檔**：只在用到時寫入 `"targetHeadways"`（只列出有目標的等級）、`"trains"`、`"lastDispatch"`，所以沒有用到的線路存檔與之前逐位元相同，舊存檔讀成沒有目標、沒有列車、從未派車。一律拒絕：明確的 `null`、超出範圍的目標、沒有遞增或重複的列車、分鐘 0 以前的派車。世界解碼另外確認：列車存在、不屬於兩條線路、線路的列車不在跑重複的時刻表、上次派車不晚於現在。
- **Golden scenarios**：schema v12 新增 3 個指令、3 個結果、線路必填的 `targetHeadways`、`trains`、`lastDispatch`，以及手算的 `line-dispatch.json`。既有的 11 個 fixture 只把版本改成 12，`service-line.json` 的兩條線路加上中性的值（沒有目標、沒有列車、從未派車）。
- **驗證**
  - `LineDispatchTests` 以手算的預期值驗證：指令與錯誤順序、目標班距的列車數與班距、兩台列車每 6 分鐘一班地來回、朝錯方向的列車先折返、只有就緒的列車會出發、等級改變時的增減車、目標班距讓列車在第一站等待、營運時間與分鐘 0、取回列車與刪除線路、長批次等於逐 tick，以及存檔。
  - `LineDispatchPropertyTests`（`line.dispatch`）讓產生的指令序列同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，並檢查批次與逐 tick、2× 與 1× 相同。`ReferenceWorld` 另外寫成：目標存成以等級為 key 的字典，班距用「現在 − 上次派車」檢查，每分鐘都檢查派車，沒有快轉。
  - `SaveMutationTests` 新增 `save.dispatchMutation`。
  - Stage I–Q2a 的 property digest 在修改前後相同。
- **GamePresentation**：只為三個新錯誤加上 `playerMessage`。App 沒有修改，線路畫面屬於 Stage R。
- **已知限制**
  - 列車之間仍然互不阻擋（Phase 4.6）；同一條線路的列車可能在同一段鐵軌上重疊。
  - 最多列車數仍然假設雙線（見決策 22 的已知限制）。
  - 只從第一站派車；停在最後一站的列車不會從那裡出發。
  - 派車時只看列車停在第一站的哪個月台、朝哪個方向，不會把列車開到規劃的起點。
  - 不設定列車的 rate：rate 為 0 的列車不會被派出，rate 與線路不同的列車會提早或晚點。
  - 平日與週末不分，也沒有日曆。
- **本 Stage 不做**：交路與快慢車（Q3）、從最後一站派車、依乘客調整班次，以及線路畫面（Stage R）。

### 24. 交路與停站模式（Phase 4 Stage Q3）

Stage Q3 讓一條線路除了自己的全線站站停服務之外，還能跑其他的**服務模式**（`LinePattern`）：只跑一段的交路（短程折返），或跳過部分車站的快車。每個模式有自己的列車數或目標班距、自己的列車與派車紀錄，照決策 23 的規則派車。多個服務共用同一段鐵軌時，班次相加後仍要守住最短班距。

- **為什麼這樣做**
  - [網頁參考研究](WEB_REFERENCE_STUDY.md)的地鐵模式（已對原始碼確認）：
    - 一條線可以有多個交路，各有起訖站與各時段的列車數；各交路的班距由它自己的來回時間推導。
    - 交路重疊的區段把各自的頻率（列車數 ÷ 來回時間）相加，總和不能超過最短班距的頻率；依序處理，後面的交路被削減。
    - 快車是從整條線依序挑出的停靠站，至少 2 站，有自己的列車數。
  - 參考遊戲裡快慢車「擁有獨立路權」，快車不和慢車一起算容量。我們的快車和慢車實際共用同一條鐵軌，所以快車也算進它經過的每一段，即使它不停那些站。
  - [真實時刻表研究](TIMETABLE_DATA_STUDY.md)：真實路線同一條線上有區間車與區間快、自強號，快車停靠的是慢車停靠站的子集合。
  - 參考遊戲的交路**取代**預設的全線交路，所以要求所有交路連續覆蓋整條線。這裡線路自己的服務永遠存在、跨越全線，結構上一定覆蓋；可能沒有列車的是某個等級的某一段（例如深夜只跑中間一段的交路），所以改成推導的查詢：某等級負載為 0 的區段就是沒有覆蓋，交給玩家判斷，而不是拒絕指令。
- **資料模型**
  - `ServiceLine.patterns: [LinePattern]`，順序就是分配容量的順序（線路自己的服務永遠在最前面）。
  - `LinePattern`：
    - `calls: [Int]`：停靠的站，是線路 `stops` 的索引，至少 2 個、嚴格遞增。連續的索引是交路，跳過的索引是快車通過的站；「交路」或「快車」只是從 `calls` 看出來的。
    - `trainsInService`、`targetHeadways`、`trains`、`lastDispatch`：和線路自己的服務相同的意義（決策 22、23）。
  - 模式以索引識別；刪除一個模式時，後面的模式往前移一格。
- **行程**
  - 模式的行程從第一個停靠站的月台出發，依 `calls` 求路到下一個停靠站，在最後一個停靠站折返，再依相反順序回來。和決策 22 相同：起點是每個月台朝四個方向，取來回最短的。
  - 快車到下一個停靠站的路是最短路，不刻意經過跳過的車站。
  - `LineLeg.from`、`to` 仍是線路 `stops` 的索引。
  - 停留：中間的停靠站 1 分鐘，兩端各 2 分鐘；跳過的車站不停。
- **容量**（`lineTrainsInService`、`lineHeadway` 一併更新）
  - 區段 `i` 是線路第 `i` 站到第 `i + 1` 站。每段每天每個方向最多 `segmentCapacity = 1440 ÷ 2 = 720` 班，也就是最短班距 2 分鐘。
  - 一個服務在它從第一個停靠站到最後一個停靠站之間的每一段（停不停都算），加上**負載** `⌈1440 ÷ 班距⌉`：以它的班距跑一整天的班次，無條件進位，所以不會低估。
  - 各服務依序取得容量：線路自己的服務、模式 0、模式 1……。每個服務先照決策 23 算出它單獨時的列車數；然後在不超過這個數字的前提下，取負載在它經過的每一段都放得下（加上前面服務的負載不超過 720）的最多列車數。少一台列車負載不會變大，所以用二分搜尋。放不下任何一台時，這個等級不跑。
  - 列車數減少時，班距照決策 23 重算：`max(目標, ⌈來回 ÷ 列車數⌉)`。
  - 線路自己的服務排第一，而且單獨時的負載一定不超過 720（它的列車數不超過 `來回 ÷ 2`，而來回至少 4 分鐘），所以永遠不會被削減。沒有模式的線路，行為和 Q2 完全相同。
  - 行程無法行駛的服務不跑，也不佔容量。
  - 以整數的每日班數表示頻率，比參考遊戲的浮點數頻率（加上 1e-9 的誤差容許）精確，而且 1440 的因數多，常見的班距剛好整除。
- **指令**（都免費，失敗時世界不變）
  - `addLinePattern(_:calling:)`：`unknownLine` → `invalidLinePattern`（少於 2 個、沒有嚴格遞增、或不是線路的站的索引）。加在最後，沒有列車數、目標與列車；回傳索引。
  - `removeLinePattern(_:at:)`：`unknownLine` → `unknownLinePattern`。它的列車不再屬於線路；正在跑的這一趟繼續當一般服務跑完，和 `removeLine` 相同。
  - `setLineTrainsInService(_:to:pattern:)`、`setLineTargetHeadways(_:to:pattern:)`、`assignTrain(_:to:pattern:)`：`pattern` 為 `nil` 時是線路自己的服務（原本的行為）。錯誤順序在 `unknownLine` 之後插入 `unknownLinePattern`。
  - `setLineStops`：模式保留原本的索引；新的站數讓某個模式超出最後一站時，在原本的檢查之後丟出 `invalidLinePattern`。
  - 一台列車最多屬於一個服務（任何線路的任何服務）；`unassignTrain` 從它所在的服務移除。`assignedLine(of:)` 也找模式，`assignedPattern(of:)` 回傳模式的索引。
- **派車**：決策 23 的第 0 段依 `LineID` 遞增，每條線路依序處理自己的服務、模式 0、模式 1……，每個服務每步最多派一台。條件和決策 23 相同，只是換成該服務的列車數與班距（已經扣掉前面服務的容量）、該服務的列車、該服務的上次派車，以及停在**第一個停靠站**的列車。派出的時刻表只列出停靠的車站。快轉的喚醒時刻也逐一服務計算；前面服務的列車數只在營運時間與服務日換段時改變，所以仍然精確。
- **查詢**：`lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway` 加上 `pattern` 參數；新增 `lineSegmentLoads(_:at:)`，回傳該等級每一段的負載（為 0 就是沒有覆蓋）。
- **存檔**：線路只在有模式時寫入 `"patterns"`，模式只在用到時寫入 `"targetHeadways"`、`"trains"`、`"lastDispatch"`，所以沒有模式的存檔與之前逐位元相同。一律拒絕：明確的 `null`、不合規則的 `calls`（包括超出線路站數）、負的列車數、超出範圍的目標、沒有遞增或重複的列車、分鐘 0 以前的派車。世界解碼另外確認：列車存在、不屬於兩個服務、不在跑重複的時刻表、上次派車不晚於現在。
- **Golden scenarios**：schema v13 新增 `addLinePattern`、`removeLinePattern`，`setLineTrainsInService`、`setLineTargetHeadways`、`assignTrain` 與四個線路觀察可以加上 `"pattern"`（沒有這個 key 就是線路自己的服務），新增 `lineSegmentLoads` 觀察、`invalidLinePattern` 與 `unknownLinePattern` 結果，線路必填 `"patterns"`，以及手算的 `line-patterns.json`。既有的 12 個 fixture 只把版本改成 13，兩個有線路的 fixture 加上中性的 `"patterns": []`。
- **驗證**
  - `LinePatternTests` 以手算的預期值驗證：指令與錯誤順序、`setLineStops` 保留或拒絕、刪除模式、交路與快車的行程、各段依序分配容量（尖峰時交路被削到 2 台、快車沒有位置；深夜只覆蓋中間一段）、線路自己的服務不會被削減、無法行駛的模式不佔容量、交路與快車的派車（快車等到離峰才出發，時刻表只有兩端）、批次等於逐 tick，以及存檔與拒絕。
  - `LinePatternPropertyTests`（`line.patterns`）讓產生的指令序列同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，以及每條線路每個服務的行程、列車數、班距與各段負載。`ReferenceWorld` 另外寫成：每一段都把前面服務的負載重新加總，列車數從單獨時的數字往下數，而不是二分搜尋。
  - `SaveMutationTests` 新增 `save.patternMutation`。
  - Stage I–Q2b 的 property digest 在修改前後相同。
- **GamePresentation**：只為兩個新錯誤加上 `playerMessage`。App 沒有修改，線路畫面屬於 Stage R。
- **已知限制**
  - 列車之間仍然互不阻擋（Phase 4.6）：快車會「穿過」同一段上的慢車，真正的待避與越行屬於 Stage V。
  - 容量只在同一條線路的服務之間分配；不同線路共用鐵軌時不互相限制，要等 Phase 4.5 的軌道資源。
  - 最多列車數與每段容量仍然假設雙線（決策 22 的已知限制）。
  - 快車到下一個停靠站走最短路，不保證經過跳過的車站。
- **本 Stage 不做**：支線、環線、跨線直通、同一線路快慢車之間的轉乘（乘客屬於 Phase 5），以及線路畫面（Stage R）。

### 25. 服務與時刻表畫面（Phase 4 Stage R）

Stage R 讓玩家在 App 裡看到並操作 Stage O–Q3 的時刻表、服務與線路。GameCore 沒有修改。

- **分層**（沿用決策 1、7、17）
  - 顯示的文字與推導（班距的說法、服務的種類、覆蓋缺口、列車的早到或誤點）放在 GamePresentation，只讀 `GameWorld` 的公開查詢，可以在 Linux 上測試。
  - `GameSession` 的新指令（建立與刪除線路、各等級的列車數與目標班距、營運時間、新增與刪除服務模式、指派與取回列車、啟動與停止自己的時刻表）每個只呼叫一個 `GameWorld` 指令；拒絕時顯示 `GameError.playerMessage`，世界不變。
  - 畫面只保存暫時的 UI 狀態：選定的線路 ID、新線路的車站草稿、sheet 是否開啟、新模式的兩端。線路、列車數與時刻都每次從世界讀取。
- **早到與誤點**（推導，不存檔）：停在某站時，超過該站排定出發就是晚點（分鐘數 = 現在 − 排定出發），還沒到排定到達就已經在站上是早到；行駛中超過下一站的排定到達就是晚點。排定時刻包含重複時刻表的輪次。列車不會早於排定出發離開（決策 20），所以行駛中不會早到。Stage W2b 起改由 GameCore 的 `lateness(of:)` 依實際時刻計算（決策 39），畫面只把秒換成整分鐘。
- **服務的種類**從 `calls` 推導：停靠每一站是「All stops」，連續但沒有涵蓋全線是「Short working」，有跳過的站是「Express」，並列出通過的站。
- **細節分級**：每格小於 20 點時只畫鐵軌線、車站標記與列車（`MapScale.detail(forTileSize:)`），減少縮小時的繪圖量與雜訊。只影響呈現，模擬結果與裝置無關（網頁參考研究的結論 4）。
- **App**：HUD 的「Lines」按鈕開啟線路面板（半高 sheet，地圖仍可點選車站）；列車工具顯示所屬服務、下一站與準點狀態。新增的檔案以 XcodeGen 重新產生專案。
- **驗證**：`LineSessionTests` 以手算的文字與世界比較驗證推導與每個 session 指令；`MapScaleTests` 驗證細節分級。SwiftUI 畫面只能在 macOS CI（`ios-build.yml`）編譯與建置，無法在 Linux 驗證。
- **留給之後**：逐站編輯時刻表的畫面、班次預覽的時刻列表、拖曳時隱藏覆蓋層。

### 26. 軌道資源：道岔、平面交叉、佔用、區段與股道數（Phase 4.5 Stage S1）

Stage S1 讓鐵軌成為列車可以佔用的資源，並補上真實道岔的轉向規則。概念參考真實時刻表研究的「實體鐵路層」（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）：路網由節點與邊組成、道岔不能從一支線倒車轉進另一支線、平面交叉只能直行、每段邊是一個資源、單雙線由平行的正線判定。

- **新的鐵軌種類**（`TileType` 新增兩個 case，`TrackLayout` 描述轉向規則）
  - `turnout(connections:stem:)`：三個以上的出口，其中一個是 `stem`。從 stem 可以走到任一支線，從支線只能走到 stem，支線之間不互通。四個出口時是三向道岔。
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
- **區段**：`trackSections()`。區段是兩個分岔點之間的一串連結，內部的格都是只接兩格的一般鐵軌；分岔點是道岔、平面交叉，或相接格數不是 2 的一般鐵軌（包括端點）。每條連結恰好屬於一個區段。沒有分岔點的環狀線是一個 `isLoop` 的區段。順序見 API 文件，只由地圖決定。
- **股道數**：`parallelTracks(between:and:)` 是兩站月台之間不共用任何連結的路徑最多幾條（最大流，每條連結容量 1），忽略轉向規則與列車：0 是不相連，1 是單線，2 以上是雙線或更多。`lineTrackCounts(_:)` 回傳線路相鄰兩站之間的股道數，Stage V 修正線路容量時使用（決策 22 的已知限制）。
- **存檔**：`TileType` 的新 case 以既有的方式編碼（`{"turnout": {"connections", "stem"}}`、`{"crossing": {}}`），沒有新種類的存檔逐位元不變。地圖解碼拒絕不合規則的道岔。
- **Golden scenarios**：schema v14 新增 `buildTurnout`、`buildCrossing` 指令，`exits`、`occupancy`、`conflicts`、`trackSections`、`parallelTracks` 觀察，最終狀態的鐵軌必填 `layout`，以及手算的 `track-resources.json`。既有的 13 個 fixture 把版本改成 14，85 條鐵軌加上中性的 `"layout": { "type": "open" }`。
- **驗證**
  - `TrackResourceTests` 以手算的預期值驗證：建造的錯誤順序與費用、道岔與平面交叉的轉向、路徑與 continuation、改成道岔後停在道岔等待的列車、佔用與衝突、區段（包括環狀線）、股道數，以及存檔與拒絕。
  - `TrackResourcePropertyTests`（`track.resources`）：把產生的路網中的分岔隨機改成道岔或平面交叉，讓列車穿過它們，同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，以及每格每個方向的出口、佔用、衝突、區段與每對車站的股道數。`ReferenceWorld` 另外寫成：轉向規則是允許的（進、出）配對表，區段由連結的 union-find 得到，股道數用深度優先的增廣路徑。另外檢查每條連結恰好在一個區段、區段內部都是一般鐵軌。
  - `SaveMutationTests` 新增 `save.trackMutation`。
  - 刻意把道岔改成支線互通時，campaign 在前幾個 case 就失敗（驗證後還原）。
  - Stage I–Q3 的 property digest 在修改前後相同。
- **GamePresentation / App**：格子說明加上道岔與平面交叉；地圖畫出道岔（在 stem 那一側加一條橫槓）與平面交叉（中央一個方塊，兩條直線不相接）。建造道岔的畫面留待之後。
- **本 Stage 不做**：阻擋、進路預約與 movement authority（Phase 4.6）、列車長度與月台（S2）、依股道數修正線路容量（Stage V）、建造道岔與平面交叉的畫面。

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
  - 長度是整數個連結，所以停在節點的列車原地反向後仍然停在節點。這是刻意的選擇：如果每節只有半格，奇數節的列車反向後車頭會落在兩格之間，就不能停站，線路也無法再派出它。
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
  - 服務與線路的出發、線路的行程估算（`trip`）都使用長度：長列車折返時車頭移到車尾，並沿月台延伸。行程估算從停在月台的列車開始，每一段都從節點出發。
  - 月台比列車短時，長列車在線路第一站折返後車頭會離開月台，線路就不會再派出它。玩家要把車站加長，這也是月台長度在遊戲中的意義。
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
    - 線路派出長列車；
    - 存檔與拒絕。
  - `StationFacilityPropertyTests`（`station.facilities`）：長站、設定節數、放置、送往車站、反向、移動、取下重設、在車身下拆軌，以及派出長列車的線路，同時在 GameCore 與 `ReferenceWorld` 上執行，每步比較所有狀態，以及月台、月台股道、停站、整列停站與佔用。`ReferenceWorld` 另外寫成：車身是帶著與車頭距離的點列，裁切時逐點走距離；反向時沿點列找車尾；延伸時逐格累加；月台股道用標籤擴散求得。
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

產品方向是「以 deterministic 模擬核心為基礎的 360° 3D 鐵道城市建造遊戲」：任意方向的鐵軌、平滑曲線、真正的道岔、高架、地下與立體交叉，列車沿著 3D 鐵軌連續行駛。Stage I–S2 的鐵路是方格：節點是格子、連結是相鄰兩格、方向是北東南西，這三件事綁在一起。從 Stage S3 起把它們拆成三層，每一層只依賴下面那一層：

| 層 | 內容 | 權威資料 | 誰可以讀 |
| --- | --- | --- | --- |
| **Topology** | 節點與邊的身分、相接、節點上允許的轉向（道岔、平面交叉）、路徑搜尋、佔用與預約的資源身分、月台的綁定點 | GameCore（`TrackNodeID`、`TrackEdgeID`、`TrackTraversal`、`TrackResource`） | 路徑、移動、佔用；之後的 T 進路預約、U movement authority、V dispatcher |
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
- `RailwayNetwork`：所有鐵軌。方格時代的鐵軌是錨定在格上的節點（`TrackNodeID.tile(p)`，保存它的出口與配置：一般、道岔、平面交叉），連續路網是編號的節點與邊。兩者都只存在這裡。
- 車站、列車、線路照舊。

**S3A-2. 舊存檔何時轉成 `RailwayNetwork`？轉換點在哪裡？** 只有兩個轉換點，都是單向的：

- 讀檔：`GameWorld` 的解碼器讀入存檔的 `map.tiles`，土地放進 `GridMap`，鐵軌格變成 `RailwayNetwork` 的方格節點。之後執行期的 `GridMap` 裡沒有鐵路。
- 存檔：`GameWorld` 的編碼器把 `GridMap` 的土地與 `RailwayNetwork` 的方格節點合成存檔裡的 `map.tiles`（相容的序列化格式），所以只有方格的存檔逐位元不變。這是由權威資料推導出的投影，不是第二份資料。

**S3A-3. 指令修改哪一份資料？** 鋪軌、道岔、平面交叉、拆軌（方格的舊指令）與建造、拆除節點和邊（路網的指令）都只修改 `RailwayNetwork`；建站、車站長大只修改 `GridMap` 的土地與車站。「格上已經有東西」由兩者一起判斷：方格節點與車站不能在同一格（舊規則），連續路網不佔用任何格（見決策 30 的淨空）。

**S3A-4. 如何避免兩份資料不一致？** 型別上就不可能：`TileType` 沒有鐵路的 case，`GridMap` 無法表示鐵軌；存檔的鐵軌格只在解碼時讀一次、編碼時由網路產生。沒有任何雙向同步。

**S3A-5. 方格節點的身分。** 方格節點的 ID 是 `TrackNodeID.tile(p)`：錨點 `p` 是這個節點不變的名字（方格的鐵軌不會移動，一格最多一個方格節點）。泛用層（路徑、佔用、之後的 T/U/V）把 `TrackNodeID` 當成不透明的值，不讀格子、不讀北東南西；新的建造只產生 `TrackNodeID.node(n)`。

**S3A-6. 邊與資源的身分。**

- 邊（`TrackEdgeID`）是拓撲上的連接：兩端的節點、幾何與整數長度。方格的連結是 `.link(a, b)`，由兩個方格節點互相朝向對方的出口推導；路網的邊是 `.edge(n)`。
- 資源（`TrackResource`）是 `.node(TrackNodeID)` 或 `.span(TrackSpan)`。`TrackSpan` 是一條邊上的一段里程區間（邊、`start`、`end`）。
- **一條邊可以有很多個 span**：預設把邊等分成最少段、每段不超過 `RailwayNetwork.spanLength`（1024，一格）：段數 n = ⌈L ÷ 1024⌉，第 k 個分界在 ⌊k·L ÷ n⌋。方格的連結恰好是一個 span，所以 S1 的資源不變；一條 2 公里的邊是 125 個 span，第一台列車不會鎖住整條邊。
- 之後的分界可以來自道岔、平面交叉、月台端點（S4）、號誌與閉塞、營運區段；T 只要加分界，不必改幾何或邊。
- 佔用與預約只讀邊的整數里程與分界，不讀 renderer 的取樣：列車佔用它車頭到車尾之間經過或到達的節點，以及有一點嚴格落在區間內的 span。

**S3A-7. 路徑。** 路徑的成本是整數的長度總和（不是邊數），同長時依出口順序決定；結果是 `TrackTraversal` 的序列，不含控制點。方格上每條連結都是 1024，所以結果與舊的廣度優先搜尋相同。交通狀態、限速與道岔的額外成本留給 V/W。

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
S2 的月台（車站格旁的鐵軌格）照舊服務方格。S4 讓車站在路網上綁定月台：一條邊上的一段區間（邊、起訖距離、長度、層），整列車都在區間內才算停妥；層（level）留給 Phase 5F 的步行轉乘成本。S3 不做月台綁定，路網上的列車只能手動操作。（S5 之後路網上的列車也能停站、跑時刻表與線路，見決策 31。）

**9. 交叉與相接如何區分？**
- 只有**共用的節點**會相接。兩條邊在平面上交叉、但沒有共用節點，就不相接、不共用資源、路徑也不會從一條轉到另一條（S4 再決定這種交叉在同一高度是否允許，以及立體交叉的淨空）。
- 節點上哪兩個邊端可以通行，在建造與解碼時由邊端的切線推導一次，存成 topology：兩個邊端離開節點的方向相反、夾角誤差在 1:16（約 3.6°）以內才相通。道岔（一個邊端通往兩個以上）、菱形平面交叉（兩組互不相通的直行）與雙交分道岔都由此自然成立，不需要另外的道岔旗標，也不會因為拆掉某條邊而讓其他邊的設定失效。
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
- **路徑**：`TrainRoute.shortest` 是唯一的搜尋：先依距離（Dijkstra）找出最近的目的地距離，再倒著標出能以最短距離到達目的地的狀態，最後從起點每一步取第一個這樣的出口。結果只由規則決定：總長最短，同長時出口序列依各節點的順序逐步比較取最先。方格的每條連結都是 1024，所以與舊的廣度優先搜尋完全相同（`route.reference`、`stationStop.routes` 與所有服務、線路的 digest 不變）。`route(from:to:)` 對 `TrackNodeID` 回傳 `[TrackTraversal]`。
- **移動**：`TrainMovement.travel(along:offset:length:distance:edges:cursor:enter:)` 與方格的 kernel 規則相同，但每條邊用自己的長度；恰好走到終點停下、不看下一項；不可進入時停在終點等待。
- **車身**：放置時從車頭所在邊的起點往回走，分岔時選編號最小、能通往前一條邊的邊；移動時由路徑歷史裁切；反向時車頭移到車尾（`reversedOnNetwork`），車身沿同一段鐵軌往原車頭延伸。
- **佔用**：車頭到車尾之間經過或到達的每個節點，以及與列車有一個共同點、而且那一點不在邊的兩端的每個 span（`networkResources(of:)`）：碰到兩個 span 分界的列車同時佔用兩個。方格的連結只有一個 span，所以方格的結果不變。
- **S3A 查詢**：`trackSpans(of:)`（一條邊的 span，方格連結是一個）與 `pathAhead(of:)`（列車之後要進入的 `TrackTraversal`：方格是 continuation 中剩下的連結，不論現在是否鋪著；路網是剩下的邊，到第一條進不去的為止）。
- **存檔（S3A）**：`GameWorld` 的私有 `SavedMap` 在讀檔時把 `map.tiles` 分成土地（`GridMap`）與方格鐵軌（`RailwayNetwork`），存檔時再合成同樣的格式；鐵軌格的驗證（至少一個出口、道岔的規則）從 `GridMap` 移到這裡。`GameWorld` 的不變量另外確認方格的鐵軌只在地圖內的空地上。
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
  - 沒有共用節點的交叉、平面交叉、道岔、折角、平行的邊；
  - 方格的 adapter（道岔、平面交叉的轉向與 `exits(from:facing:)` 一致，路徑與 continuation 兩種寫法相同）；
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
- 路網上的列車還不能停站、跑時刻表或線路（S4 的月台綁定之後）。S5 已解決，見決策 31。
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
- 兩個豎曲線長度都是 0 時是固定坡度（高差 0 就是平坡）；大於 0 時那一端是平的，拋物線過渡到固定坡度。所以平坡、上坡、下坡與過渡（豎曲線）都是同一個公式的特例，就像 S3 的道岔由轉向規則自然成立。
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
- **共用節點附近**：在同一個節點相接的兩條邊（道岔的兩條支線、平行的邊）在節點附近本來就重疊（取樣點的四捨五入也會讓相切的支線在一開始重合）。所以對共用節點的兩條邊，離那個節點 `RailwayNetwork.junctionZone` = 1024（一格）以內的部分不檢查；更遠的地方照常檢查。這一格相當於道岔與它的限界範圍，之後由 T/U 的資源處理。
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
- 淨空只看中心線，不看軌道的寬度與側向間距；共用節點 1024 以內的道岔區由 T/U 的資源處理。
- 節點上的坡度變化不受限制（豎曲線是玩家的選擇）；坡度對行駛的影響與曲線限速屬於 Stage W。
- 路網上的月台只有資料與查詢；路網上的列車還不能跑服務或線路。S5 已解決，見決策 31。
- 橫向傾斜（cant）、橋墩、隧道壁、照明、真正的 3D renderer、建造畫面與地下模式都還沒有。

### 31. 路網上的營運（Phase 4.5 Stage S5）——設計決策

這一段是 S5 開工前的架構審查（review gate）。S5 是 S3、S4 的路網與 Phase 3–4 營運系統（N 停站、P 時刻表、Q1 折返與重複、Q2a 線路、Q2b 派車、Q3 交路與快車）之間的橋：路網上的列車要能停在 `TrackPlatform`，照時刻表到達、停留、出發、折返、重複，被線路自動派出，跑交路與快車，而且以整數的實際距離計算行程。S5 不做進路預約、movement authority、dispatcher 與行駛動態（T、U、V、W）。

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
| `lineMaximumTrains`、`lineTrainsInService`、`lineHeadway`、`lineSegmentLoads` | 經由上面的行程 | 路網上的線路一律沒有行程 |
| 路網的移動 kernel 與 `TrainMovement` | 路徑一定走到最後一條邊的終點 | 無法停在邊中段的月台 |
| `setTrainContinuation(_:along:)` | 同上 | 同上 |
| `GameSession.sendSelectedTrain`（Presentation） | 送往車站只用方格的路 | 路網上的列車一律「沒有路」 |
| 測試的 `WorldInvariants.serviceViolations`、`NetworkInvariants` | 用 `ahead(of:)`；「路網上的列車有服務」算違規 | 要一起泛化 |

`trainServiceStatus(of:)`、`lineServiceSummaries(_:)`、`lineStatusText(_:at:)` 與地圖的畫法只讀上面的查詢，本身不假設方格。

**1. 方格與路網共用一套營運語義嗎？** 是。分層與決策 20 相同，只把「路徑」泛化：

```
時刻表、線路（計畫）→ 執行進度（TimetableExecution）→ 服務路徑（TrainPath）→ 移動（TrainMovement）
```

- 時刻表的狀態機（`advance` 的五段、出發、停留、完成、重複、零距離到達、找不到路時等待）、線路的一趟（`LineTrip`）、行程（`drive`）、派車與服務模式都只有**一份**實作。沒有 `GridTimetableEngine` 與 `NetworkTimetableEngine`。
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

**3. 月台是停站的正式基礎。** 路網上的停站只看 `TrackPlatform`：以車站為目的地的路、到達、停站、整列停妥、派車的就緒與線路的行程都經由它。方格的月台（S2）完全不變。同一個車站可以同時有兩種月台；列車只用它所在那種鐵軌上的月台。

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
- 結果：服務與線路永遠不會把列車送到放不下它的月台；沒有夠長的月台就是沒有路（服務等待；列車不就緒，線路不派出）。
- `stationsStoppedAt(by:)` 仍然只看車頭，與方格相同：路徑走完、車頭在該站某個月台的範圍內。`stationsBesideWholeTrain(_:)` 另外要求整列車都在該站的**同一個**月台內（車身沒有跨到別的邊，車頭到車尾的里程區間在 `[start, end]` 內）。所以「車頭在月台、車尾在外」是停站但不是整列停妥，與 S2 相同；玩家把列車手動開到太短的月台時看得到這個差別。
- 方格不變：長列車到第一個月台後照 S2 沿月台延伸，月台太短時車尾在月台外，線路在第一站折返後不再派出它（決策 27）。S5 不偷偷改這個行為。

**6. 以車站為目的地。** `path(from:toStation:length:)`：

- 方格上的列車：`route(from:toStation:length:)` 的結果寫成 link 的 traversal，行為與以前完全相同。
- 路網上的列車：到該站某個夠長的月台的停車位置（第 4、5 點）的最短路（第 7、8 點）。
- 方格與路網不相接（S3 的限制），所以不假裝能跨越：方格上的列車只找方格的月台，路網上的列車只找 `TrackPlatform`。同一條線路或時刻表的每一段，只要在列車所在的鐵軌上找得到路即可。
- 找不到路時沿用決策 20、21：服務在原站等待，不瞬移、不改線、不丟掉時刻表、不先折返，之後的步長再試。

**7. 精確的行程距離。**

- 路網：車頭在 `(T₀, o₀)`、邊長 `L₀`，依序進入 `t₁ … t_k`，停在 `t_k` 的 `e`：
  - `k = 0`：`e − o₀`；
  - `k ≥ 1`：`(L₀ − o₀) + L(t₁) + … + L(t_{k−1}) + e`。
  - 例：目前的邊 A 還剩 8,300，中間的邊 B 長 21,470，最後在邊 C 的 3,200 停下，距離是 8,300 + 21,470 + 3,200 = 32,970，不是 3 × 1024。
- 方格：在連結上時先加 `1024 − offset`，再加每條連結 1024。行程的每一段都從節點出發，所以就是以前的 `route.count × 1024`。
- 一段的分鐘數是 ⌈距離 ÷ 線路的 rate⌉，以整數計算（`距離 / rate + (距離 % rate == 0 ? 0 : 1)`，rate ≥ 1，不會溢位）。各段與停留照舊以會回報溢位的加法累加，溢位時沒有行程。
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
- 線路行程的起點：先是方格的月台 × 北、東、南、西（S2 的順序），再是路網的月台依 `RailwayNetwork.platforms` 的順序（邊的編號、起點里程）× 前進、後退的兩個停車位置；取來回最短的，同樣短時取最先的。所以只有方格的世界與以前完全相同。
- 字典只用來查表，從不依它的順序走訪。

**9. LineJourney 的泛化。**

- `LineLeg` 改存 `path: TrainPath` 與 `minutes`（⌈`path.distance` ÷ rate⌉）。這是公開 API 的變更：舊的 `route` 改成由 path 推導的唯讀屬性（方格是每條 link 的終點，路網是空的）。`LineJourney.start` 仍是 `TrainPosition`，路網上是一個停車位置。
- `drive` 從 `TrainPlacement` 出發：每一段用 `path(from:toStation:length:)` 求路，走完後依第 1 點的 adapter 移動位置與車身；在最後一個停靠站原地折返。全線站站停、交路、快車、去程、終點折返與回程都是同一段程式。
- 多個候選月台與多條可能的路，由第 8 點決定。
- `ServiceLine` 的資料（站、rate、營運時間、各等級的列車數、目標班距、服務模式）與存檔格式都不變：線路是營運計畫，不是實體路徑。

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
- Q3：`calls` 仍是線路站的索引；快車沒有自己的路權；容量的算法不變；跳過的車站不會變成停站；快車走到下一個停靠站的最短路，不綁定實體路徑（之後由 V 深化）。

**15. 高架、地下、隧道。** 路徑、距離與停站只讀 topology 與水平里程（S3、S4），不因結構物分岔：隧道口、坡道與高架都是一般的邊。結構物只影響幾何、費用與之後的 W。

**16. 存檔。**

- 唯一新的存檔資料是移動的 `"end"`，只在有值時寫入。沒有它的存檔（包括所有舊存檔）讀成 `nil`，所以只有方格的存檔與 S3、S4 的路網存檔都逐位元不變。
- 一律拒絕：明確的 `null`、負數、和方格的 continuation 一起出現、有剩下的邊時為 0、沒有剩下的邊時在車頭後面（`Train` 的解碼），以及不小於最後一條邊的長度（那條邊還在時，`GameWorld` 的解碼）。
- `Train` 的解碼接受路網上有服務的列車。`execution`、`timetable` 與線路的格式都不變。
- 停車位置、停站、整列停妥與路徑的距離都由存檔的狀態推導，不存檔。

**17. 不變量與拆除月台。**

- 等待中的服務：列車依第 13 點停在該站（方格與路網同一條規則）。
- 行駛中的服務（路網）：路徑還沒走完，而且路徑的終點是目的地車站某個不比列車短的月台的停車位置。路徑還能沿剩下的邊走到最後時，檢查方向與位置；中間有被拆的邊時（ID 不重用，列車會一直在它之前等待），只檢查最後一條邊上那個月台的兩個停車位置之一。
- 為了讓這兩條在任何指令之後都成立，`removeTrackPlatform` 在 `invalidPlatform` 之後多一個拒絕：**有服務正在用這個月台**時，丟出 `trainServiceActive`（編號最小的那台列車）：
  - 等待中的服務，這一站是該月台的車站，車頭在這個月台上；
  - 行駛中的服務，目的地是該月台的車站，路徑的最後一條邊就是這個月台的邊（保守：同一條邊上同一站的其他月台也算）。
  - 要拆就先停止服務（線路的列車先取回）。沒有服務的列車不受影響，所以 S4 的行為與 `vertical.differential` 都不變。
- 其他：移動的 `end` 符合第 12 點；路徑的邊都曾經建過（S3）；線路與服務模式的指派不因鐵軌種類而不同。

**18. 舊行為與 property digest。** 方格經過 adapter 後得到完全相同的路、距離、狀態與存檔，所以預期 16 個 property digest 全部不變，包括 `network.differential` 與 `vertical.differential`（S3、S4 的 campaign 從不設定 `end`，也沒有服務）。實作後逐一確認；若有改變，逐項說明原因。

**19. 效能。** 服務的查詢只讀 topology、邊長與月台區間：

- 找路只走到最近的停車位置為止，與 S3 的路相同；
- 每次找路先把該站的停車位置依 traversal 整理一次（該站的月台數）；
- 停站的判定掃描一次月台清單，不取樣、不掃描地圖；
- 不建立全域快取，等有量測再決定。派車的快取照舊是每次 `advance` 呼叫一份。

**20. S5 不做。** 進路預約、movement authority、號誌、閉塞佔用的阻擋、dispatcher、交會、越行、月台分配的衝突處理（T、U、V），以及加減速、煞車曲線、牽引、坡度與曲線的速度影響、能耗（W）。列車之間照舊互不阻擋，可以佔用同一個資源、互相穿過。線路的 rate 仍是時刻表行程的固定速度。

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
- **線路**（`LineJourney.swift`）：`LineLeg(from:to:path:minutes:)`，`route` 是由 path 推導的唯讀屬性（方格是每條 link 的終點，路網是空的）；`journey(of:service:)` 的起點先是方格的月台 × 北、東、南、西，再是路網月台的兩個停車位置；`drive(_:calling:from:)` 從 `TrainPlacement` 出發，每段 ⌈`distance` ÷ rate⌉ 分鐘。`trip(of:service:for:)` 也從 `TrainPlacement` 出發。
- **存檔**：`TrainMovement` 的 `"end"`；`Train` 的解碼接受路網上的服務；`TimetableExecution.fits` 對兩種鐵軌用同一個「路走完」的判定；`GameWorld` 的解碼檢查 `end` 小於最後一條邊的長度，以及行駛中的服務的路停在下一站的停車位置（`pathEndsAtBerth`）。
- **效能**：本輪沒有做效能量測。找路只走到最近的停車位置，停站掃描一次月台清單，都不取樣、不掃描地圖，也沒有全域快取（第 19 點）；`service.network` 在 debug build 上跑 12,800 個操作約 4.4 分鐘，其中大部分是參考模型與逐步的整個狀態比較，不是效能數字。

#### 驗證

- `NetworkServiceTests`（手算，20 個；曲線長度以獨立的精確分數移植核對）：
  - 兩個方向的停車位置、精確距離、月台長度的篩選、同樣短時依邊的編號決定；
  - 路走完才停站、`end` 的檢查、整列停妥與車頭停站的差別；
  - 時刻表從月台到月台、誤點的列車到站後下一步就出發、沒有路時等待而且不折返、路恢復後出發、重複的時刻表來回並回到同一個位置；
  - 長列車進隧道到地下的彎曲月台再回來（整列在月台內，折返後車尾成為車頭，仍在同一個月台）、高架月台兩個方向都能停；
  - 線路的行程是精確距離、派車與再次派出、服務等級決定派出的列車數、月台太短時不派出、交路與快車、服務需要的月台不能拆、存讀。
- `ReferenceWorld`（`ReferenceNetworkService.swift` 等）另外寫一次決策 31，而且盡量寫得不同：月台沿列車所在的方向看、以車站為目的地的路用「到最近停車位置的距離」鬆弛到不動點再貪婪地走、停車位置由站的位置判定、每段之後的車身由整條走過的路讀出。
- `NetworkServicePropertyTests`（`service.network`，40 個 case × 4 個種子 × 80 個操作 = 12,800 個操作，digest `B5FBE91125ADA10C`）：產生多層的路網（直線、S 曲線、坡道、高架、隧道、支線）、長短不同的月台與 1 到 4 節的列車，執行時刻表（單次與重複、折返）、線路與服務模式、手動的路、拆建月台，同時在 GameCore 與 `ReferenceWorld` 上執行。每一步比較結果與整個狀態：位置、車身、路與 `end`、服務與時刻表、停站與整列停妥、到每一站的路與距離、每個服務的行程、各等級的列車數與班距、各線路的上次派車；並檢查不變量與存讀。量：出發 548、到達 219、折返 375、服務結束 113、下一輪 519、派車 55、服務模式派車 19、長列車在服務中移動 315、離開地面的移動 715、整列停妥 20,245、跨多條邊的路 5,936、被拒絕的拆月台 270、成功的拆月台 362。
- `SaveMutationTests` 新增 `save.networkServiceMutation`（10 個 case × 4 個種子，每個 30 次變異）：載入 503、拒絕 697、瞄準服務、路、線路與月台的變異 916、載入的路網服務 955、停在邊中段的路 1,197；載入的世界都保持不變量、可以存讀，之後的指令也保持一致。
- `WorldInvariants` 與 `NetworkInvariants` 泛化：路網上可以有服務；等待中的服務停在該站；行駛中的服務還有路，路停在下一站某個放得下列車的月台的停車位置；每個 `end` 都合法。
- Golden schema v18 與手算的 `network-service.json`（77 步：地面的 Harbour、彎道、隧道裡 1/32 的坡道與地下彎道上的 Deep；三節的 Mole 重複 Harbour → Deep → Harbour，去程 45,258（23 分鐘）、回程 47,306（24 分鐘）；線路 Tube 每 52 分鐘派出一節的 Shuttle），第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過；既有的 17 個 fixture 只把 `schemaVersion` 改成 18。
- 刻意植入的錯誤，各自單獨植入、驗證後完整還原（`git diff -- Sources` 為空）；四個都在 `service.network` 的第一個種子的前兩個 case 被抓到，手算測試與 golden 也都失敗：
  - 行程距離寫成 `邊數 × 1024`：case 0（距離 3072 對 14429）；
  - 後退方向的停車位置用錯月台端點（`L − end`）：case 0；
  - 停車位置不看列車長度：case 0（放不下的月台也找到路）；
  - 終點折返後車頭差一個列車長度：case 1（6193 對 8241，差 2048，三節列車的長度）。
- 舊行為：16 個 property digest（Stage I–S4，包括 `network.differential` 與 `vertical.differential`）在修改前後完全相同；所有既有的 golden 預期值不變。

#### GamePresentation / App

- 列車工具可以把路網上的列車送往車站：`path(from:toStation:length:)` 的結果原封不動交給 `setTrainContinuation(_:along:stoppingAt:)`；沒有路時說明原因（選的是一般的格、月台太短、車站在路網上沒有月台）。
- `Train.pathText` 以文字表示路網上的路（剩下幾條邊、停在最後一條的哪裡）。路網上的列車的停站、服務名稱、下一站、早到或誤點與線路狀態本來就只讀 GameCore 的查詢，新的測試確認它們在路網上也正確。
- 地圖在路網的鐵軌下方畫出車站的月台。
- Debug 的示範配置讓 Harbor 在環線上多一個月台、在環線上建 North Gate，線路 Circle 讓三節的 Loop 在兩站之間往返（每端折返）。它仍然從一般的新遊戲開始、付一般的費用；以原樣的 `DemoLayout.swift` 在 Linux 上編譯並模擬 240 分鐘，全程準時。

#### 已知限制與留給之後

- 方格與路網不相接：列車只找它所在那種鐵軌上的月台，一條線路或時刻表的每一段都要在同一種鐵軌上找得到路。
- 列車之間互不阻擋，可以佔用同一個資源、互相穿過；進路預約、movement authority、dispatcher（T、U、V）。線路的 rate 是固定速度，沒有加減速（W）。
- 行駛中的服務不重新求路：路中間的邊被拆時照移動規則等待（S3），直到服務停止。
- 拆月台的拒絕是保守的：行駛中的服務的路停在某條邊上時，同一條邊上同一站的其他月台也不能拆。
- `lineJourney` 仍是一節列車的行程（與方格相同）；每台列車的一趟用它自己的長度。
- 建造路網、月台與線路的畫面、spline 編輯器與 3D renderer 仍然沒有；示範配置用指令建造。

### 32. 進路預約（Phase 4.6 Stage T）——設計決策

這一段是 T 開工前的架構審查（review gate）。T 只做**進路預約**：一台列車開始使用一條已經決定好的路（`TrainPath`、手動的 continuation，或它本來就會走完的那一段）之前，先一次、原子地取得整列車走完這條路所需要的鐵路資源；拿不到就不走。T 建立在 S3–S5 統一好的 `RailwayNetwork`、`TrackTraversal`、`TrackResource`（節點與 span）、`TrackPlatform` 與 `TrainPath` 上，不再處理方格與路網的遷移，也不延續舊 PR #31 的方格實作（第 20 點）。

**T 不做**（分屬之後的 Stage）：號誌顯示、movement authority 與「進入每個資源前檢查授權」、通過後逐段釋放（U）；dispatcher、繞路、越行、交會、月台分配、快車優先（V）；加減速與煞車（W）。

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

**5. 交會點、道岔、平面交叉與限界（fouling）。** T 只讀 topology 與整數里程，不讀高度、取樣點、3D mesh 或畫面。分析既有的保護夠不夠：

- **經過交會點的進路**：任何經過某個節點的路都包含那個節點（第 4 點）。道岔的兩條支線、平面交叉的兩個方向、雙交分道岔，都在共用的節點上衝突，所以兩條經過同一個交會點的進路不能同時成立。方格的道岔與平面交叉是一格，同理（S1）。
- **立體交叉**：S4 保證平面上相遇但沒有共用節點的兩條邊高度差至少 512，它們不共用任何資源，所以互不衝突；T 不需要任何特別的規則，也不讀高度。
- **不夠的地方——停在交會點附近**：S4 讓共用節點的兩條邊在那個節點 `RailwayNetwork.junctionZone`（1024）以內不檢查淨空，因為道岔的支線在那裡本來就並排、甚至重疊。一台列車停在支線 a 上、離節點 300 的地方（車尾已經離開節點），它只佔用 a 的 span，不佔用節點；另一台列車這時經過節點轉進支線 b，兩者沒有共用資源，實際上卻會互相穿過。span 最長 1024、節點預約與車身佔用都擋不住這種情況。
- **最小的限界規則**：
  - 節點上一條邊的端點是**限界端**（fouling end），若且唯若這個節點上還有另一條邊的端點**不和它相通**（兩者不是反方向離開，決策 29 第 9 點）。道岔的兩條支線、平面交叉的四個端點、在節點相交成角度的兩條邊都是；普通的直通節點（兩個相通的端點）與盡頭都不是；道岔的 stem 和每條支線都相通，所以也不是。
  - 列車（車身，或預約範圍）在某條邊上的區間，離這條邊的一個限界端的節點不到 `junctionZone`（里程距離 < 1024，與 S4 不檢查淨空的範圍相同）時，列車也**持有那個節點**。
  - 所以停在支線 a 的限界範圍內的列車持有交會點，經過交會點的進路就拿不到它；停在 stem 上、離道岔 300 的列車不持有交會點，在同一條線上接近道岔的列車不會被多擋。
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

- **取得**（交通控制開啟時，第 9–11 點）：給列車新路的指令（`setTrainContinuation` 兩種、`placeTrain`、`reverseTrain`）、服務的出發、線路的派車，以及開啟交通控制。一律先完整驗證、算出候選的新狀態與它的預約範圍、和其他列車的持有比較，全部成立才一次寫入新的移動、位置與預約；否則世界完全不變。新預約**取代**舊預約。路的長度為 0 時不存預約（空）。
- **保留**：列車沿路移動時整份保留，T 不逐段釋放（第 16 點）；`setTrainMovementRate`（包括 0）、`stopTrainService`、`unassignTrain`、刪除線路或服務模式都不動它：停止服務不是緊急煞車，列車仍會走完它的路。
- **解除**：路走完（第 3 點的「站著」，包括路網上停在邊中段的 `end`，不只看 `remainingEdges` 是否為空）時，在那一步的移動之後清除；`unplaceTrain`；關閉交通控制。之後列車站著的軌道仍由佔用（與限界）保護。
- 因此交通控制開啟時的不變量是：列車還有路要走 ⇔ 它有預約，而且預約包含它現在的預約範圍（佔用、限界與剩下的路）；站著的列車沒有預約；任兩台列車的持有不相交。

**8. 交通控制的開關。**

- `GameWorld` 的新世界預設**關閉**：Stage I–S5 的所有 fixture、測試與 digest 不改變語義，也能證明關閉時的行為與 S5 完全相同。App 建立的新遊戲**開啟**（`GameWorld.newGame()` 之後呼叫 `setTrafficControl(true)`）。沿用舊 PR #31 的做法，沒有更好的現有機制（服務與線路都沒有「全域模式」可以借用）。
- `setTrafficControl(true)`（原本關閉時）不是只改旗標：依 `TrainID` 遞增為每台已放置的列車算出它現在應有的持有（站著的列車：佔用 ∪ 限界；有路的列車：它的預約範圍），任兩台相交就拒絕，回報 `trainsShareTrack(a, b)`：`b` 是第一台與前面某台相交的列車，`a` 是與它相交的最小編號。全部成立才一次寫入旗標與每台列車的預約；失敗時沒有任何列車拿到預約，世界完全不變。已經開啟時再開啟什麼都不做。
- 開啟時已經在等待被拆鐵軌的列車（決策 15）：方格的路包含之後可能補回的連結，預約範圍照樣包含它們的格與連結（它們的身分就是格的位置），所以補回後列車仍在預約內前進；路網的路斷在被拆的邊之前，永遠不會再前進，預約只到那裡為止。
- `setTrafficControl(false)` 一定成功：清除每台列車的預約，位置、移動、時刻表、執行進度與線路都不變，不瞬移、不反向；之後回到 S5 的互不阻擋。

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
- `unplaceTrain`、`setTrainMovementRate`、`setTrainTimetable`、`startTrainService`（列車一定站著）、`stopTrainService`、線路指令：不需要新的檢查。

**10. 服務的出發與線路的派車。**

- **出發**：S5 仍然先得到 `TrainPath`；標記折返的停靠先在**假設**的折返位置上求路。然後 T 算出「折返後、走這條路」的候選狀態的預約範圍：
  - 成立：一次寫入折返、路、預約與 `.travellingToStop`，列車離站；
  - 被持有：什麼都不改（不折返、不寫路、不取消服務），列車保持 `.waitingAtStop`，下一個基本步長再試。和「沒有路」不同，這個結果不會記在同一次 `advance` 的「找不到路」清單裡：其他列車移動、走完路之後，軌道就會空出來。
  - 零距離到達與服務完成（原地站著、必要時折返）不需要新的軌道：折返不改變佔用，所以不會被擋。
- **派車**（Q2b、Q3）：就緒的條件多一條：交通控制開啟時，列車的第一個出發（折返與否照它的一趟決定）要能取得預約。取不到的列車不就緒：線路不派出它、不改 `lastDispatch`、不寫時刻表或執行進度、不折返，下一分鐘再試；依 ID 下一台就緒的列車可以派出。
- **派出的列車立刻出發**：派車（第 0 段）之後，被派出的列車在同一段就依出發的規則離開第一站，而不是等到第 1 段依 ID 輪到它。交通控制關閉時結果完全相同（出發彼此不互動，派車的判斷也不讀這台列車的位置）；開啟時，這讓「派出」與「取得進路」成為同一件事：第 1 段的其他出發不可能在中間搶走它剛確認可以取得的進路，所以不會發生「記了派車卻沒出發」。
- **規劃查詢不受影響**：`lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway`、`lineSegmentLoads` 繼續回答「計畫上能怎麼開」，不讀預約。
- 事件感知的快轉仍然精確：一步沒有任何改變時，被擋住的出發與派車在之後也不會被放行（只有其他列車移動、走完路或指令才會釋放軌道），所以喚醒時刻不變。

**11. 等待原因的查詢。** `trainHoldingRoute(of:) -> TrainID?`，唯讀、即時推導，不存等待原因：

- 服務停在某站、排定出發已到（`<=` 現在）時：候選出發（折返後的路）的預約範圍被哪台列車持有，回報編號最小的一台；
- 線路的列車：沒有服務、停在它的服務的第一個停靠站、線路現在該派車、除了預約之外都就緒時，同樣回報第一個出發的阻擋者；
- 其他情況（交通控制關閉、還沒到出發時刻、沒有路、路是空的、未知的列車）是 `nil`。方格與路網同一段程式。

**12. 同時的要求與決定性。** 同一個基本步長裡：第 0 段依 `LineID`、服務的順序派車（被派出的列車立刻取得進路），第 1 段依 `TrainID` 遞增處理出發；先處理的先取得，後處理的等待。這只是 T 的最小決定性規則，不是 dispatcher 的優先順序（V 才做快慢車、交會與待避）。預約的資源依既有的順序排序存放；阻擋者取最小編號；沒有任何結果依字典或集合的走訪順序決定。

**13. 基礎設施的變更與 span 身分的持久性。** 交通控制開啟時，預約中的基礎設施不能被偷偷拆掉或改變意義，但不相干的建設不受影響：

- `removeTrack`：任何列車預約了那一格或以它為一端的連結時拒絕。`removeTrackEdge`：任何列車預約了那條邊的 span 時拒絕。（列車實際站在上面的情況照舊是 `trackInUse`、`trackEdgeInUse`。）
- `addTrackPlatform`、`removeTrackPlatform`：月台的兩端會切開或合併那條邊的 span，所以任何列車**持有**那條邊的 span（預約或站在上面）時拒絕：前者讓已存的 span 失去意義，後者可能把兩台列車所在的相鄰 span 合成一個而產生衝突。沒有列車的邊照常可以改。
- `buildTrackEdge`：新邊的兩端節點若被列車持有，或有列車持有這個節點上某條邊離它不到 1024 的 span（限界範圍），拒絕，因為新邊可能改變那裡的限界端（第 5 點）。其他地方照常建造。
- `removeTrackNode` 只能拆沒有邊的節點；被預約的節點一定還有被預約（因此不能拆）的邊，所以不需要新的檢查。方格的鋪軌、道岔、平面交叉只能在空格，不會改變既有的格與連結。
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
  - 公開查詢：`reservedResources(of:)`、`heldResources(of:)`、`trainHoldingRoute(of:)`（服務用出發的同一個 `leaving(_:stop:cycle:)`；線路用派車的 `readyTrip(of:on:_:memo:)` 與 `firstDeparture(of:on:calling:)`）。
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
  - 關閉時與之前相同；開關；開啟時共用與相遇的路被拒絕；方格的整條路、連結跑到 `to` 端與反向、長列車從車尾預約、後車等前車走完整條路、平面交叉與道岔是一格；
  - 服務在站等待且不折返、`trainHoldingRoute`、線路不派出等不到路的列車且不改上次派車、等待修復的方格路；
  - 路網的 span：只取需要的 span、第一條與最後一條邊的一部分、停在分界上兩邊都取、長列車從車尾；彎道（7 段，906…5439）、高架與地下月台（月台切開的 span、兩個方向的停車位置）；
  - 道岔在節點相遇、停在支線限界內的列車持有交會點而 stem 上的不持有、兩條支線都在限界內時不能開啟、持有的交會點不能加邊；平面交叉共用節點、立體交叉互不相干；
  - 持有的邊不能加減月台、預約的邊不能拆；路網的服務等待並只在能走時折返；存讀、壞掉的存檔被拒絕（多預約的資源可以讀）。
- `ReferenceWorld`（`ReferenceTrafficControl.swift` 等）另外寫一次決策 32，而且盡量寫得不同：列車需要的軌道由整條來路與去路上的一個絕對距離區間讀出，限界端每次查詢時掃描每條邊，阻擋者逐台比較，開啟時逐對檢查，線路是否就緒、出發會拿什麼在世界的複本上實際執行一次。
- `TrafficControlPropertyTests`（`traffic.reservation`，40 個 case × 4 個種子 × 80 個操作 = 12,800 個操作，digest `C6419E59862453C5`，新的 CI shard `campaigns-5`）：方格（道岔、平面交叉、兩格的車站）與路網（直線、S 曲線、坡道、高架、隧道、支線，有時有菱形平面交叉與 1024 高的立體交叉，每站兩三個月台）上的 3 到 4 台 1 到 4 節的列車，執行交通控制的開關、放置與取下、手動的路與到車站的路、反向、時刻表、線路與服務模式、拆建鐵軌、邊與月台、在節點加支線與時間，同時在 GameCore 與 `ReferenceWorld` 上執行。每一步比較結果與整個狀態，以及每台列車的預約、持有、佔用與 `trainHoldingRoute`；並檢查不變量與存讀。量：取得的預約 787、被拒絕的取得 258、出發與派車取得 162、服務出發 622、服務等待 2,501、線路派車等待 203、方格衝突 126、路網 span 衝突 234、長列車的預約 523、停在邊中段的預約 240、開啟被拒絕 115、基礎設施被拒絕 102、走完路釋放 342。
- `SaveMutationTests` 新增 `save.trafficMutation`（12 個 case × 4 個種子，每個 30 次變異，也翻轉布林值）：載入 516、拒絕 924、瞄準交通控制與路的變異 1,098、翻轉 77、載入的有預約的世界 134；載入的世界都保持不變量、可以存讀，之後的指令也保持一致。
- `WorldInvariants` 在每個 campaign 的每一步檢查決策 32：關閉時沒有預約；開啟時任兩台列車的持有不相交，預約依資源順序、屬於已放置的列車、包含它站著的軌道，明顯站著的列車沒有預約、明顯在路上的有。
- Golden schema v19 與手算的 `traffic-reservation.json`（72 步：道岔 J 的限界讓開啟被拒絕；Up 與 Down 在第 1 分鐘爭同一段單線，Up 先取得從車尾（2048，分界）到 East 停車位置的整條路，Down 等待；Freight 移到立體交叉上並預約兩條邊；Up 在第 9 分鐘那一步到站並釋放，Down 在第 10 分鐘那一步出發，停在 West 的後退停車位置（里程 1024，分界）；預約中的邊不能加月台或拆除），第一次執行就在 GameCore 與 `ReferenceWorld` 上都通過；既有的 18 個 fixture 只加上中性的值。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄（主工作目錄的 `Sources` 從未改動）；四個都在 `traffic.reservation` 第一個種子的 case 0 被抓到，golden 也都失敗：
  - 路中間相接的節點沒有預約（立體交叉上的 node 6 也漏掉）：case 0 的第 7 步，另有 12 個手算測試失敗；
  - 只預約車頭的路、不含車身：case 0 的第 38 步，另有 7 個手算測試與 1 個 GamePresentation 測試失敗；
  - 服務出發不看預約：case 0 的第 3 步，另有 3 個手算測試失敗；
  - 路的最後一條邊少算 1（停在分界上時漏掉另一邊的 span）：case 0 的第 49 步，另有 1 個手算測試失敗。

#### GamePresentation / App

- `GameSession.setTrafficControl(_:)` 套用同一個指令並回報結果；被拒絕的路與開啟以玩家的文字說明是哪台列車。
- `routeWaitText(of:)` 由 `trainHoldingRoute(of:)` 即時推導「Waiting for <列車> to clear the route」，不存檔。
- App 的新遊戲開啟交通控制；線路面板有開關（開啟被拒絕時開關回到關閉、狀態列說明原因）；列車面板顯示等待。
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

G1 的第一步：車站有需求，需求推導出每對車站之間每天、每小時的旅次，每分鐘以整數釋出成等車的乘客，乘客在起點依線路、方向與目的地排隊，每一位都記在守恆稽核裡。還沒有上下車（G1b）、票價與帳本（G1c）。車站沒有需求時什麼都不發生：決策 1–33 的行為、存檔、既有 golden 的預期值與 property digest 都不變。

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
| `_metroAdmitDispatchPassengers`、`metroAddWaitingQueueTarget`：`waitingQueue[dir].targets["線路_迄點索引_迄點"] += n`，放不下的加進 `overflow` | `StationPassengers.release(_:to:along:at:)`、`WaitingGroup`、`overflowed` | 結構 faithful；排隊順序見第 5 點 |
| `metroGetStationWaitAdmitHeadroom`、`metroResolveStationWaitCap`（整個車站等車的總數 ≤ `line.cap × 8`，沒有 cap 時 `STATION_CAPACITY 500 × 8`） | `StationPassengers.capacity = 4000` | faithful（還沒有列車容量，所以用預設值；G1b 再看） |
| `spawnPassengersFromGlobalOD` 的後備路徑：從起點的線路裡找第一條同時停兩站的，用 `findStationIndexOnLine`（第一個索引）比大小決定方向 | `passengerTrip(from:to:)`：編號最小、同時停兩站的線路，第一次停靠的索引 | faithful |
| `spawnPassengersFromGlobalOD` 的 `poissonSample` 與 `Math.random` | 不採用 | 參考的舊路徑，不是 deterministic；現行路徑是上面的累加器 |

**1. 需求**：`StationDemand { kind, dailyTrips }`，`dailyTrips` 在 `0...1_000_000`（讓所有整數乘積都遠在 `Int64` 以內）。`setStationDemand(_:to:)` 設定或以 `nil` 清除，免費；檢查順序 `unknownStation` → `invalidStationDemand`。清除需求不影響已經在等的人。

**2. 每天的旅次（gap 的補法）**：參考的基數是伺服器由真實人口算好的 OD，快照裡沒有。這裡：起點一天的 `dailyTrips` 分給它能到、而且自己有需求的車站，比例是那些車站自己的 `dailyTrips`，以最大餘數法變成整數（平手給站號小的）。沒有需求的車站不產生也不吸引旅次。

**3. 每小時的旅次**：一對車站一天的旅次，依 `dayShape[h] × departureShape_o[h] × arrivalShape_d[h]` 以最大餘數法分到 24 小時（平手給較早的小時），合計正好等於一天。起點用 `out`、迄點用 `in`，和參考相同。

**4. 每分鐘釋出**：基本步長從 `T` 到 `T + 1` 的第一個階段（在派車之前）。在一天中第 `h` 小時第 `m` 分，每一對把 `(60 − m)·R_h + m·R_{h+1}` 加到自己的餘數，整除 3600 的部分就是這一分鐘釋出的人數，餘數留到下一分鐘。每個小時的旅次在自己與前一個小時裡合計被算 1830 + 1770 = 3600 次，所以任何連續 1440 分鐘，每一對正好釋出一天的旅次，餘數回到原來的值。同一分鐘依（起點、迄點）的順序釋出。
- 這一階段不讀、也不改任何列車。`advance` 跳過沒有列車變化的步長時，照樣逐分鐘釋出被跳過的那幾分鐘，結果和逐步推進完全相同。
- 每一對的每小時旅次只由需求與線路的停靠推導，算好的計畫（`PassengerPlan`）留在世界裡，跨 `advance` 呼叫沿用；`setStationDemand`、`createLine`、`setLineStops`、`removeLine` 與讀檔時丟掉，下一次推進時重算。它不是遊戲狀態：不存檔，也不影響兩個世界是否相等。餘數在每次呼叫開始時讀出、結束時寫回。

**5. 排隊**：釋出的人在起點排隊，一分鐘、一個迄點一組（`WaitingGroup { line, direction, destination, since, count }`），依釋出的順序排在最後，所以先來的在前（ROADMAP 5D 的先進先出；參考只有依 key 加總的人數，沒有順序）。車站等車的總數最多 4000：放得下的部分成為一組，其餘立刻離開，記進 `overflowed`。

**6. 線路改變**：`removeLine` 或 `setLineStops` 之後，等的線路已經不再以那個方向載他們去迄點的組離開車站，記進 `abandoned`；其他組保持原來的順序。參考裡刪除線路時連同那條線路的車站物件一起刪掉，等車的人也跟著消失；這裡把他們記下來，讓守恆可以稽核。新增線路不影響已經在等的人（他們仍等原來的線路）。

**7. 守恆稽核**：每一站 `released = waiting + overflowed + abandoned`（`PassengerLedger`）。G1b 加上車上與到達的人（決策 35）。

**8. 依賴方向**：乘客只讀車站的身分、線路的停靠與編號，以及時間；不讀 `TrackTraversal`、`TrackResource`、預約或 `TrainMovement`，也不改列車。

**9. 存檔**：`"passengers"` 只在有乘客紀錄時寫；每一筆是 `{ station, demand?, waiting, released, overflowed, abandoned, remainders }`，依車站排序。沒有需求、從未釋出、也沒有餘數的車站沒有紀錄。解碼拒絕：
- 數不合（`released` ≠ 等車 + `overflowed` + `abandoned`）、負數、超過容量；
- 組不照來的順序（依釋出的分鐘，同一分鐘依迄點遞增，不重複）、組的人數小於 1、釋出時間不早於現在（從 T 開始的步長在 T 釋出、結束在 T + 1）、組的線路不存在或不再以那個方向載他們；
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
- `Passenger/PassengerDemand.swift`：`setStationDemand(_:to:)`；查詢 `stationDemand(of:)`、`waitingPassengers(at:)`、`passengerLedger(of:)`、`passengerTrip(from:to:)`、`dailyDemand(from:to:)`、`hourlyDemand(from:to:)`；推導、最大餘數法、釋出的計畫（`PassengerPlan`，每條線路的第一次停靠只查一次，24 小時的旅次存成一個連續陣列）與它的快取（`PassengerPlanCache`）、每次呼叫的釋出（`PassengerRelease`）、線路改變時的放棄與存檔驗證。
- `GameWorld`：`passengers`（`internal(set)`，只由乘客的規則寫入）、`advance` 的乘客階段、`removeLine`／`setLineStops` 之後的放棄、`Codable`；`GameError.invalidStationDemand` 與玩家的文字。

#### 驗證

- `PassengerDemandTests`（手算，18 個）：
  - 曲線表與 `dayShape` 由參考的公式（Foundation 的 `exp`、正規化、`Math.round`）逐格重算；
  - 指令的檢查順序、清除需求時丟掉空的紀錄；線路的選擇（編號最小、第一次停靠、方向）；最大餘數法的平手；
  - 每天的分配（1000 → 750 : 250 等）、沒有需求的車站不吸引旅次；一天一個旅次落在 8 時（或回程的 18 時）；
  - 一天一個旅次在 08:59（第 539 分鐘）釋出：07:00–07:59 累加 1770，08:00–08:58 再加 1829，第 539 分鐘補滿 3600；
  - 從第 0、777、1439 分鐘起的任何 1440 分鐘都正好釋出一天的量、餘數回到原值；
  - 排隊的順序、容量 4000 與溢出（一百萬旅次的一天：等車 4000、溢出 996,000）、一次推進與逐分鐘推進的世界相同（也跨 2x）；
  - 線路改停靠、反向、刪除時的放棄與保留、清除需求時等車的人留下；存讀、沒有乘客的存檔沒有 `"passengers"`、20 種壞掉的存檔都被拒絕（包括同一分鐘的組順序顛倒或重複、`released` 超過 2⁶²）；
  - 跨呼叫保留的計畫在每個改變需求或線路的指令之後都和重算的相同，讀檔的世界沒有計畫、而且和原來的世界相等。
- `ReferencePassengers`：`ReferenceWorld` 另外寫一次決策 34，而且寫得不同：曲線每次由 `exp` 算出、每分鐘重新找旅次（不保留一次呼叫的計畫）、最大餘數法逐一挑最大的餘數而不是排序、一分鐘的份寫成 `60·R_h + m·(R_{h+1} − R_h)`、等車人數需要時才加總。每個 golden scenario 都在它上面重跑。
- `PassengerPropertyTests`（`passenger.differential`，20 個 case × 4 個種子 × 50 個操作 = 4,000 個操作，digest `62042B9B922FCE2C`，CI shard `campaigns-1`）：3 到 6 座車站，從隨機的分鐘（也有第 0 分鐘以前）開始，執行各種大小的需求（含最大值與不合法的值）、建立、改停靠與刪除線路、各種速度與長短的時間，同時在 GameCore 與 `ReferenceWorld` 上執行。沒有鐵軌與列車，所以 GameCore 的每一步都可能被當成閒置跳過，被跳過的分鐘的釋出因此也和逐分鐘推進的參考比對。每一步比較結果、每一站的排隊、數與餘數、每一對的旅次與每小時的旅次，並檢查不變量與存讀。量：釋出 61,314,671 人；有釋出的站次 1,188、溢出 675、放棄 158；不合法的需求 93、不存在的車站 69、刪除線路 142、改停靠 225。
- `SaveMutationTests` 新增 `save.passengerMutation`（12 個 case × 4 個種子，每個 30 次變異）：載入 506、拒絕 934、瞄準乘客、線路、車站與時鐘的變異 1,053、載入後有人在等的世界 189；載入的世界都保持不變量、可以存讀，之後的指令也保持一致。
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
- 只坐同一條線路；同時停兩站的線路不只一條時，一律坐編號最小的那條。
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

**2. 誰上車**：列車必須指派在一條線路上（`assignedLine(of:)`）。線路的列車只跑線路派出的來回，所以時刻表的形狀固定：第一站、往遠端的各站、遠端（折返）、回程的各站、回到第一站（折返，服務結束）。離開第 `i` 站時：
- 方向：`i < (停靠數 − 1) ÷ 2` 是 `outbound`，其餘是 `inbound`；
- 可以上車的組：那一站等車、線路與方向相同、迄點是第 `i + 1` 站到下一個折返站（含）之間某一站的組；
- 順序：迄點第一次出現的停靠越遠越先，同樣遠（同一迄點）的依排隊的順序；
- 依序整組上車，放不下的那一組部分上車（剩下的保留原來的分鐘與位置），之後的組都上不去；
- 可以上車卻沒上去的人數加進那一站的 `refused`。這是次數，同一個人可能被好幾班車拒絕，所以不在守恆式裡，累加到 2⁶² 為止。

**3. 時機（過渡做法，W2b 已取代，見決策 39）**：`Ci/` 的遊戲在列車**到站**那一刻一次讓所有人下車、上車（`_stationCallGuard` 讓同一幀只處理一次），然後固定停 36 秒（終點 42 秒），停站時間與人數無關（見下面「停站時間」）。GameCore 目前以分鐘為步長、停站時間是整數分鐘，所以暫時改在列車**離開**一站的那一刻處理：先下車、再上車。停站期間來的人都搭得上，結果也不依停站被切成幾段而改變。這**不是永久的語義**：W2 會把「到站 → 開門 → 上下車 → 關門 → 發車」以已移植的秒級停站規則接到遊戲時間、`RunningCurve` 與行程上，取代這個時機；誰上車、順序與容量（第 1、2、4、5 點）不變。
- 派車（階段 0）與出發（階段 1）把每一次離站依發生的順序記下來，兩個階段結束後依序處理（新的「上下車」階段，在移動之前）。上下車只讀列車、只改乘客，而出發不讀乘客，所以先記下再處理，和每次離站立刻處理的結果相同。`ReferenceWorld` 刻意用後者，驗證了這一點。
- 代價：下車的時間記在離站那一刻，比實際到站晚一個停站時間。
- 閒置跳步仍然精確：離站本來就算「有變化」，沒有離站的步長沒有上下車。

**4. 下車**：離開第 `i` 站時，迄點是這一站的人下車，加進起點的 `arrived`。在折返或最後一站，還在車上的人也下車（參考的 `releaseAll`）；因為沒有人會搭到下一個折返站之後，這種人永遠不存在，這一條只是保險，記進 `abandoned`。

**5. 服務提早結束**：
- 行程中被 `unassignTrain` 拿掉、或線路被 `removeLine` 刪掉的列車，照舊把車上的人載到迄點，但不再有人上車。
- 這樣的列車之後被 `stopTrainService` 停掉時，車上的人記進起點的 `abandoned`。線路上的列車不能被停掉（`trainOnLine`），所以這是唯一會丟下乘客的路。
- `setLineStops` 不影響車上的人：時刻表在派車時就固定了。

**6. 守恆稽核**：每一站 `released = waiting + riding + arrived + overflowed + abandoned`（`PassengerLedger` 新增 `riding`、`arrived`、`refused`）。`riding` 由各列車的 `RidingGroup` 加總，不另存。

**7. 依賴方向**：上下車讀線路的指派、列車的時刻表、執行進度（`TimetableExecution`）與輛數；不讀 `TrackTraversal`、`TrackResource`、預約或 `TrainMovement`，也不改列車。

**8. 存檔**：
- `"riders"` 只在有列車載客時寫；每一筆是 `{ train, groups: [{ origin, destination, count }] }`，依列車排序，組依（起點、迄點）排序、不重複。
- 車站紀錄的 `"arrived"`、`"refused"` 只在不是 0 時寫，所以 G1a 的存檔照舊能讀，沒有乘客的世界存檔完全不變。
- 解碼拒絕：
  - 沒有組、組的人數不在 1 到 16 × 352、起點等於迄點、組沒有排序或重複；
  - 列車重複、沒有排序、不存在或沒有在跑服務，載客超過容量；
  - 起點沒有乘客紀錄；迄點不是列車從目前（或正要去）的一站到下一個折返站之間會停的站；
  - 車站的數：`arrived`、`refused` 是負數，`refused` 超過 2⁶²，`waiting + arrived + overflowed + abandoned` 超過 `released`，或加上車上的人不等於 `released`。

**9. 停站時間（純計算；W2b 以地鐵的 36／42 秒與車門時間接到遊戲時間，見決策 39）**：`Ci/` 與 `Railway/` 兩邊找到的所有停站、車門與上車速度的規則，都在 `Railway/StationDwell.swift` 移植成純整數函式（單位是十分之一秒，讓 8.3 秒、10.2 秒、半個週期都精確）。G1b 還沒有把它們接進 `advance`、時刻表或線路的行程。兩邊都**沒有**依乘客人數、上下車速度、車門數或車門容量計算停站時間的規則：唯一的候選是 `Ci/` 的 `PARAMS.BOARDING_RATE`（2，沒有單位）與 `PARAMS.TRAIN_DWELL_TIME`（44 秒），兩者都只有定義、從來沒有被讀取。它們以原值保留成常數（`referenceBoardingRate`、`referenceTrainDwellTime`），不另外發明公式。這是 reference gap。

| 參考 | Swift（`StationDwell`） | 分類 |
| --- | --- | --- |
| `Ci` `DWELL_GAME_SEC = 36`、`DWELL_TERMINAL_GAME_SEC = 42`；`_advanceTrainOneStep` 到站時設定：關閉的車站 0（通過）、環狀線一律 36、路段終點 42、其餘 36 | `metroDwell`、`metroTerminalDwell`、`metroDwell(isServed:isRing:isTerminal:)` | faithful；終點的判定（`_isTrainRouteLegTerminalMove`，快車、路段）由 W2 的呼叫端提供 |
| `Ci` 停站的消耗：`remain = max(0, remain − step)`，到 0 才能發車，發車的那一步不帶剩餘時間 | `remainingDwell(_:after:)` | faithful |
| `Ci` 停站到 0 後，共用軌道的班距未清空時繼續等（`metroSharedTrackHeadwayClearance`） | 不在這裡 | 屬於運轉控制（Stage T 之後），W2 |
| `Ci` `metroHeadwayRoundTripMinutes`：線狀 `2·行駛 + 2·(站數 − 2)·36 + 2·42`，環狀 `行駛 + 站數·36`（÷ 60 成分鐘） | `metroRoundTrip(travel:stops:isRing:)`（不除以 60） | faithful |
| `Ci` `metroHeadwaySegmentTravelSeconds`（加速 1.1、減速 1.3 的梯形／三角形） | 不在這裡 | 行駛時間，不是停站；和 W1 的 `RunningCurve` 一起在 W2 處理 |
| `Ci` 路徑搜尋同一線路續乘時加的 `36`、時刻表建構的 36／42 | 同上的常數 | faithful（呼叫端在 W2） |
| `Ci` `bootstrap-lazy` 的 `Bt`（地鐵：開門 8 秒、剩 8.3 秒關門）、`Ta`（高鐵：7 秒、9 秒）；總時間至少 1 秒，剩餘時間夾在 0…總時間 | `doorPhase(total:remaining:opening:closing:)`、`metroDoorOpening`／`Closing`、`highSpeedDoorOpening`／`Closing` | faithful（參考裡是聲音與畫面用的；這裡只是純計算） |
| `Ci` `METRO_TRAIN_DOOR_CLOSE_REAL_SEC = 10.2`（真實秒 × max(1, 速度)，預備發車的關門警告） | `metroDoorCloseWarning(speed:)` | faithful |
| `Ci` `PARAMS.BOARDING_RATE 2`、`PARAMS.TRAIN_DWELL_TIME 44`、`DWELL_SEC 60`、`LONG_DWELL_DEBUG_SEC 45` | 前兩個保留為常數；後兩個不移植 | 參考裡都沒有被讀取（`LONG_DWELL_DEBUG_SEC` 讀的 `_longDwellDebug` 從未被設定） |
| `Ci` 高鐵：`hsrTrainDetailDwell` 等（離站 − 到站，負的加一天）、實際時刻匯入（端點 0，否則 `max(0, (離 − 到 + 1440) % 1440)`）、沒有停站時間時的估計（列出的區間時間 − 離站到下一站的分鐘，1…60 才採用）、插入的停靠 2 分鐘 | `stopMinutes`、`importedStopMinutes`、`estimatedStopMinutes`、`insertedStopMinutes` | faithful；插入停靠之後的 `GuangdongHsrSchedule.recalcService` 不在快照裡（gap） |
| `Railway` `DWELL_SEC = 25`、`trtcOfficialDwellAt`（車站自己的 `dwell` → 線路的 `dwellSec[i]` → 25，非正數視為沒有） | `defaultDwell`、`stationDwell(own:line:)` | faithful |
| `Railway` `trtcOfficialCoastCycle`（週期：給定的 → 最近兩次到站的間隔 → 行駛 + 25；停站 = 週期 − 行駛，至少 15、至多半個週期） | `coastCycle(given:lastArrivalGap:run:)`、`minimumCoastDwell` | faithful（整數秒的輸入完全精確） |
| `Railway` `buildLineSchedule`（沒有時刻表的週期性運行：第一站 → 最後一站 → 第一站，環狀線繞一圈；每站停自己的 dwell 或 25；起點在週期兩端各停一次） | `periodicTimetable(dwells:runs:isLoop:)` | faithful；缺行駛時間時以距離 ÷ 速度補的部分由呼叫端提供 |
| `Railway` 由倒數看板觀測的線路停站（每段相鄰站的觀測，8 個以上取中位數（偶數取上面那個）；有行駛時間時 0 < 中位數 < 180，否則第一段行駛 + 中位數在 40…240）、`TRTC_BR_DWELL_FALLBACK = 29` | `observedLineDwell(samples:hasRunningTimes:firstRun:)`、`observedDwellFallback` | faithful（收集觀測的部分依即時資料，不移植） |
| `Railway` `retimeLoopTrains`（環島列車：08:00 發、12 小時、起點與中間每個停靠站停 120 秒，其餘依區間長度分配，四捨五入到秒） | `loopTimetable(lengths:stops:)`、`loopDeparture`、`loopDuration`、`loopDwell` | faithful |
| `Railway` `HSR_DEP_MID_SEC = 30`（分鐘精度的高鐵資料，除了最後一站都在該分鐘的中間發車） | `highSpeedDepartureOffset` | faithful |
| `Railway` 的真實停站資料：`data/trtc.json`、`krtc.json`、`tmrt.json`、`sanying.json` 每站的 `dwell` 與線路的 `dwellSec[]`（秒）；`tra_schedule_dense.json`、`api/thsr-schedule.json`、`afr_schedule_dense.json` 的 `depSec − arrSec`；`*_times.json` 隱含的停站 | 還沒有匯入 | 資料；真實藍本情境的轉換工具（Phase 6）匯入時用 `stationDwell(own:line:)` 與 `periodicTimetable` |
| `Railway` 台鐵的待避停站（`planSameDirectionOvertakes`：`OVERTAKE_CLEAR_SEC 30`、`OVERTAKE_MAX_WAIT_SEC 600`）與交會推定（`inferMeetRun`：`MEET_HEADWAY_SEC 300`）、`rail-3d` 的 `dispatch.json` 發車保留 | 不在這裡 | 依賴 `buildProfile` 的可行性與台鐵的行駛曲線，屬於 W2／待避與交會；產生 `dispatch.json` 的程式不在封存裡（gap） |
| `Railway` 畫面用的門檻（剩餘 > 3 秒且總停站 ≥ 20 秒才顯示停站中、≥ 180 秒標為長停站、看板的 30 秒寬限） | 不在 GameCore | 畫面；G1c 的畫面需要時移植到 `GamePresentation` |

**Gap（參考沒有，這裡補上）**：`refused`（第 2 點）、起點的守恆（第 6 點）、服務停止時放棄車上的人（第 5 點）。**Reference gap（兩邊都沒有，沒有發明）**：依乘客人數、上下車速度、車門數或車門容量決定停站時間。

**沒有移植的**（之後的 Stage）：
- 把停站時間接到遊戲時間（第 3、9 點）：W2。
- 轉乘（5F）：分支線共用段的轉乘目標、下車後在轉乘站重新排隊（`metroUsesGlobalOdPathTransfer` 的路徑）。
- 環狀線（參考的 `isRing` 不在路段兩端全員下車）：遊戲的線路都是來回。
- 高鐵不超載（`lineKind === "hsr"`）：還沒有線路種類。
- 擁擠與滿載的通知（`emitCrowdAndFullTrainNotices`）：畫面在 G1c。

#### 實作

- `Passenger/Boarding.swift`：`RidingGroup`、`TrainRiders`、`Train` 的容量、查詢 `riders(of:)`、`riderCount(of:)`，上下車階段（`StopDeparture`、`serve(_:)`、`board(_:at:)`）、`abandonRiders(of:)`、存檔驗證 `riderProblem()` 與各自的 `Codable`。
- `Railway/StationDwell.swift`：兩個參考的停站、車門與高鐵停站分鐘的純計算（第 9 點），不讀也不改世界。
- `Passenger/StationPassengers.swift`：`PassengerLedger` 新增 `riding`、`arrived`、`refused`；`StationPassengers` 新增 `arrived`、`refused`、`board(_:)`、`refuse(_:)`，解碼改為只要求不超過 `released`（車上的人由 `GameWorld` 核對）。
- `GameWorld`：`riders`（`internal(set)`，只由乘客的規則寫入）、派車與出發記下離站、`advance` 的上下車階段、`stopTrainService` 放棄車上的人、`Codable`。

#### 驗證

- `BoardingTests`（手算，10 個）：容量（320／352 與輛數）、離站時上車與到迄點下車（在 Beta 停站期間還在車上）、下車站遠的先上與同一迄點先來的先上、放不下的那一組部分上車並保留分鐘、`refused`、滿載時全部被拒絕直到有人下車、遠端折返後載回程、只載自己的線路與方向與前方停靠的人、pattern 不停的站的人繼續等、離開線路的列車照舊載到迄點但不載新的人、停止服務時放棄車上的人、一天的營運逐分鐘守恆而且一次推進與逐分鐘相同、存讀與 11 種壞掉的存檔。
- `StationDwellTests`（11 個）：每一個預期值都是參考的 JavaScript（原樣抽出）在 Node 執行同一組 case 的結果；第一次執行就全部一致。
- `ReferencePassengers`：`ReferenceWorld` 另外寫一次決策 35，而且寫得不同：每次離站**立刻**處理（證明先記下、之後依序處理的結果相同）、車上的人是依列車、起點、迄點的字典、逐一挑最遠而且最早的組而不是排序、容量寫成 `輛數 × 320 × 11 / 10`。每個 golden scenario 都在它上面重跑。
- `BoardingPropertyTests`（`boarding.differential`，16 個 case × 4 個種子 × 70 個操作，digest `B105FCE7743F269F`，CI shard `campaigns-1`）：派車 campaign 的小路網、線路與列車，加上各種大小的需求、2 到 3 輛的列車、離開線路後停止服務，同時在 GameCore 與 `ReferenceWorld` 上執行，每一步比較所有狀態（包括每一站的排隊、帳本與每台列車的乘客）；每次推進也逐 tick 重跑。量（逐 tick 計數）：到達 4,673、上下車 4,434、滿載 4,461、被拒絕 1,417、2 輛以上載客 142、多個迄點 281、停止服務而放棄乘客 26。
- `SaveMutationTests` 新增 `save.riderMutation`（10 個 case × 4 個種子，每個 30 次變異）：載入 386、拒絕 814、瞄準乘客與服務的變異 890、載入後有列車載客的世界 95。
- `WorldInvariants` 在每個 campaign 的每一步檢查擴充後的守恆與車上乘客的規則（另外寫一次）。
- Golden schema v21 與手算的 `boarding.json`（預期值另以獨立的 Python 實作依規則算出），在 GameCore 與 `ReferenceWorld` 上都通過；既有 fixture 的預期值沒有改變。
- 刻意植入的錯誤，各自單獨植入到 `Sources` 的複本、驗證後丟棄：下車站近的先上、空位不扣車上的人、不下車、遠端的方向算錯、不記拒絕、停止服務不放棄乘客。六個都被手算測試、golden（含 `ReferenceWorld`）與 `boarding.differential` 第一個種子抓到。
- 完整測試（本機 Linux Swift 6.4，六個 shard，521 個測試）全部通過；18 個既有的 property digest 與 `main` 完全相同，`passenger.differential` 與 G1a 相同（`62042B9B922FCE2C`）。
- **不變的**：沒有需求時決策 1–34 的行為與存檔。

#### 已知限制與留給之後

- 上下車在離站那一刻一次完成是過渡做法（第 3 點），W2 以停站規則（第 9 點）取代；下車的時間因此暫時記在離站而不是到站。
- 只有線路的列車載客；手動時刻表的列車不載客。
- 同一分鐘同一站的兩班同線車，依派車與列車編號的順序上車。
- 還沒有票價、收入與畫面（G1c）。

### 36. 票價、帳本與經營（G1c）

G1 的最後一步：乘客上車時付票價，線路的列車每次離站記下班次、車公里、載客與座位，每小時結算營運與維修，每天結算能源與人事，寫進帳本與每日的帳；票價設定後也影響需求。新的世界是「自由模式」（`EconomyMode.free`），什麼都不收、不記，所以決策 1–35 的行為、存檔、既有 golden 的預期值與 property digest 都不變；App 的新遊戲是「經營模式」（`management`）。

**來源**：作者的 `Ci/` 網站（`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`，minified，以 prettier 展開後閱讀）的地鐵經濟「舊路徑」（`metroEconomy*` 函式）；`window.MetroEconomy` 引擎本身（`economy.js`、`metro_economy_rules.js` 等）不在快照裡。`Railway/` 沒有經濟模型（只有即時資料與時刻表），兩邊都搜尋過。

| 參考 | Swift | 分類 |
| --- | --- | --- |
| `economyMode`（free／management） | `EconomyMode`、`setEconomyMode(_:)`、`CompanyAccounts.openedAt` | faithful；開始經營的那一刻記下 `openedAt`，第一次結算在下一個整點（第 5 點） |
| `MetroEconomy.setFareRules("metro", …)`、票價編輯器的 `lineInfoFareModeValue`（flat／distance）、`metroFareDefaults().flatFare ?? 5`、`lineInfoFareDefaultDistanceBands`（0／6／12／22／32 km：0.55／0.70／0.85／1.00／1.20） | `FareRules.flat`、`.distance([FareBand])`、`FareRules.standard`（`.flat(500)`）、`standardBands` | faithful＋機械換算（美元 → 美分） |
| 引擎的票價檢查（1–64 段、從 0 起、首尾相接、只有最後一段沒有終點） | `FareRules.isValid`、`setFareRules(_:)` 的 `invalidFareRules` | faithful；上限（票價 ≤ 1e9 美分、距離 ≤ 1e7 m）是 gap，為了整數不溢位 |
| `metroEconomyStationDistanceKmByNetIdx`（起迄兩站的大圓距離） | `tripFare(from:to:)`：兩站格子的直線距離（1 格 = 1024 單位 = 16 m），以平方比較，完全精確 | 機械換算（平面地圖沒有經緯度） |
| `metroEconomyAccrueHourlyFare`：`fare ≤ 0` 收 5；`fareRevenue += Math.round(count × fare)` | `FareRules.charged(_:)`、`chargeFares(_:from:to:)`：每個迄點 `floor((count·fare + 50) ÷ 100) × 100` 美分 | faithful＋機械換算 |
| `updateTrainAtStation` 的 `fareTrips`（上車時依迄點收） | `board()` 依迄點彙整後收費 | faithful；時機是 G1b 的過渡做法（離站），W2 改到真實的上車 |
| `metroEconomyAccrueDeparture`（班次、車公里、乘客、座位） | `countDeparture(distance:passengers:seats:)`、`HourlyAccrual` | faithful；距離是派車時到下一站的路徑距離（世界單位），座位是額定容量（輛數 × 320） |
| `metroEconomySettleHourlyIfNeeded`（`metro.hourly.netSettlement`）：營運 `round(75·班次 + 42·車公里 + 18·車站)`、維修 `round(12·路線公里 + 9·車公里 + 8·列車)` | `settleAccounts(at:memo:)`、`settleHour`：以 1/64000 美元計算再四捨五入到整美元 | faithful＋機械換算（64000 單位 = 1 km） |
| 小時結算的 `crowdingMetrics`（等車 > 1500 的站、滿載列車、最多等車、最大載客千分比） | `CrowdingMetrics` | faithful；只記錄，不收費 |
| `metroEconomySettleDailyForEndedDay`：能源 `round(220·路線公里 + 360·列車)`（`metro_route_energy`、`metro_train_energy`）、人事 `620·車站 + 480·列車`（`metro_station_staff`、`metro_train_staff`），`allowNegativeBalance` | `settleDay`、`GameEconomy.settle(_:)` | faithful；各項各自四捨五入，總額是加總後四捨五入（與參考相同，可能差 1 美元） |
| 固定資產：車站（所有線路的停靠站，不重複）、路線長度、列車 | `fixedAssets(memo:)`：線路自己服務的行程去程各段的路徑距離、各服務各等級列車數的最大值相加 | 機械換算；參考由地圖的線路幾何量，這裡由已推導的行程（決策 22） |
| 帳本列（`metro_hourly_net`、`metro_daily_energy`、`metro_daily_staff`），保留最後 50 列 | `LedgerEntry`、`CompanyAccounts.entries`（`keptEntries = 50`） | faithful |
| `FLOW_DASHBOARD_FINANCE_BUCKETS`（日／週／月／年 = 1／7／30／360 天）、`summarizeFinanceForTransport` | `FinancePeriod`、`DayAccount`（保留 720 天）、`financeReport(_:)`（本期與上期） | faithful；參考保留整個帳本（年報表最多 50 年），這裡保留兩年，讓年報表的本期與上期都完整 |
| `metroFareDemandPenaltyForFare`（相對 `METRO_FARE_DEMAND_BASELINE_USD = 0.75` 的比值的曲線） | `FareRules.demandFactor(fare:)`：每 0.05 一格、95 格的千分比表，線性內插 | 公式 faithful；GameCore 沒有 `exp`，事先算成表（機械換算），測試以 Foundation 逐格重算，誤差 ≤ 1.6‰ |
| 需求乘上票價的影響 | `dailyDemand(from:)` 與乘客計畫：每對 `(trips × factor + 500) ÷ 1000` | faithful；只在經營模式而且玩家設定過票價時（第 6 點） |
| `metroEconomyMoneyText`：`"$ " + Math.round(dollars)` 加千分位 | `GamePresentation` 的 `Money.moneyText` | faithful |
| 經濟明細的分類標籤（`economy.ledger.*`、`economy.group.*`，只有 zh-CN） | `LedgerItem.displayName(in:)`、`LedgerEntry.Kind.displayName(in:)`（英文；繁體中文照參考轉換，決策 38） | 翻譯 |

**1. 金額**：`Money` 是參考美元的**美分**。之前的建設費用與餘額數值不變，只是從 G1c 起以美元顯示（`$ 10,000` 是 1,000,000）：一般四捨五入到整美元（`moneyText`），票價與「餘額不足」的訊息精確到美分（`centsText`），以免顯示成「需要 $ 10、只有 $ 10」。

**2. 票價**：`tripFare(from:to:)` 是規則對兩站直線距離的票價，0 以下收 5 美元；距離段 `[from, to)`，正好在終點的距離屬於下一段。沒有設定規則時用 `FareRules.standard`（均一 5 美元）。

**3. 收入**：乘客上車時（G1b 的上下車階段）依迄點收費，進入這一小時的 `pending`；只在經營模式。

**4. 班次**：線路的列車每次離站（`Leaving.setsOff`，帶有到下一站的距離）在上車之後記一次班次、距離、車上人數與座位。手動時刻表的列車不載客也不記。

**5. 結算**：
- 每個基本步長一開始，經營模式、`now` 是整點、而且 `openedAt < now` 時，結算剛結束的一小時：營運與維修，寫一列（票價、營運、維修三項都是 0 時不寫），餘額加上淨額，`pending` 歸零，`openedAt = now`。
- 這一小時屬於 `now − 1` 那一天（參考先結算小時，再換日）。
- `now` 是午夜時，接著寫前一天的能源與人事，時間記為 `now − 1`。
- 餘額可以變成負數；之後建設仍然需要足夠的餘額（決策 4）。
- 閒置跳步：經營模式下逐分鐘檢查，不會跳過任何一次結算（一次推進與逐分鐘相同）。
- 自由模式下什麼都不累積、不結算；切回經營模式時重新從那一刻開始。

**6. 需求**：經營模式而且設定過票價規則時，每對車站每天的旅次乘上票價的影響（基準 0.75 美元時是 1000‰，0 元時 1080‰）。沒有設定過時需求完全不變，所以 G1a、G1b 的 golden 在經營模式下也不變。

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
- `GamePresentation/EconomyText.swift`：金額、票價、標籤、最近一小時的分項、最近的帳本列、每站依線路方向的等車人數、列車的載客率；`GameSession.setEconomyMode(_:)`、`setFareRules(_:)`。
- App：HUD 的餘額以美元顯示（負數為紅色），點一下開啟 `EconomyPanel`（餘額、模式、票價、最近一小時、本期與上期的報表、最近 12 列）；檢視器顯示車站的等車、列車控制顯示載客；新遊戲是經營模式；建設費用以美元顯示。

#### 驗證

- `EconomyAccountsTests`（手算，10 個）：自由模式不記帳、存檔不變；沒有任何東西在動的世界仍然每小時、每天結算；均一與距離票價、正好在段的終點、0 元收 5 元；票價規則的檢查；60 分的小時列（票價 1500、營運 142800、維修 1400、18 班）；午夜的能源（−37400 = 路線 −1400、列車 −36000）與人事（−234000）、日期與餘額；一次推進與逐步相同；需求影響 1000／1080／487 與表對公式；存檔往返與 12 種壞掉的存檔。
- `EconomyDisplayTests`（4 個）：金額的四捨五入（含負數與 Int64 的兩端）、精確到美分的金額（票價與「餘額不足」的訊息）、帳本列與最近一小時、等車與載客率、session 的指令。
- `ReferenceEconomy`：`ReferenceWorld` 另外寫一次決策 36，而且寫得不同：每站離站時立刻收費、以 1/64000 美元累積、票價規則逐步檢查、每日的帳是字典、固定資產以集合計算。每個 golden scenario 都在它上面重跑。
- `EconomyPropertyTests`（`economy.differential`，12 個 case × 4 個種子 × 60 個操作，digest `C6B29457D984AF1`，CI shard `campaigns-5`）：上下車 campaign 的路網、線路與需求，九成是經營模式，途中設定與被拒絕的票價規則、切換模式、跨小時與跨日的推進，同時在 GameCore 與 `ReferenceWorld` 上執行，每一步比較所有狀態（餘額、帳、四種報表與票價）；每次推進也逐 tick 重跑，2× 與 1× 比較。量：結算的小時 1932、有票價收入的小時 234、結算的日 82、設定的票價規則 241、被拒絕的 30、餘額變成負數 27。
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
  - 時刻表的時間可以是任何一秒，但在 W2b 之前，出發等到排定出發當時或之後的第一個整分鐘。線路推導的時間（行程、停留、班距）仍是整分鐘。
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
  2. 參考 `Ci/` 的簡體中文介面（`ui-locales/zh-CN`），轉成繁體與台灣用語：經濟明細、經濟流水、小時淨額、能源費用（日結）、員工費用（日結）、票價收入、營運成本、維護成本、線路供電與牽引用電、列車日用電、車站員工、司機與調度員工、本期、上期、固定票價、階梯票價、票價規則、餘額不足、交路、上線列車數、開班、收班、候車、載客、第 N 日。`Ci/` 的高峰／平峰、站台、运营、快速列车、普通列车、发车间隔，改用上面台灣網站的說法（尖峰／離峰、月台、營運、快車、普通車、班距）。
  3. 兩者都沒有的（gap，自訂）：交通控制、進路、軌段、道岔的共用端、平面交叉，以及所有錯誤訊息與建設、列車操作的說明。
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
  5. 客滿的列車離開時，那一站還在等、它本來可以載的人記進 `refused`（決策 35 的次數）；有空位的列車在關門之前已經載走所有它能載的人。線路的列車照舊記下班次與距離（決策 36）。
- **線路的時刻表**：派車的那一刻到達第一站，42 秒後離開（端點的最短停站），之後的時間都由這個離開推算。線路原本留在第一站的 2 分鐘終點停留，分成出發前的 42 秒與回到第一站後剩下的 78 秒（比最短停站 42 秒長），所以準點的列車仍在 `roundTripMinutes` 之後可以再被派出，派車的分鐘不變。
- **誤點（`GameWorld.lateness(of:)`，秒，負數是早到）**：停站時，排定出發之後是超過的秒數，之前則是比排定到達早到的秒數（晚到但還趕得上排定出發算 0）；行駛時是離開前一站晚了多少與超過排定到達多少中較大的（都不算早到）。重複時刻表的排定時刻加上週期 × 輪次。
- **`advance`**：每一秒先處理整分鐘的帳、乘客與派車，再處理每台列車的停站與出發，再移動。兩個事件之間只有移動：一次走完到下一個整分鐘、停站事件（開門、開始關門、出發）或某台列車走完它的路為止，結果與逐秒相同，到站的時刻也是精確的。整分鐘沒有任何改變時，跳到下一個停站事件所在的分鐘（含剛好在下一分鐘開始的事件）或下一個可能派車的分鐘；有乘客釋出而且有列車開著門時不跳，因為新釋出的人會上車。
- **存檔**：`Train` 的 `times` 與 `execution` 同時有或同時沒有；開門、上下車、關門的順序要合理（`exchangeEnd ≥ arrival + 8`、`closing ≥ exchangeEnd`、等待時 `departure ≤ arrival`、行駛時必有 `departure ≥ arrival` 而且沒有停站的欄位），而且都不晚於時鐘（`exchangeEnd` 可以晚於時鐘：上下車還在進行；但有 `exchangeEnd` 時，開門的時刻 `arrival + 8` 不晚於時鐘）。沒有存檔版本（決策 6），App 也還沒有把存檔寫到裝置，所以執行中的服務沒有 `times` 的舊存檔被拒絕，不換算。
- **決定性**：全部是整數；時刻相加以飽和運算避免溢位（列車 ID 順序、乘客的處理順序不變）。

驗證：

- 參考模型（`ReferenceWorld`）以不同的寫法逐秒執行同樣的規則（沒有捷徑），Kernel 差分與所有 property campaign 都比對 `times`；所有 golden fixture 也在參考模型上重播。
- 手算的 `ServiceDwellTests`（參考包要求的情境：到達、沒有乘客的最短停站、上下車延長停站、開著門時加入的乘客、早到等排定出發、誤點不多等、停站中存檔、剛好落在整分鐘的事件不被跳過）與 golden `station-dwell.json`。
- golden schema 24：時刻表可以寫秒（`arrivalSeconds`、`departureSeconds`），列車的 `times`，`serviceTimes`、`lateness` 觀察；既有 fixture 改變的值逐一說明在 `GoldenScenarios/README.md`。

GamePresentation／App：早到與誤點改由 `lateness(of:)` 推導（仍以整分鐘顯示，不到一分鐘算準點）；新增 `DwellPhase`（開門中、乘客上下車中、開門停站、關門中、準備發車），列車面板在停站時顯示，英文與繁體中文。

不做：月台擁擠的延長（參考包的 `platformCongestionPenalty`）、轉乘（參考包要求的「轉乘的人帶著剩下的路線回到車站」，乘客目前只有單一線路的旅次）、依車種的門數與速率、`Railway/` 的每站實測停站時間、時刻表的停留（`dwellMinutes`）改用秒；行駛曲線接到移動（W2c）。

## 目前規則摘要

- 地圖尺寸：每邊 `1...GridMap.maximumSideLength`（暫定 1024）。
- 鋪軌與建站只能在空格；車站不能與鐵軌重疊。
- 鐵軌的連接方向至少一個、只能是北、東、南、西；鋪設時不要求與鄰格相接。
- 兩格鐵軌只有在相鄰且各自有朝向對方的出口時才相接；車站不是鐵軌（決策 10）。
- 鐵軌分為一般鐵軌、道岔與平面交叉。一般鐵軌每個出口都互通（只禁止原地掉頭）；道岔的 stem 接到每條支線，支線只接到 stem；平面交叉只能直行。路徑、continuation 與移動都遵守同一條轉向規則（決策 26）。
- 拆軌只接受鐵軌格；空格與車站會被拒絕。有列車停在該格、以該格為所在連結的一端、或車身經過該格時也會被拒絕（`trackInUse`，決策 14、27）。拆除免費且**不退款**。
- 新購列車未放置。列車可以放在鐵軌格的中心（任何朝向），或兩格相接鐵軌之間 `0 < offset < 1024` 的位置；放置、取下、反向都免費。
- 已放置的列車以非負整數 rate（每遊戲分鐘的邏輯單位）沿明確的 continuation 移動；沒有 continuation 時只走到目前連結的端點。前方被拆的鐵軌讓列車在最後一個可達節點等待，補回後自動續行，等待的距離不累積（決策 15）。
- 推進時間時若遊戲秒會溢位，整批拒絕（`clockOverflow`）。
- 遊戲時間以秒計，基本步長是一秒；速度是每 tick 的十分之一秒（`x1` 是真實時間，`normal` 一 tick 一分鐘），不足一秒的部分留到下一個 tick。列車每秒走它每分鐘 rate 的份，整分鐘加起來正好是 rate，到站也每秒判定；帳、乘客釋出與派車在整分鐘處理，停站、上下車與出發在任何一秒（決策 37、39）。
- 車站或列車的 ID 已配發到最後一個（`Int.max − 1`）時，建站或購車被拒絕（`idsExhausted`），不扣款（決策 6）。
- `route(from:to:)` 回傳到目的地鐵軌格的最短、不折返的 continuation（同長時依北、東、南、西順序），或 `nil`；它是唯讀查詢，不會自己設定列車的 continuation（決策 16）。
- 車站的月台是它每一格正北、正東、正南、正西的鐵軌格；`route(from:toStation:)` 回傳到第一個到達的月台的最短、不折返 continuation。列車在月台格中心、沒有剩下的 continuation 時停在該站（`stationsStoppedAt(by:)`）；停站由狀態推導，不另存（決策 18）。
- 車站可以長到它某一格旁邊的空格（`extendStation`，收一座車站的費用）。列車有 1 到 16 節，每節一格，只能在不在軌道上時設定；車頭後方的車身沿鐵軌記錄在 `trail`，移動時跟著走，反向時車頭移到車尾。車身下的鐵軌不能拆。長列車到站時沿月台延伸，整列都在月台邊時才算整列停妥（`stationsBesideWholeTrain`，決策 27）。
- 列車的時刻表是依序的停靠（車站、排定的到達與離開，開局以來的遊戲秒，決策 37），時間從 0 起不倒流、每站都是存在的車站；`setTrainTimetable` 整份原子替換、`[]` 清除、免費。時刻表是計畫資料：放置、取下、反向、移動指令與時間都保留它；只有明確啟動的服務會讀它（決策 19、20）。
- 時刻表可以每隔固定的秒數重複（`setTrainTimetable(_:to:repeatingEvery:)`），停靠可以標記在離開時折返；週期至少 1 秒，而且重新開始時時間不倒流（決策 21、37）。
- `startTrainService` 讓停在第一站車站的列車依時刻表執行服務：只跑一次，或一輪接一輪重複（`execution` 記錄目前是第幾輪的第幾個停靠，存檔；重複的時刻表從下一個準時的輪次開始）。每一秒先處理停站與出發，再移動、推進時鐘、判定到達（決策 37、39）：列車在每一站停站（到達後 8 秒開門、上下車、至少停 36 秒，時刻表的第一站、最後一站與折返的站 42 秒，關門 9 秒），不會早於排定出發時刻離開，誤點時停完就走；啟動服務與零距離到達下一站（已停在那一站的車站）都算到達；沒有路就關著門等待；最後一站停完、而且到了排定出發才結束服務，重複的時刻表則接著下一輪。實際的到達與出發時刻（`times`）存檔，誤點（`lateness(of:)`）由它們與排定時刻算出。服務執行中不能手動設定 continuation、反向、取下或換時刻表（`trainServiceActive`），rate 仍可調整；`stopTrainService` 只結束自動化（決策 20）。標記折返的停靠在出發時先讓列車原地反向，找不到路時不反向（決策 21）。
- 服務線路是計畫資料：依序的車站、計算行程用的 rate、營運時間，以及各服務等級的列車數或目標班距；服務日決定一天中每分鐘的等級。行程、最多列車數（最短班距 2 分鐘）、實際列車數與班距由地圖推導，不存檔（決策 22、23）。
- 指派給線路的列車由線路派出：每個整分鐘在停站與出發之前，營運中、該等級有列車、距上次派車已過一個班距、跑車中的列車少於該等級的列車數時，線路讓第一台停在第一站、rate 大於 0、能開完來回的列車跑一趟來回（產生該趟的時刻表並啟動服務，在第一站停 42 秒後出發，必要時出發時先折返）。列車回到第一站後折返等待；線路的列車不能手動設定時刻表或啟停服務（`trainOnLine`，決策 23）。
- 線路可以另有交路與快車等服務模式：停靠線路部分的站（站的索引、嚴格遞增），各有自己的列車數或目標班距與列車，從自己的第一個停靠站派車。每段鐵軌每天每個方向最多 720 班；各服務依序（線路自己的服務最先）以 `⌈1440 ÷ 班距⌉` 佔用它經過的每一段，放不下的服務減少列車數（決策 24）。
- 連續軌道（決策 29）：節點是地圖內的整數世界座標點（一格 1024 單位），邊是兩個節點之間的直線或整數控制點的三次曲線，長度由固定的整數取樣規則推導、以每格鐵軌的費用計價。只有共用節點的邊才相接，而且只在兩個邊端離開節點的方向相反（誤差 1/16 以內）時互通；平面上交叉但沒有共用節點的邊互不相干。路網上的列車在邊上，`0 <= offset <=` 邊長，有車身時 `offset > 0`；它沿 `edges` 移動，車身記錄在 `trailEdges`，反向時車頭移到車尾。方格與路網共用同一個最短路徑搜尋與同一套資源身分：節點，以及邊上不超過一格長的 span（S3A）。所有鐵軌只記在 `RailwayNetwork`，地圖只有土地。
- 立體鐵路（決策 30）：節點的高度在地面（0）上下 4096 以內；邊的高度沿水平里程依縱斷面變化（固定坡度，或兩端的拋物線豎曲線），最陡 40‰。結構物決定高度帶（地面 ±128、高架與橋 ≥ 0、隧道 ≤ 0）與費用倍數（1、3、4、5）。兩條邊在平面上相遇（共用節點 1024 以內除外）時高度差至少 512，否則拒絕；同一高度的交叉必須共用節點。隧道口是隧道與非隧道的邊相接的節點。車站可以在路網上平坦的一段邊上有月台；月台屬於鐵路網，同一條邊上的月台不重疊，兩端切開那條邊的 span，有月台的邊不能拆。
- 路網上的營運（決策 31）：停站、時刻表、折返與重複、線路、派車與服務模式在方格與路網上是同一套規則，只有找月台、找路與交給移動依鐵軌種類分開。以車站為目的地的路（`TrainPath`：行進方向、停在最後一條的哪裡、精確距離）在路網上停在行進方向上月台的末端（停車位置），只考慮不比列車短的月台；總距離最短，同樣短時依邊的編號逐步決定。一段的分鐘數是距離 ÷ rate 無條件進位。路網上列車的路可以停在最後一條邊的中段（`end`，只在有值時存檔）；路走完、車頭在該站月台上（車頭所在的邊）時停在該站，整列都在同一個月台上時整列停妥。服務正在使用的月台不能拆（`trainServiceActive`）。
- 交通控制與進路預約（決策 32）：`GameWorld` 的新世界關閉交通控制，行為與之前完全相同；App 的新遊戲開啟。開啟時，列車出發、被派車或拿到新的路（手動的路、放置、反向）之前，一次取得從車尾到路的終點整列車會碰到的每個節點與 span（與佔用同一條規則，落在 span 分界上時兩邊都算），以及它接近的交會點（在交會點 1024 以內、而那裡另有不相通的邊）；任何一個被其他列車持有（佔用、限界或預約）就整個不取得，指令以 `trackReserved` 拒絕，服務原地等待（不折返）、每步重試，線路不派出那台列車。預約存檔，走到路的終點時釋放；`unplaceTrain` 與關閉交通控制也清除它。立體交叉不共用資源。預約中的鐵軌不能拆，持有的邊不能加減月台，持有的交會點不能加邊。開啟時兩台列車需要同一段軌道就拒絕（`trainsShareTrack`）。
- 車站需求與乘客（決策 34）：車站可以有需求（四種類型之一，每天 0 到 1,000,000 個旅次）。每天的旅次分給同一條線路能到、自己有需求的車站（依它們的旅次，最大餘數法），再依一天的形狀與兩端類型的曲線分到 24 小時。每個整分鐘一開始，每一對依這一小時與下一小時內插釋出這一分鐘的份，保留不到一人的餘數；任何連續 1440 分鐘正好釋出一天的旅次。乘客在起點依線路、方向、迄點與釋出的分鐘成組排隊，先來的在前；一站最多 4000 人，放不下的離開（`overflowed`）。線路刪除或改停靠而不再載某一組時，那一組離開（`abandoned`）。每一站 `released = 等車 + overflowed + abandoned`。沒有需求時什麼都不發生。
- 上下車與容量（決策 35、39）：列車到達一站 8 秒後車門開好，坐到那一站的人下車（`arrived`），同時線路上的列車讓那一站等它的線路、方向、而且迄點是它到下一次折返之前會停的站的人上車：下車站遠的先上，同一迄點先來的先上，最多到容量（每輛 352 人：額定 320 × 1.1）；花的時間是較多的一邊 ÷ 每節每秒 8 人，進位到整秒；開著門時每個整分鐘釋出的人也上車。客滿的列車離開時，還在等、本來可以搭的人記進 `refused`（次數，不是人數）。列車的服務在載客時被停止，車上的人記進 `abandoned`。每一站 `released = 等車 + 車上 + arrived + overflowed + abandoned`。
- 經營（決策 36）：新的世界是自由模式，什麼都不收、不記。經營模式下乘客上車時付票價（均一或依兩站直線距離分段，0 以下收 5 美元，每個迄點四捨五入到整美元），線路的列車每次離站記下班次、距離、乘客與座位；每個整點結算剛結束的一小時（營運 `75·班次 + 42·車公里 + 18·車站`、維修 `12·路線公里 + 9·車公里 + 8·列車`），每個午夜結算前一天的能源（`220·路線公里 + 360·列車`）與人事（`620·車站 + 480·列車`），都以美元四捨五入，寫進帳本（最後 50 列）與每日的帳（720 天）。結算可以讓餘額變成負數。設定過票價時票價影響需求。金額是美分。
- 車站目前不能拆除（未實作）。
- 餘額不足時不做任何修改，建設不會讓餘額變成負數（經營的結算可以，決策 36）。
