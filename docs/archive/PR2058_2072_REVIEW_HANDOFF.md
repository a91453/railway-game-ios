# 交接：PR #2057–#2072 審查（審查 L18，0.6.0 (126) 發版後）

派工單 REVIEW-L18（遊戲規劃第 61 任 session_01YGNNup5PejVbKYpnZigyeN，2026-11-12）。規則是「每次發版後派一輪」。這一輪審 L17（`PR2032_2056_REVIEW_HANDOFF.md`）之後合進 main、而且在 0.6.0 (126) 裡的 PR，格式同 L17。

- Session：REVIEW-L18（session_01YGNNuma2FHpBcfV3QV73QR），branch `claude/review-l18`，壓縮 1 次。
- 基準：`main` **164bfc3**（0.6.0 (126) 的 commit）。每個 PR 都讀 merge commit 對 first parent 的 diff，也讀它的決策檔。
- 範圍：`git log --first-parent 3a2fbcc..164bfc3`。有程式的 10 個合併：#2058、#2061、#2062、#2063、#2064、#2065、#2067、#2069、#2071、#2072。
- 點數（照 HANDOFF §1「多久審查一次」）：**14 點**（規劃算的；#2063 只改 `ci.yml`，另外看了、沒算點）。
  - GameCore 2 點：#2058、#2062、#2065、#2069、#2072。
  - 1 點：#2061、#2064、#2067、#2071。
  - 0 點：只改文件的 #2057、#2059、#2060、#2066、#2070。
- 分工：
  - 本 session 自己讀 GameCore 的 #2072、#2065、#2062、#2069，跑它們的測試，並用兩支暫時測試確認 L18-1 與颱風停飛（已刪，沒有 commit）。
  - 兩個子代理只讀程式（不能建置）：一個讀 #2058、#2064、#2063，一個讀 #2061、#2067、#2071。子代理的 P2 由本 session 對過程式並重現。
- 存檔版本、決策編號、golden schema 都**不動**；只改文件。**只審不修**。

## 〇、範圍

| PR | 內容 | 點數 |
| --- | --- | --- |
| **#2072** | AIRPORT-1，決策 695：機場當樞紐（GameCore，存檔 89 → 90） | 2 |
| **#2065** | DRIVE-2，決策 693：駕駛結算與獎金（GameCore，存檔 87 → 89，88 跳過） | 2 |
| **#2062** | LOOP-EXTEND，決策 691：月台軌道加長（GameCore） | 2 |
| **#2069** | SUBSIDIARY-1，決策 692：買價與現值、營業價值封頂（GameCore） | 2 |
| **#2058** | FIX-L17，決策 689：L17-1 到 L17-5（GameCore 一條檢查） | 2 |
| #2061 | DRIVE-HUD，決策 690：駕駛畫面 | 1 |
| #2064 | FIX-L17-P3：九個 P3 | 1 |
| #2067 | MUSEUM-2，決策 696：館舍與館藏頁 | 1 |
| #2071 | AIRCRAFT-LOOK，決策 698：飛機模型 | 1 |
| #2063 | `ci.yml`：stack frames 那個 job 裝不到工具時不紅 | — |
| 其餘 5 個 | L17 本身、HEALTH-125、HANDOFF、研究、126 的說明 | 0 |

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（當天修） | **0** |
| P2（該修） | **2**：L18-1、L18-2 |
| P3（記著） | **17**：L18-3 到 L18-19 |

- 沒有 P1。126 已發，沒有東西要撤回：存檔讀得回（87、89、90 三個 fixture 與 `SavedGameTests` 都跑過），沒有發現錯帳、當機、死結或決定性的問題。
- **#2072（機場）站得住**：
  - 沒有「沒去處的收入」。機場旅客走的是既有的 `TouristFlows`：要有車、有容量、付既有的票價，沒有新的帳目種類；`railBonus` 只影響顯示的航班與旅客數，不進帳。
  - 決定性：沒有亂數；字典都排序後才用；午夜 `closeAirportDay` 和 `closeTourismDay` 在同一個 `if midnight` 裡，批次與逐分同一個點。
  - 存檔：`airportsProblem` 驗證齊；89 的存檔沒有 `airports` 鍵照樣讀；`GameSession.init` 先補機場才 `CommandLog(start:)`，所以新錄的指令紀錄自洽。
  - 颱風停飛**程式是對的但沒有測試**（暫時測試確認：`isClosed`、航班 0、旅客 0；L18-4）。
  - 資料的 UNVERIFIED（民航局數字轉引維基、T1／T2 的分法是估的、松山與桃園的營運時段、`dayFactor` 與 `flightShape` 是自己訂的）決策 695 §6 都有寫，沒有漏報。
  - 留下的是觀光來源權重的副作用（L18-3，沒量）與幾件小事（L18-4、L18-5）。
