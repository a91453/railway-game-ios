# PATIENCE（乘客等太久就離開）

- 派工：遊戲規劃第 65 任，作者 2026-11-14 點頭開始整合實作清單第 1 項。
- session：雲端 thread session「實作久候離開」，分支 `claude/project-thread-px96lw`。
- 決策 [731](../decisions/731.md)；存檔 97（`SaveFixtures/v97-passenger-patience.json`）；golden schema 77（`GoldenScenarios/passenger-patience.json`）。
- 做了：PAT-1。寫實規則的新遊戲裡，乘客等 40 分（長途 90 分）還沒上車就離開，記在原出發站的「等太久離開」；車站面板多一列；新遊戲「寫實」說明加一句。
- 還留下：
  - PAT-2：路線報表多一列（設計頁 §1.6）。
  - HEALTH 150 格開與關各量一次，看營收與載客掉多少，再調 `PassengerPatience` 的 40、90 分與 20 km（決策 731「平衡」）。
  - DEMAND-HOURS（決策 730、存檔 96）和這張誰後合併，誰照當時的 `main` 重排存檔版本與遷移註解。
- UNVERIFIED：模擬器與實機都沒看過車站面板的新一列；平衡沒量。
