// Public holidays (ARCHITECTURE decision 154, the first step of
// `docs/research/DISRUPTION_STUDY.md` plan B), after the owner's `Ci/`
// reference (`Ci/reference_snapshot/lib/aviation_disruptions__q_dc8f79f5de24b024.js`):
//
// - its holiday table `x` and the further rows `K` give each country's
//   holidays as `[country, name, days, boost]`, the boost a share of the
//   demand added while the holiday runs (`l("holiday", …, y[2], y[3])`).
//   The names, the days and the boosts are the reference's; its loader
//   then adds 0.2 to every boost (`E(e) = e + .2`), which is the flight
//   game's own and is left out here;
// - Taiwan's row there has no national day and no 228 Peace Memorial Day,
//   which `Railway/site_archive_clean/index.html`'s `TW_DAYTYPE` (Taiwan's
//   public holidays of 2026 and 2027) has, and its Qingming is one day where
//   `TW_DAYTYPE` has the four of Children's Day and Tomb Sweeping Day: this
//   project's Taiwan follows `TW_DAYTYPE` (a deliberate change, decision
//   154).
//
// The reference draws a holiday at random among a country's; a railway's
// calendar is known, so here each holiday comes on the same days every
// year. The game's year is 360 days of twelve 30-day months, with no real
// date (decision 90), so each holiday is set on the month and day it has in
// 2026 (a lunar or moving holiday where it fell that year): those dates
// are this project's (gap: the reference has none).

/// How strongly disruptions bite (decision 154): the first is gentler.
public enum DisruptionLevel: String, CaseIterable, Codable, Sendable {
    /// Gentler: a holiday raises demand by half its boost (rounded down).
    case light
    /// A holiday raises demand by its whole boost.
    case standard

    /// What `boost` thousandths of a holiday add at this level.
    func scaled(_ boost: Int64) -> Int64 {
        self == .standard ? boost : boost / 2
    }
}

/// A public holiday (the reference's holiday names).
public enum HolidayKind: String, CaseIterable, Codable, Sendable {
    case newYear
    case springFestival
    /// Taiwan's 228 Peace Memorial Day (`TW_DAYTYPE`).
    case peaceMemorial
    case qingming
    case labourDay
    case dragonBoat
    case midAutumn
    case nationalDay
    case christmas
    case easter
    case thanksgiving
    case eidFitr
    case eidAdha
    case diwali
    case chuseok
    case goldenWeek
    case songkran
}

/// One of a country's holidays: what it is, the month and day of the
/// game's year it starts on, how many days it runs and how much it adds to
/// demand.
public struct Holiday: Hashable, Sendable {
    public let kind: HolidayKind
    /// 1 to 12.
    public let month: Int
    /// 1 to 30: a game month has 30 days.
    public let day: Int
    /// How many days it runs.
    public let days: Int64
    /// What it adds to demand at ``DisruptionLevel/standard``, in
    /// thousandths (the reference's boost).
    public let boost: Int64

    init(_ kind: HolidayKind, _ month: Int, _ day: Int, days: Int64, boost: Int64) {
        self.kind = kind
        self.month = month
        self.day = day
        self.days = days
        self.boost = boost
    }

    /// The day of the game's year it starts on, from 0.
    public var dayOfYear: Int64 {
        Int64((month - 1) * 30 + day - 1)
    }
}

/// Every country's holidays (the reference's `x` and `K`; Taiwan's after
/// `TW_DAYTYPE`), by ISO 3166 code.
public enum HolidayCalendar {
    /// The country of a blank map, and of a real-world map whose country is
    /// not here: Taiwan, the game's home.
    public static let home = "TW"

