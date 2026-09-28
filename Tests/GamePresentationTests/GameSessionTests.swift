import GameCore
import GamePresentation
import XCTest

// GameSession is main-actor isolated. Test methods hop onto the main actor
// with `MainActor.run` instead of isolating the XCTestCase subclass, which
// Swift 6.0 on Linux rejects under -warnings-as-errors.
final class GameSessionTests: XCTestCase {
    func testSessionOwnsTheWorldItWasGiven() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            XCTAssertEqual(session.world, world)
            XCTAssertNil(session.selection)
        }
    }

    // MARK: - Selection

    func testSelectingATileExposesItsCurrentContents() async throws {
        var world = try makeWorld()
        try world.buildTrack(at: GridPosition(x: 2, y: 1), connections: [.east, .west])
        await MainActor.run { [world] in
            let session = GameSession(world: world)

            session.select(GridPosition(x: 2, y: 1))

            XCTAssertEqual(session.selection, GridPosition(x: 2, y: 1))
            XCTAssertEqual(session.selectedTile?.type, .track(connections: [.east, .west]))
            XCTAssertEqual(session.world, world)
        }
    }

    func testSelectingOutsideTheMapKeepsThePreviousSelection() async throws {
        let world = try makeWorld(width: 8, height: 6)
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(GridPosition(x: 7, y: 5))

            session.select(GridPosition(x: 8, y: 5))
            session.select(GridPosition(x: 7, y: 6))
            session.select(GridPosition(x: -1, y: 0))

            XCTAssertEqual(session.selection, GridPosition(x: 7, y: 5))
        }
    }

    func testClearingTheSelection() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(GridPosition(x: 1, y: 1))

            session.clearSelection()

            XCTAssertNil(session.selection)
            XCTAssertNil(session.selectedTile)
        }
    }

    func testMovingTheSelectionStaysInsideTheMap() async throws {
        let world = try makeWorld(width: 3, height: 2)
        await MainActor.run {
            let session = GameSession(world: world)

            session.moveSelection(.east)
            XCTAssertEqual(session.selection, GridPosition(x: 0, y: 0), "starts at the north-west corner")

            session.moveSelection(.north)
            session.moveSelection(.west)
            XCTAssertEqual(session.selection, GridPosition(x: 0, y: 0))

            session.moveSelection(.east)
            session.moveSelection(.east)
            session.moveSelection(.east)
            session.moveSelection(.south)
            session.moveSelection(.south)
            XCTAssertEqual(session.selection, GridPosition(x: 2, y: 1))
        }
    }
}
