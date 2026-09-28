# Railway Game iOS

一款以 iPhone / iPad 為主要平台的鐵道與城市經營模擬遊戲。長期目標是玩法深度接近《A列車》系列的原生 Apple 平台遊戲。

## 目前狀態

**Early development — GameCore prototype + native app smoke test（Phase 2A）.**

目前有與畫面無關的模擬核心（`GameCore` Swift Package）與其測試，以及一個最小的原生 SwiftUI App（`RailwayGameApp/`），只用來證明 GameCore 能在真正的 iPhone / iPad App 中建置、連結與讀取。**尚未**有遊戲 UI、可遊玩的遊戲、列車運行模擬或城市模擬。

GameCore 目前能做到：

- 建立指定尺寸的方格地圖（1…1024 × 1…1024）
- 鋪設 / 拆除鐵軌（每格記錄連接方向）
- 建造車站（唯一、可保存的 Station ID）
- 購買列車（僅 ID 與名稱，不在地圖上運行）
- 整數金額的資金與建設成本
- 可暫停、1x、2x 的 deterministic 遊戲時鐘
- 所有核心狀態可 `Codable` 編碼 / 解碼

### 建設規則

| 動作 | 條件 | 成本 |
| --- | --- | --- |
| 鋪軌 | 位置在地圖內、該格為空、至少一個連接方向、資金足夠 | `ConstructionCosts.track` |
| 拆軌 | 該格必須是鐵軌（空格與車站都會被拒絕） | 免費，**不退款** |
| 建站 | 名稱非空白、位置在地圖內、該格為空、資金足夠 | `ConstructionCosts.station` |
| 購買列車 | 名稱非空白、資金足夠 | `ConstructionCosts.train` |

任何失敗都會丟出 `GameError`，且世界狀態（地圖、資金、車站、列車）完全不變。餘額永遠不會因建設變成負數。

## 技術方向

- Swift 6（language mode 6）
  - 最低 Swift tools version：6.0（`swift-tools-version: 6.0`）
  - 持續相容 Swift 6.2.x（CI 驗證 6.2.4）
- Swift Package Manager
- XcodeGen（由 `RailwayGameApp/project.yml` 產生 Xcode 專案）
- SwiftUI（Presentation；Phase 2A 為最小 smoke App，iOS 17+，iPhone / iPad）
- SpriteKit / Metal（Rendering，未來依效能需求評估）

## Architecture

| 層 | 狀態 | 職責 |
| --- | --- | --- |
| **GameCore** | ✅ 本階段 | 權威遊戲狀態與規則；不依賴任何 UI / rendering framework |
| Presentation | 🟡 Phase 2A smoke App | SwiftUI 介面、使用者輸入、HUD |
| Rendering | 未開始 | 地圖與列車的繪製、動畫 |

Presentation 與 Rendering 只讀取 GameCore 狀態並送出指令，不持有另一份遊戲真實狀態。目前的 App 以 SwiftUI `@State` 持有唯一一份 `GameWorld`，畫面只讀取。詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，未來規劃見 [docs/ROADMAP.md](docs/ROADMAP.md)。

```
Sources/GameCore/
  World/     GameWorld、GridMap、GridPosition、MapTile/TileType、GameError
  Railway/   TrackDirection/TrackConnections、Track、Station、Train
  Economy/   Money、GameEconomy、ConstructionCosts
  Time/      GameClock、GameSpeed、GameTime
Tests/GameCoreTests/
RailwayGameApp/
  project.yml   XcodeGen spec（產生的 .xcodeproj 不進版控）
  App/          RailwayGameApp（@main，持有 GameWorld）
  Views/        ContentView（smoke test 畫面）
```

## 開發流程（cloud-first）

不需要自己的 Mac，也不依賴 Swift Playgrounds：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions macOS (Xcode / Simulator) → 截圖 artifact → 在 iPhone / iPad 上檢視
```

| 層 | 在哪裡跑 | 驗證什麼 |
| --- | --- | --- |
| 1. Claude Code Cloud | Linux 容器 | 原始碼開發；GameCore `swift build` / `swift test`。**沒有** Xcode、Simulator、SwiftUI / UIKit |
| 2. Linux CI（`ci.yml`） | 每次 push / PR | GameCore 在 Swift 6.0、6.2.4、6.4 的 build（warnings as errors）與 test |
| 3. iOS App Build（`ios-build.yml`） | macOS runner，PR 與 `main` 自動執行（純文件變更略過） | XcodeGen 產生專案；以真正的 Xcode / Apple SDK 為 iOS Simulator 編譯 SwiftUI App 與 GameCore；不需簽章 |
| 4. Visual Smoke（`visual-smoke.yml`） | macOS runner，**手動**觸發 | 在 iPhone 與 iPad Simulator 啟動 App、確認沒有閃退、截圖並上傳為 artifact |

- **Swift Playgrounds**：可選，不是必要的開發或驗證環境。
- **TestFlight / App Store 簽章 / 實機部署**：延後，不屬於 Phase 2A；目前完全不需要 Apple Developer Program、憑證或 provisioning profile。

### 在 iPhone / iPad 上查看截圖

1. GitHub → **Actions** → 左側選 **Visual Smoke** → **Run workflow**（選擇分支）→ **Run workflow**
2. 等待執行完成
3. 打開該次執行的 Summary 頁面 → **Artifacts** → 下載 **visual-smoke**
4. zip 內含 `iphone.png`、`ipad.png`、`simulator.log`、`xcodebuild.log`、`simulators.txt`（失敗時另有 crash report 與 App stderr）

Artifact 只保留 7 天。只有在 workflow 檔已經存在於 `main` 時，GitHub 才會顯示 **Run workflow** 按鈕；修改 Visual Smoke workflow 或其腳本的 PR 會自動執行一次。

## Building

GameCore（任何有 Swift 6 的環境，包括 Linux）：

```sh
swift build
```

iOS App（需要 macOS + Xcode 16 以上與 [XcodeGen](https://github.com/yonaskolb/XcodeGen)）：

```sh
xcodegen generate --spec RailwayGameApp/project.yml
open RailwayGameApp/RailwayGame.xcodeproj
```

`RailwayGame.xcodeproj` 由 `project.yml` 產生、不進版控（已列入 `.gitignore`），專案設定一律改 `project.yml`。CI 使用的 XcodeGen 版本固定在 `.github/actions/setup-xcodegen/action.yml`。

## Testing

```sh
swift test
```

GameCore 只使用 Swift 標準函式庫，因此可在 macOS、iOS 與 Linux 上建置。CI 在 Linux 上以 Swift 6.0（最低版本）、6.2.4（持續相容的 6.2 系列）與 6.4（目前穩定版）執行 build 與 test。
