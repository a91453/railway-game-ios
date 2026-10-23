# Along the Line

Along the Line（沿線）是一款鐵路與城市發展模擬遊戲，以 iPhone / iPad 為主要平台。玩家規劃鐵路、車站與運輸網路，而城市會沿著交通建設逐步成長。核心概念：「鐵路是原因，城市是結果。」長期目標是玩法深度接近《A列車》系列的原生 Apple 平台遊戲。

正式名稱：English **Along the Line**、繁體中文 **沿線**。App 顯示名稱由 `project.yml` 的英文預設值與 `Resources/{en,zh-Hant}.lproj/InfoPlist.strings` 設定；畫面字串在 String Catalog 與 GamePresentation 的文字裡（繁體中文與英文，決策 38）。日文在 #171 移除。內部 `RailwayGame` target、scheme、module、Bundle ID 與存檔識別碼保留。

AppIcon 使用定稿 package 的兩張原始 1024×1024 PNG：Any／Default 為 `along-the-line-app-icon-light.png`（米白背景），Dark 為 `along-the-line-app-icon-dark.png`（深色原稿）。iOS／iPadOS 18 以上依主畫面 icon appearance 選擇；較早版本使用預設淺色版。沒有自訂 Tinted variant，由系統生成；SVG 與 preview 不放入 App bundle。

## 目前狀態

**早期開發，內部 TestFlight 0.5.0。** 2026-10-12 起功能凍結，正在修 bug。

- 現況、已有的系統、各內容開了哪些規則、文件地圖與決策索引：[docs/OVERVIEW.md](docs/OVERVIEW.md)
- 下一步做什麼（唯一的優先順序），以及機廠、行駛時間、比例、車站商業的可行性：[docs/research/NEXT_PRIORITIES_2026-10-12.md](docs/research/NEXT_PRIORITIES_2026-10-12.md)
- 規則細節：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)（決策 1–189）

玩家現在能做的事，簡單說：

- 在空白地圖或真實台灣（任意地點或全島）上鋪軌：自由角度、曲線、高架、橋、隧道、坡度與縱斷面
- 設站、加月台、轉乘；建立路線，依班距自動派車；快車、區間、環狀線、真實班次
- 自動行車控制：進路預約、跟車、待避與交會、死結解除
- 經營公司：票價、貸款、折舊、稅、各路線損益、公司建物與子公司、貨運與建材、觀光
- 看城市沿著車站成長；挑戰、歷史情境、每週挑戰、城市委託、成就
- 從開始畫面進教學（19 步）或三種示範（示範地圖、平溪線、高鐵）

## 著作權

著作權所有（[LICENSE.md](LICENSE.md)）。這個儲存庫公開供閱覽，未經授權不得重製、改作、散布，或用來上架任何 App；自帶授權的檔案與第三方資料依各自的授權，從 OpenStreetMap、Overture Maps 整理出的資料檔依 ODbL 1.0 提供。

## 架構

| 層 | 職責 |
| --- | --- |
| **GameCore**（`Sources/GameCore/`） | 唯一的權威遊戲狀態與規則。全整數、決定論、值語意，不 import Foundation，也不依賴任何 UI |
| **GamePresentation**（`Sources/GamePresentation/`） | 和平台無關的畫面邏輯：`GameSession`、tick 換算、文字、圖層、教學、存檔庫、示範與劇本。可在 Linux 測試 |
| **App**（`RailwayGameApp/`） | SwiftUI 介面。地圖是 SwiftUI Canvas，背景是 Apple 地圖或自製的 OSM 底圖（MapLibre）。官網的 3D 城市（`Web/CityView`）不讀遊戲狀態 |

Presentation 只讀取 GameCore 的狀態並送出指令，不持有另一份遊戲狀態。App 持有唯一的 `GameSession`，由它持有唯一的 `GameWorld`。詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

Swift 版 GameCore 是參考實作；`GoldenScenarios/` 的 JSON 情境把它的行為寫成與語言無關的 fixture（ARCHITECTURE 決策 13）。

