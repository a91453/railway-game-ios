# 交接：PR #1343–#1385 審查 K2 組

派工單 AX（遊戲規劃 session_01YGNNupfaTiuQSAJ5tsf5a4，2026-10-28）：審查 main 上已合併的程式 PR #1343–#1385。#1288–#1340 是審查 K1（派工單 AW，session_01YGNNupNdEVV42ZCiM39rtb），兩邊不重疊。

- Session：session_01YGNNuo3VmaAw2ggDnzk58S，branch `claude/review-k2`。
- 基準：`main` **cdb5bba**（#1385 合併後）。
- 點數照 HANDOFF 第 1 節「多久審查一次」：GameCore 2 點；GamePresentation、App、CI 腳本、會產生打包資料的 `tools/`、`Web/` 的程式 1 點；只改文件、只加模型或素材、只改測試 0 點。
- 上一輪：[PR1242_1287](PR1242_1287_REVIEW_HANDOFF.md)（審查 J）。
- 存檔版本、決策編號、golden schema 都**不動**。HANDOFF §1 的「上一輪」由規劃在 K1、K2 都合併後統一改。
- **發版凍結**（TestFlight 92）：這一輪只寫文件，不開修 App 的 PR。P2、P3 由規劃在發版後派人修。

## 〇、分段

一共 26 點，不到 30 點，所以只有一段。

| 段 | PR（照編號） | 個數 | 點數 |
| --- | --- | --: | --: |
| **1** | #1344、#1345、#1346、#1350、#1351、#1355、#1358、#1361、#1362、**#1365**（GameCore）、#1366、#1369、#1371、#1372、#1373、#1376、#1377、#1378、#1379、#1380、#1381、#1383、#1384、**#1385**（GameCore） | 24 | 26 |

0 點的不看，共 17 個：
- 只改文件：#1347、#1348、#1349、#1352、#1353、#1356、#1360、#1364、#1367、#1368、#1370、#1374、#1375、#1382。
- 只改 UI 測試：#1343。
- 工具不產生 App 打包的資料：#1354（`tools/tra-delay-analysis`，只做分析）、#1357（`tools/train-models`，匯出、預算、雜湊鎖與七向圖，App 不打包它的輸出）。

#1359、#1363 沒有合併。

兩個 GameCore PR 由本 session 自己讀。其他 22 個分成四組，交給四個子代理讀；子代理回報的每一條，本 session 都在 cdb5bba 上對過行號。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 程式 PR | 24 個，26 點（GameCore #1365、#1385 各 2 點） |
| 新發現 | **9 個**：P1 候選 1 個（實機未驗）、P2 2 個、P3 6 個 |
| 已修 | 0 個（發版凍結） |
| 沒修，交出去 | 9 個（K2-1 到 K2-9） |

下面兩件已先用 send_message 告訴規劃：
- K2-1：92 的新功能（夜燈）在 App 裡完全看不到。
- K2-2：#1385 在車站多的地圖上，尖峰記憶體可能多出 1 GB；它也會進 92。

