# STATION-PILL-CLEAR：設站確認框讓開路線、施工卡精簡、路線詳情全螢幕（決策 744、745）

- 派工：遊戲規劃第 65 任，作者 2026-11-14 自己玩回報三件（附 iPhone 橫拿截圖）。分支 `claude/project-thread-vvcnch`。存檔版本、golden、GameCore 不動。
- 做了：見 `docs/decisions/744.md`、`745.md`。新截圖場景 `stationSite`（`WebsiteScreenshotTests.testStationSite`）。

## 還留下什麼

- 作者第三點「月台坡度」（老問題）這張單沒有做，交回遊戲規劃另派。
- 設站時右邊細節卡的整平說明與確認框的「坡度 9‰：整平 80 公尺」仍各寫一次（卡上的較長、有金額）；之後可只留一處。
- 路線詳情全螢幕時仍是一欄；經濟明細那樣的兩欄（左設定、右數字）要改很多 UI 測試，沒做。
- 實機沒看過；模擬器截圖見 PR。
