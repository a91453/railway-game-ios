# CI 量測（2026-11-26，CIOPT-17）

> 0.6.0 (148) 發版例行的 CI 優化（規劃3 工作串「量測並加速 CI 時間」，分支 `claude/project-thread-3ydieb`）。上一輪是 CIOPT-16（#2698，`ec68d58`，147 之後：rest 權重、PR 不跑第一次啟動暖機），再上一輪 CIOPT-15（#2650）。門檻照 HANDOFF §1.1「CI 優化」：完整 `ci.yml` 比上一輪慢 20% 以上，或 PR tier 超過 30 分。

## 1. 量法

- GitHub Actions API：每個 run、job、步驟的開始與結束；shard 日誌裡每支 `Test Case` 的秒數按類別加總。
- 沒有為量測多開 run，全部是 11-25 到 11-26 已經跑完的。時間是 UTC。

## 2. 完整的 `ci.yml`

gate 結束的時間（不含 gate 不等的整天時刻表體檢）：

| run | 種類 | commit | gate | 最長的 shard |
| --- | --- | --- | ---: | --- |
| 45395190941 | 手動（146） | `0ecdedc` | 30.3 分 | rest-1 18.5 分 |
| 45526632957 | 夜間 11-25 | `d7f47c5` | 28.4 分 | rest-2 17.4 分 |
| 45650235089 | 手動（147） | `628fd6a` | 27.4 分 | rest-2 16.8 分 |
| 45733575677 | 夜間 11-26 | `8174381` | **36.9 分** | **rest-1 19.9 分** |

- 11-26 的夜間比 147 慢 35%，過線。分開看：從零建置 15.1 分（147 那次 10.1），慢的 runner；rest-1 19.9 分，比其他 shard 長 8 分；部分 shard 排隊 6.7–8.2 分（09:07 台灣時間開跑，和白天的 PR 搶 40 個 job）。
- rest-1 有 951 s 的測試，rest-2 只有 558 s。CIOPT-16 才照 11-25 與 147 兩次 run 重排過權重（預估 606/691、674/679），隔一晚就又偏了：重的類別幾乎都沒有長期穩定的時間（同一個類別換台 runner 差 30–50%），每天又有新的類別進 rest，權重一偏，重的幾個就落在同一邊。

rest 最重的類別（兩次 run 較慢的那次）：`FukuokaRailwaysTests` 82 s、`HongKongHarbourFerryTests` 63、`PlatformNameBoardStylesTests` 55、`Map3DHSRStudioStationTests` 53、`UndergroundStationsTests` 51、`TimetableCheckupTaiwanTests` 45、`TimetableCheckupTests` 44、`Map3DCoachesTests` 42、`KyushuShinkansenTests` 40。

### 2.1 夜間的整天時刻表體檢（不擋 gate，但擋發版）

11-26 夜間的 `ci.yml` 結論是紅，因為 `Timetable checkup / branch-lines-and-rovaniemi` 裡 `TimetableCheckupAllBoughtTests.testFukuokaLines` 紅：福岡地鐵 K+H+N simple 第 1 天「peak gap +5 min > +4」，比 main 的基準差（決策 844）。這不是 CI 速度的問題，已交協調者找人看；發版要那個 commit 的完整 `ci.yml` 綠。

## 3. PR 的 run（過線，主因是 macOS）

11-25 12:00 之後成功的 33 個 PR `ci.yml`：中位 34.8 分，20 個超過 30 分，最長 99 分。11-26 03:00 起常常 50–90 分。

拆一個最長的看（45760853540，`claude/project-thread-nqz1cq`，99.0 分）：

| 段 | 時間 |
| --- | ---: |
| 建置（有快取） | 3.4 分 |
| GamePresentation tier 八片 | 10.1–20.3 分（selected-3 最長） |
| Swift 部分完成 | 25.6 分 |
| gate 等 iOS 的 build job | **73.3 分** |

iOS 的 PR run（11-26 00:00 之後 60 個）：成功的 13–99 分，多數 50 分以上；同一個 PR 新推一次就取消舊的，有 8 個是排了 45–80 分之後才被取消。iOS build job 本身約 25 分（建置 12–13、開模擬器 2–3、gate 的 UI 測試 5），所以多出來的都是在等 macOS runner。

**誰佔了 macOS**（帳號一共 5 台）：

