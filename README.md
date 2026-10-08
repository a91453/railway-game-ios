# Along the Line

Along the Line（沿線）是一款鐵路與城市發展模擬遊戲，以 iPhone / iPad 為主要平台。玩家規劃鐵路、車站與運輸網路，而城市會沿著交通建設逐步成長。核心概念：「鐵路是原因，城市是結果。」長期目標是玩法深度接近《A列車》系列的原生 Apple 平台遊戲。

正式名稱：English **Along the Line**、繁體中文 **沿線**、日本語 **沿線**。App 顯示名稱由 `project.yml` 的英文預設值與 `Resources/{en,zh-Hant,ja}.lproj/InfoPlist.strings` 設定；開始畫面的品牌名稱與介紹使用 String Catalog（日文品牌已設定，其餘尚未翻譯的介面維持英文 fallback）。內部 `RailwayGame` target、scheme、module、Bundle ID 與存檔識別碼保留。

AppIcon 使用定稿 package 的兩張原始 1024×1024 PNG：Any／Default 為 `along-the-line-app-icon-light.png`（米白背景），Dark 為 `along-the-line-app-icon-dark.png`（深色原稿）。iOS／iPadOS 18 以上依主畫面 icon appearance 選擇；較早版本使用預設淺色版。沒有自訂 Tinted variant，由系統生成；SVG 與 preview 不放入 App bundle。

## 目前狀態

**Early development — GameCore + native prototype UI（Phase 2B）；Phase 4.6 Stage T（進路預約）；G1a（車站需求與乘客）；G1b（上下車與容量）；G1c（票價、帳本與畫面）.**

目前有與畫面無關的模擬核心（`GameCore` Swift Package）、與平台無關的 Presentation 邏輯（`GamePresentation`），以及可操作的原生 SwiftUI prototype App（`RailwayGameApp/`，iPhone / iPad）。GameCore 已有列車位置、沿明確路徑移動、最短路徑搜尋與停站（Phase 3 Stage N）的核心，每台列車的時刻表資料（Phase 4 Stage O），依時刻表執行服務的核心（Phase 4 Stage P：到達、停留到排定出發、出發），在終點站折返、每隔固定週期重複的時刻表（Phase 4 Stage Q1），服務線路的資料與推導（Phase 4 Stage Q2a），依線路自動派車（Phase 4 Stage Q2b），交路與快慢車等服務模式、各段共用的容量（Phase 4 Stage Q3），道岔與平面交叉、列車佔用的軌道資源、區段與股道數（Phase 4.5 Stage S1），多格車站、月台股道與多節列車（Phase 4.5 Stage S2），以及連續軌道路網（Stage F3c 起是唯一的鐵軌，方格已移除）：任意方向的直線與曲線、由邊端方向推導的道岔與平面交叉、在不同長度的邊上連續行駛的多節列車（Phase 4.5 Stage S3），高程、坡度、地面／高架／橋／隧道等結構物、立體交叉的淨空、隧道口與多層月台（Phase 4.5 Stage S4），以及路網上的停站、時刻表、線路與自動派車：列車停在路網月台的末端、以整數的實際距離計算行程（Phase 4.5 Stage S5），以及交通控制下的進路預約：列車出發前一次取得整條路的節點與 span，拿不到就等待（Phase 4.6 Stage T），以及車站的需求、每分鐘以整數釋出的乘客、車站的排隊與乘客守恆的稽核（G1a），列車離站時的上下車與容量（G1b），以及經營模式下的票價、每小時與每天的結算、帳本與經濟面板（G1c）；App 以最小的工程畫面（Train 工具，Phase 3 Stage M）操作列車，並有線路面板（Stage R：線路、交路與快車、各等級的列車數與班距、覆蓋缺口）與列車的服務狀態（早到或誤點）。交通控制下另有避占用選路（Stage V1）與死結的偵測與解除（Stage V2）。**尚未**有事前排定的待避與交會或城市模擬。

