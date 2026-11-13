# 作者的 Mac：本機建置、測試、實機與 Instruments

作者 2026-11-06 起有一台 MacBook Pro（M6、32 GB）。這份文件說明怎麼用它做三件事：

1. 在 Xcode 建置，裝到自己的 iPhone；
2. 讓雲端 Claude Code session 透過 Remote Control 借用 Mac 的 repo 資料夾，跑 `xcodebuild`、Simulator 的 UI 測試與官網截圖，少排 GitHub 的 macOS runner（只有 5 台）；
3. 用 Instruments 在實機量 fps 與記憶體；
4. 把 iOS App 直接開在這台 Mac 上（第 8 節），改完程式不經 Simulator 與 iPhone 就看得到。

標示 **UNVERIFIED** 的步驟寫文件時沒有機器可試（寫文件的 session 在 Linux），第一次照做時請對照畫面，不一致就改這份文件。

## 1. 工具版本要與 CI 一致

CI 的 `macos-26` runner（2026-11-04，從 `ios-build.yml` 的 **Toolchain versions** 步驟 log 讀到）：

| 項目 | 版本 |
| --- | --- |
| Xcode | 26.6（17F113） |
| macOS | 26.6.2 |
| iOS Simulator SDK | 26.5 |

**以 `ios-build.yml` 該步驟最新一次的 log 為準**：runner 映像會更新，這張表會舊。Mac 上用下面指令對照：

```sh
sw_vers
xcodebuild -version
echo "iOS Simulator SDK: $(xcrun --sdk iphonesimulator --show-sdk-version)"
```

Xcode 從 Mac App Store 或 developer.apple.com 下載；要與 CI 同版，就裝 log 上那一版（舊版從 developer.apple.com/download/all 取得，需要 Apple 帳號）。第一次開 Xcode 後，到 Settings → Components 裝 iOS Simulator runtime（與上表 SDK 同版）。Swift 的 Linux 檢查不在這台 Mac 上做，照 CLAUDE.md 由雲端 session 與 CI 負責。

## 2. XcodeGen 2.46.0

專案檔 `RailwayGameApp/RailwayGame.xcodeproj` 是由 `RailwayGameApp/project.yml` 用 XcodeGen **產生並已提交**的。釘的版本在 `.github/actions/setup-xcodegen/action.yml`（現為 **2.46.0**）。那個 action 的做法是下載官方 release 的 zip、核對 SHA-256、解壓；不是 Homebrew。在 Mac 上照做一次：

```sh
VERSION=2.46.0
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806   # 以 action.yml 為準
mkdir -p ~/tools && cd ~/tools
curl --fail --silent --show-error --location --retry 3 \
  --output "xcodegen-$VERSION.zip" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
echo "$SHA256  xcodegen-$VERSION.zip" | shasum --algorithm 256 --check
unzip -q "xcodegen-$VERSION.zip" -d "xcodegen-$VERSION"
~/tools/xcodegen-$VERSION/xcodegen/bin/xcodegen --version     # 應顯示 2.46.0
```

（版本或 SHA 以 `action.yml` 當下的內容為準；升級時 action 與 CLAUDE.md 一起改。）

**何時要重新產生專案**：改了 `project.yml`，或增減了 App 的檔案（新增、刪除、搬動 `RailwayGameApp/` 下的檔案、資源）。在 repository 根目錄：

```sh
~/tools/xcodegen-2.46.0/xcodegen/bin/xcodegen generate --spec RailwayGameApp/project.yml
git status    # 看 .xcodeproj 有沒有變；變了就連 project.yml 一起提交
```

**不要手改 `.xcodeproj`**，也不要在 Xcode 的 Signing & Capabilities 面板改隊伍或設定：那會改到產生的專案，下一次 CI 的「專案與 project.yml 一致」檢查就會紅。`ios-build.yml` 用官方 macOS 版 XcodeGen 的檢查才是準的。

## 3. clone、打開、在 Simulator 跑

```sh
git clone https://github.com/a91453/railway-game-ios.git
cd railway-game-ios
open RailwayGameApp/RailwayGame.xcodeproj
```

