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
    @State private var flatFare: Int64 = 500
    @State private var confirmsFreePlay = false

    var body: some View {
        NavigationStack {
            Form {
                balanceSection
                if session.world.scenario != nil {
                    goalsSection
                }
                loanSection
                faresSection
                lastHourSection
                reportSection
                balanceSheetSection
                closedYearsSection
                ledgerSection
            }
            .navigationTitle("Economy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        screen.panel = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session)
            }
        }
    }

    private var accounts: CompanyAccounts {
        session.world.accounts
    }

    // MARK: - Sections

    private var balanceSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((session.world.economy.balance < .zero ? Theme.error : Theme.success).opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "banknote.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(session.world.economy.balance < .zero ? Theme.error : Theme.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(session.world.economy.balance.moneyText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(session.world.economy.balance < .zero ? Theme.error : Theme.textPrimary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)

            LabeledContent("Mode", value: accounts.mode.displayName(in: session.language))
            // Free play cannot become managed again (decision 46), so the
            // switch goes one way, after a confirmation.
            if accounts.mode == .management {
                Button("Switch to Free Play", role: .destructive) {
                    confirmsFreePlay = true
                }
                .confirmationDialog("Switch to Free Play", isPresented: $confirmsFreePlay, titleVisibility: .visible) {
                    Button("Switch to Free Play", role: .destructive) {
                        session.setEconomyMode(.free)
                    }
                } message: {
                    Text("Free play has no fares or running costs, and you set each station's ridership. It cannot become a managed company again.")
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
            Button("Charge by distance (standard steps)") {
                session.setFareRules(.distance(FareRules.standardBands(for: accounts.fareBaseline)))
            }
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
                        closingCash: (cash, cash - report.current.netCashFlow),
                        in: session.language
                    ),
                currentTitle: session.language.text("This", "本期"), previousTitle: session.language.text("Last", "上期")
            )
        } header: {
            Text("Report")
        } footer: {
            // Decision 131.
            Text(verbatim: CompanyAccounts.taxTermsText(in: session.language))
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
                    YearEndReport(statement: year, previous: years.last { $0.year == year.year - 1 }, language: session.language)
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
