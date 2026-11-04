# 交接：PR #1760–#1802 審查（審查 L9）

派工單 REVIEW-L9（遊戲規劃第 46 任 session_01YGNNup5rvKQE2WYa4BP1cK，2026-11-04，112.1 發版前；第 46 任換手後報告交給第 47 任 session_01YGNNuncyse9G7nzdRW6S6p）：審查 L8（`PR1752_1759_REVIEW_HANDOFF.md`）之後已合併、改到程式的 PR。格式同 L8。

- Session：REVIEW-L9，branch `claude/review-l9`。
- 基準：`main` **bef26ca**（112.1，#1796 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff，和它的決策檔。
- 做法：GameCore（#1767、#1769、#1771、#1775、#1780、#1781 的 GameCore 部分、#1795）由本 session 自己讀。GamePresentation／App／CI 分給兩個子代理：一個審纜車與跟車，一個審其他 PR。子代理的每一點都附重現或程式位置；P1 由本 session 另寫 Linux 臨時測試重現。臨時測試量完就刪，沒有提交。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

`git log --first-parent 5464210..bef26ca` 逐一核對。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1767**（WENHUSIDE，決策 564，存檔 82：靠右行駛的線）、**#1769**（決策 570：班表線的死結判斷）、**#1771**（TYMCLIST3，決策 562：別擋跟車中的列車）、**#1775**（AUTOXO-2，決策 571 續：死結時准逆線）、**#1780**（決策 576，存檔 84：台灣節慶）、**#1781**（CABLE-1，決策 574，存檔 83：纜車）、**#1795**（TYMCLIST5，決策 577：忽略跟車列車的佔位） |
| GamePresentation | 纜車 #1781（展示層）、#1782、#1788、#1798；跟車與公車 #1783、#1784、#1797、#1802；其他 #1750、#1760、#1762、#1763、#1764、#1766、#1768、#1776、#1778、#1792、#1796 |
| App | #1779、#1790（SwiftUI 整理），以及上面各 PR 的畫面部分 |
| CI | #1774（`prune-merged-branches.yml`）、#1794（CIOPT-7，決策 582） |

沒有審的：
- 只改文件的 #1761、#1765、#1770、#1772、#1773、#1777、#1793、#1799、#1800、#1801。
- 只加 `tools/` 下研究腳本與預覽、遊戲沒有載入的 #1785、#1786、#1789、#1791。
- 只改 UI 測試的 #1787。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **1**：L9-1 |
| P2（下一版修） | **2**：L9-2、L9-3 |
| P3（記著） | **8**：L9-4 到 L9-11 |

- **L9-1** 會讓 112.1 的玩家在有列車的線上「升級為複線」一定失敗。這個功能 #1778 之前做得到，112.1 的更新說明（#1796）還特別介紹了它。
- 已在 2026-11-04 用 send_message 通報第 46 任，第 46 任已轉給第 47 任。
- GameCore 的 PR 沒有發現 P1 或 P2。

### GameCore

- **#1767**（決策 564，存檔 82）：
  - `keepsRight(toward:)`：一站只要有一條靠左的線停靠或以它為機廠，就回 false；沒有靠右的線時直接回 false，不影響舊世界。
  - `rightOfLeftmost(mirrored:)`：鏡像後取「不是最右邊的」那些路。
  - `isLeft` 的 `sameWaySlope`（1/256）只把幾乎同方向的切線改用弦來排；出路都在直行 1/16 以內，所以 `dot` 為正，不會反號。
  - `keepsRight` 的編碼「只寫 true」、讀時拒絕 false；複製線時一起帶過去。
  - 展示層的 `keepsRight(realLine:)` 把 `trtc` 對應到 `mrt`，和 `RealBranchLine.id` 的寫法（`dataSystem(of:)`）一致。
  - 存檔從 80 跳到 82：81 沒有用到，`SavedGame` 的說明寫的是「80 或 81 到 82」。
  - `KeepRightTests`、`SavedGameTests` 過。
- **#1769**（決策 570）：
  - 班表線的列車在 run 還沒到出發時刻前不算「在等」，和一般班次在出發時刻前不算一致。
  - `couldGo` 多看「線指定的路」是否空著：調度員確實會走那條路，所以只會讓死結判斷少誤報，不會多報。
  - `dueRunHasStarted` 和 `dueRunPreferredDeparture` 都照 `dueRuns` 的順序取第一個符合的 run，和 `dueRunDeparture` 一致。
  - `RunSendOutDeadlockTests` 過。
