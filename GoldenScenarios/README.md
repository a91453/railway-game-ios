# Golden Scenarios

可移植的行為 fixture：每個 JSON 檔是一個完整情境，包含起始世界、依序執行的指令與每個指令應有的結果、在指令之間進行的唯讀觀察與應有的答案，以及最後應該得到的世界狀態。預期結果是**手寫並經過 review 的**，測試只讀取、從不寫回。

Swift 參考實作：`Tests/GameCoreTests/GoldenScenario.swift`（讀取與執行）、`GoldenScenarioTests.swift`（`swift test` 會跑這個目錄下所有 `*.json`）。未來其他語言的 GameCore 移植版必須從**同一批檔案**得到同樣的結果。架構背景見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 13。

## 執行一個情境

1. 以 `initialState` 建立世界。
2. 依序執行 `steps`：
   - 指令步驟：實際結果必須等於 `expect`；被拒絕的指令不得改變世界的任何狀態。
   - 觀察步驟：向執行到這一步為止的世界提出唯讀查詢，答案必須等於 `expect`。觀察不是指令，不會改變世界。
3. 全部執行完後，世界必須等於 `expectedFinalState`。

## Schema（`schemaVersion: 26`）

除了每個步驟在 `command` 與 `observe` 之間擇一，線路指令與觀察可以省略的 `pattern`（見下面「服務模式」），`routeToStation` 可以省略的 `cars`（見下面「車站設施」），`buildTrackEdge` 可以省略的 `profile` 與 `structure`（見下面「立體鐵路」），`setTrainPath`、列車移動與路徑可以省略的 `end`、`pathToStation` 可以省略的 `cars`（見下面「路網上的營運」），時鐘的 `gameMinutes` 與 `gameSeconds` 二擇一、最終狀態可以省略的 `pendingTenths`、時刻表停靠的 `arrival` 與 `arrivalSeconds`、`departure` 與 `departureSeconds` 各二擇一（見下面「時間」），列車沒有服務時省略的 `times`（見下面「服務時刻」），以及標準性能時省略的列車與線路的 `performance`、沒有行駛曲線時省略的服務時刻 `run`（見下面「行駛曲線」），所有欄位都必填。讀取端遇到不認得的 `schemaVersion`、指令、觀察、結果或方向名稱必須報錯，不可猜測。不要加入 schema 沒有定義的欄位，同一個物件裡也不要重複 key：目前的 Swift 讀取端會忽略多出的欄位、各語言對重複 key 保留的值也不同，兩者都還沒有自動檢查。

| 欄位 | 內容 |
| --- | --- |
| `schemaVersion` | `26` |
| `description` | 這個情境驗證什麼（給人看） |
| `initialState` | `mapWidth`、`mapHeight`、`balance`、`costs`（`track` / `station` / `train`）、`gameMinutes` 或 `gameSeconds`、`speed` |
| `steps` | 依序執行的陣列；每一步是指令 `{ "command": {...}, "expect": {...} }` 或觀察 `{ "observe": {...}, "expect": {...} }`，恰好擇一 |
| `expectedFinalState` | `gameMinutes` 或 `gameSeconds`、`pendingTenths`（可以省略）、`speed`、`balance`、`stations`、`tracks`、`trains`、`lines`、`serviceDay`、`network`、`trafficControl`、`passengers`、`riders`、`accounts` |

### 值的表示

- **整數**：所有數字都是整數，寫成純十進位（不寫 `1.0`、`1e3`），絕對值不超過 2^53 − 1。有些語言的 JSON 讀取器把數字一律讀成 double，這個範圍內才保證精確；`testFixturesUsePortableJSON` 會檢查。
- **金額**（`balance`、`costs`、`required`、`available`）：整數遊戲貨幣單位（GameCore 的 `Money`），沒有小數；`costs` 不可為負數。
- **時間**（schema 23，Stage W2a 起 GameCore 的時鐘以秒計，決策 37；schema 24 起時刻表與服務時刻可以落在兩分鐘之間，決策 39）：
  - 時鐘寫成 `gameMinutes`（開局以來的整分鐘）或 `gameSeconds`（開局以來的秒），恰好其中一個。整分鐘一律寫成 `gameMinutes`，`gameSeconds` 只用在落在兩分鐘之間的時刻，所以每個時刻只有一種寫法。
  - 其他時間欄位仍然是分鐘：時刻表的 `arrival`、`departure` 與重複的 `minutes`、`lastDispatch`、`since`、`openedAt`、帳本列的 `time`、`serviceLevel` 的 `gameMinutes`。GameCore 以秒保存它們（分鐘 × 60）。
  - 時刻表停靠的時間（schema 24，Stage W2b）可以落在兩分鐘之間：線路的時刻表在派車 42 秒後才離開第一站。這樣的時間寫成 `arrivalSeconds`、`departureSeconds`（開局以來的秒），取代 `arrival`、`departure`；和時鐘一樣，整分鐘一律寫成分鐘，每一站的到達與離開各恰好一種寫法。
  - 服務時刻（`times`，schema 24）一律是開局以來的秒。
  - `ticks` 是模擬 tick 數。每個 tick 在 `paused` / `x1` / `x10` / `x60` / `normal` / `double` 下推進 0 / 0.1 / 1 / 6 / 60 / 120 秒（宿主每 100 ms 一個 tick，所以 `x1` 是真實時間）。不到一秒的部分累積在 `pendingTenths`（十分之一秒，1 到 9），跨過速度的改變與暫停；是 0 時不寫這個 key。
- **位置**：`x`、`y` 是格子座標，`x` 向東、`y` 向南，`(0, 0)` 是西北角。
- **方向**：`"north"`、`"east"`、`"south"`、`"west"`；陣列順序不影響意義，同一方向不可重複。
- **速度**：`"paused"`、`"x1"`、`"x10"`、`"x60"`（schema 23）、`"normal"`、`"double"`。
- **布林值**：JSON 的 `true` / `false`（用在觀察的答案、停靠的 `reverse`、`setTrafficControl` 的 `enabled` 與最終狀態的 `trafficControl`）。
- **ID**：車站、列車 ID 是世界依序配發的整數，從 1 開始、失敗的指令不消耗 ID。列車指令與結果以 `train` 欄位寫列車 ID；車站觀察、時刻表的停靠與 `unknownStation` 結果以 `station` 欄位寫車站 ID。
- **列車位置**：以 `type` 區分四種，只能出現該種類的欄位，多出別種的欄位必須報錯：
  - `{ "type": "unplaced" }`：未放置（出現在最終狀態與 `train` 觀察的答案；放置指令不能用它）。
  - `{ "type": "node", "x", "y", "heading" }`：停在該格鐵軌中心，面向 `heading`（方向名稱）。
  - `{ "type": "link", "from": { "x", "y" }, "to": { "x", "y" }, "offset" }`：在 `from`、`to` 兩格中心之間，距 `from` `offset` 單位，面向 `to`。
  - `{ "type": "edge", "edge", "direction", "offset" }`（schema 16）：在連續路網第 `edge` 條邊上，`direction` 是 `"forward"`（從邊的 `from` 節點往 `to`）或 `"backward"`，`offset` 是從這個方向的起點量起的距離，`0 <= offset <=` 邊長。有車身的列車（2 節以上）`offset` 必須大於 0：在節點時寫成「沿著剛走完的邊到達終點」（`offset` 等於邊長）。
  - 相鄰兩格中心的距離固定是 **1024 單位**（抽象格距，不是公尺或像素）。合法的 `link` 必須 `0 < offset < 1024`；恰好在格子中心一律寫成 `node`。指令裡的位置照原樣讀取、不檢查也不正規化，是否合法由 GameCore 判定，所以 fixture 可以預期 `offset` 為 0 的放置被拒絕。
- **列車移動**：`{ "rate", "continuation": [{ "x", "y" }, ...], "cursor", "edges" }`，四個欄位都必填；路網上的路停在最後一條邊的中段時另有 `end`（schema 18）。
  - `rate`：每遊戲分鐘可走的單位數，非負整數；Stage W2a 起分到這一分鐘的每一秒（見下面「列車移動規則」）。
  - `continuation`：列車之後依序要進入的節點，完整列出（包含已進入的項）；起點是列車所在節點或目前連結的 `to`，這個節點本身不列入。
  - `cursor`：已開始進入的項數。恰好抵達節點不算進入下一項。全部項目都進入後存成 `[]`、`cursor` 0。
  - `edges`（schema 16）：連續路網上的列車之後依序要進入的邊（邊的編號），完整列出（包含已進入的項），`cursor` 數的就是這一份；方格上的列車是 `[]`，路網上的列車 `continuation` 是 `[]`。
  - `end`（schema 18）：路網上的列車在路的最後一條邊（`edges` 的最後一項；用完時就是車頭所在的邊）上停下的位置，沿行進方向從它的起點量起；走到那條邊的終點時**不寫**這個 key（不可寫 `null`）。方格上的列車永遠沒有 `end`。
  - 未放置或從未設定過的列車是 `{ "rate": 0, "continuation": [], "cursor": 0, "edges": [] }`。
- **時刻表**：依序的停靠陣列 `[{ "station", "arrival", "departure", "reverse" }, ...]`，四個欄位都必填（落在兩分鐘之間的時間改寫成 `arrivalSeconds` 或 `departureSeconds`，見上面「時間」）：前三個是整數，`reverse` 是布林值（服務離開這一站時是否先讓列車折返）；**順序有意義**（陣列順序就是停靠順序）。沒有時刻表是 `[]`。指令裡的停靠照原樣讀取、不檢查，是否合法由 GameCore 判定，所以 fixture 可以預期負數時間被拒絕。
- **重複（repeat）**：以 `type` 區分兩種，只能出現該種類的欄位：
  - `{ "type": "once" }`：時刻表只跑一次（新購列車與 Stage Q1 之前的行為）。
  - `{ "type": "every", "minutes" }`：時刻表每 `minutes` 分鐘重複一次；整數，指令裡照原樣讀取，是否合法由 GameCore 判定。
