# ECONOMY-FULLSCREEN：經濟明細蓋滿整個畫面（決策 717）

- 派工：定期貸款畫面那一組的 session 派出（作者 Mac 的本機 session，2026-11-13；作者：「還是乾脆整個經濟明細都全螢幕」）。登記在 #2118。
- 分支 `claude/economy-fullscreen-233d83`，從本機的 `claude/term-loan-ui`（`d55d4db75`）開，疊在 TERM-LOAN-UI 上。決策 717；存檔版本、golden schema、`Sources/GameCore/`、`SaveFixtures/`、`ReplayFixtures/`、`GoldenScenarios/` 都沒動。
- **合併順序**：TERM-LOAN-UI 先合；它合了之後這個分支併 `origin/main`，PR 的 base 改成 `main`。兩邊都改 `RailwayGameApp/Views/EconomyPanel.swift` 與 `WebsiteScreenshotTests.testTermLoans`：這個分支沒有改 `termLoanSection`、`TermLoanScreen`、`TermLoanRow` 的內容，衝突時那三個照 TERM-LOAN-UI 的；`testTermLoans` 開頭「打開面板、找到合約與借入」與結尾「回到面板找資產負債表」兩段照這個分支的（先選頁）。

## 做了什麼

- `Sources/GamePresentation/EconomyLayout.swift`：四頁（總覽、借款、票價、報表）各有哪些段、前後欄、什麼時候兩欄、打開在哪一頁。測試 `Tests/GamePresentationTests/EconomyLayoutTests.swift`。
- `RailwayGameApp/Views/EconomyPanel.swift`：照它排；導覽列中間的分段選擇器換頁（`economy.pages`）；兩欄的清單是 `economy.leading`、`economy.trailing`（一欄時只有 `economy.leading`）；「完成」是 `economy.done`。「更多報表與設定」（`economy.reports`）拿掉。車隊總覽與月報改成從這個畫面上方開 sheet。
- `RailwayGameApp/Views/ContentView.swift`：`.economy` 不在 `isBesideMap` 裡，改由 `fullScreenCover(item: coveringPanel)` 開；`GameScreenState.economyFocus`（打開在哪一頁，關掉時清掉）。
- `RailwayGameApp/Views/MapAlertBubbles.swift`：破產泡泡開在「借款」頁。
- UI 測試：`FinanceCompositionUITests` 與 `WebsiteScreenshotTests` 裡用到經濟明細的幾支，改成先選頁（`XCUIApplication.showEconomyPage(_:)`、`economyList(trailing:)`、`economyDragColumn(_:)`，在 `FinanceCompositionUITests.swift`）。

## 還留下什麼

見決策 717 第 7 節：定期貸款嵌成借款頁的後欄、iPad 單欄限寬、說明頁的字。另外：

- 這台 Mac 沒有 XcodeGen，所以沒有在 `RailwayGameApp/` 加新檔；`EconomyPanel.swift` 現在同時有經濟明細與定期貸款兩個畫面，之後可以拆檔再重新產生專案。

## 驗證

見 PR 說明的「驗證」一節（本機跑過的與沒跑的分開列）。