    /// The countries, by code.
    public static let countries: [String: [Holiday]] = [
        "TW": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.springFestival, 2, 14, days: 9, boost: 200),
            Holiday(.peaceMemorial, 2, 28, days: 1, boost: 50),
            Holiday(.qingming, 4, 3, days: 4, boost: 50),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.dragonBoat, 6, 19, days: 1, boost: 50),
            Holiday(.midAutumn, 9, 25, days: 1, boost: 50),
            Holiday(.nationalDay, 10, 10, days: 1, boost: 100),
        ],
        "CN": [
            Holiday(.newYear, 1, 1, days: 3, boost: 50),
            Holiday(.springFestival, 2, 15, days: 9, boost: 200),
            Holiday(.qingming, 4, 4, days: 3, boost: 50),
            Holiday(.labourDay, 5, 1, days: 5, boost: 100),
            Holiday(.dragonBoat, 6, 19, days: 3, boost: 50),
            Holiday(.midAutumn, 9, 25, days: 3, boost: 50),
            Holiday(.nationalDay, 10, 1, days: 7, boost: 100),
        ],
        "HK": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.springFestival, 2, 17, days: 3, boost: 200),
            Holiday(.qingming, 4, 5, days: 1, boost: 50),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.dragonBoat, 6, 19, days: 1, boost: 50),
            Holiday(.midAutumn, 9, 26, days: 1, boost: 50),
            Holiday(.nationalDay, 10, 1, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "SG": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.springFestival, 2, 17, days: 2, boost: 200),
            Holiday(.eidFitr, 3, 21, days: 1, boost: 200),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.eidAdha, 5, 27, days: 1, boost: 200),
            Holiday(.nationalDay, 8, 9, days: 1, boost: 100),
            Holiday(.diwali, 11, 8, days: 2, boost: 100),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "KR": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.springFestival, 2, 16, days: 3, boost: 200),
            Holiday(.chuseok, 9, 24, days: 3, boost: 200),
            Holiday(.nationalDay, 10, 3, days: 1, boost: 100),
        ],
        "JP": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.goldenWeek, 5, 2, days: 5, boost: 100),
        ],
        "US": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.nationalDay, 7, 4, days: 1, boost: 100),
            Holiday(.labourDay, 9, 7, days: 1, boost: 80),
            Holiday(.thanksgiving, 11, 26, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "CA": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.nationalDay, 7, 1, days: 1, boost: 100),
            Holiday(.labourDay, 9, 7, days: 1, boost: 80),
            Holiday(.thanksgiving, 10, 12, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "GB": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "FR": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.easter, 4, 6, days: 1, boost: 100),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.nationalDay, 7, 14, days: 1, boost: 50),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "AU": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.nationalDay, 1, 26, days: 1, boost: 100),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "SA": [
            Holiday(.eidFitr, 3, 20, days: 4, boost: 200),
            Holiday(.eidAdha, 5, 26, days: 4, boost: 200),
            Holiday(.nationalDay, 9, 23, days: 1, boost: 100),
        ],
        "AE": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.eidFitr, 3, 20, days: 4, boost: 200),
            Holiday(.eidAdha, 5, 26, days: 4, boost: 200),
            Holiday(.nationalDay, 12, 2, days: 2, boost: 100),
        ],
        "VN": [
            Holiday(.newYear, 1, 1, days: 4, boost: 50),
            Holiday(.springFestival, 2, 14, days: 9, boost: 200),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.nationalDay, 8, 29, days: 5, boost: 100),
        ],
        "ID": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.springFestival, 2, 17, days: 1, boost: 100),
            Holiday(.eidFitr, 3, 20, days: 2, boost: 200),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.eidAdha, 5, 27, days: 1, boost: 100),
            Holiday(.nationalDay, 8, 17, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "IN": [
            Holiday(.eidFitr, 3, 21, days: 1, boost: 100),
            Holiday(.eidAdha, 5, 27, days: 1, boost: 100),
            Holiday(.nationalDay, 8, 15, days: 1, boost: 100),
            Holiday(.diwali, 11, 8, days: 1, boost: 150),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "TH": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.songkran, 4, 13, days: 3, boost: 200),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
        ],
        "DE": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.nationalDay, 10, 3, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "NL": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "PL": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.nationalDay, 11, 11, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "NZ": [
            Holiday(.newYear, 1, 1, days: 2, boost: 80),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.labourDay, 10, 26, days: 1, boost: 80),
            Holiday(.christmas, 12, 25, days: 2, boost: 100),
        ],
        "BR": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.nationalDay, 9, 7, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "MX": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.nationalDay, 9, 16, days: 1, boost: 100),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
        "ZA": [
            Holiday(.newYear, 1, 1, days: 1, boost: 50),
            Holiday(.easter, 4, 5, days: 2, boost: 100),
            Holiday(.labourDay, 5, 1, days: 1, boost: 80),
            Holiday(.christmas, 12, 25, days: 1, boost: 100),
        ],
    ]
}

