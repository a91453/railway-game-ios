# 示範地圖與挑戰關掉的世界功能總表

日期：2026-10-27。基準是遊戲 `main` 4d5c799。
讀者：遊戲規劃，以及 10/31 公開測試之後要改示範地圖與挑戰的 session。派工單 AF（研究，只寫文件）。

> **怎麼做出來的**
> - 讀 `Sources/GamePresentation/` 裡每一個蓋世界的程式（`NewGame.swift`、`RealWorldDemo.swift`、`RealWorldDemoGround.swift`、`PingxiChallenge.swift`、`LiuMingchuanChallenge.swift`、`BranchLineChallenge.swift`、`Scenarios.swift`、`HighSpeedDemo.swift`、`TRADemo.swift`、`Lessons.swift`、`GameLauncher.swift` 等），逐行對 `GameWorld` 的 `set…` 開關（`Sources/GameCore/` 裡共 29 個，第 1 節）。
> - 理由從 `docs/ARCHITECTURE.md` 與 `docs/decisions/` 裡開關自己的決策找，附行號。
> - **VERIFIED**：表一、表二的每一格是讀程式與決策得來（出處都寫了行號）；不是從執行結果得來。
> - **UNVERIFIED**：第 3 節「打開會怎樣」的方向是讀決策與程式推的，沒有把開關打開量過。原因：量要改程式（蓋世界的程式或測試），本單不改。第 5 節說明哪些既有的報告測試可以量、少了哪一個。
> - 道路與公車那一欄：**AE 處理中**（派工單 AE，決策預計 440，`claude/old-taiwan-roads`）。AE 處理「存檔」打開道路；本文只列「開局」蓋世界時有沒有道路，並標出 AE 的範圍沒涵蓋的兩個開局（第 4.1 節）。不碰 AE 的檔案。

## 0. 摘要

- 起因：作者 2026-10-27 用 10/12 的平溪線存檔測試，不能開公車。新開的平溪線挑戰也一樣。
- 原因不只一個，也不只道路。**平溪線和實景示範一共關了 14 個功能**，其中只有 6 個（假日與天氣、建材、車門擁擠、車輛經濟、彈性派車、城市委託）寫過「挑戰的目標在沒有它時量的」這類明確理由，其他是「示範、挑戰、教學一起關」的預設清單，沒有針對這張地圖的理由。
- **道路與公車**：平溪線與實景示範開局時 `world.roads == nil`（`NewGame.swift:105-109` 只有空白地圖或 `land` 是空陣列的實景地圖才開路；這兩張傳進來的是讀好的土地，不符）。決策 400 的續篇（`docs/decisions/400.md:438`）列出開路的地圖：全台灣、台灣的地點、挑戰、高鐵示範，**沒有列平溪線與實景示範，也沒有寫為什麼**。這是疏漏，不是決定。
- 建議（第 6 節）：10/31 之後先開的三項是
  1. 平溪線與實景示範開局也開道路（3.30，與 AE 合作，不需重量目標）；
  2. 實景示範／高鐵示範／台鐵示範打開觀光（2.85）；
  3. 這三張示範打開真實轉乘（2.70）。
  彈性派車與靠左（各 2.65）次之。**挑戰不要開**車輛經濟、車門擁擠、距離需求、外地連絡、潮汐、寫實運轉、區間閉塞：開了就要重量目標（平溪線沒有報告測試，第 5 節）。

## 1. 有哪些開關

`GameWorld` 的 `set…`（`grep "func set" Sources/GameCore`）裡，屬於「世界功能」、示範與挑戰會刻意開或關的：

| 縮寫 | 開關 | 出處 | 預設（`GameWorld` 新世界、舊存檔缺 key） |
| --- | --- | --- | --- |
| TC | `setTrafficControl` 行車控制 | `GameWorld.swift:1732`（欄位 `:34`） | 關 |
| KL | `setKeepLeft` 靠左 | `Railway/KeepLeft.swift:21` | 關（`GameWorld.swift:121`） |
| RO | `setRealisticOperation` 寫實運轉 | `Railway/RealisticOperation.swift:62` | 關（`:128`） |
| BS | `setBlockSections` 區間閉塞 | `Railway/BlockSections.swift:37` | 關（`:135`） |
| CL | `setCurveSpeedLimits` 彎道限速 | `Railway/CurveSpeedRuns.swift:9` | 關（`:141`） |
| RC | `setRealCarLengths` 真實車長 | `GameWorld.swift:1502` | 關（`:147`） |
| FD | `setFlexDispatch` 彈性派車 | `Railway/FlexDispatch.swift:36` | 關（`:157`） |
| DC | `setDoorCrowding` 車門擁擠 | `Railway/DoorCrowding.swift:98` | 關（`:115`） |
| RE | `setRollingStockEconomics` 車輛經濟 | `Railway/RollingStock.swift:114` | 關（`:163`） |
| DD | `setDistanceDemand` 距離需求 | `Passenger/DistanceDemand.swift:75` | 關（`:110`） |
| OC | `setOutsideConnections` 外地連絡站 | `Passenger/DistanceDemand.swift:84` | 關（`:186`） |
| LD | `setLandDemand` 土地決定運量 | `City/LandDemand.swift:245` | 關（`:106`） |
| TD | `setTidalDemand` 潮汐 | `Passenger/PassengerDemand.swift:101` | 關（`:58`） |
| TG | `setTownGrowth` 城鎮成長 | `Passenger/TownGrowth.swift:101` | 關 |
| WD | `setWeeklyDemand` + `setDemandEvents` 週需求與需求事件 | `PassengerDemand.swift:89`、`DemandEvents.swift:136` | 關（`:52`） |
| TO | `setTourism` 觀光 | `Passenger/Tourism.swift:256` | `nil` |
| CR | `setCityRequests` 城市委託 | `Economy/Requests.swift:191` | `nil` |
| DI | `setDisruptions` 假日、天氣、颱風 | `Passenger/Holidays.swift:352` | `nil` |
| MS | `setModeShift` 汽機車分流 | `Passenger/ModeShift.swift:111` | `nil` |
| RT | `setRealTransfers` 真實轉乘 | `Passenger/TransferDemand.swift:34` | 關（`:191`） |
| EM | `setEconomyMode` 經營／免費 | `Economy/Operations.swift:31` | 見 `GameEconomy`；`newGame` 設經營 |
| LA | `setLineAccounts` 逐線報表（只記帳） | `Economy/LineAccounts.swift:320` | 關 |
| BM | `setBuildingMaterials` 建材（含貨運） | `Freight/Freight.swift:441`（欄位 `:203`） | 關 |
| CB | `setCityBuildings`、`setCityDemand`、`setCityFootprints`、`setAreaBuyOut` 城市建物 | `City/Building.swift:299`、`CityDemand.swift:186`、`CompanyBuildings.swift:261`、`:270` | 關（`:223-234`） |
| RD | 道路 `enableRoads`／`turnOnRoads` | `City/RoadGrid.swift:157`、`:171` | `roads == nil` |

