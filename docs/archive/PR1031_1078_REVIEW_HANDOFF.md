# 交接：PR #1031–#1078 審查 F 組

Session：session_01PFerWVHLXvDG7PZGKYqgCu。遊戲規劃 session_01H5RHAwnA69n8EfAUSUrH52 派工，日期 2026-10-23（作者：「滿30點記得pr review」）。派工單：審查 main 上已合併的 #1031–#1078 的程式 PR；#1079 起由下一輪（審查 G）看。

- 審查基準：`main` **a2e2a90**（開工時最新合併的是 #1107）。
- 範圍：#1031–#1078。點數照 HANDOFF 第 1 節「多久審查一次」計算。
- 上一輪：[PR1019_1030](PR1019_1030_REVIEW_HANDOFF.md)（審查 E，發版前小審查）。
- 存檔版本、決策編號、golden schema 都**不動**。GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 一個 PR：這份文件、HANDOFF 與兩個修正（F1、F2）都在 `claude/review-f-1031-1078`。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）與 python3。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 範圍內合併的 PR | 47 個：#1031–#1078（#1041 是工作登記 issue，不是 PR） |
| 程式 PR（有點數） | **29 個、35 點**：GameCore 6 個（#1045、#1047、#1060、#1064、#1065、#1078）共 12 點，其他 23 個各 1 點 |
| 0 點（跳過） | 文件 14 個：#1031、#1049、#1050、#1051、#1053、#1054、#1055、#1056、#1058、#1062、#1063、#1068、#1071、#1075；只改 UI 測試 4 個：#1032、#1033、#1037、#1039 |
| 新發現 | **4 個**：P2 兩個（F1、F2），P3 兩個（F3、F4） |
| 已修 | **2 個**：F1、F2（本 PR，各附回歸測試） |
| 沒修，交出去 | **2 個**：F3、F4，見第四節 |

GameCore 的六個 PR 由本 session 自己讀，其他的分給兩個子代理：3D 地圖（10 個）、App／GamePresentation／CI 與打包資源（13 個）。子代理的發現都由本 session 再讀程式確認過；F1、F2 先寫成會紅的測試再修。

## 二、逐 PR

