# 交接：PR #1386–#1435 審查 L

派工單 CB（遊戲規劃 session_01YGNNumoD1XSP8eSkjabCvp，2026-10-28）：在 10/31 公開 TestFlight 之前，審查 main 上已合併的程式 PR #1386–#1435。上一輪是審查 K2（#1343–#1385，[PR1343_1385](PR1343_1385_REVIEW_HANDOFF.md)）。

- Session：session_01YGNNuqMJtFmVmQuYaYUDW1，branch `claude/review-l`。
- 基準：`main` **cc0256c**（#1435 合併後）。
- 點數照 HANDOFF 第 1 節「多久審查一次」：GameCore 2 點；GamePresentation、App、CI、會產生打包資料的 `tools/`、`Web/` 的程式 1 點；只改文件、只加模型或素材、只改測試 0 點。
- 存檔版本、決策編號、golden schema 都**不動**。
- 派工單允許修 P1、P2。這一輪沒有找到 P1 或 P2，所以只交這份文件，沒有改程式。

## 〇、分段

一共 32 點，只有一段。

| 段 | PR（照編號） | 個數 | 點數 |
| --- | --- | --: | --: |
| **1** | #1387、#1388、#1389、#1393、**#1394**（GameCore）、#1396、#1400、#1403、#1406、#1408、#1409、#1410、**#1414**（GameCore）、#1415、#1416、#1417、#1418、**#1419**（GameCore）、#1420、#1421、#1422、#1423、#1424、#1427、#1428、#1429、#1430、#1432、#1433 | 29 | 32 |

- #1419 照規則算 2 點，但它在 `Sources/GameCore/` 只改了註解裡的參考路徑。
- 0 點的不看，共 20 個：
  - 只改文件：#1386、#1390、#1391、#1392、#1395、#1397、#1398、#1399、#1401、#1402、#1404、#1405、#1411、#1412、#1425、#1426、#1431、#1435。
  - 只改測試：#1413。
  - 工具，App 不打包它的輸出：#1407（`tools/train-models`）。
- #1434 沒有合併（BP-2，還在做）。

三個 GameCore PR 由本 session 自己讀。其他 26 個分四組，交給四個子代理讀：
- A：速度與 GameSession。
- B：公車、鋪路、地圖比例。
- C：3D 效能與 shader。
- D：3D 素材、小修與 CI。

子代理回報的每一條，本 session 都在 cc0256c 上對過行號。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 程式 PR | 29 個，32 點（GameCore #1394、#1414、#1419） |
| 新發現 | **9 個**：P1 0、P2 0、P3 9（其中 L-1 是 P2 候選，要實機量；L-8、L-9 是疑點） |
| 已修 | 0 個 |
| 沒修，交出去 | 9 個（L-1 到 L-9） |

- 這段 PR 沒有會閃退、壞存檔或卡死的錯。
- 兩個 GameCore 效能修正（#1394、#1414）的結果都和修正前逐位元相同。
- 最值得在公開前看的是 L-1：4 GB 的 iPhone 在場景建好前關掉 3D 再打開，會同時建兩個場景。這是 App 層，Linux 上寫不出會紅的測試，所以只列出來，沒有修。

