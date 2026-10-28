import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 391 (the owner, 2026-10-22: 「道路跟鐵道會破圖解決了嗎」「目前道路要不要改照真實高度而不是全部在地面」):
/// every road lay on the ground, its bridges too, so a road bridge over the
/// track ran through the bed. The base map's bridges stand a level (6 m) up
/// now, higher where they cross the track, ramping down to the ground.
final class Map3DRoadBridgeTests: XCTestCase {
    private static let lineY: Int64 = 32_768

    /// A world 1,024 m square whose ground stands 20 m high, `track` along
    /// y = 512 m from 64 m to 960 m, its rails' base `trackHeight` metres
    /// over the sea (the ground's 20 m unless given).
    private func flatWorld(track: Bool, trackHeight: Int64 = 20) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        if track {
            let nodes = try [64, 960].map { x in try world.buildTrackNode(at: WorldCoordinate(x: Int64(x) * 64, y: Self.lineY, z: trackHeight * 64)) }
            try world.buildTrackEdge(from: nodes[0], to: nodes[1], structure: .automatic)
        }
        return world
    }

    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)

    private func road(_ points: [(Double, Double)], level: Int = 0, kind: Map3DBaseMap.RoadKind = .secondary) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }, bounds: Self.bounds, bridgeLevel: level)
    }

    /// `roads` laid on `world` as a real map's are, with its track.
    private func built(_ world: GameWorld, roads: [Map3DBaseMap.Road]) -> Map3DScene.Builder {
        let snapshot = world.railwaySnapshot()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround()
        _ = builder.addBaseMap(Map3DBaseMap(roads: roads))
        _ = builder.addTrack(snapshot)
        return builder
    }

    private func meshes(_ builder: Map3DScene.Builder) -> [Map3DMesh] {
        Array(builder.meshes.values) + Array(builder.nearMeshes.values)
    }

    /// The highest road surface over scene point (`x`, `z`).
    private func roadTop(_ x: Float, _ z: Float, in meshes: [Map3DMesh], kind: Map3DBaseMap.RoadKind = .secondary) -> Float? {
        Map3DTrenchTests.heights(over: x, z, in: meshes, colours: [Map3DPalette.road(kind)]).max()
    }

    /// The owner's question: a road bridge over track on the ground clears
    /// a train and its wires, and runs down to the ground at a road's
    /// grade on both sides; piers hold it up, clear of the track, and its
    /// traffic runs over it.
    func testABridgeOverTheTrackClearsATrainAndRampsDown() throws {
        let world = try flatWorld(track: true)
        let builder = built(world, roads: [road([(512, 300), (512, 470)]), road([(512, 470), (512, 554)], level: 1), road([(512, 554), (512, 724)])])
        let meshes = meshes(builder)
        let bed = 20 + Map3DScene.railLift - Map3DScene.Builder.bedDrop
        let lift = Map3DScene.Builder.lift(of: .secondary)
        let over = try XCTUnwrap(roadTop(512, 512, in: meshes))
        XCTAssertGreaterThanOrEqual(over, bed + Map3DRoadBridges.overTrack, "the deck over the track")
        // On the ground away from it, and never steeper than 6 %.
        XCTAssertEqual(try XCTUnwrap(roadTop(512, 310, in: meshes)), 20 + lift, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(roadTop(512, 714, in: meshes)), 20 + lift, accuracy: 0.01)
        var previous = try XCTUnwrap(roadTop(512, 310, in: meshes))
        for z in stride(from: Float(314), through: 714, by: 4) {
            let height = try XCTUnwrap(roadTop(512, z, in: meshes), "a road at \(z)")
            XCTAssertLessThanOrEqual(abs(height - previous), 4 * Map3DRoadBridges.grade(.secondary) + 0.02, "the grade at \(z)")
            previous = height
        }
        // Piers on the ground under the deck, none on the track.
        let concrete = Set([0.92, 0.80, 0.70, 0.86].map { Map3DColor.shaded(Map3DPalette.concrete, Float($0)) })
        let feet = meshes.flatMap(\.vertices).filter {
            concrete.contains($0.color) && abs($0.y - 20) < 0.01 && abs($0.x - 512) < 2 && $0.z > 470 && $0.z < 554
        }
        XCTAssertFalse(feet.isEmpty, "a pier")
        XCTAssertFalse(feet.contains { abs($0.z - 512) < 3 }, "a pier on the track")
        // Its traffic, over the track.
        let lanes = builder.streetLife.lanes.flatMap(\.path.points)
        XCTAssertTrue(lanes.contains { abs($0.x - 512) < 1 && abs($0.z - 512) < 2 && $0.y > bed + Map3DRoadBridges.overTrack }, "the bridge's traffic")
        XCTAssertTrue(lanes.contains { abs($0.x - 512) < 1 && abs($0.z - 320) < 8 && abs($0.y - 20 - lift) < 0.1 }, "on the ground")
    }

    /// Over a road on the ground, a bridge stands 6 m a level up; over
    /// nothing (a river) and as a culvert (under 20 m) it stays at the
    /// ground; two tiles' pieces of one bridge, meeting end to end, are one
    /// deck with no ramp between.
    func testABridgeStandsALevelUp() throws {
        let world = try flatWorld(track: false)
        let lift = Map3DScene.Builder.lift(of: .secondary)
        var west = road([(100, 200), (300, 200)], level: 2)
        west = Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: west.points,
                                 bounds: .init(minX: 0, minZ: 0, maxX: 200, maxZ: 1_024), bridgeLevel: 2)
        let east = Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: [.init(x: 150, z: 200), .init(x: 400, z: 200)],
                                     bounds: .init(minX: 200, minZ: 0, maxX: 1_024, maxZ: 1_024), bridgeLevel: 2)
        let under = [road([(250, 500), (250, 700)], kind: .minor), road([(260, 100), (260, 300)], kind: .minor)]
        let builder = built(world, roads: [road([(100, 600), (400, 600)], level: 1), road([(500, 800), (515, 800)], level: 1),
                                           road([(100, 900), (400, 900)], level: 1), west, east] + under)
        let meshes = meshes(builder)
        XCTAssertEqual(try XCTUnwrap(roadTop(250, 600, in: meshes)), 20 + lift + 6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(roadTop(508, 800, in: meshes)), 20 + lift, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(roadTop(250, 900, in: meshes)), 20 + lift, accuracy: 0.01, "over a river")
        // The road under it stays on the ground.
        XCTAssertEqual(try XCTUnwrap(roadTop(250, 520, in: meshes, kind: .minor)), 20 + Map3DScene.Builder.lift(of: .minor), accuracy: 0.01)
        for x: Float in [180, 200, 220] {
            XCTAssertEqual(try XCTUnwrap(roadTop(x, 200, in: meshes)), 20 + lift + 12, accuracy: 0.01, "at the tiles' edge, \(x)")
        }
    }

    /// Decision 391 (續): the app's tiles keep OpenStreetMap's `layer` on
    /// a bridge two levels or more up, so 台北's stacked viaducts (環河、
    /// 市民大道 over the streets and the railway's own crossings) stand 12 m
    /// and 18 m: z14 tiles round Taipei Main and Banqiao.
    func testTheTilesKeepABridgesLayer() throws {
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        func tile(_ latitude: Double, _ longitude: Double) -> (x: Int, y: Int) {
            let n = Double(1 << BaseMapTiles.zoom), phi = latitude * .pi / 180
            return (Int((longitude + 180) / 360 * n), Int((1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * n))
        }
        var levels: [Int: Int] = [:]
        for centre in [tile(25.0478, 121.5170), tile(25.0133, 121.4637)] {
            for y in centre.y - 3...centre.y + 3 {
                for x in centre.x - 3...centre.x + 3 {
                    guard let bytes = try tiles.archive.tile(zoom: BaseMapTiles.zoom, x: x, y: y) else { continue }
                    let decoded = try VectorTile(bytes, layers: ["transportation"])
                    for layer in decoded.layers.values {
                        for feature in layer.features where feature.kind == .line { levels[Map3DBaseMap.bridgeLevel(feature), default: 0] += 1 }
                    }
                }
            }
        }
        XCTAssertGreaterThan(levels[1] ?? 0, 100, "\(levels)")
        XCTAssertGreaterThan(levels[2] ?? 0, 10, "two levels up: \(levels)")
        XCTAssertGreaterThan(levels[3] ?? 0, 0, "three levels up: \(levels)")
        print("Map3DRoadBridgeTests: road features by bridge level round Taipei Main and Banqiao: \(levels.sorted { $0.key < $1.key })")
    }

    /// Decision 391 (續篇二, HANDOFF §4.12 第 6 點; the owner: 「路面橋在照高度的時候要不要順便補道路鋪設」):
    /// a road on the ground across track in a cutting or on an embankment
    /// ran into it, cut by the cutting and under the bank. It goes over
    /// now, clear of a train and its wires, ramping up and down at its
    /// grade, unbroken; across track on the level it stays a level
    /// crossing.
    func testARoadCrossingACuttingOrAnEmbankmentGoesOverIt() throws {
        let lift = Map3DScene.Builder.lift(of: .secondary)
        for (height, crossing) in [(Int64(18), Map3DRoadBridges.Crossing.overCutting), (22, .overEmbankment), (20, .level)] {
            let world = try flatWorld(track: true, trackHeight: height)
            let builder = built(world, roads: [road([(500, 300), (500, 724)]), road([(100, 300), (400, 300)])])
            XCTAssertEqual(builder.roadBridges.crossings, [crossing: 1], "track at \(height) m")
            let meshes = meshes(builder)
            let bed = Float(height) + Map3DScene.railLift - Map3DScene.Builder.bedDrop
            let over = roadTop(500, 512, in: meshes)
            if crossing == .level {
                XCTAssertEqual(try XCTUnwrap(over, "on the level"), 20 + lift, accuracy: 0.01)
                continue
            }
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(over, "over the track at \(height) m"), bed + Map3DRoadBridges.overTrack, "track at \(height) m")
            // Unbroken, on the ground away from it, never steeper than its grade.
            var previous = try XCTUnwrap(roadTop(500, 310, in: meshes))
            XCTAssertEqual(previous, 20 + lift, accuracy: 0.01)
            XCTAssertEqual(try XCTUnwrap(roadTop(500, 714, in: meshes)), 20 + lift, accuracy: 0.01)
            for z in stride(from: Float(314), through: 714, by: 4) {
                let top = try XCTUnwrap(roadTop(500, z, in: meshes), "a road at \(z), track at \(height) m")
                XCTAssertLessThanOrEqual(abs(top - previous), 4 * Map3DRoadBridges.grade(.secondary) + 0.02, "the grade at \(z)")
                previous = top
            }
            // The road along the track stays on the ground.
            XCTAssertEqual(try XCTUnwrap(roadTop(250, 300, in: meshes)), 20 + lift, accuracy: 0.01)
            // Its traffic over the track.
            let lanes = builder.streetLife.lanes.flatMap(\.path.points)
            XCTAssertTrue(lanes.contains { abs($0.x - 500) < 1 && abs($0.z - 512) < 2 && $0.y > bed + Map3DRoadBridges.overTrack }, "traffic over it")
        }
    }

    /// The concrete of the bridges (girders, parapets, walls, piers).
    private static let concrete = Set([0.92, 0.80, 0.70, 0.86, 1].map { Map3DColor.shaded(Map3DPalette.concrete, Float($0)) })

    /// The owner (2026-10-24): 「想問高架 應該不用那麼多的邊線怎麼感覺道路有超多條圍欄」. Two
    /// decks side by side (a road's two carriageways, mapped apart) are
    /// one deck to look at: a parapet along its outer edges only, none
    /// between them.
    func testDecksSideBySideKeepOnlyTheirOuterParapets() throws {
        let world = try flatWorld(track: false)
        let half = Map3DRoadBridges.half(.secondary)
        let north: Double = 600, south = north + 2 * Double(half)
        let builder = built(world, roads: [road([(100, north), (400, north)], level: 1), road([(400, south), (100, south)], level: 1),
                                           road([(250, 500), (250, 750)], kind: .minor)])
        let meshes = meshes(builder)
        let top = try XCTUnwrap(roadTop(230, Float(north), in: meshes))
        XCTAssertEqual(top, 20 + Map3DScene.Builder.lift(of: .secondary) + 6, accuracy: 0.01, "both decks a level up")
        // Parapets' tops, a metre over the decks.
        let over = top + 0.5
        let parapets: [Float] = meshes.flatMap(\.vertices).filter { (vertex: Map3DVertex) -> Bool in
            Self.concrete.contains(vertex.color) && vertex.x > 100 && vertex.x < 400 && vertex.y > over
        }.map(\.z)
        let outer: (north: Float, south: Float) = (Float(north) - half, Float(south) + half)
        let seam: Float = Float(north) + half
        let between = parapets.filter { abs($0 - seam) < 1 }
        XCTAssertTrue(parapets.contains { abs($0 - outer.north) < 0.5 }, "the outer parapet, north")
        XCTAssertTrue(parapets.contains { abs($0 - outer.south) < 0.5 }, "the outer parapet, south")
        XCTAssertTrue(between.isEmpty, "a parapet between the decks: \(between.count) points")
    }

    /// A ramp's walls stand only where it is a parapet's height (1 m) or
    /// more over the ground: lower, the road meets the ground it lies on.
    func testARampNearTheGroundHasNoWalls() throws {
        let world = try flatWorld(track: true)
        let builder = built(world, roads: [road([(512, 300), (512, 470)]), road([(512, 470), (512, 554)], level: 1), road([(512, 554), (512, 724)])])
        let lift = Map3DScene.Builder.lift(of: .secondary), half = Map3DRoadBridges.half(.secondary)
        let walls = meshes(builder).flatMap(\.vertices).filter { (vertex: Map3DVertex) -> Bool in
            let offRamp = vertex.z < 470 || vertex.z > 554
            return Self.concrete.contains(vertex.color) && abs(abs(vertex.x - 512) - half) < 0.05 && vertex.y > 20.05 && offRamp
        }
        XCTAssertFalse(walls.isEmpty, "the ramps' walls")
        let lowest: Float = 20 + lift + Map3DElevatedLook.roadBridge.parapet - 0.1
        let low = walls.filter { $0.y < lowest }
        XCTAssertTrue(low.isEmpty, "\(low.count) wall tops under a metre, the lowest \(low.map(\.y).min() ?? 0)")
    }

    /// Roads on the ground, and a bridge left at the ground (over a river),
    /// draw no parapet or wall.
    func testRoadsOnTheGroundHaveNoParapets() throws {
        let world = try flatWorld(track: false)
        let builder = built(world, roads: [road([(100, 300), (400, 300)]), road([(100, 600), (400, 600)], level: 1), road([(250, 100), (250, 250)])])
        XCTAssertFalse(meshes(builder).flatMap(\.vertices).contains { Self.concrete.contains($0.color) })
    }

    /// Review H4: a road on the ground beside a bridge's end, running
    /// alongside the road that ramps down from it, stays on the ground;
    /// the ramp itself still comes down from the deck, bent as well as
    /// straight (decision 391: the ramp follows the road on from the end).
    func testOnlyTheRoadOnFromABridgesEndRampsDown() throws {
        let world = try flatWorld(track: false)
        let minorLift = Map3DScene.Builder.lift(of: .minor), lift = Map3DScene.Builder.lift(of: .secondary)
        // A bridge over a street, its east end at 400 m a level up (150 m
        // from where it crosses), a straight ramp on east of it.
        let bridge = [road([(100, 300), (400, 300)], level: 1), road([(250, 200), (250, 400)], kind: .minor), road([(400, 300), (700, 300)])]
        for offset in [12.0, 15, 18] {
            // Alongside, from 46 m past the end: a road of its own.
            let side = road([(446, 300 + offset), (700, 300 + offset)], kind: .minor)
            let meshes = meshes(built(world, roads: bridge + [side]))
            for x: Float in [450, 470, 490] {
                XCTAssertEqual(try XCTUnwrap(roadTop(x, 300 + Float(offset), in: meshes, kind: .minor)), 20 + minorLift, accuracy: 0.01,
                               "the road \(offset) m beside the ramp, at \(x)")
            }
            XCTAssertGreaterThan(try XCTUnwrap(roadTop(450, 300, in: meshes)), 20 + lift + 2, "the ramp")
        }
        // A ramp on from the west end bending away, 100 m round.
        let bend = (0...12).map { step -> (Double, Double) in
            let angle = Double(step) * 0.05
            return (100 - 100 * sin(angle), 400 - 100 * cos(angle))
        }
        let meshes = meshes(built(world, roads: [road([(100, 300), (400, 300)], level: 1), road([(250, 200), (250, 400)], kind: .minor), road(bend)]))
        // 30 m round it: some 4 m down from the deck's 6 m.
        let at = (x: Float(100 - 100 * sin(0.3)), z: Float(400 - 100 * cos(0.3)))
        XCTAssertGreaterThan(try XCTUnwrap(roadTop(at.x, at.z, in: meshes)), 20 + lift + 3, "the bent ramp")
    }

    /// Review H6: a junction on the ground under a viaduct running along
    /// its road keeps its paint; none is painted on the deck over it.
    func testAJunctionUnderAViaductKeepsItsPaint() throws {
        let world = try flatWorld(track: false)
        let roads = [road([(100, 600), (500, 600)], level: 1),
                     road([(150, 600), (300, 600), (450, 600)], kind: .primary), road([(300, 400), (300, 600), (300, 800)])]
        let builder = built(world, roads: roads)
        let crosswalks = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.surface == .crosswalk }
        // Across the road under the viaduct, either side of the junction.
        let under = crosswalks.filter { abs($0.z - 600) < 5 && abs($0.x - 300) > 5 && abs($0.x - 300) < 30 }
        XCTAssertFalse(under.isEmpty, "the crossings of the road under the viaduct")
        let ground = Set(under.map { Int(($0.x - 300).sign == .minus ? -1 : 1) })
        XCTAssertEqual(ground, [-1, 1], "both arms along it")
        XCTAssertTrue(under.allSatisfy { $0.y < 20 + 1 }, "on the ground, not the deck")
    }

    /// Review K2-3: the long paint along a road running on from a
    /// bridge's end (the kerb lines and a lane's painted walkway, up to
    /// 64 m a piece) follows its ramp down, each corner at the road's
    /// height there, rather than standing at its middle's height: once
    /// 1.62 m over the ramp at one end and 1.86 m under it at the other.
    func testTheLongPaintFollowsARampDown() throws {
        let world = try flatWorld(track: false)
        // A secondary road and a lane, each a level up over a street and
        // running on east from their bridge's end at 400 m.
        let builder = built(world, roads: [
            road([(100, 300), (400, 300)], level: 1), road([(400, 300), (700, 300)]),
            road([(100, 600), (400, 600)], level: 1, kind: .minor), road([(400, 600), (700, 600)], kind: .minor),
            road([(250, 200), (250, 700)], kind: .minor),
        ])
        let near = Array(builder.nearMeshes.values)
        let meshes = meshes(builder)
        let kerbs: Set<UInt32> = [Map3DScene.Builder.kerbRed, Map3DPalette.centreLine]
        let walkway: Set<UInt32> = [Map3DScene.Builder.walkwayGreen, Map3DScene.Builder.paint]
        let offset = Float(Map3DBaseMap.RoadKind.secondary.width(ramp: false)) / 2 - Float(Map3DRoadMarkings.kerbInset)
        for (z, colours, kind) in [(300 + offset, kerbs, Map3DBaseMap.RoadKind.secondary), (300 - offset, kerbs, .secondary),
                                   (600, walkway, .minor)] {
            let paint = near.flatMap(\.vertices).filter {
                colours.contains($0.color) && $0.x > 401 && $0.x < 690 && (kind == .minor ? abs($0.z - 600) < 3 : abs($0.z - z) < 0.2)
            }
            XCTAssertTrue(paint.contains { $0.x < 440 }, "paint on the ramp by the bridge's end, \(kind)")
            XCTAssertTrue(paint.contains { $0.x > 600 }, "paint on the ground, \(kind)")
            let above = Map3DScene.Builder.centreLineLift - Map3DScene.Builder.lift(of: kind)
            for vertex in paint {
                let top = try XCTUnwrap(roadTop(vertex.x, vertex.z, in: meshes, kind: kind), "the road under \(vertex.x), \(vertex.z)")
                XCTAssertEqual(vertex.y - top, above, accuracy: 0.05, "\(kind) paint at \(vertex.x), \(vertex.z)")
            }
        }
    }

    /// The tallest freeway bridges stand at their real decks: 國姓高架橋's
    /// 265.55 m over the sea at its tallest pier.
    func testTheTallestFreewayBridgeStandsAtItsRealDeck() throws {
        let names = Map3DRoadBridges.tallestFreewayBridges.map(\.name)
        XCTAssertEqual(names.count, 5)
        XCTAssertTrue(names.contains("國六 國姓高架橋 P11"))
        XCTAssertEqual(Map3DRoadBridges.tallestFreewayBridges.map(\.deck).max(), 265.55)
    }
}

