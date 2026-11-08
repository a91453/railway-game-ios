# 交接：PR #1953–#1982 審查（審查 L14，發 122 前）

派工單 REVIEW-122（遊戲規劃第 56 任 session_01YGNNuqMnQwhbSmiaZzhLsX，2026-11-08）；規劃補充改成這一輪就是 REVIEW-L14：審 L13（`PR1915_1952_REVIEW_HANDOFF.md`）之後已合併的 PR。格式同 L13。

- Session：REVIEW-122（session_01YGNNupjWbT4aB8N7ckYBMc），branch `claude/review-122`。
- 基準：`main` **a3f7842**（#1982 合併後）。每個 PR 都讀 merge commit 對 first parent 的 diff，也讀它的決策檔。
- 點數（HANDOFF「多久審查一次」）：GameCore 2 個 × 2 = 4 點；GamePresentation／App／CI／資料工具 22 個 × 1 = 22 點；合計 **26 點**，一輪看完。
- 分工：
  - 本 session 自己讀：
    - GameCore（#1961、#1967）。
    - 121 之後的 GamePresentation／App（#1959、#1962、#1964、#1971、#1972、#1973、#1974）。
  - 121 之前的十個 GamePresentation／App PR 分給兩個子代理，只讀程式。
  - 子代理的結論中，影響分級的那條，本 session 自己寫測試核對過（下面標「核對」）。
- 存檔版本、決策編號、golden schema 都**不動**；不改程式（見 L14-1 為什麼沒修）。

## 〇、範圍

`git log --first-parent 7665f73..a3f7842`。0.6.0 (121) 是 `4abcc0c5`（#1946 的合併）。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1961**（TYMC-REBUILD-4，決策 636：跟車不停在逆向軌道；605 續：照真實改建）、**#1967**（OVERTAKE-PERF，決策 637：待避計畫的快取） |
| GamePresentation／App（121 之前） | #1941（軌道編號與圖層列，631）、#1943（機廠圖層，630）、#1944（渡輪與纜車圖鑑，632）、#1945（鋪軌調高度，629）、#1946（真實站房外觀，625）、#1948（單線三列車，628）、#1954（六家基地移出河道）、#1956（2D 收購後效能）、#1957（Mac 試玩 UI 修正）、#1958（121 更新說明） |
| GamePresentation／App（121 之後） | #1959（PLAYTEST-LINES，635）、#1962（PLAYTEST-3D，645）、#1964（MAP-LABELS-2，642）、#1971（CRASH-STATION，644）、#1972（TRACKHEIGHT-DRAG，646）、#1973（FIND-B1B4，648）、#1974（ACQUIRE-LIST，649）、#1976（MapLibre 7.0.0，651，只看檔案清單）、#1977（TRA 時刻重抓，650，資料由 `RealTRAScheduleTests` 驗） |
| CI | #1963（翻譯檢查改用建置時抽出的字串，638）、#1965（What to Test 不收的字元）、#1969（CI 分片） |

沒有審的（0 點）：
- 只改文件：#1953（L13 本身）、#1955、#1960、#1968、#1975、#1979、#1981、#1982。
- 只改測試：#1951、#1970。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（發版前必修） | **0** |
| P2（下一版修） | **0**（L13 的 P2 兩條還開著，見「上一輪的追蹤」） |
| P3（記著） | **10**：L14-1 到 L14-10 |

- 沒有 P1，不擋 122。
- **決定性、存檔、golden、replay**：
  - **#1967**：快取和舊算法逐項等價。
    - `trafficOppositeCounts` 取代「其他每一班反向集合的聯集」。同一個 plan 裡每列車只有一個 service（`trafficPlan` 對 `trains` 各取一次），所以「排除同一列車」等於「排除自己」。
    - `TrafficParts.Kept` 以列車加 `Shape` 共用。被快取的四個函式另外只讀路網、路線（`routePreference` 經 `runOrder`／`routeOrder`，只看時刻表的站與 `dispatchStream`）與 `keepLeft`，這些都在 `ServiceKey` 裡。
    - 第一點、列車站在那個 berth 時，查詢鍵帶 `trailEdges`，和 `trafficTrack` 判斷 `bodyStretches` 的條件一樣。
    - 結果照 `plan.services` 的順序用，不靠字典順序。
  - **#1961**：`standsAgainstTheLine` 用 `lines.first(where:)`，依陣列順序，結果固定。新的命令 `rebuildRealLine` 不在舊命令紀錄裡，舊紀錄讀得回。
