import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 182: the map's tint and lights by the clock, and
/// today's weather on the map.
final class DayNightTests: XCTestCase {
    func testTheTintFollowsTheDay() {
        let midnight = DayNight.tint(atMinute: 0)
        XCTAssertEqual(midnight.colour, DayNight.night)
        XCTAssertEqual(midnight.strength, 0.25)
        XCTAssertEqual(midnight.lights, 1)
        XCTAssertEqual(DayNight.tint(atMinute: 299).strength, 0.25, "night until 05:00")

        let dawn = DayNight.tint(atMinute: 330)
        XCTAssertEqual(dawn.colour, DayNight.dawn, "warm orange at 05:30")
        XCTAssertEqual(dawn.strength, 0.15, accuracy: 1e-9)
        XCTAssertEqual(DayNight.tint(atMinute: 360).strength, 0.075, accuracy: 1e-9, "fading out")

        for minute in [390.0, 600, 720, 1_000, 1_050] {
            XCTAssertEqual(DayNight.tint(atMinute: minute).strength, 0, "nothing by day (\(minute))")
            XCTAssertEqual(DayNight.tint(atMinute: minute).lights, 0)
        }

        let dusk = DayNight.tint(atMinute: 1_095)
        XCTAssertEqual(dusk.colour, DayNight.dusk, "orange at 18:15")
        XCTAssertEqual(dusk.strength, 0.25, accuracy: 1e-9)
        let late = DayNight.tint(atMinute: 1_117.5)
        XCTAssertEqual(late.strength, 0.25, accuracy: 1e-9, "turning blue")
        XCTAssertGreaterThan(late.colour.blue, dusk.colour.blue)
        XCTAssertLessThan(late.colour.red, dusk.colour.red)
        XCTAssertEqual(DayNight.tint(atMinute: 1_140).colour, DayNight.night, "night from 19:00")
        XCTAssertEqual(DayNight.tint(atMinute: 1_439.9).strength, 0.25)
        XCTAssertEqual(DayNight.tint(atMinute: 1_440 + 330), dawn, "wrapped into the day")
        XCTAssertEqual(DayNight.tint(atMinute: -1_110), dawn)
    }

    /// #603 drew the stations' names over the trains, so over the tint:
    /// they are multiplied by what the tint does to the map under it.
    func testTheMultiplierIsWhatTheTintDoesToTheMap() {
        XCTAssertEqual(DayNight.Tint.day.multiplier, DayNight.Colour(red: 1, green: 1, blue: 1))
        let night = DayNight.tint(atMinute: 0).multiplier
        // The night's blue (0x0E1640) at 25 %.
        XCTAssertEqual(night.red, 0.75 + 0.25 * 14 / 255, accuracy: 1e-9)
        XCTAssertEqual(night.green, 0.75 + 0.25 * 22 / 255, accuracy: 1e-9)
        XCTAssertEqual(night.blue, 0.75 + 0.25 * 64 / 255, accuracy: 1e-9)
        // A colour under the tint, multiplied as the blend does.
        let tint = DayNight.tint(atMinute: 1_117.5)
        let under = 0.6
        let blended = (1 - tint.strength) * under + tint.strength * under * tint.colour.blue
        XCTAssertEqual(under * tint.multiplier.blue, blended, accuracy: 1e-9)
    }

    func testTheTintNeverJumps() {
        var previous = DayNight.tint(atMinute: 0)
        for tenth in 1...14_400 {
            let tint = DayNight.tint(atMinute: Double(tenth) / 10)
            XCTAssertEqual(tint.strength, previous.strength, accuracy: 0.002, "at \(tenth)")
            XCTAssertEqual(tint.colour.red, previous.colour.red, accuracy: 0.01)
            XCTAssertEqual(tint.colour.blue, previous.colour.blue, accuracy: 0.01)
            XCTAssertEqual(tint.lights, previous.lights, accuracy: 0.01)
            XCTAssertTrue((0...0.25).contains(tint.strength), "never darker than keeps the track 3:1")
            previous = tint
        }
    }

