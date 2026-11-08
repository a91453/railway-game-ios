import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 634: in the high-speed demo's 3D map the south end of Liujia's
/// depot stood out over the water of the Touqian River. The demo lays the
/// depot's eight sidings, ladder and all, some 820 m long, centred on the
/// real yard, whose tracks are some 420 m and end on the river's north
/// bank; so its south 190 m lay over the river. Now the sidings end where
/// the real ones do and reach north from there.
extension HighSpeedDemoTests {
    /// The points of Liujia's sidings over the water the 3D map draws, and
    /// how many it checked.
    private static func liujiaSidingsOverWater() throws -> (wet: [Map3DPoint], checked: Int) {
        let (layout, world, tracks) = try built.get()
        let depot = layout.depots[1]
        let middle = layout.plan.path.point(at: (depot.entry + depot.deadEnd) / 2)
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let scene = Map3DScene(world: world, focus: (middle.x, middle.y), baseMap: tiles, heights: heights)
        // The ground there is some 40 to 47 m up; the water is the ground
        // drawn as water within a few metres of the height asked.
        let water = scene.drawnWater(round: Map3DPoint(0, 45, 0), radius: 3_000)
        var wet: [Map3DPoint] = [], checked = 0
        for edge in world.network.edges where tracks.sidings.contains(edge.id) {
            guard let geometry = world.trackGeometry(of: edge.id) else { continue }
            for point in geometry.points {
                let drawn = scene.point(worldX: Double(point.x), worldY: Double(point.y), height: Double(point.z))
                guard abs(drawn.x) < 2_000, abs(drawn.z) < 2_000 else { continue }
                checked += 1
                if water.isWater(x: drawn.x, z: drawn.z) { wet.append(drawn) }
            }
        }
        return (wet, checked)
    }

    func testLiujiaDepotStaysOnTheNorthBankOfTheTouqianRiver() throws {
        let (wet, checked) = try Self.liujiaSidingsOverWater()
        XCTAssertGreaterThan(checked, 100, "Liujia's sidings in the scene")
        XCTAssertTrue(wet.isEmpty, "\(wet.count) of \(checked) points of Liujia's sidings over the river, the southmost \(wet.max { $0.z < $1.z }.map { "\($0.z) m" } ?? "")")
    }

    /// Its sidings end where the real ones do, half the real tracks' length
    /// south of the real yard's middle.
    func testLiujiaDepotEndsWhereTheRealTracksDo() throws {
        let (layout, _, _) = try Self.built.get()
        let depot = layout.depots[1]
        let point = WorldVector(HighSpeedDemo.frame.worldPosition(latitude: depot.real.latitude, longitude: depot.real.longitude))
        let real = layout.plan.path.project(point)
        XCTAssertEqual((depot.deadEnd - real) / Self.metre, 210, accuracy: 5, "the real tracks' south end")
    }
}
