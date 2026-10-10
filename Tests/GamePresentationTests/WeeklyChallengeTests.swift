import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 87: the weekly challenge's week in Taiwan time, its shared map,
/// and the player's best results.
final class WeeklyChallengeTests: XCTestCase {
    /// 2026-10-05 00:00 in Taiwan, a Monday: 2026-10-04 16:00 UTC.
    private let monday = Date(timeIntervalSince1970: 1_791_129_600)

    func testWeeksStartOnMondayAtMidnightInTaiwan() {
        let week = WeeklyChallenge(containing: monday)
        XCTAssertEqual(week.start, monday)
        XCTAssertEqual(week.end, monday.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(WeeklyChallenge(containing: monday.addingTimeInterval(-1)).week, week.week - 1, "Sunday 23:59:59 is last week")
        XCTAssertEqual(WeeklyChallenge(containing: monday.addingTimeInterval(7 * 86_400 - 1)).week, week.week)
        XCTAssertEqual(week.rangeText, "10/5–10/11")
        XCTAssertEqual(week.daysLeft(from: monday), 7)
        XCTAssertEqual(week.daysLeft(from: monday.addingTimeInterval(6 * 86_400 + 3_600)), 1)
        XCTAssertEqual(WeeklyChallenge(containing: Date(timeIntervalSince1970: 4 * 86_400 - 8 * 3_600)).week, 0, "the first Monday")
        XCTAssertEqual(WeeklyChallenge(containing: Date(timeIntervalSince1970: 0)).week, -1)
    }

    func testEveryPlayerGetsTheSameMapInAWeekAndANewOneNextWeek() throws {
        let week = WeeklyChallenge(containing: monday)
        let first = GameWorld.newGame(weekly: week)
        let second = GameWorld.newGame(weekly: WeeklyChallenge(containing: monday.addingTimeInterval(3 * 86_400)))
        XCTAssertEqual(first.land, second.land)
        XCTAssertEqual(first.scenario, second.scenario)
        let next = GameWorld.newGame(weekly: WeeklyChallenge(week: week.week + 1))
        XCTAssertNotEqual(next.land, first.land)
        XCTAssertNotEqual(week.seed, WeeklyChallenge(week: week.week + 1).seed)

        XCTAssertEqual(first.scenario?.scenario.id, "weekly.\(week.week)")
        XCTAssertEqual(first.scenarioTitle(in: .traditionalChinese), "每週挑戰 · 三鎮連線 · 10/5–10/11")
        XCTAssertEqual(Challenge.named("weekly.\(week.week)")?.id, week.scenarioID)
        XCTAssertNil(Challenge.named("weekly.x"))
        // The week's goals are the three towns' on its own map.
        guard case .connect(let points, _)? = first.scenario?.scenario.goals.first else { return XCTFail("links the towns") }
        XCTAssertEqual(points, Land.townCentres(seed: week.seed, in: first.bounds))
    }

    /// Decision 145: from the week of 12 October 2026 the weeks take the
    /// sandbox challenges in turn; every week before it was Three Towns.
    func testTheWeeksTakeTheSandboxChallengesInTurn() throws {
        let rotating = WeeklyChallenge(containing: monday.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(rotating.week, WeeklyChallenge.firstRotatingWeek)
        XCTAssertEqual(WeeklyChallenge(containing: monday).base, Challenge.threeTowns)
        XCTAssertEqual(WeeklyChallenge(week: rotating.week - 5).base, Challenge.threeTowns)
        let turns = (0..<6).map { WeeklyChallenge(week: rotating.week + $0).base.id }
        XCTAssertEqual(turns, (Challenge.sandbox + Challenge.sandbox).map(\.id))

        // The week plays its challenge's goals and days on its own map,
        // under its own ID, and says which challenge it is.
        let week = WeeklyChallenge(week: rotating.week + 2)
        let world = GameWorld.newGame(weekly: week)
        let rules = try XCTUnwrap(world.scenario?.scenario)
        let tycoon = Challenge.tycoon.scenario(seed: week.seed, in: world.bounds)
        XCTAssertEqual(rules.id, "weekly.\(week.week)")
        XCTAssertEqual(rules.goals, tycoon.goals)
        XCTAssertEqual([rules.goldDays, rules.silverDays, rules.deadlineDays], [tycoon.goldDays, tycoon.silverDays, tycoon.deadlineDays])
        XCTAssertEqual(world.scenarioTitle(in: .traditionalChinese), "每週挑戰 · 鐵道大亨 · 10/26–11/1")
        XCTAssertTrue(week.challenge.story(in: .traditionalChinese).contains(Challenge.tycoon.story(in: .traditionalChinese)))
    }

    func testOnlyABetterResultIsKept() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("records-\(UUID().uuidString).data")
        defer { try? FileManager.default.removeItem(at: file) }
        var records = ChallengeRecords(file: file)
        XCTAssertTrue(records.best.isEmpty)

        func completed(onDay day: Int64) throws -> GameWorld {
            var world = try GameWorld(
                bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000), clock: GameClock(speed: .normal)
            )
            world.setEconomyMode(.management)
            try world.startScenario(Scenario(id: "weekly.1", goals: [.equity(Money(1))], goldDays: 1, silverDays: 5, deadlineDays: 9))
            try world.advance(ticks: Int(day) * 1_440 + 1)
            return world
        }
        // Equity is met at the first midnight: day 1, gold.
        let fast = try completed(onDay: 1)
        XCTAssertFalse(records.record(try GameWorld(bounds: WorldBounds(width: 1_024, height: 1_024), economy: GameEconomy(balance: 0))))
        XCTAssertTrue(records.record(fast, at: monday))
        XCTAssertEqual(records.best["weekly.1"], ChallengeRecord(days: 1, rating: .gold, riders: 0, date: monday))
        // As few days with more riders beats it; a result under other rules
        // is set aside when read.
        XCTAssertTrue(ChallengeRecord(days: 1, rating: .gold, riders: 5, date: monday).isBetter(than: records.best["weekly.1"]!))
        XCTAssertFalse(ChallengeRecord(days: 2, rating: .gold, riders: 9, date: monday).isBetter(than: records.best["weekly.1"]!))
        let old = try JSONEncoder().encode(["weekly.9": ChallengeRecord(days: 3, rating: .gold, riders: 0, rulesVersion: "old", date: monday)])
        let oldFile = file.appendingPathExtension("old")
        defer { try? FileManager.default.removeItem(at: oldFile) }
        try old.write(to: oldFile)
        XCTAssertTrue(ChallengeRecords(file: oldFile).best.isEmpty)
        XCTAssertFalse(records.record(fast, at: monday), "not better than itself")
        XCTAssertEqual(ChallengeRecords(file: file).best, records.best, "kept in the file")
        XCTAssertEqual(records.best["weekly.1"]?.text(in: .traditionalChinese), "最佳紀錄：1 天，金牌")
    }

