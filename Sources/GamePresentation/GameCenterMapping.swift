import Foundation
import GameCore

// Game Center (decision 396): what the app tells Game Center, worked out
// here so a Linux test can check it; the app only hands it to GameKit.
// Each achievement (decision 181) is a Game Center achievement of the same
// name, reported as a whole percent; the weekly challenge (decision 87) is
// a recurring leaderboard that restarts every Monday at 00:00 in Taiwan,
// as the challenge's own weeks do. The reference's disabled challenge mode
// (`Ci/`, `metroChallengeSubmitScore`) posted its `eventId`,
// `rulesVersion` and `scorePassengers` to its own server; here the week is
// the leaderboard's occurrence, the rules version picks the leaderboard,
// and the riders ride along as the score's context.

/// The names Game Center knows the game's achievements and leaderboard by,
/// and their points (``docs/GAME_CENTER_SETUP.md`` lists them for App Store
/// Connect).
public enum GameCenterMapping {
    /// The achievement's ID in App Store Connect: `achievement.<id>`.
    public static func achievementID(of achievement: Achievement) -> String {
        "achievement.\(achievement.id)"
    }

    /// The weekly leaderboard of each rules version of the challenges
    /// (``ChallengeRecords/rulesVersion``): new targets are a new
    /// leaderboard, so results under the old ones are never ranked with
    /// the new. A version missing here submits nothing.
    public static let weeklyLeaderboards: [String: String] = [
        "2026-10-goals-v2": "weekly.days.v2",
    ]

    /// The leaderboard of the challenges' current rules, if it has one.
    public static var weeklyLeaderboardID: String? {
        weeklyLeaderboards[ChallengeRecords.rulesVersion]
    }

    /// Each achievement's points, 800 of Game Center's 1,000, so marks
    /// added later still have room. The first steps are worth 5–10, the
    /// long-term goals 80.
    public static let points: [String: Int] = [
        "firstFare": 5, "riders1k": 10, "riders10k": 20, "riders100k": 40, "riders1m": 80,
        "track10": 5, "track50": 15, "track200": 30, "track1000": 80,
        "longLine": 25, "stoppingLine": 15, "earlyBird": 10, "nightOwl": 10, "ringLine": 15, "hub": 15, "highSpeed": 15,
        "fleet20": 15, "stations25": 10, "stations50": 20, "stations100": 40,
        "firstBuilding": 10, "firstFreight": 10, "firstTile": 10, "tower": 15, "typhoonSeason": 15,
        "challengeGold": 40, "pingxi": 30, "liuMingchuan": 30,
        "firstTourists": 10, "tourists100k": 25, "souvenirShop": 15, "fiveStars": 25,
        "firstSubsidiary": 10, "allBusinesses": 25, "businessProfit": 25,
        "mixedFleet": 10, "longTrain": 10, "fleetInvestment": 10,
    ]

    /// How far an achievement is, in whole percent: 100 once unlocked, and
    /// otherwise its progress rounded down and held below 100 (Game Center
    /// shows 100 as earned, which only the game's own unlock at midnight
    /// decides). A mark that is had or not, or one the game does not list
    /// for `facts`, is 0 until unlocked.
    public static func percent(of achievement: Achievement, unlocked: Bool, facts: AchievementFacts?) -> Int {
        if unlocked { return 100 }
        guard let facts, achievement.isListed(for: facts), let (now, need) = achievement.progress(of: facts), need > 0 else { return 0 }
        // now ≤ need (``Achievement/progress(of:)``), so no overflow.
        return min(99, Int(now * 100 / need))
    }
}

/// One weekly result for Game Center's leaderboard.
public struct GameCenterScore: Hashable, Sendable {
    public let leaderboardID: String
    /// The week it belongs to (``WeeklyChallenge/week``).
    public let week: Int64
    /// The days it took: the score, ranked low to high.
    public let days: Int
    /// The riders the day it was completed (the reference's
    /// `scorePassengers`), as the score's context: Game Center ranks one
    /// number, so the riders that break a tie in the game's own records
    /// are kept beside it, not ranked.
    public let riders: Int
}

/// What to tell Game Center: each achievement's percent by its Game Center
/// ID, and this week's best result, if there is one.
public struct GameCenterReport: Hashable, Sendable {
    public var achievements: [String: Int]
    public var score: GameCenterScore?

    public init(achievements: [String: Int] = [:], score: GameCenterScore? = nil) {
        self.achievements = achievements
        self.score = score
    }

    /// The report of `achievements` unlocked and, from a game, the
    /// progress of its `facts` (only of the IDs in `scope`, when there is
    /// one: decision 181's Pingxi challenge counts only its own marks), and
    /// the best result of the week containing `date`. A result of an
    /// earlier week is not sent: Game Center would rank it in this week's
    /// leaderboard.
    public init(
        achievements records: AchievementRecords, facts: AchievementFacts? = nil, scope: Set<String>? = nil,
        challenges: ChallengeRecords, at date: Date
    ) {
        var percents: [String: Int] = [:]
        for achievement in Achievement.all {
            let unlocked = records.isUnlocked(achievement)
            let counted = scope?.contains(achievement.id) != false ? facts : nil
            let percent = GameCenterMapping.percent(of: achievement, unlocked: unlocked, facts: counted)
            if percent > 0 { percents[GameCenterMapping.achievementID(of: achievement)] = percent }
        }
        achievements = percents
        let week = WeeklyChallenge(containing: date)
        if let leaderboard = GameCenterMapping.weeklyLeaderboardID, let best = challenges.best[week.scenarioID],
           best.rulesVersion == ChallengeRecords.rulesVersion {
            score = GameCenterScore(
                leaderboardID: leaderboard, week: week.week, days: Int(clamping: best.days), riders: Int(clamping: best.riders)
            )
        } else {
            score = nil
        }
    }
}

/// What has been sent to Game Center since the app started, so each report
/// sends only what changed: a percent higher than the last one sent, a
/// result better than the week's last one. Transient; Game Center itself
/// keeps the highest percent and the best score.
public struct GameCenterLedger: Sendable {
    private var sent: [String: Int] = [:]
    private var sentScore: GameCenterScore?

    public init() {}

    /// The part of `report` not sent yet, and notes it as sent.
    public mutating func changes(in report: GameCenterReport) -> GameCenterReport {
        var changes = GameCenterReport()
        for (id, percent) in report.achievements where percent > (sent[id] ?? 0) {
            changes.achievements[id] = percent
            sent[id] = percent
        }
        if let score = report.score {
            let known = sentScore.flatMap { $0.week == score.week && $0.leaderboardID == score.leaderboardID ? $0 : nil }
            if known.map({ score.days < $0.days || (score.days == $0.days && score.riders > $0.riders) }) ?? true {
                changes.score = score
                sentScore = score
            }
        }
        return changes
    }
}

/// The Game Center links' words (decision 396), beside the achievements.
public enum GameCenterText {
    public static func leaderboard(in language: DisplayLanguage) -> String {
        language.text("This week's leaderboard", "本週排行榜")
    }

    public static func achievements(in language: DisplayLanguage) -> String {
        language.text("Game Center achievements", "Game Center 成就")
    }

    public static func signIn(in language: DisplayLanguage) -> String {
        language.text("Sign in to Game Center", "登入 Game Center")
    }

    public static func footer(in language: DisplayLanguage) -> String {
        language.text(
            "Your weekly challenge days go on Game Center's weekly leaderboard, and your achievements show in Game Center.",
            "每週挑戰的完成天數會上 Game Center 的每週排行榜，成就也會出現在 Game Center。"
        )
    }
}
