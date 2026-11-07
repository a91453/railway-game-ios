# 交接：PR #1858–#1907 審查（審查 L11）

派工單 REVIEW-L11（遊戲規劃第 52 任 session_01YGNNun5Pr4b6AHKwn6MneD，2026-11-06，HANDOFF §1.1 固定三件之一；回報改寄第 53 任 session_01YGNNunyQhaha49M1KRzGVB）：審查 L10（`PR1803_1857_REVIEW_HANDOFF.md`）之後已合併、改到程式的 PR。格式同 L10。

- Session：REVIEW-L11 session_01YGNNumFayrcJEfodjKj3Px，branch `claude/review-l11`。
- 基準：`main` **6e525b2a**（#1906 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff，和它的決策檔。
- 點數（HANDOFF「多久審查一次」）：GameCore 8 個 × 2 = 16，GamePresentation／App／CI 16 個 × 1 = 16，共 **32 點**。只比 30 多 2 點，其中兩個是更新說明的文字，所以沒有分 L11a／L11b，一輪看完。
- 做法：
  - GameCore 由本 session 自己讀：#1862、#1866、#1871、#1872、#1881、#1883、#1889、#1896 的 GameCore 部分。
  - GamePresentation／App 分給兩個子代理：
    - 一個審 3D 與地圖：#1858、#1861、#1880、#1884、#1888、#1898、#1899、#1902。
    - 一個審線路、營運與文字：#1862、#1866、#1867、#1868、#1870、#1873、#1874、#1883、#1889、#1896 的展示層，以及 #1882、#1893、#1897。
  - 子代理的每一點都附重現或程式位置。P2 與能重現的 P3 都用 Linux 臨時測試量過，量完就刪，沒有提交。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

逐一核對 `git log --first-parent 85973647..6e525b2a`。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1862**（L10-2 修正：纜車、渡輪不接機廠）、**#1866**（決策 601：觀光客源從到得了的站挑）、**#1871**（決策 590 續：退回 #1837 的 COW）、**#1872**（決策 605：班次可過站不停，存檔 86）、**#1881**（決策 609 續：多出來、擋路的空車先回機廠）、**#1883**（決策 612：環線不換對向月台）、**#1889**（CRASH-SIGHTS：景點狀態一起算）、**#1896**（決策 614：`isScheduled` 共用行程） |
| GamePresentation／App | 3D 與地圖：#1858、#1861、#1880、#1884、#1888、#1898、#1899、#1902。線路與營運：#1862、#1866、#1867、#1870、#1873、#1874、#1883、#1889、#1896。其他：#1868（UI 測試拆 lane、站長泡泡、`ios-build.yml`）、#1882、#1897（更新說明）、#1893（著作權那行） |
| 只改測試 | #1887、#1895（捏合 UI 測試）、#1901、#1906（macOS 14 測試編譯），略看 |

沒有審的：

- 只改文件的有 #1860、#1863、#1864、#1877、#1878、#1890、#1892、#1894、#1900、#1907。
- #1859、#1865 只加 `tools/real-railways/` 的研究腳本與報告測試，遊戲沒有載入。
- #1886 只加機廠車場零件組的配方與 `tools/` 匯出（模型，0 點）。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **1**：L11-1 |
| P3（記著） | **7**：L11-2 到 L11-8 |

- 沒有 P1，所以沒有 send_message 通報。
- GameCore 的 PR 沒有發現 P1 或 P2，只有 **L11-8**（P3，效能，UNVERIFIED）。
- 上一輪的修正（#1862）確認修好：
  - L10-1、L10-3：子代理在另一個工作目錄把修法退回重跑，兩支回歸測試都紅（`1100 ≠ 100`、`3 ≠ 4`）；放回後綠（**VERIFIED**）。
  - L10-1 的 memo 鍵：`wantedTransfers()` 的輸入只有車站位置、非機廠的站、`acquisitions`、買來的線的停靠站、`branchRuns`（靜態），新加的 `boughtStops` 補上了唯一漏掉的那一個。線被刪掉時是 `[]`，也會讓 memo 失效。
  - L10-2：纜車的兩條路（`refreshCablewayTransfers` 與有 `meetsNear` 時的 `namedTransfer`）和渡輪都跳過機廠；`setStationDepot` 在有纜車或渡輪時也重算。

