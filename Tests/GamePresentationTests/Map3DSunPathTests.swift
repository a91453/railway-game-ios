import GameCore
import XCTest
@testable import GamePresentation

/// Decision 813: the sun over the 3D map's place on the game's day.
///
/// The expected sunrises and sunsets are published figures, a few times
/// written down by hand to check the formula against, not a table the game
/// ships: Taipei's and Rovaniemi's and Utsjoki's from timeanddate.com (2026,
/// read 2026-11-17), Hong Kong's from the Hong Kong Observatory's open data
/// (`dataType=SRS`, 2026, for the Observatory at Tsim Sha Tsui).
final class Map3DSunPathTests: XCTestCase {
    private let taipei = Map3DSunPlace(latitude: 25.05, longitude: 121.53, standardOffset: 480)
    private let hongKong = Map3DSunPlace(latitude: 22.302, longitude: 114.174, standardOffset: 480)
    private let rovaniemi = Map3DSunPlace(latitude: 66.50, longitude: 25.717, standardOffset: 120, summerOffset: 180)
    private let utsjoki = Map3DSunPlace(latitude: 69.908, longitude: 27.027, standardOffset: 120, summerOffset: 180)

    /// 21 June and 21 December, days of the real year.
    private let june21 = 172, december21 = 355

    private func minutes(_ text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        return parts[0] * 60 + parts[1]
    }

    private func assertTimes(_ place: Map3DSunPlace, day: Int, rise: String, set: String, within: Double = 2,
                             file: StaticString = #filePath, line: UInt = #line) {
        let sun = Map3DSunPath.day(day, at: place)
        guard let sunrise = sun.sunrise, let sunset = sun.sunset else {
            return XCTFail("no sunrise or sunset on day \(day)", file: file, line: line)
        }
        XCTAssertEqual(sunrise, minutes(rise), accuracy: within, "sunrise on day \(day)", file: file, line: line)
        XCTAssertEqual(sunset, minutes(set), accuracy: within, "sunset on day \(day)", file: file, line: line)
    }

    func testTaipeiAndHongKongSunrisesAndSunsetsAreThePublishedOnes() {
        assertTimes(taipei, day: june21, rise: "05:04", set: "18:46")
        assertTimes(taipei, day: december21, rise: "06:34", set: "17:09")
        assertTimes(hongKong, day: june21, rise: "05:40", set: "19:10")
        assertTimes(hongKong, day: december21, rise: "06:58", set: "17:44")
    }

    func testRovaniemiHasNoSunsetInJuneAndTwoHoursOfLowSunInDecember() {
        let june = Map3DSunPath.day(june21, at: rovaniemi)
        XCTAssertTrue(june.upAllDay)
        // On the Arctic Circle the sun clears the horizon at the winter
        // solstice only just, from 11:07 to 13:22 (timeanddate.com), its
        // highest half a degree.
        assertTimes(rovaniemi, day: december21, rise: "11:07", set: "13:22", within: 4)
        let december = Map3DSunPath.day(december21, at: rovaniemi)
        XCTAssertEqual(december.highest, 0.1, accuracy: 0.3)
        XCTAssertEqual(december.noon, minutes("12:15"), accuracy: 2)
    }

    func testFurtherNorthTheSunDoesNotRiseAllDay() {
        // Utsjoki, Finland's northernmost village: "Down, doesn't rise" on
        // 1 and 21 December 2026.
        for day in [335, december21] {
            let sun = Map3DSunPath.day(day, at: utsjoki)
            XCTAssertNil(sun.sunrise)
            XCTAssertNil(sun.sunset)
            XCTAssertTrue(sun.downAllDay)
        }
        XCTAssertEqual(Map3DSunPath.day(december21, at: utsjoki).highest, -3.2, accuracy: 0.5)
    }

    func testTheSunsPositionIsTheIndependentReferenceSample() {
        // sun.mjs's own check: NREL/TP-560-34302 table A5.1, Golden,
        // Colorado, 17 October 2003 12:30:30 UTC-7 (azimuth 194.34°,
        // zenith 50.11°); the NOAA formula is good to a tenth of a degree.
        let jd = 2_452_930.312847
        let position = Map3DSunPath.position(julianDay: jd, latitude: 39.742476, longitude: -105.1786)
        XCTAssertEqual(position.azimuth, 194.34024, accuracy: 0.1)
        XCTAssertEqual(90 - position.elevation, 50.11162, accuracy: 0.1)
    }

