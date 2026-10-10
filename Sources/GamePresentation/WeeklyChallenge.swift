import Foundation
import GameCore

// The weekly challenge and the player's best results (decision 87): every
// player gets the same map each week, so finishing times can be compared,
// first with themselves here, later on Game Center's weekly leaderboard.
// The week and its seed come from the device's clock in Taiwan time, when
// a game starts; the game itself is the deterministic scenario GameCore
// plays (decision 86), which never reads a clock. Weekly maps are native;
// a result's fields follow the `Ci/` reference's disabled challenge mode
// (`metroChallengeLeaderboardPayload`: `eventId`, `rulesVersion`,
// `scorePassengers`), so a leaderboard later can take them as they are.

/// The week a weekly challenge belongs to: weeks start on Monday at 00:00
/// in Taiwan (UTC+8), counted from the one that began on 5 January 1970.
public struct WeeklyChallenge: Hashable, Sendable {
    public let week: Int64

    public init(week: Int64) {
        self.week = week
    }

    /// The week containing `date`.
    public init(containing date: Date) {
        let seconds = Int64(date.timeIntervalSince1970.rounded(.down)) + Self.taiwanOffset - Self.firstMonday
        week = seconds >= 0 ? seconds / Self.secondsPerWeek : (seconds + 1) / Self.secondsPerWeek - 1
    }

    static let secondsPerWeek: Int64 = 7 * 86_400
    /// Taiwan time is UTC+8, all year.
    static let taiwanOffset: Int64 = 8 * 3_600
    /// 1970-01-05, a Monday, in seconds since the epoch.
    static let firstMonday: Int64 = 4 * 86_400

    /// When the week starts and ends, as instants.
    public var start: Date {
        Date(timeIntervalSince1970: TimeInterval(week * Self.secondsPerWeek + Self.firstMonday - Self.taiwanOffset))
    }

    public var end: Date {
        Date(timeIntervalSince1970: TimeInterval((week + 1) * Self.secondsPerWeek + Self.firstMonday - Self.taiwanOffset))
    }

    /// The towns' seed: an FNV-1a hash of the week, so that every player's
    /// map that week is the same and next week's is new.
    public var seed: UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in "weekly.\(week)".utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// The scenario's ID in a save: `"weekly.<week>"`.
    public var scenarioID: String {
        "weekly.\(week)"
    }

    /// The week's challenge: link the three towns of its map and carry their
    /// people, rated by the days it took.
    public var challenge: Challenge {
        let base = Challenge.threeTowns
        let id = scenarioID
        let range = rangeText
        return Challenge(
            id: id,
            titles: ("Weekly Challenge · \(range)", "每週挑戰 · \(range)"),
            stories: (
                "Everyone gets this map this week. \(base.story(in: .english)) The fewer days it takes, the better.",
                "這週所有人玩同一張地圖。\(base.story(in: .traditionalChinese))完成的天數越少越好。"
            ),
            rules: { seed, bounds in
                let rules = base.scenario(seed: seed, in: bounds)
                return Scenario(
                    id: id, goals: rules.goals, goldDays: rules.goldDays, silverDays: rules.silverDays, deadlineDays: rules.deadlineDays,
                    insolvencyDays: rules.insolvencyDays, trainTypes: rules.trainTypes
                )
            }
        )
    }

    /// The week's days in Taiwan, such as "10/5–10/11".
    public var rangeText: String {
        let first = Self.monthAndDay(of: start)
        let last = Self.monthAndDay(of: end.addingTimeInterval(-1))
        return "\(first)–\(last)"
    }

    private static func monthAndDay(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: Int(taiwanOffset))!
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    /// The days left in the week from `date`, counting today: 7 on Monday,
    /// 1 on Sunday.
    public func daysLeft(from date: Date) -> Int {
        let left = end.timeIntervalSince(date)
        return max(0, Int((left / 86_400).rounded(.up)))
    }

    /// The weekly challenge a scenario ID names, if it names one.
    static func named(_ id: String) -> WeeklyChallenge? {
        guard id.hasPrefix("weekly."), let week = Int64(id.dropFirst("weekly.".count)) else { return nil }
        return WeeklyChallenge(week: week)
    }
}

extension GameWorld {
    /// A new game on the week's map with its challenge.
    public static func newGame(weekly: WeeklyChallenge) -> GameWorld {
        newGame(challenge: weekly.challenge, eventSeed: weekly.seed)
    }
}

// MARK: - Best results

/// The player's best result in each challenge (decision 87): the fewest
/// days, and of as few, the most riders the day it was completed (the
/// reference's `scorePassengers`). Kept on the device, beside the saves;
/// never sent anywhere.
public struct ChallengeRecord: Hashable, Codable, Sendable {
    public let days: Int64
    public let rating: ScenarioRating
    /// Passengers who paid a fare the day it was completed.
    public let riders: Int64
    /// The rules it was played under (the reference's `rulesVersion`): a
    /// result under other targets is not compared.
    public let rulesVersion: String
    /// When it was set, by the device's clock.
    public let date: Date

    public init(days: Int64, rating: ScenarioRating, riders: Int64, rulesVersion: String = ChallengeRecords.rulesVersion, date: Date) {
        self.days = days
        self.rating = rating
        self.riders = riders
        self.rulesVersion = rulesVersion
        self.date = date
    }

    /// Whether it beats `other`: fewer days, or as few and more riders.
    func isBetter(than other: ChallengeRecord) -> Bool {
        days < other.days || (days == other.days && riders > other.riders)
    }

    /// "Best: 34 days, gold".
    public func text(in language: DisplayLanguage) -> String {
        language.text("Best: \(days) days, \(rating.displayName(in: language))", "最佳紀錄：\(days) 天，\(rating.displayName(in: language))")
    }
}

/// The best results, by scenario ID, in a file. A file that cannot be read
/// counts as no results; one that cannot be written loses only the newest.
public struct ChallengeRecords: Sendable {
    /// The challenges' rules now: a new version when their targets change,
    /// so older results are set aside.
    public static let rulesVersion = "2026-10-goals-v1"

    public let file: URL
    /// The best results under the current rules, by scenario ID.
    public private(set) var best: [String: ChallengeRecord]

    public init(file: URL) {
        self.file = file
        let read = (try? JSONDecoder().decode([String: ChallengeRecord].self, from: Data(contentsOf: file))) ?? [:]
        best = read.filter { $0.value.rulesVersion == Self.rulesVersion }
    }

    /// Keeps `world`'s scenario's result if it was completed in fewer days
    /// than the best so far, and writes the file. Returns whether it is a
    /// new best.
    @discardableResult
    public mutating func record(_ world: GameWorld, at date: Date = Date()) -> Bool {
        guard let state = world.scenario, case .completed(let day, let rating)? = state.outcome else { return false }
        // The riders of the day it was completed, not of the day before
        // this autosave: the game plays on after the scenario ends.
        let riders = world.accounts.days.first { $0.day == day }?.fareTrips ?? 0
        let result = ChallengeRecord(days: state.elapsedDays(through: day), rating: rating, riders: riders, date: date)
        if let known = best[state.scenario.id], !result.isBetter(than: known) { return false }
        best[state.scenario.id] = result
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(best).write(to: file, options: .atomic)
        return true
    }
}
