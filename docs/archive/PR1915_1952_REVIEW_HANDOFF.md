# 交接：PR #1915–#1952 審查（審查 L13）

派工單 REVIEW-L13（遊戲規劃第 55 任 session_01YGNNupgr773NrRPUr8CDiZ，2026-11-07，0.6.0 (121) 發版前）：審查 L12（`PR1908_1914_REVIEW_HANDOFF.md`）之後已合併的 PR。格式同 L12。

- Session：REVIEW-L13 session_01YGNNupyftbiKxGpeFY3pP8，branch `claude/review-l13`。
- 基準：`main` **7665f73**（#1952 合併後）。每個 PR 都讀 merge commit 對 first parent 的 diff，也讀它的決策檔。
- 點數（HANDOFF「多久審查一次」）：GameCore 5 個 × 2 = 10 點；GamePresentation／App／CI 17 個 × 1 = 17 點；合計 **27 點**，一輪看完。
- 分工：GameCore、CI、發版線由本 session 自己讀。GamePresentation／App 分給兩個子代理，只讀程式；它們的結論中，影響分級的那幾條本 session 自己再核對過（下面標「核對」）。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

逐一核對 `git log --first-parent 56f1011..7665f73`（#1918 是 L12 本身，不在範圍內）。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1916**（WENHU-LATE，決策 609 續）、**#1924**（TRAFFIC-READ，決策 138 續：問題借用推進留下的 memo）、**#1928**（KLRT-SPARE，決策 609 續：環線也算多出來的車）、**#1932**（CIOPT-5，決策 620：traffic plan 的路徑搜尋留住；rest 拆兩半）、**#1934**（TICKPERF，決策 622：`walkedDirections` 的路徑搜尋留住） |
| GamePresentation／App | #1917（MAP3D-MEM-2）、#1919（MAP3D-MEM-2B）、#1885（道路隧道口零件）、#1921（CABVIEW-2）、#1922（3D 跳回 2D）、#1926（夜間光暈，決策 617）、#1930（CABVIEW-3）、#1925（道路隧道，決策 611）、#1904（車站外觀 batch1）、#1931（機廠站型，決策 619）、#1933（高鐵北端機廠，決策 618）、#1935（輕軌機廠照真實，決策 621）、#1937（120 更新說明）、#1947（HOUR-STALL，決策 627） |
| CI／發版 | #1915（建置號不再帶 .1，決策 616）、#1936（Debug 的 iOS 也 -O，決策 624）、#1939（版本 0.6.0）、#1949（匯出字串逾時 25 分） |

沒有審的：

- 只改文件：#1920、#1923、#1927（研究與 `tools/rail-depots` 的研究腳本）、#1929、#1940、#1942、#1950。
- #1952：只改 `tools/meshy/README.md` 與文件，看過，沒有程式。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（發版前必修） | **0** |
| P2（下一版修） | **2**：L13-1、L13-2 |
| P3（記著） | **9**：L13-3 到 L13-11 |

- 沒有 P1，不擋 0.6.0 (121)。
  - 原本要用 send_message 通知第 55 任，但被拒（`elevated_session_untrusted_device`）。改在 #1579 回報。
- 建議 121 的更新說明順手帶上 **L13-1** 的更正（只改文字）。
- 決定性、存檔、golden、replay：這一輪的 GameCore 改動都沒有移動它們，PR 自己也這樣寫。本 session 讀過的四條路徑也都只是「同樣的答案，算得比較少」，或只在環線改了一個條件（見下）。
- 上一輪的追蹤：
  - **L12-1**（P2）：大部分修好（#1919，決策 610 續二），降為 P3，見 L13-6。
    - 最低等級搭「自動」畫質，以及「省電」「關」兩種畫質，蓋場景時都不蓋立面（`Map3DQuality.scenesKeepFacades` → `Map3DSceneKey.facades`）。整個蓋、串流、局部重蓋都帶這個旗標（子代理讀，**VERIFIED** 讀程式）。
  - **L12-2**（P3）：部分修好。
    - 每幀最多上傳 2 塊（`Map3DRealFacade.uploadsAFrame`）。
    - 記憶體警告時，留著目前在畫的塊。
    - 上傳仍在主執行緒的 `draw` 裡做。
  - **L12-3**：沒有 PR 動，還成立。
  - **L12-4**：一半修好，見 L13-5。
  - **L11-8**：還成立。`RunDepot.swift` 被 #1916、#1928 改過，但 `trainsInTheWay`（395 行）每次仍呼叫 `heldRunDepartures`（402 行）。