在 Xcode 上方選 scheme **RailwayGame**，裝置選任一 iPhone Simulator（官網截圖用的是 iPhone Pro，不是 Max），按 ⌘R。Simulator 不需要簽章。Swift package（`Sources/GameCore` 等）由專案自己引用，不用另外開。

## 4. 裝到自己的 iPhone

### 4.1 iPhone 的設定

1. 用線接上 Mac，iPhone 上按「信任這台電腦」。
2. iPhone 設定 → 隱私權與安全性 → **開發者模式** → 打開，重新啟動後再確認一次。（沒有這一項時，先在 Xcode 的 Window → Devices and Simulators 選這支 iPhone，這一項才會出現。）
3. Xcode 的 Settings → Accounts 登入 Apple 帳號（個人或付費的 Apple Developer Program 隊伍皆可，TestFlight 用的就是付費隊伍）。

### 4.2 簽章：不改任何已提交的檔案

`project.yml` 的註解寫明：`DEVELOPMENT_TEAM`（10 碼 Team ID）不設，Simulator 與無簽章 CI 封存都不需要；要設就加進 `project.yml` 再重新產生，**不要在 Signing & Capabilities 面板選隊伍**。CLAUDE.md 另規定 Team ID 與 app ID **不寫進 repository**（公開的 repo）。兩者合起來，做法是**指令列帶 build setting**：build setting 從命令列給，不寫進任何檔案。

Team ID 在 developer.apple.com → Membership details（10 個英數字）。不要寫進文件、commit 或 shell 的版本控制範圍內；放在自己的 shell 環境：

```sh
export TEAM_ID=XXXXXXXXXX     # 自己的，不要提交
```

找到 iPhone 的裝置 ID：

```sh
xcrun xctrace list devices       # 或 xcrun devicectl list devices
```

建置並簽章（Debug，裝置）：

```sh
xcodebuild build \
  -project RailwayGameApp/RailwayGame.xcodeproj \
  -scheme RailwayGame \
  -configuration Debug \
  -destination "platform=iOS,id=<裝置 ID>" \
  -derivedDataPath ~/Library/Developer/RailwayGameDerived \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID"
```

`-allowProvisioningUpdates` 讓 xcodebuild 用 Xcode 登入的帳號自動建立開發憑證與描述檔（`CODE_SIGN_STYLE: Automatic` 與此一致）。然後安裝並啟動：

```sh
xcrun devicectl device install app --device <裝置 ID> \
  ~/Library/Developer/RailwayGameDerived/Build/Products/Debug-iphoneos/RailwayGame.app
xcrun devicectl device process launch --device <裝置 ID> io.github.a91453.RailwayGame
```

第一次安裝後，若 iPhone 說「未受信任的開發者」：設定 → 一般 → VPN 與裝置管理 → 信任自己的帳號。

**UNVERIFIED**：上面 `xcodebuild`／`devicectl` 的組合是 Xcode 26 的標準做法，但沒有在這個 repo 實際跑過。可能遇到的狀況：

- 若 Bundle ID `io.github.a91453.RailwayGame` 已被別的隊伍註冊，簽章會失敗。TestFlight 用的隊伍和你的個人帳號不同時，要用 TestFlight 的那個隊伍。
- 若 App 需要 iCloud、Game Center 等能力（見 `docs/ICLOUD_SAVE_SETUP.md`、`docs/GAME_CENTER_SETUP.md`），免費個人帳號無法簽。
- 另一個也不改檔案的選項：用 Xcode 的 `.xcconfig` 放在 repository **之外**，用 `XCODE_XCCONFIG_FILE=~/my-signing.xcconfig xcodebuild …` 指到它（內容只有 `DEVELOPMENT_TEAM = XXXXXXXXXX`）。同樣 UNVERIFIED。

不要這樣做：在 Xcode 面板選隊伍；把 `DEVELOPMENT_TEAM` 加進 `project.yml`（與 CLAUDE.md 衝突）；把 Team ID 寫進任何提交的檔案。這條路也不會動到 TestFlight：發版仍只走 `testflight.yml`。

## 5. 本機跑 UI 測試與官網截圖

