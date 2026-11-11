# 交接：PR #2032–#2056 審查（審查 L17，0.6.0 (125) 發版後）

派工單 REVIEW-L17（遊戲規劃第 61 任 session_01YGNNup5PejVbKYpnZigyeN，2026-11-11）。規則是「每次發版後派一輪」。這一輪審 L16（`PR1986_2031_REVIEW_HANDOFF.md`）之後合進 main 的 PR，格式同 L16。

- Session：REVIEW-L17（session_01YGNNuqL6Ds37AkbvkMvP6E），branch `claude/review-l17`。
- 基準：`main` **3a2fbcc**（#2055 的合併，也是 0.6.0 (125) 的 commit）。每個 PR 都讀 merge commit 對 first parent 的 diff，也讀它的決策檔。
- 範圍：`git log --first-parent 3313197..3a2fbcc`，25 個合併（#2032–#2056）。全部都在 125 這一版裡。
- 點數（照 HANDOFF §1「多久審查一次」）：**14 點**。
  - GameCore 2 點：#2046、#2051。
  - 1 點（10 個）：#2035、#2037、#2038、#2039、#2040、#2042、#2043、#2047、#2048、#2056。
  - 0 點：#2054（報告測試與文件）；其餘 12 個只改文件（#2032、#2033、#2034、#2036、#2041、#2044、#2045、#2049、#2050、#2052、#2053、#2055）。
- 分工：
  - 本 session 自己讀 GameCore 的 #2046、#2051，重跑它們的測試，並用暫時測試重現 L17-1。
  - 其餘分三組交給子代理讀程式、跑既有測試：估算與文字（#2043、#2042、#2037）；手動駕駛與文湖線（#2047、#2039）；App 與 CI（#2035、#2038、#2040、#2048、#2054、#2056）。子代理的 P2 由本 session 對過程式（標「核對」）。
- 存檔版本、決策編號、golden schema 都**不動**；只改文件。

## 〇、範圍

| PR | 內容 | 點數 |
| --- | --- | --- |
| **#2046** | MUSEUM，決策 684：鐵道博物館（GameCore，存檔 86 → 87） | 2 |
| **#2051** | PLATFORM-EXTEND，決策 687：月台不拆除直接加長（GameCore） | 2 |
| #2043 | 決策 682：買車前的損益估算 | 1 |
| #2042 | 決策 683：城市稱號 | 1 |
| #2047 | 決策 686：手動駕駛 | 1 |
| #2039 | 決策 678：文湖線大直—松山機場走地下 | 1 |
| #2038 | CIOPT-7，決策 679 | 1 |
| #2037 | FIX-L16：L16-1、L16-2 | 1 |
| #2035 | 決策 677：Liquid Glass | 1 |
| #2040 | 決策 680：iOS 26 的 App 圖示 | 1 |
| #2048 | 決策 685：model-look 技能與追分站 | 1 |
| #2056 | TUTORIAL-CAPSULE，決策 688：教學膠囊不再搬家 | 1 |
| #2054 | TYMC-YIELD，決策 681：讓路次數的報告測試 | 0 |
| 其餘 12 個 | HANDOFF、健檢、優先表、研究、L16 本身、125 的說明 | 0 |

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（當天修） | **0** |
| P2（該修） | **5**：L17-1 到 L17-5 |
| P3（記著） | **19**：L17-6 到 L17-24 |

- 沒有 P1。125 已發，沒有東西要撤回；存檔讀得回，沒有發現死結或決定性的問題。
- **#2046（GameCore）的規則與存檔站得住**，但有一個玩家走得到的洞：沒有觀光的世界（挑戰、教學）蓋得起博物館，卻永遠沒有遊客、展品也不更新（L17-1，已重現）。
  - 存檔：新種類與 `exhibits` 的驗證（只有博物館能有、照圖鑑順序所以不重複、最多一座）都在 `placedBuildingProblem`；v87 fixture 與往返測試有跑（VERIFIED）。
  - 決定性：展品用 `Set` 收集後照 `row` 排序，沒有字典順序；收集在午夜 `closeTourismDay` 的最後，批次與逐分同一個點。
  - 失敗原子性：第二座在動手前就丟 `museumAlreadyBuilt`；PR 的測試比對 `world == before`。
