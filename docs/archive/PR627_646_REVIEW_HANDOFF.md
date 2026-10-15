# 交接：PR #627–#646 的審查與修正，以及上一輪延後的 UI 項目

Session：https://claude.ai/code/session_014pWMR25Y78kVonHB8gVbzf（2026-10-15），由派工 session_01AaAj4wvJMxJQuLWAoYu6S8 派出。從 `main` 9a88ef04（#645 的合併）開始。上一輪 #526–#626 見 [`PR526_626_REVIEW_HANDOFF.md`](PR526_626_REVIEW_HANDOFF.md)，再上一輪見 [`PR401_525_REVIEW_HANDOFF.md`](PR401_525_REVIEW_HANDOFF.md)。

作者原話：「之前 UI bug 的部分查看最新 main，然後順便做 PR review 到 PR 646。」

- 存檔版本、ARCHITECTURE 決策編號、golden schema 都沒有用到。
- GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改。
- 只開一個 PR：`claude/pr627-646-review-presentation`。GameCore 的候選發現查證後都不成立（第五節），所以沒有開 `claude/pr627-646-review-core`。

做法：

- 五個唯讀 agent 分工：
  - GameCore、存檔與 GamePresentation 邏輯：#627、#625、#630、#633、#637、#641；
  - App 介面：#626、#631、#632、#640、#642、#644、#645、#646；
  - UI 測試的修正有沒有掩蓋 App 問題：#628、#631、#638、#640、#644，以及關閉的 #629；
  - `main` 的 CI 紀錄；
  - 第一部分：上一輪延後的項目在最新 `main` 的狀態。
- 每個發現我自己讀程式確認。有兩項判定不成立（第五節）。
- GamePresentation 的每一項修正都先寫測試，確認修正前會失敗。
- App 的修正（SwiftUI）Linux 不能建置，交給 PR 的 iOS 建置與 `only_testing`。

協調：

- 遊戲規劃 session（session_018D6gYU1yiZMtxSmNNU1K17）回覆：U9、U10 已由上一輪審查 session 做好但沒推；U3、玩家文字、C6 沒人負責，交給這裡。美術外框這輪已全部合併，沒有後續會動 MapView、TutorialOverlay、PostcardView、DisplayText 的排程。
- 上一輪審查 session（session_01JXRA49xoPT4VypY1gTwWy2）把 U9、U10 推成 `claude/review-u9-u10`，這裡用 `cherry-pick -x` 收進來（dc51c5a9、2af4ba95、cf7208df）。
- 高鐵示範疊車 session（session_018mM2CNoNoGdKKrMTQJ5U6A）：多機廠的一鍵修正（第三節第 2 項）會碰到高鐵示範的路線，已告知；沒有改它的檔案。

## 第一部分：上一輪延後的 UI 項目，對照最新 `main`