    /// A result is the day it was completed on: later days, with more
    /// riders, while the game plays on, do not make it a new best again.
    func testAResultKeepsTheRidersOfItsDay() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("records-\(UUID().uuidString).data")
        defer { try? FileManager.default.removeItem(at: file) }
        var records = ChallengeRecords(file: file)
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000), clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        try world.startScenario(Scenario(id: "weekly.1", goals: [.equity(Money(1))], goldDays: 1, silverDays: 5, deadlineDays: 9))
        try world.advance(ticks: 1_441)
        guard case .completed(let day, _)? = world.scenario?.outcome else { return XCTFail("completed at the first midnight") }
        var completion = DayAccount(day: day)
        completion.fareTrips = 3
        world.accounts.days = [completion]
        XCTAssertTrue(records.record(world, at: monday))
        XCTAssertEqual(records.best["weekly.1"]?.riders, 3)
        // Played on: the next day carries more riders.
        try world.advance(ticks: 1_440)
        var later = DayAccount(day: day + 1)
        later.fareTrips = 50
        world.accounts.days = [completion, later]
        XCTAssertFalse(records.record(world, at: monday), "the same result, not a new best")
        XCTAssertEqual(records.best["weekly.1"]?.riders, 3)
    }

    /// The launcher starts the week's map, and keeps a best result the
    /// moment it is made, in its saves' folder but not as a save.
    @MainActor
    func testTheLauncherStartsTheWeekAndKeepsTheBest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Weekly-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .traditionalChinese)
        launcher.startWeeklyChallenge(at: monday)
        let session = try XCTUnwrap(launcher.session)
        XCTAssertEqual(session.world, GameWorld.newGame(weekly: WeeklyChallenge(containing: monday)))
        launcher.recordChallengeResult(at: monday)
        XCTAssertTrue(launcher.records.best.isEmpty, "not completed yet")
        XCTAssertTrue(launcher.autosaveCurrentGame(at: monday))
        XCTAssertEqual(library.entries().count, 1, "the records file is not a save")
        XCTAssertEqual(launcher.records.file.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    }
}
