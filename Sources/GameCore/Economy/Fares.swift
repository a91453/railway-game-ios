// Fares (G1c, ARCHITECTURE decision 36), ported from the owner's `Ci/`
// reference (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - the network's metro fare rules (`MetroEconomy.setFareRules("metro", …)`
//   from the line-info fare editor): a flat fare, or distance steps
//   (`lineInfoFareModeValue`), with the editor's defaults
//   (`metroFareDefaults().flatFare ?? 5`, `lineInfoFareDefaultDistanceBands`)
//   and the engine's checks (1 to 64 bands, covering every distance without
//   gaps, the last open-ended);
// - a trip's distance: straight from the origin station to the destination
//   (`metroEconomyStationDistanceKmByNetIdx`, a great-circle distance);
// - the legacy minimum: a fare of 0 or less is charged as 5
//   (`metroEconomyAccrueHourlyFare`);
// - the fare's effect on demand (`metroFareDemandPenaltyForFare`, against
//   `METRO_FARE_DEMAND_BASELINE_USD = 0.75`), as a table.
//
// Money is in cents of the reference's dollar (decision 36): its fares
// have two decimals (0.55 to 1.20 a band).

/// Whether the company keeps accounts (the reference's `economyMode`):
/// `free` builds without fares or running costs, `management` charges both.
/// A new world is free, so every rule before G1c holds unchanged; a new game
/// in the app is managed.
public enum EconomyMode: String, CaseIterable, Codable, Sendable {
    case free
    case management
}

/// One step of a distance fare: trips from `fromMeters` up to (not
/// including) `toMeters` pay `fare`; the last step has no end.
public struct FareBand: Hashable, Sendable {
    public let fromMeters: Int64
    public let toMeters: Int64?
    public let fare: Money

    public init(fromMeters: Int64, toMeters: Int64?, fare: Money) {
        self.fromMeters = fromMeters
        self.toMeters = toMeters
        self.fare = fare
    }
}

/// How the network's metro trips are priced (the reference's fare modes):
/// one fare for every trip, or a fare by the trip's straight-line distance.
public enum FareRules: Hashable, Sendable {
    case flat(Money)
    case distance([FareBand])

    /// The editor's flat fare: 5.
    public static let standard = FareRules.flat(500)

    /// The editor's distance steps (`lineInfoFareDefaultDistanceBands`):
    /// 0.55 to 6 km, 0.70 to 12, 0.85 to 22, 1.00 to 32, 1.20 beyond.
    public static let standardBands: [FareBand] = [
        FareBand(fromMeters: 0, toMeters: 6_000, fare: 55),
        FareBand(fromMeters: 6_000, toMeters: 12_000, fare: 70),
        FareBand(fromMeters: 12_000, toMeters: 22_000, fare: 85),
        FareBand(fromMeters: 22_000, toMeters: 32_000, fare: 100),
        FareBand(fromMeters: 32_000, toMeters: nil, fare: 120),
    ]

    /// The most steps the engine takes.
    public static let maximumBands = 64
    /// The highest fare and distance a rule may name: far beyond any game,
    /// and small enough that every product below fits an `Int64`.
    public static let maximumFare: Money = 1_000_000_000
    public static let maximumMeters: Int64 = 10_000_000

    /// Whether the engine would take these rules: fares from 0 to
    /// ``maximumFare``; for distance steps, 1 to ``maximumBands`` of them,
    /// the first from 0, each starting where the one before ends and ending
    /// no earlier than it starts (the editor's `toKm ≥ fromKm`), all within
    /// ``maximumMeters``, and only the last without an end.
    public var isValid: Bool {
        switch self {
        case .flat(let fare):
            return (.zero...Self.maximumFare).contains(fare)
        case .distance(let bands):
            guard (1...Self.maximumBands).contains(bands.count), bands[0].fromMeters == 0 else { return false }
            for (index, band) in bands.enumerated() {
                guard (.zero...Self.maximumFare).contains(band.fare), (0...Self.maximumMeters).contains(band.fromMeters) else { return false }
                if index == bands.count - 1 {
                    guard band.toMeters == nil else { return false }
                } else {
                    guard let to = band.toMeters, to >= band.fromMeters, to <= Self.maximumMeters, bands[index + 1].fromMeters == to else { return false }
                }
            }
            return true
        }
    }

