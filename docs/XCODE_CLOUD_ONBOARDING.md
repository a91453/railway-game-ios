# Xcode Cloud 首次啟用與內部 TestFlight 操作手冊

> **目前策略：Xcode Cloud 暫緩。** 優先路線是 GitHub Actions → 內部 TestFlight，不需要 Mac，見 [TESTFLIGHT_GITHUB_ACTIONS.md](TESTFLIGHT_GITHUB_ACTIONS.md)。
>
> 本手冊保留供日後使用，內容仍然有效：Xcode Cloud 的第一次 onboarding 仍需要一次在 Mac 上操作 Xcode。兩條路線共用同一份已提交的 Xcode 專案與 shared scheme。日後啟用 Xcode Cloud 時，再決定是否保留 GitHub macOS 的發佈 workflow。
>
> GitHub Actions 路線的 Team ID 放在 GitHub variable，不寫進 `project.yml`。下方步驟 4（把 `DEVELOPMENT_TEAM` 寫進 repository）只在啟用 Xcode Cloud 時需要。

目標：把這個原型 App 以 Xcode Cloud 建置、上傳 App Store Connect，並透過**內部** TestFlight 安裝到自己的 iPhone / iPad。外部 Beta（Beta App Review）與 App Store 上架都不是首次安裝的必要條件，本手冊不處理。

前提：主要使用 iPhone / iPad，**沒有自己的 Mac**。

Apple 官方文件查閱日期：**2026-09-28**（來源列在文末）。Apple 的畫面與選項名稱可能改變；與本手冊不一致時，以當時的官方文件為準。

## 目前狀態

| 項目 | 狀態 | 說明 |
| --- | --- | --- |
| Repository readiness | 已完成（PR #8；macOS 部分由 GitHub Actions 驗證） | 已提交的 Xcode 專案與 shared scheme、Release Archive 設定、App Icon、自動簽章設定、漂移檢查 |
| Apple 帳號 onboarding | **尚未開始，需要你操作** | Developer Program、Team ID、Bundle ID、App Store Connect app record、測試群組 |
| 簽章 Archive 與上傳（Xcode Cloud） | **尚未執行**（Xcode Cloud 暫緩） | `release-archive.yml` 的 Archive 是**未簽章**的，不能證明簽章或上傳。GitHub Actions 的 `testflight.yml` 已經真實簽章並上傳到 App Store Connect（見 TESTFLIGHT_GITHUB_ACTIONS.md），但那不是 Xcode Cloud |
| TestFlight 安裝 | **尚未有證據** | 需要 processing 完成與安裝 |

## 先知道的限制

- **第一個 Xcode Cloud workflow 必須在 Mac 上的 Xcode 建立。** Apple：「You need to configure your first Xcode Cloud workflow in Xcode」。第一次建置完成之後，才能在 App Store Connect 網頁（iPad 瀏覽器可用）建立或編輯 workflow、手動開始建置、看 log、下載 artifact。Linux、iPad、Swift Playgrounds 都無法完成首次設定；付費加入 Developer Program 也不會改變這點。
- 因此需要**一次性**使用一台可操作 Xcode 的 Mac（借用、朋友的、或你自己選擇的遠端 Mac 服務；本專案不代你購買或租用）。需求：Xcode 15 以上可以設定 Xcode Cloud，但 **App Store Connect 自 2026-04-28 起只接受以 Xcode 26 / iOS 26 SDK 以上建置的上傳**，所以 Xcode Cloud workflow 要選 Xcode 26.x（本機 Xcode 版本只影響設定畫面，建置在雲端進行）。預計使用 30–60 分鐘。
- Xcode Cloud 需要**持續存在於 repository 的 Xcode 專案**：「If you use a third-party tool that dynamically generates or edits your project or workspace, the initial configuration of Xcode Cloud and subsequent builds may fail.」所以本專案把 XcodeGen 產生的 `RailwayGame.xcodeproj` 與 shared scheme 提交進版控（見下方〈Repository 已完成的準備〉）。
- Apple Developer Program 會員含每月 **25 小時** Xcode Cloud 運算時間。初期只手動啟動建置，不讓每個 PR 都封存發佈。

