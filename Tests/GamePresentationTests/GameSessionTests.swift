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

    func testSelectingATilePicksTheStationInsideIt() async throws {
        var world = try makeWorld()
        let station = try world.buildStation(named: "Central", at: PlanPoint(x: 2_300, y: 1_100))
        await MainActor.run { [world] in
            let session = GameSession(world: world)

            session.select(GridPosition(x: 2, y: 1))
            XCTAssertEqual(session.selection, GridPosition(x: 2, y: 1))
            XCTAssertEqual(session.selectedStation?.id, station.id, "the station stands inside the tile")

            session.select(GridPosition(x: 3, y: 1))
            XCTAssertEqual(session.selection, GridPosition(x: 3, y: 1))
            XCTAssertNil(session.selectedStation)
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
            XCTAssertNil(session.selectedStation)
        }
    }
}
