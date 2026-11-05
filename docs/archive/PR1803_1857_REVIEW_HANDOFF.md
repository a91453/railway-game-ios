# 交接：PR #1803–#1857 審查（審查 L10）

派工單 REVIEW-L10（遊戲規劃第 50 任 session_01YGNNumyd5kmn2HrCenU1qN，2026-11-05，114.1 發版後；HANDOFF §1.1 固定三件之一）：審查 L9（`PR1760_1802_REVIEW_HANDOFF.md`）之後已合併、改到程式的 PR。格式同 L9。

- Session：REVIEW-L10 session_01YGNNuoB7f2rfxdhAmyP2L8，branch `claude/review-l10`。
- 基準：`main` **85973647**（#1857 合併後；114.1 是 c1be6078，之後只多文件）。每個 PR 讀 merge commit 對 first parent 的 diff，和它的決策檔。
- 做法：
  - GameCore 由本 session 自己讀：#1810、#1816、#1821、#1822、#1823、#1827、#1837，以及 #1743 的 GameCore 部分。
  - GamePresentation／App 分給兩個子代理：
    - 一個審渡輪、跟隨、3D 街景與地標（含 studies 對遊戲路徑的影響）。
    - 一個審放車、預覽、效能 memo、L9 修正與更新說明。#1849 的 GameCore `PathMemo` 也在這邊。
  - 子代理的每一點都附重現或程式位置。P2 與本 session 的 P3 都用 Linux 臨時測試重現。臨時測試量完就刪，沒有提交。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

逐一核對 `git log --first-parent bef26ca..85973647`。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1810**（渡輪 PR-1，決策 585，存檔 85）、**#1816**（決策 586：纜車載觀光客）、**#1821**（決策 556 續：等下一班的車逆向開進空月台）、**#1822**（決策 587：公車載觀光客）、**#1823**（決策 587 續：通勤轉乘站不接機廠）、**#1827**（決策 589：渡輪載觀光客）、**#1837**（決策 590 下一步 2：GameWorld 狀態放到堆上、寫入時才複製）、**#1743**（決策 556：機場捷運，GameCore 部分）、**#1849**（決策 597：path memo 留住月台股道） |
| GamePresentation | 渡輪與跟隨：#1814、#1824、#1835、#1811、#1819。3D：#1841、#1854、#1832、#1833。放車與預覽：#1808、#1820、#1825、#1831、#1839、#1851。其他：#1843、#1809、#1807、#1812、#1818、#1829、#1852、#1743 的展示層。studies：#1817、#1830、#1834、#1844、#1845，只看遊戲路徑會不會碰到 |
| App | 上面各 PR 的畫面部分 |
| 測試 | 只改測試：#1815（HEALTH-112）、#1838（UI 測試），略看 |

沒有審的：

- 只改文件的有 #1803、#1804、#1805、#1806、#1826、#1828、#1836、#1842、#1847、#1848、#1850、#1853、#1855、#1856、#1857。
  - #1853 另有 `tools/` 下的研究腳本，遊戲沒有載入。
- #1813 只加 `tools/` 下的研究腳本與預覽，遊戲沒有載入。
- #1840 只動 CI 與 `tools/`，用來列出超過 32 KB 的堆疊框。
- #1846 拿掉 Wasm 探針與 `Web/`，遊戲沒有用到。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **1**：L10-1 |
| P3（記著） | **12**：L10-2 到 L10-13 |

- 沒有 P1，所以沒有 send_message 通報。
- GameCore 的 PR 沒有發現 P1 或 P2，只有 **L10-2**（P3）。
- 上一輪的修正都確認修好：
  - L9-1、L9-3（#1812）：子代理把修法反向套回去重跑新測試，兩支都紅；放回後綠（**VERIFIED**）。
  - L9-2、L9-9、L9-10、L9-11（#1818）：都修好。L9-2 另外留一處沒改，見 **L10-3**。
  - L9-6、L9-8（#1819）：都修好。L9-8 只改了窗的方向，窗的位置見 **L10-7**。
  - L9-4、L9-5、L9-7：還沒派，照舊。

### GameCore

