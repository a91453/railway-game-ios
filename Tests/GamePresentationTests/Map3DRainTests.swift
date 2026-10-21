import Foundation
@testable import GamePresentation
import XCTest

/// Decision 320: the rain over the 3D map, the reference's curtain of
/// parallel streaks.
final class Map3DRainTests: XCTestCase {
    private let rain = Map3DRain(MapWeather(sky: .rain))

    /// A clear day has no rain and no lightning.
    func testAClearDayHasNoRain() {
        let clear = Map3DRain(.clear)
        XCTAssertEqual(clear, .none)
        XCTAssertEqual(clear.look(night: 0).opacity, 0)
        XCTAssertEqual(clear.streakCount(.full), 0)
        XCTAssertTrue(clear.streaks(at: 12, width: 400, height: 800, detail: .full).isEmpty)
        XCTAssertEqual((0..<200).map { clear.flash(at: Double($0) * 0.1) }.max(), 0)
    }

    /// Under rain, the reference's counts for each street detail; at
    /// night its colour at 0.24, by day the 2D map's at 0.35, between
    /// them as the light fades. Harder and more streaks in a thunderstorm,
    /// most in a typhoon, whose wind leans them further.
    func testHowHardItRains() {
        XCTAssertEqual(Map3DStreetDetail.allCases.map(rain.streakCount), [140, 260, 480])
        XCTAssertEqual(rain.look(night: 1).colour, 0xC6D7E4)
        XCTAssertEqual(rain.look(night: 1).opacity, 0.24, accuracy: 1e-9)
        XCTAssertEqual(rain.look(night: 0).colour, 0x4A5A80)
        XCTAssertEqual(rain.look(night: 0).opacity, 0.35, accuracy: 1e-9)
        XCTAssertEqual(rain.look(night: 0.5).colour, 0x8899B2)
        XCTAssertEqual(rain.look(night: -1).colour, 0x4A5A80)
        XCTAssertEqual(rain.slant, 0.12)
        let storm = Map3DRain(MapWeather(sky: .thunderstorm)), typhoon = Map3DRain(MapWeather(sky: .typhoon))
        XCTAssertLessThan(rain.streakCount(.full), storm.streakCount(.full))
        XCTAssertLessThan(storm.streakCount(.full), typhoon.streakCount(.full))
        XCTAssertLessThan(storm.look(night: 0).opacity, typhoon.look(night: 0).opacity)
        XCTAssertLessThanOrEqual(typhoon.look(night: 0).opacity, 0.55)
        XCTAssertEqual(storm.slant, 0.12)
        XCTAssertGreaterThan(typhoon.slant, storm.slant)
    }

    /// Every streak leans the same way, 5 to 11 points long, starting on
    /// the screen; the same time gives the same streaks.
    func testTheStreaksAreParallelAndTheSameEveryTime() {
        for time in [0.0, 3.7, 1_000.25] {
            let streaks = rain.streaks(at: time, width: 402, height: 874, detail: .full)
            XCTAssertEqual(streaks.count, 480)
            XCTAssertEqual(streaks, rain.streaks(at: time, width: 402, height: 874, detail: .full))
            for streak in streaks {
                XCTAssertEqual((streak.x1 - streak.x0) / (streak.y1 - streak.y0), 0.12, accuracy: 1e-9)
                XCTAssertTrue((5...11).contains(streak.y1 - streak.y0))
                XCTAssertTrue((0..<402).contains(streak.x0) && (0..<874).contains(streak.y0))
            }
        }
        XCTAssertNotEqual(rain.streaks(at: 0, width: 402, height: 874, detail: .full),
                          rain.streaks(at: 0.5, width: 402, height: 874, detail: .full))
    }

    /// Each streak falls 0.85 to 1.15 times 220 points a second and
    /// drifts by the slant as it falls, coming back in at the top.
    func testTheStreaksFall() {
        let height = 874.0, width = 402.0, step = 0.05
        let before = rain.streaks(at: 10, width: width, height: height, detail: .reduced)
        let after = rain.streaks(at: 10 + step, width: width, height: height, detail: .reduced)
        for (a, b) in zip(before, after) {
            var fallen = b.y0 - a.y0
            if fallen < 0 { fallen += height }
            XCTAssertTrue((0.85 * 220 * step - 1e-6...1.15 * 220 * step + 1e-6).contains(fallen), "\(fallen)")
            var drifted = b.x0 - a.x0
            if drifted < -width / 2 { drifted += width }
            XCTAssertEqual(drifted, fallen * 0.12, accuracy: 1e-6)
        }
    }

    /// Lightning flashes in a thunderstorm and a typhoon, as on the 2D
    /// map, never under plain rain.
    func testLightning() {
        let times = (0..<400).map { Double($0) * 0.05 }
        XCTAssertEqual(times.map(rain.flash).max(), 0)
        for sky in [MapWeather.Sky.thunderstorm, .typhoon] {
            let weather = MapWeather(sky: sky)
            XCTAssertEqual(times.map(Map3DRain(weather).flash), times.map(weather.flash))
            XCTAssertGreaterThan(times.map(Map3DRain(weather).flash).max() ?? 0, 0)
        }
    }
}
