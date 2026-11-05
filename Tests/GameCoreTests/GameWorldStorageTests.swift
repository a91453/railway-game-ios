import Foundation
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

    /// A save with trains running on lines: the tick touches dozens of the
    /// fields and the caches that are not game state.
    private func runningWorld() throws -> GameWorld {
        let save = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v8-demo-siding-90-minutes.json")
        let world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: save)).world
        XCTAssertFalse(world.trains.isEmpty)
        return world
    }

    private static func encoded(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(world)
    }

    func testRunningACopyLeavesTheWorldItCameFromByteForByte() throws {
        let world = try runningWorld()
        let before = try Self.encoded(world)
        var copy = world
        try copy.advance(ticks: 50)
        XCTAssertNotEqual(copy.clock.now, world.clock.now)
        XCTAssertEqual(try Self.encoded(world), before)

        // Two copies run alike end alike.
        var one = world, other = world
        try one.advance(ticks: 30)
        try other.advance(ticks: 30)
        XCTAssertEqual(one, other)
        XCTAssertEqual(try Self.encoded(one), try Self.encoded(other))
    }

    func testCopiesRunOnSeveralThreadsAsOnOne() throws {
        let world = try runningWorld()
        let before = try Self.encoded(world)
        var alone = world
        try alone.advance(ticks: 20)
        let expected = try Self.encoded(alone)

        final class Results: @unchecked Sendable {
            let lock = NSLock()
            var data: [Int: Data] = [:]
        }
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            var copy = world
            let data = (try? copy.advance(ticks: 20)).flatMap { try? Self.encoded(copy) } ?? Data()
            results.lock.lock()
            results.data[index] = data
            results.lock.unlock()
        }
        XCTAssertEqual(results.data.count, 8)
        for index in 0..<8 { XCTAssertEqual(results.data[index], expected, "thread \(index)") }
        XCTAssertEqual(try Self.encoded(world), before)
    }

    func testAWorldComesBackFromItsSaveEqual() throws {
        var world = try runningWorld()
        try world.advance(ticks: 10)
        let decoded = try JSONDecoder().decode(GameWorld.self, from: try Self.encoded(world))
        XCTAssertEqual(try Self.encoded(decoded), try Self.encoded(world))
    }
}
