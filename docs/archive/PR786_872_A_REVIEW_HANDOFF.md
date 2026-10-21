# 交接：PR #786–#872 審查 A 組（行車控制與調度，GameCore）

Session：session_01E7zTjYUjLAZAyKtN2yszHu，遊戲規劃 session_01WW7o3decEv5LY59nYVqnDN 派工，2026-10-21。分支 `claude/pr786-872-review-a`。審查基準 `main` **f4f1b3a1**（#871 的合併）。之後合併的 #876（決策 302，`claude/hsr-depot-churn`）不在本組範圍，也沒有重跑。上一輪是 [PR755_784](PR755_784_REVIEW_HANDOFF.md)。#816、#822、#823 已由 [PR816_823](PR816_823_REVIEW_HANDOFF.md)（#828）審過，本輪只確認 R1–R4 的現況。

- 存檔版本、決策編號、golden schema 都**不動**。
- 本 PR 只加這份文件。GameCore、測試、GoldenScenarios、SaveFixtures、ReplayFixtures、workflow 都沒改，`docs/HANDOFF.md` 依派工也不改。
- 探針放在 session 的暫存目錄，沒有加入測試 target。寫法在第四節，要重跑時照著貼回即可。
- 以下 **VERIFIED** 都在 Linux、官方 Swift **6.4.0**（`/opt/swift`）實跑，不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 本組新發現 | **0** |
| 已修 | **0** |
| 延後（舊項目仍未修，或跨組轉來） | **3**：R3、R4（#828 留下）、B4（B 組轉來） |

每個 PR 都依派工的重點逐項查過，包括每秒存檔、批次對逐分、號誌開關兩種、死結、高鐵示範日。能在 main 上重現失敗的反例一個也沒有找到。出入庫相關也沒有發現，所以沒有要轉給決策 302 session 的項目。