    func testTheGameDayIsTheRealDayOfTheSameMonthAndDate() {
        XCTAssertEqual(Map3DSunPath.realDayOfYear(gameDay: 0), 1)
        XCTAssertEqual(Map3DSunPath.realDayOfYear(gameDay: 5 * 30 + 20), june21)
        XCTAssertEqual(Map3DSunPath.realDayOfYear(gameDay: 11 * 30 + 20), december21)
        XCTAssertEqual(Map3DSunPath.realDayOfYear(gameDay: 360 + 11 * 30 + 20), december21)
        // The game's 30 February is the real 28th.
        XCTAssertEqual(Map3DSunPath.realDayOfYear(gameDay: 30 + 29), 59)
        // The game's December has 30 days.
        XCTAssertEqual(Map3DSunPath.realDayOfYear(gameDay: 359), 364)
    }

    func testTheMapsPlaceAndClockComeFromItsAnchor() {
        let hk = Map3DSunPlace(anchor: GeoAnchor(latitudeDegrees: 22.315901, longitudeDegrees: 113.936517)!)
        XCTAssertEqual(hk.utcOffsetMinutes(onDay: december21), 480)
        let finland = Map3DSunPlace(anchor: GeoAnchor(latitudeDegrees: 66.498045, longitudeDegrees: 25.705274)!)
        XCTAssertEqual(finland.utcOffsetMinutes(onDay: december21), 120)
        XCTAssertEqual(finland.utcOffsetMinutes(onDay: june21), 180)
        let kinmen = Map3DSunPlace(anchor: GeoAnchor(latitudeDegrees: 24.43, longitudeDegrees: 118.32)!)
        XCTAssertEqual(kinmen.utcOffsetMinutes(onDay: june21), 480)
        XCTAssertEqual(Map3DSunPlace.taipei.standardOffset, 480)
    }

    // MARK: The light

    private func light(_ place: Map3DSunPlace, gameDay: Int64, minute: Double) -> Map3DLighting {
        Map3DLighting(at: GameTime(seconds: gameDay * GameTime.secondsPerDay + Int64(minute * 60)), place: place)
    }

    private let gameJune21: Int64 = 5 * 30 + 20, gameDecember21: Int64 = 11 * 30 + 20

    func testTaipeisDuskComesLaterInSummer() {
        let summer = light(taipei, gameDay: gameJune21, minute: minutes("18:15"))
        let winter = light(taipei, gameDay: gameDecember21, minute: minutes("18:15"))
        // An hour after December's sunset it is nearly dark; half an hour
        // before June's it is still day.
        XCTAssertLessThan(summer.night, 0.5)
        XCTAssertGreaterThan(winter.night, 0.75)
        XCTAssertEqual(light(taipei, gameDay: gameDecember21, minute: minutes("19:30")).night, 1, accuracy: 0.01)
        XCTAssertLessThan(light(taipei, gameDay: gameDecember21, minute: 12 * 60).night, 0.01)
        XCTAssertEqual(light(taipei, gameDay: gameJune21, minute: 0).night, 1, accuracy: 0.01)
    }

    func testRovaniemisDecemberNoonIsOnlyABlueGlow() {
        var darkest: Float = 0, brightest: Float = 1
        for minute in stride(from: 0.0, to: 1_440, by: 10) {
            let lit = light(rovaniemi, gameDay: gameDecember21, minute: minute)
            brightest = min(brightest, lit.night)
            darkest = max(darkest, lit.night)
            // The sun's disc stays on the horizon at the most.
            XCTAssertLessThan(lit.skySun.y, 0.02, "minute \(minute)")
        }
        XCTAssertEqual(darkest, 1, accuracy: 0.01)
        // At its lightest, at noon, the night is not over: the polar
        // noon's twilight, the street lights still on.
        let noon = light(rovaniemi, gameDay: gameDecember21, minute: minutes("12:15"))
        XCTAssertEqual(noon.night, brightest, accuracy: 0.001)
        XCTAssertEqual(noon.night, Map3DLighting.polarNoon.night, accuracy: 0.02)
        XCTAssertGreaterThan(noon.lights, 0.3)
        // Its zenith, the snow's light from the sky and from the ground are
        // blue, more blue than red.
        XCTAssertGreaterThan(Int(noon.zenith.blue), Int(noon.zenith.red) + 40)
        XCTAssertGreaterThan(noon.skyLight.z, noon.skyLight.x)
        XCTAssertGreaterThan(noon.groundLight.z, noon.groundLight.x)
        // By the evening it is night.
        XCTAssertEqual(light(rovaniemi, gameDay: gameDecember21, minute: minutes("20:15")).night, 1, accuracy: 0.01)
        // Further north, where the sun does not rise at all, the noon is
        // the same twilight, a little darker.
        let polar = light(utsjoki, gameDay: gameDecember21, minute: minutes("12:10"))
        XCTAssertGreaterThanOrEqual(polar.night, noon.night)
        XCTAssertLessThan(polar.night, 0.5)
        // Taipei's and Hong Kong's winter noons never take any of it.
        XCTAssertEqual(Map3DLighting.polarNoonShare(elevation: 41.5, highest: 41.5), 0)
        XCTAssertEqual(Map3DLighting.polarNoonShare(elevation: 0.06, highest: 0.06), 1, accuracy: 0.001)
        // And in June the night never comes.
        for minute in stride(from: 0.0, to: 1_440, by: 30) {
            XCTAssertLessThan(light(rovaniemi, gameDay: gameJune21, minute: minute).night, 0.75, "minute \(minute)")
        }
    }

