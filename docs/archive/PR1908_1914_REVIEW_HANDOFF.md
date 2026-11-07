# 交接：PR #1908–#1914 審查（審查 L12）

派工單 REVIEW-L12（遊戲規劃第 53 任 session_01YGNNunyQhaha49M1KRzGVB，2026-11-07，HANDOFF §1.1 固定三件之一，119 發版之後這一輪）：審查 L11（`PR1858_1907_REVIEW_HANDOFF.md`）之後已合併、改到程式的 PR。格式同 L11。

- Session：REVIEW-L12 session_01YGNNupGkWdzqJpt3YuWtZQ，branch `claude/review-l12`。
- 基準：`main` **a3c83a0b**（#1914 合併後，119 發版的 commit）。開工時 #1915（BUILDNUM）還沒合，不在這一輪。每個 PR 讀 merge commit 對 first parent 的 diff，和它的決策檔。
- 點數（HANDOFF「多久審查一次」）：GameCore 0 個；GamePresentation／App／CI 7 個 × 1 = **7 點**，一輪看完，沒有用子代理。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

逐一核對 `git log --first-parent 6e525b2a..a3c83a0b`。

| 層 | PR |
| --- | --- |
| **GameCore** | 沒有。`Sources/GameCore` 從 #1883（1838127）之後沒有改過 |
| GamePresentation／App | **#1876**（MAP3D-MEM-1，決策 608：模型上 GPU 後放掉 CPU 的頂點）、**#1879**（FACADE-REAL，決策 610：實景建物面街立面）、**#1905**（ROUNDHOUSE-STOCK，決策 581 後來：扇形車庫停機車）、**#1911**（L11FIX-A：L11-1、L11-3）、**#1912**（L11FIX-B：L11-2、L11-4、L11-5、L11-6、L11-7）、**#1914**（119.1 更新說明） |
| CI | **#1909**（`swift-shards.sh` 的 started 行不錨定行首） |

沒有審的：

- 只改文件的有 #1908、#1910、#1913（HEALTH-119 報告與報告測試）。
- #1903 只加 `tools/thsr-liujia-depot-studies/` 與 `docs/art/`，遊戲沒有載入（模型，0 點）。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **1**：L12-1 |
| P3（記著） | **3**：L12-2 到 L12-4 |

- 沒有 P1，所以沒有 send_message 通報。
- 這一輪沒有 GameCore 的 PR，決定性、存檔、golden、replay 都沒有被碰到。
- 上一輪的修正確認：
  - **L11-1**（#1911）：修好。`layRealRun` 留哪些取樣點、在哪裡切 256 m 的塊、高架的墩放哪裡，都改看整條線上的位置（`along`），不看這段從哪裡開始。藏掉一段只影響它兩邊的塊。新的回歸測試在 `Map3DSceneRebuildTests` 裡，過（**VERIFIED**）。
  - **L11-3**（#1911）：修好。`glideSeconds` 在兩個 tick 相差超過 `durations.upperBound`（5 s）時改用 `tickSeconds`；`RealTrainClock`（`RealTrainMotion.swift:1001`）用同一個函式，所以也修好。`TrainMotionTests`、`RealTrainMotionTests` 過。
  - **L11-2**（#1912）：修好。`canAfford` 放進 memo 的鍵（`SightMarks.swift`），每次讀都算，只是一個比較。`SightsPanelCostTests` 過。
  - **L11-4**（#1912）：修好。`readsLandForFerries` 放進鍵。`FerryCijinShoreTests` 過。
  - **L11-5**（#1912）：修好。換成月台的點之後，再查一次在不在地圖內。
  - **L11-6**（#1912）：118 的英文名稱都照 App 改了。
  - **L11-7**（#1912）：修好。`sightUnreachable` 加了 `edge`，沒有對外連接時不提地圖邊緣。
  - **L11-8**：**還成立，還沒派**。`RunDepot.swift` 從 #1881 之後沒改過：`trainsInTheWay(memo:)`（375 行）每次都呼叫 `heldRunDepartures`（382 行），`runDepotEntryCandidates`（228 行）又各算一次。仍是 P3，**UNVERIFIED**（沒有量）。

### GamePresentation／App

- **#1876**（決策 608）：
  - 模型做好後，在背景上 GPU，CPU 只留名字、頂點數、外框、燈、方向幕、玻璃；`Map3DModelPack.standard` 的頂點也放掉。
  - 查過 App 與 GamePresentation 在放掉之後還讀不讀 `standard` 的頂點：
    - App 沒有直接讀 `standard`。
    - `Map3DCityBus.pack` 只在 `makeModels()` 裡用，而 `start` 有 `started` 擋著，只會跑一次。
    - 街景、路邊物、公車只用 `index(of:)`，看名字。
    - 各套件的 `includeStandard` 只在工具與測試裡用。
    - 所以沒有在放掉之後才讀頂點的路。
  - 並行：
    - 第二個呼叫 `make()` 的人看到 `uploading`，就只排進 `waitingForUpload`。
    - 上傳的 task 要在 MainActor 上才能叫醒等的人。continuation 是同一段同步程式裡加進去的，所以不會先叫醒才加。
  - `StandardPack.pack` 在鎖裡做模型，和原來 `static let` 的 `swift_once` 一樣會擋住同時來拿的人，沒有變差。
  - 沒有 Metal 時 `uploaded` 是 nil，列車一直畫成方塊。這和原來 `useModels` 失敗時一樣。
  - `MapView` 新加的捏合紀錄只在手勢開始與結束時寫，不在 `.changed` 寫。
  - 沒發現問題。`Map3DModelPackSlimTests` 過；臨時測試確認 `withoutVertices()` 的頂點數和原本一樣、頂點都是空的（**VERIFIED**，已刪）。
