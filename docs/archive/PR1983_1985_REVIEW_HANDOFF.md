# 交接：PR #1966、#1983–#1985 審查（審查 L15，0.6.0 (122) 發版後）

派工單 REVIEW-L15（遊戲規劃第 56 任 session_01YGNNuqMnQwhbSmiaZzhLsX，2026-11-08）。規則是「每次發版後派一輪」。這一輪審 L14（`PR1953_1982_REVIEW_HANDOFF.md`）之後合進 main 的 PR，格式同 L14。

- Session：REVIEW-L15（session_01YGNNukhsWYuJnxBUwBRNhq），branch `claude/review-l15`。
- 基準：`main` **dc4a436**，就是 0.6.0 (122) 的發版 commit（#1985 的合併）。每個 PR 都讀 merge commit 對 first parent 的 diff，也讀它的決策檔。
- 範圍：`git log --first-parent a3f7842..dc4a436`。
  - **#1966** 編號比 #1983 小，但在 L14 的基準 a3f7842 之後才合併（比 #1983 早 3 秒），L14 沒審到，規劃也把它算在 L15 的點數裡，所以這一輪一起審。
  - 開工時再查過一次：dc4a436 之後 main 沒有新的合併。
- 點數：#1984 2 點（收購資料），#1966 1 點，#1985、#1983、#1978、#1938 都是 0 點，合計 **3 點**。
- 分工：
  - 本 session 自己讀 #1984、#1985、#1978、#1938。
  - #1966 交給一個子代理讀程式並跑測試；它的主要結論，本 session 對過程式（下面標「核對」）。
- 存檔版本、決策編號、golden schema 都**不動**；只改文件。

## 〇、範圍

| PR | 內容 | 點數 |
| --- | --- | --- |
| **#1984** | TYMC-A12-TRACK，決策 652：機捷 A12 往 A13 那側的渡線改向（GamePresentation `RealLineAcquisition`） | 2 |
| #1966 | IPAD-FIXES，決策 643：iPad 教學鏡頭、下半卡全高、設定寫對裝置、開始畫面兩欄 | 1 |
| #1985 | WHATSNEW-122：122 的 What to Test 與「這版新增」卡 | 0（玩家看的文字，照派工單逐條對過） |
| #1978 | FULLLANE-121：只改 UI 測試 | 0 |
| #1938 | Codex 車站外觀第二批（決策 626）：研究配方，App 沒有引用 | 0 |
| #1983 | L14 本身，只改文件 | 0 |

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（發版前必修） | **0** |
| P2（下一版修） | **1**：L15-1。L13-1、L13-2 也還開著 |
| P3（記著） | **9**：L15-2 到 L15-10 |

- 沒有 P1。122 已經發了，這一輪也沒有東西要撤回。
- **#1984 的改法是對的，也只影響機捷**：
  - 渡線方向的判斷和決策 564 的 `keepsRight` 是同一個翻轉（`line.keepsRight != facing`），所以「迎著進站的車」的那一組，鋪法就是另一種靠邊方式的折返渡線。
  - `facingTurnbackStations` 與 `turnsBackBetween` 都只對 `tymc:A` 成立，其他線鋪出來的軌道和 main 逐項相同。決策 652 量的其他五線也沒有變。
  - 改建（`RealLineRebuild.realRebuildLayout`）只重鋪長庚那一段，不碰 A12。
  - 原本的 `testATrainTurnedBackReachesItsOwnTrack` 會檢查每一個折返站往兩邊的路，A12 停在 567、往機場回頭的車也在裡面。它仍然過，所以停在 567 的車還是回得到自己的股（改走 A13 那一組）。