- **#2051（GameCore）的改法站得住**：
  - 檢查全部在動手前；`replacePlatform` 的插入位置與 `addPlatform` 同一寫法；區間重切與侵限重算和加月台、拆月台同一條路。
  - GameCore 裡存著 `TrackPlatform` 值的只有 `network.platforms` 與 `LineRoutePreference.platform`（路線與停站模式各一份），兩份都跟著改了（grep 過 `Sources/GameCore`）。
  - `trackPlatformRoom` 的二分搜尋靠「一條邊的高度不回頭」；就算不成立，`extendTrackPlatform` 自己還會用 `isValidPlatform` 再驗一次，最壞是選單上一個選項被拒絕。
  - 留下的是幾件小事（L17-7）。
- **CI 規則沒有被繞過**：#2038、#2056 沒有跳過測試、沒有放寬逾時；但 #2056 新加的「膠囊 5 秒不動」斷言在慢模擬器上會假紅，而且它在 PR gate 裡（L17-4）。
- **L16-1、L16-2 確實修到**（#2037，第三節的表）。

## 二、發現

### L17-1（P2，已重現）#2046：沒有觀光的世界蓋得起博物館，但它永遠沒有遊客，展品也不更新

- **位置**：`Sources/GameCore/Passenger/Tourism.swift:1110`（`closeTourismDay` 的 `guard var tourism`）、`:1146`（`collectMuseumExhibits()` 在這個 guard 後面）、`:776`（`companySights()` 沒有觀光就回空）；`RailwayGameApp/Views/ControlPanel.swift:929`（建築清單列出 `PlacedBuildingKind.allCases`，不看有沒有觀光）；`Sources/GamePresentation/TourismText.swift`（博物館那一列只在 `tourism != nil` 時才有）。
- **問題**：`tourism == nil` 的世界裡：
  - `placeBuilding(.railwayMuseum)` 照樣成功、照樣收錢；
  - 博物館不是景點（`companySight(of:)` 回 nil），遊客永遠 0，觀光面板沒有它那一列；
  - 午夜的 `collectMuseumExhibits()` 走不到，之後買的車種永遠不進館；
  - 每天照付人事費，蓋館當時收進的展品每件每天 NT$1,000 也照付。
- **哪些世界**：`GameWorld.newGame(challenge:)`（`Scenarios.swift:177`，沙盒目標、歷史挑戰、教學、每週挑戰）、劉銘傳挑戰（`LiuMingchuanChallenge.swift:203`）、`NewGame.swift:295` 的量測用世界。一般新局、平溪、支線挑戰、真實地圖有觀光，不受影響。
- **為什麼是問題**：卡片說「車種越多，搭你的車來參觀、買門票的人越多」，玩家花了約 NT$650 萬卻只有支出。廟與夜市從決策 361 起就有同一個洞（沒有觀光時也是 0 人、只付人事費）；博物館多了「展品不更新」與「展品維護費」，而且 125 的說明主打它。
- **重現**（本 session 的暫時測試，在 3a2fbcc 上紅，已刪）：`RailwayMuseumTests.world()` 拿掉 `setTourism` 那一行；先買一列 A 型車、蓋博物館、再買一列 C 型車，走 3 天。結果：`exhibits == ["A"]`（預期 `["A", "C"]`）、`visitors == 0`、`books.totalSales == 0`、`books.totalCost == 432,711` 分、`companySight(of:) == nil`。
- **修法**（擇一或都做）：
  - 畫面：沒有觀光的世界，建築清單不列景點類（廟、夜市、博物館），或卡片上說「這張地圖沒有觀光客」並擋下。這一半不動 GameCore。
  - GameCore：`collectMuseumExhibits()` 移到 `guard var tourism` 之前（展品是公司的紀錄，和有沒有觀光無關）；要不要在 `placeBuilding` 對沒有觀光的世界丟 `tourismNotEnabled` 是設計決定（會動到廟與夜市既有的行為）。
