import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 627: run only with `HOUR_TICK_REPORT` set. The high-speed
/// demo run by the game loop's ticks (``GameSession/LoopTick/work()``
/// and ``GameSession/finish(_:with:)``) from 07:00, set to 10× two game
/// minutes before the game hour `HOUR_TICK_REPORT` (default 11), and the
/// ticks around that hour timed one by one; the slow ones and those at the
/// hour also taken apart on copies (the passenger routes worked out ahead,
/// the advance, the traffic reading, the station master's advice and its
/// two slow parts, the map bubbles). The Debug app on the Simulator
/// stopped its clock some 4 s at 11:00 at 10× after a pause and a resume.
@MainActor
final class HourTickReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func second(_ time: GameTime) -> String {
        let second = time.seconds % GameTime.secondsPerDay
        return String(format: "%02d:%02d:%02d", second / 3600, second / 60 % 60, second % 60)
    }

    func testTheTicksAroundAGameHour() async throws {
        guard let value = ProcessInfo.processInfo.environment["HOUR_TICK_REPORT"] else {
            throw XCTSkip("set HOUR_TICK_REPORT=<hour> to time the high-speed demo's ticks around that hour")
        }
        let hour = Int64(value) ?? 11
        let clock = ContinuousClock()
        var made: GameSession?
        let making = try clock.measure { made = try MapFrameCostReportTests.highSpeedSession() }
        let session = try XCTUnwrap(made)
        if session.world.clock.isPaused { session.togglePause() }
        // As the player did: the game runs at its normal speed (a game
        // minute a tick) and is set to 10× two game minutes before the
        // hour, a command; `HOUR_TICK_FROM_START` sets 10× at 07:00.
        let fromStart = ProcessInfo.processInfo.environment["HOUR_TICK_FROM_START"] != nil
        session.setSpeed(fromStart ? .x10 : .normal)
        print(String(format: "HOURTICK made in %.0f ms, %d trains, at %@", Self.ms(making), session.world.trains.count, session.world.clock.now.clockText))
        let day = session.world.clock.now.seconds / GameTime.secondsPerDay
        let target = day * GameTime.secondsPerDay + hour * GameTime.secondsPerHour
        var slowest: [(String, Double)] = []
        var hourly: [String] = []
        while session.world.clock.now.seconds < target + 60 {
            if !fromStart, session.world.clock.speed == .normal, session.world.clock.now.seconds >= target - 120 {
                session.setSpeed(.x10)
                print("HOURTICK set to 10× at \(Self.second(session.world.clock.now))")
            }
            guard let tick = session.beginLoopTick() else { XCTFail("paused"); return }
            var outcome: Result<GameSession.TickStep, GameError>!
            let work = await clock.measure { outcome = await tick.work() }
            let finish = clock.measure { _ = session.finish(tick, with: outcome) }
            let at = Self.second(tick.world.clock.now)
            slowest.append(("\(at) work", Self.ms(work)))
            slowest.append(("\(at) finish", Self.ms(finish)))
            let nearHour = abs(tick.world.clock.now.seconds - target) <= 2
            if (tick.world.clock.now.seconds + 1) % GameTime.secondsPerHour == 0 {
                hourly.append(String(format: "HOURTICK   hour tick from %@: work %.0f ms, finish %.0f ms", at, Self.ms(work), Self.ms(finish)))
            }
            guard nearHour || Self.ms(work) > 50 else { continue }
            // The tick taken apart on copies of the world it began from.
            var given = tick.world
            let ahead = await clock.measure { given = await PassengerRoutesAhead.given(to: tick.world) }
            let advance = clock.measure { try? given.advance(ticks: 1) }
            let after = given
            let traffic = clock.measure { _ = TrafficReading(world: after, train: tick.train, in: tick.language, previous: tick.previousTraffic) }
            let advice = clock.measure { _ = tick.advice?.advice(of: after) }
            let alerts = clock.measure { _ = after.situationAlerts() }
            let losing = clock.measure { _ = after.worstLosingLine() }
            let passing = clock.measure { _ = after.firstLineWithoutPlaceToPass() }
            print(String(
                format: "HOURTICK tick from %@: work %.0f ms, finish %.1f ms (apart: routes ahead %.0f, advance %.0f, traffic %.0f, advice %.0f [kept: losing line %@, place to pass %@], alerts %.0f; asked anyway: losing line %.0f, place to pass %.0f)%@",
                at, Self.ms(work), Self.ms(finish), Self.ms(ahead), Self.ms(advance), Self.ms(traffic), Self.ms(advice),
                tick.advice?.leader == nil ? "no" : "yes", tick.advice?.placeToPass == nil ? "no" : "yes",
                Self.ms(alerts), Self.ms(losing), Self.ms(passing), (try? outcome.get()) == nil ? " REFUSED" : ""
            ))
        }
        print(hourly.joined(separator: "\n"))
        let top = slowest.sorted { $0.1 > $1.1 }.prefix(8).map { String(format: "%@ %.0f ms", $0.0, $0.1) }
        print("HOURTICK slowest: " + top.joined(separator: ", "))
    }
}
