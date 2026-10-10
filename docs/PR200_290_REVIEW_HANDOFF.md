# 交接：PR #200–#318 的審查與修正

Session：`claude/railway-game-ios-pr-review-hzdbwt`（2026-10-09～10）。分支從 `main` 6b43d31 開始，收工前合併了 `main` dedbb659（#291–#296）。存檔版本、ARCHITECTURE 決策編號、golden schema 都沒有用到；GoldenScenarios、ReplayFixtures、SaveFixtures 的期望值都沒有改。

## 一、合併狀態

- #200–#290（#231 是工作登記 issue，不是 PR）除了 #289 以外都已合併。每個 head commit 都用 `git merge-base --is-ancestor` 確認過，都在 `main` 上。
  - 注意：clone 是淺層的，會讓 #200–#218 看起來不在 `main`；`git fetch --unshallow` 之後才正確。
  - #259、#260、#262 合併到中間的分支，再由 #266 一起進 `main`。
- #289（新建模擬器的實驗）是刻意關閉、沒有合併：量到的開機時間沒有變快（作者在 PR 上留言說明）。沒有遺漏的內容，不用補 PR。

## 二、`main` 的 CI 紅燈與根因

| 合併 | 失敗 | 根因 | 現況 |
| --- | --- | --- | --- |
| #202 | `LineRoutePreferenceUITests` 啟動逾時 | #200 加了背景音樂，#202 起 `-ui-testing` 會清掉設定，所以 UI 測試全程播音樂，模擬器搶不到 CPU（#215 的調查） | #215 已修 |
| #205 | `testConstructionHUDAppearsDuringTrackPreview` | 失敗時的 UI 層級和錄影都顯示：點了 Network，畫面上選中的仍是 Select，所以地圖上的兩下是在 Select 工具下點的。點擊被誰吞掉，現存資料判斷不出來；當時 runner 正被音樂佔用 CPU | 之後完整 lane 都通過；該工具列已被 #267 換掉 |
| #221 | `LineRoutePreferenceUITests` 跑滿 8 分鐘被中止 | 實景示範地圖每一格都在主執行緒算，每次 XCTest 查詢要 5–10 秒 | 由 #230（背景計算）、#272（O(n²) 的候車計數）修好 |
| #237 | iPhone：房子沒蓋成 | 點在 (0.5, 0.3) 的那一下沒有交給建物工具 | #247 已修 |
| #237 | iPad：`Unable to find a device` | xcodebuild 自己的裝置清單裡一台模擬器都沒有（simctl 剛開好的 iPad 也不在），那個 runner 上 Xcode 的裝置探索沒有載入 runtime | 只出現一次。可以考慮在 xcodebuild 之前先跑 `-showdestinations` 檢查 |
| #245 | App 編譯失敗、在地化匯出失敗 | `PopulationLegendView` 少了 `import GameCore` | #249／#250 已修 |
| #246、#248（夜間）、#253 | 房子測試：點的那一下沒選到可以蓋的位置 | 先是點的位置不對（#247），之後是小地圖蓋住地圖中央（#272） | 已修 |
| #261 | `start.realWorldDemo` 點不到；路線那一列始終沒有整列進入畫面 | 決策 106 改了版面，測試卻還從畫面中央開始捲動 | #272 已修 |
| #282、#288、#290 | `testNavigationDoesNotChooseConstructionPoints` 找不到「Zoom in」 | #281（決策 123）讓手機上的縮放鈕讓位給寬卡片，測試卻在選了工具、卡片打開時去讀它 | #296 已修（本分支原本也做了同樣的修正，合併時改用 #296 的版本） |
| #290（push） | `RealWorldMapUITests.testARealWorldGameStartsFromAPlaceAndIsSavedAsOne`：按「繼續」後沒有回到實景地圖 | 推測：從遊戲選單按「回到開始畫面」時，選單的呈現視窗還沒收起，吞掉了「繼續」那一下。依據是失敗時的層級裡多了一個全螢幕的第二個 Window，錄影第 44 秒選單還在淡出。在 Linux 上用真實資料模擬「實景新遊戲 → 自動存檔 → 繼續」，存讀都正常 | **沒修**。同一個 commit 的夜間 run 這項通過。錄影在按下前就截斷了，證據中等 |
| #290（夜間） | `LineRoutePreferenceUITests`：15 秒內實景示範按鈕一直不能按 | 實景資料在背景讀超過 15 秒（自 #287 起多讀 12 MB 的高度檔）；同一個 commit 的 push run 這項通過 | **沒修，原因還沒查到**。下一步看那次 run 從 App 啟動到資料讀完各步的時間 |

