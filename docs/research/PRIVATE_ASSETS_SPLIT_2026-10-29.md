# 把編 App 必需的檔案搬到私庫：盤點與計畫（A 案）

2026-10-29，派工單 PRIV，session_01YGNNunCs4CpTF415GeYCpT，由遊戲規劃第 31 任（session_01YGNNukxseY7eMCvXhjtc4X）派。只做盤點和計畫：不搬檔、不改 CI、不改程式。數字量自 `main` c82af9d（2026-10-29 08:20 UTC）。

**背景**：作者擔心公開的 `a91453/railway-game-ios` 被人 clone 去重新編成 App。作者選了 A 案：程式維持公開，把編 App 一定要用、最有價值的非程式檔案移到私庫，CI 建置時再拉進來。B 案（資料加密放在公開 repo）和 C 案（整個 repo 改私人）只拿來比較（第 7 節）。

**計畫要作者看過、點頭才動手。**

## 0. 結論（先看這段）

- **建議做法**：
  - 另開一個新的私庫 `a91453/railway-game-data-private`，只放「App 打包的資料、音效、圖示、模型」，路徑和公開 repo 一模一樣（`RailwayGameApp/Resources/...`）。
  - 公開 repo 放一個鎖檔 `private-assets.lock`，寫私庫的 commit SHA。
  - CI 用 **deploy key**（唯讀、只開這一個私庫）把那個 commit 拉下來，**疊回原來的路徑**，再照現在的步驟建置、測試。
  - 程式、`project.yml`、`.xcodeproj` 都不用改路徑。GameCore、存檔、golden、replay 都不動。
- **要搬的**：`RailwayGameApp/Resources/` 下的 `BaseMap/`、`RealWorld/`、`RealRailways/`、`RealBuses/`、`Audio/`、`Models/`、`Map3D/`、`Assets.xcassets/`，共約 143 MB、761 個檔。另外搬 `tools/audio/` 的 MML 原稿與樂譜，因為它們可以原樣重新合成全部音效。
- **留在公開的**：
  - 全部 Swift 程式，包括 `Map3D*Kit`、列車配方等「寫在 Swift 裡的美術」，約 1.6 MB（第 2 節）。
  - 翻譯（`Localizable.xcstrings`、`*.lproj`）、`PrivacyInfo.xcprivacy`、`Licenses/`。
  - `tools/` 的產生腳本：ODbL 要求「怎麼做出來的」要能取得，第 8 節。
  - `Web/CityView`：MIT，App 不打包它。
- **防得住的與防不住的**：
  - 防得住的：搬完以後，別人 clone 公開 repo，編得出 App，但只能玩不需要真實資料的課程與沙盒地圖。這種 App 沒有台灣實景地圖、鐵道與公車資料、地形、音效、圖示，3D 地圖沒有底圖。
  - 防不住的有兩樣：
    - 3D 列車、建築套件都是 Swift 程式，照樣編得出來。
    - **git 歷史裡已經有的檔案照樣拿得到**（第 5 節）：現在的全部資料都在歷史裡，搬家只保護以後的新版本。
- **作者要做的**（第 4 節）：建私庫、產生一把 deploy key、把公鑰加到私庫、把私鑰存成公開 repo 的 Actions secret、讓 Claude 的 session 也能掛上這個私庫。約 10 分鐘。
- **PR 數**：私庫 1 個，公開 repo 3 個；另有 1 個選做的 PR，把最大的網格資料表從 Swift 換成資源檔。第 9 節。
- **C 案**：照最近 7 天的用量換算，改私人每月約 USD __C_MONTHLY__（macOS 佔大部分），第 7 節。

## 1. 編出能玩的 App 一定要用的非程式檔案

`RailwayGameApp/Resources/` 共 144 MB。`project.yml` 把 `Resources/` 當原始檔逐一列進 `.xcodeproj`，`BaseMap/` 則是整個資料夾一起複製（決策 151）。App 用 `Bundle.main.url(forResource:withExtension:)` 找檔案，底圖另外加 `subdirectory: "BaseMap"`。

