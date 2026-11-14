import GameCore
import GamePresentation
import SwiftUI

/// A statement's rows (Phase 7a, decision 85) in a grid: the title, this
/// period and, when there is one to compare with, the last. Sections are
/// headings, subtotals and the total stand out, losses are red. The rows
/// and their words come from GamePresentation.
///
/// An amount never breaks over two lines (a player's report from an iPhone
/// held sideways: "$ 3,269,8" above "58"). Where the titles and the full
/// amounts do not fit on one line, each title goes above its amounts; where
/// even the full amounts do not fit beside each other, they are shown short
/// (``StatementRow/amountText(_:short:in:)``).
struct StatementGrid: View {
    let rows: [StatementRow]
    let currentTitle: String
    let previousTitle: String?
    /// For the short amounts (decision 523, continued: 萬 in Chinese).
    let language: DisplayLanguage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            besideGrid
            stackedGrid(short: false)
            stackedGrid(short: true)
        }
        .font(.footnote)
        .monospacedDigit()
    }

    // The rows are built in sendable closures, not main-actor code
    // (CRASHSWEEP): the grids stand in a ViewThatFits, whose layouts
    // SwiftUI's asynchronous renderer may measure, and build, off the main
    // thread, where a main-actor ForEach closure stops the app (CRASH101).

    /// Each title above its amounts, the amounts at the trailing edge.
    private func stackedGrid(short: Bool) -> some View {
        let hasPrevious = previousTitle != nil
        let language = language
        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Color.clear.frame(width: 0, height: 0)
                Text(verbatim: currentTitle).fontWeight(.semibold)
                if let previousTitle {
                    Text(verbatim: previousTitle).fontWeight(.semibold)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { @Sendable _, row in
                StatementStackedRows(row: row, hasPrevious: hasPrevious, short: short, language: language)
            }
        }
    }

    /// The titles beside their amounts, all on one line.
    private var besideGrid: some View {
        let hasPrevious = previousTitle != nil
        let language = language
        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text(verbatim: "").gridColumnAlignment(.leading)
                Text(verbatim: currentTitle).fontWeight(.semibold)
                if let previousTitle {
                    Text(verbatim: previousTitle).fontWeight(.semibold)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { @Sendable _, row in
                StatementBesideRow(row: row, hasPrevious: hasPrevious, language: language)
            }
        }
    }
}

/// One of ``StatementGrid``'s amounts on one line, red for a loss below
/// a heading.
private struct StatementAmount: View {
    let money: Money?
    let style: StatementRow.Style
    let short: Bool
    let language: DisplayLanguage

    var body: some View {
        Text(verbatim: StatementRow.amountText(money, short: short, in: language))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(style != .item && (money ?? .zero) < .zero ? Theme.error : Theme.textPrimary)
    }
}

/// A row of ``StatementGrid``'s stacked layout: its title on a line across
/// the grid, then its amounts.
private struct StatementStackedRows: View {
    let row: StatementRow
    let hasPrevious: Bool
    let short: Bool
    let language: DisplayLanguage

    /// The amount columns: this period's and, when there is one, the last.
    private var amountColumns: Int { hasPrevious ? 2 : 1 }

