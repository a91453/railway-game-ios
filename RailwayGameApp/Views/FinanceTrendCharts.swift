import Charts
import GameCore
import GamePresentation
import SwiftUI

/// The economy panel's trend charts (decision 176): revenue by source
/// against cost, net profit, and passengers, one bucket per bar. Small and
/// self-contained so the per-line operating report can use it later: it is
/// given a ``FinanceHistory`` and draws it; the numbers and the sentences
/// are `GamePresentation`'s (and tested there).
///
/// Colours follow the dataviz palette (categorical slots 1 to 3 for the
/// revenue sources, the app's success and error colours for profit and
/// loss, primary ink for the cost line), each with a dark variant. Colour
/// is never the only cue: the sources have a legend, a loss sits below the
/// zero rule, and touching a bar reads its numbers out in words.
struct FinanceTrendCharts: View {
    let history: FinanceHistory
    let language: DisplayLanguage
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: selectedPoint.map { $0.detailText(for: history.range, in: language) } ?? history.summaryText(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("economy.trend.summary")
            if history.isEmpty {
                EmptyView()
            } else {
                chartTitle(language.text("Revenue and cost", "收入與成本"))
                revenueChart
                chartTitle(language.text("Net profit", "淨利"))
                profitChart
                if history.hasTrips {
                    chartTitle(language.text("Passengers", "旅客數"))
                    tripsChart
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("economy.trend")
    }

    // MARK: - Data

    private var selectedPoint: FinanceTrendPoint? {
        guard let selected else { return nil }
        return history.points.first { key($0) == selected }
    }

    /// The x value of a bucket: unique, and short enough to label an axis
    /// (the day or year it starts on).
    private func key(_ point: FinanceTrendPoint) -> String {
        point.axisKey(for: history.range)
    }

    /// About six axis labels, whatever the number of buckets.
    private var tickKeys: [String] {
        let step = max(1, history.points.count / 6)
        return history.points.enumerated().filter { $0.offset % step == 0 }.map { key($0.element) }
    }

    private func dollars(_ money: Money) -> Double {
        Double(money.amount) / 100
    }

    private struct Source: Identifiable {
        let name: String
        let color: Color
        let value: (FinanceTrendPoint) -> Money
        var id: String { name }
    }

    /// Fares first (slot 1), freight (2) and rent (3) only where there was
    /// any in the window.
    private var sources: [Source] {
        let all = [
            Source(name: language.text("Fares", "票價收入"), color: Self.blue, value: \.fareRevenue),
            Source(name: language.text("Freight", "貨運收入"), color: Self.orange, value: \.freightRevenue),
            Source(name: language.text("Rent", "物業租金"), color: Self.aqua, value: \.propertyRevenue),
        ]
        return all.enumerated().filter { index, source in
            index == 0 || history.points.contains { source.value($0) != .zero }
        }.map(\.element)
    }

    // MARK: - Charts

    private var revenueChart: some View {
        let costName = language.text("Cost", "成本")
        return Chart {
            ForEach(sources) { source in
                ForEach(history.points) { point in
                    BarMark(x: .value("Period", key(point)), y: .value(source.name, dollars(source.value(point))))
                        .foregroundStyle(by: .value("Source", source.name))
                        .opacity(selected == nil || selected == key(point) ? 1 : 0.45)
                }
            }
            ForEach(history.points) { point in
                LineMark(x: .value("Period", key(point)), y: .value(costName, dollars(point.cost)), series: .value("Series", costName))
                    .foregroundStyle(Theme.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .chartForegroundStyleScale(domain: sources.map(\.name), range: sources.map(\.color))
        .chartLegend(position: .bottom, alignment: .leading)
        .modifier(TrendAxes(ticks: tickKeys, selection: $selected))
        .frame(height: 170)
        .accessibilityLabel(Text(verbatim: language.text("Revenue and cost chart", "收入與成本圖")))
        .accessibilityValue(Text(verbatim: history.summaryText(in: language)))
        .accessibilityIdentifier("economy.trend.revenue")
    }

    private var profitChart: some View {
        Chart {
            ForEach(history.points) { point in
                BarMark(x: .value("Period", key(point)), y: .value("Net profit", dollars(point.netProfit)))
                    .foregroundStyle(point.netProfit < .zero ? Theme.error : Theme.success)
                    .opacity(selected == nil || selected == key(point) ? 1 : 0.45)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .modifier(TrendAxes(ticks: tickKeys, selection: $selected))
        .frame(height: 130)
        .accessibilityLabel(Text(verbatim: language.text("Net profit chart", "淨利圖")))
        .accessibilityValue(Text(verbatim: profitSummary))
        .accessibilityIdentifier("economy.trend.profit")
    }

    private var profitSummary: String {
        let losses = history.points.filter { $0.netProfit < .zero }.count
        let total = history.points.count
        return language.text("\(total - losses) of \(total) periods in profit", "\(total) 段期間中 \(total - losses) 段獲利")
    }

    private var tripsChart: some View {
        Chart(history.points) { point in
            if let trips = point.trips {
                LineMark(x: .value("Period", key(point)), y: .value("Passengers", trips))
                    .foregroundStyle(Self.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Period", key(point)), y: .value("Passengers", trips))
                    .foregroundStyle(Self.blue)
                    .symbolSize(selected == key(point) ? 70 : 24)
            }
        }
        .modifier(TrendAxes(ticks: tickKeys, selection: $selected))
        .frame(height: 110)
        .accessibilityLabel(Text(verbatim: language.text("Passengers chart", "旅客數圖")))
        .accessibilityValue(Text(verbatim: history.summaryText(in: language)))
        .accessibilityIdentifier("economy.trend.trips")
    }

    private func chartTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Colours (dataviz categorical slots 1 to 3, light and dark)

    private static let blue = adaptive(light: (0x2A, 0x78, 0xD6), dark: (0x39, 0x87, 0xE5))
    private static let orange = adaptive(light: (0xEB, 0x68, 0x34), dark: (0xD9, 0x59, 0x26))
    private static let aqua = adaptive(light: (0x1B, 0xAF, 0x7A), dark: (0x19, 0x9E, 0x70))

    private static func adaptive(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        func ui(_ c: (Int, Int, Int)) -> UIColor {
            UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// The charts' shared axes: a few x labels, a compact y scale with hairline
/// grid, and touch selection of a bar.
private struct TrendAxes: ViewModifier {
    let ticks: [String]
    @Binding var selection: String?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: ticks) { _ in
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.panelBorder)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: number.formatted(.number.notation(.compactName)))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
    }
}

/// A line's last days (decision 179): riders as bars with the day's profit
/// as a line over them, and a second chart of profit against the zero rule.
/// The numbers and sentences are ``LineReport``'s, tested in
/// `GamePresentation`; colours are the finance charts' (blue for riders,
/// the app's success and error colours for profit and loss).
struct LineOperatingCharts: View {
    let report: LineReport
    let language: DisplayLanguage
    @State private var selected: Int64?
    /// Not a literal: a literal here would be a string to translate.
    private static let dayAxis = "Day"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: selectedDay.map { report.dayText($0, in: language) } ?? report.summaryText(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("line.operations.summary")
            if !report.days.isEmpty {
                Text(verbatim: language.text("Riders and profit", "運量與損益"))
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ridersChart
                Text(verbatim: language.text("Profit by day", "每日損益"))
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                profitChart
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("line.operations")
    }

    private var selectedDay: LineOperatingDay? {
        guard let selected else { return nil }
        return report.days.first { $0.day == selected }
    }

    private func dollars(_ money: Money) -> Double {
        Double(money.amount) / 100
    }

    private var ridersChart: some View {
        let ridersName = language.text("Riders", "人次")
        let profitName = language.text("Profit", "損益")
        return Chart {
            ForEach(report.days) { day in
                BarMark(x: .value(Self.dayAxis, day.day + 1), y: .value(ridersName, day.riders))
                    .foregroundStyle(Color.accentColor.opacity(selected == nil || selected == day.day ? 0.9 : 0.4))
            }
            ForEach(report.days) { day in
                LineMark(x: .value(Self.dayAxis, day.day + 1), y: .value(profitName, dollars(day.profit) / profitScale), series: .value("Series", profitName))
                    .foregroundStyle(Theme.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .modifier(DayAxes(selection: $selected, offset: 1))
        .frame(height: 130)
        .accessibilityLabel(Text(verbatim: language.text("Riders and profit chart", "運量與損益圖")))
        .accessibilityValue(Text(verbatim: report.summaryText(in: language)))
        .accessibilityIdentifier("line.operations.riders")
    }

    /// The profit line shares the riders' axis: dollars scaled so the
    /// largest profit or loss reaches the tallest bar. The legend's words
    /// name it; the exact figures are in the sentence above.
    private var profitScale: Double {
        let money = report.days.map { abs(dollars($0.profit)) }.max() ?? 0
        let riders = Double(report.days.map(\.riders).max() ?? 0)
        return money > 0 && riders > 0 ? money / riders : 1
    }

    private var profitChart: some View {
        let profitName = language.text("Profit", "損益")
        return Chart {
            ForEach(report.days) { day in
                BarMark(x: .value(Self.dayAxis, day.day + 1), y: .value(profitName, dollars(day.profit)))
                    .foregroundStyle(day.profit < .zero ? Theme.error : Theme.success)
                    .opacity(selected == nil || selected == day.day ? 1 : 0.45)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .modifier(DayAxes(selection: $selected, offset: 1))
        .frame(height: 110)
        .accessibilityLabel(Text(verbatim: language.text("Profit by day chart", "每日損益圖")))
        .accessibilityValue(Text(verbatim: report.summaryText(in: language)))
        .accessibilityIdentifier("line.operations.profit")
    }
}

/// Axes of a chart whose x is a day number: a few labels, a compact y scale
/// and touch selection of a day (the selection is the day's index, one less
/// than the number shown).
private struct DayAxes: ViewModifier {
    @Binding var selection: Int64?
    let offset: Int64

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: Binding(
                get: { selection.map { $0 + offset } },
                set: { selection = $0.map { $0 - offset } }
            ))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.panelBorder)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: number.formatted(.number.notation(.compactName)))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
    }
}