- **服務（execution）**：以 `type` 區分三種，只能出現該種類的欄位：
  - `{ "type": "inactive" }`：沒有執行中的服務。
  - `{ "type": "waiting", "stop", "cycle" }`：停在時刻表第 `stop` 站（第 `cycle` 輪），停站到可以離開為止（Stage W2b：開門、上下車、等排定出發、關門，見下面「服務時刻」）。
  - `{ "type": "travelling", "stop", "cycle" }`：已離開前一站（`stop` 為 0 時是上一輪的最後一站），正前往第 `cycle` 輪的第 `stop` 站。
  - `stop` 是從 0 開始的**時刻表索引**，不是車站 ID（時刻表可以重複同一個車站）。
  - `cycle` 是重複的時刻表已經重新開始的次數，從 0 起；第 `k` 輪的每個時刻是時刻表記錄的時刻加上 `k × minutes`。只跑一次的時刻表永遠是 0。
- **服務時刻（times）**（schema 24，Stage W2b，決策 39）：`{ "arrival", "exchangeEnd", "closing", "departure", "run" }`，時刻都是開局以來的秒；`arrival` 必填，另外四個只在有值時寫（不可寫 `null`）。
  - `arrival`：到達正在等待的這一站（行駛中則是上一個等待過的站）的時刻；啟動服務與線路派車算是在那一刻到達第一站。
  - `exchangeEnd`：只在等待時、車門開好之後才有：乘客上下車到哪一刻為止。
  - `closing`：只在等待時：開始關門的時刻；離開是它的 9 秒後。
  - `departure`：實際離開前一站的時刻；這個服務還沒離開過任何一站時沒有。
  - `run`（schema 25，Stage W2c，決策 40）：只在行駛中、列車跟著行駛曲線時有：`{ "start", "length", "seconds" }`，列車在 `start`（開局以來的秒）出發，用 `seconds` 秒（1 到 4294967）走完 `length` 單位（至少 1）到下一站的停車位置（見下面「行駛曲線」）。
- **服務等級**：`"peak"`、`"offPeak"`、`"low"`（尖峰、離峰、低峰）。
- **線路**：`{ "id", "name", "stops", "performance", "window", "trainsInService", "targetHeadways", "trains", "lastDispatch", "patterns" }`，除了 `performance` 都必填：
  - `id`：線路 ID，世界依序配發，從 1 開始、失敗的指令不消耗 ID、刪除的線路 ID 不再使用。指令、結果與觀察以 `line` 欄位寫線路 ID。
  - `stops`：依序停靠的車站 ID 陣列。列車從第一站開到最後一站再折返回來。
  - `performance`（schema 25，Stage W2c，取代以前的 `rate`）：規劃行程時間用的性能（形式見下面「行駛曲線」）；標準性能時省略，不可寫 `null`。
  - `window`：營運時間，以 `type` 區分：`{ "type": "allDay" }`，或 `{ "type": "hours", "open", "close" }`（一天中的分鐘，`close` 可以超過 1440，也就是隔天清晨）。
  - `trainsInService`：`{ "peak", "offPeak", "low" }`，各服務等級要跑的列車數。
  - `targetHeadways`：`{ "peak", "offPeak", "low" }`，三個 key 都必填；各等級的目標班距（分鐘），沒有目標的等級是 `null`，由 `trainsInService` 決定。
  - `trains`：指派給這條線路的列車 ID，依 ID 遞增；沒有是 `[]`。
  - `lastDispatch`：線路上次從第一站派出列車的遊戲分鐘；從未派車是 `null`。
  - `patterns`：線路的服務模式陣列，順序就是分配容量的順序；沒有是 `[]`。
  - 指令裡的線路值照原樣讀取、不檢查，是否合法由 GameCore 判定。
- **服務模式（pattern）**：`{ "calls", "trainsInService", "targetHeadways", "trains", "lastDispatch" }`，五個欄位都必填：
  - `calls`：停靠的站，是線路 `stops` 的索引（從 0 起）、嚴格遞增；連續的索引是交路，跳過的索引是快車通過的站。
  - 其他四個欄位的形式與意義和線路的相同，只是屬於這個模式；`lastDispatch` 是它上次從第一個停靠站派車的分鐘。
  - 模式以在 `patterns` 裡的索引（從 0 起）指定。`setLineTrainsInService`、`setLineTargetHeadways`、`assignTrain` 指令與 `lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway` 觀察可以加上整數的 `pattern`；沒有這個 key 就是線路自己的服務（停靠每一站），不可寫 `null`。
- **服務日**：`[{ "start", "level" }, ...]`，每一段從一天中的某分鐘開始，到下一段開始為止。
- **鐵軌的 layout**：以 `type` 區分：`{ "type": "open" }`（一般鐵軌，每個出口互通）、`{ "type": "turnout", "stem" }`（道岔：stem 接到每條支線，支線只接到 stem）、`{ "type": "crossing" }`（平面交叉：只能直行，四個出口）。
- **軌道資源**：`{ "type": "node", "x", "y" }`，或 `{ "type": "link", "from": { "x", "y" }, "to": { "x", "y" } }`，`from` 是逐列由北到南、每列由西到東較前面的一格；連續路網（schema 16）是 `{ "type": "networkNode", "node" }` 或 `{ "type": "networkSpan", "edge", "start", "end" }`（邊的編號與 span 的里程，從邊的 `from` 節點量起）。方格的 `link` 是那條連結唯一的 span（0 到 1024）；路網的邊切成 n = ⌈長度 ÷ 1024⌉ 段，第 k 個分界在 ⌊k × 長度 ÷ n⌋（Stage S3A）。資源的順序是先所有節點再所有 span：節點裡方格的格依位置排序、再路網節點依編號；span 裡連結依位置排序、再路網的邊依編號、同一條邊依里程（見決策 26、29）。
- **連續路網**（schema 16，決策 29）：
  - 世界座標：`x` 向東、`y` 向南、`z` 向上的整數，一格是 1024 單位；方格 (x, y) 的中心是 (1024x + 512, 1024y + 512, 0)。
  - 節點與邊依建造順序從 1 編號，失敗的指令不消耗編號，拆除的編號不再使用。指令、結果與觀察以 `node`、`edge` 欄位寫編號。
  - 曲線（`curve`）：`{ "type": "straight" }`，或 `{ "type": "cubic", "control1": { "x", "y" }, "control2": { "x", "y" } }`（兩個平面控制點，世界座標）。
  - 行進方向（traversal）：`{ "edge", "direction" }`，`direction` 是 `"forward"` 或 `"backward"`。
  - 位置與方向（location）：`{ "x", "y", "z", "dx", "dy" }`，`dx`、`dy` 是沒有正規化的方向。點：`{ "x", "y", "z" }`。
- **立體鐵路**（schema 17，決策 30）：
  - 縱斷面（`profile`）：`{ "startTransition", "endTransition" }`，兩端豎曲線的長度（里程，0 是沒有）。`buildTrackEdge` 省略時是兩個 0。
  - 結構物（`structure`）：`"surface"`、`"elevated"`、`"bridge"` 或 `"tunnel"`。`buildTrackEdge` 省略時是 `"surface"`。
  - 姿態（pose）：`{ "x", "y", "z", "dx", "dy", "rise", "run" }`，位置、沒有正規化的方向，以及沿這個方向的坡度 `rise / run`（最簡分數，`run` 為正，上坡為正；平坡是 `0 / 1`）。
  - 縱斷面的分段：`{ "kind", "start", "end" }`，`kind` 是 `"level"`、`"up"`、`"down"` 或 `"transition"`，里程從邊的 `from` 端量起。
  - 路網上的月台：`{ "edge", "start", "end" }`（邊的編號、從邊的 `from` 端量起的起訖里程）。
- **路徑**（schema 18，決策 31）：`{ "traversals": [行進方向, ...], "end", "distance" }`：列車在車頭所在的邊之後依序進入的行進方向、車頭停在最後一條（沒有時是車頭所在的那一條）的哪裡（沿行進方向量起；走到終點時不寫 `end`），以及車頭從現在的位置走到那裡的精確距離。
- **線路行程**：`{ "start", "legs", "roundTripSeconds", "roundTripMinutes" }`。`start` 是列車位置（方格是 `node`，路網是 `edge` 的停車位置）；`legs` 是 `[{ "from", "to", "route", "seconds" }, ...]`（schema 25：一段的秒數；`roundTripSeconds` 是整趟的秒數，`roundTripMinutes` 是它無條件進位到整分鐘），`from`、`to` 是線路 `stops` 的索引，`route` 是 `[{ "x", "y" }, ...]`。從路網出發的行程（schema 18）每一段以 `path`（上面的「路徑」）取代 `route`：一段只有其中一個。
- **乘客**（schema 20，決策 34）：
  - 需求（`demand`）：`{ "kind", "dailyTrips" }`，`kind` 是 `"residential"`、`"office"`、`"shopping"` 或 `"scenic"`，`dailyTrips` 是整數；指令裡照原樣讀取，是否合法由 GameCore 判定。
  - 沿線路的方向：`"outbound"`（往線路 `stops` 的後面）或 `"inbound"`（往前面）。
  - 旅次（`trip`）：`{ "line", "direction" }`。
  - 等車的一組（`groups` 的一項、最終狀態的 `waiting`）：`{ "line", "direction", "destination", "since", "count" }`：要坐的線路與方向、迄點車站、釋出的遊戲分鐘與人數，依排隊的順序（先來的在前）。
  - 守恆稽核（`ledger`）：`{ "released", "waiting", "riding", "arrived", "overflowed", "abandoned", "refused" }`（`riding`、`arrived`、`refused` 自 schema 21，決策 35），七個欄位都必填。
  - 車上的一組（`riders` 的一項，schema 21）：`{ "origin", "destination", "count" }`：上車的車站、迄點車站與人數，依（起點、迄點）排序。
- **經營**（schema 22，決策 36）：金額都是整數美分。
  - 經營模式：`"free"` 或 `"management"`。
  - 票價規則（`rules`）：`{ "mode": "flat", "fare" }` 或 `{ "mode": "distance", "bands": [{ "fromMeters", "toMeters", "fare" }, ...] }`；`toMeters` 必填，沒有終點時是 `null`。指令裡照原樣讀取，是否合法由 GameCore 判定。
  - 帳（`accounts`）：`{ "mode", "fareRules", "openedAt", "pending", "ledger", "days" }`，六個欄位都必填；`fareRules`（沒有設定過是 `null`）、`openedAt`（遊戲分鐘，從未經營是 `null`）；`pending` 是這一小時的 `{ "fareRevenue", "fareTrips", "departures", "trainDistance", "passengers", "seats" }`；`ledger` 是帳本列 `{ "kind", "time", "amount", "breakdown": [{ "item", "amount" }, ...], "crowding" }`（`kind` 是 `"hourlyNet"`、`"dailyEnergy"` 或 `"dailyStaff"`，`crowding` 必填：小時列是 `{ "crowdedStations", "fullTrains", "maxWaiting", "maxLoad" }`，其他是 `null`），依寫入的順序；`days` 是 `{ "day", "fareRevenue", "operatingCost", "maintenanceCost", "energyCost", "staffCost" }`（成本是正數），依日期遞增。
  - 報表（`report`）：`{ "current": 一期, "previous": 一期 }`，一期是 `{ "index", "fareRevenue", "operatingCost", "maintenanceCost", "energyCost", "staffCost" }`。

