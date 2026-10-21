import GameCore

// How riders find a line (ARCHITECTURE decision 301; the City Transport
// Manager study's 4.13 and its M3 step): three scores out of 100 on the
// line card, each read from a figure the line accounts already keep over
// the report's settled days (decision 194's ``LineLossMeasures``):
//
// - waiting, estimated from the minutes between its trains each way (a
//   rider turning up at random waits half of it);
// - crowding, from the fullest departure of a day, on average;
// - punctuality, from the trips on time (decision 207, realistic
//   operation only).
//
// Too few departures, riders or trips to go on, and an item says it is not
// rated yet rather than show a score no figure stands behind. Only shown:
// it changes no demand and no money. The weakest item below good gets the
// change that answers it, decision 194's one-tap "run more trains".
//
// The reference has nothing to port: its line panels show loads and
// delays but no rating (decision 301's table). The thresholds are this
// project's own.

/// Three ratings of a line, as its riders would find it (decision 301).
public struct LineSatisfaction: Hashable, Sendable {
    /// What is rated.
    public enum Aspect: String, CaseIterable, Hashable, Sendable {
        case waiting, crowding, punctuality

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .waiting: language.text("Waiting", "候車")
            case .crowding: language.text("Room on board", "車上空間")
            case .punctuality: language.text("On time", "準點")
            }
        }
    }

    /// A score's band: the face drawn beside it.
    public enum Grade: String, CaseIterable, Hashable, Sendable {
        case good, fair, poor

        /// The band of `score` out of 100.
        public init(score: Int64) {
            self = score >= LineSatisfaction.goodScore ? .good : score < LineSatisfaction.poorScore ? .poor : .fair
        }

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .good: language.text("Good", "好")
            case .fair: language.text("Fair", "普通")
            case .poor: language.text("Poor", "差")
            }
        }
    }

    /// One rated aspect: its score and the figure it comes from, or why it
    /// has none yet.
    public struct Item: Hashable, Identifiable, Sendable {
        public enum Rating: Hashable, Sendable {
            /// `score` out of 100, from `figure`: minutes between trains,
            /// or thousandths full or on time.
            case rated(score: Int64, figure: Int64)
            /// Too few departures, riders or trips over the days.
            case tooFew
            /// Punctuality without realistic operation, which counts no
            /// trips (decision 207).
            case notCounted
        }

        public let aspect: Aspect
        public let rating: Rating

        public var id: Aspect { aspect }

        public var score: Int64? {
            if case .rated(let score, _) = rating { return score }
            return nil
        }

        public var grade: Grade? { score.map(Grade.init(score:)) }

        /// "Waiting", what the row is called.
        public func title(in language: DisplayLanguage) -> String {
            aspect.title(in: language)
        }

        /// "83%", or "Not rated yet".
        public func scoreText(in language: DisplayLanguage) -> String {
            score.map { "\($0)%" } ?? language.text("Not rated yet", "尚未評分")
        }

        /// The figure the score comes from, or why there is none, in a
        /// sentence.
        public func detail(in language: DisplayLanguage) -> String {
            switch (aspect, rating) {
            case let (.waiting, .rated(_, headway)):
                let wait = headway % 2 == 0 ? "\(headway / 2)" : "\(headway / 2).5"
                return language.text(
                    "About \(wait) min on average, estimated from a train every \(headway) min",
                    "平均約 \(wait) 分，由每 \(headway) 分一班估算"
                )
            case let (.crowding, .rated(_, permille)):
                return language.text(
                    "The fullest train of a day leaves \(LineLossDiagnosis.percentText(permille, in: language)) full on average",
                    "每天最擠的一班平均坐滿 \(LineLossDiagnosis.percentText(permille, in: language))"
                )
            case let (.punctuality, .rated(_, permille)):
                let minutes = GameWorld.punctualSeconds / 60
                return language.text(
                    "\(permille / 10)% of trips no more than \(minutes) min late",
                    "\(permille / 10)% 的車次誤點不超過 \(minutes) 分鐘"
                )
            case (.punctuality, .notCounted):
                return language.text("Counted only with realistic operation on.", "開啟寫實運轉才會計算。")
            case (.waiting, _):
                return language.text("Too few trains have run yet.", "開出的班次還太少。")
            case (.crowding, _):
                return language.text("Too few riders yet.", "搭車的人還太少。")
            case (.punctuality, _):
                return language.text("Too few trips have finished yet.", "跑完的車次還太少。")
            }
        }

        /// What the player can do about a low score, or `nil` for a good
        /// one or one not rated.
        public func advice(in language: DisplayLanguage) -> String? {
            guard let grade, grade != .good else { return nil }
            switch aspect {
            case .waiting:
                return language.text("Run trains more often to cut the wait.", "班距縮短，候車就短。")
            case .crowding:
                return language.text("Run more trains, or longer ones.", "加開列車，或改用長一點的列車。")
            case .punctuality:
                return language.text(
                    "Trains running late often wait for each other: add passing loops or a second track, or run them less often.",
                    "誤點多半是列車互相等候：加交會、待避線或複線，或拉長班距。"
                )
            }
        }

        /// "Waiting 83%, Good: About 7.5 min…", what VoiceOver reads.
        public func spokenText(in language: DisplayLanguage) -> String {
            let band = grade.map { ", \($0.title(in: language))" } ?? ""
            return "\(title(in: language)) \(scoreText(in: language))\(band): \(detail(in: language))"
        }
    }

    public let line: LineID
    /// The settled days the items read; 0 before the first.
    public let days: Int
    /// Waiting, crowding and punctuality, in that order; empty before a
    /// settled day.
    public let items: [Item]

    // MARK: Thresholds (decision 301)

    /// A score this high or more is good (a green face)...
    public static let goodScore: Int64 = 70
    /// ...and under this, poor (a red one).
    public static let poorScore: Int64 = 45
    /// Waiting: full marks with a train every this many minutes or less
    /// (about 3 min on the platform)...
    public static let bestHeadway: Int64 = 6
    /// ...none with a train every this many or more (18 min); straight
    /// between. A train every 15 minutes is just good, every 20 fair
    /// (decision 194 calls trains 20 minutes apart too far apart when
    /// they are full), every 30 poor.
    public static let worstHeadway: Int64 = 36
    /// Crowding: full marks with the fullest train of a day this full or
    /// less, in thousandths of its rated room...
    public static let roomyPermille: Int64 = 600
    /// ...none this full or more (a train takes at most 1.1 times its
    /// rated room); straight between. 75% full is just good, 90% (decision
    /// 194's crowded) poor.
    public static let packedPermille: Int64 = 1_100
    /// Punctuality: none at this share of trips on time or less, in
    /// thousandths...
    public static let worstOnTimePermille: Int64 = 800
    /// ...full marks at this share or more; straight between. 93% on time
    /// is just good, under 88% poor.
    public static let bestOnTimePermille: Int64 = 980
    /// Too few to rate: fewer departures than this over the days...
    public static let minimumDepartures: Int64 = 12
    /// ...fewer boardings...
    public static let minimumBoardings: Int64 = 100
    /// ...or fewer finished trips.
    public static let minimumTrips: Int64 = 10

    public init(line: LineID, days: Int, items: [Item]) {
        self.line = line
        self.days = days
        self.items = items
    }

    /// The three items from `measures`, over `days` settled days;
    /// `counted` says whether the world counts trips (realistic
    /// operation, decision 207).
    public init(line: LineID, days: Int, measures: LineLossMeasures, countsTrips: Bool) {
        let ran = measures.departures >= Self.minimumDepartures
        let waiting: Item.Rating = if ran, let headway = measures.headwayMinutes {
            .rated(score: Self.waitingScore(headway: headway), figure: headway)
        } else {
            .tooFew
        }
        let crowding: Item.Rating = ran && measures.boardings >= Self.minimumBoardings
            ? .rated(score: Self.crowdingScore(peakPermille: measures.meanPeakPermille), figure: measures.meanPeakPermille)
            : .tooFew
        let punctuality: Item.Rating = if measures.trips >= Self.minimumTrips, let onTime = measures.punctualityPermille {
            .rated(score: Self.punctualityScore(onTimePermille: onTime), figure: onTime)
        } else {
            countsTrips ? .tooFew : .notCounted
        }
        self.init(line: line, days: days, items: [
            Item(aspect: .waiting, rating: waiting),
            Item(aspect: .crowding, rating: crowding),
            Item(aspect: .punctuality, rating: punctuality),
        ])
    }

    /// Waiting's score for a train every `headway` minutes.
    public static func waitingScore(headway: Int64) -> Int64 {
        straight(headway, from: bestHeadway, to: worstHeadway)
    }

    /// Crowding's score with the fullest train of a day `peakPermille`
    /// thousandths full.
    public static func crowdingScore(peakPermille: Int64) -> Int64 {
        straight(peakPermille, from: roomyPermille, to: packedPermille)
    }

    /// Punctuality's score with `onTimePermille` thousandths of the trips
    /// on time.
    public static func punctualityScore(onTimePermille: Int64) -> Int64 {
        100 - straight(onTimePermille, from: worstOnTimePermille, to: bestOnTimePermille)
    }

    /// 100 at `best` or less, 0 at `worst` or more, straight between,
    /// rounded down.
    private static func straight(_ value: Int64, from best: Int64, to worst: Int64) -> Int64 {
        guard value > best else { return 100 }
        guard value < worst else { return 0 }
        return (worst - value) * 100 / (worst - best)
    }

    /// Whether any item has a score.
    public var isRated: Bool { items.contains { $0.score != nil } }

    /// The lowest-scored item that is not good (the first in order on a
    /// tie), or `nil`: the one the card offers a fix beside.
    public var weakest: Item? {
        items.filter { ($0.grade ?? .good) != .good }.min { ($0.score ?? 0) < ($1.score ?? 0) }
    }

    /// "Riders' view, last 3 days", or before a settled day, what it
    /// waits for.
    public func spanText(in language: DisplayLanguage) -> String {
        guard days > 0 else {
            return language.text("Riders' view: not rated yet", "乘客感受：尚未評分")
        }
        return language.text("Riders' view, last \(days) \(days == 1 ? "day" : "days")", "乘客感受（最近 \(days) 天）")
    }

    /// What a line without a settled day says, or `nil`.
    public func waitingText(in language: DisplayLanguage) -> String? {
        guard days == 0 else { return nil }
        return language.text(
            "Scores come after the line's first full day of running.",
            "這條線營運滿一天之後才有分數。"
        )
    }
}

