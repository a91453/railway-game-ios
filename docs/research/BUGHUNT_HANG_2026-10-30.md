# 公測前抓蟲：卡住（派工單 BH9，2026-10-30）

遊戲規劃第 32 任派，分支 `claude/bughunt-hang`，main `797687d` 起。範圍是「卡住」的四種：

- 畫面凍結、點了沒反應；
- 遊戲時間不走、列車全停（死結）；
- 某個操作要等很久；
- 玩家卡在某一步走不下去（按鈕灰掉沒說為什麼、sheet 關不掉）。

當機歸 BH8。教學與入門關的步驟歸 BH2，挑戰歸 BH5：在那裡看到的已轉過去（第 5 節）。

## 1. 怎麼查的

- **GameCore**
  - 讀遍 116 個 `while`／`repeat`、遞迴與尋路，看有沒有沒上限的迴圈：沒有（第 6 節）。
  - 讀懂死結偵測與解法：`Deadlock.swift`、`GameWorld.resolveDeadlock`／`changeBerth`、`RouteReservation.swift`。
- **量時間**（Linux，`swift build -c release -Xswiftc -enable-testing`）
  - 新的只在要求時跑的報告：
    - `DeadlockSearchCostTests/testWhatTheSearchCostsOnLongSingleTracks`（`DEADLOCK_COST_REPORT=<站>x<車>,…`）。世界是一條沒有待避線的長單線，每站一個月台，一條線，行車控制開，最快速度（6000×）跑一天。
    - `HangReportTests`（`HANG_REPORT=<天>`）。量高鐵、宜蘭線兩個示範，與決策 421 的台北 20 條真實路線：最快速度每 tick 的平均、p99、最長，與存讀檔；另外量每個城市開局每條可收購路線的收購卡。
  - 卡住的程序用 `gdb -p <pid> -batch -ex bt` 取樣找熱點。
- **App 主執行緒**（只讀程式，Linux 跑不了 SwiftUI）
  - 遊戲迴圈、存讀檔、iCloud、每個指令之後做的事、地圖、面板；
  - 找 `DispatchQueue.main.sync`、`semaphore.wait`、`saveQueue.sync`。
- **玩家流程**
  - 全部 60 個 `.sheet`／`.fullScreenCover`／`.alert`／`.confirmationDialog`／`.popover` 能不能關；
  - 灰掉的按鈕有沒有說原因；
  - 錢不夠、沒地、沒車時有沒有路走。

## 2. P1（已修，同一個 PR）

### P1-1 大型永久死結時，死結搜尋每問一列車就重算整條線，遊戲時間幾乎停住，每點一下卡近一秒

**在哪：** `GameWorld.isSpare(_:)`（`Sources/GameCore/Railway/Deadlock.swift`）。

**怎麼壞：**
- 死結搜尋 `deadlock(memo:)` 要先找出各線的備用車，對每列不在等待中的車各問一次 `isSpare`。
- `spareStandingAside` 對每列車也各問一次。
- `isSpare` 每次都開一個新的 `DispatchMemo`，於是每列車都把線的容量配置（`capacityLayout`：每站每個月台往前後站各尋一次路）和行程（`journey`）整個重算。
- gdb 取樣 12 次，12 次都在這條路上。

**影響：**
- 死結搜尋每個遊戲分鐘在 tick 裡跑一次（6000× 一個 tick 跑十次）。
- App 每個指令之後，又在主執行緒上跑一次到兩次：`situationAlerts` 的死結泡泡，與 `TrafficReading`。
- 死結是玩家要自己解的（加待避線、加月台、減車）。正要動手時，每點一下都卡住，時間也幾乎不走。

**怎麼重現：** `DEADLOCK_COST_REPORT=40x6,40x16,120x16,120x40`。修前修後量的數字（Linux release，最快速度跑一天，每 tick 100 ms 預算）：

| 站 | 車 | 修前 平均 tick | 修前 最長 tick | 修前 死結搜尋一次 | 修後 平均 tick | 修後 最長 tick | 修後 死結搜尋一次 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 2 | 1.3 ms | 7.3 ms | 0.7 ms | — | — | — |
| 40 | 6 | 35.8 ms | 52.3 ms | 16.9 ms | 8.6 ms | 17.5 ms | 4.1 ms |
| 40 | 16 | 100.5 ms | 151.6 ms | 38.8 ms | 8.8 ms | 13.4 ms | 4.3 ms |
| 120 | 16 | 670.8 ms | 829.6 ms | 319.6 ms | 54.1 ms | 77.3 ms | 22.3 ms |
| 120 | 40 | 1,785 ms | 2,103 ms | 971.8 ms | 56.2 ms | 78.6 ms | 28.7 ms |

