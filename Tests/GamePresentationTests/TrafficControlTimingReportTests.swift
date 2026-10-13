import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// How long traffic control takes on the high-speed demo
/// (`docs/research/NEXT_PRIORITIES_2026-10-12.md` §2 items 6 and 7), and how
/// punctual its sets are on the real day's timetable (decision 197): printed,
/// and only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     TRAFFIC_TIMING_REPORT=1 swift test -c release --skip-build --filter TrafficControlTimingReportTests
///
/// `TRAFFIC_TIMING_HOURS` (default 20) is how many game hours from 05:00
/// to run, and `TRAFFIC_TIMING_CAP` (default 1200) the seconds after which
/// an hour stops the report. Each hour prints the seconds of computing it
/// took, the sets running and a digest of the saved world, so two builds can
/// be shown to run the same game; the end, the runs sent out, those dropped,
/// how late the sets reached the end of their runs and how long the real
/// trains that call at all of their line's stations took end to end.
final class TrafficControlTimingReportTests: XCTestCase {
    private func say(_ text: String) {
        FileHandle.standardError.write(Data(("TIMING " + text + "\n").utf8))
    }

    private var hours: Int { Int(ProcessInfo.processInfo.environment["TRAFFIC_TIMING_HOURS"] ?? "") ?? 20 }
    private var cap: Double { Double(ProcessInfo.processInfo.environment["TRAFFIC_TIMING_CAP"] ?? "") ?? 1_200 }

