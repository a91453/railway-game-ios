# HK-PEAK-CONTROL（2026-11-18）

- 派工：新專案協調者（`docs/priorities/REVIEW-L27.md` 第 1、8 列，`docs/priorities/DEBUG-137.md` 第 1 列）。雲端 Linux，分支 `claude/project-thread-yrhzre`，決策 849。
- 存檔版本不動（108）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。

## 做了什麼

- 決策 849：沒有閉塞區間時，班次跑全線、每站都停的路線上，服務往它折返或終到的站、整條路空著才出發時，只拿到下一站咽喉前的進站號誌，離號誌 1 km 內才拿進站的路；停在號誌前的車只 claim 拿著的路與它的月台，後面的車可以跟它。`ApproachLocking.swift`（`homeLimit`、`throatPoint`、`claimCover`、`holdsToItsApproach`、`approachLimit(of:holding:_:)`）。
- 香港新局預設（簡化＋管制）兩線第二天沒發 26 → 1/732（南港島綫 23 → 0，剩的是東涌綫清晨 06:17 的 TCL-DAWN）；29 個世界的比對在決策 849 §3，其餘世界與 `main` 一樣。
- HK-CTRL-DEADLOCK（REVIEW-L27 第 8 列）：決策 836 之後 `main` 已是 0 死結，結案。但這個 PR 之後車位變了，`main` 潛伏的 TCL-DEPOT-CLAIM 在每晚 00:03、00:10 各出現一次 1 分鐘的 5 列死結，自己解開；排在評分檔 `docs/priorities/HK-PEAK-CONTROL.md` 第 1 列。
- 時刻表體檢順便量到：東鐵綫（落馬洲）新局沒發 15 → 0、將軍澳綫（康城）新局誤點 92 → 0（`docs/priorities/TIMETABLE-CHECKUP.md` 第 1、3 列的新局那一半）。
- 測試：`HomeSignalTests`（GameCore）、`HongKongDepotTests.testTheSouthIslandLineMorningPeakSendsEveryRun`；`TIMETABLE_CHECKUP_RUNS=1` 列出體檢裡沒發與出庫誤點的是第幾班。

## 還留下什麼

- 評分檔 `docs/priorities/HK-PEAK-CONTROL.md`（私有庫 `a91453/railway-assets-private-2`）：TCL-DEPOT-CLAIM（先修）、HK-PEAK-REALISTIC（擬實的南港島綫仍 10/458）。
- 時刻表體檢的上限已照量到的改（`TimetableCheckupTests.swift`，決策 849 §3 的表）：南港島綫、東鐵綫（落馬洲）、將軍澳綫（康城）新局調低；東涌綫出庫誤點 6 → 7、PR 版誤點 101 → 118 是調高，逐班的理由在決策裡。修 TCL-DEPOT-CLAIM 的人把東涌綫那格調回去。
- TCL-DAWN（東涌綫清晨 06:17 等 3 班）照舊歸 DEPOT-DAWN-QUEUE（決策 841 那一串）。

## UNVERIFIED

- iOS 實機、畫面：沒看（雲端沒有 Xcode）。運行圖上金鐘出站的車先過渡線、進站車在號誌前停一下，是規則推出來的，沒在畫面上看過。
- 量測是 Linux debug（GameCore -O）；CI 的 shard 由 PR 的 CI 跑。
