# AIR-A1：GameCore 可收購航線

- 派工：主規劃（專案「鐵道遊戲主規劃」工作串「在遊戲核心加上可收購航線」），作者 11-15「好先做a」，照 `docs/research/AIR_ROUTE_ACQUISITION_DESIGN_2026-11-15.md` 第 6 節 A1。
- session：雲端 thread session，分支 `claude/project-thread-fgw0oi`。
- 決策 758（`docs/decisions/758.md`），存檔 103（`SaveFixtures/v103-air-routes.json`）。golden schema 不動。
- 做完：`Sources/GameCore/Passenger/AirRoute.swift`：`AirRoute`、`AircraftSize`（四級）、`AirRouteFrequency`（減班／照真實／加班）、`AirRouteDay`、`AirRouteOffer`；指令 `airRouteOffer`、`buyAirRoute`、`setAirRouteFrequency`、`setAirRouteSize`、`sellAirRoute`；查詢 `airRoute(id:)`、`airRouteDepartureMinutes(_:)`；午夜 `settleAirRoutes`（在 `closeAirportDay` 裡）；新帳列「航線（日結）」與三個項目（GamePresentation 的 `EconomyText`、`DisplayText` 已補中英文字）。
- 還留下（照設計頁第 6 節，各開新串）：
  - **A2**（App）：收購清單多「航線」一頁，用 `airRouteOffer` 顯示價錢（飛機＋旅客）；航線卡（班數三格、飛機大小，接 `setAirRouteFrequency`、`setAirRouteSize`、`sellAirRoute`）；2D 地圖畫航線。App 要給海外航點的距離（`metres`，例如桃園—香港約 810 km，用兩地經緯度的大圓距離算），地圖裡兩座機場給 `farAirport`。航點名要和 `AirportCatalog` 給機場的 `AirDestination.name` 一樣（例「香港」「澎湖」）。
  - **A3**：收購任一條台灣↔香港的航線就打開香港地圖（決策 712 多一個條件）。
  - **A4**（3D）：`Map3DAircraft` 讀 `airRouteDepartureMinutes` 讓玩家的班照時刻起降。
  - 平衡量測（決策 758「平衡」一節，NOT ASSESSED）：A2 之後量回本天數再調數值。
  - 小缺口：沒有列車在跑的世界一次跳過好幾個小時，只有機場（沒有航線）時午夜的機場計數會被跳過（決策 695 原本就這樣，這張沒改；有航線時已補喚醒）。
- UNVERIFIED：沒有畫面，模擬器、實機都沒跑過；Linux 本機跑了 `swift build --build-tests -Xswiftc -warnings-as-errors` 與 `AirRouteTests`、`SavedGameTests`、`AirportTests`、`FerryTests`、`GoldenScenarioTests`、`ReplayFixtureTests`、`EconomyAccountsTests`、`DisplayTextTests`（全過）；其餘交給 CI。
