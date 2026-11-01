import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 542's measurement: a day of the TRA demo and of a single-track
/// line with a passing loop, under traffic control, printed, and only on
/// request (the high-speed demo's day is `TrafficControlTimingReportTests`
/// with `TRAFFIC_TIMING_ON=1`):
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     LIVE_OVERTAKE_REPORT=1 swift test -c release --skip-build --filter LiveOvertakeReportTests
///
/// Each prints the seconds of computing the day took, the most a set was
/// ever late, the runs due and dropped, the waits planned (and how many of
/// them overtakes), the sets deadlocked at the end and a digest of the
/// saved world, so two builds can be compared.
final class LiveOvertakeReportTests: XCTestCase {
    private func say(_ text: String) {
        FileHandle.standardError.write(Data(("OVERTAKE " + text + "\n").utf8))
    }

    private func skipUnlessAsked() throws {
        guard ProcessInfo.processInfo.environment["LIVE_OVERTAKE_REPORT"] != nil else { throw XCTSkip("Set LIVE_OVERTAKE_REPORT=1.") }
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

    /// Runs `world` `minutes` game minutes, a minute at a time, and prints
    /// what it measured.
    private func measure(_ name: String, _ world: inout GameWorld, minutes: Int) throws {
        var seconds = 0.0
        var late: [String: Int64] = [:]
        var waits: Set<ScheduledTrafficWait> = []
        for _ in 0..<minutes {
            let began = Date()
            try world.advance(ticks: 1)
            seconds += Date().timeIntervalSince(began)
            for train in world.trains where train.execution != nil {
                late[train.name] = max(late[train.name] ?? 0, world.lateness(of: train.id) ?? 0)
            }
            waits.formUnion(world.scheduledTrafficWaits())
        }
        let now = world.clock.now.seconds
        var due = 0, dropped = 0
        for line in world.lines {
            for (index, run) in line.runs.enumerated() {
                var day: Int64 = 0
                while run.start(onDay: day + 1) + LineRun.latestDispatch < now { day += 1 }
                guard run.start(onDay: day) + LineRun.latestDispatch < now else { continue }
                due += 1
                if (line.runDays[index] ?? -1) < day { dropped += 1 }
            }
        }
        let lateness = late.values.sorted()
        say(String(
            format: "%@: %.1f s computing, late worst %.1f min, median of sets %.1f min, %d runs due, %d dropped, %d waits planned (%d overtakes), %d deadlocked, digest %@",
            name, seconds, Double(lateness.last ?? 0) / 60, Double(lateness.isEmpty ? 0 : lateness[lateness.count / 2]) / 60, due, dropped,
            waits.count, waits.count { $0.kind == .overtake }, world.deadlockedTrains().count, try Self.digest(world)
        ))
    }

    /// The TRA demo as the game opens it (07:00), run until traffic
    /// control can be turned on (the demo has it off, and no two sets may
    /// share track when it is turned on; with it off no wait is ever
    /// planned), then a day with it on.
    func testTheTRADemo() throws {
        try skipUnlessAsked()
        var world = try TRADemoTests.opened.get()
        var minutes = 0
        while (try? world.setTrafficControl(true)) == nil {
            try world.advance(ticks: 1)
            minutes += 1
            guard minutes < 24 * 60 else { return XCTFail("traffic control never turned on") }
        }
        say("TRA demo: traffic control on at \(world.clock.now.minute / 60 % 24):\(String(format: "%02d", world.clock.now.minute % 60))")
        try measure("TRA demo, traffic control on", &world, minutes: 24 * 60)
    }

    /// A single track about 8 km long, W – M – E, M with a loop beside
    /// the main track, W and E each with a bay beside their main platform:
    /// a stopping train (W, M, E) and an express (W, E) out of W every
    /// hour from 06:00 to 21:00, the express 6 minutes behind, and each
    /// back from E half an hour later. The stopping train's timetable
    /// allows it less time than it needs, so it runs late and the express
    /// catches it up.
    func testASingleTrackWithAPassingLoop() throws {
        try skipUnlessAsked()
        let scale: Int64 = 16
        var world = try GameWorld(
            bounds: WorldBounds(width: 36_864 * scale, height: 10_240 * scale),
            economy: GameEconomy(balance: 100_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0)),
            clock: GameClock(speed: .normal)
        )
        // Nodes: 1 W main end, 2 W bay end, 3 W turnout, 4 loop start, 5
        // loop end, 6 E turnout, 7 E main end, 8 E bay end, 9 and 10 the
        // loop's ends.
        for (x, y): (Int64, Int64) in [(1_024, 4_096), (1_024, 2_048), (7_168, 4_096), (11_264, 4_096), (25_600, 4_096), (29_696, 4_096),
                                       (35_840, 4_096), (35_840, 2_048), (15_360, 6_144), (21_504, 6_144)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x * scale, y: y * scale))
        }
        func point(_ x: Int64, _ y: Int64) -> PlanPoint { PlanPoint(x: x * scale, y: y * scale) }
        try world.buildTrackEdge(from: .node(1), to: .node(3)) // e1 W main
        try world.buildTrackEdge(from: .node(2), to: .node(3), curve: .cubic(point(4_096, 2_048), point(4_096, 4_096))) // e2 W bay
        try world.buildTrackEdge(from: .node(3), to: .node(4)) // e3
        try world.buildTrackEdge(from: .node(4), to: .node(5)) // e4 M main
        try world.buildTrackEdge(from: .node(4), to: .node(9), curve: .cubic(point(13_312, 4_096), point(13_312, 6_144))) // e5
        try world.buildTrackEdge(from: .node(9), to: .node(10)) // e6 M loop
        try world.buildTrackEdge(from: .node(10), to: .node(5), curve: .cubic(point(23_552, 6_144), point(23_552, 4_096))) // e7
        try world.buildTrackEdge(from: .node(5), to: .node(6)) // e8
        try world.buildTrackEdge(from: .node(6), to: .node(7)) // e9 E main
        try world.buildTrackEdge(from: .node(6), to: .node(8), curve: .cubic(point(32_768, 4_096), point(32_768, 2_048))) // e10 E bay
        var ids: [StationID] = []
        for (name, x) in [("W", Int64(4_096)), ("M", 18_432), ("E", 32_768)] {
            ids.append(try world.buildStation(named: name, at: PlanPoint(x: x * scale, y: 8_192 * scale)).id)
        }
        func length(_ edge: Int) throws -> Int64 { try XCTUnwrap(world.trackEdge(.edge(edge))?.length) }
        for (station, edge) in [(0, 1), (0, 2), (1, 4), (1, 6), (2, 9), (2, 10)] {
            let l = try length(edge)
            try world.addTrackPlatform(ids[station], on: .edge(edge), from: l / 2 - 1_024 * scale, to: l / 2 + 1_024 * scale)
        }
        func at(_ seconds: Int64, _ dwell: Int64 = 0) -> LineRunTime { LineRunTime(arrival: seconds, departure: seconds + dwell) }
        let local = try world.createLine(named: "Local", stops: ids).id
        let express = try world.createLine(named: "Express", stops: [ids[0], ids[2]]).id
        var localRuns: [LineRun] = [], expressRuns: [LineRun] = []
        for hour in Int64(6)...21 {
            let t = hour * 3_600
            localRuns.append(LineRun(from: 0, to: 2, times: [at(t), at(t + 180, 30), at(t + 420)]))
            localRuns.append(LineRun(from: 2, to: 0, times: [at(t + 1_800), at(t + 2_040, 30), at(t + 2_280)]))
            expressRuns.append(LineRun(from: 0, to: 1, times: [at(t + 360), at(t + 780)]))
            expressRuns.append(LineRun(from: 1, to: 0, times: [at(t + 2_160), at(t + 2_580)]))
        }
        try world.setLineRuns(local, to: localRuns)
        try world.setLineRuns(express, to: expressRuns)
        for (line, edge) in [(local, 1), (express, 2)] {
            let id = try world.purchaseTrain(named: line == local ? "Local" : "Express").id
            let offset = try length(edge) / 2 + 1_024 * scale
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 1_024)
            try world.assignTrain(id, to: line)
        }
        world.setKeepLeft(true)
        try world.setTrafficControl(true)
        world.setSpeed(.normal)
        try measure("single track with a passing loop", &world, minutes: 24 * 60)
    }
}
