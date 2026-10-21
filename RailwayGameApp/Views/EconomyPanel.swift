import GameCore
import GamePresentation
import SwiftUI

/// The company's money (G1c, decision 36), after the reference's economy
/// details: the balance, free play or management, the fare rules, the last
/// hour by item, the income or cash flow statement for a period (this one
/// and the last), the balance sheet, the closed years (Phase 7a, decision
/// 85) and the last rows of the ledger.
///
/// Everything shown is read from `session.world` when the view is drawn,
/// and every control calls a `GameSession` method that applies one
/// `GameWorld` command.
struct EconomyPanel: View {
    let session: GameSession
    /// Closes it (decision 106: shown beside the map, not presented, so
    /// the environment's dismiss would do nothing).
    @Environment(GameScreenState.self) private var screen
    @State private var period: FinancePeriod = .day
    @State private var statement: Statement = .income
    @State private var trendRange: FinanceTrendRange = .thirtyDays
    @State private var flatFare: Int64 = 500
    /// The distance steps' first fare, in cents; `nil` until the panel
    /// takes the world's (``FareRules/bandStart(baseline:)``).
    @State private var bandStart: Int64?
    /// The day pass's price on the stepper, in cents; `nil` until the
    /// player moves it (decision 324).
    @State private var dayPassPrice: Int64?
    @State private var confirmsFreePlay = false
    /// Whether the reports under the "Today" card show: `nil` until the
    /// player chooses, when a game of simple rules shows only the card.
    @State private var showsReports: Bool?

