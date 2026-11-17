import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 834 (ROAD-GRADE-CAP): a motorway over the hills climbed and
/// fell with the ground's 64 m corners (林口: 12.7 % at the 95th
/// percentile); it keeps to 5 % now, through a crest in a cutting and over
/// its feet on a fill, and nothing else moves.
final class Map3DRoadGradeTests: XCTestCase {
    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)
    /// The ridge's corners, by column (x / 64 m): 20 m, then up 8 m a
    /// corner (12.5 %) to 36 m at 512 m, and down again.
    private static let ridge: [Int: Int16] = [7: 28, 8: 36, 9: 28]

    /// A world 1,024 m square, its ground 20 m high but for a ridge
    /// running north and south through x = 512 m.
    private func ridgeWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        let heights = (0..<(side * side)).map { Self.ridge[$0 % side] ?? 20 }
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights))])
        return world
    }

    private func road(_ points: [(Double, Double)], kind: Map3DBaseMap.RoadKind = .motorway, level: Int = 0) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }, bounds: Self.bounds, bridgeLevel: level)
    }

    /// `roads` laid on `world` as a real map's are: graded before the
    /// ground is laid.
    private func built(_ world: GameWorld, roads: [Map3DBaseMap.Road]) -> Map3DScene.Builder {
        let snapshot = world.railwaySnapshot()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        let map = Map3DBaseMap(roads: roads)
        builder.roadGrade = builder.gradeMotorways(of: map)
        builder.addGround()
        _ = builder.addBaseMap(map)
        builder.addTrenches()
        return builder
    }

    /// The scene's triangles, by their corners.
    private func meshes(_ builder: Map3DScene.Builder) -> [[Map3DVertex]] {
        (Array(builder.meshes.values) + Array(builder.nearMeshes.values)).flatMap { mesh in
            stride(from: 0, to: mesh.indices.count - 2, by: 3).map { index in (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] } }
        }
    }

    private func roadTop(_ x: Float, _ z: Float, in triangles: [[Map3DVertex]], kind: Map3DBaseMap.RoadKind = .motorway) -> Float? {
        Map3DTrenchTests.heights(over: x, z, in: triangles, colours: [Map3DPalette.road(kind)]).max()
    }

    /// The motorway across the ridge keeps to 5 %: down in a cutting at the
    /// crest, with no ground or anything else over it, and up on a fill
    /// where the ridge meets the plain, on piers once its girder is clear;
    /// on the plain at each end, on the ground.
    func testAMotorwayKeepsToFivePercentOverARidge() throws {
        let world = try ridgeWorld()
        var builder = built(world, roads: [road([(40, 512), (984, 512)])])
        let meshes = meshes(builder)
        let lift = Map3DScene.Builder.lift(of: .motorway)
        var previous = try XCTUnwrap(roadTop(60, 512, in: meshes))
        XCTAssertEqual(previous, 20 + lift, accuracy: 0.01, "on the plain")
        XCTAssertEqual(try XCTUnwrap(roadTop(964, 512, in: meshes)), 20 + lift, accuracy: 0.01, "on the plain")
        var steepest: Float = 0
        let lanes = meshes.filter { triangle in triangle.contains { abs($0.z - 512) < 20 } && triangle[0].color == Map3DPalette.road(.motorway) }
        for x in stride(from: Float(64), through: 960, by: 4) {
            let height = try XCTUnwrap(roadTop(x, 512, in: lanes), "the motorway at \(x)")
            steepest = max(steepest, abs(height - previous) / 4)
            previous = height
        }
        XCTAssertLessThanOrEqual(steepest, Map3DRoadGrade.grade + 0.005, "its steepest grade")
        // At the crest, in a cutting: nothing over its lanes.
        let crest = try XCTUnwrap(roadTop(512, 512, in: meshes))
        XCTAssertLessThan(crest, 36 - 2, "the crest's cutting")
        let colours = Set(meshes.flatMap { $0 }.map { (vertex: Map3DVertex) in vertex.color })
        for z: Float in [506, 512, 518] {
            let over = Map3DTrenchTests.heights(over: 512, z, in: meshes, colours: colours).filter { $0 > crest + 0.05 }
            XCTAssertTrue(over.isEmpty, "something over the cutting's lanes at \(z): \(over)")
        }
        // Where the ridge meets the plain, on a fill over the ground.
        let foot = try XCTUnwrap(roadTop(384, 512, in: meshes))
        XCTAssertGreaterThan(foot - lift - builder.drawnGround(x: 384, z: 512), Map3DElevatedLook.roadBridge.girderDepth + 0.5, "the fill")
        let concrete = Set([0.92, 0.80, 0.70, 0.86].map { Map3DColor.shaded(Map3DPalette.concrete, Float($0)) })
        let vertices: [Map3DVertex] = meshes.flatMap { $0 }
        let feet = vertices.filter { (vertex: Map3DVertex) -> Bool in
            concrete.contains(vertex.color) && abs(vertex.y - 20) < 0.01 && abs(vertex.z - 512) < 2
        }
        XCTAssertFalse(feet.isEmpty, "a pier under the fill")
    }

    /// A motorway on the plain, and a trunk road over the ridge (a
    /// mountain highway climbs steeper for real), lie on the ground as
    /// before.
    func testOtherRoadsLieOnTheGround() throws {
        let world = try ridgeWorld()
        var builder = built(world, roads: [road([(150, 40), (150, 984)]), road([(40, 800), (984, 800)], kind: .trunk)])
        let meshes = meshes(builder)
        for z: Float in [100, 512, 900] {
            XCTAssertEqual(try XCTUnwrap(roadTop(150, z, in: meshes)), 20 + Map3DScene.Builder.lift(of: .motorway), accuracy: 0.01)
        }
        XCTAssertTrue(builder.roadGrade.cells.isEmpty, "a motorway on the plain is never looked up")
        XCTAssertTrue(builder.roadGrade.cuts.isEmpty)
        let trunk = Map3DScene.Builder.lift(of: .trunk)
        for x: Float in [300, 448, 512, 600] {
            XCTAssertEqual(try XCTUnwrap(roadTop(x, 800, in: meshes, kind: .trunk)), builder.drawnGround(x: x, z: 800) + trunk, accuracy: 0.01, "at \(x)")
        }
    }

    /// Two tiles' pieces of one motorway, meeting end to end, take one
    /// profile: no step where they meet, and within a few centimetres of
    /// the whole road's (their samples lie apart).
    func testPiecesOfOneMotorwayMeet() throws {
        XCTAssertLessThanOrEqual(Map3DRoadGrade.window + 30, Map3DBaseMap.bridgeReach, "a chunk built apart reads all its window")
        let world = try ridgeWorld()
        let west = Map3DBaseMap.Road(kind: .motorway, isRamp: false, points: [.init(x: 40, z: 512), .init(x: 984, z: 512)],
                                     bounds: .init(minX: 0, minZ: 0, maxX: 480, maxZ: 1_024))
        let east = Map3DBaseMap.Road(kind: .motorway, isRamp: false, points: [.init(x: 40, z: 512), .init(x: 984, z: 512)],
                                     bounds: .init(minX: 480, minZ: 0, maxX: 1_024, maxZ: 1_024))
        let split = built(world, roads: [west, east]), whole = built(world, roads: [road([(40, 512), (984, 512)])])
        let splitMeshes = meshes(split), wholeMeshes = meshes(whole)
        for x: Float in [380, 440, 476, 480, 484, 512, 600] {
            let a = try XCTUnwrap(roadTop(x, 512, in: splitMeshes), "\(x)"), b = try XCTUnwrap(roadTop(x, 512, in: wholeMeshes), "\(x)")
            XCTAssertEqual(a, b, accuracy: 0.25, "at \(x)")
        }
    }
}
