import GameCore

// The secretary room's news log (ARCHITECTURE decision 175): what the
// station master said, what the status line told, goals met, the year's and
// the month's close, holidays and typhoons starting, fuel prices and the
// land for sale, kept with the game so that a reminder seen once is not lost
// when the player looks away. A presentation record, derived from the
// world: it is not part of `SavedGame` (no save version), it is kept in a
// side file of each save (``SaveLibrary``), and a log that cannot be read is
// an empty one.

/// What an item of the log is about; picks its icon.
public enum NewsCategory: String, Codable, CaseIterable, Sendable {
    case advice, success, failure, goal, scenario, yearEnd, monthly, land, holiday, typhoon, fuel, growth, materials, debt, deadline
    /// An achievement unlocked (decision 181).
    case achievement

    /// The item's SF Symbol.
    public var symbolName: String {
        switch self {
        case .advice: "bubble.left.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .goal: "flag.checkered"
        case .scenario: "trophy.fill"
        case .yearEnd: "doc.text.fill"
        case .monthly: "calendar"
        case .land: "map.fill"
        case .holiday: "gift.fill"
        case .typhoon: "tropicalstorm"
        case .fuel: "fuelpump.fill"
        case .growth: "building.2.fill"
        case .materials: "shippingbox.fill"
        case .debt: "banknote.fill"
        case .deadline: "hourglass"
        case .achievement: "rosette"
        }
    }

    /// Whether the item is a worry rather than news.
    public var isWorry: Bool {
        switch self {
        case .failure, .typhoon, .debt, .deadline, .materials: true
        default: false
        }
    }
}

/// Where the map goes when the player taps "Go" on an item: an ID only,
/// never a copy of the thing.
public enum NewsTarget: Hashable, Codable, Sendable {
    case station(Int)
    case line(Int)
    case train(Int)
}

/// One item of the log. The text is kept in both languages the app has when
/// the writer knows both; a status message, which exists in the language
/// it was said in only, has that one.
public struct NewsItem: Hashable, Codable, Sendable, Identifiable {
    public let id: Int
    /// The game day it happened on.
    public let day: Int64
    public let category: NewsCategory
    public let english: String?
    public let chinese: String?
    public let target: NewsTarget?

    /// The text in `language`, else in the other.
    public func text(in language: DisplayLanguage) -> String {
        switch language {
        case .english: english ?? chinese ?? ""
        case .traditionalChinese: chinese ?? english ?? ""
        }
    }

    public var date: GameDate { GameDate(day: day) }
}

/// What the monthly report compares with, kept between reports: the month
/// last reported, each station's planned daily trips and how many of the
/// city's buildings are of density D3 and D4 at that time.
public struct MonthlyBaseline: Hashable, Codable, Sendable {
    /// The last month (day ÷ 30) a report was made for.
    public var reportedMonth: Int64
    /// Each station's daily trips (``StationDemand/dailyTrips``), by
    /// station ID.
    public var stationTrips: [Int: Int64]
    /// The buildings of density D3 and D4.
    public var tallBuildings: Int

    public init(reportedMonth: Int64, stationTrips: [Int: Int64], tallBuildings: Int) {
        self.reportedMonth = reportedMonth
        self.stationTrips = stationTrips
        self.tallBuildings = tallBuildings
    }

    /// The baseline of `world` as it is now, for the month before the one
    /// it is in.
    public init(world: GameWorld) {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        reportedMonth = today / FinancePeriod.month.days - 1
        stationTrips = Dictionary(
            world.stations.compactMap { station in world.stationDemand(of: station.id).map { (station.id.rawValue, $0.dailyTrips) } },
            uniquingKeysWith: { $1 }
        )
        tallBuildings = world.buildings.all.count { $0.density == .d3 || $0.density == .d4 }
    }
}

/// The log: the newest item first, at most ``capacity``.
public struct NewsLog: Hashable, Codable, Sendable {
    /// The most items kept.
    public static let capacity = 300

    public private(set) var items: [NewsItem]
    /// The ID the next item takes.
    private var nextID: Int
    /// The newest item the player has seen, 0 for none.
    private var readThrough: Int
    public var baseline: MonthlyBaseline?
    /// Whether the game is one of the demos (decision 181): kept with the
    /// save, so a demo continued later still unlocks no achievements.
    public var isDemo = false

    public init() {
        items = []
        nextID = 1
        readThrough = 0
        baseline = nil
    }

    /// Items not yet seen.
    public var unread: Int {
        items.prefix { $0.id > readThrough }.count
    }

    /// Where the player had read up to, kept by a view when the log opens.
    public var readMark: Int { readThrough }

    /// Whether `item` was not yet seen at `mark` (a ``readMark`` taken
    /// earlier). Items added while the log is open push the list down, so
    /// a view marks what is new by ID, not by position.
    public static func isNew(_ item: NewsItem, since mark: Int) -> Bool {
        item.id > mark
    }

    /// The player has opened the log: everything in it is seen.
    public mutating func markRead() {
        readThrough = nextID - 1
    }

    /// Adds an item at the front, dropping the oldest beyond ``capacity``.
    /// Returns it.
    @discardableResult
    public mutating func add(
        day: Int64, _ category: NewsCategory, english: String?, chinese: String?, target: NewsTarget? = nil
    ) -> NewsItem {
        let item = NewsItem(id: nextID, day: day, category: category, english: english, chinese: chinese, target: target)
        nextID += 1
        items.insert(item, at: 0)
        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        return item
    }

