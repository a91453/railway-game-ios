# AIR-A3：收購台港航線也打開香港地圖

- 派工：主規劃（專案「鐵道遊戲主規劃」工作串「買下台港航線就解鎖香港地圖」），照 `docs/research/AIR_ROUTE_ACQUISITION_DESIGN_2026-11-15.md` 第 6 節 A3。
- session：雲端 thread session，分支 `claude/project-thread-lewek6`。
- 決策 763（`docs/decisions/763.md`）。存檔、golden、fixtures、GameCore 不動。
- 做完：`AirRoutes.earned(in:)` 多「擁有一條飛那張地圖機場的航線」；`AirRoutes.opensByBuying`；`GameSession.onAirRouteBought`（收購成功後由 launcher 檢查，當下開航）；選地圖那一列、機場那一行的字；收購確認「價錢」段的註腳。測試在 `AirRoutesTests`（`testAnAirRouteToTheCityOpensIt` 等四個）。
- 還留下：
  - **A4**（3D，另開新串）：`Map3DAircraft` 照 `airRouteDepartureMinutes` 起降、跟隨飛機（設計頁 5.2）。
  - B 段（一局多張地圖、轉場、港幣）照設計頁，B0 量測先。
- UNVERIFIED：收購確認的註腳與選地圖那一列沒在模擬器、實機看過；App 的編譯交給 CI 的 Xcode 建置。