目前的地圖畫面是 **prototype**：SwiftUI Canvas 畫出土地與連續路網的俯視 debug 投影（沿取樣的中心線畫出邊與路網上的列車；高度只表現在由低到高的繪製順序與結構物的樣式：隧道是虛線、高架有陰影）。真正的 3D renderer、建造連續軌道的畫面與 spline 編輯器都還沒有開始；GameCore 只提供給 renderer 讀取的整數幾何查詢（`railwaySnapshot()`、`trackAlignment(of:)`、`trackGeometry(of:)`、`location(of:)`、`bodyPath(of:)`），它們是未來 3D renderer 的權威輸入。

App 目前能做到：

- 顯示 `GameWorld` 的世界（新遊戲 16 公里見方，示範地圖在中央），路網、車站與列車以不同形狀繪製；可捲動、縮放
- 點選地圖：選到手指附近的車站或列車，並記下點選的那一點（F3d 起不再以格為單位）
- 工具：選取、路網（建節點與邊、月台、車站）、列車
- 建設透過 GameCore 指令執行；失敗時顯示玩家看得懂的訊息，世界不變
- 繁體中文與英文：跟著系統語言切換（ARCHITECTURE 決策 38）
- 音樂與音效：和第一支介紹影片相同的配樂循環播放；列車到站有到站鈴、鋪好軌道有鐵軌接縫聲、換工具有「咻」聲；遊戲選單可以分別關掉音樂與音效（ARCHITECTURE 決策 79）
- HUD：現金、遊戲時間（`Day 1 · 08:30`／`第 1 日 · 08:30`，慢速或在分鐘中間時加上秒）、暫停／播放與速度選單（1× 真實時間、10×、60×、600×、1200×；新遊戲是 600×）
- `GameSession` 的 game loop 把真實時間換算成整數 tick 推進遊戲時間與列車；App 不在前景作用中（背景、控制中心、App 切換器）時停止，回來不補跑
- Train 工具：購買列車、放置在選取車站的路網月台（選朝向）、設定 rate、把列車送到選取的車站（GameCore 求路後原封不動提交為路；到不了時什麼都不改）、反向、取下；顯示 GameCore 記錄的位置、剩餘路徑、rate 與停在哪些車站，地圖在列車的權威位置畫出列車（每個 tick 跳一步，不插值）

GameCore 目前能做到：

