import Foundation
import GameCore
import XCTest

/// Stage F1: stations built at a point of the world, taking no tile. They
/// have platforms only on the track network, and stops, paths, lines and
/// passengers treat them as any other station.
final class FreeStationTests: XCTestCase {
    private let e1 = TrackEdgeID.edge(1)

    func testAStationAtAPointTakesNoTile() throws {
        var world = try makeWorld(width: 8, height: 4)
        // Two stations over the same tile, (2, 1).
        let central = try world.buildStation(named: "Central", at: PlanPoint(x: 2_600, y: 1_100))
        let annex = try world.buildStation(named: "Annex", at: PlanPoint(x: 2_100, y: 1_500))
        XCTAssertEqual(central, Station(id: StationID(rawValue: 1), name: "Central", point: PlanPoint(x: 2_600, y: 1_100)))
        XCTAssertEqual(central.position, GridPosition(x: 2, y: 1), "the tile under the point")
        XCTAssertEqual(central.location, PlanPoint(x: 2_600, y: 1_100))
        XCTAssertEqual(annex.id, StationID(rawValue: 2))
        XCTAssertEqual(world.economy.balance, Money(10_000 - 2 * 1_000))
        XCTAssertEqual(world.map.tile(at: GridPosition(x: 2, y: 1))?.type, .empty, "the land is unchanged")
        XCTAssertEqual(world.trackPlatforms(of: central.id), [], "no platform until the network gives it one")
    }

    func testAStationAtAPointIsRefusedOffTheMapAndWithoutAName() throws {
        var world = try makeWorld(width: 8, height: 4)
        let before = world
        XCTAssertThrowsGameError(try world.buildStation(named: " ", at: PlanPoint(x: -5, y: 0)), .invalidName)
        XCTAssertThrowsGameError(try world.buildStation(named: "East", at: PlanPoint(x: 8_192, y: 0)), .outOfBounds(GridPosition(x: 8, y: 0)))
        XCTAssertThrowsGameError(try world.buildStation(named: "South", at: PlanPoint(x: 0, y: 4_096)), .outOfBounds(GridPosition(x: 0, y: 4)))
        XCTAssertThrowsGameError(try world.buildStation(named: "West", at: PlanPoint(x: -1, y: 0)), .outOfBounds(GridPosition(x: -1, y: 0)))
        XCTAssertThrowsGameError(try world.buildStation(named: "North", at: PlanPoint(x: 0, y: -1_025)), .outOfBounds(GridPosition(x: 0, y: -2)))
        XCTAssertEqual(world, before)
        // The last unit inside the map is on it.
        XCTAssertNoThrow(try world.buildStation(named: "Corner", at: PlanPoint(x: 8_191, y: 4_095)))

        var poor = try makeWorld(width: 8, height: 4, balance: 999)
        let unchanged = poor
        XCTAssertThrowsGameError(
            try poor.buildStation(named: "Dear", at: PlanPoint(x: 0, y: 0)),
            .insufficientFunds(required: 1_000, available: 999)
        )
        XCTAssertEqual(poor, unchanged, "no ID used, nothing spent")
    }

    /// The nearest station by location, the lowest ID of equally near ones,
    /// and none beyond reach.
    func testTheNearestStationIsFoundByItsLocation() throws {
        var world = try makeWorld(width: 8, height: 4)
        try world.buildStation(named: "Point", at: PlanPoint(x: 2_048, y: 512))
        try world.buildStation(named: "Twin", at: PlanPoint(x: 2_048, y: 1_536))
        XCTAssertEqual(world.station(near: PlanPoint(x: 2_048, y: 600), within: 100)?.name, "Point")
        XCTAssertNil(world.station(near: PlanPoint(x: 2_048, y: 700), within: 100), "188 away")
        XCTAssertEqual(world.station(near: PlanPoint(x: 1_200, y: 512), within: 2_000)?.name, "Point", "848 from Point, about 1330 from Twin")
        // Point and Twin are both 512 from (2048, 1024): the lower ID.
        XCTAssertEqual(world.station(near: PlanPoint(x: 2_048, y: 1_024), within: 512)?.name, "Point")
        XCTAssertNil(world.station(near: PlanPoint(x: 2_048, y: 1_024), within: 511))
        XCTAssertNil(world.station(near: PlanPoint(x: 0, y: 0), within: -1))
    }

    /// A station at a point is served by platforms on the track network:
    /// a path ends at the far end of its platform, a train stops there, and
    /// a line between two such stations carries passengers.
    func testAStationAtAPointIsServedOnTheNetwork() throws {
        var world = try makeWorld(width: 16, height: 4, balance: 100_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 1_024))
        try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 1_536)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 7_168, y: 1_536)).id
        try world.addTrackPlatform(west, on: e1, from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: e1, from: 5_120, to: 7_168)
        XCTAssertEqual(world.trackPlatforms(of: west).map(\.edge), [e1])

        let start = TrainPosition.onEdge(TrackTraversal(edge: e1, direction: .forward), offset: 3_072)
        XCTAssertEqual(world.path(from: start, toStation: east), TrainPath(traversals: [], end: 7_168, distance: 4_096))
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: start)
        try world.setTrainContinuation(train, along: [], stoppingAt: 3_072)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [west])

        try world.createLine(named: "Main", stops: [west, east])
        try world.setStationDemand(west, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(east, to: StationDemand(kind: .office, dailyTrips: 1_000))
        XCTAssertEqual(world.dailyDemand(from: west, to: east), 1_000)
    }

    func testAStationAtAPointIsSavedAsItsPoint() throws {
        var world = try makeWorld(width: 8, height: 4)
        try world.buildStation(named: "Point", at: PlanPoint(x: 2_600, y: 1_100))
        let data = try JSONEncoder().encode(world)
        let stations = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["stations"] as? [[String: Any]])
        XCTAssertEqual(stations[0]["point"] as? [String: Int], ["x": 2_600, "y": 1_100])
        XCTAssertNil(stations[0]["position"], "a point, not a tile")
        XCTAssertNil(stations[0]["annexes"])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
    }

    func testAStationsPointIsCheckedWhenLoaded() throws {
        func decodeStation(_ json: String) throws -> Station {
            try JSONDecoder().decode(Station.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            try decodeStation(#"{"id": 3, "name": "P", "point": {"x": 5, "y": 1030}}"#),
            Station(id: StationID(rawValue: 3), name: "P", point: PlanPoint(x: 5, y: 1_030))
        )
        XCTAssertThrowsError(try decodeStation(#"{"id": 3, "name": "P", "point": {"x": -1, "y": 0}}"#), "off the map")
        XCTAssertThrowsError(try decodeStation(#"{"id": 3, "name": "P", "point": {"x": 0, "y": 0}, "position": {"x": 0, "y": 0}}"#), "both")
        XCTAssertThrowsError(try decodeStation(#"{"id": 3, "name": "P", "point": {"x": 0, "y": 0}, "annexes": []}"#), "annexes too")
        XCTAssertThrowsError(try decodeStation(#"{"id": 3, "name": "P"}"#), "neither")

        // On the world: the point must lie on its map.
        var world = try makeWorld(width: 8, height: 4)
        try world.buildStation(named: "Point", at: PlanPoint(x: 8_000, y: 100))
        let data = try JSONEncoder().encode(world)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let moved = text.replacingOccurrences(of: #""x":8000"#, with: #""x":8192"#)
        XCTAssertNotEqual(moved, text)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(moved.utf8)), "off an 8-tile map")
    }
}
