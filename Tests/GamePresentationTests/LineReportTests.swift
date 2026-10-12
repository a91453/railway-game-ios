import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 179: the per-line report read from the line
/// accounts: yesterday's row, the sorts, the map's bubble for a line that
/// loses money a week running, the fleet's sorts and a station's flow.
@MainActor
final class LineReportTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let gamma = StationID(rawValue: 3)
    private static let short = LineID(rawValue: 1)
    private static let long = LineID(rawValue: 2)

    /// Short (Alpha, Beta) and Long (Alpha, Beta, Gamma), managed, no trains,
    /// so no fares: each line loses what its stations cost, Long the more.
    private func managedWorld(accounts: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Short", stops: [Self.alpha, Self.beta])
        try world.createLine(named: "Long", stops: [Self.alpha, Self.beta, Self.gamma])
        world.setEconomyMode(.management)
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        return world
    }

    func testWithoutTheAccountsThereIsNoReport() throws {
        var world = try managedWorld(accounts: false)
        try world.advance(ticks: 3 * 1_440)
        XCTAssertNil(world.lineReport(Self.short))
        XCTAssertEqual(world.lineReports(), [])
        XCTAssertNil(world.stationFlowText(at: Self.alpha, in: .english))
        XCTAssertFalse(world.lineLosingMoney(Self.short))
    }

    func testYesterdayRowAndTheCompletedDays() throws {
        var world = try managedWorld()
        XCTAssertEqual(world.lineReport(Self.short)?.yesterday, nil)
        XCTAssertEqual(world.lineReport(Self.short)?.rowText(in: .english), "No record of yesterday yet")
        try world.advance(ticks: 2 * 1_440 + 120)
        let report = try XCTUnwrap(world.lineReport(Self.short))
        // Days 0 and 1 are complete, day 2 is in progress and left out.
        XCTAssertEqual(report.days.map(\.day), [0, 1])
        let yesterday = try XCTUnwrap(report.yesterday)
        XCTAssertEqual(yesterday.day, 1)
        XCTAssertEqual(yesterday.riders, 0)
        XCTAssertLessThan(yesterday.profit, .zero)
        XCTAssertEqual(report.rowText(in: .english),
                       "Yesterday 0 riders · fares $ 0 · profit \(yesterday.profit.moneyText) · peak 0%")
        XCTAssertEqual(report.rowText(in: .traditionalChinese),
                       "昨日 0 人次 · 票收 $ 0 · 損益 \(yesterday.profit.moneyText) · 尖峰 0%")
        XCTAssertNil(report.operatingRatioPercent, "no fares, no ratio")
        XCTAssertTrue(report.summaryText(in: .english).hasPrefix("Last 2 days · 0 riders"))
        XCTAssertEqual(report.totalProfit, .zero - report.totalCost)
    }

    func testTheSorts() throws {
        var world = try managedWorld()
        try world.advance(ticks: 1_440 + 120)
        // The same riders and load (none), so profit tells them apart: Long
        // has more stations to pay for.
        XCTAssertEqual(world.lineReports(sortedBy: .profit).map(\.line), [Self.short, Self.long])
        XCTAssertEqual(world.lineReports(sortedBy: .name).map(\.name), ["Long", "Short"])
        XCTAssertEqual(world.lineReports(sortedBy: .ridership).map(\.line), [Self.short, Self.long], "a tie goes by line")
        XCTAssertEqual(world.lineReports(sortedBy: .load).map(\.line), [Self.short, Self.long])
        XCTAssertEqual(LineReportSort.allCases.count, 4)
        for sort in LineReportSort.allCases {
            XCTAssertFalse(sort.displayName(in: .english).isEmpty)
            XCTAssertFalse(sort.displayName(in: .traditionalChinese).isEmpty)
        }
    }

    func testALineLosingMoneyForAWeekShowsOnTheMap() throws {
        var world = try managedWorld()
        try world.advance(ticks: 6 * 1_440 + 120)
        XCTAssertFalse(world.lineLosingMoney(Self.short), "six completed days")
        XCTAssertFalse(world.mapAlerts().contains { if case .lineLosingMoney = $0.kind { true } else { false } })
        try world.advance(ticks: 1_440)
        XCTAssertTrue(world.lineLosingMoney(Self.short))
        let alerts = world.mapAlerts().filter { if case .lineLosingMoney = $0.kind { true } else { false } }
        XCTAssertEqual(alerts.map(\.kind), [.lineLosingMoney(Self.short), .lineLosingMoney(Self.long)])
        XCTAssertEqual(alerts.first?.station, Self.alpha)
        XCTAssertEqual(alerts.first?.text(in: .english, lineName: "Short"), "Short: losing money")
        XCTAssertEqual(alerts.first?.text(in: .traditionalChinese, lineName: "Short"), "Short：連續虧損")
        let session = GameSession(world: world)
        XCTAssertTrue(session.respond(to: try XCTUnwrap(alerts.last)), "the line panel opens")
        XCTAssertEqual(session.selectedLineID, Self.long)
    }

    func testAStationsFlowOfYesterday() throws {
        var world = try managedWorld()
        try world.advance(ticks: 1_440 + 10)
        XCTAssertEqual(world.stationFlowText(at: Self.alpha, in: .english), "Yesterday 0 boarded · 0 got off")
        XCTAssertEqual(world.stationFlowText(at: Self.alpha, in: .traditionalChinese), "昨日進站 0 人 · 出站 0 人")
    }

    func testTheFleetSorts() throws {
        var world = try managedWorld()
        try world.createLine(named: "Third", stops: [Self.beta, Self.gamma])
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        let three = try world.purchaseTrain(named: "Three").id
        try world.assignTrain(one, to: LineID(rawValue: 3), pattern: nil)
        try world.assignTrain(two, to: Self.short, pattern: nil)
        // Three is on no line.
        XCTAssertEqual(world.fleet(sortedBy: .name).map(\.id), [one, two, three])
        XCTAssertEqual(world.fleet(sortedBy: .line).map(\.id), [two, one, three])
        XCTAssertEqual(world.fleet(sortedBy: .load).count, 3)
        XCTAssertEqual(world.fleet(sortedBy: .late).map(\.id), [one, two, three], "none has a punctuality: the world's order")
        for sort in FleetSort.allCases {
            XCTAssertFalse(sort.displayName(in: .traditionalChinese).isEmpty)
        }
    }
}
