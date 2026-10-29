import Accessibility
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
/// Colours are the theme's chart colours (``Theme/chartBlue`` and the
/// others for the revenue sources, the app's success and error colours for
/// profit and loss, primary ink for the dashed cost line). Colour is never
/// the only cue: the sources and the cost line have a legend, a loss sits
/// below the zero rule, and touching a bar reads its numbers out in words.
/// Each chart's series, names and axis are ``ChartSpec``'s, which VoiceOver
/// also plays as an audio graph (``ChartAudioGraph``).
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
            Source(name: language.text("Fares", "票價收入"), color: Theme.chartBlue, value: \.fareRevenue),
            Source(name: language.text("Freight", "貨運收入"), color: Theme.chartOrange, value: \.freightRevenue),
            Source(name: language.text("Rent", "物業租金"), color: Theme.chartAqua, value: \.propertyRevenue),
        ]
        return all.enumerated().filter { index, source in
            index == 0 || history.points.contains { source.value($0) != .zero }
        }.map(\.element)
    }

    // MARK: - Charts

    private var revenueChart: some View {
        let spec = history.revenueChart(in: language)
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
                    .foregroundStyle(by: .value("Source", costName))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        // The cost line in the legend too (UI health check 3-7), drawn
        // dashed there as on the chart.
        .chartForegroundStyleScale(domain: spec.legendNames, range: sources.map(\.color) + [Theme.textPrimary])
        .chartLegend(position: .bottom, alignment: .leading) {
            ChartLegend(names: spec.legendNames, colors: sources.map(\.color) + [Theme.textPrimary], dashedLast: true)
        }
        .modifier(TrendAxes(ticks: tickKeys, selection: $selected))
        .frame(height: 170)
        .accessibilityLabel(Text(verbatim: language.text("Revenue and cost chart", "收入與成本圖")))
        .accessibilityValue(Text(verbatim: history.summaryText(in: language)))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
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
        .accessibilityValue(Text(verbatim: history.profitChart(in: language).summary))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: history.profitChart(in: language)))
        .accessibilityIdentifier("economy.trend.profit")
    }

    private var tripsChart: some View {
        Chart(history.points) { point in
            if let trips = point.trips {
                LineMark(x: .value("Period", key(point)), y: .value("Passengers", trips))
                    .foregroundStyle(Theme.chartBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Period", key(point)), y: .value("Passengers", trips))
                    .foregroundStyle(Theme.chartBlue)
                    .symbolSize(selected == key(point) ? 70 : 24)
            }
        }
        .modifier(TrendAxes(ticks: tickKeys, selection: $selected))
        .frame(height: 110)
        .accessibilityLabel(Text(verbatim: language.text("Passengers chart", "旅客數圖")))
        .accessibilityValue(Text(verbatim: history.summaryText(in: language)))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: history.tripsChart(in: language)))
        .accessibilityIdentifier("economy.trend.trips")
    }

    private func chartTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
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