- 修前 120 站 40 車：遊戲以約 1/18 的速度走；每個指令後主執行緒還要再算約 1–2 秒。
- 修後最長 tick 在 100 ms 預算內。
- 十站兩車的死結一直都便宜，所以小地圖上看不到這個問題。

**修法：**
- `isSpare(_:memo:)` 讓同一次查看裡問的每列車共用一個 `DispatchMemo`。`isSpare(_:)` 留著，照舊每次開新的。
- memo 的生命週期：
  - `deadlock(memo:)` 與 `spareStandingAside(in:memo:)` 一開頭各建一個 `var dispatch = DispatchMemo()`，函式結束就丟。
  - 這兩個函式都是 `GameWorld` 的非 mutating 方法，世界在 memo 活著的期間不會變，所以 memo 活不過任何一次世界變動。
- memo 裡有哪些快取：
  - 以線為鍵：`journeys`、`capacityLayouts`、`capacities`、`outerCapacityJourneys`、`scheduledServices`。
  - 以車與它站的位置為鍵：`trips`、`depotTrips`。
  - 以查詢為鍵：`runDepotQuery`。
  - `isSpare` 走的是 `isDispatchDue(deadhead: true)` → `plannedService`，只用到以線為鍵的那幾個。
  - 沒有任何「依被問的那一列車而變、卻不以車為鍵」的快取，所以共用不改答案。
- 決定性、golden、存檔、replay 都不動。

**測試：**
- `DeadlockSearchCostTests/testASharedMemoAnswersAsAFreshOneForEveryTrain`（differential）
  - 隨機產生的局，三種世界交錯：單線多站（4–13 站、2–8 車、部分車是備用、全天或 06–24 營運）與 W–M–E 有待避線。
  - 每個遊戲分鐘，對每列車比「共用 memo 依序問」與「每列車新 memo（舊做法）」的答案，要逐列相同。
  - 斷言局裡真的有備用車與死結，不是空跑。
  - 死結搜尋與備用車讓路只由這些答案決定，所以兩者也相同。
- `DeadlockSearchCostTests/testTheSearchDoesNotWorkTheLineOutAgainForEverySpare`
  - 40 站 16 車在死結裡（15 列是備用）時，死結搜尋要少於同一台機器上算一次容量配置的 5 倍。
  - 舊做法在 Linux debug 是 24 倍：一次配置 17.5 ms，搜尋 425.9 ms，紅。
  - 修後綠。
  - 拿同一台機器上的一次配置當尺，慢的 runner 兩邊一起慢。

**五面向：**
- 玩家：最需要動手的時候（死結、要加待避線）畫面與時間不再卡住。
- 鐵道迷：無，調度規則不變。
- 開發：純快取，三處各幾行；differential 測試鎖住答案不變。
- 美術：無。
- 音樂：無。

## 3. P2

### P2-1 收購真實路線的卡片在主執行緒上排版，點一下最多約 0.8 秒

**在哪：** `GameSession.offerRealLine` → `realLineOffer(for:)`（`Sources/GamePresentation/RealLineAcquisition.swift`）。由 `LinesPanel` 與 `StationPanel` 的點擊呼叫。

**怎麼壞：** 最多排四次版（有／無機廠 × 高架／共用高架）。每次都在世界的副本上買地、讀地與路、讀地形。

**量到的**（`HangReportTests/testWhatARealLineOfferTakes`，Linux release；手機上通常更慢）：

| 開局 | 路線 | 時間 |
| --- | --- | ---: |
| 板橋 | 三鶯 `sanying:LB` | 815 ms |
| 淡水 | 三鶯 | 812 ms |
| 桃園 | 三鶯 | 623 ms |
| 台北 | 淡海 `ntdlrt:V` | 544 ms |
| 台北 | 平溪 | 414 ms |
| 台北 | 捷運新北投／小碧潭支線 | 270–320 ms |

開局離路線遠時（台中、高雄）都在 6 ms 以下。

**建議修法：** 在 `Task.detached` 裡排版，卡片先顯示「準備中」，排完再換上。

**五面向：**
- 玩家：點了路線之後半秒多沒反應，會以為沒點到。
- 鐵道迷：無。
- 開發：GamePresentation 與兩個面板，中等；結果要對得上當時的世界版本。
- 美術：「準備中」的樣子照 UI_THEME。
- 音樂：無。

### P2-2 回開始畫面時，存檔在主執行緒上做；還可能等 iCloud 那一輪

