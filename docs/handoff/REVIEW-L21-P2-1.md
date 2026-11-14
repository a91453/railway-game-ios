# REVIEW-L21 P2-1（2026-11-14）：回主畫面背景存檔失敗時舊局被丟掉

- 雲端 Linux，分支 `claude/project-thread-d5w78k`。存檔版本、決策號、golden schema 都沒用；GameCore 沒動。
- 修法：`returnToStartInBackground` 把離開的那一局記在 `leaving`（存檔結果放在 `LeavingWrite`，存檔佇列寫、主執行緒讀）。
  寫入期間開新局時，`begin` 先等存檔佇列跑完（`afterSaves`），再看結果：成功就照常開新局，`isReturningToStart` 當下就變回假，
  新局不會被「存檔中」蓋住、回主畫面也按得動；失敗就不開新局，把離開的那一局叫回來，狀態列寫原因並問「再試一次／不存檔離開／繼續玩」。
  寫入自己的回報晚到時什麼都不再做。原本「剛才離開的遊戲沒有存成功」那一句（`leftUnsaved`）已刪。
- 代價：存檔還沒寫完就點開新局，主執行緒會等剩下的寫入（最大存檔約 3–4 秒）。原本會封存自動存檔的開局路徑本來就要等同一個佇列，所以沒有比 #2201 之前更慢。
- 測試：`ReturnToStartInBackgroundTests` 加兩條（失敗時開新局→舊局回來並發問；成功時開新局→不被蓋、離開的那局有存下來）。

## 還留下什麼

- 沒有。實機（存檔中立刻開新局、手機空間滿）UNVERIFIED。
