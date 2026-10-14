# 內容目錄：車型數值搬到內建資料（設計，2026-10-14）

NEXT_PRIORITIES 2026-10-12 §5 第 2 項、§13 第 20 名。工作登記 #231：決策 225（待合併 session 確認），存檔版本與 golden schema **不動**。遊戲規劃 session 派工。

這份是第一段（只有文件）。第二段是 GameCore 程式，排在 GameCore 隊列第四（彎道限速二 #588 已合併，接著高鐵機廠規則 #611、班次紀錄），等合併 session 給名額才推會跑 GameCore 全量 CI 的 commit。

**這件事做什麼**：

- 把每種車型的數值從散在各處的 `switch` 搬到一張內建資料表；
- 車型的 ID 就是現在存檔裡的字串（`"A"`、`"HSR"`、`"EMU3000"`……）；
- 「是不是高鐵車組」改成表上明確的一欄，不再寫成 `self != .highSpeed`。

**這次不做的**：

- 不改任何車型的數值；
- 不加新車型；
- 不加車長、檢修、外觀這些新欄位。

這三件是之後的工作（§6）。這次只把地基打好，讓它們之後只要加一欄或加一列。

## 1. 現在的樣子

一種車型的數值分在五個地方，每個都是 `switch`：

| 數值 | 現在在哪裡 | 形式 |
| --- | --- | --- |
| 每節額定人數 | `TrainType.ratedCapacityPerCar`（`TrainType.swift`） | `switch`，12 個 case |
| 每節每側門數 | `TrainType.doorsPerCar` | `switch` |
| 會不會超載 | `TrainType.overloads` | `self != .highSpeed` |
| 自己的跑法 | `TrainType.performance` | `switch`，3 種有、其他 `nil` |
| 首節價、每節價、營運係數 | `TrainType.pricing`（`RollingStock.swift`） | `switch` |
| 哪些車型可以選 | `TrainType.main`、`.reference`、`.offered`、`.referenceDefault` | 手寫的陣列 |
| 畫面上的名稱 | `TrainType.title(in:)`（GamePresentation `DisplayText.swift`） | `switch` |
| 車種分類（捷運、鐵路、高鐵、特殊） | #608 的 `RollingStockCatalog.Family.init(_:)`（GamePresentation） | `switch` |

「是不是高鐵車組」另外散在畫面層，都寫成 `type == .highSpeed`：

- `TrainMotion.swift`：決定車鼻畫尖的；
- `Achievements.swift`：成就「有高鐵列車」；
- `LineStaffing.swift`：配車時跟著把路線改成高鐵性能；
- `HighSpeedText.swift`：判斷路線是不是全由高鐵車組跑。

路線是不是高鐵路線（決策 168 規則 1）看的是路線的性能（`ServiceLine.isHighSpeed`），不看車型，這次不動。

`TrainType` 是 `enum`，所以每加一種車型，上面每個 `switch` 都要加一個 case。存檔裡的車型是 rawValue 字串。

存檔版本過去跟著車型升過幾次：

- 版本 36 的蒸汽車；
- 版本 43 的高鐵；
- 版本 44 的 EMU3000。

升版的原因都是同一個 PR 也改了存檔格式（年代、腹地、車門擁擠）。車型本身只是讓舊 build 讀不懂新字串。

## 2. 資料格式與放哪裡

### 2.1 選定：GameCore 裡的一張 Swift 資料表（方案 A）

新檔 `Sources/GameCore/Railway/TrainTypeCatalog.swift`，只放資料。

```swift
/// One type of train car, as the built-in catalog lists it (decision 225).
public struct TrainTypeSpec: Hashable, Sendable {
    public let type: TrainType            // the ID: the code saves store
    public let family: TrainFamily        // metro, railway, highSpeed, special
    public let offer: TrainTypeOffer      // referenceMain, referenceExtra, added, eraOnly
    public let ratedCapacityPerCar: Int64
    public let doorsPerCar: Int64
    public let overloads: Bool            // takes up to 1.1 times its rating
    public let performance: TrainPerformance?
    public let pricing: RollingStockPricing
}

public enum TrainTypeCatalog {
    /// Every type, in the order menus and `TrainType.allCases` list them.
    public static let builtIn: [TrainTypeSpec] = [
        .init(code: "A", family: .metro, offer: .referenceMain, capacity: 310, doors: 5, overloads: true,
              performance: nil, firstDollars: 150_000, carDollars: 40_000, operatingPermille: 1_000),
        // … B, C, L, D, APM, MAGLEV, SKYRAIL, MONORAIL …
        .init(code: "STEAM", family: .railway, offer: .eraOnly, capacity: 50, doors: 2, overloads: true,
              performance: .steam, firstDollars: 80_000, carDollars: 20_000, operatingPermille: 1_400),
        .init(code: "HSR", family: .highSpeed, offer: .added, capacity: 80, doors: 2, overloads: false,
              performance: .highSpeed, firstDollars: 900_000, carDollars: 120_000, operatingPermille: 2_000),
        .init(code: "EMU3000", family: .railway, offer: .added, capacity: 45, doors: 2, overloads: true,
              performance: .emu3000, firstDollars: 260_000, carDollars: 55_000, operatingPermille: 1_200),
    ]
}
```

