import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// 103.1 and 104.1 (TRI3D): on a real-world map's slopes the 3D map
/// showed big triangles of paving beside the track (濁水, 竹中). A city lot the real track
/// crosses gets a plaza, and an open lot a field or a park, each a square
/// of the 64 m cell; they were laid flat at the lot's middle, while the
/// ground under them is drawn as the cell's two sloping triangles, so the
/// ground dipped under one corner of the square and the square stuck out
/// of the hill there. Now each square lies on the drawn ground.
final class Map3DLotGroundTests: XCTestCase {
    /// The squares' colours (``Map3DScene/Builder/addCity``).
    private static let squares: Set<UInt32> = [Map3DPalette.plaza, Map3DPalette.farm, Map3DPalette.park]

    /// The vertices of `scene`'s lot squares under its drawn ground (the
    /// ground hides the square there) or more than `tolerance` metres
    /// over it, and how many it checked. The base map's land of the same
    /// colours lies on the drawn ground too, its lift over it.
    private static func offGround(_ scene: Map3DScene, world: GameWorld, tolerance: Float = 0.5) -> (off: [(Map3DPoint, Float)], checked: Int) {
        var off: [(Map3DPoint, Float)] = [], checked = 0
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.farWithBoxes] {
                for index in mesh.indices {
                    let vertex = mesh.vertices[Int(index)]
                    guard squares.contains(vertex.color), vertex.ny > 0.5 else { continue }
                    checked += 1
                    let gap = vertex.y - scene.drawnGround.height(x: vertex.x, z: vertex.z, world: world)
                    if gap < 0.01 || gap > tolerance { off.append((vertex.position, gap)) }
                }
            }
        }
        return (off, checked)
    }

    /// A real-world game at `name`'s station, its 3D map 1.2 km across
    /// round it with the real lines, the heights and the base map.
    private static func scene(at name: String, system: String = "tra_sched") throws -> (scene: Map3DScene, world: GameWorld) {
        let station = try BundledRealData.station(name, in: system)
        // With its ground mapped, as a real-world game's is (without it
        // the ground is 0 m everywhere and every square lies flat on it).
        var world = GameWorld.newGame(anchor: try XCTUnwrap(station.anchor))
        try world.mapGround()
        let centre = try BundledRealData.point(station.coordinate, in: world)
        let half = 600 * Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: Double(centre.x) - half, minY: Double(centre.y) - half,
                                 maxX: Double(centre.x) + half, maxY: Double(centre.y) + half)
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world),
                               frame: (region, Double(centre.x).rounded(), Double(centre.y).rounded()), baseMap: try tiles.get(), cityTiles: [],
                               heights: try heights.get(), lineBands: nil, railways: Map3DRealTrainsTests.railways, temples: nil)
        return (scene, world)
    }

    private static let tiles = Result {
        try BaseMapTiles(data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private static let heights = Result {
        try HeightGrid(data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("RealWorld/taiwan_heights.dat")))
    }

    func testTheLotSquaresLieOnTheDrawnGroundBesideTheJijiLine() throws {
        let (scene, world) = try Self.scene(at: "濁水")
        let (off, checked) = Self.offGround(scene, world: world)
        XCTAssertGreaterThan(checked, 0, "squares to check")
        XCTAssertTrue(off.isEmpty, "\(off.count) of \(checked) corners off the ground, the worst \(off.max { abs($0.1) < abs($1.1) }.map { "\($0.1) m at \($0.0)" } ?? "")")
    }

    func testTheLotSquaresLieOnTheDrawnGroundAtZhuzhong() throws {
        let (scene, world) = try Self.scene(at: "竹中")
        let (off, checked) = Self.offGround(scene, world: world)
        XCTAssertGreaterThan(checked, 0, "squares to check")
        XCTAssertTrue(off.isEmpty, "\(off.count) of \(checked) corners off the ground, the worst \(off.max { abs($0.1) < abs($1.1) }.map { "\($0.1) m at \($0.0)" } ?? "")")
    }

    /// How many stations' maps show it, every station of the bundled
    /// lines: `MAP3D_LOT_GROUND_REPORT=1`.
    func testEveryStationReport() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_LOT_GROUND_REPORT"] != nil else { throw XCTSkip("Set MAP3D_LOT_GROUND_REPORT=1.") }
        let railways = try XCTUnwrap(Map3DRealTrainsTests.railways)
        var seen = Set<String>(), bad: [(String, Int, Float)] = [], total = 0
        for station in railways.stations where station.system.id == "tra_sched" {
            guard seen.insert(station.chinese).inserted, let (scene, world) = try? Self.scene(at: station.chinese) else { continue }
            total += 1
            let (off, _) = Self.offGround(scene, world: world)
            if !off.isEmpty { bad.append((station.chinese, off.count, off.map { abs($0.1) }.max() ?? 0)) }
        }
        print("LOT GROUND: \(bad.count) of \(total) stations have squares off the ground")
        for (name, count, worst) in bad.sorted(by: { $0.2 > $1.2 }) { print("LOT GROUND \(name): \(count) corners, worst \(worst) m") }
    }
}
