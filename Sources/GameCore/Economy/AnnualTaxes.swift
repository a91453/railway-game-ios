// The annual taxes (ARCHITECTURE decision 734, ANNUAL-FINANCE AF-1;
// `docs/research/ANNUAL_FINANCE_DESIGN_2026-11-13.md` §3.1, §3.6, §3.9). The
// shape is the owner's earlier desktop game's (`FinanceEngine`: the year's
// corporate tax charged as the year closes, owed as a liability and paid
// months later); the rates are Taiwan's, not that game's.
//
// With ``GameWorld/annualTaxes`` on, the company pays no tax at each
// midnight (decision 131). As a year closes, its profit before tax is
// charged the profit-seeking enterprise income tax (所得稅法 §5): nothing
// up to NT$120,000; above it 20 % of the whole profit, but never more than
// half of what is above NT$120,000. The tax is owed
// (``CompanyAccounts/incomeTaxPayable``, on the balance sheet as
// ``BalanceSheet/taxPayable``) until the midnight that ends the next year's
// fifth month (day 149 of the year, 30-day months), when it is paid in
// cash, whatever the balance (it may go below zero, as every cost may).
// Whole New Taiwan dollars, rounded down.

extension CompanyAccounts {
    /// Decision 734: the share of a year's profit before tax paid as income
    /// tax, in per cent (所得稅法 §5: 20 %).
    public static let annualIncomeTaxPercent: Int64 = 20
    /// A year's profit before tax up to this is not taxed: NT$120,000.
    public static let annualIncomeTaxThreshold: Money = 12_000_000
    /// Above ``annualIncomeTaxThreshold`` the tax is never more than this
    /// share of what is above it, in per cent: half.
    public static let annualIncomeTaxCapPercent: Int64 = 50
    /// The day of the year (from 0) whose midnight pays the tax the year
    /// before was charged: the last of the fifth month, as Taiwan's annual
    /// return is filed and paid in May.
    public static let incomeTaxDueDay: Int64 = 149
}

extension GameWorld {
    // MARK: - Commands

    /// Turns on or off whether the income tax is settled once a year
    /// (decision 734). Tax already owed stays owed and is paid when due.
    public mutating func setAnnualTaxes(_ enabled: Bool) {
        annualTaxes = enabled
    }

    // MARK: - Queries

    /// The income tax on a year's profit before tax `profit` (decision
    /// 734): nothing up to ``CompanyAccounts/annualIncomeTaxThreshold``;
    /// above it ``CompanyAccounts/annualIncomeTaxPercent`` of the whole,
    /// but at most ``CompanyAccounts/annualIncomeTaxCapPercent`` of what is
    /// above the threshold; whole dollars, rounded down.
    public static func annualIncomeTax(on profit: Money) -> Money {
        guard profit > CompanyAccounts.annualIncomeTaxThreshold else { return .zero }
        let dollars = profit.amount / 100
        let above = dollars - CompanyAccounts.annualIncomeTaxThreshold.amount / 100
        let full = dollars * CompanyAccounts.annualIncomeTaxPercent / 100
        let capped = above * CompanyAccounts.annualIncomeTaxCapPercent / 100
        return Money(min(full, capped) * 100)
    }

    /// The income tax this year would be charged if it closed now, from
    /// its profit before tax so far (decision 734): zero without the annual
    /// taxes.
    public func estimatedIncomeTax() -> Money {
        guard annualTaxes else { return .zero }
        return Self.annualIncomeTax(on: accounts.report(.year, day: dayIndex(of: clock.now)).current.profitBeforeTax)
    }

    // MARK: - Settlement

    /// Pays the income tax owed when day `day`, which just ended, is the
    /// year's ``CompanyAccounts/incomeTaxDueDay`` (decision 734).
    mutating func payIncomeTaxDue(day: Int64, time: GameTime) {
        let due = accounts.incomeTaxPayable
        let year = FinancePeriod.year.days
        guard due > .zero, day - CompanyAccounts.floorDivide(day, year) * year == CompanyAccounts.incomeTaxDueDay else { return }
        accounts.incomeTaxPayable = .zero
        write(LedgerEntry(
            kind: .annualIncomeTax, time: time, amount: .zero - due,
            breakdown: [LedgerLine(item: .incomeTax, amount: .zero - due)]
        ), day: day)
    }
}