- 截圖：App Store 截圖串（`claude/project-thread-tj94j2`，#2726）11-26 03:11 起一直同時開 2 到 4 個 `website-screenshots.yml`，每個 45–76 分（kind store 一次最多 150 分）。03:11–06:40 共約 370 runner 分，等於平均將近 2 台一直被截圖佔走，PR 只剩 3 台。
- `ios-compilation-cache.yml`：main 合到 GameCore 就存一次快取，11-26 到 06:50 有 3 次，各 15–20 分加排隊。
- PR 本身：當天 40 多個 iOS PR run，一個 25 分，5 台一小時最多做 12 個。

## 4. 做了什麼

### 4.1 rest 最重的六個類別搬進最輕的 campaign（本 PR）

`.github/scripts/swift-shards.sh`：

| 類別 | 秒數 | 搬到 | 那片在 11-26 的測試時間 |
| --- | ---: | --- | ---: |
| `FukuokaRailwaysTests` | 82 | campaigns-9 | 6.4 分 |
| `HongKongHarbourFerryTests` | 63 | campaigns-1 | 6.7 分 |
| `UndergroundStationsTests` | 51 | campaigns-4 | 7.1 分 |
| `Map3DHSRStudioStationTests` | 53 | campaigns-10 | 7.2 分 |
| `PlatformNameBoardStylesTests` | 55 | campaigns-12 | 7.2 分 |
| `KyushuShinkansenTests` | 40 | campaigns-7 | 7.2 分 |

每片約多 1 分，仍比 campaigns-8（9.5 分）、-13（9.3 分）短。另外 7 個 rest 類別的權重差了一半以上，改成兩次 run 較慢的那次（`Map3DTrackKindsTests` 1 → 25、`AirportLineWholeIslandTests` 14 → 24、`Map3DCablewaysTests` 9 → 15、`Map3DSuspensionBridgeTests` 9 → 14、`HongKongAirportTests` 8 → 13、`Map3DFarSets420Tests` 1 → 13、`HeldDepartureMemoTests` 1 → 11）；搬走的六個也照實測更新權重（GamePresentation tier 用權重分片）。

rest 剩約 1,165 s。用同一套 `deal_part` 分法拿兩次 run 的類別時間模擬：

| run | 以前 rest-1／rest-2 | 以後 |
| --- | --- | --- |
| 45733575677（夜間 11-26） | 951／558 s（實測） | 616／554 s |
| 45650235089（147） | 508／844 s（實測） | 540／549 s |

完整 tier 最長的一片從約 20 分降到約 11–12 分（campaigns-8 的 9.5 分變成最長的 campaign）；夜間 `ci.yml` 的 gate 預估約 27–29 分。不跳過、不放寬任何測試。

不改的：rest 分成三片（多一個 job，40 個 job 的上限已經常常滿）；`TimetableCheckupTests`、`TimetableCheckupTaiwanTests` 留在 rest（PR 的 GamePresentation tier 也跑它們，搬不搬對 PR 沒差）。

### 4.2 iOS 建置優先用作者的 Mac（另一張 PR，等 runner 上線才合）

作者 11-26：「其實也能本地吧」「我 Mac 上就有 Xcode 只是我不知道怎麼讓他連結 runner」。做法與安全的考量寫在那張 PR 的決策 1014 與 `docs/MAC_RUNNER.md`；那張 PR 合之前什麼都不變。

### 4.3 協調（不改程式）

- 截圖串在發版的 PR 合完之前一次只開一個截圖 run（已請協調者轉告）。截圖是手動觸發、只有作者的 session 會開，Mac runner 上線後是最適合放到 Mac 的工作（`website-screenshots.yml` 正被 #2726 改，等它合了再接）。

## 5. 下一輪要看的

1. 下一次完整 `ci.yml`：rest-1、rest-2 都在 12 分以內，最長的一片不超過 campaigns-8。
2. `Map3DFarViewTests.testTheFarthestViewOfTaipeiIsWithinBudget` 一支 287–440 s，是整套最慢的一支（11-18 量是 98 s）：建一整片台北最遠視野、Linux 上 GamePresentation 是 -Onone。它在 GamePresentation tier 也落在一片裡（那片 20 分）。要快得改建景本身或測試的範圍，這輪沒動，寫成下一輪的第一項。
3. Mac runner 上線後：PR 的 iOS 排隊時間、Mac 上 build job 的時間（預估比 3 核心的 hosted 快）、工作室有沒有被拖慢。
