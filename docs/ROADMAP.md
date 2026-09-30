# Roadmap

各階段只是方向，實際範圍會依前一階段的成果調整。Phase 1、Phase 2A、Phase 2B 與 Phase 3 的 Stage I、J、K、L（GameCore 路徑搜尋）、M（讓 App 操作列車的最小畫面）、N（停站、以車站為目的地）已實作；Phase 3 的列車模擬核心到此告一段落。Phase 4（時刻表）進行中：Stage O（時刻表的資料契約）、Stage P（依時刻表到達、停留、出發的一次性服務）、Stage Q1（折返與重複運行）、Stage Q2a（服務線路的資料與推導）、Stage Q2b（自動派車）、Stage Q3（交路與停站模式）與 Stage R（服務與時刻表畫面）已實作，Phase 4 到此告一段落。Phase 4.5 的 Stage S1（軌道資源）、Stage S2（車站設施）、Stage S3（連續軌道幾何）、Stage S4（立體鐵路與結構物）與 Stage S5（路網上的營運）已實作，Phase 4.5 到此告一段落；下一步依參考的對照（[RAILWAY_REFERENCE_MAPPING.md](RAILWAY_REFERENCE_MAPPING.md)），先做 Phase 4.7 的 W1（行駛曲線的計算核心），再做 Phase 4.6 的 T、U、V。目前 App 的地圖畫面是原型：方格加上連續路網的俯視除錯投影，不是最終的 renderer（見 Phase 8）。

2026-09 研究了作者提供的網頁版交通經營遊戲（[WEB_REFERENCE_STUDY.md](WEB_REFERENCE_STUDY.md)），依結果調整了之後的階段：

- Stage Q 拆成 Q1–Q3；
- 新增 Phase 4.5（交通控制；之後再拆成 4.5–4.7，見下一段）；
- Phase 5 拆成 5A–5G；
- Phase 6–8 與跨階段議題補上吸收的做法。

