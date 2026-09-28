/// Prices for things the player can build or buy.
///
/// Prices are never negative: spending a negative amount is a programming
/// error (see ``GameEconomy/spend(_:)``), and decoding refuses one.
public struct ConstructionCosts: Hashable, Codable, Sendable {
    public var track: Money
    public var station: Money
    public var train: Money

    public init(track: Money, station: Money, train: Money) {
        self.track = track
        self.station = station
        self.train = train
    }

    /// Placeholder prices until balancing work starts.
    public static let standard = ConstructionCosts(track: 1_000, station: 50_000, train: 200_000)
}

extension ConstructionCosts {
    private enum CodingKeys: String, CodingKey {
        case track, station, train
    }

    /// Decodes prices, rejecting a negative one: spending a negative amount is
    /// a programming error (see ``GameEconomy/spend(_:)``), so a save holding
    /// one would load and then trap at the next purchase.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func price(_ key: CodingKeys) throws -> Money {
            let price = try container.decode(Money.self, forKey: key)
            guard price >= .zero else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Construction costs must not be negative.")
            }
            return price
        }
        self.init(track: try price(.track), station: try price(.station), train: try price(.train))
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
}
