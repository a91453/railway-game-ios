# 交接：PR #962–#1018 審查 D 組

Session：session_01TCwdHtJTq9REwDrCSHzR11。遊戲規劃 session_01CHQg7B6JqzbScGSjyDwHos 派工，日期 2026-10-22。派工單：審查 main 上從 #962 起已合併的程式 PR，看到開工時 main 上最新合併的那一號。

- 審查基準：`main` **d33defa7**。開工時 main 上最新合併的是 #1018。
- 範圍：#962–#1018。點數照 HANDOFF 第 1 節「多久審查一次」計算。
- 上一輪：[PR945_961](PR945_961_REVIEW_HANDOFF.md)（審查 C）。
- 存檔版本、決策編號、golden schema 都**不動**。GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 兩個 PR：
  - [#1023](https://github.com/a91453/railway-game-ios/pull/1023)：GamePresentation，修 D1、D2。
  - 這份文件所在的 PR：本報告與 HANDOFF。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）與 python3。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 範圍內合併的 PR | 52 個：#962–#1018，其中 #987、#991、#997、#1015、#1016 不在 main 上 |
| 程式 PR（有點數） | **36 個、40 點**：GameCore 4 個（#966、#974、#986、#995）共 8 點，其他 32 個各 1 點 |
| 0 點（跳過） | 文件 14 個；只加模型包的 2 個：#988 三節都市車、#992 五節／七節輕軌 |
| 新發現 | **5 個**：P2 一個（D1），P3 四個（D2–D5） |
| 已修 | **2 個**：D1、D2（#1023） |
| 沒修，交出去 | **3 個**：D3、D4、D5，見第四節 |

點數說明：HANDOFF 第 1 節寫的是「37 個、41 點」，差一個 PR。本輪把 #988、#992 算成模型包（0 點），因為它們只加 `Map3D*` 模型與產生腳本，沒有接進遊戲；遊戲規劃可能把其中一個算成程式。

GameCore 的四個 PR 由本 session 自己讀，其他的分給三個子代理：3D 列車、3D 場景、App／工具。子代理的發現都由本 session 再讀程式確認過；能寫成會紅的測試的，先寫出來再修。

## 二、逐 PR

GameCore（2 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#966](https://github.com/a91453/railway-game-ios/pull/966) | 世界檢查高鐵票價表的站 ID（`from >= 1`、`to < nextStationID`；因為 `isTable` 要求 `from < to`，這樣就夠）；A8：有班次的路線讀檔時改成平均發車；A6：誤點列車剩下的時間不再讓曲線限速失效（`timetabled` 與 `scheduled` 分開） | 無問題 |
| [#974](https://github.com/a91453/railway-game-ios/pull/974) | 審查 C 的 C1：環線讀檔改成平均發車；沒有主人的收購資產讀檔時拿掉 | 無問題 |
| [#986](https://github.com/a91453/railway-game-ios/pull/986) | 決策 332：汽機車分走旅客，存檔 70。整數運算（`share`、`lost`、`roadMinutes`）、`fullDistance` 的單位（世界單位，平方比較）；`setModeShift` 讓乘客計畫快取失效，計畫的輸入也有 `modeShift`；舊存檔沒有這個鍵就是關的；新開局才由 `NewGameOptions.apply` 打開，展示與挑戰都不經過它 | 無問題 |
| [#995](https://github.com/a91453/railway-game-ios/pull/995) | `dailyDemand` 拆成 `dailyDemandDetails`：逐行比對，拆開的 typhoon → distance → fare 和原本的 `keptTrips` 相同；`fastest` 改存整條路線，取的仍是最短分鐘那條 | 無問題 |

其他（1 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #962、#980、#993、#996、#1000 | 3D 列車外型的選擇：輕軌、綠色通勤車、三節都市車、列車包鎖住時的退回 | 無問題 |
| #973、#979、#981 | 跟車視角的狀態機、飛到月台、駕駛室視角（lens 重設、NaN 與除數保護） | 無問題 |
| [#1003](https://github.com/a91453/railway-game-ios/pull/1003) | 真實時刻表的列車畫進 3D | D3、D5（P3） |
| #1004 | 真實列車出站加速、進站煞車：驗算了距離恆等式，以及 L=0、T=0 的退回 | 無問題 |
| [#1010](https://github.com/a91453/railway-game-ios/pull/1010) | 1× 時列車滑過整整一秒 | D4（P3） |
| #965 | 真實廟宇：`build_temples.py` 的 PMTiles v3 與 MVT 解碼、19,201 筆資料的範圍、排序是全序 | 無問題。MVT 的 sint64 沒做 zigzag 解碼，但這份資料用不到，不算發現 |
| #976、#983、#994 | 車站下不放街道、公車不相疊、站前商店 | 無問題 |
| [#990](https://github.com/a91453/railway-game-ios/pull/990) | 公園套件 | **D1（P2）、D2（P3），已修** |
| #1006 | 透視錐：reversed Z 的投影、Metal 與 Swift 的 uniform 版面（288 B）、alpha-to-coverage | 無問題（GPU 端只做靜態比對） |
| #1008、#1009 | 套件模型的法線；道路旁的地塊 | 無問題。#1009 讓 D1 更常見 |
| #963 | 用我的位置開局：逾時任務、晚到的回呼 | 無問題 |
| #969 | 夜間快轉在 main actor 外試跑：用 `worldRevision` 丟掉過時的結果 | 無問題 |
| #970、#972、#982、#989、#998、#1002 | 需求文字、入口、汽機車轉移的提示 | 無問題 |
| #977 | `full_lane_watch.py`、`doc_numbers.py`、`ios-full-lane.yml` | 無問題；selftest 與 `--check` 都跑過 |
| #1001 | 縣市上限：367 個鄉鎮都有縣市，22 個縣市名都對得上 `ModeShiftCounties.shares` | 無問題 |
| [#1005](https://github.com/a91453/railway-game-ios/pull/1005) | 車站咽喉相接的雙線算成可以待避 | 無問題，原因見下 |
| #1007、#1012 | 跟車行駛聲、雨聲雷聲：暫停、倍速、退到背景、雷聲迴圈會不會結束 | 無問題 |

**#1005 查過、不是 bug**：
- 子代理報的是 P2：「路網有環時，單線段被算成可以待避」。理由是新的 BFS 會經過別的車站，也能折返。
- 但 `passingPlaceShortfall` 先過濾 `lineTrackCounts == 1`。這個數字由 GameCore 的 `parallelTracks` 算出，它是最大流，同樣會經過別的車站、也能折返。所以有環時那一段本來就是 2 股，#1005 之前也不報。
- #1005 只多排除一種情況：最大流是 1，但最小割落在路段外，也就是車站咽喉的轉轍器。這正是它要修的。
- 有環時算不算能待避，是決策 264 與 `parallelTracks` 本來的設計，不是這次的回歸。

## 三、修了的

### D1（#990）城市地塊蓋在公園場景上，P2，已修（#1023）

- **重現**：
  - `Map3DScene` 先放寺廟、站前商業，它們佔的格子都併進 `standing`，`addCity` 不在那裡放地塊。
  - `addParks` 沒有回報它放在哪些格子上。
  - `addArea` 要公園蓋住一個 64 m 格子的一半以上，才把那格算進 `taken.whole`。
  - 所以一個 30 m 見方的小公園只佔那格約 22%，卻放得下 18×20 m 的口袋公園，那一格照樣放城市地塊，樓房蓋在場景上。#1009 讓道路旁的格子也放建物，這種情況更常見。
  - 回歸測試 `testTheCellsItStandsOnAreTaken`：在 d33defa7 上編譯不過，因為 `addParks` 沒有回傳值。
- **修法**：`addParks` 回傳場景所在的格子，場景把它併進 `standing`。

### D2（#990）同一座大公園換個鏡頭焦點就換場景，P3，已修（#1023）

- **重現**：
  - 大公園選池塘涼亭還是運動場，種子是 `park.centre`，也就是場景座標。
  - 場景原點等於鏡頭焦點，拖動鏡頭或鋪軌重建場景後，同一座公園會在兩個場景之間跳。
  - `testABigParkKeepsItsSceneWhereverTheCameraIs`：在 d33defa7 上，6 座公園在 8 個焦點各得到 2 種場景（6120、3676 個三角形）。
- **修法**：改用公園在地圖上的位置（世界公尺）當種子，和 `addRealBuilding` 的做法相同。
- 順手修的原因：和 D1 同一個函式，修法只有兩行。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| D3 | #1003 | P3 | 阿里山林鐵（`afr`）在 3D 近處畫成通勤電聯車（列車包解鎖時是三節都市車），不是註解說的方塊。原因是 `Map3DRealTrains.formation` 的 default 回 `Formation(key: "", cars: 3)`，而 `Map3DModelPack.styleByType[""]` 是 `"commuter"`，所以 `models(forType: "")` 不是 nil。`Map3DRealTrainsTests` 刻意排除了 afr，所以測試沒抓到。測試寫法：key 為 `""`、3 節，在 eye 附近 `add`，斷言畫成方塊 | 要選：畫成方塊，還是給林鐵一個外型。這是 3D 的設計 | 3D 城市線 session_01H2iSUj5f1cCXAwjvuFvbsp |
| D4 | #1010 | P3 | 1× 時同一個遊戲秒內，`TrainMotion` 直接沿用上一個（`TrainMotion.swift:241`）。這一秒內玩家掉頭（`reverseTrain`）或換線的顏色，畫面最多晚約 1 秒才變；掉頭那次會直接跳過去，沒有滑。暫停時不走這條捷徑 | 是 #1010 換來順暢的代價；修法是捷徑也比對 `position` 與外觀，要量每 tick 的成本 | 修 #1010 的 session，或 3D 城市線 |
| D5 | #1003（既有） | P3 | 真實列車在 1× 時走半秒、停半秒：`RealTrainClock` 的滑動上限是 0.5 秒（`RealTrainMotion.swift:821`），但 1× 的遊戲時鐘每秒才變一次。#1010 只把玩家列車的上限放寬。2D 本來就這樣，3D 近看更明顯 | 不是這一輪新寫的；改法照 #1010（上限 1.25 秒），要實機看 | 3D 城市線 |
| — | （登記） | — | **決策 349 被登記兩次**：09:53 session_01H2iSUj5f1cCXAwjvuFvbsp 為 `claude/map3d-grade` 登記；10:10 #1020（`claude/map-buttons-layout`）又取用 | 不是程式 bug | 遊戲規劃：照登記先後，#1020 改號。已在 #231 留言 |

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（d33defa7、#1023） | **VERIFIED**，乾淨 |
| D1、D2 的回歸測試 | **VERIFIED**：在 d33defa7 上一個編譯不過、一個紅（6 座公園 × 2 種場景），修了之後都綠 |
| `swift test --skip-build --filter GamePresentationTests.Map3D`（#1023） | **VERIFIED**，354 個，0 失敗，7 個本來就略過 |
| 子代理在 d33defa7 跑的既有測試：NightSkip、WeatherSound、RunningSound、ModeShiftCounties、ModeShiftText、DiscoverableEntries、LessObviousEntries、StationDemandSession、MyLocationStart、AutoService、PassingLoopHint、PassingLoopSession、TRADemo、Map3DRealTrains、RealTrainMotion、TrainMotion、Map3DTrainSet、TrainPack、Map3DFollow、Map3DNextDeparture | **VERIFIED**，0 失敗 |
| `python3 -I tools/ci-watch/full_lane_watch.py --selftest`、`tools/golden-checks/doc_numbers.py --check` | **VERIFIED** |
| D3、D4、D5 | **UNVERIFIED**：只讀程式、追了呼叫路徑，沒寫成測試 |
| iOS 的建置、UI 測試、實機畫面 | **UNVERIFIED LOCALLY**，交給 `ios-build.yml` 與實機 |