作者自己的程式照原樣翻譯成 Swift（faithful port），作者自己的程式、資料與文字也可以收進 repo；第三方的程式與素材不移植、不收進來（規則見 [WEB_REFERENCE_STUDY.md](WEB_REFERENCE_STUDY.md#來源與使用方式)）。

另外研究了真實的鐵道時刻表（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）。時刻表裡的概念（逐班時刻、快慢車、時段班距、單線交會、停站時間）對應到各 Stage；即時資料不接進模擬；第一個真實藍本情境的候選是平溪線。

2026-09 再詳讀了時刻表資料的實體鐵路層（股道拓樸與道岔、單雙線、整列車的資源預約、班表綁定實體路徑、待避與交會、行駛曲線、月台與編組）。兩份參考剛好分層：網頁遊戲是經營層，時刻表資料是鐵路的物理層。所以原本的 Phase 4.5 拆成三段：

- Phase 4.5：實體鐵路（S1 軌道資源、S2 車站設施）；
- Phase 4.6：交通控制（T 進路預約、U movement authority、V dispatcher）；
- Phase 4.7：列車動態（W 行駛曲線）。

順序不變：先完成 Phase 4 的 Q3 與 R，再進 Phase 4.5。

S2 之後確定了產品方向：「以 deterministic 模擬核心為基礎的 360° 3D 鐵道城市建造遊戲」。交通控制若建立在北東南西的方格上，之後換成任意方向的鐵軌與立體交叉時就要重寫，所以先把鐵路核心拆成 topology、geometry、rendering 三層（ARCHITECTURE 決策 28），在 Phase 4.5 補上兩個 Stage（S3、S4），之後再加上 S5，把既有的營運系統接到新的路網上：

- Phase 4.5：S1 ✅ 軌道資源、S2 ✅ 車站設施、S3 ✅ 連續軌道幾何、S4 ✅ 立體鐵路與結構物、S5 ✅ 路網上的營運；
- Phase 4.6：T 進路預約、U movement authority、V dispatcher；
- Phase 4.7：W 行駛曲線。

舊的 Stage T（PR #31）建立在 S3/S4 之前的方格上，先暫停；新的 T 在 S5 之後改寫成泛用的 topology（見 Stage T）。

S5 是 S3/S4 與既有 O–Q 營運系統（operational system）之間的 bridge：停站、時刻表、折返與重複、線路、派車與服務模式都在路網上運作，而且方格與路網是同一套程式。T 之後不需要重新處理時刻表、線路與月台的 grid-specific migration。

## Phase 1 — GameCore foundation ✅

- Swift 6 Swift Package、與 rendering 分離的模擬核心
- 地圖、鐵軌、車站、最小列車模型
- 整數金額經濟、deterministic 遊戲時鐘
- Codable、XCTest、Linux CI

## Phase 2 — Native app prototype UI（cloud-first）

原本假設 Phase 2 以 M4 iPad 上的 Swift Playgrounds 為主要開發環境，但目前使用的 Swift Playgrounds 環境在執行專案程式碼之前的 prewarm / runtime 階段就會失敗，因此改為不需要 Mac、也不依賴 Swift Playgrounds 的流程：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions（Linux 測試、macOS 以 Xcode 編譯）→ 內部 TestFlight → 在 iPhone / iPad 實機上檢視
```

驗證分層：

1. Claude Code Cloud（Linux）：原始碼開發、GameCore `swift build` / `swift test`
2. Linux CI：Swift 6.0 是最低相容版本（warnings as errors 的 build 與除了長 campaign 以外的測試）；Swift 6.4 是目前的完整正確性驗證（全部測試，campaign 不減量、分成平行 shard）
3. macOS CI：XcodeGen 產生專案，以真正的 Xcode / Apple SDK 編譯原生 SwiftUI App
4. 實機人工檢視：內部 TestFlight（原本的手動 Visual Smoke Simulator 截圖已移除；人工檢視不是自動化的回歸測試）

Swift Playgrounds 只是可選環境，不是必要的開發或驗證步驟。

### Phase 2A — Cloud iOS build pipeline ✅

- 根目錄 `CLAUDE.md`（Claude Code 專案規則）
- 最小原生 SwiftUI App（iPhone / iPad、iOS 17+），連結 GameCore 並顯示地圖尺寸、現金、遊戲時間與速度
- XcodeGen spec（`RailwayGameApp/project.yml`），產生的 `.xcodeproj` 當時不進版控（Xcode Cloud onboarding 起改為提交，見下）
- macOS 自動編譯驗證（`ios-build.yml`），不需簽章
- 手動 Visual Smoke workflow（`visual-smoke.yml`，iPhone / iPad Simulator 截圖）：當時加入，之後已移除（改由內部 TestFlight 在實機人工檢視）

### Phase 2B — Prototype UI ✅

- 以 SwiftUI `Canvas` 顯示 `GameWorld` 的 grid（尺寸由世界決定），可捲動、縮放；空地 / 鐵軌 / 車站以不同形狀區分
- 點擊 tile 選取，顯示座標與內容
- 工具：選取、鋪軌（N / E / S / W 開關、常用形狀與旋轉選擇連接方向）、建站（可編輯的預設名稱）、拆軌
- 所有建設都經由 `GameWorld` 指令；`GameError` 在 Presentation 層轉成玩家看得懂的訊息
- HUD：現金、遊戲時間（`Day 1 · 08:30`，只是顯示換算）、暫停 / 1× / 2×
- `GameSession`（新的 `GamePresentation` target）持有唯一的 `GameWorld`，並把真實時間換算成整數 tick 呼叫 `advance(ticks:)`；背景時停止、不補跑
- iPhone 直向 / iPad 直向版面當時已以 Visual Smoke 截圖確認（該 workflow 已移除）；橫向版面（側邊欄）只經過編譯
- GameCore 未修改：時間顯示換算放在 Presentation 層；拆除車站延後（見下）

延後項目：拆除車站（GameCore 尚無指令）、拖曳連續鋪軌、軌道相鄰連接檢查（Phase 3 Stage I 已提供唯讀的連通查詢；鋪設時仍不要求相接）、存檔。

### 發佈管線 — 內部 TestFlight

讓 App 能以內部 TestFlight 安裝在實機上。這是發佈管線的準備，不改變遊戲開發範圍（Phase 3 照原計畫進行）。

- **Repository readiness ✅**（PR #8）：
  - XcodeGen 產生的 Xcode 專案與 shared scheme 提交進版控，`ios-build.yml` 檢查它與 `project.yml` 一致；
  - Release Archive、iPhone / iPad、自動簽章設定、臨時 App Icon；
  - 未簽章的 Release 裝置 Archive（`release-archive.yml`）。
- **GitHub Actions → 內部 TestFlight 基礎設施：已實作，真實執行驗證到上傳 App Store Connect**：
  - `testflight.yml`：只能從 `main` 手動觸發；preflight → Archive（預設 `adhoc`）→ App Store distribution 匯出 IPA → 檢查 → 上傳；
  - `testflight-checks.yml`：只用假值的腳本測試、macOS dry run、合成 IPA 檢查。
  - 手冊：[TESTFLIGHT_GITHUB_ACTIONS.md](TESTFLIGHT_GITHUB_ACTIONS.md)。
- **真實 Apple 簽章與上傳：VERIFIED（到上傳為止）**：Apple Developer Program、Team API key 與 environment 已就緒。第 1 次真實執行（`automatic`）在 Archive 失敗，因為新團隊沒有已註冊裝置、Apple 無法產生開發描述檔；第 2 次（`adhoc`）Archive、App Store distribution 匯出、IPA 檢查、上傳與清理全部成功，所以預設改為 `adhoc`。細節與 run 網址見 [TESTFLIGHT_GITHUB_ACTIONS.md](TESTFLIGHT_GITHUB_ACTIONS.md)。
- **尚未驗證**：App Store Connect processing、Missing Compliance 與 TestFlight 安裝到裝置（沒有 repository 層級的證據）。
- **Xcode Cloud onboarding：deferred**。手冊保留：[XCODE_CLOUD_ONBOARDING.md](XCODE_CLOUD_ONBOARDING.md)；啟用時需要一次 Mac／Xcode 操作。
- **之後**：外部 TestFlight 與 App Store 上架另行規劃。

## Phase 3 — Train simulation

拆成依序進行的小 Stage，每個 Stage 一個可 review 的 PR。

### Stage I — Derived Track Connectivity ✅

- `TrackDirection.opposite`；`GameWorld.connectedNeighbors(of:)`（固定北、東、南、西順序）與 `isConnected(_:to:)`
- 連通每次由地圖直接推導：雙向出口才相接；懸空出口可以鋪設；每格鐵軌是一個互通節點；車站不是鐵軌；沒有 graph cache（ARCHITECTURE 決策 10）
- `buildTrack` 與地圖解碼一致，只接受四個方向的 bit（rawValue 1…15）
- Golden scenario schema v2：唯讀的觀察步驟與 `track-connectivity.json`

### Stage J — Train Position ✅

- `TrainPosition`：`atNode(tile, heading:)`（任何朝向，死路與孤立鐵軌也可以）與 `onLink(from:to:offset:)`（兩格相接鐵軌之間，方向由端點推導）；未放置是 `Train.position == nil`
- 每條相鄰連結固定 1024 個抽象單位（`TrainPosition.linkLength`，`Int64` offset）；端點一律用 `atNode`，`onLink` 限 `0 < offset < 1024`，不做正規化
- `GameWorld`：`train(id:)`、`placeTrain(_:at:)`、`unplaceTrain(_:)`、`reverseTrain(_:)`（原地反向，兩次還原）；新購列車未放置；放置、取下、反向免費
- 列車所在節點或連結兩端的鐵軌拒絕拆除（`trackInUse`）；其他鐵軌照常可拆，取下列車後也可拆
- 存檔：未放置的列車不寫 `position`，舊存檔讀成未放置；壞資料，以及節點不在鐵軌格、連結兩端不相接的位置，一律拒絕
- Golden scenario schema v3：列車指令、結果與最終狀態的列車位置，以及 `train-position.json`
- 列車不會移動；App 沒有放置列車的介面（ARCHITECTURE 決策 14）

### Stage K — Train Movement Kernel ✅

- `TrainMovement`：`rate`（`Int64`，每遊戲分鐘的邏輯單位）、`continuation`（之後依序要進入的節點）與 `cursor`（已開始進入的項數；用完後存成空清單）；未放置的列車一律 idle
- `GameWorld`：`setTrainMovementRate(_:to:)`、`setTrainContinuation(_:to:)`（整份驗證後原子替換，空清單即清除）；`reverseTrain` 清空 continuation 並保留 rate，`unplaceTrain` 重設為 idle
- 純整數距離 kernel：先走完目前連結再依 continuation 前進，一步可跨多條連結；恰好抵達存成 `atNode` 且不消耗下一項；不選路、不折返
- `advance(ticks:)`：每個基本步長依 `TrainID` 順序移動列車、再推進一分鐘；2× 執行兩個基本步長；沒有列車能再改變時，時鐘直接跳過剩餘分鐘（精確捷徑）
- 前方鐵軌被拆時在最後可達節點等待，補回後下一步自動續行，等待期間的距離不累積
- `advance(ticks:)` 改為 `throws(GameError)`：先檢查倍速乘法與時鐘容量，溢位就整批拒絕（`clockOverflow`）；`GameClock.advance(ticks:)` 同樣檢查
- 存檔：idle 不寫 `movement`，舊存檔讀成 idle；等待修復中的世界可以存讀；壞資料一律拒絕
- Golden scenario schema v4：移動指令、`train` 觀察、最終狀態的列車 movement，以及 `train-movement.json`
- App 仍沒有放置或指定路徑的介面，列車移動只由測試與 golden fixture 驗證（ARCHITECTURE 決策 15）

### Stage L — Route / Pathfinding ✅（GameCore）

- `GameWorld.route(from:to:)`：唯讀查詢，回傳可直接交給 `setTrainContinuation` 的節點清單，或 `nil`
- 最少連結數、不立即折返（可繞圈掉頭，不會 reverse）；同長時依出口方向的北、東、南、西順序決定，結果與鋪設順序和平台無關
- 對 (節點, heading) 做 breadth-first search，只走訪可達鐵軌，不建立 graph 或快取；Stage K 的移動契約不變
- Golden scenario schema v5：`route` 觀察與 `train-route.json`（ARCHITECTURE 決策 16）
- 尚未做：多個途經點、以車站為目的地（Stage N）；App 的操作畫面見 Stage M

### Stage M — 最小畫面整合 ✅（App）

原本「最小畫面整合（尚未排定）」的項目，排在停站之前成為 Stage M；原本的 Stage M（停站）順延為 Stage N。

- App 的「Train」工具：購買列車、放置在選取的鐵軌格（選朝向）、設定 rate、把列車送到選取的鐵軌格、反向、取下；每個操作都是一個 `GameWorld` 指令
- 送出：`GameSession` 以 `route(from:to:)` 從列車目前的位置求路，在同一次呼叫中原封不動交給 `setTrainContinuation`；沒有路徑時世界不變
- 推進沿用 Phase 2B 的 game loop（HUD 的暫停 / 1× / 2×），沒有第二個推進入口
- 顯示 GameCore 記錄的位置、剩餘 continuation 與 rate；地圖在列車的權威位置畫出列車，每個 tick 跳一步，沒有插值
- GameCore 未修改（ARCHITECTURE 決策 17）

### Stage N — Station Stop ✅

- 車站仍然不是鐵軌；車站正北、正東、正南、正西的鐵軌格是它的月台（不需要朝向車站的出口，可以同時屬於多個車站），每次由地圖推導：`GameWorld.platforms(of:)`
- 以車站為目的地：`route(from:toStation:)`，用 Stage L 的搜尋把每個月台都當作目的地（最少連結、同長時北、東、南、西），在第一個月台結束，結果可直接交給 `setTrainContinuation`
- 停站：列車在月台格中心、沒有剩下的 continuation 時停在該站（`stationsStoppedAt(by:)`，依 ID 遞增）；由位置、continuation 與地圖推導，不存成狀態、存檔格式不變。經過月台、出發中（即使 rate 0）、等待修復都不是停站
- 沒有新指令或新錯誤；移動 kernel、Stage I–L 的契約不變（Stage L 的路徑 digest 不變）
- App：Train 工具選取車站格時送到該站（GameCore 求路後原封不動提交），並顯示列車停在哪些車站
- Golden scenario schema v7：`platforms`、`routeToStation`、`stationStops` 觀察與 `station-stop.json`（ARCHITECTURE 決策 18）
- 尚未做：停留時間、時刻表與服務模式（Phase 4）、乘客、拆除車站、月台容量

順序調整的理由：route / pathfinder 產生的路徑，必須是列車移動核心真的能執行的東西。先確立列車位置與移動延續的契約（J、K），路徑搜尋（L）才有明確的輸出形式可以對準；反過來做，路徑的表示方式會先把位置與移動的設計鎖死。

## Phase 4 — Timetable

和 Phase 3 一樣拆成依序進行的小 Stage，每個 Stage 一個可 review 的 PR。先確立時刻表是什麼資料（O），再讓它控制列車（P、Q），最後才做畫面（R）。

### Stage O — Timetable Foundation ✅

- `Train.timetable`：依序的 `ScheduledStop`（車站、排定的到達與離開）；陣列順序就是停靠順序，新購列車是空的
- 時間是開局以來的絕對遊戲分鐘（`GameTime`，與時鐘同一尺度）；沒有日曆、時區或字串時間
- 驗證：時間從分鐘 0 起不倒流（`0 ≤ arrival ≤ departure ≤ 下一站的 arrival`），每站都是存在的車站；允許停留 0 分鐘、相等的邊界、重複的車站與已過去的時間；不檢查路線、行駛時間或列車位置
- `setTrainTimetable(_:to:)`：整份原子替換、`[]` 清除、免費；錯誤依序 `unknownTrain` → `invalidTimetable` → `unknownStation`（第一個不存在的車站）
- 放置、取下、反向、移動指令與時間都保留時刻表；**不執行**：`advance` 不讀它，不發車、不求路、不改 rate，Stage I–N 的行為與 property digest 不變
- 存檔：空時刻表不寫 key（舊存檔讀成空、沒有時刻表的存檔格式不變）；壞資料一律拒絕，不排序或修正
- Golden scenario schema v8：`setTrainTimetable` 指令、`invalidTimetable` / `unknownStation` 結果、`timetable` 觀察、最終狀態的列車 `timetable`，以及 `train-timetable.json`（ARCHITECTURE 決策 19）
- GamePresentation 只加上兩個新錯誤的訊息；App 沒有修改

### Stage P — Dwell / Arrival / Departure ✅

- `Train.execution: TimetableExecution?`：執行進度是權威狀態，`.waitingAtStop(i)` / `.travellingToStop(i)`，`i` 是時刻表索引（不是車站 ID，因為車站可以重複）
- `startTrainService(_:)`：明確啟動，列車必須停在第一站的車站；從第 0 站開始，不依時間跳站；錯誤依序 `unknownTrain` → `trainServiceActive` → `noTimetable` → `trainNotPlaced` → `trainNotAtFirstStop`。`stopTrainService(_:)` 只結束自動化（`unknownTrain` → `trainServiceNotActive`），不清時刻表、不改位置、rate 或 continuation
- 一次、有限的服務：依時刻表順序跑到最後一站一次；不循環、不折返、不產生下一班
- 每個基本步長：`T` 的出發 → 移動 → 時鐘 `T + 1` → `T + 1` 的到達；每步最多移動一次
- 排定出發時刻是閘門：可以晚走，不會早走；不加最短停留，零停留合法，晚到的列車下一步就走；arrival 不是閘門
- 已停在下一站的車站（重複的車站、共用月台）時零距離到達；沒有路就等待並在之後重試；最後一站停到排定出發才結束
- 服務擁有 continuation：`setTrainContinuation`、`reverseTrain`、`unplaceTrain`、`setTrainTimetable` 在執行中是 `trainServiceActive`；`setTrainMovementRate` 仍可用
- `advance` 的捷徑改為事件感知：沒有變化時只跳到下一個服務出發時刻；`advance(n)` 仍等於 n 次 `advance(1)`
- 存檔：有服務時寫 `"execution"`，沒有時不寫（舊存檔讀成沒有服務）；壞資料一律拒絕，不修正
- Golden scenario schema v9：服務指令、四個新結果、`execution` 觀察、最終狀態的列車 `execution`，以及 `train-service.json`（ARCHITECTURE 決策 20）
- GamePresentation 只加上四個新錯誤的訊息；App 沒有修改

### Stage Q — Service Pattern / Automatic Dispatch

拆成三個依序的 PR。參考遊戲的兩種模式營運方式不同（[網頁參考研究](WEB_REFERENCE_STUDY.md#結論)的結論 1）：

- 地鐵以「時段 × 上線列車數」營運，班距由系統推導；
- 高鐵用逐班的時刻表，並能自動產生班次與回程。

Q 把前者展開成後者：服務模式產生具體、有限的班次，交給 Stage P 的執行核心去跑。Stage P 的契約都不變：排定出發是閘門、每步最多移動一次、沒有路就等待。

#### Q1 — 折返與重複運行（單一列車）✅

- **折返**：停靠站的屬性 `ScheduledStop.reverses`。服務離開這一站時，先讓列車原地反向，再求路到下一站；找不到路時整次出發都不發生，也不反向。Stage P「沒有路就等待、不自動反向」的規則不變。
- **重複**：`setTrainTimetable(_:to:repeatingEvery:)` 設定週期（`Train.timetablePeriod`）。
  - 跑完最後一站後，接著跑下一輪的第 0 站；第 `k` 輪的時刻是時刻表的時刻加上 `k × 週期`，由規則推導，不展開。
  - 週期至少 1 分鐘，而且重新開始時時間不倒流。
  - 時刻超出 `Int64` 的輪次不存在，服務在最後一輪之後結束。
- **執行進度**：`TimetableExecution` 帶著第幾輪（`cycle`），存檔。
- **開始**：重複的服務從第一站出發時刻不早於現在的第一輪開始，列車準時出發；一次性的服務照 Stage P。
- **一個出發段最多一整輪**：每台列車在一個出發段最多離開時刻表站數那麼多站，所以晚點的列車不會在一步裡無限繞圈。
- **存檔**：`period`、`reverse`、`cycle` 只在用到時寫入，舊存檔讀成一次、不折返、第 0 輪；壞資料一律拒絕。
- **Golden scenario schema v10**：新增 `reverse`、`repeat`、`cycle` 與 `train-repeat.json`；既有的 fixture 只加上中性的值（ARCHITECTURE 決策 21）。
- **不動的部分**：GamePresentation 只更新 `invalidTimetable` 的訊息；App 沒有修改。
- **留給之後**：停止服務後從指定的站續跑；取消落後的班次。

#### Q2 — 線路服務模式與自動派車

和 Stage O、P 一樣拆成兩步：先建立資料與推導（Q2a），再派車（Q2b）。規則移植自網頁參考遊戲的地鐵模式，改成整數分鐘（ARCHITECTURE 決策 22）。

##### Q2a — 服務線路的資料與推導 ✅

- **`ServiceLine`**（有自己的 `LineID`）：
  - 依序停靠的車站，列車到兩端都原地折返；
  - 計算行程用的 `rate`；
  - 營運時間：06:00–24:00，最晚到次日 06:00，也可以全天；
  - 尖峰、離峰、低峰各要跑幾台列車。
- **服務日**：世界的 `ServiceDay`，預設是參考遊戲的時段（07–10 時與 16–20 時尖峰、00–07 時與 21 時起低峰，其他離峰），可以用 `setServiceDay` 修改。
- **推導**（不存檔）：
  - 服務等級；
  - 行程：從第一站的月台出發，依序求路、在終點折返、回到第一站，取來回時間最短的起點；
  - 最多列車數：以最短班距 2 分鐘計算；
  - 實際列車數與班距。
- **線路是計畫資料**：不派車、不影響任何列車。
- **存檔與 golden**：存檔只在有值時寫入，golden scenario schema v11 新增 `service-line.json`。
- **App 沒有修改。**

##### Q2b — 自動派車 ✅

- **指派**：`assignTrain` 把列車交給線路，由線路設定它的時刻表、啟動它的服務；`unassignTrain` 取回時，列車跑完這一趟。線路的列車不能手動設定時刻表或啟停服務（`trainOnLine`）。
- **目標班距**（真實時刻表研究的結論）：各等級可以設定目標班距，由系統算出需要幾台車，多出的時間讓列車在第一站等；沒有設定的等級照舊用列車數推導班距。
- **派車**：每分鐘在出發之前，營運中、該等級有列車、距上次派車已過一個班距、跑車中的列車少於該等級的列車數時，線路讓停在第一站、能開完來回的列車跑一趟來回。一趟就是一份一次性的時刻表，由 Stage P、Q1 的服務執行。
- **依時段增減**：
  - 增車只能用停在第一站的列車；
  - 減車時，多出的列車跑完這一趟，回到第一站就停下（參考遊戲的「到終點站後退出」）。
- **一天**：`GameTime.minuteOfDay`，一天是 1440 分鐘；平日與週末的差別留待之後。
- **存檔與 golden**：只在用到時寫入；golden scenario schema v12 新增 `line-dispatch.json`（ARCHITECTURE 決策 23）。
- **已知限制**：Phase 4.6 之前，同一段鐵軌上的列車互不阻擋，和現在一樣會重疊；只從第一站派車。

#### Q3 — 交路與停站模式 ✅

- **服務模式**（`LinePattern`）：線路除了自己的全線站站停服務，還可以有其他模式。模式以停靠站的索引（`calls`，至少 2 個、嚴格遞增）表示：連續的索引是交路（短程折返），跳過的索引是快車通過的站。快慢車的標示只從 `calls` 看出來，是規劃資料。
- 每個模式有自己的列車數或目標班距、列車與上次派車，從自己的第一個停靠站派車，時刻表只列出停靠的車站。
- **容量**：每段鐵軌每天每個方向最多 720 班（最短班距 2 分鐘）。各服務依序（線路自己的最先）以 `⌈1440 ÷ 班距⌉` 佔用經過的每一段（快車也算進通過的站），放不下的服務減少列車數。線路自己的服務永遠不會被削減，沒有模式的線路和 Q2 完全相同。
- **覆蓋**：線路自己的服務永遠跨越全線；某等級沒有列車經過的區段由 `lineSegmentLoads` 推導（負載為 0），不拒絕指令。
- **指令**：`addLinePattern`、`removeLinePattern`；列車數、目標班距與指派加上 `pattern` 參數。
- **存檔與 golden**：只在有模式時寫入；golden scenario schema v13 新增 `line-patterns.json`（ARCHITECTURE 決策 24）。
- **已知限制**：列車互不阻擋，快車會穿過慢車，真正的待避、越行屬於 Stage V；不同線路共用鐵軌時的容量要等 Phase 4.5。

### Stage R — 服務與時刻表畫面 ✅

- **線路面板**（HUD 的「Lines」按鈕，半高的 sheet，地圖仍可操作）：
  - 每條線路的停靠站與目前的服務等級（尖峰、離峰、低峰或停駛）。
  - 選定線路的每個服務（自己的服務與各模式）：種類與兩端（站站停、交路、快車）、停靠與通過的站、各等級設定的列車數與目標班距、推導出的實際列車數與班距（「3 trains · Every 4 min」）、指派與行駛中的列車數。
  - 各等級沒有服務經過的區段（覆蓋缺口）。
  - 操作：各等級的列車數、目標班距、全天或 06:00–24:00 營運、新增與刪除交路或快車、指派選定的列車、刪除線路；在地圖上依序選車站建立新線路。
- **列車面板**：所屬的線路與服務、目前或下一個停靠與時刻、早到或誤點（和排定時刻比較後推導，不存檔）；取回線路的列車、啟動或停止自己的時刻表。
- **地圖的細節分級**：縮小到每格 20 點以下時只畫鐵軌線、車站標記與列車，不畫格線、道碴與車站圖示。
- 每個操作都是一個 `GameWorld` 指令；文字與推導都在 GamePresentation（可在 Linux 測試），畫面不保存第二份權威狀態。
- **留給之後**：逐站編輯時刻表的畫面、班次預覽的時刻列表、拖曳時隱藏覆蓋層。

## Phase 4.5 — Physical railway

多台列車要共用鐵軌，先要有可以佔用的資源，而且要知道鐵軌實際怎麼接、車站有幾股、多長。這一層參考真實時刻表資料的實體鐵路層（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md) 的「實體鐵路層」），放在交通控制之前。和 Phase 3、4 一樣，每個 Stage 一個 PR。

### Stage S1 — 軌道資源 ✅

- **道岔與平面交叉**：新增兩種鐵軌。道岔的 stem 接到每條支線，支線之間不互通；平面交叉只能直行。原本的鐵軌行為不變，所以既有存檔、路徑與 golden 值都不變。路徑、continuation 與移動遵守同一條轉向規則（`exits(from:facing:)`）。
- **區段**：兩個分岔點之間相連的一串鐵軌，沒有分岔點的環狀線是一個區段；由地圖推導、不存檔（`trackSections()`）。
- **單線與雙線**：兩站之間不共用連結的路徑數（`parallelTracks`、`lineTrackCounts`），1 是單線、2 以上是雙線。
- **佔用資源**：鐵軌格（節點）與相鄰鐵軌之間的連結；平面交叉是一格，兩個方向共用。唯讀查詢：每台列車佔用的資源、互相衝突的列車。
- 之前所有 Stage 的 property digest 不變；golden scenario schema v14 新增 `track-resources.json`（ARCHITECTURE 決策 26）。
- **留給之後**：建造道岔與平面交叉的畫面。

### Stage S2 — 車站設施 ✅

- **多格車站**：`extendStation` 讓車站長到旁邊的空格，每格都有月台。`platformTracks` 把月台依鐵軌相接分組，每組是一條月台股道，格數就是月台長度。
- **列車長度**：1 到 16 節，每節一格，只能在列車不在軌道上時設定。車頭後方的車身記錄在 `trail`，移動時跟著走，反向時車頭移到車尾，車身下的鐵軌不能拆。佔用資源包含車身。
- **停站**：長列車到站時沿月台延伸，整列都在月台邊時才算整列停妥（`stationsBesideWholeTrain`）。月台比列車短時，線路在第一站折返後無法再派出它，要把車站加長。
- **畫面**：車站工具可以切換成「長大」；列車不在軌道上時可以設定節數；地圖沿車身畫出整列車；月台太短時停站文字會說明。
- 之前所有 Stage 的 property digest 不變；golden scenario schema v15 新增 `station-facilities.json`（ARCHITECTURE 決策 27）。
- **移到 5A**：依車站等級決定規模的預設值。這屬於把真實時刻表轉成情境的工具，不在 GameCore 裡。

### Stage S3 — 連續軌道幾何 ✅

S3 分成兩個里程碑：S3A 讓 `RailwayNetwork` 成為唯一的鐵路資料與資源的基礎，S3B 在它上面加上連續幾何（ARCHITECTURE 決策 29）。

- **S3A 唯一的鐵路權威**：所有鐵軌（方格的鐵軌格與連續路網）只記在 `RailwayNetwork`；`GridMap` 只剩土地（空地與車站）。舊存檔讀檔時把鐵軌格移進路網，存檔時再寫回同樣的格式，只有方格的存檔逐位元不變。沒有雙向同步。
- **S3A 資源是 span**：資源是節點或邊上的一段里程（`TrackSpan`）。邊切成不超過一格長的等分，方格的連結恰好是一個 span，所以方格的佔用不變；長邊上的列車只佔用它所在的 span。佔用只讀整數里程，不讀畫面的取樣。泛用查詢 `pathAhead(of:)` 給之後的交通控制讀列車前方的路。
- **世界座標**：方格與連續路網共用一個整數的世界座標系（x 東、y 南、z 上），一格 1024 單位；方格 (x, y) 的中心是 (1024x + 512, 1024y + 512, 0)。
- **路網**：與方格並存的節點與邊。邊是直線或整數控制點的三次 Bézier；取樣、長度（水平里程）、位置與切線都由固定的整數演算法在建造或解碼時推導一次，之後每個 tick 只用整數長度。
- **泛用的身分**：`TrackNodeID`、`TrackEdgeID`、`TrackTraversal`、`TrackResource`（節點與 span）同時表示方格（`tile`、`link`）與路網（`node`、`edge`）。節點上的轉向由切線推導（兩端方向相反、誤差 1:16 以內才相通），道岔、菱形平面交叉與雙交分道岔都由此成立；只有共用節點才相接，平面上交叉但不共用節點的兩條邊互不相干。
- **列車**：新增位置 `onEdge`，移動 kernel 支援任意邊長；車身是車頭後方經過的邊（`trailEdges`），列車長度與格數脫鉤，反向兩次一定還原。
- **路徑搜尋**：方格與路網共用同一個最短路徑搜尋；方格的結果不變。
- **畫面**：地圖以俯視的除錯投影畫出路網與上面的列車；示範地圖有一條四段曲線組成的環線。沒有建造路網的畫面。
- 之前所有 Stage 的 property digest 不變，只有方格的存檔逐位元不變；新增獨立參考模型的差分 campaign、存檔變異測試，golden scenario schema v16 新增 `continuous-track.json`（ARCHITECTURE 決策 29）。
- **留給之後**：高程與結構物（S4 ✅）、路網上的服務（S5 ✅）、spline 編輯器與建造畫面、3D renderer。

### Stage S4 — 立體鐵路與結構物 ✅

- **高程**：節點的高度在地面上下 64 公尺（4096 單位）以內。邊沿水平里程有縱斷面：固定坡度，或兩端的拋物線豎曲線（平坡、上坡、下坡與過渡由同一個整數公式得到）；坡度是有理數，最大 40‰（遊戲參數）。長度仍是水平里程，移動與路徑不讀高度。
- **結構物**：地面、高架、橋、隧道。各自有高度帶（地面 ±2 公尺、高架與橋在地面以上、隧道在地面以下）與費用倍數；GameCore 不存橋墩或隧道壁。
- **交叉**：平面上相遇的兩條鐵軌（共用節點的一格以內除外）高度差至少 8 公尺（512），是立體交叉，不共用任何資源；否則拒絕。同一高度的交叉必須共用節點，也就是 S1 語義的平面交叉。
- **隧道**：一般的邊；隧道口是隧道與非隧道的邊相接的節點，列車照常穿過。
- **多層車站**：月台是鐵路網的基礎設施（`RailwayNetwork.platforms`，不存在車站裡）：車站、一條邊、起訖里程，層由邊的高度與結構物推導。同一站可以有任意多條、直的或彎的、地面、高架與地下的月台；月台的兩端切開那條邊的 span，整列停在月台上的列車只佔用月台內的 span；整列車都在月台區間內時可以查詢。層留給 Phase 5F 的步行轉乘成本。
- **畫面查詢**：3D 的姿態（位置、方向、坡度）、3D 車身與唯讀的 `railwaySnapshot()`；renderer 只讀、不回寫。
- **畫面**：俯視 debug 投影依高度由低到高畫，隧道是虛線、高架有陰影、隧道口加圈；示範配置有跨越環線的高架與駛入隧道的列車。
- Stage I–S2 的 14 個 property digest 不變；S3 的 `network.differential` 因為同一高度的交叉被拒絕而改變（刻意的）。新增 `vertical.differential`、`save.verticalMutation`，golden scenario schema v17 新增 `vertical-railway.json`（ARCHITECTURE 決策 30）。
- **留給之後**：地形（目前地面處處是 0）、路網與方格之間的空間檢查、軌道寬度的側向淨空、路網上的服務與派車（S5 ✅）、橫向傾斜、3D renderer、建造與地下模式的畫面。

### Stage S5 — 路網上的營運 ✅

S5 是 S3/S4 的路網與 Phase 3–4 營運系統（N、P、Q1、Q2a、Q2b、Q3）之間的橋（ARCHITECTURE 決策 31）。

- **一套營運語義**：時刻表的狀態機、線路的行程、派車與服務模式只有一份實作；只在最底層依鐵軌種類分成找月台、找路、交給移動與車身幾個小 adapter。沒有方格與路網各一份的時刻表引擎。
- **服務路徑**：`TrainPath`（依序進入的行進方向、停在最後一條的哪裡、精確的整數距離）是方格與路網共用的路。存檔的仍然只有列車的移動；路網的移動多一個 `end`，路可以停在邊的中段。
- **月台與停車位置**：路網上的停站只看 `TrackPlatform`：車頭停在行進方向上月台的末端，車身向後；只有不比列車短的月台才算，所以到站時整列車都在同一個月台上。彎道、高架與地下的月台規則相同。
- **以車站為目的地**：到停車位置的最短精確距離，同樣短時依邊的編號逐步決定，與建造順序、字典或記憶體位置無關。
- **精確距離**：一段的分鐘數是整數距離除以線路的速度、無條件進位（例如 8,300 + 21,470 + 3,200 = 32,970，而不是 3 × 1024）。
- **N、P、Q1、Q2a、Q2b、Q3 都在路網上運作**：停站與整列停妥、時刻表的到達停留出發、終點折返與重複、線路的行程與容量、自動派車、交路與快車。長列車折返時車頭移到車尾，仍在同一個月台上。
- **拆除月台**：服務正在使用的月台不能拆（`trainServiceActive`）。
- **畫面**：列車工具可以把路網上的列車送往車站；列車面板顯示路網上的路；地圖畫出路網上的月台；示範配置的環線有兩個月台，線路 Circle 在兩站之間往返派車。
- 之前的 16 個 property digest 全部不變，只有方格的世界與 S3、S4 的路網存檔逐位元不變。新增 `service.network` 差分 campaign 與 `save.networkServiceMutation`，golden scenario schema v18 新增 `network-service.json`（ARCHITECTURE 決策 31）。
- **留給之後**：列車之間的阻擋、進路預約、movement authority 與 dispatcher（T、U、V）；行駛曲線（W）；方格與路網之間的連接；建造路網、月台與線路的畫面。

## Phase 4.6 — Traffic control

要讓多台列車真正共用鐵軌、待避與交會，就需要這一層，這也是與《A列車》的深度差距最大的地方。兩個參考網站要分開看（2026-09 對私有 repo 重新確認，細節見 [RAILWAY_REFERENCE_MAPPING.md](RAILWAY_REFERENCE_MAPPING.md)）：

- `Ci/` 的交通經營遊戲沒有號誌、閉塞或待避站，快慢車也彼此「看不見」。
- `Railway/` 的股道網站沒有號誌或固定閉塞，但有這些：
  - 同向待避與單線交會（在瀏覽器裡對時刻表推估）；
  - 排定的等待（`scheduled-hold`，由建置腳本事先算好）；
  - 股道與月台的指派；
  - 同股道的跟車距離。

**建議的實作順序**（依實際的相依關係，不是字母順序）：

1. W1：行駛曲線的計算核心，照 `buildProfile` 翻譯。參考最完整，也不依賴其他 Stage。
2. W2：把曲線接到線路的行程與移動。有兩件事要作者先決定（見對照文件的 gap 分析）。
3. T、U：進路預約與 movement authority。參考只有結果、沒有演算法，所以大部分是 gap，要自己設計，或請作者補上建置腳本。
4. V：待避與交會。它的推估要用 W 的曲線；實際放行由 T、U 保證。

### Stage T — 進路預約

舊的 Stage T（PR #31）建立在 S3/S4 之前的方格上，暫停、不合併。新的 T 在 S5 之後，沿 `TrackTraversal` 的路徑預約泛用的 `TrackResource`，不依賴北東南西、格子或畫面；可以保留的語義與測試見 ARCHITECTURE 決策 29 的第 12 點。

T 直接使用 S5 統一好的服務路徑 `TrainPath`（canonical route）、`TrackTraversal`、`pathAhead(of:)`、`occupiedResources(of:)` 與 span、`TrackPlatform` 與停車位置，以及車身的佔用；路網上以車站為目的地的路、路網的時刻表與 LineJourney 的遷移都已在 S5 完成，不屬於 T（決策 31 第 21 點）。

- 出發或設定 continuation 時，列車向 GameCore 預約前方的資源（節點與 span，不是整條邊）。預約是整列車的，包含列車長度。
- 預約是權威狀態，要存檔。
- 避免死結的最小規則在 T 決定，例如一次只預約到下一個停靠站，或下一個可以停車的地方。

### Stage U — Movement authority

- 列車只能進入預約到的資源，通過後釋放。
- 決策 20 已經預留了接點：「沒有路就等待、之後再試」與「拿不到 authority 就等待」語義相同，所以時刻表與執行進度的契約不需要重寫。

### Stage V — Dispatcher：待避、交會與月台分配

- **衝突用排定的等待解決**：在某一站多停，讓對向或後面的車先過，而不是讓列車互穿。
- **待避站的選擇**：後車追上前車之前，往回找一個安全間隔足夠的車站讓前車待避。
- **單線交會**：等對向車到站再開。
- **月台分配**：例如停站的列車走月台線，通過的列車走正線。
- **優先順序**：例如快車優先。
- **路徑指定**：時刻表的每一段可以指定路徑（股道、月台），同一條線路的班次共用。
- 必須在 S1、S2、T、U 之後才做，而且不寫進 `ScheduledStop` 或 `Station`（決策 20）。
- **修正線路的容量**：Q2a 的最多列車數假設上下行互不干擾，等於雙線。單線區段只能在交會站錯車，實際容量較小（真實時刻表研究的結論，例如平溪線）。有了交會之後，最多列車數要依單線區段與交會站重新推導（決策 22 的已知限制）。

## Phase 4.7 — Train dynamics

### Stage W — 行駛曲線

參考：`Railway/` 網站的 `buildProfile`、`profTimeToProg`、`profProgToTime` 與車種性能表（[對照](RAILWAY_REFERENCE_MAPPING.md#stage-w行駛曲線)）。拆成兩步：

- **W1**：翻譯曲線本身，是純計算，不改變任何既有行為。
- **W2**：把曲線接到行程與移動。

- 站間不再等速：加速、定速、惰行、煞車組成的梯形曲線，加上速度上限；曲線半徑與坡度之後再考慮。
- 全部用整數計算，deterministic，和現在的 rate 一樣以每分鐘的單位數表示。
- 線路的行程與來回時間改由曲線推導，取代固定的 rate。
- 畫面上的平滑移動只是呈現；模擬仍以整數的基本步長前進。

## Phase 5 — Passenger simulation

乘客以群組（例如 `{ 起點, 迄點, 時段, 人數 }`）儲存，而不是一人一個物件。所有數量都是整數，每個 Stage 都有自己可以獨立測試的 deterministic 契約。

- **5A — 需求來源**：在城市模擬之前，每個車站依類型（住宅、辦公、商業、景點）套用每小時的需求曲線，權重以千分比整數表示。車站等級（真實時刻表研究）決定需求與車站規模的預設值：情境轉換工具依等級決定車站的格數（Stage S2 的多格車站）。
- **5B — OD 與時段需求**：
  - 以整數釋出並保留餘數，讓一天的總量完全精確；
  - 同時發生的釋出依 (tick, 起點, 迄點) 排序；
  - 從這裡開始做乘客守恆稽核。
- **5C — 路徑選擇**：
  - 網路或服務改變時，預先計算每個 OD 的幾個路徑選項；
  - 成本以整數分鐘計算，包含候車、乘車與轉乘懲罰；
  - 分配人數用最大餘數法，以索引決定平手，不用亂數；
  - 可以在背景對世界的快照計算。
- **5D — 車站佇列**：依方向與目標分組、先進先出；有收容上限，超過的人記入溢出計數。
- **5E — 上下車與容量**：
  - 列車記錄「在哪一站下車」的人數；
  - 容量 = 輛數 × 每輛定員；
  - 記錄被拒絕上車的人數。
- **5F — 轉乘**：
  - 依距離分出轉乘的等級（同月台、步行通道），各有轉乘懲罰；
  - 同一條線裡快慢車之間的換乘不算轉乘。
- **5G — 票價與收入**：
  - 單一票價與依距離分段的票價，以 `Money` 整數計算，並記錄收入歸屬；
  - 如果採用票價彈性，用查表，而不是浮點公式。

## Phase 6 — City simulation

**地圖方針（2026-09 決定）**：主要模式用虛擬地圖，走《A列車》「鐵路帶動城市成長」的路線。

- **虛擬地圖**：手工設計的情境地圖，加上由種子產生的地形。存檔只需要種子與玩家的修改，而且結果固定。
- **真實藍本情境**：之後可選擇加入。以真實的地形與人口為藍本，由 GameCore 以外的轉換工具產生同一種格子格式。資料來源必須能合法使用，例如政府開放資料，或標示來源的 OpenStreetMap。第一個候選（平溪線）見 [TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)。
- **GameCore 不區分地圖從哪裡來。**
- **不以真實地圖為主模式的原因**：
  - 真實城市已經開發完成，「車站帶動成長」的循環會變弱；
  - 難度與情境不好設計；
  - 目前的鐵軌只有東西南北四個方向；
  - 真實資料有授權問題，也會讓離線 App 變大。
- **對之後的影響**：
  - 本 Phase 的第一步是「地形與初始城鎮」，同時決定一格代表多少距離；
  - 5A 與本 Phase 的資料模型以「土地使用格子」為準，兩種地圖都適用；
  - 是否支援八個方向的鐵軌，另外決定。

- residential / commercial / office
- land value
- station influence：車站的服務範圍以格子距離計算
- city growth
- 以城市的土地使用取代 5A 的車站類型需求曲線
- 事件（例如客流激增、展覽）是獨立的一層：事先預告，亂數由存檔的種子產生

## Phase 7 — Company simulation

- revenue：分類帳，每一期只結算一次，各類別加總精確等於總額
- operating expense：人事、能源、車輛
- construction
- loans
- assets
- 是否採用參考遊戲的建設配額制，在這裡決定；在此之前維持現金經濟

## Phase 8 — Advanced rendering

目前的 SwiftUI Canvas 地圖是原型：方格加上連續路網的俯視除錯投影。最終的 360° 3D renderer 只讀 GameCore 的幾何查詢（`railwaySnapshot()`：世界座標、邊的中心線與縱斷面、結構物、隧道口、月台、列車的姿態與 3D 車身），不回寫，也不讓 mesh、相機或插值進入模擬。

依實際地圖大小與列車數量的效能量測，評估 SwiftUI、SpriteKit、Metal。不預先鎖定 Metal。

呈現的效能手段：依縮放層級分級顯示細節、拖曳時隱藏覆蓋層、只畫畫面內的物件。效能設定只影響呈現，不影響模擬結果。

## 跨階段議題

- save/load：加入存檔版本欄位與 migration
- undo/redo：利用 `GameWorld` 的 value semantics 快照
- 大型地圖與大量列車：量測後再考慮 chunking、背景計算
- 新的模擬行為同時加入 `GoldenScenarios/` 情境；若日後決定移植到其他引擎，逐一子系統移植並以同一批情境驗證（ARCHITECTURE 決策 13）
- 模擬結果與裝置無關：分片或背景計算都必須得到與一次算完相同的結果，性能模式只能影響呈現（網頁參考研究）
- 隨機性：之後需要時，由存檔在世界裡的種子，以（種子, 用途, 序號）的雜湊產生，不使用系統亂數
- 整數分配一律用最大餘數法，以索引決定平手；乘客與金額的守恆寫成 property 測試
- 分析指標優先由狀態推導，只有歷史彙總才存檔