- **#1985**：大多數條目對得上合併的 PR，兩種語言也一致。但「點車站快很多」和決策 644 自己寫的「點車站本身沒變」相反（L15-1）。另有幾條英中說法不一或說得太滿（L15-2、L15-3）。
- **上一輪的追蹤**（以 dc4a436 為準）：
  - **L13-1（P2，還成立）**：
    - 120 的說明（`WhatsNew.swift:200-201`）仍說 1× 也滑行。
    - 程式仍只在 10×／60× 滑行（`GameSession.swift:2260-2263`）。
    - 121、122 的說明都沒有更正。
  - **L13-2（P2，還成立，UNVERIFIED）**：`GameSession.swift:1202` 仍只看 `!isMap3DOpen`。
  - **L14-1 到 L14-10（P3）都還成立**：
    - 這一輪改到的程式只有 #1966 的 GamePresentation／App 和 #1984 的渡線那一段，碰不到這些地方。下面三處也照舊：
      - L14-8：`ContentView.swift:1595` 仍是 `stationMasterFrames.values.first`。
      - L14-5：`LinesPanel.swift:650` 仍只在 `.onAppear` 重算。
      - L14-10：`LineReportText.swift:157` 仍是 `acquisitions.first`。
    - L14-9：#1938 的第二批站房（`Map3DStationExteriorBatch2.swift:18-19`，OSM、ODbL）還沒接進遊戲。等它接進來時，Data Sources 的 OSM 那一項要和第一批一起補上。
  - L13-3 到 L13-10、L12-3、L11-8：沒有 PR 改到相關程式，都還成立。

## 二、發現

### L15-1（P2）#1985：「點車站快很多」和決策 644 相反

- **位置**：
  - `WhatsNew.swift` 122 那一筆的 fixes 第一條：「Tapping a station is much quicker, because its passenger flows are worked out faster.」／「點車站快很多，客流計算加速了。」
  - `.github/testflight-whats-new.md` 同一條，以及「請幫忙看」的「點幾個車站，看反應快不快」。
- **證據**：決策 644 的五個角度寫「玩家：地圖上的旅客去向弧線快一倍出現；路線的弧線從幾分鐘變幾秒；**點車站本身沒變**」。量到的數字（`docs/decisions/644.md` 量測表）：
  - 點車站時主執行緒本來就在 0.3 s 以內。
  - 變快的是背景算的旅客去向：南京復興 10.0 s → 5.2 s，文湖線整條 233.5 s → 5.4 s。
  - 面板的旅運量仍約 10 s。
- **為什麼是 P2**：
  - 「點車站就當機」的回報還沒有原因（決策 644 下一步 1，要當機紀錄）。
  - 說明寫「點車站快很多」，測試者容易以為點車站的問題修好了，回報的重點會跑掉。
  - 請測試者看「反應快不快」，看的是一個沒有改的東西。
- **修法**：123 的說明加一條更正，例如「更正上一版：點車站本身沒變；變快的是車站和路線的旅客去向弧線」。下一次寫說明時，每一條都對照決策的「玩家」那一行。

### L15-2（P3）#1985：英文和中文說的範圍不一樣

1. **改建**：
   - 英文：「A line you already bought, **such as** the Taoyuan Airport MRT, can be rebuilt as the real railway at Chang Gung Hospital」，讀起來像別的線也能改建。
   - 實際只有機捷有改建：`realRebuildTarget` 要 `RealBranchLine.overtakeStations(...)` 有站，而那份清單只有 `tymc:A`（`RealLineRebuild.swift:135-145`）。
   - 中文「已收購的機場捷運可選擇……」是對的。
   - 修法：英文改成「The Taoyuan Airport MRT you already bought can be rebuilt …」。
2. **3D 入口**：
   - 英文：「opens on the nearest track **when you zoom in** from the whole island」。
   - 決策 645 的 D5 是在 2D 縮到全台時「按 3D」，不是放大。
   - 中文「從全台進 3D」是對的。
   - 修法：英文改成「when you open it with the whole island in view」。
3. **台南**：英文「as since the undergrounding opened」文法不通。
   - 修法：改成「now underground, as they have been since the line moved underground」之類的句子。

