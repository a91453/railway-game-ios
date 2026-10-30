# 交接：PR #1551–#1578 審查（審查 L2）

派工單 審查 L2（遊戲規劃第 36 任 session_01YGNNunAp2WBFfGrmq3mXES，2026-10-30）：審查 #1551–#1578 合進 main 的程式 PR，幾乎就是 99.1 的內容。只找會讓玩家壞掉的：當機、存檔讀不回或舊存檔行為改變、決定性被破壞、主執行緒卡頓、iPhone／iPad 直橫畫面跑版、錢算錯、玩家看的文字違反 `docs/UI_THEME.md`。另一段 #1510–#1549 是審查 L1（`PR1510_1549_REVIEW_HANDOFF.md`）。

- Session：session_01YGNNuoHoVW8bZch4prpm3R，branch `claude/review-pr1551-1578`。
- 基準：`main` **d71ffec**（#1578 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。疑點用 Linux 的 `swift build`／`swift test --filter` 和臨時量測驗證（量完刪掉，沒有提交）。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

| PR | 內容 | 層 | 點數 |
| --- | --- | --- | --: |
| #1551 | 遊戲選單直拿與 iPad 顯示按鈕文字、規則列說明（決策 498 B2） | App＋GamePresentation | 1 |
| #1553 | 資料來源不再連到原始碼儲存庫，ODbL 改寫信索取（決策 503） | GamePresentation | 1 |
| #1554 | 收購卡：合計列、04:00 前收購寫「今天首班車」 | App＋GamePresentation | 1 |
| #1555 | 98.1 更新說明 | GamePresentation（文字） | 1 |
| #1557 | iPhone 橫拿的載入畫面 | App＋GamePresentation | 1 |
| #1558 | 存檔清單的檔頭快取（決策 497） | GamePresentation（SaveLibrary） | 1 |
| #1559 | 沿單行道鋪的路，公車照單行方向 | GamePresentation | 1 |
| #1560 | iPhone 橫拿路線面板先列路線（決策 498 B1） | App＋GamePresentation | 1 |
| #1561 | iPhone 橫拿經濟面板的圓環 | App | 1 |
| #1562 | 車站名牌避開泡泡時不蓋到旁站（決策 501） | App＋GamePresentation | 1 |
| #1563 | 98.1 更新說明補兩行 | GamePresentation（文字） | 1 |
| #1565 | 建造卡說出軌道蓋不了的原因 | GamePresentation | 1 |
| #1567 | 每天 04:00 車站還在等的人回家（決策 504） | **GameCore** | 2 |
| #1568 | 6000× 卡頓的量測：畫面更新與遊戲時間（決策 505） | App＋GamePresentation | 1 |
| #1570 | 手機面板開著時圖例往下（不擋鋪軌） | App＋GamePresentation | 1 |
| #1571 | 復原時放掉選要拆的那段路 | GamePresentation | 1 |
| #1572 | iPhone 橫拿：建設工具欄從上排、卡片開關移到「建設」旁、地圖版權往右讓 | App＋GamePresentation | 1 |
| #1573 | 還沒有路線：路線面板說缺什麼、站長問要不要教學（決策 508） | App＋GamePresentation | 1 |
| #1576 | 描線經過可收購路線時提示價格、「收購路線」鈕 | App＋GamePresentation | 1 |
| #1577 | 面板標題可兩行 | App | 1 |
| #1578 | 99.1 更新說明 | GamePresentation（文字） | 1 |

共 21 個程式 PR、22 點。只改文件的 #1552（README）、#1564、#1566、#1569、#1574、#1575 是 0 點，沒有審。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **1**：L2-1 |
| P3（記著） | **4**：L2-2～L2-5 |

GameCore 的 #1567 和執行結果一致，不會讓存檔讀不回、不破壞決定性：

- **入口**：`sendWaitingPassengersHome(at:)`（`PassengerDemand.swift:316`）在逐分那條路（`GameWorld.swift:2768`）與跳過閒置分鐘的兩條路（`:2909` 有放旅客／記帳／貨運時、`:2918` 都沒有但還有人在等時）都呼叫，順序都是「記帳之後、放旅客之前」，所以一次走完和逐分走是同一個世界。只在 `時間 mod 一天 == 04:00` 時動作，判斷用 `(s % day + day) % day`，負的時間也對。
- **決定性**：計數先放進字典，再照 `keys.sorted()` 寫回各站，和既有的 `abandonPassengers(waitingAt:)`（`:296`，車站關閉時）同一個寫法；轉乘中的人算回出發站。沒有用到集合順序或亂數。
- **存檔**：沒有新欄位，等的人和 `abandoned` 本來就存；舊存檔在下一個 04:00 讓人回家。`SaveFixtures` 沒改，`SavedGameTests` 通過。golden（3 個）與 replay（2 個檔的後段 checksum）的變動在決策 504 逐項寫明。
- **效能**：一天一次、每站一次線性掃描，加上每個出發站一次 `firstIndex`；就算幾百站也是一次十幾萬次比較，跑在 tick 裡，不是每幀。
- **跨版本**：這條規則讓 04:00 以後的世界和 99.0 以前不同；新舊版本混跑同一個網路對局會不同步，和上一輪 REV-5 同一件事，不另列。

