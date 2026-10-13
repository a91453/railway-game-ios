import GameCore
@testable import GamePresentation
import XCTest

/// TestFlight 59.1: the distance fares from a first step the player sets.
final class FareBandScaleTests: XCTestCase {
    func testTheStandardStepsScaleToTheFirstFare() {
        let baseline = FareRules.demandBaseline
        XCTAssertEqual(FareRules.distanceBands(startingAt: 55, baseline: baseline), FareRules.standardBands)
        // 1.10 doubles every step.
        XCTAssertEqual(FareRules.distanceBands(startingAt: 110, baseline: baseline).map(\.fare), [110, 140, 170, 200, 240])
        // 0.30: 0.55 × 6/11 and the rest to the nearest 0.05.
        XCTAssertEqual(FareRules.distanceBands(startingAt: 30, baseline: baseline).map(\.fare), [30, 40, 45, 55, 65])
        XCTAssertEqual(FareRules.distanceBands(startingAt: 5, baseline: baseline).map(\.fare), [5, 5, 10, 10, 10])
        let top = FareRules.distanceBands(startingAt: Money(FareRules.bandStartRange.upperBound), baseline: baseline)
        XCTAssertEqual(top.map(\.fare), [10_000, 12_725, 15_455, 18_180, 21_820])
        for start in stride(from: FareRules.bandStartRange.lowerBound, through: FareRules.bandStartRange.upperBound, by: 995) {
            let bands = FareRules.distanceBands(startingAt: Money(start), baseline: baseline)
            XCTAssertEqual(bands.map(\.fromMeters), FareRules.standardBands.map(\.fromMeters))
            XCTAssertEqual(bands.map(\.toMeters), FareRules.standardBands.map(\.toMeters))
            XCTAssertTrue(FareRules.distance(bands).isValid)
            XCTAssertEqual(bands.map(\.fare), bands.map(\.fare).sorted(), "never cheaper farther")
        }
    }

    func testTheCitysOwnStepsAtItsOwnStart() {
        let baseline: Money = 300
        let city = FareRules.standardBands(for: baseline)
        XCTAssertEqual(FareRules.distanceBands(startingAt: city[0].fare, baseline: baseline), city)
        XCTAssertEqual(FareRules.standard.bandStart(baseline: baseline), city[0].fare.amount)
        XCTAssertEqual(FareRules.distance(FareRules.distanceBands(startingAt: 110, baseline: baseline)).bandStart(baseline: baseline), 110)
        XCTAssertEqual(FareRules.distance([FareBand(fromMeters: 0, toMeters: nil, fare: 2)]).bandStart(baseline: baseline), 5)
        XCTAssertEqual(FareRules.distance([FareBand(fromMeters: 0, toMeters: nil, fare: 123)]).bandStart(baseline: baseline), 125)
    }

    func testTheStepsText() {
        XCTAssertEqual(FareRules.bandsText(FareRules.standardBands, in: .english), [
            "0–6 km · $ 0.55", "6–12 km · $ 0.70", "12–22 km · $ 0.85", "22–32 km · $ 1.00", "32 km and more · $ 1.20",
        ])
        XCTAssertEqual(FareRules.bandsText([FareBand(fromMeters: 0, toMeters: 1_500, fare: 5), FareBand(fromMeters: 1_500, toMeters: nil, fare: 10)], in: .traditionalChinese), [
            "0–1.5 km · $ 0.05", "1.5 km 以上 · $ 0.10",
        ])
    }
}
