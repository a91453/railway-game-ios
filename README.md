# Railway Game iOS

一款以 iPhone / iPad 為主要平台的鐵道與城市經營模擬遊戲。長期目標是玩法深度接近《A列車》系列的原生 Apple 平台遊戲。

## 目前狀態

**Early development — GameCore + native prototype UI（Phase 2B）；Phase 4.5 Stage S2（車站設施）.**

目前有與畫面無關的模擬核心（`GameCore` Swift Package）、與平台無關的 Presentation 邏輯（`GamePresentation`），以及可操作的原生 SwiftUI prototype App（`RailwayGameApp/`，iPhone / iPad）。GameCore 已有列車位置、沿明確路徑移動、最短路徑搜尋與停站（Phase 3 Stage N）的核心，每台列車的時刻表資料（Phase 4 Stage O），依時刻表執行服務的核心（Phase 4 Stage P：到達、停留到排定出發、出發），在終點站折返、每隔固定週期重複的時刻表（Phase 4 Stage Q1），服務線路的資料與推導（Phase 4 Stage Q2a），依線路自動派車（Phase 4 Stage Q2b），交路與快慢車等服務模式、各段共用的容量（Phase 4 Stage Q3），道岔與平面交叉、列車佔用的軌道資源、區段與股道數（Phase 4.5 Stage S1），以及多格車站、月台股道與多節列車（Phase 4.5 Stage S2）；App 以最小的工程畫面（Train 工具，Phase 3 Stage M）操作列車，並有線路面板（Stage R：線路、交路與快車、各等級的列車數與班距、覆蓋缺口）與列車的服務狀態（早到或誤點）。**尚未**有號誌與待避、乘客或城市模擬。

App 目前能做到：

- 顯示 `GameWorld` 的真實地圖（預設 32 × 24），空地 / 鐵軌 / 車站以不同形狀繪製；可捲動、縮放
- 點選格子，顯示座標與內容
- 工具：選取、鋪軌、建站、拆軌；以 N / E / S / W 開關、常用形狀（直線、彎道、T 字、十字）與旋轉選擇鐵軌連接方向
- 建設透過 GameCore 指令執行；失敗時顯示玩家看得懂的訊息，世界不變
- HUD：現金、遊戲時間（`Day 1 · 08:30`）、暫停 / 1× / 2×
- `GameSession` 的 game loop 把真實時間換算成整數 tick 推進遊戲時間與列車；App 不在前景作用中（背景、控制中心、App 切換器）時停止，回來不補跑
- Train 工具：購買列車、放置在選取的鐵軌格（選朝向）、設定 rate、把列車送到選取的鐵軌格或車站（GameCore 求路後原封不動提交為 continuation；到不了時什麼都不改）、反向、取下；顯示 GameCore 記錄的位置、剩餘路徑、rate 與停在哪些車站，地圖在列車的權威位置畫出列車（每個 tick 跳一步，不插值）

GameCore 目前能做到：

