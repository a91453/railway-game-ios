# 交接：PR #1601–#1686 審查（審查 L4）

派工單 REVIEW-L4（遊戲規劃第 41 任 session_01YGNNunAdcksLhSB1H1495m，2026-11-01）：獨立審查 #1601 到 #1686 之間已合併、改了程式（`Sources/`、`RailwayGameApp/`、`tools/` 的程式、`.github/` 的腳本）的 PR，找正確性 bug。做法同審查 L1（`PR1510_1549_REVIEW_HANDOFF.md`）、L2（`PR1551_1578_REVIEW_HANDOFF.md`）、L3（`PR1579_1610_REVIEW_HANDOFF.md`）。

- Session：session_01YGNNunjEfxiHkJqASKZyZB，branch `claude/review-l4`。
- 基準：`main` **6ebf8c7**（#1666 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff。
- 做法：GameCore 的 #1676（LOOPRUN）由本 session 自己讀；其餘分七組交給只讀的子代理（不建置、不改檔）。回來的每一項由本 session 重讀程式路徑；L4-1、L4-2 另用 Linux 臨時測試重現，L4-3 的疑點用 Simulator 的截圖 run 結果推翻。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。臨時測試量完刪掉，沒有提交。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

L3 已審到 #1610（含 #1604、#1606、#1608、#1610），本輪從 #1601 起、扣掉這幾個。

| 層 | PR |
| --- | --- |
| **GameCore** | #1601（518 停站走待避線）、#1612（521 預覽跳過乘客檢查）、#1627（ALISHAN2）、#1629（506 車站擴建，存檔 78）、#1630（526 LOOP-SIMPLE）、#1631（527 回送不走反向線）、#1636（528 刪掉的收購線可再買，存檔 79）、#1649（PLANDAY 路線搜尋）、#1651（P2-7 續，說出原因）、#1654（533 學校醫院旅客）、#1660（534 擴建條件）、#1669（路線搜尋前緣攤平）、**#1676（535 LOOPRUN 環線班次，存檔 80、golden 76）** |
| 存檔／指令／經濟／收購（GamePresentation＋App） | #1609、#1615、#1616、#1617、#1618、#1619、#1620、#1621、#1624、#1625、#1626、#1628、#1633、#1635、#1639、#1641、#1648、#1652、#1656、#1658、#1665、#1666、#1668 |
| 3D 與畫面 | #1634、#1637、#1642、#1643、#1647、#1653、#1659、#1661、#1667、#1671、#1672、#1680、#1681、#1684、#1685 |
| CI 腳本 | #1677、#1679、#1682 |

只改文件、資料、美術預覽或「這版新增」文字的（#1602、#1603、#1605、#1607、#1611、#1613、#1614、#1622、#1623、#1632、#1638、#1640、#1644–#1646、#1650、#1655、#1657、#1662–#1664、#1670、#1673–#1675、#1678、#1686）沒有審；只改 UI 測試的（#1613、#1646、#1655、#1662）沒有審。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **2**：L4-1、L4-2 |
| P3（記著） | **10**：L4-4～L4-13 |
| 推翻的疑點 | 1：L4-3 |

兩個 P2 都有 Linux 重現。L4-1 現在玩家碰得到（號誌關、照真實班次的線、進站前 1 km 內有渡線），列車會停到對向月台、在對向正線上開；L4-2 是 #1676 留下的潛在當機，**環狀輕軌收購（決策 535 PR 2）上線前一定要修**，否則一買就當。

### GameCore：#1676（LOOPRUN，存檔 80）

