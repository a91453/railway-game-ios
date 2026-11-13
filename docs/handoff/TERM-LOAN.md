# TERM-LOAN：定期貸款（決策 715）

- 派工：作者 2026-11-13 直接交辦（作者 Mac 的本機 session）。登記在 #2118。
- 分支 `claude/term-loans`。決策 715、存檔版本 93；golden schema 不動，既有 fixture 一個值都沒變。
- 來源：作者自己的桌面版鐵路模擬（私人，不在三個 repository 裡）。對照表在 `docs/decisions/715.md` 第 3 節。

## 做了什麼（第一個 PR）

GameCore 的規則、存檔與測試：`Sources/GameCore/Economy/TermLoans.swift`（合約、報價、額度、借、到期、提前還、讀檔檢查），接進 `CompanyAccounts`、`BalanceSheet`、每日結算；`GameError.invalidTermLoan` 與它的玩家文字；`SaveFixtures/v93-term-loans.json`；`Tests/GameCoreTests/TermLoanTests.swift`。

## 還留下什麼

1. **畫面（第二個 PR，還沒人做）**：經濟面板的定期貸款清單、金額與年期、報價與確認、提前還款，中英文；資產負債表多一列。細節在決策 715 第 5 節。這個做完之前玩家借不到。
2. 作者排的後續（各自一個 PR，還沒開始）：消費稅 → 年度資產評價與股票，都來自同一個來源。
3. 與 #2113（存檔版本 92）誰先合，後合的那個要併 main 並解 `SavedGame.currentVersion` 與版本說明那幾行的衝突（兩邊各加一段，版本取大的）。

## UNVERIFIED

- 只在 macOS 跑過相關的測試類別；Linux 的完整 tier、iOS 建置由 CI 驗證。
- 沒有在 App 裡看過（還沒有畫面）。
