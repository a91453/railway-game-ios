# Roadmap

各階段只是方向，實際範圍會依前一階段的成果調整。Phase 1、Phase 2A、Phase 2B 與 Phase 3 的 Stage I、J、K、L（GameCore 路徑搜尋）、M（讓 App 操作列車的最小畫面）已實作；下一步是 Phase 3 的 Stage N（停站）。

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
2. Linux CI：GameCore 在 Swift 6.0、6.2.4、6.4 的相容性
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

### Stage N — Station Stop

- 停站、以車站為目的地

順序調整的理由：route / pathfinder 產生的路徑，必須是列車移動核心真的能執行的東西。先確立列車位置與移動延續的契約（J、K），路徑搜尋（L）才有明確的輸出形式可以對準；反過來做，路徑的表示方式會先把位置與移動的設計鎖死。

## Phase 4 — Timetable

- departure / arrival
- dwell time
- service pattern

## Phase 5 — Passenger simulation

- population
- origin / destination
- demand
- transfer
- fare

## Phase 6 — City simulation

- residential / commercial / office
- land value
- station influence
- city growth

## Phase 7 — Company simulation

- revenue
- operating expense
- construction
- loans
- assets

## Phase 8 — Advanced rendering

依實際地圖大小與列車數量的效能量測，評估 SwiftUI、SpriteKit、Metal。不預先鎖定 Metal。

## 跨階段議題

- save/load：加入存檔版本欄位與 migration
- undo/redo：利用 `GameWorld` 的 value semantics 快照
- 大型地圖與大量列車：量測後再考慮 chunking、背景計算
- 新的模擬行為同時加入 `GoldenScenarios/` 情境；若日後決定移植到其他引擎，逐一子系統移植並以同一批情境驗證（ARCHITECTURE 決策 13）
