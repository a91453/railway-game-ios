@testable import GamePresentation
import GameCore
import XCTest

/// Decision 929: the high-speed stations of Miaoli, Changhua, Yunlin and
/// Chiayi are the studio's own models, stood as decision 625's studies.
final class Map3DHSRStudioStationTests: XCTestCase {
    typealias Station = Map3DHSRStudioStation

    /// Each model decodes at the studio's triangle counts, on the ground,
    /// in its palette's colours, its hall's lamp band glowing.
    func testTheModelsDecode() throws {
        let counts: [Station: (near: Int, far: Int)] = [
            .miaoli: (4544, 880), .changhua: (4620, 1168), .yunlin: (2656, 520), .chiayi: (3166, 666),
        ]
        for station in Station.allCases {
            let want = try XCTUnwrap(counts[station])
            let near = try XCTUnwrap(station.model()), far = try XCTUnwrap(station.model(far: true))
            XCTAssertEqual(near.triangleCount, want.near, "\(station)")
            XCTAssertEqual(far.triangleCount, want.far, "\(station)")
            for model in [near, far] {
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, "\(station)")
                XCTAssertTrue(model.vertices.allSatisfy { station.meshPalette.contains($0.color) }, "\(station)")
                XCTAssertTrue(model.vertices.allSatisfy { ($0.layer == Map3DVertex.glowing) == ($0.color == Map3DPalette.tunnelLamp) }, "\(station)")
            }
            XCTAssertTrue(near.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(station)'s lamp band")
        }
        // The colours two stations give one name.
        XCTAssertTrue(try XCTUnwrap(Station.changhua.model()).vertices.contains { $0.color == Map3DPalette.trimBlue })
        XCTAssertTrue(try XCTUnwrap(Station.chiayi.model()).vertices.contains { $0.color == Map3DPalette.gymGreen })
        XCTAssertTrue(try XCTUnwrap(Station.chiayi.model()).vertices.contains { $0.color == Map3DPalette.bridge }, "its skylight")
        XCTAssertTrue(try XCTUnwrap(Station.miaoli.model()).vertices.contains { $0.color == Map3DPalette.tileWhite }, "its white columns")
    }

    /// The model's own gap for the viaduct: nothing within 7.5 m of its
    /// middle from the deck (10 m) to 6.5 m over it; and its rectangles
    /// hold all of it.
    func testEachLeavesItsViaductClear() throws {
        for station in Station.allCases {
            let model = try XCTUnwrap(station.model())
            let inside = model.vertices.filter { abs($0.y - station.viaduct) < 7.4 && $0.z > 10.05 && $0.z < 16.45 }
            XCTAssertEqual(inside.count, 0, "\(station)")
            let rectangles = station.rectangles
            XCTAssertEqual(rectangles.map(\.x0).min()!, model.minimum.x, accuracy: 0.5, "\(station)")
            XCTAssertEqual(rectangles.map(\.x1).max()!, model.maximum.x, accuracy: 0.5, "\(station)")
            XCTAssertLessThanOrEqual(rectangles.map(\.y0).min()!, model.minimum.y + 10, "\(station): but its roof's overhang")
            XCTAssertEqual(rectangles.map(\.y1).max()!, model.maximum.y, accuracy: 3, "\(station)")
        }
    }

