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
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(amount)
    }
}
