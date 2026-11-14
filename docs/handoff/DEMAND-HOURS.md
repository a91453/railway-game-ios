# DEMAND-HOURS（需求時段）

- 派工：遊戲規劃第 65 任，作者 2026-11-14 點頭開始整合實作清單。雲端 thread session，分支 `claude/project-thread-5m78gv`。
- 決策 730；**存檔版本 98**（`SaveFixtures/v98-demand-hours.json`）；golden、replay 不動。
- 做了（DH-1）：大量人潮事件有舉行時刻，活動帶來的人集中在開場前與散場後，一天總人數不變；車站面板那一行寫時刻與散場時間。
- DH-2 做了（決策 730 §7，分支 `claude/project-thread-rahx5r`）：站長提醒與消息卡寫活動時刻與散場時間，只動畫面。
- 還留下：節慶有出處的時刻；設計頁 §8.7 的開與關對照量測。細節在決策 730 §6。
- PATIENCE（#2176，存檔 97）先合併，這張照 main 重排成 98；v98 範本是 v96 那次 Mac 建置寫出的同一份世界，只改了檔名與 saveVersion，由測試的 `loaded == world` 核對。
- UNVERIFIED：模擬器與實機都沒看過車站面板那行字與每小時圖；遊戲裡實際有活動那天的等候與營收沒量過。
