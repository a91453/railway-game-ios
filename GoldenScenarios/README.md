# Golden Scenarios

可移植的行為 fixture：每個 JSON 檔是一個完整情境，包含起始世界、依序執行的指令與每個指令應有的結果、在指令之間進行的唯讀觀察與應有的答案，以及最後應該得到的世界狀態。預期結果是**手寫並經過 review 的**，測試只讀取、從不寫回。

Swift 參考實作：`Tests/GameCoreTests/GoldenScenario.swift`（讀取與執行）、`GoldenScenarioTests.swift`（`swift test` 會跑這個目錄下所有 `*.json`）。未來其他語言的 GameCore 移植版必須從**同一批檔案**得到同樣的結果。架構背景見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 13。

## 執行一個情境

1. 以 `initialState` 建立世界。
2. 依序執行 `steps`：
   - 指令步驟：實際結果必須等於 `expect`；被拒絕的指令不得改變世界的任何狀態。
   - 觀察步驟：向執行到這一步為止的世界提出唯讀查詢，答案必須等於 `expect`。觀察不是指令，不會改變世界。
3. 全部執行完後，世界必須等於 `expectedFinalState`。

## Schema（`schemaVersion: 12`）

除了每個步驟在 `command` 與 `observe` 之間擇一，所有欄位都必填。讀取端遇到不認得的 `schemaVersion`、指令、觀察、結果或方向名稱必須報錯，不可猜測。不要加入 schema 沒有定義的欄位，同一個物件裡也不要重複 key：目前的 Swift 讀取端會忽略多出的欄位、各語言對重複 key 保留的值也不同，兩者都還沒有自動檢查。

| 欄位 | 內容 |
| --- | --- |
| `schemaVersion` | `12` |
| `description` | 這個情境驗證什麼（給人看） |
| `initialState` | `mapWidth`、`mapHeight`、`balance`、`costs`（`track` / `station` / `train`）、`gameMinutes`、`speed` |
| `steps` | 依序執行的陣列；每一步是指令 `{ "command": {...}, "expect": {...} }` 或觀察 `{ "observe": {...}, "expect": {...} }`，恰好擇一 |
| `expectedFinalState` | `gameMinutes`、`speed`、`balance`、`stations`、`tracks`、`trains`、`lines`、`serviceDay` |

### 值的表示

- **整數**：所有數字都是整數，寫成純十進位（不寫 `1.0`、`1e3`），絕對值不超過 2^53 − 1。有些語言的 JSON 讀取器把數字一律讀成 double，這個範圍內才保證精確；`testFixturesUsePortableJSON` 會檢查。
- **金額**（`balance`、`costs`、`required`、`available`）：整數遊戲貨幣單位（GameCore 的 `Money`），沒有小數；`costs` 不可為負數。
- **時間**：`gameMinutes` 與時刻表的 `arrival`、`departure` 都是開局以來的遊戲分鐘；`ticks` 是模擬 tick 數。每個 tick 在 `paused` / `normal` / `double` 下推進 0 / 1 / 2 分鐘。
- **位置**：`x`、`y` 是格子座標，`x` 向東、`y` 向南，`(0, 0)` 是西北角。
- **方向**：`"north"`、`"east"`、`"south"`、`"west"`；陣列順序不影響意義，同一方向不可重複。
- **速度**：`"paused"`、`"normal"`、`"double"`。
- **布林值**：JSON 的 `true` / `false`（用在觀察的答案與停靠的 `reverse`）。
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
- **時刻表**：依序的停靠陣列 `[{ "station", "arrival", "departure", "reverse" }, ...]`，四個欄位都必填：前三個是整數，`reverse` 是布林值（服務離開這一站時是否先讓列車折返）；**順序有意義**（陣列順序就是停靠順序）。沒有時刻表是 `[]`。指令裡的停靠照原樣讀取、不檢查，是否合法由 GameCore 判定，所以 fixture 可以預期負數時間被拒絕。
- **重複（repeat）**：以 `type` 區分兩種，只能出現該種類的欄位：
  - `{ "type": "once" }`：時刻表只跑一次（新購列車與 Stage Q1 之前的行為）。
  - `{ "type": "every", "minutes" }`：時刻表每 `minutes` 分鐘重複一次；整數，指令裡照原樣讀取，是否合法由 GameCore 判定。