| 項目 | 狀態 | 證據 |
| --- | --- | --- |
| B1 選車站時常常重新置中 | 已修 | #646（04f9d7b3）：`MapView.swift` 的 `keepSelectionClear` 只在 `PlanCamera.hides(_:under:)` 時移動，`keepingClear` 在可用區小於 44 pt 的軸上不動。Linux 測試 `MapFocusTests` |
| B2 站名蓋在鋪軌預覽上、夜間不變暗 | 已修 | #646（f0428535）：`MapLabelCanvas` 先畫站名，再畫 `MapArt.drawBuildMarks`；整層 `.colorMultiply(Palette.dimming(tint))`。測試 `DayNightTests` |
| B3 每次重繪算兩次候車數 | 已修 | #646（f0428535）：`MapView.swift` 的 `waitingCounts` 算一次；`MapCanvas ==` 只在畫站名時比較候車數 |
| #624 留下的兩件（選站時重新置中、站名蓋在預覽上） | 已修 | 同 B1、B2，#646 |
| U8 機廠：`trainsInDepot` 算到別條路線的機廠；S 形岔線失敗的原因寫錯 | 已修 | #633（c0d5cea6）：`DepotText.swift` 只算路線自己的機廠；`DepotYard` 新增 `.cannotBend`。測試 `DepotToolsTests` |
| U3 原因寫錯：玩家把這個時段的列數設低，卻說「受班距或軌道限制」 | 仍在 → **這裡修了** | 第三節第 1 項 |
| U3 跟隨列兩層前綴「尚未發車：列車已暫停：…」 | 仍在 → **這裡修了** | 第三節第 1 項 |
| U9 明信片每打一個字重繪一張 1200×1500 的圖；分享的圖可能和預覽不同 | 仍在 → **這裡收了** | 上一輪審查 session 的 dc51c5a9：開啟時固定世界，名字停 0.4 秒後才重繪，圖和卡片不一致時分享鈕關閉 |
| U10 教學「跳過這一步」只有 36 pt | 仍在（在展開的卡片上；收合膠囊上已經是 44 pt）→ **這裡收了** | 上一輪審查 session 的 2af4ba95：44 pt，橫拿時用負的上下間距維持外觀；收合膠囊不超出螢幕。測試 `TutorialCardPlacementTests` |
| U11 色盲配色的說明講了怎麼挑顏色 | 已修 | #599（749567f3）：`SettingsView.swift:120` 只剩一句效果 |
| 玩家文字：「Node #N／節點 #N」、「新節點」 | 仍在 → **這裡修了** | 第三節第 6 項 |
| 玩家文字：「Track #N／軌段 #N」 | 不適用 | `docs/UI_THEME.md` 第 6 條（決策 201）允許：軌段編號畫在地圖上，鋪軌訊息與進路選單用它 |
| 玩家文字：錯誤訊息帶原始 ID（「There is no train #3」等約 20 句） | 仍在 → **這裡修了** | 第三節第 5 項 |
| 玩家文字：「physical path／軌段與月台」 | 仍在 → **這裡修了** | 第三節第 7 項 |
| 玩家文字：沒在用的 xcstrings key | 仍在，沒修 | 第四節 |
| C6 縮放測試的第二下點擊可能蓋掉「一步放大一倍」的退步 | 仍在 → **這裡修了** | 第三節第 10 項 |
| C5 TestFlight 說明寫死版號 | 不改 | 上一輪已確定 |

## 一、合併狀態

範圍 #627–#646 共 20 個號碼：

| 狀態 | 數量 | 號碼 |
| --- | --- | --- |
| 已合併 | 18 | #627、#628、#630–#638、#640–#646 |
| 關閉沒合併 | 2 | #629、#639 |
| 還開著 | 0 | — |

- 每個已合併 PR 的 head commit 都用 `git merge-base --is-ancestor` 確認過在 `main` 上（先 `git fetch --unshallow`）。
- #629（RealWorld 暫停鍵的 `isHittable`）：作者 session 自己撤回，因為同樣的 `Activation point invalid` 也出現在沒改到的 `StartSaveFlowSmokeTests`。之後 #631 從 App 端修了版面跳動。
- #639（美術 session 的完整 lane 修正）：和 #638 重複，關閉。
- 範圍外：#625（高鐵示範機廠第三段）、#626（iPhone 左欄）在上一輪交接裡列為「開著」，這輪一起審查。#647（遊戲引擎 AI 工具研究，只改文件）還開著，不在範圍內。

## 二、`main` 的 CI 紅燈與根因（2026-10-14 18:50 – 2026-10-15 01:33 UTC）

| Workflow | run 數 | 成功 | 失敗 | 取消 | 在跑 |
| --- | --- | --- | --- | --- | --- |
| `ci.yml`（push） | 23 | 18 | **0** | 3 | 2（33da9547、9a88ef04） |
| `ios-build.yml` 完整 lane（7 個由 ios-full-lane.yml 啟動、1 個夜間） | 8 | 2 | **3** | 1 | 2（b4984255、9a88ef04） |
| `ios-full-lane.yml`（啟動器） | 23 | 22 | 0 | 1 | 0 |
| `release-archive.yml` 夜間 | 1 | 1（aafe7b13） | 0 | 0 | 0 |

取消的都是 concurrency 換掉的 run：`ci.yml` 的 7611fbdf（#624）、5978c286（#635）、382487fa（#641），每一批的下一個 run 都綠；`ios-build.yml` 的 38649976511（5790c463）在 237f194d 的完整 lane 開始時被取消。

失敗的全部是 `Xcode build (iOS Simulator)` 的 iPhone UI 測試，加上一次 iPad 的基礎設施錯誤：