## 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1344 | 決策 434 列車展示（`Map3DShowcase`）：<br>• `Selection` 的切換、節數、範圍夾限<br>• `layout`、`cars(of:count:pack:)`（遠景、`ownLengths`、沒有尾車時把頭車轉過來）<br>• 鏡頭的 orbit、zoom<br>• 模型包在 `Task.detached` 先做好<br>• 轉台的 CADisplayLink 在 dismantle 時 invalidate | 無問題 |
| #1345 | `WhatsNew.entries` 加 `2026-10-27`（id 不重複、新的在前） | 無問題 |
| #1346 | `Slot.fourth` 與 `modelIndex(of:)`；`localTrain(number:)` 的負數取模；`Map3DRealTrains.formation(of:)` 讓 EMU900 固定 10 節 | 無問題 |
| #1350 | 展示隱藏按鈕時改成蓋一層全螢幕的點擊層（VoiceOver 也按得到） | 無問題 |
| #1351 | full lane：`FULL_LANE_SECOND_JOB` 與 `FULL_LANE_LESSONS_JOB` 不重疊；build job 把兩份都排除（`ios-build.yml` 約 552 行），另外兩個 job 只跑自己的那份，三個類別都存在 | 無問題 |
| #1355 | 決策 437 傍晚垃圾車：<br>• `presence` 在 18:00–21:00 兩端是 0<br>• `round`、`place` 的 guard<br>• 每幀掃 lane，和原本街景同一量級<br>• `sound` 量化後才通知 `GameAudio` | 無問題 |
| #1358 | 決策 436 月台小物與車頭方向幕：<br>• `Map3DPlatformProps` 的間距與數量<br>• `callingFormations` 濾掉 0 節<br>• `segments` 把數字夾在 0–9<br>• `Map3DHeadSign.add` 每幀查表，量很小 | 無問題 |
| #1361 | 決策 440：土地一次給齊的台灣地圖也開道路<br>• `newGame` 的分支<br>• `RoadsOffer.baseMapHasRoads`<br>• `roadBlocks`、`blocksRoundStations`<br>• `landBlocks` 是 nil 時的 `readRoads` | **K2-7（P3）** |
| #1362 | 台北 610 加進 `Map3DModelPack.standard`：B 車取負 x、y 是繞 z 轉 180°，不是鏡像，面的方向不變 | **K2-8（P3）** |
| #1365 | **GameCore**，市區公車與玩家道路，存檔 75。見下面「GameCore」一節 | 無問題 |
| #1366 | 決策 441 機廠車庫、扇形車庫：<br>• `besidePlatforms` 和原本 `addHouse` 的邏輯相同，`min(...)!` 不會空<br>• `addRoundhouseTurntable` 先 `contains`，再 `isClearOfTrack` | 無問題 |
| #1369 | xcstrings 的 key 和 `MapLayerSheet` 的 `Text` 一起改 | 無問題 |
| #1371 | 決策 442，實景新局 22 縣市：新的 11 個地點座標都和實際位置相差 1 km 內；名稱與 id 不重複；`standard` 仍是臺北 | 無問題 |
| #1372 | `DemoMode.Reveal.tap(at:gap:)`；`-ui-testing` 只在 `#if DEBUG` 裡讀 | 無問題 |
| #1373 | 決策 439 列車遮蔽烘焙：<br>• `baked` 用 Key 去重，shade 陣列長度一定對得上<br>• `concurrentPerform` 各寫各格<br>• summed table 的 index 夾在範圍內 | **K2-4（P3）** |
| #1376 | 改速度不丟 tick（`GameSession`）：<br>• 兩個 `finish` 都會套用保留的速度<br>• `tick.revision` 擋住舊結果蓋過新世界<br>• `togglePause`、`pauseForBuilding`、Undo、`stopGameLoop`、`worldToSave` 都處理到 | **K2-9（P3）** |
| #1377 | 決策 445 行人號誌：<br>• `window(.main)` 0..<32 = 主路綠燈，`(.cross)` 36..<64 = 支路綠燈，偏移是同一個 `offset(group)`<br>• 行人綠燈時，與他衝突的車流一定是紅燈 | **K2-6（P3）** |
| #1378 | 決策 446 機車：<br>• 並排那台用 `spacing >= 10` 和 `behind` 擋住，不會碰到後車<br>• `rowSlots` 遇到 NaN 回空陣列<br>• 三角形與記憶體增加的量，決策已量過並寫明 | 無問題 |
| #1379 | 決策 447 斑馬線、機車停等區、待轉區、紅黃線（`addKerbs` 每段 64 m、`addMark`） | **K2-3（P2）** |
| #1380 | 決策 447 續，標線型人行道（`walkwaySide`、`addWalkway`）、騎樓 3.64 m | 與 K2-3 同一個根源；另有 **K2-5（P3）** |
| #1381 | 決策 450 材質：<br>• Swift 的 −13、−14、−15 和 `.metal` 的範圍一致（`Map3DShaders.metal` 約 94–97、271、304–316 行）<br>• −12 是 floodlit，不在材質範圍內<br>• 非列車模型沒有材質層的頂點 | 無問題 |
| #1383 | 決策 449 夜燈：<br>• 頭燈 `atFront: !turned`、尾燈 `atFront: turned`，反向時也對<br>• 推拉式最後一節翻面時以中點對齊，連結點不動<br>• 合併時講好的 −15 → −13 已經在 main 上 | **K2-1（P2）** |
| #1384 | 決策 451 淡色調柔：`functional` 併入 `kept`、`restyle` 比對 alpha、shader 的 contrast | 無問題 |
| #1385 | **GameCore**，乘客路線搜尋加速。見下面「GameCore」一節 | **K2-2（P2）** |

### GameCore

**#1365**（市區公車與玩家道路，存檔 75）。合併前已經獨立審查過一次，這次在合併後的 main 上再看：