| 路徑（`RailwayGameApp/Resources/`） | 檔案 | 大小 | 內容 | 怎麼來的 | 建議 |
| --- | --: | --: | --- | --- | --- |
| `BaseMap/taiwan.pmtiles` | 1 | 52 MB | 全台向量底圖 | `tools/basemap/build_basemap.py`，讀 osmtoday 的 OSM 整包（ODbL） | 搬 |
| `BaseMap/taiwan_buildings.pmtiles` | 1 | 29 MB | 建物足跡 | `tools/overture-footprint-tiles/`（Overture、OSM，ODbL） | 搬 |
| `BaseMap/taiwan_terrain.pmtiles` | 1 | 9.6 MB | 地形 | `tools/basemap/build_terrain.py`（Copernicus DEM） | 搬 |
| `BaseMap/taiwan_temples.json` | 1 | 360 KB | 廟宇 | `tools/temples/`（OSM） | 搬 |
| `BaseMap/city/` | 98 | 2.6 MB | 高雄、台中的街區 | `tools/procedural-city/` 等 | 搬 |
| `BaseMap/fonts/` | 194 | 1.9 MB | Noto Sans 字形（OFL） | `tools/basemap/fetch_glyphs.py` | 跟 BaseMap 一起搬（第 8 節） |
| `RealWorld/` | 7 | 19 MB | 高度、水域、不可蓋地、地名、人口、覆蓋率 | `tools/real-world-population/`、`place-names/`、`no-build-land/`（OSM、WorldPop、Copernicus、Overture） | 搬 |
| `RealBuses/` | 23 | 13 MB | 22 縣市公車路線 | `tools/real-buses/`（TDX，讀參考庫的整理） | 搬 |
| `RealRailways/` | 44 | 5.7 MB | 台鐵、高鐵、各捷運的軌道、車站、班表、運量、構造物 | `tools/real-railways/`、`real-timetables/`、`real-ridership/`（TDX、OSM、參考庫） | 搬，**最有價值** |
| `Audio/` | 27 | 8.7 MB | 音樂、汽笛、音效 | `tools/audio/make_game_audio.py` 從本專案的 MML 原稿合成（決策 79、219） | 搬，連原稿 |
| `Models/` | 11 | 404 KB | 公車、垃圾車、Kenney 樹（CC0）、Meshy 站牌與郵筒 | `tools/glb-to-m3dmodel/`、`kenney-props/`、`meshy-props/` | 搬 |
| `Map3D/` | 2 | 1.4 MB | 3D 招牌字、地面貼圖 | `tools/map3d-signs/`、`map3d-preview/` | 搬 |
| `Assets.xcassets/` | 263 | 1.9 MB | App 圖示、71 個圖示集（70 SVG、80 PNG）、成就圖、AccentColor | 手畫（`.claude/skills/art-style/`） | 搬 |
| `Localizable.xcstrings`、`*.lproj/` | 3 | 92 KB | 中英文字串 | 手寫 | 留公開（`ios-build.yml` 的翻譯檢查讀它；字串本身不是能搬走的價值） |
| `PrivacyInfo.xcprivacy` | 1 | 4 KB | 隱私清單 | 手寫 | 留公開 |
| `Licenses/` | 2 | 112 KB | MapLibre、Noto Sans 授權全文 | 照抄 | 留公開（第 8 節） |

合計要搬的：761 個檔、約 143 MB。

**不在 Resources 的**：
- `Web/CityView`（9 MB）：App 不打包它。決策 163 起由官網提供，App 只開網頁。它是 MIT（jeantimex/tokyo），留公開。
- `tools/` 裡有 6 個檔被測試直接讀：`tools/audio/manifest.json`、`tools/map3d-signs/words.json`、`tools/real-railways/osm_exceptions.json`、`tools/tourism-spots/taiwan_attractions.json` 和兩個 `glb-to-m3dmodel` 測試用的小模型。都很小，留公開。
- `tools/audio/` 的 `mml/` 與 `scores/` 是本專案自己寫的曲子，`make_game_audio.py` 用它們可以一個位元組都不差地重做全部音效。只搬 `Audio/` 的輸出防不了，所以原稿一起搬。產生腳本可以留公開。

**能自己重做多少**：BaseMap、RealWorld、地名、廟宇都只用公開來源（OSM、Overture、Copernicus、WorldPop）加上公開的 `tools/` 腳本，有心人花一兩天可以重做。真正重做不出來的有兩類：
- 從參考庫（`Railway/`、`Ci/`）整理的鐵道、班表、公車資料。
- 手畫的圖示和自己寫的曲子。