**在哪：** `GameLauncher.returnToStart()` → `autosaveCurrentGame` → `afterSaves { library.save(...) }`，即 `saveQueue.sync`。

**怎麼壞：**
- 存檔是整個世界的 JSON 編碼加寫檔，在主執行緒上。
- 前面若有排著的背景存檔或 iCloud 同步（`syncSaves`，在 App 回到前景時排的），主執行緒會等它們做完。
- 之後 `refresh()` 再用一次 `saveQueue.sync`，解碼每個存檔的檔頭。程式註解自己記的是一份約 70 ms、六份 0.4 s。
- 開始畫面每次出現（`StartView.onAppear`）、新遊戲（`archiveAutosave`）、改名、刪除，也都走 `saveQueue.sync`。
- iCloud 那一輪只讀已經下載好的檔（`ICloudSaveFolder.files()` 對沒下載的只叫它開始下載），所以不會等網路下載；但會讀寫整份存檔，大地圖上是幾 MB。

**量到的：** 存讀檔時間這輪沒量到。報告測試在示範世界上開關行車控制時拋 `trainsShareTrack`，那兩個測試整個沒跑完；修正後的報告留給下一輪。

**建議修法：**
- 回開始畫面改用背景的 `write(...)`，寫完再換畫面。
- `refresh()` 改成 `saveQueue.async` 讀完再回主執行緒。
- iCloud 那一輪不要放在主執行緒會 `sync` 的同一條佇列。

**五面向：**
- 玩家：大地圖按「回開始畫面」停一下，偶爾更久。
- 鐵道迷：無。
- 開發：GameLauncher，中等；要保留「存不了就不離開」的保護。
- 美術：無。
- 音樂：無。

### P2-3 每個指令之後，主執行緒算死結泡泡與交通狀態

**在哪：**
- `GameSession.world` 的 `didSet` → `refreshMapMarks()` → `situationAlerts`（`MapAlerts.swift`）。它的 memo 以 `commandRevision` 為鍵，所以每個指令都失效。
- `MapView` 的 `.onChange(of: TrafficKey…)` → `trafficOverlay` → `TrafficReading(world:)`。

**量到的：**
- 兩者都會跑死結搜尋。P1-1 修好後，120 站 40 車的永久死結約 30 ms 一次。
- 程式註解記的是收購三鶯線後 70–100 ms（Linux release）。

**觸發：** 建設時每點一下、暫停、換速度、復原、拖動列車速度滑桿。

**建議修法：** 照遊戲迴圈的做法，指令後在 detached task 裡算，算好之前先顯示舊的；或只在會改軌道或預約的指令後重算。

**五面向：**
- 玩家：大路網上建設時，每點一下略頓。
- 鐵道迷：無。
- 開發：GameSession，中等。
- 美術：無。
- 音樂：無。

### P2-4 跳過夜晚的預先試跑，在三個地方仍在主執行緒上做

**在哪：** `GameSession.nightSkip`（`Sources/GamePresentation/NightSkip.swift`）。memo 沒命中時，在主執行緒上跑 `NightSkip.firstMove(after:)`。

**量到的：** 程式註解記的是宜蘭線約 30 ms、跨午夜 160 ms、台北七條線 600 ms。

**還在主執行緒上跑的三個地方：**
- `stopNightSkip()`：`endNightSkip` 改了版本，memo 必定沒命中；
- `skipToMorning()` 在 memo 沒命中時；
- `GameSession.init`：每次讀檔或開新遊戲。

**建議修法：** 這三處改用已經有的 `refreshNightSkipOfferOffTheMainActor()`。

**五面向：**
- 玩家：按「停止跳過」或讀檔時頓一下。
- 鐵道迷：無。
- 開發：三行。
- 美術：無。
- 音樂：無。

### P2-5 欠錢時轉成自由模式，從此什麼都蓋不了，也轉不回來

**在哪：** `setEconomyMode`（`Sources/GameCore/Economy/Operations.swift:31-39`）只改模式，不改餘額。

**怎麼卡：**
- 自由模式沒有票價收入（`Operations.swift` 的收入都要 `.management`），也不能借錢（`.loanNeedsManagement`）。
- 建設與買車照樣扣錢（`GameEconomy.spend`）。
- 確認框（`EconomyPanel.swift:257-262`）只說「不能再變回經營公司」，沒說錢會停在現在的數字。
- 經營公司負債、貸款已借滿時，按這個看起來像出路的選項，從此錢是負的、永遠不會增加。
- 只剩賣車（帳面 70%）或「回到自動存檔」。

**建議修法：** 二選一，並在確認框寫清楚：
- 轉換時打開無限資金；或
- 確認框說「現金維持現在的數字，不再增加」。

