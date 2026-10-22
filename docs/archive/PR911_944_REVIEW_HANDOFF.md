# 交接：PR #911–#944 審查 B 組

Session：session_017M3NJsMXLafGDsSvidGhD6，遊戲規劃 session_014rYHMtmqA5bEMkBBuKu6PV 派工，2026-10-21。分支 `claude/pr-review-b-911-944`。

- 審查基準：`main` **543770c**（#944 的合併）。
- 範圍：已合併的 #911–#944，以及遊戲規劃之後要求一起看的 #941、#942。#873–#910 由審查 A（session_01SvQ285hMiSeRsER1EXzfT9）審。
- 上一輪：[PR786_872_A](PR786_872_A_REVIEW_HANDOFF.md)、[B](PR786_872_B_REVIEW_HANDOFF.md)、[C](PR786_872_C_REVIEW_HANDOFF.md)。
- 存檔版本、決策編號、golden schema 都**不動**。GameCore、GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 本 PR 改了兩個 GamePresentation 檔案，各附一個回歸測試，另外加這份文件與 `docs/HANDOFF.md` §7.1 的一行。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 新發現 | **7**：P2 兩個（B1、B2），P3 五個（B3–B7） |
| 已修 | **2**：B1、B2，都先在 main 上用測試重現成紅的，修好後轉綠 |
| 沒修，交出去 | **5**：B3–B7，見第四節（2026-10-22：B3 由 #966、B4–B6 由 PR 2 處理；B7 交 3D session） |

讀 diff 的工作分給三個子代理：#912／#927、#918、3D 與介面。#934、#935、#936、#939 和只改文件的 PR 由本 session 自己讀。

子代理的發現都由本 session 再讀程式確認過。能在 Linux 重現的才修。