- 建立指定尺寸的方格地圖（1…1024 × 1…1024）
- 鋪設 / 拆除鐵軌（每格記錄連接方向，只能是北、東、南、西；不要求與鄰格相接）
- 查詢鐵軌連通：由地圖推導相鄰鐵軌是否雙向相接（`connectedNeighbors(of:)`、`isConnected(_:to:)`）
- 建造車站（唯一、可保存的 Station ID）
- 購買列車（新車未放置）；把列車放到鐵軌格中心或兩格相接鐵軌之間、取下、原地反向（`placeTrain`、`unplaceTrain`、`reverseTrain`；每條連結 1024 單位）
- 列車移動：設定 rate（每遊戲分鐘的邏輯單位）與明確的 continuation（`setTrainMovementRate`、`setTrainContinuation`），隨時間逐步沿指定路徑前進；不自動選路。前方鐵軌被拆時等待，補回後自動續行
- 路徑搜尋：`route(from:to:)` 找出到目的地鐵軌格的最短、不折返路徑（同長時依北、東、南、西順序），結果可直接交給 `setTrainContinuation`；只查詢、不改變世界
- 停站：車站旁（正北、東、南、西）的鐵軌格是月台（`platforms(of:)`）；`route(from:toStation:)` 找出到最近月台的路徑；列車在月台格中心、行程結束時停在該站（`stationsStoppedAt(by:)`）。都由狀態推導，不另存
- 時刻表：每台列車有依序的停靠（車站、排定的到達與離開，開局以來的遊戲分鐘），以 `setTrainTimetable` 整份替換；時間不倒流、車站必須存在。時刻表本身是計畫資料，只有明確啟動的服務會讀它
- 時刻表服務：`startTrainService` 讓停在第一站的列車依時刻表跑一次（`stopTrainService` 結束）。列車不會早於排定出發時刻離開，也不另加停留時間；已停在下一站時零距離到達，沒有路就等待，最後一站停到排定出發才結束。執行進度（第幾個停靠）是存檔的權威狀態；執行中不能手動改路、反向、取下或換時刻表
- 折返與重複：停靠可以標記「在這站折返」，服務離開時先讓列車原地反向（找不到路時不反向），讓列車能從死路的終點站往回開。時刻表可以每隔固定週期重複（`setTrainTimetable(_:to:repeatingEvery:)`），一輪接一輪執行，執行進度同時記錄第幾輪；重複的服務從下一個準時的輪次開始
- 服務線路：依序的車站、營運時間，以及尖峰／離峰／低峰各跑幾台列車或目標班距；世界的服務日決定每分鐘是哪個等級。由地圖推導線路的來回行程、最多列車數（最短班距 2 分鐘）、實際列車數與班距
- 自動派車：用 `assignTrain` 把列車交給線路後，線路每分鐘檢查一次：營運中、這個等級有車要跑、距上次發車已過一個班距、跑車中的列車少於該等級的列車數時，就讓停在第一站的列車跑一個來回（產生該趟的時刻表並啟動服務）。列車回到第一站後原地折返等待，減車時多出的列車就停在那裡；線路的列車不能手動設定時刻表或啟停服務
- 整數金額的資金與建設成本
- 可暫停、1x、2x 的 deterministic 遊戲時鐘（2x 為每 tick 兩個基本步長；時間溢位時整批拒絕）
- 所有核心狀態可 `Codable` 編碼 / 解碼

### 建設規則

| 動作 | 條件 | 成本 |
| --- | --- | --- |
| 鋪軌 | 位置在地圖內、該格為空、至少一個連接方向（只能是北、東、南、西）、資金足夠；不需要與鄰格相接 | `ConstructionCosts.track` |
| 拆軌 | 該格必須是鐵軌（空格與車站都會被拒絕），且沒有列車停在該格或以該格為所在連結的一端 | 免費，**不退款** |
| 建站 | 名稱非空白、位置在地圖內、該格為空、資金足夠 | `ConstructionCosts.station` |
| 購買列車 | 名稱非空白、資金足夠 | `ConstructionCosts.train` |
| 放置列車 | 列車存在且未放置；位置是鐵軌格中心，或兩格相接鐵軌之間 `0 < offset < 1024` | 免費 |
| 取下 / 反向列車 | 列車存在且已放置 | 免費 |
| 設定 rate / continuation | 列車存在且已放置；rate 非負；continuation 從列車前方節點起每一步都相接、不折返 | 免費 |
| 設定時刻表 | 列車存在（放置與否皆可）且不屬於任何線路；時間從 0 起不倒流（每站 arrival ≤ departure ≤ 下一站 arrival）；每站都是存在的車站；`[]` 清除 | 免費 |
| 指派列車到線路 | 列車與線路存在；列車不屬於任何線路，也沒有自己的服務在執行 | 免費 |

任何失敗都會丟出 `GameError`，且世界狀態（地圖、資金、車站、列車與時刻表）完全不變。餘額永遠不會因建設變成負數。

## 技術方向

- Swift 6（language mode 6）
  - 最低 Swift tools version：6.0（`swift-tools-version: 6.0`）
  - CI 驗證最低版本 6.0 與目前穩定版 6.4；介於兩者之間的版本（例如 iPad Swift Playgrounds 的 6.2.x）不另外驗證
- Swift Package Manager
- XcodeGen（由 `RailwayGameApp/project.yml` 產生 Xcode 專案，產生結果提交進版控）
- SwiftUI（Presentation；Phase 2B prototype UI，iOS 17+，iPhone / iPad）
- SpriteKit / Metal（Rendering，未來依效能需求評估）