## 你需要準備的資料（都不是秘密，不要提供密碼或驗證碼給任何人）

| 資料 | 在哪裡取得 | 用途 |
| --- | --- | --- |
| Team ID（10 個字元） | developer.apple.com → Account → Membership details | 寫入 `project.yml` 的 `DEVELOPMENT_TEAM`（它會出現在每個簽章過的 App 內，不是秘密） |
| Bundle ID 是否可用 | Certificates, Identifiers & Profiles → Identifiers | 預設 `io.github.a91453.RailwayGame`，**尚未確認已註冊** |
| App Store Connect 的 App 名稱 | 建立 app record 時決定 | 正式品牌為 Along the Line／沿線；商店名稱須符合 App Store 的唯一性要求，不影響 Bundle ID |

**絕對不要**把 Apple 帳號密碼、雙重認證碼、`.p12` / `.p8`、憑證、provisioning profile 或 token 貼到 issue、PR、聊天或 repository。Xcode Cloud 使用雲端管理的自動簽章，本專案不需要任何這類檔案。

## 步驟一覽

| # | 步驟 | 在哪裡做 |
| --- | --- | --- |
| 1 | 確認 Developer Program、角色、協議 | iPhone / iPad 瀏覽器 |
| 2 | 註冊 Bundle ID、取得 Team ID | 瀏覽器 |
| 3 | 建立 App Store Connect app record | 瀏覽器（或 App Store Connect App） |
| 4 | 把 Team ID 寫進 repository | Claude Code 工作階段或 PR（不需要 Mac） |
| 5 | 建立內部測試群組 | 瀏覽器 |
| 6 | 在 Mac 上開啟專案、建立第一個 workflow、授權 GitHub、第一次建置 | **Mac（一次性）** |
| 7 | 提交 Xcode Cloud 的 `manifest.json` | Mac 或瀏覽器 |
| 8 | 建立 TestFlight workflow、Release Archive、等待 processing | 瀏覽器（或在 Mac 上一併完成） |
| 9 | 回答出口合規、把 build 加入群組、在 iPhone / iPad 安裝 | 瀏覽器 + TestFlight App |
| 10 | 之後從 iPad 開發與發佈 | iPad |

### 1. Developer Program、角色與協議（瀏覽器）

1. 以 Account Holder 的 Apple Account 登入 developer.apple.com/account，確認 Apple Developer Program 會員有效（不是免費的 Apple Account 開發者身分）。
2. 你的角色要能建立 app record 與使用 Xcode Cloud：Account Holder、Admin 或 App Manager。
3. 若網頁或 App Store Connect 顯示有待同意的協議，由 Account Holder 同意。**免費 App** 依 Apple Developer Program License Agreement 發佈；只有收費或 In-App Purchase 才需要 Paid Apps Agreement，本輪不需要。

### 2. Team ID 與 Bundle ID（瀏覽器）

1. developer.apple.com/account → Membership details → 記下 **Team ID**。
2. Certificates, Identifiers & Profiles → Identifiers → 「+」→ App IDs → App：
   - Description：`Along the Line`
   - Bundle ID：**Explicit**，`io.github.a91453.RailwayGame`
   - Capabilities：全部不勾（App 目前沒有使用任何需要 entitlement 的功能）