- **服務（execution）**：以 `type` 區分三種，只能出現該種類的欄位：
  - `{ "type": "inactive" }`：沒有執行中的服務。
  - `{ "type": "waiting", "stop", "cycle" }`：停在時刻表第 `stop` 站，等待它在第 `cycle` 輪的排定出發。
  - `{ "type": "travelling", "stop", "cycle" }`：已離開前一站（`stop` 為 0 時是上一輪的最後一站），正前往第 `cycle` 輪的第 `stop` 站。
  - `stop` 是從 0 開始的**時刻表索引**，不是車站 ID（時刻表可以重複同一個車站）。
  - `cycle` 是重複的時刻表已經重新開始的次數，從 0 起；第 `k` 輪的每個時刻是時刻表記錄的時刻加上 `k × minutes`。只跑一次的時刻表永遠是 0。
- **服務等級**：`"peak"`、`"offPeak"`、`"low"`（尖峰、離峰、低峰）。
- **線路**：`{ "id", "name", "stops", "rate", "window", "trainsInService", "targetHeadways", "trains", "lastDispatch" }`，九個欄位都必填：
  - `id`：線路 ID，世界依序配發，從 1 開始、失敗的指令不消耗 ID、刪除的線路 ID 不再使用。指令、結果與觀察以 `line` 欄位寫線路 ID。
  - `stops`：依序停靠的車站 ID 陣列。列車從第一站開到最後一站再折返回來。
  - `rate`：計算行程時間用的速度（每分鐘的邏輯單位）。
  - `window`：營運時間，以 `type` 區分：`{ "type": "allDay" }`，或 `{ "type": "hours", "open", "close" }`（一天中的分鐘，`close` 可以超過 1440，也就是隔天清晨）。
  - `trainsInService`：`{ "peak", "offPeak", "low" }`，各服務等級要跑的列車數。
  - `targetHeadways`：`{ "peak", "offPeak", "low" }`，三個 key 都必填；各等級的目標班距（分鐘），沒有目標的等級是 `null`，由 `trainsInService` 決定。
  - `trains`：指派給這條線路的列車 ID，依 ID 遞增；沒有是 `[]`。
  - `lastDispatch`：線路上次從第一站派出列車的遊戲分鐘；從未派車是 `null`。
  - 指令裡的線路值照原樣讀取、不檢查，是否合法由 GameCore 判定。
