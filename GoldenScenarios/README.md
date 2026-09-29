# Golden Scenarios

可移植的行為 fixture：每個 JSON 檔是一個完整情境，包含起始世界、依序執行的指令與每個指令應有的結果、在指令之間進行的唯讀觀察與應有的答案，以及最後應該得到的世界狀態。預期結果是**手寫並經過 review 的**，測試只讀取、從不寫回。

Swift 參考實作：`Tests/GameCoreTests/GoldenScenario.swift`（讀取與執行）、`GoldenScenarioTests.swift`（`swift test` 會跑這個目錄下所有 `*.json`）。未來其他語言的 GameCore 移植版必須從**同一批檔案**得到同樣的結果。架構背景見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 13。

## 執行一個情境

1. 以 `initialState` 建立世界。
2. 依序執行 `steps`：
   - 指令步驟：實際結果必須等於 `expect`；被拒絕的指令不得改變世界的任何狀態。
   - 觀察步驟：向執行到這一步為止的世界提出唯讀查詢，答案必須等於 `expect`。觀察不是指令，不會改變世界。
3. 全部執行完後，世界必須等於 `expectedFinalState`。

## Schema（`schemaVersion: 8`）

除了每個步驟在 `command` 與 `observe` 之間擇一，所有欄位都必填。讀取端遇到不認得的 `schemaVersion`、指令、觀察、結果或方向名稱必須報錯，不可猜測。不要加入 schema 沒有定義的欄位，同一個物件裡也不要重複 key：目前的 Swift 讀取端會忽略多出的欄位、各語言對重複 key 保留的值也不同，兩者都還沒有自動檢查。

| 欄位 | 內容 |
| --- | --- |
| `schemaVersion` | `8` |
| `description` | 這個情境驗證什麼（給人看） |
| `initialState` | `mapWidth`、`mapHeight`、`balance`、`costs`（`track` / `station` / `train`）、`gameMinutes`、`speed` |
| `steps` | 依序執行的陣列；每一步是指令 `{ "command": {...}, "expect": {...} }` 或觀察 `{ "observe": {...}, "expect": {...} }`，恰好擇一 |
| `expectedFinalState` | `gameMinutes`、`speed`、`balance`、`stations`、`tracks`、`trains` |

### 值的表示

- **整數**：所有數字都是整數，寫成純十進位（不寫 `1.0`、`1e3`），絕對值不超過 2^53 − 1。有些語言的 JSON 讀取器把數字一律讀成 double，這個範圍內才保證精確；`testFixturesUsePortableJSON` 會檢查。
- **金額**（`balance`、`costs`、`required`、`available`）：整數遊戲貨幣單位（GameCore 的 `Money`），沒有小數；`costs` 不可為負數。
- **時間**：`gameMinutes` 與時刻表的 `arrival`、`departure` 都是開局以來的遊戲分鐘；`ticks` 是模擬 tick 數。每個 tick 在 `paused` / `normal` / `double` 下推進 0 / 1 / 2 分鐘。
- **位置**：`x`、`y` 是格子座標，`x` 向東、`y` 向南，`(0, 0)` 是西北角。
- **方向**：`"north"`、`"east"`、`"south"`、`"west"`；陣列順序不影響意義，同一方向不可重複。
- **速度**：`"paused"`、`"normal"`、`"double"`。
- **布林值**：JSON 的 `true` / `false`（只用在觀察的答案）。
- **ID**：車站、列車 ID 是世界依序配發的整數，從 1 開始、失敗的指令不消耗 ID。列車指令與結果以 `train` 欄位寫列車 ID；車站觀察、時刻表的停靠與 `unknownStation` 結果以 `station` 欄位寫車站 ID。
- **列車位置**：以 `type` 區分三種，只能出現該種類的欄位，多出別種的欄位必須報錯：
  - `{ "type": "unplaced" }`：未放置（出現在最終狀態與 `train` 觀察的答案；放置指令不能用它）。
  - `{ "type": "node", "x", "y", "heading" }`：停在該格鐵軌中心，面向 `heading`（方向名稱）。
  - `{ "type": "link", "from": { "x", "y" }, "to": { "x", "y" }, "offset" }`：在 `from`、`to` 兩格中心之間，距 `from` `offset` 單位，面向 `to`。
  - 相鄰兩格中心的距離固定是 **1024 單位**（抽象格距，不是公尺或像素）。合法的 `link` 必須 `0 < offset < 1024`；恰好在格子中心一律寫成 `node`。指令裡的位置照原樣讀取、不檢查也不正規化，是否合法由 GameCore 判定，所以 fixture 可以預期 `offset` 為 0 的放置被拒絕。