### 指令（`command.type`）

| `type` | 其他欄位 | GameCore 指令 |
| --- | --- | --- |
| `buildTrack` | `x`、`y`、`connections` | `buildTrack(at:connections:)` |
| `removeTrack` | `x`、`y` | `removeTrack(at:)` |
| `buildTurnout` | `x`、`y`、`connections`、`stem`（方向名稱） | `buildTurnout(at:connections:stem:)` |
| `buildCrossing` | `x`、`y` | `buildCrossing(at:)` |
| `buildStation` | `name`、`x`、`y` | `buildStation(named:at:)` |
| `buildStationAt` | `name`、`point`（`{ "x", "y" }`，世界單位） | `buildStation(named:at:)`（`PlanPoint`） |
| `extendStation` | `station`、`x`、`y` | `extendStation(_:to:)` |
| `purchaseTrain` | `name` | `purchaseTrain(named:)` |
| `setTrainCars` | `train`、`cars` | `setTrainCars(_:to:)` |
| `placeTrain` | `train`、`position`（`node` 或 `link`） | `placeTrain(_:at:)` |
| `unplaceTrain` | `train` | `unplaceTrain(_:)` |
| `reverseTrain` | `train` | `reverseTrain(_:)` |
| `setTrainMovementRate` | `train`、`rate` | `setTrainMovementRate(_:to:)` |
| `setTrainPerformance`（schema 25） | `train`、`performance` | `setTrainPerformance(_:to:)` |
| `setTrainContinuation` | `train`、`continuation`（`[{ "x", "y" }, ...]`，可為空陣列） | `setTrainContinuation(_:to:)` |
| `setTrainTimetable` | `train`、`timetable`（停靠陣列，可為空陣列）、`repeat` | `setTrainTimetable(_:to:repeatingEvery:)`（`once` 傳 `nil`） |
| `startTrainService` | `train` | `startTrainService(_:)` |
| `stopTrainService` | `train` | `stopTrainService(_:)` |
| `createLine` | `name`、`stops` | `createLine(named:stops:)` |
| `removeLine` | `line` | `removeLine(_:)` |
| `setLineStops` | `line`、`stops` | `setLineStops(_:to:)` |
| `setLinePerformance`（schema 25，取代 `setLineRate`） | `line`、`performance` | `setLinePerformance(_:to:)` |
| `setLineServiceWindow` | `line`、`window` | `setLineServiceWindow(_:to:)` |
| `setLineTrainsInService` | `line`、`trains`（`{ "peak", "offPeak", "low" }`），可加 `pattern` | `setLineTrainsInService(_:to:pattern:)` |
| `setServiceDay` | `bands`（`[{ "start", "level" }, ...]`） | `setServiceDay(_:)` |
| `setLineTargetHeadways` | `line`、`targetHeadways`（`{ "peak", "offPeak", "low" }`，分鐘或 `null`），可加 `pattern` | `setLineTargetHeadways(_:to:pattern:)` |
| `assignTrain` | `train`、`line`，可加 `pattern` | `assignTrain(_:to:pattern:)` |
| `unassignTrain` | `train` | `unassignTrain(_:)` |
| `addLinePattern` | `line`、`calls`（整數陣列） | `addLinePattern(_:calling:)` |
| `removeLinePattern` | `line`、`pattern` | `removeLinePattern(_:at:)` |
| `setSpeed` | `speed` | `setSpeed(_:)` |
| `pause` | — | `pause()` |
| `resume` | — | `resume()` |
| `advance` | `ticks`（≥ 0） | `advance(ticks:)`（可能回傳 `clockOverflow`） |
| `buildTrackNode` | `x`、`y`、`z` | `buildTrackNode(at:)` |
| `buildTrackEdge` | `from`、`to`（節點編號）、`curve` | `buildTrackEdge(from:to:curve:)` |
| `removeTrackEdge` | `edge` | `removeTrackEdge(_:)` |
| `removeTrackNode` | `node` | `removeTrackNode(_:)` |
| `setTrainPath` | `train`、`path`（行進方向的陣列，可為空陣列），可加 `end`（schema 18，整數） | `setTrainContinuation(_:along:stoppingAt:)`（省略 `end` 傳 `nil`） |
| `buildTrackEdge`（schema 17） | 另外可加 `profile`、`structure` | `buildTrackEdge(from:to:curve:profile:structure:)` |
| `addTrackPlatform` | `station`、`edge`、`start`、`end` | `addTrackPlatform(_:on:from:to:)` |
| `removeTrackPlatform` | `station`、`edge`、`start` | `removeTrackPlatform(_:on:from:)` |
| `setTrafficControl`（schema 19） | `enabled`（布林值） | `setTrafficControl(_:)` |
| `setStationDemand`（schema 20） | `station`、`demand`（需求，或 `null` 清除；key 必填） | `setStationDemand(_:to:)` |
| `setEconomyMode`（schema 22） | `mode`（經營模式） | `setEconomyMode(_:)` |
| `setFareRules`（schema 22） | `rules`（票價規則） | `setFareRules(_:)` |

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
| `invalidTrainPosition` | — | 位置不是地圖內的鐵軌格，或不是兩格相接鐵軌之間、`0 < offset < 1024` 的連結；或多節列車的車身在後方沒有足夠的鐵軌 |
| `invalidMovementRate` | — | rate 是負數 |
| `invalidContinuation` | — | continuation 有一步與前一個節點不相接，或立即折返 |
| `clockOverflow` | — | 推進後的遊戲秒超出時鐘上限（`Int64`），整批不執行。可移植整數（≤ 2^53 − 1）無法表達這個情境，目前只在 Swift 單元測試驗證 |
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
| `invalidTrainPerformance`（schema 25，取代 `invalidLineRate`） | — | 列車或線路的性能不合法（見下面「行駛曲線」） |
| `invalidServiceWindow` | — | 營運時間不合法：`open` 不在 0…1439，`close` 不晚於 `open`，或晚於 1800（隔天 06:00） |
| `invalidTrainsInService` | — | 某個服務等級的列車數是負數 |
| `invalidServiceDay` | — | 服務日不從分鐘 0 開始，或各段的開始時間沒有在一天內嚴格遞增 |
| `invalidHeadway` | — | 某個等級的目標班距不在 2…1440 分鐘 |
| `trainOnLine` | `train` | 列車屬於一條線路：由線路設定它的時刻表、啟動它的服務，不能手動設定時刻表、啟動或停止服務，也不能再指派一次，要先取回 |
| `trainNotOnLine` | `train` | 列車不屬於任何線路，沒有可以取回的 |
| `invalidLinePattern` | — | 服務模式的 `calls` 少於兩個、沒有嚴格遞增，或不是線路的站的索引；或新的站數會讓某個模式停靠超出最後一站 |
| `unknownLinePattern` | `pattern` | 線路沒有這個索引的服務模式 |
| `invalidStationTile` | `x`、`y` | 車站要長到的格不在它任何一格的正北、正東、正南、正西 |
| `invalidTrainLength` | — | 節數不在 1…16 |
| `unknownTrackNode` | `node` | 連續路網沒有這個編號的節點 |
| `unknownTrackEdge` | `edge` | 連續路網沒有這個編號的邊 |
| `invalidTrackGeometry` | — | 點不在地圖內或高度超出 −4096…4096（schema 16 時 `z` 必須是 0），該點已有節點，邊的兩端是同一個節點（或平面上同一點），控制點在地圖外，曲線不能成為一條邊（控制點與端點重合、取樣後折返），或縱斷面不成立（負的豎曲線、兩段合計超過邊長、平坡上有豎曲線） |
| `trackNodeInUse` | `node` | 還有邊接在這個節點上，要先拆邊 |
| `trackEdgeInUse` | `edge` | 有已放置列車的車頭或車身在這條邊上，要先取下列車 |
| `trackTooSteep` | — | 邊的固定坡度超過 40‰（schema 17） |
| `invalidTrackStructure` | — | 結構物不能在兩端的高度承載鐵軌（schema 17） |
| `trackConflict` | `edge` | 新邊會在平面上與這條邊相遇（不在共用節點附近），高度差不到 512；是編號最小的一條（schema 17） |
| `trackEdgeHasPlatform` | `edge` | 有車站的月台在這條邊上，要先移除月台（schema 17） |
| `invalidPlatform` | — | 月台不在邊內、不是平的、長度不為正、與同一條邊上的月台重疊，或要移除的月台不存在（schema 17） |
| `trackReserved` | `train` | 交通控制開啟時，這台列車（編號最小的一台）持有指令需要的軌道：新的路或放置要取得的預約範圍，或要拆除、改變的鐵軌（schema 19） |
| `trainsShareTrack` | `trains`（`[a, b]`） | 開啟交通控制時，兩台列車需要同一段軌道：`b` 是依 ID 第一台與前面某台相交的列車，`a` 是與它相交的最小編號（schema 19） |
| `invalidStationDemand` | — | 車站每天的旅次不在 0…1,000,000（schema 20） |
| `invalidFareRules` | — | 票價規則不成立：票價不在 0…1e9、沒有段或超過 64 段、第一段不從 0 起、段之間有缺口、`to` 小於 `from`、最後一段之外沒有終點、最後一段有終點，或距離超過 1e7 m（schema 22） |

### 觀察（`observe.type`）

觀察透過 GameCore 的公開唯讀查詢回答，不屬於指令，也不能寫在 `command.type`。`expect` 的形式由觀察種類決定，種類不符或同時寫了兩種答案（例如 `connectedNeighbors` 配 `connected`，或 `neighbors` 與 `connected` 並列）必須報錯。

