# SWITCH-THROW（含 PB-4）

- 派工：遊戲規劃（專案「鐵道遊戲主規劃」工作串「加上月台安全餘裕和道岔扳轉時間」），接 `PLATFORM-BOOK-PB3.md` 留下的 PB-4 與 SWITCH-THROW。
- session：雲端 thread session，分支 `claude/project-thread-2fwvdu`。
- 決策 756（`docs/decisions/756.md`，存檔 102）、757（`docs/decisions/757.md`，量過不做）。golden schema 不動。
- 做完：
  - 道岔扳轉：行車控制開時的「道岔扳轉要時間」選項（預設關，路線頁「交通控制」下面的開關）；道岔記住開向，從站出發時進路上有道岔要改向就晚 4 秒開動；扳轉中存檔讀不回的漏洞一併修了。
  - PB-4 月台安全餘裕：量了 25 個地圖 259 列車，只有新北投、小碧潭支線受影響（餘 2 m），評分 1.85，不做。
- 還留下：
  - 設計頁第 ② 步：道岔扳轉小動畫、扳轉聲、車卡「等道岔扳好」（`switchesThrownUntil(of:)` 已有）。
  - 半路延長進路經過要扳的道岔要不要等（先量）。
  - 用正式版本在 Mac 重跑量測報告第 2 節的機捷、文湖（4 秒開與關）。
  - PLATFORM-BOOK 設計頁 §3.8 的 Mac 量測（決策 755 留下的，沒動）。
- UNVERIFIED：模擬器、實機都沒看過路線頁的開關；大地圖量測沒用正式版本重跑。Linux 本機跑了 `swift build --build-tests -Xswiftc -warnings-as-errors`、`SwitchInterlockingTests`、`SavedGameTests`、`CommandEditTests`、`GoldenScenarioTests`、`ReplayFixtureTests`、`PlatformListTests`、`StrandedTrainTests`，其餘交 CI。
