@testable import GameCore
import GamePresentation
import XCTest

/// UI health check H: each finance chart's series stand on one axis
/// (money and people never share a scale), the legend names every series
/// of a chart with more than one, and the audio graph has a value for
/// each x.
@MainActor
final class FinanceChartSpecTests: XCTestCase {
    private func history(freight: Bool) -> FinanceHistory {
        var accounts = CompanyAccounts()
        for day: Int64 in 100...129 {
            var account = DayAccount(day: day)
            account.fareRevenue = Money(50_000)
            account.fareTrips = 40
            if freight, day == 120 { account.freightRevenue = Money(12_000) }
            account.operatingCost = Money(day == 110 ? 90_000 : 30_000)
            accounts.days.append(account)
        }
        return FinanceHistory.make(.thirtyDays, accounts: accounts, today: 129)
    }

    func testTheRevenueChartListsTheCostLineInItsLegend() {
        let chart = history(freight: false).revenueChart(in: .english)
        XCTAssertEqual(chart.axis, .money)
        XCTAssertEqual(chart.legendNames, ["Fares", "Cost"])
        XCTAssertEqual(chart.series.map(\.mark), [.bars, .dashedLine])
        XCTAssertEqual(chart.xLabels.first, "Day 101")
        XCTAssertEqual(chart.series[0].values.first, 500)
        XCTAssertEqual(chart.series[1].values.first, 300)

        let withFreight = history(freight: true).revenueChart(in: .traditionalChinese)
        XCTAssertEqual(withFreight.legendNames, ["票價收入", "貨運收入", "成本"])
        XCTAssertEqual(withFreight.yTitle, "金額")
    }

    func testProfitAndPassengersHaveChartsOfTheirOwn() {
        let history = history(freight: false)
        let profit = history.profitChart(in: .english)
        XCTAssertEqual(profit.axis, .money)
        XCTAssertEqual(profit.legendNames, [], "one series: the title names it")
        XCTAssertEqual(profit.summary, "29 of 30 periods in profit")
        XCTAssertEqual(profit.series[0].values[10], -400)
        XCTAssertEqual(profit.valueRange, -400...200)

        let trips = history.tripsChart(in: .english)
        XCTAssertEqual(trips.axis, .people)
        XCTAssertEqual(trips.series.map(\.mark), [.line])
        XCTAssertEqual(trips.valueText(1_234), "1,234 people")
        XCTAssertEqual(profit.valueText(-400), "$ -400")
    }

    func testEverySeriesHasAValueForEachX() {
        let history = history(freight: true)
        for chart in [history.revenueChart(in: .english), history.profitChart(in: .english), history.tripsChart(in: .english)] {
            XCTAssertEqual(Set(chart.xLabels).count, chart.xLabels.count, "\(chart.title): x labels are the audio graph's categories")
            for series in chart.series {
                XCTAssertEqual(series.values.count, chart.xLabels.count, "\(chart.title): \(series.name)")
            }
        }
    }

    /// The line report's riders and its profit are two charts: the profit
    /// is no longer a line scaled onto the riders' axis.
    func testTheLineReportKeepsRidersAndProfitApart() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Short", stops: [StationID(rawValue: 1), StationID(rawValue: 2)])
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        world.setSpeed(.normal)
        try world.advance(ticks: 2 * 1_440 + 120)
        let report = try XCTUnwrap(world.lineReport(LineID(rawValue: 1)))

        let riders = report.ridersChart(in: .english)
        XCTAssertEqual(riders.axis, .people)
        XCTAssertEqual(riders.series.map(\.name), ["Riders"])
        XCTAssertEqual(riders.title, "Riders by day")
        XCTAssertEqual(riders.xLabels, ["Day 1", "Day 2"])

        let profit = report.profitChart(in: .traditionalChinese)
        XCTAssertEqual(profit.axis, .money)
        XCTAssertEqual(profit.series.map(\.name), ["損益"])
        XCTAssertEqual(profit.xLabels, ["第 1 天", "第 2 天"])
        XCTAssertEqual(profit.series[0].values, report.days.map { Double($0.profit.amount) / 100 })
        XCTAssertLessThan(profit.valueRange.lowerBound, 0)
    }
}
