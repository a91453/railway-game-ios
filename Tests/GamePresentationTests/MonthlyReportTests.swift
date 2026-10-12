import GameCore
@testable import GamePresentation
import XCTest

/// Decision 175: the monthly report, after the reference's economy report
/// (the period against the one before it).
@MainActor
final class MonthlyReportTests: XCTestCase {
    func testAFigureSaysItsChangeInWholePercent() {
        XCTAssertEqual(MonthlyFigure(value: 118, previous: 100).percent, 18)
        XCTAssertEqual(MonthlyFigure(value: 118, previous: 100).arrowText, "▲ 18%")
        XCTAssertEqual(MonthlyFigure(value: 95, previous: 100).arrowText, "▼ 5%")
        XCTAssertEqual(MonthlyFigure(value: 100, previous: 100).arrowText, "–")
        XCTAssertEqual(MonthlyFigure(value: 5, previous: 0).arrowText, "", "nothing to compare with")
        XCTAssertEqual(MonthlyFigure(value: 5, previous: nil).percent, nil)
        XCTAssertEqual(MonthlyFigure(value: 1, previous: 3).percent, -67)
    }

    func testTheHeadlinesAreSaidInBothLanguages() {
        XCTAssertEqual(MonthlyHeadline.record(.fares, percent: 18).text(in: .traditionalChinese), "票收創新高 +18%")
        XCTAssertEqual(MonthlyHeadline.record(.fares, percent: 18).text(in: .english), "Fare revenue hit a record: +18%")
        XCTAssertEqual(MonthlyHeadline.change(.riders, percent: -7).text(in: .traditionalChinese), "客流量比上月減少 7%")
        XCTAssertEqual(MonthlyHeadline.turnedProfit.text(in: .traditionalChinese), "轉虧為盈：本月有賺錢")
    }

    func testFreePlayHasNoReport() throws {
        let world = try NewsSessionTests.world(day: 31, managed: false)
        XCTAssertNil(MonthlyReport.make(month: 0, in: world, baseline: nil))
    }

    func testTheSessionClosesEachMonthWithAReportThatOpensAndPauses() throws {
        let world = try NewsSessionTests.world(day: 28)
        let session = GameSession(world: world, language: .english)
        XCTAssertEqual(session.monthlyReportMode, .openAndPause)
        // Day 28 to day 31: month 0 closes at day 30.
        func step(_ ticks: Int) throws {
            let tick = try XCTUnwrap(session.beginLoopTick())
            XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: ticks, listening: false))))
        }
        try step(1_440)
        XCTAssertNil(session.monthEndReport)
        try step(1_440)
        let report = try XCTUnwrap(session.monthEndReport)
        XCTAssertEqual(report.month, 0)
        XCTAssertNil(report.fares.previous, "the game had no month before the first")
        XCTAssertTrue(session.world.clock.isPaused)
        let item = try XCTUnwrap(session.news.items.first { $0.category == .monthly })
        XCTAssertTrue(item.text(in: .traditionalChinese).hasPrefix("第 1 個月月報："), item.text(in: .traditionalChinese))
        XCTAssertEqual(session.news.baseline?.reportedMonth, 0)

        session.dismissMonthEnd()
        XCTAssertNil(session.monthEndReport)
    }

    /// Decision 175, later: a demo being looked at, or a game with its pauses
    /// off, gets the report in the news but no sheet and no pause.
    func testADemoOrAGameWithPausesOffOnlyLogsTheReport() throws {
        for (demo, pauses) in [(true, true), (false, false)] {
            let session = GameSession(world: try NewsSessionTests.world(day: 29), language: .english)
            session.news.isDemo = demo
            session.pausesForImportantEvents = pauses
            let tick = try XCTUnwrap(session.beginLoopTick())
            XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 2 * 1_440, listening: false))))
            XCTAssertNil(session.monthEndReport, "demo \(demo)")
            XCTAssertFalse(session.world.clock.isPaused, "demo \(demo)")
            XCTAssertTrue(session.news.items.contains { $0.category == .monthly }, "demo \(demo)")
        }
    }

    /// A news file whose baseline is of a month not yet come (it belongs to
    /// another game) would stop the reports; it starts afresh.
    func testABaselineFromTheFutureIsReplacedWhenTheNewsIsRestored() throws {
        let session = GameSession(world: try NewsSessionTests.world(day: 3), language: .english)
        var log = NewsLog()
        log.baseline = MonthlyBaseline(reportedMonth: 50, stationTrips: [:], tallBuildings: 0)
        session.restoreNews(log)
        XCTAssertEqual(session.news.baseline?.reportedMonth, -1)
    }

    func testLogOnlyKeepsTheReportInTheNewsAndDoesNotPause() throws {
        let world = try NewsSessionTests.world(day: 29)
        let session = GameSession(world: world, language: .english)
        session.monthlyReportMode = .logOnly
        let tick = try XCTUnwrap(session.beginLoopTick())
        XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 2 * 1_440, listening: false))))
        XCTAssertNil(session.monthEndReport)
        XCTAssertFalse(session.world.clock.isPaused)
        XCTAssertTrue(session.news.items.contains { $0.category == .monthly })
    }

    func testOffWritesNothing() throws {
        let session = GameSession(world: try NewsSessionTests.world(day: 29), language: .english)
        session.monthlyReportMode = .off
        let tick = try XCTUnwrap(session.beginLoopTick())
        XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 2 * 1_440, listening: false))))
        XCTAssertNil(session.monthEndReport)
        XCTAssertFalse(session.news.items.contains { $0.category == .monthly })
        XCTAssertEqual(session.news.baseline?.reportedMonth, 0, "the next report still compares with this month")
    }

    func testTheSecondMonthIsComparedWithTheFirstAndStationsAreRanked() throws {
        let world = try NewsSessionTests.world(day: 0)
        let session = GameSession(world: world, language: .english)
        session.monthlyReportMode = .logOnly
        // The baseline is taken at the first step; raise a station's trips for month 1.
        func step(days: Int) throws {
            let tick = try XCTUnwrap(session.beginLoopTick())
            XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: days * 1_440, listening: false))))
        }
        try step(days: 1)
        try session.performEdit { world throws(GameError) in
            try world.setStationDemand(NewsSessionTests.alpha, to: StationDemand(kind: .residential, dailyTrips: 500))
        }
        try step(days: 30)
        try step(days: 30)
        let reports = session.news.items.filter { $0.category == .monthly }
        XCTAssertEqual(reports.count, 2)
        let second = try XCTUnwrap(MonthlyReport.make(month: 1, in: session.world, baseline: MonthlyBaseline(
            reportedMonth: 0, stationTrips: [1: 200, 2: 200], tallBuildings: 0
        )))
        XCTAssertNotNil(second.riders.previous)
        XCTAssertEqual(second.grown.map(\.station), [NewsSessionTests.alpha])
        XCTAssertEqual(second.grown.first?.delta, 300)
        XCTAssertTrue(second.fallen.isEmpty)
        XCTAssertEqual(second.cash.value, session.world.economy.balance.amount)
    }
}
