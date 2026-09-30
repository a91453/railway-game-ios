/// A non-negative 128-bit integer, for the few exact computations whose
/// intermediate products do not fit in 64 bits (the running curve of Stage
/// W1, ARCHITECTURE decision 33). Built only on the standard library's
/// full-width multiply and divide, so every result is the same on every
/// platform; `UInt128` is not used because the app still supports systems
/// that do not have it.
///
/// Every operation traps on overflow or on a negative result, like the
/// standard integer operators: callers keep their values inside documented
/// bounds, and a trap means a bound was wrong.
struct WideInteger: Hashable, Comparable, Sendable {
    let high: UInt64
    let low: UInt64

    init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    init(_ value: UInt64) {
        self.init(high: 0, low: value)
    }

    /// `value`, which must not be negative.
    init(_ value: Int64) {
        precondition(value >= 0, "WideInteger holds non-negative values")
        self.init(UInt64(value))
    }

    /// `a × b`, exactly.
    static func product(_ a: UInt64, _ b: UInt64) -> WideInteger {
        let (high, low) = a.multipliedFullWidth(by: b)
        return WideInteger(high: high, low: low)
    }

    /// `a × b` for non-negative `a` and `b`, exactly.
    static func product(_ a: Int64, _ b: Int64) -> WideInteger {
        precondition(a >= 0 && b >= 0, "WideInteger holds non-negative values")
        return product(UInt64(a), UInt64(b))
    }

    /// The value, which must fit in an `Int64`.
    var int64: Int64 {
        precondition(high == 0 && low <= UInt64(Int64.max), "WideInteger value does not fit in an Int64")
        return Int64(low)
    }

    static func < (lhs: WideInteger, rhs: WideInteger) -> Bool {
        lhs.high != rhs.high ? lhs.high < rhs.high : lhs.low < rhs.low
    }

    static func + (lhs: WideInteger, rhs: WideInteger) -> WideInteger {
        let (low, carry) = lhs.low.addingReportingOverflow(rhs.low)
        return WideInteger(high: lhs.high + rhs.high + (carry ? 1 : 0), low: low)
    }

    /// `lhs − rhs`; `rhs` must not be greater than `lhs`.
    static func - (lhs: WideInteger, rhs: WideInteger) -> WideInteger {
        precondition(rhs <= lhs, "WideInteger holds non-negative values")
        let (low, borrow) = lhs.low.subtractingReportingOverflow(rhs.low)
        return WideInteger(high: lhs.high - rhs.high - (borrow ? 1 : 0), low: low)
    }

    /// The value times `factor`, exactly.
    func multiplied(by factor: UInt64) -> WideInteger {
        let (lowHigh, lowLow) = low.multipliedFullWidth(by: factor)
        let (highHigh, highLow) = high.multipliedFullWidth(by: factor)
        precondition(highHigh == 0, "WideInteger multiplication overflows")
        let (sum, carry) = highLow.addingReportingOverflow(lowHigh)
        precondition(!carry, "WideInteger multiplication overflows")
        return WideInteger(high: sum, low: lowLow)
    }

    /// The value times `factor`, which must not be negative, exactly.
    func multiplied(by factor: Int64) -> WideInteger {
        precondition(factor >= 0, "WideInteger holds non-negative values")
        return multiplied(by: UInt64(factor))
    }

    /// ⌊value ÷ divisor⌋, by long division in two 64-bit steps.
    func dividedRoundingDown(by divisor: UInt64) -> WideInteger {
        precondition(divisor > 0, "WideInteger division needs a positive divisor")
        let highQuotient = high / divisor
        let (lowQuotient, _) = divisor.dividingFullWidth((high % divisor, low))
        return WideInteger(high: highQuotient, low: lowQuotient)
    }

    /// ⌊value ÷ divisor⌋ for a positive `divisor`.
    func dividedRoundingDown(by divisor: Int64) -> WideInteger {
        precondition(divisor > 0, "WideInteger division needs a positive divisor")
        return dividedRoundingDown(by: UInt64(divisor))
    }

    /// The value times 2^`shift`, exactly; `0 <= shift < 64`.
    func shiftedLeft(by shift: Int) -> WideInteger {
        precondition(shift >= 0 && shift < 64, "WideInteger shifts by 0..<64")
        guard shift > 0 else { return self }
        precondition(high >> (64 - shift) == 0, "WideInteger shift overflows")
        return WideInteger(high: high << shift | low >> (64 - shift), low: low << shift)
    }

    /// ⌊value ÷ 2^`shift`⌋; `0 <= shift < 64`.
    func shiftedRight(by shift: Int) -> WideInteger {
        precondition(shift >= 0 && shift < 64, "WideInteger shifts by 0..<64")
        guard shift > 0 else { return self }
        return WideInteger(high: high >> shift, low: low >> shift | high << (64 - shift))
    }

    /// ⌊√value⌋, by the binary digit-by-digit method (the 128-bit form of
    /// ``FixedPoint/squareRoot(_:)``).
    func squareRoot() -> UInt64 {
        var remainder = self
        var root = WideInteger(0 as UInt64)
        var bit = WideInteger(high: 1 << 62, low: 0)
        while remainder < bit {
            bit = bit.shiftedRight(by: 2)
        }
        while bit != WideInteger(0 as UInt64) {
            let candidate = root + bit
            if remainder >= candidate {
                remainder = remainder - candidate
                root = root.shiftedRight(by: 1) + bit
            } else {
                root = root.shiftedRight(by: 1)
            }
            bit = bit.shiftedRight(by: 2)
        }
        precondition(root.high == 0, "a 128-bit square root fits in 64 bits")
        return root.low
    }
}