- **大小**：小。只改畫面就不動 GameCore。

### L17-2（P2，核對）#2043：「票收 —」會卡住最多一個遊戲小時

- **位置**：`Sources/GamePresentation/LinePanelMemo.swift:193-205`；`Sources/GamePresentation/TrainPurchaseEstimate.swift:311-312`。
- **問題**：估算的 memo 鍵是（指令修訂、購買參數、遊戲小時），`.unknown`（乘客計畫還沒建）的結果也照存。乘客計畫是 tick 建的，tick 不加指令修訂，所以同一個遊戲小時內不會重算。
- **走得到的路**：遊戲在跑時畫一條新線（`createLine` 清掉計畫，下一個 tick 前第一次繪製就存下 `.unknown`）；或暫停中建線、開面板、解除暫停（`setSpeed` 是指令，memo 清空後馬上重畫，還沒 tick）。
- **影響**：畫面寫「時間開始走以後才算得出乘客」，但時間已經在走：60× 是 1 分鐘，10× 是 6 分鐘，1× 是 1 小時。換一個班距（新鍵）立刻有票收，切回原選項又變回「—」。決策 682 寫的是「一個 tick 就有」。
- **重現草稿**（未跑）：`GameSession(world: 兩鎮一線)`，`memo.purchaseEstimate(...)` 得 `.unknown`；世界前進 1 tick（不經指令）；再讀一次，預期有票收，實際仍是 `.unknown`。
- **修法**：`.unknown` 不存；或把「計畫建好了沒」放進鍵。`testThePanelKeepsItForTheHour` 補「`.unknown` 之後會變」「跨小時重算」。
- **附帶**：計畫存在但這條線沒有任何乘客段時，也顯示同一句「時間開始走以後…」，理由不對。
- **大小**：小。不動 GameCore。

### L17-3（P2，未重現）#2043：最近 7 天內車隊或班距變過，估算會偏

- **位置**：`Sources/GamePresentation/TrainPurchaseEstimate.swift:316-332`。
- **問題**：「現在」取最近 7 個完整日的帳，`modelBefore` 卻用目前的車隊；估算是「歷史平均＋（modelAfter − modelBefore）」，只有那幾天的車隊和現在一樣才成立。今天（還沒結算）買的車完全不在歷史裡。
- **例子**：1 列車跑了 3 天，今天買 2 列，馬上再看下一個選項的估算：「現在的成本」是 1 列時的數字，剛買那 2 列的成本整個漏掉，「比現在多／少」與回本天數跟著錯，之後 7 天逐日才收斂。分次加車是很常見的玩法。
- **決策沒寫**：決策 682「誤差從哪裡來」沒有這一項；測試的 3% 斷言只涵蓋歷史車隊等於現在車隊。
- **修法**：歷史日的發車數平均和 `modelBefore` 的發車數差超過 10–15% 時，不用歷史，改用模型算「現在」（`historyDays` 設 0）；至少寫進決策的誤差清單。
- **大小**：小到中。不動 GameCore。

### L17-4（P2，核對，未跑）#2056：「膠囊 5 秒不動」的斷言在慢模擬器上會假紅，而且在 PR gate 裡

- **位置**：`RailwayGameApp/UITests/TutorialUITests.swift:141-149`（斷言在 `:146`）；`.github/workflows/ios-build.yml:640`（gate 清單）；`Sources/GamePresentation/Tutorial.swift:461`（`skipOfferSeconds`）；`RailwayGameApp/Views/TutorialOverlay.swift:783`。
- **問題**：
  - 迴圈是 10 次 ×（睡 0.5 秒＋`pill.exists`＋`pill.frame`），不是 5 秒；慢 runner 上一次 XCUI 查詢可到 1–2 秒（同檔註解記過一次 snapshot 12 秒），整段可拖到 15–25 秒。
  - 每一步的卡片出現 20 秒後會多一顆「跳過這一步」，膠囊的 trailing padding 從 12 變 8、旁邊多一顆鈕，`tutorial.unfold` 的 frame 一定變。
  - 斷言比的是整個 frame 相等，所以超過 20 秒就報「The folded card moved」，膠囊其實沒有搬家。