### GameCore

- **#1916**：決策 609 的「多一列就回廠」在有閉塞區間時不作用。
  - 規則本身（`runDepotEntryCandidates`）和它的醒來時間（`minutesUntilRunDepotMove`）兩處都加了同一個條件，兩邊一致。
  - 新測試 `testWithBlockSectionsBothWait` 與 batch／逐分相等，過（**VERIFIED**）。
  - 沒發現問題。
- **#1924**：`questionMemo()` 把推進留下的 `paths`／`curves`（`Key` 相同時）與 `trafficParts`（`ServiceKey` 相同時）借給查詢用。
  - 條件和推進自己借用時一模一樣（`lend(to:for:)`），查詢不寫回，世界不變。
  - `Key`／`ServiceKey` 每次查詢都建一份，比較 network／lines。這些是 COW 的 Array 與 Dictionary，相等時有同一塊儲存的捷徑，所以不貴。
  - `QuestionMemoTests` 逐秒比對「借用」與「空 memo」的答案，也測了改路網之後就不借。過（**VERIFIED**）。
  - 沒發現問題。
- **#1928**：新的判斷 `countsSurplus(on:way:blockSections:)`。
  - 非環線（`way == nil`）是 `!blockSections`，和 #1916 相同。
  - 環線不看閉塞區間。另加一個條件：另一個方向留著的車不算。
  - 非環線時 `runWays` 只有 `[nil]`，新加的 `!counted.contains(where: $0.0 != way …)` 永遠為真，所以非環線一個位元不變。這和決策寫的一致。
  - 醒來時間同樣改用 `countsSurplus`。
  - `RingRunsTests` 39 支過（**VERIFIED**）。
  - 代價寫在決策裡：空車多 8 趟、12 km。
  - 沒發現問題。
- **#1932**（GameCore 部分）：`trafficPoints(of:cycle:paths:)` 把 `plannedPath` 內聯成 `preferred ?? path(..., memo:)`。
  - 核對 `LineRoutePreference.swift:336`：`plannedPath` 正是這兩個呼叫的 `??`，所以選到的路一樣。
  - `matched` 從「有偏好且 `preferredPath == path`」改成「`preferred != nil`」。偏好路存在時，`path` 就是它，兩者等價。
  - `PathMemo` 的鍵（起點、偏移、站、長度、eligible、keepingLeft）涵蓋了 `networkPath` 讀的東西，只讀路網。
  - `ScheduledTrafficTests` 過（**VERIFIED**）。
  - 沒發現問題。
- **#1934**：`walkedDirections`／`leg` 的路徑搜尋改走 `memo.paths`，同一個純函式加上 memo。
  - `preferredPath(memo:)` 只把 eligible 那條搜尋留住，走固定股道的那條照算。
  - 沒發現問題。

### CI／發版

- **#1915**（決策 616）：第一次嘗試上傳純數字（120），重跑時是 `120.2`。
  - App Store Connect 逐段比較、缺的那段當 0，所以 119.1 < 120 < 120.2 < 121。
  - `testflight-changes.py` 的 `LAST_DOTTED_RUN = 119` 和 preflight 一致，自我測試涵蓋了。
  - 已經實證：testflight run 120（ff15345）成功。
  - 沒發現問題。
- **#1936**（決策 624）：Package.swift 改成 GameCore 在 Linux 與 iOS 上 -O，GamePresentation 只在 iOS 上 -O，GameCoreTests 只在 Linux 上 -O。
  - Linux 的行為和原來相同（GamePresentation 仍是 -Onone）。
  - `unsafeFlags` 只在以路徑引用的本地 package 才允許，這個專案正是如此。
  - 合併之後的 release archive（ff15345，workflow_dispatch）綠，120 也從那個 commit 發出。
  - 沒發現問題。
- **#1939**：`project.yml` 與 `.pbxproj` 的兩個設定都改成 0.6.0，沒有別處還寫 0.5.0（測試裡的 0.5.0 是假資料）。
- **#1949**：只放寬逾時。沒問題。

### GamePresentation／App（子代理讀，**VERIFIED** 讀程式，沒有在 macOS 上跑）

- **#1917**：
  - 三組輪替緩衝配上 semaphore 3。
  - 兩個提早 return（沒有 drawable／command buffer、沒有 encoder）都會 signal。
  - 同一個 queue 的 command buffer 依序完成，所以 GPU 不會讀到正在填的那組。
  - 有 L13-4。