- `RoadGrid.built` 和 `cells` 分開存。所有讀道路的地方都改用 `contains`／`allCells`：GameCore 的成長、站前路、公車找路；GamePresentation 的 `BusRouteEditor`、`Map3DBuses`、`Map3DStreets`；App 的 `Map3DSceneKey`。在 cdb5bba 上 grep，已經沒有程式只讀 `.cells`。
- `roadQuote`：
  - 1 到 256 格，相鄰（含斜角）。
  - 已經有路的格子不收錢；同一格只算一次。
  - 第一格算一邊的長度。
- `removeRoads`：
  - 只能拆玩家鋪的路。
  - 每條路線的每一段（含到車站那段）在拆之前和拆之後各算一次長度，不一樣就拒絕。
  - 失敗時世界不變。
  - `buildRoad` 與 `removeRoads` 還沒有接到 `PlayerCommand` 或 UI，玩家碰不到。
- `BusRoute`：
  - `station` 改成可選。
  - `isValid` 檢查市區線至少 2 站、段數是站數減 1、`transfer` 的站序在範圍內。
  - Codable 舊檔照讀（沒有 `station` 就是市區線，只有 75 版會寫出）。
  - `reviseBusRoute` 會先清掉 `transfer`（`9bb9dfd`）。
- `refreshBusTransfers`：
  - 在 `refreshBusFeeders` 開頭、`drawsDemandFromLand` 判斷之前，所以每次 `refreshLandDemand` 都會重算。
  - `removeStation` 結尾會呼叫 `refreshLandDemand`，所以不會留下指到已拆車站的 `transfer`，`busRoutesProblem` 不會因此讀不回存檔。
- `refreshCityBusTrips`：
  - 最大餘數分配，同分時看站序，結果固定。
  - 整數相乘的上限（人數 × 次數、平方距離）不會溢位。
- `settleBuses`：餘載上限 `dailyCapacity` 對接駁線也生效，是決策 438 寫明的改變。
- 計畫的 key：`busFeeders` 改用 `feeds`，所以 `transfer` 變了計畫會重算。
- 目前玩家還開不了市區線（`editBusRoute`、地圖、3D 都跳過沒有 `station` 的路線），所以就算有問題也還碰不到。

**#1385**（乘客路線搜尋加速，宣稱逐位元相同）：

- **逐位元相同：成立。**
  - 舊的 `shortest` 是每個終點各跑一次 Dijkstra，pop 到第一個在終點、在車上的標籤就回傳。
  - 新的 `PassengerRouteSearch` 在 pop 時記下每一站第一個到達的標籤，接著從同一個狀態往下跑。
  - 展開、支配、heap 的全序都不看終點，所以每個終點拿到的標籤和單獨搜尋一樣。
  - 禁用邊的搜尋，從不禁用的那次「第一次要展開被禁用的那個停靠點之前」的複本分岔。在那之前沒有展開過被禁用的邊，`arrived` 記下的也都不受影響。
  - `labels` 只會往後加，`reconstruct` 用的索引不會變。
  - `testAResumedSearchFindsWhatASearchForOneDestinationFinds` 用隨機路網比對兩種結果。
- **記憶體：K2-2。**

## 三、交出去的（沒修）

P1 候選 1 個（K2-2）、P2 2 個（K2-1、K2-3）、P3 6 個（K2-4 到 K2-9）。

### K2-1（#1383）App 裡的模型包丟掉夜燈，天黑後列車全黑：P2

- **位置**（cdb5bba）：
  - `Sources/GamePresentation/Map3DCityBus.swift:91–98`：`replacing` 用 `Map3DModelPack(models:)` 重建模型包，只帶 `locked`。
  - `Sources/GamePresentation/Map3DModels.swift:148–151`：`init(models:)` 沒設 `lights`。
  - `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:724–726`：App 的模型包是 `Map3DGarbageTruck.pack(Map3DCityBus.pack(file:…))`，兩層都走 `replacing`（`Map3DGarbageTruck.swift:250`）。
  - `Sources/GamePresentation/Map3DTrainLights.swift:285`：`guard lights > 0, !pack.lights.isEmpty else { return }`。
