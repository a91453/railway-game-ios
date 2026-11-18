# DEBUG-138（2026-11-18，#2423）

138 發版後的除錯（決策 819 的後來）看 137→138 的 GameCore 時留下的一項。交接在 `docs/handoff/DEBUG-138.md`。尺同 NEXT_PRIORITIES §19。

| 順位 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 | 狀態、注意 |
| --: | --- | --: | --: | --: | --: | --: | --: | --- |
| 1 | bug：**APPORTION-BOUND** `GameWorld.apportion(_:by:)` 的註解說 `total` 至多 `maximumDailyTrips`（100 萬），但 `trips(of:at:)` 乘了活動與假日倍數會超過；決策 828 的遠距權重（吸引力 × 1000）再乘上去，起訖兩站都接近每日 100 萬人次、兩站都有大活動又逢假日時 `total × weight` 會超過 Int64 而當掉。實際地圖最大的站遠低於這個值，量不到 | 1 | 2 | 1 | 1 | 1 | 1.25 | 未派；動 GameCore（`PassengerDemand.swift`），改用 `multipliedFullWidth` 或把上限寫對；跟下一張碰 `PassengerDemand` 的單一起做 |

五方：
- 玩家：現在的地圖碰不到，玩家看不到（1）。
- 開發：只是註解與一個極端值的防護，改了要跑 GameCore 全套 CI（2）。
- 美術：無（1）。
- 鐵道迷：無（1）。
- 音樂：無（1）。
