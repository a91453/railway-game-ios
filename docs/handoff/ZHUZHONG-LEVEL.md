# ZHUZHONG-LEVEL（竹中兩條線一高架一地面）

- 派工：協調者，作者 140 實機（2026-11-19）。session：雲端工作串「讓竹中站變成真實月台」，分支 `claude/project-thread-wtslol`。
- 決策 875「後來（ZHUZHONG-LEVEL）」；存檔版本、golden schema、GameCore 不動。
- 做了：端點站附近有幾條描線時選讓路徑最短的那條（路徑不折返）；共站端點量間距只看站內與站外 40 m。竹中兩條線同在高架、同高、隔 11.4 m。
- 全地圖共站掃描（作者要的清單）：`SHARED_STATION_REPORT=<檔> swift test --skip-build --filter SharedStationLayoutTests/testReport`，
  140 的結果在專案共用資料夾 `shared-station-merge/scan-140.txt`。

## 還留下什麼

見決策 875「後來」的「還沒修」：濱海沙崙共用一島（兩條線共用股道）、欣澳與青衣（車道上的線）、只有內灣線的舊存檔、已買兩條的舊存檔。

## UNVERIFIED

沒有在 Simulator 或 iPhone 看過。下一版 TestFlight 請在新局（或拆掉重買）一起買六家線＋內灣線，看竹中是不是二樓一層、中間一座島。