CI（Linux）、Wasm Probe、App Localization（#245 那次除外）在範圍內都是綠的；紅燈只出在 iOS App Build 的完整 UI lane。

## 三、本分支修的 bug（每項都先寫了重現測試，確認修之前會失敗）

1. **實景地圖的長直線軌道蓋不起來**（`NetworkSession.swift` 的 `EdgePlan.build`）：直線只讀了兩端所在區塊的地面，GameCore 卻每 16 m 量一次地面，所以中間經過的區塊會報 `groundNotLoaded`。現在改成讀 survey 實際取樣的每一點。測試：`HeightGridTests.testAStraightTrackReadsTheGroundOfTheBlocksItCrosses`。
2. **退出轉乘群組後存檔讀不回來**（`Boarding.abandonStrandedRiders`、`abandonUnservedPassengers`）：已經在車上、後面還要步行轉乘的乘客，以及走那段步行的 OD 路線平衡，都留了下來。現在步行接不上時，乘客算放棄，路線平衡丟掉。測試：`PassengerWalkTransferTests.testRidersWhoseWalkGoesLeaveWhenTheGroupGoes`。
3. **`dailyRiders` 目標讀錯日子**（`Goals.judgeScenario`）：一次 advance 跳過午夜的閒置分鐘時，`lastDayTrips()` 讀到的是前天，和逐分鐘推進的結果不同。現在改讀被結算的那一天。測試：`GoalsTests.testDailyRidersAreJudgedOnTheDayThatEndedHoweverTimeIsAdvanced`。
4. **劇本在未結算的午夜開始，存檔讀不回來**：前一天的結算被當成劇本的第一天來判定，可能直接完成或失敗。現在 `day < startDay` 時不判定。測試：`GoalsTests.testAScenarioStartedAtAnUnsettledMidnightKeepsALoadableSave`。
5. **損壞的存檔讓 App 當掉，而不是被拒絕**：自動區段的長度、建物的建造費加土地費、同一列車的車廂紀錄，三處相加會溢位而 trap。現在先限制每一項的範圍再相加。測試加在 `TrackSectionTests`、`PlacedBuildingTests`、`AssetAccountsTests`。
6. **挑戰紀錄在劇本結束後又「刷新紀錄」**（`ChallengeRecords.record`）：每次自動存檔都會重記一次，乘客數卻取自存檔前一天。現在改用完成那天的乘客數。測試：`WeeklyChallengeTests.testAResultKeepsTheRidersOfItsDay`。
7. **高度檔晚到時，軌道預覽沒有更新**：預覽快取的 key 裡沒有 `heights`，所以一直顯示「地面還沒讀入」。現在 `heights` 一改就清掉快取。測試：`HeightGridTests.testThePreviewIsWorkedOutAgainWhenTheHeightsArrive`。
8. **全島地圖新車站說「800 公尺內沒有人」**：土地在建站指令之後才讀入，訊息卻在指令內就寫好了；點月台位置時的腹地人數也是 0。現在先讀入土地再寫訊息，點選月台位置時也先讀入那裡的土地，和建物工具的做法一樣。測試：`WholeTaiwanTests.testAFarStationSaysWhoItReachesFromItsOwnLand`。
9. **`setGround` 能讓已有軌道的平面世界開啟地面**：結果存檔讀不回來。現在和 `mapGround()` 一樣拒絕。目前沒有 App 路徑會這樣呼叫。測試加在 `GroundTests`。
10. **分區回傳的變更格數算錯**：在水上被清掉的格子沒有算進去，數字甚至會是負的。只影響訊息裡的數字。測試：`ZoningTests.testCellsClearedOnWaterCountAsChanged`。
11. **站長的建議沒顯示就被標成已讀**（`StationMasterView`，SwiftUI）：手機打開側邊面板時泡泡放不下，建議卻被標成已說過。現在等泡泡有空間時再說。**UNVERIFIED LOCALLY**，Linux 不能建置 App，要看 CI。

