# 交接：PR #1581–#1610 審查（審查 L3）

派工單 REVIEW-L3（遊戲規劃第 38 任 session_01YGNNumGMsXsPxuQX4jyaCq，2026-10-31，`docs/research/NEXT_PRIORITIES_2026-10-12.md` §23.1 第 6 名）：獨立審查 100.1／100.2 合進 main 的程式 PR，做法同審查 L1（`PR1510_1549_REVIEW_HANDOFF.md`）、L2（`PR1551_1578_REVIEW_HANDOFF.md`）。只找會讓玩家壞掉的：當機、存檔讀不回或舊存檔行為改變、決定性被破壞、主執行緒卡頓、iPhone／iPad 直橫畫面跑版、錢算錯、玩家看的文字違反 `docs/UI_THEME.md`。另外補跑 #1550（新台幣）的 ChallengeReport seed 1。

- Session：session_01YGNNunFaX1uAwwDvFxKbUi，branch `claude/review-l3`。
- 基準：`main` **90f50da**（#1608 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff；#1604 還沒合，讀 `origin/claude/iphone-landscape-fixes`（189ad85）對 main 的 diff。
- 做法：GameCore 的 #1593、#1599 由本 session 自己讀；App／GamePresentation 的 PR 分三組交給三個只讀的子代理（不建置、不改檔），回來的每一項都由本 session 重讀程式路徑，P2 兩項另用 Linux 臨時測試或逐行追蹤確認。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。臨時測試量完刪掉，沒有提交。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

| PR | 內容 | 層 | 點數 |
| --- | --- | --- | --: |
| #1581 | 分區工具：建設工具順序、手機「完成」在「建設」旁、站長指空地、第一棟通知、成就（決策 509） | App＋GamePresentation | 1 |
| #1582 | 車站配線：島式／相對式／待避線一鍵（決策 507） | App＋GamePresentation | 1 |
| #1583 | 地圖上少一點東西：景點依縮放收起、警告合併成徽章（決策 510） | App＋GamePresentation | 1 |
| #1586 | 鋪軌提示：先鋪不接軌道的直線最便宜 | App＋GamePresentation | 1 |
| #1587 | 修 L2-1：選教學前先存目前這局 | GamePresentation | 1 |
| #1588 | 列車運用表入口與拖拉編排（決策 512） | App＋GamePresentation | 1 |
| #1590 | DR3100 柴聯自強號外型與時刻表（決策 511） | GamePresentation＋資料工具 | 1 |
| #1591 | 修 L1-1：拆路時每條公車線只算一次 | GamePresentation | 1 |
| #1592 | 分區圖層說出原因（決策 514） | App＋GamePresentation | 1 |
| #1593 | 阿里山登山軌道與登山車種（決策 515，存檔 77） | **GameCore** | 2 |
| #1594 | 從 3D 按「建設」，完成後回 3D（決策 517） | App＋GamePresentation | 1 |
| #1596 | 車站卡不被切 | App＋GamePresentation | 1 |
| #1597 | 實景地圖的住宅臨路（決策 516） | GamePresentation | 1 |
| #1598 | 貨運月台：新線上直接加（決策 519） | App＋GamePresentation | 1 |
| #1599 | 隧道可到地下 1,024 m、描線端點、被擋時說出原因（決策 513） | **GameCore**（一個常數）＋GamePresentation | 2 |
| #1600 | 「加月台」按鈕文字（決策 507） | App＋GamePresentation | 1 |
| #1604 | （**未合**）iPhone 橫拿：面板標題放到導覽列下、空的小地圖不畫 | App＋GamePresentation | 1 |
| #1606 | CI：rest 分片重排、測試類別的 `pack` 改計算屬性 | CI 腳本＋測試 | 1 |
| #1608 | full lane 的 UI 測試修正 | 只改 UI 測試 | 0 |
| #1610 | 鋪軌拖曳：地面區塊每塊只讀一次（決策 521） | GamePresentation | 1 |

