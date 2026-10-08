import GameCore
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
}
