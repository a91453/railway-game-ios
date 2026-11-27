# CIOPT-18：0.6.0 (153) 發版例行的 CI 優化

串「縮短 PR 等 CI 的時間」，分支 `claude/project-thread-7j312h`，2026-11-27。接 `docs/handoff/CIOPT-17.md`「還留下什麼」第 3–5、7 項，與私有庫 `docs/memory/ci-wait-where.md` 建議的兩張單（兩張都已經做了：決策 1019、決策 1012 §7）。

## 做了什麼

1. **合併規則不再叫人「main 動了就先併」。** `CLAUDE.md` 的 Merging 一段原本寫「合併前 `main` 動了就先併 `origin/main`，新 head 綠了才合」，和作者 2026-11-26 08:05 的規則（私有庫 `docs/handoff/PLAN-4-HANDOFF.md` §0 第 3 條：「只有真衝突的才併 main 重跑」）相反，同一檔後面的「Merge `main` into a pull request only when it conflicts」也和它打架。現在兩處一致：只有 GitHub 說衝突（或 `conflict-watch.yml` 留言）、或 PR 需要只在 `main` 上的東西時才併；`AGENTS.md` 那行跟著改。
   - 量到的（`git log origin/main --since=2026-11-26T16:00Z`，台灣 11-27 一整天）：61 張 PR 合進 `main`，PR 分支上併 `origin/main` 的合併有 38 次，其中 **30 次沒有衝突**（合併訊息沒有 `# Conflicts`）。#2817 在 12:22、12:53 各併一次，#2823 在 12:49 併一次，都沒衝突，每次 Swift CI 重跑（約 14–25 分）。
   - iOS 那邊沒那麼糟：「這個改動通過過嗎」（`Has this change passed before?`）會讓 App 沒變的重跑 30 秒就跳過（例：#2823 併 main 後的 46002897466，0.5 分）。所以多花的主要是 Swift CI 和等待。
   - 漏掉的組合錯誤（兩張各自綠、合在一起紅）由 `main` 的 push run 抓，照「紅了就修」開 PR 修。
2. **分片重排**（例行第 3 件）。nightly 45920779013（main `1ed26fd`）：build 14.6 分；rest-2 725 秒測試（job 13.9 分，最長）、rest-1 608、campaigns-3 359（最輕）、campaigns-9 10.9 分。rest-2 最重的兩個 `TrainPortraitTests`（40 s）、`Map3DCoachesTests`（36 s）搬到 campaigns-3（約 435 s），權重改成這次的時間（38→40、28→36）。沒有類別印「has no CLASS_WEIGHTS entry」（rest 最慢的類別 44.7 s，門檻 60）。`swift-shards-selftest.sh` 本機過。省的是 nightly 與 GameCore PR 完整 tier 的約 1 分鐘；PR 的 GamePresentation tier 照模組選，不受影響。
   - nightly 真正最晚結束的是 `Timetable checkup / taiwan-metro-realistic`（37.4 分），但 gate 不等它（決策 844），不影響 PR。
3. **Mac runner 第一天的量測**（CIOPT-17 第 3 項的預量；一週的正式量測仍照原計畫約 12-03 做）。`ios-build.yml` 的 PR run，2026-11-26 11:53Z 到 11-27 14:45Z 最近 100 個、成功的 94 個：
   - 跳過（App 沒變或只改說明）24 個，約 0.5 分。
   - 在 `chien-mac` 上（整個 run < 18 分）46 個，中位 8.3 分、平均 8.5 分。
   - 在 GitHub 的 Mac 上 24 個，中位 32.4 分、平均 31.7 分。例：#2823 的 45995203013，排隊 18 分（12:02→12:20，那時 Mac 忙），編譯 12 分，UI 冒煙 9 分，共 44 分。
   - 結論：Mac 有空時一張 PR 的 iOS 約 8 分，排到 hosted 時 30–45 分，差距主要是 hosted 的排隊和較慢的編譯。三分之二的 PR 排到了 Mac。

## 沒做的與原因

- **CIOPT-17 第 4 項 `website-screenshots.yml` 接 `pick-mac.yml`：不做。** 截圖 run 一次 40–340 分（`timeout-minutes`），放到 Mac 上會把唯一能讓 PR 8 分鐘跑完的 Mac 佔掉幾小時，PR 全部退回 hosted 的 30 分以上。截圖照舊用 hosted。
- **CIOPT-17 第 5 項 `Map3DFarViewTests.testTheFarthestViewOfTaipeiIsWithinBudget`（權重 375 s）：還沒做。** 它在 campaigns-8（9.7 分），不是 nightly 最長的；PR 的 Swift 那邊（約 14 分）也不是 PR 等最久的地方（iOS 才是）。等 Swift 那邊又變成瓶頸再處理（要改測試本身，例如縮小量的範圍）。
- **CIOPT-17 第 7 項**：已由決策 1016（#2756）做完。

## 等作者決定（不要自己改）

- **TestFlight 的 build 號會撞**：153 是在 Mac 上本機發的（`tools/release/testflight-local.sh`），GitHub 的 `testflight.yml` 算出來的下一號也是 153。如果之後又用 GitHub CI 發，要先決定 `BUILD_NUMBER_OFFSET`（例如 1），否則 App Store Connect 會拒收重複的號碼。只有作者能決定發版，這串沒有改。

## 下一步

- 約 2026-12-03：照第 3 段的方法量 Mac runner 一整週（`ios-build.yml` PR run 的時間分兩群，加上 hosted 的排隊時間），寫回決策 1014 的「下一步」。
- 下次發版後的 CI 例行：照第 2 段的做法看最新 nightly 的分片，把最重分片的類別搬到最輕的 campaign。