## 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#790](https://github.com/a91453/railway-game-ios/pull/790) | `AutoService.swift`、`LineFeedback.swift`：待避線依地面判斷、兩端號誌燈。也跑了待避場景探針（每秒存讀、逐分對逐秒、invariant） | 無問題 |
| [#801](https://github.com/a91453/railway-game-ios/pull/801) | `ServiceDirections.swift`、`RunDepot.swift`、`GameWorld.swift`：跨 tick 保留的 `RouteMemo`。`ServiceKey` 涵蓋網路、無發車時刻的路線、車站、車庫、開關、營運日、車號與長度，任一改變就會失效。memo 不進存檔，讀回後重算，結果與連續執行一致（第三節的高鐵日逐分對讀回） | 無問題 |
| [#804](https://github.com/a91453/railway-game-ios/pull/804) | 決策 278，`Deadlock.swift` 的 `berthChange`、`Terminus.swift` 的 `leadsOnlyInto`。也跑了換股道場景（開閉塞）、終點站場景（含 depotBeyond 與閉塞關） | 無問題 |
| [#810](https://github.com/a91453/railway-game-ios/pull/810) | 決策 280，`Depot.swift` 的 `depotHasRoom`。也跑了車庫容量場景 60 分鐘 | 無問題 |
| [#811](https://github.com/a91453/railway-game-ios/pull/811) | 高鐵示範日加閉塞，`RouteReservation.swift`、`ScheduledOvertakeTracks.swift`、`ScheduledTraffic.swift`。跑了 `campaigns-16` 分片與整日逐分對讀回 | 無問題 |
| [#816](https://github.com/a91453/railway-game-ios/pull/816)／[#822](https://github.com/a91453/railway-game-ios/pull/822)／[#823](https://github.com/a91453/railway-game-ios/pull/823) | 只確認 #828 的 R1–R4：R1、R2 已由 #831 修好；R3、R4 仍可重現（第五節） | R3、R4 延後 |
| [#829](https://github.com/a91453/railway-game-ios/pull/829) | 決策 290，`RunDepot.swift` 的 `freeEndBerths`、`endHasRoom`、`pullOutBerths`。也跑了出庫場景（`oneFreeTrack`） | 無問題 |
| [#831](https://github.com/a91453/railway-game-ios/pull/831) | `TrainTrips.swift` 的 `retimeRunningTrip`、`Deadlock.swift` 的 `shortTurn`。重跑 #828 的 R1、R2 探針，都通過。也跑了折返加真實運轉場景 20 分鐘 | 無問題。另有 B4 延後，見第五節 |
| [#838](https://github.com/a91453/railway-game-ios/pull/838) | 決策 291，`LineRoutePreference.swift` 的 `stopIndices`（LCS）與 `movedRoutes`、`setLineStops` | 無問題 |
| [#845](https://github.com/a91453/railway-game-ios/pull/845) | 決策 294，`ApproachLocking.swift` 的 `approachLimit`（`approachReach` 896,000、`approachHold` 256,000，同 `TrackPoint` 的比例），以及 `timetabledOvertake` 的 `hold` 300 秒。也跑了接近鎖閉場景 40 分鐘與表定待避場景 | 無問題 |
| [#846](https://github.com/a91453/railway-game-ios/pull/846) | 決策 296，`cameOutOfDepot`；只計可到達的出入庫。也跑了車庫來回場景 | 無問題 |
| [#863](https://github.com/a91453/railway-game-ios/pull/863) | 決策 297，`trainsInTheWay`。也跑了擋路車庫場景 | 無問題 |

## 三、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| 場景探針（debug），共 11 個：接近鎖閉 40 分、表定待避、車庫來回、擋路車庫、出庫（`oneFreeTrack`）、車庫容量 60 分、換股道（開閉塞）、終點站（一般／depotBeyond／閉塞關）、折返加真實運轉 20 分 | **VERIFIED**，0 失敗 |
| 號誌關的高鐵示範日（release），05:00 到隔日 05:00。另有一份每 15 分鐘讀回的存檔與連續執行逐分比對，以及每小時一次的 60 分鐘批次 | **VERIFIED**，0 差異，115 秒 |
| 行車控制加閉塞的高鐵示範日（release），同上的逐分對讀回與小時批次 | 見下方「行車控制整日」 |
| 分片 `campaigns-16`（`swift-shards.sh run campaigns-16`） | **VERIFIED**，6/6；HighSpeedDemoDayTests 210.7 秒、HighSpeedDemoBatchTests 122.3 秒、TRADemoDayTests 78.4 秒 |
| `python3 -I tools/golden-checks/doc_numbers.py --check` | **VERIFIED**，0 差異（存檔 64、fixture 68、golden schema 74、golden 77、replay 9、決策到 303） |
| `swift build --build-tests -Xswiftc -warnings-as-errors` | **VERIFIED**，乾淨（本 PR 不改程式） |

場景探針每一個都做以下檢查：

- 以 `.x10`（一秒一 tick）執行；
- 每秒做 `WorldInvariants.roundTripProblem`；
- 每 10 秒存讀一份副本，與繼續執行的世界比對；
- 用逐分步進對照逐秒步進；
- 最後做 `WorldInvariants.violations`。

這樣涵蓋了折返、出入庫、待避等待的每一秒存檔。

行車控制整日（行車控制加閉塞）：

- 05:00–07:00 **VERIFIED**：逐分對讀回與小時批次 0 差異，0 死結。
- 之後的時段仍在跑；跑完後補在這裡。
- 早高峰之後，一分鐘要 1–2 秒，比號誌關的整日慢得多。這不是錯誤，但記下來，給量測效能的人參考。

沒有做到的：

- 行車控制開、閉塞關的整日，太慢，中途停掉了。
- 示範日 05:30–07:30 與 21:30–23:59 的逐秒存檔窗，也是中途停掉。

這兩項列為 **UNVERIFIED**。場景探針已經以逐秒存檔涵蓋同樣的折返、出入庫與待避情況。

## 四、探針寫法

- **場景探針**：把 `ApproachLocking`、`TimetabledOvertake`、`DepotShuttle`、`InTheWayDepot`、`PullOutRoom`、`DepotRoom`、`BerthChange`、`Terminus` 這幾個測試類別複製成 `RA…Support`，拿掉 `private`。用 `RAxxxSupport(name: "s") { _ in }.makeScene()` 取得場景，再交給 `check(name, world, minutes)`，做第三節列的那幾項。`BerthChange` 的場景只在閉塞開時成立（閉塞關會丟出 `trackReserved`），不算發現。
- **示範日**：照 `TrafficControlTimingReportTests` 的方式建世界：
  1. `HighSpeedDemo.Layout(railways:heights:)`；
  2. `newWorld`、`build`、`setSpeed(.normal)`；
  3. 先開行車控制與閉塞，再 `advance(ticks: 300)` 到 05:00。

  直接對已開好的示範（07:00）呼叫 `setTrafficControl(true)` 會丟出 `trainsShareTrack(1, 8)`。這是開關的既定前提，不算發現。
- 輸出導向檔案時，`print` 會被緩衝。要看即時進度，用 `stdbuf -oL` 包住 test runner。
- 要避開 SwiftPM 鎖，直接執行 `.build/{debug,release}/GameCoreTests-test-runner <Class>/<method>`。

## 五、延後的項目

### R3（#828，#822 的閉塞分界只看車頭），P2，仍未修

- **重現**：`testBlockHeadClearButTailFouls`（#828 附錄）在 main 仍失敗。分界 22,400 時，`branchFouled` 有 6 筆。
- **預期與實際**：預期整列車離開岔線區才清空；實際車頭過了就清空。
- **為什麼延後**：要改的是閉塞清空的契約（整列車或只看車頭）。這會牽動閉塞開時的 golden 與 replay 值，屬設計變更。
- **建議**：`isClear` 改用車尾位置判斷，並重新驗證 golden 與 replay。交 #822 的作者評估。

### R4（#828，`WorldInvariants.violations` 遇到 v28 自動結構會 trap），P2（測試工具），仍未修

- **重現**：設 `REVIEW_FIXTURE=v28-terrain-track.json` 跑 #828 的 R4 探針，在 `ReferenceVertical.swift:81` 停在 "the reference model of decision 30 has no automatic structure"。
- **探針的過期處**：fixture 現在有 68 份，探針裡的 `count == 67` 斷言已經過期，重跑時改成 68。
- **為什麼延後**：這是參照模型 `ReferenceWorld` 本身的限制，與本組的行車規則無關。
- **建議**：參照模型補上自動結構，或讓 `violations` 對它不支援的結構回報而不是 trap。交 `ReferenceWorld` 的作者。

### B4（B 組 #874 轉來：折返晚於原定返程時刻時，時刻表不變），P3

- **重現**：拿 #828 的 `testShortTurnRepeatingAndAlreadyLate`，把移動速率設為 0，只用指令操作。列車在 540 秒折返，晚於表定的返程 406 秒。決策 288 規定時刻「只提前、不延後」，所以時刻表沒有動，畫面上的 `shortTurnCall` 因此認不出這是一次折返。
- **預期與實際**：預期畫面認得出這次折返；實際認不出，屬顯示問題。
- **B 組的建議修法不安全**：B 組建議把跳過的停靠改成「現在」。但這樣時刻表會變成非遞增，而 `Train` 解碼（`Train.swift:354`，`ScheduledStop.isTimetable`）會拒絕這種時刻表，結果會變成存檔讀不回（P1）。
- **為什麼延後**：
  - 正確的修法在 GameCore，是把之後的停靠移到「不早於現在」。但這違反決策 288 的「不延後」，而且要重新驗證 golden 與 replay。
  - 另一個修法在 GamePresentation：從行程紀錄辨認折返。這不在本組的範圍。
- **處理**：已用 send_message 回覆 B 組 session_01E3oRjatcqtfWgatbqPbcr1。