以下指令抄自 `ios-build.yml` 與 `website-screenshots.yml` 實際用的參數（`$RUNNER_TEMP` 換成本機資料夾）。參數若與 workflow 不同，以 workflow 為準。

```sh
export DERIVED=~/Library/Developer/RailwayGameDerived-sim
# 選一台 Simulator：iPhone Pro（不是 Max）
xcrun simctl list devices available | grep "iPhone"
export SIMULATOR_UDID=<上面列出的 UDID>
```

### 5.1 建置（供測試用，與 CI 相同）

```sh
xcodebuild build-for-testing \
  -project RailwayGameApp/RailwayGame.xcodeproj \
  -scheme RailwayGame \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  CODE_SIGN_IDENTITY=-
```

`CODE_SIGN_IDENTITY=-` 是 ad hoc 簽章，UI 測試需要，且不用 Apple 帳號。

### 5.2 Gate 的 UI 測試（PR 上跑的那四個）

```sh
xcodebuild test-without-building \
  -project RailwayGameApp/RailwayGame.xcodeproj \
  -scheme RailwayGame \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath ~/ui-smoke.xcresult \
  -only-testing:RailwayGameUITests/ToolbarSmokeTests/testEnglishToolbar \
  -only-testing:RailwayGameUITests/StartSaveFlowSmokeTests/testBackToStartWorksWithLargeTextWhileTheClockRuns \
  -only-testing:RailwayGameUITests/TutorialUITests/testBuildingTrackEnablesNextAndSkipEnds \
  -only-testing:RailwayGameUITests/TutorialUITests/testTheLineStepLeavesTheLinesPanelUsable \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 480 \
  -maximum-test-execution-time-allowance 600 \
  -disableAutomaticPackageResolution
```

Gate 的清單會變，以 `ios-build.yml` 的「UI smoke tests」步驟（`GITHUB_EVENT_NAME == pull_request`）為準。

### 5.3 單一 UI 測試

把 `-only-testing:` 換成要跑的，格式 `RailwayGameUITests/<類別>[/<方法>]`，例如：

```sh
-only-testing:RailwayGameUITests/SettingsUITests/testTheCityPreviewLoadsItsPageAndCloses
```

其餘參數與 5.2 相同。整個 full lane 是「不加 `-only-testing`，並 `-skip-testing` 掉截圖、宣傳素材等幾個類別」，見同一步驟的 `else` 分支；本機全跑要很久（CI 上 20 到 70 分鐘），除非為了查 CI 紅燈，不必。

### 5.4 官網截圖（`WebsiteScreenshotTests`）

CI 的做法（`website-screenshots.yml`）：iPhone Pro 的 Simulator、Debug、**深色**、**橫向**（測試自己把裝置轉成 `landscapeLeft`）、狀態列固定 9:41。

```sh
# 先建置（同 5.1，但 CODE_SIGNING_ALLOWED=NO）
xcodebuild build-for-testing \
  -project RailwayGameApp/RailwayGame.xcodeproj -scheme RailwayGame -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED" -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO

# 開機、深色、狀態列
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl ui "$SIMULATOR_UDID" appearance dark
xcrun simctl status_bar "$SIMULATOR_UDID" override --time 9:41 --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3

# 跑（要只跑幾個方法時，在類別後加 /<方法名>，像 CI 的 tests 輸入）
xcodebuild test-without-building \
  -project RailwayGameApp/RailwayGame.xcodeproj -scheme RailwayGame -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED" -resultBundlePath ~/screenshots.xcresult \
  -only-testing:RailwayGameUITests/WebsiteScreenshotTests \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 480 \
  -maximum-test-execution-time-allowance 1800 \
  CODE_SIGN_IDENTITY=-
```

照片取出：`xcrun xcresulttool export attachments --path ~/screenshots.xcresult --output-path ~/attachments`。CI 之後還會用 Python 依 `suggestedHumanReadableName`（小寫加連字號）挑出測試自己存的圖，並把橫向的圖轉回正向；這一段（`Export the screenshots` 與其後的步驟）照 `website-screenshots.yml` 抄，這份文件不重複。iPad 版（`device: ipad`）是最大的 iPad Pro；在本機選 iPad Pro Simulator 即可。

