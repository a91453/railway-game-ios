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
}
