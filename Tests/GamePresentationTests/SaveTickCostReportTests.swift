import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 597 (PERF114): what a player's save costs a tick, played as
/// the game loop plays it (each tick worked out off the main actor, then
/// ``GameSession/finish(_:with:)`` on it). The owner's 113.1 report: a
/// real-world map of 112 stations, 16 lines and 134 trains whose tick took
/// some 400 ms at 600×, so the world moved on twice a second instead of ten
/// times. Run on request, with the save (not committed: a player's file):
///
///     PERF_SAVE=/path/to/save.json PERF_TICKS=60 PERF_SPEED=normal \
///       swift test -c release -Xswiftc -enable-testing --skip-build \
///       --filter SaveTickCostReportTests
@MainActor
final class SaveTickCostReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    func testWhatASaveCostsATick() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PERF_SAVE"] else { throw XCTSkip("set PERF_SAVE=<save> to time its ticks") }
        let ticks = Int(environment["PERF_TICKS"] ?? "") ?? 60
        let speed = environment["PERF_SPEED"].flatMap(GameSpeed.init(rawValue:)) ?? .normal
        let world = try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        print("PERF114 world: stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), \(world.clock.now.clockText)")
        let session = GameSession(world: world, language: .traditionalChinese)
        if world.geoAnchor != nil {
            let data = Map3DOpenEveryStartTests.data
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            session.coverage = data.coverage
            session.railways = data.railways
        }
        session.setSpeed(speed)
        let clock = ContinuousClock()
        var steps: [Double] = [], finishes: [Double] = []
        for _ in 0..<ticks {
            guard let tick = session.beginLoopTick() else { break }
            var outcome: Result<GameSession.TickStep, GameError>!
            let step = await clock.measure { outcome = await tick.work() }
            let finish = clock.measure { session.finish(tick, with: outcome) }
            steps.append(Self.ms(step))
            finishes.append(Self.ms(finish))
            if case .failure(let error) = outcome { XCTFail("\(error)"); break }
        }
        func line(_ name: String, _ values: [Double]) -> String {
            let sorted = values.sorted()
            return String(
                format: "PERF114 %@: %d ticks, mean %.1f ms, median %.1f ms, p95 %.1f ms, longest %.1f ms",
                name, sorted.count, sorted.reduce(0, +) / Double(max(1, sorted.count)), sorted[sorted.count / 2],
                sorted[min(sorted.count - 1, sorted.count * 95 / 100)], sorted.last ?? 0
            )
        }
        print(line("step (off the main actor)", steps))
        print(line("finish (main actor)", finishes))
        print("PERF114 ended at \(session.world.clock.now.clockText)")
    }
}