其他 App／GamePresentation 的重點：

- **#1558**（檔頭快取）：快取放在 Caches，和存檔資料夾分開；用大小、修改時間、檔案編號判斷是不是同一個檔，存檔本身與格式沒動；寫的時候日期一樣用 ISO 8601（`SaveLibrary.swift:477`、`:845`），存檔當下記的檔頭和之後讀檔得到的一樣。讀不出來的檔不快取，下次再試。
- **#1576**（描線提示）：路線報價在背景算（`Task.detached`），回到主執行緒時比對 `commandRevision`。可收購路線的實際路徑第一次要算：竹中（六家線 2 站）、瑞芳（3 站）各約 **0.9 ms**（Linux debug，臨時測試量的），之後用記憶，不會卡。
- **#1568**：新增的 run loop 觀察者在 `stopBeat` 都失效；閉包不抓 self，用 `MainActor.assumeIsolated`（觀察者掛在主 run loop）。
- **#1572**：工具欄改成往下伸到版權那一帶時，同時用 `mapCreditsLeading` 把 Apple 標誌、OSM 版權往右讓過工具欄；版權字改成可換行，但字數短（`DataSourceCredits.mapCorner` 最長約 45 字元），一般字級不會換行，換行時 `attributionFrames` 也照新的高度回報，地圖上的東西會讓開。
- **#1565**：`geometry == nil` 提早回傳只改錯誤文字；原本的緩坡（eased profile）要先有 `geometry` 才算，所以沒有原本蓋得了、現在蓋不了的情形。
- 更新說明（#1555、#1563、#1578）、#1553 的授權文字、#1573 的站長與說明文字：只說玩家能做什麼，沒有內部名稱或設計理由，符合 UI_THEME。

## 二、發現

### L2-1（P2）#1573：站長的「跟我做 5 分鐘教學」直接換成第 1 關，目前這局沒有先存，最多 15 分鐘的進度不見

- **位置**：`Sources/GamePresentation/GameLauncher.swift:220`（`chooseFirstLineGuide(_:)`）→ `startTutorial()`（`:1222`）→ `startLesson`（`:1107`）→ `begin(_:keepingAutosave: true)`（`:1627`）。按鈕在 `RailwayGameApp/Views/StationMasterView.swift`（`offerCard`），呼叫在 `ContentView.swift:684`。
- **問題**：`begin` 的 `keepingAutosave` 只把**已經在磁碟上**的自動存檔改名保留（`SaveLibrary.archiveAutosave()`），沒有先把**正在玩的這局**寫下去。這局的自動存檔每 15 分鐘一次（`GameLauncher.autosaveInterval`），或回開始畫面時（`returnToStart` 會先 `autosaveCurrentGame`）。所以按下去之後，上次自動存檔以後做的事都沒了；才開的新局（還沒到第一次自動存檔）整局不見。決策 508 寫「目前的局照舊自動存檔」，實際沒有。
- **什麼時候會碰到**：沒完成教學的玩家開自由遊戲，站長的卡片一開局就出現，**一直留著直到回答**，而且留著時站長不說別的。先不理它、自己鋪了軌道和車站（還沒有路線）的玩家，之後按「跟我做 5 分鐘教學」就會掉。實景地圖還要重新選城市、等載入。
- **玩家看到**：畫面換成第 1 關；回開始畫面找不到剛才那局，或只找到十幾分鐘前的版本。
- **驗證**（Linux，臨時測試，量完刪掉）：`startNewGame()`，鋪 1 段軌道、蓋 1 座車站，`FirstLineGuide.offers` 為 true；`chooseFirstLineGuide(.tutorial)` 之後 `session.lesson` 是第 1 關，存檔資料夾 `library.entries()` 是**空的**：剛才那局一個檔都沒有。
- **建議修法**：`chooseFirstLineGuide(.tutorial)` 在 `startTutorial()` 之前先 `autosaveCurrentGame(refreshing: false)`（同 `returnToStart()`），存失敗就不換局；加一個 Linux 測試：先建東西、選教學，存檔裡有那局。目標面板的「開始」（`GoalsPanel.swift:699`，`startLesson`）也是同一條路，修的時候可以一起看；那是玩家自己點關卡的既有行為，不是這次新增的。

### L2-2（P3）#1577：iPhone 橫拿時，兩行的面板標題可能放不進較矮的導覽列