這要改 GameCore 或確認框的文字，屬經營（BH3）的範圍，轉 BH3 判斷。

**五面向：**
- 玩家：選了一個看起來是出路的選項，結果永遠卡住。
- 鐵道迷：無。
- 開發：小。
- 美術：無。
- 音樂：無。

### P2-6 回開始畫面時自動存檔失敗，就出不去

**在哪：** `GameLauncher.returnToStart()` 第一行：`guard session == nil || autosaveCurrentGame(refreshing: false) else { return }`。

**怎麼卡：**
- 存檔失敗時（例如手機空間滿了），只在狀態列寫一句；之後每按一次都一樣失敗。
- 選單沒有「不存檔離開」，玩家只能強制關 App。
- 這個保護是刻意的（不把沒存的遊戲丟掉）。

**建議修法：** 失敗時跳確認框，提供「不存檔離開」，並說明會失去什麼。

**五面向：**
- 玩家：少見，但碰到就只能強關。
- 鐵道迷：無。
- 開發：小。
- 美術：無。
- 音樂：無。

### P2-7 有幾種等待不會自己解，也不算死結

`deadlock(memo:)` 的 `couldGo` 把下面這些車擋住的軌道當作會讓出來，所以等它們的車不會被報成卡住，也沒有泡泡：

- 玩家自己停下的車（速度 0）；
- 沒有派給任何線的車；
- 線的營運時段外（夜裡）停著的車；
- 沒路可走（`.noRoute`）而停在月台的車；
- 機廠月台滿了、要進機廠的車。

另外：
- 已經在部分授權上、互相對面跟著走的兩列車（`departs: false`），只有備用車讓路與短折返兩種解法。
- 一分鐘只解開一列車，大塞車要很多分鐘才散。

BH2 用無頭玩過單線頁真實按鈕 224 局、入門 10 關、猴子玩家 9 局，沒有找到玩家走得到的這類死結（`BUGHUNT_OPERATIONS_2026-10-30.md`），所以列 P2。

**建議修法：** 先讓 `routeWaitText` 與泡泡說出「在等哪一列停著的車」。要不要讓派車員把它們當備用車移開，是調度規則的改變，公測後由 BH2 那條線決定。

**五面向：**
- 玩家：車不動又沒有提示，不知道該移哪一列。
- 鐵道迷：真實調度會指出佔用者。
- 開發：先改提示文字，小；改規則大。
- 美術：無。
- 音樂：無。

## 4. P3

- **P3-1 手改存檔把節點座標放大千倍，讀檔要好幾分鐘**（BH8 的模糊測試找到）
  - 讀檔時 `RailwayNetwork.init(from:)` → `workOutFouling()` 照邊長算 fouling。
  - v3–v7 示範存檔、v70-mode-shift、v73-bus-route 改過後，`GameSim load` 就超過 2 分鐘。
  - 讀檔在背景，所以畫面停在載入中，不會凍結；這種存檔只有手改得出來。
  - 建議修法：解碼時拒絕超出世界範圍的座標。
- **P3-2 錢不夠時按鈕灰掉，沒說是因為錢不夠**
  - `LinesPanel.swift` 約 2092（補車）、2120（改班距）、2302（買 N 台並開始營運；成本會變紅，但沒有指向貸款）；
  - `TourismPanel.swift:137`；
  - `StationCommerceSection.swift:56`；
  - `StationPanel.swift:1047`（移動站牌，沒有原因）。
  - 參考做法：線的虧損與滿意度修正（`LinesPanel.swift` 約 2666、2848）有寫原因。
- **P3-3 兩個全螢幕畫面在資料變成 nil 時是空白、沒有關閉鍵**
  - `SettingsView.swift:98-101`（3D 預覽，`if let session`）；
  - `LinesPanel.swift:2522-2526`（運行圖，`if let id = session.selectedLineID`）。
  - 要在畫面開著時資料消失才會發生，幾乎碰不到。
- **P3-4 自動存檔的比較**
  - 每 15 分鐘的自動存檔先在主執行緒比整個世界（`world != lastSlotWorld`）。
  - 每月結算時 `MonthlyReport.make` 也在主執行緒上做。
  - 量級都小，沒量。
- **P3-5 每格畫面都處理每列真實列車**
  - `RealTrainCanvas` 每格畫面對每列真實列車先組字串鍵、查形狀，之後才裁掉看不到的（`RealTrainMotion.swift` 約 609–640），30 fps。
  - 建議先裁掉看不到的再處理。

每項的五面向：

- 玩家：P3-2 會困惑，其餘幾乎碰不到；
- 鐵道迷：無；
- 開發：都小；
- 美術：P3-2 要加一行說明；
- 音樂：無。

