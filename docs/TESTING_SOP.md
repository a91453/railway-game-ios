# 測試作業程序：改了什麼、在哪裡測、報告怎麼寫

作者 2026-11-14 定下，之後每個 session 照這份選測法。怎麼裝工具、指令的完整參數在
[`MAC_LOCAL_SETUP.md`](MAC_LOCAL_SETUP.md)；CI 跑哪些工作在 `CLAUDE.md` 與
`.github/scripts/swift-shards.sh`。這份只回答「這個改動該用哪一種測法」。

## 1. 先看改的是哪一類

| 改的是 | 先用 | 再用 | 一定要實機的 |
| --- | --- | --- | --- |
| GameCore 規則、數值、存檔、效能（tick 時間、演算法） | 2.1 命令列 `swift test`／量測 | CI 該 tier | 沒有（除非要手機上的時間） |
| GamePresentation 的邏輯（選單列什麼、卡片放哪、文字） | 2.1（Linux 測試） | CI | 沒有 |
| SwiftUI 畫面、版面、觸控、動畫 | 2.2 iOS 模擬器，改前改後截圖 | CI 的 UI 測試、`website-screenshots.yml` | 手勢手感（作者 TestFlight） |
| 3D 外觀（模型、塗裝、場景） | 2.4 Mac 上跑（快看）→ 2.2 模擬器截圖 | 交總覽圖給作者或遊戲規劃 | 幀數、發熱 |
| 效能時間、記憶體、iCloud、Game Center、聲音 | 2.3 手機實機 | — | 全部 |

一個改動跨兩類就兩種都做。測不到的那一類，報告寫 UNVERIFIED，不跳過不提。

## 2. 四種測法

### 2.1 命令列（最快，沒畫面）