共 20 個 PR（19 個程式 PR、22 點；#1608 只改測試，0 點但順便看了有沒有放鬆斷言）。#1584、#1585、#1589、#1595、#1601（未合）、#1602、#1603、#1605、#1607（未合）、#1609（未合）不在派工範圍或只改文件，沒有審。

派工單寫「#1590 改了 GameCore」：實際上 #1590（DR3100）沒有動 `Sources/GameCore`，這段期間動 GameCore 的是 #1593、#1599 與 #1550（新台幣，L1 之後另有獨立審查）。#1590 照 GamePresentation 審。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **2**：L3-1、L3-2 |
| P3（記著） | **9**：L3-3～L3-11 |

100.2 可以照計畫發；兩個 P2 都不會當機、不會讓存檔讀不回，L3-1 會掉最多 15 分鐘的進度，排在 100.2 之後的第一個版本。

### GameCore：#1593（登山軌道，存檔 77）

- **存檔**：`TrackEdge.mountain` 只在 `true` 時寫 `"mountain": true`（`RailwayNetwork.swift:621`），讀時沒有就是 `false`（`:545`），所以沒有登山軌道的世界寫出來的 JSON 和 76 版一樣；`SaveFixtures` 沒改舊檔，加了 `v77-mountain-track.json`；`currentVersion` 77，舊版本讀到 77 會說存檔較新。讀檔時的驗證改成看每段自己的上限（`GameWorld.swift:5496` `edge.maximumGrade`），76 版以前的軌道一律 40‰，行為不變。
- **決定性與重播**：新車種 `ALISHAN` 加在 `TrainTypeCatalog.builtIn` 最後，既有車種的 `row` 不變；車種用代碼存，不用索引。沒有任何 GamePresentation／GameCore 的路徑照 `TrainType.offered` 的位置或亂數挑車種（只有 `LineStaffing.swift:63` 取 `first`，第一個不變）。`TrainLength.isCarPitch` 多收 13.0 m 一種長度，只放寬。golden、replay 沒有變動。
- **指令紀錄**：`PlayerCommand.TrackStretch.mountain` 用 `Bool?` 讀寫，舊紀錄沒有這個欄位讀成 `false`，新紀錄只在 `true` 時寫（`PlayerCommand.swift:384`、`:468`、`:604`）；`MountainTraceTests` 有來回測試。
- **所有造邊的路徑**：GameCore 只有兩處 `addEdge`：`buildTrackEdge`（帶 `mountain`）與 `splitTrackEdge`（沿用原邊的 `mountain` 與上限，`GameWorld.swift:631`、`:674`）。沒有其他地方新建或改寫邊，所以不會有登山邊在別的指令後變回一般邊。
- **限速**：`MountainTrack.speed(grade:)` 整數運算，有溢位保護，下限 `CurveSpeedLimit.lowest`；限速在建邊與讀檔時算，不存。
- **已知缺口**（決策 515「缺口與下一步」第 2 項，§23.1 第 9 名 ALISHAN2 會做）：`placeTrain`、接續運轉不檢查；線路之後改走登山軌道時線上的一般車不會被拉下來。本輪不重複列。
- 新發現的只有 L3-3（自動補車的預設車種）。

### GameCore：#1599（`RailwayNetwork.heightRange` 下限 −64 m → −1,024 m）

- 只放寬範圍：舊存檔的每個節點都還在範圍內，驗證不會多擋；新存檔可以有更深的節點，舊版本會在驗證時拒絕，但這段期間存檔版本另有升（76、77），舊版本本來就讀不了。
- 用到 `heightRange` 的只有 `GameWorld.isInWorld`（`GameWorld.swift:983`）與 `TrackGeometryProblem` 的說明文字；`NetworkBuilding.heightRange`（玩家手動調高度的 Stepper）仍是 ±64 m，玩家手動鋪不到 −1,024 m，只有描線會。`TrackGeometry.maximumRise`（一段 128 m）沒動，所以單段的坡度與造價計算不受影響。