3. 如果 Bundle ID 已被占用，改用其他值，並在步驟 4 一併修改 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`（之後 CI 裡寫死的 `io.github.a91453.RailwayGame` 檢查也要同步改）。

### 3. App Store Connect app record（瀏覽器）

Apple 的已知問題：團隊在 App Store Connect **還沒有任何 App 時，Xcode Cloud onboarding 會失敗**，解法是先手動建立 app record。所以在用 Mac 之前先做：

App Store Connect → Apps → 「+」→ New App：

| 欄位 | 值 |
| --- | --- |
| Platforms | iOS |
| Name | 正式名稱 `Along the Line`；繁體中文與日文為 `沿線`（須符合 App Store 的唯一性要求） |
| Primary Language | 你的主要語言 |
| Bundle ID | 選步驟 2 註冊的 `io.github.a91453.RailwayGame` |
| SKU | 任意唯一字串，例：`railwaygame-ios` |
| User Access | Full Access |

建立 app record 不會公開任何東西；沒有送審前不會出現在 App Store。

### 4. 把 Team ID 寫進 repository（不需要 Mac）

`project.yml` 是專案設定的唯一來源，產生的 `.xcodeproj` 也提交在 repository，兩者必須一致（`ios-build.yml` 會檢查）。所以**不要**在 Xcode 的 Signing & Capabilities 畫面選 Team，也不要只手改 `.xcodeproj`。

做法（擇一）：

- **Claude Code 工作階段（建議）**：請它「把 `DEVELOPMENT_TEAM` 設為 `<你的 Team ID>`，重新產生 Xcode 專案並開 PR」。它會在 `RailwayGameApp/project.yml` 的 target `settings.base` 加上 `DEVELOPMENT_TEAM: <Team ID>`，依 `CLAUDE.md` 的步驟在 Linux 上重新產生專案，再開 PR。
- **有 Mac 時**：安裝固定版本的 XcodeGen（見 `.github/actions/setup-xcodegen/action.yml`），編輯 `project.yml` 後執行 `xcodegen generate --spec RailwayGameApp/project.yml`，提交兩者。

PR 的 **iOS App Build** 通過（包含「Check the committed Xcode project matches project.yml」）後再 merge 到 `main`。

### 5. 內部測試群組（瀏覽器）

App Store Connect → Apps → 你的 App → TestFlight → Internal Testing 旁的「+」：

- 群組名稱：`Internal`
- 按 Invite Testers，勾選你自己。內部測試者必須是 App Store Connect 團隊成員，角色為 Account Holder、Admin、App Manager、Developer 或 Marketing；最多 100 人。
- 「Enable automatic distribution」可以勾，但 Apple 的說明寫明：**Xcode Cloud 產生的 build 必須手動加入群組**（見步驟 9）。

內部測試不需要 Beta App Review。

### 6. 在 Mac 上建立第一個 workflow（一次性）

1. Xcode → Settings → Accounts →「+」加入你的 Apple Account（在你的團隊內）。
2. Terminal：
   ```sh
   git clone https://github.com/a91453/railway-game-ios.git
   open railway-game-ios/RailwayGameApp/RailwayGame.xcodeproj
   ```
   打開的是 **`RailwayGameApp/RailwayGame.xcodeproj`**，不是根目錄的 `Package.swift`（那是 GameCore 套件，Xcode Cloud 不會把它當成 App）。
3. 只檢查、不修改：
   - Scheme 選單有 **RailwayGame**。
   - Target RailwayGame → Signing & Capabilities：「Automatically manage signing」已勾選，Team 顯示你的團隊（來自步驟 4），Bundle Identifier 為 `io.github.a91453.RailwayGame`。
   - 若 Xcode 提示「Update to recommended settings」，**不要**套用（它會修改產生的專案）。
4. Report navigator（⌘9）→ **Cloud** → **Get Started**。
5. Select a Product：選 **RailwayGame**（iOS App，`io.github.a91453.RailwayGame`）。清單也可能列出 GameCore、GamePresentation：那是本地套件的 library，不要選。若有多個團隊，選你要用來發佈 TestFlight 的團隊。
6. Review Workflow → **Edit Workflow**，改成下方〈Workflow 1：Build〉的設定後儲存。Apple 建議的預設是「每次 `main` 變更與每個指向 `main` 的 PR 都 Archive」，會消耗運算時間，所以改成手動啟動的 Build。
7. **Grant Access**：Xcode 會帶你到 GitHub 安裝 / 授權 Xcode Cloud 的 GitHub App。只授權 `a91453/railway-game-ios` 這一個 repository 即可；需要 repository 的 admin 權限（你是擁有者）。
8. App record：出現「Confirm Existing App」時，確認名稱與 Bundle ID 後按 Next（步驟 3 已建立）。
9. 選分支 `main` → **Start Build**。在 Report navigator 的 Cloud 或 App Store Connect → 你的 App → Xcode Cloud → Builds 觀察結果。
10. 第一次 Build 成功後，可以直接在這台 Mac 上繼續步驟 8（Report navigator 的 Cloud → 在產品上按 Control-click → Manage Workflows），或回到 iPad 用 App Store Connect 網頁做。
11. 用完之後：Xcode → Settings → Accounts 移除你的 Apple Account；刪除 clone 的資料夾；若在 Keychain 或瀏覽器留下 GitHub / Apple 的登入，一併登出或刪除。

### 7. 提交 `manifest.json`

Xcode 會把產品的中繼資料寫進 `RailwayGameApp/RailwayGame.xcodeproj/xcshareddata/xcodecloud/manifest.json`，Apple 要求把它推到 remote。

- 在 Mac 上：`git status` 應該**只有**這個檔案是新的。若 `project.pbxproj` 或 `.xcscheme` 也被 Xcode 改了，用 `git restore <檔案>` 還原，不要提交。然後開一個分支、只提交 `manifest.json`、push、開 PR。
- 或把檔案內容交給 Claude Code 工作階段，由它開 PR。

XcodeGen 重新產生專案時會保留這個檔案（已在 Linux 上以 XcodeGen 2.46.0 實測），漂移檢查不會把它當成差異。

### 8. TestFlight workflow 與 Release Archive

依下方〈Workflow 2：TestFlight Internal〉建立第二個 workflow（Mac 上的 Xcode，或 App Store Connect → 你的 App → Xcode Cloud → Manage Workflows →「+」，iPad 瀏覽器可用），然後：

1. App Store Connect → Xcode Cloud → 選 **TestFlight Internal** → Start Build → 分支 `main`。
2. 建置會 Archive（Release、真實 iOS 裝置 SDK）、以雲端管理的憑證簽章、上傳 App Store Connect。
3. 上傳後 App Store Connect 還要 **processing**（通常數分鐘到數十分鐘），完成前 TestFlight 看不到可安裝的 build。

### 9. 出口合規、加入群組、安裝

1. App Store Connect → TestFlight → 這個 build。若顯示 **Missing Compliance**，按 Manage 回答加密問題（見〈出口合規〉）。回答前 build 不能測試。
2. TestFlight → Internal Testing → `Internal` → Builds 旁的「+」/ Add Builds → 選這個 build（Xcode Cloud 的 build 要手動加入；若 post-action 已經加入就略過）。
3. 在 iPhone / iPad 從 App Store 安裝免費的 **TestFlight** App，用同一個 Apple Account 登入，接受邀請，安裝 Along the Line（沿線）。
4. 最小 smoke check：
   - 主畫面名稱為「Along the Line」（英文）或「沿線」（繁體中文／日文）。Default／Light appearance 使用米白背景的淺色版；Dark appearance 使用深色原稿（iOS／iPadOS 18 以上）。
   - 開啟後顯示地圖、現金、`Day 1 · 08:30`，時間會前進；暫停 / 1× / 2× 有反應。
   - 選取一格、鋪一段鐵軌、建一個車站，金額減少；在空格以外鋪軌會顯示錯誤訊息。
   - iPad 直向、橫向都能顯示；切到背景再回來不會閃退。
   - 內部測試 build 90 天後過期，之後需要新的 build。

### 10. 之後從 iPad 開發與發佈

- 開發：照常用 Claude Code 工作階段改程式、開 PR；GitHub Actions 的 CI、iOS App Build 會驗證。
- 發佈：PR merge 到 `main` 後，App Store Connect → Xcode Cloud → TestFlight Internal → Start Build。每次建置的 build number 由 Xcode Cloud 自動遞增。
- 查看結果：App Store Connect → Xcode Cloud → Builds（log、artifact 保留 30 天）；TestFlight App 會通知新 build。
- 改版號：修改 `project.yml` 的 `MARKETING_VERSION`，重新產生專案（同步驟 4）。

## Xcode Cloud workflow 設定表

Xcode Cloud 的 workflow 設定存在 Apple 的服務裡，**repository 裡沒有、也不能用 YAML 設定**；以下是要在 Xcode 或 App Store Connect 畫面上選的值。

共通：

| 欄位 | 值 |
| --- | --- |
| Repository | `a91453/railway-game-ios`（GitHub） |
| Project | `RailwayGameApp/RailwayGame.xcodeproj`（不是 `Package.swift`） |
| Scheme | `RailwayGame`（shared，已提交） |
| Custom build scripts | 無。本專案沒有 `ci_scripts/`：專案已提交，不需要在雲端產生 |
| 環境變數 | 無 |
| Package.resolved | 目前沒有遠端套件相依，只有 repository 本身的本地套件；GitHub CI 以 `-disableAutomaticPackageResolution`（與 Xcode Cloud 相同）建置來確認不需要它。將來加入遠端套件時，必須提交 `RailwayGame.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |

