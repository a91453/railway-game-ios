# 交接：PR #200–#296 的審查與修正

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

1. **反轉一條在營運中的路線會讓它停擺**（`GameWorld.reverseLineStops`，路線面板可以直接按）。
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

**驗證**：
- **VERIFIED（本機 Linux）**：建置沒有警告。改到的類別都通過：`BuildingSale*`、`CompanyBuildings*`、`SavedGameTests`、`TerrainPresentationTests`、`HeightGridTests`。
- #297 那份修正的 golden（24 項）、`PassengerPropertyTests`、`BoardingPropertyTests` 都已在本機通過，結果貼在 #297 的留言。
- 其餘交給 CI。
