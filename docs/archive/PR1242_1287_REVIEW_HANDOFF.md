# 交接：PR #1242–#1287 審查 J 組

派工單 R（遊戲規劃 session_01TH2DNkW2meh3EZJ1vxBczC，2026-10-26）：審查 main 上已合併的程式 PR，從 #1242 起，分三段，每段一個 PR。這份檔第 1 段建立，第 2、3 段在同一個檔加自己那一段（從最新的 main 開 branch，照下面同一張分段表）。

- 分段基準：`main` **57dc35d**（#1287 合併後）。
- 點數照 HANDOFF 第 1 節「多久審查一次」：GameCore 2 點；GamePresentation、App、CI 腳本、會產生打包資料的 `tools/`、`Web/` 的程式 1 點；只改文件、只加模型或素材、只改測試 0 點。
- 上一輪：[PR1189_1241](PR1189_1241_REVIEW_HANDOFF.md)（審查 I）。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、分段表（第 2、3 段照這張做）

範圍是 #1242 起已合併的程式 PR，**加上四個編號較小、審查 I 沒看的**：#1232、#1239（HANDOFF 寫明合併後算進下一輪）與 #1229、#1230（都在審查 I 的基準 2ae0f7c 之後才合併，審查 I 的交接沒有列）。`git log --first-parent 2ae0f7c..57dc35d` 裡編號小於 1242 的合併只有這四個。

| 段 | PR（照編號） | 個數 | 點數 |
| --- | --- | --: | --: |
| **1** | #1229、#1230、**#1232**（GameCore）、**#1239**（GameCore）、#1244、#1245、#1246、#1247、#1249、#1252、#1253 | 11 | 13 |
| **2** | #1254、#1256、#1257、#1258、#1259、#1260、#1261、#1262、#1263、#1265、#1266、**#1268**（GameCore，`BusRoute.swift`） | 12 | 13 |
| **3** | #1270、#1271、#1272、#1273、#1275、#1277、#1278、#1280、#1283、#1284、#1285、#1287 | 12 | 12 |
| 合計 | | **35** | **38** |

0 點（不看，14 個）：只改文件 #1242、#1269（建模手冊）、#1243、#1248、#1250、#1251、#1264、#1274、#1279、#1288、#1289；只改 UI 測試 #1267、#1276、#1286。#1281、#1282 沒有合併。

判斷依據：#1229、#1230、#1256 雖然是 Codex 的車輛，但改了 `Map3DTrainSets.swift`／`Map3DModels.swift`，遊戲畫的車跟著換，算程式（同審查 I 算 #1201、#1227）；它們 `tools/` 底下的產生器只渲染、檢查，App 不打包輸出，不另算。

**第 3 段注意**：公車道路與真站牌在主執行緒讀的問題，派工單 E（session_01MdqoSy58YkbJUqAMxXXoCk）正在修（`BusRoadNetwork.swift`、`BusStopLabels.swift`、`BusRouteEditor.swift`、`GameSession.swift`）。不要重報，也不要改這幾個檔。

最後一段另外要做：在 HANDOFF §1「多久審查一次」把「上一輪」改成審查 J、寫下一輪從哪一號起數；HANDOFF 審查清單（約 1485 行，「PR #1189–#1241 那一輪」那段之後）加這一輪；`docs/OVERVIEW.md` 的 archive 表加這個檔。

## 第 1 段（#1229–#1253）

Session：session_01KA4P39dCU3gKAqH2vLPej8，branch `claude/segment-1-dev-494qsx`（系統指定的開發 branch，取代派工單的 `claudepro/review-j-1`）。

### 一、結論

| 項目 | 數量 |
| --- | --- |
| 程式 PR | 11 個、13 點（GameCore #1232、#1239 各 2 點） |
| 新發現 | **1 個**，P2 |
| 已修 | **1 個**：J1（附回歸測試） |
| 沒修，交出去 | 0 個 |

兩個 GameCore PR 由本 session 自己讀（合併前另有獨立審查，見審查 I 的交接）。

