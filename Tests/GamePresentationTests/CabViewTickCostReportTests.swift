import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 379 (continued, CABVIEW-2): run only with `CABVIEW_REPORT`
/// set. The Kaohsiung Circular Light Rail bought, the second day at
/// 08:00, a train followed on the 3D map at 10×: the game loop's steps
/// timed tick by tick, and each tick taken apart (GameCore's advance,
/// the traffic reading, the glide, the heights, the bubbles).
@MainActor
final class CabViewTickCostReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    func testWhatTheRingCostsATickWhenFollowed() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CABVIEW_REPORT"] != nil else { throw XCTSkip("set CABVIEW_REPORT=1 to time the ring's ticks") }
        let rules: NewGameRules = environment["CABVIEW_RULES"] == "simple" ? .simple : .realistic
        let bought = try RealLineAcquisitionTests.game(round: KaohsiungLightRailTests.id, side: 1 << 21, heights: true, rules: rules)
        let line = try XCTUnwrap(bought.buyableRealLines.first { $0.id == KaohsiungLightRailTests.id })
        XCTAssertTrue(bought.acquireRealLine(bought.realLineOffer(for: line)), bought.message?.text ?? "")
        var world = bought.world
        // The second day at 08:00.
        let target = GameTime.secondsPerDay + 8 * GameTime.secondsPerHour
        while world.clock.now.seconds < target { try world.advance(ticks: 1) }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = bought.railways
        session.heights = bought.heights
        let train = try XCTUnwrap(session.world.trains.first { $0.position != nil && $0.movement.rate > 0 }?.id ?? session.world.trains.first?.id)
        session.selectTrain(train)
        // `CABVIEW_2D`: on the 2D map, nothing followed.
        if environment["CABVIEW_2D"] == nil {
            session.followTrain(train)
            session.setMap3DOpen(true)
        }
        session.setSpeed(.x10)
        print("CABVIEW2 world: trains \(session.world.trains.count), \(session.world.clock.now.clockText), speed \(session.world.clock.speed)")
        let clock = ContinuousClock()
        var motion = TrainMotion(world: session.world, time: 0)
        _ = session.trainMotion(after: motion, at: 0)
        var steps: [Double] = []
        let stepCount = Int(environment["CABVIEW_STEPS"] ?? "") ?? 6
        for _ in 0..<stepCount {
            for index in 0..<5 {
                guard var tick = session.beginLoopTick() else { break }
                tick.readsTraffic = index == 4
                var after = tick.world
                let core = try clock.measure { after = try GameSession.advanced(tick.world, by: 1, listening: false).world }
                let traffic = clock.measure { _ = TrafficReading(world: after, train: tick.train, in: .traditionalChinese, previous: tick.previousTraffic) }
                let glide = clock.measure { _ = tick.glide.map { TrainMotion(world: after, previous: $0, time: $0.time) } }
                let heights = clock.measure { _ = Map3DTrains.Heights(world: after) }
                let alerts = clock.measure { _ = after.situationAlerts() }
                var outcome: Result<GameSession.TickStep, GameError>!
                let work = await clock.measure { outcome = await tick.work() }
                let finish = clock.measure { session.finish(tick, with: outcome) }
                motion = session.trainMotion(after: motion, at: Double(steps.count))
                steps.append(Self.ms(work))
                print(String(
                    format: "CABVIEW2 %@ tick %d (traffic %@): work %.1f ms, finish %.1f ms | advance %.1f, traffic %.1f, glide %.1f, heights %.1f, alerts %.1f",
                    tick.world.clock.now.clockText, index, tick.readsTraffic ? "read" : "not read", Self.ms(work), Self.ms(finish),
                    Self.ms(core), Self.ms(traffic), Self.ms(glide), Self.ms(heights), Self.ms(alerts)
                ))
            }
        }
        // The traffic reading taken apart (for the GameCore part, B).
        let now = session.world
        var memo = GameWorld.DirectionMemo()
        let deadlock = clock.measure { _ = now.deadlock(memo: &memo) }
        var planMemo = GameWorld.DirectionMemo()
        let plan = clock.measure { _ = now.trafficPlan(memo: &planMemo) }
        var awaited = 0
        let routes = clock.measure {
            for train in now.trains where now.awaitedRoute(of: train.id, memo: &memo) != nil { awaited += 1 }
        }
        let waits = now.routeWaits()
        var kinds = ScheduledWaitKinds()
        let overlay = clock.measure { _ = now.trafficOverlay(waits, kinds: &kinds) }
        let whole = clock.measure { _ = now.routeWaits() }
        print(String(
            format: "CABVIEW2 traffic parts: routeWaits %.1f ms (deadlock %.1f, trafficPlan alone %.1f, awaitedRoute x%d after it %.1f, %d waiting), overlay %.1f ms",
            Self.ms(whole), Self.ms(deadlock), Self.ms(plan), now.trains.count, Self.ms(routes), awaited, Self.ms(overlay)
        ))
        // The game loop itself, in real time: how fast the game really runs.
        if let seconds = Double(environment["CABVIEW_LOOP_SECONDS"] ?? "") {
            if environment["CABVIEW_CPU"] == "standard" { GameSession.tickPace = TickPace(cpu: .standard) }
            defer { GameSession.tickPace = TickPace() }
            let before = session.world.clock.now.seconds
            let started = ContinuousClock.now
            session.startGameLoop()
            try await Task.sleep(for: .seconds(seconds))
            session.stopGameLoop()
            let real = Self.ms(ContinuousClock.now - started) / 1_000
            let game = Double(session.world.clock.now.seconds - before)
            print(String(format: "CABVIEW2 loop: %.1f s real, %.0f game s, %.2f of 10x (%@)", real, game, game / real / 10, GameSession.tickPace.summary))
        }
        let sorted = steps.sorted()
        print(String(format: "CABVIEW2 work: %d ticks, median %.1f ms, longest %.1f ms", sorted.count, sorted[sorted.count / 2], sorted.last ?? 0))
    }
}
