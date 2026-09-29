# Roadmap

各階段只是方向，實際範圍會依前一階段的成果調整。Phase 1、Phase 2A、Phase 2B 與 Phase 3 的 Stage I、J、K、L（GameCore 路徑搜尋）、M（讓 App 操作列車的最小畫面）、N（停站、以車站為目的地）已實作；Phase 3 的列車模擬核心到此告一段落。Phase 4（時刻表）進行中：Stage O（時刻表的資料契約）、Stage P（依時刻表到達、停留、出發的一次性服務）、Stage Q1（折返與重複運行）、Stage Q2a（服務線路的資料與推導）與 Stage Q2b（自動派車）已實作，下一步是 Stage Q3（交路與停站模式）。

2026-09 研究了作者提供的網頁版交通經營遊戲（[WEB_REFERENCE_STUDY.md](WEB_REFERENCE_STUDY.md)），依結果調整了之後的階段：

- Stage Q 拆成 Q1–Q3；
- 新增 Phase 4.5（交通控制；之後再拆成 4.5–4.7，見下一段）；
- Phase 5 拆成 5A–5G；
- Phase 6–8 與跨階段議題補上吸收的做法。

作者自己的邏輯可以改寫成 Swift 移植；網頁的程式、快照與素材不進版控。

另外研究了真實的鐵道時刻表（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）。時刻表裡的概念（逐班時刻、快慢車、時段班距、單線交會、停站時間）對應到各 Stage；即時資料不接進模擬；第一個真實藍本情境的候選是平溪線。

2026-09 再詳讀了時刻表資料的實體鐵路層（股道拓樸與道岔、單雙線、整列車的資源預約、班表綁定實體路徑、待避與交會、行駛曲線、月台與編組）。兩份參考剛好分層：網頁遊戲是經營層，時刻表資料是鐵路的物理層。所以原本的 Phase 4.5 拆成三段：

- Phase 4.5：實體鐵路（S1 軌道資源、S2 車站設施）；
- Phase 4.6：交通控制（T 進路預約、U movement authority、V dispatcher）；
- Phase 4.7：列車動態（W 行駛曲線）。

順序不變：先完成 Phase 4 的 Q3 與 R，再進 Phase 4.5。

## Phase 1 — GameCore foundation ✅

- Swift 6 Swift Package、與 rendering 分離的模擬核心
- 地圖、鐵軌、車站、最小列車模型
- 整數金額經濟、deterministic 遊戲時鐘
- Codable、XCTest、Linux CI

## Phase 2 — Native app prototype UI（cloud-first）