## 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #911、#924、#929、#931、#933 | OVERVIEW、HANDOFF、NEXT_PRIORITIES 的索引與交接 | 只改文件。`doc_numbers.py --check` 0 差異 |
| [#912](https://github.com/a91453/railway-game-ios/pull/912) | 決策 308。`RouteReservation.swift` 的 `released`／`binds`、`Deadlock.swift` 的 `berthChange`、`GameWorld.swift` 的 `approachesStandingTrain`。`extendAuthorities` 與 `canExtendAnyAuthority` 的判斷一致，批次與逐分相同。只在號誌開、閉塞關時才有作用 | 無問題 |
| #913、#921、#925、#926、#930、#937 | 靜態素材套件（車站、細節、工程、公共、住宅、公園）：只有 GamePresentation 程式、測試、工具、圖 | 沒有違反規則；沒有玩家文字，也沒改 App 專案 |
| [#914](https://github.com/a91453/railway-game-ios/pull/914) | 市區公車模型。`project.pbxproj` 的改動和 `project.yml` 把 `Resources` 當目錄來源相符，是重新產生的，不是手改。`DataSourceCredits` 的 Meshy 與照片（CC0）有列 | B6（P3） |
| #915、#916 | 日本鐵道資料研究；OSM 偏移量測工具與研究 | 只有文件與工具 |
| [#917](https://github.com/a91453/railway-game-ios/pull/917) | 雨絲、閃電。「減少動態效果」打開時不畫雨絲、不閃（motion §3）。用位置雜湊，所以同一時刻的雨絲相同 | 無問題 |
| [#918](https://github.com/a91453/railway-game-ios/pull/918) | 決策 319，存檔 67。查了 `homeShare` 的範圍（夾在 0–1000，指令與成長都不會超出解碼器範圍）、溢位、遷移、`setTidalDemand`（不會丟錯；`PassengerPlan.Key` 含 `tidalDemand`），以及各劇本有沒有關掉。golden、replay、舊 fixture 都沒動 | B4、B5（P3） |
| [#919](https://github.com/a91453/railway-game-ios/pull/919) | `swift-shards.sh` 重新平衡：8 個類別各只在一個 shard，`check_partition` 仍會擋重複或漏跑。GamePresentation 測試的 tier 沒變 | 無問題 |
| [#920](https://github.com/a91453/railway-game-ios/pull/920) | 低橋。迴圈每一輪至少拿掉一個界，所以會結束；測試的界比原本嚴 | 無問題 |
| [#922](https://github.com/a91453/railway-game-ios/pull/922) | 決策 321，車站套件接上地圖。`append(_:at:forward:)` 的旋轉正確，車站依 ID 排序 | B7（P3） |
| [#923](https://github.com/a91453/railway-game-ios/pull/923) | 弧形車頭。`named()`／`byType` 在三處用法一致 | 無問題 |
| [#927](https://github.com/a91453/railway-game-ios/pull/927) | 決策 323，六家線、沙崙線雙線。`readyRunTrain` 的「偏好路線能保留就放行」和 `departService` 的順序、呼叫相同。待避線數與索引對得上，放不下時是丟錯，不是當掉 | 無問題。鐵道迷附註：資料裡六家站只有 1 股道，實際應是島式 2 股，沒有查 `extract_branch_runs.py` |
| [#928](https://github.com/a91453/railway-game-ios/pull/928) | 站前商店街。車道號是負數時，顏色索引也安全；店只放在站前廣場的格子上，且避開道路 | 無問題 |
| #932、#940、#943 | 80.1 的 What to Test、PLAYER_FEEDBACK。玩家文字沒有內部名詞 | 只改文件 |
| [#934](https://github.com/a91453/railway-game-ios/pull/934) | 決策 324，存檔 68。`DayPass.swift`、`Tourism.swift` 的 `touristFlows`、`Subsidiary.swift`、帳本的驗證；`SavedGame` 的 68、69 遷移註解與兩個 fixture（v68 有 `dayPass`，沒有 `highSpeedFares`；v69 相反；`CompanyAccounts` 的 CodingKeys 兩個都在）。`SavedGameTests`、`DayPassTests`、`HighSpeedTests` 都過 | **B1（P2），已修** |
| [#935](https://github.com/a91453/railway-game-ios/pull/935) | 決策 325，存檔 69。`HighSpeedFare.isTable`、二分搜尋、`tripFare`、示範的 66 組票價（NT$10 = $1）、TDX 的授權說明 | B3（P3） |
| [#936](https://github.com/a91453/railway-game-ios/pull/936) | 決策 327。`removeLineSellingTrains` 先刪線再逐列賣；指令在副本上執行，所以失敗時整個不生效。`sellWhereItStands` 依序停服務、拉下軌道、賣掉。確認卡與訊息的文字沒問題 | 無問題 |
| [#938](https://github.com/a91453/railway-game-ios/pull/938) | 決策 326，架空線。`wireSupports` 每根電桿至少前進 2 m，所以會結束。字典只拿來查，不影響順序。輕軌、捷運、林鐵不畫。快取的 key 加了 `hasRailways` | **B2（P2），已修**；B6 的第二項 |
| [#939](https://github.com/a91453/railway-game-ios/pull/939) | 決策 328。`StationPassengers.enqueue` 的二分搜尋，在佇列依 `since` 排序、同一分鐘內依目的地排序時，和從頭找的結果相同；`waiting` 的每個寫入點都維持這個順序，解碼器也要求。`Boarding` 排序只是先查好再排，等價。試跑移出主執行緒：tick 的結果只有在 `tick.revision == worldRevision` 時才收，memo 只有在 `memo.revision == commandRevision` 時才存，所以 tick 進行中下了指令，結果會丟掉，不會蓋掉新狀態。`covers` 多了 `now == from`，結果和重算相同。`buyableRealLines` 的 key（範圍、地理錨點、已收購、railways 版本）涵蓋了計算用到的東西。`FrameCostMeter` 有加鎖 | 無問題 |
| [#941](https://github.com/a91453/railway-game-ios/pull/941)、[#942](https://github.com/a91453/railway-game-ios/pull/942)（範圍外，遊戲規劃要求一起看） | 高頂小巴、低地板公車加入街景公車池（`Map3DStreetLife.swift` 的 `isBus`、選型、進出路端的長度）。#942 的 base 是 #941 的分支，所以 2026-10-21 23:31 的合併進了 `codex/shuttle-bus-2026-10-21`，不是 main（55a1775 不在 main 上）；遊戲規劃已改開 #951 合進 main，#945 的 base 也改成 main | 程式無問題。合併的 base 錯了，已通知遊戲規劃，由 #951 補上 |
| [#944](https://github.com/a91453/railway-game-ios/pull/944) | full lane 的兩個 UI 測試。重試前先看 `exists`，再用 `appears(within:)` | 無問題 |

PR 描述裡寫 VERIFIED 的測試數（架空線 8、車站 9、商店街 5、雨 5、公車 5），和 main 上的測試數相符。沒有找到宣稱有跑、實際沒跑的。

## 三、修了的

### B1（#934）一日週遊券卡片建議的價格賣不出去，P2，已修

- **重現**：`DayPassCardTests.testTheSuggestedPriceSells`，在 main 上紅。
  - 票價用編輯器的距離分段時，最短一段是 $0.55，三倍是 **$1.65**。卡片就以這個價格起跳，按「以 $1.65 販售週遊券」會被 `setDayPass` 拒絕，因為週遊券只收整數元。
  - 步進器一次跳 $1，所以之後是 $2.65、$3.65……都不是整數元，怎麼調都賣不出去。
  - 均一票價超過 $166 時，三倍會超過步進器的上限 $500。
- **修法**：`DayPassCard.suggestedPrice` 四捨五入到整數元，再夾在 `priceRange`（$1–$500）之內。GameCore 的 `DayPass.suggestedPrice` 不改，它的測試值 165 也不動。
- **玩家**：第一次按就賣得出去。**鐵道迷**：無。**開發**：只改 GamePresentation，不動 GameCore 與 golden。**美術**：無。**音樂**：無。

### B2（#938）平交道的路面上立著電桿，P2，已修

- **重現**：`Map3DOverheadLineTests.testNoMastStandsInTheStreetAtALevelCrossing`，在 main 上紅。直線軌道每 40 m 一根電桿，x = 0 正好是平交道，那根電桿就立在車道中間，路上的車會穿過它。80.1 的 What to Test 第 8 項也請玩家看這個。
- **修法**：電桿的位置落在平交道的路面上（含人行道，與 `Map3DLevelCrossing.rise` 的寬度相同，往兩邊各 40 m 以內）時，就不立那一根。架空線照樣跨過路面，接到兩旁的電桿。
- **玩家**：車不會穿過電桿。**鐵道迷**：真實的平交道上也不會立電桿。**開發**：只在電桿迴圈裡多一個判斷。**美術**：那一段的跨距變成最多 80 m，近看還是一條線。**音樂**：無。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| B3 | #935 | P3 | 存檔裡 `highSpeedFares` 指到不存在的車站 ID 時，解碼器不會擋。`setHighSpeedFares` 會檢查，但解碼與世界驗證不會。車站 ID 只增不回收，所以只有在存檔被改過時，之後新建的車站才可能繼承那組票價 | 正常玩出不來；要補驗證就是改 GameCore 的解碼 | **已修**（2026-10-22，#966，session_01QiPq4nZdq5bVS9MZ4rkr4L）。原本：高鐵票價的作者，或下一個改 `Accounts.swift` 的人：在 `GameWorld` 的驗證裡檢查票價表的站 ID 小於 `nextStationID` |
| B4 | #918 | P3 | 車站卡在「沒有起訖對」時畫的示意曲線，潮汐開著也一律用平日的形狀。週末時，住宅站顯示 08:00 的尖峰，但 GameCore 週末不放那個尖峰（`StationDemandText.swift` 約 307 行；`PassengerDemand.hourly` 的 `tide = tidal && !weekend`） | 原本就沒看週末，只是潮汐讓差距變大；只影響示意圖 | **已修**（2026-10-22，PR 2：週末與假日用週末的形狀、不放潮汐）。原本：潮汐或車站卡的作者：`shared(_:by:tidal:)` 也要帶上週末 |
| B5 | #918 | P3 | 不在經營模式時（`drawsDemandFromLand` 是 false），關掉潮汐，`refreshLandDemand` 一開始就返回，車站留著舊的 `homeShare`；之後再打開潮汐，就用這個舊值。決策 319 第 4 條寫「關掉就拿回去」 | 自由模式本來就凍結了所有由土地來的需求，`dailyTrips` 也一樣；屬設計層面，要先決定自由模式要不要動需求 | **定案**（2026-10-22，遊戲規劃：自由模式不動需求，程式不改；決策 319 補「後來」，測試 `TidalDemandTests.testAFreeCompanysTideWaitsForTheManagedOne`，PR 2）。原本：決策 319 的作者 |
| B6 | #914、#938 | P3 | (a) `Map3DCityBus.swift` 約 37 行，用 `length / size.x` 算縮放，沒有防護；模型檔在某一軸是扁的，或沒有頂點時，會得到 NaN，而不是改用方塊公車。只有壞掉或被換掉的素材才會發生。(b) `Map3DPreviewScreen.swift` 約 145、248 行，在沒有地理錨點的地圖上，railways 讀進來時整個 3D 場景會白白重建一次 | (a) 正常素材不會觸發；(b) 是 App 的程式，Linux 測不到，只影響效能 | **已修**（2026-10-22，PR 2：(a) 扁的或沒有頂點的模型改用方塊公車；(b) 沒有地理錨點的地圖 key 不看 railways）。原本：3D session：(a) 加 `size.x > 0 && size.y > 0 && size.z > 0` 的防護；(b) key 改用 `world.geoAnchor != nil && session.railways != nil` |
| B7 | #922 | P3 | 不是實景的地圖上，`addSeededStreets` 在 `addStations` 之前執行，所以車站的廣場格子沒有避開種子街道。只拿掉街道家具（`removeProps`），街道帶和車流（`Map3DStreetLife` 的車道）仍可能從站房下面穿過 | 子代理讀程式推論出來的，本 session 沒有寫出會紅的測試；要調整執行順序，或讓街道避開站房，屬 3D 排版的設計 | 3D session：先用新遊戲的世界寫測試，確認站房的範圍內有沒有 `seededStreets.edges` 的端點 |

另外記下兩件，不算發現：

- `DayPassTests` 有一段在設了 `DAY_PASS_SAVE_NEW` 時重寫 v68 fixture。現在 `currentVersion` 是 69，照這個做會寫出 69 版，然後 68 的斷言失敗。CLAUDE.md 本來就不准重寫 fixture，所以只記在這裡，不改。
- #912 每次重建軌道佔用時建 `released`，成本大約是「佔用數 × 列車數 × 掃描岔道」，屬效能，不是正確性。

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors` | **VERIFIED**，乾淨 |
| `DayPassCardTests`、`DayPassTests` | **VERIFIED**：修之前新測試紅，修之後 4＋11 個全過 |
| `Map3DOverheadLineTests` | **VERIFIED**：修之前新測試紅，修之後 9 個全過 |
| `--filter GamePresentationTests.Map3D`（所有 3D 類別） | **VERIFIED**，242 個，0 失敗，4 個本來就略過 |
| `SavedGameTests`、`HighSpeedTests`、`NightSkipTests`、`LineRemovalTrainsTests`、`StationPassengersTests` 等（main 上，修之前） | **VERIFIED**，0 失敗 |
| `python3 -I tools/golden-checks/doc_numbers.py --check` | **VERIFIED**，0 差異（存檔 69、fixture 73、golden schema 74、golden 77、replay 9、決策到 328） |
| iOS 的建置與 UI 測試 | **UNVERIFIED LOCALLY**，交給本 PR 的 `ios-build.yml`。本 PR 不改 App 的程式 |
