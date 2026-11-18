# DEADLOCK-SWEEP（2026-11-18）

## 進度

- 做到哪：佔用表換時刻重算的 bug 修完（決策 877）、各世界清查做完、開 PR；清查找到的三種問題與三項工具**沒做**，這個 session 壓縮兩次停手。
- 已驗證：30 個世界各兩天的雜湊與死結、久停、沒發（決策 877 §3、§4 的表）；`swift build --build-tests -Xswiftc -warnings-as-errors`；新的回歸測試照修前行為是紅的。
- 下一步的第一個指令：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=sanying DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_SAVE=/tmp/sanying-simple.json DEPOT_RETURN_SAVE_AT=0 DEPOT_RETURN_UNTIL=1 swift test --skip-build --filter DepotReturnReportTests/testTheSanyingLine`（存出三鶯線新局規則的存檔），再照「留下的」第 1 項的 `DEADLOCK_SWEEP_WATCH`。

## 派工

- 派工：協調者，從 TICK-REAL（決策 878）分出來的「各世界死結清查」。雲端 Linux，分支 `claude/project-thread-xmlajh`，決策 877。
- 存檔版本不動（110）、golden schema 不動；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。
- 這個 session 壓縮兩次，照規則停手；下面「留下的」都沒有人在做。

## 做了什麼

- **修了一個 bug**（決策 877）：佔用表的快取只看列車，但回庫空車的 claim「不綁到點的車」（決策 836、850）要看時刻。所有列車都停著時，到點的車會被舊的表綁到這次 `advance` 結束
  （一次一分鐘晚到下一分鐘、十倍速晚十分鐘並靠死結排解才開），整批和逐分走出不同的世界。改成讀過時刻的表在時刻變了之後只重跑 `settleClaims`。
  GameCore 只改 `RouteReservation.swift`（`keptHolders`、`TrackHolders.readsTheTime`、`HolderAudit` 的計數）與 `ServiceDirections.swift`（`DirectionMemo.holders` 多記 `at`）。
- **真實世界只有香港東涌綫變了**：第二天 00:51:42 一列到點的回庫空車早幾秒開，東涌綫單買與香港新局（南港島綫＋東涌綫）兩天後的雜湊不同，時刻表體檢的數字和上限相同。
  其餘量過的世界修前修後、一般速度與十倍速的雜湊全部相同（決策 877 §3）。
- **清查**：單線與示範世界、香港與羅瓦涅米全買、台灣與香港的共站線組、機捷三個世界，各走兩天。**畫面上寫「死結」的只在桃園機場捷運出現**，其餘三種規則都是 0（決策 877 §4）。
- **找到的都沒有在這張單修**，已評分：私有庫 `docs/priorities/DEADLOCK-SWEEP.md`（末班車進不了終點 2.85、機捷航廈站互等 2.45、回庫空車的 claim 太長 2.30，另有三項工具與檢查）。
- 新測試：`EmptyRunClaimDueServiceTests.testADueServiceLeavesWhenDueWithEveryTrainStanding`（照修前的行為是紅的）；新工具 `DeadlockSweepReportTests`。
- 和 TICK-REAL（#2478，決策 878）動到同一段，這個分支已經把它併進來：`keptHolders` 改了表就加 `memo.holderChanges += 1`，它的 `DirectionMemo.HolderStore` 的 tuple 也有 `at:`。

## 清查工具怎麼用

存檔怎麼來：單線、示範世界、香港幾條線一起買、機捷三個世界用 `DepotReturnReportTests/<那個世界的測試>` 加 `DEPOT_RETURN_REPORT=1 DEPOT_RETURN_ONLY=<名字> DEPOT_RETURN_SAVE=<檔> DEPOT_RETURN_SAVE_AT=0 DEPOT_RETURN_UNTIL=1`
（新局規則加 `DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1`，管制關只加 `DEPOT_RETURN_SIMPLE=1`，擬實都不加；機捷舊線、改建線與安坑後加機廠的世界買線後才開始，`DEPOT_RETURN_UNTIL` 要給大、存檔寫出來就停）；
香港、羅瓦涅米、台灣全買用 `BoughtWorldSaveTests`（`BOUGHT_WORLDS=<目錄>`）。台灣的共站線組（六家線＋內灣線、淡海兩線）這次是用沒有提交的暫時測試買的，
要再量就照 `TimetableCheckupAllBoughtTests` 的 `sharingGroups`、`buyTogether` 寫。存檔只要是 `SavedGame` 的 JSON 就行，玩家回報的存檔也可以。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
DEADLOCK_SWEEP=/path/world.json swift test --skip-build --filter DeadlockSweepReportTests 2>&1 | grep DEADLOCK_SWEEP
```