## 6. Remote Control：讓雲端 session 借用這台 Mac

目的：雲端 Claude Code session 要跑 `xcodebuild` 時，借用 Mac 的 repo 資料夾來跑，不排 GitHub 的 macOS runner。

做法（名稱以產品文件為準，**UNVERIFIED**：寫文件時看不到 Claude 桌面版的畫面）：

1. 在 Mac 安裝 Claude 桌面版，登入同一個帳號。
2. Settings → Claude Code → **Remote Control**，把 clone 好的 `railway-game-ios` 資料夾加入。Mac 要開著、Claude 桌面版要在執行，這個資料夾才算「在線」。
3. 雲端 session 用 `list_computer_folders` 看到這個資料夾，再用 `request_computer_folder` 要求連線。**每一次都會問作者**（在 Claude app 上按允許），沒有永久授權。作者不在時，session 等不到答案就會繼續做不需要 Mac 的部分。
4. 一個 session 同一時間只連一個資料夾，且一直綁在第一台電腦上；要換電腦，開新 session。連上後要斷線，只有作者能在對話選單或 Remote Control 設定處斷開。
5. 借用期間，session 的指令與檔案工具直接在這個資料夾執行，所以：
   - 在 Mac 的 repo 資料夾保持乾淨：不要在裡面放未提交的修改，session 可能 checkout 其他分支；
   - 簽章用的 Team ID 只放在作者自己的 shell 環境，不在 repo 資料夾；
   - 雲端 session 不得用這個通道跑 `testflight.yml`，也不得要作者的 Apple 密碼、2FA 或私鑰（CLAUDE.md）。

**不要把這台 Mac 掛成 GitHub self-hosted runner。** 這個 repository 是公開的，任何人的 PR 都能觸發 workflow，程式就會在作者的機器上跑。這個決定已在 `docs/HANDOFF.md` 的「CI 4C」那一列寫下；Remote Control 每次由作者核准，與 self-hosted runner 不同。Xcode Cloud 也仍暫緩：它要把 Team ID 寫進 `project.yml`（與 CLAUDE.md 衝突），每月 25 小時的額度對 full lane 不夠（見 `docs/XCODE_CLOUD_ONBOARDING.md`）。

## 7. Instruments：在實機量 fps 與記憶體

用 Debug 版（第 4 節）裝到 iPhone；要接近玩家看到的效能，改量 Release：把第 4.2 節指令的 `-configuration Debug` 換成 `Release`、路徑換成 `Release-iphoneos`。Debug 版的 fps 會偏低。

### 7.1 先看 App 自己的讀數

App 的設定裡可以開 3D 地圖預覽（`Map3DPreviewScreen`），有除錯數字列（fps、CPU／GPU ms、draw 數、三角形數、人與車數；決策 417、485）。Instruments 的結果要和這列對照。

### 7.2 量法

1. 連上 iPhone，Xcode 的 Product → Profile（⌘I）會用 Release 設定建置並開 Instruments；或直接開 Instruments，選裝置與 App。
2. 選範本，按錄製，在遊戲裡重現場景（例如 3D 地圖跟車 10×），錄 30 到 60 秒：
   - **Time Profiler**：看哪個函式吃主執行緒。看「Heaviest Stack Trace」，勾選 Invert Call Tree 與 Hide System Libraries。
   - **Core Animation**（新版 Xcode 裡可能叫 Animation Hitches 或在 Game Performance 範本內）：看 FPS 與卡頓。
   - **Metal System Trace**（在 Game Performance 範本內）：看 GPU 每幀時間、是否 CPU 或 GPU 受限、各階段（頂點／片段）。
   - **Allocations**／**Leaks**：量記憶體，跑長場景看成長；決策 460 的機型分級要的就是這個。
   - 範本名稱隨 Xcode 版本變動，**UNVERIFIED**。
3. 記下：裝置機型、iOS 版本、Debug 或 Release、場景、3D 畫質設定（省電／自動／高畫質）、fps 的中位數與最低值、CPU／GPU ms、記憶體峰值。寫進 PR 或決策，並把「實機 fps UNVERIFIED」改成 VERIFIED。

