// Weather, typhoons and the fuel price (ARCHITECTURE decision 162, the
// second step of `docs/research/DISRUPTION_STUDY.md` plan B), on the
// switch and level of decision 154 (``Disruptions``).
//
// After the owner's `Ci/` reference:
//
// - `Ci/reference_snapshot/lib/aviation_disruptions__q_dc8f79f5de24b024.js`
//   closes a region's airports for weather (`airportClosed`), a typhoon in
//   Taiwan's and southern China's regions, and raises or lowers fuel
//   (`fuelUp`, `fuelDown`: `fuelIndex` 1.12–1.32 or 0.88–0.96, 7 to 14
//   days, never in the first six weeks);
// - its draws are FNV-1a over `seed|key` (`d(state, key)`), as
//   ``SeedDraw`` already is (decision 69).
//
// Here every draw's key names its day, year or month, so the weather of
// any day, the typhoons of any year and the fuel price of any month are
// worked out from the seed alone: nothing is stored day by day, and a batch,
// a minute at a time or a save carried on all give the same. The chances,
// the drops in demand, the typhoon season and the areas are this project's
// (gap: the reference has no railway weather), and so is the calm of the
// first 30 days.

/// A day's weather (decision 162).
public enum Weather: String, CaseIterable, Codable, Sendable {
    case clear
    case rain
    case thunderstorm

    /// What it takes off the whole network's demand at
    /// ``DisruptionLevel/standard``, in thousandths.
    var drop: Int64 {
        switch self {
        case .clear: 0
        case .rain: 100
        case .thunderstorm: 200
        }
    }
}

/// A typhoon (decision 162): announced days before it comes, it cuts the
/// demand of every station within its radius while it lasts.
public struct Typhoon: Hashable, Sendable {
    /// The day it is announced, the first day it blows and the day after
    /// its last.
    public let announced: Int64
    public let start: Int64
    public let end: Int64
    /// The middle of its area, and how far from it a station is hit, in
    /// world units.
    public let centre: PlanPoint
    public let radius: Int64
    /// What it takes off a station's demand, in thousandths, at the world's
    /// level.
    public let drop: Int64

    /// Whether it blows on game day `day`.
    public func isActive(onDay day: Int64) -> Bool {
        start <= day && day < end
    }

    /// Whether `point` is within its radius.
    public func covers(_ point: PlanPoint) -> Bool {
        let dx = point.x - centre.x, dy = point.y - centre.y
        return dx * dx + dy * dy <= radius * radius
    }
}

/// A spell of dearer or cheaper fuel (decision 162): from `start` to the day
/// before `end`, the day's energy costs `index` thousandths of its own.
public struct FuelSpell: Hashable, Sendable {
    public let start: Int64
    public let end: Int64
    public let index: Int64

    public func isActive(onDay day: Int64) -> Bool {
        start <= day && day < end
    }
}

extension Disruptions {
    /// No weather, typhoon or fuel spell in a game's first days.
    public static let calmDays: Int64 = 30
    /// The fuel price stays as it is for the reference's first six weeks.
    static let fuelCalmDays: Int64 = 42

    /// Each month's chance of rain and of a thunderstorm, in thousandths:
    /// a plum-rain spring and afternoon thunderstorms in summer, as a
    /// Taiwanese year has them (this project's, used for every country).
    static let monthlyRain: [(rain: Int64, storm: Int64)] = [
        (250, 0), (300, 0), (300, 20), (300, 50), (450, 80), (450, 120),
        (200, 250), (200, 250), (200, 150), (200, 30), (200, 0), (200, 0),
    ]

    /// The countries typhoons reach.
    static let typhoonCountries: Set<String> = ["TW", "CN", "HK", "JP", "KR", "VN"]
    /// The typhoon season: from 1 July (day 180 of the game's year) to the
    /// end of October (day 299).
    static let typhoonSeason: ClosedRange<Int64> = 180...299
    /// A year has up to three typhoons, each one this likely, in
    /// thousandths: half as many at the light level.
    static let typhoonSlots = 3
    var typhoonChance: Int64 { level == .standard ? 500 : 250 }

    /// What `drop` thousandths take off at this level: all of it, or half
    /// (rounded down) at the light level.
    func scaledDrop(_ drop: Int64) -> Int64 {
        level.scaled(drop)
    }

    /// The weather of game day `day`: clear without a seed or in the first
    /// ``calmDays``.
    public func weather(onDay day: Int64) -> Weather {
        guard let seed, day >= Self.calmDays else { return .clear }
        let year = FinancePeriod.year.days
        let month = Int(((day % year) + year) % year / FinancePeriod.month.days)
        let chances = Self.monthlyRain[month]
        let roll = SeedDraw(seed: seed).roll("weather.\(day)", in: 0...999)
        if roll < chances.storm { return .thunderstorm }
        return roll < chances.storm + chances.rain ? .rain : .clear
    }

