import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 625: the eleven exterior studies of #1904 stood on the 3D map
/// where OpenStreetMap has the real stations, in the demo's real lines
/// laid round each (decision 351), clear of the track and the platforms.
@MainActor
final class Map3DStationExteriorsTests: XCTestCase {
    typealias Study = Map3DStationExteriorBatch1.Station

    /// The real station each study's demo is laid round: its system and
    /// name in the bundled data.
    static let laidAt: [Study: (system: String, name: String)] = [
        .taichungTRA: ("tra_sched", "臺中"), .hsinchuTRA: ("tra_sched", "新竹"), .hualienTRA: ("tra_sched", "花蓮"),
        .taitungTRA: ("tra_sched", "臺東"), .banqiaoTRA: ("tra_sched", "板橋"), .nangangTRA: ("tra_sched", "南港"),
        .taoyuanHSR: ("thsr_sched", "桃園"), .hsinchuHSR: ("thsr_sched", "新竹"), .taichungHSR: ("thsr_sched", "台中"),
        .tainanHSR: ("thsr_sched", "台南"), .zuoyingHSR: ("thsr_sched", "左營"),
    ]

    /// The demo's real lines laid in the view 1.5 km each way round
    /// `study`'s station, and the 3D scene 900 m each way round its origin.
    static func scene(round study: Study) async throws -> (scene: Map3DScene, world: GameWorld) {
        let at = try XCTUnwrap(laidAt[study])
        if at.system == "thsr_sched" {
            let world = try HighSpeedDemoTests.opened.get()
            return (try scene(round: study, in: world, heights: HighSpeedDemoTests.heights, railways: HighSpeedDemoTests.railways()), world)
        }
        let (session, view) = try DemoRealLinesTrackReportTests.game(at: at.name, in: at.system, half: 4_000)
        _ = await session.layDemoRealLines(in: view)
        return (try scene(round: study, in: session.world, heights: session.heights, railways: session.railways), session.world)
    }

    /// The 3D scene of `world` 900 m each way round `study`'s origin.
    static func scene(round study: Study, in world: GameWorld, heights: HeightGrid?, railways: RealRailways?) throws -> Map3DScene {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let origin = Map3DStationExteriorBatch1.origin(of: study)
        let middle = frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
        let reach = 900 * Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: middle.x - reach, minY: middle.y - reach, maxX: middle.x + reach, maxY: middle.y + reach)
        return Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: nil, frame: (region, middle.x.rounded(), middle.y.rounded()),
                          baseMap: nil, cityTiles: [], heights: heights, lineBands: nil, railways: railways, temples: nil)
    }

    func testReportWhatStands() async throws {
        guard ProcessInfo.processInfo.environment["STATION_EXTERIOR_REPORT"] == "1" else { throw XCTSkip("report") }
        for study in Study.allCases {
            let started = Date()
            let (scene, world) = try await Self.scene(round: study)
            let stations = world.stations.count
            let stood = scene.stationExteriors.map { "\($0.station.rawValue) near \($0.kept.near) far \($0.kept.far) tris \($0.near.triangleCount)/\($0.far.triangleCount)" }
            print("EXTERIOR \(study.rawValue): stations \(stations) stood \(stood) in \(Int(Date().timeIntervalSince(started))) s")
            for s in Study.allCases {
                let full = (Map3DStationExteriorBatch1.mesh(for: s, detail: .near).triangleCount, Map3DStationExteriorBatch1.mesh(for: s, detail: .far).triangleCount)
                if s == study { print("  study full \(full)") }
            }
        }
    }
}
