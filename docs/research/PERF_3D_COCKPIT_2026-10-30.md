# 3D 駕駛室每秒只有 9 格：主執行緒在忙什麼（2026-10-30）

派工單：作者在 TestFlight 0.5.0 (96.1)、iPhone18,1 上回報「下雨對 3D 駕駛模式負擔太大」，後來補了一段不下雨的錄影。分支 `claude/perf-3d-cockpit`，對照的是 `main` a1e33214b。

標記：

- **VERIFIED**：這個 session 在 Linux（Swift 6.4，4 核雲端機）真的跑過。
- **UNVERIFIED**：沒有實機，只能從程式、作者的錄影和數字推估。

SwiftUI 的重畫、Metal 與 GPU 都是 UNVERIFIED，因為 Linux 沒有 SwiftUI，也沒有 Metal。

## 0. 結論先講

- **不是雨。** 作者不下雨的錄影（`norain.mov`）是這樣的：
  - 場景：駕駛室跟著三鶯線列車 4，車停在媽祖田，時速 0。畫質是 higher full。
  - 數字：每秒 **9 格**。CPU 15.3 ms、GPU 15.6 ms，**主執行緒每格 120.8 ms**，最長一段 228 ms。
  - 整段影片：每秒 4–28 格，主執行緒每格 34–184 ms。
  - GPU 與 3D 的 `draw()`（13–19 ms）都不慢。慢的是主執行緒，它已經滿了，每秒忙將近 1 秒。
- **3D 自己每個 tick 在主執行緒上做的事，幾乎都已經很便宜。** 唯一大的一項是「數道路格子」：
  - 修之前，一次約 2.0 ms（Linux release），一個 tick 兩次，分在兩處：
    - 3D 場景的鑰匙 `Map3DSceneKey`；
    - 公車的簽章 `Map3DBuses.Signature`。
  - 每次都把城市的 81,088 格和玩家蓋的 6 格合成一個新集合，只為了數它有幾格。
  - 修好了（第 3.1 節）。
- **剩下最大的嫌疑（UNVERIFIED，已修）：3D 底下那張看不到的 2D 地圖還在跟車、每格重畫。**
  - 3D 是全螢幕蓋在 2D 上（`fullScreenCover`），2D 地圖還活在底下。
  - 駕駛室跟著一列車，2D 地圖也就跟著那列車：
    - 鏡頭在**每一格**移動，最多每秒 60 次（決策 182 後來、371：「每格重畫整張地圖」）；
    - 列車、真實列車、雨每秒滑行 30 次；
    - 每個 tick 的交通狀態也讓軌道重畫一次。
  - 作者同一個存檔的 2D 回報：**軌道與路線重畫一次約 34 ms**，最長 57 ms（`PERF_REAL_MAP_2026-10-30.md` 第 93 行）。
  - 每秒幾次 34 ms 就能把主執行緒塞滿，對得上每格 120 ms、每秒 9 格。
  - 這也解釋了「下雨時 3D 更卡、2D 下雨卻有 40–60 格」：
    - 3D 底下的 2D 雨也在每秒畫 30 次；
    - 2D 單獨開著、沒有跟車時，鏡頭不會每格動。
- **改法：3D 蓋著時，2D 地圖停下這些事。**
  - 停的：每格跟車、每個 tick 移鏡頭、列車與真實列車的滑行、等待的脈動、雨、每個 tick 的交通。
  - 3D 一關，2D 立刻讀當下的交通、鏡頭貼回列車，滑行也照常恢復。
  - 判斷寫在 GamePresentation 的 `CoveredMap`，有 Linux 測試。App 端只改 `MapView.swift` 幾行。
- **原本猜的「隱藏的 2D 每個 tick 算站長建議、警示、下一步、公司評等、交通」不成立。**
  - 我的量測把它們每個 tick 都算一遍，合計每 tick 15.5–17.5 ms（release）。
  - App 裡它們不是每個 tick 算：
    - 站長建議：每個遊戲小時算一次；
    - 警示：每 10 分鐘遊戲時間算一次；
    - 交通：在背景算好；
    - 下一步：本來就很便宜；
    - 公司評等：只有目標面板打開時，每個遊戲日算一次。
  - 15.5 ms 幾乎全是公司評等，是量測的假設，不是 App 的行為（第 2.2 節）。

