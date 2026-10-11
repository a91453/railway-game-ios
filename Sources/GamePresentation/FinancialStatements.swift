import GameCore

// What the economy panel and the year-end report show of Phase 7a
// (ARCHITECTURE decision 85): the income statement, the cash flow statement
// and the balance sheet, row by row, in English or Traditional Chinese. The
// layout follows the `Ci/` reference's finance dashboard
// (`flowDashboardFinanceStatementHtml`: sections, rows, subtotals and a
// total; its cash flow statement's operating and investing activities and
// net increase in cash), with money in as positive and money out as
// negative. All of it is read from the world; nothing here is kept.

/// One row of a statement.
public struct StatementRow: Hashable, Sendable {
    public enum Style: Hashable, Sendable {
        /// A heading, with no amounts (the reference's `section`).
        case section
        case item
        /// A line that adds up those above it (`is-subtotal`).
        case subtotal
        /// The statement's bottom line (`is-total`).
        case total
    }

    public let title: String
    /// `nil` for a section.
    public let current: Money?
    /// The previous period's, or `nil` for a section or when there is none
    /// to compare with.
    public let previous: Money?
    public let style: Style

    public init(title: String, current: Money?, previous: Money?, style: Style) {
        self.title = title
        self.current = current
        self.previous = previous
        self.style = style
    }

    static func section(_ title: String) -> StatementRow {
        StatementRow(title: title, current: nil, previous: nil, style: .section)
    }
}

extension AssetClass {
    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .track: language.text("Track and structures", "軌道與結構物")
        case .stations: language.text("Stations", "車站")
        case .rollingStock: language.text("Trains and cars", "車輛")
        case .buildings: language.text("Buildings", "建物")
        case .land: language.text("Land", "土地")
        }
    }
}

extension FinanceSummary {
    /// The income statement (the reference's `incomeStatement`), with
    /// `previous` beside it if given: fares, the running costs, the
    /// operating profit, then interest, depreciation and assets written off
    /// down to the net profit, through the profit before tax and the tax
    /// where there was tax (decision 131).
    public func incomeStatementRows(previous: FinanceSummary?, in language: DisplayLanguage) -> [StatementRow] {
        func row(_ title: String, _ value: (FinanceSummary) -> Money, _ style: StatementRow.Style = .item) -> StatementRow {
            StatementRow(title: title, current: value(self), previous: previous.map(value), style: style)
        }
        let out = { (amount: Money) in Money.zero - amount }
        // Decision 94: the company's buildings, only where it has some.
        let property = hasProperty(previous: previous) ? [
            row(LedgerItem.propertyRent.displayName(in: language), \.propertyRevenue),
            row(language.text("Building upkeep, land tax and demolition", "建物維護、土地資產稅與拆除")) { out($0.propertyCost) },
        ] : []
        // Decision 155: freight, only where it brought something in.
        let freight = hasFreight(previous: previous) ? [row(LedgerItem.freightRevenue.displayName(in: language), \.freightRevenue)] : []
        // Decision 130: buildings sold, what they brought in less their
        // book value, the gain or loss realized; only where there were any.
        let sales = hasSales(previous: previous) ? [
            row(language.text("Buildings sold", "出售建物收入"), \.saleProceeds),
            row(language.text("Their book value", "出售建物的帳面價值")) { out($0.saleBookValue) },
            row(language.text("Gain or loss on sale (realized)", "出售建物損益（已實現）"), \.realizedGain, .subtotal),
        ] : []
        // Decision 131: the tax, only where there was some.
        let tax = hasTax(previous: previous) ? [
            row(language.text("Profit before tax", "稅前淨利"), \.profitBeforeTax, .subtotal),
            row(LedgerItem.incomeTax.displayName(in: language)) { out($0.taxCost) },
        ] : []
        return [
            row(LedgerItem.fareRevenue.displayName(in: language), \.fareRevenue),
        ] + freight + [
            row(LedgerItem.operatingCost.displayName(in: language)) { out($0.operatingCost) },
            row(LedgerItem.maintenanceCost.displayName(in: language)) { out($0.maintenanceCost) },
            row(language.text("Energy", "能源費用")) { out($0.energyCost) },
            row(language.text("Staff", "員工費用")) { out($0.staffCost) },
        ] + property + [
            row(language.text("Operating profit", "營業利益"), \.operatingProfit, .subtotal),
            row(LedgerItem.loanInterest.displayName(in: language)) { out($0.interestCost) },
            row(language.text("Depreciation", "折舊費用")) { out($0.depreciationCost) },
            row(language.text("Assets written off", "資產報廢損失")) { out($0.writeOffCost) },
        ] + sales + tax + [
            row(language.text("Net profit", "本期淨利"), \.netProfit, .total),
        ]
    }