- **服務日**：`[{ "start", "level" }, ...]`，每一段從一天中的某分鐘開始，到下一段開始為止。
- **線路行程**：`{ "start", "legs", "roundTripMinutes" }`。`start` 是列車位置（`node`）；`legs` 是 `[{ "from", "to", "route", "minutes" }, ...]`，`from`、`to` 是線路 `stops` 的索引，`route` 是 `[{ "x", "y" }, ...]`。

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
| `setTrainTimetable` | `train`、`timetable`（停靠陣列，可為空陣列）、`repeat` | `setTrainTimetable(_:to:repeatingEvery:)`（`once` 傳 `nil`） |
| `startTrainService` | `train` | `startTrainService(_:)` |
| `stopTrainService` | `train` | `stopTrainService(_:)` |
| `createLine` | `name`、`stops` | `createLine(named:stops:)` |
| `removeLine` | `line` | `removeLine(_:)` |
| `setLineStops` | `line`、`stops` | `setLineStops(_:to:)` |
| `setLineRate` | `line`、`rate` | `setLineRate(_:to:)` |
| `setLineServiceWindow` | `line`、`window` | `setLineServiceWindow(_:to:)` |
| `setLineTrainsInService` | `line`、`trains`（`{ "peak", "offPeak", "low" }`） | `setLineTrainsInService(_:to:)` |
| `setServiceDay` | `bands`（`[{ "start", "level" }, ...]`） | `setServiceDay(_:)` |
| `setLineTargetHeadways` | `line`、`targetHeadways`（`{ "peak", "offPeak", "low" }`，分鐘或 `null`） | `setLineTargetHeadways(_:to:)` |
| `assignTrain` | `train`、`line` | `assignTrain(_:to:)` |
| `unassignTrain` | `train` | `unassignTrain(_:)` |
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
| `trainNotPlaced` | `train` | 列車不在鐵軌上，無法取下、反向、設定 rate 或 continuation，也無法啟動服務 |
| `invalidTrainPosition` | — | 位置不是地圖內的鐵軌格，或不是兩格相接鐵軌之間、`0 < offset < 1024` 的連結 |
| `invalidMovementRate` | — | rate 是負數 |
| `invalidContinuation` | — | continuation 有一步與前一個節點不相接，或立即折返 |
| `clockOverflow` | — | 推進後的遊戲分鐘超出時鐘上限（`Int64`），整批不執行。可移植整數（≤ 2^53 − 1）無法表達這個情境，目前只在 Swift 單元測試驗證 |
| `idsExhausted` | — | 這類 ID（車站或列車）已配發到最後一個（`Int.max − 1`），建造或購買整個不執行、不扣款。fixture 只能從 1 開始配發，無法走到這裡，目前只在 Swift 單元測試驗證 |
| `invalidMapSize` | `width`、`height` | 地圖尺寸不支援（目前指令不會產生） |
| `invalidTimetable` | — | 時刻表的時間倒流：某站 `arrival` 為負數或晚於 `departure`，或某站 `arrival` 早於前一站的 `departure`；或重複的週期不合法：時刻表是空的、週期小於 1，或最後一站的 `departure` 晚於下一輪第一站的 `arrival` |
| `unknownStation` | `station` | 時刻表的這一站不是存在的車站（依時刻表順序的第一個） |
| `trainServiceActive` | `train` | 列車正在執行時刻表服務：不能再啟動、設定 continuation、反向、取下或替換時刻表，要先停止服務 |
| `trainServiceNotActive` | `train` | 列車沒有執行中的服務可以停止 |
| `noTimetable` | `train` | 列車沒有時刻表，無法啟動服務 |
| `trainNotAtFirstStop` | `train` | 列車沒有停在時刻表第一站的車站，無法啟動服務 |
| `unknownLine` | `line` | 沒有這個 ID 的線路 |
| `invalidLineStops` | — | 線路少於兩站，或同一個車站連續出現兩次 |
| `invalidLineRate` | — | 線路的 rate 小於 1 |
| `invalidServiceWindow` | — | 營運時間不合法：`open` 不在 0…1439，`close` 不晚於 `open`，或晚於 1800（隔天 06:00） |
| `invalidTrainsInService` | — | 某個服務等級的列車數是負數 |
| `invalidServiceDay` | — | 服務日不從分鐘 0 開始，或各段的開始時間沒有在一天內嚴格遞增 |
| `invalidHeadway` | — | 某個等級的目標班距不在 2…1440 分鐘 |
| `trainOnLine` | `train` | 列車屬於一條線路：由線路設定它的時刻表、啟動它的服務，不能手動設定時刻表、啟動或停止服務，也不能再指派一次，要先取回 |
| `trainNotOnLine` | `train` | 列車不屬於任何線路，沒有可以取回的 |

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
| `execution` | `train` | `{ "execution": { "type", ... } }`（見上面「服務」） | `train(id:)?.execution` |
| `serviceLevel` | `line`、`gameMinutes` | `{ "level": "peak" }`，停止營運或沒有這條線路時是 `"closed"` | `serviceLevel(of:at:)` |
| `lineJourney` | `line` | `{ "found": true, "journey": {...} }` 或 `{ "found": false }` | `lineJourney(_:)` |
| `lineMaximumTrains` | `line` | `{ "found": true, "trains": n }` 或 `{ "found": false }` | `lineMaximumTrains(_:)` |
| `lineTrainsInService` | `line`、`level` | 與 `lineMaximumTrains` 相同 | `lineTrainsInService(_:at:)` |
| `lineHeadway` | `line`、`level` | `{ "found": true, "minutes": n }` 或 `{ "found": false }` | `lineHeadway(_:at:)` |

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
- 重複的時刻表（決策 21）：`repeat` 為 `every` 時，時刻表至少要有一站、週期至少 1 分鐘，而且重新開始時時間不倒流：最後一站的 `departure` 不晚於第一站的 `arrival` 加上週期（兩者可以相等）。`once` 的時刻表沒有這些限制。設定時刻表同時設定它的重複方式，`[]` 與 `once` 清除兩者。
- 檢查順序：`unknownTrain` → `invalidTimetable`（時間與週期）→ `unknownStation`（依時刻表順序第一個不存在的車站）。被拒絕時時刻表、週期與世界完全不變。
- 時刻表不影響任何其他狀態：放置、取下、反向、`setTrainMovementRate`、`setTrainContinuation` 與 `advance` 都保留它；沒有啟動服務時，它不會讓列車出發、停留、求路或改變 rate。`train` 觀察只回答位置與 movement；時刻表以 `timetable` 觀察讀取。服務執行中，`setTrainTimetable` 在 `unknownTrain` 之後先檢查 `trainServiceActive`。