- **為什麼是問題**：這支在 PR gate，紅了會擋每一個動到 App 的 PR；workflow 自己記過第一支測試在慢模擬器跑 7.5 分鐘。它正是為了修偶發紅（L16-3）加的，卻帶進另一種偶發紅。
- **重現**：要 macOS。把 `skipOfferSeconds` 暫時改成 3 應該必紅（未跑）。
- **修法**：迴圈改用期限（`Date() < start + 5`）；只比 `frame.origin`；或 `tutorial.skipStep` 出現就停止比較。
- **大小**：小。

### L17-5（P2，核對）#2047：暫停中按「駕駛」不會降到 1×，駕駛中也能調回 10×

- **位置**：`Sources/GamePresentation/ManualDriveSession.swift:69`、`:117`。
- **問題**：`startManualDrive` 用 `world.clock.speed.tenthsPerTick > x1` 判斷；暫停時是 0，所以不降速，恢復後回到原本的 10×。駕駛中倍速選單也照樣給 10×。`stepManualDrive` 就以 10 倍的時間推進。
- **影響**：把手的反應與煞車距離在 10× 下幾乎抓不住，評分沒有意義。決策 686 寫「開始駕駛時高於 1× 就降到 1×」，這條路沒做到。
- **重現**（未跑）：`session.setSpeed(.x10)` → 暫停 → `startManualDrive()` → 恢復，`world.clock.speed` 仍是 `.x10`。`testStartingSlowsTheGame…` 只測沒暫停的 10×。
- **修法**：用恢復後會跑的速度（`runningSpeed`）判斷；駕駛中倍速選單只留暫停與 1×，或 `stepManualDrive` 把倍率夾到 1。
- **大小**：小。不動 GameCore。

### L17-6（P3）#2046 的小事

1. 當天買、當天賣的車種不進館：展品只在午夜從「現在擁有」收（`Tourism.swift:809-814`）。決策寫「擁有過的每一種」，卡片也這樣說。玩家很少這樣做，記著。
2. 觀光面板的博物館那一列只有今天與昨天；今年、去年沒有記（`TourismText.swift` 的 `thisYear: 0`）。決策 8 有寫。
3. 3D 用 48 m 百貨的低樓層站在 64 m 的地上（`Map3DPlacedBuildingKits.swift:262`），四周會空一圈；決策已列為第二步。
4. 沒有「沒有觀光的世界」的測試（L17-1 就是這個洞）。

### L17-7（P3）#2051 的小事

1. **常常沒有空間（未量）**：一座月台只在一條邊上。用「月台軌道」工具蓋的站，月台所在的邊兩端就是轉轍器；玩家最需要加長的站，選單很可能只有「沒有空間加長」。決策把它列為限制 1，但沒有量過示範地圖與真實路線上有多少月台加得了。建議健檢數一次；多數加不了的話，125 說明裡「月台可以直接加長」會讓玩家失望。
2. **每次重畫都重算**：`StationPanel.swift:824` 每座月台每次 body 都呼叫 `platformExtensionMenuChoices`，裡面對每個節數各算一次 `trackPlatformRoom`（最多 15 次，每次兩個二分搜尋）。`TickStable` 只省了畫，沒省算。比照 `platformTrackMenuMemo`（`GameSession.swift:222`）照指令修訂記起來。大站、高倍速下才看得出來，未量。
3. **沒有測試的路**：沒有行車管制時，正要進站（還沒停）的列車遇到月台加長，之後照舊到站（決策「列車正在月台上時」第一點的後半）；`trackPlatformRoom` 在有坡的邊上「另一端」的結果。
4. 成對的島式月台要各按一次（決策限制 4）；面板沒有提示另一座還沒加長。