- 建立指定範圍的世界（`WorldBounds`：每邊 1…2^20 世界單位，64 單位一公尺，最大 16,384 公尺；F3d 起沒有格子）；鐵軌在路網上
- 建造車站：在世界座標的一點（唯一、可保存的 Station ID）
- 購買列車（新車未放置）；把列車放到路網的邊上、取下、原地反向（`placeTrain`、`unplaceTrain`、`reverseTrain`）
- 遊戲時間：開局以來的遊戲秒（Stage W2a），基本步長一秒；速度是每 tick 的十分之一秒，宿主每 100 ms 一個 tick，所以 `x1` 是真實時間，不足一秒的部分留到下一個 tick。到站、停站與發車每秒判定，派車、乘客釋出與帳在整分鐘處理
- 列車與線路的性能（Stage W2c）：加速度、減速度、最高速度（可以有備用值與惰行），預設是標準性能，另有作者參考資料裡的車種（含 `Ci/` 的地鐵列車）；`setTrainPerformance`、`setLinePerformance` 更換
- 列車移動：設定 rate（每遊戲分鐘的邏輯單位，分到每一秒）與明確的路（`setTrainMovementRate`、`setTrainContinuation(_:along:stoppingAt:)`），隨時間逐步沿指定路徑前進；不自動選路。前方鐵軌被拆時等待，補回後自動續行
- 路徑搜尋：`route(from:to:)` 找出到路網節點的最短路，`path(from:toStation:)` 到車站的停車位置，結果可直接交給 `setTrainContinuation(_:along:stoppingAt:)`；只查詢、不改變世界
- 停站：車站的月台在路網的邊上；列車的路走完、車頭在月台上時停在該站（`stationsStoppedAt(by:)`）。都由狀態推導，不另存
- 時刻表：每台列車有依序的停靠（車站、排定的到達與離開，開局以來的遊戲秒），以 `setTrainTimetable` 整份替換；時間不倒流、車站必須存在。時刻表本身是計畫資料，只有明確啟動的服務會讀它
- 時刻表服務：`startTrainService` 讓停在第一站的列車依時刻表跑一次（`stopTrainService` 結束）。每一站停站（Stage W2b）：到站 8 秒後開門、上下車（人越多越久）、至少停 36 秒（第一站、最後一站與折返的站 42 秒）、關門 9 秒；不會早於排定出發時刻離開，誤點時停完就走；兩站之間跟著列車性能的行駛曲線走（Stage W2c：加速、定速、惰行、煞車），走排定出發到排定到達的時間，準時出發就準時到達、晚出發整段往後移，排得太緊時盡快跑；已停在下一站時零距離到達（也停站），沒有路就關著門等待，最後一站停完、到了排定出發才結束。執行進度（第幾個停靠）與實際的到達、出發時刻是存檔的權威狀態，誤點由它們算出（`lateness(of:)`）；執行中不能手動改路、反向、取下或換時刻表
- 折返與重複：停靠可以標記「在這站折返」，服務離開時先讓列車原地反向（找不到路時不反向），讓列車能從死路的終點站往回開。時刻表可以每隔固定週期重複（`setTrainTimetable(_:to:repeatingEvery:)`），一輪接一輪執行，執行進度同時記錄第幾輪；重複的服務從下一個準時的輪次開始
- 服務線路：依序的車站、規劃行程用的性能、營運時間，以及尖峰／離峰／低峰各跑幾台列車或目標班距；世界的服務日決定每分鐘是哪個等級。由地圖推導線路的來回行程（每一段是性能建得出行駛曲線的最少整秒，Stage W2c）、最多列車數（最短班距 2 分鐘）、實際列車數與班距
- 自動派車：用 `assignTrain` 把列車交給線路後，線路每分鐘檢查一次：營運中、這個等級有車要跑、距上次發車已過一個班距、跑車中的列車少於該等級的列車數時，就讓停在第一站的列車跑一個來回（產生該趟的時刻表並啟動服務）。列車回到第一站後原地折返等待，減車時多出的列車就停在那裡；線路的列車不能手動設定時刻表或啟停服務
- 連續軌道（Phase 4.5 Stage S3）：以整數世界座標（64 單位一公尺，世界沒有格子，F3d）建造節點，節點之間以直線或兩個整數控制點的三次曲線建造邊（`buildTrackNode`、`buildTrackEdge`）；長度與取樣由固定的整數規則推導。只有共用節點的邊才會相接，離開節點方向相反的邊端互通，所以道岔、平面交叉自然成立，平面上交叉但沒有共用節點的邊互不相干。列車可以放在邊上、沿邊移動（`setTrainContinuation(_:along:)`）、反向，車身跨越多條邊
- 立體鐵路（Phase 4.5 Stage S4）：節點可以在地面上下 64 公尺（4096 單位）以內；邊沿水平里程有縱斷面（固定坡度，或兩端的拋物線豎曲線），最陡 40‰；結構物（地面、高架、橋、隧道）決定可以蓋的高度與費用。兩條鐵軌在平面上相遇時要相差 8 公尺以上（立體交叉，不共用資源），同一高度的交叉必須共用節點（平面交叉）。隧道口由邊推導；車站可以在路網上平坦的一段邊上有地面、高架或地下的月台（`addTrackPlatform`）。位置帶坡度（pitch），車身路徑是 3D 的
- 路網上的營運（Phase 4.5 Stage S5）：停站、時刻表（折返與重複）、線路、自動派車、交路與快車都能在路網上運作。以車站為目的地的路（`path(from:toStation:length:)`，`TrainPath`）停在行進方向上月台的末端，只找放得下整列車的月台，距離是整數的實際里程；列車的路可以停在邊的中段（`setTrainContinuation(_:along:stoppingAt:)`）。服務正在使用的月台不能拆
- 進路預約（Phase 4.6 Stage T）：交通控制開啟時（`setTrafficControl`，App 的新遊戲預設開啟），列車出發、被派車或拿到新的路之前，一次取得從車尾到路的終點整列車會碰到的每個節點與 span（`reservedResources(of:)`）；被其他列車持有（`heldResources(of:)`）時整個不取得，服務原地等待並每步重試（`trainHoldingRoute(of:)` 回答在等哪一台）。經過道岔與平面交叉的進路在共用節點衝突，停在交會點附近的列車也持有它，立體交叉互不衝突；預約中的鐵軌不能拆或改月台。預約存檔，走完路時釋放；列車每次移動之後只留下還需要的部分，車尾離開的軌道立刻釋放（Stage U1）。服務出發時路被行駛中、一定會讓出的前車持有，就跟車出發：只預約到前車持有的軌道之前 400 m（參考的 `BLOCK_GAP_KM`），走到那裡停下，每一秒延長，前車離開它的路之後取得剩下的全部（Stage U2）。服務出發與線路派車就緒判斷先嘗試預設路整條取得，再在預設路上跟車；都不行時改找同站任何合適月台的避占用最短路並整條取得，否則等待（Stage V1）。替代路新增借用的軌道也避開還會開的列車所用的反方向：執行中的服務從它所在的位置往後的每一段，以及有已放置列車的線路的整個計畫；對向服務在數段之外、線路尚未營運（但已有列車）時仍受保護，單線共用的預設走廊照常取得；改走的路最多比預設路長 400 m。方向是短期推導值，不存檔。交會站有空的另一月台時，對向列車可以各走一個月台後繼續到對面；只互相等待的列車是死結（`deadlockedTrains()`）：每個整分鐘，調度把其中一台服務送到途中某站的待避站（`passingPlace(of:)`），讓另一台先走，再續行；解不開的死結在列車面板上告訴玩家（Stage V2，存檔版本 8）。手動路與交通控制關閉時照舊。事前排定的交會與待避、單線容量與畫面授權範圍仍待後續工作
- 車站需求與乘客（G1a）：`setStationDemand` 設定車站的類型（住宅、辦公、商業、景點）與每天的旅次。每天的旅次分給同一條線路能到的車站，再依一天的形狀與兩端類型的曲線（移植自作者的 `Ci/` 網站）分到 24 小時；每分鐘以整數釋出，任何連續 24 小時正好是一天的量。乘客在起點依線路、方向、迄點成組排隊（先來的在前，一站最多 4000 人，放不下的記為溢出）；線路改變而不再載他們時記為放棄。每一站 `released = 等車 + 溢出 + 放棄`（`passengerLedger(of:)`）。
- 上下車與容量（G1b）：列車每離開一站，先讓坐到那一站的人下車，再讓等它的線路與方向、要去它到下一次折返前會停的站的人上車（下車站遠的先上，移植自 `Ci/` 的 `allocateSeats`），最多到容量（每輛 352 人：額定 320 × 1.1）；上不去的記為被拒絕。車上的人記在列車上（`riders(of:)`），每一站 `released = 等車 + 車上 + 到達 + 溢出 + 放棄`。
- 票價、帳本與經營（G1c）：新的世界是自由模式；經營模式（App 的新遊戲）下乘客上車時付票價（均一或依兩站的點之間精確的直線距離分段，移植自 `Ci/` 的地鐵經濟，F3d 起不再以格量化），每個整點結算營運與維修、每個午夜結算能源與人事（餘額可以變成負數），寫進帳本與每日的帳（`financeReport(_:)` 的日、週、月、年）；設定過票價時票價影響需求。金額是美分，畫面以美元顯示。
- 整數金額的資金與建設成本
- 可暫停、1x、2x 的 deterministic 遊戲時鐘（2x 為每 tick 兩個基本步長；時間溢位時整批拒絕）
- 所有核心狀態可 `Codable` 編碼 / 解碼

