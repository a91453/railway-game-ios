import GameCore

// Decision 374 (City Transport Manager study 4.12): before the player
// borrows, what the next step of the loan costs. The loan has no term
// (decision 67): its interest is paid every midnight on what is owed, and
// what is owed is repaid a step at a time whenever the player likes. So
// the preview gives the interest each day, what it comes to over a month
// and a year of the game's calendar, and, from the last full days, what
// the company would keep each day with it.

/// The next step of the loan, before it is borrowed.
public struct LoanPreview: Equatable, Sendable {
    /// What would be borrowed.
    public let amount: Money
    /// The interest the step adds to each midnight's.
    public let dailyInterest: Money
    /// The company's mean result of its last full days (at most
    /// ``recentDays``), before the step, or `nil` before its first.
    public let recentDailyResult: Money?
    /// How many days ``recentDailyResult`` is the mean of.
    public let recentDayCount: Int

    /// The most full days the mean reads.
    public static let recentDays = 7

    public init(amount: Money, dailyInterest: Money, recentDailyResult: Money?, recentDayCount: Int) {
        self.amount = amount
        self.dailyInterest = dailyInterest
        self.recentDailyResult = recentDailyResult
        self.recentDayCount = recentDayCount
    }

    /// The interest the step costs if it is kept `days` days.
    public func interest(overDays days: Int64) -> Money {
        Money(dailyInterest.amount * days)
    }

    /// The step's interest over a month of the calendar.
    public var monthInterest: Money {
        interest(overDays: FinancePeriod.month.days)
    }

    /// The step's interest over a year of the calendar.
    public var yearInterest: Money {
        interest(overDays: FinancePeriod.year.days)
    }

    /// What the company would keep a day with the step, from its last
    /// full days, or `nil` before its first.
    public var dailyResultAfter: Money? {
        recentDailyResult.map { $0 - dailyInterest }
    }

    /// "Borrowing $100,000 adds $14 of interest each day, paid at
    /// midnight."
    public func paymentText(in language: DisplayLanguage) -> String {
        language.text(
            "Borrowing \(amount.moneyText) adds \(dailyInterest.moneyText) of interest each day, paid at midnight.",
            "借入 \(amount.moneyText)：每天多付利息 \(dailyInterest.moneyText)，午夜支付。"
        )
    }

    /// "Kept a month, $420 of interest in all; kept a year, $5,040, and
    /// $105,040 with the loan repaid. Repay it whenever you like."
    public func totalText(in language: DisplayLanguage) -> String {
        let repaid = amount + yearInterest
        return language.text(
            "Kept a month, \(monthInterest.moneyText) of interest in all; kept a year, \(yearInterest.moneyText), and \(repaid.moneyText) with the loan repaid. Repay it whenever you like.",
            "借一個月共付利息 \(monthInterest.moneyText)；借一年共付 \(yearInterest.moneyText)，連本金共 \(repaid.moneyText)。本金隨時可以還。"
        )
    }

    /// "Over the last 7 days the company kept $2,300 a day; with this
    /// loan, about $2,286.", or `nil` before the first full day.
    public func resultText(in language: DisplayLanguage) -> String? {
        guard let before = recentDailyResult, let after = dailyResultAfter else { return nil }
        let days = recentDayCount
        let beforeText = LedgerEntry.signedMoneyText(before), afterText = LedgerEntry.signedMoneyText(after)
        return language.text(
            "Over the last \(days) \(days == 1 ? "day" : "days") the company made \(beforeText) a day; with this loan, about \(afterText).",
            "最近 \(days) 天平均每天 \(beforeText)；借了以後約 \(afterText)。"
        )
    }
}

extension GameWorld {
    /// The next step of the loan (decision 374), or `nil` when it cannot be
    /// borrowed: the company is free, its funds are unlimited, or the loan
    /// is at its most.
    public func loanPreview() -> LoanPreview? {
        let step = CompanyAccounts.loanStep
        guard accounts.mode == .management, !economy.unlimitedFunds, accounts.loan + step <= CompanyAccounts.maximumLoan else { return nil }
        let added = GameWorld.dailyLoanInterest(on: accounts.loan + step) - GameWorld.dailyLoanInterest(on: accounts.loan)
        let today = FinanceHistory.floorDay(clock.now)
        let recent = accounts.days.filter { $0.day < today && $0.day >= today - Int64(LoanPreview.recentDays) }
        let mean = recent.isEmpty ? nil : Money(recent.map { Self.dailyResult($0).amount }.reduce(0, +) / Int64(recent.count))
        return LoanPreview(amount: step, dailyInterest: added, recentDailyResult: mean, recentDayCount: recent.count)
    }

    /// What the company kept on `day`: everything earned less everything
    /// paid but what it bought.
    static func dailyResult(_ day: DayAccount) -> Money {
        day.fareRevenue + day.freightRevenue + day.propertyRevenue
            - day.totalCost - day.propertyCost - day.interestCost - day.taxCost
    }
}