沒有列的 `setSpeed`、`setZone`、`setStationDepot` 等是玩家的指令，不是世界功能。`setUnlimitedFunds` 只有演示模式用（決策 351）。

## 2. 表一：每種開局 × 每個功能

●＝開，○＝關。「簡單」「寫實」指新遊戲的規則（決策 258）：簡單把 RO、BS、CL、DC、RE、BM 與天氣關掉（`NewGame.swift:490-504`）。

開局代號：

| 代號 | 開局 | 蓋世界的程式 |
| --- | --- | --- |
| A | 空白新遊戲（簡單，App 預設） | `GameLauncher.newWorld` → `GameWorld.newGame`（`GameLauncher.swift:445-470`、`NewGame.swift:49-188`）→ `NewGameOptions.apply`（`NewGame.swift:689-704`） |
| B | 空白新遊戲（寫實） | 同 A，`rules = .realistic` |
| C | 全台灣 | `startWholeTaiwan` → `newWholeTaiwanGame`（`WholeTaiwan.swift:68`）→ `options.apply`（`GameLauncher.swift:489-499`） |
| D | 台灣的地點（一塊一塊買）、演示模式的地點 | `newRealWorldExpansionGame`（`RealWorldExpansion.swift:280`）；演示模式 `GameLauncher.swift:447-451` |
| E | 台灣以外的城市（沒有人口資料的實景地圖） | `newGame(anchor:, land: nil)`（`GameLauncher.swift:459`） |
| F | 示範地圖 `DemoWorld`（含網站截圖場景） | `NewGame.swift:265-292`；截圖 `ScreenshotScene.swift:37、78` |
| G | 實景示範（有地形／無地形） | `RealWorldDemoGround.swift:34-68`／`RealWorldDemo.swift:84-119` |
| H | 平溪線挑戰 | `PingxiChallenge.swift:70-119`，建在 G 無地形版上 |
| I | 劉銘傳挑戰 | `LiuMingchuanChallenge.swift:178-205` |
| J | 每條支線挑戰 | `BranchLineChallenge.swift:119-143` |
| K | 沙盒挑戰、每週挑戰（空白地圖） | `Scenarios.swift:151-175`、`WeeklyChallenge.swift:135` |
| L | 高鐵示範 | `HighSpeedDemo.swift:261-288`、`:1097` |
| M | 台鐵示範（宜蘭線） | `TRADemo.swift:134`，走高鐵示範同一條建造路徑 |
| N | 教學、課程 | `Lessons.swift:889-915`（`newGame(eventSeed:, rules: .simple)`） |
| O1 | 畫面幀時測試（`FrameTimeBench`） | `FrameTimeBench.swift:95` |
| O2 | UI 測試專用世界 | `RailwayGameApp/App/FeatureUITestWorld.swift`（光禿的 `GameWorld(bounds:)`） |

### 表一之一：運轉規則

| 開局 | TC 行車控制 | KL 靠左 | RO 寫實運轉 | BS 區間閉塞 | CL 彎道限速 | RC 真實車長 | FD 彈性派車 | DC 車門擁擠 |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| A 空白·簡單 | ● | ● | ○ | ○ | ○ | ● | ● | ○ |
| B 空白·寫實 | ● | ● | ● | ● | ● | ● | ● | ● |
| C 全台灣 | ●（同 A／B 的規則） | ● | ○／● | ○／● | ○／● | ● | ● | ○／● |
| D 台灣的地點 | ● | ● | ○／● | ○／● | ○／● | ● | ● | ○／● |
| E 台灣以外 | ● | ● | ○／● | ○／● | ○／● | ● | ● | ○／● |
| F 示範地圖 | ● | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| G 實景示範 | ● | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| H 平溪線 | ● | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| I 劉銘傳 | ● | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| J 支線 | ● | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| K 沙盒／每週 | ● | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| L 高鐵示範 | **○** | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| M 台鐵示範 | **○** | **●** | ○ | ○ | ○ | ○ | ○ | ○ |
| N 教學／課程 | ● | ● | ○ | ○ | ○ | ● | ● | ○ |
| O1 幀時測試 | ● | ● | ● | ● | ● | ● | ● | ● |
| O2 UI 測試世界 | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ |

出處：

| 開局 | 行 |
| --- | --- |
| A–E | `NewGame.swift:62`（TC）、`:125`（KL）、`:128`（RO）、`:131`（BS）、`:133`（CL）、`:135`（RC）、`:141`（FD）、`:122`（DC）；簡單關 RO/BS/CL/DC：`NewGame.swift:494-497` |
| F | `NewGame.swift:275`（DC）、`:277`（FD）、`:279`（KL）、`:281`（RO）、`:283`（BS）、`:284`（CL）、`:285`（RC）；TC 沒動（`:62` 開） |
| G | 有地形 `RealWorldDemoGround.swift:52`（DC）、`:54`（FD）、`:56`（KL）、`:58`（RO）、`:60`（BS）、`:61`（CL）、`:62`（RC）；無地形 `RealWorldDemo.swift:103、105、107、109、111、112、113` |
| H | 沿用 G 無地形版（`PingxiChallenge.swift:76`），自己又關一次：`:88`（DC）、`:90`（FD）、`:92`（KL）、`:94`（RO）、`:96`（BS）、`:97`（CL）、`:98`（RC） |
| I | `LiuMingchuanChallenge.swift:189`（DC）、`:191`（FD）、`:193`（KL）、`:195`（RO）、`:197`（BS）、`:198`（CL）、`:199`（RC） |
| J | `BranchLineChallenge.swift:130`（DC）、`:132`（FD）、`:133`（KL）、`:134`（RO）、`:135`（BS）、`:136`（CL）、`:137`（RC） |
| K | `Scenarios.swift:159`（DC）、`:161`（FD）、`:163`（KL）、`:165`（RO）、`:167`（BS）、`:168`（CL）、`:169`（RC） |
| L | `HighSpeedDemo.swift:272`（DC）、`:274`（FD）、`:276`（KL）、`:278`（RO）、`:280`（BS）、`:281`（CL）、`:282`（RC）；TC：`:1097` 的 `setTrafficControl(false)`，註解「Traffic control is off (see ``HighSpeedDemo``)」 |
| M | 同 L；`HighSpeedDemo.swift:236` 的 `setKeepLeft(spec.keepLeft)`，台鐵 `TRADemo.swift:134` 是 `true`，高鐵 `RealLineDemoSpec.swift:75` 預設 `false` |
| N | `Lessons.swift:897` 的 `newGame(eventSeed: Lesson.seed, rules: .simple)`，簡單關 RO/BS/CL/DC（`NewGame.swift:494-497`），TC、KL、RC、FD 保持 `newGame` 的開 |
| O1 | `GameWorld.newGame(anchor:, eventSeed:)` 預設 `rules: .realistic`（`NewGame.swift:51`），之後沒動 |
| O2 | `GameWorld(bounds:economy:clock:)`，沒有 `newGame`；`isTrafficControlEnabled` 沒設就是關（`GameWorld.swift:4866` 缺 key＝關）。只有 `setTourism`（`:57`）、`setDisruptions(nil)`、`setCityRequests(nil)`（`:100-101`）、`setUnlimitedFunds`（`:80`）明寫 |

