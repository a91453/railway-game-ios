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
- **GamePresentation**（Phase 2B 起）是與平台無關的 Presentation 邏輯：持有世界的 `GameSession`、`TickAccumulator`、玩家看到的文字（錯誤訊息、時間、金額）與地圖縮放換算。它只依賴 GameCore 與 Swift 標準函式庫的 `Observation`，不 import SwiftUI / UIKit，因此與 GameCore 一起在 Linux CI 上測試。
- **App**（`RailwayGameApp/`）只有 SwiftUI 畫面：`@main` App 以 `@State` 持有唯一一個 `GameSession`，畫面讀取 `session.world` 並呼叫 session 的方法。GameCore 維持不變、不為 UI 加上 observation。

## GameCore 模組

| 目錄 | 內容 |
| --- | --- |
| `World` | `GameWorld`（狀態協調點與指令入口）、`GridMap`、`GridPosition`、`MapTile` / `TileType`、`GameError` |
| `Railway` | `TrackDirection` / `TrackConnections`、`Track`（唯讀快照）、軌道連通查詢（`connectedNeighbors(of:)`、`isConnected(_:to:)`，由地圖推導）、`Station` / `StationID`、`Train` / `TrainID`、`TrainPosition`（列車在鐵軌上的位置）、`TrainMovement`（rate、continuation 與移動 kernel）、路徑搜尋（`route(from:to:)`）、停站（`platforms(of:)`、`route(from:toStation:)`、`stationsStoppedAt(by:)`）、時刻表（`ScheduledStop`、`Train.timetable`） |
| `Economy` | `Money`、`GameEconomy`、`ConstructionCosts` |
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

`GameTime` 是自開局以來的整數「遊戲分鐘」。`GameClock` 從不讀取 wall clock：宿主（Presentation 層的 game loop，見決策 12）把真實經過時間換算成整數 tick，再呼叫 `advance(ticks:)`。每個 tick 在 paused / 1x / 2x 下分別執行 0 / 1 / 2 個**基本步長**（basic step），每個基本步長是一遊戲分鐘。相同的 tick 序列必定得到相同結果，測試不需要 sleep。

2x 以「每 tick 執行兩次基本步長」實作，而不是把步長加倍，讓結果與速度無關（Phase 3 Stage K 起列車移動就是逐步執行，見決策 15）。

`advance(ticks:)` 會 throw（`throws(GameError)`）：在改動任何東西之前，先以 checked 運算確認 `ticks × 每 tick 步數` 不溢位、且時鐘加上這些分鐘後仍放得下（`Int64` 分鐘）；任一項不成立就丟出 `clockOverflow`，整批不執行、世界完全不變。paused 的步數永遠是 0，多大的 ticks 都不會因此被拒絕。負數 ticks 仍是程式錯誤（`precondition`）。`GameClock.advance(ticks:)` 本身也用同一套檢查。

### 4. GameWorld ownership

`GameWorld` 是 value type（struct），所有欄位 `private(set)`，唯一的修改方式是它的指令方法（`buildTrack`、`removeTrack`、`buildStation`、`purchaseTrain`、`placeTrain`、`unplaceTrain`、`reverseTrain`、`setTrainMovementRate`、`setTrainContinuation`、`setTrainTimetable`、時間控制與 `advance(ticks:)`）。

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
- 每個玩家動作都是 session 方法 → 對應的 `GameWorld` 指令。session 不預先檢查遊戲規則（空格、資金、名稱），由 GameCore 決定並丟出 `GameError`；session 只把結果轉成畫面訊息（`GameError.playerMessage`，定義在 GamePresentation）。失敗時世界保持不變（GameCore 的原子性保證）。
- session 另外只保存 UI 暫時狀態：選取的格子、目前工具、下一段鐵軌的方向、車站名稱草稿、選取的列車 ID、放置列車時的朝向、最後一則訊息。現金、時間、速度、地圖、車站、列車的位置與移動都直接從 `world` 讀取，不另存副本（列車見決策 17）。
- 全部在 main actor 上執行，不需要鎖或 `@unchecked Sendable`。
- 放在獨立的 SwiftPM target 而不是 App target，是為了讓 session 與其規則在 Linux 上以 `swift test` 驗證（App target 只能在 macOS CI 編譯）。

### 12. 宿主 game loop：真實時間 → 整數 tick

wall clock 只存在於 Presentation 層；GameCore 只收到 `advance(ticks:)`。