| `type` | 其他欄位 | `expect` | GameCore 查詢 |
| --- | --- | --- | --- |
| `connectedNeighbors` | `x`、`y` | `{ "neighbors": [{ "x", "y" }, ...] }` | `connectedNeighbors(of:)` |
| `isConnected` | `from`、`to`（各為 `{ "x", "y" }`） | `{ "connected": true }` 或 `false` | `isConnected(_:to:)` |
| `train` | `train` | `{ "position": {...}, "movement": {...} }`（形式同最終狀態） | `train(id:)` |
| `route` | `from`（列車位置，`node` 或 `link`）、`to`（`{ "x", "y" }`） | `{ "found": true, "route": [{ "x", "y" }, ...] }` 或 `{ "found": false }` | `route(from:to:)` |
| `platforms` | `station`（車站 ID） | `{ "platforms": [{ "x", "y" }, ...] }` | `platforms(of:)` |
| `routeToStation` | `from`（列車位置，`node` 或 `link`）、`station`（車站 ID），可加 `cars`（1…16，省略是 1） | 與 `route` 相同 | `route(from:toStation:length:)`（`length` = (`cars` − 1) × 1024） |
| `stationStops` | `train` | `{ "stations": [id, ...] }` | `stationsStoppedAt(by:)` |
| `wholeTrainStops` | `train` | `{ "stations": [id, ...] }` | `stationsBesideWholeTrain(_:)` |
| `platformTracks` | `station` | `{ "platformTracks": [[{ "x", "y" }, ...], ...] }` | `platformTracks(of:)` |
| `timetable` | `train` | `{ "timetable": [{ "station", "arrival", "departure" }, ...] }` | `train(id:)?.timetable` |
| `execution` | `train` | `{ "execution": { "type", ... } }`（見上面「服務」） | `train(id:)?.execution` |
| `serviceLevel` | `line`、`gameMinutes` | `{ "level": "peak" }`，停止營運或沒有這條線路時是 `"closed"` | `serviceLevel(of:at:)` |
| `lineJourney` | `line`，可加 `pattern` | `{ "found": true, "journey": {...} }` 或 `{ "found": false }` | `lineJourney(_:pattern:)` |
| `lineMaximumTrains` | `line`，可加 `pattern` | `{ "found": true, "trains": n }` 或 `{ "found": false }` | `lineMaximumTrains(_:pattern:)` |
| `lineTrainsInService` | `line`、`level`，可加 `pattern` | 與 `lineMaximumTrains` 相同 | `lineTrainsInService(_:at:pattern:)` |
| `lineHeadway` | `line`、`level`，可加 `pattern` | `{ "found": true, "minutes": n }` 或 `{ "found": false }` | `lineHeadway(_:at:pattern:)` |
| `lineSegmentLoads` | `line`、`level` | `{ "found": true, "loads": [n, ...] }` 或 `{ "found": false }` | `lineSegmentLoads(_:at:)` |
| `exits` | `x`、`y`、`heading` | `{ "exits": [{ "x", "y" }, ...] }`，依北、東、南、西 | `exits(from:facing:)` |
| `occupancy` | `train` | `{ "resources": [資源, ...] }` | `occupiedResources(of:)` |
| `conflicts` | — | `{ "conflicts": [{ "resource", "trains": [id, ...] }, ...] }` | `occupancyConflicts()` |
| `trackSections` | — | `{ "sections": [{ "nodes": [{ "x", "y" }, ...], "loop": true / false }, ...] }` | `trackSections()` |
| `parallelTracks` | `from`、`to`（車站 ID） | `{ "tracks": n }` | `parallelTracks(between:and:)` |
| `trackEdge` | `edge` | `{ "found": true, "edge": { "from", "to", "length" } }` 或 `{ "found": false }` | `trackEdge(_:)` |
| `edgeLocation` | `edge`、`direction`、`distance` | `{ "found": true, "location": { "x", "y", "z", "dx", "dy" } }`，沒有這條邊或距離不在 0…邊長時是 `{ "found": false }` | `trackGeometry(of:)` 的 `location(at:going:)` |
| `transitions` | `edge`、`direction` | `{ "transitions": [行進方向, ...] }`，依邊的編號遞增 | `transitions(after:)` |
| `pathToNode` | `from`（列車位置）、`node` | `{ "found": true, "path": [行進方向, ...] }` 或 `{ "found": false }` | `route(from:to:)`（以 `TrackNodeID` 為目的地） |
| `bodyPath` | `train` | `{ "points": [點, ...] }`，從車頭到車尾 | `bodyPath(of:)` |
| `edgePose` | `edge`、`direction`、`distance` | `{ "found": true, "pose": 姿態 }`，與 `edgeLocation` 相同的條件下是 `{ "found": false }` | `trackGeometry(of:)` 的 `location(at:going:)` |
| `edgeAlignment` | `edge` | `{ "found": true, "alignment": { "structure", "segments": [分段, ...], "steepest": { "rise", "run" } } }` 或 `{ "found": false }`；`steepest` 是朝 `to` 端的最陡坡度 | `trackAlignment(of:)` |
| `tunnelPortals` | — | `{ "nodes": [編號, ...] }`，依編號遞增 | `isTunnelPortal(_:)` |
| `trackPlatformsAlongTrain` | `train` | `{ "trackPlatforms": [{ "station", "edge", "start", "end" }, ...] }`，沿鐵軌的順序 | `trackPlatformsAlongWholeTrain(_:)` |
| `platformLevels` | `station` | `{ "levels": [{ "edge", "start", "end", "height", "structure" }, ...] }`，依該站的順序 | `railwaySnapshot()` 的 `platforms` |
| `pathToStation`（schema 18） | `from`（列車位置，必須是 `edge`）、`station`，可加 `cars`（1…16，省略是 1） | `{ "found": true, "trainPath": 路徑 }` 或 `{ "found": false }` | `path(from:toStation:length:)`（`length` = (`cars` − 1) × 1024） |
| `reservation`（schema 19） | `train` | `{ "resources": [資源, ...] }` | `reservedResources(of:)` |
| `heldResources`（schema 19） | `train` | `{ "resources": [資源, ...] }` | `heldResources(of:)` |
| `routeHolder`（schema 19） | `train` | `{ "found": true, "train": id }` 或 `{ "found": false }` | `trainHoldingRoute(of:)` |
| `passengerTrip`（schema 20） | `from`、`to`（車站 ID） | `{ "found": true, "trip": 旅次 }` 或 `{ "found": false }` | `passengerTrip(from:to:)` |
| `demand`（schema 20） | `from`、`to`（車站 ID） | `{ "daily": n, "hourly": [24 個整數，0 時起] }` | `dailyDemand(from:to:)`、`hourlyDemand(from:to:)` |
| `waitingPassengers`（schema 20） | `station` | `{ "groups": [等車的一組, ...] }` | `waitingPassengers(at:)` |
| `passengerLedger`（schema 20） | `station` | `{ "ledger": 守恆稽核 }` | `passengerLedger(of:)` |
| `riders`（schema 21） | `train` | `{ "riders": [車上的一組, ...] }` | `riders(of:)` |
| `tripFare`（schema 22） | `from`、`to`（車站 ID） | `{ "found": true, "fare": n }` 或 `{ "found": false }` | `tripFare(from:to:)` |
| `accounts`（schema 22） | — | `{ "accounts": 帳 }` | `accounts` |
| `financeReport`（schema 22） | `period`（`"day"`、`"week"`、`"month"`、`"year"`） | `{ "report": 報表 }` | `financeReport(_:)` |
| `serviceTimes`（schema 24） | `train` | `{ "found": true, "times": 服務時刻 }`，沒有服務（或沒有這台列車）時 `{ "found": false }` | `train(id:)?.times` |
| `lateness`（schema 24） | `train` | `{ "found": true, "lateness": 秒 }`（負數是早到），沒有服務（或沒有這台列車）時 `{ "found": false }` | `lateness(of:)` |

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
- 每個 `advance` 依速度推進秒數（見上面「時間」）；每一秒（一個基本步長）依列車 ID 順序讓每台列車走它這一秒的份：一分鐘裡的第 `s` 秒（從 0 起）走 `⌊rate·(s + 1)/60⌋ − ⌊rate·s/60⌋` 單位，然後時間 +1 秒。整分鐘加起來正好是 `rate`，和 Stage W2a 之前一步一分鐘時相同。到站每一秒判定；發車、派車、乘客與帳仍然在整分鐘處理（Stage W2b 才改到秒）。
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

車站設施規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 27）：

- `extendStation` 讓車站長到它某一格正北、正東、正南、正西的空格，收一座車站的費用。檢查順序：`unknownStation` → `outOfBounds` → `tileOccupied` → `invalidStationTile` → `insufficientFunds`。車站的每一格都有月台：`platforms` 依車站的格（原本的格、再依長出的順序）、每格依北、東、南、西排列，重複的只列一次。停站看車站的任何一格。
- `platformTracks`：把月台依相接分組，每組依 `platforms` 的順序，組依第一個月台的順序。
- 列車有 1 到 16 節，每節一格，新購的是 1 節。`setTrainCars` 只能在列車不在軌道上時設定：`unknownTrain` → `invalidTrainLength` → `trainAlreadyPlaced`。車頭後方的車身長 (節數 − 1) × 1024。
- 車身 `trail` 是車頭後方車身經過的節點，由近到遠，到第一個位於或超過車尾的節點為止：`node` 的列車從它身後那一格開始（與 `heading` 相反的方向），`link` 的列車從 `from` 開始。
  - 放置時從那裡沿列車可能開來的方向往回走，分岔時選北、東、南、西第一個可走的方向；鐵軌不夠長時是 `invalidTrainPosition`。
  - 移動時車身跟著車頭經過的節點。
  - `reverseTrain` 讓車頭移到車尾的位置，面向離開原車頭的方向，車身沿同一段鐵軌往原車頭延伸；1 節的列車與之前相同。
  - 取下列車時車身清空，節數保留。拆軌時，車身經過的節點也是 `trackInUse`。
- `occupancy` 加上車身經過的連結，以及車身到達或經過的節點（與車頭距離不超過車身長度）。
- `routeToStation` 加上 `cars` 時，到達第一個月台後再沿月台往前，每多一節多走一格（選北、東、南、西第一個是該站月台的出口），月台走完就停。服務與線路的出發、線路列車的行程都用列車自己的節數。
- `wholeTrainStops`：停在該站，而且車身經過的每一格都是該站的月台。

