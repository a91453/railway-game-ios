# TOURISM-OFFICIAL-1

派工單 TOURISM-OFFICIAL-1（session_01YGNNumFoPi4DvrdpL8A11f，`claude/tourism-official-1`，2026-11-13；遊戲規劃第 64 任派，#2118；任務單 `docs/research/DATA_PRIORITY_2026-11-13.md` §6.3）。[決策 724](../decisions/724.md)。不動 GameCore、存檔版本、golden、`SaveFixtures/`、`ReplayFixtures/`、星等與觀光客人數。

## 做完的

- `tools/tourism-spots/build_official_visitors.py`：讀交通部觀光署 data.gov.tw 8116 的 CSV（不提交），照人工對照表寫 `RailwayGameApp/Resources/RealWorld/taiwan_sight_visitors.json`（2024 年，每個對上的景點的年人次與 12 個月）。資料不對就失敗。
- `tools/tourism-spots/official_names.json`：人工逐筆校對，對上 104 個、看過留空 30 個（寫原因）、相加 0 個。
- 景點清單每張卡片多一行「一年約 N 萬人次（2024，交通部觀光署）」；沒有對上的不顯示。
- `DataSourceCredits` 的「人口與旅客」加 `sightVisitors`。
- Linux 測試 `SightVisitorsTests`；`RealRailwaysTests.testEverySourceIsCredited` 的清單加一筆。

## 還留下的

1. TOURISM-OFFICIAL-2（同類型內校正星等）：另一張單，讀同一份對照表與資料檔（決策 724 第 6 節）。
2. 明年 8116 更新到 2025 年後重跑工具；網站上 2025 年新增的據點名稱可能讓士林夜市、大稻埕等對得上。
3. UNVERIFIED：iOS 畫面只靠 CI 的建置與截圖；實機沒看。
