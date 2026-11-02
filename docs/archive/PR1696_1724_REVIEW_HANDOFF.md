# 交接：PR #1696–#1724 審查（審查 L6）

派工單 REVIEW-L6（遊戲規劃 pro 暫代 session_01JMHz9YRiP23RXrrfdsaGsq，2026-11-02，108.1 發版後）：獨立審查 L5 之後已合併、改了程式的 PR，找正確性 bug。格式同 L5（`PR1666_1695_REVIEW_HANDOFF.md`）。

- Session：session_01JMHz9YHpNFxp8mYxf4E7ce，branch `claude/review-l6`。
- 基準：`main` **043d726**（#1725 合併後）。每個 PR 讀 merge commit 對 first parent 的 diff。
- 做法：全部由本 session 自己讀，沒有用子代理。L6-1 用 Linux 臨時測試重現（修前、修後各跑一次），量完刪掉，沒有提交。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

`git log --first-parent 0b44155^..043d726` 逐一核對，只看改到 `Sources/`、`RailwayGameApp/`、`Tests/`、`.github/` 的。

| 層 | PR |
| --- | --- |
| **GameCore** | **#1706**（L4-1，`freePlatformPath` 的 `rejoining`）、**#1710**（MISSRUN，決策 547）、**#1719**（TOURCOUNT，決策 551）、**#1698**（LOOP-3，決策 542；只看 REV1698 之後的 6f0fe81） |
| GamePresentation | #1696（決策 543）、#1700（桃園機捷 studies 模型）、#1702（決策 546，模型包平行化）、#1703（RINGBOARD）、#1704（LABELFIX）、#1711（決策 548，85 大樓） |
| App | #1705、#1712（MENUSTALL）、#1713、#1716、#1718（CRASHSWEEP-2） |
| CI | #1697（CIWEIGHT）、#1707（決策 545，`.build` 快取）、#1714（CIWARN）、#1717（FLANE6） |

沒有審：只改文件或發版說明的 #1699、#1701、#1708、#1709、#1715、#1720、#1722、#1724；#1721（Info.plist 一行）；#1693（App 與 UI 測試，3D 啟動）編號在 L5 的範圍，卻在 L5 的基準 39aaec0 之後才合併，L5 和本輪都沒看，留給下一輪；#1725 派工單說不看。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（馬上修） | **0** |
| P2（下一版修） | **1**：L6-1 |
| P3（記著） | **4**：L6-2～L6-5 |

沒有 P1，沒有 send_message 緊急通報。

### GameCore

- **#1706**（L4-1）：`rejoining` 只在「停站後繼續往前、不折返」時算；`onwardWay` 的距離加法用 `addingReportingOverflow`，索引都先 `indices.contains`。`straightPath` 為 nil 時不設 `rejoining`，退回舊行為。最後一步（`own > 1` 時的「所有月台」）沒有套 `rejoining`，這正是 WENHUCAP（#1723，決策 549）找到的文湖線逆向，已在修，本輪不重列。
- **#1710**（決策 547）：`pathOutOfDepot` 只在號誌關、照班次、從機廠出發時動；守門順序便宜的先。`depotHasRoom` 現在號誌關也看（`runTrainEnteringDepot` 與提前入庫兩處）。`Set` 只拿來 `contains`，不影響確定性。見 L6-3、L6-4。
- **#1719**（決策 551）：見 **L6-1**。`countedAt(day:)` 的乘法在合理的天數內不會溢位。
- **#1698**（只看 6f0fe81）：`caught` 的新條件 `c.x + 1 < x.points.count` 先比再用；`keptBehind` 的迴圈 `1...(lp.point - back)` 下界 ≥ 1（`back` 取自 `..<lp.point`），`x.points[fp.point + k]` 最大到 `start`，不越界。`runServices` 改傳 `trains[index]`（REV1698 P3-1）對。`timetabled` 只看慢車的線（`followsRealTimetable(l.train)`），快車是照班次、慢車不是時不套新條件；目前沒有這種混線，記在 L6-5。

### GamePresentation