    var body: some View {
        NavigationStack {
            Form {
                // CTM study 4.12 (M0): today's money in three lines first.
                let today = session.world.todayAccount()
                if let today {
                    todaySection(today)
                }
                if session.world.scenario != nil {
                    goalsSection
                }
                if today == nil || showsAllReports {
                    trendSection
                    balanceSection
                    // Decision 200: with unlimited funds there is nothing to
                    // borrow for, and no cash to sheet.
                    if !session.world.economy.unlimitedFunds {
                        loanSection
                    }
                    faresSection
                    dayPassSection
                    lastHourSection
                    reportSection
                    if !session.world.economy.unlimitedFunds {
                        balanceSheetSection
                    }
                    closedYearsSection
                    ledgerSection
                }
                if today != nil {
                    reportsToggleSection
                }
            }
            .navigationTitle("Economy")
            .hardTopScrollEdge()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        screen.panel = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session, announces: false)
            }
        }
    }

    private var accounts: CompanyAccounts {
        session.world.accounts
    }

    /// Decision 258's simple rules show only the "Today" card at first;
    /// realistic games show every report, as before.
    private var showsAllReports: Bool {
        showsReports ?? (NewGameRules(of: session.world) == .realistic)
    }

    // MARK: - Sections

    /// Today's fares, running costs and result, to the last full hour
    /// (CTM study 4.12, step M0; ``TodayAccount``).
    private func todaySection(_ today: TodayAccount) -> some View {
        let language = session.language
        let rows = today.rows(in: language)
        return Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                LabeledContent {
                    Text(verbatim: row.value)
                        .foregroundStyle(index == rows.count - 1 ? (today.result < .zero ? Theme.error : Theme.success) : Theme.textPrimary)
                } label: {
                    Text(verbatim: row.title)
                }
                .font(index == rows.count - 1 ? .body.weight(.semibold) : .body)
                .monospacedDigit()
            }
        } header: {
            Text(verbatim: today.title(in: language))
        } footer: {
            Text(verbatim: today.note(in: language))
        }
        .accessibilityIdentifier("economy.today")
    }

    /// Shows or hides the reports under the "Today" card.
    private var reportsToggleSection: some View {
        Section {
            Button {
                showsReports = !showsAllReports
            } label: {
                Text(verbatim: showsAllReports
                     ? session.language.text("Hide the other reports", "收起其他報表")
                     : session.language.text("Show the other reports", "顯示其他報表"))
            }
            .accessibilityIdentifier("economy.reports")
        }
    }

    /// Decision 176: how the company is growing, over 30 days, 90 days, a
    /// year or all its closed years.
    private var trendSection: some View {
        Section {
            Picker(selection: $trendRange) {
                ForEach(FinanceTrendRange.allCases, id: \.self) { range in
                    Text(verbatim: range.displayName(in: session.language)).tag(range)
                }
            } label: {
                Text(verbatim: session.language.text("Range", "範圍"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("economy.trend.range")
            FinanceTrendCharts(history: FinanceHistory.make(trendRange, world: session.world), language: session.language)
        } header: {
            Text(verbatim: session.language.text("Trends", "趨勢"))
        }
    }

    private var balanceSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((session.world.economy.showsInTheRed ? Theme.error : Theme.success).opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "banknote.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(session.world.economy.showsInTheRed ? Theme.error : Theme.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    // Decision 200: "∞" with unlimited funds.
                    Text(verbatim: session.world.economy.cashText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(session.world.economy.showsInTheRed ? Theme.error : Theme.textPrimary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)

            LabeledContent("Mode", value: accounts.mode.displayName(in: session.language))
            // Decision 160: the tiles of the map owned, and what the next
            // costs and needs.
            if let map = session.mapExpansionText {
                Text(verbatim: map)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("economy.mapExpansion")
            }
            // Decision 200: what unlimited funds mean.
            if session.world.economy.unlimitedFunds {
                Text(verbatim: session.language.text(
                    "Unlimited funds: building and buying cost nothing. Fares and costs are still counted. Games with unlimited funds do not count for achievements.",
                    "資金無限：建造與購買都不扣款，票收與成本照常計算。資金無限的局不計成就。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("economy.unlimitedFunds")
            }
            // Decision 162, later: the fuel price while a spell lasts, not
            // only the station master's first day.
            if let fuel = session.world.fuelText(in: session.language) {
                Text(verbatim: fuel)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("economy.fuel")
            }
            // Free play cannot become managed again (decision 46), so the
            // switch goes one way, after a confirmation. Decision 86,
            // later: not while a challenge is being played.
            if accounts.mode == .management {
                Button("Switch to Free Play", role: .destructive) {
                    confirmsFreePlay = true
                }
                .disabled(session.isFreePlayLocked)
                .confirmationDialog("Switch to Free Play", isPresented: $confirmsFreePlay, titleVisibility: .visible) {
                    Button("Switch to Free Play", role: .destructive) {
                        session.setEconomyMode(.free)
                    }
                } message: {
                    Text("Free play has no fares or running costs, and you set each station's ridership. It cannot become a managed company again.")
                }
                if session.isFreePlayLocked {
                    Text(verbatim: GameSession.freePlayLockedText(in: session.language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            Text(accounts.mode == .management
                ? "Passengers pay as they board. Running and upkeep are settled every hour, energy and staff every day, and the balance may go below zero."
                : "Free play: no fares and no running costs.")
        }
    }

    /// Decision 86: the challenge's goals, opening the goals panel's
    /// sections.
    private var goalsSection: some View {
        Section {
            NavigationLink {
                Form {
                    GoalsSections(session: session)
                }
                .navigationTitle(Text(verbatim: session.world.scenarioTitle(in: session.language) ?? ""))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.world.scenarioTitle(in: session.language) ?? "")
                        .fontWeight(.semibold)
                    if let status = session.world.scenarioStatusText(in: session.language) {
                        Text(verbatim: status)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .accessibilityIdentifier("economy.goals")
        } header: {
            Text(verbatim: session.language.text("Challenge", "挑戰"))
        }
    }

    /// Decision 67: borrowing and repaying in steps, with the daily
    /// interest. The words come from GamePresentation in the game's
    /// language.
    private var loanSection: some View {
        Section {
            Text(verbatim: accounts.loanText(in: session.language))
                .monospacedDigit()
                .accessibilityIdentifier("economy.loan")
            HStack {
                Button {
                    session.borrowLoanStep()
                } label: {
                    Text(verbatim: session.language.text("Borrow \(CompanyAccounts.loanStep.moneyText)", "借入 \(CompanyAccounts.loanStep.moneyText)"))
                }
                .disabled(accounts.mode != .management || accounts.loan >= CompanyAccounts.maximumLoan)
                .accessibilityIdentifier("economy.borrow")
                Spacer()
                Button {
                    session.repayLoanStep()
                } label: {
                    Text(verbatim: session.language.text("Repay \(CompanyAccounts.loanStep.moneyText)", "償還 \(CompanyAccounts.loanStep.moneyText)"))
                }
                .disabled(accounts.loan == .zero)
                .accessibilityIdentifier("economy.repay")
            }
            .buttonStyle(.borderless)
        } header: {
            Text(verbatim: session.language.text("Loan", "貸款"))
        } footer: {
            Text(verbatim: CompanyAccounts.loanTermsText(in: session.language))
        }
    }

    private var faresSection: some View {
        Section("Fares") {
            LabeledContent("Rules", value: accounts.effectiveFareRules.displayText(in: session.language))
            Stepper(value: $flatFare, in: 0...10_000, step: 25) {
                Text("Flat fare \(Money(flatFare).centsText)")
                    .monospacedDigit()
            }
            Button("Charge a flat fare of \(Money(flatFare).centsText)") {
                session.setFareRules(.flat(Money(flatFare)))
            }
            // TestFlight 59.1: the distance steps from a fare of the
            // player's, the standard five scaled to it.
            let language = session.language
            let start = Binding(
                get: { bandStart ?? accounts.effectiveFareRules.bandStart(baseline: accounts.fareBaseline) },
                set: { bandStart = $0 }
            )
            let bands = FareRules.distanceBands(startingAt: Money(start.wrappedValue), baseline: accounts.fareBaseline)
            Stepper(value: start, in: FareRules.bandStartRange, step: Int(FareRules.bandStartStep)) {
                Text(verbatim: language.text("Distance fares from \(Money(start.wrappedValue).centsText)", "階梯票價起價 \(Money(start.wrappedValue).centsText)"))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("economy.bandStart")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(FareRules.bandsText(bands, in: language), id: \.self) { band in
                    Text(verbatim: band)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("economy.bandPreview")
            Button {
                session.setFareRules(.distance(bands))
            } label: {
                Text(verbatim: language.text("Charge by distance from \(bands[0].fare.centsText)", "改收階梯票價（\(bands[0].fare.centsText) 起）"))
            }
            .accessibilityIdentifier("economy.chargeByDistance")
        }
    }

    /// Decision 324: the day pass, a ticket for a day of rides that the
    /// sights' visitors buy.
    private var dayPassSection: some View {
        let language = session.language
        let card = DayPassCard(world: session.world)
        let price = Binding(
            get: { dayPassPrice ?? card.suggestedPrice.amount },
            set: { dayPassPrice = $0 }
        )
        return Section {
            Label {
                Text(verbatim: card.statusText(in: language))
            } icon: {
                Image(systemName: "ticket")
                    .foregroundStyle(Theme.primary)
            }
            .accessibilityIdentifier("economy.dayPass.status")
            Text(verbatim: card.explanation(in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let unavailable = card.unavailableText(in: language) {
                Text(verbatim: unavailable)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            } else {
                Stepper(value: price, in: DayPassCard.priceRange, step: DayPassCard.priceStep) {
                    Text(verbatim: language.text("Price \(Money(price.wrappedValue).centsText)", "售價 \(Money(price.wrappedValue).centsText)"))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("economy.dayPass.price")
                Button {
                    session.setDayPass(Money(price.wrappedValue))
                } label: {
                    Text(verbatim: DayPassCard.sellText(Money(price.wrappedValue), in: language))
                }
                .disabled(card.price == Money(price.wrappedValue))
                .accessibilityIdentifier("economy.dayPass.sell")
                if let today = card.todayText(in: language) {
                    Text(verbatim: today)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("economy.dayPass.today")
                }
                if card.price != nil {
                    Button(role: .destructive) {
                        session.setDayPass(nil)
                    } label: {
                        Text(verbatim: DayPassCard.stopText(in: language))
                    }
                    .accessibilityIdentifier("economy.dayPass.stop")
                }
            }
        } header: {
            Text(verbatim: card.title(in: language))
        }
    }

    private var lastHourSection: some View {
        Section("Last hour") {
            let totals = session.world.recentLedgerTotals()
            if totals.isEmpty {
                Text("Nothing settled in the last hour.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(totals, id: \.item) { total in
                LabeledContent(total.item.displayName(in: session.language), value: total.amountText)
                    .monospacedDigit()
            }
            // Decision 155: the tons made and carried, once there is any.
            if let freight = session.world.freightTotalsText(in: session.language) {
                Text(verbatim: freight)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Which statement the report shows (Phase 7a): the reference's
    /// income and cash flow statements, switched as its
    /// `flow-dashboard-statement-switch` does.
    private enum Statement: Hashable, CaseIterable {
        case income, cashFlow
    }

    private var reportSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(FinancePeriod.allCases, id: \.self) { period in
                    Text(period.displayName(in: session.language)).tag(period)
                }
            }
            .pickerStyle(.segmented)
            Picker(selection: $statement) {
                Text(verbatim: session.language.text("Income", "損益表")).tag(Statement.income)
                Text(verbatim: session.language.text("Cash flows", "現金流量表")).tag(Statement.cashFlow)
            } label: {
                Text(verbatim: session.language.text("Statement", "報表類型"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("economy.statement")
            let report = session.world.financeReport(period)
            // The cash now ends this period so far; the last one ended with
            // what this one started with.
            let cash = session.world.economy.balance
            StatementGrid(
                rows: statement == .income
                    ? report.current.incomeStatementRows(previous: report.previous, in: session.language)
                    : report.current.cashFlowRows(
                        previous: report.previous,
                        // Decision 200: no cash in hand to show with
                        // unlimited funds.
                        closingCash: session.world.economy.unlimitedFunds ? nil : (cash, cash - report.current.netCashFlow),
                        in: session.language
                    ),
                currentTitle: session.language.text("This", "本期"), previousTitle: session.language.text("Last", "上期")
            )
        } header: {
            Text("Report")
        } footer: {
            // Decision 131: only a managed company's midnights charge the tax.
            if session.world.accounts.mode == .management {
                Text(verbatim: CompanyAccounts.taxTermsText(in: session.language))
            }
        }
    }

    /// Phase 7a: the balance sheet now, beside the last year's closing.
    private var balanceSheetSection: some View {
        Section {
            let sheet = session.world.balanceSheet()
            let closed = session.world.lastClosedYear
            StatementGrid(
                rows: sheet.rows(previous: closed?.closing, in: session.language),
                currentTitle: session.language.text("Now", "目前"),
                previousTitle: closed.map { session.language.text("\($0.yearText(in: session.language)) end", "\($0.yearText(in: session.language))底") }
            )
            .accessibilityIdentifier("economy.balanceSheet")
        } header: {
            Text(verbatim: session.language.text("Balance sheet", "資產負債表"))
        } footer: {
            let sheet = session.world.balanceSheet()
            let lines = AssetClass.allCases.map { sheet.depreciationText(of: $0, in: session.language) }
                + [session.world.unrecordedAssetsText(in: session.language)].compactMap { $0 }
            Text(verbatim: lines.joined(separator: "\n"))
        }
    }

    /// Phase 7a: every closed year kept, the latest first, each opening its
    /// year-end report.
    private var closedYearsSection: some View {
        Section {
            let years = session.world.accounts.years
            if years.isEmpty {
                Text(verbatim: session.language.text("A year closes every 360 days.", "每 360 天結算一次年度決算。"))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(years.reversed(), id: \.year) { year in
                NavigationLink {
                    YearEndReport(statement: year, previous: years.last { $0.year == year.year - 1 }, language: session.language,
                                  unlimitedFunds: session.world.economy.unlimitedFunds)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: year.titleText(in: session.language))
                            .fontWeight(.semibold)
                        Text(verbatim: year.headlineText(in: session.language))
                            .font(.caption)
                            .foregroundStyle(year.income.netProfit < .zero ? Theme.error : Theme.textSecondary)
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
        } header: {
            Text(verbatim: session.language.text("Year-end closings", "年度決算"))
        }
    }

    private var ledgerSection: some View {
        Section("Ledger") {
            let entries = session.world.recentLedgerEntries()
            if entries.isEmpty {
                Text("No rows yet.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.kind.displayName(in: session.language))
                            .fontWeight(.semibold)
                        Spacer()
                        Text(entry.amountText)
                            .foregroundStyle(entry.amount < .zero ? Theme.error : Theme.success)
                    }
                    Text(entry.time.displayText(in: session.language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.footnote)
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
