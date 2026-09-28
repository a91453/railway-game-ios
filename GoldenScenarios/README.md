# Golden Scenarios

可移植的行為 fixture：每個 JSON 檔是一個完整情境，包含起始世界、依序執行的指令與每個指令應有的結果、在指令之間進行的唯讀觀察與應有的答案，以及最後應該得到的世界狀態。預期結果是**手寫並經過 review 的**，測試只讀取、從不寫回。

Swift 參考實作：`Tests/GameCoreTests/GoldenScenario.swift`（讀取與執行）、`GoldenScenarioTests.swift`（`swift test` 會跑這個目錄下所有 `*.json`）。未來其他語言的 GameCore 移植版必須從**同一批檔案**得到同樣的結果。架構背景見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 13。

## 執行一個情境

1. 以 `initialState` 建立世界。
2. 依序執行 `steps`：
   - 指令步驟：實際結果必須等於 `expect`；被拒絕的指令不得改變世界的任何狀態。
   - 觀察步驟：向執行到這一步為止的世界提出唯讀查詢，答案必須等於 `expect`。觀察不是指令，不會改變世界。
3. 全部執行完後，世界必須等於 `expectedFinalState`。

## Schema（`schemaVersion: 3`）

除了每個步驟在 `command` 與 `observe` 之間擇一，所有欄位都必填。讀取端遇到不認得的 `schemaVersion`、指令、觀察、結果或方向名稱必須報錯，不可猜測。不要加入 schema 沒有定義的欄位，同一個物件裡也不要重複 key：目前的 Swift 讀取端會忽略多出的欄位、各語言對重複 key 保留的值也不同，兩者都還沒有自動檢查。

| 欄位 | 內容 |
| --- | --- |
| `schemaVersion` | `3` |
| `description` | 這個情境驗證什麼（給人看） |
| `initialState` | `mapWidth`、`mapHeight`、`balance`、`costs`（`track` / `station` / `train`）、`gameMinutes`、`speed` |
| `steps` | 依序執行的陣列；每一步是指令 `{ "command": {...}, "expect": {...} }` 或觀察 `{ "observe": {...}, "expect": {...} }`，恰好擇一 |
| `expectedFinalState` | `gameMinutes`、`speed`、`balance`、`stations`、`tracks`、`trains` |

### 值的表示

- **整數**：所有數字都是整數，寫成純十進位（不寫 `1.0`、`1e3`），絕對值不超過 2^53 − 1。有些語言的 JSON 讀取器把數字一律讀成 double，這個範圍內才保證精確；`testFixturesUsePortableJSON` 會檢查。
- **金額**（`balance`、`costs`、`required`、`available`）：整數遊戲貨幣單位（GameCore 的 `Money`），沒有小數；`costs` 不可為負數。
- **時間**：`gameMinutes` 是開局以來的遊戲分鐘；`ticks` 是模擬 tick 數。每個 tick 在 `paused` / `normal` / `double` 下推進 0 / 1 / 2 分鐘。
- **位置**：`x`、`y` 是格子座標，`x` 向東、`y` 向南，`(0, 0)` 是西北角。
- **方向**：`"north"`、`"east"`、`"south"`、`"west"`；陣列順序不影響意義，同一方向不可重複。
- **速度**：`"paused"`、`"normal"`、`"double"`。
- **布林值**：JSON 的 `true` / `false`（只用在觀察的答案）。
- **ID**：車站、列車 ID 是世界依序配發的整數，從 1 開始、失敗的指令不消耗 ID。列車指令與結果以 `train` 欄位寫列車 ID。
- **列車位置**：以 `type` 區分三種，只能出現該種類的欄位，多出別種的欄位必須報錯：
  - `{ "type": "unplaced" }`：未放置（只出現在最終狀態；放置指令不能用它）。
  - `{ "type": "node", "x", "y", "heading" }`：停在該格鐵軌中心，面向 `heading`（方向名稱）。
  - `{ "type": "link", "from": { "x", "y" }, "to": { "x", "y" }, "offset" }`：在 `from`、`to` 兩格中心之間，距 `from` `offset` 單位，面向 `to`。
  - 相鄰兩格中心的距離固定是 **1024 單位**（抽象格距，不是公尺或像素）。合法的 `link` 必須 `0 < offset < 1024`；恰好在格子中心一律寫成 `node`。指令裡的位置照原樣讀取、不檢查也不正規化，是否合法由 GameCore 判定，所以 fixture 可以預期 `offset` 為 0 的放置被拒絕。

### 指令（`command.type`）

| `type` | 其他欄位 | GameCore 指令 |
| --- | --- | --- |
| `buildTrack` | `x`、`y`、`connections` | `buildTrack(at:connections:)` |
| `removeTrack` | `x`、`y` | `removeTrack(at:)` |
| `buildStation` | `name`、`x`、`y` | `buildStation(named:at:)` |
| `purchaseTrain` | `name` | `purchaseTrain(named:)` |
| `placeTrain` | `train`、`position`（`node` 或 `link`） | `placeTrain(_:at:)` |
| `unplaceTrain` | `train` | `unplaceTrain(_:)` |
| `reverseTrain` | `train` | `reverseTrain(_:)` |
| `setSpeed` | `speed` | `setSpeed(_:)` |
| `pause` | — | `pause()` |
| `resume` | — | `resume()` |
| `advance` | `ticks`（≥ 0） | `advance(ticks:)` |

### 結果（`expect.result`）

