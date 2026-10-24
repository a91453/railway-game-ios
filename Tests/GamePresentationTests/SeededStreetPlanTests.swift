import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 270: the 2D map draws the seeded streets the 3D
/// map lays (decision 263), worked out without building the 3D city.
final class SeededStreetPlanTests: XCTestCase {
    private func towns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    func testThePlanIsTheThreeDMapsStreets() throws {
        let world = try towns()
        let plan = Map3DScene.seededStreets(world: world)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertEqual(plan.roads, Map3DScene(world: world).seededStreets.roads)
    }

    func testEachLineIsOneRoadForEachRunOfOneKind() throws {
        let plan = Map3DScene.seededStreets(world: try towns())
        let cell = Int64(Land.cellLength)
        for road in plan.roads {
            XCTAssertEqual(road.points.count, 2)
            let a = road.points[0], b = road.points[1]
            // Along a grid line, from one grid crossing to another, west to
            // east or north to south.
            XCTAssertTrue(a.x == b.x || a.y == b.y)
            XCTAssertTrue(a.x < b.x || a.y < b.y)
            for value in [a.x, a.y, b.x, b.y] { XCTAssertEqual(value % cell, 0) }
            XCTAssertTrue([9, 7, 5].contains(road.width), "\(road.width)")
            XCTAssertEqual(road.major, road.width >= 7)
        }
        // Two runs of one kind on one line never touch: they would be one.
        for (i, r) in plan.roads.enumerated() {
            let rLine = r.points[0].y == r.points[1].y ? (true, r.points[0].y) : (false, r.points[0].x)
            for s in plan.roads[(i + 1)...] where s.rank == r.rank {
                let sLine = s.points[0].y == s.points[1].y ? (true, s.points[0].y) : (false, s.points[0].x)
                guard rLine == sLine else { continue }
                XCTAssertFalse(r.points[1] == s.points[0] || s.points[1] == r.points[0], "\(r) \(s)")
            }
        }
        // The larger drawn last.
        XCTAssertEqual(plan.roads.map(\.rank), plan.roads.map(\.rank).sorted())
    }

    func testOnlyTheRoadsInViewAndNoneOnARealMap() throws {
        let plan = Map3DScene.seededStreets(world: try towns())
        let road = try XCTUnwrap(plan.roads.first)
        let x = Double(road.points[0].x), y = Double(road.points[0].y)
        let near = plan.roads(in: WorldRegion(minX: x - 10, minY: y - 10, maxX: x + 10, maxY: y + 10))
        XCTAssertTrue(near.contains(road))
        XCTAssertLessThan(near.count, plan.roads.count)
        XCTAssertTrue(plan.roads(in: WorldRegion(minX: -1e9, minY: -1e9, maxX: -1e8, maxY: -1e8)).isEmpty)
        let real = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        XCTAssertTrue(Map3DScene.seededStreets(world: real).isEmpty)
    }

    func testItCostsLittleOfBuildingTheScene() throws {
        let world = try towns()
        // With swift test --parallel (decision 404) each test runs in a
        // process of its own: the first plan paid for loading what both
        // share, and the wall clock counted the other tests on the cores
        // too (plan 7.26 s, scene 7.23 s). So one plan first, then this
        // thread's CPU time.
        _ = Map3DScene.seededStreets(world: world)
        let start = threadSeconds()
        _ = Map3DScene.seededStreets(world: world)
        let plan = threadSeconds() - start
        let sceneStart = threadSeconds()
        _ = Map3DScene(world: world)
        let scene = threadSeconds() - sceneStart
        print("SEEDED plan \(plan) s, scene \(scene) s")
        XCTAssertLessThan(plan, scene)
    }

    private func threadSeconds() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
}
