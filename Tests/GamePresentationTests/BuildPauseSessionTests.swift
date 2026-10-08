import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 99: the tools that build pause a running game, so
/// an edit made with them can still be undone (decision 82 empties the
/// history as soon as game time moves). Leaving them resumes the game if
/// the session paused it and the player has not touched the speed since.
@MainActor
final class BuildPauseSessionTests: XCTestCase {
    private func makeSession(speed: GameSpeed) throws -> GameSession {
        var world = try makeWorld(balance: 20_000, speed: speed)
        try world.buildStation(named: "West", at: PlanPoint(x: 1_024, y: 1_024))
        return GameSession(world: world)
    }

    func testTheBuildingToolsPauseAndPausesGameSaysWhich() {
        XCTAssertEqual(ConstructionTool.allCases.filter(\.pausesGame), [.network, .building])
    }

    func testChoosingTheNetworkToolPausesAndLeavingItResumesAtTheSameSpeed() throws {
        let session = try makeSession(speed: .double)
        session.selectTool(.network)
        XCTAssertTrue(session.world.clock.isPaused)
        XCTAssertTrue(session.isPausedForBuilding)
        XCTAssertEqual(session.message?.kind, .success, "the player is told why time stopped")

        session.selectTool(.building)
        XCTAssertTrue(session.world.clock.isPaused, "still building")
        XCTAssertTrue(session.isPausedForBuilding)

        session.selectTool(.train)
        XCTAssertFalse(session.world.clock.isPaused)
        XCTAssertEqual(session.world.clock.speed, .double)
        XCTAssertFalse(session.isPausedForBuilding)
    }

    func testAGameAlreadyPausedStaysPausedAfterLeavingTheTool() throws {
        let session = try makeSession(speed: .paused)
        session.selectTool(.building)
        XCTAssertFalse(session.isPausedForBuilding, "the player paused it")
        XCTAssertNil(session.message)
        session.selectTool(.select)
        XCTAssertTrue(session.world.clock.isPaused)
    }

    func testThePlayersSpeedChoiceWhileBuildingIsKept() throws {
        let resumed = try makeSession(speed: .normal)
        resumed.selectTool(.network)
        resumed.togglePause()
        XCTAssertFalse(resumed.world.clock.isPaused, "play while building runs the game")
        XCTAssertFalse(resumed.isPausedForBuilding)
        resumed.selectTool(.select)
        XCTAssertFalse(resumed.world.clock.isPaused)
        resumed.selectTool(.building)
        XCTAssertTrue(resumed.world.clock.isPaused, "choosing a building tool pauses a running game again")

        let paused = try makeSession(speed: .normal)
        paused.selectTool(.network)
        paused.togglePause()
        paused.togglePause()
        paused.selectTool(.select)
        XCTAssertTrue(paused.world.clock.isPaused, "the player paused it last")

        let faster = try makeSession(speed: .normal)
        faster.selectTool(.network)
        faster.setSpeed(.double)
        faster.selectTool(.select)
        XCTAssertEqual(faster.world.clock.speed, .double)
    }

    func testAnEditMadeWithABuildingToolCanStillBeUndoneAfterRealTimePasses() throws {
        let session = try makeSession(speed: .normal)
        session.selectTool(.building)
        session.purchaseTrain()
        XCTAssertEqual(session.undoCount, 1)
        session.advance(realElapsed: .seconds(5))
        XCTAssertEqual(session.undoCount, 1, "no game time passed")
        XCTAssertTrue(session.canUndo)

        session.selectTool(.select)
        session.advance(realElapsed: .milliseconds(100))
        XCTAssertEqual(session.undoCount, 0, "the game runs again: one tick empties the history")
    }
}