    /// The typhoons of game year `year` (day `360 × year` on) in a world of
    /// `bounds`, by start: none without a seed or outside
    /// ``typhoonCountries``, and none starting in the first ``calmDays``.
    public func typhoons(ofYear year: Int64, in bounds: WorldBounds) -> [Typhoon] {
        guard let seed, Self.typhoonCountries.contains(country) else { return [] }
        let draw = SeedDraw(seed: seed)
        let first = year * FinancePeriod.year.days
        var typhoons: [Typhoon] = []
        for slot in 0..<Self.typhoonSlots {
            let key = "typhoon.\(year).\(slot)"
            guard draw.roll("\(key).comes", in: 0...999) < typhoonChance else { continue }
            let start = first + draw.roll("\(key).start", in: Self.typhoonSeason)
            guard start >= Self.calmDays else { continue }
            let side = max(bounds.width, bounds.height)
            typhoons.append(Typhoon(
                announced: start - draw.roll("\(key).notice", in: 1...3),
                start: start,
                end: start + draw.roll("\(key).days", in: 1...2),
                centre: PlanPoint(x: draw.roll("\(key).x", in: 0...bounds.width), y: draw.roll("\(key).y", in: 0...bounds.height)),
                radius: side * draw.roll("\(key).radius", in: 300...600) / 1_000,
                drop: scaledDrop(800)
            ))
        }
        return typhoons.sorted { $0.start < $1.start }
    }

    /// The fuel spell of game day `day`, or `nil`: each 30-day month after
    /// the first six weeks may have one, 7 to 14 days long, dearer three
    /// times in five (1.12–1.32) and cheaper otherwise (0.88–0.96), half as
    /// far from 1 at the light level.
    public func fuelSpell(onDay day: Int64) -> FuelSpell? {
        guard let seed else { return nil }
        let monthDays = FinancePeriod.month.days
        let month = CompanyAccounts.floorDivide(day, monthDays)
        let draw = SeedDraw(seed: seed)
        let key = "fuel.\(month)"
        guard draw.roll("\(key).comes", in: 0...999) < 300 else { return nil }
        let start = month * monthDays + draw.roll("\(key).start", in: 0...15)
        let spell = FuelSpell(
            start: start,
            end: start + draw.roll("\(key).days", in: 7...14),
            index: {
                let index = draw.roll("\(key).up", in: 0...4) < 3
                    ? draw.roll("\(key).index", in: 1_120...1_320)
                    : draw.roll("\(key).index", in: 880...960)
                return 1_000 + level.scaled(index - 1_000)
            }()
        )
        return start >= Self.fuelCalmDays && spell.isActive(onDay: day) ? spell : nil
    }
}

extension GameWorld {
    // MARK: - Queries

    /// The weather of game day `day` (decision 162).
    public func weather(onDay day: Int64) -> Weather {
        disruptions?.weather(onDay: day) ?? .clear
    }

    /// The typhoons announced and not yet over on game day `day`, by start
    /// (decision 162).
    public func typhoons(onDay day: Int64) -> [Typhoon] {
        guard let disruptions else { return [] }
        // The season is inside the year, notice and all.
        let year = CompanyAccounts.floorDivide(day, FinancePeriod.year.days)
        return disruptions.typhoons(ofYear: year, in: bounds).filter { $0.announced <= day && day < $0.end }
    }

    /// The fuel spell of game day `day`, or `nil` (decision 162).
    public func fuelSpell(onDay day: Int64) -> FuelSpell? {
        disruptions?.fuelSpell(onDay: day)
    }

    /// What game day `day`'s weather takes off the whole network's demand,
    /// in thousandths, at the world's level: 0 on a clear day.
    public func weatherDrop(onDay day: Int64) -> Int64 {
        guard let disruptions else { return 0 }
        return disruptions.scaledDrop(weather(onDay: day).drop)
    }

    /// How much today's weather leaves of the whole network's demand, in
    /// thousandths: 1000 on a clear day.
    var weatherMultiplier: Int64 {
        1_000 - weatherDrop(onDay: dayIndex(of: clock.now))
    }

    /// How much today's typhoons leave of station `id`'s demand, in
    /// thousandths: 1000 where none blows.
    func typhoonMultiplier(at id: StationID) -> Int64 {
        guard disruptions?.seed != nil, let point = station(id: id)?.point else { return 1_000 }
        let day = dayIndex(of: clock.now)
        let drop = typhoons(onDay: day).filter { $0.isActive(onDay: day) && $0.covers(point) }.map(\.drop).max() ?? 0
        return 1_000 - drop
    }
}