- **#1837**（決策 590 下一步 2，GameWorld 改成堆上的 COW）：
  - 每個欄位都改成 `_read`（讀 `storage.state.pointee`）與 `_modify`（經 `uniqueState`，`isKnownUniquelyReferenced` 不成立時先整份複製）。
  - `network` 留在 struct 裡，`==` 比 `network` 與整份 state。
  - 不會因共用而少比：同一份 storage 也逐欄比，所以 NaN 的語意和合成的 `==` 一樣。
  - 快取欄位（`passengerPlan`、`passengerRouteMemo`、`routeMemo`、`trackEditDepth`）照舊跟著複製。
  - 沒找到別名寫入的路徑：`_modify` 期間再讀 `self` 的其他欄位會被靜態獨佔檢查擋住，而且整個專案編得過。
  - `@unchecked Sendable`：共用時只讀、寫前一定獨佔，和標準 COW 一樣。
  - 風險只有說明裡自己寫的那一點：`GameWorldState` 每個欄位都有預設值，新的 initializer 漏設欄位時，編譯器不會報錯。不列。
  - `GameWorldStorageTests` 過。
- **#1810**（渡輪 PR-1，存檔 85）：
  - `createFerryRoute` 依序檢查 ID、航段、`isValid`、碼頭、錢，最後才寫入，失敗時世界不變。
  - `FerryRoute` 解碼前先擋碼頭數上限；`ferryRoutesProblem` 檢查編號已發出、照順序、碼頭在地圖內、`transfer` 是存在的車站。
  - 拆掉車站時，相接航線的 `transfer` 與接駁人數歸零。
  - 帳目：`ferryFares` 為正、`ferryRunning` 為負，和 `ledgerEntryIsValid` 新加的一行一致；`DayAccount` 把它們歸進物業收支，和公車、纜車相同。
  - `Int64` 的乘法（`dailyCost`、`countFerryRiders`）在合法範圍內不會溢位。
  - 船數 0 時 `headway` 是 nil，班次與成本都是 0。
  - 例外是 **L10-2**：航線接到的車站可能是機廠。
  - `FerryTests`、`SavedGameTests`（v85 fixture）過。
- **#1816／#1822／#1827**（決策 586、587、589：纜車、公車、渡輪載觀光客）：
  - `feederAccess` 依纜車、渡輪、公車的順序找，和土地分配的順序（決策 585）一致。
  - 有 `day` 時，停駛的纜車、颱風日的渡輪不算；`attractionStation` 用 nil，表示哪天都算。
  - 接駁的觀光客不買一日券（`feeder == nil` 才加進 `visited`），和決策一致。
  - `countFeederRides` 在午夜的 `closeTourismDay` 呼叫，早於 `settleOperations` 的 `settleCableways`／`settleBuses`／`settleFerries`，所以當天結算有算進去。
  - 公車的 `meets.stop = stops.count` 是刻意放在索引外，讓所有站都能當景點站。
  - 纜車的 `meetsNear`：建時檢查 500 m 內有上下客的站，讀檔時選離那點最近的車站。
  - `BusTourismTests`、`FerryTourismTests`、`CablewayTests` 過。
- **#1823**（決策 587 續）：
  - 城市公車找轉乘站時跳過機廠；`setStationDepot` 在有公車路線時重算土地需求。
  - 同樣的規則沒有套到纜車與渡輪，見 **L10-2**。
  - `CityBusTripsTests` 過。
- **#1821、#1743 的 GameCore 部分**（決策 556 續，TYMCLIST7–9）：
  - `runTrainPutOnItsRun`、`runTrainEmptyToDepot` 放車上班次的那幾個欄位，和 `dispatchRuns`、機廠出入的寫法逐欄一致。
  - `standingAsideServiceTakingAFreeBerth`、`serviceStandingAsideAnyWay` 只在 `reserving` 回 `.granted` 時才 `setOff`。
  - `passingPlace(anyWay:)` 把長度設成 `Int64.max`，但下游用 `addingReportingOverflow` 加，不會溢位。
  - `otherDepotRun` 只在交控開、有班表、擋到等路的班次時才換機廠，其他照舊。
  - `heldRunStart` 由 `>` 改成 `>=`，只多在起點那一秒叫醒一次。
  - 一點小差別：`runTrainEmptyToDepot` 照 `line.depots` 的順序挑，不是挑最近的。死結裡的最後手段，不列。
  - `RunTrainCounterflowTests`、`RunTrainFollowerClaimTests`、`RunTrainDepotDeadlockTests`、`RunDepotFallbackTests`、`RunServiceStandAsideAnyWayTests`、`RunStoodAsideCounterflowTests` 過。
