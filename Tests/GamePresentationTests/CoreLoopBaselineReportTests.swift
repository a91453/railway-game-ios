import Foundation
@testable import GameCore
import GamePresentation
import XCTest

/// Decision 254: the baseline a simpler core loop is measured against. A
/// new player's usual opening on a new game, played without a player under
/// the new game's rules and under each rule taken off in turn, printed as
/// Markdown: when the first fare comes in, how the money goes, how long the
/// trains stand held for a route or a block, and how far the curves slow
/// them (docs/research/CORE_LOOP_2026-10-16.md §1). It asserts nothing and
/// runs only on request:
///
///     CORE_LOOP_REPORT=14 swift test -c release -Xswiftc -enable-testing \
///       --filter CoreLoopBaselineReportTests
///
/// `CORE_LOOP_REPORT` is the days to play (1 to 60). The opening, as the
/// tutorial and the run testers were asked to play ("first fare, then the
/// second town and a second train", NEXT_PRIORITIES §0) play it:
///
/// 1. Minute 0: one line from the first town to the second (seed 1), its
///    track one curved edge bowed sideways as a finger draws it, a station
///    at each end, one train of four cars running all day.
/// 2. Day 3: the track runs on from the first town's end to the third
///    town (on the far side of the first), curving on from the first
///    line's track, and a second line calls at all three with a train of
///    its own, so the two share the first line's single track.
@MainActor
final class CoreLoopBaselineReportTests: XCTestCase {
    func testANewPlayersOpening() throws {
        guard let value = ProcessInfo.processInfo.environment["CORE_LOOP_REPORT"] else {
            throw XCTSkip("set CORE_LOOP_REPORT=<days> to print the core loop baseline")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (1...60).contains($0) ? $0 : nil }, "CORE_LOOP_REPORT is 1 to 60 days")
        var rows = [
            "| Rules | Commands | First fare (game min / real s at 600×) | Fares day 1 | Balance day 1 / 3 / 7 / \(days) | Back to the starting balance | Held train-minutes (episodes) | Slowest curve limit | Trips day 2 / \(days) | Deadlocked at the end |",
            "| --- | --: | --- | --: | --- | --- | --- | --: | --- | --: |",
        ]
        var shared: [PlayReport] = []
        // Decision 261: the rule sets are the shared presets.
        for preset in RulePreset.allCases {
            let started = Date()
            let (row, report) = try row(preset, days: days)
            rows.append(row)
            shared.append(report)
            FileHandle.standardError.write(Data("\(rows.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print("### A new player's opening (seed 1, \(days) days)\n\n" + rows.joined(separator: "\n"))
        print("\n" + PlayReport.table(shared, title: "A new player's opening"))
    }

    private func row(_ preset: RulePreset, days: Int64) throws -> (String, PlayReport) {
        var world = GameWorld.newGame(eventSeed: 1)
        try preset.apply(to: &world)
        let start = world.economy.balance.amount
        let towns = Land.townCentres(seed: 1, in: world.bounds)
        // Decision 261: the opening is the shared policy, played a minute
        // at a time; its due actions run as each day begins.
        var player = PolicyPlayer(world: world, policy: .thirdTown(towns, auto: preset == .autoService), byMinute: true)
        var firstFare: Int64?
        var balances: [Int64: Int64] = [:]
        var faresDayOne: Int64 = 0
        var backOn: Int64?
        var tripsDayTwo: Int64 = 0
        for day in 1...days {
            try player.playDay { world, minute in
                if firstFare == nil, world.financeReport(.day).current.fareRevenue.amount > 0 {
                    firstFare = minute
                }
            }
            world = player.world
            balances[day] = world.economy.balance.amount
            if day == 1 { faresDayOne = world.financeReport(.day).previous.fareRevenue.amount }
            if day == 2 { tripsDayTwo = world.lastDayTrips() }
            if backOn == nil, world.economy.balance.amount >= start { backOn = day }
        }
        let first = firstFare.map { "\($0) / " + String(format: "%.1f", Double($0) / 10) } ?? "none"
        let opening = player.memory.opening
        let curve = opening.edges.compactMap { world.trackEdge($0) }.flatMap { $0.speedLimits(going: .forward) }.map(\.speed).min().map { "\($0) km/h" } ?? "—"
        let shown = [1, 3, 7, days].map { balances[$0].map(dollars) ?? "—" }.joined(separator: " / ")
        let row = "| \(preset.title) | \(opening.commands) | \(first) | \(dollars(faresDayOne)) | \(shown) | "
            + "\(backOn.map { "day \($0)" } ?? "not by day \(days)") | \(player.heldTrainMinutes) (\(player.holdEpisodes)) | \(curve) | \(tripsDayTwo) / \(world.lastDayTrips()) | \(world.deadlockedTrains().count) of \(world.trains.count) trains |"
        return (row, PlayReport(label: preset.title, player: player))
    }
}

private func dollars(_ cents: Int64) -> String {
    "$\(cents / 100)"
}