## 四、沒修、需要作者決定的項目

1. **反轉一條在營運中的路線會讓它停擺**（`GameWorld.reverseLineStops`，路線面板可以直接按）。**已處理**：作者選 (a)，決策 134。
   - 列車跑完舊的一趟，會停在舊的起站，也就是現在的終點站。發車只接受停在第一站的列車，所以之後再也不發車。
   - 同時，等這條線的乘客會全部被放棄，這和文件寫的「停靠的站和以前一樣」矛盾。
   - 環狀線還有一個問題：已發出的列車，方向標籤會和實際行駛方向相反。
   - 選項：
     - (a) 有列車的路線不允許反轉，按鈕停用並說明原因（最簡單，**建議**）。
     - (b) 允許從任一端發車，同時把乘客與列車的方向標籤一起翻轉（體驗最好，改動大）。
     - (c) 反轉時把列車撤下，交給玩家重新配置。
   - 曾試做過只翻轉乘客方向的版本；因為整條線停擺，這個修正單獨沒有意義，已經撤回。
2. **切開自動結構的軌道時，各段重算區段**：這是決策 124 刻意的設計。後果有兩個：
   - 全島地圖上水域晚讀入時，原本建好的邊可能切不開（`trackOverWater`）。
   - 隧道切開後可能變成明挖，上面公司的建物卻沒有被拆除。
   - 選項：保留原區段只在切點分開；或在明挖段碰到建物時拒絕切開。
3. **縮放鈕讓位（決策 123）**：
   - 在 iPad 也會觸發：11" 橫拿開側邊面板（430 > 1180/3）、直拿開卡片（350 > 820/3）。決策寫的卻是「iPad 照舊」。
   - VoiceOver 和切換控制的使用者，在卡片打開時沒有任何縮放方式（地圖沒有 accessibility zoom action）。
   - 建議：開著 VoiceOver 或切換控制時保留縮放鈕；判斷條件改成「留給地圖的寬度」，或只在手機上生效。
4. **拖曳鋪軌時的邊緣捲動區在卡片和工具欄底下**：手指要越過卡片，伸到螢幕實體邊緣才會開始捲動。建議改用扣掉 inset 後的區域來量。
5. **`annualNetProfit` 目標會算進劇本開始前就結算的年度**：目前內建的劇本都從新遊戲開始，所以沒有影響。這可能是刻意的設計。
6. **地價圖層不畫只因臨水而加價的空格**：可能是全島地圖為了省資料刻意不畫。
7. **效能**：MapView 用 `Task.detached` 計算 LineMap、CityMap、CitySkyline。被取代的計算不會停，會跑完才丟掉。要真的停下來，得在 GamePresentation 的這些初始化裡加入取消檢查。
8. 第二節最後兩項 UI 測試紅燈（實景地圖的「繼續」、示範按鈕 15 秒內不能按）的根因，還要再查。

## 五、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 無警告。這是合併 `main` dedbb659 之後的結果。
  - 改到的測試類別共 158 項全部通過：`HeightGridTests`、`PassengerWalkTransferTests`、`TransferGroupTests`、`GoalsTests`、`TrackSectionTests`、`PlacedBuildingTests`、`AssetAccountsTests`、`WeeklyChallengeTests`、`WholeTaiwanTests`、`StationSitingTests`、`GroundTests`、`ZoningTests`、`ZoningSessionTests`、`SavedGameTests`、`ReplayFixtureTests`、`StationRemovalTests`、`NetworkBuildingSessionTests` 等。
  - 每個新測試都先在修正前跑過，確認會失敗（存檔溢位那三項在修正前是當掉）。