### 建設規則

| 動作 | 條件 | 成本 |
| --- | --- | --- |
| 建節點 | 點在世界範圍內（`0 <= x < 寬`、`0 <= y < 高`，世界單位）、高度在地面上下 4096 以內、該點沒有節點 | 免費 |
| 建邊 | 兩端的節點存在且不同；曲線的控制點在世界範圍內；坡度、立體交叉的淨空與線間距合法；資金足夠 | 每 1024 單位（16 公尺，`ConstructionCosts.trackPricingLength`）或不足的部分收一次 `ConstructionCosts.track`，乘上結構物的倍數 |
| 拆邊 / 拆節點 | 邊上沒有列車、月台，交通控制下沒有被預約；節點上沒有邊 | 免費，**不退款** |
| 建站 | 名稱非空白、點在世界範圍內、資金足夠；車站是一點，月台另外加在路網的邊上 | `ConstructionCosts.station` |
| 加月台 | 車站與邊存在；範圍在邊上、不與其他月台重疊、平坦 | 免費 |
| 購買列車 | 名稱非空白、資金足夠 | `ConstructionCosts.train` |
| 放置列車 | 列車存在且未放置；位置在路網的邊上（`0 <= offset <=` 邊長），後方的軌道放得下整列 | 免費 |
| 取下 / 反向列車 | 列車存在且已放置 | 免費 |
| 設定 rate / 路 | 列車存在且已放置；rate 非負；路從列車前方起每一步都相接、不折返 | 免費 |
| 設定時刻表 | 列車存在（放置與否皆可）且不屬於任何線路；時間從 0 起不倒流（每站 arrival ≤ departure ≤ 下一站 arrival）；每站都是存在的車站；`[]` 清除 | 免費 |
| 指派列車到線路 | 列車與線路存在；列車不屬於任何線路，也沒有自己的服務在執行 | 免費 |
| 開關交通控制 | 開啟時任兩台列車需要的軌道不重疊；開啟後，放置、反向與設定路要取得的軌道不能被其他列車持有，預約中的鐵軌不能拆、持有的邊不能加減月台、持有的交會點不能加邊 | 免費 |