- **什麼情況**：App 一定附公車與垃圾車的模型檔，所以模型包一定被換過，`lights` 一定是空的。`add` 一進去就 return。而 `split` 已經把模型原本畫亮的燈改成 `unlit`。
- **玩家看到**：天黑後地圖上所有列車（玩家的車、真實時刻表的車）都沒有頭燈、尾燈，客室窗也不亮，比 #1383 之前還暗。決策 449 在 App 裡完全看不到。
- **查證**：子代理在 Linux、cdb5bba 寫臨時測試：`Map3DModelPack.standard.replacing(<公車模型>)` 後，`lights` 從 220 變 0（`headSigns` 24 → 24，不受影響）。Linux 的測試都用 `.standard`，所以抓不到。
- **修法**：`replacing` 裡加 `pack.lights = lights`。換掉的只是公車、貨車，不是列車，模型索引不變。回歸測試：`standard.replacing(公車)` 後 `lights` 不是空的。
- **已通知、已派**：2026-10-28 告訴規劃。規劃在 main 上核對成立，決定 92 發版前修：派工單 BA（session_01YGNNumD9tgN3Jrf65GEox9，branch `claude/train-lights-replacing`），加 Linux 回歸測試。What to Test 的夜燈項目保留。

### K2-2（#1385）分岔搜尋每個暫停點都留一份整個搜尋的複本，尖峰記憶體隨車站數暴增：P1 候選（實機未驗）

- **位置**：`Sources/GameCore/Passenger/PassengerRoutes.swift`
  - `PassengerRouteSearches.runUnbanned`：`paused[number] = (paused.count, unbanned!)`。
  - `searches[forbidden]`：同一個起點的每一組禁用邊都留一份。
- **什麼情況**：
  - 不禁用的搜尋每第一次要展開一個停靠點，就存一份自己的複本（`labels`、`frontier`、`active`、`open`、`arrived`、`expanded`），之後繼續跑。寫入時觸發 copy-on-write，所以每份都是當下整個狀態的完整複製。
  - 一個起點跑完整張圖，就留下「停靠點數」那麼多份。每組禁用邊的搜尋也各留一份。
  - 換起點才會放掉。
- **量到的**（Linux release，臨時測試，合成路網：80 站、16 條線雙向、每線 12–21 站、有步行轉乘；每對起終點問一次不禁用、每條邊禁用一次、再加最多 6 組兩邊禁用）：

  | | 尖峰 RSS | 時間 |
  | --- | --: | --: |
  | 舊（每次 `graph.shortest`），80 站 | 139 MB | 59.4 s |
  | 新（`PassengerRouteSearches`），80 站 | 467 MB | 34.6 s |
  | 新，120 站（24 條線） | **1,147 MB** | 143.9 s |

  - 舊的不留複本，尖峰約等於開始時的 136–139 MB。
  - 合成路網和作者那局（高雄 78 站、63 列車）不一樣，數字只當量級看。
- **玩家看到**：每天 06:00 算乘客計畫時，記憶體短暫多出幾百 MB 到 1 GB 以上。iPhone 上 3D 地圖本來就用掉不少，車站多的地圖可能被系統關掉，看起來像閃退。
- **還沒驗證**：實機沒有量，所以先列 P1 候選，不算確定的 P1。
- **發 92 前要做的**：
  1. 用作者那局（`PASSENGER_ROUTE_SAVE`）加印 `ru_maxrss`。
  2. 再量一張車站更多的地圖。
  3. 過大就退回 #1385，或照下面的修法先修。
- **已派**：規劃派工單 BB（session_01YGNNuqBhweBkD7Em8wPZwr）用作者那局量新舊尖峰記憶體。多出來就修成有上限、仍逐位元相同的版本；兩小時內修不出來，就退回 #1385 再發。92 等 BB 的結果。
- **修法方向**（保持逐位元相同）：
  - 只在 `paused` 留下會被禁用的停靠點的複本，也就是第一條路線經過的那些，不是每一個停靠點。
  - 或在起點的禁用邊用完後丟掉 `searches`。
  - 或給 `paused` 設上限，超過就退回從頭搜。
  - 改好後用 `PASSENGER_ROUTE_SAVE` 那局量尖峰 RSS，寫進 HANDOFF §5 AQ 那一列。

### K2-3（#1379、#1380）紅黃線與綠色人行帶在橋頭引道上浮起或沒入：P2

- **位置**：`Sources/GamePresentation/Map3DRoadMarkings.swift:580–582`。`addMark` 只在標線中心取一次 `roadRise(at: mark.centre…)`，整塊用同一個 `lift`。長標線由 `addKerbs`（約 338 行，每段最長 `kerbPiece` 64 m，約 368 行）和 `addWalkway`（約 281 行）產生。
- **什麼情況**：
  - 地面道路從橋頭接出來會跟著斜坡升降（`Map3DRoadBridge.roadRise`，斜坡最長 360 m）。路面用 `addStrip(raised: true)` 每 4 m 取一次高度。
  - 64 m 的標線只取中心的高度，所以一端浮在路面上、一端埋進路面下。
  - 中心點如果落在越軌橋的橋面上（`onBridge`），整段 64 m 直接不畫。
  - 以前只有斑馬線、停止線這類短標線，看不太出來。這兩個 PR 是第一批長標線。
