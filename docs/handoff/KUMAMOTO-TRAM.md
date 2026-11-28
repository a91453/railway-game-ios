# KUMAMOTO-TRAM：熊本市電 A、B 系統接進福岡地圖（交接）

## 進度

- 做到哪：做完，決策 1041（`docs/decisions/1041.md`）。A、B 一起賣、照官方 GTFS 時刻表跑，機廠用真的大江（22 股）與上熊本（9 股），車先用替身 `klrtCitadis`。
- 已驗證：兩天的機廠報告兩種規則 400 班全發（寫實晚點 9 班、死結每次 1 組 1 分鐘內解開；簡易＋號誌全 0）；`KumamotoTramTests`、一天體檢 `testKumamotoTram` 與改到的舊測試在 Linux 跑過；其餘交給 CI。
- 車：2026-11-28 換成工作室的 `kumamoto-tram-lowfloor`（`Map3DKumamotoTram`，決策 1041 續；Chien 同意新色 wine #943040）。
- 下一步：照 assets-2 `docs/priorities/KUMAMOTO-TRAM.md` 的順位挑下一張（bug 的 KUMAMOTO-TRAM-LATE 排第一）。

## 派工

- 派工：規劃 4 工作串「接入熊本市電和山頂纜車」，規則在 assets-2 `docs/handoff/STREET-TEMPLE-VIADUCT-TRAM-RULES.md` §5（#635）。
- 山頂纜車那一半是 #2837（決策 1040）。熊本市電的第一個工作串（session_01YGNNupQeXdRJTTLMvavPYm）壓縮 3 次後停手，第二個做完。

## 還留下的（分數在 assets-2 `docs/priorities/KUMAMOTO-TRAM.md`）

- 路上的車避開軌道（只在畫面層）。
- 3 節的 2400 形與單節舊車。
- 熊本站前照真的折返（現在延到田崎橋，決策 1041 §3）。
- 兩座機廠的俯視圖（`plot_depots.py`）。
