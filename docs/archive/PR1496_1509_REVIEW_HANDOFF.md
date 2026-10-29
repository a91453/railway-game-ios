# 交接：PR #1496–#1509 公測前審查

派工單 REV（遊戲規劃第 32 任 session_01YGNNuon2Njt6B8dAanT7j5，2026-10-29）：公測前審查 2026-10-29 合進 main 的程式 PR。只找會讓玩家壞掉的：當機、存檔讀不回、舊存檔行為改變、決定性被破壞、主執行緒卡頓、iPhone／iPad 直橫畫面跑版、玩家看的文字寫了內部名稱。

- Session：session_01YGNNuo6Fi8RzveGo8bcMk6，branch `claude/review-pr1496-1509`。
- 基準：`main` **a0a4ebe**（#1509 合併後）。
- 規則：不改程式、不開修正 PR、不跑 iOS workflow。疑點用 Linux 的 `swift build`／`swift test --filter` 和臨時量測驗證（量完刪掉，沒有提交）。
- 存檔版本、決策編號、golden schema 都**不動**。

## 〇、範圍

| PR | 內容 | 層 | 點數 |
| --- | --- | --- | --: |
| #1496 | 路線面板：手機橫放時搜尋、篩選、排序收成一列（決策 486） | App＋GamePresentation | 1 |
| #1497 | CI：20 個慢的 GamePresentation 類別換 shard | CI 腳本 | 1 |
| #1498 | UI 測試不穩＋車站面板捲到群組 | App（StationPanel）＋UI 測試 | 1 |
| #1499 | 實景地圖鋪路照畫的鋪（決策 487） | **GameCore**（RoadGrid）＋GamePresentation | 2 |
| #1501 | 3D 跟車 10× 的 tick 工作移出主執行緒（決策 485） | App＋GamePresentation | 1 |
| #1502 | 垃圾車／資源回收車模型重建 | 模型＋工具 | 0 |
| #1504 | 公車工具的淡站名不再重複 | App＋GamePresentation | 1 |
| #1505 | 車站面板停下來才捲到群組 | App | 1 |
| #1507 | 拖曳放置建物：不改世界的試算（決策 488） | **GameCore**（PlacedBuilding）＋GamePresentation | 2 |
| #1508 | 收購的線開跑前旅客不出發（決策 490） | **GameCore**（PassengerDemand） | 2 |
| #1509 | iPad 直拿兩站比較卡（決策 491） | App＋GamePresentation | 1 |

派工單只點名 #1507、#1508 是 GameCore；**#1499 也改了 GameCore**（`RoadGrid.roadQuote`／`buildRoad`），一起細看。#1502 只換模型檔（`Map3DBundledModelFilesTests` 守著讀得進來），#1497 只改 CI 分片，玩家碰不到，只看了 diff 沒有發現問題。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（公測前必修） | **0** |
| P2（下一版修） | **2**：REV-1、REV-2 |
| P3（記著） | **3**：REV-3～REV-5 |

三個 GameCore PR 都和真的執行結果一致，也不會讓舊存檔讀不回、不會破壞決定性：

- **#1508**（`PassengerDemand.swift:911`、`:939`）：旅客放出只有 `releasePassengers(at:_:)` 一個入口，逐分與跳過閒置分鐘的兩條路（`GameWorld.swift:2769`、`:2909`）都經過它，所以新條件兩邊都套到。`linesNotYetRunning` 只用 `Set.contains`，不依賴集合順序；沒有收購的世界直接回空集合。存檔夾具 `v66-line-acquisition.json` 存在收購隔天，不受影響。行為改變只在「04:00 以後收購的那一天」，決策 490 已寫明重播會不同；`ReplayFixtures`、`GoldenScenarios` 裡都沒有收購指令（grep 過）。
- **#1507**（`PlacedBuilding.swift`）：`placeBuilding` 改成先呼叫同一個 `placement(of:at:look:)`，再扣款、刪土地、重算需求。原本 `economy.spend` 的檢查就是 `canAfford`（`GameEconomy.swift:98`），試算改用 `canAfford` 拋出同一個錯誤、同一個順序；`cleared`／`moved` 都在任何改動之前算，和舊流程一樣。預覽的記憶鍵用 `worldRevision`，`GameSession` 是 `@MainActor`，記憶不會跨執行緒；語言在 session 中只設一次，記憶裡的錯誤文字不會換語言後過期。
- **#1499**（`RoadGrid.swift`）：`taken` 只在 `geoAnchor != nil` 時有內容，空白地圖逐位元不變。`built` 本來就允許和 `cells` 重疊，存檔用既有欄位。`removeRoads` 不退錢（`RoadGrid.swift:318`），免費接收的城市格子拆掉也拿不到錢，沒有刷錢的路。