## 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1387、#1428 | `WhatsNew` 新項目的 id（`2026-10-28`、`2026-10-28-93`）不重複；要不要顯示只看 `entries.first?.id` | 無問題 |
| #1388 | 只改 DEBUG 啟動參數的順序與 UI 測試；`pause()` 已經暫停時不會再點 | 無問題 |
| #1389 | `swift-shards.sh`：18 個 campaign shard 的類別不重複、都存在，移出的類別由 `rest` 跑 | 無問題 |
| #1393 | `Map3DModelPack(models:)` 只在 `replacing` 用到。三條換模型的路（公車、垃圾車、#1417 的 `Map3DSceneryProp`）都帶回 `lights` 與 `locked`；`headSigns` 不變 | 無問題 |
| **#1394** | **GameCore**，見下面「GameCore」一節 | 無問題 |
| #1396、#1418 | full lane 的分配：`StartSaveFlowSmokeTests` 的 12 個方法（second 3 個、lessons 4 個、build job 5 個）不重疊、不漏，方法名稱都存在；`-skip-testing` 收「類別/方法」 | 無問題 |
| #1400 | `heldSpeed`：<br>• `finish` 的 defer、`stopGameLoop`、`togglePause`、`setRunningSpeed`、`worldToSave` 都會先套用<br>• `skipToMorning`（`NightSkip.swift:224`）與 `layDemoRealLines`（`DemoRealLines.swift:281`）先套用才記速度<br>• 背景讀道路（`GameLauncher.swift:745–755`）用 `session === playing` 判斷，不會蓋掉別的局；讀取時有載入畫面蓋住按鈕 | 無問題 |
| #1403 | 靜態展示列車移出模型包：<br>• 執行時都用名字查模型，索引不會錯位<br>• 主執行緒在 `modelsReady` 之前不會讀到 `standard`<br>• 包先好或場景先好，順序都對 | 無問題 |
| #1406 | 長標線切段：<br>• `raisedCuts` 與 `lift()` 都擋住長度 0 的段，不會除以零<br>• `Pace` 的分母有 `max(1, …)`，時間跳 1e9 或倒退都不會出 NaN（子代理寫臨時測試驗過）<br>• `walkwaySide` 遇到退化的線段改用第一段的方向 | 無問題 |
| #1408 | 遠景方塊實例：<br>• `Map3DBoxInstance` 88 bytes、stride 88、對齊 4，和 `.metal` 一致，有測試釘住<br>• `append` 帶上 `boxes`，會轉向的那個只收不收方塊的 mesh<br>• chunk 邊界與透視都算進方塊 | 無問題 |
| #1409、#1420 | 台北地標：<br>• `colour(_:)` 用到的鍵都在 palette 裡<br>• `precondition` 與除法吃的都是常數，測試建過每個地標的近景與遠景 | **L-7（P3）** |
| #1410 | Metal 實例：<br>• `boxCorners` 和 Swift 的 `faceCorners` 逐項相同<br>• 0 個實例時 buffer 是 nil，不發 draw call<br>• 用 `setVertexBuffer`，沒有 4 KB 的限制<br>• 太陽陰影 pass 有畫；shader 載入不到時整個退回決策 232 的陰影 | 無問題 |
| **#1414** | **GameCore**，見下面「GameCore」一節 | 無問題 |
| #1415 | 站長建議的快取：<br>• key 是（遊戲小時，`commandRevision`）；指令、Undo、Redo、設定都會加 revision<br>• 讀檔、換局都是新的 `GameSession`<br>• 背景算好的那份只在 revision 對得上時採用（`SecretaryRoom.swift:336`） | **L-9（疑點）** |
| #1416 | 新的 `train-model-tools.yml` 只在 Linux 跑工具測試；本機重跑 node 5 個、python 6 個都通過 | 無問題 |
| #1417 | Kenney 布景：<br>• 讀檔失敗用 `try?`、`compactMap`，`canFit` 擋掉尺寸 0<br>• 6 個 `.m3dmodel` 都在 xcodeproj 的 Resources<br>• 新模型插在中段，但沒有地方寫死索引<br>• 子代理在阿里山鋪 40 段玩家軌道，最近的針葉樹離中心線 9.2 m | 無問題 |
| **#1419** | **GameCore**：只改了註解裡的路徑；`tools/` 也只改了說明字串 | 無問題 |
| #1421 | 機型兩軸：<br>• 模擬器、iPad on Mac 讀不到可用記憶體時算 ample<br>• 未來的晶片 family ≥ 9 算 higher<br>• `TickPace` 在 higher、溫度正常時 share = 1，和以前一樣<br>• `DrawScale` 不會小於 1 | **L-1（P3，P2 候選）**、**L-8（疑點）** |
| #1422、#1430 | 三鶯、台中綠線只進 `studies`，App 不用 | 無問題 |
| #1423 | 六家線月台架高：<br>• `isRaised` 要求橋從站往前後各延伸 160 m，所以竹中的內灣線月台不架高<br>• 遇到 `trackConflict` 才重鋪一次，失敗時回第一次的理由<br>• 收購指令記錄的是鋪好的節點，舊存檔與 replay 不受影響<br>• 遇到 `trackConflict` 的那一下點擊會鋪兩次（`pricingCopy` 再 build），主執行緒上約慢一倍，沒有量 | 無問題 |
| #1424 | 台北捷運配車：<br>• C371、C381、C341、610、generic 與玩家的 A、B、D、L，1 到 10 節都找得到模型，500 m 外都有遠景<br>• 列車編號 −5 到 45 都取得到車頭<br>• 查不到的路線預設 6 節 C371<br>• 模型包上限測試通過 | 無問題 |
| #1427 | 速度提示：<br>• 只在沒暫停時計時；暫停、背景、按「改成 ×N」都清掉<br>• 換倍速重設計時，略過到早上不會誤跳<br>• 70% 開始計、80% 才清，中間有緩衝 | **L-2（P3）** |
| #1429 | `mapPoint` 是 `worldPosition(latitude:longitude:)` 的反算。grep 過：`MKMapPointsPerMeterAtLatitude` 只剩 UI 測試在用；舊存檔的世界座標沒動 | 無問題 |
| #1432 | 市區公車與鋪路：<br>• 鋪路、拆路、開市區線都走 `perform`<br>• 預覽、泡泡、按鈕的價格都取 `world.roadQuote`<br>• 站被拆後的草稿只會得到 GameCore 的錯誤訊息<br>• 市區線至少 2 站；3D 公車在 `station` 為 nil 時不越界 | **L-3～L-6（P3）** |
| #1433 | 不跳提示的開關在 `RailwayGameApp.swift:121–204` 的 `#if DEBUG` 裡，只在 `-ui-testing` 時生效；Release 的 `showsSpeedLagHint` 維持 true | 無問題 |