服務規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 20、21）：

- `startTrainService` 的檢查順序：`unknownTrain` → `trainServiceActive` → `noTimetable` → `trainNotPlaced` → `trainNotAtFirstStop`（列車必須依上面的停站規則停在第一站的車站；共用月台時包含即可）。成功後是第 0 站的 `waiting`，其他都不變；從第 0 站開始，不跳站。`once` 的時刻表在第 0 輪（即使時間都已過去）；`every` 的時刻表在第一站出發時刻不早於目前時間的第一輪（剛好等於也算），若連最後一個時刻放得下的一輪都已過去，就是那一輪。`stopTrainService`：`unknownTrain` → `trainServiceNotActive`，只把服務變成 `inactive`，時刻表、週期、位置、rate 與 continuation 都保留。
- 服務依時刻表順序執行：`once` 跑一次；`every` 跑完最後一站後接著跑下一輪的第 0 站，直到某一輪的時刻超出遊戲分鐘的上限（`Int64`）為止。服務不改 rate，只在 `reverse` 為 `true` 的站折返。
- 每個基本步長（分鐘 `T` → `T + 1`）依序是：出發（`T`）→ 移動 → 時間 +1 → 到達（`T + 1`），每一段都依列車 ID 順序處理。
  - 出發：`waiting` 且該站在該輪的 `departure <= T` 的服務離開。`reverse` 為 `true` 的站先讓列車在原地折返（與 `reverseTrain` 相同），之後的處理從折返後的位置開始。下一個停靠是同一輪的下一站；最後一站之後，`every` 的時刻表是下一輪的第 0 站（那一輪的時刻放得下時）。沒有下一個停靠（`once` 的最後一站，或最後一輪的最後一站）：服務變成 `inactive`，列車留在原地（有 `reverse` 時已折返）。否則以 `routeToStation` 的同一個規則求路到下一個停靠的車站：空路徑表示已停在那一站（重複的車站、共用月台、回到起點的重複時刻表），立即成為那一站的 `waiting`，若它的出發也已到就在同一段繼續；非空路徑成為 continuation（`cursor` 0），服務成為 `travelling`；沒有路就維持 `waiting`，**也不折返**，之後的步長再試（屆時再折返一次）。每台列車在一個出發段最多離開時刻表站數那麼多站：`once` 的時刻表全部，`every` 的最多一整輪，剩下的在下一步繼續。
  - 到達：`travelling` 的列車若停在該站的車站，就成為該站的 `waiting`。
  - 因此列車不會早於排定出發時刻離開，也不另加停留：早到的等到出發時刻，晚到的下一個步長就走；在某一步到達的列車最早在下一步離開。排定的 `arrival` 不影響行為。
