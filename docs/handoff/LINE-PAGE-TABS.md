# LINE-PAGE-TABS：路線自己的頁分成分頁、兩欄（決策 779）

- 派工：主規劃（作者 2026-11-15 在 132 版 iPad 上回報「路線詳情…要滑太多 應該可以改成跟資料類似」）。登記在 #2118。
- 分支 `claude/project-thread-et46iu`。決策 779；存檔版本、golden schema、`Sources/GameCore/` 都沒動。

## 做了什麼

- `Sources/GamePresentation/LineDetailLayout.swift`：四頁（總覽、列車、停靠站、設定）各有哪些段、前後欄、什麼時候兩欄。測試 `Tests/GamePresentationTests/LineDetailLayoutTests.swift`。
- `RailwayGameApp/Views/LinesPanel.swift`：`lineDetailPage` 照它排；上方一列是上一條線（`line.previous`）、分頁（`line.pages`）、第幾條、下一條線（`line.next`）；兩欄的清單是 `line.detail`、`line.detail.trailing`（一欄時只有 `line.detail`）。`trainsSection` 拆出 `lineFeedbackSections`（營運狀況、改騎車開車），一張長表單時仍接在列車後面。
- UI 測試：用到路線頁內容的都先選頁（`XCUIApplication.showLinePage(_:_:trailing:)`、`linePageList(trailing:)`，在 `ToolbarSmokeTests.swift`）。

## 還留下什麼

- 沒在模擬器或實機看過；作者發版後自己看。若 iPhone 橫拿時上方那一列太擠，`ViewThatFits` 會退成只有箭頭。
- 車站詳情（決策 746）若也被說難滑，可比照拆分頁。