### Workflow 1：Build（首次 onboarding 驗證）

目的：先證明 Xcode Cloud 能 clone、找到專案與 scheme、解析本地套件並編譯，不牽涉簽章，失敗時容易定位。

| 區塊 | 欄位 | 值 |
| --- | --- | --- |
| General | Name | `Build` |
| | Description | `Compiles the iOS app (onboarding check)` |
| | Restrict Editing | 不勾 |
| Environment | Xcode Version | Latest Release（Xcode 26.x） |
| | macOS Version | Latest Release / Recommended |
| | Clean | 不勾 |
| Start Conditions | | 刪除預設的 Branch Changes；新增 **Manual Start**，Branch：`main` |
| Actions | Build | Platform：iOS；Scheme：RailwayGame；Destination：Any iOS Simulator Device |
| Post-Actions | | 無（預設 email 通知即可） |

不加 Test action：App 專案的 scheme 沒有測試 target，GameCore / GamePresentation 的測試由 Linux CI 執行；加了只會失敗或空跑。

### Workflow 2：TestFlight Internal（Release Archive → App Store Connect → 內部 TestFlight）

| 區塊 | 欄位 | 值 |
| --- | --- | --- |
| General | Name | `TestFlight Internal` |
| | Description | `Archives Release and delivers to internal TestFlight` |
| | Restrict Editing | 不勾（只有要送外部測試或 App Store 的 build 才必須勾） |
| Environment | Xcode Version | Latest Release（必須是 Xcode 26 以上，否則 App Store Connect 拒收） |
| | macOS Version | Latest Release / Recommended |
| | Clean | 勾選（發佈用 build 不使用快取） |
| Start Conditions | | 只有 **Manual Start**，Branch：`main`（不會因 push 或 PR 自動封存） |
| Actions | Archive | Platform：iOS；Scheme：RailwayGame；Deployment Preparation：**TestFlight (Internal Testing Only)** |
| Post-Actions | TestFlight Internal Testing | Group：`Internal` |