### GameCore

**#1394**（乘客路線搜尋的複本設上限，修 K2-2）：

- 不禁用的搜尋只每 `spacing` 個停靠點留一份複本。超過 `checkpointLimit` 時 `spacing` 加倍，只留 `order % spacing == 0` 的複本。
  - order 0 永遠留著，所以 `paused(at:)` 的 `checkpoints.last { $0.order <= order }!` 一定找得到。
- `paused(at:)` 從最近的複本用 `run(until: -1, pausing: true)` 往下跑到 `order`。
  - 每次 run 都停在下一個第一次展開，和 `runUnbanned` 每次前進的方式相同。
  - 原本的搜尋中途停在某個終點的到達，不改變 pop 的順序。所以重跑得到的狀態，和 #1385 存下的那份相同。
- `start` 的最後一支（`runUnbanned` 停在第一個被禁用的停靠點）直接複製 `unbanned`。這和 #1385 的 `paused[number]` 是同一個狀態。
- 禁用搜尋最多留 `searchLimit` 個，標籤總數最多 `labelBudget`，先丟最久沒問的。丟掉的下次問到時從頭建，結果相同。
- 測試 `PassengerRouteSearchTests` 用很小的上限（1、3、8，`labelBudget` 60）比對隨機路網，所以丟掉後重建的路也測到了。

**#1414**（06:00 不再重算全部乘客路線）：

- `PassengerRouteMemo.use` 多留前一張圖和它的選擇。只有新的圖等於前一張圖時才拿回來。
- 選擇本來就是圖的純函數（#1414 之前，同一張圖就已經沿用），所以結果逐位元相同。
- memo 不存檔，兩個世界比較時永遠相等，存檔與重播不受影響。
- 記憶體最多多一張圖與一份選擇。

## 三、交出去的（沒修）

P1 0、P2 0、P3 9（L-1 到 L-9；L-1 是 P2 候選；L-8、L-9 是疑點）。

