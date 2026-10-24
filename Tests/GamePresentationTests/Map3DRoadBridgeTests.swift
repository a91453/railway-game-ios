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
    /// y = 512 m from 64 m to 960 m at the ground.
    private func flatWorld(track: Bool) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        if track {
            let nodes = try [64, 960].map { x in try world.buildTrackNode(at: WorldCoordinate(x: Int64(x) * 64, y: Self.lineY, z: 20 * 64)) }
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
}