### GameCore

- **#1872**（決策 605，班次過站不停，存檔 86）：
  - `isValid`：`passes` 必須是首末兩停之間的站、不重複、照經過的順序；`times` 的數量改成 `along.count - passes.count`。不在中間的站、重複的站都會被擋。
  - 解碼時有 `"passes"` 但是空陣列就拒絕，編碼時空的不寫，所以同一個世界只有一種寫法。
  - 用到 `times[index]` 的只有 `RunTrip.timetable`，它用 `calls(stopCount:)` 的索引，已經扣掉過站。
  - `reverseLine` 把 `passes` 照 `last - $0` 翻，跑的方向也一起反，經過的順序不變。
  - 改線的停靠站時 `runs` 會清空（`ServiceLine` 543、`GameWorld` 2055），不會留下對不上的 `passes`。
  - `runsServe` 的兩條（一般線與環線）都排除上下車站在 `passes` 裡的班次。
  - 跳站的那一段沒有路線偏好（`routePreferences` 是相鄰兩站的），照 `path(from:toStation:)` 找路。決策 605 有寫，不列。
  - v86 fixture 與 `SavedGame` 的說明都加了。golden 不動：預設沒有任何班次有 `passes`。
  - `PassingRunTests`（11）、`SavedGameTests`（38）過。
- **#1871**（決策 590 續，退回 #1837）：
  - 就是 `git revert`。`GameWorld` 回到存放欄位，`==` 回到合成的，`GameWorldStorage` 刪掉。編得過，就表示 #1837 之後沒有新欄位留在已刪的 state 裡。
  - 審查 L10 看 #1837 時沒看出閃退的原因（`UnsafeMutablePointer` 沒有綁住儲存體的生命期，只是懷疑，還沒證實）。決策 590 已寫：要再做，先在 macOS 做出會紅的指令。本輪不列。
- **#1866**（決策 601）：
  - 對外連接的權重照舊，但現在也要先到得了；住宅最多的 5 站改成從到得了的站裡挑。`reaches` 只問到挑滿 5 站為止，問過的會記住。
  - `touristFlows` 裡同一站服務的幾個景點共用來源，`reaches` 不因景點而不同，可以共用。
  - 改了行為，但 golden 與 replay 都沒有變（CI 綠，本 session 也跑過 `GoldenScenarioTests`）。
  - `TourismTests`（28）過。
- **#1881**（決策 609 續）：
  - 多出來的空車：只在行車控制開、不是環線、本來沒有要回機廠的車時，才看最後一列；一小時內的班次少了它仍然都有車，才送回去。`ready` 先拿掉一個「現在」，就是這一列自己。
  - 擋路的空車：只在沒有閉塞區間時；`stuck` 的不受決策 296 的「剛出廠的先留著」保護，這是刻意的。
  - `trainsInTheWay` 的 `ways` 帶列車 ID，自己不會擋自己。
  - 喚醒時間多了一個 `start - 1 小時`，只在行車控制開、不是環線時。
  - 有 **L11-8**。
  - `HeldRunTrainInTheWayTests`、`SurplusRunDepotTests`、`RunTrainDepotDeadlockTests` 過。
- **#1883**（決策 612）：`platformWaits` 對有班次的環線回 nil，4 行。`RingRunsTests`（9）過。
- **#1889**（CRASH-SIGHTS）：
  - `attractionStatuses()` 共用一份 `AttractionStatusAsked`（當天的路網、客源候選、站對站到不到得了），和逐一呼叫 `attractionStatus(of:)` 的答案相同。
  - `graph` 用 `PassengerRouteGraph??` 分開「還沒算」和「算了但沒有」（非路網模式），沒問題。
  - 展示層的 memo 見 **L11-2**。
