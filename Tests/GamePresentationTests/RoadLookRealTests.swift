import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 822 (ROAD-LOOK-REAL; the owner's four screenshots of
/// 2026-11-17, the default real map's elevated roads over a river at
/// 07:40): what the real map's water and roads looked like, each a
/// measurement that was red on main `003a1bf`.
final class RoadLookRealTests: XCTestCase {
    /// A world 1,024 m square whose ground stands 20 m high.
    private func flatWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        return world
    }

    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)

    private static func points(_ list: [(Double, Double)]) -> [Map3DBaseMap.Point] {
        list.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }
    }

    /// `map` laid on `world` as a real map's is.
    private func built(_ world: GameWorld, _ map: Map3DBaseMap) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.addGround(water: false)
        _ = builder.addBaseMap(map)
        return builder
    }

    /// The builder's triangles reaching into the square `minX`…`maxX`,
    /// `minZ`…`maxZ`.
    private func triangles(_ builder: Map3DScene.Builder, minX: Float = -.infinity, minZ: Float = -.infinity,
                           maxX: Float = .infinity, maxZ: Float = .infinity) -> [[Map3DVertex]] {
        (Array(builder.meshes.values) + Array(builder.nearMeshes.values)).flatMap { mesh in
            stride(from: 0, to: mesh.indices.count - 2, by: 3).compactMap { index -> [Map3DVertex]? in
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] }
                let xs = triangle.map(\.x), zs = triangle.map(\.z)
                guard xs.max()! >= minX, xs.min()! <= maxX, zs.max()! >= minZ, zs.min()! <= maxZ else { return nil }
                return triangle
            }
        }
    }

    /// The faces over (`x`, `z`): each one's height, colour and layer.
    private func faces(over x: Float, _ z: Float, in triangles: [[Map3DVertex]]) -> [(y: Float, color: UInt32, layer: Float)] {
        triangles.compactMap { triangle in
            Map3DTrenchTests.heights(over: x, z, in: [triangle], colours: [triangle[0].color]).first.map { ($0, triangle[0].color, triangle[0].layer) }
        }
    }

    /// Whether (`x`, `z`) lies inside `ring` (even and odd).
    private func inside(_ x: Double, _ z: Double, _ ring: [Map3DBaseMap.Point]) -> Bool {
        var inside = false
        var previous = ring[ring.count - 1]
        for point in ring {
            if (point.z > z) != (previous.z > z), x < (previous.x - point.x) * (z - point.z) / (previous.z - point.z) + point.x { inside.toggle() }
            previous = point
        }
        return inside
    }

    /// A river 824 m square with an island in it, across several of the
    /// ground's 64 m cells.
    private static let river = points([(100, 100), (924, 100), (924, 924), (100, 924)])
    private static let island = points([(300, 330), (560, 300), (700, 520), (520, 700), (330, 600)])

    /// The points of the island 3 m or more inside its shore, every 4 m.
    private func islandPoints() -> [(Double, Double)] {
        var found: [(Double, Double)] = []
        for x in stride(from: 300.0, through: 700, by: 4) {
            for z in stride(from: 300.0, through: 700, by: 4) where inside(x, z, Self.island) {
                let near = [(-3.0, 0.0), (3, 0), (0, -3), (0, 3)].contains { !inside(x + $0.0, z + $0.1, Self.island) }
                if !near { found.append((x, z)) }
            }
        }
        return found
    }

    /// IMG_5325 and IMG_5322: sharp triangles of water over the river's
    /// islands. A river's outline, cut to each 64 m cell's triangle with
    /// its island's cut beside it, was triangulated with the island's
    /// piece touching the cell's edge, and the whole triangle came out
    /// water.
    func testNoWaterLiesOverARiversIsland() throws {
        let map = Map3DBaseMap(areas: [Map3DBaseMap.Area(cover: .water, rings: [Self.river, Self.island], bounds: Self.bounds)])
        let builder = built(try flatWorld(), map)
        let triangles = triangles(builder, minX: 290, minZ: 290, maxX: 710, maxZ: 710) + triangles(builder, minX: 140, minZ: 140, maxX: 160, maxZ: 160)
        let points = islandPoints()
        XCTAssertGreaterThan(points.count, 3_000)
        let wet = points.filter { faces(over: Float($0.0), Float($0.1), in: triangles).contains { $0.layer == Map3DVertex.water } }
        print("ROADLOOK island points \(points.count), under water \(wet.count)")
        XCTAssertEqual(wet.count, 0, "the island's points with water drawn over them")
        // And the river round it stays water.
        let shore = [(150.0, 150.0), (620, 300), (680, 420), (360, 660)]
        for (x, z) in shore {
            XCTAssertTrue(faces(over: Float(x), Float(z), in: triangles).contains { $0.layer == Map3DVertex.water }, "water at \(x), \(z)")
        }
    }

    /// IMG_5324: grey strips in the water. An island the tiles give no
    /// cover of its own (a hole in a river's outline, a sandbar or a
    /// mudflat such as the Tamsui's beside 華江) showed the bare ground
    /// under the river, grey at 07:40.
    func testARiversIslandIsNoBareGround() throws {
        let map = Map3DBaseMap(areas: [Map3DBaseMap.Area(cover: .water, rings: [Self.river, Self.island], bounds: Self.bounds)])
        let drawn = triangles(built(try flatWorld(), map), minX: 290, minZ: 290, maxX: 710, maxZ: 710)
        let points = islandPoints()
        let bare = points.filter { point in
            faces(over: Float(point.0), Float(point.1), in: drawn).max { $0.y < $1.y }.map { $0.color == Map3DPalette.ground } ?? true
        }
        print("ROADLOOK island points \(points.count), bare ground \(bare.count)")
        XCTAssertEqual(bare.count, 0, "the island's points showing the ground under the river")
        // The sea's holes are the land: no island drawn over them.
        var sea = Map3DBaseMap.Area(cover: .water, rings: [Self.river, Self.island], bounds: Self.bounds)
        sea.isSea = true
        let land = triangles(built(try flatWorld(), Map3DBaseMap(areas: [sea])), minX: 290, minZ: 290, maxX: 710, maxZ: 710)
        let covered = points.filter { point in
            faces(over: Float(point.0), Float(point.1), in: land).contains { $0.color == Map3DPalette.cover(Map3DScene.Builder.islandCover) }
        }
        XCTAssertEqual(covered.count, 0, "the land in a sea's hole")
    }
}
