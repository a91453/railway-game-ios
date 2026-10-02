import GameCore
import GamePresentation
import XCTest

/// Stage C4: the demo map is built on the track network only (Stage F1),
/// with ordinary commands, and runs at once: both lines send their trains
/// out, passengers ride and fares are charged.
final class DemoWorldTests: XCTestCase {
    func testTheDemoMapIsBuiltOnTheNetworkWithStationsAtPoints() {
        let world = DemoWorld.make(in: .english)
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertTrue(world.stations.allSatisfy { $0.point != nil && $0.tiles.isEmpty }, "no station takes a tile")
        XCTAssertTrue(world.tracks.isEmpty, "no grid track")
        XCTAssertEqual(world.network.edges.map(\.structure), [.surface, .elevated])
        let central = world.stations[1].id
        XCTAssertEqual(world.trackPlatforms(of: central).map(\.edge), [.edge(1), .edge(2)], "a platform on each line")
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