### 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1229 | EMU3000 原生模型：`Map3DEMU3000.unit(at:count:)` 12 節照真實編組、其他節數頭尾與第 3 節集電弓；`modelIndex` 的 emu3000 分支與 `gameModels` 的名稱一一對得上（8 種車 × 近遠）；尾車繞垂直軸轉、法線一起轉；`nearOnly` 加 emu3000 | 無問題（`ownLengths` 造成的長度問題由 #1254 修，在第 2 段） |
| #1230 | TEMU1000（太魯閣）原生八節：`fixedCars: 8`、集電弓在 2、5；兩端車燈白前紅後；模型包加 `Map3DTEMU1000` 各單元與整列 | 無問題（遠景版由 #1275 補，在第 3 段） |
| #1232 | 學校、醫院、夜市，存檔 74：`PlacedBuildingKind` 三種的大小、用途（學校醫院 `.civic`）、層數、0 容量、兩種樣子；`isSight` 取代 `== .temple` 的四處（驗證、顧客、`companySights`、夜裡記遊客）；同種才分遊客；`PassengerPlanCache` 的 `temples` 含夜市，蓋或賣會重算；地價 `civicPremium`（400 m、`<` 判斷，學校 900、醫院 500）；`homeGrowth` 的上限與餘數分配（每一輪不是分完就是多填滿一格，會結束；`room < base` 的格子照沒有學校時一樣只損失 `base − room`）；`civicGrowthWeights` 滿的格子不加權；賣 0 容量建物時地價不算它自己（`var without = self`，只移除該建物）；`SavedGame` 74 的說明與遷移；fixture `v74-school-hospital-night-market.json`；App 的圖示、地圖符號、`effectText` 兩種語言 | **J1（P2），已修**（成就把夜市、廟算成三種事業之一） |
| #1239 | 捷運可以收購：`LineAcquisition.Tier` 三種的單價（支線 $10,000、輕軌 $70、捷運 $100）；`maximumDailyRiders` 20 萬 → 200 萬（乘以 $10,000 的分是 2e12，不溢位；公車收購也用這個上限，仍是支線單價，#1220 起如此）；`RealBranchLine.id` 與報價迴圈都經 `dataSystem(of:)`（`mrt` → `trtc`），買過的判斷一致；`leavesALine` 不付北投、七張的旅客；`trainType` 台北捷運 `.a`；`RealLineLayout.metro` 150 m 的待避線與月台區；記錄時 `tier ?? .branch`（舊紀錄的輕軌照當時的價錢重播）；`extract_metro_runs.py` 的 `prompt="spare"` | 無問題 |
| #1244 | 決策 411：18 個 campaign 分片重排、`CLASS_WEIGHTS` | 無問題：目前 main 的 18 個分片共 106 個類別，沒有重複，每個都找得到 |
| #1245 | 長編組車尾：`TrainCars.cars` 的縮放（`min(1, max(車身+兩節, 20 m × 節數) / 實長)`）、`backward` 改用最後 20 m（比 20 m 短時用整段，`Trail.point(at:)` 夾在 0） | 無問題 |
| #1246 | 決策 412：iOS PR 閘門 7 支減到 4 支，三支移到 full lane（它們的邏輯有 Linux 測試） | 無問題 |
| #1247 | 審查 I 自己的修正（I1–I6）：`map3DLookoutStop` 的停留上限與單位（都是 world units）、`Signature.Line.isHighSpeed`、色帶在護欄內、致謝、匯出類型、轉向重排 | 無問題 |
| #1249 | 決策 396 續二：成就清單用 Game Center 的 38 張圖，`imageName` 與 asset catalog 一一對得上（`testEachHasItsBadgeInTheAssetCatalog`），未解鎖的半透明 | 無問題（J1 是 #1232 碰到這裡的計數） |
| #1252 | wasm-probe 只在 PR 跑；release-archive 的 PR 只看 App 的進入點與 entitlements | 無問題。`RailwayGameApp/App/` 其他檔都沒有 Release 才編的分支（`#if DEBUG` 只在 `RailwayGameApp.swift` 與 `FeatureUITestWorld.swift`），nightly 仍會跑完整的 archive |
| #1253 | 決策 413：push 跑自己的 tier、每晚 01:37 跑完整的 `ci.yml`；`head_full_run` 認 `Swift 6.4 (Linux) / rest` 這個 job 名稱（#1258 之後 ci.yml 的 job 名稱仍是 `Swift 6.4 (Linux) / ${{ matrix.shard }}`）；schedule 的 concurrency 一個 commit 一組、不取消；gate 對 schedule 與手動同樣處理 | 無問題 |