/// Decision 391 on the real map, beside the memory test that opens the
/// same demo.
extension Map3DSceneMemoryTests {
    /// Where the base map's road bridges cross the high-speed demo's track
    /// out of a tunnel, the whole network: each crossing point's road
    /// either clears a train over the bed, keeps under a viaduct's girder,
    /// or spans a cutting at the ground. Before decision 391 every bridge
    /// lay on the ground, through the bed and the embankments.
    func testTheDemosRoadBridgesClearTheTrack() throws {
        let world = try HighSpeedDemoTests.opened.get()
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let snapshot = world.railwaySnapshot()
        let metre = Map3DScene.Builder.metre
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: 0, minY: 0, maxX: 1, maxY: 1), world: world,
                                         heights: HighSpeedDemoTests.heights)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        let cover = builder.trackCover
        // The 2,048 m squares the track runs through out of a tunnel.
        let side = 2_048.0
        var squares = Set<Map3DScene.ChunkKey>()
        for piece in cover.pieces where !piece.isTunnel {
            for p in [piece.a, piece.b] { squares.insert(Map3DScene.ChunkKey(column: Int((Double(p.x) / side).rounded(.down)), row: Int((Double(p.z) / side).rounded(.down)))) }
        }
        var crossings = 0, overCutting = 0, before: [Float] = [], after: [Float] = []
        let started = Date()
        for square in squares.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            let region = WorldRegion(minX: Double(square.column) * side * metre, minY: Double(square.row) * side * metre,
                                     maxX: Double(square.column + 1) * side * metre, maxY: Double(square.row + 1) * side * metre)
            let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: 0, originY: 0)
            builder.roadBridges = builder.bridgeDecks(of: map, frame: frame)
            for road in map.roads where road.bridgeLevel > 0 {
                for (a, b) in zip(road.points, road.points.dropFirst()) {
                    guard let (start, end) = Map3DScene.Builder.clipSegment(a, b, to: road.bounds) else { continue }
                    let length = ((end.x - start.x) * (end.x - start.x) + (end.z - start.z) * (end.z - start.z)).squareRoot()
                    guard length > 0.01 else { continue }
                    let along = (x: (end.x - start.x) / length, z: (end.z - start.z) / length)
                    var seen = Set<Int>()
                    let low = Map3DTrackCover.key(x: Float(min(start.x, end.x)), z: Float(min(start.z, end.z)))
                    let high = Map3DTrackCover.key(x: Float(max(start.x, end.x)), z: Float(max(start.z, end.z)))
                    for row in low.row...high.row {
                        for column in low.column...high.column {
                            for index in cover.cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] where seen.insert(index).inserted {
                                let piece = cover.pieces[index]
                                let pa = Map3DBaseMap.Point(x: Double(piece.a.x), z: Double(piece.a.z)), pb = Map3DBaseMap.Point(x: Double(piece.b.x), z: Double(piece.b.z))
                                guard !piece.isTunnel, let share = Map3DRoadBridges.crossing(start, end, pa, pb) else { continue }
                                let at = Map3DBaseMap.Point(x: start.x + (end.x - start.x) * share, z: start.z + (end.z - start.z) * share)
                                let rail = Map3DRoadBridges.nearest(at, pa, pb).point
                                let t = Float(((rail.x - pa.x) * (pb.x - pa.x) + (rail.z - pa.z) * (pb.z - pa.z)) / max((pb.x - pa.x) * (pb.x - pa.x) + (pb.z - pa.z) * (pb.z - pa.z), 1e-9))
                                let bed = piece.a.y + (piece.b.y - piece.a.y) * t - Map3DScene.Builder.bedDrop
                                let ground = builder.drawnGround(x: Float(at.x), z: Float(at.z))
                                crossings += 1
                                if bed <= ground - Map3DRoadBridges.overTrack {
                                    overCutting += 1
                                    continue
                                }
                                let lift = Map3DScene.Builder.lift(of: road.kind)
                                func short(_ top: Float) -> Float? {
                                    if top >= bed + Map3DRoadBridges.overTrack - 0.05 { return nil }
                                    if piece.isViaduct, top <= bed - Map3DRoadBridges.underViaduct + 0.05 { return nil }
                                    return bed + Map3DRoadBridges.overTrack - top
                                }
                                if let depth = short(ground + lift) { before.append(depth) }
                                if let depth = short(ground + lift + builder.roadRise(at: at, along: along, onDeck: true).rise) { after.append(depth) }
                            }
                        }
                    }
                }
            }
        }
        print("Map3DSceneMemoryTests: road bridges over the demo's track, \(squares.count) squares in \(Int(Date().timeIntervalSince(started))) s:",
              "\(crossings) crossings, \(overCutting) over a cutting; laid on the ground \(before.count) short (most \(before.max() ?? 0) m),",
              "raised \(after.count) short (most \(after.max() ?? 0) m)")
        XCTAssertGreaterThan(crossings, 20, "bridges cross the line")
        XCTAssertTrue(after.isEmpty, "\(after.count) crossings short of clearing the track, most \(after.max() ?? 0) m")
    }

    /// Decision 391 (續篇二, HANDOFF §4.12 第 6 點): where the base map's
    /// roads on the ground cross the demo's track out of a tunnel, the
    /// whole network. Before, each on an embankment or in a cutting ran
    /// into it (under the bank, cut by the cutting); now each goes over,
    /// clear of a train over the bed.
    func testTheDemosRoadsOnTheGroundGoOverItsEmbankmentsAndCuttings() throws {
        let world = try HighSpeedDemoTests.opened.get()
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let snapshot = world.railwaySnapshot()
        let metre = Map3DScene.Builder.metre
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: 0, minY: 0, maxX: 1, maxY: 1), world: world,
                                         heights: HighSpeedDemoTests.heights)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        let side = 2_048.0
        var squares = Set<Map3DScene.ChunkKey>()
        for piece in builder.trackCover.pieces where !piece.isTunnel {
            for p in [piece.a, piece.b] { squares.insert(Map3DScene.ChunkKey(column: Int((Double(p.x) / side).rounded(.down)), row: Int((Double(p.z) / side).rounded(.down)))) }
        }
        var kinds: [Map3DRoadBridges.Crossing: Int] = [:], banks: [Float] = [], short: [Float] = [], unopened = 0
        for square in squares.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            let region = WorldRegion(minX: Double(square.column) * side * metre, minY: Double(square.row) * side * metre,
                                     maxX: Double(square.column + 1) * side * metre, maxY: Double(square.row + 1) * side * metre)
            let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: 0, originY: 0)
            // The square's own roads on the ground, each crossing counted once.
            var own = builder
            own.roadBridges = own.bridgeDecks(of: Map3DBaseMap(roads: map.roads.filter { $0.bridgeLevel == 0 }), frame: frame)
            for (kind, count) in own.roadBridges.crossings { kinds[kind, default: 0] += count }
            builder.roadBridges = builder.bridgeDecks(of: map, frame: frame)
            for join in own.roadBridges.joins {
                let ground = builder.drawnGround(x: Float(join.point.x), z: Float(join.point.z))
                let bed = join.height - Map3DRoadBridges.overTrack
                if bed > ground { banks.append(bed - ground) }
                let rise = builder.roadRise(at: join.point, along: (join.along.x, join.along.z), onDeck: false).rise
                if ground + rise < join.height - 0.05 { short.append(join.height - ground - rise) }
            }
            // Under an embankment tall enough, the road stays on the
            // ground and the bank opens over it.
            for opening in own.roadBridges.openings {
                let pieces = own.trackCover.pieces.filter { !$0.isTunnel && Map3DRoadBridges.nearest(opening.point, Map3DBaseMap.Point(x: Double($0.a.x), z: Double($0.a.z)),
                                                                                                 Map3DBaseMap.Point(x: Double($0.b.x), z: Double($0.b.z))).distance < 1 }
                if !pieces.contains(where: { !own.openings(of: [$0.a, $0.b]).spans.isEmpty }) { unopened += 1 }
            }
        }
        banks.sort()
        let quartiles = banks.isEmpty ? [] : [0, 0.25, 0.5, 0.75, 1].map { banks[Int(Float(banks.count - 1) * $0)] }
        print("Map3DSceneMemoryTests: roads on the ground across the demo's track:", kinds.sorted { "\($0.key)" < "\($1.key)" },
              "; embankments gone over, quartiles", quartiles.map { String(format: "%.1f", $0) })
        XCTAssertGreaterThan((kinds[.overCutting] ?? 0) + (kinds[.overEmbankment] ?? 0), 20)
        XCTAssertTrue(short.isEmpty, "\(short.count) crossings short of clearing the track, most \(short.max() ?? 0) m")
        XCTAssertEqual(unopened, 0, "embankments not open over the road under them")
    }
}
