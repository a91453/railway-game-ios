import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

final class TRADemoScratch2Tests: XCTestCase {
    func testEnds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)")) }
        let railways = try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"),
            operations: RealRailwayOperations(systems: [:], timetables: [:], schedules: ["tra-yilan": file("tra-yilan-schedule.json")])
        )
        let base = TRADemo.spec
        for (south, tol, edge) in [(3, 5.0, 2000.0), (4, 5.0, 2000.0), (5, 5.0, 2000.0), (6, 5.0, 2000.0)] {
            let spec = RealLineDemoSpec(path: base.path, stationNames: base.stationNames, stationIDPrefix: base.stationIDPrefix, schedule: base.schedule, kinds: base.kinds,
                endTrackSides: (north: (east: south, west: 1), south: (east: south, west: 1)), islandStations: base.islandStations, depots: base.depots, tolerance: tol * 64, longestEdge: edge * 64, landAt: base.landAt, opensAt: base.opensAt)
            let layout = try HighSpeedDemo.Layout(railways: railways, spec: spec)
            var world = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
            do { _ = try layout.build(in: &world, language: .english); print("ENDS south", south, tol, edge, "ok") } catch { print("ENDS south", south, tol, edge, error) }
        }
    }
}
