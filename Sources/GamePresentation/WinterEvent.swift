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
    /// The most trains a running passenger line calling at the
    /// Christmas market (``WinterMarket``) sends out from 17:00 to 22:00,
    /// one way: the trains it runs over its round trip, hour by hour.
    public var eveningMarketDepartures: Int64 = 0
    /// The riders of the day just ended.
    public var yesterdayRiders: Int64 = 0
    /// Whether a running passenger line wears the Christmas livery.
    public var hasLiveriedLineRunning = false
    /// Whether a running passenger line runs past midnight.
    public var hasLineAfterMidnight = false
    /// Decision 818: on a map that holds Santa Claus Village
    /// (``WinterSantaVillage``), whether a running passenger line calls
    /// within a station's reach of it; `nil` on any other map.
    public var reachesSantaVillage: Bool?

    public init() {}

    /// Reads `world`; `liveried` are the lines the player put the
    /// Christmas livery on (kept on the device, not in the save).
    public init(world: GameWorld, liveried: Set<LineID> = []) {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        yesterdayRiders = world.accounts.days.first { $0.day == today - 1 }?.fareTrips ?? 0
        var lit: Set<StationID> = []
        let market = WinterMarket.stations(in: world)
        let village = WinterSantaVillage.stations(in: world)
        reachesSantaVillage = village.map { _ in false }
        for line in world.lines where !line.isFreight && !line.assignedTrains.isEmpty {
            let runsAfter: (Int) -> Bool
            switch line.window {
            case .allDay:
                runsAfter = { _ in true }
            case .hours(_, let close):
                runsAfter = { close > $0 }
            }
            if runsAfter(Self.nightStarts) { lit.formUnion(line.stops) }
            if market.map({ !$0.isDisjoint(with: line.stops) }) ?? true {
                eveningMarketDepartures = max(eveningMarketDepartures, Self.eveningDepartures(of: line, in: world))
            }
            // L23 P3-1 (decision 814): a train at 00:00, whether its
            // hours run past midnight or open at it.
            if line.window.contains(minuteOfDay: 0) { hasLineAfterMidnight = true }
            if liveried.contains(line.id) { hasLiveriedLineRunning = true }
            if let village, !village.isDisjoint(with: line.stops) { reachesSantaVillage = true }
        }
        stationsLitAtNight = lit.count
    }

    /// 18:00, when the stations' lights count; 17:00 to 22:00, the
    /// market's evening (hours of the day).
    static let nightStarts = 18 * 60
    static let marketHours = 17..<22

    /// The trains `line` sends out one way over the market's evening: in
    /// each hour it is open, the trains it runs then (no more than it has)
    /// over its round trip, rounded down at the end.
    static func eveningDepartures(of line: ServiceLine, in world: GameWorld) -> Int64 {
        guard let roundTrip = world.lineJourney(line.id)?.roundTripMinutes, roundTrip > 0 else { return 0 }
        var trips = 0.0
        for hour in marketHours {
            guard let level = world.serviceLevel(of: line.id, at: GameTime(minutes: Int64(hour * 60))) else { continue }
            let trains = min(line.assignedTrains.count, world.lineTrainsInService(line.id, at: level) ?? 0)
            trips += 60 * Double(trains) / Double(roundTrip)
        }
        return Int64(trips + 1e-9)
    }
}

/// Week 2's Christmas market (decision 814; the plan's §2.4): New Taipei's
/// Christmasland on Banqiao's civic square, or Tsim Sha Tsui's waterfront,
/// on a map that holds one (the plazas of ``Map3DWinterLights``); on any
/// other map its middle, the place with the most jobs.
public enum WinterMarket {
    /// The plazas a market may be at, by ``Map3DWinterLights/Plaza/name``.
    static let plazaNames: Set<String> = ["banqiao", "tsim-sha-tsui"]

