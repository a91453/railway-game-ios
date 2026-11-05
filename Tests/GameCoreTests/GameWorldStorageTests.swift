import XCTest
@testable import GameCore

/// Decision 590, step 2: a world keeps its state on the heap, shared by
/// copies until one changes, so a copy takes little stack (its network and
/// one reference), and copies still behave as independent values that
/// compare by content.
final class GameWorldStorageTests: XCTestCase {
    func testAWorldIsItsNetworkAndOneReference() {
        // The network stays in the world itself (it is read at every
        // step of every train); everything else is behind one reference.
        XCTAssertEqual(MemoryLayout<GameWorld>.size, MemoryLayout<RailwayNetwork>.size + MemoryLayout<Int>.size)
        XCTAssertLessThanOrEqual(MemoryLayout<GameWorld>.size, 128, "a world was 2,032 bytes before decision 590, step 2")
    }

    func testACopyChangesApartFromTheWorldItCameFrom() throws {
        var world = GameWorld(bounds: .standard, economy: fixtureEconomy(balance: 1_000_000_000, costs: testCosts))
        try world.buildStation(named: "A", at: PlanPoint(x: 1_024, y: 4_096))
        let before = world

        var copy = world
        try copy.buildStation(named: "B", at: PlanPoint(x: 65_024, y: 4_096))
        try copy.setTrafficControl(true)

        XCTAssertEqual(world.stations.map { $0.name }, ["A"])
        XCTAssertFalse(world.isTrafficControlEnabled)
        XCTAssertEqual(world, before)
        XCTAssertEqual(copy.stations.map { $0.name }, ["A", "B"])
        XCTAssertTrue(copy.isTrafficControlEnabled)
        XCTAssertNotEqual(copy, world)

        // And the other way round: changing the world leaves the copy.
        try world.buildStation(named: "C", at: PlanPoint(x: 129_024, y: 4_096))
        XCTAssertEqual(copy.stations.map { $0.name }, ["A", "B"])
        XCTAssertEqual(world.stations.map { $0.name }, ["A", "C"])
    }

    func testWorldsCompareByContentNotByStorage() throws {
        func built() throws -> GameWorld {
            var world = GameWorld(bounds: .standard, economy: fixtureEconomy(balance: 1_000_000_000, costs: testCosts))
            try world.buildStation(named: "A", at: PlanPoint(x: 1_024, y: 4_096))
            return world
        }
        let one = try built(), other = try built()
        XCTAssertEqual(one, other)

        var changedBack = one
        try changedBack.setTrafficControl(true)
        try changedBack.setTrafficControl(false)
        XCTAssertEqual(changedBack, one)
    }

    func testAFailedCommandOnACopyLeavesBothAsTheyWere() throws {
        var world = GameWorld(bounds: .standard, economy: fixtureEconomy(balance: 1_000_000_000, costs: testCosts))
        try world.buildStation(named: "A", at: PlanPoint(x: 1_024, y: 4_096))
        let before = world
        var copy = world
        XCTAssertThrowsError(try copy.buildStation(named: "B", at: PlanPoint(x: -1, y: 4_096)))
        XCTAssertEqual(copy, before)
        XCTAssertEqual(world, before)
    }
}
