import GameCore
@testable import GamePresentation
import XCTest

/// Decision 377 (§22.2 25a, after decision 367; TestFlight 84.1): the
/// map's alert bubbles, its sight marks, the station master's corner and
/// the status bar's frame are told to look again only when something they
/// show changed, not at every tick.
@MainActor
final class MapMarksTests: XCTestCase {
    /// What the bubbles, the sight marks and the corner read before.
    static func readsBefore(_ session: GameSession) {
        _ = session.world.mapAlerts() + session.situationAlerts
        for sight in session.world.tourism?.attractions ?? [] { _ = session.world.stars(of: sight) }
        _ = session.world.clock.now.seconds / GameTime.secondsPerHour
    }

    /// What they read now.
    static func reads(_ session: GameSession) {
        _ = session.mapBubbles
        _ = session.mapSights
        _ = session.stationMasterRefreshKey
    }

    func testATickTellsTheMarksToLookAgainOnlyWhenTheyChanged() throws {
        let session = try ScreenFactsTests.runningLine()
        let before = ScreenFactsTests.lookAgain(over: 100, session) { Self.readsBefore(session) }
        let start = session.world.clock.now.seconds / GameTime.secondsPerHour
        let now = ScreenFactsTests.lookAgain(over: 100, session) { Self.reads(session) }
        let hours = Int(session.world.clock.now.seconds / GameTime.secondsPerHour - start)
        print("[map-marks] of 100 ticks at 600×, the marks looked again: before \(before), now \(now) (\(hours) new hours)")
        XCTAssertEqual(before, 100, "before decision 377 every tick rebuilt them")
        // A new hour (the station master's advice) at most, and the alerts
        // when they change.
        XCTAssertLessThan(now, 100)
        XCTAssertGreaterThanOrEqual(now, hours)
    }

    /// The sight marks are not told to look again when only a bubble's
    /// waiting count changed.
    func testTheSightMarksDoNotFollowTheBubbles() throws {
        let session = try ScreenFactsTests.runningLine()
        session.setSpeed(.fast)
        let bubbles = ScreenFactsTests.lookAgain(over: 100, session) { _ = session.mapBubbles }
        let sights = ScreenFactsTests.lookAgain(over: 100, session) { _ = session.mapSights }
        print("[map-marks] of 100 ticks at 6000×: bubbles \(bubbles), sights \(sights)")
        XCTAssertEqual(sights, 0)
    }

    /// The marks and the hour are what the session works out afresh, after
    /// every tick, over two game days.
    func testTheMarksAreWhatTheWorldShows() throws {
        let session = try ScreenFactsTests.runningLine()
        func check(_ step: String, line: UInt = #line) {
            let marks = MapMarks(world: session.world, situationAlerts: session.situationAlerts)
            XCTAssertEqual(session.mapBubbles, marks.bubbles, step, line: line)
            XCTAssertEqual(session.mapSights, marks.sights, step, line: line)
            XCTAssertEqual(session.adviceHour, session.world.clock.now.seconds / GameTime.secondsPerHour, step, line: line)
        }
        check("a new session")
        session.setSpeed(.fast)
        for tick in 0..<300 {
            session.advance(realElapsed: GameSession.tickInterval)
            check("tick \(tick)")
        }
    }
}
