# TYMC-DAWN-TAIPEI 交接

## 進度

- 做到哪：修好機捷擬實清晨台北車站的班（決策 954），PR 見 #2118 的回報。新局規則（沒有閉塞）的機捷清晨沒有修。
- 已驗證（雲端 Linux debug，main `ec720bd`）：`tymc:A realistic` 第二天 1／8／3／+4 → 1／5／2／+4，台北清晨晚的班 4 → 1；香港、台灣其他線擬實、台鐵支線與 `main` 相同；`DawnRunDepotTests` 新測試。
- 下一步的第一個指令：沒有待辦。要接新局規則的機捷時：`TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_RUNS=1 TIMETABLE_CHECKUP_ONLY="tymc:A simple" swift test --skip-build --filter TimetableCheckupFullTests/testTaiwanMetroLines`。

## 做了什麼

- 派工：遊戲規劃協調者第 3 任，2026-11-24（評分 2.65）。session_01JMHz9cg6vfda9XPsGCGaDj，分支 `claude/tymc-dawn-taipei`，決策 954。存檔版本、golden schema、fixtures 都不動。
- 改的檔：`Sources/GameCore/Railway/RunDepot.swift`（`dawnRunsKept`、`dawnKeepDepotRun`，接進 `runDepotEntryCandidates`）、`Tests/GameCoreTests/DawnRunDepotTests.swift`、`Tests/GamePresentationTests/CheckupBudgets/Taiwan.swift`（只收緊）、depot-work 技能第 5 節一列。

## 還留下的

- **新局規則的機捷**（`TYMC-QINGPU-FULL`，2.70）：同一條規則在沒有閉塞時讓台北清晨變準，但 09:00–17:00 台北每小時晚 4–8 班（整天 92 → 133）。量到的現象：晚 5–12 分不觸發從機廠補車（蘆竹 22 分遠），台北的折返就一直晚；`main` 清晨晚 20 分以上，會補車，10:45 以後追回。這是推測的機制，沒有單獨驗證。要修先查「小幅晚點時的折返」，再回來試留車。
- **05:58 長庚醫院沒發、06:07 長庚醫院晚 28 分**：蘆竹清晨出庫的排隊（決策 841、DEPOT-DAWN-QUEUE），沒碰。
- 量測用的探針（04:00 各站停幾列、各端點到機廠的空車分鐘數、中午誰停在哪）沒有合進 main；做法寫在決策 954「先做出會紅的指令」，照 `TimetableCheckup.play` 加幾行即可。

## UNVERIFIED

- 實機、Xcode、iOS 模擬器都沒有跑（雲端 Linux）；改動只在 GameCore 的調度規則與測試。
- 新局規則整天的檢查、完整測試留給 CI。