### L-1（#1421）記憶體少的機型關掉 3D 時清快取，還在建的場景沒停，重開會再建一個：P3（P2 候選，實機未驗）

- **位置**（cc0256c）：
  - `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:259`：`onDisappear` 在 `!memoryTier.keepsSceneBuilt` 時呼叫 `Map3DSceneCache.shared.clear()`。
  - 同檔 `:391–396`：`clear()` 只把 `key`、`building` 設成 nil。
  - 同檔 `:439` 起：`Task.detached` 建場景，不能取消，會一直跑完。
- **什麼情況**：4 GB 的 iPhone（tight）開 3D，在轉圈的那幾秒內關掉再打開。因為 key 已經清掉，`task(for:)` 會另起一個建造，前一個還在跑，兩個城市場景同時在建。
  - 決策 455 量過一個場景約 370–520 MB，所以尖峰約加倍，正好發生在 #1421 要保護的機型上。
  - #1421 之前，關掉 3D 不清快取，重開會沿用同一個建造中的 task。系統發記憶體警告時本來也會呼叫 `clear()`，那條路徑從以前就是這樣。
- **玩家看到**：載入變慢；最壞情況是在台北一帶被系統關掉，看起來像閃退。
- **查證**：讀程式，追過呼叫路徑。App 層在 Linux 編不了，寫不出會紅的測試，所以沒有修。
- **修法**（任選一個）：
  - `clear()` 遇到還沒建完的 task 先保留，標記「建完就放掉」；重開時如果 key 相同就沿用，並取消這個標記。
  - 或 `onDisappear` 只放掉已經建好的場景。
  - 改完用 tight 機型在台北開關 3D 兩次，看記憶體尖峰。

### L-2（#1427）速度提示的 popover 被系統收掉時，這一局就再也不跳：P3

- **位置**：`RailwayGameApp/Views/HUDView.swift:894–900`。popover 的 binding 只要被寫成 false，就呼叫 `dismissSpeedLagHint()`，這一局之後都不再提示。
- **什麼情況**：提示要跳的時候，畫面上已經開著別的 sheet 或 popover，SwiftUI 顯示不了，把 binding 寫回 false。
  - 倍速旁的點剛消失、提示還沒清掉的那 100 ms 內（例如剛換倍速），也可能發生。
- **玩家看到**：一直跟不上設定倍速，卻沒有提示。
- **查證**：讀程式；要在 Simulator 上開著 sheet 時觸發提示才能確定。
- **修法**：提示卡真的出現過（`onAppear` 記一筆）之後，才把 set(false) 當成「知道了」。

### L-3（#1432）斜著拖出的路，在真實地圖上畫成一串三角形：P3

- **位置**：
  - `Sources/GamePresentation/RoadDraft.swift:308–312`（`roadMapOverlay` 的 `streets`）。
  - `Sources/GamePresentation/Map3DStreets.swift:439–446`（`addOwnRoads`）。
  - 兩處都把相鄰的格子兩兩連起來，斜角相鄰的也連。
- **什麼情況**：手指斜著拖時，`RoadDraft.extend` 會因為每次只差一格而走出階梯形（右一格、下一格……）。階梯的每個轉角都多一條斜邊。
- **玩家看到**：2D 與 3D 的路面都是一串三角形，不是一條路。3D 裡三角形的頂點會被當成路口（這一點沒在 Metal 上看過）。
- **查證**：子代理寫臨時測試模擬斜拖。草稿 9 格，連出 15 段，其中 7 段是多出來的斜邊（應該 8 段）。
- **修法**：兩格斜角相鄰，而且已經有一個共同的直向鄰格也是自己的路時，不畫那條斜邊。

### L-4（#1432）從地圖外開始拖，訊息講錯原因：P3

