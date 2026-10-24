# 交接：PR #1079–#1136 審查 G 組

Session：session_012mpfbnZwWC7RpNFhhNgFKs。遊戲規劃 session_01H5RHAwnA69n8EfAUSUrH52 派工，日期 2026-10-23。派工單：審查 main 上已合併的 #1079–#1136 的程式 PR（32 點），順便查 full lane 的 `Feature284To286UITests` 紅是不是退步；#1137 起由下一輪看。

- 審查基準：`main` **ff8e4dd**（開工時最新合併的是 #1113）。
- 範圍：#1079–#1136。點數照 HANDOFF 第 1 節「多久審查一次」計算。
- 上一輪：[PR1031_1078](PR1031_1078_REVIEW_HANDOFF.md)（審查 F）。
- 存檔版本、決策編號、golden schema 都**不動**。GameCore、GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 一個 PR：這份文件、HANDOFF 與兩個修正（G1、G2）都在 `claude/review-g-1079-1136`。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）與 python3。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 範圍內合併的 PR | 47 個（其餘號碼是 issue、還開著或關掉沒合併的 PR） |
| 程式 PR（有點數） | **31 個、32 點**：GameCore 1 個（#1117）2 點，其他 30 個各 1 點 |
| 0 點（跳過） | 文件、只有素材或只改測試的 16 個：#1079、#1080、#1086、#1088、#1091、#1092、#1095、#1097、#1102、#1104、#1105、#1109、#1114、#1134、#1135、#1136 |
| 新發現 | **7 個**：P2 兩個（G1、G2），P3 五個（G3–G7） |
| 已修 | **2 個**：G1、G2（本 PR，各附回歸測試） |
| 沒修，交出去 | **5 個**：G3–G7，見第四節 |
| full lane 的 `Feature284To286UITests` | **不是退步**：Simulator 冷啟動慢造成的偶發，見第五節 |

GameCore 的 #1117 由本 session 自己讀。其他的分給四個子代理：3D 繪製與模型（8 個）、3D 真實資料（4 個）、效能與 App UI（7 個）、課程／經濟／車站／劇情／CI（11 個）。子代理的發現都由本 session 再讀程式確認過。G1、G2 先寫成會紅的測試，再修。

## 二、逐 PR

GameCore（2 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#1117](https://github.com/a91453/railway-game-ios/pull/1117) | 決策 378 第 5 關複線。`splitTrackEdge` 的檢查原樣抽成 `splitCut`，順序不變（切點、坡度、列車、月台、路線），切開的部分用同一組值，行為不變；`trackEdgeSplitRefusal` 不改世界。GamePresentation 這邊：`offsetPieces` 的取樣索引在 `0...steps` 之內；月台區段不切（切點移到月台端外 8 m）；每段的月台用該段的長度比例換算；`parallel` 改成段數之後，`planDoubleChain` 的渡線與主線分開走，不依賴兩邊段數相同；渡線先問能不能切，被拒的位置照樣會被拒。`tutorialDoubleTrackStretch` 的 `max` 以 id 決勝負，結果決定性；只在第 5 關的那一步算，路網小 | 無問題 |

