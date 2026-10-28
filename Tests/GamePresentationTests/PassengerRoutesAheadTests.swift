@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 470: the routes of a new passenger plan worked out ahead, on
/// every core, change nothing the tick makes; the tick then works none out.
final class PassengerRoutesAheadTests: XCTestCase {
    func testRoutesWorkedOutAheadGiveTheSameTick() async throws {
        var world = DemoWorld.make(in: .english)
        world.setSpeed(.fast)
        for round in 0..<2 {
            XCTAssertFalse(world.passengerRoutesToWorkOut()?.origins.isEmpty ?? true, "round \(round)")
            // The demo has fewer stations than the app works out ahead.
            let given = await PassengerRoutesAhead.given(to: world, minimumOrigins: 1)
            XCTAssertGreaterThan(given.passengerRouteCache.pairs, world.passengerRouteCache.pairs, "round \(round)")
            let plain = try GameSession.advanced(world, by: 1, listening: false).world
            let ahead = try GameSession.advanced(given, by: 1, listening: false).world
            XCTAssertEqual(ahead, plain, "round \(round)")
            XCTAssertEqual(ahead.passengers, plain.passengers, "round \(round)")
            XCTAssertEqual(ahead.riders, plain.riders, "round \(round)")
            XCTAssertEqual(ahead.passengerRouteCache.pairs, given.passengerRouteCache.pairs,
                           "round \(round): the tick asked no route that was not worked out ahead")
            XCTAssertNil(ahead.passengerRoutesToWorkOut(), "round \(round): the plan is current")
            // An edit to the lines: the plan and its routes start again.
            world = plain
            try world.removeLine(try XCTUnwrap(world.lines.last).id)
        }
    }
}
