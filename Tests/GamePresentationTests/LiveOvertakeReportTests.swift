import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 542's measurement: a day of the TRA demo and of the Pingxi
/// challenge's single-track line with passing loops, under traffic control, printed, and only on
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

    /// The Pingxi challenge (decision 90): the Pingxi Line, single track
    /// with passing loops, beside the Yilan and Shen'ao Lines, a day from
    /// the start with traffic control on as it can be.
    func testThePingxiChallenge() throws {
        try skipUnlessAsked()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        let railways = try RealRailways(lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"))
        var world = PingxiChallenge.make(in: .english, railways: railways)
        world.setSpeed(.normal)
        var minutes = 0
        while (try? world.setTrafficControl(true)) == nil {
            try world.advance(ticks: 1)
            minutes += 1
            guard minutes < 24 * 60 else { return XCTFail("traffic control never turned on") }
        }
        say("Pingxi: \(world.trains.count) trains, \(world.lines.map { "\($0.name) \($0.hasRuns ? "runs" : "headway")" }), traffic control on after \(minutes) min")
        try measure("Pingxi challenge, traffic control on", &world, minutes: 24 * 60)
    }
}