- **#1771**（決策 562）：
  - `followerCutOff`：只在閉塞開時看；候選列車站著的地方若在跟車列車的路上，或跟車列車在候選列車的路上，就不擋。
  - 折返或終點的那一站直接擋；其他情況模擬抵達後用 `followerWaitsInTheWay` 判斷。
  - 判斷沒找到反例。另記兩點：
    - 死結偵測看不到這種「擋」，見 **L9-4**。
    - 效能：每次 `reserving` 都對所有列車算 `authority` 與 `followingCover`，列車多時一 tick 是 O(n²)。決策 577 下一步 2 記的 `trafficPlan` 慢可能有關，這裡沒量，不列。
  - `FollowerCutOffTests` 過。
- **#1775**（決策 571 續）：
  - `counterflowRoute`：只用在死結解不開時，候選的路要比原路多不到 `detourAllowance`。
  - 用 `reserving` 整條拿下時，對向的車拿不到這段，不會迎面相撞。
  - 唯一的例外見 **L9-5**。
  - `CounterflowDeadlockTests`、`DoubleTrackDeadlockTests`（GameCore 部分）過。
- **#1780**（決策 576，存檔 84）：
  - 農曆表和決策 211 的表同一套回推（19 年週期）。抽查 2026 元宵 3/3 是第 62 天，和平溪挑戰原本的 `festivalDay` 相同；2042、2099 兩年也抽查了，都合理。
  - 遊戲每月 30 天，31 日併到 30 日（`Week.game` 的 `min(dd, 30)`），所以跨年 12/31 落在一年的最後一天（359），`starts(onDay:)` 不會因此跳到下一年。
  - 加成最大 1,200，在 `DemandEvent.isValid` 的 1–2,000 之內；天數 ≤ 9，在 30 之內，所以新事件不會讓存檔驗證失敗。
  - 地點驗證包括：數量不超過節慶種類數、不重複、在地圖內。
  - `setDemandEvents` 換種子時保留地點。
  - 舊存檔沒有地點，劇本節慶也照舊每年同一天，和決策寫的一致。
  - 站長提示中英都有；「人潮多在…」只在不是整天時出現。
  - `FestivalTests`、`SavedGameTests`（v84 fixture）過。
- **#1781**（決策 574，存檔 83，GameCore 部分）：
  - `isValid`：用 `&&` 短路，站數不到 2 時不會跑到 `stops.first!`。
  - 解碼前先擋站數上限。
  - 拆掉車站時，相接的纜車的 `transfer` 與接駁人數歸零，存檔的「transfer 是存在的車站」不會被打破。
  - `refreshCablewayTransfers` 不看有沒有土地需求，每次都重算。
  - 纜車先分走土地，被分走的格子公車不再算。
  - `settleCableways` 只在經營模式下寫帳：帳目的正負與 `breakdown` 合計，和 `ledgerEntryIsValid` 新加的一行一致。
  - 停駛日收入為 0、成本照付。停駛日鐵路那邊的接駁需求不變，這點決策 574 自己寫成「沒做」，不列。
  - `CablewayTests` 過。
- **#1795**（決策 577）：
  - 只在閉塞關時、死結裡、其他方法都不行時，才忽略「跟車列車的佔位」（claims）。
  - 列車實際拿下（held）的與 foul 的照擋。
  - 候選列車整條拿下，所以那些跟車列車之後拿不到這段，不會相撞。
  - `@inline(never)` 是為了 Wasm 的堆疊。
  - `FollowerClaimDeadlockTests` 過。

### GamePresentation

- **纜車**（#1781 展示層、#1782、#1788、#1798）：
  - `CablewayCabins`：一圈的秒數、去回兩段的拆分逐項對過；`loop` ≥ 120 s，不會除以 0；停駛時吊廂各半停在兩端站。
  - `Map3DCableways`：去線、回線與站內吊廂靠哪一側，在起站、中間站、終點站三種情況都一致。
  - `CablewayTool`：8 站上限、退回最後一站、貓空選項整條在地圖內才提供。
  - 新字串中英都有。
  - 每幀成本：貓空場景 debug build 約 1.1 ms，323 個 instance，可接受。
  - 只有 **L9-7**。
- **跟車與公車**（#1783、#1784、#1797、#1802）：
  - `followTrain` 與 `followBus` 互斥。
  - 跟車時，被跟的公車在街景關閉時也會畫；漸隱後接下一班，路線拆掉就放開。
  - 跨午夜同一班的 run 索引連續。
  - 串流的半徑設定不會讓區塊反覆重建。
  - 有 **L9-6**、**L9-8**。
