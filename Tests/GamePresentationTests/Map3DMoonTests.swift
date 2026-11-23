import GameCore
import XCTest
@testable import GamePresentation

/// Decision 942: the moon's place and phase (``Map3DSunPath/moonPosition(julianDay:latitude:longitude:)``)
/// against the published almanacs, and the game's moon
/// (``Map3DSunPath/moonPosition(date:place:)``) through its months.
final class Map3DMoonTests: XCTestCase {
    private let taipeiLatitude = 25.05, taipeiLongitude = 121.5

    private func moon(_ year: Int, _ month: Int, _ day: Int, _ hour: Double) -> Map3DSunPath.Moon {
        Map3DSunPath.moonPosition(julianDay: Map3DSunPath.julianDayTaiwan(year: year, month: month, day: day, hour: hour),
                                  latitude: taipeiLatitude, longitude: taipeiLongitude)
    }

    /// USNO's phases of the moon for 2026 (UTC, here on Taiwan's clock):
    /// full 3 January 10:03 and 3 March 11:38, new 18 January 19:52 and
    /// 17 February 12:01, first quarter 26 January 04:47. Within 0.2 % of
    /// the disc lit (some 10 minutes of the moon's month round full and
    /// new), the quarter within 1 %.
    func testThePhasesFallOnTheAlmanacsDates() {
        let fulls = [moon(2026, 1, 3, 18 + 3 / 60.0), moon(2026, 3, 3, 19 + 38 / 60.0)]
        for full in fulls {
            XCTAssertGreaterThan(full.illuminated, 0.998)
            XCTAssertLessThan(full.phaseAngle, 5.5, "the moon's latitude keeps it a few degrees off")
        }
        for new in [moon(2026, 1, 19, 3 + 52 / 60.0), moon(2026, 2, 17, 20 + 1 / 60.0)] {
            XCTAssertLessThan(new.illuminated, 0.002)
        }
        let quarter = moon(2026, 1, 26, 12 + 47 / 60.0)
        XCTAssertEqual(quarter.illuminated, 0.5, accuracy: 0.01)
        XCTAssertTrue(quarter.waxing)
        XCTAssertEqual(quarter.elongation, 90, accuracy: 0.05)
        // A day either side of full, the moon is a few per cent short.
        XCTAssertLessThan(moon(2026, 1, 2, 18).illuminated, 0.99)
        XCTAssertFalse(moon(2026, 1, 5, 18).waxing)
    }

    /// The moon's place in Taipei's sky against the JPL-based almanac
    /// (PyEphem, topocentric, no refraction), within 0.1° up and round.
    func testThePlaceInTaipeisSkyIsTheAlmanacs() {
        let cases: [(Map3DSunPath.Moon, Double, Double)] = [
            (moon(2026, 1, 3, 18 + 3 / 60.0), 10.66, 65.39),
            (moon(2026, 1, 26, 12 + 47 / 60.0), 20.90, 79.95),
            (moon(2026, 6, 15, 20), -9.40, 306.24),
        ]
        for (position, elevation, azimuth) in cases {
            XCTAssertEqual(position.elevation, elevation, accuracy: 0.1)
            XCTAssertEqual(position.azimuth, azimuth, accuracy: 0.1)
        }
    }