GameCore（2 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#1045](https://github.com/a91453/railway-game-ios/pull/1045)、[#1047](https://github.com/a91453/railway-game-ios/pull/1047)、[#1064](https://github.com/a91453/railway-game-ios/pull/1064) | 鳴日號、環島之星、仲夏寶島號：`TrainTypeCatalog` 新列（代碼不重複、`isSightseeing` 改由 `sightseeingStars > 0` 算出，舊的三款仍是 50）；`TrainPerformance` 三組值在 `1...maximumRate`；`sightseeingStops()` 取停靠列車中最多的星數，依 `stations` 順序，決定性不受 `Dictionary` 影響；乘客計畫的鍵本來就有 `tourismStars`；GamePresentation 的名稱、塗裝、3D 編組、性能預設都補齊兩種語言；玩家文字「景點加 1.25 星」只說效果 | 無問題 |
| [#1060](https://github.com/a91453/railway-game-ios/pull/1060) | 決策 361 自有公園與廟，存檔 71：`look`、`visitors` 只在非 0 時寫、讀不到給 0，舊檔照讀；`validate` 檢查 look 在範圍、只有廟有 visitors；`placeBuilding` 先驗 look 再做別的（失敗原子）；公園、廟不住人，賣給市政府時 `handOverToCity` 直接跳過；地價的公園列帶（`parkRows`）對建物中心不在格子中央的情形也不會漏；乘客計畫在廟增減時作廢（`passengerPlan.temples`）；`PlayerCommand.Edit.placeBuilding` 的 `look` 是 Optional，舊的指令記錄照讀 | 無問題 |
| [#1065](https://github.com/a91453/railway-game-ios/pull/1065) | 決策 364 環狀線：`ringCallsToFirst` 兩個方向的站序（內環遞增到最後一站再整圈、外環遞減到 1 再整圈）；`ringWayRuns` 讓只有一列車的環狀線不排外環的旅客；`PassengerPlanKey` 含整條 `lines`（含 `trains`），列車數一變計畫就重算；`long-leg-traffic.json` 重錄的理由逐值寫在 ReplayFixtures README；`swift-shards.sh` 的兩個新類別放 campaigns-11 | 無問題 |
| [#1078](https://github.com/a91453/railway-game-ios/pull/1078) | 決策 366 照班距派車的越行：迭代都照 `lines`、`plan.services` 的順序，`Set` 只拿來查；等待的 `hold` 用 `departureDue`（含誤點），超過就放行；同一點已有決策 59 的等待就不加；`TrafficPlanKey` 加到站、離站時間，與 `execution` 同時變，重算時機不變 | 無問題。備註：每次重算計畫是照班距線列車的兩兩配對（n²），大多在第一個 guard（同站同股）就跳出；沒有量大路網的成本，不算發現 |

其他（1 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#1034](https://github.com/a91453/railway-game-ios/pull/1034) | 車站紀念章的後續：脈衝標記、`collectedStamps`、縣市分組、離開主執行緒的縣市查詢 | **F1（P2），已修** |
| #1036 | 一鍵鋪路線途中的鎖：涵蓋 `setSpeed`、`togglePause`、`skipToMorning`、復原／重做、建造暫停與兩處按鈕；`defer` 的順序讓解鎖前先換速度；`trackEdgePoint` 的外框預篩（三次貝茲曲線在控制點凸包內，留 1 單位） | 無問題 |
| #1040、#1046 | 只改點擊範圍（44 pt 的 `contentShape`）；新的 UI 測試類別在專案裡、跑 full lane | 無問題 |
| #1042 | 登記 issue 從 #231 改 #1041；`full_lane_watch.py --selftest` | 無問題 |
| [#1057](https://github.com/a91453/railway-game-ios/pull/1057) | 決策 360 第一步：3D 跟車最高 10× | **F2（P2），已修** |
| #1059 | 升級複線的預覽改以 `commandRevision` 為鍵，✓ 時世界已變就重算；錢不夠仍由 GameCore 拒絕 | 無問題 |
| #1066 | `CoverageMemo.Key`（範圍、土地、開著的車站位置）涵蓋 `coveredCells` 與 `CoverageSummary` 的所有輸入；夜間快轉在主執行緒外試跑 | 無問題 |
| #1069 | 資料出處：前後比對 id 與網址，沒有刪掉的，新增 13 筆、兩種語言都有 | 無問題 |
| #1072 | `ScreenFacts` 在世界、教學、新聞與四個選取 ID 任一改變時更新 | 無問題 |
| #1073 | 隱私清單在 Copy Bundle Resources、`release-archive.yml` 檢查並 lint；程式裡沒有其他需要理由的 API | 無問題 |
| #1074 | `NSPhotoLibraryAddUsageDescription` 在 `project.yml`、專案兩個組態、兩種語言的 `InfoPlist.strings`；文字只說用途 | 無問題 |
| #1076 | 夜間快轉的試跑移出 tick：每個提早 return 都在試跑之前 | 無問題。既有的：`GameSession.init` 仍在主執行緒同步試跑一次（夜裡開大存檔），不是這個 PR 加的 |
| #1077 | 2D 地圖分層畫布：每層的相等判斷涵蓋它畫的東西，畫的順序不變，放大鏡仍畫全部；`big-grid` 測試世界只給 UI 測試 | 無問題 |
| #1035 | 3D 路名招牌：圖集索引取模有保護、實例版面 64 B 對得上 `Map3DSignIn`、讀壞的圖磚退回沒有招牌；Noto Sans TC（OFL）只畫成 PNG，README 有出處 | 無問題 |
| #1038 | 路面標線：24 層正好填滿 `nightWindows[12]` 與 `glassMirror[24]`，第 25 層有 precondition；路口與支線先檢查 `count >= 2` | 無問題 |
| #1043 | Fresnel：`Map3DReflection.rows` 的 12 個 float 對得上 shader；水面層 −3 與發光層在 Swift 與 Metal 都分開 | 無問題 |
| [#1044](https://github.com/a91453/railway-game-ios/pull/1044) | 太陽陰影：uniform 的順序與大小、texture 1 每個讀它的 fragment shader 都有綁 | F3（P3） |
| #1048 | 3D 邊開邊載入：世代號擋住過時的區塊、建模在 `Task.detached`、主執行緒只每 0.25 秒做小規模規劃 | 無問題 |
| #1052、#1061 | 隧道：`Map3DTrackCover` 的格子查詢有界、`addBore` 只從保留 2 點以上的 `pieces(of:)` 進來、串流區塊拿到整個路網的覆蓋 | 無問題 |
| [#1067](https://github.com/a91453/railway-game-ios/pull/1067) | 3D 畫質的「省電」與「關」 | F4（P3） |
| #1070 | 遠處粗略區塊：建模與 `Window.finished` 用同一個距離與半徑；升級（≤2,000 m）與降級（>3,024 m）不會來回跳 | 無問題 |

## 三、修了的

### F1（#1034）教學、課程與演示裡，車站卡答應會蓋紀念章，但永遠不會蓋，P2，已修

- **路徑**：`GameSession.stationStampStatus(of:)` 對任何真實車站都回 `.notYet`，車站卡（`StationPanel.swift`）就寫「紀念章：還沒收集。列車在這裡載客，第二天就蓋上。」但 `GameLauncher.checkStationStamps` 在演示、教學、課程裡直接 return，不收集。例：演示模式在台北一鍵鋪好路線（決策 351），點臺北站，卡上答應明天蓋章，永遠等不到。
- **回歸測試**：`StationStampTests.testTheDemoPromisesNoStamp`（`news.isDemo = true` 時應回 `nil`）。
- **修法**：兩處共用一個 `GameSession.collectsStationStamps`（不是演示、沒有教學、沒有課程），車站卡在不收集的局裡不顯示紀念章那一行。

### F2（#1057）夜間快轉中進 3D 跟車，關掉 3D 後遊戲停在最快速度，P2，已修

- **路徑**：夜裡快轉（決策 305）時時鐘是快轉自己的速度（例如 `.fast`）。玩家跟一列車、打開 3D：`updateMap3DSpeedCap()` 把 `clock.runningSpeed`（`.fast`）記成 `speedBefore3D`，再 `setRunningSpeed(.x10)`；`setRunningSpeed` 呼叫 `dropNightSkip()`，丟掉 `nightSkipRun.speed`（玩家原本的 600×）。關掉 3D 時 `setRunningSpeed(speedBefore3D)` 給回 `.fast`：白天的 2D 地圖以最快速度跑；3D 開著時的存檔（`worldToSave`）也寫 `.fast`。決策 360 寫的是「關掉 3D 就回到原本的 600×」。
- **回歸測試**：`NightSkipTests.testFollowingIn3DDuringTheSkipGivesBackThePlayersSpeed`。在 a2e2a90 上紅兩處（存檔與關 3D 後都是 `fast`，應為 `normal`），修了之後綠。
- **修法**：快轉進行中時，玩家的速度是 `nightSkipRun.speed`；3D 依它封頂，要記住的也是它（玩家原本就在 10× 以下時不必記，關 3D 後維持原速）。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| F3 | #1044 | P3 | `Map3DMetalView.draw` 裡 `wantedSunRegion(at:)` 先把 `sunDrawn`、`sunDrawnAt` 設好、`sunSceneChanged = false`（尺寸變了還換一張清空的 `sunMap`），之後第一個 `guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable, …` 失敗（GPU 忙、`nextDrawable` 逾時）就 return，沒畫陰影圖也沒重設 `sunDrawn`（只有第二個 guard 有重設）。之後幾幀 `isStale` 為 false，shader 取到沒畫過的陰影圖：陰影消失或位置不對，鏡頭不動、1× 時可能維持幾分鐘，直到太陽轉 0.01 rad、目標移動或場景改變 | 只有實機能確認；修法很小（第一個 guard 也設 `sunDrawn = nil`，或在 `drawSunMap` 之後才設） | 3D 城市線（#1044 的作者） |
| F4 | #1067 | P3 | 「省電」與「關」的 `samplesPerPixel` 是 1，`seeThroughPipeline` 仍開 `isAlphaToCoverageEnabled`，`rasterSampleCount = 1`。決策 342 讓擋在跟車列車前的建物以 25%（`Map3DSeeThrough.opacity`）顯示，靠的是 4 個 MSAA 樣本；1 個樣本時覆蓋只有全或無，那面牆可能整片不見，而不是半透明。決策 365 沒提這個改變 | Apple GPU 在單樣本時會不會對 alpha-to-coverage 做抖動，只有實機能答 | 3D 城市線（#1067 的作者）：實機看省電模式跟車時前面的建物；若整片消失，單樣本時改用混色或抖動 |

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（本 PR） | **VERIFIED**，乾淨 |
| F1、F2 的回歸測試 | **VERIFIED**：F2 在 a2e2a90 的程式上紅（兩個 `fast` ≠ `normal`），修了之後綠；F1 由子代理在 a2e2a90 上以暫時測試重現（回 `.notYet`），修了之後新測試綠 |
| `swift test --skip-build --filter "NightSkipTests\|Map3DFollowSpeedTests\|StationStampTests"` | **VERIFIED**，68 個，0 失敗 |
| `python3 -I tools/ci-watch/full_lane_watch.py --selftest` | **VERIFIED**（子代理） |
| F3、F4 | **UNVERIFIED**：只讀程式、追了呼叫路徑，需要實機 |
| 完整測試、iOS 的建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

## 六、五方

- 玩家：兩個 P2 是玩家會碰到的（夜裡跟車後速度失控、教學裡等不到的紀念章），在下一版之前修好。
- 鐵道迷：觀光列車的編組、性能與星數照決策 286 寫的出處；照班距越行（決策 366）不借對向正線，和決策文字一致。
- 開發：六個 GameCore PR 的存檔（71）、Codable 預設值、驗證、決定性與計畫快取的鍵都查過，沒有問題；修正只動 GamePresentation，不動存檔與 golden。
- 美術：無（素材不在範圍）。
- 音樂：無。