- **#1919**：
  - `mayDraw` 與 Metal view 的 `level` 走同一條鏈：`quality.drawn`、`tier(device:)`。
  - `Map3DSceneKey` 比較 `facades`，所以跨過門檻時整個重蓋。
  - 測試確認建物本體的網格有沒有立面時位元相同。
- **#1885**、**#1925**：
  - 隧道口只在 `.near` 與非粗略的區塊蓋。
  - 切到 tile 邊的端點（0.5 m 內）不算洞口。
  - 局部重蓋用同樣的 256 m apron。
  - 有 L13-7。
- **#1922**：
  - 3D 打開時，提示被收起，不算玩家按了「知道了」。
  - `SpeedLagHintTests` 過（**VERIFIED**）。
  - 有 L13-2。
- **#1926**：
  - 光暈表在背景、放掉頂點之前就做好。
  - 列車自己的燈不重複發光。
  - pipeline 格式、取樣數、深度設定都和主 pass 相同。
  - 白天、最低等級、省電時都不畫。
  - 有 L13-8。
- **#1921**、**#1930**：
  - 一個 step 的中間 tick（只有 10×／60×）不各自滑行，最後一個 tick 整段滑。
  - 旗標綁 `worldRevision`，任何指令都會關掉它。
  - `stopGameLoop` 也清掉旗標。
  - 有 L13-9。
- **#1931**：
  - 先找節點的道岔查法找不到舊紀錄裡的梯形道岔（16 單位內沒有節點），所以舊紀錄照舊重播成梯形。`testALadderFromAnOldLogIsLaidAsItWas` 涵蓋了。
  - memo 的鍵含站型。
- **#1933**：有 L13-10。
- **#1935**：
  - 長條布局只用在 `site.strip != nil`（高雄輕軌），其他機廠走原來的 `lay`。
  - 放不下時回 nil，玩家看到「這條線的機廠放不下」。
  - 已經買下的存檔保留舊機廠。
- **#1937**：有 L13-1、L13-3。其餘幾行都對得上合併的 PR（#1934、#1922、#1917／#1919、#1916、#1928、#1885／#1925／#1926）。
- **#1947**（決策 627）：
  - 只有 `.setSpeed`、`.pause`、`.resume` 會把兩個 memo 與 `hourAdvice` 搬到新的 revision，而且只搬原本在舊 revision 上的。
  - 這三個指令只動 `clock`，站長的建議不讀倍速，所以留下的答案等於重算的答案。
  - tick 進行中暫停，`worldRevision` 會變，這個 tick 的結果被丟掉。
  - `stationMasterLook()` 存之前先比對 revision。
  - `AutoServiceTests` 過（**VERIFIED**）。
  - 沒發現問題。
- **#1904**：遊戲裡沒有任何地方呼叫它，見 L13-11。

## 二、發現

### L13-1（P2，文字）#1937：120 的更新說明說 1× 的車窗視角也修好了

- **位置**：`Sources/GamePresentation/WhatsNew.swift:60-61`，`2026-11-07-120`。
- **問題**：
  - 說明寫「Correction to the last build: … glides smoothly instead of jerking, at 10x and at 1x.／……10 倍速和 1 倍速都滑行連貫。」
  - CABVIEW-2／3 只改了 10× 和 60×：`LoopTick.glidesOverTheStep` 是 `speed == .x10 || speed == .x60`（`GameSession.swift:2225`）。
  - 決策 379 續四的下一步寫明「1× 沒做」。
  - 核對：**VERIFIED**（讀程式與決策）。
- **影響**：120 已經發出。上一版的「更正」又說得太滿。
- **修法**：121 的說明更正為只說 10×（或等 1× 真的修好再說）。這是純文字修改，可以和 121 的說明一起帶。

### L13-2（P2，**UNVERIFIED**）#1922：跑不到倍速的提示，只在 3D 地圖打開時才擋住

- **位置**：`Sources/GamePresentation/GameSession.swift:1166`（`!isMap3DOpen`）；HUD 的 popover 在 `RailwayGameApp/Views/HUDView.swift:927`。
- **問題**：
  - 決策 464 續寫查到的機制是：HUD 的 popover 在別的呈現（3D 的 `fullScreenCover`）底下自己跳出來，UIKit 就把上面那層收起（`_UICurrentContextPresentationController`）。
  - 這個機制不限於 3D。2D 上還有好幾個 cover 與 sheet：
    - fullScreenCover：車隊總覽（`FleetOverviewSheet.swift:155`）、列車名冊（`InspectorView.swift:29`）、路線圖與名冊（`LinesPanel.swift:2697`、`:2702`）、設定裡的城市視角與列車展示（`SettingsView.swift:98`、`:106`）。
    - sheet：各個面板（`ContentView.swift:199` 等）。
  - 這次的條件只認 3D。