- `GameSession` 的 loop 以 `ContinuousClock` 量測經過時間，交給 `TickAccumulator` 換算成固定間隔（100 ms）的整數 tick，不足一個 tick 的餘數留到下一次，因此 tick 頻率不會隨畫面節奏漂移。`Task.sleep` 只負責節奏，不影響正確性。
- 速度不改變 tick 頻率：1× 與 2× 都是每 100 ms 一個 tick，由 GameCore 決定每個 tick 執行幾個基本步長（決策 3）。暫停時丟棄經過的時間，不累積。
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
  - `unplaceTrain(_:)`：取下列車，保留 ID 與名稱（Stage O 起也保留時刻表，決策 19）。錯誤依序為 `unknownTrain` → `trainNotPlaced`；重複取下會被拒絕（與拆除空格被拒絕的慣例一致），不是 no-op。
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
  - `rate: Int64`：每個基本步長（一遊戲分鐘）可走的邏輯單位數，1024 = 一格。不是 km/h；與 `GameSpeed` 的 1× / 2× 分開命名。範圍是 `0...Int64.max`：移動時先比較剩餘距離與到下一節點的距離，只有剩餘距離較短時才把它加到 offset 上（結果必小於 1024），否則相減，所以任何非負 rate 都不會溢位；負數以 `invalidMovementRate` 拒絕。rate 0 表示原地不動，但保留 continuation。
  - `continuation: [GridPosition]`：列車之後依序要進入的節點。起點是「目前所在的節點」或「目前連結的 `to` 端」，這個節點本身不列入。例如在 `onLink(A→B)` 上，`[C, D]` 表示先走完 A→B，再走 B→C、C→D。
  - `cursor: Int`：已經**開始進入**的 continuation 項數。恰好抵達節點不前進 cursor；真的開始走下一條連結（消耗正距離）時才 +1。前面已進入的項保留在陣列裡，只移動 cursor，不做 `removeFirst` 搬移。全部項目都進入後，continuation 視為用完，存成 `[]`、cursor 0；因此 `cursor < continuation.count`，或兩者皆為空。
  - 未放置的列車永遠是 `TrainMovement.idle`（rate 0、無 continuation）。**被阻擋不存成狀態**：它可以由位置、continuation 與地圖推導，每一步都重新檢查。
- **指令**（皆免費，錯誤依序檢查；失敗時世界完全不變）
  - `setTrainMovementRate(_:to:)`：`unknownTrain` → `trainNotPlaced` → `invalidMovementRate`。
  - `setTrainContinuation(_:to:)`：`unknownTrain` → `trainNotPlaced` → `invalidContinuation`。先對**當前地圖**驗證整份清單，再整份替換、cursor 歸 0；空清單就是清除。每一項都必須與前一項（第一項則是列車所在節點或目前連結的 `to` 端）依決策 10 相接，且不能立即折返：`atNode` 往 heading 的反方向離開、`onLink(A→B)` 後接回 A、或清單中 X→Y→X 都算 U-turn，必須先 `reverseTrain`。同格、斜對角、隔格、地圖外、空格與車站都拒絕；有限迴圈與重複經過同一節點可以。清除 continuation 不會把列車瞬移到節點：在連結上的列車若 rate > 0，仍會走到該連結的端點；要立即停住就把 rate 設為 0。
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
  - 若某一步沒有任何列車改變，同一次呼叫裡之後的步驟也不可能改變任何東西（地圖與每台列車的輸入在下一個指令前都不變），所以時鐘直接前進剩下的分鐘數。這是精確的捷徑，不是近似；它讓一次推進大量 tick 在列車停下之後不必逐步空轉。
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
  - 停站列車所在的鐵軌不能拆（決策 14 的 `trackInUse`），車站目前也不能拆，所以停站只會因這台列車的指令結束：設定非空的 continuation，或 `unplaceTrain`。
  - `stationsStoppedAt(by:)` 依 `StationID` 遞增列出列車停的車站；未知、未放置或沒有停站的列車是 `[]`。一格月台旁可能有多個車站，所以回傳清單而不是單一車站。
  - 停站不存成狀態（與決策 15 的「被阻擋」相同），因此不會殘留、不會提早消失，存讀後也相同；存檔格式不變。
