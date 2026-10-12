import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 184: Redo makes again what Undo (decision 82)
/// took back, the simulator's `past`／`future` stacks. A new edit and a
/// tick of game time end it; the tutorial refuses it as it refuses Undo.
@MainActor
final class RedoSessionTests: XCTestCase {
    private func makeSession(speed: GameSpeed = .paused) throws -> GameSession {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480, speed: speed), language: .english)
        return session
    }

    func testRedoMakesAgainWhatUndoTookBack() throws {
        let session = try makeSession()
        XCTAssertFalse(session.canRedo)
        session.buildingKind = .house
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        let one = session.world
        session.buildingKind = .office
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 10_000, y: 10_000)))
        let two = session.world
        XCTAssertFalse(session.canRedo, "nothing undone yet")

        session.undo()
        session.undo()
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
        XCTAssertEqual(session.redoCount, 2)
        XCTAssertTrue(session.canRedo)
        XCTAssertFalse(session.canUndo)

        session.redo()
        XCTAssertEqual(session.world, one)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Redid the edit."))
        session.redo()
        XCTAssertEqual(session.world, two, "money and all")
        XCTAssertEqual(session.undoCount, 2, "each redone edit can be undone again")
        XCTAssertFalse(session.canRedo)

        session.redo()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Nothing to redo."))
        XCTAssertEqual(session.world, two)
    }

    func testANewEditEndsRedo() throws {
        let session = try makeSession()
        session.buildingKind = .house
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.placeBuilding(at: PlanPoint(x: 10_000, y: 10_000))
        XCTAssertFalse(session.canRedo, "the simulator's push clears the future")
        XCTAssertEqual(session.redoCount, 0)
    }

    func testAnEditThatChangesNothingKeepsRedo() throws {
        let session = try makeSession()
        session.buildingKind = .house
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        session.placeBuilding(at: PlanPoint(x: 10_000, y: 10_000))
        session.undo()
        // Refused: stands on the first building. No edit, nothing lost.
        XCTAssertFalse(session.placeBuilding(at: PlanPoint(x: 5_500, y: 5_000)))
        XCTAssertTrue(session.canRedo)
    }

    func testGameTimeEndsRedoAndRedoKeepsTheSpeed() throws {
        let session = try makeSession(speed: .normal)
        session.buildingKind = .house
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        session.togglePause()
        session.undo()
        session.togglePause()
        XCTAssertFalse(session.world.clock.isPaused)
        session.redo()
        XCTAssertFalse(session.world.clock.isPaused, "Redo keeps the clock as the player has it")
        XCTAssertEqual(session.world.placedBuildings.count, 1)
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.advance(realElapsed: .milliseconds(100))
        XCTAssertFalse(session.canRedo, "a tick empties it, as it empties Undo")
        XCTAssertEqual(session.redoCount, 0)
    }

    func testTheMessagesAreInTheSessionsLanguage() throws {
        let session = GameSession(world: try makeWorld(), language: .traditionalChinese)
        session.redo()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "沒有可重做的編輯。"))
    }
}