- **玩家可能看到**：在跑不滿 10× 的路網上打開路線圖或車隊總覽，約 20 秒後畫面自己關掉。
- **不是新的退步**：決策 464 之後就是這樣，這一批只修了 3D 那一種。
- **驗證**：只讀程式，**UNVERIFIED**。要用 Simulator 的 UI 測試確認：`-show-speed-lag-hint`，開路線圖，等 25 秒，看它還在不在。
- **修法**：
  - 條件改成「沒有任何東西蓋在 2D 上」。例如在 `GameSession` 記一個呈現計數，由那些 view 的 `onAppear`／`onDisappear` 增減。
  - 或把提示改成不用 popover 的橫幅。

### L13-3（P3，文字）#1937：名稱和 App 裡的不一致

- 「前鎮機廠／Qianzhen depot」：App 裡叫「輕軌機廠／Light Rail Depot」（`RealLineDepotSite.klrt`）。Sources 與 App 裡都沒有「前鎮」。
- 「Liujia depot」：應為「Liujia Depot」。「Nangang's stabling sidings」：應為「Nangang Sidings」（`HighSpeedDemo.realDepots`）。
- 「空車少跑／fewer empty trains run」：決策 621 量到空車趟數相同（54／54），變的是公里（78 → 51 km）。比較準確的說法是「空車跑得比較短」。
- 「fan out symmetrically」：預設 3 股（`DepotYard.defaultSidings`），決策 619 自己說 3 股的喉部一邊多一個道岔。另外 #1931 拿掉了機廠工具的「邊」選項，說明沒有提到。
- 三行寫「10x」，App 的倍速標籤是「10×」（`DisplayText.swift:840`）。
- 和 L11-6、L12-4 同一類。下一個要改 `WhatsNew.swift` 的 PR 順手帶上。

### L13-4（P3）#1917：「每幀 0 次配置」只對 MTLBuffer 成立；三組緩衝只長不縮

- **問題**：
  - 每幀仍會建 CPU 的陣列：`carsSorted`、`lifeSorted`、各種 `flatMap(\.floats)`、`glassVertices`，以及 #1926 的 `trainSpots`、`glowRuns`（`Map3DMetalView.swift` 約 1180–1230 行）。
  - 三組幀緩衝只會長大。記憶體警告（`memoryRunsShort`）也不放。所以畫過一次大的幀（列車展示、玻璃多的景）之後，就一直佔著那麼大。
- **影響**：有上限、量小，記著就好。**UNVERIFIED**（沒量）。

### L13-5（P3）L12-4 後半還沒修

- `WhatsNew.swift:98`（119.1）與 `:1134` 仍寫「The Changhua roundhouse」。App 裡是「Changhua Roundhouse」（`AttractionCatalog.swift:135`）。
- 每處只差一個字。

### L13-6（P3）L12-1 的剩餘部分：標準以上的等級，立面的 CPU 那份仍常駐

- 依決策 610 續二是刻意的，記錄如下：
  - 標準以上的等級，場景快取、`built`、Metal `Chunk.facadeMesh`（`Map3DMetalView.swift:239`）都留著 CPU 的那份。近景區塊同時有 CPU 和 GPU 兩份。
  - 低耗電模式與過熱時仍會蓋立面，只放掉 GPU 那份。
- 新發現（#1879 起就有）：區塊離開近景時，它的立面 GPU 緩衝不放（`frontsUp` 變 false，但 `facade` 留著，`Map3DMetalView.swift:1145-1155`）。只有記憶體警告、改畫質、區塊被換掉時才放。
  - 所以在密集市區拖過一輪之後，曾經在近景的每一塊都還佔著 GPU 立面，每塊最多約 0.9 MB，上限是場景的區塊數。
  - 決策 610 說「不畫時放掉」，對這部分不成立。
- **驗證**：讀程式，**UNVERIFIED**（沒量）。
- **修法**：`frontsUp` 由 true 變 false 時，放掉 `facade` 的 GPU 緩衝；或留最近 N 塊。

### L13-7（P3，**UNVERIFIED**）#1925：隧道口的配對和端點的順序有關，串流與整個蓋沒有測試比對

