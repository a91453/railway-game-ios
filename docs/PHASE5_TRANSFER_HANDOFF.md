# Phase 5 轉乘與全網路徑：接手紀錄

更新：2026-10-06。工作分支：`codex/phase5f-transfer-boarding`。目前是 WIP，請勿合併。Phase 5C 路由查詢已由 PR #136 完成；本分支接續 Phase 5F，讓需求產生的乘客按路徑搭車、轉乘、抵達。

## 已推送的實作

- `PassengerJourney.swift`：儲存乘客選定的完整路徑、目前路段、原起站；每組候車與乘車乘客可帶 journey。舊存檔中的群組仍可解碼。
- `PassengerDemand.swift`：新增 `.network` 模式，以 `passengerRoutes` 產生 OD 路徑選項，按票價調整需求，並用持久化的 `PassengerRouteBalance` 分配多條路徑。原有 `.direct` 模式是舊存檔的預設值。
- `Boarding.swift`：按路線、pattern、方向及實際停靠站上車；到轉乘站後排入下一段候車，同站跨線轉乘等待 4 分鐘。票價只在旅程第一段收取；原起站的守恆帳記錄轉乘候車乘客。
- `SavedGame.currentVersion = 11`；加入 `SaveFixtures/v11-network-transfer.json`，並檢查舊版存檔載入。不要修改既有 fixture。
- `PassengerTransferTests.swift`：驗證兩線 A→B→C 實際換車、原起站乘客守恆、存檔往返，以及批量推進與逐分鐘推進一致。

已推送程式提交：`fb709ca0a35b2af56375ab69ed7f78ba071deec1`。此文件將另行提交。

## 驗證狀態

- **VERIFIED（本工作環境，Swift 6.4）**：`swift build --build-tests -Xswiftc -warnings-as-errors` 通過。
- **VERIFIED（本工作環境）**：`PassengerTransferTests` 2 項、`SavedGameTests` 23 項通過；`git diff --check` 通過。
- **UNVERIFIED（目前提交）**：完整 Swift CI、iOS App Build、其他 GameCore 測試類別、真機行為。先前執行過的 `BoardingTests` 不涵蓋本提交最後一輪改動，須重跑。

## 尚未完成：接手順序

1. 先跑 `BoardingTests`、`PassengerDemandTests`、`PassengerRoutesTests`、`RingLineTests`，再看 draft PR 的 Swift CI 和 iOS App Build；對紅燈修正並推送。測試類別名稱以 `swift test --list-tests` 或檔案內容核對。
2. 檢查旅程和服務在路線刪除、pattern 改動、軌道斷裂、封站、列車停駛時的處理。`makeNetworkPassengerPlan()` 在一次 `advance(ticks:)` 開頭快取路徑；同一批推進途中服務變化是否要重建，尚未證明。補上守恆、轉乘溢出、反向和環線測試。
3. 移植不同 StationID 的步行轉乘，以及同月台／站內通道／跨站的時間成本。現有路徑圖與登車流程只支援**相同 StationID** 轉乘；`Railway/` 的 `station_transfers.json` 尚未接入。跨站轉乘需要路徑、候車位置和存檔格式一致設計。
4. 檢查多路徑權重與 `PassengerRouteBalance` 的長期分配、存檔往返、服務選項變更和大數量乘客情境。此處目前只有基本測試。
5. 完成上述行為後，決定新遊戲何時啟用 `.network`；目前 `GameWorld` 預設 `.direct`，測試以 `setPassengerRoutingMode(.network)` 顯式開啟。確認 `GamePresentation` 新遊戲流程、玩家存檔遷移語義及 UI 指標。
6. 更新 `docs/ROADMAP.md`、`docs/RAILWAY_REFERENCE_MAPPING.md` 和架構決策；PR 內列出來源對照與缺口，完成 review 後才考慮合併。

## 來源及重要位置

| 來源／契約 | 目前實作或待接位置 |
| --- | --- |
| PR #136 的 `PassengerRoutes.swift`、`LineJourney.swift` | `passengerRoutes` 供需求選路；pattern、實體路網與班距以既有服務查詢為準 |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` 的 `_metroSpawnODSplitCountByOptions`、`_metroNormalizeDispatchOptionWeights`、`metroExpandODDispatchPath` | `PassengerDemand.swift` 的 route choices／路徑配額；仍須核對邊界值與權重 |
| `Railway/` 的 `station_transfers.json` 與站名／距離匹配 | 尚未接入；先定義跨 StationID 的轉乘資料模型與上下車行為 |
| `GameWorld.swift`、`StationPassengers.swift`、`Boarding.swift` | 權威狀態、候車群組、實際換車與原起站守恆 |
| `SavedGame.swift`、`SaveFixtures/v11-network-transfer.json` | v11 解碼與向後相容測試 |

本分支只處理第 1 項的 Phase 5F 後半段；車種、經濟、週需求及城市成長等後續項目尚未開始。