    var body: some View {
        if row.style == .section {
            GridRow {
                stackedTitle(row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
                    .gridCellColumns(amountColumns + 1)
            }
        } else {
            GridRow {
                stackedTitle(row.title)
                    .padding(.top, 4)
                    .padding(.leading, row.style == .note ? 12 : 0)
                    .foregroundStyle(row.style == .note ? Theme.textSecondary : Theme.textPrimary)
                    .gridCellColumns(amountColumns + 1)
            }
            .fontWeight(row.style == .item || row.style == .note ? .regular : .semibold)
            GridRow {
                Spacer(minLength: 0)
                StatementAmount(money: row.current, style: row.style, short: short, language: language)
                if hasPrevious {
                    StatementAmount(money: row.previous, style: row.style, short: short, language: language)
                }
            }
            .fontWeight(row.style == .item || row.style == .note ? .regular : .semibold)
        }
    }

    /// A title across the stacked grid: it wraps to the width there is, and
    /// does not count when the layouts are measured, so a long title does
    /// not make the amounts short.
    private func stackedTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of ``StatementGrid``'s layout with the titles beside their
/// amounts.
private struct StatementBesideRow: View {
    let row: StatementRow
    let hasPrevious: Bool
    let language: DisplayLanguage

    var body: some View {
        if row.style == .section {
            GridRow {
                Text(verbatim: row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
                    .gridCellColumns(hasPrevious ? 3 : 2)
                    .gridCellAnchor(.leading)
            }
        } else {
            GridRow {
                Text(verbatim: row.title)
                    .lineLimit(1)
                    .padding(.leading, row.style == .note ? 12 : 0)
                    .foregroundStyle(row.style == .note ? Theme.textSecondary : Theme.textPrimary)
                    .gridColumnAlignment(.leading)
                StatementAmount(money: row.current, style: row.style, short: false, language: language)
                if hasPrevious {
                    StatementAmount(money: row.previous, style: row.style, short: false, language: language)
                }
            }
            .fontWeight(row.style == .item || row.style == .note ? .regular : .semibold)
        }
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
    /// Decision 200: the company has unlimited funds, so there is no cash
    /// in hand to show.
    var unlimitedFunds = false
    /// Decision 751: the year's grades, shown above its statements.
    var appraisal: YearEndAppraisal?

    var body: some View {
        Form {
            if let appraisal {
                YearEndAppraisalSection(appraisal: appraisal, language: language)
            }
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
                              currentTitle: statement.yearText(in: language), previousTitle: previous?.yearText(in: language), language: language)
            } header: {
                Text(verbatim: language.text("Income statement", "損益表"))
            }
            Section {
                StatementGrid(rows: statement.income.cashFlowRows(
                                  previous: previous?.income,
                                  closingCash: unlimitedFunds ? nil : (statement.closing.cash, previous?.closing.cash),
                                  in: language
                              ),
                              currentTitle: statement.yearText(in: language), previousTitle: previous?.yearText(in: language), language: language)
            } header: {
                Text(verbatim: language.text("Cash flows", "現金流量表"))
            }
            Section {
                StatementGrid(rows: statement.closing.rows(previous: previous?.closing, in: language),
                              currentTitle: statement.yearText(in: language), previousTitle: previous?.yearText(in: language), language: language)
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

/// Decision 751: the year-end appraisal, five counts graded A, B or C,
/// with the taxes the year left owing under the annual taxes.
struct YearEndAppraisalSection: View {
    let appraisal: YearEndAppraisal
    let language: DisplayLanguage

    var body: some View {
        Section {
            ForEach(appraisal.rows, id: \.item) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    AppraisalGradeMark(grade: row.grade)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.item.title(in: language))
                            .fontWeight(.semibold)
                        Text(verbatim: row.detail(in: language))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("yearEnd.appraisal.row")
            }
            ForEach(appraisal.taxesDue, id: \.dueDay) { due in
                Label {
                    Text(verbatim: appraisal.taxDueText(due, in: language))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Theme.warning)
                }
                .font(.footnote)
            }
        } header: {
            Text(verbatim: appraisal.titleText(in: language))
        } footer: {
            Text(verbatim: YearEndAppraisal.footnote(in: language))
        }
        .accessibilityIdentifier("yearEnd.appraisal")
    }
}

/// A grade's letter in a tinted square: the letter says it, the colour
/// only helps (A green, B amber, C red); "—" when not graded.
private struct AppraisalGradeMark: View {
    let grade: AppraisalGrade?

    var body: some View {
        Text(verbatim: grade?.letter ?? "—")
            .font(.headline.weight(.bold))
            .foregroundStyle(color)
            .frame(minWidth: 32, minHeight: 32)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var color: Color {
        switch grade {
        case .a?: Theme.success
        case .b?: Theme.warning
        case .c?: Theme.error
        case nil: Theme.textSecondary
        }
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
                    let previous = years.last { $0.year == statement.year - 1 }
                    YearEndReport(statement: statement, previous: previous, language: session.language,
                                  unlimitedFunds: session.world.economy.unlimitedFunds,
                                  appraisal: YearEndAppraisal(statement: statement, previous: previous, world: session.world))
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
