# Roadmap

各階段只是方向，實際範圍會依前一階段的成果調整。Phase 1、Phase 2A、Phase 2B 已實作；下一步是 Phase 3。

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
- XcodeGen spec（`RailwayGameApp/project.yml`），產生的 `.xcodeproj` 不進版控
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

延後項目：拆除車站（GameCore 尚無指令）、拖曳連續鋪軌、軌道相鄰連接檢查、存檔。

### 之後（可選）— TestFlight

在 Simulator 流程穩定之後，才評估以 TestFlight 發佈到實機（需要 Apple Developer Program、簽章憑證與 App Store Connect）。不屬於 Phase 2。

## Phase 3 — Train simulation

- 由 `TrackConnections` 推導 track topology / graph
- route
- pathfinding
- train movement（位置表示方式在此決定）
- station stop

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
