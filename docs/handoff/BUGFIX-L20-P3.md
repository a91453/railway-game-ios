# BUGFIX-L20-P3：審查留下的三個小修（2026-11-13）

- 作者 2026-11-13 在專案討論串說「修 bug」「看你」。分支 `claude/project-thread-5hrywn`。登記在 #2118。
- 不佔決策號（沿用 715，加第 9 節）；存檔版本、golden schema、`SaveFixtures/`、`ReplayFixtures/`、`GoldenScenarios/` 都沒動。

## 修了

| 項 | 做法 | 驗證 |
| --- | --- | --- |
| REVIEW-L20 P3-2、P3-3 | `termLoansProblem()` 擋 `borrowedDay` 早到相減溢位、`nextTermLoanID == Int64.max` 的存檔（決策 715 第 9 節） | `TermLoanTests` 加兩行；由 CI 跑 |
| REVIEW-L19 P3-17 (c) | `RealRailwayOperations.systemOrder` 最後補 `hkmtr`。香港地鐵原本就因為是唯一「不在表上」的系統而排在最後，所以畫面順序不變；補的是表與 `siteSystems` 對齊，之後再加系統不會把香港擠到別的位置 | `RealRailwayOperationsTests.testEverySystemHasItsPlaceInTheOrder`；由 CI 跑 |
| REVIEW-L19 P2-3 | 3D 地圖換日時當天的航班改在背景算（`Map3DTrainFeed.laidAircraft`、`counted`）；算好之前沿用前一天的，機場重鋪後算好之前只畫停著的飛機 | 只有 iOS CI 編得到；模擬器、實機 UNVERIFIED |

## 沒修

- REVIEW-L20 P3-1：不改規則，理由在決策 715 第 9 節。
- REVIEW-L20 P2-2（4 GB 機型）要實機；P2-4、P2-7 的更新說明由規劃在 130 發版前寫。
- #2115 模擬器上香港那一列沒出現：另一個討論串在追。

## UNVERIFIED

- 這個雲端環境的網路政策擋 `download.swift.org`，裝不了 Swift 6.4，所以**本機沒有建置、沒有跑任何測試**；全部交給 CI。
- 航班改背景算之後換日那一下還卡不卡，沒有量（報告原本也沒量，PLAUSIBLE）。