- **非環線完全不變**（逐處看過，已告訴 WENHUBISECT）：`runWays` 非環線回 `[nil]`；`pendingRunStarts(way: nil)`、`runTrainsWaiting(way: nil)` 回原清單；`runTrainsReady` 的 `way.map` 為 nil 時照舊；「太多車入庫」的 kept＝`waiting.prefix(wanted)` 與 leaving＝suffix 不相交，多的 filter 不改結果；`emptyRun(facing: nil)` 只跑一輪、同舊路徑；出庫的 `ringPullOutBerths` 要 `isRing && hasRuns`；Boarding、PassengerDemand、PassengerRoutes、`ServiceLine.services` 的新分支都以 `isRing` 守門。所以文湖線（非環線）在 446bf7f..main 間變卡，原因不在 #1676。
- **存檔**：`LineRun.way` 用 `decodeIfPresent`／`encodeIfPresent`；`canHave` 在非環線要求 `way == nil`、環線要求有 `way`，79 版以前沒有環線班次，所以舊檔照讀；`currentVersion` 80、遷移註解、`v80-ring-runs.json` 都在。
- **環線的算式**：`ringLegs`（同站＝一整圈）、`ringPlace`（outer 的位置 `(n − s) % n`）、`PassengerRoutes` 把 arc 的位置換回站（`(n − start) % n`）、`reverseLine` 把 `way` 對調、`setLineRing` 兩個方向都擋有班次的線：逐一對過，前後一致。
- **乘客與經濟**：環線的區段數改成 `stops.count`（含最後一站回第一站），`runHeadway` 用 `isOutbound`（環線看 `way`），對。
- 新發現：L4-2（GamePresentation 兩處還用非環線的 `run.calls`）、L4-11（每步多出的路徑搜尋，效能）。

### GameCore：其他

- **#1629／#1660**（車站擴建，存檔 78）：兩個 `release` 與轉乘 `enqueueTransfer` 都傳車站自己的容量；`DoorCrowding` 以 `max(1, holds)` 防除以零；讀檔把隊伍壓到各站容量內；`expandStation` 先檢查再扣錢；`fullDays` 只在大於 1 時寫，沒有升存檔版本也安全（舊版忽略未知鍵）。
- **#1636**（收購線刪掉可再買，存檔 79）：`removeLine` 與 `removeStation` 都 `forgetAcquisition`；讀檔丟掉線已不在的收購紀錄；`splitTrackEdge` 同時改兩份邊清單；整個收購（含拆舊軌）是一個指令、在複本上做。
- **#1649／#1669**（路線搜尋，宣稱逐位元相同）：`orderPrecedes` 與舊陣列比較等價；`paused(before:)` 的截斷（`madeAt`、`poppedAt`、`droppedAt`）與重建 heap 和新搜尋同序；`precedes` 是嚴格全序；`frontierNext` 與 `labels` 等長。沒有找到結果不同或會當的情形。只有 L4-12（記憶體）。
- **#1654**：學校醫院旅客的權重都大於 0、`Pair.hours` 固定 24、計畫快取鍵含 `civic`，決定性 OK。
- **#1630、#1631、#1612、#1627、#1651**：沒有找到錯；#1651 有 L4-13（效能）。
- **#1601**：L4-1。

### GamePresentation／App（看過、沒問題的）

