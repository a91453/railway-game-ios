# DT-DEADLOCK（2026-11-13）

- 派工：遊戲規劃第 65 任（NEXT_PRIORITIES §29.4 第 2 項「複線互等的死結」）。雲端 thread session。分支 `claude/project-thread-6j98ei`。
- 決策：沿用 571（加「續二」）。存檔版本、golden schema、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 不動。

## 查到的

110.1 回報的整天互卡已在 111.1 前後修掉（決策 571 #1768、571 續 #1775、572 #1778）。還沒做的只有 571「續」下一步第一點：每趟進站閃一次不到 1 分鐘的「互相卡住」。

## 做了什麼

`takingDeparture` 在簡單規則下，預設路線被「停在要去那站月台、互等的班」或「備用車」擋住時，當下逆線整段進空月台（`takingFreeBerthPastStandingTrain`）。測試見決策 571「續二」。

## 還留下什麼

- 玩家 110.1 的存檔沒拿到，沒重播。
- 寫實規則（有閉塞區間）沒套這步。
- 實機 UNVERIFIED。