- **玩家看到**：橋頭引道兩側的紅線、黃線、綠色人行帶一節一節浮在半空中，或沉進路面。
- **查證**：子代理在 Linux 寫臨時測試：照 `Map3DRoadBridgeTests` 的平地世界，一條 secondary 地面路接上 level 1 的橋。標線和路面的高度差有 +1.62 m、+1.32 m、−1.86 m。
- **修法**：長標線照 `addStrip` 的做法，在 `raisedCuts` 或每 `raisedStep` 切開，每個角點各取一次 `roadRise`。

### K2-4（#1373）第一次開 3D 時，烘焙也在主執行緒上做：P3

- **位置**：
  - `Sources/GamePresentation/Map3DModels.swift:139`：`Map3DTrainOcclusion.baked` 在 `Map3DModelPack.init(styles:)` 裡。
  - `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:724`：`Map3DView.models` 是 `static let`，第一次在主執行緒的 `makeUIView` 讀到。
- **玩家看到**：第一次從 2D 進 3D 時，畫面停住的時間變長。決策 439 量的是 4 核 Linux release 多約 0.34 s（整個模型包 1.43 s）；iPhone 沒有量。只有一次。
- **修法**：照 `TrainShowcaseScreen.swift:78` 的做法，在 `Task.detached` 先把 `Map3DView.models` 做好再建 view。

### K2-5（#1380）標線型人行道在某個走向附近左右亂跳：P3

- **位置**：`Map3DRoadMarkings.swift:275` 的 `walkwaySide`：`way.x * 0.94 - way.z * 0.34 >= 0`。`addWalkway` 每一段各自判斷。
- **什麼情況**：分界在偏南北約 20° 的走向。巷子的走向接近這個方位，或在這附近轉彎時，相鄰兩段會選到不同側。
- **玩家看到**：彎巷中途，綠色帶從一側跳到另一側。
- **查證**：讀程式，沒有跑。
- **修法**：每條路只決定一次側邊（例如用首尾兩點的方向），不要每段各自決定。

### K2-6（#1377）小綠人的步伐每秒亂跳一次：P3

- **位置**：`Sources/GamePresentation/Map3DPedestrianSignals.swift:96`：`steps = floor(time / step(left:of:))`。`time` 是開機以來的秒數（`Map3DMetalView.swift` 約 861 行的 `CACurrentMediaTime()`），可以到 10⁵ 量級。
- **什麼情況**：倒數每過一秒 `step` 就變小一點。`time / step` 一下差了上千格，取 7 的餘數後是任意一格。
- **玩家看到**：綠燈時小人每秒抽一下，步伐不連續。
- **查證**：手算，沒有跑。
- **修法**：以綠燈開始的時刻為原點累積相位，或固定一個參考時間。

### K2-7（#1361）開實景示範與平溪線挑戰時，在主執行緒讀道路：P3

- **位置**：`GameLauncher.swift` 的 `openRealWorldDemo`（約 716–725 行）在主執行緒建好世界後呼叫 `begin`，`begin` 呼叫 `readLandRoundStations(roads: nil)`（約 1421 行），接著是 `WholeTaiwan.swift` 約 102 行的 `readRoads`。
- **什麼情況**：決策 440 讓土地一次給齊的地圖也開道路。高鐵和宜蘭線示範用 `readingRoads` 在背景讀，這兩局沒有。
- **量到的**：子代理在 Linux debug 用真資料量：12 站、134 個街區、6,206 格道路，0.48 s；之後每蓋一站約 0.22 s。
- **玩家看到**：開這兩局時多停一下。量比高鐵那次（2,500 個街區）小很多。
- **修法**：這兩局也走 `GameLauncher.readingRoads`。

### K2-8（#1362）沒用到的台北 610 模型加進標準模型包：P3

- **位置**：`Map3DModels.swift:121–126`。
- **什麼情況**：4 種車 × 近景、遠景、light 三種，共 24,916 個三角形，佔模型包 1,400,248 個的 1.8%，debug 生成約 0.08 s。沒有任何列車引用它們。
- **玩家看到**：看不出來，只是記憶體與開模型包的時間略增。
- **修法**：等列車真的用到時再加，或先放在只給工具用的包。