**每一欄**：

| 欄 | 取代 | 說明 |
| --- | --- | --- |
| `type` | enum 的 case | ID，就是現在的 rawValue，一個字都不改 |
| `family` | #608 的 `Family.init(_:)` | 捷運、鐵路、高鐵、特殊。值照 #608：A B C L D APM 捷運；STEAM、EMU3000 鐵路；HSR 高鐵；MAGLEV、SKYRAIL、MONORAIL 特殊。**「是不是高鐵車組」就是 `family == .highSpeed`**（`TrainType.isHighSpeed`） |
| `offer` | `main`、`reference`、`offered` 三個陣列 | 參考的主要車型、參考的其他車型、這個專案加的（一般遊戲可選）、只有年代劇本有。三個陣列改成依表的順序過濾，結果和現在逐項相同（§3 的測試） |
| `ratedCapacityPerCar` | `switch` | 不變 |
| `doorsPerCar` | `switch` | 不變 |
| `overloads` | `self != .highSpeed` | 明寫成一欄。現在只有 HSR 是 `false`。測試另外檢查「高鐵車組不超載」這條決策 168 的規則，`family == .highSpeed` 的都要是 `false` |
| `performance` | `switch` | 不變 |
| `pricing` | `RollingStock.swift` 的 `switch` | 不變。`RollingStock.standard`（沒有車型的標準車）留在原處，它不是表上的一列 |

**`TrainType` 從 `enum` 改成 `struct`**：

- 存一個 `rawValue: String`，和一個指向表的位置（`UInt8`）；
- 讀屬性是 O(1)：`TrainTypeCatalog.builtIn[index]`，不比對字串。上車、停站每秒都讀 `capacity`、`doorsPerCar`，所以這很要緊；
- `==` 與雜湊看 `rawValue`（同一張表裡 ID 不重複，所以和看位置一樣）；
- `init?(rawValue:)`：表裡沒有的字串回傳 `nil`，和 enum 一樣；
- `static let a = TrainType(…"A")` 這些常數保留，所以 `.a`、`.highSpeed`、`type == .highSpeed` 這些寫法都照樣編譯；
- `CaseIterable` 保留，`allCases` 就是表的順序（A B C L D APM MAGLEV SKYRAIL MONORAIL STEAM HSR EMU3000，和現在一樣）。

**`Codable` 不變**：

- 用 `RawRepresentable` 的預設實作，和現在的 enum 用的是同一份；
- 寫出來就是 `"HSR"` 這樣一個字串；
- 讀到不認得的字串，丟一樣的 `DecodingError.dataCorrupted`。

畫面上的名稱留在 GamePresentation：

- `title(in:)` 的 `switch` 改成一張依 ID 查的表；
- `TrainTypeNameTests` 已經檢查「每種車型剛好有一個名稱」，照舊。

名稱不進 GameCore，原因是 GameCore 不放玩家看的文字（ARCHITECTURE 規則）。

### 2.2 為什麼不是另外兩種

| 方案 | 長什麼樣子 | 為什麼沒選 |
| --- | --- | --- |
| A（選定） | 上面那張 Swift 表 | — |
| B. JSON 檔＋產生器 | `tools/train-types/train_types.json` 是來源；`build_train_types.py` 寫出 A 那個 Swift 檔（像 `tools/holiday-calendar/` 寫 `TaiwanHolidays.swift`）；測試檢查兩邊一致 | 多一個工具、一份同步測試，換到的只是「網頁也能讀同一份 JSON」。網頁的 3D 車（`Web/CityView/src/world/trains.js` 的 `STOCK`）現在用的是外觀數值（長度、車鼻、塗裝），和 GameCore 的數值沒有交集。等第三件事（外觀依車種畫）真的要共用時，再從 A 的表匯出一份 JSON 給網頁，表本身不用改 |
| C. JSON 當套件資源，執行時讀 | `Package.swift` 加 `resources:`，GameCore 開遊戲時解析 | GameCore 不 import Foundation，沒有 `JSONDecoder`，要自己寫一個 JSON 解析器。資料錯了要到執行時才發現，A 是編譯時就發現。另外每個測試、golden、重播都多一個讀檔的步驟 |

