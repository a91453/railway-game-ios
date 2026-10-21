// Station demand (G1a, ARCHITECTURE decision 34): what kind of place a
// station serves and how many trips start there a day. The hourly shapes
// port the owner's `Ci/` reference (`buildStationFlowPresetCurves` and
// `normalizeStationFlowPresetRowToDailyBase`, with the reference's default
// hour domain 0–23 and no server base, in
// `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`) to whole
// thousandths. GameCore has no `exp`, so the Gaussian curves are worked out
// once and kept as tables; `StationDemandTests` recomputes every entry from
// the reference formula.

/// The kind of place a station serves, which shapes when its trips start
/// and end over the day: the four presets of the `Ci/` reference, and
/// schools and public services (decision 91, this project's: the reference
/// has no such preset).
public enum StationDemandKind: String, CaseIterable, Codable, Sendable {
    /// Homes: trips leave in the morning and come back in the evening.
    case residential
    /// Workplaces: trips arrive in the morning and leave in the evening.
    case office
    /// Shops: trips arrive and leave around midday and in the evening.
    case shopping
    /// Sights: trips arrive before midday and leave in the afternoon.
    case scenic
    /// Schools, hospitals and public offices (decision 91): trips arrive
    /// early in the morning and leave in the afternoon, before the evening
    /// rush.
    case civic

    /// How strongly trips leave the station in each hour of the day
    /// (`0..<24`), in thousandths: the reference's `out` curve, normalised
    /// so that the day's mean is 1.
    public var departureShape: [Int64] {
        switch self {
        case .residential: Self.morningPeak
        case .office: Self.eveningPeak
        case .shopping: Self.shoppingDepartures
        case .scenic: Self.scenicDepartures
        case .civic: Self.civicDepartures
        }
    }

    /// How strongly trips arrive at the station in each hour of the day, in
    /// thousandths: the reference's `in` curve, normalised the same way.
    public var arrivalShape: [Int64] {
        switch self {
        case .residential: Self.eveningPeak
        case .office: Self.morningPeak
        case .shopping: Self.shoppingArrivals
        case .scenic: Self.scenicArrivals
        case .civic: Self.civicArrivals
        }
    }

    // `1 + 0.6·g(h; 8, 1.15)` and `1 + 0.6·g(h; 18, 1.15)`, where
    // `g(h; μ, σ) = exp(−½((h − μ)/σ)²)`.
    static let morningPeak: [Int64] = [
        933, 933, 933, 933, 934, 951, 1056, 1316, 1492, 1316, 1056, 951,
        934, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933,
    ]
    static let eveningPeak: [Int64] = [
        933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933,
        933, 933, 934, 951, 1056, 1316, 1492, 1316, 1056, 951, 934, 933,
    ]
    // Tidal demand (decision 319, this project's: the reference has none),
    // fitted to Taipei Metro's homes and offices of 2025:
    // `(1 + 1.9·g(h; 8, 0.8))·(1 − 0.8·g(h; 18, 2))` and
    // `(1 + 1.9·g(h; 18, 2))·(1 − 0.8·g(h; 8, 0.8))`, each normalised so
    // that the day's mean is 1. A home's trips leave in the first and come
    // back in the second, and hardly the other way round.
    static let tidalMorning: [Int64] = [
        1008, 1008, 1008, 1008, 1008, 1010, 1092, 1885, 2923, 1885, 1092, 1008,
        999, 973, 899, 746, 519, 296, 202, 296, 519, 746, 899, 973,
    ]
    static let tidalEvening: [Int64] = [
        752, 752, 752, 752, 752, 752, 726, 477, 150, 477, 726, 755,
        768, 815, 946, 1217, 1620, 2014, 2182, 2014, 1620, 1217, 946, 815,
    ]
    // `1 + 0.42·g(h; 14, 2.4) + 0.5·g(h; 19, 1.8)`.
    static let shoppingDepartures: [Int64] = [
        834, 834, 834, 834, 834, 835, 836, 839, 850, 874, 922, 995,
        1082, 1157, 1193, 1191, 1186, 1220, 1279, 1291, 1207, 1064, 940, 870,
    ]
    // `1 + 0.42·g(h; 13, 2.4) + 0.5·g(h; 18, 1.8)`.
    static let shoppingArrivals: [Int64] = [
        834, 834, 834, 834, 834, 835, 839, 849, 874, 921, 994, 1082,
        1157, 1193, 1190, 1185, 1219, 1279, 1291, 1207, 1064, 939, 870, 843,
    ]
    // Decision 91, the presets' form with this project's hours (gap):
    // `1 + 0.6·g(h; 7, 1.15)` arriving, a school's or a hospital's day
    // starting before the offices', and `1 + 0.6·g(h; 16, 1.15)` leaving,
    // as classes end.
    static let civicArrivals: [Int64] = [
        933, 933, 933, 934, 951, 1056, 1316, 1492, 1316, 1056, 951, 934,
        933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933,
    ]
    static let civicDepartures: [Int64] = [
        933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933, 933,
        934, 951, 1056, 1316, 1492, 1316, 1056, 951, 934, 933, 933, 933,
    ]
    // `1 + 0.75·g(h; 16, 2.1)`.
    static let scenicDepartures: [Int64] = [
        859, 859, 859, 859, 859, 859, 859, 859, 859, 861, 870, 897,
        964, 1091, 1268, 1434, 1503, 1434, 1268, 1091, 964, 897, 870, 861,
    ]
    // `1 + 0.75·g(h; 11, 2.1)`.
    static let scenicArrivals: [Int64] = [
        859, 859, 859, 859, 861, 870, 897, 964, 1091, 1268, 1434, 1503,
        1434, 1268, 1091, 964, 897, 870, 861, 859, 859, 859, 859, 859,
    ]
}

