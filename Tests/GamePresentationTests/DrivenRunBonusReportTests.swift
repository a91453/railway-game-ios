import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// HEALTH-126: the most a day of runs driven by hand can earn the company
/// (decision 693), printed as Markdown. It asserts nothing and runs only
/// on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     DRIVEN_RUN_REPORT=tymc:A swift test -c release --skip-build --filter DrivenRunBonusReportTests
///
/// `DRIVEN_RUN_REPORT` is the real line bought (`tymc:A`, `trtc:BR`), in
/// the game `AirportReportTests` plays (a new game's rules: simple,
/// traffic control on). After a day to fill the trains, one day
/// is played a minute a tick and counted three ways:
///
/// - **every tick**: a run with full marks settled each minute for the
///   fullest train on the track, which is all
///   ``DrivenRun/shortestSeconds`` asks (the commands a player's game
///   never sends: the ceiling of the rule itself);
/// - **a player who never stops**: at the game's 1× a run is taken over
///   when free (the one earning most a second it still takes, of those
///   ``GameWorld/manualDriveTakeOver(of:)`` and
///   ``ManualDriveRun/shortestMetres`` allow), driven to its stop on
///   time, and settled with full marks for those on the train then;
/// - the same player at 85 marks.
@MainActor
final class DrivenRunBonusReportTests: XCTestCase {
    func testWhatADayOfRunsDrivenByHandEarns() throws {
        guard let network = ProcessInfo.processInfo.environment["DRIVEN_RUN_REPORT"] else {
            throw XCTSkip("set DRIVEN_RUN_REPORT=<real line> to print what a day of runs driven by hand earns")
        }
        // The game `AirportReportTests` plays: the map's people, places
        // and airports, so the trains carry whom a player's would.
        var world = try AirportReportTests.bought(network, data: RealWorldData.load(file: RealWorldDataLoadTests.file))
        XCTAssertEqual(world.accounts.mode, .management)
        world.setSpeed(.normal)
        // To the next midnight, a day to fill the trains, and the tick
        // that counts it.
        while world.clock.now.seconds % GameTime.secondsPerDay != 0 { try world.advance(ticks: 1) }
        try world.advance(ticks: 1_440 + 1)
        // The same day played without a settlement, to compare the cash.
        var untouched = world
        let counted = world.dayIndex(of: world.clock.now)
        var everyTick = (runs: 0, earned: Int64(0), refused: 0)
        var player = (runs: 0, full: Int64(0), good: Int64(0), riders: Int64(0), seconds: Int64(0))
        // The run the player drives: its train and when it reaches its stop.
        var driving: (train: TrainID, until: Int64)?
        for _ in 0..<1_440 {
            try world.advance(ticks: 1)
            try untouched.advance(ticks: 1)
            let now = world.clock.now.seconds
            // The player's run ends: settled for those on the train now.
            if let run = driving, now >= run.until {
                let riders = world.riderCount(of: run.train)
                player.runs += 1
                player.riders += riders
                player.full += DrivenRun.bonus(marks: 100, riders: riders).amount
                player.good += DrivenRun.bonus(marks: 85, riders: riders).amount
                driving = nil
            }
            if driving == nil {
                var best: (train: TrainID, until: Int64, rate: Int64)?
                for train in world.trains {
                    guard let found = world.manualDriveTakeOver(of: train.id),
                          found.run.length - found.covered >= ManualDriveRun.shortestMetres * WorldCoordinate.unitsPerMetre else { continue }
                    let left = max(DrivenRun.shortestSeconds, found.run.seconds - found.elapsed)
                    let rate = DrivenRun.bonus(marks: 100, riders: world.riderCount(of: train.id)).amount / left
                    if rate > best?.rate ?? -1 { best = (train.id, now + left, rate) }
                }
                if let best {
                    driving = (best.train, best.until)
                    player.seconds += best.until - now
                }
            }
            // Every tick: the fullest train a run is settled for.
            let fullest = world.trains.filter { world.settlesDrivenRuns(of: $0.id) }.max { world.riderCount(of: $0.id) < world.riderCount(of: $1.id) }
            if let fullest {
                do {
                    let settled = try world.settleDrivenRun(DrivenRun(train: fullest.id, outcome: .stopped, offset: 0, lateness: 0, overspeed: 0, usedEmergency: false))
                    everyTick.runs += 1
                    everyTick.earned += settled.bonus.amount
                } catch {
                    everyTick.refused += 1
                }
            }
        }
        try world.advance(ticks: 1)
        try untouched.advance(ticks: 1)
        let day = try XCTUnwrap(untouched.accounts.days.first { $0.day == counted })
        let fares = day.fareRevenue.amount
        func dollars(_ cents: Int64) -> String { "NT$\(cents / 100)" }
        func share(_ cents: Int64) -> String { fares > 0 ? String(format: "%.2f%%", Double(cents) * 100 / Double(fares)) : "–" }
        print([
            "### What a day of runs driven by hand earns: \(network), simple rules with traffic control",
            "",
            "The day's fares without any: \(dollars(fares)). Cash with a settlement every tick less the cash without: "
                + "\(dollars((world.economy.balance - untouched.economy.balance).amount)); the record: \(world.driving?.runs ?? 0) runs, \(dollars(world.driving?.earned.amount ?? 0)).",
            "",
            "| Who | Runs settled | Bonus in the day | Of the day's fares | A run | Riders a run |",
            "| --- | --: | --: | --: | --: | --: |",
            "| Every tick (a minute), full marks, the fullest train | \(everyTick.runs) (\(everyTick.refused) refused) | \(dollars(everyTick.earned)) | \(share(everyTick.earned)) | "
                + "\(dollars(everyTick.earned / Int64(max(1, everyTick.runs)))) | |",
            "| A player who never stops, full marks | \(player.runs) | \(dollars(player.full)) | \(share(player.full)) | "
                + "\(dollars(player.full / Int64(max(1, player.runs)))) | \(player.riders / Int64(max(1, player.runs))) |",
            "| The same at 85 marks | \(player.runs) | \(dollars(player.good)) | \(share(player.good)) | \(dollars(player.good / Int64(max(1, player.runs)))) | |",
            "",
            "The player drove \(player.seconds / 60) of the day's 1440 minutes (the rest: no run to take over).",
        ].joined(separator: "\n"))
    }
}