    /// FNV-1a of the saved world, keys sorted.
    private static func digest(_ world: GameWorld) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in try encoder.encode(SavedGame(world: world)) {
            hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// Where each set is and what it waits for.
    private func dump(_ world: GameWorld, layout: HighSpeedDemo.Layout, built: HighSpeedDemo.Built, tracks: HighSpeedDemoTests.Tracks) {
        let m = Double(WorldCoordinate.unitsPerMetre)
        var kinds: [TrackEdgeID: String] = [:]
        for (i, e) in built.down.edges.enumerated() { kinds[e] = "down@\(Int(layout.plan.distances[i] / m / 100) )hm" }
        for (i, e) in built.up.edges.enumerated() { kinds[e] = "up@\(Int(built.up.plan.distances[i] / m / 100))hm" }
        for (n, loop) in (built.loops + built.outerLoops).enumerated() {
            for e in loop.down.edges { kinds[e] = "downloop\(n)" }
            for e in loop.up.edges { kinds[e] = "uploop\(n)" }
        }
        for e in built.crossovers { kinds[e] = "crossover" }
        for (n, yard) in built.yards.enumerated() { for e in yard.edges { kinds[e] = "yard\(n)" } }
        let deadlocked = Set(world.deadlockedTrains())
        let names = world.stations.map(\.name)
        say("-- \(world.clock.now.minute / 60 % 24):\(String(format: "%02d", world.clock.now.minute % 60)) --")
        for train in world.trains {
            guard let line = world.lines.first(where: { $0.trains.contains(train.id) }) else { continue }
            var place = "off"
            if case .onEdge(let traversal, let offset)? = train.position {
                place = "\(kinds[traversal.edge] ?? "?")\(traversal.direction == .forward ? "S" : "N")+\(offset / 64)m" + (tracks.isAgainst(traversal) ? " AGAINST" : "")
            }
            let state: String
            switch train.execution {
            case .waitingAtStop(let stop, _)?: state = "at \(names[world.stations.firstIndex { $0.id == train.timetable[stop].station }!])(\(stop))"
            case .travellingToStop(let stop, _)?: state = "to \(names[world.stations.firstIndex { $0.id == train.timetable[stop].station }!])(\(stop))"
            case nil: state = "idle at \(world.stationsStoppedAt(by: train.id).compactMap { id in world.stations.first { $0.id == id }?.name }.joined(separator: "/"))"
            }
            let holder = world.trainHoldingRoute(of: train.id).flatMap { world.train(id: $0)?.name } ?? "-"
            func describe(_ resources: [TrackResource]) -> String {
                var edges: [String] = [], nodes = 0
                for resource in resources {
                    switch resource {
                    case .node: nodes += 1
                    case .span(let span):
                        let name = "\(kinds[span.edge] ?? "?")#\(span.edge.networkNumber ?? 0)"
                        if edges.last != name { edges.append(name) }
                    }
                }
                return edges.joined(separator: ",") + " +\(nodes)n"
            }
            var line2 = "\(train.name) [\(line.name.suffix(10))] \(place) \(state) holder \(holder)\(deadlocked.contains(train.id) ? " DEADLOCK" : "")"
            if ProcessInfo.processInfo.environment["TRAFFIC_TIMING_HELD"] != nil, holder != "-" || train.execution != nil {
                line2 += "\n    held \(describe(world.heldResources(of: train.id)))\n    contested \(describe(world.contestedResources(of: train.id)))"
            }
            say(line2)
        }
    }

    /// The demo as the game builds it, at midnight of its first day, run
    /// minute by minute from there.
    func testTheDemoOnTheRealDay() throws {
        guard ProcessInfo.processInfo.environment["TRAFFIC_TIMING_REPORT"] != nil else { throw XCTSkip("Set TRAFFIC_TIMING_REPORT=1.") }
        let layout = try HighSpeedDemo.Layout(railways: HighSpeedDemoTests.railways())
        var world = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
        let built = try layout.build(in: &world, language: .english)
        let tracks = HighSpeedDemoTests.Tracks(layout: layout, built: built)
        world.setSpeed(.normal)
        try world.advance(ticks: 5 * 60)
        say("== the demo on the real day: \(world.trains.count) sets, \(world.lines.map { $0.runs.count }) runs, traffic control \(world.isTrafficControlEnabled) ==")
        say("hour | seconds | running (most) | waiting for a route | deadlocked | against its track | digest")

        // Each run sent out: the set, and the second it left its first stop
        // and reached its last.
        struct Sent {
            let line: Int
            let run: Int
            let day: Int64
            var left: Int64?
            var reached: Int64?
        }
        var sent: [TrainID: Sent] = [:]
        var done: [Sent] = []
        var against = 0
        var total = 0.0
        // `TRAFFIC_TIMING_DUMP=06:00,07:30`: every set's state at those minutes.
        let dumps = Set((ProcessInfo.processInfo.environment["TRAFFIC_TIMING_DUMP"] ?? "").split(separator: ",").compactMap { time -> Int64? in
            let parts = time.split(separator: ":").compactMap { Int64($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
        })
        for _ in 0..<hours {
            var seconds = 0.0, most = 0, waiting = 0, deadlocked = 0
            for _ in 0..<60 {
                let before = world.lines.map(\.runDays)
                let began = Date()
                try world.advance(ticks: 1)
                seconds += Date().timeIntervalSince(began)
                // Runs sent out this minute, matched to the set that took
                // each: one with a service now that had none.
                for (index, line) in world.lines.enumerated() {
                    for (run, runDay) in line.runDays.enumerated() where before[index][run] != runDay {
                        guard let runDay else { continue }
                        let first = line.stops[line.runs[run].from]
                        guard let train = line.trains.first(where: { id in
                            sent[id] == nil && world.train(id: id)?.timetable.first?.station == first && world.train(id: id)?.execution != nil
                        }) else { continue }
                        sent[train] = Sent(line: index, run: run, day: runDay)
                    }
                }
                for (id, entry) in sent {
                    guard let train = world.train(id: id) else { continue }
                    var entry = entry
                    if entry.left == nil, let execution = train.execution, execution.stop > 0 || { if case .travellingToStop = execution { true } else { false } }() {
                        entry.left = world.clock.now.seconds
                    }
                    let last = world.lines[entry.line].runs[entry.run].calls.count - 1
                    if train.execution == nil || (train.execution.map { if case .waitingAtStop(let stop, _) = $0 { stop == last } else { false } } ?? false) {
                        entry.reached = world.clock.now.seconds
                        done.append(entry)
                        sent[id] = nil
                    } else {
                        sent[id] = entry
                    }
                }
                if dumps.contains(world.clock.now.minute % 1_440) { dump(world, layout: layout, built: built, tracks: tracks) }
                let running = world.trains.filter { $0.execution != nil }
                most = max(most, running.count)
                for train in running {
                    if case .onEdge(let traversal, _)? = train.position, tracks.isAgainst(traversal) { against += 1 }
                }
            }
            waiting = world.trains.count { world.trainHoldingRoute(of: $0.id) != nil }
            deadlocked = world.deadlockedTrains().count
            total += seconds
            let clock = world.clock.now.minute % 1_440 / 60
            say(String(format: "%02d–%02d | %.1f | %d | %d | %d | %d | %@", (clock + 23) % 24, clock, seconds, most, waiting, deadlocked, against, try Self.digest(world)))
            if seconds > cap {
                say("stopped: the hour took more than \(Int(cap)) s")
                break
            }
        }
        say(String(format: "total %.1f s", total))

        // The runs: sent out, dropped, and how late they ended.
        let now = world.clock.now.seconds
        for (index, line) in world.lines.enumerated() {
            let planned = layout.timetable.lines[index]
            let due = line.runs.indices.filter { line.runs[$0].start(onDay: 0) + LineRun.latestDispatch < now }
            let dropped = due.filter { (line.runDays[$0] ?? -1) < 0 }
            let ended = done.filter { $0.line == index }
            let late = ended.map { entry -> Int64 in
                let run = line.runs[entry.run]
                return (entry.reached ?? 0) - (entry.day * GameTime.secondsPerDay + run.times[run.times.count - 1].arrival)
            }.sorted()
            func minutes(_ seconds: Int64) -> String { String(format: "%.1f", Double(seconds) / 60) }
            let onTime = late.count { $0 < 60 }, within5 = late.count { $0 < 300 }
            say("\(planned.english): \(due.count) due, \(dropped.count) dropped, \(ended.count) ended; late at the end: median \(late.isEmpty ? "–" : minutes(late[late.count / 2])) min, worst \(late.last.map(minutes) ?? "–") min, under 1 min \(onTime), under 5 min \(within5)")
            // The real trains that call at all the line's stops, end to end.
            let whole = ended.filter { entry in
                let run = line.runs[entry.run]
                return Set([run.from, run.to]) == [0, line.stops.count - 1] && entry.left != nil
            }
            let times = whole.map { ($0.reached ?? 0) - ($0.left ?? 0) }.sorted()
            let real = whole.map { entry -> Int64 in
                let run = line.runs[entry.run]
                return run.times[run.times.count - 1].arrival - run.times[0].departure
            }.sorted()
            if !times.isEmpty {
                say("  end to end, \(times.count) runs: game median \(minutes(times[times.count / 2])) min (\(minutes(times.first!))–\(minutes(times.last!))), timetable median \(minutes(real[real.count / 2])) min")
            }
        }
    }
}