    /// Each is a study of its own, at its catalog station: the station
    /// lies on the model's viaduct, within its outlines.
    func testEachIsAStudyAtItsStation() throws {
        XCTAssertEqual(Map3DExteriorStudy.allCases.filter { if case .studio = $0 { true } else { false } }.count, 4)
        XCTAssertEqual(Set(Map3DExteriorStudy.allCases.map(\.rawValue)).count, Map3DExteriorStudy.allCases.count)
        for station in Station.allCases {
            let study = Map3DExteriorStudy.studio(station)
            XCTAssertEqual(study.rawValue, "studio-" + station.rawValue)
            let catalog = try XCTUnwrap(Map3DStationKit.station(id: station.stationID))
            XCTAssertEqual(catalog.profile, .highSpeed)
            // Metres east and north of the origin, then in the model's own.
            let origin = station.origin
            let north = Float((catalog.latitude - origin.latitude) * 110_574)
            let east = Float((catalog.longitude - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180))
            let angle = station.bearing * .pi / 180
            let x = east * sinf(angle) + north * cosf(angle), y = -east * cosf(angle) + north * sinf(angle)
            XCTAssertEqual(y, station.viaduct, accuracy: 6, "\(station): the station on its viaduct")
            XCTAssertLessThan(abs(x), 60, "\(station): by its hall")
            // The study's mesh is the model turned, mirrored for the scene.
            let mesh = study.mesh(detail: .near), scene = study.sceneMesh(detail: .near)
            XCTAssertEqual(mesh.triangleCount, try XCTUnwrap(station.model()).triangleCount)
            XCTAssertEqual(scene.triangleCount, mesh.triangleCount)
            let outline = study.outlines.flatMap { $0 }
            let bounds = try XCTUnwrap(mesh.bounds)
            XCTAssertEqual(outline.map(\.0).min()!, bounds.min.x, accuracy: 12, "\(station)")
            XCTAssertEqual(outline.map(\.1).max()!, bounds.max.z, accuracy: 12, "\(station)")
            // Facing out: most of its roofs' normals up, in the scene too.
            let up = scene.vertices.filter { $0.ny > 0.9 }.count, down = scene.vertices.filter { $0.ny < -0.9 }.count
            XCTAssertGreaterThan(up, down, "\(station)")
            var area: Float = 0
            for t in 0..<scene.triangleCount {
                let p = (0..<3).map { scene.vertices[Int(scene.indices[t * 3 + $0])] }
                let normal = (p[1].position - p[0].position).cross(p[2].position - p[0].position)
                area += normal.dot(Map3DPoint(p[0].nx, p[0].ny, p[0].nz))
            }
            XCTAssertGreaterThan(area, 0, "\(station): each triangle turned as its normal")
        }
    }

    // MARK: - With the real data

    /// What the scene builds 900 m round `station` in the high-speed demo.
    static func built(round station: Station) throws -> (builder: Map3DScene.Builder, exteriors: [Map3DExteriorStudy: Set<Map3DScene.ChunkKey>]) {
        let world = try HighSpeedDemoTests.opened.get(), railways = try HighSpeedDemoTests.railways()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let middle = frame.worldPosition(latitude: station.origin.latitude, longitude: station.origin.longitude)
        let reach = 900 * Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: middle.x - reach, minY: middle.y - reach, maxX: middle.x + reach, maxY: middle.y + reach)
        var builder = Map3DScene.Builder(originX: middle.x.rounded(), originY: middle.y.rounded(), region: region, world: world,
                                         heights: HighSpeedDemoTests.heights)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround(water: true)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let realTrains = Map3DScene.realTrains(world: world, railways: railways, snapshot: snapshot, builder: &builder)
        builder.realTrackLines = realTrains?.shownLanes ?? []
        builder.addViaducts()
        let exteriors = builder.addStationExteriors(snapshot, frame: frame)
        _ = builder.addStations(snapshot, frame: frame, shops: false)
        return (builder, exteriors)
    }

    /// In the high-speed demo each stands once, most of it left, clear of
    /// the trains and the platforms, and its station draws no vaulted box
    /// of the kit's beside it.
    @MainActor func testEachStandsInTheHighSpeedDemo() throws {
        for station in Station.allCases {
            let built = try Self.built(round: station)
            let stood = built.builder.stationExteriors.filter { $0.station == .studio(station) }
            XCTAssertEqual(stood.count, 1, "\(station) stands once")
            guard let exterior = stood.first else { continue }
            print("HSR studio \(station): kept near \(exterior.kept.near) far \(exterior.kept.far),",
                  "triangles near \(exterior.near.triangleCount) far \(exterior.far.triangleCount)")
            XCTAssertNotNil(built.exteriors[.studio(station)])
            XCTAssertGreaterThanOrEqual(exterior.kept.near, Map3DScene.Builder.exteriorLeast, "\(station)")
            XCTAssertLessThanOrEqual(exterior.near.triangleCount, 12_000, "\(station) near")
            XCTAssertLessThanOrEqual(exterior.far.triangleCount, 4_000, "\(station) far")
            XCTAssertEqual(Map3DStationExteriorsTests.inTheGauge(exterior.near, built.builder, ground: exterior.origin.y), 0, "\(station) near")
            XCTAssertEqual(Map3DStationExteriorsTests.inTheGauge(exterior.far, built.builder, ground: exterior.origin.y), 0, "\(station) far")
            XCTAssertTrue(exterior.near.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(station)'s lamp band")
            XCTAssertEqual(built.builder.houseTriangleCount, 0, "\(station): no building of the kit's")
        }
    }
}