- **#2065（駕駛獎金）站得住**：檢查全在動手前，`testARunTheWorldRefusesChangesNothing` 比對 `world == before`；帳目種類與項目在 `Operations.swift` 有驗證；獎金算術與決策一致；v89 fixture 的測試有斷言版本 89。自動模擬拿不到獎金。小事在 L18-6。
- **#2062（月台軌道加長）站得住**：計畫在網路的副本上做，列車與錢都在動手前檢查；邊與節點的 ID 不變；`TrainPosition` 只有 `.onEdge`，所以列車檢查蓋到所有在線上的車；沒有既有邊紀錄時 `extendTrackAsset` 會走 `acquireAsset`，資本支出照樣記。測試有世界 JSON 往返、行進中的列車、復原、重播。沒有發現。
- **#2069（營業價值封頂）站得住**：GameCore 只多一個 `min` 與一個算出來的旗標，不存檔；售價仍是 `max(不動產價, 營業價值)`，所以封頂不會讓售價低於決策 130 的價。小事在 L18-7。
- **L17 的五個 P2 都確實修到**（#2058），九個 P3 也是（#2064）；見第三節。
- **CI 規則沒有被繞過**：#2063 沒有動 gate，只是讓本來就 `continue-on-error` 的 job 在裝不到工具時不紅（L18-17）。

## 二、發現

### L18-1（P2，已重現）#2067：今天買的車種在館藏頁列在「還沒擁有」

- **位置**：`Sources/GamePresentation/RailwayMuseumGuide.swift:56`（`waiting` = 圖鑑減 `museum.exhibits`）；標題在 `RailwayGameApp/Views/TourismPanel.swift:318`（「還沒擁有／Not owned yet」）。
- **問題**：展品只在蓋館當下（`PlacedBuilding.swift:379`）與午夜（`Tourism.swift:809` `collectMuseumExhibits`）收集。玩家買了一種新車，到午夜之前，館藏頁把它畫成剪影、放在「還沒擁有」下面；公司明明已經擁有。決策 696 §4 把這一區定義成「公司沒擁有過的車種」，同一頁的提示又說「買一種沒擁有過的列車，隔天進館展示」，兩句互相打架。
- **重現**（Linux，本 session 跑過，暫時測試）：`ScreenshotScene.museumWorld` → 取一個 `!isShown` 的車種 → `world.purchaseTrain(named:as:)` → 再建 `RailwayMuseumGuide`。結果 `world.ownedTrainTypes()` 含它，`item.isShown == false`（線性馬達捷運）。
- **修法**（擇一，都不動 GameCore）：
  1. 標題改成「還沒展出／Not on show yet」。最小。
  2. 分三區：展出中、`world.ownedTrainTypes()` 裡還沒進館的（「明天進館／Arrives tomorrow」，不塗剪影）、還沒擁有。比較對得上決策。
- **驗證**：`RailwayMuseumGuideTests` 加一支（Linux）；畫面是既有清單改字或多一區，第一級，不用截圖。

### L18-2（P2，核對）#2072：機場存檔的測試用 `currentVersion` 拼檔名，下一次升存檔就找不到檔

- **位置**：`Tests/GameCoreTests/AirportTests.swift:155`（`"v\(SavedGame.currentVersion)-airports.json"`），開關 `AIRPORT_SAVE_NEW` 在 `:158`。
- **問題**：
  - 存檔升到 91 的那個 PR，這支測試會去讀不存在的 `v91-airports.json` 而紅。最順手的「修法」是照註解 `AIRPORT_SAVE_NEW=1` 重寫一份，那正是 CLAUDE.md 禁止的（為了過測試而重生存檔）。
  - 測試也沒有斷言讀回來的是版本 90；#2065 的 v89 測試有斷言 89，寫法不一致。
  - `v90-airports.json` 本身仍由 `SavedGameTests` 讀（每個 fixture 都讀），所以 90 的存檔讀得回這件事現在有人看；問題只在下一次升版。
