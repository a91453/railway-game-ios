import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// How long traffic control takes on the high-speed demo's long legs
/// (`docs/research/NEXT_PRIORITIES_2026-10-12.md` §2 item 6): the seconds
/// of computing each game hour takes with traffic control on, printed, and
/// only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     TRAFFIC_TIMING_REPORT=1 swift test -c release --skip-build --filter TrafficControlTimingReportTests
///
/// `TRAFFIC_TIMING_HOURS` (default 18) is how many game hours from 06:00
/// to run, and `TRAFFIC_TIMING_CAP` (default 1200) the seconds after which
/// an hour stops the scenario. Each hour also prints a digest of the saved
/// world, so two builds can be shown to run the same game.
///
/// Two scenarios, with sets that wait off the track until they are wanted
/// (the game has no depot yet; ordinary commands stand in for one):
///
/// - The demo's own services, at their fixed headways with their 24 sets
///   (the way #436 measured): a set is put at Nangang's platform when its
///   service is due to send one out and the platform is free, and taken off
///   once it has stood there idle for three minutes.
/// - The real day: one line of the twelve stations running the 169 trains
///   of the bundled `thsr-schedule.json` as runs (decision 133), each
///   stopping at every station between its ends (a station it passes at
///   the times between those of its calls either side), southbound at the
///   down track's main platforms and northbound at the up track's, the way
///   the measurement in #231 did. A set is put at a run's first station
///   five minutes before the run sends one out when none stands there, and
///   taken off when no run leaves its station within half an hour.
final class TrafficControlTimingReportTests: XCTestCase {
    private func say(_ text: String) {
        FileHandle.standardError.write(Data(("TIMING " + text + "\n").utf8))
    }

    private var hours: Int { Int(ProcessInfo.processInfo.environment["TRAFFIC_TIMING_HOURS"] ?? "") ?? 18 }
    private var cap: Double { Double(ProcessInfo.processInfo.environment["TRAFFIC_TIMING_CAP"] ?? "") ?? 1_200 }

    private func requireReport() throws {
        guard ProcessInfo.processInfo.environment["TRAFFIC_TIMING_REPORT"] != nil else { throw XCTSkip("Set TRAFFIC_TIMING_REPORT=1.") }
    }

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

    /// The demo built at midnight of its first day, with traffic control
    /// off and every set off the track.
    /// `extra` is money on top, for more sets.
    private static func builtDemo(extra: Int64 = 0) throws -> (world: GameWorld, stations: [StationID], down: Set<TrackEdgeID>, up: Set<TrackEdgeID>) {
        let layout = try HighSpeedDemo.Layout(railways: HighSpeedDemoTests.railways())
        var world = HighSpeedDemo.newWorld(paying: Money(layout.cost(at: ConstructionCosts.newGame).amount + extra), eventSeed: 1)
        let built = try layout.build(in: &world, language: .traditionalChinese)
        for train in world.trains where train.position != nil {
            try world.unplaceTrain(train.id)
        }
        let stations = try XCTUnwrap(world.lines.first).stops
        return (world, stations, Set(built.down.edges), Set(built.up.edges))
    }

    /// Puts `train` at `platform`, facing the way `forward` says, standing
    /// at its far end; `false` when the game refuses (track held).
    private static func place(_ train: TrainID, at platform: TrackPlatform, forward: Bool, in world: inout GameWorld) -> Bool {
        guard let length = world.trackEdge(platform.edge)?.length else { return false }
        let offset = forward ? platform.end : length - platform.start
        let position = TrainPosition.onEdge(TrackTraversal(edge: platform.edge, direction: forward ? .forward : .backward), offset: offset)
        var placed = world
        do throws(GameError) {
            try placed.placeTrain(train, at: position)
            try placed.setTrainContinuation(train, along: [], stoppingAt: offset)
            try placed.useTrainPerformanceForMovement(train)
        } catch {
            return false
        }
        world = placed
        return true
    }

