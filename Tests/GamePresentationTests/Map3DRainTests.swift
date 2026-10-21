import GameCore
import GamePresentation
import XCTest

/// Decision 277, next step: the rain over the 3D map, from
/// `town-scene-reference-clean`'s `weather.js`.
final class Map3DRainTests: XCTestCase {
    /// No rain on a clear day; the reference's counts at its three
    /// qualities on a day of rain; more and darker in a storm and a typhoon;
    /// lightning only in those.
    func testHowHardItRains() {
        let clear = Map3DRain(.clear), rain = Map3DRain(MapWeather(sky: .rain))
        let storm = Map3DRain(MapWeather(sky: .thunderstorm)), typhoon = Map3DRain(MapWeather(sky: .typhoon))
        XCTAssertEqual(clear.amount, 0)
        XCTAssertEqual(clear.streaks(at: 10, width: 400, height: 800, detail: .full), [])
        XCTAssertEqual(Map3DStreetDetail.allCases.map(rain.count(for:)), [140, 260, 480])
        XCTAssertEqual(rain.opacity, 0.24, accuracy: 1e-9)
        XCTAssertLessThan(rain.count(for: .full), storm.count(for: .full))
        XCTAssertLessThan(storm.count(for: .full), typhoon.count(for: .full))
        XCTAssertLessThan(storm.opacity, typhoon.opacity)
        XCTAssertFalse(rain.flashes)
        XCTAssertTrue(storm.flashes && typhoon.flashes)
        XCTAssertEqual((0..<90).map { rain.flash(at: Double($0) / 10) }.max(), 0)
        XCTAssertGreaterThan((0..<90).map { storm.flash(at: Double($0) / 10) }.max() ?? 0, 0, "a flash every 9 s")
    }

    /// Every streak is on the screen, 5 to 11 points long, leaning the
    /// reference's slant; the same moment draws the same rain, and a later
    /// one moves every streak down.
    func testTheStreaksFallParallelAndTheSameEveryTime() throws {
        let rain = Map3DRain(MapWeather(sky: .rain))
        let now = rain.streaks(at: 1_000, width: 400, height: 800, detail: .full)
        XCTAssertEqual(now.count, 480)
        XCTAssertEqual(now, rain.streaks(at: 1_000, width: 400, height: 800, detail: .full))
        for streak in now {
            XCTAssertTrue((0..<400).contains(streak.x0) && (0..<800).contains(streak.y0))
            let length = streak.y1 - streak.y0
            XCTAssertTrue((5...11).contains(length), "\(length)")
            XCTAssertEqual((streak.x1 - streak.x0) / length, Map3DRain.slant, accuracy: 1e-9)
        }
        let later = rain.streaks(at: 1_000.01, width: 400, height: 800, detail: .full)
        for (a, b) in zip(now, later) where b.y0 > a.y0 {
            // 0.85 to 1.15 times 220 points a second, for a hundredth.
            XCTAssertEqual(b.y0 - a.y0, 2.2, accuracy: 0.34)
        }
        XCTAssertGreaterThan(zip(now, later).filter { $0.1.y0 > $0.0.y0 }.count, 470, "all but those coming back in at the top")
    }
}
