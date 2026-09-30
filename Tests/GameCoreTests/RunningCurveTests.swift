@testable import GameCore
import XCTest

/// Stage W1 (ARCHITECTURE decision 33): the running curve, a port of the
/// Railway reference's `buildProfile`, `profTimeToProg` and
/// `profProgToTime`. Hand-computed cases with exact integers, and a
/// differential campaign against a line-by-line `Double` transliteration of
/// the JavaScript (``ReferenceRunningProfile``).
final class RunningCurveTests: XCTestCase {
    // 2 km in 105.25 s at a = 2.5 and b = 3 km/h/s: D = 11,250 + 9,375 =
    // 20,625 ms² per unit, T² − 4DL = 22,750², so the cruise speed is
    // 2L ÷ (T + 22,750) = 2 units per ms (112.5 km/h) exactly. It
    // accelerates for 45,000 ms over 45,000 units, cruises for 22,750 ms
    // over 45,500 and brakes for 37,500 ms over 37,500.
    private func handCurve(topSpeed: Int64 = 120) -> RunningCurve? {
        RunningCurve(length: 128_000, duration: 105_250, acceleration: 2500, braking: 3000, topSpeed: topSpeed)
    }

    func testHandComputedTrapezoid() throws {
        let curve = try XCTUnwrap(handCurve())
        XCTAssertEqual(curve.cruiseSpeed, 2 << 32)
        XCTAssertEqual(curve.brakingSpeed, 2 << 32)
        XCTAssertEqual(curve.accelerationTime, 45_000 << 16)
        XCTAssertEqual(curve.cruiseTime, 22_750 << 16)
        XCTAssertEqual(curve.coastTime, 0)
        XCTAssertEqual(curve.brakingTime, 37_500 << 16)
        XCTAssertEqual(curve.accelerationDistance, 45_000 << 16)
        XCTAssertEqual(curve.cruiseDistance, 45_500 << 16)
        XCTAssertEqual(curve.coastDistance, 0)
        // ½at² = 2500 t² ÷ 112,500,000; the brake phase is
        // 90,500 + 2τ − 3000 τ² ÷ 112,500,000 (90,000 ms: τ = 22,250).
        let distances: [(Int64, Int64)] = [
            (-5, 0), (0, 0), (1, 0), (10_000, 2222), (45_000, 45_000), (50_000, 55_000),
            (67_750, 90_500), (90_000, 121_798), (105_249, 127_999), (105_250, 128_000), (200_000, 128_000),
        ]
        for (time, distance) in distances {
            XCTAssertEqual(curve.distance(at: time), distance, "distance at \(time) ms")
        }
        // √(2d/a), d/v after the acceleration and the brake phase's root,
        // rounded down.
        let times: [(Int64, Int64)] = [
            (-1, 0), (0, 0), (1, 212), (2222, 9999), (45_000, 45_000), (55_000, 50_000),
            (90_500, 67_750), (121_798, 89_999), (127_999, 105_056), (128_000, 105_250), (500_000, 105_250),
        ]
        for (distance, time) in times {
            XCTAssertEqual(curve.time(atDistance: distance), time, "time at \(distance) units")
        }
    }

    func testNoCurveWhenTheRunCannotBeMadeInTime() {
        // 1 km in 60 s at the default performance: T² < 4DL (the reference's
        // disc < 0).
        XCTAssertNil(RunningCurve(length: 64_000, duration: 60_000, performance: .standard))
        XCTAssertNotNil(RunningCurve(length: 64_000, duration: 90_000, performance: .standard))
    }

    func testNoCurveAboveTheTopSpeed() {
        // The hand curve cruises at 112.5 km/h.
        XCTAssertNil(handCurve(topSpeed: 112))
        XCTAssertNotNil(handCurve(topSpeed: 113))
    }

