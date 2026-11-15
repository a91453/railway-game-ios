import Foundation
import GameCore

// Decision 788: the winter event's frame (docs/research/WINTER_EVENT_2026-11-15.md
// §2.1 and §2.4). From 1 December to 6 January by the device's own date, a
// mission a week that reads only the player's network, a badge for each and
// the Christmas livery for the fourth. Nothing here is game state: the
// badges are a file beside the saves, like the achievements, the season is
// the device's calendar, not the game's (whose months are 30 days and
// differ in every save), and GameCore is untouched, so no save, golden
// value or replay moves.

/// The winter event's calendar: which week, if any, a date of the device
/// falls in.
public enum WinterEvent {
    /// Where a date stands in the event.
    public enum Phase: Hashable, Sendable {
        /// Outside 1 December to 6 January.
        case off
        /// One of the five weeks, 1 to 5.
        case week(Int)
        /// 5 and 6 January: no mission, the badges shown.
        case wrapUp
    }

    /// The first day of each week, as day of December (week 5 runs into
    /// January), and the last day of the event, 6 January.
    static let weekStarts = [1, 8, 15, 22, 29]
    static let lastJanuaryDay = 6
    /// The last week: 29 December to 4 January.
    public static let weeks = 5

    /// The key of the settings' "Festive decorations" switch, on by
    /// default: off, the map is drawn as on any other day.
    public static let decorationsKey = "event.festiveDecorations"

    /// The calendar a date is read in: Gregorian, in the device's time
    /// zone, so the week turns at the player's own midnight.
    public static func calendar(in timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The season `date` belongs to, named by the year of its December
    /// (6 January 2027 is the 2026 season's), and its phase; the season is
    /// `nil` when the phase is off.
    public static func phase(at date: Date, calendar: Calendar = calendar()) -> (season: Int?, phase: Phase) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return (nil, .off) }
        if month == 12 {
            let week = weekStarts.lastIndex { $0 <= day }.map { $0 + 1 } ?? 1
            return (year, .week(week))
        }
        if month == 1 {
            if day <= 4 { return (year - 1, .week(weeks)) }
            if day <= lastJanuaryDay { return (year - 1, .wrapUp) }
        }
        return (nil, .off)
    }

    /// Whether the event is on at `date`.
    public static func isOn(at date: Date, calendar: Calendar = calendar()) -> Bool {
        phase(at: date, calendar: calendar).phase != .off
    }

    /// Whether the map wears the event's decorations at `date`: during the
    /// event, unless the player switched them off.
    public static func showsDecorations(at date: Date, switchedOn: Bool, calendar: Calendar = calendar()) -> Bool {
        switchedOn && isOn(at: date, calendar: calendar)
    }

    /// The mission of the week `date` falls in, if any.
    public static func mission(at date: Date, calendar: Calendar = calendar()) -> WinterMission? {
        guard case .week(let week) = phase(at: date, calendar: calendar).phase else { return nil }
        return WinterMission.of(week: week)
    }

    /// The dates of a week in the player's language ("12/1–12/7").
    public static func datesText(ofWeek week: Int) -> String {
        guard (1...weeks).contains(week) else { return "" }
        let start = weekStarts[week - 1]
        let end = week == weeks ? "1/4" : "12/\(weekStarts[week] - 1)"
        return "12/\(start)–\(end)"
    }

    /// The event's dates, both languages alike.
    public static let periodText = "12/1–1/6"
}

/// What a week's mission reads from a world: only its network and its
/// riders, never its date (decision 788). Read at midnight and when the
/// event card opens.
public struct WinterMissionFacts: Hashable, Sendable {
    /// The stations a running passenger line calls at after 18:00.
    public var stationsLitAtNight = 0
    /// Whether a running passenger line runs from 17:00 to 22:00 with at
    /// least ``WinterMission/marketTrains`` trains.
    public var hasEveningMarketLine = false
    /// The riders of the day just ended.
    public var yesterdayRiders: Int64 = 0
    /// Whether a running passenger line wears the Christmas livery.
    public var hasLiveriedLineRunning = false
    /// Whether a running passenger line runs past midnight.
    public var hasLineAfterMidnight = false

    public init() {}

