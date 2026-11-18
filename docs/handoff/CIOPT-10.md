# CIOPT-10（138 發版後的 CI 優化）

- 派工：新專案「鐵道遊戲主規劃 2」的協調者（2026-11-18），138 發版後例行六件之一；作者同天加一件：盤點過時、重複、該拿掉的 CI 測試。
- session：工作串「做 138 版發版後 CI 優化」（雲端 Linux），分支 `claude/project-thread-2u3fly`。
- 號碼：決策不取新號（寫成[決策 719 的後來](../decisions/719.md)）；存檔、golden、GameCore、fixture 都不動。
- 數字：[CI_MEASURE_2026-11-18](../research/CI_MEASURE_2026-11-18.md) §6（CIOPT-9 的快取合併後）與 §7（這一輪）。
- 併入 TEST-JUMP（NEXT_PRIORITIES 的 2.05，`handoff/SUN-TIMES.md`）：第 1 步「時間花在哪」做了（§7.4），(2) UI 測試寫成評分 LESSON-RESULT-JUMP，(3) campaign 從中途狀態開始不做（理由在 §7.4）。

## 做了

- `swift-shards.sh`：rest 最重的 10 個類別搬到 6 片 campaign，27 個類別權重照五個完整 tier 最慢的那次。用同樣五個 run 重算，完整 tier 最長一片 518–782 s → 388–454 s。完整 tier 仍是 19 個 job。
- `swift-shards-selftest.sh`：「rest 的重類別」例子換成還在 rest 的 `AirportLineWholeIslandTests`。
- `Map3DModelPackLockTests.hash`：不再每個頂點建陣列（雜湊逐位元相同）；另外 6 個類別的同一份抄本改叫它。本機這 7 個類別約少 100 s。
- 盤點結果（§7.5）：沒有測已刪功能的測試；230 支 skipped 全是要設環境變數才跑的報告或除錯工具，不花 CI 時間；重複的是雜湊抄本（已併）與 `LessonUITests` 三支各跑一次第一課（評分）。

## 合併後要看的

1. 下一次完整 `ci.yml`（夜間或手動）：每片測試秒數，最長一片 8 分以內，rest 兩片不再是最長的。`time_warnings` 若又點名沒有權重的類別就補。
2. `Map3DModelPackLockTests` 在 campaigns-4 的時間（夜間 147 s → 預估 35–45 s）。
3. `ios-compilation-cache.yml`：每個受影響的 PR 約省 2 分，一天多用約 1 小時 macOS；macOS 排隊若常超過 20 分，先停它的 push 觸發（§6）。

## 留下的（沒有人在做）

- PR 最長的路仍是 iOS build job（中位約 26 分）：建置 12.5 分裡 GamePresentation 的 -O 佔 6–9 分。要再省只剩拆模組（CIOPT-9 的 GP-SPLIT，1.25）。
- LESSON-RESULT-JUMP（1.25，`docs/priorities/CIOPT-10.md`）。