B 的預覽（沒有採用）：

```json
[
  {"id": "A", "family": "metro", "offer": "referenceMain", "capacity": 310, "doors": 5,
   "overloads": true, "performance": null, "first": 150000, "car": 40000, "operatingPermille": 1000}
]
```

C 的預覽（沒有採用）：

```swift
// Package.swift
.target(name: "GameCore", resources: [.process("Resources/train-types.json")])
// GameCore 要自己解析，因為沒有 Foundation
```

### 2.3 四方

- **玩家**：看不到任何改變，選單、價格、載客都一樣。之後加新車型時，舊存檔不用跟著升版，也不會因為多了車型就讀不進來。
- **開發**：
  - 加一種車型只要在表上加一列，加名稱表上一列；不必找遍每個 `switch`，也不必升存檔版本；
  - 加一個屬性（車長、檢修週期）只要加一欄；
  - 編譯器會檢查每一列都填了每一欄；
  - GameCore 不需要 JSON 解析器。
- **美術**：
  - 「是不是高鐵」和車種分類是表上明寫的一欄，畫面層的車鼻（決策 168：高鐵尖、其他圓）、2D 逐節畫法、車種型錄的分類（決策 224）都讀同一欄；
  - 之後要放的車長、車鼻形狀、塗裝、3D 模型名稱都有固定的地方放。
- **音樂**：
  - 這次沒有聲音的改動；
  - 之後要依車種放的聲音（決策 219 的鐵道聲音，例如高鐵與台鐵不同的行駛音、開關門音）可以用同一個 ID 對到聲音檔，不必另外分類。

## 3. 怎麼保證既有車型的每一個數值逐位元不變

第二段的 PR 要做到下面五件事，任何一件沒做到就不推。

**1. 先釘值，再搬家。**

第二段的第一個 commit 只加一個測試檔 `Tests/GameCoreTests/TrainTypeCatalogTests.swift`，**在現在的 `enum` 上**寫死現在的值：

- 12 種車型，每種的 rawValue、每節額定、門數、會不會超載、自己的跑法、首節價、每節價、營運係數；
- `main`、`reference`、`offered` 的內容與順序，和 `referenceDefault`；
- `RollingStock.standard`；
- 每種車型 1 節與 16 節的 `capacity`、`ratedCapacity`、`passengersPerSecond`、`RollingStock.price(of:cars:)`、`weight(of:cars:)`。

這個 commit 在 `main` 的程式上跑過，綠了才搬家。搬家之後同一個測試檔**一行不改**再跑一次。PR 會寫明「這個檔在第一個 commit 之後沒有被改過」，用 `git diff <第一個 commit> HEAD -- Tests/GameCoreTests/TrainTypeCatalogTests.swift` 為空來證明。

**2. 存檔寫出來的字串不變。**

- `TrainTypeNameTests.testTheCodesTheSavesStoreDidNotMove` 已經檢查每種車型編碼成 `["A"]` 這樣的字串，並且讀得回來；
- 第二段加一條：不認得的字串（`"XYZ"`）照舊讀不進來；
- 重播的 checksum 是 sorted-keys 的 JSON（`ReplayState.checksum`），車型寫出來的字串一樣，checksum 就一樣。

**3. golden、replay、存檔 fixture 一個都不改。**

- 有車型的 fixture：
  - `SaveFixtures/v36-steam-era.json`；
  - `v43-high-speed.json`；
  - `v44-door-crowding.json`；
  - `v49-rolling-stock-economics.json`；
  - `GoldenScenarios/rolling-stock-economics.json`；
- `ReplayFixtures/` 裡沒有車型，但 GameCore 一改就整組都跑；
- PR 用 `git diff --stat origin/main -- GoldenScenarios SaveFixtures ReplayFixtures` 為空證明一個檔都沒動；
- GameCore 一改，PR 的 CI 就跑全部 shard（決策 185），golden、存檔、重播全部要綠；
- **任何一個要改值，就停下來回報遊戲規劃 session，不推。**

**4. 順序不變。**

`allCases` 的順序就是表的順序。依它挑車型的地方：

- 選單；
- `NewGameCampaignTests` 用亂數取 `allCases.prefix(5)`。

所以表的順序和現在 enum 的順序相同，測試第 1 條也釘住它。

**5. 沒有浮點數，沒有新的計算。**