### 三、修了的

#### J1（#1232 × #1249）廟、夜市加一間飯店就拿到「企業集團」，P2，已修

- **路徑**：`AchievementFacts.init(world:)` 用 `kind.isSubsidiary` 數事業（`Achievements.swift` 約 129 行）。決策 361 起廟是事業，#1232 起夜市也是；「企業集團」只看 `subsidiaryKinds` 到 3，所以廟 + 夜市 + 飯店就達成。「多角經營」也一樣，只蓋一間廟或夜市就達成。
- **玩家看到**：成就寫「百貨公司、飯店、遊樂園各一間」「開第一間百貨公司、飯店或遊樂園」，沒蓋就解鎖了。成就解鎖後留在裝置上，也報給 Game Center（`GameCenterLink.swift`），收不回來。
- **回歸測試**：`AchievementsTests.testATempleOrANightMarketIsNotOneOfTheNamedBusinesses`：管理模式的空地蓋廟與夜市，「多角經營」不該達成；再蓋飯店，「多角經營」達成、「企業集團」不該達成；再蓋百貨公司與遊樂園才達成。在 57dc35d 的原始碼上紅。
- **修法**：「多角經營」與「企業集團」只數百貨公司、飯店、遊樂園。「生意興隆」（一間事業開業以來賺 $1,000,000）仍算所有事業，廟與夜市也是事業。
- commit：本段 PR 的第一個 commit（`claude/segment-1-dev-494qsx`）。

### 四、沒修、交出去的

無。

### 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（這個 branch，Linux，官方 Swift 6.4.0 `/opt/swift`） | **VERIFIED**，乾淨，0 個 warning |
| J1 的回歸測試 | **VERIFIED**：`Achievements.swift` 換回 57dc35d 的版本時紅（「多角經營」「企業集團」兩個斷言都失敗），修了之後綠 |
| `swift test --skip-build --filter AchievementsTests` | **VERIFIED**，25 個，0 失敗 |
| `.github/scripts/swift-shards-selftest.sh`（57dc35d） | **VERIFIED**，201 項 ok，通過 |
| 18 個 campaign 分片的類別不重複、都存在（57dc35d） | **VERIFIED**，106 個 |
| 其他 PR | 只讀程式、追了呼叫路徑 |
| 完整測試、iOS 建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

### 六、五方

- 玩家：J1 讓成就不再沒做到就解鎖；其他 PR 沒有會丟存檔、當掉或卡住的問題。
- 鐵道迷：#1239 捷運的單價、北投站的旅客不重複付錢，與真實資料一致；EMU3000、太魯閣的編組照真車。
- 開發：兩個 GameCore PR 沒有問題；修正只動 GamePresentation 一個檔，不動存檔、重播與 golden。
- 美術：無（模型由各自的 PR 照 art-style 檢查）。
- 音樂：無。

## 第 2 段（#1254–#1268）

Session：session_01KA4P39dCU3gKAqH2vLPej8，branch `claude/segment-1-dev-494qsx`（#1290 合併後，從 main **ddcd8b9** 重開，同一個名字）。

派工單 E（session_01MdqoSy58YkbJUqAMxXXoCk）正在改 `BusRoadNetwork.swift`、`BusStopLabels.swift`、`BusRouteEditor.swift`、`GameSession.swift`，這一段沒有動它們。#1260、#1263、#1268 碰到這幾個檔的部分照樣讀了，沒有發現要交給 E 的新問題。公車道路與真站牌在主執行緒讀，是 E 正在修的那一件，不重報。

### 一、結論

| 項目 | 數量 |
| --- | --- |
| 程式 PR | 12 個、13 點（GameCore #1268 2 點） |
| 新發現 | **0 個** |
| 已修 | 0 個 |
| 沒修，交出去 | 0 個 |

GameCore 的 #1268 由本 session 自己讀。