## Architecture

| 層 | 狀態 | 職責 |
| --- | --- | --- |
| **GameCore** | ✅ 本階段 | 權威遊戲狀態與規則；不依賴任何 UI / rendering framework |
| Presentation | ✅ Phase 2B prototype UI | `GamePresentation`（session、tick 換算、顯示文字）與 SwiftUI 介面、輸入、HUD |
| Rendering | 未開始 | 地圖與列車的繪製、動畫 |

Presentation 與 Rendering 只讀取 GameCore 狀態並送出指令，不持有另一份遊戲真實狀態。App 以 SwiftUI `@State` 持有唯一一個 `GameSession`，由它持有唯一一份 `GameWorld` 並執行所有指令與 game loop。詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，未來規劃見 [docs/ROADMAP.md](docs/ROADMAP.md)。

Swift 版 GameCore 是目前的參考實作；`GoldenScenarios/` 的 JSON 情境把它的行為寫成與語言無關的 fixture，GameSession 則是可替換的平台 shell。是否移植到 Unity / Godot 尚未決定；目前只保留逐一子系統移植並以同一批情境驗證的路徑（ARCHITECTURE 決策 13）。

```
Sources/GameCore/
  World/     GameWorld、GridMap、GridPosition、MapTile/TileType、GameError
  Railway/   TrackDirection/TrackConnections、Track、TrackConnectivity（連通查詢）、Station、Train、TrainPosition、TrainMovement、TrainRoute（路徑搜尋）、StationStop（月台與停站）、Timetable（ScheduledStop）、TimetableExecution（服務的執行進度）
  Economy/   Money、GameEconomy、ConstructionCosts
  Time/      GameClock、GameSpeed、GameTime
Sources/GamePresentation/
  GameSession（持有 GameWorld、UI 暫時狀態、game loop）、TickAccumulator、
  ConstructionTool / TrackPiece、MapScale、DisplayText（玩家看到的文字）
Tests/GameCoreTests/
Tests/GamePresentationTests/
GoldenScenarios/  可移植的 golden scenario（JSON，schema 見該目錄的 README）
RailwayGameApp/
  project.yml   XcodeGen spec（專案設定的唯一來源）
  RailwayGame.xcodeproj  由 project.yml 產生並提交（Xcode Cloud 需要），不要手改
  Resources/    Assets.xcassets（App Icon）
  App/          RailwayGameApp（@main，持有 GameSession）、DemoLayout（僅 Debug，截圖用）
  Views/        ContentView、HUDView、MapView / TileArt、ControlPanel、TrackPieceEditor、TrainControls
```

## 開發流程（cloud-first）

