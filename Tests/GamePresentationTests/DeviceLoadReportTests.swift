import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 460: what a tick costs and what a world holds as the map grows
/// and the game speeds up, and so how fast the game really runs on each
/// CPU tier (``TickPace``). Run on request, in release for the device's
/// proportions:
///
///     DEVICE_LOAD_REPORT=60 swift test -c release -Xswiftc -enable-testing --filter DeviceLoadReportTests
///
/// `DEVICE_LOAD_REPORT` is the ticks timed at each size and speed, after a
/// game hour run to warm the caches, in the demos (``games()``).
final class DeviceLoadReportTests: XCTestCase {
    func testWhatATickCostsBySizeAndSpeed() throws {
        guard let value = ProcessInfo.processInfo.environment["DEVICE_LOAD_REPORT"], let ticks = Int(value), ticks > 0 else {
            throw XCTSkip("set DEVICE_LOAD_REPORT=<ticks> to time the ticks")
        }
        let clock = ContinuousClock()
        var rows = ["| Game | Stations | Trains running | Speed | Median ms/tick | p95 | Slowest | Memory grown running (MB) | Game speed: lower / standard / higher |",
                    "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |"]
        for (name, made) in try Self.games() {
            let before = Self.residentMegabytes()
            var world = made
            for speed in [GameSpeed.normal, .double, .fast] {
                world.setSpeed(speed)
                // A game hour to warm the caches (the day's plan among them).
                try world.advance(ticks: Int(3_600 * 10 / speed.tenthsPerTick))
                var times: [Double] = []
                for _ in 0..<ticks {
                    let spent = try clock.measure { try world.advance(ticks: 1) }
                    times.append(Double(spent.components.seconds) * 1_000 + Double(spent.components.attoseconds) / 1e15)
                }
                times.sort()
                let median = times[times.count / 2], p95 = times[min(times.count - 1, Int(Double(times.count) * 0.95))]
                // How fast the game runs: steps of five ticks of the median,
                // the rest the pace's.
                let speeds = DeviceCPUTier.allCases.map { tier -> String in
                    let work = Duration.milliseconds(Int64(5 * median))
                    let step = max(work + TickPace(cpu: tier).rest(afterWorking: work, interval: GameSession.tickInterval),
                                   GameSession.maximumStepDuration)
                    let real = Double(step.components.seconds) + Double(step.components.attoseconds) / 1e18
                    return "\(Int((5 * Double(speed.tenthsPerTick) / 10 / real).rounded()))×"
                }
                rows.append("| \(name) | \(world.stations.count) | \(world.trains.count { $0.position != nil }) | \(speed.rawValue) | \(String(format: "%.1f", median)) | "
                    + "\(String(format: "%.1f", p95)) | \(String(format: "%.1f", times.last ?? 0)) | \(Self.residentMegabytes() - before) | "
                    + speeds.joined(separator: " / ") + " |")
            }
        }
        print(rows.joined(separator: "\n"))
    }

    /// The process's resident memory, in megabytes (Linux's
    /// `/proc/self/statm`, pages of 4 KiB); 0 elsewhere.
    static func residentMegabytes() -> Int {
        guard let text = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else { return 0 }
        let fields = text.split(separator: " ")
        guard fields.count > 1, let pages = Int(fields[1]) else { return 0 }
        return pages * 4_096 / 1_048_576
    }

    /// The demos, smallest first: the simple one, the high-speed one and
    /// the Yilan Line's (decision 240), with their land.
    static func games() throws -> [(String, GameWorld)] {
        return [
            ("Simple demo", DemoWorld.make(in: .english)),
            ("High-speed demo", try HighSpeedDemo.make(in: .english, railways: HighSpeedDemoTests.railways(), population: HighSpeedDemoTests.population,
                                                       places: HighSpeedDemoTests.places)),
            ("Yilan Line demo", try TRADemo.make(in: .english, railways: TRADemoTests.railways(), population: HighSpeedDemoTests.population,
                                                 places: HighSpeedDemoTests.places)),
        ]
    }
}