    /// Where the market is in `world`, or `nil` on a map with no plaza
    /// and no jobs.
    public static func place(in world: GameWorld) -> PlanPoint? {
        if let frame = RealWorldFrame(world: world) {
            let region = WorldRegion(bounds: world.bounds)
            for plaza in Map3DWinterLights.plazas where plazaNames.contains(plaza.name) {
                let at = frame.worldPosition(latitude: plaza.latitude, longitude: plaza.longitude)
                if (region.minX...region.maxX).contains(at.x), (region.minY...region.maxY).contains(at.y) {
                    return PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))
                }
            }
        }
        // The first of the busiest cells, in the land's own order.
        guard let busiest = world.land.cells.max(by: { $0.jobs < $1.jobs }), busiest.jobs > 0 else { return nil }
        return busiest.middle
    }

    /// The stations within a station's reach (``Land/catchmentRadius``)
    /// of the market, or `nil` when `world` has none: then any line will
    /// do.
    static func stations(in world: GameWorld) -> Set<StationID>? {
        guard let place = place(in: world) else { return nil }
        let reach = Double(Land.catchmentRadius)
        return Set(world.stations.filter { station in
            let dx = Double(station.location.x - place.x), dy = Double(station.location.y - place.y)
            return dx * dx + dy * dy <= reach * reach
        }.map(\.id))
    }
}

/// Decision 818: Santa Claus Village on the Arctic Circle north of
/// Rovaniemi (the plaza of ``Map3DWinterLights``), which has no railway:
/// on Rovaniemi's map week 3 asks for a line to it (the plan's §2.4).
public enum WinterSantaVillage {
    static let plazaName = "santa-claus-village"