### App／GamePresentation 的重點（看過、沒問題的）

- **#1582**（配線）：✓ 鈕按下時才從目前的世界規劃，整組是一個 `performEdit`（全有或全無、一次復原、一筆紀錄）；顯示的價格是同一個指令在複本上跑出來的，和實際扣的一樣；沒有新的存檔欄位。
- **#1588**（運用表拖拉）：新的 `Edit` 都經過 `perform`，放開時再對目前的世界檢查一次；VoiceOver 動作沒有預覽也會被 GameCore 擋（`trainServiceActive`／`trainNotAtFirstStop`）。
- **#1590**（DR3100）：時刻表空的或讀不到時 `dr3100` 是 nil，不會當；JSON 4 班 × 50 站、時間遞增、不跨午夜（跨午夜的 `+86_400` 也有處理）；資料出處是台鐵開放資料（政府資料開放授權條款第 1 版），`DataSourceCredits` 已列；`project.pbxproj` 有加進 Resources。
- **#1591**（修 L1-1）：只重算畫的路經過拆除段 2 格內的公車線，在 `trying` 複本上算，不動共用的公車路網；L1-1 關掉了。
- **#1592**（分區圖層）：`ZoningOutlook` 和 GameCore 的 `spread` 同一套條件（800 m、`<`、水與陡坡除外）；`CityMap` 仍在背景建。
- **#1606**：前後比對分片清單，沒有類別漏掉或重複；`swift-shards-selftest.sh` 本機 VERIFIED。`Map3DModelPack.standard` 是 `static let`，計算屬性只複製共用陣列的 struct，不會每次重建。
- **#1608**：每一處都是重試或失敗前再讀一次同一個條件，斷言沒有放鬆。
- **#1610**：快取以 `RealWorldFrame` 為鍵、換 frame 清掉、跟著 `HeightGrid` 實例走；最多 4,096 塊（約 2.4 MB）；`NSLock` 保護、鎖外計算、frame 沒變才寫回；結果和不快取的路徑相同（同樣排序、讀不到的塊同樣略過）。
- **#1604**（未合）：只在 `verticalSizeClass == .compact` 改擺法，iPad 與 iPhone 直拿照舊；`navigationTitle` 保留，返回鍵文字正常；標題列有 header 特性，佔位元件對 VoiceOver 隱藏；小地圖的資料仍在 `.task` 算，不會卡在隱藏。
- 玩家看的文字（#1581、#1583、#1586、#1593、#1598、#1599 的新句子）：兩種語言都只說玩家能做什麼，沒有內部名稱或設計理由，符合 UI_THEME。

## 二、發現

### L3-1（P2）#1587 只修了站長那條路：目標面板的「開始」還是不先存目前這局

- **位置**：`RailwayGameApp/Views/GoalsPanel.swift:699`（`launcher.startLesson(lesson)`）→ `Sources/GamePresentation/GameLauncher.swift:1123`（`startLesson`）→ `begin(_:keepingAutosave: true)`（`:1660`）。#1587 只在 `chooseFirstLineGuide`（`:225` 起）加了 `autosaveCurrentGame(refreshing: false)`。
- **問題**：和 L2-1 同一件事。`begin` 的 `keepingAutosave` 只把磁碟上已有的自動存檔改名保留，沒有先寫正在玩的這局；自動存檔每 15 分鐘一次。L2-1 的建議修法已點名這條路，#1587 沒有一起修。
- **什麼時候會碰到**：自由遊戲裡打開「目標」，點任何一關的「開始」。上次自動存檔之後做的事都沒了；還沒到第一次自動存檔的新局整局不見。
- **驗證**（Linux，臨時測試，量完刪掉）：照 `FirstLineGuideTests.testTheTutorialKeepsTheGameBeingPlayed` 一樣開新局、鋪一段軌道、加一個月台（`stations.count == 1`），改呼叫 `launcher.startLesson(Lesson.all[0])`：`session.lesson` 是 `lesson.1`，存檔資料夾裡不是關卡的局是 **`[]`**（同一個設定走站長那條路是 `[1]`）。**VERIFIED**。
- **建議修法**：把守門移進 `startLesson`：`guard session == nil || autosaveCurrentGame(refreshing: false) else { return }`，`chooseFirstLineGuide` 的那行拿掉（它會經過 `startTutorial` → `startLesson`）。關卡結果卡的「下一關」「再玩一次」（`ContentView.swift:213`、`:217`）也會走到，那時的局是關卡，存了無妨。加一個 Linux 測試：上面的設定走 `startLesson`，存檔裡有那局。