- **重現**：把 `SavedGame.currentVersion` 暫時改成 91 再跑 `swift test --skip-build --filter 'AirportTests/testTheSaveKeepsTheAirports$'`（沒有跑；讀程式可知 `Data(contentsOf:)` 會丟錯）。
- **修法**：檔名寫死 `v90-airports.json`，加 `XCTAssertEqual(saved.version, 90)`；重寫的開關改成只在檔案不存在時才寫，或拿掉。只動測試。
- **為什麼是 P2**：AIRPORT-DOMESTIC、DRIVE 後續都在路上，下一個升存檔的 PR 一定踩到。

### L18-3（P3，沒量）#2072：機場站的觀光來源權重很大，有些景點的遊客數會變

- **位置**：`Sources/GameCore/Passenger/Tourism.swift:992` 附近（`touristSources` 加 `airportTouristWeights()`）；`Airport.swift:167`。
- **問題**：
  1. 機場站的權重是它一天的航空旅客（桃園 T1／T2 約 5.9 萬／7.2 萬），和「最忙五站的居民」與 `outsideWeight` 20 萬放在一起分。到得了機場站的景點，遊客大半改成從機場站出發。
  2. 以前「沒有任何來源到得了」的景點，現在只要機場站到得了，就拿到全部的 `expected` 遊客。決策 695 寫「景點一天來多少人不變」，只在原本就有來源時成立。公司自己的景點（廟、夜市、博物館）這樣多出來的是新的遊客收入。
  3. 颱風停飛那天，機場照樣當來源（`airportTouristWeights` 不看停飛；暫時測試：停飛日權重仍是 16,000）。
- **不是 P2 的原因**：遊客還是要搭車、付票價、受容量限制，不是憑空的錢；方向也合理（外國旅客從機場來）。但幅度沒有人量過。
- **修法**：交 HEALTH-126 量（桃園機捷那張圖，補機場前後各景點的遊客與公司景點收入）；決策 695 補一句「原本沒有來源的景點會多出遊客」；停飛日把權重歸零要動 GameCore（一行），量完再決定。

### L18-4（P3）#2072：測試缺的

1. **颱風停飛沒有測試**。`Airport.swift:190` 的 `closed` 沒有任何測試走到。暫時測試（`Disruptions(level: .standard, country: "TW", seed: 7)`，找第一個颱風蓋到航廈的日子，第 194 天）確認 `isClosed == true`、航班 0、旅客 0、`from`／`to` 空。照 `FerryTests.testATyphoonKeepsTheBoatsIn` 的寫法補一支即可（Linux）。
2. 舊的真實地圖存檔補機場那一步（`AirportCatalog.withAirports`）有測試，但沒有「補完之後存、再讀、不再補第二次」的往返。
3. 昨天是停飛日時 `yesterdayText` 回 `nil`（航班 0、旅客 0），面板上什麼都沒有；沒有測試，也沒有「昨天停飛」這句話。

### L18-5（P3）#2072 的小事

1. **整點的繞回**：`landedShape` 用 `flights[(h+23)%24]`，營運到 24 點的機場（高雄 6–24、桃園全天）23 點落地的旅客算在同一天的 0 點（當天的航班還沒飛）；`leavingShape` 用 `flights[(h+2)%24]`，松山 06:00 的航班把旅客放在 04:00–05:00，那時沒有捷運。這些人照樣算進 `ridersTo`、鐵路加成與「今天搭你的車」。決策的限制有寫「不是閘門數」；記著。
2. **上限**：`yesterdayPassengers`／`yesterdayFlights` 在 `dailyPassengers` 等於 `maximumAccrued`（1<<50）時，乘 1.15 × 1.2 後會超過上限，世界會寫出一個自己的 `airportsProblem` 不收的存檔。算術本身不溢位（2^50 × 1150、× 1200 都在 Int64 內）。圖鑑的數字很小，只有手改資料走得到。
3. **面板**：`TourismPanel` 的 `.task { airportDays = world.airportDays() }` 在主執行緒建 `PassengerRouteGraph`，只在開面板時算一次；面板開著過了午夜或蓋了站不會更新（沒量時間，未驗證：要實機）。
4. **舊的問題回報**：125 錄的指令紀錄，起點世界沒有機場；126 重播時 `GameSession.init` 會補上機場（`GameSession.swift:1287`），之後的旅客與擁擠不同，重播可能在某一步和裝置上的分岔（`HeadlessGame.replay`）。和 `withCityRidership` 同一類。沒有重現。修法：問題回報帶版本時，重播舊版的紀錄不補；或在文件記一筆。
5. **新局與舊檔不一致**：`NewGame.swift:160` 對任何真實地圖新局都放機場；`withAirports` 對 `scenario != nil` 的世界不補。所以真實地圖的挑戰，126 新開的有機場，125 存下來再讀的沒有。沒有驗證哪些挑戰的圖框裡有機場。
6. **給 AIRPORT-DOMESTIC（決策 700）的提醒**：`withAirports` 的條件是 `airports.isEmpty`，126 已經有 5 座機場的存檔拿不到後來加的 8 座；要改成「補圖鑑裡還沒有的」，而且編號要穩定。
7. 網站的資料來源頁還沒同步（決策 695 下一步 6，已知）。

