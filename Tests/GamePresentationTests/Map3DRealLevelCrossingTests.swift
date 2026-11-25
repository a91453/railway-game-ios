import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 941 (later, LEVEL-CROSSING-REAL-MAP; the owner's IMG_5594, 146:
/// 「已經是最新版 但遊戲還是沒有鋪平交道」): on a real-world map a road of the
/// base map crossing the track on the level ran on under the track's bed,
/// with no deck, barriers or booms: only a seeded street of a map with no
/// base map got a level crossing. Every road on the ground crossing the
/// track on the ground gets one now, the player's track and a real line's.
final class Map3DRealLevelCrossingTests: XCTestCase {
    /// A world 1,024 m square whose ground stands 20 m high, with a track
    /// along each of `lines` (scene z, metres) from x 64 m to 960 m, its
    /// rails' base `trackHeight` metres over the sea.
    private func flatWorld(lines: [Int64], trackHeight: Int64 = 20) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        for z in lines {
            let nodes = try [64, 960].map { x in try world.buildTrackNode(at: WorldCoordinate(x: Int64(x) * 64, y: z * 64, z: trackHeight * 64)) }
            try world.buildTrackEdge(from: nodes[0], to: nodes[1], structure: .automatic)
        }
        return world
    }

    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)

    private func road(_ points: [(Double, Double)], level: Int = 0, kind: Map3DBaseMap.RoadKind = .secondary) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }, bounds: Self.bounds, bridgeLevel: level)
    }

    /// `roads` laid on `world` as a real map's are, with its track (and
    /// `real`, a real line's track on the ground), and the level crossings
    /// as the scene lays them.
    private func built(_ world: GameWorld, roads: [Map3DBaseMap.Road], real: [[Map3DPoint]] = []) -> Map3DScene.Builder {
        let snapshot = world.railwaySnapshot()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround()
        _ = builder.addBaseMap(Map3DBaseMap(roads: roads))
        _ = builder.addTrack(snapshot)
        builder.realSurfaceLines = real
        builder.addRealLevelCrossings()
        return builder
    }

    private func meshes(_ builder: Map3DScene.Builder) -> [Map3DMesh] {
        Array(builder.meshes.values) + Array(builder.nearMeshes.values)
    }

    /// The highest road-coloured surface over scene point (`x`, `z`): the
    /// road, or a level crossing's deck and ramps in the road's colour.
    private func roadTop(_ x: Float, _ z: Float, in meshes: [Map3DMesh], kind: Map3DBaseMap.RoadKind = .secondary) -> Float? {
        Map3DTrenchTests.heights(over: x, z, in: meshes, colours: [Map3DPalette.road(kind)]).max()
    }

    /// The owner's screenshot: a road crossing the player's double track on
    /// the level. One crossing over both tracks, its deck over the rails,
    /// its barriers either side, its traffic over the deck, not through the
    /// bed.
    func testARoadCrossingTheTrackOnTheLevelGetsALevelCrossing() throws {
        let world = try flatWorld(lines: [510, 514])
        let builder = built(world, roads: [road([(500, 300), (500, 724)])])
        XCTAssertEqual(builder.roadBridges.crossings[.level], 2, "both tracks on the level")
        XCTAssertEqual(builder.crossings.count, 1, "one crossing over the double track")
        let crossing = try XCTUnwrap(builder.crossings.first)
        XCTAssertEqual(crossing.point.x, 500, accuracy: 0.1)
        XCTAssertEqual(crossing.point.z, 512, accuracy: 0.1)
        XCTAssertEqual(crossing.spread, 4, accuracy: 0.1)
        XCTAssertEqual(crossing.kind, .secondary)
        XCTAssertEqual(crossing.gateFeet.map(\.end), [-1, 1], "a barrier each side")
        let rails = Float(20) + Map3DScene.railLift
        XCTAssertEqual(crossing.point.y, rails, accuracy: 0.05)
        // The deck over both tracks, the road on the ground away from it.
        let meshes = meshes(builder)
        for z: Float in [510, 512, 514] {
            XCTAssertEqual(try XCTUnwrap(roadTop(500, z, in: meshes), "the deck at \(z)"), crossing.deckTop, accuracy: 0.05)
        }
        XCTAssertEqual(try XCTUnwrap(roadTop(500, 400, in: meshes)), 20 + Map3DScene.Builder.lift(of: .secondary), accuracy: 0.01)
        // The traffic over the deck and up its ramps, not through the bed.
        let lanes = builder.streetLife.lanes.flatMap(\.path.points).filter { abs($0.x - 500) < 1 }
        let overTrack = lanes.filter { abs($0.z - 512) < 2.5 }
        XCTAssertFalse(overTrack.isEmpty, "traffic over the track")
        XCTAssertTrue(overTrack.allSatisfy { $0.y >= crossing.deckTop - 0.01 }, "traffic over the deck: \(overTrack.map(\.y))")
        let ramp = lanes.filter { abs($0.z - 512) > crossing.deckHalfLength + 1 && abs($0.z - 512) < crossing.rampEnd - 1 }
        XCTAssertFalse(ramp.isEmpty, "traffic on the ramps")
        XCTAssertTrue(ramp.allSatisfy { $0.y > 20 + Map3DScene.Builder.lift(of: .secondary) + 0.05 }, "up the ramps")
    }

    /// A road over the track on a bank or in a cutting goes over it
    /// (decision 391); one passing under a viaduct goes under; one along
    /// the track or ending at it crosses nothing; a motorway never crosses
    /// on the level.
    func testOnlyARoadCrossingTheTrackOnTheLevelGetsOne() throws {
        for height in [Int64(18), 22] {
            let builder = built(try flatWorld(lines: [512], trackHeight: height), roads: [road([(500, 300), (500, 724)])])
            XCTAssertTrue(builder.crossings.isEmpty, "track at \(height) m")
        }
        let viaduct = built(try flatWorld(lines: [512], trackHeight: 32), roads: [road([(500, 300), (500, 724)])])
        XCTAssertTrue(viaduct.crossings.isEmpty, "under a viaduct")
        let level = try flatWorld(lines: [512])
        XCTAssertTrue(built(level, roads: [road([(100, 520), (900, 524)])]).crossings.isEmpty, "along the track")
        XCTAssertTrue(built(level, roads: [road([(500, 300), (500, 511)])]).crossings.isEmpty, "ending at the track")
        XCTAssertTrue(built(level, roads: [road([(500, 300), (500, 724)], kind: .motorway)]).crossings.isEmpty, "a motorway")
        XCTAssertTrue(built(level, roads: [road([(500, 300), (500, 724)], level: 1)]).crossings.isEmpty, "a road bridge")
    }

    /// A real line's track on the ground (decision 402), which the player
    /// has not bought, gets its level crossings too.
    func testARoadCrossingARealLineOnTheLevelGetsALevelCrossing() throws {
        let world = try flatWorld(lines: [])
        let rails = Float(20) + Map3DScene.railLift
        let real = [[Map3DPoint(64, rails, 600), Map3DPoint(960, rails, 600)], [Map3DPoint(64, rails, 604), Map3DPoint(960, rails, 604)]]
        let builder = built(world, roads: [road([(300, 300), (310, 900)], kind: .tertiary)], real: real)
        XCTAssertEqual(builder.crossings.count, 1)
        let crossing = try XCTUnwrap(builder.crossings.first)
        XCTAssertEqual(crossing.point.z, 602, accuracy: 0.2)
        XCTAssertEqual(crossing.spread, 4, accuracy: 0.1)
        XCTAssertEqual(crossing.kind, .tertiary)
        XCTAssertEqual(try XCTUnwrap(roadTop(crossing.point.x, 602, in: meshes(builder), kind: .tertiary)), crossing.deckTop, accuracy: 0.05)
    }
}