- **#1896**（決策 614）：
  - 新的 `isScheduled(_:pattern:journeys:)` 和舊的路（`lineJourney` 之後每個等級各呼叫一次 `lineHeadway` → `serviceRoundTrips`）逐步比過：都是自己的行程沒有就 false，再用 0 到 `service` 的行程算 round trip 與容量，等級逐一看 `plans[service]?.headway`。
  - 快取的鍵是線 ID 與服務編號，`journey(of:service:)` 只看這兩個；快取只活在一次呼叫裡，世界在那期間不變。
  - 記住「沒有行程」用 `.some(nil)`，讀回時 `if let` 解開外層，對的。
  - golden 24/24、replay 結果相同。

### GamePresentation

- **3D 與地圖**（子代理）：
  - **#1899**：**L11-1**。其餘查過的都對：`differsOnlyInTrack` 比了鍵的每個欄位；只有畫面正顯示被拿來重蓋的那一版時才局部替換，跳過一版就整個換；鋪了又拆、拆掉的邊都把新舊兩邊的點算進去；車站的變更連月台一起算；串流照新的 `trackCover` 與 generation 重來。
  - **#1902**：**L11-3**。第一個 tick（沒有上一個）用 0.1 s、時間倒退夾到 0.05、不會 NaN 或除以 0；換速度不會停 tick。
  - **#1888**：**L11-4**。
  - **#1858**：`pierShore` 和 `isPierCell` 一致；水的 runs 已排序不重疊；中英文一致（方位加「方」不會變「方方」）。沒發現問題。
  - **#1861**（決策 402／600）：`legs` 的區間與索引都有上下界保護，`line[start...end+1]` 不會越界。沒發現問題；另見「其他觀察」。
  - **#1880**（決策 607）：索引都 ≥ 1，佇列不會一直長，迴圈一定會結束。沒發現問題。
  - **#1884**：改成 `switch` 後語意相同。沒發現問題。
  - **#1898**（決策 615）：近景的玻璃有經過 `Map3DTransparentGlass.applying`；排序是穩定的嚴格弱序；鋪設模式仍然只有貓空。沒發現問題。
- **線路、營運與文字**（子代理）：
  - **#1862**：見上面「上一輪的修正」。
  - **#1866**：**L11-7**。
  - **#1867**（小碧潭單線，決策 603）：工具資料（1 組車、每站 1 股）和 `singleTrackUrban` 一致；舊存檔不改，決策有寫。沒發現問題。
  - **#1868**：`max-parallel: 2` 加 build job 最多佔 3 台 macOS；iPad job 等三個 partition；`-speaking-ms` 只在 DEBUG 讀。沒發現問題。
  - **#1870**（決策 602）：**L11-5**。
  - **#1873**（放空模式跟真實列車）：`setFollowingRealTrain` 在每條離開的路（結束、換畫面、找不到車，含 500 ms 等待中結束）都設回 false，不會卡在 10×。另見「其他觀察」。
  - **#1874**（決策 605）：從中間站出發時下一站從 `passes` 移除；反向時 `passes` 與 `way` 一起翻；第二股的待避線用 piece 1 的 `besideNodes`。沒發現問題。
  - **#1883**（決策 612／535）：環線站序旋轉、`turned`、建線時 `way` 反轉、`ringRoutePreferences` 取模都對得上。沒發現問題；另見「其他觀察」。
  - **#1889**：**L11-2**。
  - **#1896**：`createLineFromDraft` 的 `!runsLinesForThePlayer ? nil : (A ?? B)` 優先順序對；`trackPreviewCopy()` 與 `pricingCopy()` 只差 `trackEditDepth`，GameCore 裡只有乘客那條路讀它，拒不拒絕與渡線的幾何不受影響。沒發現問題。
  - **#1882、#1897**：**L11-6**。
  - **#1893**：App 裡只剩「© 2026 CHIENLIN YEH」，UI 測試沒有引用舊字串。沒發現問題。

### App

- 畫面、Metal、`Map3DPreviewScreen` 的替換流程都是 **UNVERIFIED**（沒有 macOS），只讀程式。

