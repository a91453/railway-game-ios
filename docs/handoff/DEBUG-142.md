# DEBUG-141＋DEBUG-142（2026-11-21）

- 派工：新專案協調者（141、142 發版後例行的除錯；協調者另加 HEALTH-141 留下的 TYMC-881-ENDS）。雲端 Linux，分支 `claude/project-thread-4p4mh7`。
- 範圍：140→141（`be1e79e..c68cdcc`）與 141→142（`c68cdcc..9a77465`）。full lane 紅的三支 UI 測試、REVIEW-L29／L30、HEALTH-142 由別的工作串做，這裡沒碰。
- GameCore、存檔版本、golden schema、決策號都不動；這個 PR 只有這份交接。

## 做了什麼

1. **release 建置**（`main` `444ef70`，`swift build -c release -Xswiftc -enable-testing --build-tests`）：1,946 秒，**0 個警告**。
2. **看了 140→142 動到 GameCore 的 12 個檔**（決策 878 後來 TICK-TAIWAN、881 後來、883 旋律工作坊、885 `goesOn`、886、890 `shortRunsOnlyAtDayEdges`、894 `addAttractions`）：沒找到要修的。旋律的存檔檢查（`playerMelodiesProblem`）、站同時設官方與自寫旋律的互斥、刪旋律時站改回預設都對；`addAttractions` 照英文名補、有上限；GamePresentation 的 `withSights` 只對海外免費局，沒有海外的示範局會被它打開觀光。
3. **地圖包刪除／重新下載（#2500）**讀了 `MapPackDownloader` 與 `MapPackChoices`：沒找到問題（App 端，只能讀程式）。
4. **nightly** `ci.yml` 44835852885（`6a9e23d`，含 142 之後的模型）全綠，整日時刻表體檢也綠（141 時紅的福岡 K、N 與落馬洲已由 #2541、#2532 修好）。

## TYMC-881-ENDS（HEALTH-141 第 1 項）：查到原因，不是 881「後來」的錯，不改規則

重現：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_ONLY=tymc-rebuilt DEPOT_RETURN_EPISODES=1`，release 一格約 15 分，數字和 HEALTH-141 一樣（7/333、讓路 57；第 1 天 18:32、18:51，第 2 天 16:46、17:48、18:01，一、二航廈）。

用一個只在本機的開關（不進 repo）量 881「後來」那段放行：

| 做法 | 改建線 簡＋控 |
| --- | --- |
| 照 main | 7/333、死結 5 次、讓路 57 |
| 只在改建之後關掉那段 | 一樣死結（第 1 天 18:32 起，次數還多一點），沒發 5、讓路 40 |
| 整場關掉（含改建前的舊線） | 5/333、**死結 0**、讓路 35（＝`cc2f433`） |

記下每次放行：改建後兩天它只放行 3 次，都在第 1 天 18:35（老街溪），**比第一次死結晚**；改建前的舊線上只有兩段，第 0 天 18:24 老街溪、18:32–18:33 台北車站（空車 26 回台北，放行到點要開的 13 號）。這兩段正是 881「後來」該做的事。
從第 1 天 18:14 存的世界接著跑（8 秒就到死結），關掉那段一樣在 18:32 死結。

所以：881「後來」只改了改建當下各車的位置與先後，改建後的死結是舊的 **TYMC-A12-A13**（一、二航廈沒班的車互換月台：18:32 是 11 號停一航廈要去二航廈、25 號停二航廈要去一航廈，各占著對方要的那一股；24 號從 14:23 就停在二航廈）。決策 681 記過這三個機捷世界對小改動極敏感（加「到站後 1 分不讓」就翻面）。不收任何讓改建線回到 0 的硬改：它只會在另一格翻出來。

**結論：TYMC-881-ENDS 併進 TYMC-A12-A13（2.45），改建線 簡＋控的基準改成 7/333、死結 1–3 分的 5 次。** 每次 1–3 分鐘自己解開，沒發仍在門檻 ≤ 9 內。評分檔 railway-assets-private-2 `docs/priorities/HEALTH-141.md` 同步改。

存檔與重跑（給接 TYMC-A12-A13 的人）：
- 存世界：上面的指令加 `DEPOT_RETURN_SAVE=<檔> DEPOT_RETURN_SAVE_AT=152000 DEPOT_RETURN_UNTIL=152200`（`UNTIL` 要比 `SAVE_AT` 晚一分以上，否則迴圈在存之前就停了）。
- 接著跑：`DEPOT_RETURN_ONLY=tymc DEPOT_RETURN_FROM=<檔> DEPOT_RETURN_DAY=1 DEPOT_RETURN_UNTIL=153600 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_WATCH=152400-153120 … DepotReturnReportTests/testTheTaoyuanAirportLine`，8 秒。

## UNVERIFIED

- 實機（沒有改 App）。
- macOS／Xcode（沒有改程式）。