- **列車移動**：`{ "rate", "continuation": [{ "x", "y" }, ...], "cursor" }`，三個欄位都必填。
  - `rate`：每個基本步長（一遊戲分鐘）可走的單位數，非負整數。
  - `continuation`：列車之後依序要進入的節點，完整列出（包含已進入的項）；起點是列車所在節點或目前連結的 `to`，這個節點本身不列入。
  - `cursor`：已開始進入的項數。恰好抵達節點不算進入下一項。全部項目都進入後存成 `[]`、`cursor` 0。
  - 未放置或從未設定過的列車是 `{ "rate": 0, "continuation": [], "cursor": 0 }`。
- **時刻表**：依序的停靠陣列 `[{ "station", "arrival", "departure" }, ...]`，三個欄位都必填、都是整數；**順序有意義**（陣列順序就是停靠順序）。沒有時刻表是 `[]`。指令裡的停靠照原樣讀取、不檢查，是否合法由 GameCore 判定，所以 fixture 可以預期負數時間被拒絕。

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
| `setTrainMovementRate` | `train`、`rate` | `setTrainMovementRate(_:to:)` |
| `setTrainContinuation` | `train`、`continuation`（`[{ "x", "y" }, ...]`，可為空陣列） | `setTrainContinuation(_:to:)` |
| `setTrainTimetable` | `train`、`timetable`（停靠陣列，可為空陣列） | `setTrainTimetable(_:to:)` |
| `setSpeed` | `speed` | `setSpeed(_:)` |
| `pause` | — | `pause()` |
| `resume` | — | `resume()` |
| `advance` | `ticks`（≥ 0） | `advance(ticks:)`（可能回傳 `clockOverflow`） |

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
| `trainNotPlaced` | `train` | 列車不在鐵軌上，無法取下、反向、設定 rate 或 continuation |
| `invalidTrainPosition` | — | 位置不是地圖內的鐵軌格，或不是兩格相接鐵軌之間、`0 < offset < 1024` 的連結 |
| `invalidMovementRate` | — | rate 是負數 |
| `invalidContinuation` | — | continuation 有一步與前一個節點不相接，或立即折返 |
| `clockOverflow` | — | 推進後的遊戲分鐘超出時鐘上限（`Int64`），整批不執行。可移植整數（≤ 2^53 − 1）無法表達這個情境，目前只在 Swift 單元測試驗證 |
| `idsExhausted` | — | 這類 ID（車站或列車）已配發到最後一個（`Int.max − 1`），建造或購買整個不執行、不扣款。fixture 只能從 1 開始配發，無法走到這裡，目前只在 Swift 單元測試驗證 |
| `invalidMapSize` | `width`、`height` | 地圖尺寸不支援（目前指令不會產生） |
| `invalidTimetable` | — | 時刻表的時間倒流：某站 `arrival` 為負數或晚於 `departure`，或某站 `arrival` 早於前一站的 `departure` |
| `unknownStation` | `station` | 時刻表的這一站不是存在的車站（依時刻表順序的第一個） |

### 觀察（`observe.type`）

觀察透過 GameCore 的公開唯讀查詢回答，不屬於指令，也不能寫在 `command.type`。`expect` 的形式由觀察種類決定，種類不符或同時寫了兩種答案（例如 `connectedNeighbors` 配 `connected`，或 `neighbors` 與 `connected` 並列）必須報錯。

