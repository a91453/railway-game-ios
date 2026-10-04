import GameCore
import XCTest

/// Building stations and buying trains. Stations stand at points since
/// Stage F3c (a station on tiles went with the grid); the tile under a
/// point is what an out-of-bounds error names.
final class StationAndTrainTests: XCTestCase {
    func testBuildingStationRecordsItAndChargesCost() throws {
        var world = try makeWorld(balance: 10_000)
        let point = PlanPoint(x: 2_560, y: 5_632)

        let station = try world.buildStation(named: "Central", at: point)

        XCTAssertEqual(station.name, "Central")
        XCTAssertEqual(station.location, point)
        XCTAssertEqual(world.stations, [station])
        XCTAssertEqual(world.station(id: station.id), station)
        XCTAssertEqual(world.economy.balance, 9_000)
    }

    func testStationIDsAreUniqueAndNotReusedAfterFailures() throws {
        var world = try makeWorld(width: 5_120, height: 5_120, balance: 10_000)

        let first = try world.buildStation(named: "A", at: PlanPoint(x: 512, y: 512))
        XCTAssertThrowsError(try world.buildStation(named: "Off", at: PlanPoint(x: 5_120, y: 512)))
        let second = try world.buildStation(named: "B", at: PlanPoint(x: 512, y: 512))
        let third = try world.buildStation(named: "C", at: PlanPoint(x: 2_560, y: 512))

        let ids = [first.id, second.id, third.id]
        XCTAssertEqual(ids.map(\.rawValue), [1, 2, 3])
    }

    func testStationFailuresLeaveWorldUnchanged() throws {
        var world = try makeWorld(width: 5_120, height: 5_120, balance: 999)
        let before = world

        XCTAssertThrowsGameError(
            try world.buildStation(named: "Central", at: PlanPoint(x: 1_536, y: 1_536)),
            .insufficientFunds(required: 1_000, available: 999)
        )
        XCTAssertThrowsGameError(try world.buildStation(named: "  ", at: PlanPoint(x: 1_536, y: 1_536)), .invalidName)
        XCTAssertThrowsGameError(
            try world.buildStation(named: "Central", at: PlanPoint(x: 5_632, y: 1_536)),
            .outOfBounds(PlanPoint(x: 5_632, y: 1_536))
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
