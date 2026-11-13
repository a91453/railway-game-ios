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
    /// The flat fare on the stepper, in cents; until the player steps it,
    /// the fare in force (``FareRules/flatStart(baseline:)``, decision 643).
    @State private var flatFareChoice: Int64?
    /// The distance steps' first fare, in cents; `nil` until the panel
    /// takes the world's (``FareRules/bandStart(baseline:)``).
    @State private var bandStart: Int64?
    /// The day pass's price on the stepper, in cents; `nil` until the
    /// player moves it (decision 324).
    @State private var dayPassPrice: Int64?
    @State private var confirmsFreePlay = false
    /// Whether the reports under the "Today" card, the loan and the fares
    /// show: `nil` until the player chooses, when a game of simple rules
    /// shows only those.
    @State private var showsReports: Bool?

    var body: some View {
        NavigationStack {
            Form {
                // Today's money in three lines first.
                let today = session.world.todayAccount()
                if let today {
                    todaySection(today)
                }
                if session.world.scenario != nil {
                    goalsSection
                }
                // Decision 336: the loan and the fares under "Today", never
                // folded away, so the insolvency bubble lands on Borrow.
                // Decision 200: with unlimited funds there is nothing to
                // borrow for, and no cash to sheet.
                if !session.world.economy.unlimitedFunds {
                    loanSection
                }
                // Decision 715: the term loans beside it.
                if session.world.showsTermLoans {
                    termLoanSection
                }
                faresSection
                dayPassSection
                punctualitySection
                fleetSection
                if today == nil || showsAllReports {
                    trendSection
                    balanceSection
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

    /// Decision 258's simple rules show only the "Today" card, the loan
    /// and the fares at first (decision 336); realistic games show every
    /// report, as before.
    private var showsAllReports: Bool {
        showsReports ?? (NewGameRules(of: session.world) == .realistic)
    }

    // MARK: - Sections

    /// Today's fares, running costs and result, to the last full hour
    /// (``TodayAccount``).
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

    /// Decision 524, later: every passenger line's trips on time over the
    /// last seven settled days, beside Taiwan Railway's past year, the
    /// same figure the line card shows for one line. Nothing below ten
    /// trips or without realistic operation.
    @ViewBuilder
    private var punctualitySection: some View {
        if let weekly = session.world.companyWeeklyPunctuality() {
            Section {
                Text(verbatim: weekly.companyText(in: session.language))
                    .monospacedDigit()
                    .accessibilityIdentifier("economy.weeklyPunctuality")
            }
        }
    }

    /// Decision 336, later: the trains and their sale, from
    /// the company's money too, not only behind Build → Train.
    private var fleetSection: some View {
        Section {
            Button {
                screen.panel = .fleet
            } label: {
                Label {
                    Text(verbatim: session.language.text("Fleet Overview…", "車隊總覽…"))
                } icon: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                }
            }
            .accessibilityIdentifier("economy.fleet")
            // UI audit 2026-10-30: the last month's report again, which
            // otherwise only opened once, as the month closed.
            if let report = session.lastMonthReport {
                Button {
                    screen.panel = .monthEnd
                } label: {
                    Label {
                        Text(verbatim: session.language.text(
                            "Month \(report.month + 1) Report…", "第 \(report.month + 1) 個月月報…"
                        ))
                    } icon: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
                .accessibilityIdentifier("economy.monthlyReport")
            }
        }
    }

    /// Shows or hides the reports under the "Today" card.
    private var reportsToggleSection: some View {
        Section {
            Button {
                showsReports = !showsAllReports
            } label: {
                Text(verbatim: showsAllReports
                     ? session.language.text("Hide the other reports and settings", "收起其他報表與設定")
                     : session.language.text("More reports and settings", "更多報表與設定"))
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
            // Decision 471: the charts drawn again only when what they are
            // made from changes, not at every tick.
            let source = FinanceHistory.Source(trendRange, world: session.world)
            let language = session.language
            TickStable(StableKey(source, language)) {
                FinanceTrendCharts(history: source.history(), language: language)
            }
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
                    // Decision 200: "∞" with unlimited funds. Decision 523,
                    // continued: in 萬 or 億 in Chinese, every dollar under it.
                    Text(verbatim: session.world.economy.cashText(in: session.language))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(session.world.economy.showsInTheRed ? Theme.error : Theme.textPrimary)
                        .monospacedDigit()
                    // Decision 523: a rough US dollar figure under the
                    // balance, English only.
                    if !session.world.economy.unlimitedFunds,
                       let reference = session.world.economy.balance.usDollarReferenceText(in: session.language) {
                        Text(verbatim: reference)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                            .accessibilityIdentifier("economy.balance.usd")
                    }
                    if !session.world.economy.unlimitedFunds,
                       session.world.economy.balance.compactText(in: session.language) != session.world.economy.balance.moneyText {
                        Text(verbatim: session.world.economy.balance.moneyText)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                            .accessibilityIdentifier("economy.balance.exact")
                    }
                }
            }
            .padding(.vertical, 4)
            // Decision 523: the currency, said once in English.
            if let note = Money.currencyNoteText(in: session.language) {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("economy.currencyNote")
            }

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
                    Text(verbatim: GameSession.freePlaySwitchText(in: session.language))
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
            // Decision 374: what the next step costs, before it is borrowed.
            if let preview = session.world.loanPreview() {
                loanPreviewText(preview)
            }
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

    /// Decision 715: how many term loans there are and what they come to,
    /// how much more the bank lends, and the way to the contracts and the
    /// form that signs one (``TermLoanScreen``).
    private var termLoanSection: some View {
        let language = session.language
        let board = session.world.termLoanBoard()
        return Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: board.summaryText(in: language))
                if let next = board.nextDueText(in: language) {
                    Text(verbatim: next)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("economy.termLoans")
            Text(verbatim: board.creditText(in: language))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("economy.termLoans.credit")
            // Free play with none signed has nothing to open.
            if board.blocked != .freePlay || !board.contracts.isEmpty {
                NavigationLink {
                    TermLoanScreen(session: session)
                } label: {
                    Text(verbatim: language.text("Contracts and Borrowing", "合約與借入"))
                }
                .accessibilityIdentifier("economy.termLoans.open")
            }
        } header: {
            Text(verbatim: language.text("Term loans", "定期貸款"))
        }
    }

    /// Decision 374: the interest the next step adds each day, what it
    /// comes to over a month and a year, and what the company would keep
    /// a day with it, in red when that is a loss.
    private func loanPreviewText(_ preview: LoanPreview) -> some View {
        let language = session.language
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: preview.paymentText(in: language))
                .font(.subheadline)
            Text(verbatim: preview.totalText(in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let result = preview.resultText(in: language) {
                Text(verbatim: result)
                    .font(.caption)
                    .foregroundStyle((preview.dailyResultAfter ?? .zero) < .zero ? Theme.error : Theme.textSecondary)
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("economy.loanPreview")
    }

    /// Decision 374: how many riders the fare on the stepper would keep,
    /// against now.
    @ViewBuilder
    private func fareDemandText(_ rules: FareRules, id: String) -> some View {
        if let hint = session.world.fareDemandHint(for: rules) {
            Text(verbatim: hint.text(in: session.language))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(hint.isWarning ? Theme.warning : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
        }
    }

    private var faresSection: some View {
        Section {
            LabeledContent("Rules", value: accounts.effectiveFareRules.displayText(in: session.language))
            let flatFare = flatFareChoice ?? accounts.effectiveFareRules.flatStart(baseline: accounts.fareBaseline)
            Stepper(value: Binding(get: { flatFare }, set: { flatFareChoice = $0 }), in: FareRules.flatFareRange, step: 25) {
                Text("Flat fare \(Money(flatFare).centsText)")
                    .monospacedDigit()
            }
            fareDemandText(.flat(Money(flatFare)), id: "economy.flatFareDemand")
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
            // Decision 663: what high-speed trips pay instead.
            if let highSpeed = session.world.highSpeedFareText(in: language) {
                Text(verbatim: highSpeed)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("economy.highSpeedFares")
            }
            fareDemandText(.distance(bands), id: "economy.bandDemand")
            Button {
                session.setFareRules(.distance(bands))
            } label: {
                Text(verbatim: language.text("Charge by distance from \(bands[0].fare.centsText)", "改收階梯票價（\(bands[0].fare.centsText) 起）"))
            }
            .accessibilityIdentifier("economy.chargeByDistance")
        } header: {
            Text("Fares")
        } footer: {
            if accounts.mode == .management {
                Text(verbatim: FareDemandHint.usualFareText(accounts.fareBaseline, in: session.language))
            }
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
                Stepper(value: price, in: DayPassCard.priceRange, step: Int(DayPassCard.priceStep)) {
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
                currentTitle: session.language.text("This", "本期"), previousTitle: session.language.text("Last", "上期"),
                language: session.language
            )
            // Decision 480: the period's income and costs by kind.
            FinanceCompositionChart(
                composition: FinanceComposition(report.current, hasRecords: !accounts.days.isEmpty), language: session.language
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
                previousTitle: closed.map { session.language.text("\($0.yearText(in: session.language)) end", "\($0.yearText(in: session.language))底") },
                language: session.language
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
            let rows = session.world.recentLedgerRows()
            if rows.isEmpty {
                Text("No rows yet.")
                    .foregroundStyle(Theme.textSecondary)
            }
            // Decision 471: each row keeps its ID as newer rows come in above it.
            ForEach(rows) { row in
                let entry = row.entry
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

/// Decision 715: the term loans, pushed from the economy panel. The form
/// on top signs one: an amount in steps of ``CompanyAccounts/loanStep`` up
/// to the most the bank lends, a term of 1 to 10 years, the bank's quote
/// for the two, and a question before it is signed. Under it every
/// contract, the soonest due first, with what paying it back today costs
/// and a question before that too.
///
/// Everything shown is read from `session.world` when the view is drawn
/// (``TermLoanBoard``, GameCore's own quotes), and both buttons call a
/// `GameSession` method that applies one `GameWorld` command.
private struct TermLoanScreen: View {
    let session: GameSession
    /// The amount on the stepper; `nil` until the player moves it.
    @State private var principalChoice: Money?
    @State private var years: Int64 = 1
    @State private var confirmsSigning = false
    /// The contract the player asked to pay back, while the question shows.
    @State private var repaying: TermLoanBoard.Contract?

    var body: some View {
        let language = session.language
        let board = session.world.termLoanBoard()
        Form {
            borrowSection(board)
            Section {
                if board.contracts.isEmpty {
                    Text(verbatim: language.text("No term loans yet.", "還沒有定期貸款。"))
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(board.contracts) { contract in
                    TermLoanRow(contract: contract, language: language) {
                        repaying = contract
                    }
                }
            } header: {
                Text(verbatim: language.text("Contracts", "合約"))
            } footer: {
                if !board.contracts.isEmpty {
                    Text(verbatim: board.summaryText(in: language))
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle(Text(verbatim: language.text("Term Loans", "定期貸款")))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text(verbatim: language.text("Repay this term loan today?", "今天提前還這筆定期貸款？")),
            isPresented: Binding(get: { repaying != nil }, set: { if !$0 { repaying = nil } }),
            titleVisibility: .visible, presenting: repaying
        ) { contract in
            Button {
                session.repayTermLoanEarly(contract.id)
            } label: {
                Text(verbatim: language.text("Pay \(contract.repayment.total.moneyText)", "付 \(contract.repayment.total.moneyText)"))
            }
            .accessibilityIdentifier("termLoan.repay.confirm")
        } message: { contract in
            Text(verbatim: contract.repaymentText(in: language))
        }
    }

    /// The form, or why the bank signs nothing now.
    @ViewBuilder
    private func borrowSection(_ board: TermLoanBoard) -> some View {
        let language = session.language
        Section {
            Text(verbatim: board.creditText(in: language))
                .monospacedDigit()
                .foregroundStyle(board.blocked == nil ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("termLoan.credit")
            if let principal = board.principal(for: principalChoice), let choices = board.principalChoices {
                let step = CompanyAccounts.loanStep.amount
                let amount = Binding(get: { principal.amount }, set: { principalChoice = Money($0) })
                Stepper(value: amount, in: choices, step: Int64.Stride(step)) {
                    Text(verbatim: language.text("Amount \(principal.moneyText)", "金額 \(principal.moneyText)"))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("termLoan.amount")
                // The stepper goes a step at a time; the slider crosses a
                // large credit in one drag.
                if choices.upperBound >= 4 * step {
                    Slider(
                        value: Binding(get: { Double(principal.amount / step) }, set: { principalChoice = Money(Int64($0) * step) }),
                        in: 1...Double(choices.upperBound / step), step: 1
                    ) {
                        Text(verbatim: language.text("Amount", "金額"))
                    }
                    .accessibilityValue(Text(verbatim: principal.moneyText))
                    .accessibilityIdentifier("termLoan.amountSlider")
                }
                Stepper(value: $years, in: TermLoanBoard.yearChoices) {
                    Text(verbatim: language.text(
                        "Term \(TermLoanBoard.yearsText(years, in: language))", "年期 \(TermLoanBoard.yearsText(years, in: language))"
                    ))
                    .monospacedDigit()
                }
                .accessibilityIdentifier("termLoan.years")
                if let quote = try? session.world.termLoanQuote(principal: principal, years: years) {
                    let rows = quote.rows(in: language)
                    ForEach(rows, id: \.title) { row in
                        LabeledContent {
                            Text(verbatim: row.value)
                                .foregroundStyle(Theme.textPrimary)
                        } label: {
                            Text(verbatim: row.title)
                        }
                        .font(row.title == rows.last?.title ? .body.bold() : .body)
                        .monospacedDigit()
                    }
                    Button {
                        confirmsSigning = true
                    } label: {
                        Text(verbatim: language.text("Borrow \(principal.moneyText)…", "借入 \(principal.moneyText)…"))
                    }
                    .accessibilityIdentifier("termLoan.sign")
                    .confirmationDialog(
                        Text(verbatim: language.text(
                            "Sign a term loan for \(TermLoanBoard.yearsText(years, in: language))?",
                            "簽 \(TermLoanBoard.yearsText(years, in: language))的定期貸款？"
                        )),
                        isPresented: $confirmsSigning, titleVisibility: .visible
                    ) {
                        Button {
                            session.takeTermLoan(principal: principal, years: years)
                            principalChoice = nil
                        } label: {
                            Text(verbatim: language.text("Sign and Borrow \(principal.moneyText)", "簽約，借入 \(principal.moneyText)"))
                        }
                        .accessibilityIdentifier("termLoan.sign.confirm")
                    } message: {
                        Text(verbatim: quote.confirmText(in: language))
                    }
                } else {
                    Text(verbatim: GameError.invalidTermLoan.playerMessage(in: language))
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }
        } header: {
            Text(verbatim: language.text("Borrow", "借入"))
        } footer: {
            Text(verbatim: TermLoanBoard.termsText(in: language))
        }
    }
}

/// One term loan in ``TermLoanScreen``: what was borrowed and what is paid
/// when it falls due, its term, rate and due day, what paying it back
/// today costs, and the button that asks to. The button is off, with the
/// reason above it, when the cash in hand does not pay it.
private struct TermLoanRow: View {
    let contract: TermLoanBoard.Contract
    let language: DisplayLanguage
    let repay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    principal
                    Spacer(minLength: 12)
                    due
                }
                VStack(alignment: .leading, spacing: 2) {
                    principal
                    due
                }
            }
            Text(verbatim: contract.loan.termsText(in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: contract.repaymentText(in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let shortfall = contract.shortfallText(in: language) {
                Label {
                    Text(verbatim: shortfall)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .accessibilityIdentifier("termLoan.shortfall.\(contract.id)")
            }
            Button(action: repay) {
                Text(verbatim: language.text("Repay Early…", "提前還款…"))
            }
            .buttonStyle(.borderless)
            .disabled(!contract.canRepay)
            .frame(minHeight: 44)
            .accessibilityIdentifier("termLoan.repay.\(contract.id)")
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }

    private var principal: some View {
        Text(verbatim: contract.loan.principal.moneyText)
            .font(.body.bold())
    }

    private var due: some View {
        Text(verbatim: contract.loan.dueTotalText(in: language))
            .font(.subheadline)
    }
}