- **萬／億（#1633、#1639）**：四捨五入遠離零；99,999,499 → 9,999.9 萬、99,999,500 → 1 億；未滿 1 萬顯示全數；負數用 `magnitude`，`Int64.min` 不溢位；`StatusBarWidths` 與 `compactText` 同一個進位判斷。
- **NT$ 與 ≈US$（#1625）**、**7 天準點率（#1626、#1641）**：至少 10 班才算，不會除以零；`lateTrips` 不超過 `trips`。
- **#1616**：`startLesson` 每條路都先寫自動存檔（L3-1 關掉）；從 3D 按「擴大地圖」會忘掉回 3D（L3-2 關掉）。
- **#1617、#1620、#1621、#1652**：舊泡泡在新的算好後才換、世界變了就丟；`openedAt` 只在轉成經營模式時設；赤字、有貸款、挑戰中仍不能轉。
- **#1624**：L1-2、L1-3、L2-3～L2-5、L3-5～L3-10 的修法逐項對過。
- **收購（#1665、#1666、#1668、#1628）**：買線是一個 `perform(.acquireRealLine)`，失敗什麼都不變、一次復原；`moreDepots`、`clearing` 是可選欄位，舊紀錄照讀；文湖線兩座機廠各收自己那一端過夜的車；子代理重跑 `extract_metro_runs.py` 與提交的 `metro_runs.json` 逐位元相同。
- **3D（#1634、#1637、#1659、#1661、#1647、#1681、#1684）**：射線前進有上限、處理 NaN；`screenPoint` 擋掉眼睛後面的點；#1684 的退化情形（零長邊、單節、車比軌道長、軌道盡頭、倒車）都有退路，`location(at:)` 的前置條件成立。
- **列車模型（#1642、#1643、#1671、#1680、#1685）**：#1680 合併前先合了 #1685，`Map3DTrainSets.swift` 與 `hashes.lock.json` 兩邊的東西都在（`r100Hauled`、`breezyBlue`、`freight`、`nearOnly` 的 `BLUE` 與貨運鍵、`cycleFromFront`、`headOf`）；`set-BLUE-head` 14,636 三角形在 20,000 上限內；被刪的 `.r135`、`.r200` 沒有人再引用。
- **CI（#1677、#1679、#1682）**：`swift-shards-selftest.sh` 本機 **VERIFIED**；#1682 只改 timeout。

## 二、發現

### L4-1（P2）#1601：號誌關時，停站列車會越過渡線停到對向正線的月台，之後在對向正線上開

- **位置**：`Sources/GameCore/Railway/RunSpacing.swift:398-426`（`freePlatformPath`）。
- **問題**：#1601 之前，列車自己的月台空著（`own == 0`）就不改路徑。#1601 讓「會繼續開」的列車在目標是直通那一條時，也從 `platformApproach`（1 km）切點改找 `beside` 的空月台。`beside` 是 `berths(of:length:)`（車站所有月台，兩個方向的正線都算）扣掉直通那一條；`path(..., eligible:, keepingLeft: true)` 從切點找最短路，不擋對向正線；新加的 `crosses` 只擋走過直通那條邊的路。所以切點之後到月台之間有渡線，就會選到對向正線的月台（空的月台 `platformWaits` 是 0，比 `max(own, 1)` 小）。決策 228 說 1 km「比車站的待避線伸得遠，所以不會在更遠處切到對向」，但渡線在 1 km 內時擋不住；#1601 之前只有「自己的月台被佔」時才會走到這一步，#1601 讓一般停站都會。
- **什麼時候會碰到**：號誌（交通管制）關、照真實班次的線（收購或示範的線，`followsRealTimetable`）、雙線、某站進站前 1 km 內有渡線（玩家自己鋪的渡線、決策 247 雙線工具在雙線段兩端放的渡線）、那時沒有對向列車要停那個月台。列車停到對向月台，接著沿對向正線開往下一站；對向的車來時會互相擋（決策 527 在三鶯線看到的對頭卡法），可能卡死。
- **驗證**（Linux，臨時測試，量完刪掉）：雙線 P–X–Q，東正線 e2、西正線 e4，X 進站前一組渡線 e3（J1→K，1/20），X 在 e2、e4 各一座同位置的月台，Q 也是；號誌關；一條線 P→X→Q 一班（10:05／10:12–10:13／10:20）。main 6ebf8c7：列車在 X 停在 **e4**（對向），之後沿 e4 開到 Q（`stationsStoppedAt == [Q]`，仍在 e4）。#1601 之前（aa13937^1）同一個測試通過：停在 **e2**，開到 Q 時仍在 e2（第四節）。所以是 #1601 造成的退步。**VERIFIED**。
- **建議修法**：`beside` 只留不用換到對向正線就到得了的月台，例如路徑不能走 `opposingServiceTraversals` 或線路的規劃方向（#1631 的 `oneWayAgainst`）標成反方向的邊；或要求從切點出發的路要接回直通那條軌道的同一條正線。回歸測試照上面的場景，修前紅、修後綠。要動 GameCore，佔一個 GameCore 名額。

