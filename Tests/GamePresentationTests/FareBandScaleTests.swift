import GameCore
@testable import GamePresentation
import XCTest

/// TestFlight 59.1: the distance fares from a first step the player sets.
final class FareBandScaleTests: XCTestCase {
    func testTheStandardStepsScaleToTheFirstFare() {
        let baseline = FareRules.standardFare
        XCTAssertEqual(FareRules.distanceBands(startingAt: 1_100, baseline: baseline), FareRules.standardBands)
        // NT$22 doubles every step.
        XCTAssertEqual(FareRules.distanceBands(startingAt: 2_200, baseline: baseline).map(\.fare), [2_200, 2_800, 3_400, 4_000, 4_800])
        // NT$6: NT$11 × 6/11 and the rest to the nearest New Taiwan dollar.
        XCTAssertEqual(FareRules.distanceBands(startingAt: 600, baseline: baseline).map(\.fare), [600, 800, 900, 1_100, 1_300])
        XCTAssertEqual(FareRules.distanceBands(startingAt: 100, baseline: baseline).map(\.fare), [100, 100, 200, 200, 200])
        let top = FareRules.distanceBands(startingAt: Money(FareRules.bandStartRange.upperBound), baseline: baseline)
        XCTAssertEqual(top.map(\.fare), [30_000, 38_200, 46_400, 54_500, 65_500])
        for start in stride(from: FareRules.bandStartRange.lowerBound, through: FareRules.bandStartRange.upperBound, by: 2_900) {
            let bands = FareRules.distanceBands(startingAt: Money(start), baseline: baseline)
            XCTAssertEqual(bands.map(\.fromMeters), FareRules.standardBands.map(\.fromMeters))
            XCTAssertEqual(bands.map(\.toMeters), FareRules.standardBands.map(\.toMeters))
            XCTAssertTrue(FareRules.distance(bands).isValid)
            XCTAssertEqual(bands.map(\.fare), bands.map(\.fare).sorted(), "never cheaper farther")
        }
    }

    func testTheCitysOwnStepsAtItsOwnStart() {
        let baseline: Money = 900
        let city = FareRules.standardBands(for: baseline)
        XCTAssertEqual(FareRules.distanceBands(startingAt: city[0].fare, baseline: baseline), city)
        XCTAssertEqual(FareRules.standard.bandStart(baseline: baseline), city[0].fare.amount)
        XCTAssertEqual(FareRules.distance(FareRules.distanceBands(startingAt: 2_200, baseline: baseline)).bandStart(baseline: baseline), 2_200)
        XCTAssertEqual(FareRules.distance([FareBand(fromMeters: 0, toMeters: nil, fare: 2)]).bandStart(baseline: baseline), 100)
        XCTAssertEqual(FareRules.distance([FareBand(fromMeters: 0, toMeters: nil, fare: 1_250)]).bandStart(baseline: baseline), 1_300)
    }

    func testTheStepsText() {
        XCTAssertEqual(FareRules.bandsText(FareRules.standardBands, in: .english), [
            "0–6 km · \(Money(1_100).centsText)", "6–12 km · \(Money(1_400).centsText)", "12–22 km · \(Money(1_700).centsText)", "22–32 km · \(Money(2_000).centsText)", "32 km and more · \(Money(2_400).centsText)",
        ])
        XCTAssertEqual(FareRules.bandsText([FareBand(fromMeters: 0, toMeters: 1_500, fare: 5), FareBand(fromMeters: 1_500, toMeters: nil, fare: 10)], in: .traditionalChinese), [
            "0–1.5 km · \(Money(5).centsText)", "1.5 km 以上 · \(Money(10).centsText)",
        ])
    }
}