不需要自己的 Mac，也不依賴 Swift Playgrounds：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions macOS (Xcode / Simulator) → 截圖 artifact → 在 iPhone / iPad 上檢視
```

| 層 | 在哪裡跑 | 驗證什麼 |
| --- | --- | --- |
| 1. Claude Code Cloud | Linux 容器 | 原始碼開發；GameCore `swift build` / `swift test`。**沒有** Xcode、Simulator、SwiftUI / UIKit |
| 2. Linux CI（`ci.yml`） | 每次 push / PR | GameCore 與 GamePresentation 在 Swift 6.0、6.4 的 build（warnings as errors）與 test；property 測試只在 6.4 執行 |
| 3. iOS App Build（`ios-build.yml`） | macOS runner，PR 與 `main` 自動執行（純文件變更略過） | 已提交的 Xcode 專案與 `project.yml` 一致、shared scheme 可被 Xcode Cloud 找到；以真正的 Xcode / Apple SDK 為 iOS Simulator 編譯 SwiftUI App 與 GameCore；不需簽章 |
| 4. Visual Smoke（`visual-smoke.yml`） | macOS runner，**手動**觸發 | 在 iPhone 與 iPad Simulator 啟動 App、確認沒有閃退、截圖並上傳為 artifact（新遊戲畫面，以及 Debug 限定的 `-demo-layout` 示範配置） |
| 5. Release Archive（`release-archive.yml`） | macOS runner，手動觸發；修改專案設定或 App 資源的 PR 自動執行 | 以 Release、真實 iOS 裝置 SDK 封存並檢查 App（**未簽章**：不代表簽章、上傳或 TestFlight 會成功） |
| 6. TestFlight Checks（`testflight-checks.yml`） | Linux + macOS runner；修改 TestFlight workflow 或腳本的 PR 自動執行 | 發佈腳本的 lint 與測試、macOS dry run、合成 IPA 檢查；只用假值，不需 Apple 帳號，不簽章、不上傳 |
| 7. TestFlight（`testflight.yml`） | macOS runner，**只能從 `main` 手動**觸發 | 簽章 Archive → 匯出 IPA → 檢查 → 上傳 App Store Connect → 內部 TestFlight；需要 environment `testflight` 的 secrets |

- **Swift Playgrounds**：可選，不是必要的開發或驗證環境。
- **TestFlight / 實機安裝**：以 GitHub Actions（`testflight.yml`）Archive、簽章、上傳，發佈到**內部** TestFlight，不需要 Mac。
  - Workflow 與不需帳號的驗證已完成；真實簽章與上傳要等 Apple Developer Program 生效、設定 API key 後才能執行。步驟與狀態見 [docs/TESTFLIGHT_GITHUB_ACTIONS.md](docs/TESTFLIGHT_GITHUB_ACTIONS.md)。
  - 簽章以 App Store Connect API key 自動完成；repository 不含、也不提交任何憑證、描述檔或金鑰。
  - Xcode Cloud 暫緩（[docs/XCODE_CLOUD_ONBOARDING.md](docs/XCODE_CLOUD_ONBOARDING.md)）。

### 在 iPhone / iPad 上查看截圖

1. GitHub → **Actions** → 左側選 **Visual Smoke** → **Run workflow**（選擇分支）→ **Run workflow**
2. 等待執行完成
3. 打開該次執行的 Summary 頁面 → **Artifacts** → 下載 **visual-smoke**
4. zip 內含 `iphone.png`、`ipad.png`（新遊戲）、`iphone-demo.png`、`ipad-demo.png`（示範配置：以一般 GameCore 指令、照常付費建好的鐵軌與車站，以及用 Train 工具購買、放置並送出、正在行駛的一台列車）、`simulator.log`、`xcodebuild.log`、`simulators.txt` 與 App 的 stderr（`*-app-stderr.log`）；失敗時另附 crash report

Artifact 只保留 7 天。只有在 workflow 檔已經存在於 `main` 時，GitHub 才會顯示 **Run workflow** 按鈕；修改 Visual Smoke workflow 或其腳本的 PR，每次推送都會自動執行。

## Building

GameCore（任何有 Swift 6 的環境，包括 Linux）：

```sh
swift build
```

iOS App（需要 macOS + Xcode 16 以上；上傳 App Store Connect 的 build 需要 Xcode 26 以上，由 GitHub Actions 的 `testflight.yml` 建置）：

```sh
open RailwayGameApp/RailwayGame.xcodeproj
```

`RailwayGame.xcodeproj` 由 `project.yml` 以 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 產生，並**提交進版控**：Xcode Cloud 要求專案與 shared scheme 持續存在於 repository。專案設定一律改 `project.yml`；改了設定，或新增、刪除、改名 App 的原始檔或資源後，重新產生並一起提交：

```sh
xcodegen generate --spec RailwayGameApp/project.yml
```

- 使用 `.github/actions/setup-xcodegen/action.yml` 固定的 XcodeGen 版本；Linux（Claude Code 工作階段）從同一版本的原始碼建置，步驟見 `CLAUDE.md`。
- 在名為 `railway-game-ios` 的資料夾（`git clone` 的預設名稱）中執行：資料夾名稱會寫進專案。
- 不要手改 `.xcodeproj`，也不要在 Xcode 的專案編輯器（例如 Signing & Capabilities）修改設定。`ios-build.yml` 會重新產生並比對，不一致就失敗，並附上預期專案的 `regenerated-xcodeproj` artifact。
- Xcode Cloud 寫入的 `xcshareddata/xcodecloud/manifest.json` 與日後的 `Package.resolved` 要提交；重新產生專案時它們會被保留。

## Testing

```sh
swift test
```

`swift test` 會執行 GameCore 與 GamePresentation 的測試。兩者都只使用 Swift 標準函式庫（GamePresentation 另用標準函式庫的 `Observation`），因此可在 macOS、iOS 與 Linux 上建置。CI 在 Linux 上以 Swift 6.0（最低版本）與 6.4（目前穩定版）執行 build 與 test。佔去大部分測試時間的 property 測試（`*PropertyTests`、`KernelDifferentialTests`、`SaveMutationTests`）只在 6.4 執行：它們檢查的是邏輯，不因編譯器版本而不同。6.0 仍會編譯所有測試，並執行其餘的測試（包括 golden scenario）。

GameCore 測試也會執行 `GoldenScenarios/` 裡的每個情境，並與檔案中手寫的預期結果比對。測試只讀取 fixture、從不寫回；預期值改變代表遊戲行為改變，必須在 PR 中說明。

另有 deterministic 的 property 測試（`*PropertyTests`、`WorldStateMachineTests`、`TrainSessionPropertyTests`）：以固定的 seed（SplitMix64，`Tests/GameCoreTests/PropertySupport.swift`）產生地圖、列車位置、路徑與指令序列，和獨立寫成的參考模型（逐單位移動、另一種最短路徑算法、窮舉所有最短路徑）及世界不變量比對。CI 每次都跑同一批 seed，不會隨機挑選；失敗訊息會寫出 suite、seed、case 編號與產生的參數。

- `KernelDifferentialTests`：同一串產生的指令同時交給 GameCore 與另外重寫的整個核心（`ReferenceWorld`：格子存在字典裡、每一步的移動以除法一次算出且每分鐘都逐步執行、路徑以鬆弛法求出），每個指令之後比對結果（包括錯誤種類與檢查順序）與所有可觀察的狀態（時間、金額、每一格、車站、列車、連通、月台、停站），並檢查停站只因決策 18 列出的指令開始或結束。失敗時先把指令序列縮到仍會失敗的最少指令，再連同 seed 與 case 回報。參考模型本身也要通過所有 golden scenario（`ReferenceWorldGoldenTests`）。
- `SaveMutationTests`：把產生的世界存檔後改掉 JSON 裡的一個值（數字、名稱、key、陣列元素、`null`），壞資料必須被拒絕；讀得進來的世界必須維持所有不變量、能再次存讀，之後的指令也維持原子性。另一組優先改動時刻表裡的值（沒有車站或列車的世界沒有時刻表可改）。
- `ServicePropertyTests`：在上面的指令序列中混入從停靠車站開始的時刻表、服務的啟動與停止與長短不一的推進，同時與參考模型比對（參考模型逐分鐘步進、沒有快轉、每次出發都重新求路），並檢查每次 `advance(n)` 等於 n 次 `advance(1)`、2× 等於兩倍的 1×，以及服務的不變量。`SaveMutationTests` 另有一組專門改動或寫入 `execution` 的變異存檔。
- `LineDispatchPropertyTests`（`line.dispatch`）：在小型路網上建立有列車的線路，混入目標班距、列車數、營運時間、服務日的改變、指派與取回、手動移動列車與拆鋪軌，和長短不一的推進，逐步與參考模型比對（參考模型每分鐘檢查每條線路的派車），並檢查每次 `advance(n)` 等於 n 次 `advance(1)`、2× 等於兩倍的 1×，確認快轉不會跳過任何派車。`SaveMutationTests` 另有一組改動線路列車、目標班距、上次發車與服務的變異存檔。
- `TimetablePropertyTests`：在上面的指令序列中混入合法與不合法的時刻表，同時與參考模型比對（錯誤種類與順序、被拒絕時世界不變、只改變該列車的時刻表），並讓同一串指令在從不設定時刻表的雙胞胎世界上執行：清除時刻表後兩者必須完全相同，證明時刻表不影響移動、路徑、停站、資金、時間與 ID。

```sh
PROPERTY_STRESS=20 swift test --filter PropertyTests                       # 本機多跑 20 組衍生的 seed
PROPERTY_REPLAY=route.reference@5EEDA001@17 swift test --filter RoutePropertyTests   # 只重跑一個失敗的 case
PROPERTY_REPLAY=kernel.differential@5EEDA002@3 swift test --filter KernelDifferentialTests   # 同上，會印出縮減後的指令序列
```
