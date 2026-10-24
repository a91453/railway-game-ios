# 交接：PR #1137–#1188 審查 H 組

Session：session_01G5KnXReBk4W8w69FWWX4LW。遊戲規劃 session_019yHzrc1rgGJgdXSSwRNqgM 派工，日期 2026-10-24。派工單：審查 main 上已合併的 #1137–#1188 的程式 PR（32 點）；GameCore 的 #1166、#1175、#1178 必看。#1189 起由下一輪看。

- 審查基準：`main` **717947b**（#1190 合併後）。
- 範圍：#1137–#1188。點數照 HANDOFF 第 1 節「多久審查一次」計算。
- 上一輪：[PR1079_1136](PR1079_1136_REVIEW_HANDOFF.md)（審查 G）。
- 存檔版本、決策編號、golden schema 都**不動**。GameCore、GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 兩個 PR：這份文件與 HANDOFF、OVERVIEW 在 `claude/review-h-1137-1188`；兩個修正（H2、H3）在 [#1195](https://github.com/a91453/railway-game-ios/pull/1195)（`claude/review-h-fixes`）。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）與 python3。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 範圍內合併的 PR | 52 個 |
| 程式 PR（有點數） | **29 個、32 點**：GameCore 3 個（#1166、#1175、#1178）各 2 點；其他 26 個各 1 點（#1165、#1167、#1168 是 #1162 工具的一行修改，各算 1 點） |
| 0 點（跳過） | 23 個。只改文件：#1141、#1142、#1143、#1144、#1147、#1148、#1149、#1154、#1161、#1169、#1170、#1172、#1177；只改 TestFlight 的 What to Test 文字（`.github/testflight-whats-new.md`）：#1145、#1180、#1185、#1187；只改 UI 測試：#1140、#1146、#1153、#1163、#1181、#1188 |
| 新發現 | **8 個**：P2 三個（H1、H2、H4），P3 五個（H3、H5–H8） |
| 已修 | **2 個**：H2、H3（#1195，附回歸測試） |
| 沒修，交出去 | **6 個**：H1、H4–H8，見第四節 |

三個 GameCore PR 由本 session 自己讀。其他的分給三個子代理：3D 繪製與底圖工具（9 個）、Game Center／iCloud／跟車資訊（7 個）、課程／劇情／收購車站／列車模型／CI（8 個）。子代理的發現都由本 session 再讀程式確認過；H1、H2、H3 由本 session 寫測試在 origin/main 上跑紅。

## 二、逐 PR

GameCore（各 2 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#1166](https://github.com/a91453/railway-game-ios/pull/1166) | 決策 398：`PlacedBuildingKind.looks` 只把飯店改 3、百貨改 2；GameCore 只有 `placeBuilding` 與解碼用它檢查範圍，舊存檔的 look 0 照讀，不影響 golden、replay。GamePresentation：`placedKitLayouts[kind]![look]` 的 look 已由 GameCore 擋住；`seaward(of:)` 的格子換算（負數向下取整）與 `isWater` 越界；外框盒子的轉向與 `StationKitBuilder.add` 一致；屋頂換色只換奶油色與其陰影 | 無問題 |
| [#1175](https://github.com/a91453/railway-game-ios/pull/1175) | 決策 401：`buyMapTile(_:passingMilestone:)` 預設關，既有指令不變；`buyingOrder` 先列後行、決定性，不相連時回 nil；`build` 先買地、讀土地再鋪軌道，在 `perform` 的副本上做，失敗整筆不成立；`tiles` 是選填欄位，舊的指令紀錄照讀；試蓋迴圈每次至少多一塊地，會結束；價格列的地價與合計 | 無問題 |
| [#1178](https://github.com/a91453/railway-game-ios/pull/1178) | 決策 400 10i-1：存檔 72 與遷移註解、`RoadGrid` 的編解碼（run 有序、不相鄰）、`problem(in:)`、每 30 天午夜長路（`dayWake` 加上 `roads`，批次與逐步一致有測試）、`nearestRoad` 的環狀搜尋提前結束、站前路的報價與錯誤順序、資本支出記帳、`StationRoadOffer`、`Map3DSceneKey` 加路格數 | **H1（P2）**；解碼總格數沒有上限已寫在決策 400「下一步」 |

其他（1 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#1137](https://github.com/a91453/railway-game-ios/pull/1137) | 決策 390：第 2 課每一步的目標與提示、第 7 課營運時間的按鈕與 xcstrings、連通目標的標題、新提示 | **H2（P2）、H3（P3），已修** |
| #1138 | 沙盒挑戰的劇情：進度段落、一段接一段的順序、第一次只記不說、目標列順序與目標索引 | 無問題 |
| #1139 | 審查 G 的兩個修正：`TrainMotion.source` 的比對只影響效能；`Snapshot.resumed` | 無問題（H3 的根源之一，見下） |
| #1150 | `ios-build.yml`：build job 跑第二、課程 job 以外的所有 UI 測試，兩份清單不重疊，每個 UI 測試類別恰好跑一次 | 無問題 |
| #1151 | 決策 392：`nearestTracks`、島式月台另一側的正負號與索引、`count > 1` 擋住的強制解包、寬度不夠不畫 | 無問題 |
| #1152 | 決策 394：`Map3DUnderground` 的地下判斷與遲滯、`portalEnds` 看整個路網、`Map3DMetalView` 跳過的 pass、沒有太陽陰影時、雨層的 `Equatable` | 無問題 |
| [#1155](https://github.com/a91453/railway-game-ios/pull/1155) | 決策 395：隧道內的吊架、洞口內縮、電桿與洞口的關係 | **H5（P3）** |
| #1156 | 決策 396：`GameCenterMapping` 38 個 id、點數合計 800、未解鎖時停在 99%、只送本週最佳、規則版本選排行榜；`GameCenterLedger`；GameKit 的呼叫都在 iOS 14 以上（目標 iOS 17）；示範、教學、課程與無限資金不回報 | 無問題 |
| #1157 | 決策 393：`Cover` 的 raw value 位移（沒有別處用 raw value）、0.035 m 的層距（水面 0.245 m 仍在人行道 0.26 m 下）、2D 樣式層 | 無問題 |
| #1158 | 只看 entitlement：`.entitlements`、`project.yml` 與 pbxproj 兩個設定的 `CODE_SIGN_ENTITLEMENTS` 一致 | 無問題 |
| [#1159](https://github.com/a91453/railway-game-ios/pull/1159) | 決策 391：橋面接續、交越與上下限的決定性（max／min，與順序無關）、分塊與整體建置一致、`bridgeLevel`、`parts(of:)`、街景與道具的抬高 | **H4（P2）、H6（P3）** |
| [#1160](https://github.com/a91453/railway-game-ios/pull/1160) | 決策 397：`SaveSync.run` 的每個分支對照規則 2–7（另一台刪掉的照留、遊戲開著不寫自動存檔、`keepingDevice` 不覆寫不刪、較新版本的存檔不就地覆寫、寫一半的組放回、換帳號清狀態、下載中的跳過）；整輪在 `saveQueue` 上；`BackgroundSave` 等 `savesWritten()` | **H7（P3）**；沒有找到會丟存檔的路徑 |
| #1162、#1165、#1167、#1168 | Game Center 設定工具與 workflow：只能 `workflow_dispatch`、`testflight` 環境、限 `main`；secret 只進一個步驟的環境變數，輸入也走環境變數；金鑰寫 0600 暫存檔、不印 token；分頁連結限同一主機才帶 token；檢查用的 workflow 沒有 secret。三個後續的 `PT168H`、`FREQ=DAILY;INTERVAL=7` 在 JSON、工具、測試、文件一致。`test_game_center_setup.py` 14 個通過 | 無問題 |
| #1164 | 決策 399：依模型的車廂配置（蒸汽機車加煤水車是 count+1 節，索引在範圍內）、7 節固定編組、模型包鎖住時退回 | 無問題 |
| [#1171](https://github.com/a91453/railway-game-ios/pull/1171) | `build_basemap.py` 的 `osm_layer` 解析、`vector_layers` 欄位 | 無問題（備註見 H8） |
| #1173 | iCloud entitlement：容器 `iCloud.io.github.a91453.RailwayGame` 與 `CloudDocuments`，和 `url(forUbiquityContainerIdentifier: nil)` 取第一個容器一致；存檔不在 `Documents/`，不需要 `NSUbiquitousContainers` | 無問題 |
| #1174 | 收購單一真實車站：走 `PlayerCommand.buyRealStation` → `perform`，整筆成立或不成立；價格在有錢的副本上算；沒得買或錢不夠時按鈕不能按；編解碼一致；教學與課程排除 | 無問題 |
| #1176 | 決策 391 續篇三：`roadBeside`、護欄分段 | 無問題 |
| #1179 | 決策 391 續篇二：`addJoins` 的分類、`openings(of:)` 的合併與索引、路塹 `min(rise) < 1` | 無問題（`Map3DRoadBridge.swift:609` 的接合也有 H4 那種越遠越寬的判斷，沒有另外測） |
| #1182 | 決策 402：`RealRailTracks` 解碼的檢查、`Laid.lanes`（強制解包安全、同距離時決定性、左右行車的正負號）、視窗與 run、`bought` 對照、pbxproj 的資源、`extract_tracks.py` | 無問題 |
| #1183 | 決策 403：單位（世界單位、ms × 1000、km/h）、到站提示的表定時間與 `scheduledArrival(of:cycle:)` 一致、誤點的取整、1 km／3 km／30 s 門檻、前方限速合併、`runCurve` 有記憶；兩種語言的文字只說畫面上是什麼 | 無問題 |
| #1184、#1186 | `swift-shards.sh`：selftest 通過；campaigns-1..17 的類別沒有重複，都在 `Tests/` 裡；沒列的照設計進 `rest` | 無問題 |

## 三、修了的（#1195）

### H2（#1137）第 2 課先蓋一小段再畫到城鎮，「按 ✓ 蓋好軌道」被跳過，P2，已修

- **路徑**：lesson.2.track，先點路線的端點、再點第三座城鎮之前的一點，按 ✓（比最短長度長，這一步還在等）。接著點第三座城鎮，畫的那段接到城鎮，這一步完成。按「下一步」：`.buildTrack` 只看「蓋了的新軌道 ≥ 最短長度」，前一小段已經算，`track.build` 被跳過，到了 `station.mode`；它的 `.clearPicks` 和按「月台」把還沒蓋的那段丟掉（`TutorialSession.swift:339`）。
- **玩家看到**：卡片說「點第三座城鎮裡的軌道」，那裡沒有軌道；點城鎮選不到站址，卡片也不說要回軌道工具。
- **回歸測試**：`LessonGuideTests.testTheSecondLessonWaitsForTheStretchThatReachesTheTownToBeBuilt`。在 717947b 上紅（按「下一步」後是 `station.mode`）；修了之後綠。
- **修法**：要接到地點時，`.buildTrack` 另外要求**蓋好的**軌道經過那些地點，畫著的那段不算（`newTrackReachesEveryPlace(since:drawn: false)`）。

### H3（#1137、#1139）重開 App 在第 2 課軌道步驟接續，軌道兩步都直接跳過，P3，已修

- **路徑**：App 停在 lesson.2.track，重開按「繼續教學」。`Snapshot.resumed(over:)` 的 `stations` 是空的（讓已經蓋的都算新），`holdsForPlaces` 看 `!before.stations.isEmpty`（`TutorialSession.swift:462`），於是不再等地點；課程原有的路線算成新軌道，這一步與 `track.build` 立刻完成，停在「點月台」，往第三座城鎮什麼都沒有。站址也不再限定在城鎮。
- **回歸測試**：`LessonGuideTests.testTheSecondLessonTakenUpAgainStillWaitsForTrackToTheTown`。在 717947b 上紅；修了之後綠。
- **修法**：`Snapshot` 多記 `hadStations`。平常照世界算（和以前一樣）；接續時照課程算：第 1 課之後的課程都從第 1 課的路線開始（`GameWorld.newGame(lesson:)`）。不用接續時的世界，因為第 1 課蓋了車站後接續也會有車站，而第 1 課刻意不等（`TutorialSessionTests.testTheTutorialIsTakenUpAgainInALaterLaunch` 守這件事；第一版這樣寫就紅了 14 個斷言）。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| H1 | #1178 | P2 | **分區購買的空白地圖（新遊戲的預設）上，後來買的地塊永遠沒有路**。`newGame` 在 `enableMapExpansion` 之前用整張 5×5 地圖的 `Land.townCentres` 開路（`NewGame.swift:102`），三個城鎮都在中間那塊；`buyMapTile` 為新地塊建城鎮（`MapExpansion.swift` `foundTowns(in:seed:)`），`roads.towns` 卻沒有加。長路只朝「離每個城鎮中心最近的車站」（`RoadGrid.swift:284`），一個月一格，所以新地塊的城鎮沒有路，那裡的車站永遠是「路還沒長到這裡：站前路最長 512 公尺。」。同樣地，中間那塊裡不是任何城鎮最近的車站也長不到路，車站面板的說明卻寫「道路每個月會自己往你的車站長」（`StationPanel.swift` `roadSection` 的 footer）。**VERIFIED**：探查測試（seed 7，`buysMap: true`，買下右邊一塊）新地塊有 982 格城鎮、0 格路；測試沒有留在 repository | 修法要動 GameCore（`buyMapTile` 在有 `roads` 時替新地塊的城鎮開 3×3 種子並加進 `towns`，或沒有城鎮的長路也讓每個車站都拉一格），golden、replay 不受影響（它們沒有 `roads`），但是 GameCore 的規則改變，照派工交規劃；footer 的文字可在同一個 PR 依規則改 | 遊戲規劃另派（決策 400 的作者線），可用決策 400 的一列或新號 |
| H4 | #1159 | P2 | **地面的路在橋端旁邊與橋平行時，被橋的坡道抬起來**。`roadRise` 的橋端迴圈接受任何大致平行（≥ 0.9）、側向距離 ≤ `end.half + 0.15 * out` 的路（`Map3DRoadBridge.swift:596`），容許範圍隨離橋端越遠越寬，沒有確認這條路是從橋端接出去的。路徑：實景底圖上跨線橋的端點旁有平行的側車道（台北、新北很常見）；`addStrip`、`addRoadBridges`、街景、`roadBeside` 與標線都用它。玩家看到側車道半途離地抬高再斜回地面，還有擋牆，車與標線跟著上去。**VERIFIED（子代理的 Linux 測試）**：平地上一座跨線橋，平行的次要道路從橋端外 46 m 起：一層的 secondary 橋，側路離中心 12／15／18 m 時抬高 3.0／2.5／1.56 m；layer 2 的 motorway 橋，側路離 20 m 從 0 跳到 7.1 m、離 28 m 跳到 4.7 m | 那個越遠越寬的範圍是為了讓彎的坡道（決策 391：「坡道也接到橋端外面的地面道路上（最多 120 m）」）接得上；本 session 算過，彎道半徑 100 m 的坡道與平行的側車道在局部幾何上分不開，只改公式會壞掉彎坡道。正確的修法要知道這條路是不是從橋端接出去（例如在建 `ends` 時記下接在端點上的那條 way，`roadRise` 帶著路的身分比對），超過一兩個檔 | 3D 城市線（決策 391 的作者）；修時一併看 `:609` 的接合 |
| H5 | #1155 | P3 | **軌道由隧道出到地面的洞口沒有電桿**。隧道線現在也在 `lines` 裡，最後一點進了 `ends`（`Map3DOverheadLine.swift:152`）；洞外那條線的第一根看到「別條線在這裡結束、它的電桿撐這條線」就跳過（`:270`），隧道那條卻不立電桿。與決策 395 規則 7「洞口那一點由洞外的電桿撐住」不符；既有測試只測了地面進隧道。**VERIFIED（子代理的 Linux 測試）**：同樣的幾何兩個方向，地面→隧道在 x = −0.11 有電桿，隧道→地面第一根在 x = 40.1 | P3，派工只修 P1、P2；修法一行（隧道線不加進 `ends`，或 order 0 的判斷略過隧道的端點）加一個反方向的測試 | 3D 城市線（決策 395 的作者） |
| H6 | #1159 | P3 | **與高架平行的地面道路，路口的標線消失**。`addMark` 對每個標線都用 `roadRise(..., onDeck: true).onBridge` 判斷（`Map3DRoadMarkings.swift:290`），不知道標線屬於哪條路；地面路上的斑馬線、停止線、箭頭在平行的橋面半寬加 0.5 m 內、方向 ≥ 0.9 時被當成在橋面上而拿掉。例：市民高架、建國高架下的路口 | 只讀程式（**UNVERIFIED**）；修法是像道具一樣傳標線所屬那條路的橋層，不用 `onDeck: true` | 3D 城市線，與 H4 一起 |
| H7 | #1160 | P3 | **iCloud 衝突版本可能被當成「來自另一台裝置」重複留下**。衝突版本的迴圈（`SaveSync.swift:248-270`）與 `keepAsCopy`（`:360-383`）每個沒解決的版本都另存一份，不比對內容是否和雲端目前的、本機的或已留的副本相同。iPhone、iPad 都離線改同一份後上傳，iCloud 把 iPhone 的留成衝突版本：iPhone 把**自己的**遊戲標成「來自另一台裝置」；兩台在解決前都看到時，都建同名的 `save-<savedAt>-other.json` 並上傳，可能再生出一份。玩家看到自己的遊戲被標成別台的、列表裡有內容一樣的存檔；不會丟存檔 | 只讀程式（**UNVERIFIED**），要看 iCloud 實際怎麼標記與解決衝突版本，只有決策 397 的兩台實機驗證能確認；修法在 `SaveSync.swift`：指紋與雲端目前的、本機同名的、這一輪已留的相同就略過，與本機相同時不標成另一台，加一個 `SaveSyncTests` | 決策 397 的作者，兩台實機驗證時一起 |
| H8 | #1171 | P3 | 備註：`build_basemap.py` 的 `osm_layer` 遇到 `layer=inf` 會丟出沒接住的 `OverflowError`，整個建圖停下 | 只影響工具，現在的資料沒有；下次重建底圖時順手 | 實景資料線 |

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（origin/main 717947b 與 #1195） | **VERIFIED**，乾淨 |
| H2、H3 的回歸測試 | **VERIFIED**：兩個都在 717947b 上紅，修了之後綠 |
| `swift test --skip-build --filter "Tutorial\|Lesson\|Snapshot"`（#1195） | **VERIFIED**，99 個，0 失敗（1 個本來就 skip） |
| H1 的探查測試 | **VERIFIED**（本 session，Linux；沒有留在 repository） |
| H4、H5 的測試 | **VERIFIED**（子代理，暫時的 worktree，已刪） |
| `swift-shards-selftest.sh`、shard 涵蓋；`test_game_center_setup.py` | **VERIFIED**（子代理） |
| H6–H8 | **UNVERIFIED**：只讀程式、追了呼叫路徑 |
| 完整測試、iOS 的建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

## 六、五方

- 玩家：H2 是照卡片走就會碰到的（第 2 課停在沒有軌道的城鎮），H1 是預設的新遊戲擴地後就會看到的（站前路永遠鋪不了），H4 是實景 3D 裡常見的側車道離地。H2、H3 已修，H1、H4 下一版之前派。
- 鐵道迷：H5 洞口沒有電桿和真實的架空線不符；其他無。
- 開發：三個 GameCore PR 裡兩個沒有問題；#1178 的 H1 是規則漏了地圖擴張，修要動 GameCore。修正只動 GamePresentation，不動存檔、重播與 golden。
- 美術：H4、H6 是 3D 道路畫錯的地方，要實機看。
- 音樂：無。