/// How many trips start at a station each day, and what kind of place it
/// serves (G1a). A station without demand neither starts nor draws trips.
public struct StationDemand: Hashable, Sendable {
    public let kind: StationDemandKind
    /// Trips that start at the station each day, in
    /// `0...maximumDailyTrips`. They are shared among the stations the lines
    /// reach from it, in proportion to those stations' own daily trips (see
    /// ``GameWorld/dailyDemand(from:to:)``).
    public let dailyTrips: Int64
    /// The people of a high-speed station's hinterland (decision 168): the
    /// residents and jobs within ``HighSpeed/hinterlandRadius`` of it that
    /// no other high-speed station is nearer to, in
    /// `0...maximumHinterland`. They make the intercity trips between it and
    /// the other high-speed stations (``HighSpeed/pairTrips(_:_:)``), which
    /// are not part of its ``dailyTrips``. 0 for any other station.
    public let hinterland: Int64
    /// How much a home rather than a workplace the station is, in
    /// thousandths, for tidal demand (decision 319): 1000 a home, whose
    /// trips leave in the morning and come back in the evening, 0 a
    /// workplace, the other way round. Demand from land sets it from the
    /// station's residents and jobs (``LandDemand/Share/homeShare``);
    /// `nil` follows the station's kind, as a demand the player sets does.
    public let homeShare: Int64?

    /// The most trips a day a station can start: keeps every product of
    /// the demand's integer arithmetic well inside an `Int64`.
    public static let maximumDailyTrips: Int64 = 1_000_000
    /// The most people a hinterland can have (a hundred million, far beyond
    /// any real one), small enough that every product of the intercity
    /// trips' arithmetic fits an `Int64`.
    public static let maximumHinterland: Int64 = 100_000_000

    public init(kind: StationDemandKind, dailyTrips: Int64, hinterland: Int64 = 0, homeShare: Int64? = nil) {
        self.kind = kind
        self.dailyTrips = dailyTrips
        self.hinterland = hinterland
        self.homeShare = homeShare
    }

    var isValid: Bool {
        (0...Self.maximumDailyTrips).contains(dailyTrips) && (0...Self.maximumHinterland).contains(hinterland)
            && (homeShare.map { (0...1_000).contains($0) } ?? true)
    }

    /// How strongly trips leave the station in each hour of the day, in
    /// thousandths: its kind's ``StationDemandKind/departureShape``, or on
    /// a working day with tidal demand (decision 319) its ``homeShare``'s
    /// blend of the tidal morning and evening (a home's and a
    /// workplace's for one without, by its kind; any other kind keeps its
    /// own hours).
    public func departureShape(tidal: Bool) -> [Int64] {
        guard tidal, let home = tidalHomeShare else { return kind.departureShape }
        return Self.blend(StationDemandKind.tidalMorning, StationDemandKind.tidalEvening, home)
    }

    /// How strongly trips arrive at the station in each hour of the day,
    /// as ``departureShape(tidal:)`` with the morning and evening swapped.
    public func arrivalShape(tidal: Bool) -> [Int64] {
        guard tidal, let home = tidalHomeShare else { return kind.arrivalShape }
        return Self.blend(StationDemandKind.tidalEvening, StationDemandKind.tidalMorning, home)
    }

    /// The home share tidal demand uses: ``homeShare``, else 1000 for a
    /// home and 0 for a workplace; `nil` for any other kind.
    var tidalHomeShare: Int64? {
        if let homeShare { return homeShare }
        switch kind {
        case .residential: return 1_000
        case .office: return 0
        case .shopping, .scenic, .civic: return nil
        }
    }

    /// `home` thousandths of `first` and the rest of `second`, rounded
    /// half up.
    static func blend(_ first: [Int64], _ second: [Int64], _ home: Int64) -> [Int64] {
        zip(first, second).map { ($0 * home + $1 * (1_000 - home) + 500) / 1_000 }
    }

    /// How busy each hour of the day is for every trip, in thousandths:
    /// `PARAMS.PEAK_FACTOR` of the `Ci/` reference (0.1 at night, 1.5 in
    /// the rush hours and 1.8 at 08:00 and 18:00, `0.6 + 0.02·h` in between).
    /// It stands in for the server's hourly base, which the reference
    /// snapshot does not have.
    public static let dayShape: [Int64] = [
        100, 100, 100, 100, 100, 100, 720, 1500, 1800, 1500, 800, 820,
        840, 860, 880, 900, 1500, 1500, 1800, 1500, 1000, 1020, 1040, 100,
    ]