- **#1778**（決策 572）：**L9-1**、**L9-3**。`placeBeside` 的方向判斷、車站面板走 `layLiftingTrains` 把列車放回、Codable 都對。
- **#1764**（決策 565）：**L9-2**。16 m 世界行為不變。
- 其他：
  - **#1766**：有 **L9-11**。JSON 索引檢查、`band` 二分搜尋都沒問題。
  - **#1796**：有 **L9-10**。
  - **#1760、#1762、#1763、#1768、#1750、#1776、#1792**：子代理逐一看過，沒發現問題。
  - #1763：被跟隨的柴油車停著或不在軌道上時，也會發出怠速聲（`ofDiesel` 低於 5 km/h 都播）。看起來是刻意的，不列。

### App

- **#1779**：有 **L9-9**。
- **#1790**：`ConcentricRectangle` 包在 iOS 26 的版本判斷裡，沒發現問題。
- 畫面都是 **UNVERIFIED**（沒有 macOS）。

### CI

- **#1794**（決策 582）：
  - iPad job 加了 `needs: ui-full-lane` 和 `!cancelled()`：pull request 上 `ui-full-lane` 被跳過時，iPad job 照樣會跑。
  - 夜間的「缺按鈕」檢查改用 `verify_missing_button=true` 觸發。
  - 沒有「永遠跑不到」或「該紅卻綠」的路徑。
- **#1774**：
  - 預設是 dry run，只在 `main` 跑。
  - 已合併與還開著的分支，比對沒有錯。
  - 分批刪除。

## 二、發現

### L9-1（P1）#1778：線上有列車時「升級為複線」一定失敗，預覽卻說可以

- **位置**：
  - `Sources/GamePresentation/TrackUpgrade.swift:305-320`：把站旁渡線併進 `.buildDoubleTrackChain` 的 `crossovers`。
  - `Sources/GamePresentation/StationCrossovers.swift:48-54`：`missingStationCrossovers(of:in:)` 先在草稿撤下所有列車。
  - `Sources/GamePresentation/PlayerCommand.swift:329-333`：執行時直接 `crossover.build`。
- **問題**：
  - 規劃站旁渡線時，列車都已從草稿撤下，所以算得出渡線。
  - 執行時卻沒有像車站面板的「加渡線」那樣走 `layLiftingTrains`，列車還在原位。
  - 站上的列車或它的進路擋住渡線，GameCore 拒絕，整個命令失敗。
  - 預覽的 `problem` 只看錢夠不夠，看不到這一點。
- **玩家看到**：
  - 營運中的單線按「升級為複線」，預覽寫「車站旁加 2 組渡線」，價錢也照常顯示。
  - 按下去失敗：「A train's route runs over that track. Wait for it to pass.」
  - 列車停在月台不會「通過」，等多久都一樣（子代理在第 0、7、20、45、90 分鐘試過）。
  - #1778 之前沒有站旁渡線，這一步做得到（子代理量過：同一個命令拿掉站旁渡線就成功）。
- **驗證**（Linux，main bef26ca，**VERIFIED**）：
  - 臨時測試，照 `OldStationCrossoverTests.upgradedStations`：4 km 單線，兩站各在端點內 500 m。
  - 先 `line(session)`，再 `plus(session, id, to: 1)` 加 1 列車，然後點軌道 `beginTrackUpgrade(.doubleTrack)`、`buildTrackUpgrade()`：

  | 規則 | 列車 | 預覽 `problem` | 結果 |
  | --- | --- | --- | --- |
  | 擬實 | 0 | nil | success（「Made the track double for NT$ 1,276,800…」） |
  | 擬實 | 1 | nil（note：「4 crossovers go in beside its stations」） | **failure**「A train's route runs over that track. Wait for it to pass.」 |
  | 一般（建線就自動放 1 列） | 1 | nil（note：「2 crossovers go in beside its stations」） | **failure**，同上 |

- **修法建議**（擇一）：
  - 執行時照車站面板走 `layLiftingTrains`，把列車撤下、蓋好、放回。
  - 規劃時不撤列車，被擋的站旁渡線就剔掉，並寫進說明，像兩端渡線的「trains in the way」那樣處理。
- **回歸測試**：在 `OldStationCrossoverTests` 照上面的步驟建線、加 1 列車後升級，斷言 `message?.kind == .success`，而且兩站的 `stationCrossoverOffer` 都是 nil（若選剔掉的修法，改成斷言說明文字寫出剔掉了哪些）。修前紅。

### L9-2（P2）#1764：EMU3000 等 20 m 以上的車停 4 節（80 m）月台，每次都被叫「減到 3 節」

- **位置**：
  - `Sources/GamePresentation/LineDispatchText.swift:157-171`：`whole = cars × carPitch` 與月台長比。
  - `Sources/GamePresentation/AutoService.swift:565`：自動排班依 `platformCarLength`（20 m）定節數。
