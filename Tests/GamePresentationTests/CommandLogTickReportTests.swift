import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The ticks of a problem report's command log (decision 193), each timed
/// as the device ran it (派工單 BK: 92.1's real-world game of 81 stations
/// and 145 trains, whose iPhone reported the CPU too busy at 06:00). The
/// report is the player's and stays out of the repository; run on request,
/// in release to see the device's proportions:
///
///     COMMAND_LOG_TICKS=<command-log.json> swift test -c release -Xswiftc -enable-testing --filter CommandLogTickReportTests
///
/// Every `advance` entry runs a tick at a time, GameCore's step timed
/// apart from what the session does after it. `COMMAND_LOG_AFTER` is how
/// many game seconds to run on after the log's end at its last speed
/// (default 1,200, which crosses 06:00 from 05:59:57);
/// `COMMAND_LOG_SLOW` the milliseconds above which a tick is printed
/// (default 200); `COMMAND_LOG_DUMP`, when set, where the world at the
/// log's end is written, to compare two builds byte for byte.
@MainActor
final class CommandLogTickReportTests: XCTestCase {
    func testTheTicksOfACommandLog() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["COMMAND_LOG_TICKS"] else {
            throw XCTSkip("set COMMAND_LOG_TICKS=<command-log.json> to time a report's ticks")
        }
        let report = try JSONDecoder().decode(CommandLogReport.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let after = Int64(environment["COMMAND_LOG_AFTER"] ?? "") ?? 1_200
        let slow = Duration.milliseconds(Int(environment["COMMAND_LOG_SLOW"] ?? "") ?? 200)
        let game = HeadlessGame(world: report.start.world)
        let session = game.session
        session.pausesForImportantEvents = true
        try game.install(report.startData, from: CommandLogReplay.realWorld)
        let clock = ContinuousClock()
        var core = Duration.zero, total = Duration.zero, ticks = 0
        var slowest: [(Duration, String)] = []
        func tick() throws {
            let world = session.world
            let time = world.clock.now.seconds
            let spentCore = try clock.measure { _ = try GameSession.advanced(world, by: 1, listening: false) }
            let spent = clock.measure { session.advance(ticks: 1) }
            ticks += 1
            core += spentCore
            total += spent
            let day = time / GameTime.secondsPerDay + 1, second = time % GameTime.secondsPerDay
            let label = String(format: "day %lld %02lld:%02lld:%02lld", day, second / 3_600, second / 60 % 60, second % 60)
            slowest.append((spentCore, label))
            if spentCore > slow || spent - spentCore > slow {
                print("\(label): GameCore \(spentCore), session after \(spent - spentCore)")
            }
        }
        print("stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count), buses \(session.world.busRoutes.count) routes, from \(session.world.clock.now.seconds)")
        for (index, entry) in report.entries.enumerated() {
            if case .advance(let count) = entry.action {
                XCTAssertEqual(session.world.clock.now.seconds, entry.time, "entry \(index)")
                for _ in 0..<count { try tick() }
            } else if let reason = try game.step(entry, realWorld: CommandLogReplay.realWorld) {
                XCTFail("entry \(index) (\(entry.action)): \(reason)")
                return
            }
        }
        let end = CommandLogReport.Summary(session.world)
        print("end \(end == report.end ? "matches the device's" : "differs: \(end) against \(report.end)")")
        XCTAssertEqual(end, report.end)
        if let dump = environment["COMMAND_LOG_DUMP"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try encoder.encode(SavedGame(world: session.world)).write(to: URL(fileURLWithPath: dump))
        }
        if session.world.clock.isPaused { session.togglePause() }
        let until = session.world.clock.now.seconds + after
        while session.world.clock.now.seconds < until { try tick() }
        slowest.sort { $0.0 > $1.0 }
        print("ticks \(ticks), GameCore \(core), session \(total), slowest GameCore: " + slowest.prefix(12).map { "\($0.1) \($0.0)" }.joined(separator: "; "))
    }

    /// What the screen works out on the main actor once a game hour or a
    /// day at 6000× (派工單 BK, part 2), for the world of a save
    /// (`COMMAND_LOG_SAVE`, a `.alongtheline` file or a `SavedGame`):
    /// the station master's hourly look (its advice, the story, the rank)
    /// and letting go of a world copy many ticks old.
    func testWhatTheScreenWorksOutOnTheHour() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["COMMAND_LOG_SAVE"] else {
            throw XCTSkip("set COMMAND_LOG_SAVE=<save> to time what the screen works out on the hour")
        }
        struct SharedFile: Decodable { let game: SavedGame }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game) ?? JSONDecoder().decode(SavedGame.self, from: data)
        let session = GameSession(world: saved.world)
        session.setSpeed(.fast)
        let clock = ContinuousClock()
        func ms(_ duration: Duration) -> String {
            String(format: "%.1f ms", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        for round in 0..<3 {
            session.advance(ticks: 6)
            let world = session.world
            let advice = clock.measure { _ = StationMasterAdvice(world: world, worstLosingLine: { session.worstLosingLine }) }
            let rank = clock.measure { _ = CompanyRank(world: world) }
            var teller = StoryTeller()
            let story = clock.measure { _ = teller.look(at: world) }
            print("round \(round) at \(world.clock.now.seconds): StationMasterAdvice \(ms(advice)), CompanyRank \(ms(rank)), StoryTeller.look \(ms(story))")
        }
        // A copy kept while the game ran on a game day, then let go.
        var stale: GameWorld? = session.world
        session.advance(ticks: 144)
        let release = clock.measure { stale = nil }
        print("letting go of a world a day old: \(ms(release)), \(stale == nil)")
    }
}