```
Sources/GameCore/
  World/      GameWorld、WorldBounds、GameError、SavedGame（帶版本的存檔）、GeoAnchor、MapExpansion
  Geometry/   整數世界座標（64 單位一公尺）、軌道曲線與縱斷面、淨空與線間距
  Railway/    路網、車站、月台、列車、行駛曲線、時刻表、路線與派車、進路預約、死結、彈性派車
  Passenger/  需求、選路、上下車、轉乘、假日、天氣、觀光、高鐵、城鎮成長
  Economy/    金額、帳本、票價、營運成本、資產、目標、各路線帳、委託
  City/       土地、地形、城市建物、分區、地價、公司建物、子公司
  Freight/    貨運與建材
  Time/       GameClock（暫停、1×–6000×）
Sources/GamePresentation/   GameSession、GameLauncher、SaveLibrary、NewGame、教學、示範與劇本、地圖圖層、文字
Tests/                      GameCoreTests、GamePresentationTests
GoldenScenarios/            golden 情境（schema 見該目錄的 README）
SaveFixtures/               每個存檔版本的回歸存檔
ReplayFixtures/             指令紀錄與狀態檢查碼
RailwayGameApp/
  project.yml               XcodeGen spec（專案設定的唯一來源）
  RailwayGame.xcodeproj     由 project.yml 產生並提交，不要手改
  App/、Views/、UITests/、Resources/（圖示、字串、音效、底圖、真實鐵路與實景資料）
Web/                        CityView（官網的 3D 城市）、WasmProbe（GameCore 編成 Wasm 的探針）
tools/                      產生資料的腳本（人口、底圖、真實鐵路與班次、地名、觀光、音效、golden 檢查）
docs/                       總覽、架構與決策、研究、手冊；封存在 docs/archive/
```

## 開發流程（cloud-first）

