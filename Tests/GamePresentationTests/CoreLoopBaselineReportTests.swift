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
        for preset in Preset.allCases {
            let started = Date()
            rows.append(try row(preset, days: days))
            FileHandle.standardError.write(Data("\(rows.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print("### A new player's opening (seed 1, \(days) days)\n\n" + rows.joined(separator: "\n"))
    }

    /// The rules the opening is played under: the new game's, and each
    /// rule a simpler default might take off.
    enum Preset: String, CaseIterable {
        case newGame = "New game (every rule on)"
        case noCurveLimits = "− curve limits (217)"
        case noBlockSections = "− block sections (212)"
        case noRealisticOperation = "− realistic operation (207)"
        case noFlexDispatch = "− flexible dispatch (172)"
        case simple = "Simple: − 207, 212, 217, 172, 169, 180"
        case noTrafficControl = "Simple and − traffic control (32)"
        /// Decision 258: the app's default, ``NewGameRules/simple``.
        case simpleRules = "Simple rules (258): − 207, 212, 217, 169, 180, 156, weather"

        func apply(to world: inout GameWorld) throws {
            switch self {
            case .newGame: break
            case .simpleRules: NewGameRules.simple.apply(to: &world)
            case .noCurveLimits: world.setCurveSpeedLimits(false)
            case .noBlockSections: world.setBlockSections(false)
            case .noRealisticOperation: world.setRealisticOperation(false)
            case .noFlexDispatch: world.setFlexDispatch(false)
            case .simple, .noTrafficControl:
                world.setRealisticOperation(false)
                world.setBlockSections(false)
                world.setCurveSpeedLimits(false)
                world.setFlexDispatch(false)
                world.setDoorCrowding(false)
                world.setRollingStockEconomics(false)
                if self == .noTrafficControl { try world.setTrafficControl(false) }
            }
        }
    }

    private func row(_ preset: Preset, days: Int64) throws -> String {
        var world = GameWorld.newGame(eventSeed: 1)
        try preset.apply(to: &world)
        let start = world.economy.balance.amount
        let towns = Land.townCentres(seed: 1, in: world.bounds)
        // Decision 261: the opening is the shared policy; its due actions
        // run as each day begins.
        var player = PolicyPlayer(world: world, policy: .thirdTown(towns))
        try player.runDue(onDay: 0)
        world = player.world
        var firstFare: Int64?
        var balances: [Int64: Int64] = [:]
        var faresDayOne: Int64 = 0
        var backOn: Int64?
        var heldMinutes = 0, episodes = 0
        var held: Set<TrainID> = []
        var minute: Int64 = 0
        var tripsDayTwo: Int64 = 0
        while minute < days * 1_440 {
            if minute > 0, minute % 1_440 == 0 {
                try player.runDue(onDay: minute / 1_440)
            }
            try player.advance(ticks: 1)
            world = player.world
            minute += 1
            if firstFare == nil, world.financeReport(.day).current.fareRevenue.amount > 0 {
                firstFare = minute
            }
            let holding = Set(world.trains.map(\.id).filter { world.trainHoldingRoute(of: $0) != nil })
            heldMinutes += holding.count
            episodes += holding.subtracting(held).count
            held = holding
            if minute % 1_440 == 0 {
                let day = minute / 1_440
                balances[day] = world.economy.balance.amount
                if day == 1 { faresDayOne = world.financeReport(.day).previous.fareRevenue.amount }
                if day == 2 { tripsDayTwo = world.lastDayTrips() }
                if backOn == nil, world.economy.balance.amount >= start { backOn = day }
            }
        }
        let first = firstFare.map { "\($0) / " + String(format: "%.1f", Double($0) / 10) } ?? "none"
        let opening = player.memory.opening
        let curve = opening.edges.compactMap { world.trackEdge($0) }.flatMap { $0.speedLimits(going: .forward) }.map(\.speed).min().map { "\($0) km/h" } ?? "—"
        let shown = [1, 3, 7, days].map { balances[$0].map(dollars) ?? "—" }.joined(separator: " / ")
        return "| \(preset.rawValue) | \(opening.commands) | \(first) | \(dollars(faresDayOne)) | \(shown) | "
            + "\(backOn.map { "day \($0)" } ?? "not by day \(days)") | \(heldMinutes) (\(episodes)) | \(curve) | \(tripsDayTwo) / \(world.lastDayTrips()) | \(world.deadlockedTrains().count) of \(world.trains.count) trains |"
    }
}

private func dollars(_ cents: Int64) -> String {
    "$\(cents / 100)"
}
