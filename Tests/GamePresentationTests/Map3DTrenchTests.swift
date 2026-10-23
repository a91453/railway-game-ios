import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 375 (the owner's iPhone 17 Pro, 84.1, the high-speed demo at
/// 10× from the cab): the ground, the base map's land and its roads lay
/// over track that runs below the drawn ground (a cutting, and surface
/// track a little under the 64 m triangles), so the cab saw a road and a
/// white plane running into the hills instead of the rails. The track's
/// trench is cut out of them now, its slopes drawn down to the bed.
final class Map3DTrenchTests: XCTestCase {
    /// A world 1,024 m square whose ground stands 20 m high: track from
    /// 64 m to 960 m along y = 512 m, falling from the ground to 8 m under
    /// it at 448 m, level to 576 m and back up (a cutting between).
    private func cuttingWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        let nodes = try [(64, 20), (448, 12), (576, 12), (960, 20)].map { x, z in
            try world.buildTrackNode(at: WorldCoordinate(x: Int64(x) * 64, y: Self.lineY, z: Int64(z) * 64))
        }
        for (a, b) in zip(nodes, nodes.dropFirst()) { try world.buildTrackEdge(from: a, to: b, structure: .automatic) }
        XCTAssertTrue(world.network.edges.contains { $0.sectionSpans.contains { $0.kind == .cutting } })
        return world
    }

    private static let lineY: Int64 = 32_768

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The rails' height at `x` metres along the cutting world's track.
    private func railHeight(atMetre x: Float) -> Float {
        let z: Float = x <= 448 ? 20 - 8 * (x - 64) / 384 : x <= 576 ? 12 : 12 + 8 * (x - 576) / 384
        return z + Map3DScene.railLift
    }

    /// The colours of the ground and of what lies on it: the land, its
    /// cover, the roads and their paint.
    static let groundColours: Set<UInt32> = {
        var colours: Set<UInt32> = [Map3DPalette.ground, Map3DPalette.water, Map3DPalette.sidewalk, Map3DPalette.centreLine]
        for cover in Map3DBaseMap.Cover.allCases { colours.insert(Map3DPalette.cover(cover)) }
        for road in Map3DBaseMap.RoadKind.allCases { colours.insert(Map3DPalette.road(road)) }
        return colours
    }()

    /// Every triangle of `meshes` that `colours` paints and that lies over
    /// scene point (`x`, `z`), with its height there.
    static func heights(over x: Float, _ z: Float, in meshes: [Map3DMesh], colours: Set<UInt32>) -> [Float] {
        heights(over: x, z, in: meshes.flatMap { mesh in
            stride(from: 0, to: mesh.indices.count - 2, by: 3).map { index in (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] } }
        }, colours: colours)
    }

    /// The same, of `triangles` given by their corners.
    static func heights(over x: Float, _ z: Float, in triangles: [[Map3DVertex]], colours: Set<UInt32>) -> [Float] {
        var found: [Float] = []
        for triangle in triangles {
            let a = triangle[0], b = triangle[1], c = triangle[2]
            guard colours.contains(a.color) else { continue }
            let d = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
            guard abs(d) > 1e-6 else { continue }
            let l1 = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
            let l2 = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
            let l3 = 1 - l1 - l2
            guard l1 >= -1e-4, l2 >= -1e-4, l3 >= -1e-4 else { continue }
            found.append(l1 * a.y + l2 * b.y + l3 * c.y)
        }
        return found
    }

    /// The owner's report: no ground over the bed of track below the
    /// ground, where the cab looks.
    func testNoGroundLiesOverTheTrackInACutting() throws {
        let world = try cuttingWorld()
        let scene = Map3DScene(world: world)
        let meshes = scene.chunks.map(\.mesh)
        let lineZ = scene.point(worldX: 0, worldY: Double(Self.lineY), height: 0).z
        var covered: [(Float, Float)] = []
        for metre in stride(from: Float(100), through: 920, by: 8) {
            let x = scene.point(worldX: Double(metre) * 64, worldY: 0, height: 0).x
            let bed = railHeight(atMetre: metre) - Map3DScene.Builder.bedDrop
            for across: Float in [-1.5, 0, 1.5] {
                if let over = Self.heights(over: x, lineZ + across, in: meshes, colours: Self.groundColours).first(where: { $0 > bed + 0.05 }) {
                    covered.append((metre, over))
                }
            }
        }
        XCTAssertTrue(covered.isEmpty, "\(covered.count) points of ground over the bed, first \(covered.prefix(3))")
        // The trench's slopes, from its floor up to the ground on both
        // sides, at the deepest: 7.8 m deep, so 2.9 + 7.8 m out.
        let x = scene.point(worldX: 512 * 64, worldY: 0, height: 0).x
        let banks = scene.chunks.flatMap(\.mesh.vertices).filter { $0.color == Map3DPalette.embankment && abs($0.x - x) < 24 }
        for side: Float in [-1, 1] {
            XCTAssertTrue(banks.contains { abs($0.z - (lineZ + side * 10.7)) < 0.6 && abs($0.y - 20) < 0.05 }, "its rim, side \(side)")
        }
        // The cab follows the rails, not the ground over them.
        let rail = Map3DPoint(x, railHeight(atMetre: 512), lineZ)
        let ground = try XCTUnwrap(scene.trackCover.ground(at: rail))
        XCTAssertLessThanOrEqual(ground.height, rail.y - Map3DScene.Builder.bedDrop + 0.01)
        XCTAssertFalse(ground.inTunnel)
    }

    /// A road along the track gives way to the trench; one across it,
    /// clear of a train, stays as a bridge over it.
    func testARoadGivesWayToTheTrenchOrBridgesIt() throws {
        let world = try cuttingWorld()
        let snapshot = world.railwaySnapshot()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround()
        let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)
        let along = Map3DBaseMap.Road(kind: .primary, isRamp: false, points: [.init(x: 80, z: 512), .init(x: 940, z: 512)], bounds: bounds)
        let across = Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: [.init(x: 512, z: 400), .init(x: 512, z: 624)], bounds: bounds)
        var taken = Set<Map3DScene.ChunkKey>()
        builder.addRoads([along, across], taking: &taken)
        _ = builder.addTrack(snapshot)
        let meshes = Array(builder.meshes.values) + Array(builder.nearMeshes.values)
        var covered: [(Float, Float)] = []
        for metre in stride(from: Float(100), through: 920, by: 8) where abs(metre - 512) > 12 {
            let bed = railHeight(atMetre: metre) - Map3DScene.Builder.bedDrop
            for offset: Float in [-1.5, 0, 1.5] {
                if let over = Self.heights(over: metre, 512 + offset, in: meshes, colours: Self.groundColours).first(where: { $0 > bed + 0.05 }) {
                    covered.append((metre, over))
                }
            }
        }
        XCTAssertTrue(covered.isEmpty, "\(covered.count) points of road or ground over the bed, first \(covered.prefix(3))")
        // The road across, over the 7.5 m deep trench at the ground's
        // height: a bridge the train runs under.
        let bridge = Self.heights(over: 512, 512, in: meshes, colours: [Map3DPalette.road(.secondary)])
        XCTAssertTrue(bridge.contains { abs($0 - 20 - Map3DScene.Builder.lift(of: .secondary)) < 0.01 }, "\(bridge)")
        // No traffic along the road where it gave way: its lanes keep to
        // the ground on either side.
        let lanes = builder.streetLife.lanes.flatMap(\.path.points)
        XCTAssertFalse(lanes.contains { $0.x > 120 && $0.x < 900 && abs($0.x - 512) > 8 && abs($0.z - 512) < 1 },
                       "a lane over the trench")
        XCTAssertTrue(lanes.contains { abs($0.x - 512) < 1 && abs($0.z - 512) < 1 && $0.y > 19 }, "the bridge's traffic")
    }
}