- 服務執行中，`setTrainContinuation`、`reverseTrain`、`unplaceTrain` 在 `unknownTrain` → `trainNotPlaced` 之後是 `trainServiceActive`（`setTrainContinuation` 早於 `invalidContinuation`）；`setTrainMovementRate` 照常可用。行駛中前方鐵軌被拆時照移動規則等待，不重新求路。
- 一次 `advance` 推進多個 tick 與逐 tick 推進的結果相同，也不會跳過任何出發時刻。

線路規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 22）：

- 線路是計畫資料：不移動、不求路、不排班任何列車。新線路的營運時間是 06:00–24:00（`{ "type": "hours", "open": 360, "close": 1440 }`），`rate` 是 1024，各等級都是 0 台。
- 檢查順序：`createLine` 是 `invalidName` → `invalidLineStops` → `unknownStation`（第一個不存在的車站）→ `idsExhausted`；其他線路指令先檢查 `unknownLine`，再檢查自己的值；`setLineStops` 的 `unknownStation` 在 `invalidLineStops` 之後。
- 新世界的服務日：0 起低峰、420 起尖峰、600 起離峰、960 起尖峰、1200 起離峰、1260 起低峰。
- `serviceLevel`：營運時間內是服務日在那一分鐘的等級，否則是 `"closed"`。一天中的分鐘是 `gameMinutes` 除以 1440 的非負餘數。營運時間從 `open` 到 `close`，`open` 之前的分鐘算作隔天的（加 1440）。
- `lineJourney`：從第一站的一個月台出發，依序以 `routeToStation` 的規則求路到每一站；到最後一站原地折返，再依相反順序回到第一站。
  - 起點會試遍第一站的每個月台（依 `platforms` 的順序）、朝北、東、南、西，取來回時間最短的，同樣時取最先的。
  - 每一段的分鐘數是連結數 × 1024 ÷ `rate`，無條件進位。
  - 來回時間是各段加上停留：兩端之間的每一站去回各 1 分鐘，兩端各 2 分鐘。
  - 任何一段沒有路時是 `{ "found": false }`。
- `lineMaximumTrains`：來回時間 ÷ 2（最短班距 2 分鐘），無條件捨去，至少 1。
- `lineTrainsInService`：該等級設定的列車數，但不超過 `lineMaximumTrains`。該等級有目標班距時，是來回時間 ÷ 目標班距（無條件進位），同樣不超過 `lineMaximumTrains`。
- `lineHeadway`：來回時間 ÷ 該等級的列車數，無條件進位；有目標班距時是目標班距，但不短於前者。沒有列車時是 `{ "found": false }`。

### 最終狀態