| 合併（run） | 失敗 | 根因 | 現況 |
| --- | --- | --- | --- |
| #620（bd44ae21；38623673773） | `MapInteractionTests.swift:35` `testSwitchingFollowTargetWhilePausedCentersTheCamera`：列 `fleet.follow.Train 2` 一直沒出現 | 測試問題：#615 加了運用表按鈕，手機橫拿時那一列在畫面外，測試沒捲過去 | #628 已修（拖曳直到整列在畫面內） |
| 同上 | `MapInteractionTests.swift:188` `testTheStationTagsPencilRenamesAtOnce`：「A tap on Central…」 | App 問題：#603 的開局取景約 1 秒後重新取景，路網縮到角落 | #624 已修 |
| #622（8c604e88；38625196256） | `StartSaveFlowSmokeTests.swift:551`：暫停鍵 `Activation point invalid` | 狀態列版面在跳（#620 的落後點），點擊時暫停鍵在移動 | #631 從 App 端修了落後點。之後 021aff64、237f194d 的完整 lane 都綠。仍有其他會改寬度的元素（第四節） |
| #626（bf12187d；38641908091，夜間） | iPhone 3 支：`ToolbarSmokeTests.swift:149` Advanced 開關沒打開；`MapInteractionTests.swift:418` 擴地點到 Done；`RealWorldMapUITests.swift:272` 月台蓋不出來 | #626 的左欄改了點擊位置。前一支與第三支是測試問題；**第二支有 App 問題：擴地時鏡頭沒避開控制項**（第三節第 3 項） | #638 改測試；App 問題這裡修 |
| 同上，iPad job | `xcodebuild: Unable to find a device` | 基礎設施：runner 的 simulator 不見了 | 沒再出現 |

目前狀態（01:33 UTC）：

- `ci.yml`：最新完成的 924a956d（#644，38665217445）**綠**；33da9547、9a88ef04 在跑。
- 完整 lane：最後一次完成且綠的是 237f194d（#640，38655291347）。#633、#635、#637、#641、#642–#646 都還沒有完成的完整 lane；9a88ef04 的 38665547090 在跑。
- `release-archive.yml` 夜間：38644141148（aafe7b13）**綠**。

## 三、修的 bug（`claude/pr627-646-review-presentation`）

GamePresentation 的每一項都先寫了測試，確認修正前會失敗。

1. **路線列車卡把「玩家把這個時段設低」說成「受班距或軌道限制」；跟隨列重複前綴**（第一部分 U3，#565 起）：
   - 這個時段的列數等於 `planned`、比最忙時段少、而且這個時段沒有目標班距時，改說「路線這個時段設定只開 N 列」。
   - 跟隨列的 `.held` 只顯示原因本身，不再加「尚未發車：」。原因每一句都已經說了卡在哪、要做什麼。
   - 測試：`LineDispatchTextTests.testALevelSetLowNowIsNamedAsTheLinesOwnSetting`；`testAnUnplacedLineTrainIsToldToBePlacedAtTheFirstStop` 的期望值由「尚未發車：未放上軌道：…」改成「未放上軌道：…」（它固定的正是這個重複）。
2. **站長的一鍵修正把多機廠路線的其他機廠丟掉**（#633、#625 讓多機廠可以設；`LineLossFixes.swift`）：
   - 原本只看 `line.depot`（第一個）。「改用機廠 X」用 `setLineDepot` 取代整個清單；「列車改停兩端」只說第一個機廠，卻把全部移除；建議的「較近」機廠可能已經是路線自己的。
   - 現在比較路線所有機廠的距離；「改用機廠 X」把 X 加在清單最前面、保留其他（GameCore 依空車回送時間挑最近的機廠，決策 221）；「列車改停兩端」列出全部機廠。
   - 測試：`LineLossFixesTests.testALineWithSeveralDepotsKeepsThemWhenANearerOneIsAdded`（修正前清單只剩一個，失敗）；`testEmptyRunningToADepotMovesItOrKeepsTheTrainsAtTheEnds` 的期望值改成遠的機廠保留、指令是 `setLineDepots`。
3. **擴地時鏡頭沒避開控制項，下方那格在膠囊（含「結束」）底下**（#626、#644 之後，`MapView.swift` 的 `mapExpansionButton`）：
   - 3×3 格用整個畫面取景，沒有 `clearOf`。#638 改成點右邊那格繞過。
   - 現在用 `MapCover.framing(above:in:)`：控制項的取景，再加上擴地那一排頂端以下的整條底邊（膠囊開始選格後會沿著底邊變長）。
   - 測試：`MapFocusTests.testTheTilesForSaleShowAboveTheExpansionsRow`（修正前 API 不存在，編譯失敗）。App 的那一行 **UNVERIFIED LOCALLY**。
