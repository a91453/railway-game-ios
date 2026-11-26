# POST-148-CI-DEBUG：0.6.0 (148) 發版後的例行 debug

## 進度

- 做到哪：main `f1da01c` 的完整 `ci.yml`（run 45805083341，和發版的 `9d4a7d2` 程式相同）只有香港時刻表體檢紅；原因找到了（#2727 香港 2021 普查人口，決策 1008），**預算還沒改**。這個 session 壓縮第 2 次，依規定停手。
- 已驗證：本機（Linux，Swift 6.4）用 main 的資料跑 `hk SIL simple` 得 80 班誤點、1 班出庫誤點，和 CI 一樣；把 `RailwayGameApp/Resources/` 香港的 `pack.json`、`population.json` 換回 `8174381`（上一次夜間全綠）的版本，同一個世界變回 70／0，過關。其他世界沒有本機重跑，用 CI 的數字。
- 下一步的第一個指令：改 `Tests/GamePresentationTests/CheckupBudgets/HongKong.swift`（下表），再用手動 `ci.yml` 在分支上跑一次（只有夜間與手動 run 有 `timetable-checkup`），看 `hong-kong-realistic`、`hong-kong-simple` 兩個 job。

- 派工單：發版例行 debug（規劃3「修好 main 上不穩的測試」串），分支 `claude/project-thread-j5zrxi`。
- 決策、存檔版本、golden：都不動。前面已合的 #2746（UI 測試重試一次、容器拉取的逾時）、#2749（shellcheck）記在決策 582 的「後來」。

## 香港體檢：量到的數字（run 45805083341）

job 139863811166（hong-kong-realistic）與 139863811312（hong-kong-simple）的 `TIMETABLE_CHECKUP` 行。「現在預算」是 `HongKong.swift` 在 `f1da01c` 的值。

| 世界 | 現在預算（不發／誤點／出庫誤點／尖峰間隔） | 量到 | 結果 |
|---|---|---|---|
| hk EAL_LMC realistic | 0 / 9 / 0 / +3 | 0 / 15 / 0 / +7 | 紅（15 > 9+2，+7 > +3） |
| hk SIL simple | 0 / 70 / 0 / +8 | 0 / 80 / 1 / +6 | 紅（80 > 70+3，出庫 1 > 0） |
| hk TCL simple | 1 / 62 / 6 / +19 | 1 / 67 / 7 / +19 | 紅（67 > 62+3，出庫 7 > 6） |
| hk TCL+AEL+DRL simple | 1 / 62 / 6 / +19 | 1 / 67 / 7 / +19 | 紅（同上） |
| hk EAL_LMC simple | 0 / 40 / 0 / +7 | 0 / 36 / 0 / +7 | 比預算好，可降 |
| hk SIL realistic | 0 / 88 / 0 / +7 | 0 / 68 / 0 / +6 | 比預算好，可降 |
| hk TCL realistic | 0 / 17 / 1 / +13 | 0 / 11 / 1 / +6 | 比預算好，可降 |
| hk TCL+AEL+DRL realistic | 0 / 17 / 1 / +13 | 0 / 11 / 1 / +5 | 比預算好，可降 |

AEL、DRL、TKL_LHP 兩種規則都是 0 / 0 / 0 / +0，沒有預算列，不用動。

細節：南港島綫 simple 一天 458 班，尖峰最大間隔在金鐘 18:29（11.0 分對時刻表 5.8 分）；東涌綫 simple 274 班，最晚一班 29.1 分，香港站 07:56 間隔 27.1 分對 9.0 分（+19 是改資料以前就有的）。

## 為什麼是重定預算、不是改回資料

#2727 是刻意的資料改動（香港的人口與工作換成 2021 年普查，決策 1008），車站的乘客變了，停站時間跟著變，所以東鐵與南港島綫、東涌綫 simple 的誤點多了幾班，另外三個 realistic 世界反而少了。決策 844 的預算是「main 的數字」，資料刻意改了，預算就要跟著改，在 `HongKong.swift` 的註解逐值寫：哪個世界、從多少到多少、因為 #2727（決策 1008）。也在決策 1008 加一段「後來」記這次的數字。

紅的四個世界照量到的值寫；比預算好的四個也可以一起降到量到的值（測試會印「lower it」）。

## 還沒看的

- iOS full lane run 45805119006（`f1da01c`，11-26 10:50 UTC 開始）：11:25 UTC 時三個 UI 工作還在跑，建置、開機、暖機都綠。下一個 session 看結果；有測試只在重試才過，`ui-retry-report.sh` 會在 job 摘要列出來。
- 福岡夜間（決策 582「後來」）：`8528dd0` 量到 +3.7、預算 +4，過關但很貼近；下次重鋪地圖包時手動跑一次體檢。