### 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1254 | `TrainCars.cars`：實長只超過上限（`max(車身 + 兩節, 20 m × 節數)`）半節以內時照自己的長度畫，超過才縮到上限；12 節 EMU3000 245.7 m 不再擠進 240 m | 無問題。上限在 20 m × 節數這一邊時是常數，同一列車不會在兩種畫法之間跳 |
| #1256 | E500 原生模型（`Map3DE500`）：近景與遠景兩種；`e500Hauled` 換掉 E500CK、MINGRI、STAR 三列的車頭，客車、尾燈、`ownLengths` 照舊；三組加進 `nearOnly`，500 m 外換遠景組、900 m 外不畫；`reach(of:)` 與 `pack.model(_:forType:count:at:)` 的對應有測試 | 無問題。遠景組的客車與近景同一個模型，只換車頭（三角形預算由測試管） |
| #1257 | `full_lane_watch.py`：從失敗 job 的 log 讀 XCTest 的 `error: -[類別 測試]`，同樣幾個 job 紅、多一個測試紅也留言；任何一份 log 讀不到就退回只看 job；授權標頭不跟著轉址送出；timeout 5 → 10 分。六個 UI 測試的穩定性修正（逐字打、拖曳避開滑桿與按鈕、示範地圖讀取時容忍 UI 查詢逾時） | 無問題。`ios-build.yml` 沒有用 retry，log 裡的 `error:` 行就是真的失敗；測試名稱只有 `\w`，不會帶出 at 號；UI 測試的閘門清單沒有動 |
| #1258 | 決策 411 共用建置：`swift-build` job 建一次、`pack`（tar 保留 `.build/debug` 連結，gzip -1）、artifact 不再壓、留 1 天；分片 `unpack` 後 `swift test --skip-build`；gate 多看 `BUILD`（需要時要 success，不需要時要 skipped）；`superseded` 與 gate 的 `needs` 加上建置；selftest 新增 8 項 | 無問題。建置失敗時分片因 `needs` 被略過，gate 因 `BUILD` 紅；`unpack` 不蓋掉已有的 `.build`。只重跑失敗的 job 時，隔天以後 artifact 已過期，要整輪重跑，決策 411 寫明了 |
| #1259 | N700S-G 後半列反向：`modelIndex` 的 `carIndex * 2 >= count` 用 `carBack`、`pantoBack`，沒有這兩個模型的車組退回原來的；近景、遠景都加；`Map3DTrainSetTests` 的名稱清單加上兩個新名字 | 無問題 |
| #1260 | 高鐵、宜蘭線示範在 `Task.detached` 裡建好世界後，連同全部土地的道路一起讀（`GameLauncher.readingRoads`，叫用 `GameSession.readRoads` 的靜態函式），`begin` 不再在主執行緒讀約 2,500 塊；`baseMap` 是 `nil` 時照舊在 `begin` 讀 | 無問題。道路寫在世界裡，存檔的第一個世界就有（測試看 `commandLog.start`） |
| #1261 | 決策 414 放空模式：`AmbientDirector`（種子 SplitMix、`[列車, 列車, 車站, 列車, 路線]` 輪流、最近 5 個不重複、權重都 > 0、列車 60–120 s、其他 20–30 s、3D 每隔一班列車換一個視角）；`Cast` 只取有位置的列車、非機廠的車站、兩站以上的路線；`region(of:)`；`CameraRequest.region`；App 端開始時暫停的遊戲照跑、結束時暫停回去，開面板或教學就結束，不在教學裡開；`ambientHidden` 收起按鈕；`MotionRule.ambientCut` 只淡入淡出 | 無問題。每秒在主執行緒建一次 `Cast`，每站一次 `waitingPassengers(at:)`，量很小 |
| #1262 | 決策 415「這版新增」卡：`whatsNewSeen` 是可選欄位，舊的偏好設定讀得回來；新安裝（沒有偏好檔）不顯示；更新後顯示一次，關掉（`onDismiss`，滑掉也算）才記住；說明頁的列與搜尋；其他寫偏好檔的 UI 測試路徑都寫了 `whatsNewSeen`，不會被卡片擋住（只有 `-ui-test-updated` 故意不寫） | 無問題。玩家看的文字兩種語言都有，只寫功能，沒有程式名稱 |
| #1263 | 10i-5 自己畫公車路線：`ConstructionTool.bus`（會暫停）、`PlayerCommand.Edit` 新增 5 種（Codable，舊紀錄照讀）、`BusRouteEdits.revise` 在複本上做完才寫回（全有或全無）、預覽在 `pricingCopy` 上跑 GameCore 自己的指令、教學與課程裡不開、`BusRoadPath` 與 GameCore 的搜尋同一套順序；App 的工具列、確認鈕、車站面板的路線卡、地圖畫法 | 無問題。現在的 `createBusRoute`／`reviseBusRoute` 也記下 `legMetres`（決策 424），重播用同一個長度。`BusRouteEditor.swift`、`GameSession.swift` 的部分只讀；預覽每點一次在主執行緒找路，是 E 的那一件 |
| #1265 | 10i-3 真實公車資料：`RealBuses` 索引（schema、scale > 0、bounds 的順序）與各縣市檔（差分座標、至少兩點、站牌名與距離數量相同、站牌不倒退且不超過線長、班距 1 分到 `BusService.longestHeadway`）；`build_real_buses.py` 的估計班距（市 30 分、縣 60 分）、簡化、站牌投影、TDX 的三種找站方式；致謝加 TDX 與政府資料開放授權 | 無問題。臺北市 989 條裡 448 條是估計班距，README 寫了原因（TDX 的 `Schedule` 只有 451 組路線加方向）。這些檔在哪裡讀是 `BusStopLabels.swift`，E 的範圍 |
| #1266 | 決策 416 路網分析：路線（人次、單程長度，非環狀線取去程的腿，與 GameCore `Operations` 同一個算法；每公里人次，0.05 km 以下不算；尖峰列車）、最擠區間（沒有列車的區間 `ratio` 是 ∞，排最前面）、未滿足需求（等半小時以上、流失、沒有路線連的兩站，網路模式用聯集與步行轉乘）；`Task.detached` 算，不在主執行緒；說明頁的條目 | 無問題。兩站之間的估計人次是兩個 Int64 相乘，每站每天要到三十億人次才會溢位 |
| #1268 | **GameCore**：`busRoutesProblem` 要求路線編號在 `1..<nextBusRouteID`（審查 I 的 I8），前面已先擋掉 `nextBusRouteID < 1`，範圍不會倒過來；測試加 0 與 -1。GamePresentation：舊存檔的資料到了以後，車站周圍的道路在主執行緒外先讀（`RoadsReadAhead`），`frame`、`bounds` 一樣才用，只取現在還要的區塊，其他的照舊讀 | 無問題。讀的期間玩家多蓋了車站，多出來的區塊在主執行緒補讀，結果一樣；換了一局但地圖大小相同時，同一塊的道路本來就相同 |