extension LineSatisfaction.Aspect {
    /// The one-tap change decision 194 makes for it, when there is one:
    /// more trains, or trains closer together, answer both waiting and
    /// crowding; punctuality has none.
    public var fixKind: LineLossReason.Kind? {
        switch self {
        case .waiting, .crowding: .longHeadway
        case .punctuality: nil
        }
    }
}

extension GameWorld {
    /// How riders find line `id` (decision 301), over the same settled days
    /// as its diagnosis (``lineLossDiagnosis(_:)``); not rated before the
    /// first. `nil` where the line card has no diagnosis to show at all:
    /// no such line, a freight line, or no line accounts.
    public func lineSatisfaction(_ id: LineID) -> LineSatisfaction? {
        guard let line = line(id: id), !line.isFreight, lineReport(id) != nil else { return nil }
        guard let diagnosis = lineLossDiagnosis(id) else {
            return LineSatisfaction(line: id, days: 0, items: [])
        }
        return LineSatisfaction(line: id, days: diagnosis.days, measures: diagnosis.measures, countsTrips: realisticOperation)
    }
}

/// Keeps the selected line's satisfaction and the fix beside its weakest
/// item for the line panel, worked out again only for a new
/// ``GameSession/commandRevision``, line or settled day, as
/// ``LineLossMemo``. Not game state.
@MainActor
public final class LineSatisfactionMemo {
    private struct Key: Equatable {
        let session: ObjectIdentifier
        let revision: Int
        let line: LineID
        let day: Int64
    }

    private var key: Key?
    private var kept: LineSatisfaction?
    private var keptFix: LineLossFix?
    /// How many times it has worked the line out (for the tests).
    private(set) var workedOut = 0

    public init() {}

    /// ``GameWorld/lineSatisfaction(_:)`` of `session`'s world.
    public func satisfaction(_ id: LineID, of session: GameSession) -> LineSatisfaction? {
        let world = session.world
        let now = Key(session: ObjectIdentifier(session), revision: session.commandRevision, line: id,
                      day: world.lineLossSettledDay)
        guard now != key else { return kept }
        key = now
        kept = world.lineSatisfaction(id)
        keptFix = kept?.weakest?.aspect.fixKind.flatMap { world.lineLossFix($0, on: id) }
        workedOut += 1
        return kept
    }

    /// The change beside the weakest item (decision 194's
    /// ``LineLossFix``), worked out with it, or `nil`.
    public func fix(_ id: LineID, of session: GameSession) -> LineLossFix? {
        _ = satisfaction(id, of: session)
        return keptFix
    }
}
