# TIMETABLE-CHECKUP-ALL（2026-11-18）

雲端工作串「讓時刻表體檢涵蓋所有可收購路線」，分支 `claude/project-thread-29fqrf`。決策 844 的「後來」；存檔、golden schema、GameCore、GamePresentation 不動。

## 做了什麼

- 盤點三張地圖在售的真實路線（台灣 15、香港 6、羅瓦涅米 2）對照全日體檢：台灣、香港每條都有單買；缺的是羅瓦涅米單買，以及共用車站的線一起買（淡海兩線、六家＋內灣）。
- 新檔 `Tests/GamePresentationTests/TimetableCheckupAllBoughtTests.swift`：補上那些世界（夜間／手動，在 `branch-lines-and-rovaniemi` job），和兩個每個 PR 都跑的涵蓋檢查（約 2.4 秒）。
- 新世界的上限在那個檔的 `budgets`（六家＋內灣 4 格誤點 3，其餘 0）。原有的上限仍在 `TimetableCheckupTests.swift`。

## 還留下什麼

- 沒有新的問題要派（細節在決策 844「後來」）。
- 香港其餘六條線（屯馬、東鐵主線、荃灣、港島、觀塘、將軍澳主線）開賣時，涵蓋檢查會因為在售數變了而紅：把 `testEveryLineOnSaleIsPlayed` 的數字改掉，共站的組別（例如金鐘、北角）照紅字加一起買的世界。
- 整張地圖全買不做（作者 2026-11-18）。要量時：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=hk` 的 `DepotReturnReportTests/testHongKong` 買香港全部在售線。