### 三、修了的

無。

### 四、沒修、交出去的

無。

### 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（這個 branch，ddcd8b9，Linux，官方 Swift 6.4.0 `/opt/swift`） | **VERIFIED**，乾淨，0 個 warning |
| 與這一段有關的測試類別：`TrainCarsTests` 10、`Map3DE500Tests` 5、`Map3DHighSpeedSetsTests` 8、`AmbientDirectorTests` 10、`WhatsNewTests` 6、`BusRouteEditorTests` 13、`RealBusesTests` 6、`NetworkFlowReportTests` 15、`RealRoadCellsTests` 8、GameCore `BusRouteTests` 17 | **VERIFIED**，`swift test --skip-build --filter`，都是 0 失敗 |
| `python3 -I tools/ci-watch/full_lane_watch.py --selftest`（#1257） | **VERIFIED**，all cases passed |
| `.github/scripts/swift-shards-selftest.sh`（#1258 的 pack、unpack、gate） | **VERIFIED**，通過 |
| `python3 -I tools/golden-checks/doc_numbers.py --check` | **VERIFIED**，差異 0 項 |
| 其他 | 只讀程式、追了呼叫路徑 |
| 完整測試、iOS 建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

這一段沒有改程式，所以沒有回歸測試。

### 六、五方

- 玩家：十二個 PR 沒有會丟存檔、當掉或卡住的問題；放空模式、這版新增、路網分析的文字兩種語言都只寫功能。
- 鐵道迷：真實公車的估計班距在遊戲裡標明，來源（TDX、參考庫）的致謝齊全；E500、N700S-G、EMU3000 的長度與方向照真車。
- 開發：唯一的 GameCore PR #1268 驗證完整；派工單 E 的四個檔沒有動。
- 美術：無（模型由各自的 PR 照 art-style 檢查）。
- 音樂：無（放空模式讓音樂照放，沒有改音樂）。

