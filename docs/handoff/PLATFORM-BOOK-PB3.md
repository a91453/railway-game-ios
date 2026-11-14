# PLATFORM-BOOK-PB3

- 派工：遊戲規劃（專案「鐵道遊戲主規劃」工作串「讓玩家自己排月台清單」），接 `PLATFORM-BOOK.md` 的下一步 1。
- session：雲端 thread session，分支 `claude/project-thread-5z9x3f`。
- 決策 755（`docs/decisions/755.md`）。存檔版本、golden schema 不動。
- 做完：路線編輯排備選月台清單（加入、往前／往後移、移除）；放不下、已拆掉的月台標出；清單月台數少於同時在站列車時提醒；死結例外停清單外時車卡寫「清單的月台都滿了，改停軌段 #N 的月台」；修 REVIEW-L21 P3-1、P3-2。
- 還留下：
  - PB-4（量過再定）：月台安全餘裕。
  - SWITCH-THROW：道岔扳轉時間（`PLATFORM-BOOK.md` 下一步 2）。
  - 設計頁 §3.8 的 Mac 量測。
  - 沒有 UI 測試；車卡那一句沒有死結場景的測試。
- UNVERIFIED：模擬器、實機都沒看過路線編輯的清單和車卡那一句；Linux 本機跑了 `swift build --build-tests` 與兩個 `PlatformListEditTests`、`PlatformListTests`，其餘交 CI。