    private func step(_ a: PopTravel.RGB, _ b: PopTravel.RGB) -> Int {
        let red = abs(Int(a.red) - Int(b.red)), green = abs(Int(a.green) - Int(b.green))
        return red + green + abs(Int(a.blue) - Int(b.blue))
    }

    func testTheLightNeverStepsFromOneMinuteToTheNext() {
        for place in [taipei, hongKong, rovaniemi, utsjoki] {
            for gameDay: Int64 in [0, 2 * 30 + 19, gameJune21, 8 * 30 + 22, gameDecember21] {
                var last = light(place, gameDay: gameDay, minute: 0)
                for minute in stride(from: 1.0, through: 1_440, by: 1) {
                    let lit = light(place, gameDay: gameDay, minute: minute)
                    let where_ = "\(place.latitude)° day \(gameDay) minute \(minute)"
                    XCTAssertLessThan(abs(lit.night - last.night), 0.03, where_)
                    XCTAssertLessThan(abs(lit.sunStrength - last.sunStrength), 0.06, where_)
                    for (a, b) in [(lit.sky, last.sky), (lit.zenith, last.zenith), (lit.ground, last.ground)] {
                        XCTAssertLessThanOrEqual(step(a, b), 12, where_)
                    }
                    XCTAssertGreaterThan(lit.sunDirection.dot(last.sunDirection), 0.995, where_)
                    last = lit
                }
            }
        }
    }

    func testTheSunStandsWhereItDoes() {
        // Taipei's December noon: due south, 41.5° high, so shadows are
        // longer than in the summer; the light never lower than about 5°.
        let noon = light(taipei, gameDay: gameDecember21, minute: minutes("11:51"))
        XCTAssertEqual(asin(Double(noon.skySun.y)) * 180 / .pi, 41.5, accuracy: 0.3)
        XCTAssertGreaterThan(noon.skySun.z, 0.7)
        XCTAssertEqual(noon.skySun.x, 0, accuracy: 0.02)
        XCTAssertEqual(noon.sunDirection.dot(noon.skySun), 1, accuracy: 0.0001)
        // Sunrise in June, in the north-east; the moon across from the sun.
        let morning = light(taipei, gameDay: gameJune21, minute: minutes("05:30"))
        XCTAssertGreaterThan(morning.skySun.x, 0.8)
        XCTAssertLessThan(morning.skySun.z, -0.3)
        XCTAssertEqual(morning.skyMoon.x, -morning.skySun.x, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(morning.sunDirection.y, Float(sin(5.0 * .pi / 180)))
        // The sky draws them there.
        let sky = Map3DSky(noon)
        XCTAssertEqual(sky.sun, noon.skySun)
        XCTAssertGreaterThan(sky.sunShown, 0.99)
        XCTAssertEqual(Map3DSky(light(taipei, gameDay: gameDecember21, minute: 0)).sunShown, 0)
    }

    func testTheOldFixedDayIsUnchanged() {
        // The light by the minute alone keeps its 06:00 and 18:00 sun.
        let old = Map3DLighting(minute: 12 * 60)
        let noon = Map3DPoint(cosf(.pi / 2), 1.15, 0.45).normalized ?? .up
        XCTAssertEqual(old.sunDirection.dot(noon), 1, accuracy: 0.000001)
        XCTAssertEqual(Map3DLighting(minute: 12 * 60).skySun, Map3DSky.path(at: 0.5, rise: 1.15))
        XCTAssertEqual(Map3DLighting(minute: 0).night, 1)
    }
}
