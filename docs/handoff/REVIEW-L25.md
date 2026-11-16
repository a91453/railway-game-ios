# REVIEW-L25 ＋ HEALTH-135（2026-11-17）

## 進度

- 做完：審查與健檢報告都寫好；等這張 PR 的 CI。
- 已驗證：release 建置（`89ed04b`，1,914 s、0 警告）、fixture 65＋12 個 0 失敗、健檢六組 × 27 個世界 0 失敗（數字在 HEALTH-135 §2）。
- 下一步：CI 綠了在 #2118 留「可合併、head <SHA>」並轉 ready。

## 做了什麼

- 派工：遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed（135 發版後例行）。本串 session_01JMHz9Z7bzL2Fw5y2b6StX3，雲端 Linux，Opus 5.5 高，分支 `claude/review-l25`。
- 存檔版本、決策號、golden schema：都沒用。
- 報告：[`docs/research/REVIEW_L25_2026-11-17.md`](../research/REVIEW_L25_2026-11-17.md)、[`docs/research/HEALTH_135_2026-11-17.md`](../research/HEALTH_135_2026-11-17.md)。
- 程式改動只有一處：`DepotReturnReportTests` 加羅瓦涅米兩條線的世界（`rovaniemi-kja`、`rovaniemi-mul`，只在 `DEPOT_RETURN_REPORT=1` 時跑）。

## 結果

- 審查 `36b5cb5..89ed04b`（#2292–#2314，17 點）：P1 0、P2 2、P3 3 新＋3 沿用。
- HEALTH-135：CONCERNS（舊項目與 full lane），模擬沒有新退步；134 的 318/333 回到 0。

## 還留下什麼（請規劃評分後派）

1. **P2-1 橫拿＋最大字級時 ✓ 在畫面外**（約 2.5，full lane second 兩支紅，擋 136）。推定與修法方向在報告 P2-1，已在 #2118 告知。
2. **P2-2 建置組速度選單觸控停在 600 倍**（約 1.8）：看下一次 full lane。
3. **P3-1 新局沒手動存過，聖誕塗裝重開就不見**（約 1.7），12/1 前；P3-4 冬季第 5 週 00:00 路線（沿用）一起。
4. **P3-2 管制關著時主執行緒每 tick 多一次全車 `heldUp`**（約 1.3）：交效能串量。
5. 羅瓦涅米兩條同一局、兩天：在含 #2316 的 main 補量；有乘客的四格、長途客運：下一次健檢先補。

## UNVERIFIED

- iOS 畫面、Metal、實機都沒看；P2-1 的原因是讀程式的推定。
- 決策 805 的放行在真實路線上沒有被量到（沒有圈）。

下一輪 L26 從 #2315 起（另加 #2310）
