import GameCore

// What the finance charts draw (decision 176's trends, decision 179's line
// report): each chart's series, which axis they stand on, their names in
// the legend, and the same data for VoiceOver's audio graph. The app draws
// it with Swift Charts and hands it to `accessibilityChartDescriptor`.
// A chart's series always share one axis: money and people never on the
// same scale (UI health check H, 3-7).

/// What a chart's y axis counts.
public enum ChartAxis: Hashable, Sendable {
    /// Dollars.
    case money
    /// Passengers or riders.
    case people
}

/// One series of a chart: one value per x, `nil` where there is none.
public struct ChartSeries: Hashable, Sendable {
    public enum Mark: Hashable, Sendable {
        case bars
        case line
        /// A dashed line over bars.
        case dashedLine
    }

    /// Its name in the legend and to VoiceOver.
    public let name: String
    public let mark: Mark
    /// One value per x of the chart: dollars or people, as the chart's axis.
    public let values: [Double?]
}

/// A finance chart.
public struct ChartSpec: Hashable, Sendable {
    public let title: String
    /// What x is ("Period", "Day").
    public let xTitle: String
    /// Each x, spoken: "Day 12", "Days 8–14", "Year 2".
    public let xLabels: [String]
    public let axis: ChartAxis
    public let series: [ChartSeries]
    /// The sentence VoiceOver reads first.
    public let summary: String
    let language: DisplayLanguage

    /// The names the legend lists: only a chart of more than one series
    /// needs one (a single series is named by the chart's title).
    public var legendNames: [String] {
        series.count > 1 ? series.map(\.name) : []
    }

    /// The y axis's name.
    public var yTitle: String {
        switch axis {
        case .money: language.text("Dollars", "金額")
        case .people: language.text("People", "人數")
        }
    }

    /// A value on the y axis, spoken: "$ 1,234" or "1,234 people".
    public func valueText(_ value: Double) -> String {
        let whole = Int64(value.rounded())
        switch axis {
        case .money: return Money(whole * 100).moneyText
        case .people: return language.text("\(Money(whole).displayText) people", "\(Money(whole).displayText) 人")
        }
    }

    /// The lowest and highest values, with zero in the range.
    public var valueRange: ClosedRange<Double> {
        let values = series.flatMap { $0.values.compactMap { $0 } }
        let low = min(0, values.min() ?? 0), high = max(0, values.max() ?? 0)
        return low...(high > low ? high : low + 1)
    }
}

extension FinanceTrendPoint {
    fileprivate static func dollars(_ money: Money) -> Double {
        Double(money.amount) / 100
    }
}

extension FinanceHistory {
    private func spec(_ title: String, _ axis: ChartAxis, _ series: [ChartSeries], summary: String, in language: DisplayLanguage) -> ChartSpec {
        ChartSpec(
            title: title, xTitle: language.text("Period", "期間"),
            xLabels: points.map { $0.label(for: range, in: language) },
            axis: axis, series: series, summary: summary, language: language
        )
    }

    /// Revenue by source as bars, fares always and freight and rent only
    /// where there was any, and cost as a dashed line: all in dollars.
    public func revenueChart(in language: DisplayLanguage) -> ChartSpec {
        let sources: [(String, KeyPath<FinanceTrendPoint, Money>)] = [
            (language.text("Fares", "票價收入"), \.fareRevenue),
            (language.text("Freight", "貨運收入"), \.freightRevenue),
            (language.text("Rent", "物業租金"), \.propertyRevenue),
        ]
        var series = sources.enumerated().filter { index, source in
            index == 0 || points.contains { $0[keyPath: source.1] != .zero }
        }.map { _, source in
            ChartSeries(name: source.0, mark: .bars, values: points.map { FinanceTrendPoint.dollars($0[keyPath: source.1]) })
        }
        series.append(ChartSeries(name: language.text("Cost", "成本"), mark: .dashedLine, values: points.map { FinanceTrendPoint.dollars($0.cost) }))
        return spec(language.text("Revenue and cost", "收入與成本"), .money, series, summary: summaryText(in: language), in: language)
    }

    /// Net profit as bars, in dollars.
    public func profitChart(in language: DisplayLanguage) -> ChartSpec {
        let losses = points.filter { $0.netProfit < .zero }.count
        let summary = language.text("\(points.count - losses) of \(points.count) periods in profit", "\(points.count) 段期間中 \(points.count - losses) 段獲利")
        let series = [ChartSeries(name: language.text("Net profit", "淨利"), mark: .bars, values: points.map { FinanceTrendPoint.dollars($0.netProfit) })]
        return spec(language.text("Net profit", "淨利"), .money, series, summary: summary, in: language)
    }

    /// Passengers as a line, where they were counted.
    public func tripsChart(in language: DisplayLanguage) -> ChartSpec {
        let series = [ChartSeries(name: language.text("Passengers", "旅客數"), mark: .line, values: points.map { $0.trips.map(Double.init) })]
        return spec(language.text("Passengers", "旅客數"), .people, series, summary: summaryText(in: language), in: language)
    }
}

extension LineReport {
    private func spec(_ title: String, _ axis: ChartAxis, _ series: [ChartSeries], in language: DisplayLanguage) -> ChartSpec {
        ChartSpec(
            title: title, xTitle: language.text("Day", "日"),
            xLabels: days.map { language.text("Day \($0.day + 1)", "第 \($0.day + 1) 天") },
            axis: axis, series: series, summary: summaryText(in: language), language: language
        )
    }

    /// Riders each day as bars. The day's profit has a chart of its own
    /// (``profitChart(in:)``), not a line on this one's scale of people.
    public func ridersChart(in language: DisplayLanguage) -> ChartSpec {
        let series = [ChartSeries(name: language.text("Riders", "人次"), mark: .bars, values: days.map { Double($0.riders) })]
        return spec(language.text("Riders by day", "每日運量"), .people, series, in: language)
    }

    /// Fares less the line's running costs each day, as bars in dollars.
    public func profitChart(in language: DisplayLanguage) -> ChartSpec {
        let series = [ChartSeries(name: language.text("Profit", "損益"), mark: .bars, values: days.map { Double($0.profit.amount) / 100 })]
        return spec(language.text("Profit by day", "每日損益"), .money, series, in: language)
    }
}