### L15-3（P3）#1985：機捷那兩條，中文說得比實際滿

- **跟車那一條**：
  - 中文：「機場捷運不再互等卡死」。英文是過去式「which jammed」，沒有這麼滿。
  - 決策 652 量到的：現買仍有 7 列死結、舊線 3 列、改建 3 列（各一個十分鐘的 tick，自己解開）。
- **A12 那一條**：
  - 中文：「不再卡住直達車」。
  - 決策 652 量到的：現買傍晚仍有 6 班 環北↔A12 沒發。
  - 「多開約十四班」（26 → 12）只是「簡單＋行車控制」量到的；擬實規則下沒有差別（1 → 1）。
- **修法**：以後寫成「少卡很多」「大多不再卡住」，或在中文也照英文的說法。

### L15-4（P3）決策 652：「已知缺口」漏了兩件

決策 652 的「已知缺口與下一步」寫了改建的死結、改建要多等一天、傍晚的 A12↔環北、量法不對等、真實配線。另外兩件沒寫進去：

1. **舊存檔得不到改善**：
   - 「只改新買時鋪的路網，已經買下的存檔照舊」只寫在「改法」一節。
   - 121 以前就買了機捷的玩家，傍晚仍是 26 班沒發的那種路網，也沒有辦法換：改建只重鋪長庚一段（`RealLineRebuild.swift:571-626`）。
   - 這要列為缺口，讓規劃決定要不要補一個「重鋪 A12 渡線」的改建，或在說明裡寫清楚。
2. **擬實規則只量了現買**：
   - 決策 647 下一步 3（照決策 609 下一步 4）要求三個機捷世界和其他五線都量。
   - 決策 652 的擬實只有現買（1/333、140 誤點）。舊線、改建在擬實下沒有量。

### L15-5（P3）#1984：「迎著進站的車」那一組只放在 upperBound 那一側

- **位置**：`RealLineAcquisition.swift:1278-1281`。只有 `span.upperBound` 那一側會設成 facing。
- **問題**：
  - 「下一站那側」其實是靠 `runs.stops` 的排列方向決定的。
  - 機捷今天的排法剛好對（新測試確認 A13 在 A12 的前一站）。
  - 以後別的站加進 `facingTurnbackStations` 時，如果要的是另一側，程式不會報錯，只會默默放錯邊。
  - 那一組若被 guard 略過（放不下），也是默默退回舊的鋪法。
- **影響**：今天沒有；新測試會抓到機捷這一個。
- **修法**：下一個用到它的 PR，把站名清單改成「站名＋哪一側」，並加一個斷言：清單裡的每一站都真的鋪出了 facing 的那一組。

### L15-6（P3，核對過，UNVERIFIED 畫面）#1966：iPad 的版面規則看裝置種類，不看視窗大小

- **位置**：
  - `RailwayGameApp.swift:954-956`：`DeviceFamily.current` 只看 `userInterfaceIdiom`。
  - `DeviceFamily.swift:24-26`：`framesTheLessonsTowns`。
  - `DeviceFamily.swift:42-46`：`SheetHeight.offered`，只給 `.full`。
- **問題**：iPad 的 Slide Over、1/3 分割畫面或很小的台前調度視窗，其實是 iPhone 寬，卻照 iPad 處理：
  - 下半卡只開全高，地圖整個被蓋住。
  - 教學框兩座城鎮時會縮得很遠。決策 643 不在 iPhone 橫拿時框，就是因為縮得太遠時，第一段軌道會長到買不起。
- **修法**：
  - 下半卡的高度改看 `horizontalSizeClass`：寬度是 compact 時給半高和全高。
  - 框城鎮之前先算框好後的縮放；太遠就不框。
  - 決策 643 的缺口補上分割畫面和台前調度。

### L15-7（P3，核對過）#1966：「教學時不列月台」的範圍比決策寫的大