**何時用**：GameCore 與 GamePresentation 的規則、數值、存檔、重播、效能量測。
**在哪跑**：雲端 session 的 Linux（Swift 6.4，SessionStart hook 已裝）；需要時作者的 Mac 也行。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors     # 推之前一定跑，要乾淨
swift test --skip-build --filter <Class>                    # 改到的測試類別
.github/scripts/swift-shards.sh run <shard>                 # 改到某個 campaign 的行為時
```

量測（tick 時間、卡頓）用只在要求時才跑的報告測試，照 `.claude/skills/diagnosing-bugs` 與
`.claude/skills/economy-balance`；數字寫明是 Linux release，不是手機。

**報告**：跑過的寫「VERIFIED（Linux，`swift test --filter X`）」；整套交給 CI 的寫「其餘交給 CI」。

### 2.2 iOS 模擬器（UI、版面、3D 截圖）

**何時用**：畫面、面板、清單、圖表、版面、文字長度、3D 場景的樣子；CI 的 UI 測試也是模擬器。
**在哪跑**：作者的 Mac（雲端 session 用 Remote Control 借），或 GitHub 的 macOS runner
（`ios-build.yml` 的 `only_testing`、`website-screenshots.yml`）。

```sh
# 指令全文：MAC_LOCAL_SETUP.md §5
xcodebuild build-for-testing ... -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" ...
xcodebuild test-without-building ... -only-testing:RailwayGameUITests/<類別>[/<方法>]
```

- **改前改後各拍一張**，同一台模擬器（iPhone Pro，不是 Max；iPad 用最大的 iPad Pro）、同一個場景、同一個鏡頭。
  截圖要看的層級照 `.claude/skills/ui-review/SKILL.md`（決策 482 修正：純文字不拍、小改自己審、新畫面給遊戲規劃看）。
- 只想驗一兩個 UI 測試：用 `ios-build.yml` 的 `only_testing`，不要開 full lane。
- 模擬器的 fps 與記憶體**不算數**（在 Mac 的 GPU 上跑）。

**報告**：「VERIFIED（iPhone 17 Pro 模擬器，iOS 26.x，截圖附上）」；「實機手感 UNVERIFIED」。

### 2.3 手機實機（效能、記憶體、iCloud 的唯一準）

**何時用**：fps、主執行緒時間、記憶體峰值、發熱、iCloud 存檔同步、Game Center、聲音、觸覺。
**在哪跑**：作者的 iPhone（Xcode 直裝，MAC_LOCAL_SETUP.md §4；量測 §7 用 Release 與 Instruments），或 TestFlight。
雲端 session 自己碰不到手機，只能請作者跑，或列出「發版後在實機看」的清單。

**報告**：寫機型、iOS 版本、Debug／Release、場景、3D 畫質設定、fps 中位數與最低、記憶體峰值。
沒量的寫「實機 fps／記憶體 UNVERIFIED」，並在決策裡留著，讓作者可以挑（MAC_LOCAL_SETUP.md §7.3）。

### 2.4 iPhone App 直接開在 Mac 上（Designed for iPad）

**何時用**：快速玩一下、看 3D 場景、看面板內容；重新開起來約 4 秒（沒改程式時）。
**在哪跑**：作者的 Apple silicon Mac：`tools/mac-run/run_on_mac.sh`（MAC_LOCAL_SETUP.md §8）。

**不能取代模擬器和實機**：它是 iPad 的版面、滑鼠不是觸控、Mac 的顯示晶片強很多（fps 與記憶體不能當手機數字）、
iCloud 可能和手機是同一份存檔（兩邊同時開可能互蓋，不用時關掉 Mac 上的）。
所以它只當「先看一眼」，交出去的截圖仍用 2.2，效能仍用 2.3。

**報告**：「Mac（Designed for iPad）上看過」不算 iPhone 版面的 VERIFIED。

## 3. 報告的寫法（每個 PR、每份交接）

- **VERIFIED**：真的跑過，寫在哪裡跑、跑了什麼（指令、機器、截圖）。
- **UNVERIFIED**：沒跑的寫出來，並寫原因，例如「UNVERIFIED LOCALLY — requires macOS/Xcode CI」、
  「實機 fps UNVERIFIED」。靜態讀程式不算執行驗證。
- 每份報告最後一行列「沒在裝置上驗證的」：至少寫 iPhone 實機有沒有看過。

## 4. 本機已經把關過，CI 要不要放寬（2026-11-14 評估）

作者問：本機做過嚴格檢查的 PR，CI 能不能放寬。結論是**檢查本身不放寬**，理由：

- `main` 的分支規則只認 CI 的 `Swift CI (gate)`；本機的結果別人看不到、也不能重現，沒辦法當合併的依據。
- 本機跑的是改到的類別，CI 跑的是改到的檔案會影響的整個 tier；兩者不重複的部分正是本機漏掉的。

「讓 CI 變快」的做法大多已經在跑，不必另開：

| 想法 | 現況 |
| --- | --- |
| 只改文件時跳過 iOS 建置 | 已有：`ios-build.yml` 的 `paths-ignore`（`docs/**`、最上層的 `*.md`、`Tests/**`、fixtures、`tools/**`、`.claude/**`、其他 workflow） |
| 只改文件、App 程式時跳過 Swift | 已有：`swift-shards.sh plan` 的 `none` tier |
| 依改動路徑只跑相關測試 | 已有：tier（`tests-only`、`fixtures`、`presentation`、`full`），決策 185 |
| 同一份改動 iOS 已綠就不再跑 | 已有：`ios-build.yml` 認出同一改動已通過就跳過 macOS 工作（決策 187） |
| 合併不自動跑 full lane | 已有：決策 582 |

五方評分（權重照 NEXT_PRIORITIES §19）：再做一層「本機已驗就略過 CI」是開發 2（gate 會失去意義、
本機結果無法重現）、玩家 1、美術 1、鐵道迷 1、音樂 1，加權約 1.3，**不做**。
真正能省時間的是照第 1 節**選對測法**：純文字改動不拍截圖、不手動開 full lane、
只驗一兩個 UI 測試用 `only_testing`，以及推一次完整的改動、不要一段一段推（CLAUDE.md Workflow）。

## 5. 模擬器佔的磁碟（2026-11-14 作者的 Mac 約 59 GB）

模擬器的資料在 `~/Library/Developer/CoreSimulator/`（各台裝置的資料與 runtime），建置產物在
`~/Library/Developer/RailwayGameDerived-sim`、`RailwayGameDerived-mac` 與 Xcode 預設的 `DerivedData`。

**什麼時候清**：

- **Xcode 升級之後**：舊版 iOS runtime 的裝置變成 unavailable，直接刪。
- **一輪 UI 測試或截圖做完**：每次跑測試會留下 app 資料與 `.xcresult`；想要下一輪從乾淨開始就抹掉。
- **剩餘空間低於約 50 GB**：先清 unavailable 與舊 runtime，再清 DerivedData。
- **不要在 session 正在建置或跑測試時清**，會讓它失敗。

**怎麼清**（從輕到重；每一步都可以重新產生，不會動到 repo 與存檔以外的東西）：

```sh
du -sh ~/Library/Developer/CoreSimulator ~/Library/Developer/RailwayGameDerived-* ~/Library/Developer/Xcode/DerivedData 2>/dev/null
xcrun simctl delete unavailable          # 1. 舊版 runtime 留下的裝置
xcrun simctl runtime list                # 2. 看裝了哪些 iOS runtime
xcrun simctl runtime delete <版本或ID>   #    只留和 CI 同版的那一個（MAC_LOCAL_SETUP.md §1）
xcrun simctl shutdown all && xcrun simctl erase all   # 3. 抹掉所有模擬器裡的 App 資料（裝置留著）
rm -rf ~/Library/Developer/RailwayGameDerived-sim ~/Library/Developer/Xcode/DerivedData   # 4. 建置產物；下次要從頭編譯
rm -rf ~/ui-smoke.xcresult ~/screenshots.xcresult ~/attachments   # 5. 本機測試結果
```

第 3 步會清掉模擬器裡的遊戲存檔，要留的先匯出。第 4 步之後第一次建置會慢很多（從頭編譯），
所以只在空間不夠時做，不必每次。

**UNVERIFIED**：寫這份的 session 在 Linux，沒有在作者的 Mac 上量過各資料夾的大小，
也沒有跑過上面的指令；`simctl runtime` 的子指令依 Xcode 版本可能不同，第一次照做時對照 `xcrun simctl help runtime`。