| `result` | 其他欄位 | 意義 |
| --- | --- | --- |
| `ok` | — | 指令成功 |
| `outOfBounds` | `x`、`y` | 位置在地圖外 |
| `tileOccupied` | `x`、`y` | 該格已有東西 |
| `invalidTrackConnections` | — | 鐵軌沒有任何連接方向（GameCore 也拒絕四個方向以外的位元，但方向名稱無法表達它們，因此只在 Swift 單元測試驗證） |
| `invalidName` | — | 名稱是空白 |
| `insufficientFunds` | `required`、`available` | 資金不足 |
| `noTrackToRemove` | `x`、`y` | 該格不是鐵軌 |
| `trackInUse` | `x`、`y` | 該格鐵軌是某台已放置列車所在的節點，或其連結的一端，不能拆除 |
| `unknownTrain` | `train` | 沒有這個 ID 的列車 |
| `trainAlreadyPlaced` | `train` | 列車已經在鐵軌上；放置不會移動列車，要先取下 |
| `trainNotPlaced` | `train` | 列車不在鐵軌上，無法取下或反向 |
| `invalidTrainPosition` | — | 位置不是地圖內的鐵軌格，或不是兩格相接鐵軌之間、`0 < offset < 1024` 的連結 |
| `invalidMapSize` | `width`、`height` | 地圖尺寸不支援（目前指令不會產生） |

### 觀察（`observe.type`）

觀察透過 GameCore 的公開唯讀查詢回答，不屬於指令，也不能寫在 `command.type`。`expect` 的形式由觀察種類決定，種類不符或同時寫了兩種答案（例如 `connectedNeighbors` 配 `connected`，或 `neighbors` 與 `connected` 並列）必須報錯。

| `type` | 其他欄位 | `expect` | GameCore 查詢 |
| --- | --- | --- | --- |
| `connectedNeighbors` | `x`、`y` | `{ "neighbors": [{ "x", "y" }, ...] }` | `connectedNeighbors(of:)` |
| `isConnected` | `from`、`to`（各為 `{ "x", "y" }`） | `{ "connected": true }` 或 `false` | `isConnected(_:to:)` |

相接規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 10）：

- 兩格只有在上下左右相鄰、都在地圖內、都是鐵軌，而且各自有朝向對方的出口時才相接；`isConnected` 與參數順序無關。
- 只有一邊有出口、空格、車站、地圖外、同一格、斜對角、相隔一格以上都不相接。懸空的出口可以鋪設，不影響指令結果。
- `neighbors` 固定依北、東、南、西排序且不重複，比對時**順序有意義**；起點是空格、車站或在地圖外時為空陣列。
- 每格鐵軌是一個互通節點：三個、四個出口的鐵軌，每個相接的出口都會列出。

列車規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 14）：

- 新購列車是 `unplaced`。放置、取下、反向都免費。
- `node` 必須是地圖內的鐵軌格，`heading` 可以是任何方向（不要求該方向有出口或鐵軌）。`link` 的兩端必須依上面的相接規則相接。空格、車站、地圖外、同一格、斜對角、隔格、只有一邊有出口都是 `invalidTrainPosition`。
- `placeTrain` 的檢查順序：`unknownTrain` → `trainAlreadyPlaced` → `invalidTrainPosition`。`unplaceTrain`、`reverseTrain`：`unknownTrain` → `trainNotPlaced`。
- 反向：`node` 的 `heading` 取反；`link` 的 `from`、`to` 對調，`offset` 變成 `1024 - offset`。位置不變，反向兩次還原。
- 拆軌的檢查順序：`outOfBounds` → `noTrackToRemove` → `trackInUse`。多台列車可以共用同一節點或連結。
- `advance` 只推進時間，列車不會移動。

### 最終狀態

- `stations`：`{ "id", "name", "x", "y" }`，依 ID 遞增。
- `tracks`：`{ "x", "y", "connections" }`，逐列由北到南、每列由西到東。
- `trains`：`{ "id", "name", "position" }`，依 ID 遞增；`position` 的形式見上面「列車位置」。

只比對有意義的遊戲狀態；不包含存檔格式、內部欄位（例如下一個 ID）或任何畫面狀態。

## 修改 fixture

- **改 fixture 就是改遊戲行為。** PR 說明必須逐一解釋每個改變的值為什麼改變；不可為了讓測試變綠而修改預期值。
- 測試失敗時會印出實際結果的 JSON 以便對照；確認差異是預期中的行為改變後，才手動更新 fixture。沒有自動 regenerate 的工具，也不要做一個。
- 新情境的預期值從遊戲規則推算，而不是先執行一次再貼上輸出。
- 新增欄位、指令、觀察或結果種類時，提升 `schemaVersion` 並同步更新所有讀取端、所有 fixture 與本文件。
- Fixture 檔案只使用 ASCII（名稱與說明都是），`testFixturesUsePortableJSON` 會檢查：Unicode 正規化與空白判斷在各語言之間可能不同，目前不屬於契約範圍。

## Schema 版本紀錄

- **1**：起始狀態、指令與結果、最終狀態。
- **2**（Phase 3 Stage I）：新增觀察步驟（`observe` + `expect`）與 `connectedNeighbors`、`isConnected` 兩種觀察，以及 `track-connectivity.json`。既有的兩個 fixture 只把 `schemaVersion` 從 1 改成 2，指令、結果與最終狀態的預期值都沒有改變。
- **3**（Phase 3 Stage J）：新增 `placeTrain`、`unplaceTrain`、`reverseTrain` 指令，`trackInUse`、`unknownTrain`、`trainAlreadyPlaced`、`trainNotPlaced`、`invalidTrainPosition` 結果，最終狀態每台列車新增必填的 `position`，以及 `train-position.json`。既有的三個 fixture 把 `schemaVersion` 從 2 改成 3；`build-starter-line.json` 唯一的列車（`Local 1`，從未放置）加上 `"position": { "type": "unplaced" }`。它們的指令、結果、時間、金額、軌道、車站與 ID 預期值都沒有改變。讀取端只接受 3。
