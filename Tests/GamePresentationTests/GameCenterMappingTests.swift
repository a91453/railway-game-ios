import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 396: what the app tells Game Center about the achievements
/// (decision 181) and the weekly challenge (decision 87).
final class GameCenterMappingTests: XCTestCase {
    private var directory: URL!
    /// 2026-10-26 00:00 in Taiwan, a Monday.
    private let monday = Date(timeIntervalSince1970: 1_792_944_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("GameCenterMappingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEveryAchievementHasAnIDAndPointsWithinGameCentersLimits() {
        let ids = Achievement.all.map(GameCenterMapping.achievementID(of:))
        XCTAssertEqual(Set(ids).count, Achievement.all.count)
        XCTAssertEqual(ids.first, "achievement.firstFare")
        XCTAssertTrue(ids.allSatisfy { $0.count <= 100 })
        XCTAssertEqual(Set(GameCenterMapping.points.keys), Set(Achievement.all.map(\.id)), "no achievement without points, none left over")
        XCTAssertTrue(GameCenterMapping.points.values.allSatisfy { (1...100).contains($0) })
        XCTAssertEqual(GameCenterMapping.points.values.reduce(0, +), 800, "Game Center allows 1,000 in all")
        XCTAssertLessThanOrEqual(Achievement.all.count, 100)
    }

    /// A rules change (``ChallengeRecords/rulesVersion``) needs a new
    /// leaderboard, set up in App Store Connect, before it is played.
    func testTheCurrentRulesHaveAWeeklyLeaderboard() {
        XCTAssertEqual(GameCenterMapping.weeklyLeaderboardID, "weekly.days.v2")
        XCTAssertEqual(Set(GameCenterMapping.weeklyLeaderboards.values).count, GameCenterMapping.weeklyLeaderboards.count)
    }

    func testPercentIsWholeAndOnlyAnUnlockReachesAHundred() throws {
        let riders = try XCTUnwrap(Achievement.named("riders10k"))
        var facts = AchievementFacts(figures: CompanyFigures(bestDayRiders: 3_456))
        XCTAssertEqual(GameCenterMapping.percent(of: riders, unlocked: false, facts: facts), 34)
        facts.figures.bestDayRiders = 9_999
        XCTAssertEqual(GameCenterMapping.percent(of: riders, unlocked: false, facts: facts), 99)
        facts.figures.bestDayRiders = 50_000
        XCTAssertEqual(GameCenterMapping.percent(of: riders, unlocked: false, facts: facts), 99, "met, but not unlocked until midnight")
        XCTAssertEqual(GameCenterMapping.percent(of: riders, unlocked: true, facts: nil), 100)
        XCTAssertEqual(GameCenterMapping.percent(of: riders, unlocked: false, facts: nil), 0, "the start screen has no progress")
        let ring = try XCTUnwrap(Achievement.named("ringLine"))
        XCTAssertEqual(GameCenterMapping.percent(of: ring, unlocked: false, facts: facts), 0, "a mark had or not")
        // A mark the game does not list there (decision 174) shows none.
        var tourists = AchievementFacts()
        tourists.touristsInAYear = 50_000
        let season = try XCTUnwrap(Achievement.named("tourists100k"))
        XCTAssertEqual(GameCenterMapping.percent(of: season, unlocked: false, facts: tourists), 0)
        tourists.hasTourism = true
        XCTAssertEqual(GameCenterMapping.percent(of: season, unlocked: false, facts: tourists), 50)
    }

    func testAReportHasTheUnlockedTheProgressAndOnlyTheScopesMarks() {
        var records = AchievementRecords(file: directory.appendingPathComponent(AchievementRecords.fileName))
        _ = records.unlock(meeting: AchievementFacts(figures: CompanyFigures(bestDayRiders: 1)), at: monday)
        let challenges = ChallengeRecords(file: directory.appendingPathComponent("challenge-records.data"))
        let facts = AchievementFacts(figures: CompanyFigures(bestDayRiders: 500, stations: 5))

        let report = GameCenterReport(achievements: records, facts: facts, challenges: challenges, at: monday)
        XCTAssertEqual(report.achievements, [
            "achievement.firstFare": 100, "achievement.riders1k": 50, "achievement.riders10k": 5,
            "achievement.stations25": 20, "achievement.stations50": 10, "achievement.stations100": 5,
        ])
        XCTAssertNil(report.score)
        // The Pingxi challenge's own marks only (decision 181): the
        // demo's lines are not the player's.
        let pingxi = GameCenterReport(achievements: records, facts: facts, scope: ["challengeGold", "pingxi"], challenges: challenges, at: monday)
        XCTAssertEqual(pingxi.achievements, ["achievement.firstFare": 100])
        XCTAssertEqual(GameCenterReport(achievements: records, challenges: challenges, at: monday).achievements, ["achievement.firstFare": 100])
    }

    func testOnlyThisWeeksBestGoesOnTheLeaderboard() throws {
        let week = WeeklyChallenge(containing: monday)
        let file = directory.appendingPathComponent("challenge-records.data")
        let stored = [
            week.scenarioID: ChallengeRecord(days: 34, rating: .gold, riders: 120_000, date: monday),
            "weekly.\(week.week - 1)": ChallengeRecord(days: 20, rating: .gold, riders: 90_000, date: monday),
            "sandbox.threeTowns": ChallengeRecord(days: 10, rating: .gold, riders: 1, date: monday),
        ]
        try JSONEncoder().encode(stored).write(to: file)
        let challenges = ChallengeRecords(file: file)
        let records = AchievementRecords(file: directory.appendingPathComponent(AchievementRecords.fileName))

        let report = GameCenterReport(achievements: records, challenges: challenges, at: monday.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(report.score, GameCenterScore(leaderboardID: "weekly.days.v2", week: week.week, days: 34, riders: 120_000))
        // Next Monday, last week's result is not this week's.
        XCTAssertNil(GameCenterReport(achievements: records, challenges: challenges, at: week.end).score)
    }

    func testTheLedgerSendsOnlyWhatChanged() {
        var ledger = GameCenterLedger()
        let score = GameCenterScore(leaderboardID: "weekly.days.v2", week: 3_000, days: 40, riders: 100)
        let first = GameCenterReport(achievements: ["a": 30, "b": 100], score: score)
        XCTAssertEqual(ledger.changes(in: first), first)
        XCTAssertEqual(ledger.changes(in: first), GameCenterReport(), "nothing new")
        // A higher percent, a lower one, and a better result.
        let better = GameCenterScore(leaderboardID: "weekly.days.v2", week: 3_000, days: 40, riders: 200)
        XCTAssertEqual(
            ledger.changes(in: GameCenterReport(achievements: ["a": 31, "b": 100, "c": 0], score: better)),
            GameCenterReport(achievements: ["a": 31], score: better)
        )
        let worse = GameCenterScore(leaderboardID: "weekly.days.v2", week: 3_000, days: 41, riders: 900)
        XCTAssertEqual(ledger.changes(in: GameCenterReport(score: worse)), GameCenterReport())
        // A new week starts over.
        let nextWeek = GameCenterScore(leaderboardID: "weekly.days.v2", week: 3_001, days: 60, riders: 1)
        XCTAssertEqual(ledger.changes(in: GameCenterReport(score: nextWeek)).score, nextWeek)
    }

    /// The setup steps the owner follows in App Store Connect list every
    /// achievement with its ID and points, and the leaderboard.
    func testTheSetupStepsListEveryAchievement() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("docs/GAME_CENTER_SETUP.md"), encoding: .utf8)
        for achievement in Achievement.all {
            let id = GameCenterMapping.achievementID(of: achievement)
            let points = try XCTUnwrap(GameCenterMapping.points[achievement.id])
            XCTAssertTrue(text.contains("| `\(id)` | \(points) |"), "\(id) with \(points) points")
        }
        XCTAssertTrue(text.contains("`\(try XCTUnwrap(GameCenterMapping.weeklyLeaderboardID))`"))
    }

    func testTheLinksWordsInBothLanguages() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            for text in [GameCenterText.leaderboard, GameCenterText.achievements, GameCenterText.signIn, GameCenterText.footer] {
                XCTAssertFalse(text(language).isEmpty)
            }
        }
        XCTAssertEqual(GameCenterText.leaderboard(in: .traditionalChinese), "本週排行榜")
    }
}