## 5. 轉給別的 BH

- **BH2**（已收，寫進 #1528 的 `BUGHUNT_OPERATIONS_2026-10-30.md` §3a）：
  - 入門關結果卡的「再一次／下一關」在遊戲裡失敗時沒有回饋；
  - 另一個 sheet 開著時，結果卡可能出不來（BH2 評疑似 P2，要 UI 測試）；
  - 教學中復原全關，沒說原因；最後一步不能跳過；
  - 滑掉結果卡後遊戲仍暫停。
- **BH5**（已收，記成 `BUGHUNT_FREIGHT_CHALLENGES_2026-10-30.md` 的 P3-9）：
  - 挑戰輸定時，遊戲裡沒有「重來這個挑戰」，要回開始畫面重選。
- **BH3**：P2-5（欠錢轉自由模式）的修法，請 BH3 判斷。

## 6. 查過、確定沒問題的

- **GameCore 迴圈**
  - 116 個 `while`／`repeat` 都有已走過的集合、保證前進或是二分搜尋：
    - `TrainRoute.shortest` 的 `done`、`walkedDirections`、`currentTrafficWait` 鏈的 `met`；
    - Goals 與 LineCapacity 的 union-find、TrackSections 的短段合併；
    - LandDemand 的空地迴圈、`TrainMovement.travel`、UnitFlow 的 max-flow；
    - Tourism 的嘗試上限 200、RoadGrid 的找路、MapExpansion 的 BFS。
  - `PassengerRouteSearches` 有標籤與搜尋預算。
  - `trackDistances` 雖是 O(n²)，但限 512 單位內，而且只在指令時跑。
  - 城市與道路成長一天或一個月一次。
- **死結搜尋本身**
  - `deadlock(memo:)` 的定點迴圈每輪至少拿掉一列車，否則就停，所以一定結束。
  - P1-1 之後，即使大型永久死結也在 tick 預算內。
- **遊戲迴圈**
  - 每個 tick 在 `Task.detached` 裡算；一次醒來最多 5 個 tick，tick 之間都有 `await`；最快速度是每個 tick 走更多遊戲時間，不是更多 tick。
  - 跳過夜晚只改速度。
  - tick 之後主執行緒上的步驟由 `FrameCostMeter` 量著（決策 330、369）。
- **背景做的**
  - 讀檔與匯入（決策 419）、背景與定時自動存檔、匯出、真實世界資料、道路預讀；
  - `LineMap`／`StationLabels`／`MiniMap`、CityMap、地形、天際線、3D 場景。
- **找不到的**：`DispatchQueue.main.sync`、`Thread.sleep`、`usleep`、`DispatchGroup.wait`、忙等。
  - `Map3DMetalView` 的 `lifeInFlight.wait()` 是三緩衝的號誌，每條路都會 signal，只在 GPU 塞住時等（3D 歸 BH6）。
- **sheet 與確認框**
  - 60 處沒有 `interactiveDismissDisabled`；
  - 由狀態算出的 binding 都有清掉狀態的 setter；
  - 月報、年報、目標報告關了就清；
  - 3D、車庫、列車一覽、運行圖、環境模式、真實資料載入畫面都有關閉或取消。
- **錢不夠、沒地**
  - 貸款到上限、還款、賣車、貸款預覽；餘額可以是負的，不會直接結束；
  - 建設的 ✓ 會寫出問題；地圖邊緣可以買地；
  - 挑戰負債 60 天才失敗；
  - 開線確認框有取消，也寫出差多少錢。
- **示範鋪真實路線**：`defer { demoRealLinesProgress = nil }` 一定放開按鈕。

## 7. 驗證

**VERIFIED（Linux）：**
- `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨。
- debug 測試類：`DeadlockSearchCostTests`、`DeadlockPropertyTests`、`IdleTrainDeadlockTests`、`DeadlockTests`、`GoldenScenarioTests`、`ReplayFixtureTests`、`SavedGameTests`。
- shard：`campaigns-4`、`campaigns-14`。
- 修前修後的數字：release 的 `DEADLOCK_COST_REPORT`。

**UNVERIFIED：**
- App 主執行緒各項（第 3、4 節），要 macOS 與實機看 `FrameCostMeter` 或錄影。
- 高鐵、宜蘭、台北 20 線示範的每 tick 時間與存讀檔：報告測試修正後沒有重跑（第 3 節 P2-2）。

**參考庫與外部專案：** 這輪是抓蟲。P1-1 的修法是這個專案自己的快取，沒有搬參考庫或外部程式。