    /// Reads `world`; `liveried` are the lines the player put the
    /// Christmas livery on (kept on the device, not in the save).
    public init(world: GameWorld, liveried: Set<LineID> = []) {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        yesterdayRiders = world.accounts.days.first { $0.day == today - 1 }?.fareTrips ?? 0
        var lit: Set<StationID> = []
        for line in world.lines where !line.isFreight && !line.assignedTrains.isEmpty {
            let runsAfter: (Int) -> Bool
            let covers: (Int, Int) -> Bool
            switch line.window {
            case .allDay:
                runsAfter = { _ in true }
                covers = { _, _ in true }
            case .hours(let open, let close):
                runsAfter = { close > $0 }
                covers = { open <= $0 && close >= $1 }
            }
            if runsAfter(Self.nightStarts) { lit.formUnion(line.stops) }
            if covers(Self.marketOpens, Self.marketCloses), line.assignedTrains.count >= WinterMission.marketTrains {
                hasEveningMarketLine = true
            }
            if runsAfter(Int(GameTime.minutesPerDay)) { hasLineAfterMidnight = true }
            if liveried.contains(line.id) { hasLiveriedLineRunning = true }
        }
        stationsLitAtNight = lit.count
    }

    /// 18:00, when the stations' lights count; 17:00 to 22:00, the
    /// market's evening (minutes of the day).
    static let nightStarts = 18 * 60
    static let marketOpens = 17 * 60
    static let marketCloses = 22 * 60
}

/// One week's mission (decision 788; the plan's §2.4). Its numbers are the
/// frame's first ones: WINTER-MISSIONS measures them so a new game's first
/// week can meet them.
public struct WinterMission: Identifiable, Hashable, Sendable {
    public let id: String
    /// 1 to 5.
    public let week: Int
    let english: (title: String, how: String, badge: String)
    let chinese: (title: String, how: String, badge: String)
    let progress: @Sendable (WinterMissionFacts) -> (now: Int64, need: Int64)?
    let test: @Sendable (WinterMissionFacts) -> Bool

    public static func == (lhs: WinterMission, rhs: WinterMission) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public func title(in language: DisplayLanguage) -> String { language.text(english.title, chinese.title) }
    public func how(in language: DisplayLanguage) -> String { language.text(english.how, chinese.how) }
    /// The badge the mission gives.
    public func badge(in language: DisplayLanguage) -> String { language.text(english.badge, chinese.badge) }

    public func isMet(by facts: WinterMissionFacts) -> Bool { test(facts) }

    public func progress(of facts: WinterMissionFacts) -> (now: Int64, need: Int64)? {
        progress(facts).map { (min($0.now, $0.need), $0.need) }
    }

    /// Whether the mission's badge also keeps the Christmas livery for
    /// good (the fourth week's).
    public var unlocksLivery: Bool { id == "christmasEve" }

    /// The SF Symbol standing in for the badge until its drawing is made.
    public var placeholderSymbol: String {
        switch id {
        case "lights": "lightbulb.fill"
        case "market": "basket.fill"
        case "arctic": "snowflake"
        case "christmasEve": "gift.fill"
        default: "sparkles"
        }
    }

    static let litStations: Int64 = 3
    static let marketTrains = 2
    static let santaRiders: Int64 = 1_000

    public static let all: [WinterMission] = [
        WinterMission(
            id: "lights", week: 1,
            english: ("Lighting-Up Week", "Have \(litStations) stations with trains calling after 18:00.", "Lights On"),
            chinese: ("點燈週", "讓 \(litStations) 座以上的車站在 18:00 後還有車停靠。", "點燈"),
            progress: { (Int64($0.stationsLitAtNight), litStations) },
            test: { Int64($0.stationsLitAtNight) >= litStations }
        ),
        WinterMission(
            id: "market", week: 2,
            english: ("Christmas Market Specials", "Run a line from 17:00 to 22:00 with at least \(marketTrains) trains.", "Market"),
            chinese: ("聖誕市集專車", "讓一條路線 17:00 到 22:00 都營運，而且至少有 \(marketTrains) 列車。", "市集"),
            progress: { _ in nil },
            test: \.hasEveningMarketLine
        ),
        WinterMission(
            id: "arctic", week: 3,
            english: ("Santa Week", "Carry \(santaRiders.groupedText) riders in a day.", "Arctic Circle"),
            chinese: ("聖誕老人週", "一天載 \(santaRiders.groupedText) 位以上的旅客。", "北極圈"),
            progress: { ($0.yesterdayRiders, santaRiders) },
            test: { $0.yesterdayRiders >= santaRiders }
        ),
        WinterMission(
            id: "christmasEve", week: 4,
            english: ("Christmas Eve", "Run a day with trains in the Christmas livery.", "Christmas Livery"),
            chinese: ("平安夜", "讓套用聖誕塗裝的列車跑完一整天。", "聖誕塗裝"),
            progress: { _ in nil },
            test: \.hasLiveriedLineRunning
        ),
        WinterMission(
            id: "newYear", week: 5,
            english: ("New Year's Last Trains", "Run a line with trains after midnight.", "New Year"),
            chinese: ("跨年加開末班車", "讓一條路線在 00:00 之後還有車。", "跨年"),
            progress: { _ in nil },
            test: \.hasLineAfterMidnight
        ),
    ]