- **問題**：月台工具說「4 節」，蓋的是 4 × 20 m = 80 m；EMU3000 的節距是 20.3 m，4 節共 81.2 m，最後一節伸出月台約 1.2 m。
- **玩家看到**：派車或自動排班後出現「列車比 West 的月台長，停站時最後一節會在月台外：把月台加長到 82 公尺，或把列車移出軌道、減到 3 節。」EMU100（20.1 m）、22 m 的車也一樣。旗艦車配預設月台是常見組合，提示會讓玩家以為要砍掉一節。
- **驗證**（子代理，Linux，**VERIFIED**）：
  - 設定：實景節距、4 節 80 m 月台、4 節 EMU3000，執行 `assignTrain`。
  - 結果：`ShortPlatformCall(needed: 5196, cars: 3, overhangs: true)`，訊息如上。
- **修法建議**（擇一，由修的人照五方決定）：
  - 超出不到半節（或一個固定容差）時不提示。
  - 月台工具與自動排班照線上車型的實際節距算長度。

### L9-3（P2）#1778：車站面板「加渡線」按鈕的「錢不夠」停在舊結果

- **位置**：`Sources/GamePresentation/StationCrossovers.swift:188-205`。`stationCrossoverDraft` 用 `commandRevision` 當 memo 的鍵，`shortfallText` 存在 offer 裡。
- **問題**：時間推進、收入入帳都不會改 `commandRevision`。
  - 錢不夠時按鈕灰掉，之後錢夠了，只要玩家沒下其他命令，按鈕就一直灰著。
  - 反過來，錢從夠變不夠（每日成本扣款）時，按鈕仍可按，按下去才被拒（GameCore 會擋，不會扣錯錢）。
- **驗證**：讀程式，子代理與本 session 都核對過 memo 的鍵；沒有寫測試。**可能**；修法是 memo 只存渡線與價錢，`problem` 每次用現在的餘額算。

### L9-4（P3）#1771：被 `followerCutOff` 擋住的列車，死結偵測看成「能走」

- **位置**：`Sources/GameCore/Railway/RouteReservation.swift:193-195`（`reserving` 回 `.held(by: follower)`）、`Sources/GameCore/Railway/Deadlock.swift` 的 `couldGo`（只看其他列車擋住的軌道）。
- **問題**：
  - `waitingRoute` 會把這種列車算成「在等」。
  - 但 `couldGo` 只問它的路有沒有被等待中的列車佔住，而跟車列車並沒有佔住那段，所以第一輪就把它移出等待名單，連帶讓其他等它的列車也被算成能走。
  - 若真的形成「候選列車等跟車列車、跟車列車等前車、前車等候選列車」的環，`deadlock(memo:)` 會回空：不會解，也不會顯示「互相卡住」。
- **驗證**：讀程式推的，沒有造出這種環。**可能**。修法方向：`couldGo` 對 `followerCutOff` 有回傳值的候選，把那列跟車列車當成擋住它的人。

### L9-5（P3）#1775：逆線解死結在閉塞開、照實際班表、路長超過 14 km 時只拿下一部分

- **位置**：`Sources/GameCore/World/GameWorld.swift`（`resolveDeadlock` 的逆線段，約 3750–3768 行）呼叫 `reserving(...)`。`reserving` 在 `blockSections` 與 `followsRealTimetable` 都成立、路長大於 `approachReach`（896,000，14 km）時改走 `reservingApproach`，只拿到 `approachLimit`（終點前 4 km 不拿）。
- **問題**：決策 571 續與 `counterflowRoute` 的說明都寫「只整條拿下，所以不會有車迎面而來」，但上述條件下，最後 4 km 沒拿。對向列車（那是它的正線）可以拿走這段，兩車在逆線上對頭，互相卡住。不會相撞，因為兩邊都靠佔位。
- **驗證**：讀程式推的。要同時滿足：死結、擬實（閉塞開）、實際班表的線、站間超過 14 km（高鐵等級）。罕見，**可能**。修法：逆線時傳一個參數跳過 `approachLimit`，或在 `counterflowRoute` 擋掉這種長度。

### L9-6（P3）#1783：「從車站看」停站時的可選判斷，和實際看的站不一致

- **位置**：`Sources/GamePresentation/Map3DFollow.swift:569-594`（`map3DStopAhead`、`map3DMetresToStopAhead`）、`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift` 的 `Map3DFollowBar.choices`（`stationOffered`）。
- **問題**：
  - 停站時，車站視角看的是**這一站**，但按鈕能不能選，看的是到**下一站**的直線距離（超過 12 km 就灰掉）。
  - 來回時刻表 `[1, 2, 1]` 停在最後一列時，`(stop + 1) % count` 繞回同一站，算出 0 m。
