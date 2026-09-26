import GameCore
import XCTest

final class StationAndTrainTests: XCTestCase {
    func testBuildingStationRecordsItAndChargesCost() throws {
        var world = try makeWorld(balance: 10_000)
        let position = GridPosition(x: 2, y: 5)

        let station = try world.buildStation(named: "Central", at: position)

        XCTAssertEqual(station.name, "Central")
        XCTAssertEqual(station.position, position)
        XCTAssertEqual(world.stations, [station])
        XCTAssertEqual(world.station(id: station.id), station)
        XCTAssertEqual(world.station(at: position), station)
        XCTAssertEqual(world.map.tile(at: position)?.type, .station(id: station.id))
        XCTAssertEqual(world.economy.balance, 9_000)
    }

    func testStationIDsAreUniqueAndNotReusedAfterFailures() throws {
        var world = try makeWorld(balance: 10_000)

        let first = try world.buildStation(named: "A", at: GridPosition(x: 0, y: 0))
        XCTAssertThrowsError(try world.buildStation(named: "Dup", at: GridPosition(x: 0, y: 0)))
        let second = try world.buildStation(named: "B", at: GridPosition(x: 1, y: 0))
        let third = try world.buildStation(named: "C", at: GridPosition(x: 2, y: 0))

        let ids = [first.id, second.id, third.id]
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(ids, ids.sorted())
    }

    func testStationCannotOverlapTrack() throws {
        var world = try makeWorld()
        let position = GridPosition(x: 4, y: 4)
        try world.buildTrack(at: position, connections: [.east, .west])
        let before = world

        XCTAssertThrowsGameError(try world.buildStation(named: "Central", at: position), .tileOccupied(position))
        XCTAssertEqual(world, before)
    }

    func testStationFailuresLeaveWorldUnchanged() throws {
        var world = try makeWorld(width: 5, height: 5, balance: 999)
        let before = world

        XCTAssertThrowsGameError(
            try world.buildStation(named: "Central", at: GridPosition(x: 1, y: 1)),
            .insufficientFunds(required: 1_000, available: 999)
        )
        XCTAssertThrowsGameError(try world.buildStation(named: "  ", at: GridPosition(x: 1, y: 1)), .invalidName)
        XCTAssertThrowsGameError(
            try world.buildStation(named: "Central", at: GridPosition(x: 5, y: 1)),
            .outOfBounds(GridPosition(x: 5, y: 1))
        )
        XCTAssertEqual(world, before)
        XCTAssertTrue(world.stations.isEmpty)
    }

    func testPurchasingTrainsChargesCostAndAssignsUniqueIDs() throws {
        var world = try makeWorld(balance: 12_000)

        let first = try world.purchaseTrain(named: "Local 1")
        let second = try world.purchaseTrain(named: "Local 2")
        let before = world
        XCTAssertThrowsGameError(
            try world.purchaseTrain(named: "Local 3"),
            .insufficientFunds(required: 5_000, available: 2_000)
        )

        XCTAssertEqual(world, before)
        XCTAssertEqual(world.trains, [first, second])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(world.economy.balance, 2_000)
    }
}