連續軌道規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 29）：

- `buildTrackNode`：點必須在地圖內（`0 <= x < 寬 × 1024`、`0 <= y < 高 × 1024`）、在地面（`z` 為 0），而且那裡還沒有節點；否則是 `invalidTrackGeometry`，接著才是 `idsExhausted`。免費。
- `buildTrackEdge` 的檢查順序：`unknownTrackNode`（先 `from` 再 `to`）→ `invalidTrackGeometry` → `idsExhausted` → `insufficientFunds`。費用是鐵軌的費用乘上邊長的格數（除以 1024 無條件進位，至少 1）。
- 長度：直線是 `round(√(dx² + dy²))`。三次曲線取樣 N 段，N 是 8…1024 之間最小的 2 的冪次，使 64N 不小於控制多邊形的長度（`|c1 − p0| + |c2 − c1| + |p3 − c2|`，各自四捨五入）；第 i 點是 `((N−i)³·p0 + 3(N−i)²i·c1 + 3(N−i)i²·c2 + i³·p3) ÷ N³` 四捨五入（一半進位）；去掉連續重複的點；長度是每段 `round(√(dx² + dy²))` 的總和。相鄰兩段的夾角達 90° 以上（尖點）時拒絕。
- 位置：`edgeLocation` 找到距離所在的一段，在段內以 `(b − a) × 段內距離 ÷ 段長` 四捨五入（一半進位）內插；方向是那一段的方向（恰好在取樣點時取之後那一段，終點取最後一段）；`backward` 從 `to` 端量起、方向相反。
- 相接：只有共用節點的邊才會相接。在一個節點上，兩個邊端離開節點的方向相反、而且叉積的絕對值不超過負內積的 1/16 時，列車可以從一邊通往另一邊；`transitions` 依邊的編號遞增列出。在平面上交叉、但沒有共用節點的邊，不相接也不共用資源。
- 列車在路網上沿 `edges` 移動，規則與方格相同，只是每條邊有自己的長度：恰好走到邊的終點時停下、不看下一項；還有距離時，下一條邊要在當下存在並與剛走完的邊相接才進入，否則停在終點等待。在路的最後一條邊上走到 `end`（schema 18）就停。`setTrainPath` 整份檢查後替換（`cursor` 歸 0，`end` 一起替換），檢查順序：`unknownTrain` → `trainNotPlaced` → `trainServiceActive` → `invalidContinuation`。`setTrainContinuation` 對路網上的列車只接受空陣列（清除，包括 `end`）；`reverseTrain` 也清除 `end`。
- `pathToNode`：從列車所在邊的終點出發、第一次到達 `node` 為止，總長最短；同樣最短時，在每個節點依邊的編號從起點逐步比較，取最先的一條。不會立即折返。起點與終點不是同一種鐵軌（方格與路網）時是 `{ "found": false }`。
- 車身：`trailEdges` 由放置時從車頭所在邊的起點往回走（分岔時選編號最小、而且能通往前一條邊的邊）得到，移動時跟著車頭走過的邊，反向時車頭移到車尾、車身沿同一段鐵軌往原車頭延伸。
- 佔用：車頭與車尾之間經過或到達的每個節點，以及車身有一部分嚴格落在其中的每條邊；1 節的列車在節點時是那個節點，在邊的中間時是那條邊。
- `removeTrackEdge`：`unknownTrackEdge` → `trackEdgeInUse` → `trackEdgeHasPlatform`（schema 17）；`removeTrackNode`：`unknownTrackNode` → `trackNodeInUse`。拆除免費、不退款。

立體鐵路規則（schema 17，完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 30）：

- 節點的高度 `z` 在 −4096…4096；地面是 0。邊的長度仍是水平里程，移動、路徑與佔用都不讀高度。
- 高度：R 是兩端的高差、L 是長度、T₀、T₁ 是兩端的豎曲線、D = 2L − T₀ − T₁。從 `from` 端量起 s 處比 `from` 高：`s < T₀` 時 `R·s² / (T₀·D)`；`s > L − T₁` 時 `R·(T₁·D − (L − s)²) / (T₁·D)`；其他 `R·(2s − T₀) / D`；各自四捨五入（一半進位）一次。坡度是這條規則的精確斜率：`2R·s / (T₀·D)`、`2R·(L − s) / (T₁·D)` 或 `2R / D`，約成最簡分數。`edgePose` 的高度與坡度不在取樣點之間內插。
- `buildTrackEdge` 的檢查順序：`unknownTrackNode` → `invalidTrackGeometry` → `trackTooSteep`（`2|R| × 1000 > 40 × D`）→ `invalidTrackStructure` → `trackConflict` → `idsExhausted` → `insufficientFunds`。費用是鐵軌的費用乘上結構物的係數（地面 1、高架 3、橋 4、隧道 5）再乘上格數。
- 結構物的高度帶（只看兩端，高度沿邊單調）：`surface` 是 |z| ≤ 128，`elevated`、`bridge` 是 z ≥ 0，`tunnel` 是 z ≤ 0。
- 淨空：兩條邊在平面上相交、端點落在另一條上或共線重疊的每一處，除了兩條邊共用的節點 1024 以內（兩端各自從那個節點量起），一條邊在相遇點的最低高度必須比另一條的最高高度高至少 512；否則是 `trackConflict`。相遇點在每一段上的里程是那一段兩端里程之間的線性內插，四捨五入（一半進位）。同一高度的交叉要共用節點（平面交叉），那個節點是兩方共用的資源。
- 隧道口：同時有隧道的邊與非隧道的邊接在上面的節點。
- 月台：`addTrackPlatform` 的檢查順序 `unknownStation` → `unknownTrackEdge` → `invalidPlatform`（`0 <= start < end <=` 邊長、兩端高度相同、與同一條邊上任何車站的月台不重疊，端點相接可以）；`removeTrackPlatform`：`unknownStation` → `invalidPlatform`。免費。車頭在月台的邊上、車身不離開那條邊，而且車頭到車尾都在月台的起訖之間（含端點）時，`trackPlatformsAlongTrain` 列出它。月台的兩端也是那條邊的 span 分界（Stage S3A 的等分再切開），所以整列停在月台上的列車只佔用月台內的 span。

路網上的營運規則（schema 18，完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 31）：

- 停車位置：車頭停在行進方向上月台的末端，車身向後。沿 `forward` 是 `offset = end`，沿 `backward` 是 `offset = 邊長 − start`。只有不比列車短的月台（`end − start >=` 列車長度，(`cars` − 1) × 1024）才算，所以走到停車位置時整列車都在那個月台上。
- `pathToStation`：從車頭所在的位置到該站某個停車位置、總距離最短的路；距離是 `(邊長 − offset) +` 中間每條邊的長度 `+` 最後一條上的 `end`（只在車頭所在的邊上時是 `end − offset`）。同樣短時逐步比較選擇：同一條行進方向上前方的停車位置在前（依里程），轉向在後、依邊的編號遞增。不立即折返。起點不在路網上、車站不存在、沒有夠長的月台或到不了時是 `{ "found": false }`；已在停車位置時是沒有 `traversals`、距離 0 的路。
- 停站（`stationStops`）：路走完（沒有剩下的邊，車頭在 `end`；沒有 `end` 時在邊的終點），而且車頭所在的邊上有該站的月台、車頭的里程在它的起訖之間（含兩端）。只看車頭所在的那一條邊。`wholeTrainStops` 另外要求整列車都在同一個月台內。要讓放在月台上的列車停站，給它一條在原地結束的路：`setTrainPath` 以 `path: []` 與 `end` 為目前的 `offset`（在邊的終點時省略 `end`）。
- `setTrainPath` 的 `end`：方格上的列車不能有；在最後一條邊上 `0 <= end <` 邊長；有剩下的邊時 `end >= 1`；沒有剩下的邊時不能在車頭後面（`end >= offset`）。否則是 `invalidContinuation`。
- 服務與線路在路網上用同一套規則，只是以 `pathToStation` 取代 `routeToStation`：出發時的路就是 `pathToStation` 的結果，寫成 `edges` 與 `end`；距離 0 表示已停在那一站。`reverse` 的停靠先原地折返（與 `reverseTrain` 相同），再讓列車的路在原地結束（`end` 是新的車頭位置），之後照常求路。
- `lineJourney` 從路網的停車位置出發時，每一段是 `pathToStation` 的路，秒數是線路的性能走完 `distance` 的最少整秒（schema 25）；每段之後列車在停車位置，車身沿走過的路；到最後一站原地折返。
- `removeTrackPlatform`：在 `invalidPlatform` 之後，有服務正在用這個月台時是 `trainServiceActive`（編號最小的列車）：等待中的服務停在這一站、車頭在這個月台上，或行駛中的服務前往這一站、路的最後一條邊就是這個月台的邊。

交通控制與進路預約規則（schema 19，完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 32）：

- 新世界的交通控制是關閉的，行為與 schema 18 完全相同，沒有列車有預約。
- 列車的路：方格上是剩下的 continuation（在連結上至少到 `to` 端），路網上是之後能進入的邊，停在最後一條的 `end`（沒有 `end` 或路斷掉時是那條邊的終點；沒有剩下的邊時是自己那條邊的 `end` 或終點）。路的長度為 0 時列車站著。
- 預約範圍：從車尾現在的位置沿車身與路一直到路的終點，這一整段依佔用的規則碰到的資源（碰到的每個節點；和這一段有一個嚴格落在邊的兩端之間的共同點的每個 span，所以落在 span 分界上時兩邊都算），再加上它的限界節點。
- 限界：節點上一條邊的端點，若這個節點上還有另一條邊的端點不和它相通，就是限界端；列車（車身或預約範圍）在這條邊上有一點離這個節點不到 1024 時，也持有這個節點。只存在於路網。
- 持有 = 佔用 ∪ 限界 ∪ 預約（`heldResources`）。取得預約時和其他列車的持有有交集就被拒絕或等待，阻擋者是編號最小的一台。
- 取得：`placeTrain`、`reverseTrain`、`setTrainContinuation`、`setTrainPath`、服務的出發、線路的派車與開啟交通控制，一次取得整個預約範圍，取代舊的預約；路的長度為 0 時預約是 `[]`。被拒絕的指令回報 `trackReserved`，錯誤順序排在既有的檢查之後。服務的出發被擋時什麼都不改（也不折返），下一個基本步長再試；線路的列車取不到時不就緒，不派出、不改 `lastDispatch`。派出的列車在同一段立刻出發。
- 解除：列車走到路的終點的那一步移動之後、`unplaceTrain`、關閉交通控制。`setTrainMovementRate`（包括 0）與 `stopTrainService` 不動預約。
- 基礎設施：交通控制開啟時，`removeTrack`（預約了那一格或以它為一端的連結）、`removeTrackEdge`（預約了那條邊的 span）、`addTrackPlatform` 與 `removeTrackPlatform`（持有那條邊的 span）、`buildTrackEdge`（持有新邊一端的節點，或那個節點上某條邊離它不到 1024 的 span，檢查排在 `idsExhausted` 之後、扣款之前）回報 `trackReserved`。
- `setTrafficControl` 開啟時依 ID 為每台已放置的列車算出它應有的持有，任兩台相交就是 `trainsShareTrack`，世界不變；關閉一定成功並清除所有預約。
- `routeHolder`：服務停在某站、排定出發已到時，或線路的列車就緒只差預約、線路該派車時，第一個出發的預約範圍被哪台列車持有（編號最小的一台）；其他情況（包括交通控制關閉）是 `{ "found": false }`。