    /// The cash flow statement (the reference's `cashFlowStatement`):
    /// operating, investing and financing activities and the net change in
    /// cash. The reference's investing activities are quota purchases and
    /// returns; here they are what was paid for track, stations, trains and
    /// cars, and since decision 130 what buildings sold for, and the
    /// financing activities are the loan, which it has not.
    ///
    /// With `closingCash`, the cash at the period's end (and the previous
    /// period's, if any), two more rows (decision 123): the cash at its
    /// start and at its end, so the net change can be checked against the
    /// cash in hand. Without them the real-world demo, which starts with the
    /// money its lines cost and spends it at once, showed a day's purchases
    /// of $ 6.6 million beside $ 3 million still in the bank.
    public func cashFlowRows(
        previous: FinanceSummary?, closingCash: (current: Money, previous: Money?)? = nil, in language: DisplayLanguage
    ) -> [StatementRow] {
        func row(_ title: String, _ value: (FinanceSummary) -> Money, _ style: StatementRow.Style = .item) -> StatementRow {
            StatementRow(title: title, current: value(self), previous: previous.map(value), style: style)
        }
        let out = { (amount: Money) in Money.zero - amount }
        let property = hasProperty(previous: previous) ? [
            row(language.text("Rent received", "收取租金"), \.propertyRevenue),
            row(language.text("Building upkeep, land tax and demolition paid", "建物維護、土地資產稅與拆除支出")) { out($0.propertyCost) },
        ] : []
        return [
            .section(language.text("Operating activities", "營業活動之現金流量")),
            row(LedgerItem.fareRevenue.displayName(in: language), \.fareRevenue),
        ] + (hasFreight(previous: previous) ? [row(LedgerItem.freightRevenue.displayName(in: language), \.freightRevenue)] : []) + [
            row(language.text("Running costs paid", "營運支出")) { out($0.totalCost) },
        ] + property + [
            row(language.text("Interest paid", "利息支出")) { out($0.interestCost) },
        ] + (hasTax(previous: previous) ? [row(language.text("Income tax paid", "所得稅支出")) { out($0.taxCost) }] : []) + [
            row(language.text("Net from operating", "營業活動淨額"), \.operatingCashFlow, .subtotal),
            .section(language.text("Investing activities", "投資活動之現金流量")),
            row(language.text("Track, stations, trains and buildings bought", "購置軌道、車站、車輛與建物")) { out($0.capitalSpending) },
        ] + (hasSales(previous: previous) ? [row(language.text("Buildings sold", "出售建物收入"), \.saleProceeds)] : []) + [
            row(language.text("Net from investing", "投資活動淨額"), \.investingCashFlow, .subtotal),
            .section(language.text("Financing activities", "籌資活動之現金流量")),
            row(language.text("Borrowed", "借入款項"), \.loanBorrowed),
            row(language.text("Repaid", "償還借款")) { out($0.loanRepaid) },
            row(language.text("Net from financing", "籌資活動淨額"), \.financingCashFlow, .subtotal),
            row(language.text("Net change in cash", "本期現金淨增減"), \.netCashFlow, .total),
        ] + cashInHand(previous: previous, closingCash: closingCash, in: language)
    }

    private func cashInHand(
        previous: FinanceSummary?, closingCash: (current: Money, previous: Money?)?, in language: DisplayLanguage
    ) -> [StatementRow] {
        guard let closingCash else { return [] }
        let previousClosing = previous == nil ? nil : closingCash.previous
        var previousOpening: Money?
        if let previous, let previousClosing {
            previousOpening = previousClosing - previous.netCashFlow
        }
        return [
            StatementRow(
                title: language.text("Cash at the start", "期初現金"),
                current: closingCash.current - netCashFlow,
                previous: previousOpening,
                style: .subtotal
            ),
            StatementRow(
                title: language.text("Cash at the end", "期末現金"),
                current: closingCash.current,
                previous: previousClosing,
                style: .total
            ),
        ]
    }

    /// Whether this period or `previous` sold any of the company's
    /// buildings (decision 130).
    private func hasSales(previous: FinanceSummary?) -> Bool {
        [self, previous].contains { $0.map { $0.saleProceeds != .zero || $0.saleBookValue != .zero } ?? false }
    }

    /// Whether this period or `previous` had the company's buildings' rent
    /// or costs (decision 94).
    private func hasProperty(previous: FinanceSummary?) -> Bool {
        [self, previous].contains { $0.map { $0.propertyRevenue != .zero || $0.propertyCost != .zero } ?? false }
    }