## 二、發現

### L11-1（P2）#1899：軌道鋪在真實鐵路旁時，局部重蓋和整個重蓋的結果不同

- **位置**：
  - `Sources/GamePresentation/Map3DSceneRebuild.swift:33`，`changes(from:_:to:_:)` 只把變更點周圍 `reach`（256 m）內的區塊算成要重蓋。
  - 原因在 `Sources/GamePresentation/Map3DRealTrains.swift:1006-1035`（`layRealRun`）與 `Sources/GamePresentation/Map3DScene.swift:1200`（`pieces(of:)`）。
- **問題**：
  - 玩家的軌道離真實軌道不到 `overlap`（3.4 m）時，那一段真實軌道會被藏起來。
  - 藏掉以後，下一段的起點換了，「每隔一個取樣點取一點」的奇偶跟著換，每 256 m 一塊的切法也跟著位移，一路影響到那段結束，最遠到 4 km 範圍的盡頭。
  - 範圍外的區塊還是舊的幾何，和重蓋的區塊交界處，真實線的路堤或高架和地面錯開、重疊或留缺口。
  - 串流不會重蓋場景自己的區塊，所以錯開會一直留著，直到下次整個重蓋。
- **玩家看到**：在真實台鐵旁邊鋪線後，遠一點的真實線橋梁或路堤斷開、浮起或陷進地面。
- **驗證**（子代理，Linux，**VERIFIED**）：
  - 臨時測試：台中站，在 `tra_sched` 一段 251 m、直的真實橋梁上鋪一條玩家軌道，範圍 8×8 區塊。
  - `changes` 找到 6 塊；範圍外另有 7 塊（column 2，row −8…−2）的 base、ground、mesh、shadows 和整個重蓋不同。
  - 地面三角形數例如 1136 → 1176、2283 → 2139、72 → 244；頂點最大位移 102–478（世界單位）。
  - `Map3DScene(rebuilding:)` 與整個重蓋比，同樣這 7 塊不同。
  - 把 `railways` 設成 nil 再跑，差異完全消失。
  - 現有的 `Map3DSceneRebuildTests` 抓不到，因為它的支線不靠近真實線。
- **修法建議**（擇一）：
  - `layRealRun` 的取樣奇偶改用沿線的全域取樣編號，256 m 分塊改用固定的沿線距離。這樣藏掉一段不影響下游，串流各自蓋的區塊也比較一致。
  - 或在 `changes` 裡，變更點在真實軌道的 `overlap`（或 `playerClearance`）內時，把那條真實軌道整個範圍的點都算進去。
  - 回歸測試照上面的步驟（真實線上鋪一段），斷言局部重蓋與整個重蓋逐塊相同。修前紅。

### L11-2（P3）#1889：景點面板的「買得起」要到隔天或下一個指令才更新

- **位置**：`Sources/GamePresentation/SightMarks.swift`，`sightsPanelRows` 的 `SightRowsMemo` 鍵是日子、`commandRevision`、語言；`Sources/GamePresentation/TourismText.swift:129` 的 `ShopOffer.canAfford` 卻跟著每個 tick 的現金變。
- **驗證**（子代理，Linux，**VERIFIED** 一個方向）：
  - 開局現金 = 名產店價錢 + 10 萬，`.fast` 跑 144 tick。第 49 tick 起錢不夠了，面板仍寫可以買；一天裡有 95 個 tick 不一致。
  - 這個方向只是按下去被 GameCore 拒絕。
  - 反方向（白天收到票款、錢夠了，按鈕卻灰到隔天）比較糟，但測試世界第一天沒有票收入，**沒有重現**，所以整體列 P3。
- **修法**：把 `world.economy.canAfford(Money(Tourism.souvenirCost))` 放進 memo 的鍵，或讀出時才算 `canAfford`。

### L11-3（P3）#1902：暫停後回來，第一段滑行跳一下

