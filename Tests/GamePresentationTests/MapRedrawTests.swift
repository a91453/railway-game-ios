import GameCore
@testable import GamePresentation
import XCTest

/// Decision 371: a tick that only moves the trains, the track they have
/// reserved and the people waiting redraws neither the railway nor the
/// stations' names; an edit of the railway redraws both.
@MainActor
final class MapRedrawTests: XCTestCase {
    func testATickRedrawsNeitherTheRailwayNorTheNames() throws {
        let metre = WorldCoordinate.unitsPerMetre
        // Through the new game's towns (FeatureUITestWorld's big grid), so
        // passengers come to wait.
        var start = GameWorld.newGame()
        start.setUnlimitedFunds(true)
        let world = try newGameLine(through: (0..<11).map { PlanPoint(x: (3_000 + $0 * 700) * metre, y: 8_000 * metre) }, in: start)
        XCTAssertTrue(world.isTrafficControlEnabled)
        let session = GameSession(world: world)
        session.setSpeed(.x60)
        var last = MapRedrawCount.Inputs(session)
        var trafficChanges = 0, countChanges = 0
        for _ in 0..<600 {
            session.advance(realElapsed: GameSession.tickInterval)
            let now = MapRedrawCount.Inputs(session)
            if now.traffic != last.traffic { trafficChanges += 1 }
            if now.waiting != last.waiting { countChanges += 1 }
            XCTAssertTrue(MapRedraw.sameRailway(last.world, now.world))
            XCTAssertTrue(MapRedraw.sameNames(last.world, now.world))
            last = now
        }
        // What the test is about: the ticks did change what is over them.
        XCTAssertGreaterThan(trafficChanges, 0)
        XCTAssertGreaterThan(countChanges, 0)
    }

    func testAnEditRedrawsTheRailwayTheStationsAndTheNames() throws {
        let metre = WorldCoordinate.unitsPerMetre
        let world = try newGameLine(through: [PlanPoint(x: 1_000 * metre, y: 4_000 * metre), PlanPoint(x: 3_000 * metre, y: 4_000 * metre)])
        var track = world
        _ = try track.buildTrackNode(at: WorldCoordinate(x: 2_000 * metre, y: 6_000 * metre))
        XCTAssertFalse(MapRedraw.sameRailway(world, track))
        XCTAssertFalse(MapRedraw.sameStations(world, track, comparesLand: false))
        XCTAssertFalse(MapRedraw.sameNames(world, track))
        var station = world
        _ = try station.buildStation(named: "D", at: PlanPoint(x: 2_000 * metre, y: 6_000 * metre))
        XCTAssertFalse(MapRedraw.sameRailway(world, station))
        XCTAssertFalse(MapRedraw.sameStations(world, station, comparesLand: false))
        XCTAssertFalse(MapRedraw.sameNames(world, station))
    }

    /// The trains glide at no more than 30 frames a second, and a camera
    /// following one at no more than 60.
    func testTheGlidesFrameRates() {
        XCTAssertEqual(MapGlide.minimumInterval, 1.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(MapGlide.followMinimumInterval, 1.0 / 60, accuracy: 1e-12)
    }
}
