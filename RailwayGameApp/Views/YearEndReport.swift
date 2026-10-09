import GameCore
import GamePresentation
import SwiftUI

/// A statement's rows (Phase 7a, decision 85) in a grid: the title, this
/// period and, when there is one to compare with, the last. Sections are
/// headings, subtotals and the total stand out, losses are red. The rows
/// and their words come from GamePresentation.
struct StatementGrid: View {
    let rows: [StatementRow]
    let currentTitle: String
    let previousTitle: String?

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text(verbatim: "").gridColumnAlignment(.leading)
                Text(verbatim: currentTitle).fontWeight(.semibold)
                if let previousTitle {
                    Text(verbatim: previousTitle).fontWeight(.semibold)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.style == .section {
                    GridRow {
                        Text(verbatim: row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)
                            .gridCellColumns(previousTitle == nil ? 2 : 3)
                            .gridCellAnchor(.leading)
                    }
                } else {
                    GridRow {
                        Text(verbatim: row.title).gridColumnAlignment(.leading)
                        amount(row.current, row.style)
                        if previousTitle != nil {
                            amount(row.previous, row.style)
                        }
                    }
                    .fontWeight(row.style == .item ? .regular : .semibold)
                }
            }
        }
        .font(.footnote)
        .monospacedDigit()
    }

    private func amount(_ money: Money?, _ style: StatementRow.Style) -> some View {
        Text(verbatim: money?.moneyText ?? "—")
            .foregroundStyle(style != .item && (money ?? .zero) < .zero ? Theme.error : Theme.textPrimary)
    }
}

/// The year-end report (Phase 7a, decision 85): a closed year's income
/// statement, cash flows and closing balance sheet, each beside the year
/// before when it closed too. Shown when a year closes while playing, and
/// from the economy panel's closed years.
struct YearEndReport: View {
    let statement: AnnualStatement
    /// The year before, if it closed and is kept.
    let previous: AnnualStatement?
    let language: DisplayLanguage

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: statement.headlineText(in: language))
                        .font(.headline)
                        .foregroundStyle(statement.income.netProfit < .zero ? Theme.error : Theme.textPrimary)
                        .monospacedDigit()
                        .accessibilityIdentifier("yearEnd.headline")
                }
                .padding(.vertical, 4)
            }
            Section {
                StatementGrid(rows: statement.income.incomeStatementRows(previous: previous?.income, in: language),
                              currentTitle: statement.yearText(in: language), previousTitle: previous?.yearText(in: language))
            } header: {
                Text(verbatim: language.text("Income statement", "損益表"))
            }
            Section {
                StatementGrid(rows: statement.income.cashFlowRows(
                                  previous: previous?.income,
                                  closingCash: (statement.closing.cash, previous?.closing.cash),
                                  in: language
                              ),
                              currentTitle: statement.yearText(in: language), previousTitle: previous?.yearText(in: language))
            } header: {
                Text(verbatim: language.text("Cash flows", "現金流量表"))
            }
            Section {
                StatementGrid(rows: statement.closing.rows(previous: previous?.closing, in: language),
                              currentTitle: statement.yearText(in: language), previousTitle: previous?.yearText(in: language))
            } header: {
                Text(verbatim: language.text("Balance sheet at year end", "年底資產負債表"))
            } footer: {
                Text(verbatim: AssetClass.allCases.map { statement.closing.depreciationText(of: $0, in: language) }.joined(separator: "\n"))
            }
        }
        .navigationTitle(Text(verbatim: statement.titleText(in: language)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The year-end report on its own, as the sheet that opens when a year
/// closes while playing.
struct YearEndSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let statement = session.yearEndStatement {
                    let years = session.world.accounts.years
                    YearEndReport(statement: statement, previous: years.last { $0.year == statement.year - 1 }, language: session.language)
                } else {
                    Text(verbatim: session.language.text("No year has closed yet.", "還沒有完成的年度決算。"))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: session.language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("yearEnd.done")
                }
            }
        }
    }
}
