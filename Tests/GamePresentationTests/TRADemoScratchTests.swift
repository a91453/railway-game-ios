import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

final class TRADemoScratchTests: XCTestCase {
    func testDay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)")) }
        let railways = try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"),
            operations: RealRailwayOperations(systems: [:], timetables: [:], schedules: ["tra-yilan": file("tra-yilan-schedule.json")])
        )
        let layout = try HighSpeedDemo.Layout(railways: railways, spec: TRADemo.spec)
        var built = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
        let tracks = HighSpeedDemoTests.Tracks(layout: layout, built: try layout.build(in: &built, language: .english))
        var world = try TRADemo.make(in: .english, railways: railways)
        var overlaps = 0, against: [String] = [], late: [String: Int64] = [:], firstOverlaps: [String] = []
        for _ in 0..<(24 * 60 + 30) {
            try world.advance(ticks: 1)
            let minute = world.clock.now.minute
            if minute <= 1_440 + 3 * 60 {
                for o in HighSpeedDemoDayTests.overlaps(in: world) {
                    overlaps += 1
                    if firstOverlaps.count < 15 {
                        let names = [o.trains.0, o.trains.1].map { world.train(id: $0)?.name ?? "?" }
                        let station = world.network.platforms.first { $0.edge == o.edge }.flatMap { world.station(id: $0.station)?.name } ?? "-"
                        firstOverlaps.append("\(minute / 60 % 24):\(minute % 60) \(names) at \(station) \(o.length / 64) m")
                    }
                }
            }
            if minute % 30 == 0, minute <= 1_440 {
                let lateNow = world.trains.compactMap { t -> String? in
                    guard let l = world.lateness(of: t.id), l >= 600 else { return nil }
                    let at = world.stationsStoppedAt(by: t.id).compactMap { world.station(id: $0)?.name }.first ?? "between"
                    return "\(t.name)(\(l / 60)m@\(at))"
                }
                print("HOUR \(minute / 60):\(minute % 60) late>10:", lateNow.count, lateNow.prefix(8))
            }
            for train in world.trains where train.execution != nil {
                late[train.name] = max(late[train.name] ?? 0, world.lateness(of: train.id) ?? 0)
                guard case .onEdge(let traversal, _)? = train.position else { continue }
                if tracks.isAgainst(traversal), against.count < 10 { against.append("\(train.name) at \(minute / 60 % 24):\(minute % 60)") }
            }
        }
        print("overlaps", overlaps, firstOverlaps)
        print("against", against)
        print("late (min)", late.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) \($0.value / 60)" })
        let now = world.clock.now.seconds - GameTime.secondsPerDay
        var missed: [String] = []
        for line in world.lines {
            for (index, run) in line.runs.enumerated() {
                let day: Int64 = run.times[0].departure + LineRun.latestDispatch < now ? 1 : 0
                if (line.runDays[index] ?? -1) < day { missed.append("\(line.name) \(run.times[0].departure / 60)") }
            }
        }
        print("missed runs", missed.count, missed.prefix(10))
        var night: [String] = []
        print("in depots now", world.trains.filter { world.standsInADepot($0) }.count, "of", world.trains.count, night)
        night = []
    }
}