任何失敗都會丟出 `GameError`，且世界狀態（路網、資金、車站、列車與時刻表）完全不變。餘額永遠不會因建設變成負數。

## 技術方向

- Swift 6（language mode 6）
  - 最低 Swift tools version：6.0（`swift-tools-version: 6.0`）
  - CI 與本機檢查只用 Swift 6.4（2026-10-05 起不再驗證 6.0）；其他版本（例如 iPad Swift Playgrounds 的 6.2.x）不另外驗證
- Swift Package Manager
- XcodeGen（由 `RailwayGameApp/project.yml` 產生 Xcode 專案，產生結果提交進版控）
- SwiftUI（Presentation；Phase 2B prototype UI，iOS 17+，iPhone / iPad）
- SpriteKit / Metal（Rendering，未來依效能需求評估）

## Architecture

| 層 | 狀態 | 職責 |
| --- | --- | --- |
| **GameCore** | ✅ 本階段 | 權威遊戲狀態與規則；不依賴任何 UI / rendering framework |
| Presentation | ✅ Phase 2B prototype UI | `GamePresentation`（session、tick 換算、顯示文字）與 SwiftUI 介面、輸入、HUD |
| Rendering | 未開始（目前的 SwiftUI Canvas 地圖是 prototype：土地與連續路網的俯視 debug 投影） | 地圖與列車的繪製、動畫；只讀 GameCore 的幾何查詢 |

Presentation 與 Rendering 只讀取 GameCore 狀態並送出指令，不持有另一份遊戲真實狀態。App 以 SwiftUI `@State` 持有唯一一個 `GameSession`，由它持有唯一一份 `GameWorld` 並執行所有指令與 game loop。詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，未來規劃見 [docs/ROADMAP.md](docs/ROADMAP.md)。

Swift 版 GameCore 是目前的參考實作；`GoldenScenarios/` 的 JSON 情境把它的行為寫成與語言無關的 fixture，GameSession 則是可替換的平台 shell。是否移植到 Unity / Godot 尚未決定；目前只保留逐一子系統移植並以同一批情境驗證的路徑（ARCHITECTURE 決策 13）。