    /// The full moon of 3 January 2026 rises over Taipei at 17:03 in the
    /// east-north-east (59.8°) and sets at 07:25 next morning in the
    /// west-north-west (298.4°): the almanac's times on USNO's rule (the
    /// upper edge on the horizon with 34′ of refraction, PyEphem with no
    /// air pressure and a horizon of -0:34; -0.833° for the centre), within
    /// 3 minutes and 0.5°.
    func testTheFullMoonRisesAndSetsWhereTheAlmanacSays() throws {
        func crossing(from start: Double, rising: Bool) -> (hour: Double, azimuth: Double)? {
            var hour = start
            while hour < start + 24 {
                let a = moon(2026, 1, 3, hour).elevation - Map3DSunPath.horizon
                let b = moon(2026, 1, 3, hour + 1 / 60.0).elevation - Map3DSunPath.horizon
                if rising ? (a < 0 && b >= 0) : (a > 0 && b <= 0) { return (hour, moon(2026, 1, 3, hour).azimuth) }
                hour += 1 / 60.0
            }
            return nil
        }
        let rise = try XCTUnwrap(crossing(from: 12, rising: true))
        XCTAssertEqual(rise.hour, 17 + 3.1 / 60, accuracy: 3 / 60.0)
        XCTAssertEqual(rise.azimuth, 59.84, accuracy: 0.5)
        let set = try XCTUnwrap(crossing(from: 24, rising: false))
        XCTAssertEqual(set.hour, 24 + 7 + 25.1 / 60, accuracy: 3 / 60.0)
        XCTAssertEqual(set.azimuth, 298.35, accuracy: 0.5)
    }

    /// The game's moon: new and full some 14.8 days apart, round the
    /// month in 29.5 days, waxing in between, and never a step from one
    /// minute to the next (the motion rule): past midnight, the month's
    /// end and the year's end too.
    func testTheGamesMoonRunsOnWithoutAStep() {
        let place = Map3DSunPlace.taipei
        func at(_ minute: Int64) -> Map3DSunPath.Moon { Map3DSunPath.moonPosition(date: GameTime(seconds: minute * 60), place: place) }
        var previous = at(0)
        var news: [Int64] = [], fulls: [Int64] = []
        var minute: Int64 = 10
        let end = Int64(FinancePeriod.year.days + 40) * 1_440
        while minute < end {
            let now = at(minute)
            // Ten minutes: at most some 0.1° of the moon's own motion and
            // 2.5° of the sky's turn.
            let a = Map3DLighting.direction(elevation: previous.elevation, azimuth: previous.azimuth)
            let b = Map3DLighting.direction(elevation: now.elevation, azimuth: now.azimuth)
            XCTAssertGreaterThan(a.dot(b), cosf(3 * .pi / 180), "minute \(minute)")
            XCTAssertEqual(now.illuminated, previous.illuminated, accuracy: 0.003, "minute \(minute)")
            if previous.elongation > 300 && now.elongation < 60 { news.append(minute) }
            if previous.elongation < 180 && now.elongation >= 180 { fulls.append(minute) }
            previous = now
            minute += 10
        }
        XCTAssertGreaterThanOrEqual(news.count, 12)
        for (new, next) in zip(news, news.dropFirst()) {
            XCTAssertEqual(Double(next - new) / 1_440, 29.53, accuracy: 0.6)
        }
        for full in fulls {
            let new = news.last { $0 < full }
            if let new { XCTAssertEqual(Double(full - new) / 1_440, 14.77, accuracy: 1.5) }
        }
    }

    /// At full the game's moon stands across the sky from the drawn sun,
    /// at new beside it, and its lit side faces the sun.
    func testTheGamesMoonStandsWhereItsPhaseSays() {
        let place = Map3DSunPlace.taipei
        for day in stride(from: Int64(0), to: 360, by: 1) {
            let time = GameTime(seconds: (day * 1_440 + 13 * 60) * 60)
            let moon = Map3DSunPath.moonPosition(date: time, place: place)
            let lighting = Map3DLighting(at: time, place: place)
            let towardMoon = Map3DLighting.direction(elevation: moon.elevation, azimuth: moon.azimuth)
            // The angle from the drawn sun to the moon is the phase's,
            // within 2° (the drawn sun steps a day at the game's months).
            let apart = acos(Double(min(max(towardMoon.dot(lighting.skySun), -1), 1))) * 180 / .pi
            XCTAssertEqual(apart, 180 - moon.phaseAngle, accuracy: 2.0, "day \(day)")
            XCTAssertEqual(lighting.moonLit, moon.illuminated.floatValue, accuracy: 0.0001)
        }
    }
}

private extension Double {
    var floatValue: Float { Float(self) }
}