- **#1971（玩家回報「點車站就當機」）**：
  - 新的 `stationDemandPairs(of:days:)` 和舊的（經 `stationRidership`）逐項相同：同樣的 guard、同樣照 `stations` 的順序、同樣「去或回 > 0」才列。
  - 只做字典查詢，沒有索引、強制解包或除法，**不會因這個 PR 當機**。
  - 當機原因仍不明，要當機紀錄（決策 644 下一步 1）。換站時舊的 `Task.detached` 不停（決策 644 下一步 3），還成立。
- **上一輪的追蹤**（以 a3f7842 為準）：
  - **L13-1（P2，還成立）**：
    - 120 的說明（`WhatsNew.swift:133-134`）仍說 1× 也滑行。
    - 程式仍只在 10×／60× 滑（`LoopTick.glidesOverTheStep`，`GameSession.swift:2256-2258`）。
    - 121 的說明沒提車窗視角，所以沒有更正。
  - **L13-2（P2，還成立，UNVERIFIED）**：`GameSession.swift:1197` 仍只看 `!isMap3DOpen`。
  - **L13-3、L13-5（P3，還成立）**：
    - 「Nangang's stabling sidings … the Liujia depot」（`:114`）。
    - 「Qianzhen depot／前鎮機廠」（`:118-119`）。
    - 「The Changhua roundhouse」（`:170-171`、`:431`、`:1206`）。
    - 121 的說明又多一處「the Liujia depot」（`:100`）；App 裡叫「Liujia Depot／六家基地」。
  - **L13-11（P3，部分）**：#1946 接進遊戲了。
    - 已有：Data Sources 頁有 OSM 的 ODbL 總聲明；實景地圖的 3D 照片帶「© OpenStreetMap」。
    - 缺：OSM 那一項列出的「遊戲從 OSM 取了什麼」沒有寫 3D 的真實站房（見 L14-9）。
  - **L13-4、L13-6 到 L13-10、L12-3、L11-8**：這一輪沒有 PR 改到相關程式（相關名稱在 diff 裡沒有出現），都還成立。
    - L13-6：`Map3DMetalView.swift` 約 1151 行，`frontsUp` 變 false 時仍不放 `facade`。
    - L13-10：`HighSpeedDemo.swift:589` 的 `precondition` 還在。
    - L11-8：`RunDepot.swift:402` 仍每次呼叫 `heldRunDepartures`。

## 二、發現

### L14-1（P3，核對過）#1948：「先離開軌道」的判斷，在有時刻表的線上讀的是拿下那列之後的車數

- **位置**：`Sources/GamePresentation/AutoService.swift`，`runsEveryTrainOnItsTrack`（約 759 行），在 `apply` 拿下擋路列車（`unassignTrain`）之後才呼叫（約 941 行）。
- **問題**：
  - 有時刻表的線（決策 133），`services(at:)` 回的列數就是 `trains.count`（`ServiceLine.swift:838-843`），所以拿下一列後，「在跑的列數」也跟著少一。
  - 只看這個判斷，它永遠成立，拿下的那列會被當成多出來的。
  - 用 `pattern` 的線也有一樣的問題：`lineTrainsInService` 只算線自己的班次，`onTrack` 卻算所有班次的車。這一點只讀程式，**UNVERIFIED**。
- **核對**（Linux，臨時測試，已刪；**VERIFIED**）：
  - 用 `SingleLineThreeTrainsTests` 的手放三列車，把線設成 12 班的時刻表，再按一鍵加待避線。
  - 第 3 列還是「先離開軌道」，線剩 2 列。
  - 量到的容量：拿下前 [3,3,3]，拿下一列後 [2,2,2]，加好後 [2,2,2]。
  - 但加待避線時，號誌站被插進線的停靠站（`setLineStops`），而插入停靠站會清掉時刻表（決策 133，`GameWorld.swift` 約 2054 行）。所以判斷時線已經是一般線，用的是一般線的容量（不靠車數，加好後 2）。這時讓第 3 列離開，正是決策 628 要的（「3 列只排得進 2 列」）。
  - 也就是說，上面這條路徑**今天走不到**。
  - 本 session 試著修（`!line.hasRuns` 就不讓它離開），測試仍紅，原因就是上面那一點，所以撤回，沒有改程式。