- `stations`：`{ "id", "name", "x", "y" }`，依 ID 遞增。
- `tracks`：`{ "x", "y", "connections" }`，逐列由北到南、每列由西到東。
- `trains`：`{ "id", "name", "position", "movement", "timetable", "repeat", "execution" }`，依 ID 遞增；`position`、`movement`、`timetable`、`repeat`、`execution` 的形式見上面「列車位置」「列車移動」「時刻表」「重複」「服務」。
- `lines`：線路（形式見上面「線路」），依 ID 遞增；沒有線路是 `[]`。
- `serviceDay`：服務日（形式見上面「服務日」）。

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
- **8**（Phase 4 Stage O）：新增 `setTrainTimetable` 指令，`invalidTimetable`、`unknownStation` 結果，`timetable` 觀察，最終狀態每台列車新增必填的 `timetable`，以及 `train-timetable.json`。既有的七個 fixture 把 `schemaVersion` 從 7 改成 8，並為最終狀態的 12 台列車（`build-starter-line.json` 1 台、`station-stop.json` 2 台、`train-movement.json` 3 台、`train-position.json` 4 台、`train-route.json` 2 台）加上 `"timetable": []`：這些列車從未設定時刻表，新購列車的時刻表是空的。它們的指令、結果、觀察、時間、金額、軌道、車站、ID、位置與 movement 預期值都沒有改變（`train` 觀察沒有加入時刻表）。
- **9**（Phase 4 Stage P）：新增 `startTrainService`、`stopTrainService` 指令，`trainServiceActive`、`trainServiceNotActive`、`noTimetable`、`trainNotAtFirstStop` 結果，`execution` 觀察，最終狀態每台列車新增必填的 `execution`，以及 `train-service.json`。既有的八個 fixture 把 `schemaVersion` 從 8 改成 9，並為最終狀態的 14 台列車（`build-starter-line.json` 1 台、`station-stop.json` 2 台、`train-movement.json` 3 台、`train-position.json` 4 台、`train-route.json` 2 台、`train-timetable.json` 2 台）加上 `"execution": { "type": "inactive" }`：這些列車從未啟動服務，新購列車沒有服務。它們的指令、結果、觀察、時間、金額、軌道、車站、ID、位置、movement 與時刻表預期值都沒有改變（`train-timetable.json` 裡停在排定車站、時間超過出發時刻仍不動的列車，因為沒有啟動服務，行為不變）。
- **10**（Phase 4 Stage Q1）：時刻表的每一站新增必填的 `reverse`，`setTrainTimetable` 指令與最終狀態每台列車新增必填的 `repeat`，`waiting`、`travelling` 服務新增必填的 `cycle`，`invalidTimetable` 也涵蓋不合法的週期，以及 `train-repeat.json`。既有的九個 fixture 把 `schemaVersion` 從 9 改成 10，並只加上中性的值：`train-service.json` 與 `train-timetable.json` 裡每個停靠（指令、`timetable` 觀察與最終狀態）加上 `"reverse": false`，22 個 `setTrainTimetable` 指令加上 `"repeat": { "type": "once" }`，最終狀態的 16 台列車加上 `"repeat": { "type": "once" }`，`train-service.json` 裡 15 個 `waiting` / `travelling` 服務（觀察與最終狀態）加上 `"cycle": 0`。這些值就是 Stage Q1 之前唯一的行為（不折返、只跑一次、第 0 輪），所以其他預期值都沒有改變。
- **11**（Phase 4 Stage Q2a）：新增 `createLine`、`removeLine`、`setLineStops`、`setLineRate`、`setLineServiceWindow`、`setLineTrainsInService`、`setServiceDay` 指令，`unknownLine`、`invalidLineStops`、`invalidLineRate`、`invalidServiceWindow`、`invalidTrainsInService`、`invalidServiceDay` 結果，`serviceLevel`、`lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway` 觀察，最終狀態必填的 `lines` 與 `serviceDay`，以及 `service-line.json`。既有的十個 fixture 把 `schemaVersion` 從 10 改成 11，並在最終狀態加上 `"lines": []` 與新世界的服務日：它們從未建立線路，也沒有改變服務日。其他預期值都沒有改變。
- **12**（Phase 4 Stage Q2b）：新增 `setLineTargetHeadways`、`assignTrain`、`unassignTrain` 指令，`invalidHeadway`、`trainOnLine`、`trainNotOnLine` 結果，線路必填的 `targetHeadways`、`trains`、`lastDispatch`，以及 `line-dispatch.json`。`advance` 在每個基本步長的出發之前讓線路派車，但只派指派給線路的列車。既有的十一個 fixture 把 `schemaVersion` 從 11 改成 12；`service-line.json` 最終狀態的兩條線路加上 `"targetHeadways": { "peak": null, "offPeak": null, "low": null }`、`"trains": []`、`"lastDispatch": null`：它們沒有目標班距、沒有列車，所以從未派車。其他預期值都沒有改變。讀取端只接受 12。