表上全是整數，屬性只是查表，和 `switch` 回傳同一個值。

第二段另外量一次效能，release build：

- 高鐵示範從 07:00 跑 600 tick；
- 讀檔時間；
- 和 `main` 比，差在量測誤差內才算數。

查表是陣列加位置，不比字串，所以預期不變。

## 4. 舊存檔怎麼讀

**格式不變，所以不升版、不加遷移、不加 fixture。**

- 車型在存檔裡仍是 `"type": "HSR"` 這樣一個字串（列車的 `type`、劇本的 `trainTypes`），讀法和現在一樣：
  - 字串對到表上的一列；
  - 對不到就是讀不進來的存檔，和現在一樣。
- `SavedGame.currentVersion` 維持 58（#611 預留 59，和這件無關）。
- 現有的四個含車型的存檔 fixture 照舊要讀得進來（§3 第 3 條）。

**之後新增車型時**：

- 照 CLAUDE.md 的規則（「舊存檔讀不進來的格式改變才升版」），只加一列不改格式，**不必升版**。
- 舊存檔在新 build 一定讀得進來，因為表只會多、不會少。
- **表上的一列永遠不刪、ID 永遠不改。** 不想再賣的車型改 `offer`，不刪列，因為舊存檔裡可能有它。

反過來，只認得舊表的 build 讀到有新車型的存檔，會讀不進來，錯誤訊息和現在讀到不認得的字串一樣。過去升版的一個附帶作用，是讓舊 build 說「這是新版本的存檔」；不升版就沒有這句。可以接受，原因是：

- TestFlight 的玩家只有最新的 build；
- 存檔不在裝置之間同步（iCloud 是 §6 之後的事）。

**之後改既有車型的數值時**（例如真實車長、檢修老化）：

- 那是行為改變，不是加資料。
- 照 §6 原來的計畫：新的世界開關或規則，加新的存檔版本，舊存檔保留舊的值（例如 16 m）。
- golden 要一個值一個值說明。
- 表上會多一欄，例如每節車長，依開關取用。這不屬於這次。

## 5. 第二段要動的檔案

| 檔案 | 改什麼 |
| --- | --- |
| `Tests/GameCoreTests/TrainTypeCatalogTests.swift`（新） | 第一個 commit：釘住現在的每個值（§3 第 1 條）；之後加：ID 不重複、`family == .highSpeed` 的不超載、`offer` 推出來的三個陣列、不認得的字串讀不進來 |
| `Sources/GameCore/Railway/TrainTypeCatalog.swift`（新） | `TrainTypeSpec`、`TrainFamily`、`TrainTypeOffer`、`TrainTypeCatalog.builtIn`。參考來源的註解從 `TrainType.swift` 搬過來，放在各列旁邊 |
| `Sources/GameCore/Railway/TrainType.swift` | `enum` → `struct`；屬性改成查表；`main`、`reference`、`offered` 由表推出；新增 `isHighSpeed`、`family`；`Train` 的 extension 不變 |
| `Sources/GameCore/Railway/RollingStock.swift` | `TrainType.pricing` 改成查表；`RollingStock.standard` 不動 |
| `Sources/GamePresentation/DisplayText.swift` | `title(in:)` 的 `switch` 改成依 ID 查的名稱表（文字一個字都不改） |
| `Sources/GamePresentation/TrainMotion.swift`、`Achievements.swift`、`LineStaffing.swift`、`HighSpeedText.swift` | `type == .highSpeed` 當「高鐵車組」用的地方改成 `type?.isHighSpeed == true`。`HighSpeedDemo.swift` 指定 `.highSpeed` 的地方是「要這一款」，不改 |
| `Sources/GamePresentation/RollingStockCatalog.swift`（#608，若已合併） | `Family` 改成 GameCore 的 `TrainFamily`（或 typealias），`init(_:)` 讀表；`title(in:)` 文字不改 |
| 測試裡 `switch` 車型的地方 | 照編譯器的錯誤改成查表；不改任何期望值 |
| `docs/ARCHITECTURE.md` | 決策 225：表、ID、四方理由、第 4 節的存檔規則（一列永遠不刪） |
| `docs/OVERVIEW.md`、`NEXT_PRIORITIES_2026-10-12.md` | 決策索引加一行；§5 第 2 項標「已做」；§6 的「實際車長」改寫成「在表上加一欄」 |

**不動**：

- `GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`；
- `SavedGame.swift`；
- App（`RailwayGameApp/`）：它只用 `TrainType` 的值與 `==`，`struct` 照樣編譯，由 macOS CI 確認；
- `Web/`。