## 第 3 段（#1270–#1287）

Session：session_01UvQcP14umjdnDYpqc14Ngx，branch `claude/new-session-hsegen`（系統指定的開發 branch，從 main **bfcfec9**（#1293 合併後）開）。

派工單 E（session_01MdqoSy58YkbJUqAMxXXoCk，#1295）正在改 `BusRoadNetwork.swift`、`BusStopLabels.swift`、`BusRouteEditor.swift`、`GameSession.swift`，這一段沒有動它們。#1283、#1285 碰到這幾個檔的部分照樣讀了，沒有發現要交給 E 的新問題。公車道路與真站牌在主執行緒讀（3D 的 `Map3DBuses` 也一樣），是 E 正在修、HANDOFF 已經寫的那一件，不重報。

### 一、結論

| 項目 | 數量 |
| --- | --- |
| 程式 PR | 12 個、12 點（沒有 GameCore） |
| 新發現 | **1 個**，P3（J2） |
| 已修 | 0 個（P3 不在順手修的範圍）；之後 J2 與疑點都已修，見 #1298 |
| 沒修，交出去 | **1 個**：J2（已修，見 #1298） |

另有一個疑點（推不出玩家碰得到的路徑，不算發現），寫在第四節最後。

### 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1270 | 決策 400 的 10i-6 3D 公車：`BusMotion`（往返、每站停靠不超過單程的 30 %，移動時間一定 > 0；`legMetres` 至少一段，GameCore 要求與站數相同，倒著走的 `leg` 不會 < 0）、`Map3DBuses`（`Route.stops` 比站多一個，與里程標對齊；簽名含形狀、`legMetres`、班次、車數、車站、顏色、調色盤、道路數與 `onRoads`）、`Map3DStreetLife` 的讓路、`Map3DLowFloorBus.routeModel`（加在 `Map3DModels` 最後，不動前面的索引）、`Map3DPreviewScreen` 的 `updateBuses`／`busFrame`；`RealTrainClock` 給 0–86,400 秒 | 無問題。`Map3DBuses` 在繪圖執行緒建，是 E 已寫進 HANDOFF 的同一件 |
| #1271 | 決策 417 動態預算與負載調節：`Map3DMotionBudget` 依 GPU 家族分三級（5 以下、8、9 以上；三角形 25 萬／60 萬／100 萬）、`limits(routeBuses:)`；`Map3DLoadGovernor`（連 3 個重的時窗降一級，升回要 20 → 240 個半秒、30 內再犯就加倍；「自動」從最高的下一級起、低一級從 0 起；照畫質、系統、級數記在 `map3DLoadRung`；記憶體警告就降、`critical` 熱度時最高只到 0）；`Map3DModels.model(_:forType:count:at:reach:)` 沒有遠景組時不會比以前畫得遠；`lifeCapacity`（最高一級的行人＋車＋公車 = 2,645）有 `.prefix` 擋 | 無問題。3D 一直連續畫，量到的低幀數是真的；只有「自動」用記住的級數，手動選的畫質不會被蓋掉；設定的文字兩種語言都有 |
| #1272 | 決策 418 裝置診斷：`DeviceDiagnostics`（MetricKit JSON 寬鬆解碼；最多 12 件、3 天、48 個 frame、256 KB；相同的去重；丟掉核心的 frame）、`DeviceDiagnosticsRecorder`（NSLock，存在 Application Support/Diagnostics）；問題回報在 `Task.detached` 讀檔 | 無問題 |
| #1273 | 決策 419 不在主執行緒讀存檔：`GameLauncher.open(reading:world:then:)` 在 `saveQueue` 上排在已排的存檔後面讀，道路在 `Task.detached` 讀；`isLoadingSave` 擋住重複點；300 ms 後才出讀取畫面；`gamesBegun` 擋舊的回呼；UI 測試啟動用 `readsSavesAtOnce` | 無問題。`SaveListView` 只從 StartView 開（那時 `session` 是 nil），`onChange(session != nil \|\| realWorldLoading != nil)` 關掉清單是對的；HUD 裡的讀檔照舊 |
| #1275 | 決策 420 太魯閣號、EMU800 遠景組：車鼻站的篩選；色帶高度 1+6、1+10 一致；環的預設上 3.70、下 0.83 與舊的字面值相同；`nearOnly` 加上兩組；`Map3DMeshSimplifier` 只在測試與報告用 | 無問題 |
| #1277 | 決策 421 幀時間紀錄：`FrameTimeRecord`、`FrameTimeMeter`、`FrameTimeRecorder`（2D 用 CADisplayLink 的拍子，3D 用 presented handler；每秒看一次，存在 `frame-times.json`）、`FrameCostMeter.frameParts`；建 `Map3DMetalView` 的只有一處 | **J2（P3）**：每一幀複製一次 11.6 KB 的計數，見第四節 |
| #1278 | 決策 421 的幀時間跑分：`FrameTimeBench`、`FrameTimeBenchRunner`、`layFrameTimeBench`、`layDemoRealLines(routes:)`、`GameLauncher.openFrameTimeBench`；只在測試版（`TestBuild.isTest` 加示範的開關）開得到 | 無問題。一個疑點見第四節最後 |
| #1280 | 決策 422 700T 遠景組：`refreshHighSpeed(far:)`（20 段，車底 12...17）、`refreshHighSpeedFarRunning`、`FarFittings`；N700S-G 的 `farMesh` 沒有時退回 `model(unit)` | 無問題。`teal` 的索引檢查只在車底那支用到，那裡的顏色是鋼色；色帶用裁切畫，不會少一條 |
| #1283 | 決策 424 公車走道路（E 的檔，只讀）：`BusRoadNetwork`／`BusWay` 1 m 內合併節點、`splitAtJunctions`、Dijkstra（`searchLimit` 40 萬）、圓角保留里程標；`PlayerCommandEdit` 加可選的 `legMetres`（舊紀錄解成 nil）；`Map3DBuses` 只在 `firstBroken` 是 nil 時用 `way(ofSaved:)` 的點與里程標；GameCore 的 `maximumLegMetres` 20 萬 | 無新問題。在主執行緒算是 E 的那一件 |
| #1284 | 決策 423 怎麼去：`JourneyPlan` 用 GameCore 的 `passengerRoutes(limit: 3)` 與 `tripFare(from:to:highSpeed:)`，只在經營模式顯示票價 | 無問題。與 `Boarding.chargeFares` 一致：第一次上車時收一次，起站到終點，有一段是高鐵就算高鐵（`ridesHighSpeed` 與它用同一個 `ServiceLine.isHighSpeed`） |
| #1285 | 決策 424 站牌與編號（E 的檔，只讀）：`BusStopLabels` 的編號（存檔的路線用 `farthestFirst`）、`RealBusStops` 10 m 內合併、`RealBusLibrary`、`BusArrows`（間隔 max(200 m, 120 pt)）；MapArt 的站牌、站名牌、箭頭、淡點，覆蓋層站牌與站名的 zip 順序一致；`GameLauncher`／`RealWorldData.realBuses` 讀 `real_buses_index` | 無新問題 |
| #1287 | 決策 423 車站面板的「怎麼去」：`JourneyPlanRows`、`StationPanel`；輸入是 `RidershipInputs`（含站名）加 `LineLook`，在 `Task.detached` 算；換選的車站時目的地重設 | 無問題 |