### L18-6（P3）#2065 的小事

1. `ManualDriveSession.swift` 的 `settleManualDrive()` 用 `try?` 送 `.settleDrivenRun`：被拒絕時畫面有分數、沒有獎金那一行，也沒有原因。
2. `finishManualDriveForScreenshot()` 是 `public`，會造出一趟保證好成績的駕駛並真的結算獎金；呼叫的只有 `Map3DPreviewScreen.swift:2291`（要 `-screenshot-drive-result` 啟動參數）。現在安全；函式本身最好只在 DEBUG 編進去。
3. `ManualDrive.Result.run(of:)` 裡的 `whole()` 遇到 NaN 會當（`Int64(nan)`）；輸入都是有限的累加值，沒有找到走得到的路。
4. `.drivingBonus` 加在 `propertyRevenue`（附屬收入）裡；決策有寫，報表上會和不動產混在一起。
5. 獎金能不能刷（強制 1× 下每真實分鐘賺多少）是 HEALTH-126 的題目。程式面：一趟最多 NT$500 + 每位旅客 NT$5，兩趟至少隔 20 遊戲秒。

### L18-7（P3）#2069 的小事

1. **有收購費的情形沒有單元測試**（決策 692 限制 5 自己寫了）：測試世界是空地，`building.cost == buildingCost + landRight`，兩個頂相等，`max` 的哪一邊都沒被分開測到。`BuildingSaleTests` 有旁邊有城市建物的世界可用。
2. 封頂那一列寫「生意好，至少賣回買價」；當頂是「現在重蓋一棟」（地漲過買價）時，賣價高於買價，句子仍成立但沒說出漲的原因。下一列「買價 Y（漲 N%）」有補上，可以不改。
3. `changeText` 在售價等於買價時寫「（漲 0.0%）」。
4. 檢視面板現在對每一棟公司建物都呼叫 `world.saleQuote(of:)`（以前只有子公司）；沒量，單棟應該很便宜。
5. 決策 692 限制 1（帳上利潤 1,642 萬、現金只多 522 萬，原因沒查）與限制 3（飯店、遊樂園沒量）仍是 NOT ASSESSED；第 ② 步開工前要先查，這裡只是再提一次。
6. 決策 692 限制 6：那個 PR 本機沒有跑 `-warnings-as-errors`；這一輪在 164bfc3 跑過，乾淨。

### L18-8（P3，核對）#2058：沒有景點的真實地圖也蓋不了廟、夜市、博物館；決策 689 寫「真實地圖不受影響」

- **位置**：`Sources/GameCore/Passenger/Tourism.swift:340`（景點清單空就 `tourism = nil`）、`Sources/GameCore/City/PlacedBuilding.swift:345`（`sightNeedsTourism`）、`Sources/GamePresentation/NewGame.swift:155`。
- **問題**：圖框裡沒有圖鑑景點的真實地圖新局（台灣以外一定是；台灣境內有沒有這種框沒查）`tourism == nil`，清單就不列這三種，125 的主打博物館在那裡沒有，也沒有說明。以前蓋了也是零遊客的錢坑，所以規則一致，只是決策的句子不對。
- **重現草稿**（沒跑）：`GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 35.68, longitudeDegrees: 139.76)!)`，看 `tourism == nil` 與 `GameSession(world:).buildingKindsOffered`。
- **修法**：決策 689 補一句；或清單在藏起景點時多一行說明。不動 GameCore。

