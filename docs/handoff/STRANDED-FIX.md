# STRANDED-FIX

- 派工：遊戲規劃第 65 任；作者 2026-11-14 同意做 SWITCH-THROW-MEASURE 報告 §7.4 的 1（預防）與 2（偵測），3（自動救回）延後。
- session：雲端 thread session，分支 `claude/project-thread-9qcphf`。
- 決策 735（`docs/decisions/735.md`）；存檔版本、golden schema 不動。
- 做了：`leaving()` 的預設挑月台時，最近的月台停進去就去不了下下站、別的月台去得了，就改去那些月台裡最近的；新的 `GameWorld.strandedTrains()`（半小時以上沒有出發要求的車）接進 `DepotReturnReportTests` 的摘要（`most stranded`）、`DEPOT_RETURN_EPISODES`、`DEPOT_RETURN_STRICT`。地圖沿用決策 497 P2-7 的「卡住了」泡泡，沒有新畫面。
- 還留下：第 3 項自動救回；下一次 HEALTH 看 `most stranded`；實景示範與其他 13 張地圖用正式版本重量、`TICK_SCALE` 效能（都要 Mac）。
- UNVERIFIED：本機沒有 Swift，建置與測試只在 CI；沒有在模擬器或實機上看過。