### 表一之二：需求與城市

| 開局 | DD 距離需求 | OC 外地連絡 | LD 土地決定運量 | TD 潮汐 | TG 城鎮成長 | WD 週需求與事件 | TO 觀光 | CR 城市委託 | MS 汽機車分流 | RT 真實轉乘 |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| A 空白·簡單 | ● | ●（選項） | ● | ● | ● | ● | ●（抽出的景點） | ● | ●（簡單） | ○ |
| B 空白·寫實 | ● | ●（選項） | ● | ● | ● | ● | ● | ● | ●（寫實） | ○ |
| C 全台灣 | ● | **○**（邊緣是海） | ● | ● | ● | ● | ●（台灣的景點） | ● | ● | ●（選項） |
| D 台灣的地點 | ● | ●（選項） | ● | ● | ● | ● | ● | ● | ● | ●（選項） |
| E 台灣以外 | ● | ●（選項） | ● | ● | ● | ● | ○（目錄只有台灣） | ● | ● | ●（選項；沒有真實車站可轉） |
| F 示範地圖 | **○** | **○** | ● | **○** | ● | ● | **○** | **○** | ○ | ○ |
| G 實景示範 | **○** | **○** | **○** | **○** | ● | ● | **○** | **○** | ○ | ○ |
| H 平溪線 | ○ | ○ | ○ | ○ | ● | ● | ●（只有平溪天燈） | ○ | ○ | ○ |
| I 劉銘傳 | ● | ○ | ● | ○ | ● | ● | ○ | ○ | ○ | ○ |
| J 支線 | ● | ○ | ● | ○ | ● | ● | ●（該線的景點） | ○ | ○ | ○ |
| K 沙盒／每週 | ● | ● | ● | ○ | ● | ● | ○ | ○ | ○ | ○ |
| L 高鐵示範 | ● | ○ | ● | ○ | ● | ● | ○ | ○ | ○ | ○ |
| M 台鐵示範 | ● | ○ | ● | ○ | ● | ● | ○ | ○ | ○ | ○ |
| N 教學／課程 | ● | ● | ● | ○ | ● | ● | ○（第 9 課起一處） | ○（第 10 課起） | ○ | ○ |
| O1 幀時測試 | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ○ |
| O2 UI 測試世界 | ○ | ○ | ○ | ○ | ○ | ○ | 指定 | ○ | ○ | ○ |

出處：

| 開局 | 行 |
| --- | --- |
| A–E 預設 | `NewGame.swift:118`（DD）、`:119`（OC：`bounds != WholeTaiwan.bounds`）、`:158`（LD）、`:162`（TD）、`:87`（TG）、`:77`、`:80`（WD）、`:150-155`（TO）、`:181`（CR）；MS、RT、OC 選項：`NewGame.swift:697-703`（`NewGameOptions.apply`） |
| F | `NewGame.swift:271`（DD）、`:272`（OC）、`:287`（TD）、`:289`（TO）、`:291`（CR）；LD 沒動（決策 78 明說開，`ARCHITECTURE.md:3102`） |
| G | 無地形 `RealWorldDemo.swift:94`（LD）、`:99`（DD）、`:100`（OC）、`:115`（TD）、`:117`（TO）、`:119`（CR）；有地形 `RealWorldDemoGround.swift:46、49、50、64、66、68` |
| H | G 的全部，加 `PingxiChallenge.swift:100`（TD，再關一次）、`:104`（TO 只放 `p01`） |
| I | `LiuMingchuanChallenge.swift:181`（OC）、`:201`（TD）、`:203`（TO）、`:205`（CR）；DD、LD 沒動 |
| J | `BranchLineChallenge.swift:122`（OC）、`:139`（TD）、`:140`（CR）、`:143`（TO 放該線的景點）；DD、LD 沒動 |
| K | `Scenarios.swift:171`（TD）、`:173`（TO）、`:175`（CR）；OC 沒動（標準地圖有邊緣） |
| L、M | `HighSpeedDemo.swift:284`（TD）、`:286`（TO）、`:288`（CR）；OC 是 `bounds != WholeTaiwan.bounds`＝關（`NewGame.swift:119`） |
| N | `Lessons.swift:900`（TO）、`:901`（CR）、`:903`（TD）、`:905`（第 9 課起一處景點）、`:910`（第 10 課起 CR） |
| MS、RT（F–N） | 這些都不經 `NewGameOptions.apply`，所以保持 `nil`／關；決策 332 `docs/decisions/332.md:54` 明說「`GameWorld.newGame` 本身不打開」，決策 298（`ARCHITECTURE.md:13324`）明說「空白地圖、示範、教學、挑戰、舊存檔都關」 |

### 表一之三：經濟、天氣、貨運、城市建物與道路

