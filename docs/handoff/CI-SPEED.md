# CI-SPEED 交接（2026-11-14）

工作串「縮短 CI 和 full lane 時間」，分支 `claude/project-thread-giil3t`，決策 754。

## 做完的

1. **131（`4cff950`）full lane 紅的 10 個 iPhone UI 測試**（run 43599067177）：只改測試，App 沒壞。
   - 決策 745／746 讓路線頁與車站面板蓋滿畫面後，清單左緣就是螢幕左緣，測試在左緣 8 點（貨場 2%）拖曳會被邊緣手勢吃掉。共用的拖曳改成離螢幕左右緣至少 44 點（`clearOfScreenEdges`）。
   - 第一課三支：新路線頁的導覽列是路線名，不是 "Lines"，改按目前導覽列的 Done。
   - 車站時刻表那支：改找含 `station.operations` 的清單，不再找地圖右側的清單。
   - LoadChart：列在導覽列底下被點到導覽列，改拖到 `linesListTop` 下面。
   - 驗證：CI 的 iPhone 17 Pro（iOS 26.4.1）only_testing run 43612325536（10 支全綠）、PR gate run 43612706912。
2. **不穩的測試**
   - `TutorialUITests.startFirstLesson`：開始畫面的「入門」點了沒反應（#2199 iPad 第一次紅）時再點一次，和 `TutorialJourneyUITests` 同一做法。
   - `TrainTripLogTests.testCreditingATripDoesNotWalkTheLog`：原本和只有幾筆的紀錄比，二分搜尋的步數就讓長的慢 5–15 倍（門檻 5 倍，CI 三次紅兩次）。改成 2,000 筆對 20,000 筆，各量三次取最快；本機 Linux 比值 1.1 倍，門檻 4 倍，一筆一筆走會是 10 倍。
3. **full lane 不再排成一串**（決策 754）：map 併回 build job，iPad 在 second、lessons 跑完就開始。預估 124 → 約 90 分；合併後第一次 full lane 要量實際時間，寫回決策 754。

## 留下的

- **`WebsiteScreenshotTests` 有 7 處用 `frame.minX > app.frame.midX` 找車站或路線面板**，決策 745／746 後大概會找不到，`website-screenshots.yml` 的截圖可能壞。下一張單：照這次的改法（找含識別碼的清單、拖曳離螢幕邊 44 點）修，用 website-screenshots 跑一次驗。
- 作者 Mac 的 iOS 27.2 模擬器上，建設模式的分段鈕在 XCTest 裡點不到（還原成舊測試也一樣），用到它的 UI 測試只能在 CI（iOS 26.4）驗。
- Mac 上的 worktree `~/Developer/wt-giil3t` 與 `~/Library/Developer/RailwayGameDerived-giil3t`：這個 PR 合併後可刪。
- 沒做、另案評估：Xcode 26 編譯快取（`COMPILATION_CACHE_ENABLE_CACHING`）＋ actions/cache，可能把每個 job 的 11–15 分建置縮短；要先在 Mac 上量。
- 偶發的「Timed out while launching application via Xcode」（#2179 的 run 43563652219）是模擬器那邊的，沒有改。