    /// Whether this period or `previous` brought freight in (decision 155).
    private func hasFreight(previous: FinanceSummary?) -> Bool {
        [self, previous].contains { $0.map { $0.freightRevenue != .zero } ?? false }
    }

    /// Whether this period or `previous` paid tax (decision 131).
    private func hasTax(previous: FinanceSummary?) -> Bool {
        [self, previous].contains { $0.map { $0.taxCost != .zero } ?? false }
    }
}

extension BalanceSheet {
    /// The balance sheet, with `previous` (the last year's closing) beside
    /// it if given: cash and each class of fixed assets at book value, the
    /// loan, and the equity left, with the totals of both sides.
    public func rows(previous: BalanceSheet?, in language: DisplayLanguage) -> [StatementRow] {
        func row(_ title: String, _ value: (BalanceSheet) -> Money, _ style: StatementRow.Style = .item) -> StatementRow {
            StatementRow(title: title, current: value(self), previous: previous.map(value), style: style)
        }
        return [
            .section(language.text("Assets", "資產")),
            row(language.text("Cash", "現金"), \.cash),
        ] + AssetClass.allCases.filter { assetClass in
            // Decision 94: buildings only once the company has had some;
            // decision 160: land alike.
            ![.buildings, .land].contains(assetClass) || self[assetClass] != .zero || previous.map { $0[assetClass] != .zero } ?? false
        }.map { assetClass in
            row(assetClass.displayName(in: language)) { $0[assetClass].bookValue }
        } + [
            row(language.text("Total assets", "資產總計"), \.totalAssets, .subtotal),
            .section(language.text("Liabilities and equity", "負債與權益")),
            row(language.text("Loan", "銀行借款"), \.loan),
            row(language.text("Equity", "權益"), \.equity),
            row(language.text("Total liabilities and equity", "負債與權益總計")) { $0.loan + $0.equity }.with(style: .total),
        ]
    }

    /// Each class's cost and how far it is written down, for the line under
    /// the balance sheet: "Trains and cars: cost $ 4,320, written down
    /// $ 432".
    public func depreciationText(of assetClass: AssetClass, in language: DisplayLanguage) -> String {
        let balance = self[assetClass]
        return language.text(
            "\(assetClass.displayName(in: language)): cost \(balance.cost.moneyText), written down \(balance.depreciation.moneyText)",
            "\(assetClass.displayName(in: language))：成本 \(balance.cost.moneyText)，累計折舊 \(balance.depreciation.moneyText)"
        )
    }
}

extension StatementRow {
    func with(style: Style) -> StatementRow {
        StatementRow(title: title, current: current, previous: previous, style: style)
    }
}

extension AnnualStatement {
    /// "Year 1", counting the first year as 1.
    public func yearText(in language: DisplayLanguage) -> String {
        Self.yearText(year, in: language)
    }

    static func yearText(_ year: Int64, in language: DisplayLanguage) -> String {
        language.text("Year \(year + 1)", "第 \(year + 1) 年")
    }

    /// The year-end report's title: "Year 1 closing" (the year-end
    /// settlement of A-Train-style games).
    public func titleText(in language: DisplayLanguage) -> String {
        language.text("\(yearText(in: language)) closing", "\(yearText(in: language))度決算")
    }

    /// One line for the report's top: "Net profit $ 1,234 · equity
    /// $ 3,456,789", or a loss.
    public func headlineText(in language: DisplayLanguage) -> String {
        let profit = income.netProfit
        let equity = closing.equity.moneyText
        return profit < .zero
            ? language.text("Net loss \(Money(0 - profit.amount).moneyText) · equity \(equity)", "本期淨損 \(Money(0 - profit.amount).moneyText) · 權益 \(equity)")
            : language.text("Net profit \(profit.moneyText) · equity \(equity)", "本期淨利 \(profit.moneyText) · 權益 \(equity)")
    }
}

extension GameWorld {
    /// The balance sheet's note on what was built before costs were kept
    /// (save version 16) or in free play, or `nil` when everything is on
    /// the books.
    public func unrecordedAssetsText(in language: DisplayLanguage) -> String? {
        let count = unrecordedAssetCount()
        guard count > 0 else { return nil }
        return language.text(
            "\(count) track, station or train items built before their cost was kept are on the books at $ 0.",
            "有 \(count) 項軌道、車站或列車在開始記錄成本之前建造，以 $ 0 入帳。"
        )
    }

    /// The year closed last, whose closing balance sheet the panel compares
    /// with, or `nil` before the first year has closed.
    public var lastClosedYear: AnnualStatement? {
        accounts.years.last
    }
}