### L17-8（P3，未量）#2043：估算在主執行緒重找軌道

- `TrainPurchaseEstimate.swift:296-299`：已有車的路線，三個時段各叫一次 `lineHeadway(id, at:)`，每次都重開整條線的行程（行車管制開著時還有逐站的容量搜尋）；另外每次跑整份計畫的 `plannedPassengerLegFlows()`。`LinePanelMemo.prepare` 的背景預算不含估算。
- 面板開在加開選項時，每個遊戲小時在 body 裡做一次：600× 是每 6 秒。`LinePanelMemo` 的註解記過這類搜尋在高鐵示範與文湖線是數百毫秒。
- 修法：三個時段的現行班距每個指令算一次存進 memo；大線放到背景。量到會卡就升 P2。

### L17-9（P3）#2043：兩個算術上的偏差

- `TrainPurchaseEstimate.swift:304-306`：`1_000 / headway` 每分鐘截斷一次。班距 3–30 分誤差不到 1.5%；150 分少 10%，400 分少 20%，超過 1,000 分變 0。長途真實路線只有 1–2 列車時會遇到。
- `:298`：「現在」用計畫班距（`lineHeadway`），車不夠時不會拉長（`lineRunningHeadway` 才會）。面板同時顯示「補齊 N 列」時，現在的發車數與成本偏高，估算偏低。

### L17-10（P3，核對）#2042：升到「城市」那一級時，新聞是「城市成長為城市。」

- `Sources/GamePresentation/CityTitle.swift:233-235`：英文 "The city has grown into a city."。50 萬人這一級是造鎮挑戰會經過的；低的級別是「城市成長為村莊」。
- 修法：主詞改成「這裡」或地圖名（"Your map is now a city"），兩種語言一起改。

### L17-11（P3）#2042：面板開著時，稱號當天不跟著指令更新

- `RailwayGameApp/Views/GoalsPanel.swift:84-87` 的 `.task(id: today)`：邊走邊讀土地的地圖，蓋站或買地會馬上多幾十萬居民，面板要到隔天或重開才變。id 加上指令修訂。
- `CityTitle.countsAlongTheLines` 現在沒有人讀，是決策第 6 點拿掉文字後留下的。

### L17-12（P3）#2037：內灣測試的門檻是寫死的，餘裕 1.7%

`ChallengeStoryNeiwanTests.testTheAdviceFitsTheGoal` 的 30,502、33,096 是寫死的；`neiwan.9` 的門檻 30,000 對兩節車第 7 天的 30,502。之後票價、需求、容量一動，測試照樣綠，兩節車卻可能再也聽不到那一句。改這些規則的 PR 要重跑 `NEIWAN_REPORT=1`（決策 671 的修正段已寫）。

### L17-13（P3）#2047：結束駕駛不還原速度；決策說「不送任何指令」不精確

- `ManualDriveSession.swift:69`、`:78-84`：開始時 10× 降到 1×，結束不還原，遊戲無聲地留在 1×。決策沒寫要不要還原。
- 降速走的是 `setSpeed`，是 `GameWorld` 的指令、會進指令紀錄；不違反架構規則，但決策 686「不送任何指令、不改世界」要補一句。
- 其他都是暫態：`manualDriveRun` 不寫回世界、不進存檔；PR 的測試拿沒人駕駛的 session 對照時鐘、車頭位置與 `execution`，相等。

### L17-14（P3）#2047：過站或逾時後，行駛聲停不下來

`ManualDrive.swift:273-277`、`:300-306`；`ManualDriveSession.swift:139-142`。`finish(.passed)`、`finish(.timedOut)` 不把速度歸零，成績卡顯示「過站了」、車不動，馬達聲一直響到玩家按「回到列車」。`isOver` 時回報靜止。`testTheMotorsAreHeardAsTheHandleStands` 沒測結束之後。