    func testTheLightsGoOutAtDawnAndComeOnAtDusk() {
        XCTAssertEqual(DayNight.lights(atMinute: 300), 1)
        XCTAssertEqual(DayNight.lights(atMinute: 337.5), 0.5, accuracy: 1e-9, "half way out at 05:37:30")
        XCTAssertEqual(DayNight.lights(atMinute: 375), 0)
        XCTAssertEqual(DayNight.lights(atMinute: 1_087.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(DayNight.lights(atMinute: 1_125), 1)
        XCTAssertEqual(DayNight.step(0.5), 0.5)
        XCTAssertEqual(DayNight.step(0.549), 0.5, "in twentieths")
        XCTAssertEqual(DayNight.step(1.2), 1)
        XCTAssertEqual(DayNight.step(-1), 0)
    }

    func testTheTintReadsTheGameClockToTheSecond() {
        XCTAssertEqual(DayNight.tint(at: GameTime(seconds: 18 * 3_600 + 15 * 60)), DayNight.tint(atMinute: 1_095))
        XCTAssertEqual(DayNight.tint(at: GameTime(seconds: 3 * GameTime.secondsPerDay + 330 * 60 + 30)), DayNight.tint(atMinute: 330.5))
        XCTAssertEqual(DayNight.tint(at: GameTime(seconds: -60)), DayNight.tint(atMinute: 1_439))
        XCTAssertFalse(DayNight.Tint.day.isVisible)
        XCTAssertTrue(DayNight.tint(atMinute: 0).isVisible)
    }

    // MARK: - Weather

    func testRainFallsAsAFixedNumberOfStreaksInsideTheScreen() {
        let rain = MapWeather(sky: .rain)
        XCTAssertEqual(MapWeather.clear.streaks(at: 1, width: 400, height: 800), [])
        for (width, height) in [(390.0, 844.0), (1_366.0, 1_024.0)] {
            for time in [0.0, 0.37, 12.5, 3_600] {
                let streaks = rain.streaks(at: time, width: width, height: height)
                XCTAssertEqual(streaks.count, 90, "the same on any screen and map")
                for streak in streaks {
                    XCTAssertEqual(streak.y1 - streak.y0, rain.streakLength, accuracy: 1e-9)
                    XCTAssertTrue((-rain.streakLength...height + rain.streakLength).contains(streak.y0))
                    XCTAssertGreaterThan(streak.x1, streak.x0, "leaning with the wind")
                }
            }
        }
        XCTAssertEqual(rain.streaks(at: 2, width: 400, height: 800), rain.streaks(at: 2, width: 400, height: 800))
        XCTAssertNotEqual(rain.streaks(at: 2, width: 400, height: 800), rain.streaks(at: 2.1, width: 400, height: 800), "it falls")
        XCTAssertEqual(MapWeather(sky: .thunderstorm).streakCount, 140)
        XCTAssertEqual(MapWeather(sky: .typhoon).streakCount, 200)
        XCTAssertGreaterThan(MapWeather(sky: .typhoon).slant, rain.slant)
    }

    func testLightningFlashesOnceAPeriodAndOnlyInAStorm() {
        XCTAssertEqual(MapWeather(sky: .rain).flash(at: 3), 0)
        let storm = MapWeather(sky: .thunderstorm)
        for cycle in 0..<20 {
            var lit = 0
            var longest = 0, run = 0
            for step in 0..<900 {
                let time = (Double(cycle) * MapWeather.flashPeriod) + Double(step) / 100
                let flash = storm.flash(at: time)
                XCTAssertTrue((0...1).contains(flash))
                if flash > 0 { lit += 1; run += 1; longest = max(longest, run) } else { run = 0 }
            }
            XCTAssertGreaterThan(lit, 0, "a flash in cycle \(cycle)")
            XCTAssertLessThanOrEqual(longest, 35, "short")
        }
    }

    func testReducedMotionDarkensInsteadOfMoving() {
        for sky in [MapWeather.Sky.rain, .thunderstorm, .typhoon] {
            let weather = MapWeather(sky: sky)
            XCTAssertGreaterThan(weather.dimming(reduceMotion: true), weather.dimming(reduceMotion: false))
        }
        XCTAssertEqual(MapWeather.clear.dimming(reduceMotion: true), 0)
        XCTAssertGreaterThan(MapWeather(sky: .typhoon).dimming(reduceMotion: false), MapWeather(sky: .thunderstorm).dimming(reduceMotion: false))
    }

    /// Two stations far apart on Taiwan's map with its weather: the map's
    /// weather is the day's, and a typhoon blowing marks the stations it
    /// covers.
    func testTheMapShowsTodaysWeatherAndTheTyphoonsStations() throws {
        func world(day: Int64, seed: UInt32) throws -> GameWorld {
            var world = GameWorld(
                bounds: try WorldBounds(width: 1_048_576, height: 1_048_576), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
                clock: GameClock(now: GameTime(seconds: day * GameTime.secondsPerDay + 3_600))
            )
            try world.buildStation(named: "West", at: PlanPoint(x: 100_000, y: 524_288))
            try world.buildStation(named: "East", at: PlanPoint(x: 950_000, y: 524_288))
            world.setDisruptions(Disruptions(level: .standard, country: "TW", seed: seed))
            return world
        }
        var off = try world(day: 200, seed: 1)
        off.setDisruptions(nil)
        XCTAssertEqual(MapWeather(world: off), .clear)

        var rainy = 0, stormy = 0, typhoons = 0
        for seed in UInt32(1)...3 {
            for day in Int64(180)..<360 {
                let world = try world(day: day, seed: seed)
                let weather = MapWeather(world: world)
                let blowing = world.typhoons(onDay: day).filter { $0.isActive(onDay: day) }
                if blowing.isEmpty {
                    XCTAssertTrue(weather.typhoonStations.isEmpty)
                    switch world.weather(onDay: day) {
                    case .clear: XCTAssertEqual(weather.sky, .clear)
                    case .rain: XCTAssertEqual(weather.sky, .rain); rainy += 1
                    case .thunderstorm: XCTAssertEqual(weather.sky, .thunderstorm); stormy += 1
                    }
                } else {
                    XCTAssertEqual(weather.sky, .typhoon, "a typhoon first, whatever the weather")
                    typhoons += 1
                    let covered = world.stations.filter { station in blowing.contains { $0.covers(station.point) } }.map(\.id)
                    XCTAssertEqual(weather.typhoonStations, Set(covered))
                }
            }
        }
        XCTAssertGreaterThan(rainy, 0)
        XCTAssertGreaterThan(stormy, 0)
        XCTAssertGreaterThan(typhoons, 0)
    }
}