    /// Runs `world` hour by hour from 06:00, `depot` before every minute,
    /// printing each hour's seconds of computing in `advance(ticks:)` (the
    /// depot's commands are left out).
    private func run(_ name: String, _ world: inout GameWorld, depot: (inout GameWorld) -> Void) throws {
        world.setSpeed(.normal)
        try world.setTrafficControl(true)
        let start = 6 * 60 - 10
        try world.advance(ticks: Int(Int64(start) - world.clock.now.minute))
        say("== \(name): traffic control on, from 05:50; \(world.trains.count) sets ==")
        say("hour | seconds | running (most/mean) | digest")
        var total = 0.0
        for hour in 0..<hours {
            var seconds = 0.0
            var most = 0, sum = 0
            let minutes = hour == 0 ? 70 : 60
            for _ in 0..<minutes {
                depot(&world)
                let began = Date()
                try world.advance(ticks: 1)
                seconds += Date().timeIntervalSince(began)
                let running = world.trains.count { $0.execution != nil }
                most = max(most, running)
                sum += running
            }
            total += seconds
            let clock = world.clock.now.minute % 1_440 / 60
            say(String(format: "%02d–%02d | %.1f | %d / %.1f | %@", (clock + 23) % 24, clock, seconds, most, Double(sum) / Double(minutes), try Self.digest(world)))
            if seconds > cap {
                say("stopped: the hour took more than \(Int(cap)) s")
                break
            }
        }
        say(String(format: "%@ total %.1f s", name, total))
    }

    func testTheDemoAtItsHeadwaysWithTrafficControl() throws {
        try requireReport()
        var (world, stations, _, _) = try Self.builtDemo()
        let line = try XCTUnwrap(world.lines.first)
        let platform = try XCTUnwrap(world.trackPlatforms(of: stations[0]).first)
        var idleChecks: [TrainID: Int] = [:]
        try run("demo at its headways", &world) { world in
            var memo = GameWorld.DispatchMemo()
            for train in world.trains where train.position != nil && train.execution == nil {
                guard world.stationsStoppedAt(by: train.id).contains(stations[0]) else { continue }
                idleChecks[train.id, default: 0] += 1
                if idleChecks[train.id]! > 3 {
                    try? world.unplaceTrain(train.id)
                    idleChecks[train.id] = nil
                }
            }
            guard let current = world.line(id: line.id) else { return }
            for pattern in [nil] + current.patterns.indices.map(Optional.some) {
                let ids = pattern.map { current.patterns[$0].trains } ?? current.trains
                guard let waiting = ids.first(where: { world.train(id: $0)?.position == nil }),
                      let stream = current.dispatchStream(of: waiting),
                      world.isDispatchDue(current, stream, at: world.clock.now, deadhead: false, memo: &memo)
                else { continue }
                if Self.place(waiting, at: platform, forward: true, in: &world) {
                    idleChecks[waiting] = 0
                    return
                }
            }
        }
    }

