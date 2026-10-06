# Phase 5 轉乘與全網路徑：接手紀錄

> **2026-10-06 更新（決策 65）**：PR #142 已合併。下列「尚未完成」的第 2、3（跨 StationID 步行，改以距離推導）、4（多路徑契約在步行加入後已重跑）與 5（新遊戲啟用 `.network`）已完成，第 6 的架構決策記為決策 65。仍缺：站內通道／同月台分級成本、封站 operationMode、資料明確 pairs 匯入。以下是 #142 當時的紀錄。
>
> **2026-10-06 R1**：分級成本（同月台／通道／virtual）與封站 operationMode 已移植（決策 65 修訂、存檔 v12）；常數集中在 `PassengerTransferRules`。仍缺：資料明確 pairs 匯入、列車略過封閉站、末班自動狀態。

更新：2026-10-06。工作分支：`codex/phase5f-transfer-boarding`。目前是 WIP，請勿合併。Phase 5C 路由查詢已由 PR #136 完成；本分支接續 Phase 5F，讓需求產生的乘客按路徑搭車、轉乘、抵達。

## 分支上的實作

- `PassengerJourney.swift`：儲存乘客選定的完整路徑、目前路段、原起站；每組候車與乘車乘客可帶 journey。舊存檔中的群組仍可解碼。
- `PassengerDemand.swift`：新增 `.network` 模式，以 `passengerRoutes` 產生 OD 路徑選項，按票價調整需求，並用持久化的 `PassengerRouteBalance` 分配多條路徑。原有 `.direct` 模式是舊存檔的預設值。
- `Boarding.swift`：按路線、pattern、方向及實際停靠站上車；到轉乘站後排入下一段候車，同站跨線轉乘等待 4 分鐘。票價只在旅程第一段收取；原起站的守恆帳記錄轉乘候車乘客。
- `SavedGame.currentVersion = 11`；加入 `SaveFixtures/v11-network-transfer.json`，並檢查舊版存檔載入。不要修改既有 fixture。
- `PassengerTransferTests.swift`：19 項測試，涵蓋實際換車、同分鐘多路徑存檔、開／收班、尖峰、跨午夜、pattern 索引移轉、軌道／月台失效、停駛、轉乘溢出、反向旅程、一次收費、多路徑配額、存檔續玩及不合法 route credit。`RingLineTests` 另補反向跨圈換車。

原始實作提交：`fb709ca0a35b2af56375ab69ed7f78ba071deec1`；接手起點：`da51437f8e626db444852a108964e0d7de62993e`。本次接手完成下列穩定化，仍保留 draft PR #142，不合併。

- 批量推進在服務 window／level 改變時重建網路需求、保存 OD 餘數；沒有列車或釋出計畫時，idle shortcut 仍在開班邊界醒來。
- 候車旅程檢查所有未完成 leg 的實體路徑與每天實際可開行的服務；夜間關閉可以等待再開班，永久失效則記原起站 abandoned。服務命令成功後即重新檢查。
- 刪除 pattern 時，候車與乘車旅程移轉較後的索引；移除未來 leg 的 pattern 則放棄旅程。目前正在被移除 pattern 上乘車者可用既有時刻表完成這段，歷史 leg 不改寫。
- 同分鐘、同目的 leg 可有不同旅程；重複的相同候車身分合併，解碼拒絕重複的候車／乘車旅程及不合法配額狀態。跨圈旅程中途回到原起站仍可存檔。
- 原 CI 的兩個失敗是舊測試把存檔版本固定為 10；改為檢查 v10 功能的最低版本，v11 的明確契約仍由 `SavedGameTests` 驗證。未修改既有 save、golden 或 replay fixture。
- 原 iOS smoke 的人口熱圖測試點在 SwiftUI Form 開關列中央的文字，錄影顯示開關仍關閉。第一次改點整列尾端後，run `37451260299` 的狀態檢查確認仍未切換；介面樹顯示 labelled Switch 下另有實際的 UISwitch。最新測試先暫停示範地圖，定位內層 Switch 並使用其 activation point，確認 value 為 1 才關閉面板；保留圖例驗證。最新行為須由 macOS CI 驗證。

## 驗證狀態