- `roadPortals` 照 tile 的順序貪婪配對（`Map3DRoadTunnels.swift` 約 84–100 行）。
- 串流與局部重蓋讀的 tile 集合和整個蓋不同（區塊加 256 m apron）。
- 一般的成對端點不受影響，因為 apron 遠大於 14 m 的配對距離。但如果有三個以上的快速道路端點擠在一起，兩種蓋法可能配出不同的洞口。
- `Map3DStreamingTests` 比對了立面，沒有比對隧道口。
- **修法**：補一支 `chunks(keys…)` 對整個場景的隧道口比對。配對改成和順序無關（例如先排序、再取最近的一對）。

### L13-8（P3，**UNVERIFIED**，要實機）#1926：光暈多出的 draw call 與填充沒有量

- 每個看得到的區塊，每種會發光的路邊物模型多一個 draw call，車與生活物件也各一個，另外還有列車的燈與招牌。
- 路燈多的街道，加法混合的填充最重。
- 超出預算（`overBudget`）時關掉光暈，可能和負載調節器互相拉扯。有遲滞，但沒有量。
- 下一次實機量測單加一列。

### L13-9（P3，**UNVERIFIED**）#1921／#1930：step 不正常結束後，真實列車的時鐘可能晚一個 tick

- `MapView` 與 `Map3DPreviewScreen` 在 `glidesOnThroughTheStep` 為真時不更新真實列車的時鐘，之後只在 `clock.now` 變的時候更新。
- 如果 step 的最後一個 tick 失敗，或 step 中途來了指令（暫停讓 `finish` 提早 return），旗標會變回 false，但 `clock.now` 不一定變。
- 這時真實列車、公車、纜車停在 step 中間之前的時鐘，到下一個 tick 才跟上。只是短暫停一下，會自己好。
- 3D 的高度與標籤只在 step 結束時更新（最多晚一個 step），決策裡已記為 P3 c。

### L13-10（P3）#1933：時刻表改了，高鐵示範會當掉，而不是丟錯

- `HighSpeedDemo.swift` 分配機廠時用 `precondition(left == 0, "No depot has room …")`。
- 南港、六家改成固定 8 股之後，如果以後打包的高鐵時刻表晚上北端停超過 16 組，蓋示範時就會 trap，而不是丟 `Failure`。
- 另外 `lines: [0, 1]`、`[2]` 是 `timetable.lines` 的位置。改了 `spec.kinds` 的順序，會默默把車組分到別的機廠。
- 今天的資料沒問題，示範的測試蓋得出來。
- **修法**：改成丟錯；用線的 ID 對應，不用位置。

### L13-11（P3）#1904：車站外觀 batch1 還沒接進遊戲；接的時候要補 ODbL 署名

- `Map3DStationExteriorBatch1`（1 762 行）只有它自己的測試在呼叫。
- 它內嵌了 OSM 的建物輪廓，ODbL 的署名目前只寫在程式註解裡。
- 接進遊戲時，`DataSourceCredits` 要涵蓋它。#1579 上的 station-exteriors-integrate 在做這件事，到時一起看。

## 三、驗證紀錄

- `swift build --build-tests`（Linux，Swift 6.4.0，debug）：成功。
- `swift test --skip-build`（Linux，**VERIFIED**），8 個類別全過：`SurplusRunDepotTests`、`QuestionMemoTests`、`RingRunsTests`、`ScheduledTrafficTests`、`AutoServiceTests`、`SpeedLagHintTests`、`WhatsNewTests`、`Map3DRealFacadeTests`。
- GitHub Actions 紀錄（讀取，沒有啟動任何 run）：
  - testflight run 120（ff15345）成功，用的是純數字建置號。
  - release-archive 在 ff15345 綠。
  - `ci.yml` 在 7665f73 的 push run 綠。
- 子代理的發現：L13-1 與 L13-2 的機制由本 session 讀程式與決策核對過。其餘只讀程式，標明了 **UNVERIFIED** 的部分沒有跑。
- 畫面、Metal、iOS 記憶體、UI 測試：**UNVERIFIED**（沒有 macOS，沒跑 iOS workflow）。

## 四、下一輪

- REVIEW-L14 從 **#1953** 起（`main` 7665f73 之後）。
- 還沒派的：
  - L13-1（121 說明一起改）、L13-2（P2），L13-3 到 L13-11。
  - L12-3、L11-8。
  - 之前的 L9-4、L9-5、L9-7、L10-4 到 L10-13。