### L17-15（P3）#2047：「駕駛」鈕會亮，但有些車永遠停在「離站後由你駕駛」

`ManualDriveSession.swift:28-31` 對 `:18-24`。鈕只要求有班表或有路線；接手要 `.travellingToStop`、有行駛曲線、剩 300 m 以上。被擋車後丟掉曲線而停在站間的車、站距都不到 300 m 的線、收班後停在站上的車，等待沒有期限也沒有說明，玩家只能自己按 ✕。等太久就換一句話或自動結束。

### L17-16（P3，未重現）#2047：接手那一刻的三個位置問題

1. `ManualDriveSession.swift:21-23`、`:44`：剩餘距離用曲線算，不是列車實際剩下的路。照真實時刻表、沒開行控、被前車擋住的那一分鐘內接手，停車點會落在月台前。
2. `ManualDriveTrack.swift:66-78`：行駛中接手，畫面上的車會往前跳到世界最新的整秒位置，100 km/h 時最多約 28 m。
3. `ManualDriveTrack.swift:60-62`：終點站停車點後不到 50 m 就是軌道盡頭時，車畫在盡頭不動，速度表與聲音照跑，幾秒後才判過站。
- 都只影響畫面與評分，世界不受影響。

### L17-17（P3）#2047：測試比決策少；一個用詞

- 沒測到的：行駛中接手（玩家最常走的路）、駕駛中列車入庫或被賣而自動結束、暫停時不推進、單格 0.25 秒上限與 10× 倍率、線被刪。
- `ManualDrive.swift:445-446`：按鈕中文是「加速」，VoiceOver 是「動力 n 段」，同一支把手兩個詞。

### L17-18（P3，未驗證）#2039：水下段沒有退回橋的路

`RealWorldDemoGround.swift:761-786`：改前是「先試橋，到不了才走水下」；現在真實隧道上方的水一律走水下，求不出坡度時整條線被拒買（「坡度鋪不上去」）。測試只涵蓋兩個原點（台北開局、線中心）；決策自己記過第一版在以線為中心的地圖上結果不同。加一支報告測試掃幾個開局原點，或全失敗時退回舊做法再求一次。

### L17-19（P3）#2039：新價格沒有測試釘住；舊存檔拿不到隧道

- 決策 678 的建造費 7,707,570,650（+6.5%）、其他 14 條線逐點不變，只在決策表裡；`WenhuUndergroundTests` 沒有價格的斷言。
- 已買文湖線的舊存檔不會重鋪（決策已寫、列為下一步）；125 的說明若寫「文湖線走地下」，要說是新買的才有。

### L17-20（P3，未驗證：要實機）#2056：第一次排版的位置會黏住

`TutorialOverlay.swift:394`、`:402-408`；`TutorialCardPlacement.swift:305-320`。改前第一次量到大小會清掉記下的位置；改後第一次排版（目標還沒量到時放正中間）的位置在之後是第一個候選、平手就贏。iPad 上地圖中央常是 0 成本，卡片可能留在中央擋視線。目標從沒有變成有時清一次。決策 688 自己標了 UNVERIFIED。

### L17-21（P3）#2038：「沒開就再按一次」現在只剩遮蔽作用

`TutorialUITests.swift:379-382`。#2056 已修掉膠囊搬家的原因；重試會讓「按到了卻第一次沒開」的真 bug 也綠。full lane 穩定幾天後拿掉，或重試時記一筆 `XCTContext` 活動好統計。它不會把開著的卡片按回去（開著時沒有那顆鈕）。

### L17-22（P3）#2054：報告的「最長連讓」和研究文件的定義不同

`DepotReturnReportTests.swift:284`、`:416-433` 對 `docs/research/TYMC_YIELD_2026-11-11.md:9`。文件用「30 分鐘內再讓」；測試沒有時間窗，載客或進機廠才歸零。現在的數字吻合（機捷 63 次、14 站），之後健檢拿來對門檻時容易讀錯。加一句說明。

