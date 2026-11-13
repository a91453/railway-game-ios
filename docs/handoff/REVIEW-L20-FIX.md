# REVIEW-L20-FIX（2026-11-13）

- 派工：遊戲規劃第 64 任。session_01YGNNunGhyuC1Bbe73nFVND（雲端 Linux）。
- 來源：`docs/research/REVIEW_L20_2026-11-13.md` 的 P2。
- 存檔版本、決策號（新號）、golden schema、`SaveFixtures/`、`ReplayFixtures/`、`GoldenScenarios/`：都沒動。

## PR 1：P2-5 定期貸款 × 資金無限（分支 `claude/review-l20-fix`，GameCore）

- 決策 715 第 8 節。資金無限開著時兩種貸款都暫停：不能借、不能還（`GameError.loanNeedsLimitedFunds`），定期貸款不到期；關掉後的第一個午夜照常付。
- 檔案：`Sources/GameCore/Economy/TermLoans.swift`、`Operations.swift`、`World/GameError.swift`；`Sources/GamePresentation/DisplayText.swift`（錯誤的一句字，兩種語言）；`Tests/GameCoreTests/LoanUnlimitedFundsTests.swift`（新，5 個）、`UnlimitedFundsTests.swift`（一個測試改成先借再開）、`GoldenScenario.swift`（結果名多一個）。
- 給 TERM-LOAN-UI（#2133）：GameCore 已經擋住，畫面可以直接顯示這個錯誤；要不要在資金無限時把定期貸款整區收起來（決策 67 的貸款在 `EconomyPanel` 就是這樣）由 #2133 決定。#2133 在決策 715 加的是第 7 節，這裡加的是第 8 節，合併時兩節都留。

## 還留下什麼

- **給規劃：P2-4、P2-7 沒有做**（更新說明的字：128 的「站名牌會寫你那一站的名字」做不到；封閉軌道的按鈕還沒寫進下一版的 `WhatsNew.swift` 與 `.github/testflight-whats-new.md`）。P3-20 同類。
- **P2-2 沒有做**（要 4 GB 實機）。
- P3-1（自由模式的定期貸款回到經營才付）、P3-2、P3-3（手改存檔的 `borrowedDay`、`nextTermLoanID` 沒有界限）沒有做。

## UNVERIFIED

- PR 1：本機（Linux，Swift 6.4.0）跑了建置（warnings as errors）與貸款、存檔、golden、replay、財報相關的測試類別；完整 tier 由 CI 跑。iOS 建置由 CI 跑。
