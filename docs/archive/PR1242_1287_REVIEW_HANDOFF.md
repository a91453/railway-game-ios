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
