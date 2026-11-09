import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 674: the underground platforms seeing underground lays
/// (``Map3DXRay/platforms(_:in:)``), on real underground stations. The
/// Wenhu Line's screenshots of decision 672 had none (its Songshan
/// Airport station is in a cutting in the game); the demo's real lines
/// round Taipei Main Station are all underground there (the Bannan Line,
/// the Tamsui–Xinyi Line, the Airport MRT's terminus).
@MainActor
final class Map3DXRayRealTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    func testTaipeiMainStationsUndergroundPlatformsAreLaidWhereTheyAre() async throws {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        try world.mapGround()
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        let heights = try HeightGrid(
            data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat"))
        )
        session.heights = heights
        session.railways = try BundledRealData.railways()
        session.news.isDemo = true
        let centre = try BundledRealData.point(tra.coordinate, in: session.world)
        let x = Double(centre.x), y = Double(centre.y), reach = 1_500 * metre
        let laid = await session.layDemoRealLines(in: WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach))
        XCTAssertNotNil(laid)
        let built = session.world
        let snapshot = built.railwaySnapshot()
        let scene = Map3DScene(world: built, snapshot: snapshot, focus: (x, y), heights: heights)

        let buried = snapshot.platforms.filter { $0.structure == .tunnel && $0.points.count > 1 }
        XCTAssertFalse(buried.isEmpty)
        let platforms = Map3DXRay.platforms(snapshot, in: scene)
        XCTAssertEqual(platforms.count, buried.count, "every underground platform laid")

        var report: [String] = []
        for (platform, source) in zip(platforms, buried) {
            let station = try XCTUnwrap(built.station(id: platform.station))
            // Along its own track, at the rails' height.
            let track = source.points.map { scene.point($0) + Map3DScene.Builder.lifted }
            XCTAssertEqual(platform.line, track)
            // At its station: its middle within 300 m of the station's
            // point (Taipei Main's lines' platforms are some 150 m apart).
            let middle = platform.line[platform.line.count / 2]
            let at = scene.point(worldX: Double(station.location.x), worldY: Double(station.location.y), height: 0)
            let away = Map3DPoint(middle.x - at.x, 0, middle.z - at.z).length
            XCTAssertLessThan(away, 300, station.name)
            // Under the ground, and shallow enough to be seen through it
            // (decision 674: the Tamsui–Xinyi Line's are some 36 m down).
            let ground = try XCTUnwrap(scene.trackCover.ground(at: middle), station.name)
            XCTAssertTrue(ground.inTunnel, station.name)
            XCTAssertGreaterThan(ground.height - middle.y, 0, station.name)
            XCTAssertLessThanOrEqual(ground.height - middle.y, Map3DXRay.deepest, station.name)
            // Beside its track, clear of the train (decision 392's edge).
            XCTAssertGreaterThanOrEqual(abs(platform.offset) - platform.width / 2, Map3DScene.Builder.platformEdge - 0.01, station.name)
            XCTAssertGreaterThanOrEqual(platform.width, Map3DScene.Builder.narrowestPlatform, station.name)
            // Clear of every other track of its station at its level.
            for other in buried where other.platform.station == platform.station && other.points != source.points {
                let theirs = other.points.map { scene.point($0) + Map3DScene.Builder.lifted }
                let near = theirs[theirs.count / 2]
                guard abs(near.y - middle.y) <= Map3DXRay.sameLevel else { continue }
                let across = Map3DMesh.acrossDirections(platform.line)[platform.line.count / 2]
                let apart = (near - middle).dot(across)
                let gap = abs(apart - platform.offset) - platform.width / 2
                XCTAssertGreaterThanOrEqual(gap, Map3DScene.Builder.platformEdge - 0.01, "\(station.name): the platform over a track \(apart) m beside")
            }
            // An island only with a platform of its station at its own
            // level (not a line crossing under it).
            if platform.width != Map3DScene.Builder.platformWidth {
                XCTAssertTrue(platforms.contains { other in
                    other != platform && other.station == platform.station
                        && abs(other.line[other.line.count / 2].y - middle.y) <= Map3DXRay.sameLevel
                }, station.name)
            }
            report.append("\(station.name) \(Int(away)) m from the station, \(Int(ground.height - middle.y)) m down, "
                          + "\(platform.width == Map3DScene.Builder.platformWidth ? "side" : "island") \(platform.width) m")
        }
        // The x-ray draws them: more than the tunnels alone.
        var tunnels = Map3DMesh()
        Map3DXRay.addTunnels(scene.trackCover, to: &tunnels)
        XCTAssertGreaterThan(Map3DXRay(scene: scene, snapshot: snapshot).mesh.triangleCount, tunnels.triangleCount)
        print("Decision 674 underground platforms:\n" + report.joined(separator: "\n"))
    }
}
