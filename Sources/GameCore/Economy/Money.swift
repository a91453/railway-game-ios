/// An amount of in-game currency, counted in whole units.
///
/// Backed by `Int64` so arithmetic is exact; floating point is never used for
/// authoritative money values.
public struct Money: Hashable, Comparable, Sendable {
    public var amount: Int64

    public init(_ amount: Int64) {
        self.amount = amount
    }

    public static let zero = Money(0)

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount + rhs.amount)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount - rhs.amount)
    }
}

extension Money: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self.init(value)
    }
}

extension Money: Codable {
    /// What every amount decoded is multiplied by: 1, except while
    /// ``SavedGame`` reads a world from before version 76, whose amounts
    /// were dollars and are New Taiwan dollars at 3 to 1 (decision 499).
    @TaskLocal static var decodingScale: Int64 = 1

    /// Decodes an amount, times ``decodingScale``, refusing one the scale
    /// would carry past `Int64`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let amount = try container.decode(Int64.self)
        let (scaled, overflow) = amount.multipliedReportingOverflow(by: Self.decodingScale)
        guard !overflow else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The amount is too large to convert.")
        }
        self.init(scaled)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(amount)
    }
}