    public static func of(week: Int) -> WinterMission? {
        all.first { $0.week == week }
    }

    public static func named(_ id: String) -> WinterMission? {
        all.first { $0.id == id }
    }
}

/// The badges the player earned in each season, kept on the device beside
/// the achievements (decision 788): not a save, so a new game keeps them,
/// and a file that cannot be read is none earned.
public struct WinterEventRecords: Sendable {
    public let file: URL
    /// When each badge was earned, by "season.mission" ("2026.lights").
    public private(set) var earned: [String: Date]

    public static let fileName = "winter-event.data"

    private struct Stored: Codable {
        var version: Int
        var earned: [String: Date]
    }

    private static let version = 1

    public init(file: URL) {
        self.file = file
        let stored = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        earned = stored.flatMap { $0.version <= Self.version ? $0.earned : nil } ?? [:]
    }

    static func key(season: Int, mission: WinterMission) -> String { "\(season).\(mission.id)" }

    public func hasEarned(_ mission: WinterMission, season: Int) -> Bool {
        earned[Self.key(season: season, mission: mission)] != nil
    }

    /// The season's badges, in the weeks' order.
    public func badges(season: Int) -> [WinterMission] {
        WinterMission.all.filter { hasEarned($0, season: season) }
    }

    /// Whether the season's five badges are all earned: the event card
    /// then shows the keepsake card.
    public func hasAllBadges(season: Int) -> Bool {
        badges(season: season).count == WinterMission.all.count
    }

    /// Whether the Christmas livery can be chosen at `date`: during the
    /// event, and for good once a fourth week's badge was earned.
    public func liveryIsAvailable(at date: Date, calendar: Calendar = WinterEvent.calendar()) -> Bool {
        WinterEvent.isOn(at: date, calendar: calendar)
            || earned.keys.contains { $0.hasSuffix(".christmasEve") }
    }

    /// Earns the badge of the week `date` falls in when `facts` meet its
    /// mission and it is not earned yet; writes the file and returns it.
    public mutating func earn(meeting facts: WinterMissionFacts, at date: Date, calendar: Calendar = WinterEvent.calendar()) -> WinterMission? {
        let phase = WinterEvent.phase(at: date, calendar: calendar)
        guard let season = phase.season, let mission = WinterEvent.mission(at: date, calendar: calendar),
              !hasEarned(mission, season: season), mission.isMet(by: facts) else { return nil }
        earned[Self.key(season: season, mission: mission)] = date
        save()
        return mission
    }

    /// Writes the file after adding what it holds now (the earlier date
    /// where both have one), as the achievements do, so a badge never
    /// writes over records that could not be read at launch.
    private mutating func save() {
        let manager = FileManager.default
        if manager.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file) else { return }
            if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
                guard stored.version <= Self.version else { return }
                earned.merge(stored.earned) { mine, theirs in min(mine, theirs) }
            } else {
                let damaged = file.appendingPathExtension("damaged")
                try? manager.removeItem(at: damaged)
                guard (try? manager.moveItem(at: file, to: damaged)) != nil else { return }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(Stored(version: Self.version, earned: earned)).write(to: file, options: .atomic)
    }
}

extension GameSession {
    /// Says that the week's badge was earned (decision 788): in the news,
    /// on the status line and with the coins, as an achievement.
    public func noteWinterBadge(_ mission: WinterMission) {
        news.add(day: world.clock.now.seconds / GameTime.secondsPerDay, .achievement) { language in
            mission.unlocksLivery
                ? language.text(
                    "Winter event: \(mission.title(in: language)) done. The Christmas livery is yours to keep.",
                    "冬季活動：完成「\(mission.title(in: language))」，聖誕塗裝永久解鎖。"
                )
                : language.text(
                    "Winter event: \(mission.title(in: language)) done. Badge earned: \(mission.badge(in: language)).",
                    "冬季活動：完成「\(mission.title(in: language))」，獲得徽章「\(mission.badge(in: language))」。"
                )
        }
        isMessageKeptOutOfNews = true
        message = StatusMessage(kind: .success, text: language.text(
            "Badge earned: \(mission.badge(in: language))",
            "獲得徽章：\(mission.badge(in: language))"
        ))
        isMessageKeptOutOfNews = false
        playSound?(.income)
    }
}
