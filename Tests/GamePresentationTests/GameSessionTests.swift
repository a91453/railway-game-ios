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
            XCTAssertNil(session.selectedPoint)
        }
    }

    // MARK: - Selection (Stage F3d: points, never tiles)

    /// A tap keeps its point exactly and picks a station only by distance:
    /// the old 1024-unit tile under the tap no longer decides anything.
    func testATapKeepsItsPointAndPicksTheStationWithinReach() async throws {
        var world = try makeWorld()
        let station = try world.buildStation(named: "Central", at: PlanPoint(x: 2_300, y: 1_100))
        await MainActor.run { [world] in
            let session = GameSession(world: world)

            session.tapMap(at: PlanPoint(x: 2_301, y: 1_099), reach: 64)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 2_301, y: 1_099), "the point as tapped, not rounded")
            XCTAssertEqual(session.selectedStation?.id, station.id)

            // Across what was a tile boundary (x 2048), 253 from the station:
            // within reach, so it is picked.
            session.tapMap(at: PlanPoint(x: 2_047, y: 1_100), reach: 300)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 2_047, y: 1_100))
            XCTAssertEqual(session.selectedStation?.id, station.id)

            // Inside what was the station's tile, (2, 1), but about 922 from
            // it: beyond reach, so only the point is selected.
            session.tapMap(at: PlanPoint(x: 2_100, y: 2_000), reach: 64)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 2_100, y: 2_000))
            XCTAssertNil(session.selectedStation)

            session.tapMap(at: PlanPoint(x: 3_100, y: 1_100), reach: 64)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 3_100, y: 1_100))
            XCTAssertNil(session.selectedStation)
            XCTAssertEqual(session.world, world)

            session.selectStation(station.id)
            XCTAssertEqual(session.selectedPoint, station.point, "a station picked by name selects where it stands")
        }
    }

    /// The world is `0 <= x < width`, `0 <= y < height`: its last unit each
    /// way can be tapped, one more cannot, and a tap outside keeps the
    /// selection.
    func testTapsOutsideTheBoundsKeepThePreviousSelection() async throws {
        let world = try makeWorld(width: 8_192, height: 6_144)
        await MainActor.run {
            let session = GameSession(world: world)
            session.tapMap(at: PlanPoint(x: 8_191, y: 6_143), reach: 64)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 8_191, y: 6_143))

            session.tapMap(at: PlanPoint(x: 8_192, y: 6_143), reach: 64)
            session.tapMap(at: PlanPoint(x: 8_191, y: 6_144), reach: 64)
            session.tapMap(at: PlanPoint(x: -1, y: 0), reach: 64)
            session.tapMap(at: PlanPoint(x: 0, y: -1), reach: 64)

            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 8_191, y: 6_143))
            session.tapMap(at: PlanPoint(x: 0, y: 0), reach: 64)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 0, y: 0), "the corner is in the world")
        }
    }

    func testClearingTheSelection() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.tapMap(at: PlanPoint(x: 1_536, y: 1_536), reach: 0)

            session.clearSelection()

            XCTAssertNil(session.selectedPoint)
            XCTAssertNil(session.selectedStation)
        }
    }
}