車站需求與乘客規則（schema 20，完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 34）：

- 新世界的車站都沒有需求，行為與 schema 19 完全相同。`setStationDemand` 免費，檢查順序 `unknownStation` → `invalidStationDemand`；`null` 清除需求，已經在等的人留下。
- 旅次（`passengerTrip`）：編號最小、同時停起點與迄點的線路；方向依兩站在它的 `stops` 裡第一次出現的索引（迄點在後是 `outbound`）。同一站或沒有這樣的線路是 `{ "found": false }`。
- 每天的旅次（`daily`）：起點的 `dailyTrips` 分給它有旅次可到、而且 `dailyTrips` 大於 0 的車站，比例是那些車站的 `dailyTrips`，用最大餘數法（整數部分，剩下的依餘數由大到小各加 1，平手給站號小的）。
- 每小時的旅次（`hourly`）：一天的旅次依權重 `P[h] × D_o[h] × A_d[h]` 以最大餘數法分到 24 小時（平手給較早的小時）。`P` 是 `100, 100, 100, 100, 100, 100, 720, 1500, 1800, 1500, 800, 820, 840, 860, 880, 900, 1500, 1500, 1800, 1500, 1000, 1020, 1040, 100`；`D_o` 是起點類型的出發曲線、`A_d` 是迄點類型的到達曲線，都是 `1 + a·exp(−½((h − μ)/σ)²)` 乘上 24 ÷ 一天的合計、再乘 1000 四捨五入（`Math.round`）：住宅出發與辦公到達 `a = 0.6, μ = 8, σ = 1.15`；住宅到達與辦公出發 `μ = 18`；商業出發 `0.42·g(14, 2.4) + 0.5·g(19, 1.8)`、到達 `0.42·g(13, 2.4) + 0.5·g(18, 1.8)`；景點出發 `0.75·g(16, 2.1)`、到達 `0.75·g(11, 2.1)`。
- 釋出：每個基本步長（從分鐘 `T` 到 `T + 1`）一開始、在派車之前，每一對依起點、再依迄點的順序，把 `(60 − m)·R_h + m·R_{h+1}` 加到自己的餘數（`h`、`m` 是 `T` 在一天中的小時與分，`R_{h+1}` 在 23 時是 0 時的），餘數整除 3600 的人數在這一分鐘釋出，其餘留下。
- 排隊：釋出的人在起點成為一組（這一分鐘、這個迄點、坐的線路與方向），排在最後；車站等車的總數最多 4000，放不下的離開（`overflowed`）。
- 線路刪除或改停靠後，線路不再以那個方向載去迄點的組離開（`abandoned`），其他組的順序不變。
- 每一站 `released = waiting + overflowed + abandoned`。

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
  - 因此列車不會早於排定出發時刻離開，也不另加停留：早到的等到出發時刻，晚到的下一個步長就走；在某一步到達的列車最早在下一步離開。Stage W2c 起，排定的 `arrival` 決定這一段行駛的時間（見下面「行駛曲線」），所以準時出發的列車準時到達，不會早到。
- 服務執行中，`setTrainContinuation`、`reverseTrain`、`unplaceTrain` 在 `unknownTrain` → `trainNotPlaced` 之後是 `trainServiceActive`（`setTrainContinuation` 早於 `invalidContinuation`）；`setTrainMovementRate` 照常可用。行駛中前方鐵軌被拆時照移動規則等待，不重新求路。
- 一次 `advance` 推進多個 tick 與逐 tick 推進的結果相同，也不會跳過任何出發時刻。

行駛曲線（schema 25，Stage W2c，完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 40）：

- **性能（performance）**：寫成預設的名稱 `"standard"`、`"metro"`、`"local"`、`"express"`、`"semiExpress"`、`"ordinary"`、`"highSpeed"`、`"dieselRailcar"`、`"dieselExpress"`、`"forestRailway"`、`"tiltingTaroko"`、`"tiltingPuyuma"`、`"pushPull"`、`"emu3000"`（值見 `TrainPerformance`），或物件 `{ "acceleration", "braking", "topSpeed" }`，另外可以有 `"alternativeAcceleration"`、`"alternativeBraking"` 與 `"coast": { "deceleration", "speedRatio" }`。加速度、減速度、惰行的減速度以千分之一 km/h／秒計，最高速度以 km/h 計，速度比以千分之一計。等於某個預設時，寫入端寫成它的名稱（同值時取上面清單裡最先的）；讀取端兩種都接受，指令裡照原樣讀取，是否合法由 GameCore 判定。
- 合法的性能：每個加速度、減速度與最高速度都在 1 到 2^20；有惰行時，它的減速度在 1 到 2^20 且小於 `braking`，速度比在 0 到 999。新購的列車與新線路是標準性能（`standard`：1500、2500、110）。
- `setTrainPerformance` 的檢查順序：`unknownTrain` → `trainServiceActive`（服務執行中不能換）→ `invalidTrainPerformance`。`setLinePerformance`：`unknownLine` → `invalidTrainPerformance`。
- 單位：相鄰兩格中心 1024 單位，1 km/h 是每秒 160/9 單位。曲線是 Railway 參考的 `buildProfile`（Stage W1，`RunningCurve`）：加速、等速、有惰行時惰行、減速到停；位置是曲線在那一刻的距離，無條件捨去到整數單位。
- 列車離開一站（`travelling` 開始）時得到一段行駛（`run`）：排定的時間 T 是下一站在該輪的 `arrival` 減這一站的 `departure`（秒）。T 在 1 到 4294967 而且列車的性能做得出 T 秒的曲線時，這一段走 T 秒；否則走性能做得出曲線的最少整秒（盡快跑）；連最少的也沒有時沒有行駛曲線，列車照 rate 移動。所以晚出發的列車整段往後移、晚到同樣多；排得太緊的一段以最少的秒數跑完而晚到。
- 跟著行駛曲線時，每一秒走曲線在這一秒結束與開始時的距離差（rate 只要大於 0；rate 為 0 不動）。被擋住（rate 為 0，或前方鐵軌被拆）而在這一步結束時剩下的路比曲線剩下的長時，丟掉這段行駛；之後 rate 大於 0、還有路、而且能往前走 1 單位時，從停止狀態以最少的整秒重新出發，走剩下的路。
- 線路的性能決定線路的時刻表給每一段的時間；列車的性能決定它跑不跑得完：做得到時照時刻表的時間跑，做不到時以自己的最少秒數跑而晚到。

線路規則（完整說明見 [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) 決策 22）：

- 線路是計畫資料：不移動、不求路、不排班任何列車。新線路的營運時間是 06:00–24:00（`{ "type": "hours", "open": 360, "close": 1440 }`），性能是標準性能，各等級都是 0 台。
- 檢查順序：`createLine` 是 `invalidName` → `invalidLineStops` → `unknownStation`（第一個不存在的車站）→ `idsExhausted`；其他線路指令先檢查 `unknownLine`，再檢查自己的值；`setLineStops` 的 `unknownStation` 在 `invalidLineStops` 之後。
- 新世界的服務日：0 起低峰、420 起尖峰、600 起離峰、960 起尖峰、1200 起離峰、1260 起低峰。
- `serviceLevel`：營運時間內是服務日在那一分鐘的等級，否則是 `"closed"`。一天中的分鐘是 `gameMinutes` 除以 1440 的非負餘數。營運時間從 `open` 到 `close`，`open` 之前的分鐘算作隔天的（加 1440）。
- `lineJourney`：從第一站的一個月台出發，依序以 `routeToStation` 的規則求路到每一站；到最後一站原地折返，再依相反順序回到第一站。
  - 起點會試遍第一站的每個月台（依 `platforms` 的順序）、朝北、東、南、西，再試路網上的每個月台（依 `network.platforms` 的順序）的前進、後退兩個停車位置（schema 18），取來回時間最短的，同樣時取最先的。
  - 每一段的秒數是線路的性能走完距離的最少整秒（schema 25，見下面「行駛曲線」）；方格的距離是連結數 × 1024，路網的是路徑的 `distance`（見下面「路網上的營運」）。整趟（各段加上停站）無條件進位到整分鐘，線路以這個分鐘數規劃列車數與班距。
  - 來回時間是各段加上停留：兩端之間的每一站去回各 1 分鐘，兩端各 2 分鐘。
  - 任何一段沒有路時是 `{ "found": false }`。
