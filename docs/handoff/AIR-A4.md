# AIR-A4：玩家航線的飛機照時刻起降、跟飛、航班視窗

- 派工：主規劃（專案「鐵道遊戲主規劃」工作串「讓飛機照時刻起降並跟飛」），照 `docs/research/AIR_ROUTE_ACQUISITION_DESIGN_2026-11-15.md` §5.2、§6 的 A4。
- session：雲端 thread session，分支 `claude/project-thread-gkfu82`。
- 決策 771（`docs/decisions/771.md`）。存檔、golden、fixtures、GameCore 不動。
- 做完：
  - `Map3DAirRouteFlights.swift`：`Map3DAircraft.Traffic.routes`、`Leg`、`FlightID(leg:landing:)`；航線班機照 `airRouteDepartureMinutes` 起降、從一般班次扣掉、公司塗裝；爬升到 `cruiseHeight`（3,000 m）並轉向目的地（`Laid.climbed`）。
  - `AirFlightWindow.swift`：航班視窗的內容、到 3,000 m 開視窗、國內線落地前 90 秒改跟落地。
  - App：`Map3DFlightWindow`（`Map3DPreviewScreen.swift`）、`Theme.flightSky…`、航線改變時重算當天班次。
  - 測試：`AirRouteFlightsTests`（8 個）。截圖：`WebsiteScreenshotTests.testAirRouteFlight`（場景 `airRouteSongshan`、`airRouteSongshanNone`）。
- 還留下：
  - 航班視窗的 3D 飛機、雲的動態、機艙音（設計頁 C4）。
  - B 段：B0 量測 → B1 → B2 → B3（跟到香港時視窗當讀取畫面）。
- UNVERIFIED：實機沒看過；國內線在全台灣地圖上「接著跟澎湖落地」只有 Linux 測試，截圖場景是松山附近的小地圖（澎湖不在圖上），沒拍到落地那段；放手後鏡頭停在 3,000 m 的位置，回到地圖時要自己拉回來。
