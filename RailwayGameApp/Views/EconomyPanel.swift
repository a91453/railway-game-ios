import GameCore
import GamePresentation
import SwiftUI

/// The company's money (G1c, decision 36), after the reference's economy
/// details: the balance, free play or management, the fare rules, the last
/// hour by item, the finance report for a period (this one and the last),
/// and the last rows of the ledger.
///
/// Everything shown is read from `session.world` when the view is drawn,
/// and every control calls a `GameSession` method that applies one
/// `GameWorld` command.
struct EconomyPanel: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var period: FinancePeriod = .day
    @State private var flatFare: Int64 = 500

    var body: some View {
        NavigationStack {
            Form {
                balanceSection
                faresSection
                lastHourSection
                reportSection
                ledgerSection
            }
            .navigationTitle("Economy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
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
            LabeledContent("Balance", value: session.world.economy.balance.moneyText)
                .monospacedDigit()
            Picker("Mode", selection: Binding(get: { accounts.mode }, set: { session.setEconomyMode($0) })) {
                ForEach(EconomyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName(in: session.language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(accounts.mode == .management
                ? "Passengers pay as they board. Running and upkeep are settled every hour, energy and staff every day, and the balance may go below zero."
                : "Free play: no fares and no running costs.")
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
                session.setFareRules(.distance(FareRules.standardBands))
            }
        }
    }

    private var lastHourSection: some View {
        Section("Last hour") {
            let totals = session.world.recentLedgerTotals()
            if totals.isEmpty {
                Text("Nothing settled in the last hour.")
                    .foregroundStyle(.secondary)
            }
            ForEach(totals, id: \.item) { total in
                LabeledContent(total.item.displayName(in: session.language), value: total.amountText)
                    .monospacedDigit()
            }
        }
    }

    private var reportSection: some View {
        Section("Report") {
            Picker("Period", selection: $period) {
                ForEach(FinancePeriod.allCases, id: \.self) { period in
                    Text(period.displayName(in: session.language)).tag(period)
                }
            }
            .pickerStyle(.segmented)
            let report = session.world.financeReport(period)
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text(verbatim: "").gridColumnAlignment(.leading)
                    Text("This").fontWeight(.semibold)
                    Text("Last").fontWeight(.semibold)
                }
                reportRow("Fares", report.current.fareRevenue, report.previous.fareRevenue)
                reportRow("Operating", report.current.operatingCost, report.previous.operatingCost)
                reportRow("Maintenance", report.current.maintenanceCost, report.previous.maintenanceCost)
                reportRow("Energy", report.current.energyCost, report.previous.energyCost)
                reportRow("Staff", report.current.staffCost, report.previous.staffCost)
                reportRow("Profit", report.current.operatingProfit, report.previous.operatingProfit)
            }
            .font(.footnote)
            .monospacedDigit()
        }
    }

    private func reportRow(_ title: LocalizedStringKey, _ current: Money, _ previous: Money) -> some View {
        GridRow {
            Text(title).gridColumnAlignment(.leading)
            Text(current.moneyText)
            Text(previous.moneyText)
        }
    }

    private var ledgerSection: some View {
        Section("Ledger") {
            let entries = session.world.recentLedgerEntries()
            if entries.isEmpty {
                Text("No rows yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.kind.displayName(in: session.language))
                            .fontWeight(.semibold)
                        Spacer()
                        Text(entry.amountText)
                            .foregroundStyle(entry.amount < .zero ? Color.red : Color.green)
                    }
                    Text(entry.time.displayText(in: session.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