    /// The real day's trains as runs of a line calling at all twelve
    /// stations, north to south.
    private static func realRuns(names: [String]) throws -> [LineRun] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RailwayGameApp/Resources/RealRailways/thsr-schedule.json")
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let trains = try XCTUnwrap(data["trains"] as? [[String: Any]])
        return try trains.map { train in
            let stops = try XCTUnwrap(train["stops"] as? [[String: Any]])
                .filter { ($0["stop"] as? Bool) ?? true }
                .sorted { (($0["order"] as? Int) ?? 0) < (($1["order"] as? Int) ?? 0) }
            let calls = try stops.map { stop in
                (index: try XCTUnwrap(names.firstIndex(of: try XCTUnwrap(stop["name"] as? String))),
                 arrival: try XCTUnwrap(stop["arrSec"] as? NSNumber).int64Value, departure: try XCTUnwrap(stop["depSec"] as? NSNumber).int64Value)
            }
            let from = calls[0].index, to = calls[calls.count - 1].index
            let step = from < to ? 1 : -1
            var times: [LineRunTime] = []
            for (a, b) in zip(calls, calls.dropFirst()) {
                if times.isEmpty { times.append(LineRunTime(arrival: a.arrival, departure: a.departure)) }
                // A station passed: at the times between, as a stop of no
                // dwell.
                let gaps = abs(b.index - a.index)
                for k in 1..<gaps {
                    let t = a.departure + (b.arrival - a.departure) * Int64(k) / Int64(gaps)
                    times.append(LineRunTime(arrival: t, departure: t))
                }
                times.append(LineRunTime(arrival: b.arrival, departure: b.departure))
                _ = step
            }
            return LineRun(from: from, to: to, times: times)
        }
    }

    func testTheRealDayWithTrafficControl() throws {
        try requireReport()
        var (world, stations, down, up) = try Self.builtDemo(extra: 10_000_000_000)
        let old = try XCTUnwrap(world.lines.first)
        let sets = world.trains.map(\.id)
        for id in sets { try world.unassignTrain(id) }
        try world.removeLine(old.id)
        let line = try world.createLine(named: "THSR", stops: stations).id
        try world.setLinePerformance(line, to: .highSpeed)
        let runs = try Self.realRuns(names: HighSpeedDemo.stationNames)
        XCTAssertEqual(runs.count, 169)
        try world.setLineRuns(line, to: runs)
        // Southbound at the down track's main platforms, northbound at the
        // up track's; the ends' one platform each is on the down track.
        let berths: [(south: TrackPlatform?, north: TrackPlatform?)] = stations.indices.map { station in
            let platforms = world.trackPlatforms(of: stations[station])
            if station == 0 || station == stations.count - 1 {
                let end = platforms.first { down.contains($0.edge) }
                return (end, end)
            }
            return (platforms.first { down.contains($0.edge) }, platforms.first { up.contains($0.edge) })
        }
        func platform(_ station: Int, southbound: Bool) -> TrackPlatform? {
            southbound ? berths[station].south : berths[station].north
        }
        var preferences: [LineRoutePreference] = []
        for from in stations.indices.dropLast() {
            let to = from + 1
            if to < stations.count - 1, let south = platform(to, southbound: true) {
                preferences.append(LineRoutePreference(from: from, to: to, platform: south))
            }
            if from > 0, let north = platform(from, southbound: false) {
                preferences.append(LineRoutePreference(from: to, to: from, platform: north))
            }
        }
        try world.setLineRoutePreferences(line, to: preferences)
        // 44 sets the day needs, as many again in reserve.
        var all = sets
        while all.count < 60 {
            let id = try world.purchaseTrain(named: "THSR \(all.count + 1)").id
            try world.setTrainType(id, to: .highSpeed)
            try world.setTrainCars(id, to: HighSpeedDemo.cars)
            try world.setTrainPerformance(id, to: .highSpeed)
            all.append(id)
        }
        for id in all { try world.assignTrain(id, to: line) }
        let day = GameTime.secondsPerDay
        try run("the real day (169 runs)", &world) { world in
            let now = world.clock.now.seconds % day
            // Off the track when no run leaves its station within half an
            // hour.
            let wanted = Set(runs.filter { $0.times[0].departure >= now && $0.times[0].departure - now <= 30 * 60 }.map { stations[$0.from] })
            var standing: Set<StationID> = []
            for train in world.trains where train.position != nil && train.execution == nil {
                guard let station = world.stationsStoppedAt(by: train.id).first else { continue }
                if wanted.contains(station) {
                    standing.insert(station)
                } else {
                    try? world.unplaceTrain(train.id)
                }
            }
            // On the track five minutes before a run sends a set out, when
            // none stands at its first station.
            for run in runs {
                let lead = run.times[0].departure - now
                guard lead > LineRun.earliestDispatch, lead <= LineRun.earliestDispatch + 60, !standing.contains(stations[run.from]),
                      let berth = platform(run.from, southbound: run.isOutbound),
                      let spare = world.trains.first(where: { $0.position == nil })
                else { continue }
                if Self.place(spare.id, at: berth, forward: run.isOutbound, in: &world) { standing.insert(stations[run.from]) }
            }
        }
    }
}
