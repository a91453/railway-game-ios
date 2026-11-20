# EAL-LMC-PEAK-GAP（2026-11-20）

- 派工：協調者（bug）。雲端 Linux，工作串「修東鐵綫落馬洲尖峰間隔變差」，分支 `claude/project-thread-lf2m8p`，決策 881 加「後來」一節，沒有新決策號。
- 存檔版本、golden schema 不動；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。

## 做了什麼

- 夜間 `ci.yml` 44640398797（`main` `698aaba`）`hk EAL_LMC simple` 尖峰 +9 > +7。二分 `be1e79e..698aaba`（26 個合併）：第一個壞的是 #2491（決策 881）。
- 成因與修法在決策 881「後來」：晚點的進站車照它到得了的時刻，和終點那列沒班的車的下一班比。`RouteReservation.swift` 三行。落馬洲回到 0／40／0／+7。
- `TimetableCheckupTests/testTheLokMaChauBranchDay`：落馬洲支綫的整日體檢進每張 PR 都跑的那組（約 15 秒），之後不用等夜間才知道。
- 福岡三線新局的尖峰上限 +4 → +5（空港線最長空窗多 24 秒），理由在決策 881「後來」。

## 還留下什麼

- 評分在私有庫 `docs/priorities/EAL-LMC-PEAK-GAP.md`：新局規則下沒有機廠的線（福岡三條、落馬洲），端點站白天靠決策 881 那一步逆線換月台，福岡一天幾百次。那一步是為收班過夜寫的；白天該由換月台（決策 57 的 `alternativeRoute`）在端點站自己做，像擬實的端點豁免（決策 278）。
- 二分的做法（可重用）：腳本先 `swift build --build-tests`，再跑 `TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_ONLY="<世界>" swift test --skip-build --filter 'TimetableCheckupFullTests/<測試>$'`，從輸出的 `peak gap +N min` 判好壞，`git bisect start --first-parent <壞> <好>` 後 `git bisect run`。每一步重建約 8 分鐘（4 核）。

## UNVERIFIED

- iOS、實機沒有看（沒有改 App）。
- 擬實整日體檢沒有跑（這一步在閉塞區間開的時候不走）；台灣 15 線全買沒有跑。交夜間 CI。