### L3-2（P2）#1594：從 3D 進來鋪軌時按「擴大地圖」，畫面跳回 3D，看不到可買的地

- **位置**：`RailwayGameApp/Views/ContentView.swift:1340`（`Map3DShownWatch` 的 `onChange(of: session.tool)`）→ `Sources/GamePresentation/Map3DBuildReturn.swift:75`（`toolChanged`：工具一變成 `.select` 就當作「建設結束」，回傳原本的 3D 視角）。
- **問題**：`GameSession.startChoosingMapTile()`（`Sources/GamePresentation/MapExpansionSession.swift:116`）也是先 `selectTool(.select)`，再設 `isChoosingMapTile = true`、暫停遊戲。建造卡的「擴大地圖」（`MapBuildConfirm.swift:180`，決策 336）、橫幅的「擴大地圖」（`ControlPanel.swift:1181`）、點地圖鎖（`MapExpansionSession.swift:302`）都會走到。
- **什麼時候會碰到**：要買地才能鋪的地圖（分塊買地）。在 3D 按「建設」，描線拉出自己的地，卡片出現「擴大地圖」，按下去：3D 地圖照原視角重新打開，2D 底下停在選地模式、遊戲暫停；玩家要自己關掉 3D 才看得到可買的地塊。
- **驗證**：逐行追蹤（`selectTool(.select)` 的呼叫者只有「完成」、Dock 的「建設」、`startChoosingMapTile` 與一個 UI 測試入口），沒有在 Simulator 看過（**UNVERIFIED**，照派工單不跑 iOS workflow）。
- **建議修法**：`toolChanged` 多收一個 `choosingMapTile: Bool`（`onChange` 觸發時 `session.isChoosingMapTile` 已經是 true），是 true 時 `forget()`、回傳 nil。`Map3DBuildReturnTests` 加一例：`leftForBuilding` → `toolChanged(.network)` → `toolChanged(.select, choosingMapTile: true)` 得到 nil、之後不再回 3D。

### L3-3（P3）#1593：登山路線按「補列車」用預設車種會被拒；「沿真實鐵路鋪示範」的阿里山線沒有車

- **位置**：`Sources/GamePresentation/LineStaffing.swift:63`（`lineStaffingPlan` 沒選車種時用標準車）；`Sources/GamePresentation/DemoRealLines.swift:588`（`addDemoLine` 用 `type: nil` 補車，`try?` 吞掉錯誤）。
- **問題**：線路經過登山軌道時，GameCore 只收登山車（`GameWorld.swift:2398`）。補列車面板預設車種是標準車，所以第一次按下去是失敗訊息「這條路線有登山軌道……請改用登山車種」；玩家要自己在面板改選「阿里山林鐵登山列車」才行。示範功能（鋪畫面內的真實路線，`DemoRealLines`）描阿里山線時會鋪出登山軌道（`afr_sched` 在 `mountainSystems`），之後用標準車補車被拒、錯誤被吞，那條線一班車都沒有，訊息不會說。
- **驗證**（Linux，臨時測試）：8 段 `mountain: true` 的平直軌道、兩站一條線：`lineRunsOnMountainTrack == true`、`lineStaffingPlan(...).type == nil`；`staffSelectedLine(headway: 10)` 得到 `.failure` 與上面那句、線上 0 班；`staffSelectedLine(headway: 10, type: .alishan, cars: 1)` 成功、1 班。示範那條路是讀程式推的，沒有實際跑真實資料的示範。
- **建議修法**：`lineStaffingPlan` 在沒選車種、`lineRunsOnMountainTrack` 為 true 時預設 `.alishan`（補列車面板的預設也跟著變）；示範的阿里山線就會有車。