- **#1849**（決策 597，子代理）：
  - `platformTracks` 只讀網路的形狀。它的 `PathMemo` 借自 `RouteMemo`、也存回 `RouteMemo`，而 `RouteMemo` 的鍵包含整個 `RailwayNetwork`。
  - `advance` 結束時鍵和開始時相同才保留，不同就重設，所以改軌道或月台後拿不到舊值。
  - `GoldenScenarioTests` 24/24、`ReplayFixtureTests`（2 過 1 跳過）結果相同。

### GamePresentation

- **渡輪與跟隨**（#1814、#1824、#1835、#1811、#1819）：
  - 沒有會閃退的地方。編號、`lying` 的漸移、`pierAhead` 都不會越界；纜車跟隨的 `loop` 恆大於 0。
  - 中英文一致：「接駁」、營運時間 7–19 點（週末到 20 點）和 GameCore 相同。
  - 有 **L10-4**、**L10-5**、**L10-6**、**L10-7**、**L10-9**、**L10-10**、**L10-11**。
- **#1854**（addJoins 當機修正）：
  - 修得完整。`rim > 0` 才算挖方，再加上 NaN 防護與 `plateau > 0`，所以 `across` 恆為正。
  - 同檔與 `Map3DTrench.swift`、`Map3DTrackCover.swift` 的其他 `low...high` 都用 min／max 組成，或已保證為正；沒有找到還會反轉的範圍。
- **#1841**（決策 596）：`Window.walking` 的範圍不會反轉，`lap` 與 `wrapped` 不會除以 0，用到的路徑都有 2 點以上。沒發現問題。
- **#1832、#1833**（高雄地標）：常數幾何，唯一的 `last!` 用在常數陣列上。沒發現問題。
- **放車與預覽**（#1808、#1820、#1825、#1831、#1839、#1851）：
  - 按下去的動作（建軌升級、開線確認、教學的下一步、追蹤的出售）都用 `now: true` 當場算。
  - 等待中的預覽要嘛存快取，要嘛經 `previewsWorkedOutLater` 重畫，不會一直循環。
  - `PlaceToPassMemo` 以 `commandRevision` 與每條線的列車為鍵；背景算的結果要過 `worldRevision` 檢查才存。
  - 放車選月台的命令可重播：不認得的月台回 `unknownStation`，已不存在的邊先擋。
  - 有 **L10-8**。
- **#1843**（決策 595）：**L10-1**。
- **#1818**：**L10-3**。
- **#1829／#1852**：**L10-12**；114.1 的說明（#1852）裡沒有按鈕名稱。
- **#1807、#1809、#1825**：沒發現問題。
- **studies**（#1817、#1830、#1834、#1844、#1845）：
  - #1830、#1844 的新檔只有測試引用。
  - #1834 新加的 `model(livery:)` 遊戲不會呼叫。
  - #1845 沒動 Sources 或 App。
  - 例外是 #1817：玻璃管線在遊戲裡一定會建，見 **L10-13**。

### App

- 畫面都是 **UNVERIFIED**（沒有 macOS）。只讀程式，見 L10-4、L10-11、L10-13。

## 二、發現

### L10-1（P2）#1843：買來的線拿掉一站後，那一站留著常客人數

- **位置**：
  - `Sources/GamePresentation/RealTransfers.swift:160`，`refreshTransfers()` 的 `TransferMemo`。
  - `wantedTransfers()`（約 141 行）用 `world.line(id:)?.stops.contains(station.id)` 判斷「常客」。
- **問題**：
  - memo 的鍵只有車站位置、`hasRailways` 和 `world.acquisitions`，但結果還取決於買來那條線的停靠站。
  - 拿掉或加回一站時，鍵沒變，舊的 `transferPoints` 就留著。
- **玩家看到**：
  - 平溪線拿掉十分這一站後，十分每天仍有 **1,100** 趟（應是 **100**），已經沒有線停的站有十倍的人潮。
  - 存檔再讀、或移動任何車站後才變對，所以同一個世界的需求看 session 經過了什麼而不同。
  - 反過來，加回的站也拿不到常客。