#1501 的滑行／高度記憶：`finish` 只在記憶的 revision 等於 tick 前的 revision、列車沒動時才沿用；之間有玩家指令（revision 變了）就在主執行緒重算，不會拿到舊世界的高度。3D 地圖的 RunLoop 觀察者在 `didMoveToWindow` 離開視窗時失效，閉包用 `weak self`。

## 二、發現

### REV-1（P2）#1504：公車工具拉遠時，淡站名每畫一次都是 O(n²)，台北一畫可以花上數十毫秒

- **位置**：`Sources/GamePresentation/BusStopLabels.swift:211`（`faintLabels(in:pins:)`），呼叫在 `RailwayGameApp/Views/MapArt.swift:1179`。
- **問題**：`faintLabels` 對可見範圍內**每一個**真實站（`stops(in:)`，沒有上限）逐一和已經寫過的每一站比（`written.contains`），是 O(n²)。畫點的迴圈本來有 `.prefix(600)`（`MapArt.swift:1180`），這個新函式沒有。它在地圖的 Canvas 裡，拖曳地圖與每個 tick 都重算，跑在主執行緒。
- **量到的**（Linux debug，臨時測試，台北車站周圍 6 km 共 3,311 站，`pins` 空）：

  | 可見範圍（約） | 範圍內站數 | 要寫名稱的 | 每次 ms |
  | --- | --: | --: | --: |
  | 3 km × 2.1 km | 298 | 230 | 5.5 |
  | 6 km × 4.2 km | 802 | 583 | 33.7 |
  | 9 km × 6.3 km | 1,452 | 1,034 | 101.5 |

  淡站點在 `pointsPerMetre >= 0.15` 時才畫：iPhone 橫放約 5.7 km 寬，iPad 約 8 km 寬，正好落在後兩列。release 會快幾倍，但仍是每幀十幾毫秒、隨站數平方長；實機 **UNVERIFIED**。
- **重現**：真實地圖，在台北車站附近開公車工具，選站後拉到剛好看得到淡站點的縮放，拖曳地圖，看幀時間面板的「地圖」。
- **建議修法**：只對要畫的那 600 站做，或用名稱分組（`[String: [PlanPoint]]`）只比同名的；兩種都把它降到接近 O(n)。

### REV-2（P2）#1509：iPhone 直拿也走了新的位置，決策 491 寫「手機不變」，沒有測試也沒看過

- **位置**：`Sources/GamePresentation/StationPairDrawerLayout.swift:56`（`insets(...)`），`RailwayGameApp/Views/ContentView.swift:661`。
- **問題**：新分支的條件是「帶子不到 280 點」，不只 iPad 直拿。iPhone 直拿、沒有開面板時，地圖右下角那一欄有小地圖（約 188 點寬，`MapView.swift:812` 在右邊沒有東西時才顯示）加邊距，所以原本的帶子也不夠，比較卡會改站到右下角那一欄**上方**、橫跨整個寬度。
- **算的**（用 `insets(...)`，邊距 10、角落欄 198 寬、248 高；尺寸是假設的，不是實機量的）：

  | 螢幕 | 原本的帶子 | 新的位置 |
  | --- | --: | --- |
  | 375×667 | 157 | 右 0、下 258 |
  | 402×874 | 184 | 右 0、下 258 |
  | 440×956 | 222 | 右 0、下 258 |

  原本的帶子一樣不到內容要的約 260 點，所以 iPhone 直拿在 #1509 之前很可能也有同樣的溢出，新的位置大概比較好；但它是沒寫進決策的改變：比較卡抬高約 150 點，可能蓋到玩家下一個要點的車站。`StationPairDrawerLayoutTests` 只測了 iPhone 橫放與 iPad。
