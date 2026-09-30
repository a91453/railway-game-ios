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
/// and end over the day: the four presets of the `Ci/` reference.
public enum StationDemandKind: String, CaseIterable, Codable, Sendable {
    /// Homes: trips leave in the morning and come back in the evening.
    case residential
    /// Workplaces: trips arrive in the morning and leave in the evening.
    case office
    /// Shops: trips arrive and leave around midday and in the evening.
    case shopping
    /// Sights: trips arrive before midday and leave in the afternoon.
    case scenic

    /// How strongly trips leave the station in each hour of the day
    /// (`0..<24`), in thousandths: the reference's `out` curve, normalised
    /// so that the day's mean is 1.
    public var departureShape: [Int64] {
        switch self {
        case .residential: Self.morningPeak
        case .office: Self.eveningPeak
        case .shopping: Self.shoppingDepartures
        case .scenic: Self.scenicDepartures
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

    /// The most trips a day a station can start: keeps every product of
    /// the demand's integer arithmetic well inside an `Int64`.
    public static let maximumDailyTrips: Int64 = 1_000_000

    public init(kind: StationDemandKind, dailyTrips: Int64) {
        self.kind = kind
        self.dailyTrips = dailyTrips
    }

    var isValid: Bool {
        (0...Self.maximumDailyTrips).contains(dailyTrips)
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
}

extension StationDemand: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, dailyTrips
    }

    /// Decodes a demand, rejecting daily trips outside
    /// `0...maximumDailyTrips`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(StationDemandKind.self, forKey: .kind)
        dailyTrips = try container.decode(Int64.self, forKey: .dailyTrips)
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .dailyTrips, in: container, debugDescription: "A station starts 0 to \(Self.maximumDailyTrips) trips a day."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(dailyTrips, forKey: .dailyTrips)
    }
}
