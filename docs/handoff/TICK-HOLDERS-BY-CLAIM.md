# TICK-HOLDERS-BY-CLAIM（2026-11-27）

## 進度

- 做到哪：做完，決策 1036。「誰占哪一段」不同的車不管多少都從上一份改，占的與訂路都沒變的車留著不動；重排訂路時同一列前車只問一次、找路共用備忘；開閉塞不算行車許可。
- 已驗證（雲端 Linux 4 核、Swift 6.4）：六個全買世界在 main `75f69eed` 鋪，新舊 build 逐小時雜湊相同；香港兩個世界 `SAVED_WORLD_AUDIT=1` 600 tick 稽核通過；一次一個成對量：香港全買・簡單 157.7 → 152.3 ms／tick（−3.5 %，尖峰 07–10 時 −6～−9 %，p95 −8 %），台灣全買・簡單沒有差別（642 → 654 ms，雜訊內）；數字在決策 1036 的表。**這張單不夠讓 60 倍跑滿**：台灣尖峰一個 tick 仍約 1.8 s。
- 下一步的第一個指令（決策 1038、1039 之後，見「接手」一節）：台灣全買・寫實仍最慢，先量它：`SAVED_WORLD=/tmp/worlds/taiwan-all-realistic.json SAVED_WORLD_TICKS=600 SAVED_WORLD_HOURS=1 swift test --skip-build --filter SavedWorldTickReportTests`，再照下面「量到的」挑一張。

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

## 接手：台灣寫實的發車問路與 TICK-PLAN-KEEP（2026-11-27，決策 1038、1039）

- 誰：雲端工作串「讓台灣大地圖跑滿 60 倍」，分支 `claude/project-thread-vwo545`（#2118 已登記）。下面原本的第 1、2 點做完了。
- 做了什麼：決策 1038（找軌道一猜再猜、`followsRealTimetable` 不複製路線、跟車截斷只算一次停哪、反向保護少掃列車、路線偏好每段一次算完）；決策 1039（待避計畫的會車與待避鑰匙沒變就沿用，有稽核）。
- 已驗證：見決策 1039 的表（雜湊、稽核、一次一個的時間）。
- 量到、還沒做的（台灣全買・寫實 08 時，這張 PR 的 build）：延長許可 `extendAuthorities` 21 %（其中 holders 6、`followingCover` 4.6、`authority` 4.2）、發車問路的 `reserving` 17 %（跟車截斷 9）、派車 12 %（機廠入庫候選的 `workedOutTrainsInTheWay` 9.4）、`moveTrains` 13 %、待避計畫剩 17.5 %（決策 366 的等間隔線待避 5.5、鑰匙變了時重算的待避 7）。
- 決策 980 第 3 步沒做：取樣看來開閉塞時「只避開站著的車」那次找路多半找得到路，貴的是找到之後的反向保護（`opposingParts`，已在決策 1038 減一半），「仍找不到」的紀錄省不到多少。

## 還留下什麼（依值得的程度）

1. ~~台灣寫實的發車問路~~（決策 1038，見上）。
2. ~~TICK-PLAN-KEEP~~（決策 1039，見上）。
3. **重排訂路的 `holding` 跨步驟記住**（香港約 5 %）：每列車「它的訂路蓋到誰」只在它的訂路或別人占的變了時才變；要記的是每一列車的訂路對每一份 holders 的答案，並在 `replace` 時只更新被換掉的那一列。比這張單複雜（`replace` 的每張表都要一起對），和 TICK-FREES-FROM-HOLDERS 一起想。
4. **TICK-TRAIN-INDEX**：每一步掃所有列車比值（`Train ==`）。
5. 試過、不做的：把訂路當成格子集合比（不是精確到公尺），會讓「沒變」的車多很多，但訂路的兩端決定誰被擋，改了就是改規則。

## 怎麼證明結果不變

照 `docs/handoff/TICK-REAL.md`「怎麼量」：`BoughtWorldSaveTests` 鋪六個世界，新舊 build 各跑 `SavedWorldTickReportTests`（`SAVED_WORLD_EACH=1`），逐小時雜湊與總和相同；再開 `SAVED_WORLD_AUDIT=1` 跑一次（慢幾倍），稽核那一行的 `trains changed left in them as they were` 是這張單留著不動的車數。