```
Sources/GameCore/
  World/     GameWorld、WorldBounds（世界的範圍，世界單位）、GameError、SavedGame（帶版本的存檔）、GeoAnchor、LegacyGrid（只給舊存檔解碼）
  Geometry/  WorldCoordinate / PlanPoint / PlanVector（整數世界座標）、TrackCurve 與 TrackGeometry（曲線的取樣、長度、位置、高度與坡度）、TrackProfile（縱斷面、坡度、結構物）、TrackClearance（立體交叉的淨空）、FixedPoint（整數平方根等）
  Railway/   TrackGraph（TrackNodeID、TrackEdgeID、TrackTraversal）、RailwayNetwork（連續路網）、RailwayNetworkTrains（路網上的列車與 renderer 查詢）、TrackPlatform（路網上的月台）、RailwaySnapshot（給 renderer 的唯讀快照）、Station、Train、TrainPosition、TrainMovement、TrainRoute（路徑搜尋）、StationStop（月台與停站）、Timetable（ScheduledStop）、TimetableExecution（服務的執行進度）
  Economy/   Money、GameEconomy、ConstructionCosts
  Time/      GameClock、GameSpeed、GameTime
Sources/GamePresentation/
  GameSession（持有 GameWorld、UI 暫時狀態、game loop）、TickAccumulator、
  ConstructionTool、MapScale / MapCamera、NetworkSession（路網工具）、DisplayText（玩家看到的文字）、
  GameLauncher（開始畫面、自動存檔）、SaveLibrary（存檔檔案）、NewGame（新遊戲與示範地圖）
Tests/GameCoreTests/
Tests/GamePresentationTests/
GoldenScenarios/  可移植的 golden scenario（JSON，schema 見該目錄的 README）
SaveFixtures/     每個存檔版本的回歸存檔，之後的版本都必須讀得進來（見該目錄的 README）
RailwayGameApp/
  project.yml   XcodeGen spec（專案設定的唯一來源）
  RailwayGame.xcodeproj  由 project.yml 產生並提交（Xcode Cloud 需要），不要手改
  Resources/    Assets.xcassets（App Icon）、Localizable.xcstrings（畫面字串的繁體中文，決策 38）
  App/          RailwayGameApp（@main，持有 GameLauncher：開始畫面、存檔與目前的 GameSession）
  Views/        StartView、ContentView、HUDView、MapView / TileArt、ControlPanel、TrainControls
```

## 開發流程（cloud-first）