| `type` | 其他欄位 | `expect` | GameCore 查詢 |
| --- | --- | --- | --- |
| `connectedNeighbors` | `x`、`y` | `{ "neighbors": [{ "x", "y" }, ...] }` | `connectedNeighbors(of:)` |
| `isConnected` | `from`、`to`（各為 `{ "x", "y" }`） | `{ "connected": true }` 或 `false` | `isConnected(_:to:)` |
| `train` | `train` | `{ "position": {...}, "movement": {...} }`（形式同最終狀態） | `train(id:)` |
| `route` | `from`（列車位置，`node` 或 `link`）、`to`（`{ "x", "y" }`） | `{ "found": true, "route": [{ "x", "y" }, ...] }` 或 `{ "found": false }` | `route(from:to:)` |
| `platforms` | `station`（車站 ID） | `{ "platforms": [{ "x", "y" }, ...] }` | `platforms(of:)` |
| `routeToStation` | `from`（列車位置，`node` 或 `link`）、`station`（車站 ID） | 與 `route` 相同 | `route(from:toStation:)` |
| `stationStops` | `train` | `{ "stations": [id, ...] }` | `stationsStoppedAt(by:)` |
| `timetable` | `train` | `{ "timetable": [{ "station", "arrival", "departure" }, ...] }` | `train(id:)?.timetable` |

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
- `advance` 推進時間；rate 為 0 的列車不會移動。

列車移動規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 15）：

- `setTrainMovementRate`、`setTrainContinuation` 的檢查順序：`unknownTrain` → `trainNotPlaced` → `invalidMovementRate` / `invalidContinuation`。continuation 整份對當前地圖驗證後才替換，`cursor` 歸 0；空陣列是清除。
- 每個 `advance` 的 tick 在 `normal` 執行 1 個、`double` 執行 2 個、`paused` 執行 0 個基本步長；每個基本步長依列車 ID 順序讓每台列車走 `rate` 單位，然後時間 +1 分鐘。
- 在連結上先走到 `to`；還有距離就依序進入 continuation 的下一個節點。恰好用完距離時停在節點，不進入下一項。沒有下一項，或下一項當下不相接時，停在該節點，剩下的距離作廢，下一項不消耗；之後每一步重新嘗試，鐵軌補回後自動續行。
- `reverseTrain` 清空 continuation、保留 rate；`unplaceTrain` 把 movement 重設為 idle。

路徑搜尋規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 16）：

- `route` 的答案是從列車前方節點（所在節點或連結的 `to`）出發、以 `to` 結尾的節點清單，可以原封不動用在 `setTrainContinuation`；前方節點就是 `to` 時是 `[]`。
- 連結數最少；同樣最少時，出口方向序列依北、東、南、西逐步比較，取最先的一條。不會立即折返，也不會 reverse，但可以繞圈掉頭。
- 起點不是地圖上合法的位置、`to` 不是鐵軌格（空格、車站、地圖外），或到不了時，答案是 `{ "found": false }`。`route` 只在 `found` 為 `true` 時出現。`from` 照原樣讀取，是否合法由 GameCore 判定。

停站規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 18）：

- 車站不是鐵軌。車站格正北、正東、正南、正西的鐵軌格是它的月台：不需要朝向車站的出口，斜對角不算，同一格可以同時是多個車站的月台。`platforms` 依北、東、南、西排序，**順序有意義**；未知的車站或旁邊沒有鐵軌時是空陣列。
- `routeToStation` 與 `route` 相同，只是把車站的每個月台都當作目的地：連結數最少、同樣最少時出口方向序列依北、東、南、西逐步比較；在第一個到達的月台結束。前方節點已是月台時是 `[]`。起點不合法、車站不存在或沒有月台、或到不了任何月台時是 `{ "found": false }`。
- 列車在某站的月台格中心（`node`，朝向不限）、而且沒有剩下的 continuation 時，停在該站。`stationStops` 依車站 ID 遞增列出；未知、未放置、在連結上、continuation 還有剩（經過、出發中，即使 rate 為 0，或等待修復）的列車是空陣列。

時刻表規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 19）：