Archive action 使用 scheme 的 Archive 設定，即 **Release** configuration；Deployment Preparation 決定 Xcode Cloud 如何簽章。「TestFlight (Internal Testing Only)」的 build 不能給外部測試或送審；之後要上架時，新增另一個 workflow 改選「TestFlight and App Store」並勾 Restrict Editing 與 Clean。

## 版本號與 build number

- **Marketing version**（`CFBundleShortVersionString`）：`project.yml` 的 `MARKETING_VERSION`，目前 `0.3.0`。
- **Build number**（`CFBundleVersion`）：專案內的 `CURRENT_PROJECT_VERSION: "1"` 只用於本機與 CI。Apple：「When you distribute an Xcode Cloud build with TestFlight or release it on the App Store, App Store Connect uses the build number of the Xcode Cloud build」，Xcode Cloud 的 build number 從 1 開始每次建置遞增。因此不另外加時間戳、Git hash 或 `agvtool` 流程。
- 若需要調整：App Store Connect → Xcode Cloud → Settings → Build Number → Next Build Number（需要 Admin 或 App Manager）。新 App 維持預設即可。

## 出口合規（Export Compliance）

- 目前程式只 import SwiftUI、UIKit、Observation 與本專案的 GameCore / GamePresentation；沒有網路（`URLSession`、Network）、沒有 CryptoKit / CommonCrypto / Security / Keychain，也沒有第三方套件。`release-archive.yml` 會列出封存後 App 連結的函式庫作為佐證。
- Apple：若 App（含連結的函式庫）不使用加密、或只使用豁免的加密，可在 Info.plist 設定 `ITSAppUsesNonExemptEncryption = NO`；沒有這個鍵時，App Store Connect 每次上傳都會問出口合規問卷。
- **本 PR 刻意沒有加入這個鍵**：這是由你（開發者）對美國出口法規做的聲明，不應由工具替你假設。第一次上傳時請在 App Store Connect 依實際情況回答問卷；若確認不使用非豁免加密，之後可在 `project.yml` 加上 `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` 省去每次作答。將來加入網路、帳號、雲端存檔或加密功能時必須重新評估。