### 三、修了的

無。唯一的發現是 P3，不在順手修的範圍（只修 P1、P2）。

### 四、沒修、交出去的

#### J2（#1277）幀時間計量每一幀複製一次 11.6 KB 的區間計數，P3，沒修（已修，見 #1298）

- 檔案:行：`Sources/GamePresentation/FrameTimeRecord.swift:504`（`guard var current = tally`）、`:524`（`current.intervals.add(milliseconds)`）、`:510–511`（`defer { tally = current … }`）。
- 怎麼推得到：
  1. 玩家在 2D 地圖上，每一幀 CADisplayLink 呼叫 `FrameTimeRecorder` 的拍子（`RailwayGameApp/App/FrameTimeRecorder.swift:156`），它叫 `meter.frame(at: link.timestamp)`；3D 地圖每一幀從 presented handler 叫同一個函式（`RailwayGameApp/Views/Map3D/Map3DMetalView.swift:1131`）。
  2. `frame(at:)` 在鎖裡把 `tally` 複製到 `var current`。這時 `current.intervals` 的計數陣列（2,901 個 `UInt32`，約 11.6 KB）有兩個持有者（`tally` 與 `current`）。
  3. `current.intervals.add(...)` 寫陣列，copy-on-write 配一塊新的 11.6 KB 並整塊複製；`defer` 再把 `current` 寫回 `tally`，舊的那塊釋放。
  4. 所以每一幀（60 或 120 次／秒）都多配置、複製、釋放一次 11.6 KB，與類別說明「Nothing is made for a frame but a stall longer than any before it」（`:409–410`）不符。同一個類別的 `drew`、`gpu` 用 `tally!.…` 直接改，沒有這個問題。
  5. 量的：同樣寫法的獨立程式（`swiftc -O`，Linux）每次 0.16 µs，直接改 0.034 µs。一幀多約 0.13 µs，玩家看不到，但它是量幀時間的工具本身多出來的配置。