- **位置**：`NetworkSession.swift:1557`：`if networkMode == .platform, tutorial != nil { return [] }`。
- **問題**：
  - 決策 643 說的只是「教學蓋月台那一步」。
  - 但程式在每一課、每一步的月台模式都不列已有的月台，第 2 課以後也一樣。
  - 這時要從那裡移除月台做不到；移除模式還可以。
- **修法**：只在那一步的目標是蓋車站（`.buildStation`、`.pickPlatformSite`）時不列；或者把決策改成和程式一樣。

### L15-8（P3）#1966 的小事

1. **Mac 上叫 iPad**：
   - 在 Mac 上跑 iPad 版時，`DeviceFamily.current` 是 `.iPad`（程式註解也這樣寫）。
   - 設定會寫「跟隨 iPad」「iPad 在靜音模式時」，但 Mac 沒有靜音模式。
   - 修法：判斷 `ProcessInfo.processInfo.isiOSAppOnMac`，叫它 Mac。
2. **示範線的集合沒存檔**：`GameSession.swift:778` 的 `linesLaidByTheDemo` 不在存檔裡。示範局在卡片出現前存檔再讀回，示範線可能又跳出「單線」的待避卡。
3. **框鏡頭只框一次（UNVERIFIED，要 Simulator）**：`MapView.swift:1120` 只在 `tutorialFraming` 變的那一刻，用當下的 inset 框一次。如果建造面板的大小晚一個 frame 才量到，`framing()` 回 nil，鏡頭就不動了。
4. **註解放錯地方**：
   - `WebsiteScreenshotTests.swift:3165`：`testStartScreen` 插在 `testLessonCard` 和它的說明註解中間。
   - `IPadPlaytestFixesTests.swift:67`：「outside a lesson」那段註解放在 iPhone 的測試上。
5. **有些測試證明的比它說的少**：
   - `testTheCardLeavesOutTheLinesTheDemoLaid` 只呼叫靜態函式，沒有跑 session 裡填 `passingLoopHint` 的那條路。
   - A4 的位置測試是自己把圖層列的框傳進去。
6. **兩欄開始畫面沒有截圖審查**：決策 643 沒有寫 iPad 的截圖審查（ui-review 的第 3 級：新畫面版面）。下一個碰開始畫面的 PR 補拍。

### L15-9（P3）#1978 測試裡看到的兩件遊戲裡的事

- #1978 沒有放寬測試：蓋房子那條改成接受「1 building placed · …」的字尾，但讀檔後要和存檔前一字不差，反而更嚴。
- 測試註解裡記下了兩件玩家也會碰到的事，沒有人派：
  1. **iPad 開局卡頓**：iPad 開地圖頭幾個 frame 有 4.5 s 沒有畫面（full lane run 42444107304 的 trace），點下去的觸控就被取消了（`TutorialUITests.swift` 新加的重按）。這是效能問題，沒有量過。
  2. **新局在市中心蓋房子太貴**：A9 改成開在第一座城鎮的中央之後，在畫面正中間蓋一棟房子要收購辦公室，NT$ 940 萬，比新局的現金多（`StartSaveFlowSmokeTests.swift` 的註解）。玩家第一次試蓋房子就會被拒。要不要讓第一棟便宜一點、或讓拒絕的說明指去住宅區，給規劃決定。

### L15-10（P3）#1938：研究配方已編進 App，但還沒有人用

- `Map3DStationExteriorBatch2.swift`（935 行）在 GamePresentation 裡會跟著編譯，但 App 和其他程式都沒有引用它（grep 過）。
- 接進地圖時要做三件事：
  - 接上 L14-6、L14-7 的站房清單與場景範圍。
  - 照 L14-9 補 OSM 的用途。
  - 照決策 625 的那套驗收重拍截圖。

### 看過、沒有疑點的