### L18-9（P3，未重現）#2058：按住的速度躲得過開始駕駛時的降速

- **位置**：`Sources/GamePresentation/ManualDriveSession.swift:98`。
- **問題**：`startManualDrive` 讀 `world.clock.runningSpeed`；若此時是 1× 而 `heldSpeed == .x10` 還沒套用（`GameSession.swift:1775`），判斷為不用降，之後 10× 才套上。把手有箝制所以仍是 1× 的手感，但時鐘跑 10×。窗口很窄。
- **修法**：`startManualDrive` 一開始先 `applyHeldSpeed()`。Linux 可測。

### L18-10（P3）#2058、#2064：買車估算的兩個邊角

1. `TrainPurchaseEstimate.swift:366`：往回取「成本在模型 15% 內」的連續日，遇到第一個不合的就停；一天颱風停駛或半天營運會把更早的歷史全部切掉，`historyDays` 掉到 0–2，「現在」在帳本與模型之間跳。幅度沒量。
2. `:386` 的 `.noRiders`：一條還沒有車的線也是「這條線還沒有人搭，票收估不出來」；那正是玩家最想看票收的時候。設計上的事，記著。

### L18-11（P3，未驗證：要實機）#2061：大字級下駕駛畫面的兩個固定尺寸

- `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:2843-2850`（速限圓 34×34）與 `:2880`（結果卡 260 pt）在大的 Dynamic Type 下可能截字。照 `ui-review` 技能要看最大字級；沒有模擬器，沒看。

### L18-12（P3）#2061：兩個文字

1. `ManualDriveSession.swift:113`、`:156`：下一站那行在接手當下就用當時的語言組好存著，駕駛中換語言不會跟著換。
2. `Map3DDriverHUD.swift:125`：滿 60 秒才寫「晚 N 分」，決策 690 寫的是「晚幾秒」。

### L18-13（P3，核對）#2067：鎖住的車包，「3D」鈕會開到別的車

- **位置**：`Sources/GamePresentation/RailwayMuseumGuide.swift:44`（`Map3DTrainSet.set(forKey:count:locked: [])`）；測試用的是 `Map3DModelPack.standard.drawnSet`，兩邊剛好相等所以綠。
- **問題**：這裡固定傳 `locked: []`，沒有看玩家實際鎖了哪些模型包；鎖住的車種，館外停的是替代模型，「3D」鈕卻開它自己的（或反過來）。`TrainShowcaseScreen.swift:44` 怎麼處理鎖住的 key 沒有驗證（要實機）。
- **修法**：把 session 的鎖定集合傳進 `RailwayMuseumGuide`；Linux 可測。

### L18-14（P3）#2067：館外 12 股停的是圖鑑順序的前 12 種，不是先來的 12 種

- **位置**：`Tourism.swift:813`（展品照 `row` 排序）、`Map3DRailwayMuseum.swift:378`、提示 `RailwayMuseumGuide.swift:73`（「之後的收在館內」）。
- **問題**：決策 696 §1 與提示都說後來的收在館內；實際上第 13 種若圖鑑列號比較小，會把原本停在線上的一種擠進館內，各股的車也跟著換位。存檔不受影響（順序本來就是驗證的一部分）。
- **修法**：改提示與決策的句子最小；要「先來先停」得另存到館順序（升存檔），不值得。
- **附**：館藏頁沒有超過 12 種展品的測試。

### L18-15（P3）#2067 的其餘小事

1. 展品模型的快取 key 沒有含博物館位置（`Map3DPreviewScreen.swift:1280-1282`）；賣掉再到別處蓋一座時會不會留在舊位置沒有驗證（要實機）。
2. 「館藏…」鈕高約 38 pt（`InspectorView.swift:391`，照抄旁邊較早的「出售」鈕 `:369`），低於 44 pt。
3. `testRailwayMuseumIn3D`、`testRailwayMuseumPage` 放在 `WebsiteScreenshotTests`（不在 gate，也不在夜間完整線）；其中一條路徑點正規化座標 (0.69, 0.78) 之後沒有斷言。

### L18-16（P3）#2071：Swift 與 Python 的一致性檢查只能手動跑

