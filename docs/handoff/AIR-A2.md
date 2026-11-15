# AIR-A2：航線收購清單與航線卡

- 派工：主規劃（專案「鐵道遊戲主規劃」工作串「做航線收購清單和航線卡」），作者 11-15「開始做航空a2」，照 `docs/research/AIR_ROUTE_ACQUISITION_DESIGN_2026-11-15.md` 第 6 節 A2。
- session：雲端 thread session，分支 `claude/project-thread-ehijao`（疊在 AIR-A1 的 `claude/project-thread-fgw0oi`）。
- 決策 759（`docs/decisions/759.md`）。存檔、golden、fixtures 不動。
- 做完：`Sources/GamePresentation/AirRouteMarket.swift`（清單、估計、航線卡、地圖線、四個指令）；`LinesPanel.swift` 的「航線」列與頁；`RealLineAcquisitionCards.swift` 的 `AirRoutesPage`、`AirRouteOfferSheet`；`MapArt.swift` 的 `drawAirRoutes`；測試 `AirRouteMarketTests`。
- 還留下：
  - **A3**（另開新串）：收購任一條台灣↔香港航線就打開香港地圖。清單裡的香港航線是 `AirRouteListing.destination.name == "香港"`，已收購的看 `world.airRoutes`。
  - **A4**（3D）：照 `airRouteDepartureMinutes` 起降。
  - 平衡：做完，決策 762（AIR-BALANCE）：主要航線 132–229 天回本，只剩四條一天不到 15 人的線虧錢、花蓮—香港 778 天。
  - 決策 758 第 8 點寫「松山—澎湖 140 km」，實際兩座機場在地圖上約 258 km（真實航程也是兩百多公里），那句例子要更正（只是文字）。
- UNVERIFIED：畫面沒有在模擬器、實機看過；Linux 本機跑了建置與 `AirRouteMarketTests` 等（見 PR），App 的編譯交給 CI 的 Xcode 建置。
