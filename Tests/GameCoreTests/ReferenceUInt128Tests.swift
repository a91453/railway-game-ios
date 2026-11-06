import XCTest

/// ReferenceUInt128 gives the same answers as Swift's UInt128 for every
/// operation ReferenceTrafficCurve uses. Runs where the native type exists
/// (Linux, macOS 15, iOS 18); elsewhere it is skipped.
final class ReferenceUInt128Tests: XCTestCase {
    func testMatchesNativeUInt128() throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) else {
            throw XCTSkip("Swift's UInt128 needs macOS 15 or iOS 18")
        }
        var state: UInt64 = 0x5EED_1281_2800_0001
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        // Words of every size, so values span 0 to 2^128 - 1 and divisors
        // fall on both sides of 2^64.
        func word() -> UInt64 {
            let bits = Int(next() % 65)
            return bits == 0 ? 0 : next() >> UInt64(64 - bits)
        }
        func pair() -> (ReferenceUInt128, UInt128) {
            let high = next() % 3 == 0 ? 0 : word(), low = word()
            return (ReferenceUInt128(high: high, low: low), UInt128(high) << 64 | UInt128(low))
        }
        func same(_ mine: ReferenceUInt128, _ native: UInt128, _ what: String) {
            XCTAssertEqual(mine.high, UInt64(native >> 64), what)
            XCTAssertEqual(mine.low, UInt64(truncatingIfNeeded: native), what)
        }

        for _ in 0..<20_000 {
            let (a, x) = pair(), (b, y) = pair()
            XCTAssertEqual(a < b, x < y)
            XCTAssertEqual(a == b, x == y)
            let (sum, carried) = x.addingReportingOverflow(y)
            if !carried { same(a + b, sum, "+") }
            if x >= y { same(a - b, x - y, "-") }
            let (product, overflowed) = x.multipliedReportingOverflow(by: y)
            if !overflowed { same(a * b, product, "*") }
            if y != 0 { same(a / b, x / y, "/") }
            let shift = Int(next() % 140)
            same(a << shift, x << shift, "<< \(shift)")
            same(a >> shift, x >> shift, ">> \(shift)")
            if x <= UInt128(Int64.max) { XCTAssertEqual(Int64(a), Int64(x)) }
        }
        let value = Int64(bitPattern: next() >> 1)
        same(ReferenceUInt128(value), UInt128(value), "init")
        same(1 << 126, 1 << 126, "literal")
    }
}