### L17-23（P3）#2040：文件還指向已刪的 `AppIcon.appiconset`；只有 `.icon` 的上傳

- `docs/XCODE_CLOUD_ONBOARDING.md:250` 還寫圖示在 `Assets.xcassets/AppIcon.appiconset`。
- 舊的 appiconset 整個刪了，只剩 `AppIcon.icon`。決策 680 把「App Store Connect 收不收」標為 UNVERIFIED；125（run 43019183547）已上傳，處理結果是不是 VALID 請規劃看一眼，記進決策。

### L17-24（P3）#2035：技能寫要包 `GlassEffectContainer`，程式沒有

`.claude/skills/ui-review/SKILL.md:122` 對 `Map3DPreviewScreen.swift:139-215`（左上三顆、右上兩顆相鄰的玻璃）。決策 677 寫明刻意不做、等實機幀數；技能加一句「目前未採用，見決策 677」，免得每一輪審查都再報一次。

### 看過、沒有疑點的

- **#2046**：見結論。星等、遊客、帳走決策 361 既有的路；`subsidiaryDay` 的展品維護對其他種類是 0；賣車後展品留著有測試；沒有博物館的世界錢與人次不變有測試；錯誤文字兩種語言一致、沒有內部用語。
- **#2051**：見結論。`PlayerCommand.extendPlatform` 先確認世界裡還有那座一模一樣的月台；紀錄多的兩個欄位舊紀錄沒有、不受影響；復原與重播有測試；不收錢和 `addTrackPlatform` 一致。
- **#2043**：費率與 `Operations.swift` 逐項相符；元與分的換算正確；除以零都有擋；輸出不靠字典順序；顯示條件（環狀線、貨運線、沙盒不顯示）正確；指令後 memo 會清。
- **#2042**：級別邊界、類型的順序由陣列決定；新聞與面板同一個算法；讀檔不提示、縮小再長回不重複；每個遊戲日才掃一次土地；沒動 GameCore 與存檔。
- **#2037**：L16-1、L16-2 修到（第三節）；劇情節點以 id 記錄，門檻從 75% 改 60% 不影響舊存檔。
- **#2047**：沒有第二份權威；物理積分對負值、0、NaN、大的時間步都有夾；單位換算正確；停車點與畫的位置用同一條 trail；跟車對象改變或消失會結束駕駛；離開 3D 會結束駕駛。
- **#2039**：只動 GamePresentation 的鋪法，讀檔不重鋪；其他呼叫 `TrackRise` 的地方走預設、行為不變；仍是在複本上建成功才報價，失敗不留半套。
- **#2038**：`Map3DScene.addTrack` 逐行對過，行為相同；沒有跳過測試或放寬逾時；`swift-shards.sh` 裡兩個新類別名與檔案一致，用真的測試清單跑 `select` 都落在預期的 shard。
- **#2035**：19 處換玻璃、9 處留材質，與決策表相符；觸控範圍與 `accessibilityIdentifier` 都沒動；降低透明度交給系統。
- **#2040**：`project.yml` 不用改（`Resources` 整個資料夾是來源），pbxproj 的 4 行是 XcodeGen 重產的樣子；`icon.json` 參照的 5 個 SVG 都在；`release-archive.yml` 的路徑加了新資料夾。
- **#2048**：程式只有追分站的 `coastTimber` 配方與測試，每個 switch 都處理了新 case；技能指到的工具與文件都存在；與 CLAUDE.md 沒有矛盾。
- **#2054**：整個類別仍由 `DEPOT_RETURN_REPORT` 擋住，預設 0.017 秒；沒動既有斷言，GameCore 沒動。
- **#2056**：`placesAfresh` 對第一次量、轉向、改視窗大小都對；留下的位置出了界會被丟掉重放；多的那行 `let session = session` 和上一行同寫法，無害。