| 環境變數 | 作用 |
| --- | --- |
| `DEADLOCK_SWEEP_TICKS` | 走幾次 `advance`（預設 2880，一般速度兩天） |
| `DEADLOCK_SWEEP_SPEED` | `normal`（預設）或 `fast`（十倍速，一次十分鐘；兩天是 288）、`x60`（一次 6 秒） |
| `DEADLOCK_SWEEP_BATCH` | 一次 `advance` 幾 tick（量整批和逐分是否相同） |
| `DEADLOCK_SWEEP_STANDING` | 有班次的車停多久算久停，分鐘（預設 20） |
| `DEADLOCK_SWEEP_EACH=1` | 每小時印一次世界雜湊（找兩個建置從哪一小時開始不同） |
| `DEADLOCK_SWEEP_AUDIT=1` | 印佔用表換時刻重算幾次、幾次改變了 claim 綁誰 |
| `DEADLOCK_SWEEP_STALE=1` | 照決策 877 之前的行為走（同一個建置量修前修後） |
| `DEADLOCK_SWEEP_WATCH=<起>-<迄>` | 這段時間（時鐘秒數）每次都印每列車在哪、等誰、幾點該開；`DEADLOCK_SWEEP_WATCH_LINE` 只印路線名含這段字的 |

最後一行 `deadlocked: most N, in … looks, … episodes; stranded …; stood …; last <雜湊>` 是摘要；雜湊把遊戲速度當成一般速度算，所以不同速度走出一樣的世界時雜湊相同。
機捷一個世界兩天約十幾分鐘，香港全買約十分鐘，台灣 15 線全買一天 40 分鐘以上（併了決策 878 之後）。

## 留下的

1. **三鶯線末班車每晚停在終點前一站到清晨**（新局規則）。重現：`sanying-simple` 的存檔，`DEADLOCK_SWEEP_WATCH=87780-88140`。第二天 00:26 起，往頂埔的車停在媽祖田、往鶯桃福德的車停在永吉公園，
   到 06:01 才動；兩個終點各有三列收班的車停著，機廠只收 4 列。淡海兩線是同一種，只是 20–28 分鐘後有車讓開（`danhai-simple`，`DEADLOCK_SWEEP_WATCH=88620-88680`；藍海線 23:58–00:54）。
2. **桃園機場捷運在機場第一、第二航廈站的互等**（`main` 既有）。擬實：新線兩天 42 次、改建線 39、舊線 31，每次 1–7 分鐘、最多 5 列。重現：`tymc-realistic` 的存檔，
   `DEADLOCK_SWEEP_WATCH=58140-58320`（第一天 16:10，列車 20 與 23）。新局規則：新線沒有死結但久停 8 次，改建線 08:07、17:53 各一分鐘，舊線 17:19 七列四分鐘。
   決策 681 試過 20 種讓路寫法都不過；動手前讀 depot-work skill §5，機捷三個世界 × 兩種規則都要量。
3. **回庫空車的 claim 讓到點的車晚開 20 多分鐘**。安坑每晚 23:38–23:58（雙城往玫瑰中國城的車，等十四張開回安坑機廠的空車走完整條線；`ankeng-simple`，`DEADLOCK_SWEEP_WATCH=85020-86400`）；
   淡海綠山線 20:05–20:27（崁頂往淡海新市鎮的車，`danhai-simple`，`DEADLOCK_SWEEP_WATCH=72300-72420`）。depot-work skill §5「進庫的路很長時不要整條訂下來」還沒有人試；
   試的時候機捷三個世界 × 兩種規則都要量（決策 850 §4：放得太寬機捷整天不發車）。
4. 台灣 15 線全買沒有走完兩天：新局規則到第一天 09:20、擬實到 16:50，看到的死結都是機捷的列車。修前修後的雜湊也沒有比。
5. 沒有細看的久停：三鶯線每天 06:32–06:56 一列車晚 24 分鐘開往永吉公園；淡海兩線一起買時白天三次 20–22 分鐘（08:08、08:47、10:50）；機捷新線新局規則 18:14–18:42 直達車等普通車。
6. 還沒查的同類 bug：`advance` 共用的備忘裡，其他讀了時刻卻只用列車當鍵的答案（評分檔的 MEMO-TIME-AUDIT）。用 `DEADLOCK_SWEEP_SPEED=x60` 對 `normal` 比雜湊，不同就是有。

## UNVERIFIED

- iOS、實機沒有看（沒有改 App；只在 Linux 上跑 GameCore）。
- 整天版時刻表體檢只跑了 `hk TCL simple` 一格，其餘交夜間 CI。
- 久停的成因只看了上面寫的那幾個時段的逐分鐘輸出，沒有逐一確認每一次。
