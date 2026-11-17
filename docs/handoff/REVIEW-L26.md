# REVIEW-L26 ＋ HEALTH-136（2026-11-17）

## 進度

- 做完：審查與健檢報告都寫好，分數寫進 NEXT_PRIORITIES §29.20；等這張 PR 的 CI。
- 已驗證：release 建置（`19f3cc5`，1,820 s、0 警告）、健檢六組 × 28 個世界 0 失敗、有乘客四格、長途客運 `tra`、fixture（數字在 HEALTH-136 §2–§3）。
- 下一步：CI 綠了在 #2118 留「可合併、head <SHA>」並轉 ready。

## 做了什麼

- 派工：遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed（136 發版後例行）。本串 session_01JMHz9cBHLCf2Qau1dU117D，雲端 Linux，分支 `claude/review-l26`。壓縮 1 次。
- 存檔版本、決策號、golden schema：都沒用。
- 報告：[`docs/research/REVIEW_L26_2026-11-17.md`](../research/REVIEW_L26_2026-11-17.md)、[`docs/research/HEALTH_136_2026-11-17.md`](../research/HEALTH_136_2026-11-17.md)。
- 程式改動只有一處：`DepotReturnReportTests` 加羅瓦涅米兩條線同一局的世界 `rovaniemi-both`（只在 `DEPOT_RETURN_REPORT=1` 時跑）。
- 規劃另外要的：`docs/research/PLAYER_FEEDBACK.md` 的 136 改成已發（`19f3cc5`、run 43998784830，範圍含 #2326–#2328）。

## 結果

- 審查 `89ed04b..19f3cc5`（#2310、#2315–#2328，8 點）：P1 0、P2 2、P3 4 新＋5 沿用。
- HEALTH-136：CONCERNS（舊項目、full lane 一支、香港不在表上），模擬沒有新退步；決策 808 把舊線不動擬實的半夜死結 836 分降到 42 分。
- HEALTH-135 留下的三格補齊：羅瓦涅米兩條同一局 0/14；有乘客四格與長途客運見 HEALTH-136 §3.3、§3.4。

## 還留下什麼（分數在 NEXT_PRIORITIES §29.20）

1. **P2-1 full lane 建置組的橫拿教學**（2.35）：已派 FULLLANE-136，修好以前不發版。
2. **P2-2 HEALTH-HK：健檢加香港的世界**（2.65）：DEADLOCK-HK（816）合併後用它的重現加。
3. **機捷擬實（有乘客）死結 5 → 6 列**（2.10，HEALTH-136 §3.3）：照 §29.17 的規則只記數字與重現，規劃轉給當時唯一修死結的 session。
4. **P3-3 聖誕塗裝第一次出現時在畫面執行緒上做模型**（1.70）：12/1 前看一次實機。
5. **P3-1**（1.25，同上）、**P3-2**（1.25，和 L25 P3-2 一起交效能串）、**P3-4**（1.15，下次改 `MapBuildConfirm.swift` 時順手）。
6. 全臺 `taiwan` 的長途客運這次沒跑。

## UNVERIFIED

- iOS 畫面、Metal、實機都沒看；P2-1 的原因是讀程式的推定。
- 決策 805 的放行在真實路線上沒有被量到（沒有圈）。

下一輪 L27 從 #2329 起（加上編號較小、在 136 之後才合併的）。
