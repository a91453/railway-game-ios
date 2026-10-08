import Foundation
import GameCore
import XCTest

/// Stage F3d: the world's bounds, in world units. A point is in the world
/// when `0 <= x < width` and `0 <= y < height`; there are no cells.
final class WorldBoundsTests: XCTestCase {
    func testBoundsHaveTheRequestedSizeInWorldUnits() throws {
        let bounds = try WorldBounds(width: 20_480, height: 12_288)
        XCTAssertEqual(bounds.width, 20_480)
        XCTAssertEqual(bounds.height, 12_288)
        XCTAssertEqual(try WorldBounds(width: 1, height: 1).width, 1, "a side need not be a whole tile")
        XCTAssertEqual(try WorldBounds(width: 1_000, height: 333).height, 333)
    }

    /// Off by one at each edge and corner: the first unit outside is out.
    func testContainsIsHalfOpenAtEveryEdgeAndCorner() throws {
        let bounds = try WorldBounds(width: 5_000, height: 3_000)
        let inside = [
            PlanPoint(x: 0, y: 0), PlanPoint(x: 4_999, y: 0), PlanPoint(x: 0, y: 2_999), PlanPoint(x: 4_999, y: 2_999),
            PlanPoint(x: 2_500, y: 0), PlanPoint(x: 0, y: 1_500), PlanPoint(x: 4_999, y: 1_500), PlanPoint(x: 2_500, y: 2_999),
        ]
        for point in inside {
            XCTAssertTrue(bounds.contains(point), "(\(point.x), \(point.y))")
        }
        let outside = [
            PlanPoint(x: -1, y: 0), PlanPoint(x: 0, y: -1), PlanPoint(x: -1, y: -1),
            PlanPoint(x: 5_000, y: 0), PlanPoint(x: 5_000, y: 2_999), PlanPoint(x: 0, y: 3_000), PlanPoint(x: 4_999, y: 3_000),
            PlanPoint(x: 5_000, y: 3_000), PlanPoint(x: -1, y: 3_000), PlanPoint(x: 5_000, y: -1),
            PlanPoint(x: .min, y: 0), PlanPoint(x: 0, y: .max),
        ]
        for point in outside {
            XCTAssertFalse(bounds.contains(point), "(\(point.x), \(point.y))")
        }
    }

    func testInvalidSizesAreRejected() {
        let tooLarge = WorldBounds.maximumSide + 1
        for (width, height) in [(Int64(0), Int64(10)), (10, 0), (-3, 5), (tooLarge, 1), (1, tooLarge), (.min, .max)] {
            XCTAssertThrowsGameError(try WorldBounds(width: width, height: height), .invalidMapSize(width: width, height: height))
        }
    }

    /// The largest world (decision 88) is 2^25 units, 524,288 m, a side,
    /// enough for the whole of Taiwan; the standard one, a new game's
    /// (Stage E1) and the largest until then, 2^20 units, 16,384 m.
    func testTheLargestWorldReachesAcrossTaiwanAndTheStandardOneIsANewGames() throws {
        XCTAssertEqual(WorldBounds.maximumSide, 33_554_432)
        XCTAssertEqual(WorldBounds.maximumSide / WorldCoordinate.unitsPerMetre, 524_288)
        XCTAssertEqual(WorldBounds.maximum, try WorldBounds(width: 33_554_432, height: 33_554_432))
        XCTAssertNoThrow(try WorldBounds(width: 33_554_432, height: 1), "a long, thin world")
        XCTAssertEqual(WorldBounds.standard, try WorldBounds(width: 1_048_576, height: 1_048_576))
        XCTAssertTrue(WorldBounds.standard.contains(PlanPoint(x: 1_048_575, y: 1_048_575)))
        XCTAssertFalse(WorldBounds.standard.contains(PlanPoint(x: 1_048_576, y: 0)))
        XCTAssertTrue(WorldBounds.maximum.contains(PlanPoint(x: 33_554_431, y: 1_048_576)))
        XCTAssertLessThan(WorldBounds.maximumSide, WorldCoordinate.limit, "every point stays inside the geometry's limit")
    }

    func testBoundsRoundTripAndInvalidOnesAreRefusedAsTheyLoad() throws {
        let bounds = try WorldBounds(width: 9_216, height: 2_048)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(bounds)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"height":2048,"width":9216}"#)
        XCTAssertEqual(try JSONDecoder().decode(WorldBounds.self, from: data), bounds)
        for json in [#"{"width":0,"height":5}"#, #"{"width":5,"height":-1}"#, #"{"width":33554433,"height":5}"#, #"{"width":5}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(WorldBounds.self, from: Data(json.utf8)), json)
        }
    }

    /// Track and stations stand at any point, at any angle: nothing about
    /// them falls on a 1024-unit lattice. Track is priced by each 1024 units
    /// of its length (``ConstructionCosts/trackPricingLength``), rounded up.
    func testTrackAndStationsStandAtAnyPointAndAngle() throws {
        var world = try makeWorld(width: 5_000, height: 3_000, balance: 100_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 7, y: 2_993))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 4_993, y: 11))
        let before = world.economy.balance
        let edge = try world.buildTrackEdge(from: a, to: b)
        let length = try XCTUnwrap(world.trackEdge(edge)?.length)
        XCTAssertEqual(length, 5_810, "5809.69 between the nodes, to the nearest unit")
        XCTAssertEqual(before.amount - world.economy.balance.amount, 6 * 100, "six lengths of 1024 or part of one")
        let station = try world.buildStation(named: "Askew", at: PlanPoint(x: 2_501, y: 1_499))
        try world.addTrackPlatform(station.id, on: edge, from: 1_001, to: 3_003)
        XCTAssertEqual(world.station(id: station.id)?.point, PlanPoint(x: 2_501, y: 1_499))
        XCTAssertEqual(world.trackPlatforms(of: station.id).map(\.start), [1_001])
        XCTAssertEqual(world.station(near: PlanPoint(x: 2_502, y: 1_499), within: 1)?.id, station.id)
        XCTAssertNil(world.station(near: PlanPoint(x: 2_503, y: 1_499), within: 1))
    }

    /// The world's commands use the same bounds: a node or station at the
    /// last unit inside is built, one a unit beyond is refused.
    func testCommandsUseTheBoundsToTheUnit() throws {
        var world = try makeWorld(width: 5_000, height: 3_000, balance: 100_000)
        XCTAssertNoThrow(try world.buildTrackNode(at: WorldCoordinate(x: 4_999, y: 2_999)))
        XCTAssertNoThrow(try world.buildTrackNode(at: WorldCoordinate(x: 0, y: 0)))
        XCTAssertNoThrow(try world.buildStation(named: "Corner", at: PlanPoint(x: 4_999, y: 2_999)))
        let before = world
        XCTAssertThrowsGameError(try world.buildTrackNode(at: WorldCoordinate(x: 5_000, y: 0)), .invalidTrackGeometry)
        XCTAssertThrowsGameError(try world.buildTrackNode(at: WorldCoordinate(x: 0, y: 3_000)), .invalidTrackGeometry)
        XCTAssertThrowsGameError(try world.buildStation(named: "East", at: PlanPoint(x: 5_000, y: 2_999)), .outOfBounds(PlanPoint(x: 5_000, y: 2_999)))
        XCTAssertThrowsGameError(try world.buildStation(named: "South", at: PlanPoint(x: 4_999, y: 3_000)), .outOfBounds(PlanPoint(x: 4_999, y: 3_000)))
        XCTAssertEqual(world, before)
    }
}