- **驗證**（子代理，Linux，**VERIFIED**）：
  - 臨時測試：買 PINGXI、開 transfers，`refreshTransfers()`。
  - 再 `removeStopFromSelectedLine(at: 4)` 拿掉十分（車站保留），然後 `refreshTransfers()`：十分 1,100。
  - 同一個世界開新的 `GameSession`，十分是 100。
- **修法建議**：
  - 把買來的線的停靠站加進 `TransferMemo` 的鍵（`world.acquisitions.compactMap(\.line).map { world.line(id: $0)?.stops }`），或在改到買來的線的命令後丟掉 memo。
  - 回歸測試照上面的步驟，斷言和新 session 的數字相同。修前紅。

### L10-2（P3）#1810／#1816：纜車與渡輪的轉乘站可能接到機廠

- **位置**：
  - `Sources/GameCore/Passenger/Cableway.swift`，`refreshCablewayTransfers(among:)` 沒有 `meetsNear` 的分支，以及 `namedTransfer(of:near:among:)`。
  - `Sources/GameCore/Passenger/Ferry.swift:500`，`refreshFerryTransfers(among:)`。
  - 傳進來的是 `landStations`，它只排除關閉的車站，機廠也在裡面。
- **問題**：決策 587 續（#1823）只讓城市公車跳過機廠。纜車和渡輪照舊挑最近的車站，可能挑到沒有線停的機廠，接駁人數就落在那裡。
- **驗證**（本 session，Linux，**VERIFIED**）：
  - 臨時測試照 `CablewayTests.world()`。
  - 在纜車第一站的格子中心建車站 C（比 A 近），設成機廠，再建纜車。
  - 結果：`transfer = BusTransfer(station: 3, stop: 0)`（C），`feederTrips` 200，C 的需求 399。
- **影響**：
  - 只在玩家自己把纜車或碼頭蓋在機廠旁時發生。
  - 貓空纜車有 `meetsNear`，會挑離動物園站最近的站，木柵機廠比較遠，碰不到。
  - 觀光那條路（`takesTourists`）本來就排除沒有線停的站，不受影響。
- **修法**：兩個 `refresh…Transfers` 與 `namedTransfer` 照 #1823 加 `where !station.isDepot`。`setStationDepot` 重算的條件 `!busRoutes.isEmpty` 也加上纜車與渡輪。

### L10-3（P3）#1818：月台太短時「減到 N 節」沒有算進新的容差

- **位置**：`Sources/GamePresentation/LineDispatchText.swift:167`，`let fit = max(Int(shortest / train.carPitch), …)`。
- **問題**：L9-2 的修正讓 4 節 EMU3000（81.2 m）停 80 m 月台不再提示。但 5 節時，提示說「減到 3 節」，其實 4 節就可以，少說了一節。
- **驗證**（子代理，Linux，**VERIFIED**）：5 節 EMU3000、80 m 月台，得到 `ShortPlatformCall(cars: 3)`。
- **修法**：`Int((shortest + carPitch / overhangSlackDivisor) / carPitch)`，和判斷要不要提示的容差一致。

### L10-4（P3）#1824／#1835：渡輪 3D 每天至少重排一次，每次掃整個場景

- **位置**：
  - `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:987-994`，`laidFerries` 用 `ferries?.routes != world.ferryRoutes` 判斷要不要重排。
  - `Sources/GamePresentation/Map3DScene.swift`，`drawnWater(round:radius:)`。
- **問題**：
  - `FerryRoute` 整個拿來比。`ridersToday`、`days`、`feederTrips` 在經營模式下每天結算都會變（`Ferry.swift:600` 的 `days.append`）。
  - 每次重排，每個碼頭都要 `drawnWater` 掃過 `scene.chunks` 的所有三角形，而且在主執行緒每幀的 feed 裡。
- **驗證**（子代理）：
  - 觸發條件是讀程式確認的。
  - 臨時測試（24 個 chunk 的小場景，debug）：`drawnWater` 一次約 17 ms，`Map3DFerries.init` 約 49 ms。
  - 實際台北場景大得多，每天可能卡一下。**可能**，沒有在實機量。
- **修法**：比對的鍵只取 `id`、`piers`、`legMetres`、`boats`、`service`；或依碼頭快取岸線。