### 7.3 決策裡「實機 fps／記憶體未驗證」的項目，作者可挑

- **決策 485**：3D 跟車 10× 的每 tick 主執行緒工作移出去，iOS 上的 fps 與面板「main ms」UNVERIFIED。
- **決策 417**：3D 地圖共用一份預算，裝置上的流暢度 UNVERIFIED；ProMotion（120 Hz）沒做，因為量不到裝置幀時間。
- **決策 460**：依機型的記憶體與 CPU 兩軸，開場定 3D 的起點。
- **決策 517**：從 3D 按「建設」，3D 實機約 30 fps 的 CPU 成本是估計。
- **決策 391**：3D 公路橋抬高，板橋、苗栗南的跨線橋與 fps 要實機看。
- **決策 555**：3D 鏡頭斜到 60°，幀數是模擬器數字，不代表實機。
- **決策 421**：卡頓實機量測（畫面節奏紀錄跟問題回報走）。

Simulator 的 fps 不代表實機：Simulator 在 Mac 的 GPU 上跑，Metal 的行為與 iPhone 不同，所以這一節一定要用實機。

## 8. 直接在 Mac 上開 iOS App（Designed for iPad）

Apple silicon 的 Mac 能直接跑 iPad 版的 App，不用改 `project.yml`，也不用另做 Mac 版。2026-11-13 在這台 Mac 上實際做過：Debug 建置成功，開起來是 iPad 的版面，平面地圖（資金與時鐘列、工具列、路網面板、圖例）與 3D 地圖都畫得出來。

一行做完建置、包裝、開啟（已開著的那一份會先關掉）：

```sh
tools/mac-run/run_on_mac.sh            # Debug
tools/mac-run/run_on_mac.sh Release
```

腳本做的三件事，手動也可以照做：

1. 用 `platform=macOS,variant=Designed for iPad` 這個目的地建置，簽章與第 4.2 節相同：`DEVELOPMENT_TEAM` 從命令列給，不寫進任何檔案。腳本讀環境變數 `TEAM_ID`；沒有設就從鑰匙圈的 Apple Development 憑證讀。產物放在 `~/Library/Developer/RailwayGameDerived-mac`，與第 4、5 節的資料夾分開。
2. 建出來的 `Debug-iphoneos/RailwayGame.app` 是 iOS 的 bundle，直接 `open` 會說「incorrect executable format」。要包一層：外層 `RailwayGame.app` 裡放 `Wrapper/RailwayGame.app`（複製一份），再加一個符號連結 `WrappedBundle` 指向 `Wrapper/RailwayGame.app`，也就是 Mac App Store 安裝 iPad App 時的形狀。
3. `open` 外層那個 bundle。

**第一次要登記這台 Mac。** 開發用的描述檔只包含帳號裡登記過的裝置；Mac 沒登記時建置會停在簽章：「Device … isn't registered in your developer account」。登記會改動開發者帳號的裝置清單，是作者的決定；作者同意後跑一次：

```sh
REGISTER_DEVICE=1 tools/mac-run/run_on_mac.sh
```

作者的 MacBook Pro 已在 2026-11-13 登記，之後不用再帶。

適合拿來做的事：改遊戲規則的呈現、面板內容、3D 場景後很快看一眼。重新建置、關掉舊的、再開起來，在沒有改程式時約 4 秒；有改程式時，時間幾乎都是編譯，和 Simulator 一樣。

這樣跑**看不到**的，仍要在 Simulator 或 iPhone 上確認：

- iPhone 的版面：Mac 上是 iPad 的版面。
- 觸控手勢：兩指拉近、旋轉在 Mac 上是觸控板或滑鼠。
- 效能：Mac 的顯示晶片比 iPhone 強得多，這裡的 fps 與記憶體不能當成手機上的數字（量測照第 7 節）。
- UI 測試與官網截圖：照第 5 節在 Simulator 跑。

**UNVERIFIED**（2026-11-13 沒有檢查）：只用滑鼠能不能做完所有操作；Game Center；iCloud 存檔，以及它和 iPhone 是不是同一份（是的話，兩邊同時開著可能互相蓋掉存檔，不用時把 Mac 上的關掉）；聲音；Release 建置。