不需要自己的 Mac，也不依賴 Swift Playgrounds：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions（Linux 測試、macOS 以 Xcode 編譯）→ 內部 TestFlight → 在 iPhone / iPad 實機上檢視
```

| 層 | 在哪裡跑 | 驗證什麼 |
| --- | --- | --- |
| 1. Claude Code Cloud | Linux 容器 | 原始碼開發；GameCore `swift build` / `swift test`。**沒有** Xcode、Simulator、SwiftUI / UIKit |
| 2. Linux CI（`ci.yml`） | 每次 push 到 `main` 與手動執行；PR 只在改到會影響 Swift package 的檔案時（`Package.swift`、`Sources/`、`Tests/`、`GoldenScenarios/`、`ci.yml`、`swift-shards.sh`）才跑 Swift job，`Swift CI (gate)` 一定回報 | 只用 Swift 6.4：warnings as errors 的 build 與**全部**測試，包含 property / differential / mutation campaign（不減量，分成多個平行 shard） |
| 3. iOS App Build（`ios-build.yml`） | macOS runner，PR 與 `main` 自動執行（純文件變更略過） | 已提交的 Xcode 專案與 `project.yml` 一致、shared scheme 可被 Xcode Cloud 找到；以真正的 Xcode / Apple SDK 為 iOS Simulator 編譯 SwiftUI App 與 GameCore；iPhone UI 測試與 iPad 教學 UI 測試（兩個平行 job，各用自己的 Simulator）；不需簽章。PR 只跑精簡的擋關清單（開始畫面、三個工具的中英文、開始／存檔／繼續、教學的前幾步），iPad 只在改到教學畫面時跑；合併到 `main`、每晚與手動則跑全部 UI 測試、iPad 教學測試與「拿掉按鈕要失敗」的證明，這條線紅燈不擋 PR |
| 4. Release Archive（`release-archive.yml`） | macOS runner，手動觸發；修改專案設定或 App 資源的 PR 自動執行 | 以 Release、真實 iOS 裝置 SDK 封存並檢查 App（**未簽章**：不代表簽章、上傳或 TestFlight 會成功） |
| 5. TestFlight Checks（`testflight-checks.yml`） | Linux + macOS runner；修改 TestFlight workflow 或腳本的 PR 自動執行 | 發佈腳本的 lint 與測試、macOS dry run、合成 IPA 檢查；只用假值，不需 Apple 帳號，不簽章、不上傳 |
| 6. TestFlight（`testflight.yml`） | macOS runner，**只能從 `main` 手動**觸發 | Archive（預設 `adhoc`）→ App Store distribution 簽章匯出 IPA → 檢查 → 上傳 App Store Connect（**已在真實執行驗證**）；需要 environment `testflight` 的 secrets |

- **Swift Playgrounds**：可選，不是必要的開發或驗證環境。
- **TestFlight / 實機安裝**：以 GitHub Actions（`testflight.yml`）Archive、簽章、上傳，發佈到**內部** TestFlight，不需要 Mac。
  - 真實執行已驗證：Release Archive、App Store distribution 簽章匯出、IPA 檢查與上傳到 App Store Connect 都成功；沒有已註冊裝置的新團隊，`automatic` archive 會失敗，所以預設 `adhoc`。App Store Connect processing 與 TestFlight 安裝尚未有證據。步驟與狀態見 [docs/TESTFLIGHT_GITHUB_ACTIONS.md](docs/TESTFLIGHT_GITHUB_ACTIONS.md)。
  - 簽章以 App Store Connect API key 自動完成；repository 不含、也不提交任何憑證、描述檔或金鑰。
  - Xcode Cloud 暫緩（[docs/XCODE_CLOUD_ONBOARDING.md](docs/XCODE_CLOUD_ONBOARDING.md)）。

### 在 iPhone / iPad 上查看 App

畫面由專案擁有者以**人工**在實機檢查：`testflight.yml`（手動、只能從 `main`）上傳的 build 經內部 TestFlight 安裝到 iPhone / iPad 後自行查看。這是人工檢視，**不是**自動化的回歸測試。CI 的 UI 測試（`ios-build.yml`）在 Simulator 上操作 App 並判斷對錯，截圖只是附件讓人查看，缺了或改名都不會讓 CI 失敗，也沒有比對畫面；曾有的 Visual Smoke（手動 Simulator 截圖 artifact，不判斷任何事）已移除。

開始畫面的「示範地圖」（Stage C4，Release 與 TestFlight 也有）開啟一張用一般 GameCore 指令、照常付費建好的路網：地面的 1 號線與跨越它的高架 2 號線，各有一列四節列車在營運，車站都有客流（`DemoWorld`）。Debug build（例如在本機 Xcode 執行）也可以用啟動參數 `-demo-layout` 直接開啟它；Release build 不含這個啟動參數。

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

`swift test` 會執行 GameCore 與 GamePresentation 的測試。兩者都只使用 Swift 標準函式庫（GamePresentation 另用標準函式庫的 `Observation`），因此可在 macOS、iOS 與 Linux 上建置。CI 在 Linux 上只用 Swift 6.4 建置（warnings as errors）並測試（2026-10-05 起拿掉 Swift 6.0 job）：

- **Swift 6.4**：完整正確性驗證，執行**全部**測試，包含所有 campaign。campaign 的 seed、case 數與指令數都沒有減少；它們只是被分到多個平行 job（shard），等待時間是最慢的 shard，而不是全部相加。分法與「每個測試恰好在某一個 shard 跑過一次」的證明在 `.github/scripts/swift-shards.sh`：每個 shard 先確認各 shard 的選擇剛好切分 `swift test list` 的結果，跑完再確認實際執行的測試與選擇的完全相同。新增的測試類別不必改 CI，會落在 `rest` shard。
- 只改文件、App 或 TestFlight 檔案的 PR 不會啟動這些 Swift job（`Swift CI (gate)` 仍會回報）；推到 `main` 與手動執行一律全部跑。

GameCore 測試也會執行 `GoldenScenarios/` 裡的每個情境，並與檔案中手寫的預期結果比對。測試只讀取 fixture、從不寫回；預期值改變代表遊戲行為改變，必須在 PR 中說明。

另有 deterministic 的 property 測試（`*PropertyTests`、`WorldStateMachineTests`、`TrainSessionPropertyTests`）：以固定的 seed（SplitMix64，`Tests/GameCoreTests/PropertySupport.swift`）產生地圖、列車位置、路徑與指令序列，和獨立寫成的參考模型（逐單位移動、另一種最短路徑算法、窮舉所有最短路徑）及世界不變量比對。CI 每次都跑同一批 seed，不會隨機挑選；失敗訊息會寫出 suite、seed、case 編號與產生的參數。

- `KernelDifferentialTests`：同一串產生的指令同時交給 GameCore 與另外重寫的整個核心（`ReferenceWorld`：每一步的移動以除法一次算出且每分鐘都逐步執行、路徑以鬆弛法求出），每個指令之後比對結果（包括錯誤種類與檢查順序）與所有可觀察的狀態（時間、金額、世界的範圍、車站、列車、路網、月台、停站），並檢查停站只因決策 18 列出的指令開始或結束。失敗時先把指令序列縮到仍會失敗的最少指令，再連同 seed 與 case 回報。參考模型本身也要通過所有 golden scenario（`ReferenceWorldGoldenTests`）。
- `SaveMutationTests`：把產生的世界存檔後改掉 JSON 裡的一個值（數字、名稱、key、陣列元素、`null`），壞資料必須被拒絕；讀得進來的世界必須維持所有不變量、能再次存讀，之後的指令也維持原子性。另一組優先改動時刻表裡的值（沒有車站或列車的世界沒有時刻表可改）。
- `ServicePropertyTests`：在上面的指令序列中混入從停靠車站開始的時刻表、服務的啟動與停止與長短不一的推進，同時與參考模型比對（參考模型逐分鐘步進、沒有快轉、每次出發都重新求路），並檢查每次 `advance(n)` 等於 n 次 `advance(1)`、2× 等於兩倍的 1×，以及服務的不變量。`SaveMutationTests` 另有一組專門改動或寫入 `execution` 的變異存檔。
- `LineDispatchPropertyTests`（`line.dispatch`）：在小型路網上建立有列車的線路，混入目標班距、列車數、營運時間、服務日的改變、指派與取回、手動移動列車與拆鋪軌，和長短不一的推進，逐步與參考模型比對（參考模型每分鐘檢查每條線路的派車），並檢查每次 `advance(n)` 等於 n 次 `advance(1)`、2× 等於兩倍的 1×，確認快轉不會跳過任何派車。`SaveMutationTests` 另有一組改動線路列車、目標班距、上次發車與服務的變異存檔。
- `TimetablePropertyTests`：在上面的指令序列中混入合法與不合法的時刻表，同時與參考模型比對（錯誤種類與順序、被拒絕時世界不變、只改變該列車的時刻表），並讓同一串指令在從不設定時刻表的雙胞胎世界上執行：清除時刻表後兩者必須完全相同，證明時刻表不影響移動、路徑、停站、資金、時間與 ID。

```sh
PROPERTY_STRESS=20 swift test --filter PropertyTests                       # 本機多跑 20 組衍生的 seed
PROPERTY_REPLAY=network.differential@5EEDA001@17 swift test --filter ContinuousTrackPropertyTests   # 只重跑一個失敗的 case
PROPERTY_REPLAY=kernel.differential@5EEDA002@3 swift test --filter KernelDifferentialTests   # 同上，會印出縮減後的指令序列
```