- **位置**：`RailwayGameApp/Views/Theme.swift:226`（`panelTitle(_:)`）。
- **問題**：標題放在 `.principal`，`.headline`、最多兩行、最小縮到 0.8。iPhone 橫拿（compact height）時 inline 導覽列比直拿矮（舊系統約 32 點），兩行 headline 縮到 0.8 也約 35 點，可能被切上下或壓到列外。沒有在 Simulator 或實機看過（**UNVERIFIED**）。
- **重現**：iPhone 橫拿，開一條名字長的路線頁（或「可收購路線」頁），看標題。
- **建議**：截圖驗收時看一次；被切的話 compact height 時改 `lineLimit(1)` 加 `minimumScaleFactor`，或只在直拿用兩行。

### L2-3（P3）#1573：站長的教學卡在窄的時候按鈕字被切

- **位置**：`RailwayGameApp/Views/StationMasterView.swift`（`offerCard`、`offerButtons`）。
- **問題**：卡片寬 `min(maxBubbleWidth, 340)`，只要 `maxBubbleWidth >= 140`（`hasRoom`）就顯示。兩顆鈕是 `lineLimit(1)`，窄到排成上下兩列時，每顆可用約 116 點；「跟我做 5 分鐘教學」「Show Me (5 min)」「I'll Do It Myself」加上左右 12 點內距大約 124–140 點，會變成「跟我做 5 分…」。寬度在 140–170 點之間才會發生（例如面板開著、旁邊剩一點地圖的時候），用算的，沒有量（**UNVERIFIED**）。
- **建議**：按鈕改成可以兩行，或 `hasRoom` 對這張卡用較大的門檻。

### L2-4（P3）#1558：從快取檔讀回的檔頭沒有再比一次存檔版本

- **位置**：`Sources/GamePresentation/SaveLibrary.swift`（`HeaderCache.header(of:stamped:)`）。
- **問題**：直接讀檔時，`header(of:)` 會把比這個版本新的存檔標成 `newerVersion`；快取檔裡存的是成功的檔頭，讀回來直接當成功，沒有再比 `game.saveVersion <= SavedGame.currentVersion`。只有裝回**較舊**的版本（TestFlight 可以選舊建置）才會碰到：清單把新版本的存檔列成可讀，按下去讀檔時才被擋。
- **建議**：快取命中時也比一次版本（一行），或把 `SavedGame.currentVersion` 放進快取的格式號。

### L2-5（P3）#1576：報價算到一半世界變了，暫停時提示可能一直沒有價格

- **位置**：`Sources/GamePresentation/TracedSale.swift`（`quoteTracedSale(_:)`、`tracedSaleHint`）。
- **問題**：背景算完時若 `commandRevision` 已經變了，結果丟掉、`tracedSaleQuoteTask` 設回 `nil`，但這兩個都不會通知畫面（`tracedSaleQuoteTask` 是 `@ObservationIgnored`，`tracedSaleQuote` 沒有被設）。遊戲在跑時下一個 tick 會讓畫面重讀、重新報價；**暫停時**提示會停在「可以直接收購，含列車與真實班表。」沒有價格，直到玩家再動一下。按「收購路線」仍會開卡片、自己算價格，錢不會錯。用讀程式推的，沒有量。
- **建議**：丟掉舊結果時重新排一次報價，或把結果丟掉這件事也寫到一個會被觀察的值。

## 三、驗證

Linux、Swift 6.4.0、`main` d71ffec：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（通過；臨時測試刪掉後再建一次也通過）。
- `swift test --skip-build --filter`：`FirstLineGuideTests`、`TracedSaleTests`、`PassengerDemandTests`、`SaveListHeaderCacheTests`、`LinesPanelNavigationTests`、`ToolColumnTests`、`LegendFootUnderPanelTests`、`GameMenuLayoutTests`、`MapLabelPlacementTests`、`BusOwnRoadsTests`、`CityBusToolTests`、`RealLineAcquisitionTests`、`NetworkGeometryProblemTests`、`RealWorldLoadingTests`、`FrameTimeRecordTests`、`MainThreadStallReportTests`、`DataSourceCreditsNoRepoLinkTests`、`StationMasterAdviceTests`、`SavedGameTests`、`ReplayFixtureTests`、`GoldenScenarioTests`：**VERIFIED**，全部通過（0 failures；`ReplayFixtureTests` 等照常略過的 3 個除外）。
- L2-1 的重現與 #1576 的毫秒數：臨時測試量的，量完刪掉，沒有提交。
- L2-2、L2-3 的版面：**UNVERIFIED**（照派工單不跑 iOS workflow，沒有 Simulator 與實機）。

## 四、下一步

- L2-1 交給規劃派人修（下一版，100.x）；修好前，在說明或更新說明不要寫「按教學不會影響目前這局」。
- L2-2 在下一次 `website-screenshots.yml` 截圖驗收時順便看 iPhone 橫拿的面板標題。
- L2-3～L2-5 記著，有玩家回報再處理。
