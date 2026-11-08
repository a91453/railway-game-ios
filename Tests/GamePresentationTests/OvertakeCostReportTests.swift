import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 637: run only with `OVERTAKE_REPORT` set. A real line bought
/// (`OVERTAKE_LINE`, the Wenhu line `trtc:BR` by default, or the Kaohsiung
/// Circular Light Rail `krtc:C`), played to `OVERTAKE_AT` (clock seconds,
/// the first day's 08:00 by default), then `OVERTAKE_TICKS` ticks (20)
/// timed one by one: the advance, the traffic plan without decision 366's
/// headway overtakes, and ``GameWorld/planHeadwayOvertakes(_:)`` on it,
/// with how many services it pairs, and again with nothing kept (as the
/// first plan after a command finds it), which must plan the same waits.
/// `OVERTAKE_SAVE=<file>` saves the world played to `OVERTAKE_AT`, and
/// `OVERTAKE_FROM=<file>` plays on from it. `OVERTAKE_SAVE_END=<file>`
/// saves the world it ends at, and `OVERTAKE_COMPARE=<file>` checks that it
/// is the world such a file from another build holds.
@MainActor
final class OvertakeCostReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    func testWhatHeadwayOvertakesCostATick() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OVERTAKE_REPORT"] != nil else { throw XCTSkip("set OVERTAKE_REPORT=1 to time the headway overtakes") }
        let id = environment["OVERTAKE_LINE"] ?? "trtc:BR"
        let rules: NewGameRules = environment["OVERTAKE_RULES"] == "simple" ? .simple : .realistic
        let target = Int64(environment["OVERTAKE_AT"] ?? "") ?? 8 * GameTime.secondsPerHour
        let ticks = Int(environment["OVERTAKE_TICKS"] ?? "") ?? 20
        let clock = ContinuousClock()
        var world: GameWorld
        if let path = environment["OVERTAKE_FROM"] {
            world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: path))).world
        } else {
            world = try DepotReturnReportTests.bought(id, rules: rules)
            let started = clock.now
            while world.clock.now.seconds < target { try world.advance(ticks: 1) }
            print("OVERTAKE \(id) played to \(world.clock.now.clockText) in \(String(format: "%.0f", Self.ms(started.duration(to: clock.now)) / 1000)) s")
            if let path = environment["OVERTAKE_SAVE"] {
                try JSONEncoder().encode(SavedGame(world: world)).write(to: URL(fileURLWithPath: path))
            }
        }
        var parts = GameWorld.TrafficParts(), paths = GameWorld.PathMemo()
        var totals = (advance: 0.0, plan: 0.0, headway: 0.0, unkept: 0.0)
        for tick in 0..<ticks {
            let advance = try clock.measure { try world.advance(ticks: 1) }
            var before = GameWorld.TrafficPlan()
            let plan = clock.measure { before = world.trafficPlan(parts: &parts, paths: &paths, headwayOvertakes: false) }
            var now = before
            let headway = clock.measure { world.planHeadwayOvertakes(&now) }
            // Kept for the next tick, as the plan itself keeps it.
            parts.keep(now)
            // As the first plan after a command finds it: nothing kept.
            var fresh = before
            fresh.kept = [:]; fresh.opposite = nil; fresh.sidings = [:]; fresh.moves = [:]; fresh.nominal = [:]
            let unkept = clock.measure { world.planHeadwayOvertakes(&fresh) }
            XCTAssertEqual(now.waits, fresh.waits, "\(id) tick \(tick) at \(world.clock.now.clockText)")
            let eligible = world.headwayEligible(before).count
            totals.advance += Self.ms(advance); totals.plan += Self.ms(plan)
            totals.headway += Self.ms(headway); totals.unkept += Self.ms(unkept)
            print(String(
                format: "OVERTAKE %@ %@ tick %d: advance %.1f ms | plan without headway %.1f ms, headway %.1f ms (nothing kept: %.1f ms) | services %d, at a headway %d, pairs %d, waits %d → %d",
                id, world.clock.now.clockText, tick, Self.ms(advance), Self.ms(plan), Self.ms(headway), Self.ms(unkept),
                before.services.count, eligible, eligible * max(0, eligible - 1), before.waits.count, now.waits.count
            ))
        }
        // The world it played to, to compare with one another build played
        // to (`OVERTAKE_COMPARE`): the same world when nothing it does
        // changed.
        if let path = environment["OVERTAKE_SAVE_END"] {
            try JSONEncoder().encode(SavedGame(world: world)).write(to: URL(fileURLWithPath: path))
        }
        if let path = environment["OVERTAKE_COMPARE"] {
            let other = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: path))).world
            XCTAssertTrue(world == other, "\(id): the world played to \(world.clock.now.clockText) is not the one \(path) holds")
            print("OVERTAKE \(id) compared with \(path): \(world == other ? "the same world" : "DIFFERENT")")
        }
        let n = Double(max(1, ticks))
        print(String(
            format: "OVERTAKE %@ mean of %d ticks: advance %.1f ms, plan without headway %.1f ms, headway %.1f ms (nothing kept: %.1f ms)",
            id, ticks, totals.advance / n, totals.plan / n, totals.headway / n, totals.unkept / n
        ))
    }
}
