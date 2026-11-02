# 交接：PR #1666–#1695 審查（審查 L5）

派工單 REVIEW-L5（遊戲規劃第 42 任 session_01YGNNum8LvQvgmgwxKHRvQ7，2026-11-02，105.1 發版後的固定一輪）：獨立審查 L4 之後已合併、改了程式的 PR，找正確性 bug。做法同 L4（`PR1601_1686_REVIEW_HANDOFF.md`）。

- Session：session_01YGNNumgF4LtnNX2bguZNyr，branch `claude/review-l5`。
- 基準：`main` **39aaec0**（#1695 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff。
- 做法：#1694（Package.swift／CI）、#1666、#1690、#1695 由本 session 自己讀；#1680、#1683 交給一個只讀的子代理（不建置、不改檔），回來的每一項由本 session 重讀程式路徑，L5-3 另用 Linux 臨時測試重現。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。臨時測試與臨時 print 量完刪掉，沒有提交。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

`git log --first-parent 6ebf8c7^..39aaec0` 逐一核對。L4 的基準是 6ebf8c7（#1666 合併後），L4 已列 #1685、#1686；#1666 L4 有看過，派工單要求再看一次。

| 層 | PR |
| --- | --- |
| **Package.swift／CI** | **#1694**（決策 544：Linux 上 GameCore 與 GameCoreTests 用 -O） |
| 收購／機廠資料（GamePresentation＋工具） | #1666（文湖線兩座機廠、`moreDepots`）、#1690（安坑機廠，ANKENGDEPOT） |
| 3D 與 2D 畫面 | #1680（R200 貨櫃列車，決策 539）、#1683（站名移到擁擠圈下方）、#1695（2D 列車沿彎道，決策 538 續；審查期間合併） |

只改文件或只加報告測試的沒有審：#1687、#1688、#1691、#1692，#1689（`BatchCadenceReportTests`，只在 `BATCH_CADENCE_REPORT=1` 時跑，加上決策 535 的文字）。GameCore 的程式這一段**沒有** PR 改過（#1694 只改建置旗標）。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **0** |
| P3（記著） | **7**：L5-1～L5-7 |

沒有 P1，沒有 send_message 緊急通報。

### #1694（決策 544，-O）：會不會讓只在 debug 抓得到的檢查失效、Xcode 與 Linux 分岔

逐項查過，**行為上沒有問題**：

- **檢查還在**：`-O` 保留 `precondition`、`fatalError`、整數溢位陷阱、陣列越界、除以零（只有 `-Ounchecked` 才拿掉）。`-O` 會拿掉的是 `assert`／`assertionFailure` 與標準庫的 `_debugPrecondition`。`grep` `Sources/GameCore`、`Tests/GameCoreTests`：沒有 `assert(`、`assertionFailure`、`#if DEBUG`；沒有 `Unsafe*` 指標或 `withUnsafe*`（`_debugPrecondition` 主要守的就是這些），所以沒有檢查因此消失。`&+`、`&*` 等是本來就不檢查溢位的雜湊與亂數，與 -O 無關。
- **浮點**：GameCore 唯一的浮點在 `RunSpacing.swift:92-97`（乘、除、比較），沒有 a·b＋c 的形式；Swift 不開 fast-math，`-O` 不改 IEEE 結果。發出去的 App（Release，arm64）本來就是 -O，CI（x86_64）現在和它同一種最佳化，比以前更接近玩家跑的。
- **Xcode 不分岔**：`#if os(Linux)` 在 manifest 編譯的主機上求值，Xcode 在 macOS 讀到空的 `swiftSettings`；`unsafeFlags` 只禁止「遠端套件依賴」，App 用的是本地套件，不受影響。macOS 上若有人跑 `swift test`，跑的是 -Onone，檢查只會更多。
- **`@testable`**：debug 組態仍帶 `-enable-testing`，`@testable import GameCore` 照常；#1694 的完整 tier（run 41370019390）全綠，golden、存檔、重播在 -O 下都一樣。
- **本機**：`swift build --build-tests -Xswiftc -warnings-as-errors` 在 39aaec0 從零建置 660 s 通過（4 核雲端容器）。**VERIFIED**。

新發現的是測試的「量尺」變鈍（L5-1）與本機改測試後重編變慢（L5-2），都不影響玩家。

### #1666、#1690（收購／機廠）

