import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

final class TRADemoScratchTests: XCTestCase {
    func testPrint() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)")) }
        let railways = try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"),
            operations: RealRailwayOperations(systems: [:], timetables: [:], schedules: ["tra-yilan": file("tra-yilan-schedule.json")])
        )
        let base = TRADemo.spec
        for south in [2, 3, 4, 5] {
            let spec = RealLineDemoSpec(path: base.path, stationNames: base.stationNames, stationIDPrefix: base.stationIDPrefix, schedule: base.schedule, kinds: base.kinds,
                endPlatformTracks: (north: 4, south: south), islandStations: base.islandStations, depots: base.depots, tolerance: base.tolerance, longestEdge: base.longestEdge, landAt: base.landAt, opensAt: base.opensAt)
            let layout = try HighSpeedDemo.Layout(railways: railways, spec: spec)
            var world = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
            do { _ = try layout.build(in: &world, language: .english); print("south", south, "ok") } catch { print("south", south, error) }
        }
        let layout = try HighSpeedDemo.Layout(railways: railways, spec: TRADemo.spec)
        print("path km", layout.plan.path.length / 64_000, "platforms", layout.platforms.map { Int($0.lowerBound / 64) })
        for line in layout.timetable.lines {
            print(line.chinese, "runs", line.runs.count, "positioning", line.positioning, "sets", line.sets, "overnight", line.overnight.map { $0.station })
        }
        for depot in layout.depots { print(depot.real.chinese, "entry", Int(depot.entry / 64), "end", Int(depot.deadEnd / 64), "serving", depot.serving, "sidings", depot.east.count, depot.west.count) }
        print("loops", layout.loops.keys.sorted(), "outer", layout.outerLoops.keys.sorted(), "crossovers", layout.crossovers.keys.sorted())
        print("down edges", layout.plan.distances.count - 1, "edge130 at m", layout.plan.distances.count > 130 ? Int(layout.plan.distances[129] / 64) : -1, layout.plan.distances.count > 130 ? Int(layout.plan.distances[130] / 64) : -1)
        print("junctions", Int(layout.junctions.north / 64), Int(layout.junctions.south / 64), "turnback", layout.turnbackReach.mapValues { (Int($0.lowerBound / 64), Int($0.upperBound / 64)) })
        var world = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
        _ = try layout.build(in: &world, language: .traditionalChinese)
        print("trains", world.trains.count, "lines", world.lines.count, "stations", world.stations.count)
    }
}