| 開局 | EM 經營 | RE 車輛經濟 | LA 逐線報表 | BM 建材 | DI 假日與天氣 | CB 城市建物與需求 | AB 收購城市建物 | RD 道路與公車 |
| --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| A 空白·簡單 | ● | ○ | ● | ○ | 假日●天氣○ | ● | ○ | ●（`NewGame.swift:106`） |
| B 空白·寫實 | ● | ● | ● | ● | 假日●天氣● | ● | ○ | ● |
| C 全台灣 | ● | ○／● | ● | ○／● | 假日● | ● | ● | ●（`:108`，邊用邊讀底圖路） |
| D 台灣的地點 | ● | ○／● | ● | ○／● | 假日● | ● | ● | ● |
| E 台灣以外 | ● | ○／● | ● | ○／● | 該國假日● | ● | ● | **○**（`land == nil`，`:105-109` 都不符）；`roadsOffer == .unreadable` |
| F 示範地圖 | ● | ○ | ● | ● | 輕●（含天氣） | ● | ○ | ●（`:106`） |
| G 實景示範 | ● | ○ | ● | ● | 輕● | ● | ● | **○**（AE 處理中，見 4.1） |
| H 平溪線 | ● | ○ | ● | ○ | **○** | ● | ● | **○**（AE 處理中，見 4.1） |
| I 劉銘傳 | ● | ○ | ● | ○ | **○** | ● | ● | ●（`:108`） |
| J 支線 | ● | ○ | ● | ○ | **○** | ● | ● | ● |
| K 沙盒／每週 | ● | ○ | ● | ○ | **○** | ● | ○ | ● |
| L 高鐵示範 | ● | ○ | ● | ● | 輕● | ● | ● | ●（建好後 `readingRoads` 讀路，`GameLauncher.swift:778`） |
| M 台鐵示範 | ● | ○ | ● | ● | 輕● | ● | ● | ● |
| N 教學／課程 | ● | ○ | ● | ○ | **○** | ● | ○ | ●（但工具列不給公車：`allowsBusTool` 排除教學與課程） |
| O1 幀時測試 | ● | ● | ● | ● | 輕● | ● | ● | **○**（`land == nil`） |
| O2 UI 測試世界 | 預設 | ○ | ○ | ○ | ○ | ○ | ○ | ○ |

出處：

| 開局 | 行 |
| --- | --- |
| A–E | `NewGame.swift:65`（EM）、`:138`（RE）、`:146`（LA）、`:177`（BM）、`:85`（DI）、`:165-174`（CB、AB）、`:105-109`（RD）；簡單 `:490-504`；選項 `:689-696` |
| F | `NewGame.swift:276`（RE）；BM、DI、RD 沒動（`newGame` 的預設，`:85`、`:177`、`:106`） |
| G | `RealWorldDemo.swift:104`／`RealWorldDemoGround.swift:53`（RE）；BM、DI 沒動；RD：`makeFlat` 傳 `land:`（`RealWorldDemo.swift:84-88`），`NewGame.swift:105-109` 兩個條件都不成立 |
| H | `PingxiChallenge.swift:86`（DI）、`:87`（BM）、`:89`（RE） |
| I | `LiuMingchuanChallenge.swift:183`（DI）、`:188`（BM）、`:190`（RE）；`land: []`（`:179`）→ `NewGame.swift:108` 開路 |
| J | `BranchLineChallenge.swift:128`（DI）、`:129`（BM）、`:131`（RE） |
| K | `Scenarios.swift:157`（DI）、`:158`（BM）、`:160`（RE） |
| L、M | `HighSpeedDemo.swift:273`（RE）；BM、DI 沒動；`land: []`（`:259`）→ `NewGame.swift:108` |
| N | `Lessons.swift:899`（DI）、`:897`（簡單關 RE、BM，`NewGame.swift:498-499`） |
| O1、O2 | 同上 |

LA（逐線報表）沒有任何示範或挑戰關它：決策 179「只是記錄，不改玩法，所以挑戰、教學、示範都留著」（`NewGame.swift:143-146`）。

## 3. 表二：每個「關」的理由

找法：開關自己的決策裡寫「示範、挑戰、教學關」的那一段；再看程式註解。「理由」欄只抄原文，沒有加我的判斷。「寫了理由？」：**有**＝說了為什麼這張地圖要關；**預設清單**＝只寫了「一起關」；**沒寫理由**＝找不到。