## 1. 怎麼量

- **存檔**：作者的 `87656e99-Along_the_Line_2026-10-30_033425.alongtheline`，存檔版本 75。
  - 實景地圖，第 53 日，67 站、13 條路線、74 列車。
  - 它和指令紀錄 `737d0831-command-log.json` 都只在 session 的暫存資料夾讀，**沒有放進 repo**。
- **量測程式**：`Tests/GamePresentationTests/Map3DCockpitCostReportTests.swift`。
  - 只有設了 `COCKPIT_SAVE` 才跑，平常 CI 跳過。
  - 它讀進存檔，用和 App 一樣的 `HeadlessGame` 裝好，跟著一列車（`COCKPIT_TRAIN`），然後：
    - `setMap3DOpen(true)`；
    - 開始走，10×（3D 跟車最多 10×，決策 360）；
    - 每個 tick 照遊戲迴圈的順序做 `beginLoopTick` → `work` → `finish`。
  - 每個 tick 分別計時三組工作：
    - `Map3DPreviewScreen` 的 `body` 讀的；
    - 3D 每個 tick 餵給 Metal 的；
    - 2D 和 session 可能被讀到的。
  - 存檔裡還沒有三鶯線的車（是之後才買的），所以跟的是 `淡海輕軌綠山線列車 4`，路網、城市與道路都一樣。
- 命令（release，`-enable-testing`）：

```sh
COCKPIT_SAVE=<…>.alongtheline COCKPIT_LOG=<…>-command-log.json COCKPIT_TRAIN="綠山線列車 4" COCKPIT_TICKS=300 \
  swift test -c release -Xswiftc -enable-testing --skip-build --filter Map3DCockpitCostReportTests
```

## 2. 量到的數字

### 2.1 3D 每個 tick 在主執行緒上的事（VERIFIED，Linux release，300 tick、10×）

| 項目 | 平均 | 說明 |
| --- | --: | --- |
| tick 收尾 `finish`（模擬的，不是 3D 的） | 3.08 ms | 包括 `screenFacts`、地圖標記、跟車列的整理 |
| 3D 場景鑰匙：數道路格子（**修之前**，`allCells.count`） | 1.98 ms | 81,088 + 6 格合成新集合 |
| 3D 場景鑰匙：數道路格子（**修之後**，`roadCellCount`） | 0.014 ms | |
| 3D 場景鑰匙：路線色帶簽章 | 0.015 ms | |
| 3D 場景鑰匙：其餘 | 0.006 ms | |
| 街景活動 `Map3DStreetLife.Activity` | 0.27 ms | |
| 列車名牌 `Map3DTrainLabels` | 0.21 ms | |
| 滑行與車身高度 | 0.12 ms | 決策 485：背景算好 |
| 駕駛室儀表 | 0.10 ms | |
| 天氣、光線 | 0.04 ms | |
| 公車的時鐘與簽章（修之後；簽章裡也數道路） | 0.028 ms | |
| 真實列車的時鐘 | 0.003 ms | |

- 300 個 tick 裡，3D 場景鑰匙的每一部分和公車簽章**都沒有變**：3D 場景沒有被重建。
- 修之前，每個 tick 的道路要數兩次（場景鑰匙一次、公車簽章一次），共約 4 ms；修之後兩次合計約 0.03 ms，約 140 倍。

### 2.2 原本懷疑的 2D／session 推導（VERIFIED 是量測；App 裡怎麼算是讀程式）

| 項目 | 每 tick 都算時（release） | App 裡實際多久算一次 |
| --- | --: | --- |
| 公司評等 `CompanyRank` | 17.5 ms | 只在目標面板（`GoalsPanel`）打開時，每個遊戲日一次（`.task(id: today)`） |
| 警示 `situationAlerts` | 0.001 ms | 背景的 tick 每 10 分鐘遊戲時間算一次（`situationAlertsPeriod`），主執行緒讀暫存 |
| 下一步 `nextSteps` | 0.001 ms | 每個 tick 在 `finish` 裡算（`refreshScreenFacts`），已含在上表的 `finish` |
| 站長建議 `stationMasterAdvice` | 0.006 ms | 每個遊戲小時一次（`hourAdvice`） |
| 交通 `trafficOverlay` | 0.004 ms | 背景的 tick 算好（`trafficMemo`），主執行緒讀暫存 |