### L4-2（P2，潛在；環狀輕軌上線即 P1）#1676：到站板與運行圖還用非環線的 `run.calls`，環線跨接縫的班次會讓到站板當掉

- **位置**：`Sources/GamePresentation/DepartureBoard.swift:291`（`runRows`：`let calls = run.calls`，再用 `run.times[position]`）；`Sources/GamePresentation/TrainDiagram.swift:356`（`runTrips`：`zip(run.calls, run.times)`）。
- **問題**：#1676 加了 `LineRun.calls(stopCount:)` 與 `ServiceLine.calls(of:)` 給環線，`run.calls` 只對非環線對（`from < to` 往上、否則往下）。環線 inner 從 5 到 0（6 站，跨接縫一段）：`run.calls` 是 `[5,4,3,2,1,0]`（6 個），`times` 只有 2 個 → 在站 0 的 `position` 是 5，`run.times[5]` 越界當掉。不越界的也錯：fixture 的 D→A inner 班次 `run.calls` 是 `[3,2,1,0]`，實際停 `[3,4,5,0]`，到站板會在不停的站列出、在停的站漏掉；整圈（`from == to`）只剩第一站。
- **什麼時候會碰到**：現在**碰不到**：GameCore 的環線班次只能由 `setLineRuns` 設，GamePresentation 只有收購會呼叫，還沒有環線的收購（決策 535 的 PR 2，高雄環狀輕軌）。PR 2 一上線，玩家買了環狀輕軌、打開跨接縫那一站的到站板就當。
- **驗證**（Linux，臨時測試，量完刪掉）：讀 `SaveFixtures/v80-ring-runs.json`，把環線的 `runs` 換成一班 inner 5→0（兩個時刻）再解碼 `ServiceLine`，對每一站呼叫 `DepartureBoard.runRows(...)`：第一站就 `Fatal error: Index out of range`。fixture 原本的 D→A 班次印出 `calls [3, 2, 1, 0]`、`ring calls [3, 4, 5, 0]`。**VERIFIED**。
- **建議修法**：兩處改用 `line.calls(of: run)`；`destination` 用最後一個 call（環線的 `run.to` 對，但整圈時是出發站，照 `endsHere` 處理）。`TrainDiagram.lines(through:)` 已會在環線繞回處斷開。加一個 Linux 測試：上面的設定不當，跨接縫那站有列、`comesFrom` 是前一站。只動 GamePresentation，排在決策 535 PR 2 之前或一起做。

### L4-3（推翻）#1615：「不存檔離開」按鈕會不會因為 SwiftUI 先把 `isPresented` 設成 false 而什麼都不做

- **疑點**：`RailwayGameApp/Views/HUDView.swift:110-132` 的 alert setter 收到 false 就 `keepPlayingUnsaved()`（清掉 `unsavedLeaving`），而按鈕呼叫的 `leaveWithoutSaving()`（`GameLauncher.swift:1996`）開頭 `guard unsavedLeaving != nil`。若 SwiftUI 先寫 binding 再跑按鈕，按了不會離開。
- **結果**：`website-screenshots.yml` run **41216089932**（#1615 合併的 head 1039265，success）跑了 `WebsiteScreenshotTests.testLeavingWithoutSaving`，按下 `menu.leaveWithoutSaving` 後斷言 `start.brand` 出現：通過。所以在 Simulator 上會離開，不列。改成用 `presenting:` 捕到的值（像 `ControlPanel`、`LinesPanel` 那樣）比較穩，但不急。

### L4-4（P3）#1656：CRASH101 的解釋與修法可能只蓋到一個畫面