| 功能 | 決策 | 原文（出處） | 寫了理由？ |
| --- | --- | --- | --- |
| DI 假日與天氣（挑戰） | 154、145、157 | 「教學、沙盒挑戰與每週挑戰、平溪線劇本都關閉：它們的目標是不放假量的（決策 145）」（`ARCHITECTURE.md:4874`）；後來加鎖：挑戰中不能打開，因為「連假的尖峰可能讓『每日運量』目標提早達成」（`:4891`） | **有** |
| DI（示範地圖、實景示範、高鐵／台鐵示範） | 154 | 決策 154 沒提示範地圖；程式也沒關，所以示範是「輕」開著 | 不適用（開著） |
| BM 建材（挑戰） | 156、157 | 「教學、沙盒挑戰、平溪線劇本與劉銘傳劇本（決策 153）關閉建材，它們的目標是不用建材量的（決策 145）」（`:4963`） | **有** |
| DC 車門擁擠 | 169 | 「示範地圖、挑戰與教學關掉，它們的數字是沒有這個規則…」（`:5463`）；程式註解「its challenge's targets were measured without」（`RealWorldDemo.swift:101-102`）、高鐵示範「the service levels were measured without」（`HighSpeedDemo.swift:269-271`） | **有** |
| FD 彈性派車 | 172 | 「舊存檔、golden、replay、示範地圖、挑戰與教學…都關著，和決策 154、157、169、170 一樣」；理由只有「開關打開時 `ReplayFixtures/line-patterns.json` 的檢查碼 12 會變，所以才有開關」（`:5790、5826`）。決策 258：新遊戲彈性派車保留，「§1.2 量到開或關的數字一樣」（`:10605`） | 預設清單；但 258 說開或關數字一樣 |
| RE 車輛經濟 | 180 | 「舊存檔、golden、replay、示範地圖、挑戰與教學…都關著，它們量過的數字一個都不變」（`:5958`） | **有**（數字不變） |
| TO 觀光 | 174 | 「舊存檔、教學、挑戰、示範地圖…關閉，和決策 154、157、169、170 一樣自己決定，它們量過的數字不變。平溪線劇本只放平溪天燈一處（十分）：它的運量目標算進觀光客」（`:5864`） | **有**（平溪線有例外並寫了為什麼） |
| CR 城市委託 | 183 | 「教學、挑戰、示範地圖關閉，和決策 154、169–174 一樣自己決定，它們量過的數字不變」（`:6132`） | **有** |
| KL 靠左 | 202 | 「示範地圖…、挑戰…與教學關掉，它們的路線、班距與數字是沒有這個規則量的」（`:7172`）；「高鐵示範的上行本來就鋪在下行西側，關著也已經靠左」 | **有**；台鐵示範是 `true`（`TRADemo.swift:134`） |
| RO 寫實運轉 | 207 | 「示範、教學、挑戰、舊存檔關」（作者定案，`:7349`）；「它們的時刻表與數字是沒有這個規則量的」（`:7353`） | **有**（作者定的） |
| BS 區間閉塞 | 212 | 「示範、挑戰、教學、平溪與劉銘傳劇本、實景示範關掉；高鐵示範這個 PR 不打開行車控制（量完另開 PR）」（`:7610`）；「高鐵示範等這些做完再打開行車控制」（`:7607`） | **有**；**行車控制在高鐵示範仍關**（見下） |
| TC 行車控制（高鐵／台鐵示範） | 197、212、228 | 高鐵示範打開行車控制時「191 班丟 97 班」（`:7585`）；之後 212 的量測「誤點少了三到四成，丟班沒有變」（`:7636` 前後）。程式註解只有 "Traffic control is off (see ``HighSpeedDemo``)" | 有（當時）；**之後有沒有再量沒找到** |
| CL 彎道限速 | 217 | 「示範地圖、挑戰、教學、`GameWorld` 的新世界與舊存檔關掉」（`:7805`）；真實時刻表的路線有豁免：一段在限速下排不下就不用限速（`:7813`） | **預設清單** |
| RC 真實車長 | 227 | 「示範地圖、挑戰、教學、`GameWorld` 的新世界與舊存檔關掉」（`:8705`） | **沒寫理由**（只寫「第一版沒有設定介面」） |
| DD 距離需求、OC 外地連絡 | 137 | 「兩張示範地圖都關：空白示範的五站相距幾百公尺（為了一個畫面看得到工具），實景示範的運量是真實車站的、挑戰的目標也是在舊規則下量的」（`:4367`）；「實景示範的縱貫線、宜蘭線本來就跑出地圖，等作者決定要不要也開外地連絡（要重新量平溪線挑戰的目標）」（`:4383`）。劉銘傳、支線的 OC 關：「its edges bring no one from beyond the map」（`LiuMingchuanChallenge.swift:170-176`） | **有** |
| LD 土地需求（實景示範） | 78 | 「實景示範不改：`RealWorldDemo` 仍關閉土地需求、保留每站的運量。平溪線一帶大多是靠景點的運量，土地沒有景點；…12 站合計每天只有約 1.4 萬旅次（十分 405、菁桐 552），沒有 App 的人口資料時是 0」（`:3105`） | **有** |
| TD 潮汐 | 319 | 「示範地圖（四個）、挑戰（平溪、支線、劉銘傳、沙盒挑戰）與入門關卡關（它們的目標是沒有潮汐時量的）」（`:14869`） | **有** |
| MS 汽機車分流 | 332 | 「`GameWorld.newGame` 本身不打開，所以用它蓋的教學、入門關卡、挑戰…示範地圖…」（`332.md:54`） | **有**（只因為不在 `NewGameOptions.apply` 裡） |
| RT 真實轉乘 | 298 | 「只在實景地圖打開；空白地圖、示範、教學、挑戰、舊存檔都關」（`:13324`） | 預設清單 |
| RD 道路（平溪線、實景示範） | 400 | 決策 400 續篇列開路的地圖：全台灣、台灣的地點、挑戰、高鐵示範（`400.md:438`）；平溪線、實景示範不在列，也沒有寫為什麼 | **沒寫理由** |
| RD 道路（教學、課程） | 428 | `allowsBusTool` 排除教學與課程 | 有（教學要簡單） |
| DemoWorld 的 TD、TO、CR、DD、OC、RC… | 137、319 等 | 同上列各功能；DemoWorld 的 DD／OC 另外說「五站相距幾百公尺（為了一個畫面看得到工具）」 | 有 |

**沒有任何關的理由說「這張地圖不能開」的**：RC、CL、RT、平溪線與實景示範的 RD。這些是第 6 節最先看的。

## 4. 每個關掉的功能：打開會怎樣

### 4.0 先說兩件共通的事

