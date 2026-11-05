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
        var steps: [Double] = [], finishes: [Double] = [], clocks: [String] = []
        var hours: [Int64: [Double]] = [:]
        for _ in 0..<ticks {
            guard let tick = session.beginLoopTick() else { break }
            // The tick before each hour, taken apart: the routes worked out
            // ahead, GameCore's advance, the station master's advice.
            if environment["PERF_PARTS"] != nil, tick.world.clock.now.seconds % GameTime.secondsPerHour >= GameTime.secondsPerHour - 60 {
                var ahead = tick.world
                let routes = await clock.measure { ahead = await PassengerRoutesAhead.given(to: tick.world) }
                var after = ahead
                let core = try clock.measure { after = try GameSession.advanced(ahead, by: 1, listening: false).world }
                let advice = clock.measure { _ = tick.advice?.advice(of: after) }
                let traffic = clock.measure { _ = TrafficReading(world: after, train: nil, in: .traditionalChinese, previous: nil) }
                let alerts = clock.measure { _ = after.situationAlerts() }
                print(String(
                    format: "PERF114   parts %@: routes ahead %.1f, advance %.1f, advice %.1f, traffic %.1f, alerts %.1f ms",
                    tick.world.clock.now.clockText, Self.ms(routes), Self.ms(core), Self.ms(advice), Self.ms(traffic), Self.ms(alerts)
                ))
            }
            var outcome: Result<GameSession.TickStep, GameError>!
            let step = await clock.measure { outcome = await tick.work() }
            let finish = clock.measure { session.finish(tick, with: outcome) }
            steps.append(Self.ms(step))
            clocks.append(tick.world.clock.now.clockText)
            hours[tick.world.clock.now.seconds % GameTime.secondsPerDay / 3_600, default: []].append(Self.ms(step))
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
        for hour in hours.keys.sorted() {
            print(line(String(format: "  hour %02lld", hour), hours[hour]!))
        }
        for index in steps.indices.sorted(by: { steps[$0] > steps[$1] }).prefix(10) {
            print(String(format: "PERF114   costliest: %@ %.1f ms", clocks[index], steps[index]))
        }
        print("PERF114 ended at \(session.world.clock.now.clockText)")
    }

    /// The station master's hourly advice in the save, taken apart.
    func testWhatTheAdviceCosts() throws {
        guard let path = ProcessInfo.processInfo.environment["PERF_ADVICE"] else { throw XCTSkip("set PERF_ADVICE=<save> to time the advice") }
        let world = try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let clock = ContinuousClock()
        let parts: [(String, () -> Void)] = [
            ("whole advice", { _ = StationMasterAdvice(world: world) }),
            ("shortSteamTrains", { _ = StationMasterAdvice.shortSteamTrains(in: world) }),
            ("debt", { _ = StationMasterAdvice.debt(in: world) }),
            ("mapAlerts", { _ = world.mapAlerts() }),
            ("firstLineWithoutPlaceToPass", { _ = world.firstLineWithoutPlaceToPass() }),
            ("worstLosingLine", { _ = world.worstLosingLine() }),
            ("festival", { _ = StationMasterAdvice.festival(in: world) }),
        ]
        // Decision 597: the dominators agree with decision 264's search on
        // every leg of the save's lines.
        var legs = 0
        for line in world.lines {
            guard let journey = world.lineJourney(line.id) else { continue }
            for (leg, edges) in GameWorld.legEdges(of: journey) where leg.to > leg.from && leg.to < line.stops.count {
                let (a, b) = (line.stops[leg.from], line.stops[leg.to])
                XCTAssertEqual(world.singleTrackLength(of: edges, from: a, to: b), SingleTrackLengthTests.searched(world, of: edges, from: a, to: b))
                legs += 1
            }
        }
        print("PERF114 advice legs compared: \(legs)")
        let repeats = Int(ProcessInfo.processInfo.environment["PERF_REPEATS"] ?? "") ?? 3
        for (name, part) in parts {
            let spent = clock.measure { for _ in 0..<repeats { part() } }
            print(String(format: "PERF114 advice %@: %.1f ms", name, Self.ms(spent) / Double(repeats)))
        }
    }
}