    /// The fare of a trip whose straight-line distance is
    /// `√squaredDistance` world units (1/64 m): the flat fare, or the step
    /// whose `fromMeters ≤ distance < toMeters`, compared exactly on the
    /// squares.
    public func fare(squaredDistance: Int64) -> Money {
        switch self {
        case .flat(let fare):
            return fare
        case .distance(let bands):
            for band in bands {
                guard let to = band.toMeters else { return band.fare }
                let limit = to * Self.unitsPerMeter
                if squaredDistance < limit * limit { return band.fare }
            }
            return bands.last?.fare ?? .zero
        }
    }

    static let unitsPerMeter: Int64 = 64

    /// The fare charged for a trip of the rule's fare `fare`: the legacy
    /// path charges 5 for a fare of 0 or less.
    static func charged(_ fare: Money) -> Money {
        fare > .zero ? fare : standardMinimum
    }

    static let standardMinimum: Money = 500
}

extension FareRules {
    // MARK: Demand

    /// The fare the reference's demand compares fares with
    /// (`METRO_FARE_DEMAND_BASELINE_USD`): 0.75. The reference has one for
    /// each real city; the game has no city, so it keeps the default.
    public static let demandBaseline: Money = 75

    /// How much of a pair's demand a fare of `fare` keeps, in thousandths
    /// (`metroFareDemandPenaltyForFare` against ``demandBaseline``): 1080
    /// for a free trip, rising to 1000 at the baseline, then falling with
    /// `exp(−0.72·(a − 1)^1.35)`, and faster from 4 times the baseline, never
    /// below 10. GameCore has no `exp`: the curve is a table at every 0.05
    /// of the ratio, interpolated linearly (within 1.6 thousandths of the
    /// formula; `EconomyAccountsTests` checks it).
    public static func demandFactor(fare: Money) -> Int64 {
        guard fare > .zero else { return 1_080 }
        // The ratio fare / baseline in thousandths, rounded down.
        let ratio = fare.amount * 1_000 / demandBaseline.amount
        let index = ratio / 50
        guard index < Int64(demandTable.count - 1) else { return demandTable[demandTable.count - 1] }
        let into = ratio % 50
        let lower = demandTable[Int(index)]
        let upper = demandTable[Int(index) + 1]
        return (lower * (50 - into) + upper * into) / 50
    }

    /// `metroFareDemandPenaltyForFare` at ratios 0, 0.05, …, 4.7, in
    /// thousandths rounded half up.
    static let demandTable: [Int64] = [
        1080, 1076, 1072, 1068, 1064, 1060, 1056, 1052, 1048, 1044, 1040, 1036, 1032, 1028, 1024, 1020, 1016, 1012, 1008, 1004,
        1000, 987, 968, 946, 921, 895, 868, 840, 811, 783, 754, 725, 697, 669, 641, 614, 587, 561, 536, 511,
        487, 463, 441, 419, 398, 378, 358, 340, 322, 305, 288, 272, 257, 243, 229, 216, 204, 192, 180, 170,
        160, 150, 141, 132, 124, 116, 109, 102, 96, 89, 84, 78, 73, 68, 64, 60, 56, 52, 48, 45,
        42, 37, 33, 30, 26, 24, 21, 19, 17, 15, 13, 12, 10, 10, 10,
    ]
}

extension FareBand: Codable {
    private enum CodingKeys: String, CodingKey {
        case fromMeters, toMeters, fare
    }

    /// Decodes a step; one without an end has no `"toMeters"` (an explicit
    /// `null` is rejected). Whether the steps fit together is checked by
    /// ``FareRules``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromMeters = try container.decode(Int64.self, forKey: .fromMeters)
        toMeters = container.contains(.toMeters) ? try container.decode(Int64.self, forKey: .toMeters) : nil
        fare = try container.decode(Money.self, forKey: .fare)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromMeters, forKey: .fromMeters)
        if let toMeters {
            try container.encode(toMeters, forKey: .toMeters)
        }
        try container.encode(fare, forKey: .fare)
    }
}

extension FareRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, fare, bands
    }

    /// Decodes `{"mode": "flat", "fare"}` or `{"mode": "distance",
    /// "bands"}`, rejecting rules ``isValid`` refuses.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        switch mode {
        case "flat": self = try .flat(container.decode(Money.self, forKey: .fare))
        case "distance": self = try .distance(container.decode([FareBand].self, forKey: .bands))
        default: throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "Unknown fare mode \"\(mode)\".")
        }
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "Fare rules out of range or with gaps.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .flat(let fare):
            try container.encode("flat", forKey: .mode)
            try container.encode(fare, forKey: .fare)
        case .distance(let bands):
            try container.encode("distance", forKey: .mode)
            try container.encode(bands, forKey: .bands)
        }
    }
}