1. `tools/airport-aircraft-studies/parity.sh` 與 `test_geometry.py` 沒有任何 workflow 呼叫；改了 Swift 那邊的配方，CI 不會知道兩邊分岔。
2. `parity.py` 只走 Python 的清單，Swift 多出來的模型不會被發現。
3. 停機坪三個機位在 y = −24／0／24，翼展 17／36／65 m 會互相重疊（`Map3DAirportStudies.swift:43`，比這個 PR 早；AIRPORT-2 把飛機擺上去時要處理）。

### L18-17（P3）#2063：工具永遠裝不到時，那個 job 會一直是綠的

- **位置**：`.github/workflows/ci.yml:439-449`。
- **問題**：任何安裝失敗（套件改名、映像檔換了、apt 鎖）都變成綠燈加一則 notice，而且 notice 一律寫「套件庫沒有回應」。那個 job 本來就不在 gate 裡，所以沒有放寬任何門檻；少掉的只是「長期壞掉」會被看見的紅燈。
- **修法**：`::notice::` 改 `::warning::`，原因寫中性；或改用工具鏈自帶的 `llvm-objdump`（HANDOFF 已有這一條）。

### L18-18（P3）#2062：決策與行為的一處

- 決策 691 限制 5 寫明：已認出站型的車站裡，687 的月台加長現在會連軌道一起長。行為有測試；只是玩家文字沒有在「加長月台」那裡先說價錢會含軌道（預覽有價錢）。記著。

### L18-19（P3）沒有破壞但值得知道

- #2058 之後，125 錄的、在沒有觀光的世界蓋過景點的指令紀錄，重播會停在那一步（決策 689 有寫）。`ReplayFixtures/` 與 `GoldenScenarios/` 裡沒有這三種建物（grep 過）。

### 看過、沒有疑點的

- #2072：`setAirports` 重新編號與驗證；`PassengerPlanCache.airports` 的失效條件；批次喚醒含 `demandDay != nil`；`servingStation` 每次計畫只算幾座機場；玩家文字中英都只說功能；`DataSourceCredits` 有條目。
- #2065：`drivingProblem` 的驗證；復原只在下一個 tick 之前可能，之後歷史清空；`RailwayMuseumTests` 把 87 改成 `currentVersion` 的那一支是對新編出來的存檔，不是 fixture，沒有放寬。
- #2062：`moveNode`、`restoreEdge`、`refreshFouling` 與加月台、拆月台同一條路；`TrainMovement` 只存速率、邊、游標與終點，終點有照最後一條邊的增長調整；`ServicePath` 的 `Berth`、`PathMemo` 是每次 advance 重算的。
- #2069：`businessCapped` 不進 Codable；`salePreviewLines` 與檢視面板用同一個 `changeText`；自由模式不顯示。
- #2058：`sightNeedsTourism` 在 `placement(of:at:look:)`（非 mutating），`placeBuilding` 在 `economy.spend` 之前呼叫；測試比對 `world == before`；`LocalizationTests` 的數量 57 → 58。
- #2064：`tripThousandths` 有 `headway > 0`；`manualDriveSound` 結束後回 `(0, nil)`；`Map3DStationKitCatalog.swift` 的四列座標與產生器一致（`catalog.py --check` 通過）。
- #2063：`defaults.run.shell: bash` 帶 `-eo pipefail`；`install_tools || { sleep 20; install_tools; } || true` 在 `-e` 下安全；後面的步驟看 `steps.tools.outputs.ready`，工具在時回歸照舊會紅。

## 三、L17 發現的追蹤（以 164bfc3 為準）

| L17 | 狀態 | 在哪裡 |
| --- | --- | --- |
| L17-1 | 修了（#2058） | `PlacedBuilding.swift:345`；順序在 `invalidBuildingLook` 之後、`museumAlreadyBuilt` 之前。副作用見 L18-8 |
| L17-2 | 修了（#2058；補充在 #2064） | `LinePanelMemo.swift:197-198`；`.noRiders` 見 L18-10 第 2 點 |
| L17-3 | 修了（#2058） | `TrainPurchaseEstimate.swift:366`；邊角見 L18-10 第 1 點 |
| L17-4 | 修了（#2058），**UNVERIFIED**（要 macOS） | 迴圈改成看期限 |
| L17-5 | 修了（#2058） | `runningSpeed`、`speedCap`、箝制；邊角見 L18-9 |
| L17-9（1）、-10、-11、-14、-17、-22、-23、-24 | 修了（#2064） | L17-11 的畫面更新 UNVERIFIED（SwiftUI） |
| L17-6、-7、-8、-9（2）、-12、-13、-15、-16、-18 到 -21 | 沒有動 | 照 L17 報告 |