### L3-4（P3）#1587：自動存檔失敗時，站長的教學提議不會再出現

- **位置**：`Sources/GamePresentation/GameLauncher.swift:225-235`。
- **問題**：`preferences.firstLineGuide = .tutorial` 在自動存檔之前就寫下。存檔失敗時留在這局（對的），但 `FirstLineGuide.offers` 要 `choice == nil`、步驟提示要 `.selfGuided`，兩個都不會回來。
- **建議**：存檔成功後才寫偏好，或失敗時不寫。

### L3-5（P3）#1588：把時刻表的格子往前拖過「現在」，列車會等一整個週期，預覽只寫時刻

- **位置**：`Sources/GamePresentation/TrainRosterDrag.swift:149-154`（算出下一個週期）、`:119`（文字只用 `clockText`）。
- **問題**：例如現在 08:20、首班 08:30、往前拖 15 分：新的首班 08:15 已過，`startTrainService` 會等下一個週期。預覽算得對，但只寫「−15 分 · 08:15 開」，玩家看不出是隔一個週期（可能是隔天）。讀程式推的，沒有量。
- **建議**：`cycle > 0` 時加「隔天」或「N 小時後」，或像 `notAtFirstStop` 那樣不收這種拖法。

### L3-6（P3）#1588：「編排」裡的「復原」是整局的復原

- **位置**：`RailwayGameApp/Views/TrainRosterView.swift:113`（`session.undo()`，只在 `!session.canUndo` 時停用）。
- **問題**：還沒拖過任何東西就按，或拖一次按兩次，會復原打開運用表之前做的事（鋪軌、買車、建線）。在以路線篩選時可能把正在看的線復原掉，清單變空；不會當，只有狀態訊息說復原了什麼。
- **建議**：數運用表自己的編輯次數，大於 0 才能按。

### L3-7（P3）#1588：拖到一半清單變了，放開時照位置重找目標

- **位置**：`RailwayGameApp/Views/TrainRosterView.swift:586`、`:652`（`onEnded` 用最新的 `rows[index]`／`box(drag.startLocation)` 重找）。
- **問題**：運用表每秒重算；拖曳途中上面多一列（買了車、某車今天第一趟出發），放開時可能落在和高亮不同的線上；拿著的預定格途中變成行駛中的班次時，放開什麼都不做。少見。
- **建議**：放開時用 `@GestureState` 裡記下的線 ID／列車 ID，不要重新照位置找。

### L3-8（P3）#1581：沒有城市建築的世界，分區蓋起來不會有「第一棟」通知、成就不計

- **位置**：`Sources/GamePresentation/ZoningSession.swift:141`、`:158`（`firstBuilt` 只看 `world.buildings`）；`Achievements.swift:145-147`。
- **問題**：`world.buildings` 只在 `cityBuildings` 開著時有東西（只有 `NewGame` 會打開）。土地需求開著、城市建築關著的世界（Phase 6c-1 以前的舊存檔等），GameCore 照樣在分區上長出土地，#1592 的圖層也說「會蓋」，但通知不來、「都市計畫」成就不計。讀程式確認；有多少玩家存檔是這種狀態沒有查。
- **建議**：也接受土地格：`world.land.cell(row:column:)?.use` 和分區用途相同就算。

### L3-9（P3）#1583：分塊買地的地圖上，有些景點的「沒有車站」提醒哪裡都看不到