    /// Adds an item whose text `text` says in both languages.
    @discardableResult
    public mutating func add(day: Int64, _ category: NewsCategory, target: NewsTarget? = nil, text: (DisplayLanguage) -> String) -> NewsItem {
        add(
            day: day, category, english: text(.english), chinese: text(.traditionalChinese), target: target
        )
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case version, items, nextID, readThrough, baseline, isDemo
    }

    private static let version = 1

    /// Reads a log; one of a later version, or with items out of order, is
    /// refused rather than trusted (the caller starts an empty one).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) <= Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "A later version of the news log.")
        }
        let items = try container.decode([NewsItem].self, forKey: .items)
        let nextID = try container.decode(Int.self, forKey: .nextID)
        let readThrough = try container.decode(Int.self, forKey: .readThrough)
        // Newest first, so IDs fall, and all are below the next.
        guard items.count <= Self.capacity,
              zip(items, items.dropFirst()).allSatisfy({ $0.id > $1.id }),
              nextID >= 1, nextID < Int.max / 2, items.allSatisfy({ $0.id >= 1 }),
              items.first.map({ $0.id < nextID }) ?? true,
              (0..<nextID).contains(readThrough) || readThrough == 0
        else {
            throw DecodingError.dataCorruptedError(forKey: .items, in: container, debugDescription: "The news log is out of order.")
        }
        self.items = items
        self.nextID = nextID
        self.readThrough = readThrough
        baseline = try container.decodeIfPresent(MonthlyBaseline.self, forKey: .baseline)
        isDemo = try container.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(items, forKey: .items)
        try container.encode(nextID, forKey: .nextID)
        try container.encode(readThrough, forKey: .readThrough)
        try container.encodeIfPresent(baseline, forKey: .baseline)
        if isDemo { try container.encode(isDemo, forKey: .isDemo) }
    }
}

// MARK: - What the station master says, as news

extension StationMasterAdvice {
    /// How the log keeps what the station master said: the category, a key
    /// that is the same while it is the same worry (so a worry that returns
    /// each hour is one item, not twenty) and where "Go" leads; `nil` for
    /// advice the log keeps in another way (a debt, a typhoon, a fuel
    /// spell, a goal or the challenge's end have their own items).
    var newsEntry: (category: NewsCategory, key: String, target: NewsTarget?)? {
        switch self {
        case .inDebt, .inDebtShortLine, .typhoonComing, .fuelSpell, .goalMet, .scenarioCompleted: nil
        case .stationFull(let station, _): (.advice, "full:\(station.rawValue)", .station(station.rawValue))
        case .lineWithoutTrains(let line, _): (.advice, "empty:\(line.rawValue)", .line(line.rawValue))
        case .lineLosing(let line, _, _): (.advice, "losing:\(line.rawValue)", .line(line.rawValue))
        case .stationCrowded(let station, _): (.advice, "crowded:\(station.rawValue)", .station(station.rawValue))
        case .firstLineLosing: (.advice, "firstLineLosing", nil)
        case .buildTrack: (.advice, "buildTrack", nil)
        case .buildStation: (.advice, "buildStation", nil)
        case .buildSecondStation: (.advice, "buildSecondStation", nil)
        case .createLine: (.advice, "createLine", nil)
        case .underserved(let station, _, _): (.growth, "underserved:\(station.rawValue)", .station(station.rawValue))
        case .townGrew(let station, _, _): (.growth, "grew:\(station.rawValue)", .station(station.rawValue))
        case .holidayComing(let kind, _, _): (.holiday, "holiday:\(kind.rawValue)", nil)
        case .holidayOver(let kind, _, _): (.holiday, "holidayOver:\(kind.rawValue)", nil)
        case .materialsShort(let station, _): (.materials, "materials:\(station.rawValue)", .station(station.rawValue))
        case .scenarioWelcome: (.scenario, "welcome", nil)
        case .shortSteamTrains(let line, _): (.advice, "steam:\(line.rawValue)", .line(line.rawValue))
        case .festivalComing: (.holiday, "festival", nil)
        // Decision 174: the sights.
        case .sightUnreachable(let id, _, _, _, _): (.advice, "sight:\(id.rawValue)", nil)
        case .touristsComing(let kind, _, _): (.holiday, "tourists:\(kind.rawValue)", nil)
        // Decision 183: the city's offers, once a month.
        case .newCityRequests(let month, _, _, _): (.goal, "requests:\(month)", nil)
        }
    }
}

// MARK: - The bankruptcy countdown

extension GameWorld {
    /// The days left before the challenge is lost to the red, or `nil`:
    /// the scenario sets ``Scenario/insolvencyDays``, is not over, and the
    /// balance is below zero (decision 175). The days it has already been
    /// below zero at midnight are taken off.
    public var insolvencyCountdown: Int64? {
        guard let state = scenario, state.outcome == nil, let limit = state.scenario.insolvencyDays,
              economy.showsInTheRed else { return nil }
        return max(0, limit - state.insolventDays)
    }
}

/// The text of the countdown.
public func insolvencyCountdownText(_ days: Int64, in language: DisplayLanguage) -> String {
    language.text("Bankruptcy in \(days) day\(days == 1 ? "" : "s")", "破產倒數 \(days) 天")
}