4. **地圖樣式選單在遊戲執行時每個 tick 重建**（#645，`StoredMapLayerSheet.mapStyleSection`）：
   - 原本圓形選單包在 `TickStable` 裡（決策 184 之後，TestFlight 54.1：打開的選單重建會捲回頂端、丟點擊）。搬進圖層清單時拿掉了，而清單讀 `session.world`，每 100 ms 重繪。
   - 現在整個 Section 再包回 `TickStable`，鍵是樣式、軌道樣式、有沒有真實鐵路、語言。
   - 沒有測試（App 的 SwiftUI），**UNVERIFIED LOCALLY**。UI 測試都先暫停，所以 CI 抓不到。
5. **錯誤訊息用內部編號稱呼東西**（第一部分玩家文字）：
   - 「There is no train #3」「Train #3 is already on the track」「Station #4 already has a freight yard」等約 20 句，改成「That train…／這列車…」「That station…／這個車站…」，「Trains #2 and #3」改成「Two trains／有兩列車」。`playerMessage` 拿不到世界，所以不寫名字；玩家剛點了那個東西，指的是哪個很清楚。
   - 測試：`LocalizationTests.testNoErrorNamesAThingByItsNumber`（修正前 19 種錯誤都失敗）；`DisplayTextTests`、`RouteEditingSessionTests`、`StationFacilitySessionTests`、`TrafficControlSessionTests` 的期望值跟著改。
6. **路網工具說「節點」**（第一部分玩家文字，`NetworkSession.swift`）：
   - 起點提示、「From Node #2」、「a new node／新節點」、高度設定「New nodes…／新節點：…」、「That node is gone」、轉轍器在坡上的提示。
   - 改成「the end of a track／既有軌道的端點」「a new point／新的一點」「New track…／新軌道：…」。
   - 測試：`NetworkBuildingSessionTests` 的三支（期望值改成新字，修正前失敗）。`TrackNodeID.displayText`（「Node #1」）只剩沒有被 App 用到的 `occupancyConflictTexts` 在用，沒改。
7. **「physical path／軌段與月台」**（第一部分玩家文字）：
   - 路線面板的「Automatic physical path」改成「Automatic route／自動選路」（xcstrings 的鍵跟著改；UI 測試 `ToolbarSmokeTests.swift` 兩處跟著改）。
   - 選了進路的訊息改成「Updated the tracks the line takes between these stops.／已更新路線在這兩站之間走的軌段。」（決策 201：地圖上的字是「軌段」；`RealWorldDemoTests` 檢查這一點）
   - 測試：`RoutePreviewTests.testTheSessionShowsTheLegJustPickedAndOnlyForTheSelectedLine` 新斷言（修正前失敗）。
8. **跟隨列在折返站把下一趟寫成「行駛中」**（#641 的 B5，`FollowBarText.swift`）：
   - B5 讓起訖站改成正在跑的那一段，但狀態仍拿第 0 站與最後一站比較。停在折返站時顯示「B → A」卻沒有「尚未發車」，列車卡卻說還沒出發。
   - 現在跟那一段的起站比較。
   - 測試：`TrainCardTests.testAtTheTurnTheFollowBarSaysTheTripBackHasNotLeft`（修正前 `running`）。
9. **運用表兩個問題**（#641 的 B10 與 B5，`TrainRoster.swift`）：
   - 跨午夜的那一趟同時算進昨天與今天的營收：今天的列只顯示，不再把票款算進今天。測試 `TrainRosterTests.testATripFromBeforeMidnightCountsItsFaresOnlyYesterday`（修正前今天多 500）。
   - 已跑完的來回一趟寫「West → West」（每條路線的每列車都是），計畫中的卻寫「A → B」。現在照計畫中的寫法，寫到折返的那一站。測試 `TrainRosterTests.testALoggedRoundTripNamesWhereItTurns`（修正前「West → West」）；`testEachTripIsACellOfItsTrainsRow` 原本固定「A → A」，改成「A → B」。
10. **縮放 UI 測試的第二下點擊可能蓋掉退步**（第一部分 C6，`MapInteractionTests.testZoomButtonsRemainUsableWithoutPinching`）：
    - 現在讀 `map.camera` 的縮放（UI 測試專用的讀數），等它穩定兩秒；點一下，沒動才補點；然後檢查變成剛好兩倍。
    - 要看 `only_testing`。
