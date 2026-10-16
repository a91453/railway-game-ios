import GamePresentation
import XCTest

/// Decision 253: one set of motion rules for the interface, and one answer
/// for Reduce Motion.
final class InterfaceMotionTests: XCTestCase {
    /// What comes in takes 30–50% longer than what goes (LottieFiles'
    /// "Enter > Exit"), decelerating in and accelerating out.
    func testACardComesInSlowerThanItGoes() {
        let ratio = MotionRule.cardIn.seconds / MotionRule.cardOut.seconds
        XCTAssertGreaterThanOrEqual(ratio, 1.3)
        XCTAssertLessThanOrEqual(ratio, 1.5)
        XCTAssertEqual(MotionRule.cardIn.curve, .decelerate)
        XCTAssertEqual(MotionRule.cardOut.curve, .accelerate)
    }

    /// The durations of the skill's table: a press under 180 ms, a small
    /// pop and a change 150–350 ms, a card 200–350 ms, a refusal's shake
    /// 300–400 ms; only the built ring is longer, and under 1.2 s.
    func testTheDurationsAreTheTables() {
        XCTAssertLessThanOrEqual(MotionRule.press.seconds, 0.18)
        for rule in [MotionRule.pop, .confirm, .change] {
            XCTAssertTrue((0.15...0.35).contains(rule.seconds), "\(rule)")
        }
        for rule in [MotionRule.cardIn, .cardOut] {
            XCTAssertTrue((0.2...0.35).contains(rule.seconds), "\(rule)")
        }
        XCTAssertTrue((0.3...0.4).contains(MotionRule.refuse.seconds))
        XCTAssertTrue((0.6...1.2).contains(MotionRule.builtRing.seconds))
    }

    /// A small thing pops with a little overshoot; a card, a panel and a
    /// refusal none.
    func testOnlySmallThingsOvershoot() {
        for rule in [MotionRule.pop, .confirm] {
            guard case .spring(let bounce) = rule.curve else { return XCTFail("\(rule) springs") }
            XCTAssertTrue((0.05...0.25).contains(bounce), "\(rule): a little")
        }
        for rule in [MotionRule.cardIn, .cardOut, .refuse, .change, .press] {
            if case .spring = rule.curve { XCTFail("\(rule) does not spring") }
        }
    }

    /// Reduce Motion: nothing slides, scales, springs or shakes; a fade
    /// stays, in half the time or less; what only moved happens at once.
    func testReduceMotionKeepsOnlyTheFades() {
        for rule in MotionRule.all {
            XCTAssertEqual(rule.running(reduceMotion: false), rule)
            guard let reduced = rule.running(reduceMotion: true) else {
                XCTAssertFalse(rule.fades, "\(rule): a fade stays")
                continue
            }
            XCTAssertTrue(rule.fades, "\(rule)")
            XCTAssertFalse(reduced.moves, "\(rule): nothing moves")
            XCTAssertTrue(reduced.fades)
            XCTAssertLessThanOrEqual(reduced.seconds, rule.seconds / 2, "\(rule): half the time or less")
            if case .spring = reduced.curve { XCTFail("\(rule): no spring") }
        }
        XCTAssertNil(MotionRule.refuse.reduced, "the shake does not run")
        XCTAssertNil(MotionRule.confirm.reduced, "the bump does not run")
    }

    /// The refusal's shake starts and ends where the banner stands, swings
    /// three times each way, each swing smaller, never wider than its
    /// first.
    func testTheRefusalShakeSwingsThreeTimesSmallerEachTime() {
        XCTAssertEqual(RefusalShake.offset(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(RefusalShake.offset(at: 1), 0, accuracy: 1e-9)
        let samples = (0...600).map { RefusalShake.offset(at: Double($0) / 600) }
        XCTAssertLessThanOrEqual(samples.map(abs).max() ?? 0, RefusalShake.amplitude)
        // Each half swing, between two crossings: its peak and its side.
        let halves = 2 * RefusalShake.swings, perHalf = 600 / halves
        let peaks = (0..<halves).map { half in samples[(half * perHalf)...((half + 1) * perHalf)].map(abs).max() ?? 0 }
        let sides = (0..<halves).map { half in samples[half * perHalf + perHalf / 2] > 0 }
        XCTAssertEqual(peaks, peaks.sorted(by: >), "each swing smaller: \(peaks)")
        XCTAssertEqual(sides, (0..<halves).map { $0 % 2 == 0 }, "back and forth")
        XCTAssertGreaterThan(peaks.last ?? 0, 0.1, "the last swing still shows")
        XCTAssertEqual(RefusalShake.offset(at: -1), 0, accuracy: 1e-9, "before it starts")
        XCTAssertEqual(RefusalShake.offset(at: 2), 0, accuracy: 1e-9, "after it ends")
    }
}
