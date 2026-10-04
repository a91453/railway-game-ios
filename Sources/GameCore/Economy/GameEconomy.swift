/// Prices for things the player can build or buy.
///
/// Prices are never negative: spending a negative amount is a programming
/// error (see ``GameEconomy/spend(_:)``), and decoding refuses one.
public struct ConstructionCosts: Hashable, Codable, Sendable {
    /// Each ``trackPricingLength`` of a track's length, or part of one
    /// (times its structure's ``TrackStructure/costFactor``).
    public var track: Money
    public var station: Money
    /// A new train, with its first car.
    public var train: Money
    /// Each car added to a train (``GameWorld/setTrainCars(_:to:)``), as the
    /// reference's management mode spends its car quota (`metro.cars`).
    /// 0, cars for nothing, in worlds from before it.
    public var car: Money

    public init(track: Money, station: Money, train: Money, car: Money = .zero) {
        self.track = track
        self.station = station
        self.train = train
        self.car = car
    }

    /// The length of track ``track`` is the price of: 1024 units, 16 m.
    /// Track has cost this much a 16 m since the first track was laid, when
    /// that was a tile's width; it is only a price now (Stage F3d).
    public static let trackPricingLength: Int64 = 1_024

    /// GameCore's prices for its own new worlds and tests. The app's new
    /// game sets its own (`GameWorld.newGame()`, ARCHITECTURE decision 46).
    public static let standard = ConstructionCosts(track: 1_000, station: 50_000, train: 200_000)
}

extension ConstructionCosts {
    private enum CodingKeys: String, CodingKey {
        case track, station, train, car
    }

    /// Decodes prices, rejecting a negative one: spending a negative amount is
    /// a programming error (see ``GameEconomy/spend(_:)``), so a save holding
    /// one would load and then trap at the next purchase. A save without
    /// `"car"` adds cars for nothing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func price(_ key: CodingKeys) throws -> Money {
            let price = try container.decode(Money.self, forKey: key)
            guard price >= .zero else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Construction costs must not be negative.")
            }
            return price
        }
        let car = container.contains(.car) ? try price(.car) : .zero
        self.init(track: try price(.track), station: try price(.station), train: try price(.train), car: car)
    }

    /// Writes `"car"` only when cars cost something, so a world whose cars
    /// are free saves as before.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(track, forKey: .track)
        try container.encode(station, forKey: .station)
        try container.encode(train, forKey: .train)
        if car != .zero {
            try container.encode(car, forKey: .car)
        }
    }
}

/// The player's finances.
public struct GameEconomy: Hashable, Codable, Sendable {
    public private(set) var balance: Money
    public let costs: ConstructionCosts

    public init(balance: Money, costs: ConstructionCosts = .standard) {
        self.balance = balance
        self.costs = costs
    }

    public func canAfford(_ amount: Money) -> Bool {
        amount <= balance
    }

    /// Deducts `amount`, leaving the balance untouched on failure.
    ///
    /// - Throws: ``GameError/insufficientFunds(required:available:)`` if the
    ///   balance is lower than `amount`.
    public mutating func spend(_ amount: Money) throws(GameError) {
        precondition(amount >= .zero, "spend(_:) requires a non-negative amount")
        guard canAfford(amount) else {
            throw .insufficientFunds(required: amount, available: balance)
        }
        balance = balance - amount
    }

    public mutating func earn(_ amount: Money) {
        precondition(amount >= .zero, "earn(_:) requires a non-negative amount")
        balance = balance + amount
    }

    /// Moves the balance by a settlement's `amount`, either way; it may go
    /// below zero (the reference settles running costs with
    /// `allowNegativeBalance`; G1c, ARCHITECTURE decision 36).
    mutating func settle(_ amount: Money) {
        balance = balance + amount
    }
}