- **記著**：
  - 以後加待避線若改成保留時刻表，這個判斷就會讓需要的車離開。到時改成在拿下之前判斷，或有時刻表時不讓車離開。
  - 另一件事：一鍵加待避線會清掉這條線的時刻表。這是決策 133 本來就有的行為，不是這一輪的退步，但玩家可能沒料到。

### L14-2（P3，**UNVERIFIED**，要 Simulator）#1972：高度格的手勢被取消時，狀態不歸零

- **位置**：`RailwayGameApp/Views/MapConstructionHUD.swift`，`slidSteps`、`isHeld` 是 `@State`，只在 `onEnded` 歸零。
- **問題**：手勢被系統取消時，SwiftUI 不呼叫 `onEnded`。例如：第二根手指、跳出的 sheet、按住時格子換成不能拖的那種。
- **玩家可能看到**：格子停在亮底，讀數多算了沒套用的步數，直到下一次按。
- **修法**：改用 `@GestureState`，取消時會自動回 0。

### L14-3（P3，效能，沒量）#1962：`Map3DHandoff.nearestTrack` 在主執行緒掃全部軌道

- **什麼時候跑**：2D 拉得比一個 3D 場景還遠、又沒選站或車時，按 3D。
- **問題**：每個節點、每條邊的幾何點、每個車站都看一遍。
- **待量**：收購多條真實路線的局沒量過。若卡，可改用格子索引，或只看畫面附近的邊。

### L14-4（P3）#1974：清單的土地檢查少了「取樣點之間的格子」那一步

- **問題**：
  - `landCheckOnly` 在第一次土地檢查通過就停。
  - 完整收購時，取樣點之間碰到的格子還會再加買（`RealLineAcquisition.swift` 約 1552 行），那裡也可能回「土地不相連」。
- **玩家可能看到**：極少數的線在清單上可點，點了才被拒。被拒時仍有說明。

### L14-5（P3）#1974：清單只在面板出現時重算

- **位置**：`.onAppear { session.refreshRealLineAvailability() }`。
- **問題**：
  - 面板開著時擴建地圖，灰掉的線要關掉再開才更新。
  - 重算期間顯示的是上一次的結果，已經相連的線會暫時灰掉。

### L14-6（P3，**UNVERIFIED**）#1946：局部重蓋後，被切掉的站房還留在清單裡

- **位置**：`Map3DSceneRebuild.swift:163-183`。從 `old.stationExteriors` 開始，只替換重蓋的區塊重新加入的站。
- **觸發**：鋪軌把站房切到剩不到 50%（`exteriorLeast`），再局部重蓋。站房不畫了，但 `scene.stationExteriors` 還有它。
- **影響**：今天只有測試讀這個清單，畫面不受影響。

### L14-7（P3，**UNVERIFIED**）#1946：可能畫出沒有站房的車站

- **位置**：`Map3DStations.swift` 的 `exterior(for:)`。
- **問題**：
  - 只要有真實站房「立著」，就把站型自己的站房藏起來。
  - 但真實站房只在它的原點落在這次蓋的範圍內時才畫（`addStationExteriors`、`contains(x:y:)`）。
- **觸發**：月台中點在場景內，站房原點剛好在場景外，而且沒有串流的區塊含到它。這時兩種站房都沒畫。串流通常會蓋到鄰塊，所以少見。

### L14-8（P3）#1957：站務員的框用字典的第一個

- **位置**：`ContentView.swift:1588` 取 `stationMasterFrames.values.first { !$0.isEmpty }`。字典以 UUID 為鍵，順序不固定。
- **觸發**：兩個站務員 view 同時量到（開始建造時的交接），圖例可能短暫避錯那一個。
- **影響**：舊 view 的 `onDisappear` 跑完就好。

