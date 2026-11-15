# HEALTH-132-FIX（2026-11-15）

- 派工：遊戲規劃（HEALTH-132 §6 第 1 項，`docs/handoff/REVIEW-L22.md` 留下的第 1 項）。雲端 Linux，分支 `claude/project-thread-d2797p`。
- 決策 784（`docs/decisions/784.md`）。存檔版本、golden schema：不動；golden、save、replay fixture 一個值都沒變。

## 結果

- 二分（124 個合併，`git bisect --first-parent`，debug 建置與 release 數字逐一相同）：機捷簡＋控沒發 5 → 7、文湖簡＋控 6 → 8
  **都來自 #2142（決策 718，單線輪流）**；機捷死結 13 → 0 也是它。
- 修法：讓給「只被行進中列車擋著」的班次，改成要它已經等滿 60 秒（`turnOwedToHeldAfter`）。複線渡線、端點咽喉的
  幾秒衝突不再讓；單線上真的被一直擋著的照舊輪得到。
- 量到：機捷簡＋控 4/333（門檻 ≤ 5）、死結 0、讓路 50 → 35；文湖簡＋控 6/532（回到 129）。其他格在決策 784 §4。

## 還留下什麼

1. 舊線不動擬實每晚坑口站的半夜死結（HEALTH-132 §6 第 2 項）：這裡沒看。
2. 60 秒沒有掃別的值。
3. 下一次健檢（HEALTH-133）用 release 建置重量整張 150 格，這裡只量了機捷與文湖的格。

## UNVERIFIED

- 全是 Linux 報告測試（debug 建置），沒有在 iPhone、iPad、模擬器上看列車實際怎麼跑。
- 150 格只量了機捷、文湖相關的格；其餘 19 條線交 CI 與下一次健檢。