- **成本**：`platforms(of:)` 與 `stationsStoppedAt(by:)` 只讀常數個格子（找車站與列車用既有的 O(車站數)、O(列車數) 查詢）；`route(from:toStation:)` 與 `route(from:to:)` 相同。
- **App（GamePresentation）**：Train 工具選取的格子是車站時，送出改用 `route(from:toStation:)`，同樣在同一次呼叫中原封不動交給 `setTrainContinuation`（決策 17 的其他規則不變）；成功訊息寫出車站名稱與月台，沒有路徑時世界不變。列車狀態另外顯示 `stationStopText(of:)`（例如 `Stopped at Market, Hill`），每次從世界讀取。這改變了決策 17 對車站格的行為：Stage M 時車站格一律沒有路徑。
- **Golden scenarios**：schema v7 新增 `platforms`、`routeToStation`、`stationStops` 觀察與 `station-stop.json`。
- **本 Stage 不做**：停留時間（dwell）、時刻表、途經多站或指定停靠站的服務模式（Phase 4）、乘客、拆除車站、月台容量或佔用、多格車站。

### 19. 時刻表基礎（Phase 4 Stage O）

Stage O 只回答：「這台列車被排定在哪些遊戲分鐘到達、離開哪些車站？」它**不**回答「列車現在是否該出發？」，那是 Stage P 的問題。時刻表是列車的權威狀態，但在 Stage O 是 **inert** 的計畫資料：模擬的任何部分都不讀它。

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

**Stage P 的接點**：Stage P 把時刻表接上停站（決策 18）與時鐘。它需要決定：怎樣算「到達」某一站（例如列車開始在該站停站，決策 18）、到達後如何停留到 `departure`、何時以及如何出發（由誰求路並提交 continuation）、早到與誤點怎麼處理、錯過出發時刻時怎麼辦，以及執行進度（目前在第幾站）要不要成為存檔的權威狀態。這些都是新的行為，必須在 Stage P 另外決定並以新的 golden fixture 固定；Stage O 的資料契約（順序、時間、不變量、指令、存檔）可以原樣作為輸入。

## 目前規則摘要

- 地圖尺寸：每邊 `1...GridMap.maximumSideLength`（暫定 1024）。
- 鋪軌與建站只能在空格；車站不能與鐵軌重疊。
- 鐵軌的連接方向至少一個、只能是北、東、南、西；鋪設時不要求與鄰格相接。
- 兩格鐵軌只有在相鄰且各自有朝向對方的出口時才相接；車站不是鐵軌（決策 10）。
- 拆軌只接受鐵軌格；空格與車站會被拒絕。有列車停在該格、或以該格為所在連結的一端時也會被拒絕（`trackInUse`，決策 14）。拆除免費且**不退款**。
- 新購列車未放置。列車可以放在鐵軌格的中心（任何朝向），或兩格相接鐵軌之間 `0 < offset < 1024` 的位置；放置、取下、反向都免費。
- 已放置的列車以非負整數 rate（每遊戲分鐘的邏輯單位）沿明確的 continuation 移動；沒有 continuation 時只走到目前連結的端點。前方被拆的鐵軌讓列車在最後一個可達節點等待，補回後自動續行，等待的距離不累積（決策 15）。
- 推進時間時若遊戲分鐘會溢位，整批拒絕（`clockOverflow`）。
- 車站或列車的 ID 已配發到最後一個（`Int.max − 1`）時，建站或購車被拒絕（`idsExhausted`），不扣款（決策 6）。
- `route(from:to:)` 回傳到目的地鐵軌格的最短、不折返的 continuation（同長時依北、東、南、西順序），或 `nil`；它是唯讀查詢，不會自己設定列車的 continuation（決策 16）。
- 車站的月台是它正北、正東、正南、正西的鐵軌格；`route(from:toStation:)` 回傳到第一個到達的月台的最短、不折返 continuation。列車在月台格中心、沒有剩下的 continuation 時停在該站（`stationsStoppedAt(by:)`）；停站由狀態推導，不另存（決策 18）。
- 列車的時刻表是依序的停靠（車站、排定的到達與離開，開局以來的遊戲分鐘），時間從分鐘 0 起不倒流、每站都是存在的車站；`setTrainTimetable` 整份原子替換、`[]` 清除、免費。時刻表是計畫資料：放置、取下、反向、移動指令與時間都保留它，模擬不讀它（決策 19）。
- 車站目前不能拆除（未實作）。
- 餘額不足時不做任何修改，餘額不會因建設變成負數。
