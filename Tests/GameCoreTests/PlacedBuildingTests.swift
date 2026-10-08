import Foundation
@testable import GameCore
import XCTest

/// Buildings the player places (city building P0-A, ARCHITECTURE decision
/// 92): a square of its kind's size at any point of the world, clear of
/// the world's edge, of other buildings, of track and of stations.
final class PlacedBuildingTests: XCTestCase {
    /// 320 m a side, with money enough for track and stations.
    private func world() throws -> GameWorld {
        try makeWorld(balance: 1_000_000)
    }

    // MARK: - Placing

    func testEachKindIsASquareOfItsSizeNumberedFromOne() throws {
        var world = try world()
        let balance = world.economy.balance
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 1_000, y: 1_000))
        let shop = try world.placeBuilding(.shop, at: PlanPoint(x: 5_000, y: 1_000))
        let office = try world.placeBuilding(.office, at: PlanPoint(x: 10_000, y: 10_001))
        XCTAssertEqual([house, shop, office].map(\.id.rawValue), [1, 2, 3])
        XCTAssertEqual(world.placedBuildings, [house, shop, office])
        XCTAssertEqual(world.placedBuilding(id: shop.id), shop)
        XCTAssertNil(world.placedBuilding(id: PlacedBuildingID(rawValue: 4)))
        // 16, 24 and 32 m (64 units a metre).
        XCTAssertEqual(PlacedBuildingKind.allCases.map(\.side), [1_024, 1_536, 2_048])
        XCTAssertEqual(PlacedBuildingKind.allCases.map(\.use), [.residential, .commercial, .office])
        XCTAssertEqual([house.minX, house.minY, house.maxX, house.maxY], [488, 488, 1_512, 1_512])
        XCTAssertEqual([office.minX, office.minY, office.maxX, office.maxY], [8_976, 8_977, 11_024, 11_025])
        XCTAssertEqual(world.economy.balance, balance, "free in this first step")
        XCTAssertTrue(world.land.isEmpty, "it houses no one yet")
    }

    func testTheWholeSquareMustLieInTheWorld() throws {
        var world = try world()
        let before = world
        for point in [PlanPoint(x: 511, y: 5_000), PlanPoint(x: 5_000, y: 511), PlanPoint(x: 19_969, y: 5_000), PlanPoint(x: 5_000, y: 19_969), PlanPoint(x: -1, y: -1)] {
            XCTAssertThrowsGameError(try world.placeBuilding(.house, at: point), .outOfBounds(point))
            XCTAssertEqual(world, before, "\(point)")
        }
        // Touching the edges is in the world.
        try world.placeBuilding(.house, at: PlanPoint(x: 512, y: 512))
        try world.placeBuilding(.house, at: PlanPoint(x: 19_968, y: 19_968))
    }

    func testBuildingsShareNoGroundButMayTouch() throws {
        var world = try world()
        try world.placeBuilding(.house, at: PlanPoint(x: 2_000, y: 2_000)) // 1,488 ..< 2,512
        try world.placeBuilding(.house, at: PlanPoint(x: 3_024, y: 2_000)) // touches it on the east
        try world.placeBuilding(.house, at: PlanPoint(x: 2_000, y: 3_024)) // and on the south
        let before = world
        // An office over both of the first two names the lower.
        XCTAssertThrowsGameError(try world.placeBuilding(.office, at: PlanPoint(x: 2_512, y: 2_000)), .buildingOverlaps(PlacedBuildingID(rawValue: 1)))
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 3_023, y: 3_023)), .buildingOverlaps(PlacedBuildingID(rawValue: 1))) // a unit over its corner
        XCTAssertEqual(world, before)
        try world.placeBuilding(.house, at: PlanPoint(x: 3_024, y: 3_024)) // only corners touch
        XCTAssertEqual(world.placedBuildings.count, 4)
    }

    func testTrackKeepsItsClearance() throws {
        var world = try world()
        // A straight edge east–west along y = 10,000.
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_000, y: 10_000, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 18_000, y: 10_000, z: 0))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let before = world
        // A house's half side is 512 and the clearance 128: centres 640 or
        // more north or south are clear (2 m exactly is enough), and so is
        // one past the line's end.
        for y: Int64 in [10_000, 9_361, 10_639, 9_500] {
            XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: y)), .buildingOnTrack(edge))
        }
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 1_400, y: 10_000)), .buildingOnTrack(edge)) // over its end
        XCTAssertEqual(world, before)
        try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: 9_360))
        try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: 10_640))
        try world.placeBuilding(.house, at: PlanPoint(x: 1_359, y: 10_000))
        // A diagonal edge passing a square's corner.
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 12_000, y: 2_000, z: 0))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 16_000, y: 6_000, z: 0))
        let diagonal = try world.buildTrackEdge(from: c, to: d)
        // The square round (12,000, 5,000) reaches 12,640 east and 4,360
        // north with its clearance; the line y = x − 10,000 passes 12,640 at
        // y = 2,640, north of 4,360: clear. Moving it 1,400 east puts the
        // corner (14,040, 4,360) on the line's south side, across it.
        try world.placeBuilding(.house, at: PlanPoint(x: 12_000, y: 5_000))
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 13_400, y: 4_000)), .buildingOnTrack(diagonal))
    }

    func testACurvedEdgeIsCheckedAlongItsSamples() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_000, y: 2_000, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 10_000, y: 2_000, z: 0))
        // Bows south: its middle is near y = 2,000 + 0.75 × 4,000 = 5,000.
        let edge = try world.buildTrackEdge(from: a, to: b, curve: .cubic(PlanPoint(x: 4_000, y: 6_000), PlanPoint(x: 8_000, y: 6_000)))
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: 5_000)), .buildingOnTrack(edge))
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: 5_600)), .buildingOnTrack(edge))
        try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: 3_000)) // inside the bow
        try world.placeBuilding(.house, at: PlanPoint(x: 6_000, y: 6_000)) // beyond it
    }

    func testAStationKeepsItsClearance() throws {
        var world = try world()
        let station = try world.buildStation(named: "A", at: PlanPoint(x: 5_000, y: 5_000)).id
        let before = world
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 5_000, y: 5_000)), .buildingOnStation(station))
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: PlanPoint(x: 5_639, y: 5_000)), .buildingOnStation(station))
        XCTAssertEqual(world, before)
        try world.placeBuilding(.house, at: PlanPoint(x: 5_640, y: 5_000))
        // A station may still be built on a building (a first step).
        try world.buildStation(named: "B", at: PlanPoint(x: 5_640, y: 5_000))
    }

    func testTheChecksComeInOrder() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_000, y: 3_000, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 8_000, y: 3_000, z: 0))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "A", at: PlanPoint(x: 5_000, y: 3_000)).id
        try world.placeBuilding(.house, at: PlanPoint(x: 5_000, y: 1_000))
        // Out of the world before anything else, then another building,
        // then track, then a station.
        XCTAssertThrowsGameError(try world.placeBuilding(.office, at: PlanPoint(x: 5_000, y: 500)), .outOfBounds(PlanPoint(x: 5_000, y: 500)))
        XCTAssertThrowsGameError(try world.placeBuilding(.office, at: PlanPoint(x: 5_000, y: 2_000)), .buildingOverlaps(PlacedBuildingID(rawValue: 1)))
        XCTAssertThrowsGameError(try world.placeBuilding(.office, at: PlanPoint(x: 5_000, y: 3_000)), .buildingOnTrack(edge))
        world = try self.world()
        let lone = try world.buildStation(named: "A", at: PlanPoint(x: 5_000, y: 3_000)).id
        XCTAssertEqual(lone, station)
        XCTAssertThrowsGameError(try world.placeBuilding(.office, at: PlanPoint(x: 5_000, y: 3_000)), .buildingOnStation(lone))
    }

    /// The segment test against an independent one: a point of the segment
    /// at every 1/4096 of its length within the box, for segments where
    /// that cannot miss (the box is far wider than a step).
    func testTheSegmentTestMatchesSampling() {
        let box = (minX: Int64(1_000), minY: Int64(1_000), maxX: Int64(2_000), maxY: Int64(2_000))
        var generator = SplitMix64(seed: 92)
        for _ in 0..<2_000 {
            let a = PlanPoint(x: generator.int64(in: 0...3_000), y: generator.int64(in: 0...3_000))
            let b = PlanPoint(x: generator.int64(in: 0...3_000), y: generator.int64(in: 0...3_000))
            let sampled = (0...4_096).contains { step -> Bool in
                let x = a.x * Int64(4_096 - step) + b.x * Int64(step), y = a.y * Int64(4_096 - step) + b.y * Int64(step)
                return x >= box.minX * 4_096 && x <= box.maxX * 4_096 && y >= box.minY * 4_096 && y <= box.maxY * 4_096
            }
            // Sampling may only miss a segment that grazes the box.
            let crosses = GameWorld.segment(a, b, crosses: box)
            if sampled { XCTAssertTrue(crosses, "\(a) \(b)") }
            if crosses && !sampled {
                let inner = (minX: box.minX + 2, minY: box.minY + 2, maxX: box.maxX - 2, maxY: box.maxY - 2)
                XCTAssertFalse(GameWorld.segment(a, b, crosses: inner), "\(a) \(b) only grazes")
            }
        }
    }

    // MARK: - Saving

    func testPlacedBuildingsSaveAndReadBack() throws {
        var world = try world()
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any]
        XCTAssertNil(empty?["placedBuildings"], "none: no key")
        XCTAssertNil(empty?["nextPlacedBuildingID"])
        try world.placeBuilding(.house, at: PlanPoint(x: 1_000, y: 1_000))
        try world.placeBuilding(.office, at: PlanPoint(x: 5_000, y: 5_000))
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["nextPlacedBuildingID"] as? Int, 3)
        let buildings = try XCTUnwrap(object["placedBuildings"] as? [[String: Any]])
        XCTAssertEqual(buildings.count, 2)
        XCTAssertEqual(buildings[1]["kind"] as? String, "office")
        XCTAssertEqual(buildings[1]["id"] as? Int, 2)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
    }

    func testBadPlacedBuildingsAreRefused() throws {
        var world = try world()
        try world.placeBuilding(.house, at: PlanPoint(x: 1_000, y: 1_000))
        try world.placeBuilding(.house, at: PlanPoint(x: 5_000, y: 5_000))
        let good = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        func decodes(_ change: (inout [String: Any]) -> Void) -> Bool {
            var object = good
            change(&object)
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
            return (try? JSONDecoder().decode(GameWorld.self, from: data)) != nil
        }
        func building(_ id: Int, _ kind: String, _ x: Int, _ y: Int) -> [String: Any] {
            ["id": id, "kind": kind, "centre": ["x": x, "y": y]]
        }
        XCTAssertTrue(decodes { _ in })
        XCTAssertFalse(decodes { $0["placedBuildings"] = [building(1, "house", 1_000, 1_000), building(2, "house", 1_500, 1_000)] }, "sharing ground")
        XCTAssertFalse(decodes { $0["placedBuildings"] = [building(1, "house", 100, 1_000)] }, "out of the world")
        XCTAssertFalse(decodes { $0["placedBuildings"] = [building(2, "house", 1_000, 1_000), building(1, "house", 5_000, 5_000)] }, "out of order")
        XCTAssertFalse(decodes { $0["nextPlacedBuildingID"] = 2 }, "an ID not below the next")
        XCTAssertFalse(decodes { $0["placedBuildings"] = [building(1, "castle", 1_000, 1_000)] }, "an unknown kind")
        XCTAssertFalse(decodes { $0["placedBuildings"] = NSNull() })
        XCTAssertFalse(decodes { $0["nextPlacedBuildingID"] = NSNull() })
    }
}