- **位置**：`RailwayGameApp/Views/YearEndReport.swift:22-27`（`StatementGrid` 的 `ViewThatFits` 裡有 `ForEach`）、`RailwayGameApp/Views/ContentView.swift:1067-1078`（工具欄的 `ViewThatFits` 包著有 `ForEach` 的 `ControlPanel`）。
- **問題**：#1656 說 SwiftUI 在主執行緒外量 `ViewThatFits` 的子視圖、跑到 main-actor 的 `ForEach` 閉包而當。若是這樣，同樣的寫法還在上面兩處；若不是，換成的 `BuildToolButton.body` 也是 main-actor，解釋就不對。讀程式推的，沒有當機記錄可對。
- **建議**：拿實機的當機記錄頂端 frame 對一次；iPad 入門 5 的 UI 測試加跑「年終報表」畫面。

### L4-5（P3）#1618：還在算跳過夜晚時按捷徑、接著進建設模式，跳過的要求被吞掉；不進建設卻開關工具會晚一點才跳

- **位置**：`Sources/GamePresentation/NightSkip.swift`（`skipToMorning`、`lookAgainForNightSkip`：`skipToMorningRequested` 只在 answered 分支清掉）。
- **建議**：進建設模式時清掉要求，或在 answered 分支外也處理。讀程式推的。

### L4-6（P3）#1684：車尾、車頭超出軌道追蹤範圍的那段，在道岔處選編號最小的邊

- **位置**：`Sources/GamePresentation/TrainTrackReach.swift:41`（`back`：`trailEdges` 用完後取進節點編號最小的邊，不是來的那條）、`:63`（`front`：`pathAhead` 空時取 `ways.first`）。
- **問題**：車尾剛過道岔、從編號大的那支進來時，最後一節的後半與延伸的 2 節畫到另一支上，看得到折角；班次在通過站結束、沒有路時，車頭半節可能彎進渡線或側線。只是外觀。

### L4-7（P3）#1684：每 tick 多走幾次軌道

- **位置**：`Sources/GamePresentation/TrainMotion.swift:329-366`、`Map3DTrains.swift:53-55`。每輛車每 tick 跑 `bodyPath`、`back`、`front`，`Heights(world:)` 又跑一次 `back`、`front`，每次都重建經過邊的 `trackGeometry`；`front` 呼叫 `pathAhead` 算完整剩下的路只用前一兩段。實景密集時刻表、高倍速時是主執行緒的工作。沒有量。
- **建議**：每 tick 算一次共用；`pathAhead` 只取前幾段。

### L4-8（P3）#1659：3D 點一下時對全部的邊逐段投影

- **位置**：`Sources/GamePresentation/Map3DPick.swift:216-243`、`:258-261`。附近沒有節點時，對每條邊重建 `trackGeometry`、每 16 m 投影一次（`Map3DMatrix.project` 每次配兩個陣列），沒有視錐或外框剔除，在主執行緒。實景上千段軌道時可能每點一下頓一下。沒有量。
- **建議**：先用邊的外框剔除，或用場景已建好的幾何。

### L4-9（P3）#1647：擴建到「站廳」的高架站，月台短於約 120 m 時外側樓梯站到月台外

- **位置**：`Sources/GamePresentation/Map3DStations.swift` `addEntrances` 的 `.elevated`：外側那對樓梯固定離中心 60 m，不看月台長度。
- **建議**：夾在月台半長內。

### L4-10（P3）#1648：台鐵 1、2 次的終點寫成只通過的站，回程那段沒畫

- **位置**：`tools/real-timetables/extract_tra_schedule.py`（`臺北-環島` 在 `tra.json` 找不到，被丟掉）→ `Sources/GamePresentation/RealTrainMotion.swift` 的 `service(atStationNamed:)`（用 `stops.last` 當終點）與 `RealTrainTraffic.traRun`（只留同一條線上最長的一段連續停站）。
- **問題**：子代理重跑工具看到：1 次最後是「南港（停）、松山（通過）」，到站板寫「往松山」；2 次是「板橋（停）、萬華（通過）」。1 次在縱貫線北段出去 27 站、回來 8 站，回來那段被丟掉，最後一晚在台北附近消失。全 1,038 班只有這兩班。本 session 沒有重跑資料（**UNVERIFIED**）。
- **建議**：工具把 `臺北-環島` 當 `臺北`；或 Swift 端用最後一個有停的站。