- **VERIFIED（2026-10-06，本工作環境 Linux，Swift 6.4.0）**：`swift build --build-tests -Xswiftc -warnings-as-errors` 通過。
- **VERIFIED（同環境）**：`swift test --skip-build --filter 'PassengerTransferTests|RingLineTests|BoardingTests|PassengerDemandTests|PassengerRoutesTests|SavedGameTests|LinePatternTests|LineRoutePreferenceTests|SingleTrackCapacityTests'`：118 項、0 失敗。
- **VERIFIED（同環境，未降低 case 數）**：`SaveMutationTests/testMutatedRidersAreRefusedOrLoadConsistently` 與 `SaveMutationSecondHalfTests/testMutatedPassengersAreRefusedOrLoadConsistently`：2 項、0 失敗。
- **VERIFIED（同環境，完整分片）**：`.github/scripts/swift-shards.sh run campaigns-3` 與 `campaigns-21`：共 14 項存檔變異測試，0 失敗，選取／實際執行數一致。
- **VERIFIED（同環境）**：`git diff --check` 通過；本次接手未修改 `GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/`。
- **VERIFIED（接手起點的 GitHub Actions）**：已讀取 Swift CI run `37447758836` 和 iOS run `37447758606` 的失敗記錄；Swift 只有上述兩項版本斷言失敗，iPhone smoke 9 項中的地圖圖層測試失敗，其餘 8 項通過。iOS 編譯、專案同步均通過。取得 `.xcresult` 介面結構與畫面錄影，確認人口熱圖開關未切換。
- **VERIFIED（GitHub Actions，核心接手提交 `37c991d638e6f2796e4817d42e9c4761ecd54b37`）**：Swift CI run `37451260438` 的 23 個分片與 gate 全通過；867 項皆由分片選取並執行、0 失敗，僅需手動指定輸出目錄的 replay 錄製測試按設計跳過。Wasm Probe `37451260420`、App Localization `37451260391` 通過。iOS run `37451260299` 編譯與專案同步通過，smoke 8／9 通過，人口熱圖開關狀態檢查失敗；最新提交繼續修正此問題。
- **UNVERIFIED（本次接手提交，文件撰寫時）**：完整 Swift CI 與 iOS App Build 留待推送後 GitHub Actions；最新提交與結果以 [draft PR #142](https://github.com/a91453/railway-game-ios/pull/142) 為準。Linux 沒有 Xcode／Simulator；真機行為未驗證。

## 尚未完成：接手順序

1. 核對 PR 最新 head 的完整 Swift CI 與 iOS App Build；本地相關測試已完成，CI 若有新的紅燈須處理。
2. 移植不同 StationID 的步行轉乘，以及同月台／站內通道／跨站的時間成本。現有路徑圖與登車流程只支援**相同 StationID** 轉乘；`Railway/` 的 `station_transfers.json` 尚未接入。先一致設計 walking leg、所在站／抵達時間、原起站帳、容量與存檔語義。原生目前也沒有來源的封站 operationMode；不可把 service window 測試當成已完成封站。
3. 匯入時保留 transfer dataset 的明確 pairs、來源 system-scoped ID 與嚴格小於 450 m 的條件；同名正規化在 GameCore 外做。58 groups 的 members 有傳遞連通，不能自動展開成每對都能直接走的完整圖。資料沒有分級時間成本，仍需核對／決定原生政策。
4. 多路徑已驗證百萬人次 5:3:2 配額、切批一致、存檔續玩與服務選項變更。仍須在跨站／成本政策加入後重跑此契約；目前的 deterministic smooth weighted round robin 是對來源亂數分配的原生調整，不宣稱逐值相同。
5. 完成上述行為後，決定新遊戲何時啟用 `.network`；目前 `GameWorld`／`GamePresentation` 新遊戲預設 `.direct`，測試顯式開啟。確認玩家存檔遷移語義及 UI 指標。
6. 本次已補 `docs/ROADMAP.md`、`docs/RAILWAY_REFERENCE_MAPPING.md` 與 PR 來源對照；未新增 `docs/ARCHITECTURE.md` 決策。跨站／時間成本與新遊戲啟用需要明確架構決策及 review，完成後才考慮合併。

## 來源及重要位置

| 來源／契約 | 目前實作或待接位置 |
| --- | --- |
| PR #136 的 `PassengerRoutes.swift`、`LineJourney.swift` | `passengerRoutes` 供需求選路；pattern、實體路網與班距以既有服務查詢為準 |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` 的 `_metroSpawnODSplitCountByOptions`、`_metroNormalizeDispatchOptionWeights`、`metroExpandODDispatchPath` | `PassengerDemand.swift` 的 route choices；`PassengerRouteBalance.allocate` 的原生 deterministic 配額 |
| `Railway/site_archive_clean/data/station_transfers.json` 與 `index.html` 的站名／距離匹配 | 尚未接入；先定義跨 StationID 的轉乘資料模型與上下車行為 |
| `GameWorld.swift`、`StationPassengers.swift`、`Boarding.swift` | 權威狀態、候車群組、實際換車與原起站守恆 |
| `SavedGame.swift`、`SaveFixtures/v11-network-transfer.json` | v11 解碼與向後相容測試 |

來源檢查 commit：`2db0c5a6963798e6b86723bb001189343a59940c`；詳細來源函式、資料與差異見 `docs/RAILWAY_REFERENCE_MAPPING.md` 的 Phase 5F 節。本次接手處理同站轉乘穩定化與既有 CI 紅燈；跨站轉乘仍是下一個里程碑，車種、週需求及城市成長等後續項目尚未開始。