    /// How busy each hour of a weekend day is, in thousandths, for a world
    /// with weekly demand: ``dayShape`` times the reference's weekend hourly
    /// factor over its weekday one (`H_FACTOR_WE[h] / H_FACTOR_WD[h]`),
    /// rounded half up. Weekends start later and have no rush hours.
    public static let weekendShape: [Int64] = [
        67, 75, 83, 80, 75, 38, 216, 417, 741, 1350, 1257, 1523,
        1365, 1474, 1509, 1238, 1375, 1059, 1440, 1500, 1000, 1020, 1300, 150,
    ]

    /// How busy each hour of a working day is with tidal demand (decision
    /// 319), in thousandths: ``dayShape`` with the night after 01:00 all
    /// but empty, as a metro's closed gates are, a quieter 06:00 and 23:00,
    /// and a busier midday (1200 from 10:00 to 15:00), so that with the
    /// tidal hours a line of homes and offices keeps Taipei Metro's
    /// working day of 2025 (research
    /// RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md §2.5).
    public static let tidalDayShape: [Int64] = [
        200, 10, 10, 10, 10, 10, 450, 1500, 1800, 1500, 1200, 1200,
        1200, 1200, 1200, 1200, 1500, 1500, 1800, 1500, 1000, 1020, 1040, 450,
    ]

    /// How busy each hour of a weekend day or holiday is with tidal demand
    /// (decision 319), in thousandths: Taipei Metro's days off of 2025 for
    /// a line of homes and offices with their kinds' hours (a day off has
    /// no tide), a late morning and an empty night.
    public static let tidalWeekendShape: [Int64] = [
        160, 10, 10, 10, 10, 10, 260, 410, 585, 850, 1320, 1775,
        1840, 2005, 2035, 1995, 1935, 1720, 1305, 1195, 1355, 1465, 1190, 550,
    ]

    /// Each weekday's share of a week's trips, in thousandths of a day's,
    /// Sunday first: the reference's `METRO_WEEKDAY_FACTORS`
    /// (0.84, 1.04, 1.02, 1.02, 1.04, 1.12, 0.92), which add up to a week of
    /// seven days.
    public static let weekdayFactors: [Int64] = [840, 1_040, 1_020, 1_020, 1_040, 1_120, 920]

    /// The weekday of game day `day`, 0 for Sunday to 6 for Saturday: a
    /// game starts on a Monday.
    public static func weekday(ofDay day: Int64) -> Int {
        Int(((day + 1) % 7 + 7) % 7)
    }

    /// Whether game day `day` is a Saturday or a Sunday (the reference's
    /// `isWeekend`, `[0, 6].includes(simDay % 7)`).
    public static func isWeekend(day: Int64) -> Bool {
        let weekday = weekday(ofDay: day)
        return weekday == 0 || weekday == 6
    }

    /// A station's trips on game day `day`: its daily trips times the
    /// day's ``weekdayFactors``, rounded half up.
    public func trips(onDay day: Int64) -> Int64 {
        Self.trips(dailyTrips, onDay: day)
    }

    /// `trips` a day times the day's ``weekdayFactors``, rounded half up.
    static func trips(_ trips: Int64, onDay day: Int64) -> Int64 {
        (trips * Self.weekdayFactors[Self.weekday(ofDay: day)] + 500) / 1_000
    }
}

extension StationDemand: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, dailyTrips, hinterland, homeShare
    }

    /// Decodes a demand, rejecting daily trips outside
    /// `0...maximumDailyTrips`. A station with no hinterland (decision 168,
    /// save version 43) has no `"hinterland"`, which is also how demands
    /// saved before it read; one without a home share (decision 319, save
    /// version 67) has no `"homeShare"`, which must be 0 to 1000.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(StationDemandKind.self, forKey: .kind)
        dailyTrips = try container.decode(Int64.self, forKey: .dailyTrips)
        hinterland = try container.decodeIfPresent(Int64.self, forKey: .hinterland) ?? 0
        homeShare = try container.decodeIfPresent(Int64.self, forKey: .homeShare)
        guard (0...Self.maximumDailyTrips).contains(dailyTrips) else {
            throw DecodingError.dataCorruptedError(
                forKey: .dailyTrips, in: container, debugDescription: "A station starts 0 to \(Self.maximumDailyTrips) trips a day."
            )
        }
        guard (0...Self.maximumHinterland).contains(hinterland) else {
            throw DecodingError.dataCorruptedError(
                forKey: .hinterland, in: container, debugDescription: "A hinterland has 0 to \(Self.maximumHinterland) people."
            )
        }
        guard homeShare.map({ (0...1_000).contains($0) }) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .homeShare, in: container, debugDescription: "A home share is 0 to 1000 thousandths."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(dailyTrips, forKey: .dailyTrips)
        if hinterland != 0 {
            try container.encode(hinterland, forKey: .hinterland)
        }
        try container.encodeIfPresent(homeShare, forKey: .homeShare)
    }
}