- **campaign shard**：第一次跑到一半時容器重啟，中斷了。收工時另外單獨跑了 `GoldenScenarioTests`、`PassengerPropertyTests`、`BoardingPropertyTests`，結果寫在 PR 裡。其餘交給 CI。
- **UNVERIFIED LOCALLY — requires macOS/Xcode CI**：`StationMasterView` 的修正，要看分支上 `ios-build.yml` 的 workflow_dispatch run。
- 本機用過的工具：審查用的五個只讀 agent；`gh api` 讀 CI log 與 artifact；xcresult 用 sqlite 加 zstd 解開來讀 UI 層級，用 ffmpeg 擷取錄影畫面。

## 六、延長到 #291–#296（第二個 PR，在 #297 合併之後）

**合併狀態**：#291–#296 都已合併，head commit 都在 `main` 上。

**main 的 CI**：
- #291 合併後的完整 lane 有兩項紅燈：
  - 縮放測試（#296 已修）。
  - `TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds`：H3 的縱斷面卡片在手機上太高，#293 改成收起後已修。
- #293 合併後只剩縮放測試紅燈。
- #292、#294、#295 的 iOS run 被下一次推送取消，CI（Linux）與 Wasm Probe 都是綠的。
- #290 時兩個沒查到根因的紅燈（實景地圖「繼續」、示範按鈕 15 秒），在 #291、#293 的完整 lane 都沒有再出現。
  - 量測：示範按鈕在通過的 run 裡，啟動後 20–27 秒才變成可按；失敗那次超過 38 秒。
  - 同一份資料，Linux Debug 只要 1.1 秒就讀完（各檔：population 0.05 s、places 0.51 s、water 0.38 s、heights 0.03 s、railways 0.14 s）。
  - 所以慢的不是解碼本身，可能是模擬器上的 I/O 或主執行緒排程。
  - 要查到底，得在 App 裡記錄讀取各段的時間，從 xcresult 的 App stdout 讀出來。

**修的 bug（各附重現測試，確認修之前會失敗）**：
1. **出售建物時，居民被搬到另一棟公司建物仍佔用的格子**（`BuildingSale.handOverCell`）：違反決策 95（城市不在被公司建物佔用的格子上建）。現在改找建物底下其他未被佔用的陸地格；都沒有時，居民離開，和城市成長時的做法一樣。測試：`BuildingSaleTests.testPeopleDoNotMoveOntoACellAnotherOfTheCompanysBuildingsClaims`。
2. **邊坡與縱斷面的水域畫錯位置**：最後一段較短的 16 m 被畫成「中點前後各 8 m」，蓋到前一段。現在照 GameCore 的切法，每段從起點起算，16 m 一段。測試：`TerrainPresentationTests.testTheLastShortLengthsSlopeCoversOnlyThatLength`。
3. **大地圖的高度圖層，東、南邊留下一條空白**：格數不是 step 的倍數時，最後幾格沒有角點。測試：`TerrainPresentationTests.testTheLastCellsOfALargeMapHaveTheirHeight`。
4. （SwiftUI）**自由模式的經營報表也寫著所得稅的規則**，但自由模式不會課稅。現在只在經營模式顯示。**UNVERIFIED LOCALLY**。

**需要作者決定**：
- 所得稅（決策 131）讓存檔多了 `dailyTax`、`incomeTax`、`taxCost`，版本卻仍是 29。#294 到 #295 之間的版本讀到這種存檔時，可能報出一般的「資料損壞」錯誤，而不是「存檔較新」，也可能悄悄丟掉稅額。
  - 決策 67（貸款）當初也沒有升版，可以沿用這個慣例。
  - 只有在 #294 之後、#295 之前有發出過版本時才有影響。
  - 選項：升到 30（不需要 migration，只加一筆 fixture），或維持現狀。
  - **已處理**：#300（決策 133）把存檔升到 30，不再另外升版；說明補在 `SavedGame` 的版本 30 與決策 131、134。