- **#1696**：`init(beside:)` 只在兩端偏移相同時縮放把手，`offsets[index + 1]` 與原本的 `nodes[index + 1]` 一樣靠「offsets 與 indices 同長」，沒有新增風險。
- **#1700**、**#1711**：只加模型。`frontPatch` 的 `[String: Edge]` 用 `keys.sorted()` 走，雜湊穩定；85 大樓用到的 `colour(...)` 名稱逐一對過 `palette`，都有（`palette[name]!` 不會炸）。
- **#1702**（決策 546）：`Map3DParallel.map` 每格只寫一次、`defer` 裡 deinitialize＋deallocate，回傳照索引；`Map3DTrainLights`、`Map3DTrainMaterial`、`Map3DTrainOcclusion` 傳進去的都是純函式（`GamePresentation` 沒有可變的 static）。`Map3DTrainModels` 全在 main actor，`start` 與 `finished` 不會漏醒。3D 頁先畫方塊、模型好了再換：`updateUIView` 先處理 `hasModels`，場景還沒顯示時不提早 `showTrains`，之後顯示時一起帶模型。沒有找到錯。
- **#1703**（RINGBOARD）：`calls.count == run.times.count` 先比；有班次的線 `stops` 不重複（`LineRuns.swift:156`），所以同一站在一班裡最多兩次（環狀整圈的頭尾），列 id 用 `|end` 分開，不會重複。
- **#1704**（LABELFIX）：L5-3、L5-4、L5-7 三處都改到 `MapProblems.nameTop`；`stationTag` 的 `stationRadius` 預設 0，舊呼叫點行為不變。

### App

- **#1705**、**#1718**（CRASHSWEEP）：`@Sendable` 閉包只抓值或 main-actor 類別（`GameSession`），列抽成 struct 後 body 每次重算，不會拿到舊值。`MeterBar` 與原本的 `GeometryReader` 寬度算法相同。`FinanceCompositionChart` 的中心文字從 `chartBackground` 的 plot frame 改成 `.background` 加固定寬度，位置靠截圖驗收（PR 已做），本輪不能看畫面。
- **#1712**（MENUSTALL）：`setActive` 進前景時在背景 queue 設 audio session，好了才 `isActive = true`；中途退到背景，`sessionIsSet` 的 `guard appIsActive` 擋掉。`plays` 是 init 時的常數，不會「先不設 session、之後才要播」。`StallSampler` 整段在 `#if DEBUG`，而且要 `-ui-test-stall-stacks` 才開。
- **#1713**：Release 拿掉永遠 false 的 guard；DEBUG 照舊。`.utility` 取代 `.background`，與決策 546 一致。
- **#1716**：一段靜態文字。

### CI

- **#1697**（CIWEIGHT）：分片名單只換班；`swift-shards.sh` 本來就會證明每個 job 跑的正好是它的測試（名單裡的類別不存在或沒被跑到會紅）。批次上限 100,000 字元是測試 ID 長度的總和，離 Linux 單一參數上限 128 KiB 還有約 31,000。
- **#1707**（決策 545，快取）：會不會讓該紅的變綠——逐項查過：(1) 只在 build 綠時存（`actions/cache/save` 在 build 之後，build 紅就不跑到）；(2) 存的只有 main；(3) 改了 GameCore、`Package.swift` 或刪了 GameCore 檔就丟掉快取從零建；(4) 用內容（blob）決定時間，沒改的檔拿回原時間、改過的拿到比清單裡都晚的時間，driver 一定重編；(5) 快取上建置失敗會從零再建一次；(6) 夜間與手動（發版用的完整 run）不讀快取。剩一個沒法在這裡證明的：**沒改的檔不重編就不會再印它的警告**，`-warnings-as-errors` 只對重編的檔有效。只要警告是由改過的檔引起，依賴它的檔會被 driver 重編，警告照樣出來；所以只有「工具鏈不變、程式不變卻多出警告」這種不會發生的情形才漏。結論：沒有放過該紅的。
- **#1714**（CIWARN）：只改警告時間與字串；`SHARD_LIMIT_MINUTES` 與 `timeout-minutes` 由 selftest 對齊。
- **#1717**（FLANE6）：放寬 full lane 時限、兩支 UI 測試等模型與關掉 stderr 的 log。沒有放鬆斷言內容（只放長等待時間）。

## 二、發現

### L6-1（P2）#1719：營運時間不含中午的線，觀光客整天算 0，景點顯示「沒人能搭車到這裡」（退步）

