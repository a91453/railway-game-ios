/// Exact integer arithmetic for the track geometry (ARCHITECTURE decision
/// 29). Every result is the same on every platform and in every language
/// with 64-bit integers: nothing here uses floating point.
enum FixedPoint {
    /// ⌊√n⌋, the largest integer whose square is at most `n`, by the
    /// binary digit-by-digit method.
    ///
    /// - Precondition: `n >= 0`.
    static func squareRoot(_ n: Int64) -> Int64 {
        precondition(n >= 0, "squareRoot(_:) needs a non-negative value")
        var remainder = UInt64(n)
        var root: UInt64 = 0
        var bit: UInt64 = 1 << 62
        while bit > remainder {
            bit >>= 2
        }
        while bit != 0 {
            if remainder >= root + bit {
                remainder -= root + bit
                root = (root >> 1) + bit
            } else {
                root >>= 1
            }
            bit >>= 2
        }
        return Int64(root)
    }

    /// √n rounded to the nearest integer. For an integer `n` the root is
    /// never exactly halfway between two integers, so there is no tie:
    /// it rounds up exactly when n > r² + r, where r = ⌊√n⌋.
    ///
    /// - Precondition: `n >= 0`.
    static func roundedSquareRoot(_ n: Int64) -> Int64 {
        let root = squareRoot(n)
        return n - root * root > root ? root + 1 : root
    }

    /// `numerator / 2^shift` rounded to the nearest integer, halves up
    /// (toward positive infinity), for either sign: an arithmetic shift
    /// rounds toward negative infinity.
    ///
    /// - Precondition: `0 < shift < 63` and `numerator + 2^(shift - 1)`
    ///   fits in an `Int64`.
    static func roundedShift(_ numerator: Int64, by shift: Int) -> Int64 {
        (numerator + (Int64(1) << (shift - 1))) >> shift
    }

    /// `numerator / denominator` rounded to the nearest integer, halves up
    /// (toward positive infinity), for either sign of the numerator.
    ///
    /// - Precondition: `denominator > 0` and `2 × |numerator| + denominator`
    ///   fits in an `Int64`.
    static func roundedDivision(_ numerator: Int64, by denominator: Int64) -> Int64 {
        precondition(denominator > 0, "roundedDivision(_:by:) needs a positive denominator")
        let doubled = 2 * numerator + denominator
        let divisor = 2 * denominator
        let quotient = doubled / divisor
        // `/` truncates toward zero; step down to the floor for a negative
        // value that does not divide exactly.
        return doubled < 0 && quotient * divisor != doubled ? quotient - 1 : quotient
    }

    /// `a × b / c` rounded to the nearest integer, halves up, with the
    /// product worked out in 128 bits (the standard library's full-width
    /// multiply and divide) so it never overflows (Stage S4).
    ///
    /// - Precondition: `a >= 0`, `b >= 0`, `c > 0` and the result fits in an
    ///   `Int64`.
    static func roundedProduct(_ a: Int64, times b: Int64, over c: Int64) -> Int64 {
        precondition(a >= 0 && b >= 0 && c > 0, "roundedProduct(_:times:over:) needs non-negative factors and a positive divisor")
        let divisor = UInt64(c)
        let (quotient, remainder) = divisor.dividingFullWidth(UInt64(a).multipliedFullWidth(by: UInt64(b)))
        // Halves up: add one when the remainder is at least half the divisor.
        return Int64(quotient) + (remainder >= divisor - remainder ? 1 : 0)
    }

    /// The greatest common divisor of `|a|` and `|b|`; 0 only when both are
    /// 0.
    ///
    /// - Precondition: neither is `Int64.min`.
    static func greatestCommonDivisor(_ a: Int64, _ b: Int64) -> Int64 {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x
    }
}