- **驗證**（子代理，Linux，**VERIFIED**，`ScreenshotScene.farStops` 的線）：
  - 停在站 2 時：`watches 2, ahead 1, metres 14000, offered false`。
  - 停在站 1 時：`watches 1, ahead 1, metres 0, offered true`。
  - 同一條 14 km 的線，一端可選、另一端不可選。
- **影響**：只是按鈕灰不灰、提前蓋哪一站。修法：停站時直接可選；找下一站時跳過同一站。

### L9-7（P3）#1782／#1798：轉角站的模型固定右轉 24°，和實際纜線方向不合

- **位置**：`Sources/GamePresentation/Map3DCableCar.swift:35`（`cornerAngle`）、`:305-320`（第二翼）；`Sources/GamePresentation/Map3DCableways.swift:91`（站只朝進站方向擺）。
- **問題**：照 `RealCableway.maokong` 的座標算，貓空的兩個轉角站實際約左轉 10°、右轉 80°。出站的纜線與吊廂會從站體牆面穿出。
- **驗證**：子代理讀程式加手算方位角，沒有截圖。純外觀，下一輪 3D 纜車（決策 575 下一步）一起改：依出站方向轉第二翼，或依角度選模型。

### L9-8（P3）#1784：公車的「車窗」視角朝左，台灣道路靠右行駛，看到的是對向車道

- **位置**：`Sources/GamePresentation/Map3DFollow.swift` 的 window 分支（`left = (forward.z, 0, -forward.x)`）；`Map3DBusFollowBar` 的選項只排除 `.station`。
- **問題**：決策 578 選左窗，理由是列車靠左行駛；公車沿用同一套，但公車靠右，左窗看出去是中線與對向來車，不是街邊。
- **驗證**：讀程式；設計沒顧到公車。修法：公車用右窗（決策 578 下一步本來就有「車窗選左右」）。

### L9-9（P3）#1779：集章本第 100 頁起頁碼被截成兩位

- **位置**：`RailwayGameApp/Views/StationStampPassportView.swift:166`，`.number.precision(.integerLength(2))`。
- **問題**：`integerLength(2)` 是「剛好兩位」：100 會顯示「00」，123 顯示「23」（原本的 `%02d` 會顯示「100」）。
- **驗證**：子代理在 Linux 的 Foundation 跑過（**VERIFIED**，iOS 上 UNVERIFIED）。要 800 枚章才遇得到。修法：`.integerLength(2...)`。

### L9-10（P3）#1796：更新說明的英文按鈕名稱和 App 不同

- **位置**：`Sources/GamePresentation/WhatsNew.swift:50`、`:62`。
- **問題**：
  - 說明寫「Upgrade to Double Track」，App 的按鈕是「Make double track」。
  - 說明寫「Follow Bus」，按鈕是「Follow a Bus」（`ControlPanel.swift:634`）。
  - 中文沒有這個問題。
- 112.1 已發，下一版的說明照按鈕寫即可。

### L9-11（P3）#1766：英文介面的公車站名候選只有中文

- **位置**：#1766 的站名候選（`english: nil` 的地標）。
- **問題**：英文遊戲裡選了候選，站名就成了中文。
- **驗證**：子代理讀程式。修法：沒有英文名的候選在英文介面不列，或用羅馬拼音。

## 三、驗證紀錄

- `swift build --build-tests`（Linux，Swift 6.4）：成功。
- `swift test --skip-build`（Linux，**VERIFIED**）：
  - 本 session：`KeepRightTests|RunSendOutDeadlockTests|FollowerCutOffTests|CounterflowDeadlockTests|CablewayTests|FestivalTests|FollowerClaimDeadlockTests|SavedGameTests`，69 個全過。
  - 子代理：`CablewayToolTests`、`Map3DCablewaysTests`、`Map3DCableCarTests`、`FollowBusTests`、`FollowBusVisibleTests`、`Map3DFollowViewsTests`、`Map3DFollowTests`，全過。
- L9-1 由本 session 另寫臨時測試重現；L9-2、L9-6、L9-9 由子代理重現。臨時測試都已刪除。
- 畫面、iOS 行為：**UNVERIFIED**（沒有 macOS，沒跑 iOS workflow）。

## 四、下一輪

REVIEW-L10 從 **#1803** 起（`main` bef26ca 之後）。L9-1 的修正 PR 合併後，下一輪要審它的修法與回歸測試。
