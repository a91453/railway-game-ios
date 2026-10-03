import GameCore
import GamePresentation
import XCTest

/// Stage C4: the demo map is built on the track network only (Stage F1),
/// with ordinary commands, and runs at once: both lines send their trains
/// out, passengers ride and fares are charged. Its stations share
/// platforms on several tracks and levels, round Central and a ring.
final class DemoWorldTests: XCTestCase {
    func testTheDemoMapIsBuiltOnTheNetworkWithStationsAtPoints() {
        let world = DemoWorld.make(in: .english)
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertTrue(world.stations.allSatisfy { $0.point != nil && $0.tiles.isEmpty }, "no station takes a tile")
        XCTAssertTrue(world.tracks.isEmpty, "no grid track")
        // Line 1 on the ground, Line 2 on a viaduct, and the ring's four arcs.
        XCTAssertEqual(world.network.edges.map(\.structure), [.surface, .elevated, .surface, .surface, .surface, .surface])
        let ids = world.stations.map(\.id)
        let platforms = ids.map { world.trackPlatforms(of: $0).map(\.edge) }
        XCTAssertEqual(platforms, [
            [.edge(1), .edge(6)],  // West: Line 1 and the ring, side by side on the ground
            [.edge(1), .edge(2)],  // Central: Line 1 below, Line 2 above
            [.edge(1), .edge(4)],  // East
            [.edge(2), .edge(3)],  // North: Line 2 above, the ring below
            [.edge(2), .edge(5)],  // South
        ])
        // Nothing crosses at its own height: the lines end inside the ring.
        let heights = world.network.nodes.map(\.position.z)
        XCTAssertEqual(heights, [0, 0, 512, 512, 0, 0, 0, 0])
        XCTAssertEqual(WorldRegion.built(in: world).map { ($0.minX + $0.maxX) / 2 }, Double(world.stations[1].location.x), "Central is the middle")
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2"])
        XCTAssertEqual(world.trains.map(\.cars), [4, 4])
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
        XCTAssertLessThan(world.economy.balance, GameWorld.newGame().economy.balance, "it paid for what it built")

        let chinese = DemoWorld.make(in: .traditionalChinese)
        XCTAssertEqual(chinese.stations.map(\.name), ["西站", "中央", "東站", "北站", "南站"])
        XCTAssertEqual(chinese.lines.map(\.name), ["1 號線", "2 號線"])
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
    }
}
