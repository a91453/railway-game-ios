import GameCore
@testable import GamePresentation
import Observation
import XCTest

/// Decision 367 (§22.2 25a; TestFlight 83.1): a tick tells the screen's
/// frame (the app's `ContentView`) to look again only when something it
/// shows changed. Before, the frame read the world itself (the real-world
/// frame, the next steps, the selection's text), so every tick, ten a
/// second, rebuilt the whole screen.
@MainActor
final class ScreenFactsTests: XCTestCase {
    /// What the frame read of the session before decision 367.
    static func frameReadsBefore(_ session: GameSession) {
        _ = RealWorldFrame(world: session.world)
        _ = session.nextSteps
        _ = session.selectionText()
    }

    /// What it reads now (``ContentView/gameLayout`` and its body).
    static func frameReads(_ session: GameSession) {
        _ = session.screenFacts
        _ = session.tutorial
        _ = session.followedTrain
        _ = session.lineDraft
        _ = session.tool
        _ = session.canUndo
        _ = session.canRedo
        _ = session.selectedStationID
        _ = session.tappedTrainID
    }

    func testATickTellsTheFrameToLookAgainOnlyWhenWhatItShowsChanged() throws {
        let session = try Self.runningLine()
        let before = Self.lookAgain(over: 100, session) { Self.frameReadsBefore(session) }
        let now = Self.lookAgain(over: 100, session) { Self.frameReads(session) }
        print("[screen-facts] of 100 ticks at 600×, the frame looked again: before \(before), now \(now)")
        XCTAssertEqual(before, 100, "before decision 367 every tick rebuilt the frame")
        XCTAssertEqual(now, 0)
    }

    func testWithAStationSelectedToo() throws {
        let session = try Self.runningLine()
        let station = try XCTUnwrap(session.world.stations.first?.id)
        session.selectStation(station)
        XCTAssertTrue(session.screenFacts.hasSelection)
        XCTAssertEqual(Self.lookAgain(over: 100, session) { Self.frameReadsBefore(session) }, 100)
        XCTAssertEqual(Self.lookAgain(over: 100, session) { Self.frameReads(session) }, 0)
    }

    /// The facts are what the session works out afresh, after every tick
    /// and every change of the selection, over two game days (the next
    /// steps are worked out once a day).
    func testTheFactsAreWhatTheSessionWorksOut() throws {
        let session = try Self.runningLine()
        XCTAssertNotNil(session.nextSteps)
        let station = try XCTUnwrap(session.world.stations.first?.id)
        func check(_ step: String, line: UInt = #line) {
            let fresh = ScreenFacts(
                realWorldFrame: RealWorldFrame(world: session.world), nextSteps: session.nextSteps, hasSelection: session.selectionText() != nil,
                showsGoals: session.world.scenario != nil || session.world.hasCityRequests || session.nextSteps != nil,
                showsTourism: session.world.hasTourism
            )
            XCTAssertEqual(session.screenFacts, fresh, step, line: line)
        }
        check("a new session")
        session.setSpeed(.fast)
        for tick in 0..<300 {
            if tick == 50 { session.selectStation(station) }
            if tick == 150 { session.clearSelection() }
            session.advance(realElapsed: GameSession.tickInterval)
            check("tick \(tick)")
        }
    }

    /// A line with its train running at the opening speed (600×).
    static func runningLine() throws -> GameSession {
        let metre = WorldCoordinate.unitsPerMetre
        let world = try newGameLine(through: (0..<4).map { PlanPoint(x: (1_000 + $0 * 1_500) * metre, y: 4_000 * metre) })
        let session = GameSession(world: world)
        session.setSpeed(.normal)
        return session
    }

    /// How many of `ticks` ticks change something `reads` read.
    static func lookAgain(over ticks: Int, _ session: GameSession, reads: () -> Void) -> Int {
        final class Flag: @unchecked Sendable { var raised = false }
        var count = 0
        for _ in 0..<ticks {
            let flag = Flag()
            withObservationTracking(reads) { flag.raised = true }
            session.advance(realElapsed: GameSession.tickInterval)
            if flag.raised { count += 1 }
        }
        return count
    }
}