- **位置**：`Sources/GameCore/Passenger/Tourism.swift:103-109`（`countedAt(day:)` 固定取當天 12:00）、`:648`（`attractionStatus`）、`:786`（`closeTourismDay`）。
- **問題**：`PassengerRouteGraph(world:at:)` 只收 `serviceLevel(of:at:)` 不為 nil 的線，也就是營運時間（`ServiceWindow`）包含那一分鐘的線。#1719 把讀圖的時刻從午夜改成中午，修好了 06:00–24:00（預設）的線，但營運時間**不含 12:00** 的線從此整天不算。玩家可以在開線卡片把開始時間往後調（`LineConfirmation.movingOpen`，最晚到收班前一小時），例如 13:00–25:00 的午後／夜間線：#1719 之前午夜在營運時間內、照算；之後中午不在，算 0。只在早上跑的線（例如 06:00–11:00）兩邊都是 0。
- **玩家看到**：只有午後或夜間營運的線通到景點時，景點的「昨天／今年」觀光客是 0，狀態寫「沒有人能搭車到這裡」，即使列車整晚都在跑（`attractionStatus` 也用當天中午，00:02 時線還在營運也一樣）。和 107.1 的玩家回報是同一個症狀，只是換了一種營運時間。
- **驗證**（Linux，臨時測試 `Tests/GameCoreTests/L6ReviewProbeTests.swift`，抄 `TourismTests.testMidnightCountsTheDayWhileTheNetworkIsClosed`，只把營運時間換成 `.hours(open: 780, close: 1500)`，跑 1,442 tick 後讀 `yesterday`，量完刪掉）：
  - `main` 043d726：13:00–25:00 **0、`.noSource`**；06:00–24:00 240、`.ok`。
  - 把 `Tourism.swift` 換回 #1719 之前（391b9e0^1）：13:00–25:00 **240、`.ok`**；06:00–24:00 0、`.noSource`（就是 #1719 修的那個）。
  - 修前紅的指令：把上面的測試放進 `Tests/GameCoreTests/`，`swift build --build-tests -Xswiftc -warnings-as-errors && swift test --skip-build --filter L6ReviewProbeTests/testAnAfternoonAndNightLineCounts`。**VERIFIED**（在 main 上紅）。
- **建議修法**：讀圖時每條線各用「它當天有營運的一刻」而不是全網同一刻：例如 `PassengerRouteGraph` 加一個「整天」模式，`serviceLevel` 換成那條線營運時間內的某一分鐘（例如營運時間中點、或當天服務最多的時段），或在 `countedAt` 依線取 `max(open, 12:00)` 這類落在營運時間內的時刻。全天（`.allDay`）與預設的線結果不變，golden 應不動（要跑 `GoldenScenarioTests` 確認）。上面的兩個情形（13:00–25:00、06:00–24:00）都當回歸測試，再加一條 06:00–11:00 的早班線。只動 GameCore 的 `Tourism.swift`／`PassengerRoutes.swift`，決策 551 寫續。

### L6-2（P3）#1719：觀光客一天只用一刻的網路決定「到不到得了」

- L6-1 的根本：一天的觀光流量（`touristFlows(onDay:)`）是一整天的量，卻只用某一分鐘的路網判斷能不能到。兩條營運時間不重疊的線接駁（一條早上、一條下午）時，任何一刻都接不起來，也算 0。很少見，記著；L6-1 修法若改成「每條線用自己營運時間內的一刻」，這個也一起好。讀程式推的，**UNVERIFIED**。

### L6-3（P3）#1710：號誌關時，機廠股道比列車短的照班次線，列車永遠不進機廠

- **位置**：`Sources/GameCore/Railway/RunDepot.swift:129-133`、`:219-221`。
- **問題**：`depotHasRoom` 以 `berths(of: depot, length: train.length)` 數股道；股道都比列車短時是空的，`depotHasRoom` 永遠 false。#1710 之前號誌關時不看，列車照樣開進去（停在股道外的咽喉，就是決策 547 要修的卡住）；之後改成待在終點站月台。對多數情形這是想要的（不再卡死），但玩家自己蓋的、照班次的線若機廠股道太短，夜裡列車全部留在月台，佔住終點站。只是推論，沒有找到這樣的現有地圖，**UNVERIFIED**。
- **建議**：線的設定或機廠卡片在「機廠股道比這條線的列車短」時提示一行（GamePresentation），或不改、記在決策 547。

