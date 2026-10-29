@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 479: the Sanying Line is bought with the Sanxia depot where
/// the real one is, between Hengxi and Longpu. The four trains the real
/// timetable leaves overnight on the main track at stations between the
/// ends stand in it instead, and run out empty for the morning's first
/// runs: on 94 they stood in the way of the first through trains, and
/// the line's trains waited for each other every morning.
@MainActor
final class SanyingDepotTests: XCTestCase {
    func testTheLineIsBoughtWithItsRealDepotAndTheMorningRunsClear() async throws {
        let session = try RealLineAcquisitionTests.game(round: "sanying:LB", side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "sanying:LB" })
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depot = try XCTUnwrap(acquisition.depot)
        XCTAssertEqual(depot.platforms.count, RealLineDepotSite.sanxia.sidings)
        XCTAssertEqual(acquisition.trains.count, 12)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let station = try XCTUnwrap(world.stations.first(where: \.isDepot))
        XCTAssertEqual(station.name, "三峽機廠")
        let bought = try XCTUnwrap(world.lines.first)
        XCTAssertEqual(bought.depots, [station.id])
        // Where the real one is: within 300 m of the real yard's middle.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let site = RealLineDepotSite.sanxia
        let real = WorldVector(frame.worldPosition(
            latitude: (site.yard.start.latitude + site.yard.end.latitude) / 2, longitude: (site.yard.start.longitude + site.yard.end.longitude) / 2
        ))
        XCTAssertLessThan((WorldVector(station.location) - real).length, 300 * RealLineAcquisition.metre)
        // The real timetable's runs, but its positioning runs to and from
        // the stations between the ends.
        let runs = try XCTUnwrap(session.railways?.metroRuns["sanying:LB"])
        XCTAssertEqual(bought.runs.count, runs.runs.count { $0.train != "回送" })
        // Overnight: four in the depot, the rest at the ends.
        let ends = Set([bought.stops[0], bought.stops[bought.stops.count - 1]])
        func standing(at id: StationID) -> Int { world.trains.count { world.stationsStoppedAt(by: $0.id).contains(id) } }
        XCTAssertEqual(standing(at: station.id), 4)
        XCTAssertEqual(ends.reduce(0) { $0 + standing(at: $1) }, 8)

        // Through the first morning: every train out of the depot but the
        // one the timetable does not need, and none waiting for another.
        session.setSpeed(.fast)
        var deadlocked = 0
        while session.world.clock.now.seconds < 7 * GameTime.secondsPerHour {
            _ = try await FiftyStationFreezeTests.tick(session)
            deadlocked = max(deadlocked, session.world.deadlockedTrains().count)
        }
        XCTAssertEqual(deadlocked, 0)
        XCTAssertLessThanOrEqual(session.world.trains.count { session.world.stationsStoppedAt(by: $0.id).contains(station.id) }, 1)
    }
}