不需要自己的 Mac，也不依賴 Swift Playgrounds：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions（Linux 測試、macOS 以 Xcode 編譯）→ 內部 TestFlight → 在 iPhone / iPad 實機上檢視
```

| 層 | 在哪裡跑 | 驗證什麼 |
| --- | --- | --- |
| 1. Claude Code Cloud | Linux 容器 | 原始碼開發；GameCore `swift build` / `swift test`。**沒有** Xcode、Simulator、SwiftUI / UIKit |
| 2. Linux CI（`ci.yml`） | push 到 `main`（和最近一輪成功的 `main` push run 的 commit 比，改到會影響 Swift package 的檔案就全跑）與手動執行跑全部分片；**PR 依改動分層**（決策 185，`swift-shards.sh plan`）：改 GameCore、Package、CI 腳本或被其他測試檔共用的測試檔 → 全部分片；只改 GamePresentation、它的測試或 App 內附資料 → 所有 GamePresentation 測試（分 3 個 job）；只改 golden／存檔／replay → 讀它們的測試類；只改 GameCoreTests 裡沒被別的檔用到的測試檔 → 那些測試類；混合時取聯集；label `full-ci` 強制全跑（加上 label 就會重跑）；都不影響時跳過。`Swift CI (gate)` 一定回報（`main` 的分支規則要求它，名稱不能改）。`main` 的 push run 共用一個 concurrency group：連續合併時只跑正在跑的那輪與最新的一輪，中間被取代的顯示 cancelled、沒有自己的判定，紅燈時手動 `workflow_dispatch` 那些 commit 來二分 | 只用 Swift 6.4：warnings as errors 的 build 與**全部**測試，包含 property / differential / mutation campaign（不減量，分成多個平行 shard）；PR 的建置也是全部、warnings as errors，只是測試依分層 |
| 3. iOS App Build（`ios-build.yml`） | macOS runner，PR 自動執行（App 看不到的變更略過：文件、套件測試與 fixture、`Web/`、`tools/`、`.claude/`、其他 workflow）；合併到 `main` 後由 `ios-full-lane.yml` 啟動完整 lane，最多每 3 小時一次（`main` 最新的 commit 已經跑過、或 3 小時內跑過就跳過；它的排程只是備援，GitHub 常延遲數小時或不跑），每晚與手動也跑 | 已提交的 Xcode 專案與 `project.yml` 一致、shared scheme 可被 Xcode Cloud 找到；以真正的 Xcode / Apple SDK 為 iOS Simulator 編譯 SwiftUI App 與 GameCore；iPhone UI 測試與 iPad 教學 UI 測試（兩個平行 job，各用自己的 Simulator）；iPhone job 也用 Xcode 匯出字串檢查繁體中文翻譯（2026-10-09 前是獨立的 `localization.yml`）；不需簽章。PR 只跑精簡的擋關清單（開始畫面、三個工具的中英文、開始／存檔／繼續、教學的前幾步），iPad 只在改到教學本身的檔案（`Views/Tutorial*`、`TutorialUITests`、`GamePresentation/Tutorial*`）時跑，教學會指到的其他畫面交給完整 lane；完整 lane（每 3 小時、每晚、手動）跑全部 UI 測試與 iPad 教學測試，每晚與手動選擇時加上「拿掉按鈕要失敗」的證明，這條線紅燈不擋 PR |
| 4. Release Archive（`release-archive.yml`） | macOS runner，手動觸發、每晚在 `main` 執行；修改 `project.yml`、App 進入點、asset catalog（`Assets.xcassets`）或 `*.lproj` 的 PR 自動執行（只改內附資料的 PR 不跑，由每晚那次涵蓋） | 以 Release、真實 iOS 裝置 SDK 封存並檢查 App（**未簽章**：不代表簽章、上傳或 TestFlight 會成功） |
| 5. TestFlight Checks（`testflight-checks.yml`） | Linux + macOS runner；修改 TestFlight workflow 或腳本的 PR 自動執行 | 發佈腳本的 lint 與測試、macOS dry run、合成 IPA 檢查、對假的 App Store Connect 測處理檢查與 What to Test；只用假值，不需 Apple 帳號，不簽章、不上傳 |
| 6. TestFlight（`testflight.yml`） | macOS runner，**只能從 `main` 手動**觸發 | Archive（預設 `adhoc`）→ App Store distribution 簽章匯出 IPA → 檢查 → 上傳 App Store Connect（**已在真實執行驗證**；匯出與上傳失敗時再試）→ Linux 上等 processing、回報結果、填 What to Test（2026-10-12 的 run #54 實際驗證：處理結果 VALID、What to Test 已填）；需要 environment `testflight` 的 secrets |

- **Swift Playgrounds**：可選，不是必要的開發或驗證環境。
- **TestFlight / 實機安裝**：以 GitHub Actions（`testflight.yml`）Archive、簽章、上傳，發佈到**內部** TestFlight，不需要 Mac。
  - 真實執行已驗證：Release Archive、App Store distribution 簽章匯出、IPA 檢查與上傳到 App Store Connect 都成功；沒有已註冊裝置的新團隊，`automatic` archive 會失敗，所以預設 `adhoc`。App Store Connect 的處理在 2026-10-12 的 run #54 驗證過（VALID）；測試者拿到 build 之前，App Store Connect 還要回答出口合規。TestFlight 安裝尚未有證據。步驟與狀態見 [docs/TESTFLIGHT_GITHUB_ACTIONS.md](docs/TESTFLIGHT_GITHUB_ACTIONS.md)。
  - 簽章以 App Store Connect API key 自動完成；repository 不含、也不提交任何憑證、描述檔或金鑰。
  - Xcode Cloud 暫緩（[docs/XCODE_CLOUD_ONBOARDING.md](docs/XCODE_CLOUD_ONBOARDING.md)）。

### 在 iPhone / iPad 上查看 App

畫面由專案擁有者以**人工**在實機檢查：`testflight.yml`（手動、只能從 `main`）上傳的 build 經內部 TestFlight 安裝到 iPhone / iPad 後自行查看。這是人工檢視，**不是**自動化的回歸測試。CI 的 UI 測試（`ios-build.yml`）在 Simulator 上操作 App 並判斷對錯，截圖只是附件讓人查看，缺了或改名都不會讓 CI 失敗，也沒有比對畫面；曾有的 Visual Smoke（手動 Simulator 截圖 artifact，不判斷任何事）已移除。

開始畫面的「示範地圖」（Stage C4，Release 與 TestFlight 也有）開啟一張用一般 GameCore 指令、照常付費建好的路網：地面的 1 號線、跨越它的高架 2 號線，以及繞著中央站的環狀線，列車都在營運，車站都有運量（`DemoWorld`）。另有平溪線與高鐵的實景示範。Debug build（例如在本機 Xcode 執行）也可以用啟動參數 `-demo-layout` 直接開啟它；Release build 不含這個啟動參數。

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

`swift test` 會執行 GameCore 與 GamePresentation 的測試。GameCore 只用 Swift 標準函式庫；GamePresentation 另用 `Observation`，有些檔案用 Foundation（讀資料檔、存檔），兩者都可在 macOS、iOS 與 Linux 上建置。CI 在 Linux 上只用 Swift 6.4 建置（warnings as errors）並測試（2026-10-05 起拿掉 Swift 6.0 job）：

- **Swift 6.4**：完整正確性驗證，執行**全部**測試，包含所有 campaign。campaign 的 seed、case 數與指令數都沒有減少；它們只是被分到多個平行 job（shard），等待時間是最慢的 shard，而不是全部相加。分法與「每個測試恰好在某一個 shard 跑過一次」的證明在 `.github/scripts/swift-shards.sh`：每個 shard 先確認各 shard 的選擇剛好切分 `swift test list` 的結果，跑完再確認實際執行的測試與選擇的完全相同。新增的測試類別不必改 CI，會落在 `rest` shard。
- 只改文件、App 或 TestFlight 檔案的 PR 與推到 `main` 的 commit 不會啟動這些 Swift job（`Swift CI (gate)` 仍會回報；`main` 跟推送前的 commit 比較，讀不到就全部跑）；手動執行一律全部跑。

GameCore 測試也會執行 `GoldenScenarios/` 裡的每個情境，並與檔案中手寫的預期結果比對。測試只讀取 fixture、從不寫回；預期值改變代表遊戲行為改變，必須在 PR 中說明。

另有 deterministic 的 property 測試（`*PropertyTests`、`WorldStateMachineTests`、`TrainSessionPropertyTests`）：以固定的 seed（SplitMix64，`Tests/GameCoreTests/PropertySupport.swift`）產生地圖、列車位置、路徑與指令序列，和獨立寫成的參考模型（逐單位移動、另一種最短路徑算法、窮舉所有最短路徑）及世界不變量比對。CI 每次都跑同一批 seed，不會隨機挑選；失敗訊息會寫出 suite、seed、case 編號與產生的參數。

- `KernelDifferentialTests`：同一串產生的指令同時交給 GameCore 與另外重寫的整個核心（`ReferenceWorld`：每一步的移動以除法一次算出且每分鐘都逐步執行、路徑以鬆弛法求出），每個指令之後比對結果（包括錯誤種類與檢查順序）與所有可觀察的狀態（時間、金額、世界的範圍、車站、列車、路網、月台、停站），並檢查停站只因決策 18 列出的指令開始或結束。失敗時先把指令序列縮到仍會失敗的最少指令，再連同 seed 與 case 回報。參考模型本身也要通過所有 golden scenario（`ReferenceWorldGoldenTests`）。
- `SaveMutationTests`：把產生的世界存檔後改掉 JSON 裡的一個值（數字、名稱、key、陣列元素、`null`），壞資料必須被拒絕；讀得進來的世界必須維持所有不變量、能再次存讀，之後的指令也維持原子性。另一組優先改動時刻表裡的值（沒有車站或列車的世界沒有時刻表可改）。
- `ServicePropertyTests`：在上面的指令序列中混入從停靠車站開始的時刻表、服務的啟動與停止與長短不一的推進，同時與參考模型比對（參考模型逐分鐘步進、沒有快轉、每次出發都重新求路），並檢查每次 `advance(n)` 等於 n 次 `advance(1)`、2× 等於兩倍的 1×，以及服務的不變量。`SaveMutationTests` 另有一組專門改動或寫入 `execution` 的變異存檔。
- `LineDispatchPropertyTests`（`line.dispatch`）：在小型路網上建立有列車的路線，混入目標班距、列車數、營運時間、服務日的改變、指派與取回、手動移動列車與拆鋪軌，和長短不一的推進，逐步與參考模型比對（參考模型每分鐘檢查每條路線的派車），並檢查每次 `advance(n)` 等於 n 次 `advance(1)`、2× 等於兩倍的 1×，確認快轉不會跳過任何派車。`SaveMutationTests` 另有一組改動路線列車、目標班距、上次發車與服務的變異存檔。
- `TimetablePropertyTests`：在上面的指令序列中混入合法與不合法的時刻表，同時與參考模型比對（錯誤種類與順序、被拒絕時世界不變、只改變該列車的時刻表），並讓同一串指令在從不設定時刻表的雙胞胎世界上執行：清除時刻表後兩者必須完全相同，證明時刻表不影響移動、路徑、停站、資金、時間與 ID。

```sh
PROPERTY_STRESS=20 swift test --filter PropertyTests                       # 本機多跑 20 組衍生的 seed
PROPERTY_REPLAY=network.differential@5EEDA001@17 swift test --filter ContinuousTrackPropertyTests   # 只重跑一個失敗的 case
PROPERTY_REPLAY=kernel.differential@5EEDA002@3 swift test --filter KernelDifferentialTests   # 同上，會印出縮減後的指令序列
```