11. **「✓／✕ 不蓋在圓鈕上」的檢查變成空的**（#644、#645 之後，`RealWorldMapUITests.testTheTrackButtonsKeepTheirWordsOnALineAndTheConfirmIsClear`）：
    - 它只看 `map.layers`、`map.style`，不存在就跳過。#644 之後圖層條在時沒有 `map.layers`，#645 之後 `map.style` 在清單裡，所以什麼都沒檢查。
    - 現在檢查圖層條的每個鈕（`map.quickLayer.*`）或 `map.layers`，並要求至少有一個。
12. **U9、U10**：上一輪審查 session 的修正，見第一部分。
13. **狀態列註解過時**（#631，`HUDView.swift` `ViewingReadout`）：說「沒落後時什麼都不顯示」，現在一直留著位置。只改註解。

golden 與 replay：都只改 GamePresentation 與 App，GameCore 沒動，沒有值會變。

## 四、沒修，需要之後處理或只回報

- **狀態列其他會改寬度的元素**（#631 之後）：天氣圖示（每天變）、假日、破產膠囊、錢的位數、跟隨列車的速度與彎道限速、通知數。寬度一變，`ViewThatFits` 可能換版面，暫停鍵移位，就是 `Activation point invalid` 的來源之一。要整體決定狀態列怎麼排，屬於版面設計，交給美術 session。
- **#632 拖曳變淡可能卡住**：拖曳中 map 的 `UIViewRepresentable` 被拆掉，或從別處換工具時，沒有東西把 `isDrawingUnderTools` 改回來；直欄版面的復原／重做也不會變淡。低機率，回報。
- **#644 跟隨列在很窄時可能超出**：iPhone 橫拿、細節卡開著時，`ViewThatFits` 的最後一種也放不下會畫到卡片底下。沒法在 Linux 確認，回報。
- **#638 的 Advanced 開關**：測試註解說元素框到 x≈582，開關畫在 x≈735，可能是側欄內容的 accessibility frame 不對（VoiceOver 也會受影響）。要在 Simulator 上確認，回報。
- **#638 的月台測試**仍依賴真實地形，鏡頭再動可能又踩到坡。測試問題，回報。
- **沒在用的 xcstrings key**（約 13 個，例如「Following Train」「Over capacity」）：用文字比對找的，有些可能是插值的鍵；要用 Xcode 匯出確認，玩家看不到，不修。
- **`TutorialJourneyUITests.swift:399` 的 `map.style`**：已經不在地圖上，這一項永遠跳過，無害。
- **`unknownLinePattern` 的「pattern #3」**：是停站模式的序號，不是內部 ID，暫留。

## 五、審查後判定不成立

- **#637 機廠喚醒跨服務日可能漏掉**（`Depot.swift` `minutesUntilDepotMove`）：agent 擔心兩分鐘內跨到下一個服務日時沒看到隔天的時段。`serviceDay` 是世界的一個固定設定，每天一樣，`nextChange` 用除以一天的餘數算到隔天，不會漏。
- **#627 存檔 61**：查證沒有問題，見第六節。

## 六、存檔、遷移與 GameCore 檢查

- **存檔 61（#627，決策 221）**：
  - `currentVersion` 61；60→61 的遷移只是註解，對的：格式與 59 相同，只是讓 60 的 build 說「存檔比較新」，不會把多機廠讀成一個。
  - `v61-run-depots.json` 與 `v59-run-depots.json` 只差 `saveVersion`；v59 仍以 59 讀（`writing: false`）。README 與 `SavedGameTests` 正確。
  - 版本 60 但已帶 `"depots"` 的存檔（#611 合併到 #627 之間的 build 寫的）仍讀得進來：decoder 不依版本檢查。
