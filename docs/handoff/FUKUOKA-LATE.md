# FUKUOKA-LATE：福岡地鐵晚點

- 派工：協調者（工作串「修福岡地鐵晚點」），2026-11-20，雲端 thread session，分支 `claude/project-thread-5m9x4x`。
- 決策 890（`docs/decisions/890.md`）。存檔版本、golden schema 不動；GameCore 改進站號誌（決策 849）套用的條件。

## 做了

- 空港線：進站號誌也套「不跑全線的班只在頭尾時段」的線（`ServiceLine.shortRunsOnlyAtDayEdges`），新局晚點 60 → 0、擬實 3 → 0，福岡機場尖峰空檔 10.4 → 7.0 分。`TimetableCheckupAllBoughtTests.budgets` 福岡兩列調低。
- 測試：`ShortRunsAtDayEdgesTests`（GameCore）。

## 還留下的

1. **FUKUOKA-NANAKUMA-FLEET**（評分在私有 `railway-assets-private-2` `docs/priorities/FUKUOKA-NANAKUMA-FLEET.md`）：七隈線尖峰要 22 組車（20 組時晚 127 班；22 組量過 0 班），端點 5 股放不下。要橋本機廠（OSM way 965734835）加上排班工具把博多多出的車回送進橋本；車數照遊戲 36 秒停站算（決策 890 §5 最後一列有試過的數字）。
2. 沒在手機上看過：福岡空港線尖峰的車距（下一版 TestFlight）。
