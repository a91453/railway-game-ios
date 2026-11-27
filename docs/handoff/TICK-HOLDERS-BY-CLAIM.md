# TICK-HOLDERS-BY-CLAIM（2026-11-27）

## 進度

- 做到哪：做完，決策 1036。「誰占哪一段」不同的車不管多少都從上一份改，占的與訂路都沒變的車留著不動；重排訂路時同一列前車只問一次、找路共用備忘；開閉塞不算行車許可。
- 已驗證（雲端 Linux 4 核、Swift 6.4）：六個全買世界在 main `75f69eed` 鋪，新舊 build 逐小時雜湊相同；香港兩個世界 `SAVED_WORLD_AUDIT=1` 600 tick 稽核通過；一次一個成對量：香港全買・簡單 157.7 → 152.3 ms／tick（−3.5 %，尖峰 07–10 時 −6～−9 %，p95 −8 %），台灣全買・簡單沒有差別（642 → 654 ms，雜訊內）；數字在決策 1036 的表。**這張單不夠讓 60 倍跑滿**：台灣尖峰一個 tick 仍約 1.8 s。
- 下一步的第一個指令：台灣全買・寫實最慢，先量它的發車問路（決策 980 第 3 步）：`SAVED_WORLD=/tmp/worlds/taiwan-all-realistic.json SAVED_WORLD_TICKS=600 SAVED_WORLD_HOURS=1 swift test --skip-build --filter SavedWorldTickReportTests`，再照下面「量到的」挑一張。

## 派工

- 協調者派工：評分檔（私有庫 `a91453/railway-assets-private-2` `docs/priorities/TICK-ROUTING.md`）第 3 列，2.40；起因是玩家回報大地圖卡頓（`docs/handoff/BIG-MAP-SLOW.md`）。
- 雲端工作串「讓列車多時不再卡頓」，分支 `claude/project-thread-6yuuvf`，決策 1036（#2118 已登記）。存檔版本、golden schema、`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 都不動。

## 量到的（main `75f69eed`，`perf record -g`，給下一張單用）

量法：`perf`（`apt-get install linux-tools-generic`，執行檔在 `/usr/lib/linux-tools/<版本>/perf`）對 `GameCoreTests-test-runner` 跑 `SavedWorldTickReportTests`，`SAVED_WORLD_SKIP` 跳到尖峰、`SAVED_WORLD_HOLD` 給取樣時間；符號用 `/opt/swift/usr/bin/swift-demangle` 解。百分比是含子呼叫的。

| | 香港全買・簡單 07–09 時 | 台灣全買・簡單 | 台灣全買・寫實（開閉塞） |
| --- | --: | --: | --: |
| 一個 tick（同時跑時量） | 約 350 ms | 約 1.8 s | 08 時約 3.5 s |
| `trackHolders`（這張單之前） | 39 % | 24 % | 12 %（幾乎全是整張重建，一半是用不到的行車許可） |
| 　其中重排訂路 `settleClaims` | 19 %（`leavingCover` 6.4、`holding` 5.3） | 12 % | 不排（開閉塞） |
| `runServices`／發車問路 | — | 27.6 % | 24 %（`reservingDeparture` 12.5） |
| 待避計畫 `trafficPlan` | — | 20.5 % | 18.5 % |
| 延長許可 `extendAuthorities` | — | 16 % | — |
| 派車 `dispatchTrains` | — | 11.6 % | — |
| 掃列車比值 `Train ==` | 2 % | 4.3 % | — |

這張單之後香港重排訂路 13 %（`leavingCover` 0.9 %），剩下的訂路 10.6 % 是每列在動的車本來就要算的（行車許可＋行進範圍，延長許可也要）。

## 還留下什麼（依值得的程度）

1. **台灣寫實的發車問路**：決策 980 第 3 步（開閉塞時最後那一段只避開站著的車的找路，同一種「仍被擋就不重找」紀錄），做法在 `docs/handoff/TICK-HELD-ASK-ONCE.md` 做法第 4 點。
2. **TICK-PLAN-KEEP**（待避計畫，兩個台灣世界都約 20 %）。
3. **重排訂路的 `holding` 跨步驟記住**（香港約 5 %）：每列車「它的訂路蓋到誰」只在它的訂路或別人占的變了時才變；要記的是每一列車的訂路對每一份 holders 的答案，並在 `replace` 時只更新被換掉的那一列。比這張單複雜（`replace` 的每張表都要一起對），和 TICK-FREES-FROM-HOLDERS 一起想。
4. **TICK-TRAIN-INDEX**：每一步掃所有列車比值（`Train ==`）。
5. 試過、不做的：把訂路當成格子集合比（不是精確到公尺），會讓「沒變」的車多很多，但訂路的兩端決定誰被擋，改了就是改規則。

## 怎麼證明結果不變

照 `docs/handoff/TICK-REAL.md`「怎麼量」：`BoughtWorldSaveTests` 鋪六個世界，新舊 build 各跑 `SavedWorldTickReportTests`（`SAVED_WORLD_EACH=1`），逐小時雜湊與總和相同；再開 `SAVED_WORLD_AUDIT=1` 跑一次（慢幾倍），稽核那一行的 `trains changed left in them as they were` 是這張單留著不動的車數。