- **#630 關路線帳清班次紀錄**：`setLineAccounts(false)` 清掉 `tripLog`；只有 decoder 會另外設 `lineAccounts`；遊戲中沒有關掉的入口（只有 `NewGame` 打開）。
- **#641 G8 二分搜尋**：每條路徑都保持依列車排序：讀檔由 `tripLogProblem` 檢查；唯一的插入在 `firstTripIndex(after:)`；`dropTrips` 用 `removeAll` 保持順序；列車 ID 不重用。比較方向與驗證一致。
- **#641 F5 明寫 null 拒絕**：受影響的鍵都只在有值時寫；`SaveFixtures/`、`GoldenScenarios/`、`ReplayFixtures/` 沒有這些鍵的 `null`。
- **#641 G3、G5、G9**：限速只在一段之內；不指定日期時結果不變；`Set` 只用來查詢。
- **#637**：`depotHours` 上限、班次紀錄的上限、靠左的搜尋快取鍵、`rerouted` 的秒數都正確。
- **#625 高鐵示範機廠**：建構依排序的鍵，決定性；過夜擺放依（出庫時間、列車）排序。
- **決定性、`Sendable`、失敗原子性**：沒有發現問題。
- **變數名稱遮住函式（Linux 能過、Xcode 不能）**：agent 用腳本掃過每個改到的檔案，沒有新的。這次自己的改動也避開了（`PostcardView` 的 `let world = world` 只遮住屬性，不是函式）。

## 七、審查過、沒有問題（摘要）

- **GameCore 與存檔**：#627、#630、#637。
- **GamePresentation**：#625、#633（除第三節第 2 項），#641（除第三節第 8、9 項）。
- **App**：#626、#631、#640、#642、#646；#632、#644 只有第四節的低機率項目；#645 除第三節第 4 項。
  - accessibility identifier：UI 測試用到的都還在（119 個加上動態組成的 8 個）。
  - 新的玩家字串兩種語言都有。
- **UI 測試修正**：#628 更嚴，沒有掩蓋；#631 是 App 修正，正確；#638 沒有放寬斷言，但第一支繞過了 App 問題（第三節第 3 項）。
- **文件與發版**：#634、#636、#643。沒有新增 `testflight.yml` 的觸發，沒有洩漏秘密。

## 八、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 每個新的 GamePresentation 測試修正前都跑過，確認失敗（第三節各項寫了修正前的結果；第 3 項是 API 不存在，編譯失敗）。
  - 修正後通過：`LineDispatchTextTests`、`FollowBar*`、`TrainCardTests`、`TrainRosterTests`、`DepartureBoardTests`、`LineLossFixesTests`、`MapFocusTests`、`LocalizationTests`、`DisplayTextTests`、`RouteEditingSessionTests`、`StationFacilitySessionTests`、`TrafficControlSessionTests`、`TrainControlTests`、`NetworkBuildingSessionTests`、`NetworkDisplayTests`、`RoutePreviewTests`、`TutorialCardPlacementTests`。
- **UNVERIFIED LOCALLY — requires macOS/Xcode CI**：
  - App 的 SwiftUI：`MapView.swift`（第 3、4 項）、`HUDView.swift` 的註解、`LinesPanel.swift`、`PostcardView.swift`、`TutorialOverlay.swift`、`Localizable.xcstrings`。
  - UI 測試：`MapInteractionTests`（第 10 項與擴地那支）、`RealWorldMapUITests`（第 11 項）、`LineRoutePreferenceUITests`（第 7 項）、教學測試（U10）。用 `ios-build.yml` 的 `only_testing` 跑，結果記在 PR。
- 其餘交給 CI。

## 總表

| | 發現 | 修了 | 沒修 |
| --- | --- | --- | --- |
| 第一部分：上一輪延後的項目 | 17 | 8（U3 兩件、U9、U10、錯誤訊息 ID、節點、physical path、C6；U9／U10 用上一輪的 commit） | 2（沒在用的 xcstrings key；C5 照決定不改）。另 6 項在 `main` 上已修（B1、B2、B3、#624 的兩件算一項、U8、U11），1 項不適用（Track #） |
| 第二部分 GameCore（模擬、存檔） | 1 | 0 | 0（判定不成立，第五節） |
| 第二部分 GamePresentation | 4 | 4（第三節第 2、8、9 兩項） | 0 |
| 第二部分 App 與 UI 測試 | 10 | 4（第三節第 3、4、11、13 項） | 6（狀態列寬度、拖曳變淡、跟隨列超出、Advanced 開關的框、月台測試依賴地形、教學測試的 `map.style`） |
| **合計（第二部分）** | **15** | **8** | **6** |

第二部分另有 1 項判定不成立（第五節），不計入「沒修」。第一部分的「修了」與第二部分分開計算：兩部分合計修了 16 項，沒修 8 項（含 C5 與 xcstrings key）。