### L10-5（P3）#1824：碼頭的岸線只看一開始建好的場景

- **位置**：`laidFerries` 傳進 `built.scene`，之後串流進來的 chunk 不在裡面。
- **問題**：航線在一開始的範圍外時，`shore` 回 nil，碼頭改放在 64 m 的格邊上，可能在畫出來的岸線內陸，船開過陸地。
- **驗證**：讀程式，**可能**。修法：找不到岸線時記下來，附近 chunk 建好後再重排。

### L10-6（P3）#1835：照班表（`.runs`）開的渡輪，可能同時開出比船還多的班

- **位置**：`Sources/GamePresentation/Map3DFerries.swift:266-310`，`departures` 與 `numberedSailings`。
- **問題**：
  - `.runs` 照時刻表的分鐘開，間隔不受 `headway` 限制，可能有同號的船同時在開。
  - `prefix(boats)` 會丟掉多出來的班，跟隨可能抓錯船。
- **影響**：目前畫面只做得出 `.every`，玩家碰不到。讀程式。

### L10-7（P3）#1819：公車的「車窗」視角，眼睛在車身外面

- **位置**：`Sources/GamePresentation/Map3DFollow.swift:514-521`；公車的 pose 沒有給 `window`（`Map3DBuses.swift:674`）。
- **問題**：
  - 公車用列車的預設值：橫移 `windowEyeAcross` 1.59 m、高 2 m。
  - 低地板公車半寬只有 1.23 m（`bodyWidth` 2.46），眼睛在車外約 0.36 m，像飄在公車旁邊。
  - L9-8 只把方向改成右窗，方向是對的；這是 FOLLOWBUS 留下來的。
- **驗證**：讀程式。修法：公車的 pose 給 `window`，例如橫移約 0.8 m、高約 1.9 m。

### L10-8（P3）#1808／#1820：放車選的月台換了列車還留著；選月台每次重畫都重算

- **位置**：`GameSession` 的 `pickedPlacementPlatform`；`placementPlatformChoices`、`placementPlatform`。
- **問題**：
  - 換選另一列車時，`pickedPlacementPlatform` 沒有清掉。在同一站幫 A 車選的月台會帶到 B 車。讀程式，**可能**。
  - 兩個函式每次重畫都跑一次整個路網的 union-find（沒有路徑壓縮）並掃所有列車。
  - 子代理量過（**VERIFIED**，debug）：台北實景示範（2,868 條邊、139 列車）最慢一次 2.8 ms，每次重畫 2–3 次。現在可以接受，路網再大時以 `commandRevision` 快取。

### L10-9（P3）#1824／#1835：每幀重算颱風

- **位置**：`laid()` 經 `open` 閉包呼叫 `world.ferryRouteIsOpen`。
- **問題**：
  - `ferryRouteIsOpen` 每次都呼叫 `typhoons(ofYear:)`，每次都用字串鍵做 `SeedDraw` 抽樣，`lying` 還會看 2 到 3 天。
  - 每幀從 frame、ahead、ferryPose 與串流的 ahead 呼叫好幾次。
- **驗證**：測試世界沒有天氣，600 幀約 0.21 s（debug），有颱風時的成本沒量到。修法：init 時依日期把「今天開不開」存起來。

### L10-10（P3）#1835：跟隨列的「下一班」沒說是明天

- **位置**：`FollowFerry.swift` 的 `case nil` 分支。
- **問題**：19 點後、下一班在隔天時，只寫「下一班 07:00 開」，沒有說是明天。中英文一致。

### L10-11（P3）#1814：航線卡的顏色靠列的順序判斷

- **位置**：`ControlPanel.swift`，`index == 2 && !card.sails`。
- **問題**：船數 0 時（GameCore 與舊存檔允許 0，畫面的 Stepper 從 1 起），「今天開航」那一列被染成警告色。之後加一列，位置就錯。修法：卡片的列帶一個種類，不靠索引。

### L10-12（P3）#1829：113.1 更新說明的兩個名稱和 App 不同

