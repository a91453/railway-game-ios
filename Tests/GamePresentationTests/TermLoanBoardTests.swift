import GameCore
@testable import GamePresentation
import XCTest

/// Decision 715's screen: the term loans as the economy panel lists them,
/// what the form offers, the words of a quote and of paying back early,
/// the session's two commands, and the balance sheet's row.
final class TermLoanBoardTests: XCTestCase {
    /// A managed company of NT$20,000,000 and nothing else, its clock
    /// running; a train costs `train`.
    private func world(balance: Money = 2_000_000_000, train: Money = 5_000) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 8_192, height: 6_144),
            economy: GameEconomy(balance: balance, costs: ConstructionCosts(track: 100, station: 1_000, train: train)),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        return world
    }

    private let step = CompanyAccounts.loanStep

    func testACompanyWithNoTermLoanIsOfferedHalfOfWhatItIsWorth() throws {
        let board = try world().termLoanBoard()
        XCTAssertEqual(board.contracts, [])
        XCTAssertNil(board.blocked)
        XCTAssertEqual(board.summaryText(in: .english), "No term loans")
        XCTAssertEqual(board.summaryText(in: .traditionalChinese), "沒有定期貸款")
        XCTAssertNil(board.nextDueText(in: .english))
        // Below half of NT$20,000,000, in whole steps of NT$300,000.
        XCTAssertEqual(board.credit.maximumPrincipal, Money(990_000_000))
        XCTAssertEqual(board.creditText(in: .english), "Up to \(Money(990_000_000).moneyText) more · 50 more loans")
        XCTAssertEqual(board.creditText(in: .traditionalChinese), "還能借 \(Money(990_000_000).moneyText) · 還能簽 50 筆")
        XCTAssertEqual(board.principalChoices, step.amount...990_000_000)
    }

    func testTheFormKeepsTheAmountInWholeStepsTheBankLends() throws {
        let board = try world().termLoanBoard()
        XCTAssertEqual(board.principal(for: nil), Money(300_000_000), "ten steps to start from")
        XCTAssertEqual(board.principal(for: Money(0)), step)
        XCTAssertEqual(board.principal(for: Money(-5)), step)
        XCTAssertEqual(board.principal(for: Money(75_000_000)), Money(60_000_000), "down to a whole step")
        XCTAssertEqual(board.principal(for: Money(5_000_000_000)), Money(990_000_000))
        // A smaller company starts from the most it can have.
        let small = try world(balance: 200_000_000).termLoanBoard()
        XCTAssertEqual(small.credit.maximumPrincipal, Money(90_000_000))
        XCTAssertEqual(small.principal(for: nil), Money(90_000_000))
        // Whatever the form shows, the bank quotes.
        var world = try world()
        for choice in [nil, Money(0), Money(75_000_000), Money(5_000_000_000)] {
            let principal = try XCTUnwrap(world.termLoanBoard().principal(for: choice))
            for years in TermLoanBoard.yearChoices {
                XCTAssertNoThrow(try world.termLoanQuote(principal: principal, years: years))
            }
        }
        try world.takeTermLoan(principal: Money(990_000_000), years: 1)
        XCTAssertNil(world.termLoanBoard().principal(for: nil))
        XCTAssertNil(world.termLoanBoard().principalChoices)
    }

    func testTheQuotesWords() throws {
        let quote = try world().termLoanQuote(principal: Money(300_000_000), years: 2)
        let due = GameDate(day: 720)
        XCTAssertEqual(due.year, 3)
        XCTAssertEqual(quote.rows(in: .english).map(\.title), ["Rate a year", "Interest in all", "Due", "Paid when due"])
        XCTAssertEqual(
            quote.rows(in: .english).map(\.value),
            ["5.10%", Money(30_600_000).moneyText, due.text(in: .english), Money(330_600_000).moneyText]
        )
        XCTAssertEqual(quote.rows(in: .traditionalChinese).map(\.title), ["年利率", "整期利息", "到期日", "到期一次付"])
        XCTAssertEqual(
            quote.confirmText(in: .english),
            "You get \(Money(300_000_000).moneyText) now and pay \(Money(330_600_000).moneyText) in one sum on \(due.text(in: .english)). Repaying before then costs an early fee."
        )
        XCTAssertEqual(
            quote.confirmText(in: .traditionalChinese),
            "現在拿到 \(Money(300_000_000).moneyText)，\(due.text(in: .traditionalChinese))一次付 \(Money(330_600_000).moneyText)。提前還要付違約金。"
        )
        XCTAssertEqual((1...10).map { TermLoanBoard.rateText(CompanyAccounts.termLoanRate(years: $0) ?? 0) },
                       ["5.00%", "5.10%", "5.20%", "5.30%", "5.40%", "5.50%", "5.70%", "5.90%", "6.10%", "6.30%"])
        XCTAssertEqual(TermLoanBoard.rateText(505), "5.05%")
        XCTAssertEqual(TermLoanBoard.yearsText(1, in: .english), "1 year")
        XCTAssertEqual(TermLoanBoard.yearsText(10, in: .english), "10 years")
        XCTAssertEqual(TermLoanBoard.yearsText(10, in: .traditionalChinese), "10 年")
    }

    func testTheContractsAreListedSoonestDueFirst() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        try world.takeTermLoan(principal: step, years: 1)
        try world.takeTermLoan(principal: step, years: 2)
        let board = world.termLoanBoard()
        XCTAssertEqual(board.contracts.map(\.id), [2, 1, 3])
        XCTAssertEqual(board.contracts.map(\.loan), [2, 1, 3].map { id in world.accounts.termLoans.first { $0.id == id } })
        // NT$3,306,000, NT$315,000 and NT$330,600.
        XCTAssertEqual(board.totalDue, Money(395_160_000))
        XCTAssertEqual(board.totalDue, world.termLoanCredit().outstanding)
        XCTAssertEqual(board.summaryText(in: .english), "3 term loans · \(Money(395_160_000).moneyText) to pay when due")
        XCTAssertEqual(board.summaryText(in: .traditionalChinese), "定期貸款 3 筆 · 到期共付 \(Money(395_160_000).moneyText)")
        let soonest = GameDate(day: 360)
        XCTAssertEqual(board.nextDueText(in: .english), "Next due \(soonest.text(in: .english)): \(Money(31_500_000).moneyText)")
        XCTAssertEqual(board.nextDueText(in: .traditionalChinese), "最近到期：\(soonest.text(in: .traditionalChinese))，付 \(Money(31_500_000).moneyText)")
        XCTAssertEqual(board.contracts[1].loan.termsText(in: .english), "2 years at 5.10% · due \(GameDate(day: 720).text(in: .english))")
        XCTAssertEqual(board.contracts[0].loan.termsText(in: .traditionalChinese), "1 年 · 年利率 5.00% · \(soonest.text(in: .traditionalChinese))到期")
        XCTAssertEqual(board.creditText(in: .english), "Up to \(board.credit.maximumPrincipal.moneyText) more · 47 more loans")
        XCTAssertEqual(board.contracts[1].loan.dueTotalText(in: .english), "Pays \(Money(330_600_000).moneyText) when due")
        XCTAssertEqual(board.contracts[1].loan.dueTotalText(in: .traditionalChinese), "到期付 \(Money(330_600_000).moneyText)")

        var one = try self.world()
        try one.takeTermLoan(principal: step, years: 1)
        XCTAssertEqual(one.termLoanBoard().summaryText(in: .english), "1 term loan · \(Money(31_500_000).moneyText) to pay when due")
    }

    func testPayingBackEarlyIsPricedAsTheRuleChargesIt() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        // Signed today: no interest yet, a fifth of NT$306,000 as the fee.
        var contract = try XCTUnwrap(world.termLoanBoard().contracts.first)
        XCTAssertEqual(contract.repayment, try world.termLoanRepaymentQuote(1))
        XCTAssertTrue(contract.canRepay)
        XCTAssertNil(contract.shortfallText(in: .english))
        XCTAssertEqual(contract.roundedOff, .zero)
        XCTAssertEqual(
            contract.repaymentText(in: .english),
            "Repaying today: \(Money(0).moneyText) of interest for 0 days and a \(Money(6_120_000).moneyText) early fee, \(Money(306_120_000).moneyText) in all with the loan."
        )
        XCTAssertEqual(
            contract.repaymentText(in: .traditionalChinese),
            "今天提前還：已過 0 天的利息 \(Money(0).moneyText)，違約金 \(Money(6_120_000).moneyText)，連本金共付 \(Money(306_120_000).moneyText)。"
        )
        XCTAssertEqual(contract.repayText(in: .english), "Repay Today for \(Money(306_120_000).moneyText)…")
        XCTAssertEqual(contract.repayText(in: .traditionalChinese), "今天提前還 \(Money(306_120_000).moneyText)…")
        // A week on, NT$2,975 and NT$60,605 are charged as NT$63,500.
        try world.advance(ticks: 7 * 1_440)
        contract = try XCTUnwrap(world.termLoanBoard().contracts.first)
        XCTAssertEqual(contract.repayment.elapsedDays, 7)
        XCTAssertEqual(contract.roundedOff, Money(8_000))
        XCTAssertEqual(
            contract.repaymentText(in: .english),
            "Repaying today: \(Money(297_500).moneyText) of interest for 7 days and a \(Money(6_060_500).moneyText) early fee, less the odd \(Money(8_000).moneyText), \(Money(306_350_000).moneyText) in all with the loan."
        )
        XCTAssertEqual(
            contract.repaymentText(in: .traditionalChinese),
            "今天提前還：已過 7 天的利息 \(Money(297_500).moneyText)，違約金 \(Money(6_060_500).moneyText)，不滿百元的 \(Money(8_000).moneyText) 不計，連本金共付 \(Money(306_350_000).moneyText)。"
        )
        XCTAssertEqual(contract.repayment.total, world.accounts.termLoans[0].principal + contract.repayment.accruedInterest + contract.repayment.penalty - contract.roundedOff)
    }

    func testALoanTheCashCannotPayBackSaysHowMuchIsMissing() throws {
        // NT$9,900,000 for ten years, then a train of NT$25,000,000.
        var world = try world(train: 2_500_000_000)
        try world.takeTermLoan(principal: Money(990_000_000), years: 10)
        try world.purchaseTrain(named: "T")
        XCTAssertEqual(world.economy.balance, Money(490_000_000))
        let contract = try XCTUnwrap(world.termLoanBoard().contracts.first)
        let total = try world.termLoanRepaymentQuote(1).total
        XCTAssertFalse(contract.canRepay)
        XCTAssertEqual(contract.shortfall, total - Money(490_000_000))
        XCTAssertEqual(contract.shortfallText(in: .english), "Not enough cash to repay it today: \(contract.shortfall.moneyText) short.")
        XCTAssertEqual(contract.shortfallText(in: .traditionalChinese), "現金不夠，今天還不了：還差 \(contract.shortfall.moneyText)。")
        XCTAssertThrowsError(try world.repayTermLoanEarly(1)) {
            XCTAssertEqual($0 as? GameError, .insufficientFunds(required: total, available: Money(490_000_000)))
        }
    }

    func testWhyTheBankLendsNothing() throws {
        var free = try world()
        free.setEconomyMode(.free)
        XCTAssertEqual(free.termLoanBoard().blocked, .freePlay)
        XCTAssertNil(free.termLoanBoard().principal(for: nil))
        XCTAssertEqual(free.termLoanBoard().creditText(in: .english), "Only a managed company can sign a term loan. Free play cannot.")
        XCTAssertEqual(free.termLoanBoard().creditText(in: .traditionalChinese), "定期貸款只有經營模式能借，自由模式不能簽約。")
        XCTAssertThrowsError(try free.termLoanQuote(principal: step, years: 1)) { XCTAssertEqual($0 as? GameError, .loanNeedsManagement) }

        var signed = try world()
        try signed.takeTermLoan(principal: step, years: 1)
        signed.setEconomyMode(.free)
        XCTAssertEqual(signed.termLoanBoard().blocked, .freePlay)
        XCTAssertEqual(signed.termLoanBoard().creditText(in: .english), "Free play cannot sign a term loan. The ones already signed can still be repaid early.")
        XCTAssertEqual(signed.termLoanBoard().creditText(in: .traditionalChinese), "自由模式不能再簽定期貸款，已簽的仍可以提前還。")
        XCTAssertTrue(signed.termLoanBoard().contracts[0].canRepay)

        let poor = try world(balance: 10_000)
        XCTAssertEqual(poor.termLoanBoard().blocked, .noCredit)
        XCTAssertNil(poor.termLoanBoard().principalChoices)
        XCTAssertEqual(poor.termLoanBoard().creditText(in: .traditionalChinese), "目前沒有額度可借。公司的淨值增加，額度就會增加。")
        XCTAssertEqual(poor.termLoanBoard().creditText(in: .english), "The bank has nothing more to lend now. It lends more as the company is worth more.")

        var full = try world(balance: 10_000_000_000)
        for _ in 0..<CompanyAccounts.termLoanSlots {
            try full.takeTermLoan(principal: step, years: 1)
        }
        XCTAssertEqual(full.termLoanBoard().blocked, .full)
        XCTAssertEqual(full.termLoanBoard().contracts.count, 50)
        XCTAssertEqual(full.termLoanBoard().creditText(in: .english), "The bank holds 50 term loans at once. Repay one to sign another.")
        XCTAssertEqual(full.termLoanBoard().creditText(in: .traditionalChinese), "最多同時 50 筆，還掉一筆才能再簽。")
    }

    func testThePanelShowsTermLoansUnlessFundsAreUnlimited() throws {
        var world = try world()
        XCTAssertTrue(world.showsTermLoans)
        try world.takeTermLoan(principal: step, years: 1)
        world.setUnlimitedFunds(true)
        XCTAssertTrue(world.showsTermLoans, "there is one to pay back")
        var unlimited = try self.world()
        unlimited.setUnlimitedFunds(true)
        XCTAssertFalse(unlimited.showsTermLoans)
    }

    @MainActor
    func testTheSessionSignsAndRepaysThroughTheCommandLog() throws {
        let session = GameSession(world: try world())
        let due = GameDate(day: 720)
        session.takeTermLoan(principal: Money(300_000_000), years: 2)
        XCTAssertEqual(session.world.accounts.termLoans.map(\.principal), [Money(300_000_000)])
        XCTAssertEqual(session.world.economy.balance, Money(2_300_000_000))
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(
            session.message?.text,
            "Signed a term loan of \(Money(300_000_000).moneyText) for 2 years. \(Money(330_600_000).moneyText) is due on \(due.text(in: .english))."
        )
        // More than the bank lends: refused in the bank's words, nothing signed.
        session.takeTermLoan(principal: Money(990_000_000), years: 1)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.text, GameError.invalidTermLoan.playerMessage(in: .english))
        XCTAssertEqual(session.world.accounts.termLoans.count, 1)

        session.repayTermLoanEarly(1)
        XCTAssertEqual(session.world.accounts.termLoans, [])
        XCTAssertEqual(session.world.economy.balance, Money(2_000_000_000 - 6_120_000))
        XCTAssertEqual(session.message?.text, "Repaid the term loan of \(Money(300_000_000).moneyText): \(Money(306_120_000).moneyText) in all.")
        session.repayTermLoanEarly(1)
        XCTAssertEqual(session.message?.kind, .failure)

        let chinese = GameSession(world: try world(), language: .traditionalChinese)
        chinese.takeTermLoan(principal: Money(300_000_000), years: 2)
        XCTAssertEqual(
            chinese.message?.text,
            "簽了 2 年的定期貸款 \(Money(300_000_000).moneyText)，\(due.text(in: .traditionalChinese))到期付 \(Money(330_600_000).moneyText)。"
        )
        chinese.repayTermLoanEarly(1)
        XCTAssertEqual(chinese.message?.text, "還清定期貸款 \(Money(300_000_000).moneyText)，共付 \(Money(306_120_000).moneyText)。")
    }

    @MainActor
    func testARepaymentTheCashCannotPayIsRefusedWithWhatItNeeds() throws {
        var world = try world(train: 2_500_000_000)
        try world.takeTermLoan(principal: Money(990_000_000), years: 10)
        try world.purchaseTrain(named: "T")
        let session = GameSession(world: world)
        session.repayTermLoanEarly(1)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.fundsNeeded, try world.termLoanRepaymentQuote(1).total)
        XCTAssertEqual(session.world, world)
    }

    /// Free play never settles a day, so a term loan would never fall due:
    /// as with the loan of decision 67, it is repaid before the switch.
    @MainActor
    func testACompanyWithATermLoanDoesNotSwitchToFreePlay() throws {
        let session = GameSession(world: try world(), language: .traditionalChinese)
        session.takeTermLoan(principal: step, years: 1)
        session.setEconomyMode(.free)
        XCTAssertEqual(session.world.accounts.mode, .management)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.text, "公司還有定期貸款，連利息共 \(Money(31_500_000).moneyText)。自由模式不會到期付款，請先提前還清再切換。")
        session.repayTermLoanEarly(1)
        session.setEconomyMode(.free)
        XCTAssertEqual(session.world.accounts.mode, .free)
    }

    /// The screenshot scene shows each state of the screen: contracts due
    /// on different days, one the cash cannot pay back, and credit left.
    func testTheScreenshotSceneShowsEveryState() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let world = ScreenshotScene.termLoans.make(in: language)
            let board = world.termLoanBoard()
            XCTAssertEqual(world.accounts.mode, .management)
            XCTAssertTrue(world.showsTermLoans)
            XCTAssertEqual(board.contracts.map(\.id), [2, 1, 3])
            XCTAssertEqual(board.contracts.map(\.canRepay), [true, true, false])
            XCTAssertEqual(board.contracts.map(\.repayment.elapsedDays), [3, 3, 0])
            XCTAssertNil(board.blocked)
            XCTAssertNotNil(board.principal(for: nil))
            XCTAssertEqual(world.clock.speed, .paused)
        }
    }

    func testTheBalanceSheetListsTermLoansOnceThereAreSome() throws {
        var world = try world()
        let none = world.balanceSheet().rows(previous: nil, in: .english)
        XCTAssertFalse(none.map(\.title).contains("Term loans"))
        try world.borrow(step)
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        let sheet = world.balanceSheet()
        let rows = sheet.rows(previous: nil, in: .english)
        XCTAssertEqual(rows.suffix(4).map(\.title), ["Loan", "Term loans", "Equity", "Total liabilities and equity"])
        XCTAssertEqual(rows.suffix(4).map(\.current), [step, Money(300_000_000), Money(2_000_000_000), Money(2_330_000_000)])
        XCTAssertEqual(rows.last?.current, sheet.totalAssets, "both sides balance")
        XCTAssertEqual(sheet.rows(previous: nil, in: .traditionalChinese).suffix(3).first?.title, "定期貸款")
        // Paid back, the row stays while the year before had some.
        try world.repayTermLoanEarly(1)
        let after = world.balanceSheet()
        XCTAssertFalse(after.rows(previous: nil, in: .english).map(\.title).contains("Term loans"))
        let beside = after.rows(previous: sheet, in: .english)
        let row = try XCTUnwrap(beside.first { $0.title == "Term loans" })
        XCTAssertEqual(row.current, .zero)
        XCTAssertEqual(row.previous, Money(300_000_000))
        XCTAssertEqual(beside.last?.previous, sheet.totalAssets)
    }
}