/// A world's disruptions (decision 154): the country whose holidays it
/// keeps, and how strongly they bite. A world without them has none.
public struct Disruptions: Hashable, Sendable {
    /// An ISO 3166 code of ``HolidayCalendar/countries``.
    public let country: String
    public let level: DisruptionLevel

    /// Disruptions at `level` with `country`'s holidays, or `nil` for a
    /// country ``HolidayCalendar`` does not have.
    public init?(level: DisruptionLevel, country: String) {
        guard HolidayCalendar.countries[country] != nil else { return nil }
        self.country = country
        self.level = level
    }

    /// The country's holidays.
    public var holidays: [Holiday] {
        HolidayCalendar.countries[country] ?? []
    }
}

extension Disruptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case country, level
    }

    /// Decodes disruptions, rejecting a country the calendar does not have.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let country = try container.decode(String.self, forKey: .country)
        guard let disruptions = Disruptions(level: try container.decode(DisruptionLevel.self, forKey: .level), country: country) else {
            throw DecodingError.dataCorruptedError(forKey: .country, in: container, debugDescription: "No holidays are known for \(country).")
        }
        self = disruptions
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(country, forKey: .country)
        try container.encode(level, forKey: .level)
    }
}

/// One year's run of a holiday: its first game day, the day after its
/// last, and what it adds to demand at the world's level.
public struct HolidayRun: Hashable, Sendable {
    public let holiday: Holiday
    public let start: Int64
    public let end: Int64
    /// In thousandths.
    public let boost: Int64

    /// Whether it runs on game day `day`.
    public func isActive(onDay day: Int64) -> Bool {
        start <= day && day < end
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns disruptions on with `disruptions`, or off with `nil`
    /// (decision 154). Free. Passengers already waiting stay; the next
    /// release follows the new demand.
    public mutating func setDisruptions(_ disruptions: Disruptions?) {
        guard disruptions != self.disruptions else { return }
        self.disruptions = disruptions
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    /// The holiday running on game day `day`, or `nil`: the one adding the
    /// most to demand, the first of ``holidays(from:through:)`` when two
    /// add as much.
    public func holiday(onDay day: Int64) -> HolidayRun? {
        holidays(from: day, through: day).max { $0.boost < $1.boost }
    }

    /// The runs of the world's holidays that are on any day from `first`
    /// through `last`, by start, then by the country's order.
    public func holidays(from first: Int64, through last: Int64) -> [HolidayRun] {
        guard let disruptions, first <= last else { return [] }
        let year = FinancePeriod.year.days
        var runs: [HolidayRun] = []
        for holiday in disruptions.holidays {
            // The year of the run that started last on or before `first`,
            // and every later one that starts by `last`.
            var start = CompanyAccounts.floorDivide(first - holiday.dayOfYear, year) * year + holiday.dayOfYear
            while start <= last {
                if start + holiday.days > first {
                    runs.append(HolidayRun(holiday: holiday, start: start, end: start + holiday.days, boost: disruptions.level.scaled(holiday.boost)))
                }
                start += year
            }
        }
        return runs.enumerated().sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }.map(\.element)
    }

    /// How much the whole network's demand is raised today, in thousandths
    /// of its own: 1000, or 1000 and today's holiday's boost.
    public var holidayMultiplier: Int64 {
        1_000 + (holiday(onDay: dayIndex(of: clock.now))?.boost ?? 0)
    }
}