    func testValuesOutsideTheRangeHaveNoCurve() {
        XCTAssertNil(RunningCurve(length: 0, duration: 105_250, acceleration: 2500, braking: 3000, topSpeed: 120))
        XCTAssertNil(RunningCurve(length: 128_000, duration: 0, acceleration: 2500, braking: 3000, topSpeed: 120))
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250, acceleration: 0, braking: 3000, topSpeed: 120))
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250, acceleration: 2500, braking: -1, topSpeed: 120))
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250, acceleration: 2500, braking: 3000, topSpeed: 0))
        XCTAssertNil(RunningCurve(length: RunningCurve.maximumLength + 1, duration: 105_250,
                                  acceleration: 2500, braking: 3000, topSpeed: 120))
        XCTAssertNil(RunningCurve(length: 128_000, duration: RunningCurve.maximumDuration + 1,
                                  acceleration: 2500, braking: 3000, topSpeed: 120))
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250,
                                  acceleration: RunningCurve.maximumRate + 1, braking: 3000, topSpeed: 120))
    }

    func testTheExtremesStayInsideTheArithmetic() {
        // No combination of values inside the supported range traps; the
        // curves that exist answer queries anywhere along them.
        let largest = RunningCurve.maximumRate
        let lengths: [Int64] = [1, 64, 64_000, RunningCurve.maximumLength]
        let durations: [Int64] = [1, 1000, 3_600_000, RunningCurve.maximumDuration]
        let rates: [Int64] = [1, 1000, largest]
        var built = 0
        for length in lengths {
            for duration in durations {
                for rate in rates {
                    for topSpeed in [1, 300, largest] {
                        for coast in [nil, TrainPerformance.Coast(deceleration: max(1, rate - 1), speedRatio: 0),
                                      .init(deceleration: 1, speedRatio: 999)] {
                            guard let curve = RunningCurve(length: length, duration: duration, acceleration: rate,
                                                           braking: rate, topSpeed: topSpeed, coast: coast) else { continue }
                            built += 1
                            for step: Int64 in 0...8 {
                                let distance = curve.distance(at: duration * step / 8)
                                XCTAssertTrue((0...length).contains(distance))
                                XCTAssertTrue((0...duration).contains(curve.time(atDistance: length * step / 8)))
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(built, 0)
    }

    func testAlternativesAreTriedInTheReferenceOrder() throws {
        let hand = try XCTUnwrap(handCurve())
        // Braking 1 km/h/s is too weak for the run; the alternative braking
        // is the hand curve's.
        let weakBrakes = TrainPerformance(acceleration: 2500, braking: 1000, topSpeed: 120, alternativeBraking: 3000)
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250, acceleration: 2500, braking: 1000, topSpeed: 120))
        XCTAssertEqual(RunningCurve(length: 128_000, duration: 105_250, performance: weakBrakes), hand)
        // Neither the usual acceleration with either braking works; both
        // alternatives do.
        let weak = TrainPerformance(acceleration: 500, braking: 1000, topSpeed: 120,
                                    alternativeAcceleration: 2500, alternativeBraking: 3000)
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250, acceleration: 500, braking: 3000, topSpeed: 120))
        XCTAssertEqual(RunningCurve(length: 128_000, duration: 105_250, performance: weak), hand)
        // An alternative acceleration alone is never tried.
        let alone = TrainPerformance(acceleration: 500, braking: 3000, topSpeed: 120, alternativeAcceleration: 2500)
        XCTAssertNil(RunningCurve(length: 128_000, duration: 105_250, performance: alone))
    }

    func testCoastIsIgnoredWhenItIsNotBelowTheBraking() throws {
        let hand = try XCTUnwrap(handCurve())
        for coast in [TrainPerformance.Coast(deceleration: 3000, speedRatio: 450),
                      .init(deceleration: 0, speedRatio: 450), .init(deceleration: 450, speedRatio: 1000)] {
            XCTAssertEqual(RunningCurve(length: 128_000, duration: 105_250, acceleration: 2500, braking: 3000,
                                        topSpeed: 120, coast: coast), hand)
        }
    }

    func testPresetsAreTheReferenceValues() {
        func values(_ p: TrainPerformance) -> [Int64?] {
            [p.acceleration, p.braking, p.topSpeed, p.alternativeAcceleration, p.alternativeBraking,
             p.coast?.deceleration, p.coast?.speedRatio]
        }
        XCTAssertEqual(values(.standard), [1500, 2500, 110, nil, nil, nil, nil])
        XCTAssertEqual(values(.highSpeed), [1400, 1500, 300, 2000, 2700, 450, 450])
        XCTAssertEqual(values(.dieselRailcar), [1500, 2448, 110, nil, nil, nil, nil])
        XCTAssertEqual(values(.forestRailway), [700, 1100, 45, nil, nil, nil, nil])
        XCTAssertEqual(values(.ordinary), [1300, 2400, 100, nil, nil, nil, nil])
        XCTAssertEqual(values(.tiltingTaroko), [1880, 3600, 135, nil, nil, nil, nil])
        XCTAssertEqual(values(.tiltingPuyuma), [1840, 3600, 135, nil, nil, nil, nil])
        XCTAssertEqual(values(.pushPull), [1600, 2800, 130, nil, nil, nil, nil])
        XCTAssertEqual(values(.emu3000), [2520, 3600, 135, nil, nil, nil, nil])
        XCTAssertEqual(values(.dieselExpress), [1500, 2448, 110, nil, nil, nil, nil])
        XCTAssertEqual(values(.express), [1800, 2900, 130, nil, nil, nil, nil])
        XCTAssertEqual(values(.semiExpress), [1500, 2600, 120, nil, nil, nil, nil])
        XCTAssertEqual(values(.local), [2500, 3000, 120, nil, nil, nil, nil])
    }

    private static let presets: [TrainPerformance] = [
        .standard, .highSpeed, .dieselRailcar, .forestRailway, .ordinary, .tiltingTaroko, .tiltingPuyuma,
        .pushPull, .emu3000, .dieselExpress, .express, .semiExpress, .local,
    ]

    private func reference(_ length: Int64, _ duration: Int64, _ p: TrainPerformance, braking: Int64? = nil,
                           acceleration: Int64? = nil) -> (profile: ReferenceRunningProfile?, margin: Double) {
        ReferenceRunningProfile.build(
            Lkm: Double(length) / 64 / 1000, T: Double(duration) / 1000,
            aK: Double(acceleration ?? p.acceleration) / 1000, bK: Double(braking ?? p.braking) / 1000,
            vK: Double(p.topSpeed),
            coast: p.coast.map { (c: Double($0.deceleration) / 1000, rho: Double($0.speedRatio) / 1000) }
        )
    }

    /// The integer curve against the transliterated JavaScript, for every
    /// preset, over runs from 200 m to 80 km and times from below the
    /// fastest possible to four times it: the same runs have a curve, and
    /// where they do, the distance at any time is within 2 units (3 cm) and
    /// the time at any distance within 2 ms, except where the reference's
    /// own braking root makes the time ill-conditioned (the last units of
    /// the run, where the train is almost stopped).
    func testMatchesTheReferenceTransliteration() {
        var generator = SplitMix64(seed: 0x57A6_E0_01)
        var compared = 0, withoutCurve = 0, tooCloseToCall = 0, coasting = 0
        for index in 0..<4000 {
            let p = Self.presets[index % Self.presets.count]
            let length = 64 * generator.int64(in: 200...80_000)
            // The fastest time: the length at the top speed (4v ÷ 225 units
            // per ms), then 0.9 to 4 times it.
            let fastest = length * 225 / (4 * p.topSpeed)
            let duration = fastest * generator.int64(in: 900...4000) / 1000 + generator.int64(in: 0...999)
            let ours = RunningCurve(length: length, duration: duration, acceleration: p.acceleration,
                                    braking: p.braking, topSpeed: p.topSpeed, coast: p.coast)
            let (theirs, margin) = reference(length, duration, p)
            guard let ours, let theirs else {
                if (ours == nil) != (theirs == nil) {
                    XCTAssertLessThan(margin, 1e-6, "case \(index): only one side has a curve (L \(length), T \(duration))")
                    tooCloseToCall += 1
                } else {
                    withoutCurve += 1
                }
                continue
            }
            if theirs.rho < 1 { coasting += 1 }
            let ratio = Double(ours.brakingSpeed) / Double(ours.cruiseSpeed)
            if abs(ratio - theirs.rho) > 1e-4 {
                // The bisection took the other side of a threshold.
                XCTAssertLessThan(margin, 1e-6, "case \(index): coasting ratio \(ratio) against \(theirs.rho)")
                tooCloseToCall += 1
                continue
            }
            compared += 1
            for step in 0...40 {
                let time = duration * Int64(step) / 40 + (step == 0 ? 0 : -generator.int64(in: 0...999) % max(1, duration / 40))
                let expected = theirs.progress(at: Double(time) / 1000) * theirs.L * 64
                XCTAssertEqual(Double(ours.distance(at: time)), expected, accuracy: 2,
                               "case \(index): distance at \(time) ms of \(duration) (L \(length))")
                let distance = length * Int64(step) / 40
                let speedNearEnd = theirs.vb > 0 ? (2 * theirs.b * max(Double(length - distance) / 64, 0)).squareRoot() : 0
                let conditioning = speedNearEnd > 0 ? 2 / (speedNearEnd * 64 / 1000) : .infinity
                let expectedTime = theirs.time(atProgress: Double(distance) / Double(length)) * 1000
                XCTAssertEqual(Double(ours.time(atDistance: distance)), expectedTime, accuracy: max(2, conditioning),
                               "case \(index): time at \(distance) of \(length) units (T \(duration))")
            }
        }
        XCTAssertGreaterThan(compared, 2000)
        XCTAssertGreaterThan(withoutCurve, 100)
        XCTAssertGreaterThan(coasting, 50)
        XCTAssertLessThan(tooCloseToCall, 20)
        print("[runningCurve.reference] compared \(compared), no curve \(withoutCurve), coasting \(coasting), too close \(tooCloseToCall)")
    }

    func testDistanceGrowsWithTimeAndTimeWithDistance() throws {
        for p in Self.presets {
            for (length, duration) in [(Int64(64 * 3_000), Int64(240_000)), (64 * 45_000, 1_500_000), (64 * 900, 90_000)] {
                guard let curve = RunningCurve(length: length, duration: duration, performance: p) else { continue }
                var previous: Int64 = 0
                var time: Int64 = 0
                while time <= duration {
                    let distance = curve.distance(at: time)
                    XCTAssertGreaterThanOrEqual(distance + 1, previous, "\(p) at \(time)")
                    previous = max(previous, distance)
                    time += 997
                }
                var last: Int64 = 0
                var distance: Int64 = 0
                while distance <= length {
                    let t = curve.time(atDistance: distance)
                    XCTAssertGreaterThanOrEqual(t + 1, last, "\(p) at \(distance) units")
                    last = max(last, t)
                    distance += length / 503 + 1
                }
            }
        }
    }
}

final class WideIntegerTests: XCTestCase {
    func testArithmeticAgainstSixtyFourBits() {
        var generator = SplitMix64(seed: 0x1D_E128)
        for _ in 0..<5000 {
            let a = generator.next() >> 33, b = generator.next() >> 33
            let product = WideInteger.product(a, b)
            XCTAssertEqual(product, WideInteger(a * b))
            let divisor = max(1, generator.next() >> 40)
            XCTAssertEqual(product.dividedRoundingDown(by: divisor), WideInteger(a * b / divisor))
            let shift = generator.below(30)
            XCTAssertEqual(WideInteger(a).shiftedLeft(by: shift), WideInteger(a << UInt64(shift)))
            XCTAssertEqual(product.shiftedRight(by: shift), WideInteger((a * b) >> UInt64(shift)))
            XCTAssertEqual(product.squareRoot(), UInt64(FixedPoint.squareRoot(Int64(a * b))))
            XCTAssertEqual((product + WideInteger(a)) - WideInteger(a), product)
        }
    }

    func testFullWidthValues() {
        let largest = WideInteger.product(UInt64.max, UInt64.max)
        XCTAssertEqual(largest, WideInteger(high: UInt64.max - 1, low: 1))
        XCTAssertEqual(largest.dividedRoundingDown(by: UInt64.max), WideInteger(UInt64.max))
        XCTAssertEqual(largest.squareRoot(), UInt64.max)
        XCTAssertEqual(WideInteger(high: 1, low: 0).squareRoot(), 1 << 32)
        XCTAssertEqual(WideInteger(high: 1, low: 0) - WideInteger(1 as UInt64), WideInteger(UInt64.max))
        XCTAssertEqual(WideInteger(UInt64.max) + WideInteger(1 as UInt64), WideInteger(high: 1, low: 0))
        XCTAssertEqual(WideInteger(1 as UInt64).shiftedLeft(by: 63).shiftedLeft(by: 1), WideInteger(high: 1, low: 0))
        XCTAssertEqual(WideInteger(high: 3, low: 5).multiplied(by: 7 as UInt64), WideInteger(high: 21, low: 35))
        var generator = SplitMix64(seed: 0x5_0127)
        for _ in 0..<2000 {
            let value = WideInteger(high: generator.next() >> 1, low: generator.next())
            let root = value.squareRoot()
            XCTAssertLessThanOrEqual(WideInteger.product(root, root), value)
            let next = WideInteger.product(root, root) + WideInteger(root) + WideInteger(root) + WideInteger(1 as UInt64)
            XCTAssertLessThan(value, next)
            let divisor = max(1, generator.next())
            let quotient = value.dividedRoundingDown(by: divisor)
            XCTAssertLessThanOrEqual(quotient.multiplied(by: divisor), value)
            XCTAssertLessThan(value, quotient.multiplied(by: divisor) + WideInteger(divisor))
        }
    }
}
