# TYMC-PEAK-CASCADE 交接

## 進度

- 做到哪：修好下午尖峰的連鎖（決策 948），PR 已開；早上台北車站那幾班沒修，另評一項。
- 已驗證（雲端 Linux，併了決策 943 的 main `12561cb`）：`tymc:A realistic` 第一天 1／20／6／+13 → 1／8／3／+4；其他擬實世界一字不差；`SurplusRunDepotTests` 新測試舊規則下紅。
- 下一步的第一個指令：沒有待辦。要接早上那一項時：`TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_RUNS=1 TIMETABLE_CHECKUP_ONLY="tymc:A realistic" swift test --filter TimetableCheckupFullTests/testTaiwanMetroLines`，看 06:00–07:00 晚的班。

## 做了什麼

- 派工：遊戲規劃協調者第 3 任，2026-11-23（評分 2.95，assets-2 `docs/priorities/TYMC-PEAK-CASCADE.md`）。session_01JMHz9ZbN5z32Fci1i45YLw，分支 `claude/tymc-peak-cascade`，決策 948。存檔版本、golden schema、fixtures 都不動。
- 原因、規則、每種做法的數字、改動的基準：`docs/decisions/948.md`。
- 改的檔：`Sources/GameCore/Railway/RunDepot.swift`（`countsSurplus` 多一個站的參數）、`Tests/GameCoreTests/SurplusRunDepotTests.swift`、`Tests/GamePresentationTests/CheckupBudgets/Taiwan.swift`（只收緊）、`.claude/skills/depot-work/SKILL.md` 第 5 節一列。

## 還留下的

- **早上台北車站 06:15–07:00 的班**（`TYMC-DAWN-TAIPEI`，assets-2 `docs/priorities/TYMC-DAWN-TAIPEI.md`，2.65）：靠前一晚留在台北車站的車，留 3 列晚 6–9 班，留 2 列 11 班。決策 948「還留下的」有量到的數字。沒試過的方向（推測）：收班時先看隔天清晨那一站在第一列車到站以前要開幾班，留夠那個數目的車在月台，其餘才回機廠。`TYMC-QINGPU-FULL` 交接檔試過「夜裡把月台上的車開到出庫最遠的一端」，變差，別重試。
- 新局規則（沒有閉塞）的機捷沒有變（條件沒改）；`TYMC-QINGPU-FULL` 的 15:49 那班在新局規則下的原因沒有另外查。
- 量測用的探針（每分鐘記下每列車的位置與等誰、換高度檔、從存檔接著跑）沒有合進 main；決策 948 寫了做法，要用時照 `TimetableCheckup.play` 加一個每分鐘的 closure 即可。

## UNVERIFIED

- 實機、Xcode、iOS 模擬器都沒有跑（雲端 Linux）；這個改動只在 GameCore 的調度規則與測試。
- 新局規則的整天時刻表檢查與完整測試留給 CI（full-ci 與手動 ci.yml）。