- `RealLineDepotSite.sites(of:)` 取代 `site(of:)`：三峽、淡海各只有一座，原路徑不變（`depotSite` 取 `beyond == nil` 那座，`depotEnds` 只收 `beyond` 有值的）。
- 兩座以上機廠：`depotsLaid` 依序收，`depot` 是第一座、`moreDepots` 是其餘；`build` 把全部蓋起來再一次 `setLineDepots`（以前每座各設一次會互相蓋掉，現在對）。`moreDepots` 是可選欄位，合成的 `Codable` 用 `decodeIfPresent`，舊紀錄照讀。
- 過夜車分配：有「端點外機廠」的線，每一端只放進那一端的機廠（`depotsLaid.firstIndex { $0.stop == stop }`），放不下的留在車站；沒有的線照舊放進「線旁機廠」。
- 文湖線（`trtc:BR`）在 `urbanLines` 裡**沒有上架**（#1666 自己拿掉那一列，等決策 535 第 1 點查好），所以 #1666 新增的多機廠路徑現在只有安坑（一座）走得到，玩家碰不到兩座的情形。
- #1690 的 `metro_runs.json`：安坑過夜 雙城 6＋十四張 1＝7，與改前 4＋1＋1＋1 相同；`tracks` 雙城 4 ≤ 輕軌端點上限 7；中間站不再過夜。`extract_metro_runs.py` 的 `DEPOT_ENDS` 改成 tuple，`depot_tracks` 用 `in`，一致。
- 安坑 4/182 班沒發（DEBUG-BATCH 量到）不是 #1690 的程式造成的推論沒有足夠證據，MISSRUN（#1579 登記）正在逐班查，本輪不重複。

### #1680、#1683、#1695（畫面）

- **#1680**：`run.look == .freight` 只在 `TrainMotion` 的 `line.isFreight` 設，客運線照舊；舊存檔的 R200CK 客運車照樣是 R200 頭＋莒光客車（有測試）。車廂索引在 1、2、≥3 節都沒有負索引或越界；`headOf` 借車頭，遠景用 `set-R200CKFar-head`；雜湊鎖多的 8 行對得上 `models()`；選單、`LineStaffing`、`RollingStockCatalog` 跟著過濾；汽笛兩個呼叫點都改了；`-screenshot-follow-freight` 在 `#if DEBUG` 裡，Release 碰不到。只有 L5-5、L5-6。
- **#1683**：站名在 full 縮放時往下移到擁擠圈與白邊之外，方向、單位、半徑都對；商店、擴建方塊、路線徽章跟著 `nameRect` 一起移。漏改的見 L5-3、L5-4。
- **#1695**：`Trail.points(from:to:)` 改從 `segment(at: a) + 1` 開始走，`segment` 回傳 `distances[i] ≤ a` 的段，之前的點距離都 ≤ a、本來就會被濾掉，結果相同。`mapCars` 在車頭超出 `trail` 起點時接 `aheadTrail`（同一個起點），兩者都夠長才走快路徑，否則退回 `cars(body:heading:count:track:)`（軌道盡頭、跳位）。`aheadTrail` 每 tick 建一次。沒有找到錯。

## 二、發現

### L5-1（P3）#1694：-O 之後，幾個「相對計時」測試的固定寬限 0.01 s 蓋過了比例，守不住原本要守的退步

- **位置**：`Tests/GameCoreTests/HolidayTests.swift:316`（`testAPlanAsksForTodaysHolidayOnce`：`taiwan < china * 1.5 + 0.01`）、`Tests/GameCoreTests/TrainTripLogTests.swift:243`（`testCreditingATripDoesNotWalkTheLog`：`long < short * 5 + 0.01`）。
- **問題**：兩個都寫「比例＋10 ms 寬限」。debug 時量到的時間是幾十到上百 ms，寬限可以忽略；-O 之後同一段只要幾 ms，寬限變成主角。
- **量到的**（39aaec0，Linux 4 核，臨時 print，各跑 3 次）：
  - Holiday：台灣 9.2–10.0 ms、中國 8.7–9.2 ms。斷言變成「台灣 < 約 23.5 ms」，也就是台灣慢到中國的 **2.5 倍**仍然綠（原意是 1.5 倍）。
  - TrainTripLog：short 0.10 ms、long 1.64–1.94 ms，**比例已經 17 倍**，只是因為 10 ms 寬限才綠。這 17 倍主要是 `var world = world` 第一次寫入時複製 21,000 筆紀錄（copy-on-write，一次性），不是每次記帳都走整個紀錄；但斷言現在等於「long < 10 ms」，不再量比例。真的退步成每次走整個紀錄（2,000 次 × 21,000 筆）估計仍會超過 10 ms，所以還抓得到大退步，抓不到中等的。