- **位置**：`RailwayGameApp/Views/MapAlertBubbles.swift:186-188`（`markedSights` 用 `MapAttractionMarks.marks(...)` 的清單）；`RailwayGameApp/Views/MapAttractionMarks.swift:39`。
- **問題**：泡泡把「地圖上已有景點標記」的景點提醒拿掉，但標記本身在蓋到地價（`coversPrice`）或正在選地（`sightMarksTakeTouches` 為 false）時不畫，這些景點的提醒就既不是泡泡、也不是標記、也不在徽章裡。只在分塊買地的地圖。
- **建議**：`markedSights` 套用和標記畫面一樣的地價與選地過濾後再算。

### L3-10（P3）#1592：開關城市需求後，分區標記要等下一次土地或車站變動才更新

- **位置**：`RailwayGameApp/Views/MapView.swift:2895`（`CityMapKey`）。
- **問題**：分區標記現在看 `world.cityDemand` 有沒有開，但重建地圖的鍵沒有它。很少碰到。
- **建議**：鍵加 `cityDemand != nil`。

### L3-11（P3）#1582、#1583：每幀多做的掃描（沒有量）

- **位置**：#1582 `Sources/GamePresentation/StationLayout.swift:182`、`:189-192`、`:214-219`、`:228`（車站模式下 `fits()` → `networkPlatformBeside` → 兩次 `trackBeside`，每次對全部 edge 線性找 `trackEdgePoint`，一次 body 約 7 次，在記憶檢查之前）；#1583 `RailwayGameApp/Views/MapAttractionMarks.swift:101` 與 `MapAlertBubbles.arranged`（每個可點的景點標記每幀 `trackEdgePoint`；`arranged` 一幀約算 5 次，含 `SightMarks.shown` 的 O(k²)）。
- **問題**：現在的規模（畫面內約 30 個景點、1–2 千段軌道）估計每幀幾毫秒以內，不是卡死；HANDOFF 開頭記著 full lane 有原因不明的主執行緒停頓，值得量一次。
- **建議**：先在 Linux 量（實景示範、約 1,000 段軌道、中等縮放）；慢的話 `networkPlatformBeside` 以（stretch, `commandRevision`）記憶，`arranged` 以相機與泡泡的鍵快取。

### 沒列的

- #1581 站長指空地後分區工具預設住宅、而住宅需求第 1 天就轉負：決策 514「下一步」第 1 項已記，ZONE3（#1609）正在做。
- #1599 `TrackRise` 合併樣本時，距 0 不到 0.5 單位（1 cm 以下）的 level 端點會取代 0 的樣本：高度照樣內插，看不出差別。
- #1604 小地圖在「看得到整張地圖」的縮放附近會出現又消失：只影響外觀，角落按鈕不會移動。

## 三、#1550 的 ChallengeReport seed 1

（待補：見下次提交）

## 四、驗證

Linux、Swift 6.4.0、`main` 90f50da：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（通過；臨時測試刪掉後再建一次也通過）。
- `swift test --skip-build --filter`：（待補）
- `.github/scripts/swift-shards-selftest.sh`：**VERIFIED**（通過）。
- L3-1、L3-3 的重現：臨時測試量的，量完刪掉，沒有提交。
- L3-2 與各項版面：**UNVERIFIED**（照派工單不跑 iOS workflow，沒有 Simulator 與實機）。

## 五、下一步

- L3-1 交給規劃派人修（100.2 之後第一版）；修好前不要在說明裡寫「開始關卡不會影響目前這局」。和 REV-P3（§23.1 第 11 名）一起做也可以，改的是同一個檔案的一行。
- L3-2 交給規劃派人修（同一版）；修法與測試都在 GamePresentation（`Map3DBuildReturn`），App 只多傳一個值。
- L3-3 併進 ALISHAN2（§23.1 第 9 名）一起做，它本來就要動登山車的指派。
- L3-4～L3-11 記著，有玩家回報或有空的 session 再處理；L3-11 可以交給查主執行緒停頓的工作順便量。
- 下一輪審查從 #1611 起數（#1604 若在這之後才合，下一輪不用再看）。