Debug 版的同一張表（100 tick）：

| 項目 | 平均 |
| --- | --: |
| 公司評等 | 125 ms |
| 其餘四項 | 都在 0.1 ms 以下 |

所以「隱藏的 2D 每 tick 15.5 ms」幾乎全是公司評等，而 App 不會每個 tick 算它。這一項**不用修**。

### 2.3 和錄影對帳（UNVERIFIED 的推估）

- 3D 那邊能在 Linux 量到的主執行緒工作，修之前每個 tick 約 7.8 ms（含模擬的 `finish` 3.1 ms）。一秒 10 個 tick，約 78 ms。
  - 其中 3D 自己的約 4.7 ms，多半是數道路（兩次約 4 ms）。
  - 修之後每個 tick 約 3.9 ms（3D 自己的約 0.8 ms），一秒約 39 ms。
- 實機的主執行緒一秒忙將近 1,000 ms，量得到的只佔一小部分。剩下的是 SwiftUI 與 UIKit 的重畫，Linux 量不到。
- 最符合的就是底下那張 2D 地圖：
  - 跟車時它每格都在動鏡頭，而作者同一個存檔的 2D 軌道重畫一次約 34 ms。
  - 一秒只要重畫 25 次，就是 850 ms。

### 2.4 實機的基準（作者的 iPhone18,1，0.5.0 (96.1)，修之前）

| 情況 | 每秒格數 | CPU（`draw()`） | GPU | 主執行緒每格 | 最長 | 其他 |
| --- | --: | --: | --: | --: | --: | --- |
| 作者的存檔，駕駛室跟三鶯線列車 4，不下雨，higher full（`norain.mov`） | 9 | 15.3 ms | 15.6 ms | 120.8 ms | 228 ms | 整段 4–28 格，主執行緒 34–184 ms |
| 作者的存檔，駕駛室跟高鐵 29，10×，夜裡，不下雨，full / higher full | 22 | 6.7 ms | 3.3 ms | 44.0 ms | 138 ms | 等待 0.0 ms，154 次繪製，398,143 三角，0 人、0 車 |
| 高鐵示範地圖，同樣的駕駛室 | 50–60 | — | — | — | — | 作者口述 |

- 畫圖本身很便宜：CPU 6.7 ms、GPU 3.3 ms、不用等 GPU。問題全在主執行緒（每格 44 ms）。
- 同一個駕駛室，在小的示範地圖上有 50–60 格，在作者的存檔（67 站、74 列車、實景地圖）上只有 9–22 格：
  - 慢的程度跟著存檔的大小走，而 3D 自己每個 tick 的工作在 Linux 上量到只有幾毫秒；
  - 跟著存檔變大的，正是底下那張 2D 地圖一次重畫的成本。
- 這和第 2.3 節的推估對得上（仍是 UNVERIFIED，要實機確認）。

**修之後預期（UNVERIFIED）**：

- 主執行緒每格大約是 3D 的 `draw()`（6.7–15 ms），加上每個 tick 留在主執行緒的工作。
  - 後者每 tick 約 3.9 ms，一秒 10 個 tick，攤到每格不到 1 ms。
  - 再加上 3D 畫面自己的 SwiftUI 更新。
- 預期大約 **10–17 ms**，接近示範地圖的 50–60 格。
- 如果實機還是遠高於這個數，就是 `ContentView` 其他部分在 3D 底下的重算，要用 Instruments 找（第 6 節）。

## 3. 改了什麼

### 3.1 數道路格子不再合成集合（VERIFIED）

- `RoadGrid.roadCellCount`（`Sources/GamePresentation/Map3DBuses.swift`）算的是 `cells.count` 加上 `built` 裡不在 `cells` 的格數。
  - 結果和 `allCells.count` 一樣，但不做出新的集合。
- `Map3DSceneKey` 和 `Map3DBuses.Signature` 都改用它。
- 數字見 2.1 表：1.98 ms → 0.014 ms。
- 測試：`RoadCellCountTests`。
  - 數出來和聯集的格數一樣；
  - 蓋一格路，公車的簽章會變。

### 3.2 3D 蓋著時，2D 地圖不跟車、不滑行、不重畫交通（App 端 UNVERIFIED）