- **重現**：iPhone 直拿、真實地圖，建設 → 新增路線，點兩站（不開路線面板），看比較卡在哪裡、有沒有蓋到小地圖或要點的站。
- **建議**：發版前實機看一次；若位置可以接受，在決策 491 補一句「iPhone 直拿也走這條」並加一個 iPhone 直拿的測試。

### REV-3（P3）#1505：跳到車站面板的群組之後約一秒內，玩家自己捲會被拉回去

- **位置**：`RailwayGameApp/Views/StationPanel.swift:117`（`onGeometryChange`）、`:300`（`settleJump(_:)`）。
- **問題**：跳到某個群組後，`settleJump` 等面板停下（`MotionRule.cardIn`），再不帶動畫連捲三次（每次間隔 `MotionRule.change`）。這段期間玩家若自己往上捲，會被拉回群組；面板每動一次（鍵盤、iPhone 上的 sheet 拉高）還會重新開始等。
- **重現**：點地圖上的貨運標記打開車站面板（會跳到貨運組），面板一停就往上捲，看是否被拉回。
- **建議**：玩家開始捲動時清掉 `pendingJump`（例如 `onScrollPhaseChange` 看到 `.interacting`）。

### REV-4（P3）#1496：橫放時搜尋欄放在 List 的一列裡，捲走時可能失去焦點

- **位置**：`RailwayGameApp/Views/LinesPanel.swift:921`（`inlineControlsSection`）、`:928`。
- **問題**：橫放時搜尋欄是 List 第一個 section 的一列。打字中捲到下面，那一列被回收時 TextField 可能失去焦點、收起鍵盤（SwiftUI List 的一般行為，沒有在實機確認）。字還在、欄也會因為有字一直顯示，不會壞，只是要再點一次。
- **重現**：iPhone 橫放，路線面板，點放大鏡打字，路線多時往下捲，看鍵盤是否收起。
- **建議**：記著，等玩家回報再看。

### REV-5（P3）#1508：新舊版本混著跑同一個網路對局會不同步

- **位置**：`Sources/GameCore/Passenger/PassengerDemand.swift:911`。
- **問題**：決策 490 寫明 04:00 以後收購那天的旅客放出和舊版不同。指令流重播（決策 193）在兩台裝置版本不同時，那天之後的狀態會分開；GameCore 裡沒有找到版本握手（grep `protocolVersion`／`rulesVersion` 沒有結果）。同一個 TestFlight 版本之間沒問題。
- **建議**：記著；之後若開放跨版本連線，要先有版本檢查。

## 三、驗證

Linux、Swift 6.4.0、`main` a0a4ebe：

- `swift build --build-tests -Xswiftc -warnings-as-errors`：**VERIFIED**（通過）。
- `swift test --skip-build --filter`：`BuildingPlacementTrialTests`（2）、`BuildingDragPreviewTests`（2）、`RoadGridTests`（28）、`RoadDrawRealMapTests`（2）、`StationPairDrawerLayoutTests`（9）、`LinesPanelNavigationTests`（14）、`BusStopLabelsTests`（17）、`Map3DFollowTickTests`（3）、`LiujiaLineTrainsTests`（4，117 秒）、`SavedGameTests`（36）、`ReplayFixtureTests`（3，1 個照常略過）、`GoldenScenarioTests`（24）：**VERIFIED**，全部通過。
- REV-1 的毫秒數與 REV-2 的位置：臨時測試量的，量完刪掉，沒有提交。
- iPhone／iPad 實機、iOS UI 測試：**UNVERIFIED**（照派工單不跑 iOS workflow）。

## 四、下一步

- REV-1、REV-2 交給規劃，在公測後派人修（REV-2 發版前先實機看一次）。
- REV-3～REV-5 記著，有玩家回報再處理。
- HANDOFF §1「上一輪審查」由規劃更新。