## 三、L16 發現的追蹤（以 3a2fbcc 為準）

| 編號 | 現況 |
| --- | --- |
| L16-1 | 修到（#2037：有服務車站、有名產店、或 800 m 內的景點不再收起；一公里內寫公尺） |
| L16-2 | 修到（#2037：站長四句不再叫玩家用短車、別加車；`neiwan.9` 降到 60%），見 L17-12 |
| L16-3 | 原因查到並修了（#2038 的重試、#2056 的膠囊不搬家）；引進 L17-4、L17-20、L17-21。125 發版後的 full lane 結果由規劃補記 |
| L16-9 第 4 點 | #2055 的說明第一行寫了「這一版起需要 iOS 26」 |
| L16-4 到 L16-20 其餘 | 這一輪沒有 PR 碰，沒逐條重查 |

## 四、驗證紀錄

- **建置**：`swift build --build-tests -Xswiftc -warnings-as-errors`（Linux，Swift 6.4.0，3a2fbcc）乾淨，**VERIFIED**。
- **測試**（`swift test --skip-build`，Linux，**VERIFIED**）：
  - 本 session：`RailwayMuseumTests`（12 支）、`PlatformExtensionTests`（6 支），0 失敗；暫時測試一支（L17-1，紅），已刪、沒有 commit。
  - 子代理：`TrainPurchaseEstimateTests`、`CityTitleTests`、`CityTitleReportTests`、`SightsWithinReachTests`、`ChallengeStoryNeiwanTests`（27 支，1 支要環境變數的略過）；`ManualDriveTests`（9）、`ManualDriveSessionTests`（6）、`WenhuUndergroundTests`（3）；`TutorialCardPlacementTests`、`Map3DStationKitTests`（35）、`DepotReturnReportTests`（19 支裡 18 支略過）。0 失敗。`python3 -I tools/golden-checks/doc_numbers.py --check` 沒有報錯。
- **UNVERIFIED**：
  - 所有 App 端（SwiftUI、Metal、玻璃、圖示、UI 測試）行為；這一輪沒有 macOS，也沒有跑 iOS workflow。L17-4、L17-20 是讀程式推得。
  - L17-2、L17-3、L17-5、L17-13 到 L17-18 的重現草稿都沒有跑（子代理不能重建）。
  - 決策 678、681、682、684 的量測數字照它們自己的報告引用，沒有重跑。
  - committed `.xcodeproj` 沒有重跑 XcodeGen 比對。

## 五、沒審到的與原因

- #2048 的 `coastTimber` 配方幾何本身、`docs/art` 的圖、railway-assets-private 的截圖：只看引用、測試與 switch 的完整性。
- 各 PR 頁面上的截圖驗收附件：只看 commit 與決策檔。
- `SaveFixtures/v87-railway-museum.json` 的內容：靠 `testVersionEightySevenKeepsTheMuseum` 與 `SavedGameTests`（後者沒有單獨重跑，CI 的完整 tier 跑過）。
- #2051 在沒有行車管制、列車行進中加長的行為：只讀程式，沒有寫測試（L17-7 第 3 點）。
- 12 個只改文件的 PR：沒有讀內容。

## 六、下一輪

- **REVIEW-L18 從 #2057 起**（`main` 3a2fbcc 之後）。
- 還沒派的：
  - P2：L17-1 到 L17-5。都小、都可以不動 GameCore；L17-1 與 L17-5 一個 PR，L17-2 與 L17-3（同一個檔）一個 PR，L17-4 單獨一個（只有 UI 測試）且最好先做，免得擋別人的 gate。
  - P3：L17-6 到 L17-24；L16 的 P3（L16-4 到 L16-20）與更早的仍照 L16 報告第六節。
- 建議：L17-7 第 1 點（多少月台加得了）與 L17-8（估算的耗時）交給 HEALTH-125 或下一輪 CIOPT 量；L17-23 的上傳結果請規劃看 App Store Connect 的處理狀態。