原本假設 Phase 2 以 M4 iPad 上的 Swift Playgrounds 為主要開發環境，但目前使用的 Swift Playgrounds 環境在執行專案程式碼之前的 prewarm / runtime 階段就會失敗，因此改為不需要 Mac、也不依賴 Swift Playgrounds 的流程：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions macOS (Xcode / Simulator) → 截圖 / log artifact → 在 iPhone / iPad 上檢視
```

驗證分層：

1. Claude Code Cloud（Linux）：原始碼開發、GameCore `swift build` / `swift test`
2. Linux CI：GameCore 在 Swift 6.0、6.4 的相容性
3. macOS CI：XcodeGen 產生專案，以真正的 Xcode / Apple SDK 編譯原生 SwiftUI App
4. 手動 Visual Smoke：iPhone / iPad Simulator 截圖，以 GitHub artifact 在手機或平板上檢視

Swift Playgrounds 只是可選環境，不是必要的開發或驗證步驟。

### Phase 2A — Cloud iOS build pipeline ✅

- 根目錄 `CLAUDE.md`（Claude Code 專案規則）
- 最小原生 SwiftUI App（iPhone / iPad、iOS 17+），連結 GameCore 並顯示地圖尺寸、現金、遊戲時間與速度
- XcodeGen spec（`RailwayGameApp/project.yml`），產生的 `.xcodeproj` 當時不進版控（Xcode Cloud onboarding 起改為提交，見下）
- macOS 自動編譯驗證（`ios-build.yml`），不需簽章
- 手動 Visual Smoke workflow（`visual-smoke.yml`）：iPhone / iPad Simulator 截圖

### Phase 2B — Prototype UI ✅

- 以 SwiftUI `Canvas` 顯示 `GameWorld` 的 grid（尺寸由世界決定），可捲動、縮放；空地 / 鐵軌 / 車站以不同形狀區分
- 點擊 tile 選取，顯示座標與內容
- 工具：選取、鋪軌（N / E / S / W 開關、常用形狀與旋轉選擇連接方向）、建站（可編輯的預設名稱）、拆軌
- 所有建設都經由 `GameWorld` 指令；`GameError` 在 Presentation 層轉成玩家看得懂的訊息
- HUD：現金、遊戲時間（`Day 1 · 08:30`，只是顯示換算）、暫停 / 1× / 2×
- `GameSession`（新的 `GamePresentation` target）持有唯一的 `GameWorld`，並把真實時間換算成整數 tick 呼叫 `advance(ticks:)`；背景時停止、不補跑
- iPhone 直向 / iPad 直向版面已以 Visual Smoke 截圖確認；橫向版面（側邊欄）只經過編譯
- GameCore 未修改：時間顯示換算放在 Presentation 層；拆除車站延後（見下）

延後項目：拆除車站（GameCore 尚無指令）、拖曳連續鋪軌、軌道相鄰連接檢查（Phase 3 Stage I 已提供唯讀的連通查詢；鋪設時仍不要求相接）、存檔。

### 發佈管線 — 內部 TestFlight

讓 App 能以內部 TestFlight 安裝在實機上。這是發佈管線的準備，不改變遊戲開發範圍（Phase 3 照原計畫進行）。

- **Repository readiness ✅**（PR #8）：
  - XcodeGen 產生的 Xcode 專案與 shared scheme 提交進版控，`ios-build.yml` 檢查它與 `project.yml` 一致；
  - Release Archive、iPhone / iPad、自動簽章設定、臨時 App Icon；
  - 未簽章的 Release 裝置 Archive（`release-archive.yml`）。
- **GitHub Actions → 內部 TestFlight 基礎設施：已實作，dry run 驗證**：
  - `testflight.yml`：只能從 `main` 手動觸發；preflight → 簽章 Archive → 匯出 IPA → 檢查 → 上傳；
  - `testflight-checks.yml`：只用假值的腳本測試、macOS dry run、合成 IPA 檢查。
  - 手冊：[TESTFLIGHT_GITHUB_ACTIONS.md](TESTFLIGHT_GITHUB_ACTIONS.md)。
- **真實 Apple 簽章與上傳：blocked**，等待 Apple Developer Program 生效、API 存取與 Team API key；第一次執行同時驗證雲端簽章在 GitHub runner 上的行為。
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

#### Q3 — 交路與停站模式

- 交路以停靠站的索引區間表示，所有交路必須連續覆蓋整條線，各自有列車數。
- 快車是停靠站的子集合。快慢車的標示只是規劃資料。
- 重疊區段的頻率相加後，仍要滿足最短班距。
- 真正的待避、越行屬於 Stage V。

### Stage R — 服務與時刻表畫面

- **線路服務面板**：時段、上線列車數、推導出的班距（「每 X 分一班」）、營運時間，以及產生的班次預覽。
- **列車面板**：所屬的服務、目前或下一個停靠、下一次出發，以及早到或誤點。早到與誤點是和排定時刻比較後推導出來的，不存檔。
- **操作**：啟動與停止服務、編輯時刻表（屆時再決定是否需要編輯單一停靠的指令）。每個操作都是一個 `GameWorld` 指令，畫面不保存第二份權威狀態。
- **地圖的細節分級**：縮小時只畫路線與列車，放大才畫車站細節；拖曳時隱藏覆蓋層。
- 可以先拆出唯讀的 R1，只顯示已有的時刻表與服務，不必等 Q 全部完成。

## Phase 4.5 — Physical railway

多台列車要共用鐵軌，先要有可以佔用的資源，而且要知道鐵軌實際怎麼接、車站有幾股、多長。這一層參考真實時刻表資料的實體鐵路層（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md) 的「實體鐵路層」），放在交通控制之前。和 Phase 3、4 一樣，每個 Stage 一個 PR。

### Stage S1 — 軌道資源

- **分岔的轉向規則**
  - 目前格子鐵軌的 T 形分岔三個方向可以任意互通，只禁止原地掉頭，等於一個三角線。
  - 真實道岔的兩支彼此不能直接互通，只能各自接回主線。
  - 要表達真實道岔，傾向新增一種明確的道岔鐵軌，保留現在的分岔行為，讓既有存檔、路徑與 golden 值不變。實際做法在 S1 決定。
- **區段**：兩個分岔之間相連的一串鐵軌是一個區段，由地圖推導、不存檔。
- **單線與雙線**：由地圖推導單線區段（兩站之間只有一條相連的鐵軌）。
- **佔用資源**：
  - 鐵軌格（節點）與相鄰鐵軌之間的連結；
  - 平面交叉點（兩個方向共用一個衝突資源）。
- **唯讀查詢**：哪些資源被哪台列車佔用、哪些列車互相衝突。佔用由列車位置推導，不存檔。
- 不改變任何移動規則，之前所有 Stage 的 property digest 不變。

### Stage S2 — 車站設施

- 多格車站、月台股道與月台長度（以格計）。
- 列車長度：輛數 × 每輛長度（整數單位），列車佔用多格。
- 停站判定改看月台與列車長度，例如整列車都在月台內才算停妥。
- 車站等級決定規模的預設值（真實時刻表研究的車站等級）。

## Phase 4.6 — Traffic control

參考遊戲沒有號誌、閉塞或待避站，快慢車也彼此「看不見」。要讓多台列車真正共用鐵軌、待避與交會，就需要這一層，這也是與《A列車》的深度差距最大的地方。

### Stage T — 進路預約

- 出發或設定 continuation 時，列車向 GameCore 預約前方的資源。預約是整列車的，包含列車長度。
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

- 站間不再等速：加速、定速、惰行、煞車組成的梯形曲線，加上速度上限；曲線半徑與坡度之後再考慮。
- 全部用整數計算，deterministic，和現在的 rate 一樣以每分鐘的單位數表示。
- 線路的行程與來回時間改由曲線推導，取代固定的 rate。
- 畫面上的平滑移動只是呈現；模擬仍以整數的基本步長前進。

## Phase 5 — Passenger simulation

乘客以群組（例如 `{ 起點, 迄點, 時段, 人數 }`）儲存，而不是一人一個物件。所有數量都是整數，每個 Stage 都有自己可以獨立測試的 deterministic 契約。

- **5A — 需求來源**：在城市模擬之前，每個車站依類型（住宅、辦公、商業、景點）套用每小時的需求曲線，權重以千分比整數表示。
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
