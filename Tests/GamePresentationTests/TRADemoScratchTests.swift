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
        print("PLATFORMS", layout.platforms.map { Int($0.lowerBound / 64) }, "down33", Int(layout.plan.distances[33] / 64), Int(layout.plan.distances[34] / 64))
        for depot in layout.depots { print("DEPOT", depot.real.english, Int(depot.entry / 64), Int(depot.deadEnd / 64), depot.serving, depot.east.count) }
        var world = try TRADemo.make(in: .english, railways: railways)
        var overlaps = 0, against: [String] = [], late: [String: Int64] = [:], firstOverlaps: [String] = []
        for _ in 0..<(24 * 60 + 30) {
            try world.advance(ticks: 1)
            let minute = world.clock.now.minute
            if (19 * 60 + 50)...(20 * 60 + 4) ~= minute || (23 * 60 + 38)...(23 * 60 + 46) ~= minute {
                for t in world.trains where (minute < 1300 && t.name == "Local 1") || (minute >= 1300 && t.name == "Local 4") {
                    guard case .onEdge(let tr, let off)? = t.position else { continue }
                    let di = tracks.down.firstIndex(of: tr.edge)
                    let at = di.map { Int((layout.plan.distances[$0] + Double(off)) / 64) } ?? -1
                    let ex = String(describing: t.execution)
                    let stopped = world.stationsStoppedAt(by: t.id).compactMap { world.station(id: $0)?.name }
                    var kindOf = "?"
                    if tracks.down.contains(tr.edge) { kindOf = "down" }
                    if tracks.up.contains(tr.edge) { kindOf = "up" }
                    if tracks.sidings.contains(tr.edge) { kindOf = "siding" }
                    if tracks.crossovers.contains(tr.edge) { kindOf = "crossover" }
                    if tracks.ends.contains(tr.edge) { kindOf = "end" }
                    if tracks.downLoops.contains(tr.edge) { kindOf = "downLoop" }
                    if tracks.upLoops.contains(tr.edge) { kindOf = "upLoop" }
                    let ui = tracks.upInOrder.firstIndex(of: tr.edge).map { Int(layout.up.distances[$0] / 64) } ?? -1
                    print("TRACE \(kindOf) up@\(ui)", terminator: " ")
                    print("TRACE \(minute / 60):\(minute % 60) \(t.name) edge \(tr.edge) down#\(String(describing: di)) at m \(at) \(tr.direction) end \(String(describing: t.movement.end)) rem \(t.movement.remainingEdges.count) \(ex) stopped \(stopped)")
                }
            }
            if minute == 1_440 + 3 * 60 {
                print("NIGHT not in depot:", world.trains.filter { !world.standsInADepot($0) }.map(\.name))
            }
            if minute <= 1_440 + 3 * 60 {
                for o in HighSpeedDemoDayTests.overlaps(in: world) {
                    overlaps += 1
                    if firstOverlaps.count < 15 {
                        let names = [o.trains.0, o.trains.1].map { world.train(id: $0)?.name ?? "?" }
                        let station = world.network.platforms.first { $0.edge == o.edge }.flatMap { world.station(id: $0.station)?.name } ?? "-"
                        var kindOf = "?"
                        if tracks.down.contains(o.edge) { kindOf = "down \(tracks.down.firstIndex(of: o.edge)!)" }
                        if tracks.up.contains(o.edge) { kindOf = "up" }
                        if tracks.sidings.contains(o.edge) { kindOf = "siding" }
                        if tracks.crossovers.contains(o.edge) { kindOf = "crossover" }
                        if tracks.ends.contains(o.edge) { kindOf = "end" }
                        if tracks.downLoops.contains(o.edge) || tracks.upLoops.contains(o.edge) { kindOf = "loop" }
                        let execs = [o.trains.0, o.trains.1].map { String(describing: world.train(id: $0)?.execution) }
                        firstOverlaps.append("\(minute / 60 % 24):\(minute % 60) \(names) at \(station) \(kindOf) \(o.length / 64) m \(execs)")
                    }
                }
            }
            let probes: [Int64] = [630, 690, 825]
            if probes.contains(Int64(minute)) {
                for t in world.trains where (world.lateness(of: t.id) ?? 0) >= 600 {
                    guard case .onEdge(let tr, let off)? = t.position else { continue }
                    func kind(_ e: TrackEdgeID) -> String {
                        if tracks.between.contains(e) || tracks.down.contains(e) { return "down" }
                        if tracks.up.contains(e) { return "up" }
                        if tracks.downLoops.contains(e) { return "downLoop" }
                        if tracks.upLoops.contains(e) { return "upLoop" }
                        if tracks.ends.contains(e) { return "end" }
                        if tracks.sidings.contains(e) { return "siding" }
                        if tracks.crossovers.contains(e) { return "crossover" }
                        return "?"
                    }
                    var km: Double = -1
                    if let i = tracks.down.firstIndex(of: tr.edge) { km = layout.plan.distances[i] / 64_000 }
                    if let i = tracks.upInOrder.firstIndex(of: tr.edge) { km = layout.up.distances[i] / 64_000 }
                    let exec: String = String(describing: t.execution)
                    let ahead: [String] = t.movement.remainingEdges.prefix(3).map { kind($0) }
                    let where_ = kind(tr.edge); let rem = t.movement.remainingEdges.count; let endText = String(describing: t.movement.end)
                    print("STUCK \(minute) \(t.name) \(where_) \(tr.edge) \(tr.direction) off \(off) km \(km) exec \(exec) rem \(rem) end \(endText) ahead \(ahead)")
                }
            }
            if minute % 60 == 0, minute <= 1_440 {
                let lateNow = world.trains.compactMap { t -> String? in
                    guard let l = world.lateness(of: t.id), l >= 600 else { return nil }
                    let at = world.stationsStoppedAt(by: t.id).compactMap { world.station(id: $0)?.name }.first ?? "between"
                    return "\(t.name)(\(l / 60)m@\(at))"
                }
                if minute % 120 == 0 { for d in layout.depots { _ = d } }
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