### K2-9（#1376）等 tick 時選的速度，按「略過到早上」或鋪示範路線後被丟掉：P3

- **位置**：`Sources/GamePresentation/NightSkip.swift:219–227` 的 `skipToMorning` 用 `world.clock.runningSpeed` 記下略過前的速度，沒看 `heldSpeed`。`DemoRealLines.swift` 約 281 行的 `layDemoRealLines` 也一樣（`let speed = world.clock.speed`）。
- **什麼情況**：tick 很慢時（大地圖 6000×，一個 tick 2–5 s），玩家先換速度（被保留），在那個 tick 算完前又按「略過到早上」或鋪示範路線。
- **玩家看到**：略過或鋪完之後，速度回到換之前的那個。
- **查證**：追程式路徑，沒有跑。
- **修法**：這兩處先呼叫 `applyHeldSpeed()`，再讀時鐘。

## 四、給 AU 的線索（LessonUITests 第 1 課）

沒有找到能解釋這兩支測試失敗的機制：

- **#1361 可以排除**：課程的世界由 `Lessons.swift` 約 897 行的 `newGame(eventSeed:rules:)` 建出，`anchor`、`land` 都是 nil，走 `NewGame.swift` 約 108 行沒有改的那個分支。`RealWorldFrame` 是 nil，所以 `readRoads` 直接 return。課程裡 `roadsOffer` 和 `turnOnRoads` 本來就關閉。
- **#1376**：
  - 選建造工具時，`pauseForBuilding` 先套用保留的速度，再保持暫停，`isPausedForBuilding` 不會被清掉，所以不會讓 `map.build.confirm` 消失。
  - 唯一的弱線索：`SpeedControl` 讀 `shownClock`，`FollowBar` 和狀態列讀 `world.clock`。tick 正在算時換速度，後兩者會晚一個 tick 才更新。
- 其他 PR 都沒有碰鋪軌確認或課程流程。

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests`（cdb5bba 加上臨時測試，Linux，官方 Swift 6.4.0 `/opt/swift`） | **VERIFIED**，Build complete |
| `swift build --build-tests -c release -Xswiftc -enable-testing` 與 K2-2 的臨時量測 | **VERIFIED**：<br>• 80 站：舊 139 MB／59.4 s，新 467 MB／34.6 s<br>• 120 站：新 1,147 MB／143.9 s |
| K2-1 的臨時測試（`replacing` 前後的 `lights`、各編組的轉向、材質層的分布） | **VERIFIED**：`lights` 220 → 0；只有推拉式編組翻面；非列車模型的材質頂點 0 |
| K2-3 的臨時測試（橋頭引道的標線高度） | **VERIFIED**：+1.62 m、+1.32 m、−1.86 m |
| K2-7、K2-8 的臨時測試（實景示範讀道路、610 的三角形） | **VERIFIED**：0.48 s、134 街區、6,206 格；24,916 / 1,400,248 |
| 臨時測試 | 都已刪除，這個 branch 只加這份文件 |
| `python3 -I tools/golden-checks/doc_numbers.py --check` | **VERIFIED**，通過 |
| K2-4、K2-5、K2-6、K2-9 | 只讀程式、追了呼叫路徑，**UNVERIFIED** |
| 完整測試、iOS 建置、UI 測試、實機畫面與記憶體 | 交給 CI 與實機，**UNVERIFIED LOCALLY** |

這一段沒有改程式（發版凍結），所以沒有回歸測試。

## 六、五方

- **玩家**：K2-1 讓 92 的夜燈看不到；K2-2 在車站多的地圖上可能被系統關掉，要實機量。這兩件都已先告訴規劃。其他都是看得到但不影響玩的畫面問題，或一次性的停頓。沒有會壞存檔或卡住的。
- **鐵道迷**：夜裡列車的頭燈、尾燈方向正確，推拉式也對（K2-1 修好之後才看得到）；22 縣市的地點座標與真實位置相差 1 km 內。
- **開發**：兩個 GameCore PR 的邏輯正確，#1385 確實逐位元相同，要改的只有記憶體；K2-1 是一行，加一個非 `.standard` 模型包的回歸測試。
- **美術**：K2-3、K2-5、K2-6 都是 3D 街景的標線與號誌畫錯，修的時候照決策 445、447 的預覽圖對。
- **音樂**：無。
