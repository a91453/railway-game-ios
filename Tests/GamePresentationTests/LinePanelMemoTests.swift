import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 184, later: the line panel keeps what only a command changes
/// (``LinePanelMemo``) and reads it back while game time runs. What it
/// reads back is what the world would work out now, and a command makes it
/// work everything out again.
@MainActor
final class LinePanelMemoTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let main = LineID(rawValue: 1)

    /// Alpha, Beta, Gamma and Delta along one straight track, a line
    /// calling at all four with an express between the ends, and trains
    /// every 5 minutes on it, running all day.
    private func runningSession() throws -> GameSession {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000, speed: .normal)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        try world.setLineServiceWindow(Self.main, to: .allDay)
        let session = GameSession(world: world)
        session.selectLine(Self.main)
        session.staffSelectedLine(headway: 5)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.addPatternToSelectedLine(from: 0, to: 3, express: true)
        XCTAssertEqual(session.world.line(id: Self.main)?.patterns.count, 1)
        return session
    }

    /// Every leg of every service of `line`, as the panel lists them.
    private func legs(of line: ServiceLine) -> [(pattern: Int?, from: Int, to: Int)] {
        ([nil] + line.patterns.indices.map(Optional.some)).flatMap { pattern -> [(pattern: Int?, from: Int, to: Int)] in
            let calls = pattern.map { line.patterns[$0].calls } ?? Array(line.stops.indices)
            let order = calls + calls.dropLast().reversed()
            return zip(order, order.dropFirst()).map { (pattern, $0, $1) }
        }
    }

    /// Asserts that everything `memo` gives for the main line is what the
    /// world works out now.
    private func assertSameAsTheWorld(_ memo: LinePanelMemo, _ session: GameSession, _ note: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let world = session.world, language = session.language
        let main = try XCTUnwrap(world.line(id: Self.main), file: file, line: line)
        XCTAssertEqual(memo.serviceSummaries(Self.main, of: session), world.lineServiceSummaries(Self.main, in: language), note, file: file, line: line)
        for leg in legs(of: main) {
            XCTAssertEqual(
                memo.routeChoices(Self.main, from: leg.from, to: leg.to, pattern: leg.pattern, of: session),
                world.lineRouteChoices(Self.main, from: leg.from, to: leg.to, pattern: leg.pattern),
                "\(note): leg \(leg)", file: file, line: line
            )
        }
        XCTAssertEqual(memo.journeyText(Self.main, of: session), world.lineJourneyText(Self.main, in: language), note, file: file, line: line)
        XCTAssertEqual(memo.trackCountTexts(Self.main, of: session), world.lineTrackCountTexts(Self.main, in: language), note, file: file, line: line)
        for level in ServiceLevel.allCases {
            XCTAssertEqual(memo.coverageText(Self.main, at: level, of: session), world.lineCoverageText(Self.main, at: level, in: language),
                           "\(note): \(level)", file: file, line: line)
        }
        for headway in GameWorld.staffingHeadways {
            for type in [nil, TrainType.highSpeed] {
                XCTAssertEqual(
                    memo.staffingPlan(Self.main, headway: headway, type: type, cars: 3, of: session),
                    world.lineStaffingPlan(Self.main, headway: headway, type: type, cars: 3),
                    "\(note): every \(headway) min", file: file, line: line
                )
            }
        }
    }

    func testWhileTheGameRunsTheMemoGivesWhatTheWorldWorksOutNow() throws {
        let session = try runningSession()
        let memo = LinePanelMemo()
        try assertSameAsTheWorld(memo, session, "before the clock runs")
        let revision = session.commandRevision
        var sawRunning = false, sawWaiting = false
        // Two game hours at the normal speed: trains set out, run, wait and
        // set out again, while what was kept is read back.
        for tick in 1...720 {
            session.advance(realElapsed: GameSession.tickInterval)
            XCTAssertEqual(session.commandRevision, revision, "game time alone keeps what was worked out")
            let running = memo.serviceSummaries(Self.main, of: session).map(\.running).reduce(0, +)
            sawRunning = sawRunning || running > 0
            sawWaiting = sawWaiting || running < session.world.trains.count
            if tick.isMultiple(of: 60) {
                try assertSameAsTheWorld(memo, session, "after \(tick) ticks")
            } else if tick.isMultiple(of: 5) {
                XCTAssertEqual(memo.serviceSummaries(Self.main, of: session), session.world.lineServiceSummaries(Self.main, in: session.language),
                               "after \(tick) ticks")
            }
        }
        XCTAssertTrue(sawRunning, "the test needs trains on a trip")
        XCTAssertTrue(sawWaiting, "the test needs trains between trips")
    }

    func testACommandMakesTheMemoWorkItOutAgain() throws {
        let session = try runningSession()
        let memo = LinePanelMemo()
        try assertSameAsTheWorld(memo, session, "at first")
        let summaries = memo.serviceSummaries(Self.main, of: session)
        let journey = memo.journeyText(Self.main, of: session)

        // The express taken off: one service fewer.
        session.removePatternFromSelectedLine(0)
        XCTAssertEqual(session.world.line(id: Self.main)?.patterns.count, 0, session.message?.text ?? "")
        XCTAssertNotEqual(memo.serviceSummaries(Self.main, of: session), summaries, "kept from before the command")
        try assertSameAsTheWorld(memo, session, "after the express is taken off")

        // Gamma no longer called at: the journey, the legs and the tracks change.
        session.removeStopFromSelectedLine(at: 2)
        XCTAssertEqual(session.world.line(id: Self.main)?.stops.count, 3, session.message?.text ?? "")
        XCTAssertNotEqual(memo.journeyText(Self.main, of: session), journey, "kept from before the command")
        try assertSameAsTheWorld(memo, session, "after a stop removed")

        // An undo is a change too.
        session.undo()
        XCTAssertEqual(session.world.line(id: Self.main)?.stops.count, 4)
        try assertSameAsTheWorld(memo, session, "after the undo")
    }

    func testAnotherSessionOrLineIsWorkedOutForItself() throws {
        let session = try runningSession()
        let memo = LinePanelMemo()
        _ = memo.serviceSummaries(Self.main, of: session)
        // A second line, Beta to Delta, in a session of its own.
        var world = session.world
        let stops = world.lines[0].stops
        try world.createLine(named: "Short", stops: [stops[1], stops[3]])
        let other = GameSession(world: world)
        let short = try XCTUnwrap(world.lines.last?.id)
        XCTAssertEqual(memo.serviceSummaries(short, of: other), world.lineServiceSummaries(short, in: other.language))
        XCTAssertEqual(memo.journeyText(short, of: other), world.lineJourneyText(short, in: other.language))
        try assertSameAsTheWorld(memo, session, "back to the first session")
    }

    func testLinesKeepTheOrderTheyWereSortedIn() throws {
        var world = try runningSession().world
        let stops = world.lines[0].stops
        try world.createLine(named: "Short", stops: [stops[1], stops[3]])
        try world.createLine(named: "Shorter", stops: [stops[2], stops[3]])
        let ids = world.lines.map(\.id)
        XCTAssertEqual(world.lines(keeping: [ids[2], ids[0], ids[1]]).map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertEqual(world.lines(keeping: [ids[1]]).map(\.id), [ids[1], ids[0], ids[2]], "lines made since go last")
        XCTAssertEqual(world.lines(keeping: [LineID(rawValue: 99), ids[2]]).map(\.id), [ids[2], ids[0], ids[1]], "a line gone is left out")
    }
}