- **位置**：`Sources/GamePresentation/TrainMotion.swift:315`（`durations` 上限 5 s）；`RealTrainClock` 用同一條式子（`Sources/GamePresentation/RealTrainMotion.swift:1001`）。
- **問題**：
  - 暫停期間不重算 `TrainMotion` 與 `RealTrainClock`，`previous.time` 停在暫停前。
  - 恢復後第一段滑行被設成 5 s，但 1 s 後下一段就從取樣終點開始，剩下的直接跳過。
- **驗證**（子代理，Linux，**VERIFIED**）：暫停 60 s 後，1× 時滑 20%、跳 80%（舊版上限 1.25 s 時是滑 80%、跳 20%）；10× 時滑 2%、跳 98%。從背景回來、或很久沒動的列車再動時也一樣。
- **修法**：`previous.time` 和這次相差超過可能的 tick 間隔（`TickPace` 的單 tick 時間加 `longestRest` 再加一點餘裕）時，當作不知道上一個 tick，用 `tickSeconds`。

### L11-4（P3）#1888：岸線的 memo 鍵少了 `readsLandForFerries`

- **位置**：`Sources/GamePresentation/FerryTool.swift:499`，`ferryShoreMemo` 的鍵只有 `bounds`、`terrain`、`landBlocks`，但結果看 `readsLandForFerries`（`water` 與 `population` 有沒有設）。
- **問題**：第一次算岸線時 `water` 還沒設，memo 會存下沒有格子的版本；之後 `readsLandForFerries` 變成 true，每次點都說「附近沒有岸邊」。
- **影響**：這兩個值看起來是建 session 時就設好，實際碰到的機會低。讀程式，**UNVERIFIED**。
- **修法**：把 `readsLandForFerries` 加進鍵。

### L11-5（P3）#1870：南港展覽館換點之後沒有再檢查是否在地圖內

- **位置**：`Sources/GamePresentation/RealLineAcquisition.swift`，`points.allSatisfy(bounds.contains)` 之後才把南港展覽館的點換成 `fan.platform`（往東約 90 m）。
- **影響**：只有地圖邊緣剛好切在那 90 m 裡才會發生，大概會被 GameCore 拒絕，不會壞存檔。讀程式，**UNVERIFIED**。
- **修法**：換點移到 bounds 檢查之前。

### L11-6（P3）#1882／#1897：更新說明的名稱和 App 不同

- **位置**：`Sources/GamePresentation/WhatsNew.swift`。
- **問題**：
  - 118 英文第 46 行寫「With train control on」，App 與之前的說明都是「traffic control」。中文「行車控制」是對的。
  - 英文線名和收購清單（`RealLineAcquisition.swift:179-185`）不同：「the Wenhu line」→「Wenhu Line」、「the Airport MRT」→「Taoyuan Airport MRT」、「A Xiaobitan branch」→「Xiaobitan Branch Line」。中文「機場捷運」，清單是「桃園機場捷運」。
- **影響**：118 已發。之後的說明照 App 的字串寫；這次的要不要改，等之後本來就要改 `WhatsNew.swift` 的 PR 一起帶（HANDOFF「PR 綠了就不再推小修」）。

### L11-7（P3）#1866：站長的 `noSource` 說法永遠提到「地圖邊緣」

- **位置**：`Sources/GamePresentation/StationMasterAdvice.swift:705-707`，`sightUnreachable` 沒有照 `outsideConnections` 分開說。
- **影響**：現在是死分支（第 448 行只送 `.noStation`）。哪天開始送 `noSource`，在全台灣地圖上會叫玩家去接一個不存在的邊緣。
- **修法**：照 `TourismText` 加 `edge` 參數，或刪掉這個分支。

### L11-8（P3）#1881：`heldRunDepartures` 一次判斷裡算好幾次

- **位置**：`Sources/GameCore/Railway/RunDepot.swift`，`runDepotEntryCandidates(of:memo:)` 約 214–228 行，與 `trainsInTheWay(memo:)` 第 382 行。
- **問題**：
  - `trainsInTheWay` 每次都算一次 `heldRunDepartures`（掃所有沒有班的列車，每列 `lines.first(where:)` 再試排進路），`runDepotEntryCandidates` 又為 `heldRuns` 另算一次。
  - 這兩個都是每條有班次的線各算一次，但結果和線無關；`otherDepotRun` 每次也重算 `trainsInTheWay`。
  - 只在行車控制開時。行為正確，只是重複。