/// Decision 375 on the real map, beside the memory test that opens the
/// same demo (a minute or two of a CI job), so it is opened once.
extension Map3DSceneMemoryTests {
    /// The owner's view: the high-speed demo with the app's base map and
    /// heights, round its deepest cutting (some 20 m, south of Miaoli):
    /// along every trench there, nothing of the ground, the land or the
    /// roads over the bed but a road bridging it, clear of a train. Before
    /// decision 375 the ground lay over nearly all of it.
    func testTheHighSpeedDemosCuttingIsOpen() throws {
        let world = try HighSpeedDemoTests.opened.get()
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let snapshot = world.railwaySnapshot()
        let origin = (x: 179_006 * Map3DScene.Builder.metre, y: 68_767 * Map3DScene.Builder.metre)
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: WorldRegion(minX: origin.x, minY: origin.y,
                                         maxX: origin.x + 1, maxY: origin.y + 1), world: world, heights: HighSpeedDemoTests.heights)
        let cover = Map3DTrackCover(snapshot, builder: &builder)
        let keys = (-1...0).flatMap { row in (-1...0).map { Map3DStreaming.Key(column: $0, row: row) } }
        let chunks = Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, baseMap: tiles, heights: HighSpeedDemoTests.heights,
                                       trackCover: cover)
        let meshes = chunks.map(\.mesh)
        let roads = Set(Map3DBaseMap.RoadKind.allCases.map { Map3DPalette.road($0) }).union([Map3DPalette.sidewalk, Map3DPalette.centreLine])
        let size = Map3DScene.chunkSize
        // Only the triangles near the track, 8 m squares of them.
        var near: [Map3DScene.ChunkKey: [[Map3DVertex]]] = [:]
        let keyOf = { (x: Float, z: Float) in Map3DScene.ChunkKey(column: Int((x / 8).rounded(.down)), row: Int((z / 8).rounded(.down))) }
        for mesh in meshes {
            var index = 0
            while index + 2 < mesh.indices.count {
                defer { index += 3 }
                let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] }
                guard Map3DTrenchTests.groundColours.contains(corners[0].color) else { continue }
                let low = keyOf(corners.map(\.x).min()!, corners.map(\.z).min()!), high = keyOf(corners.map(\.x).max()!, corners.map(\.z).max()!)
                guard high.column - low.column < 64, high.row - low.row < 64 else { continue }
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        near[Map3DScene.ChunkKey(column: column, row: row), default: []].append(corners)
                    }
                }
            }
        }
        var sections = 0, bridged = 0
        var covered: [(Float, Float, Float)] = []
        for (r, run) in cover.trenches.runs.enumerated() {
            // A portal's own line: the ground over the tunnel's mouth.
            let ends = cover.trenches.portalEnds[r]
            for (i, section) in run.enumerated() where section.rail.x > -size && section.rail.x < size && section.rail.z > -size && section.rail.z < size
                && !(i == 0 && ends.first) && !(i == run.count - 1 && ends.last) {
                sections += 1
                let bed = section.rail.y - Map3DScene.Builder.bedDrop
                for offset: Float in [-1.5, 0, 1.5] {
                    let p = section.rail + section.across * offset
                    for colours in [Map3DTrenchTests.groundColours.subtracting(roads), roads] {
                        for height in Map3DTrenchTests.heights(over: p.x, p.z, in: near[keyOf(p.x, p.z)] ?? [], colours: colours) where height > bed + 0.05 {
                            if colours == roads, height >= bed + Map3DTrenches.bridgeDepth { bridged += 1 } else { covered.append((p.x, p.z, height - bed)) }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(sections, 50, "the cutting is round here")
        XCTAssertTrue(covered.isEmpty, "\(covered.count) points over the bed of \(sections * 3), first \(covered.prefix(3))")
        print("Map3DSceneMemoryTests: \(sections) sections, \(bridged) points under a road's bridge, \(chunks.count) chunks")
    }
}