**驗證**：
- **VERIFIED（本機 Linux）**：建置沒有警告。改到的類別都通過：`BuildingSale*`、`CompanyBuildings*`、`SavedGameTests`、`TerrainPresentationTests`、`HeightGridTests`。
- #297 那份修正的 golden（24 項）、`PassengerPropertyTests`、`BoardingPropertyTests` 都已在本機通過，結果貼在 #297 的留言。
- 其餘交給 CI。

## 七、延長到 #298–#302，並對 #200–#296 做第二輪（第三個 PR）

**合併狀態**：#298、#300、#301、#302 都已合併，head 都在 `main` 上。#303 只改版本號（0.5.0）。

**作者已決定的**：
- 有列車的路線不能反轉（決策 134，#301）。
- 所得稅不升存檔版本，沿用決策 67 的慣例（#301 的說明）。

**main 的 CI**：
- #298–#302 合併後，CI（Linux）與 Wasm Probe 都是綠的。
- iOS run 都被下一次推送取消；#303 的完整 lane 在交接時還在跑。
- #299 合併後的完整 lane 27 項全綠，也包括之前查不出根因的實景地圖「繼續」與示範按鈕兩項。

**修的 bug（都先寫測試，確認修之前會失敗）**：
1. **固定班次的列車跑到一半時，改站序或拆站讓乘客被丟下**（決策 133）：
   - `setLineStops` 與 `removeStation` 會清掉班次。之後判斷列車方向時，退回「來回一趟」的規則：要去後半段的乘客被放棄，後半段也不再載客。
   - `setLineRuns` 本來就會在列車行駛中拒絕；現在這兩條路徑也一樣拒絕。
   - 測試：`LineRunsTests.testRunsAreNotEndedUnderATrainOnOne`。
2. **時鐘接近時間盡頭時，固定班次會溢位當掉**：載入存檔與推進時間都會。
   - 現在放不進時鐘的那一天直接跳過，載入時的檢查改用不會溢位的加法。
   - 測試：`LineRunsTests.testRunsNearTheEndOfTimeDoNotOverflow`。
3. **全島地圖按復原後，建物蓋在沒讀入的土地上**：
   - 結果是沒有收購城市建物，地價也算成空地的價。
   - 現在建造時，在同一個編輯裡重新讀入土地；復原後，也重讀選好位置的土地。
   - 測試：`WholeTaiwanTests.testABuildingAfterAnUndoStillStandsOnItsLand`。
4. **拖曳鋪軌被取消後，留下一段玩家沒選過的軌道**：
   - 拖曳從別段軌道開始、換了起點，取消時卻把舊終點還原回來。
   - 現在新起點保留，不留終點。
   - 測試：`NetworkDragTests.testACancelledDragFromOtherTrackLeavesNoStretchUnpicked`。
5. **選路線停靠站時，同一站點兩次沒有說明**：失敗訊息在同一次點擊裡就被清掉。測試加在 `LineDraftRouteTests`。
6. **`expandLand` 接受超出世界邊界的格子**，結果存檔讀不回來。App 的匯入會裁切到邊界，所以只有直接呼叫才會遇到。測試加在 `LandBlocksTests`。

**沒修、需要作者決定**：
- **決策 134 可以從「移動站序」繞過**（2026-10-10 作者決定：排進路線圖當正式功能，不當 bug 修，見 `docs/ROADMAP.md` 的 Q4）：
  - 兩站的線把第 0 站往後移一格，就等於反轉；任何改到第一站的編輯也一樣（拆掉第一站、在第一站前插站）。
  - 有列車時，這些編輯同樣會讓列車停在舊起站、不再發車。
  - 選項：
    - (a) 有列車時，不允許改動第一站，這是決策 134 的延伸。
    - (b) 允許列車從任一端發車。