- `lineMaximumTrains`：來回時間 ÷ 2（最短班距 2 分鐘），無條件捨去，至少 1。
- `lineTrainsInService`：該等級設定的列車數，但不超過 `lineMaximumTrains`。該等級有目標班距時，是來回時間 ÷ 目標班距（無條件進位），同樣不超過 `lineMaximumTrains`。
- `lineHeadway`：來回時間 ÷ 該等級的列車數，無條件進位；有目標班距時是目標班距，但不短於前者。沒有列車時是 `{ "found": false }`。
- 服務模式（完整說明見決策 24）：
  - 模式的行程和線路相同，只是依 `calls` 停靠：從第一個停靠站出發、在最後一個折返；`legs` 的 `from`、`to` 仍是線路 `stops` 的索引。兩端之間的停靠站去回各停 1 分鐘，兩端各 2 分鐘，通過的站不停。
  - 區段 `i` 是線路第 `i` 站到第 `i + 1` 站，每天每個方向最多 720 班。一個服務以 `⌈1440 ÷ 班距⌉` 佔用它從第一個停靠站到最後一個停靠站之間的每一段。
  - 各服務依序取得容量：線路自己的服務最先，再依 `patterns` 的順序。每個服務先照上面的規則算出單獨時的列車數，再取不超過它、而且每一段加上前面服務的負載都不超過 720 的最多列車數；一台都放不下時是 0。班距用減少後的列車數重算。
  - `lineSegmentLoads`：每一段的負載，依區段順序；為 0 的區段在該等級沒有列車經過。
  - 派車時，每條線路依序處理自己的服務與每個模式；模式的列車從它的第一個停靠站派出，時刻表只列出停靠的車站。

### 最終狀態

- `stations`：`{ "id", "name", "x", "y", "annexes" }`，或建在一個點上的車站 `{ "id", "name", "point": { "x", "y" } }`（世界單位，沒有 `x`、`y`、`annexes`），依 ID 遞增；`annexes` 是長出的格（`[{ "x", "y" }, ...]`，依長出的順序），只有一格的車站是 `[]`。車站在路網上的月台屬於鐵路網，寫在 `network` 的 `platforms`。
- `tracks`：`{ "x", "y", "connections", "layout" }`，逐列由北到南、每列由西到東；平面交叉的 `connections` 是四個方向。
- `trains`：`{ "id", "name", "position", "movement", "timetable", "repeat", "execution", "times", "cars", "trail", "trailEdges", "reservation", "performance" }`，依 ID 遞增（`performance` 只在不是標準性能時有，schema 25；`movement` 只在路網上的路停在邊的中段時有 `end`，schema 18；`times` 只在列車執行服務時有，形式見上面「服務時刻」，schema 24）；`position`、`movement`、`timetable`、`repeat`、`execution` 的形式見上面「列車位置」「列車移動」「時刻表」「重複」「服務」；`cars` 是節數，`trail` 是方格上的車身（`[{ "x", "y" }, ...]`，見上面「車站設施」），`trailEdges` 是連續路網上車頭所在邊之後車身經過的邊（編號，由近到遠，到車尾所在的那一條為止）；1 節的列車是 `1`、`[]` 與 `[]`。`reservation`（schema 19）是列車在交通控制下預約的資源（形式見上面「軌道資源」，依資源的順序），沒有預約是 `[]`。
- `lines`：線路（形式見上面「線路」），依 ID 遞增；沒有線路是 `[]`。
- `serviceDay`：服務日（形式見上面「服務日」）。
- `network`（schema 16）：`{ "nodes": [{ "id", "x", "y", "z" }, ...], "edges": [{ "id", "from", "to", "curve", "length", "profile", "structure" }, ...] }`，各自依編號遞增；`length` 是 GameCore 由兩端與曲線推導出的長度，fixture 以它釘住長度的整數規則；`profile` 與 `structure`（schema 17）必填；`platforms`（schema 17）必填：`[{ "station", "edge", "start", "end" }, ...]`，沿鐵軌的順序（依邊的編號、再依起點）。沒有路網是 `{ "nodes": [], "edges": [], "platforms": [] }`。
- `trafficControl`（schema 19）：交通控制是否開啟，布林值。
- `passengers`（schema 20）：有需求、或曾經釋出過乘客的車站，依車站 ID 遞增：`{ "station", "demand", "waiting", "released", "arrived", "overflowed", "abandoned", "refused" }`（`arrived`、`refused` 自 schema 21），八個欄位都必填；`demand` 沒有時是 `null`，`waiting` 是等車的各組（依排隊的順序）。還沒有乘客時是 `[]`。尚未釋出的不到一人的餘數是內部狀態，不列入。
- `riders`（schema 21）：每台載客的列車，依列車 ID 遞增：`{ "train", "groups": [車上的一組, ...] }`。沒有列車載客時是 `[]`。
- `accounts`（schema 22）：帳（形式見上面「經營」）。從未經營、也沒有設定票價時是 `{ "mode": "free", "fareRules": null, "openedAt": null, "pending": 全部是 0, "ledger": [], "days": [] }`。

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
- **12**（Phase 4 Stage Q2b）：新增 `setLineTargetHeadways`、`assignTrain`、`unassignTrain` 指令，`invalidHeadway`、`trainOnLine`、`trainNotOnLine` 結果，線路必填的 `targetHeadways`、`trains`、`lastDispatch`，以及 `line-dispatch.json`。`advance` 在每個基本步長的出發之前讓線路派車，但只派指派給線路的列車。既有的十一個 fixture 把 `schemaVersion` 從 11 改成 12；`service-line.json` 最終狀態的兩條線路加上 `"targetHeadways": { "peak": null, "offPeak": null, "low": null }`、`"trains": []`、`"lastDispatch": null`：它們沒有目標班距、沒有列車，所以從未派車。其他預期值都沒有改變。
- **13**（Phase 4 Stage Q3）：新增 `addLinePattern`、`removeLinePattern` 指令，`invalidLinePattern`、`unknownLinePattern` 結果，`lineSegmentLoads` 觀察，`setLineTrainsInService`、`setLineTargetHeadways`、`assignTrain` 指令與 `lineJourney`、`lineMaximumTrains`、`lineTrainsInService`、`lineHeadway` 觀察可以省略的 `pattern`，線路必填的 `patterns`，以及 `line-patterns.json`。既有的十二個 fixture 把 `schemaVersion` 從 12 改成 13；`service-line.json` 與 `line-dispatch.json` 最終狀態的三條線路加上 `"patterns": []`：它們沒有服務模式，所以派車與推導都和之前相同。其他預期值都沒有改變。
- **14**（Phase 4.5 Stage S1）：新增 `buildTurnout`、`buildCrossing` 指令，`exits`、`occupancy`、`conflicts`、`trackSections`、`parallelTracks` 觀察，最終狀態每條鐵軌必填的 `layout`，以及 `track-resources.json`。既有的十三個 fixture 把 `schemaVersion` 從 13 改成 14，並為最終狀態的 85 條鐵軌加上 `"layout": { "type": "open" }`：它們都是一般鐵軌，轉向與路徑規則不變。其他預期值都沒有改變。
- **15**（Phase 4.5 Stage S2）：新增 `extendStation`、`setTrainCars` 指令，`invalidStationTile`、`invalidTrainLength` 結果，`wholeTrainStops`、`platformTracks` 觀察，`routeToStation` 可以省略的 `cars`，最終狀態每座車站必填的 `annexes`、每台列車必填的 `cars` 與 `trail`，以及 `station-facilities.json`。既有的十四個 fixture 把 `schemaVersion` 從 14 改成 15，並為最終狀態的車站加上 `"annexes": []`、列車加上 `"cars": 1, "trail": []`：它們的車站都只有一格，列車都是 1 節（沒有車身），行為不變。其他預期值都沒有改變。讀取端只接受 15。
- **16**（Phase 4.5 Stage S3）：新增連續路網：`buildTrackNode`、`buildTrackEdge`、`removeTrackEdge`、`removeTrackNode`、`setTrainPath` 指令，`unknownTrackNode`、`unknownTrackEdge`、`invalidTrackGeometry`、`trackNodeInUse`、`trackEdgeInUse` 結果，`trackEdge`、`edgeLocation`、`transitions`、`pathToNode`、`bodyPath` 觀察，`edge` 列車位置，`networkNode`、`networkSpan` 資源（Stage S3A 把整條邊的資源改成 span，這個 schema 還沒有合併，所以不另加版本），列車移動必填的 `edges`、最終狀態每台列車必填的 `trailEdges` 與必填的 `network`，以及手算的 `continuous-track.json`（曲線的取樣另以獨立的精確分數計算核對）。既有的十五個 fixture 把 `schemaVersion` 從 15 改成 16，並只加上中性的值：86 個列車移動（最終狀態與 `train` 觀察）加上 `"edges": []`，最終狀態的 30 台列車加上 `"trailEdges": []`，最終狀態加上 `"network": { "nodes": [], "edges": [] }`：它們都沒有連續路網，行為不變。其他預期值都沒有改變。
- **17**（Phase 4.5 Stage S4）：新增立體鐵路：`buildTrackEdge` 可加的 `profile` 與 `structure`，`addTrackPlatform`、`removeTrackPlatform` 指令，`trackTooSteep`、`invalidTrackStructure`、`trackConflict`、`trackEdgeHasPlatform`、`invalidPlatform` 結果，`edgePose`、`edgeAlignment`、`tunnelPortals`、`trackPlatformsAlongTrain`、`platformLevels` 觀察，最終狀態 `network` 必填的 `platforms`（月台屬於鐵路網，見決策 30）與每條邊必填的 `profile`、`structure`，以及手算的 `vertical-railway.json`（高度與坡度另以獨立的精確分數計算核對）。既有的十六個 fixture 把 `schemaVersion` 從 16 改成 17，並只加上中性的值：最終狀態的 `network` 加上 `"platforms": []`，`continuous-track.json` 最終狀態的 6 條邊加上 `"profile": { "startTransition": 0, "endTransition": 0 }, "structure": "surface"`。**一個刻意的行為改變**：`continuous-track.json` 的第 7 步原本以 `z: 5` 驗證 S3 的「節點一律在地面」，S4 取消這條規則（5 是合法的高度），所以這一步改成 `z: 5000`（超出 ±4096），預期結果仍是 `invalidTrackGeometry`，說明文字同步更新；其他預期值都沒有改變。
- **18**（Phase 4.5 Stage S5）：路網上的營運：`setTrainPath` 可加的 `end`，列車移動只在有值時出現的 `end`，`pathToStation` 觀察（回答 `trainPath`），路網出發的 `lineJourney` 每一段以 `path` 取代 `route`，`removeTrackPlatform` 的 `trainServiceActive`，以及手算的 `network-service.json`（彎道、隧道與地下月台的距離另以獨立的精確分數計算核對）。既有的十七個 fixture 只把 `schemaVersion` 從 17 改成 18：它們的路網上沒有服務、沒有停在邊中段的路，所以沒有 `end`，方格的行程仍以 `route` 表示；其他預期值都沒有改變。
- **19**（Phase 4.6 Stage T）：交通控制與進路預約：`setTrafficControl` 指令，`trackReserved`、`trainsShareTrack` 結果，`reservation`、`heldResources`、`routeHolder` 觀察，最終狀態每台列車必填的 `reservation` 與必填的 `trafficControl`，以及手算的 `traffic-reservation.json`（道岔的限界、單線上的等待與放行、span 分界上的車尾與停車位置、立體交叉互不衝突、預約中的邊不能加月台或拆除）。既有的十八個 fixture 把 `schemaVersion` 從 18 改成 19，並只加上中性的值：最終狀態的 37 台列車加上 `"reservation": []`，最終狀態加上 `"trafficControl": false`：它們從未開啟交通控制，新世界的交通控制是關閉的，所以行為不變。其他預期值都沒有改變。
- **20**（G1a）：車站需求與乘客：`setStationDemand` 指令，`invalidStationDemand` 結果，`passengerTrip`、`demand`、`waitingPassengers`、`passengerLedger` 觀察，最終狀態必填的 `passengers`，以及手算的 `station-demand.json`（一天一個旅次在 08:59 釋出、百萬旅次在兩分鐘內讓車站滿、溢出、線路改停靠後放棄等車，每一站都守恆；預期值另以獨立的 Python 實作依規則計算）。既有的十九個 fixture 把 `schemaVersion` 從 19 改成 20，並只在最終狀態加上 `"passengers": []`：它們的車站都沒有需求，新世界的車站沒有需求，所以沒有人被釋出。其他預期值都沒有改變。
- **21**（G1b）：上下車與容量：`riders` 觀察，守恆稽核加上必填的 `riding`、`arrived`、`refused`，最終狀態車站的乘客加上必填的 `arrived`、`refused`、最終狀態必填的 `riders`，以及手算的 `boarding.json`（1 節列車 352 人的容量、下車站遠的先上、被拒絕的人數、下車、在遠端折返後載回程的人、線路的列車不能停止服務、離開線路後停止服務而放棄車上的人；預期值另以獨立的 Python 實作依規則計算）。既有的二十個 fixture 把 `schemaVersion` 從 20 改成 21，最終狀態加上 `"riders": []`，`station-demand.json` 的守恆稽核與最終狀態的乘客加上值為 0 的新欄位：它們都沒有列車載客。其他預期值都沒有改變。
- **22**（G1c）：票價、帳本與經營：`setEconomyMode`、`setFareRules` 指令，`invalidFareRules` 結果，`tripFare`、`accounts`、`financeReport` 觀察，最終狀態必填的 `accounts`，以及 `economy.json`（從 23:00 開始經營，被拒絕與接受的距離票價、兩段票價的邊界、需求受票價影響、午夜的小時列與能源、人事列、日報表的本期與上期、跨日後的下一個小時；預期值另以獨立的 Python 實作依規則計算）。既有的二十一個 fixture 把 `schemaVersion` 從 21 改成 22，並只在最終狀態加上初始的 `accounts`：新的世界是自由模式，什麼都不收、不記，所以行為不變。其他預期值都沒有改變。
- **23**（Stage W2a）：GameCore 的時鐘改以秒計（決策 37）：時鐘可以寫成 `gameSeconds`（只用在兩分鐘之間的時刻），最終狀態可以有 `pendingTenths`，新的速度 `x1`、`x10`、`x60`，以及 `clock-seconds.json`（真實時間累積十分之一秒、跨過速度的改變，列車每秒走它這一秒的份，跨過整分鐘時和以前一步一分鐘走到同一個地方，最後停在兩分鐘之間）。其他時間欄位仍然寫分鐘，GameCore 以秒保存，讀取端換算。既有的二十二個 fixture 只把 `schemaVersion` 從 22 改成 23：它們都以 `paused`、`normal` 或 `double` 推進整分鐘，Stage W2a 在整分鐘的行為不變（發車、派車、乘客與帳都還在整分鐘處理，到站在分鐘之內記下也不改變整分鐘看到的結果，列車在整分鐘時的位置與以前一步一分鐘相同），所以其他預期值都沒有改變。
- **24**（Stage W2b）：停站、上下車與實際時刻（決策 39）：時刻表停靠可以寫成 `arrivalSeconds`、`departureSeconds`（只用在兩分鐘之間的時間），最終狀態執行服務的列車必有的 `times`，`serviceTimes`、`lateness` 觀察，以及手算的 `station-dwell.json`（開門 8 秒的那一步才上下車、端點最短停站 42 秒、早到的列車等到排定出發前 9 秒才關門、晚到的列車只停最短的 36 秒、在最後一站停完才結束服務、每一刻的誤點秒數）。既有的二十三個 fixture 把 `schemaVersion` 從 23 改成 24。**刻意的行為改變**，每個改變的值都另以獨立的參考模型（`ReferenceWorld` 逐秒依規則執行）核對：
  - 服務在每一站停站才離開：啟動服務與派車算是在那一刻到達第一站，至少停 42 秒（端點與折返的站）或 36 秒（中間的站），所以列車比以前晚離開，之後的位置、服務與停在哪些車站也跟著晚：`train-repeat.json`、`train-service.json`、`line-dispatch.json`、`line-patterns.json`、`network-service.json`、`economy.json` 的位置、`execution`、`stationStops` 觀察與最終狀態。晚 42 秒、每分鐘 1024 的列車在整分鐘時還差一段的 308（= 1024 − ⌊1024 × 42 ÷ 60⌋）才到節點，晚 36 秒時差 410；每分鐘 2048 的路網列車少走 1433（= ⌊2048 × 42 ÷ 60⌋）。
  - 線路的時刻表在派車 42 秒後才離開第一站，之後的時間都晚 42 秒（寫成 `arrivalSeconds`、`departureSeconds`）：`line-dispatch.json`、`line-patterns.json`、`network-service.json`、`boarding.json`、`economy.json` 的 `timetable` 觀察與最終狀態。`line-patterns.json` 的 Shuttle 一趟因此要 8 分鐘（以前 7 分鐘），最後一次派車從 599 變成 600。
  - 被拒絕的人數改在客滿的列車離開時才計（等車中、可以上這班車卻沒上的人）：`boarding.json` 第一趟在 481:01 離開時記 4000（以前在 480 派車時記 3648），第二趟離開前已經取回線路，不再記；`economy.json` 最終狀態 Alpha 的 `refused` 18678 → 19192。
  - 車門開著的時候每個整分鐘釋出的人也會上車，票價依每次上車的人數各自四捨五入到整美元：`economy.json` 第 1 個小時的票價收入 65600 → 65500（帳本列、日帳、報表與餘額跟著少 100）。
  - 執行服務的列車加上 `times`。其他預期值都沒有改變。