    /// Where the village is in `world`, or `nil` when the map does not
    /// hold it.
    public static func place(in world: GameWorld) -> PlanPoint? {
        guard let frame = RealWorldFrame(world: world),
              let plaza = Map3DWinterLights.plazas.first(where: { $0.name == plazaName }) else { return nil }
        let region = WorldRegion(bounds: world.bounds)
        let at = frame.worldPosition(latitude: plaza.latitude, longitude: plaza.longitude)
        guard (region.minX...region.maxX).contains(at.x), (region.minY...region.maxY).contains(at.y) else { return nil }
        return PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))
    }

    /// The stations within a station's reach (``Land/catchmentRadius``)
    /// of the village, or `nil` when the map does not hold it.
    static func stations(in world: GameWorld) -> Set<StationID>? {
        guard let place = place(in: world) else { return nil }
        let reach = Double(Land.catchmentRadius)
        return Set(world.stations.filter { station in
            let dx = Double(station.location.x - place.x), dy = Double(station.location.y - place.y)
            return dx * dx + dy * dy <= reach * reach
        }.map(\.id))
    }
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
    /// What to do on the map `facts` were read from: week 3 on a map that
    /// holds Santa Claus Village asks for a line to it (decision 818).
    public func how(in language: DisplayLanguage, facts: WinterMissionFacts?) -> String {
        how(in: language, onSantaMap: facts?.reachesSantaVillage != nil)
    }
    /// What to do, on a map that holds Santa Claus Village or not.
    public func how(in language: DisplayLanguage, onSantaMap: Bool) -> String {
        if id == "arctic", onSantaMap {
            return language.text("Run a line to Santa Claus Village on the Arctic Circle.", "讓一條路線連到北極圈上的聖誕老人村。")
        }
        return how(in: language)
    }
    /// The badge the mission gives.
    public func badge(in language: DisplayLanguage) -> String { language.text(english.badge, chinese.badge) }

    public func isMet(by facts: WinterMissionFacts) -> Bool { test(facts) }

    public func progress(of facts: WinterMissionFacts) -> (now: Int64, need: Int64)? {
        progress(facts).map { (min($0.now, $0.need), $0.need) }
    }

    /// Whether the mission's badge also keeps the Christmas livery for
    /// good (the fourth week's).
    public var unlocksLivery: Bool { id == "christmasEve" }

    /// The badge's drawing in the app's asset catalog (decision 814):
    /// `WinterBadge-<id>`, a medal on the winter night's navy.
    public var badgeImageName: String { "WinterBadge-\(id)" }

    static let litStations: Int64 = 3
    static let marketDepartures: Int64 = 6
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
            english: ("Christmas Market Specials", "Run a line to the Christmas market (Banqiao, Tsim Sha Tsui or the city centre) with \(marketDepartures) trains out between 17:00 and 22:00.", "Market"),
            chinese: ("聖誕市集專車", "讓一條路線連到聖誕市集（板橋、尖沙咀或市中心），17:00 到 22:00 開出 \(marketDepartures) 班以上。", "市集"),
            progress: { ($0.eveningMarketDepartures, marketDepartures) },
            test: { $0.eveningMarketDepartures >= marketDepartures }
        ),
        WinterMission(
            id: "arctic", week: 3,
            english: ("Santa Week", "Carry \(santaRiders.groupedText) riders in a day.", "Arctic Circle"),
            chinese: ("聖誕老人週", "一天載 \(santaRiders.groupedText) 位以上的旅客。", "北極圈"),
            // Decision 818: on Rovaniemi's map, a line to Santa Claus
            // Village instead.
            progress: { $0.reachesSantaVillage == nil ? ($0.yesterdayRiders, santaRiders) : nil },
            test: { $0.reachesSantaVillage ?? ($0.yesterdayRiders >= santaRiders) }
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

/// Decision 884: the station master's own part in the winter event. While
/// the event's decorations show, Taiwan's station master wears a Christmas
/// hat (its faces with ``outfitSuffix``), and each week's mission is told
/// by it once, on a card in the corner, the first time the game is played
/// that week.
public enum WinterStationMaster {
    /// Added to a face's name in the asset catalog while the hat is worn:
    /// `StationMasterTaiwanNormal` + `Christmas`.
    public static let outfitSuffix = "Christmas"
    /// The last week whose mission was told, as ``key(season:week:)``.
    public static let toldKey = "event.winterMissionTold"

    /// What to add to a face's name at `date`: the hat during the event,
    /// unless the player switched the decorations off, else nothing.
    public static func outfit(at date: Date, switchedOn: Bool, calendar: Calendar = WinterEvent.calendar()) -> String {
        WinterEvent.showsDecorations(at: date, switchedOn: switchedOn, calendar: calendar) ? outfitSuffix : ""
    }

    /// The key ``toldKey`` keeps for week `week` of season `season`.
    public static func key(season: Int, week: Int) -> String { "\(season).\(week)" }

    /// The card to tell at `date`, if this week's mission was not told yet
    /// (`told` is the last told week's key, ``toldKey``), with the key to
    /// keep once it is told. Nothing in the last days (6 January), when
    /// there is no mission.
    /// `onSantaMap`: the map holds Santa Claus Village (week 3 asks for a
    /// line to it there, decision 818).
    public static func announcement(
        at date: Date, told: String?, onSantaMap: Bool = false, calendar: Calendar = WinterEvent.calendar()
    ) -> (beat: StoryBeat, key: String)? {
        let state = WinterEvent.phase(at: date, calendar: calendar)
        guard let season = state.season, case .week(let week) = state.phase, let mission = WinterMission.of(week: week) else { return nil }
        let key = key(season: season, week: week)
        guard key != told else { return nil }
        return (beat(mission, season: season, onSantaMap: onSantaMap), key)
    }

    /// The card's words: the week's mission and what it asks.
    static func beat(_ mission: WinterMission, season: Int, onSantaMap: Bool) -> StoryBeat {
        let week = mission.week
        let first = week == 1
        let english = (first ? "The winter event has begun! " : "")
            + "Week \(week)'s mission: \(mission.english.title). \(mission.how(in: .english, onSantaMap: onSantaMap)) Its badge is in Goals."
        let chinese = (first ? "冬季活動開始了！" : "")
            + "第 \(week) 週的任務是「\(mission.chinese.title)」：\(mission.how(in: .traditionalChinese, onSantaMap: onSantaMap))徽章在「目標」裡。"
        return StoryBeat(
            "winter.\(season).\(week)", .winterWeek(season: season, week: week), .stationMaster, english, chinese
        )
    }
}
