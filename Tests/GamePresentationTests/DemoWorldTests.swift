import Foundation
import GameCore
import GamePresentation
import XCTest

/// Stage C4: the demo map is built on the track network only (Stage F1),
/// with ordinary commands, and runs at once: every line sends its trains
/// out, the ring one each way round (decision 49), passengers ride and
/// fares are charged. Its stations share platforms on several tracks and
/// levels, round Central and a double ring.
final class DemoWorldTests: XCTestCase {
    /// Phase 5F: a new game routes passengers over the whole network, so on
    /// the demo they change between Line 1, Line 2 and the ring.
    func testNewGamesRoutePassengersOverTheNetworkAndTheyChangeTrains() throws {
        XCTAssertEqual(GameWorld.newGame().passengerRoutingMode, .network)
        XCTAssertTrue(GameWorld.newGame().weeklyDemand, "Item 4: weekdays and weekends differ")
        var world = DemoWorld.make(in: .english)
        XCTAssertEqual(world.passengerRoutingMode, .network)
        let west = try XCTUnwrap(world.stations.first { $0.name == "West" }).id
        let north = try XCTUnwrap(world.stations.first { $0.name == "North" }).id
        // West is on Line 1 and the ring, North on Line 2 and the ring: no
        // single line of the two crossing ones takes West to North, but the
        // ring or a change at Central does.
        XCTAssertFalse(world.passengerRoutes(from: west, to: north).isEmpty)
        var changed = false
        for _ in 0..<240 {
            try world.advance(ticks: 1)
            if world.passengers.contains(where: { record in
                record.waiting.contains { ($0.journey?.current ?? 0) > 0 }
            }) {
                changed = true
                break
            }
        }
        XCTAssertTrue(changed, "Some passengers wait to change trains")
        for station in world.stations {
            let ledger = world.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        }
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testTheDemoMapIsBuiltOnTheNetworkWithStationsAtPoints() throws {
        let world = DemoWorld.make(in: .english)
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertTrue(world.stations.allSatisfy { world.bounds.contains($0.point) }, "every station stands at a point in the world")
        // Line 1 on the ground, Line 2 on a viaduct, and the four arcs of
        // each ring track: edges 3 to 6 the inner, 7 to 10 the outer.
        XCTAssertEqual(world.network.edges.map(\.structure), [.surface, .elevated] + Array(repeating: .surface, count: 8))
        let ids = world.stations.map(\.id)
        let platforms = ids.map { world.trackPlatforms(of: $0).map(\.edge) }
        XCTAssertEqual(platforms, [
            [.edge(1), .edge(6), .edge(10)],  // West: Line 1 and both ring tracks, side by side on the ground
            [.edge(1), .edge(2)],  // Central: Line 1 below, Line 2 above
            [.edge(1), .edge(4), .edge(8)],  // East
            [.edge(2), .edge(3), .edge(7)],  // North: Line 2 above, the ring below
            [.edge(2), .edge(5), .edge(9)],  // South
        ])
        // Nothing crosses at its own height: the lines end inside the ring.
        let heights = world.network.nodes.map(\.position.z)
        XCTAssertEqual(heights, [0, 0, 512, 512] + Array(repeating: 0, count: 8))
        // Central is the middle of the map and of what the demo builds
        // (UI_INTERFACES: UI tests may rely on it).
        XCTAssertEqual(world.stations[1].point, PlanPoint(x: 512 * 1_024, y: 512 * 1_024))
        let built = try XCTUnwrap(WorldRegion.built(in: world))
        XCTAssertEqual((built.minX + built.maxX) / 2, Double(world.stations[1].location.x), "Central is the middle")
        XCTAssertEqual((built.minY + built.maxY) / 2, Double(world.stations[1].location.y), "Central is the middle")
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2", "Ring Line"])
        XCTAssertEqual(world.lines.map(\.isRing), [false, false, true])
        XCTAssertEqual(world.trains.map(\.cars), [4, 4, 2, 2])
        // The ring from West round North, East and South; its first train
        // the inner way, its second the outer, both at West's platforms.
        let ring = world.lines[2]
        XCTAssertEqual(ring.stops, [ids[0], ids[3], ids[2], ids[4]])
        XCTAssertEqual(ring.trains.map { ring.ringDirection(of: $0) }, [.inner, .outer])
        XCTAssertEqual(ring.trainsInService, TrainsInService(peak: 2, offPeak: 2, low: 2))
        for id in ring.trains {
            XCTAssertTrue(world.stationsStoppedAt(by: id).contains(ids[0]), "train \(id.rawValue) stands at West")
        }
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
        XCTAssertLessThan(world.economy.balance, GameWorld.newGame().economy.balance, "it paid for what it built")

        let chinese = DemoWorld.make(in: .traditionalChinese)
        XCTAssertEqual(chinese.stations.map(\.name), ["西站", "中央", "東站", "北站", "南站"])
        XCTAssertEqual(chinese.lines.map(\.name), ["1 號線", "2 號線", "環狀線"])
        XCTAssertEqual(chinese.trains.map(\.name), ["列車 1", "列車 2", "環狀線列車 1", "環狀線列車 2"])
    }

    func testTheDemoMapRunsAtOnce() throws {
        var world = DemoWorld.make(in: .english)
        // A tick is a game minute at the demo's normal speed: three hours.
        try world.advance(ticks: 180)
        // A station's ledger counts the passengers who set out from it.
        let west = world.passengerLedger(of: world.stations[0].id)
        let north = world.passengerLedger(of: world.stations[3].id)
        XCTAssertGreaterThan(west.arrived, 0, "Line 1 carried passengers")
        XCTAssertGreaterThan(north.arrived, 0, "Line 2 carried passengers")
        let fares = world.accounts.entries.flatMap(\.breakdown).filter { $0.item == .fareRevenue }
        XCTAssertGreaterThan(fares.map(\.amount).reduce(Money.zero, +), .zero, "fares were charged")
        // The ring sends a train out each way, round the ring and back to
        // West without turning.
        let ring = world.lines[2]
        XCTAssertNotNil(ring.lastDispatch)
        XCTAssertNotNil(ring.outerLastDispatch)
        let ids = world.stations.map(\.id)
        XCTAssertEqual(world.train(id: ring.trains[0])?.timetable.map(\.station), [0, 3, 2, 4, 0].map { ids[$0] }, "West, North, East, South")
        XCTAssertEqual(world.train(id: ring.trains[1])?.timetable.map(\.station), [0, 4, 2, 3, 0].map { ids[$0] }, "West, South, East, North")
        XCTAssertTrue(ring.trains.allSatisfy { world.train(id: $0)?.timetable.allSatisfy { !$0.reverses } == true })
    }
}