判斷在 `Sources/GamePresentation/CoveredMap.swift`，App 端在 `RailwayGameApp/Views/MapView.swift` 讀 `screen.showsMap3D`。

| 2D 地圖的事 | 以前（3D 蓋著時） | 現在（3D 蓋著時） | 3D 一關 |
| --- | --- | --- | --- |
| 跟車的鏡頭每格移動（`followsGlide` 的 `TimelineView`，每秒最多 60 次，每次整張地圖重畫） | 照跑 | 不跑 | 立刻恢復 |
| 每個 tick 把鏡頭移到列車 | 照跑 | 不跑 | 鏡頭立刻貼回列車（`followCamera.reset()` 後移一次） |
| 列車、真實列車滑行（每秒 30 次） | 照跑 | 停在最後一格 | 立刻恢復 |
| 等待的脈動、死結的閃動 | 照跑 | 不動 | 立刻恢復 |
| 雨（每秒 30 次） | 照跑 | 不動 | 立刻恢復 |
| 每個 tick 的交通（等待、閉塞），每次讓軌道重畫 | 照跑 | 不收 | 立刻讀當下的交通 |
| 列車的滑行資料（`trainMotion`，背景算好） | 照跑 | **照跑** | — |

- 列車的滑行資料照收，是因為 session 下一個 tick 的滑行要接著它算（決策 379 的 `shownGlide`）。
  - 它每個 tick 只讓列車那一層畫一次，不是每秒 30 次。
- 從 3D 的「2D」鈕或縮小回 2D 時，`map2DReturn` 會停止跟車，並把鏡頭放到 3D 看的地方，和以前一樣。
  - 新加的「關掉時貼回列車」在那之前或之後跑都一樣：跟車停了，它什麼都不做；它先跑的話，`map2DReturn` 隨後會蓋過去。
- 測試：`CoveredMapTests`。
  - 3D 蓋著時，不論跟不跟車、遊戲走不走、列車動不動，2D 這些事都不跑；
  - 3D 一關，那一刻刷新一次，之後照常；
  - 沒有 3D 蓋著時，和以前的判斷一模一樣。

### 3.3 沒有改的

- 模擬推進、2D 軌道與路線的畫法、收購與刪線：另一位 worker 在 `claude/perf-real-map-600x` 處理。
- `GameCore`：沒有改。
- 3D 的雨：改用 Metal 畫的版本在 `claude/perf-3d-rain-gpu`（80908c4），**留到公測之後**。
  - 每格的 CPU 從 15.8–23.6 µs 降到 0.08–0.2 µs（Linux release）。
  - 這次的錄影證明雨不是主因，所以那個分支不放進這個 PR。

## 4. 找過的參考

- 作者的參考 repo：`a91453/railway-reference-private` 的網頁版都只有一張畫面，沒有「3D 蓋在 2D 上、2D 還在跑」這種 SwiftUI 的狀況，**沒有可用的**。
- 開源：SwiftUI 在 `fullScreenCover` 底下的畫面照樣更新，是 Apple 平台的行為；這裡用的是一般做法：看不到的畫面停下自己的動畫。沒有拿任何外部程式碼。

## 5. 請作者在實機看的（UNVERIFIED）

1. 同一個存檔、同一個駕駛室（三鶯線列車 4，higher full，不下雨）：
   - 3D 疊加層的每秒格數與「主執行緒」毫秒數；
   - 修之前是 9 格、120.8 ms。
2. 同上，下雨。
3. 關掉 3D 回到 2D（「2D」鈕和關閉鈕各試一次）：
   - 鏡頭是否在該在的地方；
   - 列車是否立刻開始滑。
4. 如果主執行緒還是滿的：用 Instruments 的 Time Profiler 錄 10 秒駕駛室，看主執行緒最多的是哪一層。

## 6. 接下來

- 如果實機確認 2D 底下的重畫就是主因，那 `ContentView` 其他讀 `session.world` 的部分也可能在 3D 底下每個 tick 重算 `body`。
  - 例如上方的資訊列與卡片。
  - 那些一次都不大（`screenFacts` 已經只在變了才通知，決策 367），等 Instruments 的結果再決定。
- `claude/perf-3d-rain-gpu`：公測後再開 PR。