- **位置**：`RoadDraft.swift:154–162` 的 `dragRoad`。只檢查終點在 `world.bounds` 裡，沒檢查起點。
- **什麼情況**：從地圖邊緣外一格以上開始拖，草稿的第一格就在世界外（例如 column −3）。
- **玩家看到**：整次都被 GameCore 以 `invalidRoads` 拒絕，訊息說「這一帶的道路讀不到」，玩家看不懂。
- **查證**：子代理的臨時測試印出 `CellPosition(row: 2, column: -3)` 和這句訊息。
- **修法**：起點在界外時，從第一個在界內的點開始畫。

### L-5（#1432）鋪路預覽和拆路選取，在世界改變後不會更新：P3

- **位置**：`RoadDraft.swift:146–288`。`roadPreview` 只在拖曳或收回一格時算，`roadRemoval` 只在點擊時算。
- **玩家看到**：
  - 顯示「錢不夠」之後收入進帳，鋪路按鈕還是灰的，要重拖。
  - 反過來，錢變少時預覽仍說能鋪；按下去 GameCore 會拒絕並給訊息，不會出錯。
  - 城市的路長進草稿的格子後，顯示的價格偏高；實際扣款以 GameCore 為準。
  - 「有公車走這段，不能拆」在公車路線改掉之後不會消失，要再點一次。
- **查證**：讀程式。
- **修法**：世界前進時，以及 perform、Undo 之後，也呼叫 `refreshRoadPreview()`，並重算 `roadRemoval`。

### L-6（#1432）3D 的「自己的路」偶爾沒有重建：P3

- **位置**：`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:583`：`Map3DSceneKey.roads = world.roads?.allCells.count`。但 `addOwnRoads` 畫的是 `built`。
- **什麼情況**：
  - 拆掉一格同時也是城市路的自己的路，`allCells` 的格數不變。
  - 同一段時間先拆再鋪一樣多格，格數也不變。
- **玩家看到**：3D 地圖上還留著已經拆掉的路，等到別的原因重建才更新。
- **查證**：讀程式。
- **修法**：key 改看 `built.count`，或 `built` 的雜湊。

### L-7（#1409）小城門可能畫在玩家斜切過的軌道上：P3

- **位置**：`Sources/GamePresentation/Map3DTaipeiLandmarks.swift:1113` 的 `isClearOfTrack`。只檢查軌道上每個取樣點（約 16 m 一個）是否落在矩形加 4 m 內。
- **什麼情況**：這個函式本來就是這樣，不是 #1409 寫的。但 #1409 加了很小的城門（小南門約 13.6 × 12.6 m）。軌道斜切過城門一角時，前後兩個取樣點都可能落在範圍外。
- **玩家看到**：城門蓋在玩家的軌道上。
- **查證**：讀程式；要在小南門或北門斜鋪一條軌道才能確定。
- **修法**：改成量線段到矩形的距離，不只看取樣點。

### L-8（#1421）疑點：tight 機型在台北可能一直被降到最低畫質

- **位置**：`RailwayGameApp/Views/Map3D/Map3DMetalView.swift:1366–1371`；`DeviceLoad.swift` 的 `least` 是 300 MB。
- **什麼情況**：剩餘記憶體低於 300 MB 時呼叫 `relieve()`，一次降兩格；10 秒後還是低，就再降。
  - 決策 460 自己量到街景只佔 0.6 MB，降格幾乎不放記憶體。所以 4 GB 的機型如果在台北一直低於 300 MB，約 30 秒內就降到底，之後慢慢爬回去又被降下來。
  - 降低後的格位還會被 `rememberRung` 記到下次開 3D。
- **要確定**：看實機的 `os_proc_available_memory`（問題回報的「裝置」那一項）。

### L-9（#1415）疑點：被換掉的世界交給低優先的工作放掉

- **位置**：`Sources/GamePresentation/GameSession.swift:2033`：舊的世界交給 `Task.detached(priority: .utility)` 放掉。
- **什麼情況**：utility 的工作如果一直排不到，舊世界就會在記憶體裡累積。實際上 tick 一次只算一個、通常有空的核心，新舊世界也多半共用同一份儲存（copy-on-write），所以應該不會發生。
- **要確定**：在實機用 Instruments 看 6000× 下記憶體是否穩定。
- **檔案在 BP-2 手上**：GameSession 一帶由 BP-2（#1434）在改，這一條只寫在這裡、告訴規劃，不自己改。