- **驗證**：讀程式，**UNVERIFIED**，沒有量。決策 614 量的大存檔指令成本裡不含這條。
- **修法**：`trainsInTheWay` 接受已算好的 `heldRunDepartures`，或在 `DispatchMemo` 裡依 tick 記住。

### 其他觀察（不編號，沒有量）

- #1861：每次蓋場景（包括每個串流區塊）都對所有週時刻表的車算 `legs`。
- #1873：`candidates(...)` 每秒在主執行緒上把所有線算一次，全台灣地圖上沒量過。
- #1888：`ferryPreview` 在 `readsLandForFerries` 時，草稿一變就在主執行緒複製世界並讀碼頭周圍的地；第一次進渡輪模式時在主執行緒算全台的岸線。
- #1874：`calls` 是空陣列的資料會讓 `calls[0]` 當掉；改之前就是這樣，資料是內建的。
- #1883：`RealLineRing.swift` 的 `start = seamMiddle + ringSeam/2` 若超過 `round.length` 會被夾住，接縫最多偏 40 m；現在的資料不會發生。

## 三、驗證紀錄

- `swift build --build-tests`（Linux，Swift 6.4.0，debug）：成功。
- `swift test --skip-build`（Linux，**VERIFIED**）：
  - 本 session 跑了 11 個類別，全過（`ReplayFixtureTests` 照舊跳過錄製那支）：`PassingRunTests`（11）、`SavedGameTests`（38）、`HeldRunTrainInTheWayTests`（2）、`SurplusRunDepotTests`（3）、`RunTrainDepotDeadlockTests`（3）、`RingRunsTests`（9）、`TourismTests`（28）、`CablewayTests`（17）、`FerryTests`（12）、`GoldenScenarioTests`（24）、`ReplayFixtureTests`（2 過 1 跳過）。
  - 子代理（3D 與地圖）跑了 12 個類別共 82 個測試，0 失敗，跳過 1 個（要環境變數的報告測試）：`Map3DSceneRebuildTests`、`TrainMotionTests`、`RealTrainMotionTests`、`FerryPierSnapTests`、`FerryCijinShoreTests`、`FerryToolTests`、`Map3DRealDispatchTests`、`Map3DInterchangeTests`、`Map3DInterchangeStreetTests`、`Map3DSunMoonCabinTests`、`Map3DTransparentGlassTests`、`Map3DCableCarTests`。
  - 子代理（線路與營運）全過，報告測試照舊跳過：`PlatformStopTests`、`TourismSessionTests`、`TouristSourcesReportTests`、`SightsPanelCostTests`、`AmbientRealTrainsTests`、`AmbientDirectorTests`、`Map3DFollowSpeedTests`、`Map3DStreamingTests`、`BuildCommandCostReportTests`（跳過）、`WenhuLineTests`、`TaoyuanAirportLineTests`、`KaohsiungLightRailTests`、`DanhaiDepotTests`，以及 `RealLineAcquisitionTests` 的兩支（`testAStopTakenOffALineBoughtLosesItsRegulars`、`testTheXiaobitanBranchIsSingleTrack`）。
- 臨時測試：L11-1、L11-2、L11-3 由子代理重現；L10-1、L10-3 的修前紅由子代理在另一個工作目錄退回修法確認。都已刪除，工作目錄乾淨。
- 畫面、Metal、iOS 行為、UI 測試：**UNVERIFIED**（沒有 macOS，沒跑 iOS workflow）。

## 四、下一輪

- REVIEW-L12 從 **#1908** 起（`main` 6e525b2a 之後）。
- 還沒派的：L11-1（P2），L11-2 到 L11-8；以及之前的 L9-4、L9-5、L9-7、L10-4 到 L10-13。