- 等級：**P3**。不會丟存檔、當掉或算錯錢，玩家也看不到。
- 建議怎麼修：照 `drew()`、`gpu()` 的寫法直接改 `tally!`（`tally!.intervals.add(milliseconds)`、`tally!.last = time` 等），或複製之後先 `tally = nil` 再改、最後寫回，讓陣列只有一個持有者。只動 GamePresentation 這一個函式；`FrameTimeRecordTests` 的結果不該變。交給下一個碰 `FrameTimeRecord.swift` 的 PR 順手帶上（決策 421 線）。

**疑點（不算發現；遊戲規劃查證會發生，已修，見 #1298，派工單 J3，決策 421 的「續修」）**：#1278 的跑分在 `railways` 還沒讀好時，`layDemoRealLines` 回 nil，跑出來是 0 條線，紀錄的情境卻寫真實的線數。只在測試版、而且要在真實鐵路資料讀完之前就開跑分才會發生，推不出正常的操作會走到這裡，所以只記為疑點。

### 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（這個 branch，bfcfec9，Linux，官方 Swift 6.4.0 `/opt/swift`） | **VERIFIED**，乾淨，0 個 warning |
| 與這一段有關的測試類別（`swift test --skip-build --filter`，第一個 Executed 行） | **VERIFIED**，都是 0 失敗：`BusMotionTests` 8、`Map3DBusesTests` 12（1 個略過，要 `BUS_3D_REPORT` 的報告）、`Map3DMotionBudgetTests` 27（2 個略過，要 `MOTION_BUDGET_REPORT` 的報告）、`DeviceDiagnosticsTests` 5、`GameLauncherTests` 9、`BackgroundSaveTests` 5、`SaveRecoveryTests` 7、`RealWorldDataLoadTests` 7、`Map3DFarSets420Tests` 3、`Map3DMeshSimplifierTests` 7、`Map3DFarSets422Tests` 3、`Map3DTrainSetTests` 12、`Map3DHighSpeedSetsTests` 8、`Map3DStreetLifeTests` 12、`FrameTimeRecordTests` 12、`FrameTimeBenchTests` 5、`BusRoadNetworkTests` 12、`BusStopLabelsTests` 16、`BusRouteEditorTests` 13、`JourneyPlanTests` 15（#1284、#1287 都是這一個類別） |
| `python3 -I tools/golden-checks/doc_numbers.py --check` | **VERIFIED**，差異 0 項 |
| J2 的量測（同樣寫法的獨立 `swiftc -O` 程式，Linux） | **VERIFIED**，0.16 µs 對 0.034 µs |
| 其他 | 只讀程式、追了呼叫路徑 |
| 完整測試、iOS 建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

這一段沒有改程式，所以沒有回歸測試。

### 六、五方

- 玩家：十二個 PR 沒有會丟存檔、當掉、卡住或算錯錢的問題；讀存檔不再卡住畫面，「怎麼去」的票價與實際收的一致。
- 鐵道迷：「怎麼去」的票價照 GameCore 收費的規則（第一次上車收一次、有高鐵段就算高鐵）；太魯閣號、EMU800、700T 的遠景組沒有改色帶與外型。
- 開發：這一段沒有 GameCore PR；J2 只是一個函式的寫法，交給決策 421 線；派工單 E 的四個檔沒有動。
- 美術：無（遠景組由各自的 PR 照 art-style 檢查）。
- 音樂：無。