- **25**（Stage W2c）：行駛曲線（決策 40）：列車與線路的 `performance`（取代線路的 `rate`），`setTrainPerformance`、`setLinePerformance` 指令（取代 `setLineRate`），`invalidTrainPerformance` 結果（取代 `invalidLineRate`），服務時刻的 `run`，線路行程每段的 `seconds`（取代 `minutes`）與整趟的 `roundTripSeconds`，以及手算的 `service-run.json`（性能指令的檢查順序、線路以性能規劃的秒數、時刻表給的時間、排得太緊時的最少秒數、加速段的位置 a·t²/2、被擋住時丟掉行駛、放行後從停止重新出發、晚到的誤點秒數）。既有的二十四個 fixture 把 `schemaVersion` 從 24 改成 25，線路去掉 `rate`、行程的 `minutes` 改名 `seconds`。**刻意的行為改變**，每個改變的值都另以獨立的參考模型（`ReferenceWorld` 逐秒依規則執行，自己寫的最少秒數與行駛規則）核對：
  - 列車照時刻表給的時間跑完一段，不再照 rate：準時出發就準時到達，不早到；兩站之間的位置是曲線的距離（例如 240 秒走 4 個連結，出發 18 秒後在 302，以前 308）。`train-service.json`、`train-repeat.json`、`station-dwell.json`、`traffic-reservation.json`、`network-service.json` 的位置、`execution`、`stationStops`、服務時刻與最終狀態跟著改變。
  - 為了保留原來要驗證的情境，幾個 fixture 改了指令（只改輸入，不改規則）：`boarding.json`、`economy.json`、`line-patterns.json`、`service-line.json` 的線路用 1 km/h 的慢速性能 `{ 250, 250, 1 }`（兩個連結 120 秒，和以前一樣）；`line-dispatch.json` 用 `{ 125, 100, 1 }`（四個連結 240 秒）；`network-service.json` 的 Tube 用 2 km/h 的 `{ 25, 25, 2 }`（往返 52 分鐘，和以前一樣），Mole 的時刻表改成 Deep 22/30、Harbour 53/62、每 63 分鐘（和以前照 rate 跑到的時間相近）；`traffic-reservation.json` 的時刻表 East 11 → 10、West 12 → 9（和以前到達的時間相同）；`station-dwell.json` 的列車用 `{ 250, 250, 1 }`，第一段排得太緊（60 秒）而以最少的 120 秒跑完、第二段從晚出發整段後移，最後一次 `advance` 119 → 179；`train-service.json` 的 Local 2 手動開到 Beta 多一個 tick（3 → 4），時刻表 Beta 29 → 30、Gamma 到達 45 → 44；`service-line.json` 的第二個性能 700 → 慢速性能（`setLineRate` 的 0 改成加速度 0 的性能）。
  - 線路的行程以秒計：`service-line.json` 的標準性能一段 16 秒（以前 2 分鐘），整趟 424 秒、8 分鐘，最多 4 台、班距 2、3、8 分鐘。
  - 執行服務、行駛中的列車加上 `run`；不是標準性能的列車與線路加上 `performance`。其他預期值都沒有改變。
- **26**（Stage F1）：建在任意座標的車站（決策 44）：`buildStationAt` 指令，最終狀態車站的 `point` 形式，以及手算的 `free-station.json`（點上的車站不占格：同一格可以有兩個點上的車站，土地、方格軌道與方格車站的規則不變，旁邊的方格軌道不是它的月台；沒有名字、點在地圖外時拒絕，地圖外報點所在的格（向下取整）；一樣花一個車站的錢；不能長到格上；路網上的月台、往車站的路徑與停靠和其他車站相同）。既有的二十五個 fixture 只把 `schemaVersion` 從 25 改成 26，其他預期值都沒有改變。