### 只記一筆、不編號

- #1400：讀道路的時候再開平溪挑戰或實景示範，會回 nil、什麼都不顯示（`startChallenge`、`openRealWorldDemo`，`GameLauncher.swift:519`、`:722`；守衛在 `:745`）。載入畫面蓋住了按鈕，玩家碰不到。
- #1415：一小時中途打開站長角落，看到的是這小時開頭的建議。決策 459 寫明這是刻意的。
- #1423：遇到 `trackConflict` 的那一下點擊會鋪兩次，見第二節。

## 四、和進行中的 session 的關係

| session | 碰到的檔 | 這一輪 |
| --- | --- | --- |
| BP-2（#1434） | GameSession 一帶 | L-9 是疑點，在它的檔裡，交給規劃 |
| BZ（`claude/trace-overlap`） | RealRailwayTracing、真實路線畫面 | 沒有發現 |
| BO | Map3DMeshSimplifier、Meshy | 沒有發現 |
| BY | GameCore 派車、三鶯 | 沒有發現（#1422 的三鶯只進 `studies`） |

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests`（cc0256c，Linux，官方 Swift 6.4.0 `/opt/swift`） | **VERIFIED**，Build complete |
| A 組的測試：`SpeedLagHintTests`、`NightSkipTests`、`LineLossFixesTests`、`StationMasterHourReportTests`、`RealWorldDemoRoadsTests`、`DemoRealLinesTests` | **VERIFIED**：63 通過，1 略過（要設環境變數才跑） |
| C 組的測試：`Map3DBoxInstanceTests`、`DeviceLoadTests`、`Map3DModelPackSizeTests`、`Map3DCoarseChunkTests` | **VERIFIED**：23 通過（含 struct 佈局 88 / 88 / 4） |
| D 組的測試：14 個類別（台北捷運 461、夜燈、模型包大小、布景、台北地標、行人號誌、標線、道路橋、三鶯、台中綠線、WhatsNew、真實列車、市區公車、編組） | **VERIFIED**：104 個，0 失敗，2 個本來就略過 |
| `node --test tools/train-models/test.mjs`、`python3 -m unittest`（#1416） | **VERIFIED**：5、6 個通過 |
| 臨時測試（L-3、L-4 的斜拖與界外起點；#1393 換模型後的 `headSigns`；#1406 的 `Pace`；#1417 的針葉樹離軌道距離；#1424 的配車） | **VERIFIED**：數字寫在上面各條 |
| 臨時測試 | 都已刪除，這個 branch 只加這份文件 |
| `python3 -I tools/golden-checks/doc_numbers.py --check` | **VERIFIED**，通過 |
| L-1、L-2、L-5～L-9 | 只讀程式、追了呼叫路徑，**UNVERIFIED** |
| `.metal`、App 層、iOS 建置、UI 測試、實機畫面與記憶體 | **UNVERIFIED LOCALLY**，要 macOS、CI 或實機 |

## 六、五方

- **玩家**：沒有會閃退、壞存檔或卡死的錯。要在公開前看的是 L-1（4 GB 機型快速開關 3D 時記憶體加倍）和 L-8（tight 機型畫質一直被降）。兩件都要實機量，已告訴規劃。其他是鋪路畫面與提示的小問題。
- **鐵道迷**：台北捷運的配車、六家線月台架高、Apple 地圖與遊戲對齊都正確；L-7 是城門蓋在軌道上，少見。
- **開發**：三個 GameCore PR 都逐位元相同，#1394 的上限也有小上限的測試涵蓋。L-1、L-2 在 App 層，Linux 上寫不出會紅的測試，修的人要在 macOS 驗。
- **美術**：L-3（三角形路面）和 L-7（城門蓋在軌道上）是畫面問題，修的時候照決策 438、457 的預覽圖對。
- **音樂**：無。