1. **golden、replay、存檔 fixture 不受影響。** 示範與挑戰的世界是開局時由程式蓋的（`GameLauncher.swift:516-571`），不是存檔。`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 是檔案；GameCore 的測試（`Tests/GameCoreTests/`）沒有一個用 `DemoWorld`、`PingxiChallenge`、`RealWorldDemo`、`HighSpeedDemo`（grep 確認）。`SaveFixtures/README.md:153-156` 的示範存檔是之前寫好的檔案，不是用現在的 `DemoWorld.make` 重蓋的。所以改蓋世界的程式不改任何 fixture，也不用升存檔版本。
2. **會動的是 GamePresentation 的測試與挑戰目標。** 用到這些蓋世界的程式的測試很多：`DemoWorld.make` 在 53 個測試檔、`newGame(lesson:)` 10 個、`newGame(challenge:)` 12 個、`LiuMingchuanChallenge.make` 11 個、`HighSpeedDemo.make` 7 個、`RealWorldDemo.make` 4 個、`PingxiChallenge.make` 2 個（`PingxiChallengeTests`、`GameLauncherTests`）。其中很多在斷言目標或運量的數字，開關一變就紅。UI 測試（`RailwayGameApp/UITests/`）靠 `DemoWorld` 的 Central 在地圖正中、第一天的運量，也會受影響。
3. 開關打開之後，**世界仍可存檔**（每個開關開著才存），所以新蓋的挑戰存檔會比舊的多幾個 key；舊的挑戰存檔照舊讀得進來（缺 key＝關）。

### 4.1 道路與公車（RD）

- 現況：平溪線（H）與實景示範（G）開局 `roads == nil`；台灣以外的城市（E）與幀時測試（O1）也沒有。其他實景類開局（全台灣、台灣的地點、劉銘傳、支線、高鐵／台鐵示範）都有。條件在 `NewGame.swift:105-109`：`anchor == nil && land == nil`（空白）或 `anchor != nil && land.isEmpty`（邊用邊讀）才 `enableRoads`；平溪線與實景示範傳進讀好的土地（或 `nil`），兩個條件都不成立。`GameSession.readRoads`（`RealRoadCells.swift:169-170`）要 `world.roads` 已經開著才讀底圖，所以也不會事後補上。
- **AE 處理中**：AE 做的是「存檔」：台灣境內沒有 `landBlocks` 的實景存檔，也能從打包的底圖打開道路（`turnOnRoads`，決策 428 的缺口）。AE 預計不升存檔、不動 golden。
- AE 預計**沒涵蓋**的兩個開局，待 AE 結論確認：
  1. **新開的平溪線挑戰與實景示範**：它們有 `landBlocks`（H、G 的土地是 `land:` 傳入、`GameSession` 邊讀），所以 AE 的「打開道路」按鈕應該能用；但新開局本身不是已經開好的。這是設計問題：開局直接開路（改蓋世界的程式），還是讓玩家按鈕打開（AE 已有）。建議開局直接開（第 6 節）。
  2. 台灣以外的城市（E）：決策 400 與 428 都寫了「底圖只有台灣，開了路也長不出來」，AE 的結論是「說清楚原因」。這是資料限制，不是關掉的功能。
- 打開會怎樣：路不載客、不收錢、不影響票收與旅客（`400.md:406`），所以不動挑戰目標。會變的是 3D 街景（路會每月長）與公車工具可用。要確認的只有一項：平溪線的 `GameSession.readLandRoundStations` 在開局時讀路的時間（高鐵示範讀 2,500 塊曾讓主執行緒卡 28–58 秒，`GameLauncher.swift:765-778` 註解）；平溪線只有 12 站，量級小得多，**UNVERIFIED**。
- 存檔／golden／replay：不動。指令紀錄：開局時蓋世界不經指令，不新增指令。

### 4.2 靠左（KL）

- 影響：只在雙線區間改選路（`ARCHITECTURE.md:7172`）。單線的線不動（支線、平溪支線通常是單線，**我沒有逐線確認**）；實景示範的縱貫線、宜蘭線是雙線，改的是「開出去的車走哪一股」。
- 挑戰目標：平溪線的目標是乘客數與一年淨利，列車走哪一股不改運量，只可能改交會處的等待。**風險低**。
- 實景示範有真實班次的路線（`runs`）照真實時刻排點，走哪一股由進路決定。台鐵示範已經開（`TRADemo.swift:134`）。高鐵示範的上行本來就鋪在下行西側，已經靠左（`:7172`），開或關不變。
- 存檔／golden／replay：不動。

### 4.3 彈性派車（FD）

- 影響：列車可以從路線任一端發車，停在別處的先空車回送（決策 172）。決策 258 量過「開或關的數字一樣」（`:10605`）。
- 風險：有真實班次（`runs`）的路線在打開時要看 `ReplayFixtures/line-patterns.json` 的檢查碼 12 會變（那是 GameCore replay，與蓋世界無關，開關是世界自己的，replay 檔不動）。示範的列車一開始就停在特定位置，打開後行為可能不同，**UNVERIFIED**。
- 存檔／golden／replay：不動。

### 4.4 彎道限速（CL）

- 影響：列車在彎道前煞車（決策 217）。真實班次的路線有豁免：一段行駛在限速下排不下，這一段就不用限速（`:7813`），所以平溪線、實景示範、高鐵與台鐵示範的真實班次不會被拖慢。玩家自己開的車會慢一些。
- 風險：玩家編的路線運行時間變長，平溪線「每日運量」目標會慢一點，要重量。
- 效能：決策 217 量過高鐵示範 +35%（強制打開的最壞情況）；讀檔不變。**示範在手機上的幀時要實機看**。
- 存檔／golden／replay：不動。

### 4.5 真實車長（RC）

- 影響：`Train.carPitch` 在買車與改車型時依開關定；打開後買的車用車型的真實節長（決策 227）。月台停不停得下取決於列車長：「12 節高鐵停不進 12 × 16 m 的月台、停得進 12 × 25 m 的」（`:8729`）。
- 風險：示範的月台長度是蓋世界時固定的（高鐵示範的 12 個站、宜蘭線的各站）。打開後示範自己放的列車（開局就有的）要確認每個站停得下；玩家買的車停不進時要顯示原因。**UNVERIFIED**：我沒有逐站對月台長度與車長。
- 3D 好處：列車與月台的比例對（美術 3）。
- 存檔／golden／replay：不動。

### 4.6 寫實運轉與區間閉塞（RO、BS）

- 影響：RO 把時刻表排點改成「正常加減速＋4% 恢復時間」，高鐵停站 110 秒，並有準點率（決策 207）；BS 把長區間切成閉塞段（決策 212）。
- 挑戰目標：RO 讓每段多 4%，整條線的往返變長，運量與收入會降；平溪線與劉銘傳都是短線，影響以百分比算大約相同，但要重量。BS 只對「長區間＋行車控制」有用，短支線幾乎無影響。
- 示範：實景示範與高鐵／台鐵示範跑真實班次，時間本來就是真實的（決策 207 明說），打開不改。
- 存檔／golden／replay：不動。

### 4.7 車門擁擠（DC）

- 影響：擁擠的列車停站時間變長（決策 169）。
- 挑戰目標：平溪線的天燈節有大批人潮湧進十分和平溪（`PingxiChallenge.swift:67` 的 `festivalBoost`），打開後停站更久，目標更難；**會動到平溪線的目標**。劉銘傳是 50 人的蒸汽客車（`LiuMingchuanChallenge.swift` 的註解：「a crowd would hardly slow」），影響小。
- 存檔／golden／replay：不動。

### 4.8 車輛經濟（RE）

- 影響：列車的價格、重量、營運成本、出售價依車型與節數而不同（決策 180）。
- 挑戰目標：平溪線的目標有「一年淨利」，營運成本一變淨利就變。**一定動到平溪線與劉銘傳與支線的目標**。
- 示範：示範自己放的列車（`DemoWorld` 的 4 列車）會依車型付營運成本，`DemoWorld` 的「約 8 天回本」（決策 78、`NewGameBalanceTests`）會變。
- 存檔／golden／replay：不動。

### 4.9 距離需求與外地連絡站（DD、OC）

- 影響：2 公里內的旅次只留一部分，地圖邊緣的車站帶來外地旅客（決策 137）。
- 示範地圖（F）的五站相距幾百公尺，打開 DD 會讓運量大減（決策 137 明說關是因此）。實景示範（G）的運量是真實車站的，加 OC 會把縱貫線與宜蘭線兩端的車站多出外地旅客。
- 挑戰：「要重新量平溪線挑戰的目標」（`:4383`）。**動目標**。
- 存檔／golden／replay：不動。

### 4.10 土地決定運量（LD）、潮汐（TD）

- LD（G、H）：沒有人口資料時為 0（`:3105`），所以打開會讓這兩張地圖沒有運量；有資料時只有 1.4 萬旅次，遠小於現在的真實車站運量。**維持關**。
- TD：決策 319 寫「強弱從土地來」。G、H 的 LD 關，沒有土地的家／工作比例，所以 TD 在這兩張**幾乎沒有作用**（`PassengerDemand.swift:905` 只有 01:00 的日界位移）；**UNVERIFIED**。F 的 LD 開，打開有作用，但 `DemoWorld` 的「約 8 天回本」是沒有潮汐時量的（決策 78），要重量。

### 4.11 觀光（TO）、城市委託（CR）

- TO：G（實景示範）的 `setTourism(nil)` 與平溪線的 `p01` 例外並存：平溪線挑戰已經有平溪天燈，G 卻沒有。實景示範的畫面就是平溪線、宜蘭線、縱貫線、深澳線，應該有九份、平溪天燈這些景點。挑戰不開（目標含觀光客，決策 174）。高鐵與台鐵示範也可開（景點在 `AttractionCatalog`，已有 `only:` 篩選，`PingxiChallenge.swift:104`）。
- 打開之後的運量：景點帶來的是週末與連假的額外觀光客（決策 174，`Tourism.captureRate` 200‰）。示範沒有目標，所以不影響評分；影響的是示範的畫面與車站卡。
- CR：城市委託每月 1 日抽（決策 183）。示範與挑戰不開的理由都是「量過的數字不變」；沒有目標的示範（G、L、M）可開。F（DemoWorld）UI 測試有 `-city-requests` 專用路徑（`GameLauncher.swift:638-641`），**維持關**，免得測試的地圖有請託。
- 存檔／golden／replay：不動。

### 4.12 汽機車分流（MS）與真實轉乘（RT）

- MS：打開後 2 公里以外的旅次一部分改騎機車或開車（決策 332）。示範地圖全在 2 公里內，沒影響（`332.md:106`）；實景示範的真實班次車站相距遠，**會降低運量**。示範沒有目標，但會讓看起來的運量下降，不建議為了「完整」打開。
- RT：在真實車站旁加轉乘旅客（決策 298）。需要 `NewGameOptions.apply` 內的資料（真實運量），示範的蓋世界路徑沒有。實作要把 `RealTransfers` 的計算（presentation）接到示範的蓋世界程式。對鐵道迷價值高（5），開發成本中。

### 4.13 其他

- 假日與天氣（DI）：挑戰是「連假的尖峰可能讓『每日運量』目標提早達成」，維持關（決策 154 後續修正，已加鎖）。示範（F、G、L、M）已開。
- 建材（BM）：挑戰維持關（決策 157）。
- 行車控制（TC，高鐵／台鐵示範）：關著。理由是當時開了丟班（決策 197、212）；之後 212 的量測顯示開了誤點少三到四成（`:7636` 附近），沒找到後續把示範打開的決策。**待重量**：`TrafficControlTimingReportTests`（`TRAFFIC_TIMING_BLOCKS=1`）。

## 5. 報告測試：能量什麼，少什麼

`.github/scripts/swift-shards.sh` 是 CI 把測試分成幾個 shard 的腳本，不是量平衡的工具；本單沒有用它跑完整 shard（那是 CI 的事）。報告測試是各自的環境變數開關，預設 `XCTSkip`。

| 目標 | 既有報告 | 環境變數 | 能不能直接量「打開之後」 |
| --- | --- | --- | --- |
| 沙盒挑戰（空白，K） | `ChallengeReportTests` | `CHALLENGE_REPORT=<種子數>`、`CHALLENGE_ONLY`、`CHALLENGE_PLAY` | 只能量目前的（關著）。要量打開的得改 `Scenarios.swift` 或測試。 |
| 劉銘傳（I） | `LiuMingchuanReportTests` | `LIU_REPORT=1`、`LIU_PLAY`、`LIU_DAYS` | 同上 |
| 教學／課程（N） | `LessonTargetReportTests` | `LESSON_REPORT=<天數>` | 同上 |
| 高鐵示範（L） | `HighSpeedReportTests`、`TrafficControlTimingReportTests` | `BALANCE_REPORT=1`、`TRAFFIC_TIMING_BLOCKS=1` | `TrafficControlTimingReportTests` 有打開行車控制與閉塞的旋鈕 |
| 空白線平衡 | `BalanceReportTests` | `BALANCE_REPORT=…`、`BALANCE_NO_REALISTIC=1`、`BALANCE_NO_MATERIALS=1`、`BALANCE_MODE_SHIFT` | 可以量寫實運轉、建材、汽機車分流的開與關 |
| 潮汐 | `TideReportTests`（GameCore） | `TIDE_REPORT=14`、`TIDE_TIDAL=1` | 可以量開與關 |
| 轉乘 | `TransferReportTests` | `TRANSFER_REPORT=14` | 可以量開與關 |
| **平溪線（H）** | **沒有報告測試**，只有 `PingxiChallengeTests` 的斷言 | — | **缺。** 要重量平溪線的目標得先寫一個，才能比較開關 |
| **支線（J）** | `BranchLineChallengeTests` 的斷言，沒有報告 | — | **缺** |
| **實景示範（G）** | `RealWorldDemoTests` 的斷言，沒有報告 | — | **缺** |

結論：**要重量挑戰目標，第一步是補平溪線、支線的報告測試**（另派，要改測試，不屬本單）。

跑了什麼：**一個報告測試也沒有跑**。要在 Linux 跑這些得先 `swift build --build-tests -c release`（整個套件的 release 建置），本單的時間不夠，也不會改變結論：這些報告量的是「目前關著」的數字，量不了「打開」。全部 UNVERIFIED（第 8 節）。

## 6. 五方打分與建議

尺：NEXT_PRIORITIES §19：每方 1–5，權重玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15。鐵道迷：5＝照真實鐵路的做法或真實資料，出處寫得出來；3＝和鐵路有關但是遊戲自己的模型；1＝和鐵路無關。分數相同時玩家高的在前，再看開發，再看鐵道迷。

候選分兩種：**開**（建議哪張地圖開）和**維持關**（寫理由）。

| 順 | 候選（地圖範圍） | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權分 | 要重量目標？ | 判 |
| --: | --- | --: | --: | --: | --: | --: | --: | --- | --- |
| 1 | **道路與公車：平溪線、實景示範開局也開路**（`NewGame.swift:105-109` 的條件；與 AE 合作） | 5 | 3 | 3 | 3 | 1 | 3.30 | 否（路不載客、不收錢） | **10/31 後先開** |
| 2 | **觀光：實景示範、高鐵示範、台鐵示範** | 3 | 3 | 3 | 4 | 1 | 2.85 | 否（這三張沒有目標） | **10/31 後先開** |
| 3 | **真實轉乘：實景示範、高鐵示範、台鐵示範** | 3 | 3 | 1 | 5 | 1 | 2.70 | 否（沒有目標） | **10/31 後先開**（要把轉乘點數接進示範） |
| 4 | 彈性派車：所有示範與挑戰 | 3 | 4 | 1 | 3 | 1 | 2.65 | 要確認（決策 258 說數字相同） | 次批；先量 |
| 5 | 靠左：實景示範、平溪線、支線、劉銘傳 | 2 | 4 | 1 | 5 | 1 | 2.65 | 要確認（單線區間不變） | 次批；先量 |
| 6 | 真實車長：實景示範、高鐵／台鐵示範（不含挑戰） | 2 | 2 | 3 | 5 | 1 | 2.45 | 示範沒有；挑戰要 | 後批；先對月台長度 |
| 7 | 彎道限速：高鐵／台鐵／實景示範（真實班次豁免） | 2 | 3 | 1 | 5 | 1 | 2.40 | 示範沒有；挑戰要 | 後批；實機看幀時 |
| 8 | 城市委託：實景示範、高鐵／台鐵示範 | 3 | 3 | 2 | 2 | 1 | 2.40 | 否 | 後批 |
| 9 | 潮汐：示範地圖（F）以外的示範 | 2 | 3 | 1 | 5 | 1 | 2.40 | F 要重量「約 8 天回本」；G 幾乎無作用 | 後批；價值小 |
| 10 | 寫實運轉＋區間閉塞：高鐵／台鐵示範 | 3 | 2 | 1 | 4 | 1 | 2.30 | 示範本來是真實時間 | 後批 |
| 11 | 車門擁擠：示範 | 2 | 2 | 2 | 4 | 1 | 2.15 | 示範沒有；挑戰要 | 維持關（平溪線天燈節會變難） |
| 12 | 車輛經濟：示範與挑戰 | 3 | 1 | 1 | 4 | 1 | 2.05 | **是**（淨利目標） | 維持關；要開先補報告測試 |
| 13 | 行車控制：高鐵／台鐵示範 | 3 | 1 | 1 | 4 | 1 | 2.05 | 示範沒有 | 維持關，先重量 `TrafficControlTimingReportTests` |
| 14 | 土地決定運量：實景示範、平溪線 | 2 | 2 | 1 | 3 | 1 | 1.85 | **是**（無人口資料時運量為 0） | 維持關（決策 78 的理由還成立） |
| 15 | 建材：挑戰 | 1 | 3 | 1 | 3 | 1 | 1.80 | **是** | 維持關（決策 157） |
| 16 | 距離需求＋外地連絡站：實景示範、平溪線 | 2 | 1 | 1 | 4 | 1 | 1.75 | **是**（決策 137 自己說要重量） | 維持關 |
| 17 | 假日與天氣：挑戰 | 1 | 2 | 1 | 3 | 1 | 1.55 | **是** | 維持關（已鎖，決策 154） |

**五方各一行**（候選 1）：
- 玩家：作者自己碰到的 bug，平溪線與實景示範都不能開公車；打開路是玩家最看得到的差別。
- 開發：蓋世界的條件改一處；路不載客、不收錢，不動目標；和 AE 要協調 `RoadsTurnOn.swift` 的條件，不要兩邊各改一次。
- 美術：3D 街景會有路（`GameSession.readRoads` 讀的是 OpenStreetMap 的底圖）。
- 鐵道迷：實景示範的路是真實街道；公車接駁站前。
- 音樂：無。

**順序**（10/31 後，一張一個 PR）：
1. 候選 1（與 AE 的結論一起看，AE 沒合併前不開工）。
2. 候選 2、3 一起或各一個 PR：只動實景示範、高鐵、台鐵三張的蓋世界程式；這三張沒有目標。
3. 候選 4、5：先在 `BalanceReportTests` 之類的既有報告量開與關各一次，數字相同再開。
4. 候選 6–10：每項先做上面第 4 節「待確認」的那件事（月台長度、幀時、`TrafficControlTimingReportTests`）。
5. 候選 11–17 維持關。

**要重量挑戰目標的**：候選 11–17 打開任何一項，都要先補平溪線與支線的報告測試（第 5 節），再用 `economy-balance` skill 量。本單不建議為了「完整」打開它們：挑戰的目標是沒有這些時量的，作者也沒有要求挑戰變難。

## 7. 沒有做的、不確定的

- **沒有把任何開關打開量**。第 4 節的方向都是讀決策與程式推的。UNVERIFIED。
- **沒有逐站對月台長度與真實車長**（候選 6）。
- **沒有查 TRADemo 的建造路徑是否每一處都走 `HighSpeedDemo.run`**（行車控制關著這一格寫的是「同 L」）。
- **沒有查 `isDemoMode`（演示模式）下 `startNewGame` 之外的開局**是否有別的差異；表一把 D 與演示模式合併。
- 表一不含 `Policy.swift` 的規則預設（`Policy.swift:587-598`，Headless 工具用，每一個都是把某幾個開關關掉）；它們是對 A 的組合，不是獨立開局。
- 表一不含 `DemoRealLines`（一鍵鋪真實路線，`DemoRealLines.swift:298`）：鋪線時暫時關行車控制，鋪完還原，是動作不是開局。
- 道路那一欄的結論等 AE（決策 440）；若 AE 的結論改變 4.1 的理解，以 AE 為準。

## 8. 驗證

- **VERIFIED**（Linux 雲端 session）：`python3 -I tools/golden-checks/doc_numbers.py --check` 通過（差異 0 項）。
- **VERIFIED**（讀程式）：表一、表二每一格的出處行號是對 main 4d5c799 讀出來的。
- **UNVERIFIED**：沒有跑任何報告測試、沒有 `swift build`、沒有把任何開關打開量；第 4 節的影響是推的。
- 這份文件與 `NEXT_PRIORITIES` §22.18 之外，不改 `Sources/`、`Tests/`、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`、`RailwayGameApp/`。