### L6-4（P3）#1710：出機廠繞開停著的列車後，決策 527 的改路又會走回去

- **位置**：`Sources/GameCore/World/GameWorld.swift:4082-4088`。
- **問題**：`pathOutOfDepot` 用 `keepingLeft: false`、`avoiding: standing` 找到 `kept`；接著若 `kept` 走到「只給反方向用的軌道」，`lineDirectionPath` 從頭重找一次（`avoiding: Set<TrackResource>()`，不帶 `standing`），可能又穿過停著的列車。結果只是退回 #1710 之前的路，不會更糟；也可能 `kept` 因為不靠左而先走上反方向軌道才觸發這個重找。讀程式推的，沒有重現，**UNVERIFIED**。
- **建議**：`lineDirectionPath` 收一個 `avoiding` 參數，出機廠時帶 `standing`；或 `pathOutOfDepot` 本身就帶 `forbidden: against`。

### L6-5（P3）#1698：越行判斷的「照班次」只看慢車

- **位置**：`Sources/GameCore/Railway/HeadwayOvertake.swift:109`（`let timetabled = followsRealTimetable(l.train)`）。
- **問題**：「快車也要先離開、而且還要往前開」的條件只在慢車照班次時套。慢車照班距、快車照班次（同一段軌道上玩家自己的線和買來的線混跑）時，「同一停站型態的下一班」與「在那站結束的班次」仍會被當成越行，正是 LOOP-3 修的死結型態。現在沒有這種混跑的地圖。REV1698 P3-1 提過另一處的 `||`，這裡是同一類。讀程式推的，**UNVERIFIED**。
- **建議**：改成 `followsRealTimetable(l.train) || followsRealTimetable(x.train)`，跑 `LiveOvertakeTests` 與淡海兩日測試確認不變。

### 沒列的

- `Map3DTrainOcclusion.baked`（`Sources/GamePresentation/Map3DTrainOcclusion.swift:89-91`）的 `results` 只 `deallocate` 沒有 `deinitialize`，每個不重複的車型留一份 `[Float]` 不放。模型包一個 process 只建一次，量很小；而且這段在 #1702 之前就有（`ba284aa`），不在範圍。順手修時改成 `Map3DParallel.map`。
- #1702：`Map3DTrainModels.make` 的等待不理會 task 取消；3D 頁在模型做好前關掉，`.task` 會一直等到做好才設 `modelsReady`（畫面已不在），無害。
- #1707：快取 key 只含 Swift 版本與 `Package.swift`，不含 runner 映像；換映像但 Swift 相同時沿用舊 `.build`，只要 driver 照時間判斷就照樣對，失敗也會從零再建。
- #1712：退到背景時沒有 `setActive(false)` audio session，與 #1712 之前相同。

## 三、驗證

Linux、Swift 6.4.0、`main` 043d726：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（從零 417 s 通過）。
- `swift test --skip-build --filter` `TourismTests`、`CallingLoopPlatformTests`、`DepotPullOutStandingTests`、`LiveOvertakeTests`、`RingRunBoardTests`、`MapLabelPlacementTests`：**VERIFIED**（58 個測試全過）。
- L6-1：臨時測試，main 紅、#1719 之前綠（另一個情形相反），量完刪掉。**VERIFIED**。
- L6-2～L6-5：讀程式，**UNVERIFIED**。
- App 與 CI 的 PR：讀程式；畫面、Simulator、GitHub Actions 的行為都 **UNVERIFIED**（沒有 macOS）。

## 四、下一步

- L6-1（P2）派一個小 session 修（GameCore，2 點），附上面的回歸測試；決策 551 續。L6-2 一起看。
- L6-5 一行，可以和 L6-1 同一個 GameCore PR，或等下一個動 `HeadwayOvertake.swift` 的 session。
- L6-3、L6-4 記在決策 547 的下一步。
- L4 的 L4-1 仍有一半在 #1723（WENHUCAP）。
- 下一輪審查從 #1726 起數。