## 四、驗證紀錄

- **建置**：`swift build --build-tests -Xswiftc -warnings-as-errors`（Linux，Swift 6.4.0，164bfc3）乾淨，**VERIFIED**。
- **測試**（`swift test --skip-build --filter …`，Linux，164bfc3，**VERIFIED**，0 失敗）：
  - GameCoreTests 7 個類別、106 支（1 支略過）：`AirportTests`、`DrivenRunTests`、`RailwayMuseumTests`、`ReplayFixtureTests`、`SavedGameTests`、`SchoolsHospitalsNightMarketsTests`、`SubsidiaryTests`。
  - GamePresentationTests 17 個類別、145 支（1 支略過）：`AirportCatalogTests`、`AirportReportTests`、`BuildingSaleSessionTests`、`BuildingSessionTests`、`CityTitleTests`、`CommandEditTests`、`LocalizationTests`、`ManualDriveSessionTests`、`ManualDriveTests`、`Map3DAirportAircraftStudiesTests`、`Map3DRailwayMuseumTests`、`PlatformExtensionSessionTests`、`PlatformLoopExtensionSessionTests`、`RailwayMuseumGuideTests`、`SubsidiarySessionTests`、`TourismSessionTests`、`TrainPurchaseEstimateTests`。
  - 暫時測試兩支（L18-1 的重現；L18-4 第 1 點的颱風停飛），跑過、已刪、沒有 commit。
- **工具**（Linux，**VERIFIED**）：`python3 -I tools/golden-checks/doc_numbers.py --check`、`python3 -I tools/station-kit/catalog.py --check`、`python3 -I -m unittest discover -s tools/stack-frames -p 'test_*.py'`，都通過。
- **UNVERIFIED**：
  - 所有 App 端（SwiftUI、Metal、UI 測試）行為；這一輪沒有 macOS，也沒有跑 iOS workflow。L18-5 第 3 點、L18-11、L18-13、L18-15 是讀程式推得。
  - L18-2、L18-5 第 4、5 點、L18-8、L18-9、L18-10 的重現沒有跑。
  - L18-3 的幅度沒有量；決策 692、693、695 的量測數字照它們自己的報告引用，沒有重跑（`BalanceReportTests` 沒跑）。
  - `tools/airport-aircraft-studies/parity.sh` 沒有跑。
  - committed `.xcodeproj` 沒有重跑 XcodeGen 比對。

## 五、沒審到的與原因

- #2071 的飛機幾何本身與 #2067 的館舍模型好不好看：`model-look` 的事，只看程式、測試與引用。
- 各 PR 頁面上的截圖驗收附件：只看 commit 與決策檔。
- `SaveFixtures/v89-driven-run.json`、`v90-airports.json` 的內容：靠各自的測試與 `SavedGameTests`。
- `AirportCatalog` 五座機場的座標與數字有沒有對過來源：沒有重查，照決策 695 §6 的聲明。
- #2062 `loopExtensionPlan` 的幾何（`StationThroat`、`reach`、`loopShift`）只讀過一遍並靠它的 10 支測試；沒有另寫邊界測試（坡道、曲線起點剛好在咽喉）。
- 5 個只改文件的 PR：沒有讀內容。

## 六、下一輪

- **REVIEW-L19 從 164bfc3 之後的第一個合併起**。
- 還沒派的：
  - P2：L18-1（館藏頁，GamePresentation 加 App 一行字）、L18-2（只動一支測試）。都小、都不動 GameCore，可以一個 PR；L18-2 最好在下一個升存檔的 PR 之前合。
  - 交 HEALTH-126：L18-3（機場來源權重對景點遊客與公司景點收入的幅度）、L18-6 第 5 點（駕駛獎金）。
  - 交 AIRPORT-DOMESTIC：L18-5 第 5、6 點。
  - P3：L18-3 到 L18-19；L17 沒動的 P3 與更早的仍照 L17 報告第六節。
