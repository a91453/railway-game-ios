# TERM-LOAN-UI：定期貸款的畫面（決策 715 第 7 節）

- 派工：TERM-LOAN 的 session 派出（作者 Mac 的本機 session，2026-11-13）。登記在 #2118。
- 分支 `claude/term-loan-ui`。規則是 #2122（已合併，這個分支已併入 `origin/main`）。決策沿用 715（加第 7 節，沒取新號）；存檔版本、golden schema、`Sources/GameCore/`、`SaveFixtures/`、`ReplayFixtures/`、`GoldenScenarios/` 都沒動。
- **合併前**：新畫面，規劃看過截圖才合（ui-review 第三級）。ECONOMY-FULLSCREEN（經濟明細整個改全螢幕）疊在這個分支上，這個先合。

## 做了什麼

- `Sources/GamePresentation/TermLoanBoard.swift`：`GameWorld.termLoanBoard()`，畫面要的排序、借不了的原因、表單金額的範圍與兩種語言的文字。測試 `Tests/GamePresentationTests/TermLoanBoardTests.swift`。
- `RailwayGameApp/Views/EconomyPanel.swift`：經濟面板的「定期貸款」一段，與它開的全螢幕畫面 `TermLoanScreen`（`fullScreenCover`，寬的時候兩欄：左借入、右合約；窄或大字級一欄；借入的表單、報價、確認；合約清單、提前還的報價、確認、現金不夠時停用並寫原因）。
- `PlayerCommand.Edit.takeTermLoan`、`.repayTermLoanEarly`；`GameSession.takeTermLoan(principal:years:)`、`repayTermLoanEarly(_:)`。
- `BalanceSheet.rows`：多「定期貸款」一列，總計把它算進去。
- `GameSession.setEconomyMode`：有定期貸款時不讓切到自由模式（理由在決策 715 第 7 節第 6 點）。
- 截圖用的場景 `ScreenshotScene.termLoans` 與 `WebsiteScreenshotTests.testTermLoans`（中英文各拍一輪）。

## 為什麼畫面寫在 `EconomyPanel.swift` 裡，沒有開新檔

這台 Mac 沒有 XcodeGen（要作者同意才能裝），App 裡加新檔就得重新產生 `.xcodeproj`。所以 `TermLoanScreen` 與 `TermLoanRow` 放在 `EconomyPanel.swift` 的最後面。之後哪個有 XcodeGen 的 session 順手，可以搬到 `RailwayGameApp/Views/TermLoanScreen.swift` 再重新產生專案；不搬也不影響功能。

## 還留下什麼

1. 帳本裡到期與提前還仍顯示成「貸款利息（日結）」：要另給名字得在 GameCore 加帳目種類（存檔格式），留給下一個動規則的 PR。
2. 到期前沒有提醒；到期時餘額可以變負。要不要加站長提醒或通知，規劃決定。
3. `WhatsNew` 沒有加這一項（進哪一版由規劃決定）。
4. `CrashFuzzTests` 沒有加這兩個指令（會動到既有種子的序列）。
5. 成功訊息的橫幅浮在表單上，會蓋住合約欄的一兩行字幾秒（與其他畫面同一個橫幅）；捲動時標題列下緣有系統的模糊。
6. 整個經濟明細改全螢幕：另一個 session（ECONOMY-FULLSCREEN）在做，它只改 `TermLoanScreen` 怎麼被放進版面，不改裡面。
7. 規則上看到、沒有改的（寫給 #2122 的作者）：見 PR 說明的「規則上看到的」。

## 驗證

見 PR 說明的「驗證」一節（本機跑過的與沒跑的分開列）。