/// A line's last days (decision 179): riders as bars, a second chart
/// of profit against the zero rule, and a third of the fullest train each
/// day against its seats (decision 478). The profit is not drawn on the riders'
/// chart: its scale is people, not dollars (UI health check 3-7). The
/// numbers and sentences are ``LineReport``'s, tested in `GamePresentation`
/// (``LineReport/ridersChart(in:)``); colours are the finance charts' (blue
/// for riders, the app's success and error colours for profit and loss).
struct LineOperatingCharts: View {
    let report: LineReport
    let language: DisplayLanguage
    @State private var selected: Int64?
    /// Not a literal: a literal here would be a string to translate.
    private static let dayAxis = "Day"
    private static let seatsAxis = "Seats"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: selectedDay.map { report.dayText($0, in: language) } ?? report.summaryText(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("line.operations.summary")
            if !report.days.isEmpty {
                Text(verbatim: report.ridersChart(in: language).title)
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ridersChart
                Text(verbatim: report.profitChart(in: language).title)
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                profitChart
                Text(verbatim: report.peakLoadChart(in: language).title)
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                peakLoadChart
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
        let spec = report.ridersChart(in: language)
        return Chart {
            ForEach(report.days) { day in
                BarMark(x: .value(Self.dayAxis, day.day + 1), y: .value(spec.series[0].name, day.riders))
                    .foregroundStyle(Theme.chartBlue.opacity(selected == nil || selected == day.day ? 1 : 0.45))
            }
        }
        .modifier(DayAxes(selection: $selected, offset: 1))
        .frame(height: 130)
        .accessibilityLabel(Text(verbatim: language.text("Riders by day chart", "每日運量圖")))
        .accessibilityValue(Text(verbatim: report.summaryText(in: language)))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
        .accessibilityIdentifier("line.operations.riders")
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
        .accessibilityChartDescriptor(ChartAudioGraph(spec: report.profitChart(in: language)))
        .accessibilityIdentifier("line.operations.profit")
    }

    /// Each day's fullest train in percent of its seats, with the seats
    /// drawn as a rule at 100% and named beside it.
    private var peakLoadChart: some View {
        let spec = report.peakLoadChart(in: language)
        return Chart {
            ForEach(report.days) { day in
                LineMark(x: .value(Self.dayAxis, day.day + 1), y: .value(spec.yTitle, Double(day.peakLoadPercent)))
                    .foregroundStyle(Theme.chartBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value(Self.dayAxis, day.day + 1), y: .value(spec.yTitle, Double(day.peakLoadPercent)))
                    .foregroundStyle(Theme.chartBlue)
                    .symbolSize(selected == day.day ? 70 : 24)
            }
            RuleMark(y: .value(Self.seatsAxis, 100.0))
                .foregroundStyle(Theme.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text(verbatim: language.text("Seats", "座位"))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
        }
        .chartYScale(domain: spec.valueRange)
        .modifier(DayAxes(selection: $selected, offset: 1))
        .frame(height: 110)
        .accessibilityLabel(Text(verbatim: spec.title))
        .accessibilityValue(Text(verbatim: spec.summary))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
        .accessibilityIdentifier("line.operations.peakLoad")
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

/// A legend of the charts' series: a swatch and a name each, the last a
/// dashed line when `dashedLast` (the revenue chart's cost).
struct ChartLegend: View {
    let names: [String]
    let colors: [Color]
    var dashedLast = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(names.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    if dashedLast, index == names.count - 1 {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 4))
                            path.addLine(to: CGPoint(x: 14, y: 4))
                        }
                        .stroke(colors[index], style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
                        .frame(width: 14, height: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(colors[index])
                            .frame(width: 10, height: 10)
                    }
                    Text(verbatim: names[index])
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// A chart (the finance charts, and decision 472's) as VoiceOver's audio graph (Apple's Audio Graphs): the
/// periods or days along x, dollars or people up y, one series each. The
/// data is the chart's ``ChartSpec``.
struct ChartAudioGraph: AXChartDescriptorRepresentable {
    let spec: ChartSpec

    func makeChartDescriptor() -> AXChartDescriptor {
        let spec = spec
        let x = AXCategoricalDataAxisDescriptor(title: spec.xTitle, categoryOrder: spec.xLabels)
        let y = AXNumericDataAxisDescriptor(title: spec.yTitle, range: spec.valueRange, gridlinePositions: []) { spec.valueText($0) }
        let series = spec.series.map { series in
            AXDataSeriesDescriptor(
                name: series.name,
                isContinuous: series.mark != .bars,
                dataPoints: zip(spec.xLabels, series.values).compactMap { label, value in
                    value.map { AXDataPoint(x: label, y: $0) }
                }
            )
        }
        return AXChartDescriptor(title: spec.title, summary: spec.summary, xAxis: x, yAxis: y, additionalAxes: [], series: series)
    }
}