### L4-11（P3）#1676：環線每步多做的路徑搜尋

- **位置**：`Sources/GameCore/Railway/LineRuns.swift`（`facesRingWay`：兩次 `linePath`）←`RunDepot.swift` 的 `runTrainsWaiting(way:)`、`ringPullOutWay`。
- **問題**：有班次的環線，每站、每個方向、每輛在站的車都做兩次 `linePath`，沒有記憶。現在只有測試裡的環線有班次，環狀輕軌上線（38 站、約 20 組）後值得量一次。

### L4-12（P3）#1649：暫停的搜尋複本不剪 `orders`，不計入標籤預算

- **位置**：`Sources/GameCore/Passenger/PassengerRoutes.swift` `paused(before:)`：複本保留父搜尋整個 `orders` 與之後的節點，`held` 不算它們，記憶體可能比決策 470 的估計大。結果不受影響。

### L4-13（P3）#1651：`runDepotEntryCandidates` 先收齊全部候選，死結搜尋 `trainsInTheWay` 比以前常跑

- **位置**：`Sources/GameCore/Railway/RunDepot.swift` 約 155–180 行。以前在第一個候選就回傳；現在只要有一站沒有班次到期就會算 `trainsInTheWay`，`heldDepartures()` 每次又用新的 memo 對每條線重做。結果與順序不變。沒有量。

### 沒列的

- #1685 藍皮解憂號：車頭一節 31.6 m、客車各 20 m，畫出來比 GameCore 的車身長約 11.6 m；決策 541 看過總覽圖，屬外觀取捨，不列。
- #1625 負餘額寫「≈ US$-50」：數字對，只是寫法。
- #1626／#1641：週中才打開擬實運轉時，之前的日子沒有誤點紀錄，準點率偏高一點：屬設計。
- #1609 `zone(near:)` 會把分區標成玩家自選：不影響結果。
- 決策文件已列為缺口或下一步的（#1627 非路線服務走登山軌道、#1676 的 P3 等）不重複列。

## 三、驗證

Linux、Swift 6.4.0、`main` 6ebf8c7：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（通過）。
- L4-1 在 #1601 之前的對照：aa13937^1 的 worktree，**VERIFIED**（通過）。
- L4-1、L4-2 的重現：臨時測試（`Tests/GameCoreTests/ZZReviewL4OppositePlatformTests.swift`、`Tests/GamePresentationTests/ZZReviewL4RingRunTests.swift`），量完刪掉，沒有提交。**VERIFIED**。
- `.github/scripts/swift-shards-selftest.sh`：**VERIFIED**（通過）。
- L4-3：Simulator 的截圖 run 41216089932（之前就跑過的，本 session 沒有另跑）。
- L4-4～L4-13：讀程式（L4-10 是子代理跑工具看的資料），**UNVERIFIED**（沒有量、沒有 Simulator）。

## 四、#1601 之前的對照

把 L4-1 的臨時測試放到 aa13937^1（#1601 合併前）的 worktree，Linux 建置後跑：列車在 X 停在 e2（自己的正線，offset 123,136），之後在 e2 停到 Q；測試通過（EXIT 0）。main 6ebf8c7 上同一個測試失敗（停在 e4）。**VERIFIED**。worktree 與臨時測試量完刪掉。

## 五、下一步

- L4-1 交給規劃派人修（佔一個 GameCore 名額），回歸測試照第二節的場景。修好前，號誌關的收購線若玩家回報「列車逆向」「對頭卡住」，先看停站列車是不是停到對向月台。
- L4-2 排在決策 535 PR 2（高雄環狀輕軌收購）之前或併進 PR 2；PR 2 的派工單要寫上。
- L4-4 有實機當機記錄時對一次；L4-5～L4-13 記著，有玩家回報或有空的 session 再處理；L4-7、L4-8、L4-11、L4-13 可以交給查主執行緒停頓或 CIOPT 的工作順便量。
- 下一輪審查從 #1687 起數。
