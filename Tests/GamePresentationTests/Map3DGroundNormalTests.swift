import GameCore
@testable import GamePresentation
import XCTest

/// Decision 965: the ground is lit by its smoothed slope, each 64 m
/// corner's way up from the heights round it, not by each square's own
/// face. A steep valley side was a row of light and dark triangles
/// (TERRAIN-CHECK-A, the Keelung River's bend at Dahua).
final class Map3DGroundNormalTests: XCTestCase {
    /// A one-block world whose corners stand at `height(row, column)` metres.
    private func world(_ height: (Int, Int) -> Int) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        let heights = (0..<(side * side)).map { Int16(height($0 / side, $0 % side)) }
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights))])
        return world
    }

    /// The ground's vertices away from the block's edge, by where they
    /// stand (to the centimetre), with every normal each was given.
    private func groundNormals(_ world: GameWorld) -> [SIMD3<Int>: [Map3DPoint]] {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.addGround()
        var found: [SIMD3<Int>: [Map3DPoint]] = [:]
        for mesh in builder.meshes.values {
            for vertex in mesh.vertices where vertex.color == Map3DPalette.ground && vertex.layer == Map3DVertex.plain {
                let p = vertex.position
                guard p.x > 64, p.x < 960, p.z > 64, p.z < 960 else { continue }
                let key = SIMD3(Int((p.x * 100).rounded()), Int((p.y * 100).rounded()), Int((p.z * 100).rounded()))
                found[key, default: []].append(Map3DPoint(vertex.nx, vertex.ny, vertex.nz))
            }
        }
        return found
    }

    /// On an even slope every vertex faces the slope's own way, as before.
    func testAnEvenSlopeFacesItsOwnWay() throws {
        let found = groundNormals(try world { _, column in 4 * column })
        XCTAssertFalse(found.isEmpty)
        let slope = try XCTUnwrap(Map3DPoint(-4.0 / 64, 1, 0).normalized)
        for (at, normals) in found {
            for normal in normals {
                XCTAssertEqual((normal - slope).length, 0, accuracy: 1e-4, "at \(at)")
            }
        }
    }

    /// Across a valley's floor and a ridge, the squares meeting at a
    /// corner give it one normal, so the light runs on with no seam.
    func testSquaresMeetingAtACornerAreLitAlike() throws {
        let found = groundNormals(try world { row, column in 12 * abs(column - 8) + 3 * abs(row - 6) })
        var shared = 0
        for (at, normals) in found where normals.count > 1 {
            shared += 1
            for normal in normals.dropFirst() {
                XCTAssertEqual((normal - normals[0]).length, 0, accuracy: 1e-5, "at \(at)")
            }
        }
        XCTAssertGreaterThan(shared, 100, "the squares share their corners' vertices' places")
        // The valley's floor (column 8) faces straight up across it, its
        // sides each their own way.
        let floor = try XCTUnwrap(found.first { $0.key.x == 512 * 100 && $0.key.z == 320 * 100 }?.value.first)
        XCTAssertEqual(floor.x, 0, accuracy: 1e-5)
        let west = try XCTUnwrap(found.first { $0.key.x == 256 * 100 && $0.key.z == 320 * 100 }?.value.first)
        let east = try XCTUnwrap(found.first { $0.key.x == 768 * 100 && $0.key.z == 320 * 100 }?.value.first)
        XCTAssertGreaterThan(west.x, 0.1, "the west side faces east")
        XCTAssertLessThan(east.x, -0.1, "the east side faces west")
    }

    /// What lies on the ground is lit as the ground under it: the
    /// smoothed normal at a point runs between its square's corners'.
    func testThePointsBetweenTheCornersRunBetweenTheirNormals() throws {
        let world = try world { row, column in 12 * abs(column - 8) + 3 * abs(row - 6) }
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let corner = builder.groundCornerNormal(row: 5, column: 7)
        XCTAssertEqual((builder.groundNormal(x: 448, z: 320) - corner).length, 0, accuracy: 1e-5)
        let next = builder.groundCornerNormal(row: 5, column: 8)
        let between = builder.groundNormal(x: 480, z: 320)
        let expected = try XCTUnwrap(((corner + next) * 0.5).normalized)
        XCTAssertEqual((between - expected).length, 0, accuracy: 1e-5)
        XCTAssertEqual(between.length, 1, accuracy: 1e-5)
    }
}