- **#1879**（決策 610）：有 **L12-1**、**L12-2**。其餘查過的都對：
  - 每區塊上限照 `r(999)` 排序，所以整個蓋和一區一區串流蓋出來一樣。`Map3DStreamingTests` 新加的斷言逐區比 `facade` 的頂點與索引，過。
  - 粗略的區塊（`isCoarse`）不蓋立面。
  - `Map3DRealBuildings` 的 `defer { facadeStreets = nil }` 在迴圈本體裡，每一區結束就清掉。
  - 局部重蓋（`Map3DSceneRebuild`）整塊換掉，`facade` 跟著換；Metal 的 `Chunk` 重做，`facade` 緩衝是 nil，下一幀才重新上傳。
- **#1905**：有 **L12-3**。
  - 停的機車只有 `plain` 層（臨時測試列出 R100、R200 遠近四款的層，全是 −1），不會在晚上亮窗，也沒有車用材質（−13…−17）跑進城市區塊的 shader。
  - `LandmarkMesh` 的庫位角度與半徑改成共用常數，值和原來一字不差。`Map3DTaipeiLandmarksTests` 過。
- **#1911**、**#1912**：見上面「上一輪的修正」。
- **#1914**：有 **L12-4**。

### CI

- **#1909**：`started` 與 `failed` 改成不錨定行首，處理測試自己的 print 黏在 XCTest 那一行前面的情況。
  - `sed` 的 `^.*` 是貪婪的，一行裡有兩個 `Test Case '…' started` 時取最後一個。實際上不會有。
  - 自我測試加了 `glued` 模式，本 session 跑 `.github/scripts/swift-shards-selftest.sh`，全過（**VERIFIED**）。
  - 沒發現問題。

### App

- 畫面、Metal、`Map3DMetalView` 的立面上傳、`Map3DTrainModels` 的上傳流程都是 **UNVERIFIED**（沒有 macOS），只讀程式。

## 二、發現

### L12-1（P2）#1879：立面層的 CPU 記憶體一直留著，連最低等級的機器、省電時也留著

- **位置**：
  - `Sources/GamePresentation/Map3DScene.swift:73`：`Chunk.facade` 是場景的一部分，蓋場景時不看機器等級，每次都蓋。
  - `RailwayGameApp/Views/Map3D/Map3DMetalView.swift:232`、`:1001`：Metal 的 `Chunk` 存著 `facadeMesh`（CPU 的頂點與索引），一直留到區塊被換掉。
  - `Map3DMetalView.swift:650` 的 `Map3DRealFacade.draws(...)` 與 `releaseFacades()` 只放掉 GPU 的緩衝。
- **問題**：
  - 決策 610 寫「這 +12 % 不是常駐的：立面層只在近景區塊上傳、不畫時放掉」。這只對 GPU 那一份成立。
  - CPU 那一份留在場景裡。`Map3DSceneCache`（決策 269）與畫面上的 `Map3DPreviewScreen.built` 都留著場景，Metal 的 `Chunk` 也留著。
  - 決策 610 自己量的板橋場景是 **+44 028 992 B**（+12.0 %），這一份在所有機器上都常駐。
  - `.lower` 等級、省電畫質、低耗電模式、過熱時根本不畫立面，卻照樣付這 44 MB 與蓋它的時間。這些正是最缺記憶體的情況。
  - 畫的時候，近景區塊上傳後，GPU 一份、CPU 一份。iPhone 是共用記憶體，近景那部分是兩倍。
- **玩家看到**：舊機在板橋這種密集市區開 3D，比 118 多用約 44 MB。比較容易收到記憶體警告、被系統關掉。
- **驗證**：
  - 讀程式，**VERIFIED**：留住的路徑如上。
  - 數字取自決策 610 的 `Map3DRealFacadeReportTests`（Linux，debug）。本 session 沒有重跑，那支要 App 的底圖檔，一次約 2 分。
  - 機器上的實際記憶體：**UNVERIFIED**（沒有 iPhone）。
- **修法建議**（擇一，和在做的 MAP3D-MEM-2 協調）：
  - 蓋場景時帶「這台會不會畫立面」（`Map3DRealFacade.draws` 的等級部分，`tier > .lower`），不畫就不蓋 `facade`。省電與過熱是會變的，那兩種情況照現在只放 GPU。
  - 或在 Metal 的 `Chunk` 上傳後放掉 `facadeMesh`，並從 `Map3DSceneCache` 留的場景裡拿掉 `facade`。重新上傳時，再從場景重蓋那一區，或在背景重算。
  - 回歸測試（Linux）：等級 `.lower` 蓋出的場景，每塊的 `facade.isEmpty`。

