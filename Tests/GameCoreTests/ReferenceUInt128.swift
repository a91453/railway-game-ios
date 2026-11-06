/// An unsigned 128-bit integer for the reference models in these tests.
///
/// Swift's own `UInt128` needs macOS 15 or iOS 18, and the package still
/// supports macOS 14 and iOS 17, so `ReferenceTrafficCurve` uses this
/// instead. It has only the operations that model uses and behaves like
/// `UInt128` in them: `+`, `-`, `*` and `/` trap on overflow, underflow and
/// division by zero; `<<` and `>>` drop the bits shifted out; converting a
/// negative value or a value that does not fit traps.
/// `ReferenceUInt128Tests` checks it against the native type where that exists.
struct ReferenceUInt128: Comparable, ExpressibleByIntegerLiteral {
    var high: UInt64
    var low: UInt64

    init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    init(integerLiteral value: UInt64) {
        self.init(high: 0, low: value)
    }

    init<T: BinaryInteger>(_ value: T) {
        self.init(high: 0, low: UInt64(value))
    }

    static func < (a: Self, b: Self) -> Bool {
        a.high != b.high ? a.high < b.high : a.low < b.low
    }

    static func + (a: Self, b: Self) -> Self {
        let (low, carry) = a.low.addingReportingOverflow(b.low)
        let (sum, first) = a.high.addingReportingOverflow(b.high)
        let (high, second) = sum.addingReportingOverflow(carry ? 1 : 0)
        precondition(!first && !second, "ReferenceUInt128 overflow")
        return Self(high: high, low: low)
    }

    static func - (a: Self, b: Self) -> Self {
        let (low, borrow) = a.low.subtractingReportingOverflow(b.low)
        let (difference, first) = a.high.subtractingReportingOverflow(b.high)
        let (high, second) = difference.subtractingReportingOverflow(borrow ? 1 : 0)
        precondition(!first && !second, "ReferenceUInt128 underflow")
        return Self(high: high, low: low)
    }

    static func * (a: Self, b: Self) -> Self {
        precondition(a.high == 0 || b.high == 0, "ReferenceUInt128 overflow")
        let (carry, low) = a.low.multipliedFullWidth(by: b.low)
        let (left, first) = a.high.multipliedReportingOverflow(by: b.low)
        let (right, second) = a.low.multipliedReportingOverflow(by: b.high)
        let (cross, third) = left.addingReportingOverflow(right)
        let (high, fourth) = carry.addingReportingOverflow(cross)
        precondition(!first && !second && !third && !fourth, "ReferenceUInt128 overflow")
        return Self(high: high, low: low)
    }

    static func / (a: Self, b: Self) -> Self {
        precondition(b != 0, "ReferenceUInt128 division by zero")
        if b.high == 0 {
            let divisor = b.low
            let (rest, _) = divisor.dividingFullWidth((a.high % divisor, a.low))
            return Self(high: a.high / divisor, low: rest)
        }
        // A divisor of 2^64 or more leaves a quotient below 2^64.
        var remainder = a, quotient: UInt64 = 0
        for shift in stride(from: b.high.leadingZeroBitCount, through: 0, by: -1) {
            let part = b << shift
            if remainder >= part {
                remainder = remainder - part
                quotient |= 1 << UInt64(shift)
            }
        }
        return Self(high: 0, low: quotient)
    }

    static func << (a: Self, shift: Int) -> Self {
        if shift < 0 { return a >> -shift }
        if shift >= 128 { return 0 }
        if shift >= 64 { return Self(high: a.low << UInt64(shift - 64), low: 0) }
        if shift == 0 { return a }
        return Self(high: a.high << UInt64(shift) | a.low >> UInt64(64 - shift), low: a.low << UInt64(shift))
    }

    static func >> (a: Self, shift: Int) -> Self {
        if shift < 0 { return a << -shift }
        if shift >= 128 { return 0 }
        if shift >= 64 { return Self(high: 0, low: a.high >> UInt64(shift - 64)) }
        if shift == 0 { return a }
        return Self(high: a.high >> UInt64(shift), low: a.low >> UInt64(shift) | a.high << UInt64(64 - shift))
    }

    static func += (a: inout Self, b: Self) { a = a + b }
    static func -= (a: inout Self, b: Self) { a = a - b }
    static func >>= (a: inout Self, shift: Int) { a = a >> shift }
}

extension Int64 {
    /// Traps when the value does not fit, as `Int64(_: UInt128)` does.
    init(_ value: ReferenceUInt128) {
        precondition(value.high == 0, "ReferenceUInt128 does not fit in Int64")
        self.init(value.low)
    }
}
