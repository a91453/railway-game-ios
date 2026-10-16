import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 145: the sandbox challenges played without a player on several
/// seeds, three ways each, printed as a Markdown table of the day each goal
/// was met and how the challenge ended, so the targets can be checked again
/// whenever a rule moves them (decision 86's were measured on a line that
/// decision 137 left losing money). It asserts nothing and runs only on
/// request:
///
///     CHALLENGE_REPORT=1 swift test -c release -Xswiftc -enable-testing \
///       --filter ChallengeReportTests
///
/// `CHALLENGE_REPORT` is the number of seeds (1 to 8). A grown network
/// plays a day in some 2 seconds, so a seed's three challenges take over an
/// hour; to run them side by side, `CHALLENGE_SEEDS` (such as `2,5`)
/// picks seeds, `CHALLENGE_ONLY` one challenge by ID and `CHALLENGE_PLAY`
/// one way to play (`linked`, `longTrains` or `grown`). `CHALLENGE_RUN_ON=1`
/// plays on to the deadline after a challenge ends, for the last column
/// (to tune a target); `CHALLENGE_TRACE=1` prints every day. The
/// ways to play:
///
/// - **Linked**: the least the first challenge asks, from day 1: a line
///   from the first town to the second and one from the first to the
///   third, one train of four cars each, never changed.
/// - **Long trains**: the same lines with trains of eight cars. Until
///   about day 120 the riders are the demand's; after it, the trains' room
///   (decision 145).
/// - **Grown**: long trains, and from day 30 a line from the second town
///   to the third and one from each town to the nearest edge of the map
///   (an outside connection, decision 137), each built as soon as the money
///   allows.
///
/// A line that would cross track already built runs on a viaduct one
/// clearance higher, as a player would build it; a station in a town is
/// shared by every line calling there.
final class ChallengeReportTests: XCTestCase {
    func testTheSandboxChallenges() throws {
        guard let value = ProcessInfo.processInfo.environment["CHALLENGE_REPORT"] else {
            throw XCTSkip("set CHALLENGE_REPORT=<seeds> to print the challenge report")
        }
        let environment = ProcessInfo.processInfo.environment
        let count = try XCTUnwrap(Int(value).flatMap { (1...8).contains($0) ? $0 : nil }, "CHALLENGE_REPORT is 1 to 8 seeds")
        let seeds = environment["CHALLENGE_SEEDS"].map { $0.split(separator: ",").compactMap { UInt32($0) } } ?? Array(1...UInt32(count))
        let challenges = Challenge.sandbox.filter { challenge in environment["CHALLENGE_ONLY"].map { $0 == challenge.id } ?? true }
        let plays = Play.allCases.filter { play in environment["CHALLENGE_PLAY"].map { $0 == "\(play)" } ?? true }
        let runOn = environment["CHALLENGE_RUN_ON"] != nil
        var lines: [String] = []
        for challenge in challenges {
            let goals = challenge.goalsText(in: .english)
            lines += [
                "### \(challenge.title(in: .english)): \(challenge.ratingsText(in: .english))",
                "",
                "| Seed | Play | " + goals.joined(separator: " | ") + " | Result | Riders a day / population / equity on day " + Self.checkpoints.map(String.init).joined(separator: ", ") + " |",
                "| --: | --- |" + String(repeating: " --: |", count: goals.count) + " --- | --- |",
            ]
            var shared: [PlayReport] = []
            for seed in seeds {
                for play in plays {
                    let started = Date()
                    let (row, report) = try row(challenge, seed: seed, play: play, runOn: runOn)
                    lines.append(row)
                    shared.append(report)
                    // Each row as it comes: the longest take minutes.
                    FileHandle.standardError.write(Data("\(lines.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
                }
            }
            lines.append("")
            // Decision 261: the measures every report shares.
            lines += [PlayReport.table(shared, title: challenge.title(in: .english)), ""]
        }
        print(lines.joined(separator: "\n"))
    }

    enum Play: String, CaseIterable {
        case linked = "Linked"
        case longTrains = "Long trains"
        case grown = "Grown"

        /// The shared policy that plays it (decision 261).
        var policy: Policy.ChallengePlay {
            switch self {
            case .linked: .linked
            case .longTrains: .longTrains
            case .grown: .grown
            }
        }
    }

    /// The days whose riders, population and equity the last column shows.
    static let checkpoints: [Int64] = [30, 60, 120, 240, 360, 720, 1_080]

    /// Plays `challenge` on `seed` until it ends (or, `runOn`, until its
    /// deadline) and returns its row.
    private func row(_ challenge: Challenge, seed: UInt32, play: Play, runOn: Bool) throws -> (String, PlayReport) {
        let start = GameWorld.newGame(challenge: challenge, eventSeed: seed)
        let towns = Land.townCentres(seed: seed, in: start.bounds)
        // Decision 261: the way to play is the shared policy, each line
        // built as soon as it can be paid for; a line refused for anything
        // else is a broken script.
        var player = try reportPlayer(start, policy: .challenge(play.policy, towns: towns, bounds: start.bounds))
        try player.advance(ticks: 1)
        var checked: [String] = []
        let deadline = player.world.scenario?.scenario.deadlineDays ?? 0
        while player.world.scenario?.outcome == nil || (runOn && player.day < deadline) {
            let clock = Date()
            try player.playDay()
            let world = player.world, day = player.day
            if Self.checkpoints.contains(day) {
                checked.append("\(world.lastDayTrips() / 1_000)k / \(world.totalResidents() / 1_000)k / $\(world.balanceSheet().equity.amount / 100_000_000)M")
            }
            if ProcessInfo.processInfo.environment["CHALLENGE_TRACE"] != nil {
                FileHandle.standardError.write(Data("day \(day) \(Int(Date().timeIntervalSince(clock) * 1000)) ms trips \(world.lastDayTrips()) lines \(world.lines.count) cash \(world.economy.balance.amount / 100)\n".utf8))
            }
        }
        let world = player.world, pending = player.pending
        let state = try XCTUnwrap(world.scenario)
        // A goal met shows its day; one not met, how far it got.
        let met = zip(state.achieved, world.goalProgress(in: .english)).map { achieved, progress in
            achieved.map { "\(state.elapsedDays(through: $0))" } ?? "— (\(progress.detail))"
        }
        let result = switch state.outcome {
        case .completed(let end, let rating)?: "\(rating.displayName(in: .english)), day \(state.elapsedDays(through: end))"
        case .failed(let end, let reason)?: "failed (\(reason)), day \(state.elapsedDays(through: end))"
        case nil: "playing"
        }
        let unbuilt = pending.isEmpty ? "" : ", \(pending.count) lines never paid for"
        let column = checked.isEmpty ? "—" : checked.joined(separator: ", ")
        let row = "| \(seed) | \(play.rawValue) | " + met.joined(separator: " | ") + " | \(result)\(unbuilt) | \(column) |"
        return (row, PlayReport(label: "Seed \(seed), \(play.rawValue)", player: player))
    }
}