所以優先順序是：RealRailways、RealBuses、Audio＋原稿、Assets.xcassets，再來才是 BaseMap 和 RealWorld。

## 2. 寫在 Swift 裡的美術

這些都在 `Sources/GamePresentation/`，是程式碼，會一起編進 App：

| 類別 | 檔案 | 大小 | 例子 |
| --- | --: | --: | --- |
| 列車、公車、機車配方 | 40 | 0.90 MB | `Map3DTrainSets`、`Map3DTrainShell`、`Map3DEMU*`、`Map3DTEMU*`、`Map3DN700SG*`（其中 `Map3DN700SGMesh` 加 `FarMesh` 是 260 KB 的頂點表）、`Map3DCityBus`、`Map3DScooters` |
| 建築與場景套件 | 69 | 0.56 MB | `Map3D{Civic,Coastal,Commercial,Detail,Estate,Park,Recreation,Residential,Station,Works,Scene}Kit*` |
| 地標 | 7 | 0.14 MB | `Map3DTaipeiLandmarks`、`Map3DTaipeiPalaces`、`Map3DTaipei610`、`Map3DChineseRoof` |
| 國界等資料表 | 1 | 0.11 MB | `CountryBorders.swift` |
| 其他 Map3D（繪製引擎、相機、天氣、道路標線） | 約 64 | 約 1.1 MB | 引擎，不算美術 |

GamePresentation 全部 7.0 MB，其中 Map3D 開頭的 2.8 MB。

**搬得走的**：只有純資料的大表，例如 N700S 的頂點表（260 KB）、`CountryBorders`。
- 做法：改成 `Models/` 那種 `.m3dmodel` 或 JSON 資源檔，App 執行時讀。
- 代價：
  - 要改讀取的程式。
  - 測試要改成從檔案讀。
  - 列車雜湊、頂點 FNV 那類鎖定（`rolling-stock` skill）要確認讀進來的位元組一樣。
- 這是選做的 PR 5（第 9 節）。

**搬不走的**：配方本身。配方是「怎麼用程式組出模型」，和繪製引擎、`Map3DModels` 的打包、上百個 GamePresentation 測試綁在一起。要搬就得拆出一個私有 Swift package，讓 `Package.swift` 依賴一個私有 Git 來源。這樣一來：
- 每個 Linux session、每個 CI job、每次 XcodeGen 都要認證才編得過；
- 沒有私庫時整個 GamePresentation 編不過，不是只少資料；
- 這等於半個 C 案，代價遠超過效果，**不建議**。

**影響**：對方只拿公開 repo，能編出完整的 GameCore 規則、課程和沙盒地圖，以及 3D 地圖裡全部的列車、公車、建築套件、地標（都是程式畫的）。拿不到的是：
- 台灣實景地圖、真實鐵道與班表、公車；
- 地形和底圖；
- 音效與音樂、圖示、App icon。

能玩，但就是一個「沒有台灣、沒有聲音、沒有圖示」的鐵道沙盒。那些配方受 `LICENSE.md` 的著作權聲明保護（不得拿來製作或上架任何 App），被整包照搬時有證據（陷阱資料是另一單）。

## 3. 搬走以後會壞的地方與修法

做法的核心是**疊回原路徑**：CI 和開發 session 先把私庫的檔案複製到 `RailwayGameApp/Resources/...` 原來的位置，再跑原來的步驟。所以大部分東西不用改，只要在建置之前多一步。

### 3.1 `ci.yml` 的 Linux 測試

- 70 個 `Tests/GamePresentationTests/*.swift` 用 `#filePath` 推出 repo 根目錄，直接讀 `RailwayGameApp/Resources/...`。檔案不在時，`Data(contentsOf:)` 丟錯，測試紅。`HeadlessGame`、`GameSim` 也接受 `RealWorld` 資料夾路徑。
- 修法：
  - 在 `swift-build` 和每個 `selected-*`／分片 job 的 checkout 後面，加一個 composite action `.github/actions/private-assets`：照 `private-assets.lock` 的 SHA 淺拉私庫，驗證 `manifest.sha256`，把檔案疊回原路徑。
  - 分片下載的是 `.build`，不含 Resources，所以每個讀資料的 job 都要這一步。
  - 用 `actions/cache` 以 SHA 為鍵快取，約 143 MB，22 個 job 不必每個都重拉。