其他（1 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1083 | 決策 354 車站卡的下一班分月台：`DepartureBoard.rows`、循環時刻表的第 0 站、`byPlatform` 的三層來源、15 分鐘分組（沒車時列下一班、每組最多 6 列）、`Map3DNextDeparture` 拆出 `routedPlatform` 後行為不變 | 無問題 |
| #1084 | 決策 372 夜間快轉配樂收小：`nightSkipRun` 的 didSet、和跟車壓低音樂相乘、換場景時送 `duckMusic?(1)` 重設 | 無問題 |
| #1085 | 決策 373 出票聲：成功、有價錢、和原本不同才響；同價時按鈕按不下去；提示音的類別、音量、間隔、震動都補齊 | 無問題 |
| #1087、#1090、#1120 | `swift-shards.sh`：selftest 通過；用 `swift test list` 的 4,079 個測試對 16 個 campaign shard 加 `rest` 逐一 `select`，每個測試恰好在一個 shard；`classes_of` 列的類別都存在；`CLASS_WEIGHTS` 沒有重複的鍵 | 無問題 |
| #1089 | 決策 374：票價需求提示只在經營模式、借錢試算（利息差額、平均最多 7 天、到上限或資金無限時不顯示）、`Lesson.number(unlocking:)`、型錄的 `firstOpen`；非課程的世界不受影響 | 無問題 |
| [#1093](https://github.com/a91453/railway-game-ios/pull/1093)、[#1100](https://github.com/a91453/railway-game-ios/pull/1100) | 決策 376 課程第 3–10 關一步一步帶：各步的目標與提示、`revealsInPanel`、換順序、復原、重開 App 後接續；`AutoService.NewLine.isFreight` 是選填，舊的指令記錄照讀 | **G2（P2），已修** |
| #1098 | `PolylineDetail`（重要度、子段上限、precondition 走不到）、`MapCanvas ==` 改寫前後等價、`MapMarks`、`ScreenFacts`、逐邊快取 | 無問題 |
| [#1108](https://github.com/a91453/railway-game-ios/pull/1108) | 決策 379：`CuePlayers` 只在自己的佇列建立與播放；`FrameCostMeter` 有鎖；`CFRunLoopObserver` 在主執行緒；背景算的滑行綁 `worldRevision` | **G1（P2），已修** |
| #1110 | 決策 381 主選單：舊入口都還走得到（存檔與匯入、挑戰、語言、資料來源）；xcstrings 刪掉的 5 個 key 沒人用，留下的非 verbatim key 都在；玩家文字只說功能 | 無問題 |
| #1113 | 決策 382 邊距：`HUDMargins`、`ToolColumn` 的切點、建設時完成與鐵鎚固定在底下、教學目標 `tool.select` 還在 | 無問題 |
| #1116 | 決策 384：`keepingOff` 搬家前後相同；ContentView 與 `MapBuildConfirm` 都以 `verticalSizeClass == .compact` 判斷，抽屜不會兩邊都有或都沒有 | 無問題 |
| #1124、#1126 | 決策 387 挑戰劇情：`StoryMoment` 的四種時機、只說今天的段落、讀檔不重說、`sayIfNew` 不會死鎖、6000× 時不漏天；`day(of:)` 擋住指向自己的前置條件；`StoryBeat` 的 precondition 只作用在固定資料 | 無問題 |
| #1129 | 四種預覽的 memo key 改 `commandRevision`、`affordable` 讓錢夠不夠時重算、`patternInTheWayText` 的文字與 xcstrings 一致 | 無問題 |
| #1133 | 審查 F 的修正：3D 限速遇上夜間快轉的 `speedBefore3D`、`collectsStationStamps` | 無問題 |
| #1099 | 決策 375 路塹：凸包方向與 `inside`、`holds` 的正負號一致；`trenchRuns` 的界限；`xs.min()!` 前有 `count >= 3`；串流區塊拿到整個路網的溝；在 `Task.detached` 建 | 無問題 |
| #1101 | 決策 370 淡色：`Map3DUniforms` 沒動；新層 `road = -11` 與 Swift 一致，水面判斷兩邊同樣收窄；`glassMirror` 24 筆對得上；`restyle` 在背景逐頂點 | 無問題 |
| [#1107](https://github.com/a91453/railway-game-ios/pull/1107) | 台北地標：shader 層的範圍、`Map3DMesh` 的 precondition 只吃內部產生的網格、`palette[name]!` 的名稱測試都走到 | G3（P3） |
| #1112 | 斑馬線與箭頭：`crosswalk = 22`、`laneArrows = 23` 與 enum 順序相符，沒有材質位元 | 無問題 |
| #1082、#1096、#1106、#1111 | 只看 Swift：都加在 `Map3DModelPack.init` 最後，既有索引不變；名稱不衝突；海岸套件沒有註冊到 App | 無問題 |
| #1123 | 決策 386 足跡圖塊工具：整份 `taiwan_buildings.pmtiles` 解開，49,196 塊、1,964,945 個足跡，與研究文件一致；樓層來源的數字與決策 389 一致；金門、馬祖沒混進對岸的建物；`test_tiff.py` 通過；出處都有署名 | 無問題（備註見 G7） |
| #1127 | 決策 385：讀檔與建場景在 `Task.detached`；讀不到時退回原畫法；沿街房子的種子取自地圖座標 | 無問題 |
| [#1130](https://github.com/a91453/railway-game-ios/pull/1130) | 決策 385 續：`PlaceGrid.noBuild` 只在 GamePresentation，不進存檔；每個 WorldPop 格的乾地全是不住人用地時人照舊放回；`GameLauncher` 與 `HeadlessGame` 讀檔一致；`testNoOneLivesOnTheAirport` 總人口與工作守恆 | G4、G5（P3） |
| #1132 | 決策 389：`Map3DFootprints.decode` 的 varint 與長度都有界限，壞圖塊跳過，整檔讀壞退回程序房子；mmap、在背景解；座標換算與 `RealWorldFrame` 一致 | 無問題（備註見 G7） |

## 三、修了的

### G1（#1108）高倍速時，背景算好的列車滑行幾乎都白算，主執行緒又重算一次，P2，已修

- **路徑**：打開高鐵示範，用 2D 地圖，調到 6000×。一個 tick（推進加背景滑行）要幾十 ms，`dueTicks` 讓遊戲迴圈一圈跑兩個以上的 tick。`finish(tick n)` 之後立刻 `beginLoopTick()`，第 n+1 個 tick 拿到的還是地圖上一次顯示的 `shownGlide`（S）。`await tick.work()` 讓出主執行緒時，地圖顯示 tick n，`shownGlide` 換成 M_n。tick n+1 的滑行是從 S 算的，地圖手上的卻是 M_n，`memo.from == previous.time` 對不上，於是在主執行緒重算 `TrainMotion`（決策 379 量到 release 平均 29 ms、最長 79 ms）。一圈 k 個 tick 裡有 k−1 個仍在主執行緒算，背景那份每個 tick 白算一次，tick 變慢，一圈的 tick 又更多。決策 379 的改後量測（「地圖跟著推進」最長 1.8 s）和這個一致。
- **回歸測試**：`TrainMotionTests.testTicksBackToBackStillGlideOffTheMainActor`，照真實迴圈的順序：tick 1 完成、tick 2 開始、地圖顯示 tick 1、tick 2 完成、地圖顯示 tick 2；並逐步和地圖自己算的 `TrainMotion` 比 lag 與車頭位置。在 ff8e4dd 的程式上紅：50 步裡背景的結果被用到 **0** 次；修了之後 50 次。
- **修法**：`TrainMotion` 記下它的列車是在哪個 `worldRevision` 的世界看到的（`source`，`seen(at:)` 照抄）。一個 tick 開始時，若上一個 tick 的滑行還沒給地圖顯示，就從那份接著算，否則從地圖顯示的那份；地圖拿滑行時用 `source` 比對，不用時間。滑行的列車位置只取決於前一份的 `samples`，與它被顯示的時間無關，所以結果和地圖自己算的一樣（測試有比）。地圖沒有顯示上一份、背景又算了下一份時，`source` 對不上，照舊在主執行緒算，結果仍對。

### G2（#1093、#1100）重開 App 接續課程時，「改路線設定」的步驟永遠不會自己前進，P2，已修

- **路徑**：玩第 6 關，做到「改路線的營運時間」這一步，App 被系統收掉或玩家關掉。重開後繼續這一局，`GameLauncher` 用 `keepTutorialToResume(atStep:)` 留下接續點，玩家按「繼續教學」回到 lesson.6.hours。打開路線、按「全天營運」：營運時間改了，這一步卻不算完成；後面的班距、停站模式兩步也一樣。第 7 關在 lesson.7.depot 接續，勾選機廠也不會前進。只能等 20 秒的「跳過」一步一步跳。
- **原因**：`Tutorial.init(steps:resumingAt:over:)` 把接續之前各章的快照都設成 `Snapshot.nothing`，它的 `services` 是空的、`serviceDay` 是 `nil`。「有沒有新東西」的目標這樣是對的；「比較前後有沒有改」的目標（`.changeServiceHours`、`.changeHeadway`、`.addPattern`、`.chooseDepot`）找不到基準，永遠是 false。
- **回歸測試**：`LessonGuideTests.testALessonTakenUpAgainMovesOnWithAChangeToALine`：第 6 關在 lesson.6.hours 接續，營運時間、班距、停站模式三步各自前進；第 7 關蓋好機廠後換一個新的 session（像重開 App），在 lesson.7.depot 接續，勾選機廠就前進。在 ff8e4dd 的程式上紅（lesson.6.hours 不算完成，之後停在同一步）；修了之後綠。
- **修法**：接續用 `Snapshot.resumed(over:)`：蓋好的東西仍當作沒有（和 `nothing` 一樣），路線的營運設定取接續當下的世界，改了就算。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| G3 | #1107 | P3 | 串流重建時可能同時出現台北車站的地標和站體套件。「300 m 內的玩家車站讓給地標」只在這一次建置的 region（區塊加 256 m apron）包到地標中心時才成立（`Map3DScene.swift:322,328`、`Map3DTaipeiLandmarks.swift:613`、`Map3DStations.swift:230`、`realReach` 300 m）。路徑：實景地圖上在台北車站旁 256–300 m 蓋一座車站，相機從別處移過去或 coarse 區塊升級時，車站所在區塊單獨重建，region 沒包到地標中心，就建出一棟站體 | 只有實機看得到；修法要動 3D 的建置流程：讓位的判斷改成不看 region（直接算地標中心與 `isClearOfTrack`），並用 `Map3DScene.chunks([key], …)` 與整個場景比的測試 | 3D 城市線（#1107 的作者） |
| G4 | #1130 | P3 | 設定 → 資料來源 →「機場與空地」只說 3D 地圖上那些地方不蓋房子；#1130 之後這份資料也決定實景地圖上那些格沒有人住（人口與工作移到同一個 WorldPop 格的其他格），畫面沒說 | 只是文字，兩種語言各加一句「這些地方也沒有人住」，可在 DataSourceCredits 的測試斷言 | 實景資料線（#1130 的作者） |
| G5 | #1130 | P3 | #1130 之前存的全台存檔：已讀入的 1 km 地塊用舊規則（機場格也有人），之後蓋新車站讀入的鄰塊用新規則；跨兩塊的 WorldPop 格（約 90 m）兩半用不同比例，人可能多算或少算幾十人。同一個存檔內一致、不會當機，任何資料更新都有同樣的效應 | 要修得在 `LandBlocks` 記讀入時的資料版本，成本不划算；寫進決策 385 的已知限制即可 | 實景資料線 |
| G6 | #1093 | P3 | 在 lesson.addTrain 接續時，原本就在路線上的列車被當成新的，這一步直接跳過（不會卡住） | 與 G2 同一個設計（接續時蓋好的都算新的），G2 的修法刻意不改它；跳過一步不影響玩家 | 課程線（決策 376 的作者），有需要再改 |
| G7 | #1123、#1132 | P3 | 備註：(a) 非 OSM 的足跡都標成 Shi 等人（`build_footprint_tiles.py` 的 `0 if dataset == OSM else 1`），金門、馬祖方框沒有依 dataset 欄位驗證過；(b) 臺北建照的提供機關，PMTiles metadata 寫 "Taipei City Construction Management Office"，App 的署名寫「臺北市政府」，應統一成 data.gov.tw 151936 上登記的機關；(c) `Map3DFrontage.prepareNoBuild` 要求多邊形至少一個頂點落在區域 ±0.01° 內，頂點稀疏的大多邊形會漏，對整份資料模擬只有亮島的軍事區（那裡沒有城鎮）會漏 | 都還沒有玩家看得到的錯；(a)、(b) 是出處的寫法 | 實景資料線，下次重建圖塊時一起 |

## 五、full lane 的 `Feature284To286UITests` 第 176 行

- **結論：不是退步，是 Simulator 冷啟動慢造成的偶發**。不需要改 App，也不需要配合哪個 PR 改測試。
- 第 176 行是 `reveal(_:)` 的 `XCTAssertTrue(list.appears(within: 10))`：點 `entry.lines` 之後路線面板的清單（CollectionView）10 秒內沒出現。
- 失敗那次（run 39992945211，main 0149127，lessons job 120549185274）：這個測試是該 job 的第一個；App 啟動時 `map` 到 t = 76 s 才在重試時找到，t = 80.66 s 送出點擊，之後 11 秒沒有清單。同一次 run 的另一個 job 有 3 個「Timed out while launching application」。
- 同一個測試在 1aff6a5（run 39966648040）通過，在之後的 main b6ca9af（run 40020950220，包含 0149127）也通過，那次 t = 29.7 s 就點到 `entry.lines`。
- 1aff6a5..0149127 之間碰到 App 的只有 #1116（站對抽屜在手機橫放時放進 ✓ 膠囊），不改 `entry.lines` 打開什麼，也不改路線面板的 List；#1089 對非課程的世界沒有影響；#1093、#1100 只在路線面板加教學目標與 `.id`；#1110、#1113 不在這段裡。
- 所以沒有用 `only_testing` 重跑。若之後冷啟動又碰到，可選的做法：在 `Feature284To286UITests` 點 `entry.lines` 後，10 秒內沒看到清單就再點一次（只改 UI 測試）。

## 六、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（本 PR） | **VERIFIED**，乾淨 |
| G1、G2 的回歸測試 | **VERIFIED**：兩個都在 ff8e4dd 的程式上紅（G1：50 步裡用到 0 次；G2：lesson.6.hours 不算完成），修了之後綠 |
| `swift test --skip-build --filter "LessonGuideTests\|LessonTests\|TutorialSessionTests\|TutorialTests\|TrainMotionTests\|NightSkipTests"` | **VERIFIED**，156 個，0 失敗 |
| `FastForwardReadsReportTests`、`FrameCostMeterTests` | **VERIFIED**（子代理與本 session），0 失敗 |
| `Map3DFootprintsTests`、`Map3DFrontageTests`、`LandImportTests/testNoOneLivesOnTheAirport`、`test_tiff.py`、`swift-shards-selftest.sh`、shard 涵蓋 | **VERIFIED**（子代理） |
| G3–G7 | **UNVERIFIED**：只讀程式、追了呼叫路徑 |
| 完整測試、iOS 的建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

## 七、五方

- 玩家：兩個 P2 都是玩家會碰到的：6000× 的 2D 地圖仍卡（主執行緒每個 tick 多算一次滑行）、課程中途關掉 App 後第 6、7 關停在原地。下一版之前修好。
- 鐵道迷：真實建物足跡與不住人用地的出處都有署名，G7 的兩處寫法下次重建圖塊時統一。
- 開發：唯一的 GameCore PR（#1117）只把檢查抽出來，行為不變；修正只動 GamePresentation，不動存檔、重播與 golden。
- 美術：無（素材不在範圍；G3 的兩個台北車站要實機看）。
- 音樂：無（#1084、#1085 沒有問題）。
