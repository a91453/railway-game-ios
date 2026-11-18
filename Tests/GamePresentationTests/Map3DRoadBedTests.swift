import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 865 (HK-ROAD-TILT): a road lay on the drawn ground corner by
/// corner, so on a hillside one kerb stood metres over the other (Hong
/// Kong's hillside roads 3–8 m at the 95th percentile). It lies on a bed
/// now, level across, the ground's highest under it, with a wall down its
/// downhill side; roads meet at one height.
final class Map3DRoadBedTests: XCTestCase {
    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)

    /// A world 1,024 m square: a hillside climbing east, 16 m a 64 m
    /// corner (25 %), or `climb` metres a corner, or level at 20 m.
    private func world(hillside: Bool, climb: Int = 16) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        let heights = (0..<(side * side)).map { Int16(hillside ? 20 + climb * ($0 % side) : 20) }
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights))])
        return world
    }

    private func road(_ points: [(Double, Double)], kind: Map3DBaseMap.RoadKind, bounds: Map3DBaseMap.Bounds = Map3DRoadBedTests.bounds) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }, bounds: bounds)
    }

    /// `roads` laid on `world` as a real map's are.
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

    private func triangles(_ builder: Map3DScene.Builder) -> [[Map3DVertex]] {
        (Array(builder.meshes.values) + Array(builder.nearMeshes.values)).flatMap { mesh in
            stride(from: 0, to: mesh.indices.count - 2, by: 3).map { index in (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] } }
        }
    }

    private func top(_ x: Float, _ z: Float, in triangles: [[Map3DVertex]], colour: UInt32) -> Float? {
        Map3DTrenchTests.heights(over: x, z, in: triangles, colours: [colour]).max()
    }

    /// The hillside's ground at `x` metres east.
    private func hill(_ x: Float) -> Float { 20 + x / 4 }

    /// A road along a hillside: both kerbs, both pavements' edges and its
    /// centre line at one height, the ground's highest under it (less the
    /// slack); never under the ground; a wall down its downhill side, none
    /// on its uphill side.
    func testARoadAlongAHillsideIsLevelAcross() throws {
        var builder = built(try world(hillside: true), roads: [road([(500, 40), (500, 984)], kind: .secondary)])
        let all = triangles(builder)
        let half = Float(Map3DRoadBed.half(.secondary, ramp: false))
        XCTAssertEqual(half, 7, "a secondary road's 8 m and a 3 m pavement each side")
        let bed = hill(500 + half) - Map3DRoadBed.slack
        let lift = Map3DScene.Builder.lift(of: .secondary)
        for z: Float in [100, 333, 512, 700, 931] {
            for x: Float in [496.2, 500, 503.8] {
                XCTAssertEqual(try XCTUnwrap(top(x, z, in: all, colour: Map3DPalette.road(.secondary)), "\(x) \(z)"), bed + lift, accuracy: 0.02, "the road at \(x), \(z)")
            }
            for x: Float in [493.2, 506.8] {
                let pavement = try XCTUnwrap(top(x, z, in: all, colour: builder.look.streets.sidewalk), "\(x) \(z)")
                XCTAssertEqual(pavement, bed + Map3DScene.Builder.sidewalkLift, accuracy: 0.02, "the pavement at \(x), \(z)")
                XCTAssertGreaterThan(pavement, builder.drawnGround(x: x, z: z), "over the ground at \(x), \(z)")
            }
        }
        // The wall: concrete from the downhill pavement's edge down into
        // the ground there, and none uphill, where the ground meets it.
        let concrete = all.flatMap { $0 }.filter { $0.color == Map3DPalette.concrete }
        let downhill = concrete.filter { abs($0.x - (500 - half)) < 0.05 }, uphill = concrete.filter { abs($0.x - (500 + half)) < 0.05 }
        XCTAssertFalse(downhill.isEmpty, "a wall down the downhill side")
        XCTAssertTrue(uphill.isEmpty, "none on the uphill side")
        XCTAssertEqual(try XCTUnwrap(downhill.map(\.y).max()), bed + Map3DScene.Builder.sidewalkLift - 0.02, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(downhill.map(\.y).min()), hill(500 - half) - 0.3, accuracy: 0.02)
        // Straight and level along: the bed bends nowhere, so the road is
        // no more pieces than the ground's grid cuts it into.
        let road = all.filter { $0[0].color == Map3DPalette.road(.secondary) }
        XCTAssertLessThanOrEqual(road.count, 2 * 2 * 16 + 8, "\(road.count) triangles")
    }

    /// On level ground nothing moves: the road on the ground, no wall.
    func testARoadOnLevelGroundLiesOnIt() throws {
        let builder = built(try world(hillside: false), roads: [road([(500, 40), (500, 984)], kind: .secondary), road([(40, 512), (984, 512)], kind: .minor)])
        let all = triangles(builder)
        for (x, z): (Float, Float) in [(497, 200), (503, 700), (500, 512)] {
            XCTAssertEqual(try XCTUnwrap(top(x, z, in: all, colour: Map3DPalette.road(.secondary))), 20 + Map3DScene.Builder.lift(of: .secondary), accuracy: 0.001)
        }
        XCTAssertEqual(try XCTUnwrap(top(300, 513, in: all, colour: Map3DPalette.road(.minor))), 20 + Map3DScene.Builder.lift(of: .minor), accuracy: 0.001)
        XCTAssertFalse(all.contains { $0[0].color == Map3DPalette.concrete }, "no wall on level ground")
    }

    /// A side street up the hill meets the road along it at the road's
    /// height, and comes down from it at ``Map3DRoadBed/ramp`` over its
    /// own ground: no step at the junction; far from it, on the ground.
    func testASideStreetMeetsTheRoadAtItsHeight() throws {
        var builder = built(try world(hillside: true), roads: [road([(500, 40), (500, 984)], kind: .secondary), road([(200, 512), (500, 512)], kind: .minor)])
        let all = triangles(builder)
        let half = Float(Map3DRoadBed.half(.secondary, ramp: false))
        let bed = hill(500 + half) - Map3DRoadBed.slack
        let minor = Map3DScene.Builder.lift(of: .minor)
        // On the main road's bed, at its height.
        for x: Float in [494, 497, 499.5] {
            XCTAssertEqual(try XCTUnwrap(top(x, 512, in: all, colour: Map3DPalette.road(.minor)), "\(x)"), bed + minor, accuracy: 0.05, "at \(x)")
        }
        // Down from where it is held (a step and a metre past the bed's
        // edge, on the bed's own samples: within 3 m of the edge): what
        // holds it up there less 15 cm a metre, on its own ground beyond.
        var last = bed + minor
        for back: Float in [4, 8, 12, 16, 20, 24] {
            let x = 500 - half - back
            let here = try XCTUnwrap(top(x, 512, in: all, colour: Map3DPalette.road(.minor)), "\(x)")
            let low = hill(x) + (bed - hill(500 - half)) - Map3DRoadBed.ramp * back, high = hill(x) + (bed - hill(497 - half)) - Map3DRoadBed.ramp * (back - 3)
            XCTAssertGreaterThanOrEqual(here, max(low, hill(x)) + minor - 0.02, "\(back) m down the ramp")
            XCTAssertLessThanOrEqual(here, max(high, hill(x)) + minor + 0.02, "\(back) m down the ramp")
            XCTAssertLessThan(here, last, "down all the way")
            XCTAssertLessThanOrEqual(last - here, 4 * (0.25 + Map3DRoadBed.ramp) + 0.02, "no steeper than its ground and the ramp")
            last = here
        }
        for x: Float in [250, 400, 460] {
            XCTAssertEqual(try XCTUnwrap(top(x, 512, in: all, colour: Map3DPalette.road(.minor)), "\(x)"), hill(x) + minor, accuracy: 0.02, "on its own ground at \(x)")
        }
        // Its own kerbs level all the way (its ground is level across).
        for x: Float in [300, 470, 485] {
            let north = try XCTUnwrap(top(x, 510, in: all, colour: Map3DPalette.road(.minor))), south = try XCTUnwrap(top(x, 514, in: all, colour: Map3DPalette.road(.minor)))
            XCTAssertEqual(north, south, accuracy: 0.02, "at \(x)")
        }
        XCTAssertEqual(builder.roadGround(at: .init(x: 499, z: 512), along: (1, 0), onDeck: false), bed, accuracy: 0.05)
    }

    /// Two carriageways side by side on a gentle slope take one height
    /// (neither's pavement over the other's lanes); on a steep one each
    /// keeps its own.
    func testCarriagewaysSideBySideTakeOneHeight() throws {
        let roads = [road([(500, 40), (500, 984)], kind: .trunk), road([(488, 984), (488, 40)], kind: .trunk)]
        let half = Float(Map3DRoadBed.half(.trunk, ramp: false))
        let steep = built(try world(hillside: true), roads: roads)
        let upper = try XCTUnwrap(steep.roadBed.level(at: .init(x: 500, z: 500), along: (0, 1), onDeck: false))
        let lower = try XCTUnwrap(steep.roadBed.level(at: .init(x: 488, z: 500), along: (0, 1), onDeck: false))
        XCTAssertEqual(upper, hill(500 + half) - Map3DRoadBed.slack, accuracy: 0.01)
        XCTAssertEqual(lower, hill(488 + half) - Map3DRoadBed.slack, accuracy: 0.01, "3 m apart in height: each its own")
        // 2 m a corner: the two beds 0.375 m apart, so one height.
        let gentle = built(try world(hillside: true, climb: 2), roads: roads)
        let high = try XCTUnwrap(gentle.roadBed.level(at: .init(x: 500, z: 500), along: (0, 1), onDeck: false))
        let low = try XCTUnwrap(gentle.roadBed.level(at: .init(x: 488, z: 500), along: (0, 1), onDeck: false))
        XCTAssertEqual(high, 20 + (500 + half) / 32 - Map3DRoadBed.slack, accuracy: 0.01)
        XCTAssertEqual(low, high, accuracy: 0.001)
        XCTAssertEqual(Map3DRoadBed.taper(0.4), 0.4)
        XCTAssertEqual(Map3DRoadBed.taper(1.5), 0.5)
        XCTAssertEqual(Map3DRoadBed.taper(3), 0)
    }

    /// Two tiles' pieces of one road meet at one height, as the whole
    /// road's, and a chunk's reach holds what a bed depends on.
    func testPiecesOfOneRoadMeet() throws {
        XCTAssertLessThanOrEqual(Map3DRoadBed.reach, Map3DBaseMap.bridgeReach, "the base map reads the roads a bed depends on")
        XCTAssertLessThanOrEqual(Double(Map3DRoadBed.passes) * (Double(Map3DRoadBed.tallest / Map3DRoadBed.ramp) + 20), Map3DRoadBed.reach)
        let hillside = try world(hillside: true)
        let line: [(Double, Double)] = [(200, 300), (800, 700)]
        let west = road(line, kind: .tertiary, bounds: .init(minX: 0, minZ: 0, maxX: 480, maxZ: 1_024))
        let east = road(line, kind: .tertiary, bounds: .init(minX: 480, minZ: 0, maxX: 1_024, maxZ: 1_024))
        let split = triangles(built(hillside, roads: [west, east])), whole = triangles(built(hillside, roads: [road(line, kind: .tertiary)]))
        for x: Float in [380, 470, 479, 481, 490, 600] {
            let z = 300 + (x - 200) * 2 / 3
            let a = try XCTUnwrap(top(x, z, in: split, colour: Map3DPalette.road(.tertiary)), "\(x)")
            let b = try XCTUnwrap(top(x, z, in: whole, colour: Map3DPalette.road(.tertiary)), "\(x)")
            XCTAssertEqual(a, b, accuracy: 0.02, "at \(x)")
        }
    }
}
