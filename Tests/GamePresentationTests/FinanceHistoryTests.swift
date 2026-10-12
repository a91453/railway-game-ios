@testable import GameCore
import GamePresentation
import XCTest

/// Decision 176: the economy panel's trend charts, folded from the days and
/// closed years of the accounts.
final class FinanceHistoryTests: XCTestCase {
    private func accounts(days: [Int64: (fare: Int64, trips: Int64)], cost: Int64 = 0) -> CompanyAccounts {
        var accounts = CompanyAccounts()
        for day in days.keys.sorted() {
            var account = DayAccount(day: day)
            account.fareRevenue = Money(days[day]!.fare)
            account.fareTrips = days[day]!.trips
            account.operatingCost = Money(cost)
            account.interestCost = Money(cost)
            account.taxCost = Money(cost)
            accounts.days.append(account)
        }
        return accounts
    }

    func testThirtyDaysAreOneBucketPerDayEndingToday() {
        let history = FinanceHistory.make(.thirtyDays, accounts: accounts(days: [100: (500, 5), 129: (700, 7)], cost: 100), today: 129)
        XCTAssertEqual(history.points.count, 30)
        XCTAssertEqual(history.points.first?.startDay, 100)
        XCTAssertEqual(history.points.last?.startDay, 129)
        XCTAssertEqual(history.points.first?.fareRevenue, Money(500))
        XCTAssertEqual(history.points.first?.cost, Money(300))
        XCTAssertEqual(history.points.first?.netProfit, Money(200))
        XCTAssertEqual(history.points.last?.trips, 7)
        XCTAssertEqual(history.fareRevenue, Money(1_200))
    }

    func testDaysBeforeTheCompanyBeganAreLeftOut() {
        let history = FinanceHistory.make(.thirtyDays, accounts: accounts(days: [125: (500, 5)]), today: 129)
        XCTAssertEqual(history.points.map(\.startDay), Array(125...129))
        XCTAssertTrue(FinanceHistory.make(.thirtyDays, accounts: CompanyAccounts(), today: 10).isEmpty)
    }

    func testWeeksAndMonthsAddTheirDaysUp() {
        let days = Dictionary(uniqueKeysWithValues: (0..<360).map { (Int64($0), (fare: Int64(10), trips: Int64(1))) })
        let week = FinanceHistory.make(.ninetyDays, accounts: accounts(days: days), today: 359)
        XCTAssertEqual(week.points.count, 13)
        XCTAssertEqual(week.points.last?.endDay, 359)
        XCTAssertEqual(week.points.allSatisfy { $0.fareRevenue == Money(70) && $0.trips == 7 }, true)
        let month = FinanceHistory.make(.oneYear, accounts: accounts(days: days), today: 359)
        XCTAssertEqual(month.points.count, 12)
        XCTAssertEqual(month.points.allSatisfy { $0.fareRevenue == Money(300) }, true)
        XCTAssertEqual(month.points.first?.startDay, 0)
    }

    func testTheHeadlineComparesWithTheWindowBefore() {
        var days: [Int64: (fare: Int64, trips: Int64)] = [:]
        for day in 70..<100 { days[Int64(day)] = (100, 10) }
        for day in 100..<130 { days[Int64(day)] = (112, 9) }
        let history = FinanceHistory.make(.thirtyDays, accounts: accounts(days: days), today: 129)
        XCTAssertEqual(history.fareChangePercent, 12)
        XCTAssertEqual(history.tripsChangePercent, -10)
        XCTAssertEqual(history.summaryText(in: .english), "Last 30 days: fares up 12%, passengers down 10%")
        XCTAssertEqual(history.summaryText(in: .traditionalChinese), "過去 30 天：票收成長 12%、旅客下降 10%")
    }

    func testNothingEarlierToCompareWith() {
        let history = FinanceHistory.make(.thirtyDays, accounts: accounts(days: [129: (100, 1)]), today: 129)
        XCTAssertNil(history.fareChangePercent)
        XCTAssertTrue(history.summaryText(in: .english).contains("no earlier period"))
        XCTAssertEqual(FinanceHistory.make(.oneYear, accounts: CompanyAccounts(), today: 5).summaryText(in: .english), "Last year: nothing to show yet.")
    }

    func testClosedYearsHaveNoPassengerCount() {
        var accounts = CompanyAccounts()
        for year in 0..<2 {
            let income = FinanceSummary(
                index: Int64(year), fareRevenue: Money(Int64(1_000 * (year + 1))), operatingCost: Money(200), maintenanceCost: .zero,
                energyCost: .zero, staffCost: .zero, interestCost: Money(50)
            )
            let zero = AssetClassBalance.zero
            let sheet = BalanceSheet(cash: .zero, track: zero, stations: zero, rollingStock: zero, loan: .zero)
            accounts.years.append(AnnualStatement(year: Int64(year), income: income, closing: sheet))
        }
        let history = FinanceHistory.make(.allYears, accounts: accounts, today: 800)
        XCTAssertEqual(history.points.count, 2)
        XCTAssertEqual(history.points[1].startDay, 360)
        XCTAssertEqual(history.points[1].netProfit, Money(1_750))
        XCTAssertFalse(history.hasTrips)
        XCTAssertEqual(history.fareChangePercent, 100)
        XCTAssertEqual(history.summaryText(in: .english), "Latest closed year: fares up 100%")
        XCTAssertEqual(history.points[1].label(for: .allYears, in: .traditionalChinese), "第 2 年")
    }

    func testTheLossIsNamedInTheDetail() {
        let point = FinanceTrendPoint(
            startDay: 7, endDay: 7, fareRevenue: Money(100), freightRevenue: .zero, propertyRevenue: .zero, cost: Money(300), trips: 4
        )
        XCTAssertTrue(point.detailText(for: .thirtyDays, in: .english).hasPrefix("Day 8 · revenue "))
        XCTAssertTrue(point.detailText(for: .thirtyDays, in: .english).contains("loss $ 2"))
        XCTAssertTrue(point.detailText(for: .thirtyDays, in: .traditionalChinese).contains("旅客 4 人"))
    }

    func testTheWorldOverloadReadsTheClock() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000, costs: ConstructionCosts(track: 1, station: 1, train: 1, car: 1)))
        try world.advance(ticks: 1_441)
        let history = FinanceHistory.make(.thirtyDays, world: world)
        XCTAssertTrue(history.points.count <= 30)
    }
}
