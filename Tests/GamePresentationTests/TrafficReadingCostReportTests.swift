import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 138 (continued, TRAFFIC-READ): on request
/// (`TRAFFIC_READING_REPORT=<ticks>`, `TRAFFIC_READING_LINE=<id>`, the
/// Kaohsiung Circular Light Rail by default): what the game loop's
/// traffic reading (``TrafficReading``) costs after each 10× tick of a
/// bought real line, read from the world as the tick left it and from the
/// same world with nothing kept from its advances (``GameWorld/routeMemo``
/// emptied, as every reading was before), and that both read the same.
/// The author's iPhone 17 Pro took 0.7–1.2 s a reading on this line
/// (docs/research/CABVIEW2_MAC_TRACE_2026-11-07.md).
@MainActor
final class TrafficReadingCostReportTests: XCTestCase {
    func testWhatTheTrafficReadingCostsAfterEachTick() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["TRAFFIC_READING_REPORT"] else {
            throw XCTSkip("set TRAFFIC_READING_REPORT=<ticks>")
        }
        let ticks = Int(value) ?? 50
        let id = environment["TRAFFIC_READING_LINE"] ?? "krtc:C"
        let clock = ContinuousClock()
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        let started = clock.now
        var world = try DepotReturnReportTests.bought(id)
        XCTAssertTrue(world.isTrafficControlEnabled)
        // To 08:00 of the next day, at 6000×.
        world.setSpeed(.fast)
        while world.clock.now.seconds % GameTime.secondsPerDay < 8 * 3600 || world.clock.now.seconds < GameTime.secondsPerDay {
            try world.advance(ticks: 1)
        }
        world.setSpeed(.x10)
        print("\(id): \(world.trains.count) trains, ready in \(Int(ms(clock.now - started))) ms")
        var advance: [Double] = [], kept: [Double] = [], fresh: [Double] = []
        var previous: TrafficReading?
        for _ in 0..<ticks {
            advance.append(ms(clock.measure { try? world.advance(ticks: 1) }))
            var emptied = world
            emptied.routeMemo = GameWorld.RouteMemo()
            var before: TrafficReading?
            fresh.append(ms(clock.measure { before = TrafficReading(world: emptied, in: .traditionalChinese, previous: previous) }))
            var now: TrafficReading?
            kept.append(ms(clock.measure { now = TrafficReading(world: world, in: .traditionalChinese, previous: previous) }))
            XCTAssertEqual(now?.overlay, before?.overlay)
            XCTAssertEqual(world.routeWaits(), emptied.routeWaits())
            previous = now
        }
        func line(_ name: String, _ times: [Double]) {
            let sorted = times.sorted()
            print(String(format: "%@: mean %.1f ms, median %.1f ms, longest %.1f ms", name,
                         times.reduce(0, +) / Double(times.count), sorted[sorted.count / 2], sorted.last ?? 0))
        }
        print("== \(ticks) ticks at 10x from \(world.clock.now.seconds) s ==")
        line("advance", advance)
        line("reading, nothing kept (before)", fresh)
        line("reading, the world's memo lent (now)", kept)
    }
}