### L12-2（P3）#1879：立面緩衝在主執行緒、畫圖的那一幀裡做

- **位置**：`Map3DMetalView.swift:1085-1090`。區塊第一次進近景、而且要畫立面時，就在 `draw` 裡 `makeBuffer` 頂點與索引。
- **問題**：
  - 每區最多 10 000 個三角形，約 0.9 MB。
  - 第一次打開市區的近景，或記憶體警告 `releaseFacades()` 之後，看得到的近景區塊都會在同一幀裡上傳。十幾塊就是十幾 MB 的複製，可能掉一兩幀。
  - 另外，記憶體警告時放掉的緩衝，只要那一區還在近景，下一幀就重做。所以如果等級沒有降，放掉幾乎沒有省到。
- **驗證**：讀程式，**UNVERIFIED**，沒有量。
- **修法**：一幀最多上傳 N 塊（像串流那樣分幀）；記憶體警告時，等 `load.relieve()` 讓等級降到 `.lower` 再放。

### L12-3（P3）#1905：每次蓋場景都重做四輛機車的模型，而且不共用

- **位置**：`Sources/GamePresentation/Map3DTaipeiLandmarks.swift:2848` 呼叫 `Map3DRoundhouseStock.model(full:)`（`Map3DRoundhouseStock.swift:66`）。
- **問題**：
  - 每次蓋到彰化扇形車庫（整個蓋、串流、局部重蓋），都重跑 `Map3DR100.model`、`Map3DR200.model`。R200 的 `roundedEnds` 用字串當鍵，所以慢。
  - 結果每次都一樣，卻沒有存起來。
  - 四輛車是逐頂點寫進城市區塊（沒有索引共用、沒有 instancing）：近景 120 120 個頂點（約 4 萬個三角形、4.8 MB），遠景 51 384 個（約 1.7 萬個三角形）。
  - 比較：決策 610 量的最忙近景區塊是 15 534 個三角形。也就是遠看時，四輛機車就有 1.7 萬個三角形。
- **驗證**（臨時測試，Linux，debug，**VERIFIED**，已刪）：`model(full: true)` 850 ms、`model(full: false)` 299 ms。release 版應該快很多；iPhone 上沒量（**UNVERIFIED**）。
- **修法**：
  - 把兩個版本存成 `static let`（結果和世界無關）。
  - 遠景用比較粗的版本，或只畫車頭露在門外的部分（庫裡的車身被屋頂蓋住）。
  - 或改成像路邊物那樣用模型包的 instancing。

### L12-4（P3）#1914：119.1 的更新說明有兩處和實際不符

- **位置**：`Sources/GamePresentation/WhatsNew.swift`，`2026-11-07-119-1`。
- **問題**：
  - 「The cab window view no longer jerks along in fits and starts. ／車窗視角走走停停的問題修好了。」CABVIEW-2（#1579 的登記，session_01YGNNuo1avNxcoZmdFdC825）回報 119.1 的高雄環狀輕軌 10× 跟車仍然「動 0.3 秒、停 2.2 秒」。所以這句說得太滿。
  - 「The Changhua roundhouse」：App 的景點名（`AttractionCatalog.swift:135`）和較早一條說明（`WhatsNew.swift:310`）都是「Changhua Roundhouse」（大寫 R）。和 L11-6 同一類。
- **影響**：119 已發。照 HANDOFF「PR 綠了就不再推小修」，等 CABVIEW-2 或下一版本來就要改 `WhatsNew.swift` 的 PR 一起帶。CABVIEW-2 修好時，120 的說明可以寫「10× 跟車也不再走走停停」。

## 三、驗證紀錄

- `swift build --build-tests`（Linux，Swift 6.4.0，debug）：成功。
- `swift test --skip-build`（Linux，**VERIFIED**），13 個類別全過：`Map3DSceneRebuildTests`、`TrainMotionTests`、`RealTrainMotionTests`、`FerryCijinShoreTests`、`SightsPanelCostTests`、`TourismSessionTests`、`Map3DModelPackSlimTests`、`Map3DRoundhouseStockTests`、`Map3DRealFacadeTests`、`Map3DStreamingTests`、`Map3DTaipeiLandmarksTests`、`StationMasterAdviceTests`、`WhatsNewTests`。
- `.github/scripts/swift-shards-selftest.sh`：過（**VERIFIED**）。
- 臨時測試 `ZZReviewL12ProbeTests`：機車的層與蓋的時間（L12-3）、`withoutVertices()`（#1876）。都已刪除，工作目錄乾淨。
- 畫面、Metal、iOS 記憶體、UI 測試：**UNVERIFIED**（沒有 macOS，沒跑 iOS workflow）。

## 四、下一輪

- REVIEW-L13 從 **#1915** 起（`main` a3c83a0b 之後）。
- 還沒派的：
  - L12-1（P2）、L12-2 到 L12-4。
  - L11-8。
  - 之前的 L9-4、L9-5、L9-7、L10-4 到 L10-13。
