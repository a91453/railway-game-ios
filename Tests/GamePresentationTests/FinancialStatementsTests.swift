@testable import GameCore
import GamePresentation
import XCTest

/// Phase 7a (decision 85): the income statement, cash flows, balance sheet
/// and year-end report as the economy panel and the year-end sheet show
/// them, and the session noticing a year that closes while it runs.
final class FinancialStatementsTests: XCTestCase {
    private static let costs = ConstructionCosts(track: 9_000, station: 720_000, train: 360_000, car: 36_000)

    private func world() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 10_000_000, costs: Self.costs),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_096))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 4_096))
        try world.buildTrackEdge(from: a, to: b)
        try world.buildStation(named: "West", at: PlanPoint(x: 2_048, y: 2_048))
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 3)
        try world.borrow(CompanyAccounts.loanStep)
        return world
    }

    func testTheStatementsAddUpRowByRow() throws {
        var world = try world()
        try world.advance(ticks: 1_441)
        let report = world.financeReport(.day)
        let income = report.previous.incomeStatementRows(previous: nil, in: .english)
        XCTAssertEqual(income.map(\.title), [
            "Fares", "Operating", "Maintenance", "Energy", "Staff", "Operating profit", "Loan interest", "Depreciation",
            "Assets written off", "Net profit",
        ])
        XCTAssertEqual(income.last?.style, .total)
        XCTAssertEqual(income.last?.current, Money(-1_400 - 230))
        // Every item and the net profit: the items add up to it.
        let items = income.filter { $0.style == .item }.compactMap(\.current)
        XCTAssertEqual(items.reduce(Money.zero, +), income.last?.current)
        XCTAssertTrue(income.allSatisfy { $0.previous == nil })

        let cash = report.previous.cashFlowRows(previous: report.current, in: .traditionalChinese)
        XCTAssertEqual(cash.first, StatementRow(title: "營業活動之現金流量", current: nil, previous: nil, style: .section))
        XCTAssertEqual(cash.last?.title, "本期現金淨增減")
        XCTAssertEqual(cash.last?.current, Money(-1_400 - 1_224_000) + CompanyAccounts.loanStep)
        XCTAssertEqual(cash.last?.previous, .zero, "nothing yet today")
        let flows = cash.filter { $0.style == .item }.compactMap(\.current)
        XCTAssertEqual(flows.reduce(Money.zero, +), cash.last?.current)

        // Decision 123: with the cash at the end, the cash at the start and
        // at the end follow the net change, each period's start its end
        // less its change.
        let closing = Money(5_000_000)
        let inHand = report.previous.cashFlowRows(previous: report.current, closingCash: (closing, Money(4_000_000)), in: .english)
        XCTAssertEqual(inHand.dropLast(2).map(\.title), report.previous.cashFlowRows(previous: report.current, in: .english).map(\.title))
        XCTAssertEqual(inHand.suffix(2).map(\.title), ["Cash at the start", "Cash at the end"])
        XCTAssertEqual(inHand.last, StatementRow(title: "Cash at the end", current: closing, previous: Money(4_000_000), style: .total))
        XCTAssertEqual(inHand[inHand.count - 2].current, closing - report.previous.netCashFlow)
        XCTAssertEqual(inHand[inHand.count - 2].previous, Money(4_000_000) - report.current.netCashFlow)
        XCTAssertEqual(
            report.previous.cashFlowRows(previous: nil, closingCash: (closing, Money(1)), in: .english).last?.previous, nil,
            "no previous period, no previous cash"
        )

        let sheet = world.balanceSheet()
        let rows = sheet.rows(previous: nil, in: .english)
        XCTAssertEqual(rows.map(\.title), [
            "Assets", "Cash", "Track and structures", "Stations", "Trains and cars", "Total assets", "Liabilities and equity", "Loan",
            "Equity", "Total liabilities and equity",
        ])
        XCTAssertEqual(rows[5].current, rows[9].current, "assets equal liabilities and equity")
        XCTAssertEqual(rows[4].current, Money(432_000 - 120))
        XCTAssertEqual(sheet.depreciationText(of: .rollingStock, in: .english), "Trains and cars: cost $ 4,320, written down $ 1")
        XCTAssertEqual(sheet.depreciationText(of: .stations, in: .traditionalChinese), "車站：成本 $ 7,200，累計折舊 $ 1")
        XCTAssertNil(world.unrecordedAssetsText(in: .english))
    }

    func testTaxShowsWhereThereWasSome() throws {
        // Decision 131: $250,000 of fares on a day with $14 of interest and
        // $2.30 of depreciation: $249,983.70 before tax, $74,992 of tax.
        var world = try world()
        try world.advance(ticks: 1)
        let fares = Money(25_000_000)
        world.write(LedgerEntry(
            kind: .hourlyNet, time: world.clock.now, amount: fares,
            breakdown: [
                LedgerLine(item: .fareRevenue, amount: fares), LedgerLine(item: .operatingCost, amount: .zero),
                LedgerLine(item: .maintenanceCost, amount: .zero),
            ],
            crowding: CrowdingMetrics(crowdedStations: 0, fullTrains: 0, maxWaiting: 0, maxLoad: 0)
        ), day: 0)
        try world.advance(ticks: 1_440)
        let report = world.financeReport(.day)
        let income = report.previous.incomeStatementRows(previous: report.current, in: .english)
        XCTAssertEqual(income.map(\.title), [
            "Fares", "Operating", "Maintenance", "Energy", "Staff", "Operating profit", "Loan interest", "Depreciation",
            "Assets written off", "Profit before tax", "Income tax", "Net profit",
        ])
        XCTAssertEqual(income[9], StatementRow(title: "Profit before tax", current: Money(24_998_370), previous: .zero, style: .subtotal))
        XCTAssertEqual(income[10].current, Money(-7_499_200))
        XCTAssertEqual(income.last?.current, Money(24_998_370 - 7_499_200))
        let items = income.filter { $0.style == .item }.compactMap(\.current)
        XCTAssertEqual(items.reduce(Money.zero, +), income.last?.current)
        XCTAssertEqual(
            report.previous.incomeStatementRows(previous: nil, in: .traditionalChinese).suffix(3).map(\.title), ["稅前淨利", "營利事業所得稅", "本期淨利"]
        )

        let cash = report.previous.cashFlowRows(previous: report.current, in: .traditionalChinese)
        XCTAssertEqual(cash.map(\.title).prefix(6), ["營業活動之現金流量", "票價收入", "營運支出", "利息支出", "所得稅支出", "營業活動淨額"])
        XCTAssertEqual(cash[4].current, Money(-7_499_200))
        let flows = cash.filter { $0.style == .item }.compactMap(\.current)
        XCTAssertEqual(flows.reduce(Money.zero, +), cash.last?.current)
        XCTAssertEqual(LedgerEntry.Kind.dailyTax.displayName(in: .traditionalChinese), "營利事業所得稅（日結）")
        XCTAssertEqual(LedgerItem.incomeTax.displayName(in: .english), "Income tax")
        XCTAssertEqual(
            CompanyAccounts.taxTermsText(in: .english), "Income tax: 50% of each day's profit before tax beyond $ 100,000, paid at midnight"
        )
        XCTAssertEqual(CompanyAccounts.taxTermsText(in: .traditionalChinese), "營利事業所得稅：每天的稅前淨利超過 $ 100,000 的部分課 50%，午夜支付")
    }

    func testAClosedYearHasItsTitleAndHeadline() throws {
        var world = try world()
        try world.advance(ticks: 360 * 1_440 + 1)
        let year = try XCTUnwrap(world.lastClosedYear)
        XCTAssertEqual(year.titleText(in: .english), "Year 1 closing")
        XCTAssertEqual(year.titleText(in: .traditionalChinese), "第 1 年度決算")
        // 360 days of $14 interest and 230 cents of depreciation: $5,040 and
        // $828, a loss of $5,868; equity $100,000 less that.
        XCTAssertEqual(year.headlineText(in: .english), "Net loss $ 5,868 · equity $ 94,132")
        XCTAssertEqual(year.headlineText(in: .traditionalChinese), "本期淨損 $ 5,868 · 權益 $ 94,132")
    }

    func testWhatWasBuiltBeforeCostsWereKeptIsNoted() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 10_000_000, costs: Self.costs))
        try world.buildStation(named: "West", at: PlanPoint(x: 2_048, y: 2_048))
        world.setEconomyMode(.management)
        XCTAssertEqual(world.unrecordedAssetsText(in: .english), "1 track, station or train items built before their cost was kept are on the books at $ 0.")
        XCTAssertEqual(world.unrecordedAssetsText(in: .traditionalChinese), "有 1 項軌道、車站或列車在開始記錄成本之前建造，以 $ 0 入帳。")
    }

    @MainActor
    func testTheSessionNoticesAYearThatClosesWhileItRuns() throws {
        var world = try world()
        try world.advance(ticks: 359 * 1_440)
        world.setSpeed(.normal)
        let session = GameSession(world: world)
        XCTAssertNil(session.yearEndYear)
        // `normal` runs a game minute a 100 ms tick; five ticks a step.
        for _ in 0..<288 {
            session.advance(realElapsed: GameSession.maximumStepDuration)
            XCTAssertNil(session.yearEndYear)
        }
        // The step past midnight closes the year.
        session.advance(realElapsed: GameSession.maximumStepDuration)
        XCTAssertEqual(session.yearEndYear, 0)
        XCTAssertEqual(session.yearEndStatement, session.world.accounts.years.last)
        session.dismissYearEnd()
        XCTAssertNil(session.yearEndYear)
        XCTAssertNil(session.yearEndStatement)
        // A loaded game whose year closed before shows nothing.
        XCTAssertNil(GameSession(world: session.world).yearEndYear)
    }

    /// Decision 130: a period that sold a building shows what it brought in,
    /// its book value and the gain or loss in the income statement, and the
    /// cash in the investing activities; one that sold none shows neither.
    func testABuildingSoldShowsInBothStatements() throws {
        // A house on empty land, 2,048,000 + 256,000, sold at once for 95%
        // of its land, 243,200.
        var world = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        world.setEconomyMode(.management)
        let id = try world.placeBuilding(.house, at: PlanPoint(x: 5_000, y: 5_000)).id
        let bought = world.financeReport(.day).current
        XCTAssertFalse(bought.incomeStatementRows(previous: nil, in: .english).map(\.title).contains("Buildings sold"))
        XCTAssertFalse(bought.cashFlowRows(previous: nil, in: .english).map(\.title).contains("Buildings sold"))
        try world.sellPlacedBuilding(id)
        let summary = world.financeReport(.day).current
        let income = summary.incomeStatementRows(previous: nil, in: .english)
        let rows = Dictionary(uniqueKeysWithValues: income.map { ($0.title, $0.current) })
        XCTAssertEqual(rows["Buildings sold"], 243_200)
        XCTAssertEqual(rows["Their book value"], -2_304_000)
        XCTAssertEqual(rows["Gain or loss on sale (realized)"], -2_060_800)
        XCTAssertEqual(rows["Net profit"], -2_060_800)
        XCTAssertEqual(income.last?.title, "Net profit")
        let cash = summary.cashFlowRows(previous: nil, in: .traditionalChinese)
        let investing = Dictionary(uniqueKeysWithValues: cash.map { ($0.title, $0.current) })
        XCTAssertEqual(investing["出售建物收入"], 243_200)
        XCTAssertEqual(investing["投資活動淨額"], 243_200 - 2_304_000)
        XCTAssertEqual(investing["本期現金淨增減"], world.economy.balance - 100_000_000)
        // A later period beside it shows the rows too, at 0.
        let next = world.accounts.report(.day, day: 1)
        XCTAssertEqual(next.current.incomeStatementRows(previous: next.previous, in: .traditionalChinese)
            .first { $0.title == "出售建物損益（已實現）" }?.previous, -2_060_800)
    }
}
