import GameCore
import GamePresentation
import SwiftUI

/// The monthly report (decision 175): a small card that opens when a month
/// closes: riders, fares, costs, net profit and cash against the month
/// before, the headline, the stations whose planned trips grew and fell
/// most, the new towers and the stations short of building materials.
struct MonthlyReportSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let language = session.language
        NavigationStack {
            Group {
                if let report = session.monthEndReport {
                    MonthlyReportCard(report: report, language: language)
                } else {
                    Text(verbatim: language.text("No month has closed yet.", "還沒有完成的月報。"))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("monthEnd.done")
                }
            }
        }
    }
}

private struct MonthlyReportCard: View {
    let report: MonthlyReport
    let language: DisplayLanguage

    var body: some View {
        Form {
            Section {
                Text(verbatim: report.headline.text(in: language))
                    .font(.headline)
                    .accessibilityIdentifier("monthEnd.headline")
            }
            Section {
                figure(language.text("Riders", "旅客"), report.riders) { "\(Money($0).displayText)" }
                figure(language.text("Fare revenue", "票收"), report.fares) { Money($0).moneyText }
                figure(language.text("Running costs", "成本"), report.costs, upIsGood: false) { Money($0).moneyText }
                figure(language.text("Net profit", "淨利"), report.net) { Money($0).moneyText }
                figure(language.text("Cash", "現金"), report.cash) { Money($0).moneyText }
            } header: {
                Text(verbatim: language.text("Month \(report.month + 1) against the month before", "第 \(report.month + 1) 個月，與上月相比"))
            }
            if !report.grown.isEmpty || !report.fallen.isEmpty {
                Section {
                    ForEach(report.grown, id: \.station) { change in stationRow(change) }
                    ForEach(report.fallen, id: \.station) { change in stationRow(change) }
                } header: {
                    Text(verbatim: language.text("Planned trips a day", "計畫運量（每日）"))
                }
            }
            if report.newTowers > 0 || !report.shortOfMaterials.isEmpty {
                Section {
                    if report.newTowers > 0 {
                        Label {
                            Text(verbatim: language.text("\(report.newTowers) new tall buildings (D3 or D4)", "新增 \(report.newTowers) 棟高樓（D3、D4）"))
                        } icon: {
                            Image(systemName: "building.2.fill")
                        }
                    }
                    if !report.shortOfMaterials.isEmpty {
                        Label {
                            Text(verbatim: language.text(
                                "Short of building materials: \(report.shortOfMaterials.map(\.name).joined(separator: ", "))",
                                "建材不足：\(report.shortOfMaterials.map(\.name).joined(separator: "、"))"
                            ))
                        } icon: {
                            Image(systemName: "shippingbox.fill")
                        }
                        .foregroundStyle(Theme.warning)
                    }
                } header: {
                    Text(verbatim: language.text("The towns", "城市"))
                }
            }
        }
        .navigationTitle(Text(verbatim: language.text("Monthly report", "月報")))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A line of the report: the name, the figure and its change (green
    /// where it is good, red where it is not).
    private func figure(
        _ title: String, _ figure: MonthlyFigure, upIsGood: Bool = true, text: @escaping (Int64) -> String
    ) -> some View {
        let percent = figure.percent ?? 0
        let isGood = upIsGood ? percent > 0 : percent < 0
        let isBad = upIsGood ? percent < 0 : percent > 0
        return LabeledContent {
            HStack(spacing: 8) {
                Text(verbatim: text(figure.value))
                    .monospacedDigit()
                Text(verbatim: figure.arrowText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isGood ? Theme.success : isBad ? Theme.error : Theme.textSecondary)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        } label: {
            Text(verbatim: title)
        }
    }

    private func stationRow(_ change: StationTripChange) -> some View {
        LabeledContent {
            Text(verbatim: change.delta > 0 ? "▲ +\(Money(change.delta).displayText)" : "▼ \(Money(-change.delta).displayText)")
                .monospacedDigit()
                .foregroundStyle(change.delta > 0 ? Theme.success : Theme.error)
        } label: {
            Text(verbatim: change.name)
        }
    }
}
