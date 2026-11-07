import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 624: run only with `FIRST_TICK_REPORT` set. What the game
/// loop's first ticks of a game just opened cost, tick by tick, as the
/// loop runs them (``GameSession/LoopTick/work()``: the passenger routes
/// worked out ahead, the advance, the traffic reading, the bubbles), for
/// a new blank game, the high-speed demo and the Yilan Line demo. Built
/// as `swift test` builds it (GameCore -O, GamePresentation -Onone on
/// Linux), it stands for Xcode's Debug app once GameCore is optimized
/// there too; with GameCore's flag taken off it stands for the Debug app
/// before. `FIRST_TICK_REPORT` is the ticks to time (default 12).
@MainActor
final class FirstTickReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    func testTheFirstTicksOfAGameJustOpened() async throws {
        guard let value = ProcessInfo.processInfo.environment["FIRST_TICK_REPORT"] else {
            throw XCTSkip("set FIRST_TICK_REPORT=<ticks> to time a game's first ticks")
        }
        let ticks = Int(value) ?? 12
        let clock = ContinuousClock()
        var rows: [String] = []
        var blank: GameSession?
        let blankMade = clock.measure { blank = GameSession(world: GameWorld.newGame(eventSeed: 1), language: .traditionalChinese) }
        rows += await time("New blank game", try XCTUnwrap(blank), made: blankMade, ticks: ticks)
        var hsr: GameSession?
        let hsrMade = try clock.measure { hsr = try MapFrameCostReportTests.highSpeedSession() }
        rows += await time("High Speed Rail demo", try XCTUnwrap(hsr), made: hsrMade, ticks: ticks)
        var yilan: GameWorld?
        let yilanMade = try clock.measure { yilan = try TRADemoTests.opened.get() }
        rows += await time("Yilan Line demo", GameSession(world: try XCTUnwrap(yilan), language: .traditionalChinese), made: yilanMade, ticks: ticks)
        print(rows.joined(separator: "\n"))
    }

    private func time(_ name: String, _ session: GameSession, made: Duration, ticks: Int) async -> [String] {
        let clock = ContinuousClock()
        var rows = [String(
            format: "FIRSTTICK %@: made in %.0f ms, %d stations, %d trains, %@ at %@",
            name, Self.ms(made), session.world.stations.count, session.world.trains.count,
            "\(session.world.clock.speed)", session.world.clock.now.clockText
        )]
        if session.world.clock.isPaused { session.togglePause() }
        for index in 0..<ticks {
            guard let tick = session.beginLoopTick() else { rows.append("FIRSTTICK   paused"); break }
            var outcome: Result<GameSession.TickStep, GameError>!
            // The parts, timed apart on copies; then the tick as the loop runs it.
            var given = tick.world
            let ahead = await clock.measure { given = await PassengerRoutesAhead.given(to: tick.world) }
            let advance = clock.measure { try? given.advance(ticks: 1) }
            let after = given
            let traffic = clock.measure { _ = TrafficReading(world: after, train: tick.train, in: tick.language, previous: tick.previousTraffic) }
            let advice = clock.measure { _ = tick.advice?.advice(of: after) }
            let alerts = clock.measure { _ = after.situationAlerts() }
            let losing = clock.measure { _ = after.worstLosingLine() }
            let passing = clock.measure { _ = after.firstLineWithoutPlaceToPass() }
            let work = await clock.measure { outcome = await tick.work() }
            let finish = clock.measure { _ = session.finish(tick, with: outcome) }
            rows.append(String(
                format: "FIRSTTICK   tick %d at %@: work %.0f ms (apart: routes ahead %.0f, advance %.0f, traffic %.0f, advice %.0f [losing line %.0f, place to pass %.0f], alerts %.0f), finish %.1f ms%@",
                index, tick.world.clock.now.clockText, Self.ms(work), Self.ms(ahead), Self.ms(advance), Self.ms(traffic), Self.ms(advice), Self.ms(losing), Self.ms(passing), Self.ms(alerts), Self.ms(finish),
                (try? outcome.get()) == nil ? " REFUSED" : ""
            ))
        }
        return rows
    }
}