### L14-9（P3）L13-11 的剩餘：Data Sources 的 OSM 一項沒列 3D 真實站房

- **位置**：`DataSourceCredits.swift` 約 395-406 行。
- **問題**：`Map3DStationExteriorBatch1.swift` 的建物輪廓標了「© OpenStreetMap contributors, ODbL 1.0」，但 OSM 一項列出的用途裡沒有它。
- **影響**：總聲明在，所以有署名，只是沒寫用在哪裡。
- **修法**：下一個改 Data Sources 的 PR 加一行。

### L14-10（P3）#1959：路線報表用第一次收購的日子

- **位置**：`LineReportText.swift`，`acquisitions.first { $0.line == id }?.day`。
- **問題**：同一條線賣掉再買時，用的是最早那天，所以報表從第一次收購的隔天算起。
- **影響**：只影響報表從哪天開始。

### 看過、沒有疑點的

- **#1964**：`crossings` 先用 `guard` 排除完全在畫面外的線段，所以 `x0...x1`、`y0...y1` 不會倒過來；NaN 座標也被 guard 擋掉。
- **#1959**：
  - `NewTrainArrival.together` 的 `arrivals[0]`：唯一的呼叫端先 `guard !new.isEmpty`。
  - `StationLabels` 的排序比較是嚴格弱序。
  - `TrafficOverlay.namingHolders` 平手時取 ID 小的。
- **#1972**：步數先 `clamped`，放開才送一次命令；夾住的範圍和 `raiseNetworkEnd` 用同一個 `heightRange`。
- **#1962**：
  - `openingDistance` 取場景與 2D 距離的較小者，再由 `Map3DCamera.init` 夾住。
  - viewport 高度為 0 時有 `max(…, 1)`。
  - 夜窗的 `fwidth` 在分支前取。
- **#1973**：`followableTrain` 讀 `tappedTrainID`，和原本卡片上的列車相同。
- **#1974**：背景檢查比對的拒絕文字和 `refusedForLand`、`RealLineRing` 的一致。
- **#1961 的 `RealLineRebuild`**：
  - `main[0]`、`beside[0]` 一定有：鏈是非空才建。
  - `low < high`：`along` 遞增，`need > 0`。
  - 切片前先 guard `lowBeside < highBeside`。
- **121 之前的十個**（子代理讀）：
  - #1943、#1944、#1945、#1954、#1956、#1941：沒有疑點。
    - #1954：`HighSpeedDemoTests` 25 支過，**VERIFIED**。
  - #1957、#1946：疑點見 L14-6 到 L14-8。
  - #1948：疑點見 L14-1。
  - #1958：見 L13-1、L13-3。

## 三、驗證紀錄

- **建置**：`swift build --build-tests -Xswiftc -warnings-as-errors`（Linux，Swift 6.4.0）乾淨。
- **測試**：`swift test --skip-build`（Linux，**VERIFIED**）：
  - 11 個類別全過（3 支要環境變數的報告測試跳過）：`StationTapCostTests`、`NetworkHeightFixTests`、`RealLineListingTests`、`Map3DOpeningTargetTests`、`TrackNumberPlacementTests`、`TrafficPlanKeptTests`、`FollowerAgainstTheLineTests`、`SelectionHeadLayoutTests`、`NewTrainArrivalTests`、`TrafficOverlayTests`、`MapFocusTests`。
  - 子代理另跑 `HighSpeedDemoTests`，也過。
- **L14-1 的臨時測試**：結果見 L14-1。量完已刪，沒有留在 repo 裡。
- **UNVERIFIED**：畫面、手勢、Metal、MapLibre 7、UI 測試都只讀了程式。沒有 macOS，也沒跑 iOS workflow。

## 四、下一輪

- REVIEW-L15 從 **#1983** 起（`main` a3f7842 之後）。
- 還沒派的：
  - L13-1、L13-2（P2）。
  - L13-3 到 L13-10。
  - L14-1 到 L14-10。
  - L12-3、L11-8。
  - 之前的 L9-4、L9-5、L9-7、L10-4 到 L10-13。