**畫面上沒有新文字。**

CI：

- GameCore 改了，所以 PR 跑全部 shard；
- iOS 的閘門也會跑，因為 App 看得到 GamePresentation。

## 6. 參考檢查

`a91453/railway-reference-private`，`7888702`（本 session 的 shallow clone）：

| 參考 | 內容 | 在這裡 |
| --- | --- | --- |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` 的 `TRAIN_TYPES` | 9 種車型的 `ppc`（每節人數）與 `label` | 決策 66 已移植，`ratedCapacityPerCar`。第二段原樣搬進表，不改值 |
| 同檔 `LINE_TRAIN_TYPE_MAIN`、`LINE_TRAIN_TYPE_EXTRA` | 主要／其他車型 | `offer` 的 `referenceMain`、`referenceExtra` |
| 同檔 `HSR_TRAIN_CARS_CAPACITY`、`metroTrainUsesOperationalOverload` | 高鐵整組人數、高鐵不超載 | 決策 168 已移植：HSR 那列 80 人、`overloads: false` |
| 同檔 26 個城市的 `*_STOCK_MODELS`（`SINGAPORE_STOCK_MODELS`、`HONG_KONG_STOCK_MODELS`……：`code`、`ppc` 或 `cap`、`cars`、`speed`） | 各城市真實車款的人數、編組、速度 | **這次不移植**（不加新車型）。之後「更多車型」的來源，欄位對得上表：`ppc` → 每節人數、`speed` → 跑法的最高速、`cars` → 預設節數（表上還沒有這欄） |
| `Railway/` 的 `PERF_RULES`、`PERF_HSR` | 各車種的加減速與最高速 | 已是 `TrainPerformance` 的預設值；表的 `performance` 欄指向它們 |
| `Railway/site_archive_clean/memories/tainan-2026-09-12/fleet/catalog.json` | 13 款台鐵車輛的車體長、連結器間距、寬、高。例：EMU3000 中間車 `pitchM` 20.3、`bodyM` 19.6；頭車 21.35；TEMU2000 中間車 20.7；EMU800 20.3；莒光號 20.0。附來源與推定的門數 | **這次不移植**。之後真實車長的資料：一節的長度用連結器間距；世界座標每公尺 64 單位（`Train.carLength` 1,024 = 16 m），20.3 m ≈ 1,299 單位 |
| `OpenWorld/reference_snapshot/play/assets/taiwan-tra/`（`emu3000.glb`、`puyuma.glb`、`taroko.glb`）、`.../assets/trains/`（高鐵、磁浮、台鐵的車頭與車身，含 LOD1）、`Simulator/reference_snapshot/models/tra-e201/` | 3D 車款 | **這次不移植**。之後外觀依車種畫的時候，表上加「模型名稱」一欄對到它們（照 rolling-stock skill：參考模型是量尺，尺寸對照 catalog） |
| `Railway/site_archive_clean/rail-3d/assets/` | 只有 `blender-buildings-v1`、`historic-buildings-v2`、`blender-map-v1`、`wenhu-v1` | 沒有車款（nothing usable） |

這個 repository 裡已經有的：

- `Web/CityView/src/world/trains.js` 的 `STOCK`：每款的節數、長度、車鼻長、`highSpeed`。它的 `highSpeed` 和這次的 `family == .highSpeed` 是同一件事，之後外觀依車種畫時對齊；
- `.claude/skills/rolling-stock/SKILL.md`：做 3D 車的規則，這次不畫車，只讀了。

**外部專案**：這次沒有搜尋。理由是資料表就是一個 Swift 陣列，沒有需要借的演算法；程式是這個專案自己的。

## 7. 這次不做、之後做的

| 項目 | 在表上會是 | 依賴 |
| --- | --- | --- |
| 各車種的實際車長（§6） | 每節長度一欄（世界單位），依新的世界開關取用；舊存檔保留 16 m | 這件；新存檔版本；約 65 份 golden 要逐值說明 |
| 機廠 L2：檢修與老化（§5 第 4 項） | 檢修週期、耐用年數一欄；列車的車齡存在列車上（那才要升版） | 這件 |
| 更多車型（決策 224 的型錄、`*_STOCK_MODELS`、台鐵車款） | 加列；名稱表加列 | 這件 |
| 3D 與 2D 依車種畫 | 車鼻形狀、塗裝、模型名稱一欄（放 GamePresentation 的外觀表，依 ID 對） | 這件、rolling-stock skill |
| 依車種的聲音 | 聲音名稱，依 ID 對 | 決策 219 |