- **玩家看到**：無。只是 CI 少一道效能防線。
- **其他計時測試**：`DeadlockSearchCostTests`（`search < layout * 5`，無寬限）、`PassengerPlanKeyTests`（`later < first`，無寬限）、`ContinuousTrackTests`（只印不斷言）不受影響。
- **建議**：把寬限改成比例（例如 `max(short, 0.001) * 5`），或把迴圈次數放大 10 倍讓 -O 下也有幾十 ms；TrainTripLog 先暖一次（先做一次寫入觸發複製）再計時。只改測試。

### L5-2（P3）#1694：本機改一個 GameCoreTests 檔，重編要 3 分多（只改註解也是）

- **量到的**（39aaec0，Linux 4 核）：在 `HolidayTests.swift` 末尾加一行註解後 `swift build --build-tests`：**201.7 s**（user 6 分 15 秒）；同一個建置改兩個 GameCoreTests 檔（加 print）是 10 分 14 秒（user 26 分）。改一個 GamePresentationTests 檔（-Onone）只要 44 s。-O 的 GameCoreTests 看起來每次都重編大半個模組。
- **影響**：只有雲端 session 的本機迴圈（CLAUDE.md「改了套件先跑快速檢查」）；CI 每次從零建置，決策 544 已算進去。改 GameCore 的 session 每改一次測試要多等幾分鐘。debug 下同樣的改動多快，本輪沒有切回 -Onone 對照（**UNVERIFIED**）。
- **建議**：決策 544 的「開發」一行補上這個數字；要反覆改 GameCore 測試的 session 可本機暫時拿掉兩行 `swiftSettings`（決策 544 已寫逐行除錯時可這樣做），提交前恢復。

### L5-3（P3）#1683：標籤避讓用的站名框沒跟著往下移，放大時泡泡、票價標籤、站牌卡片會蓋到站名

- **位置**：`Sources/GamePresentation/MapLabelPlacement.swift:46-48`（`nameBox`：`y = station.y + radius + 4`，高 15）。
- **問題**：#1683 讓 `drawStationName` 從 `MapProblems.nameTop(stationRadius:)`＝`radius + max(4.5, 0.35·radius) + 4` 開始畫，`nameBox` 還用舊的 `radius + 4`。半徑 40 時估的框在 44–59、實際站名在 58 起；半徑 80 時框在 84–99、站名在 112 起，**完全錯開**。`obstacles(...)` 拿這個框給警示泡泡（`placeBubbles`）、票價標籤（`MapLabelPlacement:223`）、站牌卡片（`MapStationTagView` 的 `keepingOff`）避讓，所以它們會被放到「以為空著」、其實是站名的位置。這正是決策 477 要避免的。
- **玩家看到**：放大地圖時，警示泡泡或票價標籤蓋住鄰站站名的下半或整個站名。只是外觀。
- **驗證**（Linux，臨時測試 `Tests/GamePresentationTests/L5ReviewProbeTests.swift`，量完刪掉）：對半徑 5、10、20、40、80 斷言 `nameBox(...).minY == MapProblems.nameTop(stationRadius:)`，五個都紅（9 vs 13.5、14 vs 18.5、24 vs 31、44 vs 58、84 vs 112）。**VERIFIED**。
- **建議修法**：`nameBox` 的 y 改用 `station.y + MapProblems.nameTop(stationRadius: radius)`；上面的測試當回歸測試，再加一個鄰站放在泡泡候選正下方、選出的位置不和實際站名重疊。只動 GamePresentation。決策 482 的分級屬「既有畫面的小改」，修的 session 自己截圖驗收。

### L5-4（P3）#1683：中縮放仍然是擁擠圈壓著站名（PR 說每個縮放都清開）

- **位置**：`RailwayGameApp/Views/MapArt.swift:2383/2387`（`drawOverviewNames`：站名在 `radius + 2`）。
- **問題**：`drawStationProblems` 在 `MapProblems.level == .medium` 也畫擁擠圈（只排除 `.hidden`），這時 `projection.detail != .full`，站名走 overview 這條路，沒有改。半徑 5 時圈 9.5、白邊到 12，站名從 7 開始。
- **玩家看到**：拉遠到中縮放，擁擠站的圈蓋住站名上緣。#1683 之前就這樣，不是退步，只是沒修完。
- **驗證**：讀程式（App 端，Linux 測不到），**UNVERIFIED**。修法可把 overview 的站名偏移也抽成 `MapProblems` 的函式，照 L5-3 的方式測。