## 隱私

- App 不蒐集、不傳送任何資料，沒有網路、帳號、追蹤或第三方 SDK。
- Privacy manifest（`PrivacyInfo.xcprivacy`）：Apple 要求在使用「required reason API」（檔案時間戳、系統開機時間、磁碟空間、目前鍵盤、`UserDefaults`）時宣告理由。原始碼沒有直接使用這些 API；`release-archive.yml` 會掃描封存後的二進位檔並列出任何疑似引用。**目前沒有加入 privacy manifest**，也不為消除警告而虛構宣告。若 App Store Connect 寄來 ITMS-91053（Missing API declaration）之類的通知，依通知內容加入真實的理由。
- App Privacy（隱私營養標籤）是提交 App Store 審查時填寫的資訊；本輪只做內部 TestFlight，不送審。

## 常見失敗與定位

| 症狀 | 可能原因 | 處理 |
| --- | --- | --- |
| Get Started 找不到產品 / 沒有 RailwayGame | 打開的是 `Package.swift` 或資料夾；scheme 沒有 Archive | 開 `RailwayGameApp/RailwayGame.xcodeproj`；iOS App Build 的「List schemes and archivable products」應列出 `io.github.a91453.RailwayGame`（類型 app） |
| Onboarding 在建立產品時失敗 | 團隊還沒有任何 App（Apple 已知問題） | 先做步驟 3 建立 app record |
| Xcode Cloud 找不到專案或 scheme | 專案或 scheme 沒有提交、或被改名 | 確認 `main` 上有 `RailwayGame.xcodeproj/xcshareddata/xcschemes/RailwayGame.xcscheme`；不要改 scheme 名稱 |
| 「a resolved file is required…」 | 新增了遠端套件但沒提交 `Package.resolved` | 提交 `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| Signing requires a development team | 沒設定 `DEVELOPMENT_TEAM` | 步驟 4 |
| No profiles / bundle identifier 無法使用 | Bundle ID 被其他團隊占用或不一致 | 步驟 2；確認 app record、`project.yml`、Identifiers 三處相同 |
| Missing app icon / 缺少 1024 圖示 | asset catalog 沒被打包 | `release-archive.yml` 會檢查 `Assets.car` 與 `CFBundleIcons`；圖示在 `RailwayGameApp/Resources/Assets.xcassets/AppIcon.appiconset`（1024×1024、不透明） |
| 上傳被拒：SDK / Xcode 版本太舊 | workflow 選了 Xcode 26 以前的版本 | Environment 改 Latest Release |
| 上傳被拒：version / build 重複 | 同一個版本號下 build number 重複 | 不要手動改 build number；需要時用 Next Build Number，或提高 `MARKETING_VERSION` |
| TestFlight 顯示 Missing Compliance | 未回答出口合規 | 步驟 9 |
| Build 一直在 Processing | App Store Connect 處理中 | 等待；超過數小時再看 Apple 寄的 email |
| 測試者看不到 build | build 沒加入群組、測試者不是團隊成員、沒接受邀請 | 步驟 5、9；Xcode Cloud 的 build 要手動加入群組 |
| iOS App Build 的漂移檢查失敗 | 改了 `project.yml` 沒重新產生，或在 Xcode 裡改了專案 | 依錯誤訊息重新產生並提交；該次執行的 `regenerated-xcodeproj` artifact 是預期的專案 |

## GitHub macOS 驗證的移交條件

目前（2026-09-28）`main` 沒有 branch protection，也沒有 required status checks；`ios-build.yml` 是唯一自動執行的 iOS 編譯檢查。在 Xcode Cloud 實際成功前**全部保留**，不製造 iOS 驗證空窗。

| GitHub workflow | 現在 | Xcode Cloud 可以取代的部分 |
| --- | --- | --- |
| `ci.yml`（Linux，Swift 6.4） | 保留 | 不取代：GameCore 在 Linux 上的可移植性與完整測試 |
| `ios-build.yml` 的漂移檢查、archivable product 檢查 | 保留 | 不取代：Xcode Cloud 不檢查專案是否與 `project.yml` 一致 |
| `ios-build.yml` 的 Simulator build | 保留 | 可取代，條件見下 |
| `release-archive.yml`（未簽章） | 保留 | Workflow 2 成功後可只留手動觸發 |

`ios-build.yml` 的 Simulator build 可以退場的條件（全部成立）：

1. Workflow 1 加上 **Pull Request Changes**（Source：Any Branch，Target：`main`）與 **Branch Changes**（`main`），並在至少一個 PR 與一次 `main` 更新上成功。
2. GitHub PR 頁面出現 Xcode Cloud 的 check。
3. 若之後啟用 branch protection，required checks 改為 Xcode Cloud 的 check，並確認該 check 已在 PR 上回報。
4. 每月 Xcode Cloud 運算時數足夠（公開 repository 使用 GitHub 標準 runner 是免費的，Xcode Cloud 則會消耗 25 小時額度，不一定值得替換）。

退場方式：只移除 `ios-build.yml` 的「Build for iOS Simulator」步驟，保留漂移與 archivable product 檢查。回退：revert 該 commit 即恢復。

## Repository 已完成的準備

- **專案提交（方案 A）**：`RailwayGameApp/RailwayGame.xcodeproj`（`project.pbxproj`、`project.xcworkspace/contents.xcworkspacedata`、`xcshareddata/xcschemes/RailwayGame.xcscheme`）由 XcodeGen 2.46.0 從 `project.yml` 產生並提交；不含 `xcuserdata`、使用者狀態或絕對路徑。`project.yml` 仍是設定來源。
  - 未選方案 B（不提交、在 `ci_post_clone.sh` 產生）：Apple 明文表示動態產生或編輯專案的工具可能讓首次設定與之後的建置失敗；首次 onboarding 時借來的 Mac 也得先裝 XcodeGen 產生專案才能開啟，而 Xcode Cloud 端要依賴 clone 後才存在的專案。沒有官方證據證明這條路可靠，所以不採用。
- **可重現**：同一個 checkout 重新產生、不同路徑或使用者重新產生，輸出完全相同；Xcode Cloud 寫入的 `manifest.json` 與 `Package.resolved` 在重新產生時保留。限制：checkout 資料夾名稱會寫進專案（本地套件的顯示名稱），所以要在名為 `railway-game-ios` 的資料夾（`git clone` 預設）中產生。
- **漂移檢查**：`ios-build.yml` 以固定版本、checksum 驗證的 XcodeGen 重新產生，任何差異都失敗並附上預期專案的 artifact；另外確認 shared scheme 已提交、`xcodebuild -describeAllArchivableProducts`（Xcode Cloud 用來找產品的指令）列得出 App。
- **發佈設定**：App target、shared scheme、Archive action = Release；iPhone + iPad（`TARGETED_DEVICE_FAMILY` 1,2）、iOS 17.0；Bundle ID `io.github.a91453.RailwayGame`；顯示名稱 Along the Line（繁體中文／日文：沿線）；`MARKETING_VERSION` 0.3.0；`CODE_SIGN_STYLE` Automatic，`DEVELOPMENT_TEAM` 待填；Release 不定義 `DEBUG`，因此 `-demo-layout` 啟動參數不會編進 Release（示範地圖本身從 Stage C4 起由開始畫面開啟，Release 也有）。
- **App Icon**：作者提供的正式 Light／Dark 定稿，兩張原始 1024×1024 PNG。`AppIcon.appiconset` 的 Any／Default 指向 `along-the-line-app-icon-light.png`，Dark 指向 `along-the-line-app-icon-dark.png`；不裁切、不改色、不加圓角，由 iOS 套用 mask，Tinted 由系統生成。`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`（XcodeGen 的 iOS App 預設值）。
- **未簽章 Release Archive**：`release-archive.yml` 以 Release、`generic/platform=iOS`、`-disableAutomaticPackageResolution`、`CODE_SIGNING_ALLOWED=NO` 封存並檢查 Info.plist、圖示、架構與 Release 不含示範配置。它**不能**證明簽章、上傳或 TestFlight；`CODE_SIGNING_ALLOWED=NO` 只用在這個 CI 檢查，不用於任何真正的發佈。

## 官方來源（查閱日期 2026-09-28）

- Xcode Cloud 需求、持續存在的專案、shared scheme、自動簽章：https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud
- 首次 workflow 必須在 Xcode 建立、建議的預設 workflow、`-describeAllArchivableProducts`、之後可用 App Store Connect：https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow
- `manifest.json` 需推到 remote：https://developer.apple.com/documentation/xcode/getting-started-with-xcode-cloud
- Actions 與 Deployment Preparation：https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions
- Workflow 設定（Environment、Clean、Post-actions）：https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference
- Start conditions（Manual Start、Pull Request Changes）：https://developer.apple.com/documentation/xcode/configuring-start-conditions
- 發佈用 workflow（Restrict Editing、Clean、TestFlight post-action）：https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution
- 透過 TestFlight 發佈 Xcode Cloud build、app record：https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight
- 套件相依與 `Package.resolved`：https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud
- `ci_scripts` 位置、時機、權限（本專案目前不需要）：https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
- 環境變數：https://developer.apple.com/documentation/xcode/environment-variable-reference
- Build number：https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
- Xcode Cloud 已知問題（無 App 時 onboarding 失敗）與可用 Xcode 版本：https://developer.apple.com/xcode-cloud/release-notes/
- 每月 25 小時：https://developer.apple.com/xcode-cloud/get-started/
- 內部測試者、群組、Xcode Cloud build 需手動加入群組：https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers
- TestFlight 內部 / 外部測試：https://developer.apple.com/testflight/
- 協議（免費 App 不需 Paid Apps Agreement）：https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements
- 上傳的 Xcode / SDK 最低要求：https://developer.apple.com/news/upcoming-requirements/
- 出口合規：https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations 、https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption
- Required reason API：https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- App Icon：https://developer.apple.com/documentation/xcode/configuring-your-app-icon
- GitHub Actions 對公開 repository 標準 runner 免費：https://docs.github.com/en/billing/concepts/product-billing/github-actions
