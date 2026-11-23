import GameCore
import XCTest
@testable import GamePresentation

/// Decision 347: the sky drawn behind the native 3D map.
final class Map3DSkyTests: XCTestCase {
    private func lighting(_ hour: Double, _ weather: Map3DWeather = .clear) -> Map3DLighting {
        var lighting = Map3DLighting(minute: hour * 60)
        lighting.weather = weather
        return lighting
    }

    private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ within: Float = 0.002) -> Bool {
        abs(a.x - b.x) <= within && abs(a.y - b.y) <= within && abs(a.z - b.z) <= within
    }

    func testTheHorizonIsTheFogsColourAndStraightUpTheZenith() {
        for hour in [3.0, 9, 12, 18.5, 22] {
            let lit = lighting(hour), sky = Map3DSky(lit)
            XCTAssertEqual(sky.horizon, lit.fogColour)
            // Away from the sun and the moon, low on the horizon and below
            // it the sky is the fog's colour, so the far ground fades into it.
            let light = sky.sunShown > 0 ? sky.sun : sky.moon
            let away = Map3DPoint(-light.x, 0, -light.z + 0.01)
            XCTAssertTrue(close(sky.colour(toward: away), lit.fogColour), "hour \(hour)")
            XCTAssertTrue(close(sky.colour(toward: Map3DPoint(0, -1, 0.3)), lit.fogColour), "hour \(hour)")
            if sky.stars == 0 && sky.sun.y < 0.5 {
                XCTAssertTrue(close(sky.colour(toward: .up), sky.zenith, 0.01), "hour \(hour)")
            }
        }
    }

    func testTheZenithIsBrightBlueAtNoonAndDarkAtMidnight() {
        let noon = Map3DSky(lighting(12)).zenith, midnight = Map3DSky(lighting(0)).zenith
        XCTAssertGreaterThan(noon.z, noon.x, "blue by day")
        XCTAssertGreaterThan(noon.sum(), midnight.sum() * 3)
    }

    func testTheSunShowsByDayAndTheMoonAndStarsOnAClearNight() {
        let noon = Map3DSky(lighting(12))
        XCTAssertEqual(noon.sunShown, 1)
        XCTAssertEqual(noon.moonShown, 0)
        XCTAssertEqual(noon.stars, 0)
        XCTAssertGreaterThan(noon.sun.y, 0.8)
        // Its disc is near white, brighter than the sky beside it.
        XCTAssertGreaterThan(noon.colour(toward: noon.sun).sum(), 2.8)

        let midnight = Map3DSky(lighting(0))
        XCTAssertEqual(midnight.sunShown, 0)
        XCTAssertGreaterThan(midnight.moonShown, 0.9)
        XCTAssertGreaterThan(midnight.moon.y, 0.8, "high at midnight")
        XCTAssertGreaterThan(midnight.stars, 0.9)
        XCTAssertGreaterThan(midnight.colour(toward: midnight.moon).sum(), 2.5)

        // The moon is up in the east in the evening and low in the west
        // before dawn.
        let evening = Map3DSky(lighting(20)), dawn = Map3DSky(lighting(5))
        XCTAssertGreaterThan(evening.moon.x, 0)
        XCTAssertLessThan(dawn.moon.x, 0)
    }

    func testRainHidesTheSunTheMoonAndTheStars() {
        let rainyNoon = Map3DSky(lighting(12, .rain)), rainyNight = Map3DSky(lighting(0, .rain))
        XCTAssertEqual(rainyNoon.sunShown, 0)
        XCTAssertEqual(rainyNight.moonShown, 0)
        XCTAssertEqual(rainyNight.stars, 0)
        XCTAssertLessThan(rainyNoon.colour(toward: rainyNoon.sun).sum(), 2.5)
        // The rain's grey reaches the zenith.
        XCTAssertNotEqual(rainyNoon.zenith, Map3DSky(lighting(12)).zenith)
    }

    func testStarsAreScatteredAndNoneLowDown() {
        var high = 0, low = 0, total = 0
        for i in 0..<200 {
            for j in 0..<200 {
                let x = Float(i) / 100 - 1, z = Float(j) / 100 - 1
                total += 1
                high += Map3DSky.star(Map3DPoint(x, 0.8, z).normalized!) > 0 ? 1 : 0
                // Within some 5° of the horizon.
                let around = Float(i * 200 + j) * 0.0001, up = Float(j) / 2_300
                low += Map3DSky.star(Map3DPoint(cosf(around), up, sinf(around))) > 0 ? 1 : 0
            }
        }
        XCTAssertGreaterThan(high, 0)
        XCTAssertLessThan(Double(high) / Double(total), 0.02)
        XCTAssertEqual(low, 0)
        for value in [Map3DSky.hash(3, 7), Map3DSky.hash(-120, 45), Map3DSky.hash(0, 0)] {
            XCTAssertTrue((0..<1).contains(value))
        }
    }

    func testTheShaderGetsElevenRowsOfFour() {
        let camera = Map3DCamera(target: .zero, distance: 300, heading: 0.4)
        let floats = Map3DSky(lighting(21)).floats(camera: camera)
        XCTAssertEqual(floats.count, 44)
        XCTAssertEqual(Array(floats[36..<40]), [0, 0, 0, 0])
        var lit = lighting(23)
        lit.aurora = 0.8
        XCTAssertEqual(Array(Map3DSky(lit).floats(camera: camera, seconds: 12)[36..<40]), [Map3DSky(lit).aurora, 12, 0, 0])
        // Decision 942: the way from the moon toward the sun and its lit share.
        let sky = Map3DSky(lit)
        XCTAssertEqual(Array(sky.floats(camera: camera).suffix(4)), [sky.moonSunward.x, sky.moonSunward.y, sky.moonSunward.z, sky.moonLit])
        // The camera's way is a unit vector looking down at the target.
        let look = Map3DPoint(floats[0], floats[1], floats[2])
        XCTAssertEqual(look.length, 1, accuracy: 0.001)
        XCTAssertLessThan(look.y, 0)
        let toTarget = (camera.target - camera.eye).normalized!
        XCTAssertEqual(look.dot(toTarget), 1, accuracy: 0.001)
    }

    /// The way the shader turns a point of the screen into a way into the
    /// sky lands on that point through the camera's own projection.
    func testTheScreensPointsLookWhereTheCameraDraws() {
        var camera = Map3DCamera(target: Map3DPoint(200, 0, -50), distance: 260, heading: 2.1, viewport: (1_024, 768))
        camera.lens = 50 * .pi / 180
        let f = Map3DSky(lighting(21)).floats(camera: camera)
        let look = Map3DPoint(f[0], f[1], f[2]), side = Map3DPoint(f[4], f[5], f[6]), up = Map3DPoint(f[8], f[9], f[10])
        for (x, y) in [(Float(0.5), Float(0.3)), (-0.9, 0.95), (0.2, -0.7)] {
            let way = look + side * (x * f[12]) + up * (y * f[13])
            let seen = camera.viewProjection.project(camera.eye + way * 500)!
            XCTAssertEqual(seen.x, x, accuracy: 0.001)
            XCTAssertEqual(seen.y, y, accuracy: 0.001)
        }
    }

    // MARK: - The aurora (decision 813's later part, AURORA)

    private let rovaniemi = Map3DSunPlace(latitude: 66.50, longitude: 25.717, standardOffset: 120, summerOffset: 180)

    private func time(day: Int64, hour: Double) -> GameTime {
        GameTime(seconds: day * GameTime.secondsPerDay + Int64(hour * 3600))
    }

    /// The share of nights is the Finnish Meteorological Institute's: one
    /// night a month on the south coast, every other night over Rovaniemi,
    /// three of four in the far north; never in Taiwan or Hong Kong.
    func testTheAuroraComesOnTheNightsTheFinnishFiguresGive() {
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 25.05), 0)
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 22.3), 0)
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 58), 0)
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 60), 0.033, accuracy: 0.001)
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 66.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 69), 0.75, accuracy: 0.001)
        XCTAssertEqual(Map3DLighting.auroraNights(latitude: 75), 0.75, accuracy: 0.001)
        // Over a year of nights at Rovaniemi, about every other one.
        let nights = (0..<720 as Range<Int64>).filter { Map3DLighting.aurora(at: time(day: $0, hour: 23.5), latitude: 66.5) > 0 }.count
        XCTAssertEqual(Double(nights) / 720, 0.5, accuracy: 0.06)
        let taipei = (0..<360 as Range<Int64>).filter { Map3DLighting.aurora(at: time(day: $0, hour: 23.5), latitude: 25.05) > 0 }
        XCTAssertTrue(taipei.isEmpty)
    }

    /// One night is one draw: the same before and after midnight, the same
    /// every time it is asked; out in the late evening, gone by day.
    func testANightsAuroraLastsTheNightAndNotTheDay() throws {
        let night = try XCTUnwrap((0..<60 as Range<Int64>).first { Map3DLighting.aurora(at: time(day: $0, hour: 23.5), latitude: 66.5) > 0 })
        let evening = Map3DLighting.aurora(at: time(day: night, hour: 23.5), latitude: 66.5)
        XCTAssertGreaterThanOrEqual(evening, 0.55)
        XCTAssertEqual(Map3DLighting.aurora(at: time(day: night + 1, hour: 1), latitude: 66.5), evening, accuracy: 0.001)
        XCTAssertEqual(Map3DLighting.aurora(at: time(day: night, hour: 23.5), latitude: 66.5), evening)
        for hour in [8.0, 12, 15, 18] {
            XCTAssertEqual(Map3DLighting.aurora(at: time(day: night, hour: hour), latitude: 66.5), 0)
        }
        XCTAssertEqual(Map3DLighting.aurora(at: time(day: night + 1, hour: 5), latitude: 66.5), 0)
        XCTAssertLessThan(Map3DLighting.aurora(at: time(day: night, hour: 20), latitude: 66.5), evening)
    }

    /// The light over Rovaniemi carries it; the sky shows it in the north
    /// on a clear dark night, not in the south, not by day, not in rain.
    func testTheSkyShowsTheAuroraInTheNorthOnAClearNight() throws {
        let gameDecember: Int64 = 11 * 30
        let night = try XCTUnwrap((gameDecember..<gameDecember + 30).first { Map3DLighting.aurora(at: time(day: $0, hour: 23.5), latitude: 66.5) > 0 })
        let dark = Map3DLighting(at: time(day: night, hour: 23.5), place: rovaniemi)
        XCTAssertGreaterThan(dark.aurora, 0)
        let sky = Map3DSky(dark)
        XCTAssertGreaterThan(sky.aurora, 0.5)
        let north = Map3DPoint(0, 0.45, -1).normalized!, south = Map3DPoint(0, 0.45, 1).normalized!
        let without = Map3DSky(Map3DLighting(at: time(day: night, hour: 23.5), place: .taipei))
        XCTAssertEqual(without.aurora, 0)
        let green = sky.colour(toward: north) - sky.colour(toward: south)
        XCTAssertGreaterThan(green.y, 0.1)
        XCTAssertGreaterThan(green.y, green.x)
        // Under the foot of the curtain and below the horizon: nothing.
        XCTAssertEqual(Map3DSky.auroraLight(Map3DPoint(0, 0.05, -1).normalized!, seconds: 0), .zero)
        XCTAssertEqual(Map3DSky.auroraLight(Map3DPoint(0, -0.3, -1).normalized!, seconds: 0), .zero)
        XCTAssertEqual(Map3DSky.auroraLight(south, seconds: 0), .zero)
        // It moves with the seconds (none pass under Reduce Motion).
        XCTAssertNotEqual(Map3DSky.auroraLight(north, seconds: 0), Map3DSky.auroraLight(north, seconds: 20))
        // Rain hides it; by day there is none.
        var rainy = dark
        rainy.weather = .rain
        XCTAssertEqual(Map3DSky(rainy).aurora, 0)
        XCTAssertEqual(Map3DSky(Map3DLighting(at: time(day: night, hour: 12), place: rovaniemi)).aurora, 0)
    }
}