- 不加跳過的機制：
  - 測試少了檔案就照常紅，不加 `XCTSkip`。
  - 原因：跳過會讓綠燈不再代表測過，CLAUDE.md 也規定不能用跳過測試換綠燈。
  - 例外只有一個：私庫拉不到時，composite action 自己先失敗，並印出原因：「需要私有資料；fork 的 PR 拿不到，請由維護者在本 repo 開分支」。
- `swift-shards.sh`：
  - `relevant_paths` 和分層要加 `private-assets.lock`，比照 `RailwayGameApp/Resources/*`（只跑 GamePresentation 那一層）。
  - 私庫的資料一改，就要在公開 repo 開 PR 改鎖檔，這個 PR 就會跑對應的測試。
  - 公開 repo 的 CI 永遠測鎖定的那一版，不會因為私庫有人推了新檔案而默默變色。

### 3.2 golden、SaveFixtures、ReplayFixtures

**不需要被搬走的檔案，也不用動。**
- `GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 由 `Tests/GameCoreTests/` 的 `GoldenScenarioTests`、`SavedGameTests`、`ReplayFixtureTests` 讀。GameCore 不 import Foundation，讀不到 Resources；用 `grep` 查過，三個資料夾和 GameCoreTests 都沒有提到 `RailwayGameApp`、`RealWorld`、`RealRailways` 或 `pmtiles`。
- GamePresentation 有兩個測試（`RoadsTurnOnTests`、`LandImportTests`）同時讀 `SaveFixtures/` 和實景資料。它們跟著 3.1 的疊回步驟就能跑，fixture 本身不變。
- 鎖檔的 SHA 固定，所以資料不會在 golden 不知情時改變。

### 3.3 `ios-build.yml`（含 XcodeGen 漂移檢查）

- `.xcodeproj` 逐一列出 `Resources/` 的檔名（246 個 PBXFileReference）。漂移檢查重新產生專案再比對；檔案不在時，產生出來的專案少了那些參照，檢查就紅。
- 修法：
  - 在 `build`、`ui-full-lane`、`ipad-tutorial` 三個 job 的 checkout 後面、`Set up XcodeGen` 前面，加同一個 composite action。
  - 公開 repo 的 `.xcodeproj` 照樣列出檔名。檔名公開沒有關係，對方 clone 後一編就會「找不到檔案」，這正是要的效果。
  - `project.yml` 不改。
- `paths-ignore` 和 patch-id 的清單不用動：`private-assets.lock` 不在排除清單裡，改鎖檔會跑 iOS 建置。
- 翻譯檢查讀 `Localizable.xcstrings`，它留在公開，不受影響。

### 3.4 `release-archive.yml`、`testflight.yml`、`website-screenshots.yml`、`ios-full-lane.yml`

- `release-archive.yml`、`website-screenshots.yml`：在 checkout 後加同一個 composite action。
- `release-archive.yml` 的 `paths` 有 `Assets.xcassets/**`；搬走後改成看 `private-assets.lock`。
- `testflight.yml`：
  - 三個 checkout 中，只有建置 archive 的那個 job 要加。
  - 它跑在 `testflight` environment，repository secret 照樣拿得到，所以 deploy key 放 repository secret 就好，不放進 `testflight` environment。
  - 這是 CLAUDE.md 說「不加觸發條件、不讓 PR 碰到它的 secret」的檔案：只加一個步驟，不改 `on:`。
  - 改這個檔案的 PR 要特別請作者看。
- `ios-full-lane.yml` 只是用 `workflow_dispatch` 啟動 `ios-build.yml`，不用改。
- `testflight-checks.yml`、`gltf-validate.yml`、`train-model-tools.yml`、`wasm-probe.yml`：不讀 Resources 的，不用改；動手前再 `grep` 一次確認。

### 3.5 `tools/` 的產生腳本

- 25 個工具資料夾把輸出寫到 `RailwayGameApp/Resources/...`（例如 `tools/real-railways/`、`tools/audio/`）。路徑不變，照樣寫進工作目錄；疊回的檔案在公開 repo 被 `.gitignore` 擋掉。
- 新的流程：
  1. 跑工具。
  2. 在私庫開 PR，提交輸出。
  3. 私庫合併後，公開 repo 開 PR 改 `private-assets.lock`。
- `tools/private-assets/sync.sh` 負責第 2 步：把疊回路徑的檔案複製回私庫的 checkout，並重算 `manifest.sha256`。
- 每個 README 的「產生」段落加一行指向它。
- `make_game_audio.py --check` 這種「重做要和提交的一樣」的檢查，改成和私庫的版本比。

### 3.6 開發 session 在 Linux 上怎麼拿到私庫

- 雲端 session 用 `add_repo` 掛上 `a91453/railway-game-data-private`（需要作者讓 Claude GitHub App 也裝到這個私庫，第 4 節）。然後跑：

  ```sh
  git clone --depth 1 https://github.com/a91453/railway-game-data-private /home/user/railway-game-data-private
  tools/private-assets/fetch.sh --from /home/user/railway-game-data-private   # 檢查 lock 的 SHA、疊回
  ```

- `.claude/hooks/session-start.sh` 加一段：私庫的資料夾在的話就自動疊回；不在的話印一行提示，不擋 session。
- CLAUDE.md 的「Environments and validation」加一段說明。
- 沒有掛私庫的 session，`swift build` 照樣過（GamePresentation 不在編譯期讀資源）。但讀資料的 70 個測試類別會紅，所以 CLAUDE.md 要寫明：碰到實景資料的工作必須掛私庫。
- Codex 走同一套（`AGENTS.md` 加同一段）。

### 3.7 其他

- **公開 repo 的守門**：搬走的路徑加進 `.gitignore`。另加一個很小的 CI 檢查：這些路徑若有檔案被 `git add -f` 加回，就紅。
- **Xcode Cloud**：目前延後（`docs/XCODE_CLOUD_ONBOARDING.md`）。真的要用時，`ci_scripts/ci_post_clone.sh` 要用同一把 deploy key（Xcode Cloud 的環境變數）跑 `fetch.sh`。

## 4. CI 怎麼拉私庫

| | deploy key（SSH，唯讀） | fine-grained PAT | GitHub App |
| --- | --- | --- | --- |
| 範圍 | 只有那一個私庫，唯讀 | 指定的 repo＋權限（Contents: read） | 安裝到的 repo＋權限 |
| 會不會過期 | 不會 | 會（最長一年，要記得換） | App 私鑰不過期；每次拿 1 小時的 token |
| 和作者帳號綁 | 不綁 | 綁作者帳號，作者帳號出事就斷 | 不綁 |
| 設定步驟 | 3 步 | 3 步 | 6 步以上（建 App、裝、存 App ID 與私鑰、workflow 換 token） |
| `actions/checkout` | 直接支援 `ssh-key:` | `token:` | 要先用 `actions/create-github-app-token` |
| 外洩的傷害 | 只能讀這一個私庫 | 只能讀指定的 repo | 只能讀安裝的 repo |

**建議 deploy key**：範圍最小、不會過期、不綁作者帳號、步驟最少。缺點是一把 key 只能開一個 repo，以後要拉第二個私庫就再一把。

**作者要做的**（建私庫之後；session 不碰金鑰）：
1. 在自己的電腦產生一把 key（不設密碼）：`ssh-keygen -t ed25519 -N "" -C "railway-game-ios CI" -f railway-data-deploy-key`。
2. 私庫 `railway-game-data-private` → Settings → Deploy keys → Add deploy key：貼上 `railway-data-deploy-key.pub`，**不要勾** Allow write access。
3. 公開 repo `railway-game-ios` → Settings → Secrets and variables → Actions → New repository secret：名稱 `PRIVATE_ASSETS_SSH_KEY`，內容貼 `railway-data-deploy-key`（私鑰）。然後刪掉電腦上的兩個檔案。
4. 讓 Claude 的 session 拿得到私庫：
   - github.com/apps/claude 的安裝設定裡，把 `railway-game-data-private` 加進可存取的 repo（或選 All repositories）。
   - 如果 claude.ai 的環境有限定 repo，也加進去。

**fork 來的 PR 拿不到 secret**：
- GitHub 不把 secret 給 fork 的 `pull_request` 執行。composite action 會在第一步失敗，印出原因，Swift CI (gate) 和 iOS 建置紅。
- 現在 fork 數是 0，所有 PR 都是作者和 session 在本 repo 開的分支，不受影響。
- 外人真的送 fork PR 時，維護者把它的 commit 推到本 repo 的分支再跑。
- **絕對不改用 `pull_request_target`** 去給 fork 秘密，那會讓外人的程式碼拿到 key。
- Dependabot 的 PR 也拿不到一般 Actions secret；本 repo 沒有 `dependabot.yml`，不受影響。

## 5. git 歷史：搬家只防得了以後

- CLAUDE.md 規定不 force-push `main`、不改寫歷史，所以已經提交過的檔案會一直留在歷史裡。任何人 `git clone` 後 `git checkout <搬家前的 commit>`，就拿得到當時的全部資料。
- 量到的（完整歷史，5,144 個 commit；把每個 blob 算在第一次出現的路徑下）：
  - 整個 pack 572 MiB；GitHub 回報 repo 大小 542 MiB。
  - `RailwayGameApp/Resources/` 的歷史：壓縮後約 228 MiB，佔 pack 四成。
    - `BaseMap/` 198 MiB，300 個版本；
    - `RealWorld/` 11.7 MiB；
    - `Audio/` 5.1 MiB；
    - `RealBuses/` 3.4 MiB；
    - `Assets.xcassets/` 2.0 MiB；
    - `RealRailways/` 1.7 MiB；
    - `Map3D/` 1.5 MiB。
  - `docs/art/` 的預覽圖另有 197 MiB。
- **換句話說，今天的價值 100% 已經在歷史裡**：搬家那一刻 `main` 上的每個檔案，前一個 commit 都還有。
- 搬家能保護的是以後：
  - 新的班表、新的公車、新的線；
  - 修正過的構造物資料；
  - 新的圖示與音效；
  - 改版的底圖。
- 現在這些變化很快：`RailwayGameApp/Resources/` 從 10-05 起有 270 個 commit 改過它，其中 106 個在 10-15 之後。所以幾週後，歷史裡那一版就會明顯落後。
- 要連歷史也清掉，只有兩條路，都違反現行規則，必須作者另外決定：
  - 改寫歷史（`git filter-repo` 加 force-push，所有 session 的分支都要重拉）；
  - 開一個全新的公開 repo，只放搬家後的樹，舊 repo 改私人。
- 這份計畫**不建議**走這兩條路：舊資料本來就會過時，代價（所有 PR、issue、#1041 的連結斷掉）太高。

## 6. 私庫放哪

| 選項 | 說明 |
| --- | --- |
| A. 放進 `a91453/railway-assets-private` | 現有的素材庫，1.3 GB；規則是單檔 ≤ 50 MB、一個 PR 新增 ≤ 200 MB、`asset_guard` 只認 `game-art-previews/docs/art/<model>/<round>/` |
| B. **另開 `a91453/railway-game-data-private`**（建議） | 只放 App 打包的檔案，路徑照公開 repo；自己的規則與檢查 |

`taiwan.pmtiles` 是 52 MB，已經超過素材庫單檔 50 MB 的規則。CI 每次也要從 1.3 GB 的庫裡稀疏拉出 143 MB。素材庫的規則和檢查是為「預覽圖輪次」設計的，打包資料的需求不同（要能被鎖到一個 commit、要有 SHA 清單）。

選 B，五方各一行：
- **玩家**：沒有差別；B 的 CI 拉得快，修正和新資料送到 TestFlight 比較快。
- **鐵道迷**：鐵道、班表、公車資料自成一庫，每次更新都有自己的 commit 與來源說明，比混在模型預覽裡好查。
- **開發**：
  - 路徑和公開 repo 一樣，疊回只要一個 `rsync`；
  - deploy key 只開這一個庫，外洩時素材庫不受影響；
  - 不必為 52 MB 的底圖破素材庫的規則。
- **美術**：素材庫的預覽、輪次規則照舊；圖示和模型的「成品」進 B，「過程」留素材庫，分工清楚。
- **音樂**：MML 原稿、樂譜和合成好的音效放在同一個庫，`--check` 在一處就能做完。

## 7. 拿來比較的 C 案與 B 案

### C 案：整個 repo 改私人

公開 repo 的 Actions 不收費；改成私人後，每分鐘照標準價計（2026-01-01 起的價格，GitHub 文件 `billing/reference/actions-runner-pricing`）：Linux 2 核 USD 0.006，macOS USD 0.062（約 10 倍）。作者帳號每月內含 USD 12（Free）或 USD 18（Pro）。

最近 7 天（2026-10-22 08:00 到 10-29 08:00 UTC）的用量：從 Actions API 讀 __RUNS__ 次執行的每個 job，以開始與結束時間計，每個 job 無條件進位到整分鐘：

| | 7 天（分鐘） | 換算 30 天（分鐘） | 單價 | 每月 |
| --- | --: | --: | --: | --: |
| Linux | __LIN7__ | __LIN30__ | USD 0.006 | USD __LINUSD__ |
| macOS | __MAC7__ | __MAC30__ | USD 0.062 | USD __MACUSD__ |
| 合計 | | | | **USD __TOTALUSD__**（扣掉 Pro 內含 USD 18 約 USD __NETUSD__） |

用最多的 workflow：__TOPW__。

C 案的其他代價：
- 私人的免費方案同時最多 20 個 job（macOS 5 個），比現在的 40 個少一半。CI 一個完整層就 22 個 job，排隊會變長。
- artifact 存量上限 500 MB（Pro 1 GB）。`ci.yml` 每次上傳 `.build` 給分片，會很快撞到。
- 官網、公開說明、別人看得到的 issue 都要另外處理。
- 好處是最乾淨：連 git 歷史一起關起來（第 5 節的問題消失）。

### B 案：資料在公開 repo 裡加密，金鑰放 secret

- 優點：
  - 單一 repo；
  - 檔案版本和程式一起走；
  - 不用第二個庫和 deploy key。
- 缺點：
  - 加密的大檔每改一次就是一個全新的 blob（不能差異壓縮）。底圖改 300 次就是 300 個完整的 52 MB，repo 會很快長大。
  - `git diff` 和審查看不到資料改了什麼。鐵道資料的 PR 審不了，golden 失準也追不到原因。
  - 每個 session 都要拿到解密金鑰。金鑰一旦外洩，歷史裡全部加密檔都公開，而且換金鑰也救不回已經 clone 走的版本。
  - 解密後的檔案在工作目錄，`.gitignore` 一漏就把明文推上公開 repo。
- 比 A 案差：A 案的私庫也有完整的 diff 與歷史，外洩時只影響那一把唯讀 key。

## 8. 有第三方授權的素材

搬家不改任何授權，只改檔案放在哪。要做的：

- **`Licenses/`（MapLibre、Noto Sans OFL）留在公開 repo 的 `RailwayGameApp/Resources/Licenses/`**，照樣打包進 App。OFL 要求字型散布時附授權，字形檔搬到私庫時，私庫的 `BaseMap/fonts/` 也放一份 `NotoSans-OFL.txt`。
- **`DataSourceCredits.swift`** 是程式，留公開，遊戲內「資料來源」頁不變。
- **ODbL（OSM、Overture 整理出的資料：底圖、建物、地名、水域、不可蓋地、廟宇、`track_*.geojson`）**：
  - 公開散布含這些衍生資料庫的 App（TestFlight、App Store）時，ODbL 4.6 要求同時提供衍生資料庫本身，或「做出它的方法或修改檔」。
  - 現在是靠公開 repo 裡的資料檔做到的（`LICENSE.md` 例外第 2 條）。
  - 搬走後改成兩件事：
    - 公開 repo 的 `tools/basemap/`、`tools/place-names/` 等產生腳本留著，README 寫明輸入（osmtoday 的抽取日期）與指令，滿足「方法」這條；
    - `LICENSE.md` 例外第 2 條改寫成「由 OpenStreetMap 或 Overture Maps 整理出的資料，依 ODbL 1.0 提供；產生方法在 `tools/`，資料檔向著作權人索取」。
  - 這段改寫屬於 PR 4，要作者看過。
- **TDX（政府資料開放授權條款第 1 版）、Copernicus DEM、WorldPop（CC BY 4.0）**：只要求標示出處，不要求公開資料檔。`DataSourceCredits` 已經標示，不用改。
- **Kenney（CC0）**：不要求任何事；私庫照素材庫的慣例留 `SOURCE.md`。
- **Meshy 產生的模型**：依素材庫已有的來源紀錄（`meshy-batch-2026-10/00_READ_ME_FIRST.md`），私庫同樣附一份。
- **私庫的 README** 列出每個資料夾的來源與授權，並保留每個上游的授權全文：拿 `Licenses/` 的副本，加上 `tools/*/README.md` 寫的出處。

## 9. 實作計畫

| 順序 | PR | 內容 | 工作量 | 風險 | 誰 |
| --- | --- | --- | --- | --- | --- |
| 0 | — | 建私庫 `railway-game-data-private`、deploy key、`PRIVATE_ASSETS_SSH_KEY`、讓 Claude App 能存取（第 4 節） | 10 分鐘 | 低 | **作者** |
| 1 | 私庫 #1 | 從公開 `main` 複製第 1 節「搬」的 761 個檔＋`tools/audio/mml`、`scores`，路徑不變；README（來源、授權、怎麼更新）、`manifest.sha256`、一個檢查清單與實際檔案相符的 workflow | 半天 | 低（約 143 MB，在 GitHub 單檔 100 MB 的上限內） | session |
| 2 | 公開 PR A | `private-assets.lock`、`tools/private-assets/fetch.sh` 與 `sync.sh`、`.github/actions/private-assets`；`ci.yml`、`ios-build.yml`、`release-archive.yml`、`website-screenshots.yml` 加步驟；`swift-shards.sh` 認鎖檔；session-start hook；CLAUDE.md、AGENTS.md 加說明。**這時公開 repo 裡的檔案還在**，疊回是同樣的位元組，CI 應該照綠 | 1 天 | 中（動 CI；要 `full-ci` 標籤跑全層、手動跑一次 full lane 與 release-archive） | session |
| 3 | 公開 PR B | `testflight.yml` 加同一步（只加步驟，不改觸發） | 1 小時 | 中（只有真的發版才驗得到；放在一次發版之前合，並請作者看） | session＋**作者看** |
| 4 | 公開 PR C | `git rm` 搬走的檔案、`.gitignore`、守門檢查、`tools/*/README` 的更新流程、`LICENSE.md` 與 README 的說明；`.xcodeproj` 不變 | 半天 | 中（合併後沒掛私庫的 session 跑實景測試會紅；先在 #1041 與 HANDOFF 公告） | session＋**作者點頭**（`LICENSE.md` 的文字） |
| 5（選做） | 公開 PR D | 把 N700S 頂點表、`CountryBorders` 等純資料大表從 Swift 換成 Resources 的資源檔（進私庫） | 1 天 | 中（列車雜湊、頂點鎖要逐位元組相同） | session |

- PR 2 到 4 一個合了再做下一個。PR 4 要在一次 TestFlight 發版之前至少經過一次完整的 nightly 與 full lane。
- 都不動 GameCore、存檔版本、golden、replay。
- 要取決策號：PR 2 開工時取一個新決策號，寫進 `docs/decisions/`，記下做法與五方。

**驗證 PR 2 的方法**：在分支上先暫時 `git rm` 一個小資料夾（例如 `RealRailways/`）推一次，確認 CI 靠疊回仍然綠；再還原，最後才推正式版本。

## 10. 這份盤點怎麼量的

- 檔案數、大小：`find`、`du`（main c82af9d）。
- 測試讀哪些檔：`grep "RailwayGameApp/Resources" Tests`（70 個檔）；`GameCoreTests`、golden、fixture 的 `grep` 都是空的。
- 歷史：`git fetch --unshallow` 後跑 `git rev-list --objects origin/main | git cat-file --batch-check`，依路徑加總 `objectsize:disk`。
- Actions 分鐘：Actions REST API 的 `runs` 與 `runs/{id}/jobs`，依 job 的 `labels` 分 Linux、macOS。腳本沒有提交，量法寫在這裡，可以重跑。
- 價格：GitHub 文件 `billing/reference/actions-runner-pricing` 與 `billing/concepts/product-billing/github-actions`，2026-10-29 讀取。
