import GameCore
import XCTest

final class TrackConstructionTests: XCTestCase {
    private let straight: TrackConnections = [.north, .south]
    private let origin = GridPosition(x: 3, y: 4)

    func testBuildingTrackUpdatesMapAndChargesCost() throws {
        var world = try makeWorld(balance: 10_000)

        let track = try world.buildTrack(at: origin, connections: straight)

        XCTAssertEqual(track, Track(position: origin, connections: straight))
        XCTAssertEqual(world.track(at: origin), track)
        XCTAssertEqual(world.map.tile(at: origin)?.type, .empty, "track lives in the railway network, not on the land")
        XCTAssertEqual(world.tracks, [track])
        XCTAssertEqual(world.economy.balance, 9_900)
    }

    func testBuildingOnOccupiedTileFailsWithoutChanges() throws {
        var world = try makeWorld()
        try world.buildTrack(at: origin, connections: straight)
        try world.buildStation(named: "Central", at: GridPosition(x: 0, y: 0))
        let before = world

        XCTAssertThrowsGameError(
            try world.buildTrack(at: origin, connections: [.east, .west]),
            .tileOccupied(origin)
        )
        XCTAssertThrowsGameError(
            try world.buildTrack(at: GridPosition(x: 0, y: 0), connections: straight),
            .tileOccupied(GridPosition(x: 0, y: 0))
        )
        XCTAssertEqual(world, before)
    }

    func testBuildingOutOfBoundsFailsWithoutChanges() throws {
        var world = try makeWorld(width: 4, height: 4)
        let before = world
        let outside = GridPosition(x: 4, y: 0)

        XCTAssertThrowsGameError(try world.buildTrack(at: outside, connections: straight), .outOfBounds(outside))
        XCTAssertEqual(world, before)
    }

    func testTrackNeedsAtLeastOneConnection() throws {
        var world = try makeWorld()
        let before = world

        XCTAssertThrowsGameError(try world.buildTrack(at: origin, connections: []), .invalidTrackConnections)
        XCTAssertEqual(world, before)
    }

    func testInsufficientFundsLeavesWorldUnchanged() throws {
        var world = try makeWorld(balance: 99)
        let before = world

        XCTAssertThrowsGameError(
            try world.buildTrack(at: origin, connections: straight),
            .insufficientFunds(required: 100, available: 99)
        )
        XCTAssertEqual(world, before)
        XCTAssertNil(world.track(at: origin))
        XCTAssertEqual(world.economy.balance, 99)
    }

    func testBalanceCanBeSpentExactlyToZero() throws {
        var world = try makeWorld(balance: 200)

        try world.buildTrack(at: GridPosition(x: 0, y: 0), connections: straight)
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: straight)

        XCTAssertEqual(world.economy.balance, .zero)
        XCTAssertThrowsGameError(
            try world.buildTrack(at: GridPosition(x: 0, y: 2), connections: straight),
            .insufficientFunds(required: 100, available: .zero)
        )
    }

    func testRemovingTrackEmptiesTileWithoutRefund() throws {
        var world = try makeWorld(balance: 10_000)
        try world.buildTrack(at: origin, connections: straight)

        try world.removeTrack(at: origin)

        XCTAssertNil(world.track(at: origin))
        XCTAssertEqual(world.map.tile(at: origin)?.type, .empty)
        XCTAssertEqual(world.economy.balance, 9_900)
    }

    func testRemovalRejectsEmptyStationAndOutOfBoundsTiles() throws {
        var world = try makeWorld(width: 5, height: 5)
        let stationPosition = GridPosition(x: 1, y: 1)
        try world.buildStation(named: "Central", at: stationPosition)
        let before = world

        XCTAssertThrowsGameError(try world.removeTrack(at: stationPosition), .noTrackToRemove(stationPosition))
        XCTAssertThrowsGameError(try world.removeTrack(at: origin), .noTrackToRemove(origin))
        XCTAssertThrowsGameError(
            try world.removeTrack(at: GridPosition(x: 9, y: 9)),
            .outOfBounds(GridPosition(x: 9, y: 9))
        )
        XCTAssertEqual(world, before)
        XCTAssertNotNil(world.station(at: stationPosition))
    }

    func testConnectionsListDirectionsInFixedOrder() {
        let junction: TrackConnections = [.west, .north, .east]

        XCTAssertEqual(junction.directions, [.north, .east, .west])
        XCTAssertEqual(TrackConnections(.south), .south)
    }
}