- 新購列車的時刻表是 `[]`。`setTrainTimetable` 整份替換，`[]` 清除；免費，列車放置與否都可以。
- 時間從 0 起不倒流：每一站 `0 <= arrival <= departure`，而且 `departure <= 下一站的 arrival`。允許相等（停留 0 分鐘、在前一站離開的同一分鐘到達）、重複的車站、沒有月台的車站與已經過去的時間。不檢查路線、行駛時間或列車位置。
- 檢查順序：`unknownTrain` → `invalidTimetable` → `unknownStation`（依時刻表順序第一個不存在的車站）。被拒絕時時刻表與世界完全不變。
- 時刻表不影響任何其他狀態：放置、取下、反向、`setTrainMovementRate`、`setTrainContinuation` 與 `advance` 都保留它，而且它不會讓列車出發、停留、求路或改變 rate。`train` 觀察只回答位置與 movement；時刻表以 `timetable` 觀察讀取。

### 最終狀態

- `stations`：`{ "id", "name", "x", "y" }`，依 ID 遞增。
- `tracks`：`{ "x", "y", "connections" }`，逐列由北到南、每列由西到東。
- `trains`：`{ "id", "name", "position", "movement", "timetable" }`，依 ID 遞增；`position`、`movement`、`timetable` 的形式見上面「列車位置」「列車移動」「時刻表」。

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
- **3**（Phase 3 Stage J）：新增 `placeTrain`、`unplaceTrain`、`reverseTrain` 指令，`trackInUse`、`unknownTrain`、`trainAlreadyPlaced`、`trainNotPlaced`、`invalidTrainPosition` 結果，最終狀態每台列車新增必填的 `position`，以及 `train-position.json`。既有的三個 fixture 把 `schemaVersion` 從 2 改成 3；`build-starter-line.json` 唯一的列車（`Local 1`，從未放置）加上 `"position": { "type": "unplaced" }`。它們的指令、結果、時間、金額、軌道、車站與 ID 預期值都沒有改變。
- **4**（Phase 3 Stage K）：新增 `setTrainMovementRate`、`setTrainContinuation` 指令，`invalidMovementRate`、`invalidContinuation`、`clockOverflow` 結果，`train` 觀察，最終狀態每台列車新增必填的 `movement`，以及 `train-movement.json`。既有的四個 fixture 把 `schemaVersion` 從 3 改成 4，並為 `build-starter-line.json` 的 1 台與 `train-position.json` 的 4 台列車加上 `"movement": { "rate": 0, "continuation": [], "cursor": 0 }`：這些列車從未設定 rate，Stage K 的規則下也保持 idle，所以時間推進時仍不移動。它們的指令、結果、時間、金額、軌道、車站、ID 與位置預期值都沒有改變。
- **5**（Phase 3 Stage L）：新增 `route` 觀察與 `train-route.json`。既有的五個 fixture 只把 `schemaVersion` 從 4 改成 5，其他預期值都沒有改變。
- **6**（ID 用盡）：新增 `idsExhausted` 結果。既有的六個 fixture 只把 `schemaVersion` 從 5 改成 6，其他預期值都沒有改變。
- **7**（Phase 3 Stage N）：新增 `platforms`、`routeToStation`、`stationStops` 觀察與 `station-stop.json`。既有的六個 fixture 只把 `schemaVersion` 從 6 改成 7，其他預期值都沒有改變。
- **8**（Phase 4 Stage O）：新增 `setTrainTimetable` 指令，`invalidTimetable`、`unknownStation` 結果，`timetable` 觀察，最終狀態每台列車新增必填的 `timetable`，以及 `train-timetable.json`。既有的七個 fixture 把 `schemaVersion` 從 7 改成 8，並為最終狀態的 12 台列車（`build-starter-line.json` 1 台、`station-stop.json` 2 台、`train-movement.json` 3 台、`train-position.json` 4 台、`train-route.json` 2 台）加上 `"timetable": []`：這些列車從未設定時刻表，新購列車的時刻表是空的。它們的指令、結果、觀察、時間、金額、軌道、車站、ID、位置與 movement 預期值都沒有改變（`train` 觀察沒有加入時刻表）。讀取端只接受 8。