### L5-5（P3）#1680：`Map3DTrainSetTests` 裡貨運車頭的長度與三角形數檢查永遠跑不到

- **位置**：`Tests/GamePresentationTests/Map3DTrainSetTests.swift`（`name == set.headName && ["FREIGHT", "FREIGHTFar"]` 的 20.0...20.02 長度檢查與三角形數分支）。
- **問題**：`headOf != nil` 時 `models()` 不放車頭，迴圈遇不到這個名字。不影響遊戲，只是以為有測到。
- **建議**：刪掉那個分支，或改測借來的 `set-R200CK-head`。

### L5-6（P3）#1680：模型包每次建構都白做一次 R200 車頭

- **位置**：`Sources/GamePresentation/Map3DTrainSets.swift:593-599`（`freight(far:)`）。
- **問題**：閉包每次都算 `litLenses(Map3DR200.model(far:))`（近景 12,702、遠景 5,098 三角形），因為 `headOf` 的關係 `models()` 直接丟掉。畫面不受影響，模型包建構多花一點時間。沒有量。
- **建議**：讓 `Cars.head` 可以是空的，或在 `headOf` 有值時不建。

### L5-7（P3）#1680／#1683：站牌卡片更常蓋到自己那站的站名

- **位置**：`MapLabelPlacement.stationTag`：第一個候選固定在站點下方 34 點，只避開泡泡、不避開站名。
- **問題**：#1683 把站名往下移後，半徑約大於 10.5 就會蓋到被選站自己的站名（以前約 15）。若本來就允許卡片蓋自己那站的站名，可以忽略。讀程式推的，**UNVERIFIED**。

### 沒列的

- #1666／#1690：有「端點外機廠」的線，機廠放不下時沒有「不帶機廠」的退路（`laidOffer` 的 `sites.allSatisfy { $0.beyond == nil }`），所以玩家若在安坑機廠的位置自己蓋了東西，#1690 之後買不了安坑輕軌（之前可以）。這是決策 489 的既定做法（不帶機廠時雙城放不下 6 列），而且安坑舊資料本來就把車停在中間站；不列。
- #1666：同一條線同時有「線旁」與「端點外」機廠時，`room` 只看端點外的，線旁那座不收中間站的車。現在沒有這種線，潛在；不列。
- #1694：`.github/workflows/ci.yml` build job 逾時 20 → 30 分，合理（本機從零 660 s）。
- `Sources/GameCore/Railway/TrackSections.swift:394` 的 `b + divisor / 2` 在 `b` 已溢位時仍可能陷阱：本段沒有改到，不在範圍，記在這裡給下一輪。

## 三、驗證

Linux、Swift 6.4.0、`main` 39aaec0（含 #1694 的 -O）：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（通過，從零 660 s）。
- `swift test --skip-build --filter` `TrainTripLogTests`、`HolidayTests`、`PassengerPlanKeyTests/testAManyStationNetworkKeepsItsPlanBetweenCalls`、`DeadlockSearchCostTests/testTheSearchDoesNotWorkTheLineOutAgainForEverySpare`：**VERIFIED**（都通過）。
- L5-1 的秒數：臨時 print，各跑 3 次，量完還原。**VERIFIED**。
- L5-2 的重編時間：本機 `time swift build --build-tests`，量完還原。**VERIFIED**（只有 -O 這一邊）。
- L5-3：臨時測試，五個半徑都紅，量完刪掉。**VERIFIED**。
- L5-4～L5-7：讀程式（L5-5～L5-7 由子代理讀、本 session 重讀），**UNVERIFIED**（沒有 Simulator）。

## 四、下一步

- L5-3 值得順手修（只動 GamePresentation，附回歸測試），可以和 L5-4 一起派一個小 session；決策 482 屬既有畫面小改。
- L5-1、L5-2 交給下一輪 CIOPT 或 CIWEIGHT（#1579 已登記的 `claude/ci-weights-o`）順便處理：放大計時測試的量、在決策 544 補上本機重編的數字。
- L5-5～L5-7 記著，有空的 session 再處理。
- L4 的 L4-1（P2）、L4-2（環狀輕軌上線前必修）仍未修，派工時別漏。
- 下一輪審查從 #1696 起數。