- **位置**：`Sources/GamePresentation/WhatsNew.swift`（113.1 的條目）。
- **問題**：
  - 說明寫「The Bus button is now Transit, with Bus and Ferry inside」（中文「分公車、渡輪」）。實際的模式有三個：Buses／Roads／Ferries（公車／道路／渡輪，`RoadDraft.swift:29-31`）。英文的單複數不同，兩種語言都漏了「道路」。
  - 說明寫「Garage is now the Collection」，但拍照的標題仍是「Train Garage」／「車庫」（`RailwayGameApp/Views/Map3D/TrainShowcaseScreen.swift:221`）。
  - 其他名稱都對得上（子代理逐一核對兩種語言）。113.1 已發，之後的說明照按鈕寫；拍照標題要不要改成「圖鑑」，由修的人照五方決定。

### L10-13（P3）#1817：玻璃管線建不起來時，整個 3D 地圖打不開

- **位置**：`RailwayGameApp/Views/Map3D/Map3DMetalView.swift` 約 371 行，`guard let glassDrawing = Map3DGlassPipeline.make(...) else { return nil }`。
- **問題**：
  - 這條管線只有 studies 用，遊戲的模型都沒有 -16／-17 這兩層，但它失敗時整個 3D view 回 nil。
  - 招牌等其他管線失敗時都只是略過。
  - 換模型包時還會掃整包建 `Cache`。
- **驗證**：讀程式，macOS 上 **UNVERIFIED**。修法：改成 `if let`，失敗時不畫玻璃。

## 三、驗證紀錄

- `swift build --build-tests`（Linux，Swift 6.4，debug）：成功。
- `swift test --skip-build`（Linux，**VERIFIED**）：
  - 本 session 跑了 13 個類別，共 110 個測試，全過：`BusTourismTests`、`CablewayTests`、`CityBusTripsTests`、`FerryTests`、`FerryTourismTests`、`GameWorldStorageTests`、`RunDepotFallbackTests`、`RunServiceStandAsideAnyWayTests`、`RunStoodAsideCounterflowTests`、`RunTrainCounterflowTests`、`RunTrainDepotDeadlockTests`、`RunTrainFollowerClaimTests`、`SavedGameTests`。
  - 子代理（渡輪、跟隨、3D），共 17 個類別，全過（`Map3DSeeThroughTests` 跳過 1 個）：`FerryToolTests`、`FerryCollectionTests`、`Map3DFerriesTests`、`FerryFollowTests`、`CabinFollowTests`、`FollowBusVisibleTests`、`Map3DFollowViewsTests`、`Map3DSeeThroughTests`、`Map3DStreetStopTests`、`Map3DRoadBridgeTests`、`Map3DTaipeiLandmarksTests`、`Map3DCoachLiveryTests`、`Map3DTransparentGlassTests`、`Map3DAirportAircraftStudiesTests`、`Map3DBusTerminalStudiesTests`、`LocalizationTests`、`ScreenshotSceneTests`。
  - 子代理（放車、預覽、memo）：
    - 16 個類別共 138 個測試，跳過 1 個，其他全過：`AutoServiceTests`、`CommandEditTests`、`DetailsCardLayoutTests`、`DeviceDiagnosticsTests`、`OldStationCrossoverTests`、`PlacementGuidanceTests`、`PlacementPlatformTests`、`PlatformStopTests`、`RealLineAcquisitionTests`、`ScrollEdgeFadeTests`、`SingleTrackLengthTests`、`StationLandmarkNamingTests`、`TrainControlTests`、`TrainSessionPropertyTests`、`WaitingPreviewTests`、`XiaogangHangReportTests`（跳過）。
    - 另跑 `GoldenScenarioTests` 24/24、`ReplayFixtureTests`（2 過 1 跳過）。
- 臨時測試：L10-2 由本 session 重現；L10-1、L10-3、L10-4、L10-8 的時間由子代理量。都已刪除。
- L9-1、L9-3 的回歸測試修前紅、修後綠，由子代理在另一個工作目錄反向套用修法確認，該目錄已刪除。
- 畫面、Metal、iOS 行為：**UNVERIFIED**（沒有 macOS，沒跑 iOS workflow）。

## 四、下一輪

- REVIEW-L11 從 **#1858** 起（`main` 85973647 之後）。
- L10-1 的修正 PR 合併後，下一輪要審它的修法與回歸測試。
- 還沒派的：L9-4、L9-5、L9-7，與 L10-2 到 L10-13。