- **自由模式免費蓋的建物，切到經營模式後出售會憑空賺錢**（以土地價出售），也會收租金。
  - App 不允許從自由模式切回經營模式，所以玩家碰不到，只有 GameCore API 會遇到。
  - 選項：沒有資產紀錄的建物以 0 元出售；或讓 GameCore 也禁止自由模式切回經營模式。
- **負餘額的自由模式不能蓋、也不能拆免費的建物**：`spend(0)` 在餘額小於 0 時會拒絕。App 不允許負餘額切到自由模式，所以玩家碰不到。

**驗證**：
- **VERIFIED（本機 Linux）**：建置沒有警告。改到的類別都通過：`LineRunsTests`、`StationRemoval*`、`LineEditing*`、`RouteEditing*`、`RealWorldDemo*`、`WholeTaiwanTests`、`Building*`、`UndoSessionTests`、`NetworkDragTests`、`NetworkBuildingSessionTests`、`LineDraftRouteTests`、`LandBlocksTests`、`SparseCityLand*`。
- golden、replay、存檔、`LineDispatchPropertyTests` 的結果寫在 PR 裡。
- 其餘交給 CI。

## 八、延長到 #303–#306，並對 #200–#302 做第三輪（第四個 PR）

**合併狀態**：#303（版本號 0.5.0）、#304（第三個 PR）、#305（決策 136：車站客源在背景算、手機畫軌道時細節卡收起）、#306（路線圖 Q4）都已合併，head 都在 `main` 上。

**main 的 CI**：#304 與 #305 合併後 CI（Linux）是綠的。#304 的 PR 上 campaigns-6 有一次是 SwiftPM 在跑任何測試之前 segfault，重跑一次就過（已在 PR 留言）。

**修的 CI 問題（工作流程與腳本）**：
1. **只改 App 內附資料時，Swift 測試不會跑**：套件的測試會讀 `RailwayGameApp/Resources/`（實景網格、鐵路與時刻表、授權檔），但 `swift-shards.sh` 的 `relevant_paths` 不算它，閘門直接放行。現在算進去，selftest 也加了兩個例子。
2. **按鈕消失檢查找不到鐵軌工具的「完成」鈕**：`ui-smoke-missing-button.sh` 要找的那行已經改成 `doneButton(compact: compact)`，舊的字串比對永遠找不到，檢查等於失效。現在用正規表示式只認一行，找到的不是剛好一行就停止。
3. **iPad 教學測試漏掉幾個教學會指到的畫面**：`ios-build.yml` 偵測教學畫面的清單補上 `BuildToolRail`、`LinesPanel`、`TrainControls`、`StartView`。
4. **手動與夜間的 release archive 會互相取消**：兩者同一個 concurrency group。現在只有 PR 依分支分組並取消舊的，其他每次 run 自己一組。
- 同一批也把誤提交的 `tools/real-world-population/__pycache__/*.pyc` 從版本控制移除（已在 `.gitignore`）。

**修的 bug**：
1. **有班次的路線在列車跑班次時改停靠，訊息叫玩家「先停止服務」**，但路線的列車不能停止服務（`trainOnLine`）。這是 #304 新加的拒絕帶出的錯誤訊息。現在說「等它跑完，或先讓它離開路線」，和拆站時的訊息一致。先寫的測試：`LineEditingTests.testNewStopsUnderARunSayWhatCanBeDone`（修之前失敗）。
2. **車站面板的客源在改軌道後不會更新**（#305 的快取）：全網路徑模式下，結果還依路網、路線性能與路徑偏好、列車容量、轉乘群組決定，但快取的鍵沒有這些。拆掉路線走的軌道或改路線速度後，旅次與每小時圖要到隔天才更新，暫停時就一直不更新。現在鍵包含它們。App 的 SwiftUI 檔，Linux 上不能建置：把鍵單獨抽出來對 GameCore 型別檢查通過，畫面行為 UNVERIFIED LOCALLY。