- **#1984**：
  - `facingStops` 和 `turning` 一樣用 `runs.stops` 的站名查，索引一致。
  - `turnbacks` 型別多一個欄位，只在同一個函式裡用。
  - 報告測試的 `for … where` 迴圈最多 288 次（兩天），條件變假後不再推進時間，不會跑過頭。
  - 改建前的 `XCTUnwrap` 拿到的提議，若還是不能改，失敗訊息會帶 `session.message`。
- **#1985**：其他條目和 PR 一一對得上，兩種語言意思相同：
  - 高度格是 #1972（646），只調離地高度；清單由近到遠、灰掉、約幾公里外是 #1974（649）。
  - 3D 時鐘、夜窗是 #1962（645）；台南地下化是 #1977（650）；軌道編號避開站點與泡泡是 #1964（642）。
  - 「跟隨」與 ☰ 是 #1973（648）；iPad 是 #1966（643）。
  - 文湖線倍速是 #1967（637，一個 tick 快 11 倍）。
  - MapLibre 是 #1976（651，#4817 標籤紋理的競態）。
  - 路線頁、開線訊息、收購當天、等進路標籤是 #1959（635）。
  - 跟車是 #1961（636）；A12 是 #1984（652）。
  - `.github/testflight-whats-new.md` 和 App 卡片的條目相同；「遊戲選單」與「☰ 選單」的差別是 #1965 的字元規則造成的。
- **#1966**（子代理讀，跑了測試）：
  - iPhone 不受影響：框城鎮只在 iPad，下半卡在 iPhone 照舊半高與全高，兩欄在 non-compact 那一支，而且要 864 pt 寬。
  - `StartMenuEntry.columns` 每個按鈕剛好一次、順序不變。
  - `LessonResult.days` 第一天算 1，和每週挑戰的紀錄一致。
  - 均一票價的步進器從現行票價開始，也不會超出範圍。
  - 新的玩家文字兩種語言一致，只說控制做什麼。
- **#1938**：只有配方、測試、預覽圖與決策 626 的段落；App 沒有引用，不影響 122 的玩法。

## 三、驗證紀錄

- **建置**：`swift build --build-tests -Xswiftc -warnings-as-errors`（Linux，Swift 6.4.0，dc4a436）乾淨，**VERIFIED**。
- **測試**（`swift test --skip-build`，Linux，**VERIFIED**）：
  - 本 session：`TaoyuanAirportLineTests`（8 支，2 支要環境變數的跳過，含 #1984 的新測試）、`WhatsNewTests`（6 支）全過。
  - 子代理：`IPadPlaytestFixesTests`、`LanguageChoiceTests`、`LessonTests`、`PassingLoopHintTests`、`TutorialCardPlacementTests`、`TutorialSessionTests`、`DemoRealLinesTests`、`NetworkBuildingSessionTests`、`StartMenuTests`、`FareBandScaleTests`、`WeeklyChallengeTests`，共 250 支，0 失敗。
- **UNVERIFIED**：
  - 只讀了程式、沒有實際看過的：iPad 的畫面、下半卡、框鏡頭的時機、分割畫面與台前調度、Mac、UI 測試。這一輪沒有 macOS，也沒有跑 iOS workflow。
  - 決策 652 的量測數字是照它自己的報告引的，本 session 沒有重跑 `DepotReturnReportTests`（要環境變數，跑很久）。

## 四、下一輪

- **REVIEW-L16 從 #1986 起**（`main` dc4a436 之後）。
- 還沒派的：
  - P2：L15-1、L13-1、L13-2。L15-1 和 L13-1 都是說明要更正，可以一起寫進 123 的說明。
  - P3：L15-2 到 L15-10、L14-1 到 L14-10、L13-3 到 L13-10、L12-3、L11-8。
  - 之前的：L9-4、L9-5、L9-7、L10-4 到 L10-13。
- L15-4 的第 1 點（舊存檔得不到 A12 的新渡線）建議交給 TYMC-REBUILD-GAPS（決策 654），一起看要不要補。