**沒修，只回報**：
- **手機上只選了起點時，地圖上沒有 ✕**：決策 136 第 4 點已寫明是設計（打開卡片按「清除」或按「完成」）。如果想要地圖上也能取消，可以在只有起點時顯示只有 ✕ 的小膠囊；這是設計選擇，留給作者。
- **車站客源的背景計算不會被取消**：換車站或關面板時，舊的計算會跑完才丟掉結果。實景地圖、全網路徑、快速播放下，如果一次計算超過一個遊戲日（約 14 秒），面板可能一直停在「正在計算客流…」。沒有量到實際時間，先不改。
- **`ios-build.yml` 的 `paths-ignore: "**/*.md"` 也會忽略 App 內附的 `RailwayGameApp/Resources/Licenses/MapLibre-iOS-LICENSE.md`**：只改這個檔不會跑 iOS 建置。影響很小（授權檔很少改），先不改。

**驗證**：
- **VERIFIED（本機 Linux）**：`swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告；`LineEditingTests`、`LineSessionTests`、`RingLineSessionTests`、`LineStaffingTests` 通過；`swift-shards.sh selftest` 通過；改到的 YAML 都能解析，`bash -n` 通過；按鈕消失檢查的正規表示式在目前的 `BuildToolRail.swift` 上剛好刪掉那一行。
- **UNVERIFIED LOCALLY**：`StationPanel.swift` 的畫面行為、`ios-build.yml` 與 `release-archive.yml` 的實際觸發（要 macOS CI）。

## 九、延長到 #307–#318（第五個 PR）

**合併狀態**：#307–#318 都已合併，head 都在 `main` 上。
- #310 是空的 PR（0 個檔案，內容已由 #309 合併），關閉沒合併，不用補。
- #315 先合併進 #314 的分支，再隨 #314 進 `main`。

**main 的 CI**：
- Linux CI 在每次合併後都是綠的。
- #313、#314 合併後，iOS App Build 紅在同一個 UI 測試：`LineRoutePreferenceUITests.testALineLegCanSelectAPhysicalPlatform`。
  - 根因：狀態訊息 4 秒後自己消失，測試先找到「Dismiss message」按鈕，再讀它的位置；按鈕在兩步之間消失，讀位置就失敗。
  - 另一個 session 已在 #318 改成對每個按鈕拍快照，並在 #319 的分支上用完整 UI 測試驗證過。
- 之後 `main` 的 iOS run 都被新推送取消，要看最新一次完整的 run。
- 我手動觸發的 ios-build（2b08a2e7，含按鈕消失檢查）全綠：#307 修的檢查在 macOS CI 上真的刪掉了「完成」鈕，UI 測試也照預期失敗。

**修的 bug（GameCore 與 GamePresentation 都先寫測試，確認修之前會失敗）**：
1. **月台位置的「外地連絡站」說明可能說錯**（#308，決策 137）：說明看的是點到的軌道，但月台會接到選單選的車站，或蓋在那一段的中點。現在看實際會接到的車站，或那一段的中點。測試：`StationSitingTests.testAStationByTheEdgeSaysItIsAnOutsideConnection`。
2. **沒有改變世界的動作也會丟掉背景算的 tick**（#317，決策 143）：再點一次目前的速度、在一般地圖上選建地，都會把世界原樣寫回，6000× 時每點一下就少走一格遊戲時間。現在只有真的改變時才寫。測試：`GameLoopTests.testWhatChangesNothingDoesNotDropTheLoopTick`。
3. **分區工具的城市需求在 −1 到 −9（千分之一）時顯示「0%」**（#312，決策 139）：需求是負的就不蓋，但畫面寫 0%，說明又說「需求不是負的時才會蓋」。現在百分比往遠離零的方向進位。測試：`ZoningSessionTests.testTheZoningToolShowsTheCitysDemand`。
4. **全島地圖讀進新土地會被當成城市成長**（#312，決策 139）：需求比較的是土地現在的比例和當初記下的比例，所以之後讀進的每一塊都會讓需求亂跳。實測讀進一個辦公區，住宅需求就變 +100%、辦公 −100%。
   - 現在 `expandLand` 把新土地依居民數併進記下的比例；`setLandOnDemand` 會清掉舊土地的比例。
   - 沒有 golden、存檔或 replay 會按需讀土地。
   - 測試：`CityDemandTests.testLandReadInIsNotTheCityGrowing`。
5. **賣掉的建物，人搬到的格子會落在別的公司建物方塊裡**（#315，決策 142 與 130）：判斷時用的是那格現在的方塊（空格是 D1），但城市接著蓋的建物可能更密（D2）。現在用搬進去之後那棟建物的方塊來判斷。測試：`CityFootprintsTests.testASoldBuildingsPeopleDoNotMoveIntoAnotherBuildingsSquare`。
6. **成長動畫把讀進的土地當成新蓋的建物**（#313、#314，決策 140）：
   - 地圖只在土地或建物改變時才重做天際線，所以平靜的一晚之後，隔天早上讀進的土地（全島）或出售交還的格子，會被當成新建物升起。
   - 現在天際線的鍵加上遊戲日。
   - App 的 SwiftUI 檔：鍵單獨抽出來對 GameCore 型別檢查通過，畫面 UNVERIFIED LOCALLY。

**審查過、沒有問題**：
- #309（只改文件）。
- #311（決策 138）的三個快取：每條路線服務有沒有開車、交通點、站間股道數。它們的依賴都只會被指令改變，快取只活在一次 `advance` 裡。
- #316（跟車放行不再建集合）：子代理做了三種差分測試，新舊結果逐位元相同。
- #318（建地自動對齊）。

**沒修，需要作者決定**：
- **地圖邊緣兩站的短程接駁會賺錢**（#308，決策 137）：兩端都是外地連絡站時完全不套距離比例，300 m 的兩站線每天各 3,120 人次、營業利益約 +$14,000。正好是決策 137 想擋的情況。
  - 選項：
    - (a) 只有一端是外地連絡站時才不套距離比例。
    - (b) 兩端都是時，外地附加費只收一次或不收。
    - (c) 維持現狀。
  - 建議 (a)。會改到外地旅客的分布，要重量 `BalanceReportTests`。
- **空白地圖挑戰的目標是決策 137 之前量的**：已由「挑戰模式依現況重調」的 session（決策 145）處理。
- **教學的「最遠 2 公里」說明**在依距離算需求關閉的地圖（示範、舊存檔）上不成立，只是文字。
- **城市需求幾乎沒有工作時，某些夜晚完全不成長**（#312，罕見）：權重以千分之一取整到 0。
- **需求那一行在需求不起作用時也顯示**（實景示範、自由模式）。
- **車站客源的背景計算不會取消**（#305，第八節已列）。

**範圍外（#300 之前就有），待追查**：
- `TrafficFollowingPropertyTests` 用額外種子時，GameCore 和參考模型不一致。CI 的 4 個種子沒事；#316 前後一樣，不是這次造成的。
- 重現：`PROPERTY_STRESS=8 PROPERTY_REPLAY="traffic.following@9E03B1A53EA6991E@0" swift test --skip-build --filter TrafficFollowingPropertyTests`。
  - 2 號車在 GameCore 還在第 1 站停站，參考模型已經開往第 2 站。
  - case 1 是 3 號車的 `ServiceTimes.run` 不同。
- 還沒判斷是哪一邊錯。

**驗證**：
- **VERIFIED（本機 Linux）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 通過的類別：`StationSitingTests`、`NetworkBuildingSessionTests`、`GameLoopTests`、`BuildingSessionTests`、`WholeTaiwanTests`、`UndoSessionTests`、`BuildPauseSessionTests`、`ZoningSessionTests`、`CityDemandTests`、`LandBlocksTests`、`CityFootprintsTests`、`BuildingSale*`、`PlacedBuilding*`、`NewGame*`、`SavedGameTests`、`GoldenScenarioTests`。
  - #311 的交通 campaign 用 12 個額外種子加跑：只有種子數變多造成的次數斷言，沒有任何一個案例不一致。
- **UNVERIFIED LOCALLY**：`MapView.swift` 的畫面行為（要 macOS CI）。
